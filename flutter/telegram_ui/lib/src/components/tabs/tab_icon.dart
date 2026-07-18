// The tab-icon abstraction of the glass tab bar (ARCHITECTURE.md section 5,
// "Iconography / Lottie").
//
// Port of the `TabAnimation` contract from
// `java/org/telegram/ui/Components/glass/GlassTabView.java`:
//
// - the `TabAnimation` enum (lines 545-613) describes each icon as either a
//   static drawable (`iconStatic`, e.g. LINK -> `tabs_link_24`), a single
//   lottie played forward on select / reverse on deselect (CHATS, CONTACTS,
//   CALLS, SETTINGS), paired `*_reverse` files for attach tabs, or a
//   frame-segment animation (`endFrameMid`/`endFrameEnd`: BOOSTS mid 25 end
//   49, MONETIZATION mid 19 end 45, lines 568-569);
// - `checkPlayAnimation` (lines 280-398) drives the icon's
//   `RLottieDrawable` when the tab's selection changes.
//
// This package deliberately has NO lottie dependency: [TabAnimationController]
// is only the playback *contract* — a minimal projection of the
// `RLottieDrawable` surface that `checkPlayAnimation` touches
// (`getFramesCount`, `getCurrentFrame`, `setCurrentFrame`,
// `setCustomEndFrame`, `setPlayInDirectionOfCustomEndFrame`, `start`). The
// example app provides a `package:lottie` adapter implementing it; an
// rlottie/thorvg FFI adapter is future work. Paired forward/`*_reverse`
// compositions are likewise an adapter concern: from this contract's point of
// view they are one logical timeline played forward or backward.
library;

import 'package:flutter/widgets.dart';

/// Playback contract an animated tab icon implements so [TabIcon.animated]
/// (driven by `GlassTab`) can play it forward on select and in reverse on
/// deselect — the projection of `RLottieDrawable` used by
/// `GlassTabView.checkPlayAnimation` (GlassTabView.java:280-398).
///
/// Frame indices run `0 .. frameCount` in composition order; implementations
/// clamp out-of-range values.
abstract class TabAnimationController {
  /// Enables const implementations.
  const TabAnimationController();

  /// Total frame count of the composition
  /// (`RLottieDrawable.getFramesCount()`).
  int get frameCount;

  /// The frame currently displayed (`RLottieDrawable.getCurrentFrame()`).
  int get currentFrame;

  /// Jumps to [frame] without playing
  /// (`RLottieDrawable.setCurrentFrame(frame, false)`).
  void setFrame(int frame);

  /// Sets the frame playback stops at
  /// (`RLottieDrawable.setCustomEndFrame(frame)`).
  void setEndFrame(int frame);

  /// When [enabled], playback runs *toward* the custom end frame — backwards
  /// if the current frame is past it
  /// (`RLottieDrawable.setPlayInDirectionOfCustomEndFrame(enabled)`).
  void setPlayTowardEndFrame(bool enabled);

  /// Starts playback from the current frame toward the end frame
  /// (`RLottieDrawable.start()`).
  void play();
}

/// A frame-segment description for icons whose select/deselect transitions
/// are sub-ranges of one composition — the `endFrameMid`/`endFrameEnd`
/// members of the `TabAnimation` enum (GlassTabView.java:574, 576-582).
///
/// Semantics (GlassTabView.java:322-357): selecting plays
/// [startFrame]..[midFrame] and holds at [midFrame]; deselecting plays
/// [midFrame]..[endFrame] (the segment that morphs back to the resting
/// glyph) and rewinds to [startFrame] when starting from an unplayed state.
@immutable
class TabFrameSegment {
  /// Creates a frame segment; Java's enum always starts at frame 0
  /// ([startFrame] is exposed for generality).
  const TabFrameSegment({
    this.startFrame = 0,
    required this.midFrame,
    required this.endFrame,
  }) : assert(startFrame >= 0),
       assert(midFrame > startFrame),
       assert(endFrame > midFrame);

  /// First frame of the select segment (implicitly 0 in Java).
  final int startFrame;

  /// `endFrameMid` — the selected resting frame.
  final int midFrame;

  /// `endFrameEnd` — the last frame of the deselect segment.
  final int endFrame;

  /// `BOOSTS(R.raw.boosts, 25, 49)` (GlassTabView.java:568).
  static const TabFrameSegment boosts = TabFrameSegment(
    midFrame: 25,
    endFrame: 49,
  );

  /// `MONETIZATION(R.raw.monetize, 19, 45)` (GlassTabView.java:569).
  static const TabFrameSegment monetization = TabFrameSegment(
    midFrame: 19,
    endFrame: 45,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TabFrameSegment &&
          other.startFrame == startFrame &&
          other.midFrame == midFrame &&
          other.endFrame == endFrame;

  @override
  int get hashCode => Object.hash(startFrame, midFrame, endFrame);
}

/// A tab's icon: either a static 24x24 glyph or an animated composition that
/// reacts to selection — the Dart analog of the `TabAnimation` enum plus the
/// `RLottieImageView` it configures (GlassTabView.java:545-613, 280-398).
///
/// `GlassTab` renders the icon content ([StaticTabIcon.child] /
/// [StaticTabIcon.image] / [AnimatedTabIcon.child]) inside its 24x24 icon
/// slot with a `glass_tabUnselected` -> `glass_tabSelected` SRC_IN tint, and
/// calls [applySelection] whenever the tab's selection state changes.
sealed class TabIcon {
  const TabIcon._();

