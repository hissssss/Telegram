// The transient bottom banner ("undo toast") — ARCHITECTURE.md section 6,
// row "Bulletin".
//
// Port of `ui/Components/Bulletin.java`, with every constant cited:
//
// - durations: `DURATION_SHORT = 1500`, `DURATION_LONG = 2750`,
//   `DURATION_PROLONG = 5000` ms (Bulletin.java:89-91). The 2750ms
//   DURATION_LONG is the everyday default (BulletinFactory's standard
//   bulletins), so it is [kBulletinDurationDefault] here;
// - base layout: min height 48dp (`setMinimumHeight(dp(48))`,
//   Bulletin.java:797), padding 16dp horizontal / 8dp vertical
//   (Bulletin.java:800), background `undo_background` as a 16dp-radius
//   round rect (`setBackground(color, 16)` ->
//   `Theme.createRoundRectDrawable(dp(16), color)`, Bulletin.java:810-817)
//   — radius verified 16dp (callers may pass other roundings through
//   `setBackground(color, rounding)`, but the default is 16);
// - single-line content (`LottieLayout`, Bulletin.java:1973-2008): lottie
//   icon frame 56x48 start-aligned CENTER (Bulletin.java:1983-1985); text
//   15dp, single line, end-ellipsized, 8dp vertical text padding, margins
//   start 56 / end 16 within the padded frame, color `undo_infoColor`,
//   links `undo_cancelColor` (Bulletin.java:1999-2008). When no leading
//   widget is given the port starts the text at the container padding
//   (Java's LottieLayout always reserves the 56dp frame because its
//   RLottieImageView always exists);
// - trailing action (`UndoButton`, Bulletin.java:2232-2281): text 14dp
//   `AndroidUtilities.bold()` (Roboto Medium) `undo_cancelColor`, padding
//   (12, 8, 12, 8), 8dp side margins, END|CENTER_VERTICAL placement
//   (`ButtonLayout.setButton`, Bulletin.java:1322-1332); tapping runs the
//   action and hides the bulletin (`undo()`, Bulletin.java:2279-2292);
// - enter/exit: spring on offsetY from layout height to 0, dampingRatio
//   0.8, stiffness 400 (`SpringTransition`, Bulletin.java:1121-1172) —
//   mass 1 (the DynamicAnimation FloatValueHolder default);
// - auto-hide: posted after the enter transition completes, full [duration]
//   delay, cancelled while pressed and re-posted on release
//   (`setCanHide`, Bulletin.java:393-403);
// - swipe-to-dismiss (`ParentLayout`, Bulletin.java:600-660): translationX
//   follows the horizontal drag; released beyond width/3 the layout settles
//   to +-width over 200ms with Android's AccelerateInterpolator and hides
//   (Bulletin.java:645-653); below threshold it settles back over 200ms
//   with the ViewPropertyAnimator default AccelerateDecelerateInterpolator
//   (Bulletin.java:655). The fling path (SpringAnimation stiffness 100
//   no-bouncy, Bulletin.java:585-597) is not ported;
// - one visible bulletin: showing a new bulletin hides the current one
//   (Bulletin.java:285-288; `hideVisible`, Bulletin.java:214-218);
// - not ported: the wide-screen wrap-content mode (Bulletin.java:864-871),
//   the 8dp DST_OUT container edge gradient (Bulletin.java:1241-1254), the
//   press scale (ScaleStateListAnimator, Bulletin.java:806), the alternative
//   255/175ms DefaultTransition (Bulletin.java:1056-1119), and the blur-out
//   variant (Bulletin.java:1200).
//
// Undo variant — the `ui/Components/UndoView.java` countdown recipe,
// expressed as a Bulletin layout variant (kit-lens audit #19), not a
// separate component:
//
// - countdown circle: an 18dp ring (`rect` spans dp(15)..dp(15+18),
//   UndoView.java:319) stroked at 2dp with round caps in `undo_infoColor`
//   (UndoView.java:321-325); the arc starts at 12 o'clock and depletes
//   counter-clockwise, sweep `-360 * (timeLeft / 5000f)` — the divisor is
//   the literal 5000 regardless of the starting timeLeft
//   (UndoView.java:1694), so longer countdowns clamp to a full ring until
//   5s remain and shorter ones start partially depleted;
// - seconds text: `max(1, ceil(timeLeft / 1000))` (UndoView.java:1645-1649)
//   drawn centered in the ring at 12dp Roboto Medium `undo_infoColor`
//   (UndoView.java:327-330). A change of digit cross-fades over 150ms
//   (`timeReplaceProgress += 16f / 150f` per 16ms frame,
//   UndoView.java:1659-1665): the old digit slides 10dp down fading out,
//   the new one slides in from 10dp above fading in
//   (UndoView.java:1670-1690);
// - the countdown starts at show and ticks through the enter transition
//   (`lastUpdateTime = SystemClock.elapsedRealtime()`, UndoView.java:485);
//   default `timeLeft = 5000` ms (UndoView.java:482). When it empties the
//   view hides itself (`timeLeft <= 0 -> hide(true, ...)`,
//   UndoView.java:1697-1703);
// - commit/undo semantics (`hide(boolean apply, ...)`,
//   UndoView.java:384-403): apply=true (countdown expiry, replacement, any
//   non-undo dismissal) runs the action runnable — [onCommit] here; the
//   undo button hides with apply=false (UndoView.java:300-305), running the
//   cancel runnable — [onUndo];
// - undo button text: 14dp Roboto Medium `undo_cancelColor`
//   (UndoView.java:312-316) — identical to Bulletin's own UndoButton, so
//   the variant reuses the standard trailing action;
// - divergences: the ring is centered in Bulletin's standard 56x48 leading
//   frame instead of UndoView's absolute (15,15) placement; the enter/exit
//   motion is Bulletin's spring, not UndoView's 250ms translate
//   (UndoView.java:410-415); the `chats_undo` arrow icon next to the undo
//   label (UndoView.java:307-310) is not ported.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../../foundation/tg_text_styles.dart';
import '../../glass/geometry.dart';
import '../../glass/glass_panel.dart';
import '../../glass/presets.dart';
import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';

