// Port of the fragment push/pop navigation transition of
// `ui/ActionBar/ActionBarLayout.java` (`spec_typography_motion.md` §2.1,
// PLAN_UIKIT.md M12):
//
// - standard push: **48dp slide-in + crossfade** over 150ms with
//   `DecelerateInterpolator(1.5f)` — NOT a full-width iOS push; the page
//   underneath never moves (startLayoutAnimation, ActionBarLayout.java:
//   1816-1926);
// - standard pop: the exact mirror of the push (:1904-1916);
// - swipe-back gesture: the top page tracks the finger full-width (:1469),
//   a black scrim dims the back page proportionally to coverage up to
//   96/255 (:1214-1215), and the `layer_shadow` edge shadow hugs the
//   moving edge with a 20dp alpha ramp (:1192); release commits at
//   `x >= width/3` or on a 3500px/s fling (:1483, :1498) with the
//   commit/cancel duration formulas of `animateBackEndAnimation`
//   (:1606-1641).
//
// Deliberately NOT ported: the preview (peek & pop) transition (190ms
// `OvershootInterpolator(1.02)` scale, :1877-1897), the predictive-back
// peel (56dp `StandardDecelerate`, :1577-1583, and its 380/320ms
// EASE_OUT_QUINT settle, :1617-1637), the root-level `useAlphaAnimations`
// layout fade (:2164-2178), navigation-bar color blending (:1851-1873)
// and the bottom-tabs/sheet clipping paths. The scrim and the edge shadow
// are hardcoded black in Java (`Color.argb(..., 0x00, 0x00, 0x00)`,
// :1215, and the black `layer_shadow` drawable, :656) — no theme key
// exists for either, so this file resolves no theme colors and takes no
// `resources` parameter.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show protected;
import 'package:flutter/gestures.dart' show HorizontalDragGestureRecognizer;
import 'package:flutter/widgets.dart';

import '../foundation/tg_curves.dart';
import '../foundation/tg_motion.dart';

// -----------------------------------------------------------------------------
// Gesture constants — ui/ActionBar/ActionBarLayout.java.

/// Minimum horizontal travel before swipe-back tracking starts:
/// `dx >= AndroidUtilities.getPixelsInCM(0.4f, true)`
/// (ActionBarLayout.java:1448). 0.4 physical cm at the 160dpi logical-pixel
/// definition — `0.4 / 2.54 * 160 ≈ 25.2` logical px
/// (getPixelsInCM, AndroidUtilities.java:2899).
const double kTgBackGestureStartDistance = 0.4 / 2.54 * 160.0;

/// Release commit threshold as a fraction of the page width: the release
/// cancels when `x < containerView.getMeasuredWidth() / 3.0f`
/// (ActionBarLayout.java:1498) — i.e. commits from one third onward.
const double kTgBackGestureCommitFraction = 1.0 / 3.0;

/// Fling velocity that starts/commits a swipe-back regardless of distance:
/// 3500 *physical* px/s (`velX >= 3500`, ActionBarLayout.java:1483, also in
/// the release decision at :1498). Compare against logical velocity times
/// the device pixel ratio.
const double kTgBackGestureFlingVelocity = 3500.0;

/// Commit (dismiss) settle base: `200.0f / width * distToMove` ms
/// (ActionBarLayout.java:1617).
const double kTgBackGestureCommitBaseMs = 200.0;

/// Commit settle floor: 50ms (`Math.max(..., 50)`,
/// ActionBarLayout.java:1617 — the non-predictive branch).
const int kTgBackGestureCommitMinMs = 50;

/// Cancel (snap back) settle base: `320.0f / width * distToMove` ms
/// (ActionBarLayout.java:1629).
const double kTgBackGestureCancelBaseMs = 320.0;

/// Cancel settle floor: 120ms (`Math.max(..., 120)`,
/// ActionBarLayout.java:1629 — the non-predictive branch).
const int kTgBackGestureCancelMinMs = 120;

