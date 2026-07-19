// The Telegram Android motion dictionary — durations, distances, dims and
// curves swept from:
//
// - `ui/ActionBar/ActionBarLayout.java` (fragment push/pop),
// - `ui/ActionBar/BottomSheet.java` (sheet open/close physics),
// - `ui/ActionBar/AlertDialog.java` + `AlertDialogDecor.java` (dialog dim),
// - `ui/ActionBar/ActionBarPopupWindow.java` (context menu),
//
// per `flutter/docs/spec_typography_motion.md` §2. Curve *instances* live in
// `tg_curves.dart` (the `CubicBezierInterpolator.java` port); this file pins
// the recipe constants that combine them.
//
// Deliberately NOT ported here: the preview (peek & pop) transition, the
// predictive-back peel and the swipe-back commit/cancel duration formulas —
// those are gesture-machinery details owned by the `TgPageRoute` port
// (spec_typography_motion.md §2.1), not shared constants.
library;

import 'package:flutter/animation.dart' show Cubic;

import 'tg_curves.dart';

/// Motion constants for page, sheet, dialog and menu transitions
/// (`spec_typography_motion.md` §2).
abstract final class TgMotion {
  // ---------------------------------------------------------------------------
  // Fragment push/pop — ui/ActionBar/ActionBarLayout.java.

  /// Push/pop duration: 150ms (`float duration = preview && open ? 190.0f :
  /// 150.0f;`, ActionBarLayout.java:1839 — the non-preview branch).
  static const Duration pageDuration = Duration(milliseconds: 150);

  /// Horizontal slide distance of the incoming/outgoing page: 48dp
  /// (`containerView.setTranslationX(dp(48) * (1.0f - interpolated))`,
  /// ActionBarLayout.java:1901; pop mirror at :1916). The page underneath
  /// never moves — the standard transition is a 48dp slide-in + crossfade.
  static const double pageSlide = 48.0;

  /// Push/pop curve: `DecelerateInterpolator(1.5f)`
  /// (ActionBarLayout.java:577, applied at :1882) — `f(t) = 1 - (1 - t)^3`.
  static const TgDecelerateCurve pageCurve = TgDecelerateCurve(factor: 1.5);

  /// Maximum black scrim over the back page during a gesture pop:
  /// `Color.argb((int) (120 * opacity), 0, 0, 0)` with `opacity` clamped to
  /// 0.8 (ActionBarLayout.java:1214-1215) — 96/255 ≈ 37.6% black, linearly
  /// proportional to how much of the back page is still covered.
  static const double pageScrimMax = 96 / 255;

  // ---------------------------------------------------------------------------
  // Bottom sheet — ui/ActionBar/BottomSheet.java.

  /// Sheet open duration: 400ms (`openDuration = 400`, BottomSheet.java:210).
  static const Duration sheetOpenDuration = Duration(milliseconds: 400);

  /// Sheet open start delay: 20ms (`setStartDelay(waitingKeyboard ? 0 : 20)`,
  /// BottomSheet.java:1745).
  static const Duration sheetOpenDelay = Duration(milliseconds: 20);

  /// Sheet open curve: `EASE_OUT_QUINT` (`openInterpolator`,
  /// BottomSheet.java:211).
  static const Cubic sheetOpenCurve = TgCurves.easeOutQuint;

  /// Sheet dismiss duration: 250ms (`setDuration(duration = 250)`,
  /// BottomSheet.java:2032).
  static const Duration sheetCloseDuration = Duration(milliseconds: 250);

  /// Sheet dismiss curve: `EASE_OUT` (BottomSheet.java:2033).
  static const Cubic sheetCloseCurve = TgCurves.easeOut;

  /// Sheet barrier dim: `dimBehindAlpha = 51` (BottomSheet.java:219) —
  /// 51/255 = 20% black.
  static const double sheetDim = 51 / 255;

  // ---------------------------------------------------------------------------
  // Alert dialog — ui/ActionBar/AlertDialog.java + AlertDialogDecor.java.

  /// Dialog barrier dim: `dimAlpha = 0.5f` black (AlertDialog.java:210,
  /// applied via `WindowManager.LayoutParams.dimAmount` at :1241-1243).
  static const double dialogDim = 0.5;

  /// Dialog fade in/out: the window-animation path — `TransparentDialog`
  /// (res/values/styles.xml:139-153) inherits the ~150ms system dialog fade
  /// from `@android:style/Theme.Dialog`. The content is a pure fade, no
  /// scale (spec_typography_motion.md §2.3).
  static const Duration dialogFadeDuration = Duration(milliseconds: 150);

  /// In-layout decor dim fade: `DIM_DURATION = 300`
  /// (AlertDialogDecor.java:39, applied at :54).
  static const Duration dialogDimDuration = Duration(milliseconds: 300);

  // ---------------------------------------------------------------------------
  // Popup/context menu — ui/ActionBar/ActionBarPopupWindow.java.

  /// Menu open base duration: 150ms of `150 + 16 * visibleCount`
  /// (ActionBarPopupWindow.java:965; also :896).
  static const Duration menuOpenBase = Duration(milliseconds: 150);

  /// Menu open per-item increment: 16ms of `150 + 16 * visibleCount`
  /// (ActionBarPopupWindow.java:965).
  static const Duration menuOpenPerItem = Duration(milliseconds: 16);

  /// Menu dismiss duration: 150ms (`dismissAnimationDuration = 150`,
  /// ActionBarPopupWindow.java:69).
  static const Duration menuCloseDuration = Duration(milliseconds: 150);

  /// Total menu open duration for [visibleItemCount] rows:
  /// `150 + 16 * visibleCount` ms (ActionBarPopupWindow.java:965).
  static Duration menuOpenDuration(int visibleItemCount) =>
      menuOpenBase + menuOpenPerItem * visibleItemCount;

  // ---------------------------------------------------------------------------
  // Curve aliases (single source of truth: TgCurves /
  // CubicBezierInterpolator.java:11-22), re-exposed here so motion recipes
  // read from one class.

  /// `EASE_OUT = (0, 0, .58, 1)` (CubicBezierInterpolator.java:12).
  static const Cubic easeOut = TgCurves.easeOut;

  /// `EASE_OUT_QUINT = (.23, 1, .32, 1)` (CubicBezierInterpolator.java:13).
  static const Cubic easeOutQuint = TgCurves.easeOutQuint;

  /// `EASE_OUT_BACK = (.34, 1.56, .64, 1)` (CubicBezierInterpolator.java:16).
  static const Cubic easeOutBack = TgCurves.easeOutBack;
}