  /// A non-animated icon — the `iconStatic` arm of `TabAnimation`
  /// (GlassTabView.java:565, 584-596). Provide exactly one of [child]
  /// (arbitrary widget) or [image] (drawn 24x24 by `GlassTab`).
  const factory TabIcon.static({Widget? child, ImageProvider? image}) =
      StaticTabIcon;

  /// An animated icon: [child] displays the composition, [controller] is the
  /// playback contract `GlassTab` drives — forward on select, reverse on
  /// deselect, or the [frameSegment] protocol when one is given
  /// (GlassTabView.java:280-398).
  const factory TabIcon.animated({
    required TabAnimationController controller,
    required Widget child,
    TabFrameSegment? frameSegment,
  }) = AnimatedTabIcon;

  /// Reacts to the owning tab's selection change — the port of
  /// `checkPlayAnimation` (GlassTabView.java:280-398). No-op for static
  /// icons. [animated] false snaps to the terminal frame instead of playing
  /// (initial binding, theme rebinds).
  void applySelection({required bool selected, required bool animated});
}

/// See [TabIcon.static].
class StaticTabIcon extends TabIcon {
  /// Creates a static icon from exactly one of [child] or [image].
  const StaticTabIcon({this.child, this.image})
    : assert(
        (child == null) != (image == null),
        'Provide exactly one of child or image.',
      ),
      super._();

  /// Widget-based glyph (already sized/fit for the 24x24 slot).
  final Widget? child;

  /// Image-based glyph, drawn 24x24 with [BoxFit.contain] by `GlassTab`.
  final ImageProvider? image;

  /// Static icons ignore selection (`checkPlayAnimation` returns after
  /// `setImageResource` + `updateColors`, GlassTabView.java:313-317).
  @override
  void applySelection({required bool selected, required bool animated}) {}
}

/// See [TabIcon.animated].
class AnimatedTabIcon extends TabIcon {
  /// Creates an animated icon driven through [controller].
  const AnimatedTabIcon({
    required this.controller,
    required this.child,
    this.frameSegment,
  }) : super._();

  /// The playback contract (implemented by the app's lottie adapter).
  final TabAnimationController controller;

  /// The widget displaying the composition inside the 24x24 icon slot.
  final Widget child;

  /// Optional frame-segment protocol (BOOSTS / MONETIZATION style).
  final TabFrameSegment? frameSegment;

  /// Port of the `RLottieDrawable`-driving core of `checkPlayAnimation`.
  ///
  /// Frame-segment icons (GlassTabView.java:322-357) — [animated] is ignored
  /// on this path, exactly as in Java:
  ///
  /// - select: end frame = mid; a run that finished the deselect segment
  ///   (`current >= end - 2`) rewinds to start; then play if `current <=
  ///   mid`, else snap to mid;
  /// - deselect: if `current >= mid - 1` play mid..(end-1), else snap back
  ///   to start.
  ///
  /// Full-range icons (GlassTabView.java:385-397): select plays 0 ->
  /// frameCount forward, deselect plays frameCount -> 0 in reverse. With
  /// [animated] false the icon snaps to the terminal frame instead (the
  /// analog of Java's `setProgress(0.99f)` unanimated bind, line 370).
  @override
  void applySelection({required bool selected, required bool animated}) {
    final TabAnimationController c = controller;
    final TabFrameSegment? segment = frameSegment;

    if (segment != null) {
      if (selected) {
        c.setEndFrame(segment.midFrame);
        if (c.currentFrame >= segment.endFrame - 2) {
          c.setFrame(segment.startFrame);
        }
        if (c.currentFrame <= segment.midFrame) {
          c.play();
        } else {
          c.setFrame(segment.midFrame);
        }
      } else {
        if (c.currentFrame >= segment.midFrame - 1) {
          c.setEndFrame(segment.endFrame - 1);
          c.play();
        } else {
          c.setEndFrame(segment.startFrame);
          c.setFrame(segment.startFrame);
        }
      }
      return;
    }

    if (selected) {
      // GlassTabView.java:387-390.
      c.setPlayTowardEndFrame(false);
      if (animated) {
        c.setFrame(0);
        c.setEndFrame(c.frameCount);
        c.play();
      } else {
        c.setEndFrame(c.frameCount);
        c.setFrame(c.frameCount);
      }
    } else {
      // GlassTabView.java:391-395.
      c.setPlayTowardEndFrame(true);
      if (animated) {
        c.setFrame(c.frameCount);
        c.setEndFrame(0);
        c.play();
      } else {
        c.setEndFrame(0);
        c.setFrame(0);
      }
    }
  }
}