// -----------------------------------------------------------------------------
// Scrim + edge shadow constants — ActionBarLayout.drawChild.

/// Scrim base alpha over the back page: `Color.argb((int) (120 * opacity),
/// 0x00, 0x00, 0x00)` (ActionBarLayout.java:1215). With the coverage clamp
/// below the maximum is `120 * 0.8 = 96/255` = [TgMotion.pageScrimMax].
const int kTgPageScrimBaseAlpha = 120;

/// Coverage clamp for the scrim: `opacity = MathUtils.clamp(widthOffset /
/// (float) width, 0, 0.8f)` (ActionBarLayout.java:1214).
const double kTgPageScrimCoverageMax = 0.8;

/// The edge shadow reaches full opacity once the moving page still covers
/// 20dp: `alpha = MathUtils.clamp(255 * widthOffset / dp(20), 0, 255)`
/// (ActionBarLayout.java:1192) — i.e. it only ramps out over the last 20dp
/// of coverage.
const double kTgPageEdgeShadowRampDistance = 20.0;

/// Intrinsic width of the `layer_shadow` drawable: 4dp
/// (drawable-mdpi/layer_shadow.webp is 4×2px; bounds set at intrinsic
/// width, ActionBarLayout.java:1204-1209).
const double kTgPageEdgeShadowWidth = 4.0;

/// Gradient alpha at the far (away from the page) edge of `layer_shadow`:
/// 0x04, sampled from drawable-mdpi/layer_shadow.webp column 0.
const int kTgPageEdgeShadowStartAlpha = 0x04;

/// Gradient alpha at the page edge of `layer_shadow`: 0x32, sampled from
/// drawable-mdpi/layer_shadow.webp last column.
const int kTgPageEdgeShadowEndAlpha = 0x32;

// -----------------------------------------------------------------------------
// Pure gesture formulas (unit-testable ports of ActionBarLayout.java).

/// Whether swipe-back tracking may start after moving [dx] logical px
/// horizontally and [dy] vertically from the pointer-down position:
/// `dx >= getPixelsInCM(0.4f, true) && Math.abs(dx) / 3 > dy`
/// (ActionBarLayout.java:1448; Java divides ints, the port divides
/// doubles).
bool tgBackGestureShouldStart({required double dx, required double dy}) {
  return dx >= kTgBackGestureStartDistance && dx / 3.0 > dy;
}

/// The release decision — returns true when the drag should CANCEL (snap
/// back), the `backAnimation` boolean of ActionBarLayout.java:1498:
///
/// `backAnimation = x < width / 3.0f && (velX < 3500 || |velX| < |velY|)`
///
/// [x] is the page's translation in logical px, [velocityX]/[velocityY]
/// are *physical* px/s (Java's `VelocityTracker` works in view pixels).
/// Note the faithful quirk: past width/3 the release always commits, even
/// against a leftward fling.
bool tgBackGestureShouldCancel({
  required double x,
  required double width,
  required double velocityX,
  required double velocityY,
}) {
  return x < width * kTgBackGestureCommitFraction &&
      (velocityX < kTgBackGestureFlingVelocity ||
          velocityX.abs() < velocityY.abs());
}

/// Commit settle duration: `Math.max((int) (200.0f / width * distToMove),
/// 50)` ms where `distToMove = width - x` (ActionBarLayout.java:1616-1617).
Duration tgBackGestureCommitDuration({required double x, required double width}) {
  assert(width > 0);
  final int ms = (kTgBackGestureCommitBaseMs / width * (width - x)).toInt();
  return Duration(milliseconds: math.max(ms, kTgBackGestureCommitMinMs));
}

/// Cancel settle duration: `Math.max((int) (320.0f / width * distToMove),
/// 120)` ms where `distToMove = x` (ActionBarLayout.java:1628-1629).
Duration tgBackGestureCancelDuration({required double x, required double width}) {
  assert(width > 0);
  final int ms = (kTgBackGestureCancelBaseMs / width * x).toInt();
  return Duration(milliseconds: math.max(ms, kTgBackGestureCancelMinMs));
}

