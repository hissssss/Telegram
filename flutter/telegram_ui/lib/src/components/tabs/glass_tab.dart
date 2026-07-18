// A single tab of the floating glass tab bar.
//
// Port of `java/org/telegram/ui/Components/glass/GlassTabView.java` (main-tab
// and avatar-tab variants; the counter badge punch-out of lines 167-219 is
// ported separately in `counter_badge.dart`):
//
// - icon slot: 24x24dp, top 4dp, centered horizontally
//   (`createMainTab`, line 406); avatar variant 22x22dp, top 5dp, round
//   radius 11dp (`createAvatar`, lines 424-427);
// - label: 12dp, single line, ellipsized, centered, top margin 28.33dp
//   (lines 88-96); typeface Roboto Medium, swapping to Roboto ExtraBold the
//   moment the tab is selected (`setSelected`, line 237);
// - selection factor: `BoolAnimator(320ms, DECELERATE)` (line 67), ported as
//   [BoolFactor] with [TgCurves.decelerate];
// - selection pill (`dispatchDraw`, lines 152-165): stadium round-rect over
//   the tab bounds, radius `min(w, h) / 2`, color
//   `multAlpha(glass_tabSelected, 0.09 * DECELERATE(factor))`, scaled
//   `lerp(0.6, 1, factor)` about the center;
// - colors (`updateColors`, lines 254-265): icon tint
//   `blendARGB(glass_tabUnselected, glass_tabSelected, factor)` applied
//   SRC_IN; text `blendARGB(glass_tabUnselected, glass_tabSelectedText,
//   factor)`; keys resolved per-surface (lines 268-270, 407-409).
//
// Not ported here: the attach-panel tab variants (`createAttachTab` /
// `createAttachBotTab` / `setAttachScale`, lines 441-513) and the counter
// badge; both consume the same layout constants exposed on [GlassTab].
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../foundation/color_math.dart';
import '../../foundation/tg_curves.dart';
import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';
import 'tab_icon.dart';

/// Port of `androidx.core.graphics.ColorUtils.blendARGB(color1, color2,
/// ratio)` — per-channel float lerp with Java's `(int)` truncation — as used
/// by `GlassTabView.updateColors` (GlassTabView.java:255-256) for the icon
/// tint and label color blends.
Color blendArgb(Color color1, Color color2, double ratio) {
  final int c1 = color1.toARGB32();
  final int c2 = color2.toARGB32();
  final double inverseRatio = 1.0 - ratio;
  int channel(int shift) =>
      (((c1 >> shift) & 0xFF) * inverseRatio + ((c2 >> shift) & 0xFF) * ratio)
          .truncate();
  return Color(
    (channel(24) << 24) |
        (channel(16) << 16) |
        (channel(8) << 8) |
        channel(0),
  );
}

/// A single glass-tab-bar tab: icon (or avatar) over a 12dp label, with the
/// animated selection pill behind — the port of `GlassTabView`
/// (`ui/Components/glass/GlassTabView.java`).
///
/// The tab is a pure visual cell: it fills whatever bounds its parent (the
/// `GlassTabBar` row) gives it and draws no gestures of its own — hit
/// handling, the long-press "lens" drag ([selectionOverride] /
/// [skipSelectionPill]) and width equalization ([visualWidth]) belong to the
/// bar (`MainTabsLayout.java`).
///
/// Selection changes animate over [selectionDuration] with
/// [TgCurves.decelerate] (`BoolAnimator(..., DECELERATE_INTERPOLATOR, 320)`,
/// GlassTabView.java:67); the label typeface flips to Roboto ExtraBold
/// instantly on selection (GlassTabView.java:237); [TabIcon.applySelection]
/// is invoked so animated icons play forward/reverse.
class GlassTab extends StatefulWidget {
  /// A main tab: 24x24 [icon] tinted `glass_tabUnselected` ->
  /// `glass_tabSelected` (`createMainTab`, GlassTabView.java:400-412).
  const GlassTab({
    super.key,
    required this.label,
    required TabIcon this.icon,
    this.selected = false,
    this.selectionOverride,
    this.skipSelectionPill = false,
    this.visualWidth,
    this.resources,
  }) : avatar = null;

  /// The avatar tab variant: an untinted 22x22 [avatar] widget clipped to
  /// radius 11dp at top 5dp (`createAvatar`, GlassTabView.java:414-433 —
  /// the avatar keeps its own colors; only the label blends).
  const GlassTab.avatar({
    super.key,
    required this.label,
    required Widget this.avatar,
    this.selected = false,
    this.selectionOverride,
    this.skipSelectionPill = false,
    this.visualWidth,
    this.resources,
  }) : icon = null;

  /// Single-line label under the icon.
  final String label;

  /// The 24x24 icon; null for the [GlassTab.avatar] variant.
  final TabIcon? icon;

  /// The avatar widget; null for the main variant.
  final Widget? avatar;

