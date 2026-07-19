// The popup/context-menu row (PLAN_UIKIT.md M4).
//
// Port of `ui/ActionBar/ActionBarMenuSubItem.java`, with every constant
// cited:
//
// - height exactly 48dp (`itemHeight` default, ActionBarMenuSubItem.java:51;
//   forced EXACTLY in onMeasure, :126-131);
// - padding 18dp horizontal (:84); the icon-side padding drops to 8dp when a
//   right icon is installed (:176);
// - text 16dp, single line, ellipsize end, start-aligned, vertically
//   centered, color `key_actionBarDefaultSubmenuItem` (:91-98, 78); text
//   start padding 43dp when a leading icon is present (:217), 34dp with the
//   leading check (:112-113);
// - leading icon: wrap-content frame 40dp tall, centered vertically at the
//   start (:86-89), 24dp glyphs (animated icons are explicitly 24x24, :337),
//   tint `key_actionBarDefaultSubmenuItemIcon` MULTIPLY (:79, 88);
// - optional right icon: 24dp-wide end frame, label end margin 32dp
//   (:159-176);
// - optional subtext: 13dp `key_groupcreate_sectionText` at the same
//   indent; the main label gets a 10dp bottom margin while the subtext gets
//   a 10dp top margin, both CENTER_VERTICAL — centers at 19dp/29dp of the
//   48dp row (:356-378);
// - optional check: a `CheckBox2` of size 26 that draws the check only (no
//   unchecked circle), colored `key_actionBarDefaultSubmenuItem`
//   (:104-119); the check-state change animates 200ms EASE_OUT
//   (CheckBoxBase.java:277-292); the check path is the CheckBoxBase arm
//   geometry (CheckBoxBase.java:623-645);
// - pressed selector `Theme.createRadSelectorDrawable(key_dialogButtonSelector,
//   topRad, bottomRad)` — the fill is clipped to rounded top/bottom corners,
//   12dp on the container's first/last visible row and 0 elsewhere (:47, 81,
//   395-416; Theme.java:6100-6108). The enclosing [TgPopupMenu] drives the
//   flags through [TgMenuRowScope];
// - disabled rows render at 0.5 alpha and ignore taps (the popup animators
//   enforce the alpha, ActionBarPopupWindow.java:886, 908, 989).
//
// Deliberately NOT ported: the ripple expansion of the selector (a plain
// pressed fill, the TgAlertDialogCell precedent); the multiline mode (2
// lines at 14dp, :191-204) and `expandIfMultiline` (+8dp, :128-130); the
// trailing check placement (`needCheck == 2`, :114-116); the RTL `scaleX =
// -1` mirroring of the right icon glyph (:164-166 — positions mirror through
// [Directionality], glyphs do not flip); the BackupImageView thumbnail slot
// (:225-248); the animated enable/disable color blend (:273-319 — the port
// switches the 0.5 alpha directly); Lottie icon autoplay on land
// (`onItemShown`, :340-344).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../foundation/tg_curves.dart';
import '../foundation/tg_text_styles.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Row height: exactly 48dp (`itemHeight = 48`, ActionBarMenuSubItem.java:51,
/// forced in onMeasure, :126-131).
const double kTgMenuItemHeight = 48.0;

/// Horizontal padding: 18dp (`setPadding(dp(18), 0, dp(18), 0)`,
/// ActionBarMenuSubItem.java:84).
const double kTgMenuItemHorizontalPadding = 18.0;

/// Icon-side padding when a right icon is installed: 8dp
/// (ActionBarMenuSubItem.java:176).
const double kTgMenuItemRightIconSidePadding = 8.0;

/// Label text size: 16dp (ActionBarMenuSubItem.java:97) — the
/// [TgTextStyles.body] role.
const double kTgMenuItemTextSize = 16.0;

/// Subtext size: 13dp (ActionBarMenuSubItem.java:365) — the
/// [TgTextStyles.caption] role.
const double kTgMenuItemSubtextSize = 13.0;

