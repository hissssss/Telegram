// The mic / video / send button of the chat input bar — a port of the
// `audioVideoButtonContainer` slot of
// `java/org/telegram/ui/Components/ChatActivityEnterView.java` (**CAEV**):
//
//  * the 44x44dp container with the visible 38x38dp send-area circle
//    (CAEV:3188-3209) and the 24dp animated mic/video icon (CAEV:3387-3407);
//  * tap toggles voice <-> video with the `voice_and_video` icon morph and a
//    KEYBOARD_TAP haptic (CAEV:3063-3073;
//    ChatActivityEnterViewAnimatedIconView.java:42-76, cited as **AIV**);
//  * holding 150ms arms a recording (`recordAudioVideoRunnable`,
//    CAEV:3013-3018, 895-956) and expands the `RecordCircle` (CAEV:1945-2555);
//  * while the field has text the mic/video icon morphs into the send plane
//    (scale 0.1 + fade, 220ms EASE_OUT_QUINT out / 150ms back,
//    CAEV:8153-8189, 8604).
//
// Presentation + gesture state machine only: microphone amplitude is a
// callback slot ([RecordSendButton.amplitude]) and no audio/camera capture
// exists anywhere in this package (flutter/docs/spec_chat_input.md, "capture
// pipelines are callback slots"). Slide-to-cancel, lock and timer live in the
// separate record overlay component; this button reports record start/end and
// leaves the rest to its owner.
//
// Note on springs: the Java sources animate this surface with
// `DecelerateInterpolator` plus a hand-rolled overshoot mapping
// (CAEV:2152-2160, 8923-8961) — androidx `SpringAnimation` is only used for
// the unrelated sender-select avatar (CAEV:4242-4332) — so no
// `SpringDescription` appears here.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import '../../foundation/tg_curves.dart';
import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';

/// Recording mode — the Java `isInVideoMode()` flag, i.e.
/// `ChatActivityEnterViewAnimatedIconView.State.VOICE` / `State.VIDEO`
/// (AIV:52, CAEV:6112-6120).
enum RecordMode {
  /// Voice-note mode (`State.VOICE`; static lottie progress 0.5, AIV:52).
  voice,

  /// Round-video mode (`State.VIDEO`; static lottie progress 0, AIV:52).
  video,
}

/// The visible state of a [RecordSendButton].
enum RecordSendState {
  /// Resting, voice mode: mic icon on the send-area circle.
  mic,

  /// Resting, video mode: camera icon on the send-area circle.
  video,

  /// The field has text: the send plane (tap fires [RecordSendButton.onSend]).
  send,

  /// A recording is armed: the `RecordCircle` is expanded (CAEV:1945-2555).
  recording,
}

/// Button slot size: `DEFAULT_HEIGHT` = 44dp — `createFrame(44, 44,
/// RIGHT | BOTTOM)` inside the 100x44dp `sendButtonContainer`
/// (CAEV:6410, 3209).
const double kRecordSendButtonSize = 44.0;

/// Visible send-area circle: `dpf2(38)` square (CAEV:3191-3192).
const double kRecordSendCircleSize = 38.0;

/// Send-area corner radius: `dpf2(19)` (CAEV:3188).
const double kRecordSendCircleRadius = 19.0;

/// Send-area margin from the container's bottom-right corner: `dpf2(3)`
/// (CAEV:3190).
const double kRecordSendCircleMargin = 3.0;

/// Icon lottie box: `new ChatActivityEnterViewAnimatedIconView(context, 24)`
/// (CAEV:3387).
const double kRecordSendIconSize = 24.0;

/// Icon content padding: `setPadding(dp(10), ...)` on the 44dp frame
/// (CAEV:3404-3405).
const double kRecordSendIconPadding = 10.0;

/// Hold delay before recording arms:
/// `runOnUIThread(recordAudioVideoRunnable, 150)` (CAEV:3016). Applies only
/// when video recording is available; without it the runnable runs directly
/// at pointer-down (CAEV:3018).
const Duration kRecordSendHoldDelay = Duration(milliseconds: 150);

/// Duration of the voice <-> video icon morph: the `voice_and_video` lottie
/// plays 30 frames each way (VIDEO -> VOICE frames 0 -> 30, VOICE -> VIDEO
/// progress 0.5 -> frame 60, AIV:63-69) at the raw's 60fps
/// (`res/raw/voice_and_video.json`, `"fr": 60`) = 500ms.
const Duration kRecordSendModeSwitchDuration = Duration(milliseconds: 500);

/// Mic -> send morph when text appears: 220ms EASE_OUT_QUINT
/// (CAEV:8187-8189).
const Duration kRecordSendMorphDuration = Duration(milliseconds: 220);

/// Send -> mic morph when text is cleared: 150ms with the Android
/// `ValueAnimator` default accelerate-decelerate (no interpolator set,
/// CAEV:8604).
const Duration kRecordSendMorphReverseDuration = Duration(milliseconds: 150);

/// Scale of the outgoing icon in the mic <-> send morph:
/// `ObjectAnimator.ofFloat(..., View.SCALE_X, 0.1f)` with alpha to 0
/// (CAEV:8153-8155).
const double kRecordSendMorphMinScale = 0.1;

