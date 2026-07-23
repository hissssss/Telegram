// Port of `ui/Components/FlickerLoadingView.java` — the skeleton-placeholder
// list with a moving highlight gradient (PLAN_UIKIT.md S2).
//
// Faithful recipe:
// - rows are flat shapes (avatar circle + r4 rounded text bars) drawn with a
//   single gradient-shader paint (FlickerLoadingView.java:64, 934);
// - the gradient is a 4-stop linear ramp `[color1, color0, color0, color1]`
//   at stops `[0, 0.4, 0.6, 1]` (FlickerLoadingView.java:930-932): `color0`
//   (the highlight center) resolves `actionBarDefaultSubmenuBackground`,
//   `color1` (the edges) `listSelector` (FlickerLoadingView.java:82-83,
//   917-918);
// - list mode sweeps the gradient **vertically** with a 600dp ramp
//   (FlickerLoadingView.java:927, 932); single-cell mode sweeps horizontally
//   with a 200dp ramp (FlickerLoadingView.java:925, 930; mode selection at
//   :893, 924, 929);
// - sweep speed: the translation advances `dt · extent / 400` per frame —
//   one full extent (view height, or width in single-cell mode) every 400ms —
//   wrapping from `extent · 2` back to `−gradientWidth · 2`
//   (FlickerLoadingView.java:894-904); per-frame dt is clamped to 16ms above
//   17ms and floored to 0 below 4ms (FlickerLoadingView.java:874-880);
// - row geometry mirrors the ported cells: `DIALOG_CELL_TYPE` (the
//   DialogCell skeleton, FlickerLoadingView.java:183-215, height dp(72)+1 at
//   :954-955) and `USERS_TYPE` (the UserCell skeleton,
//   FlickerLoadingView.java:431-456, height 64dp at :970-972);
// - RTL mirrors every shape around the width axis (`checkRtl`,
//   FlickerLoadingView.java:938-950);
// - single-cell mode measures `cellHeight · itemsCount` tall
//   (FlickerLoadingView.java:140-147, `getAdditionalHeight() == 0` at
//   :153-155) and stops after `itemsCount` rows (FlickerLoadingView.java:
//   212-214).
//
// Deliberately NOT ported:
// - the other 30+ view types (PHOTOS/FILES/AUDIO/… STAR_GIFT,
//   FlickerLoadingView.java:26-60) — the plan scopes S2 to the dialog-cell
//   and user-cell shapes; the geometry table is trivially extensible;
// - `SharedConfig.useThreeLinesLayout` third bar (FlickerLoadingView.java:
//   198-202) — the package's DialogCell port is the two-line layout;
// - `globalGradientView` cross-view gradient sharing and `setParentSize`
//   (FlickerLoadingView.java:94, 160-166, 1048-1056);
// - `useHeaderOffset`, `skipDrawItemsCount`, `setPaddingTop`/`setPaddingLeft`
//   and the `BOTS_MENU_TYPE` random widths (FlickerLoadingView.java:74-105,
//   1018-1042);
// - `LoadingDrawable.java` (the path-shaped text shimmer with its own
//   550/320ms appear/disappear gradients) — a different primitive keyed to
//   text layouts, out of the S2 skeleton-row scope (it is also the
//   `setFlickeringLoading` shimmer already noted as unported in
//   `tg_button.dart`).
library;

import 'dart:ui' as ui show Gradient, TileMode;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';

import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Dialog-cell skeleton row height: dp(72) + 1 divider px for the default
/// two-line layout (`dp((useThreeLinesLayout ? 78 : 72) + 1)`,
/// FlickerLoadingView.java:954-955 — the Java adds the +1 in dp).
const double kTgFlickerDialogCellHeight = 73.0;

/// User-cell skeleton row height: 64dp (FlickerLoadingView.java:970-972).
const double kTgFlickerUsersCellHeight = 64.0;

/// Dialog-cell avatar radius: 28dp (`int r = dp(28)`,
/// FlickerLoadingView.java:187).
const double kTgFlickerDialogAvatarRadius = 28.0;

/// Dialog-cell avatar left inset: 10dp (`dp(10) + r`,
/// FlickerLoadingView.java:188).
const double kTgFlickerDialogAvatarLeft = 10.0;

/// User-cell avatar radius: 23dp (`int r = dp(23)`,
/// FlickerLoadingView.java:434).
const double kTgFlickerUsersAvatarRadius = 23.0;

