// The attachment menu sheet (ARCHITECTURE.md section 6; spec:
// flutter/docs/spec_attach_emoji.md, Part A).
//
// Port of the liquid-glass `ChatAttachAlert` (CAA =
// `ui/Components/ChatAttachAlert.java`) composed on the existing sheet /
// tabs primitives. The classic `chat_attachAlert*` circle-button design is
// gone from this branch — attach buttons are `GlassTabView` pills
// (`createAttachTab`, GTV = `ui/Components/glass/GlassTabView.java`) on a
// floating `mainTabs` glass bar. Every constant cited:
//
// - sheet chrome: 12dp top corners (the `sheet_shadow_round` 9-patch,
//   BottomSheet.java:1194; reused from `tg_bottom_sheet.dart`), grabber
//   36x4dp r2 `key_sheet_scrollUp` at top + 20dp (CAA:1893-1913);
// - action-button row = the layout switcher: wrapper MATCH x 70dp bottom
//   (CAA:2735), glass bg `mainTabs` radius 28dp glass-padding 7dp
//   (CAA:2725-2728), content padding 11dp (CAA:2729-2731); tab width
//   `min(84, text + 2 * lerp(16, 8, (text - 40) / 16))` plus equally
//   distributed leftover (GTV:485-489, 505-513; CAA:2661-2684); tab anatomy
//   per `createAttachTab` (GTV:441-454): 24x24 icon top 4, 11dp Roboto
//   Medium label (extra-bold selected) top 28.33, selection pill
//   `glass_tabSelected` @9% radius min(w,h)/2 scale 0.6->1, select animator
//   320ms decelerate (GTV:67);
// - glass action bar: `attachMenuActionBar` pills radius 23dp glass-padding
//   6dp (CAA:4075; ActionBar.java:213-252), header title 16dp bold
//   `dialogTextBlack` (CAA:2477-2481) inset (23, 21) (CAA:2534), show/hide
//   380ms EASE_OUT_QUINT (CAA:5695-5736);
// - open: container spring damping 0.75 / stiffness 350 (CAA:5278-5286);
//   dim 400ms delay 20ms Overshoot(0.7) (CAA:5292-5298, 1344); attach-tab
//   cascade — master 400ms delay 20ms, per-tab start `32 * (3 - i)`ms, scale
//   0 -> 1.1 EASE_OUT over 200ms (alpha EASE_BOTH), settle 1.1 -> 1.0
//   EASE_IN over 100ms, applied via `setAttachScale` (CAA:5189-5228,
//   5257-5262; GTV:491-503);
// - close: BottomSheet dismissal, 250ms EASE_OUT (BottomSheet.java:2014-2033);
// - layout switch: outgoing 180ms DEFAULT to +78dp with fade
//   (CAA:4605-4615); incoming from +78dp via spring damping 0.75 /
//   stiffness 500 (CAA:4606-4641);
// - send button: container 110x50dp bottom-right, hidden alpha 0 scale 0.2,
//   shown over 180ms (CAA:3503-3527, 4999, 5103); pill 52x38dp, circle
//   padding (7, 6), `newCounterPos` (CAA:3556-3560); count badge circle
//   `max(18, 9 + textWidth)` at `(pillRight - 50, pillTop)` with a +2dp
//   clear punch-out ring (CAEV = `ui/Components/ChatActivityEnterView.java`,
//   lines 15166-15189) — composed on the `CounterBadgeLayer` punch-out
//   machinery of `counter_badge.dart`.
//
// Content pipelines (photo gallery, sticker sets, attach-menu bots) are
// slot/provider parameters, never implemented here. Not ported: the 8dp
// horizontal edge-fade masks of the overflowing row (CAA:2592-2658; the row
// simply scrolls), the photo <-> photo-preview horizontal swap
// (CAA:4654-4709), and the `AnimatedTextDrawable` count crossfade/bounce.
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../foundation/tg_curves.dart';
import '../../glass/geometry.dart';
import '../../glass/glass_panel.dart';
import '../../glass/presets.dart';
import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';
import '../sheet/tg_bottom_sheet.dart' show kSheetBarrierColor, kSheetCornerRadius;
import '../tabs/counter_badge.dart';
import '../tabs/glass_tab.dart';
import '../tabs/tab_icon.dart';

// ---------------------------------------------------------------------------
// Constants (spec_attach_emoji.md Part A, Java lines cited per value).
// ---------------------------------------------------------------------------

/// Grabber width: 36dp (CAA:1893-1913).
const double kAttachGrabberWidth = 36.0;

/// Grabber height: 4dp (CAA:1893-1913).
const double kAttachGrabberHeight = 4.0;

/// Grabber corner radius: 2dp (CAA:1893-1913).
const double kAttachGrabberRadius = 2.0;

/// Grabber y position: sheet top + 20dp (CAA:1893-1913).
const double kAttachGrabberTop = 20.0;

/// Action-button row wrapper height: 70dp (`buttonsRecyclerViewWrapper`,
/// CAA:2735).
const double kAttachButtonRowHeight = 70.0;

/// Row glass background radius: 28dp (= 56 / 2, CAA:2725-2728) — the
/// `GlassPresets.mainTabs` pill, identical to the main bottom tab bar.
const double kAttachButtonRowGlassRadius = 28.0;

/// Row glass drawable padding: 7dp (CAA:2725-2728).
const double kAttachButtonRowGlassPadding = 7.0;

/// Row content (recycler) padding, all sides: 11dp (CAA:2729-2731). Tab
/// content height = 70 - 2*11 = 48dp.
const double kAttachButtonRowContentPadding = 11.0;

/// Tab content height: 70 - 22 = 48dp (CAA:2729-2735).
const double kAttachTabHeight =
    kAttachButtonRowHeight - kAttachButtonRowContentPadding * 2;

/// Maximum natural tab width: 84dp (GTV:485-489).
const double kAttachTabMaxWidth = 84.0;

/// Tab text padding endpoints: `lerp(16, 8, clamp((textWidth - 40) / 16))`
/// (GTV:485-489).
const double kAttachTabTextPaddingMax = 16.0;

/// See [kAttachTabTextPaddingMax] (GTV:485-489).
const double kAttachTabTextPaddingMin = 8.0;

/// Attach-tab label size: 11dp (GTV:445-446; the main tab bar uses 12dp).
const double kAttachTabLabelSize = 11.0;

