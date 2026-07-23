// Tests for lib/src/loading/tg_flicker_loading.dart (PLAN_UIKIT.md S2),
// golden-free:
//
//  * constants against FlickerLoadingView.java (cell heights :954-955,
//    :970-972; gradient widths :925-927; sweep speed :894-904; dt clamps
//    :874-880; stops :930-932);
//  * TgFlickerSweep translation arithmetic (clamp, floor, wrap);
//  * row geometry for the dialog-cell (:183-215) and users (:431-456)
//    shapes, LTR and RTL (`checkRtl`, :938-950), with and without the date
//    bar;
//  * theme key resolution (`colorKey1`/`colorKey2` defaults :82-83) + the
//    resources override, both directions;
//  * single-cell sizing (cellHeight × itemsCount, :140-147) and the
//    horizontal 200dp sweep vs the vertical 600dp list sweep;
//  * the sweep animating continuously across pumped frames.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/loading/tg_flicker_loading.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

Widget _host(Widget child, {TextDirection textDirection = TextDirection.ltr}) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: textDirection,
      child: Center(child: child),
    ),
  );
}

TgFlickerLoadingPainter _painter(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(find.descendant(
    of: find.byType(TgFlickerLoading),
    matching: find.byType(CustomPaint),
  ));
  return paint.painter! as TgFlickerLoadingPainter;
}

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      // dp(72) + 1 two-line dialog cell (FlickerLoadingView.java:954-955).
      expect(kTgFlickerDialogCellHeight, 73.0);
      expect(kTgFlickerUsersCellHeight, 64.0); // :970-972
      expect(kTgFlickerDialogAvatarRadius, 28.0); // :187
      expect(kTgFlickerDialogAvatarLeft, 10.0); // :188
      expect(kTgFlickerUsersAvatarRadius, 23.0); // :434
      expect(kTgFlickerUsersAvatarLeft, 9.0); // :435
      expect(kTgFlickerLineRadius, 4.0); // :192
      expect(kTgFlickerGradientWidthList, 600.0); // :927
      expect(kTgFlickerGradientWidthSingleCell, 200.0); // :925
      expect(kTgFlickerSweepTravelMs, 400.0); // :894, 900
      expect(kTgFlickerFrameClampThresholdMs, 17.0); // :875
      expect(kTgFlickerFrameClampMs, 16.0); // :876
      expect(kTgFlickerMinFrameMs, 4.0); // :878-880
      expect(kTgFlickerGradientStops, <double>[0.0, 0.4, 0.6, 1.0]); // :930
      // Enum plumbing.
      expect(TgFlickerLoadingType.dialogCell.cellHeight, 73.0);
      expect(TgFlickerLoadingType.users.cellHeight, 64.0);
    });
  });

  group('TgFlickerSweep', () {
    test('advances one extent per 400ms (FlickerLoadingView.java:900)', () {
      final TgFlickerSweep sweep = TgFlickerSweep();
      expect(sweep.translation, 0.0);
      sweep.update(16.0, extent: 400.0, gradientWidth: 600.0);
      // 16 · 400 / 400 = 16.
      expect(sweep.translation, 16.0);
      sweep.update(8.0, extent: 400.0, gradientWidth: 600.0);
      expect(sweep.translation, 24.0);
    });

    test('clamps large frame deltas to 16ms (:874-877)', () {
      final TgFlickerSweep sweep = TgFlickerSweep();
      sweep.update(100.0, extent: 400.0, gradientWidth: 600.0);
      expect(sweep.translation, 16.0);
    });

    test('floors deltas below 4ms to zero (:878-880)', () {
      final TgFlickerSweep sweep = TgFlickerSweep();
      sweep.update(3.9, extent: 400.0, gradientWidth: 600.0);
      expect(sweep.translation, 0.0);
    });

    test('wraps from extent·2 back to −gradientWidth·2 (:901-903)', () {
      final TgFlickerSweep sweep = TgFlickerSweep();
      sweep.translation = 799.0;
      sweep.update(16.0, extent: 400.0, gradientWidth: 600.0);
      // 799 + 16 = 815 ≥ 800 → −1200.
      expect(sweep.translation, -1200.0);
    });
  });

  group('row geometry — dialog cell (FlickerLoadingView.java:183-215)', () {
    test('avatar, title, message and date shapes', () {
      final TgFlickerRowGeometry row = TgFlickerRowGeometry.of(
        TgFlickerLoadingType.dialogCell,
        width: 400.0,
      );
      // r28 circle at (10 + 28, cellHeight / 2) (:186-188).
      expect(row.avatarRadius, 28.0);
      expect(row.avatarCenter, const Offset(38.0, 36.5));
      const Radius r = Radius.circular(4.0);
      expect(row.lines, <RRect>[
        RRect.fromLTRBR(76.0, 16.0, 148.0, 24.0, r), // :190-192
        RRect.fromLTRBR(76.0, 38.0, 268.0, 46.0, r), // :194-196
        RRect.fromLTRBR(350.0, 16.0, 388.0, 24.0, r), // :204-208
      ]);
    });

    test('top offset shifts every shape', () {
      final TgFlickerRowGeometry row = TgFlickerRowGeometry.of(
        TgFlickerLoadingType.dialogCell,
        width: 400.0,
        top: 73.0,
      );
      expect(row.avatarCenter, const Offset(38.0, 73.0 + 36.5));
      expect(row.lines.first.top, 73.0 + 16.0);
      expect(row.lines.first.bottom, 73.0 + 24.0);
    });

    test('showDate false drops the date bar (:204, 1018-1020)', () {
      final TgFlickerRowGeometry row = TgFlickerRowGeometry.of(
        TgFlickerLoadingType.dialogCell,
        width: 400.0,
        showDate: false,
      );
      expect(row.lines, hasLength(2));
    });

    test('RTL mirrors around the width axis (:938-950)', () {
      final TgFlickerRowGeometry row = TgFlickerRowGeometry.of(
        TgFlickerLoadingType.dialogCell,
        width: 400.0,
        textDirection: TextDirection.rtl,
      );
      expect(row.avatarCenter, const Offset(400.0 - 38.0, 36.5));
      const Radius r = Radius.circular(4.0);
      expect(
        row.lines.first,
        RRect.fromLTRBR(400.0 - 148.0, 16.0, 400.0 - 76.0, 24.0, r),
      );
      // Mirrored date bar hugs the leading edge.
      expect(
        row.lines.last,
        RRect.fromLTRBR(12.0, 16.0, 50.0, 24.0, r),
      );
    });
  });

  group('row geometry — users (FlickerLoadingView.java:431-456)', () {
    test('avatar, name, status and date shapes', () {
      final TgFlickerRowGeometry row = TgFlickerRowGeometry.of(
        TgFlickerLoadingType.users,
        width: 400.0,
      );
      // r23 circle at (9 + 23, 64 / 2) (:434-435).
      expect(row.avatarRadius, 23.0);
      expect(row.avatarCenter, const Offset(32.0, 32.0));
      const Radius r = Radius.circular(4.0);
      expect(row.lines, <RRect>[
        RRect.fromLTRBR(68.0, 17.0, 260.0, 25.0, r), // :437-439
        RRect.fromLTRBR(68.0, 39.0, 140.0, 47.0, r), // :441-443
        RRect.fromLTRBR(350.0, 20.0, 388.0, 28.0, r), // :445-449
      ]);
    });
  });

  group('theme keys', () {
    testWidgets(
        'defaults resolve actionBarDefaultSubmenuBackground / listSelector '
        '(:82-83, 917-918)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(width: 400, height: 300, child: TgFlickerLoading()),
      ));
      final TgFlickerLoadingPainter painter = _painter(tester);
      expect(
        painter.color0,
        _dayTheme.color(TelegramColorKey.actionBarDefaultSubmenuBackground),
      );
      expect(painter.color1, _dayTheme.color(TelegramColorKey.listSelector));
    });

    testWidgets('custom color keys resolve (`setColors`, :121-126)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(
          width: 400,
          height: 300,
          child: TgFlickerLoading(
            colorKey1: TelegramColorKey.dialogBackground,
            colorKey2: TelegramColorKey.windowBackgroundWhite,
          ),
        ),
      ));
      final TgFlickerLoadingPainter painter = _painter(tester);
      expect(
        painter.color0,
        _dayTheme.color(TelegramColorKey.dialogBackground),
      );
      expect(
        painter.color1,
        _dayTheme.color(TelegramColorKey.windowBackgroundWhite),
      );
    });

    testWidgets('resources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color override0 = Color(0xFF123456);
      const Color override1 = Color(0xFF654321);
      await tester.pumpWidget(_host(
        SizedBox(
          width: 400,
          height: 300,
          child: Builder(builder: (BuildContext context) {
            return TgFlickerLoading(
              resources: ResourcesOverride(
                parent: TelegramTheme.resources(context),
                overrides: const <int, Color>{
                  TelegramColorKey.actionBarDefaultSubmenuBackground:
                      override0,
                  TelegramColorKey.listSelector: override1,
                },
              ),
            );
          }),
        ),
      ));
      final TgFlickerLoadingPainter painter = _painter(tester);
      expect(painter.color0, override0);
      expect(painter.color1, override1);
    });
  });

  group('modes', () {
    testWidgets('list mode fills the parent and sweeps vertically at 600dp',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(width: 400, height: 300, child: TgFlickerLoading()),
      ));
      expect(tester.getSize(find.byType(TgFlickerLoading)),
          const Size(400, 300));
      final TgFlickerLoadingPainter painter = _painter(tester);
      expect(painter.horizontalSweep, isFalse); // :899-904
      expect(painter.gradientWidth, 600.0); // :927
      expect(painter.itemsLimit, isNull); // fills the height
    });

    testWidgets(
        'single-cell mode measures cellHeight × itemsCount and sweeps '
        'horizontally at 200dp (:140-147, 893-898, 925)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(
          width: 400,
          child: TgFlickerLoading(singleCell: true, itemsCount: 2),
        ),
      ));
      expect(
        tester.getSize(find.byType(TgFlickerLoading)),
        const Size(400, 2 * 73.0),
      );
      final TgFlickerLoadingPainter painter = _painter(tester);
      expect(painter.horizontalSweep, isTrue);
      expect(painter.gradientWidth, 200.0);
      expect(painter.itemsLimit, 2);
    });

    testWidgets('users type sizes rows at 64dp', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(
          width: 400,
          child: TgFlickerLoading(
            type: TgFlickerLoadingType.users,
            singleCell: true,
            itemsCount: 3,
          ),
        ),
      ));
      expect(
        tester.getSize(find.byType(TgFlickerLoading)),
        const Size(400, 3 * 64.0),
      );
    });

    testWidgets('painter mirrors the ambient RTL direction',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(width: 400, height: 300, child: TgFlickerLoading()),
        textDirection: TextDirection.rtl,
      ));
      expect(_painter(tester).textDirection, TextDirection.rtl);
    });
  });

  group('sweep animation', () {
    testWidgets('translation advances continuously across frames',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(width: 400, height: 300, child: TgFlickerLoading()),
      ));
      // Warm the ticker (the first tick's dt floors to 0).
      await tester.pump(const Duration(milliseconds: 16));
      final double t0 = _painter(tester).translation;
      await tester.pump(const Duration(milliseconds: 16));
      final double t1 = _painter(tester).translation;
      await tester.pump(const Duration(milliseconds: 16));
      final double t2 = _painter(tester).translation;
      // Each 16ms frame advances extent · 16 / 400 = 300 · 0.04 = 12
      // (FlickerLoadingView.java:900).
      expect(t1 - t0, moreOrLessEquals(12.0, epsilon: 0.001));
      expect(t2 - t1, moreOrLessEquals(12.0, epsilon: 0.001));
    });

    testWidgets('single-cell mode sweeps along the width (:893-898)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(
          width: 400,
          child: TgFlickerLoading(singleCell: true),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      final double t0 = _painter(tester).translation;
      await tester.pump(const Duration(milliseconds: 16));
      final double t1 = _painter(tester).translation;
      // extent = width 400 → 400 · 16 / 400 = 16 per frame.
      expect(t1 - t0, moreOrLessEquals(16.0, epsilon: 0.001));
    });
  });
}
