// Tests for lib/src/components/chat_input/record_overlay.dart — the
// recording chrome port (ChatActivityEnterView.java cited as CAEV,
// InstantCameraView.java as ICV, AndroidUtilities.java as AU), golden-free:
//
//  * constants mirror the Java values (44dp panel, 45/13/28/6 layout, 15dp
//    texts, 0.35/140dp cancel distance, 0.45 release threshold, 57dp lock,
//    36/18/50 pill, -8dp/3dp video ring, 60s cap);
//  * slide threshold math on the controller (CAEV:3135-3169, 3048-3062);
//  * lock trigger: 57dp drag, 0.7 slide gate, one-shot onLocked
//    (CAEV:2094-2114);
//  * formatRecordTimer reproduces formatTimerDurationFast (AU:986-1001) —
//    minutes unpadded, 2-digit seconds, comma, single tenths digit;
//  * dot blink cadence via pump: 600ms out + 600ms in, linear, starting at
//    alpha 1 (CAEV:1032-1049);
//  * lock pill geometry across rest / mid-drag / locked, including the
//    250ms snap and the 350ms/100ms-delay translation return
//    (CAEV:1385-1391, 1521, 4607-4630);
//  * CANCEL morph and tap (CAEV:14074-14122);
//  * round-video circle geometry: diameter rules (AU:2800-2810;
//    ICV:509-526) and the progress ring math (ICV:284-287, 612-629).
//
// No pumpAndSettle anywhere: the dot pulse and arrow bob repeat forever.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/chat_input/record_overlay.dart';
import 'package:telegram_ui/src/components/chat_input/record_send_button.dart'
    show RecordMode;
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

Widget _host(Widget child) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  );
}

