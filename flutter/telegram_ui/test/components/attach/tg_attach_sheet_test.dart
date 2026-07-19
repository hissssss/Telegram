// Tests for lib/src/components/attach/tg_attach_sheet.dart (spec:
// flutter/docs/spec_attach_emoji.md Part A), golden-free:
//
//  * constants against the Java values (ChatAttachAlert.java = CAA,
//    GlassTabView.java = GTV, ChatActivityEnterView.java = CAEV, cited per
//    value);
//  * pure math: attach-tab width formula (GTV:485-489) + leftover
//    distribution (GTV:505-513), the open cascade (CAA:5189-5228), the
//    overshoot dim curve (CAA:1344) and the 0.75/350 open spring curve
//    (CAA:5278-5286), send badge sizing (CAEV:15166-15189);
//  * route motion: spring open over 500ms, 250ms EASE_OUT dismiss
//    (BottomSheet.java:2014-2033), barrier dim + tap dismiss;
//  * button row geometry/colors: 70dp wrapper, mainTabs glass r28/pad7
//    (CAA:2725-2735), 11dp content padding, self-measured tab widths, 11dp
//    labels with the glass_tab* color keys, selection pill;
//  * page switching: outgoing/incoming overlap, onPageChanged, header title;
//  * send button: 110x50 container, 52x38 pill at inset (7,6), punch-out
//    badge count, show/hide animation.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/attach/tg_attach_sheet.dart';
import 'package:telegram_ui/src/components/sheet/tg_bottom_sheet.dart';
import 'package:telegram_ui/src/components/tabs/counter_badge.dart';
import 'package:telegram_ui/src/components/tabs/glass_tab.dart';
import 'package:telegram_ui/src/components/tabs/tab_icon.dart';
import 'package:telegram_ui/src/foundation/tg_curves.dart';
import 'package:telegram_ui/src/glass/glass_panel.dart';
import 'package:telegram_ui/src/glass/presets.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

const Size _screen = Size(800, 600);

/// Hosts [child] bottom-aligned under theme + media query (loose
/// constraints, like a sheet docked over content).
Widget _host(Widget child, {double? width}) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: _screen),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: width == null ? child : SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

/// A bare app with a navigator for route tests.
Widget _app() {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: _screen),
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

Finder get _panel => find.byKey(TgAttachSheetRoute.panelKey);

List<AttachSheetPage> _pages({int badgeOnSecond = 0}) => <AttachSheetPage>[
      AttachSheetPage(
        id: 'gallery',
        tabLabel: 'Gallery',
        title: 'Gallery header',
        icon: const TabIcon.static(child: SizedBox(width: 24, height: 24)),
        bodyBuilder: (BuildContext context) => const ColoredBox(
          key: ValueKey<String>('body-gallery'),
          color: Color(0xFFEEEEEE),
        ),
      ),
      AttachSheetPage(
        id: 'file',
        tabLabel: 'File',
        title: 'Files header',
        badgeCount: badgeOnSecond,
        bodyBuilder: (BuildContext context) => const ColoredBox(
          key: ValueKey<String>('body-file'),
          color: Color(0xFFDDDDDD),
        ),
      ),
      AttachSheetPage(
        id: 'poll',
        tabLabel: 'Poll',
        title: 'Poll header',
        bodyBuilder: (BuildContext context) => const ColoredBox(
          key: ValueKey<String>('body-poll'),
          color: Color(0xFFCCCCCC),
        ),
      ),
    ];

