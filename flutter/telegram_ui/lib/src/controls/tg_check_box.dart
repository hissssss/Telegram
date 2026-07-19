// The round animated check box (PLAN_UIKIT.md M5).
//
// Port of `ui/Components/CheckBoxBase.java` (the canvas engine) wrapped the
// way `ui/Components/CheckBox2.java` frames it, exposing the three recipes
// production screens actually use instead of all 14 `backgroundType` magic
// ints (spec_forms.md §1):
//
// - plain (type 0): 1.2dp ring (CheckBoxBase.java:122-124), translucent
//   service-color interior when unchecked (CheckBoxBase.java:429, 465);
// - `.settingsRow` (type 10 + drawUnchecked, the CheckBoxCell round recipe,
//   CheckBoxCell.java:194-199): 1.5dp ring (CheckBoxBase.java:264-266) of
//   radius `rad - 1.5dp` (CheckBoxBase.java:453-459), one color for ring and
//   fill (`setCheckBoxColor` forwards `(background, background, check)`,
//   CheckBoxCell.java:527-531);
// - `.avatarOverlay` (type 3 + !drawUnchecked, the list-multiselect recipe,
//   ProxyListActivity.java:164, CachedMediaLayout.java:1030): 3dp ring
//   (CheckBoxBase.java:262-263) drawn as a 270°-per-progress arc
//   (CheckBoxBase.java:497-502, 516) fading in from transparent white
//   (CheckBoxBase.java:432-434).
//
// The signature animation is a single 0..1 progress, 200ms EASE_OUT
// (CheckBoxBase.java:277-294), split in two phases (CheckBoxBase.java:407,
// 521): 0-0.5 fills the disc as an annulus growing from the ring inward
// (erase-circle punch, CheckBoxBase.java:572-579 — realized here as an
// even-odd path, same result), 0.5-1 draws the check arms.
//
// Deliberately NOT ported: the other 11 backgroundType variants, number mode
// (`setNum`, CheckBoxBase.java:354-368, 595-621), forbidden dashed ring
// (CheckBoxBase.java:583-593), cutCheck compositing (CheckBoxBase.java:54-63),
// checkScale (CheckBoxBase.java:39), message-drawable gradient fills
// (CheckBoxBase.java:472-482), and CheckBox2's icon mode
// (CheckBox2.java:110-120, 138-148). CheckBox2 announces itself to
// accessibility as `android.widget.Switch` (CheckBox2.java:130-136) — the
// port uses proper checkbox semantics instead.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../foundation/tg_curves.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Canonical size: 21dp — 28 call sites (lists/settings; e.g.
/// `new CheckBox2(context, 21, ...)`, CheckBoxCell.java:194).
const double kTgCheckBoxSize = 21.0;

/// Photo-picker/media-grid size: 24dp — 13 call sites (spec_forms.md §1).
const double kTgCheckBoxPickerSize = 24.0;

/// Check-mark stroke: 1.9dp, round cap + round join
/// (CheckBoxBase.java:116-120).
const double kTgCheckBoxCheckStroke = 1.9;

/// Plain (type 0) ring stroke: 1.2dp (CheckBoxBase.java:122-124).
const double kTgCheckBoxRingStroke = 1.2;

/// Settings-row (type 10) ring stroke: 1.5dp (CheckBoxBase.java:264-266).
const double kTgCheckBoxSettingsRingStroke = 1.5;

/// Avatar-overlay (type 3) ring stroke: 3dp (CheckBoxBase.java:262-263).
const double kTgCheckBoxAvatarRingStroke = 3.0;

/// Toggle animation duration: 200ms (`animationDuration = 200`,
/// CheckBoxBase.java:277, 292).
const Duration kTgCheckBoxDuration = Duration(milliseconds: 200);

/// Toggle animation curve: `CubicBezierInterpolator.EASE_OUT`
/// (CheckBoxBase.java:291).
const Curve kTgCheckBoxCurve = TgCurves.easeOut;

/// Check anchor offset from center: `x = cx - 1.5dp`, `y = cy + 4dp`
/// (CheckBoxBase.java:632-633).
const Offset kTgCheckBoxCheckAnchor = Offset(-1.5, 4.0);

/// Long check arm: 9dp at full progress (CheckBoxBase.java:630).
const double kTgCheckBoxCheckLongArm = 9.0;

