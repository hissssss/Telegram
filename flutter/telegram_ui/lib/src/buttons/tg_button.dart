// Port of `ui/Stories/recorder/ButtonWithCounterView.java` (BWC) — the
// canonical modern Telegram button (380 uses / 103 files) — with its press
// feedback from `ui/Components/ScaleStateListAnimator.java` (SSLA).
// Spec: `flutter/docs/spec_primitives.md` §1.
//
// Faithful recipe:
// - 48dp tall (call-site convention), corner radius 8dp (`radiusDp = 8`,
//   BWC:44), `setRound()` = 24dp stadium (BWC:67-70);
// - variants: filled `featuredStickers_addButton` / `featuredStickers_buttonText`
//   bold label (BWC:114-119), text mode = transparent + regular weight +
//   10%-alpha ripple of the label color (BWC:96-98, 170, 187), neutral =
//   `buttonNeutral` / `buttonNeutralText` (BWC:72-78);
// - press scale 0.98 over 80ms, release 350ms `OvershootInterpolator(1.2)`
//   (`ScaleStateListAnimator.apply(this, .02f, 1.2f)`, BWC:109; SSLA:15-33);
// - loading crossfade 320ms EASE_OUT_QUINT (BWC:350-351): the spinner
//   (`CircularProgressDrawable` in the label color, BWC:506) slides in from
//   `y = (1 − loadingT)·24dp` below center (BWC:508-509) while the content
//   translates up 24dp and squashes to ×0.6 vertically (BWC:519-520);
// - counter pill 18dp tall, r10, white-paint fill, 12dp bold count in the
//   fill color, 5dp gap after the label (BWC:118-119, 136-142, 558-575);
//   appear/disappear alpha 350ms EASE_OUT_QUINT (BWC:50-51), change bounce
//   `OvershootInterpolator(2.0)` 200ms (BWC:364-387); `setCountFilled(false)`
//   = bare 14dp bold count at 50% alpha (BWC:206-215, 579); timer mode ticks
//   the bare count down once per second (BWC:219-240);
// - disabled animates content alpha ×0.5↔×1.0 (stock 300ms ValueAnimator,
//   BWC:428-448) and ignores taps; the background does not change.
//
// Deliberately NOT ported:
// - per-glyph `AnimatedTextDrawable` animation for the main label
//   (BWC:121-122) — label changes swap immediately; the counter keeps a
//   minimal whole-string digit roll instead (PLAN_UIKIT.md §5 allows the
//   inline scoped port; amplitude/duration from
//   `setAnimationProperties(.3f, 0, 250, EASE_OUT_QUINT)`, BWC:137);
// - `withCounterIcon` (`mini_boost_button` drawable, BWC:391-398);
// - `setFlickeringLoading` LoadingDrawable shimmer (BWC:478-502);
// - `setUseWrapContent` / `setMinWidth` wrap machinery (BWC:632-663) — width
//   follows the incoming constraints (Java MATCH_PARENT convention);
// - `disableRippleView`, `setGlobalAlpha`, `setTextHacks`, and the Java
//   width-clobber quirk where a visible subText shifts the counter pill
//   (`width = subTextWidth`, BWC:541 — the pill here always positions
//   against the label + counter block).
library;

import 'dart:async' show Timer;
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';

import '../foundation/color_math.dart';
import '../foundation/tg_curves.dart';
import '../foundation/tg_text_styles.dart';
import '../progress/tg_circular_progress.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Button height: 48dp — not set in the Java class; every call site places
/// the view at 48dp (`createLinear/createFrame(MATCH_PARENT, 48)` grep,
/// spec_primitives.md §1.1).
const double kTgButtonHeight = 48.0;

/// Default corner radius: 8dp (`radiusDp = 8`, ButtonWithCounterView.java:44).
const double kTgButtonRadius = 8.0;

/// `setRound()` stadium radius: 24dp (ButtonWithCounterView.java:67-70).
const double kTgButtonRoundRadius = 24.0;

/// Pressed scale delta: `ScaleStateListAnimator.apply(this, .02f, 1.2f)`
/// (ButtonWithCounterView.java:109) — pressed scale is `1 − 0.02 = 0.98`.
const double kTgButtonPressScale = 0.02;

/// Release overshoot tension: 1.2 (ButtonWithCounterView.java:109;
/// ScaleStateListAnimator.java:32).
const double kTgButtonReleaseTension = 1.2;

/// Press-in duration: 80ms (`pressedAnimator.setDuration(80)`,
/// ScaleStateListAnimator.java:25).
const Duration kTgButtonPressDuration = Duration(milliseconds: 80);

/// Release duration: 350ms (`defaultAnimator.setDuration(350)`,
/// ScaleStateListAnimator.java:33).
const Duration kTgButtonReleaseDuration = Duration(milliseconds: 350);

/// Loading crossfade duration: 320ms EASE_OUT_QUINT
/// (ButtonWithCounterView.java:350-351).
const Duration kTgButtonLoadingDuration = Duration(milliseconds: 320);

/// Loading slide distance: 24dp — the spinner enters from
/// `(1 − loadingT)·24dp` below center (ButtonWithCounterView.java:508) while
/// the content translates up `loadingT·24dp` (ButtonWithCounterView.java:519).
const double kTgButtonLoadingShift = 24.0;

/// Loading vertical squash: content y-scale is `1 − 0.4·loadingT`
/// (ButtonWithCounterView.java:520).
const double kTgButtonLoadingSquash = 0.4;

/// Text-mode ripple alpha: `Theme.multAlpha(text.getTextColor(), .10f)`
/// (ButtonWithCounterView.java:170, 187).
const double kTgButtonTextRippleAlpha = 0.10;