  /// Whether this tab is the selected one. Changes animate
  /// ([selectionDuration], [TgCurves.decelerate]) and drive
  /// [TabIcon.applySelection].
  final bool selected;

  /// When non-null, replaces the animated factor for the selection *pill
  /// only* — colors keep following [selected] — mirroring
  /// `setGestureSelectedOverride` (GlassTabView.java:137-141, 153; the
  /// override feeds `dispatchDraw` but not `updateColors`). The bar uses
  /// this during the long-press lens drag.
  final double? selectionOverride;

  /// Suppresses the selection pill while the bar draws its own selector —
  /// `setSkipDrawSelector` (GlassTabView.java:143-148, 154).
  final bool skipSelectionPill;

  /// The bar-assigned visual width (`setVisualWidth`,
  /// GlassTabView.java:106-129): the pill spans `(0, 0, visualWidth,
  /// height)` and icon + label shift by `(visualWidth - width) / 2` so both
  /// stay centered in the visual cell.
  final double? visualWidth;

  /// Per-surface color override — the `Theme.ResourcesProvider` convention.
  /// When null, keys resolve through [TelegramTheme.colorOf] (per-key
  /// rebuild granularity).
  final TelegramResources? resources;

  /// Icon slot: 24x24dp (GlassTabView.java:406).
  static const double iconSize = 24.0;

  /// Icon slot top inset: 4dp (GlassTabView.java:406).
  static const double iconTop = 4.0;

  /// Avatar slot: 22x22dp (GlassTabView.java:427).
  static const double avatarSize = 22.0;

  /// Avatar slot top inset: 5dp (GlassTabView.java:427).
  static const double avatarTop = 5.0;

  /// Avatar corner radius: 11dp (GlassTabView.java:424).
  static const double avatarRadius = 11.0;

  /// Label size: 12dp (GlassTabView.java:88).
  static const double labelSize = 12.0;

  /// Label top margin: 28.33dp (GlassTabView.java:96).
  static const double labelTop = 28.33;

  /// Selection animation: 320ms (GlassTabView.java:67).
  static const Duration selectionDuration = Duration(milliseconds: 320);

  /// Roboto Medium (`AndroidUtilities.bold()`, `fonts/rmedium.ttf`) — the
  /// unselected label typeface, bundled by this package.
  static const String unselectedFontFamily = 'RobotoMedium';

  /// Roboto ExtraBold (`TYPEFACE_ROBOTO_EXTRA_BOLD`, `fonts/rextrabold.ttf`)
  /// — the selected label typeface (GlassTabView.java:237).
  static const String selectedFontFamily = 'RobotoExtraBold';

  @override
  State<GlassTab> createState() => _GlassTabState();
}

