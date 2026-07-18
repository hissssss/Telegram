// Pure geometry for liquid-glass surfaces.
//
// Port of the `Props` inner class (bounds/padding/radii/stroke-ring state),
// the static `drawStroke` clip-band math, the shadow-layer defaults, and
// `getOutline` from
// `java/org/telegram/ui/Components/blur3/drawable/BlurredBackgroundDrawable.java`,
// plus the corner-radius clamps of
// `java/org/telegram/ui/Components/blur3/LiquidGlassEffect.java` (lines 56-65).
//
// No widgets and no BuildContext: inputs are logical-pixel rects and radii,
// outputs are `dart:ui` geometry (RRect / Path / Rect / MaskFilter) consumed
// by the glass render objects in their shadow -> backdrop -> child -> strokes
// paint order (ARCHITECTURE.md section 3.2). Android's `Props.bounds` is an
// int `Rect`; this port keeps doubles — pixel snapping, when wanted, is the
// caller's job via `TgDimens.fidelity`.
//
// Stroke-band math, verified against the Java sources:
//
// * The static `drawStroke` (BlurredBackgroundDrawable.java:392-490) clips the
//   top hairline to the band `top .. clamp(top + radii[0]*2, top, bottom)`
//   (line 410) and the bottom hairline to
//   `clamp(bottom - radii[4]*2, top, bottom) .. bottom` (line 451). The top
//   band is keyed off the TOP-LEFT radius (`radii[0]`) and the bottom band off
//   the BOTTOM-RIGHT radius (`radii[4]`) even when the radii differ per
//   corner — an upstream quirk that is preserved here.
// * The software rings (`Props.build`, lines 260-281) are filled paths: an
//   outer round-rect plus a second round-rect whose leading edge is inset by
//   the stroke width, resolved with the even-odd rule.
// * This port follows ARCHITECTURE.md section 3.2 step 3, which synthesizes
//   the two: ring = evenOdd(outer round-rect, copy shifted inward by the
//   stroke width) intersected with the `drawStroke` clamp band. With a zero
//   corner radius the band is empty and no hairline is produced — exactly
//   like Android, where `drawStroke`'s `clipRect` returns false (line 410)
//   and the nine-patch path gates on `radii[0] > 0` / `radii[4] > 0`
//   (lines 815, 834).
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;

import '../foundation/blur_math.dart';
import '../tokens/glass_metrics.g.dart';

/// Port of `androidx.core.math.MathUtils.clamp(value, min, max)` — the clamp
/// used by `drawStroke`. Unlike `dart:ui`'s `clampDouble` it tolerates an
/// inverted `min > max` range (possible when padding exceeds the bounds),
/// returning `max` — the resulting inverted band is empty, so nothing draws,
/// matching Android's empty-clip behavior.
double _clampJava(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);

