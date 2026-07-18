// The chat-list row (ARCHITECTURE.md section 6, row "DialogCell").
//
// Simplified-but-faithful port of `java/org/telegram/ui/Cells/DialogCell.java`
// (an 8000+ line owner-drawn view). The port keeps the *layout constants* —
// every number below is cross-checked against the Java and cited — while the
// feature matrix (drafts, typing animations, reactions/mentions, tags, forum
// topics, archive pull, stories ring, checkboxes, reordering, spoilers,
// thumbnails, RTL-specific metrics) is intentionally NOT ported.
//
// Java facts mirrored here (all `dp` values are logical px, 1:1 per TgDimens):
//
// - layout constants (DialogCell.java:169-174): `avatarStart = 11`,
//   `messagePaddingStart = 72`, `heightDefault = 70`,
//   `heightThreeLines = 76`;
// - measured height = base + 1px separator — `getCollapsedHeight` adds the
//   separator pixel unconditionally (`if (useSeparator || true) height += 1`,
//   DialogCell.java:1019-1023), so the row is 71/77 tall whether or not the
//   line is painted;
// - two-line (default) geometry (DialogCell.java:2451-2470): avatar 52x52 at
//   (11, 9); text left `messagePaddingStart + 4` = 76 (L2466); timeTop 16
//   (L2454); countTop 38 (L2457); pinTop 39 (L2456); message top 39 (L2688);
//   message width `w - dp(72 + 20 - 12)` (L2459); name top 14 (L4081);
// - three-line geometry (DialogCell.java:2428-2449): avatar 56x56 at
//   (11, 11); text left `messagePaddingStart + 6` = 78 (L2443); timeTop 13
//   (L2431); countTop 42.33 (L2432-2434); pinTop 43 (L2433); message top 32
//   (L2682, up to two message lines, L2758); message width `w - dp(72 + 21)`
//   (L2436); name top 10 (L4081);
// - text sizes: name 16, message 15 — the forced `paintIndex = 1` sizes
//   (`if (... || true)`, DialogCell.java:1246-1258); time 12
//   (Theme.java:8472); counter 13 bold (`dialogs_countTextPaint2`,
//   Theme.java:8371-8372 `createCommonDialogResources`); "bold" is Roboto
//   Medium (`AndroidUtilities.bold()`, AndroidUtilities.java:260-269),
//   bundled by this package as the w500 family `RobotoMedium`;
// - name field width `w - nameLeft - dp(14 + 8) - timeWidth` with
//   `timeWidth = ceil(measureText(time))` (DialogCell.java:2261-2290);
// - unread badge (DialogCell.java:1224-1229): height 20.666 =
//   `2 * 6.333 text pad + 8 min text width` (the derivation is upstream's
//   own comment, L1224), text-pad 6.333, min text width 8, gap 17
//   (`25 - 8`), right margin 15.666; fill radius 11.5 (L5291); count text
//   drawn at `(countLeft + 6.333, countTop + 3)` in an ALIGN_CENTER layout
//   of width `countWidth = max(dp(8), ceil(measureText))` (L2510-2515,
//   L5264, L5298); fill key `chats_unreadCounter`, muted
//   `chats_unreadCounterMuted` (`dialogs_countPaint`/`dialogs_countGrayPaint`
//   selection at L5255, colors Theme.java:8508-8509), text
//   `chats_unreadCounterText` (Theme.java:8504-8505); when a count shows,
//   the message field shrinks by `countWidth + gap` (L2512-2513) and the pin
//   icon is suppressed (the `else if (getIsPinned())` draw chain,
//   L4517-4523);
// - pin icon at `w - intrinsicWidth - dp(14)` (L2491), top pinTop;
// - mute/verified glyphs anchor 6dp after the painted name width
//   (`nameMuteLeft = nameLeft + left + dp(6)`, LTR branch L2891): mute at
//   `anchor - dp(threeLines ? 0 : 1)`, top 17.5 / 13.5 (L4427-4428);
//   verified at `anchor - dp(1)`, top 16.5 / 13.5 (L4467-4471);
// - separator: 1px `Theme.dividerPaint` line at the bottom, left-inset
//   `messagePaddingStart` (72) unless a full separator (L4774-4791); the
//   divider color key (`dividerPaint.setColor(getColor(key_divider))`,
//   Theme.java `createCommonResources`);
// - color keys: `chats_name` (L4104), `chats_message` (Theme.java:8493),
//   `chats_message_threeLines` (DialogCell.java:1257), `chats_date`
//   (Theme.java:8501).
//
// Deliberate departures, each localized and documented at its use site:
//
// - the separator reserves/paints 1 *logical* px where Android adds 1
//   *physical* px — deterministic across devicePixelRatio (goldens);
// - when pinned, upstream shifts the time 24dp left and draws a pill-style
//   pin beside it (L2266, L4130-4155); the port keeps the classic
//   count-row pin slot only;
// - RTL is a pure mirror of the LTR metrics rather than the slightly
//   different Java RTL constants (e.g. L2461-2464);
// - providing both glyph slots stacks mute 6dp after verified (upstream
//   computes a single `nameMuteLeft` anchor for whichever glyph wins,
//   L2790-2806).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';

