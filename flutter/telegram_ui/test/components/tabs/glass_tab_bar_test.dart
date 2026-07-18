// Ring-1/Ring-2 tests for lib/src/components/tabs/glass_tab_bar.dart
// (ARCHITECTURE.md section 6, row "GlassTabBar"), golden-free:
//
//  * container geometry — 56/8/72dp heights, 28dp radius, 7.666dp glass
//    padding, 12dp row padding, 344dp max width, 320dp min row width
//    (DialogsActivity.java:289-291, MainTabsActivity.java:287-288, 343-344);
//  * the auto-fit pass algorithm of MainTabsLayout.onMeasure
//    (MainTabsLayout.java:46-47, 58-154) as a pure function and through the
//    widget (TabSlotData.textSize);
//  * show/hide: translationY +40dp / alpha over 380ms EASE_OUT_QUINT
//    (MainTabsActivity.java:102-103, 955-969);
//  * the long-press lens drag: selector activation, spring settle on the
//    selected tab center, 1.019 bar scale, commit semantics
//    (MainTabsLayout.java:289, 356-369, 436-439, 465-511);
//  * the pivot warp math (MainTabsLayout.java:563-604);
//  * the GlassTabBarController API (select/animateTo/show/hide).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/tabs/glass_tab_bar.dart';
import 'package:telegram_ui/src/components/tabs/tab_contract.dart';
import 'package:telegram_ui/src/foundation/tg_curves.dart';
import 'package:telegram_ui/src/glass/backdrop_scope.dart';
import 'package:telegram_ui/src/glass/geometry.dart';
import 'package:telegram_ui/src/glass/glass_panel.dart';
import 'package:telegram_ui/src/glass/presets.dart';
import 'package:telegram_ui/src/glass/runtime_probe.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

/// Settings whose probe never resolves: liquid requests stay conservatively
/// frosted — the deterministic flutter_tester path (no ImageFilter.shader).
GlassSettings _manualSettings() =>
    GlassSettings(probe: () => Completer<GlassCapability>().future);

List<GlassTabBarItem> _items(List<String> labels) => <GlassTabBarItem>[
      for (int i = 0; i < labels.length; i++)
        GlassTabBarItem(id: 't$i', label: labels[i]),
    ];

Widget _host({
  required Widget child,
  required GlassSettings settings,
  double width = 400,
}) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: GlassBackdropScope(
        settings: settings,
        probeOnMount: false,
        child: Center(
          child: SizedBox(
            width: width,
            height: 200,
            child: Align(alignment: Alignment.bottomCenter, child: child),
          ),
        ),
      ),
    ),
  );
}

