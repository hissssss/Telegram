// The composed chat input — [ChatInputBar] + [RecordSendButton] +
// [RecordOverlay] wired through the enter-view state machine of
// `java/org/telegram/ui/Components/ChatActivityEnterView.java` (**CAEV**):
//
//  * typing morphs the mic/video button into the send plane
//    (`checkSendButton`, CAEV:8153-8189) and a send tap emits the trimmed
//    draft, then clears the field (`sendMessage` -> `setFieldText`,
//    CAEV:12233-12295);
//  * holding the button arms a recording (`recordAudioVideoRunnable`,
//    CAEV:895-956) and mounts the record overlay chrome (record panel,
//    slide-to-cancel, lock pill, CAEV:9677-9703);
//  * the pointer drag is fed into the [RecordOverlayController]
//    (`onTouchEvent` ACTION_MOVE, CAEV:3123-3170): sliding to progress 0
//    cancels mid-drag (CAEV:3158-3169), releasing below 0.45 cancels
//    (CAEV:3048-3062), dragging up 57dp locks (`setLockTranslation`,
//    CAEV:2094-2114, 3125-3130);
//  * a locked recording survives the release (`sendButtonVisible`,
//    CAEV:2108): the overlay persists, the bar button shows the send plane,
//    and either CANCEL (CAEV:14110-14117) or send resolves it;
//  * plain release is release-to-send (CAEV:3074-3121).
//
// The pieces own their gestures and animations; this file owns only the
// state machine and the recording clock (the `TimerView` time base,
// CAEV:14197-14202). Capture pipelines stay callback slots: [ChatInput]
// forwards [ChatInput.amplitude] and [ChatInput.videoPreview] verbatim and
// records nothing.
//
// Owner simplifications (documented per spec_chat_input.md):
//
//  * a mid-drag slide cancel hides the overlay immediately but the record
//    circle plays its exit only on the actual release — the button exposes
//    no programmatic stop (Java runs the RECORD_STATE_CANCEL_BY_GESTURE set
//    at once, CAEV:3158-3169);
//  * a locked recording drops the expanded circle on release instead of
//    keeping the in-circle send button of the Java ControlsView
//    (CAEV:1162-1875); the bar-button send morph stands in for it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../glass/liquid_glass_settings.dart';
import '../../glass/strategy.dart';
import '../../theme/telegram_resources.dart';
import 'chat_input_bar.dart';
import 'record_overlay.dart';
import 'record_send_button.dart';

/// Tick of the recording clock driving [RecordOverlayController.elapsed].
/// The Java `TimerView` redraws every frame off `SystemClock` deltas
/// (CAEV:14197-14202); 100ms is the coarsest tick that keeps the `m:ss,d`
/// tenths digit ([formatRecordTimer]) advancing every step.
const Duration kChatInputTimerTick = Duration(milliseconds: 100);

/// Phase of the [ChatInput] record state machine.
enum ChatInputPhase {
  /// No recording: the bar is live, the button rests as mic/video/send.
  idle,

  /// The pointer holds an armed recording (`recordingAudioVideo`,
  /// CAEV:895-956); the overlay chrome is mounted.
  recording,

  /// The recording locked hands-free and the pointer released
  /// (`sendButtonVisible`, CAEV:2108): the overlay persists and the bar
  /// button shows the send plane until CANCEL or send resolves it.
  lockedRecording,
}

/// The wired chat input: the [ChatInputBar] island with a [RecordSendButton]
/// in its send slot and the [RecordOverlay] recording chrome over the chat
/// area, connected through the CAEV state machine (see the library comment).
///
/// Fill the chat area with it (bounded constraints required): the bar docks
/// to the bottom edge and the overlay covers the rest while recording — the
/// lock pill floats 134dp up (CAEV:1385-1386) and a video recording centers
/// [videoPreview] in the viewport (ICV:509-526). Transparent regions pass
/// hits through to whatever sits underneath (the message list). The 9dp
/// island bottom gap ([kChatInputBubbleBottomGapDp]) and the bottom inset
/// remain the host's job, exactly as for the bare bar.
///
/// Outputs are callbacks only: [onSendMessage] with the trimmed draft,
/// [onRecordingComplete] with the mode and clocked duration, and
/// [onRecordingCanceled]. Nothing is recorded — [amplitude] and
/// [videoPreview] are the capture callback slots forwarded to the pieces.
class ChatInput extends StatefulWidget {
  /// Creates the composed input.
  const ChatInput({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText = 'Message',
    this.emojiSlot,
    this.attachSlot,
    this.hasVideo = true,
    this.initialRecordMode = RecordMode.voice,
    this.onSendMessage,
    this.onRecordingStarted,
    this.onRecordingComplete,
    this.onRecordingCanceled,
    this.onRecordModeChanged,
    this.amplitude,
    this.videoPreview,
    this.micIcon,
    this.videoIcon,
    this.sendIcon,
    this.slideText = 'Slide to cancel',
    this.cancelText = 'CANCEL',
    this.settings = kChatInputGlassSettings,
    this.tier,
    this.resources,
  });

