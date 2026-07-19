// The glass-mode action bar (ARCHITECTURE.md section 6, row "GlassAppBar").
//
// Port of `ui/ActionBar/ActionBar.java` in its glass configuration
// (`setupGlass`, ActionBar.java:209-252), with every constant cited:
//
// - bar height 56dp portrait / 48dp landscape (`getCurrentActionBarHeight`,
//   ActionBar.java:1855-1861) plus the status-bar inset when `occupyStatusBar`
//   (ActionBar.java:111, 1389);
// - three glass pills, radius 23dp with 6dp drawable padding
//   (ActionBar.java:221-239); pill geometry from `dispatchDraw`
//   (ActionBar.java:2152-2197): content band s = 46dp, padding p = 6dp, pill
//   height s + 2p = 58dp, back pill `[0, t, 58dp, b]`;
// - glass title 17dp Roboto Medium (`AndroidUtilities.bold()`,
//   ActionBar.java:523, size ActionBar.java:1431-1443), color key
//   `actionBarDefaultTitle` (ActionBar.java:520), textLeft 76dp with a back
//   button / 24dp without (glass override, ActionBar.java:1511-1513);
// - subtitle 14dp, color key `actionBarDefaultSubtitle`
//   (ActionBar.java:465, 1437);
// - title swap: incoming from translationY +-20dp with an alpha crossfade
//   (`setTitleAnimated`, ActionBar.java:1863-1927); the Java duration is
//   caller-supplied — the default here is the bar's own 220ms transition/
//   subtitle-crossfade constant (ActionBar.java:1878, 2055-2056);
// - menu items width tracked by a 320ms EASE_OUT_QUINT animator
//   (ActionBar.java:2115-2116, `checkMenuItemsWidth` 2136-2150);
// - search show/hide fade 150ms with hidden views at scale 0.95
//   (ActionBar.java:1196-1264), glass menu shift -10dp -> -5dp lerped by the
//   search alpha (ActionBar.java:242, 1207-1209), forum main-pill corners
//   18.33dp -> 23dp (ActionBar.java:224-228, 1200-1205).
//
// Pill color recipe (verified against every production `setupGlass` caller):
// `BlurredBackgroundProviderImpl.topPanelChatActivity(...)` is passed by
// ChatActivity.java:4530-4533, ChannelAdminLogActivity.java:1161,
// CommunityCreateActivity.java:107, and CommunityEditActivity.java:162 —
// the port's `GlassPresets.topPanelChat` — while the attach sheet passes
// `attachMenuActionBar` (ChatAttachAlert.java:4075). (`FloatingToolbar` is
// the floating text-selection toolbar, not this bar; it uses
// `photoViewerMenu`, FloatingToolbar.java:1499.) The default [GlassAppBar.preset]
// is therefore [GlassPresets.topPanelChat]; attach-sheet hosts override it.
//
// The pills render at [GlassTier.frosted] by default — the "frosted for
// full-width bars" area budget of ARCHITECTURE.md section 3.5.
//
// The in-bar search *field* (ActionBarMenuItem's search layout) lives in
// glass_app_bar_search_field.dart ([GlassAppBarSearchField]) and mounts in the
// search socket by default when [GlassAppBar.searchMode] flips true; the
// [GlassAppBar.searchBuilder] slot overrides it with custom content. The
// open/close wiring ports:
//
// - open: the field text resets and the field grabs focus
//   (`searchField.setText(""); searchField.requestFocus()` + show keyboard,
//   ActionBarMenuItem.java:993-996), gated by [GlassAppBar.searchAutoFocus]
//   (the `openKeyboard` flag, ActionBarMenuItem.java:896);
// - close: the field drops focus (`searchField.clearFocus()`,
//   ActionBarMenuItem.java:947);
// - while search is visible a tap on the back/leading slot closes search
//   instead of activating the slot (`backButtonImageView` click:
//   `if (isSearchFieldVisible) { closeSearchField(); return; }`,
//   ActionBar.java:271-274) — the port notifies [GlassAppBar.onSearchClose];
//   the Java `MenuDrawable` back-arrow morph (ActionBar.java:1266-1272) is a
//   drawable of the caller-owned leading slot and is not ported.
//
// Deliberately NOT ported (out of the v1 glass scope, kept as doc pointers):
// the action mode (ActionBar.java:767-1100), the non-glass adaptive scroll
// background (320ms `windowBackgroundGray` -> `actionBarDefault`,
// ActionBar.java:2287-2313 — glass mode nulls the view background,
// ActionBar.java:216), `extraHeight`, the tablet metrics, the
// `chatAvatarContainer` width animation (ActionBar.java:2090-2113), the
// avatar-search image, and the `overlayTitleAnimation` crossfade arm of
// `setTitleAnimated` (ActionBar.java:1872-1879).
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../foundation/tg_curves.dart';
import '../../glass/geometry.dart';
import '../../glass/glass_panel.dart';
import '../../glass/presets.dart';
import '../../glass/strategy.dart';
import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';
import 'glass_app_bar_search_field.dart';

/// Portrait bar height: `dp(56)` (`getCurrentActionBarHeight`,
/// ActionBar.java:1858-1859).
const double kGlassAppBarHeightPortrait = 56.0;

/// Landscape bar height: `dp(48)` (ActionBar.java:1856-1857).
const double kGlassAppBarHeightLandscape = 48.0;

/// Glass pill corner radius: `dp(23)` (ActionBar.java:227, 233, 238).
const double kGlassAppBarPillRadius = 23.0;

/// Forum main-pill leading-corner radius: `dp(18.33)` for the top-left and
/// bottom-left corners (ActionBar.java:225), animating to 23dp with the
/// search alpha (ActionBar.java:1200-1205).
const double kGlassAppBarForumRadius = 18.33;

/// Glass drawable padding `p = dp(6)` — both the `.setPadding(dp(6))` of all
/// three pills (ActionBar.java:223, 234, 239) and the geometry padding of
/// `dispatchDraw` (ActionBar.java:2154).
const double kGlassAppBarPillPadding = 6.0;

/// Pill content band `s = dp(46)` (ActionBar.java:2155).
const double kGlassAppBarPillContentSize = 46.0;

/// Pill height `s + 2p = 58dp` (`b - t`, ActionBar.java:2162-2163).
const double kGlassAppBarPillHeight =
    kGlassAppBarPillContentSize + kGlassAppBarPillPadding * 2;