/// Pinned text metrics per ARCHITECTURE.md section 5 (TextView vs Paragraph
/// default-metric mismatch is golden-load-bearing).
const TextHeightBehavior _kTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
);

/// `Theme.getColor(key, resourcesProvider)`: an explicit per-surface
/// [resources] override wins, otherwise the granular per-key ambient lookup.
Color _resolve(BuildContext context, TelegramResources? resources, int key) {
  if (resources != null) {
    return resources.getColor(key);
  }
  return TelegramTheme.colorOf(context, key);
}

/// The extracted layout constants of `ui/Cells/DialogCell.java` — every value
/// is logical px, 1:1 with Android dp.
abstract final class DialogCellMetrics {
  /// Avatar left inset: `avatarStart = 11` (DialogCell.java:169).
  static const double avatarStart = 11.0;

  /// Base start of the text column and the separator inset:
  /// `messagePaddingStart = 72` (DialogCell.java:170).
  static const double messagePaddingStart = 72.0;

  /// Two-line row height before the separator: `heightDefault = 70`
  /// (DialogCell.java:171).
  static const double heightDefault = 70.0;

  /// Three-line row height before the separator: `heightThreeLines = 76`
  /// (DialogCell.java:172).
  static const double heightThreeLines = 76.0;

  /// Separator thickness reserved in the measured height. Android adds one
  /// *physical* pixel unconditionally (`if (useSeparator || true) height +=
  /// 1`, DialogCell.java:1019-1023); the port reserves one *logical* pixel
  /// so layout is deterministic across devicePixelRatio.
  static const double separatorHeight = 1.0;

  /// Row height including the always-reserved separator pixel
  /// (DialogCell.java:994-1031).
  static double height({bool threeLines = false}) =>
      (threeLines ? heightThreeLines : heightDefault) + separatorHeight;

  /// Avatar side: 52 two-line (DialogCell.java:2470) / 56 three-line
  /// (DialogCell.java:2447).
  static double avatarSize({bool threeLines = false}) =>
      threeLines ? 56.0 : 52.0;

  /// Avatar top: 9 two-line (DialogCell.java:2452) / 11 three-line
  /// (DialogCell.java:2429).
  static double avatarTop({bool threeLines = false}) => threeLines ? 11.0 : 9.0;

  /// Text column left: `messagePaddingStart + 4` = 76 two-line
  /// (DialogCell.java:2466) / `+ 6` = 78 three-line (DialogCell.java:2443).
  static double textStart({bool threeLines = false}) =>
      messagePaddingStart + (threeLines ? 6.0 : 4.0);

  /// Name layout top: 14 two-line / 10 three-line (DialogCell.java:4081).
  static double nameTop({bool threeLines = false}) => threeLines ? 10.0 : 14.0;

  /// Trailing space reserved after the name, before the time:
  /// `nameWidth = w - nameLeft - dp(14 + 8) - timeWidth`
  /// (DialogCell.java:2290).
  static const double nameTrailingGap = 22.0;

  /// Message layout top: 39 two-line (DialogCell.java:2688) / 32 three-line
  /// (DialogCell.java:2682).
  static double messageTop({bool threeLines = false}) =>
      threeLines ? 32.0 : 39.0;

  /// Total width consumed around the message field: two-line
  /// `dp(messagePaddingStart + 20 - 12)` = 80 LTR (DialogCell.java:2459) /
  /// three-line `dp(messagePaddingStart + 21)` = 93 (DialogCell.java:2436).
  static double messageWidthInset({bool threeLines = false}) =>
      threeLines ? messagePaddingStart + 21.0 : messagePaddingStart + 8.0;

  /// Floor of the message field width: `messageWidth = Math.max(dp(12),
  /// messageWidth)` (DialogCell.java:2652).
  static const double messageMinWidth = 12.0;

  /// Time layout top: 16 two-line (DialogCell.java:2454) / 13 three-line
  /// (DialogCell.java:2431).
  static double timeTop({bool threeLines = false}) => threeLines ? 13.0 : 16.0;

  /// Right margin of the time text: upstream draws the time at
  /// `w - dp(15) - timeWidth` (DialogCell.java:2268). Distinct from the
  /// unread badge's [badgeMargin] (`BADGE_MARGIN = 15.666f`,
  /// DialogCell.java:1229).
  static const double timeRightMargin = 15.0;

