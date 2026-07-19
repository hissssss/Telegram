// The popup / context menu (PLAN_UIKIT.md M4).
//
// Port of `ui/ActionBar/ActionBarPopupWindow.java` — the
// `ActionBarPopupWindowLayout` surface, its open/dismiss animations, and the
// `GapView` separator — with every constant cited:
//
// - surface: 9-patch `popup_fixed_alert2` (rounded rect + soft drop shadow)
//   tinted `key_actionBarDefaultSubmenuBackground` MULTIPLY
//   (ActionBarPopupWindow.java:153, 164-171), layout padding 8dp all around
//   = the shadow ring (:166); corner radius 12dp (the gap-clip path insets
//   the drawable bounds by 8dp and rounds them at dp(12), :542-549);
// - open (`startAnimation`, static variant :843-914): the container does
//   NOT view-scale — the background's drawn bounds grow vertically
//   (`backScaleY` 0 -> 1) together with `backAlpha` 0 -> 255 (:891-895),
//   children clipped to the revealed background (`clipChildren`, :533-539);
//   duration `150 + 16 * visibleCount` ms (:896; [TgMotion.menuOpenDuration]);
//   every item runs translationY -6dp -> 0 plus alpha 0 -> 1 (0.5 disabled)
//   offset per index via `AndroidUtilities.cascade(t, index, count, 4)`
//   (:875-895; cascade: AndroidUtilities.java:5273-5278); all fractions run
//   through the Android `ValueAnimator` default
//   AccelerateDecelerateInterpolator (no interpolator is set, :874-896);
// - dismiss (:1024-1100): whole popup translationY -> -5dp (+5 if shown
//   from bottom) + alpha -> 0 over 150ms (`dismissAnimationDuration`, :69,
//   :1064-1068); `scaleOut` variant scales to 0.8 instead (:1058-1063);
//   pivot top-right (:847-848);
// - dim: opt-in `dimBehind()`, default amount 0.2 (:783-795), applied
//   instantly via the window flag and removed at dismiss start (:1026 — the
//   port's barrier fades out with the 150ms dismiss instead);
// - separator (`GapView`, :1110-1140): a full-width band colored
//   `key_actionBarDefaultSubmenuSeparator`, canonical height 8dp
//   (`ItemOptions.addGap` adds it MATCH_PARENT x 8, ItemOptions.java:786-792);
// - rows scroll when the menu exceeds the screen (the layout hosts a
//   ScrollView, :185-203).
//
// Deliberately NOT ported (PLAN_UIKIT.md M4 defers the first two): the
// `fitItems` width equalization (:206-248 — the port relies on
// [IntrinsicWidth]); the nested swipe-back sublayout (`FLAG_USE_SWIPEBACK`,
// :104, 180-183); the member-variant reveal that triggers each row as the
// front passes it (180ms DecelerateInterpolator, :324-404 — the static
// cascade variant is the port); the background split around the gap zone
// (:467-523 — the gap band paints over the surface instead); the GapView
// `greydivider` shadow overlay (:1120, 1132-1139 — a bitmap asset); the
// reactions enter-transition (:575-584).
//
// The anchored placement itself ([TgPopupMenuLayoutDelegate]) is Flutter-side
// glue: on Android the framework `PopupWindow` positions and edge-fits the
// menu — the delegate reproduces "at the anchor, clamped on screen"
// (inferred, not Telegram code).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../components/app_bar/glass_app_bar.dart'
    show TgAccelerateDecelerateCurve;
import '../foundation/tg_motion.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';
import 'tg_menu_item.dart';

/// Surface corner radius: 12dp (`path.addRoundRect(rect, dp(12), dp(12))` on
/// the 8dp-inset bounds, ActionBarPopupWindow.java:542-549; matches the row
/// `selectorRad = 12`, ActionBarMenuSubItem.java:47).
const double kTgPopupMenuCornerRadius = 12.0;

/// Shadow-ring padding: 8dp all around (`setPadding(dp(8), ...)`,
/// ActionBarPopupWindow.java:166).
const double kTgPopupMenuShadowPadding = 8.0;

/// Per-item open slide distance: 6dp (`(1f - at) * dp(-6)`,
/// ActionBarPopupWindow.java:885).
const double kTgPopupMenuItemSlide = 6.0;