/// `DURATION_SHORT = 1500` ms (Bulletin.java:89).
const Duration kBulletinDurationShort = Duration(milliseconds: 1500);

/// `DURATION_LONG = 2750` ms (Bulletin.java:90) — the everyday default.
const Duration kBulletinDurationDefault = Duration(milliseconds: 2750);

/// `DURATION_PROLONG = 5000` ms (Bulletin.java:91).
const Duration kBulletinDurationLong = Duration(milliseconds: 5000);

/// Min banner height: 48dp (Bulletin.java:797).
const double kBulletinMinHeight = 48.0;

/// Horizontal content padding: 16dp (Bulletin.java:800).
const double kBulletinHorizontalPadding = 16.0;

/// Vertical content padding: 8dp (Bulletin.java:800).
const double kBulletinVerticalPadding = 8.0;

/// Background corner radius: 16dp (`setBackground(color, 16)`,
/// Bulletin.java:810-816).
const double kBulletinRadius = 16.0;

/// Text size: 15dp (Bulletin.java:2002).
const double kBulletinTextSize = 15.0;

/// Leading (lottie) frame width: 56dp (Bulletin.java:1985).
const double kBulletinLeadingWidth = 56.0;

/// Leading (lottie) frame height: 48dp (Bulletin.java:1985).
const double kBulletinLeadingHeight = 48.0;

/// Text end margin within the padded frame: 16dp (Bulletin.java:2005).
const double kBulletinTextEndMargin = 16.0;

/// Action text size: 14dp (Bulletin.java:2259).
const double kBulletinActionTextSize = 14.0;

/// Enter/exit spring damping ratio: 0.8 (`SpringTransition.DAMPING_RATIO`,
/// Bulletin.java:1123).
const double kBulletinSpringDampingRatio = 0.8;

/// Enter/exit spring stiffness: 400 (`SpringTransition.STIFFNESS`,
/// Bulletin.java:1124).
const double kBulletinSpringStiffness = 400.0;

/// Swipe-dismiss threshold as a fraction of the banner width: 1/3
/// (`Math.abs(translationX) > layout.getWidth() / 3f`, Bulletin.java:645).
const double kBulletinSwipeThresholdFraction = 1 / 3;

/// Swipe settle duration (both dismiss and return): 200ms
/// (Bulletin.java:648, 655).
const Duration kBulletinSwipeSettleDuration = Duration(milliseconds: 200);

/// Default undo countdown: `timeLeft = 5000` ms (UndoView.java:482).
const Duration kBulletinUndoDuration = Duration(milliseconds: 5000);

/// Countdown ring diameter: 18dp (`rect` spans dp(15)..dp(15 + 18),
/// UndoView.java:319).
const double kBulletinCountdownSize = 18.0;

