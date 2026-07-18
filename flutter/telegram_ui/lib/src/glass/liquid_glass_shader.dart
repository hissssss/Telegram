// Shader loading and the epsilon-diffed uniform packer for the liquid-glass
// fragment shader.
//
// Port of `java/org/telegram/ui/Components/blur3/LiquidGlassEffect.java`:
// the center/half-size computation (lines 50-54), the vertical-only
// radius-pair rescale (lines 56-65), the 0.1f-per-float dirty check with an
// exact int compare on the color (lines 67-82), the component-wise color
// premultiply (lines 85-88), and the (RB, RT, LB, LT) `radius` uniform
// packing (line 93) — plus the draw-time thickness clamp of
// `java/org/telegram/ui/Components/blur3/drawable/BlurredBackgroundDrawableRenderNode.java`
// (lines 115-118):
// `max(min(liquidThickness <= 0 ? dp(11) : liquidThickness, min(w, h) / 5), 1)`.
//
// All packer inputs are *physical* pixels (the shader samples the backdrop
// texture in pixel space); [LiquidGlassUniforms.update] takes a
// `devicePixelRatio` only to resolve the dp(11) default thickness. Float slot
// indices come from the generated `tokens/liquid_glass_uniforms.g.dart`;
// expected values are pre-verified by the Ring-0 fixture tables of
// `flutter/tool/gen_uniform_fixtures.py`.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier, visibleForTesting;

import '../foundation/dimens.dart';
import '../tokens/glass_metrics.g.dart';
import '../tokens/liquid_glass_uniforms.g.dart';
import 'geometry.dart';

/// Asset key of the liquid-glass fragment shader inside this package's own
/// bundle (tests, example app running from the package root).
const String kLiquidGlassShaderAsset = 'shaders/liquid_glass.frag';

/// Asset key of the shader when `telegram_ui` is consumed as a dependency —
/// package assets get the `packages/<name>/` prefix.
const String kLiquidGlassShaderPackageAsset = 'packages/telegram_ui/shaders/liquid_glass.frag';

/// Per-float change-detection epsilon of `LiquidGlassEffect.update`
/// (LiquidGlassEffect.java:67-82). A float uniform is only considered changed
/// when it moves by strictly more than this from its last *pushed* value; the
/// tint color is compared exactly as an ARGB int instead.
const double kUniformDirtyEpsilon = 0.1;

/// Loader/cache for this package's fragment programs
/// (ARCHITECTURE.md section 3.5).
///
/// Call [ensureInitialized] once at startup (before any glass surface
/// paints); afterwards [liquidGlassProgram] is a synchronous accessor for the
/// paint path. The Android analog is the one-time
/// `new RuntimeShader(AndroidUtilities.readRes(R.raw.liquid_glass_shader))`
/// of `LiquidGlassEffect`'s constructor (LiquidGlassEffect.java:20-25).
abstract final class TgShaders {
  static ui.FragmentProgram? _liquidGlass;
  static Future<ui.FragmentProgram>? _pending;
  static final ValueNotifier<bool> _initializedNotifier = ValueNotifier<bool>(false);

  /// Whether [ensureInitialized] has completed successfully.
  static bool get isInitialized => _liquidGlass != null;

  /// Notifies when [isInitialized] flips — the hook `RenderGlassSurface`
  /// uses to repaint a liquid-requesting surface that had to degrade to
  /// frosted because the program had not loaded yet (a late
  /// [ensureInitialized] completion would otherwise leave a static panel
  /// frosted until an unrelated repaint).
  static ValueListenable<bool> get initialized => _initializedNotifier;

  /// The loaded liquid-glass program.
  ///
  /// Throws a [StateError] when [ensureInitialized] has not completed yet —
  /// the paint path must never await.
  static ui.FragmentProgram get liquidGlassProgram {
    final ui.FragmentProgram? program = _liquidGlass;
    if (program == null) {
      throw StateError(
        'TgShaders.liquidGlassProgram read before TgShaders.ensureInitialized() '
        'completed. Await it during app startup.',
      );
    }
    return program;
  }

  /// Loads (once) and returns the liquid-glass [ui.FragmentProgram].
  ///
  /// Tries the unprefixed asset key first, then the `packages/`-prefixed one:
  /// the shader is registered unprefixed inside the package's own bundle but
  /// `packages/telegram_ui/`-prefixed when the package is consumed from an
  /// app. Concurrent callers share one load; a failed load is not cached, so
  /// a later call retries.
  static Future<ui.FragmentProgram> ensureInitialized() {
    final ui.FragmentProgram? program = _liquidGlass;
    if (program != null) {
      return Future<ui.FragmentProgram>.value(program);
    }
    return _pending ??= _load();
  }

  static Future<ui.FragmentProgram> _load() async {
    try {
      ui.FragmentProgram program;
      try {
        program = await ui.FragmentProgram.fromAsset(kLiquidGlassShaderAsset);
      } on Exception {
        program = await ui.FragmentProgram.fromAsset(kLiquidGlassShaderPackageAsset);
      }
      _liquidGlass = program;
      _initializedNotifier.value = true;
      return program;
    } finally {
      _pending = null;
    }
  }