  /// Unread badge top: `countTop` 38 two-line (DialogCell.java:2457) /
  /// 42.33 three-line (DialogCell.java:2432-2434).
  static double countTop({bool threeLines = false}) =>
      threeLines ? 42.33 : 38.0;

  /// Pin icon top: 39 two-line (DialogCell.java:2456) / 43 three-line
  /// (DialogCell.java:2433).
  static double pinTop({bool threeLines = false}) => threeLines ? 43.0 : 39.0;

  /// Pin icon right margin: `pinLeft = w - intrinsicWidth - dp(14)`
  /// (DialogCell.java:2491).
  static const double pinRightMargin = 14.0;

  /// Badge text horizontal padding: `BADGE_TEXT_PADDING = 6.333f`
  /// (DialogCell.java:1226).
  static const double badgeTextPadding = 6.333;

  /// Badge minimum text width: `BADGE_TEXT_MIN_WIDTH = 8f`
  /// (DialogCell.java:1227).
  static const double badgeTextMinWidth = 8.0;

  /// Badge height — upstream's own derivation comment: `BADGE_SIZE =
  /// BADGE_TEXT_PADDING * 2 + BADGE_TEXT_MIN_WIDTH` = 20.666
  /// (DialogCell.java:1224-1225).
  static const double badgeHeight = badgeTextMinWidth + 2 * badgeTextPadding;

  /// Gap reserved next to a badge (message shrink, badge stacking):
  /// `BADGE_GAP = 25 - BADGE_TEXT_MIN_WIDTH` = 17 (DialogCell.java:1228,
  /// applied at L2512-2513).
  static const double badgeGap = 17.0;

  /// Badge right margin: `BADGE_MARGIN = 15.666f` (DialogCell.java:1229,
  /// applied at L2515).
  static const double badgeMargin = 15.666;

  /// Badge fill corner radius: `drawRoundRect(rect, dp(11.5f), dp(11.5f))`
  /// (DialogCell.java:5291).
  static const double badgeRadius = 11.5;

  /// Count text top inside the badge: `countTop + dpf2(3)`
  /// (DialogCell.java:5298).
  static const double badgeTextTop = 3.0;

  /// Gap between the painted name width and the mute/verified glyph anchor:
  /// `nameMuteLeft = nameLeft + left + dp(6)` (DialogCell.java:2891).
  static const double glyphGap = 6.0;

  /// Mute glyph x nudge off the anchor: `muteAnchor - dp(threeLines ? 0 : 1)`
  /// (DialogCell.java:4427).
  static double muteGlyphDx({bool threeLines = false}) =>
      threeLines ? 0.0 : -1.0;

  /// Mute glyph top: 17.5 two-line / 13.5 three-line (DialogCell.java:4428).
  static double muteGlyphTop({bool threeLines = false}) =>
      threeLines ? 13.5 : 17.5;

  /// Verified glyph x nudge off the anchor: `nameMuteLeft - dp(1)`
  /// (DialogCell.java:4471).
  static const double verifiedGlyphDx = -1.0;

  /// Verified glyph top: 16.5 two-line / 13.5 three-line
  /// (DialogCell.java:4467).
  static double verifiedGlyphTop({bool threeLines = false}) =>
      threeLines ? 13.5 : 16.5;

  /// Name text size: `dialogs_namePaint[1].setTextSize(dp(16))` — the forced
  /// paint index (DialogCell.java:1246, 1252).
  static const double nameFontSize = 16.0;

  /// Message text size: `dialogs_messagePaint[1].setTextSize(dp(15))`
  /// (DialogCell.java:1254).
  static const double messageFontSize = 15.0;

  /// Time text size: `dialogs_timePaint.setTextSize(dp(12))`
  /// (Theme.java:8472).
  static const double timeFontSize = 12.0;

  /// Counter text size: `dialogs_countTextPaint2.setTextSize(dp(13))`, bold
  /// (Theme.java `createCommonDialogResources`); DialogCell measures and
  /// draws counts with `dialogs_countTextPaint2` (DialogCell.java:2510-2511).
  static const double countFontSize = 13.0;

  /// Badge outer width for a measured count-text width: `countWidth =
  /// Math.max(dp(8), (int) Math.ceil(measureText))` plus
  /// `dp(BADGE_TEXT_PADDING * 2)` (DialogCell.java:2510, 2515, 5264).
  static double badgeWidthFor(double textWidth) =>
      math.max(badgeTextMinWidth, textWidth.ceilToDouble()) +
      2 * badgeTextPadding;
}