/// Countdown ring stroke width: 2dp (UndoView.java:323).
const double kBulletinCountdownStroke = 2.0;

/// Countdown seconds text size: 12dp (UndoView.java:328).
const double kBulletinCountdownTextSize = 12.0;

/// The arc-sweep divisor: the Java draws `-360 * (timeLeft / 5000.0f)` with
/// a literal 5000 regardless of the starting timeLeft (UndoView.java:1694),
/// so the ring only depletes over the final 5 seconds.
const int kBulletinCountdownSweepDivisorMs = 5000;

/// Digit-change cross-fade: 150ms (`timeReplaceProgress += 16f / 150f` per
/// 16ms frame, UndoView.java:1660).
const Duration kBulletinCountdownDigitSwapDuration =
    Duration(milliseconds: 150);

/// Digit-change vertical travel: 10dp (UndoView.java:1673, 1684).
const double kBulletinCountdownDigitSlide = 10.0;

/// The enter/exit spring: dampingRatio 0.8, stiffness 400, mass 1
/// (Bulletin.java:1121-1172; DynamicAnimation's implicit unit mass) —
/// damping coefficient `2 * 0.8 * sqrt(400 * 1) = 32`.
final SpringDescription kBulletinSpring = SpringDescription.withDampingRatio(
  mass: 1.0,
  stiffness: kBulletinSpringStiffness,
  ratio: kBulletinSpringDampingRatio,
);

/// Android `AccelerateInterpolator` (factor 1): `f(t) = t * t` — the swipe
/// dismiss settle curve (`AndroidUtilities.accelerateInterpolator`,
/// Bulletin.java:648).
class BulletinAccelerateCurve extends Curve {
  /// Creates the curve.
  const BulletinAccelerateCurve();

  @override
  double transformInternal(double t) => t * t;
}

/// Android `AccelerateDecelerateInterpolator`:
/// `f(t) = cos((t + 1) * pi) / 2 + 0.5` — the ViewPropertyAnimator default
/// used by the below-threshold settle-back (Bulletin.java:655).
class BulletinAccelerateDecelerateCurve extends Curve {
  /// Creates the curve.
  const BulletinAccelerateDecelerateCurve();

  @override
  double transformInternal(double t) => math.cos((t + 1) * math.pi) / 2 + 0.5;
}

/// The transient bottom banner — `ui/Components/Bulletin.java`.
///
/// [show] inserts an [OverlayEntry] pinned to the overlay's bottom edge,
/// above the ambient bottom insets. At most one bulletin is visible:
/// showing a new one hides the current one (Bulletin.java:285-288).
abstract final class Bulletin {
  /// Key on the banner surface (background + content) for tests/tooling.
  static const Key bannerKey = ValueKey<String>('Bulletin.banner');

  /// Key on the 56x48 leading frame.
  static const Key leadingKey = ValueKey<String>('Bulletin.leading');

  /// Key on the trailing action button.
  static const Key actionKey = ValueKey<String>('Bulletin.action');

  /// Key on the undo variant's leading countdown circle.
  static const Key countdownKey = ValueKey<String>('Bulletin.countdown');

  static BulletinController? _visible;

  /// The currently visible bulletin, if any
  /// (`getVisibleBulletin`, Bulletin.java:210-212).
  static BulletinController? get visible => _visible;

  /// Hides the visible bulletin, if any (Bulletin.java:214-218).
  static void hideVisible() => _visible?.hide();

