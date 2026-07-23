// Tests for lib/src/components/bulletin/bulletin.dart (ARCHITECTURE.md
// section 6, row "Bulletin"), golden-free:
//
//  * constants against the Java values (Bulletin.java, cited per constant),
//    including the enter/exit spring (damping 0.8 / stiffness 400 / mass 1,
//    Bulletin.java:1121-1172) and the Android interpolator ports;
//  * banner geometry: min height 48dp, 16/8dp padding, full width, 16dp
//    round-rect `undo_background` (Bulletin.java:797-817);
//  * leading 56x48 frame + 15dp `undo_infoColor` text placement
//    (Bulletin.java:1983-2008);
//  * trailing action: 14dp Roboto Medium `undo_cancelColor`, runs the
//    action then hides (Bulletin.java:2256-2292);
//  * enter spring motion from below the screen edge to rest;
//  * auto-hide timer semantics (posted after enter, full-delay re-post on
//    release, Bulletin.java:393-403), press-to-pause;
//  * swipe-to-dismiss: width/3 threshold, 200ms settle out / settle back
//    (Bulletin.java:645-655);
//  * single-visible semantics (Bulletin.java:285-288) and the glass
//    variant;
//  * the undo variant (UndoView.java countdown recipe): ring/digit
//    constants (UndoView.java:319-330, 482, 1660, 1673, 1694), countdown
//    ticks + digit swap animation, expiry auto-hide (UndoView.java:
//    1697-1703), undo-cancels-commit vs dismiss-commits semantics
//    (UndoView.java:384-403), and `undo_infoColor` resolution both ways.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/bulletin/bulletin.dart';
import 'package:telegram_ui/src/foundation/tg_text_styles.dart';
import 'package:telegram_ui/src/glass/glass_panel.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

const Key _hostKey = ValueKey<String>('host');

/// Theme + directionality + media query + a bare overlay hosting an empty
/// page whose context is used to call [Bulletin.show].
Widget _host({EdgeInsets padding = EdgeInsets.zero}) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: const Size(800, 600), padding: padding),
        child: Overlay(
          initialEntries: <OverlayEntry>[
            OverlayEntry(
              builder: (BuildContext context) =>
                  const SizedBox.expand(key: _hostKey),
            ),
          ],
        ),
      ),
    ),
  );
}

BuildContext _context(WidgetTester tester) =>
    tester.element(find.byKey(_hostKey));

Finder get _banner => find.byKey(Bulletin.bannerKey);

