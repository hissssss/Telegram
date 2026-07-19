// Port of `ui/Components/LineProgressView.java` (spec_primitives.md §4.3):
// the determinate line — a filled rounded bar (radius = height/2, canonical
// 4dp) over an optional track, progress easing 300ms decelerate, the whole
// bar fading out over 200ms once progress reaches 1.
//
// Faithful details:
// - radius = height/2, bar drawn full view height (LineProgressView.java:
//   113-121); canonical 4dp height from the AlertDialog LOADING recipe
//   (`MATCH_PARENT × 4`, AlertDialog.java:866);
// - track drawn only while progress < 1 (LineProgressView.java:110-116) and
//   always full width (the Java `start` variable is dead code,
//   LineProgressView.java:113);
// - progress animates only forward: an animated set to a LOWER value is
//   ignored by the update loop (`progressDiff > 0`,
//   LineProgressView.java:57-70) — snap with `animated: false` to go back,
//   exactly like the Java;
// - completion fade: `alpha -= dt / 200` once the animated value sits at 1
//   (LineProgressView.java:71-77); setting any progress != 1 restores alpha
//   (LineProgressView.java:95-97);
// - colors: the Java takes raw ints (`setProgressColor`/`setBackColor`,
//   LineProgressView.java:80-86); the port defaults to the dialog recipe
//   keys `dialogLineProgress` / `dialogLineProgressBackground`
//   (AlertDialog.java:863-864) with raw-color overrides.
//
// Deliberately NOT ported: the `CellFlickerDrawable` shimmer sweep
// (LineProgressView.java:123-133, optional polish per the plan) and the
// unused 2dp round-cap stroke setup (LineProgressView.java:47-48 — the paint
// fills rounded rects, so the stroke parameters never apply).
library;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';

import '../foundation/tg_curves.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Canonical bar height: 4dp (the AlertDialog LOADING recipe places the view
/// `MATCH_PARENT × 4`, AlertDialog.java:866).
const double kTgLinearProgressHeight = 4.0;

/// Progress eases over 300ms decelerate (LineProgressView.java:61-66).
const double kTgLinearProgressProgressTimeMs = 300.0;

/// Completion fade-out: 200ms (`animatedAlphaValue -= dt / 200.0f`,
/// LineProgressView.java:72).
const double kTgLinearProgressFadeTimeMs = 200.0;

/// The `LineProgressView` animation state machine — a widget-free port of
/// `updateAnimation()` + `setProgress` (LineProgressView.java:52-103),
/// driven by explicit dt like [BoolFactor]. The Java uses unclamped wall dt.
class TgLinearProgressAnimation {
  /// Fields start at the Java defaults (LineProgressView.java:24-29):
  /// everything 0 except `animatedAlphaValue = 1`.
  TgLinearProgressAnimation();

  double _currentProgress = 0.0;
  double _animationProgressStart = 0.0;
  double _currentProgressTime = 0.0;

  /// Displayed progress (`animatedProgressValue`, LineProgressView.java:28).
  double animatedProgressValue = 0.0;

  /// Whole-bar alpha, depleting after completion (`animatedAlphaValue`,
  /// LineProgressView.java:29).
  double animatedAlphaValue = 1.0;

  /// The target (`getCurrentProgress`, LineProgressView.java:105-107).
  double get progress => _currentProgress;

  /// Whether an [update] can still change state — the port of "the view
  /// keeps invalidating": either the eased progress is still moving forward
  /// (LineProgressView.java:57-70) or the completion fade is running
  /// (LineProgressView.java:71-77).
  bool get isAnimating =>
      (animatedProgressValue != 1.0 &&
          animatedProgressValue != _currentProgress &&
          _currentProgress - _animationProgressStart > 0.0) ||
      (animatedProgressValue == 1.0 && animatedAlphaValue != 0.0);

