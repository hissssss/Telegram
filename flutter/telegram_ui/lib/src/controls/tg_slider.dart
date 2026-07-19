// The settings/player seek bar (PLAN_UIKIT.md M7).
//
// Port of `ui/Components/SeekBarView.java` per spec_forms.md §3: a 38dp-tall
// bar with a 3dp round-rect track inset 16dp at each end (selectorWidth 32,
// SeekBarView.java:115, 451), a 6dp thumb growing to 8dp while pressed at
// 1dp/60ms (SeekBarView.java:489-509), buffered + min-progress segments,
// discrete-step snapping through a 60ms EASE_OUT AnimatedFloat with a haptic
// per step (SeekBarView.java:62, 350-356, 440-442), a 225ms double-circle
// swap for animated programmatic jumps (SeekBarView.java:510-528), forgiving
// grab + tap-to-seek touch handling (SeekBarView.java:231-335), and the
// two-sided center-notch mode (SeekBarView.java:184-190, 461-467).
//
// Deviations (documented per §2 conventions):
// - the port honors [innerColorKey] — Java hard-sets the track color every
//   frame (SeekBarView.java:448), clobbering `setColors`/`setInnerColor`;
//   spec_forms.md §3 calls for NOT replicating that quirk;
// - Java quantizes `thumbX` to int px (SeekBarView.java:61, 386); the port
//   animates sub-pixel (TgSwitch precedent);
// - `onChanged` always streams during drags — Java gates live reporting
//   behind `setReportChanges(true)` (SeekBarView.java:213-215, 314);
// - the haptic is `HapticFeedback.selectionClick`, the closest Flutter
//   analog of `AndroidUtilities.vibrateCursor` (TEXT_HANDLE_MOVE,
//   AndroidUtilities.java:6543-6549);
// - two-sided release reports through [onChangeEnd] like the single-sided
//   path — Java passes `stop=false` there (SeekBarView.java:255-262), a
//   delegate-protocol detail without a Flutter analog.
//
// Deliberately NOT ported: the hover ripple drawable (SeekBarView.java:
// 119-123, 483-487), timestamp/chapter machinery (SeekBarView.java:537-891
// — chat-media-specific per the spec), `needVisuallyDivideSteps` unanimated
// snapping (SeekBarView.java:443-446), and the RTL-agnostic Java draw is
// kept LTR (the Java onDraw never mirrors).
library;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import '../foundation/tg_curves.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Canonical bar height: 38dp (`createFrame(MATCH_PARENT, 38, ...)`,
/// ThemeActivity.java:341, 425).
const double kTgSliderHeight = 38.0;

/// `selectorWidth` = 32dp (SeekBarView.java:115); the track is inset half of
/// it (16dp) at each end and thumb travel = width - 32dp
/// (SeekBarView.java:447, 451).
const double kTgSliderSelectorWidth = 32.0;

/// Logical thumb grab box: 24dp (`thumbSize`, SeekBarView.java:116).
const double kTgSliderThumbSize = 24.0;

/// Visible thumb radius at rest: 6dp (SeekBarView.java:117, 490).
const double kTgSliderThumbRadius = 6.0;

/// Visible thumb radius while pressed: 8dp (SeekBarView.java:490).
const double kTgSliderThumbRadiusPressed = 8.0;

/// The press growth animates linearly at 1dp per 60ms
/// (`currentRadius += dp(1) * (dt / 60.0f)`, SeekBarView.java:498, 503) —
/// 120ms for the full 6->8dp change.
const Duration kTgSliderThumbRadiusDuration = Duration(milliseconds: 120);

/// Default track height: 3dp (`lineWidthDp = 3`, SeekBarView.java:77).
const double kTgSliderLineWidth = 3.0;

/// Track corner radius: 2dp (`drawProgressBar`, SeekBarView.java:657-659).
const double kTgSliderTrackRadius = 2.0;

/// Step-snap animation: 60ms (`AnimatedFloat(this, 0, 60, EASE_OUT)`,
/// SeekBarView.java:62).
const Duration kTgSliderSnapDuration = Duration(milliseconds: 60);

