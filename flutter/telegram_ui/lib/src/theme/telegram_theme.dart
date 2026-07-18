// Widget-tree plumbing for the Telegram theme runtime: the ambient theme
// scope, per-surface resource overrides, and the Material ThemeExtension
// bridge (flutter/docs/ARCHITECTURE.md section 4.2).
//
// Android equivalents being ported:
// - `Theme.getColor(int key)` global resolution + `Theme.getColor(key,
//   resourcesProvider)` per-surface resolution
//   (java/org/telegram/ui/ActionBar/Theme.java:9552-9614);
// - the `resourcesProvider` plumbing convention: a surface pushes a
//   `Theme.ResourcesProvider` (Theme.java:2949) and every descendant view
//   resolves colors through it — here [TelegramResourcesScope];
// - `NotificationCenter.didSetNewTheme`-driven invalidation, replaced by
//   Flutter dependency tracking: [TelegramTheme] is an [InheritedModel]
//   keyed by color-key ordinal, so a widget that registered interest in
//   `chat_inBubble` does not rebuild when only `actionBarDefault` changed.
library;

import 'package:flutter/material.dart';

import '../tokens/theme_keys.g.dart';
import 'telegram_resources.dart';
import 'telegram_theme_data.dart';

/// Ambient [TelegramThemeData] scope with per-color-key rebuild granularity.
///
/// An [InheritedModel] whose aspects are [TelegramColorKey] ordinals:
///
/// - [colorOf] registers a dependency on a *single* key — the widget rebuilds
///   only when that key's resolved color changes;
/// - [of] / [maybeOf] register an unconditional dependency — the widget
///   rebuilds on any theme change (use for widgets reading many keys, or the
///   [TelegramThemeData.colors] typed groups);
/// - [resources] returns the ambient [TelegramResources] view (nearest
///   [TelegramResourcesScope] override first, then the theme itself) — the
///   value every component's optional `resources` parameter defaults to.
///
/// When no [TelegramTheme] ancestor exists, lookups fall back to the Material
/// [ThemeExtension] bridge —
/// `Theme.of(context).extension<TelegramThemeExtension>()` — so a plain
/// [MaterialApp] can host the design system by installing
/// [TelegramThemeExtension] in its [ThemeData.extensions] (per-key granularity is unavailable on that path —
/// Material's [Theme] is a plain inherited widget).
///
/// ### Change-detection cost
///
/// When [data] changes, the changed-key set is computed **once** per
/// old/new pair — an O([TelegramColorKey.colorsCount]) palette walk (777
/// [Color] comparisons), memoized in a one-slot static cache which is safe
/// because the framework notifies all dependents of one element synchronously
/// with the same old widget. Each dependent then pays
/// O(min(changed, registered-aspects)) hash lookups. Two short-circuits skip
/// the walk entirely: identical [data] instances, and equal
/// [TelegramThemeData.revision] (the data model mints a new revision whenever
/// palette contents change, so equal revisions mean an identical palette).
class TelegramTheme extends InheritedModel<int> {
  /// Makes [data] the ambient theme for [child]'s subtree.
  const TelegramTheme({super.key, required this.data, required super.child});

  /// The theme exposed to this subtree.
  final TelegramThemeData data;

  /// The ambient theme, or null when neither a [TelegramTheme] ancestor nor
  /// a [TelegramThemeExtension] in the Material theme exists.
  ///
  /// Registers an unconditional dependency: the calling widget rebuilds on
  /// any theme change. Prefer [colorOf] for single-key consumers.
  static TelegramThemeData? maybeOf(BuildContext context) {
    final TelegramTheme? scope = InheritedModel.inheritFrom<TelegramTheme>(
      context,
    );
    if (scope != null) {
      return scope.data;
    }
    // ThemeExtension bridge: MaterialApp users install TelegramThemeExtension
    // in ThemeData.extensions; Theme.of registers the Material dependency so
    // extension swaps propagate.
    return Theme.of(context).extension<TelegramThemeExtension>()?.data;
  }

  /// The ambient theme. Throws a [FlutterError] when absent — see [maybeOf].
  static TelegramThemeData of(BuildContext context) {
    final TelegramThemeData? data = maybeOf(context);
    if (data == null) {
      throw FlutterError(
        'TelegramTheme.of() called with a context that has no ambient '
        'Telegram theme.\n'
        'Insert a TelegramTheme widget above this context, or install a '
        'TelegramThemeExtension in your MaterialApp ThemeData.extensions.',
      );
    }
    return data;
  }

