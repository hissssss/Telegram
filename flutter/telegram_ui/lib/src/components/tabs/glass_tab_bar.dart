// The floating glass main tab bar — the flagship surface of the port
// (ARCHITECTURE.md section 6, row "GlassTabBar").
//
// Ports, with every constant cited:
//
// - container geometry — `ui/MainTabsActivity.java` +
//   `ui/DialogsActivity.java`: bar height 56dp / outer margin 8dp /
//   with-margins 72dp (DialogsActivity.java:289-291); row padding 12dp
//   (= margin + 4, MainTabsActivity.java:287); max view width dp(328 + 16)
//   = 344dp (MainTabsActivity.java:288); glass background radius 28dp
//   (= 56/2, MainTabsActivity.java:343) with drawable padding
//   dp(8 - 0.334) ~= 7.666dp (MainTabsActivity.java:344); placed 72dp tall,
//   bottom|center-h, above the navigation bar
//   (MainTabsActivity.java:357-361, 824);
// - show/hide — `BoolAnimator(380ms, EASE_OUT_QUINT)`
//   (MainTabsActivity.java:102-103): hidden = translationY +40dp, alpha =
//   factor (MainTabsActivity.java:955-968; the scale computed on line 962 is
//   never applied and is not ported);
// - row layout — `ui/MainTabsLayout.java`: text auto-fit passes at sizes
//   {12, 12, 10}dp with per-tab horizontal paddings {16, 8, 4}dp
//   (MainTabsLayout.java:46-47), min total row width 320dp
//   (MainTabsLayout.java:69), width equalization / scale-to-fit
//   (MainTabsLayout.java:59-154);
// - long-press "lens" drag — custom selector `glass_tabSelected` at 9%
//   alpha, stadium radius = row height / 2 (MainTabsLayout.java:289,
//   310-324); position/offset springs at STIFFNESS_MEDIUM (1500) /
//   DAMPING_RATIO_LOW_BOUNCY (0.75) (MainTabsLayout.java:356-369); whole-bar
//   scale 1.019 over 380ms EASE_OUT_QUINT (MainTabsLayout.java:436-439);
//   long-press trigger at 75% of the system duration
//   (MainTabsLayout.java:484-486); selector restore delay 450ms
//   (MainTabsLayout.java:493);
// - pressed-bar pivot warp — radial mapping `mappedR = 1.5r / (r + 0.5)`
//   with the pivot-Y lerp extrapolated x3 (MainTabsLayout.java:563-604).
//
// The glass surface itself is `GlassPanel(preset: GlassPresets.mainTabs)` at
// the liquid tier with default `LiquidGlassSettings` — exactly the Android
// wiring `iBlur3FactoryGlass.create(tabsView,
// BlurredBackgroundProviderImpl.mainTabs(...))` (MainTabsActivity.java:342).
library;

import 'dart:async' show Timer;
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;
import 'package:flutter/widgets.dart';

import '../../foundation/color_math.dart';
import '../../foundation/tg_curves.dart';
import '../../glass/geometry.dart';
import '../../glass/glass_panel.dart';
import '../../glass/presets.dart';
import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';
import 'glass_tab.dart';
import 'tab_contract.dart';
import 'tab_icon.dart';

/// `MAIN_TABS_HEIGHT = 56` dp — the visible glass pill height
/// (DialogsActivity.java:289).
const double kGlassTabBarHeight = 56.0;

/// `MAIN_TABS_MARGIN = 8` dp — the outer margin around the pill
/// (DialogsActivity.java:290).
const double kGlassTabBarMargin = 8.0;

/// `MAIN_TABS_HEIGHT_WITH_MARGINS = 72` dp — the bar's layout height,
/// pill + margins (DialogsActivity.java:291).
const double kGlassTabBarHeightWithMargins = 72.0;

/// Glass background corner radius: `dp(MAIN_TABS_HEIGHT / 2f)` = 28dp
/// (MainTabsActivity.java:343).
const double kGlassTabBarRadius = 28.0;

/// Glass drawable padding: `dp(MAIN_TABS_MARGIN - 0.334f)` ~= 7.666dp — the
/// inset of the glass visuals from the 72dp bar bounds, i.e. the 8dp margin
/// minus a stroke compensation (MainTabsActivity.java:344).
const double kGlassTabBarPanelPadding = kGlassTabBarMargin - 0.334;

/// Row padding on all sides: `dp(MAIN_TABS_MARGIN + 4)` = 12dp
/// (MainTabsActivity.java:287).
const double kGlassTabBarViewPadding = 12.0;

/// Tab row height: 72 - 2*12 = 48dp (`tabHeight`, MainTabsLayout.java:62).
const double kGlassTabBarRowHeight =
    kGlassTabBarHeightWithMargins - kGlassTabBarViewPadding * 2;

/// Maximum bar width: `dp(328 + MAIN_TABS_MARGIN * 2)` = 344dp
/// (MainTabsActivity.java:288).
const double kGlassTabBarMaxWidth = 344.0;

/// Minimum total row width: `dp(320)` (MainTabsLayout.java:69).
const double kGlassTabBarMinRowWidth = 320.0;

/// Auto-fit label text sizes per pass: `{12f, 12f, 10f}` dp
/// (`PASS_TEXT_SIZES_DP`, MainTabsLayout.java:46).
const List<double> kGlassTabBarPassTextSizes = <double>[12.0, 12.0, 10.0];

/// Auto-fit per-tab horizontal paddings per pass: `{16, 8, 4}` dp
/// (`PASS_PADDINGS_DP`, MainTabsLayout.java:47).
const List<double> kGlassTabBarPassPaddings = <double>[16.0, 8.0, 4.0];

/// Hidden-state translation: `hiddenY = normalY + dp(40)`
/// (MainTabsActivity.java:959).
const double kGlassTabBarHiddenOffsetY = 40.0;

/// Show/hide duration: `BoolAnimator(..., EASE_OUT_QUINT, 380)`
/// (MainTabsActivity.java:102-103).
const Duration kGlassTabBarVisibilityDuration = Duration(milliseconds: 380);

