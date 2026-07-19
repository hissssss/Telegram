// Port of `ui/Components/FragmentFloatingButton.java` (FFB) — the modern
// floating action button (DialogsActivity/ContactsActivity/LoginActivity et
// al.) — with its press feedback from
// `ui/Components/ScaleStateListAnimator.java` (SSLA). PLAN_UIKIT.md S5.
//
// Faithful recipe:
// - circular fill `featuredStickers_addButton` with
//   `featuredStickers_addButtonPressed` pressed state
//   (`Theme.createSimpleSelectorCircleDrawable(dp(48), …)`, FFB:166-169);
//   icon tinted `chats_actionIcon` SRC_IN (FFB:164);
// - sizes: 56dp (`createDefaultLayoutParamsBig`, FFB:188-192 — LoginActivity
//   recipe, the PLAN S5 default) and 48dp compact (`SIZE = 48`, FFB:173;
//   `createDefaultLayoutParams`, FFB:181-185 — the chat-list FAB);
// - press scale `ScaleStateListAnimator.apply(this)` (FFB:71): pressed
//   1 − 0.1 over 80ms, release 350ms `OvershootInterpolator(1.5)`
//   (SSLA:11-33);
// - show/hide via `BoolAnimator(EASE_OUT_QUINT, 380)` (FFB:38-39): alpha =
//   factor, scale = lerp(0.4, 1, factor) (`setAnimatedVisibility`,
//   FFB:250-259), extra translationY `dp(40)·(1 − factor)` (FFB:126), and
//   the view is clickable only at factor ≥ 0.99 (FFB:125).
//
// Deliberately NOT ported:
// - the `RadialProgressView` icon↔progress crossfade (FFB:41-42, 65-69,
//   127-135) — it depends on the `TgRadialProgress` port (PLAN M9, built in
//   parallel); a follow-up can add a progress slot without API breakage;
// - the blur3 glass sub-button variant (`isSubButton`, FFB:77-100, 150-162)
//   and `createSubButtonLayoutParams` (FFB:175-179);
// - `addAdditionalView` content stacking (FFB:242-248), the RLottie
//   `setAnimation` plumbing (FFB:138-144), and the 0.5dp `translationZ` +
//   oval outline elevation shadow (FFB:72-75) — Android render details;
// - Android `GONE` at factor 0 (FFB:258): the port keeps its layout slot
//   (FABs live in a Stack/Positioned overlay, so nothing shifts) but stops
//   hit-testing and reports disabled semantics.
//
// The classic pre-FragmentFloatingButton FAB used the
// `chats_actionBackground` / `chats_actionPressedBackground` keys; pass them
// as [TgFab.backgroundColorKey] / [TgFab.pressedColorKey] to reproduce that
// look — the modern defaults below follow FFB:166-169.
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../foundation/tg_curves.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Default button diameter: 56dp (`createDefaultLayoutParamsBig`,
/// FragmentFloatingButton.java:188-192; PLAN_UIKIT.md S5).
const double kTgFabSize = 56.0;

/// Compact diameter: 48dp (`SIZE = 48`, FragmentFloatingButton.java:173;
/// `createDefaultLayoutParams`, :181-185 — the chat-list FAB).
const double kTgFabSizeCompact = 48.0;

/// Show/hide duration: 380ms EASE_OUT_QUINT
/// (`new BoolAnimator(…, CubicBezierInterpolator.EASE_OUT_QUINT, 380, …)`,
/// FragmentFloatingButton.java:38-39).
const Duration kTgFabVisibilityDuration = Duration(milliseconds: 380);

/// Hide slide distance: 40dp (`dp(isSubButton ? 64 : 40) * (1f - factor)`,
/// FragmentFloatingButton.java:126 — the main-button branch).
const double kTgFabHideSlide = 40.0;

/// Hidden scale: 0.4 (`lerp(0.4f, 1f, f)`,
/// FragmentFloatingButton.java:256-257).
const double kTgFabHiddenScale = 0.4;

/// Clickability threshold: the button accepts taps only at visibility
/// factor ≥ 0.99 (`setClickable(factor >= 0.99f)`,
/// FragmentFloatingButton.java:125).
const double kTgFabClickableThreshold = 0.99;

/// Pressed scale delta: `ScaleStateListAnimator.apply(this)` defaults
/// (`apply(view, .1f, 1.5f)`, ScaleStateListAnimator.java:11-12) — pressed
/// scale is `1 − 0.1`.
const double kTgFabPressScale = 0.1;

/// Release overshoot tension: 1.5 (ScaleStateListAnimator.java:12, 32).
const double kTgFabReleaseTension = 1.5;

/// Press-in duration: 80ms (`pressedAnimator.setDuration(80)`,
/// ScaleStateListAnimator.java:25).
const Duration kTgFabPressDuration = Duration(milliseconds: 80);

/// Release duration: 350ms (`defaultAnimator.setDuration(350)`,
/// ScaleStateListAnimator.java:33).
const Duration kTgFabReleaseDuration = Duration(milliseconds: 350);

/// Android's `AccelerateDecelerateInterpolator` —
/// `cos((t + 1)·π)/2 + 0.5` — the `ValueAnimator` default driving the
/// press-in (ScaleStateListAnimator.java:20-25). File-local like
/// `glass_icon_button.dart`'s copy; not a `TgCurves` member because
/// foundation files are owned by the A0 build wave.
class _AccelerateDecelerateCurve extends Curve {
  const _AccelerateDecelerateCurve();

  @override
  double transformInternal(double t) => math.cos((t + 1) * math.pi) / 2.0 + 0.5;
}

const Curve _accelerateDecelerate = _AccelerateDecelerateCurve();

/// Release curve: `OvershootInterpolator(1.5)`
/// (ScaleStateListAnimator.java:12, 32).
const Curve _releaseCurve = TgOvershootInterpolator(tension: kTgFabReleaseTension);

/// The Telegram floating action button — the `FragmentFloatingButton` port:
/// a [size]-diameter circle filled `featuredStickers_addButton` (pressed
/// `featuredStickers_addButtonPressed`) with a centered [icon] tinted
/// `chats_actionIcon`, the `ScaleStateListAnimator` press scale, and the
/// 380ms EASE_OUT_QUINT show/hide (alpha + 0.4 scale + 40dp slide-down).
///
/// A controlled widget: toggle [visible] across rebuilds to play the
/// show/hide animation; while hidden the button ignores taps and reports
/// disabled semantics (Java sets the view GONE and unclickable below factor
/// 0.99, FragmentFloatingButton.java:125, 258).
///
/// Like every component in this package, the button takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise keys resolve through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class TgFab extends StatefulWidget {
  /// Creates the button.
  const TgFab({
    super.key,
    required this.icon,
    this.onPressed,
    this.visible = true,
    this.size = kTgFabSize,
    this.backgroundColorKey = TelegramColorKey.featuredStickers_addButton,
    this.pressedColorKey = TelegramColorKey.featuredStickers_addButtonPressed,
    this.iconColorKey = TelegramColorKey.chats_actionIcon,
    this.tooltip,
    this.resources,
  }) : assert(size > 0);

  /// The centered icon (`ScaleType.CENTER`, FragmentFloatingButton.java:62).
  /// Rendered under an [IconTheme] carrying the resolved [iconColorKey]
  /// color (the `PorterDuff.Mode.SRC_IN` tint, FragmentFloatingButton.java:164).
  final Widget icon;

  /// Tap callback; null disables the button (inert, disabled semantics).
  final VoidCallback? onPressed;

  /// Whether the button is shown (`setButtonVisible`,
  /// FragmentFloatingButton.java:109-111); changes animate 380ms
  /// EASE_OUT_QUINT.
  final bool visible;

  /// Circle diameter, default [kTgFabSize] (56dp); pass [kTgFabSizeCompact]
  /// (48dp) for the chat-list layout (FragmentFloatingButton.java:173-192).
  final double size;

  /// Circle fill key, default `featuredStickers_addButton`
  /// (FragmentFloatingButton.java:167).
  final int backgroundColorKey;

  /// Pressed fill key, default `featuredStickers_addButtonPressed`
  /// (FragmentFloatingButton.java:168).
  final int pressedColorKey;

  /// Icon tint key, default `chats_actionIcon`
  /// (FragmentFloatingButton.java:164).
  final int iconColorKey;

  /// Accessibility description, exposed as the semantics tooltip.
  final String? tooltip;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  @override
  State<TgFab> createState() => TgFabState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ObjectFlagProperty<VoidCallback>.has('onPressed', onPressed))
      ..add(FlagProperty('visible', value: visible, ifFalse: 'hidden'))
      ..add(DoubleProperty('size', size, defaultValue: kTgFabSize))
      ..add(StringProperty('tooltip', tooltip, defaultValue: null));
  }
}

