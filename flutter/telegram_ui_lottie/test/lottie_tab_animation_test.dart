// Drives the TabAnimationController contract (telegram_ui tab_icon.dart, the
// port of GlassTabView.checkPlayAnimation, GlassTabView.java:280-398) against
// LottieTabAnimation with the fixture composition in test/fixtures/:
// 60 frames at 60 fps, so the full-range timeline plays in exactly 1 second.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:telegram_ui/telegram_ui.dart';
import 'package:telegram_ui_lottie/telegram_ui_lottie.dart';

Future<LottieComposition> loadFixture() {
  return LottieComposition.fromBytes(
    File('test/fixtures/tab_icon.json').readAsBytesSync(),
  );
}

void main() {
  testWidgets('exposes the RLottie frame surface over the composition', (
    tester,
  ) async {
    final LottieTabAnimation animation = LottieTabAnimation(
      composition: await loadFixture(),
      vsync: const TestVSync(),
    );
    addTearDown(animation.dispose);

    expect(animation.composition.duration, const Duration(seconds: 1));
    expect(animation.frameCount, 60);
    expect(animation.currentFrame, 0);

    animation.setFrame(30);
    expect(animation.currentFrame, 30);
    expect(animation.progress.value, closeTo(0.5, 1e-9));

    // Out-of-range frames clamp (contract: "implementations clamp").
    animation.setFrame(999);
    expect(animation.currentFrame, 60);
    animation.setFrame(-5);
    expect(animation.currentFrame, 0);
  });

  testWidgets('full-range icon plays forward on select, reverse on deselect', (
    tester,
  ) async {
    final LottieTabAnimation animation = LottieTabAnimation(
      composition: await loadFixture(),
      vsync: const TestVSync(),
    );
    addTearDown(animation.dispose);
    final TabIcon icon = lottieTabIcon(animation);

    // Select: 0 -> frameCount at the native frame rate (1 s for 60 frames).
    icon.applySelection(selected: true, animated: true);
    await tester.pump(); // First tick establishes the ticker's start time.
    await tester.pump(const Duration(milliseconds: 500));
    expect(animation.currentFrame, 30);
    await tester.pump(const Duration(milliseconds: 600));
    expect(animation.currentFrame, 60);

    // Deselect: frameCount -> 0 in reverse (GlassTabView.java:391-395).
    icon.applySelection(selected: false, animated: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(animation.currentFrame, 45);
    await tester.pump(const Duration(milliseconds: 800));
    expect(animation.currentFrame, 0);
  });

  testWidgets('unanimated bind snaps to the terminal frame without playing', (
    tester,
  ) async {
    final LottieTabAnimation animation = LottieTabAnimation(
      composition: await loadFixture(),
      vsync: const TestVSync(),
    );
    addTearDown(animation.dispose);
    final TabIcon icon = lottieTabIcon(animation);

    icon.applySelection(selected: true, animated: false);
    expect(animation.currentFrame, 60);
    expect(animation.isPlaying, isFalse);

    icon.applySelection(selected: false, animated: false);
    expect(animation.currentFrame, 0);
    expect(animation.isPlaying, isFalse);
  });

  testWidgets('frame-segment icon follows the BOOSTS-style protocol', (
    tester,
  ) async {
    // Scaled-down BOOSTS shape (GlassTabView.java:568) that fits the
    // 60-frame fixture: select rests at 25, deselect segment ends at 49.
    const TabFrameSegment segment = TabFrameSegment(midFrame: 25, endFrame: 49);
    final LottieTabAnimation animation = LottieTabAnimation(
      composition: await loadFixture(),
      vsync: const TestVSync(),
    );
    addTearDown(animation.dispose);
    final TabIcon icon = lottieTabIcon(animation, frameSegment: segment);

    // Select from rest: plays start..mid and holds at mid
    // (25 frames at 60 fps ~= 417 ms).
    icon.applySelection(selected: true, animated: true);
    await tester.pump(); // First tick establishes the ticker's start time.
    await tester.pump(const Duration(milliseconds: 500));
    expect(animation.currentFrame, 25);
    expect(animation.isPlaying, isFalse);

    // Deselect from mid: plays mid..(end - 1).
    icon.applySelection(selected: false, animated: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(animation.currentFrame, 48);

    // Re-select after a finished deselect run (current >= end - 2): rewinds
    // to start, then plays to mid again (GlassTabView.java:322-357).
    icon.applySelection(selected: true, animated: true);
    expect(animation.currentFrame, lessThanOrEqualTo(25));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(animation.currentFrame, 25);
  });

  testWidgets('frame-segment icon snaps when outside the playable range', (
    tester,
  ) async {
    const TabFrameSegment segment = TabFrameSegment(midFrame: 25, endFrame: 49);
    final LottieTabAnimation animation = LottieTabAnimation(
      composition: await loadFixture(),
      vsync: const TestVSync(),
    );
    addTearDown(animation.dispose);
    final TabIcon icon = lottieTabIcon(animation, frameSegment: segment);

    // Select while past mid (but before end - 2): snap to mid.
    animation.setFrame(30);
    icon.applySelection(selected: true, animated: true);
    expect(animation.currentFrame, 25);
    expect(animation.isPlaying, isFalse);

    // Deselect while below mid - 1: snap back to start.
    animation.setFrame(10);
    icon.applySelection(selected: false, animated: true);
    expect(animation.currentFrame, 0);
    expect(animation.isPlaying, isFalse);
  });

  testWidgets('play honors RLottie end-frame and direction semantics', (
    tester,
  ) async {
    final LottieTabAnimation animation = LottieTabAnimation(
      composition: await loadFixture(),
      vsync: const TestVSync(),
    );
    addTearDown(animation.dispose);

    // start() no-ops when already at the custom end frame
    // (RLottieDrawable.java:894).
    animation.setFrame(60);
    animation.setEndFrame(60);
    animation.play();
    expect(animation.isPlaying, isFalse);

    // Forward-only mode (setPlayTowardEndFrame(false)) stalls when the end
    // frame is behind the current frame (RLottieDrawable.java:436).
    animation.setPlayTowardEndFrame(false);
    animation.setEndFrame(0);
    animation.play();
    expect(animation.isPlaying, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(animation.currentFrame, 60);

    // Toward-end-frame mode plays the same segment backwards
    // (RLottieDrawable.java:767).
    animation.setPlayTowardEndFrame(true);
    animation.play();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(animation.currentFrame, 0);

    // setFrame stops a running animation (setCurrentFrame(frame, false),
    // RLottieDrawable.java:1017-1026).
    animation.setEndFrame(60);
    animation.setPlayTowardEndFrame(false);
    animation.play();
    expect(animation.isPlaying, isTrue);
    animation.setFrame(12);
    expect(animation.isPlaying, isFalse);
    expect(animation.currentFrame, 12);
  });

  testWidgets('lottieTabIcon mounts a Lottie widget driven by the adapter', (
    tester,
  ) async {
    final LottieTabAnimation animation = LottieTabAnimation(
      composition: await loadFixture(),
      vsync: const TestVSync(),
    );
    final AnimatedTabIcon icon = lottieTabIcon(animation) as AnimatedTabIcon;
    expect(icon.controller, same(animation));
    expect(icon.frameSegment, isNull);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: icon.child),
      ),
    );
    expect(find.byType(Lottie), findsOneWidget);
    expect(tester.getSize(find.byType(Lottie)), const Size(24, 24));

    icon.applySelection(selected: true, animated: true);
    await tester.pump(); // First tick establishes the ticker's start time.
    await tester.pump(const Duration(milliseconds: 500));
    expect(animation.currentFrame, 30);
    await tester.pump(const Duration(milliseconds: 600));
    expect(animation.currentFrame, 60);

    // Unmount before disposing the controller the Lottie widget listens to.
    await tester.pumpWidget(const SizedBox());
    animation.dispose();
  });

  testWidgets('loadLottieAssetTabIcon loads via the asset bundle', (
    tester,
  ) async {
    final TabIcon icon = await loadLottieAssetTabIcon(
      'fixtures/tab_icon.json',
      vsync: const TestVSync(),
      bundle: _FixtureBundle(),
      frameSegment: TabFrameSegment.boosts,
    );
    final AnimatedTabIcon animatedIcon = icon as AnimatedTabIcon;
    final LottieTabAnimation animation =
        animatedIcon.controller as LottieTabAnimation;
    addTearDown(animation.dispose);

    expect(animation.frameCount, 60);
    expect(animatedIcon.frameSegment, TabFrameSegment.boosts);
    expect(
      (animatedIcon.child as Lottie).composition,
      same(animation.composition),
    );
  });
}

/// Serves test/fixtures/* as asset bytes for [loadLottieAssetTabIcon].
class _FixtureBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    return ByteData.sublistView(File('test/$key').readAsBytesSync());
  }
}
