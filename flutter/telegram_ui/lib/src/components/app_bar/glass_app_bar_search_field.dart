// The in-bar search field of the glass action bar (ARCHITECTURE.md section 6,
// row "GlassAppBar" — the search socket content).
//
// Port of the `ActionBarMenuItem` search layout (`checkCreateSearchField`,
// ActionBarMenuItem.java:1294-1647), every constant cited:
//
// - field text 18dp in `actionBarDefaultSearch`, hint in
//   `actionBarDefaultSearchPlaceholder`, cursor `actionBarDefaultSearch` at
//   width 1.5dp (ActionBarMenuItem.java:1489-1493);
// - field frame: height 36dp, vertically centered, margins 6dp left / 48dp
//   right for the clear slot (ActionBarMenuItem.java:1575);
// - single line, no suggestions (`TYPE_TEXT_FLAG_NO_SUGGESTIONS`,
//   ActionBarMenuItem.java:1494-1498), IME action search
//   (ActionBarMenuItem.java:1557);
// - clear button: a 48dp-wide slot at the trailing edge
//   (ActionBarMenuItem.java:1645) holding a `CloseProgressDrawable2` "X" —
//   2dp round-cap strokes, half-diagonal 8dp (CloseProgressDrawable2.java:
//   40-47) in the bar's `itemsColor` (ActionBarMenuItem.java:1609-1614),
//   ported as `actionBarDefaultIcon`;
// - clear show/hide: 180ms DecelerateInterpolator, hidden at alpha 0 /
//   scale 0 / rotation 45deg (`checkClearButton`,
//   ActionBarMenuItem.java:1666-1703, 1710-1749; hidden state
//   ActionBarMenuItem.java:1617-1618);
// - clear tap empties the field and refocuses it
//   (ActionBarMenuItem.java:1621-1639);
// - enter/search submits: keyboard hidden, `onSearchPressed`
//   (ActionBarMenuItem.java:1509-1516) — focus is kept, so the port keeps
//   focus too and leaves IME dismissal to the platform.
//
// Not ported (out of scope, doc pointers only): the search caption
// (ActionBarMenuItem.java:1437-1443), search filters (`searchFilterLayout`),
// the additional button, the horizontal-scroll wrap, and the RTL mirror.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';

import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';

/// Search field text size: 18dp (`searchField.setTextSize(DIP, 18)`,
/// ActionBarMenuItem.java:1491; the caption matches at
/// ActionBarMenuItem.java:1438).
const double kGlassAppBarSearchTextSize = 18.0;

/// Search field height: 36dp (`createFrame(MATCH_PARENT, 36, ...)`,
/// ActionBarMenuItem.java:1575).
const double kGlassAppBarSearchFieldHeight = 36.0;

/// Search field leading margin inside its container: 6dp
/// (ActionBarMenuItem.java:1575).
const double kGlassAppBarSearchFieldLeftMargin = 6.0;

/// Search field trailing margin — the clear-button slot: 48dp
/// (field margin ActionBarMenuItem.java:1575; clear frame width
/// ActionBarMenuItem.java:1645).
const double kGlassAppBarSearchClearSlotWidth = 48.0;

/// Clear button show/hide duration: 180ms (`AnimatorSet().setDuration(180)`,
/// ActionBarMenuItem.java:1670, 1714).
const Duration kGlassAppBarSearchClearDuration = Duration(milliseconds: 180);

/// Clear button hidden-state rotation: 45 degrees
/// (ActionBarMenuItem.java:1592, 1618, 1699).
const double kGlassAppBarSearchClearHiddenAngle = 45.0;

/// Cursor width: 1.5dp (`setCursorWidth(1.5f)`, ActionBarMenuItem.java:1489).
const double kGlassAppBarSearchCursorWidth = 1.5;

