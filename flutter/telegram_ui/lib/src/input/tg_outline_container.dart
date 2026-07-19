// Port of `ui/Components/OutlineTextContainerView.java` (OTC below) — the
// Material-outlined frame around the modern login/forms text fields
// (flutter/docs/spec_primitives.md section 5.4, PLAN_UIKIT M11):
//
// - rounded-rect outline, radius 8dp (OTC:211), stroke round-capped (OTC:83),
//   idle width `max(2px, 0.5dp)` -> selected 1.6667dp (OTC:64-65);
// - a 16dp label (OTC:81) that floats from the field center into a gap cut in
//   the top stroke at scale 0.75 (OTC:196-227), 14dp left inset with 4dp text
//   side gaps (OTC:23);
// - colors: label blends `windowBackgroundWhiteHintText` ->
//   `windowBackgroundWhiteValueText`, stroke blends
//   `windowBackgroundWhiteInputField` -> `windowBackgroundWhiteInputFieldActivated`,
//   error blends both toward `text_RedBold` (OTC:124-129);
// - every transition is a spring: stiffness 500, damping ratio 1 — no bounce
//   (OTC:179-183) — on a progress scaled by 100 in Java (OTC:25-48; the
//   multiplier only widens the working range against the spring epsilon, so
//   the port runs the same spring on the raw 0..1 progress).
//
// Deliberately NOT ported: the `forceUseCenter`/`forceUseCenter2`/
// `forceForceUseCenter` special cases (OTC:68, 90-103 — LoginActivity
// oddities), the `attachEditText` plumbing (OTC:105-112 — replaced by the
// declarative [TgOutlineContainer.useCenter] input), and RTL mirroring (the
// Java view draws LTR-only coordinates).
library;

import 'dart:math' as math;
import 'dart:ui' as ui show ClipOp;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;
import 'package:flutter/widgets.dart';

import '../foundation/tg_text_styles.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Label left inset: 14dp (`PADDING_LEFT = 14`,
/// OutlineTextContainerView.java:23).
const double kTgOutlinePaddingLeft = 14.0;

/// Side gap between the top-stroke gap edges and the label text: 4dp
/// (`PADDING_TEXT = 4`, OutlineTextContainerView.java:23).
const double kTgOutlinePaddingText = 4.0;

/// The Java spring progress multiplier: 100 (`SPRING_MULTIPLIER`,
/// OutlineTextContainerView.java:25). It only rescales the spring's working
/// range against the framework's end epsilon; the port runs the identical
/// spring on the raw 0..1 progress.
const double kTgOutlineSpringMultiplier = 100.0;

/// Idle stroke width, dp component: 0.5dp
/// (`strokeWidthRegular = Math.max(2, dp(0.5f))`,
/// OutlineTextContainerView.java:64). See [kTgOutlineStrokeWidthIdleMinPx]
/// and [TgOutlineContainer.idleStrokeWidth] for the physical-pixel floor.
const double kTgOutlineStrokeWidthIdle = 0.5;

/// Idle stroke width floor: 2 *physical* pixels
/// (the raw `2` in `Math.max(2, dp(0.5f))`, OutlineTextContainerView.java:64).
const double kTgOutlineStrokeWidthIdleMinPx = 2.0;

/// Selected stroke width: 1.6667dp
/// (`strokeWidthSelected = dp(1.6667f)`, OutlineTextContainerView.java:65).
const double kTgOutlineStrokeWidthSelected = 1.6667;

/// Label text size: 16dp (`textPaint.setTextSize(dp(16))`,
/// OutlineTextContainerView.java:81) — the [TgTextStyles.body] role.
const double kTgOutlineLabelTextSize = 16.0;

/// Top padding reserving space for the floated label: 6dp
/// (`setPadding(0, dp(6), 0, 0)`, OutlineTextContainerView.java:87).
const double kTgOutlineTopPadding = 6.0;

/// Spring stiffness: 500 (`setStiffness(500f)`,
/// OutlineTextContainerView.java:181).
const double kTgOutlineSpringStiffness = 500.0;