/// State of [TgFab]; public for test access to the debug getters.
class TgFabState extends State<TgFab> with TickerProviderStateMixin {
  /// Pressed factor: 0 resting, 1 fully pressed. Unbounded — the overshoot
  /// release dips below 0 (scale above 1.0), like Android's
  /// `OvershootInterpolator`.
  late final AnimationController _pressed = AnimationController.unbounded(vsync: this, value: 0.0);

  /// Visibility factor — the `animatorButtonVisible` BoolAnimator
  /// (FragmentFloatingButton.java:38-39), retargeted from the current value
  /// over the full 380ms like `BoolAnimator.setValue`.
  late final AnimationController _visibility =
      AnimationController(vsync: this, value: widget.visible ? 1.0 : 0.0);

  /// The current press scale multiplier: `lerp(1, 0.9, pressedFactor)`
  /// (ScaleStateListAnimator.java:11-12).
  @visibleForTesting
  double get debugPressScale => 1.0 - kTgFabPressScale * _pressed.value;

  /// The current visibility factor (`animatorButtonVisible.getFloatValue()`).
  @visibleForTesting
  double get debugVisibilityFactor => _visibility.value;

  bool get _clickable =>
      widget.onPressed != null && _visibility.value >= kTgFabClickableThreshold;

  @override
  void didUpdateWidget(TgFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      _visibility.animateTo(
        widget.visible ? 1.0 : 0.0,
        duration: kTgFabVisibilityDuration,
        curve: TgCurves.easeOutQuint,
      );
    }
  }

  @override
  void dispose() {
    _pressed.dispose();
    _visibility.dispose();
    super.dispose();
  }

  /// `state_pressed` enter: scale toward 0.9 over 80ms with the Android
  /// default accelerate-decelerate (ScaleStateListAnimator.java:20-25).
  void _handleTapDown(TapDownDetails details) {
    if (!_clickable) {
      return;
    }
    _pressed.animateTo(1.0, duration: kTgFabPressDuration, curve: _accelerateDecelerate);
  }

  /// `state_pressed` exit: back to 1.0 over 350ms with
  /// `OvershootInterpolator(1.5)` (ScaleStateListAnimator.java:27-33).
  void _handleRelease() {
    if (_pressed.value == 0.0 && !_pressed.isAnimating) {
      return;
    }
    _pressed.animateTo(0.0, duration: kTgFabReleaseDuration, curve: _releaseCurve);
  }

  void _handleTap() {
    if (!_clickable) {
      return;
    }
    widget.onPressed!();
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
    final Color background = _color(context, widget.backgroundColorKey);
    final Color pressedColor = _color(context, widget.pressedColorKey);
    final Color iconColor = _color(context, widget.iconColorKey);
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_pressed, _visibility]),
      builder: (BuildContext context, Widget? child) {
        final double factor = _visibility.value.clamp(0.0, 1.0);
        final double pressT = _pressed.value.clamp(0.0, 1.0);
        final bool clickable = _clickable;
        return Semantics(
          container: true,
          button: true,
          enabled: clickable,
          tooltip: widget.tooltip,
          // The tap action lives on the Semantics node (absent while
          // unclickable); the raw GestureDetector below is excluded so its
          // press-feedback handlers do not register an always-on tap action.
          onTap: clickable ? _handleTap : null,
          child: IgnorePointer(
            // setClickable(factor >= 0.99f) (FragmentFloatingButton.java:125).
            ignoring: !clickable,
            child: GestureDetector(
              excludeFromSemantics: true,
              behavior: HitTestBehavior.opaque,
              onTapDown: _handleTapDown,
              onTapUp: (TapUpDetails details) => _handleRelease(),
              onTapCancel: _handleRelease,
              onTap: clickable ? _handleTap : null,
              child: Opacity(
                // setAlpha(f) (FragmentFloatingButton.java:255).
                opacity: factor,
                child: Transform.translate(
                  // dp(40) * (1 − factor) (FragmentFloatingButton.java:126).
                  offset: Offset(0.0, kTgFabHideSlide * (1.0 - factor)),
                  child: Transform.scale(
                    // lerp(0.4, 1, f) (FragmentFloatingButton.java:256-257)
                    // × the press scale. In Java both writes race for
                    // View.scaleX/Y; the port composes them.
                    scale: lerpDouble(kTgFabHiddenScale, 1.0, factor)! * debugPressScale,
                    child: SizedBox.square(
                      dimension: widget.size,
                      child: DecoratedBox(
                        // createSimpleSelectorCircleDrawable(dp(48),
                        // background, pressed)
                        // (FragmentFloatingButton.java:166-169): the pressed
                        // color blends in with the press factor — a simple
                        // highlight in place of the Android ripple, per the
                        // package convention.
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.lerp(background, pressedColor, pressT),
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: Center(
        child: IconTheme.merge(
          data: IconThemeData(color: iconColor),
          child: widget.icon,
        ),
      ),
    );
  }
}
