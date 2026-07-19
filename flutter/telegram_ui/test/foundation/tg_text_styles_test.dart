// Ring-1 tests for lib/src/foundation/tg_text_styles.dart.
//
// Every role's (size, weight, family) is asserted against the table in
// spec_typography_motion.md §1.2; weight is strictly binary (w400/w500) —
// w700 never appears in the core Telegram UI.

import 'package:flutter/widgets.dart' show FontWeight, TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/tg_text_styles.dart';

/// What `TextStyle(fontFamily: 'RobotoMedium', package: 'telegram_ui')`
/// resolves to.
const String kMediumFamily = 'packages/telegram_ui/RobotoMedium';

void main() {
  group('role table (spec_typography_motion.md §1.2)', () {
    void expectRole(
      TextStyle style,
      double size,
      FontWeight weight, {
      String reason = '',
    }) {
      expect(style.fontSize, size, reason: reason);
      expect(style.fontWeight, weight, reason: reason);
      if (weight == FontWeight.w500) {
        // "bold" = bundled Roboto Medium (AndroidUtilities.java:260-269).
        expect(style.fontFamily, kMediumFamily, reason: reason);
      } else {
        // Regular text inherits the ambient (platform Roboto) family.
        expect(style.fontFamily, isNull, reason: reason);
      }
    }

    test('title 20/500 (ActionBar.java:1431,1443; AlertDialog.java:791-792)',
        () => expectRole(TgTextStyles.title, 20.0, FontWeight.w500));

    test('titleCondensed 18/500 (ActionBar.java:1431,1435)',
        () => expectRole(TgTextStyles.titleCondensed, 18.0, FontWeight.w500));

    test('titleGlass 17/500 (ActionBar.java:1431,1435,1443)',
        () => expectRole(TgTextStyles.titleGlass, 17.0, FontWeight.w500));

    test('input 18/400 (ChatActivityEnterView.java:5752)',
        () => expectRole(TgTextStyles.input, 18.0, FontWeight.w400));

    test('cellTitle 17/500 (DialogCell.java:1247-1248)',
        () => expectRole(TgTextStyles.cellTitle, 17.0, FontWeight.w500));

    test('body 16/400 (DialogCell.java:1249; TextCell.java:98)',
        () => expectRole(TgTextStyles.body, 16.0, FontWeight.w400));

    test('bodyEmphasis 16/500 (UserCell.java:188-189)',
        () => expectRole(TgTextStyles.bodyEmphasis, 16.0, FontWeight.w500));

    test('bodySecondary 15/400 (UserCell.java:197)',
        () => expectRole(TgTextStyles.bodySecondary, 15.0, FontWeight.w400));

    test('tab 15/500 (ScrollSlidingTextTabStrip.java:549-553)',
        () => expectRole(TgTextStyles.tab, 15.0, FontWeight.w500));

    test('label 14/500 (HeaderCell.java:85-86; ButtonWithCounterView.java:124-126)',
        () => expectRole(TgTextStyles.label, 14.0, FontWeight.w500));

    test('subtitle 14/400 (ActionBar.java:1437,1446)',
        () => expectRole(TgTextStyles.subtitle, 14.0, FontWeight.w400));

    test('caption 13/400 (TextCell.java:105; HeaderCell.java:106)',
        () => expectRole(TgTextStyles.caption, 13.0, FontWeight.w400));

    test('captionEmphasis 13/500 (CounterView.java:134-135)',
        () => expectRole(TgTextStyles.captionEmphasis, 13.0, FontWeight.w500));

    test('micro 12/400 (Theme.java:8472)',
        () => expectRole(TgTextStyles.micro, 12.0, FontWeight.w400));

    test('microEmphasis 12/500 (Theme.java:8363,8371)',
        () => expectRole(TgTextStyles.microEmphasis, 12.0, FontWeight.w500));

    test('tagSmall 11/500 (Theme.java:8405,8478)',
        () => expectRole(TgTextStyles.tagSmall, 11.0, FontWeight.w500));

    test('tag 10/500 (Theme.java:8409,8481)',
        () => expectRole(TgTextStyles.tag, 10.0, FontWeight.w500));
  });

  group('scale-wide invariants', () {
    test('exactly the 17 documented roles, all registered in [roles]', () {
      expect(TgTextStyles.roles, hasLength(17));
      expect(
        TgTextStyles.roles.keys,
        containsAll(<String>[
          'title', 'titleCondensed', 'titleGlass', 'input', 'cellTitle',
          'body', 'bodyEmphasis', 'bodySecondary', 'tab', 'label',
          'subtitle', 'caption', 'captionEmphasis', 'micro', 'microEmphasis',
          'tagSmall', 'tag',
        ]),
      );
      expect(identical(TgTextStyles.roles['title'], TgTextStyles.title), isTrue);
      expect(identical(TgTextStyles.roles['tag'], TgTextStyles.tag), isTrue);
    });

    test('weight is strictly binary — w400 or w500, never w700', () {
      for (final MapEntry<String, TextStyle> entry
          in TgTextStyles.roles.entries) {
        expect(
          entry.value.fontWeight,
          anyOf(FontWeight.w400, FontWeight.w500),
          reason: entry.key,
        );
        expect(entry.value.fontWeight, isNot(FontWeight.w700),
            reason: entry.key);
        expect(entry.value.fontWeight, isNot(FontWeight.bold),
            reason: entry.key);
      }
    });

    test('every w500 role uses the bundled RobotoMedium family', () {
      for (final MapEntry<String, TextStyle> entry
          in TgTextStyles.roles.entries) {
        if (entry.value.fontWeight == FontWeight.w500) {
          expect(entry.value.fontFamily, kMediumFamily, reason: entry.key);
        } else {
          expect(entry.value.fontFamily, isNull, reason: entry.key);
        }
      }
    });

    test('sizes span 10-20dp', () {
      for (final MapEntry<String, TextStyle> entry
          in TgTextStyles.roles.entries) {
        expect(entry.value.fontSize, inInclusiveRange(10.0, 20.0),
            reason: entry.key);
      }
    });

    test('styles carry no color — color resolves via theme keys at use sites',
        () {
      for (final MapEntry<String, TextStyle> entry
          in TgTextStyles.roles.entries) {
        expect(entry.value.color, isNull, reason: entry.key);
        expect(entry.value.backgroundColor, isNull, reason: entry.key);
      }
    });
  });

  group('kTgTextHeightBehavior', () {
    test('pins Android TextView metrics (no first-ascent/last-descent height)',
        () {
      expect(kTgTextHeightBehavior.applyHeightToFirstAscent, isFalse);
      expect(kTgTextHeightBehavior.applyHeightToLastDescent, isFalse);
    });
  });
}