  /// Shows a bulletin in the root [Overlay] of [context] and returns its
  /// controller.
  ///
  /// - [text]: the single-line 15dp `undo_infoColor` message
  ///   (Bulletin.java:1999-2008).
  /// - [leading]: optional widget centered in the 56x48 lottie frame
  ///   (Bulletin.java:1983-1985) — the RLottieImageView contract slot; pass
  ///   a lottie adapter or a static icon.
  /// - [actionText]/[onAction]: the trailing `UndoButton`; tapping runs
  ///   [onAction] then hides (Bulletin.java:2279-2292).
  /// - [duration]: auto-hide delay counted from the end of the enter
  ///   transition (Bulletin.java:393-403); null never auto-hides (the Java
  ///   `duration < 0` convention).
  /// - [bottomOffset]: extra lift above the bottom inset — the Java
  ///   `Delegate.getBottomOffset` (e.g. main tabs: navBar + 56 + 8dp,
  ///   MainTabsActivity.java:192).
  /// - [margin]: outer margin; zero by default (the base layout is
  ///   MATCH_PARENT, Bulletin.java:866).
  /// - [useGlass]: renders the background as a [GlassPanel] with
  ///   [GlassPresets.bulletin] instead of the solid `undo_background`.
  static BulletinController show(
    BuildContext context, {
    required String text,
    Widget? leading,
    String? actionText,
    VoidCallback? onAction,
    Duration? duration = kBulletinDurationDefault,
    double bottomOffset = 0.0,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
    bool useGlass = false,
    TelegramResources? resources,
  }) {
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    // Showing a new bulletin hides the current one (Bulletin.java:285-288).
    _visible?.hide();
    final BulletinController controller = BulletinController._();
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) {
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BulletinHost(
            controller: controller,
            text: text,
            leading: leading,
            actionText: actionText,
            onAction: onAction,
            duration: duration,
            bottomOffset: bottomOffset,
            margin: margin,
            useGlass: useGlass,
            resources: resources,
          ),
        );
      },
    );
    controller._entry = entry;
    _visible = controller;
    overlay.insert(entry);
    return controller;
  }

  /// Shows the undo variant — the `ui/Components/UndoView.java` countdown
  /// recipe as a Bulletin layout: a leading [BulletinCountdown] (seconds
  /// text inside a depleting 2dp ring) plus a trailing undo action.
  ///
  /// - [countdown]: the `timeLeft` budget, default 5000ms
  ///   (UndoView.java:482). The countdown starts immediately and ticks
  ///   through the enter transition (UndoView.java:485); when it empties the
  ///   bulletin hides itself (`timeLeft <= 0 -> hide(true, ...)`,
  ///   UndoView.java:1697-1703).
  /// - [undoText]/[onUndo]: the trailing button — 14dp Roboto Medium
  ///   `undo_cancelColor` (UndoView.java:312-316). Tapping runs [onUndo] and
  ///   hides without committing (`hide(false, 1)` runs the cancel runnable,
  ///   UndoView.java:300-305, 397-403). The label is a parameter because the
  ///   package carries no localization (Java: `R.string.UndoNoCaps`).
  /// - [onCommit]: the deferred action, run once the bulletin has fully left
  ///   for any reason other than undo — countdown expiry, swipe-dismiss,
  ///   replacement by another bulletin, or a programmatic [hideVisible] /
  ///   [BulletinController.hide] (`apply == true` runs the action runnable,
  ///   UndoView.java:391-396).
  ///
  /// Remaining parameters match [show].
  static BulletinController showUndo(
    BuildContext context, {
    required String text,
    required String undoText,
    VoidCallback? onUndo,
    VoidCallback? onCommit,
    Duration countdown = kBulletinUndoDuration,
    double bottomOffset = 0.0,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
    bool useGlass = false,
    TelegramResources? resources,
  }) {
    BulletinController? controller;
    bool undone = false;
    controller = show(
      context,
      text: text,
      leading: BulletinCountdown(
        key: countdownKey,
        duration: countdown,
        resources: resources,
        // `timeLeft <= 0 -> hide(true, hideAnimationType)`
        // (UndoView.java:1700-1703).
        onExpired: () => controller!.hide(),
      ),
      actionText: undoText,
      onAction: () {
        // `hide(false, 1)` — apply=false runs the cancel runnable and skips
        // the action runnable (UndoView.java:300-305, 391-403); the base
        // trailing action already hides afterwards.
        undone = true;
        onUndo?.call();
      },
      // The countdown drives dismissal, not the standard auto-hide timer.
      duration: null,
      bottomOffset: bottomOffset,
      margin: margin,
      useGlass: useGlass,
      resources: resources,
    );
    if (onCommit != null) {
      // Any dismissal that is not the undo press commits the deferred
      // action (`apply == true`, UndoView.java:391-396).
      controller.closed.then((_) {
        if (!undone) {
          onCommit();
        }
      });
    }
    return controller;
  }
}

/// Handle to a shown bulletin: [hide] it or await [closed].
class BulletinController {
  BulletinController._();

  OverlayEntry? _entry;
  _BulletinHostState? _state;
  final Completer<void> _closed = Completer<void>();

  /// Completes when the bulletin has fully left the overlay.
  Future<void> get closed => _closed.future;

  /// Whether the bulletin is still in the overlay (possibly animating out).
  bool get isShowing => !_closed.isCompleted;

  /// Hides the bulletin: [animated] runs the exit spring
  /// (Bulletin.java:1152-1171), otherwise the entry is removed immediately.
  void hide({bool animated = true}) {
    final _BulletinHostState? state = _state;
    if (state != null) {
      state._hide(animated: animated);
    } else {
      _finish();
    }
  }

