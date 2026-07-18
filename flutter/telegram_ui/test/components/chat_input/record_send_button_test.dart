// Tests for lib/src/components/chat_input/record_send_button.dart — the
// `audioVideoButtonContainer` port (ChatActivityEnterView.java, cited as
// CAEV), golden-free:
//
//  * constants mirror the Java values (44dp slot, 38/19/3 send circle, 150ms
//    hold, 220/150ms send morph at scale 0.1, 41+30 circle radii, 300/360ms
//    enter/exit);
//  * recordCircleScaleFor reproduces the manual overshoot mapping
//    (CAEV:2152-2160);
//  * state transitions across {mic, video, send, recording};
//  * tap toggle: mode swap, onModeChanged, KEYBOARD_TAP haptic
//    (CAEV:3063-3073), and the hasVideo=false immediate-record path
//    (CAEV:3018);
//  * long-press arming: 150ms delay, onRecordStart with the active mode,
//    onRecordEnd on release (CAEV:3013-3016, 895-956);
//  * send morph values at the t extremes (CAEV:8153-8189, 8604);
//  * record circle enter scale values (300ms decelerate through the
//    overshoot map, CAEV:8925-8961) and amplitude-driven radius
//    (CAEV:2182).

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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
      child: Center(child: child),
    ),
  );
}

Finder _button() => find.byType(RecordSendButton);

