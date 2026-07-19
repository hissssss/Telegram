// The discrete labeled slider (PLAN_UIKIT.md S7) — the settings
// "message text size" / auto-delete control.
//
// Port of `ui/Components/SlideChooseView.java`: a 74dp-tall strip of dots
// (3dp radius growing to 6dp near the selection, SlideChooseView.java:233)
// joined by 2dp-tall line segments (SlideChooseView.java:252), 13dp labels
// whose color blends toward the accent as the selection approaches
// (SlideChooseView.java:257, 276-280), and a moving 6dp knob with a 12dp
// pressed halo at 80/255 alpha (SlideChooseView.java:288-292). The drawn
// selection index eases through a 120ms DEFAULT-curve AnimatedFloat, the
// halo through a 150ms one (SlideChooseView.java:52-53).
//
// Deviations (documented per §2 conventions): the crossing haptic is
// `HapticFeedback.selectionClick` — the `AndroidUtilities.vibrateCursor`
// analog (SlideChooseView.java:200-203; AndroidUtilities.java:6543-6549).
// Java re-fires `setOption(selectedIndex)` on drag release when the drag
// changed the selection (SlideChooseView.java:184-187); the port reports
// each change as it happens and only [onTouchEnd] on release. The Java
// `onDraw` never mirrors for RTL; the port keeps the fixed LTR layout.
//
// Deliberately NOT ported: `setDashedFrom` dashed tail segments
// (SlideChooseView.java:135-137, 237-246), `leftDrawables` label icons
// (SlideChooseView.java:106-120, 259-273), and `setMinAllowedIndex`
// (SlideChooseView.java:122-133, 230).
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import '../foundation/tg_curves.dart';
import '../foundation/tg_text_styles.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Fixed control height: 74dp (`makeMeasureSpec(dp(74), EXACTLY)`,
/// SlideChooseView.java:213).
const double kTgSlideChooserHeight = 74.0;

/// Resting dot diameter: 6dp (`circleSize`, SlideChooseView.java:214).
const double kTgSlideChooserDotSize = 6.0;

/// Gap between a dot and its line segment: 2dp (`gapSize`,
/// SlideChooseView.java:215).
const double kTgSlideChooserGap = 2.0;

/// Side inset: 22dp (`sideSide`, SlideChooseView.java:216).
const double kTgSlideChooserSideInset = 22.0;

/// Label text size: 13dp (SlideChooseView.java:73).
const double kTgSlideChooserTextSize = 13.0;

/// Label baseline y: 28dp from the top (SlideChooseView.java:276-280).
const double kTgSlideChooserTextBaseline = 28.0;

/// Track center y: height/2 + 11dp (SlideChooseView.java:224).
const double kTgSlideChooserTrackCenterOffset = 11.0;

/// Dot radius near the selection: 6dp (`lerp(circleSize/2, dp(6), t)`,
/// SlideChooseView.java:233); also the knob radius
/// (SlideChooseView.java:292).
const double kTgSlideChooserSelectedDotRadius = 6.0;

/// Pressed-halo radius: 12dp (`dp(12 * movingAnimated)`,
/// SlideChooseView.java:290).
const double kTgSlideChooserHaloRadius = 12.0;

/// Pressed-halo alpha: 80/255 (`setAlphaComponent(color, 80)`,
/// SlideChooseView.java:289).
const int kTgSlideChooserHaloAlpha = 80;

/// Line segments are 2dp tall (`cy ± dp(1)`, SlideChooseView.java:252).
const double kTgSlideChooserLineHeight = 2.0;

/// Segment ends shrink 3dp back from an adjacent selection
/// (SlideChooseView.java:250-251).
const double kTgSlideChooserLineShrink = 3.0;

/// Drawn-index animation: 120ms (`AnimatedFloat(this, 120, DEFAULT)`,
/// SlideChooseView.java:52).
const Duration kTgSlideChooserIndexDuration = Duration(milliseconds: 120);