  /// Removes the overlay entry and completes [closed].
  void _finish() {
    if (identical(Bulletin._visible, this)) {
      Bulletin._visible = null;
    }
    final OverlayEntry? entry = _entry;
    _entry = null;
    if (entry != null) {
      // remove() unconditionally: `entry.mounted` stays false until the
      // overlay rebuilds, so a hide in the same frame as show (a second
      // Bulletin.show in one event handler, or an immediate hide()) would
      // skip a mounted-guarded remove and leave the entry inserted —
      // dispose() then asserts, and the overlay would later mount a
      // disposed entry. This is the only place that removes the entry, so
      // its `_overlay` is always still set here; remove() itself no-ops on
      // an unmounted overlay state.
      entry.remove();
      entry.dispose();
    }
    if (!_closed.isCompleted) {
      _closed.complete();
    }
  }

  /// Host teardown without a normal hide (the overlay itself being torn
  /// down): release the entry and complete [closed]. The entry must still be
  /// removed + disposed here — nothing else ever will, and an undisposed
  /// entry leaks its internal notifier (the pattern mirrors the framework's
  /// own `_WrappingOverlayState.dispose`; remove() no-ops on the unmounted
  /// overlay state).
  void _detached() {
    if (identical(Bulletin._visible, this)) {
      Bulletin._visible = null;
    }
    final OverlayEntry? entry = _entry;
    _entry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
    if (!_closed.isCompleted) {
      _closed.complete();
    }
  }
}

class _BulletinHost extends StatefulWidget {
  const _BulletinHost({
    required this.controller,
    required this.text,
    required this.leading,
    required this.actionText,
    required this.onAction,
    required this.duration,
    required this.bottomOffset,
    required this.margin,
    required this.useGlass,
    required this.resources,
  });

  final BulletinController controller;
  final String text;
  final Widget? leading;
  final String? actionText;
  final VoidCallback? onAction;
  final Duration? duration;
  final double bottomOffset;
  final EdgeInsetsGeometry margin;
  final bool useGlass;
  final TelegramResources? resources;

  @override
  State<_BulletinHost> createState() => _BulletinHostState();
}