/// Cascade wavelength: 4 (`AndroidUtilities.cascade(t, index, count, 4)`,
/// ActionBarPopupWindow.java:884).
const double kTgPopupMenuCascadeWaveLength = 4.0;

/// Dismiss slide distance: 5dp (`TRANSLATION_Y, dp(shownFromBottom ? 5 :
/// -5)`, ActionBarPopupWindow.java:1066).
const double kTgPopupMenuDismissSlide = 5.0;

/// `scaleOut` dismiss target scale: 0.8 (ActionBarPopupWindow.java:
/// 1058-1063).
const double kTgPopupMenuDismissScale = 0.8;

/// Default opt-in dim amount: 0.2 (`dimBehind()`,
/// ActionBarPopupWindow.java:783-784).
const double kTgPopupMenuDimAmount = 0.2;

/// Separator band height: 8dp (`ItemOptions.addGap` adds the GapView
/// MATCH_PARENT x 8, ItemOptions.java:786-792).
const double kTgMenuGapHeight = 8.0;

/// The open interpolator: Android's `ValueAnimator` default
/// AccelerateDecelerateInterpolator — the popup animator sets none
/// (ActionBarPopupWindow.java:874-896).
const TgAccelerateDecelerateCurve _kOpenCurve = TgAccelerateDecelerateCurve();

/// Port of `AndroidUtilities.cascade(fullAnimationT, position, count,
/// waveLength)` (AndroidUtilities.java:5273-5278): a sliding clamp window —
/// item [position] of [count] runs over `waveDuration = min(waveLength,
/// count) / count` of the timeline, offset by `position / count * (1 -
/// waveDuration)`.
///
/// With `count <= waveLength` the window spans the whole timeline and every
/// item animates in unison; beyond that, earlier items land first.
double tgMenuCascade(
  double t,
  double position,
  double count,
  double waveLength,
) {
  if (count <= 0) {
    return t;
  }
  final double waveDuration = 1.0 / count * math.min(waveLength, count);
  final double waveOffset = position / count * (1.0 - waveDuration);
  return ((t - waveOffset) / waveDuration).clamp(0.0, 1.0);
}

/// The 8dp separator band between menu sections — the
/// `ActionBarPopupWindow.GapView` port (ActionBarPopupWindow.java:1110-1140):
/// a full-width `actionBarDefaultSubmenuSeparator` fill. The `greydivider`
/// shadow overlay (tinted `windowBackgroundGrayShadow`, :1120) is a bitmap
/// asset and is not ported.
///
/// [TgPopupMenu] recognizes gaps in its child list (the Java `child
/// instanceof GapView` checks, :854, 881): they are excluded from the open
/// cascade and from the row count that scales the open duration, and the row
/// after a gap re-rounds its top selector corners.
class TgMenuGap extends StatelessWidget {
  /// Creates a separator band.
  const TgMenuGap({
    super.key,
    this.height = kTgMenuGapHeight,
    this.colorKey = TelegramColorKey.actionBarDefaultSubmenuSeparator,
    this.resources,
  });

  /// Band height, canonical 8dp (ItemOptions.java:786-792).
  final double height;

  /// Fill key, `actionBarDefaultSubmenuSeparator` by default
  /// (ActionBarPopupWindow.java:1115).
  final int colorKey;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  @override
  Widget build(BuildContext context) {
    final TelegramResources? resources = this.resources;
    final Color color = resources != null
        ? resources.getColor(colorKey)
        : TelegramTheme.colorOf(context, colorKey);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ColoredBox(color: color),
    );
  }
}

