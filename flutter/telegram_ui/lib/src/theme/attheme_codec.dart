// `.attheme` decode/encode with Android-exact semantics
// (ARCHITECTURE.md section 4.4).
//
// Ports (paths relative to /home/user/Telegram/TMessagesProj/src/main/):
// - java/org/telegram/ui/ActionBar/Theme.java
//     `getThemeFileValues(File, String, String[])` (line 8135): the
//     1024-byte chunked line scanner, `WLS=` wallpaper-link capture, the
//     `WPS` stop marker + wallpaper byte offset, `#hex` vs decimal value
//     parsing, unknown-name tolerance, and the final
//     `stringMap.put(key_wallpaperFileOffset, offset)` overwrite; plus the
//     `saveCurrentTheme` writer (line ~7340: `name=value\n` lines with
//     signed-decimal Java ints, `WLS=<link>\n`, `WPS\n` + wallpaper bytes).
// - java/org/telegram/messenger/Utilities.java
//     `parseInt(CharSequence)` (line 157, the non-Windows branch) including
//     its off-by-one quirk (see [_utilitiesParseInt]).
// - android.graphics.Color.parseColor for `#RRGGBB` / `#AARRGGBB` strings
//     (`#RRGGBB` gets an implicit FF alpha).
//
// The same semantics are independently implemented in Python by
// flutter/tool/gen_tokens.py (Pass 4), which generates the checked-in
// palettes under lib/src/tokens/palettes/. The Dart decoder mirrors the
// Python one 1:1 — test/theme/attheme_codec_test.dart asserts byte-for-byte
// color parity between the two parsers over all five bundled assets.
//
// Quirks replicated on purpose (all present in the Java scanner):
// - Only `\n`-terminated lines inside a 1024-byte chunk are consumed; after
//   each chunk the stream is repositioned to the end of the last consumed
//   line. Hence a final line with no trailing `\n` is silently dropped
//   (true for day.attheme and arctic.attheme on Android), and a single
//   line whose content reaches 1024 bytes aborts parsing entirely
//   (`previousPosition == currentPosition` bailout).
// - A `WPS`-prefixed line stops parsing; every byte after that line is
//   opaque wallpaper payload, surfaced verbatim and never interpreted.
// - The wallpaperFileOffset slot (key ordinal 0) is always overwritten with
//   the computed byte offset (-1 when there is no `WPS` marker), even when
//   the file carries a literal `wallpaperFileOffset=` entry.
// - Unknown serialized names are ignored (`ThemeColors.stringKeyToInt` == -1
//   tolerance) — collected here as warnings, never errors.
library;

import 'dart:convert' show utf8;
import 'dart:typed_data';
import 'dart:ui' show Color;

import '../tokens/theme_key_names.g.dart';
import '../tokens/theme_keys.g.dart';

/// The result of [AtthemeCodec.decode]: a sparse color overlay plus the
/// wallpaper passthrough data and parse diagnostics.
class AtthemeDecodeResult {
  /// Creates a decode result; instances are normally produced by
  /// [AtthemeCodec.decode].
  AtthemeDecodeResult({
    required this.colors,
    required this.wallpaperLink,
    required this.wallpaperBytes,
    required this.warnings,
    required this.droppedFinalLine,
  });

  /// Sparse key-ordinal -> color overlay, exactly the `SparseIntArray`
  /// Android builds: last write wins for duplicate names, and the
  /// [TelegramColorKey.wallpaperFileOffset] slot (ordinal 0) always holds
  /// the wallpaper byte offset re-interpreted as an ARGB int
  /// (`Color(0xFFFFFFFF)` — Java `-1` — when the file has no `WPS` marker).
  /// It is positional metadata, not a color.
  final Map<int, Color> colors;

  /// The payload of the last `WLS=` line, or null if none was present
  /// (Android overwrites `wallpaperLink[0]` per line: last write wins).
  final String? wallpaperLink;

