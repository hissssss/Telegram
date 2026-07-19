// The Telegram alert dialog (PLAN_UIKIT.md M3).
//
// Port of `ui/ActionBar/AlertDialog.java` — the message / items / buttons
// variants (`ALERT_TYPE_MESSAGE`, AlertDialog.java:91) — with every constant
// cited:
//
// - surface: `popup_fixed_alert4` tinted `key_dialogBackground` MULTIPLY
//   (AlertDialog.java:312-315), clipped at **20dp** corner radius
//   (`boundsWithPaddingRoundRect(dp(8), dp(20))`, AlertDialog.java:663-664);
//   width = `min(maxWidth, screenWidth - 48dp)` with maxWidth **356dp** on
//   phones (AlertDialog.java:1250-1262; 446/496dp tablet variants stay
//   parameter overrides);
// - barrier: black at `dimAlpha = 0.5` (AlertDialog.java:210, applied via
//   FLAG_DIM_BEHIND at :1241-1243), overridable (`setDimAlpha` /
//   `setDimEnabled`, AlertDialog.java:1944-1952);
// - show/dismiss: the stock `Theme.Dialog` window animation — a ~150ms pure
//   fade ([TgMotion.dialogFadeDuration]); the content does not scale
//   (res/values/styles.xml:139-153 sets no windowAnimationStyle override);
// - title 20dp Roboto Medium `key_dialogTextBlack`, container margin 24dp
//   horizontal, top 19dp, bottom 10dp (14dp with an items list)
//   (AlertDialog.java:784-794);
// - message 16dp `key_dialogTextBlack` at 24dp gutters
//   (AlertDialog.java:849-850, 893), block top 19dp when there is no title,
//   bottom 20dp (AlertDialog.java:453-455); with items below, the message
//   keeps a 12dp gap (`customViewOffset`, AlertDialog.java:116, 893) and the
//   block margin is 8dp (AlertDialog.java:450-452);
// - items (`AlertDialogCell`, AlertDialog.java:238-294): rows forced 48dp
//   (onMeasure, :266-269), padding 23dp horizontal (:249), text 16dp
//   `key_dialogTextBlack` single-line (:256-262), optional leading icon in a
//   40dp-tall start frame tinted `key_dialogIcon` (:251-254) indenting the
//   text 56dp (:284); pressed selector `key_dialogButtonSelector` (:248);
//   tap fires the callback and dismisses (:915-920);
// - button row: MATCH_PARENT x 52dp (AlertDialog.java:1055), padding 8dp
//   (:1053), buttons 40dp ([TgDialogButton]); positive pinned to the
//   trailing edge, negative immediately before it with an 8dp gap, neutral
//   pinned to the leading edge, RTL-mirrored (:961-1013); per-button max
//   width `(availableWidth - 24dp) / 2` (:390-398);
// - vertical fallback: labels pre-measured with a 16dp bold paint plus
//   12+12dp padding and 8dp gaps (:932-951) — if the combined width exceeds
//   `screenWidth - 64dp` the row becomes a vertical stack (:952-959), order
//   negative / neutral / positive (:1124-1125, 1165-1166), each
//   MATCH_PARENT x 40dp with a 6dp top margin between buttons (:1222-1226);
// - button clicks call the listener then dismiss, unless
//   `dismissDialogByButtons` is false (:1088-1096, 1129-1137); clicks are
//   ignored while the button is loading (:1089).
//
// Deliberately NOT ported: the 9-patch drop shadow ring (the surface is a
// plain rounded rect, the TgBottomSheet precedent); the scroll edge shadows
// (`header_shadow` bitmaps fading 150ms, AlertDialog.java:816-845,
// 1422-1432 — bitmap assets); the blurred-background mode
// (AlertDialog.java:306-316, spec `NICE`); second title / subtitle / top
// image rows (AlertDialog.java:706-813); the custom-view slot
// (AlertDialog.java:923-929); BUTTON_NEGATIVE_2 (AlertDialog.java:1181-1220);
// link handling inside the message (`LinkMovementMethodMy` +
// `key_dialogTextLink`, AlertDialog.java:851-852 — span machinery is
// app-side); `dismissUnless`/`showDelayed` timing helpers
// (AlertDialog.java:1505-1512, 1696-1699).
//
// TODO(integration): the progress variants — ALERT_TYPE_LOADING (4dp
// LineProgressView + 14dp bold percent label, AlertDialog.java:858-873) and
// ALERT_TYPE_SPINNER (86dp r18 card + 32dp RadialProgressView with the
// 190ms Overshoot(1.3) pop-in, AlertDialog.java:874-888, 327-335) — depend
// on M9/M10 (agent B5) and land in a follow-up commit of this file per
// PLAN_UIKIT.md §3 cross-agent notes (spec_dialog_menu.md §1.6).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../buttons/tg_dialog_button.dart';
import '../foundation/tg_motion.dart';
import '../foundation/tg_text_styles.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Surface corner radius: 20dp (`boundsWithPaddingRoundRect(dp(8), dp(20))`,
/// AlertDialog.java:663-664).
const double kTgAlertDialogCornerRadius = 20.0;

