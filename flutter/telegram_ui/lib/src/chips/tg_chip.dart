// The input chip (PLAN_UIKIT.md S4).
//
// Port of `ui/Components/GroupCreateSpan.java` — the avatar + name pill used
// by the group-create / contact-picker token fields: a 32dp rounded pill with
// a leading 32dp avatar, a 14dp name, and a delete state in which the avatar
// crossfades into a rotating "x" over the selection color while the pill and
// text tint toward it (GroupCreateSpan.java:323-371).
//
// Faithful details:
// - geometry regular/small: height 32/28, corner radius 16/14
//   (GroupCreateSpan.java:345-347), avatar 32/28 at the leading edge
//   (GroupCreateSpan.java:231), text at x 41/35 y 8/6
//   (GroupCreateSpan.java:364), measured width `dp((small ? 28-8 : 32)+25) +
//   textWidth` (GroupCreateSpan.java:317-320) — including the Java small-mode
//   quirks (26 vs 28 in the text offset, the `28 - 8`), text width ceil'd
//   (GroupCreateSpan.java:246);
// - delete progress: linear, 120ms (`progress += dt / 120f`,
//   GroupCreateSpan.java:331-341);
// - pill background lerps from `windowBackgroundWhiteBlackText` at 5% alpha
//   (GroupCreateSpan.java:263) to the selection color with per-channel Java
//   `(int)` truncation (GroupCreateSpan.java:346);
// - delete overlay: a circle of the selection color at alpha `progress`
//   (GroupCreateSpan.java:352-356) with the 10dp `R.drawable.delete` cross
//   (bounds 11..21 / 9..19, GroupCreateSpan.java:359) tinted
//   `groupcreate_spanDelete` (GroupCreateSpan.java:264, 273), fading in with
//   `progress` and rotating from 45° to 0° (GroupCreateSpan.java:358-361);
//   the avatar stays fully drawn beneath until `progress == 1`
//   (GroupCreateSpan.java:348-350);
// - name color blends `groupcreate_spanText` -> `avatar_text` with
//   `ColorUtils.blendARGB` truncation semantics (GroupCreateSpan.java:365-367);
// - newlines in the name flatten to spaces (GroupCreateSpan.java:240).
//
// Divergences (documented inline):
// - the delete cross rotates around the delete-circle center; the Java
//   hardcodes `dp(16)` as the pivot even in small mode
//   (GroupCreateSpan.java:358) — an evident quirk, ported as intent;
// - `R.drawable.delete` is a 10x10 white bitmap cross; the port draws the
//   equivalent two 2dp round-capped diagonals instead of shipping the asset;
// - the selection color is a parameter ([TgChip.selectedColor], defaulting to
//   the `avatar_backgroundBlue` key) instead of the Java
//   `avatarDrawable.getColor()` read (GroupCreateSpan.java:262, 352) — the
//   avatar here is a widget slot, so the caller supplies the matching color
//   (e.g. `TgAvatarColors.pairFor(id, resources).top`);
// - the max name width is a parameter ([TgChip.maxNameWidth]) instead of the
//   screen-size derivation (GroupCreateSpan.java:233-238), which is app
//   layout policy, ellipsized with `…` like `TextUtils.ellipsize(..., END)`
//   (GroupCreateSpan.java:243);
// - the chip draws in fixed LTR coordinates like the Java `onDraw`; RTL
//   placement of chips is the container's job (FLAG_DIRECTION is never
//   consulted in GroupCreateSpan).
//
// Deliberately NOT ported: the TLRPC User/Chat/Contact constructor overloads
// and their `uid`/`key` bookkeeping (GroupCreateSpan.java:102-226 — pass a
// [TgChip.avatar] slot and a name instead), the filter/premium/miniapps/
// country avatar types and their drawables, `Emoji.replaceEmoji` image spans
// (Flutter shapes emoji natively), the `NotificationCenter` emoji-loading
// listener (GroupCreateSpan.java:258), and the `FiltersView.java` search
// filter chip (a variant reference only per PLAN_UIKIT.md S4).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../foundation/color_math.dart';
import '../foundation/tg_text_styles.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Chip height: 32dp (`dp(small ? 28 : 32)`, GroupCreateSpan.java:319, 345).
const double kTgChipHeight = 32.0;

/// Small-mode chip height: 28dp (GroupCreateSpan.java:319, 345).
const double kTgChipSmallHeight = 28.0;

/// Pill corner radius: 16dp (`dp(small ? 14 : 16)`,
/// GroupCreateSpan.java:347).
const double kTgChipRadius = 16.0;

