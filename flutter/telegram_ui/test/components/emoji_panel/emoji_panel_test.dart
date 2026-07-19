// Ring-1 tests for lib/src/components/emoji_panel/emoji_panel.dart — the
// EmojiView chrome shell (spec_attach_emoji.md Part B), golden-free:
//
//  * bottom tab strip geometry + indicator — 48dp strip, (4,11,4,11)
//    padding, 11dp tab padding around 24x24 icon slots, indicator pill =
//    full tab bounds with radius height/2 at chat_emojiPanelIconSelected
//    alpha 20/255, 350ms EASE_OUT_QUINT settle (EV:2697-2705,
//    PSTS:249-300); glass background emojiViewButton r18/pad6
//    (EV:2923-2951);
//  * tab switching + EmojiPanelController — page slide/indicator share the
//    350ms clock, offstage page retention (EV:2709), callback semantics;
//  * category strip selection — 36dp strip, 30x30 buttons, 11dp content
//    padding, leftover-as-margins (ETS:196), selector squash
//    (ETS:702-711), radius 8 vs height/2 (ETS:268-272);
//  * search row layout — 50dp row, 36dp r18 box, margins (10, 6/8, 10, 8),
//    16dp hint, 36x36 icon slots (EV:796-1010);
//  * trending header — 27dp, 15dp bold title, 3dp dot (SSNC:234, 79;
//    EV:6512-6515);
//  * chat_emojiPanel* color keys resolved light/dark + resources override.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/emoji_panel/emoji_panel.dart';
import 'package:telegram_ui/src/foundation/color_math.dart';
import 'package:telegram_ui/src/foundation/tg_curves.dart';
import 'package:telegram_ui/src/glass/backdrop_scope.dart';
import 'package:telegram_ui/src/glass/geometry.dart';
import 'package:telegram_ui/src/glass/glass_panel.dart';
import 'package:telegram_ui/src/glass/presets.dart';
import 'package:telegram_ui/src/glass/runtime_probe.dart';
import 'package:telegram_ui/src/theme/telegram_resources.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared themes (constructing the 777-key palettes once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();
final TelegramThemeData _nightTheme = TelegramThemeData.night();

/// Settings whose probe never resolves: liquid requests stay conservatively
/// frosted — the deterministic flutter_tester path.
GlassSettings _manualSettings() =>
    GlassSettings(probe: () => Completer<GlassCapability>().future);

Widget _host(Widget child, {TelegramThemeData? theme, double width = 400}) {
  return TelegramTheme(
    data: theme ?? _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: GlassBackdropScope(
        settings: _manualSettings(),
        probeOnMount: false,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

Key _iconKey(int i) => ValueKey<String>('icon$i');

List<Widget> _icons(int n) => <Widget>[
      for (int i = 0; i < n; i++)
        ColoredBox(key: _iconKey(i), color: const Color(0xFF000000)),
    ];

EmojiPanelTabIndicatorPainter _indicatorPainterOf(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (Widget w) => w is CustomPaint && w.painter is EmojiPanelTabIndicatorPainter,
    ),
  );
  return paint.painter! as EmojiPanelTabIndicatorPainter;
}

EmojiCategorySelectorPainter _selectorPainterOf(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (Widget w) => w is CustomPaint && w.painter is EmojiCategorySelectorPainter,
    ),
  );
  return paint.painter! as EmojiCategorySelectorPainter;
}

/// Fixed-palette resources for exact expectations.
class _FixedResources extends TelegramResources {
  const _FixedResources(this.colors);

  final Map<int, Color> colors;

