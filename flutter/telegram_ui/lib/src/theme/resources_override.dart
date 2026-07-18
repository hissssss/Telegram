// Sparse per-surface theme override — the shape of ChatActivity's per-chat
// `ThemeDelegate.getColor`
// (java/org/telegram/ui/ChatActivity.java:43041-43064).
//
// On Android a per-chat theme is a `Theme.ResourcesProvider` holding a sparse
// `SparseIntArray currentColors`; its `getColor(key)` resolves:
//
//   1. `currentColors[key]`                        — direct override hit;
//   2. `currentColors[Theme.getFallbackKey(key)]`  — the override map
//      consulted *through the fallback table*, so overriding a fallback
//      target (e.g. `featuredStickers_addButtonPressed`) also recolors every
//      key that falls back to it (e.g. `chat_inQuote`);
//   3. `Theme.getColor(key)`                       — everything else
//      delegates to the ambient theme.
//
// [ResourcesOverride] ports that resolution order verbatim, with the ambient
// theme generalized to any parent [TelegramResources].
library;

import 'dart:ui' show Color;

import '../tokens/theme_fallbacks.g.dart';
import 'telegram_resources.dart';

/// A sparse per-surface delta over a parent [TelegramResources]
/// (the per-chat-theme `ThemeDelegate` shape, ChatActivity.java:43041-43064).
///
/// Keys present in [overrides] (directly, or via one hop through the
/// [kFallbackKeys] table) resolve to the override color; every other key
/// delegates to [parent]. Because the miss path calls `parent.getColor`
/// at lookup time — the override is never flattened into a full palette —
/// **fallback resolution stays live through the parent**: a key absent from
/// both this override and the parent's own sparse layer still walks the
/// parent's full `fallbackKeys -> defaults` chain, and a later change to the
/// parent is observed immediately by every override stacked on top of it.
///
/// [isDark] is inherited from [TelegramResources] and resolves through
/// [getColor], so an override of `windowBackgroundWhite` re-classifies the
/// surface's brightness.
class ResourcesOverride extends TelegramResources {
  /// Creates a sparse override of [parent].
  ///
  /// [overrides] maps [TelegramColorKey] ordinals to replacement colors. The
  /// map is not copied; treat it as immutable after construction.
  const ResourcesOverride({required this.parent, required this.overrides});

  /// The resources this override delegates to on a miss.
  final TelegramResources parent;

  /// Sparse replacement colors, keyed by [TelegramColorKey] ordinal.
  final Map<int, Color> overrides;

  @override
  Color getColor(int key) {
    // 1. Direct override hit (currentColors.indexOfKey(key) >= 0).
    final Color? direct = overrides[key];
    if (direct != null) {
      return direct;
    }
    // 2. Override hit through the fallback table
    //    (currentColors[Theme.getFallbackKey(key)]).
    final int? fallbackKey = kFallbackKeys[key];
    if (fallbackKey != null) {
      final Color? viaFallback = overrides[fallbackKey];
      if (viaFallback != null) {
        return viaFallback;
      }
    }
    // 3. Delegate to the ambient theme (Theme.getColor(key)) — the parent
    //    applies its own fallback/default resolution at lookup time.
    return parent.getColor(key);
  }
}