/// User-cell avatar left inset: 9dp (`dp(9) + r`,
/// FlickerLoadingView.java:435).
const double kTgFlickerUsersAvatarLeft = 9.0;

/// Text-bar corner radius: 4dp (`drawRoundRect(rectF, dp(4), dp(4), paint)`,
/// FlickerLoadingView.java:192 et al.).
const double kTgFlickerLineRadius = 4.0;

/// List-mode gradient ramp length: 600dp (`gradientWidth = dp(600)`,
/// FlickerLoadingView.java:927).
const double kTgFlickerGradientWidthList = 600.0;

/// Single-cell-mode gradient ramp length: 200dp (`gradientWidth = dp(200)`,
/// FlickerLoadingView.java:925).
const double kTgFlickerGradientWidthSingleCell = 200.0;

/// Sweep travel time: the translation advances `dt · extent / 400.0f` — one
/// full view extent every 400ms (FlickerLoadingView.java:894, 900).
const double kTgFlickerSweepTravelMs = 400.0;

/// Frame-delta clamp threshold: dt above 17ms… (FlickerLoadingView.java:
/// 874-877).
const double kTgFlickerFrameClampThresholdMs = 17.0;

/// …is clamped to 16ms (`dt = 16`, FlickerLoadingView.java:876).
const double kTgFlickerFrameClampMs = 16.0;

/// Frame-delta floor: dt below 4ms counts as 0 (FlickerLoadingView.java:
/// 878-880).
const double kTgFlickerMinFrameMs = 4.0;

/// Gradient color stops: `{0.0f, 0.4f, 0.6f, 1f}`
/// (FlickerLoadingView.java:930-932). Colors run
/// `[color1, color0, color0, color1]` — the highlight `color0` occupies the
/// 0.4-0.6 band.
const List<double> kTgFlickerGradientStops = <double>[0.0, 0.4, 0.6, 1.0];

/// The skeleton row shapes ported for S2 (`viewType`,
/// FlickerLoadingView.java:26-60 — see the library header for the types
/// deliberately not ported).
enum TgFlickerLoadingType {
  /// `DIALOG_CELL_TYPE = 7` — the chat-list DialogCell skeleton
  /// (FlickerLoadingView.java:32, 183-215).
  dialogCell(kTgFlickerDialogCellHeight),

  /// `USERS_TYPE = 6` — the UserCell skeleton
  /// (FlickerLoadingView.java:31, 431-456).
  users(kTgFlickerUsersCellHeight);

  const TgFlickerLoadingType(this.cellHeight);

  /// Row height (`getCellHeight`, FlickerLoadingView.java:952-1016).
  final double cellHeight;
}

/// The sweep clock — a widget-free port of `updateGradient()`'s translation
/// arithmetic (FlickerLoadingView.java:868-909), driven by explicit dt like
/// `TgRadialProgressAnimation`.
class TgFlickerSweep {
  /// Starts at rest (`totalTranslation` field default,
  /// FlickerLoadingView.java:67).
  TgFlickerSweep();

  /// Current gradient translation along the sweep axis in logical px
  /// (`totalTranslation`, FlickerLoadingView.java:67).
  double translation = 0.0;

  /// Advances the clock by [dtMs] over a view of [extent] logical px along
  /// the sweep axis (height in list mode, width in single-cell mode) with a
  /// [gradientWidth] ramp; returns the new [translation].
  ///
  /// Port of FlickerLoadingView.java:873-904: dt above
  /// [kTgFlickerFrameClampThresholdMs] clamps to [kTgFlickerFrameClampMs],
  /// below [kTgFlickerMinFrameMs] floors to 0; the translation advances
  /// `dt · extent / 400` and wraps from `extent · 2` back to
  /// `−gradientWidth · 2`.
  double update(
    double dtMs, {
    required double extent,
    required double gradientWidth,
  }) {
    double dt = dtMs.abs();
    if (dt > kTgFlickerFrameClampThresholdMs) {
      dt = kTgFlickerFrameClampMs;
    }
    if (dt < kTgFlickerMinFrameMs) {
      dt = 0.0;
    }
    translation += dt * extent / kTgFlickerSweepTravelMs;
    if (translation >= extent * 2.0) {
      translation = -gradientWidth * 2.0;
    }
    return translation;
  }
}

