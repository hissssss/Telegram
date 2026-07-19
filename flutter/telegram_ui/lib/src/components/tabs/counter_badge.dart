// The tab counter badge with its punch-out ring.
//
// Port of the counter pass of `GlassTabView.dispatchDraw`
// (`java/org/telegram/ui/Components/glass/GlassTabView.java`, lines 167-218)
// plus the counter drawable setup (lines 98-103) and `setCounter`
// (lines 223-227):
//
// - the whole tab is rendered into an offscreen layer (`canvas.saveLayer`,
//   line 170) so that an outer rounded rect drawn with `Theme.PAINT_CLEAR`
//   (a CLEAR-xfermode paint, ui/ActionBar/Theme.java:10638-10640) can ERASE
//   the icon pixels around the badge — the "punch-out" ring through which
//   the glass backdrop shows (line 193);
// - geometry (lines 178-190): badge height 16dp, width
//   `max(16, textWidth + 8)`dp, inner radius 8dp, ring gap 1.33dp, outer
//   clear radius 9.333dp, centered at `(viewWidth / 2 + 11dp, 10dp)`;
// - text (lines 98-103): 10dp, `AndroidUtilities.bold()` (Roboto Medium,
//   `fonts/rmedium.ttf`), white, gravity center in the badge rect;
// - fill (line 208): `ColorUtils.blendARGB(key_telegram_color,
//   key_fill_RedNormal, errorFactor)`;
// - animation: appearance scales the whole badge (clear ring included)
//   about its center by the `isHasCounterAnimator` factor — a
//   `BoolAnimator(380ms, EASE_OUT_QUINT)` (lines 68, 167, 192); the error
//   blend animates with the same timing (lines 69, 208);
// - premium variant (lines 73, 167, 196-206, 229-231): the fill + text pass
//   is replaced by a round rect filled with the PremiumGradient main
//   gradient (matrix extent 96x16dp, `updateMainGradientMatrix`,
//   PremiumGradient.java:106-108 -> PremiumGradientTools.gradientMatrix,
//   lines 200-223 non-`exactly` branch) and a white 14dp star
//   (`R.drawable.star`, res/drawable/star.xml) centered on the badge; the
//   appearance factor is pinned to 1 (`usePremiumCounter ? 1f : ...`, line
//   167). The gradient is the 4-stop linear
//   `premiumGradient1..premiumGradient4` shader of
//   PremiumGradientTools.chekColors (PremiumGradient.java:29, 241-264,
//   c5 == 0 branch at line 258): stops [0, 0.5, 0.78, 1] along
//   `(0, 100) -> (150, 0)` in the 100-unit gradient space, CLAMP tiling.
//
// Not ported: `AnimatedTextDrawable`'s per-glyph text/width crossfade when
// the count changes while visible (the text swaps instantly here), the
// `attachScale` multiplier of the attach-panel tabs (line 167), and the
// rest of the PremiumGradient class (only the main-gradient shader math
// used by this badge is ported).
library;

import 'dart:math' as math;
import 'dart:ui' as ui show Gradient, Shader;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../foundation/tg_curves.dart';
import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';
import 'glass_tab.dart' show blendArgb;

/// The extracted constants of the counter badge pass
/// (GlassTabView.java:98-103, 175-213) — every value is logical px, 1:1 with
/// Android dp.
abstract final class CounterBadge {
  /// Badge (inner rect) height: `dpf2(16)` (GlassTabView.java:181).
  static const double height = 16.0;

  /// Minimum badge width — the height reused as the floor of
  /// `Math.max(height, textWidth + dp(8))` (GlassTabView.java:182).
  static const double minWidth = 16.0;

  /// Horizontal text padding added to the measured text width: `dp(8)`
  /// (GlassTabView.java:182).
  static const double textPadding = 8.0;

  /// Inner (fill) corner radius: `dpf2(8)` (GlassTabView.java:184).
  static const double innerRadius = 8.0;

  /// Outer (punch-out clear) corner radius: `dpf2(9.333)`
  /// (GlassTabView.java:183).
  static const double outerRadius = 9.333;

  /// Ring gap between the cleared outer rect and the filled inner rect:
  /// `dpf2(1.33)` (GlassTabView.java:178, 185-190, 194).
  static const double punchGap = 1.33;