/// Back pill width: `s + p * 2 = 58dp` — bounds `[0, t, 58dp, b]`
/// (ActionBar.java:2190).
const double kGlassAppBarBackPillWidth =
    kGlassAppBarPillContentSize + kGlassAppBarPillPadding * 2;

/// Back button slot width: 54dp (`createBackButtonImage`,
/// ActionBar.java:269; measured 54dp wide x barHeight tall,
/// ActionBar.java:1393).
const double kGlassAppBarBackButtonSize = 54.0;

/// Glass-mode back button shift: `translationX = dp(2)`
/// (ActionBar.java:249-251).
const double kGlassAppBarBackShiftX = 2.0;

/// Glass text left with a back button: `dp(76)` (ActionBar.java:1511).
const double kGlassAppBarTextLeftWithBack = 76.0;

/// Glass text left without a back button: `dp(24)` (ActionBar.java:1513).
const double kGlassAppBarTextLeftNoBack = 24.0;

/// Glass title text size: 17dp (ActionBar.java:1431, 1435, 1443).
const double kGlassAppBarTitleTextSize = 17.0;

/// Subtitle text size: 14dp non-tablet with a title present
/// (ActionBar.java:1437).
const double kGlassAppBarSubtitleTextSize = 14.0;

/// Trailing gap reserved next to the title:
/// `availableWidth = width - menuWidth - dp(16) - textLeft`
/// (ActionBar.java:1428).
const double kGlassAppBarTitleRightGap = 16.0;

/// Title swap translation: incoming from `+-dp(20)`, outgoing to the mirror
/// offset (`setTitleAnimated`, ActionBar.java:1893, 1904).
const double kGlassAppBarTitleSwapOffset = 20.0;

/// Default title-swap duration. The Java duration is caller-supplied
/// (ActionBar.java:1867); 220ms is the bar's own transition-set duration
/// (ActionBar.java:2055-2056) and the subtitle-crossfade duration
/// (ActionBar.java:1878).
const Duration kGlassAppBarTitleSwapDuration = Duration(milliseconds: 220);

/// Search field show/hide duration: 150ms (ActionBar.java:1264).
const Duration kGlassAppBarSearchDuration = Duration(milliseconds: 150);

/// Scale of the views hidden by the search expansion: 0.95
/// (ActionBar.java:1221-1226).
const double kGlassAppBarSearchHiddenScale = 0.95;

/// Menu width / has-menu tracking duration: `FactorAnimator(...,
/// EASE_OUT_QUINT, 320)` (ActionBar.java:2115-2116).
const Duration kGlassAppBarMenuTrackDuration = Duration(milliseconds: 320);

/// Glass menu shift when the search field is hidden: `translationX = -dp(10)`
/// (ActionBar.java:242).
const double kGlassAppBarMenuShiftDefault = 10.0;

/// Glass menu shift when the search field is fully visible: `-dp(5)` — the
/// lerp target of ActionBar.java:1207-1209.
const double kGlassAppBarMenuShiftSearch = 5.0;

/// Left edge of the expanded search content: `dp(66)` non-tablet
/// (menu measured at `width - dp(66)` when the search field is visible,
/// ActionBar.java:1412, laid out at `menuLeft = dp(66)`, ActionBar.java:1518).
const double kGlassAppBarSearchContentLeft = 66.0;

/// Port of Android's `android.view.animation.AccelerateDecelerateInterpolator`
/// — `f(t) = cos((t + 1) * pi) / 2 + 0.5` — the default interpolator of the
/// `ValueAnimator` / `ViewPropertyAnimator` instances behind the ActionBar
/// search fade (ActionBar.java:1196-1264) and title swap
/// (ActionBar.java:1895-1909), none of which set an explicit interpolator.
class TgAccelerateDecelerateCurve extends Curve {
  /// Creates the curve; it has no parameters.
  const TgAccelerateDecelerateCurve();

  @override
  double transformInternal(double t) => math.cos((t + 1) * math.pi) / 2.0 + 0.5;
}

/// The curve used for the search fade and the title swap — see
/// [TgAccelerateDecelerateCurve].
const Curve kGlassAppBarAnimatorCurve = TgAccelerateDecelerateCurve();

/// The three glass pill rectangles of the bar — the pure output of the
/// `dispatchDraw` geometry (ActionBar.java:2152-2197) for one frame.
///
/// All values are logical px; the Java int-px truncations (including the
/// `(int) (p * factor)` cast of ActionBar.java:2166) are not reproduced —
/// pixel snapping is a caller opt-in via `TgDimens.fidelity`, like everywhere
/// else in this package.
@immutable
class GlassAppBarPillGeometry {
  /// Creates resolved geometry; prefer [GlassAppBarPillGeometry.compute].
  const GlassAppBarPillGeometry({
    required this.backPill,
    required this.mainPill,
    required this.menuPill,
    required this.menuPillOpacity,
  });

  /// Runs the `dispatchDraw` pill math (ActionBar.java:2152-2197).
  ///
  /// [size] is the full bar size *including* the status-bar inset (the Java
  /// `getWidth()`/`getHeight()`); [barHeight] is `getCurrentActionBarHeight()`.
  /// [menuWidth] is the animated tracked menu-items width
  /// (`animatorMenuItemsWidth`, ActionBar.java:2158) and [hasMenuFactor] the
  /// animated 0..1 `animatorHasMenuItems` value (ActionBar.java:2166).
  /// [onlyBackPill] is `glassOnlyBack` (ActionBar.java:201-203): only the
  /// back pill draws (ActionBar.java:2165, 2193).
  ///
  /// The `chatAvatarContainer` arm and `hasForcedMenuWidth` are not ported;
  /// their lerp factors collapse to the null-container / unforced branches
  /// (ActionBar.java:2166-2184).
  factory GlassAppBarPillGeometry.compute({
    required Size size,
    required double barHeight,
    required bool hasBackButton,
    double menuWidth = 0.0,
    double hasMenuFactor = 0.0,
    bool onlyBackPill = false,
  }) {
    const double p = kGlassAppBarPillPadding; // ActionBar.java:2154
    const double s = kGlassAppBarPillContentSize; // ActionBar.java:2155
    final double t = size.height - (barHeight + s) / 2.0 - p; // :2162
    final double b = t + s + p * 2.0; // :2163

    Rect? mainPill;
    if (!onlyBackPill) {
      // menuWidthWithPadding, null-avatar-container branch (:2166-2170).
      final double menuWidthWithPadding = menuWidth + p * hasMenuFactor;
      final double left = hasBackButton ? s + p : 0.0; // :2169
      final double right = size.width - menuWidthWithPadding; // :2167, :2170
      mainPill = Rect.fromLTRB(left, t, right, b); // :2186
    }

    final Rect? backPill = hasBackButton
        ? Rect.fromLTRB(0.0, t, s + p * 2.0, b) // :2189-2190
        : null;

    Rect? menuPill;
    if (!onlyBackPill && menuWidth > 0.0) {
      menuPill = Rect.fromLTRB(
        size.width - math.max(s, menuWidth) - p * 2.0, // :2194
        t,
        size.width,
        b,
      );
    }

    return GlassAppBarPillGeometry(
      backPill: backPill,
      mainPill: mainPill,
      menuPill: menuPill,
      // glassDrawableMenu.setAlpha(255 * animatorHasMenuItems) (:2195).
      menuPillOpacity: onlyBackPill ? 0.0 : hasMenuFactor,
    );
  }