/// Layout slots of [DialogCell]'s [CustomMultiChildLayout].
enum DialogCellSlot {
  /// The 52/56dp avatar frame.
  avatar,

  /// The name line.
  name,

  /// The message line(s).
  message,

  /// The right-aligned time.
  time,

  /// The unread-count badge.
  badge,

  /// The pin icon (count row, shown when no badge).
  pin,

  /// The verified glyph after the name.
  verified,

  /// The mute glyph after the name.
  mute,
}

/// The measurement/placement pass of `DialogCell.buildLayout` +
/// `dispatchDraw`, reduced to the ported slots. All x positions are computed
/// in LTR terms and mirrored for RTL.
class DialogCellLayoutDelegate extends MultiChildLayoutDelegate {
  /// Creates the delegate.
  DialogCellLayoutDelegate({
    required this.threeLines,
    required this.textDirection,
  });

  /// `useForceThreeLines || SharedConfig.useThreeLinesLayout`.
  final bool threeLines;

  /// Mirrors every x for [TextDirection.rtl].
  final TextDirection textDirection;

  void _place(DialogCellSlot slot, double x, double y, Size child, Size size) {
    final double dx = textDirection == TextDirection.rtl
        ? size.width - x - child.width
        : x;
    positionChild(slot, Offset(dx, y));
  }

  @override
  void performLayout(Size size) {
    final double textStart = DialogCellMetrics.textStart(
      threeLines: threeLines,
    );

    // Time first: the name field width depends on the ceiled time width
    // (`timeWidth = (int) Math.ceil(measureText)`, DialogCell.java:2264,
    // consumed at L2290).
    double timeWidth = 0.0;
    if (hasChild(DialogCellSlot.time)) {
      final Size time = layoutChild(
        DialogCellSlot.time,
        BoxConstraints.loose(size),
      );
      timeWidth = time.width.ceilToDouble();
      _place(
        DialogCellSlot.time,
        size.width - DialogCellMetrics.timeRightMargin - time.width,
        DialogCellMetrics.timeTop(threeLines: threeLines),
        time,
        size,
      );
    }

    // Badge next: the message field shrinks by `countWidth + BADGE_GAP`
    // (DialogCell.java:2512-2513).
    double messageBadgeInset = 0.0;
    if (hasChild(DialogCellSlot.badge)) {
      final Size badge = layoutChild(
        DialogCellSlot.badge,
        BoxConstraints.loose(size),
      );
      // countLeft = w - BADGE_MARGIN - (countWidth + BADGE_TEXT_PADDING * 2)
      // (DialogCell.java:2515).
      _place(
        DialogCellSlot.badge,
        size.width - DialogCellMetrics.badgeMargin - badge.width,
        DialogCellMetrics.countTop(threeLines: threeLines),
        badge,
        size,
      );
      final double countWidth =
          badge.width - 2 * DialogCellMetrics.badgeTextPadding;
      messageBadgeInset = countWidth + DialogCellMetrics.badgeGap;
    }
    if (hasChild(DialogCellSlot.pin)) {
      // pinLeft = w - intrinsicWidth - dp(14) (DialogCell.java:2491), pinTop
      // 39/43 (L2456, L2433).
      final Size pin = layoutChild(
        DialogCellSlot.pin,
        BoxConstraints.loose(size),
      );
      _place(
        DialogCellSlot.pin,
        size.width - pin.width - DialogCellMetrics.pinRightMargin,
        DialogCellMetrics.pinTop(threeLines: threeLines),
        pin,
        size,
      );
    }

    if (hasChild(DialogCellSlot.avatar)) {
      final double side = DialogCellMetrics.avatarSize(threeLines: threeLines);
      final Size avatar = layoutChild(
        DialogCellSlot.avatar,
        BoxConstraints.tight(Size.square(side)),
      );
      _place(
        DialogCellSlot.avatar,
        DialogCellMetrics.avatarStart,
        DialogCellMetrics.avatarTop(threeLines: threeLines),
        avatar,
        size,
      );
    }

    // Name: field width w - nameLeft - dp(14 + 8) - timeWidth
    // (DialogCell.java:2290).
    Size name = Size.zero;
    if (hasChild(DialogCellSlot.name)) {
      final double nameMaxWidth = math.max(
        0.0,
        size.width - textStart - DialogCellMetrics.nameTrailingGap - timeWidth,
      );
      name = layoutChild(
        DialogCellSlot.name,
        BoxConstraints(maxWidth: nameMaxWidth),
      );
      _place(
        DialogCellSlot.name,
        textStart,
        DialogCellMetrics.nameTop(threeLines: threeLines),
        name,
        size,
      );
    }

    // Glyph anchor 6dp after the painted name width (`nameMuteLeft =
    // nameLeft + left + dp(6)`, DialogCell.java:2891).
    double glyphAnchor = textStart + name.width + DialogCellMetrics.glyphGap;
    if (hasChild(DialogCellSlot.verified)) {
      final Size verified = layoutChild(
        DialogCellSlot.verified,
        BoxConstraints.loose(size),
      );
      final double x = glyphAnchor + DialogCellMetrics.verifiedGlyphDx;
      _place(
        DialogCellSlot.verified,
        x,
        DialogCellMetrics.verifiedGlyphTop(threeLines: threeLines),
        verified,
        size,
      );
      // Port simplification: a mute glyph provided alongside verified stacks
      // after it (upstream resolves a single nameMuteLeft anchor,
      // DialogCell.java:2790-2806).
      glyphAnchor = x + verified.width + DialogCellMetrics.glyphGap;
    }
    if (hasChild(DialogCellSlot.mute)) {
      final Size mute = layoutChild(
        DialogCellSlot.mute,
        BoxConstraints.loose(size),
      );
      _place(
        DialogCellSlot.mute,
        glyphAnchor + DialogCellMetrics.muteGlyphDx(threeLines: threeLines),
        DialogCellMetrics.muteGlyphTop(threeLines: threeLines),
        mute,
        size,
      );
    }

    if (hasChild(DialogCellSlot.message)) {
      // messageWidth = w - inset (DialogCell.java:2436/2459), shrunk by an
      // active badge (L2512-2513), floored at dp(12) (L2652).
      final double messageMaxWidth = math.max(
        DialogCellMetrics.messageMinWidth,
        size.width -
            DialogCellMetrics.messageWidthInset(threeLines: threeLines) -
            messageBadgeInset,
      );
      final Size message = layoutChild(
        DialogCellSlot.message,
        BoxConstraints(maxWidth: messageMaxWidth),
      );
      _place(
        DialogCellSlot.message,
        textStart,
        DialogCellMetrics.messageTop(threeLines: threeLines),
        message,
        size,
      );
    }
  }

