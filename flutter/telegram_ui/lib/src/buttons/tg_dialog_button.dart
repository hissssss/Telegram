// The flat dialog text button (PLAN_UIKIT.md M2).
//
// Port of the `AlertDialog` button convention —
// `ui/ActionBar/AlertDialog.java:1050-1096` (identical for the
// negative/neutral buttons at :1099-1179) on `ui/ActionBar/
// TextViewWithLoading.java` — with every constant cited:
//
// - height 40dp (`createFrame(WRAP_CONTENT, 40, ...)`,
//   AlertDialog.java:1084-1086), minWidth 64dp (`setMinWidth(dp(64))`,
//   AlertDialog.java:1074), horizontal padding 12dp (`setPadding(dp(12), 0,
//   dp(12), 0)`, AlertDialog.java:1082);
// - label 16dp `AndroidUtilities.bold()` (Roboto Medium, w500), gravity
//   center, color `key_dialogButton` (AlertDialog.java:1076-1079) — **no
//   all-caps transform**, the label renders as given;
// - destructive buttons re-color to `key_text_RedBold` (`redPositive()`,
//   AlertDialog.java:231-236);
// - background `Theme.getRoundRectSelectorDrawable(dp(20), color)`
//   (AlertDialog.java:1081): transparent at rest, a 20dp-radius pill pressed
//   fill in the label color at alpha 0x19 (`(color & 0x00ffffff) |
//   0x19000000`, Theme.java:5515-5522);
// - disabled: alpha 0.5 on the whole view + taps ignored (`setEnabled`
//   override, AlertDialog.java:1062-1066);
// - loading (TextViewWithLoading.java:46-73): `AnimatedFloat` 320ms
//   EASE_OUT_QUINT (TextViewWithLoading.java:16) crossfades label and
//   spinner — the label slides down `6dp * loading` while fading out, the
//   `CircularProgressDrawable` spinner (tg_circular_progress.dart) slides in
//   from `-6dp * (1 - loading)` horizontally while fading in, tinted the
//   label color (TextViewWithLoading.java:26-29). Clicks are ignored while
//   loading (AlertDialog.java:1089).
//
// Deliberately NOT ported: the radial ripple expansion of the Android
// `RippleDrawable` (the port shows a plain pressed fill at the identical
// color — the package uses no Material ink machinery); the rare
// BUTTON_NEGATIVE_2 variant (36dp tall, r=6dp selector,
// AlertDialog.java:1181-1220).
library;

import 'package:flutter/widgets.dart';

import '../foundation/tg_curves.dart';
import '../foundation/tg_text_styles.dart';
import '../progress/tg_circular_progress.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Button height: 40dp (`createFrame(WRAP_CONTENT, 40, ...)`,
/// AlertDialog.java:1084-1086).
const double kTgDialogButtonHeight = 40.0;

/// Minimum button width: 64dp (`setMinWidth(dp(64))`,
/// AlertDialog.java:1074).
const double kTgDialogButtonMinWidth = 64.0;

/// Horizontal label padding: 12dp (`setPadding(dp(12), 0, dp(12), 0)`,
/// AlertDialog.java:1082).
const double kTgDialogButtonHorizontalPadding = 12.0;

/// Label text size: 16dp (`setTextSize(COMPLEX_UNIT_DIP, 16)`,
/// AlertDialog.java:1076) — the [TgTextStyles.bodyEmphasis] role.
const double kTgDialogButtonTextSize = 16.0;

/// Pressed-pill corner radius: 20dp
/// (`Theme.getRoundRectSelectorDrawable(dp(20), color)`,
/// AlertDialog.java:1081).
const double kTgDialogButtonRippleRadius = 20.0;

/// Pressed-fill alpha over the label color: 0x19 = 25/255 ≈ 9.8%
/// (`(color & 0x00ffffff) | 0x19000000`, Theme.java:5519).
const int kTgDialogButtonRippleAlpha = 0x19;

/// Disabled alpha: 0.5 (`setAlpha(enabled ? 1.0f : 0.5f)`,
/// AlertDialog.java:1065).
const double kTgDialogButtonDisabledAlpha = 0.5;

