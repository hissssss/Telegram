// Ring-1 tests for AtthemeCodec (ARCHITECTURE.md sections 4.4 and 7).
//
// The centerpiece is the cross-language parity suite: the Dart decoder
// reads the five bundled `.attheme` assets straight from the ANDROID tree
// (TMessagesProj/src/main/assets/) and must reproduce, color for color, the
// checked-in palettes under lib/src/tokens/palettes/ that the independent
// Python parser (flutter/tool/gen_tokens.py Pass 4) generated from the very
// same bytes — including the dropped-final-line quirk of day.attheme and
// arctic.attheme and the per-asset unknown-name warnings recorded in
// flutter/tool/theme_tokens.json meta.
//
// Also covered: encode -> decode round-trips (the encoder as parser
// oracle), the Utilities.parseInt quirk table, Color.parseColor semantics,
// WLS/WPS wallpaper passthrough with synthetic binary bytes, and the
// 1024-byte chunked-scanner edge cases of Theme.getThemeFileValues
// (Theme.java:8135).

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/theme/attheme_codec.dart';
import 'package:telegram_ui/src/tokens/palettes/palettes.g.dart';
import 'package:telegram_ui/src/tokens/theme_key_names.g.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// The bundled assets in the Android tree, relative to this package root
/// (flutter/telegram_ui), which is the cwd `flutter test` runs from.
const String _kAssetsDir = '../../TMessagesProj/src/main/assets';

/// Android registration name -> (asset file, generated palette, whether the
/// asset's final line lacks a trailing `\n` and is dropped on Android).
/// Mirrors the Theme.java static-init registrations captured in
/// flutter/tool/theme_tokens.json.
const List<(String, String, Map<int, int>, bool)> _kBundledAssets =
    <(String, String, Map<int, int>, bool)>[
      ('Blue', 'bluebubbles.attheme', kBlueTheme, false),
      ('Dark Blue', 'darkblue.attheme', kDarkBlueTheme, false),
      ('Arctic Blue', 'arctic.attheme', kArcticBlueTheme, true),
      ('Day', 'day.attheme', kDayTheme, true),
      ('Night', 'night.attheme', kNightTheme, false),
    ];

/// Unknown serialized names per asset (warned + ignored), hand-copied from
/// theme_tokens.json meta so the two parsers must agree on tolerance too.
const Map<String, List<String>> _kExpectedUnknownNames = <String, List<String>>{
  'bluebubbles.attheme': <String>[
    'key_telegram_color_text',
    'chat_attachLocationText',
  ],
  'darkblue.attheme': <String>[
    'avatar_actionBarSelectorGreen',
    'chat_emojiPanelBadgeBackground',
  ],
  'arctic.attheme': <String>['chat_attachLocationText'],
  'day.attheme': <String>['chat_attachLocationText'],
  'night.attheme': <String>[
    'avatar_actionBarSelectorGreen',
    'chat_emojiPanelBadgeBackground',
  ],
};

Uint8List _readAsset(String name) =>
    File('$_kAssetsDir/$name').readAsBytesSync();

Map<int, int> _argbMap(Map<int, Color> colors) =>
    colors.map((int key, Color color) => MapEntry(key, color.toARGB32()));

