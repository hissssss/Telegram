// Ring-1 tests for lib/src/foundation/color_math.dart.
//
// The solveSrcColor property test enforces the documented invariant from
// BlurredBackgroundProviderImpl.java:288-316:
//   compositeColors(solveSrcColor(bg, target, a), bg) == target
// within +/-1 per channel, for targets reachable at the given alpha.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/color_math.dart';

int _alphaOf(int c) => (c >> 24) & 0xFF;
int _redOf(int c) => (c >> 16) & 0xFF;
int _greenOf(int c) => (c >> 8) & 0xFF;
int _blueOf(int c) => c & 0xFF;
int _argb(int a, int r, int g, int b) => (a << 24) | (r << 16) | (g << 8) | b;

void main() {
  group('multAlpha (Theme.multAlpha)', () {
    test('multiply == 1 returns the color unchanged (Java shortcut)', () {
      expect(multAlpha(0x8012AB34, 1.0), 0x8012AB34);
      expect(multAlpha(0x00000000, 1.0), 0x00000000);
    });

    test('multiplies only the alpha channel, truncating like (int) cast', () {
      expect(multAlpha(0xFF112233, 0.5), 0x7F112233); // (int)(255*0.5) = 127
      expect(multAlpha(0xFF000000, 0.999), 0xFE000000); // 254.745 truncates to 254
      expect(multAlpha(0x80FFFFFF, 0.0), 0x00FFFFFF);
    });

    test('clamps the result to 0..255', () {
      expect(multAlpha(0x80000000, 3.0), 0xFF000000); // 384 -> 255
      expect(multAlpha(0x80123456, -1.0), 0x00123456); // -128 -> 0
    });

    test('accepts Java-style negative ints', () {
      expect(multAlpha(-1, 0.5), 0x7FFFFFFF); // -1 == 0xFFFFFFFF
    });
  });

  group('computePerceivedBrightness (AndroidUtilities)', () {
    test('white is 1, black is 0', () {
      expect(computePerceivedBrightness(0xFFFFFFFF), closeTo(1.0, 1e-9));
      expect(computePerceivedBrightness(0xFF000000), 0.0);
    });

    test('uses Rec. 709 weights and ignores alpha', () {
      // Pure green: 0.7152 exactly.
      expect(computePerceivedBrightness(0xFF00FF00), closeTo(0.7152, 1e-9));
      expect(
        computePerceivedBrightness(0x0000FF00),
        computePerceivedBrightness(0xFF00FF00),
      );
    });

    test('threshold constant is 0.721', () {
      expect(kDarkThemeBrightnessThreshold, 0.721);
    });

    test('grays straddling the 0.721 threshold classify correctly', () {
      // 183/255 = 0.71765 < 0.721 -> dark; 184/255 = 0.72157 >= 0.721 -> light.
      const int gray183 = 0xFFB7B7B7;
      const int gray184 = 0xFFB8B8B8;
      expect(computePerceivedBrightness(gray183), lessThan(kDarkThemeBrightnessThreshold));
      expect(
        computePerceivedBrightness(gray184),
        greaterThanOrEqualTo(kDarkThemeBrightnessThreshold),
      );
      expect(isDarkColor(gray183), isTrue);
      expect(isDarkColor(gray184), isFalse);
    });

    test('the default day/night window backgrounds classify correctly', () {
      expect(isDarkColor(0xFFFFFFFF), isFalse); // windowBackgroundWhite (day)
      expect(isDarkColor(0xFF1A1D21), isTrue); // DEFAULT_BLACK_TEXT-style dark
    });
  });

  group('compositeColors (androidx ColorUtils int math)', () {
    test('opaque foreground wins entirely', () {
      expect(compositeColors(0xFF123456, 0xFFABCDEF), 0xFF123456);
    });

    test('transparent foreground leaves the background', () {
      expect(compositeColors(0x00123456, 0xFFABCDEF), 0xFFABCDEF);
    });

    test('50% red over opaque blue (exact Java truncation)', () {
      expect(compositeColors(0x80FF0000, 0xFF0000FF), 0xFF80007F);
    });

    test('translucent over translucent', () {
      expect(compositeColors(0x80808080, 0x80000000), 0xC0555555);
    });

    test('fully transparent over fully transparent is 0', () {
      expect(compositeColors(0x00000000, 0x00000000), 0x00000000);
    });
  });

  group('solveSrcColor (BlurredBackgroundProviderImpl:288-316)', () {
    test('alpha <= 0 returns transparent black', () {
      expect(solveSrcColor(0xFFFFFFFF, 0xFF808080, 0.0), 0x00000000);
      expect(solveSrcColor(0xFFFFFFFF, 0xFF808080, -0.5), 0x00000000);
    });

    test('alpha >= 1 returns the target forced opaque', () {
      expect(solveSrcColor(0xFFFFFFFF, 0x00123456, 1.0), 0xFF123456);
      expect(solveSrcColor(0xFF000000, 0xFFABCDEF, 2.0), 0xFFABCDEF);
    });

    test('known value: mid-gray over white at alpha 0.5', () {
      // src = round((128 - 255*0.5)/0.5) = 1 per channel, a8 = round(127.5) = 128.
      expect(solveSrcColor(0xFFFFFFFF, 0xFF808080, 0.5), 0x80010101);
    });

    test('known value: near-white target over white at the glass alpha 0.85', () {
      expect(solveSrcColor(0xFFFFFFFF, 0xFFF0F4F7, 0.85), 0xD9EDF2F6);
    });

    test('clamps unreachable channels to 0..255', () {
      // Solving black over white at low alpha demands a negative src.
      final int solved = solveSrcColor(0xFFFFFFFF, 0xFF000000, 0.1);
      expect(_redOf(solved), 0);
      expect(_greenOf(solved), 0);
      expect(_blueOf(solved), 0);
      expect(_alphaOf(solved), 26); // round(0.1 * 255) = 25.5 -> 26
    });

    test(
        'property: composite(solve(bg, t, a), bg) == t within +/-1 per channel '
        'over 200 seeded random reachable cases', () {
      final Random rng = Random(20260718); // fixed seed
      for (int i = 0; i < 200; i++) {
        final int bg = _argb(255, rng.nextInt(256), rng.nextInt(256), rng.nextInt(256));
        final double a = 0.05 + rng.nextDouble() * 0.90;
        final int a8 = (a * 255.0 + 0.5).floor();
        // Construct a target that is reachable at alpha a by compositing a
        // random src — mirrors how the presets produce their target colors.
        final int src = _argb(a8, rng.nextInt(256), rng.nextInt(256), rng.nextInt(256));
        final int target = compositeColors(src, bg);

        final int solved = solveSrcColor(bg, target, a);
        final int result = compositeColors(solved, bg);

        expect(_alphaOf(result), 255, reason: 'case $i: result must stay opaque');
        expect(
          (_redOf(result) - _redOf(target)).abs(),
          lessThanOrEqualTo(1),
          reason: 'case $i red: bg=0x${bg.toRadixString(16)} a=$a',
        );
        expect(
          (_greenOf(result) - _greenOf(target)).abs(),
          lessThanOrEqualTo(1),
          reason: 'case $i green: bg=0x${bg.toRadixString(16)} a=$a',
        );
        expect(
          (_blueOf(result) - _blueOf(target)).abs(),
          lessThanOrEqualTo(1),
          reason: 'case $i blue: bg=0x${bg.toRadixString(16)} a=$a',
        );
      }
    });
  });
}