/// Selection animator: 320ms decelerate — `BoolAnimator(...,
/// DECELERATE_INTERPOLATOR, 320)` (GTV:67), same as [GlassTab].
const Duration kAttachTabSelectionDuration = GlassTab.selectionDuration;

/// Action-bar glass pill radius: 23dp (`ActionBar.setupGlass`,
/// ActionBar.java:213-252, wired at CAA:4075).
const double kAttachActionBarPillRadius = 23.0;

/// Action-bar glass drawable padding: 6dp (ActionBar.java:213-252).
const double kAttachActionBarGlassPadding = 6.0;

/// Action bar show/hide: 380ms EASE_OUT_QUINT (CAA:5695-5736).
const Duration kAttachActionBarVisibilityDuration = Duration(milliseconds: 380);

/// Header title text size: 16dp bold `dialogTextBlack` (CAA:2477-2481).
const double kAttachHeaderTitleSize = 16.0;

/// Header start inset: 23dp (`headerView` frame, CAA:2534).
const double kAttachHeaderInsetStart = 23.0;

/// Header end inset: 21dp (CAA:2534).
const double kAttachHeaderInsetEnd = 21.0;

/// Open spring: `SpringAnimation` damping ratio 0.75, stiffness 350
/// (CAA:5278-5286).
final SpringDescription kAttachSheetOpenSpring =
    SpringDescription.withDampingRatio(mass: 1.0, stiffness: 350.0, ratio: 0.75);

/// Open transition duration: the settle time of [kAttachSheetOpenSpring] —
/// decay rate `zeta * omega_n = 0.75 * sqrt(350) ~= 14.03/s` reaches the
/// default 1e-3 physics tolerance at `ln(1000) / 14.03 ~= 0.49s`, rounded to
/// 500ms. (Android springs run open-ended; a route needs a bound.)
const Duration kAttachSheetOpenDuration = Duration(milliseconds: 500);

/// Dim animation length: 400ms (CAA:5292-5298).
const Duration kAttachSheetDimDuration = Duration(milliseconds: 400);

/// Dim start delay: 20ms (CAA:5292-5298).
const Duration kAttachSheetDimDelay = Duration(milliseconds: 20);

/// Dim interpolator: `OvershootInterpolator(0.7)` (`openInterpolator`,
/// CAA:1344, applied CAA:5292-5298) windowed to the 20..420ms span of the
/// 500ms open transition.
const Curve kAttachSheetDimCurve =
    Interval(0.04, 0.84, curve: TgOvershootCurve(0.7));

/// Close: 250ms (the BottomSheet dismissal the attach alert inherits,
/// BottomSheet.java:2014-2033).
const Duration kAttachSheetDismissDuration = Duration(milliseconds: 250);

/// Close curve: EASE_OUT (BottomSheet.java:2014-2033).
const Cubic kAttachSheetDismissCurve = TgCurves.easeOut;

/// Cascade master clock length: 400ms (CAA:5189-5228).
const Duration kAttachCascadeMasterDuration = Duration(milliseconds: 400);

/// Cascade master start delay: 20ms (CAA:5257-5262).
const Duration kAttachCascadeDelay = Duration(milliseconds: 20);

/// Per-tab cascade start: `32 * (3 - index)` ms (CAA:5189-5228).
const double kAttachCascadeStaggerMs = 32.0;

/// Cascade grow phase: 200ms, scale 0 -> [kAttachCascadePeakScale] EASE_OUT,
/// alpha 0 -> 1 EASE_BOTH (CAA:5189-5228).
const double kAttachCascadeGrowMs = 200.0;

/// Cascade overshoot peak: 1.1 (CAA:5189-5228).
const double kAttachCascadePeakScale = 1.1;

/// Cascade settle phase: 100ms, 1.1 -> 1.0 EASE_IN (CAA:5189-5228).
const double kAttachCascadeSettleMs = 100.0;

/// `EASE_BOTH = (0.42, 0, 0.58, 1)` (CubicBezierInterpolator.java:13) — the
/// cascade alpha curve (CAA:5189-5228). Not in [TgCurves] (no other consumer
/// yet).
const Cubic kAttachCascadeAlphaCurve = Cubic(0.42, 0.0, 0.58, 1.0);

/// Layout-switch outgoing: 180ms DEFAULT (CAA:4605-4615).
const Duration kAttachLayoutSwitchOutDuration = Duration(milliseconds: 180);

/// Layout-switch translation extent: 78dp (CAA:4605-4641).
const double kAttachLayoutSwitchOffset = 78.0;

/// Layout-switch incoming spring: damping 0.75, stiffness 500
/// (CAA:4606-4641).
final SpringDescription kAttachLayoutSwitchInSpring =
    SpringDescription.withDampingRatio(mass: 1.0, stiffness: 500.0, ratio: 0.75);

/// Send button container: 110x50dp (`writeButtonContainer`, CAA:3503-3527).
const Size kAttachSendContainerSize = Size(110.0, 50.0);

/// Send pill: `setCircleSize(dp(52), dp(38))` (CAA:3556-3560).
const Size kAttachSendPillSize = Size(52.0, 38.0);

/// Send pill horizontal inset: `setCirclePadding(dp(7), dp(6))`
/// (CAA:3556-3560).
const double kAttachSendPillPaddingH = 7.0;

/// Send pill vertical inset (CAA:3556-3560).
const double kAttachSendPillPaddingV = 6.0;

/// Count badge minimum diameter: `max(dp(18), ...)` (CAEV:15166-15189).
const double kAttachSendBadgeMinSize = 18.0;

/// Count badge text padding: `dp(9) + textWidth` (CAEV:15166-15189).
const double kAttachSendBadgeTextPadding = 9.0;

/// Punch-out ring gap: clear circle radius `sz/2 + 2dp` (CAEV:15166-15189).
const double kAttachSendBadgeRingGap = 2.0;

/// Badge center x from the pill's right edge: `pillRight - 50dp`
/// (`newCounterPos`, CAEV:15166-15189).
const double kAttachSendBadgeOffsetFromPillRight = 50.0;

/// Send button show/hide: 180ms (the comments/selection animator,
/// CAA:4999, 5103).
const Duration kAttachSendVisibilityDuration = Duration(milliseconds: 180);

/// Send button hidden scale: 0.2 (CAA:3503-3527).
const double kAttachSendHiddenScale = 0.2;

// ---------------------------------------------------------------------------
// Pure geometry / timing helpers (unit-testable).
// ---------------------------------------------------------------------------