  /// Every byte after the `WPS` marker line, verbatim and uninterpreted
  /// (opaque passthrough per ARCHITECTURE.md section 1 non-goals), or null
  /// when the file has no `WPS` marker. Android writes a JPEG followed by a
  /// `\nWPE\n` trailer here; both travel through this field untouched.
  final Uint8List? wallpaperBytes;

  /// Parse diagnostics: one entry per unknown serialized name (ignored, as
  /// on Android) and one for dropped unconsumed trailing bytes.
  final List<String> warnings;

  /// True when trailing bytes were silently discarded by the Android
  /// scanner semantics — a final line with no terminating `\n` (the
  /// day.attheme / arctic.attheme case) or a >= 1024-byte line bailing out
  /// mid-file. Always false when [wallpaperBytes] is non-null (the `WPS`
  /// branch consumes everything).
  final bool droppedFinalLine;
}

/// Codec for the Telegram `.attheme` theme-file format, faithful to
/// `Theme.getThemeFileValues` (decode) and `Theme.saveCurrentTheme`
/// (encode); see the library docs for the exact quirks replicated.
abstract final class AtthemeCodec {
  /// Decodes [bytes] with Android-exact `Theme.getThemeFileValues`
  /// semantics. Never throws on malformed input: bad values parse to 0,
  /// unknown names become [AtthemeDecodeResult.warnings], unterminated
  /// trailing lines are dropped (flagged via
  /// [AtthemeDecodeResult.droppedFinalLine]).
  static AtthemeDecodeResult decode(Uint8List bytes) {
    final Map<int, Color> colors = <int, Color>{};
    final List<String> warnings = <String>[];
    String? wallpaperLink;
    int wallpaperFileOffset = -1;
    int currentPosition = 0;
    bool finished = false;
    // Port of the `while ((read = stream.read(bytes)) != -1)` chunk loop.
    while (true) {
      final int chunkStart = currentPosition;
      final int remaining = bytes.length - chunkStart;
      if (remaining <= 0) {
        break; // stream.read() == -1
      }
      final int read = remaining < 1024 ? remaining : 1024;
      final int previousPosition = currentPosition;
      int start = 0;
      for (int a = 0; a < read; a++) {
        if (bytes[chunkStart + a] != 0x0A) {
          continue;
        }
        final int len = a - start + 1;
        // new String(bytes, start, len - 1) — Android default charset is
        // UTF-8; malformed sequences become U+FFFD, as in Java.
        final String line = utf8.decode(
          Uint8List.sublistView(
            bytes,
            chunkStart + start,
            chunkStart + start + len - 1,
          ),
          allowMalformed: true,
        );
        if (line.startsWith('WLS=')) {
          wallpaperLink = line.substring(4);
        } else if (line.startsWith('WPS')) {
          // currentPosition is still the absolute start of this line, so
          // the offset points just past the WPS line's newline.
          wallpaperFileOffset = currentPosition + len;
          finished = true;
          break;
        } else {
          final int idx = line.indexOf('=');
          if (idx != -1) {
            final String name = line.substring(0, idx);
            final String param = line.substring(idx + 1);
            final int value = _parseColorValue(param);
            final int? key = kAttThemeNames[name];
            if (key != null) {
              // ThemeColors.stringKeyToInt >= 0: store (last write wins,
              // SparseIntArray.put). Mask the Java signed int to ARGB.
              colors[key] = Color(value & 0xFFFFFFFF);
            } else {
              warnings.add("unknown attheme key '$name' ignored");
            }
          }
        }
        start += len;
        currentPosition += len;
      }
      if (previousPosition == currentPosition) {
        // No line consumed from this chunk: either only an unterminated
        // tail remains, or a single line spans >= 1024 bytes. Bail out.
        break;
      }
      if (finished) {
        break;
      }
    }
    // stringMap.put(key_wallpaperFileOffset, wallpaperFileOffset) — always,
    // overwriting any literal `wallpaperFileOffset=` entry.
    colors[TelegramColorKey.wallpaperFileOffset] = Color(
      wallpaperFileOffset & 0xFFFFFFFF,
    );
    Uint8List? wallpaperBytes;
    bool droppedFinalLine = false;
    if (finished) {
      wallpaperBytes = Uint8List.fromList(
        Uint8List.sublistView(bytes, wallpaperFileOffset),
      );
    } else if (currentPosition < bytes.length) {
      droppedFinalLine = true;
      final Uint8List tail = Uint8List.sublistView(bytes, currentPosition);
      String preview = utf8.decode(tail, allowMalformed: true);
      if (preview.length > 100) {
        preview = '${preview.substring(0, 100)}…';
      }
      warnings.add(
        'dropped ${tail.length} unconsumed trailing byte(s) for Android '
        "parity (final line unterminated, or a >= 1024-byte line): '$preview'",
      );
    }
    return AtthemeDecodeResult(
      colors: colors,
      wallpaperLink: wallpaperLink,
      wallpaperBytes: wallpaperBytes,
      warnings: warnings,
      droppedFinalLine: droppedFinalLine,
    );
  }