/// One skeleton row's shapes: the avatar circle plus the rounded text bars
/// (date bar included when shown), in draw order.
@immutable
class TgFlickerRowGeometry {
  /// Bundles precomputed shapes; obtain rows via [TgFlickerRowGeometry.of].
  const TgFlickerRowGeometry({
    required this.avatarCenter,
    required this.avatarRadius,
    required this.lines,
  });

  /// The row shapes for [type] in a row of [width] whose top edge sits at
  /// [top] — the per-type draw blocks of `onDraw`
  /// (FlickerLoadingView.java:183-215 dialog cell, :431-456 users).
  ///
  /// [TextDirection.rtl] mirrors every shape around the width axis
  /// (`checkRtl`, FlickerLoadingView.java:938-950).
  factory TgFlickerRowGeometry.of(
    TgFlickerLoadingType type, {
    required double width,
    double top = 0.0,
    bool showDate = true,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final Offset avatarCenter;
    final double avatarRadius;
    final List<RRect> lines = <RRect>[];
    const Radius r = Radius.circular(kTgFlickerLineRadius);

    RRect bar(double left, double t, double right, double b) =>
        RRect.fromLTRBR(left, top + t, right, top + b, r);

    switch (type) {
      case TgFlickerLoadingType.dialogCell:
        // Avatar r28 at x = 10 + r, vertically centered in the row
        // (FlickerLoadingView.java:186-188; the Java integer half is `childH
        // >> 1`, dp-equal to cellHeight / 2).
        avatarRadius = kTgFlickerDialogAvatarRadius;
        avatarCenter = Offset(
          kTgFlickerDialogAvatarLeft + kTgFlickerDialogAvatarRadius,
          top + kTgFlickerDialogCellHeight / 2.0,
        );
        // Title bar (76, 16)-(148, 24) (FlickerLoadingView.java:190-192).
        lines.add(bar(76.0, 16.0, 148.0, 24.0));
        // Message bar (76, 38)-(268, 46) (FlickerLoadingView.java:194-196).
        lines.add(bar(76.0, 38.0, 268.0, 46.0));
        if (showDate) {
          // Date bar (w−50, 16)-(w−12, 24) (FlickerLoadingView.java:204-208).
          lines.add(bar(width - 50.0, 16.0, width - 12.0, 24.0));
        }
      case TgFlickerLoadingType.users:
        // Avatar r23 at x = 9 + r, cy = 64 / 2 (FlickerLoadingView.java:
        // 434-435; `paddingLeft` not ported, see the library header).
        avatarRadius = kTgFlickerUsersAvatarRadius;
        avatarCenter = Offset(
          kTgFlickerUsersAvatarLeft + kTgFlickerUsersAvatarRadius,
          top + kTgFlickerUsersCellHeight / 2.0,
        );
        // Name bar (68, 17)-(260, 25) (FlickerLoadingView.java:437-439).
        lines.add(bar(68.0, 17.0, 260.0, 25.0));
        // Status bar (68, 39)-(140, 47) (FlickerLoadingView.java:441-443).
        lines.add(bar(68.0, 39.0, 140.0, 47.0));
        if (showDate) {
          // Date bar (w−50, 20)-(w−12, 28) (FlickerLoadingView.java:445-449).
          lines.add(bar(width - 50.0, 20.0, width - 12.0, 28.0));
        }
    }

    if (textDirection == TextDirection.rtl) {
      // checkRtl: x → width − x (FlickerLoadingView.java:938-950).
      return TgFlickerRowGeometry(
        avatarCenter: Offset(width - avatarCenter.dx, avatarCenter.dy),
        avatarRadius: avatarRadius,
        lines: List<RRect>.unmodifiable(lines.map(
          (RRect line) => RRect.fromLTRBR(
              width - line.right, line.top, width - line.left, line.bottom, r),
        )),
      );
    }
    return TgFlickerRowGeometry(
      avatarCenter: avatarCenter,
      avatarRadius: avatarRadius,
      lines: List<RRect>.unmodifiable(lines),
    );
  }

  /// Avatar circle center (FlickerLoadingView.java:188, 435).
  final Offset avatarCenter;

  /// Avatar circle radius (FlickerLoadingView.java:187, 434).
  final double avatarRadius;

  /// Rounded text bars in draw order — title/name, message/status, then the
  /// date bar when shown.
  final List<RRect> lines;
}

/// The `FlickerLoadingView.onDraw` port (FlickerLoadingView.java:157-866 for
/// the two S2 types): rows of [TgFlickerRowGeometry] shapes filled with the
/// sweeping 4-stop gradient. Public so tests can probe the resolved colors
/// and translation.
class TgFlickerLoadingPainter extends CustomPainter {
  /// Creates the painter with all values pre-resolved by the widget.
  TgFlickerLoadingPainter({
    required this.type,
    required this.color0,
    required this.color1,
    required this.translation,
    required this.horizontalSweep,
    required this.gradientWidth,
    required this.showDate,
    required this.textDirection,
    this.itemsLimit,
  });