/// RecordCircle base radius: `circleRadius = dpf2(41)` (CAEV:1960).
const double kRecordCircleRadius = 41.0;

/// Amplitude radius gain: `circleRadiusAmplitude = dp(30)` (CAEV:1961) —
/// full radius `circleRadius + 30dp * amplitude` (CAEV:2182).
const double kRecordCircleAmplitudeRadius = 30.0;

/// RecordCircle enter: scale 0 -> 1 over 300ms (CAEV:8925-8927), set-level
/// `DecelerateInterpolator` (CAEV:8961).
const Duration kRecordCircleEnterDuration = Duration(milliseconds: 300);

/// Bar-icon legs of the record enter/exit sets: 150ms
/// (`iconChanges.setDuration(150)` CAEV:8923-8925;
/// `iconsAnimator.setDuration(150)` CAEV:9593).
const Duration kRecordSendIconsDuration = Duration(milliseconds: 150);

/// Delay before the bar icons return on release:
/// `iconsAnimator.setStartDelay(200)` (CAEV:9594).
const Duration kRecordSendIconsReturnDelay = Duration(milliseconds: 200);

/// RecordCircle exit: `exitTransition` 0 -> 1 over 360ms (220ms when the
/// message send transition runs — not modeled here) (CAEV:9605-9606).
const Duration kRecordCircleExitDuration = Duration(milliseconds: 360);

/// Exit geometry radius bump: `radius + dp(16) * progressToSeekbarStep1`
/// before the shrink (CAEV:2214-2216).
const double kRecordCircleExitRadiusGain = 16.0;

/// RecordCircle center, from the right edge: `cx = width - dp2(26)`
/// (CAEV:2139; `dp2` floors — identical to 26.0 at 1:1 logical px).
const double kRecordCircleCenterFromRight = 26.0;

/// RecordCircle center, above the layout bottom: `cy = dp(170)` in the
/// 194dp-tall view = 24dp above its bottom (CAEV:2118-2140). Both offsets
/// are mapped into the 44dp button box, whose bottom-right corner rests at
/// the input bar's bottom-right in the Java layout.
const double kRecordCircleCenterFromBottom = 24.0;

/// Icon box inside the record circle: `cx ± dp(12)` (CAEV:2249-2252).
const double kRecordCircleIconSize = 24.0;

/// Amplitude smoothing: the drawn amplitude moves linearly toward the target
/// over `100 + 500 * 0.55 = 375`ms (CAEV:2025-2030, 2161-2175;
/// WaveDrawable.java:31, 45).
const Duration kRecordAmplitudeSmoothing = Duration(milliseconds: 375);

/// Tiny wave blob radius range: `minRadius = dp(47)`, `maxRadius = dp(47) +
/// dp(15) * FORM_SMALL_MAX(0.6)` (CAEV:2269-2274; BlobDrawable.java:19-28).
const double kRecordWaveTinyMinRadius = 47.0;

/// See [kRecordWaveTinyMinRadius].
const double kRecordWaveTinyMaxRadius = 47.0 + 15.0 * 0.6;

/// Big wave blob radius range: `minRadius = dp(50)`, `maxRadius = dp(50) +
/// dp(12) * FORM_BIG_MAX(0.6)` (CAEV:2269-2274; BlobDrawable.java:19-28).
const double kRecordWaveBigMinRadius = 50.0;

/// See [kRecordWaveBigMinRadius].
const double kRecordWaveBigMaxRadius = 50.0 + 12.0 * 0.6;

/// Big wave alpha over `chat_messagePanelVoiceBackground`:
/// `WaveDrawable.CIRCLE_ALPHA_1 = 0.30` (CAEV:2448-2450;
/// WaveDrawable.java:32).
const double kRecordWaveBigAlpha = 0.30;

/// Tiny wave alpha: `WaveDrawable.CIRCLE_ALPHA_2 = 0.15` (CAEV:2448-2450;
/// WaveDrawable.java:33).
const double kRecordWaveTinyAlpha = 0.15;

/// Big wave draw-scale floor: `BlobDrawable.SCALE_BIG_MIN = 0.878`; scale =
/// `min + 1.4 * amplitude` (CAEV:2295-2306; BlobDrawable.java:19-28).
const double kRecordWaveBigScaleMin = 0.878;

/// Tiny wave draw-scale floor: `BlobDrawable.SCALE_SMALL_MIN = 0.926`
/// (CAEV:2295-2306; BlobDrawable.java:19-28).
const double kRecordWaveTinyScaleMin = 0.926;

/// Waves enter ramp: `wavesEnterAnimation += 0.04f` per frame
/// (CAEV:2288-2295) — 25 frames at the assumed 60fps ≈ 416.7ms, with
/// EASE_OUT applied at draw time.
const Duration kRecordWavesEnterDuration = Duration(microseconds: 416667);