/// Spring damping ratio: 1 — `DAMPING_RATIO_NO_BOUNCY`
/// (OutlineTextContainerView.java:182).
const double kTgOutlineSpringDampingRatio = 1.0;

/// Label baseline offset inside its half-text-size band: 1.75dp
/// (`textOffset = textSize / 2f - dp(1.75f)`,
/// OutlineTextContainerView.java:196).
const double kTgOutlineLabelBaselineOffset = 1.75;

/// Floated label scale: 0.75 (`scaleX = 0.75f + 0.25f * (1f - titleProgress)`,
/// OutlineTextContainerView.java:204).
const double kTgOutlineLabelFloatedScale = 0.75;

/// Outline corner radius: 8dp (`drawRoundRect(rect, dp(8), dp(8), ...)`,
/// OutlineTextContainerView.java:211).
const double kTgOutlineRadius = 8.0;

/// Right inset of the drawn top-stroke run: 6dp
/// (`right = getWidth() - stroke - getPaddingRight() - dp(6)`,
/// OutlineTextContainerView.java:215).
const double kTgOutlineLineRightInset = 6.0;

/// The Material-outlined frame of the modern Telegram forms — an r8 stroked
/// rounded rect whose 16dp label floats from the field center into a gap cut
/// in the top stroke, with spring-driven focus/error recolors — the
/// `ui/Components/OutlineTextContainerView.java` port.
///
/// A controlled widget: [selected], [floating] and [error] are targets; each
/// change animates through the Java spring (stiffness 500, critically
/// damped, OTC:179-183). The first build snaps (the Java
/// `animateSelection(..., false)` path, OTC:155-164).
///
/// [useCenter] mirrors `useCenter` at OTC:199 — whether the label may rest in
/// the field center (the attached edit text is empty and has no hint). Pass
/// the field's emptiness; while `false` the label is pinned floated, which is
/// how a filled, unfocused field keeps its floated label in Java.
///
/// Like every component in this package, the container takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention, OTC:70-78); otherwise keys resolve through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class TgOutlineContainer extends StatefulWidget {
  /// Creates the outlined frame.
  const TgOutlineContainer({
    super.key,
    this.label = '',
    this.selected = false,
    this.floating,
    this.error = false,
    this.useCenter = true,
    this.leftPadding = 0.0,
    this.resources,
    this.child,
  });

  /// The label drawn on the frame (`setText`, OTC:114-117).
  final String label;

  /// Selection target: drives the stroke width and stroke color blend
  /// (`selectionProgress`, OTC:26-34). Callers pass focus
  /// (`animateSelection(hasFocus ? 1f : 0f)`, LoginActivity.java:5384 et
  /// al.).
  final bool selected;

  /// Label-float target (`titleProgress`, OTC:35-42). `null` follows
  /// [selected] — the common Java call sets both progresses together
  /// (`animateSelection(float)`, OTC:135-137).
  final bool? floating;

  /// Error target: blends label and stroke toward `text_RedBold`
  /// (`errorProgress` + `animateError`, OTC:44-48, 169-171).
  final bool error;

  /// Whether the label may rest in the field center — the Java
  /// `attachedEditText.length() == 0 && TextUtils.isEmpty(hint)` condition
  /// (OTC:199). When `false` the label is pinned floated in the top-stroke
  /// gap regardless of [floating].
  final bool useCenter;

  /// Extra x offset of the resting centered label, scaled away as it floats
  /// (`setLeftPadding` applied at OTC:186-190, 201) — the phone-prefix
  /// indent of LoginActivity.
  final double leftPadding;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  /// The wrapped field, padded [kTgOutlineTopPadding] from the top
  /// (OTC:87).
  final Widget? child;

  /// The idle stroke width in logical px: `max(2px, 0.5dp)` (OTC:64) —
  /// 2 physical pixels floor over a 0.5dp nominal width.
  static double idleStrokeWidth(double devicePixelRatio) => math.max(
      kTgOutlineStrokeWidthIdleMinPx / devicePixelRatio,
      kTgOutlineStrokeWidthIdle);

  @override
  State<TgOutlineContainer> createState() => TgOutlineContainerState();
}

