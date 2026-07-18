// The round glass icon button (ARCHITECTURE.md section 6, row
// "GlassIconButton": the `emojiViewButton` preset).
//
// Port of the glass-design buttons of
// `java/org/telegram/ui/Components/EmojiView.java` (backspace / search /
// sticker-settings and the type-tabs pill), the only production users of
// `BlurredBackgroundProviderImpl.emojiViewButton`:
//
//  * view frame **48x48dp** (`createFrame(48, 48, ...)`,
//    EmojiView.java:2679, 2776);
//  * glass background `factory.create(button)
//    .setColorProvider(BlurredBackgroundProviderImpl.emojiViewButton(...))
//    .setRadius(dp(18)).setPadding(dp(6))` (EmojiView.java:2923-2950) — the
//    visible glass circle is 48 − 2·6 = 36dp across, radius 18 = 36/2;
//  * icon tint `getGlassIconColor(0.6f)` =
//    `ColorUtils.setAlphaComponent(Theme.getColor(key_glass_defaultIcon,
//    resourcesProvider), (int) (255 * 0.6f))` (EmojiView.java:2651,
//    10135-10139), centered (`ScaleType.CENTER`, EmojiView.java:2652);
//  * press feedback `ScaleStateListAnimator.apply(button)`
//    (EmojiView.java:2661): pressed scales to 1 − 0.1 over **80ms** (Android
//    `ObjectAnimator` default accelerate-decelerate), released springs back
//    to 1 over **350ms** with `OvershootInterpolator(1.5)`
//    (ScaleStateListAnimator.java:11-34);
//  * accessibility label via `setContentDescription`
//    (EmojiView.java:2653) — the [GlassIconButton.tooltip] parameter.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../glass/geometry.dart';
import '../../glass/glass_panel.dart';
import '../../glass/liquid_glass_settings.dart';
import '../../glass/presets.dart';
import '../../glass/strategy.dart';
import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';

/// Button box size: `createFrame(48, 48, ...)` (EmojiView.java:2679, 2776).
const double kGlassIconButtonSize = 48.0;

/// Glass drawable padding: `setPadding(dp(6))` (EmojiView.java:2928) — the
/// inset of the glass visuals inside the 48dp box.
const double kGlassIconButtonGlassPadding = 6.0;

/// Glass corner radius: `setRadius(dp(18))` (EmojiView.java:2927) — half the
/// padded 36dp circle, i.e. `(size - 2 * padding) / 2` at the defaults.
const double kGlassIconButtonRadius = 18.0;

/// Icon tint alpha: `getGlassIconColor(0.6f)` (EmojiView.java:2651), applied
/// as `ColorUtils.setAlphaComponent(color, (int) (255 * alpha))`
/// (EmojiView.java:10135-10139) over `glass_defaultIcon`.
const double kGlassIconButtonIconAlpha = 0.6;

/// Pressed scale delta: `apply(view, .1f, 1.5f)`
/// (ScaleStateListAnimator.java:12) — pressed scale is `1 − 0.1`.
const double kGlassIconButtonPressScale = 0.1;

/// Overshoot tension of the release animation: `OvershootInterpolator(1.5f)`
/// (ScaleStateListAnimator.java:12, 32).
const double kGlassIconButtonReleaseTension = 1.5;

/// Press-in duration: `pressedAnimator.setDuration(80)`
/// (ScaleStateListAnimator.java:25).
const Duration kGlassIconButtonPressDuration = Duration(milliseconds: 80);

/// Release duration: `defaultAnimator.setDuration(350)`
/// (ScaleStateListAnimator.java:33).
const Duration kGlassIconButtonReleaseDuration = Duration(milliseconds: 350);

/// Android's `AccelerateDecelerateInterpolator` —
/// `cos((t + 1) * PI) / 2 + 0.5` — the `ValueAnimator` default interpolator
/// driving the press-in animation (no explicit interpolator is set on the
/// pressed animator, ScaleStateListAnimator.java:20-25).
class _AccelerateDecelerateCurve extends Curve {
  const _AccelerateDecelerateCurve();

  @override
  double transformInternal(double t) => math.cos((t + 1) * math.pi) / 2.0 + 0.5;
}

/// Android's `OvershootInterpolator(tension)`:
/// `f(t) = (t − 1)^2 * ((T + 1) * (t − 1) + T) + 1`, exceeding 1.0 near the
/// end — the release animation overshoots past the resting scale
/// (ScaleStateListAnimator.java:32).
class _OvershootCurve extends Curve {
  const _OvershootCurve(this.tension);

  final double tension;

  @override
  double transformInternal(double t) {
    final double x = t - 1.0;
    return x * x * ((tension + 1.0) * x + tension) + 1.0;
  }
}

