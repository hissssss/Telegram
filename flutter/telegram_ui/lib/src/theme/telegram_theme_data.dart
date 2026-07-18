// Immutable theme snapshot: the data-model port of the Telegram Android
// color-table runtime (ARCHITECTURE.md sections 4.1-4.2).
//
// Ports (paths relative to /home/user/Telegram/TMessagesProj/src/main/):
// - java/org/telegram/ui/ActionBar/Theme.java
//     key space (`key_* = colorsCount++`, line 3364+), the `fallbackKeys`
//     table (line 4281+), and the resolution order + forced-opaque handling
//     of `getColor(int, boolean[], boolean)` (lines 9552-9618).
// - java/org/telegram/ui/ActionBar/ThemeColors.java
//     `createDefaultColors()` defaults (via the generated kDefaultColors).
// - assets/*.attheme
//     bundled sparse overlays (via the generated kBundledThemes maps);
//     'Blue' (bluebubbles.attheme) is Android's default day theme and
//     'Dark Blue' (darkblue.attheme) the default night theme
//     (Theme.java static init, lines 4612 / 4638).
//
// Resolution-order collapse for an immutable snapshot model
// ---------------------------------------------------------
// Android resolves `animatingColors -> currentColors -> fallbackKeys
// (into currentColors) -> defaultColors`. In this port a theme is an
// immutable value, so the mutable `animatingColors` transition layer has no
// per-instance analog: theme crossfades are driven by [TelegramThemeData.lerp]
// producing interpolated snapshots instead. What remains per instance is
// `currentColors` (base bundled palette merged with sparse overrides),
// `fallbackKeys` and `defaultColors`, resolved in exactly the Android order.
//
// Precompute-vs-lazy decision (documented per ARCHITECTURE.md section 4.2)
// -----------------------------------------------------------------------
// The sparse inputs are retained (so fallback behavior survives copyWith,
// section 4.1: fallbacks are never flattened at codegen time) and the dense
// 777-entry Int32List is PRECOMPUTED once per construction rather than lazily
// cached, because:
//  (a) the model is an immutable snapshot — every resolution input is frozen
//      at construction, so eager resolution can never go stale;
//  (b) construction is rare (a theme switch, or one instance per crossfade
//      tick) and costs only ~777 map lookups, while [color] is the hot path
//      called from paint / shader-uniform code every frame — precompute keeps
//      it a single branch-free typed-array read;
//  (c) a lazy cache would need a separate validity bitmask, because
//      0x00000000 is a legal resolved color (Java's zero-initialized array),
//      so no in-band sentinel exists — that adds a branch to every read and
//      mutable state to an otherwise deeply immutable object.
library;

import 'dart:ui' show Brightness, Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show ColorProperty;

import '../foundation/color_math.dart';
import '../tokens/color_scheme.g.dart';
import '../tokens/palettes/palettes.g.dart';
import '../tokens/theme_fallbacks.g.dart';
import '../tokens/theme_keys.g.dart';

/// Immutable snapshot of the full 777-key Telegram color table.
///
/// Backed by a precomputed [Int32List] so [color] is an O(1) typed-array
/// read; the sparse `currentColors` layer (base palette + overrides) is kept
/// alongside it so [copyWith] re-resolves through `kFallbackKeys` exactly
/// like `Theme.getColor` (Theme.java:9552-9618).
///
/// Equality is by [revision] — a monotonic per-construction counter — not by
/// content: two independently built, identical-looking themes are *not*
/// equal. Glass surfaces key their repaint / uniform-repack off [revision],
/// so "same revision" must guarantee "same colors", which only identity can.
class TelegramThemeData with Diagnosticable {
  /// Builds a theme from a sparse [basePalette] (raw ARGB ints, typically one
  /// of the generated bundled overlays such as `kBlueTheme`) with sparse
  /// [overrides] merged on top (the `currentColors` analog).
  ///
  /// Keys absent from both resolve through `kFallbackKeys` into the merged
  /// sparse set, then fall back to the key's own `kDefaultColors` entry —
  /// the `Theme.getColor` order.
  factory TelegramThemeData({
    Map<int, Color> overrides = const <int, Color>{},
    Map<int, int> basePalette = const <int, int>{},
  }) {
    final Map<int, int> currentColors = _merge(basePalette, overrides);
    return TelegramThemeData._(currentColors, _resolveDense(currentColors));
  }