class _BulletinHostState extends State<_BulletinHost>
    with TickerProviderStateMixin {
  /// Vertical in/out offset as a fraction of the translated block height:
  /// 1 = fully below the overlay's bottom edge (the Java
  /// `inOutOffset = measuredHeight` start, Bulletin.java:1128), 0 = rest.
  late final AnimationController _inOut =
      AnimationController.unbounded(value: 1.0, vsync: this);

  /// Horizontal swipe translation in logical px (the Java translationX).
  late final AnimationController _drag =
      AnimationController.unbounded(value: 0.0, vsync: this);

  Timer? _hideTimer;
  bool _canHide = false;
  bool _hiding = false;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    // Enter spring: offset height -> 0, damping 0.8 / stiffness 400
    // (Bulletin.java:1127-1150). The fraction-space simulation follows the
    // identical trajectory (linear spring, amplitude-normalized).
    _inOut
        .animateWith(SpringSimulation(kBulletinSpring, 1.0, 0.0, 0.0))
        .whenComplete(_onEntered);
  }

  void _onEntered() {
    // The Java end listener snaps the offset home (`setInOutOffset(0)`,
    // Bulletin.java:1136) — the spring stops within tolerance of 0, not
    // exactly at it.
    _inOut.value = 0.0;
    // `setCanHide(true)` after the enter transition (Bulletin.java:377,
    // 393-403).
    _canHide = true;
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    final Duration? duration = widget.duration;
    if (!_canHide || _hiding || duration == null) {
      return;
    }
    // `layout.postDelayed(hideRunnable, duration)` (Bulletin.java:398).
    _hideTimer = Timer(duration, () => _hide(animated: true));
  }

  void _pauseHideTimer() {
    // `setCanHide(!pressed)` removes the callback (Bulletin.java:402,
    // 245-260 onPressedStateChanged wiring).
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _hide({bool animated = true}) {
    if (_hiding) {
      return;
    }
    _hiding = true;
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!animated || !mounted) {
      widget.controller._finish();
      return;
    }
    // Exit spring: offset current -> height (Bulletin.java:1152-1171).
    _inOut
        .animateWith(SpringSimulation(kBulletinSpring, _inOut.value, 1.0, 0.0))
        .whenComplete(widget.controller._finish);
  }

  void _onDragStart(DragStartDetails details) {
    _drag.stop();
    _pauseHideTimer();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _drag.value += details.delta.dx;
  }

  void _onDragEnd(DragEndDetails details) {
    if (_hiding) {
      return;
    }
    final double width = context.size?.width ?? 0.0;
    final double translationX = _drag.value;
    if (width > 0 &&
        translationX.abs() > width * kBulletinSwipeThresholdFraction) {
      // Beyond width/3: settle to +-width over 200ms accelerate, then hide
      // (Bulletin.java:645-653). The layout is already offscreen
      // horizontally, so the port removes the entry without the redundant
      // vertical exit spring.
      _drag
          .animateTo(
            translationX.sign * width,
            duration: kBulletinSwipeSettleDuration,
            curve: const BulletinAccelerateCurve(),
          )
          .whenComplete(() => _hide(animated: false));
    } else {
      // Below threshold: settle back over 200ms (Bulletin.java:655).
      _drag.animateTo(
        0.0,
        duration: kBulletinSwipeSettleDuration,
        curve: const BulletinAccelerateDecelerateCurve(),
      );
      _startHideTimer();
    }
  }

  void _onDragCancel() {
    if (_hiding) {
      return;
    }
    _drag.animateTo(
      0.0,
      duration: kBulletinSwipeSettleDuration,
      curve: const BulletinAccelerateDecelerateCurve(),
    );
    _startHideTimer();
  }

  void _onAction() {
    // `UndoButton.undo()`: run the action, then hide
    // (Bulletin.java:2279-2292).
    widget.onAction?.call();
    _hide(animated: true);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (identical(widget.controller._state, this)) {
      widget.controller._state = null;
    }
    widget.controller._detached();
    _inOut.dispose();
    _drag.dispose();
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
    final Widget? leading = widget.leading;
    final String? actionText = widget.actionText;

    Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (leading != null)
          SizedBox(
            key: Bulletin.leadingKey,
            width: kBulletinLeadingWidth,
            height: kBulletinLeadingHeight,
            // ScaleType.CENTER (Bulletin.java:1984).
            child: Center(child: leading),
          ),
        Expanded(
          child: Padding(
            // Text margin end 16 within the padded frame; the start margin
            // (56, Bulletin.java:2005) is realized by the leading frame's
            // width. Own 8dp vertical text padding (Bulletin.java:2003).
            padding: const EdgeInsetsDirectional.only(
              end: kBulletinTextEndMargin,
              top: kBulletinVerticalPadding,
              bottom: kBulletinVerticalPadding,
            ),
            child: Text(
              widget.text,
              maxLines: 1,
              // TruncateAt.END (Bulletin.java:2000-2001).
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: kBulletinTextSize,
                color: _color(context, TelegramColorKey.undo_infoColor),
              ),
            ),
          ),
        ),
        if (actionText != null)
          Padding(
            // 8dp button side margins (Bulletin.java:2265).
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 8.0),
            child: Semantics(
              button: true,
              child: GestureDetector(
                key: Bulletin.actionKey,
                onTap: _onAction,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  // (12, 8, 12, 8) text padding (Bulletin.java:2264).
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
                  child: Text(
                    actionText,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: kBulletinActionTextSize,
                      // `AndroidUtilities.bold()` = fonts/rmedium.ttf,
                      // bundled as w500 `RobotoMedium`
                      // (Bulletin.java:2260).
                      fontFamily: 'RobotoMedium',
                      package: 'telegram_ui',
                      fontWeight: FontWeight.w500,
                      color: _color(context, TelegramColorKey.undo_cancelColor),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    // Min height 48dp outside the 16/8dp padding (both set on the Layout
    // view itself, Bulletin.java:797-800).
    row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kBulletinMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kBulletinHorizontalPadding,
          vertical: kBulletinVerticalPadding,
        ),
        child: row,
      ),
    );

    Widget banner;
    if (widget.useGlass) {
      banner = GlassPanel(
        preset: GlassPresets.bulletin,
        borderRadius: const GlassRadii.all(kBulletinRadius),
        resources: widget.resources,
        child: row,
      );
    } else {
      // `Theme.createRoundRectDrawable(dp(16), undo_background)`
      // (Bulletin.java:798, 810-816).
      banner = DecoratedBox(
        decoration: BoxDecoration(
          color: _color(context, TelegramColorKey.undo_background),
          borderRadius: BorderRadius.circular(kBulletinRadius),
        ),
        child: row,
      );
    }

    banner = Listener(
      // Press pauses auto-hide; release re-posts the full delay
      // (`setCanHide(!pressed)`, Bulletin.java:245-260, 393-403).
      onPointerDown: (_) => _pauseHideTimer(),
      onPointerUp: (_) => _startHideTimer(),
      onPointerCancel: (_) => _startHideTimer(),
      child: GestureDetector(
        key: Bulletin.bannerKey,
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _onDragCancel,
        child: banner,
      ),
    );

    // Stack above the ambient bottom insets (nav bar or keyboard) plus the
    // host-provided delegate offset (Bulletin.java:352-366, updatePosition).
    final double bottomInset = math.max(
      MediaQuery.paddingOf(context).bottom,
      MediaQuery.viewInsetsOf(context).bottom,
    );

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_inOut, _drag]),
      builder: (BuildContext context, Widget? child) {
        // Enter/exit translate the whole padded block by its own height
        // fraction, so offset 1 is fully below the overlay's bottom edge.
        return FractionalTranslation(
          translation: Offset(0, _inOut.value),
          child: Transform.translate(
            offset: Offset(_drag.value, 0),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: widget.margin
            .add(EdgeInsets.only(bottom: bottomInset + widget.bottomOffset)),
        child: banner,
      ),
    );
  }
}

