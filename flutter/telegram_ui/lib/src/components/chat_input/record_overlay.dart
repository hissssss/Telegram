// The record overlay — the recording chrome shown while a voice/video note
// records, ported from `java/org/telegram/ui/Components/ChatActivityEnterView.java`
// (**CAEV**) and `java/org/telegram/ui/Components/InstantCameraView.java`
// (**ICV**), per flutter/docs/spec_chat_input.md sections 4-5:
//
//  * the record panel row (full width x 44dp, CAEV:9677-9703) with the
//    blinking `RecordDot` (CAEV:961-1067), the `TimerView` duration text
//    (CAEV:14147-14354) and the `SlideTextView` slide-to-cancel hint
//    (CAEV:13871-14145);
//  * the slide-to-cancel gesture math — cancel distance 35% of width capped
//    140dp (CAEV:3135-3141), `slideProgress = clamp(1 + dx/dist, 0, 1)`
//    (CAEV:3143-3157), reaching 0 cancels immediately (CAEV:3158-3169),
//    releasing below 0.45 cancels (CAEV:3048-3062);
//  * the lock affordance — drag up 57dp to lock (`setLockTranslation`,
//    CAEV:2094-2114), the 36dp-wide glass pill morphing into a pause button
//    (`ControlsView`, CAEV:1162-1875) with the `startLockTransition` snap
//    (CAEV:4607-4630);
//  * the round-video preview slot — a circular-masked widget slot with the
//    white 3dp progress ring of `InstantCameraView` (ICV:284-287, 612-629;
//    diameter AndroidUtilities.java:2800-2810, cited as **AU**).
//
// Pure presentation: everything is driven by a [RecordOverlayController]
// ({elapsed, dragOffset, locked, mode}) owned by whoever runs the record
// gesture (the `RecordSendButton` host). No gesture recognizers for the drag
// live here, and the camera pipeline is a **callback slot** —
// [RecordOverlay.videoPreview] receives an externally built frame widget;
// no capture is ever implemented in this package.
//
// Out of scope (owner / future work, documented per spec section 4): the
// enter/exit record-interface animator sets of `updateRecordInterface`
// (CAEV:8758-9647), the timer digit-roll (CAEV:14272-14330), the delete-dot
// lottie (CAEV:989-1008), the "Slide up to lock recording" tooltip
// (CAEV:1393-1455) and the view-once pill (CAEV:1636-1670).
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import '../../foundation/tg_curves.dart';
import '../../glass/geometry.dart';
import '../../glass/glass_panel.dart';
import '../../glass/surface_colors.dart';
import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';
import 'record_send_button.dart' show RecordMode;

// --------------------------------------------------------------- record panel

/// Height of the record panel overlay row: `createFrame(MATCH_PARENT,
/// DEFAULT_HEIGHT)` with `DEFAULT_HEIGHT` = 44dp (CAEV:9690, 6410).
const double kRecordOverlayBarHeight = 44.0;

/// Left margin of the `SlideTextView` inside the record panel: 45dp
/// (CAEV:9692).
const double kRecordSlideTextLeftMargin = 45.0;

/// Left padding of `recordTimeContainer`: `setPadding(dp(13), 0, 0, 0)`
/// (CAEV:9696).
const double kRecordTimeContainerPaddingLeft = 13.0;

/// The RecordDot slot: `createLinear(28, 28, CENTER_VERTICAL)` (CAEV:9699).
const double kRecordDotSlotSize = 28.0;

/// The red dot radius: `canvas.drawCircle(w/2, h/2, dp(5), redDotPaint)`
/// (CAEV:1055).
const double kRecordDotRadius = 5.0;

/// TimerView left margin next to the dot: 6dp (CAEV:9700).
const double kRecordTimerLeftMargin = 6.0;

/// Timer text size: `textPaint.setTextSize(dp(15))`, bold (rmedium)
/// (CAEV:14195-14196).
const double kRecordTimerFontSize = 15.0;

/// One leg of the dot pulse: alpha ramps `dt / 600` down, then up
/// (CAEV:1037-1047) — 600ms fade-out + 600ms fade-in.
const Duration kRecordDotPulseHalfDuration = Duration(milliseconds: 600);

/// Full dot pulse period: 1.2s (two [kRecordDotPulseHalfDuration] legs),
/// continuous (CAEV:1032-1049).
const Duration kRecordDotPulsePeriod = Duration(milliseconds: 1200);

// ----------------------------------------------------------- slide-to-cancel

/// Fraction of the layout width the cancel drag spans:
/// `distCanMove = measuredWidth * 0.35` (CAEV:3137).
const double kRecordSlideCancelWidthFraction = 0.35;

/// Cap of the cancel drag distance: `if (distCanMove > dp(140))` clamp
/// (CAEV:3138-3140).
const double kRecordSlideCancelMaxDistance = 140.0;

/// Release threshold: on ACTION_UP the recording cancels when
/// `slideProgress < 0.45` (`alpha < 0.45`, CAEV:3048-3062).
const double kRecordSlideCancelReleaseThreshold = 0.45;

/// "Slide to cancel" / CANCEL text size: 15dp (13dp on <=320dp screens — the
/// small-screen variant is not ported) (CAEV:13962-13977).
const double kRecordSlideTextFontSize = 15.0;