/// The countdown painter of the current frame (the undo variant's leading
/// circle).
BulletinCountdownPainter _countdownPainter(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(find.descendant(
    of: find.byKey(Bulletin.countdownKey),
    matching: find.byType(CustomPaint),
  ));
  return paint.painter! as BulletinCountdownPainter;
}

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      // DURATION_SHORT/LONG/PROLONG (Bulletin.java:89-91).
      expect(kBulletinDurationShort, const Duration(milliseconds: 1500));
      expect(kBulletinDurationDefault, const Duration(milliseconds: 2750));
      expect(kBulletinDurationLong, const Duration(milliseconds: 5000));
      expect(kBulletinMinHeight, 48.0); // Bulletin.java:797
      expect(kBulletinHorizontalPadding, 16.0); // Bulletin.java:800
      expect(kBulletinVerticalPadding, 8.0); // Bulletin.java:800
      // setBackground(color, 16) (Bulletin.java:810-816) — 16dp, not 8.
      expect(kBulletinRadius, 16.0);
      expect(kBulletinTextSize, 15.0); // Bulletin.java:2002
      expect(kBulletinLeadingWidth, 56.0); // Bulletin.java:1985
      expect(kBulletinLeadingHeight, 48.0); // Bulletin.java:1985
      expect(kBulletinTextEndMargin, 16.0); // Bulletin.java:2005
      expect(kBulletinActionTextSize, 14.0); // Bulletin.java:2259
      // SpringTransition (Bulletin.java:1123-1124).
      expect(kBulletinSpringDampingRatio, 0.8);
      expect(kBulletinSpringStiffness, 400.0);
      // width/3 threshold, 200ms settle (Bulletin.java:645-655).
      expect(kBulletinSwipeThresholdFraction, 1 / 3);
      expect(kBulletinSwipeSettleDuration, const Duration(milliseconds: 200));
    });

    test('undo variant constants mirror UndoView.java', () {
      // timeLeft = 5000 (UndoView.java:482).
      expect(kBulletinUndoDuration, const Duration(milliseconds: 5000));
      // rect dp(15)..dp(15 + 18) (UndoView.java:319).
      expect(kBulletinCountdownSize, 18.0);
      // progressPaint.setStrokeWidth(dp(2)) (UndoView.java:323).
      expect(kBulletinCountdownStroke, 2.0);
      // textPaint.setTextSize(dp(12)) (UndoView.java:328), the
      // microEmphasis role (12dp Roboto Medium).
      expect(kBulletinCountdownTextSize, 12.0);
      expect(TgTextStyles.microEmphasis.fontSize, kBulletinCountdownTextSize);
      // -360 * (timeLeft / 5000.0f) (UndoView.java:1694).
      expect(kBulletinCountdownSweepDivisorMs, 5000);
      // timeReplaceProgress += 16f / 150f (UndoView.java:1660).
      expect(kBulletinCountdownDigitSwapDuration,
          const Duration(milliseconds: 150));
      // dp(10) digit travel (UndoView.java:1673, 1684).
      expect(kBulletinCountdownDigitSlide, 10.0);
    });

    test('spring is dampingRatio 0.8 / stiffness 400 / mass 1', () {
      final SpringDescription spring = kBulletinSpring;
      expect(spring.mass, 1.0);
      expect(spring.stiffness, 400.0);
      // damping coefficient = ratio * 2 * sqrt(stiffness * mass) = 32.
      expect(spring.damping, moreOrLessEquals(32.0));
    });

    test('Android interpolator ports', () {
      // AccelerateInterpolator: f(t) = t^2.
      const BulletinAccelerateCurve accelerate = BulletinAccelerateCurve();
      expect(accelerate.transform(0.5), 0.25);
      expect(accelerate.transform(0.25), 0.0625);
      // AccelerateDecelerateInterpolator: cos((t+1)pi)/2 + 0.5.
      const BulletinAccelerateDecelerateCurve accDec =
          BulletinAccelerateDecelerateCurve();
      expect(accDec.transform(0.5), moreOrLessEquals(0.5));
      expect(accDec.transform(0.25), moreOrLessEquals(0.14644660940));
    });
  });

  group('geometry and colors', () {
    testWidgets('text-only banner: full width, min height 48, 16dp radius '
        'undo_background, 15dp undo_infoColor text at 16dp',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController controller =
          Bulletin.show(_context(tester), text: 'Saved', duration: null);
      await tester.pumpAndSettle();

      // MATCH_PARENT width (Bulletin.java:866), min height 48
      // (Bulletin.java:797) — one 15dp line + 8dp text pads + 8dp layout
      // pads stays under the minimum.
      expect(tester.getSize(_banner), const Size(800, 48));
      expect(tester.getBottomLeft(_banner).dy, 600.0);

      final DecoratedBox box = tester.widget<DecoratedBox>(find.descendant(
        of: _banner,
        matching: find.byType(DecoratedBox),
      ));
      final BoxDecoration decoration = box.decoration as BoxDecoration;
      expect(
          decoration.color, _dayTheme.color(TelegramColorKey.undo_background));
      expect(decoration.borderRadius,
          BorderRadius.circular(kBulletinRadius)); // Bulletin.java:815

      // No leading: text starts at the 16dp container padding.
      expect(tester.getRect(find.text('Saved')).left, 16.0);
      final Text text = tester.widget<Text>(find.text('Saved'));
      expect(text.style!.fontSize, kBulletinTextSize);
      expect(
          text.style!.color, _dayTheme.color(TelegramColorKey.undo_infoColor));

      controller.hide(animated: false);
      await tester.pump();
      expect(_banner, findsNothing);
    });

    testWidgets('leading slot: 56x48 frame at the padded start, text at 72',
        (WidgetTester tester) async {
      const Key iconKey = ValueKey<String>('icon');
      await tester.pumpWidget(_host());
      final BulletinController controller = Bulletin.show(
        _context(tester),
        text: 'Copied',
        leading: const SizedBox(key: iconKey, width: 24, height: 24),
        duration: null,
      );
      await tester.pumpAndSettle();

      // 48dp frame + 8+8dp layout padding (Bulletin.java:797-800, 1985).
      expect(tester.getSize(_banner), const Size(800, 64));

      final Rect frame = tester.getRect(find.byKey(Bulletin.leadingKey));
      expect(frame.size, const Size(56, 48));
      expect(frame.left, 16.0); // start of the padded frame
      expect(frame.center.dy, tester.getRect(_banner).center.dy);

      // Text margin start 56 realized by the frame width
      // (Bulletin.java:2005): 16 + 56 = 72.
      expect(tester.getRect(find.text('Copied')).left, 72.0);

      controller.hide(animated: false);
      await tester.pump();
    });

    testWidgets('action button: 14dp RobotoMedium undo_cancelColor; tap runs '
        'the action then hides (Bulletin.java:2279-2292)',
        (WidgetTester tester) async {
      int actions = 0;
      await tester.pumpWidget(_host());
      final BulletinController controller = Bulletin.show(
        _context(tester),
        text: 'Deleted',
        actionText: 'Undo',
        onAction: () => actions++,
        duration: null,
      );
      await tester.pumpAndSettle();

      final Text action = tester.widget<Text>(find.text('Undo'));
      expect(action.style!.fontSize, kBulletinActionTextSize);
      expect(action.style!.fontFamily, 'packages/telegram_ui/RobotoMedium');
      expect(action.style!.fontWeight, FontWeight.w500);
      expect(action.style!.color,
          _dayTheme.color(TelegramColorKey.undo_cancelColor));

      await tester.tap(find.byKey(Bulletin.actionKey));
      await tester.pumpAndSettle();
      expect(actions, 1);
      expect(_banner, findsNothing);
      expect(controller.isShowing, isFalse);
    });

    testWidgets('stacks above bottom insets plus the delegate offset',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(padding: const EdgeInsets.only(bottom: 34)));
      final BulletinController controller = Bulletin.show(
        _context(tester),
        text: 'Saved',
        bottomOffset: 10.0,
        duration: null,
      );
      await tester.pumpAndSettle();
      // 600 - 34 (inset) - 10 (delegate offset), Bulletin.java:352-366.
      expect(tester.getBottomLeft(_banner).dy, 600.0 - 34.0 - 10.0);

      controller.hide(animated: false);
      await tester.pump();
    });

    testWidgets('resources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color override = Color(0xFF654321);
      await tester.pumpWidget(_host());
      final BulletinController controller = Bulletin.show(
        _context(tester),
        text: 'Saved',
        duration: null,
        resources: ResourcesOverride(
          parent: TelegramTheme.resources(_context(tester)),
          overrides: const <int, Color>{
            TelegramColorKey.undo_infoColor: override,
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('Saved')).style!.color, override);

      controller.hide(animated: false);
      await tester.pump();
    });

    testWidgets('useGlass renders a GlassPanel instead of the solid fill',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController controller = Bulletin.show(
        _context(tester),
        text: 'Saved',
        useGlass: true,
        duration: null,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _banner, matching: find.byType(GlassPanel)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _banner, matching: find.byType(DecoratedBox)),
        findsNothing,
      );

      controller.hide(animated: false);
      await tester.pump();
    });
  });

  group('enter/exit spring', () {
    testWidgets('enters from below the screen edge and settles at rest',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController controller =
          Bulletin.show(_context(tester), text: 'Saved', duration: null);
      await tester.pump();

      // t = 0: inOutOffset == height (Bulletin.java:1128) — fully below.
      expect(tester.getTopLeft(_banner).dy, moreOrLessEquals(600.0));

      // Mid-flight: above the edge, below rest.
      await tester.pump(const Duration(milliseconds: 50));
      final double mid = tester.getTopLeft(_banner).dy;
      expect(mid, lessThan(600.0));
      expect(mid, greaterThan(552.0));

      // The 0.8/400 spring is critically-enough damped to be within 1px of
      // rest after 400ms (envelope e^(-zeta*omega*t) ~ 0.0017).
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.getTopLeft(_banner).dy, moreOrLessEquals(552.0, epsilon: 1.0));

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_banner).dy, moreOrLessEquals(552.0));

      // Exit runs the same spring back below the edge
      // (Bulletin.java:1152-1171).
      controller.hide();
      await tester.pump(); // exit ticker's zero frame
      await tester.pump(const Duration(milliseconds: 50));
      final double exitMid = tester.getTopLeft(_banner).dy;
      expect(exitMid, greaterThan(552.0));
      expect(exitMid, lessThan(600.0));
      expect(controller.isShowing, isTrue);

      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
      expect(controller.isShowing, isFalse);
      await expectLater(controller.closed, completes);
    });
  });

  group('auto-hide timer', () {
    testWidgets('hides after the default 2750ms, counted from enter end',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController controller =
          Bulletin.show(_context(tester), text: 'Saved');
      await tester.pumpAndSettle();
      expect(_banner, findsOneWidget);

      // Well before the deadline: still visible.
      await tester.pump(const Duration(milliseconds: 2500));
      expect(_banner, findsOneWidget);

      // Past 2750ms since enter end: exit runs and the entry leaves.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
      expect(controller.isShowing, isFalse);
    });

    testWidgets('custom short duration (DURATION_SHORT)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      Bulletin.show(_context(tester), text: 'Saved',
          duration: kBulletinDurationShort);
      await tester.pumpAndSettle();

      await tester.pump(const Duration(milliseconds: 1300));
      expect(_banner, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
    });

    testWidgets('null duration never auto-hides (the duration < 0 gate, '
        'Bulletin.java:397)', (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController controller =
          Bulletin.show(_context(tester), text: 'Pinned', duration: null);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      expect(_banner, findsOneWidget);

      controller.hide();
      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
    });

    testWidgets('press pauses the timer; release re-posts the full delay '
        '(setCanHide, Bulletin.java:393-403)', (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      Bulletin.show(_context(tester), text: 'Saved',
          duration: kBulletinDurationShort);
      await tester.pumpAndSettle();

      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(_banner));
      // Held well past the 1500ms deadline: the timer is paused.
      await tester.pump(const Duration(milliseconds: 4000));
      expect(_banner, findsOneWidget);

      await gesture.up();
      await tester.pump();
      // The release re-posts the full 1500ms delay.
      await tester.pump(const Duration(milliseconds: 1300));
      expect(_banner, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
    });
  });

  group('swipe to dismiss', () {
    testWidgets('a drag past width/3 settles out over 200ms and removes the '
        'bulletin (Bulletin.java:645-653)', (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController controller =
          Bulletin.show(_context(tester), text: 'Saved', duration: null);
      await tester.pumpAndSettle();

      // 800/3 = 266.7 threshold; 350 - touch slop is comfortably past it.
      await tester.drag(_banner, const Offset(350, 0));
      await tester.pump();
      expect(_banner, findsOneWidget); // settling out
      await tester.pump(kBulletinSwipeSettleDuration);
      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
      expect(controller.isShowing, isFalse);
    });

    testWidgets('a drag below width/3 settles back to rest '
        '(Bulletin.java:655)', (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController controller =
          Bulletin.show(_context(tester), text: 'Saved', duration: null);
      await tester.pumpAndSettle();

      await tester.drag(_banner, const Offset(100, 0));
      await tester.pump();
      // Mid-settle: displaced but coming back.
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(_banner).dx, greaterThan(0.0));

      await tester.pump(kBulletinSwipeSettleDuration);
      await tester.pumpAndSettle();
      expect(_banner, findsOneWidget);
      expect(tester.getTopLeft(_banner).dx, moreOrLessEquals(0.0));
      expect(controller.isShowing, isTrue);

      controller.hide(animated: false);
      await tester.pump();
    });
  });

  group('visibility bookkeeping', () {
    testWidgets('showing a new bulletin hides the current one '
        '(Bulletin.java:285-288)', (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController first =
          Bulletin.show(_context(tester), text: 'One', duration: null);
      await tester.pumpAndSettle();
      expect(identical(Bulletin.visible, first), isTrue);

      final BulletinController second =
          Bulletin.show(_context(tester), text: 'Two', duration: null);
      expect(identical(Bulletin.visible, second), isTrue);
      await tester.pumpAndSettle();

      expect(find.text('One'), findsNothing);
      expect(first.isShowing, isFalse);
      expect(find.text('Two'), findsOneWidget);

      Bulletin.hideVisible(); // Bulletin.java:214-218
      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
      expect(Bulletin.visible, isNull);
      expect(second.isShowing, isFalse);
    });

    testWidgets('hide is idempotent and closed completes once',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController controller =
          Bulletin.show(_context(tester), text: 'Saved', duration: null);
      await tester.pumpAndSettle();

      controller.hide();
      controller.hide();
      controller.hide(animated: false);
      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
      await expectLater(controller.closed, completes);
    });

    testWidgets(
        'two shows in one event handler (same frame) do not crash and leave '
        'only the second visible', (WidgetTester tester) async {
      // OverlayEntry.mounted stays false until the overlay rebuilds, so the
      // first bulletin is hidden while its entry is inserted-but-unmounted:
      // _finish must still remove + dispose it (a mounted-guarded remove
      // asserted in dispose and left a permanent ghost entry).
      await tester.pumpWidget(_host());
      final BuildContext context = _context(tester);
      final BulletinController first =
          Bulletin.show(context, text: 'One', duration: null);
      final BulletinController second =
          Bulletin.show(context, text: 'Two', duration: null);
      expect(tester.takeException(), isNull);
      expect(first.isShowing, isFalse);
      expect(identical(Bulletin.visible, second), isTrue);

      await tester.pumpAndSettle();
      expect(find.text('One'), findsNothing);
      expect(find.text('Two'), findsOneWidget);
      await expectLater(first.closed, completes);

      second.hide(animated: false);
      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
    });

    testWidgets('hide in the same frame as show removes the entry cleanly',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController controller =
          Bulletin.show(_context(tester), text: 'Saved', duration: null);
      controller.hide(); // _state is still null: straight to _finish().
      expect(tester.takeException(), isNull);
      expect(controller.isShowing, isFalse);
      expect(Bulletin.visible, isNull);

      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
      await expectLater(controller.closed, completes);
    });

    testWidgets(
        'external overlay teardown while showing completes closed and '
        'disposes the entry', (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController controller =
          Bulletin.show(_context(tester), text: 'Saved', duration: null);
      await tester.pumpAndSettle();
      expect(controller.isShowing, isTrue);

      // Tear the whole app (and its overlay) down without a hide().
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
      expect(controller.isShowing, isFalse);
      expect(Bulletin.visible, isNull);
      await expectLater(controller.closed, completes);
    });
  });

  group('undo variant', () {
    testWidgets('renders an 18x18 countdown centered in the leading frame '
        'plus the trailing undo action', (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController controller = Bulletin.showUndo(
        _context(tester),
        text: 'Chat deleted',
        undoText: 'Undo',
      );
      await tester.pump();

      final Rect frame = tester.getRect(find.byKey(Bulletin.leadingKey));
      final Rect ring = tester.getRect(find.byKey(Bulletin.countdownKey));
      // 18dp circle (UndoView.java:319) centered in the standard 56x48
      // leading frame (documented divergence from the absolute (15,15)
      // placement).
      expect(ring.size, const Size.square(kBulletinCountdownSize));
      expect(ring.center.dx, moreOrLessEquals(frame.center.dx));
      expect(ring.center.dy, moreOrLessEquals(frame.center.dy));

      // Trailing undo action: 14dp Roboto Medium undo_cancelColor
      // (UndoView.java:312-316 — same recipe as Bulletin's UndoButton).
      final Text action = tester.widget<Text>(find.text('Undo'));
      expect(action.style!.fontSize, kBulletinActionTextSize);
      expect(action.style!.fontFamily, 'packages/telegram_ui/RobotoMedium');
      expect(action.style!.color,
          _dayTheme.color(TelegramColorKey.undo_cancelColor));

      controller.hide(animated: false);
      await tester.pump();
    });

    testWidgets('countdown ticks: full ring and 5 at start, then the digit '
        'drops and the ring depletes (UndoView.java:1645-1694)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController controller = Bulletin.showUndo(
        _context(tester),
        text: 'Chat deleted',
        undoText: 'Undo',
      );
      await tester.pump();

      // t = 0: timeLeft 5000 -> ceil(5000/1000) = 5, ring 5000/5000 = 1.
      BulletinCountdownPainter painter = _countdownPainter(tester);
      expect(painter.seconds, 5);
      expect(painter.ringFraction, moreOrLessEquals(1.0));
      expect(painter.swapProgress, 1.0);
      expect(painter.outSeconds, isNull);

      // t = 500: timeLeft 4500 -> still 5, ring 0.9.
      await tester.pump(const Duration(milliseconds: 500));
      painter = _countdownPainter(tester);
      expect(painter.seconds, 5);
      expect(painter.ringFraction, moreOrLessEquals(0.9));

      // t = 1100: timeLeft 3900 -> 4; the 150ms digit swap starts
      // (UndoView.java:1647-1656): old 5 fading down, new 4 sliding in.
      await tester.pump(const Duration(milliseconds: 600));
      painter = _countdownPainter(tester);
      expect(painter.seconds, 4);
      expect(painter.outSeconds, 5);
      expect(painter.swapProgress, 0.0);
      expect(painter.ringFraction, moreOrLessEquals(3900 / 5000));

      // Mid-swap at +75ms of 150ms (16f/150f per frame recipe,
      // UndoView.java:1660).
      await tester.pump(const Duration(milliseconds: 75));
      painter = _countdownPainter(tester);
      expect(painter.swapProgress, moreOrLessEquals(0.5));

      // Swap done at +150ms.
      await tester.pump(const Duration(milliseconds: 75));
      painter = _countdownPainter(tester);
      expect(painter.swapProgress, 1.0);
      expect(painter.seconds, 4);

      controller.hide(animated: false);
      await tester.pump();
    });

    testWidgets('countdowns longer than 5s clamp the ring to a full circle '
        '(the literal 5000 divisor, UndoView.java:1694)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController controller = Bulletin.showUndo(
        _context(tester),
        text: 'Chat deleted',
        undoText: 'Undo',
        countdown: const Duration(seconds: 10),
      );
      await tester.pump();

      BulletinCountdownPainter painter = _countdownPainter(tester);
      expect(painter.seconds, 10);
      expect(painter.ringFraction, 1.0); // 10000/5000 clamped

      // t = 6100: timeLeft 3900 -> seconds 4, ring 3900/5000.
      await tester.pump(const Duration(milliseconds: 6100));
      painter = _countdownPainter(tester);
      expect(painter.seconds, 4);
      expect(painter.ringFraction, moreOrLessEquals(3900 / 5000));

      controller.hide(animated: false);
      await tester.pump();
    });

    testWidgets('expiry hides the bulletin and runs onCommit, not onUndo '
        '(timeLeft <= 0 -> hide(true), UndoView.java:1697-1703)',
        (WidgetTester tester) async {
      int commits = 0;
      int undos = 0;
      await tester.pumpWidget(_host());
      final BulletinController controller = Bulletin.showUndo(
        _context(tester),
        text: 'Chat deleted',
        undoText: 'Undo',
        onUndo: () => undos++,
        onCommit: () => commits++,
      );
      await tester.pump();

      // Just before expiry: still up (the digit floors at 1,
      // UndoView.java:1649).
      await tester.pump(const Duration(milliseconds: 4900));
      expect(_banner, findsOneWidget);
      expect(_countdownPainter(tester).seconds, 1);
      expect(commits, 0);

      // Past 5000ms the countdown empties -> exit spring -> removal.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
      expect(controller.isShowing, isFalse);
      expect(commits, 1);
      expect(undos, 0);
    });

    testWidgets('undo runs onUndo, hides, and cancels the commit '
        '(hide(false, 1), UndoView.java:300-305, 391-403)',
        (WidgetTester tester) async {
      int commits = 0;
      int undos = 0;
      await tester.pumpWidget(_host());
      final BulletinController controller = Bulletin.showUndo(
        _context(tester),
        text: 'Chat deleted',
        undoText: 'Undo',
        onUndo: () => undos++,
        onCommit: () => commits++,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600)); // enter settled

      await tester.tap(find.byKey(Bulletin.actionKey));
      await tester.pump();
      expect(undos, 1);
      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
      expect(controller.isShowing, isFalse);
      expect(commits, 0); // apply == false skips the action runnable
      expect(undos, 1);

      // The countdown never fires a late expiry after removal.
      await tester.pump(const Duration(seconds: 6));
      expect(commits, 0);
    });

    testWidgets('swipe-dismiss commits (any non-undo dismissal is '
        'apply == true, UndoView.java:391-396)', (WidgetTester tester) async {
      int commits = 0;
      await tester.pumpWidget(_host());
      Bulletin.showUndo(
        _context(tester),
        text: 'Chat deleted',
        undoText: 'Undo',
        onCommit: () => commits++,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      await tester.drag(_banner, const Offset(350, 0)); // past 800/3
      await tester.pump();
      // The settle simulation is done strictly after 200ms; one extra ms
      // finishes it, one extra frame removes the entry.
      await tester.pump(kBulletinSwipeSettleDuration +
          const Duration(milliseconds: 1));
      await tester.pump();
      expect(_banner, findsNothing);
      expect(commits, 1);
    });

    testWidgets('replacement by another bulletin commits',
        (WidgetTester tester) async {
      int commits = 0;
      await tester.pumpWidget(_host());
      Bulletin.showUndo(
        _context(tester),
        text: 'Chat deleted',
        undoText: 'Undo',
        onCommit: () => commits++,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Showing a new bulletin hides the undo one (Bulletin.java:285-288) —
      // an apply-side dismissal.
      final BulletinController second =
          Bulletin.show(_context(tester), text: 'Two', duration: null);
      await tester.pumpAndSettle();
      expect(commits, 1);

      second.hide(animated: false);
      await tester.pump();
    });

    testWidgets('ring and digits use undo_infoColor; a resources override '
        'wins (UndoView.java:325, 330)', (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      final BulletinController first = Bulletin.showUndo(
        _context(tester),
        text: 'Chat deleted',
        undoText: 'Undo',
      );
      await tester.pump();
      expect(_countdownPainter(tester).color,
          _dayTheme.color(TelegramColorKey.undo_infoColor));
      first.hide(animated: false);
      await tester.pump();

      const Color override = Color(0xFF123456);
      final BulletinController second = Bulletin.showUndo(
        _context(tester),
        text: 'Chat deleted',
        undoText: 'Undo',
        resources: ResourcesOverride(
          parent: TelegramTheme.resources(_context(tester)),
          overrides: const <int, Color>{
            TelegramColorKey.undo_infoColor: override,
          },
        ),
      );
      await tester.pump();
      expect(_countdownPainter(tester).color, override);
      second.hide(animated: false);
      await tester.pump();
    });
  });
}