  /// Back pill `[0, t, 58dp, b]` (ActionBar.java:2189-2192); null without a
  /// back button.
  final Rect? backPill;

  /// Main/title pill (ActionBar.java:2165-2188); null in only-back mode.
  final Rect? mainPill;

  /// Menu pill `[w - max(46dp, menuW) - 12dp, t, w, b]`
  /// (ActionBar.java:2193-2197); null when the tracked menu width is zero or
  /// in only-back mode.
  final Rect? menuPill;

  /// Menu pill alpha — the animated has-menu factor (ActionBar.java:2195).
  final double menuPillOpacity;

  @override
  bool operator ==(Object other) =>
      other is GlassAppBarPillGeometry &&
      other.backPill == backPill &&
      other.mainPill == mainPill &&
      other.menuPill == menuPill &&
      other.menuPillOpacity == menuPillOpacity;

  @override
  int get hashCode => Object.hash(backPill, mainPill, menuPill, menuPillOpacity);

  @override
  String toString() =>
      'GlassAppBarPillGeometry(back: $backPill, main: $mainPill, '
      'menu: $menuPill @ $menuPillOpacity)';
}

/// The glass action bar: frosted glass pills behind a back slot, a
/// title/subtitle block, and a row of trailing action slots (the
/// `GlassIconButton` sockets of ARCHITECTURE.md section 6).
///
/// ### Height and [PreferredSizeWidget]
///
/// The rendered height is `barHeight + statusBarInset`: 56dp portrait / 48dp
/// landscape (ActionBar.java:1855-1861) plus `MediaQuery.padding.top` when
/// [occupyStatusBar] (the Java `occupyStatusBar` + `setMeasuredDimension`,
/// ActionBar.java:111, 1389). [preferredSize] is necessarily context-free, so
/// it reports the portrait bar height alone; hosts that need the real
/// orientation- and inset-aware height (e.g. a Material `Scaffold.appBar`
/// slot) should wrap the bar in a `PreferredSize` sized with
/// [preferredHeightFor].
///
/// ### Composition
///
/// Pills are [GlassPanel]s at [tier] (default [GlassTier.frosted] — the
/// frosted-for-full-width-bars budget of ARCHITECTURE.md section 3.5) with
/// [preset] (default [GlassPresets.topPanelChat], the recipe every production
/// `ActionBar.setupGlass` caller uses — see the library docs for the call-site
/// survey), radius 23dp, drawable padding 6dp.
///
/// Like every component in this package, the bar takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention).
class GlassAppBar extends StatefulWidget implements PreferredSizeWidget {
  /// Creates a glass action bar.
  const GlassAppBar({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    this.onlyBackPill = false,
    this.isForum = false,
    this.searchMode = false,
    this.searchBuilder,
    this.searchController,
    this.searchFocusNode,
    this.searchHint,
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.onSearchClose,
    this.searchAutoFocus = true,
    this.animateTitleChange = false,
    this.titleChangeFromBottom = false,
    this.titleChangeDuration = kGlassAppBarTitleSwapDuration,
    this.occupyStatusBar = true,
    this.tier = GlassTier.frosted,
    this.preset,
    this.resources,
  });

  /// Bar title, 17dp Roboto Medium in `actionBarDefaultTitle`
  /// (ActionBar.java:520, 523, 1431-1443).
  final String? title;

  /// Subtitle under the title, 14dp in `actionBarDefaultSubtitle`
  /// (ActionBar.java:465, 1437).
  final String? subtitle;

  /// Leading slot — the back button. Laid out 54dp wide over the bar height
  /// at the top-left (ActionBar.java:269, 1393, 1510) and shifted +2dp in
  /// glass mode (ActionBar.java:249-251). When non-null the back pill draws
  /// behind it and the text left becomes 76dp (ActionBar.java:1511, 2189).
  ///
  /// Intended to host a `GlassIconButton`; any widget works.
  final Widget? leading;

  /// Trailing action slots (the `ActionBarMenu` items), laid out
  /// right-aligned over the bar height with the glass shift of
  /// ActionBar.java:242/1208. Their measured width drives the menu pill via
  /// the 320ms EASE_OUT_QUINT trackers (ActionBar.java:2115-2116).
  ///
  /// Intended to host `GlassIconButton`s; any widgets work. Note Android's
  /// `ActionBarMenu` hides its non-search items during search itself — slot
  /// visibility during [searchMode] is the caller's business here.
  final List<Widget> actions;

  /// `setGlassOnlyBack()` (ActionBar.java:201-203): only the back pill draws.
  final bool onlyBackPill;

  /// Forum variant: the main pill's leading corners are 18.33dp, animating to
  /// 23dp with the search alpha (ActionBar.java:224-228, 1200-1205).
  final bool isForum;

  /// Whether the search UI is expanded. Changes animate over 150ms
  /// (ActionBar.java:1264): title and subtitle fade out and scale to 0.95,
  /// [searchBuilder] content fades in, the menu shifts -10dp -> -5dp, and
  /// forum corners round up.
  final bool searchMode;