  /// Badge center x offset from the horizontal center of the decorated box:
  /// `cx = viewWidth / 2 + dpf2(11)` (GlassTabView.java:179).
  static const double centerOffsetX = 11.0;

  /// Badge center y from the top of the decorated box: `cy = dpf2(10)`
  /// (GlassTabView.java:180).
  static const double centerY = 10.0;

  /// Counter text size: `counter.setTextSize(dp(10))`
  /// (GlassTabView.java:103).
  static const double textSize = 10.0;

  /// Show/hide and error animators: `BoolAnimator(..., EASE_OUT_QUINT, 380)`
  /// (GlassTabView.java:68-69).
  static const Duration animationDuration = Duration(milliseconds: 380);

  /// Premium gradient matrix extent: `updateMainGradientMatrix(0, 0, dp(96),
  /// dp(16), 0, 0)` (GlassTabView.java:201).
  static const double premiumGradientWidth = 96.0;

  /// Premium gradient matrix height (GlassTabView.java:201).
  static const double premiumGradientHeight = 16.0;

  /// Premium star drawable size: `dp(14)`, centered at `(cx - 7, cy - 7)`
  /// (GlassTabView.java:203-205).
  static const double premiumStarSize = 14.0;

  /// The theme keys of the PremiumGradient main gradient, in shader order:
  /// `new PremiumGradientTools(Theme.key_premiumGradient1, ...2, ...3, ...4)`
  /// (PremiumGradient.java:29).
  static const List<int> premiumGradientKeys = <int>[
    TelegramColorKey.premiumGradient1,
    TelegramColorKey.premiumGradient2,
    TelegramColorKey.premiumGradient3,
    TelegramColorKey.premiumGradient4,
  ];

  /// The 4-color stop positions of the main gradient — the `c5 == 0` branch
  /// of PremiumGradientTools.chekColors: `new float[]{0, 0.5f, 0.78f, 1f}`
  /// (PremiumGradient.java:258).
  static const List<double> premiumGradientStops = <double>[
    0.0,
    0.5,
    0.78,
    1.0,
  ];

  /// Base gradient axis start in the 100-unit shader space:
  /// `(size * x1, size * y1)` with `size = 100`, `x1 = 0, y1 = 1`
  /// (PremiumGradient.java:35, 169, 258).
  static const Offset premiumGradientFrom = Offset(0.0, 100.0);

  /// Base gradient axis end: `(size * x2, size * y2)` with
  /// `x2 = 1.5, y2 = 0` (PremiumGradient.java:35, 169, 258).
  static const Offset premiumGradientTo = Offset(150.0, 0.0);

  /// The internal gradient-space size: `private final static int size = 100`
  /// (PremiumGradient.java:35).
  static const double _premiumGradientSize = 100.0;

  /// Star fill: `android:fillColor="#ffffff"` (res/drawable/star.xml:9) —
  /// the drawable is used untinted (GlassTabView.java:198, 206).
  static const Color premiumStarColor = Color(0xFFFFFFFF);

  /// Star vector viewport: `viewportWidth/Height = 513`
  /// (res/drawable/star.xml:5-6).
  static const double premiumStarViewport = 513.0;

  /// The local matrix of the main-gradient shader for a matrix extent of
  /// [width] x [height] at [offset] — the non-`exactly` branch of
  /// `PremiumGradientTools.gradientMatrix` (PremiumGradient.java:211-222):
  ///
  /// ```java
  /// int gradientHeight = height + height;
  /// matrix.postScale(width / 100f, gradientHeight / 100f, 75, 50);
  /// matrix.postTranslate(xOffset, -gradientHeight + yOffset);
  /// ```
  ///
  /// (Absolute x/y of the Java rect cancel out — only the extent matters.)
  /// For the badge's `updateMainGradientMatrix(0, 0, dp(96), dp(16), 0, 0)`
  /// (GlassTabView.java:201) this is scale(0.96, 0.32) + translate(3, 2),
  /// anchored — like the Java canvas-space shader — at the origin of the
  /// decorated box, not at the badge rect.
  static Matrix4 premiumGradientMatrix({
    double width = premiumGradientWidth,
    double height = premiumGradientHeight,
    Offset offset = Offset.zero,
  }) {
    final double gradientHeight = height + height;
    final double sx = width / _premiumGradientSize;
    final double sy = gradientHeight / _premiumGradientSize;
    // postScale(sx, sy, 75, sizeHalf) folded with
    // postTranslate(xOffset, -gradientHeight + yOffset).
    return Matrix4.identity()
      ..setEntry(0, 0, sx)
      ..setEntry(1, 1, sy)
      ..setEntry(0, 3, 75.0 * (1.0 - sx) + offset.dx)
      ..setEntry(1, 3, 50.0 * (1.0 - sy) - gradientHeight + offset.dy);
  }

