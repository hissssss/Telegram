// The settings-list text row (ARCHITECTURE.md section 6, row "TextCell").
//
// Port of `ui/Cells/TextCell.java` plus the minimal switch it embeds
// (`ui/Components/Switch.java`), with every constant cited:
//
// - row height 50dp (`heightDp`, TextCell.java:62); subtitle rows are set to
//   60dp by their callers (`cell.heightDp = 60`, ThemeActivity.java:2688,
//   2697);
// - default left padding 23dp (TextCell.java:79), icon left 16dp
//   (TextCell.java:63), text-over-icon offset 58dp (TextCell.java:61,
//   `getOffsetFromImage`, TextCell.java:824-826);
// - title 16dp `windowBackgroundWhiteBlackText` (TextCell.java:97-98),
//   subtitle 13dp `windowBackgroundWhiteGrayText` (TextCell.java:104-105),
//   value 16dp `windowBackgroundWhiteValueText` (TextCell.java:111-113),
//   icon tint `windowBackgroundWhiteGrayIcon` MULTIPLY (TextCell.java:130);
// - 1-physical-px bottom divider added to the measured height
//   (TextCell.java:213; `Theme.dividerPaint` stroke width 1px,
//   Theme.java:8214, colored `key_divider`, Theme.java:8305), left inset
//   20dp without an icon / 58dp with one / 72dp in the dialogs variant
//   (TextCell.java:835);
// - switch slot 37x20dp, 22dp from the trailing edge, centered vertically
//   (TextCell.java:140, 211, 289-293);
// - disabled state: 0.5 alpha on the text views (TextCell.java:221-236).
//
// Deliberately NOT ported (kept as doc pointers): the RTL mirroring driven by
// `LocaleController.isRTL` is expressed through [Directionality] instead; the
// value spoilers view, sticker/emoji values (TextCell.java:524-566, 695-822),
// the colorful-icon background (TextCell.java:614-631, offset 52dp,
// TextCell.java:824-826), the loading stripe (TextCell.java:898-965), and the
// switch's ripple/check-icon arms (Switch.java:153-218, 296-326, 499-545).
library;

import 'package:flutter/widgets.dart';

import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';
import '../app_bar/glass_app_bar.dart' show TgAccelerateDecelerateCurve;

/// Default row height: `heightDp = 50` (TextCell.java:62).
const double kTextCellHeight = 50.0;

/// Height callers give subtitle rows: `cell.heightDp = 60`
/// (ThemeActivity.java:2688, 2697 — the Java cell never grows itself; its
/// `heightDp` field is set at bind time).
const double kTextCellSubtitleHeight = 60.0;

/// Default text left padding: `leftPadding = 23` (constructor default,
/// TextCell.java:79, 82-83).
const double kTextCellLeftPadding = 23.0;

/// Leading icon left edge: `imageLeft = 16` (TextCell.java:63).
const double kTextCellImageLeft = 16.0;

/// Text left edge when an icon is present: `offsetFromImage = 58`
/// (TextCell.java:61; `getOffsetFromImage(false)`, TextCell.java:824-826).
const double kTextCellOffsetFromImage = 58.0;

/// Title text size: 16dp (`textView.setTextSize(16)`, TextCell.java:98).
const double kTextCellTitleTextSize = 16.0;

/// Subtitle text size: 13dp (TextCell.java:105).
const double kTextCellSubtitleTextSize = 13.0;

/// Value text size: 16dp (`valueTextView.setTextSize(dp(16))`,
/// TextCell.java:113).
const double kTextCellValueTextSize = 16.0;

/// Title/subtitle vertical nudge: `viewTop = (...) / 2 + dp(1)`
/// (TextCell.java:270, 275).
const double kTextCellTextShiftY = 1.0;

/// Value vertical shift: `valueTextView.setTranslationY(dp(-2))`
/// (TextCell.java:116). The extra raw `+ 1` *physical* px of the value's
/// layout top (TextCell.java:254) is not reproduced.
const double kTextCellValueShiftY = -2.0;

/// Title-to-subtitle gap for 50dp rows: `margin = heightDp > 50 ? 4 : 2`
/// (TextCell.java:269).
const double kTextCellTitleSubtitleGap = 2.0;