/// Small-mode pill corner radius: 14dp (GroupCreateSpan.java:347).
const double kTgChipSmallRadius = 14.0;

/// Leading avatar side: 32dp (`setImageCoords(..., dp(small ? 28 : 32), ...)`,
/// GroupCreateSpan.java:231).
const double kTgChipAvatarSize = 32.0;

/// Small-mode avatar side: 28dp (GroupCreateSpan.java:231).
const double kTgChipSmallAvatarSize = 28.0;

/// Avatar initials base size inside the chip: 20dp
/// (`avatarDrawable.setTextSize(dp(20))`, GroupCreateSpan.java:101).
const double kTgChipAvatarTextSize = 20.0;

/// Name text size: 14dp (`textPaint.setTextSize(dp(small ? 13 : 14))`,
/// GroupCreateSpan.java:93) — the regular-weight [TgTextStyles.subtitle] role.
const double kTgChipTextSize = 14.0;

/// Small-mode name text size: 13dp (GroupCreateSpan.java:93) — the
/// [TgTextStyles.caption] role.
const double kTgChipSmallTextSize = 13.0;

/// Name x offset: 41dp (`dp((small ? 26 : 32) + 9)`,
/// GroupCreateSpan.java:364).
const double kTgChipTextX = 41.0;

/// Small-mode name x offset: 35dp — the Java uses 26, not the 28dp avatar
/// width, in small mode (GroupCreateSpan.java:364).
const double kTgChipSmallTextX = 35.0;

/// Name top offset: 8dp (`dp(small ? 6 : 8)`, GroupCreateSpan.java:364).
const double kTgChipTextY = 8.0;

/// Small-mode name top offset: 6dp (GroupCreateSpan.java:364).
const double kTgChipSmallTextY = 6.0;

/// Width beyond the name: 57dp (`dp(32 + 25)`, GroupCreateSpan.java:317-320)
/// — 41dp leading (avatar + gap) + 16dp trailing.
const double kTgChipWidthExtra = 57.0;

/// Small-mode width beyond the name: 45dp (`dp(28 - 8 + 25)`,
/// GroupCreateSpan.java:317-320).
const double kTgChipSmallWidthExtra = 45.0;

/// Delete crossfade duration: 120ms (`progress += dt / 120.0f`,
/// GroupCreateSpan.java:332, 337). The ramp is linear — no interpolator.
const Duration kTgChipDeleteDuration = Duration(milliseconds: 120);

/// Delete cross rotation at progress 0: 45° (`canvas.rotate(45 * (1.0f -
/// progress), ...)`, GroupCreateSpan.java:358).
const double kTgChipDeleteIconRotation = 45.0;

/// Delete cross inset from the chip origin: 11dp (`setBounds(dp(small ? 9 :
/// 11), ...)`, GroupCreateSpan.java:359).
const double kTgChipDeleteIconInset = 11.0;

/// Small-mode delete cross inset: 9dp (GroupCreateSpan.java:359).
const double kTgChipSmallDeleteIconInset = 9.0;

/// Delete cross side: 10dp — bounds 11..21 (9..19 small),
/// GroupCreateSpan.java:359; `R.drawable.delete` is a 10x10dp asset.
const double kTgChipDeleteIconSize = 10.0;

/// Stroke of the two drawn diagonals standing in for the 10x10
/// `R.drawable.delete` bitmap (its arms are ~2px thick at mdpi).
const double kTgChipDeleteIconStroke = 2.0;

/// Resting pill alpha: `windowBackgroundWhiteBlackText` at 5%
/// (`Theme.multAlpha(..., 0.05f)`, GroupCreateSpan.java:263).
const double kTgChipBackgroundAlpha = 0.05;

/// The pill background at [progress]: per-channel
/// `c0 + (int) ((c1 - c0) * progress)` from the resting [from] to the
/// selection [to] — the Java `colors[]` lerp with its `(int)` truncation
/// (GroupCreateSpan.java:265-274, 346).
Color tgChipBackgroundColor(Color from, Color to, double progress) {
  final int f = from.toARGB32();
  final int t = to.toARGB32();
  int channel(int shift) {
    final int c0 = (f >> shift) & 0xFF;
    final int c1 = (t >> shift) & 0xFF;
    return c0 + ((c1 - c0) * progress).truncate();
  }

  return Color.fromARGB(channel(24), channel(16), channel(8), channel(0));
}