  /// Port of `setProgress(float, boolean)` (LineProgressView.java:88-103):
  /// animated sets ease from the current displayed value; unanimated sets
  /// snap. Any value != 1 restores the bar's alpha.
  void setProgress(double value, {bool animated = true}) {
    if (!animated) {
      animatedProgressValue = value;
      _animationProgressStart = value;
    } else {
      _animationProgressStart = animatedProgressValue;
    }
    if (value != 1.0) {
      animatedAlphaValue = 1.0;
    }
    _currentProgress = value;
    _currentProgressTime = 0.0;
  }

  /// Port of `updateAnimation()` (LineProgressView.java:52-78) with dt
  /// passed in.
  void update(double dtMs) {
    if (animatedProgressValue != 1.0 &&
        animatedProgressValue != _currentProgress) {
      final double progressDiff = _currentProgress - _animationProgressStart;
      // Backward animated sets never ease — `progressDiff > 0`
      // (LineProgressView.java:59, a Java quirk kept for parity).
      if (progressDiff > 0.0) {
        _currentProgressTime += dtMs;
        if (_currentProgressTime >= kTgLinearProgressProgressTimeMs) {
          animatedProgressValue = _currentProgress;
          _animationProgressStart = _currentProgress;
          _currentProgressTime = 0.0;
        } else {
          animatedProgressValue = _animationProgressStart +
              progressDiff *
                  TgCurves.decelerate.transform(
                    _currentProgressTime / kTgLinearProgressProgressTimeMs,
                  );
        }
      }
    }
    // `animatedProgressValue >= 1 && animatedProgressValue == 1` in Java —
    // the fade only runs at exactly 1 (LineProgressView.java:71-77).
    if (animatedProgressValue == 1.0 && animatedAlphaValue != 0.0) {
      animatedAlphaValue -= dtMs / kTgLinearProgressFadeTimeMs;
      if (animatedAlphaValue <= 0.0) {
        animatedAlphaValue = 0.0;
      }
    }
  }
}

/// The `LineProgressView.onDraw` port (LineProgressView.java:109-136): a
/// full-width track (only while progress < 1) under a `width × progress`
/// fill, both rounded at `height / 2` and drawn at [alpha].
class TgLinearProgressPainter extends CustomPainter {
  TgLinearProgressPainter({
    required this.progress,
    required this.color,
    this.backColor,
    this.alpha = 1.0,
    super.repaint,
  });

  /// Displayed (eased) progress 0..1 (LineProgressView.java:120).
  final double progress;

  /// Fill color (`setProgressColor`, LineProgressView.java:80-82).
  final Color color;

  /// Track color, or null for no track — the analog of the Java
  /// `backColor != 0` guard (LineProgressView.java:110).
  final Color? backColor;

  /// Whole-bar alpha (`animatedAlphaValue`; the Java sets the paint's alpha
  /// absolutely, `setAlpha((int) (255 * animatedAlphaValue))`,
  /// LineProgressView.java:112, 119).
  final double alpha;

  /// Whether the track is drawn: `backColor != 0 && animatedProgressValue
  /// != 1` (LineProgressView.java:110).
  bool get paintsTrack => backColor != null && progress != 1.0;

  /// The full-width track: `(0, 0, width, height)` rounded `height / 2`
  /// (LineProgressView.java:114-115).
  RRect trackRRectFor(Size size) {
    return RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2.0),
    );
  }

  /// The fill: `(0, 0, width * progress, height)` rounded `height / 2`
  /// (LineProgressView.java:120-121).
  RRect fillRRectFor(Size size) {
    return RRect.fromRectAndRadius(
      Rect.fromLTWH(0.0, 0.0, size.width * progress, size.height),
      Radius.circular(size.height / 2.0),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    final Color? backColor = this.backColor;
    if (paintsTrack && backColor != null) {
      paint.color = backColor.withValues(alpha: alpha);
      canvas.drawRRect(trackRRectFor(size), paint);
    }
    paint.color = color.withValues(alpha: alpha);
    canvas.drawRRect(fillRRectFor(size), paint);
  }

  @override
  bool shouldRepaint(TgLinearProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.backColor != backColor ||
        oldDelegate.alpha != alpha;
  }
}