/// Chevron stroke width: 1.6dp round cap/join (small screens 1.0dp, not
/// ported) (CAEV:13969-13973).
const double kRecordSlideArrowStrokeWidth = 1.6;

/// Chevron extents: legs (4, -5) -> (0, 0) -> (4, 5) — a 4dp-wide,
/// 10dp-tall left-pointing arrow (CAEV:14024-14033).
const double kRecordSlideArrowWidth = 4.0;

/// See [kRecordSlideArrowWidth].
const double kRecordSlideArrowHeight = 10.0;

/// The arrow is drawn 10dp left of the text (small screens 7dp, not ported)
/// (CAEV:14086-14091).
const double kRecordSlideArrowGap = 10.0;

/// Idle bob amplitude: `xOffset` ping-pongs between 0 and 6dp
/// (CAEV:14055-14071).
const double kRecordSlideArrowBobAmplitude = 6.0;

/// Idle bob period: the offset moves at 3dp per 250ms (CAEV:14060-14066) —
/// a 0 -> 6 -> 0 sweep of 12dp takes 1s.
const Duration kRecordSlideArrowBobPeriod = Duration(seconds: 1);

/// The bob only runs while `slideProgress > 0.8` (CAEV:14057).
const double kRecordSlideArrowBobGate = 0.8;

/// The horizontal centering bias of the slide text: `+5dp` (CAEV:14076-14080).
const double kRecordSlideTextCenterBias = 5.0;

/// CANCEL hit rect: text bounds inset `-dp(16)` (CAEV:13989).
const double kRecordCancelHitInset = 16.0;

/// The grey-text -> CANCEL morph (`cancelToProgress`) runs at the
/// SlideTextView default of 300ms (spec section 4, `startLockTransition`
/// leg CAEV:4629).
const Duration kRecordCancelMorphDuration = Duration(milliseconds: 300);

// ----------------------------------------------------------------------- lock

/// Lock trigger distance: drag up 57dp from the touch start
/// (`startTranslation - lockAnimatedTranslation >= dp(57)`, CAEV:2107).
const double kRecordLockDistance = 57.0;

/// The lock is ignored once `slideToCancelProgress < 0.7` (CAEV:2103-2105).
const double kRecordLockSlideGate = 0.7;

/// Lock pill width: `cx ± dp(18)` = 36dp, corner radius 18dp
/// (CAEV:1521-1523).
const double kRecordLockPillWidth = 36.0;

/// See [kRecordLockPillWidth].
const double kRecordLockPillRadius = 18.0;

/// Pill height at rest: `lockSize = dp(36) + dp(14) * moveProgress` with
/// `moveProgress` 1 at rest (CAEV:1521, 1385-1391).
const double kRecordLockPillRestHeight = 50.0;

/// Pill height fully dragged / locked: 36dp (CAEV:1521).
const double kRecordLockPillLockedHeight = 36.0;

/// Glass background of the pill: `BlurredBackgroundDrawable` radius 18dp,
/// `setPadding(dp(3))`, color key `chat_messagePanelVoiceLockBackground`
/// (CAEV:1683-1699).
const double kRecordLockGlassPadding = 3.0;

/// Pill center x from the right edge: `cx = width - dp2(26)` — shared with
/// the record circle (CAEV:1354, 2139; `dp2` floors, identical at 1:1).
const double kRecordLockCenterFromRight = 26.0;

/// The pill-top offset from the overlay bottom. Java: ControlsView is
/// `dp(194 + 44 + 12)` = 250dp tall, bottom-aligned (CAEV:1307-1329); the
/// pill top sits at `y = dp(60) + (viewHeight - dp(194)) - yAdd` = 116dp
/// - yAdd from its top (CAEV:1385-1386), i.e. `250 - (116 - yAdd)` =
/// **134dp + yAdd** above the overlay bottom. The pill's bottom offset is
/// therefore `134 + yAdd - lockSize` (84dp at rest).
const double kRecordLockPillTopFromBottom = 134.0;

/// Lock snap: `snapAnimationProgress` 0 -> 1 over 250ms EASE_OUT_QUINT
/// (`startLockTransition`, CAEV:4620-4624) — drives the pause-button morph.
const Duration kRecordLockSnapDuration = Duration(milliseconds: 250);

/// Lock translation return: `lockAnimatedTranslation` back to start over
/// 350ms after a 100ms delay (CAEV:4610-4617).
const Duration kRecordLockTranslateDuration = Duration(milliseconds: 350);

/// See [kRecordLockTranslateDuration].
const Duration kRecordLockTranslateDelay = Duration(milliseconds: 100);

/// Pause-bar gap of the locked pill glyph: the lock body splits into two
/// bars 3.3dp apart, radii 3dp -> 1.5dp (CAEV:1593-1612).
const double kRecordLockPauseBarGap = 3.3;

// ---------------------------------------------------------------- round video

/// Round-video circle diameter inset: `roundPlayingMessageSize =
/// min(screenW, screenH) - dp(28)` on phones (AU:2800-2810; ICV:509-526).
const double kRoundVideoDiameterInset = 28.0;

/// Short-viewport fallback factor: `roundMessageSize = min(screenW, screenH)
/// * 0.6` (AU:2800-2810).
const double kRoundVideoFallbackFactor = 0.6;

/// The fallback applies when the available height <= width * 1.3
/// (ICV:509-526).
const double kRoundVideoFallbackAspect = 1.3;