  TelegramThemeData._(this._currentColors, this._argb, {Brightness? brightness})
    : brightness = brightness ?? _brightnessOf(_argb),
      revision = _claimRevision();

  /// The default day theme: Android's 'Blue' (bluebubbles.attheme),
  /// `currentDayTheme = defaultTheme` (Theme.java:4612).
  factory TelegramThemeData.day() => TelegramThemeData.fromBundledTheme('Blue');

  /// The default night theme: Android's 'Dark Blue' (darkblue.attheme),
  /// `currentNightTheme` (Theme.java:4638).
  factory TelegramThemeData.night() =>
      TelegramThemeData.fromBundledTheme('Dark Blue');

  /// A theme that is the generated defaults plus the given sparse
  /// [overrides] (no bundled base palette).
  factory TelegramThemeData.fromOverrides(Map<int, Color> overrides) =>
      TelegramThemeData(overrides: overrides);

  /// Builds a theme from one of the five bundled Android themes by its
  /// registration name ('Blue', 'Dark Blue', 'Arctic Blue', 'Day', 'Night' —
  /// the `kBundledThemes` keys). Throws [ArgumentError] on unknown names.
  factory TelegramThemeData.fromBundledTheme(String name) {
    final Map<int, int>? palette = kBundledThemes[name];
    if (palette == null) {
      throw ArgumentError.value(
        name,
        'name',
        'Unknown bundled theme; expected one of: ${kBundledThemes.keys.join(', ')}',
      );
    }
    return TelegramThemeData(basePalette: palette);
  }

  /// Sparse `currentColors` (base palette merged with overrides), kept so
  /// [copyWith] preserves fallback-through-sparse-override behavior.
  /// `null` marks a dense snapshot (a [lerp] product) in which every key is
  /// explicitly defined and fallbacks can never fire.
  final Map<int, int>? _currentColors;

  /// Fully resolved ARGB per key ordinal (length
  /// [TelegramColorKey.colorsCount]). Values read back Java-signed;
  /// [color] re-masks to unsigned.
  final Int32List _argb;

  /// Dark iff `perceivedBrightness(color(windowBackgroundWhite)) < 0.721`
  /// (BlurredBackgroundColorProviderThemed.java:34-37) — except on [lerp]
  /// products, where it snaps to the nearer endpoint (`t < 0.5 ? a : b`).
  final Brightness brightness;

  /// Monotonic construction counter; increments once per instance. Doubles
  /// as identity for [operator ==] / [hashCode] and as the repaint key for
  /// glass surfaces.
  final int revision;

  /// Generated typed accessor groups over [color]
  /// (e.g. `theme.colors.chat.inBubble`).
  late final TelegramColorScheme colors = TelegramColorScheme(color);

  static int _revisionCount = 0;

  static int _claimRevision() => _revisionCount++;

  /// The fully resolved color for a [TelegramColorKey] ordinal — the
  /// `Theme.getColor(int)` analog and the full-key-space escape hatch.
  ///
  /// O(1): a single typed-array read (resolution and the forced-opaque OR
  /// were applied at construction). Throws [RangeError] outside
  /// `0 <= key < TelegramColorKey.colorsCount`.
  Color color(int key) => Color(_argb[key] & 0xFFFFFFFF);

  /// Returns a new theme with [overrides] layered on top of this one.
  ///
  /// Sparse themes re-resolve through `kFallbackKeys`, so an override of a
  /// fallback *target* still propagates to keys that fall back onto it.
  /// Returns `this` unchanged (identical) when [overrides] is empty.
  TelegramThemeData copyWith({Map<int, Color> overrides = const <int, Color>{}}) {
    if (overrides.isEmpty) {
      return this;
    }
    final Map<int, int>? currentColors = _currentColors;
    if (currentColors != null) {
      final Map<int, int> merged = _merge(currentColors, overrides);
      return TelegramThemeData._(merged, _resolveDense(merged));
    }
    // Dense snapshot (lerp product): every key is defined, so fallbacks can
    // never fire — overlay directly onto a copy of the dense table.
    final Int32List argb = Int32List.fromList(_argb);
    for (final MapEntry<int, Color> entry in overrides.entries) {
      assert(
        entry.key >= 0 && entry.key < TelegramColorKey.colorsCount,
        'Color key out of range: ${entry.key}',
      );
      argb[entry.key] = entry.value.toARGB32();
    }
    _forceOpaque(argb);
    return TelegramThemeData._(null, argb);
  }

