// The modal bottom sheet (ARCHITECTURE.md section 6, row "TgBottomSheet").
//
// Port of `ui/ActionBar/BottomSheet.java`, with every constant cited:
//
// - background: the `R.drawable.sheet_shadow_round` 9-patch tinted
//   `key_dialogBackground` MULTIPLY (BottomSheet.java:1194-1195). The
//   9-patch's top corner radius is 12dp — the value production code uses
//   when it redraws the same shape in software
//   (`canvas.drawRoundRect(rect, dp(12) * rad, dp(12) * rad, ...)`,
//   PollVotesAlert.java:776, GroupCallActivity.java:2886; ChatAttachAlert
//   keeps the identical commented-out call, ChatAttachAlert.java:1866). The
//   9-patch's soft shadow inset (`backgroundPaddingTop`) is not ported —
//   the panel is a plain round-rect (solid) or a frosted glass surface;
// - container padding: 8dp top when `applyTopPadding` and 8dp bottom when
//   `applyBottomPadding` (BottomSheet.java:1357);
// - dim behind: `dimBehind = true`, `dimBehindAlpha = 51` — 51/255 = 0.2
//   black (BottomSheet.java:218-219), animated together with the sheet
//   translation (BottomSheet.java:1734, 1868);
// - title row: fixed 48dp (BottomSheet.java:1389, 1411-1413); big title
//   20dp `AndroidUtilities.bold()` (Roboto Medium) `dialogTextBlack`,
//   padding (21, 6 [14 multiline], 21, 8); normal title 16dp
//   `dialogTextGray2`, padding (16, 0 [8 multiline], 16, 8)
//   (BottomSheet.java:1391-1399); multiline titles wrap to 5 lines
//   (BottomSheet.java:1401-1404). Java ellipsizes single-line titles at
//   TruncateAt.MIDDLE (BottomSheet.java:1408); Flutter has no
//   middle-ellipsis, so the port uses end ellipsis;
// - item cells (`BottomSheetCell` type 0, BottomSheet.java:1019-1083):
//   height 48dp (BottomSheet.java:1079-1081), stacked at 48dp steps
//   (BottomSheet.java:1440-1441); icon frame 56x48 start-aligned, tinted
//   `dialogIcon` MULTIPLY (BottomSheet.java:1043-1044); text 16dp
//   `dialogTextBlack`, single line, end-ellipsized, CENTER_VERTICAL
//   (BottomSheet.java:1052-1060); text inset 72dp with an icon, else 16dp
//   (21dp under a big title) (`setTextAndIcon`, BottomSheet.java:1105-1125).
//   Cell types 1 (centered bold) and 2 (80dp filled-button cell) are not
//   ported;
// - open animation: the catalog pins 250ms `CubicBezierInterpolator.DEFAULT`
//   — the duration Java uses on the `transitionFromRight` open path
//   (BottomSheet.java:1739-1741) and the recurring 200-250ms DEFAULT modal
//   grammar. (The plain-open Java path is `openDuration = 400`
//   (BottomSheet.java:210) with `openInterpolator = EASE_OUT_QUINT`
//   (BottomSheet.java:211, 1742-1746); both knobs stay overridable here.);
// - dismiss animation: 180ms `CubicBezierInterpolator.EASE_OUT`
//   (BottomSheet.java:1870-1871; the 330ms CELL_TYPE_CALL variant and the
//   200ms-DEFAULT `dismissWithButtonClick` animator, BottomSheet.java:2029-2033,
//   are not ported — every pop runs the 180ms dismiss);
// - companion chrome (nav-bar/dim companions) animates at 320ms
//   EASE_OUT_QUINT (BottomSheet.java:502-512) — exposed as
//   [kSheetCompanionDuration] for hosts;
// - touch outside dismisses by default (`canDismissWithTouchOutside = true`,
//   BottomSheet.java:198, 1647-1649);
// - selector ripple on cells (Theme.getSelectorDrawable,
//   BottomSheet.java:1037-1039) is not ported (no Material dependency).
library;

import 'package:flutter/widgets.dart';

import '../../foundation/tg_curves.dart';
import '../../glass/geometry.dart';
import '../../glass/glass_panel.dart';
import '../../glass/strategy.dart';
import '../../glass/surface_colors.dart';
import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';

/// Top corner radius of the sheet panel: 12dp — the `sheet_shadow_round`
/// 9-patch radius as replicated in code (PollVotesAlert.java:776,
/// GroupCallActivity.java:2886).
const double kSheetCornerRadius = 12.0;

