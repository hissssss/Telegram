// Port of `ui/Components/CircularProgressDrawable.java` — the Material-style
// head/tail in-button spinner embedded by `ButtonWithCounterView` and
// `TextViewWithLoading` (spec_primitives.md §4.2). This is the spinner
// shared by TgButton, TgDialogButton and TgAlertDialog's loading buttons.
//
// Faithful details:
// - 18dp arc diameter, 2.25dp round-cap/round-join stroke, default white,
//   caller-supplied color (the Java constructor takes a raw color — there is
//   no theme key; callers resolve their label color and pass it in);
// - 5400ms cycle: both arc ends advance linearly 1520°·t/5400 (the tail
//   trails the head by 20°) plus 4 interleaved 250° pulses per period, each
//   eased FastOutSlowIn over 667ms, head pulses at `t − i·1350`, tail at
//   `t − (667 + i·1350)` — the sweep breathes ~20°↔~270° while rotating;
// - arc rect = (size + thickness/2) square centered in the bounds, intrinsic
//   dimension = size + thickness.
//
// Divergence: Java's `FastOutSlowInInterpolator` (CircularProgressDrawable.
// java:35) is androidx's lookup-table approximation of the Material
// fast-out-slow-in curve; the port uses Flutter's exact cubic
// `Curves.fastOutSlowIn` (0.4, 0, 0.2, 1) — values agree to ~1e-3.
// Deliberately NOT ported: `setAlpha`/`setColorFilter` Drawable plumbing.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';

/// Arc diameter: 18dp (`size = AndroidUtilities.dp(18)`,
/// CircularProgressDrawable.java:19).
const double kTgCircularProgressSize = 18.0;

/// Stroke thickness: 2.25dp (`thickness = AndroidUtilities.dp(2.25f)`,
/// CircularProgressDrawable.java:20).
const double kTgCircularProgressThickness = 2.25;

/// Head/tail cycle period: 5400ms (`(now - start) % 5400`,
/// CircularProgressDrawable.java:39).
const double kTgCircularProgressPeriodMs = 5400.0;

/// Linear advance of both arc ends per period: 1520°
/// (`1520 * t / 5400f`, CircularProgressDrawable.java:44-45).
const double kTgCircularProgressRotationDeg = 1520.0;

/// The tail trails the head by 20° (`1520 * t / 5400f - 20`,
/// CircularProgressDrawable.java:44).
const double kTgCircularProgressTailLagDeg = 20.0;

/// Pulses per period: 4 (`for (int i = 0; i < 4; ++i)`,
/// CircularProgressDrawable.java:46).
const int kTgCircularProgressPulseCount = 4;

/// Each pulse sweeps 250° (`interpolator.getInterpolation(...) * 250`,
/// CircularProgressDrawable.java:47-48).
const double kTgCircularProgressPulseDeg = 250.0;

/// Each pulse is eased over 667ms (`(t - i * 1350) / 667f`,
/// CircularProgressDrawable.java:47-48).
const double kTgCircularProgressPulseDurationMs = 667.0;

/// Pulses start every 1350ms; the tail's pulse starts 667ms after the
/// head's (`t - i * 1350` / `t - (667 + i * 1350)`,
/// CircularProgressDrawable.java:47-48).
const double kTgCircularProgressPulseIntervalMs = 1350.0;

/// Default arc color: opaque white (`this(0xffffffff)`,
/// CircularProgressDrawable.java:22-24).
const Color kTgCircularProgressDefaultColor = Color(0xFFFFFFFF);

/// Port of the static `CircularProgressDrawable.getSegments(t, segments)`
/// (CircularProgressDrawable.java:43-50): for a time [tMs] in milliseconds
/// within the cycle (the caller mods by [kTgCircularProgressPeriodMs]),
/// returns the arc's start (tail) and end (head) angles in degrees.
///
/// `start = max(0, 1520·t/5400 − 20) + Σᵢ fastOutSlowIn((t−(667+i·1350))/667)·250`
/// `end   =        1520·t/5400       + Σᵢ fastOutSlowIn((t−i·1350)/667)·250`
///
/// The eased pulse input is clamped to [0, 1] exactly as androidx's
/// lookup-table interpolator clamps out-of-range inputs.
({double start, double end}) tgCircularProgressSegments(double tMs) {
  final double advance =
      kTgCircularProgressRotationDeg * tMs / kTgCircularProgressPeriodMs;
  double start = math.max(0.0, advance - kTgCircularProgressTailLagDeg);
  double end = advance;
  for (int i = 0; i < kTgCircularProgressPulseCount; i++) {
    final double headT =
        (tMs - i * kTgCircularProgressPulseIntervalMs) /
            kTgCircularProgressPulseDurationMs;
    final double tailT =
        (tMs -
                (kTgCircularProgressPulseDurationMs +
                    i * kTgCircularProgressPulseIntervalMs)) /
            kTgCircularProgressPulseDurationMs;
    end += Curves.fastOutSlowIn.transform(headT.clamp(0.0, 1.0)) *
        kTgCircularProgressPulseDeg;
    start += Curves.fastOutSlowIn.transform(tailT.clamp(0.0, 1.0)) *
        kTgCircularProgressPulseDeg;
  }
  return (start: start, end: end);
}