  /// Draft controller forwarded to the [ChatInputBar]; an internal one is
  /// created (and owned) when null.
  final ChatInputBarController? controller;

  /// Focus node of the message field; forwarded to the bar.
  final FocusNode? focusNode;

  /// Hint of the empty field ("Message", CAEV:6734-6823). Suppressed while a
  /// recording runs so the record panel row does not overprint it (Java
  /// fades the whole field out in the record enter set, CAEV:8831-8963).
  final String hintText;

  /// The bar's emoji slot; faded out over 150ms while recording (the
  /// enter-set icon legs, CAEV:8923-8925).
  final Widget? emojiSlot;

  /// The bar's attach slot; faded like [emojiSlot].
  final Widget? attachSlot;

  /// The Java `hasRecordVideo` flag forwarded to the button: enables the
  /// voice <-> video tap toggle and the 150ms hold delay (CAEV:3013-3018).
  final bool hasVideo;

  /// Initial record mode (Java restores it from prefs, CAEV:6112-6120).
  /// Taps toggle it internally and report through [onRecordModeChanged].
  final RecordMode initialRecordMode;

  /// A text send resolved: fired with the trimmed draft, after which the
  /// field is cleared (CAEV:12233-12295).
  final ValueChanged<String>? onSendMessage;

  /// A recording armed (the hold fired), with its mode.
  final ValueChanged<RecordMode>? onRecordingStarted;

  /// A recording resolved to send — release-to-send (CAEV:3074-3121) or the
  /// locked-state send tap — with its mode and clocked duration.
  final void Function(RecordMode mode, Duration duration)? onRecordingComplete;

  /// A recording resolved to cancel: slide-to-zero (CAEV:3158-3169), release
  /// below 0.45 (CAEV:3048-3062), or the locked CANCEL tap
  /// (CAEV:14110-14117).
  final VoidCallback? onRecordingCanceled;

  /// The tap toggle changed the record mode (`onSwitchRecordMode`,
  /// CAEV:3066-3069).
  final ValueChanged<RecordMode>? onRecordModeChanged;

  /// Normalized mic amplitude slot, forwarded to [RecordSendButton.amplitude]
  /// (Java feeds `min(1800, raw) / 1800`, CAEV:2025-2030). Never captured
  /// here.
  final ValueListenable<double>? amplitude;

  /// Round-video camera frame slot, forwarded to
  /// [RecordOverlay.videoPreview] (ICV:308-314). Never captured here.
  final Widget? videoPreview;

  /// Icon overrides forwarded to the button (see [RecordSendButton.micIcon]).
  final Widget? micIcon;

  /// See [micIcon].
  final Widget? videoIcon;

  /// See [micIcon].
  final Widget? sendIcon;

  /// Overlay strings, forwarded (`SlideToCancel2` / uppercased `Cancel`,
  /// CAEV:13975-13977).
  final String slideText;

  /// See [slideText].
  final String cancelText;

  /// Island glass parameters, forwarded to the bar (CIVC:89-90).
  final LiquidGlassSettings settings;

  /// Per-panel tier override, forwarded to the bar.
  final GlassTier? tier;

  /// Per-surface palette override, forwarded to every piece (the
  /// `resourcesProvider` convention).
  final TelegramResources? resources;

  @override
  ChatInputState createState() => ChatInputState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<ChatInputBarController>('controller', controller,
          defaultValue: null))
      ..add(StringProperty('hintText', hintText, defaultValue: 'Message'))
      ..add(FlagProperty('hasVideo',
          value: hasVideo, defaultValue: true, ifFalse: 'audio only'))
      ..add(EnumProperty<RecordMode>('initialRecordMode', initialRecordMode,
          defaultValue: RecordMode.voice))
      ..add(ObjectFlagProperty<ValueChanged<String>>.has(
          'onSendMessage', onSendMessage))
      ..add(ObjectFlagProperty<void Function(RecordMode, Duration)>.has(
          'onRecordingComplete', onRecordingComplete))
      ..add(ObjectFlagProperty<VoidCallback>.has(
          'onRecordingCanceled', onRecordingCanceled));
  }
}

