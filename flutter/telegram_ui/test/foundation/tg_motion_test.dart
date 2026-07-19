// Ring-1 tests for lib/src/foundation/tg_motion.dart.
//
// The constants table is asserted against spec_typography_motion.md §2 (all
// values verified against the cited Java lines); curve spot-checks use exact
// closed-form math where the curve is polynomial.

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/tg_curves.dart';
import 'package:telegram_ui/src/foundation/tg_motion.dart';

void main() {
  group('page transition (ActionBarLayout.java)', () {
    test('duration 150ms (:1839)', () {
      expect(TgMotion.pageDuration, const Duration(milliseconds: 150));
    });

    test('slide distance 48dp (:1901, :1916)', () {
      expect(TgMotion.pageSlide, 48.0);
    });

    test('pageCurve is DecelerateInterpolator(1.5) — f(t) = 1-(1-t)^3 (:577)',
        () {
      expect(TgMotion.pageCurve.factor, 1.5);
      // Exact polynomial values, not bezier approximations.
      expect(TgMotion.pageCurve.transform(0.5), 0.875);
      expect(TgMotion.pageCurve.transform(0.25), 0.578125);
      expect(TgMotion.pageCurve.transform(0.0), 0.0);
      expect(TgMotion.pageCurve.transform(1.0), 1.0);
    });

    test('scrim max 120*0.8/255 ≈ 37.6% black (:1214-1215)', () {
      expect(TgMotion.pageScrimMax, 96 / 255);
      expect(TgMotion.pageScrimMax, closeTo(0.376, 5e-4));
    });
  });

  group('bottom sheet (BottomSheet.java)', () {
    test('open 400ms EASE_OUT_QUINT with 20ms delay (:210-211, :1745)', () {
      expect(TgMotion.sheetOpenDuration, const Duration(milliseconds: 400));
      expect(TgMotion.sheetOpenDelay, const Duration(milliseconds: 20));
      expect(identical(TgMotion.sheetOpenCurve, TgCurves.easeOutQuint), isTrue);
    });

    test('close 250ms EASE_OUT (:2032-2033)', () {
      expect(TgMotion.sheetCloseDuration, const Duration(milliseconds: 250));
      expect(identical(TgMotion.sheetCloseCurve, TgCurves.easeOut), isTrue);
    });

    test('dim 51/255 = 20% black (:219)', () {
      expect(TgMotion.sheetDim, 51 / 255);
      expect(TgMotion.sheetDim, closeTo(0.2, 1e-12));
    });
  });

  group('alert dialog (AlertDialog.java + AlertDialogDecor.java)', () {
    test('dim 0.5 black (AlertDialog.java:210)', () {
      expect(TgMotion.dialogDim, 0.5);
    });

    test('window-parity fade 150ms; decor dim fade 300ms (Decor:39)', () {
      expect(TgMotion.dialogFadeDuration, const Duration(milliseconds: 150));
      expect(TgMotion.dialogDimDuration, const Duration(milliseconds: 300));
    });
  });

  group('popup menu (ActionBarPopupWindow.java)', () {
    test('open 150 + 16·n ms (:965), close 150ms (:69)', () {
      expect(TgMotion.menuOpenBase, const Duration(milliseconds: 150));
      expect(TgMotion.menuOpenPerItem, const Duration(milliseconds: 16));
      expect(TgMotion.menuCloseDuration, const Duration(milliseconds: 150));
    });

    test('menuOpenDuration scales with visible item count', () {
      expect(TgMotion.menuOpenDuration(0), const Duration(milliseconds: 150));
      expect(TgMotion.menuOpenDuration(1), const Duration(milliseconds: 166));
      expect(TgMotion.menuOpenDuration(4), const Duration(milliseconds: 214));
      expect(TgMotion.menuOpenDuration(10), const Duration(milliseconds: 310));
    });
  });

  group('curve aliases (CubicBezierInterpolator.java:11-22)', () {
    test('are the TgCurves instances — single source of truth', () {
      expect(identical(TgMotion.easeOut, TgCurves.easeOut), isTrue);
      expect(identical(TgMotion.easeOutQuint, TgCurves.easeOutQuint), isTrue);
      expect(identical(TgMotion.easeOutBack, TgCurves.easeOutBack), isTrue);
    });

    test('control points match the Java declarations', () {
      expect(TgMotion.easeOut.a, 0.0);
      expect(TgMotion.easeOut.b, 0.0);
      expect(TgMotion.easeOut.c, 0.58);
      expect(TgMotion.easeOut.d, 1.0);

      expect(TgMotion.easeOutQuint.a, 0.23);
      expect(TgMotion.easeOutQuint.b, 1.0);
      expect(TgMotion.easeOutQuint.c, 0.32);
      expect(TgMotion.easeOutQuint.d, 1.0);

      expect(TgMotion.easeOutBack.a, 0.34);
      expect(TgMotion.easeOutBack.b, 1.56);
      expect(TgMotion.easeOutBack.c, 0.64);
      expect(TgMotion.easeOutBack.d, 1.0);
    });
  });

  group('overshoot helper (android OvershootInterpolator)', () {
    test('starts at 0 and ends exactly at 1.0', () {
      expect(TgCurves.overshoot.transform(0.0), 0.0);
      expect(TgCurves.overshoot.transform(1.0), 1.0);
      expect(const TgOvershootInterpolator(tension: 1.02).transform(1.0), 1.0);
      expect(const TgOvershootInterpolator(tension: 1.3).transform(1.0), 1.0);
    });

    test('overshoots past 1.0 mid-flight, more with higher tension', () {
      final double lowPeak =
          const TgOvershootInterpolator(tension: 1.02).transform(5 / 9);
      final double highPeak = TgCurves.overshoot.transform(5 / 9);
      expect(lowPeak, greaterThan(1.0));
      expect(highPeak, greaterThan(lowPeak));
    });
  });
}