  /// The main-gradient shader for resolved [colors] (the 4
  /// [premiumGradientKeys] colors, in order) — `LinearGradient(size * x1,
  /// size * y1, size * x2, size * y2, colors, {0, 0.5, 0.78, 1}, CLAMP)`
  /// (PremiumGradient.java:258) with the [premiumGradientMatrix] local
  /// matrix applied (`shader.setLocalMatrix`, line 221).
  static ui.Shader premiumGradientShader(
    List<Color> colors, {
    double width = premiumGradientWidth,
    double height = premiumGradientHeight,
    Offset offset = Offset.zero,
  }) {
    assert(colors.length == premiumGradientStops.length);
    return ui.Gradient.linear(
      premiumGradientFrom,
      premiumGradientTo,
      colors,
      premiumGradientStops,
      TileMode.clamp,
      premiumGradientMatrix(width: width, height: height, offset: offset)
          .storage,
    );
  }

  /// The star outline of `R.drawable.star` (res/drawable/star.xml) mapped
  /// into [bounds] — the path data is in the 513-unit viewport and scaled by
  /// `bounds.size / 513` (the Java `setBounds(x, y, x + dp(14), y + dp(14))`
  /// at GlassTabView.java:205 makes bounds a 14x14 square).
  static Path premiumStarPath(Rect bounds) {
    final Path path = Path()
      ..moveTo(247.137, 383.282)
      ..lineTo(162.895, 436.247)
      ..cubicTo(154.142, 441.751, 142.586, 439.116, 137.082, 430.363)
      ..cubicTo(134.375, 426.057, 133.536, 420.836, 134.758, 415.9)
      ..lineTo(148.409, 360.759)
      ..cubicTo(152.895, 342.636, 164.961, 327.32, 181.529, 318.716)
      ..lineTo(260.21, 277.857)
      ..cubicTo(264.456, 275.652, 266.111, 270.424, 263.906, 266.178)
      ..cubicTo(262.188, 262.871, 258.546, 261.032, 254.865, 261.615)
      ..lineTo(167.201, 275.479)
      ..cubicTo(146.263, 278.79, 124.929, 272.731, 108.858, 258.909)
      ..lineTo(75.1235, 229.894)
      ..cubicTo(67.2844, 223.152, 66.3952, 211.332, 73.1372, 203.493)
      ..cubicTo(76.3537, 199.754, 80.915, 197.436, 85.8316, 197.041)
      ..lineTo(185.693, 189.02)
      ..cubicTo(192.761, 188.452, 198.9, 183.94, 201.554, 177.366)
      ..lineTo(239.742, 82.7576)
      ..cubicTo(243.612, 73.1699, 254.521, 68.5349, 264.109, 72.4049)
      ..cubicTo(268.822, 74.3075, 272.559, 78.0443, 274.462, 82.7576)
      ..lineTo(312.649, 177.366)
      ..cubicTo(315.303, 183.94, 321.443, 188.452, 328.51, 189.02)
      ..lineTo(428.9, 197.083)
      ..cubicTo(439.206, 197.911, 446.89, 206.937, 446.062, 217.243)
      ..cubicTo(445.671, 222.105, 443.399, 226.622, 439.729, 229.833)
      ..lineTo(362.454, 297.445)
      ..cubicTo(357.243, 302.005, 354.974, 309.068, 356.555, 315.809)
      ..lineTo(380.184, 416.554)
      ..cubicTo(382.545, 426.621, 376.299, 436.695, 366.233, 439.056)
      ..cubicTo(361.359, 440.199, 356.231, 439.342, 351.993, 436.678)
      ..lineTo(267.066, 383.282)
      ..cubicTo(260.975, 379.453, 253.228, 379.453, 247.137, 383.282)
      ..close();
    final Matrix4 transform =
        Matrix4.translationValues(bounds.left, bounds.top, 0.0).multiplied(
      Matrix4.diagonal3Values(
        bounds.width / premiumStarViewport,
        bounds.height / premiumStarViewport,
        1.0,
      ),
    );
    return path.transform(transform.storage);
  }