/// The name color at [progress]: `ColorUtils.blendARGB(text, textSelected,
/// progress)` (GroupCreateSpan.java:365-367) — per-channel
/// `(int) (c0 * (1 - ratio) + c1 * ratio)` float blend with the Java `(int)`
/// truncation (androidx `ColorUtils.blendARGB`).
Color tgChipTextColor(Color from, Color to, double progress) {
  final int f = from.toARGB32();
  final int t = to.toARGB32();
  final double inverse = 1.0 - progress;
  int channel(int shift) {
    final int c0 = (f >> shift) & 0xFF;
    final int c1 = (t >> shift) & 0xFF;
    return (c0 * inverse + c1 * progress).truncate();
  }

  return Color.fromARGB(channel(24), channel(16), channel(8), channel(0));
}

/// The `GroupCreateSpan` input chip: leading avatar, name, and an animated
/// delete state.
///
/// Controlled widget (TgSwitch/TgCheckBox precedent): [deleting] in,
/// callbacks out. Flipping [deleting] animates the 120ms linear crossfade
/// (GroupCreateSpan.java:325-341 — `startDeleteAnimation` /
/// `cancelDeleteAnimation`); a tap fires [onDeleted] when [deleting] is true
/// and [onTap] otherwise, mirroring the GroupCreateActivity span-click
/// recipe (tap once to arm, tap again to remove).
///
/// The [avatar] slot is typically a [TgAvatar] sized by the chip
/// (32dp regular / 28dp small, initials at 20dp per
/// GroupCreateSpan.java:101); pass the avatar's palette color as
/// [selectedColor] to reproduce the Java tint toward
/// `avatarDrawable.getColor()` (GroupCreateSpan.java:262, 352) — unset, the
/// chip tints toward the `avatar_backgroundBlue` key (the S4 default; the
/// Java "miniapps" span uses the same pair, GroupCreateSpan.java:160).
///
/// Like every component in this package, takes an optional [resources]
/// override that wins over the ambient theme (the Java `resourcesProvider`
/// convention); otherwise keys resolve through [TelegramTheme.colorOf].
class TgChip extends StatefulWidget {
  /// Creates an input chip.
  const TgChip({
    super.key,
    required this.name,
    this.avatar,
    this.selectedColor,
    this.selectedColorKey = TelegramColorKey.avatar_backgroundBlue,
    this.deleting = false,
    this.onTap,
    this.onDeleted,
    this.small = false,
    this.maxNameWidth,
    this.resources,
  });

  /// The chip label (the Java `firstName`); newlines flatten to spaces
  /// (GroupCreateSpan.java:240).
  final String name;

  /// Leading avatar slot — typically a [TgAvatar]; sized to 32dp (28dp
  /// small) at the leading edge (GroupCreateSpan.java:231). Hidden once the
  /// delete crossfade completes (`progress != 1f` gate,
  /// GroupCreateSpan.java:348-350).
  final Widget? avatar;

  /// The selection color the pill, circle, and text tint toward — the Java
  /// `avatarDrawable.getColor()` (GroupCreateSpan.java:262, 352). Wins over
  /// [selectedColorKey].
  final Color? selectedColor;

  /// Theme key resolved when [selectedColor] is null; defaults to
  /// `avatar_backgroundBlue` (PLAN_UIKIT.md S4; the Java "miniapps" span,
  /// GroupCreateSpan.java:160).
  final int selectedColorKey;

  /// Whether the chip shows the delete state; external changes animate
  /// (`startDeleteAnimation`/`cancelDeleteAnimation`,
  /// GroupCreateSpan.java:285-301).
  final bool deleting;

  /// Tap handler while not [deleting] — the GroupCreateActivity click
  /// recipe arms the delete state here.
  final VoidCallback? onTap;

  /// Tap handler while [deleting] — the second tap that removes the span
  /// (GroupCreateActivity's `span.isDeleting()` branch; the a11y "Delete"
  /// click action, GroupCreateSpan.java:377-378).
  final VoidCallback? onDeleted;

  /// Small mode: 28dp chip, 13dp text (the `small` constructor flag,
  /// GroupCreateSpan.java:85-93).
  final bool small;

  /// Max name width before `…` ellipsis — the Java screen-derived
  /// `maxNameWidth` (GroupCreateSpan.java:233-238, 243), surfaced as a
  /// parameter. Null never ellipsizes.
  final double? maxNameWidth;

  /// Per-surface palette override; defaults to the ambient theme.
  final TelegramResources? resources;

  /// The laid-out name width, ceil'd like the Java
  /// `Math.ceil(nameLayout.getLineWidth(0))` (GroupCreateSpan.java:246),
  /// after newline flattening and optional ellipsis.
  static double nameWidth(String name, {bool small = false, double? maxNameWidth}) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: name.replaceAll('\n', ' '),
        style: small ? TgTextStyles.caption : TgTextStyles.subtitle,
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      textHeightBehavior: kTgTextHeightBehavior,
    )..layout(maxWidth: maxNameWidth ?? double.infinity);
    final double width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  @override
  State<TgChip> createState() => TgChipState();
}

