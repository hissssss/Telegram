// The animated radio button and its settings row (PLAN_UIKIT.md M6).
//
// Port of `ui/Components/RadioButton.java` (the drawing engine) and
// `ui/Cells/RadioCell.java` (the 50dp settings row), per spec_forms.md §2.
//
// The signature animation is a single 0..1 progress, 200ms with the default
// `ObjectAnimator` accelerate-decelerate interpolator
// (RadioButton.java:122-126), whose `circleProgress` is a triangle wave
// (RadioButton.java:161-166): the first half fills the interior inward from
// the ring (annulus erase, RadioButton.java:182-183 — realized here as an
// even-odd path) while the ring radius breathes inward
// (`size/2 - dp(1 + circleProgress)`, RadioButton.java:178); the second half
// collapses the interior to the resting dot (`size/4 + (rad - 1dp - size/4)
// * circleProgress`, RadioButton.java:185) while the color lerps per channel
// unchecked -> checked (RadioButton.java:166-175).
//
// Divergence (documented per §2 conventions): Java takes raw colors
// (`setColor(color1, color2)`, RadioButton.java:100-104); the port resolves
// the two theme keys RadioCell passes (`key_radioBackground` /
// `key_radioBackgroundChecked`, RadioCell.java:72-75) so per-key theme
// rebuilds work. Java's per-channel `(int)` lerp truncation becomes
// `Color.lerp` (sub-unit difference; TgSwitch precedent).
//
// Deliberately NOT ported: icon mode (`setIcon`, RadioButton.java:88-94,
// 189-201), the static shared paints (RadioButton.java:33-35 — irrelevant in
// Flutter), RadioCell's `hideRadioButton` (RadioCell.java:122-124) and the
// animator-list variant of setEnabled (RadioCell.java:111-116 — the port
// applies the 0.5 alpha directly).
library;

import 'package:flutter/widgets.dart';

import '../components/app_bar/glass_app_bar.dart'
    show TgAccelerateDecelerateCurve;
import '../components/cells/text_cell.dart' show TextCellDividerPainter;
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Bare-widget drawn size: 16dp (`size = dp(16)`, RadioButton.java:45).
const double kTgRadioSize = 16.0;

/// RadioCell drawn size: 20dp (`setSize(dp(20))`, RadioCell.java:70).
const double kTgRadioCellRadioSize = 20.0;

/// RadioCell radio frame: 22x22dp (RadioCell.java:76, 88).
const double kTgRadioCellRadioBox = 22.0;

/// Ring stroke: 2dp STROKE (RadioButton.java:50-52).
const double kTgRadioStroke = 2.0;

/// Toggle animation duration: 200ms (RadioButton.java:124).
const Duration kTgRadioDuration = Duration(milliseconds: 200);

/// Toggle animation curve: the Java `ObjectAnimator` runs its default
/// `AccelerateDecelerateInterpolator` (none is set, RadioButton.java:122-126).
const Curve kTgRadioCurve = TgAccelerateDecelerateCurve();

/// Row height: 50dp (+1px divider) (RadioCell.java:85).
const double kTgRadioCellHeight = 50.0;

/// Row text size: 16dp (RadioCell.java:61).
const double kTgRadioCellTextSize = 16.0;

/// Row side padding: 21dp (constructor default, RadioCell.java:40, 67).
const double kTgRadioCellPadding = 21.0;

/// Radio frame top margin: 14dp (RadioCell.java:76).
const double kTgRadioCellRadioTopMargin = 14.0;

/// Divider leading inset: 20dp (RadioCell.java:128).
const double kTgRadioCellDividerInset = 20.0;

/// Disabled row alpha: 0.5 on text + radio (RadioCell.java:114-119).
const double kTgRadioCellDisabledAlpha = 0.5;

/// A round Telegram radio button — the `RadioButton.java` port.
///
/// Controlled widget: [checked] in, [onSelected] out (a tap always selects —
/// radios never toggle off). External [checked] changes animate the 200ms
/// triangle-wave progress.
class TgRadio extends StatefulWidget {
  /// Creates a radio button.
  const TgRadio({
    super.key,
    required this.checked,
    this.onSelected,
    this.size = kTgRadioSize,
    this.colorKey = TelegramColorKey.radioBackground,
    this.checkedColorKey = TelegramColorKey.radioBackgroundChecked,
    this.resources,
  });

  /// Current state; external changes animate (`setChecked(checked, true)`,
  /// RadioButton.java:140-152).
  final bool checked;

  /// Called on tap when not already selected. Null makes the radio inert
  /// (Java cells own the click handling; this is a standalone convenience).
  final VoidCallback? onSelected;

  /// Drawn circle size in dp — Java `setSize` takes px, bare default 16dp
  /// (RadioButton.java:45, 81-86).
  final double size;

  /// Unchecked color key (`key_radioBackground`, 0xffb3b3b3 — Java passes
  /// the raw resolved int, RadioCell.java:74; the port resolves the key).
  final int colorKey;

