// The de-facto Telegram Android type scale (`spec_typography_motion.md` §1).
//
// There is no central type-scale class in the Java codebase; these are the
// recurring `(size dp, weight)` pairs swept from every ported component's
// source (DialogCell.java, TextCell.java, AlertDialog.java, ActionBar.java,
// UserCell.java, the Theme.java paints, …) — citations on each role below.
//
// Weight is strictly binary: everything the Java codebase calls "bold"
// (`AndroidUtilities.bold()`, AndroidUtilities.java:260-269) is Roboto
// Medium — `fonts/rmedium.ttf`, `Typeface.create(null, 500, false)` on the
// fallback path (line 263) — i.e. **w500, never w700**. This package bundles
// rmedium.ttf as the family `RobotoMedium`; regular text (w400) uses the
// default platform Roboto. Sizes are Android dp, mapped 1:1 to Flutter
// logical px.
//
// Styles deliberately carry NO color: color always resolves at the use site
// through theme keys (`TelegramTheme.colorOf` / `TelegramResources`).
//
// Deliberately NOT ported: the specialty typefaces — `rextrabold.ttf`
// (selected tab state only), `rmono.ttf` (code), Merriweather (Stories
// covers) — none is part of the core scale
// (spec_typography_motion.md §1.1).
library;

import 'package:flutter/widgets.dart' show FontWeight, TextHeightBehavior, TextStyle;

/// The shared text-height behavior for all Telegram text: Android `TextView`
/// does not add half-leading above the first line or below the last, while
/// Flutter's `Paragraph` does — pin
/// `applyHeightToFirstAscent/LastDescent: false` per ARCHITECTURE.md §5
/// (spec_typography_motion.md §1.2).
const TextHeightBehavior kTgTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
);

/// The 17-role Telegram type scale, sizes 10-20dp, weights strictly
/// w400/w500 (`spec_typography_motion.md` §1.2 role table).
///
/// "Medium" roles use the bundled `RobotoMedium` family (rmedium.ttf @ w500);
/// regular roles inherit the ambient (platform Roboto) family at w400.
/// Emphasis at the same size is always done with Roboto Medium, never by a
/// size bump; w700 never appears in the core UI.
abstract final class TgTextStyles {
  /// Portrait screen title / sheet large title / dialog title — 20dp medium
  /// (ActionBar.java:1431,1443 with the typeface set bold at :523;
  /// BottomSheet.java:1393-1394; AlertDialog.java:791-792).
  static const TextStyle title = TextStyle(
    debugLabel: 'TgTextStyles.title',
    fontSize: 20.0,
    fontWeight: FontWeight.w500,
    fontFamily: 'RobotoMedium',
    package: 'telegram_ui',
  );

  /// Landscape/tablet action-bar title — 18dp medium
  /// (ActionBar.java:1431,1435).
  static const TextStyle titleCondensed = TextStyle(
    debugLabel: 'TgTextStyles.titleCondensed',
    fontSize: 18.0,
    fontWeight: FontWeight.w500,
    fontFamily: 'RobotoMedium',
    package: 'telegram_ui',
  );

  /// Glass-mode app-bar title on this branch — 17dp medium
  /// (ActionBar.java:1431,1435,1443 — `glassMode ? 17 : …`).
  static const TextStyle titleGlass = TextStyle(
    debugLabel: 'TgTextStyles.titleGlass',
    fontSize: 17.0,
    fontWeight: FontWeight.w500,
    fontFamily: 'RobotoMedium',
    package: 'telegram_ui',
  );

  /// Chat composer / in-bar search field — 18dp regular
  /// (ChatActivityEnterView.java:5752; ActionBarMenuItem.java:1438,1491).
  static const TextStyle input = TextStyle(
    debugLabel: 'TgTextStyles.input',
    fontSize: 18.0,
    fontWeight: FontWeight.w400,
  );

  /// Chat-list name, 2-line layout — 17dp medium
  /// (DialogCell.java:1247-1248,1261-1262; paints made bold at
  /// Theme.java:8386-8389).
  static const TextStyle cellTitle = TextStyle(
    debugLabel: 'TgTextStyles.cellTitle',
    fontSize: 17.0,
    fontWeight: FontWeight.w500,
    fontFamily: 'RobotoMedium',
    package: 'telegram_ui',
  );

  /// Message preview / default message / TextCell label / dialog message /
  /// sheet + popup rows — 16dp regular (DialogCell.java:1249,1263;
  /// SharedConfig.java:313; TextCell.java:98,113,123; AlertDialog.java:850;
  /// BottomSheet.java:1058; ActionBarMenuSubItem.java:97).
  static const TextStyle body = TextStyle(
    debugLabel: 'TgTextStyles.body',
    fontSize: 16.0,
    fontWeight: FontWeight.w400,
  );

  /// UserCell name / dialog action buttons — 16dp medium
  /// (UserCell.java:188-189; AlertDialog.java:1076-1079 et al.;
  /// Theme.java:8393-8396,8482-8483).
  static const TextStyle bodyEmphasis = TextStyle(
    debugLabel: 'TgTextStyles.bodyEmphasis',
    fontSize: 16.0,
    fontWeight: FontWeight.w500,
    fontFamily: 'RobotoMedium',
    package: 'telegram_ui',
  );

