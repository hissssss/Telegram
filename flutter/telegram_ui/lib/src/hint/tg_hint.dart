// Port of `ui/Stories/recorder/HintView2.java` — the modern tooltip/hint
// bubble (PLAN_UIKIT.md S1): a rounded bubble with a triangular arrow pointing
// at an anchor, a 14dp text line (or multiline paragraph), tap-to-dismiss and
// an auto-hide timer, shown/hidden with a 350ms EASE_OUT_QUINT scale+fade
// anchored at the arrow tip.
//
// Faithful recipe:
// - bubble: 8dp rounding (HintView2.java:94), inner padding 11/6/11/7
//   single-line or 15/8/15/8 multiline (:95, :227), arrow 7dp half-width ×
//   6dp height (:97-98) with 2dp shoulders and a 1dp-flat tip (:999-1006);
// - text: 14dp regular (`setTextSize(14)`, :158) — the `TgTextStyles.subtitle`
//   role — default white on 0xe6282828 (:151, :159), re-keyed here as
//   `undo_infoColor` on `undo_background` (see below);
// - show/hide: `AnimatedFloat(350, EASE_OUT_QUINT)` (:132) driving alpha
//   (:862) and a 0.75→1 scale around the arrow tip (:865-866); nothing is
//   painted at factor 0 (:834);
// - auto-hide after 3500ms (:83), tap inside the bubble hides when no tap
//   handler is set (`hideByTouch`, :1105-1110), `onHidden` runs after the
//   hide animation completes (:690-691).
//
// Divergence (API convention 1): HintView2 hardcodes background 0xe6282828
// (:151) and white text (:159); virtually every themed call site immediately
// re-colors with `Theme.key_undo_background` (DialogsActivity.java:4777,
// :13525; DialogStoriesCell.java:2110), whose companion text key is
// `undo_infoColor` — the port resolves those keys by default.
//
// Deliberately NOT ported:
// - `AnimatedTextView.AnimatedTextDrawable` per-character text morphing on
//   single-line hints (:117, :154-155) — text changes swap statically;
// - the close button (`setCloseButton`, :288-294, drawable at :840-847), the
//   RLottie icon slot (:306-328), link handling (:1126-1198), the ripple
//   selector (:535-564), blur (:267-274, :1200-1240), the flicker sweep
//   (:198-221), shadow layers (:165-173) and `cutInFancyHalf` (:392-477);
// - the repeated-show bounce (300ms EASE_OUT_BACK, :649-674) and the
//   `ButtonBounce` press scale (:763-764) — a hint is transient chrome;
// - `pause`/`unpause` of the auto-hide timer (:696-705);
// - `CornerPathEffect(rounding)` corner smoothing (:152): the port draws true
//   corner arcs — the Java `roundWithCornerEffect = false` branch
//   (:995-1053) — so the arrow tip stays crisp.
library;

import 'dart:async' show Timer;
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../foundation/tg_curves.dart';
import '../foundation/tg_text_styles.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Auto-hide delay: 3500ms (`private long duration = 3500`,
/// HintView2.java:83).
const Duration kTgHintDuration = Duration(milliseconds: 3500);

/// Show/hide animation length: 350ms EASE_OUT_QUINT
/// (`new AnimatedFloat(this, 350, CubicBezierInterpolator.EASE_OUT_QUINT)`,
/// HintView2.java:132).
const Duration kTgHintShowDuration = Duration(milliseconds: 350);

/// Scale at the fully hidden end of the show animation: 0.75
/// (`lerp(.75f, 1f, showT)` around the arrow tip, HintView2.java:865-866).
const double kTgHintHiddenScale = 0.75;

/// Bubble corner radius: 8dp (`rounding = dp(8)`, HintView2.java:94).
const double kTgHintRounding = 8.0;

/// Single-line inner padding: 11/6/11/7dp
/// (`innerPadding = new RectF(dp(11), dp(6), dp(11), dp(7))`,
/// HintView2.java:95).
const EdgeInsets kTgHintInnerPadding = EdgeInsets.fromLTRB(11.0, 6.0, 11.0, 7.0);

