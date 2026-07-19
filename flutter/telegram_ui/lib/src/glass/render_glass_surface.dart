// The glass surface render object — the heart of the liquid-glass port
// (ARCHITECTURE.md section 3.2, Strategy 1).
//
// Ports, from the Android sources under
// `java/org/telegram/ui/Components/blur3/`:
//
// - `drawable/BlurredBackgroundDrawableRenderNode.java` — the paint order
//   shadow -> fill (backdrop effect) -> strokes (`draw`, lines 172-198 and
//   `updateDisplayList`, lines 101-154), the draw-time thickness clamp
//   (lines 115-118), and the "no glass" tint fallbacks (lines 134-142);
// - `DownscaleScrollableNoiseSuppressor.java` — the backdrop pyramid the
//   composed [ui.ImageFilter] chains reproduce: glass = downscale 4x +
//   blur dpf2(6) + saturation x3 (lines 410-412), frosted = the glass output
//   blurred again at downscale 8x + blur dpf2(38.34) (lines 413-415,
//   438-445), radius<->sigma math per lines 256-277 (`foundation/blur_math.dart`);
// - `org/telegram/messenger/utils/RenderNodeEffects.java` — the saturation
//   color-matrix effect (`ColorMatrix.setSaturation(3f)`, lines 28-36),
//   re-derived here from the AOSP `android.graphics.ColorMatrix.setSaturation`
//   formula;
// - `drawable/BlurredBackgroundDrawable.java` — stroke/shadow defaults and the
//   stroke gating on a non-zero stroke color (RenderNode drawable,
//   lines 143-152 of BlurredBackgroundDrawableRenderNode.java).
//
// Tiering (ARCHITECTURE.md section 3.2): the liquid fill pushes a
// [BackdropFilterLayer] whose filter composes the downscale/blur/saturate
// sandwich with `ui.ImageFilter.shader` (the refraction shader composites the
// tint in-shader); coverage is the panel rect inflated by
// `bleed = ceil(8 * thickness * intensity)` px (the shader's ray-length
// constant 8.0) under a plain rect clip — NO rounded clip, the SDF shapes the
// output. The frosted fill pushes blur+saturation under a rounded clip and
// paints the tint as a rounded rect; the flat fill is the tint rect alone.
//
// flutter_tester constraint: `ui.ImageFilter.shader` throws off Impeller.
// [RenderGlassSurface.effectiveTier] therefore refuses to enter the liquid
// branch unless `ui.ImageFilter.isShaderFilterSupported` reports support AND
// [TgShaders.isInitialized] — a liquid request degrades to frosted at paint
// time, mirroring the `GlassSettings` probe ladder one level deeper.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../foundation/blur_math.dart';
import '../tokens/glass_metrics.g.dart';
import 'geometry.dart';
import 'liquid_glass_settings.dart';
import 'liquid_glass_shader.dart';
import 'strategy.dart';
import 'surface_colors.dart';