/// Short check arm: 4dp at full progress (CheckBoxBase.java:631).
const double kTgCheckBoxCheckShortArm = 4.0;

/// Non-plain types shave the outer ring radius by 0.2dp
/// (CheckBoxBase.java:401-403).
const double kTgCheckBoxOuterRadiusInset = 0.2;

/// The fill disc radius is `rad - 0.5dp` (CheckBoxBase.java:564, 573).
const double kTgCheckBoxFillInset = 0.5;

/// Settings-row unchecked ring radius inset: `rad - 1.5dp`
/// (CheckBoxBase.java:459).
const double kTgCheckBoxSettingsRingInset = 1.5;

/// Unchecked interior alpha for the plain recipe: 0x28/255
/// (`(serviceMessageColor & 0x00ffffff) | 0x28000000`,
/// CheckBoxBase.java:429).
const int kTgCheckBoxUncheckedInteriorAlpha = 0x28;

/// Progress-arc start angle for the default arc branch: 90°
/// (CheckBoxBase.java:498).
const double kTgCheckBoxArcStartAngle = 90.0;

/// Progress-arc sweep at full progress: 270° (`270 * progress`,
/// CheckBoxBase.java:499).
const double kTgCheckBoxArcSweepAngle = 270.0;

/// The three ported `backgroundType` recipes (spec_forms.md §1 port notes).
enum TgCheckBoxStyle {
  /// Type 0 — the bare `CheckBox2` default (CheckBoxBase.java:250-268 keeps
  /// the constructor 1.2dp ring).
  plain,

  /// Type 10 + `setDrawUnchecked(true)` — the `CheckBoxCell` round recipe
  /// (CheckBoxCell.java:194-199).
  settingsRow,

  /// Type 3 + `setDrawUnchecked(false)` — the select-over-avatar overlay
  /// (ProxyListActivity.java:164).
  avatarOverlay,
}

/// The avatar-overlay ring fade: `AndroidUtilities.getOffsetColor(0x00ffffff,
/// target, progress, 1f)` (CheckBoxBase.java:433; AndroidUtilities.java:
/// 5066-5077) — per-channel lerp from transparent white toward [target] with
/// Java's `(int)` truncation.
Color tgCheckBoxRingFadeColor(Color target, double progress) {
  const int fromRgb = 0xFF; // 0x00ffffff channels.
  final int a = ((target.a * 255.0) * progress).toInt();
  final int r = (fromRgb + ((target.r * 255.0) - fromRgb) * progress).toInt();
  final int g = (fromRgb + ((target.g * 255.0) - fromRgb) * progress).toInt();
  final int b = (fromRgb + ((target.b * 255.0) - fromRgb) * progress).toInt();
  return Color.fromARGB(a, r, g, b);
}

/// A round Telegram check box — the `CheckBoxBase`/`CheckBox2` port.
///
/// Controlled widget (TgSwitch precedent): [checked] in, [onChanged] out;
/// external [checked] changes animate the 200ms EASE_OUT two-phase progress
/// (CheckBoxBase.java:277-294). The three constructors map to the three
/// production recipes — see [TgCheckBoxStyle].
///
/// Like every component in this package, takes an optional [resources]
/// override that wins over the ambient theme (the Java `resourcesProvider`
/// convention); otherwise keys resolve through [TelegramTheme.colorOf].
class TgCheckBox extends StatefulWidget {
  /// The plain type-0 check box (bare `new CheckBox2(context, 21)`).
  const TgCheckBox({
    super.key,
    required this.checked,
    this.onChanged,
    this.size = kTgCheckBoxSize,
    this.enabled = true,
    this.fillColorKey = TelegramColorKey.checkbox,
    this.disabledFillColorKey = TelegramColorKey.checkboxDisabled,
    this.ringColorKey = TelegramColorKey.checkboxCheck,
    this.checkColorKey = TelegramColorKey.checkboxCheck,
    this.uncheckedInteriorColorKey = TelegramColorKey.chat_serviceBackground,
    this.resources,
  }) : style = TgCheckBoxStyle.plain;