/// The undo countdown circle: seconds text inside a depleting 18dp / 2dp
/// ring, `undo_infoColor` (UndoView.java:319-330, 1644-1694).
///
/// Self-contained: its clock starts on mount (the Java
/// `lastUpdateTime = SystemClock.elapsedRealtime()` at show,
/// UndoView.java:485) and runs [onExpired] once when [duration] has fully
/// elapsed (`timeLeft <= 0`, UndoView.java:1700-1703). [Bulletin.showUndo]
/// mounts one in the standard 56x48 leading frame and wires [onExpired] to
/// hide the bulletin.
class BulletinCountdown extends StatefulWidget {
  /// Creates the countdown circle.
  const BulletinCountdown({
    super.key,
    this.duration = kBulletinUndoDuration,
    this.onExpired,
    this.resources,
  });

  /// Total countdown budget — the Java `timeLeft` (default 5000ms,
  /// UndoView.java:482).
  final Duration duration;

  /// Runs once when the countdown empties (UndoView.java:1700-1703).
  final VoidCallback? onExpired;

  /// Explicit resources override; otherwise keys resolve through
  /// [TelegramTheme.colorOf].
  final TelegramResources? resources;

  @override
  State<BulletinCountdown> createState() => _BulletinCountdownState();
}

class _BulletinCountdownState extends State<BulletinCountdown>
    with TickerProviderStateMixin {
  /// Remaining fraction of [BulletinCountdown.duration], 1 -> 0 linear (the
  /// Java `timeLeft -= dt` wall-clock decrement, UndoView.java:1697-1699).
  late final AnimationController _remaining = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1.0,
  );

  /// Digit-change cross-fade, 0 -> 1 over 150ms (`timeReplaceProgress`,
  /// UndoView.java:1659-1665); rests at 1 (no swap in flight).
  late final AnimationController _swap = AnimationController(
    vsync: this,
    duration: kBulletinCountdownDigitSwapDuration,
    value: 1.0,
  );

  late int _seconds =
      _secondsOfMs(widget.duration.inMilliseconds.toDouble());
  int? _outSeconds;

  /// `newSeconds = timeLeft > 0 ? ceil(timeLeft / 1000) : 0`, displayed as
  /// `max(1, newSeconds)` (UndoView.java:1645-1649) — the digit never drops
  /// below 1.
  static int _secondsOfMs(double ms) {
    final int raw = ms > 0 ? (ms / 1000.0).ceil() : 0;
    return math.max(1, raw);
  }

  @override
  void initState() {
    super.initState();
    // Registered before the AnimatedBuilder subscribes, so the digit state
    // is current when the frame repaints.
    _remaining.addListener(_onTick);
    // The countdown starts at show and ticks through the enter transition
    // (UndoView.java:485). The TickerFuture resolves only on natural
    // completion — a dispose mid-flight never fires onExpired.
    _remaining.reverse(from: 1.0).whenComplete(_onExpired);
  }

  void _onTick() {
    final int seconds = _secondsOfMs(
        _remaining.value * widget.duration.inMilliseconds);
    if (seconds != _seconds) {
      // Digit changed: cross-fade old -> new (UndoView.java:1647-1656).
      _outSeconds = _seconds;
      _seconds = seconds;
      _swap.forward(from: 0.0);
    }
  }

  void _onExpired() {
    if (mounted) {
      widget.onExpired?.call();
    }
  }

  @override
  void dispose() {
    _remaining.dispose();
    _swap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ring and digits both use `undo_infoColor` (UndoView.java:325, 330).
    final TelegramResources? resources = widget.resources;
    final Color color = resources != null
        ? resources.getColor(TelegramColorKey.undo_infoColor)
        : TelegramTheme.colorOf(context, TelegramColorKey.undo_infoColor);
    final TextDirection textDirection = Directionality.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_remaining, _swap]),
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          size: const Size.square(kBulletinCountdownSize),
          painter: BulletinCountdownPainter(
            ringFraction: math.min(
              1.0,
              _remaining.value *
                  widget.duration.inMilliseconds /
                  kBulletinCountdownSweepDivisorMs,
            ),
            seconds: _seconds,
            outSeconds: _outSeconds,
            swapProgress: _swap.value,
            color: color,
            textDirection: textDirection,
          ),
        );
      },
    );
  }
}

