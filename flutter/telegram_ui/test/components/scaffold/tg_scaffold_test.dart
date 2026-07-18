// Tests for lib/src/components/scaffold/tg_scaffold.dart
// (ARCHITECTURE.md section 6, row "TgScaffold"), golden-free:
//
//  * inset injection: body MediaQuery.padding.bottom = safe-area bottom +
//    72dp (DialogsActivity.java:289-291, 2978; MainTabsActivity.java:805)
//    and padding.top = safe-area top + appBar preferred height;
//  * slot layout rects: full-bleed body, top bar box, bottom-docked tab bar
//    (pill bottom = navigationBar edge, MainTabsActivity.java:359, 824);
//  * edge fades: 60dp/opacity MainTabs table behind the bottom slot
//    (MainTabsActivity.java:350-355, 804-809), default 40dp/5-stop table
//    behind the top slot with the ramp anchored bottom-up
//    (BlurredBackgroundWithFadeDrawable.java:58;
//    ChatActivityFadeView.java:47-48, 95-99);
//  * GlassBackdropScope installation and background color resolution
//    (windowBackgroundWhite key).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/scaffold/tg_scaffold.dart';
import 'package:telegram_ui/src/components/tabs/glass_tab_bar.dart'
    show kGlassTabBarHeightWithMargins;
import 'package:telegram_ui/src/glass/backdrop_scope.dart';
import 'package:telegram_ui/src/glass/glass_fade.dart';
import 'package:telegram_ui/src/glass/glass_panel.dart';
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

const Key _bodyKey = Key('body');
const Key _appBarKey = Key('appBar');
const Key _tabBarKey = Key('tabBar');

/// Default test screen is 800x600; safe-area insets used across the tests.
const EdgeInsets _padding = EdgeInsets.only(left: 5, top: 20, right: 7, bottom: 30);

PreferredSizeWidget _appBar({double height = 56}) => PreferredSize(
      key: _appBarKey,
      preferredSize: Size.fromHeight(height),
      child: const SizedBox.expand(),
    );

Widget _tabBar() => const SizedBox(key: _tabBarKey, height: 72, width: double.infinity);

Widget _host({required Widget scaffold, MediaQueryData? mediaQuery}) {
  Widget child = scaffold;
  child = MediaQuery(
    data: mediaQuery ?? const MediaQueryData(size: Size(800, 600), padding: _padding),
    child: child,
  );
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  );
}

Finder _bottomFade() => find.byWidgetPredicate(
    (Widget w) => w is GlassEdgeFade && w.opacity, description: 'MainTabs fade');

Finder _topFade() => find.byWidgetPredicate(
    (Widget w) => w is GlassEdgeFade && !w.opacity, description: 'default fade');