/// Natural attach-tab width for a measured [textWidth]:
/// `min(84, textWidth + 2 * padding)` with
/// `padding = lerp(16, 8, clamp((textWidth - 40) / 16, 0, 1))`
/// (GTV:485-489).
double attachTabNaturalWidth(double textWidth) {
  final double t =
      ((textWidth - 40.0) / 16.0).clamp(0.0, 1.0);
  final double padding =
      lerpDouble(kAttachTabTextPaddingMax, kAttachTabTextPaddingMin, t)!;
  return math.min(kAttachTabMaxWidth, textWidth + 2.0 * padding);
}

/// Final attach-tab widths: natural widths plus the equally distributed
/// leftover when the row underfills [availableWidth]
/// (`setAdditionalWidth`, GTV:505-513; CAA:2661-2684). An overflowing row
/// keeps the natural widths (and scrolls).
List<double> attachTabRowWidths(
  List<double> textWidths,
  double availableWidth,
) {
  final List<double> natural = <double>[
    for (final double w in textWidths) attachTabNaturalWidth(w),
  ];
  if (natural.isEmpty) {
    return natural;
  }
  double total = 0.0;
  for (final double w in natural) {
    total += w;
  }
  if (total < availableWidth) {
    final double extra = (availableWidth - total) / natural.length;
    return <double>[for (final double w in natural) w + extra];
  }
  return natural;
}

/// The open-cascade scale of tab [index] at master-clock time [masterMs]
/// (0..400): starts at `32 * (3 - index)` ms, grows 0 -> 1.1 with EASE_OUT
/// over 200ms, settles 1.1 -> 1.0 with EASE_IN over 100ms (CAA:5189-5228).
/// Indices above 3 have negative starts — they are simply further along at
/// master 0, exactly like the Java arithmetic.
double attachCascadeScale(double masterMs, int index) {
  final double local = masterMs - kAttachCascadeStaggerMs * (3 - index);
  if (local <= 0.0) {
    return 0.0;
  }
  if (local < kAttachCascadeGrowMs) {
    return kAttachCascadePeakScale *
        TgCurves.easeOut.transform(local / kAttachCascadeGrowMs);
  }
  if (local < kAttachCascadeGrowMs + kAttachCascadeSettleMs) {
    final double t = (local - kAttachCascadeGrowMs) / kAttachCascadeSettleMs;
    return lerpDouble(
      kAttachCascadePeakScale,
      1.0,
      TgCurves.easeIn.transform(t),
    )!;
  }
  return 1.0;
}

/// The open-cascade alpha of tab [index] at [masterMs]: 0 -> 1 with
/// EASE_BOTH over the same 200ms grow phase (CAA:5189-5228).
double attachCascadeAlpha(double masterMs, int index) {
  final double local = masterMs - kAttachCascadeStaggerMs * (3 - index);
  if (local <= 0.0) {
    return 0.0;
  }
  if (local < kAttachCascadeGrowMs) {
    return kAttachCascadeAlphaCurve.transform(local / kAttachCascadeGrowMs);
  }
  return 1.0;
}

/// Send-count badge diameter: `max(18, 9 + textWidth)` (CAEV:15166-15189).
double attachSendBadgeSize(double textWidth) =>
    math.max(kAttachSendBadgeMinSize, kAttachSendBadgeTextPadding + textWidth);

/// Measures an attach-tab label at [kAttachTabLabelSize] with the label
/// typeface (Roboto Medium w500, bundled by this package) — the analog of
/// the `GlassTabView` label paint measurement feeding the width formula
/// (GTV:485-489).
double measureAttachTabLabelWidth(String label) {
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        fontSize: kAttachTabLabelSize,
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

// ---------------------------------------------------------------------------
// Curves.
// ---------------------------------------------------------------------------

/// Port of Android's `android.view.animation.OvershootInterpolator`:
/// `f(t) = (t - 1)^2 * ((tension + 1) * (t - 1) + tension) + 1`. The attach
/// sheet dims with tension 0.7 (CAA:1344).
class TgOvershootCurve extends Curve {
  /// Creates the curve; [tension] is Android's constructor argument.
  const TgOvershootCurve(this.tension);

  /// Android's `mTension`.
  final double tension;

  @override
  double transformInternal(double t) {
    final double u = t - 1.0;
    return u * u * ((tension + 1.0) * u + tension) + 1.0;
  }
}

/// The open motion as a curve: [kAttachSheetOpenSpring] sampled over the
/// [kAttachSheetOpenDuration] window — `transform(t)` is the spring position
/// from 0 to 1 at `t * 0.5s`. Underdamped (ratio 0.75), so values overshoot
/// slightly past 1 mid-flight, exactly like the Android `SpringAnimation`
/// (CAA:5278-5286).
class AttachSheetOpenSpringCurve extends Curve {
  /// Creates the curve.
  const AttachSheetOpenSpringCurve();

  @override
  double transformInternal(double t) {
    final SpringSimulation simulation =
        SpringSimulation(kAttachSheetOpenSpring, 0.0, 1.0, 0.0);
    return simulation.x(
      t * kAttachSheetOpenDuration.inMilliseconds / 1000.0,
    );
  }
}

// ---------------------------------------------------------------------------
// Pages.
// ---------------------------------------------------------------------------

/// One pluggable attach layout — the declarative analog of an
/// `AttachAlertLayout` plus its `GlassTabView` switcher tab (CAA:4587-4652;
/// GTV:441-454). Selecting the page's tab shows [bodyBuilder]'s widget with
/// the layout-switch animation.
@immutable
class AttachSheetPage {
  /// Creates a page.
  const AttachSheetPage({
    required this.id,
    required this.tabLabel,
    this.icon,
    this.title,
    this.actions = const <Widget>[],
    required this.bodyBuilder,
    this.badgeCount = 0,
  });

  /// The media-grid page: the gallery body is built from the
  /// [thumbnailsBuilder] provider slot — the photo pipeline
  /// (`MediaController`-backed `ChatAttachAlertPhotoLayout` adapter) is never
  /// implemented here, callers supply already-built thumbnail widgets. The
  /// 3-column grid with 2dp gaps is presentation glue for the slot, not a
  /// Java metric.
  factory AttachSheetPage.mediaGrid({
    Object id = 'gallery',
    String tabLabel = 'Gallery',
    TabIcon? icon,
    String? title,
    List<Widget> actions = const <Widget>[],
    required List<Widget> Function(BuildContext context) thumbnailsBuilder,
    int badgeCount = 0,
  }) {
    return AttachSheetPage(
      id: id,
      tabLabel: tabLabel,
      icon: icon,
      title: title,
      actions: actions,
      badgeCount: badgeCount,
      bodyBuilder: (BuildContext context) => GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 2.0,
        crossAxisSpacing: 2.0,
        padding: EdgeInsets.zero,
        children: thumbnailsBuilder(context),
      ),
    );
  }

  /// Stable identity (keys the body subtree across switches).
  final Object id;

  /// The switcher-tab label (11dp, GTV:445-446).
  final String tabLabel;

  /// The tab's 24x24 icon slot — the `TabAnimation` lottie pairs
  /// (`tab_*` / `tab_*_reverse`, GTV:545-569) arrive through the
  /// [TabIcon]/[TabAnimationController] contract; null leaves the slot empty.
  final TabIcon? icon;

  /// Header title; falls back to [tabLabel] (the "Gallery" /
  /// "N media selected" `selectedTextView`, CAA:2477-2481).
  final String? title;

  /// Action-bar widgets shown in the trailing menu pill (the
  /// `selectedMenuItem` / `searchItem` slots, CAA:2559-2563).
  final List<Widget> actions;

  /// Builds the page body (the `AttachAlertLayout` content — always a slot).
  final WidgetBuilder bodyBuilder;

  /// Per-tab counter badge count; 0 hides it (GTV:167-227, ported by
  /// `counter_badge.dart`).
  final int badgeCount;
}