// -----------------------------------------------------------------------------
// Edge shadow painter.

/// The `layer_shadow` drawable of a horizontally moving page: a 4dp black
/// gradient (alpha 0x04 → 0x32 toward the page) hugging the page's leading
/// edge, with the whole drawable's alpha ramping
/// `255 * widthOffset / dp(20)` (ActionBarLayout.java:1192-1211).
///
/// [coverage] is `widthOffset / width` — the fraction of the layout the
/// moving page still covers (1.0 at rest, 0.0 fully swiped away); at 0 the
/// painter draws nothing, which is also the standard (non-gesture)
/// transition state: Java only draws the shadow for gesture-driven
/// `innerTranslationX` offsets.
class TgPageEdgeShadowPainter extends CustomPainter {
  /// Creates the edge-shadow painter.
  const TgPageEdgeShadowPainter({
    required this.coverage,
    this.textDirection = TextDirection.ltr,
  });

  /// Fraction of the layout width the moving page still covers (0..1).
  final double coverage;

  /// Which edge is leading: LTR draws left of the page, RTL right.
  final TextDirection textDirection;

  /// The drawable-level alpha for a page still covering [widthOffset]
  /// logical px: `MathUtils.clamp(255 * widthOffset / dp(20), 0, 255)`
  /// (ActionBarLayout.java:1192).
  static int rampAlpha(double widthOffset) {
    return (255.0 * widthOffset / kTgPageEdgeShadowRampDistance)
        .clamp(0.0, 255.0)
        .toInt();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final int alpha = rampAlpha(coverage * size.width);
    if (alpha <= 0) {
      return;
    }
    final bool ltr = textDirection == TextDirection.ltr;
    // `layerShadowDrawable.setBounds(translationX - intrinsicWidth, top,
    // translationX, bottom)` (ActionBarLayout.java:1204-1209): the shadow
    // abuts the moving page's leading edge, outside its bounds.
    final Rect rect = ltr
        ? Rect.fromLTRB(-kTgPageEdgeShadowWidth, 0.0, 0.0, size.height)
        : Rect.fromLTRB(
            size.width, 0.0, size.width + kTgPageEdgeShadowWidth, size.height);
    // `layerShadowDrawable.setAlpha(alpha)` modulates the bitmap's own
    // 0x04→0x32 gradient.
    final double factor = alpha / 255.0;
    final Color far =
        Color.fromARGB((kTgPageEdgeShadowStartAlpha * factor).round(), 0, 0, 0);
    final Color near =
        Color.fromARGB((kTgPageEdgeShadowEndAlpha * factor).round(), 0, 0, 0);
    final Paint paint = Paint()
      ..shader = LinearGradient(
        colors: ltr ? <Color>[far, near] : <Color>[near, far],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(TgPageEdgeShadowPainter oldDelegate) {
    return coverage != oldDelegate.coverage ||
        textDirection != oldDelegate.textDirection;
  }
}

// -----------------------------------------------------------------------------
// The transition widget.

/// The visual half of the ActionBarLayout push/pop:
///
/// - animated mode ([linearTransition] false): the page fades
///   `alpha 0→1` (ActionBarLayout.java:1886) and slides
///   `dp(48) * (1 - interpolated) → 0` (:1901) through
///   `DecelerateInterpolator(1.5f)` (:577, applied :1882); the pop is the
///   time-mirror (:1904-1916). No scrim, no shadow — Java draws those only
///   for gesture offsets.
/// - gesture mode ([linearTransition] true, i.e.
///   `route.popGestureInProgress`): translation maps the animation value
///   linearly to the full width (`containerView.setTranslationX(dx)`,
///   :1469), alpha stays 1, the back page dims through the black scrim
///   (:1214-1215) and the [TgPageEdgeShadowPainter] shadow hugs the moving
///   edge (:1192-1211).
///
/// The `secondaryAnimation` of the route below intentionally drives
/// nothing: the outgoing fragment underneath never moves
/// (spec_typography_motion.md §2.1). Both modes build the same element
/// tree so a drag can begin mid-frame without recreating the subtree
/// (which would drop the in-flight gesture state).
class TgPageTransition extends StatefulWidget {
  /// Creates the Telegram page transition.
  const TgPageTransition({
    super.key,
    required this.primaryRouteAnimation,
    this.linearTransition = false,
    required this.child,
  });

  /// The route's own animation (0 = dismissed, 1 = presented).
  final Animation<double> primaryRouteAnimation;

  /// True while a swipe-back drives [primaryRouteAnimation] — the value
  /// then maps linearly to a full-width translation instead of the curved
  /// 48dp slide + fade.
  final bool linearTransition;

  /// The page contents.
  final Widget child;

  @override
  State<TgPageTransition> createState() => _TgPageTransitionState();
}

class _TgPageTransitionState extends State<TgPageTransition> {
  late CurvedAnimation _curved;

  @override
  void initState() {
    super.initState();
    _createCurve();
  }

  @override
  void didUpdateWidget(TgPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryRouteAnimation != widget.primaryRouteAnimation) {
      _curved.dispose();
      _createCurve();
    }
  }

  void _createCurve() {
    // Push: v = C(t) — alpha v, x = 48(1-v) (ActionBarLayout.java:1886,
    // :1901). Pop re-runs the same interpolator on pop progress p
    // (:1905, :1916): alpha = 1-C(p), x = 48·C(p); with t = 1-p that is
    // v = 1 - C(1-t), exactly `pageCurve.flipped` on the reversing parent.
    _curved = CurvedAnimation(
      parent: widget.primaryRouteAnimation,
      curve: TgMotion.pageCurve,
      reverseCurve: TgMotion.pageCurve.flipped,
    );
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextDirection direction = Directionality.of(context);
    final double sign = direction == TextDirection.rtl ? -1.0 : 1.0;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        return AnimatedBuilder(
          animation: widget.primaryRouteAnimation,
          child: widget.child,
          builder: (BuildContext context, Widget? child) {
            final double dx;
            final double alpha;
            final int scrimAlpha;
            final double shadowCoverage;
            if (widget.linearTransition) {
              // Gesture: page tracks the finger full-width, no fade
              // (ActionBarLayout.java:1469; alpha untouched during drags).
              final double t =
                  widget.primaryRouteAnimation.value.clamp(0.0, 1.0);
              dx = (1.0 - t) * width;
              alpha = 1.0;
              // `Color.argb((int) (120 * clamp(widthOffset / width, 0,
              // 0.8f)), 0, 0, 0)` (:1214-1215); widthOffset/width == t.
              scrimAlpha =
                  (kTgPageScrimBaseAlpha * math.min(t, kTgPageScrimCoverageMax))
                      .toInt();
              shadowCoverage = t;
            } else {
              // Animated push/pop: 48dp slide + crossfade, no scrim/shadow
              // (drawChild only draws them for gesture-driven
              // innerTranslationX, :1189-1222).
              final double v = _curved.value;
              dx = TgMotion.pageSlide * (1.0 - v);
              // `MathUtils.clamp(interpolated, 0, 1)` (:1885, :1904).
              alpha = v.clamp(0.0, 1.0);
              scrimAlpha = 0;
              shadowCoverage = 0.0;
            }
            return Stack(
              fit: StackFit.passthrough,
              children: <Widget>[
                // Scrim over the back page — drawn under the moving page,
                // over whatever the route reveals (ActionBarLayout draws it
                // on containerViewBack, :1213-1221).
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Color.fromARGB(scrimAlpha, 0, 0, 0),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(dx * sign, 0.0),
                  child: CustomPaint(
                    painter: TgPageEdgeShadowPainter(
                      coverage: shadowCoverage,
                      textDirection: direction,
                    ),
                    child: Opacity(
                      opacity: alpha,
                      alwaysIncludeSemantics: true,
                      child: child,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Route mixin + route + theme-wide builder.

/// Mixin providing the ActionBarLayout push/pop transition and swipe-back
/// gesture to any [PageRoute] — the [CupertinoRouteTransitionMixin]
/// analog. [TgPageRoute] is the ready-made application.
mixin TgRouteTransitionMixin<T> on PageRoute<T> {
  /// Builds the primary contents of the route.
  @protected
  Widget buildContent(BuildContext context);

  /// 150ms (`float duration = preview && open ? 190.0f : 150.0f;`,
  /// ActionBarLayout.java:1839 — non-preview) via [TgMotion.pageDuration].
  @override
  Duration get transitionDuration => TgMotion.pageDuration;

  /// The pop runs the same 150ms loop (ActionBarLayout.java:1839).
  @override
  Duration get reverseTransitionDuration => TgMotion.pageDuration;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: buildContent(context),
    );
  }

  /// Called by [_TgBackGestureDetector] when a swipe-back drag crosses the
  /// start threshold; the returned controller owns the rest of the drag.
  _TgBackGestureController<T> _startPopGesture() {
    assert(popGestureEnabled);
    return _TgBackGestureController<T>(
      navigator: navigator!,
      controller: controller!,
      getIsCurrent: () => isCurrent,
      getIsActive: () => isActive,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return buildPageTransitions<T>(
        this, context, animation, secondaryAnimation, child);
  }

  /// Builds the transition for any [PageRoute] — used by both
  /// [buildTransitions] and [TgPageTransitionsBuilder].
  ///
  /// The swipe-back detector is only wired when [route] mixes in
  /// [TgRouteTransitionMixin] (the gesture needs the route's animation
  /// controller); other routes — e.g. a `MaterialPageRoute` under a
  /// theme-wide [TgPageTransitionsBuilder] — get the visuals only.
  /// `secondaryAnimation` intentionally drives nothing: the page under a
  /// push never moves (ActionBarLayout.java:1816-1926 only animates the
  /// incoming/outgoing container).
  static Widget buildPageTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Mid-drag the transition is linear to match finger motion; the flag
    // stays up through the release settle, like Java's animateBackEnd
    // animator keeping innerTranslationX authoritative (:1606-1641).
    final bool linearTransition = route.popGestureInProgress;
    Widget result = child;
    if (route is TgRouteTransitionMixin<T>) {
      result = _TgBackGestureDetector<T>(
        enabledCallback: () => route.popGestureEnabled,
        onStartPopGesture: route._startPopGesture,
        child: result,
      );
    }
    return TgPageTransition(
      primaryRouteAnimation: animation,
      linearTransition: linearTransition,
      child: result,
    );
  }
}

/// A page route with the Telegram fragment transition: 48dp slide-in +
/// crossfade over 150ms (`DecelerateInterpolator(1.5f)`), a static page
/// underneath, and the classic swipe-back gesture (full-width tracking,
/// commit at width/3, scrim + edge shadow) — the
/// `ui/ActionBar/ActionBarLayout.java` port.
///
/// ```dart
/// Navigator.of(context).push(
///   TgPageRoute<void>(builder: (BuildContext context) => const Page()),
/// );
/// ```
///
/// For theme-wide installation on Material routes see
/// [TgPageTransitionsBuilder].
class TgPageRoute<T> extends PageRoute<T> with TgRouteTransitionMixin<T> {
  /// Creates a Telegram page route.
  TgPageRoute({
    required this.builder,
    super.settings,
    super.requestFocus,
    this.maintainState = true,
    super.fullscreenDialog,
    super.allowSnapshotting = true,
  });

  /// Builds the primary contents of the route.
  final WidgetBuilder builder;

  @override
  final bool maintainState;

  @override
  Widget buildContent(BuildContext context) => builder(context);

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}

/// [PageTransitionsBuilder] applying the Telegram fragment transition, so
/// apps can install it theme-wide (e.g. in a Material
/// `PageTransitionsTheme`); `MaterialPageRoute`s then use the 150ms 48dp
/// slide + crossfade. The swipe-back gesture additionally requires the
/// route to be a [TgPageRoute] (or mix in [TgRouteTransitionMixin]) —
/// foreign routes get the visuals only.
class TgPageTransitionsBuilder extends PageTransitionsBuilder {
  /// Creates the builder.
  const TgPageTransitionsBuilder();

  /// 150ms (ActionBarLayout.java:1839) via [TgMotion.pageDuration].
  @override
  Duration get transitionDuration => TgMotion.pageDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return TgRouteTransitionMixin.buildPageTransitions<T>(
        route, context, animation, secondaryAnimation, child);
  }
}

// -----------------------------------------------------------------------------
// Swipe-back gesture machinery.

/// Widget side of the swipe-back gesture: a full-area listener (Telegram
/// tracks from anywhere on the page, not just the leading edge —
/// ActionBarLayout.java:1440-1472) feeding a [HorizontalDragGestureRecognizer]
/// whose stream is gated by the Telegram start threshold before the route's
/// controller is touched.
class _TgBackGestureDetector<T> extends StatefulWidget {
  const _TgBackGestureDetector({
    required this.enabledCallback,
    required this.onStartPopGesture,
    required this.child,
  });

  final Widget child;

  final ValueGetter<bool> enabledCallback;

  final ValueGetter<_TgBackGestureController<T>> onStartPopGesture;

  @override
  _TgBackGestureDetectorState<T> createState() =>
      _TgBackGestureDetectorState<T>();
}

class _TgBackGestureDetectorState<T>
    extends State<_TgBackGestureDetector<T>> {
  _TgBackGestureController<T>? _controller;

  late HorizontalDragGestureRecognizer _recognizer;

  /// Global pointer-down position (Java's startedTrackingX/Y before the
  /// threshold, ActionBarLayout.java:1430-1448).
  Offset? _downPosition;

  /// Global x at threshold crossing — tracking rebases here
  /// (`startedTrackingX = (int) ev.getX()`, ActionBarLayout.java:1452), so
  /// the page starts moving from zero.
  double? _trackStartX;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    // If a drag is in flight while disposing, release the navigator's
    // user-gesture lock once it is safe to do so.
    if (_controller != null) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (_controller?.navigator.mounted ?? false) {
          _controller?.navigator.didStopUserGesture();
        }
        _controller = null;
      });
    }
    super.dispose();
  }

  double get _sign =>
      Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.enabledCallback()) {
      _downPosition = event.position;
      _recognizer.addPointer(event);
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    assert(mounted);
    final Offset position = details.globalPosition;
    // `dx = Math.max(0, x - startedTrackingX); dy = |y - startedTrackingY|`
    // (ActionBarLayout.java:1445-1446).
    final double dx =
        math.max(0.0, (position.dx - _downPosition!.dx) * _sign);
    final double dy = (position.dy - _downPosition!.dy).abs();
    if (_controller == null) {
      if (tgBackGestureShouldStart(dx: dx, dy: dy)) {
        _controller = widget.onStartPopGesture();
        _trackStartX = position.dx;
      }
      return;
    }
    // `containerView.setTranslationX(dx)` (ActionBarLayout.java:1469) —
    // the page tracks the finger full-width from the rebased origin.
    final double width = context.size!.width;
    final double drag = math.max(0.0, (position.dx - _trackStartX!) * _sign);
    _controller!.dragTo(1.0 - drag / width);
  }

  void _handleDragEnd(DragEndDetails details) {
    assert(mounted);
    final double pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    // Java's VelocityTracker yields physical px/s
    // (`computeCurrentVelocity(1000)`, ActionBarLayout.java:1478).
    final double velocityX =
        details.velocity.pixelsPerSecond.dx * _sign * pixelRatio;
    final double velocityY = details.velocity.pixelsPerSecond.dy * pixelRatio;
    if (_controller == null) {
      // Fling-start on release without tracking: `velX >= 3500 && velX >
      // Math.abs(velY)` (ActionBarLayout.java:1483) — the shared release
      // decision then commits from x = 0.
      if (!widget.enabledCallback() ||
          velocityX < kTgBackGestureFlingVelocity ||
          velocityX <= velocityY.abs()) {
        return;
      }
      _controller = widget.onStartPopGesture();
    }
    _controller!.dragEnd(
      velocityX: velocityX,
      velocityY: velocityY,
      width: context.size!.width,
    );
    _controller = null;
  }

  void _handleDragCancel() {
    assert(mounted);
    // A cancelled pointer runs the same release decision with no velocity
    // (Java handles ACTION_CANCEL together with ACTION_UP,
    // ActionBarLayout.java:1474).
    _controller?.dragEnd(
      velocityX: 0.0,
      velocityY: 0.0,
      width: context.size?.width ?? 1.0,
    );
    _controller = null;
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasDirectionality(context));
    return Listener(
      onPointerDown: _handlePointerDown,
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}

/// Controller side of the swipe-back gesture: drives the route's animation
/// controller from drag input and runs the Java release physics — the
/// `animateBackEndAnimation` port (ActionBarLayout.java:1606-1641).
///
/// Works in route-animation space: value 1.0 = page at rest, 0.0 = page
/// fully swiped away; the page's x is `(1 - value) * width`.
class _TgBackGestureController<T> {
  /// Locks the navigator's user-gesture state for the drag's duration.
  _TgBackGestureController({
    required this.navigator,
    required this.controller,
    required this.getIsCurrent,
    required this.getIsActive,
  }) {
    navigator.didStartUserGesture();
  }

  final AnimationController controller;
  final NavigatorState navigator;
  final ValueGetter<bool> getIsCurrent;
  final ValueGetter<bool> getIsActive;

  /// Pins the route animation to [value] (finger tracking).
  void dragTo(double value) {
    controller.value = value;
  }

  /// Runs the release decision and settle animation.
  ///
  /// [velocityX] and [velocityY] are physical px/s ([velocityX] positive
  /// toward dismissal); [width] is the page width in logical px.
  void dragEnd({
    required double velocityX,
    required double velocityY,
    required double width,
  }) {
    final bool isCurrent = getIsCurrent();
    final double x = (1.0 - controller.value) * width;
    final bool cancel;
    if (!isCurrent) {
      // The route was popped/removed programmatically mid-drag: settle
      // toward wherever it is headed.
      cancel = getIsActive();
    } else {
      cancel = tgBackGestureShouldCancel(
        x: x,
        width: width,
        velocityX: velocityX,
        velocityY: velocityY,
      );
    }
    // Java's release animator is a plain ObjectAnimator — the default
    // AccelerateDecelerateInterpolator, mapped to EASE_BOTH
    // (spec_typography_motion.md §2 table).
    if (cancel) {
      controller.animateTo(
        1.0,
        duration: tgBackGestureCancelDuration(x: x, width: width),
        curve: TgCurves.easeBoth,
      );
    } else {
      if (isCurrent) {
        navigator.pop();
      }
      // The pop may have finished inline if already at the target.
      if (controller.isAnimating) {
        controller.animateBack(
          0.0,
          duration: tgBackGestureCommitDuration(x: x, width: width),
          curve: TgCurves.easeBoth,
        );
      }
    }
    if (controller.isAnimating) {
      // Hold the user-gesture state through the settle so the transition
      // stays in linear (full-width) mode until the page lands.
      late final AnimationStatusListener statusListener;
      statusListener = (AnimationStatus status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(statusListener);
      };
      controller.addStatusListener(statusListener);
    } else {
      navigator.didStopUserGesture();
    }
  }
}
