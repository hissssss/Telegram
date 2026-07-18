// The edge-fade mask of the glass system.
//
// Port of
// `java/org/telegram/ui/Components/blur3/BlurredBackgroundWithFadeDrawable.java`:
// a vertical alpha gradient masking the blurred backdrop with a DST_IN
// xfermode (line 56), used under floating bars so the blur fades out at the
// content edge. The general Java path is saveLayer + drawable +
// `drawRect(maskFadeGradientPaint)` (lines 177-186); the Flutter analog is a
// [ShaderMaskLayer] with [BlendMode.dstIn], which performs the same
// saveLayer + masked composite at the engine level while remaining correct
// over composited children (the glass panels themselves push layers).
//
// Gradient tables (`createGradient`, lines 211-230), evenly spaced stops:
//
//  * `opacity == false` (default, fade height dp(40), line 58): 5 stops,
//    alphas `0, 0x60*a/255, 0xB0*a/255, 0xE8*a/255, 0xFF*a/255`;
//  * `opacity == true` (MainTabs: dp(60), MainTabsActivity.java:352): 4
//    stops, alphas `0, 0x60*a/285, 0xB0*a/285, 0xE8*a/285` — note the 285
//    divisor, so the fully-faded-in region sits at ~0.813*a.
//
// Direction: Java encodes it in the sign of `fadeHeight` — positive scales
// the 1-px gradient downward from the top edge (lines 71-76), negative flips
// it and anchors it to the bottom (`offset = bounds.height() + fadeHeight`,
// lines 73-74, 112-114, 179-181). This port keeps [GlassEdgeFade.fadeHeight]
// positive and exposes the sign as [GlassFadeDirection].
library;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../tokens/glass_metrics.g.dart';

/// Which edge of the box the mask is transparent at — the sign of the Java
/// `fadeHeight`.
enum GlassFadeDirection {
  /// Positive Java `fadeHeight`: transparent at the TOP edge, fading in over
  /// `fadeHeight` px going down (the MainTabs bottom-bar fade — the backdrop
  /// blur appears toward the bottom of the screen).
  down,

  /// Negative Java `fadeHeight`: transparent at the BOTTOM edge, fading in
  /// over `fadeHeight` px going up, anchored to the bottom of the bounds.
  up,
}

/// The gradient color table of `createGradient(color, opacity)`
/// (BlurredBackgroundWithFadeDrawable.java:211-230): [color] with its alpha
/// scaled per stop in exact Java int arithmetic
/// (`ColorUtils.setAlphaComponent(color, numerator * alpha / divisor)`).
///
/// Stops are evenly spaced (Java passes `positions = null`); pair with
/// [fadeGradientStops].
List<Color> fadeGradientColors(Color color, {required bool opacity}) {
  final int argb = color.toARGB32();
  final int alpha = (argb >>> 24) & 0xFF;
  final List<int> numerators = opacity ? kFadeStopAlphasOpacity : kFadeStopAlphasDefault;
  final int divisor = opacity ? kFadeStopAlphaDivisorOpacity : kFadeStopAlphaDivisorDefault;
  return <Color>[
    for (final int numerator in numerators)
      Color((argb & 0x00FFFFFF) | ((numerator * alpha ~/ divisor) << 24)),
  ];
}

/// Evenly spaced stop positions for [count] colors — the meaning of Android's
/// `positions = null` (`LinearGradient` distributes colors uniformly), made
/// explicit because [ui.Gradient.linear] requires stops for more than two
/// colors.
List<double> fadeGradientStops(int count) {
  assert(count >= 2);
  return <double>[for (int i = 0; i < count; i++) i / (count - 1)];
}

/// The gradient axis in box-local coordinates: `from` is the transparent end
/// (stop 0), `to` is the fully-faded-in end at [fadeHeight] px from the
/// respective edge. [ui.TileMode.clamp] extends the last stop across the
/// rest of the box, exactly like the Java 1-px gradient scaled by the local
/// matrix (BlurredBackgroundWithFadeDrawable.java:71-76).
(Offset from, Offset to) fadeGradientAxis({
  required double fadeHeight,
  required GlassFadeDirection direction,
  required double height,
}) {
  return switch (direction) {
    GlassFadeDirection.down => (Offset.zero, Offset(0, fadeHeight)),
    GlassFadeDirection.up => (Offset(0, height), Offset(0, height - fadeHeight)),
  };
}