  /// The `CheckBoxCell` round recipe: type 10, 21dp, drawUnchecked
  /// (CheckBoxCell.java:194-199). [colorKey] colors both the unchecked ring
  /// and the checked fill — `setCheckBoxColor(background, background1,
  /// check)` forwards `(background, background, check)`, the middle argument
  /// is ignored (CheckBoxCell.java:527-531). Java callers always pass their
  /// own key (e.g. CacheControlActivity.java:2545); the default here is the
  /// standard `checkbox` green.
  const TgCheckBox.settingsRow({
    super.key,
    required this.checked,
    this.onChanged,
    this.size = kTgCheckBoxSize,
    this.enabled = true,
    int colorKey = TelegramColorKey.checkbox,
    this.checkColorKey = TelegramColorKey.checkboxCheck,
    this.resources,
  })  : style = TgCheckBoxStyle.settingsRow,
        fillColorKey = colorKey,
        disabledFillColorKey = colorKey,
        ringColorKey = colorKey,
        uncheckedInteriorColorKey = TelegramColorKey.chat_serviceBackground;

  /// The list-multiselect overlay: type 3, no unchecked state, ring fading
  /// in from transparent white (CheckBoxBase.java:432-434). Key recipe
  /// `setColor(key_checkbox, key_radioBackground, key_checkboxCheck)`
  /// (ProxyListActivity.java:164, CachedMediaLayout.java:1030).
  const TgCheckBox.avatarOverlay({
    super.key,
    required this.checked,
    this.onChanged,
    this.size = kTgCheckBoxSize,
    this.enabled = true,
    this.fillColorKey = TelegramColorKey.checkbox,
    this.ringColorKey = TelegramColorKey.radioBackground,
    this.checkColorKey = TelegramColorKey.checkboxCheck,
    this.resources,
  })  : style = TgCheckBoxStyle.avatarOverlay,
        disabledFillColorKey = fillColorKey,
        uncheckedInteriorColorKey = TelegramColorKey.chat_serviceBackground;

  /// Which ported recipe draws (Java `backgroundType`).
  final TgCheckBoxStyle style;

  /// Current state; external changes animate (`setChecked(checked, true)`,
  /// CheckBoxBase.java:370-393).
  final bool checked;

  /// Called with the toggled value on tap. Null makes the box inert (the
  /// Java view is never clickable itself; rows handle taps — the handler
  /// here is a convenience for standalone use).
  final ValueChanged<bool>? onChanged;

  /// Diameter in dp — the `CheckBoxBase(parent, sz, rp)` constructor
  /// parameter (CheckBoxBase.java:109-112). Canonical 21, picker 24.
  final double size;

  /// Disabled boxes fill with [disabledFillColorKey] instead of
  /// [fillColorKey] (`enabled ? key_checkbox : key_checkboxDisabled`,
  /// CheckBoxBase.java:530) and ignore taps.
  final bool enabled;

  /// Checked fill color key (CheckBoxBase.java:523-531).
  final int fillColorKey;

  /// Checked fill when disabled (`key_checkboxDisabled`,
  /// CheckBoxBase.java:530; only the plain recipe swaps in Java).
  final int disabledFillColorKey;

  /// Ring color key — plain draws it directly (CheckBoxBase.java:430, 486);
  /// settingsRow uses it for the unchecked ring (CheckBoxBase.java:427,
  /// 459); avatarOverlay fades it in with the progress
  /// (CheckBoxBase.java:433).
  final int ringColorKey;

  /// Check-mark color key (`checkColorKey = key_checkboxCheck`,
  /// CheckBoxBase.java:79, 537-541).
  final int checkColorKey;

  /// Plain-recipe unchecked interior: this key at alpha 0x28
  /// (`Theme.getServiceMessageColor()`, CheckBoxBase.java:429 — resolved
  /// here through `chat_serviceBackground`, the same service color).
  final int uncheckedInteriorColorKey;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  /// Phase 1 fraction: `progress >= .5 ? 1 : progress / .5`
  /// (CheckBoxBase.java:407).
  static double roundProgressFor(double progress) =>
      progress >= 0.5 ? 1.0 : progress / 0.5;

  /// Phase 2 fraction: `progress < .5 ? 0 : (progress - .5) / .5`
  /// (CheckBoxBase.java:521).
  static double checkProgressFor(double progress) =>
      progress < 0.5 ? 0.0 : (progress - 0.5) / 0.5;

