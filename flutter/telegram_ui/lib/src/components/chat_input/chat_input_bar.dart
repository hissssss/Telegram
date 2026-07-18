// The chat input island — the glass bar shell hosting the message field and
// the button slots (flutter/docs/spec_chat_input.md sections 1-2).
//
// Port of the glass-era input surface, assembled from two Java classes:
//
//  * `java/org/telegram/ui/Components/chat/ChatInputViewsContainer.java`
//    (**CIVC**) — draws the floating island bubble: radius
//    `INPUT_BUBBLE_RADIUS` 22dp (CIVC:27), drawable padding `dp(7)`
//    (CIVC:81), bottom gap `INPUT_BUBBLE_BOTTOM` 9dp (CIVC:30), color recipe
//    `bottomPanelChatActivity` over `chat_messagePanelBackground`
//    (ChatActivity.java:3547) — the ported `GlassPresets.bottomPanelChat`.
//    The under-keyboard sibling adds `setThickness(dp(32))` /
//    `setIntensity(0.4f)` (CIVC:89-90) — the liquid parameters this bar's
//    default [LiquidGlassSettings] carries.
//  * `java/org/telegram/ui/Components/ChatActivityEnterView.java` (**CAEV**)
//    — the bar content: `DEFAULT_HEIGHT` 44dp (CAEV:6410), the 18dp
//    bottom-gravity message field with 9/10dp vertical padding and maxLines 6
//    (CAEV:5751-5754), field frame margins left 50dp / right 50dp inside the
//    44dp-right-inset field container (CAEV:2660, 14399-14402, 5763), the
//    44x44dp emoji slot at leftMargin 3dp (CAEV:2713, 14399), the 44x44dp
//    attach slot at the container's bottom-right (CAEV:2783-2794), and the
//    send/mic slot at the bar's bottom-right corner (sendButtonContainer,
//    CAEV:2897-2931). Height changes animate through a `FactorAnimator` at
//    `ChatListItemAnimator.DEFAULT_DURATION` 250ms with its
//    `DEFAULT_INTERPOLATOR` (CAEV:2623-2628, 15456;
//    androidx/recyclerview/widget/ChatListItemAnimator.java:44-45).
//
// The record/send button, the emoji toggle, and the attach button are
// **slots** ([ChatInputBar.emojiSlot], [ChatInputBar.attachSlot],
// [ChatInputBar.sendSlot]) — the widgets themselves live elsewhere; this file
// only reserves their Java frames. No send logic exists here.
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';

import '../../glass/geometry.dart';
import '../../glass/glass_panel.dart';
import '../../glass/liquid_glass_settings.dart';
import '../../glass/presets.dart';
import '../../glass/strategy.dart';
import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';

/// Corner radius of the input island bubble: `INPUT_BUBBLE_RADIUS` = 22
/// (CIVC:27, applied CIVC:82).
const double kChatInputBubbleRadiusDp = 22.0;

/// Top corner radius of the in-app keyboard panel below the island:
/// `INPUT_KEYBOARD_RADIUS` = 29 (CIVC:28, applied CIVC:88). Exposed for the
/// keyboard panel surface; the island itself uses [kChatInputBubbleRadiusDp].
const double kChatInputKeyboardRadiusDp = 29.0;

/// Gap between the island bottom and the bottom inset:
/// `INPUT_BUBBLE_BOTTOM` = 9 (CIVC:30, applied CIVC:185, 234). The bar does
/// not apply it — positioning against the inset is the host's job, exactly as
/// `ChatInputViewsContainer` translates the bubble container (CIVC:185).
const double kChatInputBubbleBottomGapDp = 9.0;

/// Drawable padding of the island glass: `setPadding(dp(7))` (CIVC:81). The
/// Java bounds are first expanded vertically by the same 7dp
/// (`tmpRect.inset(0, -dp(7))`, CIVC:268), so the net visible glass is the
/// island rect inset 7dp horizontally only — reproduced by oversizing the
/// panel vertically and letting the symmetric padding cancel out.
const double kChatInputGlassPaddingDp = 7.0;