// ---------------------------------------------------------------------------
// Attach tab.
// ---------------------------------------------------------------------------

/// One attach-switcher tab — the `createAttachTab` variant of `GlassTabView`
/// (GTV:441-454): 24x24 [icon] top 4, 11dp label top 28.33 (Roboto Medium,
/// extra-bold when selected, GTV:445-446, 237), the 320ms-decelerate
/// selection pill/color blend shared with [GlassTab] (GTV:67, 152-165,
/// 254-265), the per-tab [counter] badge (GTV:167-227), and the open-cascade
/// [attachScale]/[attachAlpha] transform (`setAttachScale`, GTV:491-503 —
/// scales pill and content about the tab center; the port scales the badge
/// with them).
class TgAttachTab extends StatefulWidget {
  /// Creates a tab cell; the row supplies bounds and gestures.
  const TgAttachTab({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.attachScale = 1.0,
    this.attachAlpha = 1.0,
    this.counter,
    this.resources,
  });

  /// Single-line label (GTV:445-446).
  final String label;

  /// The 24x24 icon slot; null leaves it empty (icon pipelines are slots).
  final TabIcon? icon;

  /// Whether this tab is the selected layout; changes animate over
  /// [kAttachTabSelectionDuration] decelerate (GTV:67) and drive
  /// [TabIcon.applySelection] (forward/reverse lottie, GTV:319-397).
  final bool selected;

  /// Open-cascade scale (`setAttachScale`, GTV:491-503).
  final double attachScale;

  /// Open-cascade alpha (CAA:5189-5228).
  final double attachAlpha;

  /// Counter badge text; null/empty hides it (GTV:223-227).
  final String? counter;

  /// Per-surface palette override (the `resourcesProvider` convention).
  final TelegramResources? resources;

  @override
  State<TgAttachTab> createState() => _TgAttachTabState();
}

class _TgAttachTabState extends State<TgAttachTab>
    with SingleTickerProviderStateMixin {
  /// `isSelectedAnimator` — `BoolAnimator(320ms, DECELERATE)` (GTV:67).
  late final BoolFactor _selection = BoolFactor(
    value: widget.selected,
    duration: kAttachTabSelectionDuration,
    curve: TgCurves.decelerate,
  );

  late final Ticker _ticker;
  Duration _clockBase = Duration.zero;
  Duration _clockNow = Duration.zero;

  void _onTick(Duration elapsed) {
    final Duration now = _clockBase + elapsed;
    _clockNow = now;
    setState(() {
      _selection.tick(now);
    });
    if (!_selection.isAnimating) {
      _ticker.stop();
      _clockBase = _clockNow;
    }
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    // Initial bind is unanimated (`checkPlayAnimation(false)` from the tab
    // factory, GTV:405, 441-454).
    widget.icon?.applySelection(selected: widget.selected, animated: false);
  }

  static TabAnimationController? _controllerOf(TabIcon? icon) =>
      icon is AnimatedTabIcon ? icon.controller : null;

  @override
  void didUpdateWidget(TgAttachTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      _selection.set(widget.selected);
      if (_selection.isAnimating && !_ticker.isActive) {
        _ticker.start();
      }
    }
    if (!identical(_controllerOf(widget.icon), _controllerOf(oldWidget.icon))) {
      widget.icon?.applySelection(selected: widget.selected, animated: false);
    } else if (widget.selected != oldWidget.selected) {
      // `setSelected(selected, animated)` -> `checkPlayAnimation(animated)`
      // (GTV:233-238).
      widget.icon?.applySelection(selected: widget.selected, animated: true);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  @override
  Widget build(BuildContext context) {
    final double factor = _selection.factor;
    final Color unselected =
        _color(context, TelegramColorKey.glass_tabUnselected);
    final Color selected = _color(context, TelegramColorKey.glass_tabSelected);
    final Color selectedText =
        _color(context, TelegramColorKey.glass_tabSelectedText);

    // `updateColors` (GTV:254-265).
    final Color iconTint = blendArgb(unselected, selected, factor);
    final Color textColor = blendArgb(unselected, selectedText, factor);

    final TabIcon? icon = widget.icon;
    Widget? slot;
    if (icon != null) {
      final Widget glyph = switch (icon) {
        StaticTabIcon(:final Widget? child, :final ImageProvider? image) =>
          child ??
              Image(
                image: image!,
                width: GlassTab.iconSize,
                height: GlassTab.iconSize,
                fit: BoxFit.contain,
              ),
        AnimatedTabIcon(:final Widget child) => child,
      };
      // 24x24 at top 4, SRC_IN tint (GTV:448, 258-263).
      slot = Positioned(
        top: GlassTab.iconTop,
        left: 0,
        right: 0,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: GlassTab.iconSize,
            height: GlassTab.iconSize,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(iconTint, BlendMode.srcIn),
              child: glyph,
            ),
          ),
        ),
      );
    }

    // Label: 11dp, top 28.33, extra-bold on the *boolean* selection
    // (GTV:445-446, 96, 237).
    final Widget label = Positioned(
      top: GlassTab.labelTop,
      left: 0,
      right: 0,
      child: Text(
        widget.label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
        style: TextStyle(
          fontSize: kAttachTabLabelSize,
          color: textColor,
          fontFamily: widget.selected
              ? GlassTab.selectedFontFamily
              : GlassTab.unselectedFontFamily,
          package: 'telegram_ui',
          fontWeight: widget.selected ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    );

    // Selection pill behind the content (GTV:152-165, shared painter).
    Widget cell = CustomPaint(
      painter: GlassTabPillPainter(factor: factor, color: selected),
      child: Stack(
        alignment: Alignment.topLeft,
        clipBehavior: Clip.none,
        children: <Widget>[?slot, label],
      ),
    );

    // Per-tab counter badge with its punch-out ring (GTV:167-227).
    cell = CounterBadgeDecoration(
      count: widget.counter,
      resources: widget.resources,
      child: cell,
    );

    // `setAttachScale` scales pill + content about the center (GTV:491-503);
    // alpha rides the same cascade (CAA:5189-5228).
    if (widget.attachScale != 1.0) {
      cell = Transform.scale(scale: widget.attachScale, child: cell);
    }
    if (widget.attachAlpha != 1.0) {
      cell = Opacity(
        opacity: widget.attachAlpha.clamp(0.0, 1.0),
        child: cell,
      );
    }
    return cell;
  }
}