/// Masks its child with the blur3 edge-fade gradient — the widget port of
/// `BlurredBackgroundWithFadeDrawable` (ARCHITECTURE.md section 3.2: the
/// `GlassEdgeFade(60dp)` slot behind the tab bar).
class GlassEdgeFade extends SingleChildRenderObjectWidget {
  /// Creates an edge fade with the drawable defaults: `dp(40)` fade height,
  /// the 5-stop `opacity == false` table
  /// (BlurredBackgroundWithFadeDrawable.java:58).
  const GlassEdgeFade({
    super.key,
    this.fadeHeight = kFadeDefaultHeightDp,
    this.opacity = false,
    this.direction = GlassFadeDirection.down,
    super.child,
  }) : assert(fadeHeight > 0, 'Encode a negative Java fadeHeight as GlassFadeDirection.up.');

  /// The MainTabs variant: `setFadeHeight(dp(60), true)`
  /// (MainTabsActivity.java:352) — 60dp with the 4-stop /285 table.
  const GlassEdgeFade.mainTabs({
    super.key,
    this.direction = GlassFadeDirection.down,
    super.child,
  }) : fadeHeight = kFadeMainTabsHeightDp,
       opacity = true;

  /// Extent of the fade ramp in logical px, always positive (see
  /// [direction]).
  final double fadeHeight;

  /// Selects the stop table: false = 5 stops /255, true = 4 stops /285 (the
  /// Java parameter name is kept).
  final bool opacity;

  /// Which edge is transparent — the sign of the Java `fadeHeight`.
  final GlassFadeDirection direction;

  @override
  RenderGlassEdgeFade createRenderObject(BuildContext context) =>
      RenderGlassEdgeFade(fadeHeight: fadeHeight, opacity: opacity, direction: direction);

  @override
  void updateRenderObject(BuildContext context, RenderGlassEdgeFade renderObject) {
    renderObject
      ..fadeHeight = fadeHeight
      ..opacity = opacity
      ..direction = direction;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('fadeHeight', fadeHeight))
      ..add(FlagProperty('opacity', value: opacity, ifTrue: '4-stop /285 table'))
      ..add(EnumProperty<GlassFadeDirection>('direction', direction));
  }
}

/// Render object of [GlassEdgeFade]: pushes a [ShaderMaskLayer] whose shader
/// is the black fade gradient and whose blend mode is [BlendMode.dstIn] —
/// the engine-level form of Java's saveLayer + DST_IN gradient rect
/// (BlurredBackgroundWithFadeDrawable.java:177-186).
class RenderGlassEdgeFade extends RenderProxyBox {
  /// Creates the fade render object.
  RenderGlassEdgeFade({
    required this._fadeHeight,
    required this._opacity,
    required this._direction,
    RenderBox? child,
  }) : assert(_fadeHeight > 0),
       super(child);

  /// Extent of the fade ramp in logical px (positive; see [direction]).
  double get fadeHeight => _fadeHeight;
  double _fadeHeight;
  set fadeHeight(double value) {
    assert(value > 0);
    if (value == _fadeHeight) {
      return;
    }
    _fadeHeight = value;
    markNeedsPaint();
  }

  /// Selects the stop table (see [GlassEdgeFade.opacity]).
  bool get opacity => _opacity;
  bool _opacity;
  set opacity(bool value) {
    if (value == _opacity) {
      return;
    }
    _opacity = value;
    markNeedsPaint();
  }

  /// Which edge is transparent.
  GlassFadeDirection get direction => _direction;
  GlassFadeDirection _direction;
  set direction(GlassFadeDirection value) {
    if (value == _direction) {
      return;
    }
    _direction = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  ShaderMaskLayer? get layer => super.layer as ShaderMaskLayer?;

  /// The mask gradient for the current geometry, in box-local coordinates
  /// (the [ShaderMaskLayer] shader origin is the top-left of its mask rect).
  /// The mask color is black, as in the Java mask path
  /// (`createGradient(Color.BLACK, opacity)`, line 68) — only alpha matters
  /// under DST_IN.
  ui.Shader _buildMaskShader() {
    final (Offset from, Offset to) = fadeGradientAxis(
      fadeHeight: _fadeHeight,
      direction: _direction,
      height: size.height,
    );
    final List<Color> colors = fadeGradientColors(const Color(0xFF000000), opacity: _opacity);
    return ui.Gradient.linear(from, to, colors, fadeGradientStops(colors.length));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      layer = null;
      return;
    }
    assert(needsCompositing);
    layer ??= ShaderMaskLayer();
    layer!
      ..shader = _buildMaskShader()
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(layer!, super.paint, offset);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('fadeHeight', fadeHeight))
      ..add(FlagProperty('opacity', value: opacity, ifTrue: '4-stop /285 table'))
      ..add(EnumProperty<GlassFadeDirection>('direction', direction));
  }
}