/// Label bottom margin / subtext top margin when a subtext is shown: 10dp
/// (ActionBarMenuSubItem.java:367, 374).
const double kTgMenuItemSubtextMargin = 10.0;

/// Text start indent when a leading icon is present: 43dp
/// (`textView.setPadding(dp(43), ...)`, ActionBarMenuSubItem.java:217).
const double kTgMenuItemIconIndent = 43.0;

/// Text start indent with the leading check: 34dp
/// (ActionBarMenuSubItem.java:112-113).
const double kTgMenuItemCheckIndent = 34.0;

/// Leading icon frame height: 40dp, centered vertically
/// (`createFrame(WRAP_CONTENT, 40, CENTER_VERTICAL | LEFT)`,
/// ActionBarMenuSubItem.java:89).
const double kTgMenuItemIconFrameHeight = 40.0;

/// Icon glyph size: 24dp (animated icons are explicitly `setAnimation(resId,
/// 24, 24)`, ActionBarMenuSubItem.java:337).
const double kTgMenuItemIconSize = 24.0;

/// Check box size: 26dp (`new CheckBox2(context, 26, ...)`,
/// ActionBarMenuSubItem.java:106).
const double kTgMenuItemCheckSize = 26.0;

/// Right icon frame width: 24dp (`createFrame(24, MATCH_PARENT, ...)`,
/// ActionBarMenuSubItem.java:167).
const double kTgMenuItemRightIconWidth = 24.0;

/// Label end margin when a right icon is installed: 32dp
/// (ActionBarMenuSubItem.java:171-173).
const double kTgMenuItemRightIconTextMargin = 32.0;

/// Pressed-selector corner radius on the container's first/last row: 12dp
/// (`selectorRad = 12`, ActionBarMenuSubItem.java:47; legacy
/// `setupRadialSelectors` used 6dp, ActionBarPopupWindow.java:604-610).
const double kTgMenuItemSelectorRadius = 12.0;

/// Disabled row alpha: 0.5 (enforced by the popup open animators,
/// ActionBarPopupWindow.java:886, 908, 989).
const double kTgMenuItemDisabledAlpha = 0.5;

/// Check-toggle animation: 200ms (`animationDuration = 200`,
/// CheckBoxBase.java:277, 292) at EASE_OUT (CheckBoxBase.java:291).
const Duration kTgMenuItemCheckDuration = Duration(milliseconds: 200);

/// Corner-rounding contract between [TgPopupMenu] and its rows — the port of
/// `updateRadialSelectors()` driving
/// `ActionBarMenuSubItem.updateSelectorBackground(top, bottom)`
/// (ActionBarPopupWindow.java:612-643; ActionBarMenuSubItem.java:395-416).
///
/// The container wraps each row in a scope: the first visible row (and any
/// row directly after a gap) gets [roundTop], the last visible row gets
/// [roundBottom]. A [TgMenuItem] whose own `roundTop`/`roundBottom` are null
/// reads the enclosing scope, so rows stay position-agnostic.
class TgMenuRowScope extends InheritedWidget {
  /// Wraps [child] with pressed-selector corner flags.
  const TgMenuRowScope({
    super.key,
    this.roundTop = false,
    this.roundBottom = false,
    this.selectorRadius = kTgMenuItemSelectorRadius,
    required super.child,
  });

  /// Whether the row rounds its top selector corners
  /// (ActionBarPopupWindow.java:635 — first visible row, or one right after
  /// a gap).
  final bool roundTop;

  /// Whether the row rounds its bottom selector corners
  /// (ActionBarPopupWindow.java:635 — last visible row).
  final bool roundBottom;

  /// Corner radius, 12dp by default (ActionBarMenuSubItem.java:47).
  final double selectorRadius;

  /// The nearest enclosing scope, or null. Registers a dependency.
  static TgMenuRowScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TgMenuRowScope>();

  @override
  bool updateShouldNotify(TgMenuRowScope oldWidget) =>
      roundTop != oldWidget.roundTop ||
      roundBottom != oldWidget.roundBottom ||
      selectorRadius != oldWidget.selectorRadius;
}

