// Runtime capability probe, shader warmup, and global tier settings of the
// glass system (ARCHITECTURE.md section 3.5, graft: PERF).
//
// The Flutter analog of the two Android gates in front of the liquid path of
// `java/org/telegram/ui/Components/blur3/`:
//
//   * the platform gate of `BlurredBackgroundDrawableViewFactory.create`
//     (BlurredBackgroundDrawableViewFactory.java:81-86): the liquid render
//     node is only armed when `isLiquidGlassEffectAllowed` AND
//     `Build.VERSION.SDK_INT >= TIRAMISU` (RuntimeShader needs API 33).
//     Flutter's equivalent platform requirement is a backend that can run
//     `ui.ImageFilter.shader` (Impeller). [GlassRuntimeProbe.run] checks
//     `ui.ImageFilter.isShaderFilterSupported`, loads the fragment program,
//     and renders a 4x4 offscreen scene through the shader — detecting
//     broken backends *and* pre-compiling the pipeline so the first real
//     glass frame never stalls on shader compilation;
//
//   * the LiteMode switch,
//     `setLiquidGlassEffectAllowed(LiteMode.isEnabled(LiteMode.FLAG_LIQUID_GLASS))`
//     (MainTabsActivity.java:340 et al.) — here the [GlassSettings.forcedTier]
//     kill-switch, which can force any [GlassTier] for the whole app.
//
// Downgrade policy mirrors the Android ladder (`DRAW_GLASS` ->
// `DRAW_FROSTED_GLASS`, DownscaleScrollableNoiseSuppressor.java:49-51): a
// liquid request on an incapable — or not-yet-probed — runtime resolves to
// [GlassTier.frosted], never to [GlassTier.flat]. [GlassSettings] is a
// [ChangeNotifier] so surfaces re-resolve when the async probe lands.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ChangeNotifier, immutable, visibleForTesting;

import '../tokens/liquid_glass_uniforms.g.dart';
import 'geometry.dart';
import 'liquid_glass_shader.dart';
import 'strategy.dart';

/// Result of [GlassRuntimeProbe.run]: whether this runtime can render the
/// [GlassTier.liquid] tier, and — when it cannot — why.
@immutable
class GlassCapability {
  /// Creates a capability verdict. [reason] should be null exactly when
  /// [liquidSupported] is true.
  const GlassCapability({required this.liquidSupported, this.reason})
    : assert(liquidSupported == (reason == null), 'reason must be given iff liquid is unsupported');

  /// The liquid tier works: the backdrop shader filter is available and the
  /// fragment shader compiled and rendered.
  const GlassCapability.supported() : this(liquidSupported: true);

  /// The liquid tier is unavailable for [reason]; liquid requests downgrade
  /// to [GlassTier.frosted].
  const GlassCapability.unsupported(String reason) : this(liquidSupported: false, reason: reason);

  /// Whether `ui.ImageFilter.shader` plus the liquid-glass fragment program
  /// are usable on this runtime.
  final bool liquidSupported;

  /// Human-readable diagnosis when [liquidSupported] is false; null when
  /// supported.
  final String? reason;

  @override
  bool operator ==(Object other) =>
      other is GlassCapability &&
      other.liquidSupported == liquidSupported &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(liquidSupported, reason);

  @override
  String toString() =>
      'GlassCapability(${liquidSupported ? 'liquid supported' : 'liquid unsupported: $reason'})';
}

/// Async capability check + shader warmup (ARCHITECTURE.md section 3.5).
///
/// The Flutter analog of Android's API-33 RuntimeShader gate
/// (`BlurredBackgroundDrawableViewFactory.java:81-86`), with pipeline
/// pre-compilation folded in: the probe scene exercises the exact fragment
/// shader the first glass surface will use, so its compilation cost is paid
/// off-screen at startup instead of on first paint.
abstract final class GlassRuntimeProbe {
  /// Extent (physical px) of the offscreen probe scene.
  static const int kProbeExtent = 4;