/// Long-press whole-bar scale: `lerp(1, 1.019f, factor)`
/// (MainTabsLayout.java:437-438).
const double kGlassTabBarLongPressScale = 1.019;

/// Long-press scale duration: `BoolAnimator(..., EASE_OUT_QUINT, 380)`
/// (MainTabsLayout.java:439).
const Duration kGlassTabBarScaleDuration = Duration(milliseconds: 380);

/// Long-press trigger: 75% of the 500ms system long-press duration —
/// `getLongPressDuration() * 750 / 1000` (MainTabsLayout.java:484-486).
const Duration kGlassTabBarLongPressDuration = Duration(milliseconds: 375);

/// Delay before children resume drawing their own selection pill after a
/// lens drag: `runOnUIThread(restoreDrawSelector, 450)`
/// (MainTabsLayout.java:493, 507).
const Duration kGlassTabBarSelectorRestoreDelay = Duration(milliseconds: 450);

/// Lens selector alpha: `multAlpha(glass_tabSelected, 0.09f)`
/// (MainTabsLayout.java:289).
const double kGlassTabBarSelectorAlpha = 0.09;

/// The lens selector springs: `STIFFNESS_MEDIUM` (= 1500) with
/// `DAMPING_RATIO_LOW_BOUNCY` (= 0.75) on both the position and the grab
/// offset (MainTabsLayout.java:356-359, 366-368), mapped onto Flutter's
/// `SpringDescription.withDampingRatio(mass: 1, stiffness: 1500,
/// ratio: 0.75)`.
final SpringDescription kGlassTabBarSelectorSpring =
    SpringDescription.withDampingRatio(mass: 1.0, stiffness: 1500.0, ratio: 0.75);

/// Port of `MainTabsLayout.clampXToChildrenCenters`
/// (MainTabsLayout.java:613-643): clamps [x] to the range spanned by the tab
/// [centers]; returns [x] unchanged when there are none.
double glassTabBarClampToCenters(double x, List<double> centers) {
  if (centers.isEmpty) {
    return x;
  }
  double min = double.infinity;
  double max = double.negativeInfinity;
  for (final double c in centers) {
    if (c < min) {
      min = c;
    }
    if (c > max) {
      max = c;
    }
  }
  if (x < min) {
    return min;
  }
  if (x > max) {
    return max;
  }
  return x;
}

/// Port of `MainTabsLayout.findNearestVisibleChildByX`
/// (MainTabsLayout.java:645-670): the index whose center is nearest [x]
/// (first wins on ties, like the Java strict `<`); -1 when [centers] is
/// empty.
int glassTabBarNearestIndex(double x, List<double> centers) {
  int nearest = -1;
  double nearestDistance = double.infinity;
  for (int i = 0; i < centers.length; i++) {
    final double distance = (centers[i] - x).abs();
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearest = i;
    }
  }
  return nearest;
}

/// Port of `MainTabsLayout.getInterpolatedWidthByX`
/// (MainTabsLayout.java:672-718): the lens selector width at position [x] —
/// the linear interpolation between the widths of the two tabs whose centers
/// bracket [x] (or the single neighbor's width past either end).
double glassTabBarInterpolatedWidth(
  double x,
  List<double> centers,
  List<double> widths,
) {
  assert(centers.length == widths.length);
  int left = -1;
  int right = -1;
  for (int i = 0; i < centers.length; i++) {
    final double centerX = centers[i];
    if (centerX <= x && (left == -1 || centerX > centers[left])) {
      left = i;
    }
    if (centerX >= x && (right == -1 || centerX < centers[right])) {
      right = i;
    }
  }
  if (left == -1 && right == -1) {
    return 0.0;
  }
  if (left == -1) {
    return widths[right];
  }
  if (right == -1) {
    return widths[left];
  }
  final double leftX = centers[left];
  final double rightX = centers[right];
  if (left == right || leftX == rightX) {
    return widths[left];
  }
  final double ratio = (x - leftX) / (rightX - leftX);
  return lerpDouble(widths[left], widths[right], ratio)!;
}

/// Port of `MainTabsLayout.checkPivot` (MainTabsLayout.java:563-604): warps
/// the touch [position] into the scale pivot of the long-pressed bar.
///
/// The touch offset from the center is normalized against the half-extents,
/// its radius mapped through `mappedR = 1.5r / (r + 0.5)`
/// (MainTabsLayout.java:589), and the resulting pivot lerped from the center
/// with factor 1 on X but **3** on Y (an extrapolation, Android's `lerp` is
/// unclamped; MainTabsLayout.java:599-600).
Offset glassTabBarWarpPivot(Size size, Offset position) {
  final double w = size.width;
  final double h = size.height;
  if (w <= 0.0 || h <= 0.0) {
    // Java early-returns without touching the pivot (MainTabsLayout.java:567).
    return Offset(w / 2.0, h / 2.0);
  }
  final double cx = w * 0.5;
  final double cy = h * 0.5;
  final double dx = position.dx - cx;
  final double dy = position.dy - cy;
  final double nx = dx / (w * 0.5);
  final double ny = dy / (h * 0.5);
  final double r = math.sqrt(nx * nx + ny * ny);
  double pivotX;
  double pivotY;
  if (r > 1e-4) {
    final double mappedR = 1.5 * r / (r + 0.5);
    final double scale = mappedR / r;
    pivotX = cx + dx * scale;
    pivotY = cy + dy * scale;
  } else {
    pivotX = cx;
    pivotY = cy;
  }
  pivotX = lerpDouble(cx, pivotX, 1.0)!; // MainTabsLayout.java:599
  pivotY = lerpDouble(cy, pivotY, 3.0)!; // MainTabsLayout.java:600
  return Offset(pivotX, pivotY);
}

