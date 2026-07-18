// The page scaffold of the glass design system
// (ARCHITECTURE.md section 6, row "TgScaffold"; widget tree of section 3.2).
//
// Android has no single scaffold class — this widget ports the page
// composition that `MainTabsActivity` + `DialogsActivity` (and the other
// main-tab hosts) assemble by hand:
//
//  * one shared blur source per page
//    (`BlurredBackgroundDrawableViewFactory`, MainTabsActivity.java:342-348)
//    — here [GlassBackdropScope], mounted exactly once per page;
//  * content laid out full-bleed behind the floating bars
//    (`contentView.addView(chatListView, MATCH_PARENT)` with the bars added
//    on top, ChatActivity.java:6911-6918), with scrollables padded instead of
//    resized — the `extendBodyBehindBars` layout;
//  * a bottom content inset of `navigationBarHeight +
//    MAIN_TABS_HEIGHT_WITH_MARGINS` (= 56 + 8*2 = 72dp)
//    (`additionNavigationBarHeight = hasMainTabs ?
//    dp(MAIN_TABS_HEIGHT_WITH_MARGINS) : 0`, DialogsActivity.java:2978;
//    constants DialogsActivity.java:289-291), injected here into the body's
//    `MediaQuery.padding.bottom`;
//  * a top content inset of the app bar's extent (status bar + bar height —
//    Android offsets scrollables by `ActionBar.getCurrentActionBarHeight() +
//    statusBarHeight`), injected into `MediaQuery.padding.top`;
//  * the blurred edge fade behind the bottom bar: a full-width view of
//    height `navigationBarHeight + dp(MAIN_TABS_HEIGHT_WITH_MARGINS)`
//    anchored to the bottom (MainTabsActivity.java:350-355, 804-809) whose
//    background is `BlurredBackgroundWithFadeDrawable` at
//    `setFadeHeight(dp(60), true)` (MainTabsActivity.java:352) over a
//    color-provider-less blur drawable (`iBlur3FactoryFade.create(fadeView,
//    null)`, MainTabsActivity.java:351) — here [GlassEdgeFade.mainTabs] over
//    an un-tinted [FrostedPanel];
//  * the mirrored fade behind a top panel: the fade drawable's default
//    `dp(40)` height with `opacity == false`
//    (BlurredBackgroundWithFadeDrawable.java:58) and a *negative* fade
//    height anchoring the ramp to the bottom of the top zone
//    (`fadeDrawableTop.setFadeHeight(-height, ...)` +
//    `setBounds(0, 0, width, fadeZoneTop)`, ChatActivityFadeView.java:47-48,
//    54-60, 95-99) — here [GlassFadeDirection.up].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../glass/backdrop_scope.dart';
import '../../glass/glass_fade.dart';
import '../../glass/glass_panel.dart';
import '../../glass/runtime_probe.dart';
import '../../glass/strategy.dart';
import '../../glass/surface_colors.dart';
import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';
import '../tabs/glass_tab_bar.dart' show kGlassTabBarHeightWithMargins;

/// The bottom content inset reserved for the floating tab bar, excluding the
/// navigation-bar safe area: `MAIN_TABS_HEIGHT_WITH_MARGINS` = 56 + 8*2 =
/// 72dp (DialogsActivity.java:289-291). The full injected inset is
/// `MediaQuery.padding.bottom + kTgScaffoldTabBarInset`
/// (DialogsActivity.java:2978; MainTabsActivity.java:805).
const double kTgScaffoldTabBarInset = kGlassTabBarHeightWithMargins;

/// The blur surface under both edge fades: `iBlur3FactoryFade.create(
/// fadeView, null)` passes a **null color provider**
/// (MainTabsActivity.java:351), so the drawable has no tint, strokes, or
/// shadow (`BlurredBackgroundDrawable.setColorProvider`,
/// BlurredBackgroundDrawable.java:203) — a pure blurred backdrop.
const GlassSurfaceStyle _fadeSurfaceStyle = GlassSurfaceStyle();