/// State of [ChatInput]; public for test access to [phase] and the debug
/// getters.
class ChatInputState extends State<ChatInput> {
  ChatInputBarController? _internalBarController;
  late final RecordOverlayController _overlay;

  ChatInputPhase _phase = ChatInputPhase.idle;

  /// The slide hit progress 0 mid-drag: the overlay is already gone but the
  /// button still tracks the pointer until release (see the library comment).
  bool _pendingCancel = false;

  bool _hasText = false;
  late RecordMode _mode;
  Timer? _clock;
  Offset? _dragStart;

  ChatInputBarController get _barController =>
      widget.controller ?? (_internalBarController ??= ChatInputBarController());

  @override
  void initState() {
    super.initState();
    _mode = widget.hasVideo ? widget.initialRecordMode : RecordMode.voice;
    _overlay = RecordOverlayController(mode: _mode, onCancel: _handleSlideCancel);
    _barController.addListener(_handleDraftChanged);
    _hasText = _barController.text.trim().isNotEmpty;
  }

  @override
  void didUpdateWidget(ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      (oldWidget.controller ?? _internalBarController)
          ?.removeListener(_handleDraftChanged);
      _barController.addListener(_handleDraftChanged);
      _handleDraftChanged();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _clock = null;
    (widget.controller ?? _internalBarController)
        ?.removeListener(_handleDraftChanged);
    _internalBarController?.dispose();
    _overlay.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ state

  /// The current phase of the record state machine.
  ChatInputPhase get phase => _phase;

  /// The overlay controller the machine drives (elapsed/drag/locked/mode).
  @visibleForTesting
  RecordOverlayController get debugOverlayController => _overlay;

  /// Whether a mid-drag slide cancel is waiting for the pointer release.
  @visibleForTesting
  bool get debugPendingCancel => _pendingCancel;

  /// The effective record mode (tap toggles included).
  RecordMode get recordMode => _mode;

  bool get _recordingActive => _phase != ChatInputPhase.idle;

  bool get _overlayVisible => _recordingActive && !_pendingCancel;

  // ------------------------------------------------------------------ draft

  void _handleDraftChanged() {
    final bool hasText = _barController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      // checkSendButton (CAEV:8118-8189): the morph itself animates inside
      // the button; this just flips its input.
      setState(() => _hasText = hasText);
    }
  }

  // -------------------------------------------------------------- recording

  void _startClock() {
    _clock?.cancel();
    // Tick-based so a delayed callback still lands on the true multiple —
    // `Timer.tick` counts elapsed periods.
    _clock = Timer.periodic(kChatInputTimerTick, (Timer timer) {
      _overlay.elapsed = kChatInputTimerTick * timer.tick;
    });
  }

  /// The hold fired (`recordAudioVideoRunnable`, CAEV:895-956).
  void _handleRecordStart(RecordMode mode) {
    _overlay
      ..reset()
      ..mode = mode;
    _pendingCancel = false;
    _startClock();
    setState(() => _phase = ChatInputPhase.recording);
    widget.onRecordingStarted?.call(mode);
  }

  /// The slide reached progress 0 mid-drag
  /// (`RECORD_STATE_CANCEL_BY_GESTURE`, CAEV:3158-3169). The overlay hides
  /// now; the cancel resolves on the release the button is still tracking.
  void _handleSlideCancel() {
    if (_phase != ChatInputPhase.recording || _pendingCancel) {
      return;
    }
    _clock?.cancel();
    _clock = null;
    setState(() => _pendingCancel = true);
  }

  /// The pointer released or was cancelled while recording (CAEV:3042-3121).
  void _handleRecordEnd() {
    if (_phase != ChatInputPhase.recording) {
      return;
    }
    if (_pendingCancel) {
      _resolveCancel();
    } else if (_overlay.locked) {
      // The lock survives the release (`sendButtonVisible`, CAEV:2108): keep
      // the overlay and clock, morph the bar button into the send plane.
      setState(() => _phase = ChatInputPhase.lockedRecording);
    } else if (_overlay.shouldCancelOnRelease) {
      // Released left of the 0.45 slide threshold (CAEV:3048-3062).
      _resolveCancel();
    } else {
      // Release-to-send (CAEV:3074-3121).
      _resolveComplete();
    }
  }

  /// The locked CANCEL button (CAEV:14110-14117).
  void _handleCancelTap() {
    if (_phase == ChatInputPhase.lockedRecording) {
      _resolveCancel();
    }
  }

