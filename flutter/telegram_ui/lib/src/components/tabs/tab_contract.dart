// The minimal contract between the tab-bar container
// (`tabs/glass_tab_bar.dart`, port of `ui/MainTabsLayout.java`) and the tab
// slot widgets rendered inside it (`tabs/glass_tab.dart`, port of
// `ui/Components/glass/GlassTabView.java`).
//
// The bar owns layout, gestures, and selection state; a slot is a pure
// visual cell built from this data. Keeping the contract to one tiny value
// type lets both sides compile and evolve independently — the bar renders
// slots through a builder (`GlassTabSlotBuilder`) that receives a
// [TabSlotData], and any widget can implement the slot side.
library;

import 'package:flutter/animation.dart' show Animation;
import 'package:flutter/foundation.dart' show immutable;

/// Everything the tab bar tells one tab slot per frame — the Dart analog of
/// the calls `MainTabsLayout` makes into its `GlassTabView` children:
/// `setSelected` (MainTabsLayout.java:258-265), `setTextSizeDp`
/// (MainTabsLayout.java:213-221 via the `Tab` interface, GlassTabView.java:532),
/// and `setSkipDrawSelector` (MainTabsLayout.java:286-302).
@immutable
class TabSlotData {
  /// Creates slot data. The bar constructs one per tab per build.
  const TabSlotData({
    required this.label,
    required this.selected,
    required this.animation,
    this.badgeCount = 0,
    this.textSize = 12.0,
    this.skipSelector = false,
  });

  /// The single-line tab label (GlassTabView.java:88-96).
  final String label;

  /// Whether this slot is the (visually) selected tab —
  /// `GlassTabView.isTabSelected()` state driven by
  /// `MainTabsLayout.setTabSelected` (MainTabsLayout.java:258-265).
  final bool selected;

  /// The bar-driven selection factor, 0 (unselected) to 1 (selected),
  /// animated over 320ms with the Android decelerate interpolator —
  /// the `isSelectedAnimator` timing of the tab (GlassTabView.java:67).
  /// Slots that run their own selection animator (as `GlassTab` does,
  /// mirroring the Java ownership) may ignore it.
  final Animation<double> animation;

  /// Unread counter for the slot's badge; 0 hides the badge
  /// (GlassTabView.java:98-103, ported by `counter_badge.dart`).
  final int badgeCount;

  /// Label text size in logical px chosen by the bar's auto-fit passes —
  /// one of {12, 12, 10} (MainTabsLayout.java:46, applied via
  /// `setTextSizeDp`, GlassTabView.java:532-539).
  final double textSize;

  /// True while the bar draws the long-press "lens" selector itself, so the
  /// slot must suppress its own selection pill — `setSkipDrawSelector`
  /// (MainTabsLayout.java:286-302; GlassTabView.java:143-148).
  final bool skipSelector;

  @override
  String toString() =>
      'TabSlotData("$label", selected: $selected, badge: $badgeCount, '
      'textSize: $textSize, skipSelector: $skipSelector)';
}