/// The manual overshoot mapping of the RecordCircle enter `scale`
/// (CAEV:2152-2160):
///
///  * `scale <= 0.5`  -> `scale / 0.5` (0 -> 1);
///  * `scale <= 0.75` -> `1 - (scale - 0.5) / 0.25 * 0.1` (dips to 0.9);
///  * otherwise       -> `0.9 + (scale - 0.75) / 0.25 * 0.1` (back to 1.0).
///
/// This is the Java replacement for a physics spring: the 300ms
/// DecelerateInterpolator drive overshoots through this piecewise map, so no
/// `SpringDescription` is involved in the port either.
double recordCircleScaleFor(double scale) {
  if (scale <= 0.5) {
    return scale / 0.5;
  }
  if (scale <= 0.75) {
    return 1.0 - (scale - 0.5) / 0.25 * 0.1;
  }
  return 0.9 + (scale - 0.75) / 0.25 * 0.1;
}

/// Android's `AccelerateDecelerateInterpolator` — `cos((t + 1) * PI) / 2 +
/// 0.5` — the `ValueAnimator` default used where the Java sets no explicit
/// interpolator: the reverse send morph (CAEV:8604) and `exitTransition`
/// (CAEV:9605-9606).
class _AccelerateDecelerateCurve extends Curve {
  const _AccelerateDecelerateCurve();

  @override
  double transformInternal(double t) => math.cos((t + 1) * math.pi) / 2.0 + 0.5;
}

const Curve _accelerateDecelerate = _AccelerateDecelerateCurve();

/// `CubicBezierInterpolator.EASE_BOTH = (0.42, 0, 0.58, 1)`
/// (CubicBezierInterpolator.java:14), used by the exit-geometry steps
/// (CAEV:2204-2216).
const Cubic _easeBoth = Cubic(0.42, 0.0, 0.58, 1.0);

/// The mic / video / send button (`audioVideoButtonContainer`,
/// CAEV:2933-3209) with the expanding `RecordCircle` (CAEV:1945-2555).
///
/// A 44x44dp box ([kRecordSendButtonSize]) that:
///
///  * paints the 38x38dp round-rect send area (radius 19dp, margin 3dp, fill
///    `chat_messagePanelSend`, CAEV:3188-3203) with the current 24dp icon
///    over it;
///  * on tap toggles [RecordMode.voice] <-> [RecordMode.video], reporting
///    the new mode through [onModeChanged] with a KEYBOARD_TAP haptic
///    (CAEV:3063-3073) and cross-morphing the icon (the `voice_and_video`
///    lottie substitution, AIV:63-69);
///  * on hold (150ms, [kRecordSendHoldDelay]) arms a recording: fires
///    [onRecordStart] with the active mode, fades the bar content out
///    (150ms) and expands the record circle (300ms decelerate with the
///    manual overshoot [recordCircleScaleFor], fill
///    `chat_messagePanelVoiceBackground`, amplitude waves in voice mode);
///    releasing fires [onRecordEnd] and plays the 360ms exit
///    (CAEV:2204-2221, 9535-9619). When [hasVideo] is false the recording
///    arms directly at pointer-down (CAEV:3018);
///  * while [hasText] is true morphs to the send plane — outgoing icon to
///    scale 0.1 + fade over 220ms EASE_OUT_QUINT, back in 150ms
///    (CAEV:8153-8189, 8604) — and taps fire [onSend].
///
/// Recording capture is *not* implemented: [amplitude] is a callback slot
/// for the normalized mic amplitude (Java feeds `min(1800, raw) / 1800`,
/// CAEV:2025-2030), smoothed internally over 375ms as in `WaveDrawable`.
///
/// Like every component in this package, takes an optional [resources]
/// override that wins over the ambient theme (the Java `resourcesProvider`
/// convention).
class RecordSendButton extends StatefulWidget {
  /// Creates the button.
  const RecordSendButton({
    super.key,
    this.mode = RecordMode.voice,
    this.hasText = false,
    this.hasVideo = true,
    this.onSend,
    this.onRecordStart,
    this.onRecordEnd,
    this.onModeChanged,
    this.amplitude,
    this.micIcon,
    this.videoIcon,
    this.sendIcon,
    this.iconColor,
    this.resources,
  });

  /// The externally supplied recording mode (Java persists it in prefs,
  /// CAEV:6112-6120). Adopted on build and whenever it changes; taps toggle
  /// an internal copy and report through [onModeChanged] without requiring
  /// the owner to write it back. Coerced to [RecordMode.voice] while
  /// [hasVideo] is false.
  final RecordMode mode;

  /// Whether the message field has text: morphs the button into the send
  /// plane (CAEV:8153-8189) and routes taps to [onSend].
  final bool hasText;

  /// The Java `hasRecordVideo` flag: enables the voice <-> video tap toggle
  /// and the 150ms hold delay; when false, pointer-down starts an audio
  /// recording immediately (CAEV:3013-3018).
  final bool hasVideo;

  /// Tap callback in the send state.
  final VoidCallback? onSend;

  /// A recording was armed (the `recordAudioVideoRunnable` fired,
  /// CAEV:895-956), with the mode it started in.
  final ValueChanged<RecordMode>? onRecordStart;

  /// The pointer was released (or cancelled) while recording — the
  /// release-to-send path (CAEV:3074-3121). Slide-to-cancel and lock belong
  /// to the record overlay, not this button.
  final VoidCallback? onRecordEnd;