/// Maximum surface width on phones: 356dp (AlertDialog.java:499,
/// 1252-1260; small/big tablets use 446/496dp — pass `maxWidth`).
const double kTgAlertDialogMaxWidth = 356.0;

/// Total horizontal screen inset: the window width is
/// `min(maxWidth, screenWidth - 48dp)` (AlertDialog.java:1250-1262; the
/// rotation re-layout path uses 56dp, AlertDialog.java:490).
const double kTgAlertDialogScreenInset = 48.0;

/// Default barrier color: black at `dimAlpha = 0.5` (AlertDialog.java:210,
/// 1241-1243) — see [TgMotion.dialogDim].
const Color kTgAlertDialogBarrierColor = Color(0x80000000);

/// Title/message horizontal gutters: 24dp (AlertDialog.java:784, 893).
const double kTgAlertDialogHorizontalMargin = 24.0;

/// Title top margin: 19dp (AlertDialog.java:794).
const double kTgAlertDialogTitleTopMargin = 19.0;

/// Title bottom margin: 10dp (AlertDialog.java:794).
const double kTgAlertDialogTitleBottomMargin = 10.0;

/// Title bottom margin with an items list: 14dp (AlertDialog.java:794).
const double kTgAlertDialogTitleBottomMarginItems = 14.0;

/// Message block top margin when there is no title: 19dp
/// (AlertDialog.java:454).
const double kTgAlertDialogMessageTopMargin = 19.0;

/// Message block bottom margin: 20dp (AlertDialog.java:455).
const double kTgAlertDialogMessageBottomMargin = 20.0;

/// Items block top/bottom margin: 8dp (AlertDialog.java:451-452).
const double kTgAlertDialogItemsBlockMargin = 8.0;

/// Message-to-items gap: 12dp (`customViewOffset` default,
/// AlertDialog.java:116, 893).
const double kTgAlertDialogMessageItemsGap = 12.0;

/// Button row height: 52dp (`createLinear(MATCH_PARENT, 52)`,
/// AlertDialog.java:1055).
const double kTgAlertDialogButtonRowHeight = 52.0;

/// Button row padding: 8dp all sides (AlertDialog.java:1053). With the 40dp
/// buttons this exceeds the fixed 52dp row — Java lays the buttons from the
/// padded top edge and overlaps the bottom pad; the port does the same.
const double kTgAlertDialogButtonRowPadding = 8.0;

/// Gap between horizontal buttons: 8dp (AlertDialog.java:937-950, 982-988).
const double kTgAlertDialogButtonGap = 8.0;

/// Top margin between stacked vertical buttons: 6dp
/// (AlertDialog.java:1222-1226).
const double kTgAlertDialogVerticalButtonGap = 6.0;

/// Vertical-stack threshold inset: the row stacks when the measured
/// combined button width exceeds `screenWidth - 64dp`
/// (AlertDialog.java:952).
const double kTgAlertDialogVerticalOverflowInset = 64.0;

/// Per-button max width inset: each button is capped at
/// `(availableWidth - 24dp) / 2` (AlertDialog.java:390-398).
const double kTgAlertDialogButtonMaxWidthInset = 24.0;

/// Items row height: 48dp, forced in onMeasure (AlertDialog.java:266-269).
const double kTgAlertDialogItemHeight = 48.0;