/// Multiline inner padding: 15/8/15/8dp
/// (`innerPadding.set(dp(15), dp(8), dp(15), dp(8))`, HintView2.java:227).
const EdgeInsets kTgHintInnerPaddingMultiline = EdgeInsets.fromLTRB(15.0, 8.0, 15.0, 8.0);

/// Arrow half-width: 7dp (`arrowHalfWidth = dp(7)`, HintView2.java:97).
const double kTgHintArrowHalfWidth = 7.0;

/// Arrow height (protrusion from the bubble edge): 6dp
/// (`arrowHeight = dp(6)`, HintView2.java:98).
const double kTgHintArrowHeight = 6.0;

/// Flat run on the bubble edge on each side of the arrow slope: 2dp
/// (`path.lineTo(arrowXY - arrowHalfWidth - dp(2), bounds.top)`,
/// HintView2.java:1018, :1025 et al.).
const double kTgHintArrowShoulder = 2.0;

/// Half-width of the flattened arrow tip: 1dp
/// (`path.lineTo(arrowXY - dp(1), bounds.top - arrowHeight)`,
/// HintView2.java:1020, :1023 et al.).
const double kTgHintArrowTipFlat = 1.0;

/// Hint text size: 14dp regular (`setTextSize(14)`, HintView2.java:158) —
/// the `TgTextStyles.subtitle` role.
const double kTgHintTextSize = 14.0;

/// Which side of the hint bubble carries the arrow — `DIRECTION_LEFT/TOP/
/// RIGHT/BOTTOM` (HintView2.java:74-77). The arrow points *away* from the
/// bubble toward the anchored view: a [bottom] hint sits above its target,
/// a [top] hint below it.
enum TgHintDirection {
  /// Arrow on the left edge (`DIRECTION_LEFT = 0`, HintView2.java:74) —
  /// the hint sits to the right of its target.
  left,

  /// Arrow on the top edge (`DIRECTION_TOP = 1`, HintView2.java:75) —
  /// the hint sits below its target.
  top,

  /// Arrow on the right edge (`DIRECTION_RIGHT = 2`, HintView2.java:76) —
  /// the hint sits to the left of its target.
  right,

  /// Arrow on the bottom edge (`DIRECTION_BOTTOM = 3`, HintView2.java:77) —
  /// the hint sits above its target.
  bottom,
}