/// Liquid lens thickness of the chat-input glass: `setThickness(dp(32))`
/// (CIVC:89). Not a generated `glass_metrics.g.dart` constant — the generated
/// file only carries the drawable defaults (thickness dp(11), intensity
/// 0.75); the 32dp/0.4 pair is the per-surface caller override documented in
/// spec_glass.md section 2.
const double kChatInputGlassThicknessDp = 32.0;

/// Liquid refraction intensity of the chat-input glass:
/// `setIntensity(0.4f)` (CIVC:90). See [kChatInputGlassThicknessDp] for why
/// this is a local constant rather than a generated one.
const double kChatInputGlassIntensity = 0.4;

/// The chat-input liquid parameters — thickness 32dp at intensity 0.4
/// (CIVC:89-90) — the default [ChatInputBar.settings].
const LiquidGlassSettings kChatInputGlassSettings = LiquidGlassSettings(
  thickness: kChatInputGlassThicknessDp,
  refractIntensity: kChatInputGlassIntensity,
);

/// Resting bar height and the side of every button slot:
/// `DEFAULT_HEIGHT` = 44 (CAEV:6410).
const double kChatInputBarHeightDp = 44.0;

/// Message field text size: `setTextSize(COMPLEX_UNIT_DIP, 18)` (CAEV:5752).
const double kChatInputFieldTextSizeDp = 18.0;

/// Field top padding: `setPadding(0, dp(9), 0, dp(10))` (CAEV:5754).
const double kChatInputFieldPaddingTopDp = 9.0;

/// Field bottom padding: `setPadding(0, dp(9), 0, dp(10))` (CAEV:5754).
const double kChatInputFieldPaddingBottomDp = 10.0;

/// Field line cap: `setMaxLines(6)` (CAEV:5751). Beyond it the field scrolls.
const int kChatInputFieldMaxLines = 6;

/// Field frame left margin in bar coordinates: the onMeasure-normalized
/// default `leftMargin = dp(50)` (CAEV:14402; creation value 52dp at
/// CAEV:5763 is immediately re-derived every measure).
const double kChatInputFieldMarginLeftDp = 50.0;

/// Field frame right margin *within the field container*: `rightMargin 50dp`
/// with the attach button only (CAEV:5763, floor logic CAEV:8704-8731). The
/// container itself is inset [kChatInputFieldContainerRightMarginDp] from the
/// bar's right edge, so the field's total right inset is 94dp.
const double kChatInputFieldMarginRightDp = 50.0;

/// Field frame bottom margin: `1.5f` (CAEV:5763).
const double kChatInputFieldBottomMarginDp = 1.5;

/// Right margin of the field container (`messageEditTextContainer`) inside
/// the bar — the 44dp column reserved for the send/mic button:
/// `createFrame(MATCH_PARENT, WRAP_CONTENT, BOTTOM, 0, 0, DEFAULT_HEIGHT, 0)`
/// (CAEV:2660).
const double kChatInputFieldContainerRightMarginDp = 44.0;

/// Emoji slot left margin, normalized every measure: `leftMargin = dp(3)`
/// (CAEV:14399; creation value 2dp at CAEV:2713).
const double kChatInputEmojiLeftMarginDp = 3.0;

/// Bar-height animation duration: `ChatListItemAnimator.DEFAULT_DURATION` =
/// 250ms (ChatListItemAnimator.java:44), wired to the input-field height
/// `FactorAnimator` (CAEV:15456).
const Duration kChatInputHeightDuration = Duration(milliseconds: 250);

/// Bar-height animation curve: `ChatListItemAnimator.DEFAULT_INTERPOLATOR` —
/// cubic-bezier(0.199..., 0.011..., 0.279..., 0.910...)
/// (ChatListItemAnimator.java:45), full-precision constants verbatim.
const Cubic kChatInputHeightCurve = Cubic(
  0.19919472913616398,
  0.010644531250000006,
  0.27920937042459737,
  0.91025390625,
);

