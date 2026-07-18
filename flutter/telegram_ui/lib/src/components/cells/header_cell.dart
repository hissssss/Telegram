// The settings-section header row (ARCHITECTURE.md section 6, row
// "HeaderCell").
//
// Port of `ui/Cells/HeaderCell.java`, with every constant cited:
//
// - nominal height 40dp (`height = 40`, HeaderCell.java:44) realized as
//   `topMargin + minHeight(height - topMargin)`: the text view's min height
//   is `dp(height - topMargin)` (HeaderCell.java:98) under a `topMargin`
//   (default 7dp, HeaderCell.java:49-61) and the cell measures UNSPECIFIED,
//   wrapping its content (HeaderCell.java:160-162);
// - text 14dp `AndroidUtilities.bold()` — `fonts/rmedium.ttf`, bundled by
//   this package as family `RobotoMedium` at w500 — color key
//   `windowBackgroundWhiteBlueHeader` (HeaderCell.java:49, 94-99);
// - horizontal padding: the Java constructor default is 18dp
//   (HeaderCell.java:49), but the catalog pins 21dp — the value production
//   list screens pass (e.g. Stars/StarsIntroActivity.java:682,
//   PrivacyUsersActivity.java:432, Adapters/ContactsAdapter.java:431);
// - disabled state: 0.5 alpha on the text (HeaderCell.java:142-149).
//
// Deliberately NOT ported: the animated-text variant (HeaderCell.java:83-91)
// and the trailing 13dp `text2` view (HeaderCell.java:104-109).
library;

import 'package:flutter/widgets.dart';

import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';

/// Nominal cell height: 40dp (`height = 40`, HeaderCell.java:44).
const double kHeaderCellHeight = 40.0;

/// Text size: 14dp (HeaderCell.java:85, 94).
const double kHeaderCellTextSize = 14.0;

/// Horizontal padding: 21dp — the production call-site value
/// (Stars/StarsIntroActivity.java:682 et al.; the bare constructor default
/// is 18dp, HeaderCell.java:49).
const double kHeaderCellPadding = 21.0;

/// Top margin above the text block: 7dp (constructor default,
/// HeaderCell.java:49-61).
const double kHeaderCellTopMargin = 7.0;

/// Disabled text alpha: 0.5 (HeaderCell.java:142-149).
const double kHeaderCellDisabledAlpha = 0.5;

/// A section header row: 14dp Roboto Medium text in
/// `windowBackgroundWhiteBlueHeader`, 21dp horizontal padding, 7dp top
/// margin — nominally 40dp tall — the `ui/Cells/HeaderCell.java` port.
///
/// The height is not fixed: like the Java cell (UNSPECIFIED measure,
/// HeaderCell.java:160-162) the row is `topMargin + max(height - topMargin,
/// text height) + bottomMargin` tall, i.e. exactly [kHeaderCellHeight] for a
/// single line at default metrics.
///
/// Like every component in this package, the cell takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise the key resolves through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class HeaderCell extends StatelessWidget {
  /// Creates a header row.
  const HeaderCell({
    super.key,
    required this.text,
    this.padding = kHeaderCellPadding,
    this.topMargin = kHeaderCellTopMargin,
    this.bottomMargin = 0.0,
    this.height = kHeaderCellHeight,
    this.textColorKey = TelegramColorKey.windowBackgroundWhiteBlueHeader,
    this.enabled = true,
    this.resources,
  });

  /// Header text, 14dp Roboto Medium (HeaderCell.java:94-95).
  final String text;

  /// Horizontal padding (HeaderCell.java:101); defaults to the production
  /// 21dp.
  final double padding;

  /// Top margin (HeaderCell.java:49-61, 101).
  final double topMargin;

  /// Bottom margin, default 0 (`bottomMargin`, HeaderCell.java:72, 101).
  final double bottomMargin;

  /// Nominal height driving the text's min height
  /// (`setMinHeight(dp(height - topMargin))`, HeaderCell.java:98, 122-128).
  final double height;

  /// Text color key, `windowBackgroundWhiteBlueHeader` by default
  /// (HeaderCell.java:49).
  final int textColorKey;

  /// Disabled headers draw their text at [kHeaderCellDisabledAlpha]
  /// (HeaderCell.java:142-149 — Java animates the alpha; the port applies it
  /// directly).
  final bool enabled;

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

  @override
  Widget build(BuildContext context) {
    // `ViewCompat.setAccessibilityHeading(this, true)` (HeaderCell.java:111,
    // 210-222).
    return Semantics(
      header: true,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: padding,
            end: padding,
            top: topMargin,
            bottom: bottomMargin,
          ),
          child: ConstrainedBox(
            // `textView.setMinHeight(dp(height - topMargin))`
            // (HeaderCell.java:98) with CENTER_VERTICAL gravity
            // (HeaderCell.java:97).
            constraints: BoxConstraints(minHeight: height - topMargin),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              // Wrap the text height (the Java cell measures UNSPECIFIED and
              // wraps, HeaderCell.java:160-162) instead of filling a bounded
              // parent; the ConstrainedBox above keeps the min height.
              heightFactor: 1.0,
              child: Opacity(
                opacity: enabled ? 1.0 : kHeaderCellDisabledAlpha,
                child: Text(
                  text,
                  maxLines: 1,
                  // `setEllipsize(TextUtils.TruncateAt.END)`
                  // (HeaderCell.java:96).
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: kHeaderCellTextSize,
                    // `AndroidUtilities.bold()` = fonts/rmedium.ttf
                    // (AndroidUtilities.java:260-269), bundled here as the
                    // w500 family `RobotoMedium`.
                    fontFamily: 'RobotoMedium',
                    package: 'telegram_ui',
                    fontWeight: FontWeight.w500,
                    color: _color(context, textColorKey),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
