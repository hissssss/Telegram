// The sticker / GIF / emoji panel CHROME — the port of the shell of
// `java/org/telegram/ui/Components/EmojiView.java` (spec:
// `flutter/docs/spec_attach_emoji.md` Part B).
//
// Scope (deliberately chrome-only): the panel container with its imposed
// height rules, the bottom type-tab strip (emoji / GIFs / stickers) with the
// pill indicator, the per-page category strip, the search row, and the
// trending/section header. Content pipelines — emoji grids, sticker sets,
// GIF search — are SLOT parameters (`WidgetBuilder`s / icon widgets) and are
// never implemented here.
//
// Java sources cited below:
// - **EV**   = `ui/Components/EmojiView.java`
// - **ETS**  = `ui/Components/EmojiTabsStrip.java`
// - **PSTS** = `ui/Components/PagerSlidingTabStrip.java`
// - **CAEV** = `ui/Components/ChatActivityEnterView.java`
// - **SSNC** = `ui/Cells/StickerSetNameCell.java`
//
// Units: 1 Android dp = 1 Flutter logical px.
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import '../../foundation/color_math.dart';
import '../../foundation/tg_curves.dart';
import '../../glass/geometry.dart';
import '../../glass/glass_panel.dart';
import '../../glass/presets.dart';
import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';
import '../tabs/glass_tab.dart' show blendArgb;

// ---------------------------------------------------------------------------
// Constants (spec_attach_emoji.md Part B)
// ---------------------------------------------------------------------------

/// Default panel height when no IME height was ever measured: `kbd_height`
/// defaults to 200dp (CAEV:12597-12621). Callers pass the real IME height.
const double kEmojiPanelDefaultHeight = 200.0;

/// Bottom padding the grids get so content scrolls under the bottom tab
/// strip: `setBottomInset(h)` adds `44dp + inset` (EV:2956-2972).
const double kEmojiPanelGridBottomPadding = 44.0;

/// `bottomTabContainer`: MATCH_PARENT x 48dp, gravity bottom (EV:2678).
const double kEmojiPanelStripHeight = 48.0;

/// `typeTabs.setPadding(dp(4), dp(11), dp(4), dp(11))` (EV:2704).
const EdgeInsets kEmojiPanelStripPadding =
    EdgeInsets.fromLTRB(4.0, 11.0, 4.0, 11.0);

/// `typeTabs.setTabPaddingLeftRight(dp(11))` (EV:2703).
const double kEmojiPanelTabPadding = 11.0;

/// The type-tab icon slot. The `smiles_tab_*` selector drawables occupy a
/// 24x24 slot like every other tab icon in the glass design
/// (GlassTabView.java:448 convention).
const double kEmojiPanelTabIconSize = 24.0;

/// The indicator pill extends 11dp past the tab *content* on each side —
/// `rectTmp.set(lineLeft - dp(11), ..., lineRight + dp(11), ...)`
/// (PSTS:297). With the 11dp tab padding this equals the full tab bounds.
const double kEmojiPanelIndicatorInflate = 11.0;

/// Indicator color alpha: `setAlphaComponent(chat_emojiPanelIconSelected,
/// 20)` — an absolute 20/255, not a multiplier (EV:2701).
const int kEmojiPanelIndicatorAlpha = 20;

/// Indicator settle / tab switch timing: `AnimatedFloat(350,
/// EASE_OUT_QUINT)` on the indicator edges (PSTS:249-250). The port drives
/// the page slide with the same clock so body and indicator agree.
const Duration kEmojiPanelSwitchDuration = Duration(milliseconds: 350);

/// Glass background of `typeTabs`/backspace/search/settings: radius 18dp
/// (EV:2923-2951), preset `GlassPresets.emojiViewButton`.
const double kEmojiPanelStripGlassRadius = 18.0;

/// Glass drawable padding of the strip background: 6dp (EV:2923-2951).
const double kEmojiPanelStripGlassPadding = 6.0;

/// Side buttons (backspace / search / sticker settings): 48x48 with a 2dp
/// edge margin (EV:2679, 2689, 2769-2776).
const double kEmojiPanelSideButtonSize = 48.0;

/// Side button edge margin (EV:2679).
const double kEmojiPanelSideButtonMargin = 2.0;

/// Category strip container height (EV:1965; EV:2510-2513).
const double kEmojiCategoryStripHeight = 36.0;

/// Category tab button size: 30x30dp (ETS:1237).
const double kEmojiCategoryButtonSize = 30.0;

/// Category strip content padding left/right: 11dp (`5+6`, ETS:647-655).
const double kEmojiCategoryContentPadding = 11.0;

/// Category selector pill radius in the non-glass design (ETS:268-272);
/// glass uses `height / 2`.
const double kEmojiCategorySelectorRadius = 8.0;

/// Selector slide mid-flight squash: width x(1 + 0.3 * isMiddle)
/// (ETS:702-711, 255-259).
const double kEmojiCategorySquashWidthFactor = 0.3;

/// Selector slide mid-flight squash: height x(1 - 0.05 * isMiddle)
/// (ETS:702-711, 255-259).
const double kEmojiCategorySquashHeightFactor = 0.05;

/// `searchFieldHeight = 50dp` (EV:1579).
const double kEmojiSearchRowHeight = 50.0;

/// Search box: MATCH x 36dp, corner radius 18dp (EV:811-819).
const double kEmojiSearchBoxHeight = 36.0;

/// Search box corner radius (EV:811-819).
const double kEmojiSearchBoxRadius = 18.0;

/// Search box horizontal margins: 10dp (EV:811-819).
const double kEmojiSearchBoxMarginHorizontal = 10.0;

/// Search box top margin: 6dp, or 8dp for the sticker-type field
/// (EV:811-819).
const double kEmojiSearchBoxMarginTop = 6.0;

