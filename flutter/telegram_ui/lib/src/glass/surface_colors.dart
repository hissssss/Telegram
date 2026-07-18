// Resolved glass-surface colors and the builder that produces them.
//
// Ports, from the Android sources:
// - `BlurredBackgroundProviderBuilder`
//   (java/org/telegram/ui/Components/blur3/drawable/color/BlurredBackgroundProviderBuilder.java):
//   the fluent per-surface recipe — (light, dark) color pairs plus a
//   background resolver — including its constructor defaults, shadow layer
//   `(dpf2(1), 0, dpf2(1/3))` and stroke widths `(dpf2(1), dpf2(2/3))`
//   (lines 15-16).
// - `BlurredBackgroundColorProviderThemed`
//   (java/org/telegram/ui/Components/blur3/drawable/color/BlurredBackgroundColorProviderThemed.java):
//   the "themed" mode — one theme key tinted at 0.85 (liquid) / 0.76
//   (frosted) with stroke/shadow sets chosen by the perceived brightness of
//   the resolved key (`< 0.721` selects the dark set, lines 34-51).
//
// Where Java keeps the provider live (colors re-queried on every draw), the
// Flutter port resolves eagerly into an immutable [GlassSurfaceStyle] value:
// theme changes construct a new style (the surrounding widgets rebuild on
// `TelegramTheme` changes anyway), which keeps the render object's inputs
// value-comparable.
//
// Units: stroke widths and shadow metrics are logical dp (the Java sources
// wrap the same numbers in `dpf2()` at draw time); colors are exact ARGB.
library;

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;

import '../foundation/color_math.dart';
import '../theme/telegram_resources.dart';
import '../tokens/glass_metrics.g.dart';
import 'strategy.dart';

/// Resolves the background tint of a glass surface —
/// `BlurredBackgroundProviderBuilder.ColorProvider`
/// (BlurredBackgroundProviderBuilder.java:19-21).
///
/// Returns a raw 0xAARRGGBB int so recipes keep the Java hex verbatim;
/// [isDark] is the ambient palette classification the builder resolved
/// (BlurredBackgroundProviderBuilder.java:118-121).
typedef GlassBackgroundColorProvider = int Function(TelegramResources resources, bool isDark);

/// The resolved paint inputs of one glass surface: tint, hairline strokes,
/// drop shadow, and their metrics.
///
/// This is the value-type analog of Android's `BlurredBackgroundProvider`
/// (blur3/drawable/color/BlurredBackgroundProvider.java) — what
/// `BlurredBackgroundDrawable.setColorProvider` reads into its paints
/// (BlurredBackgroundDrawable.java:189-199). Field defaults are the drawable
/// constructor defaults (BlurredBackgroundDrawable.java:46-53): stroke widths
/// 1dp / (2/3)dp, shadow radius 1dp, offset (0, 1/3)dp, all colors
/// transparent.
@immutable
class GlassSurfaceStyle {
  /// Creates a style; defaults mirror `BlurredBackgroundDrawable`'s
  /// constructor (BlurredBackgroundDrawable.java:46-53) with no colors set.
  const GlassSurfaceStyle({
    this.backgroundColor = const Color(0x00000000),
    this.strokeColorTop = const Color(0x00000000),
    this.strokeColorBottom = const Color(0x00000000),
    this.shadowColor = const Color(0x00000000),
    this.strokeWidthTop = kGlassStrokeWidthTopDp,
    this.strokeWidthBottom = kGlassStrokeWidthBottomDp,
    this.shadowRadius = kGlassShadowRadiusDp,
    this.shadowDx = kGlassShadowDxDp,
    this.shadowDy = kGlassShadowDyDp,
    this.tintAlpha = 0.0,
    this.strokeWidthPhysicalPx = false,
  });