/// Halo show/hide animation: 150ms (`AnimatedFloat(this, 150, DEFAULT)`,
/// SlideChooseView.java:53).
const Duration kTgSlideChooserMovingDuration = Duration(milliseconds: 150);

/// Both AnimatedFloats run `CubicBezierInterpolator.DEFAULT`
/// (SlideChooseView.java:52-53).
const Curve kTgSlideChooserCurve = TgCurves.defaultCubic;

/// A touch snaps to a stop when within 0.35 of it
/// (`abs(indexTouch - round) < .35f`, SlideChooseView.java:144).
const double kTgSlideChooserSnapThreshold = 0.35;

/// The discrete labeled slider — the `SlideChooseView.java` port.
///
/// Controlled widget: [selectedIndex] in, [onOptionSelected] out (fired per
/// stop as a drag crosses it and on taps, with a selection haptic —
/// SlideChooseView.java:200-209). External [selectedIndex] changes ease the
/// drawn knob over 120ms.
class TgSlideChooser extends StatefulWidget {
  /// Creates a slide chooser over [options] stops.
  const TgSlideChooser({
    super.key,
    required this.options,
    required this.selectedIndex,
    this.onOptionSelected,
    this.onTouchEnd,
    this.trackColorKey = TelegramColorKey.switchTrack,
    this.activeColorKey = TelegramColorKey.switchTrackChecked,
    this.textColorKey = TelegramColorKey.windowBackgroundWhiteGrayText,
    this.activeTextColorKey = TelegramColorKey.windowBackgroundWhiteBlueText,
    this.resources,
  });

  /// Stop labels (`setOptions`, SlideChooseView.java:102-120). Must not be
  /// empty.
  final List<String> options;

  /// Currently selected stop.
  final int selectedIndex;

  /// Called with the stop index on tap or as a drag crosses stops
  /// (`Callback.onOptionSelected`, SlideChooseView.java:315-321).
  final ValueChanged<int>? onOptionSelected;

  /// Called when the touch ends (`Callback.onTouchEnd`,
  /// SlideChooseView.java:189-191).
  final VoidCallback? onTouchEnd;

  /// Dot/segment resting color key (`key_switchTrack`,
  /// SlideChooseView.java:230).
  final int trackColorKey;

  /// Selected dot/segment/knob color key (`key_switchTrackChecked`,
  /// SlideChooseView.java:230, 289-291).
  final int activeColorKey;

  /// Resting label color key (`key_windowBackgroundWhiteGrayText`,
  /// SlideChooseView.java:257).
  final int textColorKey;

  /// Selected label color key (`key_windowBackgroundWhiteBlueText`,
  /// SlideChooseView.java:257).
  final int activeTextColorKey;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  /// Segment length between adjacent dots: `(width - circleSize·n -
  /// gapSize·2·(n-1) - sideSide·2) / max(1, n-1)` (SlideChooseView.java:217).
  static double lineSizeFor(double width, int optionCount) =>
      (width -
          kTgSlideChooserDotSize * optionCount -
          kTgSlideChooserGap * 2 * (optionCount - 1) -
          kTgSlideChooserSideInset * 2) /
      (optionCount - 1 > 0 ? optionCount - 1 : 1);

  /// Dot center x for stop [index]: `sideSide + (lineSize + gapSize·2 +
  /// circleSize)·a + circleSize/2` (SlideChooseView.java:227).
  static double dotCenterX(double width, int optionCount, double index) =>
      kTgSlideChooserSideInset +
      (lineSizeFor(width, optionCount) +
              kTgSlideChooserGap * 2 +
              kTgSlideChooserDotSize) *
          index +
      kTgSlideChooserDotSize / 2;