/// The resolved tab-row layout — the output of the `MainTabsLayout.onMeasure`
/// algorithm (MainTabsLayout.java:58-154) as a pure value.
///
/// All values are logical px (dp). [widths] are rounded to whole px like the
/// Java `Math.round` (MainTabsLayout.java:141), so [rowWidth] (their sum,
/// the measured content width of MainTabsLayout.java:145) may differ from
/// the available width by sub-pixel rounding, exactly as on Android.
@immutable
class GlassTabRowLayout {
  /// Creates a resolved layout; prefer [compute].
  const GlassTabRowLayout({
    required this.passIndex,
    required this.textSize,
    required this.tabPadding,
    required this.widths,
    required this.lefts,
    required this.rowWidth,
  });

  /// The chosen auto-fit pass, 0..2.
  final int passIndex;

  /// Label text size of the chosen pass —
  /// `kGlassTabBarPassTextSizes[passIndex]`.
  final double textSize;

  /// Per-tab horizontal padding of the chosen pass —
  /// `kGlassTabBarPassPaddings[passIndex]`.
  final double tabPadding;

  /// Final tab widths, whole logical px (`tabsWidth`,
  /// MainTabsLayout.java:141).
  final List<double> widths;

  /// Tab left positions relative to the row (padding excluded;
  /// `tabsLeftPos`, MainTabsLayout.java:142).
  final List<double> lefts;

  /// Sum of [widths] — the measured row content width
  /// (MainTabsLayout.java:145).
  final double rowWidth;

  /// Tab center x positions relative to the row.
  List<double> get centers => <double>[
        for (int i = 0; i < widths.length; i++) lefts[i] + widths[i] / 2.0,
      ];

  /// Runs the `onMeasure` algorithm (MainTabsLayout.java:58-154):
  ///
  ///  1. **Pass selection** (lines 71-90): for each pass, measure every
  ///     label at the pass text size ([measureTextWidths], memoized across
  ///     passes sharing a size like `lastMeasuredTextSize`) and pick the
  ///     first pass whose total `textWidth + 2*padding` fits [maxRowWidth]
  ///     (the last pass is chosen unconditionally).
  ///  2. **Weights** (lines 94-119): a tab wider than the equal share
  ///     `maxRowWidth / tabCount` gets weight 0, others 1; all-zero weights
  ///     reset to 1.
  ///  3. **Fit** (lines 121-133): if the total overflows, every width is
  ///     scaled by `maxRowWidth / total`; if it undershoots
  ///     `min(minRowWidth, maxRowWidth)`, the deficit is distributed to
  ///     weight-1 tabs.
  ///  4. **Rounding** (lines 135-144): widths round to whole px and pack
  ///     left to right.
  static GlassTabRowLayout compute({
    required int tabCount,
    required List<double> Function(double textSizeDp) measureTextWidths,
    required double maxRowWidth,
    double minRowWidth = kGlassTabBarMinRowWidth,
  }) {
    assert(tabCount >= 0);
    if (tabCount == 0) {
      return GlassTabRowLayout(
        passIndex: 0,
        textSize: kGlassTabBarPassTextSizes[0],
        tabPadding: kGlassTabBarPassPaddings[0],
        widths: const <double>[],
        lefts: const <double>[],
        rowWidth: 0.0,
      );
    }
    final double maxTotal = math.max(0.0, maxRowWidth);

    // Pass selection (MainTabsLayout.java:71-90).
    int chosenPass = kGlassTabBarPassTextSizes.length - 1;
    List<double> textWidths = const <double>[];
    double lastMeasuredTextSize = -1.0;
    for (int pass = 0; pass < kGlassTabBarPassTextSizes.length; pass++) {
      if (kGlassTabBarPassTextSizes[pass] != lastMeasuredTextSize) {
        textWidths = measureTextWidths(kGlassTabBarPassTextSizes[pass]);
        assert(
          textWidths.length == tabCount,
          'measureTextWidths must return one width per tab '
          '(${textWidths.length} != $tabCount).',
        );
        lastMeasuredTextSize = kGlassTabBarPassTextSizes[pass];
      }
      final double padding = kGlassTabBarPassPaddings[pass];
      double total = 0.0;
      for (final double w in textWidths) {
        total += w + padding * 2;
      }
      final bool fits = total <= maxTotal;
      if (fits || pass == kGlassTabBarPassTextSizes.length - 1) {
        chosenPass = pass;
        break;
      }
    }
    final double tabPadding = kGlassTabBarPassPaddings[chosenPass];

    // Weights against the equal share (MainTabsLayout.java:94-119).
    final double maxTabTextWidthIfEq = maxTotal / tabCount - tabPadding * 2;
    final List<double> withMargin = <double>[
      for (final double w in textWidths) w + tabPadding * 2,
    ];
    final List<int> weights = <int>[
      for (final double w in withMargin)
        w > maxTabTextWidthIfEq + tabPadding * 2 ? 0 : 1,
    ];
    double totalWidth = 0.0;
    int totalWeight = 0;
    for (int i = 0; i < tabCount; i++) {
      totalWidth += withMargin[i];
      totalWeight += weights[i];
    }
    if (totalWeight == 0) {
      for (int i = 0; i < tabCount; i++) {
        weights[i] = 1;
      }
      totalWeight = tabCount;
    }

    // Scale down / grow up (MainTabsLayout.java:121-133).
    final double minTotal = math.min(minRowWidth, maxTotal);
    if (totalWidth > maxTotal && totalWidth > 0) {
      final double m = maxTotal / totalWidth;
      for (int i = 0; i < tabCount; i++) {
        withMargin[i] *= m;
      }
    } else if (totalWidth < minTotal) {
      final double growPer = (minTotal - totalWidth) / totalWeight;
      for (int i = 0; i < tabCount; i++) {
        withMargin[i] += growPer * weights[i];
      }
    }

    // Round and pack (MainTabsLayout.java:135-144).
    final List<double> widths = <double>[];
    final List<double> lefts = <double>[];
    double l = 0.0;
    for (int i = 0; i < tabCount; i++) {
      final double w = withMargin[i].roundToDouble();
      widths.add(w);
      lefts.add(l);
      l += w;
    }
    return GlassTabRowLayout(
      passIndex: chosenPass,
      textSize: kGlassTabBarPassTextSizes[chosenPass],
      tabPadding: tabPadding,
      widths: List<double>.unmodifiable(widths),
      lefts: List<double>.unmodifiable(lefts),
      rowWidth: l,
    );
  }