/// Controller of a [ChatInputBar]: the draft text, a text-change callback,
/// and the bar's expanded state.
///
/// [textController] is the backing [TextEditingController] — pass an existing
/// one to share the draft with other widgets, or let the controller create
/// (and own) its own. [onTextChanged] fires on every text change (selection
/// changes do not fire it). [expanded] reports whether the island has grown
/// past its resting 44dp height — true from the second wrapped line on
/// (island height `max(dp(44), content)`, CAEV:2623-2628) — and
/// [ChangeNotifier] listeners fire when it flips (and on text changes).
class ChatInputBarController extends ChangeNotifier {
  /// Creates a controller. When [textController] is given, [initialText] must
  /// be null (seed the passed controller instead) and the caller keeps
  /// ownership; otherwise an owned controller is created with [initialText]
  /// and disposed by [dispose].
  ChatInputBarController({
    TextEditingController? textController,
    String? initialText,
    this.onTextChanged,
  })  : assert(
          textController == null || initialText == null,
          'Provide initialText only when the controller owns its '
          'TextEditingController.',
        ),
        _ownsTextController = textController == null,
        textController =
            textController ?? TextEditingController(text: initialText) {
    _lastText = this.textController.text;
    this.textController.addListener(_handleTextControllerChanged);
  }

  /// The backing text controller (the `messageEditText` state).
  final TextEditingController textController;

  /// Fired whenever the draft text changes (not on selection-only changes).
  ValueChanged<String>? onTextChanged;

  final bool _ownsTextController;
  late String _lastText;
  bool _expanded = false;

  /// The current draft text.
  String get text => textController.text;

  /// Replaces the draft text, placing a collapsed selection at its end.
  set text(String value) {
    textController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  /// Whether the attached bar is taller than its resting
  /// [kChatInputBarHeightDp] — i.e. the field wraps to two or more lines.
  /// Always false while no [ChatInputBar] is attached.
  bool get expanded => _expanded;

  void _handleTextControllerChanged() {
    final String current = textController.text;
    if (current == _lastText) {
      return;
    }
    _lastText = current;
    onTextChanged?.call(current);
    notifyListeners();
  }

  /// Called by the bar after measuring the field.
  void _setExpanded(bool value) {
    if (_expanded == value) {
      return;
    }
    _expanded = value;
    notifyListeners();
  }

  @override
  void dispose() {
    textController.removeListener(_handleTextControllerChanged);
    if (_ownsTextController) {
      textController.dispose();
    }
    super.dispose();
  }
}

/// The chat input island: a [GlassPanel] bubble
/// ([GlassPresets.bottomPanelChat], radius 22dp, glass padding 7dp, liquid
/// thickness 32dp at intensity 0.4 — CIVC:27, 81-82, 89-90;
/// ChatActivity.java:3547) hosting the message field and three widget slots
/// in their Java frames:
///
///  * [emojiSlot] — 44x44dp, bottom-left, leftMargin 3dp (CAEV:2713, 14399);
///  * [attachSlot] — 44x44dp at the field container's bottom-right, i.e.
///    44dp in from the bar's right edge (CAEV:2660, 2783-2794);
///  * [sendSlot] — the record/send button, anchored to the bar's
///    bottom-right corner and self-sized (`sendButtonContainer` 100x44dp,
///    CAEV:2897-2931). Built elsewhere and injected, never imported here.
///
/// The field (an [EditableText], 18dp, bottom gravity, padding 9/10dp,
/// maxLines 6, CAEV:5751-5754) sits at left 50dp / right 94dp / bottom 1.5dp
/// in bar coordinates (CAEV:14402, 2660 + 5763). Its color keys:
/// text `chat_messagePanelText`, hint `chat_messagePanelHint`, cursor
/// `chat_messagePanelCursor`, selection `chat_inTextSelectionHighlight`
/// (CAEV:5756-5762). No send logic lives here.
///
/// Bar height = `max(44dp, field height + 1.5dp)` and every change animates
/// over 250ms with the ChatListItemAnimator default interpolator
/// (CAEV:2623-2628, 15456; ChatListItemAnimator.java:44-45), retargeting from
/// the in-flight value like `FactorAnimator.animateTo`. The island's top
/// hairline is the preset's 0.5dp top stroke drawn by the glass surface
/// (BlurredBackgroundProviderImpl `bottomPanelChatActivity`, lines 129-133).
///
/// Taps landing on the island but on no child are swallowed (CIVC:347-364);
/// taps on the field area focus the field. The 9dp bottom gap and the
/// under-keyboard panel are the host's responsibility
/// ([kChatInputBubbleBottomGapDp], [kChatInputKeyboardRadiusDp]).
///
/// Layout is absolute left/right like the Java `Gravity.LEFT/RIGHT` frames —
/// the bar does not mirror under RTL, matching Android. The bar must be given
/// a bounded width.
class ChatInputBar extends StatefulWidget {
  /// Creates the bar shell.
  const ChatInputBar({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText = 'Message',
    this.emojiSlot,
    this.attachSlot,
    this.sendSlot,
    this.settings = kChatInputGlassSettings,
    this.tier,
    this.resources,
  });