/// The 4x5 color matrix of `ColorMatrix.setSaturation(saturation)` (AOSP
/// `android.graphics.ColorMatrix`), in the row-major 20-element layout that
/// [ui.ColorFilter.matrix] consumes — the matrix behind
/// `RenderNodeEffects.getSaturationX3RenderEffect()`
/// (RenderNodeEffects.java:28-36) when called with
/// [kGlassBackdropSaturation].
///
/// AOSP luma weights: R 0.213, G 0.715, B 0.072.
List<double> saturationColorMatrix(double saturation) {
  final double invSat = 1.0 - saturation;
  final double r = 0.213 * invSat;
  final double g = 0.715 * invSat;
  final double b = 0.072 * invSat;
  return <double>[
    r + saturation, g, b, 0, 0, //
    r, g + saturation, b, 0, 0, //
    r, g, b + saturation, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// The blur sigma to apply on a backdrop downscaled by [downscale], for a
/// full-resolution blur radius of [radiusPx] physical px:
/// `radiusToSigma(downscaleRadius(radiusPx, downscale))` — the sigma the
/// Android pipeline effectively runs on its downsampled nodes
/// (DownscaleScrollableNoiseSuppressor.java:134-153, 261-273).
double downscaledBlurSigma(double radiusPx, double downscale) =>
    radiusToSigma(downscaleRadius(radiusPx, downscale));

/// A [ui.ImageFilter.matrix] scaling uniformly by [scale] with bilinear
/// sampling — one slice of the downscale sandwich (Android's k-times
/// downsampled render nodes are bilinearly restored).
ui.ImageFilter _scaleFilter(double scale) => ui.ImageFilter.matrix(
  Float64List.fromList(<double>[
    scale, 0, 0, 0, //
    0, scale, 0, 0, //
    0, 0, 1, 0, //
    0, 0, 0, 1,
  ]),
  filterQuality: ui.FilterQuality.low,
);

/// The downscale-blur-upscale sandwich: `matrix(1/k) -> blur -> matrix(k)`,
/// blurring at the sigma the k-times-downscaled Android node uses. With
/// [emulateDownscale] false the sandwich is skipped and the blur runs at the
/// equivalent full-resolution sigma instead.
ui.ImageFilter _downscaleBlur({
  required double radiusPx,
  required int downscale,
  required bool emulateDownscale,
}) {
  if (!emulateDownscale) {
    final double sigma = radiusToSigma(radiusPx);
    return ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.clamp);
  }
  final double sigma = downscaledBlurSigma(radiusPx, downscale.toDouble());
  return ui.ImageFilter.compose(
    outer: _scaleFilter(downscale.toDouble()),
    inner: ui.ImageFilter.compose(
      outer: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.clamp),
      inner: _scaleFilter(1.0 / downscale),
    ),
  );
}

/// The glass backdrop stage: downscale [kGlassBackdropDownscale]x, blur
/// `dpf2(6)`, saturation x[kGlassBackdropSaturation]
/// (DownscaleScrollableNoiseSuppressor.java:410-412). This is the input of
/// both the liquid refraction shader and the frosted re-blur.
///
/// [emulateDownscale] keeps the matrix sandwich reproducing Android's
/// bilinear-upsample softness (ARCHITECTURE.md section 3.2).
ui.ImageFilter glassBackdropFilter({
  required double devicePixelRatio,
  bool emulateDownscale = true,
}) {
  return ui.ImageFilter.compose(
    outer: ui.ColorFilter.matrix(saturationColorMatrix(kGlassBackdropSaturation)),
    inner: _downscaleBlur(
      radiusPx: kGlassBackdropBlurRadiusDp * devicePixelRatio,
      downscale: kGlassBackdropDownscale,
      emulateDownscale: emulateDownscale,
    ),
  );
}

/// The frosted backdrop chain:
/// `frosted = blur_38.34@8x(saturate_3(blur_6@4x(src)))` — the second blur
/// runs over the *glass output* (SourcePart.invalidate,
/// DownscaleScrollableNoiseSuppressor.java:413-415, 438-445). The double-blur
/// composition is mandatory; a naive single blur is wrong
/// (ARCHITECTURE.md section 3.1).
ui.ImageFilter frostedBackdropFilter({
  required double devicePixelRatio,
  bool emulateDownscale = true,
}) {
  return ui.ImageFilter.compose(
    outer: _downscaleBlur(
      radiusPx: kFrostedBackdropBlurRadiusDp * devicePixelRatio,
      downscale: kFrostedBackdropDownscale,
      emulateDownscale: emulateDownscale,
    ),
    inner: glassBackdropFilter(
      devicePixelRatio: devicePixelRatio,
      emulateDownscale: emulateDownscale,
    ),
  );
}

/// The full liquid chain: the glass backdrop stage refracted (and tinted)
/// by the SDF shader — `ui.ImageFilter.shader` outermost, per the Android
/// order where `LiquidGlassEffect` wraps the already blurred+saturated fill
/// node (LiquidGlassEffect.java:24, 98).
///
/// Throws [UnsupportedError] off Impeller — callers must gate on
/// `ui.ImageFilter.isShaderFilterSupported` (see
/// [RenderGlassSurface.effectiveTier]).
ui.ImageFilter liquidBackdropFilter({
  required ui.FragmentShader shader,
  required double devicePixelRatio,
  bool emulateDownscale = true,
}) {
  return ui.ImageFilter.compose(
    outer: ui.ImageFilter.shader(shader),
    inner: glassBackdropFilter(
      devicePixelRatio: devicePixelRatio,
      emulateDownscale: emulateDownscale,
    ),
  );
}

