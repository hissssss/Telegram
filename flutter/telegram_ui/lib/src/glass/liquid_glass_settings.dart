// The liquid-glass refraction parameters as an immutable Flutter value type.
//
// Port of the liquid parameter surface of
// `java/org/telegram/ui/Components/blur3/drawable/BlurredBackgroundDrawable.java`:
// the `Props` defaults `liquidThickness = 0` (resolving to dp(11) at draw
// time), `liquidIntensity = 0.75f`, `liquidIndex = 1.5f` (lines 223-225) and
// the setters `setThickness(int)` / `setIntensity(float)` (lines 133-141) —
// `liquidIndex` has no production setter and is always 1.5. The tint is the
// `backgroundColor` that `LiquidGlassEffect.update` premultiplies into the
// shader (`blur3/LiquidGlassEffect.java:85-97`), and the per-corner radii are
// the `shaderRadii` of `setRadius`
// (`BlurredBackgroundDrawable.java:99-131`).
//
// Values here are *logical* pixels (Flutter convention); the uniform packer
// (`liquid_glass_shader.dart`) works in physical pixels and applies the
// draw-time thickness clamp of `BlurredBackgroundDrawableRenderNode.java`
// (lines 115-118).
library;

import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;

import '../tokens/glass_metrics.g.dart';
import 'geometry.dart';

/// Immutable parameter set of one liquid-glass surface.
///
/// Defaults mirror Android production values (`glass_metrics.g.dart`):
/// thickness dp(11), intensity 0.75, index 1.5. Documented caller overrides
/// (spec_glass.md section 2): keyboard/attach panels use thickness dp(32) at
/// intensity 0.4, the fast-scroll tag dp(4), tag chips dp(5).
@immutable
class LiquidGlassSettings {
  /// Creates liquid-glass settings; every parameter defaults to the Android
  /// production value.
  const LiquidGlassSettings({
    this.thickness = kGlassThicknessDefaultDp,
    this.refractIntensity = kGlassRefractIntensityDefault,
    this.refractIndex = kGlassRefractIndex,
    this.tintColor = const Color(0x00000000),
    this.radii = GlassRadii.zero,
  });

  /// Lens rim thickness in logical px — `Props.liquidThickness`.
  ///
  /// Default [kGlassThicknessDefaultDp] (dp(11)). A value `<= 0` means "use
  /// the default at draw time", exactly like the Java sentinel; either way
  /// the packer clamps to `min(width, height) / 5` with a 1 physical px
  /// floor (`BlurredBackgroundDrawableRenderNode.java:115-118`).
  final double thickness;

  /// Refraction displacement multiplier — `Props.liquidIntensity`,
  /// default [kGlassRefractIntensityDefault] (0.75).
  final double refractIntensity;

  /// Index of refraction — `Props.liquidIndex`, default [kGlassRefractIndex]
  /// (1.5, no production setter exists).
  final double refractIndex;

  /// The tint composited over the refracted backdrop *inside* the shader —
  /// the `backgroundColor` argument of `LiquidGlassEffect.update`.
  ///
  /// Default fully transparent (no tint). Themed surfaces derive this from
  /// their color provider (e.g. `multAlpha(themeColor, 0.85)`,
  /// `BlurredBackgroundColorProviderThemed.java:16,41`).
  final Color tintColor;

  /// Per-corner radii of the refraction SDF in logical px — the
  /// `shaderRadii` of `setRadius` (`BlurredBackgroundDrawable.java:99-131`).
  ///
  /// Note the `forceBottomZero` quirk: these may stay rounded while the clip
  /// radii go square (see `GlassGeometry.shaderRadii`).
  final GlassRadii radii;

  /// Copy with the given fields replaced.
  LiquidGlassSettings copyWith({
    double? thickness,
    double? refractIntensity,
    double? refractIndex,
    Color? tintColor,
    GlassRadii? radii,
  }) {
    return LiquidGlassSettings(
      thickness: thickness ?? this.thickness,
      refractIntensity: refractIntensity ?? this.refractIntensity,
      refractIndex: refractIndex ?? this.refractIndex,
      tintColor: tintColor ?? this.tintColor,
      radii: radii ?? this.radii,
    );
  }

  /// Linear interpolation between [a] and [b] at position [t]
  /// (0 -> [a], 1 -> [b]); [t] is not clamped.
  static LiquidGlassSettings lerp(LiquidGlassSettings a, LiquidGlassSettings b, double t) {
    if (identical(a, b) || t == 0.0) {
      return a;
    }
    if (t == 1.0) {
      return b;
    }
    return LiquidGlassSettings(
      thickness: lerpDouble(a.thickness, b.thickness, t)!,
      refractIntensity: lerpDouble(a.refractIntensity, b.refractIntensity, t)!,
      refractIndex: lerpDouble(a.refractIndex, b.refractIndex, t)!,
      tintColor: Color.lerp(a.tintColor, b.tintColor, t)!,
      radii: GlassRadii(
        topLeft: lerpDouble(a.radii.topLeft, b.radii.topLeft, t)!,
        topRight: lerpDouble(a.radii.topRight, b.radii.topRight, t)!,
        bottomRight: lerpDouble(a.radii.bottomRight, b.radii.bottomRight, t)!,
        bottomLeft: lerpDouble(a.radii.bottomLeft, b.radii.bottomLeft, t)!,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassSettings &&
      other.thickness == thickness &&
      other.refractIntensity == refractIntensity &&
      other.refractIndex == refractIndex &&
      other.tintColor == tintColor &&
      other.radii == radii;

  @override
  int get hashCode => Object.hash(thickness, refractIntensity, refractIndex, tintColor, radii);

  @override
  String toString() =>
      'LiquidGlassSettings(thickness: $thickness, '
      'refractIntensity: $refractIntensity, refractIndex: $refractIndex, '
      'tintColor: $tintColor, radii: $radii)';
}