  /// Convenience wrapper over [decode] for text sources: parses the UTF-8
  /// encoding of [source]. Note that `.attheme` is a byte format — a file
  /// with a wallpaper payload must go through [decode] so the bytes after
  /// `WPS` survive untouched.
  static AtthemeDecodeResult decodeString(String source) =>
      decode(Uint8List.fromList(utf8.encode(source)));

  /// Encodes a sparse color overlay to Android-compatible `.attheme` bytes:
  /// one `name=value\n` line per entry in ascending key-ordinal order (the
  /// `SparseIntArray` iteration order of `Theme.saveCurrentTheme`), values
  /// as signed 32-bit Java decimals (`0xFFFFFFFF` -> `-1`), then
  /// `WLS=<wallpaperLink>\n` when given, then a `WPS\n` marker followed by
  /// [wallpaperBytes] verbatim when given. Every line is `\n`-terminated,
  /// so `decode(encode(...))` never drops entries — this is the decoder's
  /// round-trip oracle.
  ///
  /// Deliberate divergences from `saveCurrentTheme`, both safe because the
  /// decoder recomputes / ignores them:
  /// - the [TelegramColorKey.wallpaperFileOffset] entry (ordinal 0) is
  ///   skipped, not serialized: it is positional metadata that [decode]
  ///   always overwrites (Android serializes the stale value and likewise
  ///   overwrites it on load);
  /// - no `\nWPE\n` trailer is appended after [wallpaperBytes]: the bytes
  ///   are opaque passthrough, and a payload captured by [decode] already
  ///   contains whatever trailer the source file had.
  ///
  /// Throws [ArgumentError] for key ordinals outside the 777-key space or
  /// without a `createColorKeysMap()` name (Android's
  /// `ThemeColors.getStringName` returns null for those and would emit an
  /// unloadable `null=...` line; failing fast is the safer port).
  static Uint8List encode(
    Map<int, Color> colors, {
    String? wallpaperLink,
    Uint8List? wallpaperBytes,
  }) {
    final StringBuffer buffer = StringBuffer();
    final List<int> keys = colors.keys.toList()..sort();
    for (final int key in keys) {
      if (key < 0 || key >= TelegramColorKey.colorsCount) {
        throw ArgumentError.value(
          key,
          'colors',
          'Color key ordinal out of range '
              '(0 <= key < ${TelegramColorKey.colorsCount})',
        );
      }
      if (key == TelegramColorKey.wallpaperFileOffset) {
        continue; // Parser-computed positional metadata; never serialized.
      }
      final String? name = kColorKeyNames[key];
      if (name == null) {
        throw ArgumentError.value(
          key,
          'colors',
          'Key ordinal has no createColorKeysMap() name and cannot appear '
              'in an .attheme file',
        );
      }
      final int argb = colors[key]!.toARGB32();
      // Java writes the int as a signed decimal (-1 for 0xFFFFFFFF).
      final int signed = argb >= 0x80000000 ? argb - 0x100000000 : argb;
      buffer.write('$name=$signed\n');
    }
    if (wallpaperLink != null) {
      buffer.write('WLS=$wallpaperLink\n');
    }
    if (wallpaperBytes == null) {
      return Uint8List.fromList(utf8.encode(buffer.toString()));
    }
    buffer.write('WPS\n');
    final BytesBuilder builder = BytesBuilder(copy: false)
      ..add(utf8.encode(buffer.toString()))
      ..add(wallpaperBytes);
    return builder.toBytes();
  }
}