  /// The tap toggle changed the mode (`onSwitchRecordMode`, CAEV:3066-3069).
  final ValueChanged<RecordMode>? onModeChanged;

  /// Callback slot for the normalized mic amplitude in 0..1 (Java:
  /// `min(1800, rawValue) / 1800`, CAEV:2025-2030). Values are clamped and
  /// smoothed over [kRecordAmplitudeSmoothing]; never read outside the
  /// recording state.
  final ValueListenable<double>? amplitude;

  /// Mic icon override (the `voice_and_video` lottie voice pose / the
  /// `input_mic_pressed` drawable inside the circle, CAEV:2005-2016). The
  /// default is a simple built-in glyph tinted by the ambient [IconTheme].
  final Widget? micIcon;

  /// Video icon override (video pose / `input_video_pressed`).
  final Widget? videoIcon;

  /// Send icon override (`send_plane_24`, CAEV:3435).
  final Widget? sendIcon;

  /// Bar icon tint; defaults to white — the fill of the `voice_and_video` /
  /// `send_plane_24` assets drawn over the `chat_messagePanelSend` circle.
  final Color? iconColor;

  /// Per-surface palette override; defaults to the ambient
  /// [TelegramTheme] resolution.
  final TelegramResources? resources;

  @override
  RecordSendButtonState createState() => RecordSendButtonState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<RecordMode>('mode', mode, defaultValue: RecordMode.voice))
      ..add(FlagProperty('hasText', value: hasText, ifTrue: 'send state'))
      ..add(FlagProperty('hasVideo', value: hasVideo, defaultValue: true, ifFalse: 'audio only'))
      ..add(ObjectFlagProperty<VoidCallback>.has('onSend', onSend))
      ..add(ObjectFlagProperty<ValueChanged<RecordMode>>.has('onRecordStart', onRecordStart))
      ..add(ObjectFlagProperty<VoidCallback>.has('onRecordEnd', onRecordEnd))
      ..add(ObjectFlagProperty<ValueChanged<RecordMode>>.has('onModeChanged', onModeChanged))
      ..add(ColorProperty('iconColor', iconColor, defaultValue: null));
  }
}

/// Record-circle geometry snapshot: the Java draw-pass math of
/// CAEV:2176-2221 with the slide factors at rest.
class _CircleGeometry {
  const _CircleGeometry(this.radius, this.alpha, this.exitStep2);

  final double radius;
  final double alpha;
  final double exitStep2;
}

/// State of [RecordSendButton]; public for test access to [visualState] and
/// the animation value getters.
class RecordSendButtonState extends State<RecordSendButton> with TickerProviderStateMixin {
  /// Send morph factor: 0 = mic/video icon, 1 = send plane (CAEV:8153-8189).
  late final AnimationController _send;

  /// Mode swap factor: 0 = voice icon, 1 = video icon (AIV:63-69).
  late final AnimationController _modeSwap;

  /// The RecordCircle `scale` field: enter 0 -> 1 over 300ms decelerate
  /// (CAEV:8925-8961), rendered through [recordCircleScaleFor].
  late final AnimationController _enter;

  /// The RecordCircle `exitTransition` field: 0 -> 1 over 360ms
  /// (CAEV:9605-9606, geometry CAEV:2204-2221).
  late final AnimationController _exit;

  /// Bar content visibility driver: 0 = shown, 1 = hidden (the
  /// `audioVideoButtonContainer` ALPHA legs of the record sets,
  /// CAEV:8831-8963, 9535-9619).
  late final AnimationController _barIcons;

  /// `wavesEnterAnimation` (CAEV:2288-2295), linear; EASE_OUT applied at
  /// draw time.
  late final AnimationController _wavesEnter;

  /// Amplitude smoothing clock: one linear 375ms sweep per retarget
  /// (CAEV:2025-2030).
  late final AnimationController _amp;

  late final Listenable _repaint;

  RecordMode _mode = RecordMode.voice;
  bool _recording = false;
  bool _showWaves = false;
  bool _disposed = false;

  Timer? _holdTimer;
  Timer? _iconsReturnTimer;

  double _ampFrom = 0.0;
  double _ampTo = 0.0;

  @override
  void initState() {
    super.initState();
    _mode = widget.hasVideo ? widget.mode : RecordMode.voice;
    _send = AnimationController(vsync: this, value: widget.hasText ? 1.0 : 0.0, duration: kRecordSendMorphDuration);
    _modeSwap = AnimationController(
      vsync: this,
      value: _mode == RecordMode.video ? 1.0 : 0.0,
      duration: kRecordSendModeSwitchDuration,
    );
    _enter = AnimationController(vsync: this, duration: kRecordCircleEnterDuration);
    _exit = AnimationController(vsync: this, duration: kRecordCircleExitDuration);
    _barIcons = AnimationController(vsync: this, duration: kRecordSendIconsDuration);
    _wavesEnter = AnimationController(vsync: this, duration: kRecordWavesEnterDuration);
    _amp = AnimationController(vsync: this, value: 1.0, duration: kRecordAmplitudeSmoothing);
    _repaint = Listenable.merge(<Listenable>[_send, _modeSwap, _enter, _exit, _barIcons, _wavesEnter, _amp]);
    widget.amplitude?.addListener(_onAmplitudeChanged);
  }