  /// Port of `BlurredBackgroundColorProviderThemed` — a single theme key
  /// tinted at [alpha] with brightness-selected stroke/shadow sets.
  ///
  /// [alpha] defaults per tier as in the Java one-arg constructor
  /// (BlurredBackgroundColorProviderThemed.java:15-17): 0.85 when the liquid
  /// glass LiteMode flag is enabled ([GlassTier.liquid]), 0.76 otherwise.
  /// The background is `multAlpha(getColor(colorKey), alpha)` (line 41).
  ///
  /// Dark detection uses the resolved *key* color, not the ambient palette:
  /// `computePerceivedBrightness(color) < 0.721` (lines 34-37). Dark set
  /// (lines 43-46): strokes `0x28FFFFFF` / `0x14FFFFFF`, shadow `0`; light
  /// set (lines 47-51): white / white, shadow `0x20000000`. Stroke widths
  /// and shadow metrics stay at the drawable defaults — the Java themed
  /// provider is a plain `BlurredBackgroundColorProvider`, so it never
  /// overrides them.
  factory GlassSurfaceStyle.themed({
    required TelegramResources resources,
    required int colorKey,
    double? alpha,
    GlassTier tier = GlassTier.liquid,
  }) {
    final double resolvedAlpha =
        alpha ?? (tier == GlassTier.liquid ? kGlassTintAlphaLiquid : kGlassTintAlphaFrosted);
    final int themeColor = resources.getColor(colorKey).toARGB32();
    final bool dark = isDarkColor(themeColor);
    return GlassSurfaceStyle(
      backgroundColor: Color(multAlpha(themeColor, resolvedAlpha)),
      strokeColorTop: Color(dark ? kGlassStrokeTopColorDark : kGlassStrokeTopColorLight),
      strokeColorBottom: Color(dark ? kGlassStrokeBottomColorDark : kGlassStrokeBottomColorLight),
      shadowColor: Color(dark ? kGlassShadowColorDark : kGlassShadowColorLight),
      tintAlpha: resolvedAlpha,
    );
  }

  /// The tint painted over (liquid: inside the shader of) the blurred
  /// backdrop — `getBackgroundColor()`. Usually non-opaque.
  final Color backgroundColor;

  /// Top hairline color — `getStrokeColorTop()`.
  final Color strokeColorTop;

  /// Bottom hairline color — `getStrokeColorBottom()`.
  final Color strokeColorBottom;

  /// Drop-shadow color — `getShadowColor()`; transparent disables the shadow.
  final Color shadowColor;

  /// Top hairline width in logical dp — `getStrokeWidthTop()`.
  final double strokeWidthTop;

  /// Bottom hairline width in logical dp — `getStrokeWidthBottom()`.
  final double strokeWidthBottom;

  /// Shadow blur radius in logical dp — `getShadowRadius()`.
  final double shadowRadius;

  /// Shadow x offset in logical dp — `getShadowDx()`.
  final double shadowDx;

  /// Shadow y offset in logical dp — `getShadowDy()`.
  final double shadowDy;

  /// The opacity of the recipe's tint: the multiplier the recipe applied to
  /// its theme color (0.85 / 0.76 themed, or a recipe-specific value), the
  /// alpha of a fixed-hex background, 1.0 for the opaque blur-disabled
  /// fallbacks, and 0.0 when the recipe paints no background at all.
  ///
  /// [backgroundColor] already carries this alpha; the separate field
  /// preserves the un-quantized recipe value for renderers that re-derive
  /// the tint (e.g. crossfading against a differently-tinted backdrop).
  final double tintAlpha;

  /// Whether [strokeWidthTop]/[strokeWidthBottom] are *physical* pixels
  /// instead of logical dp. Almost every Java recipe wraps its widths in
  /// `dpf2()` at draw time (making logical dp the natural port unit), but
  /// `searchFloatingDate` passes a raw `1` px
  /// (BlurredBackgroundProviderImpl.java:114) — the renderer divides by the
  /// devicePixelRatio at draw time when this is set, keeping the hairline
  /// exactly one physical pixel on every density, as on Android.
  final bool strokeWidthPhysicalPx;

