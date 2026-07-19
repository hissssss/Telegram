// Port of `ui/Components/RadialProgressView.java` (spec_primitives.md §4.1):
// the standalone 40dp spinner — a 3dp round-cap arc in `progressCircle` that
// rotates one revolution per 2s while its sweep alternates 500ms grow/shrink
// phases (indeterminate) or eases to `max(4°, 360°·progress)` over 200ms
// (determinate), with an optional `toCircle` morph to a full ring.
//
// Faithful details:
// - arc box 40dp centered in the widget's bounds (RadialProgressView.java:63,
//   228-231; the AlertDialog spinner recipe overrides to 32dp,
//   AlertDialog.java:886);
// - 3dp STROKE, round cap, key `progressCircle` (RadialProgressView.java:65,
//   68-72);
// - the whole state machine of `updateAnimation(long dt)`
//   (RadialProgressView.java:133-203) is ported verbatim into
//   [TgRadialProgressAnimation.update], including the +270° offset jump with
//   `circleLength = -266` (negative sweeps draw counter-clockwise, same as
//   Android), the frozen phase clock during the toCircle blend, and the
//   `max(4°, ...)` determinate floor;
// - the per-frame `dt` clamp to 17ms lives in the widget's ticker
//   (`if (dt > 17) dt = 17`, RadialProgressView.java:126-128) — the pure
//   state machine takes dt unclamped so tests can drive exact times.
//
// Divergence: the Java advances `toCircleProgress` by a fixed `16 / 220f`
// (in) / `16 / 400f` (out) per invalidation (RadialProgressView.java:138-148)
// — a ~60fps frame assumption; the port advances by `dt / 220` / `dt / 400`
// for the same 220ms/400ms totals independent of frame rate (with the 17ms
// dt clamp the two agree to within ~6%).
//
// Deliberately NOT ported: `setUseSelfAlpha`/`setAlpha` background plumbing
// (RadialProgressView.java:75-91) and `sync` (RadialProgressView.java:106-121).
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';

import '../foundation/tg_curves.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Default arc box: 40dp (`size = AndroidUtilities.dp(40)`,
/// RadialProgressView.java:63).
const double kTgRadialProgressSize = 40.0;

/// The AlertDialog SPINNER recipe's arc box: 32dp
/// (`progressView.setSize(dp(32))`, AlertDialog.java:886).
const double kTgRadialProgressDialogSize = 32.0;

/// Stroke width: 3dp (`setStrokeWidth(AndroidUtilities.dp(3))`,
/// RadialProgressView.java:71).
const double kTgRadialProgressStrokeWidth = 3.0;

/// One full rotation every 2000ms (`rotationTime`,
/// RadialProgressView.java:41; `radOffset += 360 * dt / rotationTime`,
/// RadialProgressView.java:134).
const double kTgRadialProgressRotationTimeMs = 2000.0;

/// Each indeterminate grow/shrink phase lasts 500ms (`risingTime`,
/// RadialProgressView.java:42).
const double kTgRadialProgressRisingTimeMs = 500.0;

/// Minimum sweep: 4° (RadialProgressView.java:157, 159, 200).
const double kTgRadialProgressMinSweepDeg = 4.0;

/// The grow phase adds up to 266° over the accelerate curve
/// (`4 + 266 * accelerate(t)`, RadialProgressView.java:157).
const double kTgRadialProgressGrowSweepDeg = 266.0;

/// The shrink phase spans 270° over the decelerate curve
/// (`4 - 270 * (1 - decelerate(t))`, RadialProgressView.java:159).
const double kTgRadialProgressShrinkSweepDeg = 270.0;

/// Offset jump between phases: +270° (`radOffset += 270`,
/// RadialProgressView.java:164).
const double kTgRadialProgressOffsetJumpDeg = 270.0;

/// Determinate progress eases over 200ms decelerate
/// (RadialProgressView.java:193-197).
const double kTgRadialProgressProgressTimeMs = 200.0;

/// `toCircle` morph in: 220ms (`toCircleProgress += 16 / 220f`,
/// RadialProgressView.java:139).
const double kTgRadialProgressToCircleInMs = 220.0;

/// `toCircle` morph out: 400ms (`toCircleProgress -= 16 / 400f`,
/// RadialProgressView.java:144).
const double kTgRadialProgressToCircleOutMs = 400.0;