/// Barrier dim opacity: `dimBehindAlpha = 51` -> 51/255 = 0.2
/// (BottomSheet.java:219).
const double kSheetDimBehindAlpha = 51 / 255;

/// The default barrier color: black at [kSheetDimBehindAlpha]
/// (0x33 == 51, BottomSheet.java:219).
const Color kSheetBarrierColor = Color(0x33000000);

/// Fixed title row height: 48dp (BottomSheet.java:1389, 1411-1413).
const double kSheetTitleRowHeight = 48.0;

/// Big title text size: 20dp (BottomSheet.java:1393).
const double kSheetBigTitleTextSize = 20.0;

/// Normal title text size: 16dp (BottomSheet.java:1398).
const double kSheetTitleTextSize = 16.0;

/// Big title horizontal padding: 21dp (BottomSheet.java:1395).
const double kSheetBigTitleHorizontalPadding = 21.0;

/// Normal title horizontal padding: 16dp (BottomSheet.java:1399).
const double kSheetTitleHorizontalPadding = 16.0;

/// Item cell height: 48dp (BottomSheet.java:1079-1081, 1440-1441).
const double kSheetCellHeight = 48.0;

/// Item icon frame: 56dp wide (BottomSheet.java:1044).
const double kSheetCellIconFrameWidth = 56.0;

/// Item icon frame: 48dp tall (BottomSheet.java:1044).
const double kSheetCellIconFrameHeight = 48.0;

/// Item text size: 16dp (BottomSheet.java:1058).
const double kSheetCellTextSize = 16.0;

/// Item text start inset when an icon is present: 72dp
/// (`setTextAndIcon`, BottomSheet.java:1115-1118).
const double kSheetCellTextInsetWithIcon = 72.0;

/// Container top/bottom padding: 8dp (`applyTopPadding` /
/// `applyBottomPadding`, BottomSheet.java:1357).
const double kSheetVerticalPadding = 8.0;

/// Open: 250ms — the catalog-pinned modal duration (Java's
/// `transitionFromRight` open, BottomSheet.java:1739-1741; the plain-open
/// field default is `openDuration = 400`, BottomSheet.java:210).
const Duration kSheetOpenDuration = Duration(milliseconds: 250);

/// Open curve: `CubicBezierInterpolator.DEFAULT` (BottomSheet.java:1741;
/// the plain-open path uses EASE_OUT_QUINT, BottomSheet.java:211, 1746).
const Cubic kSheetOpenCurve = TgCurves.defaultCubic;

/// Dismiss: 180ms (BottomSheet.java:1870).
const Duration kSheetDismissDuration = Duration(milliseconds: 180);

/// Dismiss curve: `CubicBezierInterpolator.EASE_OUT` (BottomSheet.java:1871).
const Cubic kSheetDismissCurve = TgCurves.easeOut;

/// Companion chrome (nav-bar/dim companion animators): 320ms EASE_OUT_QUINT
/// (BottomSheet.java:502-512). Informational — hosts animating chrome
/// alongside the sheet should use this.
const Duration kSheetCompanionDuration = Duration(milliseconds: 320);

/// One tappable row of a [TgBottomSheetRoute] items list — the data for a
/// `BottomSheetCell` type 0 (BottomSheet.java:1019-1083).
class TgBottomSheetItem<T> {
  /// Creates an item row. [value] is what the route pops with when the row
  /// is tapped (the Java `dismissWithButtonClick(position)` callback value,
  /// BottomSheet.java:1442-1444).
  const TgBottomSheetItem({required this.text, this.icon, this.value});

  /// Row label, 16dp `dialogTextBlack` (BottomSheet.java:1056-1058).
  final String text;

  /// Optional leading icon widget, centered in the 56x48 frame and tinted
  /// `dialogIcon` through [IconTheme] (BottomSheet.java:1041-1044).
  final Widget? icon;

  /// The result popped when this row is tapped.
  final T? value;
}