/// The popup-menu surface — the `ActionBarPopupWindowLayout` port
/// (ActionBarPopupWindow.java:103-681).
///
/// A rounded-rect card (`actionBarDefaultSubmenuBackground`, r=12dp) inside
/// an 8dp shadow ring that self-plays the Telegram open animation on mount:
/// the background reveals vertically from the top (bottom when
/// [shownFromBottom]) over `150 + 16 * n` ms while each non-gap child slides
/// in from -6dp with a cascade fade (ActionBarPopupWindow.java:843-914).
/// Children taller than the incoming height constraint scroll
/// (ActionBarPopupWindow.java:185-203).
///
/// [children] are arbitrary widgets — typically [TgMenuItem] rows and
/// [TgMenuGap] separators. The first visible row, the last one, and rows
/// directly after a gap receive selector-corner rounding through
/// [TgMenuRowScope] (`updateRadialSelectors`,
/// ActionBarPopupWindow.java:612-643).
///
/// Like every component in this package, the menu takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise keys resolve through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class TgPopupMenu extends StatefulWidget {
  /// Creates a popup-menu surface.
  const TgPopupMenu({
    super.key,
    required this.children,
    this.shownFromBottom = false,
    this.animateOpen = true,
    this.backgroundColorKey = TelegramColorKey.actionBarDefaultSubmenuBackground,
    this.resources,
  });

  /// Key on the surface [CustomPaint], for tests and tooling.
  static const Key surfaceKey = ValueKey<String>('TgPopupMenu.surface');

  /// Menu rows and separators, top to bottom.
  final List<Widget> children;

  /// Anchors the reveal at the bottom (`FLAG_SHOWN_FROM_BOTTOM`,
  /// ActionBarPopupWindow.java:105, 176-178, 491-493): the background grows
  /// upward, the cascade runs bottom-up (:884) and items slide from +6dp
  /// (:385).
  final bool shownFromBottom;

  /// Whether the open animation plays on mount (`setAnimationEnabled`,
  /// ActionBarPopupWindow.java:713-715). False renders the settled menu.
  final bool animateOpen;

  /// Surface fill key, `actionBarDefaultSubmenuBackground` by default
  /// (ActionBarPopupWindow.java:170).
  final int backgroundColorKey;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  /// Non-gap children — what scales the open duration (`visibleCount`,
  /// ActionBarPopupWindow.java:851-863, 896).
  static int visibleItemCount(List<Widget> children) {
    int count = 0;
    for (final Widget child in children) {
      if (child is! TgMenuGap) {
        count++;
      }
    }
    return count;
  }

  @override
  State<TgPopupMenu> createState() => _TgPopupMenuState();
}