/// Step-snap curve: `EASE_OUT` (SeekBarView.java:62).
const Curve kTgSliderSnapCurve = TgCurves.easeOut;

/// Animated programmatic jump: `transitionProgress += dt / 225f`
/// (SeekBarView.java:511).
const Duration kTgSliderTransitionDuration = Duration(milliseconds: 225);

/// The old thumb circle collapses within the first third of the transition
/// (`easeInQuad(min(1, t * 3))`, SeekBarView.java:520).
const double kTgSliderTransitionOldSpeed = 3.0;

/// The `[0, minProgress]` segment draws at 50% of the fill alpha
/// (SeekBarView.java:472-476).
const double kTgSliderMinProgressAlpha = 0.5;

/// Two-sided center notch: 2dp wide x 12dp tall (`±dp(1) x ±dp(6)`,
/// SeekBarView.java:462).
const Size kTgSliderNotchSize = Size(2.0, 12.0);

/// Two-sided fill bar height: 2dp (`±dp(1)`, SeekBarView.java:463-467).
const double kTgSliderTwoSidedFillHeight = 2.0;

/// Accessibility scroll delta with no steps: 5%
/// (`FloatSeekBarAccessibilityDelegate.getDelta`,
/// FloatSeekBarAccessibilityDelegate.java:75-77); with steps `1/stepsCount`
/// (SeekBarView.java:155-163).
const double kTgSliderA11yDelta = 0.05;

/// `Easings.easeInQuad` (Easings.java:12) — file-local because TgCurves
/// carries only the CubicBezierInterpolator constants; consolidation is a
/// wave-3 cleanup.
const Cubic kTgSliderEaseInQuad = Cubic(0.55, 0.085, 0.68, 0.53);

/// `Easings.easeOutQuad` (Easings.java:13) — see [kTgSliderEaseInQuad].
const Cubic kTgSliderEaseOutQuad = Cubic(0.25, 0.46, 0.45, 0.94);

/// The Telegram seek bar — the `SeekBarView.java` port.
///
/// Controlled widget: [value] in, [onChanged]/[onChangeEnd] out. Progress is
/// 0..1 (or [-1, 1] in [twoSided] mode — see [TgSlider.thumbXForValue] for
/// the exact, asymmetric Java mapping). Set [animateChanges] to run external
/// [value] changes through the 225ms double-circle swap
/// (`setProgress(p, animated)`, SeekBarView.java:388-393).
class TgSlider extends StatefulWidget {
  /// Creates a seek bar.
  const TgSlider({
    super.key,
    required this.value,
    this.onChanged,
    this.onChangeEnd,
    this.onPressedChanged,
    this.buffered,
    this.minValue,
    this.stepCount = 0,
    this.twoSided = false,
    this.lineWidth = kTgSliderLineWidth,
    this.height = kTgSliderHeight,
    this.animateChanges = false,
    this.outerColorKey = TelegramColorKey.player_progress,
    this.innerColorKey = TelegramColorKey.player_progressBackground,
    this.bufferedColorKey = TelegramColorKey.player_progressCachedBackground,
    this.resources,
  });

  /// Current progress, 0..1 (two-sided: [-1, 1], SeekBarView.java:377-384).
  final double value;

  /// Streams the live progress during drags (`onSeekBarDrag(stop=false, p)`,
  /// SeekBarView.java:314-325 — the port always streams, see header).
  final ValueChanged<double>? onChanged;

  /// Fires once on release / tap with the final progress
  /// (`onSeekBarDrag(stop=true, p)`, SeekBarView.java:255-265).
  final ValueChanged<double>? onChangeEnd;

  /// Mirrors `onSeekBarPressed` (SeekBarView.java:85, 270, 297).
  final ValueChanged<bool>? onPressedChanged;

  /// Buffered fraction, drawn `[0, buffered]` in [bufferedColorKey]
  /// (SeekBarView.java:456-459). Null hides the segment.
  final double? buffered;

  /// Lower bound (`minProgress`, SeekBarView.java:217-223): the thumb clamps
  /// to it (SeekBarView.java:337-339) and `[0, minValue]` draws at 50% alpha
  /// (SeekBarView.java:469-476). Null disables (Java -1).
  final double? minValue;