  @override
  bool shouldRelayout(DialogCellLayoutDelegate oldDelegate) =>
      threeLines != oldDelegate.threeLines ||
      textDirection != oldDelegate.textDirection;
}

/// The 1px bottom separator of DialogCell.java:4774-4791: a `dividerPaint`
/// line at `y = measuredHeight - 1`, left-inset [inset] (LTR; the inset
/// mirrors to the right edge in RTL, L4788-4791).
class DialogCellSeparatorPainter extends CustomPainter {
  /// Creates the painter.
  const DialogCellSeparatorPainter({
    required this.color,
    required this.inset,
    this.textDirection = TextDirection.ltr,
    this.thickness = DialogCellMetrics.separatorHeight,
  });

  /// Resolved `divider` key (`Theme.dividerPaint`).
  final Color color;

  /// Left inset — `messagePaddingStart` (72) or 0 for a full separator
  /// (DialogCell.java:4775-4780).
  final double inset;

  /// Mirrors the inset for RTL (DialogCell.java:4788-4791).
  final TextDirection textDirection;

  /// Painted thickness (1 logical px; Android draws 1 physical px).
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect line = textDirection == TextDirection.rtl
        ? Rect.fromLTWH(0, size.height - thickness, size.width - inset,
            thickness)
        : Rect.fromLTWH(inset, size.height - thickness, size.width - inset,
            thickness);
    canvas.drawRect(line, Paint()..color = color);
  }

  @override
  bool shouldRepaint(DialogCellSeparatorPainter oldDelegate) =>
      color != oldDelegate.color ||
      inset != oldDelegate.inset ||
      textDirection != oldDelegate.textDirection ||
      thickness != oldDelegate.thickness;
}

/// The unread-count badge of DialogCell.java:2508-2523 / 5254-5301,
/// standalone and self-sizing:
///
/// - width `max(dp(8), ceil(textWidth)) + dp(2 * 6.333)` — at the 8dp text
///   floor this is exactly [DialogCellMetrics.badgeHeight] (a circle), the
///   upstream `BADGE_SIZE` derivation (DialogCell.java:1224-1227);
/// - height [DialogCellMetrics.badgeHeight] (20.666);
/// - fill: 11.5dp-radius round rect (L5291), key `chats_unreadCounter`, or
///   `chats_unreadCounterMuted` when [muted]
///   (`dialogs_countGrayPaint` selection at L5255, Theme.java:8508-8509);
/// - text: 13dp Roboto Medium (`dialogs_countTextPaint2`), key
///   `chats_unreadCounterText` (Theme.java:8505), centered in the text field
///   and top-offset 3 (`translate(countLeft + dp(6.333), countTop +
///   dpf2(3))` over an ALIGN_CENTER layout, L2511, L5298).
class DialogCellUnreadBadge extends StatelessWidget {
  /// Creates the badge.
  const DialogCellUnreadBadge({
    super.key,
    required this.text,
    this.muted = false,
    this.resources,
  });