  /// The counter text style: 10dp `AndroidUtilities.bold()` (Roboto Medium,
  /// `fonts/rmedium.ttf`, bundled by this package as the w500 family
  /// `RobotoMedium`), white (`counter.setTextColor(Color.WHITE)`,
  /// GlassTabView.java:99-103).
  static const TextStyle textStyle = TextStyle(
    fontSize: textSize,
    color: Color(0xFFFFFFFF),
    fontFamily: 'RobotoMedium',
    package: 'telegram_ui',
    fontWeight: FontWeight.w500,
  );

  /// Badge (inner rect) width for a measured [textWidth]:
  /// `Math.max(height, counter.getCurrentWidth() + dp(8))`
  /// (GlassTabView.java:182).
  static double widthFor(double textWidth) =>
      math.max(minWidth, textWidth + textPadding);
}

/// Paints the counter badge of GlassTabView.java:167-218 — usable standalone
/// through [CustomPaint], or composed over an icon by
/// [CounterBadgeDecoration] / [CounterBadgeLayer] (which sandwich the child
/// between the saveLayer and the badge pass so the clear ring actually
/// erases the icon).
///
/// [paint] is self-contained and safe anywhere: it bounds the
/// [BlendMode.clear] ring with its own `saveLayer` (the standalone analog of
/// GlassTabView.java:169-171/216-218), so the ring reads as transparency of
/// the painted picture rather than a hole in the whole scene. [paintBadge]
/// is the raw badge pass (lines 175-213 only) for embedders that already
/// hold an isolating layer open.
class CounterBadgePainter extends CustomPainter {
  /// Creates the painter. A [premium] painter requires the four resolved
  /// [premiumGradientColors] (see [CounterBadge.premiumGradientKeys]).
  CounterBadgePainter({
    required this.text,
    required this.color,
    required this.errorColor,
    this.visibility = 1.0,
    this.errorFactor = 0.0,
    this.premium = false,
    this.premiumGradientColors,
    this.center,
    TextPainter? counterPainter,
  }) : _externalCounterPainter = counterPainter,
       assert(visibility >= 0.0 && visibility <= 1.0),
       assert(errorFactor >= 0.0 && errorFactor <= 1.0),
       assert(
         !premium ||
             (premiumGradientColors != null &&
                 premiumGradientColors.length ==
                     CounterBadge.premiumGradientKeys.length),
         'premium: true requires the 4 resolved premiumGradient1..4 colors '
         '(PremiumGradient.java:29)',
       ),
       assert(
         counterPainter == null ||
             (counterPainter.text as TextSpan?)?.text == text,
         'counterPainter must be laid out for the same text',
       );

  /// The counter text (`counter.setText`, GlassTabView.java:224). May be
  /// empty (width falls back to [CounterBadge.minWidth]).
  final String text;

  /// Resolved `telegram_color` — the errorFactor-0 endpoint of the fill
  /// blend (GlassTabView.java:208).
  final Color color;

  /// Resolved `fill_RedNormal` — the errorFactor-1 endpoint of the fill
  /// blend (GlassTabView.java:208).
  final Color errorColor;

  /// Appearance factor in 0..1 — `isHasCounterAnimator.getFloatValue()`
  /// (GlassTabView.java:167): 0 paints nothing, in between scales the whole
  /// badge (clear ring included) about [centerFor] (line 192). A [premium]
  /// painter ignores it — see [effectiveVisibility].
  final double visibility;

  /// Error factor in 0..1 — `isHasCounterErrorAnimator.getFloatValue()`,
  /// blending the fill `telegram_color` -> `fill_RedNormal`
  /// (GlassTabView.java:208).
  final double errorFactor;

  /// The premium variant (`setPremiumBadge`, GlassTabView.java:229-231):
  /// the fill + text pass is replaced by the PremiumGradient round rect and
  /// the white 14dp star (lines 196-206), and the appearance factor is
  /// pinned to 1 (line 167).
  final bool premium;

  /// Resolved [CounterBadge.premiumGradientKeys] colors, in shader order —
  /// required (asserted) when [premium] is true, ignored otherwise.
  final List<Color>? premiumGradientColors;