/// Loading crossfade duration: 320ms (`new AnimatedFloat(this, 320,
/// EASE_OUT_QUINT)`, TextViewWithLoading.java:16).
const Duration kTgDialogButtonLoadingDuration = Duration(milliseconds: 320);

/// Loading crossfade curve: EASE_OUT_QUINT (TextViewWithLoading.java:16).
const Cubic kTgDialogButtonLoadingCurve = TgCurves.easeOutQuint;

/// Loading slide distance: 6dp — the label translates down `dp(6) * loading`
/// (TextViewWithLoading.java:56) and the spinner center slides in from
/// `-dp(6) * (1 - loading)` (TextViewWithLoading.java:63).
const double kTgDialogButtonLoadingSlide = 6.0;

/// The flat Telegram dialog text button — the `AlertDialog` button
/// convention (AlertDialog.java:1050-1096) on `TextViewWithLoading`.
///
/// A 40dp-tall, minimum-64dp-wide transparent button: 16dp Roboto Medium
/// label in `dialogButton` (or `text_RedBold` when [destructive]), 12dp
/// horizontal padding, no all-caps transform. Pressing fills a 20dp-radius
/// pill with the label color at ~10% alpha (Theme.java:5515-5522); disabled
/// buttons render at 0.5 alpha and ignore taps; [loading] swaps the label
/// for the in-button spinner over 320ms EASE_OUT_QUINT
/// (TextViewWithLoading.java:46-73) and ignores taps while set
/// (AlertDialog.java:1089).
///
/// Like every component in this package, the button takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise keys resolve through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class TgDialogButton extends StatefulWidget {
  /// Creates a dialog text button.
  const TgDialogButton({
    super.key,
    required this.text,
    this.onPressed,
    this.destructive = false,
    this.enabled = true,
    this.loading = false,
    this.height = kTgDialogButtonHeight,
    this.minWidth = kTgDialogButtonMinWidth,
    this.colorKey,
    this.resources,
  });

  /// Key on the label's fade wrapper, for tests probing the loading swap.
  static const Key labelKey = ValueKey<String>('TgDialogButton.label');

  /// Key on the spinner's fade wrapper (present only while the loading
  /// factor is > 0), for tests probing the loading swap.
  static const Key spinnerKey = ValueKey<String>('TgDialogButton.spinner');

  /// The label, rendered exactly as given — no all-caps transform
  /// (AlertDialog.java:1080; single line, end-ellipsized like
  /// AlertDialog.java:1119-1120).
  final String text;

  /// Tap callback. Null renders the button inert (still at full alpha —
  /// Java's disabled *state* is [enabled]).
  final VoidCallback? onPressed;

  /// Re-colors the label (and pressed pill) to `text_RedBold` — the
  /// `redPositive()` destructive convention (AlertDialog.java:231-236).
  final bool destructive;

  /// Disabled buttons draw at [kTgDialogButtonDisabledAlpha] and ignore
  /// taps (AlertDialog.java:1062-1066).
  final bool enabled;

  /// Swaps the label for the spinner (TextViewWithLoading.java:31-40);
  /// changes animate over [kTgDialogButtonLoadingDuration]. Taps are
  /// ignored while loading (AlertDialog.java:1089).
  final bool loading;

  /// Button height, default [kTgDialogButtonHeight]
  /// (AlertDialog.java:1084-1086).
  final double height;

  /// Minimum width, default [kTgDialogButtonMinWidth]
  /// (AlertDialog.java:1074).
  final double minWidth;

  /// Label color key override. Defaults to `dialogButton`
  /// (AlertDialog.java:1077), or `text_RedBold` when [destructive].
  final int? colorKey;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  @override
  State<TgDialogButton> createState() => TgDialogButtonState();
}

