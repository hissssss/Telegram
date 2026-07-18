// Tests for lib/src/components/chat_input/chat_input.dart — the composed
// bar + button + overlay state machine (ChatActivityEnterView.java, cited as
// CAEV):
//
//  * typing morphs the button to send; send tap emits the trimmed draft and
//    clears the field (CAEV:8153-8189, 12233-12295);
//  * hold-to-record mounts the overlay, drives the clock, and
//    release-to-send completes with mode + duration (CAEV:895-956,
//    3074-3121);
//  * slide-to-zero cancels mid-drag (CAEV:3158-3169) and release below the
//    0.45 threshold cancels (CAEV:3048-3062);
//  * dragging up 57dp locks; the overlay persists after release, the button
//    shows the send plane, and CANCEL / send resolve the locked recording
//    (CAEV:2094-2114, 2108, 14110-14117).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/chat_input/chat_input.dart';
import 'package:telegram_ui/src/components/chat_input/chat_input_bar.dart';
import 'package:telegram_ui/src/components/chat_input/record_overlay.dart';
import 'package:telegram_ui/src/components/chat_input/record_send_button.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

Widget _host(Widget child) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: 400, height: 600, child: child),
      ),
    ),
  );
}

ChatInputState _state(WidgetTester tester) =>
    tester.state<ChatInputState>(find.byType(ChatInput));

Offset _buttonCenter(WidgetTester tester) =>
    tester.getCenter(find.byType(RecordSendButton));

/// Presses the record button and pumps past the 150ms hold so the recording
/// arms; returns the live gesture.
Future<TestGesture> _armRecording(WidgetTester tester) async {
  final TestGesture gesture = await tester.startGesture(_buttonCenter(tester));
  await tester.pump(kRecordSendHoldDelay);
  await tester.pump();
  return gesture;
}