/// Sticker-type search box top margin (EV:811-819).
const double kEmojiSearchBoxMarginTopSticker = 8.0;

/// Search input text size: 16dp (EV:870-901).
const double kEmojiSearchTextSize = 16.0;

/// Section header height: `dp(27)` (SSNC:234).
const double kEmojiTrendingHeaderHeight = 27.0;

/// Section header title size: 15dp (SSNC:79).
const double kEmojiTrendingHeaderTextSize = 15.0;

/// Unread/trending dot radius: `drawCircle(x, y, dp(3), dotPaint)`
/// (EV:6512-6515).
const double kEmojiTrendingDotRadius = 3.0;

/// Glass-mode `glass_defaultIcon` alpha for unselected icons (EV:10135-10139,
/// ETS:754-758, PSTS:343-347).
const double kEmojiGlassIconUnselectedAlpha = 0.4;

/// Glass-mode alpha for selected icons.
const double kEmojiGlassIconSelectedAlpha = 0.8;

/// Glass-mode alpha for buttons (backspace/settings/search tint, EV:2651).
const double kEmojiGlassIconButtonAlpha = 0.6;

/// Glass-mode alpha for the search hint (EV:870-901).
const double kEmojiGlassIconHintAlpha = 0.45;

/// Glass-mode alpha for the search box fill (EV:811-819).
const double kEmojiGlassSearchFillAlpha = 0.06;

/// Glass-mode alpha for the category selector pill (ETS:743-752).
const double kEmojiGlassSelectorAlpha = 0.05;

/// Glass-mode alpha for section-header titles (SSNC:77).
const double kEmojiGlassHeaderTextAlpha = 0.6;

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// The three pager pages, in Java page order — **0 emoji, 1 GIFs,
/// 2 stickers** (EV:196, 2810). `EmojiPanelTab.values[i].index == i` is the
/// page index.
enum EmojiPanelTab {
  /// Page 0 — the emoji grid.
  emoji,

  /// Page 1 — GIF search/sections.
  gifs,

  /// Page 2 — sticker sets.
  stickers,
}

/// Programmatic state of an [EmojiPanel]: the active page and the current
/// category-strip selection.
///
/// The controller is the source of truth; the panel listens and animates
/// toward it (the ViewPager `setCurrentItem` analog). User taps on the
/// bottom strip write back into the controller.
///
/// [categoryIndex] is the selection the consumer forwards to the current
/// page's [EmojiCategoryStrip]; each page owns its own strip on Android
/// (EV Part B4), so consumers typically reset it when [activeTab] changes.
class EmojiPanelController extends ChangeNotifier {
  /// Creates a controller with an initial [activeTab] and [categoryIndex].
  EmojiPanelController({
    EmojiPanelTab activeTab = EmojiPanelTab.emoji,
    int categoryIndex = 0,
  })  : assert(categoryIndex >= 0),
        // Keeps the public parameter names on private fields.
        // ignore: prefer_initializing_formals
        _activeTab = activeTab,
        // ignore: prefer_initializing_formals
        _categoryIndex = categoryIndex;

  EmojiPanelTab _activeTab;
  int _categoryIndex;
  bool _tabChangeAnimated = true;

  /// The committed active page.
  EmojiPanelTab get activeTab => _activeTab;

  /// The committed category selection of the current page's strip.
  int get categoryIndex => _categoryIndex;

  /// Whether the latest [selectTab] wants the 350ms slide or a snap.
  bool get tabChangeAnimated => _tabChangeAnimated;

  /// Selects a page. [animated] false snaps (initial binding, restores);
  /// true runs the pager slide + indicator settle
  /// (350ms EASE_OUT_QUINT, PSTS:249-250).
  void selectTab(EmojiPanelTab tab, {bool animated = true}) {
    if (_activeTab == tab) {
      return;
    }
    _activeTab = tab;
    _tabChangeAnimated = animated;
    notifyListeners();
  }

  /// Selects a category-strip entry (the `onTabClick` of the strips).
  void selectCategory(int index) {
    assert(index >= 0);
    if (_categoryIndex == index) {
      return;
    }
    _categoryIndex = index;
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

Color _resolveColor(
  BuildContext context,
  TelegramResources? resources,
  int key,
) {
  if (resources != null) {
    return resources.getColor(key);
  }
  return TelegramTheme.colorOf(context, key);
}

/// `glass_defaultIcon` at one of the fixed glass alphas (EV:10135-10139).
Color _glassIcon(BuildContext context, TelegramResources? r, double alpha) =>
    Color(multAlpha(
      _resolveColor(context, r, TelegramColorKey.glass_defaultIcon).toARGB32(),
      alpha,
    ));

/// SRC_IN tint applied to an icon slot, like the Android selector drawables
/// / `setColorFilter(color, PorterDuff.Mode.SRC_IN)`.
Widget _tinted(Color color, Widget child) => ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: child,
    );

// ---------------------------------------------------------------------------
// Bottom type-tab strip (emoji / GIFs / stickers switcher)
// ---------------------------------------------------------------------------

/// The bottom type-tab strip — the port of `typeTabs`
/// (`PagerSlidingTabStrip`, EV:2697-2705):
///
/// - centered, WRAP x 48dp; own padding (4, 11, 4, 11); per-tab horizontal
///   padding 11dp around a 24x24 icon slot;
/// - selected indicator: a pill behind the active tab spanning the strip's
///   inner height (26dp) and the full tab width (content +11dp each side),
///   radius height/2, color `chat_emojiPanelIconSelected` at alpha 20/255
///   (EV:2701, PSTS:295-300); position tracks the page and settles with
///   350ms EASE_OUT_QUINT (PSTS:249-250);
/// - glass background: `GlassPresets.emojiViewButton`, radius 18dp, glass
///   padding 6dp (EV:2923-2951);
/// - icon tints: `glass_defaultIcon` @40% unselected / @80% selected in
///   glass mode, else `chat_emojiBottomPanelIcon` /
///   `chat_emojiPanelIconSelected` (EV:1583-1585, 5903-5904).
class EmojiPanelTabStrip extends StatefulWidget {
  /// Creates the strip; [icons] are the `smiles_tab_*` glyph slots, one per
  /// page.
  const EmojiPanelTabStrip({
    super.key,
    required this.icons,
    this.index = 0,
    this.onSelected,
    this.glass = true,
    this.resources,
  })  : assert(icons.length > 0),
        assert(index >= 0 && index < icons.length);

