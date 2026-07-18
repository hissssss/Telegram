// Port of the dp()/dpf2() dimension helpers from
// `java/org/telegram/messenger/AndroidUtilities.java` (lines ~2708-2750).
//
// Android semantics (density == devicePixelRatio there):
//   dp(v)   = v == 0 ? 0 : (int) Math.ceil(density * v)   // int physical px
//   dpf2(v) = v == 0 ? 0 : density * v                    // float physical px
//
// Flutter lays out in *logical* pixels, so a literal `11.0` is already the
// analog of `dp(11)` — the engine applies the devicePixelRatio. The default
// [TgDimens.logical] mode is therefore a plain pass-through.
//
// The subtle difference is Android's ceil-rounding: `dp(0.4)` at density
// 2.625 is ceil(1.05) = 2 physical px (~0.762 logical px), while Flutter
// would rasterize 0.4 logical px to ~1 physical px. For pixel-parity work
// (hairline strokes, goldens vs Android captures) the opt-in
// [TgDimens.fidelity] mode reproduces Android's rounding at a given
// devicePixelRatio and converts the result back to logical pixels.
library;

import 'dart:typed_data';

/// Scratch buffer used to round doubles to IEEE-754 float32, matching Java's
/// 32-bit `float` arithmetic in `dp()`/`dpf2()`.
final Float32List _f32Buf = Float32List(1);

double _f32(double v) {
  _f32Buf[0] = v;
  return _f32Buf[0];
}

/// Multiplies [a] by [b] in float32 precision, exactly as a Java
/// `float * float` expression.
///
/// A single float32 operation performed in double precision and then rounded
/// back to float32 is exact (24-bit x 24-bit products fit in a 53-bit
/// mantissa), so this reproduces Java bit-for-bit.
double _f32Mul(double a, double b) => _f32(_f32(a) * _f32(b));

/// Dimension conversion with Android `AndroidUtilities.dp`/`dpf2` semantics.
///
/// Two modes:
///
/// * [TgDimens.logical] (default): dp values pass through unchanged as
///   Flutter logical pixels. This is what almost all code should use.
/// * [TgDimens.fidelity]: reproduces Android's physical-pixel math at a
///   given [devicePixelRatio] and converts back to logical pixels, so that
///   rasterized output lands on the same physical pixels as Android.
class TgDimens {
  /// Pass-through mode: `dp(v) == v` logical pixels.
  const TgDimens.logical()
      : fidelityRounding = false,
        devicePixelRatio = 1.0;

  /// Fidelity mode: reproduces Android's `ceil(density * v)` rounding at
  /// [devicePixelRatio] (the analog of Android's `density`).
  const TgDimens.fidelity({required this.devicePixelRatio})
      : fidelityRounding = true,
        assert(devicePixelRatio > 0);

  /// Whether Android ceil-rounding is emulated ([TgDimens.fidelity]).
  final bool fidelityRounding;

  /// The physical-per-logical pixel ratio used for fidelity rounding.
  /// Unused (1.0) in pass-through mode.
  final double devicePixelRatio;

  /// Shared pass-through instance.
  static const TgDimens passthrough = TgDimens.logical();

  /// Port of `AndroidUtilities.dp(value)`, returned in *logical* pixels.
  ///
  /// Pass-through mode: returns [value] unchanged.
  /// Fidelity mode: `ceil(devicePixelRatio * value) / devicePixelRatio` —
  /// i.e. Android's int physical-pixel result expressed in logical pixels.
  double dp(double value) {
    if (!fidelityRounding) {
      return value;
    }
    return dpPx(value) / devicePixelRatio;
  }

  /// Port of `AndroidUtilities.dpf2(value)`, returned in *logical* pixels.
  ///
  /// Android's `dpf2` is a plain float multiply with no rounding, so in
  /// logical pixels it is the identity in both modes (fidelity mode only
  /// applies Java float32 precision, which round-trips to the same double
  /// for all practical dp values).
  double dpf2(double value) {
    if (!fidelityRounding) {
      return value;
    }
    return dpf2Px(value) / devicePixelRatio;
  }

  /// Android `dp(value)` verbatim: int *physical* pixels, ceil-rounded.
  ///
  /// `value == 0 ? 0 : (int) Math.ceil(density * value)`, with the multiply
  /// performed in Java float32 precision.
  int dpPx(double value) {
    if (value == 0) {
      return 0;
    }
    return _f32Mul(devicePixelRatio, value).ceil();
  }

  /// Android `dpf2(value)` verbatim: float *physical* pixels, no rounding.
  ///
  /// `value == 0 ? 0 : density * value`, in Java float32 precision.
  double dpf2Px(double value) {
    if (value == 0) {
      return 0;
    }
    return _f32Mul(devicePixelRatio, value);
  }
}
