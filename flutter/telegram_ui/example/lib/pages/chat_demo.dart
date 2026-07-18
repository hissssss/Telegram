// Chat demo: a fake message list (plain colored bubbles — deliberately not a
// ChatBubble component) over a busy gradient background, with the composed
// ChatInput docked at the bottom. Exercises the full record flow: typing ->
// send morph, hold-to-record with the fake clock, slide-to-cancel, lock,
// and a synthesized amplitude feed for the voice waves.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:telegram_ui/telegram_ui.dart';

import 'glass_playground.dart' show BusyBackgroundPainter;

/// The chat demo page.
class ChatDemoPage extends StatefulWidget {
  const ChatDemoPage({super.key});

  @override
  State<ChatDemoPage> createState() => _ChatDemoPageState();
}

class _DemoMessage {
  const _DemoMessage(this.text, {required this.outgoing});

  final String text;
  final bool outgoing;
}

class _ChatDemoPageState extends State<ChatDemoPage> {
  final List<_DemoMessage> _messages = <_DemoMessage>[
    const _DemoMessage('Hey! Check out the new liquid glass input bar',
        outgoing: false),
    const _DemoMessage('Looks amazing over this gradient', outgoing: true),
    const _DemoMessage('Hold the mic to record — slide left to cancel, '
        'drag up to lock', outgoing: false),
    const _DemoMessage('Tap the mic to switch to round video mode',
        outgoing: false),
  ];

  /// Fake mic amplitude feed — capture pipelines are callback slots, so the
  /// demo synthesizes one with a timer.
  final ValueNotifier<double> _amplitude = ValueNotifier<double>(0.0);
  final math.Random _random = math.Random();
  Timer? _amplitudeTimer;

  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    _amplitude.dispose();
    super.dispose();
  }

  void _startAmplitude() {
    _amplitudeTimer?.cancel();
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 120),
        (Timer timer) => _amplitude.value = _random.nextDouble());
  }

  void _stopAmplitude() {
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _amplitude.value = 0.0;
  }

  void _addMessage(String text) {
    setState(() => _messages.add(_DemoMessage(text, outgoing: true)));
  }

  void _handleRecordingComplete(RecordMode mode, Duration duration) {
    _stopAmplitude();
    final String label = mode == RecordMode.voice ? 'Voice' : 'Video';
    _addMessage('🎤 $label message · ${formatRecordTimer(duration)}');
  }

  @override
  Widget build(BuildContext context) {
    final Color iconColor =
        TelegramTheme.colorOf(context, TelegramColorKey.chat_messagePanelIcons);
    return GlassBackdropScope(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const CustomPaint(painter: BusyBackgroundPainter()),
          SafeArea(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12,
                        kChatInputBarHeightDp + kChatInputBubbleBottomGapDp + 16),
                    itemCount: _messages.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _Bubble(_messages[_messages.length - 1 - index]),
                  ),
                ),
                // The composed input fills the chat area so the record
                // overlay (lock pill, video preview) can cover it; the bar
                // docks to its bottom, with the 9dp Java island gap applied
                // here (the host's job, CIVC:185).
                Positioned(
                  left: 8,
                  right: 8,
                  top: 0,
                  bottom: kChatInputBubbleBottomGapDp,
                  child: ChatInput(
                    onSendMessage: _addMessage,
                    onRecordingStarted: (RecordMode mode) => _startAmplitude(),
                    onRecordingComplete: _handleRecordingComplete,
                    onRecordingCanceled: _stopAmplitude,
                    amplitude: _amplitude,
                    // Round-video frames are a callback slot too; the demo
                    // fills the preview circle with a gradient stand-in.
                    videoPreview: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[Color(0xFF232526), Color(0xFF414345)],
                        ),
                      ),
                      child: Center(
                        child: Icon(Icons.videocam_rounded,
                            color: Colors.white38, size: 48),
                      ),
                    ),
                    emojiSlot: Icon(Icons.emoji_emotions_outlined,
                        color: iconColor),
                    attachSlot: Icon(Icons.attach_file_rounded,
                        color: iconColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain colored bubble — intentionally not a ported component.
class _Bubble extends StatelessWidget {
  const _Bubble(this.message);

  final _DemoMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment:
          message.outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: message.outgoing
              ? const Color(0xE6DCF8C6)
              : const Color(0xE6FFFFFF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          message.text,
          style: const TextStyle(fontSize: 15, color: Color(0xFF1B1B1B)),
        ),
      ),
    );
  }
}