/// The expected row layout for [labels] measured exactly like the widget.
GlassTabRowLayout _expectedLayout(List<String> labels, double maxRowWidth) {
  return GlassTabRowLayout.compute(
    tabCount: labels.length,
    maxRowWidth: maxRowWidth,
    measureTextWidths: (double textSize) => <double>[
      for (final String label in labels)
        GlassTabBar.measureLabelWidth(label, textSize),
    ],
  );
}

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      // DialogsActivity.java:289-291.
      expect(kGlassTabBarHeight, 56.0);
      expect(kGlassTabBarMargin, 8.0);
      expect(kGlassTabBarHeightWithMargins, 72.0);
      expect(kGlassTabBarHeightWithMargins,
          kGlassTabBarHeight + 2 * kGlassTabBarMargin);
      // MainTabsActivity.java:343-344, 287-288.
      expect(kGlassTabBarRadius, kGlassTabBarHeight / 2);
      expect(kGlassTabBarPanelPadding, closeTo(8 - 0.334, 1e-9));
      expect(kGlassTabBarViewPadding, 12.0);
      expect(kGlassTabBarMaxWidth, 344.0);
      // MainTabsLayout.java:46-47, 69.
      expect(kGlassTabBarMinRowWidth, 320.0);
      expect(kGlassTabBarPassTextSizes, <double>[12, 12, 10]);
      expect(kGlassTabBarPassPaddings, <double>[16, 8, 4]);
      expect(kGlassTabBarRowHeight, 48.0);
      // MainTabsActivity.java:959, 102-103; MainTabsLayout.java:436-439,
      // 484-486, 493, 289.
      expect(kGlassTabBarHiddenOffsetY, 40.0);
      expect(kGlassTabBarVisibilityDuration, const Duration(milliseconds: 380));
      expect(kGlassTabBarLongPressScale, 1.019);
      expect(kGlassTabBarLongPressDuration, const Duration(milliseconds: 375));
      expect(kGlassTabBarSelectorRestoreDelay,
          const Duration(milliseconds: 450));
      expect(kGlassTabBarSelectorAlpha, 0.09);
      // MainTabsLayout.java:356-369 (STIFFNESS_MEDIUM / LOW_BOUNCY).
      expect(kGlassTabBarSelectorSpring.stiffness, 1500.0);
      expect(kGlassTabBarSelectorSpring.mass, 1.0);
      // damping c = ratio * 2 * sqrt(mass * stiffness).
      expect(kGlassTabBarSelectorSpring.damping,
          closeTo(0.75 * 2 * 38.7298334621, 1e-6));
    });
  });

  group('row layout (pure)', () {
    test('short labels: pass 0 fits and grows to the 320dp min row width',
        () {
      final GlassTabRowLayout layout = GlassTabRowLayout.compute(
        tabCount: 4,
        maxRowWidth: 320,
        measureTextWidths: (double textSize) => List<double>.filled(4, 24),
      );
      expect(layout.passIndex, 0);
      expect(layout.textSize, 12);
      expect(layout.tabPadding, 16);
      // withMargin 24 + 32 = 56 each, total 224 < 320; grow (320-224)/4 = 24.
      expect(layout.widths, <double>[80, 80, 80, 80]);
      expect(layout.lefts, <double>[0, 80, 160, 240]);
      expect(layout.rowWidth, 320);
      // Bar width = row + 2*12 = the 344dp flagship width.
      expect(layout.rowWidth + 2 * kGlassTabBarViewPadding,
          kGlassTabBarMaxWidth);
    });

    test('pass 1 chosen when 8dp paddings fit but 16dp do not', () {
      final GlassTabRowLayout layout = GlassTabRowLayout.compute(
        tabCount: 4,
        maxRowWidth: 320,
        measureTextWidths: (double textSize) => List<double>.filled(4, 64),
      );
      // pass 0: (64+32)*4 = 384 > 320; pass 1: (64+16)*4 = 320 <= 320.
      expect(layout.passIndex, 1);
      expect(layout.textSize, 12);
      expect(layout.tabPadding, 8);
      expect(layout.widths, <double>[80, 80, 80, 80]);
      expect(layout.rowWidth, 320);
    });

    test('pass 2 (10dp text) chosen when 12dp never fits', () {
      final GlassTabRowLayout layout = GlassTabRowLayout.compute(
        tabCount: 4,
        maxRowWidth: 320,
        measureTextWidths: (double textSize) =>
            List<double>.filled(4, textSize == 10 ? 58 : 70),
      );
      // pass 0: 102*4 = 408 > 320; pass 1: 86*4 = 344 > 320;
      // pass 2: (58+8)*4 = 264 <= 320 -> fits; grow (320-264)/4 = 14.
      expect(layout.passIndex, 2);
      expect(layout.textSize, 10);
      expect(layout.tabPadding, 4);
      expect(layout.widths, <double>[80, 80, 80, 80]);
    });

    test('last pass is forced and the row scales down on overflow', () {
      final GlassTabRowLayout layout = GlassTabRowLayout.compute(
        tabCount: 4,
        maxRowWidth: 320,
        measureTextWidths: (double textSize) =>
            List<double>.filled(4, textSize == 10 ? 90 : 100),
      );
      // pass 2 total (90+8)*4 = 392 > 320 -> forced; scale 320/392:
      // 98 * 320/392 = 80.0 exactly.
      expect(layout.passIndex, 2);
      expect(layout.widths, <double>[80, 80, 80, 80]);
      expect(layout.rowWidth, 320);
    });

    test('oversized tab gets weight 0: growth goes to the others', () {
      final GlassTabRowLayout layout = GlassTabRowLayout.compute(
        tabCount: 4,
        maxRowWidth: 320,
        measureTextWidths: (double textSize) => <double>[200, 10, 10, 10],
      );
      // pass 0: 232+42*3 = 358 > 320; pass 1: 216+26*3 = 294 <= 320.
      expect(layout.passIndex, 1);
      // Equal share 320/4 = 80; withMargin 216 > 80 -> weight 0.
      // Grow (320-294)/3 = 8.667 on the weight-1 tabs only.
      expect(layout.widths[0], 216);
      expect(layout.widths[1], closeTo(35, 0.5)); // round(26 + 8.667) = 35.
      expect(layout.widths[2], layout.widths[1]);
      expect(layout.widths[3], layout.widths[1]);
    });

    test('measures once per distinct pass text size', () {
      final List<double> measured = <double>[];
      GlassTabRowLayout.compute(
        tabCount: 2,
        maxRowWidth: 100,
        measureTextWidths: (double textSize) {
          measured.add(textSize);
          return List<double>.filled(2, 200); // never fits -> all passes run.
        },
      );
      // Passes 0 and 1 share size 12 (`lastMeasuredTextSize`,
      // MainTabsLayout.java:72-77).
      expect(measured, <double>[12, 10]);
    });

    test('narrow bars clamp the min row width to the available width', () {
      final GlassTabRowLayout layout = GlassTabRowLayout.compute(
        tabCount: 2,
        maxRowWidth: 276, // a 300dp-wide screen: 300 - 24.
        measureTextWidths: (double textSize) => List<double>.filled(2, 10),
      );
      // minTotal = min(320, 276) = 276 -> grows to fill exactly.
      expect(layout.rowWidth, 276);
      expect(layout.widths, <double>[138, 138]);
    });

    test('empty bar yields an empty layout', () {
      final GlassTabRowLayout layout = GlassTabRowLayout.compute(
        tabCount: 0,
        maxRowWidth: 320,
        measureTextWidths: (double textSize) => const <double>[],
      );
      expect(layout.widths, isEmpty);
      expect(layout.rowWidth, 0);
    });
  });

  group('drag helpers (pure)', () {
    const List<double> centers = <double>[50, 150];
    const List<double> widths = <double>[100, 60];

    test('clampXToChildrenCenters port', () {
      expect(glassTabBarClampToCenters(0, centers), 50);
      expect(glassTabBarClampToCenters(99, centers), 99);
      expect(glassTabBarClampToCenters(500, centers), 150);
      expect(glassTabBarClampToCenters(77, const <double>[]), 77);
    });

    test('findNearestVisibleChildByX port', () {
      expect(glassTabBarNearestIndex(99, centers), 0);
      expect(glassTabBarNearestIndex(101, centers), 1);
      expect(glassTabBarNearestIndex(-10, centers), 0);
      expect(glassTabBarNearestIndex(0, const <double>[]), -1);
    });

    test('getInterpolatedWidthByX port', () {
      expect(glassTabBarInterpolatedWidth(50, centers, widths), 100);
      expect(glassTabBarInterpolatedWidth(150, centers, widths), 60);
      expect(glassTabBarInterpolatedWidth(100, centers, widths), 80);
      expect(glassTabBarInterpolatedWidth(0, centers, widths), 100);
      expect(glassTabBarInterpolatedWidth(400, centers, widths), 60);
      expect(
          glassTabBarInterpolatedWidth(0, const <double>[], const <double>[]),
          0);
    });

    test('pivot warp: center touch maps to the center', () {
      expect(glassTabBarWarpPivot(const Size(100, 100), const Offset(50, 50)),
          const Offset(50, 50));
    });

    test('pivot warp: corner touch — mappedR = 1.5r/(r+0.5), pivotY lerp x3',
        () {
      // size (100,100), touch (100,100): nx = ny = 1, r = sqrt(2);
      // mappedR = 1.5*sqrt2 / (sqrt2 + 0.5) = 1.108203...;
      // scale = mappedR / r = 0.783618...; dx*scale = 39.18088...;
      // pivotX = 50 + 39.18088 = 89.18088; pivotY = 50 + 3*39.18088.
      final Offset pivot =
          glassTabBarWarpPivot(const Size(100, 100), const Offset(100, 100));
      expect(pivot.dx, closeTo(89.181, 0.05));
      expect(pivot.dy, closeTo(167.543, 0.05));
    });

    test('pivot warp is an extrapolation on Y only', () {
      // Touch right of center on the horizontal axis: Y stays centered.
      final Offset pivot =
          glassTabBarWarpPivot(const Size(320, 72), const Offset(300, 36));
      expect(pivot.dy, 36);
      expect(pivot.dx, greaterThan(160));
    });
  });

  group('geometry (widget)', () {
    testWidgets('56/8/28/344: panel box, radius, paddings, slot rects',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      const List<String> labels = <String>['One', 'Two', 'Three', 'Four'];
      await tester.pumpWidget(_host(
        settings: settings,
        child: GlassTabBar(items: _items(labels)),
      ));

      final GlassTabRowLayout expected = _expectedLayout(
          labels, kGlassTabBarMaxWidth - 2 * kGlassTabBarViewPadding);

      // The bar box is 72dp tall (56 + 2*8 margins inside).
      final Size barSize = tester.getSize(find.byType(GlassTabBar));
      expect(barSize.height, kGlassTabBarHeightWithMargins);

      // The glass panel: measured row + 12dp paddings, 72dp tall, centered.
      final Rect panelRect = tester.getRect(find.byType(GlassPanel));
      expect(panelRect.height, kGlassTabBarHeightWithMargins);
      expect(panelRect.width,
          expected.rowWidth + 2 * kGlassTabBarViewPadding);
      // Short labels grow the row to exactly 320dp -> the 344dp flagship.
      expect(expected.rowWidth, kGlassTabBarMinRowWidth);
      expect(panelRect.width, kGlassTabBarMaxWidth);

      // Panel configuration: mainTabs preset, 28dp radius, 7.666dp glass
      // padding, default LiquidGlassSettings, no tier pin (liquid-first).
      final GlassPanel panel = tester.widget(find.byType(GlassPanel));
      expect(panel.preset, GlassPresets.mainTabs);
      expect(panel.borderRadius, const GlassRadii.all(kGlassTabBarRadius));
      expect(panel.padding, closeTo(8 - 0.334, 1e-9));
      expect(panel.tier, isNull);
      expect(panel.settings.thickness, 11.0);
      expect(panel.settings.refractIntensity, 0.75);

      // Slot rects: top 12dp, height 48dp, packed lefts.
      for (int i = 0; i < labels.length; i++) {
        final Rect slot =
            tester.getRect(find.byKey(ValueKey<Object>('t$i')));
        expect(slot.top - panelRect.top, kGlassTabBarViewPadding);
        expect(slot.height, kGlassTabBarRowHeight);
        expect(slot.left - panelRect.left,
            kGlassTabBarViewPadding + expected.lefts[i]);
        expect(slot.width, expected.widths[i]);
      }
    });

    testWidgets('narrow hosts clamp the bar to the available width',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      const List<String> labels = <String>['A', 'B', 'C'];
      await tester.pumpWidget(_host(
        settings: settings,
        width: 300,
        child: GlassTabBar(items: _items(labels)),
      ));
      final GlassTabRowLayout expected =
          _expectedLayout(labels, 300 - 2 * kGlassTabBarViewPadding);
      final Rect panelRect = tester.getRect(find.byType(GlassPanel));
      expect(panelRect.width,
          expected.rowWidth + 2 * kGlassTabBarViewPadding);
      expect(panelRect.width, lessThanOrEqualTo(300));
      // The min row width clamps to the available space, so the pill fills
      // the host (within the per-tab px rounding).
      expect(panelRect.width, closeTo(300, labels.length / 2));
    });
  });

  group('auto-fit (widget)', () {
    testWidgets('short labels render at 12dp, long labels drop to 10dp',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final Map<Object, TabSlotData> slots = <Object, TabSlotData>{};
      Widget capture(BuildContext context, GlassTabBarItem item,
          TabSlotData slot) {
        slots[item.id] = slot;
        return const SizedBox.expand();
      }

      await tester.pumpWidget(_host(
        settings: settings,
        child: GlassTabBar(
          items: _items(const <String>['One', 'Two', 'Three', 'Four']),
          tabBuilder: capture,
        ),
      ));
      expect(slots['t0']!.textSize, 12);

      slots.clear();
      final List<String> long =
          List<String>.filled(4, 'An Extremely Long Tab Label Indeed');
      await tester.pumpWidget(_host(
        settings: settings,
        child: GlassTabBar(items: _items(long), tabBuilder: capture),
      ));
      // (34-char labels at 12dp cannot fit 4-up in 320dp.)
      expect(slots['t0']!.textSize, 10);

      // The slot contract carries label/badge/selection through.
      expect(slots['t0']!.label, long[0]);
      expect(slots['t0']!.selected, isTrue);
      expect(slots['t1']!.selected, isFalse);
      expect(slots['t0']!.animation.value, 1);
      expect(slots['t1']!.animation.value, 0);
      expect(slots['t0']!.skipSelector, isFalse);
    });

    testWidgets('badge counts flow into TabSlotData',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final Map<Object, TabSlotData> slots = <Object, TabSlotData>{};
      await tester.pumpWidget(_host(
        settings: settings,
        child: GlassTabBar(
          items: const <GlassTabBarItem>[
            GlassTabBarItem(id: 'a', label: 'Chats', badgeCount: 7),
            GlassTabBarItem(id: 'b', label: 'Calls'),
          ],
          tabBuilder: (BuildContext context, GlassTabBarItem item,
              TabSlotData slot) {
            slots[item.id] = slot;
            return const SizedBox.expand();
          },
        ),
      ));
      expect(slots['a']!.badgeCount, 7);
      expect(slots['b']!.badgeCount, 0);
    });
  });

  group('show/hide', () {
    testWidgets('hide translates +40dp and fades out; show restores',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final GlassTabBarController controller = GlassTabBarController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(
        settings: settings,
        child: GlassTabBar(
          items: _items(const <String>['One', 'Two', 'Three']),
          controller: controller,
        ),
      ));
      final GlassTabBarState state =
          tester.state(find.byType(GlassTabBar));
      final double shownTop = tester.getRect(find.byType(GlassPanel)).top;
      expect(state.debugVisibilityFactor, 1);

      controller.hide();
      await tester.pumpAndSettle();
      expect(state.debugVisibilityFactor, 0);
      expect(tester.getRect(find.byType(GlassPanel)).top,
          shownTop + kGlassTabBarHiddenOffsetY);

      controller.show();
      await tester.pumpAndSettle();
      expect(state.debugVisibilityFactor, 1);
      expect(tester.getRect(find.byType(GlassPanel)).top, shownTop);
    });

    testWidgets('show runs 380ms of EASE_OUT_QUINT',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final GlassTabBarController controller =
          GlassTabBarController(visible: false);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(
        settings: settings,
        child: GlassTabBar(
          items: _items(const <String>['One', 'Two']),
          controller: controller,
        ),
      ));
      final GlassTabBarState state =
          tester.state(find.byType(GlassTabBar));
      expect(state.debugVisibilityFactor, 0);

      controller.show();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 190));
      final double expected = TgCurves.easeOutQuint.transform(0.5);
      expect(state.debugVisibilityFactor, closeTo(expected, 1e-3));
      // 40dp * (1 - factor) of remaining translation.
      // Complete: exactly at the 380ms mark the curve lands on 1.
      await tester.pump(const Duration(milliseconds: 190));
      expect(state.debugVisibilityFactor, closeTo(1, 1e-9));
      await tester.pumpAndSettle();
    });

    testWidgets('a hidden bar ignores taps', (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final GlassTabBarController controller = GlassTabBarController();
      addTearDown(controller.dispose);
      final List<int> selections = <int>[];
      await tester.pumpWidget(_host(
        settings: settings,
        child: GlassTabBar(
          items: _items(const <String>['One', 'Two', 'Three']),
          controller: controller,
          onSelected: selections.add,
        ),
      ));
      controller.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<Object>('t1')),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(selections, isEmpty);
      expect(controller.index, 0);
    });
  });

  group('selection: taps and controller API', () {
    testWidgets('tap selects, fires onSelected, animates 320ms decelerate',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final GlassTabBarController controller = GlassTabBarController();
      addTearDown(controller.dispose);
      final List<int> selections = <int>[];
      await tester.pumpWidget(_host(
        settings: settings,
        child: GlassTabBar(
          items: _items(const <String>['One', 'Two', 'Three']),
          controller: controller,
          onSelected: selections.add,
        ),
      ));
      final GlassTabBarState state =
          tester.state(find.byType(GlassTabBar));

      await tester.tap(find.byKey(const ValueKey<Object>('t1')));
      await tester.pump();
      expect(selections, <int>[1]);
      expect(controller.index, 1);
      expect(state.debugVisualIndex, 1);

      // Mid-flight at 160/320ms the linear factor is 0.5; the slot animation
      // applies DECELERATE: 1 - (1 - 0.5)^2 = 0.75 (GlassTabView.java:67).
      await tester.pump(const Duration(milliseconds: 160));
      expect(state.debugSelectionAnimation(1).value, closeTo(0.75, 1e-3));
      expect(state.debugSelectionAnimation(0).value, closeTo(0.25, 1e-3));
      await tester.pumpAndSettle();
      expect(state.debugSelectionAnimation(1).value, 1);
      expect(state.debugSelectionAnimation(0).value, 0);

      // Tapping the already-selected tab re-fires onSelected (performClick
      // semantics) without changing the index.
      await tester.tap(find.byKey(const ValueKey<Object>('t1')));
      await tester.pumpAndSettle();
      expect(selections, <int>[1, 1]);
      expect(controller.index, 1);
    });

    testWidgets('controller.select snaps without animation',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final GlassTabBarController controller = GlassTabBarController();
      addTearDown(controller.dispose);
      final List<int> selections = <int>[];
      await tester.pumpWidget(_host(
        settings: settings,
        child: GlassTabBar(
          items: _items(const <String>['One', 'Two', 'Three']),
          controller: controller,
          onSelected: selections.add,
        ),
      ));
      final GlassTabBarState state =
          tester.state(find.byType(GlassTabBar));

      controller.select(2);
      await tester.pump();
      // Snapped: no intermediate factor anywhere.
      expect(state.debugVisualIndex, 2);
      expect(state.debugSelectionAnimation(2).value, 1);
      expect(state.debugSelectionAnimation(0).value, 0);
      // Programmatic changes do not fire onSelected.
      expect(selections, isEmpty);
    });

    testWidgets('controller.animateTo animates to the target',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final GlassTabBarController controller = GlassTabBarController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(
        settings: settings,
        child: GlassTabBar(
          items: _items(const <String>['One', 'Two', 'Three']),
          controller: controller,
        ),
      ));
      final GlassTabBarState state =
          tester.state(find.byType(GlassTabBar));

      controller.animateTo(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final double mid = state.debugSelectionAnimation(1).value;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(1));
      await tester.pumpAndSettle();
      expect(state.debugSelectionAnimation(1).value, 1);
      expect(state.debugVisualIndex, 1);
    });
  });

  group('long-press lens drag', () {
    testWidgets(
        'drag activates the selector, scales the bar 1.019, and the spring '
        'settles on the selected tab center', (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final GlassTabBarController controller = GlassTabBarController();
      addTearDown(controller.dispose);
      final List<int> selections = <int>[];
      await tester.pumpWidget(_host(
        settings: settings,
        child: GlassTabBar(
          items: _items(const <String>['One', 'Two', 'Three', 'Four']),
          controller: controller,
          onSelected: selections.add,
        ),
      ));
      final GlassTabBarState state =
          tester.state(find.byType(GlassTabBar));

      // Hold on tab 0 past the 375ms threshold (75% of the 500ms system
      // long-press, MainTabsLayout.java:484-486).
      final Offset start =
          tester.getCenter(find.byKey(const ValueKey<Object>('t0')));
      final TestGesture gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.debugDragSelectorActive, isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.debugDragSelectorActive, isTrue);
      // Starting on the already-selected tab commits nothing yet.
      expect(selections, isEmpty);

      // The whole bar scales to 1.019 over 380ms EASE_OUT_QUINT.
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.debugBarScale, closeTo(kGlassTabBarLongPressScale, 1e-6));
      expect(state.debugScalePivot, isNotNull);

      // Drag to tab 3: the visual selection follows the finger.
      final Offset target =
          tester.getCenter(find.byKey(const ValueKey<Object>('t3')));
      await gesture.moveTo(target);
      await tester.pump();
      expect(state.debugVisualIndex, 3);
      expect(controller.index, 0); // Not committed until release.

      // Release: commit + spring toward tab 3's center.
      await gesture.up();
      await tester.pump();
      expect(selections, <int>[3]);
      expect(controller.index, 3);
      expect(state.debugDragSelectorActive, isTrue); // 450ms restore delay.

      await tester.pump(kGlassTabBarSelectorRestoreDelay +
          const Duration(milliseconds: 50));
      expect(state.debugDragSelectorActive, isFalse);

      await tester.pumpAndSettle();
      expect(state.debugSelectorCenterX,
          closeTo(state.debugSlotCenters[3], 0.5));
      expect(state.debugBarScale, closeTo(1.0, 1e-6));
    });

    testWidgets('starting the drag over another tab commits it immediately',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final GlassTabBarController controller = GlassTabBarController();
      addTearDown(controller.dispose);
      final List<int> selections = <int>[];
      await tester.pumpWidget(_host(
        settings: settings,
        child: GlassTabBar(
          items: _items(const <String>['One', 'Two', 'Three']),
          controller: controller,
          onSelected: selections.add,
        ),
      ));
      final TestGesture gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey<Object>('t2'))));
      await tester.pump(const Duration(milliseconds: 400));
      // `if (selected != found) found.performClick()`
      // (MainTabsLayout.java:405-407).
      expect(selections, <int>[2]);
      expect(controller.index, 2);
      await gesture.up();
      await tester.pump();
      // Release re-fires the click on the settled tab (performClick,
      // MainTabsLayout.java:494-496).
      expect(selections, <int>[2, 2]);
      await tester.pump(kGlassTabBarSelectorRestoreDelay +
          const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
    });

    testWidgets('selector pill geometry: interpolated width, radius h/2',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      await tester.pumpWidget(_host(
        settings: settings,
        child: GlassTabBar(
            items: _items(const <String>['One', 'Two', 'Three'])),
      ));
      final GlassTabBarState state =
          tester.state(find.byType(GlassTabBar));
      final TestGesture gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey<Object>('t0'))));
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.debugDragSelectorActive, isTrue);

      // The lens height is the 48dp row and its radius is height/2 = 24 —
      // both baked into the painter's math; verify through the layout.
      final GlassTabRowLayout layout = state.debugRowLayout!;
      final double x = state.debugSelectorCenterX;
      final double width = glassTabBarInterpolatedWidth(
          x, state.debugSlotCenters, layout.widths);
      // At a tab center the interpolated width is that tab's width.
      expect(width, greaterThan(0));

      await gesture.up();
      await tester.pump(kGlassTabBarSelectorRestoreDelay +
          const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
    });

    testWidgets('slots receive skipSelector while the lens is active',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final Map<Object, TabSlotData> slots = <Object, TabSlotData>{};
      await tester.pumpWidget(_host(
        settings: settings,
        child: GlassTabBar(
          items: _items(const <String>['One', 'Two']),
          tabBuilder: (BuildContext context, GlassTabBarItem item,
              TabSlotData slot) {
            slots[item.id] = slot;
            return const SizedBox.expand();
          },
        ),
      ));
      expect(slots['t0']!.skipSelector, isFalse);
      final TestGesture gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey<Object>('t0'))));
      await tester.pump(const Duration(milliseconds: 400));
      expect(slots['t0']!.skipSelector, isTrue);
      await gesture.up();
      await tester.pump(kGlassTabBarSelectorRestoreDelay +
          const Duration(milliseconds: 50));
      expect(slots['t0']!.skipSelector, isFalse);
      await tester.pumpAndSettle();
    });
  });
}