void main() {
  group('constants', () {
    test('sheet chrome and row mirror the Java values', () {
      expect(kAttachGrabberWidth, 36.0); // CAA:1893-1913
      expect(kAttachGrabberHeight, 4.0);
      expect(kAttachGrabberRadius, 2.0);
      expect(kAttachGrabberTop, 20.0);
      expect(kAttachButtonRowHeight, 70.0); // CAA:2735
      expect(kAttachButtonRowGlassRadius, 28.0); // CAA:2725-2728
      expect(kAttachButtonRowGlassPadding, 7.0); // CAA:2725-2728
      expect(kAttachButtonRowContentPadding, 11.0); // CAA:2729-2731
      expect(kAttachTabHeight, 48.0); // 70 - 2*11
      expect(kAttachTabMaxWidth, 84.0); // GTV:485-489
      expect(kAttachTabTextPaddingMax, 16.0);
      expect(kAttachTabTextPaddingMin, 8.0);
      expect(kAttachTabLabelSize, 11.0); // GTV:445-446
      // 320ms decelerate (GTV:67), shared with GlassTab.
      expect(kAttachTabSelectionDuration, const Duration(milliseconds: 320));
      expect(kAttachTabSelectionDuration, GlassTab.selectionDuration);
    });

    test('action bar mirrors the Java values', () {
      expect(kAttachActionBarPillRadius, 23.0); // ActionBar.java:213-252
      expect(kAttachActionBarGlassPadding, 6.0);
      expect(kAttachActionBarVisibilityDuration,
          const Duration(milliseconds: 380)); // CAA:5695-5736
      expect(kAttachHeaderTitleSize, 16.0); // CAA:2477-2481
      expect(kAttachHeaderInsetStart, 23.0); // CAA:2534
      expect(kAttachHeaderInsetEnd, 21.0); // CAA:2534
    });

    test('motion constants mirror the Java values', () {
      // Open spring damping 0.75 / stiffness 350 (CAA:5278-5286).
      expect(kAttachSheetOpenSpring.stiffness, 350.0);
      expect(kAttachSheetOpenSpring.mass, 1.0);
      expect(
        kAttachSheetOpenSpring.damping,
        moreOrLessEquals(2 * 0.75 * math.sqrt(350.0)),
      );
      expect(kAttachSheetOpenDuration, const Duration(milliseconds: 500));
      // Dim 400ms delay 20 Overshoot(0.7) (CAA:5292-5298, 1344).
      expect(kAttachSheetDimDuration, const Duration(milliseconds: 400));
      expect(kAttachSheetDimDelay, const Duration(milliseconds: 20));
      expect(kAttachSheetDimCurve,
          const Interval(0.04, 0.84, curve: TgOvershootCurve(0.7)));
      // Close 250ms EASE_OUT (BottomSheet.java:2014-2033).
      expect(kAttachSheetDismissDuration, const Duration(milliseconds: 250));
      expect(kAttachSheetDismissCurve, TgCurves.easeOut);
      // Cascade (CAA:5189-5228, 5257-5262).
      expect(kAttachCascadeMasterDuration, const Duration(milliseconds: 400));
      expect(kAttachCascadeDelay, const Duration(milliseconds: 20));
      expect(kAttachCascadeStaggerMs, 32.0);
      expect(kAttachCascadeGrowMs, 200.0);
      expect(kAttachCascadePeakScale, 1.1);
      expect(kAttachCascadeSettleMs, 100.0);
      expect(kAttachCascadeAlphaCurve, const Cubic(0.42, 0.0, 0.58, 1.0));
      // Layout switch (CAA:4605-4641).
      expect(kAttachLayoutSwitchOutDuration,
          const Duration(milliseconds: 180));
      expect(kAttachLayoutSwitchOffset, 78.0);
      expect(kAttachLayoutSwitchInSpring.stiffness, 500.0);
    });

    test('send button constants mirror the Java values', () {
      expect(kAttachSendContainerSize, const Size(110, 50)); // CAA:3503-3527
      expect(kAttachSendPillSize, const Size(52, 38)); // CAA:3556-3560
      expect(kAttachSendPillPaddingH, 7.0); // CAA:3556-3560
      expect(kAttachSendPillPaddingV, 6.0);
      expect(kAttachSendBadgeMinSize, 18.0); // CAEV:15166-15189
      expect(kAttachSendBadgeTextPadding, 9.0);
      expect(kAttachSendBadgeRingGap, 2.0);
      expect(kAttachSendBadgeOffsetFromPillRight, 50.0);
      expect(kAttachSendVisibilityDuration,
          const Duration(milliseconds: 180)); // CAA:4999
      expect(kAttachSendHiddenScale, 0.2); // CAA:3503-3527
    });
  });

  group('tab width math (GTV:485-489, 505-513)', () {
    test('natural width: min(84, text + 2 * lerp(16, 8, (text-40)/16))', () {
      expect(attachTabNaturalWidth(0), 32.0); // padding 16
      expect(attachTabNaturalWidth(40), 72.0); // padding 16
      expect(attachTabNaturalWidth(48), 72.0); // padding 12
      expect(attachTabNaturalWidth(56), 72.0); // padding 8
      expect(attachTabNaturalWidth(60), 76.0); // padding clamped at 8
      expect(attachTabNaturalWidth(68), 84.0); // capped
      expect(attachTabNaturalWidth(200), 84.0); // capped
    });

    test('leftover is distributed equally; overflow keeps natural widths',
        () {
      // Two zero-width labels: naturals [32, 32].
      expect(attachTabRowWidths(<double>[0, 0], 100), <double>[50, 50]);
      // Overflow: 64 > 60 -> unchanged (the row scrolls).
      expect(attachTabRowWidths(<double>[0, 0], 60), <double>[32, 32]);
      expect(attachTabRowWidths(<double>[], 100), isEmpty);
    });

    test('label measurement returns a positive width', () {
      expect(measureAttachTabLabelWidth('Gallery'), greaterThan(0));
    });
  });

  group('open cascade (CAA:5189-5228)', () {
    test('tab 3 starts at master 0; grow/settle phases', () {
      expect(attachCascadeScale(0, 3), 0.0);
      expect(attachCascadeScale(100, 3),
          moreOrLessEquals(1.1 * TgCurves.easeOut.transform(0.5)));
      expect(attachCascadeScale(200, 3), moreOrLessEquals(1.1));
      expect(
        attachCascadeScale(250, 3),
        moreOrLessEquals(1.1 + (1.0 - 1.1) * TgCurves.easeIn.transform(0.5)),
      );
      expect(attachCascadeScale(300, 3), 1.0);
      expect(attachCascadeScale(400, 3), 1.0);
    });

    test('tab 0 starts at 32 * 3 = 96ms', () {
      expect(attachCascadeScale(96, 0), 0.0);
      expect(attachCascadeScale(196, 0),
          moreOrLessEquals(1.1 * TgCurves.easeOut.transform(0.5)));
      expect(attachCascadeScale(296, 0), moreOrLessEquals(1.1));
      expect(attachCascadeScale(396, 0), 1.0);
    });

    test('tabs past index 3 have negative starts (further along at 0)', () {
      expect(attachCascadeScale(0, 4), greaterThan(0.0));
    });

    test('alpha ramps with EASE_BOTH over the grow phase', () {
      expect(attachCascadeAlpha(0, 3), 0.0);
      expect(attachCascadeAlpha(100, 3),
          moreOrLessEquals(kAttachCascadeAlphaCurve.transform(0.5)));
      expect(attachCascadeAlpha(200, 3), 1.0);
      expect(attachCascadeAlpha(400, 0), 1.0);
    });
  });

  group('curves', () {
    test('TgOvershootCurve matches OvershootInterpolator(0.7)', () {
      const TgOvershootCurve curve = TgOvershootCurve(0.7);
      expect(curve.transform(0.0), 0.0);
      expect(curve.transform(1.0), 1.0);
      // f(0.5) = 0.25 * (1.7 * -0.5 + 0.7) + 1 = 0.9625.
      expect(curve.transform(0.5), moreOrLessEquals(0.9625));
    });

    test('open spring curve: endpoints exact, slight overshoot mid-flight',
        () {
      const AttachSheetOpenSpringCurve curve = AttachSheetOpenSpringCurve();
      expect(curve.transform(0.0), 0.0);
      expect(curve.transform(1.0), 1.0);
      final double mid = curve.transform(0.3);
      expect(mid, greaterThan(0.5));
      // Underdamped 0.75 overshoots but stays under ~5%.
      double peak = 0.0;
      for (double t = 0.05; t < 1.0; t += 0.05) {
        peak = peak > curve.transform(t) ? peak : curve.transform(t);
      }
      expect(peak, greaterThan(1.0));
      expect(peak, lessThan(1.05));
    });
  });

  group('route motion', () {
    testWidgets('opens on the 0.75/350 spring over 500ms',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      final TgAttachSheetRoute<void> route =
          TgAttachSheetRoute<void>(pages: _pages(), height: 300);
      expect(route.transitionDuration, kAttachSheetOpenDuration);
      expect(route.reverseTransitionDuration, kAttachSheetDismissDuration);
      expect(route.barrierColor, kSheetBarrierColor); // BottomSheet.java:219
      expect(route.barrierDismissible, isTrue);

      _navigator(tester).push(route);
      await tester.pump(); // t = 0.

      const double restTop = 600.0 - 300.0;
      expect(tester.getTopLeft(_panel).dy, moreOrLessEquals(600.0));

      // t = 250/500: spring position at 0.25s.
      await tester.pump(const Duration(milliseconds: 250));
      const AttachSheetOpenSpringCurve curve = AttachSheetOpenSpringCurve();
      final double expectedMid = restTop + (1 - curve.transform(0.5)) * 300.0;
      expect(tester.getTopLeft(_panel).dy, moreOrLessEquals(expectedMid));

      // t = 500: settled (Curve.transform pins t=1 to exactly 1).
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.getTopLeft(_panel).dy, moreOrLessEquals(restTop));
      expect(tester.getSize(_panel), const Size(800, 300));
    });

    testWidgets('dismisses down over 250ms EASE_OUT '
        '(BottomSheet.java:2014-2033)', (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester)
          .push(TgAttachSheetRoute<void>(pages: _pages(), height: 300));
      await tester.pumpAndSettle();

      const double restTop = 600.0 - 300.0;
      _navigator(tester).pop();
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 125));
      final double expectedMid =
          restTop + TgCurves.easeOut.transform(0.5) * 300.0;
      expect(tester.getTopLeft(_panel).dy, moreOrLessEquals(expectedMid));

      await tester.pump(const Duration(milliseconds: 125));
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
    });

    testWidgets('barrier dims to 0.2 black and tap-outside dismisses',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      final Future<String?> result = showTgAttachSheet<String>(
        _navigator(tester).context,
        pages: _pages(),
        height: 300,
      );
      await tester.pumpAndSettle();
      final AnimatedModalBarrier barrier = tester
          .widget<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier));
      expect(barrier.color.value, kSheetBarrierColor);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
      expect(await result, isNull);
    });
  });

  group('button row geometry/colors', () {
    testWidgets('70dp wrapper with the mainTabs glass pill r28/pad7 '
        '(CAA:2725-2735)', (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(TgAttachSheet(pages: _pages(), height: 500)));
      await tester.pumpAndSettle();

      final Finder rowFinder = find.byKey(TgAttachSheet.buttonRowKey);
      expect(tester.getSize(rowFinder), const Size(800, 70));
      // Docked at the sheet bottom (gravity bottom, CAA:2735).
      expect(tester.getBottomLeft(rowFinder).dy, 600.0);

      final GlassPanel panel = tester.widget<GlassPanel>(
        find.descendant(of: rowFinder, matching: find.byType(GlassPanel)),
      );
      expect(panel.preset, GlassPresets.mainTabs);
      expect(panel.borderRadius.topLeft, kAttachButtonRowGlassRadius);
      expect(panel.borderRadius.bottomRight, kAttachButtonRowGlassRadius);
      expect(panel.padding, kAttachButtonRowGlassPadding);
    });

    testWidgets('tabs self-measure and split the leftover equally '
        '(GTV:485-489, 505-513)', (WidgetTester tester) async {
      final List<AttachSheetPage> pages = _pages();
      await tester
          .pumpWidget(_host(TgAttachSheet(pages: pages, height: 500)));
      await tester.pumpAndSettle();

      // Row content width: 800 - 2*11 (CAA:2729-2731).
      final List<double> expected = attachTabRowWidths(
        <double>[
          for (final AttachSheetPage page in pages)
            measureAttachTabLabelWidth(page.tabLabel),
        ],
        800.0 - 2 * kAttachButtonRowContentPadding,
      );
      final Finder tabs = find.byType(TgAttachTab);
      expect(tabs, findsNWidgets(3));
      double total = 0.0;
      for (int i = 0; i < 3; i++) {
        final Size size = tester.getSize(tabs.at(i));
        expect(size.width, moreOrLessEquals(expected[i]));
        expect(size.height, kAttachTabHeight);
        total += size.width;
      }
      // Underfilled row: leftover fully distributed.
      expect(total, moreOrLessEquals(800.0 - 2 * kAttachButtonRowContentPadding));
    });

    testWidgets('labels: 11dp, extra-bold + glass_tabSelectedText selected, '
        'medium + glass_tabUnselected otherwise (GTV:445-446, 237, 254-265)',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(TgAttachSheet(pages: _pages(), height: 500)));
      await tester.pumpAndSettle();

      final Text selected = tester.widget<Text>(find.text('Gallery'));
      expect(selected.style!.fontSize, kAttachTabLabelSize);
      expect(selected.style!.fontFamily, 'packages/telegram_ui/RobotoExtraBold');
      expect(selected.style!.fontWeight, FontWeight.w800);
      expect(selected.style!.color,
          _dayTheme.color(TelegramColorKey.glass_tabSelectedText));

      final Text unselected = tester.widget<Text>(find.text('File'));
      expect(unselected.style!.fontSize, kAttachTabLabelSize);
      expect(unselected.style!.fontFamily, 'packages/telegram_ui/RobotoMedium');
      expect(unselected.style!.fontWeight, FontWeight.w500);
      expect(unselected.style!.color,
          _dayTheme.color(TelegramColorKey.glass_tabUnselected));
    });

    testWidgets('selection pill: factor 1 on the selected tab, '
        'glass_tabSelected fill (GTV:152-165)', (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(TgAttachSheet(pages: _pages(), height: 500)));
      await tester.pumpAndSettle();

      final CustomPaint paint = tester.widget<CustomPaint>(find.descendant(
        of: find.byType(TgAttachTab).first,
        matching: find.byWidgetPredicate(
          (Widget w) => w is CustomPaint && w.painter is GlassTabPillPainter,
        ),
      ));
      final GlassTabPillPainter pill = paint.painter! as GlassTabPillPainter;
      expect(pill.factor, 1.0);
      expect(pill.color, _dayTheme.color(TelegramColorKey.glass_tabSelected));
    });

    testWidgets('per-tab counter badge wires badgeCount (GTV:167-227)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _host(TgAttachSheet(pages: _pages(badgeOnSecond: 5), height: 500)));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is CounterBadgeDecoration && w.count == '5',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an overflowing row scrolls horizontally (CAA:2592-2658)',
        (WidgetTester tester) async {
      final List<AttachSheetPage> pages = <AttachSheetPage>[
        for (int i = 0; i < 6; i++)
          AttachSheetPage(
            id: i,
            tabLabel: 'WWWWWWWWWW $i',
            bodyBuilder: (BuildContext context) => const SizedBox(),
          ),
      ];
      await tester.pumpWidget(
          _host(TgAttachSheet(pages: pages, height: 500), width: 300));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(TgAttachSheet.buttonRowKey),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
    });

    testWidgets('grabber: 36x4 at top + 20 (CAA:1893-1913); action bar uses '
        'attachMenuActionBar pills r23/pad6 (CAA:4075)',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(TgAttachSheet(pages: _pages(), height: 500)));
      await tester.pumpAndSettle();

      final Finder grabber = find.byKey(TgAttachSheet.grabberKey);
      expect(tester.getSize(grabber), const Size(36, 4));
      final double sheetTop = 600.0 - 500.0;
      expect(tester.getTopLeft(grabber).dy, sheetTop + kAttachGrabberTop);
      expect(tester.getCenter(grabber).dx, 400.0);

      final GlassPanel pill = tester.widget<GlassPanel>(
        find
            .descendant(
              of: find.byKey(TgAttachSheet.actionBarKey),
              matching: find.byType(GlassPanel),
            )
            .first,
      );
      expect(pill.preset, GlassPresets.attachMenuActionBar);
      expect(pill.borderRadius.topLeft, kAttachActionBarPillRadius);
      expect(pill.padding, kAttachActionBarGlassPadding);

      // Header title: 16dp bold dialogTextBlack (CAA:2477-2481).
      final Text title = tester.widget<Text>(find.text('Gallery header'));
      expect(title.style!.fontSize, kAttachHeaderTitleSize);
      expect(title.style!.fontWeight, FontWeight.w500);
      expect(title.style!.color,
          _dayTheme.color(TelegramColorKey.dialogTextBlack));
    });
  });

  group('page switching (CAA:4587-4652)', () {
    testWidgets('tapping a tab cross-animates bodies and fires onPageChanged',
        (WidgetTester tester) async {
      final List<int> changes = <int>[];
      await tester.pumpWidget(_host(TgAttachSheet(
        pages: _pages(),
        height: 500,
        onPageChanged: changes.add,
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('body-gallery')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('body-file')), findsNothing);

      await tester.tap(find.text('File'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      // Mid-switch: outgoing (180ms DEFAULT) and incoming (0.75/500 spring)
      // overlap (CAA:4605-4641).
      expect(changes, <int>[1]);
      expect(find.byKey(const ValueKey<String>('body-gallery')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('body-file')), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('body-gallery')), findsNothing);
      expect(find.byKey(const ValueKey<String>('body-file')), findsOneWidget);
      // Header title follows the page.
      expect(find.text('Files header'), findsOneWidget);
      expect(find.text('Gallery header'), findsNothing);
    });

    testWidgets('outgoing page unmounts after the 180ms out animation',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(TgAttachSheet(pages: _pages(), height: 500)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Poll'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 179));
      expect(find.byKey(const ValueKey<String>('body-gallery')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('body-gallery')), findsNothing);
    });

    testWidgets('re-tapping the selected tab is a no-op',
        (WidgetTester tester) async {
      final List<int> changes = <int>[];
      await tester.pumpWidget(_host(TgAttachSheet(
        pages: _pages(),
        height: 500,
        onPageChanged: changes.add,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
    });

    testWidgets('mediaGrid page renders the thumbnails provider slot',
        (WidgetTester tester) async {
      final List<AttachSheetPage> pages = <AttachSheetPage>[
        AttachSheetPage.mediaGrid(
          thumbnailsBuilder: (BuildContext context) => <Widget>[
            for (int i = 0; i < 4; i++)
              SizedBox(key: ValueKey<String>('thumb-$i')),
          ],
        ),
      ];
      await tester.pumpWidget(_host(TgAttachSheet(pages: pages, height: 500)));
      await tester.pumpAndSettle();
      for (int i = 0; i < 4; i++) {
        expect(find.byKey(ValueKey<String>('thumb-$i')), findsOneWidget);
      }
    });
  });

  group('send button (CAA:3503-3560, CAEV:15166-15189)', () {
    test('badge size: max(18, 9 + textWidth)', () {
      expect(attachSendBadgeSize(0), 18.0);
      expect(attachSendBadgeSize(9), 18.0);
      expect(attachSendBadgeSize(10), 19.0);
      expect(attachSendBadgeSize(20), 29.0);
    });

    test('badge painter geometry: circle at (pillRight - 50, pillTop), '
        'ring +2', () {
      final TextPainter counter = CounterBadgePainter.buildCounterPainter('3');
      final AttachSendBadgePainter painter = AttachSendBadgePainter(
        text: '3',
        fill: const Color(0xFF54A1DB),
        counterPainter: counter,
      );
      final double sz = attachSendBadgeSize(counter.width);
      expect(painter.badgeSize, sz);
      const Size box = Size(110, 50);
      // cx = (110 - 7) - 50 = 53; cy = pillTop(6) + sz/2.
      expect(painter.centerFor(box), Offset(53.0, 6.0 + sz / 2.0));
      final Rect punch = painter.punchRect(box);
      expect(punch.width, moreOrLessEquals(sz + 2 * kAttachSendBadgeRingGap));
      expect(punch.height, punch.width); // circle
      expect(painter.fillColor, const Color(0xFF54A1DB));
      counter.dispose();
    });

    testWidgets('pill: 52x38 at inset (7,6), chat_messagePanelSend fill',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgAttachSendButton(count: 3)));
      await tester.pumpAndSettle();

      final Rect container =
          tester.getRect(find.byType(TgAttachSendButton));
      expect(container.size, kAttachSendContainerSize);
      final Rect pill = tester.getRect(find.byKey(TgAttachSendButton.pillKey));
      expect(pill.size, kAttachSendPillSize);
      expect(pill.right, container.right - kAttachSendPillPaddingH);
      expect(pill.bottom, container.bottom - kAttachSendPillPaddingV);

      final DecoratedBox box = tester.widget<DecoratedBox>(find.descendant(
        of: find.byKey(TgAttachSendButton.pillKey),
        matching: find.byType(DecoratedBox),
      ));
      expect((box.decoration as BoxDecoration).color,
          _dayTheme.color(TelegramColorKey.chat_messagePanelSend));
    });

    testWidgets('badge shows the count through the punch-out layer',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgAttachSendButton(count: 3)));
      await tester.pumpAndSettle();

      final CounterBadgeLayer layer =
          tester.widget<CounterBadgeLayer>(find.byType(CounterBadgeLayer));
      expect(layer.painter, isA<AttachSendBadgePainter>());
      expect(layer.painter!.text, '3');
      expect(layer.painter!.visibility, 1.0);
    });

    testWidgets('hidden at count 0 (alpha 0, scale 0.2), shows over 180ms',
        (WidgetTester tester) async {
      Widget build(int count) => _host(TgAttachSendButton(count: count));
      await tester.pumpWidget(build(0));
      Opacity opacity = tester
          .widget<Opacity>(find.byKey(TgAttachSendButton.visibilityKey));
      expect(opacity.opacity, 0.0);

      await tester.pumpWidget(build(2));
      await tester.pump(const Duration(milliseconds: 90));
      opacity = tester
          .widget<Opacity>(find.byKey(TgAttachSendButton.visibilityKey));
      expect(opacity.opacity,
          moreOrLessEquals(TgCurves.defaultCubic.transform(0.5)));

      await tester.pump(const Duration(milliseconds: 90));
      await tester.pumpAndSettle();
      opacity = tester
          .widget<Opacity>(find.byKey(TgAttachSendButton.visibilityKey));
      expect(opacity.opacity, 1.0);
    });

    testWidgets('sheet wires selectedCount + onSend; button floats above the '
        'row', (WidgetTester tester) async {
      int sends = 0;
      await tester.pumpWidget(_host(TgAttachSheet(
        pages: _pages(),
        height: 500,
        selectedCount: 2,
        onSend: () => sends++,
      )));
      await tester.pumpAndSettle();

      // Every tab hosts a CounterBadgeLayer too — scope to the send button.
      final CounterBadgeLayer layer = tester.widget<CounterBadgeLayer>(
        find.descendant(
          of: find.byType(TgAttachSendButton),
          matching: find.byType(CounterBadgeLayer),
        ),
      );
      expect(layer.painter!.text, '2');

      final Rect button = tester.getRect(find.byType(TgAttachSendButton));
      expect(button.right, 800.0);
      expect(button.bottom, 600.0 - kAttachButtonRowHeight);

      await tester.tap(find.byKey(TgAttachSendButton.pillKey));
      expect(sends, 1);
    });
  });
}