  /// Linearly interpolates two themes per key over all 777 entries with
  /// [Color.lerp] semantics; [brightness] snaps to the nearer endpoint
  /// (`t < 0.5 ? a : b`). This is the immutable-snapshot analog of Android's
  /// `animatingColors` theme-transition layer.
  ///
  /// Returns [a] / [b] themselves at (or beyond) the endpoints, preserving
  /// their [revision]s so glass surfaces do not repaint spuriously.
  static TelegramThemeData lerp(
    TelegramThemeData a,
    TelegramThemeData b,
    double t,
  ) {
    if (identical(a, b) || t <= 0.0) {
      return a;
    }
    if (t >= 1.0) {
      return b;
    }
    final Int32List argb = Int32List(TelegramColorKey.colorsCount);
    for (int key = 0; key < TelegramColorKey.colorsCount; key++) {
      argb[key] = Color.lerp(
        Color(a._argb[key] & 0xFFFFFFFF),
        Color(b._argb[key] & 0xFFFFFFFF),
        t,
      )!.toARGB32();
    }
    _forceOpaque(argb);
    return TelegramThemeData._(
      null,
      argb,
      brightness: t < 0.5 ? a.brightness : b.brightness,
    );
  }

  static Map<int, int> _merge(
    Map<int, int> basePalette,
    Map<int, Color> overrides,
  ) {
    // Always copy, so later caller-side mutation of either input map cannot
    // leak into this snapshot's copyWith re-resolution.
    final Map<int, int> merged = Map<int, int>.of(basePalette);
    for (final MapEntry<int, Color> entry in overrides.entries) {
      assert(
        entry.key >= 0 && entry.key < TelegramColorKey.colorsCount,
        'Color key out of range: ${entry.key}',
      );
      merged[entry.key] = entry.value.toARGB32();
    }
    return merged;
  }

  /// The `Theme.getColor` resolution loop, run once over the whole key space:
  /// `currentColors[key] ?? currentColors[fallbackKeys[key]] ??
  /// defaultColors[key]` — note the final default is the key's OWN default,
  /// not the fallback key's (Theme.java:9591-9610 returns
  /// `getDefaultColor(key)`).
  static Int32List _resolveDense(Map<int, int> currentColors) {
    final Int32List argb = Int32List(TelegramColorKey.colorsCount);
    for (int key = 0; key < TelegramColorKey.colorsCount; key++) {
      int? value = currentColors[key];
      if (value == null) {
        final int? fallbackKey = kFallbackKeys[key];
        if (fallbackKey != null) {
          value = currentColors[fallbackKey];
        }
        value ??= kDefaultColors[key];
      }
      argb[key] = value;
    }
    _forceOpaque(argb);
    return argb;
  }

  /// Applies `color |= 0xFF000000` to the four forced-opaque keys
  /// (Theme.java:9614: windowBackgroundWhite, windowBackgroundGray,
  /// actionBarDefault, actionBarDefaultArchived).
  ///
  /// Deliberate simplification vs Android: upstream skips the OR when the
  /// value arrived via the fallback or default branch (those `return`
  /// early). All four defaults are already opaque, and only
  /// actionBarDefaultArchived has a fallback (-> actionBarDefault, itself
  /// forced opaque), so forcing unconditionally on read is observably
  /// identical for every real theme and strictly more consistent.
  static void _forceOpaque(Int32List argb) {
    for (final int key in kForcedOpaqueKeys) {
      argb[key] |= 0xFF000000;
    }
  }

  static Brightness _brightnessOf(Int32List argb) =>
      isDarkColor(argb[TelegramColorKey.windowBackgroundWhite] & 0xFFFFFFFF)
      ? Brightness.dark
      : Brightness.light;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TelegramThemeData && other.revision == revision;
  }

  @override
  int get hashCode => revision;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<Brightness>('brightness', brightness));
    properties.add(IntProperty('revision', revision));
    properties.add(
      IntProperty(
        'sparseColorCount',
        _currentColors?.length,
        ifNull: 'dense (lerp product)',
      ),
    );
    properties.add(
      ColorProperty(
        'windowBackgroundWhite',
        color(TelegramColorKey.windowBackgroundWhite),
      ),
    );
  }
}
