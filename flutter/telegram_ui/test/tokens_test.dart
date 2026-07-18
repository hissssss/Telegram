// Ring-1 token tests (ARCHITECTURE.md §7): lock the generated token tables
// against values read independently from the Android sources / the token
// spec (flutter/docs/spec_tokens.md), so codegen regressions cannot land
// silently.

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/color_math.dart'
    show kDarkThemeBrightnessThreshold;
import 'package:telegram_ui/src/tokens/color_scheme.g.dart';
import 'package:telegram_ui/src/tokens/glass_metrics.g.dart'
    show kGlassDarkBrightnessThreshold;
import 'package:telegram_ui/src/tokens/palettes/palettes.g.dart';
import 'package:telegram_ui/src/tokens/theme_fallbacks.g.dart';
import 'package:telegram_ui/src/tokens/theme_key_names.g.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// (key ordinal, attheme serialized name, default ARGB) triples, hand-read
/// from spec_tokens.md §3 (which cites ThemeColors.java line numbers) plus
/// the glass/accent keys. Do NOT copy these from the generated files — the
/// point is independent verification.
const List<(int, String, int)> kSpotChecks = <(int, String, int)>[
  (TelegramColorKey.windowBackgroundWhite, 'windowBackgroundWhite', 0xFFFFFFFF),
  (TelegramColorKey.windowBackgroundGray, 'windowBackgroundGray', 0xFFF1F1F3),
  (
    TelegramColorKey.windowBackgroundWhiteBlackText,
    'windowBackgroundWhiteBlackText',
    0xFF1A1D21,
  ),
  (
    TelegramColorKey.windowBackgroundWhiteGrayText,
    'windowBackgroundWhiteGrayText',
    0xFF808384,
  ),
  (
    TelegramColorKey.windowBackgroundWhiteHintText,
    'windowBackgroundWhiteHintText',
    0xFFA8A8A8,
  ),
  (
    TelegramColorKey.windowBackgroundWhiteLinkText,
    'windowBackgroundWhiteLinkText',
    0xFF298ACF,
  ),
  (TelegramColorKey.divider, 'divider', 0xFFD9D9D9),
  (TelegramColorKey.graySection, 'graySection', 0xFFF5F5F5),
  (TelegramColorKey.actionBarDefault, 'actionBarDefault', 0xFFFFFFFF),
  (TelegramColorKey.actionBarDefaultIcon, 'actionBarDefaultIcon', 0xFF1A1D21),
  (TelegramColorKey.actionBarDefaultTitle, 'actionBarDefaultTitle', 0xFF1A1D21),
  (
    TelegramColorKey.actionBarDefaultSubtitle,
    'actionBarDefaultSubtitle',
    0xFF79817E,
  ),
  (
    TelegramColorKey.actionBarDefaultSelector,
    'actionBarDefaultSelector',
    0x121A1D21,
  ),
  (
    TelegramColorKey.actionBarDefaultSubmenuBackground,
    'actionBarDefaultSubmenuBackground',
    0xFFFFFFFF,
  ),
  (
    TelegramColorKey.actionBarTabActiveText,
    'actionBarTabActiveText',
    0xFF298ACF,
  ),
  (
    TelegramColorKey.actionBarTabUnactiveText,
    'actionBarTabUnactiveText',
    0xFF777C7F,
  ),
  (TelegramColorKey.actionBarTabLine, 'actionBarTabLine', 0xFF298ACF),
  (TelegramColorKey.chats_name, 'chats_name', 0xFF1A1D21),
  (TelegramColorKey.chats_message, 'chats_message', 0xFF75787A),
  (TelegramColorKey.chats_nameMessage, 'chats_nameMessage', 0xFF298ACF),
  (TelegramColorKey.chats_date, 'chats_date', 0xFF848688),
  (TelegramColorKey.chats_unreadCounter, 'chats_unreadCounter', 0xFF229AF0),
  (
    TelegramColorKey.chats_unreadCounterMuted,
    'chats_unreadCounterMuted',
    0xFFBEC3C7,
  ),
  (
    TelegramColorKey.chats_unreadCounterText,
    'chats_unreadCounterText',
    0xFFFFFFFF,
  ),
  (TelegramColorKey.chats_sentReadCheck, 'chats_sentReadCheck', 0xFF46AA36),
  (TelegramColorKey.chats_onlineCircle, 'chats_onlineCircle', 0xFF4BCB1C),
  (TelegramColorKey.chat_inBubble, 'chat_inBubble', 0xFFFFFFFF),
  (TelegramColorKey.chat_inBubbleSelected, 'chat_inBubbleSelected', 0xFFECF7FD),
  (TelegramColorKey.chat_outBubble, 'chat_outBubble', 0xFFEFFFDE),
  (
    TelegramColorKey.chat_outBubbleSelected,
    'chat_outBubbleSelected',
    0xFFD9F7C5,
  ),
  (TelegramColorKey.chat_messageTextIn, 'chat_messageTextIn', 0xFF000000),
  (TelegramColorKey.chat_messageTextOut, 'chat_messageTextOut', 0xFF000000),
  (TelegramColorKey.chat_messageLinkIn, 'chat_messageLinkIn', 0xFF2678B6),
  (TelegramColorKey.chat_inTimeText, 'chat_inTimeText', 0xFFA1AAB3),
  (TelegramColorKey.chat_outTimeText, 'chat_outTimeText', 0xFF70B15C),
  (
    TelegramColorKey.chat_messagePanelBackground,
    'chat_messagePanelBackground',
    0xFFFFFFFF,
  ),
  (TelegramColorKey.chat_messagePanelHint, 'chat_messagePanelHint', 0xFF858A84),
  (TelegramColorKey.dialogBackground, 'dialogBackground', 0xFFFFFFFF),
  (TelegramColorKey.dialogTextBlack, 'dialogTextBlack', 0xFF1A1D21),
  (TelegramColorKey.dialogButton, 'dialogButton', 0xFF298ACF),
  (
    TelegramColorKey.featuredStickers_addButton,
    'featuredStickers_addButton',
    0xFF229AF0,
  ),
  (TelegramColorKey.switchTrackChecked, 'switchTrackChecked', 0xFF229AF0),
  (TelegramColorKey.checkbox, 'checkbox', 0xFF5EC245),
  (TelegramColorKey.telegram_color, 'telegram_color', 0xFF229AF0),
  (TelegramColorKey.glass_tabSelected, 'glass_tabSelected', 0xFF1A91E6),
  (
    TelegramColorKey.glass_tabSelectedText,
    'glass_tabSelectedText',
    0xFF0D7FCF,
  ),
  (TelegramColorKey.glass_tabUnselected, 'glass_tabUnselected', 0xFF1A1D21),
  (TelegramColorKey.glass_defaultIcon, 'glass_defaultIcon', 0x991B2227),
  (TelegramColorKey.glass_defaultText, 'glass_defaultText', 0x991B2227),
];