  /// The count string (already formatted — upstream hands the paint a
  /// preformatted `countString`, DialogCell.java:2510).
  final String text;

  /// Muted fill: `dialogs_countGrayPaint` = `chats_unreadCounterMuted`
  /// (DialogCell.java:5255, Theme.java:8509).
  final bool muted;

  /// Per-surface color override — the `Theme.ResourcesProvider` convention.
  final TelegramResources? resources;

  /// The counter text style: 13dp `AndroidUtilities.bold()` (Roboto Medium,
  /// bundled as the w500 family `RobotoMedium`) — `dialogs_countTextPaint2`
  /// (Theme.java:8365-8372).
  static TextStyle textStyle(Color color) => TextStyle(
        fontSize: DialogCellMetrics.countFontSize,
        color: color,
        fontFamily: 'RobotoMedium',
        package: 'telegram_ui',
        fontWeight: FontWeight.w500,
      );

  @override
  Widget build(BuildContext context) {
    return _RawUnreadBadge(
      text: text,
      fillColor: _resolve(
        context,
        resources,
        muted
            ? TelegramColorKey.chats_unreadCounterMuted
            : TelegramColorKey.chats_unreadCounter,
      ),
      textColor: _resolve(
        context,
        resources,
        TelegramColorKey.chats_unreadCounterText,
      ),
      textDirection: Directionality.of(context),
    );
  }
}

class _RawUnreadBadge extends LeafRenderObjectWidget {
  const _RawUnreadBadge({
    required this.text,
    required this.fillColor,
    required this.textColor,
    required this.textDirection,
  });

  final String text;
  final Color fillColor;
  final Color textColor;
  final TextDirection textDirection;

  @override
  RenderDialogCellUnreadBadge createRenderObject(BuildContext context) =>
      RenderDialogCellUnreadBadge(
        text: text,
        fillColor: fillColor,
        textColor: textColor,
        textDirection: textDirection,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderDialogCellUnreadBadge renderObject,
  ) {
    renderObject
      ..text = text
      ..fillColor = fillColor
      ..textColor = textColor
      ..textDirection = textDirection;
  }
}

/// Render box of [DialogCellUnreadBadge]: measures the count with a
/// [TextPainter] (the `dialogs_countTextPaint2.measureText` analog,
/// DialogCell.java:2510) and sizes/paints per the badge constants.
class RenderDialogCellUnreadBadge extends RenderBox {
  /// Creates the render box.
  RenderDialogCellUnreadBadge({
    required this._text,
    required this._fillColor,
    required this._textColor,
    required this._textDirection,
  });

  final TextPainter _textPainter = TextPainter();
  bool _painterDirty = true;

  /// The count string.
  String get text => _text;
  String _text;
  set text(String value) {
    if (value == _text) {
      return;
    }
    _text = value;
    _painterDirty = true;
    markNeedsLayout();
  }

  /// Resolved fill color (`chats_unreadCounter` / `chats_unreadCounterMuted`).
  Color get fillColor => _fillColor;
  Color _fillColor;
  set fillColor(Color value) {
    if (value == _fillColor) {
      return;
    }
    _fillColor = value;
    markNeedsPaint();
  }

  /// Resolved text color (`chats_unreadCounterText`).
  Color get textColor => _textColor;
  Color _textColor;
  set textColor(Color value) {
    if (value == _textColor) {
      return;
    }
    _textColor = value;
    _painterDirty = true;
    markNeedsLayout();
  }

  /// Ambient direction for the text layout.
  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    _painterDirty = true;
    markNeedsLayout();
  }

  TextPainter _layoutText() {
    if (_painterDirty) {
      _textPainter
        ..text = TextSpan(
          text: _text,
          style: DialogCellUnreadBadge.textStyle(_textColor),
        )
        ..textDirection = _textDirection
        ..textHeightBehavior = _kTextHeightBehavior;
      _painterDirty = false;
    }
    _textPainter.layout();
    return _textPainter;
  }

  Size _badgeSize(BoxConstraints constraints) {
    final TextPainter painter = _layoutText();
    return constraints.constrain(
      Size(
        DialogCellMetrics.badgeWidthFor(painter.width),
        DialogCellMetrics.badgeHeight,
      ),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _badgeSize(constraints);

  @override
  void performLayout() {
    size = _badgeSize(constraints);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect rect = offset & size;
    // rect.set(x, countTop, x + countWidth + dp(6.333 * 2), countTop +
    // dp(20.666)); drawRoundRect(rect, dp(11.5), dp(11.5), paint)
    // (DialogCell.java:5264, 5291).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        const Radius.circular(DialogCellMetrics.badgeRadius),
      ),
      Paint()..color = _fillColor,
    );
    // translate(countLeft + dp(6.333), countTop + dpf2(3)) over an
    // ALIGN_CENTER layout of width countWidth (DialogCell.java:2511, 5298).
    final TextPainter painter = _layoutText();
    final double fieldWidth = size.width - 2 * DialogCellMetrics.badgeTextPadding;
    painter.paint(
      canvas,
      offset +
          Offset(
            DialogCellMetrics.badgeTextPadding +
                (fieldWidth - painter.width) / 2,
            DialogCellMetrics.badgeTextTop,
          ),
    );
  }

  @override
  void dispose() {
    _textPainter.dispose();
    super.dispose();
  }
}