  @override
  void didUpdateWidget(RecordSendButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.amplitude, oldWidget.amplitude)) {
      oldWidget.amplitude?.removeListener(_onAmplitudeChanged);
      widget.amplitude?.addListener(_onAmplitudeChanged);
      _onAmplitudeChanged();
    }
    if (widget.hasText != oldWidget.hasText) {
      _cancelHold();
      if (widget.hasText) {
        // checkSendButton show: 220ms EASE_OUT_QUINT (CAEV:8187-8189).
        _send.animateTo(1.0, duration: kRecordSendMorphDuration, curve: TgCurves.easeOutQuint);
      } else {
        // Text cleared: 150ms, ValueAnimator default interpolator (CAEV:8604).
        _send.animateTo(0.0, duration: kRecordSendMorphReverseDuration, curve: _accelerateDecelerate);
      }
    }
    final RecordMode incoming = widget.hasVideo ? widget.mode : RecordMode.voice;
    final RecordMode previous = oldWidget.hasVideo ? oldWidget.mode : RecordMode.voice;
    if (incoming != previous && incoming != _mode) {
      // The owner drove the mode (the prefs restore path, CAEV:6112-6120).
      _applyMode(incoming, animated: true);
    } else if (!widget.hasVideo && _mode == RecordMode.video) {
      _applyMode(RecordMode.voice, animated: true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.amplitude?.removeListener(_onAmplitudeChanged);
    _cancelHold();
    _iconsReturnTimer?.cancel();
    _iconsReturnTimer = null;
    _send.dispose();
    _modeSwap.dispose();
    _enter.dispose();
    _exit.dispose();
    _barIcons.dispose();
    _wavesEnter.dispose();
    _amp.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- state

  /// The current visible state.
  RecordSendState get visualState {
    if (_recording) {
      return RecordSendState.recording;
    }
    if (widget.hasText) {
      return RecordSendState.send;
    }
    return _mode == RecordMode.video ? RecordSendState.video : RecordSendState.mic;
  }

  /// The effective recording mode (tap toggles included).
  RecordMode get mode => _mode;

  /// Whether a recording is armed.
  bool get isRecording => _recording;

  /// Send morph factor in 0..1 (already curved; 0 = mic/video, 1 = send).
  @visibleForTesting
  double get debugSendMorphFactor => _send.value;

  /// Outgoing mic/video icon scale: `lerp(1, 0.1, morph)` (CAEV:8153-8155).
  @visibleForTesting
  double get debugMicVideoScale => lerpDouble(1.0, kRecordSendMorphMinScale, _send.value)!;

  /// Outgoing mic/video icon alpha: `1 - morph` (CAEV:8155).
  @visibleForTesting
  double get debugMicVideoAlpha => 1.0 - _send.value;

  /// Incoming send icon scale: `lerp(0.1, 1, morph)`.
  @visibleForTesting
  double get debugSendScale => lerpDouble(kRecordSendMorphMinScale, 1.0, _send.value)!;

  /// Incoming send icon alpha: `morph`.
  @visibleForTesting
  double get debugSendAlpha => _send.value;

  /// Mode swap factor in 0..1 (0 = voice icon, 1 = video icon).
  @visibleForTesting
  double get debugModeSwapFactor => _modeSwap.value;

  /// The raw RecordCircle enter factor (the Java `scale` field).
  @visibleForTesting
  double get debugRecordCircleEnterFactor => _enter.value;

  /// The drawn circle scale: [recordCircleScaleFor] of the enter factor
  /// (CAEV:2152-2160).
  @visibleForTesting
  double get debugRecordCircleScale => recordCircleScaleFor(_enter.value);

  /// The drawn circle radius, amplitude and exit geometry included
  /// (CAEV:2176-2221).
  @visibleForTesting
  double get debugRecordCircleRadius => _circleGeometry().radius;

  /// The drawn circle alpha (fades over exit 0.6..1.0, CAEV:2217-2220).
  @visibleForTesting
  double get debugRecordCircleAlpha => _circleGeometry().alpha;

  /// Bar content hide factor (0 shown .. 1 hidden).
  @visibleForTesting
  double get debugBarIconsFactor => _barIcons.value;

  // -------------------------------------------------------------- gestures

  bool get _holdPending => _holdTimer?.isActive ?? false;

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  /// ACTION_DOWN (CAEV:3013-3018): schedule `recordAudioVideoRunnable` with
  /// a 150ms delay when video recording exists, else run it immediately.
  void _handlePointerDown(PointerDownEvent event) {
    if (widget.hasText || _recording) {
      return;
    }
    if (widget.hasVideo) {
      _holdTimer = Timer(kRecordSendHoldDelay, _startRecording);
    } else {
      _startRecording();
    }
  }

  /// ACTION_UP (CAEV:3063-3121): before the runnable fires it is a tap —
  /// cancel and toggle the mode; while recording it is release-to-send.
  void _handlePointerUp(PointerUpEvent event) {
    if (widget.hasText) {
      return; // The GestureDetector tap handles the send state.
    }
    if (_holdPending) {
      _cancelHold();
      _toggleMode();
    } else if (_recording) {
      _stopRecording();
    }
  }

  /// Pointer cancel: drop a pending hold quietly; while recording, end the
  /// recording (the Java ACTION_CANCEL path locks instead, CAEV:3036-3041 —
  /// the lock belongs to the record overlay, not this button).
  void _handlePointerCancel(PointerCancelEvent event) {
    _cancelHold();
    if (_recording) {
      _stopRecording();
    }
  }

  /// The tap toggle (CAEV:3063-3073): `onSwitchRecordMode(!isInVideoMode)` +
  /// `setRecordVideoButtonVisible` + KEYBOARD_TAP haptic.
  void _toggleMode() {
    if (!widget.hasVideo) {
      return;
    }
    // performHapticFeedback(KEYBOARD_TAP) (CAEV:3070): Flutter's mediumImpact
    // maps to HapticFeedbackConstants.KEYBOARD_TAP on Android.
    HapticFeedback.mediumImpact();
    final RecordMode next = _mode == RecordMode.voice ? RecordMode.video : RecordMode.voice;
    _applyMode(next, animated: true);
    widget.onModeChanged?.call(next);
  }

  void _applyMode(RecordMode next, {required bool animated}) {
    if (_mode == next) {
      return;
    }
    setState(() => _mode = next);
    final double target = next == RecordMode.video ? 1.0 : 0.0;
    if (animated) {
      // The lottie frames advance linearly (AIV:63-76).
      _modeSwap.animateTo(target, duration: kRecordSendModeSwitchDuration);
    } else {
      _modeSwap.value = target;
    }
  }

  /// `recordAudioVideoRunnable` (CAEV:895-956): flags recording, runs the
  /// RECORD_STATE_ENTER set (icons 150ms, circle 300ms, DecelerateInterpolator,
  /// CAEV:8831-8963), waves for audio only (`showWaves(true/false)`).
  void _startRecording() {
    _holdTimer = null;
    if (_recording || widget.hasText) {
      return;
    }
    setState(() => _recording = true);
    _iconsReturnTimer?.cancel();
    _iconsReturnTimer = null;
    _exit.stop();
    _exit.value = 0.0;
    _enter.animateTo(1.0, duration: kRecordCircleEnterDuration, curve: TgCurves.decelerate);
    _barIcons.animateTo(1.0, duration: kRecordSendIconsDuration, curve: TgCurves.decelerate);
    _showWaves = _mode == RecordMode.voice;
    if (_showWaves) {
      _wavesEnter.forward(from: 0.0);
    } else {
      _wavesEnter.value = 0.0;
    }
    // Seed the amplitude smoother at the slot's current value.
    _ampFrom = _ampTo = ((widget.amplitude?.value ?? 0.0)).clamp(0.0, 1.0);
    _amp.value = 1.0;
    widget.onRecordStart?.call(_mode);
  }

  /// Release: RECORD_STATE_SENDING (CAEV:9535-9619) — `exitTransition` to 1
  /// over 360ms, bar icons back over 150ms after a 200ms delay.
  void _stopRecording() {
    if (!_recording) {
      return;
    }
    setState(() => _recording = false);
    widget.onRecordEnd?.call();
    _exit.animateTo(1.0, duration: kRecordCircleExitDuration, curve: _accelerateDecelerate).then((void _) {
      // The primary TickerFuture only completes on a natural finish, so a
      // re-arm or dispose mid-exit never reaches this reset.
      if (_disposed || _recording) {
        return;
      }
      _enter.value = 0.0;
      _exit.value = 0.0;
    });
    _iconsReturnTimer = Timer(kRecordSendIconsReturnDelay, () {
      _iconsReturnTimer = null;
      _barIcons.animateTo(0.0, duration: kRecordSendIconsDuration, curve: _accelerateDecelerate);
    });
  }

  // ------------------------------------------------------------- amplitude

  double get _amplitudeValue => lerpDouble(_ampFrom, _ampTo, _amp.value)!;

  void _onAmplitudeChanged() {
    final double target = (widget.amplitude?.value ?? 0.0).clamp(0.0, 1.0);
    if (target == _ampTo) {
      return;
    }
    _ampFrom = _amplitudeValue;
    _ampTo = target;
    _amp.forward(from: 0.0);
  }

  // -------------------------------------------------------------- geometry

  /// The draw-pass radius/alpha math (CAEV:2176-2221) with the slide-to-
  /// cancel factors at rest (the slide gesture lives in the record overlay).
  _CircleGeometry _circleGeometry() {
    final double sc = recordCircleScaleFor(_enter.value);
    double radius = (kRecordCircleRadius + kRecordCircleAmplitudeRadius * _amplitudeValue) * sc;
    double alpha = 1.0;
    double exitStep2 = 0.0;
    final double exit = _exit.value;
    if (exit != 0.0) {
      // step1Time = 0.6, step2Time = 0.4, both EASE_BOTH (CAEV:2204-2216).
      final double exitStep1 = _easeBoth.transform(math.min(1.0, exit / 0.6));
      exitStep2 = _easeBoth.transform(math.max(0.0, (exit - 0.6) / 0.4));
      radius = (radius + kRecordCircleExitRadiusGain * exitStep1) * (1.0 - exitStep2);
      if (exit > 0.6) {
        alpha = math.max(0.0, 1.0 - (exit - 0.6) / 0.4);
      }
    }
    return _CircleGeometry(radius, alpha, exitStep2);
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    return resources != null ? resources.getColor(key) : TelegramTheme.colorOf(context, key);
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final Color sendFill = _color(context, TelegramColorKey.chat_messagePanelSend);
    final Color voiceBackground = _color(context, TelegramColorKey.chat_messagePanelVoiceBackground);
    final Color voicePressed = _color(context, TelegramColorKey.chat_messagePanelVoicePressed);
    final Color iconColor = widget.iconColor ?? const Color(0xFFFFFFFF);
    return Semantics(
      container: true,
      button: true,
      child: Listener(
        onPointerDown: _handlePointerDown,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.hasText ? widget.onSend : null,
          child: SizedBox(
            width: kRecordSendButtonSize,
            height: kRecordSendButtonSize,
            child: AnimatedBuilder(
              animation: _repaint,
              builder: (BuildContext context, Widget? child) {
                final _CircleGeometry circle = _circleGeometry();
                final double barVisibility = (1.0 - _barIcons.value).clamp(0.0, 1.0);
                // Java: s = scale * enterEased * (SCALE_MIN + 1.4 * amp),
                // gated by exitProgress2 < 0.4 (CAEV:2288-2306).
                final double waveBase = _showWaves && circle.exitStep2 < 0.4
                    ? _enter.value * TgCurves.easeOut.transform(_wavesEnter.value)
                    : 0.0;
                final double circleIconAlpha = (_enter.value.clamp(0.0, 1.0) * circle.alpha).clamp(0.0, 1.0);
                return Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RecordSendPainter(
                          sendFill: sendFill,
                          barAlpha: barVisibility,
                          circleColor: voiceBackground,
                          circleRadius: circle.radius,
                          circleAlpha: _enter.value > 0.0 ? circle.alpha : 0.0,
                          waveBase: waveBase,
                          amplitude: _amplitudeValue,
                        ),
                      ),
                    ),
                    if (barVisibility > 0.0)
                      Positioned.fill(
                        child: Opacity(
                          opacity: barVisibility,
                          child: Padding(
                            padding: const EdgeInsets.all(kRecordSendIconPadding),
                            child: _buildBarIconCluster(iconColor),
                          ),
                        ),
                      ),
                    // input_mic_pressed / input_video_pressed tinted
                    // chat_messagePanelVoicePressed, cx ± 12dp (CAEV:2005-2016,
                    // 2249-2252).
                    if (circleIconAlpha > 0.0)
                      Positioned(
                        right: kRecordCircleCenterFromRight - kRecordCircleIconSize / 2,
                        bottom: kRecordCircleCenterFromBottom - kRecordCircleIconSize / 2,
                        width: kRecordCircleIconSize,
                        height: kRecordCircleIconSize,
                        child: Opacity(
                          opacity: circleIconAlpha,
                          child: IconTheme.merge(
                            data: IconThemeData(color: voicePressed, size: kRecordCircleIconSize),
                            child: Center(
                              child: _mode == RecordMode.video
                                  ? (widget.videoIcon ?? const _Glyph(_GlyphKind.video))
                                  : (widget.micIcon ?? const _Glyph(_GlyphKind.mic)),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// The bar icon layers: the voice <-> video cross-morph nested inside the
  /// mic <-> send morph. Both reuse the Java cross-scale/fade pattern of
  /// `drawIconInternal` (CAEV:2404-2431) as the lottie substitution.
  Widget _buildBarIconCluster(Color iconColor) {
    final double sendFactor = _send.value;
    final double swapFactor = _modeSwap.value;
    final Widget micVideo = Stack(
      alignment: Alignment.center,
      children: <Widget>[
        _scaledFaded(widget.micIcon ?? const _Glyph(_GlyphKind.mic), scale: 1.0 - swapFactor, alpha: 1.0 - swapFactor),
        _scaledFaded(widget.videoIcon ?? const _Glyph(_GlyphKind.video), scale: swapFactor, alpha: swapFactor),
      ],
    );
    return IconTheme.merge(
      data: IconThemeData(color: iconColor, size: kRecordSendIconSize),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          _scaledFaded(
            micVideo,
            scale: lerpDouble(1.0, kRecordSendMorphMinScale, sendFactor)!,
            alpha: 1.0 - sendFactor,
          ),
          _scaledFaded(
            widget.sendIcon ?? const _Glyph(_GlyphKind.send),
            scale: lerpDouble(kRecordSendMorphMinScale, 1.0, sendFactor)!,
            alpha: sendFactor,
          ),
        ],
      ),
    );
  }

  static Widget _scaledFaded(Widget child, {required double scale, required double alpha}) {
    return Opacity(
      opacity: alpha.clamp(0.0, 1.0),
      child: Transform.scale(scale: scale, child: child),
    );
  }
}

/// Paints, in Java draw order: the 38dp send-area round rect
/// (`dispatchDraw`, CAEV:3182-3203), the amplitude waves (CAEV:2288-2306,
/// simplified to plain circles — `BlobDrawable`'s randomized wobble is not
/// reproduced) and the record circle itself (CAEV:2176-2231).
class _RecordSendPainter extends CustomPainter {
  const _RecordSendPainter({
    required this.sendFill,
    required this.barAlpha,
    required this.circleColor,
    required this.circleRadius,
    required this.circleAlpha,
    required this.waveBase,
    required this.amplitude,
  });

  final Color sendFill;
  final double barAlpha;
  final Color circleColor;
  final double circleRadius;
  final double circleAlpha;
  final double waveBase;
  final double amplitude;

  @override
  void paint(Canvas canvas, Size size) {
    if (barAlpha > 0.0) {
      final Rect rect = Rect.fromLTWH(
        size.width - kRecordSendCircleSize - kRecordSendCircleMargin,
        size.height - kRecordSendCircleSize - kRecordSendCircleMargin,
        kRecordSendCircleSize,
        kRecordSendCircleSize,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(kRecordSendCircleRadius)),
        Paint()..color = sendFill.withValues(alpha: sendFill.a * barAlpha),
      );
    }
    final Offset center = Offset(
      size.width - kRecordCircleCenterFromRight,
      size.height - kRecordCircleCenterFromBottom,
    );
    if (waveBase > 0.0) {
      // setAlphaComponent(voiceBackground, 255 * alpha) *replaces* the alpha
      // channel (CAEV:2448-2450).
      final double bigRadius = lerpDouble(kRecordWaveBigMinRadius, kRecordWaveBigMaxRadius, amplitude)!;
      canvas.drawCircle(
        center,
        bigRadius * waveBase * (kRecordWaveBigScaleMin + 1.4 * amplitude),
        Paint()..color = circleColor.withValues(alpha: kRecordWaveBigAlpha),
      );
      final double tinyRadius = lerpDouble(kRecordWaveTinyMinRadius, kRecordWaveTinyMaxRadius, amplitude)!;
      canvas.drawCircle(
        center,
        tinyRadius * waveBase * (kRecordWaveTinyScaleMin + 1.4 * amplitude),
        Paint()..color = circleColor.withValues(alpha: kRecordWaveTinyAlpha),
      );
    }
    if (circleRadius > 0.0 && circleAlpha > 0.0) {
      canvas.drawCircle(
        center,
        circleRadius,
        Paint()..color = circleColor.withValues(alpha: circleColor.a * circleAlpha),
      );
    }
  }

  @override
  bool shouldRepaint(_RecordSendPainter oldDelegate) {
    return sendFill != oldDelegate.sendFill ||
        barAlpha != oldDelegate.barAlpha ||
        circleColor != oldDelegate.circleColor ||
        circleRadius != oldDelegate.circleRadius ||
        circleAlpha != oldDelegate.circleAlpha ||
        waveBase != oldDelegate.waveBase ||
        amplitude != oldDelegate.amplitude;
  }
}

enum _GlyphKind { mic, video, send }

/// Built-in fallback glyphs standing in for the Android assets
/// (`voice_and_video` lottie poses, `input_mic_pressed` /
/// `input_video_pressed`, `send_plane_24`): simple 24dp vector shapes tinted
/// by the ambient [IconTheme]. Apps supply real assets through
/// [RecordSendButton.micIcon] / [RecordSendButton.videoIcon] /
/// [RecordSendButton.sendIcon].
class _Glyph extends StatelessWidget {
  const _Glyph(this.kind);

  final _GlyphKind kind;

  @override
  Widget build(BuildContext context) {
    final Color color = IconTheme.of(context).color ?? const Color(0xFFFFFFFF);
    return CustomPaint(
      size: const Size.square(kRecordSendIconSize),
      painter: _GlyphPainter(kind, color),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.kind, this.color);

  final _GlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = color;
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    switch (kind) {
      case _GlyphKind.mic:
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTRB(9.0, 3.0, 15.0, 14.0), const Radius.circular(3.0)),
          fill,
        );
        canvas.drawArc(Rect.fromCircle(center: const Offset(12.0, 11.5), radius: 5.5), 0.0, math.pi, false, stroke);
        canvas.drawLine(const Offset(12.0, 17.0), const Offset(12.0, 20.0), stroke);
      case _GlyphKind.video:
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTRB(2.5, 7.0, 15.0, 17.0), const Radius.circular(2.5)),
          fill,
        );
        final Path lens = Path()
          ..moveTo(15.0, 10.2)
          ..lineTo(20.5, 7.0)
          ..lineTo(20.5, 17.0)
          ..lineTo(15.0, 13.8)
          ..close();
        canvas.drawPath(lens, fill);
      case _GlyphKind.send:
        final Path plane = Path()
          ..moveTo(3.0, 20.5)
          ..lineTo(21.0, 12.0)
          ..lineTo(3.0, 3.5)
          ..lineTo(3.0, 10.0)
          ..lineTo(14.5, 12.0)
          ..lineTo(3.0, 14.0)
          ..close();
        canvas.drawPath(plane, fill);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) => kind != oldDelegate.kind || color != oldDelegate.color;
}
