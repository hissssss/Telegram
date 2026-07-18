// Ring-1 tests for TelegramThemeData (ARCHITECTURE.md sections 4.1-4.2, 7):
// the Theme.getColor resolution order (currentColors -> fallbackKeys ->
// own-key default, Theme.java:9552-9618), forced-opaque keys, day/night
// palettes, lerp, copyWith identity and revision semantics.
//
// Spot-check hex values are hand-read from flutter/docs/spec_tokens.md and
// the Android sources — independent of the generated tables where the test's
// point is verification, programmatic against the generated palettes where
// the point is wiring.

import 'dart:ui' show Brightness, Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/palettes/palettes.g.dart';
import 'package:telegram_ui/src/tokens/theme_fallbacks.g.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

// Key ordinals under test (names -> ordinals via the generated constants).
const int _kDialogBackground = TelegramColorKey.dialogBackground; // 1
const int _kInlineProgressBg = TelegramColorKey.dialog_inlineProgressBackground;
const int _kGiftsTabText = TelegramColorKey.dialogGiftsTabText; // 48
const int _kGrayText2 = TelegramColorKey.windowBackgroundWhiteGrayText2; // 71
const int _kWindowBgWhite = TelegramColorKey.windowBackgroundWhite; // 49
const int _kWindowBgGray = TelegramColorKey.windowBackgroundGray; // 98
const int _kActionBarDefault = TelegramColorKey.actionBarDefault; // 165
const int _kActionBarArchived = TelegramColorKey.actionBarDefaultArchived;