  @override
  String toString() =>
      'GlassTabRowLayout(pass: $passIndex, textSize: $textSize, '
      'widths: $widths, rowWidth: $rowWidth)';
}

/// One tab of a [GlassTabBar]: identity, label, optional icon/avatar, and a
/// badge count — the declarative analog of the `GlassTabView` instances
/// `MainTabsActivity` adds to its `MainTabsLayout`
/// (MainTabsActivity.java:285-328).
@immutable
class GlassTabBarItem {
  /// Creates a tab item. At most one of [icon] and [avatar] may be given.
  const GlassTabBarItem({
    required this.id,
    required this.label,
    this.icon,
    this.avatar,
    this.badgeCount = 0,
  }) : assert(
          icon == null || avatar == null,
          'Provide icon OR avatar, not both.',
        );

  /// Stable identity of the tab (used to key the slot subtree so slot state
  /// survives reordering).
  final Object id;

  /// Single-line label; also the input of the bar's auto-fit measurement
  /// (`MainTabsLayout.Tab.measureTextWidth`, MainTabsLayout.java:156-160).
  final String label;

  /// Optional 24x24 icon; the default slot builder renders a `GlassTab`
  /// main tab with it (`createMainTab`, GlassTabView.java:400-412).
  final TabIcon? icon;

  /// Optional avatar widget; the default slot builder renders a
  /// `GlassTab.avatar` with it (`createAvatar`, GlassTabView.java:414-433).
  final Widget? avatar;

  /// Unread counter forwarded to the slot via [TabSlotData.badgeCount].
  final int badgeCount;
}

/// Builds the visual cell for one tab slot. The default implementation
/// composes `GlassTab`; supply your own to render anything else against the
/// [TabSlotData] contract.
typedef GlassTabSlotBuilder = Widget Function(
  BuildContext context,
  GlassTabBarItem item,
  TabSlotData slot,
);

/// Programmatic control of a [GlassTabBar]: selection (`select` snaps,
/// `animateTo` animates — the two arms of Java's
/// `setTabSelected(tab, animated)`, MainTabsLayout.java:258-265) and
/// visibility (`show`/`hide` — `animatorTabsVisible.setValue(value,
/// animated)`, MainTabsActivity.java:102-103).
///
/// The controller is the source of truth for the committed selection and
/// visibility; the bar listens and animates toward it. User gestures on the
/// bar write back into the controller.
class GlassTabBarController extends ChangeNotifier {
  /// Creates a controller with an initial selection ([index]) and
  /// [visible]-ness.
  GlassTabBarController({int index = 0, bool visible = true})
      : assert(index >= 0),
        _index = index,
        // Keeps the public parameter names (index/visible) on private fields.
        // ignore: prefer_initializing_formals
        _visible = visible;

  int _index;
  bool _visible;
  bool _selectionAnimated = false;
  bool _visibilityAnimated = true;

  /// The committed selected tab index.
  int get index => _index;

  /// Whether the bar is (or is animating toward) shown.
  bool get visible => _visible;

  /// Whether the latest selection change wants animation (`animateTo` vs
  /// [select]).
  bool get selectionAnimated => _selectionAnimated;

  /// Whether the latest visibility change wants animation.
  bool get visibilityAnimated => _visibilityAnimated;

  /// Selects [index] without animation (the `animated = false` arm of
  /// `setTabSelected`).
  void select(int index) => _setIndex(index, animated: false);

  /// Animates the selection to [index] (320ms decelerate on the tab factors,
  /// GlassTabView.java:67).
  void animateTo(int index) => _setIndex(index, animated: true);

  void _setIndex(int index, {required bool animated}) {
    assert(index >= 0);
    if (_index == index) {
      return;
    }
    _index = index;
    _selectionAnimated = animated;
    notifyListeners();
  }

  /// Shows the bar — factor animates to 1 over 380ms EASE_OUT_QUINT
  /// (MainTabsActivity.java:102-103) unless [animated] is false.
  void show({bool animated = true}) => _setVisible(true, animated: animated);

  /// Hides the bar — translationY +40dp, alpha 0
  /// (MainTabsActivity.java:955-968).
  void hide({bool animated = true}) => _setVisible(false, animated: animated);

  void _setVisible(bool visible, {required bool animated}) {
    if (_visible == visible) {
      return;
    }
    _visible = visible;
    _visibilityAnimated = animated;
    notifyListeners();
  }
}

/// The floating glass main tab bar (ARCHITECTURE.md section 6 "GlassTabBar"):
/// a 72dp-tall, bottom-docked bar whose 56dp glass pill (radius 28dp, max
/// width 344dp, centered) hosts equal-ized tab slots with label auto-fit,
/// tap selection, the long-press lens drag, and animated show/hide.
///
/// ### Placement
///
/// The bar is [kGlassTabBarHeightWithMargins] (72dp) tall with the 8dp
/// visual margins *inside* that box (via the glass padding), so hosts dock
/// it flush to the bottom safe-area edge: `bottom = safeAreaBottom`, giving
/// the Android placement `pill bottom = navigationBar + 8dp`
/// (MainTabsActivity.java:359, 824). Scrollable content behind it should
/// reserve `safeAreaBottom + 72dp` (MainTabsActivity.java:192, 805-815).
///
/// ### Composition
///
/// The surface is a `GlassPanel(preset: GlassPresets.mainTabs)` at the
/// scope-resolved (liquid-first) tier with default `LiquidGlassSettings`
/// (MainTabsActivity.java:340-345). Slots are built via [tabBuilder]
/// against the [TabSlotData] contract; the default builder composes
/// [GlassTab] (icon/avatar items) or a plain label.
///
/// Like every component in this package, the bar takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention).
class GlassTabBar extends StatefulWidget {
  /// Creates the bar.
  const GlassTabBar({
    super.key,
    required this.items,
    this.controller,
    this.initialIndex = 0,
    this.onSelected,
    this.tabBuilder,
    this.resources,
  }) : assert(initialIndex >= 0);

