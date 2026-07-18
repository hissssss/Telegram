// The between-sections spacer (ARCHITECTURE.md section 6, row
// "ShadowSectionCell").
//
// Port of `ui/Cells/ShadowSectionCell.java`:
//
// - fixed height, default 12dp, measured EXACTLY
//   (ShadowSectionCell.java:32-36, 107-109);
// - the classic `greydivider`/`greydivider_top`/`greydivider_bottom`
//   9-patch shadows tinted `key_windowBackgroundGrayShadow` are **commented
//   out upstream** (ShadowSectionCell.java:74-92; resource ids
//   ShadowSectionCell.java:94-104): the current cell's own background is
//   null — a plain spacer showing the `windowBackgroundGray` list backdrop
//   behind it — or a caller-supplied flat color
//   (ShadowSectionCell.java:50-59, 81-83).
//
// The port therefore fills with `windowBackgroundGray` itself (the backdrop
// the transparent Java cell exposes), and offers the shadows as an opt-in
// pair of 1-physical-px hairlines tinted with the 9-patches' tint key,
// default **off** to match the shipped upstream look.
library;

import 'package:flutter/widgets.dart';

import '../../theme/telegram_resources.dart';
import '../../theme/telegram_theme.dart';
import '../../tokens/theme_keys.g.dart';

/// Default spacer height: 12dp (`this(context, 12, ...)`,
/// ShadowSectionCell.java:32, 36; measured EXACTLY,
/// ShadowSectionCell.java:107-109).
const double kShadowSectionCellHeight = 12.0;

/// A 12dp section spacer — the `ui/Cells/ShadowSectionCell.java` port.
///
/// Fills with the `windowBackgroundGray` key by default — what shows through
/// the Java cell's null background (ShadowSectionCell.java:74-77) in a
/// standard settings list. Pass [backgroundColor] for the flat-color
/// constructor variant (ShadowSectionCell.java:50-59), or a null
/// [backgroundKey] for the literal transparent spacer.
///
/// [hairlines] (default off, matching upstream where the 9-patch shadows are
/// commented out, ShadowSectionCell.java:74-92) draws 1-physical-px top and
/// bottom lines in `windowBackgroundGrayShadow` — the tint key of the
/// disabled `greydivider*` assets (ShadowSectionCell.java:79, 85).
///
/// Like every component in this package, the cell takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise keys resolve through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class ShadowSectionCell extends StatelessWidget {
  /// Creates a section spacer.
  const ShadowSectionCell({
    super.key,
    this.height = kShadowSectionCellHeight,
    this.backgroundKey = TelegramColorKey.windowBackgroundGray,
    this.backgroundColor,
    this.hairlines = false,
    this.hairlineColorKey = TelegramColorKey.windowBackgroundGrayShadow,
    this.resources,
  });

  /// Spacer height (`size`, ShadowSectionCell.java:23, 107-109).
  final double height;

  /// Fill color key; null renders a transparent spacer (the Java cell's own
  /// background, ShadowSectionCell.java:74-77). Ignored when
  /// [backgroundColor] is set.
  final int? backgroundKey;

  /// Explicit flat fill — the `int backgroundColor` constructor variant
  /// (ShadowSectionCell.java:50-59, 81-83). Wins over [backgroundKey].
  final Color? backgroundColor;

  /// Whether the opt-in top/bottom hairlines draw. Off by default: upstream
  /// ships the plain spacer (the 9-patch shadows are commented out,
  /// ShadowSectionCell.java:74-92).
  final bool hairlines;

  /// Hairline tint key: `windowBackgroundGrayShadow`, the tint of the
  /// disabled `greydivider*` assets (ShadowSectionCell.java:79, 85).
  final int hairlineColorKey;

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
    final Color? fill = backgroundColor ??
        (backgroundKey != null ? _color(context, backgroundKey!) : null);
    Widget? child;
    if (fill != null) {
      child = ColoredBox(color: fill, child: const SizedBox.expand());
    }
    if (hairlines) {
      final double devicePixelRatio =
          MediaQuery.maybeDevicePixelRatioOf(context) ??
              View.of(context).devicePixelRatio;
      child = CustomPaint(
        foregroundPainter: ShadowSectionHairlinePainter(
          color: _color(context, hairlineColorKey),
          thickness: 1.0 / devicePixelRatio,
        ),
        child: child,
      );
    }
    return SizedBox(width: double.infinity, height: height, child: child);
  }
}

/// Paints the opt-in 1-physical-px top and bottom hairlines of a
/// [ShadowSectionCell] — the flat stand-in for the commented-out
/// `greydivider` 9-patch edges (ShadowSectionCell.java:74-92).
class ShadowSectionHairlinePainter extends CustomPainter {
  /// Creates the hairline painter.
  const ShadowSectionHairlinePainter({
    required this.color,
    required this.thickness,
  });

  /// Hairline color (`windowBackgroundGrayShadow`,
  /// ShadowSectionCell.java:79).
  final Color color;

  /// Line thickness — one physical pixel in logical px.
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, thickness), paint);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - thickness, size.width, thickness),
      paint,
    );
  }

  @override
  bool shouldRepaint(ShadowSectionHairlinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.thickness != thickness;
}
