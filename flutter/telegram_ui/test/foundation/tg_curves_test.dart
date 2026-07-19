// Ring-1 tests for lib/src/foundation/tg_curves.dart.
//
// Cubic spot values are exact mathematical solutions of the bezier (solved
// to 1e-15 by bisection offline); Flutter's Cubic and Java's Newton solver
// both approximate to ~1e-3, so a 5e-3 tolerance covers slope amplification.

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/tg_curves.dart';

void main() {
  group('cubic bezier constants (CubicBezierInterpolator.java:11-14)', () {
    test('control points match the Java declarations', () {
      expect(TgCurves.defaultCubic.a, 0.25);
      expect(TgCurves.defaultCubic.b, 0.1);
      expect(TgCurves.defaultCubic.c, 0.25);
      expect(TgCurves.defaultCubic.d, 1.0);

      expect(TgCurves.easeOut.a, 0.0);
      expect(TgCurves.easeOut.b, 0.0);
      expect(TgCurves.easeOut.c, 0.58);
      expect(TgCurves.easeOut.d, 1.0);

      expect(TgCurves.easeOutQuint.a, 0.23);
      expect(TgCurves.easeOutQuint.b, 1.0);
      expect(TgCurves.easeOutQuint.c, 0.32);
      expect(TgCurves.easeOutQuint.d, 1.0);

      expect(TgCurves.easeIn.a, 0.42);
      expect(TgCurves.easeIn.b, 0.0);
      expect(TgCurves.easeIn.c, 1.0);
      expect(TgCurves.easeIn.d, 1.0);

      // CubicBezierInterpolator.java:15-16, 22.
      expect(TgCurves.easeBoth.a, 0.42);
      expect(TgCurves.easeBoth.b, 0.0);
      expect(TgCurves.easeBoth.c, 0.58);
      expect(TgCurves.easeBoth.d, 1.0);

      expect(TgCurves.easeOutBack.a, 0.34);
      expect(TgCurves.easeOutBack.b, 1.56);
      expect(TgCurves.easeOutBack.c, 0.64);
      expect(TgCurves.easeOutBack.d, 1.0);

      expect(TgCurves.standardDecelerate.a, 0.0);
      expect(TgCurves.standardDecelerate.b, 0.0);
      expect(TgCurves.standardDecelerate.c, 0.0);
      expect(TgCurves.standardDecelerate.d, 1.0);
    });

    test('EASE_BOTH matches Flutter easeInOut (identical control points)', () {
      expect(TgCurves.easeBoth.a, Curves.easeInOut.a);
      expect(TgCurves.easeBoth.b, Curves.easeInOut.b);
      expect(TgCurves.easeBoth.c, Curves.easeInOut.c);
      expect(TgCurves.easeBoth.d, Curves.easeInOut.d);
    });

    test('EASE_OUT_BACK overshoots past 1.0 mid-flight', () {
      double peak = 0.0;
      for (double t = 0.05; t < 1.0; t += 0.05) {
        final double v = TgCurves.easeOutBack.transform(t);
        if (v > peak) peak = v;
      }
      expect(peak, greaterThan(1.05));
    });

    test('all curves are exact at the endpoints', () {
      for (final curve in [
        TgCurves.defaultCubic,
        TgCurves.easeOut,
        TgCurves.easeOutQuint,
        TgCurves.easeIn,
        TgCurves.easeBoth,
        TgCurves.easeOutBack,
        TgCurves.standardDecelerate,
        TgCurves.decelerate,
        TgCurves.decelerateFactor2,
        TgCurves.overshoot,
      ]) {
        expect(curve.transform(0.0), 0.0, reason: '$curve at 0');
        expect(curve.transform(1.0), 1.0, reason: '$curve at 1');
      }
    });

    test('DEFAULT spot values', () {
      expect(TgCurves.defaultCubic.transform(0.25), closeTo(0.408511, 5e-3));
      expect(TgCurves.defaultCubic.transform(0.5), closeTo(0.802403, 5e-3));
      expect(TgCurves.defaultCubic.transform(0.75), closeTo(0.960459, 5e-3));
    });

    test('EASE_OUT spot values', () {
      expect(TgCurves.easeOut.transform(0.25), closeTo(0.378138, 5e-3));
      expect(TgCurves.easeOut.transform(0.5), closeTo(0.684643, 5e-3));
      expect(TgCurves.easeOut.transform(0.75), closeTo(0.906535, 5e-3));
    });

    test('EASE_OUT_QUINT spot values', () {
      expect(TgCurves.easeOutQuint.transform(0.25), closeTo(0.775382, 5e-3));
      expect(TgCurves.easeOutQuint.transform(0.5), closeTo(0.965983, 5e-3));
      expect(TgCurves.easeOutQuint.transform(0.75), closeTo(0.997362, 5e-3));
    });

    test('EASE_IN spot values', () {
      expect(TgCurves.easeIn.transform(0.25), closeTo(0.093465, 5e-3));
      expect(TgCurves.easeIn.transform(0.5), closeTo(0.315357, 5e-3));
      expect(TgCurves.easeIn.transform(0.75), closeTo(0.621862, 5e-3));
    });
  });

  group('TgDecelerateCurve (android DecelerateInterpolator)', () {
    test('factor 1: f(t) = 1 - (1 - t)^2, exact', () {
      expect(TgCurves.decelerate.transform(0.5), 0.75);
      expect(TgCurves.decelerate.transform(0.25), closeTo(0.4375, 1e-12));
      expect(TgCurves.decelerate.transform(0.9), closeTo(0.99, 1e-12));
    });

    test('factor 2: f(t) = 1 - (1 - t)^4, exact', () {
      expect(TgCurves.decelerateFactor2.factor, 2.0);
      expect(TgCurves.decelerateFactor2.transform(0.5), closeTo(0.9375, 1e-12));
      expect(TgCurves.decelerateFactor2.transform(0.25), closeTo(1 - 0.31640625, 1e-12));
    });

    test('factor 1.5: f(t) = 1 - (1 - t)^3, exact (page transition curve)',
        () {
      const TgDecelerateCurve curve = TgDecelerateCurve(factor: 1.5);
      expect(curve.transform(0.5), 0.875);
      expect(curve.transform(0.25), closeTo(0.578125, 1e-12));
    });
  });

  group('TgOvershootInterpolator (android OvershootInterpolator)', () {
    test('default tension is 2.0 (the Android default)', () {
      expect(TgCurves.overshoot.tension, 2.0);
      expect(const TgOvershootInterpolator().tension, 2.0);
    });

    test('f(t) = (t-1)^2·((T+1)(t-1)+T)+1, exact spot values', () {
      // T=2, t=0.5: 0.25·(3·(−0.5)+2)+1 = 1.125.
      expect(TgCurves.overshoot.transform(0.5), closeTo(1.125, 1e-12));
      // T=2, t=5/9 (the analytic peak u=−2T/(3(T+1))=−4/9):
      // (16/81)·(2/3)+1 = 1+32/243.
      expect(TgCurves.overshoot.transform(5 / 9), closeTo(1 + 32 / 243, 1e-12));
      // T=1.02 (fragment preview, ActionBarLayout.java:578), t=0.5:
      // 0.25·(2.02·(−0.5)+1.02)+1 = 1.0025.
      expect(const TgOvershootInterpolator(tension: 1.02).transform(0.5),
          closeTo(1.0025, 1e-9));
    });

    test('ends exactly at 1.0 for every tension', () {
      for (final double tension in [1.02, 1.2, 1.3, 2.0]) {
        expect(TgOvershootInterpolator(tension: tension).transform(1.0), 1.0,
            reason: 'tension $tension');
      }
    });
  });

  group('BoolFactor (BoolAnimator analog, manual ticker)', () {
    test('initial state', () {
      final BoolFactor f = BoolFactor();
      expect(f.target, isFalse);
      expect(f.factor, 0.0);
      expect(f.isAnimating, isFalse);

      final BoolFactor on = BoolFactor(value: true);
      expect(on.target, isTrue);
      expect(on.factor, 1.0);
    });

    test('animates 0 -> 1 over the duration with a linear curve', () {
      final BoolFactor f = BoolFactor(
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      f.tick(Duration.zero);
      f.set(true);
      expect(f.isAnimating, isTrue);
      expect(f.factor, 0.0); // no time has passed yet

      expect(f.tick(const Duration(milliseconds: 50)), closeTo(0.25, 1e-9));
      expect(f.tick(const Duration(milliseconds: 100)), closeTo(0.5, 1e-9));
      expect(f.tick(const Duration(milliseconds: 200)), 1.0);
      expect(f.isAnimating, isFalse);
      expect(f.tick(const Duration(milliseconds: 300)), 1.0); // stays settled
    });

    test('applies the curve to normalized time', () {
      final BoolFactor f = BoolFactor(
        value: true,
        duration: const Duration(milliseconds: 100),
        curve: TgCurves.decelerate,
      );
      f.tick(Duration.zero);
      f.set(false);
      // t = 0.5 -> decelerate(0.5) = 0.75 -> lerp(1, 0, 0.75) = 0.25.
      expect(f.tick(const Duration(milliseconds: 50)), closeTo(0.25, 1e-9));
      expect(f.tick(const Duration(milliseconds: 100)), 0.0);
    });

    test('retargeting mid-flight restarts from the current factor', () {
      final BoolFactor f = BoolFactor(
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      f.tick(Duration.zero);
      f.set(true);
      f.tick(const Duration(milliseconds: 100));
      expect(f.factor, closeTo(0.5, 1e-9));

      f.set(false); // reverse at half-way; full duration from 0.5 -> 0
      expect(f.target, isFalse);
      expect(f.tick(const Duration(milliseconds: 200)), closeTo(0.25, 1e-9));
      expect(f.tick(const Duration(milliseconds: 300)), 0.0);
      expect(f.isAnimating, isFalse);
    });

    test('unanimated set snaps immediately and cancels the animation', () {
      final BoolFactor f = BoolFactor(
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      f.tick(Duration.zero);
      f.set(true);
      f.tick(const Duration(milliseconds: 100));
      f.set(false, animated: false);
      expect(f.factor, 0.0);
      expect(f.isAnimating, isFalse);
    });

    test('unanimated set to the same target still snaps (Java parity)', () {
      final BoolFactor f = BoolFactor()..force(true, 0.3);
      expect(f.factor, 0.3);
      f.set(true, animated: false);
      expect(f.factor, 1.0);
    });

    test('animated set toward the current target is a no-op', () {
      int calls = 0;
      final BoolFactor f = BoolFactor(onChanged: (_) => calls++);
      f.set(false);
      expect(f.isAnimating, isFalse);
      expect(calls, 0);
    });

    test('zero duration snaps on animated set', () {
      final BoolFactor f = BoolFactor(duration: Duration.zero);
      f.set(true);
      expect(f.factor, 1.0);
      expect(f.isAnimating, isFalse);
    });

    test('drives the onChanged callback with each factor change', () {
      final List<double> seen = <double>[];
      final BoolFactor f = BoolFactor(
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
        onChanged: seen.add,
      );
      f.tick(Duration.zero);
      f.set(true);
      f.tick(const Duration(milliseconds: 25));
      f.tick(const Duration(milliseconds: 50));
      f.tick(const Duration(milliseconds: 100));
      f.tick(const Duration(milliseconds: 150)); // settled: no extra callback
      expect(seen, <double>[0.25, 0.5, 1.0]);
    });

    test('toggle flips the target and returns it', () {
      final BoolFactor f = BoolFactor(duration: Duration.zero);
      expect(f.toggle(), isTrue);
      expect(f.factor, 1.0);
      expect(f.toggle(), isFalse);
      expect(f.factor, 0.0);
    });

    test('force pins target and factor without animating, clamped', () {
      final BoolFactor f = BoolFactor();
      f.force(true, 1.7);
      expect(f.target, isTrue);
      expect(f.factor, 1.0);
      f.force(false);
      expect(f.factor, 0.0);
      expect(f.isAnimating, isFalse);
    });
  });
}