void main() {
  group('cross-layer drift gates', () {
    test(
        'hand-written kDarkThemeBrightnessThreshold equals the generated '
        'kGlassDarkBrightnessThreshold', () {
      // foundation/ is a deliberately import-free leaf layer, so
      // color_math.dart hard-codes the 0.721 threshold of
      // BlurredBackgroundColorProviderThemed.java:34-37 while the codegen
      // pipeline extracts the same value into glass_metrics.g.dart. The
      // generated token is the source of truth; a re-extraction that moves
      // it must fail here until the hand-written copy follows.
      expect(kDarkThemeBrightnessThreshold, kGlassDarkBrightnessThreshold);
    });
  });

  group('key ordinals', () {
    test('count matches Theme.java colorsCount (777)', () {
      expect(TelegramColorKey.colorsCount, 777);
      expect(kDefaultColors.length, TelegramColorKey.colorsCount);
      expect(kColorKeyNames.length, TelegramColorKey.colorsCount);
    });

    test('ordinal pinning against Theme.java declaration order', () {
      // Theme.java:3365+ — first three declarations.
      expect(TelegramColorKey.wallpaperFileOffset, 0);
      expect(TelegramColorKey.dialogBackground, 1);
      expect(TelegramColorKey.dialogBackgroundGray, 2);
      // Independently counted declaration positions (grep -c over Theme.java).
      expect(TelegramColorKey.windowBackgroundWhite, 49);
      expect(TelegramColorKey.glass_tabSelected, 768);
      // Last two declarations (Theme.java:4207-4208).
      expect(TelegramColorKey.telegram_color, 775);
      expect(TelegramColorKey.telegram_color_text, 776);
    });
  });

  group('spot-checked (key, name, default) triples', () {
    test('${kSpotChecks.length} triples from spec_tokens.md / ThemeColors.java',
        () {
      expect(kSpotChecks.length, greaterThanOrEqualTo(30));
      for (final (key, name, argb) in kSpotChecks) {
        expect(kColorKeyNames[key], name, reason: 'name of ordinal $key');
        expect(kAttThemeNames[name], key, reason: 'reverse lookup of $name');
        expect(
          kDefaultColors[key],
          argb,
          reason:
              'default for $name: got '
              '0x${kDefaultColors[key].toRadixString(16).toUpperCase()}',
        );
      }
    });

    test('unassigned keys default to Java zero-init 0x00000000', () {
      // 777 declared vs 760 assigned — e.g. runtime-computed service bg.
      expect(kDefaultColors[TelegramColorKey.chat_serviceBackground], 0);
      expect(kDefaultColors[TelegramColorKey.fill_RedDark], 0);
      expect(kDefaultColors[TelegramColorKey.chat_wallpaper], 0);
    });
  });

  group('attheme name map', () {
    test('773 serialized names for 777 keys', () {
      expect(kAttThemeNames.length, 773);
      expect(kColorKeyNames.whereType<String>().length, 773);
    });

    test('the 4 known name mismatches are preserved verbatim', () {
      // ARCHITECTURE.md §4.1 / spec_tokens.md §1c — names must come from
      // createColorKeysMap, never from string-munging the Java identifier.
      expect(kColorKeyNames[TelegramColorKey.listSelector], 'listSelectorSDK21');
      expect(
        kColorKeyNames[TelegramColorKey.graySectionText],
        'key_graySectionText', // upstream typo preserved
      );
      expect(kColorKeyNames[TelegramColorKey.chat_inGreenCall], 'chat_inDownCall');
      expect(kColorKeyNames[TelegramColorKey.chat_outGreenCall], 'chat_outUpCall');
      expect(
        kColorKeyNames[TelegramColorKey.actionBarDefaultArchivedSearchPlaceholder],
        'actionBarDefaultSearchArchivedPlaceholder',
      );
    });

    test('keys with no serialized name are null', () {
      expect(kColorKeyNames[TelegramColorKey.settings_listSelector], isNull);
      expect(kColorKeyNames[TelegramColorKey.avatar_backgroundGray], isNull);
      expect(kColorKeyNames[TelegramColorKey.starsGradient1], isNull);
      expect(kColorKeyNames[TelegramColorKey.starsGradient2], isNull);
    });
  });

  group('fallbacks and forced-opaque', () {
    test('183 fallback pairs, sampled against Theme.java', () {
      expect(kFallbackKeys.length, 183);
      expect(
        kFallbackKeys[TelegramColorKey.graySectionText],
        TelegramColorKey.windowBackgroundWhiteGrayText2,
      );
      expect(
        kFallbackKeys[TelegramColorKey.chat_inQuote],
        TelegramColorKey.featuredStickers_addButtonPressed,
      );
      expect(
        kFallbackKeys[TelegramColorKey.iv_background],
        TelegramColorKey.windowBackgroundWhite,
      );
      expect(
        kFallbackKeys[TelegramColorKey.glass_tabSelected],
        TelegramColorKey.chat_messagePanelSend,
      );
      expect(
        kFallbackKeys[TelegramColorKey.telegram_color],
        TelegramColorKey.chat_messagePanelSend,
      );
      // Keys with a default and no fallback stay absent.
      expect(kFallbackKeys.containsKey(TelegramColorKey.dialogBackground), false);
    });

    test('forced-opaque keys (Theme.getColor `|= 0xFF000000`)', () {
      expect(kForcedOpaqueKeys, <int>[
        TelegramColorKey.windowBackgroundWhite,
        TelegramColorKey.windowBackgroundGray,
        TelegramColorKey.actionBarDefault,
        TelegramColorKey.actionBarDefaultArchived,
      ]);
    });
  });

  group('bundled theme overlays', () {
    test('the five Android registrations, sparse sizes from the assets', () {
      expect(kBundledThemes.keys.toList(), <String>[
        'Blue',
        'Dark Blue',
        'Arctic Blue',
        'Day',
        'Night',
      ]);
      expect(kBlueTheme.length, 183);
      expect(kDarkBlueTheme.length, 471);
      expect(kArcticBlueTheme.length, 278);
      expect(kDayTheme.length, 304);
      expect(kNightTheme.length, 494);
      expect(kBundledThemes['Dark Blue'], same(kDarkBlueTheme));
    });

    test('signed-decimal attheme values decode like Android', () {
      // night.attheme:235 `windowBackgroundWhite=-15198183`.
      expect(kNightTheme[TelegramColorKey.windowBackgroundWhite], 0xFF181819);
      // darkblue.attheme final line `stories_circle2=-11682817` (kept: the
      // file ends with a newline).
      expect(kDarkBlueTheme[TelegramColorKey.stories_circle2], 0xFF4DBBFF);
      // bluebubbles.attheme final line, also newline-terminated.
      expect(kBlueTheme[TelegramColorKey.dialogTopBackground], 0xFF326A98);
    });

    test('dropped-final-line Android parity (day/arctic lack trailing \\n)',
        () {
      // `chat_editMediaButton=-15033089` is the last, unterminated line of
      // both files; Theme.getThemeFileValues silently drops it.
      final int key = TelegramColorKey.chat_editMediaButton;
      expect(kDayTheme.containsKey(key), false);
      expect(kArcticBlueTheme.containsKey(key), false);
    });

    test('wallpaperFileOffset mirrors the Android parser (-1, no WPS)', () {
      for (final MapEntry<String, Map<int, int>> e in kBundledThemes.entries) {
        expect(
          e.value[TelegramColorKey.wallpaperFileOffset],
          0xFFFFFFFF,
          reason: '${e.key} should store -1 as unsigned',
        );
      }
    });
  });

  group('typed color scheme', () {
    Color resolve(int key) => Color(kDefaultColors[key]);
    final TelegramColorScheme scheme = TelegramColorScheme(resolve);

    test('grouped accessors resolve through the generated key ordinals', () {
      expect(scheme.chat.inBubble, const Color(0xFFFFFFFF));
      expect(scheme.chat.outBubble, const Color(0xFFEFFFDE));
      expect(scheme.chats.unreadCounter, const Color(0xFF229AF0));
      expect(scheme.window.white, const Color(0xFFFFFFFF));
      expect(scheme.window.gray, const Color(0xFFF1F1F3));
      expect(scheme.glass.tabSelected, const Color(0xFF1A91E6));
      expect(scheme.glass.tabUnselected, const Color(0xFF1A1D21));
      expect(scheme.accent.telegramColor, const Color(0xFF229AF0));
      expect(scheme.dialog.textBlack, const Color(0xFF1A1D21));
      // Reserved-word fallback: actionBarDefault keeps its full name.
      expect(scheme.actionBar.actionBarDefault, const Color(0xFFFFFFFF));
      // Leading-digit fallback: switch2Track keeps its full name.
      expect(
        scheme.switches.switch2Track,
        Color(kDefaultColors[TelegramColorKey.switch2Track]),
      );
    });

    test('ungrouped catch-all reaches keys outside every group', () {
      expect(scheme.ungrouped.divider, const Color(0xFFD9D9D9));
      expect(scheme.ungrouped.graySection, const Color(0xFFF5F5F5));
      expect(
        scheme.ungrouped.fillRedNormal,
        Color(kDefaultColors[TelegramColorKey.fill_RedNormal]),
      );
    });

    test('escape hatch exposes the raw resolver', () {
      expect(
        scheme.resolve(TelegramColorKey.chat_inBubble),
        const Color(0xFFFFFFFF),
      );
    });
  });
}