  /// Test seam: skips the `ui.ImageFilter.isShaderFilterSupported` gate so
  /// the load+render phases can be exercised under flutter_tester (whose CPU
  /// backend reports the shader image filter as unsupported).
  @visibleForTesting
  static bool debugBypassBackendGate = false;

  /// Runs the capability check. Never throws — every failure mode is caught
  /// and folded into an unsupported [GlassCapability] with a [GlassCapability.reason].
  ///
  /// Three phases, first failure wins:
  ///
  /// 1. `ui.ImageFilter.isShaderFilterSupported` — false on every non-Impeller
  ///    backend, including flutter_tester's CPU backend, so `flutter test`
  ///    always resolves non-liquid here without touching the GPU;
  /// 2. [TgShaders.ensureInitialized] — loads/compiles the fragment program;
  /// 3. a [kProbeExtent]-square offscreen render of a rect filled with the
  ///    liquid-glass shader through `ui.PictureRecorder` +
  ///    `ui.Picture.toImageSync`. This is the Canvas path, so the probe binds
  ///    what the engine binds on the production `ui.ImageFilter.shader` path:
  ///    the `u_size` slots (`engineSetsSize: false`) and a stand-in backdrop
  ///    image on the `u_backdrop` sampler (drawing with an unbound sampler
  ///    throws "missing sampler" on every backend).
  static Future<GlassCapability> run() async {
    if (!debugBypassBackendGate && !ui.ImageFilter.isShaderFilterSupported) {
      return const GlassCapability.unsupported(
        'ui.ImageFilter.shader is unsupported on this rendering backend '
        '(Impeller required; flutter_tester and other CPU/Skia backends '
        'cannot run backdrop fragment shaders)',
      );
    }
    ui.FragmentProgram program;
    try {
      program = await TgShaders.ensureInitialized();
    } catch (error) {
      return GlassCapability.unsupported('liquid-glass shader failed to load: $error');
    }
    try {
      _renderProbeScene(program);
    } catch (error) {
      return GlassCapability.unsupported('liquid-glass probe render failed: $error');
    }
    return const GlassCapability.supported();
  }

  /// Draws one [kProbeExtent]-square frame through the full uniform packer +
  /// shader, forcing pipeline compilation.
  static void _renderProbeScene(ui.FragmentProgram program) {
    const double extent = 4;
    assert(extent == kProbeExtent);
    final ui.Image backdrop = _solidBackdrop();
    final LiquidGlassUniforms uniforms = LiquidGlassUniforms.fromProgram(program);
    try {
      uniforms.update(
        coverageSize: const ui.Size(extent, extent),
        panelRect: const ui.Rect.fromLTWH(0, 0, extent, extent),
        radii: const GlassRadii.all(1),
        // Any non-trivial tint; 0xD9 ~ the production liquid alpha 0.85.
        tint: const ui.Color(0xD9FFFFFF),
        thickness: 0, // Exercise the dp(11) default + min(w,h)/5 clamp -> 1px.
        devicePixelRatio: 1,
      );
      uniforms.shader.setImageSampler(kUniformBackdropSampler, backdrop);
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, extent, extent),
        ui.Paint()..shader = uniforms.shader,
      );
      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = picture.toImageSync(kProbeExtent, kProbeExtent);
      image.dispose();
      picture.dispose();
    } finally {
      uniforms.dispose();
      backdrop.dispose();
    }
  }

  /// A [kProbeExtent]-square mid-gray image standing in for the backdrop
  /// texture the engine binds in production.
  static ui.Image _solidBackdrop() {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, kProbeExtent.toDouble(), kProbeExtent.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF808080),
    );
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = picture.toImageSync(kProbeExtent, kProbeExtent);
    picture.dispose();
    return image;
  }
}