  /// The tabs, in visual order (LTR, matching Android's LinearLayout row).
  final List<GlassTabBarItem> items;

  /// External controller; when null the bar owns an internal one seeded with
  /// [initialIndex].
  final GlassTabBarController? controller;

  /// Initial selection for the internal controller (ignored when
  /// [controller] is given).
  final int initialIndex;

  /// Fired when the user commits a selection — a tap, or a lens-drag
  /// start/release (`performClick`, MainTabsLayout.java:405-407, 494-496).
  /// Fires even when the tapped tab is already selected, like Android's
  /// click-through. Programmatic controller changes do NOT fire it.
  final ValueChanged<int>? onSelected;

  /// Slot builder; defaults to a [GlassTab]-composing builder.
  final GlassTabSlotBuilder? tabBuilder;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  /// Measures [label] at [textSize] logical px with the tab-label typeface
  /// (Roboto Medium w500, bundled by this package) — the analog of
  /// `GlassTabView.measureTextWidth(textSizeDp)` which measures the label
  /// `TextPaint` at `dp(textSizeDp)` (GlassTabView.java:523-529).
  ///
  /// Text scaling is deliberately not applied: Android sizes these labels in
  /// dp (`COMPLEX_UNIT_DIP`, GlassTabView.java:88), not sp.
  static double measureLabelWidth(String label, double textSize) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: textSize,
          fontFamily: GlassTab.unselectedFontFamily,
          package: 'telegram_ui',
          fontWeight: FontWeight.w500,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  State<GlassTabBar> createState() => GlassTabBarState();
}