/// Title-to-subtitle gap for taller rows (TextCell.java:269).
const double kTextCellTitleSubtitleGapTall = 4.0;

/// Divider left inset without an icon: 20dp (TextCell.java:835).
const double kTextCellDividerInsetPlain = 20.0;

/// Divider left inset with an icon: 58dp (TextCell.java:835).
const double kTextCellDividerInsetIcon = 58.0;

/// Divider left inset with an icon in the dialogs variant: 72dp
/// (`inDialogs`, TextCell.java:64, 154-156, 835).
const double kTextCellDividerInsetInDialogs = 72.0;

/// Trailing width reserved next to the title block:
/// `width - dp(71 + leftPadding) - valueWidth` (TextCell.java:193, 201-202).
/// 71dp covers the switch slot (22 + 37dp) plus breathing room.
const double kTextCellTextEndReserved = 71.0;

/// Value trailing inset delta: the value's right edge sits at
/// `leftPadding - 6` from the trailing edge (TextCell.java:255).
const double kTextCellValueEndInsetDelta = 6.0;

/// Value width cap as a fraction of the available width: the Java cell
/// ellipsizes the value at `displaySize.x / 2.5f` (TextCell.java:460, 476).
/// The port applies the same fraction to the cell's own width.
const double kTextCellValueMaxWidthFraction = 1 / 2.5;

/// Switch slot trailing inset: 22dp (`createFrame(37, 20, ..., 22, 0, 22,
/// 0)`, TextCell.java:140; layout TextCell.java:291).
const double kTextCellSwitchEndInset = 22.0;

/// Disabled alpha applied to the text views: 0.5 (TextCell.java:227-236).
const double kTextCellDisabledAlpha = 0.5;