/// State of a [TgDialogButton]; public so tests can read
/// [debugLoadingFactor] and [debugPressed].
class TgDialogButtonState extends State<TgDialogButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loading;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    // The initial state applies without animation, like AnimatedFloat's
    // first set (TextViewWithLoading.java:16, 48).
    _loading = AnimationController(
      vsync: this,
      duration: kTgDialogButtonLoadingDuration,
      value: widget.loading ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(TgDialogButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading != oldWidget.loading) {
      // `animatedLoading.set(loading)`: 320ms EASE_OUT_QUINT from the
      // current value (TextViewWithLoading.java:16, 48).
      _loading.animateTo(
        widget.loading ? 1.0 : 0.0,
        curve: kTgDialogButtonLoadingCurve,
      );
    }
  }

  @override
  void dispose() {
    _loading.dispose();
    super.dispose();
  }

  /// The animated loading crossfade factor (the Java `loading` float of
  /// `TextViewWithLoading.onDraw`, TextViewWithLoading.java:48).
  double get debugLoadingFactor => _loading.value;

  /// Whether the pressed fill is showing.
  bool get debugPressed => _pressed;

  bool get _interactive =>
      widget.enabled && !widget.loading && widget.onPressed != null;

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

  void _handleTap() {
    // `if (textView.isLoading()) return;` (AlertDialog.java:1089); disabled
    // buttons never receive the tap ([_interactive] gates the detector).
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final int colorKey = widget.colorKey ??
        (widget.destructive
            ? TelegramColorKey.text_RedBold
            : TelegramColorKey.dialogButton);
    final Color color = _color(context, colorKey);

    final Widget label = Text(
      widget.text,
      maxLines: 1,
      // `setEllipsize(TextUtils.TruncateAt.END)` + `setSingleLine(true)`
      // (AlertDialog.java:1119-1120).
      overflow: TextOverflow.ellipsis,
      textHeightBehavior: kTgTextHeightBehavior,
      // 16dp Roboto Medium (AlertDialog.java:1076-1079) — the
      // TgTextStyles.bodyEmphasis role; color merged at the use site.
      style: TgTextStyles.bodyEmphasis.copyWith(color: color),
    );

    final Widget content = AnimatedBuilder(
      animation: _loading,
      builder: (BuildContext context, Widget? child) {
        final double t = _loading.value;
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Label: alpha 1-t, sliding down 6dp*t
            // (TextViewWithLoading.java:50-59).
            Opacity(
              key: TgDialogButton.labelKey,
              opacity: (1.0 - t).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, kTgDialogButtonLoadingSlide * t),
                child: child,
              ),
            ),
            // Spinner: alpha t, center sliding in from -6dp*(1-t), tinted
            // the label color (TextViewWithLoading.java:61-71, 26-29).
            if (t > 0)
              Opacity(
                key: TgDialogButton.spinnerKey,
                opacity: t.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(-kTgDialogButtonLoadingSlide * (1.0 - t), 0),
                  child: TgCircularProgress(color: color),
                ),
              ),
          ],
        );
      },
      child: label,
    );

    final Widget button = Opacity(
      // `setAlpha(enabled ? 1.0f : 0.5f)` (AlertDialog.java:1065).
      opacity: widget.enabled ? 1.0 : kTgDialogButtonDisabledAlpha,
      child: Container(
        height: widget.height,
        constraints: BoxConstraints(minWidth: widget.minWidth),
        padding: const EdgeInsets.symmetric(
          horizontal: kTgDialogButtonHorizontalPadding,
        ),
        // Transparent at rest; pressed = the ripple color of
        // `getRoundRectSelectorDrawable(dp(20), color)` as a plain fill
        // (Theme.java:5515-5522) — the radial expansion is not ported.
        decoration: _pressed
            ? BoxDecoration(
                color: color.withAlpha(kTgDialogButtonRippleAlpha),
                borderRadius:
                    BorderRadius.circular(kTgDialogButtonRippleRadius),
              )
            : null,
        // Gravity.CENTER (AlertDialog.java:1078); width wraps the label
        // above the 64dp minimum, like a WRAP_CONTENT TextView with
        // minWidth.
        child: Center(widthFactor: 1.0, child: content),
      ),
    );

    return Semantics(
      container: true,
      button: true,
      enabled: _interactive,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _interactive ? (TapDownDetails d) => _setPressed(true) : null,
        onTapUp: _interactive ? (TapUpDetails d) => _setPressed(false) : null,
        onTapCancel: _interactive ? () => _setPressed(false) : null,
        onTap: _interactive ? _handleTap : null,
        child: button,
      ),
    );
  }
}