  @override
  State<TgCheckBox> createState() => TgCheckBoxState();
}

/// State of a [TgCheckBox]; public so tests can read [debugProgress].
class TgCheckBoxState extends State<TgCheckBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Initial state applies without animation (not attached -> jump,
    // CheckBoxBase.java:387-392).
    _controller = AnimationController(
      vsync: this,
      duration: kTgCheckBoxDuration,
      value: widget.checked ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(TgCheckBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.checked != oldWidget.checked) {
      // `animateToCheckedState` — 200ms EASE_OUT (CheckBoxBase.java:278-294).
      _controller.animateTo(
        widget.checked ? 1.0 : 0.0,
        curve: kTgCheckBoxCurve,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Current animated progress (the Java `progress` field,
  /// CheckBoxBase.java:74).
  double get debugProgress => _controller.value;

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  @override
  Widget build(BuildContext context) {
    final Color fill = _color(
      context,
      widget.enabled ? widget.fillColorKey : widget.disabledFillColorKey,
    );
    final Color ring = _color(context, widget.ringColorKey);
    final Color check = _color(context, widget.checkColorKey);
    final Color interior = _color(context, widget.uncheckedInteriorColorKey)
        .withAlpha(kTgCheckBoxUncheckedInteriorAlpha);
    final TextDirection textDirection = Directionality.of(context);
    final ValueChanged<bool>? onChanged = widget.onChanged;
    final bool interactive = widget.enabled && onChanged != null;
    return Semantics(
      // Proper checkbox semantics; the Java wrapper's `android.widget.Switch`
      // announcement (CheckBox2.java:130-136) is a platform quirk not
      // replicated.
      checked: widget.checked,
      enabled: interactive,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interactive ? () => onChanged(!widget.checked) : null,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            final double progress = _controller.value;
            return CustomPaint(
              size: Size.square(widget.size),
              painter: TgCheckBoxPainter(
                progress: progress,
                style: widget.style,
                diameter: widget.size,
                fillColor: fill,
                ringColor: widget.style == TgCheckBoxStyle.avatarOverlay
                    // Ring fades in from transparent white
                    // (CheckBoxBase.java:432-434).
                    ? tgCheckBoxRingFadeColor(ring, progress)
                    : ring,
                checkColor: check,
                uncheckedInteriorColor: interior,
                textDirection: textDirection,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints the `CheckBoxBase.draw` geometry (CheckBoxBase.java:395-655) for
/// the three ported recipes, centered in the canvas like the Java engine
/// centers in its bounds (CheckBoxBase.java:409-410).
class TgCheckBoxPainter extends CustomPainter {
  /// Creates the painter.
  const TgCheckBoxPainter({
    required this.progress,
    required this.style,
    required this.diameter,
    required this.fillColor,
    required this.ringColor,
    required this.checkColor,
    required this.uncheckedInteriorColor,
    this.textDirection = TextDirection.ltr,
  });

  /// Animated 0..1 progress (CheckBoxBase.java:74).
  final double progress;

  /// Which recipe (Java `backgroundType`).
  final TgCheckBoxStyle style;

  /// Drawn diameter in dp (`size`, CheckBoxBase.java:94, 396).
  final double diameter;

  /// Resolved checked fill (CheckBoxBase.java:523-536).
  final Color fillColor;

  /// Resolved ring color; for [TgCheckBoxStyle.avatarOverlay] the caller
  /// pre-applies the progress fade ([tgCheckBoxRingFadeColor]).
  final Color ringColor;

  /// Resolved check-mark color (CheckBoxBase.java:537-541).
  final Color checkColor;

  /// Plain-recipe unchecked interior (already at 0x28 alpha,
  /// CheckBoxBase.java:429).
  final Color uncheckedInteriorColor;

  /// RTL mirrors the progress-arc sweep (CheckBoxBase.java:500-502).
  final TextDirection textDirection;

  /// Ring stroke width for this recipe (CheckBoxBase.java:122-124, 250-268).
  double get ringStrokeWidth {
    switch (style) {
      case TgCheckBoxStyle.plain:
        return kTgCheckBoxRingStroke;
      case TgCheckBoxStyle.settingsRow:
        return kTgCheckBoxSettingsRingStroke;
      case TgCheckBoxStyle.avatarOverlay:
        return kTgCheckBoxAvatarRingStroke;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double cx = center.dx;
    final double cy = center.dy;
    // rad = dp(size / 2); non-0/11 types shave the outer radius by 0.2dp
    // (CheckBoxBase.java:396-404).
    final double rad = diameter / 2.0;
    final double outerRad = style == TgCheckBoxStyle.plain
        ? rad
        : rad - kTgCheckBoxOuterRadiusInset;

    final double roundProgress = TgCheckBox.roundProgressFor(progress);
    final double checkProgress = TgCheckBox.checkProgressFor(progress);

    final Paint ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringStrokeWidth
      ..color = ringColor;

    // Unchecked layer (`drawUnchecked`, CheckBoxBase.java:450-467) — drawn
    // at every progress; the fill covers it as it grows.
    switch (style) {
      case TgCheckBoxStyle.plain:
        // Translucent interior (CheckBoxBase.java:429, 465).
        canvas.drawCircle(
          center,
          rad,
          Paint()..color = uncheckedInteriorColor,
        );
        // Full ring for types 0/11 (CheckBoxBase.java:485-486).
        canvas.drawCircle(center, rad, ringPaint);
      case TgCheckBoxStyle.settingsRow:
        // Ring only, radius rad - 1.5dp (CheckBoxBase.java:453-459); type 10
        // is excluded from the arc section (CheckBoxBase.java:469).
        canvas.drawCircle(
          center,
          rad - kTgCheckBoxSettingsRingInset,
          ringPaint,
        );
      case TgCheckBoxStyle.avatarOverlay:
        // No unchecked state; the ring is a progress arc — start 90°, sweep
        // 270°·progress, mirrored in RTL (CheckBoxBase.java:497-502, 516).
        final double sweep = kTgCheckBoxArcSweepAngle *
            progress *
            (textDirection == TextDirection.rtl ? -1.0 : 1.0);
        if (sweep != 0.0) {
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: outerRad),
            kTgCheckBoxArcStartAngle * math.pi / 180.0,
            sweep * math.pi / 180.0,
            false,
            ringPaint,
          );
        }
    }

    if (roundProgress > 0.0) {
      // Fill disc of radius rad - 0.5dp with a concentric hole of radius
      // (rad - 0.5dp)·(1 - roundProgress) — Java punches it out with
      // PAINT_CLEAR in a saveLayer (CheckBoxBase.java:546-579); an even-odd
      // path draws the identical annulus.
      final double fillRad = rad - kTgCheckBoxFillInset;
      final Paint fillPaint = Paint()..color = fillColor;
      if (roundProgress >= 1.0) {
        canvas.drawCircle(center, fillRad, fillPaint);
      } else {
        final double hole = fillRad * (1.0 - roundProgress);
        final Path annulus = Path()
          ..fillType = PathFillType.evenOdd
          ..addOval(Rect.fromCircle(center: center, radius: fillRad))
          ..addOval(Rect.fromCircle(center: center, radius: hole));
        canvas.drawPath(annulus, fillPaint);
      }

      if (checkProgress != 0.0) {
        // Check arms 9dp/4dp at 45° from the anchor (cx - 1.5, cy + 4)
        // (CheckBoxBase.java:623-645); recipe scale is 1 for all three
        // ported types (CheckBoxBase.java:624-629).
        final double x = cx + kTgCheckBoxCheckAnchor.dx;
        final double y = cy + kTgCheckBoxCheckAnchor.dy;
        final double checkSide = kTgCheckBoxCheckLongArm * checkProgress;
        final double smallCheckSide = kTgCheckBoxCheckShortArm * checkProgress;
        final double smallSide =
            math.sqrt(smallCheckSide * smallCheckSide / 2.0);
        final double longSide = math.sqrt(checkSide * checkSide / 2.0);
        final Path check = Path()
          ..moveTo(x - smallSide, y - smallSide)
          ..lineTo(x, y)
          ..lineTo(x + longSide, y - longSide);
        canvas.drawPath(
          check,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = kTgCheckBoxCheckStroke
            ..color = checkColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(TgCheckBoxPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.style != style ||
      oldDelegate.diameter != diameter ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.checkColor != checkColor ||
      oldDelegate.uncheckedInteriorColor != uncheckedInteriorColor ||
      oldDelegate.textDirection != textDirection;
}
