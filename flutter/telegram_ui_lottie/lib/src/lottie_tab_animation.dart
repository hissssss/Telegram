// The `package:lottie` adapter for the glass tab bar's animated icons
// (ARCHITECTURE.md section 5, "Iconography / Lottie").
//
// `telegram_ui` deliberately has no lottie dependency: `TabIcon.animated`
// only drives the [TabAnimationController] contract — the projection of the
// `RLottieDrawable` surface used by `GlassTabView.checkPlayAnimation`
// (java/org/telegram/ui/Components/glass/GlassTabView.java:280-398). This
// package supplies that missing half: [LottieTabAnimation] maps the
// frame-oriented RLottie API onto a Flutter [AnimationController] whose
// 0..1 value feeds a `package:lottie` [Lottie] widget.
//
// RLottie semantics ported here
// (java/org/telegram/ui/Components/RLottieDrawable.java):
//
// - `getFramesCount()` == `metaData[0]` == `op - ip` of the composition
//   (RLottieDrawable.java:593, 780);
// - `setCurrentFrame(frame, false)` jumps without playing
//   (RLottieDrawable.java:1017-1026);
// - `setCustomEndFrame(frame)` stores the frame playback stops at
//   (RLottieDrawable.java:771-778);
// - `setPlayInDirectionOfCustomEndFrame(value)` (RLottieDrawable.java:767):
//   when set, playback runs *toward* the custom end frame — backwards if the
//   current frame is past it; when unset playback is forward-only, so a
//   custom end frame at or behind the current frame stalls on the next
//   update (RLottieDrawable.java:436, `currentFrame + framesPerUpdates <
//   customEndFrame` fails immediately);
// - `start()` no-ops when already at the custom end frame
//   (RLottieDrawable.java:893-894) and otherwise plays at the composition's
//   native frame rate.

import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';
import 'package:telegram_ui/telegram_ui.dart';

/// A [TabAnimationController] backed by a `package:lottie`
/// [LottieComposition] — the adapter that lets `TabIcon.animated` /
/// `GlassTab` play a tab icon forward on select and in reverse on deselect
/// (`GlassTabView.checkPlayAnimation`, GlassTabView.java:280-398), including
/// the frame-segment protocol of `TabFrameSegment` (BOOSTS / MONETIZATION,
/// GlassTabView.java:568-569).
///
/// The adapter owns an [AnimationController] whose 0..1 [progress] is the
/// composition timeline; hand [progress] to a [Lottie] widget (or use
/// [lottieTabIcon] / [loadLottieAssetTabIcon], which wire it up for you).
/// Call [dispose] when the icon is gone.
class LottieTabAnimation extends TabAnimationController {
  /// Creates an adapter for an already-loaded [composition].
  ///
  /// [vsync] is the ticker provider of the owning widget state (a
  /// `TickerProviderStateMixin`, or `TestVSync` in tests). Playback runs at
  /// the composition's native frame rate ([LottieComposition.duration]
  /// scaled to the segment being played), matching `RLottieDrawable`'s
  /// `metaData[1]`-derived frame timing (RLottieDrawable.java:764).
  LottieTabAnimation({required this.composition, required TickerProvider vsync})
    : _controller = AnimationController(
        vsync: vsync,
        duration: composition.duration,
      );

  /// Loads [asset] with [AssetLottie] and wraps it — the asynchronous analog
  /// of constructing an `RLottieDrawable` from a raw resource
  /// (`TabAnimation.icon`, GlassTabView.java:584-596).
  static Future<LottieTabAnimation> loadAsset(
    String asset, {
    required TickerProvider vsync,
    AssetBundle? bundle,
    String? package,
  }) async {
    final LottieComposition composition = await AssetLottie(
      asset,
      bundle: bundle,
      package: package,
    ).load();
    return LottieTabAnimation(composition: composition, vsync: vsync);
  }

  /// The loaded composition this adapter plays.
  final LottieComposition composition;

  final AnimationController _controller;

  /// Custom end frame (`RLottieDrawable.customEndFrame`); [frameCount] until
  /// [setEndFrame] is called — RLottie's `-1` sentinel means "composition
  /// end" (RLottieDrawable.java:436).
  int _endFrame = -1;

  /// `RLottieDrawable.playInDirectionOfCustomEndFrame`
  /// (RLottieDrawable.java:767-769).
  bool _playTowardEndFrame = false;

  /// The 0..1 composition progress to hand to a [Lottie] widget's
  /// `controller`.
  Animation<double> get progress => _controller;

