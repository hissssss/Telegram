// Port of `ui/Components/EditTextBoldCursor.java` (ETB below) — the base
// Telegram form/login/dialog input — as an [EditableText]-based widget
// (flutter/docs/spec_primitives.md section 5, PLAN_UIKIT M11):
//
// - block cursor 2dp x 24dp (ETB:121, 416; the forms recipe narrows it to
//   1.5dp x 20dp, ChangeNameActivity.java:110-111), default color
//   `0xff54a1db` (ETB:360, 396), blinking 500ms on / 500ms off (ETB:896 —
//   matching Flutter's own [EditableText] half-second blink);
// - underline: 1dp `windowBackgroundWhiteInputField` resting ~6dp under the
//   text (ETB:605, 978), focused 2dp `windowBackgroundWhiteInputFieldActivated`
//   expanding horizontally from the last touch x (center fallback) —
//   activeness 150ms, EASE_BOTH at draw (ETB:723-730, 977-1023); a non-empty
//   [TgTextField.errorText] snaps the resting line to 2dp `text_RedRegular`
//   (ETB:980-983; color per the `setLineColors` caller convention, e.g.
//   ChangeNameActivity.java:100);
// - hint drawn only while empty (ETB:753), alpha fading linearly over 150ms
//   (ETB:756-775); floating-label mode (`setTransformHintToHeader`) scales
//   the hint x0.7 and raises it 22dp while blending
//   `windowBackgroundWhiteHintText` -> `windowBackgroundWhiteBlueHeader`,
//   200ms EASE_OUT_QUINT (ETB:667-686, 814-827);
// - forms text recipe: 18dp `windowBackgroundWhiteBlackText`
//   (ChangeNameActivity.java:96-98) = the [TgTextStyles.input] role;
// - outlined variant: wraps the editor in a [TgOutlineContainer]
//   (`OutlineTextContainerView`), label = [TgTextField.hintText], selection
//   driven by focus (LoginActivity.java:5384), 16dp inner padding and the
//   1.5dp x 20dp `windowBackgroundWhiteInputFieldActivated` cursor of the
//   outlined call sites (TwoStepVerificationSetupActivity.java:710-722).
//
// Port notes / divergences:
// - the underline's bottom edge is pinned to the widget's bottom, 6dp under
//   the text (ETB:605); the Java scroll-compensation (ETB:1002-1003) and the
//   no-hint `measuredHeight - 2dp` variant (ETB:608) are not reproduced;
// - the error caption itself is NOT rendered — Java's own error-layout draw
//   is commented out (ETB:1040-1045) and callers render the label; only the
//   line recolor is ported;
// - floating-label mode reserves [kTgTextFieldHeaderRise] of headroom above
//   the text so the raised header stays inside the widget's bounds (Java
//   relies on the caller's row height);
// - deliberately NOT ported: the RTL hint mirror (ETB:808-813), the animated
//   per-substring hint hot-swap (ETB:621-651), and the reflective
//   Editor/cursor plumbing (Flutter's [EditableText] owns the caret).
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';

import '../foundation/tg_curves.dart';
import '../foundation/tg_text_styles.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';
import 'tg_outline_container.dart';

/// Default cursor width: 2dp (`cursorWidth = 2.0f`, ETB:121).
const double kTgTextFieldCursorWidth = 2.0;

/// Default cursor height: 24dp (`cursorSize = dp(24)`, ETB:416), vertically
/// centered on the line (ETB:926-927).
const double kTgTextFieldCursorHeight = 24.0;

/// Forms-recipe cursor width: 1.5dp (`setCursorWidth(1.5f)`,
/// ChangeNameActivity.java:111, LoginActivity.java:2324, ...).
const double kTgTextFieldFormsCursorWidth = 1.5;

/// Forms-recipe cursor height: 20dp (`setCursorSize(dp(20))`,
/// ChangeNameActivity.java:110, LoginActivity.java:2323, ...).
const double kTgTextFieldFormsCursorHeight = 20.0;

