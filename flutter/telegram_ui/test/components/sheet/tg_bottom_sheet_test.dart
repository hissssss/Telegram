// Tests for lib/src/components/sheet/tg_bottom_sheet.dart (ARCHITECTURE.md
// section 6, row "TgBottomSheet"), golden-free:
//
//  * constants against the Java values (BottomSheet.java, cited per
//    constant);
//  * route motion: open 250ms DEFAULT (BottomSheet.java:1739-1741) /
//    dismiss 180ms EASE_OUT (BottomSheet.java:1870-1871), verified both on
//    the route fields and by sampling the slide mid-flight;
//  * barrier: black at 51/255 (BottomSheet.java:218-219), tap-outside
//    dismiss (BottomSheet.java:198, 1647-1649);
//  * title row geometry and styles (BottomSheet.java:1388-1413);
//  * item cell geometry: 48dp rows, 56x48 icon frame, 72/16dp text insets
//    (BottomSheet.java:1019-1083, 1105-1125), tap-to-pop values;
//  * container padding 8/8 + bottom inset (BottomSheet.java:1357);
//  * solid `dialogBackground` fill vs the FrostedPanel glass variant;
//  * color keys `dialogTextBlack`/`dialogTextGray2`/`dialogIcon`.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/sheet/tg_bottom_sheet.dart';
import 'package:telegram_ui/src/foundation/tg_curves.dart';
import 'package:telegram_ui/src/glass/glass_panel.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

const Size _screen = Size(800, 600);

/// A bare app: theme + directionality + media query + navigator with an
/// empty home page.
Widget _app({EdgeInsets padding = EdgeInsets.zero}) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: _screen, padding: padding),
        child: Navigator(
          onGenerateRoute: (RouteSettings settings) => PageRouteBuilder<void>(
            settings: settings,
            pageBuilder: (BuildContext context, _, _) =>
                const ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
    ),
  );
}

NavigatorState _navigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator));