  /// The factor actually painted: `usePremiumCounter ? 1f :
  /// isHasCounterAnimator.getFloatValue()` (GlassTabView.java:167) — premium
  /// pins the badge visible regardless of [visibility].
  double get effectiveVisibility => premium ? 1.0 : visibility;

  /// Overrides the badge center. When null, the Java placement is used:
  /// `(size.width / 2 + 11, 10)` (GlassTabView.java:179-180) — correct when
  /// the painted box is the whole tab cell (whose horizontal center is the
  /// icon center). Pass an explicit center when decorating a bare icon.
  final Offset? center;

  /// Caller-owned laid-out painter (see [buildCounterPainter]); when set the
  /// painter allocates no text resources of its own. [CounterBadgeDecoration]
  /// passes one so its per-tick rebuilds reuse a single [TextPainter] instead
  /// of allocating (and never disposing) one per animation frame.
  final TextPainter? _externalCounterPainter;

  TextPainter? _textPainterCache;

  /// Builds and lays out the counter [TextPainter] — the port of the
  /// `AnimatedTextDrawable` configured at GlassTabView.java:98-103 (10dp
  /// Roboto Medium, white, gravity center). TextHeightBehavior pinned per
  /// ARCHITECTURE.md section 5. The caller owns (and must dispose) the
  /// returned painter.
  static TextPainter buildCounterPainter(String text) {
    return TextPainter(
      text: TextSpan(text: text, style: CounterBadge.textStyle),
      textDirection: TextDirection.ltr,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    )..layout();
  }

  /// The laid-out counter text: the caller-owned painter when provided,
  /// otherwise a lazily built one released by [dispose].
  TextPainter get _counter =>
      _externalCounterPainter ?? (_textPainterCache ??= buildCounterPainter(text));

  /// Releases the internally cached [TextPainter], if any (standalone use
  /// without a `counterPainter`). [CustomPainter] has no dispose lifecycle,
  /// so owners that construct painters directly should call this when done.
  void dispose() {
    _textPainterCache?.dispose();
    _textPainterCache = null;
  }

  /// Measured text width — `counter.getCurrentWidth()`
  /// (GlassTabView.java:182).
  double get textWidth => _counter.width;

  /// Badge (inner rect) width: `max(16, textWidth + 8)`
  /// (GlassTabView.java:182).
  double get badgeWidth => CounterBadge.widthFor(textWidth);

  /// The fill color: `ColorUtils.blendARGB(telegram_color, fill_RedNormal,
  /// errorFactor)` (GlassTabView.java:208) in exact Java int arithmetic
  /// ([blendArgb]).
  Color get fillColor => blendArgb(color, errorColor, errorFactor);

  /// The badge center for a painted box of [size]: [center] if set,
  /// otherwise `(size.width / 2 + 11, 10)` (GlassTabView.java:179-180).
  Offset centerFor(Size size) =>
      center ??
      Offset(size.width / 2.0 + CounterBadge.centerOffsetX,
          CounterBadge.centerY);

  /// The outer punch-out rect at full scale — the badge rect inflated by
  /// [CounterBadge.punchGap] on each side (GlassTabView.java:185-190).
  Rect punchRect(Size size) => Rect.fromCenter(
        center: centerFor(size),
        width: badgeWidth + 2.0 * CounterBadge.punchGap,
        height: CounterBadge.height + 2.0 * CounterBadge.punchGap,
      );

  /// The inner fill rect — [punchRect] inset by the gap
  /// (`tmpRectF.inset(gap, gap)`, GlassTabView.java:194).
  Rect fillRect(Size size) => punchRect(size).deflate(CounterBadge.punchGap);

  /// The offscreen-layer bounds for the punch-out. Java uses the whole tab
  /// view (`saveLayer(0, 0, viewWidth, height)`, GlassTabView.java:170); the
  /// port additionally unions in [punchRect] so a decorated box smaller than
  /// the tab cell (e.g. a bare 24x24 icon) does not clip the badge away —
  /// the appearance scale is <= 1 about the badge center, so the full-scale
  /// rect always covers the scaled one.
  Rect layerBounds(Size size) =>
      (Offset.zero & size).expandToInclude(punchRect(size));