/// Progress ring rect: circle bounds inset `-dp(8)` (ICV:284-287, 612-629).
const double kRoundVideoRingInset = 8.0;

/// Progress ring stroke: 3dp, round cap, color `0xFFFFFFFF` (ICV:284-287).
const double kRoundVideoRingStrokeWidth = 3.0;

/// Recording cap: `progress = min(1, recordedTime / 60000)` (ICV:626).
const Duration kRoundVideoMaxDuration = Duration(seconds: 60);

// ------------------------------------------------------------- pure functions

/// The slide-to-cancel distance for a layout [width]:
/// `min(width * 0.35, 140dp)` (CAEV:3135-3141).
double recordSlideCancelDistance(double width) =>
    math.min(width * kRecordSlideCancelWidthFraction, kRecordSlideCancelMaxDistance);

/// `AndroidUtilities.formatTimerDurationFast` (AU:986-1001), fed
/// `time = t / 1000` seconds and `ms = (t % 1000) / 10` hundredths
/// (CAEV:14201-14202, 14218): minutes unpadded, seconds 2-digit, a comma,
/// then `ms / 10` — a **single tenths digit** (the Java appends the
/// hundredths value integer-divided by 10). Hours branch `h:mm:ss,d`.
String formatRecordTimer(Duration elapsed) {
  final int totalMs = elapsed.inMilliseconds;
  final int tenths = (totalMs % 1000) ~/ 100; // ((t % 1000) / 10) / 10.
  final int totalSeconds = totalMs ~/ 1000;
  final int seconds = totalSeconds % 60;
  final int minutes = totalSeconds ~/ 60;
  if (minutes >= 60) {
    return '${minutes ~/ 60}:${_pad2(minutes % 60)}:${_pad2(seconds)},$tenths';
  }
  return '$minutes:${_pad2(seconds)},$tenths';
}

/// `AndroidUtilities.normalizeTimePart` (AU:1003-1010).
String _pad2(int value) => value < 10 ? '0$value' : '$value';

/// The dot pulse alpha as a triangle wave of the normalized period phase
/// [t] in 0..1: starts at 1, ramps to 0 over the first half (the 600ms
/// fade-out) and back to 1 over the second (CAEV:1032-1049).
double recordDotPulseAlpha(double t) {
  final double phase = t - t.floorToDouble();
  return phase < 0.5 ? 1.0 - 2.0 * phase : 2.0 * phase - 1.0;
}

/// Lock pill height for a drag progress in 0..1 (0 = rest, 1 = fully
/// dragged/locked): `dp(36) + dp(14) * moveProgress` with
/// `moveProgress = 1 - drag` (CAEV:1385-1391, 1521).
double recordLockPillHeight(double lockDragProgress) =>
    kRecordLockPillLockedHeight +
    (kRecordLockPillRestHeight - kRecordLockPillLockedHeight) * (1.0 - lockDragProgress.clamp(0.0, 1.0));

/// Round-video preview diameter for a [viewport]:
/// `min(w, h) - 28dp`, falling back to `min(w, h) * 0.6` when the viewport
/// height <= width * 1.3 (AU:2800-2810; ICV:509-526).
double roundVideoPreviewDiameter(Size viewport) {
  final double side = math.min(viewport.width, viewport.height);
  if (viewport.height <= viewport.width * kRoundVideoFallbackAspect) {
    return side * kRoundVideoFallbackFactor;
  }
  return side - kRoundVideoDiameterInset;
}

/// Ring radius around a preview of [diameter]: the circle bounds inset
/// `-8dp` (ICV:284-287) — the arc runs along `diameter / 2 + 8`.
double roundVideoRingRadius(double diameter) => diameter / 2.0 + kRoundVideoRingInset;

/// Progress ring sweep fraction: `min(1, recordedTime / 60000)` (ICV:626).
double roundVideoProgress(Duration elapsed) => math.min(
    1.0, elapsed.inMilliseconds / kRoundVideoMaxDuration.inMilliseconds);

/// Android's `AccelerateDecelerateInterpolator` — `cos((t + 1) * PI) / 2 +
/// 0.5` — the `ValueAnimator` default where Java sets no interpolator (the
/// lock translation return, CAEV:4610-4617).
class _AccelerateDecelerateCurve extends Curve {
  const _AccelerateDecelerateCurve();

  @override
  double transformInternal(double t) => math.cos((t + 1) * math.pi) / 2.0 + 0.5;
}

const Curve _accelerateDecelerate = _AccelerateDecelerateCurve();

// ------------------------------------------------------------------ controller

/// Drives a [RecordOverlay]: the recording clock, the raw drag offset, the
/// locked flag and the record mode — the state the Java gesture code mutates
/// on the enter-view fields (`slideToCancelProgress`, `sendButtonVisible`,
/// the TimerView clock).
///
/// The owner (whoever runs the record pointer events — see
/// `RecordSendButton`) writes [elapsed], [dragOffset], [locked] and [mode];
/// the overlay renders. Derived gesture math ([slideProgress],
/// [shouldCancelOnRelease], [lockDragProgress]) lives here so it is testable
/// without any gestures or widgets.
///
/// Setting [dragOffset]:
///
///  * fires [onCancel] when [slideProgress] first reaches 0 — the Java
///    move-to-zero immediate cancel (CAEV:3158-3169);
///  * flips [locked] (firing [onLocked]) when the drag rises
///    [kRecordLockDistance] = 57dp while [slideProgress] >=
///    [kRecordLockSlideGate] = 0.7 (`setLockTranslation`, CAEV:2094-2114).
class RecordOverlayController extends ChangeNotifier {
  /// Creates the controller. The private initializing formals surface as
  /// `elapsed`, `dragOffset`, `locked` and `mode` named arguments.
  RecordOverlayController({
    this._elapsed = Duration.zero,
    this._dragOffset = Offset.zero,
    this._locked = false,
    this._mode = RecordMode.voice,
    this.onLocked,
    this.onCancel,
  });