/// State of [TgOutlineContainer]; public for test access to the spring
/// progress probes.
class TgOutlineContainerState extends State<TgOutlineContainer>
    with TickerProviderStateMixin {
  /// The Java spring: stiffness 500, critically damped (OTC:179-183).
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: kTgOutlineSpringStiffness,
    ratio: kTgOutlineSpringDampingRatio,
  );

  late final AnimationController _selection = AnimationController.unbounded(
      vsync: this, value: _selectionTarget);
  late final AnimationController _title =
      AnimationController.unbounded(vsync: this, value: _titleTarget);
  late final AnimationController _error =
      AnimationController.unbounded(vsync: this, value: _errorTarget);

  double get _selectionTarget => widget.selected ? 1.0 : 0.0;
  double get _titleTarget => (widget.floating ?? widget.selected) ? 1.0 : 0.0;
  double get _errorTarget => widget.error ? 1.0 : 0.0;

  /// Current `selectionProgress` (OTC:56).
  double get debugSelectionProgress => _selection.value;

  /// Current `titleProgress` (OTC:59).
  double get debugTitleProgress => _title.value;

  /// Current `errorProgress` (OTC:62).
  double get debugErrorProgress => _error.value;

  /// Port of `animateSpring` (OTC:173-184): retarget the running spring,
  /// carrying position and velocity over.
  void _animateSpring(AnimationController controller, double target) {
    if (!controller.isAnimating && controller.value == target) {
      return;
    }
    controller.animateWith(SpringSimulation(
      _spring,
      controller.value,
      target,
      controller.isAnimating ? controller.velocity : 0.0,
    ));
  }

  @override
  void didUpdateWidget(TgOutlineContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _animateSpring(_selection, _selectionTarget);
    _animateSpring(_title, _titleTarget);
    _animateSpring(_error, _errorTarget);
  }

  @override
  void dispose() {
    _selection.dispose();
    _title.dispose();
    _error.dispose();
    super.dispose();
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    return resources != null
        ? resources.getColor(key)
        : TelegramTheme.colorOf(context, key);
  }

  @override
  Widget build(BuildContext context) {
    // Palette end points (`updateColor`, OTC:124-129).
    final Color hintColor =
        _color(context, TelegramColorKey.windowBackgroundWhiteHintText);
    final Color valueColor =
        _color(context, TelegramColorKey.windowBackgroundWhiteValueText);
    final Color fieldColor =
        _color(context, TelegramColorKey.windowBackgroundWhiteInputField);
    final Color activatedColor = _color(
        context, TelegramColorKey.windowBackgroundWhiteInputFieldActivated);
    final Color errorColor = _color(context, TelegramColorKey.text_RedBold);
    final double idleStroke = TgOutlineContainer.idleStrokeWidth(
        MediaQuery.devicePixelRatioOf(context));
    final TextDirection textDirection = Directionality.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_selection, _title, _error]),
      builder: (BuildContext context, Widget? child) {
        // The critically damped spring never overshoots; clamp anyway so the
        // color blends stay inside the Java `blendARGB` domain.
        final double selection = clampDouble(_selection.value, 0.0, 1.0);
        final double title = clampDouble(_title.value, 0.0, 1.0);
        final double error = clampDouble(_error.value, 0.0, 1.0);
        return CustomPaint(
          painter: TgOutlineContainerPainter(
            label: widget.label,
            // Label: (hint -> value) -> error (OTC:125-126).
            labelColor: Color.lerp(
                Color.lerp(hintColor, valueColor, title), errorColor, error)!,
            // Stroke: (field -> activated) -> error (OTC:127-128).
            outlineColor: Color.lerp(
                Color.lerp(fieldColor, activatedColor, selection),
                errorColor,
                error)!,
            // Width lerp (OTC:30, 160).
            strokeWidth: lerpDouble(
                idleStroke, kTgOutlineStrokeWidthSelected, selection)!,
            titleProgress: title,
            useCenter: widget.useCenter,
            leftPadding: widget.leftPadding,
            textDirection: textDirection,
          ),
          child: child,
        );
      },
      // The Java container pads its content 6dp from the top (OTC:87).
      child: Padding(
        padding: const EdgeInsets.only(top: kTgOutlineTopPadding),
        child: widget.child,
      ),
    );
  }
}

