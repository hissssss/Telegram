// Tests for lib/src/controls/tg_slide_chooser.dart (PLAN_UIKIT.md S7),
// golden-free:
//
//  * constants vs SlideChooseView.java (74dp height, 6/2/22dp strip metrics,
//    13dp labels at baseline 28, 120/150ms DEFAULT-curve floats);
//  * strip geometry: lineSize / dot centers / touch->index inverse
//    (SlideChooseView.java:143, 217, 227);
//  * option snap on tap and per-stop selection during drags with the
//    selection haptic (SlideChooseView.java:170-183, 200-209);
//  * the drawn selection eases 120ms; the halo follows the press 150ms
//    (SlideChooseView.java:52-53, 222-223, 288-292);
//  * onTouchEnd on release (SlideChooseView.java:189-191);
//  * theme key resolution + resources override; slider semantics.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/controls/tg_slide_chooser.dart';
import 'package:telegram_ui/src/foundation/tg_curves.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

const List<String> _options = <String>['S', 'M', 'L', 'XL'];

Widget _host(Widget child) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.topCenter, child: child),
    ),
  );
}

TgSlideChooserPainter _painter(WidgetTester tester) =>
    tester
        .widget<CustomPaint>(find.descendant(
          of: find.byType(TgSlideChooser),
          matching: find.byType(CustomPaint),
        ))
        .painter! as TgSlideChooserPainter;

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kTgSlideChooserHeight, 74.0); // SlideChooseView.java:213
      expect(kTgSlideChooserDotSize, 6.0); // SlideChooseView.java:214
      expect(kTgSlideChooserGap, 2.0); // SlideChooseView.java:215
      expect(kTgSlideChooserSideInset, 22.0); // SlideChooseView.java:216
      expect(kTgSlideChooserTextSize, 13.0); // SlideChooseView.java:73
      expect(kTgSlideChooserTextBaseline, 28.0); // SlideChooseView.java:276
      expect(kTgSlideChooserTrackCenterOffset, 11.0); // SlideChooseView.java:224
      expect(kTgSlideChooserSelectedDotRadius, 6.0); // SlideChooseView.java:233
      expect(kTgSlideChooserHaloRadius, 12.0); // SlideChooseView.java:290
      expect(kTgSlideChooserHaloAlpha, 80); // SlideChooseView.java:289
      expect(kTgSlideChooserLineHeight, 2.0); // SlideChooseView.java:252
      expect(kTgSlideChooserLineShrink, 3.0); // SlideChooseView.java:250-251
      expect(kTgSlideChooserIndexDuration,
          const Duration(milliseconds: 120)); // SlideChooseView.java:52
      expect(kTgSlideChooserMovingDuration,
          const Duration(milliseconds: 150)); // SlideChooseView.java:53
      expect(kTgSlideChooserCurve, TgCurves.defaultCubic);
      expect(kTgSlideChooserSnapThreshold, 0.35); // SlideChooseView.java:144
    });

    test('strip geometry (SlideChooseView.java:143, 217, 227)', () {
      // width 800, 4 options: lineSize = (800 - 24 - 12 - 44) / 3 = 240.
      expect(TgSlideChooser.lineSizeFor(800, 4), 240.0);
      // Dot centers: 22 + (240 + 4 + 6)·a + 3.
      expect(TgSlideChooser.dotCenterX(800, 4, 0), 25.0);
      expect(TgSlideChooser.dotCenterX(800, 4, 1), 275.0);
      expect(TgSlideChooser.dotCenterX(800, 4, 3), 775.0);
      // The Java touch formula offsets by +circleSize/2 (not -), so a dot
      // center reads slightly high — the 0.35 snap threshold absorbs it
      // (SlideChooseView.java:143-146).
      expect(
        TgSlideChooser.indexForTouchX(800, 4, 275.0),
        closeTo((275.0 - 22.0 + 3.0) / 250.0, 1e-9),
      );
      expect(TgSlideChooser.indexForTouchX(800, 4, 0.0), 0.0);
      expect(TgSlideChooser.indexForTouchX(800, 4, 800.0), 3.0);
    });
  });

  group('geometry', () {
    testWidgets('74dp tall, full width', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgSlideChooser(
        options: _options,
        selectedIndex: 0,
      )));
      expect(
        tester.getSize(find.byType(TgSlideChooser)),
        const Size(800, 74),
      );
      final TgSlideChooserPainter painter = _painter(tester);
      expect(painter.selectedIndexAnimated, 0.0);
      expect(painter.movingAnimated, 0.0);
      expect(painter.trackColor,
          _dayTheme.color(TelegramColorKey.switchTrack));
      expect(painter.activeColor,
          _dayTheme.color(TelegramColorKey.switchTrackChecked));
      expect(painter.textColor,
          _dayTheme.color(TelegramColorKey.windowBackgroundWhiteGrayText));
      expect(painter.activeTextColor,
          _dayTheme.color(TelegramColorKey.windowBackgroundWhiteBlueText));
    });
  });

  group('selection', () {
    testWidgets('tap snaps to the nearest stop (SlideChooseView.java:179-183)',
        (WidgetTester tester) async {
      final List<int> selections = <int>[];
      int touchEnds = 0;
      await tester.pumpWidget(_host(TgSlideChooser(
        options: _options,
        selectedIndex: 0,
        onOptionSelected: selections.add,
        onTouchEnd: () => touchEnds++,
      )));
      // Dot 2 center is at x = 525.
      await tester.tapAt(const Offset(525, 48));
      expect(selections, <int>[2]);
      expect(touchEnds, 1);

      // Tapping the already-selected stop does not re-fire.
      await tester.pumpWidget(_host(TgSlideChooser(
        options: _options,
        selectedIndex: 2,
        onOptionSelected: selections.add,
        onTouchEnd: () => touchEnds++,
      )));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(525, 48));
      expect(selections, <int>[2]);
      expect(touchEnds, 2);
    });

    testWidgets(
        'dragging fires per stop crossed, with a selection haptic '
        '(SlideChooseView.java:170-176, 200-209)',
        (WidgetTester tester) async {
      final List<MethodCall> haptics = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call);
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final List<int> selections = <int>[];
      int selectedIndex = 0;
      int touchEnds = 0;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return TgSlideChooser(
            options: _options,
            selectedIndex: selectedIndex,
            onOptionSelected: (int index) {
              selections.add(index);
              setState(() => selectedIndex = index);
            },
            onTouchEnd: () => touchEnds++,
          );
        },
      )));

      final TestGesture gesture =
          await tester.startGesture(const Offset(25, 48));
      // Walk from dot 0 to dot 3 in 25px increments — every stop fires as
      // its snap zone is crossed.
      for (int i = 0; i < 30; i++) {
        await gesture.moveBy(const Offset(25, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selections, <int>[1, 2, 3]);
      expect(haptics, hasLength(3));
      expect(haptics.first.arguments, 'HapticFeedbackType.selectionClick');
      expect(touchEnds, 1);
    });
  });

  group('animation', () {
    testWidgets('drawn selection eases over 120ms DEFAULT '
        '(SlideChooseView.java:52, 222)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgSlideChooser(
        options: _options,
        selectedIndex: 1,
      )));
      expect(_painter(tester).selectedIndexAnimated, 1.0);

      await tester.pumpWidget(_host(const TgSlideChooser(
        options: _options,
        selectedIndex: 3,
      )));
      await tester.pump(const Duration(milliseconds: 60));
      final double expected =
          1.0 + 2.0 * TgCurves.defaultCubic.transform(0.5);
      expect(_painter(tester).selectedIndexAnimated, closeTo(expected, 0.01));
      await tester.pumpAndSettle();
      expect(_painter(tester).selectedIndexAnimated, 3.0);
    });

    testWidgets('halo follows the press over 150ms '
        '(SlideChooseView.java:53, 223, 288-292)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgSlideChooser(
        options: _options,
        selectedIndex: 0,
        onOptionSelected: (int index) {},
      )));
      final TgSlideChooserState state =
          tester.state(find.byType(TgSlideChooser));
      final TestGesture gesture =
          await tester.startGesture(const Offset(25, 48));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(state.movingAnimated, 0.0);
      await tester.pump(const Duration(milliseconds: 75));
      expect(state.movingAnimated,
          closeTo(TgCurves.defaultCubic.transform(0.5), 0.01));
      await tester.pump(const Duration(milliseconds: 75));
      expect(state.movingAnimated, closeTo(1.0, 1e-6));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(state.movingAnimated, 0.0);
    });
  });

  group('theme + semantics', () {
    testWidgets('resources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color override = Color(0xFF123456);
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return TgSlideChooser(
          options: _options,
          selectedIndex: 0,
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.switchTrackChecked: override,
            },
          ),
        );
      })));
      expect(_painter(tester).activeColor, override);
    });

    testWidgets('slider semantics carry the selected label '
        '(SlideChooseView.java:75-95)', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final List<int> selections = <int>[];
      await tester.pumpWidget(_host(TgSlideChooser(
        options: _options,
        selectedIndex: 1,
        onOptionSelected: selections.add,
      )));
      expect(
        tester.getSemantics(find.byType(TgSlideChooser)),
        isSemantics(
          isSlider: true,
          value: 'M',
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      handle.dispose();
    });
  });
}