/// Counter alpha animation: 350ms EASE_OUT_QUINT
/// (`new AnimatedFloat(350, CubicBezierInterpolator.EASE_OUT_QUINT)`,
/// ButtonWithCounterView.java:51).
const Duration kTgButtonCountAlphaDuration = Duration(milliseconds: 350);

/// Count-change bounce duration: 200ms (ButtonWithCounterView.java:385).
const Duration kTgButtonCountBounceDuration = Duration(milliseconds: 200);

/// Count-change bounce tension: `new OvershootInterpolator(2.0f)`
/// (ButtonWithCounterView.java:384).
const double kTgButtonCountBounceTension = 2.0;

/// Counter digit-roll duration: 250ms EASE_OUT_QUINT
/// (`countText.setAnimationProperties(.3f, 0, 250, EASE_OUT_QUINT)`,
/// ButtonWithCounterView.java:137).
const Duration kTgButtonCountRollDuration = Duration(milliseconds: 250);

/// Counter digit-roll amplitude as a fraction of the text height: 0.3
/// (`setAnimationProperties(.3f, …)`, ButtonWithCounterView.java:137).
const double kTgButtonCountRollAmplitude = 0.3;

/// Counter pill height: 18dp (ButtonWithCounterView.java:560-562).
const double kTgButtonCountPillHeight = 18.0;

/// Counter pill corner radius: 10dp (`dp(10)`,
/// ButtonWithCounterView.java:573).
const double kTgButtonCountPillRadius = 10.0;

/// Counter pill horizontal content padding: 4dp each side (`dp(… + 4 + 4)`,
/// ButtonWithCounterView.java:561).
const double kTgButtonCountPillPadding = 4.0;

/// Counter pill minimum content width: 9dp (`Math.max(dp(9), …)`,
/// ButtonWithCounterView.java:561).
const double kTgButtonCountPillMinTextWidth = 9.0;

/// Gap between label and filled pill: 5dp (`dp(countFilled ? 5 : 2)`,
/// ButtonWithCounterView.java:559).
const double kTgButtonCountGapFilled = 5.0;

/// Gap between label and bare (unfilled) count: 2dp
/// (ButtonWithCounterView.java:559).
const double kTgButtonCountGapBare = 2.0;

/// Extra width reserved for the counter besides the count text itself:
/// `dp(5.66f + 5 + 5)` (ButtonWithCounterView.java:527).
const double kTgButtonCountReservedExtra = 15.66;

/// Bare (unfilled) count draw alpha: ×0.5 (`countFilled ? 1 : .5f`,
/// ButtonWithCounterView.java:579).
const double kTgButtonBareCountAlpha = 0.5;

/// Bare (unfilled) count text size: 14dp (`dp(countFilled ? 12 : 14)`,
/// ButtonWithCounterView.java:209).
const double kTgButtonBareCountTextSize = 14.0;

/// Label lift when subText is visible: 7dp
/// (`rectTmp2.offset(0, (int) (-dp(7) * subTextT))`,
/// ButtonWithCounterView.java:534).
const double kTgButtonSubTextShift = 7.0;

/// SubText offset below center: 11dp (`rectTmp2.offset(0, dp(11))`,
/// ButtonWithCounterView.java:548).
const double kTgButtonSubTextOffset = 11.0;

/// SubText resting alpha: 200/255 (`subTextAlpha = 200`,
/// ButtonWithCounterView.java:468).
const double kTgButtonSubTextAlpha = 200 / 255;

/// SubText show/hide duration: 200ms `CubicBezierInterpolator.DEFAULT`
/// (ButtonWithCounterView.java:300-301, 315-316).
const Duration kTgButtonSubTextDuration = Duration(milliseconds: 200);

/// SubText scale-in start: 0.1 (`lerp(.1f, 1f, subTextT)`,
/// ButtonWithCounterView.java:550).
const double kTgButtonSubTextStartScale = 0.1;

/// Disabled content alpha: ×0.5 (`lerp(.5f, 1f, enabledT)`,
/// ButtonWithCounterView.java:535, 552, 572).
const double kTgButtonDisabledAlpha = 0.5;

/// Enable/disable animation: 300ms — the stock `ValueAnimator` default
/// duration and AccelerateDecelerate interpolator (no explicit values set,
/// ButtonWithCounterView.java:440-445).
const Duration kTgButtonEnableDuration = Duration(milliseconds: 300);

/// Vertical text nudge: the label/subText box sits 1dp above true center
/// (`… / 2f - dp(1)`, ButtonWithCounterView.java:530-532, 544-546).
const double kTgButtonLabelNudge = 1.0;

/// Android's `AccelerateDecelerateInterpolator` —
/// `cos((t + 1)·π)/2 + 0.5` — the `ValueAnimator` default interpolator
/// driving the press-in (ScaleStateListAnimator.java:20-25) and the
/// enable/disable fade (ButtonWithCounterView.java:440-445). File-local like
/// `glass_icon_button.dart`'s copy; not a `TgCurves` member because
/// foundation files are owned by the A0 build wave.
class _AccelerateDecelerateCurve extends Curve {
  const _AccelerateDecelerateCurve();

  @override
  double transformInternal(double t) => math.cos((t + 1) * math.pi) / 2.0 + 0.5;
}

const Curve _accelerateDecelerate = _AccelerateDecelerateCurve();

/// Release curve: `OvershootInterpolator(1.2)` (ButtonWithCounterView.java:109).
const Curve _releaseCurve = TgOvershootInterpolator(tension: kTgButtonReleaseTension);