/// Paints the outlined frame: the r8 rounded rect with a gap clipped out of
/// its top stroke, the two top-stroke runs closing over the gap, and the
/// floating label — the `OutlineTextContainerView.onDraw` port
/// (OTC:192-228).
///
/// All blends/lerps happen in the owning widget; the painter receives final
/// colors and the final stroke width.
class TgOutlineContainerPainter extends CustomPainter {
  /// Creates the painter with resolved colors and progress.
  TgOutlineContainerPainter({
    required this.label,
    required this.labelColor,
    required this.outlineColor,
    required this.strokeWidth,
    required this.titleProgress,
    this.useCenter = true,
    this.leftPadding = 0.0,
    this.textDirection = TextDirection.ltr,
    super.repaint,
  });

  /// The label text (`mText`, OTC:51).
  final String label;

  /// Resolved label color (`textPaint` color, OTC:125-126).
  final Color labelColor;

  /// Resolved stroke color (`outlinePaint` color, OTC:127-128).
  final Color outlineColor;

  /// Resolved stroke width in logical px (idle->selected lerp, OTC:30).
  final double strokeWidth;

  /// Label float progress 0 centered .. 1 floated (`titleProgress`, OTC:59).
  final double titleProgress;

  /// Whether the label may rest centered (OTC:199); see
  /// [TgOutlineContainer.useCenter].
  final bool useCenter;

  /// Resting-label x offset (`leftPadding`, OTC:186-190).
  final double leftPadding;

  /// Direction for label text layout (the Java view itself is LTR-only).
  final TextDirection textDirection;

  TextPainter _labelPainter() => TextPainter(
        text: TextSpan(
          text: label,
          // 16dp regular (OTC:81) = the TgTextStyles.body role; dp-fixed
          // like the Java Paint (no user font scaling).
          style: TgTextStyles.body.copyWith(color: labelColor),
        ),
        textDirection: textDirection,
        textScaler: TextScaler.noScaling,
        textHeightBehavior: kTgTextHeightBehavior,
        maxLines: 1,
      )..layout();

  /// Label placement for a given box — baseline y, unscaled draw x and the
  /// scale factor (OTC:196-205). Public as a golden-free test probe.
  ({double baselineY, double x, double scaleX}) labelGeometry(Size size) {
    // textOffset = textSize / 2 - dp(1.75) (OTC:196).
    final double textOffset =
        kTgOutlineLabelTextSize / 2.0 - kTgOutlineLabelBaselineOffset;
    // topY = paddingTop + textOffset (OTC:197; container padding is (0,6,0,0),
    // OTC:87).
    final double topY = kTgOutlineTopPadding + textOffset;
    // centerY = height / 2 + textSize / 2 (OTC:198).
    final double centerY = size.height / 2.0 + kTgOutlineLabelTextSize / 2.0;
    // textY / textX (OTC:200-201) plus the 14dp draw inset (OTC:226).
    final double baselineY =
        useCenter ? topY + (centerY - topY) * (1.0 - titleProgress) : topY;
    final double x = kTgOutlinePaddingLeft +
        (useCenter ? leftPadding * (1.0 - titleProgress) : 0.0);
    // scaleX (OTC:204).
    final double scaleX = useCenter
        ? kTgOutlineLabelFloatedScale +
            (1.0 - kTgOutlineLabelFloatedScale) * (1.0 - titleProgress)
        : kTgOutlineLabelFloatedScale;
    return (baselineY: baselineY, x: x, scaleX: scaleX);
  }

