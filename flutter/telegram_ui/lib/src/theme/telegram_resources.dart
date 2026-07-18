// Port of `Theme.ResourcesProvider`
// (java/org/telegram/ui/ActionBar/Theme.java:2949-2988).
//
// On Android every themed view resolves its colors through a
// `ResourcesProvider` — an interface with a single required method
// `int getColor(int key)` plus defaulted helpers — so that a surface (a chat
// with a per-chat theme, a preview cell, a photo-viewer overlay) can swap the
// palette for its own subtree without touching the global theme.
// [TelegramResources] is the Dart analog: the one required member is
// [getColor]; [isDark] mirrors the interface's defaulted `isDark()` which
// classifies the ambient palette by the perceived brightness of its window
// background (BlurredBackgroundColorProviderThemed.java:34-37 uses the same
// `computePerceivedBrightness(...) < 0.721` predicate for glass surfaces).
//
// The drawable/paint/service-shader members of the Java interface are Android
// rendering details and are intentionally not ported.
library;

import 'dart:ui' show Color;

import '../foundation/color_math.dart';
import '../tokens/theme_keys.g.dart';

/// A per-surface color resolver — the `Theme.ResourcesProvider` analog
/// (Theme.java:2949).
///
/// Implementations resolve a [TelegramColorKey] ordinal into a themed
/// [Color]. Everything in the component catalog reads colors through this
/// interface (each component takes an optional `TelegramResources? resources`
/// parameter that wins over the ambient scope, mirroring the Java
/// `resourcesProvider` convention), so substituting a sparse override for a
/// subtree — a per-chat theme, for example — is a matter of supplying a
/// different instance.
///
/// Extend (rather than implement) this class to inherit the default [isDark].
abstract class TelegramResources {
  /// Enables const constructors in subclasses.
  const TelegramResources();

  /// Resolves [key] (a [TelegramColorKey] ordinal, `0 ..
  /// TelegramColorKey.colorsCount - 1`) into a themed color.
  Color getColor(int key);

  /// Whether this palette counts as dark.
  ///
  /// Default implementation mirrors the defaulted `ResourcesProvider.isDark()`
  /// contract: the palette is dark when the perceived brightness of its
  /// resolved window background is below the dark-theme threshold —
  /// `computePerceivedBrightness(getColor(windowBackgroundWhite)) < 0.721`
  /// (AndroidUtilities.java:4973-4975 for the Rec. 709 brightness;
  /// BlurredBackgroundColorProviderThemed.java:34-37 for the threshold).
  ///
  /// Because it goes through the virtual [getColor], the default stays
  /// correct for sparse overrides: overriding `windowBackgroundWhite`
  /// re-classifies the surface.
  bool get isDark =>
      isDarkColor(getColor(TelegramColorKey.windowBackgroundWhite).toARGB32());
}