  /// Draft/expanded-state controller; an internal one is created when null.
  final ChatInputBarController? controller;

  /// Focus node of the message field; an internal one is created when null.
  final FocusNode? focusNode;

  /// Hint shown while the draft is empty — default `TypeMessage`
  /// ("Message"); channels/threads/edit modes substitute their own strings
  /// (CAEV:6734-6823). Rendered at 18dp in `chat_messagePanelHint`
  /// (CAEV:5759-5760).
  final String hintText;

  /// The emoji-toggle button slot: 44x44dp, bottom-left, 3dp left margin
  /// (CAEV:2713, 14399). Null leaves the frame empty.
  final Widget? emojiSlot;

  /// The attach button slot: 44x44dp at the field container's bottom-right —
  /// 44dp in from the bar's right edge (CAEV:2660, 2783-2794). Null leaves
  /// the frame empty.
  final Widget? attachSlot;

  /// The record/send button slot, anchored bottom-right and self-sized
  /// (`sendButtonContainer`, CAEV:2897-2931). The RecordSendButton widget is
  /// injected here by the host — this shell never imports it.
  final Widget? sendSlot;

  /// Liquid refraction parameters of the island glass; default
  /// [kChatInputGlassSettings] — thickness 32dp, intensity 0.4 (CIVC:89-90).
  final LiquidGlassSettings settings;