  /// Resolves a single color key, registering a dependency on that key only.
  ///
  /// This is the granular path: after `TelegramTheme.colorOf(context,
  /// TelegramColorKey.chat_inBubble)`, the calling widget rebuilds only when
  /// `chat_inBubble`'s resolved color (or the theme's brightness) changes —
  /// not when unrelated keys change.
  ///
  /// A [TelegramResourcesScope] override wins over the theme value,
  /// mirroring `Theme.getColor(key, resourcesProvider)`
  /// (Theme.java:9552-9560). The per-key theme dependency is registered even
  /// under a scope, so theme changes flowing through a live override chain
  /// still trigger rebuilds.
  static Color colorOf(BuildContext context, int key) {
    assert(
      key >= 0 && key < TelegramColorKey.colorsCount,
      'Color key $key is outside 0..${TelegramColorKey.colorsCount - 1}.',
    );
    final TelegramTheme? scope = InheritedModel.inheritFrom<TelegramTheme>(
      context,
      aspect: key,
    );
    final TelegramResources? scoped = TelegramResourcesScope.maybeOf(context);
    if (scoped != null) {
      return scoped.getColor(key);
    }
    if (scope != null) {
      return scope.data.color(key);
    }
    return of(context).color(key);
  }

  /// The ambient [TelegramResources] view — what every component's optional
  /// `resources` constructor parameter defaults to (the Java
  /// `resourcesProvider` convention).
  ///
  /// Resolution order:
  ///
  /// 1. the nearest [TelegramResourcesScope]'s resources (per-surface
  ///    override wins, as in `Theme.getColor(key, resourcesProvider)`);
  /// 2. otherwise a view over [of]\(context) whose [TelegramResources.isDark]
  ///    is the theme's [TelegramThemeData.brightness] (the
  ///    `ResourcesProvider.isDark()` default delegates to
  ///    `Theme.isCurrentThemeDark()`, Theme.java:2974-2978).
  ///
  /// Registers a whole-scope dependency (scope widget or full theme):
  /// callers rebuild on any change. Use [colorOf] when per-key granularity
  /// matters.
  static TelegramResources resources(BuildContext context) {
    final TelegramResources? scoped = TelegramResourcesScope.maybeOf(context);
    if (scoped != null) {
      return scoped;
    }
    return _ThemeDataResources(of(context));
  }

  @override
  bool updateShouldNotify(TelegramTheme oldWidget) {
    final TelegramThemeData oldData = oldWidget.data;
    if (identical(data, oldData)) {
      return false;
    }
    // Revision short-circuit: the data model guarantees palette changes mint
    // a new revision, so equal revisions (and brightness) mean no visible
    // change.
    return data.revision != oldData.revision ||
        data.brightness != oldData.brightness;
  }

  @override
  bool updateShouldNotifyDependent(
    TelegramTheme oldWidget,
    Set<int> dependencies,
  ) {
    final TelegramThemeData oldData = oldWidget.data;
    if (identical(data, oldData)) {
      return false;
    }
    if (data.brightness != oldData.brightness) {
      // Theme identity flip (day/night): notify everyone — dark-classification
      // reads (TelegramResources.isDark) are not keyed by color aspect.
      return true;
    }
    if (data.revision == oldData.revision) {
      return false;
    }
    final Set<int> changed = _changedKeys(oldData, data);
    // Probe the smaller set against the larger one.
    if (changed.length < dependencies.length) {
      for (final int key in changed) {
        if (dependencies.contains(key)) {
          return true;
        }
      }
      return false;
    }
    for (final int key in dependencies) {
      if (changed.contains(key)) {
        return true;
      }
    }
    return false;
  }

  // One-slot memo for the palette diff. Safe as a static: notifyClients
  // delivers all dependents of one element synchronously against a single
  // (old, new) widget pair, so within one notification pass the slot always
  // hits; interleaved passes from nested TelegramThemes only cost a
  // recompute. Holds the last two data instances — cleared implicitly on the
  // next theme change.
  static TelegramThemeData? _diffOld;
  static TelegramThemeData? _diffNew;
  static Set<int>? _diffKeys;

  /// Keys whose resolved color differs between [oldData] and [newData]:
  /// one O(colorsCount) walk per pair, memoized.
  static Set<int> _changedKeys(
    TelegramThemeData oldData,
    TelegramThemeData newData,
  ) {
    if (identical(_diffOld, oldData) && identical(_diffNew, newData)) {
      return _diffKeys!;
    }
    final Set<int> changed = <int>{};
    for (int key = 0; key < TelegramColorKey.colorsCount; key++) {
      if (oldData.color(key) != newData.color(key)) {
        changed.add(key);
      }
    }
    _diffOld = oldData;
    _diffNew = newData;
    _diffKeys = changed;
    return changed;
  }
}