RecordSendButtonState _state(WidgetTester tester) =>
    tester.state<RecordSendButtonState>(_button());

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      // CAEV:6410, 3209: DEFAULT_HEIGHT 44dp container.
      expect(kRecordSendButtonSize, 44.0);
      // CAEV:3188-3192: dpf2(38) circle, radius dpf2(19), margin dpf2(3).
      expect(kRecordSendCircleSize, 38.0);
      expect(kRecordSendCircleRadius, 19.0);
      expect(kRecordSendCircleMargin, 3.0);
      // CAEV:3387, 3404-3405: 24dp lottie with 10dp padding.
      expect(kRecordSendIconSize, 24.0);
      expect(kRecordSendIconPadding, 10.0);
      // CAEV:3016: runOnUIThread(recordAudioVideoRunnable, 150).
      expect(kRecordSendHoldDelay, const Duration(milliseconds: 150));
      // AIV:63-69 + voice_and_video.json "fr": 60 — 30 frames each way.
      expect(kRecordSendModeSwitchDuration, const Duration(milliseconds: 500));
      // CAEV:8187-8189 / 8604 / 8153-8155.
      expect(kRecordSendMorphDuration, const Duration(milliseconds: 220));
      expect(kRecordSendMorphReverseDuration, const Duration(milliseconds: 150));
      expect(kRecordSendMorphMinScale, 0.1);
      // CAEV:1960-1961: dpf2(41) + dp(30) * amplitude.
      expect(kRecordCircleRadius, 41.0);
      expect(kRecordCircleAmplitudeRadius, 30.0);
      // CAEV:8925-8927 / 9605-9606 / 9593-9594.
      expect(kRecordCircleEnterDuration, const Duration(milliseconds: 300));
      expect(kRecordCircleExitDuration, const Duration(milliseconds: 360));
      expect(kRecordSendIconsDuration, const Duration(milliseconds: 150));
      expect(kRecordSendIconsReturnDelay, const Duration(milliseconds: 200));
      // CAEV:2139-2140: cx = width - dp2(26), cy 24dp above the bottom.
      expect(kRecordCircleCenterFromRight, 26.0);
      expect(kRecordCircleCenterFromBottom, 24.0);
      expect(kRecordCircleIconSize, 24.0);
      // CAEV:2025-2030: 100 + 500 * 0.55.
      expect(kRecordAmplitudeSmoothing, const Duration(milliseconds: 375));
      // CAEV:2269-2274; WaveDrawable.java:32-33; BlobDrawable.java:19-28.
      expect(kRecordWaveTinyMinRadius, 47.0);
      expect(kRecordWaveTinyMaxRadius, moreOrLessEquals(56.0));
      expect(kRecordWaveBigMinRadius, 50.0);
      expect(kRecordWaveBigMaxRadius, moreOrLessEquals(57.2));
      expect(kRecordWaveBigAlpha, 0.30);
      expect(kRecordWaveTinyAlpha, 0.15);
      expect(kRecordWaveBigScaleMin, 0.878);
      expect(kRecordWaveTinyScaleMin, 0.926);
    });
  });

  group('recordCircleScaleFor', () {
    test('reproduces the manual overshoot mapping (CAEV:2152-2160)', () {
      expect(recordCircleScaleFor(0.0), 0.0);
      expect(recordCircleScaleFor(0.25), moreOrLessEquals(0.5));
      expect(recordCircleScaleFor(0.5), moreOrLessEquals(1.0));
      // Dips to 0.9 at 0.75 ...
      expect(recordCircleScaleFor(0.625), moreOrLessEquals(0.95));
      expect(recordCircleScaleFor(0.75), moreOrLessEquals(0.9));
      // ... and recovers to 1.0.
      expect(recordCircleScaleFor(0.875), moreOrLessEquals(0.95));
      expect(recordCircleScaleFor(1.0), moreOrLessEquals(1.0));
    });

    test('is continuous at the segment joints', () {
      expect(recordCircleScaleFor(0.4999999), moreOrLessEquals(recordCircleScaleFor(0.5000001), epsilon: 1e-5));
      expect(recordCircleScaleFor(0.7499999), moreOrLessEquals(recordCircleScaleFor(0.7500001), epsilon: 1e-5));
    });
  });

  group('geometry', () {
    testWidgets('the button is a 44dp square', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const RecordSendButton()));
      expect(tester.getSize(_button()), const Size(44, 44));
    });
  });

  group('state transitions', () {
    testWidgets('mic by default, video when mode is video', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const RecordSendButton()));
      expect(_state(tester).visualState, RecordSendState.mic);
      expect(_state(tester).mode, RecordMode.voice);

      await tester.pumpWidget(_host(const RecordSendButton(mode: RecordMode.video)));
      await tester.pumpAndSettle();
      expect(_state(tester).visualState, RecordSendState.video);
      expect(_state(tester).mode, RecordMode.video);
    });

    testWidgets('hasText produces the send state, clearing restores mic', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const RecordSendButton()));
      await tester.pumpWidget(_host(const RecordSendButton(hasText: true)));
      expect(_state(tester).visualState, RecordSendState.send);
      await tester.pumpAndSettle();

      await tester.pumpWidget(_host(const RecordSendButton()));
      await tester.pumpAndSettle();
      expect(_state(tester).visualState, RecordSendState.mic);
    });

    testWidgets('hold enters recording, release leaves it', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const RecordSendButton()));
      final TestGesture gesture = await tester.startGesture(tester.getCenter(_button()));
      await tester.pump(kRecordSendHoldDelay);
      expect(_state(tester).visualState, RecordSendState.recording);
      expect(_state(tester).isRecording, isTrue);

      await gesture.up();
      await tester.pump();
      expect(_state(tester).visualState, RecordSendState.mic);
      expect(_state(tester).isRecording, isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('mode is coerced to voice when hasVideo turns off', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const RecordSendButton(mode: RecordMode.video)));
      expect(_state(tester).visualState, RecordSendState.video);
      await tester.pumpWidget(_host(const RecordSendButton(mode: RecordMode.video, hasVideo: false)));
      await tester.pumpAndSettle();
      expect(_state(tester).visualState, RecordSendState.mic);
      expect(_state(tester).mode, RecordMode.voice);
    });
  });

  group('tap toggle (CAEV:3063-3073)', () {
    testWidgets('a quick tap flips voice <-> video and reports it', (WidgetTester tester) async {
      final List<RecordMode> modes = <RecordMode>[];
      final List<RecordMode> started = <RecordMode>[];
      await tester.pumpWidget(_host(RecordSendButton(
        onModeChanged: modes.add,
        onRecordStart: started.add,
      )));

      await tester.tap(_button());
      await tester.pumpAndSettle();
      expect(modes, <RecordMode>[RecordMode.video]);
      expect(_state(tester).visualState, RecordSendState.video);
      expect(_state(tester).debugModeSwapFactor, 1.0);

      await tester.tap(_button());
      await tester.pumpAndSettle();
      expect(modes, <RecordMode>[RecordMode.video, RecordMode.voice]);
      expect(_state(tester).visualState, RecordSendState.mic);
      expect(_state(tester).debugModeSwapFactor, 0.0);

      // A tap released before the 150ms hold never arms a recording.
      expect(started, isEmpty);
    });

    testWidgets('the swap animates over 500ms (30 lottie frames)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const RecordSendButton()));
      await tester.tap(_button());
      await tester.pump();
      expect(_state(tester).debugModeSwapFactor, 0.0);
      await tester.pump(const Duration(milliseconds: 250));
      expect(_state(tester).debugModeSwapFactor, moreOrLessEquals(0.5, epsilon: 1e-6));
      await tester.pump(const Duration(milliseconds: 250));
      expect(_state(tester).debugModeSwapFactor, 1.0);
    });

    testWidgets('emits the KEYBOARD_TAP haptic (CAEV:3070)', (WidgetTester tester) async {
      final List<MethodCall> calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
          (MethodCall call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(_host(const RecordSendButton()));
      await tester.tap(_button());
      await tester.pumpAndSettle();
      // Flutter's mediumImpact maps to HapticFeedbackConstants.KEYBOARD_TAP
      // on Android.
      expect(
        calls.where((MethodCall call) =>
            call.method == 'HapticFeedback.vibrate' &&
            call.arguments == 'HapticFeedbackType.mediumImpact'),
        hasLength(1),
      );
    });

    testWidgets('hasVideo=false records at pointer-down and never toggles (CAEV:3018)',
        (WidgetTester tester) async {
      final List<RecordMode> modes = <RecordMode>[];
      final List<RecordMode> started = <RecordMode>[];
      int ended = 0;
      await tester.pumpWidget(_host(RecordSendButton(
        hasVideo: false,
        onModeChanged: modes.add,
        onRecordStart: started.add,
        onRecordEnd: () => ended++,
      )));

      final TestGesture gesture = await tester.startGesture(tester.getCenter(_button()));
      // No 150ms wait: the runnable ran directly at ACTION_DOWN.
      expect(started, <RecordMode>[RecordMode.voice]);
      await tester.pump();
      expect(_state(tester).visualState, RecordSendState.recording);

      await gesture.up();
      await tester.pump();
      expect(ended, 1);
      expect(modes, isEmpty);
      await tester.pumpAndSettle();
    });
  });

  group('long press (CAEV:3013-3016, 895-956)', () {
    testWidgets('arms only after 150ms and reports the voice mode', (WidgetTester tester) async {
      final List<RecordMode> started = <RecordMode>[];
      int ended = 0;
      await tester.pumpWidget(_host(RecordSendButton(
        onRecordStart: started.add,
        onRecordEnd: () => ended++,
      )));

      final TestGesture gesture = await tester.startGesture(tester.getCenter(_button()));
      await tester.pump(const Duration(milliseconds: 149));
      expect(started, isEmpty);
      expect(_state(tester).isRecording, isFalse);

      await tester.pump(const Duration(milliseconds: 1));
      expect(started, <RecordMode>[RecordMode.voice]);
      expect(_state(tester).isRecording, isTrue);
      expect(ended, 0);

      await gesture.up();
      await tester.pump();
      expect(ended, 1);
      expect(started, hasLength(1));
      await tester.pumpAndSettle();
    });

    testWidgets('reports the video mode after a toggle', (WidgetTester tester) async {
      final List<RecordMode> started = <RecordMode>[];
      await tester.pumpWidget(_host(RecordSendButton(onRecordStart: started.add)));

      await tester.tap(_button()); // voice -> video
      await tester.pumpAndSettle();

      final TestGesture gesture = await tester.startGesture(tester.getCenter(_button()));
      await tester.pump(kRecordSendHoldDelay);
      expect(started, <RecordMode>[RecordMode.video]);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a hold in the send state never records', (WidgetTester tester) async {
      final List<RecordMode> started = <RecordMode>[];
      int sends = 0;
      await tester.pumpWidget(_host(RecordSendButton(
        hasText: true,
        onSend: () => sends++,
        onRecordStart: started.add,
      )));
      await tester.pumpAndSettle();

      final TestGesture gesture = await tester.startGesture(tester.getCenter(_button()));
      await tester.pump(const Duration(milliseconds: 400));
      expect(started, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(started, isEmpty);
    });

    testWidgets('pointer cancel drops a pending hold without toggling', (WidgetTester tester) async {
      final List<RecordMode> modes = <RecordMode>[];
      final List<RecordMode> started = <RecordMode>[];
      await tester.pumpWidget(_host(RecordSendButton(
        onModeChanged: modes.add,
        onRecordStart: started.add,
      )));

      final TestGesture gesture = await tester.startGesture(tester.getCenter(_button()));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 200));
      expect(modes, isEmpty);
      expect(started, isEmpty);
      expect(_state(tester).isRecording, isFalse);
    });
  });

  group('send morph (CAEV:8153-8189, 8604)', () {
    testWidgets('values at the t extremes', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const RecordSendButton()));
      RecordSendButtonState state = _state(tester);
      // Resting: mic fully in, send parked at scale 0.1 / alpha 0.
      expect(state.debugSendMorphFactor, 0.0);
      expect(state.debugMicVideoScale, 1.0);
      expect(state.debugMicVideoAlpha, 1.0);
      expect(state.debugSendScale, kRecordSendMorphMinScale);
      expect(state.debugSendAlpha, 0.0);

      // Text appears: 220ms morph to the opposite extreme.
      await tester.pumpWidget(_host(const RecordSendButton(hasText: true)));
      await tester.pumpAndSettle();
      state = _state(tester);
      expect(state.debugSendMorphFactor, 1.0);
      expect(state.debugMicVideoScale, moreOrLessEquals(kRecordSendMorphMinScale));
      expect(state.debugMicVideoAlpha, 0.0);
      expect(state.debugSendScale, 1.0);
      expect(state.debugSendAlpha, 1.0);

      // Text cleared: back to the resting extreme.
      await tester.pumpWidget(_host(const RecordSendButton()));
      await tester.pumpAndSettle();
      state = _state(tester);
      expect(state.debugSendMorphFactor, 0.0);
      expect(state.debugMicVideoScale, 1.0);
      expect(state.debugSendScale, kRecordSendMorphMinScale);
    });

    testWidgets('forward runs 220ms, reverse 150ms', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const RecordSendButton()));
      await tester.pumpWidget(_host(const RecordSendButton(hasText: true)));
      await tester.pump();
      expect(_state(tester).debugSendMorphFactor, 0.0);
      await tester.pump(const Duration(milliseconds: 219));
      expect(_state(tester).debugSendMorphFactor, lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 1));
      expect(_state(tester).debugSendMorphFactor, 1.0);

      await tester.pumpWidget(_host(const RecordSendButton()));
      await tester.pump();
      expect(_state(tester).debugSendMorphFactor, 1.0);
      await tester.pump(const Duration(milliseconds: 149));
      expect(_state(tester).debugSendMorphFactor, greaterThan(0.0));
      await tester.pump(const Duration(milliseconds: 1));
      expect(_state(tester).debugSendMorphFactor, 0.0);
    });

    testWidgets('tap in the send state fires onSend once', (WidgetTester tester) async {
      int sends = 0;
      await tester.pumpWidget(_host(RecordSendButton(hasText: true, onSend: () => sends++)));
      await tester.pumpAndSettle();
      await tester.tap(_button());
      await tester.pumpAndSettle();
      expect(sends, 1);
    });
  });

  group('record circle (CAEV:1945-2555, 8925-8961)', () {
    testWidgets('enter scale runs 300ms decelerate through the overshoot map',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const RecordSendButton()));
      final RecordSendButtonState state = _state(tester);
      final TestGesture gesture = await tester.startGesture(tester.getCenter(_button()));

      await tester.pump(kRecordSendHoldDelay); // Arms; animation not yet ticked.
      expect(state.debugRecordCircleEnterFactor, 0.0);
      expect(state.debugRecordCircleScale, 0.0);
      expect(state.debugRecordCircleRadius, 0.0);

      // 150/300ms: DecelerateInterpolator(0.5) = 1 - 0.5^2 = 0.75, which the
      // overshoot map turns into the 0.9 dip (CAEV:2152-2160).
      await tester.pump(const Duration(milliseconds: 150));
      expect(state.debugRecordCircleEnterFactor, moreOrLessEquals(0.75, epsilon: 1e-6));
      expect(state.debugRecordCircleScale, moreOrLessEquals(0.9, epsilon: 1e-6));
      expect(state.debugRecordCircleRadius, moreOrLessEquals(kRecordCircleRadius * 0.9, epsilon: 1e-6));

      // Fully entered: sc = 1, radius = 41dp at amplitude 0.
      await tester.pump(const Duration(milliseconds: 150));
      expect(state.debugRecordCircleEnterFactor, 1.0);
      expect(state.debugRecordCircleScale, 1.0);
      expect(state.debugRecordCircleRadius, kRecordCircleRadius);
      expect(state.debugRecordCircleAlpha, 1.0);
      expect(state.debugBarIconsFactor, 1.0); // Bar content fully hidden.

      await gesture.up();
      await tester.pumpAndSettle();
      // Exit finished: everything reset for the next enter.
      expect(state.debugRecordCircleEnterFactor, 0.0);
      expect(state.debugRecordCircleScale, 0.0);
      expect(state.debugBarIconsFactor, 0.0);
      expect(state.visualState, RecordSendState.mic);
    });

    testWidgets('amplitude drives the radius: 41 + 30 * amplitude (CAEV:2182)',
        (WidgetTester tester) async {
      final ValueNotifier<double> amplitude = ValueNotifier<double>(0.0);
      addTearDown(amplitude.dispose);
      await tester.pumpWidget(_host(RecordSendButton(amplitude: amplitude)));
      final RecordSendButtonState state = _state(tester);

      final TestGesture gesture = await tester.startGesture(tester.getCenter(_button()));
      await tester.pump(kRecordSendHoldDelay);
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.debugRecordCircleRadius, kRecordCircleRadius);

      amplitude.value = 1.0;
      // Smoothing: linear over 375ms (CAEV:2025-2030).
      await tester.pump(kRecordAmplitudeSmoothing);
      await tester.pump(kRecordAmplitudeSmoothing);
      expect(
        state.debugRecordCircleRadius,
        moreOrLessEquals(kRecordCircleRadius + kRecordCircleAmplitudeRadius),
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('exit fades the circle out over 360ms', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const RecordSendButton()));
      final RecordSendButtonState state = _state(tester);
      final TestGesture gesture = await tester.startGesture(tester.getCenter(_button()));
      await tester.pump(kRecordSendHoldDelay);
      await tester.pump(const Duration(milliseconds: 300));

      await gesture.up();
      await tester.pump();
      // Exit begins: still opaque (alpha only fades past exit 0.6).
      expect(state.debugRecordCircleAlpha, 1.0);
      await tester.pump(kRecordCircleExitDuration);
      expect(state.debugRecordCircleAlpha, 0.0);
      expect(state.debugRecordCircleRadius, 0.0);
      await tester.pumpAndSettle();
    });

    testWidgets('re-arming mid-exit restarts the circle cleanly', (WidgetTester tester) async {
      final List<RecordMode> started = <RecordMode>[];
      await tester.pumpWidget(_host(RecordSendButton(onRecordStart: started.add)));
      final RecordSendButtonState state = _state(tester);

      TestGesture gesture = await tester.startGesture(tester.getCenter(_button()));
      await tester.pump(kRecordSendHoldDelay);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100)); // Mid-exit.

      gesture = await tester.startGesture(tester.getCenter(_button()));
      await tester.pump(kRecordSendHoldDelay);
      expect(started, hasLength(2));
      expect(state.isRecording, isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.debugRecordCircleScale, 1.0);
      expect(state.debugRecordCircleAlpha, 1.0);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(state.debugRecordCircleEnterFactor, 0.0);
    });
  });
}
