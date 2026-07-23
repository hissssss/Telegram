// Port of `ui/Components/StickerEmptyView.java` — the centered empty-state
// column with the progress↔content crossfade (PLAN_UIKIT.md S3;
// `ui/Components/EmptyTextProgressView.java` is the legacy text-only
// sibling whose recipe — one 20dp `emptyListPlaceholder` line over the same
// kind of progress swap, EmptyTextProgressView.java:77-104 — is a subset of
// this API: title + [TgEmptyView.titleColorKey] with no subtitle/button).
//
// Faithful recipe (StickerEmptyView.java):
// - vertical column centered in the view with 46dp side margins and a 30dp
//   bottom margin (`addView(linearLayout, createFrame(WRAP, WRAP, CENTER,
//   46, 0, 46, 30))`, :128);
// - 117×117dp sticker/image slot (:124), title 12dp below it (:125),
//   subtitle 8dp below the title (:126), 48dp button 16dp below with 28dp
//   side margins (:127);
// - title: 20dp `AndroidUtilities.bold()` (Roboto Medium) in
//   `windowBackgroundWhiteBlackText`, centered (:108-112) — the
//   `TgTextStyles.title` role (20/500; the PLAN S3 index says bodyEmphasis,
//   but the Java source is 20dp bold and per the plan's own preamble the
//   Java citation wins);
// - subtitle: 14dp regular `windowBackgroundWhiteGrayText`, centered
//   (:114-119) — the `TgTextStyles.subtitle` role;
// - button: `ButtonWithCounterView(…).setRound()` (:121) — [TgButton] with
//   the 24dp stadium radius — hidden until given a label (:122);
// - progress crossfade (`showProgress`, :354-414): content fades 1↔0 while
//   scaling 1↔0.8 and the progress spinner fades 0↔1 while scaling 0.5↔1,
//   both over 150ms (:71-73, 132-134, 213, 219, 229, 366-380) with the
//   stock `ViewPropertyAnimator` AccelerateDecelerate interpolator (none is
//   set);
// - the default progress indicator is `RadialProgressView` (:130-136) —
//   [TgRadialProgress] — replaceable via the [TgEmptyView.progress] slot
//   (the Java `progressView` constructor argument, :78-85); the slot is
//   unmounted while fully hidden (`progressView.setVisibility(GONE)` on
//   animation end, :222-227).
//
// Deliberately NOT ported:
// - the sticker machinery — `setSticker`, sticker types, NotificationCenter
//   reloads, Lottie autoplay (:36-40, 88-104, 262-331) — the image is a
//   caller-supplied widget slot;
// - `createButtonLayout` (the legacy inline 15dp text button, :139-168) and
//   `setColors`' key-tag plumbing (:191-200) beyond the two color-key
//   params;
// - keyboard tracking, `preventMoving`, `animateLayoutChange` and the
//   layout-shift settle (:170-189, 333-352, 416-428);
// - the 480ms EASE_OUT_QUINT `visibilityFactor` hook for embedding chrome
//   (:473-513) — show/hide the widget with standard Flutter transitions;
// - `setSubtitle`'s whitespace-balancing line break (:441-461) — Flutter
//   text wrapping applies.
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../buttons/tg_button.dart';
import '../components/app_bar/glass_app_bar.dart'
    show TgAccelerateDecelerateCurve;
import '../foundation/tg_text_styles.dart';
import '../progress/tg_radial_progress.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Image/sticker slot size: 117×117dp (`createLinear(117, 117)`,
/// StickerEmptyView.java:124).
const double kTgEmptyViewImageSize = 117.0;

/// Title top margin below the image: 12dp (StickerEmptyView.java:125).
const double kTgEmptyViewTitleTopMargin = 12.0;

/// Subtitle top margin below the title: 8dp (StickerEmptyView.java:126).
const double kTgEmptyViewSubtitleTopMargin = 8.0;

/// Button top margin below the subtitle: 16dp (StickerEmptyView.java:127).
const double kTgEmptyViewButtonTopMargin = 16.0;

/// Button side margins inside the column: 28dp (StickerEmptyView.java:127).
const double kTgEmptyViewButtonSideMargin = 28.0;

/// Column side margins: 46dp (StickerEmptyView.java:128).
const double kTgEmptyViewSideMargin = 46.0;

/// Column bottom margin: 30dp (StickerEmptyView.java:128).
const double kTgEmptyViewBottomMargin = 30.0;

/// Progress↔content crossfade duration: 150ms (`setDuration(150)` on every
/// leg, StickerEmptyView.java:70-73, 213, 219, 227-229, 366-380).
const Duration kTgEmptyViewFadeDuration = Duration(milliseconds: 150);

