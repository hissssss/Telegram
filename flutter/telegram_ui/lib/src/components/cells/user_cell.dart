// The contact/member list row (ARCHITECTURE.md section 6, row "UserCell").
//
// Port of `ui/Cells/UserCell.java`, with every constant cited:
//
// - row height 58dp + 1 *physical* px when the divider is on
//   (`dp(callCellStyle ? 56 : 58) + (needDivider ? 1 : 0)`, EXACTLY,
//   UserCell.java:493-498);
// - avatar slot 46x46dp at (7 + padding, 6), round radius 24dp
//   (UserCell.java:182-183);
// - name 16dp `AndroidUtilities.bold()` — `fonts/rmedium.ttf`, bundled by
//   this package as the w500 family `RobotoMedium`
//   (AndroidUtilities.java:260-269) — key `windowBackgroundWhiteBlackText`,
//   in a 20dp-tall box at (64 + padding, 10), trailing margin 28dp plus the
//   add-button reserve (UserCell.java:186-191);
// - status 15dp in a 20dp-tall box at (64 + padding, 32)
//   (UserCell.java:196-199); offline color `windowBackgroundWhiteGrayText`
//   (UserCell.java:158, applied at 701/709/720), online color
//   `telegram_color_text` (UserCell.java:159, applied at 716-718; the key
//   falls back to `windowBackgroundWhiteBlueText4`, Theme.java:4208, 4493);
// - add button: wrap-content x 28dp at top 15 / trailing 14, radius-14dp
//   filled round rect `featuredStickers_addButton`
//   (`Theme.AdaptiveRipple.filledRectByKey(key, 14)`, UserCell.java:147;
//   `filledRect` radii are dp, Theme.java:5844-5872), text 14dp bold
//   `featuredStickers_buttonText`, horizontal padding 17dp
//   (UserCell.java:142-150); the name/status trailing reserve is
//   `ceil(measureText(text) + dp(34 + 14))` (UserCell.java:151);
// - checkbox slot: the multi-select `CheckBox2` frame, 24x24dp at
//   (24 + padding, 36) (UserCell.java:210-215) — a widget slot only; the
//   checkbox itself is not this cell's logic;
// - divider: 1px `Theme.dividerPaint` line at the bottom, leading inset 68dp
//   (UserCell.java:771-774; stroke width 1px, Theme.java:8214, colored
//   `key_divider`, Theme.java:8305).
//
// Deliberately NOT ported (kept as doc pointers): the call-cell style (56dp
// row, 15/13dp text, 44dp avatar, UserCell.java:477-490, 497), the
// story-ring avatar machinery (UserCell.java:104-117, 163-181), emoji
// status / bot-verification drawables (20dp, UserCell.java:193-194), the
// leading icon variant (UserCell.java:201-205), the `CheckBoxSquare`
// (18x18 trailing 19, UserCell.java:207-209) and `account_check`
// (UserCell.java:216-222) checkbox variants, the admin/role labels
// (UserCell.java:225-232, 288-296), and the MessagesController-driven
// online determination (UserCell.java:716 — the port takes a plain
// [UserCell.online] flag).
library;

import 'package:flutter/widgets.dart';

import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';
import 'text_cell.dart' show TextCellDividerPainter;

/// Row height: 58dp (`dp(callCellStyle ? 56 : 58)`, UserCell.java:497).
const double kUserCellHeight = 58.0;

/// Call-cell style row height: 56dp (UserCell.java:497). The call style
/// itself (UserCell.java:479-490) is not ported; the constant is kept for
/// reference.
const double kUserCellCallHeight = 56.0;

/// Avatar slot size: 46x46dp (`createFrame(46, 46, ...)`,
/// UserCell.java:183).
const double kUserCellAvatarSize = 46.0;

/// Avatar corner radius: `setRoundRadius(dp(24))` (UserCell.java:182) — on a
/// 46dp image this clamps to a circle.
const double kUserCellAvatarRadius = 24.0;

/// Avatar leading edge before the `padding` constructor value: 7dp
/// (`7 + padding`, UserCell.java:183).
const double kUserCellAvatarLeft = 7.0;

/// Avatar top edge: 6dp (UserCell.java:183).
const double kUserCellAvatarTop = 6.0;

/// Name/status leading edge before the `padding` value: 64dp
/// (`64 + padding`, UserCell.java:191, 199).
const double kUserCellTextLeft = 64.0;