/// Per-frame dt clamp: 17ms (`if (dt > 17) dt = 17`,
/// RadialProgressView.java:126-128).
const double kTgRadialProgressMaxFrameMs = 17.0;

/// Android `new AccelerateInterpolator()` — `f(t) = t * t`
/// (RadialProgressView.java:39, 67, 157).
double _accelerate(double t) => t * t;

/// The `RadialProgressView` animation state machine — a widget-free port of
/// `updateAnimation(long dt)` (RadialProgressView.java:133-203) plus the
/// mode setters, driven by explicit dt like [BoolFactor].
///
/// Angles are degrees. [circleLength] (the sweep) may be negative — the
/// shrink phase runs `-266° → 4°` and negative sweeps draw
/// counter-clockwise from [radOffset], exactly as `Canvas.drawArc` does on
/// both platforms.
class TgRadialProgressAnimation {
  /// Fields start at the Java defaults: `radOffset = 0`,
  /// `currentCircleLength = 0`, `risingCircleLength = false`,
  /// `noProgress = true` (RadialProgressView.java:27-52).
  TgRadialProgressAnimation();

  /// Arc start angle in degrees, wrapped into `[0, 360)` at each update
  /// (`radOffset`, RadialProgressView.java:134-136 — jumps from
  /// RadialProgressView.java:164, 177, 185 land after the wrap and are
  /// wrapped on the next update).
  double radOffset = 0.0;

  /// Signed sweep in degrees (`currentCircleLength`,
  /// RadialProgressView.java:29).
  double circleLength = 0.0;

  /// Whether the indeterminate cycle is in its grow phase
  /// (`risingCircleLength`, RadialProgressView.java:30).
  bool risingCircleLength = false;

  /// Phase clock in ms (`currentProgressTime`, RadialProgressView.java:31).
  double currentProgressTime = 0.0;

  /// Indeterminate mode flag (`noProgress = true` default,
  /// RadialProgressView.java:52; `setNoProgress`,
  /// RadialProgressView.java:93-95).
  bool noProgress = true;

  /// Eased, displayed progress (`animatedProgress`,
  /// RadialProgressView.java:48).
  double animatedProgress = 0.0;

  double _currentProgress = 0.0;
  double _progressAnimationStart = 0.0;
  double _progressTime = 0.0;

  bool _toCircle = false;

  /// The morph factor 0..1 (`toCircleProgress`, RadialProgressView.java:50).
  double toCircleProgress = 0.0;

  /// The determinate target (`currentProgress`, RadialProgressView.java:45).
  double get progress => _currentProgress;

  /// Port of `setProgress(float)` (RadialProgressView.java:97-104): eases
  /// upward over 200ms; a lower value snaps the displayed progress down
  /// before easing.
  void setProgress(double value) {
    _currentProgress = value;
    if (animatedProgress > value) {
      animatedProgress = value;
    }
    _progressAnimationStart = animatedProgress;
    _progressTime = 0.0;
  }

  /// Port of `toCircle(boolean, boolean)` (RadialProgressView.java:219-224).
  void toCircle(bool toCircle, {bool animated = true}) {
    _toCircle = toCircle;
    if (!animated) {
      toCircleProgress = toCircle ? 1.0 : 0.0;
    }
  }

  /// Port of `isCircle()` (RadialProgressView.java:241-243).
  bool get isCircle => circleLength.abs() >= 360.0;