  /// Discrete stop count (`separatorsCount`, SeekBarView.java:172-174);
  /// > 1 snaps the drawn thumb through the 60ms EASE_OUT float
  /// (SeekBarView.java:440-442) and fires a haptic per step change
  /// (SeekBarView.java:350-356). Ignored in [twoSided] mode
  /// (SeekBarView.java:440).
  final int stepCount;

  /// Center-notch mode with progress in [-1, 1] (`setTwoSided`,
  /// SeekBarView.java:184-190).
  final bool twoSided;

  /// Track height in dp (`setLineWidth`, SeekBarView.java:341-343).
  final double lineWidth;

  /// Bar height; canonical 38dp (ThemeActivity.java:341).
  final double height;

  /// Whether external [value] changes run the 225ms double-circle swap
  /// (`setProgress(p, animated=true)`, SeekBarView.java:388-393).
  final bool animateChanges;

  /// Fill + thumb color key (`outerPaint1`, `key_player_progress`,
  /// SeekBarView.java:112-113).
  final int outerColorKey;

  /// Track color key (`key_player_progressBackground`, SeekBarView.java:448
  /// — honored as a parameter here, see the header deviation note).
  final int innerColorKey;

  /// Buffered-segment color key (`key_player_progressCachedBackground`,
  /// SeekBarView.java:457).
  final int bufferedColorKey;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  /// Value -> thumbX (the Java `thumbX` left coordinate, 0..travel where
  /// travel = width - 32; thumb center = thumbX + 16dp).
  ///
  /// Two-sided (`setProgress`, SeekBarView.java:377-384): with `cx =
  /// travel/2`, `p >= 0` maps `cx + travel/2 · p`; `p < 0` maps
  /// `cx - travel/2 · (1 + p)` — the Java encoding measures negative values
  /// from the LEFT EDGE: -1 sits just left of center, -0.01 at the far left
  /// (mirroring the release mapping, SeekBarView.java:255-262).
  static double thumbXForValue(
    double value,
    double travel, {
    bool twoSided = false,
  }) {
    if (travel <= 0) {
      return 0;
    }
    double x;
    if (twoSided) {
      final double cx = travel / 2.0;
      x = value < 0
          ? cx + travel / 2.0 * -(1.0 + value)
          : cx + travel / 2.0 * value;
    } else {
      x = travel * value;
    }
    return x.clamp(0.0, travel);
  }

  /// ThumbX -> value; the exact release mapping (single-sided
  /// SeekBarView.java:264, 363; two-sided SeekBarView.java:255-262).
  static double valueForThumbX(
    double thumbX,
    double travel, {
    bool twoSided = false,
  }) {
    if (travel <= 0) {
      return 0;
    }
    if (twoSided) {
      final double w = travel / 2.0;
      if (thumbX >= w) {
        return (thumbX - w) / w;
      }
      return -(1.0 - (w - thumbX) / w).clamp(0.01, double.infinity);
    }
    return thumbX / travel;
  }

  @override
  State<TgSlider> createState() => TgSliderState();
}

/// State of a [TgSlider]; public so tests can drive and probe it.
class TgSliderState extends State<TgSlider> with TickerProviderStateMixin {
  /// Press radius factor 0..1 (6dp..8dp), linear at 1dp/60ms.
  late final AnimationController _radiusController;

  /// Step-snap animation (full 60ms per retarget, AnimatedFloat semantics).
  late final AnimationController _snapController;

  /// Animated programmatic jump (SeekBarView.java:510-528).
  late final AnimationController _transitionController;

  double _snapFrom = 0.0;
  double _snapTarget = 0.0;

  /// The old thumb's value during a 225ms transition.
  double? _transitionFromValue;

  bool _pressed = false;
  double _dragThumbX = 0.0;
  double _thumbDX = 0.0;
  double _width = 0.0;
  int _lastStepValue = 0;

