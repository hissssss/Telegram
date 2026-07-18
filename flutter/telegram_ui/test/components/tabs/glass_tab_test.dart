// Ring-1 widget tests for GlassTab + TabIcon
// (port of `ui/Components/glass/GlassTabView.java`):
//
// - label typeface flips RobotoMedium -> RobotoExtraBold the moment the tab
//   is selected (GlassTabView.java:237), while colors keep animating;
// - selection pill values at t = 0 / 0.5 / 1 of the 320ms DECELERATE
//   animator (GlassTabView.java:67, 152-165): scale lerp(0.6 -> 1, factor),
//   fill multAlpha(glass_tabSelected, 0.09 * DECELERATE(factor));
// - icon slot geometry: 24x24 top 4 centered (line 406); avatar variant
//   22x22 top 5 radius 11 (lines 424-427); label top 28.33 (line 96);
// - color key wiring (glass_tabUnselected / glass_tabSelected /
//   glass_tabSelectedText) through TelegramTheme.colorOf in light AND dark
//   themes, plus the explicit `resources` override path;
// - the TabIcon.animated playback contract: forward on select, reverse on
//   deselect, frame segments (GlassTabView.java:280-398).
//
// No glass shaders are involved: the tab is a plain widget, so no
// GlassSettings tier forcing is needed here.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/tabs/glass_tab.dart';
import 'package:telegram_ui/src/components/tabs/tab_icon.dart';
import 'package:telegram_ui/src/foundation/color_math.dart';
import 'package:telegram_ui/src/theme/telegram_resources.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Hosts a tab in a bar-cell-sized box (72x56) under an ambient theme.
Widget _host(TelegramThemeData theme, Widget tab) {
  return TelegramTheme(
    data: theme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(width: 72, height: 56, child: tab),
      ),
    ),
  );
}

GlassTabPillPainter _pill(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (Widget w) => w is CustomPaint && w.painter is GlassTabPillPainter,
    ),
  );
  return paint.painter! as GlassTabPillPainter;
}

/// Fixed-palette resources for exact-int pill expectations.
class _FixedResources extends TelegramResources {
  const _FixedResources(this.colors);

  final Map<int, Color> colors;

  @override
  Color getColor(int key) => colors[key] ?? const Color(0xFF000000);
}

/// Records every [TabAnimationController] call the tab/icon makes.
class _RecordingController extends TabAnimationController {
  _RecordingController({this.frames = 60});

  final int frames;
  int current = 0;
  final List<String> log = <String>[];

  @override
  int get frameCount => frames;

  @override
  int get currentFrame => current;

  @override
  void setFrame(int frame) {
    current = frame;
    log.add('frame:$frame');
  }

  @override
  void setEndFrame(int frame) => log.add('end:$frame');

  @override
  void setPlayTowardEndFrame(bool enabled) => log.add('toward:$enabled');

  @override
  void play() => log.add('play');
}