// ---------------------------------------------------------------------------
// Send button + count badge.
// ---------------------------------------------------------------------------

/// The send-count badge painter — the `newCounterPos` count pass of
/// `SendButton.drawInternal` (CAEV:15166-15189) reusing the
/// [CounterBadgePainter]/[CounterBadgeLayer] punch-out machinery:
///
/// - circle diameter `sz = max(18, 9 + textWidth)`;
/// - center `(pillRight - 50, pillTop + sz/2)` for the pill inset (7, 6)
///   inside the painted box;
/// - a clear circle of radius `sz/2 + 2` erases the pixels behind
///   (`Theme.PAINT_CLEAR`), then a filled circle of radius `sz/2` in the
///   send-button background color, then the centered count text.
class AttachSendBadgePainter extends CounterBadgePainter {
  /// Creates the painter; [fill] is the send-button background color
  /// (`chat_messagePanelSend`) used for the badge circle (CAEV:15166-15189).
  AttachSendBadgePainter({
    required super.text,
    required Color fill,
    super.visibility,
    required TextPainter super.counterPainter,
  }) : _counter = counterPainter,
       super(color: fill, errorColor: fill);

  /// The laid-out count text (the super's painter is private to its
  /// library, so the subclass keeps its own reference).
  final TextPainter _counter;

  /// Badge diameter: `max(18, 9 + textWidth)` (CAEV:15166-15189).
  double get badgeSize => attachSendBadgeSize(textWidth);

  /// `cx = pillRight - 50`, `cy = pillTop + sz/2` (CAEV:15166-15189) with
  /// the pill inset (7, 6) of CAA:3556-3560.
  @override
  Offset centerFor(Size size) => Offset(
        size.width - kAttachSendPillPaddingH - kAttachSendBadgeOffsetFromPillRight,
        kAttachSendPillPaddingV + badgeSize / 2.0,
      );

  /// The clear circle bounds: radius `sz/2 + 2` (CAEV:15166-15189).
  @override
  Rect punchRect(Size size) => Rect.fromCircle(
        center: centerFor(size),
        radius: badgeSize / 2.0 + kAttachSendBadgeRingGap,
      );

  @override
  void paintBadge(Canvas canvas, Size size) {
    if (visibility <= 0.0) {
      return;
    }
    canvas.save();
    final Offset c = centerFor(size);
    // Appearance scale about the badge center (the bounce/scale factor,
    // CAEV:15166-15189).
    canvas.translate(c.dx, c.dy);
    canvas.scale(visibility, visibility);
    canvas.translate(-c.dx, -c.dy);

    // Punch-out ring, then the filled count circle (CAEV:15166-15189).
    canvas.drawCircle(
      c,
      badgeSize / 2.0 + kAttachSendBadgeRingGap,
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.drawCircle(c, badgeSize / 2.0, Paint()..color = fillColor);
    _counter.paint(
      canvas,
      c - Offset(_counter.width / 2.0, _counter.height / 2.0),
    );
    canvas.restore();
  }
}

/// The selected-count send button — `writeButtonContainer` + `SendButton`
/// (CAA:3503-3527, 3556-3560; CAEV:15166-15189): a 110x50 box holding the
/// 52x38 send pill (inset 7/6, fill `chat_messagePanelSend`) with the
/// punch-out count badge, hidden at alpha 0 / scale 0.2 and shown over 180ms
/// while [count] > 0.
class TgAttachSendButton extends StatefulWidget {
  /// Creates the button.
  const TgAttachSendButton({
    super.key,
    required this.count,
    this.onTap,
    this.icon,
    this.resources,
  });

  /// Key on the tappable send pill.
  static const Key pillKey = ValueKey<String>('TgAttachSendButton.pill');

  /// Key on the visibility [Opacity] wrapper (tests).
  static const Key visibilityKey =
      ValueKey<String>('TgAttachSendButton.visibility');

  /// Selected-item count; 0 hides the button (CAA:4999, 5103).
  final int count;

  /// Tap handler (the send action).
  final VoidCallback? onTap;

  /// The 24x24 `send_plane_24` glyph slot (icon assets are the app's).
  final Widget? icon;

  /// Per-surface palette override.
  final TelegramResources? resources;

  @override
  State<TgAttachSendButton> createState() => _TgAttachSendButtonState();
}

class _TgAttachSendButtonState extends State<TgAttachSendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _visible = AnimationController(
    vsync: this,
    duration: kAttachSendVisibilityDuration,
    value: widget.count > 0 ? 1.0 : 0.0,
  );

  /// Last non-zero count — keeps painting while scaling out, like the
  /// `AnimatedTextDrawable` whose text outlives the hide.
  late int _shownCount = widget.count;

  TextPainter? _counterPainter;
  String? _counterPainterText;

  TextPainter _counterPainterFor(String text) {
    if (_counterPainter == null || _counterPainterText != text) {
      _counterPainter?.dispose();
      _counterPainter = CounterBadgePainter.buildCounterPainter(text);
      _counterPainterText = text;
    }
    return _counterPainter!;
  }

