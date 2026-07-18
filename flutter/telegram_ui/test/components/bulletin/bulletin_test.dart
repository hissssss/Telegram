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
//    variant.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/bulletin/bulletin.dart';
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
}