  /// Builds custom expanded-search content, mounted from 66dp
  /// (ActionBar.java:1412, 1518) to the trailing edge and faded by the search
  /// factor. When null (default) the socket mounts a [GlassAppBarSearchField]
  /// wired to [searchController], [searchFocusNode], [searchHint],
  /// [onSearchChanged], and [onSearchSubmitted].
  final WidgetBuilder? searchBuilder;

  /// Controller of the built-in [GlassAppBarSearchField]; an internal one is
  /// created when null. On every search open the text is reset
  /// (`searchField.setText("")`, ActionBarMenuItem.java:993). Unused when
  /// [searchBuilder] is set (custom content owns its own field).
  final TextEditingController? searchController;

  /// Focus node of the built-in [GlassAppBarSearchField]; an internal one is
  /// created when null. Focus is requested on search open and dropped on
  /// close (ActionBarMenuItem.java:994, 947). Unused when [searchBuilder]
  /// is set.
  final FocusNode? searchFocusNode;

  /// Hint of the built-in search field, in
  /// `actionBarDefaultSearchPlaceholder` (ActionBarMenuItem.java:1492).
  final String? searchHint;

  /// Text-change callback of the built-in search field
  /// (`listener.onTextChanged`, ActionBarMenuItem.java:1536-1538).
  final ValueChanged<String>? onSearchChanged;

  /// Submit callback of the built-in search field — the IME search action
  /// (`onSearchPressed`, ActionBarMenuItem.java:1509-1516).
  final ValueChanged<String>? onSearchSubmitted;

  /// Called when a tap on the leading slot should close search instead of
  /// activating the slot — the Java back-click arm
  /// `if (isSearchFieldVisible) { closeSearchField(); return; }`
  /// (ActionBar.java:271-274). While [searchMode] is true and this is
  /// non-null, the leading slot's own gestures are absorbed and a tap
  /// invokes this instead (the host flips [searchMode] back to false).
  final VoidCallback? onSearchClose;

  /// Whether opening search focuses the field (and thus raises the
  /// keyboard) — the `openKeyboard` flag of `toggleSearch`
  /// (ActionBarMenuItem.java:896, 993-996).
  final bool searchAutoFocus;

  /// When true, a [title] change plays the `setTitleAnimated` swap
  /// (ActionBar.java:1863-1927): the new title fades in from +-20dp while the
  /// old fades out to the mirror offset. When false (default), title changes
  /// are instant — the plain `setTitle` path.
  final bool animateTitleChange;

  /// The `fromBottom` flag of `setTitleAnimated` (ActionBar.java:1867): true
  /// slides the incoming title up from +20dp, false (default) down from
  /// -20dp (ActionBar.java:1893, 1904).
  final bool titleChangeFromBottom;

  /// Title-swap duration (caller-supplied in Java, ActionBar.java:1867);
  /// defaults to [kGlassAppBarTitleSwapDuration].
  final Duration titleChangeDuration;

  /// Whether the bar extends behind the status bar and adds
  /// `MediaQuery.padding.top` to its height (the Java `occupyStatusBar`,
  /// ActionBar.java:111, 1389).
  final bool occupyStatusBar;

  /// Glass tier of the pills. Defaults to [GlassTier.frosted] (ARCHITECTURE.md
  /// section 3.5: frosted for full-width bars, matching Android's frosted top
  /// bars); pass null to defer to the enclosing `GlassBackdropScope`.
  final GlassTier? tier;

  /// Pill color recipe; defaults to [GlassPresets.topPanelChat] (the
  /// `topPanelChatActivity` provider every production `setupGlass` caller
  /// passes — see the library docs). The attach sheet would pass
  /// [GlassPresets.attachMenuActionBar] (ChatAttachAlert.java:4075).
  final GlassSurfaceStyleResolver? preset;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  /// Key of the main/title pill's [GlassPanel].
  static const Key mainPillKey = Key('GlassAppBar.mainPill');

  /// Key of the back pill's [GlassPanel].
  static const Key backPillKey = Key('GlassAppBar.backPill');

  /// Key of the menu pill's [GlassPanel].
  static const Key menuPillKey = Key('GlassAppBar.menuPill');

  /// Key of the (incoming) title [Text].
  static const Key titleKey = Key('GlassAppBar.title');

  /// Key of the outgoing title [Text] during a swap.
  static const Key outgoingTitleKey = Key('GlassAppBar.outgoingTitle');

  /// Key of the subtitle [Text].
  static const Key subtitleKey = Key('GlassAppBar.subtitle');

  /// Key of the leading slot wrapper.
  static const Key leadingKey = Key('GlassAppBar.leading');

  /// Key of the actions [Row].
  static const Key actionsRowKey = Key('GlassAppBar.actionsRow');

  /// Key of the mounted search content.
  static const Key searchContentKey = Key('GlassAppBar.searchContent');

  /// Key of the close-search tap overlay covering the leading slot while
  /// [searchMode] is true and [onSearchClose] is set (ActionBar.java:271-274).
  static const Key searchCloseKey = Key('GlassAppBar.searchClose');

  /// `getCurrentActionBarHeight()` (ActionBar.java:1855-1861): 48dp when the
  /// display is wider than tall, else 56dp.
  static double barHeightFor(Orientation orientation) =>
      orientation == Orientation.landscape
          ? kGlassAppBarHeightLandscape
          : kGlassAppBarHeightPortrait;

  /// The context-aware preferred height: [barHeightFor] the ambient
  /// orientation plus `MediaQuery.padding.top` when [occupyStatusBar] — the
  /// Java measured height `actionBarHeight + statusBarHeight`
  /// (ActionBar.java:1389; `extraHeight` is not ported).
  static double preferredHeightFor(
    BuildContext context, {
    bool occupyStatusBar = true,
  }) {
    final double barHeight = barHeightFor(MediaQuery.orientationOf(context));
    return barHeight +
        (occupyStatusBar ? MediaQuery.paddingOf(context).top : 0.0);
  }

  /// Glass text left (`onLayout`, ActionBar.java:1508-1514): 76dp with a
  /// leading/back slot, 24dp without (ActionBar.java:1511-1513).
  static double titleLeftFor({required bool hasLeading}) =>
      hasLeading ? kGlassAppBarTextLeftWithBack : kGlassAppBarTextLeftNoBack;