  /// Test hook: forgets any loaded program so initialization paths can be
  /// re-exercised.
  @visibleForTesting
  static void debugReset() {
    _liquidGlass = null;
    _pending = null;
    _initializedNotifier.value = false;
  }
}

/// Epsilon-diffed uniform packer owning one [ui.FragmentShader] instance —
/// the port of `LiquidGlassEffect` (blur3/LiquidGlassEffect.java).
///
/// [update] recomputes the derived uniforms and re-pushes **all** of them
/// when any float moved by more than [kUniformDirtyEpsilon] from its last
/// pushed value (or the tint changed by even one bit) — the Java dirty check
/// is all-or-nothing, and so is this one. When nothing moved, zero
/// `setFloat` calls are made.
///
/// One packer per glass surface; the packer owns [shader] and [dispose]
/// releases it.
class LiquidGlassUniforms {
  /// Wraps [shader]; the packer takes ownership.
  LiquidGlassUniforms(this.shader);

  /// Creates a fresh [ui.FragmentShader] from [program] and wraps it.
  LiquidGlassUniforms.fromProgram(ui.FragmentProgram program) : this(program.fragmentShader());

  /// The owned shader, for handing to `ui.ImageFilter.shader` /
  /// `Paint.shader`.
  final ui.FragmentShader shader;

  /// Last *pushed* values per float slot, the Java instance fields
  /// (LiquidGlassEffect.java:27-37). Doubles as the dirty-check baseline and
  /// the test-visible mirror. Starts all-zero exactly like Java.
  final Float64List _bound = Float64List(kLiquidGlassUniformFloatCount);

  /// Last pushed tint as an ARGB int — compared exactly, never by epsilon
  /// (LiquidGlassEffect.java:81).
  int _boundColor = 0;

  bool _dirty = false;
  int _uniformWrites = 0;
  double _resolvedThickness = 0;

  /// Whether the most recent [update] pushed uniforms (the Java `if` at
  /// LiquidGlassEffect.java:67-82 taken). `false` before any update.
  bool get dirty => _dirty;

  /// Total number of `shader.setFloat` calls made over this packer's
  /// lifetime. A push costs [kLiquidGlassUniformFloatCount] writes, minus the
  /// two `u_size` slots when `engineSetsSize` is true; a clean [update] costs
  /// zero.
  int get uniformWrites => _uniformWrites;

  /// The clamped thickness (physical px) computed by the most recent
  /// [update] — the value bound to `u_thickness` when a push happens.
  double get resolvedThickness => _resolvedThickness;

  /// The currently pushed 17-float uniform array in shader slot order.
  ///
  /// Slots [kUniformSizeX]/[kUniformSizeY] mirror the coverage size even when
  /// `engineSetsSize` skipped writing them to the shader (they still
  /// participate in the dirty check, as the Java `resolution` fields do).
  List<double> get boundUniforms => List<double>.unmodifiable(_bound);