/// Clear "X" stroke width: 2dp (`CloseProgressDrawable2()` delegates to
/// `this(2)`, CloseProgressDrawable2.java:36-46).
const double kGlassAppBarSearchClearStrokeWidth = 2.0;

/// Clear "X" half-diagonal: 8dp (`side = dp(8)`,
/// CloseProgressDrawable2.java:46).
const double kGlassAppBarSearchClearHalfSide = 8.0;

/// The clear show/hide curve: Android's `DecelerateInterpolator` with the
/// default factor 1 — `1 - (1 - t)^2` (ActionBarMenuItem.java:1671, 1715) —
/// which is exactly Flutter's [Curves.decelerate].
const Curve kGlassAppBarSearchClearCurve = Curves.decelerate;

/// The expanded in-bar search field: an 18dp single-line editor over a hint,
/// with the animated clear "X" in a 48dp trailing slot — the
/// `ActionBarMenuItem` search layout (ActionBarMenuItem.java:1294-1647).
///
/// The widget fills whatever box it is given (inside [GlassAppBar] that is
/// the search socket from 66dp to the trailing edge) and centers the 36dp
/// field band vertically, like the Java `CENTER_VERTICAL` frame
/// (ActionBarMenuItem.java:1575).
///
/// [controller] and [focusNode] are optional; internal ones are created (and
/// disposed) when omitted. Like every component in this package, the field
/// takes an optional [resources] override that wins over the ambient theme.
class GlassAppBarSearchField extends StatefulWidget {
  /// Creates the search field.
  const GlassAppBarSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.resources,
  });

  /// Text controller; an internal one is created when null.
  final TextEditingController? controller;

  /// Focus node; an internal one is created when null.
  final FocusNode? focusNode;

  /// Hint shown while the field is empty, in
  /// `actionBarDefaultSearchPlaceholder` (`setHintTextColor`,
  /// ActionBarMenuItem.java:1492).
  final String? hintText;

  /// Text-change callback (`listener.onTextChanged`,
  /// ActionBarMenuItem.java:1536-1538).
  final ValueChanged<String>? onChanged;

  /// Submit callback — the IME search action (`onSearchPressed`,
  /// ActionBarMenuItem.java:1509-1516). Focus is kept, like the Java field
  /// (only the keyboard is hidden there).
  final ValueChanged<String>? onSubmitted;

  /// Whether the field grabs focus when first mounted — the
  /// `searchField.requestFocus()` of the search-open path
  /// (ActionBarMenuItem.java:993-996). [GlassAppBar] drives focus itself on
  /// `searchMode` flips, so this defaults to false.
  final bool autofocus;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  /// Key of the [EditableText].
  static const Key fieldKey = Key('GlassAppBarSearchField.field');

  /// Key of the hint [Text].
  static const Key hintKey = Key('GlassAppBarSearchField.hint');

  /// Key of the clear-button slot.
  static const Key clearButtonKey = Key('GlassAppBarSearchField.clearButton');

  @override
  State<GlassAppBarSearchField> createState() => GlassAppBarSearchFieldState();
}