  /// The drag crossed the 57dp lock threshold (`setLockTranslation`
  /// returning 2 -> `startLockTransition`, CAEV:3128-3130). Not fired by an
  /// explicit [locked] write — the owner already knows.
  VoidCallback? onLocked;

  /// The slide reached progress 0 — cancel immediately
  /// (`RECORD_STATE_CANCEL_BY_GESTURE`, CAEV:3158-3169).
  VoidCallback? onCancel;

  Duration _elapsed;
  Offset _dragOffset;
  bool _locked;
  RecordMode _mode;
  double _slideWidth = 0.0;

  /// The recording clock (the TimerView `t`, CAEV:14200-14202).
  Duration get elapsed => _elapsed;
  set elapsed(Duration value) {
    if (_elapsed == value) {
      return;
    }
    _elapsed = value;
    notifyListeners();
  }

  /// Raw pointer offset from the touch start: negative dx = slide left
  /// toward cancel (CAEV:3143-3145), negative dy = drag up toward the lock
  /// (CAEV:2094-2114).
  Offset get dragOffset => _dragOffset;
  set dragOffset(Offset value) {
    if (_dragOffset == value) {
      return;
    }
    final double before = slideProgress;
    _dragOffset = value;
    if (!_locked && before > 0.0 && slideProgress <= 0.0) {
      onCancel?.call();
    } else if (!_locked &&
        slideProgress >= kRecordLockSlideGate &&
        -_dragOffset.dy >= kRecordLockDistance) {
      _locked = true;
      onLocked?.call();
    }
    notifyListeners();
  }

  /// Whether the recording is hand-free (`sendButtonVisible`, CAEV:2108).
  /// Auto-set by the drag (see [dragOffset]); writable for the owner's
  /// programmatic paths.
  bool get locked => _locked;
  set locked(bool value) {
    if (_locked == value) {
      return;
    }
    _locked = value;
    notifyListeners();
  }

  /// Voice or round-video note (`isInVideoMode()`, CAEV:6112-6120).
  RecordMode get mode => _mode;
  set mode(RecordMode value) {
    if (_mode == value) {
      return;
    }
    _mode = value;
    notifyListeners();
  }

  /// The layout width the cancel distance derives from — the Java
  /// `sizeNotifierLayout.getMeasuredWidth()` (CAEV:3137). Reported by the
  /// attached overlay every layout; settable directly in tests or by
  /// widget-less owners.
  double get slideWidth => _slideWidth;
  set slideWidth(double value) {
    if (_slideWidth == value) {
      return;
    }
    _slideWidth = value;
    notifyListeners();
  }

  /// Layout-time report from [RecordOverlay] — stores without notifying
  /// (the overlay is rebuilding already).
  void _reportSlideWidth(double value) {
    _slideWidth = value;
  }

  /// `distCanMove` (CAEV:3135-3141).
  double get cancelDistance => recordSlideCancelDistance(_slideWidth);

  /// `slideProgress = clamp(1 + dx / distCanMove, 0, 1)` (CAEV:3143-3157);
  /// only leftward drag counts, and an unmeasured width (distance 0) pins
  /// the progress at rest.
  double get slideProgress {
    final double distance = cancelDistance;
    if (distance <= 0.0) {
      return 1.0;
    }
    final double dx = math.min(0.0, _dragOffset.dx);
    return (1.0 + dx / distance).clamp(0.0, 1.0);
  }

  /// Whether releasing now cancels the recording: `slideProgress < 0.45`
  /// (CAEV:3048-3062). Never true once [locked] (release stops tracking,
  /// CAEV:3125-3127).
  bool get shouldCancelOnRelease =>
      !_locked && slideProgress < kRecordSlideCancelReleaseThreshold;

  /// Upward drag toward the lock in 0..1 (1 = the 57dp threshold): the Java
  /// `1 - moveProgress` (CAEV:1385-1391, 2107). Pinned at 1 while [locked].
  double get lockDragProgress {
    if (_locked) {
      return 1.0;
    }
    return (-_dragOffset.dy / kRecordLockDistance).clamp(0.0, 1.0);
  }

  /// Record-circle x translation for the slide:
  /// `-distCanMove * (1 - slideProgress)` (CAEV:1913-1921). Exposed for the
  /// circle's owner; the overlay itself only consumes the text drift.
  double get slideDelta => -cancelDistance * (1.0 - slideProgress);

  /// Record-circle scale for the slide: `0.7 + 0.3 * slideProgress`
  /// (CAEV:2176-2181). Exposed for the circle's owner.
  double get slideCircleScale => 0.7 + 0.3 * slideProgress;

  /// Restores the resting state for the next recording (elapsed 0, no drag,
  /// unlocked). [mode] is preserved — Java persists it in prefs
  /// (CAEV:6112-6120).
  void reset() {
    _elapsed = Duration.zero;
    _dragOffset = Offset.zero;
    _locked = false;
    notifyListeners();
  }
}