  /// One tab-cell width: 24dp icon + 2 x 11dp tab padding (EV:2703).
  static const double tabWidth =
      kEmojiPanelTabIconSize + 2 * kEmojiPanelTabPadding;

  /// The icon glyph slots, in page order (typically 3: emoji, GIFs,
  /// stickers). Rendered inside a 24x24 tinted slot.
  final List<Widget> icons;

  /// The selected page index; changes animate the indicator (and the icon
  /// tints) over 350ms EASE_OUT_QUINT.
  final int index;

  /// Fired on a tab tap, even on the already-selected tab (Android
  /// click-through).
  final ValueChanged<int>? onSelected;

  /// Whether the glass design is active (`LiteMode.FLAG_LIQUID_GLASS`):
  /// glass background pill + `glass_defaultIcon` tints.
  final bool glass;

  /// Per-surface palette override (the `resourcesProvider` convention).
  final TelegramResources? resources;

  /// The strip content width: strip padding + tabs (EV:2704).
  double get contentWidth =>
      kEmojiPanelStripPadding.horizontal + icons.length * tabWidth;

  @override
  State<EmojiPanelTabStrip> createState() => EmojiPanelTabStripState();
}

/// State of [EmojiPanelTabStrip]; public for test access to [debugPosition].
class EmojiPanelTabStripState extends State<EmojiPanelTabStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _position;

  /// The animated indicator position in tab-index space (the pager
  /// `position + positionOffset` analog, PSTS:273-289).
  @visibleForTesting
  double get debugPosition => _position.value;

  @override
  void initState() {
    super.initState();
    _position = AnimationController.unbounded(
      vsync: this,
      value: widget.index.toDouble(),
    );
  }

