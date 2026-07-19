// Ring-1/Ring-2 tests for lib/src/components/app_bar/glass_app_bar.dart
// (ARCHITECTURE.md section 6, row "GlassAppBar"), golden-free:
//
//  * constants against the Java values (ActionBar.java, cited per constant);
//  * preferred-size math: 56dp portrait / 48dp landscape
//    (getCurrentActionBarHeight, ActionBar.java:1855-1861) plus the
//    MediaQuery top padding when occupyStatusBar (ActionBar.java:111, 1389);
//  * pill geometry (dispatchDraw, ActionBar.java:2152-2197) as a pure
//    function and through the widget;
//  * title position: textLeft 76dp with leading / 24dp without
//    (ActionBar.java:1511-1513) and the vertical formulas
//    (ActionBar.java:1528-1543);
//  * subtitle color key `actionBarDefaultSubtitle` (ActionBar.java:465);
//  * the title swap (setTitleAnimated, ActionBar.java:1863-1927): +-20dp
//    translate + alpha crossfade over 220ms;
//  * the 150ms search-expand fade hook (ActionBar.java:1196-1264) incl. the
//    menu shift (ActionBar.java:242, 1207-1209) and forum corner animation
//    (ActionBar.java:1200-1205);
//  * menu width tracking, 320ms EASE_OUT_QUINT (ActionBar.java:2115-2116,
//    2136-2150).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/app_bar/glass_app_bar.dart';
import 'package:telegram_ui/src/components/app_bar/glass_app_bar_search_field.dart';
import 'package:telegram_ui/src/foundation/tg_curves.dart';
import 'package:telegram_ui/src/glass/backdrop_scope.dart';
import 'package:telegram_ui/src/glass/glass_panel.dart';
import 'package:telegram_ui/src/glass/presets.dart';
import 'package:telegram_ui/src/glass/runtime_probe.dart';
import 'package:telegram_ui/src/glass/strategy.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

/// Settings whose probe never resolves: liquid requests stay conservatively
/// frosted — the deterministic flutter_tester path (no ImageFilter.shader).
GlassSettings _manualSettings() =>
    GlassSettings(probe: () => Completer<GlassCapability>().future);

/// Hosts [child] top-left aligned at [barWidth] logical px wide, under a
/// MediaQuery of [screenSize] (orientation source) and [topPadding]
/// (status-bar inset source).
Widget _host({
  required Widget child,
  Size screenSize = const Size(400, 800),
  double topPadding = 0.0,
  double barWidth = 400.0,
}) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(
          size: screenSize,
          padding: EdgeInsets.only(top: topPadding),
        ),
        child: GlassBackdropScope(
          settings: _manualSettings(),
          probeOnMount: false,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: barWidth, child: child),
          ),
        ),
      ),
    ),
  );
}

double _opacityOf(WidgetTester tester, Finder inner) => tester
    .widget<Opacity>(
      find.ancestor(of: inner, matching: find.byType(Opacity)).first,
    )
    .opacity;