  /// Title top within the bar band (below the status inset), from
  /// ActionBar.java:1528-1532: centered when alone (:1531), else
  /// `(barHeight/2 - titleHeight)/2 + 2dp + (landscape ? 2 : 3)dp` (:1529;
  /// tablet not ported).
  static double titleTopFor({
    required double barHeight,
    required double titleHeight,
    required bool hasSubtitle,
    bool landscape = false,
  }) {
    if (!hasSubtitle) {
      return (barHeight - titleHeight) / 2.0;
    }
    return (barHeight / 2.0 - titleHeight) / 2.0 + 2.0 + (landscape ? 2.0 : 3.0);
  }

  /// Subtitle top within the bar band:
  /// `barHeight/2 + (barHeight/2 - subtitleHeight)/2 - 2dp`
  /// (ActionBar.java:1541-1543).
  static double subtitleTopFor({
    required double barHeight,
    required double subtitleHeight,
  }) =>
      barHeight / 2.0 + (barHeight / 2.0 - subtitleHeight) / 2.0 - 2.0;

  /// The glass title style: 17dp Roboto Medium (`AndroidUtilities.bold()` =
  /// `fonts/rmedium.ttf`, ActionBar.java:523; size ActionBar.java:1431-1443),
  /// bundled by this package as family `RobotoMedium` at w500.
  static TextStyle titleStyleFor(Color color) => TextStyle(
        fontSize: kGlassAppBarTitleTextSize,
        fontFamily: 'RobotoMedium',
        package: 'telegram_ui',
        fontWeight: FontWeight.w500,
        color: color,
      );

  /// The subtitle style: 14dp regular (`SimpleTextView` default typeface —
  /// regular Roboto, which this package does not bundle; the ambient default
  /// family is used).
  static TextStyle subtitleStyleFor(Color color) => TextStyle(
        fontSize: kGlassAppBarSubtitleTextSize,
        color: color,
      );

  /// Measures the laid-out single-line height of [text] in [style], exactly
  /// as the bar does for its vertical formulas ([titleTopFor] /
  /// [subtitleTopFor] consume this as `textHeight`). Text scaling is not
  /// applied: the Java `SimpleTextView.setTextSize` is dp-based, not sp.
  static double measureTextHeight(String text, TextStyle style) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final double height = painter.height;
    painter.dispose();
    return height;
  }

  /// Context-free preferred size: the portrait bar height alone
  /// (orientation and the status-bar inset need a context — see
  /// [preferredHeightFor]).
  @override
  Size get preferredSize => const Size.fromHeight(kGlassAppBarHeightPortrait);

  @override
  State<GlassAppBar> createState() => GlassAppBarState();
}