/// The Telegram hint/tooltip bubble — the `HintView2` port: a rounded 8dp
/// bubble with a 7×6dp arrow on the [direction] edge (positioned along it by
/// [joint]), 14dp text inside, a 3500ms auto-hide timer, tap-to-dismiss, and
/// the 350ms EASE_OUT_QUINT alpha + 0.75-scale show/hide anchored at the
/// arrow tip.
///
/// The hint sizes itself to its text (plus padding and arrow); positioning
/// next to the target view is up to the caller — a `Stack`/`Positioned` or a
/// `CompositedTransformFollower` — exactly as in Java ("the layout (bounds of
/// hint) are up to a user of this component", HintView2.java:78).
///
/// A controlled widget: toggle [shown] across rebuilds to play the show/hide
/// animation. The auto-hide timer and tap-to-dismiss hide the hint
/// internally (mirroring the Java view hiding itself) and report through
/// [onHidden] once the hide animation completes; setting [shown] back to
/// true re-shows it.
///
/// Like every component in this package, the hint takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise keys resolve through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class TgHint extends StatefulWidget {
  /// Creates the hint.
  const TgHint({
    super.key,
    required this.text,
    this.shown = true,
    this.direction = TgHintDirection.bottom,
    this.joint = 0.5,
    this.jointTranslate = 0.0,
    this.multiline = false,
    this.textAlign = TextAlign.start,
    this.maxTextWidth,
    this.autoHideDuration = kTgHintDuration,
    this.hideByTouch = true,
    this.onTap,
    this.onHidden,
    this.innerPadding,
    this.rounding = kTgHintRounding,
    this.arrowHalfWidth = kTgHintArrowHalfWidth,
    this.arrowHeight = kTgHintArrowHeight,
    this.backgroundColorKey = TelegramColorKey.undo_background,
    this.textColorKey = TelegramColorKey.undo_infoColor,
    this.resources,
  })  : assert(joint >= 0.0 && joint <= 1.0),
        assert(rounding >= 0.0),
        assert(arrowHalfWidth > 0.0),
        assert(arrowHeight > 0.0),
        assert(maxTextWidth == null || maxTextWidth > 0.0);

  /// The hint message, 14dp regular (`setTextSize(14)`, HintView2.java:158).
  final String text;

  /// Whether the hint is visible; changes animate 350ms EASE_OUT_QUINT
  /// (`show()`/`hide()`, HintView2.java:624-694). A hint mounted with
  /// `shown: true` animates in on its first frame, like the Java view's
  /// `firstDraw` handshake (HintView2.java:829-833).
  final bool shown;

  /// Which edge carries the arrow (`setDirection`, HintView2.java:175-178).
  final TgHintDirection direction;

  /// Arrow position along the [direction] edge, 0 (start) .. 1 (end),
  /// default centered (`joint = .5f`, HintView2.java:81; `setJoint`,
  /// :594-602). Not RTL-flipped, as in Java. The arrow keeps
  /// `rounding + arrowHalfWidth` clear of the corners (HintView2.java:967).
  final double joint;

  /// Extra translation of the arrow along the edge, in logical px
  /// (`jointTranslate`, HintView2.java:81, :594-602).
  final double jointTranslate;

  /// Multiline layout: wrapping text and the larger 15/8/15/8 padding
  /// (`setMultilineText`, HintView2.java:224-234). Single-line hints clip to
  /// one line.
  final bool multiline;

  /// Paragraph alignment for [multiline] text (`setTextAlign`,
  /// HintView2.java:572-575; default `ALIGN_NORMAL`, :121).
  final TextAlign textAlign;

  /// Optional cap on the text width in logical px (`setMaxWidth`,
  /// HintView2.java:296-299; applied in `getTextMaxWidth`, :711-717).
  final double? maxTextWidth;

  /// Delay before the hint hides itself, default 3500ms (HintView2.java:83,
  /// scheduled in `show()`, :639-641). Pass null to keep the hint up until
  /// [shown] turns false or it is tapped away — the Java `duration < 0`
  /// contract (`setDuration`, :489-493).
  final Duration? autoHideDuration;

  /// Whether tapping the bubble hides the hint when [onTap] is null
  /// (`hideByTouch = true`, HintView2.java:128; `setHideByTouch`, :530-533;
  /// tap-up handling, :1105-1110).
  final bool hideByTouch;

  /// Tap callback; when set, taps invoke it *instead of* hiding — the Java
  /// `hasOnClickListeners() → performClick()` branch (HintView2.java:
  /// 1106-1110).
  final VoidCallback? onTap;

  /// Called after the hide animation completes, whatever initiated the hide
  /// (`setOnHiddenListener`, HintView2.java:586-589, scheduled after
  /// `show.get() * show.getDuration()`, :690-691).
  final VoidCallback? onHidden;

  /// Overrides the text-to-bubble padding (`setInnerPadding`,
  /// HintView2.java:503-506); defaults to [kTgHintInnerPadding] or
  /// [kTgHintInnerPaddingMultiline] per [multiline].
  final EdgeInsets? innerPadding;

  /// Bubble corner radius, default 8dp (`setRounding`,
  /// HintView2.java:180-190).
  final double rounding;

  /// Arrow half-width, default 7dp (`setArrowSize`, HintView2.java:100-104).
  final double arrowHalfWidth;

  /// Arrow protrusion from the bubble edge, default 6dp (`setArrowSize`,
  /// HintView2.java:100-104).
  final double arrowHeight;

  /// Bubble fill key, default `undo_background` — the themed stand-in for
  /// the hardcoded 0xe6282828 (HintView2.java:151; DialogsActivity.java:4777).
  final int backgroundColorKey;

  /// Text color key, default `undo_infoColor` — the themed stand-in for the
  /// hardcoded white (HintView2.java:159).
  final int textColorKey;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  @override
  State<TgHint> createState() => TgHintState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('text', text))
      ..add(FlagProperty('shown', value: shown, ifFalse: 'hidden'))
      ..add(EnumProperty<TgHintDirection>('direction', direction))
      ..add(DoubleProperty('joint', joint, defaultValue: 0.5))
      ..add(FlagProperty('multiline', value: multiline, ifTrue: 'multiline'))
      ..add(DiagnosticsProperty<Duration?>('autoHideDuration', autoHideDuration,
          defaultValue: kTgHintDuration))
      ..add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}