Finder get _panel => find.byKey(TgBottomSheetRoute.panelKey);

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      // sheet_shadow_round replicated radius (PollVotesAlert.java:776).
      expect(kSheetCornerRadius, 12.0);
      expect(kSheetDimBehindAlpha, 51 / 255); // BottomSheet.java:219
      expect(kSheetBarrierColor, const Color(0x33000000));
      expect(kSheetTitleRowHeight, 48.0); // BottomSheet.java:1389
      expect(kSheetBigTitleTextSize, 20.0); // BottomSheet.java:1393
      expect(kSheetTitleTextSize, 16.0); // BottomSheet.java:1398
      expect(kSheetBigTitleHorizontalPadding, 21.0); // BottomSheet.java:1395
      expect(kSheetTitleHorizontalPadding, 16.0); // BottomSheet.java:1399
      expect(kSheetCellHeight, 48.0); // BottomSheet.java:1079-1081
      expect(kSheetCellIconFrameWidth, 56.0); // BottomSheet.java:1044
      expect(kSheetCellIconFrameHeight, 48.0); // BottomSheet.java:1044
      expect(kSheetCellTextSize, 16.0); // BottomSheet.java:1058
      expect(kSheetCellTextInsetWithIcon, 72.0); // BottomSheet.java:1117
      expect(kSheetVerticalPadding, 8.0); // BottomSheet.java:1357
      // Open 250ms DEFAULT (BottomSheet.java:1739-1741), dismiss 180ms
      // EASE_OUT (BottomSheet.java:1870-1871), companions 320ms
      // EASE_OUT_QUINT (BottomSheet.java:502-512).
      expect(kSheetOpenDuration, const Duration(milliseconds: 250));
      expect(kSheetOpenCurve, TgCurves.defaultCubic);
      expect(kSheetDismissDuration, const Duration(milliseconds: 180));
      expect(kSheetDismissCurve, TgCurves.easeOut);
      expect(kSheetCompanionDuration, const Duration(milliseconds: 320));
    });

    test('route defaults mirror the Java dialog defaults', () {
      final TgBottomSheetRoute<void> route = TgBottomSheetRoute<void>();
      expect(route.transitionDuration, kSheetOpenDuration);
      expect(route.reverseTransitionDuration, kSheetDismissDuration);
      expect(route.openCurve, TgCurves.defaultCubic);
      expect(route.dismissCurve, TgCurves.easeOut);
      // dimBehind = true, alpha 51 (BottomSheet.java:218-219).
      expect(route.barrierColor, kSheetBarrierColor);
      // canDismissWithTouchOutside = true (BottomSheet.java:198).
      expect(route.barrierDismissible, isTrue);
    });

    test('dimBehind=false removes the barrier color; dimAlpha rescales it',
        () {
      expect(TgBottomSheetRoute<void>(dimBehind: false).barrierColor, isNull);
      expect(
        TgBottomSheetRoute<void>(dimAlpha: 102 / 255).barrierColor,
        const Color(0x66000000),
      );
    });
  });

  group('route motion', () {
    testWidgets('opens by sliding the panel up over 250ms DEFAULT',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      final TgBottomSheetRoute<void> route = TgBottomSheetRoute<void>(
        items: const <TgBottomSheetItem<void>>[
          TgBottomSheetItem<void>(text: 'One'),
          TgBottomSheetItem<void>(text: 'Two'),
        ],
      );
      _navigator(tester).push(route);
      await tester.pump(); // Build the route at t = 0.

      // Panel: 8 + 48 + 48 + 8 = 112dp tall (BottomSheet.java:1357,
      // 1440-1441); rest top at 600 - 112 = 488.
      const double panelHeight = 112.0;
      const double restTop = 600.0 - panelHeight;

      // t = 0: fully below the screen edge.
      expect(tester.getTopLeft(_panel).dy, moreOrLessEquals(600.0));

      // t = 125/250: translated by 1 - DEFAULT(0.5) of the panel height.
      await tester.pump(const Duration(milliseconds: 125));
      final double expectedMid =
          restTop + (1 - TgCurves.defaultCubic.transform(0.5)) * panelHeight;
      expect(tester.getTopLeft(_panel).dy, moreOrLessEquals(expectedMid));
      expect(tester.getTopLeft(_panel).dy, greaterThan(restTop));
      expect(tester.getTopLeft(_panel).dy, lessThan(600.0));

      // t = 250: settled.
      await tester.pump(const Duration(milliseconds: 125));
      expect(tester.getTopLeft(_panel).dy, moreOrLessEquals(restTop));
      expect(tester.getSize(_panel), const Size(800, panelHeight));
    });

    testWidgets('dismisses by sliding down over 180ms EASE_OUT',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      final TgBottomSheetRoute<void> route = TgBottomSheetRoute<void>(
        items: const <TgBottomSheetItem<void>>[
          TgBottomSheetItem<void>(text: 'One'),
          TgBottomSheetItem<void>(text: 'Two'),
        ],
      );
      _navigator(tester).push(route);
      await tester.pumpAndSettle();

      const double panelHeight = 112.0;
      const double restTop = 600.0 - panelHeight;

      _navigator(tester).pop();
      await tester.pump();

      // t = 90/180 on the way down. Java runs EASE_OUT on forward dismiss
      // time (BottomSheet.java:1870-1871); the route's flipped reverseCurve
      // reproduces it, so offset = easeOut(0.5) of the panel height.
      await tester.pump(const Duration(milliseconds: 90));
      final double expectedMid =
          restTop + TgCurves.easeOut.transform(0.5) * panelHeight;
      expect(tester.getTopLeft(_panel).dy, moreOrLessEquals(expectedMid));

      await tester.pump(const Duration(milliseconds: 90));
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
    });

    testWidgets('barrier tap dismisses and resolves null '
        '(canDismissWithTouchOutside, BottomSheet.java:198)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      final Future<String?> result = showTgBottomSheet<String>(
        _navigator(tester).context,
        items: const <TgBottomSheetItem<String>>[
          TgBottomSheetItem<String>(text: 'One', value: 'one'),
        ],
      );
      await tester.pumpAndSettle();
      expect(_panel, findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
      expect(await result, isNull);
    });

    testWidgets('modal barrier carries the 0.2 black dim',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgBottomSheetRoute<void>(title: 'T'));
      await tester.pumpAndSettle();
      final AnimatedModalBarrier barrier =
          tester.widget<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier));
      expect(barrier.color.value, kSheetBarrierColor);
    });
  });

  group('geometry', () {
    testWidgets('title row is 48dp; normal title 16dp dialogTextGray2 at 16dp',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgBottomSheetRoute<void>(
        title: 'Sheet title',
        items: const <TgBottomSheetItem<void>>[
          TgBottomSheetItem<void>(text: 'One'),
        ],
      ));
      await tester.pumpAndSettle();

      // Panel: 8 + 48 (title) + 48 (cell) + 8 = 112.
      expect(tester.getSize(_panel), const Size(800, 112));
      final double panelTop = tester.getTopLeft(_panel).dy;

      // Title text: horizontal padding 16 (BottomSheet.java:1399), centered
      // in the 48dp row under the 8dp container top padding, shifted by the
      // (0, 8) vertical padding pair.
      final Rect title = tester.getRect(find.text('Sheet title'));
      expect(title.left, 16.0);
      final double rowTop = panelTop + 8.0;
      // Centered inside the padded box: top 0, bottom 8.
      expect(title.center.dy, moreOrLessEquals(rowTop + (48.0 - 8.0) / 2.0));

      final Text titleText = tester.widget<Text>(find.text('Sheet title'));
      expect(titleText.style!.fontSize, kSheetTitleTextSize);
      expect(titleText.style!.color,
          _dayTheme.color(TelegramColorKey.dialogTextGray2));
      expect(titleText.style!.fontFamily, isNot('RobotoMedium'));

      // First cell directly below the title row (topOffset += 48,
      // BottomSheet.java:1413, 1440-1441).
      expect(tester.getTopLeft(find.byType(TgBottomSheetCell)).dy,
          moreOrLessEquals(rowTop + 48.0));
    });

    testWidgets('big title: 20dp RobotoMedium dialogTextBlack at 21dp',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester)
          .push(TgBottomSheetRoute<void>(title: 'Big', bigTitle: true));
      await tester.pumpAndSettle();

      final Rect title = tester.getRect(find.text('Big'));
      expect(title.left, 21.0); // BottomSheet.java:1395
      final Text titleText = tester.widget<Text>(find.text('Big'));
      expect(titleText.style!.fontSize, kSheetBigTitleTextSize);
      expect(titleText.style!.fontFamily, 'packages/telegram_ui/RobotoMedium');
      expect(titleText.style!.fontWeight, FontWeight.w500);
      expect(titleText.style!.color,
          _dayTheme.color(TelegramColorKey.dialogTextBlack));
    });

    testWidgets('item cells: 48dp tall, 56x48 icon frame, 72/16dp text insets',
        (WidgetTester tester) async {
      const Key iconKey = ValueKey<String>('icon');
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgBottomSheetRoute<String>(
        items: const <TgBottomSheetItem<String>>[
          TgBottomSheetItem<String>(
            text: 'With icon',
            icon: SizedBox(key: iconKey, width: 24, height: 24),
            value: 'a',
          ),
          TgBottomSheetItem<String>(text: 'No icon', value: 'b'),
        ],
      ));
      await tester.pumpAndSettle();

      final Finder cells = find.byType(TgBottomSheetCell);
      expect(cells, findsNWidgets(2));
      expect(tester.getSize(cells.first), const Size(800, 48));
      expect(tester.getSize(cells.last), const Size(800, 48));
      // Stacked at 48dp steps (BottomSheet.java:1440-1441).
      expect(
        tester.getTopLeft(cells.last).dy - tester.getTopLeft(cells.first).dy,
        48.0,
      );

      // Icon centered in the 56x48 start-aligned frame
      // (BottomSheet.java:1042-1044).
      final double cellTop = tester.getTopLeft(cells.first).dy;
      expect(tester.getCenter(find.byKey(iconKey)),
          Offset(56.0 / 2.0, cellTop + 24.0));

      // Text: 72dp with icon (BottomSheet.java:1117), 16dp without
      // (BottomSheet.java:1123).
      expect(tester.getRect(find.text('With icon')).left, 72.0);
      expect(tester.getRect(find.text('No icon')).left, 16.0);

      // 16dp dialogTextBlack (BottomSheet.java:1056-1058).
      final Text cellText = tester.widget<Text>(find.text('With icon'));
      expect(cellText.style!.fontSize, kSheetCellTextSize);
      expect(cellText.style!.color,
          _dayTheme.color(TelegramColorKey.dialogTextBlack));

      // Icon frame tint dialogIcon via IconTheme (BottomSheet.java:1043).
      final IconThemeData iconTheme = IconTheme.of(
        tester.element(find.byKey(iconKey)),
      );
      expect(iconTheme.color, _dayTheme.color(TelegramColorKey.dialogIcon));
    });

    testWidgets('bottom view padding is added inside the panel',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_app(padding: const EdgeInsets.only(bottom: 34)));
      _navigator(tester).push(TgBottomSheetRoute<void>(
        items: const <TgBottomSheetItem<void>>[
          TgBottomSheetItem<void>(text: 'One'),
        ],
      ));
      await tester.pumpAndSettle();
      // 8 + 48 + 8 + 34 (BottomSheet.java:1357 + nav-bar inset).
      expect(tester.getSize(_panel).height, 98.0);
      expect(tester.getBottomLeft(_panel).dy, 600.0);
    });

    testWidgets('applyTopPadding/applyBottomPadding drop the 8dp pads',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgBottomSheetRoute<void>(
        applyTopPadding: false,
        applyBottomPadding: false,
        items: const <TgBottomSheetItem<void>>[
          TgBottomSheetItem<void>(text: 'One'),
        ],
      ));
      await tester.pumpAndSettle();
      expect(tester.getSize(_panel).height, 48.0);
    });
  });

  group('results', () {
    testWidgets('tapping an item pops with its value',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      final Future<String?> result = showTgBottomSheet<String>(
        _navigator(tester).context,
        items: const <TgBottomSheetItem<String>>[
          TgBottomSheetItem<String>(text: 'One', value: 'one'),
          TgBottomSheetItem<String>(text: 'Two', value: 'two'),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
      expect(await result, 'two');
    });
  });

  group('surfaces', () {
    testWidgets('solid panel fills with dialogBackground '
        '(BottomSheet.java:1194-1195)', (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgBottomSheetRoute<void>(title: 'T'));
      await tester.pumpAndSettle();

      final ColoredBox fill = tester.widget<ColoredBox>(find.descendant(
        of: _panel,
        matching: find.byType(ColoredBox),
      ));
      expect(fill.color, _dayTheme.color(TelegramColorKey.dialogBackground));
      expect(
        find.descendant(of: _panel, matching: find.byType(FrostedPanel)),
        findsNothing,
      );
    });

    testWidgets('useGlass swaps the fill for a FrostedPanel',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester)
          .push(TgBottomSheetRoute<void>(title: 'T', useGlass: true));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: _panel, matching: find.byType(FrostedPanel)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _panel, matching: find.byType(ColoredBox)),
        findsNothing,
      );
    });

    testWidgets('resources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color background = Color(0xFF123456);
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgBottomSheetRoute<void>(
        title: 'T',
        resources: ResourcesOverride(
          parent: TelegramTheme.resources(_navigator(tester).context),
          overrides: const <int, Color>{
            TelegramColorKey.dialogBackground: background,
          },
        ),
      ));
      await tester.pumpAndSettle();

      final ColoredBox fill = tester.widget<ColoredBox>(find.descendant(
        of: _panel,
        matching: find.byType(ColoredBox),
      ));
      expect(fill.color, background);
    });
  });
}