/// State of a [TgChip]; public so tests can read [debugProgress].
class TgChipState extends State<TgChip> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // A fresh mount snaps to the current state (controlled-widget
    // convention); the Java span always mounts at progress 0.
    _controller = AnimationController(
      vsync: this,
      duration: kTgChipDeleteDuration,
      value: widget.deleting ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(TgChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.deleting != oldWidget.deleting) {
      // Linear 120ms ramp both ways (GroupCreateSpan.java:331-341).
      _controller.animateTo(widget.deleting ? 1.0 : 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Current animated delete progress (the Java `progress` field,
  /// GroupCreateSpan.java:61).
  double get debugProgress => _controller.value;

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  void _handleTap() {
    // GroupCreateActivity's span click: armed spans delete, others arm.
    if (widget.deleting) {
      widget.onDeleted?.call();
    } else {
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool small = widget.small;
    final double height = small ? kTgChipSmallHeight : kTgChipHeight;
    final double radius = small ? kTgChipSmallRadius : kTgChipRadius;
    final double avatarSize = small ? kTgChipSmallAvatarSize : kTgChipAvatarSize;
    final String name = widget.name.replaceAll('\n', ' ');
    final double textWidth = TgChip.nameWidth(
      widget.name,
      small: small,
      maxNameWidth: widget.maxNameWidth,
    );
    final double width =
        (small ? kTgChipSmallWidthExtra : kTgChipWidthExtra) + textWidth;

    // Resting background: windowBackgroundWhiteBlackText at 5%
    // (GroupCreateSpan.java:263).
    final Color base = Color(multAlpha(
      _color(context, TelegramColorKey.windowBackgroundWhiteBlackText)
          .toARGB32(),
      kTgChipBackgroundAlpha,
    ));
    final Color selected =
        widget.selectedColor ?? _color(context, widget.selectedColorKey);
    final Color text = _color(context, TelegramColorKey.groupcreate_spanText);
    final Color textSelected = _color(context, TelegramColorKey.avatar_text);
    final Color deleteIcon =
        _color(context, TelegramColorKey.groupcreate_spanDelete);

    final Widget? avatar = widget.avatar;
    final bool interactive = widget.onTap != null || widget.onDeleted != null;
    return Semantics(
      // `info.setText(nameLayout.getText())` (GroupCreateSpan.java:376).
      label: name,
      button: interactive,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interactive ? _handleTap : null,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            final double progress = _controller.value;
            return SizedBox(
              width: width,
              height: height,
              child: CustomPaint(
                painter: TgChipPainter(
                  backgroundColor:
                      tgChipBackgroundColor(base, selected, progress),
                  radius: radius,
                  name: name,
                  textColor: tgChipTextColor(text, textSelected, progress),
                  small: small,
                  maxNameWidth: widget.maxNameWidth,
                ),
                foregroundPainter: TgChipDeletePainter(
                  progress: progress,
                  circleColor: selected,
                  iconColor: deleteIcon,
                  small: small,
                ),
                // Avatar drawn only while `progress != 1f`
                // (GroupCreateSpan.java:348-350).
                child: avatar != null && progress < 1.0
                    ? Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox.square(
                          dimension: avatarSize,
                          child: avatar,
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints the pill and the name (GroupCreateSpan.java:344-370, minus the
/// delete overlay — see [TgChipDeletePainter]). [backgroundColor] and
/// [textColor] arrive pre-blended for the current progress
/// ([tgChipBackgroundColor] / [tgChipTextColor]).
class TgChipPainter extends CustomPainter {
  /// Creates the painter.
  const TgChipPainter({
    required this.backgroundColor,
    required this.radius,
    required this.name,
    required this.textColor,
    this.small = false,
    this.maxNameWidth,
  });

  /// Blended pill color (GroupCreateSpan.java:346).
  final Color backgroundColor;

  /// Pill corner radius: 16/14dp (GroupCreateSpan.java:347).
  final double radius;

  /// Newline-flattened name (GroupCreateSpan.java:240).
  final String name;

  /// Blended name color (GroupCreateSpan.java:367).
  final Color textColor;

  /// Small mode flag: 13dp text at (35, 6) instead of 14dp at (41, 8)
  /// (GroupCreateSpan.java:93, 364).
  final bool small;

  /// Ellipsis width cap (GroupCreateSpan.java:243).
  final double? maxNameWidth;

  @override
  void paint(Canvas canvas, Size size) {
    // Pill: full bounds, r16/14 (GroupCreateSpan.java:345-347).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.0, 0.0, size.width, size.height),
        Radius.circular(radius),
      ),
      Paint()..color = backgroundColor,
    );

    // Name at (41, 8) / (35, 6) (GroupCreateSpan.java:364, 369).
    final TextStyle style = small ? TgTextStyles.caption : TgTextStyles.subtitle;
    final TextPainter painter = TextPainter(
      text: TextSpan(text: name, style: style.copyWith(color: textColor)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      textHeightBehavior: kTgTextHeightBehavior,
    )..layout(maxWidth: maxNameWidth ?? double.infinity);
    painter.paint(
      canvas,
      Offset(
        small ? kTgChipSmallTextX : kTgChipTextX,
        small ? kTgChipSmallTextY : kTgChipTextY,
      ),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(TgChipPainter oldDelegate) =>
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.radius != radius ||
      oldDelegate.name != name ||
      oldDelegate.textColor != textColor ||
      oldDelegate.small != small ||
      oldDelegate.maxNameWidth != maxNameWidth;
}

/// Paints the delete overlay (GroupCreateSpan.java:351-363): a circle of
/// [circleColor] at alpha [progress] covering the avatar slot, and the 10dp
/// cross tinted [iconColor], fading in with [progress] while rotating from
/// 45° to 0° (GroupCreateSpan.java:358-361).
class TgChipDeletePainter extends CustomPainter {
  /// Creates the painter.
  const TgChipDeletePainter({
    required this.progress,
    required this.circleColor,
    required this.iconColor,
    this.small = false,
  });

  /// Delete crossfade progress 0..1 (GroupCreateSpan.java:61).
  final double progress;

  /// Selection color of the circle — the Java `avatarDrawable.getColor()`
  /// (GroupCreateSpan.java:352).
  final Color circleColor;

  /// Cross tint: `groupcreate_spanDelete` (GroupCreateSpan.java:264, 273).
  final Color iconColor;

  /// Small mode: circle r14 at (14, 14), cross inset 9dp
  /// (GroupCreateSpan.java:356, 359).
  final bool small;

  @override
  void paint(Canvas canvas, Size size) {
    // `if (progress != 0)` (GroupCreateSpan.java:351).
    if (progress == 0.0) {
      return;
    }
    final double circleRadius = small ? kTgChipSmallRadius : kTgChipRadius;
    final Offset center = Offset(circleRadius, circleRadius);
    // Circle alpha = 255 * progress * (colorAlpha / 255)
    // (GroupCreateSpan.java:353-356) — multAlpha's truncation matches.
    canvas.drawCircle(
      center,
      circleRadius,
      Paint()..color = Color(multAlpha(circleColor.toARGB32(), progress)),
    );

    canvas.save();
    // Rotate 45°·(1 - progress) around the circle center; the Java pivots on
    // the hardcoded dp(16) even in small mode (GroupCreateSpan.java:358) —
    // ported as the evident intent (the circle center).
    final double angle =
        kTgChipDeleteIconRotation * (1.0 - progress) * math.pi / 180.0;
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-center.dx, -center.dy);

    // 10dp cross at bounds 11..21 / 9..19 (GroupCreateSpan.java:359), alpha
    // `progress` (`deleteDrawable.setAlpha((int) (255 * progress))`,
    // GroupCreateSpan.java:360). The white 10x10 bitmap under a MULTIPLY
    // filter renders as [iconColor]; drawn here as two 2dp round-capped
    // diagonals.
    final double inset =
        small ? kTgChipSmallDeleteIconInset : kTgChipDeleteIconInset;
    final Rect box = Rect.fromLTWH(
      inset,
      inset,
      kTgChipDeleteIconSize,
      kTgChipDeleteIconSize,
    );
    final double capInset = kTgChipDeleteIconStroke / 2.0;
    final Paint cross = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kTgChipDeleteIconStroke
      ..strokeCap = StrokeCap.round
      ..color = Color(multAlpha(iconColor.toARGB32(), progress));
    canvas.drawLine(
      Offset(box.left + capInset, box.top + capInset),
      Offset(box.right - capInset, box.bottom - capInset),
      cross,
    );
    canvas.drawLine(
      Offset(box.right - capInset, box.top + capInset),
      Offset(box.left + capInset, box.bottom - capInset),
      cross,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(TgChipDeletePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.circleColor != circleColor ||
      oldDelegate.iconColor != iconColor ||
      oldDelegate.small != small;
}