/// State of [TgHint]; public for test access to the debug getters.
class TgHintState extends State<TgHint> with SingleTickerProviderStateMixin {
  /// The show factor — the `AnimatedFloat(350, EASE_OUT_QUINT)` of
  /// HintView2.java:132, retargeted from the current value over the full
  /// 350ms.
  late final AnimationController _show = AnimationController(vsync: this);

  final GlobalKey _chromeKey = GlobalKey();
  Timer? _autoHideTimer;
  bool _internallyHidden = false;
  Color? _lastBackground;

  bool get _effectiveShown => widget.shown && !_internallyHidden;

  /// The current show factor, 0 hidden .. 1 shown (`show.get()`).
  @visibleForTesting
  double get debugShowFactor => _show.value;

  /// Whether the hint is logically shown (`shown()`, HintView2.java:707-709)
  /// — false once the auto-hide timer or a dismissing tap fired, even while
  /// the hide animation is still running.
  @visibleForTesting
  bool get debugEffectivelyShown => _effectiveShown;

  /// Whether the auto-hide timer is currently pending (`hideRunnable`
  /// scheduled, HintView2.java:639-641).
  @visibleForTesting
  bool get debugAutoHideScheduled => _autoHideTimer?.isActive ?? false;

  /// The bubble fill resolved in the last build.
  @visibleForTesting
  Color? get debugBackgroundColor => _lastBackground;

  _RenderHintChrome? get _chrome {
    final RenderObject? renderObject = _chromeKey.currentContext?.findRenderObject();
    return renderObject is _RenderHintChrome ? renderObject : null;
  }

  /// The laid-out bubble rectangle in the hint's local coordinates —
  /// excludes the arrow, like the Java `bounds` (HintView2.java:767, filled
  /// at :969-984).
  @visibleForTesting
  Rect? get debugBubbleBounds => _chrome?.debugGeometry?.bubble;

  /// The arrow tip point in local coordinates — the scale origin
  /// (`arrowX`/`arrowY`, HintView2.java:770, :865-866).
  @visibleForTesting
  Offset? get debugArrowTip => _chrome?.debugGeometry?.arrowTip;

  @override
  void initState() {
    super.initState();
    if (widget.shown) {
      _animateIn();
    }
  }

