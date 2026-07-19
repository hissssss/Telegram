// Ring-1 tests for lib/src/progress/tg_circular_progress.dart.
//
// Segment samples are exact closed-form evaluations of the Java
// `getSegments` math (CircularProgressDrawable.java:43-50): at pulse
// boundaries every eased term is a clamped 0 or 1, so the expected values
// are exact; the mid-pulse sample tolerates the lookup-table-vs-cubic
// FastOutSlowIn divergence (~1e-3 → ≤0.25°).

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/progress/tg_circular_progress.dart';

void main() {
  group('constants (CircularProgressDrawable.java)', () {
    test('geometry: 18dp arc, 2.25dp stroke, white (:19-24)', () {
      expect(kTgCircularProgressSize, 18.0);
      expect(kTgCircularProgressThickness, 2.25);
      expect(kTgCircularProgressDefaultColor, const Color(0xFFFFFFFF));
    });

    test('cycle: 5400ms, 1520° advance, 20° tail lag, 4×250° pulses '
        'of 667ms every 1350ms (:39, :43-50)', () {
      expect(kTgCircularProgressPeriodMs, 5400.0);
      expect(kTgCircularProgressRotationDeg, 1520.0);
      expect(kTgCircularProgressTailLagDeg, 20.0);
      expect(kTgCircularProgressPulseCount, 4);
      expect(kTgCircularProgressPulseDeg, 250.0);
      expect(kTgCircularProgressPulseDurationMs, 667.0);
      expect(kTgCircularProgressPulseIntervalMs, 1350.0);
    });
  });

  group('tgCircularProgressSegments (CircularProgressDrawable.java:43-50)',
      () {
    test('t=0: both ends at 0° (tail clamped by max(0, ·))', () {
      final ({double start, double end}) s = tgCircularProgressSegments(0.0);
      expect(s.start, 0.0);
      expect(s.end, 0.0);
    });

    test('quarter period t=1350: (610°, 630°) — first pulse complete', () {
      // end   = 1520·1350/5400 + 250 = 380 + 250 = 630
      // start = 380 − 20 + 250      = 610
      final ({double start, double end}) s = tgCircularProgressSegments(1350.0);
      expect(s.start, closeTo(610.0, 1e-9));
      expect(s.end, closeTo(630.0, 1e-9));
    });

    test('half period t=2700: (1240°, 1260°) — two pulses complete', () {
      final ({double start, double end}) s = tgCircularProgressSegments(2700.0);
      expect(s.start, closeTo(1240.0, 1e-9));
      expect(s.end, closeTo(1260.0, 1e-9));
    });

    test('three quarters t=4050: (1870°, 1890°) — three pulses complete', () {
      final ({double start, double end}) s = tgCircularProgressSegments(4050.0);
      expect(s.start, closeTo(1870.0, 1e-9));
      expect(s.end, closeTo(1890.0, 1e-9));
    });

    test('full period t=5400: (2500°, 2520°) — all four pulses complete', () {
      final ({double start, double end}) s = tgCircularProgressSegments(5400.0);
      expect(s.start, closeTo(2500.0, 1e-9));
      expect(s.end, closeTo(2520.0, 1e-9));
    });

    test('mid-pulse t=333.5 (pulse half-time): head races, tail waits', () {
      // end   = 1520·333.5/5400 + fastOutSlowIn(0.5)·250
      //       ≈ 93.8741 + 0.77557·250 ≈ 287.77
      // start = 93.8741 − 20 = 73.8741 (no tail pulse active yet)
      final ({double start, double end}) s = tgCircularProgressSegments(333.5);
      expect(s.start, closeTo(73.874074, 1e-6));
      expect(s.end, closeTo(287.77, 0.5));
    });

    test('sweep breathes: ~20° at pulse boundaries, >200° mid-pulse', () {
      for (final double t in [1350.0, 2700.0, 4050.0, 5400.0]) {
        final ({double start, double end}) s = tgCircularProgressSegments(t);
        expect(s.end - s.start, closeTo(20.0, 1e-9), reason: 't=$t');
      }
      for (final double t in [333.5, 1683.5, 3033.5, 4383.5]) {
        final ({double start, double end}) s = tgCircularProgressSegments(t);
        expect(s.end - s.start, greaterThan(200.0), reason: 't=$t');
        expect(s.end - s.start, lessThan(270.001), reason: 't=$t');
      }
    });

    test('end never precedes start across the cycle', () {
      for (double t = 0.0; t <= 5400.0; t += 27.0) {
        final ({double start, double end}) s = tgCircularProgressSegments(t);
        expect(s.end, greaterThanOrEqualTo(s.start), reason: 't=$t');
      }
    });
  });

  group('TgCircularProgressPainter', () {
    test('defaults mirror the Java drawable', () {
      final TgCircularProgressPainter p =
          TgCircularProgressPainter(elapsed: Duration.zero);
      expect(p.color, kTgCircularProgressDefaultColor);
      expect(p.diameter, kTgCircularProgressSize);
      expect(p.thickness, kTgCircularProgressThickness);
      expect(p.angleOffset, 0.0);
    });

    test('arcRect: (size + thickness/2) square centered in the bounds '
        '(setBounds math, CircularProgressDrawable.java:86-96)', () {
      final TgCircularProgressPainter p =
          TgCircularProgressPainter(elapsed: Duration.zero);
      final Rect rect = p.arcRect(const Size(40.0, 40.0));
      expect(rect.width, closeTo(18.0 + 2.25 / 2, 1e-9));
      expect(rect.height, closeTo(18.0 + 2.25 / 2, 1e-9));
      expect(rect.center, const Offset(20.0, 20.0));
      expect(rect.left, closeTo(20.0 - 19.125 / 2, 1e-9));
    });

    test('arcRect honors a custom diameter/thickness', () {
      final TgCircularProgressPainter p = TgCircularProgressPainter(
        elapsed: Duration.zero,
        diameter: 24.0,
        thickness: 3.0,
      );
      final Rect rect = p.arcRect(const Size(30.0, 30.0));
      expect(rect.width, closeTo(25.5, 1e-9));
      expect(rect.center, const Offset(15.0, 15.0));
    });

    test('shouldRepaint: true on tick (elapsed change) and config change, '
        'false when identical', () {
      final TgCircularProgressPainter base =
          TgCircularProgressPainter(elapsed: const Duration(milliseconds: 100));
      final TgCircularProgressPainter same =
          TgCircularProgressPainter(elapsed: const Duration(milliseconds: 100));
      final TgCircularProgressPainter ticked =
          TgCircularProgressPainter(elapsed: const Duration(milliseconds: 116));
      final TgCircularProgressPainter recolored = TgCircularProgressPainter(
        elapsed: const Duration(milliseconds: 100),
        color: const Color(0xFF298ACF),
      );
      expect(ticked.shouldRepaint(base), isTrue);
      expect(recolored.shouldRepaint(base), isTrue);
      expect(same.shouldRepaint(base), isFalse);
    });

    test('paints without error at t=0 and quarter-period samples', () {
      for (final Duration elapsed in const [
        Duration.zero,
        Duration(milliseconds: 1350),
        Duration(milliseconds: 2700),
        Duration(milliseconds: 4050),
        Duration(milliseconds: 6750), // wraps past one period
      ]) {
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final Canvas canvas = Canvas(recorder);
        TgCircularProgressPainter(elapsed: elapsed)
            .paint(canvas, const Size(20.25, 20.25));
        recorder.endRecording().dispose();
      }
    });
  });

  group('TgCircularProgress widget', () {
    testWidgets('sizes itself to the intrinsic size + thickness '
        '(CircularProgressDrawable.java:116-123)', (tester) async {
      await tester.pumpWidget(const Center(child: TgCircularProgress()));
      expect(
        tester.getSize(find.byType(TgCircularProgress)),
        const Size(20.25, 20.25),
      );
    });

    testWidgets('repaints on tick: the painter advances between frames',
        (tester) async {
      await tester.pumpWidget(const Center(child: TgCircularProgress()));

      TgCircularProgressPainter painterNow() {
        final CustomPaint paint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(TgCircularProgress),
            matching: find.byType(CustomPaint),
          ),
        );
        return paint.painter! as TgCircularProgressPainter;
      }

      // Let the ticker's first tick land (it anchors the start time).
      await tester.pump(const Duration(milliseconds: 20));
      final Duration t0 = painterNow().elapsed;
      await tester.pump(const Duration(milliseconds: 100));
      final Duration t1 = painterNow().elapsed;
      await tester.pump(const Duration(milliseconds: 100));
      final Duration t2 = painterNow().elapsed;

      expect(t1, greaterThan(t0));
      expect(t2, greaterThan(t1));
      // The new painter reports shouldRepaint against the previous frame's.
      expect(
        TgCircularProgressPainter(elapsed: t2)
            .shouldRepaint(TgCircularProgressPainter(elapsed: t1)),
        isTrue,
      );
    });

    testWidgets('configurable color and size flow into the painter',
        (tester) async {
      const Color color = Color(0xFF5EC245);
      await tester.pumpWidget(
        const Center(
          child: TgCircularProgress(
            color: color,
            diameter: 32.0,
            thickness: 3.0,
            angleOffset: 90.0,
          ),
        ),
      );
      final CustomPaint paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(TgCircularProgress),
          matching: find.byType(CustomPaint),
        ),
      );
      final TgCircularProgressPainter painter =
          paint.painter! as TgCircularProgressPainter;
      expect(painter.color, color);
      expect(painter.diameter, 32.0);
      expect(painter.thickness, 3.0);
      expect(painter.angleOffset, 90.0);
      expect(
        tester.getSize(find.byType(TgCircularProgress)),
        const Size(35.0, 35.0),
      );
    });

    testWidgets('disposes its ticker cleanly', (tester) async {
      await tester.pumpWidget(const Center(child: TgCircularProgress()));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox());
      // Un-disposed tickers would throw a FlutterError here.
      expect(tester.takeException(), isNull);
    });
  });
}