void main() {
  group('idle / text flow', () {
    testWidgets('starts idle with no overlay', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ChatInput()));
      expect(_state(tester).phase, ChatInputPhase.idle);
      expect(find.byType(RecordOverlay), findsNothing);
      expect(find.byType(ChatInputBar), findsOneWidget);
      expect(find.byType(RecordSendButton), findsOneWidget);
    });

    testWidgets('typing flips the button to send; tap sends trimmed and clears',
        (WidgetTester tester) async {
      final ChatInputBarController controller = ChatInputBarController();
      addTearDown(controller.dispose);
      final List<String> sent = <String>[];
      await tester.pumpWidget(_host(ChatInput(
        controller: controller,
        onSendMessage: sent.add,
      )));

      controller.text = '  hello world  ';
      await tester.pump();
      final RecordSendButtonState button =
          tester.state<RecordSendButtonState>(find.byType(RecordSendButton));
      await tester.pumpAndSettle();
      expect(button.visualState, RecordSendState.send);

      await tester.tap(find.byType(RecordSendButton));
      await tester.pumpAndSettle();
      expect(sent, <String>['hello world']);
      expect(controller.text, isEmpty);
      expect(button.visualState, RecordSendState.mic);
    });

    testWidgets('whitespace-only draft neither morphs nor sends',
        (WidgetTester tester) async {
      final ChatInputBarController controller = ChatInputBarController();
      addTearDown(controller.dispose);
      final List<String> sent = <String>[];
      await tester.pumpWidget(_host(ChatInput(
        controller: controller,
        onSendMessage: sent.add,
      )));
      controller.text = '   ';
      await tester.pumpAndSettle();
      expect(
        tester
            .state<RecordSendButtonState>(find.byType(RecordSendButton))
            .visualState,
        RecordSendState.mic,
      );
      expect(sent, isEmpty);
    });
  });

  group('record flow', () {
    testWidgets('hold arms a recording, mounts the overlay and runs the clock',
        (WidgetTester tester) async {
      RecordMode? started;
      await tester.pumpWidget(_host(ChatInput(
        onRecordingStarted: (RecordMode mode) => started = mode,
      )));

      final TestGesture gesture = await _armRecording(tester);
      final ChatInputState state = _state(tester);
      expect(started, RecordMode.voice);
      expect(state.phase, ChatInputPhase.recording);
      expect(find.byType(RecordOverlay), findsOneWidget);

      // The 100ms tick clock advances the overlay's elapsed.
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        state.debugOverlayController.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 500)),
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('release-to-send completes with mode and duration',
        (WidgetTester tester) async {
      RecordMode? completedMode;
      Duration? completedDuration;
      int canceled = 0;
      await tester.pumpWidget(_host(ChatInput(
        onRecordingComplete: (RecordMode mode, Duration duration) {
          completedMode = mode;
          completedDuration = duration;
        },
        onRecordingCanceled: () => canceled++,
      )));

      final TestGesture gesture = await _armRecording(tester);
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await tester.pump();

      expect(completedMode, RecordMode.voice);
      expect(completedDuration,
          greaterThanOrEqualTo(const Duration(seconds: 2)));
      expect(canceled, 0);
      expect(_state(tester).phase, ChatInputPhase.idle);
      expect(find.byType(RecordOverlay), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('sliding to zero cancels mid-drag (CAEV:3158-3169)',
        (WidgetTester tester) async {
      int canceled = 0;
      int completed = 0;
      await tester.pumpWidget(_host(ChatInput(
        onRecordingCanceled: () => canceled++,
        onRecordingComplete: (RecordMode m, Duration d) => completed++,
      )));

      final TestGesture gesture = await _armRecording(tester);
      final ChatInputState state = _state(tester);
      // Slide distance = min(400 * 0.35, 140) = 140dp; drag left past it.
      await gesture.moveBy(const Offset(-150, 0));
      await tester.pump();
      expect(state.debugPendingCancel, isTrue);
      expect(find.byType(RecordOverlay), findsNothing);
      // Cancel resolves on the release the button still tracks.
      expect(canceled, 0);
      await gesture.up();
      await tester.pump();
      expect(canceled, 1);
      expect(completed, 0);
      expect(state.phase, ChatInputPhase.idle);
      await tester.pumpAndSettle();
    });

    testWidgets('release below the 0.45 slide threshold cancels (CAEV:3048-3062)',
        (WidgetTester tester) async {
      int canceled = 0;
      int completed = 0;
      await tester.pumpWidget(_host(ChatInput(
        onRecordingCanceled: () => canceled++,
        onRecordingComplete: (RecordMode m, Duration d) => completed++,
      )));

      final TestGesture gesture = await _armRecording(tester);
      // Progress = 1 - 100/140 ≈ 0.286 < 0.45: still recording, cancels on
      // release.
      await gesture.moveBy(const Offset(-100, 0));
      await tester.pump();
      final ChatInputState state = _state(tester);
      expect(state.debugPendingCancel, isFalse);
      expect(state.phase, ChatInputPhase.recording);
      await gesture.up();
      await tester.pump();
      expect(canceled, 1);
      expect(completed, 0);
      await tester.pumpAndSettle();
    });
  });

  group('lock flow', () {
    Future<TestGesture> lockRecording(WidgetTester tester) async {
      final TestGesture gesture = await _armRecording(tester);
      // Drag up past the 57dp lock threshold (CAEV:2094-2114).
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      return gesture;
    }

    testWidgets('locking persists the overlay after release',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ChatInput()));
      final TestGesture gesture = await lockRecording(tester);
      final ChatInputState state = _state(tester);
      expect(state.debugOverlayController.locked, isTrue);
      expect(state.phase, ChatInputPhase.recording);

      await gesture.up();
      await tester.pump();
      expect(state.phase, ChatInputPhase.lockedRecording);
      expect(find.byType(RecordOverlay), findsOneWidget);
      // The bar button morphed to the send plane (sendButtonVisible,
      // CAEV:2108). No pumpAndSettle while the overlay is mounted — its dot
      // pulse repeats forever; bounded pumps instead.
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        tester
            .state<RecordSendButtonState>(find.byType(RecordSendButton))
            .visualState,
        RecordSendState.send,
      );
      // The clock keeps running hands-free.
      final Duration before = state.debugOverlayController.elapsed;
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.debugOverlayController.elapsed, greaterThan(before));
      // Resolve the recording so no clock Timer outlives the test.
      await tester.tap(find.byType(RecordSendButton));
      await tester.pump();
      expect(state.phase, ChatInputPhase.idle);
      await tester.pumpAndSettle();
    });

    testWidgets('CANCEL tap cancels a locked recording (CAEV:14110-14117)',
        (WidgetTester tester) async {
      int canceled = 0;
      await tester.pumpWidget(_host(ChatInput(
        onRecordingCanceled: () => canceled++,
      )));
      final TestGesture gesture = await lockRecording(tester);
      await gesture.up();
      // Let the CANCEL morph fade the button in.
      await tester.pump(kRecordCancelMorphDuration);
      await tester.pump();

      await tester.tap(find.text('CANCEL'));
      await tester.pump();
      expect(canceled, 1);
      expect(_state(tester).phase, ChatInputPhase.idle);
      expect(find.byType(RecordOverlay), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('send tap completes a locked recording',
        (WidgetTester tester) async {
      RecordMode? completedMode;
      Duration? completedDuration;
      await tester.pumpWidget(_host(ChatInput(
        onRecordingComplete: (RecordMode mode, Duration duration) {
          completedMode = mode;
          completedDuration = duration;
        },
      )));
      final TestGesture gesture = await lockRecording(tester);
      await gesture.up();
      // Bounded pumps only: the mounted overlay's dot pulse never settles.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byType(RecordSendButton));
      await tester.pump();
      expect(completedMode, RecordMode.voice);
      expect(completedDuration, greaterThan(Duration.zero));
      expect(_state(tester).phase, ChatInputPhase.idle);
      expect(find.byType(RecordOverlay), findsNothing);
      await tester.pumpAndSettle();
    });
  });

  group('bar chrome while recording', () {
    testWidgets('hint is suppressed and slots fade out during a recording',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ChatInput(
        hintText: 'Message',
        emojiSlot: SizedBox.square(dimension: 24, key: Key('emoji')),
      )));
      expect(find.text('Message'), findsOneWidget);

      final TestGesture gesture = await _armRecording(tester);
      expect(find.text('Message'), findsNothing);
      await tester.pump(kRecordSendIconsDuration);
      final AnimatedOpacity fade = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byKey(const Key('emoji')),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(fade.opacity, 0.0);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Message'), findsOneWidget);
    });

    testWidgets('mode toggle reports through onRecordModeChanged',
        (WidgetTester tester) async {
      final List<RecordMode> modes = <RecordMode>[];
      await tester.pumpWidget(_host(ChatInput(onRecordModeChanged: modes.add)));
      await tester.tap(find.byType(RecordSendButton));
      await tester.pumpAndSettle();
      expect(modes, <RecordMode>[RecordMode.video]);
      expect(_state(tester).recordMode, RecordMode.video);
    });
  });
}