/// Global glass configuration: probe state + the tier kill-switch
/// (ARCHITECTURE.md section 3.5).
///
/// The port of the app-wide LiteMode wiring: Android pushes
/// `LiteMode.isEnabled(LiteMode.FLAG_LIQUID_GLASS)` into every drawable
/// factory (`BlurredBackgroundDrawableViewFactory.java:57-60`); here every
/// `GlassBackdropScope` consults [resolvedTier] and listens for changes.
///
/// Apps use the process-wide [instance]; tests may construct their own (the
/// [GlassSettings.new] `probe` parameter injects a fake probe function).
/// Notifies listeners when the probe completes ("late probe completion" —
/// surfaces conservatively render frosted until the probe proves liquid
/// works) and when [forcedTier] changes.
class GlassSettings extends ChangeNotifier {
  /// Creates standalone settings. [probe] overrides the capability check
  /// run by [ensureProbed] — a test seam; production uses
  /// [GlassRuntimeProbe.run].
  GlassSettings({Future<GlassCapability> Function()? probe})
    : _probe = probe ?? GlassRuntimeProbe.run;

  /// The process-wide settings used when none are injected.
  static final GlassSettings instance = GlassSettings();

  final Future<GlassCapability> Function() _probe;

  Future<GlassCapability>? _probing;
  GlassCapability? _capability;
  GlassTier? _forcedTier;

  /// The probe verdict, or null while the probe has not completed (liquid
  /// requests resolve to frosted in the meantime).
  GlassCapability? get capability => _capability;

  /// Whether a capability verdict is present.
  bool get probed => _capability != null;

  /// Kill-switch: when non-null, [resolvedTier] returns this tier for every
  /// request, bypassing the probe entirely — including forcing
  /// [GlassTier.liquid] on a runtime the probe rejected (debug/eyeball-parity
  /// use). Null (the default) restores probe-driven resolution. Notifies on
  /// change.
  GlassTier? get forcedTier => _forcedTier;
  set forcedTier(GlassTier? value) {
    if (_forcedTier == value) {
      return;
    }
    _forcedTier = value;
    notifyListeners();
  }

  /// Runs the probe once (concurrent callers share the run) and caches the
  /// verdict; completes immediately when already probed. Completion notifies
  /// listeners. Never throws.
  Future<GlassCapability> ensureProbed() {
    final GlassCapability? existing = _capability;
    if (existing != null) {
      return Future<GlassCapability>.value(existing);
    }
    return _probing ??= _runProbe();
  }

  Future<GlassCapability> _runProbe() async {
    GlassCapability result;
    try {
      result = await _probe();
    } catch (error) {
      result = GlassCapability.unsupported('liquid-glass probe failed: $error');
    }
    applyCapability(result);
    return result;
  }

  /// Installs a capability verdict directly (probe completion calls this;
  /// tests and hosts with out-of-band knowledge may too). Notifies listeners
  /// when the verdict changed.
  void applyCapability(GlassCapability capability) {
    if (_capability == capability) {
      return;
    }
    _capability = capability;
    notifyListeners();
  }

  /// Resolves a requested tier against the kill-switch and the probe state.
  ///
  /// [forcedTier], when set, wins unconditionally. Otherwise a
  /// [GlassTier.liquid] request downgrades to [GlassTier.frosted] — one rung,
  /// mirroring `DRAW_GLASS` -> `DRAW_FROSTED_GLASS` — unless the probe has
  /// completed with [GlassCapability.liquidSupported]. Frosted and flat
  /// requests pass through untouched.
  GlassTier resolvedTier(GlassTier requested) {
    final GlassTier? forced = _forcedTier;
    if (forced != null) {
      return forced;
    }
    if (requested == GlassTier.liquid && !(_capability?.liquidSupported ?? false)) {
      return GlassTier.frosted;
    }
    return requested;
  }

  /// Test hook: clears the probe verdict, any in-flight probe, and the
  /// kill-switch, then notifies listeners.
  @visibleForTesting
  void debugReset() {
    _probing = null;
    _capability = null;
    _forcedTier = null;
    notifyListeners();
  }
}