/// Count-change bounce curve: `OvershootInterpolator(2.0)`
/// (ButtonWithCounterView.java:384).
const TgOvershootInterpolator _bounceCurve = TgOvershootInterpolator(tension: kTgButtonCountBounceTension);

/// Port of `LocaleController.formatNumber(count, ' ')`
/// (LocaleController.java:1636-1646): groups digits in threes from the right
/// with [separator] — the counter's space-grouped format
/// (ButtonWithCounterView.java:413).
String tgFormatNumber(int count, [String separator = ' ']) {
  if (count < 0) {
    return '-${tgFormatNumber(-count, separator)}';
  }
  final String digits = count.toString();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      out.write(separator);
    }
    out.write(digits[i]);
  }
  return out.toString();
}

/// The three visual modes of [TgButton] (`filled` constructor flag +
/// `setNeutral()`, ButtonWithCounterView.java:53-55, 72-78, 90-101).
enum TgButtonVariant {
  /// Filled `featuredStickers_addButton` background, bold
  /// `featuredStickers_buttonText` label (ButtonWithCounterView.java:114-119).
  filled,

  /// Transparent background, regular-weight `featuredStickers_addButton`
  /// label, ripple at 10% of the label color
  /// (ButtonWithCounterView.java:96-98, 187).
  text,

  /// Filled `buttonNeutral` background, bold `buttonNeutralText` label — the
  /// "secondary/cancel" filled button (ButtonWithCounterView.java:72-78).
  neutral,
}

/// The canonical modern Telegram button — the `ButtonWithCounterView` port
/// (spec_primitives.md §1): 48dp tall, r8 rounded (or r24 stadium), with the
/// loading spinner swap, the animated counter pill, subText, timer mode and
/// the `ScaleStateListAnimator` press scale.
///
/// A controlled widget: [loading], [count], [subText], [enabled] and
/// [timerSeconds] are plain state passed in; changing them across rebuilds
/// plays the corresponding Java animation (loading 320ms EASE_OUT_QUINT
/// crossfade, counter 350ms alpha + 200ms Overshoot(2.0) bounce, subText
/// 200ms, enabled 300ms).
///
/// Width follows the incoming constraints (the Java MATCH_PARENT convention);
/// give the button a bounded width (or set [width]) when placing it in an
/// unbounded context.
///
/// Like every component in this package, the button takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise keys resolve through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class TgButton extends StatefulWidget {
  /// Creates the button.
  const TgButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = TgButtonVariant.filled,
    this.radius = kTgButtonRadius,
    this.height = kTgButtonHeight,
    this.width,
    this.enabled = true,
    this.loading = false,
    this.count = 0,
    this.showZero = false,
    this.countFilled = true,
    this.subText,
    this.timerSeconds,
    this.onTimerDone,
    this.color,
    this.resources,
  });

  /// The label, 14dp — bold in filled/neutral mode, regular in text mode
  /// (ButtonWithCounterView.java:124-127, 96-98). Also the semantics label
  /// (`setContentDescription`, ButtonWithCounterView.java:255).
  final String text;

  /// Tap callback; null renders the button inert (no press feedback, no
  /// semantics tap action) without playing the disabled fade — use [enabled]
  /// for the animated 0.5-alpha disabled state.
  final VoidCallback? onPressed;

  /// Visual mode (ButtonWithCounterView.java:53-55, 72-78).
  final TgButtonVariant variant;

  /// Corner radius, default [kTgButtonRadius] (8dp,
  /// ButtonWithCounterView.java:44); pass [kTgButtonRoundRadius] (24dp) for
  /// the `setRound()` stadium (ButtonWithCounterView.java:67-70).
  final double radius;

  /// Button height, default [kTgButtonHeight] (48dp call-site convention).
  final double height;

  /// Fixed width; null stretches to the incoming constraints (the Java
  /// MATCH_PARENT convention).
  final double? width;

  /// Disabled buttons animate their content to ×0.5 alpha over 300ms and
  /// ignore taps (ButtonWithCounterView.java:428-448); the background does
  /// not change.
  final bool enabled;

  /// Loading state: crossfades label↔spinner over 320ms EASE_OUT_QUINT
  /// (`setLoading`, ButtonWithCounterView.java:326-354).
  final bool loading;

  /// Counter value (`setCount`, ButtonWithCounterView.java:404-415); 0 hides
  /// the counter unless [showZero]. Ignored while [timerSeconds] is active.
  final int count;

  /// Whether a zero count stays visible (`setShowZero`,
  /// ButtonWithCounterView.java:400-402).
  final bool showZero;

  /// true = white pill with the count in the fill color; false = bare 14dp
  /// bold count in the label color at 50% alpha (`setCountFilled`,
  /// ButtonWithCounterView.java:206-215).
  final bool countFilled;

  /// Optional second line, 12dp at 200/255 alpha, 11dp below center; the
  /// main label lifts 7dp while visible (`setSubText`,
  /// ButtonWithCounterView.java:278-319, 534-556).
  final String? subText;

  /// Timer mode (`setTimer`, ButtonWithCounterView.java:219-240): counts
  /// down from this value once per second as a bare count, ignoring taps
  /// until it reaches 0 (the Java recipe re-enables clicks at 0). Setting a
  /// new value restarts the countdown; null cancels it.
  final int? timerSeconds;

  /// Fired when the [timerSeconds] countdown reaches 0 (`whenTimerUp`,
  /// ButtonWithCounterView.java:232-234).
  final VoidCallback? onTimerDone;

  /// Custom color (`setColor`, ButtonWithCounterView.java:164-172): replaces
  /// the fill in filled/neutral mode, or the label + ripple color in text
  /// mode.
  final Color? color;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  @override
  State<TgButton> createState() => TgButtonState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('text', text))
      ..add(ObjectFlagProperty<VoidCallback>.has('onPressed', onPressed))
      ..add(EnumProperty<TgButtonVariant>('variant', variant, defaultValue: TgButtonVariant.filled))
      ..add(DoubleProperty('radius', radius, defaultValue: kTgButtonRadius))
      ..add(FlagProperty('enabled', value: enabled, ifFalse: 'disabled'))
      ..add(FlagProperty('loading', value: loading, ifTrue: 'loading'))
      ..add(IntProperty('count', count, defaultValue: 0))
      ..add(StringProperty('subText', subText, defaultValue: null));
  }
}