  /// Row shape set.
  final TgFlickerLoadingType type;

  /// Highlight-center color — `colorKey1`, default
  /// `actionBarDefaultSubmenuBackground` (FlickerLoadingView.java:82, 917).
  final Color color0;

  /// Edge color — `colorKey2`, default `listSelector`
  /// (FlickerLoadingView.java:83, 918).
  final Color color1;

  /// Gradient translation along the sweep axis ([TgFlickerSweep.translation];
  /// `matrix.setTranslate`, FlickerLoadingView.java:898, 904).
  final double translation;

  /// true = single-cell horizontal sweep, false = list-mode vertical sweep
  /// (`isSingleCell` gating, FlickerLoadingView.java:893, 929-932).
  final bool horizontalSweep;

  /// Gradient ramp length (FlickerLoadingView.java:922-928).
  final double gradientWidth;

  /// Whether rows draw the trailing date bar (`showDate`,
  /// FlickerLoadingView.java:74, 204, 445).
  final bool showDate;

  /// Ambient direction for the `checkRtl` mirroring
  /// (FlickerLoadingView.java:938-950).
  final TextDirection textDirection;

  /// Maximum rows to draw, or null to fill the height — single-cell mode
  /// passes `itemsCount` (`if (isSingleCell && k >= itemsCount) break`,
  /// FlickerLoadingView.java:212-214).
  final int? itemsLimit;

  @override
  void paint(Canvas canvas, Size size) {
    // LinearGradient([color1, color0, color0, color1], [0, .4, .6, 1],
    // CLAMP) along the sweep axis, offset by the translation
    // (FlickerLoadingView.java:898-907, 929-934).
    final Paint paint = Paint()
      ..shader = ui.Gradient.linear(
        horizontalSweep ? Offset(translation, 0.0) : Offset(0.0, translation),
        horizontalSweep
            ? Offset(translation + gradientWidth, 0.0)
            : Offset(0.0, translation + gradientWidth),
        <Color>[color1, color0, color0, color1],
        kTgFlickerGradientStops,
        ui.TileMode.clamp,
      );

    // Row loop: `while (h <= getMeasuredHeight())` — the last row may
    // overflow-draw (FlickerLoadingView.java:185, 433).
    double h = 0.0;
    int k = 0;
    final int? limit = itemsLimit;
    while (h <= size.height) {
      final TgFlickerRowGeometry row = TgFlickerRowGeometry.of(
        type,
        width: size.width,
        top: h,
        showDate: showDate,
        textDirection: textDirection,
      );
      canvas.drawCircle(row.avatarCenter, row.avatarRadius, paint);
      for (final RRect line in row.lines) {
        canvas.drawRRect(line, paint);
      }
      h += type.cellHeight;
      k++;
      if (limit != null && k >= limit) {
        break;
      }
    }
  }

