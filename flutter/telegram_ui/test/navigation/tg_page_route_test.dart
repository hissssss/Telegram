// Tests for lib/src/navigation/tg_page_route.dart (PLAN_UIKIT.md M12),
// golden-free:
//
//  * constants against the Java values (ActionBarLayout.java, cited per
//    constant in the lib file);
//  * pure release formulas: commit `max(200·remaining/width, 50)ms`, cancel
//    `max(320·x/width, 120)ms` (:1616-1633), the `backAnimation` release
//    decision (:1498) and the start threshold (:1448);
//  * push = 48dp slide-in + crossfade over 150ms through
//    `DecelerateInterpolator(1.5f)` = 1−(1−t)³ (:1839, :1882, :1886,
//    :1901); pop is the exact time-mirror (:1904-1916);
//  * the page underneath never moves during a push;
//  * swipe-back: 25.2px start threshold with rebase, full-width finger
//    tracking (:1469), scrim `(120 · clamp(coverage, 0, 0.8))/255` black
//    over the back page (:1214-1215), edge-shadow painter coverage,
//    commit/cancel settle timing, fling-start (:1483);
//  * TgPageTransitionsBuilder drives a foreign PageRoute (visuals only, no
//    gesture);
//  * scopesRoute semantics on the page.
//
// Theme note (blanket contract item 2): this component resolves NO theme
// keys — Java hardcodes the scrim (`Color.argb(..., 0, 0, 0)`,
// ActionBarLayout.java:1215) and the black `layer_shadow` drawable — so the
// scrim-color assertions below double as the "hardcoded black" divergence
// test; there is no resources override to flip.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/tg_motion.dart';
import 'package:telegram_ui/src/navigation/tg_page_route.dart';

const Size _screen = Size(800, 600);

const Key _p1 = ValueKey<String>('page1');
const Key _p2 = ValueKey<String>('page2');

Widget _page(Key key, Color color) => Container(key: key, color: color);

/// Bare widgets-layer app: directionality + media query + navigator whose
/// initial route is a settled [TgPageRoute] hosting page 1.
Widget _app({TextDirection direction = TextDirection.ltr}) {
  return Directionality(
    textDirection: direction,
    child: MediaQuery(
      data: const MediaQueryData(size: _screen),
      child: Navigator(
        onGenerateRoute: (RouteSettings settings) => TgPageRoute<void>(
          settings: settings,
          builder: (BuildContext context) =>
              _page(_p1, const Color(0xFFFFFFFF)),
        ),
      ),
    ),
  );
}

NavigatorState _nav(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator));

/// Pushes page 2 and pumps one frame (transition at t = 0).
Future<TgPageRoute<void>> _push(WidgetTester tester) async {
  final TgPageRoute<void> route = TgPageRoute<void>(
    builder: (BuildContext context) => _page(_p2, const Color(0xFF88AA44)),
  );
  _nav(tester).push(route);
  await tester.pump();
  return route;
}

double _opacityOf(WidgetTester tester, Key key) {
  return tester
      .widget<Opacity>(
        find.ancestor(of: find.byKey(key), matching: find.byType(Opacity)).first,
      )
      .opacity;
}

double _dxOf(WidgetTester tester, Key key) =>
    tester.getTopLeft(find.byKey(key)).dx;