// ---------------------------------------------------------------------- widget

/// The recording chrome (spec_chat_input.md sections 4-5), pure presentation
/// over a [RecordOverlayController]:
///
///  * bottom row, full width x 44dp (CAEV:9690): the pulsing 5dp red dot in
///    its 28dp slot (`chat_recordedVoiceDot`, 600ms out / 600ms in,
///    CAEV:1032-1055), the `m:ss,d` timer (15dp bold `chat_recordTime`,
///    CAEV:14193-14218) 6dp to its right, and the "Slide to cancel" hint
///    with its bobbing 1.6dp chevron (CAEV:13958-14091) that drifts and
///    fades with the slide and morphs into the CANCEL button once locked
///    (CAEV:14074-14122);
///  * the lock pill: 36dp wide, radius 18dp, height 50dp -> 36dp with the
///    upward drag, glass background over
///    `chat_messagePanelVoiceLockBackground` (radius 18dp, padding 3dp,
///    CAEV:1683-1699), glyph in `glass_defaultIcon` morphing into pause bars
///    on lock (250ms EASE_OUT_QUINT snap + 350ms/100ms-delay translation
///    return, CAEV:4607-4630);
///  * in [RecordMode.video], the centered circular [videoPreview] slot with
///    the white 3dp progress ring (inset -8dp, from -90 degrees, 60s cap,
///    ICV:284-287, 612-629).
///
/// The overlay must be given bounded constraints (it covers the chat area
/// above the input bar, bottom-aligned like the Java record views,
/// CAEV:4460-4472). Like every component in this package it takes an
/// optional [resources] override that wins over the ambient theme.
class RecordOverlay extends StatefulWidget {
  /// Creates the overlay.
  const RecordOverlay({
    super.key,
    required this.controller,
    this.videoPreview,
    this.onCancelTap,
    this.slideText = 'Slide to cancel',
    this.cancelText = 'CANCEL',
    this.resources,
  });

  /// The driving state; the overlay repaints on every change. Never owned:
  /// the caller creates and disposes it (it outlives the overlay across the
  /// record enter/exit remounts).
  final RecordOverlayController controller;

  /// Callback slot for the round-video camera frames (the Java camera
  /// TextureView, ICV:308-314): masked into the preview circle. Never built
  /// here — capture pipelines are callback slots.
  final Widget? videoPreview;

  /// The CANCEL button was tapped in the locked state (CAEV:14110-14117).
  final VoidCallback? onCancelTap;

  /// `SlideToCancel2` ("Slide to cancel", CAEV:13975).
  final String slideText;

  /// The uppercased `Cancel` string (CAEV:13976-13977).
  final String cancelText;

  /// Per-surface palette override; defaults to the ambient [TelegramTheme]
  /// resolution (the `resourcesProvider` convention).
  final TelegramResources? resources;

  @override
  RecordOverlayState createState() => RecordOverlayState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<RecordOverlayController>('controller', controller))
      ..add(ObjectFlagProperty<Widget>.has('videoPreview', videoPreview))
      ..add(ObjectFlagProperty<VoidCallback>.has('onCancelTap', onCancelTap))
      ..add(StringProperty('slideText', slideText, defaultValue: 'Slide to cancel'))
      ..add(StringProperty('cancelText', cancelText, defaultValue: 'CANCEL'));
  }
}

/// State of [RecordOverlay]; public for test access to the animation value
/// getters.
class RecordOverlayState extends State<RecordOverlay> with TickerProviderStateMixin {
  /// Dot pulse phase over [kRecordDotPulsePeriod], repeating; alpha =
  /// [recordDotPulseAlpha] of the value (CAEV:1032-1049). The Java holds
  /// alpha at 1 during the 150ms enter set (CAEV:1033-1034) — the enter set
  /// is out of scope here, so the pulse starts at phase 0 (alpha 1).
  late final AnimationController _dotPhase;

  /// Arrow bob phase over [kRecordSlideArrowBobPeriod], repeating; offset =
  /// amplitude * triangle(value) gated by slideProgress > 0.8
  /// (CAEV:14055-14071).
  late final AnimationController _bobPhase;

  /// `cancelToProgress`: grey hint -> CANCEL morph, 300ms (CAEV:14074-14122).
  late final AnimationController _cancelTo;

  /// `snapAnimationProgress`: the pause morph, 250ms EASE_OUT_QUINT
  /// (CAEV:4620-4624). The stored value is already curved
  /// ([AnimationController.animateTo] applies the curve internally).
  late final AnimationController _snap;

  /// `lockAnimatedTranslation` return: 0 = pill still at the dragged
  /// position, 1 = back at start; 350ms after a 100ms delay
  /// (CAEV:4610-4617).
  late final AnimationController _lockTranslate;

  Timer? _translateTimer;
  bool _wasLocked = false;