class _TgPopupMenuState extends State<TgPopupMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // `windowAnimatorSet.setDuration(150 + 16 * visibleCount)`
    // (ActionBarPopupWindow.java:896).
    _controller = AnimationController(
      vsync: this,
      duration:
          TgMotion.menuOpenDuration(TgPopupMenu.visibleItemCount(widget.children)),
      value: widget.animateOpen ? 0.0 : 1.0,
    );
    if (widget.animateOpen) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(TgPopupMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration =
        TgMotion.menuOpenDuration(TgPopupMenu.visibleItemCount(widget.children));
  }

  @override
  void dispose() {
    _controller.dispose();
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
    final List<Widget> children = widget.children;
    final int count = children.length;
    final bool fromBottom = widget.shownFromBottom;
    // First/last visible non-gap rows for the selector corners
    // (`updateRadialSelectors`, ActionBarPopupWindow.java:612-643).
    int firstRow = -1;
    int lastRow = -1;
    for (int i = 0; i < count; i++) {
      if (children[i] is! TgMenuGap) {
        if (firstRow < 0) {
          firstRow = i;
        }
        lastRow = i;
      }
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? _) {
        // Every animated fraction runs through the ValueAnimator default
        // AccelerateDecelerateInterpolator (ActionBarPopupWindow.java:
        // 874-896 set no interpolator).
        final double t = _kOpenCurve.transform(_controller.value);

        final List<Widget> wrapped = <Widget>[];
        for (int i = 0; i < count; i++) {
          final Widget child = children[i];
          if (child is TgMenuGap) {
            // Gaps skip the cascade (`child instanceof GapView` -> continue,
            // ActionBarPopupWindow.java:881-883); they fade with the
            // background alpha.
            wrapped.add(Opacity(opacity: t, child: child));
            continue;
          }
          // `cascade(t, shownFromBottom ? count - 1 - a : a, count, 4)` over
          // the raw child index including gaps
          // (ActionBarPopupWindow.java:884).
          final double at = tgMenuCascade(
            t,
            (fromBottom ? count - 1 - i : i).toDouble(),
            count.toDouble(),
            kTgPopupMenuCascadeWaveLength,
          );
          wrapped.add(
            Opacity(
              // The 0.5 disabled factor (:886) composes with the row's own
              // disabled opacity.
              opacity: at,
              child: Transform.translate(
                // -6dp -> 0 (+6 from bottom) (ActionBarPopupWindow.java:885;
                // member variant sign, :385).
                offset: Offset(
                  0,
                  (1.0 - at) *
                      (fromBottom
                          ? kTgPopupMenuItemSlide
                          : -kTgPopupMenuItemSlide),
                ),
                child: TgMenuRowScope(
                  roundTop:
                      i == firstRow || (i > 0 && children[i - 1] is TgMenuGap),
                  roundBottom: i == lastRow,
                  child: child,
                ),
              ),
            ),
          );
        }

        return CustomPaint(
          key: TgPopupMenu.surfaceKey,
          painter: TgPopupMenuSurfacePainter(
            color: _color(context, widget.backgroundColorKey),
            alpha: t,
            revealFraction: t,
            shownFromBottom: fromBottom,
          ),
          child: Padding(
            padding: const EdgeInsets.all(kTgPopupMenuShadowPadding),
            child: ClipRect(
              clipper: _TgPopupMenuRevealClipper(
                fraction: t,
                inset: kTgPopupMenuShadowPadding,
                shownFromBottom: fromBottom,
              ),
              child: IntrinsicWidth(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: wrapped,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints the popup surface: the `popup_fixed_alert2` 9-patch tinted
/// `actionBarDefaultSubmenuBackground` (ActionBarPopupWindow.java:153,
/// 164-171) as a rounded rect (r=12dp) inset [kTgPopupMenuShadowPadding]
/// from the bounds, with a soft drop shadow approximating the 9-patch ring
/// (inferred — the bitmap itself is not portable).
///
/// During the open animation the drawn body grows vertically —
/// `backgroundDrawable.setBounds(0, 0, w, h * backScaleY)` from the top, or
/// anchored at the bottom when [shownFromBottom]
/// (ActionBarPopupWindow.java:491-523) — while its alpha follows `backAlpha`
/// (:490).
class TgPopupMenuSurfacePainter extends CustomPainter {
  /// Creates the surface painter.
  const TgPopupMenuSurfacePainter({
    required this.color,
    this.alpha = 1.0,
    this.revealFraction = 1.0,
    this.cornerRadius = kTgPopupMenuCornerRadius,
    this.inset = kTgPopupMenuShadowPadding,
    this.shownFromBottom = false,
  });

  /// Surface fill (`key_actionBarDefaultSubmenuBackground`,
  /// ActionBarPopupWindow.java:170).
  final Color color;

  /// Background alpha 0..1 (`backAlpha` 0..255,
  /// ActionBarPopupWindow.java:893).
  final double alpha;

  /// Vertical reveal 0..1 (`backScaleY`, ActionBarPopupWindow.java:892).
  final double revealFraction;

  /// Body corner radius, 12dp (ActionBarPopupWindow.java:542-549).
  final double cornerRadius;

  /// Shadow-ring inset, 8dp (ActionBarPopupWindow.java:166).
  final double inset;

  /// Anchors the reveal at the bottom (ActionBarPopupWindow.java:491-493).
  final bool shownFromBottom;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0.0) {
      return;
    }
    final double revealed = size.height * revealFraction.clamp(0.0, 1.0);
    final Rect body = shownFromBottom
        ? Rect.fromLTRB(
            inset,
            size.height - revealed + inset,
            size.width - inset,
            size.height - inset,
          )
        : Rect.fromLTRB(
            inset,
            inset,
            size.width - inset,
            revealed - inset,
          );
    if (body.bottom <= body.top || body.right <= body.left) {
      return;
    }
    final RRect rrect =
        RRect.fromRectAndRadius(body, Radius.circular(cornerRadius));
    // Soft drop shadow in the 8dp ring — approximation of the
    // popup_fixed_alert2 9-patch shadow (inferred).
    canvas.drawRRect(
      rrect.shift(const Offset(0, 1)),
      Paint()
        ..color = const Color(0xFF000000).withValues(alpha: 0.25 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = color.withValues(alpha: color.a * alpha),
    );
  }

  @override
  bool shouldRepaint(TgPopupMenuSurfacePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.alpha != alpha ||
      oldDelegate.revealFraction != revealFraction ||
      oldDelegate.cornerRadius != cornerRadius ||
      oldDelegate.inset != inset ||
      oldDelegate.shownFromBottom != shownFromBottom;
}

/// Clips the menu content to the revealed background — the `clipChildren`
/// clip to the drawn bounds inset by the background paddings
/// (ActionBarPopupWindow.java:533-539). Operates in the padded child space:
/// the full popup is `childHeight + 2 * inset` tall.
class _TgPopupMenuRevealClipper extends CustomClipper<Rect> {
  const _TgPopupMenuRevealClipper({
    required this.fraction,
    required this.inset,
    required this.shownFromBottom,
  });

  final double fraction;
  final double inset;
  final bool shownFromBottom;

  @override
  Rect getClip(Size size) {
    final double full = size.height + 2 * inset;
    if (shownFromBottom) {
      final double top =
          (full * (1.0 - fraction)).clamp(0.0, size.height);
      return Rect.fromLTRB(0, top, size.width, size.height);
    }
    final double bottom =
        (full * fraction - 2 * inset).clamp(0.0, size.height);
    return Rect.fromLTRB(0, 0, size.width, bottom);
  }

  @override
  bool shouldReclip(_TgPopupMenuRevealClipper oldClipper) =>
      oldClipper.fraction != fraction ||
      oldClipper.inset != inset ||
      oldClipper.shownFromBottom != shownFromBottom;
}

/// One entry of a [showTgPopupMenu] menu: an action row
/// ([TgPopupMenuItem]) or a separator ([TgPopupMenuGap]).
sealed class TgPopupMenuEntry<T> {
  /// Const base constructor for subclasses.
  const TgPopupMenuEntry();
}

/// One action row of a [showTgPopupMenu] menu — the data behind a
/// [TgMenuItem] (the `ItemOptions.add(...)` payload shape,
/// ui/Components/ItemOptions.java).
final class TgPopupMenuItem<T> extends TgPopupMenuEntry<T> {
  /// Creates an action row. [value] is what [showTgPopupMenu] resolves with
  /// when the row is tapped.
  const TgPopupMenuItem({
    required this.text,
    this.icon,
    this.rightIcon,
    this.subtext,
    this.checked,
    this.enabled = true,
    this.value,
    this.onTap,
    this.textColorKey,
    this.iconColorKey,
  });

  /// Row label (ActionBarMenuSubItem.java:91-98).
  final String text;

  /// Optional leading icon widget (ActionBarMenuSubItem.java:86-89).
  final Widget? icon;

  /// Optional trailing icon widget (ActionBarMenuSubItem.java:159-176).
  final Widget? rightIcon;

  /// Optional 13dp subtext (ActionBarMenuSubItem.java:356-378).
  final String? subtext;

  /// Non-null shows the leading check slot (ActionBarMenuSubItem.java:
  /// 104-113).
  final bool? checked;

  /// Disabled rows draw at 0.5 alpha and ignore taps
  /// (ActionBarPopupWindow.java:886).
  final bool enabled;

  /// The result popped when this row is tapped.
  final T? value;

  /// Per-row callback, fired before the menu dismisses.
  final VoidCallback? onTap;

  /// Label color-key override — e.g. `text_RedBold` for destructive rows
  /// (the `ItemOptions.makeDangerous` convention); null keeps
  /// `actionBarDefaultSubmenuItem`.
  final int? textColorKey;

  /// Icon tint key override; null keeps `actionBarDefaultSubmenuItemIcon`.
  final int? iconColorKey;
}

/// A separator band entry — an 8dp [TgMenuGap]
/// (`ItemOptions.addGap`, ItemOptions.java:786-792).
final class TgPopupMenuGap<T> extends TgPopupMenuEntry<T> {
  /// Creates a separator entry.
  const TgPopupMenuGap();
}

/// Shows a [TgPopupMenu] anchored at [position] and returns the tapped
/// row's [TgPopupMenuItem.value] (null when dismissed by the barrier or
/// back).
///
/// The `ActionBarPopupWindow.showAsDropDown` + `startAnimation` port: the
/// menu opens instantly as a route (Android shows the popup window
/// immediately, ActionBarPopupWindow.java:833-841) and the surface plays the
/// `150 + 16 * n` ms reveal itself; dismissing runs the 150ms fade + 5dp
/// slide (or the [scaleOutDismiss] 0.8 scale) (:1024-1100). [dim] opts into
/// the 0.2 barrier dim (`dimBehind()`, :783-795).
Future<T?> showTgPopupMenu<T>(
  BuildContext context, {
  required RelativeRect position,
  required List<TgPopupMenuEntry<T>> entries,
  bool dim = false,
  double dimAmount = kTgPopupMenuDimAmount,
  bool scaleOutDismiss = false,
  bool shownFromBottom = false,
  bool barrierDismissible = true,
  TelegramResources? resources,
  bool useRootNavigator = false,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push(
    TgPopupMenuRoute<T>(
      position: position,
      entries: entries,
      dim: dim,
      dimAmount: dimAmount,
      scaleOutDismiss: scaleOutDismiss,
      shownFromBottom: shownFromBottom,
      barrierDismissible: barrierDismissible,
      resources: resources,
    ),
  );
}

/// The modal route behind [showTgPopupMenu] — `ActionBarPopupWindow` itself
/// (show :833-841, dismiss :1024-1100).
///
/// The forward transition is zero-length: Android shows the popup window
/// (and applies the opt-in dim flag) instantly, and the [TgPopupMenu]
/// surface plays the open reveal on its own clock. The reverse transition is
/// the 150ms dismiss ([TgMotion.menuCloseDuration]): a fade + 5dp slide
/// (ActionBarPopupWindow.java:1064-1068), or a fade + scale to 0.8 when
/// [scaleOutDismiss] (:1058-1063). Divergence: Java removes the dim
/// instantly at dismiss start (:1026); the barrier here fades with the
/// dismiss.
class TgPopupMenuRoute<T> extends PopupRoute<T> {
  /// Creates the route; see [showTgPopupMenu] for the convenience wrapper.
  TgPopupMenuRoute({
    required this.position,
    required this.entries,
    this.dim = false,
    this.dimAmount = kTgPopupMenuDimAmount,
    this.scaleOutDismiss = false,
    this.shownFromBottom = false,
    this.barrierDismissible = true,
    this.resources,
    super.settings,
  });

  /// Where the menu anchors, relative to the overlay: the menu's top-left
  /// sits at (`position.left`, `position.top`) — bottom-left at
  /// `position.bottom` from the overlay bottom when [shownFromBottom] —
  /// clamped on screen by [TgPopupMenuLayoutDelegate].
  final RelativeRect position;

  /// Menu rows and separators.
  final List<TgPopupMenuEntry<T>> entries;

  /// Opts into the barrier dim (`dimBehind()`,
  /// ActionBarPopupWindow.java:783-795); plain overflow menus keep it off.
  final bool dim;

  /// Barrier dim amount 0..1, default 0.2 (ActionBarPopupWindow.java:784).
  final double dimAmount;

  /// Dismisses by scaling to 0.8 instead of sliding (`setScaleOut`,
  /// ActionBarPopupWindow.java:95-97, 1058-1063).
  final bool scaleOutDismiss;

  /// Bottom-anchored reveal (`FLAG_SHOWN_FROM_BOTTOM`,
  /// ActionBarPopupWindow.java:105).
  final bool shownFromBottom;

  /// Tap outside dismisses (the outside-touchable PopupWindow default).
  @override
  final bool barrierDismissible;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  @override
  Color? get barrierColor {
    if (!dim) {
      return null;
    }
    final int alpha = (dimAmount * 255).round().clamp(0, 255);
    return Color.fromARGB(alpha, 0, 0, 0);
  }

  @override
  String? get barrierLabel => 'Dismiss';

  /// Zero: the window shows instantly; the surface animates itself
  /// (ActionBarPopupWindow.java:833-841, 916-995).
  @override
  Duration get transitionDuration => Duration.zero;

  /// The 150ms dismiss (`dismissAnimationDuration`,
  /// ActionBarPopupWindow.java:69).
  @override
  Duration get reverseTransitionDuration => TgMotion.menuCloseDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final Widget menu = TgPopupMenu(
      shownFromBottom: shownFromBottom,
      resources: resources,
      children: <Widget>[
        for (final TgPopupMenuEntry<T> entry in entries)
          switch (entry) {
            TgPopupMenuGap<T>() => TgMenuGap(resources: resources),
            final TgPopupMenuItem<T> item => TgMenuItem(
                text: item.text,
                icon: item.icon,
                rightIcon: item.rightIcon,
                subtext: item.subtext,
                checked: item.checked,
                enabled: item.enabled,
                textColorKey: item.textColorKey ??
                    TelegramColorKey.actionBarDefaultSubmenuItem,
                iconColorKey: item.iconColorKey ??
                    TelegramColorKey.actionBarDefaultSubmenuItemIcon,
                resources: resources,
                onTap: () {
                  // Callback, then close — the ItemOptions row convention.
                  item.onTap?.call();
                  Navigator.pop<T>(context, item.value);
                },
              ),
          },
      ],
    );
    return CustomSingleChildLayout(
      delegate: TgPopupMenuLayoutDelegate(
        position: position,
        shownFromBottom: shownFromBottom,
      ),
      child: _TgPopupMenuDismissTransition(
        animation: animation,
        scaleOut: scaleOutDismiss,
        shownFromBottom: shownFromBottom,
        child: menu,
      ),
    );
  }
}

/// Places the menu at its anchor and keeps it on screen — the Android
/// `PopupWindow` fitting behavior (inferred, not Telegram code). The child
/// is constrained loosely to the overlay, so an over-tall menu caps at the
/// screen height and scrolls inside [TgPopupMenu].
class TgPopupMenuLayoutDelegate extends SingleChildLayoutDelegate {
  /// Creates the delegate.
  const TgPopupMenuLayoutDelegate({
    required this.position,
    this.shownFromBottom = false,
  });

  /// The anchor rectangle relative to the overlay.
  final RelativeRect position;

  /// Anchors the menu's bottom edge at `position.bottom` from the overlay
  /// bottom instead of its top edge at `position.top`.
  final bool shownFromBottom;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x = position.left;
    double y = shownFromBottom
        ? size.height - position.bottom - childSize.height
        : position.top;
    x = x.clamp(0.0, math.max(0.0, size.width - childSize.width));
    y = y.clamp(0.0, math.max(0.0, size.height - childSize.height));
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(TgPopupMenuLayoutDelegate oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.shownFromBottom != shownFromBottom;
}

/// The dismiss transition (ActionBarPopupWindow.java:1054-1068): identity
/// while the route animation sits at 1; on pop the whole popup fades out
/// while sliding 5dp (up, or down when [shownFromBottom]) — or scaling to
/// 0.8 around the top-right pivot (:847-848, 1058-1063) when [scaleOut].
/// The reversing fraction runs through the ValueAnimator default
/// AccelerateDecelerateInterpolator, like the Java animators.
class _TgPopupMenuDismissTransition extends AnimatedWidget {
  const _TgPopupMenuDismissTransition({
    required Animation<double> animation,
    required this.scaleOut,
    required this.shownFromBottom,
    required this.child,
  }) : super(listenable: animation);

  final bool scaleOut;
  final bool shownFromBottom;
  final Widget child;

  Animation<double> get _animation => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) {
    final double value = _animation.value;
    if (value >= 1.0) {
      return child;
    }
    final double t = _kOpenCurve.transform(value);
    if (scaleOut) {
      return Opacity(
        opacity: t,
        child: Transform.scale(
          scale: kTgPopupMenuDismissScale +
              (1.0 - kTgPopupMenuDismissScale) * t,
          // `pivotX = measuredWidth, pivotY = 0`
          // (ActionBarPopupWindow.java:847-848) — the physical top-right,
          // not direction-aware, as in Java.
          alignment: Alignment.topRight,
          child: child,
        ),
      );
    }
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(
          0,
          (shownFromBottom
                  ? kTgPopupMenuDismissSlide
                  : -kTgPopupMenuDismissSlide) *
              (1.0 - t),
        ),
        child: child,
      ),
    );
  }
}