  /// Copy with the given fields replaced.
  GlassSurfaceStyle copyWith({
    Color? backgroundColor,
    Color? strokeColorTop,
    Color? strokeColorBottom,
    Color? shadowColor,
    double? strokeWidthTop,
    double? strokeWidthBottom,
    double? shadowRadius,
    double? shadowDx,
    double? shadowDy,
    double? tintAlpha,
    bool? strokeWidthPhysicalPx,
  }) {
    return GlassSurfaceStyle(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      strokeColorTop: strokeColorTop ?? this.strokeColorTop,
      strokeColorBottom: strokeColorBottom ?? this.strokeColorBottom,
      shadowColor: shadowColor ?? this.shadowColor,
      strokeWidthTop: strokeWidthTop ?? this.strokeWidthTop,
      strokeWidthBottom: strokeWidthBottom ?? this.strokeWidthBottom,
      shadowRadius: shadowRadius ?? this.shadowRadius,
      shadowDx: shadowDx ?? this.shadowDx,
      shadowDy: shadowDy ?? this.shadowDy,
      tintAlpha: tintAlpha ?? this.tintAlpha,
      strokeWidthPhysicalPx:
          strokeWidthPhysicalPx ?? this.strokeWidthPhysicalPx,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassSurfaceStyle &&
      other.backgroundColor == backgroundColor &&
      other.strokeColorTop == strokeColorTop &&
      other.strokeColorBottom == strokeColorBottom &&
      other.shadowColor == shadowColor &&
      other.strokeWidthTop == strokeWidthTop &&
      other.strokeWidthBottom == strokeWidthBottom &&
      other.shadowRadius == shadowRadius &&
      other.shadowDx == shadowDx &&
      other.shadowDy == shadowDy &&
      other.tintAlpha == tintAlpha &&
      other.strokeWidthPhysicalPx == strokeWidthPhysicalPx;

  @override
  int get hashCode => Object.hash(
        backgroundColor,
        strokeColorTop,
        strokeColorBottom,
        shadowColor,
        strokeWidthTop,
        strokeWidthBottom,
        shadowRadius,
        shadowDx,
        shadowDy,
        tintAlpha,
        strokeWidthPhysicalPx,
      );

  @override
  String toString() =>
      'GlassSurfaceStyle(backgroundColor: $backgroundColor, '
      'strokeColorTop: $strokeColorTop, strokeColorBottom: $strokeColorBottom, '
      'shadowColor: $shadowColor, '
      'strokeWidthTop: $strokeWidthTop, strokeWidthBottom: $strokeWidthBottom'
      '${strokeWidthPhysicalPx ? ' (physical px)' : ''}, '
      'shadowRadius: $shadowRadius, shadowDx: $shadowDx, shadowDy: $shadowDy, '
      'tintAlpha: $tintAlpha)';
}

/// Fluent port of `BlurredBackgroundProviderBuilder`
/// (BlurredBackgroundProviderBuilder.java:10-126).
///
/// Color setters take Java's `(light, dark)` argument order (lines 29-42);
/// the pair is resolved by [TelegramResources.isDark] at [build] time, the
/// port of the Java builder's `isDark()` which delegates to the resources
/// provider (lines 118-121; the `instanceof DarkThemeResourceProvider`
/// operand there is dead code — `a || b ? c : d` parses as `(a || b) ? c : d`
/// and a non-null provider always reaches `resourcesProvider.isDark()`).
///
/// Constructor defaults (lines 15-16): shadow layer `(1, 0, 1/3)`dp, stroke
/// widths `(1, 2/3)`dp. Unset colors resolve to transparent (the Java
/// `get(provider, 0)` default, lines 114-116).
///
/// [setTintAlpha] is a Dart-side addition: Java surfaces recompute their
/// recipe alpha from LiteMode on every query, while the resolved
/// [GlassSurfaceStyle] records it once for downstream renderers.
class GlassSurfaceStyleBuilder {
  /// Creates a builder resolving against [resources]
  /// (the Java `resourcesProvider` constructor argument, lines 13-17).
  GlassSurfaceStyleBuilder(this.resources);

  /// The palette every color pair and the background resolver read from.
  final TelegramResources resources;

  ({int light, int dark})? _shadowColor;
  ({int light, int dark})? _strokeColorTop;
  ({int light, int dark})? _strokeColorBottom;
  GlassBackgroundColorProvider? _backgroundColor;
  double _strokeWidthTop = kGlassStrokeWidthTopDp;
  double _strokeWidthBottom = kGlassStrokeWidthBottomDp;
  double _shadowRadius = kGlassShadowRadiusDp;
  double _shadowDx = kGlassShadowDxDp;
  double _shadowDy = kGlassShadowDyDp;
  double _tintAlpha = 0.0;
  bool _strokeWidthPhysicalPx = false;

  /// Sets the shadow color pair — `setShadowColor(light, dark)` (lines 29-32).
  GlassSurfaceStyleBuilder setShadowColor(int light, int dark) {
    _shadowColor = (light: light, dark: dark);
    return this;
  }

  /// Sets the top hairline pair — `setStrokeColorTop(light, dark)`
  /// (lines 34-37).
  GlassSurfaceStyleBuilder setStrokeColorTop(int light, int dark) {
    _strokeColorTop = (light: light, dark: dark);
    return this;
  }

  /// Sets the bottom hairline pair — `setStrokeColorBottom(light, dark)`
  /// (lines 39-42).
  GlassSurfaceStyleBuilder setStrokeColorBottom(int light, int dark) {
    _strokeColorBottom = (light: light, dark: dark);
    return this;
  }

  /// Sets the background resolver — `setBackgroundColor(ColorProvider)`
  /// (lines 44-47).
  GlassSurfaceStyleBuilder setBackgroundColor(GlassBackgroundColorProvider provider) {
    _backgroundColor = provider;
    return this;
  }

  /// Sets the shadow metrics in logical dp — `setShadowLayer(radius, dx, dy)`
  /// (lines 49-54).
  GlassSurfaceStyleBuilder setShadowLayer(double radius, double dx, double dy) {
    _shadowRadius = radius;
    _shadowDx = dx;
    _shadowDy = dy;
    return this;
  }

  /// Sets the hairline widths in logical dp — `setStrokeWidth(top, bottom)`
  /// (lines 56-60). Pass [physicalPx] for the one Java recipe whose widths
  /// are raw physical px, not `dpf2()`-wrapped
  /// (`searchFloatingDate`, BlurredBackgroundProviderImpl.java:114) — see
  /// [GlassSurfaceStyle.strokeWidthPhysicalPx].
  GlassSurfaceStyleBuilder setStrokeWidth(
    double top,
    double bottom, {
    bool physicalPx = false,
  }) {
    _strokeWidthTop = top;
    _strokeWidthBottom = bottom;
    _strokeWidthPhysicalPx = physicalPx;
    return this;
  }

  /// Records the recipe's tint opacity in the built style
  /// (see [GlassSurfaceStyle.tintAlpha]); Dart-side addition, no Java analog.
  GlassSurfaceStyleBuilder setTintAlpha(double alpha) {
    _tintAlpha = alpha;
    return this;
  }

  /// Resolves every pair against [TelegramResources.isDark] and returns the
  /// immutable style — the eager analog of Java `build()` returning the live
  /// provider (lines 110-112).
  GlassSurfaceStyle build() {
    final bool isDark = resources.isDark;
    int resolve(({int light, int dark})? pair) =>
        pair == null ? 0 : (isDark ? pair.dark : pair.light);
    return GlassSurfaceStyle(
      backgroundColor: Color(_backgroundColor?.call(resources, isDark) ?? 0),
      strokeColorTop: Color(resolve(_strokeColorTop)),
      strokeColorBottom: Color(resolve(_strokeColorBottom)),
      shadowColor: Color(resolve(_shadowColor)),
      strokeWidthTop: _strokeWidthTop,
      strokeWidthBottom: _strokeWidthBottom,
      shadowRadius: _shadowRadius,
      shadowDx: _shadowDx,
      shadowDy: _shadowDy,
      tintAlpha: _tintAlpha,
      strokeWidthPhysicalPx: _strokeWidthPhysicalPx,
    );
  }
}