  @override
  void didUpdateWidget(EmojiPanelTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      // `AnimatedFloat(350, EASE_OUT_QUINT)` retarget (PSTS:249-250).
      _position.animateTo(
        widget.index.toDouble(),
        duration: kEmojiPanelSwitchDuration,
        curve: TgCurves.easeOutQuint,
      );
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TelegramResources? r = widget.resources;
    final Color unselected = widget.glass
        ? _glassIcon(context, r, kEmojiGlassIconUnselectedAlpha)
        : _resolveColor(context, r, TelegramColorKey.chat_emojiBottomPanelIcon);
    final Color selected = widget.glass
        ? _glassIcon(context, r, kEmojiGlassIconSelectedAlpha)
        : _resolveColor(
            context, r, TelegramColorKey.chat_emojiPanelIconSelected);
    // `setAlphaComponent(chat_emojiPanelIconSelected, 20)` (EV:2701).
    final Color indicator = _resolveColor(
      context,
      r,
      TelegramColorKey.chat_emojiPanelIconSelected,
    ).withAlpha(kEmojiPanelIndicatorAlpha);

    Widget content = SizedBox(
      width: widget.contentWidth,
      height: kEmojiPanelStripHeight,
      child: AnimatedBuilder(
        animation: _position,
        builder: (BuildContext context, Widget? child) {
          final double position = _position.value;
          return CustomPaint(
            painter: EmojiPanelTabIndicatorPainter(
              position: position,
              tabCount: widget.icons.length,
              color: indicator,
            ),
            child: Padding(
              padding: kEmojiPanelStripPadding,
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < widget.icons.length; i++)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onSelected?.call(i),
                      child: SizedBox(
                        width: EmojiPanelTabStrip.tabWidth,
                        height: kEmojiPanelStripHeight -
                            kEmojiPanelStripPadding.vertical,
                        child: Center(
                          child: SizedBox(
                            width: kEmojiPanelTabIconSize,
                            height: kEmojiPanelTabIconSize,
                            child: _tinted(
                              blendArgb(
                                unselected,
                                selected,
                                (1.0 - (position - i).abs()).clamp(0.0, 1.0),
                              ),
                              widget.icons[i],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (widget.glass) {
      // `blurredBackgroundDrawableFactory.create(typeTabs, emojiViewButton)`
      // radius 18, glass padding 6 (EV:2923-2951).
      content = GlassPanel(
        preset: GlassPresets.emojiViewButton,
        borderRadius: const GlassRadii.all(kEmojiPanelStripGlassRadius),
        padding: kEmojiPanelStripGlassPadding,
        resources: widget.resources,
        child: content,
      );
    }

    return SizedBox(
      height: kEmojiPanelStripHeight,
      child: Center(child: content),
    );
  }
}

/// The indicator pill of [EmojiPanelTabStrip] — the `onDraw` indicator pass
/// of `PagerSlidingTabStrip` (PSTS:295-300): a round-rect from
/// `lineLeft - 11dp` to `lineRight + 11dp` spanning paddingTop to
/// height - paddingBottom, radius height/2, offset by the strip's left
/// padding.
class EmojiPanelTabIndicatorPainter extends CustomPainter {
  /// Creates the painter for the given animated [position].
  const EmojiPanelTabIndicatorPainter({
    required this.position,
    required this.tabCount,
    required this.color,
  });

  /// Indicator position in tab-index space (tracks page scroll live,
  /// PSTS:273-289).
  final double position;

  /// Number of tabs (clamps [position]).
  final int tabCount;

  /// `chat_emojiPanelIconSelected` at alpha 20/255 (EV:2701).
  final Color color;

  /// The indicator rect at [position].
  ///
  /// `lineLeft = tab.left + tabPadding` and the rect inflates by 11dp each
  /// side (PSTS:259-260, 297) — with the 11dp tab padding that is exactly
  /// the full tab-cell bounds, linear in the position, so:
  /// `left = stripPaddingLeft + position * tabWidth`.
  Rect rectFor(double position) {
    final double clamped =
        tabCount <= 1 ? 0.0 : position.clamp(0.0, (tabCount - 1).toDouble());
    final double left =
        kEmojiPanelStripPadding.left + clamped * EmojiPanelTabStrip.tabWidth;
    return Rect.fromLTRB(
      left,
      kEmojiPanelStripPadding.top,
      left + EmojiPanelTabStrip.tabWidth,
      kEmojiPanelStripHeight - kEmojiPanelStripPadding.bottom,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = rectFor(position);
    canvas.drawRRect(
      // radius = height / 2 (PSTS:299).
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2.0)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(EmojiPanelTabIndicatorPainter oldDelegate) =>
      position != oldDelegate.position ||
      tabCount != oldDelegate.tabCount ||
      color != oldDelegate.color;
}

// ---------------------------------------------------------------------------
// Category strip
// ---------------------------------------------------------------------------

/// The per-page category strip — the port of the `EmojiTabsStrip` chrome
/// (spec B4): a 36dp-tall row of 30x30 icon buttons with 11dp content
/// padding, leftover width distributed as equal per-button margins
/// (ETS:196), a sliding selector pill (350ms EASE_OUT_QUINT with the
/// mid-flight squash, ETS:702-711), and a 1px bottom shadow line
/// (`chat_emojiPanelShadowLine`, EV:1967-1973).
///
/// Icons are slots; content (recents, categories, pack thumbnails) is the
/// consumer's. When the buttons overflow the width the strip scrolls
/// horizontally (the `ScrollableHorizontalWidget` base of ETS).
class EmojiCategoryStrip extends StatefulWidget {
  /// Creates the strip.
  const EmojiCategoryStrip({
    super.key,
    required this.icons,
    this.selectedIndex = 0,
    this.onSelected,
    this.glass = true,
    this.showShadowLine = true,
    this.resources,
  })  : assert(icons.length > 0),
        assert(selectedIndex >= 0 && selectedIndex < icons.length);

  /// The bottom shadow line's [Key] (one per strip instance in a test tree).
  static const Key shadowKey = Key('EmojiCategoryStrip.shadow');

  /// Category icon slots (recent + categories + packs), each centered in a
  /// 30x30 button (ETS:1237).
  final List<Widget> icons;

  /// The selected button; changes slide the pill over 350ms EASE_OUT_QUINT.
  final int selectedIndex;

  /// Fired on a button tap.
  final ValueChanged<int>? onSelected;

  /// Glass design: selector `glass_defaultIcon` @5% with radius height/2,
  /// icon tints @40/80%; else `chat_emojiPanelIcon` @18% selector radius
  /// 8dp and `chat_emojiPanelIcon` / `chat_emojiPanelIconSelected` tints
  /// (ETS:268-272, 743-752).
  final bool glass;

  /// Whether to draw the `chat_emojiPanelShadowLine` 1px bottom line
  /// (EV:1967-1973).
  final bool showShadowLine;

  /// Per-surface palette override.
  final TelegramResources? resources;

  /// Per-slot stride: the 30dp button plus the equal share of leftover
  /// width, distributed as margins (ETS:196). When the natural content
  /// (11 + count*30 + 11) overflows [availableWidth] the stride stays 30
  /// and the strip scrolls.
  static double slotStride(int count, double availableWidth) {
    if (count <= 0) {
      return 0.0;
    }
    final double natural =
        2 * kEmojiCategoryContentPadding + count * kEmojiCategoryButtonSize;
    final double extra = math.max(0.0, availableWidth - natural) / count;
    return kEmojiCategoryButtonSize + extra;
  }

  /// Left edge of button [index]'s 30x30 bounds (margins split evenly around
  /// each button).
  static double slotLeft(int index, int count, double availableWidth) {
    final double stride = slotStride(count, availableWidth);
    final double margin = (stride - kEmojiCategoryButtonSize) / 2.0;
    return kEmojiCategoryContentPadding + index * stride + margin;
  }

  /// Center x of button [index].
  static double slotCenterX(int index, int count, double availableWidth) =>
      slotLeft(index, count, availableWidth) + kEmojiCategoryButtonSize / 2.0;

  /// The selector pill rect while sliding from [fromCenterX] to [toCenterX]
  /// at time-fraction [t] (curve already applied):
  /// width x(1 + 0.3*isMiddle), height x(1 - 0.05*isMiddle) with
  /// `isMiddle = 4t(1-t)` (ETS:702-711, 255-259); vertically centered in
  /// the 36dp strip.
  static Rect selectorRectFor({
    required double fromCenterX,
    required double toCenterX,
    required double t,
  }) {
    final double centerX = lerpDouble(fromCenterX, toCenterX, t)!;
    final double isMiddle =
        fromCenterX == toCenterX ? 0.0 : 4.0 * t * (1.0 - t);
    final double width = kEmojiCategoryButtonSize *
        (1.0 + kEmojiCategorySquashWidthFactor * isMiddle);
    final double height = kEmojiCategoryButtonSize *
        (1.0 - kEmojiCategorySquashHeightFactor * isMiddle);
    return Rect.fromCenter(
      center: Offset(centerX, kEmojiCategoryStripHeight / 2.0),
      width: width,
      height: height,
    );
  }

  @override
  State<EmojiCategoryStrip> createState() => EmojiCategoryStripState();
}

/// State of [EmojiCategoryStrip]; public for test access to
/// [debugSelectorRect].
class EmojiCategoryStripState extends State<EmojiCategoryStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _move;
  late final Animation<double> _t;
  late int _fromIndex;
  double _contentWidth = 0.0;

  /// The current selector pill rect (strip-content coordinates).
  @visibleForTesting
  Rect get debugSelectorRect => EmojiCategoryStrip.selectorRectFor(
        fromCenterX: EmojiCategoryStrip.slotCenterX(
            _fromIndex, widget.icons.length, _contentWidth),
        toCenterX: EmojiCategoryStrip.slotCenterX(
            widget.selectedIndex, widget.icons.length, _contentWidth),
        t: _t.value,
      );

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.selectedIndex;
    _move = AnimationController(
      vsync: this,
      duration: kEmojiPanelSwitchDuration,
      value: 1.0,
    );
    // `ValueAnimator` 350ms EASE_OUT_QUINT (ETS:702-711).
    _t = CurvedAnimation(parent: _move, curve: TgCurves.easeOutQuint);
  }

  @override
  void didUpdateWidget(EmojiCategoryStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _fromIndex = oldWidget.selectedIndex;
      _move.forward(from: 0.0);
    } else if (widget.icons.length != oldWidget.icons.length &&
        _fromIndex >= widget.icons.length) {
      _fromIndex = widget.selectedIndex;
    }
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TelegramResources? r = widget.resources;
    final int count = widget.icons.length;
    // Selector color (ETS:743-752).
    final Color selector = widget.glass
        ? _glassIcon(context, r, kEmojiGlassSelectorAlpha)
        : Color(multAlpha(
            _resolveColor(context, r, TelegramColorKey.chat_emojiPanelIcon)
                .toARGB32(),
            0.18,
          ));
    final Color unselected = widget.glass
        ? _glassIcon(context, r, kEmojiGlassIconUnselectedAlpha)
        : _resolveColor(context, r, TelegramColorKey.chat_emojiPanelIcon);
    final Color selected = widget.glass
        ? _glassIcon(context, r, kEmojiGlassIconSelectedAlpha)
        : _resolveColor(
            context, r, TelegramColorKey.chat_emojiPanelIconSelected);
    return SizedBox(
      height: kEmojiCategoryStripHeight,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double natural = 2 * kEmojiCategoryContentPadding +
              count * kEmojiCategoryButtonSize;
          final double available =
              constraints.maxWidth.isFinite ? constraints.maxWidth : natural;
          final double contentWidth = math.max(natural, available);
          _contentWidth = contentWidth;

          final Widget content = SizedBox(
            width: contentWidth,
            height: kEmojiCategoryStripHeight,
            child: AnimatedBuilder(
              animation: _move,
              builder: (BuildContext context, Widget? child) {
                return CustomPaint(
                  painter: EmojiCategorySelectorPainter(
                    fromCenterX: EmojiCategoryStrip.slotCenterX(
                        _fromIndex, count, contentWidth),
                    toCenterX: EmojiCategoryStrip.slotCenterX(
                        widget.selectedIndex, count, contentWidth),
                    t: _t.value,
                    color: selector,
                    glass: widget.glass,
                  ),
                  child: child,
                );
              },
              child: Stack(
                children: <Widget>[
                  for (int i = 0; i < count; i++)
                    Positioned(
                      left: EmojiCategoryStrip.slotLeft(i, count, contentWidth),
                      top: (kEmojiCategoryStripHeight -
                              kEmojiCategoryButtonSize) /
                          2.0,
                      width: kEmojiCategoryButtonSize,
                      height: kEmojiCategoryButtonSize,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onSelected?.call(i),
                        child: Center(
                          child: _tinted(
                            i == widget.selectedIndex ? selected : unselected,
                            widget.icons[i],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );

          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: content,
                ),
              ),
              if (widget.showShadowLine)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 1,
                  child: ColoredBox(
                    key: EmojiCategoryStrip.shadowKey,
                    color: _resolveColor(
                      context,
                      r,
                      TelegramColorKey.chat_emojiPanelShadowLine,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The category selector pill — the `EmojiTabsStrip` select pass
/// (ETS:255-272): color from the strip, radius 8dp (glass: height/2), the
/// slide squash of [EmojiCategoryStrip.selectorRectFor].
class EmojiCategorySelectorPainter extends CustomPainter {
  /// Creates the painter for one animation frame.
  const EmojiCategorySelectorPainter({
    required this.fromCenterX,
    required this.toCenterX,
    required this.t,
    required this.color,
    required this.glass,
  });

  /// Center of the outgoing button.
  final double fromCenterX;

  /// Center of the incoming button.
  final double toCenterX;

  /// Curved time-fraction 0..1.
  final double t;

  /// Selector fill (ETS:743-752).
  final Color color;

  /// Glass design flag: radius height/2 instead of 8dp (ETS:268-272).
  final bool glass;

  /// The pill rect this frame.
  Rect get rect => EmojiCategoryStrip.selectorRectFor(
        fromCenterX: fromCenterX,
        toCenterX: toCenterX,
        t: t,
      );

  /// The pill corner radius (ETS:268-272).
  double get radius =>
      glass ? rect.height / 2.0 : kEmojiCategorySelectorRadius;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(EmojiCategorySelectorPainter oldDelegate) =>
      fromCenterX != oldDelegate.fromCenterX ||
      toCenterX != oldDelegate.toCenterX ||
      t != oldDelegate.t ||
      color != oldDelegate.color ||
      glass != oldDelegate.glass;
}

// ---------------------------------------------------------------------------
// Search row
// ---------------------------------------------------------------------------

/// The per-page search row — the port of `SearchField` chrome (EV:796-1010):
/// a 50dp row hosting a 36dp round box (radius 18dp; margins left/right
/// 10dp, top 6dp — 8dp for the sticker-type field — bottom 8dp), the 36x36
/// leading search-icon slot, the 16dp input/hint, and the 36x36 trailing
/// clear-button slot.
///
/// The input widget, search-state icon, clear drawable, and the in-box
/// category mini-strip (EV:826-841, 966-993) are content — pass them via
/// [input]/[leading]/[trailing] or leave null for the hint-only chrome.
class EmojiSearchRow extends StatelessWidget {
  /// Creates the row.
  const EmojiSearchRow({
    super.key,
    this.hintText = 'Search',
    this.input,
    this.leading,
    this.trailing,
    this.stickerType = false,
    this.drawBackground = true,
    this.glass = true,
    this.resources,
  });

  /// The round box's [Key] (one row per test tree).
  static const Key boxKey = Key('EmojiSearchRow.box');

  /// Hint shown when [input] is null ("Search", EV:884).
  final String hintText;

  /// The consumer's input widget (e.g. an `EditableText`); replaces the
  /// hint.
  final Widget? input;

  /// The `SearchStateDrawable` slot, 36x36 at the left (EV:845-868),
  /// tinted `glass_defaultIcon` @40% (glass) else `chat_emojiSearchIcon`.
  final Widget? leading;

  /// The clear-button slot, 36x36 at the right (`CloseProgressDrawable2`,
  /// EV:937-963), same tint as [leading].
  final Widget? trailing;

  /// Sticker-type field: box top margin 8dp instead of 6dp (EV:815).
  final bool stickerType;

  /// `shouldDrawBackground`: the `chat_emojiPanelBackground` fill plus the
  /// bottom `chat_emojiPanelShadowLine` (EV:800-809).
  final bool drawBackground;

  /// Glass design flag (fills/tints, EV:811-819, 845-868).
  final bool glass;

  /// Per-surface palette override.
  final TelegramResources? resources;

  @override
  Widget build(BuildContext context) {
    final TelegramResources? r = resources;
    final Color boxFill = glass
        ? _glassIcon(context, r, kEmojiGlassSearchFillAlpha)
        : _resolveColor(context, r, TelegramColorKey.chat_emojiSearchBackground);
    final Color iconColor = glass
        ? _glassIcon(context, r, kEmojiGlassIconUnselectedAlpha)
        : _resolveColor(context, r, TelegramColorKey.chat_emojiSearchIcon);
    final Color hintColor = glass
        ? _glassIcon(context, r, kEmojiGlassIconHintAlpha)
        : _resolveColor(context, r, TelegramColorKey.chat_emojiSearchIcon);

    return SizedBox(
      height: kEmojiSearchRowHeight,
      child: Stack(
        children: <Widget>[
          if (drawBackground) ...<Widget>[
            Positioned.fill(
              child: ColoredBox(
                color: _resolveColor(
                    context, r, TelegramColorKey.chat_emojiPanelBackground),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 1,
              child: ColoredBox(
                color: _resolveColor(
                    context, r, TelegramColorKey.chat_emojiPanelShadowLine),
              ),
            ),
          ],
          Positioned(
            left: kEmojiSearchBoxMarginHorizontal,
            right: kEmojiSearchBoxMarginHorizontal,
            top: stickerType
                ? kEmojiSearchBoxMarginTopSticker
                : kEmojiSearchBoxMarginTop,
            height: kEmojiSearchBoxHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kEmojiSearchBoxRadius),
              child: DecoratedBox(
                key: boxKey,
                decoration: BoxDecoration(
                  color: boxFill,
                  borderRadius: BorderRadius.circular(kEmojiSearchBoxRadius),
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: kEmojiSearchBoxHeight,
                      height: kEmojiSearchBoxHeight,
                      child: leading == null
                          ? null
                          : Center(child: _tinted(iconColor, leading!)),
                    ),
                    Expanded(
                      child: input ??
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              hintText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: kEmojiSearchTextSize,
                                color: hintColor,
                              ),
                            ),
                          ),
                    ),
                    SizedBox(
                      width: kEmojiSearchBoxHeight,
                      height: kEmojiSearchBoxHeight,
                      child: trailing == null
                          ? null
                          : Center(child: _tinted(iconColor, trailing!)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trending / section header
// ---------------------------------------------------------------------------

/// A section / trending header row — the port of the `StickerSetNameCell`
/// chrome (SSNC:60-113, 234): a 27dp row with a 15dp bold single-line title
/// in `chat_emojiPanelStickerSetName` (glass: `glass_defaultIcon` @60%),
/// content margins (left 15dp / 5dp emoji-variant, top 5dp, right 25dp /
/// 15dp), an optional unread dot (radius 3dp,
/// `chat_emojiPanelNewTrending`, EV:6512-6515) and an optional [trailing]
/// slot (the "ADD"/edit chip is content, SSNC:97-101).
class EmojiTrendingHeader extends StatelessWidget {
  /// Creates the header.
  const EmojiTrendingHeader({
    super.key,
    required this.title,
    this.emojiVariant = false,
    this.showUnreadDot = false,
    this.trailing,
    this.glass = true,
    this.resources,
  });

  /// The unread dot's [Key].
  static const Key dotKey = Key('EmojiTrendingHeader.dot');

  /// The section title (15dp bold, SSNC:78-80).
  final String title;

  /// Emoji-variant margins: left 5 / right 15 instead of 15 / 25
  /// (SSNC:88-89).
  final bool emojiVariant;

  /// Draws the 3dp-radius `chat_emojiPanelNewTrending` dot after the title
  /// (EV:6512-6515, 1617-1618).
  final bool showUnreadDot;

  /// Optional trailing slot, end-aligned (the ADD/edit chip, SSNC:97-101).
  final Widget? trailing;

  /// Glass design flag: title `glass_defaultIcon` @60% (SSNC:77).
  final bool glass;

  /// Per-surface palette override.
  final TelegramResources? resources;

  @override
  Widget build(BuildContext context) {
    final TelegramResources? r = resources;
    final Color titleColor = glass
        ? _glassIcon(context, r, kEmojiGlassHeaderTextAlpha)
        : _resolveColor(
            context, r, TelegramColorKey.chat_emojiPanelStickerSetName);
    return SizedBox(
      height: kEmojiTrendingHeaderHeight,
      child: Padding(
        // createFrame margins (SSNC:88-89).
        padding: EdgeInsets.fromLTRB(
          emojiVariant ? 5.0 : 15.0,
          5.0,
          emojiVariant ? 15.0 : 25.0,
          0.0,
        ),
        child: Row(
          children: <Widget>[
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: kEmojiTrendingHeaderTextSize,
                  fontFamily: 'RobotoMedium',
                  package: 'telegram_ui',
                  fontWeight: FontWeight.w500,
                  color: titleColor,
                ),
              ),
            ),
            if (showUnreadDot)
              Padding(
                padding: const EdgeInsets.only(left: 4.0),
                child: SizedBox(
                  width: kEmojiTrendingDotRadius * 2,
                  height: kEmojiTrendingDotRadius * 2,
                  child: DecoratedBox(
                    key: dotKey,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _resolveColor(
                        context,
                        r,
                        TelegramColorKey.chat_emojiPanelNewTrending,
                      ),
                    ),
                  ),
                ),
              ),
            if (trailing != null) ...<Widget>[
              const Spacer(),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The panel
// ---------------------------------------------------------------------------

/// The emoji/GIF/sticker panel shell — the port of the `EmojiView` chrome
/// (spec Part B):
///
/// - **Height rules** (B1): the panel never self-measures; its height is
///   [height] (the saved IME height, default [kEmojiPanelDefaultHeight])
///   plus [bottomInset] (the navigation-bar inset, `setBottomInset`,
///   EV:2956-2972). Grids the consumer places in the body slots should
///   reserve [gridBottomPadding] of bottom padding so content scrolls under
///   the bottom strip.
/// - **Structure** (B2): three pages — 0 emoji, 1 GIFs, 2 stickers
///   (EV:196, 2810) — as [WidgetBuilder] slots, plus the centered
///   [EmojiPanelTabStrip] and optional 48x48 side-button slots at the
///   bottom band's corners (backspace right, search left; EV:2679,
///   2769-2776).
/// - **Tab switch** (B8): the pages slide horizontally and the strip
///   indicator tracks the same 350ms EASE_OUT_QUINT clock (PSTS:249-300);
///   a page is kept alive but offstage once fully out of view
///   (`checkGridVisibility`, EV:2709).
/// - Background: `chat_emojiPanelBackground` (EV:807, 1752), with the
///   bottom gradient fade of the same color over the nav-bar zone
///   (EV:4552-4560).
class EmojiPanel extends StatefulWidget {
  /// Creates the panel.
  const EmojiPanel({
    super.key,
    this.controller,
    this.initialTab = EmojiPanelTab.emoji,
    this.height = kEmojiPanelDefaultHeight,
    this.bottomInset = 0.0,
    this.emojiBuilder,
    this.gifsBuilder,
    this.stickersBuilder,
    this.tabIcons,
    this.leftButton,
    this.rightButton,
    this.onTabSelected,
    this.glass = true,
    this.resources,
  })  : assert(height > 0),
        assert(bottomInset >= 0),
        assert(tabIcons == null || tabIcons.length == 3);

  /// External controller; when null the panel owns one seeded with
  /// [initialTab].
  final EmojiPanelController? controller;

  /// Initial page for the internal controller (ignored when [controller]
  /// is given).
  final EmojiPanelTab initialTab;

  /// The imposed panel height (the saved IME height `kbd_height`, default
  /// 200dp; CAEV:12597-12621), excluding [bottomInset].
  final double height;

  /// Navigation-bar inset below the panel; the bottom band translates up by
  /// it and the nav-bar zone gets the background fade (EV:2956-2972,
  /// 4448-4453, 4552-4560).
  final double bottomInset;

  /// Page 0 body slot (the emoji grid). Null renders empty chrome.
  final WidgetBuilder? emojiBuilder;

  /// Page 1 body slot (the GIF grid).
  final WidgetBuilder? gifsBuilder;

  /// Page 2 body slot (the sticker grid).
  final WidgetBuilder? stickersBuilder;

  /// The three `smiles_tab_*` glyph slots for the bottom strip, in page
  /// order; null renders empty 24x24 slots.
  final List<Widget>? tabIcons;

  /// Bottom-left 48x48 button slot (the hidden-by-default search button,
  /// EV:2769-2776).
  final Widget? leftButton;

  /// Bottom-right 48x48 button slot (backspace on page 0, sticker settings
  /// on page 2 — the swap is the consumer's; EV:2679, 2689, 2744-2745).
  final Widget? rightButton;

  /// Fired when the user taps a strip tab (even the active one, Android
  /// click-through). Programmatic controller changes do NOT fire it.
  final ValueChanged<EmojiPanelTab>? onTabSelected;

  /// Glass design flag, forwarded to the strip.
  final bool glass;

  /// Per-surface palette override.
  final TelegramResources? resources;

  /// The grid bottom padding for a given nav inset: `44dp + inset`
  /// (EV:2956-2972).
  static double gridBottomPadding(double bottomInset) =>
      kEmojiPanelGridBottomPadding + bottomInset;

  /// The [Key] wrapping [tab]'s body slot subtree.
  static Key bodyKeyFor(EmojiPanelTab tab) =>
      ValueKey<String>('EmojiPanel.body.${tab.name}');

  @override
  State<EmojiPanel> createState() => EmojiPanelState();
}

/// State of [EmojiPanel]; public for test access to [debugPage].
class EmojiPanelState extends State<EmojiPanel>
    with SingleTickerProviderStateMixin {
  EmojiPanelController? _internalController;
  late final AnimationController _page;
  int _pageTarget = 0;

  /// The effective controller (widget-supplied or internal).
  EmojiPanelController get controller =>
      widget.controller ?? _internalController!;

  /// The animated page position (0 emoji .. 2 stickers).
  @visibleForTesting
  double get debugPage => _page.value;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = EmojiPanelController(activeTab: widget.initialTab);
    }
    controller.addListener(_onControllerChanged);
    _pageTarget = controller.activeTab.index;
    _page = AnimationController.unbounded(
      vsync: this,
      value: _pageTarget.toDouble(),
    );
  }

  @override
  void didUpdateWidget(EmojiPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      (oldWidget.controller ?? _internalController)
          ?.removeListener(_onControllerChanged);
      if (widget.controller != null) {
        _internalController?.dispose();
        _internalController = null;
      } else {
        _internalController ??= EmojiPanelController(
          activeTab: oldWidget.controller?.activeTab ?? widget.initialTab,
        );
      }
      controller.addListener(_onControllerChanged);
      _applyPage(controller.activeTab.index, animated: false);
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    _internalController?.dispose();
    _page.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final int target = controller.activeTab.index;
    if (target != _pageTarget) {
      _applyPage(target, animated: controller.tabChangeAnimated);
    }
    // categoryIndex changes are the consumer's (per-page strips); the panel
    // itself only tracks the page.
    setState(() {});
  }

  void _applyPage(int target, {required bool animated}) {
    _pageTarget = target;
    if (animated) {
      // The pager slide + indicator settle share the 350ms EASE_OUT_QUINT
      // clock (PSTS:249-250).
      _page.animateTo(
        target.toDouble(),
        duration: kEmojiPanelSwitchDuration,
        curve: TgCurves.easeOutQuint,
      );
    } else {
      _page.stop();
      _page.value = target.toDouble();
    }
  }

  /// The strip tap handler — commits into the controller and fires
  /// [EmojiPanel.onTabSelected] (Android click-through fires even on the
  /// active tab).
  void _onStripSelected(int index) {
    final EmojiPanelTab tab = EmojiPanelTab.values[index];
    controller.selectTab(tab);
    widget.onTabSelected?.call(tab);
  }

  WidgetBuilder? _builderFor(EmojiPanelTab tab) => switch (tab) {
        EmojiPanelTab.emoji => widget.emojiBuilder,
        EmojiPanelTab.gifs => widget.gifsBuilder,
        EmojiPanelTab.stickers => widget.stickersBuilder,
      };

  @override
  Widget build(BuildContext context) {
    final Color background = _resolveColor(
      context,
      widget.resources,
      TelegramColorKey.chat_emojiPanelBackground,
    );

    // Bodies built once per build; the slide closure below only re-wraps
    // them, so slot subtree state survives every animation tick.
    final List<Widget> bodies = <Widget>[
      for (final EmojiPanelTab tab in EmojiPanelTab.values)
        KeyedSubtree(
          key: EmojiPanel.bodyKeyFor(tab),
          child: _builderFor(tab)?.call(context) ?? const SizedBox.expand(),
        ),
    ];

    return SizedBox(
      height: widget.height + widget.bottomInset,
      child: ColoredBox(
        color: background,
        child: ClipRect(
          child: Stack(
            children: <Widget>[
              // Pages slide horizontally like the ViewPager; a fully
              // off-screen page goes offstage but keeps its state
              // (`checkGridVisibility`, EV:2709).
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _page,
                  builder: (BuildContext context, Widget? child) {
                    final double page = _page.value;
                    return Stack(
                      children: <Widget>[
                        for (int i = 0; i < bodies.length; i++)
                          Positioned.fill(
                            child: Visibility(
                              visible: (i - page).abs() < 1.0,
                              maintainState: true,
                              child: FractionalTranslation(
                                translation: Offset(i - page, 0.0),
                                child: bodies[i],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              // Nav-bar zone fade of the panel background (EV:4552-4560).
              if (widget.bottomInset > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: widget.bottomInset,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            background.withAlpha(0),
                            background,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // The 48dp bottom band, lifted above the nav inset
              // (EV:2678, 4448-4453).
              Positioned(
                left: 0,
                right: 0,
                bottom: widget.bottomInset,
                height: kEmojiPanelStripHeight,
                child: Stack(
                  children: <Widget>[
                    Center(
                      child: EmojiPanelTabStrip(
                        icons: widget.tabIcons ??
                            const <Widget>[
                              SizedBox.expand(),
                              SizedBox.expand(),
                              SizedBox.expand(),
                            ],
                        index: controller.activeTab.index,
                        onSelected: _onStripSelected,
                        glass: widget.glass,
                        resources: widget.resources,
                      ),
                    ),
                    if (widget.leftButton != null)
                      Positioned(
                        left: kEmojiPanelSideButtonMargin,
                        bottom: 0,
                        width: kEmojiPanelSideButtonSize,
                        height: kEmojiPanelSideButtonSize,
                        child: widget.leftButton!,
                      ),
                    if (widget.rightButton != null)
                      Positioned(
                        right: kEmojiPanelSideButtonMargin,
                        bottom: 0,
                        width: kEmojiPanelSideButtonSize,
                        height: kEmojiPanelSideButtonSize,
                        child: widget.rightButton!,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