/// Render object of one glass surface — the port of
/// `BlurredBackgroundDrawableRenderNode` plus the child slot of the wrapping
/// view.
///
/// Paint order (ARCHITECTURE.md section 3.2; Java `draw` +
/// `updateDisplayList`):
///
///  1. **shadow** — [GlassGeometry.shadowPath] filled with the style's shadow
///     color under [GlassGeometry.shadowMaskFilter] (the `setShadowLayer`
///     analog, BlurredBackgroundDrawable.java:46-53);
///  2. **fill** — tier switch: liquid pushes a [BackdropFilterLayer] with
///     [liquidBackdropFilter] under a *rect* clip inflated by the refraction
///     bleed (the SDF clips in-shader; a rounded clip would clamp backdrop
///     sampling and kill rim refraction); frosted pushes
///     [frostedBackdropFilter] under a rounded clip and paints the tint as a
///     rounded rect; flat paints the tint rect alone (zero readback);
///  3. **child** — the panel content;
///  4. **strokes** — [GlassGeometry.strokeRingTop]/[GlassGeometry.strokeRingBottom]
///     filled with the style's hairline colors, gated on a non-zero color
///     exactly like Java (BlurredBackgroundDrawableRenderNode.java:143-152).
///
/// Repaint is keyed on the value-comparable inputs ([style], [settings],
/// [radii], ...) plus [themeRevision] — the monotonic
/// `TelegramThemeData.revision` counter, so an in-place theme swap that
/// produced identical style values still repaints (and re-packs uniforms)
/// exactly once.
class RenderGlassSurface extends RenderProxyBox {
  /// Creates a glass surface render object.
  RenderGlassSurface({
    required this._tier,
    required this._strategy,
    required this._style,
    required this._settings,
    this._radii = GlassRadii.zero,
    this._forceBottomZero = false,
    this._padding = 0.0,
    this._devicePixelRatio = 1.0,
    this._themeRevision = 0,
    this._backdropKey,
    RenderBox? child,
  }) : assert(_devicePixelRatio > 0),
       super(child);

  final LayerHandle<BackdropFilterLayer> _backdropLayer = LayerHandle<BackdropFilterLayer>();
  Offset _paintOffset = Offset.zero;
  final LayerHandle<ClipRRectLayer> _frostedClipLayer = LayerHandle<ClipRRectLayer>();
  final LayerHandle<ClipRectLayer> _liquidClipLayer = LayerHandle<ClipRectLayer>();
  LiquidGlassUniforms? _uniforms;
  bool _listeningForShaderLoad = false;

