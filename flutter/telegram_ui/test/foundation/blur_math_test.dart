// Ring-1 tests for lib/src/foundation/blur_math.dart against hand-computed
// values (exact doubles derived from the DownscaleScrollableNoiseSuppressor
// formulas; see ARCHITECTURE.md section 3.1).

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/blur_math.dart';

void main() {
  group('constants', () {
    test('kBlurSigmaScale is 0.57735 (approx 1/sqrt(3))', () {
      expect(kBlurSigmaScale, 0.57735);
    });

    test('kMaxRadiusForFastBlur is 2.595', () {
      expect(kMaxRadiusForFastBlur, 2.595);
    });
  });

  group('radiusToSigma', () {
    test('radiusToSigma(18) == 10.8923 (the 6dp glass blur at dpr 3)', () {
      // 0.57735 * 18 + 0.5
      expect(radiusToSigma(18), closeTo(10.8923, 1e-9));
    });

    test('radiusToSigma(6) == 3.9641', () {
      expect(radiusToSigma(6), closeTo(3.9641, 1e-9));
    });

    test('zero and negative radii map to sigma 0 (no +0.5 offset)', () {
      expect(radiusToSigma(0), 0.0);
      expect(radiusToSigma(-3), 0.0);
    });
  });

  group('sigmaToRadius', () {
    test('inverts radiusToSigma for positive radii', () {
      for (final double r in <double>[0.5, 1, 2.595, 6, 18, 38.34, 100]) {
        expect(sigmaToRadius(radiusToSigma(r)), closeTo(r, 1e-9), reason: 'radius $r');
      }
    });

    test('sigma <= 0.5 maps to radius 0', () {
      expect(sigmaToRadius(0.5), 0.0);
      expect(sigmaToRadius(0.4), 0.0);
      expect(sigmaToRadius(0), 0.0);
    });

    test('sigmaToRadius(2) == 2.598076...', () {
      expect(sigmaToRadius(2), closeTo(1.5 / 0.57735, 1e-12));
    });
  });

  group('downscaleRadius', () {
    // Hand-computed: sigma(18) = 10.8923;
    //   k=4:  (10.8923/4  - 0.5) / 0.57735 = 3.8504806443232007
    //   k=8:  (10.8923/8  - 0.5) / 0.57735 = 1.4922274183770676
    //   k=16: (10.8923/16 - 0.5) / 0.57735 = 0.3131... -> clamped to 1
    test('radius 18 at the glass 4x downscale', () {
      expect(downscaleRadius(18, 4), closeTo(3.8504806443232007, 1e-9));
    });

    test('radius 18 at the frosted 8x downscale', () {
      expect(downscaleRadius(18, 8), closeTo(1.4922274183770676, 1e-9));
    });

    test('radius 18 at 16x hits the max(1, ...) floor', () {
      expect(downscaleRadius(18, 16), 1.0);
    });

    test('never returns less than 1 even for tiny radii', () {
      expect(downscaleRadius(0.5, 4), 1.0);
      expect(downscaleRadius(0, 4), 1.0);
    });
  });
}