/// Items row horizontal padding: 23dp (AlertDialog.java:249).
const double kTgAlertDialogItemPadding = 23.0;

/// Items row text size: 16dp (AlertDialog.java:262).
const double kTgAlertDialogItemTextSize = 16.0;

/// Text indent (inside the 23dp padding) when a row has an icon: 56dp
/// (AlertDialog.java:284).
const double kTgAlertDialogItemIconIndent = 56.0;

/// Icon frame height: 40dp, vertically centered (AlertDialog.java:254).
const double kTgAlertDialogItemIconFrameHeight = 40.0;

/// One dialog action button — text, listener and per-button state, the
/// `setPositiveButton`/`setNegativeButton`/`setNeutralButton` payload
/// (AlertDialog.java:1801-1819) plus the per-button toggles.
class TgAlertDialogAction {
  /// Creates a button descriptor.
  const TgAlertDialogAction({
    required this.text,
    this.onPressed,
    this.destructive = false,
    this.enabled = true,
    this.loading = false,
  });

  /// Button label, rendered as given — no all-caps (AlertDialog.java:1080).
  final String text;

  /// The click listener, invoked before the dialog dismisses
  /// (AlertDialog.java:1088-1096).
  final VoidCallback? onPressed;

  /// Colors the button `text_RedBold` (`redPositive()` /
  /// `Builder.makeRed`, AlertDialog.java:231-236, 1910-1929).
  final bool destructive;

  /// Disabled buttons render at 0.5 alpha and ignore taps
  /// (AlertDialog.java:1062-1066).
  final bool enabled;

  /// Shows the in-button spinner (`makeButtonLoading`,
  /// AlertDialog.java:1313-1335); taps are ignored while loading
  /// (AlertDialog.java:1089).
  final bool loading;
}

/// One row of the items-list variant (`Builder.setItems`,
/// AlertDialog.java:905-922) — mirroring the `TgBottomSheetItem` shape.
class TgDialogItem<T> {
  /// Creates an item row. [value] is what [showTgAlertDialog] resolves with
  /// when the row is tapped.
  const TgDialogItem({required this.text, this.icon, this.value, this.onTap});

  /// Row label, 16dp `dialogTextBlack` (AlertDialog.java:261-262).
  final String text;

  /// Optional leading icon widget, centered in the 40dp-tall start frame
  /// and tinted `dialogIcon` through [IconTheme]
  /// (AlertDialog.java:251-254).
  final Widget? icon;

  /// The result popped when this row is tapped (the Java
  /// `onClickListener.onClick(dialog, which)` index generalized to a
  /// value).
  final T? value;

  /// Per-row callback, fired before the dialog dismisses
  /// (AlertDialog.java:915-920).
  final VoidCallback? onTap;
}