/// Name top edge: 10dp (UserCell.java:191).
const double kUserCellNameTop = 10.0;

/// Name text size: 16dp (`nameTextView.setTextSize(16)`, UserCell.java:189).
const double kUserCellNameTextSize = 16.0;

/// Name/status layout-box height: 20dp (`createFrame(MATCH_PARENT, 20,
/// ...)`, UserCell.java:191, 199).
const double kUserCellTextBoxHeight = 20.0;

/// Status top edge: 32dp (UserCell.java:199).
const double kUserCellStatusTop = 32.0;

/// Status text size: 15dp (`statusTextView.setTextSize(15)`,
/// UserCell.java:197).
const double kUserCellStatusTextSize = 15.0;

/// Name/status base trailing margin: 28dp (the LTR right margin
/// `28 + (checkbox == 2 ? 18 : 0) + additionalPadding`, UserCell.java:191,
/// 199; the checkbox==2 variant is not ported).
const double kUserCellTextEndInset = 28.0;

/// Divider leading inset: 68dp (`canvas.drawLine(... dp(68) ...)`,
/// UserCell.java:773).
const double kUserCellDividerInset = 68.0;

/// Add-button height: 28dp (`createFrame(WRAP_CONTENT, 28, ...)`,
/// UserCell.java:150).
const double kUserCellAddButtonHeight = 28.0;

/// Add-button corner radius: 14dp (`filledRectByKey(key, 14)`,
/// UserCell.java:147; radii are dp, Theme.java:5844-5872).
const double kUserCellAddButtonRadius = 14.0;

/// Add-button text size: 14dp (UserCell.java:145).
const double kUserCellAddButtonTextSize = 14.0;

/// Add-button horizontal text padding: 17dp (`setPadding(dp(17), 0, dp(17),
/// 0)`, UserCell.java:149).
const double kUserCellAddButtonHPadding = 17.0;

/// Add-button top edge: 15dp (UserCell.java:150).
const double kUserCellAddButtonTop = 15.0;

/// Add-button trailing margin: 14dp (UserCell.java:150).
const double kUserCellAddButtonEndInset = 14.0;

/// Extra dp added to the measured add-button text when reserving trailing
/// space for the name/status: `dp(34 + 14)` — twice the 17dp text padding
/// plus the 14dp trailing margin (UserCell.java:151).
const double kUserCellAddButtonReserve = 34.0 + 14.0;

/// Checkbox slot size: 24x24dp (`createFrame(24, 24, ...)`,
/// UserCell.java:215).
const double kUserCellCheckboxSize = 24.0;

/// Checkbox slot leading edge before the `padding` value: 24dp
/// (`24 + padding`, UserCell.java:215).
const double kUserCellCheckboxLeft = 24.0;

/// Checkbox slot top edge: 36dp (UserCell.java:215).
const double kUserCellCheckboxTop = 36.0;