/// State of [TgButton]; public for test access to the debug getters.
class TgButtonState extends State<TgButton> with TickerProviderStateMixin {
  /// Pressed factor: 0 resting, 1 fully pressed. Unbounded — the overshoot
  /// release dips below 0 (scale above 1.0), like Android's
  /// `OvershootInterpolator`.
  late final AnimationController _pressed = AnimationController.unbounded(vsync: this, value: 0.0);

  /// `loadingT` (ButtonWithCounterView.java:323): animated 320ms
  /// EASE_OUT_QUINT from the current value, like the Java `ValueAnimator`.
  late final AnimationController _loading = AnimationController(vsync: this, value: widget.loading ? 1.0 : 0.0);

  /// `enabledT` (ButtonWithCounterView.java:428).
  late final AnimationController _enabled = AnimationController(vsync: this, value: widget.enabled ? 1.0 : 0.0);

  /// `countAlpha` through its `AnimatedFloat(350, EASE_OUT_QUINT)`
  /// (ButtonWithCounterView.java:50-51).
  late final AnimationController _countAlpha = AnimationController(vsync: this);

  /// Bounce clock, 0..1 over 200ms; the pill scale is
  /// `max(1, overshoot₂(t))` (ButtonWithCounterView.java:372-386).
  late final AnimationController _bounce = AnimationController(vsync: this, duration: kTgButtonCountBounceDuration, value: 1.0);

  /// Digit-roll clock, 0..1 over 250ms (ButtonWithCounterView.java:137).
  late final AnimationController _roll = AnimationController(vsync: this, duration: kTgButtonCountRollDuration, value: 1.0);

  /// `subTextT` (ButtonWithCounterView.java:263).
  late final AnimationController _subTextT = AnimationController(vsync: this, value: widget.subText != null ? 1.0 : 0.0);

  /// Spinner clock — runs only while `loadingT > 0`, mirroring the
  /// `CircularProgressDrawable` self-invalidation loop.
  late final Ticker _spinnerTicker = createTicker(_onSpinnerTick);
  final ValueNotifier<Duration> _spinnerElapsed = ValueNotifier<Duration>(Duration.zero);

  int _lastCount = 0;
  String _countText = '';
  String? _oldCountText;
  bool _rollUp = true;
  String? _subTextString;

  Timer? _timer;
  int _timerRemaining = 0;

  /// The current visual scale: `lerp(1, 0.98, pressedFactor)` — the
  /// `ScaleStateListAnimator.apply(this, .02f, 1.2f)` state
  /// (ButtonWithCounterView.java:109).
  @visibleForTesting
  double get debugPressScale => 1.0 - kTgButtonPressScale * _pressed.value;

  /// The current `loadingT` (ButtonWithCounterView.java:323).
  @visibleForTesting
  double get debugLoadingFactor => _loading.value;

  /// The current `enabledT` (ButtonWithCounterView.java:428).
  @visibleForTesting
  double get debugEnabledFactor => _enabled.value;

  /// The current counter alpha (ButtonWithCounterView.java:50-51).
  @visibleForTesting
  double get debugCountAlpha => _countAlpha.value;

  /// The current `subTextT` (ButtonWithCounterView.java:263).
  @visibleForTesting
  double get debugSubTextFactor => _subTextT.value;

  /// Whether the countdown is still running (`isTimerActive`,
  /// ButtonWithCounterView.java:238-240).
  bool get isTimerActive => _timerRemaining > 0;

  /// Seconds left on the countdown (`timerSeconds`,
  /// ButtonWithCounterView.java:217).
  int get timerRemaining => _timerRemaining;

