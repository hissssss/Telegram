// Tests for lib/src/controls/tg_slider.dart (PLAN_UIKIT.md M7), golden-free:
//
//  * constants vs SeekBarView.java (insets, radii, durations);
//  * geometry: 16dp end insets, travel = width - 32 (SeekBarView.java:447,
//    451), thumb center placement;
//  * drag streams onChanged + clamps, release fires onChangeEnd
//    (SeekBarView.java:255-265, 308-325);
//  * tap-to-seek (SeekBarView.java:238-252);
//  * press radius 6->8dp at 1dp/60ms (SeekBarView.java:489-509);
//  * step snap: 60ms EASE_OUT drawn-thumb animation (SeekBarView.java:62,
//    440-442) + selection haptic per step (SeekBarView.java:350-356);
//  * 225ms double-circle animated jump (SeekBarView.java:510-528);
//  * two-sided [-1, 1] mapping (SeekBarView.java:255-262, 377-384);
//  * minProgress clamp + 50%-alpha segment (SeekBarView.java:337-339,
//    469-476);
//  * theme key resolution + resources override; slider semantics.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/controls/tg_slider.dart';
import 'package:telegram_ui/src/foundation/tg_curves.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

/// The default 800-wide test surface: travel = 800 - 32.
const double _travel = 768.0;

Widget _host(Widget child) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.topCenter, child: child),
    ),
  );
}