  @override
  Color getColor(int key) => colors[key] ?? const Color(0xFF000000);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bottom tab strip geometry + indicator', () {
    testWidgets('strip: 48dp tall, 8 + 3*46 content, centered 24x24 icon '
        'slots (EV:2678, 2703-2704)', (tester) async {
      await tester.pumpWidget(_host(EmojiPanelTabStrip(icons: _icons(3))));

      final EmojiPanelTabStrip strip =
          tester.widget<EmojiPanelTabStrip>(find.byType(EmojiPanelTabStrip));
      // Tab cell = 24 icon + 2*11 padding; content = strip padding + tabs.
      expect(EmojiPanelTabStrip.tabWidth, 46.0);
      expect(strip.contentWidth, 4.0 + 3 * 46.0 + 4.0);
      expect(
        tester.getSize(find.byType(EmojiPanelTabStrip)),
        const Size(400, 48),
      );

      // The 146dp pill is centered in the 400dp host: left (400-146)/2.
      final Rect content = tester.getRect(find.byWidgetPredicate(
        (Widget w) => w is SizedBox && w.width == 146.0 && w.height == 48.0,
      ));
      expect(content, const Rect.fromLTWH(127, 0, 146, 48));

      // Icon slot i: 24x24, centered in the (4 + i*46 .. +46) cell, in the
      // 11..37 vertical band.
      for (int i = 0; i < 3; i++) {
        final Rect icon = tester.getRect(find.byKey(_iconKey(i)));
        expect(icon.size, const Size(24, 24));
        expect(icon.center.dx, 127.0 + 4.0 + i * 46.0 + 23.0);
        expect(icon.center.dy, 24.0);
      }
    });

    testWidgets('glass background: emojiViewButton preset, r18, glass '
        'padding 6 (EV:2923-2951); non-glass has none', (tester) async {
      await tester.pumpWidget(_host(EmojiPanelTabStrip(icons: _icons(3))));
      final GlassPanel panel =
          tester.widget<GlassPanel>(find.byType(GlassPanel));
      expect(panel.preset, GlassPresets.emojiViewButton);
      expect(panel.borderRadius, const GlassRadii.all(18.0));
      expect(panel.padding, 6.0);

      await tester.pumpWidget(
        _host(EmojiPanelTabStrip(icons: _icons(3), glass: false)),
      );
      expect(find.byType(GlassPanel), findsNothing);
    });