/// The chat-list row — the simplified-but-faithful port of
/// `ui/Cells/DialogCell.java` (see the library header for the full metric
/// citations and the list of deliberate departures).
///
/// A fixed-height row (70dp + 1px separator; 76dp + 1px in the [threeLines]
/// variant) laying out:
///
/// - an [avatar] widget slot in the 52x52 (56x56) frame at (11, 9) /
///   (11, 11) — the image pipeline stays out of this package;
/// - [name] at 16dp Roboto Medium, `chats_name`, top 14 (10), left 76 (78);
/// - [message] at 15dp, `chats_message` (`chats_message_threeLines` when
///   [threeLines]; upstream's forced `paintIndex = 1` actually uses the
///   threeLines key everywhere, DialogCell.java:1246-1258 — the port keeps
///   the per-variant keys of the section-6 spec row), top 39 (32), one line
///   (two lines when [threeLines]);
/// - [time] at 12dp `chats_date`, top 16 (13), right-aligned at 15
///   (DialogCell.java:2268);
/// - the unread badge ([unreadCount] / [countText], [countMuted]) at the
///   count row, right margin 15.666;
/// - a [pinnedIcon] slot at the count row (suppressed while a badge shows,
///   like the upstream draw chain);
/// - [verifiedGlyph] / [muteGlyph] slots 6dp after the painted name.
///
/// Like every component in this package, an optional [resources] override
/// wins over the ambient theme (the Java `resourcesProvider` convention);
/// otherwise colors resolve through [TelegramTheme.colorOf] for per-key
/// rebuild granularity.
class DialogCell extends StatelessWidget {
  /// Creates the cell.
  const DialogCell({
    super.key,
    required this.name,
    this.avatar,
    this.message,
    this.time,
    this.unreadCount = 0,
    this.countText,
    this.countMuted = false,
    this.pinned = false,
    this.pinnedIcon,
    this.verifiedGlyph,
    this.muteGlyph,
    this.threeLines = false,
    this.drawSeparator = true,
    this.fullSeparator = false,
    this.resources,
  }) : assert(unreadCount >= 0);

  /// The dialog name (16dp Roboto Medium, `chats_name`).
  final String name;

  /// Avatar slot, laid out tight at 52x52 (56x56 when [threeLines]) at
  /// (11, 9) / (11, 11). The cell imposes the frame; avatar content (image,
  /// initials, story ring) is the caller's.
  final Widget? avatar;

  /// The message preview (15dp, one line; two lines when [threeLines]).
  final String? message;

  /// The preformatted time string (12dp `chats_date`, right-aligned).
  final String? time;

  /// Unread count; > 0 shows the badge (suppressing [pinnedIcon]).
  final int unreadCount;

  /// Overrides the badge label (e.g. a capped "999+") while [unreadCount]
  /// still gates visibility when this is null. A non-null non-empty value
  /// shows the badge regardless of [unreadCount] — the upstream
  /// `countString != null` gate (DialogCell.java:2508-2509).
  final String? countText;

  /// Muted badge fill (`chats_unreadCounterMuted`, DialogCell.java:5255).
  final bool countMuted;

  /// Whether the dialog is pinned. The [pinnedIcon] slot only renders when
  /// pinned and no badge shows (DialogCell.java:4517-4523).
  final bool pinned;

  /// Pin glyph slot at (width - childWidth - 14, pinTop)
  /// (DialogCell.java:2491, 2456/2433). No default asset — the icon
  /// pipeline stays out of this package.
  final Widget? pinnedIcon;

  /// Verified glyph slot, 6dp after the painted name (top 16.5 / 13.5,
  /// DialogCell.java:4467-4471).
  final Widget? verifiedGlyph;