void main() {
  group('cross-language parity: Dart decoder vs Python-generated palettes', () {
    for (final (
          String themeName,
          String asset,
          Map<int, int> palette,
          bool dropsFinalLine,
        )
        in _kBundledAssets) {
      test('$asset decodes byte-for-byte to k${themeName.replaceAll(' ', '')}'
          'Theme', () {
        final AtthemeDecodeResult result = AtthemeCodec.decode(
          _readAsset(asset),
        );

        expect(
          _argbMap(result.colors),
          equals(palette),
          reason: 'Dart parser must match gen_tokens.py Pass 4 exactly',
        );
        // No bundled asset carries a wallpaper.
        expect(result.wallpaperLink, isNull);
        expect(result.wallpaperBytes, isNull);
        // wallpaperFileOffset slot = -1 masked (no WPS marker).
        expect(
          result.colors[TelegramColorKey.wallpaperFileOffset],
          const Color(0xFFFFFFFF),
        );

        expect(
          result.droppedFinalLine,
          dropsFinalLine,
          reason:
              'day/arctic lack a trailing newline; Android silently '
              'drops their final line',
        );
        if (dropsFinalLine) {
          // Both files end with the same unterminated entry.
          expect(
            result.warnings.join('\n'),
            contains('chat_editMediaButton=-15033089'),
          );
        }

        // Unknown names are warnings, never errors — and exactly the ones
        // the Python parser recorded.
        final List<String> unknownWarnings = result.warnings
            .where((String w) => w.startsWith('unknown attheme key'))
            .toList();
        expect(
          unknownWarnings,
          _kExpectedUnknownNames[asset]!
              .map((String name) => "unknown attheme key '$name' ignored")
              .toList(),
        );
      });
    }

    test('bundled palettes are sparse overlays (sanity)', () {
      // Guards the fixture wiring: entry counts straight from
      // theme_tokens.json meta.
      expect(kBlueTheme.length, 183);
      expect(kDarkBlueTheme.length, 471);
      expect(kArcticBlueTheme.length, 278);
      expect(kDayTheme.length, 304);
      expect(kNightTheme.length, 494);
    });
  });

  group('encode -> decode round-trip (encoder as parser oracle)', () {
    for (final (String themeName, String asset, _, _) in _kBundledAssets) {
      test('$asset survives decode -> encode -> decode', () {
        final AtthemeDecodeResult first = AtthemeCodec.decode(
          _readAsset(asset),
        );
        final Uint8List encoded = AtthemeCodec.encode(first.colors);
        final AtthemeDecodeResult second = AtthemeCodec.decode(encoded);

        expect(
          _argbMap(second.colors),
          _argbMap(first.colors),
          reason: '$themeName colors must survive the round trip',
        );
        expect(second.wallpaperLink, isNull);
        expect(second.wallpaperBytes, isNull);
        expect(
          second.warnings,
          isEmpty,
          reason: 'encoder writes only known names',
        );
        expect(
          second.droppedFinalLine,
          isFalse,
          reason: 'encoder always terminates the final line',
        );
      });
    }

    test('hand-built map round-trips, including low-alpha positive ints', () {
      final Map<int, Color> colors = <int, Color>{
        TelegramColorKey.dialogBackground: const Color(0xFFFFFFFF), // -1
        TelegramColorKey.dialogTextBlack: const Color(0xFF1A1D21),
        TelegramColorKey.listSelector: const Color(0x0F000000),
        // Positive signed decimal (alpha < 0x80): 285212671.
        TelegramColorKey.actionBarDefaultSelector: const Color(0x10FFFFFF),
        TelegramColorKey.chat_wallpaper: const Color(0x00000000),
      };
      final Uint8List encoded = AtthemeCodec.encode(colors);
      final AtthemeDecodeResult decoded = AtthemeCodec.decode(encoded);
      final Map<int, Color> expected = Map<int, Color>.of(colors)
        ..[TelegramColorKey.wallpaperFileOffset] = const Color(0xFFFFFFFF);
      expect(_argbMap(decoded.colors), _argbMap(expected));
      expect(decoded.warnings, isEmpty);
      expect(decoded.droppedFinalLine, isFalse);
    });

    test('encode writes Android signed decimals, sorted by ordinal, with '
        'trailing newline', () {
      final Uint8List encoded = AtthemeCodec.encode(<int, Color>{
        // Deliberately out of ordinal order (dialogTextBlack is ordinal 3,
        // dialogBackground ordinal 1).
        TelegramColorKey.dialogTextBlack: const Color(0xFF1A1D21),
        TelegramColorKey.dialogBackground: const Color(0xFFFFFFFF),
        TelegramColorKey.actionBarDefaultSelector: const Color(0x10FFFFFF),
      });
      expect(
        String.fromCharCodes(encoded),
        'dialogBackground=-1\n'
        'dialogTextBlack=-15065823\n'
        'actionBarDefaultSelector=285212671\n',
      );
    });

    test(
      'encode uses the createColorKeysMap name, not the Java identifier',
      () {
        // key_listSelector serializes as 'listSelectorSDK21' and
        // key_graySectionText as 'key_graySectionText' (upstream typo kept).
        final Uint8List encoded = AtthemeCodec.encode(<int, Color>{
          TelegramColorKey.listSelector: const Color(0x0F000000),
          TelegramColorKey.graySectionText: const Color(0xFF82868A),
        });
        final String text = String.fromCharCodes(encoded);
        expect(text, contains('listSelectorSDK21=251658240\n'));
        expect(text, contains('key_graySectionText=-8223094\n'));
        final AtthemeDecodeResult decoded = AtthemeCodec.decode(encoded);
        expect(
          decoded.colors[TelegramColorKey.listSelector],
          const Color(0x0F000000),
        );
        expect(
          decoded.colors[TelegramColorKey.graySectionText],
          const Color(0xFF82868A),
        );
      },
    );

    test('encode skips the wallpaperFileOffset slot', () {
      final Uint8List encoded = AtthemeCodec.encode(<int, Color>{
        TelegramColorKey.wallpaperFileOffset: const Color(0xFFFFFFFF),
        TelegramColorKey.dialogBackground: const Color(0xFFFFFFFF),
      });
      expect(String.fromCharCodes(encoded), 'dialogBackground=-1\n');
    });

    test('encode throws on out-of-range or unnamed key ordinals', () {
      expect(
        () => AtthemeCodec.encode(<int, Color>{
          TelegramColorKey.colorsCount: const Color(0xFF000000),
        }),
        throwsArgumentError,
      );
      expect(
        () => AtthemeCodec.encode(<int, Color>{-1: const Color(0xFF000000)}),
        throwsArgumentError,
      );
      // settings_listSelector has no createColorKeysMap() entry and cannot
      // be serialized (theme_tokens.json meta keysWithoutName).
      expect(kColorKeyNames[TelegramColorKey.settings_listSelector], isNull);
      expect(
        () => AtthemeCodec.encode(<int, Color>{
          TelegramColorKey.settings_listSelector: const Color(0xFF000000),
        }),
        throwsArgumentError,
      );
    });
  });

  group('value parsing: Utilities.parseInt quirks (Utilities.java:157)', () {
    // Each case decodes a single known-name line; expectation is the masked
    // ARGB stored for that key.
    const List<(String, int)> cases = <(String, int)>[
      ('-1', 0xFFFFFFFF), // clean signed decimal
      ('-15065823', 0xFF1A1D21),
      ('285212671', 0x10FFFFFF), // positive (alpha < 0x80)
      ('0', 0x00000000),
      // The end++ quirk: a disallowed char TERMINATING a run is included in
      // the parsed substring -> Integer.parseInt throws -> 0.
      ('500x', 0x00000000),
      ('12a34', 0x00000000),
      ('42 ', 0x00000000), // trailing space joins the substring -> 0
      // A run STARTED after garbage parses cleanly to end of input.
      ('x500', 500),
      (' 42', 42), // leading space skipped, no terminator -> 42
      ('abc', 0x00000000), // no run at all -> 0
      ('', 0x00000000), // empty param -> 0
      ('-', 0x00000000), // bare sign -> Integer.parseInt throws -> 0
      ('-5-3', 0x00000000), // '-' is an allowed char: run '-5-3' -> throws
      ('99999999999', 0x00000000), // > 32-bit signed -> overflow -> 0
      ('2147483647', 0x7FFFFFFF), // Integer.MAX_VALUE parses exactly
      ('-2147483648', 0x80000000), // Integer.MIN_VALUE parses exactly
    ];
    for (final (String param, int expected) in cases) {
      test("'$param' -> 0x${expected.toRadixString(16).padLeft(8, '0')}", () {
        final AtthemeDecodeResult result = AtthemeCodec.decodeString(
          'dialogBackground=$param\n',
        );
        expect(
          result.colors[TelegramColorKey.dialogBackground],
          Color(expected),
        );
        expect(result.warnings, isEmpty);
      });
    }
  });

  group('value parsing: Color.parseColor semantics', () {
    test('#RRGGBB gets an implicit FF alpha', () {
      final AtthemeDecodeResult result = AtthemeCodec.decodeString(
        'dialogBackground=#229AF0\n',
      );
      expect(
        result.colors[TelegramColorKey.dialogBackground],
        const Color(0xFF229AF0),
      );
    });

    test('#AARRGGBB is taken as-is', () {
      final AtthemeDecodeResult result = AtthemeCodec.decodeString(
        'dialogBackground=#80229AF0\n',
      );
      expect(
        result.colors[TelegramColorKey.dialogBackground],
        const Color(0x80229AF0),
      );
    });

    test('bad hex length falls back to Utilities.parseInt', () {
      // '#12345' has 5 hex digits -> parseColor throws -> parseInt scans
      // the '12345' digit run -> 12345.
      final AtthemeDecodeResult result = AtthemeCodec.decodeString(
        'dialogBackground=#12345\n',
      );
      expect(
        result.colors[TelegramColorKey.dialogBackground],
        const Color(0x00003039), // 12345
      );
    });

    test('non-hex payload falls back to Utilities.parseInt -> 0', () {
      final AtthemeDecodeResult result = AtthemeCodec.decodeString(
        'dialogBackground=#GGHHII\n',
      );
      expect(
        result.colors[TelegramColorKey.dialogBackground],
        const Color(0x00000000),
      );
    });
  });

  group('line-level semantics of Theme.getThemeFileValues', () {
    test('lines without = are ignored silently', () {
      final AtthemeDecodeResult result = AtthemeCodec.decodeString(
        'no equals sign here\ndialogBackground=-1\n',
      );
      expect(
        result.colors[TelegramColorKey.dialogBackground],
        const Color(0xFFFFFFFF),
      );
      expect(result.warnings, isEmpty);
    });

    test('unknown names are warnings, not errors', () {
      final AtthemeDecodeResult result = AtthemeCodec.decodeString(
        'notARealKey=-1\ndialogBackground=-1\n=42\n',
      );
      expect(result.colors.length, 2); // dialogBackground + offset slot
      expect(result.warnings, <String>[
        "unknown attheme key 'notARealKey' ignored",
        "unknown attheme key '' ignored",
      ]);
    });

    test('duplicate names: last write wins (SparseIntArray.put)', () {
      final AtthemeDecodeResult result = AtthemeCodec.decodeString(
        'dialogBackground=-1\ndialogBackground=-16777216\n',
      );
      expect(
        result.colors[TelegramColorKey.dialogBackground],
        const Color(0xFF000000),
      );
    });

    test(
      'a literal wallpaperFileOffset entry is overwritten by the parser',
      () {
        final AtthemeDecodeResult result = AtthemeCodec.decodeString(
          'wallpaperFileOffset=12345\n',
        );
        expect(
          result.colors[TelegramColorKey.wallpaperFileOffset],
          const Color(0xFFFFFFFF), // recomputed: no WPS marker -> -1 masked
        );
      },
    );

    test('WLS= captures the wallpaper link; last write wins', () {
      final AtthemeDecodeResult result = AtthemeCodec.decodeString(
        'WLS=https://first.example\n'
        'dialogBackground=-1\n'
        'WLS=https://attheme.org?slug=abc&intensity=50\n',
      );
      expect(result.wallpaperLink, 'https://attheme.org?slug=abc&intensity=50');
      // WLS lines are not name=value entries.
      expect(result.colors.length, 2);
    });
  });

  group('WPS wallpaper passthrough', () {
    // Synthetic binary payload: includes 0x0A bytes and invalid UTF-8 so
    // the passthrough must be byte-exact, never line- or text-processed.
    final Uint8List payload = Uint8List.fromList(<int>[
      0xFF, 0xD8, 0x0A, 0x00, 0xFE, 0x0A, 0x0A, 0x80, 0xC3, 0x28, 0xFF, 0xD9,
      // Android appends '\nWPE\n' after the JPEG; keep it in the synthetic
      // payload to prove it travels through opaquely.
      0x0A, 0x57, 0x50, 0x45, 0x0A,
    ]);

    test('decode surfaces the bytes after WPS verbatim', () {
      const String head =
          'dialogBackground=-1\n'
          'WLS=https://example.com/wp\n'
          'WPS\n';
      final Uint8List bytes = Uint8List.fromList(<int>[
        ...head.codeUnits, // pure ASCII
        ...payload,
      ]);
      final AtthemeDecodeResult result = AtthemeCodec.decode(bytes);

      expect(
        result.colors[TelegramColorKey.dialogBackground],
        const Color(0xFFFFFFFF),
      );
      expect(result.wallpaperLink, 'https://example.com/wp');
      expect(result.wallpaperBytes, payload);
      // The offset slot holds the byte offset just past 'WPS\n'.
      expect(
        result.colors[TelegramColorKey.wallpaperFileOffset],
        Color(head.length),
      );
      expect(result.droppedFinalLine, isFalse);
      expect(result.warnings, isEmpty);
    });

    test('encode -> decode passes wallpaper link and bytes through', () {
      final Uint8List encoded = AtthemeCodec.encode(
        <int, Color>{
          TelegramColorKey.dialogBackground: const Color(0xFF17212B),
        },
        wallpaperLink: 'https://attheme.org?slug=xyz',
        wallpaperBytes: payload,
      );
      final AtthemeDecodeResult decoded = AtthemeCodec.decode(encoded);
      expect(
        decoded.colors[TelegramColorKey.dialogBackground],
        const Color(0xFF17212B),
      );
      expect(decoded.wallpaperLink, 'https://attheme.org?slug=xyz');
      expect(decoded.wallpaperBytes, payload);
      expect(decoded.droppedFinalLine, isFalse);
      // The offset slot points past the encoded 'WPS\n' marker.
      final int payloadStart = encoded.length - payload.length;
      expect(
        decoded.colors[TelegramColorKey.wallpaperFileOffset],
        Color(payloadStart),
      );
    });

    test('everything after WPS stops parsing, even valid-looking lines', () {
      final AtthemeDecodeResult result = AtthemeCodec.decodeString(
        'dialogBackground=-1\nWPS\ndialogTextBlack=-16777216\n',
      );
      expect(
        result.colors.containsKey(TelegramColorKey.dialogTextBlack),
        isFalse,
      );
      expect(
        String.fromCharCodes(result.wallpaperBytes!),
        'dialogTextBlack=-16777216\n',
      );
    });

    test('any WPS-prefixed line triggers the marker (startsWith)', () {
      final AtthemeDecodeResult result = AtthemeCodec.decodeString(
        'WPSomething\nrest',
      );
      expect(result.wallpaperBytes, isNotNull);
      expect(String.fromCharCodes(result.wallpaperBytes!), 'rest');
      expect(result.droppedFinalLine, isFalse);
    });

    test('WPS with no trailing bytes yields an empty payload', () {
      final AtthemeDecodeResult result = AtthemeCodec.decodeString('WPS\n');
      expect(result.wallpaperBytes, isEmpty);
      expect(
        result.colors[TelegramColorKey.wallpaperFileOffset],
        const Color(0x00000004),
      );
    });
  });

  group('chunked scanner edge cases (1024-byte reads)', () {
    test('final unterminated line is silently dropped', () {
      final AtthemeDecodeResult result = AtthemeCodec.decodeString(
        'dialogBackground=-1\ndialogTextBlack=-16777216', // no trailing \n
      );
      expect(
        result.colors[TelegramColorKey.dialogBackground],
        const Color(0xFFFFFFFF),
      );
      expect(
        result.colors.containsKey(TelegramColorKey.dialogTextBlack),
        isFalse,
      );
      expect(result.droppedFinalLine, isTrue);
      expect(result.warnings.join('\n'), contains('dialogTextBlack=-16777216'));
    });

    test('a line of exactly 1024 bytes (incl. newline) is still consumed', () {
      // 'dialogBackground=' (17) + 1006 digits + '\n' = 1024 bytes. The
      // digit run overflows Integer.parseInt -> 0, but the LINE parses.
      final String line = 'dialogBackground=${'1' * 1006}\n';
      expect(line.length, 1024);
      final AtthemeDecodeResult result = AtthemeCodec.decodeString(
        '${line}dialogTextBlack=-16777216\n',
      );
      expect(
        result.colors[TelegramColorKey.dialogBackground],
        const Color(0x00000000),
      );
      expect(
        result.colors[TelegramColorKey.dialogTextBlack],
        const Color(0xFF000000),
      );
      expect(result.droppedFinalLine, isFalse);
    });

    test('a >= 1024-byte line aborts parsing and drops the rest', () {
      // Content of 1024 bytes before the newline: the terminator falls
      // outside the chunk, no line is consumed, and the scanner bails
      // (previousPosition == currentPosition) — dropping even the valid
      // lines that follow.
      final String longLine = 'dialogBackground=${'1' * 1007}\n';
      expect(longLine.length, 1025);
      final AtthemeDecodeResult result = AtthemeCodec.decodeString(
        'dialogTextBlack=-16777216\n${longLine}dialogTextLink=-1\n',
      );
      expect(
        result.colors[TelegramColorKey.dialogTextBlack],
        const Color(0xFF000000),
      );
      expect(
        result.colors.containsKey(TelegramColorKey.dialogBackground),
        isFalse,
      );
      expect(
        result.colors.containsKey(TelegramColorKey.dialogTextLink),
        isFalse,
      );
      expect(result.droppedFinalLine, isTrue);
    });

    test('lines spanning a chunk boundary are re-read whole', () {
      // 60 entries of ~20 bytes straddle the 1024-byte boundary; every one
      // must survive (the scanner repositions to the last consumed line
      // and re-reads the straddling line from its start).
      final StringBuffer source = StringBuffer();
      for (int i = 0; i < 60; i++) {
        source.write('dialogBackground=${1000000 + i}\n');
      }
      final AtthemeDecodeResult result = AtthemeCodec.decodeString(
        source.toString(),
      );
      expect(
        result.colors[TelegramColorKey.dialogBackground],
        const Color(0x000F427B), // 1000059 — last write wins
      );
      expect(result.droppedFinalLine, isFalse);
    });

    test('empty input decodes to just the offset slot', () {
      final AtthemeDecodeResult result = AtthemeCodec.decode(Uint8List(0));
      expect(_argbMap(result.colors), <int, int>{0: 0xFFFFFFFF});
      expect(result.wallpaperLink, isNull);
      expect(result.wallpaperBytes, isNull);
      expect(result.droppedFinalLine, isFalse);
      expect(result.warnings, isEmpty);
    });
  });
}