/// One 48dp popup-menu row — the `ui/ActionBar/ActionBarMenuSubItem.java`
/// port.
///
/// Geometry (logical px == Android dp, LTR):
///
/// ```text
/// |-18-|icon 24 in 40-frame|      label 16dp        |-8-| right 24 |-8-|
/// |-18-|------43-----------| label / subtext 13dp
/// |-18-| label (no icon)
/// ```
///
/// Like every component in this package, the row takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise keys resolve through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class TgMenuItem extends StatefulWidget {
  /// Creates a menu row.
  const TgMenuItem({
    super.key,
    required this.text,
    this.onTap,
    this.icon,
    this.rightIcon,
    this.subtext,
    this.checked,
    this.enabled = true,
    this.roundTop,
    this.roundBottom,
    this.selectorRadius,
    this.textColorKey = TelegramColorKey.actionBarDefaultSubmenuItem,
    this.iconColorKey = TelegramColorKey.actionBarDefaultSubmenuItemIcon,
    this.subtextColorKey = TelegramColorKey.groupcreate_sectionText,
    this.selectorColorKey = TelegramColorKey.dialogButtonSelector,
    this.checkColorKey = TelegramColorKey.actionBarDefaultSubmenuItem,
    this.resources,
  });

  /// Row label, 16dp single line ellipsized end
  /// (ActionBarMenuSubItem.java:91-98).
  final String text;

  /// Tap handler; the enclosing [TgPopupMenuRoute] additionally pops the
  /// route. Null (or [enabled] false) makes the row inert.
  final VoidCallback? onTap;

  /// Optional leading icon widget, centered in the 40dp-tall start frame and
  /// tinted [iconColorKey] through [IconTheme]
  /// (ActionBarMenuSubItem.java:86-89).
  final Widget? icon;

  /// Optional trailing icon widget in the 24dp end frame
  /// (ActionBarMenuSubItem.java:159-176).
  final Widget? rightIcon;

  /// Optional 13dp subtext under the label (ActionBarMenuSubItem.java:
  /// 356-378).
  final String? subtext;

  /// Non-null shows the leading 26dp check slot (`needCheck == 1`,
  /// ActionBarMenuSubItem.java:104-113); true draws the check (animating
  /// 200ms on change, CheckBoxBase.java:277-292). Ignored when [icon] is
  /// set (Java overlays both in the same start frame — not reproduced).
  final bool? checked;

  /// Disabled rows draw at [kTgMenuItemDisabledAlpha] and ignore taps
  /// (ActionBarPopupWindow.java:886, 908, 989).
  final bool enabled;

  /// Rounds the top selector corners; null defers to the enclosing
  /// [TgMenuRowScope] (ActionBarMenuSubItem.java:395-416).
  final bool? roundTop;

  /// Rounds the bottom selector corners; null defers to the enclosing
  /// [TgMenuRowScope].
  final bool? roundBottom;

  /// Selector corner radius; null defers to the scope's 12dp default
  /// (ActionBarMenuSubItem.java:47).
  final double? selectorRadius;

  /// Label color key, `actionBarDefaultSubmenuItem` by default
  /// (ActionBarMenuSubItem.java:78).
  final int textColorKey;

  /// Icon tint key, `actionBarDefaultSubmenuItemIcon` by default
  /// (ActionBarMenuSubItem.java:79).
  final int iconColorKey;

  /// Subtext color key, `groupcreate_sectionText` by default
  /// (ActionBarMenuSubItem.java:363).
  final int subtextColorKey;

  /// Pressed-fill key, `dialogButtonSelector` by default
  /// (ActionBarMenuSubItem.java:81).
  final int selectorColorKey;

  /// Check color key, `actionBarDefaultSubmenuItem` by default
  /// (`checkView.setColor(-1, -1, key_actionBarDefaultSubmenuItem)`,
  /// ActionBarMenuSubItem.java:108).
  final int checkColorKey;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)` (the Java `resourcesProvider`,
  /// ActionBarMenuSubItem.java:52, 418-420).
  final TelegramResources? resources;

  @override
  State<TgMenuItem> createState() => _TgMenuItemState();
}

class _TgMenuItemState extends State<TgMenuItem> {
  bool _pressed = false;

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  void _setPressed(bool pressed) {
    if (_pressed != pressed) {
      setState(() => _pressed = pressed);
    }
  }

  /// The leading slot: icon (43dp indent) wins over check (34dp indent)
  /// (ActionBarMenuSubItem.java:217, 112-113).
  Widget? _leadingSlot(BuildContext context) {
    final Widget? icon = widget.icon;
    if (icon != null) {
      return SizedBox(
        width: kTgMenuItemIconIndent,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          // Wrap-content frame, 40dp tall, CENTER_VERTICAL | start
          // (ActionBarMenuSubItem.java:89).
          child: SizedBox(
            height: kTgMenuItemIconFrameHeight,
            child: IconTheme.merge(
              data: IconThemeData(
                color: _color(context, widget.iconColorKey),
                size: kTgMenuItemIconSize,
              ),
              child: Center(child: icon),
            ),
          ),
        ),
      );
    }
    final bool? checked = widget.checked;
    if (checked != null) {
      return SizedBox(
        width: kTgMenuItemCheckIndent,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TweenAnimationBuilder<double>(
            // `setChecked(checked, true)` animates the progress 200ms
            // EASE_OUT (ActionBarMenuSubItem.java:137-142,
            // CheckBoxBase.java:277-292); the first build applies without
            // animation.
            tween: Tween<double>(end: checked ? 1.0 : 0.0),
            duration: kTgMenuItemCheckDuration,
            curve: TgCurves.easeOut,
            builder: (BuildContext context, double progress, Widget? _) {
              return CustomPaint(
                size: const Size.square(kTgMenuItemCheckSize),
                painter: TgMenuCheckPainter(
                  progress: progress,
                  color: _color(context, widget.checkColorKey),
                ),
              );
            },
          ),
        ),
      );
    }
    return null;
  }

  /// Label (and optional subtext). With a subtext, the label carries a 10dp
  /// bottom margin and the subtext a 10dp top margin, both CENTER_VERTICAL
  /// (ActionBarMenuSubItem.java:367, 374) — centers land at 19dp/29dp of
  /// the 48dp row.
  Widget _textBlock(BuildContext context) {
    final Widget label = Text(
      widget.text,
      maxLines: 1,
      // TruncateAt.END (ActionBarMenuSubItem.java:95).
      overflow: TextOverflow.ellipsis,
      textHeightBehavior: kTgTextHeightBehavior,
      // 16dp regular (ActionBarMenuSubItem.java:97).
      style: TgTextStyles.body.copyWith(
        color: _color(context, widget.textColorKey),
      ),
    );
    final String? subtext = widget.subtext;
    if (subtext == null) {
      return Align(alignment: AlignmentDirectional.centerStart, child: label);
    }
    return Stack(
      children: <Widget>[
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.only(bottom: kTgMenuItemSubtextMargin),
            child: label,
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.only(top: kTgMenuItemSubtextMargin),
            child: Text(
              subtext,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textHeightBehavior: kTgTextHeightBehavior,
              // 13dp `groupcreate_sectionText`
              // (ActionBarMenuSubItem.java:363-365).
              style: TgTextStyles.caption.copyWith(
                color: _color(context, widget.subtextColorKey),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool interactive = widget.enabled && widget.onTap != null;
    final TgMenuRowScope? scope = TgMenuRowScope.maybeOf(context);
    final bool roundTop = widget.roundTop ?? scope?.roundTop ?? false;
    final bool roundBottom = widget.roundBottom ?? scope?.roundBottom ?? false;
    final double radius = widget.selectorRadius ??
        scope?.selectorRadius ??
        kTgMenuItemSelectorRadius;
    final Widget? leading = _leadingSlot(context);
    final bool hasRightIcon = widget.rightIcon != null;

    final Widget row = Padding(
      // 18dp sides; 8dp on the icon side with a right icon
      // (ActionBarMenuSubItem.java:84, 176).
      padding: EdgeInsetsDirectional.only(
        start: kTgMenuItemHorizontalPadding,
        end: hasRightIcon
            ? kTgMenuItemRightIconSidePadding
            : kTgMenuItemHorizontalPadding,
      ),
      child: Row(
        children: <Widget>[
          ?leading,
          Expanded(child: _textBlock(context)),
          if (hasRightIcon)
            // Label end margin 32dp of which the end frame occupies 24dp
            // (ActionBarMenuSubItem.java:167-173).
            SizedBox(
              width: kTgMenuItemRightIconTextMargin,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: SizedBox(
                  width: kTgMenuItemRightIconWidth,
                  child: IconTheme.merge(
                    data: IconThemeData(
                      color: _color(context, widget.iconColorKey),
                      size: kTgMenuItemIconSize,
                    ),
                    child: Center(child: widget.rightIcon),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: interactive,
      checked: widget.checked,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: interactive ? (TapDownDetails d) => _setPressed(true) : null,
        onTapUp: interactive ? (TapUpDetails d) => _setPressed(false) : null,
        onTapCancel: interactive ? () => _setPressed(false) : null,
        onTap: interactive ? widget.onTap : null,
        child: DecoratedBox(
          // `createRadSelectorDrawable(selectorColor, top ? rad : 0,
          // bottom ? rad : 0)` (ActionBarMenuSubItem.java:414-416) as a
          // plain pressed fill.
          decoration: BoxDecoration(
            color: _pressed
                ? _color(context, widget.selectorColorKey)
                : const Color(0x00000000),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(roundTop ? radius : 0.0),
              bottom: Radius.circular(roundBottom ? radius : 0.0),
            ),
          ),
          child: SizedBox(
            height: kTgMenuItemHeight,
            width: double.infinity,
            child: Opacity(
              opacity: widget.enabled ? 1.0 : kTgMenuItemDisabledAlpha,
              child: row,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the CheckBox2 check mark of the menu row's check slot — the
/// `CheckBoxBase.draw` check-path geometry (CheckBoxBase.java:623-645) at
/// `drawUnchecked(false)` (ActionBarMenuSubItem.java:107), i.e. the check
/// arms only, no circle:
///
/// - anchor at `(cx - 1.5dp, cy + 4dp)` (CheckBoxBase.java:632-633);
/// - short arm `4dp * progress`, long arm `9dp * progress`, both at 45
///   degrees (`side = len / sqrt(2)`, CheckBoxBase.java:630-638);
/// - stroke 1.9dp, round cap (CheckBoxBase.java:116-120).
class TgMenuCheckPainter extends CustomPainter {
  /// Creates the check painter.
  const TgMenuCheckPainter({required this.progress, required this.color});

  /// Check progress 0..1 (the CheckBoxBase `checkProgress`).
  final double progress;

  /// Check color — `actionBarDefaultSubmenuItem` in the menu recipe
  /// (ActionBarMenuSubItem.java:108).
  final Color color;

  /// Check stroke width: 1.9dp (CheckBoxBase.java:120).
  static const double strokeWidth = 1.9;

  /// Long-arm length at full progress: 9dp (CheckBoxBase.java:630).
  static const double longArm = 9.0;

  /// Short-arm length at full progress: 4dp (CheckBoxBase.java:631).
  static const double shortArm = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) {
      return;
    }
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    // `x = cx - dp(1.5); y = cy + dp(4)` (CheckBoxBase.java:632-633).
    final double x = cx - 1.5;
    final double y = cy + 4.0;
    final double checkSide = longArm * progress;
    final double smallCheckSide = shortArm * progress;
    double side = math.sqrt(smallCheckSide * smallCheckSide / 2.0);
    final Path path = Path()..moveTo(x - side, y - side);
    path.lineTo(x, y);
    side = math.sqrt(checkSide * checkSide / 2.0);
    path.lineTo(x + side, y - side);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(TgMenuCheckPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