/// Pushes a per-surface [TelegramResources] override for a subtree — the
/// per-chat-theme shape (`ChatActivity.ThemeDelegate` handed down as
/// `resourcesProvider`, ChatActivity.java:42996+).
///
/// Descendants reading colors through [TelegramTheme.resources] (or
/// [TelegramTheme.colorOf]) see [resources] instead of the raw theme.
/// Typical usage stacks a sparse `ResourcesOverride` over the ambient theme:
///
/// ```dart
/// Builder(builder: (context) {
///   return TelegramResourcesScope(
///     resources: ResourcesOverride(
///       parent: TelegramTheme.resources(context),
///       overrides: {TelegramColorKey.chat_inBubble: myBubbleColor},
///     ),
///     child: chatSubtree,
///   );
/// })
/// ```
///
/// Because the `Builder` above depends on the enclosing [TelegramTheme], a
/// theme change rebuilds it, constructs a fresh override chain, and
/// [updateShouldNotify] (identity `!=` unless the resources type defines
/// equality) notifies the subtree — the override stays live over the theme.
/// Cache the [TelegramResources] instance (const, field, or memoized) when
/// the scope's builder rebuilds for unrelated reasons and spurious
/// notifications matter.
class TelegramResourcesScope extends InheritedWidget {
  /// Makes [resources] the ambient resources for [child]'s subtree.
  const TelegramResourcesScope({
    super.key,
    required this.resources,
    required super.child,
  });

  /// The resources exposed to this subtree.
  final TelegramResources resources;

  /// The nearest enclosing scope's resources, or null. Registers a
  /// dependency on the scope.
  static TelegramResources? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TelegramResourcesScope>()
      ?.resources;

  /// The nearest enclosing scope's resources. Throws a [FlutterError] when
  /// no [TelegramResourcesScope] ancestor exists; prefer
  /// [TelegramTheme.resources] for the theme-backed default.
  static TelegramResources of(BuildContext context) {
    final TelegramResources? resources = maybeOf(context);
    if (resources == null) {
      throw FlutterError(
        'TelegramResourcesScope.of() called with a context that has no '
        'TelegramResourcesScope ancestor.\n'
        'Use TelegramTheme.resources(context) to fall back to the ambient '
        'theme when no per-surface override is installed.',
      );
    }
    return resources;
  }

  @override
  bool updateShouldNotify(TelegramResourcesScope oldWidget) =>
      resources != oldWidget.resources;
}

/// Bridges [TelegramThemeData] into Material's [ThemeExtension] mechanism so
/// a plain [MaterialApp] can host the Telegram design system:
///
/// ```dart
/// MaterialApp(
///   theme: ThemeData(
///     extensions: [TelegramThemeExtension(TelegramThemeData.day())],
///   ),
/// )
/// ```
///
/// [TelegramTheme.of]/[TelegramTheme.maybeOf]/[TelegramTheme.colorOf] fall
/// back to this extension when no [TelegramTheme] ancestor exists. [lerp]
/// delegates to [TelegramThemeData.lerp], so Material theme animations
/// crossfade the full 777-key palette exactly like the Android theme
/// transition.
class TelegramThemeExtension extends ThemeExtension<TelegramThemeExtension> {
  /// Wraps [data] for installation in [ThemeData.extensions].
  const TelegramThemeExtension(this.data);

  /// The wrapped theme.
  final TelegramThemeData data;

  @override
  TelegramThemeExtension copyWith({TelegramThemeData? data}) =>
      TelegramThemeExtension(data ?? this.data);

  @override
  TelegramThemeExtension lerp(
    ThemeExtension<TelegramThemeExtension>? other,
    double t,
  ) {
    if (other is! TelegramThemeExtension) {
      return this;
    }
    return TelegramThemeExtension(TelegramThemeData.lerp(data, other.data, t));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TelegramThemeExtension && other.data == data;

  @override
  int get hashCode => data.hashCode;
}

/// [TelegramResources] view over a [TelegramThemeData] — what
/// [TelegramTheme.resources] returns when no [TelegramResourcesScope]
/// overrides the subtree.
class _ThemeDataResources extends TelegramResources {
  const _ThemeDataResources(this.data);

  final TelegramThemeData data;

  @override
  Color getColor(int key) => data.color(key);

  /// The theme's own brightness is authoritative here — the
  /// `ResourcesProvider.isDark()` default delegates to
  /// `Theme.isCurrentThemeDark()` (Theme.java:2974-2978) rather than
  /// recomputing perceived brightness.
  @override
  bool get isDark => data.brightness == Brightness.dark;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ThemeDataResources && identical(other.data, data);

  @override
  int get hashCode => identityHashCode(data);
}