/// `Theme.getThemeFileValues` value parsing: `#`-prefixed strings go
/// through `Color.parseColor` with `Utilities.parseInt` as the
/// exception fallback; everything else goes straight to
/// `Utilities.parseInt`. Returns the Java signed 32-bit int; the caller
/// masks to unsigned ARGB when storing.
int _parseColorValue(String param) {
  if (param.startsWith('#')) {
    try {
      return _javaColorParseColor(param);
    } on FormatException {
      return _utilitiesParseInt(param);
    }
  }
  return _utilitiesParseInt(param);
}

/// `android.graphics.Color.parseColor` for `#`-prefixed strings:
/// `Long.parseLong(s.substring(1), 16)`, then `#RRGGBB` (length 7) gets an
/// implicit FF alpha, any length other than 9 throws (routed by
/// [_parseColorValue] to the `Utilities.parseInt` fallback, as in
/// Theme.java), and the `(int)` cast truncates to a signed 32-bit value.
int _javaColorParseColor(String s) {
  final String body = s.substring(1);
  // Long.parseLong(body, 16): optional sign + hex digits, else throws.
  if (!RegExp(r'^[+-]?[0-9a-fA-F]+$').hasMatch(body) || body.length > 16) {
    throw FormatException('unparseable color', s);
  }
  // May itself throw FormatException on > 2^63-1, matching Long.parseLong's
  // overflow NumberFormatException.
  int color = int.parse(body, radix: 16);
  if (s.length == 7) {
    color |= 0xFF000000;
  } else if (s.length != 9) {
    throw FormatException('unknown color length', s);
  }
  // (int) cast: truncate to a signed 32-bit view.
  color &= 0xFFFFFFFF;
  return color >= 0x80000000 ? color - 0x100000000 : color;
}

/// `Integer.parseInt`: optional sign + decimal digits, signed 32-bit range,
/// throws [FormatException] otherwise (the NumberFormatException analog).
int _javaIntegerParseInt(String s) {
  if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(s)) {
    throw FormatException('NumberFormatException', s);
  }
  final int v = int.parse(s); // Throws on > 64-bit, matching the range gate.
  if (v < -2147483648 || v > 2147483647) {
    throw FormatException('NumberFormatException (overflow)', s);
  }
  return v;
}

/// Faithful port of `Utilities.parseInt(CharSequence)` — the non-Windows
/// branch (Utilities.java:157-189).
///
/// Scans for the first run of allowed chars (`-` or `0-9`). Quirk kept on
/// purpose: when a disallowed char terminates a started run, Java does
/// `end++` before breaking, so the offending char is INCLUDED in the parsed
/// substring, `Integer.parseInt` throws, and the catch returns 0 (e.g.
/// `"500x"` -> 0, not 500 — but `"x500"` -> 500, because the run then ends
/// at the end of input). Clean values like `"-1"` parse exactly.
int _utilitiesParseInt(String value) {
  int val = 0;
  int start = -1;
  int end = 0;
  final int n = value.length;
  while (end < n) {
    final int ch = value.codeUnitAt(end);
    final bool allowed = ch == 0x2D /* - */ || (ch >= 0x30 && ch <= 0x39);
    if (allowed && start < 0) {
      start = end;
    } else if (!allowed && start >= 0) {
      end++;
      break;
    }
    end++;
  }
  if (start >= 0) {
    try {
      val = _javaIntegerParseInt(value.substring(start, end));
    } on FormatException {
      val = 0;
    }
  }
  return val;
}