  /// Per-panel tier override forwarded to the panel; null uses the enclosing
  /// `GlassBackdropScope` resolution.
  final GlassTier? tier;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)` (the `resourcesProvider` convention).
  final TelegramResources? resources;

  @override
  State<ChatInputBar> createState() => ChatInputBarState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<ChatInputBarController>('controller', controller,
          defaultValue: null))
      ..add(DiagnosticsProperty<FocusNode>('focusNode', focusNode, defaultValue: null))
      ..add(StringProperty('hintText', hintText, defaultValue: 'Message'))
      ..add(DiagnosticsProperty<LiquidGlassSettings>('settings', settings,
          defaultValue: kChatInputGlassSettings))
      ..add(EnumProperty<GlassTier>('tier', tier, defaultValue: null));
  }
}

/// State of [ChatInputBar]; public for test access to [debugBarHeight].
class ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  ChatInputBarController? _internalController;
  FocusNode? _internalFocusNode;

  ChatInputBarController get _effectiveController =>
      widget.controller ?? (_internalController ??= ChatInputBarController());

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode(debugLabel: 'ChatInputBar'));

  /// The height driver — the `animatorInputFieldHeight` FactorAnimator
  /// (CAEV:15456): 250ms, ChatListItemAnimator default interpolator, always
  /// running 0 -> 1 between [_heightFrom] and [_heightTo].
  late final AnimationController _height = AnimationController(
    vsync: this,
    duration: kChatInputHeightDuration,
    value: 1.0,
  );
  late final CurvedAnimation _heightCurved =
      CurvedAnimation(parent: _height, curve: kChatInputHeightCurve);

  double _heightFrom = kChatInputBarHeightDp;
  double _heightTo = kChatInputBarHeightDp;
  bool _measuredOnce = false;

  double _lastFieldHeight = 0.0;
  bool _retargetScheduled = false;

  /// The current animated bar height:
  /// `lerp(from, to, interpolator(t))` — the live island height.
  @visibleForTesting
  double get debugBarHeight =>
      lerpDouble(_heightFrom, _heightTo, _heightCurved.value)!;

  @override
  void didUpdateWidget(ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller && _measuredOnce) {
      // Sync the newly attached controller's expanded state from the last
      // measured field height.
      _handleFieldHeight(_lastFieldHeight);
    }
  }

  @override
  void dispose() {
    _heightCurved.dispose();
    _height.dispose();
    _internalController?.dispose();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  /// Field height report from layout. Defers the retarget out of the layout
  /// phase; the post-frame callback reads the latest reported value.
  void _handleFieldHeight(double fieldHeight) {
    _lastFieldHeight = fieldHeight;
    if (_retargetScheduled) {
      return;
    }
    _retargetScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retargetScheduled = false;
      if (!mounted) {
        return;
      }
      // Island height = max(dp(44), content) where content is the field plus
      // its 1.5dp bottom margin (CAEV:2623-2628, 5763).
      final double target = math.max(
        kChatInputBarHeightDp,
        _lastFieldHeight + kChatInputFieldBottomMarginDp,
      );
      _effectiveController._setExpanded(target > kChatInputBarHeightDp);
      _retarget(target);
    });
  }

  /// `animatorInputFieldHeight.animateTo(height)` after the first measure,
  /// `forceFactor(height)` on it (CAEV:2623-2628): the first report snaps,
  /// later changes animate from the in-flight value over the full 250ms.
  void _retarget(double target) {
    final bool first = !_measuredOnce;
    _measuredOnce = true;
    if (target == _heightTo) {
      return;
    }
    if (first) {
      setState(() {
        _heightFrom = _heightTo = target;
        _height.value = 1.0;
      });
      return;
    }
    _heightFrom = debugBarHeight;
    _heightTo = target;
    _height.forward(from: 0.0);
  }

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    return resources != null
        ? resources.getColor(key)
        : TelegramTheme.colorOf(context, key);
  }

  /// The message field cell: hint behind an [EditableText], both under the
  /// 9/10dp vertical padding (CAEV:5754), bottom-aligned like the Java
  /// `Gravity.BOTTOM` field.
  Widget _buildField(BuildContext context) {
    final Color textColor = _color(context, TelegramColorKey.chat_messagePanelText);
    final Color hintColor = _color(context, TelegramColorKey.chat_messagePanelHint);
    final Color cursorColor = _color(context, TelegramColorKey.chat_messagePanelCursor);
    final Color selectionColor =
        _color(context, TelegramColorKey.chat_inTextSelectionHighlight);
    const EdgeInsets fieldPadding = EdgeInsets.only(
      top: kChatInputFieldPaddingTopDp,
      bottom: kChatInputFieldPaddingBottomDp,
    );
    final TextEditingController textController = _effectiveController.textController;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _effectiveFocusNode.requestFocus(),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: textController,
        builder: (BuildContext context, TextEditingValue value, Widget? child) {
          return Stack(
            alignment: AlignmentDirectional.bottomStart,
            children: <Widget>[
              // The hint stays mounted and fades by opacity so the sibling
              // EditableText element is never re-slotted (which would drop
              // its input connection) when the draft flips empty/non-empty.
              Padding(
                padding: fieldPadding,
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: value.text.isEmpty ? 1.0 : 0.0,
                      child: Text(
                        widget.hintText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: kChatInputFieldTextSizeDp,
                          color: hintColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: fieldPadding,
                child: EditableText(
                  controller: textController,
                  focusNode: _effectiveFocusNode,
                  style: TextStyle(
                    fontSize: kChatInputFieldTextSizeDp,
                    color: textColor,
                  ),
                  cursorColor: cursorColor,
                  // Android has no floating-cursor analog; reuse the hint
                  // grey for the iOS backing cursor.
                  backgroundCursorColor: hintColor,
                  selectionColor: selectionColor,
                  minLines: 1,
                  maxLines: kChatInputFieldMaxLines,
                  keyboardType: TextInputType.multiline,
                  // TYPE_TEXT_FLAG_CAP_SENTENCES (CAEV:5748).
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Taps on the island that hit no child are swallowed (CIVC:347-364).
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: AnimatedBuilder(
        animation: _height,
        builder: (BuildContext context, Widget? child) =>
            SizedBox(height: debugBarHeight, child: child),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // Island glass: bounds expanded 7dp vertically then padded 7dp on
            // all sides — visible glass inset 7dp horizontally only, exactly
            // the Java `inset(0, -dp(7))` + `setPadding(dp(7))`
            // (CIVC:81, 268).
            Positioned(
              left: 0,
              right: 0,
              top: -kChatInputGlassPaddingDp,
              bottom: -kChatInputGlassPaddingDp,
              child: GlassPanel(
                preset: GlassPresets.bottomPanelChat,
                borderRadius: const GlassRadii.all(kChatInputBubbleRadiusDp),
                padding: kChatInputGlassPaddingDp,
                settings: widget.settings,
                tier: widget.tier,
                resources: widget.resources,
              ),
            ),
            // Message field frame: left 50dp, right 44 + 50 = 94dp, bottom
            // 1.5dp (CAEV:14402, 2660, 5763). The positioned child's height
            // is unconstrained, so the field always lays out at its natural
            // height — the measurement driving the island animation.
            Positioned(
              left: kChatInputFieldMarginLeftDp,
              right: kChatInputFieldContainerRightMarginDp +
                  kChatInputFieldMarginRightDp,
              bottom: kChatInputFieldBottomMarginDp,
              child: _FieldSizeObserver(
                onHeightChanged: _handleFieldHeight,
                child: _buildField(context),
              ),
            ),
            // Emoji slot: 44x44dp bottom-left, leftMargin 3dp
            // (CAEV:2713, 14399).
            Positioned(
              left: kChatInputEmojiLeftMarginDp,
              bottom: 0,
              child: SizedBox.square(
                dimension: kChatInputBarHeightDp,
                child: widget.emojiSlot,
              ),
            ),
            // Attach slot: 44x44dp at the field container's bottom-right
            // (CAEV:2660, 2783-2794).
            Positioned(
              right: kChatInputFieldContainerRightMarginDp,
              bottom: 0,
              child: SizedBox.square(
                dimension: kChatInputBarHeightDp,
                child: widget.attachSlot,
              ),
            ),
            // Record/send slot: bottom-right corner, self-sized
            // (sendButtonContainer, CAEV:2897-2931).
            if (widget.sendSlot != null)
              Positioned(right: 0, bottom: 0, child: widget.sendSlot!),
          ],
        ),
      ),
    );
  }
}

/// Reports the laid-out height of its child — the `messageEditTextContainer`
/// onMeasure hook feeding `animatorInputFieldHeight` (CAEV:2623-2628). The
/// callback fires during layout only when the height changed; the receiver
/// defers any retargeting out of the layout phase.
class _FieldSizeObserver extends SingleChildRenderObjectWidget {
  const _FieldSizeObserver({required this.onHeightChanged, super.child});

  final ValueChanged<double> onHeightChanged;

  @override
  _RenderFieldSizeObserver createRenderObject(BuildContext context) =>
      _RenderFieldSizeObserver(onHeightChanged);

  @override
  void updateRenderObject(
      BuildContext context, _RenderFieldSizeObserver renderObject) {
    renderObject.onHeightChanged = onHeightChanged;
  }
}

class _RenderFieldSizeObserver extends RenderProxyBox {
  _RenderFieldSizeObserver(this.onHeightChanged);

  ValueChanged<double> onHeightChanged;
  double? _lastHeight;

  @override
  void performLayout() {
    super.performLayout();
    if (size.height != _lastHeight) {
      _lastHeight = size.height;
      onHeightChanged(size.height);
    }
  }
}