/// Per-corner radii of a glass surface, in the Java `setRadius(topLeft,
/// topRight, bottomRight, bottomLeft)` parameter order
/// (BlurredBackgroundDrawable.java:108-131).
///
/// The Java `Props` stores 8 floats (an x/y pair per corner) but every setter
/// writes the same value into both halves of a pair, so a corner is always
/// circular and four doubles model it exactly.
@immutable
class GlassRadii {
  /// Creates per-corner radii; parameter order matches the Java `setRadius`.
  const GlassRadii({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// All four corners at [radius] — the Java `setRadius(float radius)`.
  const GlassRadii.all(double radius)
    : this(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius);

  /// Square corners.
  static const GlassRadii zero = GlassRadii.all(0);

  /// Top-left corner radius (Java `radii[0..1]`).
  final double topLeft;

  /// Top-right corner radius (Java `radii[2..3]`).
  final double topRight;

  /// Bottom-right corner radius (Java `radii[4..5]`).
  final double bottomRight;

  /// Bottom-left corner radius (Java `radii[6..7]`).
  final double bottomLeft;

  /// Whether all four corners share one radius — the Java `radiiAreSame`
  /// (BlurredBackgroundDrawable.java:358-366).
  bool get isUniform => topLeft == topRight && topLeft == bottomRight && topLeft == bottomLeft;

  /// Copy with the bottom corners zeroed — the clip-radii half of
  /// `setRadius(..., forceBottomZero: true)`
  /// (BlurredBackgroundDrawable.java:119-131).
  GlassRadii get withBottomZero =>
      GlassRadii(topLeft: topLeft, topRight: topRight, bottomRight: 0, bottomLeft: 0);

  /// The shader `radius` uniform packing **(RB, RT, LB, LT)** —
  /// `LiquidGlassEffect.java:93`, matching the SDF's per-corner selection.
  ///
  /// Component order corresponds to the generated float slots
  /// `kUniformRadiusRightBottom`, `kUniformRadiusRightTop`,
  /// `kUniformRadiusLeftBottom`, `kUniformRadiusLeftTop` of
  /// `tokens/liquid_glass_uniforms.g.dart`. This packing is the #1 silent
  /// corruption hazard of the port (ARCHITECTURE.md section 3.3) — never
  /// reorder it.
  List<double> get shaderQuad => <double>[bottomRight, topRight, bottomLeft, topLeft];

  /// Vertical-pair rescale, port of `LiquidGlassEffect.update`
  /// (LiquidGlassEffect.java:56-65).
  ///
  /// If a left or right vertical pair sums to **more than** [height]
  /// (strict `>`), both members are scaled proportionally so the pair sums to
  /// exactly [height]. There is no horizontal counterpart — Android never
  /// clamps against the width.
  GlassRadii rescaleVerticalPairs(double height) {
    double lt = topLeft;
    double rt = topRight;
    double rb = bottomRight;
    double lb = bottomLeft;
    if (lt + lb > height) {
      final double a = lt / (lt + lb);
      lt = height * a;
      lb = height * (1.0 - a);
    }
    if (rt + rb > height) {
      final double a = rt / (rt + rb);
      rt = height * a;
      rb = height * (1.0 - a);
    }
    return GlassRadii(topLeft: lt, topRight: rt, bottomRight: rb, bottomLeft: lb);
  }

  /// The `min(width, height) / 2` uniform cap of `Props.build`
  /// (BlurredBackgroundDrawable.java:253-258) and `getOutline` (line 342).
  ///
  /// Only applies when [isUniform]: a shared radius above half the smaller
  /// bounds extent is capped to it. Non-uniform radii are returned unchanged,
  /// exactly as in Java.
  GlassRadii capUniform(double width, double height) {
    if (!isUniform) {
      return this;
    }
    final double radiusMax = math.min(width, height) / 2;
    return topLeft > radiusMax ? GlassRadii.all(radiusMax) : this;
  }

  /// This radii set applied to [rect] as a `dart:ui` [RRect] with circular
  /// corners.
  RRect toRRect(Rect rect) => RRect.fromRectAndCorners(
    rect,
    topLeft: Radius.circular(topLeft),
    topRight: Radius.circular(topRight),
    bottomRight: Radius.circular(bottomRight),
    bottomLeft: Radius.circular(bottomLeft),
  );

  @override
  bool operator ==(Object other) =>
      other is GlassRadii &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() => 'GlassRadii(tl: $topLeft, tr: $topRight, br: $bottomRight, bl: $bottomLeft)';
}

/// Immutable geometry of one glass surface — the port of
/// `BlurredBackgroundDrawable.Props` (BlurredBackgroundDrawable.java:217-311).
///
/// Inputs: the surface [bounds], per-corner [clipRadii] (plus the shader-only
/// [shaderRadii] set), a symmetric [padding], the hairline stroke widths and
/// the drop-shadow layer parameters. Everything else — the padded rect, the
/// outer round-rect, the even-odd stroke rings, the clamp bands, the shadow
/// path/mask — is derived on demand.
///
/// ## The `forceBottomZero` dual-radii quirk
///
/// `setRadius(topLeft, topRight, bottomRight, bottomLeft, forceBottomZero)`
/// (BlurredBackgroundDrawable.java:119-131) zeroes the **clip** radii of the
/// bottom corners while the **shader** radii keep the un-forced values. The
/// clip path, outline, and bottom stroke ring go square, but the refraction
/// SDF still bends light around rounded bottom corners — used by panels that
/// sit flush against the keyboard. Both sets are exposed here: [clipRadii]
/// drives every path/band in this class, [shaderRadii] (via
/// [shaderRadiusQuad]) is what the uniform packer must feed slot
/// `u_radius`.
///
/// (The stateful 4-arg Java overload `setRadius(tl, tr, br, bl)` at lines
/// 108-117 updates only the clip radii and leaves any previously-set shader
/// radii stale; being an immutable value type, this port has no analog of
/// that — the 5-arg semantics above are the modeled ones.)
@immutable
class GlassGeometry {
  /// Creates the geometry for one glass surface.
  ///
  /// [radii] follows the Java `setRadius(topLeft, topRight, bottomRight,
  /// bottomLeft, forceBottomZero)`: with [forceBottomZero] the clip radii get
  /// square bottom corners while the shader radii keep [radii] unchanged.
  ///
  /// Stroke and shadow defaults are the constructor defaults of
  /// `BlurredBackgroundDrawable` (lines 46-53): stroke widths `dpf2(1)` top /
  /// `dpf2(2/3)` bottom, shadow radius `dpf2(1)`, dx `0`, dy `dpf2(1/3)` —
  /// all in logical px here.
  GlassGeometry({
    required this.bounds,
    GlassRadii radii = GlassRadii.zero,
    bool forceBottomZero = false,
    this.padding = 0.0,
    this.strokeWidthTop = kGlassStrokeWidthTopDp,
    this.strokeWidthBottom = kGlassStrokeWidthBottomDp,
    this.shadowRadius = kGlassShadowRadiusDp,
    this.shadowDx = kGlassShadowDxDp,
    this.shadowDy = kGlassShadowDyDp,
  }) : clipRadii = forceBottomZero ? radii.withBottomZero : radii,
       shaderRadii = radii;

  /// The un-padded surface bounds (the Java drawable bounds).
  final Rect bounds;

  /// The corner radii of every clip/stroke/outline path — the Java
  /// `Props.radii`. Bottom corners are zero when constructed with
  /// `forceBottomZero`.
  final GlassRadii clipRadii;

  /// The corner radii of the refraction shader — the Java `Props.shaderRadii`.
  /// Keeps the un-forced bottom radii under `forceBottomZero`.
  final GlassRadii shaderRadii;

  /// Symmetric inset applied to [bounds] — the Java `Props.padding`.
  final double padding;

  /// Top hairline width — `Props.strokeWidthTop`, default `dpf2(1)`.
  final double strokeWidthTop;

  /// Bottom hairline width — `Props.strokeWidthBottom`, default `dpf2(2/3)`.
  final double strokeWidthBottom;

  /// Shadow blur radius — `shadowLayerRadius`, default `dpf2(1)`.
  final double shadowRadius;

  /// Shadow x offset — `shadowLayerDx`, default `0`.
  final double shadowDx;

  /// Shadow y offset — `shadowLayerDy`, default `dpf2(1/3)`.
  final double shadowDy;

  /// [bounds] inset by [padding] on all sides — `Props.boundsWithPadding`
  /// (BlurredBackgroundDrawable.java:241-242).
  Rect get boundsWithPadding => bounds.deflate(padding);

  /// Whether the clip radii are uniform — `Props.radiiAreSame`.
  bool get radiiAreSame => clipRadii.isUniform;

  /// `min(width, height) / 2` of [boundsWithPadding] — the `radiusMax` of
  /// `Props.build` (line 253).
  double get radiusMax {
    final Rect rect = boundsWithPadding;
    return math.min(rect.width, rect.height) / 2;
  }

  /// The outer rounded rect: [boundsWithPadding] under [clipRadii].
  ///
  /// Radii are stored raw; degenerate combinations (sums exceeding an edge)
  /// are proportionally scaled by the engine when painted, matching Android's
  /// `Path.addRoundRect` behavior.
  RRect get outerRRect => clipRadii.toRRect(boundsWithPadding);

  /// The fill/clip path — `Props.path` (lines 244-251).
  Path get outerPath => Path()..addRRect(outerRRect);

  /// [shaderRadii] in the shader's **(RB, RT, LB, LT)** uniform packing —
  /// see [GlassRadii.shaderQuad] and the `forceBottomZero` note on this
  /// class.
  ///
  /// Raw values: the uniform packer is responsible for
  /// [GlassRadii.rescaleVerticalPairs] against the shader node height, as
  /// `LiquidGlassEffect.update` does.
  List<double> get shaderRadiusQuad => shaderRadii.shaderQuad;

  /// Clamp band of the top hairline:
  /// `top .. clamp(top + topLeftRadius * 2, top, bottom)` over the full width
  /// (drawStroke, BlurredBackgroundDrawable.java:410). Empty when the
  /// top-left clip radius is zero — square corners draw no hairline.
  Rect get strokeBandTop {
    final Rect rect = boundsWithPadding;
    return Rect.fromLTRB(
      rect.left,
      rect.top,
      rect.right,
      _clampJava(rect.top + clipRadii.topLeft * 2, rect.top, rect.bottom),
    );
  }

  /// Clamp band of the bottom hairline:
  /// `clamp(bottom - bottomRightRadius * 2, top, bottom) .. bottom`
  /// (drawStroke, BlurredBackgroundDrawable.java:451). Keyed off the
  /// bottom-RIGHT radius (Java `radii[4]`), preserving the upstream quirk.
  Rect get strokeBandBottom {
    final Rect rect = boundsWithPadding;
    return Rect.fromLTRB(
      rect.left,
      _clampJava(rect.bottom - clipRadii.bottomRight * 2, rect.top, rect.bottom),
      rect.right,
      rect.bottom,
    );
  }

  /// The top hairline ring, to be filled (not stroked) with the top stroke
  /// color: evenOdd(outer round-rect, copy shifted **down** by
  /// [strokeWidthTop]) intersected with [strokeBandTop]
  /// (ARCHITECTURE.md section 3.2 step 3; band per drawStroke line 410,
  /// tmpRadii staging per Props.build lines 255-267).
  ///
  /// Empty when the band or the stroke width is empty. A fresh [Path] is
  /// built per call — cache the [GlassGeometry] and reuse per frame.
  Path get strokeRingTop => _strokeRing(isTop: true);

  /// The bottom hairline ring, mirrored: evenOdd(outer round-rect, copy
  /// shifted **up** by [strokeWidthBottom]) intersected with
  /// [strokeBandBottom] (Props.build lines 269-281, drawStroke line 451).
  Path get strokeRingBottom => _strokeRing(isTop: false);

  /// The drop-shadow silhouette: [outerPath] translated by
  /// ([shadowDx], [shadowDy]) — the Android `setShadowLayer` offset applied
  /// as a path shift (ARCHITECTURE.md section 3.2 step 1).
  Path get shadowPath => outerPath.shift(Offset(shadowDx, shadowDy));

  /// Gaussian sigma of the shadow blur: `radiusToSigma(shadowRadius)` — the
  /// hwui radius-to-sigma mapping from `foundation/blur_math.dart`.
  double get shadowSigma => radiusToSigma(shadowRadius);

  /// The shadow [MaskFilter], or null when the blur is zero.
  MaskFilter? get shadowMaskFilter =>
      shadowSigma > 0 ? MaskFilter.blur(BlurStyle.normal, shadowSigma) : null;

  /// Port of `getOutline` (BlurredBackgroundDrawable.java:338-356): the
  /// view-outline path over [boundsWithPadding]. Uniform radii are capped at
  /// `min(width, height) / 2` (line 342); non-uniform radii are used raw as
  /// a convex round-rect path.
  Path get outlinePath {
    final Rect rect = boundsWithPadding;
    final GlassRadii capped = clipRadii.capUniform(rect.width, rect.height);
    return Path()..addRRect(capped.toRRect(rect));
  }

  /// The `tmpRadii` staging of `Props.build` (lines 255-273): keep the
  /// band-side corner pair, zero the far pair, and cap the kept pair at
  /// [radiusMax] when the radii are uniform and overflow it.
  GlassRadii _bandRadii({required bool isTop}) {
    final bool cap = radiiAreSame && clipRadii.topLeft > radiusMax;
    if (isTop) {
      return GlassRadii(
        topLeft: cap ? radiusMax : clipRadii.topLeft,
        topRight: cap ? radiusMax : clipRadii.topRight,
        bottomRight: 0,
        bottomLeft: 0,
      );
    }
    return GlassRadii(
      topLeft: 0,
      topRight: 0,
      bottomRight: cap ? radiusMax : clipRadii.bottomRight,
      bottomLeft: cap ? radiusMax : clipRadii.bottomLeft,
    );
  }

  Path _strokeRing({required bool isTop}) {
    final Rect rect = boundsWithPadding;
    final double strokeWidth = isTop ? strokeWidthTop : strokeWidthBottom;
    final Rect band = isTop ? strokeBandTop : strokeBandBottom;
    if (rect.isEmpty || strokeWidth <= 0 || band.isEmpty) {
      return Path();
    }
    final RRect outer = _bandRadii(isTop: isTop).toRRect(rect);
    final RRect shifted = outer.shift(Offset(0, isTop ? strokeWidth : -strokeWidth));
    final Path ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(outer)
      ..addRRect(shifted);
    return Path.combine(PathOperation.intersect, ring, Path()..addRect(band));
  }

  @override
  bool operator ==(Object other) =>
      other is GlassGeometry &&
      other.bounds == bounds &&
      other.clipRadii == clipRadii &&
      other.shaderRadii == shaderRadii &&
      other.padding == padding &&
      other.strokeWidthTop == strokeWidthTop &&
      other.strokeWidthBottom == strokeWidthBottom &&
      other.shadowRadius == shadowRadius &&
      other.shadowDx == shadowDx &&
      other.shadowDy == shadowDy;

  @override
  int get hashCode => Object.hash(
    bounds,
    clipRadii,
    shaderRadii,
    padding,
    strokeWidthTop,
    strokeWidthBottom,
    shadowRadius,
    shadowDx,
    shadowDy,
  );

  @override
  String toString() =>
      'GlassGeometry(bounds: $bounds, clipRadii: $clipRadii, '
      'shaderRadii: $shaderRadii, padding: $padding)';
}
