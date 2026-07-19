// Animation curves and the BoolFactor animator ported from
// `java/org/telegram/ui/Components/CubicBezierInterpolator.java` (lines 11-22),
// Android's `android.view.animation.DecelerateInterpolator` and
// `android.view.animation.OvershootInterpolator`, and the
// `BoolAnimator` / `AnimatedFloat` pattern
// (me/vkryl/android/animator/BoolAnimator.java,
//  org/telegram/ui/Components/AnimatedFloat.java).
//
// Flutter's [Cubic] and Java's CubicBezierInterpolator solve the same
// cubic bezier with different numeric methods (bisection vs Newton), both to
// ~1e-3 tolerance; spot values agree within ~2e-3.
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart' show Cubic, Curve;

/// The Telegram cubic-bezier interpolator constants
/// (CubicBezierInterpolator.java:11-14).
abstract final class TgCurves {
  /// `DEFAULT = (0.25, 0.1, 0.25, 1)` — the CSS `ease` curve. Used for
  /// modal fades (200-250ms) and as the AnimatedFloat default.
  static const Cubic defaultCubic = Cubic(0.25, 0.1, 0.25, 1.0);

  /// `EASE_OUT = (0, 0, 0.58, 1)`.
  static const Cubic easeOut = Cubic(0.0, 0.0, 0.58, 1.0);

  /// `EASE_OUT_QUINT = (0.23, 1, 0.32, 1)` — the structural/emphasis curve
  /// (380ms) and width/color-tracking curve (320ms).
  static const Cubic easeOutQuint = Cubic(0.23, 1.0, 0.32, 1.0);

  /// `EASE_IN = (0.42, 0, 1, 1)`.
  static const Cubic easeIn = Cubic(0.42, 0.0, 1.0, 1.0);

  /// `EASE_BOTH = (0.42, 0, 0.58, 1)` (CubicBezierInterpolator.java:15) —
  /// the CSS `ease-in-out` curve, e.g. the text-field underline activation
  /// (EditTextBoldCursor.java:994-1022, 150ms).
  static const Cubic easeBoth = Cubic(0.42, 0.0, 0.58, 1.0);

  /// `EASE_OUT_BACK = (.34, 1.56, .64, 1)` (CubicBezierInterpolator.java:16)
  /// — overshooting settle; identical control points to Flutter's
  /// `Curves.easeOutBack`.
  static const Cubic easeOutBack = Cubic(0.34, 1.56, 0.64, 1.0);

  /// `StandardDecelerate = PathInterpolator(0, 0, 0, 1)`
  /// (CubicBezierInterpolator.java:22) — the Material "standard decelerate";
  /// drives the predictive-back peel (ActionBarLayout.java:1577-1583).
  static const Cubic standardDecelerate = Cubic(0.0, 0.0, 0.0, 1.0);

  /// Android `new DecelerateInterpolator()` — `f(t) = 1 - (1 - t)^2`.
  /// Used e.g. for the tab selection pill (320ms DECELERATE).
  static const TgDecelerateCurve decelerate = TgDecelerateCurve();

  /// Android `new DecelerateInterpolator(2)` — `f(t) = 1 - (1 - t)^4`.
  static const TgDecelerateCurve decelerateFactor2 = TgDecelerateCurve(factor: 2.0);

  /// Android `new OvershootInterpolator()` at the default tension 2.0.
  /// Telegram instantiates other tensions inline — 1.02 for fragment preview
  /// (ActionBarLayout.java:578), 1.2/2.0 in ButtonWithCounterView, 1.3 for
  /// the spinner-dialog pop (AlertDialog.java:330) — via
  /// `TgOvershootInterpolator(tension: t)`.
  static const TgOvershootInterpolator overshoot = TgOvershootInterpolator();
}

/// Port of Android's `android.view.animation.DecelerateInterpolator`.
///
/// `factor == 1`: `f(t) = 1 - (1 - t) * (1 - t)`
/// otherwise:     `f(t) = 1 - (1 - t)^(2 * factor)`
class TgDecelerateCurve extends Curve {
  const TgDecelerateCurve({this.factor = 1.0});

  /// Android's `mFactor` constructor argument.
  final double factor;

  @override
  double transformInternal(double t) {
    if (factor == 1.0) {
      return 1.0 - (1.0 - t) * (1.0 - t);
    }
    return 1.0 - math.pow(1.0 - t, 2.0 * factor).toDouble();
  }
}