  /// Whether playback is currently running — `RLottieDrawable.isRunning`
  /// (RLottieDrawable.java:894, 897).
  bool get isPlaying => _controller.isAnimating;

  /// Total frames, `op - ip` rounded — `RLottieDrawable.getFramesCount()`
  /// (RLottieDrawable.java:593, 780).
  @override
  int get frameCount => composition.durationFrames.round();

  @override
  int get currentFrame => (_controller.value * frameCount).round();

  /// Jumps to [frame] (clamped to `0..frameCount`) without playing,
  /// stopping any running playback — `setCurrentFrame(frame, false)`
  /// (RLottieDrawable.java:1017-1026).
  @override
  void setFrame(int frame) {
    if (frameCount == 0) {
      return;
    }
    _controller.value = frame.clamp(0, frameCount) / frameCount;
  }

  /// Stores the frame playback stops at — `setCustomEndFrame(frame)`
  /// (RLottieDrawable.java:771-778). Values past the composition end are
  /// ignored there ( `frame > metaData[0]` ); this port clamps instead so
  /// the contract's `setEndFrame(frameCount)` is always honored.
  @override
  void setEndFrame(int frame) {
    _endFrame = frame.clamp(0, frameCount);
  }

  @override
  void setPlayTowardEndFrame(bool enabled) {
    _playTowardEndFrame = enabled;
  }

  /// Plays from the current frame to the custom end frame at the
  /// composition's frame rate — `RLottieDrawable.start()`
  /// (RLottieDrawable.java:893-906).
  ///
  /// Direction follows the RLottie decode loop: with
  /// [setPlayTowardEndFrame] enabled playback runs toward the end frame in
  /// either direction; without it playback is forward-only, so an end frame
  /// at or behind the current frame is a no-op (RLottieDrawable.java:436).
  @override
  void play() {
    if (frameCount == 0) {
      return;
    }
    final int end = _endFrame < 0 ? frameCount : _endFrame;
    final double target = end / frameCount;
    if (target == _controller.value) {
      return; // `customEndFrame == currentFrame` (RLottieDrawable.java:894).
    }
    if (target < _controller.value && !_playTowardEndFrame) {
      return; // Forward-only mode stalls (RLottieDrawable.java:436).
    }
    _controller.animateTo(
      target,
      duration: composition.duration * (target - _controller.value).abs(),
      curve: Curves.linear,
    );
  }

  /// Releases the internal [AnimationController].
  void dispose() {
    _controller.dispose();
  }
}

/// Builds a `TabIcon.animated` whose child is a [Lottie] widget driven by
/// [animation] — the convenience analog of `TabAnimation` configuring an
/// `RLottieImageView` inside the 24x24 icon slot (GlassTabView.java:130-137,
/// 545-613).
///
/// Pass [frameSegment] for BOOSTS / MONETIZATION-style icons whose
/// select/deselect transitions are sub-ranges of one composition
/// (GlassTabView.java:568-569); leave it null for play-forward-on-select /
/// reverse-on-deselect icons. `GlassTab` tints the icon via the tab's
/// `glass_tabUnselected` -> `glass_tabSelected` color, so the composition's
/// own colors are usually irrelevant.
TabIcon lottieTabIcon(
  LottieTabAnimation animation, {
  TabFrameSegment? frameSegment,
  double width = 24,
  double height = 24,
  BoxFit fit = BoxFit.contain,
}) {
  return TabIcon.animated(
    controller: animation,
    frameSegment: frameSegment,
    child: Lottie(
      composition: animation.composition,
      controller: animation.progress,
      width: width,
      height: height,
      fit: fit,
    ),
  );
}

/// `TabIcon.lottieAsset(...)`-style one-call convenience: loads [asset] and
/// returns the wired-up animated icon. The created [LottieTabAnimation] is
/// reachable for disposal as the icon's `AnimatedTabIcon.controller`.
Future<TabIcon> loadLottieAssetTabIcon(
  String asset, {
  required TickerProvider vsync,
  TabFrameSegment? frameSegment,
  AssetBundle? bundle,
  String? package,
  double width = 24,
  double height = 24,
  BoxFit fit = BoxFit.contain,
}) async {
  final LottieTabAnimation animation = await LottieTabAnimation.loadAsset(
    asset,
    vsync: vsync,
    bundle: bundle,
    package: package,
  );
  return lottieTabIcon(
    animation,
    frameSegment: frameSegment,
    width: width,
    height: height,
    fit: fit,
  );
}