  /// Checked color key (`key_radioBackgroundChecked`, 0xff229AF0,
  /// RadioCell.java:74).
  final int checkedColorKey;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)`.
  final TelegramResources? resources;

  @override
  State<TgRadio> createState() => TgRadioState();
}

/// State of a [TgRadio]; public so tests can read [debugProgress].
class TgRadioState extends State<TgRadio> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Initial state applies without animation (RadioButton.java:146-151).
    _controller = AnimationController(
      vsync: this,
      duration: kTgRadioDuration,
      value: widget.checked ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(TgRadio oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.checked != oldWidget.checked) {
      // `animateToCheckedState` — 200ms, default interpolator
      // (RadioButton.java:122-126).
      _controller.animateTo(widget.checked ? 1.0 : 0.0, curve: kTgRadioCurve);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Current animated progress (the Java `progress` field,
  /// RadioButton.java:40).
  double get debugProgress => _controller.value;

  Color _color(BuildContext context, int key) {
    final TelegramResources? resources = widget.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  @override
  Widget build(BuildContext context) {
    final Color color = _color(context, widget.colorKey);
    final Color checkedColor = _color(context, widget.checkedColorKey);
    final VoidCallback? onSelected = widget.onSelected;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: widget.checked,
      enabled: onSelected != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onSelected == null
            ? null
            : () {
                if (!widget.checked) {
                  onSelected();
                }
              },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            return CustomPaint(
              size: Size.square(widget.size),
              painter: TgRadioPainter(
                progress: _controller.value,
                size: widget.size,
                color: color,
                checkedColor: checkedColor,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints the `RadioButton.onDraw` geometry (RadioButton.java:159-202),
/// centered in the canvas.
class TgRadioPainter extends CustomPainter {
  /// Creates the painter.
  const TgRadioPainter({
    required this.progress,
    required this.size,
    required this.color,
    required this.checkedColor,
  });

  /// Animated 0..1 progress (RadioButton.java:40).
  final double progress;

  /// Drawn circle size in dp (RadioButton.java:45).
  final double size;

  /// Resolved unchecked color (RadioButton.java:101).
  final Color color;

  /// Resolved checked color (RadioButton.java:102).
  final Color checkedColor;

  /// The triangle wave: `progress <= .5 ? progress / .5 : 2 - progress / .5`
  /// (RadioButton.java:161-166).
  static double circleProgressFor(double progress) =>
      progress <= 0.5 ? progress / 0.5 : 2.0 - progress / 0.5;

  /// Breathing ring radius: `size/2 - dp(1 + circleProgress)`
  /// (RadioButton.java:178).
  static double ringRadiusFor(double progress, double size) =>
      size / 2.0 - (1.0 + circleProgressFor(progress));

  /// Second-half dot radius: `size/4 + (rad - 1dp - size/4) * circleProgress`
  /// (RadioButton.java:185); at rest (progress 1) exactly `size/4`.
  static double dotRadiusFor(double progress, double size) {
    final double cp = circleProgressFor(progress);
    final double rad = ringRadiusFor(progress, size);
    return size / 4.0 + (rad - 1.0 - size / 4.0) * cp;
  }

  /// Paint color: unchecked hue through the whole first half; per-channel
  /// lerp toward [checkedColor] by `1 - circleProgress` in the second
  /// (RadioButton.java:161-176).
  static Color colorFor(double progress, Color color, Color checkedColor) {
    if (progress <= 0.5) {
      return color;
    }
    return Color.lerp(color, checkedColor, 1.0 - circleProgressFor(progress))!;
  }

  @override
  void paint(Canvas canvas, Size bounds) {
    final Offset center = bounds.center(Offset.zero);
    final double cp = circleProgressFor(progress);
    final Color paintColor = colorFor(progress, color, checkedColor);
    final double rad = ringRadiusFor(progress, size);

    // 2dp stroke ring (RadioButton.java:50-52, 179).
    canvas.drawCircle(
      center,
      rad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = kTgRadioStroke
        ..color = paintColor,
    );

    final Paint fill = Paint()..color = paintColor;
    if (progress <= 0.5) {
      // Interior fills from the ring inward: disc rad - 1dp minus an erase
      // circle (rad - 1dp)(1 - circleProgress) (RadioButton.java:182-183) —
      // the even-odd annulus equivalent.
      final double outer = rad - 1.0;
      if (cp >= 1.0) {
        canvas.drawCircle(center, outer, fill);
      } else if (cp > 0.0) {
        final Path annulus = Path()
          ..fillType = PathFillType.evenOdd
          ..addOval(Rect.fromCircle(center: center, radius: outer))
          ..addOval(
            Rect.fromCircle(center: center, radius: outer * (1.0 - cp)),
          );
        canvas.drawPath(annulus, fill);
      }
    } else {
      // Interior collapses to the resting dot (RadioButton.java:185).
      canvas.drawCircle(center, dotRadiusFor(progress, size), fill);
    }
  }

  @override
  bool shouldRepaint(TgRadioPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.size != size ||
      oldDelegate.color != color ||
      oldDelegate.checkedColor != checkedColor;
}

/// The 50dp settings radio row — the `ui/Cells/RadioCell.java` port: 16dp
/// text with 21dp side padding, a 22x22dp trailing radio frame (drawn size
/// 20dp) at 14dp from the top, an optional 1-physical-px divider inset 20dp
/// (leading), and 0.5 alpha on text + radio when disabled.
class TgRadioCell extends StatelessWidget {
  /// Creates a settings radio row (`RadioCell(context, false, 21)`,
  /// RadioCell.java:40).
  const TgRadioCell({
    super.key,
    required this.text,
    required this.checked,
    this.onSelected,
    this.enabled = true,
    this.divider = false,
    this.padding = kTgRadioCellPadding,
    this.textColorKey = TelegramColorKey.windowBackgroundWhiteBlackText,
    this.radioColorKey = TelegramColorKey.radioBackground,
    this.radioCheckedColorKey = TelegramColorKey.radioBackgroundChecked,
    this.resources,
  });

  /// The dialog variant (`RadioCell(context, true, padding)`,
  /// RadioCell.java:56-57, 71-72): `dialogTextBlack` text and
  /// `dialogRadioBackground[Checked]` radio keys.
  const TgRadioCell.dialog({
    super.key,
    required this.text,
    required this.checked,
    this.onSelected,
    this.enabled = true,
    this.divider = false,
    this.padding = kTgRadioCellPadding,
    this.textColorKey = TelegramColorKey.dialogTextBlack,
    this.radioColorKey = TelegramColorKey.dialogRadioBackground,
    this.radioCheckedColorKey = TelegramColorKey.dialogRadioBackgroundChecked,
    this.resources,
  });

  /// Row label, single line, 16dp, end-ellipsized (RadioCell.java:61-65).
  final String text;

  /// Whether this row's radio is selected.
  final bool checked;

  /// Called when the row (or radio) is tapped while not selected. The Java
  /// cell leaves click handling to callers (`setOnClickListener` at the list
  /// site); the port wires the whole row.
  final VoidCallback? onSelected;

  /// Disabled rows draw text + radio at [kTgRadioCellDisabledAlpha] and
  /// ignore taps (RadioCell.java:111-120).
  final bool enabled;

  /// Draws the trailing 1-physical-px divider (RadioCell.java:126-130).
  final bool divider;

  /// Side padding (constructor parameter, default 21, RadioCell.java:40).
  final double padding;

  /// Text color key (`windowBackgroundWhiteBlackText`, RadioCell.java:59).
  final int textColorKey;

  /// Radio unchecked color key (RadioCell.java:74).
  final int radioColorKey;

  /// Radio checked color key (RadioCell.java:74).
  final int radioCheckedColorKey;

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

  @override
  Widget build(BuildContext context) {
    // Hairlines are 1 physical px, per `Theme.dividerPaint`
    // (Theme.java:3089) — the dialog_cell.dart precedent.
    final double dividerThickness =
        divider ? 1.0 / MediaQuery.devicePixelRatioOf(context) : 0.0;
    final TextDirection textDirection = Directionality.of(context);
    final VoidCallback? onSelected = this.onSelected;
    final bool interactive = enabled && onSelected != null;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: checked,
      enabled: interactive,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interactive && !checked ? onSelected : null,
        child: CustomPaint(
          foregroundPainter: divider
              ? TextCellDividerPainter(
                  color: _color(context, TelegramColorKey.divider),
                  inset: kTgRadioCellDividerInset,
                  thickness: dividerThickness,
                  textDirection: textDirection,
                )
              : null,
          child: SizedBox(
            width: double.infinity,
            // 50dp + 1px divider (RadioCell.java:85).
            height: kTgRadioCellHeight + dividerThickness,
            child: Opacity(
              opacity: enabled ? 1.0 : kTgRadioCellDisabledAlpha,
              child: Stack(
                children: <Widget>[
                  // Text: side margins = padding, CENTER_VERTICAL gravity
                  // (RadioCell.java:66-67).
                  PositionedDirectional(
                    start: padding,
                    end: padding,
                    top: 0,
                    bottom: dividerThickness,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: kTgRadioCellTextSize,
                          color: _color(context, textColorKey),
                        ),
                      ),
                    ),
                  ),
                  // Radio: 22x22 frame, trailing inset padding + 1, top 14
                  // (RadioCell.java:76); drawn size 20 (RadioCell.java:70).
                  PositionedDirectional(
                    end: padding + 1.0,
                    top: kTgRadioCellRadioTopMargin,
                    child: SizedBox.square(
                      dimension: kTgRadioCellRadioBox,
                      child: Center(
                        child: ExcludeSemantics(
                          // The row provides the radio semantics
                          // (RadioCell.java:132-138).
                          child: TgRadio(
                            checked: checked,
                            size: kTgRadioCellRadioSize,
                            colorKey: radioColorKey,
                            checkedColorKey: radioCheckedColorKey,
                            resources: resources,
                          ),
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