  RecordOverlayController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _dotPhase = AnimationController(vsync: this, duration: kRecordDotPulsePeriod)..repeat();
    _bobPhase = AnimationController(vsync: this, duration: kRecordSlideArrowBobPeriod)..repeat();
    _cancelTo = AnimationController(vsync: this, duration: kRecordCancelMorphDuration);
    _snap = AnimationController(vsync: this, duration: kRecordLockSnapDuration);
    _lockTranslate = AnimationController(vsync: this, duration: kRecordLockTranslateDuration);
    _controller.addListener(_handleControllerChanged);
    _syncLockState(jump: true);
  }

  @override
  void didUpdateWidget(RecordOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _syncLockState(jump: true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _translateTimer?.cancel();
    _translateTimer = null;
    _dotPhase.dispose();
    _bobPhase.dispose();
    _cancelTo.dispose();
    _snap.dispose();
    _lockTranslate.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    _syncLockState(jump: false);
    setState(() {});
  }

  /// Tracks the controller's locked flag into the lock-transition drivers:
  /// animated on a live flip (`startLockTransition`, CAEV:4607-4630),
  /// jumped when (re)attaching a controller.
  void _syncLockState({required bool jump}) {
    final bool locked = _controller.locked;
    if (locked == _wasLocked && !jump) {
      return;
    }
    _wasLocked = locked;
    _translateTimer?.cancel();
    _translateTimer = null;
    if (jump) {
      final double value = locked ? 1.0 : 0.0;
      _cancelTo.value = value;
      _snap.value = value;
      _lockTranslate.value = value;
      return;
    }
    if (locked) {
      // performHapticFeedback(KEYBOARD_TAP) (CAEV:4608); Flutter's
      // mediumImpact maps to it on Android.
      HapticFeedback.mediumImpact();
      _snap.animateTo(1.0, duration: kRecordLockSnapDuration, curve: TgCurves.easeOutQuint);
      _cancelTo.animateTo(1.0, duration: kRecordCancelMorphDuration, curve: TgCurves.defaultCubic);
      _translateTimer = Timer(kRecordLockTranslateDelay, () {
        _translateTimer = null;
        if (mounted) {
          _lockTranslate.animateTo(1.0,
              duration: kRecordLockTranslateDuration, curve: _accelerateDecelerate);
        }
      });
    } else {
      _cancelTo.value = 0.0;
      _snap.value = 0.0;
      _lockTranslate.value = 0.0;
    }
  }

  // ----------------------------------------------------------- debug getters

  /// The pulsing dot alpha (CAEV:1032-1049).
  @visibleForTesting
  double get debugDotAlpha => recordDotPulseAlpha(_dotPhase.value);

  /// The chevron bob offset in dp, 0 while gated (CAEV:14055-14071).
  @visibleForTesting
  double get debugArrowBobOffset => _bobOffset;

  /// `cancelToProgress` (CAEV:14074-14122).
  @visibleForTesting
  double get debugCancelMorphFactor => _cancelTo.value;

  /// `snapAnimationProgress` — the pause morph (CAEV:4620-4624).
  @visibleForTesting
  double get debugPauseMorphFactor => _snap.value;

  /// The current `yAdd` — the pill's upward translation in dp
  /// (CAEV:1385-1386), returning to 0 after the lock snap.
  @visibleForTesting
  double get debugLockYAdd => _lockYAdd;

  /// The pill height: `lockSize` (CAEV:1521).
  @visibleForTesting
  double get debugLockPillHeight => recordLockPillHeight(_controller.lockDragProgress);

  /// The pill's bottom offset from the overlay bottom:
  /// `134 + yAdd - lockSize` (see [kRecordLockPillTopFromBottom]).
  @visibleForTesting
  double get debugLockPillBottom =>
      kRecordLockPillTopFromBottom + _lockYAdd - debugLockPillHeight;

  double get _lockYAdd =>
      kRecordLockDistance * _controller.lockDragProgress * (1.0 - _lockTranslate.value);

  double get _bobOffset => _controller.slideProgress > kRecordSlideArrowBobGate
      ? kRecordSlideArrowBobAmplitude * _triangle(_bobPhase.value)
      : 0.0;

  static double _triangle(double t) {
    final double phase = t - t.floorToDouble();
    return phase < 0.5 ? 2.0 * phase : 2.0 - 2.0 * phase;
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    return resources != null ? resources.getColor(key) : TelegramTheme.colorOf(context, key);
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final RecordOverlayController controller = _controller;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        controller._reportSlideWidth(width);
        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_cancelTo, _snap, _lockTranslate]),
          builder: (BuildContext context, Widget? child) {
            return Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                if (controller.mode == RecordMode.video && widget.videoPreview != null)
                  Positioned.fill(child: _buildVideoPreview(constraints.biggest)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: kRecordOverlayBarHeight,
                  child: _buildBar(context),
                ),
                Positioned(
                  right: kRecordLockCenterFromRight - kRecordLockPillWidth / 2,
                  bottom: debugLockPillBottom,
                  width: kRecordLockPillWidth,
                  height: debugLockPillHeight,
                  child: _buildLockPill(context),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// The record panel row (CAEV:9677-9703): timer container left, slide
  /// text from 45dp on.
  Widget _buildBar(BuildContext context) {
    final RecordOverlayController controller = _controller;
    final Color recordTime = _color(context, TelegramColorKey.chat_recordTime);
    final Color dotColor = _color(context, TelegramColorKey.chat_recordedVoiceDot);
    final double slideProgress = controller.slideProgress;
    final double cancelTo = _cancelTo.value;
    // Grey hint alpha: `alpha *= (1 - cancelToProgress) * slideProgress`
    // (CAEV:14074-14085).
    final double hintAlpha = ((1.0 - cancelTo) * slideProgress).clamp(0.0, 1.0);
    // Drift: `-width/4 * (1 - slideProgress) + circleTranslationX * 0.3`
    // over the +5dp centering bias (CAEV:14076-14089), with
    // circleTranslationX = slideDelta (CAEV:1913-1921).
    final double slideAreaWidth =
        math.max(0.0, controller.slideWidth - kRecordSlideTextLeftMargin);
    final double drift = kRecordSlideTextCenterBias -
        slideAreaWidth / 4.0 * (1.0 - slideProgress) +
        controller.slideDelta * 0.3;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        // recordTimeContainer: paddingLeft 13dp, children centered
        // vertically (CAEV:9694-9702).
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Padding(
            padding: const EdgeInsets.only(left: kRecordTimeContainerPaddingLeft),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AnimatedBuilder(
                  animation: _dotPhase,
                  builder: (BuildContext context, Widget? child) => CustomPaint(
                    size: const Size.square(kRecordDotSlotSize),
                    painter: _RecordDotPainter(color: dotColor, alpha: debugDotAlpha),
                  ),
                ),
                const SizedBox(width: kRecordTimerLeftMargin),
                Text(
                  formatRecordTimer(controller.elapsed),
                  style: TextStyle(
                    // AndroidUtilities.bold() = Roboto Medium, bundled as the
                    // w500 family `RobotoMedium` (CAEV:14196).
                    fontFamily: 'RobotoMedium',
                    fontWeight: FontWeight.w500,
                    fontSize: kRecordTimerFontSize,
                    color: recordTime,
                  ),
                ),
              ],
            ),
          ),
        ),
        // SlideTextView area: leftMargin 45dp (CAEV:9692).
        Positioned(
          left: kRecordSlideTextLeftMargin,
          right: 0,
          top: 0,
          bottom: 0,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              if (hintAlpha > 0.0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: hintAlpha,
                      child: Center(
                        child: Transform.translate(
                          offset: Offset(drift, 0.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              AnimatedBuilder(
                                animation: _bobPhase,
                                builder: (BuildContext context, Widget? child) =>
                                    Transform.translate(
                                  offset: Offset(-_bobOffset, 0.0),
                                  child: child,
                                ),
                                child: CustomPaint(
                                  size: const Size(
                                    kRecordSlideArrowWidth + kRecordSlideArrowStrokeWidth,
                                    kRecordSlideArrowHeight + kRecordSlideArrowStrokeWidth,
                                  ),
                                  painter: _SlideArrowPainter(color: recordTime),
                                ),
                              ),
                              const SizedBox(width: kRecordSlideArrowGap),
                              Text(
                                widget.slideText,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: kRecordSlideTextFontSize,
                                  color: recordTime,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (cancelTo > 0.0)
                Positioned.fill(
                  child: Opacity(
                    opacity: cancelTo.clamp(0.0, 1.0),
                    child: Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onCancelTap,
                        child: Padding(
                          // Hit rect = text bounds inset -16dp (CAEV:13989).
                          padding: const EdgeInsets.all(kRecordCancelHitInset),
                          child: Text(
                            widget.cancelText,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: 'RobotoMedium',
                              fontWeight: FontWeight.w500,
                              fontSize: kRecordSlideTextFontSize,
                              color: _color(context, TelegramColorKey.chat_recordVoiceCancel),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The lock pill: glass over `chat_messagePanelVoiceLockBackground`
  /// (radius 18dp, padding 3dp, CAEV:1683-1699) with the lock/pause glyph.
  Widget _buildLockPill(BuildContext context) {
    final TelegramResources resources = widget.resources ?? TelegramTheme.resources(context);
    final double drag = _controller.lockDragProgress;
    final double pauseMorph = _snap.value;
    // Rotation: 9 deg * (1 - moveProgress) while dragging, snapping to
    // -15 deg * snapProgress on lock (CAEV:1546-1632).
    final double rotationDegrees = lerpDouble(9.0 * drag, -15.0, pauseMorph)!;
    return GlassPanel(
      style: GlassSurfaceStyle.themed(
        resources: resources,
        colorKey: TelegramColorKey.chat_messagePanelVoiceLockBackground,
      ),
      borderRadius: const GlassRadii.all(kRecordLockPillRadius),
      padding: kRecordLockGlassPadding,
      child: CustomPaint(
        painter: _LockGlyphPainter(
          iconColor: _color(context, TelegramColorKey.glass_defaultIcon),
          keyholeColor:
              _color(context, TelegramColorKey.chat_messagePanelVoiceLockBackground),
          moveProgress: 1.0 - drag,
          pauseMorph: pauseMorph,
          rotationDegrees: rotationDegrees,
        ),
      ),
    );
  }

  /// The round-video preview slot: the circular mask (`ViewOutlineProvider`
  /// oval + clipToOutline, ICV:308-314) with the progress ring drawn on the
  /// circle bounds inset -8dp (ICV:284-287, 612-629).
  Widget _buildVideoPreview(Size viewport) {
    final double diameter = roundVideoPreviewDiameter(viewport);
    final double ringBox =
        diameter + 2.0 * (kRoundVideoRingInset + kRoundVideoRingStrokeWidth / 2.0);
    return Center(
      child: SizedBox(
        width: ringBox,
        height: ringBox,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            SizedBox(
              width: diameter,
              height: diameter,
              child: ClipOval(child: widget.videoPreview),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _VideoRingPainter(
                  progress: roundVideoProgress(_controller.elapsed),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- painters

/// The 5dp red dot centered in its 28dp slot; the paint alpha *replaces* the
/// color's (`redDotPaint.setAlpha(255 * alpha)`, CAEV:1030, 1055).
class _RecordDotPainter extends CustomPainter {
  const _RecordDotPainter({required this.color, required this.alpha});

  final Color color;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      size.center(Offset.zero),
      kRecordDotRadius,
      Paint()..color = color.withValues(alpha: alpha.clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(_RecordDotPainter oldDelegate) =>
      color != oldDelegate.color || alpha != oldDelegate.alpha;
}

/// The left-pointing chevron: legs (4, -5) -> (0, 0) -> (4, 5), stroke 1.6dp
/// round cap/join (CAEV:13969-13973, 14024-14033).
class _SlideArrowPainter extends CustomPainter {
  const _SlideArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double inset = kRecordSlideArrowStrokeWidth / 2.0;
    final double cy = size.height / 2.0;
    final Path chevron = Path()
      ..moveTo(inset + kRecordSlideArrowWidth, cy - kRecordSlideArrowHeight / 2.0)
      ..lineTo(inset, cy)
      ..lineTo(inset + kRecordSlideArrowWidth, cy + kRecordSlideArrowHeight / 2.0);
    canvas.drawPath(
      chevron,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = kRecordSlideArrowStrokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SlideArrowPainter oldDelegate) => color != oldDelegate.color;
}

/// The round-video progress ring: white 3dp round-cap stroke from -90
/// degrees, sweep `360 * progress` (ICV:284-287, 612-629). The paint box is
/// already the circle bounds inset -8dp plus stroke overhang.
class _VideoRingPainter extends CustomPainter {
  const _VideoRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) {
      return;
    }
    final Rect rect =
        (Offset.zero & size).deflate(kRoundVideoRingStrokeWidth / 2.0);
    canvas.drawArc(
      rect,
      -math.pi / 2.0,
      2.0 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = kRoundVideoRingStrokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_VideoRingPainter oldDelegate) => progress != oldDelegate.progress;
}

/// The lock glyph (CAEV:1546-1632, simplified — the resume-to-mic morph and
/// idle swell easing are not ported): a ~12dp rounded body with the 8dp
/// shackle arc (stroke 1.7dp) and a 2dp keyhole dot in the background color;
/// once [pauseMorph] rises the body splits into two pause bars 3.3dp apart
/// with radii 3dp -> 1.5dp while shackle and keyhole fade out
/// (CAEV:1593-1612).
class _LockGlyphPainter extends CustomPainter {
  const _LockGlyphPainter({
    required this.iconColor,
    required this.keyholeColor,
    required this.moveProgress,
    required this.pauseMorph,
    required this.rotationDegrees,
  });

  final Color iconColor;
  final Color keyholeColor;

  /// 1 at rest, 0 fully dragged (the Java `moveProgress`).
  final double moveProgress;

  /// `snapAnimationProgress`-driven pause morph, 0..1.
  final double pauseMorph;

  /// Glyph rotation (CAEV:1546-1632).
  final double rotationDegrees;

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2.0;
    final double cy = size.height / 2.0;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotationDegrees * math.pi / 180.0);
    canvas.translate(-cx, -cy);

    // Body: cx +- 6dp with a 2dp swell while unlocked (CAEV:1546-1560).
    final double swell = 2.0 * moveProgress * (1.0 - pauseMorph);
    final double bodySide = 12.0 + swell;
    final Rect body = Rect.fromCenter(
      center: Offset(cx, cy + 3.0),
      width: bodySide,
      height: bodySide,
    );
    final double gap = kRecordLockPauseBarGap * pauseMorph;
    final Radius radius = Radius.circular(lerpDouble(3.0, 1.5, pauseMorph)!);
    final Paint fill = Paint()..color = iconColor;
    if (gap <= 0.0) {
      canvas.drawRRect(RRect.fromRectAndRadius(body, radius), fill);
    } else {
      final double barWidth = (body.width - gap) / 2.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(body.left, body.top, barWidth, body.height),
          radius,
        ),
        fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(body.right - barWidth, body.top, barWidth, body.height),
          radius,
        ),
        fill,
      );
    }

    final double lockPartsAlpha = (1.0 - pauseMorph).clamp(0.0, 1.0);
    if (lockPartsAlpha > 0.0) {
      // Shackle: 8x8dp top-half arc, stroke 1.7dp round cap (CAEV:1561-1580).
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, body.top), radius: 4.0),
        math.pi,
        math.pi,
        false,
        Paint()
          ..color = iconColor.withValues(alpha: iconColor.a * lockPartsAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round,
      );
      // Keyhole dot: radius 2dp in the background color (CAEV:1581-1590).
      canvas.drawCircle(
        body.center,
        2.0,
        Paint()..color = keyholeColor.withValues(alpha: keyholeColor.a * lockPartsAlpha),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LockGlyphPainter oldDelegate) =>
      iconColor != oldDelegate.iconColor ||
      keyholeColor != oldDelegate.keyholeColor ||
      moveProgress != oldDelegate.moveProgress ||
      pauseMorph != oldDelegate.pauseMorph ||
      rotationDegrees != oldDelegate.rotationDegrees;
}