/// A settings text row: title, optional subtitle, optional leading icon
/// slot, and a trailing value text *or* switch — the `ui/Cells/TextCell.java`
/// port.
///
/// Geometry (logical px == Android dp):
///
/// ```text
/// |-16-|icon|      title 16dp                    value 16dp |-17-|
/// |----58----|      subtitle 13dp             or  switch |-22-|
/// |-23-| title (no icon)                                       |
/// ```
///
/// The row is [kTextCellHeight] (50dp) tall — [kTextCellSubtitleHeight]
/// (60dp) once [subtitle] is set, matching what Java callers do
/// (ThemeActivity.java:2688) — plus one *physical* pixel when [divider] is
/// on, exactly like `setMeasuredDimension(width, height + (needDivider ? 1 :
/// 0))` (TextCell.java:213).
///
/// Like every component in this package, the cell takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise keys resolve through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class TextCell extends StatelessWidget {
  /// Creates a text row.
  const TextCell({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.icon,
    this.checked,
    this.onChanged,
    this.onTap,
    this.enabled = true,
    this.divider = false,
    this.inDialogs = false,
    this.dividerInset,
    this.height,
    this.leftPadding = kTextCellLeftPadding,
    this.imageLeft = kTextCellImageLeft,
    this.offsetFromImage = kTextCellOffsetFromImage,
    this.titleColorKey = TelegramColorKey.windowBackgroundWhiteBlackText,
    this.subtitleColorKey = TelegramColorKey.windowBackgroundWhiteGrayText,
    this.valueColorKey = TelegramColorKey.windowBackgroundWhiteValueText,
    this.iconColorKey = TelegramColorKey.windowBackgroundWhiteGrayIcon,
    this.resources,
  });

  /// Title, 16dp in [titleColorKey] (TextCell.java:97-98).
  final String title;

  /// Optional subtitle, 13dp in [subtitleColorKey] (`setSubtitle`,
  /// TextCell.java:975-982). Setting it changes the default row height to
  /// [kTextCellSubtitleHeight].
  final String? subtitle;

  /// Optional trailing value text, 16dp in [valueColorKey]
  /// (TextCell.java:111-113). Mutually exclusive with the switch in Java
  /// (`setTextAndValue` hides the check, TextCell.java:467-469); here both
  /// simply render if both are set.
  final String? value;

  /// Leading icon slot, left edge at [imageLeft], vertically centered
  /// (TextCell.java:278-282). [IconTheme] is set to [iconColorKey] — the
  /// analog of the `windowBackgroundWhiteGrayIcon` MULTIPLY filter
  /// (TextCell.java:130).
  final Widget? icon;

  /// Switch state; non-null shows the 37x20dp [TgSwitch] 22dp from the
  /// trailing edge (TextCell.java:140). Null hides the slot.
  final bool? checked;

  /// Called with the toggled value when the switch row is tapped. The Java
  /// switch itself is not clickable — the enclosing row toggles it — so the
  /// whole cell is the tap target here too.
  final ValueChanged<bool>? onChanged;

  /// Row tap callback (the list-item `onClick` of the Java side). When null
  /// and [checked] is set, a tap toggles the switch via [onChanged].
  final VoidCallback? onTap;

  /// Disabled rows draw their text at [kTextCellDisabledAlpha] and ignore
  /// taps (`setEnabled`, TextCell.java:221-236 — Java animates the alpha;
  /// the port applies it directly). The icon keeps full alpha, as in Java.
  final bool enabled;

  /// Whether the 1-physical-px bottom divider draws (`needDivider`,
  /// TextCell.java:213, 828-837).
  final bool divider;

  /// Dialogs variant flag: with an icon, the divider inset becomes 72dp
  /// (`setIsInDialogs`, TextCell.java:154-156, 835).
  final bool inDialogs;

  /// Explicit divider left inset override; defaults to [dividerInsetFor]
  /// (20/58/72dp, TextCell.java:835).
  final double? dividerInset;

  /// Row height override (`heightDp`, TextCell.java:62); defaults to 50dp,
  /// or 60dp with a [subtitle] (ThemeActivity.java:2688, 2697).
  final double? height;

  /// Text left padding without an icon (TextCell.java:79).
  final double leftPadding;

  /// Icon left edge (TextCell.java:63).
  final double imageLeft;

  /// Text left edge when [icon] is set (TextCell.java:61).
  final double offsetFromImage;

  /// Title color key; `windowBackgroundWhiteBlackText` by default
  /// (TextCell.java:97; overridable like `setColors`, TextCell.java:324-332).
  final int titleColorKey;

  /// Subtitle color key (TextCell.java:104).
  final int subtitleColorKey;

  /// Value color key (TextCell.java:111).
  final int valueColorKey;

  /// Icon tint key (TextCell.java:130).
  final int iconColorKey;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  /// The Java divider-inset rule (TextCell.java:835): 20dp without an icon,
  /// 58dp with one, 72dp with an icon in the dialogs variant.
  static double dividerInsetFor({
    required bool hasIcon,
    bool inDialogs = false,
  }) {
    if (!hasIcon) {
      return kTextCellDividerInsetPlain;
    }
    return inDialogs
        ? kTextCellDividerInsetInDialogs
        : kTextCellDividerInsetIcon;
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = this.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  void _handleTap() {
    final VoidCallback? onTap = this.onTap;
    if (onTap != null) {
      onTap();
      return;
    }
    final bool? checked = this.checked;
    if (checked != null) {
      onChanged?.call(!checked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasIcon = icon != null;
    final bool hasSwitch = checked != null;
    final double rowHeight =
        height ?? (subtitle != null ? kTextCellSubtitleHeight : kTextCellHeight);
    // The divider is 1 *physical* pixel (Theme.dividerPaint strokeWidth 1,
    // Theme.java:8214), and Java adds that pixel to the measured height
    // (TextCell.java:213).
    final double devicePixelRatio =
        MediaQuery.maybeDevicePixelRatioOf(context) ??
            View.of(context).devicePixelRatio;
    final double dividerThickness = divider ? 1.0 / devicePixelRatio : 0.0;
    final double textStart = hasIcon ? offsetFromImage : leftPadding;
    // Trailing text inset: with a value the value's right edge sits at
    // `leftPadding - 6` (TextCell.java:255); otherwise the title measure
    // reserves 71dp (TextCell.java:193, 201) — which is what clears the
    // switch slot (22 + 37dp).
    final double textEnd = value != null
        ? leftPadding - kTextCellValueEndInsetDelta
        : kTextCellTextEndReserved;
    // `margin = heightDp > 50 ? 4 : 2` (TextCell.java:269).
    final double subtitleGap = rowHeight > kTextCellHeight
        ? kTextCellTitleSubtitleGapTall
        : kTextCellTitleSubtitleGap;

    final Widget titleBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: kTextCellTitleTextSize,
            color: _color(context, titleColorKey),
          ),
        ),
        if (subtitle != null) SizedBox(height: subtitleGap),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: kTextCellSubtitleTextSize,
              color: _color(context, subtitleColorKey),
            ),
          ),
      ],
    );

    final Widget textRow = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Row(
          children: <Widget>[
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                // `viewTop = (...) / 2 + dp(1)` (TextCell.java:270, 275).
                child: Transform.translate(
                  offset: const Offset(0, kTextCellTextShiftY),
                  child: titleBlock,
                ),
              ),
            ),
            if (value != null)
              // `setTranslationY(dp(-2))` (TextCell.java:116).
              Transform.translate(
                offset: const Offset(0, kTextCellValueShiftY),
                child: ConstrainedBox(
                  // Ellipsize cap `displaySize.x / 2.5f` (TextCell.java:460),
                  // applied to the cell's own width here.
                  constraints: BoxConstraints(
                    maxWidth:
                        constraints.maxWidth * kTextCellValueMaxWidthFraction,
                  ),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: kTextCellValueTextSize,
                      color: _color(context, valueColorKey),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );

    final Widget cell = SizedBox(
      width: double.infinity,
      height: rowHeight + dividerThickness,
      child: CustomPaint(
        foregroundPainter: divider
            ? TextCellDividerPainter(
                color: _color(context, TelegramColorKey.divider),
                inset: dividerInset ??
                    dividerInsetFor(hasIcon: hasIcon, inDialogs: inDialogs),
                thickness: dividerThickness,
                textDirection: Directionality.of(context),
              )
            : null,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: textStart,
                  end: textEnd,
                ),
                // Disabled alpha 0.5 on the text views only
                // (TextCell.java:227-235) — the icon stays opaque.
                child: Opacity(
                  opacity: enabled ? 1.0 : kTextCellDisabledAlpha,
                  child: textRow,
                ),
              ),
            ),
            if (hasIcon)
              PositionedDirectional(
                start: imageLeft,
                top: 0,
                bottom: 0,
                child: Center(
                  widthFactor: 1.0,
                  child: IconTheme.merge(
                    data: IconThemeData(color: _color(context, iconColorKey)),
                    child: icon!,
                  ),
                ),
              ),
            if (hasSwitch)
              PositionedDirectional(
                end: kTextCellSwitchEndInset,
                top: 0,
                bottom: 0,
                child: Center(
                  widthFactor: 1.0,
                  child: TgSwitch(
                    checked: checked!,
                    onChanged: enabled ? onChanged : null,
                    resources: resources,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!enabled || (onTap == null && !(hasSwitch && onChanged != null))) {
      return cell;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: cell,
    );
  }
}

