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
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

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
      if (entry.mounted) {
        entry.remove();
      }
      entry.dispose();
    }
    if (!_closed.isCompleted) {
      _closed.complete();
    }
  }

  /// Host teardown without a normal hide (overlay being disposed): mark
  /// closed but leave the entry to the framework.
  void _detached() {
    if (identical(Bulletin._visible, this)) {
      Bulletin._visible = null;
    }
    _entry = null;
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