  /// Port of `updateAnimation(long dt)` (RadialProgressView.java:133-203).
  /// [dtMs] is unclamped here; the widget clamps to
  /// [kTgRadialProgressMaxFrameMs] per frame (RadialProgressView.java:126-128).
  void update(double dtMs) {
    // Rotation: 360°/2s, wrapped (RadialProgressView.java:134-136).
    radOffset += 360.0 * dtMs / kTgRadialProgressRotationTimeMs;
    final int count = radOffset ~/ 360.0;
    radOffset -= count * 360.0;

    // toCircle morph (RadialProgressView.java:138-148; dt-based, see the
    // library divergence note).
    if (_toCircle && toCircleProgress != 1.0) {
      toCircleProgress += dtMs / kTgRadialProgressToCircleInMs;
      if (toCircleProgress > 1.0) {
        toCircleProgress = 1.0;
      }
    } else if (!_toCircle && toCircleProgress != 0.0) {
      toCircleProgress -= dtMs / kTgRadialProgressToCircleOutMs;
      if (toCircleProgress < 0.0) {
        toCircleProgress = 0.0;
      }
    }

    if (noProgress) {
      if (toCircleProgress == 0.0) {
        // Plain indeterminate cycle (RadialProgressView.java:151-169).
        currentProgressTime += dtMs;
        if (currentProgressTime >= kTgRadialProgressRisingTimeMs) {
          currentProgressTime = kTgRadialProgressRisingTimeMs;
        }
        final double t = currentProgressTime / kTgRadialProgressRisingTimeMs;
        if (risingCircleLength) {
          circleLength = kTgRadialProgressMinSweepDeg +
              kTgRadialProgressGrowSweepDeg * _accelerate(t);
        } else {
          circleLength = kTgRadialProgressMinSweepDeg -
              kTgRadialProgressShrinkSweepDeg *
                  (1.0 - TgCurves.decelerate.transform(t));
        }
        if (currentProgressTime == kTgRadialProgressRisingTimeMs) {
          if (risingCircleLength) {
            radOffset += kTgRadialProgressOffsetJumpDeg;
            circleLength = -kTgRadialProgressGrowSweepDeg;
          }
          risingCircleLength = !risingCircleLength;
          currentProgressTime = 0.0;
        }
      } else {
        // toCircle blend: the phase clock is frozen while the morph adds
        // 360°/364° of sweep (RadialProgressView.java:170-188).
        final double t = currentProgressTime / kTgRadialProgressRisingTimeMs;
        if (risingCircleLength) {
          final double old = circleLength;
          circleLength = kTgRadialProgressMinSweepDeg +
              kTgRadialProgressGrowSweepDeg * _accelerate(t);
          circleLength += 360.0 * toCircleProgress;
          final double dx = old - circleLength;
          if (dx > 0.0) {
            radOffset += dx;
          }
        } else {
          final double old = circleLength;
          circleLength = kTgRadialProgressMinSweepDeg -
              kTgRadialProgressShrinkSweepDeg *
                  (1.0 - TgCurves.decelerate.transform(t));
          circleLength -= 364.0 * toCircleProgress;
          final double dx = old - circleLength;
          if (dx > 0.0) {
            radOffset += dx;
          }
        }
      }
    } else {
      // Determinate: 200ms decelerate toward currentProgress, 4° floor
      // (RadialProgressView.java:189-201).
      final double progressDiff = _currentProgress - _progressAnimationStart;
      if (progressDiff > 0.0) {
        _progressTime += dtMs;
        if (_progressTime >= kTgRadialProgressProgressTimeMs) {
          animatedProgress = _progressAnimationStart = _currentProgress;
          _progressTime = 0.0;
        } else {
          animatedProgress = _progressAnimationStart +
              progressDiff *
                  TgCurves.decelerate.transform(
                    _progressTime / kTgRadialProgressProgressTimeMs,
                  );
        }
      }
      circleLength =
          math.max(kTgRadialProgressMinSweepDeg, 360.0 * animatedProgress);
    }
  }
}

/// The `RadialProgressView.onDraw` port (RadialProgressView.java:226-233):
/// one round-cap stroke arc from [radOffset] sweeping [circleLength]
/// degrees, in an [arcSize] square centered in the canvas.
class TgRadialProgressPainter extends CustomPainter {
  TgRadialProgressPainter({
    required this.radOffset,
    required this.circleLength,
    required this.color,
    this.arcSize = kTgRadialProgressSize,
    this.strokeWidth = kTgRadialProgressStrokeWidth,
    super.repaint,
  });

  /// Arc start angle in degrees (RadialProgressView.java:231).
  final double radOffset;

  /// Signed sweep in degrees; negative draws counter-clockwise
  /// (RadialProgressView.java:231).
  final double circleLength;

  /// Resolved arc color — `progressCircle` by default at the widget level
  /// (RadialProgressView.java:65, 72).
  final Color color;

  /// Arc box side (`size`, RadialProgressView.java:63).
  final double arcSize;

  /// Stroke width (RadialProgressView.java:71).
  final double strokeWidth;