    testWidgets('indicator rect = full tab bounds, radius h/2, '
        'chat_emojiPanelIconSelected @20/255 (EV:2701, PSTS:295-300)',
        (tester) async {
      await tester.pumpWidget(_host(EmojiPanelTabStrip(icons: _icons(3))));
      final EmojiPanelTabIndicatorPainter p = _indicatorPainterOf(tester);

      expect(p.position, 0.0);
      // lineLeft - 11 .. lineRight + 11 == the tab cell bounds; vertical
      // paddingTop .. height - paddingBottom.
      expect(p.rectFor(0), const Rect.fromLTRB(4, 11, 50, 37));
      expect(p.rectFor(1), const Rect.fromLTRB(50, 11, 96, 37));
      expect(p.rectFor(2), const Rect.fromLTRB(96, 11, 142, 37));
      // Position clamps to the tab range.
      expect(p.rectFor(5), p.rectFor(2));
      expect(
        p.color.toARGB32(),
        _dayTheme
            .color(TelegramColorKey.chat_emojiPanelIconSelected)
            .withAlpha(20)
            .toARGB32(),
      );

      // Painted as one round-rect with radius height/2 = 13 (PSTS:299).
      final TestRecordingCanvas canvas = TestRecordingCanvas();
      p.paint(canvas, const Size(146, 48));
      final List<RecordedInvocation> rrects = <RecordedInvocation>[
        for (final RecordedInvocation r in canvas.invocations)
          if (r.invocation.memberName == #drawRRect) r,
      ];
      expect(rrects, hasLength(1));
      final RRect rrect =
          rrects.single.invocation.positionalArguments[0] as RRect;
      expect(rrect.outerRect, p.rectFor(0));
      expect(rrect.tlRadiusX, 13.0);
      expect(
        (rrects.single.invocation.positionalArguments[1] as Paint)
            .color
            .toARGB32(),
        p.color.toARGB32(),
      );
    });

    testWidgets('index change slides the indicator over 350ms '
        'EASE_OUT_QUINT (PSTS:249-250)', (tester) async {
      await tester
          .pumpWidget(_host(EmojiPanelTabStrip(icons: _icons(3))));
      final EmojiPanelTabStripState state = tester
          .state<EmojiPanelTabStripState>(find.byType(EmojiPanelTabStrip));
      expect(state.debugPosition, 0.0);

      await tester
          .pumpWidget(_host(EmojiPanelTabStrip(icons: _icons(3), index: 2)));
      await tester.pump(); // t = 0
      expect(state.debugPosition, 0.0);
      await tester.pump(const Duration(milliseconds: 175)); // t = 0.5
      expect(
        state.debugPosition,
        moreOrLessEquals(2.0 * TgCurves.easeOutQuint.transform(0.5),
            epsilon: 1e-9),
      );
      expect(_indicatorPainterOf(tester).position, state.debugPosition);
      await tester.pumpAndSettle();
      expect(state.debugPosition, 2.0);
    });

    testWidgets('taps fire onSelected, including on the active tab',
        (tester) async {
      final List<int> taps = <int>[];
      await tester.pumpWidget(
        _host(EmojiPanelTabStrip(icons: _icons(3), onSelected: taps.add)),
      );
      await tester.tap(find.byKey(_iconKey(1)));
      await tester.tap(find.byKey(_iconKey(0)));
      await tester.tap(find.byKey(_iconKey(0))); // active-tab click-through
      expect(taps, <int>[1, 0, 0]);
    });

    testWidgets('icon tints: glass_defaultIcon @80/40% (glass) vs '
        'chat_emoji* keys (EV:1583-1585, 5903-5904)', (tester) async {
      ColorFilter filterOf(int i) => tester
          .widget<ColorFiltered>(
            find
                .ancestor(
                  of: find.byKey(_iconKey(i)),
                  matching: find.byType(ColorFiltered),
                )
                .first,
          )
          .colorFilter;

      final int glassIcon =
          _dayTheme.color(TelegramColorKey.glass_defaultIcon).toARGB32();
      await tester.pumpWidget(_host(EmojiPanelTabStrip(icons: _icons(3))));
      expect(
        filterOf(0),
        ColorFilter.mode(Color(multAlpha(glassIcon, 0.8)), BlendMode.srcIn),
      );
      expect(
        filterOf(2),
        ColorFilter.mode(Color(multAlpha(glassIcon, 0.4)), BlendMode.srcIn),
      );

      await tester.pumpWidget(
        _host(EmojiPanelTabStrip(icons: _icons(3), glass: false)),
      );
      expect(
        filterOf(0),
        ColorFilter.mode(
          _dayTheme.color(TelegramColorKey.chat_emojiPanelIconSelected),
          BlendMode.srcIn,
        ),
      );
      expect(
        filterOf(2),
        ColorFilter.mode(
          _dayTheme.color(TelegramColorKey.chat_emojiBottomPanelIcon),
          BlendMode.srcIn,
        ),
      );
    });
  });

  group('tab switching + controller', () {
    test('EmojiPanelController: {activeTab, categoryIndex} semantics', () {
      final EmojiPanelController c = EmojiPanelController();
      expect(c.activeTab, EmojiPanelTab.emoji);
      expect(c.categoryIndex, 0);

      int notifications = 0;
      c.addListener(() => notifications++);

      c.selectTab(EmojiPanelTab.stickers);
      expect(c.activeTab, EmojiPanelTab.stickers);
      expect(c.tabChangeAnimated, isTrue);
      expect(notifications, 1);

      c.selectTab(EmojiPanelTab.stickers); // no-op
      expect(notifications, 1);

      c.selectTab(EmojiPanelTab.gifs, animated: false);
      expect(c.tabChangeAnimated, isFalse);
      expect(notifications, 2);

      c.selectCategory(3);
      expect(c.categoryIndex, 3);
      expect(notifications, 3);
      c.selectCategory(3); // no-op
      expect(notifications, 3);
      c.dispose();
    });

    test('page order is 0 emoji, 1 GIFs, 2 stickers (EV:196, 2810)', () {
      expect(EmojiPanelTab.emoji.index, 0);
      expect(EmojiPanelTab.gifs.index, 1);
      expect(EmojiPanelTab.stickers.index, 2);
    });

    testWidgets('height rules: imposed height (default 200) + bottomInset; '
        'grid padding 44 + inset (CAEV:12597-12621, EV:2956-2972)',
        (tester) async {
      await tester.pumpWidget(_host(EmojiPanel(tabIcons: _icons(3))));
      expect(tester.getSize(find.byType(EmojiPanel)), const Size(400, 200));

      await tester.pumpWidget(
        _host(EmojiPanel(tabIcons: _icons(3), bottomInset: 34)),
      );
      expect(tester.getSize(find.byType(EmojiPanel)), const Size(400, 234));
      // The 48dp bottom band is lifted above the inset (EV:4448-4453).
      final Rect strip = tester.getRect(find.byType(EmojiPanelTabStrip));
      expect(strip.bottom, 234.0 - 34.0);
      expect(strip.height, 48.0);

      expect(EmojiPanel.gridBottomPadding(0), 44.0);
      expect(EmojiPanel.gridBottomPadding(34), 78.0);
    });

    testWidgets('tap switches the page: controller + callback + 350ms slide, '
        'offstage retention (EV:2709, PSTS:249-250)', (tester) async {
      final EmojiPanelController controller = EmojiPanelController();
      addTearDown(controller.dispose);
      final List<EmojiPanelTab> selected = <EmojiPanelTab>[];
      await tester.pumpWidget(_host(EmojiPanel(
        controller: controller,
        tabIcons: _icons(3),
        onTabSelected: selected.add,
      )));
      final EmojiPanelState state =
          tester.state<EmojiPanelState>(find.byType(EmojiPanel));

      // Page 0: the GIF page is kept alive but offstage.
      expect(state.debugPage, 0.0);
      expect(
        find.byKey(EmojiPanel.bodyKeyFor(EmojiPanelTab.gifs)),
        findsNothing,
      );
      expect(
        find.byKey(EmojiPanel.bodyKeyFor(EmojiPanelTab.gifs),
            skipOffstage: false),
        findsOneWidget,
      );

      await tester.tap(find.byKey(_iconKey(1)));
      expect(controller.activeTab, EmojiPanelTab.gifs);
      expect(selected, <EmojiPanelTab>[EmojiPanelTab.gifs]);

      await tester.pump(); // t = 0
      await tester.pump(const Duration(milliseconds: 175)); // t = 0.5
      expect(
        state.debugPage,
        moreOrLessEquals(TgCurves.easeOutQuint.transform(0.5), epsilon: 1e-9),
      );
      // Mid-slide both pages are onstage.
      expect(
        find.byKey(EmojiPanel.bodyKeyFor(EmojiPanelTab.emoji)),
        findsOneWidget,
      );
      expect(
        find.byKey(EmojiPanel.bodyKeyFor(EmojiPanelTab.gifs)),
        findsOneWidget,
      );

      await tester.pumpAndSettle();
      expect(state.debugPage, 1.0);
      // The emoji page sits one width to the left, offstage.
      final FractionalTranslation emojiSlide =
          tester.widget<FractionalTranslation>(
        find
            .ancestor(
              of: find.byKey(EmojiPanel.bodyKeyFor(EmojiPanelTab.emoji),
                  skipOffstage: false),
              matching:
                  find.byType(FractionalTranslation, skipOffstage: false),
            )
            .first,
      );
      expect(emojiSlide.translation, const Offset(-1, 0));
    });

    testWidgets('programmatic selectTab: animated slide or snap, no '
        'onTabSelected', (tester) async {
      final EmojiPanelController controller = EmojiPanelController();
      addTearDown(controller.dispose);
      final List<EmojiPanelTab> selected = <EmojiPanelTab>[];
      await tester.pumpWidget(_host(EmojiPanel(
        controller: controller,
        tabIcons: _icons(3),
        onTabSelected: selected.add,
      )));
      final EmojiPanelState state =
          tester.state<EmojiPanelState>(find.byType(EmojiPanel));

      controller.selectTab(EmojiPanelTab.stickers, animated: false);
      await tester.pump();
      expect(state.debugPage, 2.0); // snap
      expect(selected, isEmpty);
      await tester.pumpAndSettle(); // strip indicator settles
      final EmojiPanelTabStripState strip = tester
          .state<EmojiPanelTabStripState>(find.byType(EmojiPanelTabStrip));
      expect(strip.debugPosition, 2.0);

      controller.selectTab(EmojiPanelTab.emoji);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 175));
      expect(
        state.debugPage,
        moreOrLessEquals(
          2.0 * (1.0 - TgCurves.easeOutQuint.transform(0.5)),
          epsilon: 1e-9,
        ),
      );
      await tester.pumpAndSettle();
      expect(state.debugPage, 0.0);
      expect(selected, isEmpty);
    });

    testWidgets('internal controller when none is supplied', (tester) async {
      await tester.pumpWidget(_host(EmojiPanel(
        tabIcons: _icons(3),
        initialTab: EmojiPanelTab.gifs,
      )));
      final EmojiPanelState state =
          tester.state<EmojiPanelState>(find.byType(EmojiPanel));
      expect(state.controller.activeTab, EmojiPanelTab.gifs);
      expect(state.debugPage, 1.0);

      await tester.tap(find.byKey(_iconKey(2)));
      await tester.pumpAndSettle();
      expect(state.controller.activeTab, EmojiPanelTab.stickers);
      expect(state.debugPage, 2.0);
    });
  });

  group('category strip selection', () {
    test('layout math: 11dp padding, 30dp buttons, leftover as equal '
        'margins (ETS:196, 647-655, 1237)', () {
      // 4 buttons in 400: natural = 11 + 4*30 + 11 = 142; extra/button =
      // 258/4 = 64.5; stride 94.5, margin 32.25 each side.
      expect(EmojiCategoryStrip.slotStride(4, 400), 94.5);
      expect(EmojiCategoryStrip.slotLeft(0, 4, 400), 11.0 + 32.25);
      expect(EmojiCategoryStrip.slotCenterX(0, 4, 400), 58.25);
      expect(EmojiCategoryStrip.slotCenterX(2, 4, 400), 58.25 + 2 * 94.5);
      // Overflow: stride stays 30 (the strip scrolls instead).
      expect(EmojiCategoryStrip.slotStride(20, 400), 30.0);
      expect(EmojiCategoryStrip.slotLeft(0, 20, 400), 11.0);
    });

    test('selector squash: w x(1+0.3*isMiddle), h x(1-0.05*isMiddle), '
        'isMiddle = 4t(1-t) (ETS:702-711, 255-259)', () {
      // At rest (from == to): plain 30x30 pill centered at y 18.
      final Rect rest = EmojiCategoryStrip.selectorRectFor(
          fromCenterX: 58.25, toCenterX: 58.25, t: 0.7);
      expect(rest, Rect.fromCenter(
          center: const Offset(58.25, 18), width: 30, height: 30));

      // Mid-flight (t = 0.5, isMiddle = 1): 39 x 28.5 at the midpoint.
      final Rect mid = EmojiCategoryStrip.selectorRectFor(
          fromCenterX: 58.25, toCenterX: 247.25, t: 0.5);
      expect(mid.width, moreOrLessEquals(39.0, epsilon: 1e-9));
      expect(mid.height, moreOrLessEquals(28.5, epsilon: 1e-9));
      expect(mid.center.dx, moreOrLessEquals(152.75, epsilon: 1e-9));

      // Endpoints are unsquashed.
      final Rect end = EmojiCategoryStrip.selectorRectFor(
          fromCenterX: 58.25, toCenterX: 247.25, t: 1.0);
      expect(end, Rect.fromCenter(
          center: const Offset(247.25, 18), width: 30, height: 30));
    });

    testWidgets('geometry, tap selection, and the 350ms EOQ slide',
        (tester) async {
      final List<int> taps = <int>[];
      int selected = 0;
      await tester.pumpWidget(_host(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return EmojiCategoryStrip(
              icons: _icons(4),
              selectedIndex: selected,
              onSelected: (int i) {
                taps.add(i);
                setState(() => selected = i);
              },
            );
          },
        ),
      ));

      expect(
        tester.getSize(find.byType(EmojiCategoryStrip)),
        const Size(400, 36),
      );
      // Button 2's 30x30 bounds at slotLeft, vertically centered (top 3).
      // (The icon child itself is an unconstrained slot; measure the button.)
      final Rect slot2 = tester.getRect(
        find
            .ancestor(
              of: find.byKey(_iconKey(2)),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(slot2.left, EmojiCategoryStrip.slotLeft(2, 4, 400));
      expect(slot2.top, 3.0);
      expect(slot2.size, const Size(30, 30));

      final EmojiCategoryStripState state = tester
          .state<EmojiCategoryStripState>(find.byType(EmojiCategoryStrip));
      expect(
        state.debugSelectorRect,
        Rect.fromCenter(
          center: Offset(EmojiCategoryStrip.slotCenterX(0, 4, 400), 18),
          width: 30,
          height: 30,
        ),
      );

      await tester.tap(find.byKey(_iconKey(2)));
      expect(taps, <int>[2]);
      await tester.pump(); // rebuild + animation start
      await tester.pump(const Duration(milliseconds: 175)); // t = 0.5
      expect(
        state.debugSelectorRect,
        EmojiCategoryStrip.selectorRectFor(
          fromCenterX: EmojiCategoryStrip.slotCenterX(0, 4, 400),
          toCenterX: EmojiCategoryStrip.slotCenterX(2, 4, 400),
          t: TgCurves.easeOutQuint.transform(0.5),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        state.debugSelectorRect,
        Rect.fromCenter(
          center: Offset(EmojiCategoryStrip.slotCenterX(2, 4, 400), 18),
          width: 30,
          height: 30,
        ),
      );
    });

    testWidgets('selector color/radius: glass_defaultIcon@5% r=h/2 (glass) '
        'vs chat_emojiPanelIcon@18% r=8 (ETS:268-272, 743-752)',
        (tester) async {
      await tester.pumpWidget(_host(EmojiCategoryStrip(icons: _icons(3))));
      EmojiCategorySelectorPainter p = _selectorPainterOf(tester);
      expect(
        p.color.toARGB32(),
        multAlpha(
          _dayTheme.color(TelegramColorKey.glass_defaultIcon).toARGB32(),
          0.05,
        ),
      );
      expect(p.radius, 15.0); // height/2 at rest

      await tester.pumpWidget(
        _host(EmojiCategoryStrip(icons: _icons(3), glass: false)),
      );
      p = _selectorPainterOf(tester);
      expect(
        p.color.toARGB32(),
        multAlpha(
          _dayTheme.color(TelegramColorKey.chat_emojiPanelIcon).toARGB32(),
          0.18,
        ),
      );
      expect(p.radius, 8.0);
    });

    testWidgets('bottom shadow line: 1px chat_emojiPanelShadowLine '
        '(EV:1967-1973), removable', (tester) async {
      await tester.pumpWidget(_host(EmojiCategoryStrip(icons: _icons(3))));
      final Rect line = tester.getRect(find.byKey(EmojiCategoryStrip.shadowKey));
      expect(line, const Rect.fromLTWH(0, 35, 400, 1));
      final ColoredBox box = tester.widget<ColoredBox>(find.descendant(
        of: find.byKey(EmojiCategoryStrip.shadowKey),
        matching: find.byType(ColoredBox),
        matchRoot: true,
      ));
      expect(
        box.color,
        _dayTheme.color(TelegramColorKey.chat_emojiPanelShadowLine),
      );

      await tester.pumpWidget(_host(
        EmojiCategoryStrip(icons: _icons(3), showShadowLine: false),
      ));
      expect(find.byKey(EmojiCategoryStrip.shadowKey), findsNothing);
    });
  });

  group('search row layout', () {
    testWidgets('50dp row; 36dp r18 box at margins (10, 6, 10); 36x36 icon '
        'slots; 16dp hint (EV:796-1010)', (tester) async {
      await tester.pumpWidget(_host(EmojiSearchRow(
        glass: false,
        leading: ColoredBox(key: _iconKey(0), color: const Color(0xFF000000)),
        trailing: ColoredBox(key: _iconKey(1), color: const Color(0xFF000000)),
      )));

      expect(
        tester.getSize(find.byType(EmojiSearchRow)),
        const Size(400, 50),
      );
      final Rect box = tester.getRect(find.byKey(EmojiSearchRow.boxKey));
      expect(box, const Rect.fromLTWH(10, 6, 380, 36));

      final DecoratedBox decorated =
          tester.widget<DecoratedBox>(find.byKey(EmojiSearchRow.boxKey));
      final BoxDecoration decoration =
          decorated.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(18));
      expect(
        decoration.color,
        _dayTheme.color(TelegramColorKey.chat_emojiSearchBackground),
      );

      // 36x36 slots at the box edges (EV:845-868, 937-963); the icon child
      // is an unconstrained slot, so measure its enclosing 36x36 box.
      Rect slotRect(Key key) => tester.getRect(
            find
                .ancestor(
                  of: find.byKey(key),
                  matching: find.byWidgetPredicate(
                    (Widget w) =>
                        w is SizedBox && w.width == 36.0 && w.height == 36.0,
                  ),
                )
                .first,
          );
      expect(slotRect(_iconKey(0)), const Rect.fromLTWH(10, 6, 36, 36));
      expect(
        slotRect(_iconKey(1)),
        const Rect.fromLTWH(400 - 10 - 36, 6, 36, 36),
      );

      final Text hint = tester.widget<Text>(find.text('Search'));
      expect(hint.style!.fontSize, 16.0);
      expect(
        hint.style!.color,
        _dayTheme.color(TelegramColorKey.chat_emojiSearchIcon),
      );
    });

    testWidgets('sticker-type box top margin is 8dp (EV:815)', (tester) async {
      await tester.pumpWidget(_host(const EmojiSearchRow(stickerType: true)));
      expect(
        tester.getRect(find.byKey(EmojiSearchRow.boxKey)).top,
        8.0,
      );
    });

    testWidgets('glass fills: box glass_defaultIcon@6%, hint @45% '
        '(EV:811-819, 870-901)', (tester) async {
      await tester.pumpWidget(_host(const EmojiSearchRow()));
      final int glassIcon =
          _dayTheme.color(TelegramColorKey.glass_defaultIcon).toARGB32();
      final BoxDecoration decoration = (tester
              .widget<DecoratedBox>(find.byKey(EmojiSearchRow.boxKey))
              .decoration) as BoxDecoration;
      expect(decoration.color!.toARGB32(), multAlpha(glassIcon, 0.06));
      final Text hint = tester.widget<Text>(find.text('Search'));
      expect(hint.style!.color!.toARGB32(), multAlpha(glassIcon, 0.45));
    });

    testWidgets('background + shadow line only when drawBackground '
        '(EV:800-809); input slot replaces the hint', (tester) async {
      final Color bg =
          _dayTheme.color(TelegramColorKey.chat_emojiPanelBackground);
      await tester.pumpWidget(_host(const EmojiSearchRow()));
      expect(
        find.byWidgetPredicate((Widget w) => w is ColoredBox && w.color == bg),
        findsOneWidget,
      );

      await tester.pumpWidget(_host(EmojiSearchRow(
        drawBackground: false,
        input: ColoredBox(key: _iconKey(9), color: const Color(0xFF00FF00)),
      )));
      expect(
        find.byWidgetPredicate((Widget w) => w is ColoredBox && w.color == bg),
        findsNothing,
      );
      expect(find.text('Search'), findsNothing);
      expect(find.byKey(_iconKey(9)), findsOneWidget);
    });
  });

  group('trending header', () {
    testWidgets('27dp row, 15dp bold title at margins (15, 5, 25), dot r3 '
        '(SSNC:234, 79, 88-89; EV:6512-6515)', (tester) async {
      await tester.pumpWidget(_host(const EmojiTrendingHeader(
        title: 'Trending',
        glass: false,
        showUnreadDot: true,
      )));
      expect(
        tester.getSize(find.byType(EmojiTrendingHeader)),
        const Size(400, 27),
      );
      final Rect title = tester.getRect(find.text('Trending'));
      expect(title.left, 15.0);

      final Text text = tester.widget<Text>(find.text('Trending'));
      expect(text.style!.fontSize, 15.0);
      expect(text.style!.fontFamily, 'packages/telegram_ui/RobotoMedium');
      expect(
        text.style!.color,
        _dayTheme.color(TelegramColorKey.chat_emojiPanelStickerSetName),
      );

      final Rect dot = tester.getRect(find.byKey(EmojiTrendingHeader.dotKey));
      expect(dot.size, const Size(6, 6));
      final DecoratedBox dotBox =
          tester.widget<DecoratedBox>(find.byKey(EmojiTrendingHeader.dotKey));
      expect(
        (dotBox.decoration as BoxDecoration).color,
        _dayTheme.color(TelegramColorKey.chat_emojiPanelNewTrending),
      );
    });

    testWidgets('emoji variant margins (5, 15) and the glass @60% title '
        '(SSNC:77, 88-89)', (tester) async {
      await tester.pumpWidget(_host(const EmojiTrendingHeader(
        title: 'Recently used',
        emojiVariant: true,
      )));
      expect(tester.getRect(find.text('Recently used')).left, 5.0);
      final Text text = tester.widget<Text>(find.text('Recently used'));
      expect(
        text.style!.color!.toARGB32(),
        multAlpha(
          _dayTheme.color(TelegramColorKey.glass_defaultIcon).toARGB32(),
          0.6,
        ),
      );
    });
  });

  group('color keys light/dark', () {
    testWidgets('panel background is chat_emojiPanelBackground per theme '
        '(EV:807, 1752)', (tester) async {
      Color panelBg(WidgetTester tester) => tester
          .widget<ColoredBox>(find
              .descendant(
                of: find.byType(EmojiPanel),
                matching: find.byType(ColoredBox),
              )
              .first)
          .color;

      await tester.pumpWidget(_host(EmojiPanel(tabIcons: _icons(3))));
      final Color day = panelBg(tester);
      expect(day, _dayTheme.color(TelegramColorKey.chat_emojiPanelBackground));

      await tester.pumpWidget(
        _host(EmojiPanel(tabIcons: _icons(3)), theme: _nightTheme),
      );
      final Color night = panelBg(tester);
      expect(
        night,
        _nightTheme.color(TelegramColorKey.chat_emojiPanelBackground),
      );
      expect(day, isNot(night));
    });

    testWidgets('indicator follows chat_emojiPanelIconSelected per theme',
        (tester) async {
      await tester.pumpWidget(_host(EmojiPanelTabStrip(icons: _icons(3))));
      final Color day = _indicatorPainterOf(tester).color;
      expect(
        day.toARGB32(),
        _dayTheme
            .color(TelegramColorKey.chat_emojiPanelIconSelected)
            .withAlpha(20)
            .toARGB32(),
      );

      await tester.pumpWidget(
        _host(EmojiPanelTabStrip(icons: _icons(3)), theme: _nightTheme),
      );
      final Color night = _indicatorPainterOf(tester).color;
      expect(
        night.toARGB32(),
        _nightTheme
            .color(TelegramColorKey.chat_emojiPanelIconSelected)
            .withAlpha(20)
            .toARGB32(),
      );
      expect(day, isNot(night));
    });

    testWidgets('explicit resources override wins over the ambient theme',
        (tester) async {
      const TelegramResources resources = _FixedResources(<int, Color>{
        TelegramColorKey.chat_emojiPanelIconSelected: Color(0xFF112233),
        TelegramColorKey.chat_emojiBottomPanelIcon: Color(0xFF445566),
      });
      await tester.pumpWidget(_host(EmojiPanelTabStrip(
        icons: _icons(3),
        glass: false,
        resources: resources,
      )));
      expect(
        _indicatorPainterOf(tester).color.toARGB32(),
        const Color(0xFF112233).withAlpha(20).toARGB32(),
      );
      final ColorFilter unselected = tester
          .widget<ColorFiltered>(
            find
                .ancestor(
                  of: find.byKey(_iconKey(2)),
                  matching: find.byType(ColorFiltered),
                )
                .first,
          )
          .colorFilter;
      expect(
        unselected,
        const ColorFilter.mode(Color(0xFF445566), BlendMode.srcIn),
      );
    });
  });
}