  /// Mute glyph slot, 6dp after the painted name (top 17.5 / 13.5,
  /// DialogCell.java:4427-4428); stacks after [verifiedGlyph] when both are
  /// set.
  final Widget? muteGlyph;

  /// The three-line variant (`useForceThreeLines ||
  /// SharedConfig.useThreeLinesLayout`): 76dp tall, 56x56 avatar at
  /// (11, 11), text left 78, up to two message lines.
  final bool threeLines;

  /// Whether the separator line paints. The 1px row it occupies is *always*
  /// reserved (`useSeparator || true`, DialogCell.java:1021), so toggling
  /// this never changes the height.
  final bool drawSeparator;

  /// Full-width separator instead of the 72dp-inset one
  /// (DialogCell.java:4775-4780).
  final bool fullSeparator;

  /// Per-surface color override — the `Theme.ResourcesProvider` convention.
  final TelegramResources? resources;

  /// The name text style: 16dp `AndroidUtilities.bold()` (Roboto Medium,
  /// bundled as the w500 family `RobotoMedium`) —
  /// `dialogs_namePaint[1]` (DialogCell.java:1252, Theme.java:8353-8356).
  static TextStyle nameStyle(Color color) => TextStyle(
        fontSize: DialogCellMetrics.nameFontSize,
        color: color,
        fontFamily: 'RobotoMedium',
        package: 'telegram_ui',
        fontWeight: FontWeight.w500,
      );

  /// The message text style: 15dp regular (`dialogs_messagePaint[1]`,
  /// DialogCell.java:1254).
  static TextStyle messageStyle(Color color) => TextStyle(
        fontSize: DialogCellMetrics.messageFontSize,
        color: color,
      );

  /// The time text style: 12dp regular (`dialogs_timePaint`,
  /// Theme.java:8472).
  static TextStyle timeStyle(Color color) => TextStyle(
        fontSize: DialogCellMetrics.timeFontSize,
        color: color,
      );

  @override
  Widget build(BuildContext context) {
    final TextDirection direction = Directionality.of(context);
    final String badgeLabel = countText ?? '$unreadCount';
    final bool hasBadge =
        (countText != null && countText!.isNotEmpty) || unreadCount > 0;
    final bool showPin = pinned && !hasBadge && pinnedIcon != null;

    return SizedBox(
      height: DialogCellMetrics.height(threeLines: threeLines),
      child: CustomPaint(
        foregroundPainter: drawSeparator
            ? DialogCellSeparatorPainter(
                color: _resolve(context, resources, TelegramColorKey.divider),
                inset: fullSeparator
                    ? 0.0
                    : DialogCellMetrics.messagePaddingStart,
                textDirection: direction,
              )
            : null,
        child: CustomMultiChildLayout(
          delegate: DialogCellLayoutDelegate(
            threeLines: threeLines,
            textDirection: direction,
          ),
          children: <Widget>[
            if (avatar != null)
              LayoutId(id: DialogCellSlot.avatar, child: avatar!),
            LayoutId(
              id: DialogCellSlot.name,
              child: Text(
                name,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textHeightBehavior: _kTextHeightBehavior,
                style: nameStyle(
                  _resolve(context, resources, TelegramColorKey.chats_name),
                ),
              ),
            ),
            if (message != null)
              LayoutId(
                id: DialogCellSlot.message,
                child: Text(
                  message!,
                  maxLines: threeLines ? 2 : 1,
                  softWrap: threeLines,
                  overflow: TextOverflow.ellipsis,
                  textHeightBehavior: _kTextHeightBehavior,
                  style: messageStyle(
                    _resolve(
                      context,
                      resources,
                      threeLines
                          ? TelegramColorKey.chats_message_threeLines
                          : TelegramColorKey.chats_message,
                    ),
                  ),
                ),
              ),
            if (time != null)
              LayoutId(
                id: DialogCellSlot.time,
                child: Text(
                  time!,
                  maxLines: 1,
                  softWrap: false,
                  textHeightBehavior: _kTextHeightBehavior,
                  style: timeStyle(
                    _resolve(context, resources, TelegramColorKey.chats_date),
                  ),
                ),
              ),
            if (hasBadge)
              LayoutId(
                id: DialogCellSlot.badge,
                child: DialogCellUnreadBadge(
                  text: badgeLabel,
                  muted: countMuted,
                  resources: resources,
                ),
              ),
            if (showPin)
              LayoutId(id: DialogCellSlot.pin, child: pinnedIcon!),
            if (verifiedGlyph != null)
              LayoutId(id: DialogCellSlot.verified, child: verifiedGlyph!),
            if (muteGlyph != null)
              LayoutId(id: DialogCellSlot.mute, child: muteGlyph!),
          ],
        ),
      ),
    );
  }
}