void main() {
  test('kTgScaffoldTabBarInset mirrors MAIN_TABS_HEIGHT_WITH_MARGINS', () {
    // DialogsActivity.java:289-291: 56 + 8 * 2.
    expect(kTgScaffoldTabBarInset, 72.0);
    expect(kTgScaffoldTabBarInset, kGlassTabBarHeightWithMargins);
  });

  group('inset injection', () {
    testWidgets('bottom = navBar + 72dp, top = statusBar + appBar height',
        (WidgetTester tester) async {
      late MediaQueryData seen;
      await tester.pumpWidget(_host(
        scaffold: TgScaffold(
          settings: _manualSettings(),
          probeOnMount: false,
          appBar: _appBar(),
          tabBar: _tabBar(),
          body: Builder(builder: (BuildContext context) {
            seen = MediaQuery.of(context);
            return const SizedBox.expand(key: _bodyKey);
          }),
        ),
      ));
      // DialogsActivity.java:2978: navigationBarHeight + dp(72).
      expect(seen.padding.bottom, 30 + kTgScaffoldTabBarInset);
      expect(seen.padding.top, 20 + 56);
      // Horizontal safe-area padding passes through untouched.
      expect(seen.padding.left, 5);
      expect(seen.padding.right, 7);
    });

    testWidgets('missing slots leave the respective inset untouched',
        (WidgetTester tester) async {
      late MediaQueryData seen;
      await tester.pumpWidget(_host(
        scaffold: TgScaffold(
          settings: _manualSettings(),
          probeOnMount: false,
          body: Builder(builder: (BuildContext context) {
            seen = MediaQuery.of(context);
            return const SizedBox.expand(key: _bodyKey);
          }),
        ),
      ));
      expect(seen.padding, _padding);
    });

    testWidgets('tabBar only: top inset untouched, bottom grown',
        (WidgetTester tester) async {
      late MediaQueryData seen;
      await tester.pumpWidget(_host(
        scaffold: TgScaffold(
          settings: _manualSettings(),
          probeOnMount: false,
          tabBar: _tabBar(),
          body: Builder(builder: (BuildContext context) {
            seen = MediaQuery.of(context);
            return const SizedBox.expand(key: _bodyKey);
          }),
        ),
      ));
      expect(seen.padding.top, 20);
      expect(seen.padding.bottom, 30 + 72);
    });

    testWidgets('no ambient MediaQuery: insets are the bar extents alone',
        (WidgetTester tester) async {
      late MediaQueryData seen;
      await tester.pumpWidget(TelegramTheme(
        data: _dayTheme,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: TgScaffold(
            settings: _manualSettings(),
            probeOnMount: false,
            appBar: _appBar(),
            tabBar: _tabBar(),
            body: Builder(builder: (BuildContext context) {
              seen = MediaQuery.of(context);
              return const SizedBox.expand(key: _bodyKey);
            }),
          ),
        ),
      ));
      expect(seen.padding.top, 56);
      expect(seen.padding.bottom, 72);
    });
  });

  group('slot layout', () {
    testWidgets('body full-bleed; appBar and tabBar boxes', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        scaffold: TgScaffold(
          settings: _manualSettings(),
          probeOnMount: false,
          appBar: _appBar(),
          tabBar: _tabBar(),
          body: const SizedBox.expand(key: _bodyKey),
        ),
      ));
      // extendBodyBehindBars: the body covers the whole scaffold.
      expect(tester.getRect(find.byKey(_bodyKey)), const Rect.fromLTWH(0, 0, 800, 600));
      // Top slot: status bar (20) + preferred height (56).
      expect(tester.getRect(find.byKey(_appBarKey)), const Rect.fromLTWH(0, 0, 800, 76));
      // Bottom slot: docked to the bottom safe-area edge (bottom = 600 - 30),
      // 72dp tall (MainTabsActivity.java:359: pill bottom = navBar + 8dp,
      // margins inside the box).
      expect(tester.getRect(find.byKey(_tabBarKey)),
          const Rect.fromLTWH(0, 600 - 30 - 72, 800, 72));
    });

    testWidgets('extendBodyBehindBars false: body sits between the bars',
        (WidgetTester tester) async {
      late MediaQueryData seen;
      await tester.pumpWidget(_host(
        scaffold: TgScaffold(
          settings: _manualSettings(),
          probeOnMount: false,
          extendBodyBehindBars: false,
          appBar: _appBar(),
          tabBar: _tabBar(),
          body: Builder(builder: (BuildContext context) {
            seen = MediaQuery.of(context);
            return const SizedBox.expand(key: _bodyKey);
          }),
        ),
      ));
      // Body box: below the 76dp top slot, above the 102dp bottom region.
      expect(tester.getRect(find.byKey(_bodyKey)),
          const Rect.fromLTRB(0, 76, 800, 600 - 102));
      // The covered safe-area edges are consumed.
      expect(seen.padding.top, 0);
      expect(seen.padding.bottom, 0);
      expect(seen.padding.left, 5);
      expect(seen.padding.right, 7);
      // No fades: nothing renders behind the bars.
      expect(_bottomFade(), findsNothing);
      expect(_topFade(), findsNothing);
    });

    testWidgets('body is wrapped in a RepaintBoundary', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        scaffold: TgScaffold(
          settings: _manualSettings(),
          probeOnMount: false,
          body: const SizedBox.expand(key: _bodyKey),
        ),
      ));
      expect(
        find.ancestor(of: find.byKey(_bodyKey), matching: find.byType(RepaintBoundary)),
        findsWidgets,
      );
    });
  });

  group('edge fades', () {
    testWidgets('bottom: 60dp MainTabs table over the navBar + 72dp zone',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        scaffold: TgScaffold(
          settings: _manualSettings(),
          probeOnMount: false,
          tabBar: _tabBar(),
          body: const SizedBox.expand(key: _bodyKey),
        ),
      ));
      final GlassEdgeFade fade = tester.widget(_bottomFade());
      // setFadeHeight(dp(60), true) (MainTabsActivity.java:352); positive
      // Java fadeHeight = transparent at the top edge, fading downward.
      expect(fade.fadeHeight, 60.0);
      expect(fade.opacity, isTrue);
      expect(fade.direction, GlassFadeDirection.down);
      // Zone: full width, height navBar + 72, anchored bottom
      // (MainTabsActivity.java:355, 805).
      expect(tester.getRect(_bottomFade()),
          const Rect.fromLTWH(0, 600 - (30 + 72), 800, 30 + 72));
      // The masked child is the un-tinted blur surface (null color provider,
      // MainTabsActivity.java:351).
      expect(find.descendant(of: _bottomFade(), matching: find.byType(FrostedPanel)),
          findsOneWidget);
      // No top fade without an appBar.
      expect(_topFade(), findsNothing);
    });

    testWidgets('top: default 40dp table, ramp anchored at the zone bottom',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        scaffold: TgScaffold(
          settings: _manualSettings(),
          probeOnMount: false,
          appBar: _appBar(),
          body: const SizedBox.expand(key: _bodyKey),
        ),
      ));
      final GlassEdgeFade fade = tester.widget(_topFade());
      // Drawable default dp(40), opacity false
      // (BlurredBackgroundWithFadeDrawable.java:58); the top-zone drawable
      // uses a negative fade height = transparent at the bottom edge
      // (ChatActivityFadeView.java:47-48).
      expect(fade.fadeHeight, 40.0);
      expect(fade.opacity, isFalse);
      expect(fade.direction, GlassFadeDirection.up);
      // Zone: the top slot box (ChatActivityFadeView.java:95-99 anchors the
      // top drawable to (0, 0, width, fadeZoneTop)).
      expect(tester.getRect(_topFade()), const Rect.fromLTWH(0, 0, 800, 76));
      expect(find.descendant(of: _topFade(), matching: find.byType(FrostedPanel)),
          findsOneWidget);
      expect(_bottomFade(), findsNothing);
    });
  });

  group('scope and background', () {
    testWidgets('installs a GlassBackdropScope around the body',
        (WidgetTester tester) async {
      GlassScopeData? scope;
      await tester.pumpWidget(_host(
        scaffold: TgScaffold(
          settings: _manualSettings(),
          probeOnMount: false,
          body: Builder(builder: (BuildContext context) {
            scope = GlassBackdropScope.maybeOf(context);
            return const SizedBox.expand(key: _bodyKey);
          }),
        ),
      ));
      expect(scope, isNotNull);
      // Un-probed settings resolve the default liquid request to frosted.
      expect(scope!.requestedTier, GlassTier.liquid);
      expect(scope!.tier, GlassTier.frosted);
      expect(scope!.strategy, GlassStrategy.backdropShader);
    });

    testWidgets('forwards the requested tier to the scope', (WidgetTester tester) async {
      GlassScopeData? scope;
      await tester.pumpWidget(_host(
        scaffold: TgScaffold(
          settings: _manualSettings(),
          probeOnMount: false,
          tier: GlassTier.flat,
          body: Builder(builder: (BuildContext context) {
            scope = GlassBackdropScope.maybeOf(context);
            return const SizedBox.expand(key: _bodyKey);
          }),
        ),
      ));
      expect(scope!.requestedTier, GlassTier.flat);
      expect(scope!.tier, GlassTier.flat);
      // The flat floor never mounts a backdrop layer.
      expect(scope!.strategy, GlassStrategy.tintOnly);
    });

    testWidgets('background defaults to windowBackgroundWhite; override wins',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        scaffold: TgScaffold(
          settings: _manualSettings(),
          probeOnMount: false,
          body: const SizedBox.expand(key: _bodyKey),
        ),
      ));
      final ColoredBox background = tester.widget(
        find.ancestor(of: find.byKey(_bodyKey), matching: find.byType(ColoredBox)).last,
      );
      expect(background.color, _dayTheme.color(TelegramColorKey.windowBackgroundWhite));

      await tester.pumpWidget(_host(
        scaffold: TgScaffold(
          settings: _manualSettings(),
          probeOnMount: false,
          backgroundColor: const Color(0xFF123456),
          body: const SizedBox.expand(key: _bodyKey),
        ),
      ));
      final ColoredBox overridden = tester.widget(
        find.ancestor(of: find.byKey(_bodyKey), matching: find.byType(ColoredBox)).last,
      );
      expect(overridden.color, const Color(0xFF123456));
    });
  });
}