/// A circular glass icon button — the `emojiViewButton` surface of
/// `BlurredBackgroundProviderImpl` (lines 51-64) as used by `EmojiView`'s
/// backspace/search/settings buttons (EmojiView.java:2923-2950).
///
/// A [size]-square box (default 48dp) hosting a `GlassPanel` with the
/// [GlassPresets.emojiViewButton] recipe, glass padding [glassPadding]
/// (default 6dp) and a circular radius `(size − 2·glassPadding) / 2` (18dp at
/// the defaults — the Java `setRadius(dp(18))`). The [icon] is centered; an
/// ambient [IconTheme] is installed with the `glass_defaultIcon` key at 60%
/// alpha (EmojiView.java:2651, 10135-10139) unless [iconColor] overrides it.
///
/// Pressing replays `ScaleStateListAnimator`: scale to 0.9 over 80ms, back
/// to 1.0 over 350ms with a 1.5-tension overshoot
/// (ScaleStateListAnimator.java:11-34).
///
/// Like every component in this package, the button takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention).
class GlassIconButton extends StatefulWidget {
  /// Creates the button.
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = kGlassIconButtonSize,
    this.glassPadding = kGlassIconButtonGlassPadding,
    this.iconColor,
    this.settings = const LiquidGlassSettings(),
    this.tier,
    this.resources,
  })  : assert(size > 0),
        assert(glassPadding >= 0),
        assert(glassPadding * 2 < size, 'Glass padding must leave a visible circle.');

  /// The centered icon (`ScaleType.CENTER`, EmojiView.java:2652). Rendered
  /// under an [IconTheme] carrying the resolved icon color.
  final Widget icon;

  /// Tap callback; null disables the button (it stays visible but inert and
  /// is reported disabled to semantics).
  final VoidCallback? onPressed;

  /// Accessibility description — the `setContentDescription` analog
  /// (EmojiView.java:2653), exposed as the semantics tooltip.
  final String? tooltip;

  /// Side of the square button box, default [kGlassIconButtonSize] (48dp,
  /// EmojiView.java:2679).
  final double size;

  /// Inset of the glass visuals inside the box, default
  /// [kGlassIconButtonGlassPadding] (6dp, EmojiView.java:2928).
  final double glassPadding;

  /// Icon color override; defaults to `glass_defaultIcon` at
  /// [kGlassIconButtonIconAlpha] (EmojiView.java:2651, 10135-10139).
  final Color? iconColor;

  /// Liquid refraction parameters forwarded to the panel.
  final LiquidGlassSettings settings;

  /// Per-panel tier override forwarded to the panel; null uses the enclosing
  /// `GlassBackdropScope` resolution.
  final GlassTier? tier;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  /// The circular glass radius: `(size − 2·glassPadding) / 2` —
  /// [kGlassIconButtonRadius] (18dp) at the defaults, matching the Java
  /// `setRadius(dp(18))` against the 6dp-padded 48dp view
  /// (EmojiView.java:2927-2928).
  double get glassRadius => (size - glassPadding * 2) / 2.0;

  @override
  State<GlassIconButton> createState() => GlassIconButtonState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ObjectFlagProperty<VoidCallback>.has('onPressed', onPressed))
      ..add(StringProperty('tooltip', tooltip, defaultValue: null))
      ..add(DoubleProperty('size', size, defaultValue: kGlassIconButtonSize))
      ..add(DoubleProperty('glassPadding', glassPadding,
          defaultValue: kGlassIconButtonGlassPadding))
      ..add(ColorProperty('iconColor', iconColor, defaultValue: null))
      ..add(EnumProperty<GlassTier>('tier', tier, defaultValue: null));
  }
}

/// State of [GlassIconButton]; public for test access to [debugPressScale].
class GlassIconButtonState extends State<GlassIconButton> with SingleTickerProviderStateMixin {
  /// Pressed factor: 0 resting, 1 fully pressed. Unbounded — the overshoot
  /// release curve legitimately dips below 0 (scale above 1.0), exactly like
  /// Android's `OvershootInterpolator`.
  late final AnimationController _pressed = AnimationController.unbounded(vsync: this, value: 0.0);

  /// The current visual scale: `lerp(1, 1 − 0.1, pressedFactor)` — the
  /// `ScaleStateListAnimator` state (pressed 0.9, resting 1.0, overshooting
  /// slightly above 1.0 on release).
  @visibleForTesting
  double get debugPressScale => 1.0 - kGlassIconButtonPressScale * _pressed.value;

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onPressed != null;

  /// `state_pressed` enter: scale toward 0.9 over 80ms with the Android
  /// default accelerate-decelerate (ScaleStateListAnimator.java:20-25).
  void _handleTapDown(TapDownDetails details) {
    if (!_enabled) {
      return;
    }
    _pressed.animateTo(
      1.0,
      duration: kGlassIconButtonPressDuration,
      curve: const _AccelerateDecelerateCurve(),
    );
  }

  /// `state_pressed` exit: back to 1.0 over 350ms with
  /// `OvershootInterpolator(1.5)` (ScaleStateListAnimator.java:27-34).
  void _release() {
    _pressed.animateTo(
      0.0,
      duration: kGlassIconButtonReleaseDuration,
      curve: const _OvershootCurve(kGlassIconButtonReleaseTension),
    );
  }

  Color _resolveIconColor(BuildContext context) {
    final Color? iconColor = widget.iconColor;
    if (iconColor != null) {
      return iconColor;
    }
    final TelegramResources? resources = widget.resources;
    final Color base = resources != null
        ? resources.getColor(TelegramColorKey.glass_defaultIcon)
        : TelegramTheme.colorOf(context, TelegramColorKey.glass_defaultIcon);
    // ColorUtils.setAlphaComponent(color, (int) (255 * 0.6f))
    // (EmojiView.java:10136-10138): the alpha channel is *replaced*.
    return base.withAlpha((255 * kGlassIconButtonIconAlpha).toInt());
  }

  @override
  Widget build(BuildContext context) {
    final Color iconColor = _resolveIconColor(context);
    return Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      tooltip: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _handleTapDown,
        onTapUp: (TapUpDetails details) => _release(),
        onTapCancel: _release,
        onTap: widget.onPressed,
        child: AnimatedBuilder(
          animation: _pressed,
          builder: (BuildContext context, Widget? child) =>
              Transform.scale(scale: debugPressScale, child: child),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: GlassPanel(
              preset: GlassPresets.emojiViewButton,
              borderRadius: GlassRadii.all(widget.glassRadius),
              padding: widget.glassPadding,
              settings: widget.settings,
              tier: widget.tier,
              resources: widget.resources,
              child: Center(
                child: IconTheme.merge(
                  data: IconThemeData(color: iconColor),
                  child: widget.icon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
