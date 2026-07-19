// Tests for lib/src/progress/tg_radial_progress.dart (spec_primitives.md
// §4.1), golden-free:
//
//  * the `updateAnimation` state machine driven with exact dt — phase math,
//    +270° offset jump, sweep bounds over a full cycle, determinate 4° floor
//    and 200ms decelerate (RadialProgressView.java:133-203);
//  * toCircle morph timing 220ms in / 400ms out
//    (RadialProgressView.java:138-148);
//  * painter geometry + widget wiring: 40dp box, 3dp stroke, `progressCircle`
//    key with a resources override (both directions), and the 17ms per-frame
//    dt clamp (RadialProgressView.java:126-128) — all without a Material
//    dependency.

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/progress/tg_radial_progress.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

Widget _host(Widget child) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    ),
  );
}

TgRadialProgressPainter _painterOf(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(TgRadialProgress),
      matching: find.byType(CustomPaint),
    ),
  );
  return paint.painter! as TgRadialProgressPainter;
}

void main() {
  group('constants (RadialProgressView.java)', () {
    test('geometry: 40dp box (32 in dialogs), 3dp stroke', () {
      expect(kTgRadialProgressSize, 40.0); // RadialProgressView.java:63
      expect(kTgRadialProgressDialogSize, 32.0); // AlertDialog.java:886
      expect(kTgRadialProgressStrokeWidth, 3.0); // RadialProgressView.java:71
    });

    test('timing: 2s revolution, 500ms phases, 200ms progress, '
        '220/400ms toCircle, 17ms dt clamp', () {
      expect(kTgRadialProgressRotationTimeMs, 2000.0); // :41
      expect(kTgRadialProgressRisingTimeMs, 500.0); // :42
      expect(kTgRadialProgressMinSweepDeg, 4.0); // :157, :200
      expect(kTgRadialProgressGrowSweepDeg, 266.0); // :157
      expect(kTgRadialProgressShrinkSweepDeg, 270.0); // :159
      expect(kTgRadialProgressOffsetJumpDeg, 270.0); // :164
      expect(kTgRadialProgressProgressTimeMs, 200.0); // :193
      expect(kTgRadialProgressToCircleInMs, 220.0); // :139
      expect(kTgRadialProgressToCircleOutMs, 400.0); // :144
      expect(kTgRadialProgressMaxFrameMs, 17.0); // :126-128
    });
  });

  group('indeterminate cycle (RadialProgressView.java:150-169)', () {
    test('starts in the shrink phase: 4 − 270·(1 − decelerate(t))', () {
      final TgRadialProgressAnimation anim = TgRadialProgressAnimation();
      anim.update(250.0);
      // decelerate(0.5) = 1 − 0.25 = 0.75 → 4 − 270·0.25 = −63.5.
      expect(anim.circleLength, closeTo(-63.5, 1e-9));
      expect(anim.risingCircleLength, isFalse);
    });

    test('phase boundary at exactly 500ms flips to rising with sweep 4°', () {
      final TgRadialProgressAnimation anim = TgRadialProgressAnimation();
      anim.update(250.0);
      anim.update(250.0);
      expect(anim.circleLength, closeTo(4.0, 1e-9));
      expect(anim.risingCircleLength, isTrue);
      expect(anim.radOffset, closeTo(90.0, 1e-9)); // 360·500/2000
    });

    test('grow phase: 4 + 266·accelerate(t), then the +270° jump to −266°',
        () {
      final TgRadialProgressAnimation anim = TgRadialProgressAnimation();
      anim.update(250.0);
      anim.update(250.0); // now rising, phase clock 0
      anim.update(250.0);
      // accelerate(0.5) = 0.25 → 4 + 266·0.25 = 70.5.
      expect(anim.circleLength, closeTo(70.5, 1e-9));
      anim.update(250.0);
      // Phase end: sweep hits 270, then radOffset += 270 and sweep = −266
      // (RadialProgressView.java:162-168).
      expect(anim.circleLength, closeTo(-266.0, 1e-9));
      expect(anim.risingCircleLength, isFalse);
      // 360·1000/2000 = 180, +270 jump (wrapped on the next update).
      expect(anim.radOffset, closeTo(450.0, 1e-9));
      anim.update(0.0);
      expect(anim.radOffset, closeTo(90.0, 1e-9));
    });

    test('sweep stays within [−266°, 270°] over a full cycle', () {
      final TgRadialProgressAnimation anim = TgRadialProgressAnimation();
      double maxSweep = double.negativeInfinity;
      double minSweep = double.infinity;
      for (int i = 0; i < 200; i++) {
        anim.update(10.0);
        maxSweep = anim.circleLength > maxSweep ? anim.circleLength : maxSweep;
        minSweep = anim.circleLength < minSweep ? anim.circleLength : minSweep;
        expect(anim.circleLength, lessThanOrEqualTo(270.0 + 1e-9));
        expect(anim.circleLength, greaterThanOrEqualTo(-266.0 - 1e-9));
      }
      // The cycle actually breathes: nearly full ring both ways.
      expect(maxSweep, greaterThan(250.0));
      expect(minSweep, closeTo(-266.0, 1e-9));
    });

    test('rotation wraps at 360° (RadialProgressView.java:134-136)', () {
      final TgRadialProgressAnimation anim = TgRadialProgressAnimation()
        ..noProgress = false;
      anim.update(500.0);
      expect(anim.radOffset, closeTo(90.0, 1e-9));
      anim.update(1500.0); // 90 + 270 = 360 → wrapped to 0
      expect(anim.radOffset, closeTo(0.0, 1e-9));
    });
  });

  group('determinate mode (RadialProgressView.java:189-201)', () {
    test('eases upward over 200ms decelerate', () {
      final TgRadialProgressAnimation anim = TgRadialProgressAnimation()
        ..noProgress = false
        ..setProgress(0.5);
      anim.update(100.0);
      // decelerate(0.5) = 0.75 → animated 0.375 → sweep 135°.
      expect(anim.animatedProgress, closeTo(0.375, 1e-9));
      expect(anim.circleLength, closeTo(135.0, 1e-9));
      anim.update(100.0);
      expect(anim.animatedProgress, 0.5);
      expect(anim.circleLength, closeTo(180.0, 1e-9));
    });

    test('sweep floor: max(4°, 360·p)', () {
      final TgRadialProgressAnimation anim = TgRadialProgressAnimation()
        ..noProgress = false
        ..setProgress(0.005);
      anim.update(200.0);
      expect(anim.circleLength, 4.0);
    });

    test('a lower value snaps the displayed progress down '
        '(RadialProgressView.java:97-104)', () {
      final TgRadialProgressAnimation anim = TgRadialProgressAnimation()
        ..noProgress = false
        ..setProgress(0.5);
      anim.update(200.0);
      expect(anim.animatedProgress, 0.5);
      anim.setProgress(0.25);
      expect(anim.animatedProgress, 0.25);
      anim.update(0.0);
      expect(anim.circleLength, closeTo(90.0, 1e-9));
    });
  });

  group('toCircle morph (RadialProgressView.java:138-148, 219-224)', () {
    test('220ms in / 400ms out', () {
      final TgRadialProgressAnimation anim = TgRadialProgressAnimation()
        ..toCircle(true);
      anim.update(110.0);
      expect(anim.toCircleProgress, closeTo(0.5, 1e-9));
      anim.update(110.0);
      expect(anim.toCircleProgress, 1.0);
      anim.update(50.0);
      expect(anim.toCircleProgress, 1.0); // clamped
      anim.toCircle(false);
      anim.update(200.0);
      expect(anim.toCircleProgress, closeTo(0.5, 1e-9));
      anim.update(200.0);
      expect(anim.toCircleProgress, 0.0);
    });

    test('unanimated set snaps, and a full morph reads as a circle '
        '(RadialProgressView.java:170-188, 241-243)', () {
      final TgRadialProgressAnimation anim = TgRadialProgressAnimation()
        ..toCircle(true, animated: false);
      expect(anim.toCircleProgress, 1.0);
      anim.update(10.0);
      // Shrink branch with the morph: 4 − 270·(1−decel(0)) − 364·1 = −630.
      expect(anim.circleLength, closeTo(-630.0, 1e-9));
      expect(anim.isCircle, isTrue);
    });
  });

  group('TgRadialProgressPainter', () {
    test('arcRect: arcSize square centered in the bounds '
        '(RadialProgressView.java:228-230)', () {
      final TgRadialProgressPainter painter = TgRadialProgressPainter(
        radOffset: 0.0,
        circleLength: 90.0,
        color: const Color(0xFF1C93E3),
      );
      final Rect rect = painter.arcRect(const Size(60.0, 60.0));
      expect(rect, const Rect.fromLTRB(10.0, 10.0, 50.0, 50.0));
      expect(painter.arcSize, kTgRadialProgressSize);
      expect(painter.strokeWidth, kTgRadialProgressStrokeWidth);
    });

    test('shouldRepaint on angle/sweep/config change, false when identical',
        () {
      TgRadialProgressPainter make({
        double radOffset = 10.0,
        double circleLength = 90.0,
        Color color = const Color(0xFF1C93E3),
        double arcSize = 40.0,
      }) {
        return TgRadialProgressPainter(
          radOffset: radOffset,
          circleLength: circleLength,
          color: color,
          arcSize: arcSize,
        );
      }

      final TgRadialProgressPainter base = make();
      expect(make().shouldRepaint(base), isFalse);
      expect(make(radOffset: 11.0).shouldRepaint(base), isTrue);
      expect(make(circleLength: -63.5).shouldRepaint(base), isTrue);
      expect(
        make(color: const Color(0xFF6B7378)).shouldRepaint(base),
        isTrue,
      );
      expect(make(arcSize: 32.0).shouldRepaint(base), isTrue);
    });

    test('paints without error, including negative sweeps', () {
      for (final double sweep in const <double>[4.0, 270.0, -266.0, -630.0]) {
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final Canvas canvas = Canvas(recorder);
        TgRadialProgressPainter(
          radOffset: 45.0,
          circleLength: sweep,
          color: const Color(0xFF1C93E3),
        ).paint(canvas, const Size(40.0, 40.0));
        recorder.endRecording().dispose();
      }
    });
  });

  group('TgRadialProgress widget', () {
    testWidgets('sizes itself to the arc box; 32dp dialog override',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgRadialProgress()));
      expect(
        tester.getSize(find.byType(TgRadialProgress)),
        const Size(40.0, 40.0),
      );
      await tester.pumpWidget(_host(
        const TgRadialProgress(size: kTgRadialProgressDialogSize),
      ));
      expect(
        tester.getSize(find.byType(TgRadialProgress)),
        const Size(32.0, 32.0),
      );
      expect(_painterOf(tester).arcSize, 32.0);
    });

    testWidgets('resolves progressCircle via the theme, and a resources '
        'override flips it (both directions)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgRadialProgress()));
      expect(
        _painterOf(tester).color,
        _dayTheme.color(TelegramColorKey.progressCircle),
      );

      const Color override = Color(0xFFABCDEF);
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return TgRadialProgress(
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.progressCircle: override,
            },
          ),
        );
      })));
      expect(_painterOf(tester).color, override);
    });

    testWidgets('raw color override wins over the key '
        '(setProgressColor, RadialProgressView.java:214-217)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgRadialProgress(
        color: Color(0xFF6B7378), // the AlertDialog dialog_inlineProgress way
        colorKey: TelegramColorKey.progressCircle,
      )));
      expect(_painterOf(tester).color, const Color(0xFF6B7378));
    });

    testWidgets('ticks: the arc advances between frames',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgRadialProgress()));
      await tester.pump(const Duration(milliseconds: 16)); // first tick
      final double r0 = _painterOf(tester).radOffset;
      final double s0 = _painterOf(tester).circleLength;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_painterOf(tester).radOffset, isNot(closeTo(r0, 1e-9)));
      expect(_painterOf(tester).circleLength, isNot(closeTo(s0, 1e-9)));
    });

    testWidgets('per-frame dt clamps to 17ms '
        '(RadialProgressView.java:126-128)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgRadialProgress()));
      await tester.pump(const Duration(milliseconds: 16)); // first tick, dt 0
      final double r0 = _painterOf(tester).radOffset;
      await tester.pump(const Duration(seconds: 1));
      final double r1 = _painterOf(tester).radOffset;
      // One clamped frame: 360·17/2000 = 3.06°, not 180°.
      expect(r1 - r0, closeTo(3.06, 1e-6));
    });

    testWidgets('determinate progress eases over 200ms of frames',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgRadialProgress(progress: 0.0)));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_painterOf(tester).circleLength, 4.0); // max(4, 0)

      await tester.pumpWidget(_host(const TgRadialProgress(progress: 0.5)));
      await tester.pump(const Duration(milliseconds: 16));
      final double mid = _painterOf(tester).circleLength;
      expect(mid, greaterThan(4.0));
      expect(mid, lessThan(180.0));
      for (int i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_painterOf(tester).circleLength, closeTo(180.0, 1e-9));
    });

    testWidgets('toCircle morphs to a full ring', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgRadialProgress()));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpWidget(_host(const TgRadialProgress(toCircle: true)));
      for (int i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_painterOf(tester).circleLength.abs(), greaterThanOrEqualTo(360));
    });

    testWidgets('disposes its ticker cleanly', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgRadialProgress()));
      await tester.pump(const Duration(milliseconds: 32));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  });
}