  @override
  bool shouldRepaint(TgFlickerLoadingPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.color0 != color0 ||
        oldDelegate.color1 != color1 ||
        oldDelegate.translation != translation ||
        oldDelegate.horizontalSweep != horizontalSweep ||
        oldDelegate.gradientWidth != gradientWidth ||
        oldDelegate.showDate != showDate ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.itemsLimit != itemsLimit;
  }
}

/// The `ui/Components/FlickerLoadingView.java` port — skeleton placeholder
/// rows with a continuously sweeping highlight gradient.
///
/// Two modes, as in Java:
/// - **list mode** (default): fills the parent-given height with rows and
///   sweeps the 600dp gradient vertically — the whole-list skeleton behind a
///   loading RecyclerView (FlickerLoadingView.java:899-904, 927, 932);
/// - **single-cell mode** ([singleCell] true): sizes itself
///   `cellHeight · itemsCount` tall, draws exactly [itemsCount] rows, and
///   sweeps the 200dp gradient horizontally (`setIsSingleCell` +
///   `setItemsCount`, FlickerLoadingView.java:109-111, 140-147, 893-898,
///   925, 930).
///
/// The sweep ticks continuously like the always-invalidating Java view
/// (`invalidate()` at the end of every `onDraw`, FlickerLoadingView.java:865),
/// respecting the ambient [TickerMode]; per-frame dt is clamped per
/// FlickerLoadingView.java:874-880. The skeleton is purely decorative and
/// exposes no semantics, like the Java view.
///
/// Like every component in this package, the widget takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise [colorKey1]/[colorKey2] resolve
/// through [TelegramTheme.colorOf] for per-key rebuild granularity.
class TgFlickerLoading extends StatefulWidget {
  /// Creates the skeleton.
  const TgFlickerLoading({
    super.key,
    this.type = TgFlickerLoadingType.dialogCell,
    this.singleCell = false,
    this.itemsCount = 1,
    this.showDate = true,
    this.colorKey1 = TelegramColorKey.actionBarDefaultSubmenuBackground,
    this.colorKey2 = TelegramColorKey.listSelector,
    this.resources,
  }) : assert(itemsCount > 0, 'itemsCount must be positive');

  /// Row shape set (`setViewType`, FlickerLoadingView.java:97-107).
  final TgFlickerLoadingType type;

  /// Single-cell mode: self-sized, [itemsCount] rows, horizontal sweep
  /// (`setIsSingleCell`, FlickerLoadingView.java:109-111).
  final bool singleCell;

  /// Rows drawn in single-cell mode (`setItemsCount`,
  /// FlickerLoadingView.java:1040-1042); ignored in list mode, which fills
  /// the available height.
  final int itemsCount;

  /// Whether rows draw the trailing date bar (`showDate`,
  /// FlickerLoadingView.java:1018-1020).
  final bool showDate;

  /// Highlight-center color key, default `actionBarDefaultSubmenuBackground`
  /// (`colorKey1`, FlickerLoadingView.java:82; `setColors`, :121-126).
  final int colorKey1;

  /// Edge color key, default `listSelector` (`colorKey2`,
  /// FlickerLoadingView.java:83).
  final int colorKey2;

  /// Per-surface palette override; defaults to
  /// `TelegramTheme.resources(context)` (FlickerLoadingView.java:132-136,
  /// 1044-1046).
  final TelegramResources? resources;

  @override
  State<TgFlickerLoading> createState() => _TgFlickerLoadingState();
}

class _TgFlickerLoadingState extends State<TgFlickerLoading>
    with SingleTickerProviderStateMixin {
  final TgFlickerSweep _sweep = TgFlickerSweep();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// Sweep-axis extent captured at layout time — height in list mode, width
  /// in single-cell mode (FlickerLoadingView.java:881-891).
  double _extent = 0.0;

  double get _gradientWidth => widget.singleCell
      ? kTgFlickerGradientWidthSingleCell
      : kTgFlickerGradientWidthList;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final double dtMs = (elapsed - _lastTick).inMicroseconds / 1000.0;
    _lastTick = elapsed;
    if (_extent <= 0.0) {
      return;
    }
    setState(() {
      _sweep.update(dtMs, extent: _extent, gradientWidth: _gradientWidth);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
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
    final Color color0 = _color(context, widget.colorKey1);
    final Color color1 = _color(context, widget.colorKey2);
    final TextDirection textDirection = Directionality.of(context);
    final bool singleCell = widget.singleCell;

    final Widget paint = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _extent = singleCell
            ? (constraints.hasBoundedWidth ? constraints.maxWidth : 0.0)
            : (constraints.hasBoundedHeight ? constraints.maxHeight : 0.0);
        return CustomPaint(
          size: Size.infinite,
          painter: TgFlickerLoadingPainter(
            type: widget.type,
            color0: color0,
            color1: color1,
            translation: _sweep.translation,
            horizontalSweep: singleCell,
            gradientWidth: _gradientWidth,
            showDate: widget.showDate,
            textDirection: textDirection,
            itemsLimit: singleCell ? widget.itemsCount : null,
          ),
        );
      },
    );

    if (singleCell) {
      // onMeasure: cellHeight · itemsCount (+ getAdditionalHeight() == 0)
      // (FlickerLoadingView.java:140-147, 153-155).
      return SizedBox(
        width: double.infinity,
        height: widget.type.cellHeight * widget.itemsCount,
        child: paint,
      );
    }
    return SizedBox.expand(child: paint);
  }
}