  /// Inverse of [dotCenterX]: the fractional stop under touch x
  /// (`(x - sideSide + circleSize/2) / (lineSize + gapSize·2 + circleSize)`,
  /// SlideChooseView.java:143), clamped to the stop range.
  static double indexForTouchX(double width, int optionCount, double x) {
    final double stride = lineSizeFor(width, optionCount) +
        kTgSlideChooserGap * 2 +
        kTgSlideChooserDotSize;
    final double raw =
        (x - kTgSlideChooserSideInset + kTgSlideChooserDotSize / 2) / stride;
    return raw.clamp(0.0, (optionCount - 1).toDouble());
  }

  @override
  State<TgSlideChooser> createState() => TgSlideChooserState();
}

/// State of a [TgSlideChooser]; public so tests can probe the animations.
class TgSlideChooserState extends State<TgSlideChooser>
    with TickerProviderStateMixin {
  late final AnimationController _indexController;
  late final AnimationController _movingController;

  double _indexFrom = 0.0;
  double _indexTarget = 0.0;
  double _movingFrom = 0.0;
  double _movingTarget = 0.0;

  bool _moving = false;
  double _width = 0.0;

  @override
  void initState() {
    super.initState();
    _indexController = AnimationController(
      vsync: this,
      duration: kTgSlideChooserIndexDuration,
      value: 1.0,
    );
    _movingController = AnimationController(
      vsync: this,
      duration: kTgSlideChooserMovingDuration,
      value: 1.0,
    );
    _indexFrom = _indexTarget = widget.selectedIndex.toDouble();
  }

  @override
  void didUpdateWidget(TgSlideChooser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      // AnimatedFloat retarget: animate from the current drawn value over
      // the full 120ms (SlideChooseView.java:52, 222).
      _indexFrom = selectedIndexAnimated;
      _indexTarget = widget.selectedIndex.toDouble();
      _indexController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _indexController.dispose();
    _movingController.dispose();
    super.dispose();
  }

  /// The eased drawn selection (`selectedIndexAnimatedHolder.set(...)`,
  /// SlideChooseView.java:222).
  double get selectedIndexAnimated =>
      _indexFrom +
      (_indexTarget - _indexFrom) *
          kTgSlideChooserCurve.transform(_indexController.value);

  /// The eased halo factor (`movingAnimatedHolder.set(moving ? 1 : 0)`,
  /// SlideChooseView.java:223).
  double get movingAnimated =>
      _movingFrom +
      (_movingTarget - _movingFrom) *
          kTgSlideChooserCurve.transform(_movingController.value);

  void _setMoving(bool moving) {
    if (_moving == moving) {
      return;
    }
    _moving = moving;
    _movingFrom = movingAnimated;
    _movingTarget = moving ? 1.0 : 0.0;
    _movingController.forward(from: 0.0);
  }

  void _select(int index) {
    if (index != widget.selectedIndex) {
      // `AndroidUtilities.vibrateCursor` on every actual change
      // (SlideChooseView.java:200-203).
      HapticFeedback.selectionClick();
      widget.onOptionSelected?.call(index);
    }
  }

  void _handleTouch(double x, {required bool commitTap}) {
    final double indexTouch =
        TgSlideChooser.indexForTouchX(_width, widget.options.length, x);
    final double rounded = indexTouch.roundToDouble();
    final bool isClose =
        (indexTouch - rounded).abs() < kTgSlideChooserSnapThreshold;
    if (commitTap || isClose) {
      _select(rounded.round());
    }
  }

  void _onDragStart(DragStartDetails details) {
    _setMoving(true);
    setState(() {});
  }

  void _onDragUpdate(DragUpdateDetails details) {
    // Crossing a stop while close to it selects it live
    // (SlideChooseView.java:170-176).
    _handleTouch(details.localPosition.dx, commitTap: false);
  }

  void _onDragEnd() {
    if (!_moving) {
      return;
    }
    _setMoving(false);
    setState(() {});
    widget.onTouchEnd?.call();
  }

  void _onTapUp(TapUpDetails details) {
    // A tap always snaps to the nearest stop (SlideChooseView.java:179-183).
    _handleTouch(details.localPosition.dx, commitTap: true);
    widget.onTouchEnd?.call();
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  @override
  Widget build(BuildContext context) {
    final Color track = _color(context, widget.trackColorKey);
    final Color active = _color(context, widget.activeColorKey);
    final Color text = _color(context, widget.textColorKey);
    final Color activeText = _color(context, widget.activeTextColorKey);
    final TextDirection textDirection = Directionality.of(context);
    final int count = widget.options.length;
    final bool canIncrease = widget.selectedIndex < count - 1;
    final bool canDecrease = widget.selectedIndex > 0;
    return Semantics(
      slider: true,
      // The a11y description is the selected label
      // (`getContentDescription`, SlideChooseView.java:91-94).
      value: widget.selectedIndex >= 0 && widget.selectedIndex < count
          ? widget.options[widget.selectedIndex]
          : null,
      increasedValue:
          canIncrease ? widget.options[widget.selectedIndex + 1] : null,
      decreasedValue:
          canDecrease ? widget.options[widget.selectedIndex - 1] : null,
      enabled: widget.onOptionSelected != null,
      onIncrease:
          canIncrease ? () => _select(widget.selectedIndex + 1) : null,
      onDecrease:
          canDecrease ? () => _select(widget.selectedIndex - 1) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Java tracks the touch from ACTION_DOWN (SlideChooseView.java:
        // 151-157); `DragStartBehavior.down` anchors the same way.
        dragStartBehavior: DragStartBehavior.down,
        onTapUp: _onTapUp,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: (DragEndDetails details) => _onDragEnd(),
        onHorizontalDragCancel: _onDragEnd,
        child: SizedBox(
          height: kTgSlideChooserHeight,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              _width = constraints.maxWidth;
              return AnimatedBuilder(
                animation: Listenable.merge(
                  <Listenable>[_indexController, _movingController],
                ),
                builder: (BuildContext context, Widget? child) {
                  return CustomPaint(
                    size: Size(constraints.maxWidth, kTgSlideChooserHeight),
                    painter: TgSlideChooserPainter(
                      options: widget.options,
                      selectedIndexAnimated: selectedIndexAnimated,
                      movingAnimated: movingAnimated,
                      trackColor: track,
                      activeColor: active,
                      textColor: text,
                      activeTextColor: activeText,
                      textDirection: textDirection,
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

/// Paints the `SlideChooseView.onDraw` strip (SlideChooseView.java:221-293):
/// per-stop dots and shrinking segments, labels, then the moving halo and
/// knob.
class TgSlideChooserPainter extends CustomPainter {
  /// Creates the painter.
  TgSlideChooserPainter({
    required this.options,
    required this.selectedIndexAnimated,
    required this.movingAnimated,
    required this.trackColor,
    required this.activeColor,
    required this.textColor,
    required this.activeTextColor,
    this.textDirection = TextDirection.ltr,
  });

  /// Stop labels.
  final List<String> options;

  /// Eased drawn selection (SlideChooseView.java:222).
  final double selectedIndexAnimated;

  /// Eased halo factor (SlideChooseView.java:223).
  final double movingAnimated;

  /// Resting dot/segment color (SlideChooseView.java:230).
  final Color trackColor;

  /// Selected dot/segment/knob color (SlideChooseView.java:230, 289-291).
  final Color activeColor;

  /// Resting label color (SlideChooseView.java:257).
  final Color textColor;

  /// Selected label color (SlideChooseView.java:257).
  final Color activeTextColor;

  /// Used only to lay text out; the geometry is fixed LTR like the Java
  /// `onDraw`.
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final int count = options.length;
    final double lineSize = TgSlideChooser.lineSizeFor(size.width, count);
    // `cy = height/2 + dp(11)` (SlideChooseView.java:224).
    final double cy = size.height / 2 + kTgSlideChooserTrackCenterOffset;

    for (int a = 0; a < count; a++) {
      final double cx = TgSlideChooser.dotCenterX(size.width, count, a * 1.0);
      // Selection proximity 0..1 (SlideChooseView.java:228) and the
      // "passed" fraction (SlideChooseView.java:229).
      final double t =
          (1.0 - (a - selectedIndexAnimated).abs()).clamp(0.0, 1.0);
      final double ut =
          (selectedIndexAnimated - a + 1.0).clamp(0.0, 1.0);
      final Color color = Color.lerp(trackColor, activeColor, ut)!;
      final Paint paint = Paint()..color = color;
      // Dot: radius lerp(3, 6, t) (SlideChooseView.java:233).
      canvas.drawCircle(
        Offset(cx, cy),
        kTgSlideChooserDotSize / 2 +
            (kTgSlideChooserSelectedDotRadius - kTgSlideChooserDotSize / 2) *
                t,
        paint,
      );
      if (a != 0) {
        // Segment between dot a-1 and a, shrinking 3dp near the selection
        // (SlideChooseView.java:234-236, 248-252).
        double x = cx - kTgSlideChooserDotSize / 2 -
            kTgSlideChooserGap -
            lineSize;
        double width = lineSize;
        final double nt =
            (1.0 - (a - selectedIndexAnimated - 1).abs()).clamp(0.0, 1.0);
        final double nct = (1.0 -
                math.min(
                  (a - selectedIndexAnimated).abs(),
                  (a - selectedIndexAnimated - 1).abs(),
                ))
            .clamp(0.0, 1.0);
        width -= kTgSlideChooserLineShrink * nct;
        x += kTgSlideChooserLineShrink * nt;
        canvas.drawRect(
          Rect.fromLTRB(
            x,
            cy - kTgSlideChooserLineHeight / 2,
            x + width,
            cy + kTgSlideChooserLineHeight / 2,
          ),
          paint,
        );
      }

      // Label: blend gray -> blue by t; first left-aligned at 22dp, last
      // right-aligned at width - 22dp, middle centered; baseline 28dp
      // (SlideChooseView.java:255-257, 275-281).
      final TextPainter label = TextPainter(
        text: TextSpan(
          text: options[a],
          style: TgTextStyles.caption.copyWith(
            color: Color.lerp(textColor, activeTextColor, t),
          ),
        ),
        textDirection: textDirection,
      )..layout();
      final double baseline =
          label.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      final double textY = kTgSlideChooserTextBaseline - baseline;
      final double textX;
      if (a == 0) {
        textX = kTgSlideChooserSideInset;
      } else if (a == count - 1) {
        textX = size.width - label.width - kTgSlideChooserSideInset;
      } else {
        textX = cx - label.width / 2;
      }
      label.paint(canvas, Offset(textX, textY));
    }

    // The moving knob: halo 12dp·movingAnimated at 80/255 alpha, then the
    // solid 6dp knob (SlideChooseView.java:288-292).
    final double knobX = TgSlideChooser.dotCenterX(
      size.width,
      count,
      selectedIndexAnimated,
    );
    canvas.drawCircle(
      Offset(knobX, cy),
      kTgSlideChooserHaloRadius * movingAnimated,
      Paint()..color = activeColor.withAlpha(kTgSlideChooserHaloAlpha),
    );
    canvas.drawCircle(
      Offset(knobX, cy),
      kTgSlideChooserSelectedDotRadius,
      Paint()..color = activeColor,
    );
  }

  @override
  bool shouldRepaint(TgSlideChooserPainter oldDelegate) =>
      oldDelegate.options != options ||
      oldDelegate.selectedIndexAnimated != selectedIndexAnimated ||
      oldDelegate.movingAnimated != movingAnimated ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.textColor != textColor ||
      oldDelegate.activeTextColor != activeTextColor ||
      oldDelegate.textDirection != textDirection;
}