class _GlassTabState extends State<GlassTab>
    with SingleTickerProviderStateMixin {
  /// `isSelectedAnimator` — `BoolAnimator(320ms, DECELERATE)`
  /// (GlassTabView.java:67).
  late final BoolFactor _selection = BoolFactor(
    value: widget.selected,
    duration: GlassTab.selectionDuration,
    curve: TgCurves.decelerate,
  );

  late final Ticker _ticker;

  /// Monotonic clock base: [BoolFactor.tick] requires non-decreasing
  /// timestamps, while a restarted [Ticker] resets its elapsed to zero, so
  /// the clock value reached when a run stops carries over as the base of
  /// the next run.
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
    // Initial bind is unanimated, like `checkPlayAnimation(false)` from
    // `createMainTab` (GlassTabView.java:405).
    widget.icon?.applySelection(selected: widget.selected, animated: false);
  }

  /// The playback identity of an icon config: [TabIcon] instances are
  /// rebuilt every parent build, but the same [TabAnimationController] means
  /// the same underlying composition, like the stable `TabAnimation` enum
  /// constant in Java.
  static TabAnimationController? _controllerOf(TabIcon? icon) =>
      icon is AnimatedTabIcon ? icon.controller : null;

  @override
  void didUpdateWidget(GlassTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      _selection.set(widget.selected);
      if (_selection.isAnimating && !_ticker.isActive) {
        _ticker.start();
      }
    }
    if (!identical(_controllerOf(widget.icon), _controllerOf(oldWidget.icon))) {
      // Rebinding to a new composition is unanimated (`setTabAnimation` ->
      // `checkPlayAnimation(false)`, GlassTabView.java:615-622).
      widget.icon?.applySelection(selected: widget.selected, animated: false);
    } else if (widget.selected != oldWidget.selected) {
      // `setSelected(selected, animated)` -> `checkPlayAnimation(animated)`
      // (GlassTabView.java:233-238).
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
    final Color unselected = _color(
      context,
      TelegramColorKey.glass_tabUnselected,
    );
    final Color selected = _color(context, TelegramColorKey.glass_tabSelected);
    final Color selectedText = _color(
      context,
      TelegramColorKey.glass_tabSelectedText,
    );

    // `updateColors` (GlassTabView.java:254-265). Note the pill's gesture
    // override does NOT feed these — only `isSelectedAnimator` does.
    final Color iconTint = blendArgb(unselected, selected, factor);
    final Color textColor = blendArgb(unselected, selectedText, factor);

    Widget slot;
    final Widget? avatar = widget.avatar;
    if (avatar != null) {
      // `createAvatar` (GlassTabView.java:424-427): 22x22, top 5, radius 11,
      // no tint.
      slot = Positioned(
        top: GlassTab.avatarTop,
        left: 0,
        right: 0,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: GlassTab.avatarSize,
            height: GlassTab.avatarSize,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GlassTab.avatarRadius),
              child: avatar,
            ),
          ),
        ),
      );
    } else {
      final TabIcon icon = widget.icon!;
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
      // `imageView.setColorFilter(PorterDuffColorFilter(color, SRC_IN))`
      // (GlassTabView.java:258-263).
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

    // Label (GlassTabView.java:87-96, 237): 12dp, single line, ellipsized,
    // centered, top 28.33dp; typeface keyed on the *boolean* selection, not
    // the animated factor. TextHeightBehavior pinned per ARCHITECTURE.md
    // section 5 (TextView vs Paragraph leading distribution).
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
          fontSize: GlassTab.labelSize,
          color: textColor,
          fontFamily: widget.selected
              ? GlassTab.selectedFontFamily
              : GlassTab.unselectedFontFamily,
          package: 'telegram_ui',
          fontWeight: widget.selected ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    );

    final Widget stack = Stack(
      alignment: Alignment.topLeft,
      clipBehavior: Clip.none,
      children: <Widget>[slot, label],
    );

    Widget content = stack;
    final double? visualWidth = widget.visualWidth;
    if (visualWidth != null) {
      // `checkVisualWidth` (GlassTabView.java:123-129): children shift by
      // (visualWidth - width) / 2 while the pill spans visualWidth from x=0.
      content = LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double offset = (visualWidth - constraints.maxWidth) / 2.0;
          return Transform.translate(offset: Offset(offset, 0), child: stack);
        },
      );
    }

    // The gesture override replaces the animated factor for the pill only
    // (`dispatchDraw`, GlassTabView.java:153).
    final double pillFactor = widget.selectionOverride ?? factor;
    return CustomPaint(
      painter: widget.skipSelectionPill
          ? null
          : GlassTabPillPainter(
              factor: pillFactor,
              color: selected,
              visualWidth: visualWidth,
            ),
      child: content,
    );
  }
}

/// The selection pill behind a [GlassTab] — the port of the selector pass of
/// `GlassTabView.dispatchDraw` (GlassTabView.java:152-165):
///
/// - stadium round-rect over `(0, 0, visualWidth ?? width, height)`, radius
///   `min(w, h) / 2` (lines 158-159);
/// - fill `multAlpha(glass_tabSelected, 0.09 * DECELERATE(factor))` — the
///   decelerate curve is applied a *second* time to the (already
///   decelerated) animator factor for the alpha ramp (lines 155-157);
/// - scaled `lerp(0.6, 1, factor)` about the rect center (lines 160-162; the
///   attach-panel `attachScale` multiplier is not ported).
class GlassTabPillPainter extends CustomPainter {
  /// Creates the pill painter for the given selection [factor] and resolved
  /// `glass_tabSelected` [color].
  const GlassTabPillPainter({
    required this.factor,
    required this.color,
    this.visualWidth,
  });

  /// Selection factor in 0..1 (`isSelectedAnimator.getFloatValue()` or the
  /// gesture override).
  final double factor;

  /// Resolved `glass_tabSelected` color.
  final Color color;

  /// Overrides the pill span width (`setVisualWidth`,
  /// GlassTabView.java:106-115, 152).
  final double? visualWidth;

  /// `lerp(0.6f, 1, selectedFactor)` (GlassTabView.java:160).
  double get pillScale => lerpDouble(0.6, 1.0, factor)!;

  /// `Theme.multAlpha(colorSelected, 0.09f * DECELERATE(selectedFactor))`
  /// (GlassTabView.java:155-157) in exact Java int arithmetic.
  Color get pillColor => Color(
    multAlpha(color.toARGB32(), 0.09 * TgCurves.decelerate.transform(factor)),
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (factor <= 0) {
      return;
    }
    final double width = visualWidth ?? size.width;
    final Rect rect = Rect.fromLTWH(0, 0, width, size.height);
    final double radius = math.min(rect.width, rect.height) / 2.0;
    final double scale = pillScale;
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.scale(scale, scale);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = pillColor,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(GlassTabPillPainter oldDelegate) =>
      factor != oldDelegate.factor ||
      color != oldDelegate.color ||
      visualWidth != oldDelegate.visualWidth;
}