/// Default cursor color, hardcoded in Java: `0xff54a1db` (ETB:360, 396).
/// No theme key resolves to this value; [TgTextField.cursorColor] overrides
/// (`setCursorColor`, ETB:469-477 — forms callers pass the text color,
/// ChangeNameActivity.java:109).
const Color kTgTextFieldCursorColor = Color(0xFF54A1DB);

/// Resting underline thickness: 1dp (`lineWidth = dp(1)`, ETB:978).
const double kTgTextFieldLineThickness = 1.0;

/// Active/error underline thickness: 2dp (`lineWidth = dp(2)` on error,
/// ETB:982; `lineThickness = ... * dp(2)`, ETB:1014).
const double kTgTextFieldActiveLineThickness = 2.0;

/// Gap between the text bottom and the underline's bottom edge: 6dp
/// (`lineY = ... + hintLayout.getHeight() + dp(6)`, ETB:605).
const double kTgTextFieldLineGap = 6.0;

/// Underline activeness duration: 150ms (`t = elapsed / 150.0f`, ETB:994).
const Duration kTgTextFieldLineDuration = Duration(milliseconds: 150);

/// Hint alpha fade duration: 150ms, linear (`hintAlpha += dt / 150.0f`,
/// ETB:764, 769).
const Duration kTgTextFieldHintFadeDuration = Duration(milliseconds: 150);

/// Floating-label (header) transform duration: 200ms
/// (`setDuration(200)`, ETB:678), EASE_OUT_QUINT (ETB:679).
const Duration kTgTextFieldHeaderDuration = Duration(milliseconds: 200);

/// Floated header scale: 0.7 (`scale = 1.0f - 0.3f * headerAnimationProgress`,
/// ETB:815).
const double kTgTextFieldHeaderScale = 0.7;

/// Floated header rise: 22dp (`canvas.translate(0, -dp(22) * progress)`,
/// ETB:823). Also the headroom the port reserves above the text in
/// floating-label mode.
const double kTgTextFieldHeaderRise = 22.0;

/// Inner padding of the outlined variant: 16dp on all sides
/// (`editText.setPadding(padding, padding, padding, padding)` with
/// `padding = dp(16)`, TwoStepVerificationSetupActivity.java:712-713).
const double kTgTextFieldOutlinedPadding = 16.0;