/// Port of Android's `android.view.animation.OvershootInterpolator`:
///
/// `f(t) = (t - 1)^2 * ((T + 1) * (t - 1) + T) + 1`
///
/// Starts at 0, flings past 1.0 (peak grows with [tension]) and settles back
/// to exactly 1.0 at `t = 1`. Android's default tension is 2.0.
///
/// Named after the Android class because the attach sheet predates this
/// foundation port with a file-local `TgOvershootCurve` of identical math
/// (`components/attach/tg_attach_sheet.dart`) — consolidating the two is an
/// integration-wave cleanup; new code uses this one.
class TgOvershootInterpolator extends Curve {
  const TgOvershootInterpolator({this.tension = 2.0});

  /// Android's `mTension` constructor argument.
  final double tension;

  @override
  double transformInternal(double t) {
    final double u = t - 1.0;
    return u * u * ((tension + 1.0) * u + tension) + 1.0;
  }
}

/// A 0..1 factor that animates toward a boolean target — the pure-Dart analog
/// of `BoolAnimator` (me/vkryl/android/animator/BoolAnimator.java) driven with
/// `AnimatedFloat`-style explicit time.
///
/// No widgets, no tickers, no wall clock: the owner feeds monotonic
/// timestamps through [tick] (e.g. from a `Ticker`'s elapsed duration, or a
/// fake clock in tests). [onChanged] fires whenever [factor] changes — from a
/// tick or from an unanimated snap — mirroring BoolAnimator's
/// `view.invalidate()` callback.
///
/// Retargeting mid-flight restarts the animation from the current factor
/// toward the new target over the full [duration], matching
/// `AnimatedFloat.set` / `FactorAnimator.animateTo`.
class BoolFactor {
  BoolFactor({
    bool value = false,
    this.duration = const Duration(milliseconds: 200),
    this.curve = TgCurves.defaultCubic,
    this.onChanged,
  })  : _target = value,
        _factor = value ? 1.0 : 0.0;

  /// Total animation duration (BoolAnimator's `duration`).
  /// A zero or negative duration makes every [set] an immediate snap.
  Duration duration;

  /// Interpolator applied to normalized time (BoolAnimator's `interpolator`).
  Curve curve;

  /// Fired whenever [factor] changes value.
  void Function(double factor)? onChanged;

  bool _target;
  double _factor;

  bool _animating = false;
  double _startFactor = 0.0;
  Duration _animStart = Duration.zero;
  Duration _now = Duration.zero;

  /// The boolean target currently animated toward (BoolAnimator `getValue()`).
  bool get target => _target;

  /// The current animated factor in 0..1 (BoolAnimator `getFloatValue()`).
  double get factor => _factor;

  /// Whether an animation is in flight (BoolAnimator `isAnimating()`).
  bool get isAnimating => _animating;

  /// Advances the clock to the monotonic timestamp [now] and updates
  /// [factor]. Returns the current factor.
  ///
  /// Timestamps must be non-decreasing across calls; [set] uses the most
  /// recent timestamp as the animation start time.
  double tick(Duration now) {
    assert(now >= _now, 'BoolFactor.tick timestamps must be monotonic');
    _now = now;
    if (_animating) {
      final int elapsedUs = (now - _animStart).inMicroseconds;
      final int durationUs = duration.inMicroseconds;
      double t = durationUs <= 0 ? 1.0 : elapsedUs / durationUs;
      t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
      final double targetFactor = _target ? 1.0 : 0.0;
      final double next = lerpDouble(_startFactor, targetFactor, curve.transform(t))!;
      if (t >= 1.0) {
        _animating = false;
      }
      _setFactor(next);
    }
    return _factor;
  }

  /// Port of `BoolAnimator.setValue(value, animated)`.
  ///
  /// Animated set toward the current target is a no-op; an unanimated set
  /// always snaps (also cancelling any running animation), exactly as in
  /// Java (`if (this.value != value || !animated)`).
  void set(bool value, {bool animated = true}) {
    if (_target == value && animated) {
      return;
    }
    _target = value;
    final double targetFactor = value ? 1.0 : 0.0;
    if (animated && duration > Duration.zero) {
      if (_factor == targetFactor) {
        _animating = false;
        return;
      }
      _animating = true;
      _startFactor = _factor;
      _animStart = _now;
    } else {
      _animating = false;
      _setFactor(targetFactor);
    }
  }

  /// Port of `BoolAnimator.toggleValue(animated)`; returns the new target.
  bool toggle({bool animated = true}) {
    set(!_target, animated: animated);
    return _target;
  }

  /// Port of `BoolAnimator.forceValue(value, floatValue)`: pins both the
  /// boolean target and the factor without animating.
  void force(bool value, [double? factor]) {
    _target = value;
    _animating = false;
    _setFactor((factor ?? (value ? 1.0 : 0.0)).clamp(0.0, 1.0));
  }

  void _setFactor(double next) {
    if (next != _factor) {
      _factor = next;
      onChanged?.call(next);
    }
  }
}