  /// Standalone paint: the saveLayer sandwich of GlassTabView.java:168-171 /
  /// 216-218 around [paintBadge], with no child in between.
  @override
  void paint(Canvas canvas, Size size) {
    if (effectiveVisibility <= 0.0) {
      return;
    }
    canvas.saveLayer(layerBounds(size), Paint()); // L169-171 (null paint)
    paintBadge(canvas, size);
    canvas.restore(); // L216-218
  }

  /// The raw badge pass — GlassTabView.java:175-213 — assuming the caller
  /// holds an isolating layer open (so [BlendMode.clear] erases only that
  /// layer). Draws, in order: the outer clear round rect, then either the
  /// inner fill + centered counter text, or (premium, L196-206) the
  /// PremiumGradient fill + white star; all scaled by [effectiveVisibility]
  /// about the badge center.
  void paintBadge(Canvas canvas, Size size) {
    final double hasCounter = effectiveVisibility; // L167
    if (hasCounter <= 0.0) {
      return;
    }
    canvas.save(); // L176

    final Offset c = centerFor(size); // L179-180
    Rect rect = punchRect(size); // L185-190

    // canvas.scale(hasCounter, hasCounter, cx, cy) (L192).
    canvas.translate(c.dx, c.dy);
    canvas.scale(hasCounter, hasCounter);
    canvas.translate(-c.dx, -c.dy);

    // Punch-out: Theme.PAINT_CLEAR round rect, radius 9.333 (L193).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        const Radius.circular(CounterBadge.outerRadius),
      ),
      Paint()..blendMode = BlendMode.clear,
    );

    rect = rect.deflate(CounterBadge.punchGap); // L194

    if (premium) {
      // updateMainGradientMatrix(0, 0, dp(96), dp(16), 0, 0) +
      // drawRoundRect(tmpRectF, rInner, rInner, mainGradientPaint)
      // (L201-202). The shader lives in the local (canvas) space, exactly
      // like the Java view-space shader.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          const Radius.circular(CounterBadge.innerRadius),
        ),
        Paint()
          ..shader =
              CounterBadge.premiumGradientShader(premiumGradientColors!),
      );

      // Star: `int x = (int)(cx - dpf2(7f))` — Java truncates the origin to
      // whole px (L203-205) — then a 14x14 bounds draw (L205-206).
      final double half = CounterBadge.premiumStarSize / 2.0;
      final Rect starBounds = Rect.fromLTWH(
        (c.dx - half).truncateToDouble(),
        (c.dy - half).truncateToDouble(),
        CounterBadge.premiumStarSize,
        CounterBadge.premiumStarSize,
      );
      canvas.drawPath(
        CounterBadge.premiumStarPath(starBounds),
        Paint()..color = CounterBadge.premiumStarColor,
      );
    } else {
      // Fill: blend(telegram_color -> fill_RedNormal), radius 8 (L208-209).
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          const Radius.circular(CounterBadge.innerRadius),
        ),
        Paint()..color = fillColor,
      );

      // Text centered in the badge rect (counter.setBounds + gravity CENTER,
      // L101, L210-211).
      final TextPainter counter = _counter;
      counter.paint(
        canvas,
        c - Offset(counter.width / 2.0, counter.height / 2.0),
      );
    }

    canvas.restore(); // L213
  }

  @override
  bool shouldRepaint(CounterBadgePainter oldDelegate) =>
      text != oldDelegate.text ||
      color != oldDelegate.color ||
      errorColor != oldDelegate.errorColor ||
      visibility != oldDelegate.visibility ||
      errorFactor != oldDelegate.errorFactor ||
      premium != oldDelegate.premium ||
      !listEquals(premiumGradientColors, oldDelegate.premiumGradientColors) ||
      center != oldDelegate.center;
}

/// The unanimated punch-out compositor: paints [painter]'s badge over
/// [child] inside one shared offscreen layer, so the clear ring erases the
/// child — the exact structure of `GlassTabView.dispatchDraw`
/// (saveLayer L170, children L173, badge L175-213, restore L217).
///
/// Most callers want [CounterBadgeDecoration], which owns the 380ms
/// animators and theme lookups and builds this widget; use the layer
/// directly when driving the factors yourself (as the tab bar's Java-side
/// animators do).
class CounterBadgeLayer extends SingleChildRenderObjectWidget {
  /// Creates the layer around [child].
  const CounterBadgeLayer({super.key, required this.painter, super.child});