/// Shows a Telegram bottom sheet and returns the tapped item's
/// [TgBottomSheetItem.value] (null when dismissed by barrier tap or back).
///
/// The `ui/ActionBar/BottomSheet.java` port: a [PopupRoute] whose panel
/// slides up over [openDuration]/[openCurve] and back down over
/// [dismissDuration]/[dismissCurve], behind a black barrier at
/// [dimAlpha] opacity (BottomSheet.java:218-219).
Future<T?> showTgBottomSheet<T>(
  BuildContext context, {
  String? title,
  bool bigTitle = false,
  bool multipleLinesTitle = false,
  List<TgBottomSheetItem<T>> items = const <TgBottomSheetItem<Never>>[],
  Widget? content,
  bool useGlass = false,
  bool dimBehind = true,
  double dimAlpha = kSheetDimBehindAlpha,
  bool barrierDismissible = true,
  Duration openDuration = kSheetOpenDuration,
  Curve openCurve = kSheetOpenCurve,
  Duration dismissDuration = kSheetDismissDuration,
  Curve dismissCurve = kSheetDismissCurve,
  bool applyTopPadding = true,
  bool applyBottomPadding = true,
  TelegramResources? resources,
  bool useRootNavigator = false,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push(
    TgBottomSheetRoute<T>(
      title: title,
      bigTitle: bigTitle,
      multipleLinesTitle: multipleLinesTitle,
      items: items,
      content: content,
      useGlass: useGlass,
      dimBehind: dimBehind,
      dimAlpha: dimAlpha,
      barrierDismissible: barrierDismissible,
      openDuration: openDuration,
      openCurve: openCurve,
      dismissDuration: dismissDuration,
      dismissCurve: dismissCurve,
      applyTopPadding: applyTopPadding,
      applyBottomPadding: applyBottomPadding,
      resources: resources,
    ),
  );
}

/// The modal route behind [showTgBottomSheet] — the `BottomSheet` dialog
/// itself (window + `ContainerView`, BottomSheet.java:1200+).
///
/// The panel is a top-rounded (12dp, [kSheetCornerRadius]) surface: solid
/// `dialogBackground` by default (the tinted `sheet_shadow_round`,
/// BottomSheet.java:1194-1195), or a [FrostedPanel] glass surface over the
/// same key when [useGlass] is set. Content stacks title row, item cells,
/// then [content], padded per BottomSheet.java:1357 plus the ambient bottom
/// view padding (nav bar) and lifted above the keyboard inset.
class TgBottomSheetRoute<T> extends PopupRoute<T> {
  /// Creates the route; see [showTgBottomSheet] for the convenience wrapper.
  TgBottomSheetRoute({
    this.title,
    this.bigTitle = false,
    this.multipleLinesTitle = false,
    this.items = const <TgBottomSheetItem<Never>>[],
    this.content,
    this.useGlass = false,
    this.dimBehind = true,
    this.dimAlpha = kSheetDimBehindAlpha,
    this.barrierDismissible = true,
    this.openDuration = kSheetOpenDuration,
    this.openCurve = kSheetOpenCurve,
    this.dismissDuration = kSheetDismissDuration,
    this.dismissCurve = kSheetDismissCurve,
    this.applyTopPadding = true,
    this.applyBottomPadding = true,
    this.resources,
    super.settings,
  });

  /// Key on the sheet panel (the clipped round-rect surface) for tests and
  /// tooling.
  static const Key panelKey = ValueKey<String>('TgBottomSheet.panel');

  /// Optional title row text (BottomSheet.java:1388-1413).
  final String? title;

  /// Big title style: 20dp Roboto Medium `dialogTextBlack`
  /// (BottomSheet.java:1391-1395); otherwise 16dp `dialogTextGray2`
  /// (BottomSheet.java:1396-1399).
  final bool bigTitle;

  /// Wrapping title, up to 5 lines (BottomSheet.java:1401-1404); drops the
  /// fixed 48dp row height (WRAP_CONTENT, BottomSheet.java:1411).
  final bool multipleLinesTitle;

  /// Item rows, one 48dp cell each (BottomSheet.java:1436-1444).
  final List<TgBottomSheetItem<T>> items;

  /// Custom content below the items (the Java `customView`,
  /// BottomSheet.java:1415-1430).
  final Widget? content;

  /// Renders the panel as a [FrostedPanel] glass surface over
  /// `dialogBackground` instead of the solid fill.
  final bool useGlass;

  /// Whether the barrier dims (`dimBehind`, BottomSheet.java:218, 1807-1809).
  final bool dimBehind;

  /// Barrier dim opacity 0..1 (`dimBehindAlpha`/255, BottomSheet.java:219,
  /// 1811-1813).
  final double dimAlpha;

  /// Tap outside dismisses (`canDismissWithTouchOutside`,
  /// BottomSheet.java:198, 1647-1649).
  @override
  final bool barrierDismissible;

  /// Open duration; default [kSheetOpenDuration] (BottomSheet.java:1739,
  /// overridable like `openDuration`, BottomSheet.java:210).
  final Duration openDuration;

  /// Open curve; default [kSheetOpenCurve] (BottomSheet.java:1741).
  final Curve openCurve;

  /// Dismiss duration; default [kSheetDismissDuration]
  /// (BottomSheet.java:1870).
  final Duration dismissDuration;

  /// Dismiss curve; default [kSheetDismissCurve] (BottomSheet.java:1871).
  final Curve dismissCurve;

  /// 8dp top container padding (`applyTopPadding`, BottomSheet.java:1357).
  final bool applyTopPadding;

  /// 8dp bottom container padding (`applyBottomPadding`,
  /// BottomSheet.java:1357).
  final bool applyBottomPadding;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)` (the Java `resourcesProvider`
  /// convention, BottomSheet.java:1031-1034).
  final TelegramResources? resources;

  CurvedAnimation? _curvedAnimation;

  static final Animatable<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  );

  @override
  Color? get barrierColor {
    if (!dimBehind) {
      return null;
    }
    // `backDrawable` is black at `dimBehindAlpha` (BottomSheet.java:219,
    // 1563), faded with the sheet animation (BottomSheet.java:1734, 1868).
    final int alpha = (dimAlpha * 255).round().clamp(0, 255);
    return Color.fromARGB(alpha, 0, 0, 0);
  }

  @override
  Curve get barrierCurve => openCurve;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => openDuration;

  @override
  Duration get reverseTransitionDuration => dismissDuration;

  Animation<Offset> _position(Animation<double> animation) {
    CurvedAnimation? curved = _curvedAnimation;
    if (curved == null || !identical(curved.parent, animation)) {
      curved?.dispose();
      curved = CurvedAnimation(
        parent: animation,
        curve: openCurve,
        // Java dismiss is a fresh forward animator translationY 0 -> height
        // with EASE_OUT on *forward* time (BottomSheet.java:1859-1871);
        // Flutter evaluates reverseCurve on the decreasing parent value, so
        // the flipped curve reproduces the identical trajectory
        // (offset(t) = 1 - flipped(1 - t) = easeOut(t)).
        reverseCurve: dismissCurve.flipped,
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

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = this.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final String? title = this.title;
    final Widget? content = this.content;
    // Nav-bar inset drawn inside the panel (the Java sheet's background
    // extends behind the navigation bar, BottomSheet.java:1861-1864);
    // keyboard inset lifts the whole panel.
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (title != null)
          _SheetTitle(
            title: title,
            big: bigTitle,
            multiline: multipleLinesTitle,
            route: this,
          ),
        for (final TgBottomSheetItem<T> item in items)
          TgBottomSheetCell(
            text: item.text,
            icon: item.icon,
            bigTitle: bigTitle,
            resources: resources,
            // Java pops through `dismissWithButtonClick(position)`
            // (BottomSheet.java:1442-1444); the port reuses the single
            // 180ms dismiss for every pop.
            onTap: () => Navigator.pop<T>(context, item.value),
          ),
        ?content,
      ],
    );

    // Container padding (BottomSheet.java:1357) + nav-bar inset.
    column = Padding(
      padding: EdgeInsets.only(
        top: applyTopPadding ? kSheetVerticalPadding : 0.0,
        bottom: (applyBottomPadding ? kSheetVerticalPadding : 0.0) + bottomInset,
      ),
      child: column,
    );

    Widget panel;
    if (useGlass) {
      panel = FrostedPanel(
        style: GlassSurfaceStyle.themed(
          resources: resources ?? TelegramTheme.resources(context),
          colorKey: TelegramColorKey.dialogBackground,
          tier: GlassTier.frosted,
        ),
        borderRadius: const GlassRadii(
          topLeft: kSheetCornerRadius,
          topRight: kSheetCornerRadius,
          bottomRight: 0,
          bottomLeft: 0,
        ),
        child: column,
      );
    } else {
      // `sheet_shadow_round` tinted `dialogBackground` MULTIPLY
      // (BottomSheet.java:1194-1195), minus the 9-patch shadow.
      panel = ColoredBox(
        color: _color(context, TelegramColorKey.dialogBackground),
        child: column,
      );
    }

    panel = ClipRRect(
      key: panelKey,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(kSheetCornerRadius),
      ),
      child: panel,
    );

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: SizedBox(
          width: double.infinity,
          // translationY containerHeight -> 0 (BottomSheet.java:1730-1733):
          // sliding by the panel's own height, inside the page so the
          // barrier stays put.
          child: SlideTransition(
            position: _position(animation),
            child: panel,
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

/// The 48dp title row (BottomSheet.java:1388-1413).
class _SheetTitle extends StatelessWidget {
  const _SheetTitle({
    required this.title,
    required this.big,
    required this.multiline,
    required this.route,
  });

  final String title;
  final bool big;
  final bool multiline;
  final TgBottomSheetRoute<Object?> route;

  @override
  Widget build(BuildContext context) {
    // Big: 20dp bold `dialogTextBlack`, padding (21, 6 [14], 21, 8)
    // (BottomSheet.java:1391-1395); normal: 16dp `dialogTextGray2`,
    // padding (16, 0 [8], 16, 8) (BottomSheet.java:1396-1399).
    final EdgeInsetsDirectional padding = big
        ? EdgeInsetsDirectional.fromSTEB(
            kSheetBigTitleHorizontalPadding,
            multiline ? 14.0 : 6.0,
            kSheetBigTitleHorizontalPadding,
            8.0,
          )
        : EdgeInsetsDirectional.fromSTEB(
            kSheetTitleHorizontalPadding,
            multiline ? 8.0 : 0.0,
            kSheetTitleHorizontalPadding,
            8.0,
          );
    final TextStyle style = big
        ? TextStyle(
            fontSize: kSheetBigTitleTextSize,
            // `AndroidUtilities.bold()` = fonts/rmedium.ttf
            // (AndroidUtilities.java:260-269), bundled as w500
            // `RobotoMedium`.
            fontFamily: 'RobotoMedium',
            package: 'telegram_ui',
            fontWeight: FontWeight.w500,
            color: route._color(context, TelegramColorKey.dialogTextBlack),
          )
        : TextStyle(
            fontSize: kSheetTitleTextSize,
            color: route._color(context, TelegramColorKey.dialogTextGray2),
          );
    final Widget text = Text(
      title,
      maxLines: multiline ? 5 : 1,
      // Java: TruncateAt.END multiline / TruncateAt.MIDDLE single-line
      // (BottomSheet.java:1401-1409); Flutter has no middle ellipsis.
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (multiline) {
      // WRAP_CONTENT (BottomSheet.java:1411).
      return Padding(padding: padding, child: text);
    }
    // Fixed 48dp row, CENTER_VERTICAL gravity (BottomSheet.java:1410-1413).
    return SizedBox(
      height: kSheetTitleRowHeight,
      child: Padding(
        padding: padding,
        child: Align(alignment: AlignmentDirectional.centerStart, child: text),
      ),
    );
  }
}

/// One 48dp sheet row — `BottomSheetCell` type 0
/// (BottomSheet.java:1019-1083).
///
/// Geometry: 56x48 start-aligned icon frame tinted `dialogIcon`
/// (BottomSheet.java:1043-1044); 16dp single-line text in `dialogTextBlack`
/// vertically centered (BottomSheet.java:1052-1060), inset 72dp when an icon
/// is present, else 16dp (21dp under a big title)
/// (BottomSheet.java:1115-1125). The Android selector ripple
/// (BottomSheet.java:1037-1039) is not ported.
class TgBottomSheetCell extends StatelessWidget {
  /// Creates a sheet row.
  const TgBottomSheetCell({
    super.key,
    required this.text,
    this.icon,
    this.bigTitle = false,
    this.onTap,
    this.resources,
  });

  /// Row label (BottomSheet.java:1106).
  final String text;

  /// Leading icon widget, centered in the 56x48 frame; receives the
  /// `dialogIcon` tint via [IconTheme] (PorterDuff MULTIPLY on Android,
  /// BottomSheet.java:1043).
  final Widget? icon;

  /// Widens the no-icon text inset 16dp -> 21dp (BottomSheet.java:1123).
  final bool bigTitle;

  /// Tap handler (`dismissWithButtonClick`, BottomSheet.java:1442-1444).
  final VoidCallback? onTap;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
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
    final Widget? icon = this.icon;
    final double sidePadding =
        bigTitle ? kSheetBigTitleHorizontalPadding : kSheetTitleHorizontalPadding;
    // 72dp with icon (BottomSheet.java:1115-1118), else 16/21dp
    // (BottomSheet.java:1123).
    final double textInset =
        icon != null ? kSheetCellTextInsetWithIcon : sidePadding;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: kSheetCellHeight,
          width: double.infinity,
          child: Stack(
            children: <Widget>[
              if (icon != null)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  width: kSheetCellIconFrameWidth,
                  height: kSheetCellIconFrameHeight,
                  child: IconTheme.merge(
                    data: IconThemeData(
                      color: _color(context, TelegramColorKey.dialogIcon),
                      size: 24,
                    ),
                    // ScaleType.CENTER (BottomSheet.java:1042).
                    child: Center(child: icon),
                  ),
                ),
              PositionedDirectional(
                start: textInset,
                end: sidePadding,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    text,
                    maxLines: 1,
                    // TruncateAt.END (BottomSheet.java:1055).
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: kSheetCellTextSize,
                      color: _color(context, TelegramColorKey.dialogTextBlack),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