/// The Telegram page scaffold: full-bleed [body] behind a floating bottom
/// [tabBar] slot and a top [appBar] slot, over the `windowBackgroundWhite`
/// page color (ARCHITECTURE.md section 6, row "TgScaffold").
///
/// ### Composition (ARCHITECTURE.md section 3.2)
///
/// ```
/// TgScaffold
/// └── GlassBackdropScope                // one BackdropGroup per page
///     ├── RepaintBoundary               // scrollable body content
///     │   └── body
///     └── Stack overlay slots
///         ├── GlassEdgeFade(60dp, opacity: true)   // behind the tab bar
///         ├── GlassEdgeFade(40dp, up)              // behind the app bar
///         ├── appBar
///         └── tabBar
/// ```
///
/// ### extendBodyBehindBars
///
/// With [extendBodyBehindBars] (the default and the Android layout), [body]
/// fills the scaffold and the bars float above it; the body subtree sees a
/// [MediaQuery] whose padding is grown so scrollables keep their content
/// clear of the bars:
///
///  * `padding.bottom` = safe-area bottom + [kTgScaffoldTabBarInset] (72dp)
///    when [tabBar] is set — `navigationBarHeight +
///    dp(MAIN_TABS_HEIGHT_WITH_MARGINS)` (DialogsActivity.java:2978);
///  * `padding.top` = safe-area top + `appBar.preferredSize.height` when
///    [appBar] is set.
///
/// With [extendBodyBehindBars] false the body is instead padded to sit
/// between the bars, the covered safe-area padding is consumed (set to 0),
/// and no edge fades are mounted (there is nothing behind the bars to fade).
///
/// ### Slots
///
/// [appBar] spans the top of the scaffold at `safe-area top +
/// preferredSize.height` — like Flutter's `Scaffold`, the status-bar region
/// belongs to the bar, which is expected to pad its own content. [tabBar] is
/// docked flush to the bottom safe-area edge (its own 72dp box carries the
/// 8dp visual margins — see `GlassTabBar`), giving the Android placement
/// `pill bottom = navigationBar + 8dp` (MainTabsActivity.java:359, 824).
///
/// Like every component in this package, the scaffold takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention).
class TgScaffold extends StatelessWidget {
  /// Creates a scaffold.
  const TgScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.tabBar,
    this.backgroundColor,
    this.extendBodyBehindBars = true,
    this.glassTier,
    this.glassStrategy,
    this.glassSettings,
    this.probeOnMount = true,
    this.resources,
  });

  /// Top slot; sized to `safe-area top + preferredSize.height`. Null mounts
  /// no top slot and leaves the body's top padding untouched.
  final PreferredSizeWidget? appBar;

  /// The page content, laid out full-bleed behind the bars (wrapped in a
  /// [RepaintBoundary], ARCHITECTURE.md section 3.2).
  final Widget body;

  /// Bottom slot, docked to the bottom safe-area edge — typically a
  /// `GlassTabBar` (its 72dp box carries the visual margins). Null mounts no
  /// bottom slot and leaves the body's bottom padding untouched.
  final Widget? tabBar;

  /// Page background; defaults to the `windowBackgroundWhite` theme key
  /// (forced opaque by the resolution pipeline, Theme.java:9552-9614).
  final Color? backgroundColor;

  /// Whether [body] extends behind the bars (the Android layout). See the
  /// class docs for the false-mode differences.
  final bool extendBodyBehindBars;

  /// Requested [GlassTier] forwarded to the installed [GlassBackdropScope];
  /// null inherits/defaults per [GlassBackdropScope.tier].
  final GlassTier? glassTier;

  /// Requested [GlassStrategy] forwarded to the scope.
  final GlassStrategy? glassStrategy;

  /// [GlassSettings] forwarded to the scope; null uses
  /// [GlassSettings.instance].
  final GlassSettings? glassSettings;

  /// Forwarded to [GlassBackdropScope.probeOnMount]. Disable in tests that
  /// drive capability manually.
  final bool probeOnMount;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  Color _resolveBackground(BuildContext context) {
    final Color? backgroundColor = this.backgroundColor;
    if (backgroundColor != null) {
      return backgroundColor;
    }
    final TelegramResources? resources = this.resources;
    if (resources != null) {
      return resources.getColor(TelegramColorKey.windowBackgroundWhite);
    }
    // Per-key dependency: rebuild only when windowBackgroundWhite changes.
    return TelegramTheme.colorOf(context, TelegramColorKey.windowBackgroundWhite);
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackdropScope(
      tier: glassTier,
      strategy: glassStrategy,
      settings: glassSettings,
      probeOnMount: probeOnMount,
      child: Builder(builder: _buildLayout),
    );
  }

  Widget _buildLayout(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.maybeOf(context) ?? const MediaQueryData();
    final PreferredSizeWidget? appBar = this.appBar;
    final Widget? tabBar = this.tabBar;

    // Slot extents. Top: status bar + bar height (the Flutter Scaffold
    // convention — Android's actionBarHeight + statusBarHeight offset).
    // Bottom: navigationBarHeight + dp(72) (MainTabsActivity.java:805;
    // DialogsActivity.java:2978).
    final double topExtent =
        appBar == null ? 0.0 : mediaQuery.padding.top + appBar.preferredSize.height;
    final double bottomExtent =
        tabBar == null ? 0.0 : mediaQuery.padding.bottom + kTgScaffoldTabBarInset;

    // Inset injection for scrollables inside the body.
    final EdgeInsets bodyPadding = extendBodyBehindBars
        ? mediaQuery.padding.copyWith(
            top: appBar != null ? topExtent : null,
            bottom: tabBar != null ? bottomExtent : null,
          )
        : mediaQuery.padding.copyWith(
            top: appBar != null ? 0.0 : null,
            bottom: tabBar != null ? 0.0 : null,
          );

    Widget bodyChild = MediaQuery(
      data: mediaQuery.copyWith(padding: bodyPadding),
      // One boundary around the scrollable content (ARCHITECTURE.md
      // section 3.2), so body repaints do not invalidate the overlay bars.
      child: RepaintBoundary(child: body),
    );
    if (!extendBodyBehindBars) {
      bodyChild = Padding(
        padding: EdgeInsets.only(top: topExtent, bottom: bottomExtent),
        child: bodyChild,
      );
    }

    return ColoredBox(
      color: _resolveBackground(context),
      child: Stack(
        // All children are fully positioned; a non-directional alignment
        // keeps the scaffold usable without an ambient Directionality.
        alignment: Alignment.topLeft,
        children: <Widget>[
          Positioned.fill(child: bodyChild),
          // Bottom edge fade: full-width, height navBar + 72dp, anchored
          // bottom (MainTabsActivity.java:350-355, 804-809), 60dp/opacity
          // MainTabs table (MainTabsActivity.java:352), ramp at the top of
          // the zone (positive Java fadeHeight -> GlassFadeDirection.down).
          if (extendBodyBehindBars && tabBar != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: bottomExtent,
              child: const IgnorePointer(
                child: GlassEdgeFade.mainTabs(
                  child: FrostedPanel(style: _fadeSurfaceStyle),
                ),
              ),
            ),
          // Top edge fade: the fade drawable's 40dp default
          // (BlurredBackgroundWithFadeDrawable.java:58) over the top zone,
          // ramp anchored at the zone's bottom edge (negative Java
          // fadeHeight -> GlassFadeDirection.up; ChatActivityFadeView.java:
          // 47-48, 95-99).
          if (extendBodyBehindBars && appBar != null)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: topExtent,
              child: const IgnorePointer(
                child: GlassEdgeFade(
                  direction: GlassFadeDirection.up,
                  child: FrostedPanel(style: _fadeSurfaceStyle),
                ),
              ),
            ),
          if (appBar != null)
            Positioned(left: 0, right: 0, top: 0, height: topExtent, child: appBar),
          // Docked flush to the bottom safe-area edge: pill bottom lands at
          // navigationBar + 8dp (MainTabsActivity.java:359, 824).
          if (tabBar != null)
            Positioned(left: 0, right: 0, bottom: mediaQuery.padding.bottom, child: tabBar),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ColorProperty('backgroundColor', backgroundColor, defaultValue: null))
      ..add(FlagProperty(
        'extendBodyBehindBars',
        value: extendBodyBehindBars,
        ifFalse: 'body between bars',
      ))
      ..add(EnumProperty<GlassTier>('glassTier', glassTier, defaultValue: null))
      ..add(EnumProperty<GlassStrategy>('glassStrategy', glassStrategy, defaultValue: null))
      ..add(FlagProperty('probeOnMount', value: probeOnMount, ifFalse: 'no probe on mount'));
  }
}
