// Ring-1 tests for lib/src/foundation/dimens.dart — Android dp()/dpf2()
// semantics (AndroidUtilities.java ~2708-2750) vs Flutter logical pixels.

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/dimens.dart';

void main() {
  group('TgDimens.logical (pass-through, the default)', () {
    const TgDimens d = TgDimens.logical();

    test('dp and dpf2 are the identity in logical pixels', () {
      expect(d.dp(11), 11.0);
      expect(d.dp(0.4), 0.4);
      expect(d.dpf2(38.34), 38.34);
      expect(d.dp(0), 0.0);
      expect(d.dpf2(0), 0.0);
    });

    test('shared passthrough instance matches', () {
      expect(TgDimens.passthrough.fidelityRounding, isFalse);
      expect(TgDimens.passthrough.dp(7.666), 7.666);
    });
  });

  group('TgDimens.fidelity — Android physical-pixel math', () {
    test('dpPx reproduces dp(v) = ceil(density * v) at dpr 2.625', () {
      const TgDimens d = TgDimens.fidelity(devicePixelRatio: 2.625);
      expect(d.dpPx(0.4), 2); // ceil(1.05) — the hairline-stroke case
      expect(d.dpPx(11), 29); // ceil(28.875)
      expect(d.dpPx(1), 3); // ceil(2.625)
      expect(d.dpPx(0), 0); // Java early-return for 0
    });

    test('dp returns the ceil-rounded result converted back to logical px', () {
      const TgDimens d = TgDimens.fidelity(devicePixelRatio: 2.625);
      expect(d.dp(0.4), closeTo(2 / 2.625, 1e-12));
      expect(d.dp(11), closeTo(29 / 2.625, 1e-12));
      expect(d.dp(0), 0.0);
    });

    test('dpf2 is a float multiply with no rounding', () {
      const TgDimens d = TgDimens.fidelity(devicePixelRatio: 2.625);
      expect(d.dpf2Px(11), closeTo(28.875, 1e-6));
      expect(d.dpf2Px(0.4), closeTo(1.05, 1e-6));
      expect(d.dpf2(11), closeTo(11.0, 1e-6));
      expect(d.dpf2Px(0), 0.0);
    });

    test('uses Java float32 arithmetic, not double (dpr 2.6 * 5)', () {
      // In double math 2.6 * 5 = 13.000000000000002 -> ceil = 14, but Java
      // computes 2.6f * 5f = exactly 13.0f -> ceil = 13. The float32
      // emulation must match Java.
      const TgDimens d = TgDimens.fidelity(devicePixelRatio: 2.6);
      expect(d.dpPx(5), 13);
    });

    test('dpPx at dpr 3.0 matches Android for common metrics', () {
      const TgDimens d = TgDimens.fidelity(devicePixelRatio: 3.0);
      expect(d.dpPx(56), 168); // tab bar height
      expect(d.dpPx(0.667), 3); // bottom stroke ceil(2.001)
      expect(d.dpf2Px(2 / 3), closeTo(2.0, 1e-6));
    });
  });
}