void main() {
  group('resolution order (Theme.getColor, Theme.java:9552-9618)', () {
    test('defaults-only theme returns kDefaultColors values', () {
      final TelegramThemeData theme = TelegramThemeData();
      // dialogBackground default (ThemeColors.java line 24).
      expect(theme.color(_kDialogBackground), const Color(0xFFFFFFFF));
      // Every key resolves without throwing.
      for (int key = 0; key < TelegramColorKey.colorsCount; key++) {
        expect(theme.color(key), isA<Color>());
      }
    });

    test('override (currentColors) wins over fallback and default', () {
      final TelegramThemeData theme = TelegramThemeData.fromOverrides(
        <int, Color>{
          _kGiftsTabText: const Color(0xFF111111),
          _kGrayText2: const Color(0xFF222222),
        },
      );
      // Own entry wins even though 48 falls back to 71.
      expect(kFallbackKeys[_kGiftsTabText], _kGrayText2);
      expect(theme.color(_kGiftsTabText), const Color(0xFF111111));
    });

    test('override wins over the base palette for the same key', () {
      final TelegramThemeData theme = TelegramThemeData(
        basePalette: kDarkBlueTheme,
        overrides: <int, Color>{_kDialogBackground: const Color(0xFFABCDEF)},
      );
      expect(kDarkBlueTheme.containsKey(_kDialogBackground), isTrue);
      expect(theme.color(_kDialogBackground), const Color(0xFFABCDEF));
    });

    test('fallback resolves through a sparse OVERRIDE of the fallback target',
        () {
      // 48 (dialogGiftsTabText) is absent; its fallback target 71 is
      // overridden -> 48 must pick up the overridden value, per section 4.1
      // (sparse overrides keep fallback behavior).
      final TelegramThemeData theme = TelegramThemeData.fromOverrides(
        <int, Color>{_kGrayText2: const Color(0xFF123456)},
      );
      expect(theme.color(_kGiftsTabText), const Color(0xFF123456));
    });

    test('fallback resolves through a sparse base PALETTE', () {
      // kBlueTheme has no entry for 48 but does define 71 = 0xFF8C8F91
      // (bluebubbles.attheme windowBackgroundWhiteGrayText2).
      expect(kBlueTheme.containsKey(_kGiftsTabText), isFalse);
      expect(kBlueTheme[_kGrayText2], 0xFF8C8F91);
      expect(
        TelegramThemeData.day().color(_kGiftsTabText),
        const Color(0xFF8C8F91),
      );
    });

    test('missing key + missing fallback -> the key\'s OWN default', () {
      // Theme.java:9610 returns getDefaultColor(key), NOT the fallback
      // key's default. 48's default is 0xFF56595C; 71's is 0xFF82868A.
      final TelegramThemeData theme = TelegramThemeData();
      expect(theme.color(_kGiftsTabText), const Color(0xFF56595C));
      expect(theme.color(_kGrayText2), const Color(0xFF82868A));
      // dialog_inlineProgressBackground (fb -> windowBackgroundGray): own
      // default 0xF6F0F2F5, not windowBackgroundGray's 0xFFF1F1F3.
      expect(kFallbackKeys[_kInlineProgressBg], _kWindowBgGray);
      expect(theme.color(_kInlineProgressBg), const Color(0xF6F0F2F5));
    });

    test('out-of-range keys throw RangeError', () {
      final TelegramThemeData theme = TelegramThemeData();
      expect(() => theme.color(-1), throwsRangeError);
      expect(() => theme.color(TelegramColorKey.colorsCount), throwsRangeError);
    });
  });

  group('forced-opaque keys (Theme.java:9614)', () {
    test('the four kForcedOpaqueKeys get |0xFF000000 on read', () {
      expect(
        kForcedOpaqueKeys,
        unorderedEquals(<int>[
          _kWindowBgWhite,
          _kWindowBgGray,
          _kActionBarDefault,
          _kActionBarArchived,
        ]),
      );
      final TelegramThemeData theme = TelegramThemeData.fromOverrides(
        <int, Color>{
          for (final int key in kForcedOpaqueKeys) key: const Color(0x40112233),
        },
      );
      for (final int key in kForcedOpaqueKeys) {
        expect(
          theme.color(key),
          const Color(0xFF112233),
          reason: 'key $key must be forced opaque',
        );
      }
    });

    test('non-forced keys keep their alpha', () {
      final TelegramThemeData theme = TelegramThemeData.fromOverrides(
        <int, Color>{_kDialogBackground: const Color(0x40112233)},
      );
      expect(theme.color(_kDialogBackground), const Color(0x40112233));
    });

    test('brightness is computed from the forced-opaque value', () {
      // A fully transparent black override still reads back opaque black ->
      // dark.
      final TelegramThemeData theme = TelegramThemeData.fromOverrides(
        <int, Color>{_kWindowBgWhite: const Color(0x00000000)},
      );
      expect(theme.color(_kWindowBgWhite), const Color(0xFF000000));
      expect(theme.brightness, Brightness.dark);
    });
  });

  group('day()/night() vs the bundled palettes', () {
    test('day() is the Blue overlay over defaults', () {
      final TelegramThemeData day = TelegramThemeData.day();
      // Spot values hand-read from bluebubbles.attheme via spec_tokens.md.
      expect(day.color(TelegramColorKey.dialogTextLink), const Color(0xFF2981C4));
      expect(day.color(TelegramColorKey.dialogButton), const Color(0xFF3691D9));
      // Blue does not override windowBackgroundWhite -> default white.
      expect(kBlueTheme.containsKey(_kWindowBgWhite), isFalse);
      expect(day.color(_kWindowBgWhite), const Color(0xFFFFFFFF));
      expect(day.brightness, Brightness.light);
      // Full sweep: every overlay entry must win verbatim (modulo the
      // forced-opaque OR).
      kBlueTheme.forEach((int key, int argb) {
        final int expected =
            kForcedOpaqueKeys.contains(key) ? (argb | 0xFF000000) : argb;
        expect(day.color(key), Color(expected), reason: 'Blue key $key');
      });
    });

    test('night() is the Dark Blue overlay over defaults', () {
      final TelegramThemeData night = TelegramThemeData.night();
      // darkblue.attheme windowBackgroundWhite = 0xFF1D2733.
      expect(night.color(_kWindowBgWhite), const Color(0xFF1D2733));
      expect(night.brightness, Brightness.dark);
      kDarkBlueTheme.forEach((int key, int argb) {
        final int expected =
            kForcedOpaqueKeys.contains(key) ? (argb | 0xFF000000) : argb;
        expect(night.color(key), Color(expected), reason: 'Dark Blue key $key');
      });
    });

    test('fromBundledTheme matches day()/night() and rejects unknown names',
        () {
      final TelegramThemeData blue = TelegramThemeData.fromBundledTheme('Blue');
      final TelegramThemeData day = TelegramThemeData.day();
      for (int key = 0; key < TelegramColorKey.colorsCount; key++) {
        expect(blue.color(key), day.color(key));
      }
      // All five bundled names construct.
      for (final String name in kBundledThemes.keys) {
        expect(TelegramThemeData.fromBundledTheme(name), isA<TelegramThemeData>());
      }
      expect(
        () => TelegramThemeData.fromBundledTheme('Solarized'),
        throwsArgumentError,
      );
    });

    test('brightness threshold sits at perceivedBrightness 0.721', () {
      // 0xB8 -> 184/255 = 0.7216 >= 0.721 -> light; 0xB7 -> 0.7176 -> dark.
      expect(
        TelegramThemeData.fromOverrides(
          <int, Color>{_kWindowBgWhite: const Color(0xFFB8B8B8)},
        ).brightness,
        Brightness.light,
      );
      expect(
        TelegramThemeData.fromOverrides(
          <int, Color>{_kWindowBgWhite: const Color(0xFFB7B7B7)},
        ).brightness,
        Brightness.dark,
      );
    });
  });

  group('lerp', () {
    test('endpoints return the inputs themselves (revision preserved)', () {
      final TelegramThemeData a = TelegramThemeData.day();
      final TelegramThemeData b = TelegramThemeData.night();
      expect(identical(TelegramThemeData.lerp(a, b, 0.0), a), isTrue);
      expect(identical(TelegramThemeData.lerp(a, b, 1.0), b), isTrue);
      expect(identical(TelegramThemeData.lerp(a, b, -0.5), a), isTrue);
      expect(identical(TelegramThemeData.lerp(a, b, 1.5), b), isTrue);
      expect(identical(TelegramThemeData.lerp(a, a, 0.7), a), isTrue);
    });

    test('midpoint matches Color.lerp per key over all 777', () {
      final TelegramThemeData a = TelegramThemeData.day();
      final TelegramThemeData b = TelegramThemeData.night();
      final TelegramThemeData mid = TelegramThemeData.lerp(a, b, 0.5);
      for (int key = 0; key < TelegramColorKey.colorsCount; key++) {
        expect(
          mid.color(key).toARGB32(),
          Color.lerp(a.color(key), b.color(key), 0.5)!.toARGB32(),
          reason: 'key $key',
        );
      }
    });

    test('brightness snaps to the nearer endpoint (t < 0.5 ? a : b)', () {
      final TelegramThemeData a = TelegramThemeData.day(); // light
      final TelegramThemeData b = TelegramThemeData.night(); // dark
      expect(TelegramThemeData.lerp(a, b, 0.25).brightness, Brightness.light);
      expect(TelegramThemeData.lerp(a, b, 0.49).brightness, Brightness.light);
      expect(TelegramThemeData.lerp(a, b, 0.5).brightness, Brightness.dark);
      expect(TelegramThemeData.lerp(a, b, 0.75).brightness, Brightness.dark);
    });

    test('lerp product keeps forced-opaque keys opaque', () {
      final TelegramThemeData mid = TelegramThemeData.lerp(
        TelegramThemeData.day(),
        TelegramThemeData.night(),
        0.37,
      );
      for (final int key in kForcedOpaqueKeys) {
        expect((mid.color(key).toARGB32() >> 24) & 0xFF, 0xFF);
      }
    });

    test('copyWith on a lerp product overlays the dense snapshot', () {
      final TelegramThemeData mid = TelegramThemeData.lerp(
        TelegramThemeData.day(),
        TelegramThemeData.night(),
        0.5,
      );
      final TelegramThemeData patched = mid.copyWith(
        overrides: <int, Color>{_kDialogBackground: const Color(0xFF010203)},
      );
      expect(patched.color(_kDialogBackground), const Color(0xFF010203));
      // All other keys unchanged.
      for (int key = 0; key < TelegramColorKey.colorsCount; key++) {
        if (key == _kDialogBackground) {
          continue;
        }
        expect(patched.color(key), mid.color(key), reason: 'key $key');
      }
    });
  });

  group('copyWith / revision / equality', () {
    test('copyWith with no (or empty) overrides is identity', () {
      final TelegramThemeData theme = TelegramThemeData.day();
      expect(identical(theme.copyWith(), theme), isTrue);
      expect(
        identical(theme.copyWith(overrides: const <int, Color>{}), theme),
        isTrue,
      );
    });

    test('copyWith changes only the overridden key and its fallback dependents',
        () {
      final TelegramThemeData night = TelegramThemeData.night();
      final TelegramThemeData patched = night.copyWith(
        overrides: <int, Color>{_kDialogBackground: const Color(0xFF0A0B0C)},
      );
      expect(patched.color(_kDialogBackground), const Color(0xFF0A0B0C));
      // Keys that fall back onto the overridden key AND are not defined by
      // the Dark Blue overlay legitimately change too — Android's getColor
      // reads the fallback out of currentColors (Theme.java:9594-9599).
      // Example: 652 location_actionBackground -> 1 dialogBackground.
      final Set<int> dependents = <int>{
        for (final MapEntry<int, int> entry in kFallbackKeys.entries)
          if (entry.value == _kDialogBackground &&
              !kDarkBlueTheme.containsKey(entry.key))
            entry.key,
      };
      expect(dependents, contains(TelegramColorKey.location_actionBackground));
      for (int key = 0; key < TelegramColorKey.colorsCount; key++) {
        if (key == _kDialogBackground) {
          continue;
        }
        if (dependents.contains(key)) {
          expect(
            patched.color(key),
            const Color(0xFF0A0B0C),
            reason: 'fallback dependent key $key',
          );
        } else {
          expect(patched.color(key), night.color(key), reason: 'key $key');
        }
      }
    });

    test('copyWith keeps fallback-through-sparse-override behavior', () {
      // Override only the fallback TARGET (71); the dependent key (48) must
      // re-resolve through it even though the base theme is Blue.
      final TelegramThemeData patched = TelegramThemeData.day().copyWith(
        overrides: <int, Color>{_kGrayText2: const Color(0xFF654321)},
      );
      expect(patched.color(_kGiftsTabText), const Color(0xFF654321));
    });

    test('revision is monotonic per construction', () {
      final TelegramThemeData a = TelegramThemeData.day();
      final TelegramThemeData b = TelegramThemeData.day();
      final TelegramThemeData c = a.copyWith(
        overrides: <int, Color>{_kDialogBackground: const Color(0xFF000001)},
      );
      final TelegramThemeData d = TelegramThemeData.lerp(a, b, 0.5);
      expect(b.revision, greaterThan(a.revision));
      expect(c.revision, greaterThan(b.revision));
      expect(d.revision, greaterThan(c.revision));
    });

    test('== and hashCode are by revision (identity), not content', () {
      final TelegramThemeData a = TelegramThemeData.day();
      final TelegramThemeData b = TelegramThemeData.day();
      expect(a, equals(a));
      expect(a.hashCode, a.revision);
      // Identical content, different construction -> not equal.
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
      expect(identical(a.copyWith(), a) && a.copyWith() == a, isTrue);
    });
  });

  group('typed color scheme + lookup cost', () {
    test('colors is wired to the theme resolver', () {
      final TelegramThemeData night = TelegramThemeData.night();
      expect(night.colors.window.white, night.color(_kWindowBgWhite));
      expect(
        night.colors.chat.inBubble,
        night.color(TelegramColorKey.chat_inBubble),
      );
      expect(
        night.colors.actionBar.defaultTitle,
        night.color(TelegramColorKey.actionBarDefaultTitle),
      );
    });

    test('color() lookup is O(1)-ish: flat cost regardless of override count',
        () {
      // Sanity check, not a benchmark: 777k lookups on both an empty theme
      // and a fully overridden one must complete within a budget ~100x above
      // what a precomputed Int32List read costs. Catches accidental
      // reintroduction of per-read map/fallback walks.
      final TelegramThemeData sparse = TelegramThemeData();
      final TelegramThemeData saturated = TelegramThemeData.fromOverrides(
        <int, Color>{
          for (int key = 0; key < TelegramColorKey.colorsCount; key++)
            key: Color(0xFF000000 | key),
        },
      );
      int checksum = 0;
      Duration sweep(TelegramThemeData theme) {
        final Stopwatch watch = Stopwatch()..start();
        for (int i = 0; i < 1000; i++) {
          for (int key = 0; key < TelegramColorKey.colorsCount; key++) {
            checksum ^= theme.color(key).toARGB32();
          }
        }
        return (watch..stop()).elapsed;
      }

      sweep(sparse); // warm up JIT.
      expect(sweep(sparse), lessThan(const Duration(seconds: 5)));
      expect(sweep(saturated), lessThan(const Duration(seconds: 5)));
      expect(checksum, isNot(-1)); // keep the loop observable.
    });
  });
}