  @override
  void didUpdateWidget(TgHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shown != oldWidget.shown) {
      _internallyHidden = false;
      if (widget.shown) {
        _animateIn();
      } else {
        _animateOut();
      }
    } else if (widget.autoHideDuration != oldWidget.autoHideDuration && _effectiveShown) {
      _scheduleAutoHide();
    }
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _show.dispose();
    super.dispose();
  }

  /// `show()` (HintView2.java:629-647): animate in and (re)arm the auto-hide.
  void _animateIn() {
    _show.animateTo(1.0, duration: kTgHintShowDuration, curve: TgCurves.easeOutQuint);
    _scheduleAutoHide();
  }

  /// `hide()` (HintView2.java:680-694): animate out; [TgHint.onHidden] fires
  /// only when the hide animation actually completes — the Java
  /// `show.get() * show.getDuration()` delay (:690-691). A retargeted
  /// animation abandons the pending callback, as cancelling the runnable
  /// does (:683-684).
  void _animateOut() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    _show
        .animateTo(0.0, duration: kTgHintShowDuration, curve: TgCurves.easeOutQuint)
        .then((void _) {
      if (mounted) {
        widget.onHidden?.call();
      }
    });
  }

  /// `AndroidUtilities.runOnUIThread(hideRunnable, duration)` — HintView2
  /// .java:638-641; no timer for a null duration (`duration < 0 means you
  /// would hide it on yourself`, :489).
  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    final Duration? delay = widget.autoHideDuration;
    if (delay != null && delay > Duration.zero) {
      _autoHideTimer = Timer(delay, _hide);
    }
  }

  /// A self-initiated hide (timer or dismissing tap): the hint hides itself
  /// like the Java view and reports through [TgHint.onHidden].
  void _hide() {
    if (!mounted || !_effectiveShown) {
      return;
    }
    setState(() {
      _internallyHidden = true;
    });
    _animateOut();
  }

  /// Tap-up handling (HintView2.java:1105-1110): a click listener wins over
  /// hide-by-touch.
  void _handleTap() {
    if (widget.onTap != null) {
      widget.onTap!();
    } else if (widget.hideByTouch) {
      _hide();
    }
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  @override
  Widget build(BuildContext context) {
    final Color background = _lastBackground = _color(context, widget.backgroundColorKey);
    final Color textColor = _color(context, widget.textColorKey);
    final EdgeInsets padding = widget.innerPadding ??
        (widget.multiline ? kTgHintInnerPaddingMultiline : kTgHintInnerPadding);
    final bool tappable = widget.onTap != null || widget.hideByTouch;

    Widget content = Text(
      widget.text,
      textAlign: widget.textAlign,
      maxLines: widget.multiline ? null : 1,
      softWrap: widget.multiline,
      textHeightBehavior: kTgTextHeightBehavior,
      // 14dp regular (setTextSize(14), HintView2.java:158) = the subtitle
      // role (API convention 5).
      style: TgTextStyles.subtitle.copyWith(color: textColor),
    );
    if (widget.maxTextWidth != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxTextWidth!),
        child: content,
      );
    }

    return Semantics(
      container: true,
      // The Java view announces its text on show
      // (makeAccessibilityAnnouncement, HintView2.java:634); a live region
      // is the declarative equivalent.
      liveRegion: _effectiveShown,
      child: ExcludeSemantics(
        excluding: !_effectiveShown,
        child: IgnorePointer(
          // Touches are only handled while shown (HintView2.java:1079).
          ignoring: !_effectiveShown,
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onTap: tappable ? _handleTap : null,
            child: AnimatedBuilder(
              animation: _show,
              builder: (BuildContext context, Widget? child) {
                return _HintChrome(
                  key: _chromeKey,
                  direction: widget.direction,
                  joint: widget.joint,
                  jointTranslate: widget.jointTranslate,
                  rounding: widget.rounding,
                  arrowHalfWidth: widget.arrowHalfWidth,
                  arrowHeight: widget.arrowHeight,
                  backgroundColor: background,
                  showFactor: _show.value,
                  child: child!,
                );
              },
              child: Padding(padding: padding, child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bubble geometry computed for the current size: the arrow-free bubble
/// rect (`bounds`, HintView2.java:767), the arrow tip (`arrowX`/`arrowY`,
/// :770) and the combined outline path (`path`, :769).
class _HintGeometry {
  const _HintGeometry({required this.bubble, required this.arrowTip, required this.path});

  final Rect bubble;
  final Offset arrowTip;
  final Path path;
}

/// Draws the bubble + arrow outline (`fillPath`, HintView2.java:958-1070)
/// behind its padded child, reserving [arrowHeight] on the arrow side, and
/// applies the show transform: alpha = factor (:862), scale
/// `lerp(0.75, 1, factor)` around the arrow tip (:865-866). Paints nothing
/// at factor 0 (:834). Hit-testing covers only the bubble, not the arrow
/// (`containsTouch` uses `bounds`, :1090-1092).
class _HintChrome extends SingleChildRenderObjectWidget {
  const _HintChrome({
    super.key,
    required this.direction,
    required this.joint,
    required this.jointTranslate,
    required this.rounding,
    required this.arrowHalfWidth,
    required this.arrowHeight,
    required this.backgroundColor,
    required this.showFactor,
    required super.child,
  });

  final TgHintDirection direction;
  final double joint;
  final double jointTranslate;
  final double rounding;
  final double arrowHalfWidth;
  final double arrowHeight;
  final Color backgroundColor;
  final double showFactor;

  @override
  _RenderHintChrome createRenderObject(BuildContext context) {
    return _RenderHintChrome(
      direction: direction,
      joint: joint,
      jointTranslate: jointTranslate,
      rounding: rounding,
      arrowHalfWidth: arrowHalfWidth,
      arrowHeight: arrowHeight,
      backgroundColor: backgroundColor,
      showFactor: showFactor,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderHintChrome renderObject) {
    renderObject
      ..direction = direction
      ..joint = joint
      ..jointTranslate = jointTranslate
      ..rounding = rounding
      ..arrowHalfWidth = arrowHalfWidth
      ..arrowHeight = arrowHeight
      ..backgroundColor = backgroundColor
      ..showFactor = showFactor;
  }
}

class _RenderHintChrome extends RenderShiftedBox {
  _RenderHintChrome({
    required this._direction,
    required this._joint,
    required this._jointTranslate,
    required this._rounding,
    required this._arrowHalfWidth,
    required this._arrowHeight,
    required this._backgroundColor,
    required this._showFactor,
  }) : super(null);

  TgHintDirection get direction => _direction;
  TgHintDirection _direction;
  set direction(TgHintDirection value) {
    if (_direction != value) {
      _direction = value;
      markNeedsLayout();
    }
  }

  double get joint => _joint;
  double _joint;
  set joint(double value) {
    if (_joint != value) {
      _joint = value;
      markNeedsPaint();
    }
  }

  double get jointTranslate => _jointTranslate;
  double _jointTranslate;
  set jointTranslate(double value) {
    if (_jointTranslate != value) {
      _jointTranslate = value;
      markNeedsPaint();
    }
  }

  double get rounding => _rounding;
  double _rounding;
  set rounding(double value) {
    if (_rounding != value) {
      _rounding = value;
      markNeedsPaint();
    }
  }

  double get arrowHalfWidth => _arrowHalfWidth;
  double _arrowHalfWidth;
  set arrowHalfWidth(double value) {
    if (_arrowHalfWidth != value) {
      _arrowHalfWidth = value;
      markNeedsPaint();
    }
  }

  double get arrowHeight => _arrowHeight;
  double _arrowHeight;
  set arrowHeight(double value) {
    if (_arrowHeight != value) {
      _arrowHeight = value;
      markNeedsLayout();
    }
  }

  Color get backgroundColor => _backgroundColor;
  Color _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor != value) {
      _backgroundColor = value;
      markNeedsPaint();
    }
  }

  double get showFactor => _showFactor;
  double _showFactor;
  set showFactor(double value) {
    if (_showFactor != value) {
      _showFactor = value;
      markNeedsPaint();
    }
  }

  /// The space reserved for the arrow on the [direction] side.
  EdgeInsets get _arrowExtent {
    switch (_direction) {
      case TgHintDirection.left:
        return EdgeInsets.only(left: _arrowHeight);
      case TgHintDirection.top:
        return EdgeInsets.only(top: _arrowHeight);
      case TgHintDirection.right:
        return EdgeInsets.only(right: _arrowHeight);
      case TgHintDirection.bottom:
        return EdgeInsets.only(bottom: _arrowHeight);
    }
  }

  /// The current geometry, or null before layout.
  _HintGeometry? get debugGeometry => hasSize ? _computeGeometry() : null;

  @override
  double computeMinIntrinsicWidth(double height) {
    final EdgeInsets extent = _arrowExtent;
    final double childWidth =
        child?.getMinIntrinsicWidth(math.max(0.0, height - extent.vertical)) ?? 0.0;
    return childWidth + extent.horizontal;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final EdgeInsets extent = _arrowExtent;
    final double childWidth =
        child?.getMaxIntrinsicWidth(math.max(0.0, height - extent.vertical)) ?? 0.0;
    return childWidth + extent.horizontal;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final EdgeInsets extent = _arrowExtent;
    final double childHeight =
        child?.getMinIntrinsicHeight(math.max(0.0, width - extent.horizontal)) ?? 0.0;
    return childHeight + extent.vertical;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final EdgeInsets extent = _arrowExtent;
    final double childHeight =
        child?.getMaxIntrinsicHeight(math.max(0.0, width - extent.horizontal)) ?? 0.0;
    return childHeight + extent.vertical;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final EdgeInsets extent = _arrowExtent;
    final RenderBox? childBox = child;
    if (childBox == null) {
      return constraints.constrain(Size(extent.horizontal, extent.vertical));
    }
    final Size childSize = childBox.getDryLayout(constraints.deflate(extent));
    return constraints.constrain(
      Size(childSize.width + extent.horizontal, childSize.height + extent.vertical),
    );
  }

  @override
  void performLayout() {
    final EdgeInsets extent = _arrowExtent;
    final RenderBox? childBox = child;
    if (childBox == null) {
      size = constraints.constrain(Size(extent.horizontal, extent.vertical));
      return;
    }
    childBox.layout(constraints.deflate(extent), parentUsesSize: true);
    final BoxParentData childParentData = childBox.parentData! as BoxParentData;
    childParentData.offset = Offset(extent.left, extent.top);
    size = constraints.constrain(
      Size(childBox.size.width + extent.horizontal, childBox.size.height + extent.vertical),
    );
  }

  /// Port of `fillPath` (HintView2.java:958-1070), arcs branch
  /// (`roundWithCornerEffect = false`, :995-1053): walks bottom-left →
  /// left edge → top-left → top edge → top-right → right edge →
  /// bottom-right → bottom edge, inserting the arrow on the [direction]
  /// edge with 2dp shoulders and a 1dp-flat tip.
  _HintGeometry _computeGeometry() {
    final EdgeInsets extent = _arrowExtent;
    final Rect bubble = Rect.fromLTRB(
      extent.left,
      extent.top,
      size.width - extent.right,
      size.height - extent.bottom,
    );
    // r = min(rounding, min(width / 2, height / 2)) (HintView2.java:960).
    final double r =
        math.min(_rounding, math.min(bubble.width / 2.0, bubble.height / 2.0));

    // Arrow position along the edge, kept r + arrowHalfWidth off the
    // corners (HintView2.java:962-967 horizontal, :974-979 vertical).
    double arrowAlong(double start, double end) {
      final double lo = start + r + _arrowHalfWidth;
      final double hi = end - r - _arrowHalfWidth;
      final double raw = lerpDouble(start, end, _joint)! + _jointTranslate;
      if (hi <= lo) {
        return (start + end) / 2.0;
      }
      return clampDouble(raw, lo, hi);
    }

    final bool horizontal =
        _direction == TgHintDirection.top || _direction == TgHintDirection.bottom;
    final double arrowXY = horizontal
        ? arrowAlong(bubble.left, bubble.right)
        : arrowAlong(bubble.top, bubble.bottom);

    late final Offset arrowTip;
    switch (_direction) {
      case TgHintDirection.left:
        arrowTip = Offset(bubble.left - _arrowHeight, arrowXY);
      case TgHintDirection.top:
        arrowTip = Offset(arrowXY, bubble.top - _arrowHeight);
      case TgHintDirection.right:
        arrowTip = Offset(bubble.right + _arrowHeight, arrowXY);
      case TgHintDirection.bottom:
        arrowTip = Offset(arrowXY, bubble.bottom + _arrowHeight);
    }

    final Path path = Path();
    // Bottom-left corner (HintView2.java:995-996): arc 90° → 180°.
    path.arcTo(
      Rect.fromLTWH(bubble.left, bubble.bottom - 2 * r, 2 * r, 2 * r),
      math.pi / 2.0,
      math.pi / 2.0,
      true,
    );
    if (_direction == TgHintDirection.left) {
      // Arrow on the left edge, walking upward (HintView2.java:998-1006).
      path.lineTo(bubble.left, arrowXY + _arrowHalfWidth + kTgHintArrowShoulder);
      path.lineTo(bubble.left, arrowXY + _arrowHalfWidth);
      path.lineTo(arrowTip.dx, arrowXY + kTgHintArrowTipFlat);
      path.lineTo(arrowTip.dx, arrowXY - kTgHintArrowTipFlat);
      path.lineTo(bubble.left, arrowXY - _arrowHalfWidth);
      path.lineTo(bubble.left, arrowXY - _arrowHalfWidth - kTgHintArrowShoulder);
    }
    // Top-left corner (HintView2.java:1014-1015): arc 180° → 270°.
    path.arcTo(
      Rect.fromLTWH(bubble.left, bubble.top, 2 * r, 2 * r),
      math.pi,
      math.pi / 2.0,
      false,
    );
    if (_direction == TgHintDirection.top) {
      // Arrow on the top edge, walking rightward (HintView2.java:1017-1025).
      path.lineTo(arrowXY - _arrowHalfWidth - kTgHintArrowShoulder, bubble.top);
      path.lineTo(arrowXY - _arrowHalfWidth, bubble.top);
      path.lineTo(arrowXY - kTgHintArrowTipFlat, arrowTip.dy);
      path.lineTo(arrowXY + kTgHintArrowTipFlat, arrowTip.dy);
      path.lineTo(arrowXY + _arrowHalfWidth, bubble.top);
      path.lineTo(arrowXY + _arrowHalfWidth + kTgHintArrowShoulder, bubble.top);
    }
    // Top-right corner (HintView2.java:1033-1034): arc 270° → 360°.
    path.arcTo(
      Rect.fromLTWH(bubble.right - 2 * r, bubble.top, 2 * r, 2 * r),
      -math.pi / 2.0,
      math.pi / 2.0,
      false,
    );
    if (_direction == TgHintDirection.right) {
      // Arrow on the right edge, walking downward (HintView2.java:1036-1044).
      path.lineTo(bubble.right, arrowXY - _arrowHalfWidth - kTgHintArrowShoulder);
      path.lineTo(bubble.right, arrowXY - _arrowHalfWidth);
      path.lineTo(arrowTip.dx, arrowXY - kTgHintArrowTipFlat);
      path.lineTo(arrowTip.dx, arrowXY + kTgHintArrowTipFlat);
      path.lineTo(bubble.right, arrowXY + _arrowHalfWidth);
      path.lineTo(bubble.right, arrowXY + _arrowHalfWidth + kTgHintArrowShoulder);
    }
    // Bottom-right corner (HintView2.java:1052-1053): arc 0° → 90°.
    path.arcTo(
      Rect.fromLTWH(bubble.right - 2 * r, bubble.bottom - 2 * r, 2 * r, 2 * r),
      0.0,
      math.pi / 2.0,
      false,
    );
    if (_direction == TgHintDirection.bottom) {
      // Arrow on the bottom edge, walking leftward (HintView2.java:1055-1063).
      path.lineTo(arrowXY + _arrowHalfWidth + kTgHintArrowShoulder, bubble.bottom);
      path.lineTo(arrowXY + _arrowHalfWidth, bubble.bottom);
      path.lineTo(arrowXY + kTgHintArrowTipFlat, arrowTip.dy);
      path.lineTo(arrowXY - kTgHintArrowTipFlat, arrowTip.dy);
      path.lineTo(arrowXY - _arrowHalfWidth, bubble.bottom);
      path.lineTo(arrowXY - _arrowHalfWidth - kTgHintArrowShoulder, bubble.bottom);
    }
    path.close();

    return _HintGeometry(bubble: bubble, arrowTip: arrowTip, path: path);
  }

  @override
  bool hitTestSelf(Offset position) {
    // containsTouch checks the arrow-free bounds (HintView2.java:1090-1092).
    return _computeGeometry().bubble.contains(position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final double t = _showFactor;
    if (t <= 0.0) {
      // Nothing is drawn while fully hidden (HintView2.java:834-836).
      return;
    }
    final _HintGeometry geometry = _computeGeometry();

    void paintContents(PaintingContext innerContext, Offset innerOffset) {
      final Paint backgroundPaint = Paint()
        ..isAntiAlias = true
        ..color = _backgroundColor;
      innerContext.canvas.drawPath(geometry.path.shift(innerOffset), backgroundPaint);
      final RenderBox? childBox = child;
      if (childBox != null) {
        final BoxParentData childParentData = childBox.parentData! as BoxParentData;
        innerContext.paintChild(childBox, innerOffset + childParentData.offset);
      }
    }

    if (t >= 1.0) {
      paintContents(context, offset);
      return;
    }

    // scale = lerp(.75f, 1f, showT) around (arrowX, arrowY)
    // (HintView2.java:864-867); alpha = showT (:862).
    final double scale = lerpDouble(kTgHintHiddenScale, 1.0, t)!;
    final Matrix4 transform = Matrix4.translationValues(
        geometry.arrowTip.dx, geometry.arrowTip.dy, 0.0)
      ..multiply(Matrix4.diagonal3Values(scale, scale, 1.0))
      ..multiply(Matrix4.translationValues(
          -geometry.arrowTip.dx, -geometry.arrowTip.dy, 0.0));
    context.pushOpacity(offset, (t * 255.0).round(),
        (PaintingContext opacityContext, Offset opacityOffset) {
      opacityContext.pushTransform(
        needsCompositing,
        opacityOffset,
        transform,
        paintContents,
      );
    });
  }
}