/// State of [GlassTabBar]; public for test access to the `debug*` probes.
class GlassTabBarState extends State<GlassTabBar>
    with TickerProviderStateMixin {
  GlassTabBarController? _internalController;

  /// The effective controller (widget-supplied or internal).
  GlassTabBarController get controller =>
      widget.controller ?? _internalController!;

  /// Show/hide factor: 1 shown, 0 hidden (`animatorTabsVisible`,
  /// MainTabsActivity.java:102-103).
  late final AnimationController _visibility;

  /// Long-press bar scale factor 0..1 (`animatorIsScaled`,
  /// MainTabsLayout.java:436-439).
  late final AnimationController _scale;

  /// Lens position (`animatedLongSelectedViewCenterX`,
  /// MainTabsLayout.java:371) — bar-local x, driven directly during the drag
  /// and by the spring on release.
  late final AnimationController _selectorCenterX;

  /// Lens grab offset (`animatedLongSelectedViewOffsetX`,
  /// MainTabsLayout.java:372) — springs to 0 from the initial
  /// selected-center-minus-finger delta.
  late final AnimationController _selectorOffsetX;

  /// Scale pivot from the warp (`checkPivot`), bar-local.
  final ValueNotifier<Offset?> _pivot = ValueNotifier<Offset?>(null);

  /// One factor per slot, driven like the tab's `BoolAnimator(320ms,
  /// DECELERATE)` (GlassTabView.java:67): each retarget lerps from the
  /// current factor toward the target with the decelerate curve applied to
  /// normalized *time* (the `AnimatedFloat`/`BoolAnimator` semantics).
  final List<AnimationController> _selectionControllers =
      <AnimationController>[];

  int _visualIndex = 0;
  bool _visibleTarget = true;
  bool _dragSelectorActive = false;
  bool _isInLongPress = false;
  int _lastDragIndex = -1;
  double _lastDragX = 0.0;
  Timer? _selectorRestoreTimer;

  GlassTabRowLayout? _layout;
  List<double> _slotCenters = const <double>[];
  Size _barSize = Size.zero;

  /// The row layout of the last build.
  @visibleForTesting
  GlassTabRowLayout? get debugRowLayout => _layout;

  /// Bar-local tab center x positions of the last build.
  @visibleForTesting
  List<double> get debugSlotCenters => List<double>.unmodifiable(_slotCenters);

  /// Current show/hide factor (1 shown).
  @visibleForTesting
  double get debugVisibilityFactor => _visibility.value;

  /// Current whole-bar scale, 1..1.019.
  @visibleForTesting
  double get debugBarScale =>
      lerpDouble(1.0, kGlassTabBarLongPressScale, _scale.value)!;

  /// Whether the lens selector is being drawn by the bar.
  @visibleForTesting
  bool get debugDragSelectorActive => _dragSelectorActive;

  /// Drawn lens center (bar-local x): position + grab offset.
  @visibleForTesting
  double get debugSelectorCenterX =>
      _selectorCenterX.value + _selectorOffsetX.value;

  /// The visually selected index (follows the lens during a drag).
  @visibleForTesting
  int get debugVisualIndex => _visualIndex;

  /// The scale pivot of the current/last long press, bar-local.
  @visibleForTesting
  Offset? get debugScalePivot => _pivot.value;

  /// The bar-driven selection animation of slot [index].
  @visibleForTesting
  Animation<double> debugSelectionAnimation(int index) =>
      _selectionControllers[index];

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = GlassTabBarController(index: widget.initialIndex);
    }
    controller.addListener(_onControllerChanged);
    _visualIndex = widget.items.isEmpty
        ? 0
        : controller.index.clamp(0, widget.items.length - 1);
    _visibleTarget = controller.visible;
    _visibility =
        AnimationController(vsync: this, value: _visibleTarget ? 1.0 : 0.0);
    _scale = AnimationController(vsync: this);
    _selectorCenterX = AnimationController.unbounded(vsync: this);
    _selectorOffsetX = AnimationController.unbounded(vsync: this);
    _ensureSlotAnimators();
  }

  @override
  void didUpdateWidget(GlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      (oldWidget.controller ?? _internalController)
          ?.removeListener(_onControllerChanged);
      if (widget.controller != null) {
        _internalController?.dispose();
        _internalController = null;
      } else {
        _internalController ??= GlassTabBarController(
          index: oldWidget.controller?.index ?? widget.initialIndex,
          visible: oldWidget.controller?.visible ?? true,
        );
      }
      controller.addListener(_onControllerChanged);
      _applyVisualSelection(controller.index, animated: false);
      _applyVisibility(controller.visible, animated: false);
    }
    if (widget.items.length != oldWidget.items.length) {
      _ensureSlotAnimators();
      if (widget.items.isNotEmpty && _visualIndex >= widget.items.length) {
        _applyVisualSelection(widget.items.length - 1, animated: false);
      }
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    _internalController?.dispose();
    _selectorRestoreTimer?.cancel();
    for (final AnimationController c in _selectionControllers) {
      c.dispose();
    }
    _pivot.dispose();
    _visibility.dispose();
    _scale.dispose();
    _selectorCenterX.dispose();
    _selectorOffsetX.dispose();
    super.dispose();
  }

  void _ensureSlotAnimators() {
    final int count = widget.items.length;
    while (_selectionControllers.length > count) {
      _selectionControllers.removeLast().dispose();
    }
    while (_selectionControllers.length < count) {
      final int index = _selectionControllers.length;
      _selectionControllers.add(AnimationController(
        vsync: this,
        duration: GlassTab.selectionDuration,
        value: index == _visualIndex ? 1.0 : 0.0,
      ));
    }
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final GlassTabBarController c = controller;
    if (c.index != _visualIndex) {
      _applyVisualSelection(c.index, animated: c.selectionAnimated);
    }
    if (c.visible != _visibleTarget) {
      _applyVisibility(c.visible, animated: c.visibilityAnimated);
    }
  }

  /// Port of `setTabSelected` (MainTabsLayout.java:258-265): drives every
  /// slot's selection factor toward its new target.
  void _applyVisualSelection(int index, {required bool animated}) {
    if (widget.items.isEmpty) {
      return;
    }
    final int clamped = index.clamp(0, widget.items.length - 1);
    final bool changed = _visualIndex != clamped;
    _visualIndex = clamped;
    for (int i = 0; i < _selectionControllers.length; i++) {
      final AnimationController c = _selectionControllers[i];
      final double target = i == clamped ? 1.0 : 0.0;
      if (animated) {
        // BoolAnimator semantics: lerp from the current factor toward the
        // target over the full duration with DECELERATE applied to time
        // (GlassTabView.java:67).
        c.animateTo(
          target,
          duration: GlassTab.selectionDuration,
          curve: TgCurves.decelerate,
        );
      } else {
        c.stop();
        c.value = target;
      }
    }
    if (changed && mounted) {
      setState(() {});
    }
  }

  /// Port of `checkUi_tabsPosition` (MainTabsActivity.java:955-969): factor
  /// toward 1 (shown) / 0 (hidden = translationY +40dp, alpha 0) over 380ms
  /// EASE_OUT_QUINT.
  void _applyVisibility(bool visible, {required bool animated}) {
    _visibleTarget = visible;
    final double target = visible ? 1.0 : 0.0;
    if (animated) {
      _visibility.animateTo(
        target,
        duration: kGlassTabBarVisibilityDuration,
        curve: TgCurves.easeOutQuint,
      );
    } else {
      _visibility.stop();
      _visibility.value = target;
    }
  }

  /// The `performClick` analog: commits [index] into the controller and
  /// fires [GlassTabBar.onSelected].
  void _commit(int index) {
    if (controller.index != index) {
      controller.animateTo(index);
    }
    widget.onSelected?.call(index);
  }

  Color _resolveColor(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  // -- Gestures ------------------------------------------------------------

  /// Port of `findChildUnder` (MainTabsLayout.java:382-394): the slot whose
  /// bounds contain the bar-local [position], or null.
  int? _slotAt(Offset position) {
    final GlassTabRowLayout? layout = _layout;
    if (layout == null) {
      return null;
    }
    for (int i = 0; i < layout.widths.length; i++) {
      final Rect rect = Rect.fromLTWH(
        kGlassTabBarViewPadding + layout.lefts[i],
        kGlassTabBarViewPadding,
        layout.widths[i],
        kGlassTabBarRowHeight,
      );
      if (rect.contains(position)) {
        return i;
      }
    }
    return null;
  }

  void _onTapUp(TapUpDetails details) {
    final int? hit = _slotAt(details.localPosition);
    if (hit != null) {
      _commit(hit);
    }
  }

  void _updatePivot(Offset position) {
    _pivot.value = glassTabBarWarpPivot(_barSize, position);
  }

  /// `onLongPressRequestedAt` + `checkLongMove(x, y, true, false)`
  /// (MainTabsLayout.java:465-474, 396-429).
  void _onLongPressStart(LongPressStartDetails details) {
    if (_slotCenters.isEmpty) {
      return;
    }
    _selectorRestoreTimer?.cancel();
    _selectorRestoreTimer = null;
    _updatePivot(details.localPosition);
    _isInLongPress = true;

    final double x =
        glassTabBarClampToCenters(details.localPosition.dx, _slotCenters);
    _lastDragX = x;
    final int found = glassTabBarNearestIndex(x, _slotCenters);

    // The selector spawns on the currently selected tab; its grab offset
    // (selected center - finger) springs to 0 (MainTabsLayout.java:399-410).
    final double selectedCenter =
        _visualIndex >= 0 && _visualIndex < _slotCenters.length
            ? _slotCenters[_visualIndex]
            : x;
    _selectorCenterX.stop();
    _selectorCenterX.value = x;
    _selectorOffsetX.stop();
    _selectorOffsetX.value = selectedCenter - x;
    _selectorOffsetX.animateWith(SpringSimulation(
      kGlassTabBarSelectorSpring,
      _selectorOffsetX.value,
      0.0,
      0.0,
    ));

    if (found >= 0 && found != _visualIndex) {
      _commit(found); // `found.performClick()` (MainTabsLayout.java:405-407).
    }
    if (found >= 0) {
      _lastDragIndex = found;
      _applyVisualSelection(found, animated: true);
    }
    setState(() {
      _dragSelectorActive = true;
    });
    // `animatorIsScaled.setValue(true, true)` (MainTabsLayout.java:513-514).
    _scale.animateTo(
      1.0,
      duration: kGlassTabBarScaleDuration,
      curve: TgCurves.easeOutQuint,
    );
  }

  /// `onLongPressMove` + `checkLongMove(x, y, false, false)`
  /// (MainTabsLayout.java:477-481, 412-419).
  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isInLongPress || _slotCenters.isEmpty) {
      return;
    }
    _updatePivot(details.localPosition);
    final double x =
        glassTabBarClampToCenters(details.localPosition.dx, _slotCenters);
    _lastDragX = x;
    _selectorCenterX.stop();
    _selectorCenterX.value = x;
    final int found = glassTabBarNearestIndex(x, _slotCenters);
    if (found >= 0) {
      _lastDragIndex = found;
      _applyVisualSelection(found, animated: true);
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _updatePivot(details.localPosition);
    _finishDrag(details.localPosition.dx, commit: true);
  }

  void _onLongPressCancel() {
    _finishDrag(_lastDragX, commit: false);
  }

  /// `onLongPressFinish` / `onLongPressCancelled` +
  /// `checkLongMove(x, y, false, true)` (MainTabsLayout.java:489-511,
  /// 417-428).
  void _finishDrag(double rawX, {required bool commit}) {
    if (!_isInLongPress) {
      return;
    }
    _isInLongPress = false;
    final double x = glassTabBarClampToCenters(rawX, _slotCenters);
    final int found = glassTabBarNearestIndex(x, _slotCenters);
    if (found >= 0) {
      _lastDragIndex = found;
      _applyVisualSelection(found, animated: true);
      // Spring the selector to the settled tab center
      // (MainTabsLayout.java:421-427).
      _selectorCenterX.animateWith(SpringSimulation(
        kGlassTabBarSelectorSpring,
        _selectorCenterX.value,
        _slotCenters[found],
        _selectorCenterX.velocity,
      ));
    }
    // `runOnUIThread(restoreDrawSelector, 450)` (MainTabsLayout.java:493).
    _selectorRestoreTimer?.cancel();
    _selectorRestoreTimer = Timer(kGlassTabBarSelectorRestoreDelay, () {
      _selectorRestoreTimer = null;
      if (mounted) {
        setState(() {
          _dragSelectorActive = false;
        });
      }
    });
    if (commit && _lastDragIndex >= 0) {
      // `lastLongSelectedView.performClick()` (MainTabsLayout.java:494-496).
      _commit(_lastDragIndex);
    }
    _lastDragIndex = -1;
    // `animatorIsScaled.setValue(false, true)` (MainTabsLayout.java:526-527).
    _scale.animateTo(
      0.0,
      duration: kGlassTabBarScaleDuration,
      curve: TgCurves.easeOutQuint,
    );
  }

  // -- Build ---------------------------------------------------------------

  Widget _defaultTabBuilder(
    BuildContext context,
    GlassTabBarItem item,
    TabSlotData slot,
  ) {
    final TabIcon? icon = item.icon;
    if (icon != null) {
      return GlassTab(
        label: item.label,
        icon: icon,
        selected: slot.selected,
        skipSelectionPill: slot.skipSelector,
        resources: widget.resources,
      );
    }
    final Widget? avatar = item.avatar;
    if (avatar != null) {
      return GlassTab.avatar(
        label: item.label,
        avatar: avatar,
        selected: slot.selected,
        skipSelectionPill: slot.skipSelector,
        resources: widget.resources,
      );
    }
    return _FallbackTabLabel(slot: slot, resources: widget.resources);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kGlassTabBarHeightWithMargins,
      child: LayoutBuilder(builder: _buildBar),
    );
  }

  Widget _buildBar(BuildContext context, BoxConstraints constraints) {
    final List<GlassTabBarItem> items = widget.items;

    // Incoming width clamped to 344dp (`setMaxWidth`,
    // MainTabsActivity.java:288; MainTabsLayout.java:64-66), minus the 12dp
    // row paddings (MainTabsLayout.java:68).
    final double available = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : kGlassTabBarMaxWidth;
    final double clampedWidth = math.min(available, kGlassTabBarMaxWidth);
    final double maxRowWidth =
        math.max(0.0, clampedWidth - kGlassTabBarViewPadding * 2);

    final GlassTabRowLayout layout = GlassTabRowLayout.compute(
      tabCount: items.length,
      maxRowWidth: maxRowWidth,
      measureTextWidths: (double textSize) => <double>[
        for (final GlassTabBarItem item in items)
          GlassTabBar.measureLabelWidth(item.label, textSize),
      ],
    );
    _layout = layout;
    _slotCenters = <double>[
      for (int i = 0; i < layout.widths.length; i++)
        kGlassTabBarViewPadding + layout.lefts[i] + layout.widths[i] / 2.0,
    ];
    // Measured width = row + paddings (MainTabsLayout.java:145).
    final double barWidth = layout.rowWidth + kGlassTabBarViewPadding * 2;
    _barSize = Size(barWidth, kGlassTabBarHeightWithMargins);

    // `selectorPaint.setColor(multAlpha(glass_tabSelected, 0.09f))`
    // (MainTabsLayout.java:289).
    final Color selectorColor = Color(multAlpha(
      _resolveColor(context, TelegramColorKey.glass_tabSelected).toARGB32(),
      kGlassTabBarSelectorAlpha,
    ));

    final GlassTabSlotBuilder slotBuilder =
        widget.tabBuilder ?? _defaultTabBuilder;

    final Widget row = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        // The lens selector paints under the children, like the
        // `dispatchDraw` prologue (MainTabsLayout.java:310-324).
        if (_dragSelectorActive)
          Positioned.fill(
            child: CustomPaint(
              painter: _LensSelectorPainter(
                repaint: Listenable.merge(
                  <Listenable>[_selectorCenterX, _selectorOffsetX],
                ),
                centerX: _selectorCenterX,
                offsetX: _selectorOffsetX,
                color: selectorColor,
                centers: _slotCenters,
                widths: layout.widths,
              ),
            ),
          ),
        for (int i = 0; i < items.length && i < layout.widths.length; i++)
          Positioned(
            left: kGlassTabBarViewPadding + layout.lefts[i],
            top: kGlassTabBarViewPadding,
            width: layout.widths[i],
            height: kGlassTabBarRowHeight,
            child: KeyedSubtree(
              key: ValueKey<Object>(items[i].id),
              child: slotBuilder(
                context,
                items[i],
                TabSlotData(
                  label: items[i].label,
                  selected: i == _visualIndex,
                  badgeCount: items[i].badgeCount,
                  animation: _selectionControllers[i],
                  textSize: layout.textSize,
                  skipSelector: _dragSelectorActive,
                ),
              ),
            ),
          ),
      ],
    );

    final Widget bar = RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(debugOwner: this),
          (TapGestureRecognizer instance) => instance..onTapUp = _onTapUp,
        ),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(
            duration: kGlassTabBarLongPressDuration,
            debugOwner: this,
          ),
          (LongPressGestureRecognizer instance) => instance
            ..onLongPressStart = _onLongPressStart
            ..onLongPressMoveUpdate = _onLongPressMoveUpdate
            ..onLongPressEnd = _onLongPressEnd
            ..onLongPressCancel = _onLongPressCancel,
        ),
      },
      child: SizedBox(
        width: barWidth,
        height: kGlassTabBarHeightWithMargins,
        child: GlassPanel(
          preset: GlassPresets.mainTabs,
          borderRadius: const GlassRadii.all(kGlassTabBarRadius),
          padding: kGlassTabBarPanelPadding,
          resources: widget.resources,
          child: row,
        ),
      ),
    );

    // Long-press scale about the warped pivot (MainTabsLayout.java:436-439,
    // 563-604).
    final Widget scaled = AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_scale, _pivot]),
      builder: (BuildContext context, Widget? child) {
        final double s =
            lerpDouble(1.0, kGlassTabBarLongPressScale, _scale.value)!;
        final Offset origin = _pivot.value ??
            Offset(barWidth / 2.0, kGlassTabBarHeightWithMargins / 2.0);
        // The Transform stays mounted even at scale 1 so the gesture
        // subtree is never reinflated mid-drag.
        return Transform(
          transform: Matrix4.diagonal3Values(s, s, 1.0),
          origin: origin,
          child: child,
        );
      },
      child: bar,
    );

    // Show/hide (MainTabsActivity.java:955-969). Note the Java gate is
    // `setClickable(factor > 1)` — unreachable, an upstream quirk; the port
    // uses the evident intent (interactive only when fully shown).
    return AnimatedBuilder(
      animation: _visibility,
      builder: (BuildContext context, Widget? child) {
        final double factor = _visibility.value;
        return Transform.translate(
          offset: Offset(0.0, (1.0 - factor) * kGlassTabBarHiddenOffsetY),
          child: Opacity(
            opacity: clampDouble(factor, 0.0, 1.0),
            child: IgnorePointer(ignoring: factor < 1.0, child: child),
          ),
        );
      },
      child: Align(child: scaled),
    );
  }
}