  /// UserCell status / Bulletin single-line / 3-line chat-list message —
  /// 15dp regular (UserCell.java:197; Theme.java:8479-8480;
  /// Bulletin.java:1359-1360,1382-1383; DialogCell.java:1254-1255).
  static const TextStyle bodySecondary = TextStyle(
    debugLabel: 'TgTextStyles.bodySecondary',
    fontSize: 15.0,
    fontWeight: FontWeight.w400,
  );

  /// Text tab strip labels — 15dp medium
  /// (ScrollSlidingTextTabStrip.java:549-553).
  static const TextStyle tab = TextStyle(
    debugLabel: 'TgTextStyles.tab',
    fontSize: 15.0,
    fontWeight: FontWeight.w500,
    fontFamily: 'RobotoMedium',
    package: 'telegram_ui',
  );

  /// Section header / button label / Bulletin 2-line title — 14dp medium
  /// (HeaderCell.java:85-86,94-95; ButtonWithCounterView.java:124-126;
  /// UserCell.java:145-146; Bulletin.java:1414-1415; Theme.java:8398,8471).
  static const TextStyle label = TextStyle(
    debugLabel: 'TgTextStyles.label',
    fontSize: 14.0,
    fontWeight: FontWeight.w500,
    fontFamily: 'RobotoMedium',
    package: 'telegram_ui',
  );

  /// Action-bar subtitle (phone portrait) / dialog subtitle / compact popup
  /// row — 14dp regular (ActionBar.java:1437,1446; AlertDialog.java:810;
  /// ActionBarMenuSubItem.java:198).
  static const TextStyle subtitle = TextStyle(
    debugLabel: 'TgTextStyles.subtitle',
    fontSize: 14.0,
    fontWeight: FontWeight.w400,
  );

  /// TextCell subtitle / HeaderCell second line / Bulletin subtitle / popup
  /// subtext — 13dp regular (TextCell.java:105; HeaderCell.java:106;
  /// Bulletin.java:1423-1424; ActionBarMenuSubItem.java:365;
  /// ActionBarMenuItem.java:98).
  static const TextStyle caption = TextStyle(
    debugLabel: 'TgTextStyles.caption',
    fontSize: 13.0,
    fontWeight: FontWeight.w400,
  );

  /// Standalone counter badge / large unread badge / archive label — 13dp
  /// medium (CounterView.java:134-135; Theme.java:8364-8365,8372,8403,8477).
  static const TextStyle captionEmphasis = TextStyle(
    debugLabel: 'TgTextStyles.captionEmphasis',
    fontSize: 13.0,
    fontWeight: FontWeight.w500,
    fontFamily: 'RobotoMedium',
    package: 'telegram_ui',
  );

  /// Chat-list timestamp / button sub-text — 12dp regular
  /// (Theme.java:8472; ButtonWithCounterView.java:133).
  static const TextStyle micro = TextStyle(
    debugLabel: 'TgTextStyles.micro',
    fontSize: 12.0,
    fontWeight: FontWeight.w400,
  );

  /// Small unread badge / filled-button counter — 12dp medium
  /// (Theme.java:8363,8371; ButtonWithCounterView.java:139-140).
  static const TextStyle microEmphasis = TextStyle(
    debugLabel: 'TgTextStyles.microEmphasis',
    fontSize: 12.0,
    fontWeight: FontWeight.w500,
    fontFamily: 'RobotoMedium',
    package: 'telegram_ui',
  );

  /// Small archive label — 11dp medium (Theme.java:8405,8478).
  static const TextStyle tagSmall = TextStyle(
    debugLabel: 'TgTextStyles.tagSmall',
    fontSize: 11.0,
    fontWeight: FontWeight.w500,
    fontFamily: 'RobotoMedium',
    package: 'telegram_ui',
  );

  /// Chat-folder tag chips — 10dp medium (Theme.java:8409,8481).
  static const TextStyle tag = TextStyle(
    debugLabel: 'TgTextStyles.tag',
    fontSize: 10.0,
    fontWeight: FontWeight.w500,
    fontFamily: 'RobotoMedium',
    package: 'telegram_ui',
  );

  /// Every role of the scale by name — for tooling and tests (asserting
  /// scale-wide invariants: only w400/w500, no color, no stray sizes).
  static const Map<String, TextStyle> roles = <String, TextStyle>{
    'title': title,
    'titleCondensed': titleCondensed,
    'titleGlass': titleGlass,
    'input': input,
    'cellTitle': cellTitle,
    'body': body,
    'bodyEmphasis': bodyEmphasis,
    'bodySecondary': bodySecondary,
    'tab': tab,
    'label': label,
    'subtitle': subtitle,
    'caption': caption,
    'captionEmphasis': captionEmphasis,
    'micro': micro,
    'microEmphasis': microEmphasis,
    'tagSmall': tagSmall,
    'tag': tag,
  };
}