Matrix4 _transformOf(WidgetTester tester, Finder inner) => tester
    .widget<Transform>(
      find.ancestor(of: inner, matching: find.byType(Transform)).first,
    )
    .transform;

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      // getCurrentActionBarHeight (ActionBar.java:1855-1861).
      expect(kGlassAppBarHeightPortrait, 56.0);
      expect(kGlassAppBarHeightLandscape, 48.0);
      // setupGlass pills (ActionBar.java:221-239) + dispatchDraw
      // (ActionBar.java:2154-2163).
      expect(kGlassAppBarPillRadius, 23.0);
      expect(kGlassAppBarForumRadius, 18.33);
      expect(kGlassAppBarPillPadding, 6.0);
      expect(kGlassAppBarPillContentSize, 46.0);
      expect(kGlassAppBarPillHeight, 58.0);
      expect(kGlassAppBarPillHeight,
          kGlassAppBarPillContentSize + 2 * kGlassAppBarPillPadding);
      expect(kGlassAppBarBackPillWidth, 58.0);
      // Back button (ActionBar.java:269, 249-251).
      expect(kGlassAppBarBackButtonSize, 54.0);
      expect(kGlassAppBarBackShiftX, 2.0);
      // Glass text left (ActionBar.java:1511-1513).
      expect(kGlassAppBarTextLeftWithBack, 76.0);
      expect(kGlassAppBarTextLeftNoBack, 24.0);
      // Text sizes (ActionBar.java:1431-1443, 1437) and the title gap
      // (ActionBar.java:1428).
      expect(kGlassAppBarTitleTextSize, 17.0);
      expect(kGlassAppBarSubtitleTextSize, 14.0);
      expect(kGlassAppBarTitleRightGap, 16.0);
      // setTitleAnimated (ActionBar.java:1893, 1904; 1878, 2055-2056).
      expect(kGlassAppBarTitleSwapOffset, 20.0);
      expect(kGlassAppBarTitleSwapDuration, const Duration(milliseconds: 220));
      // Search (ActionBar.java:1264, 1221-1226, 1412/1518).
      expect(kGlassAppBarSearchDuration, const Duration(milliseconds: 150));
      expect(kGlassAppBarSearchHiddenScale, 0.95);
      expect(kGlassAppBarSearchContentLeft, 66.0);
      // Menu (ActionBar.java:2115-2116, 242, 1208).
      expect(kGlassAppBarMenuTrackDuration, const Duration(milliseconds: 320));
      expect(kGlassAppBarMenuShiftDefault, 10.0);
      expect(kGlassAppBarMenuShiftSearch, 5.0);
    });

    test('AccelerateDecelerate curve matches the Android formula', () {
      const Curve curve = kGlassAppBarAnimatorCurve;
      expect(curve.transform(0.0), 0.0);
      expect(curve.transform(1.0), 1.0);
      expect(curve.transform(0.5), closeTo(0.5, 1e-12));
      // cos(1.25*pi)/2 + 0.5.
      expect(curve.transform(0.25),
          closeTo(math.cos(1.25 * math.pi) / 2 + 0.5, 1e-12));
      expect(curve.transform(0.25), closeTo(0.146446609, 1e-9));
      expect(curve.transform(0.75), closeTo(0.853553391, 1e-9));
    });
  });

  group('preferred size', () {
    test('context-free preferredSize is the portrait bar height', () {
      expect(const GlassAppBar().preferredSize,
          const Size.fromHeight(kGlassAppBarHeightPortrait));
    });

    test('barHeightFor follows orientation (ActionBar.java:1855-1861)', () {
      expect(GlassAppBar.barHeightFor(Orientation.portrait), 56.0);
      expect(GlassAppBar.barHeightFor(Orientation.landscape), 48.0);
    });

    testWidgets('preferredHeightFor adds the MediaQuery top padding',
        (WidgetTester tester) async {
      late double portraitHeight;
      late double noStatusHeight;
      await tester.pumpWidget(_host(
        topPadding: 47,
        child: Builder(builder: (BuildContext context) {
          portraitHeight = GlassAppBar.preferredHeightFor(context);
          noStatusHeight =
              GlassAppBar.preferredHeightFor(context, occupyStatusBar: false);
          return const SizedBox();
        }),
      ));
      expect(portraitHeight, 56.0 + 47.0);
      expect(noStatusHeight, 56.0);
    });

    testWidgets('preferredHeightFor uses the landscape bar height',
        (WidgetTester tester) async {
      late double height;
      await tester.pumpWidget(_host(
        screenSize: const Size(800, 400),
        topPadding: 24,
        child: Builder(builder: (BuildContext context) {
          height = GlassAppBar.preferredHeightFor(context);
          return const SizedBox();
        }),
      ));
      expect(height, 48.0 + 24.0);
    });

    testWidgets('rendered height = bar height + status inset (portrait)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        topPadding: 47,
        child: const GlassAppBar(title: 'Chats'),
      ));
      expect(tester.getSize(find.byType(GlassAppBar)), const Size(400, 103));
    });

    testWidgets('rendered height in landscape and without the status bar',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        screenSize: const Size(800, 400),
        topPadding: 47,
        child: const GlassAppBar(title: 'Chats', occupyStatusBar: false),
      ));
      expect(tester.getSize(find.byType(GlassAppBar)), const Size(400, 48));
    });
  });

  group('pill geometry (pure)', () {
    // 400x80 bar: statusTop 24 + barHeight 56.
    // t = 80 - (56+46)/2 - 6 = 23; b = 23 + 58 = 81 (ActionBar.java:2162-2163).
    const Size size = Size(400, 80);

    test('back pill is [0, t, 58, b] (ActionBar.java:2189-2192)', () {
      final GlassAppBarPillGeometry g = GlassAppBarPillGeometry.compute(
        size: size,
        barHeight: 56,
        hasBackButton: true,
      );
      expect(g.backPill, const Rect.fromLTRB(0, 23, 58, 81));
      expect(g.backPill!.height, kGlassAppBarPillHeight);
    });

    test('main pill spans back pill to menu (ActionBar.java:2165-2188)', () {
      final GlassAppBarPillGeometry g = GlassAppBarPillGeometry.compute(
        size: size,
        barHeight: 56,
        hasBackButton: true,
        menuWidth: 46,
        hasMenuFactor: 1.0,
      );
      // left = s + p = 52; right = 400 - (46 + 6) = 348.
      expect(g.mainPill, const Rect.fromLTRB(52, 23, 348, 81));
      // Menu pill: left = 400 - max(46, 46) - 12 = 342 (ActionBar.java:2194).
      expect(g.menuPill, const Rect.fromLTRB(342, 23, 400, 81));
      expect(g.menuPillOpacity, 1.0);
    });

    test('no back button: main pill starts at 0', () {
      final GlassAppBarPillGeometry g = GlassAppBarPillGeometry.compute(
        size: size,
        barHeight: 56,
        hasBackButton: false,
      );
      expect(g.backPill, isNull);
      expect(g.mainPill, const Rect.fromLTRB(0, 23, 400, 81));
      expect(g.menuPill, isNull);
    });

    test('menu narrower than 46dp keeps the 46dp minimum pill width', () {
      final GlassAppBarPillGeometry g = GlassAppBarPillGeometry.compute(
        size: size,
        barHeight: 56,
        hasBackButton: true,
        menuWidth: 30,
        hasMenuFactor: 1.0,
      );
      // left = 400 - max(46, 30) - 12 = 342.
      expect(g.menuPill, const Rect.fromLTRB(342, 23, 400, 81));
      // Main pill right tracks the actual width: 400 - (30 + 6) = 364.
      expect(g.mainPill, const Rect.fromLTRB(52, 23, 364, 81));
    });

    test('has-menu factor scales the main pill padding and the alpha', () {
      final GlassAppBarPillGeometry g = GlassAppBarPillGeometry.compute(
        size: size,
        barHeight: 56,
        hasBackButton: true,
        menuWidth: 46,
        hasMenuFactor: 0.5,
      );
      // right = 400 - (46 + 6*0.5) = 351 (ActionBar.java:2166-2170).
      expect(g.mainPill, const Rect.fromLTRB(52, 23, 351, 81));
      expect(g.menuPillOpacity, 0.5);
    });

    test('glassOnlyBack draws only the back pill (ActionBar.java:201-203)',
        () {
      final GlassAppBarPillGeometry g = GlassAppBarPillGeometry.compute(
        size: size,
        barHeight: 56,
        hasBackButton: true,
        menuWidth: 46,
        hasMenuFactor: 1.0,
        onlyBackPill: true,
      );
      expect(g.backPill, const Rect.fromLTRB(0, 23, 58, 81));
      expect(g.mainPill, isNull);
      expect(g.menuPill, isNull);
    });

    test('56dp bar without a status inset overhangs by 1dp each side', () {
      final GlassAppBarPillGeometry g = GlassAppBarPillGeometry.compute(
        size: const Size(400, 56),
        barHeight: 56,
        hasBackButton: true,
      );
      expect(g.backPill, const Rect.fromLTRB(0, -1, 58, 57));
    });
  });

  group('pill widgets', () {
    testWidgets('pills render at the dispatchDraw rects',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        topPadding: 24,
        child: GlassAppBar(
          title: 'Chats',
          leading: const SizedBox(width: 24, height: 24),
          actions: const <Widget>[SizedBox(width: 46, height: 46)],
        ),
      ));
      // The menu width lands via a post-frame callback -> one extra pump.
      await tester.pump();

      expect(tester.getRect(find.byKey(GlassAppBar.backPillKey)),
          const Rect.fromLTRB(0, 23, 58, 81));
      expect(tester.getRect(find.byKey(GlassAppBar.mainPillKey)),
          const Rect.fromLTRB(52, 23, 348, 81));
      expect(tester.getRect(find.byKey(GlassAppBar.menuPillKey)),
          const Rect.fromLTRB(342, 23, 400, 81));
    });

    testWidgets('no actions: no menu pill; no leading: no back pill',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        topPadding: 24,
        child: const GlassAppBar(title: 'Chats'),
      ));
      await tester.pump();

      expect(find.byKey(GlassAppBar.backPillKey), findsNothing);
      expect(find.byKey(GlassAppBar.menuPillKey), findsNothing);
      expect(tester.getRect(find.byKey(GlassAppBar.mainPillKey)),
          const Rect.fromLTRB(0, 23, 400, 81));
    });

    testWidgets('onlyBackPill renders the back pill alone',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        topPadding: 24,
        child: GlassAppBar(
          title: 'Chats',
          onlyBackPill: true,
          leading: const SizedBox(width: 24, height: 24),
          actions: const <Widget>[SizedBox(width: 46, height: 46)],
        ),
      ));
      await tester.pump();

      expect(find.byKey(GlassAppBar.backPillKey), findsOneWidget);
      expect(find.byKey(GlassAppBar.mainPillKey), findsNothing);
      expect(find.byKey(GlassAppBar.menuPillKey), findsNothing);
    });

    testWidgets(
        'pills default to the frosted tier and the topPanelChat preset '
        '(ARCHITECTURE.md section 3.5; ChatActivity.java:4530-4533)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: GlassAppBar(
          title: 'Chats',
          leading: const SizedBox(width: 24, height: 24),
        ),
      ));
      await tester.pump();

      final GlassPanel main =
          tester.widget<GlassPanel>(find.byKey(GlassAppBar.mainPillKey));
      expect(main.tier, GlassTier.frosted);
      expect(main.preset, GlassPresets.topPanelChat);
      expect(main.padding, kGlassAppBarPillPadding);
      final GlassPanel back =
          tester.widget<GlassPanel>(find.byKey(GlassAppBar.backPillKey));
      expect(back.tier, GlassTier.frosted);
      expect(back.preset, GlassPresets.topPanelChat);
      expect(back.borderRadius.topLeft, kGlassAppBarPillRadius);
      expect(back.borderRadius.isUniform, isTrue);
    });

    testWidgets('preset and tier overrides pass through',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const GlassAppBar(
          title: 'Attach',
          preset: GlassPresets.attachMenuActionBar,
          tier: GlassTier.flat,
        ),
      ));
      await tester.pump();
      final GlassPanel main =
          tester.widget<GlassPanel>(find.byKey(GlassAppBar.mainPillKey));
      expect(main.preset, GlassPresets.attachMenuActionBar);
      expect(main.tier, GlassTier.flat);
    });
  });

  group('title and subtitle layout', () {
    testWidgets('textLeft is 76dp with a leading slot (ActionBar.java:1511)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        topPadding: 24,
        child: GlassAppBar(
          title: 'Chats',
          leading: const SizedBox(width: 24, height: 24),
        ),
      ));
      final Offset topLeft = tester.getTopLeft(find.byKey(GlassAppBar.titleKey));
      expect(topLeft.dx, 76.0);
      // Title-only vertical centering (ActionBar.java:1531).
      final double titleHeight = GlassAppBar.measureTextHeight(
          'Chats', GlassAppBar.titleStyleFor(const Color(0xFF000000)));
      expect(topLeft.dy, closeTo(24.0 + (56.0 - titleHeight) / 2.0, 0.001));
    });

    testWidgets('textLeft is 24dp without a leading slot (ActionBar.java:1513)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(child: const GlassAppBar(title: 'Chats')));
      expect(tester.getTopLeft(find.byKey(GlassAppBar.titleKey)).dx, 24.0);
    });

    testWidgets('with a subtitle the two-row formulas apply (portrait)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        topPadding: 24,
        child: const GlassAppBar(title: 'Name', subtitle: 'online'),
      ));
      final double titleHeight = GlassAppBar.measureTextHeight(
          'Name', GlassAppBar.titleStyleFor(const Color(0xFF000000)));
      final double subtitleHeight = GlassAppBar.measureTextHeight(
          'online', GlassAppBar.subtitleStyleFor(const Color(0xFF000000)));
      // (h/2 - textH)/2 + 2 + 3 (ActionBar.java:1529).
      expect(tester.getTopLeft(find.byKey(GlassAppBar.titleKey)).dy,
          closeTo(24.0 + (28.0 - titleHeight) / 2.0 + 5.0, 0.001));
      // h/2 + (h/2 - subH)/2 - 2 (ActionBar.java:1542).
      expect(tester.getTopLeft(find.byKey(GlassAppBar.subtitleKey)).dy,
          closeTo(24.0 + 28.0 + (28.0 - subtitleHeight) / 2.0 - 2.0, 0.001));
      expect(tester.getTopLeft(find.byKey(GlassAppBar.subtitleKey)).dx, 24.0);
    });

    testWidgets('landscape: 48dp bar and the +2dp two-row offset',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        screenSize: const Size(800, 400),
        child: const GlassAppBar(title: 'Name', subtitle: 'online'),
      ));
      final double titleHeight = GlassAppBar.measureTextHeight(
          'Name', GlassAppBar.titleStyleFor(const Color(0xFF000000)));
      // (48/2 - textH)/2 + 2 + 2 (ActionBar.java:1529, landscape arm).
      expect(tester.getTopLeft(find.byKey(GlassAppBar.titleKey)).dy,
          closeTo((24.0 - titleHeight) / 2.0 + 4.0, 0.001));
    });

    testWidgets('title/subtitle color keys (ActionBar.java:520, 465)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const GlassAppBar(title: 'Name', subtitle: 'online'),
      ));
      final Text title = tester.widget<Text>(find.byKey(GlassAppBar.titleKey));
      expect(title.style!.color,
          _dayTheme.color(TelegramColorKey.actionBarDefaultTitle));
      expect(title.style!.fontSize, 17.0);
      expect(title.style!.fontFamily, 'packages/telegram_ui/RobotoMedium');
      expect(title.style!.fontWeight, FontWeight.w500);
      final Text subtitle =
          tester.widget<Text>(find.byKey(GlassAppBar.subtitleKey));
      expect(subtitle.style!.color,
          _dayTheme.color(TelegramColorKey.actionBarDefaultSubtitle));
      expect(subtitle.style!.fontSize, 14.0);
    });
  });

  group('title swap (setTitleAnimated, ActionBar.java:1863-1927)', () {
    Widget swapHost(String title, {bool fromBottom = false}) => _host(
          child: GlassAppBar(
            title: title,
            animateTitleChange: true,
            titleChangeFromBottom: fromBottom,
          ),
        );

    testWidgets('animates +-20dp translate with an alpha crossfade',
        (WidgetTester tester) async {
      await tester.pumpWidget(swapHost('Alpha'));
      final double settledDy =
          tester.getTopLeft(find.byKey(GlassAppBar.titleKey)).dy;

      await tester.pumpWidget(swapHost('Beta'));
      // Swap started: incoming at alpha 0, translated -20dp; outgoing at 1.
      expect(_opacityOf(tester, find.byKey(GlassAppBar.titleKey)), 0.0);
      expect(_opacityOf(tester, find.byKey(GlassAppBar.outgoingTitleKey)), 1.0);
      expect(tester.getTopLeft(find.byKey(GlassAppBar.titleKey)).dy,
          closeTo(settledDy - 20.0, 0.001));
      expect(tester.getTopLeft(find.byKey(GlassAppBar.outgoingTitleKey)).dy,
          closeTo(settledDy, 0.001));

      // Half of the 220ms default: curve(0.5) = 0.5.
      await tester.pump(const Duration(milliseconds: 110));
      expect(_opacityOf(tester, find.byKey(GlassAppBar.titleKey)),
          closeTo(0.5, 1e-9));
      expect(_opacityOf(tester, find.byKey(GlassAppBar.outgoingTitleKey)),
          closeTo(0.5, 1e-9));
      expect(tester.getTopLeft(find.byKey(GlassAppBar.titleKey)).dy,
          closeTo(settledDy - 10.0, 0.001));
      expect(tester.getTopLeft(find.byKey(GlassAppBar.outgoingTitleKey)).dy,
          closeTo(settledDy + 10.0, 0.001));

      // Completion removes the outgoing title (ActionBar.java:1909-1924).
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      expect(find.byKey(GlassAppBar.outgoingTitleKey), findsNothing);
      expect(find.text('Alpha'), findsNothing);
      expect(_opacityOf(tester, find.byKey(GlassAppBar.titleKey)), 1.0);
      expect(tester.getTopLeft(find.byKey(GlassAppBar.titleKey)).dy,
          closeTo(settledDy, 0.001));
    });

    testWidgets('fromBottom mirrors the offsets (ActionBar.java:1893, 1904)',
        (WidgetTester tester) async {
      await tester.pumpWidget(swapHost('Alpha', fromBottom: true));
      final double settledDy =
          tester.getTopLeft(find.byKey(GlassAppBar.titleKey)).dy;
      await tester.pumpWidget(swapHost('Beta', fromBottom: true));
      expect(tester.getTopLeft(find.byKey(GlassAppBar.titleKey)).dy,
          closeTo(settledDy + 20.0, 0.001));
      await tester.pump(const Duration(milliseconds: 110));
      expect(tester.getTopLeft(find.byKey(GlassAppBar.outgoingTitleKey)).dy,
          closeTo(settledDy - 10.0, 0.001));
    });

    testWidgets('animateTitleChange false swaps instantly (plain setTitle)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(child: const GlassAppBar(title: 'Alpha')));
      await tester.pumpWidget(_host(child: const GlassAppBar(title: 'Beta')));
      expect(find.byKey(GlassAppBar.outgoingTitleKey), findsNothing);
      expect(find.text('Alpha'), findsNothing);
      expect(_opacityOf(tester, find.byKey(GlassAppBar.titleKey)), 1.0);
    });
  });

  group('search expand (ActionBar.java:1196-1264)', () {
    Widget searchHost({required bool searchMode, bool isForum = false}) =>
        _host(
          child: GlassAppBar(
            title: 'Chats',
            subtitle: 'online',
            isForum: isForum,
            searchMode: searchMode,
            searchBuilder: (BuildContext context) => const Text('SEARCH'),
            actions: const <Widget>[SizedBox(width: 46, height: 46)],
          ),
        );

    testWidgets('150ms fade: titles out at scale 0.95, search content in',
        (WidgetTester tester) async {
      await tester.pumpWidget(searchHost(searchMode: false));
      await tester.pump();
      expect(find.byKey(GlassAppBar.searchContentKey), findsNothing);
      // Glass menu shift at rest: -10dp (ActionBar.java:242).
      Matrix4 menu =
          _transformOf(tester, find.byKey(GlassAppBar.actionsRowKey));
      expect(menu.getTranslation().x, -10.0);

      await tester.pumpWidget(searchHost(searchMode: true));
      // Animation just started: factor 0.
      expect(_opacityOf(tester, find.byKey(GlassAppBar.searchContentKey)), 0.0);

      // Half of 150ms with the AccelerateDecelerate curve: factor 0.5.
      await tester.pump(const Duration(milliseconds: 75));
      final GlassAppBarState state =
          tester.state<GlassAppBarState>(find.byType(GlassAppBar));
      expect(state.debugSearchFactor, closeTo(0.5, 1e-9));
      expect(_opacityOf(tester, find.byKey(GlassAppBar.titleKey)),
          closeTo(0.5, 1e-9));
      expect(_opacityOf(tester, find.byKey(GlassAppBar.subtitleKey)),
          closeTo(0.5, 1e-9));
      expect(_opacityOf(tester, find.byKey(GlassAppBar.searchContentKey)),
          closeTo(0.5, 1e-9));
      // Hidden-view scale lerps 1 -> 0.95 (ActionBar.java:1221-1226).
      final Matrix4 title =
          _transformOf(tester, find.byKey(GlassAppBar.titleKey));
      expect(title.storage[0], closeTo(0.975, 1e-9));
      // Menu shift lerps -10 -> -5 (ActionBar.java:1207-1209).
      menu = _transformOf(tester, find.byKey(GlassAppBar.actionsRowKey));
      expect(menu.getTranslation().x, closeTo(-7.5, 1e-9));

      // Settled.
      await tester.pump(const Duration(milliseconds: 80));
      expect(state.debugSearchFactor, 1.0);
      expect(_opacityOf(tester, find.byKey(GlassAppBar.titleKey)), 0.0);
      expect(_opacityOf(tester, find.byKey(GlassAppBar.searchContentKey)), 1.0);
      menu = _transformOf(tester, find.byKey(GlassAppBar.actionsRowKey));
      expect(menu.getTranslation().x, closeTo(-5.0, 1e-9));
      // Search content mounts from 66dp (ActionBar.java:1412, 1518).
      expect(tester.getTopLeft(find.text('SEARCH')).dx,
          greaterThanOrEqualTo(kGlassAppBarSearchContentLeft));
    });

    testWidgets('forum main-pill corners animate 18.33 -> 23dp',
        (WidgetTester tester) async {
      await tester.pumpWidget(searchHost(searchMode: false, isForum: true));
      await tester.pump();
      final GlassAppBarState state =
          tester.state<GlassAppBarState>(find.byType(GlassAppBar));
      expect(state.debugMainPillRadii!.topLeft, closeTo(18.33, 1e-9));
      expect(state.debugMainPillRadii!.bottomLeft, closeTo(18.33, 1e-9));
      expect(state.debugMainPillRadii!.topRight, 23.0);
      expect(state.debugMainPillRadii!.bottomRight, 23.0);

      await tester.pumpWidget(searchHost(searchMode: true, isForum: true));
      await tester.pump(const Duration(milliseconds: 75));
      // lerp(18.33, 23, 0.5) (ActionBar.java:1200-1205).
      expect(state.debugMainPillRadii!.topLeft, closeTo(20.665, 1e-9));
      await tester.pump(const Duration(milliseconds: 80));
      expect(state.debugMainPillRadii!.topLeft, 23.0);
    });
  });

  group('search field wiring (ActionBarMenuItem.java:874-1010; '
      'ActionBar.java:271-274)', () {
    testWidgets('searchMode without a builder mounts the built-in field '
        'and fades it over 150ms', (WidgetTester tester) async {
      Widget host({required bool searchMode}) => _host(
            child: GlassAppBar(
              title: 'Chats',
              searchMode: searchMode,
              searchHint: 'Search',
            ),
          );
      await tester.pumpWidget(host(searchMode: false));
      await tester.pump();
      expect(find.byType(GlassAppBarSearchField), findsNothing);

      await tester.pumpWidget(host(searchMode: true));
      expect(find.byType(GlassAppBarSearchField), findsOneWidget);
      expect(_opacityOf(tester, find.byKey(GlassAppBar.searchContentKey)), 0.0);
      await tester.pump(const Duration(milliseconds: 75));
      expect(_opacityOf(tester, find.byKey(GlassAppBar.searchContentKey)),
          closeTo(0.5, 1e-9));
      await tester.pump(const Duration(milliseconds: 80));
      expect(_opacityOf(tester, find.byKey(GlassAppBar.searchContentKey)), 1.0);

      // Socket geometry: from 66dp (ActionBar.java:1412, 1518) to the
      // trailing edge, over the bar band.
      expect(tester.getRect(find.byType(GlassAppBarSearchField)),
          const Rect.fromLTRB(kGlassAppBarSearchContentLeft, 0, 400, 56));
      // The field carries the bar's hint text.
      final Text hint =
          tester.widget<Text>(find.byKey(GlassAppBarSearchField.hintKey));
      expect(hint.data, 'Search');
      // Hint color key actionBarDefaultSearchPlaceholder
      // (ActionBarMenuItem.java:1492).
      expect(hint.style!.color,
          _dayTheme.color(TelegramColorKey.actionBarDefaultSearchPlaceholder));

      // Collapse unmounts it once the fade lands.
      await tester.pumpWidget(host(searchMode: false));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.byType(GlassAppBarSearchField), findsNothing);
    });

    testWidgets('open resets the text and focuses; close unfocuses '
        '(ActionBarMenuItem.java:993-996, 947)', (WidgetTester tester) async {
      final TextEditingController controller =
          TextEditingController(text: 'stale query');
      final FocusNode focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      Widget host({required bool searchMode}) => _host(
            child: GlassAppBar(
              title: 'Chats',
              searchMode: searchMode,
              searchController: controller,
              searchFocusNode: focusNode,
            ),
          );
      await tester.pumpWidget(host(searchMode: false));
      await tester.pump();

      await tester.pumpWidget(host(searchMode: true));
      // searchField.setText("") on open (ActionBarMenuItem.java:993).
      expect(controller.text, isEmpty);
      // requestFocus lands on the next frame (the field mounts this build).
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 200));

      await tester.pumpWidget(host(searchMode: false));
      // searchField.clearFocus() on collapse (ActionBarMenuItem.java:947).
      expect(focusNode.hasFocus, isFalse);
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('searchAutoFocus false opens without grabbing focus '
        '(the openKeyboard flag, ActionBarMenuItem.java:896)',
        (WidgetTester tester) async {
      final FocusNode focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      Widget host({required bool searchMode}) => _host(
            child: GlassAppBar(
              title: 'Chats',
              searchMode: searchMode,
              searchFocusNode: focusNode,
              searchAutoFocus: false,
            ),
          );
      await tester.pumpWidget(host(searchMode: false));
      await tester.pumpWidget(host(searchMode: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(focusNode.hasFocus, isFalse);
    });

    testWidgets('typed text reaches onSearchChanged through the built-in '
        'field', (WidgetTester tester) async {
      final List<String> changes = <String>[];
      await tester.pumpWidget(_host(
        child: GlassAppBar(
          title: 'Chats',
          searchMode: true,
          searchHint: 'Search',
          onSearchChanged: changes.add,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(EditableText), 'cats');
      await tester.pumpAndSettle();
      expect(changes, <String>['cats']);
    });

    testWidgets('while searching, the back slot closes search instead of '
        'its own action (ActionBar.java:271-274)',
        (WidgetTester tester) async {
      int leadingTaps = 0;
      int closes = 0;
      Widget host({required bool searchMode}) => _host(
            child: GlassAppBar(
              title: 'Chats',
              searchMode: searchMode,
              leading: GestureDetector(
                key: const Key('back-button'),
                behavior: HitTestBehavior.opaque,
                onTap: () => leadingTaps++,
                child: const SizedBox(width: 24, height: 24),
              ),
              onSearchClose: () => closes++,
            ),
          );

      // Not searching: no overlay, the leading slot acts itself.
      await tester.pumpWidget(host(searchMode: false));
      await tester.pump();
      expect(find.byKey(GlassAppBar.searchCloseKey), findsNothing);
      await tester.tap(find.byKey(const Key('back-button')));
      expect(leadingTaps, 1);
      expect(closes, 0);

      // Searching: the overlay absorbs the slot and closes search. Like the
      // Java isSearchFieldVisible, it flips with searchMode immediately.
      await tester.pumpWidget(host(searchMode: true));
      expect(find.byKey(GlassAppBar.searchCloseKey), findsOneWidget);
      await tester.tap(find.byKey(const Key('back-button')),
          warnIfMissed: false);
      expect(leadingTaps, 1);
      expect(closes, 1);
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('a custom searchBuilder overrides the built-in field',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: GlassAppBar(
          title: 'Chats',
          searchMode: true,
          searchBuilder: (BuildContext context) => const Text('CUSTOM'),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(GlassAppBarSearchField), findsNothing);
      expect(find.text('CUSTOM'), findsOneWidget);
    });
  });

  group('menu width tracking (ActionBar.java:2115-2116, 2136-2150)', () {
    Widget menuHost(List<Widget> actions) => _host(
          topPadding: 24,
          child: GlassAppBar(title: 'Chats', actions: actions),
        );

    testWidgets('first application snaps; changes animate 320ms EOQ',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(menuHost(const <Widget>[SizedBox(width: 46, height: 46)]));
      await tester.pump();
      final GlassAppBarState state =
          tester.state<GlassAppBarState>(find.byType(GlassAppBar));
      expect(state.debugMenuTrackedWidth, 46.0);
      expect(state.debugHasMenuFactor, 1.0);

      // Grow to two 46dp slots: 92dp, animated. The tracker starts from a
      // post-frame callback, so its ticker clock baselines on the next
      // frame: pump once at zero before advancing time.
      await tester.pumpWidget(menuHost(const <Widget>[
        SizedBox(width: 46, height: 46),
        SizedBox(width: 46, height: 46),
      ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      final double expectedMid =
          46.0 + (92.0 - 46.0) * TgCurves.easeOutQuint.transform(0.5);
      expect(state.debugMenuTrackedWidth, closeTo(expectedMid, 1e-6));

      await tester.pump(const Duration(milliseconds: 170));
      expect(state.debugMenuTrackedWidth, 92.0);
      // Menu pill settled: left = 400 - max(46, 92) - 12 = 296.
      expect(tester.getRect(find.byKey(GlassAppBar.menuPillKey)),
          const Rect.fromLTRB(296, 23, 400, 81));
      // Main pill right = 400 - (92 + 6) = 302.
      expect(tester.getRect(find.byKey(GlassAppBar.mainPillKey)),
          const Rect.fromLTRB(0, 23, 302, 81));
    });

    testWidgets('losing all actions animates the pill away',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(menuHost(const <Widget>[SizedBox(width: 46, height: 46)]));
      await tester.pump();
      expect(find.byKey(GlassAppBar.menuPillKey), findsOneWidget);

      await tester.pumpWidget(menuHost(const <Widget>[]));
      await tester.pump(); // Baseline the tracker ticker (post-frame start).
      await tester.pump(const Duration(milliseconds: 400));
      final GlassAppBarState state =
          tester.state<GlassAppBarState>(find.byType(GlassAppBar));
      expect(state.debugMenuTrackedWidth, 0.0);
      expect(state.debugHasMenuFactor, 0.0);
      expect(find.byKey(GlassAppBar.menuPillKey), findsNothing);
      // Main pill reclaims the full width.
      expect(tester.getRect(find.byKey(GlassAppBar.mainPillKey)),
          const Rect.fromLTRB(0, 23, 400, 81));
    });

    testWidgets('leading slot is 54dp wide with the +2dp glass shift',
        (WidgetTester tester) async {
      const Key backKey = Key('back-icon');
      await tester.pumpWidget(_host(
        topPadding: 24,
        child: GlassAppBar(
          title: 'Chats',
          leading: const SizedBox(key: backKey, width: 24, height: 24),
        ),
      ));
      // Centered in the 54dp x 56dp slot at (0, 24), shifted +2dp:
      // x = (54-24)/2 + 2 = 17, y = 24 + (56-24)/2 = 40.
      expect(tester.getTopLeft(find.byKey(backKey)), const Offset(17, 40));
    });
  });
}