/// A contact/member row: 46dp avatar slot, 16dp Roboto Medium name, 15dp
/// status line (gray, or the accent `telegram_color_text` when [online]),
/// optional trailing add button and multi-select checkbox slot — the
/// `ui/Cells/UserCell.java` port.
///
/// Geometry (logical px == Android dp, [padding] = the Java constructor's
/// `padding` argument, default 0):
///
/// ```text
/// |-7+pad-|avatar 46x46|   name 16dp rmedium   @ top 10      [ Add ]-14-|
/// |------64+pad--------|   status 15dp         @ top 32   (h 28, r 14)  |
/// |-24+pad-| checkbox 24x24 @ top 36                                    |
/// ```
///
/// The row is [kUserCellHeight] (58dp) tall plus one *physical* pixel when
/// [divider] is on, exactly like `dp(58) + (needDivider ? 1 : 0)`
/// (UserCell.java:497); the divider line itself draws at the bottom with a
/// 68dp leading inset (UserCell.java:773).
///
/// Like every component in this package, the cell takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise keys resolve through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class UserCell extends StatelessWidget {
  /// Creates a user row.
  const UserCell({
    super.key,
    required this.name,
    this.status,
    this.online = false,
    this.avatar,
    this.checkbox,
    this.addButtonText,
    this.onAddTap,
    this.onTap,
    this.divider = false,
    this.dividerInset = kUserCellDividerInset,
    this.padding = 0.0,
    this.nameColorKey = TelegramColorKey.windowBackgroundWhiteBlackText,
    this.statusColorKey = TelegramColorKey.windowBackgroundWhiteGrayText,
    this.statusOnlineColorKey = TelegramColorKey.telegram_color_text,
    this.addButtonColorKey = TelegramColorKey.featuredStickers_addButton,
    this.addButtonTextColorKey = TelegramColorKey.featuredStickers_buttonText,
    this.resources,
  });

  /// Display name, 16dp Roboto Medium in [nameColorKey]
  /// (UserCell.java:186-189).
  final String name;

  /// Status line, 15dp (UserCell.java:196-197). Null hides the line — the
  /// Java cell blanks the text view instead (UserCell.java:610-611).
  final String? status;

  /// Whether the status renders in [statusOnlineColorKey] instead of
  /// [statusColorKey] — the `statusTextView.setTextColor(statusOnlineColor)`
  /// arm (UserCell.java:716-718). The Java online determination
  /// (self / `status.expires` / online-privacy, UserCell.java:716) stays
  /// with the caller.
  final bool online;

  /// Avatar slot: 46x46dp at (7 + [padding], 6) (UserCell.java:183). The
  /// slot is positioned only — round the widget itself (the Java image is
  /// `setRoundRadius(dp(24))`, UserCell.java:182; see
  /// [kUserCellAvatarRadius]).
  final Widget? avatar;

  /// Multi-select checkbox slot: 24x24dp at (24 + [padding], 36) — the
  /// `CheckBox2` frame of the `checkbox == 1` variant (UserCell.java:210-215).
  /// A widget slot only: check state and toggling are the caller's logic,
  /// like the Java `setChecked` pass-through (UserCell.java:452-462).
  final Widget? checkbox;

  /// Trailing add-button label (the Java cell hardcodes
  /// `getString(R.string.Add)`, UserCell.java:148 — the port takes the
  /// localized text). Null hides the button and drops its trailing reserve
  /// (`needAddButton`, UserCell.java:141-154).
  final String? addButtonText;

  /// Add-button tap callback (the Java button gets the fragment's click
  /// listener, e.g. FilterUsersActivity/ChatUsersActivity wiring).
  final VoidCallback? onAddTap;

  /// Row tap callback (the list-item `onClick` of the Java side).
  final VoidCallback? onTap;

  /// Whether the 1-physical-px bottom divider draws (`needDivider`,
  /// UserCell.java:103, 360-361, 497, 771-774).
  final bool divider;

  /// Divider leading inset; 68dp by default (UserCell.java:773).
  final double dividerInset;

  /// The Java constructor's `padding` argument (dp): shifts the avatar
  /// (7 + padding), texts (64 + padding), and checkbox slot (24 + padding)
  /// (UserCell.java:136, 183, 191, 199, 215).
  final double padding;

  /// Name color key; `windowBackgroundWhiteBlackText` by default
  /// (UserCell.java:187).
  final int nameColorKey;

  /// Offline/neutral status color key; `windowBackgroundWhiteGrayText` by
  /// default (UserCell.java:158; overridable like `setStatusColors`,
  /// UserCell.java:500-503).
  final int statusColorKey;

  /// Online status color key; `telegram_color_text` by default
  /// (UserCell.java:159 — fallback `windowBackgroundWhiteBlueText4`,
  /// Theme.java:4493).
  final int statusOnlineColorKey;

  /// Add-button fill key; `featuredStickers_addButton` by default
  /// (UserCell.java:147).
  final int addButtonColorKey;

  /// Add-button text key; `featuredStickers_buttonText` by default
  /// (UserCell.java:144).
  final int addButtonTextColorKey;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = this.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  /// The trailing space the add button reserves next to the name/status:
  /// `ceil(measureText(text) + dp(34 + 14))` (UserCell.java:151).
  static double addButtonReservedWidth(
    String text,
    TextStyle style,
    TextScaler textScaler,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return (width + kUserCellAddButtonReserve).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    // The divider adds 1 *physical* pixel to the measured height
    // (UserCell.java:497; Theme.dividerPaint strokeWidth 1, Theme.java:8214).
    final double devicePixelRatio =
        MediaQuery.maybeDevicePixelRatioOf(context) ??
            View.of(context).devicePixelRatio;
    final double dividerThickness = divider ? 1.0 / devicePixelRatio : 0.0;

    final String? addButtonText = this.addButtonText;
    final TextScaler textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final TextStyle addButtonStyle = TextStyle(
      fontSize: kUserCellAddButtonTextSize,
      // `AndroidUtilities.bold()` = fonts/rmedium.ttf
      // (AndroidUtilities.java:260-269), bundled here as the w500 family
      // `RobotoMedium` (UserCell.java:146).
      fontFamily: 'RobotoMedium',
      package: 'telegram_ui',
      fontWeight: FontWeight.w500,
      color: _color(context, addButtonTextColorKey),
    );
    // `additionalPadding` (UserCell.java:151), part of the name/status
    // trailing margin (UserCell.java:191, 199).
    final double additionalPadding = addButtonText == null
        ? 0.0
        : addButtonReservedWidth(addButtonText, addButtonStyle, textScaler);

    final Widget cell = SizedBox(
      width: double.infinity,
      height: kUserCellHeight + dividerThickness,
      child: CustomPaint(
        foregroundPainter: divider
            ? TextCellDividerPainter(
                color: _color(context, TelegramColorKey.divider),
                inset: dividerInset,
                thickness: dividerThickness,
                textDirection: Directionality.of(context),
              )
            : null,
        child: Stack(
          children: <Widget>[
            if (avatar != null)
              // 46x46 at (7 + padding, 6) (UserCell.java:183).
              PositionedDirectional(
                start: kUserCellAvatarLeft + padding,
                top: kUserCellAvatarTop,
                width: kUserCellAvatarSize,
                height: kUserCellAvatarSize,
                child: avatar!,
              ),
            // Name: 20dp box at (64 + padding, 10), trailing margin
            // 28 + additionalPadding (UserCell.java:191).
            PositionedDirectional(
              start: kUserCellTextLeft + padding,
              end: kUserCellTextEndInset + additionalPadding,
              top: kUserCellNameTop,
              height: kUserCellTextBoxHeight,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: kUserCellNameTextSize,
                    // `AndroidUtilities.bold()` (UserCell.java:188).
                    fontFamily: 'RobotoMedium',
                    package: 'telegram_ui',
                    fontWeight: FontWeight.w500,
                    color: _color(context, nameColorKey),
                  ),
                ),
              ),
            ),
            if (status != null)
              // Status: 20dp box at (64 + padding, 32) (UserCell.java:199).
              PositionedDirectional(
                start: kUserCellTextLeft + padding,
                end: kUserCellTextEndInset + additionalPadding,
                top: kUserCellStatusTop,
                height: kUserCellTextBoxHeight,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    status!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: kUserCellStatusTextSize,
                      // Online -> statusOnlineColor (UserCell.java:716-718),
                      // otherwise statusColor (UserCell.java:701, 709, 720).
                      color: _color(
                        context,
                        online ? statusOnlineColorKey : statusColorKey,
                      ),
                    ),
                  ),
                ),
              ),
            if (addButtonText != null)
              // Wrap x 28 at top 15, trailing 14 (UserCell.java:150).
              PositionedDirectional(
                end: kUserCellAddButtonEndInset,
                top: kUserCellAddButtonTop,
                height: kUserCellAddButtonHeight,
                child: Semantics(
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onAddTap,
                    child: DecoratedBox(
                      // `filledRectByKey(key_featuredStickers_addButton,
                      // 14)` (UserCell.java:147).
                      decoration: BoxDecoration(
                        color: _color(context, addButtonColorKey),
                        borderRadius:
                            BorderRadius.circular(kUserCellAddButtonRadius),
                      ),
                      child: Padding(
                        // `setPadding(dp(17), 0, dp(17), 0)`
                        // (UserCell.java:149).
                        padding: const EdgeInsets.symmetric(
                          horizontal: kUserCellAddButtonHPadding,
                        ),
                        // `setGravity(Gravity.CENTER)` (UserCell.java:143).
                        child: Center(
                          widthFactor: 1.0,
                          child: Text(
                            addButtonText,
                            maxLines: 1,
                            style: addButtonStyle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (checkbox != null)
              // 24x24 at (24 + padding, 36) (UserCell.java:215).
              PositionedDirectional(
                start: kUserCellCheckboxLeft + padding,
                top: kUserCellCheckboxTop,
                width: kUserCellCheckboxSize,
                height: kUserCellCheckboxSize,
                child: checkbox!,
              ),
          ],
        ),
      ),
    );

    if (onTap == null) {
      return cell;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: cell,
    );
  }
}