  /// The badge painter; when null or fully hidden
  /// ([CounterBadgePainter.effectiveVisibility] 0) the child paints
  /// unwrapped (Java only saveLayers `if (hasCounter > 0)`,
  /// GlassTabView.java:168-171).
  final CounterBadgePainter? painter;

  @override
  RenderCounterBadge createRenderObject(BuildContext context) =>
      RenderCounterBadge(painter: painter);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCounterBadge renderObject,
  ) {
    renderObject.painter = painter;
  }
}

/// Render object of [CounterBadgeLayer].
class RenderCounterBadge extends RenderProxyBox {
  /// Creates the render object.
  RenderCounterBadge({this._painter, RenderBox? child}) : super(child);

  /// The badge painter (null or `effectiveVisibility <= 0` paints the child
  /// only).
  CounterBadgePainter? get painter => _painter;
  CounterBadgePainter? _painter;
  set painter(CounterBadgePainter? value) {
    if (identical(value, _painter)) {
      return;
    }
    final CounterBadgePainter? old = _painter;
    _painter = value;
    if (value == null || old == null || value.shouldRepaint(old)) {
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final CounterBadgePainter? painter = _painter;
    if (painter == null || painter.effectiveVisibility <= 0.0) {
      // `if (hasCounter > 0)` — no layer, no badge (GlassTabView.java:168).
      super.paint(context, offset);
      return;
    }

    final RenderBox? child = this.child;
    if (child != null && child.needsCompositing) {
      // A composited child paints into its own engine layers, which a
      // canvas-level CLEAR in this picture cannot erase (and interleaving
      // canvas save/restore across a layer split would corrupt the
      // recording). Degrade gracefully: child as-is, badge in its own
      // bounded layer — the ring shows the child through it instead of the
      // backdrop.
      super.paint(context, offset);
      final Canvas canvas = context.canvas;
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      painter.paint(canvas, size);
      canvas.restore();
      return;
    }

    final Canvas canvas = context.canvas;
    // saveLayer(0, 0, viewWidth, height, null) (L169-171), bounds expanded
    // per CounterBadgePainter.layerBounds.
    canvas.saveLayer(painter.layerBounds(size).shift(offset), Paint());
    super.paint(context, offset); // super.dispatchDraw(canvas) (L173)
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    painter.paintBadge(canvas, size); // L175-213
    canvas.restore();
    canvas.restore(); // L216-218
  }
}

/// Composes the counter badge over any icon (or whole tab cell) with the
/// Java animation semantics — the widget port of `setCounter(text, isError,
/// animated)` (GlassTabView.java:223-227) plus the two 380ms EASE_OUT_QUINT
/// `BoolAnimator`s (lines 68-69):
///
/// - a non-empty [count] shows the badge; null/empty hides it. Changes
///   animate the appearance scale over 380ms ([TgCurves.easeOutQuint]); the
///   last non-empty text keeps painting while the badge scales out (the
///   `AnimatedTextDrawable` keeps its text through the hide);
/// - [error] animates the fill `telegram_color` -> `fill_RedNormal` with
///   the same timing;
/// - the initial state binds unanimated (factor snapped), like the
///   constructor-time `setCounter(..., animated: false)` calls.
///
/// The child is wrapped in a [CounterBadgeLayer] (not a plain Stack
/// overlay): the punch-out ring must ERASE the child's pixels inside a
/// shared offscreen layer, which sibling painting cannot do.
class CounterBadgeDecoration extends StatefulWidget {
  /// Creates the decoration.
  const CounterBadgeDecoration({
    super.key,
    required this.child,
    this.count,
    this.error = false,
    this.premium = false,
    this.center,
    this.resources,
  });

  /// The decorated content (typically the tab cell or its icon).
  final Widget child;

  /// The counter text (`setCounter`'s `text`, GlassTabView.java:223-225);
  /// null or empty hides the badge.
  final String? count;

  /// Whether the badge shows the error fill (`setCounter`'s `isError`
  /// animating `telegram_color` -> `fill_RedNormal`,
  /// GlassTabView.java:208, 226).
  final bool error;

  /// The premium variant (96x16dp-matrix PremiumGradient fill + white 14dp
  /// star, GlassTabView.java:196-206): the badge stays pinned visible
  /// (`usePremiumCounter ? 1f : ...`, line 167) regardless of [count], and
  /// the gradient colors resolve from
  /// [CounterBadge.premiumGradientKeys] (PremiumGradient.java:29).
  final bool premium;