/// The long-press "lens" selector — the `dispatchDraw` prologue of
/// `MainTabsLayout` (MainTabsLayout.java:310-324): a stadium round-rect of
/// `glass_tabSelected` @ 9% alpha, height = row height, radius = height / 2,
/// centered on `centerX + offsetX` with the width interpolated between the
/// bracketing tabs' widths.
class _LensSelectorPainter extends CustomPainter {
  _LensSelectorPainter({
    required Listenable repaint,
    required this.centerX,
    required this.offsetX,
    required this.color,
    required this.centers,
    required this.widths,
  }) : super(repaint: repaint);

  final Animation<double> centerX;
  final Animation<double> offsetX;
  final Color color;
  final List<double> centers;
  final List<double> widths;

  @override
  void paint(Canvas canvas, Size size) {
    if (centers.isEmpty) {
      return;
    }
    final double x = centerX.value + offsetX.value;
    final double sWidth = glassTabBarInterpolatedWidth(x, centers, widths);
    final double sHeight = size.height - kGlassTabBarViewPadding * 2;
    if (sWidth <= 0.0 || sHeight <= 0.0) {
      return;
    }
    // (MainTabsLayout.java:317-320): rect centered vertically, radius h/2.
    final Rect rect = Rect.fromLTRB(
      x - sWidth / 2.0,
      (size.height - sHeight) / 2.0,
      x + sWidth / 2.0,
      (size.height + sHeight) / 2.0,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(sHeight / 2.0)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_LensSelectorPainter oldDelegate) =>
      color != oldDelegate.color ||
      centerX != oldDelegate.centerX ||
      offsetX != oldDelegate.offsetX ||
      !listEquals(centers, oldDelegate.centers) ||
      !listEquals(widths, oldDelegate.widths);
}

/// Plain-label fallback slot for items with neither icon nor avatar: the
/// 12/10dp Roboto Medium label with the unselected -> selectedText color
/// blend of `updateColors` (GlassTabView.java:254-265), honoring the
/// auto-fit [TabSlotData.textSize]. Full-fidelity slots use [GlassTab].
class _FallbackTabLabel extends StatelessWidget {
  const _FallbackTabLabel({required this.slot, this.resources});

  final TabSlotData slot;
  final TelegramResources? resources;

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = this.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  @override
  Widget build(BuildContext context) {
    final Color unselected =
        _color(context, TelegramColorKey.glass_tabUnselected);
    final Color selectedText =
        _color(context, TelegramColorKey.glass_tabSelectedText);
    return AnimatedBuilder(
      animation: slot.animation,
      builder: (BuildContext context, Widget? child) {
        return Center(
          child: Text(
            slot.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: slot.textSize,
              fontFamily: slot.selected
                  ? GlassTab.selectedFontFamily
                  : GlassTab.unselectedFontFamily,
              package: 'telegram_ui',
              fontWeight: slot.selected ? FontWeight.w800 : FontWeight.w500,
              color: blendArgb(unselected, selectedText, slot.animation.value),
            ),
          ),
        );
      },
    );
  }
}