/// State of [GlassAppBar]; public for test access to the `debug*` probes.
class GlassAppBarState extends State<GlassAppBar>
    with TickerProviderStateMixin {
  /// Search factor 0..1 (`searchFieldVisibleAlpha`, ActionBar.java:147,
  /// driven 150ms per ActionBar.java:1196-1264). The curve is baked into the
  /// controller value via `animateTo`.
  late final AnimationController _search;

  /// Title-swap clock 0..1 (linear; [kGlassAppBarAnimatorCurve] is applied
  /// at read time). 1.0 means settled.
  late final AnimationController _titleSwap;

  /// Tracked menu items width in logical px (`animatorMenuItemsWidth`,
  /// ActionBar.java:2115).
  late final AnimationController _menuWidth;

  /// Has-menu factor 0..1 (`animatorHasMenuItems`, ActionBar.java:2116).
  late final AnimationController _hasMenu;

  late final Listenable _repaint;

  /// The title being faded out by a running swap (`titleTextView[1]`,
  /// ActionBar.java:1887); null when settled.
  String? _outgoingTitle;

  /// Last laid-out actions-row width (the `menu.getItemsWidth()` stand-in;
  /// the Java `- dp(1) - dp(1)` trims of ActionBar.java:2137 compensate
  /// ActionBarMenuItem-internal padding and are not applied to arbitrary
  /// slots).
  double _reportedMenuWidth = 0.0;
  bool _menuUpdateScheduled = false;

  /// `isAnimationsAllowed` (ActionBar.java:2134, armed at :2209). The port
  /// arms it after the first width application instead of the first draw —
  /// visible only when a bar mounts with zero actions and later gains some:
  /// that first appearance snaps where Android animates.
  bool _menuAnimationsAllowed = false;

  /// Internal controller/focus of the built-in search field, created lazily
  /// when the caller supplies neither their own nor a [GlassAppBar.searchBuilder].
  TextEditingController? _internalSearchController;
  FocusNode? _internalSearchFocusNode;

  GlassAppBarPillGeometry? _lastGeometry;
  GlassRadii? _lastMainPillRadii;

  /// The pill geometry of the last built frame.
  @visibleForTesting
  GlassAppBarPillGeometry? get debugPillGeometry => _lastGeometry;

  /// The main pill radii of the last built frame (forum corners animate with
  /// the search factor).
  @visibleForTesting
  GlassRadii? get debugMainPillRadii => _lastMainPillRadii;

  /// Current search factor (curved), 0 hidden .. 1 expanded.
  @visibleForTesting
  double get debugSearchFactor => _search.value;

  /// Current title-swap progress (linear clock; 1 = settled).
  @visibleForTesting
  double get debugTitleSwapFactor => _titleSwap.value;

  /// Currently tracked (animated) menu width in logical px.
  @visibleForTesting
  double get debugMenuTrackedWidth => _menuWidth.value;

  /// Current has-menu factor.
  @visibleForTesting
  double get debugHasMenuFactor => _hasMenu.value;

  /// The outgoing title of a running swap, or null.
  @visibleForTesting
  String? get debugOutgoingTitle => _outgoingTitle;

  /// Whether the socket mounts the built-in [GlassAppBarSearchField]
  /// (no custom [GlassAppBar.searchBuilder]).
  bool get _usesBuiltInSearchField => widget.searchBuilder == null;

  /// The search controller in effect: the caller's, else an internal one
  /// when the built-in field is used, else null.
  TextEditingController? get _searchController {
    if (widget.searchController != null) {
      return widget.searchController;
    }
    if (!_usesBuiltInSearchField) {
      return null;
    }
    return _internalSearchController ??= TextEditingController();
  }

  /// The search focus node in effect (same resolution as [_searchController]).
  FocusNode? get _searchFocusNode {
    if (widget.searchFocusNode != null) {
      return widget.searchFocusNode;
    }
    if (!_usesBuiltInSearchField) {
      return null;
    }
    return _internalSearchFocusNode ??= FocusNode();
  }

  /// The search controller actually in use, for tests.
  @visibleForTesting
  TextEditingController? get debugSearchController => _searchController;

  @override
  void initState() {
    super.initState();
    _search = AnimationController(
      vsync: this,
      duration: kGlassAppBarSearchDuration,
      value: widget.searchMode ? 1.0 : 0.0,
    );
    _titleSwap = AnimationController(
      vsync: this,
      duration: widget.titleChangeDuration,
      value: 1.0,
    )..addStatusListener(_onTitleSwapStatus);
    _menuWidth = AnimationController.unbounded(vsync: this);
    _hasMenu = AnimationController(
      vsync: this,
      duration: kGlassAppBarMenuTrackDuration,
    );
    _repaint = Listenable.merge(
      <Listenable>[_search, _titleSwap, _menuWidth, _hasMenu],
    );
    if (widget.searchMode) {
      // Mounted already-open: apply the open-path focus (the field element
      // mounts this frame, so defer the request past it).
      _handleSearchOpened(resetText: false);
    }
  }

  @override
  void didUpdateWidget(GlassAppBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchMode != oldWidget.searchMode) {
      // ValueAnimator.ofFloat(searchFieldVisibleAlpha, visible ? 1 : 0)
      // over 150ms (ActionBar.java:1196, 1264).
      _search.animateTo(
        widget.searchMode ? 1.0 : 0.0,
        duration: kGlassAppBarSearchDuration,
        curve: kGlassAppBarAnimatorCurve,
      );
      if (widget.searchMode) {
        _handleSearchOpened(resetText: true);
      } else {
        // Collapse: the field drops focus (`searchField.clearFocus()`,
        // ActionBarMenuItem.java:947).
        _searchFocusNode?.unfocus();
      }
    }
    if (widget.title != oldWidget.title) {
      if (widget.animateTitleChange &&
          oldWidget.title != null &&
          widget.title != null) {
        // setTitleAnimated (ActionBar.java:1863-1927): the old title becomes
        // titleTextView[1] and fades out while the new fades in.
        _outgoingTitle = oldWidget.title;
        _titleSwap.duration = widget.titleChangeDuration;
        _titleSwap.forward(from: 0.0);
      } else {
        // Plain setTitle: instant.
        _titleSwap.stop();
        _titleSwap.value = 1.0;
        _outgoingTitle = null;
      }
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _titleSwap.dispose();
    _menuWidth.dispose();
    _hasMenu.dispose();
    _internalSearchController?.dispose();
    _internalSearchFocusNode?.dispose();
    super.dispose();
  }

  /// The open arm of `toggleSearch` (ActionBarMenuItem.java:993-996):
  /// `searchField.setText("")`, then `requestFocus()` (+ keyboard when the
  /// `openKeyboard` flag — [GlassAppBar.searchAutoFocus] — is set; in
  /// Flutter focus and keyboard are one). The focus request is deferred a
  /// frame so a field mounting in this build can receive it.
  void _handleSearchOpened({required bool resetText}) {
    if (resetText) {
      _searchController?.clear();
    }
    if (!widget.searchAutoFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.searchMode) {
        _searchFocusNode?.requestFocus();
      }
    });
  }

  void _onTitleSwapStatus(AnimationStatus status) {
    // The end-listener removes titleTextView[1] (ActionBar.java:1909-1924).
    if (status == AnimationStatus.completed && _outgoingTitle != null) {
      setState(() {
        _outgoingTitle = null;
      });
    }
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  // -- Menu width tracking ---------------------------------------------------

  /// Layout-time report from the actions row; the application is deferred to
  /// the end of the frame (animating a controller mid-layout would mark
  /// already-built elements dirty).
  void _onMenuLaidOut(Size size) {
    if (size.width == _reportedMenuWidth) {
      return;
    }
    _reportedMenuWidth = size.width;
    if (_menuUpdateScheduled) {
      return;
    }
    _menuUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _menuUpdateScheduled = false;
      if (mounted) {
        _applyMenuWidth();
      }
    });
  }

  /// Port of `checkMenuItemsWidth` (ActionBar.java:2136-2150): animate the
  /// width and has-menu trackers when allowed, else force.
  void _applyMenuWidth() {
    final double width = math.max(0.0, _reportedMenuWidth);
    final bool animated = _menuAnimationsAllowed;
    _menuAnimationsAllowed = true;
    if (animated) {
      if (_menuWidth.value != width) {
        _menuWidth.animateTo(
          width,
          duration: kGlassAppBarMenuTrackDuration,
          curve: TgCurves.easeOutQuint,
        );
      }
      _hasMenu.animateTo(
        width > 0 ? 1.0 : 0.0,
        duration: kGlassAppBarMenuTrackDuration,
        curve: TgCurves.easeOutQuint,
      );
    } else {
      _menuWidth.value = width;
      _hasMenu.value = width > 0 ? 1.0 : 0.0;
    }
  }

  // -- Build -----------------------------------------------------------------

  Widget _pill({
    required Key key,
    required GlassRadii radii,
    double opacity = 1.0,
  }) {
    final Widget panel = GlassPanel(
      key: key,
      tier: widget.tier,
      preset: widget.preset ?? GlassPresets.topPanelChat,
      borderRadius: radii,
      padding: kGlassAppBarPillPadding,
      resources: widget.resources,
    );
    if (opacity >= 1.0) {
      return panel;
    }
    return Opacity(opacity: clampDouble(opacity, 0.0, 1.0), child: panel);
  }

  /// A title/subtitle text leaf with the search fade/scale and (titles only)
  /// the swap translate folded into one transform:
  /// `T(0, ty) . (center-aligned S(scale))`.
  Widget _barText({
    required Key key,
    required String text,
    required TextStyle style,
    required double opacity,
    required double translationY,
    required double scale,
  }) {
    final Matrix4 transform = Matrix4.diagonal3Values(scale, scale, 1.0)
      ..setTranslationRaw(0.0, translationY, 0.0);
    return Opacity(
      opacity: clampDouble(opacity, 0.0, 1.0),
      child: Transform(
        alignment: Alignment.center,
        transform: transform,
        child: Text(
          text,
          key: key,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          textScaler: TextScaler.noScaling,
          style: style,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Orientation orientation = MediaQuery.orientationOf(context);
    final bool landscape = orientation == Orientation.landscape;
    final double barHeight = GlassAppBar.barHeightFor(orientation);
    final double statusBarTop =
        widget.occupyStatusBar ? MediaQuery.paddingOf(context).top : 0.0;
    final double height = statusBarTop + barHeight;

    final Color titleColor =
        _color(context, TelegramColorKey.actionBarDefaultTitle);
    final Color subtitleColor =
        _color(context, TelegramColorKey.actionBarDefaultSubtitle);

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          assert(
            constraints.hasBoundedWidth,
            'GlassAppBar needs a bounded width.',
          );
          final double width = constraints.maxWidth;
          return AnimatedBuilder(
            animation: _repaint,
            builder: (BuildContext context, Widget? _) => _buildBar(
              context,
              width: width,
              height: height,
              barHeight: barHeight,
              statusBarTop: statusBarTop,
              landscape: landscape,
              titleColor: titleColor,
              subtitleColor: subtitleColor,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBar(
    BuildContext context, {
    required double width,
    required double height,
    required double barHeight,
    required double statusBarTop,
    required bool landscape,
    required Color titleColor,
    required Color subtitleColor,
  }) {
    final bool hasLeading = widget.leading != null;
    final double searchFactor = clampDouble(_search.value, 0.0, 1.0);
    final double swapFactor =
        kGlassAppBarAnimatorCurve.transform(clampDouble(_titleSwap.value, 0.0, 1.0));

    // -- Pills (dispatchDraw, ActionBar.java:2152-2197) ----------------------
    final GlassAppBarPillGeometry geometry = GlassAppBarPillGeometry.compute(
      size: Size(width, height),
      barHeight: barHeight,
      hasBackButton: hasLeading,
      menuWidth: _menuWidth.value,
      hasMenuFactor: clampDouble(_hasMenu.value, 0.0, 1.0),
      onlyBackPill: widget.onlyBackPill,
    );
    _lastGeometry = geometry;

    // Forum leading corners 18.33dp -> 23dp with the search alpha
    // (ActionBar.java:224-228, 1200-1205); non-forum stays uniform 23dp.
    final GlassRadii mainRadii;
    if (widget.isForum) {
      final double leadingRadius = lerpDouble(
        kGlassAppBarForumRadius,
        kGlassAppBarPillRadius,
        searchFactor,
      )!;
      mainRadii = GlassRadii(
        topLeft: leadingRadius,
        topRight: kGlassAppBarPillRadius,
        bottomRight: kGlassAppBarPillRadius,
        bottomLeft: leadingRadius,
      );
    } else {
      mainRadii = const GlassRadii.all(kGlassAppBarPillRadius);
    }
    _lastMainPillRadii = mainRadii;

    // -- Text metrics (onMeasure/onLayout, ActionBar.java:1391-1544) ---------
    final String? title = widget.title;
    final String? subtitle = widget.subtitle;
    final bool hasTitle = title != null && title.isNotEmpty;
    final bool hasSubtitle = subtitle != null && subtitle.isNotEmpty;
    final String? outgoingTitle = _outgoingTitle;

    final double textLeft = GlassAppBar.titleLeftFor(hasLeading: hasLeading);
    // availableWidth = width - menuWidth - dp(16) - textLeft
    // (ActionBar.java:1428; titleRightMargin not ported).
    final double availableTextWidth = math.max(
      0.0,
      width - _reportedMenuWidth - kGlassAppBarTitleRightGap - textLeft,
    );

    final TextStyle titleStyle = GlassAppBar.titleStyleFor(titleColor);
    final TextStyle subtitleStyle = GlassAppBar.subtitleStyleFor(subtitleColor);

    // Hidden-view treatment during search (ActionBar.java:1216-1227):
    // alpha -> 0, scale -> 0.95.
    final double searchHiddenOpacity = 1.0 - searchFactor;
    final double searchHiddenScale =
        lerpDouble(1.0, kGlassAppBarSearchHiddenScale, searchFactor)!;

    // Title swap values (setTitleAnimated, ActionBar.java:1891-1909).
    final double swapDirection = widget.titleChangeFromBottom ? 1.0 : -1.0;
    final double incomingTy = outgoingTitle == null
        ? 0.0
        : swapDirection * kGlassAppBarTitleSwapOffset * (1.0 - swapFactor);
    final double incomingAlpha = outgoingTitle == null ? 1.0 : swapFactor;
    final double outgoingTy =
        -swapDirection * kGlassAppBarTitleSwapOffset * swapFactor;
    final double outgoingAlpha = 1.0 - swapFactor;

    final List<Widget> children = <Widget>[];

    // Pills paint before the children, like the dispatchDraw prologue
    // (ActionBar.java:2152-2214).
    final Rect? mainPill = geometry.mainPill;
    if (mainPill != null && mainPill.width > 0) {
      children.add(Positioned.fromRect(
        rect: mainPill,
        child: _pill(key: GlassAppBar.mainPillKey, radii: mainRadii),
      ));
    }
    final Rect? backPill = geometry.backPill;
    if (backPill != null) {
      children.add(Positioned.fromRect(
        rect: backPill,
        child: _pill(
          key: GlassAppBar.backPillKey,
          radii: const GlassRadii.all(kGlassAppBarPillRadius),
        ),
      ));
    }
    final Rect? menuPill = geometry.menuPill;
    if (menuPill != null && geometry.menuPillOpacity > 0) {
      children.add(Positioned.fromRect(
        rect: menuPill,
        child: _pill(
          key: GlassAppBar.menuPillKey,
          radii: const GlassRadii.all(kGlassAppBarPillRadius),
          opacity: geometry.menuPillOpacity,
        ),
      ));
    }

    // Leading slot: 54dp x barHeight at the top-left (ActionBar.java:269,
    // 1393, 1510), +2dp glass shift (ActionBar.java:249-251).
    final Widget? leading = widget.leading;
    if (leading != null) {
      Widget leadingChild = Transform.translate(
        offset: const Offset(kGlassAppBarBackShiftX, 0.0),
        child: Center(child: leading),
      );
      // While search is visible the back button closes search instead of
      // performing its own action (`backButtonImageView` click,
      // ActionBar.java:271-274): an overlay absorbs the slot's gestures and
      // taps notify onSearchClose. Like the Java `isSearchFieldVisible`,
      // this flips with searchMode immediately, not with the fade.
      final VoidCallback? onSearchClose = widget.onSearchClose;
      if (widget.searchMode && onSearchClose != null) {
        leadingChild = Stack(
          fit: StackFit.expand,
          children: <Widget>[
            leadingChild,
            GestureDetector(
              key: GlassAppBar.searchCloseKey,
              behavior: HitTestBehavior.opaque,
              onTap: onSearchClose,
            ),
          ],
        );
      }
      children.add(Positioned(
        left: 0.0,
        top: statusBarTop,
        width: kGlassAppBarBackButtonSize,
        height: barHeight,
        child: KeyedSubtree(
          key: GlassAppBar.leadingKey,
          child: leadingChild,
        ),
      ));
    }

    // Titles. Both lay at the normal formula top; the centered
    // overlayTitleAnimation arm (ActionBar.java:1525-1526) is not ported.
    if (outgoingTitle != null) {
      final double outgoingHeight =
          GlassAppBar.measureTextHeight(outgoingTitle, titleStyle);
      children.add(Positioned(
        left: textLeft,
        top: statusBarTop +
            GlassAppBar.titleTopFor(
              barHeight: barHeight,
              titleHeight: outgoingHeight,
              hasSubtitle: hasSubtitle,
              landscape: landscape,
            ),
        width: availableTextWidth,
        child: _barText(
          key: GlassAppBar.outgoingTitleKey,
          text: outgoingTitle,
          style: titleStyle,
          opacity: outgoingAlpha * searchHiddenOpacity,
          translationY: outgoingTy,
          scale: searchHiddenScale,
        ),
      ));
    }
    if (hasTitle) {
      final double titleHeight =
          GlassAppBar.measureTextHeight(title, titleStyle);
      children.add(Positioned(
        left: textLeft,
        top: statusBarTop +
            GlassAppBar.titleTopFor(
              barHeight: barHeight,
              titleHeight: titleHeight,
              hasSubtitle: hasSubtitle,
              landscape: landscape,
            ),
        width: availableTextWidth,
        child: _barText(
          key: GlassAppBar.titleKey,
          text: title,
          style: titleStyle,
          opacity: incomingAlpha * searchHiddenOpacity,
          translationY: incomingTy,
          scale: searchHiddenScale,
        ),
      ));
    }
    if (hasSubtitle) {
      final double subtitleHeight =
          GlassAppBar.measureTextHeight(subtitle, subtitleStyle);
      children.add(Positioned(
        left: textLeft,
        top: statusBarTop +
            GlassAppBar.subtitleTopFor(
              barHeight: barHeight,
              subtitleHeight: subtitleHeight,
            ),
        width: availableTextWidth,
        child: _barText(
          key: GlassAppBar.subtitleKey,
          text: subtitle,
          style: subtitleStyle,
          opacity: searchHiddenOpacity,
          translationY: 0.0,
          scale: searchHiddenScale,
        ),
      ));
    }

    // Expanded-search content socket: from 66dp to the trailing edge
    // (ActionBar.java:1412, 1518), faded by the search factor. Custom
    // searchBuilder content wins; otherwise the built-in search field
    // (the ActionBarMenuItem search layout) mounts.
    final WidgetBuilder? searchBuilder = widget.searchBuilder;
    if (widget.searchMode || searchFactor > 0) {
      final Widget searchContent = searchBuilder != null
          ? searchBuilder(context)
          : GlassAppBarSearchField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hintText: widget.searchHint,
              onChanged: widget.onSearchChanged,
              onSubmitted: widget.onSearchSubmitted,
              resources: widget.resources,
            );
      children.add(Positioned(
        left: kGlassAppBarSearchContentLeft,
        right: 0.0,
        top: statusBarTop,
        height: barHeight,
        child: IgnorePointer(
          ignoring: !widget.searchMode,
          child: Opacity(
            opacity: searchFactor,
            child: KeyedSubtree(
              key: GlassAppBar.searchContentKey,
              child: searchContent,
            ),
          ),
        ),
      ));
    }

    // Actions row, right-aligned over the bar height (ActionBar.java:
    // 1517-1520) with the glass shift -10dp -> -5dp (ActionBar.java:242,
    // 1207-1209). Its laid-out width drives the menu trackers.
    children.add(Positioned(
      right: 0.0,
      top: statusBarTop,
      height: barHeight,
      child: Transform.translate(
        offset: Offset(
          -lerpDouble(
            kGlassAppBarMenuShiftDefault,
            kGlassAppBarMenuShiftSearch,
            searchFactor,
          )!,
          0.0,
        ),
        child: _MenuSizeObserver(
          onLaidOut: _onMenuLaidOut,
          child: Row(
            key: GlassAppBar.actionsRowKey,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: widget.actions,
          ),
        ),
      ),
    ));

    // Pills overhang the bar band by 1dp at 56dp height (t < 0 without a
    // status inset), so the stack must not clip — the Java
    // `setClipChildren(false)` (ActionBar.java:217).
    return Stack(clipBehavior: Clip.none, children: children);
  }
}

/// Reports the laid-out size of its child — the stand-in for
/// `ActionBarMenu.getItemsWidth()` feeding `checkMenuItemsWidth`
/// (ActionBar.java:2136-2150).
class _MenuSizeObserver extends SingleChildRenderObjectWidget {
  const _MenuSizeObserver({required this.onLaidOut, super.child});

  final ValueChanged<Size> onLaidOut;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMenuSizeObserver(onLaidOut);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMenuSizeObserver renderObject,
  ) {
    renderObject.onLaidOut = onLaidOut;
  }
}

class _RenderMenuSizeObserver extends RenderProxyBox {
  _RenderMenuSizeObserver(this.onLaidOut);

  ValueChanged<Size> onLaidOut;
  Size? _lastReported;

  @override
  void performLayout() {
    super.performLayout();
    if (_lastReported != size) {
      _lastReported = size;
      onLaidOut(size);
    }
  }
}