/// Shows a [TgAlertDialog] and returns the tapped item's
/// [TgDialogItem.value] (null when dismissed by a button, the barrier or
/// back).
///
/// The `AlertDialog.show()` port: a [PopupRoute] fading a centered dialog
/// surface in over [TgMotion.dialogFadeDuration] behind a black barrier at
/// [TgMotion.dialogDim] (AlertDialog.java:210, 322-337).
Future<T?> showTgAlertDialog<T>(
  BuildContext context, {
  String? title,
  String? message,
  List<TgDialogItem<T>> items = const <TgDialogItem<Never>>[],
  TgAlertDialogAction? positiveButton,
  TgAlertDialogAction? negativeButton,
  TgAlertDialogAction? neutralButton,
  bool dismissByButtons = true,
  bool barrierDismissible = true,
  bool dimEnabled = true,
  double dimAlpha = TgMotion.dialogDim,
  double maxWidth = kTgAlertDialogMaxWidth,
  Duration fadeDuration = TgMotion.dialogFadeDuration,
  TelegramResources? resources,
  bool useRootNavigator = false,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push(
    TgAlertDialogRoute<T>(
      title: title,
      message: message,
      items: items,
      positiveButton: positiveButton,
      negativeButton: negativeButton,
      neutralButton: neutralButton,
      dismissByButtons: dismissByButtons,
      barrierDismissible: barrierDismissible,
      dimEnabled: dimEnabled,
      dimAlpha: dimAlpha,
      maxWidth: maxWidth,
      fadeDuration: fadeDuration,
      resources: resources,
    ),
  );
}

/// The modal route behind [showTgAlertDialog] — `AlertDialog.show()` /
/// `dismiss()` (AlertDialog.java:322-337, 1519-1549).
///
/// Barrier: black at [dimAlpha] (`dimAmount`, AlertDialog.java:1241-1243),
/// tap-outside dismisses by default. Transition: a pure [fadeDuration] fade
/// on the content, no scale — the stock `Theme.Dialog` window-animation
/// parity (res/values/styles.xml:139-153).
class TgAlertDialogRoute<T> extends PopupRoute<T> {
  /// Creates the route; see [showTgAlertDialog] for the convenience wrapper.
  TgAlertDialogRoute({
    this.title,
    this.message,
    this.items = const <TgDialogItem<Never>>[],
    this.positiveButton,
    this.negativeButton,
    this.neutralButton,
    this.dismissByButtons = true,
    this.barrierDismissible = true,
    this.dimEnabled = true,
    this.dimAlpha = TgMotion.dialogDim,
    this.maxWidth = kTgAlertDialogMaxWidth,
    this.fadeDuration = TgMotion.dialogFadeDuration,
    this.resources,
    super.settings,
  });

  /// Dialog title (AlertDialog.java:782-795).
  final String? title;

  /// Dialog message (AlertDialog.java:847-857).
  final String? message;

  /// Items-list rows (AlertDialog.java:905-922).
  final List<TgDialogItem<T>> items;

  /// The positive (confirm) button — pinned to the trailing edge
  /// (AlertDialog.java:971-977).
  final TgAlertDialogAction? positiveButton;

  /// The negative (cancel) button — before the positive with an 8dp gap
  /// (AlertDialog.java:978-991).
  final TgAlertDialogAction? negativeButton;

  /// The neutral button — pinned to the leading edge
  /// (AlertDialog.java:992-998).
  final TgAlertDialogAction? neutralButton;

  /// Whether button taps dismiss the dialog (`dismissDialogByButtons`,
  /// AlertDialog.java:1093-1095, 1954-1957).
  final bool dismissByButtons;

  /// Tap outside dismisses (`setCanceledOnTouchOutside` — the message
  /// dialog default).
  @override
  final bool barrierDismissible;

  /// Whether the barrier dims (`setDimEnabled`, AlertDialog.java:1944-1947).
  final bool dimEnabled;

  /// Barrier dim opacity 0..1 (`dimAlpha = 0.5f`, AlertDialog.java:210;
  /// `setDimAlpha`, AlertDialog.java:1949-1952).
  final double dimAlpha;

  /// Surface max width, default [kTgAlertDialogMaxWidth]
  /// (AlertDialog.java:1252-1260).
  final double maxWidth;

  /// Fade in/out duration, default [TgMotion.dialogFadeDuration].
  final Duration fadeDuration;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)` (the Java `resourcesProvider`,
  /// AlertDialog.java:300-302).
  final TelegramResources? resources;

  @override
  Color? get barrierColor {
    if (!dimEnabled) {
      return null;
    }
    final int alpha = (dimAlpha * 255).round().clamp(0, 255);
    return Color.fromARGB(alpha, 0, 0, 0);
  }

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => fadeDuration;

  @override
  Duration get reverseTransitionDuration => fadeDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // Pure fade, no scale — window-animation parity
    // (res/values/styles.xml:139-153, spec_typography_motion.md §2.3).
    return FadeTransition(
      opacity: animation,
      child: Center(
        child: TgAlertDialog<T>(
          title: title,
          message: message,
          items: items,
          positiveButton: positiveButton,
          negativeButton: negativeButton,
          neutralButton: neutralButton,
          dismissByButtons: dismissByButtons,
          maxWidth: maxWidth,
          resources: resources,
          onDismiss: () => Navigator.pop<T>(context),
          onItemSelected: (TgDialogItem<T> item) =>
              Navigator.pop<T>(context, item.value),
        ),
      ),
    );
  }
}

/// The dialog surface — title, message, items list and button row on a
/// 20dp-rounded `dialogBackground` card, `min(maxWidth, screenWidth - 48dp)`
/// wide (the `AlertDialogView` content port, AlertDialog.java:642-1227).
///
/// Usually built by [TgAlertDialogRoute]; standalone hosts wire [onDismiss]
/// / [onItemSelected] themselves.
///
/// Like every component in this package, the dialog takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise keys resolve through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class TgAlertDialog<T> extends StatelessWidget {
  /// Creates the dialog surface.
  const TgAlertDialog({
    super.key,
    this.title,
    this.message,
    this.items = const <TgDialogItem<Never>>[],
    this.positiveButton,
    this.negativeButton,
    this.neutralButton,
    this.dismissByButtons = true,
    this.maxWidth = kTgAlertDialogMaxWidth,
    this.onDismiss,
    this.onItemSelected,
    this.resources,
  });

  /// Key on the clipped dialog surface, for tests and tooling.
  static const Key panelKey = ValueKey<String>('TgAlertDialog.panel');

  /// Title: 20dp Roboto Medium `dialogTextBlack`
  /// (AlertDialog.java:790-792) — the [TgTextStyles.title] role.
  final String? title;

  /// Message: 16dp `dialogTextBlack` (AlertDialog.java:849-850) — the
  /// [TgTextStyles.body] role.
  final String? message;

  /// Items-list rows, one 48dp [TgAlertDialogCell] each
  /// (AlertDialog.java:905-922).
  final List<TgDialogItem<T>> items;

  /// The positive (confirm) button.
  final TgAlertDialogAction? positiveButton;

  /// The negative (cancel) button.
  final TgAlertDialogAction? negativeButton;

  /// The neutral button.
  final TgAlertDialogAction? neutralButton;

  /// Whether button taps call [onDismiss] (`dismissDialogByButtons`,
  /// AlertDialog.java:1093-1095).
  final bool dismissByButtons;

  /// Surface max width (AlertDialog.java:1252-1260).
  final double maxWidth;

  /// Dismiss hook: called after a button's [TgAlertDialogAction.onPressed]
  /// when [dismissByButtons], and after an item tap when [onItemSelected]
  /// is null. The route passes `Navigator.pop`.
  final VoidCallback? onDismiss;

  /// Item-tap hook, called after [TgDialogItem.onTap]; when null, item taps
  /// fall back to [onDismiss] (Java always dismisses on item tap,
  /// AlertDialog.java:915-920).
  final ValueChanged<TgDialogItem<T>>? onItemSelected;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = this.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  /// The Java pre-measure (AlertDialog.java:932-953): 16dp bold labels plus
  /// 12+12dp padding each and 8dp gaps; vertical when the total exceeds
  /// `screenWidth - 64dp`.
  bool _needsVerticalButtons(
    BuildContext context,
    List<TgAlertDialogAction> actions,
  ) {
    if (actions.isEmpty) {
      return false;
    }
    final TextDirection direction = Directionality.of(context);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    double combined = 0.0;
    for (final TgAlertDialogAction action in actions) {
      if (combined > 0) {
        combined += kTgAlertDialogButtonGap;
      }
      final TextPainter painter = TextPainter(
        text: TextSpan(text: action.text, style: TgTextStyles.bodyEmphasis),
        textDirection: direction,
        maxLines: 1,
        textScaler: scaler,
      )..layout();
      combined += painter.width + 2 * kTgDialogButtonHorizontalPadding;
      painter.dispose();
    }
    return combined >
        MediaQuery.sizeOf(context).width - kTgAlertDialogVerticalOverflowInset;
  }

  Widget _button(TgAlertDialogAction action) {
    return TgDialogButton(
      text: action.text,
      destructive: action.destructive,
      enabled: action.enabled,
      loading: action.loading,
      resources: resources,
      onPressed: () {
        // Listener first, then dismiss (AlertDialog.java:1088-1096).
        action.onPressed?.call();
        if (dismissByButtons) {
          onDismiss?.call();
        }
      },
    );
  }

  Widget _buildButtons(BuildContext context, double dialogWidth) {
    final TgAlertDialogAction? positive = positiveButton;
    final TgAlertDialogAction? negative = negativeButton;
    final TgAlertDialogAction? neutral = neutralButton;
    final List<TgAlertDialogAction> present = <TgAlertDialogAction>[
      ?positive,
      ?negative,
      ?neutral,
    ];

    if (_needsVerticalButtons(context, present)) {
      // Vertical order: negative, neutral, positive (insertion at 0/1,
      // AlertDialog.java:1124-1125, 1165-1166); MATCH_PARENT x 40 with 6dp
      // top margins (AlertDialog.java:1222-1226).
      final List<TgAlertDialogAction> ordered = <TgAlertDialogAction>[
        ?negative,
        ?neutral,
        ?positive,
      ];
      return Padding(
        padding: const EdgeInsets.all(kTgAlertDialogButtonRowPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < ordered.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  top: i == 0 ? 0.0 : kTgAlertDialogVerticalButtonGap,
                ),
                child: SizedBox(
                  height: kTgDialogButtonHeight,
                  child: _button(ordered[i]),
                ),
              ),
          ],
        ),
      );
    }

    // Horizontal: 52dp row, 8dp padding, buttons laid from the padded top
    // edge (AlertDialog.java:1053-1055); positive trailing-pinned, negative
    // before it with 8dp, neutral leading-pinned (AlertDialog.java:961-1013).
    return SizedBox(
      height: kTgAlertDialogButtonRowHeight,
      child: Padding(
        padding: const EdgeInsets.only(
          left: kTgAlertDialogButtonRowPadding,
          right: kTgAlertDialogButtonRowPadding,
          top: kTgAlertDialogButtonRowPadding,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: kTgDialogButtonHeight,
            width: double.infinity,
            child: CustomMultiChildLayout(
              delegate: _TgDialogButtonsLayout(
                // `(availableWidth - 24dp) / 2` (AlertDialog.java:396).
                maxButtonWidth:
                    (dialogWidth - kTgAlertDialogButtonMaxWidthInset) / 2.0,
                textDirection: Directionality.of(context),
                hasPositive: positive != null,
                hasNegative: negative != null,
                hasNeutral: neutral != null,
              ),
              children: <Widget>[
                if (positive != null)
                  LayoutId(
                    id: _TgDialogButtonsLayout.positiveId,
                    child: _button(positive),
                  ),
                if (negative != null)
                  LayoutId(
                    id: _TgDialogButtonsLayout.negativeId,
                    child: _button(negative),
                  ),
                if (neutral != null)
                  LayoutId(
                    id: _TgDialogButtonsLayout.neutralId,
                    child: _button(neutral),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? title = this.title;
    final String? message = this.message;
    final bool hasItems = items.isNotEmpty;
    final bool hasButtons = positiveButton != null ||
        negativeButton != null ||
        neutralButton != null;
    // Window width = min(maxWidth, screenWidth - 48dp)
    // (AlertDialog.java:1250-1262).
    final double width = math.min(
      maxWidth,
      MediaQuery.sizeOf(context).width - kTgAlertDialogScreenInset,
    );

    // Scroll-block margins (AlertDialog.java:444-456).
    final double scrollTop = hasItems
        ? (title == null && message == null ? kTgAlertDialogItemsBlockMargin : 0.0)
        : (title == null ? kTgAlertDialogMessageTopMargin : 0.0);
    final double scrollBottom = hasItems
        ? kTgAlertDialogItemsBlockMargin
        : kTgAlertDialogMessageBottomMargin;

    final List<Widget> column = <Widget>[
      if (title != null)
        Padding(
          // Container margin 24dp horizontal (AlertDialog.java:784), title
          // top 19dp / bottom 10dp (14dp with items) (AlertDialog.java:794).
          padding: EdgeInsetsDirectional.only(
            start: kTgAlertDialogHorizontalMargin,
            end: kTgAlertDialogHorizontalMargin,
            top: kTgAlertDialogTitleTopMargin,
            bottom: hasItems
                ? kTgAlertDialogTitleBottomMarginItems
                : kTgAlertDialogTitleBottomMargin,
          ),
          child: Text(
            title,
            textHeightBehavior: kTgTextHeightBehavior,
            // 20dp Roboto Medium (AlertDialog.java:791-792).
            style: TgTextStyles.title.copyWith(
              color: _color(context, TelegramColorKey.dialogTextBlack),
            ),
          ),
        ),
      if (message != null || hasItems)
        Flexible(
          child: Padding(
            padding: EdgeInsets.only(top: scrollTop, bottom: scrollBottom),
            // The message/items live in a ScrollView
            // (AlertDialog.java:823-845); the edge shadows are not ported.
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (message != null)
                    Padding(
                      // 24dp gutters; 12dp gap before items
                      // (AlertDialog.java:893).
                      padding: EdgeInsetsDirectional.only(
                        start: kTgAlertDialogHorizontalMargin,
                        end: kTgAlertDialogHorizontalMargin,
                        bottom: hasItems ? kTgAlertDialogMessageItemsGap : 0.0,
                      ),
                      child: Text(
                        message,
                        textHeightBehavior: kTgTextHeightBehavior,
                        // 16dp regular (AlertDialog.java:849-850).
                        style: TgTextStyles.body.copyWith(
                          color:
                              _color(context, TelegramColorKey.dialogTextBlack),
                        ),
                      ),
                    ),
                  for (final TgDialogItem<T> item in items)
                    TgAlertDialogCell(
                      text: item.text,
                      icon: item.icon,
                      resources: resources,
                      onTap: () {
                        // Callback, then dismiss (AlertDialog.java:915-920).
                        item.onTap?.call();
                        final ValueChanged<TgDialogItem<T>>? onItemSelected =
                            this.onItemSelected;
                        if (onItemSelected != null) {
                          onItemSelected(item);
                        } else {
                          onDismiss?.call();
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      if (hasButtons) _buildButtons(context, width),
    ];

    return SizedBox(
      width: width,
      child: ClipRRect(
        key: panelKey,
        borderRadius: BorderRadius.circular(kTgAlertDialogCornerRadius),
        child: ColoredBox(
          // `popup_fixed_alert4` tinted `dialogBackground` MULTIPLY
          // (AlertDialog.java:312-315), minus the 9-patch shadow.
          color: _color(context, TelegramColorKey.dialogBackground),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: column,
          ),
        ),
      ),
    );
  }
}

/// One 48dp items-list row — the `AlertDialogCell` port
/// (AlertDialog.java:238-294).
///
/// Geometry: 23dp horizontal padding (AlertDialog.java:249); optional
/// leading icon centered in a 40dp-tall start frame tinted `dialogIcon`
/// (AlertDialog.java:251-254); 16dp single-line `dialogTextBlack` text
/// (AlertDialog.java:256-262), indented 56dp when the icon is present
/// (AlertDialog.java:284). Pressing fills the row with
/// `dialogButtonSelector` (AlertDialog.java:248 — the ripple expansion is
/// not ported).
class TgAlertDialogCell extends StatefulWidget {
  /// Creates an items-list row.
  const TgAlertDialogCell({
    super.key,
    required this.text,
    this.icon,
    this.onTap,
    this.resources,
  });

  /// Row label (AlertDialog.java:279-280).
  final String text;

  /// Optional leading icon widget (AlertDialog.java:251-254, 281-284).
  final Widget? icon;

  /// Tap handler (AlertDialog.java:915-920).
  final VoidCallback? onTap;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  @override
  State<TgAlertDialogCell> createState() => _TgAlertDialogCellState();
}

class _TgAlertDialogCellState extends State<TgAlertDialogCell> {
  bool _pressed = false;

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  void _setPressed(bool pressed) {
    if (_pressed != pressed) {
      setState(() => _pressed = pressed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget? icon = widget.icon;
    final bool interactive = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: interactive,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: interactive ? (TapDownDetails d) => _setPressed(true) : null,
        onTapUp: interactive ? (TapUpDetails d) => _setPressed(false) : null,
        onTapCancel: interactive ? () => _setPressed(false) : null,
        onTap: widget.onTap,
        child: ColoredBox(
          // `createSelectorDrawable(dialogButtonSelector, 2)`
          // (AlertDialog.java:248) as a plain pressed fill.
          color: _pressed
              ? _color(context, TelegramColorKey.dialogButtonSelector)
              : const Color(0x00000000),
          child: SizedBox(
            height: kTgAlertDialogItemHeight,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: kTgAlertDialogItemPadding,
                end: kTgAlertDialogItemPadding,
              ),
              child: Stack(
                children: <Widget>[
                  if (icon != null)
                    PositionedDirectional(
                      start: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        widthFactor: 1.0,
                        child: SizedBox(
                          height: kTgAlertDialogItemIconFrameHeight,
                          child: IconTheme.merge(
                            data: IconThemeData(
                              color:
                                  _color(context, TelegramColorKey.dialogIcon),
                              size: 24,
                            ),
                            child: Center(child: icon),
                          ),
                        ),
                      ),
                    ),
                  PositionedDirectional(
                    start: icon != null ? kTgAlertDialogItemIconIndent : 0.0,
                    end: 0,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        widget.text,
                        maxLines: 1,
                        // TruncateAt.END (AlertDialog.java:260).
                        overflow: TextOverflow.ellipsis,
                        textHeightBehavior: kTgTextHeightBehavior,
                        style: TextStyle(
                          fontSize: kTgAlertDialogItemTextSize,
                          color:
                              _color(context, TelegramColorKey.dialogTextBlack),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The horizontal button placement (AlertDialog.java:961-1013): positive
/// pinned to the trailing edge, negative immediately before it with an 8dp
/// gap, neutral pinned to the leading edge; each button capped at
/// [maxButtonWidth].
///
/// Divergence: Java resolves an over-full row with a single-pass shrink of
/// the wider of negative/neutral (AlertDialog.java:1028-1045); the port
/// clamps sequentially (positive, then negative, then neutral) — the
/// results differ only when all three buttons together exceed the row.
class _TgDialogButtonsLayout extends MultiChildLayoutDelegate {
  _TgDialogButtonsLayout({
    required this.maxButtonWidth,
    required this.textDirection,
    required this.hasPositive,
    required this.hasNegative,
    required this.hasNeutral,
  });

  static const String positiveId = 'positive';
  static const String negativeId = 'negative';
  static const String neutralId = 'neutral';

  final double maxButtonWidth;
  final TextDirection textDirection;
  final bool hasPositive;
  final bool hasNegative;
  final bool hasNeutral;

  void _place(String id, Size size, double start, double rowWidth) {
    // `start` is the leading offset; mirror under RTL
    // (AlertDialog.java:973-997).
    final double x = textDirection == TextDirection.ltr
        ? rowWidth - start - size.width
        : start;
    positionChild(id, Offset(x, 0));
  }

  @override
  void performLayout(Size size) {
    final double rowWidth = size.width;
    BoxConstraints buttonConstraints(double available) => BoxConstraints(
          maxWidth: math.max(0.0, math.min(maxButtonWidth, available)),
          minHeight: size.height,
          maxHeight: size.height,
        );

    double used = 0.0;
    if (hasPositive) {
      final Size positive =
          layoutChild(positiveId, buttonConstraints(rowWidth));
      _place(positiveId, positive, 0.0, rowWidth);
      used = positive.width;
    }
    if (hasNegative) {
      final double gap = used > 0 ? kTgAlertDialogButtonGap : 0.0;
      final Size negative = layoutChild(
        negativeId,
        buttonConstraints(rowWidth - used - gap),
      );
      _place(negativeId, negative, used + gap, rowWidth);
      used += gap + negative.width;
    }
    if (hasNeutral) {
      final double gap = used > 0 ? kTgAlertDialogButtonGap : 0.0;
      final Size neutral = layoutChild(
        neutralId,
        buttonConstraints(rowWidth - used - gap),
      );
      // Leading-pinned (AlertDialog.java:992-998).
      final double x = textDirection == TextDirection.ltr
          ? 0.0
          : rowWidth - neutral.width;
      positionChild(neutralId, Offset(x, 0));
    }
  }

  @override
  bool shouldRelayout(_TgDialogButtonsLayout oldDelegate) {
    return oldDelegate.maxButtonWidth != maxButtonWidth ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.hasPositive != hasPositive ||
        oldDelegate.hasNegative != hasNegative ||
        oldDelegate.hasNeutral != hasNeutral;
  }
}