  /// Port of `LiquidGlassEffect.update` (lines 39-100) plus the thickness
  /// clamp of `BlurredBackgroundDrawableRenderNode.updateDisplayList`
  /// (lines 115-118). All geometry is in physical pixels.
  ///
  /// * [coverageSize] — the backdrop/filter coverage extent, the Java
  ///   `node.getWidth()/getHeight()` (AGSL `resolution`). With
  ///   [engineSetsSize] true (production `ui.ImageFilter.shader` use) the
  ///   engine binds slots 0-1 itself and the packer skips those two
  ///   `setFloat` calls — but the size still participates in the dirty check
  ///   so a resize re-pushes everything, exactly like Java.
  /// * [panelRect] — the glass rect in coverage coordinates; center and half
  ///   extents are derived per lines 50-54.
  /// * [radii] — raw per-corner radii; the vertical-pair rescale
  ///   ([GlassRadii.rescaleVerticalPairs], lines 56-65) runs *before* the
  ///   dirty comparison, so a raw change the rescale absorbs does not push.
  /// * [thickness] — physical px; `<= 0` resolves to Android's
  ///   `dp(11) = ceil(devicePixelRatio * 11)`. Either way it is clamped to
  ///   `floor(min(w, h) / 5)` (Java int division) with a floor of 1 px.
  /// * [intensity] / [index] — `refract_intensity` / `refract_index`,
  ///   production 0.75 / 1.5.
  /// * [tint] — premultiplied component-wise into
  ///   `u_foreground_color` (lines 85-88); compared exactly as ARGB.
  void update({
    required ui.Size coverageSize,
    required ui.Rect panelRect,
    required GlassRadii radii,
    required ui.Color tint,
    double thickness = 0,
    double intensity = kGlassRefractIntensityDefault,
    double index = kGlassRefractIndex,
    double devicePixelRatio = 1.0,
    bool engineSetsSize = false,
  }) {
    assert(devicePixelRatio > 0);

    // LiquidGlassEffect.java:48-54.
    final double centerX = (panelRect.left + panelRect.right) / 2;
    final double centerY = (panelRect.top + panelRect.bottom) / 2;
    final double width = panelRect.right - panelRect.left;
    final double height = panelRect.bottom - panelRect.top;
    final double halfWidth = width / 2;
    final double halfHeight = height / 2;

    // LiquidGlassEffect.java:56-65 — before the dirty comparison.
    final GlassRadii rescaled = radii.rescaleVerticalPairs(height);

    // BlurredBackgroundDrawableRenderNode.java:115-118.
    final double resolvedThickness = resolveThickness(
      thickness: thickness,
      width: width,
      height: height,
      devicePixelRatio: devicePixelRatio,
    );
    _resolvedThickness = resolvedThickness;

    final int color = tint.toARGB32();

    // LiquidGlassEffect.java:67-82 — one combined verdict, all-or-nothing.
    bool moved(int slot, double value) => (_bound[slot] - value).abs() > kUniformDirtyEpsilon;
    final bool changed = moved(kUniformSizeX, coverageSize.width) ||
        moved(kUniformSizeY, coverageSize.height) ||
        moved(kUniformCenterX, centerX) ||
        moved(kUniformCenterY, centerY) ||
        moved(kUniformHalfSizeX, halfWidth) ||
        moved(kUniformHalfSizeY, halfHeight) ||
        moved(kUniformRadiusLeftTop, rescaled.topLeft) ||
        moved(kUniformRadiusRightTop, rescaled.topRight) ||
        moved(kUniformRadiusRightBottom, rescaled.bottomRight) ||
        moved(kUniformRadiusLeftBottom, rescaled.bottomLeft) ||
        moved(kUniformThickness, resolvedThickness) ||
        moved(kUniformRefractIntensity, intensity) ||
        moved(kUniformRefractIndex, index) ||
        _boundColor != color;
    _dirty = changed;
    if (!changed) {
      return;
    }

    _boundColor = color;

    // LiquidGlassEffect.java:85-88 — component-wise premultiply.
    final double a = ((color >> 24) & 0xFF) / 255.0;
    final double r = ((color >> 16) & 0xFF) / 255.0 * a;
    final double g = ((color >> 8) & 0xFF) / 255.0 * a;
    final double b = (color & 0xFF) / 255.0 * a;

    // Push in the Java setFloatUniform order (lines 90-97; note intensity is
    // pushed before index upstream — kept for doc parity, the order is
    // irrelevant to setFloat). Radius packing is (RB, RT, LB, LT), line 93.
    _write(kUniformSizeX, coverageSize.width, engineSet: engineSetsSize);
    _write(kUniformSizeY, coverageSize.height, engineSet: engineSetsSize);
    _write(kUniformCenterX, centerX);
    _write(kUniformCenterY, centerY);
    _write(kUniformHalfSizeX, halfWidth);
    _write(kUniformHalfSizeY, halfHeight);
    _write(kUniformRadiusRightBottom, rescaled.bottomRight);
    _write(kUniformRadiusRightTop, rescaled.topRight);
    _write(kUniformRadiusLeftBottom, rescaled.bottomLeft);
    _write(kUniformRadiusLeftTop, rescaled.topLeft);
    _write(kUniformThickness, resolvedThickness);
    _write(kUniformRefractIntensity, intensity);
    _write(kUniformRefractIndex, index);
    _write(kUniformForegroundColorR, r);
    _write(kUniformForegroundColorG, g);
    _write(kUniformForegroundColorB, b);
    _write(kUniformForegroundColorA, a);
  }

  void _write(int slot, double value, {bool engineSet = false}) {
    _bound[slot] = value;
    if (engineSet) {
      return; // The engine binds u_size when running as an ImageFilter.
    }
    shader.setFloat(slot, value);
    _uniformWrites++;
  }

  /// The draw-time thickness clamp,
  /// `BlurredBackgroundDrawableRenderNode.java:115-118`:
  /// `max(min(thickness <= 0 ? dp(11) : thickness, min(w, h) / 5), 1)`.
  ///
  /// Everything is physical px. The default is Android's
  /// `dp(11) = ceil(devicePixelRatio * 11)` ([TgDimens.dpPx]); the bounds cap
  /// uses Java *int* division, generalized to `floor(min(w, h) / 5)` (equal
  /// to Java for the integral bounds Android always has).
  static double resolveThickness({
    required double thickness,
    required double width,
    required double height,
    required double devicePixelRatio,
  }) {
    final double base = thickness <= 0
        ? TgDimens.fidelity(devicePixelRatio: devicePixelRatio)
              .dpPx(kGlassThicknessDefaultDp)
              .toDouble()
        : thickness;
    final double boundsCap =
        (math.min(width, height) / kGlassThicknessBoundsDivisor).floorToDouble();
    return math.max(math.min(base, boundsCap), kGlassThicknessMinPx.toDouble());
  }

  /// Releases the owned [shader]. The packer must not be used afterwards.
  void dispose() {
    shader.dispose();
  }
}