/// The `CircularProgressDrawable.draw` port: paints one round-capped stroke
/// arc from `angleOffset + start` sweeping `end − start` degrees
/// (CircularProgressDrawable.java:62-75), centered in the canvas like the
/// Java `setBounds` math (CircularProgressDrawable.java:86-96).
class TgCircularProgressPainter extends CustomPainter {
  TgCircularProgressPainter({
    required this.elapsed,
    this.color = kTgCircularProgressDefaultColor,
    this.diameter = kTgCircularProgressSize,
    this.thickness = kTgCircularProgressThickness,
    this.angleOffset = 0.0,
    super.repaint,
  });

  /// Time since the spinner started; the painter wraps it into the 5400ms
  /// cycle (`(now - start) % 5400`, CircularProgressDrawable.java:38-39).
  final Duration elapsed;

  /// Arc color — Java takes a raw color, no theme key
  /// (CircularProgressDrawable.java:25-27, 98-100); callers resolve their
  /// label color through the theme and pass it in. Defaults to white.
  final Color color;

  /// Arc diameter, Java `size` (CircularProgressDrawable.java:19).
  final double diameter;

  /// Stroke width (CircularProgressDrawable.java:20, 95).
  final double thickness;

  /// Extra rotation in degrees (`setAngleOffset`,
  /// CircularProgressDrawable.java:81-83).
  final double angleOffset;

  /// The arc's oval: a `diameter + thickness/2` square centered in [size] —
  /// the `setBounds` inset math (CircularProgressDrawable.java:86-96).
  Rect arcRect(Size size) {
    final double side = diameter + thickness / 2.0;
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double t =
        (elapsed.inMicroseconds / 1000.0) % kTgCircularProgressPeriodMs;
    final ({double start, double end}) segment = tgCircularProgressSegments(t);
    final Paint paint = Paint()
      // STROKE, round cap, round join (CircularProgressDrawable.java:52-56).
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = thickness
      ..color = color;
    // `canvas.drawArc(bounds, angleOffset + segment[0],
    //  segment[1] - segment[0], false, paint)`
    // (CircularProgressDrawable.java:67-73); degrees → radians, same
    // 0°-at-3-o'clock convention.
    canvas.drawArc(
      arcRect(size),
      (angleOffset + segment.start) * math.pi / 180.0,
      (segment.end - segment.start) * math.pi / 180.0,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(TgCircularProgressPainter oldDelegate) {
    return oldDelegate.elapsed != elapsed ||
        oldDelegate.color != color ||
        oldDelegate.diameter != diameter ||
        oldDelegate.thickness != thickness ||
        oldDelegate.angleOffset != angleOffset;
  }
}

/// A self-ticking [TgCircularProgressPainter] host — the drop-in spinner
/// widget for TgButton/TgDialogButton/TgAlertDialog loading states.
///
/// Sizes itself to the drawable's intrinsic dimension,
/// `diameter + thickness` (`getIntrinsicWidth/Height`,
/// CircularProgressDrawable.java:116-123), and centers the arc in whatever
/// bounds it actually receives, like the Java drawable centers within its
/// bounds. The clock starts on mount (`start = SystemClock.elapsedRealtime()`
/// on first draw, CircularProgressDrawable.java:63-65) and respects the
/// ambient [TickerMode].
class TgCircularProgress extends StatefulWidget {
  const TgCircularProgress({
    super.key,
    this.color = kTgCircularProgressDefaultColor,
    this.diameter = kTgCircularProgressSize,
    this.thickness = kTgCircularProgressThickness,
    this.angleOffset = 0.0,
  });

  /// Arc color; callers pass their theme-resolved label color
  /// (CircularProgressDrawable.java:25-27). Defaults to white.
  final Color color;

  /// Arc diameter, default 18dp (CircularProgressDrawable.java:19).
  final double diameter;

  /// Stroke width, default 2.25dp (CircularProgressDrawable.java:20).
  final double thickness;

  /// Extra rotation in degrees (CircularProgressDrawable.java:81-83).
  final double angleOffset;

  @override
  State<TgCircularProgress> createState() => _TgCircularProgressState();
}

class _TgCircularProgressState extends State<TgCircularProgress>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Java invalidates itself on every draw (invalidateSelf(),
    // CircularProgressDrawable.java:74) — a continuous animation loop.
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    setState(() => _elapsed = elapsed);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      // Intrinsic bounds: size + thickness
      // (CircularProgressDrawable.java:116-123).
      size: Size.square(widget.diameter + widget.thickness),
      painter: TgCircularProgressPainter(
        elapsed: _elapsed,
        color: widget.color,
        diameter: widget.diameter,
        thickness: widget.thickness,
        angleOffset: widget.angleOffset,
      ),
    );
  }
}