  void _resolveCancel() {
    _resetRecording();
    widget.onRecordingCanceled?.call();
  }

  void _resolveComplete() {
    final RecordMode mode = _overlay.mode;
    final Duration duration = _overlay.elapsed;
    _resetRecording();
    widget.onRecordingComplete?.call(mode, duration);
  }

  void _resetRecording() {
    _clock?.cancel();
    _clock = null;
    _pendingCancel = false;
    _overlay.reset();
    setState(() => _phase = ChatInputPhase.idle);
  }

  // ------------------------------------------------------------------- send

  /// Send tap: a locked recording wins over the draft (Java hides the field
  /// behind the recorded-audio panel while locked, CAEV:9535-9619).
  void _handleSend() {
    if (_phase == ChatInputPhase.lockedRecording) {
      _resolveComplete();
      return;
    }
    final String text = _barController.text.trim();
    if (text.isEmpty) {
      return;
    }
    widget.onSendMessage?.call(text);
    // sendMessage clears the field (CAEV:12233-12295).
    _barController.text = '';
  }

  void _handleModeChanged(RecordMode mode) {
    setState(() => _mode = mode);
    widget.onRecordModeChanged?.call(mode);
  }

  // ------------------------------------------------------------------- drag

  /// The record drag is tracked here — the button only reports start/end;
  /// the ACTION_MOVE math (CAEV:3123-3170) lives in the overlay controller,
  /// fed with the raw offset from the touch-down position.
  void _handleSlotPointerDown(PointerDownEvent event) {
    _dragStart = event.position;
  }

  void _handleSlotPointerMove(PointerMoveEvent event) {
    final Offset? start = _dragStart;
    if (start == null ||
        _phase != ChatInputPhase.recording ||
        _pendingCancel ||
        _overlay.locked) {
      // Once locked the release stops tracking (CAEV:3125-3127); a pending
      // cancel already resolved the gesture.
      return;
    }
    _overlay.dragOffset = event.position - start;
  }

  void _handleSlotPointerEnd() {
    _dragStart = null;
  }

  // ------------------------------------------------------------------ build

  /// Bar slots fade out over the 150ms icon legs of the record sets
  /// (CAEV:8923-8925, 9593) and stop hit-testing while hidden.
  Widget? _fadedSlot(Widget? slot) {
    if (slot == null) {
      return null;
    }
    return IgnorePointer(
      ignoring: _recordingActive,
      child: AnimatedOpacity(
        opacity: _recordingActive ? 0.0 : 1.0,
        duration: kRecordSendIconsDuration,
        child: slot,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget sendSlot = Listener(
      onPointerDown: _handleSlotPointerDown,
      onPointerMove: _handleSlotPointerMove,
      onPointerUp: (PointerUpEvent event) => _handleSlotPointerEnd(),
      onPointerCancel: (PointerCancelEvent event) => _handleSlotPointerEnd(),
      child: RecordSendButton(
        mode: _mode,
        hasText: _hasText || _phase == ChatInputPhase.lockedRecording,
        hasVideo: widget.hasVideo,
        onSend: _handleSend,
        onRecordStart: _handleRecordStart,
        onRecordEnd: _handleRecordEnd,
        onModeChanged: _handleModeChanged,
        amplitude: widget.amplitude,
        micIcon: widget.micIcon,
        videoIcon: widget.videoIcon,
        sendIcon: widget.sendIcon,
        resources: widget.resources,
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        // The bar docks to the bottom edge; the host applies the 9dp gap and
        // insets, as with the bare ChatInputBar (CIVC:185).
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ChatInputBar(
            controller: _barController,
            focusNode: widget.focusNode,
            hintText: _recordingActive ? '' : widget.hintText,
            emojiSlot: _fadedSlot(widget.emojiSlot),
            attachSlot: _fadedSlot(widget.attachSlot),
            sendSlot: sendSlot,
            settings: widget.settings,
            tier: widget.tier,
            resources: widget.resources,
          ),
        ),
        // Recording chrome over everything: its bottom row lands on the bar
        // (the record panel replaces the bar content, CAEV:9677-9703), the
        // lock pill and video preview use the full area above. Transparent
        // regions pass hits through — the send button below stays tappable
        // in the locked state.
        if (_overlayVisible)
          Positioned.fill(
            child: RecordOverlay(
              controller: _overlay,
              videoPreview: widget.videoPreview,
              onCancelTap: _handleCancelTap,
              slideText: widget.slideText,
              cancelText: widget.cancelText,
              resources: widget.resources,
            ),
          ),
      ],
    );
  }
}