  @override
  void didUpdateWidget(TgAttachSendButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > 0) {
      _shownCount = widget.count;
    }
    final double target = widget.count > 0 ? 1.0 : 0.0;
    if (_visible.value != target) {
      // 180ms show/hide (CAA:4999, 5103) with the recurring DEFAULT modal
      // grammar.
      _visible.animateTo(target, curve: TgCurves.defaultCubic);
    }
  }

  @override
  void dispose() {
    _visible.dispose();
    _counterPainter?.dispose();
    _counterPainter = null;
    super.dispose();
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  @override
  Widget build(BuildContext context) {
    final Color fill = _color(context, TelegramColorKey.chat_messagePanelSend);
    final String text = '$_shownCount';

    // The 52x38 pill at inset (7, 6) — radius h/2 (the SendButton circle
    // pill, CAA:3556-3560).
    final Widget pill = Positioned(
      right: kAttachSendPillPaddingH,
      bottom: kAttachSendPillPaddingV,
      width: kAttachSendPillSize.width,
      height: kAttachSendPillSize.height,
      child: GestureDetector(
        key: TgAttachSendButton.pillKey,
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius:
                BorderRadius.circular(kAttachSendPillSize.height / 2.0),
          ),
          child: widget.icon == null ? null : Center(child: widget.icon),
        ),
      ),
    );

    final Widget body = CounterBadgeLayer(
      painter: AttachSendBadgePainter(
        text: text,
        fill: fill,
        counterPainter: _counterPainterFor(text),
      ),
      child: Stack(clipBehavior: Clip.none, children: <Widget>[pill]),
    );

    return SizedBox(
      width: kAttachSendContainerSize.width,
      height: kAttachSendContainerSize.height,
      child: AnimatedBuilder(
        animation: _visible,
        builder: (BuildContext context, Widget? child) {
          final double factor = _visible.value;
          // Hidden: alpha 0, scale 0.2 (CAA:3503-3527).
          return IgnorePointer(
            ignoring: factor < 1.0,
            child: Opacity(
              key: TgAttachSendButton.visibilityKey,
              opacity: factor.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: lerpDouble(kAttachSendHiddenScale, 1.0, factor)!,
                child: child,
              ),
            ),
          );
        },
        child: body,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The sheet.
// ---------------------------------------------------------------------------

/// The attachment menu content — `ChatAttachAlert`'s container view composed
/// on the sheet primitives: 12dp-top-rounded `dialogBackground` panel with
/// the grabber (CAA:1893-1913), the glass action bar
/// (`attachMenuActionBar` pills, CAA:4075), the switchable page area
/// (CAA:4587-4652), the 70dp glass action-button row (CAA:2725-2735), and
/// the selected-count send button (CAA:3503-3560).
///
/// Usually shown through [showTgAttachSheet]; embeddable directly for tests
/// or custom hosts.
class TgAttachSheet extends StatefulWidget {
  /// Creates the sheet content. [pages] must be non-empty and
  /// [initialPageIndex] in range (checked in the state's `initState`, since
  /// list lengths are not potentially-constant assert material).
  const TgAttachSheet({
    super.key,
    required this.pages,
    this.initialPageIndex = 0,
    this.onPageChanged,
    this.selectedCount = 0,
    this.onSend,
    this.sendIcon,
    this.height,
    this.resources,
  }) : assert(initialPageIndex >= 0);

  /// Key on the 70dp action-button row wrapper.
  static const Key buttonRowKey = ValueKey<String>('TgAttachSheet.buttonRow');

  /// Key on the glass action-bar/header row.
  static const Key actionBarKey = ValueKey<String>('TgAttachSheet.actionBar');

  /// Key on the grabber handle.
  static const Key grabberKey = ValueKey<String>('TgAttachSheet.grabber');

  /// The attach layouts, in tab order (Gallery / File / Location / ...).
  final List<AttachSheetPage> pages;

  /// The initially selected layout.
  final int initialPageIndex;

  /// Fired when the user switches layouts through the button row.
  final ValueChanged<int>? onPageChanged;

  /// Selected-media count driving the send button and its badge
  /// (CAA:4999, 5103).
  final int selectedCount;

  /// Send action.
  final VoidCallback? onSend;

  /// Send glyph slot forwarded to [TgAttachSendButton.icon].
  final Widget? sendIcon;

  /// Sheet height in logical px. Android imposes it from the content /
  /// keyboard state; null uses 75% of the media height.
  final double? height;

  /// Per-surface palette override (the `resourcesProvider` convention).
  final TelegramResources? resources;

  @override
  State<TgAttachSheet> createState() => _TgAttachSheetState();
}

class _TgAttachSheetState extends State<TgAttachSheet>
    with TickerProviderStateMixin {
  late int _index = widget.initialPageIndex;
  int? _outgoing;

  /// Outgoing layout: 180ms DEFAULT to +78dp with fade (CAA:4605-4615).
  late final AnimationController _switchOut = AnimationController(
    vsync: this,
    duration: kAttachLayoutSwitchOutDuration,
  );
  late final CurvedAnimation _switchOutCurved = CurvedAnimation(
    parent: _switchOut,
    curve: TgCurves.defaultCubic,
  );

  /// Incoming layout offset in px: springs 78 -> 0 (CAA:4606-4641).
  late final AnimationController _switchIn =
      AnimationController.unbounded(vsync: this, value: 0.0);

  /// The open cascade master clock: 20ms delay + 400ms run
  /// (CAA:5189-5228, 5257-5262), normalized over 420ms.
  late final AnimationController _cascade = AnimationController(
    vsync: this,
    duration: kAttachCascadeDelay + kAttachCascadeMasterDuration,
  );

  @override
  void initState() {
    super.initState();
    assert(widget.pages.isNotEmpty, 'Provide at least one page.');
    assert(widget.initialPageIndex < widget.pages.length);
    _switchOut.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed && _outgoing != null) {
        setState(() {
          _outgoing = null;
        });
      }
    });
    _cascade.forward();
  }

  @override
  void didUpdateWidget(TgAttachSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.pages.length) {
      _index = widget.pages.length - 1;
      _outgoing = null;
    }
  }

  @override
  void dispose() {
    _switchOutCurved.dispose();
    _switchOut.dispose();
    _switchIn.dispose();
    _cascade.dispose();
    super.dispose();
  }

  /// `showLayout` (CAA:4587-4652): outgoing 180ms DEFAULT down + fade,
  /// incoming from +78dp on the 0.75/500 spring.
  void _selectPage(int index) {
    if (index == _index || index < 0 || index >= widget.pages.length) {
      return;
    }
    setState(() {
      _outgoing = _index;
      _index = index;
    });
    _switchOut.forward(from: 0.0);
    _switchIn
      ..stop()
      ..value = kAttachLayoutSwitchOffset;
    _switchIn.animateWith(SpringSimulation(
      kAttachLayoutSwitchInSpring,
      kAttachLayoutSwitchOffset,
      0.0,
      0.0,
    ));
    widget.onPageChanged?.call(index);
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  /// Master-clock milliseconds of the cascade: 0 until the 20ms delay
  /// elapses, then 0..400 (CAA:5257-5262).
  double get _cascadeMasterMs {
    final double elapsedMs = _cascade.value *
        (kAttachCascadeDelay + kAttachCascadeMasterDuration).inMilliseconds;
    return (elapsedMs - kAttachCascadeDelay.inMilliseconds).clamp(
      0.0,
      kAttachCascadeMasterDuration.inMilliseconds.toDouble(),
    );
  }

  Widget _buildGrabber(BuildContext context) {
    // 36x4dp r2 `key_sheet_scrollUp`, centered at top + 20dp
    // (CAA:1893-1913).
    return Container(
      key: TgAttachSheet.grabberKey,
      width: kAttachGrabberWidth,
      height: kAttachGrabberHeight,
      decoration: BoxDecoration(
        color: _color(context, TelegramColorKey.sheet_scrollUp),
        borderRadius: BorderRadius.circular(kAttachGrabberRadius),
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    final AttachSheetPage page = widget.pages[_index];
    final String title = page.title ?? page.tabLabel;
    // Pills: `setupGlass(attachMenuActionBar)` radius 23 / glass padding 6
    // (CAA:4075; ActionBar.java:213-252); a 46dp row makes the pill a
    // stadium. Header insets (23, 21) per the `headerView` frame (CAA:2534).
    final Widget titlePill = GlassPanel(
      preset: GlassPresets.attachMenuActionBar,
      borderRadius: const GlassRadii.all(kAttachActionBarPillRadius),
      padding: kAttachActionBarGlassPadding,
      resources: widget.resources,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          // Inner text inset — port glue, not a Java metric.
          padding: const EdgeInsetsDirectional.only(start: 16.0, end: 16.0),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              // 16dp `AndroidUtilities.bold()` (Roboto Medium)
              // `dialogTextBlack` (CAA:2477-2481).
              fontSize: kAttachHeaderTitleSize,
              fontFamily: GlassTab.unselectedFontFamily,
              package: 'telegram_ui',
              fontWeight: FontWeight.w500,
              color: _color(context, TelegramColorKey.dialogTextBlack),
            ),
          ),
        ),
      ),
    );
    return SizedBox(
      key: TgAttachSheet.actionBarKey,
      height: kAttachActionBarPillRadius * 2,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: kAttachHeaderInsetStart,
          end: kAttachHeaderInsetEnd,
        ),
        child: Row(
          children: <Widget>[
            Expanded(child: titlePill),
            if (page.actions.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8.0),
                child: GlassPanel(
                  preset: GlassPresets.attachMenuActionBar,
                  borderRadius:
                      const GlassRadii.all(kAttachActionBarPillRadius),
                  padding: kAttachActionBarGlassPadding,
                  resources: widget.resources,
                  child: Row(mainAxisSize: MainAxisSize.min, children: page.actions),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildButtonRow(BuildContext context) {
    final List<AttachSheetPage> pages = widget.pages;
    return SizedBox(
      key: TgAttachSheet.buttonRowKey,
      height: kAttachButtonRowHeight,
      child: GlassPanel(
        // `iBlur3FactoryLiquidGlass.create(..., mainTabs(...))` radius 28dp,
        // glass padding 7dp (CAA:2725-2728).
        preset: GlassPresets.mainTabs,
        borderRadius: const GlassRadii.all(kAttachButtonRowGlassRadius),
        padding: kAttachButtonRowGlassPadding,
        resources: widget.resources,
        child: Padding(
          // Recycler padding 11dp all sides (CAA:2729-2731).
          padding: const EdgeInsets.all(kAttachButtonRowContentPadding),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final List<double> widths = attachTabRowWidths(
                <double>[
                  for (final AttachSheetPage page in pages)
                    measureAttachTabLabelWidth(page.tabLabel),
                ],
                constraints.maxWidth,
              );
              double total = 0.0;
              for (final double w in widths) {
                total += w;
              }
              final Widget row = AnimatedBuilder(
                animation: _cascade,
                builder: (BuildContext context, Widget? child) {
                  final double masterMs = _cascadeMasterMs;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      for (int i = 0; i < pages.length; i++)
                        SizedBox(
                          width: widths[i],
                          height: kAttachTabHeight,
                          child: GestureDetector(
                            onTap: () => _selectPage(i),
                            behavior: HitTestBehavior.opaque,
                            child: TgAttachTab(
                              key: ValueKey<Object>(pages[i].id),
                              label: pages[i].tabLabel,
                              icon: pages[i].icon,
                              selected: i == _index,
                              attachScale: attachCascadeScale(masterMs, i),
                              attachAlpha: attachCascadeAlpha(masterMs, i),
                              counter: pages[i].badgeCount > 0
                                  ? '${pages[i].badgeCount}'
                                  : null,
                              resources: widget.resources,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
              if (total > constraints.maxWidth) {
                // Overflow scrolls horizontally (the recycler); the 8dp edge
                // fade masks (CAA:2592-2658) are not ported.
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: row,
                );
              }
              return row;
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPageArea(BuildContext context) {
    final int? outgoing = _outgoing;
    final Widget incoming = AnimatedBuilder(
      animation: _switchIn,
      builder: (BuildContext context, Widget? child) {
        final double offset = _switchIn.value;
        return Transform.translate(
          offset: Offset(0.0, offset),
          child: Opacity(
            // Incoming starts at alpha 0 / +78dp (CAA:4606-4641); alpha
            // rides the translation progress.
            opacity:
                (1.0 - offset / kAttachLayoutSwitchOffset).clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<Object>(widget.pages[_index].id),
        child: widget.pages[_index].bodyBuilder(context),
      ),
    );
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (outgoing != null)
            AnimatedBuilder(
              animation: _switchOutCurved,
              builder: (BuildContext context, Widget? child) {
                final double t = _switchOutCurved.value;
                // translationY -> +78dp, cross-fade out (CAA:4605-4615).
                return Transform.translate(
                  offset: Offset(0.0, kAttachLayoutSwitchOffset * t),
                  child: Opacity(opacity: 1.0 - t, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<Object>(widget.pages[outgoing].id),
                child: widget.pages[outgoing].bodyBuilder(context),
              ),
            ),
          incoming,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double height = widget.height ??
        (MediaQuery.maybeSizeOf(context)?.height ?? 533.0) * 0.75;

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: kAttachGrabberTop),
        Center(child: _buildGrabber(context)),
        // Gap between grabber and action bar — port glue.
        const SizedBox(height: 8.0),
        _buildActionBar(context),
        Expanded(child: _buildPageArea(context)),
      ],
    );

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        // 12dp top corners — the `sheet_shadow_round` 9-patch radius
        // (BottomSheet.java:1194; kSheetCornerRadius). The dynamic flatten
        // (`cornerRadius = 1 - moveProgress`, CAA:5570) is a scroll-docking
        // behavior with no scroll host here.
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(kSheetCornerRadius),
        ),
        child: ColoredBox(
          color: _color(context, TelegramColorKey.dialogBackground),
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: content),
              // The floating glass button row over the content bottom
              // (gravity bottom, CAA:2735).
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildButtonRow(context),
              ),
              // `writeButtonContainer` bottom-right (CAA:3503-3527); lifted
              // above the button row (port placement).
              PositionedDirectional(
                end: 0,
                bottom: kAttachButtonRowHeight,
                child: TgAttachSendButton(
                  count: widget.selectedCount,
                  onTap: widget.onSend,
                  icon: widget.sendIcon,
                  resources: widget.resources,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Route + entry point.
// ---------------------------------------------------------------------------

/// Shows the attachment menu sheet. Returns when the route pops (barrier
/// tap, back, or a `Navigator.pop` from a page/action callback).
Future<T?> showTgAttachSheet<T>(
  BuildContext context, {
  required List<AttachSheetPage> pages,
  int initialPageIndex = 0,
  ValueChanged<int>? onPageChanged,
  int selectedCount = 0,
  VoidCallback? onSend,
  Widget? sendIcon,
  double? height,
  bool barrierDismissible = true,
  TelegramResources? resources,
  bool useRootNavigator = false,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push(
    TgAttachSheetRoute<T>(
      pages: pages,
      initialPageIndex: initialPageIndex,
      onPageChanged: onPageChanged,
      selectedCount: selectedCount,
      onSend: onSend,
      sendIcon: sendIcon,
      height: height,
      barrierDismissible: barrierDismissible,
      resources: resources,
    ),
  );
}

/// The modal route behind [showTgAttachSheet] — the `ChatAttachAlert` dialog
/// motion:
///
/// - open: the container slides up on the 0.75/350 spring (CAA:5278-5286,
///   as [AttachSheetOpenSpringCurve] over the 500ms window) while the dim
///   runs 400ms after a 20ms delay with Overshoot(0.7) (CAA:5292-5298);
/// - close: 250ms EASE_OUT down (BottomSheet.java:2014-2033), dim fading
///   with it;
/// - barrier: black at 51/255 (`dimBehindAlpha`, BottomSheet.java:218-219 —
///   [kSheetBarrierColor]), tap-outside dismiss.
class TgAttachSheetRoute<T> extends PopupRoute<T> {
  /// Creates the route; see [showTgAttachSheet].
  TgAttachSheetRoute({
    required this.pages,
    this.initialPageIndex = 0,
    this.onPageChanged,
    this.selectedCount = 0,
    this.onSend,
    this.sendIcon,
    this.height,
    this.barrierDismissible = true,
    this.resources,
    super.settings,
  });

  /// Key on the sheet panel for tests and tooling.
  static const Key panelKey = ValueKey<String>('TgAttachSheet.panel');

  /// See [TgAttachSheet.pages].
  final List<AttachSheetPage> pages;

  /// See [TgAttachSheet.initialPageIndex].
  final int initialPageIndex;

  /// See [TgAttachSheet.onPageChanged].
  final ValueChanged<int>? onPageChanged;

  /// See [TgAttachSheet.selectedCount].
  final int selectedCount;

  /// See [TgAttachSheet.onSend].
  final VoidCallback? onSend;

  /// See [TgAttachSheet.sendIcon].
  final Widget? sendIcon;

  /// See [TgAttachSheet.height].
  final double? height;

  /// Tap outside dismisses (`canDismissWithTouchOutside`,
  /// BottomSheet.java:198).
  @override
  final bool barrierDismissible;

  /// Per-surface palette override.
  final TelegramResources? resources;

  CurvedAnimation? _curvedAnimation;

  static final Animatable<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  );

  @override
  Color? get barrierColor => kSheetBarrierColor;

  @override
  Curve get barrierCurve => kAttachSheetDimCurve;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => kAttachSheetOpenDuration;

  @override
  Duration get reverseTransitionDuration => kAttachSheetDismissDuration;

  Animation<Offset> _position(Animation<double> animation) {
    CurvedAnimation? curved = _curvedAnimation;
    if (curved == null || !identical(curved.parent, animation)) {
      curved?.dispose();
      curved = CurvedAnimation(
        parent: animation,
        curve: const AttachSheetOpenSpringCurve(),
        // Java dismiss runs EASE_OUT on forward time
        // (BottomSheet.java:2014-2033); Flutter evaluates reverseCurve on
        // the decreasing parent value, so the flipped curve reproduces the
        // identical trajectory.
        reverseCurve: kAttachSheetDismissCurve.flipped,
      );
      _curvedAnimation = curved;
    }
    return curved.drive(_slideTween);
  }

  @override
  void dispose() {
    _curvedAnimation?.dispose();
    _curvedAnimation = null;
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: SlideTransition(
          position: _position(animation),
          child: KeyedSubtree(
            key: panelKey,
            child: TgAttachSheet(
              pages: pages,
              initialPageIndex: initialPageIndex,
              onPageChanged: onPageChanged,
              selectedCount: selectedCount,
              onSend: onSend,
              sendIcon: sendIcon,
              height: height,
              resources: resources,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