  /// The two top-stroke runs closing over the label gap (OTC:214-222):
  /// `[leftStart, leftEnd]` and `[rightStart, rightEnd]` at height [lineY]
  /// (centerline). While the label is centered the runs overlap (no gap);
  /// floated, the left run collapses and the right run starts past the
  /// label. Public as a golden-free test probe.
  ({
    double lineY,
    double leftStart,
    double leftEnd,
    double rightStart,
    double rightEnd,
  }) topStroke(Size size) {
    final ({double baselineY, double x, double scaleX}) geometry =
        labelGeometry(size);
    // textWidth = measureText(mText) * scaleX (OTC:205).
    final TextPainter textPainter = _labelPainter();
    final double textWidth = textPainter.width * geometry.scaleX;
    textPainter.dispose();
    // left / lineY / right (OTC:214-215).
    final double left = kTgOutlinePaddingLeft - kTgOutlinePaddingText;
    final double lineY = kTgOutlineTopPadding + strokeWidth;
    final double right = size.width - strokeWidth - kTgOutlineLineRightInset;
    // Fields with a permanent top label draw the gap fully open
    // (`useCenter ? titleProgress : 1f`, OTC:219, 222).
    final double t = useCenter ? titleProgress : 1.0;
    // activeLeft / fromLeft (OTC:217-218), fromRight (OTC:221).
    final double activeLeft =
        left + textWidth + (kTgOutlinePaddingLeft - kTgOutlinePaddingText);
    final double fromLeft = left + textWidth / 2.0;
    final double fromRight = left + textWidth / 2.0 + kTgOutlinePaddingText;
    return (
      lineY: lineY,
      leftStart: left,
      leftEnd: fromRight + (left - fromRight) * t,
      rightStart: fromLeft + (activeLeft - fromLeft) * t,
      rightEnd: right,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round // OTC:83.
      ..strokeWidth = strokeWidth
      ..color = outlineColor;

    final double stroke = strokeWidth;

    // Rounded rect with the label band clipped out of its top stroke
    // (OTC:207-212).
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        kTgOutlinePaddingLeft - kTgOutlinePaddingText,
        kTgOutlineTopPadding,
        size.width - (kTgOutlinePaddingLeft + kTgOutlinePaddingText),
        kTgOutlineTopPadding + stroke * 2.0,
      ),
      clipOp: ui.ClipOp.difference,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(stroke, kTgOutlineTopPadding + stroke,
            size.width - stroke, size.height - stroke),
        const Radius.circular(kTgOutlineRadius),
      ),
      paint,
    );
    canvas.restore();

    // The two runs closing the clipped band around the label (OTC:214-222).
    final ({
      double lineY,
      double leftStart,
      double leftEnd,
      double rightStart,
      double rightEnd,
    }) runs = topStroke(size);
    canvas.drawLine(Offset(runs.rightStart, runs.lineY),
        Offset(runs.rightEnd, runs.lineY), paint);
    canvas.drawLine(Offset(runs.leftStart, runs.lineY),
        Offset(runs.leftEnd, runs.lineY), paint);

    // The label, scaled about (18dp, textY) (OTC:224-227).
    if (label.isNotEmpty) {
      final ({double baselineY, double x, double scaleX}) geometry =
          labelGeometry(size);
      final TextPainter textPainter = _labelPainter();
      final double baselineOffset = textPainter
          .computeDistanceToActualBaseline(TextBaseline.alphabetic);
      final double pivotX = kTgOutlinePaddingLeft + kTgOutlinePaddingText;
      canvas.save();
      canvas.translate(pivotX, geometry.baselineY);
      canvas.scale(geometry.scaleX, geometry.scaleX);
      canvas.translate(-pivotX, -geometry.baselineY);
      textPainter.paint(
          canvas, Offset(geometry.x, geometry.baselineY - baselineOffset));
      canvas.restore();
      textPainter.dispose();
    }
  }

  @override
  bool shouldRepaint(TgOutlineContainerPainter oldDelegate) =>
      oldDelegate.label != label ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.outlineColor != outlineColor ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.titleProgress != titleProgress ||
      oldDelegate.useCenter != useCenter ||
      oldDelegate.leftPadding != leftPadding ||
      oldDelegate.textDirection != textDirection;
}