RecordOverlayState _state(WidgetTester tester) =>
    tester.state<RecordOverlayState>(find.byType(RecordOverlay));

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      // CAEV:9690-9700: record panel frames.
      expect(kRecordOverlayBarHeight, 44.0);
      expect(kRecordSlideTextLeftMargin, 45.0);
      expect(kRecordTimeContainerPaddingLeft, 13.0);
      expect(kRecordDotSlotSize, 28.0);
      expect(kRecordTimerLeftMargin, 6.0);
      // CAEV:1055, 1032-1049: the dot.
      expect(kRecordDotRadius, 5.0);
      expect(kRecordDotPulseHalfDuration, const Duration(milliseconds: 600));
      expect(kRecordDotPulsePeriod, const Duration(milliseconds: 1200));
      // CAEV:14195: timer text.
      expect(kRecordTimerFontSize, 15.0);
      // CAEV:3135-3141, 3048-3062: slide-to-cancel.
      expect(kRecordSlideCancelWidthFraction, 0.35);
      expect(kRecordSlideCancelMaxDistance, 140.0);
      expect(kRecordSlideCancelReleaseThreshold, 0.45);
      // CAEV:13958-13989, 14024-14091: slide text and chevron.
      expect(kRecordSlideTextFontSize, 15.0);
      expect(kRecordSlideArrowStrokeWidth, 1.6);
      expect(kRecordSlideArrowWidth, 4.0);
      expect(kRecordSlideArrowHeight, 10.0);
      expect(kRecordSlideArrowGap, 10.0);
      expect(kRecordSlideArrowBobAmplitude, 6.0);
      expect(kRecordSlideArrowBobPeriod, const Duration(seconds: 1));
      expect(kRecordSlideArrowBobGate, 0.8);
      expect(kRecordCancelHitInset, 16.0);
      expect(kRecordCancelMorphDuration, const Duration(milliseconds: 300));
      // CAEV:2094-2114, 1354-1391, 1521, 1683-1699, 4607-4630: the lock.
      expect(kRecordLockDistance, 57.0);
      expect(kRecordLockSlideGate, 0.7);
      expect(kRecordLockPillWidth, 36.0);
      expect(kRecordLockPillRadius, 18.0);
      expect(kRecordLockPillRestHeight, 50.0);
      expect(kRecordLockPillLockedHeight, 36.0);
      expect(kRecordLockGlassPadding, 3.0);
      expect(kRecordLockCenterFromRight, 26.0);
      expect(kRecordLockPillTopFromBottom, 134.0);
      expect(kRecordLockSnapDuration, const Duration(milliseconds: 250));
      expect(kRecordLockTranslateDuration, const Duration(milliseconds: 350));
      expect(kRecordLockTranslateDelay, const Duration(milliseconds: 100));
      expect(kRecordLockPauseBarGap, 3.3);
      // AU:2800-2810; ICV:284-287, 509-526, 612-629: round video.
      expect(kRoundVideoDiameterInset, 28.0);
      expect(kRoundVideoFallbackFactor, 0.6);
      expect(kRoundVideoFallbackAspect, 1.3);
      expect(kRoundVideoRingInset, 8.0);
      expect(kRoundVideoRingStrokeWidth, 3.0);
      expect(kRoundVideoMaxDuration, const Duration(seconds: 60));
    });
  });

  group('formatRecordTimer (AU:986-1001)', () {
    test('m:ss with a single tenths digit', () {
      expect(formatRecordTimer(Duration.zero), '0:00,0');
      expect(formatRecordTimer(const Duration(milliseconds: 99)), '0:00,0');
      expect(formatRecordTimer(const Duration(milliseconds: 100)), '0:00,1');
      expect(formatRecordTimer(const Duration(milliseconds: 999)), '0:00,9');
      expect(formatRecordTimer(const Duration(milliseconds: 1500)), '0:01,5');
      expect(formatRecordTimer(const Duration(milliseconds: 59990)), '0:59,9');
      expect(formatRecordTimer(const Duration(milliseconds: 65430)), '1:05,4');
      expect(formatRecordTimer(const Duration(minutes: 10, seconds: 3)), '10:03,0');
    });

    test('hours branch h:mm:ss,d', () {
      expect(
        formatRecordTimer(const Duration(hours: 1, minutes: 1, seconds: 1, milliseconds: 70)),
        '1:01:01,0',
      );
      expect(
        formatRecordTimer(const Duration(hours: 1, minutes: 1, seconds: 1, milliseconds: 700)),
        '1:01:01,7',
      );
      expect(formatRecordTimer(const Duration(minutes: 59, seconds: 59)), '59:59,0');
      expect(formatRecordTimer(const Duration(minutes: 60)), '1:00:00,0');
    });
  });

  group('slide threshold math (CAEV:3135-3169, 3048-3062)', () {
    test('cancel distance is 35% of width capped at 140dp', () {
      expect(recordSlideCancelDistance(300.0), 105.0);
      expect(recordSlideCancelDistance(400.0), 140.0);
      expect(recordSlideCancelDistance(1000.0), 140.0);
    });

    test('slideProgress = clamp(1 + dx / dist, 0, 1)', () {
      final RecordOverlayController controller = RecordOverlayController()
        ..slideWidth = 400.0;
      addTearDown(controller.dispose);
      expect(controller.cancelDistance, 140.0);
      expect(controller.slideProgress, 1.0);

      controller.dragOffset = const Offset(-70.0, 0.0);
      expect(controller.slideProgress, moreOrLessEquals(0.5));
      expect(controller.slideDelta, moreOrLessEquals(-70.0)); // CAEV:1913-1921.
      expect(controller.slideCircleScale, moreOrLessEquals(0.85)); // CAEV:2176-2181.

      // Rightward drag never raises the progress past 1.
      controller.dragOffset = const Offset(50.0, 0.0);
      expect(controller.slideProgress, 1.0);

      // Beyond the distance it clamps at 0.
      controller.dragOffset = const Offset(-200.0, 0.0);
      expect(controller.slideProgress, 0.0);
    });

    test('an unmeasured width pins the progress at rest', () {
      final RecordOverlayController controller = RecordOverlayController();
      addTearDown(controller.dispose);
      controller.dragOffset = const Offset(-100.0, 0.0);
      expect(controller.slideProgress, 1.0);
    });

    test('reaching 0 fires onCancel exactly once (CAEV:3158-3169)', () {
      int cancels = 0;
      final RecordOverlayController controller =
          RecordOverlayController(onCancel: () => cancels++)..slideWidth = 400.0;
      addTearDown(controller.dispose);

      controller.dragOffset = const Offset(-139.0, 0.0);
      expect(cancels, 0);
      controller.dragOffset = const Offset(-140.0, 0.0);
      expect(cancels, 1);
      // Staying at 0 does not refire.
      controller.dragOffset = const Offset(-180.0, 0.0);
      expect(cancels, 1);
    });

    test('release cancels below 0.45 (CAEV:3048-3062)', () {
      final RecordOverlayController controller = RecordOverlayController()
        ..slideWidth = 400.0;
      addTearDown(controller.dispose);

      controller.dragOffset = const Offset(-78.4, 0.0); // progress 0.44.
      expect(controller.slideProgress, moreOrLessEquals(0.44));
      expect(controller.shouldCancelOnRelease, isTrue);

      controller.dragOffset = const Offset(-63.0, 0.0); // progress 0.55.
      expect(controller.shouldCancelOnRelease, isFalse);

      // Once locked, release never cancels (CAEV:3125-3127).
      controller.locked = true;
      controller.dragOffset = const Offset(-112.0, 0.0); // progress 0.2.
      expect(controller.shouldCancelOnRelease, isFalse);
    });
  });

  group('lock trigger (CAEV:2094-2114)', () {
    test('locks at 57dp of upward drag, one-shot onLocked', () {
      int locks = 0;
      final RecordOverlayController controller =
          RecordOverlayController(onLocked: () => locks++)..slideWidth = 400.0;
      addTearDown(controller.dispose);

      controller.dragOffset = const Offset(0.0, -56.9);
      expect(controller.locked, isFalse);
      expect(controller.lockDragProgress, moreOrLessEquals(56.9 / 57.0));
      expect(locks, 0);

      controller.dragOffset = const Offset(0.0, -57.0);
      expect(controller.locked, isTrue);
      expect(controller.lockDragProgress, 1.0);
      expect(locks, 1);

      // Further drag never refires.
      controller.dragOffset = const Offset(0.0, -80.0);
      expect(locks, 1);
    });

    test('the lock is ignored once slideProgress < 0.7 (CAEV:2103-2105)', () {
      int locks = 0;
      final RecordOverlayController controller =
          RecordOverlayController(onLocked: () => locks++)..slideWidth = 400.0;
      addTearDown(controller.dispose);

      controller.dragOffset = const Offset(-84.0, -60.0); // progress 0.4.
      expect(controller.slideProgress, moreOrLessEquals(0.4));
      expect(controller.locked, isFalse);
      expect(locks, 0);
    });

    test('an explicit locked write does not fire onLocked', () {
      int locks = 0;
      final RecordOverlayController controller =
          RecordOverlayController(onLocked: () => locks++);
      addTearDown(controller.dispose);
      controller.locked = true;
      expect(controller.locked, isTrue);
      expect(locks, 0);
    });

    test('reset clears elapsed/drag/locked but keeps the mode', () {
      final RecordOverlayController controller = RecordOverlayController(
        mode: RecordMode.video,
      )..slideWidth = 400.0;
      addTearDown(controller.dispose);
      controller
        ..elapsed = const Duration(seconds: 5)
        ..dragOffset = const Offset(0.0, -60.0);
      expect(controller.locked, isTrue);

      controller.reset();
      expect(controller.elapsed, Duration.zero);
      expect(controller.dragOffset, Offset.zero);
      expect(controller.locked, isFalse);
      expect(controller.mode, RecordMode.video);
    });
  });

  group('timer & dot (CAEV:961-1067, 14147-14218)', () {
    test('recordDotPulseAlpha is a triangle wave starting at 1', () {
      expect(recordDotPulseAlpha(0.0), 1.0);
      expect(recordDotPulseAlpha(0.25), moreOrLessEquals(0.5));
      expect(recordDotPulseAlpha(0.5), moreOrLessEquals(0.0));
      expect(recordDotPulseAlpha(0.75), moreOrLessEquals(0.5));
      expect(recordDotPulseAlpha(1.0), moreOrLessEquals(1.0));
    });

    testWidgets('renders and live-updates the m:ss,d timer text', (WidgetTester tester) async {
      final RecordOverlayController controller = RecordOverlayController(
        elapsed: const Duration(milliseconds: 65430),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(RecordOverlay(controller: controller)));
      expect(find.text('1:05,4'), findsOneWidget);

      controller.elapsed = const Duration(milliseconds: 125900);
      await tester.pump();
      expect(find.text('1:05,4'), findsNothing);
      expect(find.text('2:05,9'), findsOneWidget);
    });

    testWidgets('dot blinks 600ms out + 600ms in, linear (CAEV:1032-1049)',
        (WidgetTester tester) async {
      final RecordOverlayController controller = RecordOverlayController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(RecordOverlay(controller: controller)));
      final RecordOverlayState state = _state(tester);

      expect(state.debugDotAlpha, 1.0);
      // Arming frame: tickers started in initState take their zero-elapsed
      // first tick here.
      await tester.pump();
      expect(state.debugDotAlpha, 1.0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.debugDotAlpha, moreOrLessEquals(0.5));
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.debugDotAlpha, moreOrLessEquals(0.0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.debugDotAlpha, moreOrLessEquals(0.5));
      await tester.pump(const Duration(milliseconds: 300));
      // Full 1.2s period: back at alpha 1, continuous.
      expect(state.debugDotAlpha, moreOrLessEquals(1.0));
    });

    testWidgets('arrow bobs at rest and freezes once slid past the gate',
        (WidgetTester tester) async {
      final RecordOverlayController controller = RecordOverlayController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(RecordOverlay(controller: controller)));
      final RecordOverlayState state = _state(tester);

      expect(state.debugArrowBobOffset, 0.0);
      await tester.pump(); // Arming frame (zero-elapsed first tick).
      // 250ms into the 1s ping-pong: 6dp * triangle(0.25) = 3dp
      // (3dp / 250ms, CAEV:14055-14071).
      await tester.pump(const Duration(milliseconds: 250));
      expect(state.debugArrowBobOffset, moreOrLessEquals(3.0));

      // slideProgress 0.5 <= 0.8 gate: no bob (CAEV:14057).
      controller.dragOffset = const Offset(-70.0, 0.0);
      await tester.pump();
      expect(controller.slideProgress, moreOrLessEquals(0.5));
      expect(state.debugArrowBobOffset, 0.0);
    });

    testWidgets('the grey hint fades with slideProgress (CAEV:14074-14085)',
        (WidgetTester tester) async {
      final RecordOverlayController controller = RecordOverlayController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(RecordOverlay(controller: controller)));
      expect(find.text('Slide to cancel'), findsOneWidget);

      controller.dragOffset = const Offset(-70.0, 0.0); // progress 0.5.
      await tester.pump();
      final Opacity hint = tester.widget<Opacity>(
        find
            .ancestor(of: find.text('Slide to cancel'), matching: find.byType(Opacity))
            .first,
      );
      expect(hint.opacity, moreOrLessEquals(0.5));
    });
  });

  group('lock UI (CAEV:1385-1391, 1521, 4607-4630)', () {
    test('recordLockPillHeight: 36 + 14 * moveProgress', () {
      expect(recordLockPillHeight(0.0), 50.0);
      expect(recordLockPillHeight(0.5), 43.0);
      expect(recordLockPillHeight(1.0), 36.0);
    });

    testWidgets('pill geometry follows the drag', (WidgetTester tester) async {
      final RecordOverlayController controller = RecordOverlayController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(RecordOverlay(controller: controller)));
      final RecordOverlayState state = _state(tester);

      // Rest: 50dp tall, bottom at 134 - 50 = 84dp.
      expect(state.debugLockPillHeight, 50.0);
      expect(state.debugLockPillBottom, moreOrLessEquals(84.0));
      expect(state.debugLockYAdd, 0.0);

      // Halfway up: height 43dp, yAdd 28.5dp.
      controller.dragOffset = const Offset(0.0, -28.5);
      await tester.pump();
      expect(state.debugLockPillHeight, moreOrLessEquals(43.0));
      expect(state.debugLockYAdd, moreOrLessEquals(28.5));
      expect(state.debugLockPillBottom, moreOrLessEquals(134.0 + 28.5 - 43.0));
    });

    testWidgets('locking snaps to the pause pill and slides back',
        (WidgetTester tester) async {
      final RecordOverlayController controller = RecordOverlayController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(RecordOverlay(controller: controller)));
      final RecordOverlayState state = _state(tester);

      controller.dragOffset = const Offset(0.0, -57.0);
      expect(controller.locked, isTrue);
      await tester.pump();
      // Locked frame 0: pill fixed at 36dp, still translated by 57dp.
      expect(state.debugLockPillHeight, 36.0);
      expect(state.debugLockYAdd, moreOrLessEquals(57.0));
      expect(state.debugLockPillBottom, moreOrLessEquals(155.0));
      expect(state.debugPauseMorphFactor, 0.0);

      // Snap: 250ms EASE_OUT_QUINT to the pause morph (CAEV:4620-4624);
      // the 100ms-delayed translation return only arms during this pump.
      await tester.pump(const Duration(milliseconds: 250));
      expect(state.debugPauseMorphFactor, 1.0);
      expect(state.debugLockYAdd, moreOrLessEquals(57.0));

      // Translation return: 350ms back to the start (CAEV:4610-4617).
      await tester.pump(const Duration(milliseconds: 350));
      expect(state.debugLockYAdd, moreOrLessEquals(0.0));
      expect(state.debugLockPillBottom, moreOrLessEquals(98.0));
    });

    testWidgets('lock morphs the hint into CANCEL; tapping it reports',
        (WidgetTester tester) async {
      int cancelTaps = 0;
      final RecordOverlayController controller = RecordOverlayController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(RecordOverlay(
        controller: controller,
        onCancelTap: () => cancelTaps++,
      )));
      final RecordOverlayState state = _state(tester);
      expect(find.text('CANCEL'), findsNothing);

      controller.dragOffset = const Offset(0.0, -57.0);
      await tester.pump();
      expect(state.debugCancelMorphFactor, 0.0);
      await tester.pump(const Duration(milliseconds: 300));
      // cancelToProgress at 1: grey hint gone, CANCEL fully in
      // (CAEV:14074-14122).
      expect(state.debugCancelMorphFactor, 1.0);
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('Slide to cancel'), findsNothing);

      // Past the translate delay so no timer is left pending.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('CANCEL'));
      expect(cancelTaps, 1);
    });
  });

  group('video circle geometry (AU:2800-2810; ICV:284-287, 612-629)', () {
    test('diameter: min(w, h) - 28, or 0.6 * min in short viewports', () {
      // Tall phone viewport: 800 > 400 * 1.3.
      expect(roundVideoPreviewDiameter(const Size(400.0, 800.0)), 372.0);
      expect(roundVideoPreviewDiameter(const Size(320.0, 700.0)), 292.0);
      // Short viewport: 600 <= 800 * 1.3 -> 0.6 * 600.
      expect(roundVideoPreviewDiameter(const Size(800.0, 600.0)), 360.0);
    });

    test('ring radius = diameter / 2 + 8; progress = t / 60000 capped', () {
      expect(roundVideoRingRadius(360.0), 188.0);
      expect(roundVideoProgress(Duration.zero), 0.0);
      expect(roundVideoProgress(const Duration(seconds: 30)), moreOrLessEquals(0.5));
      expect(roundVideoProgress(const Duration(seconds: 60)), 1.0);
      expect(roundVideoProgress(const Duration(seconds: 90)), 1.0);
    });

    testWidgets('the preview slot is oval-masked at the computed diameter',
        (WidgetTester tester) async {
      const Key previewKey = Key('camera-frames');
      final RecordOverlayController controller = RecordOverlayController(
        mode: RecordMode.video,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(RecordOverlay(
        controller: controller,
        videoPreview: const SizedBox.expand(key: previewKey),
      )));

      // Default test surface 800x600: short viewport -> 0.6 * 600 = 360.
      expect(find.byKey(previewKey), findsOneWidget);
      expect(tester.getSize(find.byType(ClipOval)), const Size(360.0, 360.0));
      // Centered in the overlay.
      expect(tester.getCenter(find.byType(ClipOval)), const Offset(400.0, 300.0));
    });

    testWidgets('voice mode never mounts the preview', (WidgetTester tester) async {
      const Key previewKey = Key('camera-frames');
      final RecordOverlayController controller = RecordOverlayController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(RecordOverlay(
        controller: controller,
        videoPreview: const SizedBox.expand(key: previewKey),
      )));
      expect(find.byKey(previewKey), findsNothing);
      expect(find.byType(ClipOval), findsNothing);

      // Flipping the controller mode mounts it.
      controller.mode = RecordMode.video;
      await tester.pump();
      expect(find.byKey(previewKey), findsOneWidget);
    });
  });
}