/// Content scale while hidden: 0.8 (`scaleY(0.8f).scaleX(0.8f)`,
/// StickerEmptyView.java:213, 241-242, 366).
const double kTgEmptyViewContentHiddenScale = 0.8;

/// Progress-spinner scale while hidden: 0.5 (`setScaleY(0.5f)`,
/// StickerEmptyView.java:133-134, 229, 253-255, 379).
const double kTgEmptyViewProgressHiddenScale = 0.5;

/// The crossfade curve: the Java `ViewPropertyAnimator`s set no interpolator,
/// so Android's default `AccelerateDecelerateInterpolator` applies
/// (StickerEmptyView.java:366-380).
const Curve kTgEmptyViewFadeCurve = TgAccelerateDecelerateCurve();

/// The `ui/Components/StickerEmptyView.java` port — a centered empty-state
/// column (image/lottie slot, title, subtitle, optional round [TgButton])
/// that crossfades with a progress spinner.
///
/// A controlled widget: [loading] is plain state passed in; toggling it
/// across rebuilds plays the Java 150ms crossfade — content alpha 1↔0 with
/// scale 1↔0.8 against progress alpha 0↔1 with scale 0.5↔1
/// (StickerEmptyView.java:366-380). While loading, the content ignores
/// pointers and is excluded from semantics (the Java view swaps
/// visibilities).
///
/// All content is optional: omit [image]/[title]/[subtitle]/[buttonText] to
/// drop the corresponding slot, mirroring the Java `GONE` defaults. The
/// [progress] slot replaces the default [TgRadialProgress] (the Java
/// `progressView` constructor argument, StickerEmptyView.java:78-85); it is
/// only mounted while visible, so the default spinner's ticker does not run
/// behind a fully shown content state.
///
/// Like every component in this package, the view takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise keys resolve through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class TgEmptyView extends StatefulWidget {
  /// Creates the empty view.
  const TgEmptyView({
    super.key,
    this.image,
    this.title,
    this.subtitle,
    this.buttonText,
    this.onButtonPressed,
    this.loading = false,
    this.progress,
    this.titleColorKey = TelegramColorKey.windowBackgroundWhiteBlackText,
    this.subtitleColorKey = TelegramColorKey.windowBackgroundWhiteGrayText,
    this.resources,
  });

  /// The 117×117dp sticker/illustration slot (`stickerView`,
  /// StickerEmptyView.java:103-104, 124) — a plain widget here; the Java
  /// sticker-pack loading is deliberately not ported.
  final Widget? image;

  /// Title, 20dp Roboto Medium in [titleColorKey]
  /// (StickerEmptyView.java:106-112).
  final String? title;

  /// Subtitle, 14dp regular in [subtitleColorKey]
  /// (StickerEmptyView.java:114-119).
  final String? subtitle;

  /// Label of the round button; null hides it (`button.setVisibility(GONE)`,
  /// StickerEmptyView.java:121-122).
  final String? buttonText;

  /// Tap callback for the button.
  final VoidCallback? onButtonPressed;

  /// Whether the progress spinner shows instead of the content
  /// (`showProgress`, StickerEmptyView.java:354-414). Changes animate over
  /// [kTgEmptyViewFadeDuration].
  final bool loading;

  /// Replacement progress indicator (the Java `progressView` constructor
  /// argument, StickerEmptyView.java:78-85); null uses the default
  /// [TgRadialProgress] (StickerEmptyView.java:130-136).
  final Widget? progress;

  /// Title color key, default `windowBackgroundWhiteBlackText`
  /// (StickerEmptyView.java:109-110; overridable like `setColors`, :193-200).
  final int titleColorKey;

  /// Subtitle color key, default `windowBackgroundWhiteGrayText`
  /// (StickerEmptyView.java:115-116).
  final int subtitleColorKey;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  @override
  State<TgEmptyView> createState() => TgEmptyViewState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('title', title, defaultValue: null))
      ..add(StringProperty('subtitle', subtitle, defaultValue: null))
      ..add(StringProperty('buttonText', buttonText, defaultValue: null))
      ..add(FlagProperty('loading', value: loading, ifTrue: 'loading'));
  }
}