TgSliderPainter _painter(WidgetTester tester) =>
    tester
        .widget<CustomPaint>(find.descendant(
          of: find.byType(TgSlider),
          matching: find.byType(CustomPaint),
        ))
        .painter! as TgSliderPainter;

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kTgSliderHeight, 38.0); // ThemeActivity.java:341
      expect(kTgSliderSelectorWidth, 32.0); // SeekBarView.java:115
      expect(kTgSliderThumbSize, 24.0); // SeekBarView.java:116
      expect(kTgSliderThumbRadius, 6.0); // SeekBarView.java:117, 490
      expect(kTgSliderThumbRadiusPressed, 8.0); // SeekBarView.java:490
      expect(kTgSliderThumbRadiusDuration,
          const Duration(milliseconds: 120)); // 2dp at 1dp/60ms
      expect(kTgSliderLineWidth, 3.0); // SeekBarView.java:77
      expect(kTgSliderTrackRadius, 2.0); // SeekBarView.java:657-659
      expect(kTgSliderSnapDuration,
          const Duration(milliseconds: 60)); // SeekBarView.java:62
      expect(kTgSliderSnapCurve, TgCurves.easeOut); // SeekBarView.java:62
      expect(kTgSliderTransitionDuration,
          const Duration(milliseconds: 225)); // SeekBarView.java:511
      expect(kTgSliderMinProgressAlpha, 0.5); // SeekBarView.java:474
      expect(kTgSliderNotchSize, const Size(2.0, 12.0)); // SeekBarView.java:462
      expect(kTgSliderTwoSidedFillHeight, 2.0); // SeekBarView.java:463-467
      // Easings.java:12-13.
      expect(kTgSliderEaseInQuad, const Cubic(0.55, 0.085, 0.68, 0.53));
      expect(kTgSliderEaseOutQuad, const Cubic(0.25, 0.46, 0.45, 0.94));
    });

    test('two-sided value<->thumbX mapping (SeekBarView.java:255-262, '
        '377-384)', () {
      // p >= 0 measures from the center...
      expect(TgSlider.thumbXForValue(0.0, 768, twoSided: true), 384.0);
      expect(TgSlider.thumbXForValue(1.0, 768, twoSided: true), 768.0);
      expect(TgSlider.thumbXForValue(0.5, 768, twoSided: true), 576.0);
      // ...negative values measure from the LEFT EDGE (the Java asymmetry):
      // -1 sits just left of center, -0.01 at the far left.
      expect(TgSlider.thumbXForValue(-1.0, 768, twoSided: true), 384.0);
      expect(TgSlider.thumbXForValue(-0.5, 768, twoSided: true), 192.0);
      // Round trips.
      expect(TgSlider.valueForThumbX(576.0, 768, twoSided: true), 0.5);
      expect(TgSlider.valueForThumbX(192.0, 768, twoSided: true), -0.5);
      // Far left reports -0.01 (`-Math.max(0.01f, ...)`,
      // SeekBarView.java:261).
      expect(TgSlider.valueForThumbX(0.0, 768, twoSided: true), -0.01);
      // Single-sided is linear.
      expect(TgSlider.valueForThumbX(384.0, 768), 0.5);
      expect(TgSlider.thumbXForValue(0.25, 768), 192.0);
    });
  });

  group('geometry', () {
    testWidgets('38dp tall; thumb center at 16 + value * travel',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgSlider(value: 0.5)));
      expect(tester.getSize(find.byType(TgSlider)), const Size(800, 38));
      final TgSliderPainter painter = _painter(tester);
      expect(painter.thumbCenterX, 16.0 + 0.5 * _travel);
      expect(painter.thumbRadius, kTgSliderThumbRadius);
      expect(painter.lineWidth, 3.0);
      expect(painter.fillColor,
          _dayTheme.color(TelegramColorKey.player_progress));
      expect(painter.trackColor,
          _dayTheme.color(TelegramColorKey.player_progressBackground));
      expect(painter.bufferedColor,
          _dayTheme.color(TelegramColorKey.player_progressCachedBackground));
    });

    testWidgets('buffered + minValue flow to the painter',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgSlider(
        value: 0.1,
        buffered: 0.7,
        minValue: 0.25,
      )));
      final TgSliderPainter painter = _painter(tester);
      expect(painter.buffered, 0.7);
      expect(painter.minProgress, 0.25);
      // The thumb clamps to minThumbX (SeekBarView.java:337-339, 394).
      expect(painter.thumbCenterX, 16.0 + 0.25 * _travel);
    });

    testWidgets('two-sided drawing', (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(const TgSlider(value: -0.5, twoSided: true)));
      final TgSliderPainter painter = _painter(tester);
      expect(painter.twoSided, isTrue);
      expect(painter.thumbCenterX, 16.0 + 192.0);
    });
  });

  group('touch', () {
    testWidgets('drag streams onChanged and clamps; release fires onChangeEnd',
        (WidgetTester tester) async {
      final List<double> changes = <double>[];
      final List<double> ends = <double>[];
      await tester.pumpWidget(_host(TgSlider(
        value: 0.5,
        onChanged: changes.add,
        onChangeEnd: ends.add,
      )));
      // Grab inside the thumb box (thumb left edge 384, grab offset kept —
      // SeekBarView.java:285-295), drag +200: thumbX 584.
      await tester.drag(find.byType(TgSlider), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(changes, isNotEmpty);
      expect(changes.last, closeTo(584.0 / _travel, 1e-6));
      expect(ends, hasLength(1));
      expect(ends.single, closeTo(584.0 / _travel, 1e-6));

      // A huge drag clamps to 1.0 (SeekBarView.java:308-313).
      changes.clear();
      ends.clear();
      await tester.drag(find.byType(TgSlider), const Offset(1000, 0));
      await tester.pumpAndSettle();
      expect(ends.single, 1.0);
    });

    testWidgets('tap outside the grab box jumps the thumb '
        '(SeekBarView.java:238-252)', (WidgetTester tester) async {
      final List<double> changes = <double>[];
      final List<double> ends = <double>[];
      await tester.pumpWidget(_host(TgSlider(
        value: 0.5,
        onChanged: changes.add,
        onChangeEnd: ends.add,
      )));
      // Tap at x=616: thumbX = 616 - thumbSize/2 = 604.
      await tester.tapAt(const Offset(616, 19));
      await tester.pumpAndSettle();
      expect(changes.single, closeTo(604.0 / _travel, 1e-6));
      expect(ends.single, closeTo(604.0 / _travel, 1e-6));
    });

    testWidgets('press radius grows 6->8dp at 1dp/60ms '
        '(SeekBarView.java:489-509)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgSlider(
        value: 0.5,
        onChanged: (double value) {},
      )));
      final TgSliderState state = tester.state(find.byType(TgSlider));
      final TestGesture gesture =
          await tester.startGesture(const Offset(400, 19));
      // Cross the horizontal slop so the drag recognizer wins.
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(state.debugThumbRadius, closeTo(6.0, 0.001));

      await tester.pump(const Duration(milliseconds: 60));
      expect(state.debugThumbRadius, closeTo(7.0, 0.02));
      await tester.pump(const Duration(milliseconds: 60));
      expect(state.debugThumbRadius, closeTo(8.0, 0.001));
      expect(_painter(tester).thumbRadius, closeTo(8.0, 0.001));

      // Release shrinks back at the same rate.
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(state.debugThumbRadius, closeTo(7.0, 0.02));
      await tester.pumpAndSettle();
      expect(state.debugThumbRadius, closeTo(6.0, 0.001));
    });
  });

  group('steps', () {
    testWidgets('drawn thumb snaps to the stops through the 60ms EASE_OUT '
        'float (SeekBarView.java:440-442)', (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(const TgSlider(value: 0.6, stepCount: 5)));
      await tester.pumpAndSettle();
      // round(0.6 * 4) / 4 = 0.5.
      expect(_painter(tester).thumbCenterX, closeTo(16.0 + 0.5 * _travel, 1e-6));

      // Retargeting animates over 60ms EASE_OUT.
      await tester
          .pumpWidget(_host(const TgSlider(value: 0.9, stepCount: 5)));
      await tester.pump(const Duration(milliseconds: 30));
      final double expectedFraction =
          0.5 + (1.0 - 0.5) * TgCurves.easeOut.transform(0.5);
      expect(
        _painter(tester).thumbCenterX,
        closeTo(16.0 + expectedFraction * _travel, 0.5),
      );
      await tester.pumpAndSettle();
      expect(_painter(tester).thumbCenterX, closeTo(16.0 + _travel, 1e-6));
    });

    testWidgets('crossing steps during a drag fires a selection haptic '
        '(SeekBarView.java:350-356)', (WidgetTester tester) async {
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

      await tester.pumpWidget(_host(TgSlider(
        value: 0.0,
        stepCount: 5,
        onChanged: (double value) {},
      )));
      final TestGesture gesture =
          await tester.startGesture(const Offset(16, 19));
      // Walk the full travel in small increments: 4 step crossings.
      for (int i = 0; i < 32; i++) {
        await gesture.moveBy(const Offset(24, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(haptics, hasLength(4));
      expect(haptics.first.arguments, 'HapticFeedbackType.selectionClick');
    });
  });

  group('animated jump', () {
    testWidgets('225ms double-circle swap (SeekBarView.java:510-528)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _host(const TgSlider(value: 0.2, animateChanges: true)));
      await tester.pumpWidget(
          _host(const TgSlider(value: 0.8, animateChanges: true)));
      await tester.pump(const Duration(milliseconds: 45)); // t = 0.2
      TgSliderPainter painter = _painter(tester);
      expect(painter.transitionProgress, closeTo(0.2, 0.01));
      expect(painter.transitionOldCenterX, closeTo(16.0 + 0.2 * _travel, 1e-6));
      expect(painter.thumbCenterX, closeTo(16.0 + 0.8 * _travel, 1e-6));
      // Mid-flight both circles draw at partial radii: the old collapses
      // over the first third, the new grows easeOutQuad.
      expect(painter.oldCircleFactor, greaterThan(0.0));
      expect(painter.oldCircleFactor, lessThan(1.0));
      expect(painter.newCircleFactor,
          closeTo(kTgSliderEaseOutQuad.transform(0.2), 0.02));

      // The old circle is gone after t = 1/3 of the transition.
      await tester.pump(const Duration(milliseconds: 45)); // t = 0.4
      painter = _painter(tester);
      expect(painter.oldCircleFactor, 0.0);

      await tester.pumpAndSettle();
      painter = _painter(tester);
      expect(painter.transitionProgress, 1.0);
      expect(painter.transitionOldCenterX, isNull);
    });
  });

  group('two-sided touch', () {
    testWidgets('release maps through the Java two-sided formula '
        '(SeekBarView.java:255-262)', (WidgetTester tester) async {
      final List<double> ends = <double>[];
      await tester.pumpWidget(_host(TgSlider(
        value: 0.0,
        twoSided: true,
        onChangeEnd: ends.add,
      )));
      // Thumb starts at center (thumbX 384). Drag to the far left: the
      // reported value bottoms out at -0.01.
      await tester.drag(find.byType(TgSlider), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(ends.single, -0.01);

      // And a right-half drag reports the center-relative fraction.
      ends.clear();
      await tester.pumpWidget(_host(TgSlider(
        value: 0.0,
        twoSided: true,
        onChangeEnd: ends.add,
      )));
      await tester.drag(find.byType(TgSlider), const Offset(192, 0));
      await tester.pumpAndSettle();
      expect(ends.single, closeTo(0.5, 0.01));
    });
  });

  group('theme + semantics', () {
    testWidgets('resources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color override = Color(0xFF123456);
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return TgSlider(
          value: 0.5,
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.player_progress: override,
            },
          ),
        );
      })));
      expect(_painter(tester).fillColor, override);

      await tester.pumpWidget(_host(const TgSlider(value: 0.5)));
      expect(_painter(tester).fillColor,
          _dayTheme.color(TelegramColorKey.player_progress));
    });

    testWidgets('slider semantics with increase/decrease actions '
        '(FloatSeekBarAccessibilityDelegate)', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final List<double> ends = <double>[];
      await tester.pumpWidget(_host(TgSlider(
        value: 0.5,
        onChanged: (double value) {},
        onChangeEnd: ends.add,
      )));
      expect(
        tester.getSemantics(find.byType(TgSlider)),
        isSemantics(
          isSlider: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      handle.dispose();
    });
  });
}