  /// The requested fidelity tier (see [effectiveTier] for what actually
  /// paints).
  GlassTier get tier => _tier;
  GlassTier _tier;
  set tier(GlassTier value) {
    if (value == _tier) {
      return;
    }
    final bool wantedBackdrop = _wantsBackdropLayer;
    _tier = value;
    if (wantedBackdrop != _wantsBackdropLayer) {
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  /// How the backdrop pixels are produced. Only
  /// [GlassStrategy.backdropShader] mounts a backdrop-reading layer;
  /// [GlassStrategy.snapshotCache] (phase 6, `source_host.dart`) currently
  /// paints like [GlassStrategy.tintOnly].
  GlassStrategy get strategy => _strategy;
  GlassStrategy _strategy;
  set strategy(GlassStrategy value) {
    if (value == _strategy) {
      return;
    }
    final bool wantedBackdrop = _wantsBackdropLayer;
    _strategy = value;
    if (wantedBackdrop != _wantsBackdropLayer) {
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  /// Resolved surface colors and stroke/shadow metrics.
  GlassSurfaceStyle get style => _style;
  GlassSurfaceStyle _style;
  set style(GlassSurfaceStyle value) {
    if (value == _style) {
      return;
    }
    _style = value;
    markNeedsPaint();
  }

  /// Liquid refraction parameters (logical px; the packer converts to
  /// physical and applies the draw-time thickness clamp).
  LiquidGlassSettings get settings => _settings;
  LiquidGlassSettings _settings;
  set settings(LiquidGlassSettings value) {
    if (value == _settings) {
      return;
    }
    _settings = value;
    markNeedsPaint();
  }

  /// Per-corner radii, the Java `setRadius` values. Under [forceBottomZero]
  /// the clip goes square at the bottom while the shader keeps these radii
  /// (BlurredBackgroundDrawable.java:119-131).
  GlassRadii get radii => _radii;
  GlassRadii _radii;
  set radii(GlassRadii value) {
    if (value == _radii) {
      return;
    }
    _radii = value;
    markNeedsPaint();
  }

  /// The `forceBottomZero` flag of the Java `setRadius` 5-arg overload.
  bool get forceBottomZero => _forceBottomZero;
  bool _forceBottomZero;
  set forceBottomZero(bool value) {
    if (value == _forceBottomZero) {
      return;
    }
    _forceBottomZero = value;
    markNeedsPaint();
  }

  /// Symmetric inset of the glass visuals within this box — the Java
  /// `Props.padding` (e.g. the main tab bar's 7.666dp drawable padding).
  /// Does not affect child layout.
  double get padding => _padding;
  double _padding;
  set padding(double value) {
    if (value == _padding) {
      return;
    }
    _padding = value;
    markNeedsPaint();
  }

  /// Physical-per-logical pixel ratio; the shader and blur radii work in
  /// physical px (Android `density`).
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    assert(value > 0);
    if (value == _devicePixelRatio) {
      return;
    }
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// Repaint key: the `TelegramThemeData.revision` of the theme the [style]
  /// was resolved from (0 when un-themed).
  int get themeRevision => _themeRevision;
  int _themeRevision;
  set themeRevision(int value) {
    if (value == _themeRevision) {
      return;
    }
    _themeRevision = value;
    markNeedsPaint();
  }

  /// The shared backdrop identity of the enclosing `GlassBackdropScope` —
  /// grouped backdrop layers with one key share a single backdrop snapshot
  /// per frame (ARCHITECTURE.md section 3.2).
  BackdropKey? get backdropKey => _backdropKey;
  BackdropKey? _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (value == _backdropKey) {
      return;
    }
    _backdropKey = value;
    markNeedsPaint();
  }

  /// Whether this surface mounts a backdrop-reading layer: Strategy 1 on any
  /// non-flat tier. The flat floor never pays for a backdrop
  /// (ARCHITECTURE.md section 3.2, Strategy 3).
  bool get _wantsBackdropLayer =>
      _strategy == GlassStrategy.backdropShader && _tier != GlassTier.flat;

  /// The tier that will actually paint: a liquid request degrades to frosted
  /// when `ui.ImageFilter.shader` is unavailable (non-Impeller backends,
  /// flutter_tester) or the fragment program has not loaded yet — the
  /// in-code guard that keeps the shader filter from ever being constructed
  /// on a backend that would throw.
  GlassTier get effectiveTier {
    if (_tier != GlassTier.liquid) {
      return _tier;
    }
    if (!ui.ImageFilter.isShaderFilterSupported || !TgShaders.isInitialized) {
      return GlassTier.frosted;
    }
    return GlassTier.liquid;
  }

  @override
  bool get alwaysNeedsCompositing => _wantsBackdropLayer;

  /// Glass surfaces consume hits over their whole rect, like the Android
  /// views hosting `BlurredBackgroundDrawable` backgrounds (a tap on the tab
  /// bar margin must not scroll the list beneath it).
  @override
  bool hitTestSelf(Offset position) => true;

  /// The [GlassGeometry] this surface paints for the given [bounds] —
  /// exposed so tests and callers can probe the exact stroke/shadow/clip
  /// paths without painting.
  ///
  /// Stroke widths flagged [GlassSurfaceStyle.strokeWidthPhysicalPx] (the
  /// `searchFloatingDate` raw-px recipe) are converted to logical px here,
  /// so the hairline stays one physical pixel on every density.
  GlassGeometry geometryFor(Rect bounds) {
    final double strokeUnit =
        _style.strokeWidthPhysicalPx ? 1.0 / _devicePixelRatio : 1.0;
    return GlassGeometry(
      bounds: bounds,
      radii: _radii,
      forceBottomZero: _forceBottomZero,
      padding: _padding,
      strokeWidthTop: _style.strokeWidthTop * strokeUnit,
      strokeWidthBottom: _style.strokeWidthBottom * strokeUnit,
      shadowRadius: _style.shadowRadius,
      shadowDx: _style.shadowDx,
      shadowDy: _style.shadowDy,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _paintOffset = offset;
    final GlassGeometry geometry = geometryFor(offset & size);
    final bool paintsDecoration = !geometry.boundsWithPadding.isEmpty;
    if (paintsDecoration) {
      _paintShadow(context.canvas, geometry);
      _paintFill(context, geometry);
    }
    super.paint(context, offset);
    if (paintsDecoration) {
      _paintStrokes(context.canvas, geometry);
    }
    _syncShaderLoadListener();
  }

  /// While a liquid request paints degraded because [TgShaders] has not
  /// loaded yet, watch for the load so this surface repaints on completion.
  /// Without this, a panel whose *widget-side* inputs never change (an
  /// explicit `tier: GlassTier.liquid` override, or a forced-liquid
  /// kill-switch) would stay frosted until an unrelated repaint — the scope
  /// resolution path repaints via a value change, but re-applied identical
  /// field values no-op every setter.
  void _syncShaderLoadListener() {
    final bool shouldListen =
        attached && _tier == GlassTier.liquid && !TgShaders.isInitialized;
    if (shouldListen == _listeningForShaderLoad) {
      return;
    }
    _listeningForShaderLoad = shouldListen;
    if (shouldListen) {
      TgShaders.initialized.addListener(_onShaderLoadChanged);
    } else {
      TgShaders.initialized.removeListener(_onShaderLoadChanged);
    }
  }

  void _onShaderLoadChanged() {
    // One-shot: the flip invalidates the degraded paint decision; the next
    // paint re-registers if still relevant (e.g. after a debugReset).
    _stopListeningForShaderLoad();
    markNeedsPaint();
  }

  void _stopListeningForShaderLoad() {
    if (!_listeningForShaderLoad) {
      return;
    }
    _listeningForShaderLoad = false;
    TgShaders.initialized.removeListener(_onShaderLoadChanged);
  }

  @override
  void detach() {
    _stopListeningForShaderLoad();
    super.detach();
  }

  /// Step 1 — the blurred drop shadow drawn before everything else
  /// (`boundProps.drawShadows`, BlurredBackgroundDrawableRenderNode.java:186-190).
  /// Skipped on a fully transparent shadow color, like the Java
  /// `Color.alpha(color) != 0` gate.
  void _paintShadow(Canvas canvas, GlassGeometry geometry) {
    if ((_style.shadowColor.toARGB32() >>> 24) == 0) {
      return;
    }
    final Paint paint = Paint()..color = _style.shadowColor;
    final MaskFilter? mask = geometry.shadowMaskFilter;
    if (mask != null) {
      paint.maskFilter = mask;
    }
    canvas.drawPath(geometry.shadowPath, paint);
  }

  /// Step 2 — the tier-switched fill.
  void _paintFill(PaintingContext context, GlassGeometry geometry) {
    final GlassTier tier = effectiveTier;
    if (_wantsBackdropLayer && tier == GlassTier.liquid) {
      _pushLiquidBackdrop(context, geometry);
      return; // The shader composites the tint itself.
    }
    if (_wantsBackdropLayer) {
      _pushFrostedBackdrop(context, geometry);
    }
    _paintTint(context.canvas, geometry);
  }

  /// The composited tint rounded-rect: the frosted overlay (alpha 0.76
  /// recipes) and the whole of the flat tier. Skipped on zero alpha, like
  /// the Java `Color.alpha(backgroundColor) != 0` gate
  /// (BlurredBackgroundDrawableRenderNode.java:134-142).
  void _paintTint(Canvas canvas, GlassGeometry geometry) {
    if ((_style.backgroundColor.toARGB32() >>> 24) == 0) {
      return;
    }
    canvas.drawRRect(geometry.outerRRect, Paint()..color = _style.backgroundColor);
  }

  /// Frosted fill: [frostedBackdropFilter] as a grouped backdrop layer under
  /// a rounded clip (the frosted tier has no in-shader SDF to shape it).
  void _pushFrostedBackdrop(PaintingContext context, GlassGeometry geometry) {
    final BackdropFilterLayer backdrop = _backdropLayer.layer ??= BackdropFilterLayer();
    backdrop
      ..filter = frostedBackdropFilter(devicePixelRatio: _devicePixelRatio)
      ..blendMode = BlendMode.srcOver
      ..backdropKey = _backdropKey;
    _frostedClipLayer.layer = context.pushClipRRect(
      true,
      Offset.zero,
      geometry.boundsWithPadding,
      geometry.outerRRect,
      (PaintingContext context, Offset offset) {
        context.pushLayer(backdrop, _paintNothing, Offset.zero);
      },
      clipBehavior: Clip.antiAlias,
      oldLayer: _frostedClipLayer.layer,
    );
  }

  /// Liquid fill: uniforms packed in GLOBAL (device) physical px — see the
  /// coordinate-space note inside — then [liquidBackdropFilter] as a grouped
  /// backdrop layer under a plain rect clip inflated by
  /// `bleed = ceil(8 * thickness * intensity)` physical px (the shader
  /// ray-length constant 8.0 — ARCHITECTURE.md section 3.2).
  /// The SDF clips in-shader; there is deliberately NO rounded clip here.
  void _pushLiquidBackdrop(PaintingContext context, GlassGeometry geometry) {
    assert(
      ui.ImageFilter.isShaderFilterSupported && TgShaders.isInitialized,
      'RenderGlassSurface liquid fill reached without shader-filter support; '
      'effectiveTier must gate this branch.',
    );
    final double dpr = _devicePixelRatio;
    final Rect panel = geometry.boundsWithPadding;

    // FlutterFragCoord() inside a backdrop runtime-effect filter is anchored
    // to the DEVICE/scene coordinate space, not to this layer's clip rect:
    // Impeller re-rasterizes the filter input so the fragment shader sees
    // stable entity-space coordinates (engine
    // impeller/entity/contents/filters/runtime_effect_filter_contents.cc,
    // the ShouldRasterizeForRuntimeEffects branch — the synthesized snapshot
    // coverage starts at the entity offset, and u_size is the input TEXTURE
    // size, not the clip size). The SDF uniforms must therefore be packed in
    // global physical pixels; packing them clip-locally displaces the glass
    // by the clip origin (panel - bleed), which grows with
    // thickness * intensity — the exact drift observed on-device.
    //
    // `getTransformTo(null)` maps this render object's local space to the
    // root (logical px); the paint offset is already inside
    // `geometry.boundsWithPadding`, so strip it before transforming. For
    // rotated/scaled ancestors transformRect degrades to the bounding box —
    // glass under non-axis-aligned transforms is unsupported (as on Android,
    // where blur3 assumes axis-aligned chrome). NOTE: layer-level translations
    // applied WITHOUT a repaint (e.g. scrolling this panel inside a viewport)
    // stale these uniforms; chrome surfaces are static, and scrollable hosts
    // must repaint on scroll (the Android ViewPositionWatcher analog).
    final Rect globalPanel = MatrixUtils.transformRect(
      getTransformTo(null),
      panel.shift(-_paintOffset),
    );

    // Preserve the Java `liquidThickness <= 0` sentinel; a positive logical
    // thickness converts to physical px for the packer.
    final double thicknessPx = _settings.thickness > 0 ? _settings.thickness * dpr : 0.0;
    final double resolvedThicknessPx = LiquidGlassUniforms.resolveThickness(
      thickness: thicknessPx,
      width: panel.width * dpr,
      height: panel.height * dpr,
      devicePixelRatio: dpr,
    );
    final double bleedPx = (8.0 * resolvedThicknessPx * _settings.refractIntensity).ceilToDouble();
    final Rect coverage = panel.inflate(bleedPx / dpr);

    final LiquidGlassUniforms uniforms =
        _uniforms ??= LiquidGlassUniforms.fromProgram(TgShaders.liquidGlassProgram);
    uniforms.update(
      coverageSize: Size(coverage.width * dpr, coverage.height * dpr),
      panelRect: Rect.fromLTWH(
        globalPanel.left * dpr,
        globalPanel.top * dpr,
        globalPanel.width * dpr,
        globalPanel.height * dpr,
      ),
      radii: _scaleRadii(geometry.shaderRadii, dpr),
      tint: _settings.tintColor,
      thickness: thicknessPx,
      intensity: _settings.refractIntensity,
      index: _settings.refractIndex,
      devicePixelRatio: dpr,
      engineSetsSize: true,
    );

    final BackdropFilterLayer backdrop = _backdropLayer.layer ??= BackdropFilterLayer();
    backdrop
      ..filter = liquidBackdropFilter(shader: uniforms.shader, devicePixelRatio: dpr)
      ..blendMode = BlendMode.srcOver
      ..backdropKey = _backdropKey;
    _liquidClipLayer.layer = context.pushClipRect(
      true,
      Offset.zero,
      coverage,
      (PaintingContext context, Offset offset) {
        context.pushLayer(backdrop, _paintNothing, Offset.zero);
      },
      oldLayer: _liquidClipLayer.layer,
    );
  }

  /// Step 4 — the hairline rings, filled (not stroked), gated on a non-zero
  /// color like `strokeColorTop != 0` / `strokeColorBottom != 0`
  /// (BlurredBackgroundDrawableRenderNode.java:143-152).
  void _paintStrokes(Canvas canvas, GlassGeometry geometry) {
    if (_style.strokeColorTop.toARGB32() != 0) {
      canvas.drawPath(geometry.strokeRingTop, Paint()..color = _style.strokeColorTop);
    }
    if (_style.strokeColorBottom.toARGB32() != 0) {
      canvas.drawPath(geometry.strokeRingBottom, Paint()..color = _style.strokeColorBottom);
    }
  }

  static void _paintNothing(PaintingContext context, Offset offset) {}

  static GlassRadii _scaleRadii(GlassRadii radii, double scale) => GlassRadii(
    topLeft: radii.topLeft * scale,
    topRight: radii.topRight * scale,
    bottomRight: radii.bottomRight * scale,
    bottomLeft: radii.bottomLeft * scale,
  );

  @override
  void dispose() {
    _stopListeningForShaderLoad();
    _backdropLayer.layer = null;
    _frostedClipLayer.layer = null;
    _liquidClipLayer.layer = null;
    _uniforms?.dispose();
    _uniforms = null;
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<GlassTier>('tier', tier))
      ..add(EnumProperty<GlassTier>('effectiveTier', effectiveTier))
      ..add(EnumProperty<GlassStrategy>('strategy', strategy))
      ..add(DiagnosticsProperty<GlassSurfaceStyle>('style', style))
      ..add(DiagnosticsProperty<LiquidGlassSettings>('settings', settings))
      ..add(DiagnosticsProperty<GlassRadii>('radii', radii))
      ..add(FlagProperty('forceBottomZero', value: forceBottomZero, ifTrue: 'square bottom clip'))
      ..add(DoubleProperty('padding', padding))
      ..add(DoubleProperty('devicePixelRatio', devicePixelRatio))
      ..add(IntProperty('themeRevision', themeRevision))
      ..add(
        DiagnosticsProperty<BackdropKey>('backdropKey', backdropKey, defaultValue: null),
      );
  }
}