/// The general Telegram text field — an 18dp `windowBackgroundWhiteBlackText`
/// editor with the Telegram block cursor, the animated 1dp->2dp underline
/// (default style) or a spring-outlined frame (`.outlined`) — the
/// `ui/Components/EditTextBoldCursor.java` (+ `OutlineTextContainerView`)
/// port.
///
/// A controlled widget in the package convention: text state lives in
/// [controller], focus in [focusNode] (internal fallbacks are created and
/// disposed when omitted), and [errorText]'s presence drives the error
/// recolor. The error string itself is not rendered, matching Java
/// (ETB:1040-1045 commented out) — render the caption yourself.
///
/// Like every component in this package, the field takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise keys resolve through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class TgTextField extends StatefulWidget {
  /// Creates the underline-style field (the `EditTextBoldCursor` forms
  /// default, ChangeNameActivity.java:96-112).
  const TgTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.errorText,
    this.floatingLabel = false,
    this.autofocus = false,
    this.obscureText = false,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.cursorWidth = kTgTextFieldCursorWidth,
    this.cursorHeight = kTgTextFieldCursorHeight,
    this.cursorColor,
    this.resources,
  }) : outlined = false;

  /// Creates the outlined variant (`OutlineTextContainerView` wrapping the
  /// editor, TwoStepVerificationSetupActivity.java:707-735): [hintText]
  /// becomes the frame label, floating between the field center and the gap
  /// in the top stroke; the cursor defaults to the outlined call sites'
  /// 1.5dp x 20dp in `windowBackgroundWhiteInputFieldActivated`
  /// (TwoStepVerificationSetupActivity.java:714, 720-722).
  const TgTextField.outlined({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.errorText,
    this.autofocus = false,
    this.obscureText = false,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.cursorWidth = kTgTextFieldFormsCursorWidth,
    this.cursorHeight = kTgTextFieldFormsCursorHeight,
    this.cursorColor,
    this.resources,
  })  : outlined = true,
        floatingLabel = false;

  /// Text controller; an internal one is created when null.
  final TextEditingController? controller;

  /// Focus node; an internal one is created when null.
  final FocusNode? focusNode;

  /// Hint shown while the field is empty (`setHintText`, ETB:613-615), in
  /// `windowBackgroundWhiteHintText` (ChangeNameActivity.java:97). In the
  /// outlined variant this is the frame label instead.
  final String? hintText;

  /// Non-null and non-empty puts the field in its error state: the underline
  /// snaps to 2dp `text_RedRegular` (`setErrorText`, ETB:980-983), the
  /// outlined frame blends to `text_RedBold` (OutlineTextContainerView.java:
  /// 126-128). The string itself is NOT rendered (Java parity, ETB:
  /// 1040-1045).
  final String? errorText;

  /// Underline style only: transform the hint into a floating header when
  /// focused or non-empty — scale x0.7, rise 22dp, color to
  /// `windowBackgroundWhiteBlueHeader` (`setTransformHintToHeader`,
  /// ETB:444-453, 667-686, 814-827).
  final bool floatingLabel;

  /// Whether the field grabs focus when first mounted.
  final bool autofocus;

  /// Obscure the text (password rows, TwoStepVerificationSetupActivity).
  final bool obscureText;

  /// Maximum visible lines; the Java forms fields are single-line
  /// (`setSingleLine(true)`, ChangeNameActivity.java:103).
  final int maxLines;

  /// Keyboard type; defaults to [TextInputType.text].
  final TextInputType? keyboardType;

  /// IME action (`setImeOptions`, ChangeNameActivity.java:106).
  final TextInputAction? textInputAction;

  /// Text-change callback.
  final ValueChanged<String>? onChanged;

  /// IME submit callback.
  final ValueChanged<String>? onSubmitted;

  /// Cursor width: 2dp default, 1.5dp forms/outlined (ETB:121,
  /// ChangeNameActivity.java:111).
  final double cursorWidth;

  /// Cursor height: 24dp default, 20dp forms/outlined (ETB:416,
  /// ChangeNameActivity.java:110).
  final double cursorHeight;

  /// Cursor color override (`setCursorColor`, ETB:469-477). Defaults to
  /// [kTgTextFieldCursorColor] (underline) or
  /// `windowBackgroundWhiteInputFieldActivated` (outlined,
  /// TwoStepVerificationSetupActivity.java:714).
  final Color? cursorColor;

  /// Whether this is the outlined variant (`.outlined`).
  final bool outlined;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  /// Key of the [EditableText].
  static const Key fieldKey = Key('TgTextField.field');

  /// Key of the hint [Text] (underline style).
  static const Key hintKey = Key('TgTextField.hint');

  @override
  State<TgTextField> createState() => TgTextFieldState();
}