  bool get _effectiveEnabled => widget.enabled && widget.onPressed != null && !isTimerActive;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.count;
    _countText = tgFormatNumber(widget.count);
    _countAlpha.value = widget.count != 0 || widget.showZero ? 1.0 : 0.0;
    _subTextString = widget.subText;
    _loading.addListener(_syncSpinnerTicker);
    final int? timerSeconds = widget.timerSeconds;
    if (timerSeconds != null) {
      _startTimer(timerSeconds);
    }
    _syncSpinnerTicker();
  }

  @override
  void didUpdateWidget(TgButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading != oldWidget.loading) {
      // ValueAnimator.ofFloat(loadingT, target), 320ms EASE_OUT_QUINT
      // (ButtonWithCounterView.java:338-352).
      _loading.animateTo(
        widget.loading ? 1.0 : 0.0,
        duration: kTgButtonLoadingDuration,
        curve: TgCurves.easeOutQuint,
      );
      _syncSpinnerTicker();
    }
    if (widget.enabled != oldWidget.enabled) {
      // Stock ValueAnimator: 300ms AccelerateDecelerate
      // (ButtonWithCounterView.java:440-445).
      _enabled.animateTo(
        widget.enabled ? 1.0 : 0.0,
        duration: kTgButtonEnableDuration,
        curve: _accelerateDecelerate,
      );
    }
    if (widget.timerSeconds != oldWidget.timerSeconds) {
      final int? timerSeconds = widget.timerSeconds;
      if (timerSeconds == null) {
        _timer?.cancel();
        _timer = null;
        _timerRemaining = 0;
        _applyCount(widget.count, animated: false);
      } else {
        _startTimer(timerSeconds);
      }
    } else if (widget.timerSeconds == null &&
        (widget.count != oldWidget.count || widget.showZero != oldWidget.showZero)) {
      // Controlled-widget convention: programmatic changes animate.
      _applyCount(widget.count, animated: true);
    }
    final String? subText = widget.subText;
    if (subText != oldWidget.subText) {
      if (subText != null) {
        _subTextString = subText;
      }
      // 200ms CubicBezierInterpolator.DEFAULT both ways
      // (ButtonWithCounterView.java:300-301, 315-316); the outgoing string is
      // kept until the fade completes (subText.setText(null) fires onEnd,
      // ButtonWithCounterView.java:293-299).
      _subTextT.animateTo(
        subText != null ? 1.0 : 0.0,
        duration: kTgButtonSubTextDuration,
        curve: TgCurves.defaultCubic,
      );
    }
  }

  /// `setCount(count, animated)` (ButtonWithCounterView.java:404-415).
  void _applyCount(int count, {required bool animated}) {
    final String newText = tgFormatNumber(count);
    // Bounce only on a change between two visible counts
    // (ButtonWithCounterView.java:408-410).
    if (animated && count != _lastCount && count > 0 && _lastCount > 0) {
      _bounce.forward(from: 0.0);
    }
    if (newText != _countText) {
      if (animated) {
        _oldCountText = _countText;
        _rollUp = count >= _lastCount;
        _roll.forward(from: 0.0);
      } else {
        _oldCountText = null;
        _roll.value = 1.0;
      }
      _countText = newText;
    }
    _lastCount = count;
    // showZero is forced off in timer mode (setShowZero(false),
    // ButtonWithCounterView.java:224).
    final bool visible = count != 0 || (widget.timerSeconds == null && widget.showZero);
    if (animated) {
      _countAlpha.animateTo(
        visible ? 1.0 : 0.0,
        duration: kTgButtonCountAlphaDuration,
        curve: TgCurves.easeOutQuint,
      );
    } else {
      _countAlpha.value = visible ? 1.0 : 0.0;
    }
  }

  /// `setTimer(seconds, whenTimerUp)` (ButtonWithCounterView.java:219-237):
  /// bare count, one tick per second, callback at zero.
  void _startTimer(int seconds) {
    _timer?.cancel();
    _timerRemaining = seconds;
    _applyCount(seconds, animated: false);
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      setState(() {
        _timerRemaining--;
        _applyCount(_timerRemaining, animated: true);
        if (_timerRemaining <= 0) {
          timer.cancel();
          _timer = null;
          widget.onTimerDone?.call();
        }
      });
    });
  }

  void _onSpinnerTick(Duration elapsed) {
    _spinnerElapsed.value = elapsed;
  }

  /// The spinner animates only while visible (`if (loadingT > 0) …
  /// invalidate()`, ButtonWithCounterView.java:504-513).
  void _syncSpinnerTicker() {
    final bool needed = widget.loading || _loading.value > 0.0;
    if (needed && !_spinnerTicker.isActive) {
      _spinnerElapsed.value = Duration.zero;
      _spinnerTicker.start();
    } else if (!needed && _spinnerTicker.isActive) {
      _spinnerTicker.stop();
    }
  }

  /// `state_pressed` enter: scale toward 0.98 over 80ms with the Android
  /// default accelerate-decelerate (ScaleStateListAnimator.java:20-25).
  void _handleTapDown(TapDownDetails details) {
    if (!_effectiveEnabled) {
      return;
    }
    _pressed.animateTo(1.0, duration: kTgButtonPressDuration, curve: _accelerateDecelerate);
  }

  /// `state_pressed` exit: back to 1.0 over 350ms with
  /// `OvershootInterpolator(1.2)` (ScaleStateListAnimator.java:27-33).
  void _handleRelease() {
    if (_pressed.value == 0.0 && !_pressed.isAnimating) {
      return;
    }
    _pressed.animateTo(0.0, duration: kTgButtonReleaseDuration, curve: _releaseCurve);
  }

  void _handleTap() {
    if (!_effectiveEnabled) {
      return;
    }
    widget.onPressed!();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _spinnerTicker.dispose();
    _spinnerElapsed.dispose();
    _pressed.dispose();
    _loading.dispose();
    _enabled.dispose();
    _countAlpha.dispose();
    _bounce.dispose();
    _roll.dispose();
    _subTextT.dispose();
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
    final bool filled = widget.variant != TgButtonVariant.text;
    final bool neutral = widget.variant == TgButtonVariant.neutral;
    final Color? custom = widget.color;

    // `backgroundColor` (updateColors, ButtonWithCounterView.java:180-181;
    // setColor override at :164-167). Resolved even in text mode — it is the
    // counter text color (ButtonWithCounterView.java:190).
    final Color backgroundKeyColor = _color(
      context,
      neutral ? TelegramColorKey.buttonNeutral : TelegramColorKey.featuredStickers_addButton,
    );
    final Color backgroundColor = filled && custom != null ? custom : backgroundKeyColor;
    // Label color (ButtonWithCounterView.java:183; text-mode setColor at
    // :169).
    final Color labelColor = filled
        ? _color(
            context,
            neutral ? TelegramColorKey.buttonNeutralText : TelegramColorKey.featuredStickers_buttonText,
          )
        : (custom ?? _color(context, TelegramColorKey.featuredStickers_addButton));
    // Ripple: listSelector when filled, 10% of the label color otherwise
    // (ButtonWithCounterView.java:184-188).
    final Color rippleColor = filled
        ? _color(context, TelegramColorKey.listSelector)
        : Color(multAlpha(labelColor.toARGB32(), kTgButtonTextRippleAlpha));
    // Pill paint: always featuredStickers_buttonText
    // (ButtonWithCounterView.java:118-119, 191).
    final Color pillColor = _color(context, TelegramColorKey.featuredStickers_buttonText);
    // Timer mode forces the bare count (setCountFilled(false),
    // ButtonWithCounterView.java:222).
    final bool countFilled = widget.countFilled && widget.timerSeconds == null;
    // Count color: the fill color when filled, else the label color (drawn
    // at 50% alpha by the painter) (ButtonWithCounterView.java:190, 206-215).
    final Color countColor = countFilled ? backgroundColor : labelColor;

    // Filled label is bold (Roboto Medium), text mode regular — both 14dp
    // (ButtonWithCounterView.java:95-98, 124-127). Roles: label = 14/w500,
    // subtitle = 14/w400, microEmphasis = 12/w500, micro = 12/w400.
    final TextStyle labelStyle = (filled ? TgTextStyles.label : TgTextStyles.subtitle).copyWith(color: labelColor);
    final TextStyle countStyle =
        (countFilled ? TgTextStyles.microEmphasis : TgTextStyles.label).copyWith(color: countColor);
    final TextStyle subTextStyle = TgTextStyles.micro.copyWith(color: labelColor);
    final TextDirection textDirection = Directionality.of(context);

    return Semantics(
      container: true,
      button: true,
      enabled: _effectiveEnabled,
      label: widget.text,
      // The tap action lives on the Semantics node (absent while inert);
      // the raw GestureDetector below is excluded so its press-feedback
      // handlers do not register a second, always-on tap action.
      onTap: _effectiveEnabled ? _handleTap : null,
      child: GestureDetector(
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        onTapDown: _handleTapDown,
        onTapUp: (TapUpDetails details) => _handleRelease(),
        onTapCancel: _handleRelease,
        onTap: _effectiveEnabled ? _handleTap : null,
        child: SizedBox(
          height: widget.height,
          width: widget.width ?? double.infinity,
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              _pressed,
              _loading,
              _enabled,
              _countAlpha,
              _bounce,
              _roll,
              _subTextT,
              _spinnerElapsed,
            ]),
            builder: (BuildContext context, Widget? child) {
              return Transform.scale(
                scale: debugPressScale,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: TgButtonContentPainter(
                    backgroundColor: filled ? backgroundColor : null,
                    radius: widget.radius,
                    rippleColor: rippleColor,
                    highlightT: _pressed.value.clamp(0.0, 1.0),
                    label: widget.text,
                    labelStyle: labelStyle,
                    subText: _subTextT.value > 0.0 ? _subTextString : null,
                    subTextStyle: subTextStyle,
                    subTextT: _subTextT.value,
                    countText: _countText,
                    oldCountText: _roll.value < 1.0 ? _oldCountText : null,
                    rollT: _roll.value,
                    rollUp: _rollUp,
                    countStyle: countStyle,
                    countAlpha: _countAlpha.value,
                    countBounceScale: math.max(1.0, _bounceCurve.transform(_bounce.value)),
                    countFilled: countFilled,
                    pillColor: pillColor,
                    loadingT: _loading.value,
                    spinnerElapsed: _spinnerElapsed.value,
                    enabledT: _enabled.value,
                    textDirection: textDirection,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The `ButtonWithCounterView.onDraw` port (ButtonWithCounterView.java:
/// 474-610): background rounded rect, press highlight, spinner, label,
/// subText and counter pill in one painter. Public so tests can probe the
/// resolved colors and animation factors.
class TgButtonContentPainter extends CustomPainter {
  /// Creates the painter with all values pre-resolved by [TgButtonState].
  TgButtonContentPainter({
    required this.backgroundColor,
    required this.radius,
    required this.rippleColor,
    required this.highlightT,
    required this.label,
    required this.labelStyle,
    required this.subText,
    required this.subTextStyle,
    required this.subTextT,
    required this.countText,
    required this.oldCountText,
    required this.rollT,
    required this.rollUp,
    required this.countStyle,
    required this.countAlpha,
    required this.countBounceScale,
    required this.countFilled,
    required this.pillColor,
    required this.loadingT,
    required this.spinnerElapsed,
    required this.enabledT,
    required this.textDirection,
  });

  /// Fill color; null in text mode (`setBackground(null)`,
  /// ButtonWithCounterView.java:97).
  final Color? backgroundColor;

  /// Corner radius (ButtonWithCounterView.java:44, 67-88).
  final double radius;

  /// Press-highlight color — `listSelector` when filled, 10%-alpha label
  /// color in text mode (ButtonWithCounterView.java:184-188). The color's
  /// own alpha is further scaled by [highlightT] (a simple highlight stands
  /// in for the Android ripple, per the package convention).
  final Color rippleColor;

  /// Press factor 0..1 driving the highlight opacity.
  final double highlightT;

  /// Label string (ButtonWithCounterView.java:250-257).
  final String label;

  /// Resolved label style (14dp, bold when filled) including color.
  final TextStyle labelStyle;

  /// SubText string, or null when hidden (ButtonWithCounterView.java:278).
  final String? subText;

  /// Resolved subText style (12dp regular).
  final TextStyle subTextStyle;

  /// `subTextT` 0..1 (ButtonWithCounterView.java:263).
  final double subTextT;

  /// Current counter string, space-grouped (ButtonWithCounterView.java:413).
  final String countText;

  /// Previous counter string while the digit roll is in flight, else null.
  final String? oldCountText;

  /// Digit-roll clock 0..1; eased EASE_OUT_QUINT here
  /// (ButtonWithCounterView.java:137).
  final double rollT;

  /// Roll direction: true = count increased (new text enters from below).
  final bool rollUp;

  /// Resolved count style (12dp bold pill / 14dp bold bare) including color.
  final TextStyle countStyle;

  /// Counter alpha 0..1 (ButtonWithCounterView.java:50-51, 524).
  final double countAlpha;

  /// Pill bounce scale, `max(1, overshoot₂(t))`
  /// (ButtonWithCounterView.java:374, 567-569).
  final double countBounceScale;

  /// Pill (true) vs bare count (false) (ButtonWithCounterView.java:206).
  final bool countFilled;

  /// Pill fill — `featuredStickers_buttonText`
  /// (ButtonWithCounterView.java:118-119, 191).
  final Color pillColor;

  /// `loadingT` 0..1 (ButtonWithCounterView.java:323).
  final double loadingT;

  /// Spinner clock, wrapped into the 5400ms cycle by the spinner painter.
  final Duration spinnerElapsed;

  /// `enabledT` 0..1; content alpha is `lerp(0.5, 1, enabledT)`
  /// (ButtonWithCounterView.java:428, 535).
  final double enabledT;

  /// Ambient text direction for text layout.
  final TextDirection textDirection;

  /// Content alpha from the enabled state: `lerp(.5f, 1f, enabledT)`
  /// (ButtonWithCounterView.java:535).
  double get contentAlpha => lerpDouble(kTgButtonDisabledAlpha, 1.0, enabledT)!;

  /// Label draw opacity: `(1 − loadingT) · lerp(.5, 1, enabledT)`
  /// (ButtonWithCounterView.java:535).
  double get labelOpacity => ((1.0 - loadingT) * contentAlpha).clamp(0.0, 1.0);

  TextPainter _layoutText(String text, TextStyle style, double alpha, double maxWidth) {
    final Color base = style.color ?? const Color(0xFFFFFFFF);
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(color: base.withValues(alpha: base.a * alpha.clamp(0.0, 1.0))),
      ),
      textDirection: textDirection,
      maxLines: 1,
      ellipsis: '…',
      textHeightBehavior: kTgTextHeightBehavior,
    )..layout(maxWidth: math.max(0.0, maxWidth));
    return painter;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final Color? backgroundColor = this.backgroundColor;
    if (backgroundColor != null) {
      // Theme.createRoundRectDrawable(dp(radiusDp), backgroundColor)
      // (ButtonWithCounterView.java:94, 115).
      canvas.drawRRect(rrect, Paint()..color = backgroundColor);
    }
    if (highlightT > 0.0) {
      // rippleView.draw(canvas) (ButtonWithCounterView.java:476) — a simple
      // pressed highlight in place of the Android ripple.
      canvas.drawRRect(
        rrect,
        Paint()..color = rippleColor.withValues(alpha: rippleColor.a * highlightT),
      );
    }

    if (loadingT > 0.0) {
      // Spinner slides in from (1 − loadingT)·24dp below center while
      // fading (ButtonWithCounterView.java:504-513).
      final Color spinnerColor = labelStyle.color ?? kTgCircularProgressDefaultColor;
      canvas.save();
      canvas.translate(0.0, (1.0 - loadingT) * kTgButtonLoadingShift);
      TgCircularProgressPainter(
        elapsed: spinnerElapsed,
        color: spinnerColor.withValues(alpha: spinnerColor.a * loadingT.clamp(0.0, 1.0)),
      ).paint(canvas, size);
      canvas.restore();
    }

    if (loadingT < 1.0) {
      _paintContent(canvas, size);
    }
  }

  void _paintContent(Canvas canvas, Size size) {
    canvas.save();
    // Content lifts 24dp and squashes to ×0.6 vertically as the spinner
    // takes over (ButtonWithCounterView.java:517-521).
    canvas.translate(0.0, -kTgButtonLoadingShift * loadingT);
    canvas.scale(1.0, 1.0 - kTgButtonLoadingSquash * loadingT);

    // Counter layout first: the label block centers on
    // textWidth + reserved counter width (ButtonWithCounterView.java:523-533).
    final double rollEased = TgCurves.easeOutQuint.transform(rollT.clamp(0.0, 1.0));
    // countText alpha deliberately omits enabledT, as in Java
    // (ButtonWithCounterView.java:579).
    final double countDrawAlpha =
        ((1.0 - loadingT) * countAlpha * (countFilled ? 1.0 : kTgButtonBareCountAlpha)).clamp(0.0, 1.0);
    final String? oldCountText = this.oldCountText;
    final TextPainter newCountPainter =
        _layoutText(countText, countStyle, countDrawAlpha * (oldCountText != null ? rollEased : 1.0), size.width);
    TextPainter? oldCountPainter;
    double countTextWidth = newCountPainter.width;
    if (oldCountText != null) {
      oldCountPainter = _layoutText(oldCountText, countStyle, countDrawAlpha * (1.0 - rollEased), size.width);
      // AnimatedTextDrawable.getCurrentWidth lerps old→new width during the
      // roll (minimal whole-string port).
      countTextWidth = lerpDouble(oldCountPainter.width, newCountPainter.width, rollEased)!;
    }

    final TextPainter labelPainter = _layoutText(label, labelStyle, labelOpacity, size.width);
    final double textWidth = labelPainter.width;
    final double reserved = (kTgButtonCountReservedExtra + countTextWidth) * countAlpha;
    final double blockLeft = (size.width - (textWidth + reserved)) / 2.0;

    // Label box: 1dp above center, lifted 7dp·subTextT
    // (ButtonWithCounterView.java:528-537).
    final double labelTop =
        (size.height - labelPainter.height) / 2.0 - kTgButtonLabelNudge - kTgButtonSubTextShift * subTextT;
    labelPainter.paint(canvas, Offset(blockLeft, labelTop));
    labelPainter.dispose();

    final String? subText = this.subText;
    if (subText != null && subTextT > 0.0) {
      // SubText: centered, 11dp below the (1dp-nudged) center, alpha
      // 200/255 · (1 − loadingT) · subTextT · enabled, scaling in from 0.1
      // around its bottom-center (ButtonWithCounterView.java:539-556).
      final double subAlpha =
          (kTgButtonSubTextAlpha * (1.0 - loadingT) * subTextT * contentAlpha).clamp(0.0, 1.0);
      final TextPainter subPainter = _layoutText(subText, subTextStyle, subAlpha, size.width);
      final double subTop =
          (size.height - subPainter.height) / 2.0 - kTgButtonLabelNudge + kTgButtonSubTextOffset;
      final Offset pivot = Offset(size.width / 2.0, subTop + subPainter.height);
      final double scale = lerpDouble(kTgButtonSubTextStartScale, 1.0, subTextT)!;
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.scale(scale, scale);
      canvas.translate(-pivot.dx, -pivot.dy);
      subPainter.paint(canvas, Offset(size.width / 2.0 - subPainter.width / 2.0, subTop));
      canvas.restore();
      subPainter.dispose();
    }

    if (countAlpha > 0.0) {
      // Pill: 18dp tall, 4+4dp padding around max(9dp, count width), 5dp
      // (2dp bare) after the label (ButtonWithCounterView.java:558-575).
      final double gap = countFilled ? kTgButtonCountGapFilled : kTgButtonCountGapBare;
      final double pillWidth =
          kTgButtonCountPillPadding * 2.0 + math.max(kTgButtonCountPillMinTextWidth, countTextWidth);
      final Rect pill = Rect.fromLTWH(
        blockLeft + textWidth + gap,
        (size.height - kTgButtonCountPillHeight) / 2.0,
        pillWidth,
        kTgButtonCountPillHeight,
      );
      canvas.save();
      if (countBounceScale != 1.0) {
        // Bounce from the pill center (ButtonWithCounterView.java:567-569).
        canvas.translate(pill.center.dx, pill.center.dy);
        canvas.scale(countBounceScale, countBounceScale);
        canvas.translate(-pill.center.dx, -pill.center.dy);
      }
      if (countFilled) {
        // paint alpha = (1 − loadingT) · countAlpha² · lerp(.5, 1, enabledT)
        // (ButtonWithCounterView.java:571-575).
        final double pillAlpha = ((1.0 - loadingT) * countAlpha * countAlpha * contentAlpha).clamp(0.0, 1.0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(pill, const Radius.circular(kTgButtonCountPillRadius)),
          Paint()..color = pillColor.withValues(alpha: pillColor.a * pillAlpha),
        );
      }
      // Count text nudges: −0.3dp for multi-digit counts, −0.4dp vertical
      // (ButtonWithCounterView.java:577-578).
      final double nudgeX = countText.length > 1 ? -0.3 : 0.0;
      const double nudgeY = -0.4;
      void drawCount(TextPainter painter, double dy) {
        painter.paint(
          canvas,
          Offset(
            pill.center.dx - painter.width / 2.0 + nudgeX,
            pill.center.dy - painter.height / 2.0 + nudgeY + dy,
          ),
        );
      }

      if (oldCountPainter != null) {
        // Minimal digit roll: old text slides out, new slides in, amplitude
        // 0.3 of the text height (ButtonWithCounterView.java:137).
        final double amplitude = kTgButtonCountRollAmplitude * newCountPainter.height;
        final double direction = rollUp ? 1.0 : -1.0;
        drawCount(oldCountPainter, -direction * amplitude * rollEased);
        drawCount(newCountPainter, direction * amplitude * (1.0 - rollEased));
      } else {
        drawCount(newCountPainter, 0.0);
      }
      canvas.restore();
    }
    oldCountPainter?.dispose();
    newCountPainter.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(TgButtonContentPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.radius != radius ||
        oldDelegate.rippleColor != rippleColor ||
        oldDelegate.highlightT != highlightT ||
        oldDelegate.label != label ||
        oldDelegate.labelStyle != labelStyle ||
        oldDelegate.subText != subText ||
        oldDelegate.subTextStyle != subTextStyle ||
        oldDelegate.subTextT != subTextT ||
        oldDelegate.countText != countText ||
        oldDelegate.oldCountText != oldCountText ||
        oldDelegate.rollT != rollT ||
        oldDelegate.rollUp != rollUp ||
        oldDelegate.countStyle != countStyle ||
        oldDelegate.countAlpha != countAlpha ||
        oldDelegate.countBounceScale != countBounceScale ||
        oldDelegate.countFilled != countFilled ||
        oldDelegate.pillColor != pillColor ||
        oldDelegate.loadingT != loadingT ||
        oldDelegate.spinnerElapsed != spinnerElapsed ||
        oldDelegate.enabledT != enabledT ||
        oldDelegate.textDirection != textDirection;
  }
}
