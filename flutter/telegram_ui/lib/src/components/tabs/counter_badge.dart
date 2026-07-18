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
// - premium variant (lines 73, 167, 196-206, 229-231): a 96x16dp
//   PremiumGradient round rect with a 14dp star, visibility pinned to 1.
//   NOT ported yet — see [CounterBadgePainter.premium].
//
// Not ported: `AnimatedTextDrawable`'s per-glyph text/width crossfade when
// the count changes while visible (the text swaps instantly here), and the
// `attachScale` multiplier of the attach-panel tabs (line 167).
library;

import 'dart:math' as math;

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
  /// dp(16), 0, 0)` (GlassTabView.java:201). Deferred — see
  /// [CounterBadgePainter.premium].
  static const double premiumGradientWidth = 96.0;

  /// Premium gradient matrix height (GlassTabView.java:201). Deferred.
  static const double premiumGradientHeight = 16.0;

  /// Premium star drawable size: `dp(14)`, centered at `(cx - 7, cy - 7)`
  /// (GlassTabView.java:203-205). Deferred.
  static const double premiumStarSize = 14.0;

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
  /// Creates the painter. Throws [UnimplementedError] if [premium] is true
  /// (deferred variant).
  CounterBadgePainter({
    required this.text,
    required this.color,
    required this.errorColor,
    this.visibility = 1.0,
    this.errorFactor = 0.0,
    this.premium = false,
    this.center,
    TextPainter? counterPainter,
  }) : _externalCounterPainter = counterPainter,
       assert(visibility >= 0.0 && visibility <= 1.0),
       assert(errorFactor >= 0.0 && errorFactor <= 1.0),
       assert(
         counterPainter == null ||
             (counterPainter.text as TextSpan?)?.text == text,
         'counterPainter must be laid out for the same text',
       ) {
    if (premium) {
      throw UnimplementedError(
        'Premium counter badge is not ported yet: PremiumGradient round rect '
        '(96x16dp matrix) + 14dp star, visibility pinned to 1 '
        '(GlassTabView.java:167, 196-206). '
        'TODO: port PremiumGradient and R.drawable.star, then draw them in '
        'place of the fill + text pass of paintBadge.',
      );
    }
  }

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
  /// badge (clear ring included) about [centerFor] (line 192).
  final double visibility;

  /// Error factor in 0..1 — `isHasCounterErrorAnimator.getFloatValue()`,
  /// blending the fill `telegram_color` -> `fill_RedNormal`
  /// (GlassTabView.java:208).
  final double errorFactor;

  /// The deferred premium variant (`setPremiumBadge`,
  /// GlassTabView.java:229-231). Passing true throws [UnimplementedError]
  /// at construction — see the constructor TODO.
  final bool premium;

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
    if (visibility <= 0.0) {
      return;
    }
    canvas.saveLayer(layerBounds(size), Paint()); // L169-171 (null paint)
    paintBadge(canvas, size);
    canvas.restore(); // L216-218
  }

  /// The raw badge pass — GlassTabView.java:175-213 — assuming the caller
  /// holds an isolating layer open (so [BlendMode.clear] erases only that
  /// layer). Draws, in order: the outer clear round rect, the inner fill,
  /// the centered counter text, all scaled by [visibility] about the badge
  /// center.
  void paintBadge(Canvas canvas, Size size) {
    if (visibility <= 0.0) {
      return;
    }
    canvas.save(); // L176

    final Offset c = centerFor(size); // L179-180
    Rect rect = punchRect(size); // L185-190

    // canvas.scale(hasCounter, hasCounter, cx, cy) (L192).
    canvas.translate(c.dx, c.dy);
    canvas.scale(visibility, visibility);
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

  /// The badge painter; when null or fully hidden the child paints
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

  /// The badge painter (null or `visibility <= 0` paints the child only).
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
    if (painter == null || painter.visibility <= 0.0) {
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

  /// The deferred premium variant (96x16dp PremiumGradient + 14dp star,
  /// GlassTabView.java:196-206). Setting true currently throws
  /// [UnimplementedError] (from the [CounterBadgePainter] constructor) —
  /// see the TODO there.
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
        // (GlassTabView.java:167); premium throws in the painter for now.
        visibility: _visible.factor,
        errorFactor: _error.factor,
        color: _color(context, TelegramColorKey.telegram_color),
        errorColor: _color(context, TelegramColorKey.fill_RedNormal),
        premium: widget.premium,
        center: widget.center,
        counterPainter: _counterPainterFor(_text),
      ),
      child: widget.child,
    );
  }
}
