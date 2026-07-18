// Integer ARGB color math ported from the Android sources.
//
// All colors are 32-bit ARGB ints in the 0xAARRGGBB layout used by
// `android.graphics.Color` and the Telegram theme tables. Inputs are
// normalized with `& 0xFFFFFFFF` so Java-style negative ints (e.g. -1 for
// white) are accepted; outputs are always unsigned (0 .. 0xFFFFFFFF).
//
// Ports:
// - `Theme.multAlpha`            (ui/ActionBar/Theme.java:2012-2016)
// - `AndroidUtilities.computePerceivedBrightness` (AndroidUtilities.java:4973-4975)
// - `ColorUtils.compositeColors` (androidx.core.graphics.ColorUtils, exact int math)
// - `BlurredBackgroundProviderImpl.solveSrcColor`
//   (ui/Components/blur3/drawable/color/impl/BlurredBackgroundProviderImpl.java:288-316)
library;

/// Dark-theme threshold used by the glass color providers:
/// a surface color is "dark" when
/// `computePerceivedBrightness(color) < kDarkThemeBrightnessThreshold`
/// (BlurredBackgroundColorProviderThemed.java:34-37).
const double kDarkThemeBrightnessThreshold = 0.721;

int _alpha(int color) => (color >> 24) & 0xFF;
int _red(int color) => (color >> 16) & 0xFF;
int _green(int color) => (color >> 8) & 0xFF;
int _blue(int color) => color & 0xFF;

int _argb(int a, int r, int g, int b) => ((a & 0xFF) << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);

/// Java `Math.round(float)`: `floor(v + 0.5)`.
///
/// Differs from Dart's `round()` (half away from zero) only for negative
/// half-values, which the callers below clamp away anyway; kept verbatim for
/// fidelity.
int _roundJava(double v) => (v + 0.5).floor();

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Port of `Theme.multAlpha(int color, float multiply)`.
///
/// Multiplies only the alpha channel; RGB is untouched. Matches Java exactly,
/// including the `(int)` truncation of `alpha * multiply` and the identity
/// shortcut for `multiply == 1`.
int multAlpha(int color, double multiply) {
  color &= 0xFFFFFFFF;
  if (multiply == 1.0) {
    return color;
  }
  // ColorUtils.setAlphaComponent(color, clamp((int) (alpha * multiply), 0, 0xFF))
  final int alpha = _clampInt((_alpha(color) * multiply).truncate(), 0, 0xFF);
  return (color & 0x00FFFFFF) | (alpha << 24);
}

/// Port of `AndroidUtilities.computePerceivedBrightness(int color)`:
/// `(0.2126*R + 0.7152*G + 0.0722*B) / 255` (Rec. 709 luma; alpha ignored).
double computePerceivedBrightness(int color) {
  color &= 0xFFFFFFFF;
  return (_red(color) * 0.2126 + _green(color) * 0.7152 + _blue(color) * 0.0722) / 255.0;
}

/// Whether [color] counts as a dark surface for glass theming:
/// `computePerceivedBrightness(color) < 0.721`
/// (BlurredBackgroundColorProviderThemed.java:34-37).
bool isDarkColor(int color) => computePerceivedBrightness(color) < kDarkThemeBrightnessThreshold;

/// Port of `androidx.core.graphics.ColorUtils.compositeColors(fg, bg)` —
/// src-over composite of [foreground] over [background] in exact Java int
/// arithmetic (truncating division).
int compositeColors(int foreground, int background) {
  foreground &= 0xFFFFFFFF;
  background &= 0xFFFFFFFF;
  final int bgAlpha = _alpha(background);
  final int fgAlpha = _alpha(foreground);
  final int a = _compositeAlpha(fgAlpha, bgAlpha);
  final int r = _compositeComponent(_red(foreground), fgAlpha, _red(background), bgAlpha, a);
  final int g = _compositeComponent(_green(foreground), fgAlpha, _green(background), bgAlpha, a);
  final int b = _compositeComponent(_blue(foreground), fgAlpha, _blue(background), bgAlpha, a);
  return _argb(a, r, g, b);
}

int _compositeAlpha(int foregroundAlpha, int backgroundAlpha) =>
    0xFF - (((0xFF - backgroundAlpha) * (0xFF - foregroundAlpha)) ~/ 0xFF);

int _compositeComponent(int fgC, int fgA, int bgC, int bgA, int a) {
  if (a == 0) {
    return 0;
  }
  return ((0xFF * fgC * fgA) + (bgC * bgA * (0xFF - fgA))) ~/ (a * 0xFF);
}

/// Port of `BlurredBackgroundProviderImpl.solveSrcColor(bgColor, outColor, alpha)`
/// (lines 288-316).
///
/// Inverse-solves src-over compositing: returns the `src` color (with alpha
/// `round(alpha * 255)`) such that painting `src` over the opaque [bgColor]
/// lands on [outColor]:
///
///   `compositeColors(solveSrcColor(bg, target, a), bg) == target`
///   (within +/-1 per channel — the documented invariant, property-tested).
///
/// Per channel: `src = clamp(round((out - bg * (1 - a)) / a), 0, 255)`.
/// Edge cases: `a <= 0` returns fully transparent black (0x00000000);
/// `a >= 1` returns [outColor] forced opaque. Only the RGB of [bgColor] and
/// [outColor] are read (their alphas are ignored, as in Java).
int solveSrcColor(int bgColor, int outColor, double alpha) {
  bgColor &= 0xFFFFFFFF;
  outColor &= 0xFFFFFFFF;
  alpha = alpha < 0 ? 0 : (alpha > 1 ? 1 : alpha);

  // Edge cases.
  if (alpha <= 0) {
    return 0x00000000;
  }
  if (alpha >= 1) {
    return _argb(255, _red(outColor), _green(outColor), _blue(outColor));
  }

  final int bgR = _red(bgColor);
  final int bgG = _green(bgColor);
  final int bgB = _blue(bgColor);

  final int outR = _red(outColor);
  final int outG = _green(outColor);
  final int outB = _blue(outColor);

  final double invA = 1.0 - alpha;

  final int srcR = _clampInt(_roundJava((outR - bgR * invA) / alpha), 0, 255);
  final int srcG = _clampInt(_roundJava((outG - bgG * invA) / alpha), 0, 255);
  final int srcB = _clampInt(_roundJava((outB - bgB * invA) / alpha), 0, 255);

  final int a8 = _clampInt(_roundJava(alpha * 255.0), 0, 255);

  return _argb(a8, srcR, srcG, srcB);
}