  /// The arc's oval: an [arcSize] square centered in [size]
  /// (`(getMeasuredWidth() - size) / 2`, RadialProgressView.java:228-230).
  Rect arcRect(Size size) {
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: arcSize,
      height: arcSize,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      // STROKE + round cap (RadialProgressView.java:69-70).
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = color;
    canvas.drawArc(
      arcRect(size),
      radOffset * math.pi / 180.0,
      circleLength * math.pi / 180.0,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(TgRadialProgressPainter oldDelegate) {
    return oldDelegate.radOffset != radOffset ||
        oldDelegate.circleLength != circleLength ||
        oldDelegate.color != color ||
        oldDelegate.arcSize != arcSize ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// The `ui/Components/RadialProgressView.java` port — the standalone
/// Telegram spinner.
///
/// Controlled widget: a null [progress] runs the indeterminate cycle
/// (`noProgress`, the Java default); a non-null [progress] eases toward the
/// value over 200ms while the rotation keeps spinning; [toCircle] morphs the
/// arc into a full ring (220ms in / 400ms out). Programmatic changes
/// animate.
///
/// Sizes itself to a [size] square (the Java arc box; the view centers the
/// arc in whatever bounds it gets, RadialProgressView.java:228-230, and so
/// does the painter when a parent imposes larger bounds). Ticks continuously
/// like the always-invalidating Java view, respecting the ambient
/// [TickerMode]; each frame's dt is clamped to 17ms
/// (RadialProgressView.java:126-128).
///
/// Like every component in this package, the spinner takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise [colorKey] resolves through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class TgRadialProgress extends StatefulWidget {
  const TgRadialProgress({
    super.key,
    this.progress,
    this.toCircle = false,
    this.size = kTgRadialProgressSize,
    this.strokeWidth = kTgRadialProgressStrokeWidth,
    this.colorKey = TelegramColorKey.progressCircle,
    this.color,
    this.resources,
  });

  /// Determinate progress 0..1, or null for the indeterminate cycle
  /// (`setNoProgress`/`setProgress`, RadialProgressView.java:93-104).
  final double? progress;

  /// Morph the arc into a full ring (`toCircle`,
  /// RadialProgressView.java:219-224).
  final bool toCircle;

  /// Arc box side, default 40dp; the AlertDialog recipe passes
  /// [kTgRadialProgressDialogSize] (`setSize`, RadialProgressView.java:205-208).
  final double size;

  /// Stroke width, default 3dp (`setStrokeWidth`,
  /// RadialProgressView.java:210-212).
  final double strokeWidth;

  /// Theme key for the arc, default `progressCircle`
  /// (RadialProgressView.java:65).
  final int colorKey;

  /// Raw color override winning over [colorKey] (`setProgressColor`,
  /// RadialProgressView.java:214-217 — the AlertDialog recipe recolors to
  /// `dialog_inlineProgress` this way, AlertDialog.java:887).
  final Color? color;

  /// Per-surface palette override; defaults to the ambient theme
  /// (RadialProgressView.java:59-61).
  final TelegramResources? resources;

  @override
  State<TgRadialProgress> createState() => _TgRadialProgressState();
}

class _TgRadialProgressState extends State<TgRadialProgress>
    with SingleTickerProviderStateMixin {
  final TgRadialProgressAnimation _animation = TgRadialProgressAnimation();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _applyProgress();
    _animation.toCircle(widget.toCircle, animated: false);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(TgRadialProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress != oldWidget.progress) {
      _applyProgress();
    }
    if (widget.toCircle != oldWidget.toCircle) {
      _animation.toCircle(widget.toCircle);
    }
  }

  void _applyProgress() {
    final double? progress = widget.progress;
    _animation.noProgress = progress == null;
    if (progress != null) {
      _animation.setProgress(progress);
    }
  }

  void _onTick(Duration elapsed) {
    // `if (dt > 17) dt = 17` (RadialProgressView.java:126-128).
    final double dtMs = math.min(
      (elapsed - _lastTick).inMicroseconds / 1000.0,
      kTgRadialProgressMaxFrameMs,
    );
    _lastTick = elapsed;
    setState(() => _animation.update(dtMs));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Color _color(BuildContext context) {
    final Color? color = widget.color;
    if (color != null) {
      return color;
    }
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(widget.colorKey);
    }
    return TelegramTheme.colorOf(context, widget.colorKey);
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(widget.size),
      painter: TgRadialProgressPainter(
        radOffset: _animation.radOffset,
        circleLength: _animation.circleLength,
        color: _color(context),
        arcSize: widget.size,
        strokeWidth: widget.strokeWidth,
      ),
    );
  }
}