/// Paints one frame of the undo countdown (UndoView.java:1644-1694): the
/// current [seconds] digit (plus the outgoing digit mid-swap) and the
/// depleting ring.
class BulletinCountdownPainter extends CustomPainter {
  /// Creates the painter for one frame.
  BulletinCountdownPainter({
    required this.ringFraction,
    required this.seconds,
    required this.outSeconds,
    required this.swapProgress,
    required this.color,
    required this.textDirection,
  });

  /// Remaining sweep of the ring, 0..1 — the Java `timeLeft / 5000f`
  /// clamped to a full circle (UndoView.java:1694).
  final double ringFraction;

  /// The displayed digit, `max(1, ceil(timeLeft / 1000))`
  /// (UndoView.java:1645-1649).
  final int seconds;

  /// The previous digit while a swap is in flight (`timeLayoutOut`,
  /// UndoView.java:1651-1652); ignored once [swapProgress] reaches 1.
  final int? outSeconds;

  /// Digit cross-fade progress 0..1 (`timeReplaceProgress`,
  /// UndoView.java:1659-1690).
  final double swapProgress;

  /// `undo_infoColor` for both ring and digits (UndoView.java:325, 330).
  final Color color;

  /// Ambient directionality for the digit text layout.
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    // Outgoing digit: slides 10dp down, fading out
    // (UndoView.java:1670-1677).
    final int? outSeconds = this.outSeconds;
    if (outSeconds != null && swapProgress < 1.0) {
      _paintDigit(
        canvas,
        size,
        outSeconds,
        opacity: 1.0 - swapProgress,
        dy: kBulletinCountdownDigitSlide * swapProgress,
      );
    }
    // Current digit: slides in from 10dp above, fading in
    // (UndoView.java:1679-1690).
    _paintDigit(
      canvas,
      size,
      seconds,
      opacity: math.min(1.0, swapProgress),
      dy: -kBulletinCountdownDigitSlide * (1.0 - swapProgress),
    );
    // 2dp round-cap stroke from 12 o'clock, sweeping counter-clockwise by
    // the remaining fraction (UndoView.java:321-324, 1694). Like the Java
    // (stroke centered on the 18dp rect), the stroke overhangs the bounds
    // by 1dp — the leading frame does not clip.
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kBulletinCountdownStroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Offset.zero & size,
      -math.pi / 2,
      -2.0 * math.pi * ringFraction,
      false,
      ring,
    );
  }

  void _paintDigit(
    Canvas canvas,
    Size size,
    int value, {
    required double opacity,
    required double dy,
  }) {
    // 12dp Roboto Medium (`textPaint`, UndoView.java:327-329) — the
    // microEmphasis role of the scale.
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: '$value',
        style: TgTextStyles.microEmphasis.copyWith(
          color: color.withValues(alpha: color.a * opacity),
        ),
      ),
      textDirection: textDirection,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2.0,
        (size.height - painter.height) / 2.0 + dy,
      ),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(BulletinCountdownPainter oldDelegate) {
    return ringFraction != oldDelegate.ringFraction ||
        seconds != oldDelegate.seconds ||
        outSeconds != oldDelegate.outSeconds ||
        swapProgress != oldDelegate.swapProgress ||
        color != oldDelegate.color ||
        textDirection != oldDelegate.textDirection;
  }
}