void main() {
  const int unselectedKey = TelegramColorKey.glass_tabUnselected;
  const int selectedKey = TelegramColorKey.glass_tabSelected;
  const int selectedTextKey = TelegramColorKey.glass_tabSelectedText;

  GlassTab tab({bool selected = false, TelegramResources? resources}) {
    return GlassTab(
      label: 'Chats',
      icon: const TabIcon.static(child: SizedBox()),
      selected: selected,
      resources: resources,
    );
  }

  group('label typeface', () {
    testWidgets('switches family instantly on selection', (tester) async {
      final TelegramThemeData theme = TelegramThemeData.day();
      await tester.pumpWidget(_host(theme, tab()));

      Text text = tester.widget<Text>(find.text('Chats'));
      expect(text.style!.fontFamily, 'packages/telegram_ui/RobotoMedium');
      expect(text.style!.fontWeight, FontWeight.w500);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.style!.fontSize, 12.0);

      await tester.pumpWidget(_host(theme, tab(selected: true)));
      // The typeface flips on the boolean, before the 320ms color/pill
      // animation finishes (GlassTabView.java:237).
      text = tester.widget<Text>(find.text('Chats'));
      expect(text.style!.fontFamily, 'packages/telegram_ui/RobotoExtraBold');
      expect(text.style!.fontWeight, FontWeight.w800);
      await tester.pumpAndSettle();

      // And back.
      await tester.pumpWidget(_host(theme, tab()));
      text = tester.widget<Text>(find.text('Chats'));
      expect(text.style!.fontFamily, 'packages/telegram_ui/RobotoMedium');
      expect(text.style!.fontWeight, FontWeight.w500);
      await tester.pumpAndSettle();
    });
  });

  group('selection pill', () {
    // Exact-int expectations against a known opaque selected color.
    const Color selectedColor = Color(0xFF1A91E6);
    const TelegramResources resources = _FixedResources(<int, Color>{
      unselectedKey: Color(0xFF1A1D21),
      selectedKey: selectedColor,
      selectedTextKey: Color(0xFF0D7FCF),
    });

    testWidgets('scale and alpha at t = 0 / 0.5 / 1', (tester) async {
      final TelegramThemeData theme = TelegramThemeData.day();
      await tester.pumpWidget(_host(theme, tab(resources: resources)));

      GlassTabPillPainter pill = _pill(tester);
      expect(pill.factor, 0.0);
      expect(pill.pillScale, 0.6); // lerp(0.6, 1, 0)
      expect(pill.pillColor.toARGB32() >>> 24, 0); // multAlpha(c, 0)

      await tester.pumpWidget(
        _host(theme, tab(selected: true, resources: resources)),
      );
      await tester.pump(); // first ticker tick: elapsed 0 -> t = 0
      pill = _pill(tester);
      expect(pill.factor, 0.0);
      expect(pill.pillScale, 0.6);

      await tester.pump(const Duration(milliseconds: 160)); // t = 0.5
      pill = _pill(tester);
      // factor = DECELERATE(0.5) = 1 - 0.5^2 = 0.75 (animator curve,
      // GlassTabView.java:67).
      expect(pill.factor, moreOrLessEquals(0.75, epsilon: 1e-12));
      // scale = lerp(0.6, 1, 0.75) (GlassTabView.java:160).
      expect(pill.pillScale, moreOrLessEquals(0.9, epsilon: 1e-12));
      // alpha = 0.09 * DECELERATE(0.75) = 0.09 * 0.9375; Java truncates:
      // (int) (255 * 0.084375) = 21 (Theme.multAlpha via
      // GlassTabView.java:157).
      expect(
        pill.pillColor.toARGB32(),
        (selectedColor.toARGB32() & 0x00FFFFFF) | (21 << 24),
      );

      await tester.pump(const Duration(milliseconds: 160)); // t = 1
      pill = _pill(tester);
      expect(pill.factor, 1.0);
      expect(pill.pillScale, 1.0);
      // (int) (255 * 0.09) = 22.
      expect(
        pill.pillColor.toARGB32(),
        (selectedColor.toARGB32() & 0x00FFFFFF) | (22 << 24),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('selectionOverride drives the pill but not the colors', (
      tester,
    ) async {
      final TelegramThemeData theme = TelegramThemeData.day();
      await tester.pumpWidget(
        _host(
          theme,
          const GlassTab(
            label: 'Chats',
            icon: TabIcon.static(child: SizedBox()),
            selectionOverride: 1.0,
            resources: resources,
          ),
        ),
      );
      final GlassTabPillPainter pill = _pill(tester);
      expect(pill.factor, 1.0); // gesture override (GlassTabView.java:153)
      final Text text = tester.widget<Text>(find.text('Chats'));
      // updateColors ignores the override (GlassTabView.java:255-256).
      expect(text.style!.color, const Color(0xFF1A1D21));
    });

    testWidgets('skipSelectionPill suppresses the painter', (tester) async {
      final TelegramThemeData theme = TelegramThemeData.day();
      await tester.pumpWidget(
        _host(
          theme,
          const GlassTab(
            label: 'Chats',
            icon: TabIcon.static(child: SizedBox()),
            selected: true,
            skipSelectionPill: true,
            resources: resources,
          ),
        ),
      );
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is CustomPaint && w.painter is GlassTabPillPainter,
        ),
        findsNothing,
      );
    });
  });

  group('geometry', () {
    testWidgets('icon slot is 24x24 at top 4, centered; label at 28.33', (
      tester,
    ) async {
      const ValueKey<String> glyphKey = ValueKey<String>('glyph');
      await tester.pumpWidget(
        _host(
          TelegramThemeData.day(),
          const GlassTab(
            label: 'Chats',
            icon: TabIcon.static(child: SizedBox(key: glyphKey)),
          ),
        ),
      );

      final Rect tabRect = tester.getRect(find.byType(GlassTab));
      final Rect glyph = tester.getRect(find.byKey(glyphKey));
      expect(glyph.width, 24.0); // GlassTabView.java:406
      expect(glyph.height, 24.0);
      expect(glyph.top - tabRect.top, 4.0);
      expect(glyph.center.dx, moreOrLessEquals(tabRect.center.dx));

      final Rect label = tester.getRect(find.text('Chats'));
      expect(label.top - tabRect.top, moreOrLessEquals(28.33)); // line 96
      expect(label.width, tabRect.width); // match-parent, centered
    });

    testWidgets('avatar variant is 22x22 at top 5 with radius 11', (
      tester,
    ) async {
      const ValueKey<String> avatarKey = ValueKey<String>('avatar');
      await tester.pumpWidget(
        _host(
          TelegramThemeData.day(),
          const GlassTab.avatar(
            label: 'Profile',
            avatar: SizedBox(key: avatarKey),
          ),
        ),
      );

      final Rect tabRect = tester.getRect(find.byType(GlassTab));
      final Rect avatar = tester.getRect(find.byKey(avatarKey));
      expect(avatar.width, 22.0); // GlassTabView.java:427
      expect(avatar.height, 22.0);
      expect(avatar.top - tabRect.top, 5.0);
      expect(avatar.center.dx, moreOrLessEquals(tabRect.center.dx));

      final ClipRRect clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(clip.borderRadius, BorderRadius.circular(11.0)); // line 424

      // The avatar keeps its own colors: no SRC_IN tint filter
      // (needUpdateBackupViewColor stays false, GlassTabView.java:259-263).
      expect(find.byType(ColorFiltered), findsNothing);
    });

    testWidgets('visualWidth shifts content and widens the pill', (
      tester,
    ) async {
      const ValueKey<String> glyphKey = ValueKey<String>('glyph');
      await tester.pumpWidget(
        _host(
          TelegramThemeData.day(),
          const GlassTab(
            label: 'Chats',
            icon: TabIcon.static(child: SizedBox(key: glyphKey)),
            visualWidth: 100.0,
          ),
        ),
      );
      final Rect tabRect = tester.getRect(find.byType(GlassTab));
      final Rect glyph = tester.getRect(find.byKey(glyphKey));
      // offset = (visualWidth - width) / 2 = (100 - 72) / 2 = 14
      // (GlassTabView.java:125-127).
      expect(
        glyph.center.dx,
        moreOrLessEquals(tabRect.center.dx + 14.0),
      );
      expect(_pill(tester).visualWidth, 100.0);
    });
  });

  group('color key wiring', () {
    for (final (String name, TelegramThemeData Function() make) in <(
      String,
      TelegramThemeData Function(),
    )>[
      ('day', TelegramThemeData.day),
      ('night', TelegramThemeData.night),
    ]) {
      testWidgets('$name theme resolves glass_tab* keys', (tester) async {
        final TelegramThemeData theme = make();
        final Color unselected = theme.color(unselectedKey);
        final Color selected = theme.color(selectedKey);
        final Color selectedText = theme.color(selectedTextKey);

        // Unselected: icon tint and label both glass_tabUnselected
        // (blendARGB at factor 0, GlassTabView.java:255-256).
        await tester.pumpWidget(_host(theme, tab()));
        Text text = tester.widget<Text>(find.text('Chats'));
        expect(text.style!.color, unselected);
        ColorFiltered filtered = tester.widget<ColorFiltered>(
          find.byType(ColorFiltered),
        );
        expect(
          filtered.colorFilter,
          ColorFilter.mode(unselected, BlendMode.srcIn),
        );

        // Selected (settled): icon -> glass_tabSelected, label ->
        // glass_tabSelectedText, pill fill from glass_tabSelected.
        await tester.pumpWidget(_host(theme, tab(selected: true)));
        await tester.pumpAndSettle();
        text = tester.widget<Text>(find.text('Chats'));
        expect(text.style!.color, selectedText);
        filtered = tester.widget<ColorFiltered>(find.byType(ColorFiltered));
        expect(
          filtered.colorFilter,
          ColorFilter.mode(selected, BlendMode.srcIn),
        );
        expect(_pill(tester).color, selected);
      });
    }

    testWidgets('mid-animation colors are blendARGB of the endpoints', (
      tester,
    ) async {
      final TelegramThemeData theme = TelegramThemeData.day();
      final Color unselected = theme.color(unselectedKey);
      final Color selected = theme.color(selectedKey);
      final Color selectedText = theme.color(selectedTextKey);

      await tester.pumpWidget(_host(theme, tab()));
      await tester.pumpWidget(_host(theme, tab(selected: true)));
      await tester.pump(); // t = 0
      await tester.pump(const Duration(milliseconds: 160)); // t = 0.5

      // factor = DECELERATE(0.5) = 0.75.
      final Text text = tester.widget<Text>(find.text('Chats'));
      expect(text.style!.color, blendArgb(unselected, selectedText, 0.75));
      final ColorFiltered filtered = tester.widget<ColorFiltered>(
        find.byType(ColorFiltered),
      );
      expect(
        filtered.colorFilter,
        ColorFilter.mode(blendArgb(unselected, selected, 0.75), BlendMode.srcIn),
      );
      await tester.pumpAndSettle();
    });

    test('blendArgb matches androidx ColorUtils.blendARGB truncation', () {
      // (int) truncation per channel, not rounding.
      expect(
        blendArgb(const Color(0xFF000000), const Color(0xFFFFFFFF), 0.5),
        const Color(0xFF7F7F7F), // (int) 127.5 = 127
      );
      expect(
        blendArgb(const Color(0xFF1A1D21), const Color(0xFF1A91E6), 0.0),
        const Color(0xFF1A1D21),
      );
      expect(
        blendArgb(const Color(0xFF1A1D21), const Color(0xFF1A91E6), 1.0),
        const Color(0xFF1A91E6),
      );
    });

    test('multAlpha truncates like Theme.multAlpha', () {
      // 0.09 * 255 = 22.95 -> 22 (GlassTabView.java:157 at full factor).
      expect(multAlpha(0xFF1A91E6, 0.09) >>> 24, 22);
    });
  });

  group('TabIcon.animated contract', () {
    test('full-range: forward on select, reverse on deselect', () {
      final _RecordingController c = _RecordingController(frames: 60);
      final TabIcon icon = TabIcon.animated(
        controller: c,
        child: const SizedBox(),
      );

      // GlassTabView.java:387-390.
      icon.applySelection(selected: true, animated: true);
      expect(c.log, <String>['toward:false', 'frame:0', 'end:60', 'play']);

      // GlassTabView.java:391-395.
      c.log.clear();
      icon.applySelection(selected: false, animated: true);
      expect(c.log, <String>['toward:true', 'frame:60', 'end:0', 'play']);

      // Unanimated bind snaps to the terminal frame.
      c.log.clear();
      icon.applySelection(selected: true, animated: false);
      expect(c.log, <String>['toward:false', 'end:60', 'frame:60']);
      c.log.clear();
      icon.applySelection(selected: false, animated: false);
      expect(c.log, <String>['toward:true', 'end:0', 'frame:0']);
    });

    test('frame segment protocol (BOOSTS mid 25 end 49)', () {
      final _RecordingController c = _RecordingController(frames: 49);
      final TabIcon icon = TabIcon.animated(
        controller: c,
        child: const SizedBox(),
        frameSegment: TabFrameSegment.boosts,
      );

      // Initial deselected bind at frame 0: current < mid - 1 -> snap to
      // start (GlassTabView.java:350-353).
      icon.applySelection(selected: false, animated: false);
      expect(c.log, <String>['end:0', 'frame:0']);

      // Select from frame 0: play 0..25 (GlassTabView.java:336-343).
      c.log.clear();
      icon.applySelection(selected: true, animated: true);
      expect(c.log, <String>['end:25', 'play']);

      // Deselect from the held mid frame: play 25..48
      // (GlassTabView.java:347-349).
      c.log.clear();
      c.current = 25;
      icon.applySelection(selected: false, animated: true);
      expect(c.log, <String>['end:48', 'play']);

      // Re-select after the deselect segment finished (current >= end - 2):
      // rewind to start, then play (GlassTabView.java:337-343).
      c.log.clear();
      c.current = 48;
      icon.applySelection(selected: true, animated: true);
      expect(c.log, <String>['end:25', 'frame:0', 'play']);

      // Select while already past mid (mid < current < end - 2): snap to the
      // mid frame (GlassTabView.java:341-345).
      c.log.clear();
      c.current = 30;
      icon.applySelection(selected: true, animated: true);
      expect(c.log, <String>['end:25', 'frame:25']);
    });

    testWidgets('GlassTab drives the controller on selection changes', (
      tester,
    ) async {
      final TelegramThemeData theme = TelegramThemeData.day();
      final _RecordingController c = _RecordingController(frames: 60);

      GlassTab animatedTab({required bool selected}) => GlassTab(
        label: 'Chats',
        icon: TabIcon.animated(controller: c, child: const SizedBox()),
        selected: selected,
      );

      // Initial bind is unanimated (GlassTabView.java:405).
      await tester.pumpWidget(_host(theme, animatedTab(selected: false)));
      expect(c.log, <String>['toward:true', 'end:0', 'frame:0']);

      // A rebuild with the same controller must NOT rebind.
      c.log.clear();
      await tester.pumpWidget(_host(theme, animatedTab(selected: false)));
      expect(c.log, isEmpty);

      // Selecting plays forward (GlassTabView.java:233-238, 387-390).
      await tester.pumpWidget(_host(theme, animatedTab(selected: true)));
      expect(c.log, <String>['toward:false', 'frame:0', 'end:60', 'play']);
      await tester.pumpAndSettle();

      // Deselecting plays in reverse.
      c.log.clear();
      await tester.pumpWidget(_host(theme, animatedTab(selected: false)));
      expect(c.log, <String>['toward:true', 'frame:60', 'end:0', 'play']);
      await tester.pumpAndSettle();
    });
  });
}