/// State of [TgTextField]; public for test access to the `debug*` probes.
class TgTextFieldState extends State<TgTextField>
    with TickerProviderStateMixin {
  TextEditingController? _internalController;
  FocusNode? _internalFocusNode;

  TextEditingController get _effectiveController =>
      widget.controller ?? (_internalController ??= TextEditingController());

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  /// Linear 0..1 clock of the underline activeness transition
  /// (`t = elapsed / 150`, ETB:994); the raw activeness lerps
  /// [_lastLineActiveness] toward the [_lineActive] target with it
  /// (ETB:996).
  late final AnimationController _line = AnimationController(
      vsync: this, duration: kTgTextFieldLineDuration, value: 1.0);

  /// Hint alpha, 150ms linear (`hintAlpha`, ETB:756-775).
  late final AnimationController _hint;

  /// Header (floating label) progress, 200ms EASE_OUT_QUINT baked in via
  /// `animateTo` (`headerAnimationProgress`, ETB:677-679).
  late final AnimationController _header;

  /// `lineActive` (ETB:132): focused and not in error (ETB:980-989).
  bool _lineActive = false;

  /// `lastLineActiveness` (ETB:135): the activeness frozen at the last
  /// active-state flip (ETB:990-993). While deactivating this is also what
  /// keeps the expanded width frozen (`activeLineWidth` is only recomputed
  /// while active, ETB:1011-1013).
  double _lastLineActiveness = 0.0;

  /// `lastTouchX` (ETB:723): local x of the last pointer down, -1 = unset
  /// (center fallback, ETB:1004).
  double _lastTouchX = -1.0;

  bool _isEmpty = true;
  bool _headerShown = false;

  bool get _hasError =>
      widget.errorText != null && widget.errorText!.isNotEmpty;

  /// Raw (un-eased) line activeness 0..1 (`lineActiveness`, ETB:133, 996).
  double get debugLineActiveness =>
      lerpDouble(_lastLineActiveness, _lineActive ? 1.0 : 0.0, _line.value)!;

  /// Whether the line is currently active (`lineActive`, ETB:132).
  bool get debugLineActive => _lineActive;

  /// Activeness frozen at the last flip (`lastLineActiveness`, ETB:135).
  double get debugFrozenLineActiveness => _lastLineActiveness;

  /// Last recorded pointer-down x, -1 = unset (`lastTouchX`, ETB:723).
  double get debugLastTouchX => _lastTouchX;

  /// Header progress 0..1, EASE_OUT_QUINT already applied
  /// (`headerAnimationProgress`, ETB:142).
  double get debugHeaderProgress => _header.value;

  /// Hint alpha 0..1 (`hintAlpha`, ETB:117).
  double get debugHintAlpha => _hint.value;

  /// The controller actually in use (widget-provided or internal).
  TextEditingController get debugController => _effectiveController;

  /// The focus node actually in use (widget-provided or internal).
  FocusNode get debugFocusNode => _effectiveFocusNode;

  @override
  void initState() {
    super.initState();
    _isEmpty = _effectiveController.text.isEmpty;
    _headerShown = widget.floatingLabel && !_isEmpty;
    _hint = AnimationController(
      vsync: this,
      duration: kTgTextFieldHintFadeDuration,
      value: _isEmpty ? 1.0 : 0.0,
    );
    _header = AnimationController(
      vsync: this,
      duration: kTgTextFieldHeaderDuration,
      value: _headerShown ? 1.0 : 0.0,
    );
    _effectiveController.addListener(_handleTextChanged);
    _effectiveFocusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(TgTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      (oldWidget.controller ?? _internalController)
          ?.removeListener(_handleTextChanged);
      _effectiveController.addListener(_handleTextChanged);
      _handleTextChanged();
    }
    if (widget.focusNode != oldWidget.focusNode) {
      (oldWidget.focusNode ?? _internalFocusNode)
          ?.removeListener(_handleFocusChanged);
      _effectiveFocusNode.addListener(_handleFocusChanged);
    }
    // errorText / floatingLabel changes re-derive the animated states.
    _updateLineActive();
    _checkHeader();
  }

  @override
  void dispose() {
    (widget.controller ?? _internalController)
        ?.removeListener(_handleTextChanged);
    (widget.focusNode ?? _internalFocusNode)
        ?.removeListener(_handleFocusChanged);
    _line.dispose();
    _hint.dispose();
    _header.dispose();
    _internalController?.dispose();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    final bool empty = _effectiveController.text.isEmpty;
    if (empty == _isEmpty) {
      return;
    }
    setState(() {
      _isEmpty = empty;
    });
    // Hint visibility fade, 150ms linear (ETB:756-775; Java hides the plain
    // hint the moment the text is non-empty, ETB:753 — the port routes the
    // emptiness flip through the same 150ms fade `setHintVisible` uses).
    _hint.animateTo(empty ? 1.0 : 0.0,
        duration: kTgTextFieldHintFadeDuration);
    _checkHeader();
  }

  void _handleFocusChanged() {
    setState(() {});
    _updateLineActive();
    _checkHeader();
  }

  /// Port of the activeness flip bookkeeping (ETB:979-993): freeze the
  /// current activeness and restart the 150ms clock.
  void _updateLineActive() {
    final bool active = _effectiveFocusNode.hasFocus && !_hasError;
    if (active == _lineActive) {
      return;
    }
    _lastLineActiveness = debugLineActiveness;
    _lineActive = active;
    _line.forward(from: 0.0);
  }

  /// Port of `checkHeaderVisibility` (ETB:667-686): the hint becomes a
  /// header while focused or non-empty, 200ms EASE_OUT_QUINT.
  void _checkHeader() {
    final bool shown =
        widget.floatingLabel && (_effectiveFocusNode.hasFocus || !_isEmpty);
    if (shown == _headerShown) {
      return;
    }
    _headerShown = shown;
    _header.animateTo(
      shown ? 1.0 : 0.0,
      duration: kTgTextFieldHeaderDuration,
      curve: TgCurves.easeOutQuint,
    );
  }

  /// ACTION_DOWN records the x the active line expands from (ETB:723-730).
  ///
  /// A raw pointer listener, not a tap recognizer: like the Java
  /// `onTouchEvent` this must see every down, including the ones the
  /// editor's own tap recognizer wins.
  void _handlePointerDown(PointerDownEvent event) {
    _lastTouchX = event.localPosition.dx;
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    return resources != null
        ? resources.getColor(key)
        : TelegramTheme.colorOf(context, key);
  }

  @override
  Widget build(BuildContext context) {
    // Forms palette (ChangeNameActivity.java:96-100).
    final Color textColor =
        _color(context, TelegramColorKey.windowBackgroundWhiteBlackText);
    final Color hintColor =
        _color(context, TelegramColorKey.windowBackgroundWhiteHintText);
    final Color cursorColor = widget.cursorColor ??
        (widget.outlined
            ? _color(context,
                TelegramColorKey.windowBackgroundWhiteInputFieldActivated)
            : kTgTextFieldCursorColor);

    final Widget editable = EditableText(
      key: TgTextField.fieldKey,
      controller: _effectiveController,
      focusNode: _effectiveFocusNode,
      autofocus: widget.autofocus,
      // 18dp regular `windowBackgroundWhiteBlackText`
      // (ChangeNameActivity.java:96-98) — the TgTextStyles.input role,
      // dp-fixed like the Java COMPLEX_UNIT_DIP size.
      style: TgTextStyles.input.copyWith(color: textColor),
      textScaler: TextScaler.noScaling,
      textHeightBehavior: kTgTextHeightBehavior,
      // The Telegram block cursor (ETB:121, 416); Flutter's EditableText
      // blinks it 500ms on / 500ms off like Java (ETB:896).
      cursorColor: cursorColor,
      cursorWidth: widget.cursorWidth,
      cursorHeight: widget.cursorHeight,
      // No Android floating-cursor analog; reuse the hint grey for the iOS
      // backing cursor (GlassAppBarSearchField precedent).
      backgroundCursorColor: hintColor,
      selectionColor:
          _color(context, TelegramColorKey.chat_inTextSelectionHighlight),
      maxLines: widget.maxLines,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType ?? TextInputType.text,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );

    final Widget core = widget.outlined
        ? editable
        : Stack(
            alignment: AlignmentDirectional.centerStart,
            children: <Widget>[
              if (widget.hintText != null) _buildHint(context, hintColor),
              editable,
            ],
          );

    final Widget body = widget.outlined
        ? TgOutlineContainer(
            // The frame label is the field's hint
            // (`outlineField.setText(...)` next to the field's creation,
            // TwoStepVerificationSetupActivity.java:707-734).
            label: widget.hintText ?? '',
            // `animateSelection(hasFocus ? 1f : 0f)`
            // (LoginActivity.java:5384 et al.; `floating` follows).
            selected: _effectiveFocusNode.hasFocus,
            // `attachedEditText.length() == 0` (OutlineTextContainerView
            // .java:199) — a filled field keeps its label floated.
            useCenter: _isEmpty,
            error: _hasError,
            resources: widget.resources,
            child: Padding(
              // dp(16) all around (TwoStepVerificationSetupActivity.java:
              // 712-713).
              padding: const EdgeInsets.all(kTgTextFieldOutlinedPadding),
              child: core,
            ),
          )
        : AnimatedBuilder(
            animation: _line,
            builder: (BuildContext context, Widget? child) {
              return CustomPaint(
                foregroundPainter: TgTextFieldUnderlinePainter(
                  lineColor: _color(context,
                      TelegramColorKey.windowBackgroundWhiteInputField),
                  activeLineColor: _color(
                      context,
                      TelegramColorKey
                          .windowBackgroundWhiteInputFieldActivated),
                  // `text_RedRegular` per the setLineColors caller
                  // convention (ChangeNameActivity.java:100).
                  errorLineColor:
                      _color(context, TelegramColorKey.text_RedRegular),
                  hasError: _hasError,
                  lineActive: _lineActive,
                  lineActiveness: debugLineActiveness,
                  frozenActiveness: _lastLineActiveness,
                  touchX: _lastTouchX,
                ),
                child: child,
              );
            },
            child: Padding(
              padding: EdgeInsets.only(
                // Headroom for the raised header (see the library header's
                // port notes).
                top: widget.floatingLabel ? kTgTextFieldHeaderRise : 0.0,
                // The line band: bottom edge 6dp under the text (ETB:605),
                // thickness growing upward into the gap (ETB:1007,
                // 1015-1021).
                bottom: kTgTextFieldLineGap,
              ),
              child: core,
            ),
          );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      // Taps on the editor itself are focused by EditableText's own tap
      // recognizer; this detector catches taps on the rest of the field
      // (hint band, line gap, outlined padding) so the whole row focuses,
      // like the Java view.
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _effectiveFocusNode.requestFocus,
        child: body,
      ),
    );
  }

  /// The hint / floating header (underline style): fades 150ms linear while
  /// plain (ETB:756-775), or — in floating-label mode — scales x0.7, rises
  /// 22dp and blends toward `windowBackgroundWhiteBlueHeader` (ETB:814-827;
  /// header color per the caller convention, e.g. PaymentFormActivity).
  Widget _buildHint(BuildContext context, Color hintColor) {
    final Color headerColor =
        _color(context, TelegramColorKey.windowBackgroundWhiteBlueHeader);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_hint, _header]),
          builder: (BuildContext context, Widget? child) {
            final double progress = _header.value;
            return Opacity(
              // The header branch ignores hintAlpha (ETB:814-827 vs 826-827).
              opacity:
                  widget.floatingLabel ? 1.0 : clampDouble(_hint.value, 0, 1),
              child: Transform.translate(
                // -dp(22) * progress (ETB:823).
                offset: Offset(0.0, -kTgTextFieldHeaderRise * progress),
                child: Transform.scale(
                  // 1 - 0.3 * progress (ETB:815), pivoting at the hint's
                  // start edge like the Java canvas scale (ETB:818-822).
                  scale: 1.0 - (1.0 - kTgTextFieldHeaderScale) * progress,
                  alignment: AlignmentDirectional.topStart,
                  child: Text(
                    widget.hintText!,
                    key: TgTextField.hintKey,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.noScaling,
                    textHeightBehavior: kTgTextHeightBehavior,
                    // The hint is drawn with the field's own 18dp paint
                    // (ETB:799, 824-827).
                    style: TgTextStyles.input.copyWith(
                      color: Color.lerp(hintColor, headerColor, progress),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints the underline of the default [TgTextField] style — the line block
/// of `EditTextBoldCursor.onDraw` (ETB:977-1023):
///
/// - resting: 1dp [lineColor] across the full width (2dp [errorLineColor]
///   when [hasError]), drawn while the activeness has not saturated;
/// - active: 2dp [activeLineColor] expanding horizontally from [touchX]
///   (center fallback), width/thickness eased with EASE_BOTH (ETB:1010);
///   on deactivation the width stays frozen while the thickness collapses
///   (ETB:1011-1014).
///
/// The line's bottom edge is the painter's bottom edge; size the paint area
/// so that its bottom sits [kTgTextFieldLineGap] under the text (ETB:605).
class TgTextFieldUnderlinePainter extends CustomPainter {
  /// Creates the painter with resolved colors and state.
  TgTextFieldUnderlinePainter({
    required this.lineColor,
    required this.activeLineColor,
    required this.errorLineColor,
    this.hasError = false,
    this.lineActive = false,
    this.lineActiveness = 0.0,
    this.frozenActiveness = 0.0,
    this.touchX = -1.0,
    super.repaint,
  });

  /// Resting line color — `windowBackgroundWhiteInputField` (`lineColor`,
  /// ETB:128, 987).
  final Color lineColor;

  /// Active line color — `windowBackgroundWhiteInputFieldActivated`
  /// (`activeLineColor`, ETB:129, 496).
  final Color activeLineColor;

  /// Error line color — `text_RedRegular` (`errorLineColor`, ETB:130,
  /// 981; caller convention ChangeNameActivity.java:100).
  final Color errorLineColor;

  /// Whether `errorText` is non-empty (ETB:980).
  final bool hasError;

  /// `lineActive` — focused and error-free (ETB:983-988).
  final bool lineActive;

  /// Raw activeness 0..1 (`lineActiveness`, ETB:996); EASE_BOTH is applied
  /// at draw time (ETB:1010).
  final double lineActiveness;

  /// Activeness frozen at the last flip — the expanded width source while
  /// deactivating (`activeLineWidth` is only recomputed while active,
  /// ETB:1011-1013).
  final double frozenActiveness;

  /// Local x the active line expands from; negative = unset -> center
  /// (`lastTouchX`, ETB:1004).
  final double touchX;

  /// The resting line, or null once the activeness saturates
  /// (`if (lineActiveness < 1f)`, ETB:1006-1008).
  Rect? baseLineRect(Size size) {
    if (lineActiveness >= 1.0) {
      return null;
    }
    final double thickness = hasError
        ? kTgTextFieldActiveLineThickness // dp(2) on error (ETB:982).
        : kTgTextFieldLineThickness; // dp(1) (ETB:978).
    return Rect.fromLTRB(
        0.0, size.height - thickness, size.width, size.height);
  }

  /// The active line, or null while fully inactive
  /// (`if (lineActiveness > 0f)`, ETB:1009-1022).
  Rect? activeLineRect(Size size) {
    if (lineActiveness <= 0.0) {
      return null;
    }
    final double eased =
        TgCurves.easeBoth.transform(clampDouble(lineActiveness, 0.0, 1.0));
    // centerX / maxWidth (ETB:1004-1005).
    final double centerX = touchX < 0.0 ? size.width / 2.0 : touchX;
    final double maxWidth =
        math.max(centerX, size.width - centerX) * 2.0;
    // Width grows with the eased activeness while active and stays frozen
    // while deactivating (ETB:1011-1013).
    final double width = maxWidth *
        TgCurves.easeBoth.transform(
            clampDouble(lineActive ? lineActiveness : frozenActiveness, 0, 1));
    // Thickness: full 2dp while activating, collapsing with the eased
    // activeness while deactivating (ETB:1014).
    final double thickness =
        (lineActive ? 1.0 : eased) * kTgTextFieldActiveLineThickness;
    return Rect.fromLTRB(
      math.max(0.0, centerX - width / 2.0),
      size.height - thickness,
      math.min(centerX + width / 2.0, size.width),
      size.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Rect? base = baseLineRect(size);
    if (base != null) {
      canvas.drawRect(
          base, Paint()..color = hasError ? errorLineColor : lineColor);
    }
    final Rect? active = activeLineRect(size);
    if (active != null && !active.isEmpty) {
      canvas.drawRect(active, Paint()..color = activeLineColor);
    }
  }

  @override
  bool shouldRepaint(TgTextFieldUnderlinePainter oldDelegate) =>
      oldDelegate.lineColor != lineColor ||
      oldDelegate.activeLineColor != activeLineColor ||
      oldDelegate.errorLineColor != errorLineColor ||
      oldDelegate.hasError != hasError ||
      oldDelegate.lineActive != lineActive ||
      oldDelegate.lineActiveness != lineActiveness ||
      oldDelegate.frozenActiveness != frozenActiveness ||
      oldDelegate.touchX != touchX;
}