/// Paints the cell's 1-physical-px bottom divider — `Theme.dividerPaint`
/// (stroke width 1px, Theme.java:8214; color `key_divider`, Theme.java:8305)
/// drawn at `getMeasuredHeight() - 1` with the leading inset of
/// TextCell.java:835 (mirrored under RTL, same line).
class TextCellDividerPainter extends CustomPainter {
  /// Creates the divider painter.
  const TextCellDividerPainter({
    required this.color,
    required this.inset,
    required this.thickness,
    required this.textDirection,
  });

  /// Divider color (`key_divider`, Theme.java:8305).
  final Color color;

  /// Leading inset in logical px (20/58/72dp, TextCell.java:835).
  final double inset;

  /// Line thickness — one physical pixel in logical px (Theme.java:8214).
  final double thickness;

  /// Reading direction; the inset applies to the leading edge
  /// (TextCell.java:835).
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final double left = textDirection == TextDirection.ltr ? inset : 0.0;
    final double right =
        textDirection == TextDirection.ltr ? size.width : size.width - inset;
    canvas.drawRect(
      Rect.fromLTRB(left, size.height - thickness, right, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(TextCellDividerPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.inset != inset ||
      oldDelegate.thickness != thickness ||
      oldDelegate.textDirection != textDirection;
}

/// Switch view size: 37x20dp (`createFrame(37, 20, ...)`, TextCell.java:140;
/// measured exactly, TextCell.java:211).
const Size kTgSwitchSize = Size(37, 20);

/// Track width: `dp(31)` (Switch.java:380).
const double kTgSwitchTrackWidth = 31.0;

/// Track height: `dpf2(14)` (Switch.java:383, 448).
const double kTgSwitchTrackHeight = 14.0;

/// Track corner radius: `dpf2(7)` (Switch.java:449).
const double kTgSwitchTrackRadius = 7.0;

/// Thumb outer radius, drawn in the track color: `dpf2(10)` — a 20dp circle
/// (Switch.java:450).
const double kTgSwitchThumbRadius = 10.0;

/// Thumb core radius, drawn in the thumb color: `dp(8)` (Switch.java:497).
const double kTgSwitchThumbCoreRadius = 8.0;

/// Thumb rest inset from the track's left edge: `x + dp(7)`
/// (Switch.java:384).
const double kTgSwitchThumbInset = 7.0;

/// Thumb travel: `dp(17) * progress` (Switch.java:384).
const double kTgSwitchThumbTravel = 17.0;

/// Toggle animation duration: `checkAnimator.setDuration(200)`
/// (Switch.java:238).
const Duration kTgSwitchDuration = Duration(milliseconds: 200);

/// Toggle animation curve: the Java `ObjectAnimator` runs its default
/// `AccelerateDecelerateInterpolator` (none is set, Switch.java:236-246).
const Curve kTgSwitchCurve = TgAccelerateDecelerateCurve();

/// Minimal Cupertino-free port of `ui/Components/Switch.java` as `TextCell`
/// configures it (TextCell.java:138-140):
///
/// - 37x20dp view; track 31x14dp, corner radius 7dp, centered
///   (Switch.java:380-383, 448-449);
/// - thumb center `x + dp(7) + dp(17) * progress` (Switch.java:384): a 20dp
///   circle in the track color (radius 10dp, Switch.java:450) with an 8dp-
///   radius core in the thumb color (Switch.java:497);
/// - track color lerps `switchTrack` -> `switchTrackChecked` per channel
///   with the progress (Switch.java:425-445); thumb color lerps its own key
///   pair (Switch.java:480-495) — both `windowBackgroundWhite` in the
///   TextCell recipe (`setColors(key_switchTrack, key_switchTrackChecked,
///   key_windowBackgroundWhite, key_windowBackgroundWhite)`,
///   TextCell.java:139). The bare Java defaults differ (`fill_RedNormal` /
///   `switch2TrackChecked`, Switch.java:60-63); pass the key parameters to
///   reproduce them;
/// - toggling animates the progress over 200ms (Switch.java:237-238) with
///   the default accelerate-decelerate interpolator.
///
/// The drawing does not mirror under RTL — neither does the Java `onDraw`
/// (fixed left-to-right thumb math, Switch.java:380-385). Ripple, check/lock
/// icon overlays, and the color-override snapshot machinery
/// (Switch.java:153-218, 296-326, 332-372, 499-545) are not ported.
class TgSwitch extends StatefulWidget {
  /// Creates a switch.
  const TgSwitch({
    super.key,
    required this.checked,
    this.onChanged,
    this.trackColorKey = TelegramColorKey.switchTrack,
    this.trackCheckedColorKey = TelegramColorKey.switchTrackChecked,
    this.thumbColorKey = TelegramColorKey.windowBackgroundWhite,
    this.thumbCheckedColorKey = TelegramColorKey.windowBackgroundWhite,
    this.resources,
  });

  /// Current state; external changes animate over [kTgSwitchDuration]
  /// (`setChecked(checked, animated: true)`, Switch.java:276-294).
  final bool checked;

  /// Called with the toggled value on tap. Null makes the switch inert (the
  /// Java view is never clickable itself; tap handling here is a convenience
  /// for standalone use).
  final ValueChanged<bool>? onChanged;

  /// Unchecked track color key (TextCell recipe `key_switchTrack`,
  /// TextCell.java:139).
  final int trackColorKey;

  /// Checked track color key (`key_switchTrackChecked`, TextCell.java:139).
  final int trackCheckedColorKey;

  /// Unchecked thumb-core color key (`key_windowBackgroundWhite`,
  /// TextCell.java:139).
  final int thumbColorKey;

  /// Checked thumb-core color key (`key_windowBackgroundWhite`,
  /// TextCell.java:139).
  final int thumbCheckedColorKey;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  /// Thumb center x for a given [progress] — `x + dp(7) + dp(17) * progress`
  /// with `x = (width - dp(31)) / 2` (Switch.java:380-384).
  static double thumbCenterX(double progress, {double width = 37.0}) =>
      (width - kTgSwitchTrackWidth) / 2 +
      kTgSwitchThumbInset +
      kTgSwitchThumbTravel * progress;

  @override
  State<TgSwitch> createState() => TgSwitchState();
}

/// State of a [TgSwitch]; public so tests can read [debugProgress].
class TgSwitchState extends State<TgSwitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Initial state applies without animation (`setProgress(checked ? 1 :
    // 0)`, Switch.java:287).
    _controller = AnimationController(
      vsync: this,
      duration: kTgSwitchDuration,
      value: widget.checked ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(TgSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.checked != oldWidget.checked) {
      // `animateToCheckedState` (Switch.java:236-246): 200ms to 0/1.
      _controller.animateTo(
        widget.checked ? 1.0 : 0.0,
        curve: kTgSwitchCurve,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Current animated progress (the Java `progress` field, Switch.java:46).
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
    final Color track = _color(context, widget.trackColorKey);
    final Color trackChecked = _color(context, widget.trackCheckedColorKey);
    final Color thumb = _color(context, widget.thumbColorKey);
    final Color thumbChecked = _color(context, widget.thumbCheckedColorKey);
    final ValueChanged<bool>? onChanged = widget.onChanged;
    return Semantics(
      toggled: widget.checked,
      enabled: onChanged != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap:
            onChanged == null ? null : () => onChanged(!widget.checked),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            final double progress = _controller.value;
            return CustomPaint(
              size: kTgSwitchSize,
              painter: TgSwitchPainter(
                progress: progress,
                // Per-channel color interpolation (Switch.java:425-445,
                // 480-495) — what Color.lerp computes.
                trackColor: Color.lerp(track, trackChecked, progress)!,
                thumbColor: Color.lerp(thumb, thumbChecked, progress)!,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints the `Switch.onDraw` geometry (Switch.java:374-497): the 31x14dp
/// round-rect track and the 20dp track-colored thumb circle with its 8dp-
/// radius core.
class TgSwitchPainter extends CustomPainter {
  /// Creates the painter.
  const TgSwitchPainter({
    required this.progress,
    required this.trackColor,
    required this.thumbColor,
  });

  /// Animated 0..1 checked progress (Switch.java:46).
  final double progress;

  /// Interpolated track (and thumb ring) color (Switch.java:445-450).
  final Color trackColor;

  /// Interpolated thumb-core color (Switch.java:495-497).
  final Color thumbColor;

  @override
  void paint(Canvas canvas, Size size) {
    // x = (w - dp(31)) / 2, y = (h - dpf2(14)) / 2 (Switch.java:380-383).
    final double x = (size.width - kTgSwitchTrackWidth) / 2;
    final double y = (size.height - kTgSwitchTrackHeight) / 2;
    // tx = x + dp(7) + dp(17) * progress, ty = h / 2 (Switch.java:384-385).
    final double tx =
        x + kTgSwitchThumbInset + kTgSwitchThumbTravel * progress;
    final double ty = size.height / 2;
    final Offset thumbCenter = Offset(tx, ty);

    final Paint paint = Paint()..color = trackColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, kTgSwitchTrackWidth, kTgSwitchTrackHeight),
        const Radius.circular(kTgSwitchTrackRadius),
      ),
      paint,
    );
    // Thumb ring in the track color (Switch.java:450)...
    canvas.drawCircle(thumbCenter, kTgSwitchThumbRadius, paint);
    // ...and the core in the thumb color (Switch.java:497).
    canvas.drawCircle(
      thumbCenter,
      kTgSwitchThumbCoreRadius,
      Paint()..color = thumbColor,
    );
  }

  @override
  bool shouldRepaint(TgSwitchPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.thumbColor != thumbColor;
}
