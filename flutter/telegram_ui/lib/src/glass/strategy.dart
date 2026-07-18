// Fidelity tiers and rendering strategies of the glass system
// (ARCHITECTURE.md section 3.2: one public API, tiered rendering).
//
// Port of the draw-mode ladder of
// `java/org/telegram/ui/Components/blur3/DownscaleScrollableNoiseSuppressor.java`
// (`DRAW_GLASS = -2`, `DRAW_FROSTED_GLASS = -3`, lines 49-51) and of the
// LiteMode gating that selects between them:
// `setLiquidGlassEffectAllowed(LiteMode.isEnabled(LiteMode.FLAG_LIQUID_GLASS))`
// on `blur3/drawable/BlurredBackgroundDrawable.java` (additionally gated on
// API 33 for the runtime shader), with LiteMode fully off degrading to a
// plain composited tint with no backdrop read at all.
//
// The two axes are orthogonal: [GlassTier] says *what* the surface should
// look like (which Android draw mode is being reproduced), [GlassStrategy]
// says *how* Flutter produces the backdrop pixels for it.
library;

/// What a glass surface looks like — the Android draw-mode ladder.
///
/// Mirrors the `blur3` pipeline selection in
/// `DownscaleScrollableNoiseSuppressor.java` (lines 408-428): each tier is a
/// strictly cheaper approximation of the one above it, and surfaces degrade
/// down the ladder when the device (or the user's LiteMode analog) cannot
/// afford the full effect.
enum GlassTier {
  /// Full liquid glass — the port of `DRAW_GLASS` (= -2,
  /// DownscaleScrollableNoiseSuppressor.java:49).
  ///
  /// Backdrop chain: downscale 4x, blur dpf2(6), saturation x3, then the
  /// SDF refraction shader (`res/raw/liquid_glass_shader.agsl`) which also
  /// composites the themed tint (alpha 0.85). On Android this requires
  /// `LiteMode.FLAG_LIQUID_GLASS` *and* API 33 (RuntimeShader); here it
  /// requires a backend that can run `ImageFilter.shader` (Impeller).
  liquid,

  /// Frosted glass — the port of `DRAW_FROSTED_GLASS` (= -3,
  /// DownscaleScrollableNoiseSuppressor.java:50).
  ///
  /// Backdrop chain: the liquid tier's blur+saturate output blurred again at
  /// downscale 8x with radius dpf2(40 - 1.66) = dpf2(38.34) — i.e.
  /// frosted = blur_38.34(saturate_3(blur_6(src))) (SourcePart.invalidate,
  /// lines 438-445). No refraction shader; the tint (alpha 0.76) is painted
  /// as a plain rounded rect. Android's default when liquid glass is off but
  /// blurs are still allowed.
  frosted,

  /// No backdrop effect at all — the LiteMode-off floor.
  ///
  /// The surface is an opaque-ish rounded rect of
  /// `compositeColors(backgroundColor, sourceColor)` plus the stroke rings
  /// and drop shadow; zero readback cost. Matches Android surfaces when the
  /// blur LiteMode flags are disabled and `BlurredBackgroundDrawable` falls
  /// back to solid painting.
  flat,
}

/// How the backdrop pixels behind a glass surface are produced
/// (ARCHITECTURE.md section 3.2, Strategies 1-3).
///
/// Orthogonal to [GlassTier]: any tier can in principle be rendered by any
/// strategy, though [tintOnly] is the only strategy the [GlassTier.flat]
/// tier ever needs.
enum GlassStrategy {
  /// Strategy 1 (default): a `BackdropFilter` layer participating in the
  /// enclosing `BackdropGroup`, with the blur/saturate/refract chain composed
  /// as an `ImageFilter` — the Flutter analog of blur3's shared `SourcePart`
  /// render nodes re-recorded every frame
  /// (`DownscaleScrollableNoiseSuppressor.java:408-428`).
  backdropShader,

  /// Strategy 2 (opt-in): blur3-faithful cross-frame snapshot cache — the
  /// scrollable content is captured into downscaled, pre-blurred GPU images
  /// that glass surfaces sample until the content repaints, the analog of
  /// `SourcePart`'s cached render nodes plus `onScrolled` reprojection
  /// (`DownscaleScrollableNoiseSuppressor.java:239-252`).
  snapshotCache,

  /// Strategy 3: no backdrop layer — the composited tint, strokes, and
  /// shadow only. The rendering of [GlassTier.flat], and the deterministic
  /// path used by CPU-rendered golden tests.
  tintOnly,
}