  /// Overrides the badge center — see [CounterBadgePainter.center]. When
  /// null the Java placement `(width / 2 + 11, 10)` applies, which assumes
  /// this widget wraps the whole tab cell.
  final Offset? center;

  /// Per-surface color override — the `Theme.ResourcesProvider` convention.
  /// When null, `telegram_color` and `fill_RedNormal` resolve through
  /// [TelegramTheme.colorOf] (per-key rebuild granularity).
  final TelegramResources? resources;

  @override
  State<CounterBadgeDecoration> createState() =>
      _CounterBadgeDecorationState();
}

class _CounterBadgeDecorationState extends State<CounterBadgeDecoration>
    with SingleTickerProviderStateMixin {
  static bool _hasText(String? text) => text != null && text.isNotEmpty;

  /// `isHasCounterAnimator` — `BoolAnimator(380ms, EASE_OUT_QUINT)`
  /// (GlassTabView.java:68).
  late final BoolFactor _visible = BoolFactor(
    value: _hasText(widget.count),
    duration: CounterBadge.animationDuration,
    curve: TgCurves.easeOutQuint,
  );

  /// `isHasCounterErrorAnimator` — `BoolAnimator(380ms, EASE_OUT_QUINT)`
  /// (GlassTabView.java:69).
  late final BoolFactor _error = BoolFactor(
    value: widget.error,
    duration: CounterBadge.animationDuration,
    curve: TgCurves.easeOutQuint,
  );

  /// The last non-empty counter text — kept while animating out, like the
  /// `AnimatedTextDrawable` whose text outlives the visibility animator.
  late String _text = widget.count ?? '';

  /// One reusable laid-out [TextPainter] keyed by [_text] — rebuilding a
  /// fresh painter (and re-laying-out the text) on every 380ms-animator tick
  /// would allocate a native Paragraph per frame that nothing disposes.
  TextPainter? _counterPainter;
  String? _counterPainterText;

  TextPainter _counterPainterFor(String text) {
    if (_counterPainter == null || _counterPainterText != text) {
      _counterPainter?.dispose();
      _counterPainter = CounterBadgePainter.buildCounterPainter(text);
      _counterPainterText = text;
    }
    return _counterPainter!;
  }

  late final Ticker _ticker;

  /// Monotonic clock base: [BoolFactor.tick] requires non-decreasing
  /// timestamps, while a restarted [Ticker] resets its elapsed to zero, so
  /// the clock value reached when a run stops carries over as the base of
  /// the next run.
  Duration _clockBase = Duration.zero;
  Duration _clockNow = Duration.zero;

  void _onTick(Duration elapsed) {
    final Duration now = _clockBase + elapsed;
    _clockNow = now;
    setState(() {
      _visible.tick(now);
      _error.tick(now);
    });
    if (!_visible.isAnimating && !_error.isAnimating) {
      _ticker.stop();
      _clockBase = _clockNow;
    }
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(CounterBadgeDecoration oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool hasCount = _hasText(widget.count);
    if (hasCount) {
      _text = widget.count!;
    }
    // `setCounter(text, isError, animated: true)` (GlassTabView.java:223-227).
    _visible.set(hasCount);
    _error.set(widget.error);
    if ((_visible.isAnimating || _error.isAnimating) && !_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _counterPainter?.dispose();
    _counterPainter = null;
    super.dispose();
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  @override
  Widget build(BuildContext context) {
    return CounterBadgeLayer(
      painter: CounterBadgePainter(
        text: _text,
        // `usePremiumCounter ? 1 : isHasCounterAnimator.getFloatValue()`
        // (GlassTabView.java:167) — the premium pin lives in the painter
        // (CounterBadgePainter.effectiveVisibility).
        visibility: _visible.factor,
        errorFactor: _error.factor,
        color: _color(context, TelegramColorKey.telegram_color),
        errorColor: _color(context, TelegramColorKey.fill_RedNormal),
        premium: widget.premium,
        premiumGradientColors: widget.premium
            ? <Color>[
                for (final int key in CounterBadge.premiumGradientKeys)
                  _color(context, key),
              ]
            : null,
        center: widget.center,
        counterPainter: _counterPainterFor(_text),
      ),
      child: widget.child,
    );
  }
}