/// The `ui/Components/LineProgressView.java` port — the determinate line
/// used by AlertDialog's LOADING variant.
///
/// Controlled widget: [progress] in; increases ease over 300ms decelerate
/// (decreases snap only when [animated] is false — the Java quirk); at
/// `progress == 1.0` the whole bar fades out over 200ms and the widget
/// keeps its layout box. Fills the parent's width at [height] (the Java
/// `MATCH_PARENT × 4` placement); give it a bounded width.
///
/// The ticker runs only while the eased progress or the completion fade is
/// in flight, mirroring the Java's conditional `invalidate()` chain.
///
/// Like every component in this package, the bar takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise [progressColorKey] /
/// [backColorKey] resolve through [TelegramTheme.colorOf] for per-key
/// rebuild granularity.
class TgLinearProgress extends StatefulWidget {
  const TgLinearProgress({
    super.key,
    required this.progress,
    this.animated = true,
    this.height = kTgLinearProgressHeight,
    this.progressColorKey = TelegramColorKey.dialogLineProgress,
    this.backColorKey = TelegramColorKey.dialogLineProgressBackground,
    this.progressColor,
    this.backColor,
    this.resources,
  });

  /// Target progress 0..1 (`setProgress`, LineProgressView.java:88-103).
  final double progress;

  /// Whether [progress] changes ease (300ms) or snap — the `animated`
  /// argument of the Java `setProgress`. The first build always snaps.
  final bool animated;

  /// Bar height; radius is always `height / 2` (LineProgressView.java:115).
  final double height;

  /// Fill key, default `dialogLineProgress` — the AlertDialog recipe
  /// (AlertDialog.java:863).
  final int progressColorKey;

  /// Track key, default `dialogLineProgressBackground`
  /// (AlertDialog.java:864); null omits the track (the Java unset
  /// `backColor == 0` state, LineProgressView.java:110).
  final int? backColorKey;

  /// Raw fill override winning over [progressColorKey] (`setProgressColor`,
  /// LineProgressView.java:80-82).
  final Color? progressColor;

  /// Raw track override winning over [backColorKey] (`setBackColor`,
  /// LineProgressView.java:84-86).
  final Color? backColor;

  /// Per-surface palette override; defaults to the ambient theme.
  final TelegramResources? resources;

  @override
  State<TgLinearProgress> createState() => _TgLinearProgressState();
}

class _TgLinearProgressState extends State<TgLinearProgress>
    with SingleTickerProviderStateMixin {
  final TgLinearProgressAnimation _animation = TgLinearProgressAnimation();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    // The first build shows the given value directly (a fresh Java view gets
    // an unanimated initial setProgress, e.g. AlertDialog.java:862).
    _animation.setProgress(widget.progress, animated: false);
    _ensureTicking();
  }

  @override
  void didUpdateWidget(TgLinearProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress != oldWidget.progress) {
      _animation.setProgress(widget.progress, animated: widget.animated);
      _ensureTicking();
    }
  }

  void _ensureTicking() {
    if (_animation.isAnimating && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final double dtMs = (elapsed - _lastTick).inMicroseconds / 1000.0;
    _lastTick = elapsed;
    setState(() => _animation.update(dtMs));
    if (!_animation.isAnimating) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Color _resolve(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  Color? _trackColor(BuildContext context) {
    final Color? backColor = widget.backColor;
    if (backColor != null) {
      return backColor;
    }
    final int? key = widget.backColorKey;
    if (key == null) {
      return null;
    }
    return _resolve(context, key);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: CustomPaint(
        painter: TgLinearProgressPainter(
          progress: _animation.animatedProgressValue,
          color: widget.progressColor ??
              _resolve(context, widget.progressColorKey),
          backColor: _trackColor(context),
          alpha: _animation.animatedAlphaValue,
        ),
      ),
    );
  }
}