  @override
  void initState() {
    super.initState();
    _radiusController = AnimationController(
      vsync: this,
      duration: kTgSliderThumbRadiusDuration,
    );
    _snapController = AnimationController(
      vsync: this,
      duration: kTgSliderSnapDuration,
      value: 1.0,
    );
    _transitionController = AnimationController(
      vsync: this,
      duration: kTgSliderTransitionDuration,
      value: 1.0,
    );
    _snapFrom = _snapTarget = _snappedFraction(_fractionForValue(widget.value));
  }

  @override
  void didUpdateWidget(TgSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_pressed && widget.value != oldWidget.value) {
      if (widget.animateChanges) {
        // `setProgress(p, animated=true)` (SeekBarView.java:388-393).
        _transitionFromValue = oldWidget.value;
        _transitionController.forward(from: 0.0);
      }
      _retargetSnap(_fractionForValue(widget.value));
    }
  }

  @override
  void dispose() {
    _radiusController.dispose();
    _snapController.dispose();
    _transitionController.dispose();
    super.dispose();
  }

  double get _travel => _width - kTgSliderSelectorWidth;

  /// `minThumbX` (SeekBarView.java:337-339).
  double get _minThumbX {
    final double? minValue = widget.minValue;
    if (minValue == null || widget.twoSided) {
      return 0.0;
    }
    final double x = minValue * _travel;
    return x > 0.0 ? x : 0.0;
  }

  /// Value -> travel fraction (thumbX / travel), width-independent.
  double _fractionForValue(double value) {
    if (widget.twoSided) {
      final double f =
          value < 0 ? 0.5 - (1.0 + value) / 2.0 : 0.5 + value / 2.0;
      return f.clamp(0.0, 1.0);
    }
    final double min = widget.minValue ?? 0.0;
    return value.clamp(min > 0.0 ? min : 0.0, 1.0);
  }

  double _snappedFraction(double fraction) {
    if (widget.twoSided || widget.stepCount <= 1) {
      return fraction;
    }
    // step = travel / (stepCount - 1); drawn thumb rounds to the nearest
    // step (SeekBarView.java:440-442) — fraction-space equivalent.
    final int stops = widget.stepCount - 1;
    return (fraction * stops).roundToDouble() / stops;
  }

  void _retargetSnap(double rawFraction) {
    final double target = _snappedFraction(rawFraction);
    if (target != _snapTarget) {
      _snapFrom = _drawnFraction();
      _snapTarget = target;
      if (widget.twoSided || widget.stepCount <= 1) {
        _snapController.value = 1.0;
      } else {
        _snapController.forward(from: 0.0);
      }
    }
  }

  double _drawnFraction() {
    final double t = kTgSliderSnapCurve.transform(_snapController.value);
    return _snapFrom + (_snapTarget - _snapFrom) * t;
  }

  /// Drawn thumb center x, for tests.
  double get debugThumbCenterX =>
      _drawnFraction() * _travel + kTgSliderSelectorWidth / 2.0;

  /// Current visible thumb radius, for tests.
  double get debugThumbRadius =>
      kTgSliderThumbRadius +
      (kTgSliderThumbRadiusPressed - kTgSliderThumbRadius) *
          _radiusController.value;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) {
      return;
    }
    _pressed = pressed;
    // 6dp<->8dp at 1dp/60ms — animateTo scales the 120ms full-range
    // duration by the remaining distance, matching the per-frame linear
    // walk (SeekBarView.java:489-509).
    _radiusController.animateTo(pressed ? 1.0 : 0.0);
    widget.onPressedChanged?.call(pressed);
  }

  void _hapticStep(double value) {
    if (widget.stepCount <= 1 || widget.twoSided) {
      return;
    }
    // `Math.round((separatorsCount - 1) * progress)`; vibrate on change
    // (SeekBarView.java:350-356).
    final int step = ((widget.stepCount - 1) * value).round();
    if (step != _lastStepValue) {
      _lastStepValue = step;
      HapticFeedback.selectionClick();
    }
  }

  double _clampThumbX(double x) {
    final double max = _travel;
    final double min = _minThumbX;
    if (x < min) {
      return min;
    }
    return x > max ? max : x;
  }

  double get _currentThumbX => _pressed
      ? _dragThumbX
      : _clampThumbX(
          TgSlider.thumbXForValue(
            widget.value,
            _travel,
            twoSided: widget.twoSided,
          ),
        );

  double _valueAt(double thumbX) =>
      TgSlider.valueForThumbX(thumbX, _travel, twoSided: widget.twoSided);

  void _onDragStart(DragStartDetails details) {
    final double x = details.localPosition.dx;
    double thumbX = _currentThumbX;
    // Forgiving grab (SeekBarView.java:285-295): the hit box is
    // `[thumbX - additionWidth, thumbX + thumbSize + additionWidth]` with
    // additionWidth = (height - thumbSize) / 2; outside it the thumb
    // re-centers at the finger.
    final double additionWidth = (widget.height - kTgSliderThumbSize) / 2.0;
    final bool inside = thumbX - additionWidth <= x &&
        x <= thumbX + kTgSliderThumbSize + additionWidth;
    if (!inside) {
      thumbX = _clampThumbX(x - kTgSliderThumbSize / 2.0);
    }
    _thumbDX = x - thumbX;
    setState(() {
      _dragThumbX = thumbX;
    });
    _setPressed(true);
    if (widget.stepCount > 1 && !widget.twoSided) {
      // Seed `lastValue` so the first step crossing vibrates once
      // (SeekBarView.java:345, 350-356).
      _lastStepValue = ((widget.stepCount - 1) * _valueAt(thumbX)).round();
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    // `thumbX = x - thumbDX`, clamped (SeekBarView.java:308-313).
    final double thumbX = _clampThumbX(details.localPosition.dx - _thumbDX);
    setState(() {
      _dragThumbX = thumbX;
    });
    final double value = _valueAt(thumbX);
    _retargetSnap(_travel <= 0 ? 0 : thumbX / _travel);
    widget.onChanged?.call(value);
    _hapticStep(value);
  }

  void _onDragEnd() {
    if (!_pressed) {
      return;
    }
    final double value = _valueAt(_dragThumbX);
    _setPressed(false);
    setState(() {});
    // `onSeekBarDrag(stop=true, progress)` on release
    // (SeekBarView.java:255-265).
    widget.onChangeEnd?.call(value);
  }

  void _onDragCancel() {
    if (!_pressed) {
      return;
    }
    // ACTION_CANCEL clears the press without reporting a final progress
    // (SeekBarView.java:236-237, 270-273).
    _setPressed(false);
    setState(() {});
  }

  void _onTapUp(TapUpDetails details) {
    // Tap-to-seek (SeekBarView.java:238-252): outside the grab box the
    // thumb jumps to `x - thumbSize/2`, then the release completes as a
    // drag (`onSeekBarDrag(stop=true, ...)`, SeekBarView.java:264).
    final double x = details.localPosition.dx;
    double thumbX = _currentThumbX;
    final double additionWidth = (widget.height - kTgSliderThumbSize) / 2.0;
    final bool inside = thumbX - additionWidth <= x &&
        x <= thumbX + kTgSliderThumbSize + additionWidth;
    if (!inside) {
      thumbX = _clampThumbX(x - kTgSliderThumbSize / 2.0);
    }
    final double value = _valueAt(thumbX);
    _retargetSnap(_travel <= 0 ? 0 : thumbX / _travel);
    widget.onChanged?.call(value);
    widget.onChangeEnd?.call(value);
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  void _a11yScroll(bool forward) {
    final double delta = (widget.stepCount > 0
            ? 1.0 / widget.stepCount
            : kTgSliderA11yDelta) *
        (forward ? 1.0 : -1.0);
    final double min = widget.twoSided ? -1.0 : (widget.minValue ?? 0.0);
    final double next = (widget.value + delta).clamp(min, 1.0);
    widget.onChanged?.call(next);
    widget.onChangeEnd?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final Color outer = _color(context, widget.outerColorKey);
    final Color inner = _color(context, widget.innerColorKey);
    final Color buffered = _color(context, widget.bufferedColorKey);
    return Semantics(
      slider: true,
      enabled: widget.onChanged != null || widget.onChangeEnd != null,
      onIncrease: () => _a11yScroll(true),
      onDecrease: () => _a11yScroll(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Java measures the grab from ACTION_DOWN (SeekBarView.java:232-235);
        // `DragStartBehavior.down` reports the same anchor.
        dragStartBehavior: DragStartBehavior.down,
        onTapUp: _onTapUp,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: (DragEndDetails details) => _onDragEnd(),
        onHorizontalDragCancel: _onDragCancel,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              _width = constraints.maxWidth;
              return AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[
                  _radiusController,
                  _snapController,
                  _transitionController,
                ]),
                builder: (BuildContext context, Widget? child) {
                  final bool snapping =
                      !widget.twoSided && widget.stepCount > 1;
                  final double thumbX =
                      snapping ? _drawnFraction() * _travel : _currentThumbX;
                  final double? oldValue = _transitionFromValue;
                  final bool inTransition = oldValue != null &&
                      _transitionController.value < 1.0;
                  return CustomPaint(
                    size: Size(constraints.maxWidth, widget.height),
                    painter: TgSliderPainter(
                      thumbCenterX:
                          thumbX + kTgSliderSelectorWidth / 2.0,
                      thumbRadius: debugThumbRadius,
                      fillColor: outer,
                      trackColor: inner,
                      bufferedColor: buffered,
                      buffered: widget.buffered,
                      minProgress: widget.minValue,
                      twoSided: widget.twoSided,
                      lineWidth: widget.lineWidth,
                      transitionProgress:
                          inTransition ? _transitionController.value : 1.0,
                      transitionOldCenterX: inTransition
                          ? TgSlider.thumbXForValue(
                                oldValue,
                                _travel,
                                twoSided: widget.twoSided,
                              ) +
                              kTgSliderSelectorWidth / 2.0
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Paints the `SeekBarView.onDraw` geometry (SeekBarView.java:438-535): the
/// inset round-rect track, buffered/min segments (or the two-sided notch),
/// the fill and the thumb circle(s).
class TgSliderPainter extends CustomPainter {
  /// Creates the painter.
  const TgSliderPainter({
    required this.thumbCenterX,
    required this.thumbRadius,
    required this.fillColor,
    required this.trackColor,
    required this.bufferedColor,
    this.buffered,
    this.minProgress,
    this.twoSided = false,
    this.lineWidth = kTgSliderLineWidth,
    this.transitionProgress = 1.0,
    this.transitionOldCenterX,
  });

  /// Drawn thumb center x in px (`thumbX + selectorWidth/2`,
  /// SeekBarView.java:523-527).
  final double thumbCenterX;

  /// Current visible thumb radius (`currentRadius`, SeekBarView.java:496).
  final double thumbRadius;

  /// Fill + thumb color (`outerPaint1`, SeekBarView.java:112-113).
  final Color fillColor;

  /// Track color (`innerPaint1`, SeekBarView.java:448).
  final Color trackColor;

  /// Buffered-segment color (SeekBarView.java:457).
  final Color bufferedColor;

  /// Buffered fraction, or null (SeekBarView.java:456-459).
  final double? buffered;

  /// Min-progress fraction, or null (SeekBarView.java:469-476).
  final double? minProgress;

  /// Center-notch mode (SeekBarView.java:461-467).
  final bool twoSided;

  /// Track height in dp (SeekBarView.java:452).
  final double lineWidth;

  /// 0..1 through the 225ms animated jump; 1 = no transition
  /// (`transitionProgress`, SeekBarView.java:74, 510-517).
  final double transitionProgress;

  /// The collapsing old thumb's center x, non-null only mid-transition
  /// (`transitionThumbX`, SeekBarView.java:75, 523).
  final double? transitionOldCenterX;

  /// Old-circle radius factor: `1 - easeInQuad(min(1, t*3))`
  /// (SeekBarView.java:520).
  double get oldCircleFactor => transitionProgress >= 1.0
      ? 0.0
      : 1.0 -
          kTgSliderEaseInQuad.transform(
            (transitionProgress * kTgSliderTransitionOldSpeed).clamp(0.0, 1.0),
          );

  /// New-circle radius factor: `easeOutQuad(t)` (SeekBarView.java:521).
  double get newCircleFactor => transitionProgress >= 1.0
      ? 1.0
      : kTgSliderEaseOutQuad.transform(transitionProgress);

  @override
  void paint(Canvas canvas, Size size) {
    final double centerY = size.height / 2.0;
    final double left = kTgSliderSelectorWidth / 2.0;
    final double right = size.width - kTgSliderSelectorWidth / 2.0;
    final double top = centerY - lineWidth / 2.0;
    final double bottom = centerY + lineWidth / 2.0;
    const Radius radius = Radius.circular(kTgSliderTrackRadius);

    // Track (SeekBarView.java:448-455).
    canvas.drawRRect(
      RRect.fromLTRBR(left, top, right, bottom, radius),
      Paint()..color = trackColor,
    );

    // Buffered segment (SeekBarView.java:456-459).
    final double? buffered = this.buffered;
    if (buffered != null && buffered > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          left,
          top,
          left + buffered * (size.width - kTgSliderSelectorWidth),
          bottom,
          radius,
        ),
        Paint()..color = bufferedColor,
      );
    }

    final Paint fill = Paint()..color = fillColor;
    if (twoSided) {
      // Center notch 2x12dp (SeekBarView.java:462).
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(size.width / 2.0, centerY),
          width: kTgSliderNotchSize.width,
          height: kTgSliderNotchSize.height,
        ),
        fill,
      );
      // 2dp fill from the center to the thumb (SeekBarView.java:463-467).
      final double half = kTgSliderTwoSidedFillHeight / 2.0;
      if (thumbCenterX >= size.width / 2.0) {
        canvas.drawRect(
          Rect.fromLTRB(
            size.width / 2.0,
            centerY - half,
            thumbCenterX,
            centerY + half,
          ),
          fill,
        );
      } else {
        canvas.drawRect(
          Rect.fromLTRB(
            thumbCenterX,
            centerY - half,
            size.width / 2.0,
            centerY + half,
          ),
          fill,
        );
      }
    } else {
      final double? minProgress = this.minProgress;
      if (minProgress != null && minProgress >= 0) {
        // Active fill starts at minProgress; the region below it draws at
        // 50% alpha (SeekBarView.java:469-476).
        canvas.drawRRect(
          RRect.fromLTRBR(
            left + minProgress * (right - left),
            top,
            thumbCenterX,
            bottom,
            radius,
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(
            left,
            top,
            left + minProgress * (right - left),
            bottom,
            radius,
          ),
          Paint()
            ..color = fillColor.withValues(
              alpha: fillColor.a * kTgSliderMinProgressAlpha,
            ),
        );
      } else {
        canvas.drawRRect(
          RRect.fromLTRBR(left, top, thumbCenterX, bottom, radius),
          fill,
        );
      }
    }

    // Thumb (SeekBarView.java:519-528).
    final double? oldX = transitionOldCenterX;
    if (oldX != null && transitionProgress < 1.0) {
      final double oldFactor = oldCircleFactor;
      if (oldFactor > 0) {
        canvas.drawCircle(
          Offset(oldX, centerY),
          thumbRadius * oldFactor,
          fill,
        );
      }
      canvas.drawCircle(
        Offset(thumbCenterX, centerY),
        thumbRadius * newCircleFactor,
        fill,
      );
    } else {
      canvas.drawCircle(Offset(thumbCenterX, centerY), thumbRadius, fill);
    }
  }

  @override
  bool shouldRepaint(TgSliderPainter oldDelegate) =>
      oldDelegate.thumbCenterX != thumbCenterX ||
      oldDelegate.thumbRadius != thumbRadius ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.bufferedColor != bufferedColor ||
      oldDelegate.buffered != buffered ||
      oldDelegate.minProgress != minProgress ||
      oldDelegate.twoSided != twoSided ||
      oldDelegate.lineWidth != lineWidth ||
      oldDelegate.transitionProgress != transitionProgress ||
      oldDelegate.transitionOldCenterX != transitionOldCenterX;
}