/// State of [TgEmptyView]; public for test access to [debugProgressFactor].
class TgEmptyViewState extends State<TgEmptyView>
    with SingleTickerProviderStateMixin {
  /// 0 = content shown, 1 = progress shown (`progressShowing`,
  /// StickerEmptyView.java:48, animated at :366-380).
  late final AnimationController _progressT = AnimationController(
    vsync: this,
    duration: kTgEmptyViewFadeDuration,
    value: widget.loading ? 1.0 : 0.0,
  );

  /// The current crossfade factor: 0 content, 1 progress.
  @visibleForTesting
  double get debugProgressFactor => _progressT.value;

  @override
  void didUpdateWidget(TgEmptyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading != oldWidget.loading) {
      // 150ms, stock AccelerateDecelerate (StickerEmptyView.java:366-380).
      _progressT.animateTo(
        widget.loading ? 1.0 : 0.0,
        curve: kTgEmptyViewFadeCurve,
      );
    }
  }

  @override
  void dispose() {
    _progressT.dispose();
    super.dispose();
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  Widget _buildContent(BuildContext context) {
    final String? title = widget.title;
    final String? subtitle = widget.subtitle;
    final String? buttonText = widget.buttonText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.image != null)
          // 117×117 CENTER_HORIZONTAL (StickerEmptyView.java:124).
          SizedBox(
            width: kTgEmptyViewImageSize,
            height: kTgEmptyViewImageSize,
            child: widget.image,
          ),
        if (title != null)
          Padding(
            // topMargin 12 (StickerEmptyView.java:125).
            padding: const EdgeInsets.only(top: kTgEmptyViewTitleTopMargin),
            child: Text(
              title,
              textAlign: TextAlign.center,
              textHeightBehavior: kTgTextHeightBehavior,
              // 20dp bold, windowBackgroundWhiteBlackText, CENTER
              // (StickerEmptyView.java:108-112).
              style: TgTextStyles.title
                  .copyWith(color: _color(context, widget.titleColorKey)),
            ),
          ),
        if (subtitle != null)
          Padding(
            // topMargin 8 (StickerEmptyView.java:126).
            padding: const EdgeInsets.only(top: kTgEmptyViewSubtitleTopMargin),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              textHeightBehavior: kTgTextHeightBehavior,
              // 14dp regular, windowBackgroundWhiteGrayText, CENTER
              // (StickerEmptyView.java:114-119).
              style: TgTextStyles.subtitle
                  .copyWith(color: _color(context, widget.subtitleColorKey)),
            ),
          ),
        if (buttonText != null)
          Padding(
            // MATCH_PARENT × 48, margins 28/16/28/0
            // (StickerEmptyView.java:127).
            padding: const EdgeInsets.only(
              left: kTgEmptyViewButtonSideMargin,
              right: kTgEmptyViewButtonSideMargin,
              top: kTgEmptyViewButtonTopMargin,
            ),
            child: TgButton(
              text: buttonText,
              onPressed: widget.onButtonPressed,
              // setRound() = the 24dp stadium (StickerEmptyView.java:121;
              // ButtonWithCounterView.java:67-70).
              radius: kTgButtonRoundRadius,
              resources: widget.resources,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = _buildContent(context);
    return AnimatedBuilder(
      animation: _progressT,
      builder: (BuildContext context, Widget? child) {
        final double t = _progressT.value;
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Content column, centered under 46dp side / 30dp bottom margins
            // (StickerEmptyView.java:128); fades to 0 and scales to 0.8
            // while the progress shows (StickerEmptyView.java:213, 366).
            Center(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: kTgEmptyViewSideMargin,
                  right: kTgEmptyViewSideMargin,
                  bottom: kTgEmptyViewBottomMargin,
                ),
                child: IgnorePointer(
                  ignoring: widget.loading,
                  child: ExcludeSemantics(
                    excluding: widget.loading,
                    child: Opacity(
                      opacity: 1.0 - t,
                      child: Transform.scale(
                        scale: lerpDouble(
                            1.0, kTgEmptyViewContentHiddenScale, t)!,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Progress layer, centered over the whole view
            // (StickerEmptyView.java:135); alpha 0↔1, scale 0.5↔1
            // (StickerEmptyView.java:132-134, 366-380). Unmounted at 0 —
            // the `setVisibility(GONE)`-on-end behavior
            // (StickerEmptyView.java:222-227).
            if (t > 0.0)
              IgnorePointer(
                child: ExcludeSemantics(
                  excluding: !widget.loading,
                  child: Opacity(
                    opacity: t,
                    child: Transform.scale(
                      scale: lerpDouble(
                          kTgEmptyViewProgressHiddenScale, 1.0, t)!,
                      child: Center(
                        child: widget.progress ??
                            TgRadialProgress(resources: widget.resources),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      child: content,
    );
  }
}