/// State of [GlassAppBarSearchField]; public for test access to the
/// `debug*` probes.
class GlassAppBarSearchFieldState extends State<GlassAppBarSearchField>
    with SingleTickerProviderStateMixin {
  TextEditingController? _internalController;
  FocusNode? _internalFocusNode;

  /// Clear-button factor 0 hidden .. 1 shown. The curve is baked into the
  /// controller value via `animateTo` ([kGlassAppBarSearchClearCurve]).
  late final AnimationController _clear;

  /// Whether the clear button is logically shown (the Java `clearButton`
  /// tag, ActionBarMenuItem.java:1666, 1708).
  bool _clearShown = false;

  TextEditingController get _effectiveController =>
      widget.controller ?? (_internalController ??= TextEditingController());

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  /// Current clear-button factor (curved), 0 hidden .. 1 shown.
  @visibleForTesting
  double get debugClearFactor => _clear.value;

  /// The controller actually in use (widget-provided or internal).
  @visibleForTesting
  TextEditingController get debugController => _effectiveController;

  /// The focus node actually in use (widget-provided or internal).
  @visibleForTesting
  FocusNode get debugFocusNode => _effectiveFocusNode;

  @override
  void initState() {
    super.initState();
    // The Java clear button is built directly in its resting state for the
    // current text (creation state ActionBarMenuItem.java:1617-1618, then
    // `checkClearButton` on every text change): the first application snaps,
    // later changes animate 180ms.
    _clearShown = _effectiveController.text.isNotEmpty;
    _clear = AnimationController(
      vsync: this,
      duration: kGlassAppBarSearchClearDuration,
      value: _clearShown ? 1.0 : 0.0,
    );
    _effectiveController.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(GlassAppBarSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      (oldWidget.controller ?? _internalController)
          ?.removeListener(_handleTextChanged);
      _effectiveController.addListener(_handleTextChanged);
      _checkClearButton();
    }
  }

  @override
  void dispose() {
    (widget.controller ?? _internalController)
        ?.removeListener(_handleTextChanged);
    _clear.dispose();
    _internalController?.dispose();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    _checkClearButton();
  }

  /// Port of `checkClearButton` (ActionBarMenuItem.java:1660-1750): the
  /// clear button animates in when the text becomes non-empty and out when
  /// it empties — 180ms decelerate, alpha/scale 0..1, rotation 45deg..0.
  void _checkClearButton() {
    final bool show = _effectiveController.text.isNotEmpty;
    if (show == _clearShown) {
      return;
    }
    _clearShown = show;
    _clear.animateTo(
      show ? 1.0 : 0.0,
      duration: kGlassAppBarSearchClearDuration,
      curve: kGlassAppBarSearchClearCurve,
    );
  }

  /// Clear tap (ActionBarMenuItem.java:1621-1639): empty the field, then
  /// refocus it (`searchField.requestFocus()` + show keyboard,
  /// ActionBarMenuItem.java:1637-1639).
  void _handleClearTap() {
    if (_effectiveController.text.isNotEmpty) {
      _effectiveController.clear();
      widget.onChanged?.call('');
    }
    _effectiveFocusNode.requestFocus();
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    return resources != null
        ? resources.getColor(key)
        : TelegramTheme.colorOf(context, key);
  }

  @override
  Widget build(BuildContext context) {
    // Palette (ActionBarMenuItem.java:1489-1493, 1609-1614).
    final Color textColor =
        _color(context, TelegramColorKey.actionBarDefaultSearch);
    final Color hintColor =
        _color(context, TelegramColorKey.actionBarDefaultSearchPlaceholder);
    final Color clearColor =
        _color(context, TelegramColorKey.actionBarDefaultIcon);

    final TextStyle textStyle = TextStyle(
      fontSize: kGlassAppBarSearchTextSize,
      color: textColor,
    );
    final TextEditingController controller = _effectiveController;

    return Stack(
      children: <Widget>[
        // Field band: margins 6dp / 48dp, height 36dp, centered vertically
        // (ActionBarMenuItem.java:1575).
        Positioned.fill(
          left: kGlassAppBarSearchFieldLeftMargin,
          right: kGlassAppBarSearchClearSlotWidth,
          child: Center(
            child: SizedBox(
              height: kGlassAppBarSearchFieldHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _effectiveFocusNode.requestFocus(),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (BuildContext context, TextEditingValue value,
                      Widget? child) {
                    return Stack(
                      alignment: AlignmentDirectional.centerStart,
                      children: <Widget>[
                        // The hint stays mounted and fades by opacity so the
                        // sibling EditableText element is never re-slotted
                        // (same pattern as the chat input field).
                        if (widget.hintText != null)
                          ExcludeSemantics(
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: value.text.isEmpty ? 1.0 : 0.0,
                                child: Text(
                                  widget.hintText!,
                                  key: GlassAppBarSearchField.hintKey,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  textScaler: TextScaler.noScaling,
                                  style: TextStyle(
                                    fontSize: kGlassAppBarSearchTextSize,
                                    color: hintColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        EditableText(
                          key: GlassAppBarSearchField.fieldKey,
                          controller: controller,
                          focusNode: _effectiveFocusNode,
                          autofocus: widget.autofocus,
                          style: textStyle,
                          // Cursor `actionBarDefaultSearch` at 1.5dp
                          // (ActionBarMenuItem.java:1489-1490).
                          cursorColor: textColor,
                          cursorWidth: kGlassAppBarSearchCursorWidth,
                          // No Android floating-cursor analog; reuse the
                          // placeholder grey for the iOS backing cursor.
                          backgroundCursorColor: hintColor,
                          selectionColor: _color(context,
                              TelegramColorKey.chat_inTextSelectionHighlight),
                          maxLines: 1,
                          // TYPE_TEXT_FLAG_NO_SUGGESTIONS
                          // (ActionBarMenuItem.java:1494-1498).
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.text,
                          // IME_ACTION_SEARCH (ActionBarMenuItem.java:1557).
                          textInputAction: TextInputAction.search,
                          onChanged: widget.onChanged,
                          onSubmitted: widget.onSubmitted,
                          // The Java submit hides the keyboard but keeps
                          // focus (ActionBarMenuItem.java:1509-1516);
                          // overriding onEditingComplete keeps EditableText
                          // from unfocusing.
                          onEditingComplete: controller.clearComposing,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        // Clear slot: 48dp wide at the trailing edge, full height, centered
        // (ActionBarMenuItem.java:1645).
        Positioned.fill(
          left: null,
          child: SizedBox(
            width: kGlassAppBarSearchClearSlotWidth,
            child: AnimatedBuilder(
              animation: _clear,
              builder: (BuildContext context, Widget? child) {
                final double factor = clampDouble(_clear.value, 0.0, 1.0);
                return GestureDetector(
                  key: GlassAppBarSearchField.clearButtonKey,
                  behavior: HitTestBehavior.opaque,
                  // The Java button stays clickable while hidden (only
                  // INVISIBLE after the out-animation) and refocuses the
                  // field (ActionBarMenuItem.java:1621-1639).
                  onTap: _handleClearTap,
                  child: Center(
                    child: Opacity(
                      opacity: factor,
                      child: Transform.rotate(
                        // 45deg hidden -> 0 shown
                        // (ActionBarMenuItem.java:1618, 1699, 1741).
                        angle: (1.0 - factor) *
                            kGlassAppBarSearchClearHiddenAngle *
                            math.pi /
                            180.0,
                        child: Transform.scale(
                          scale: factor,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: CustomPaint(
                size: const Size.square(kGlassAppBarSearchClearHalfSide * 2),
                painter: _ClearCrossPainter(color: clearColor),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The clear "X": two 2dp round-cap strokes crossing at 45deg with
/// half-diagonal 8dp — the resting frame of `CloseProgressDrawable2`
/// (CloseProgressDrawable2.java:36-47; the progress-spinner arm is not
/// ported).
class _ClearCrossPainter extends CustomPainter {
  const _ClearCrossPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = kGlassAppBarSearchClearStrokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final Offset center = size.center(Offset.zero);
    // side = dp(8) along both diagonals (CloseProgressDrawable2 draws the
    // two lines rotated 45deg about the center).
    const double d =
        kGlassAppBarSearchClearHalfSide * 0.70710678118654752; // /sqrt(2)
    canvas.drawLine(
      center + const Offset(-d, -d),
      center + const Offset(d, d),
      paint,
    );
    canvas.drawLine(
      center + const Offset(-d, d),
      center + const Offset(d, -d),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ClearCrossPainter oldDelegate) =>
      oldDelegate.color != color;
}
