// Chat demo: a fake message list (plain colored bubbles — deliberately not a
// ChatBubble component) over a busy gradient background, with the composed
// ChatInput docked at the bottom. Exercises the full record flow: typing ->
// send morph, hold-to-record with the fake clock, slide-to-cancel, lock,
// and a synthesized amplitude feed for the voice waves — plus the emoji
// panel (toggled from the bar's emoji slot) and the attach sheet (opened
// from the attach slot) with placeholder content in every provider slot.

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

/// Placeholder emoji for the panel's emoji grid — the grid content is a
/// SLOT (`EmojiPanel.emojiBuilder`); the demo fills it with plain [Text].
const List<String> _demoEmoji = <String>[
  '😀', '😅', '😂', '🥲', '😊', '😍', '😘', '🤔',
  '🤯', '🥳', '😎', '🤓', '😢', '😭', '😡', '🤗',
  '👍', '👎', '👏', '🙏', '💪', '🤝', '✌️', '🤞',
  '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍',
  '🔥', '⭐', '⚡', '🎉', '🎁', '🚀', '🌈', '🍕',
];

/// Placeholder thumbnail colors for the attach sheet's media grid — the
/// gallery pipeline is a SLOT (`AttachSheetPage.mediaGrid.thumbnailsBuilder`).
const List<Color> _demoThumbColors = <Color>[
  Color(0xFFE57373), Color(0xFFF06292), Color(0xFFBA68C8), Color(0xFF9575CD),
  Color(0xFF7986CB), Color(0xFF64B5F6), Color(0xFF4FC3F7), Color(0xFF4DD0E1),
  Color(0xFF4DB6AC), Color(0xFF81C784), Color(0xFFAED581), Color(0xFFDCE775),
  Color(0xFFFFF176), Color(0xFFFFD54F), Color(0xFFFFB74D), Color(0xFFFF8A65),
  Color(0xFFA1887F), Color(0xFF90A4AE),
];

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

  /// Own the bar controller so tapped emoji can be appended to the draft.
  final ChatInputBarController _barController = ChatInputBarController();

  /// Whether the emoji panel is showing under the input (the demo's stand-in
  /// for the IME swap — no keyboard in the gallery, so it just slides).
  bool _emojiPanelOpen = false;

  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    _amplitude.dispose();
    _barController.dispose();
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

  void _toggleEmojiPanel() {
    setState(() => _emojiPanelOpen = !_emojiPanelOpen);
  }

  void _appendEmoji(String emoji) {
    _barController.text = _barController.text + emoji;
  }

  Future<void> _openAttachSheet() async {
    // Opening the sheet replaces the emoji panel, like on Android.
    if (_emojiPanelOpen) {
      setState(() => _emojiPanelOpen = false);
    }
    await showTgAttachSheet<void>(
      context,
      selectedCount: 3,
      onSend: () {
        Navigator.of(context).pop();
        _addMessage('📎 3 photos');
      },
      pages: <AttachSheetPage>[
        AttachSheetPage.mediaGrid(
          icon: const TabIcon.static(
            child: Icon(Icons.photo_library_outlined, size: 24),
          ),
          // The gallery pipeline is a provider slot: the demo supplies plain
          // colored boxes instead of MediaController thumbnails.
          thumbnailsBuilder: (BuildContext context) => <Widget>[
            for (int i = 0; i < _demoThumbColors.length; i++)
              ColoredBox(
                color: _demoThumbColors[i],
                child: Center(
                  child: Icon(
                    i.isEven
                        ? Icons.photo_outlined
                        : Icons.videocam_outlined,
                    color: Colors.white70,
                  ),
                ),
              ),
          ],
        ),
        AttachSheetPage(
          id: 'file',
          tabLabel: 'File',
          title: 'Files',
          icon: const TabIcon.static(
            child: Icon(Icons.insert_drive_file_outlined, size: 24),
          ),
          bodyBuilder: (BuildContext context) => ListView(
            padding: EdgeInsets.zero,
            children: const <Widget>[
              ListTile(
                leading: Icon(Icons.description_outlined),
                title: Text('glass tab bar spec.pdf'),
                subtitle: Text('2.4 MB'),
              ),
              ListTile(
                leading: Icon(Icons.description_outlined),
                title: Text('attach sheet motion.mov'),
                subtitle: Text('18 MB'),
              ),
              ListTile(
                leading: Icon(Icons.folder_outlined),
                title: Text('Internal storage'),
              ),
            ],
          ),
        ),
        AttachSheetPage(
          id: 'location',
          tabLabel: 'Location',
          title: 'Location',
          icon: const TabIcon.static(
            child: Icon(Icons.location_on_outlined, size: 24),
          ),
          bodyBuilder: (BuildContext context) => const Center(
            child: Text('Map slot'),
          ),
        ),
      ],
    );
  }

  /// Placeholder emoji grid for the panel's emoji page slot.
  Widget _buildEmojiGrid(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(8, 8, 8, EmojiPanel.gridBottomPadding(0)),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
      ),
      itemCount: _demoEmoji.length,
      itemBuilder: (BuildContext context, int index) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _appendEmoji(_demoEmoji[index]),
        child: Center(
          child: Text(_demoEmoji[index],
              style: const TextStyle(fontSize: 24)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color iconColor =
        TelegramTheme.colorOf(context, TelegramColorKey.chat_messagePanelIcons);
    final double panelInset = _emojiPanelOpen ? kEmojiPanelDefaultHeight : 0.0;
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
                    padding: EdgeInsets.fromLTRB(
                        12,
                        12,
                        12,
                        kChatInputBarHeightDp +
                            kChatInputBubbleBottomGapDp +
                            16 +
                            panelInset),
                    itemCount: _messages.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _Bubble(_messages[_messages.length - 1 - index]),
                  ),
                ),
                // The composed input fills the chat area so the record
                // overlay (lock pill, video preview) can cover it; the bar
                // docks to its bottom, with the 9dp Java island gap applied
                // here (the host's job, CIVC:185). When the emoji panel is
                // open the whole input rides up by the panel height — the
                // demo's stand-in for the IME inset.
                AnimatedPositioned(
                  duration: kEmojiPanelSwitchDuration,
                  curve: TgCurves.easeOutQuint,
                  left: 8,
                  right: 8,
                  top: 0,
                  bottom: kChatInputBubbleBottomGapDp + panelInset,
                  child: ChatInput(
                    controller: _barController,
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
                    emojiSlot: _SlotButton(
                      onTap: _toggleEmojiPanel,
                      child: Icon(
                        _emojiPanelOpen
                            ? Icons.keyboard_alt_outlined
                            : Icons.emoji_emotions_outlined,
                        color: iconColor,
                      ),
                    ),
                    attachSlot: _SlotButton(
                      onTap: _openAttachSheet,
                      child: Icon(Icons.attach_file_rounded, color: iconColor),
                    ),
                  ),
                ),
                // The emoji/GIF/sticker panel chrome, slid in under the input
                // like the Android keyboard swap. Content pipelines are
                // slots: the emoji page gets a placeholder grid, GIFs and
                // stickers get labeled stand-ins.
                AnimatedPositioned(
                  duration: kEmojiPanelSwitchDuration,
                  curve: TgCurves.easeOutQuint,
                  left: 0,
                  right: 0,
                  height: kEmojiPanelDefaultHeight,
                  bottom: _emojiPanelOpen ? 0 : -kEmojiPanelDefaultHeight,
                  child: EmojiPanel(
                    emojiBuilder: _buildEmojiGrid,
                    gifsBuilder: (BuildContext context) =>
                        const Center(child: Text('GIF search slot')),
                    stickersBuilder: (BuildContext context) =>
                        const Center(child: Text('Sticker sets slot')),
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

/// A 44x44 tappable wrapper for the input bar's emoji/attach icon slots.
class _SlotButton extends StatelessWidget {
  const _SlotButton({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(child: child),
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