void main() {
  group('constants', () {
    test('gesture constants match ActionBarLayout.java', () {
      // 0.4cm at 160dpi (getPixelsInCM, ActionBarLayout.java:1448).
      expect(kTgBackGestureStartDistance, 0.4 / 2.54 * 160.0);
      expect(kTgBackGestureStartDistance, closeTo(25.2, 0.005));
      // x < width/3 cancels (:1498).
      expect(kTgBackGestureCommitFraction, 1.0 / 3.0);
      // velX >= 3500 physical px/s (:1483, :1498).
      expect(kTgBackGestureFlingVelocity, 3500.0);
      // max((int)(200/width·dist), 50) (:1617).
      expect(kTgBackGestureCommitBaseMs, 200.0);
      expect(kTgBackGestureCommitMinMs, 50);
      // max((int)(320/width·dist), 120) (:1629).
      expect(kTgBackGestureCancelBaseMs, 320.0);
      expect(kTgBackGestureCancelMinMs, 120);
    });

    test('scrim + edge shadow constants match ActionBarLayout.java', () {
      // Color.argb((int)(120·opacity), 0, 0, 0), opacity clamped 0.8
      // (:1214-1215); max dim equals TgMotion.pageScrimMax = 96/255.
      expect(kTgPageScrimBaseAlpha, 120);
      expect(kTgPageScrimCoverageMax, 0.8);
      expect(
        kTgPageScrimBaseAlpha * kTgPageScrimCoverageMax / 255.0,
        closeTo(TgMotion.pageScrimMax, 1e-12),
      );
      // 255·widthOffset/dp(20) alpha ramp (:1192); 4dp intrinsic width and
      // 0x04→0x32 gradient sampled from drawable-mdpi/layer_shadow.webp.
      expect(kTgPageEdgeShadowRampDistance, 20.0);
      expect(kTgPageEdgeShadowWidth, 4.0);
      expect(kTgPageEdgeShadowStartAlpha, 0x04);
      expect(kTgPageEdgeShadowEndAlpha, 0x32);
    });

    test('route and builder durations are the 150ms page duration', () {
      final TgPageRoute<void> route = TgPageRoute<void>(
        builder: (BuildContext context) => const SizedBox(),
      );
      expect(route.transitionDuration, const Duration(milliseconds: 150));
      expect(route.transitionDuration, TgMotion.pageDuration);
      expect(route.reverseTransitionDuration, TgMotion.pageDuration);
      expect(route.opaque, isTrue);
      expect(route.barrierColor, isNull);
      expect(route.maintainState, isTrue);
      expect(
        const TgPageTransitionsBuilder().transitionDuration,
        TgMotion.pageDuration,
      );
    });
  });

  group('release formulas', () {
    test('commit duration: max((int)(200/width·(width−x)), 50)ms', () {
      expect(tgBackGestureCommitDuration(x: 0, width: 800),
          const Duration(milliseconds: 200));
      expect(tgBackGestureCommitDuration(x: 400, width: 800),
          const Duration(milliseconds: 100));
      expect(tgBackGestureCommitDuration(x: 600, width: 800),
          const Duration(milliseconds: 50));
      // 2.5ms truncates to 2, floored to 50.
      expect(tgBackGestureCommitDuration(x: 790, width: 800),
          const Duration(milliseconds: 50));
    });

    test('cancel duration: max((int)(320/width·x), 120)ms', () {
      expect(tgBackGestureCancelDuration(x: 800, width: 800),
          const Duration(milliseconds: 320));
      expect(tgBackGestureCancelDuration(x: 500, width: 800),
          const Duration(milliseconds: 200));
      // 80ms floored to 120.
      expect(tgBackGestureCancelDuration(x: 200, width: 800),
          const Duration(milliseconds: 120));
      expect(tgBackGestureCancelDuration(x: 0, width: 800),
          const Duration(milliseconds: 120));
    });

    test('release decision is the Java backAnimation boolean', () {
      // Below width/3, no velocity: cancel.
      expect(
        tgBackGestureShouldCancel(
            x: 100, width: 800, velocityX: 0, velocityY: 0),
        isTrue,
      );
      // At/above width/3: commit (x < width/3 is strict).
      expect(
        tgBackGestureShouldCancel(
            x: 800 / 3, width: 800, velocityX: 0, velocityY: 0),
        isFalse,
      );
      expect(
        tgBackGestureShouldCancel(
            x: 400, width: 800, velocityX: 0, velocityY: 0),
        isFalse,
      );
      // Fling right past 3500 commits from anywhere…
      expect(
        tgBackGestureShouldCancel(
            x: 100, width: 800, velocityX: 3600, velocityY: 0),
        isFalse,
      );
      // …unless vertical velocity dominates.
      expect(
        tgBackGestureShouldCancel(
            x: 100, width: 800, velocityX: 3600, velocityY: 4000),
        isTrue,
      );
      // Below the fling threshold velocity does not commit.
      expect(
        tgBackGestureShouldCancel(
            x: 100, width: 800, velocityX: 3400, velocityY: 0),
        isTrue,
      );
      // Faithful quirk (:1498): past width/3 even a hard LEFT fling
      // commits.
      expect(
        tgBackGestureShouldCancel(
            x: 400, width: 800, velocityX: -9000, velocityY: 0),
        isFalse,
      );
    });

    test('start threshold: dx >= 25.2 && dx/3 > dy', () {
      expect(tgBackGestureShouldStart(dx: 25.2, dy: 0), isTrue);
      expect(tgBackGestureShouldStart(dx: 25.1, dy: 0), isFalse);
      expect(tgBackGestureShouldStart(dx: 60, dy: 19), isTrue);
      expect(tgBackGestureShouldStart(dx: 60, dy: 20), isFalse);
      expect(tgBackGestureShouldStart(dx: 0, dy: 0), isFalse);
    });
  });

  group('push/pop animation', () {
    testWidgets('push: 48dp slide-in + crossfade through 1−(1−t)³ in 150ms',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      final TgPageRoute<void> route = await _push(tester);
      // t = 0: fully offset and transparent.
      expect(_dxOf(tester, _p2), 48.0);
      expect(_opacityOf(tester, _p2), 0.0);
      // t = 0.5 (75ms): v = 1−0.5³ = 0.875 → x = 48·0.125 = 6, α = 0.875
      // (ActionBarLayout.java:1886, :1901).
      await tester.pump(const Duration(milliseconds: 75));
      expect(_dxOf(tester, _p2), closeTo(6.0, 1e-9));
      expect(_opacityOf(tester, _p2), closeTo(0.875, 1e-9));
      // Still transitioning at 149ms, landed at exactly 150ms (:1839).
      await tester.pump(const Duration(milliseconds: 74));
      expect(route.animation!.isCompleted, isFalse);
      expect(route.animation!.value, lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 1));
      expect(route.animation!.value, 1.0);
      expect(_dxOf(tester, _p2), 0.0);
      expect(_opacityOf(tester, _p2), 1.0);
      // The controller's status flips on the first tick past the duration
      // (simulation isDone is strict).
      await tester.pump(const Duration(milliseconds: 1));
      expect(route.animation!.isCompleted, isTrue);
    });

    testWidgets('pop mirrors the push in time',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      await _push(tester);
      await tester.pumpAndSettle();
      _nav(tester).pop();
      await tester.pump();
      // Pop progress p = 0.5: α = 1−C(p) = 0.125, x = 48·C(p) = 42
      // (ActionBarLayout.java:1905, :1916).
      await tester.pump(const Duration(milliseconds: 75));
      expect(_dxOf(tester, _p2), closeTo(42.0, 1e-9));
      expect(_opacityOf(tester, _p2), closeTo(0.125, 1e-9));
      await tester.pumpAndSettle();
      expect(find.byKey(_p2), findsNothing);
      expect(find.byKey(_p1), findsOneWidget);
    });

    testWidgets('the page underneath never moves during a push',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      expect(tester.getTopLeft(find.byKey(_p1)), Offset.zero);
      await _push(tester);
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.getTopLeft(find.byKey(_p1)), Offset.zero);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getTopLeft(find.byKey(_p1)), Offset.zero);
    });

    testWidgets('RTL mirrors the slide direction',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(direction: TextDirection.rtl));
      await _push(tester);
      await tester.pump(const Duration(milliseconds: 75));
      expect(_dxOf(tester, _p2), closeTo(-6.0, 1e-9));
    });
  });

  group('swipe-back gesture', () {
    testWidgets(
        'threshold, rebased full-width tracking, scrim and edge shadow',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      await _push(tester);
      await tester.pumpAndSettle();

      final TestGesture gesture =
          await tester.startGesture(const Offset(400, 300));
      // 20px < 25.2px: not tracking yet (ActionBarLayout.java:1448).
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(_nav(tester).userGestureInProgress, isFalse);
      expect(_dxOf(tester, _p2), 0.0);
      // 40px total crosses the threshold; tracking rebases at the current
      // finger x (:1452), so the page has not moved yet.
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(_nav(tester).userGestureInProgress, isTrue);
      expect(_dxOf(tester, _p2), 0.0);
      // 200px of tracked drag: the page follows full-width (:1469), does
      // not fade, dims the back page and draws the edge shadow.
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(_dxOf(tester, _p2), 200.0);
      expect(_opacityOf(tester, _p2), 1.0);
      // coverage t = 1 − 200/800 = 0.75 → scrim (120·0.75).toInt() = 90
      // (:1214-1215) — hardcoded black, no theme key.
      expect(
        find.byWidgetPredicate((Widget w) =>
            w is ColoredBox && w.color == const Color.fromARGB(90, 0, 0, 0)),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((Widget w) =>
            w is CustomPaint &&
            w.painter is TgPageEdgeShadowPainter &&
            (w.painter! as TgPageEdgeShadowPainter).coverage == 0.75),
        findsOneWidget,
      );

      // Release at x = 200 < width/3 ≈ 266.7 → cancel over
      // max(320·200/800, 120) = 120ms with the gesture mode held.
      await gesture.up();
      await tester.pump();
      expect(_nav(tester).userGestureInProgress, isTrue);
      await tester.pump(const Duration(milliseconds: 60));
      // easeBoth(0.5) = 0.5 → x = 200·0.5 = 100.
      expect(_dxOf(tester, _p2), closeTo(100.0, 0.5));
      await tester.pump(const Duration(milliseconds: 60));
      expect(_dxOf(tester, _p2), 0.0);
      // The settle's status flips on the first tick past 120ms, releasing
      // the navigator's user-gesture lock.
      await tester.pump(const Duration(milliseconds: 1));
      expect(_nav(tester).userGestureInProgress, isFalse);
      expect(find.byKey(_p2), findsOneWidget); // not popped
    });

    testWidgets('commit past width/3 pops with the formula duration',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      final TgPageRoute<void> route = await _push(tester);
      await tester.pumpAndSettle();

      final TestGesture gesture =
          await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(40, 0)); // start + rebase
      await gesture.moveBy(const Offset(400, 0)); // track to x = 400
      await tester.pump();
      expect(_dxOf(tester, _p2), 400.0);

      // x = 400 ≥ 266.7 → commit; duration max(200·400/800, 50) = 100ms.
      await gesture.up();
      await tester.pump();
      expect(route.isCurrent, isFalse); // popped immediately
      expect(_nav(tester).userGestureInProgress, isTrue);
      await tester.pump(const Duration(milliseconds: 50));
      // easeBoth(0.5) = 0.5 → x = 400 + 400·0.5 = 600; still no fade.
      expect(_dxOf(tester, _p2), closeTo(600.0, 0.5));
      expect(_opacityOf(tester, _p2), 1.0);
      await tester.pump(const Duration(milliseconds: 49)); // 99ms
      expect(find.byKey(_p2), findsOneWidget); // still settling
      await tester.pump(const Duration(milliseconds: 2)); // 101ms: landed
      await tester.pump();
      expect(find.byKey(_p2), findsNothing);
      expect(find.byKey(_p1), findsOneWidget);
      expect(_nav(tester).userGestureInProgress, isFalse);
    });

    testWidgets('a 3500px/s fling commits below the distance threshold',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      await _push(tester);
      await tester.pumpAndSettle();

      // 24px total (< 25.2) at ~6000 px/s (device pixel ratio 1 in this
      // harness) — the fling-start path (ActionBarLayout.java:1483).
      final TestGesture gesture =
          await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(6, 0),
          timeStamp: const Duration(milliseconds: 1));
      await gesture.moveBy(const Offset(6, 0),
          timeStamp: const Duration(milliseconds: 2));
      await gesture.moveBy(const Offset(6, 0),
          timeStamp: const Duration(milliseconds: 3));
      await gesture.moveBy(const Offset(6, 0),
          timeStamp: const Duration(milliseconds: 4));
      await gesture.up(timeStamp: const Duration(milliseconds: 5));
      await tester.pump();
      expect(_nav(tester).userGestureInProgress, isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(_p2), findsNothing);
      expect(find.byKey(_p1), findsOneWidget);
    });

    testWidgets('no swipe-back on the first route',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      final TestGesture gesture =
          await tester.startGesture(const Offset(100, 300));
      await gesture.moveBy(const Offset(400, 0));
      await tester.pump();
      expect(_nav(tester).userGestureInProgress, isFalse);
      expect(tester.getTopLeft(find.byKey(_p1)), Offset.zero);
      await gesture.up();
      await tester.pump();
    });
  });

  group('TgPageTransitionsBuilder', () {
    testWidgets('drives a foreign PageRoute — visuals only, no gesture',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _nav(tester).push(_TransitionsBuilderRoute<void>(
        builder: (BuildContext context) =>
            _page(_p2, const Color(0xFF4488AA)),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(_dxOf(tester, _p2), closeTo(6.0, 1e-9));
      expect(find.byType(TgPageTransition), findsWidgets);
      await tester.pumpAndSettle();

      // No TgRouteTransitionMixin on the route: dragging must not move it.
      final TestGesture gesture =
          await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(300, 0));
      await tester.pump();
      expect(_dxOf(tester, _p2), 0.0);
      expect(_nav(tester).userGestureInProgress, isFalse);
      await gesture.up();
      await tester.pump();
    });
  });

  group('semantics', () {
    testWidgets('the page carries scopesRoute semantics',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      await _push(tester);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((Widget w) =>
            w is Semantics && w.properties.scopesRoute == true),
        findsWidgets,
      );
    });
  });

  group('TgPageEdgeShadowPainter', () {
    test('alpha ramps 255·widthOffset/20dp, clamped', () {
      expect(TgPageEdgeShadowPainter.rampAlpha(0.0), 0);
      expect(TgPageEdgeShadowPainter.rampAlpha(10.0), 127); // 127.5 truncated
      expect(TgPageEdgeShadowPainter.rampAlpha(20.0), 255);
      expect(TgPageEdgeShadowPainter.rampAlpha(600.0), 255);
    });

    test('repaints on coverage or direction change', () {
      const TgPageEdgeShadowPainter painter =
          TgPageEdgeShadowPainter(coverage: 0.5);
      expect(
        painter.shouldRepaint(const TgPageEdgeShadowPainter(coverage: 0.5)),
        isFalse,
      );
      expect(
        painter.shouldRepaint(const TgPageEdgeShadowPainter(coverage: 0.6)),
        isTrue,
      );
      expect(
        painter.shouldRepaint(const TgPageEdgeShadowPainter(
          coverage: 0.5,
          textDirection: TextDirection.rtl,
        )),
        isTrue,
      );
    });
  });
}

/// A plain [PageRoute] wired through [TgPageTransitionsBuilder] — the
/// theme-wide installation path (e.g. a Material `PageTransitionsTheme`).
class _TransitionsBuilderRoute<T> extends PageRoute<T> {
  _TransitionsBuilderRoute({required this.builder});

  final WidgetBuilder builder;

  static const TgPageTransitionsBuilder _transitions =
      TgPageTransitionsBuilder();

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => _transitions.transitionDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _transitions.buildTransitions<T>(
        this, context, animation, secondaryAnimation, child);
  }
}
