// Tests for lib/src/components/cells/shadow_section_cell.dart
// (ARCHITECTURE.md section 6, row "ShadowSectionCell"), golden-free:
//
//  * geometry: fixed 12dp height, measured exactly
//    (ShadowSectionCell.java:32, 107-109), size override;
//  * fill: `windowBackgroundGray` key by default, flat-color constructor
//    variant, transparent spacer (ShadowSectionCell.java:74-92);
//  * opt-in hairlines, default off to match upstream (the greydivider
//    9-patches are commented out, ShadowSectionCell.java:74-92);
//  * the resources override.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/cells/shadow_section_cell.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

Widget _host(Widget child) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.topCenter, child: child),
    ),
  );
}

Finder _coloredBox() => find.descendant(
      of: find.byType(ShadowSectionCell),
      matching: find.byType(ColoredBox),
    );

Finder _customPaint() => find.descendant(
      of: find.byType(ShadowSectionCell),
      matching: find.byType(CustomPaint),
    );

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kShadowSectionCellHeight, 12.0); // ShadowSectionCell.java:32
    });
  });

  group('geometry', () {
    testWidgets('12dp tall, full width (ShadowSectionCell.java:107-109)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ShadowSectionCell()));
      expect(
        tester.getSize(find.byType(ShadowSectionCell)),
        const Size(800, 12),
      );
    });

    testWidgets('size override (`setSize`, ShadowSectionCell.java:70-72)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ShadowSectionCell(height: 20)));
      expect(tester.getSize(find.byType(ShadowSectionCell)).height, 20.0);
    });
  });

  group('fill', () {
    testWidgets('windowBackgroundGray by default',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ShadowSectionCell()));
      expect(
        tester.widget<ColoredBox>(_coloredBox()).color,
        _dayTheme.color(TelegramColorKey.windowBackgroundGray),
      );
    });

    testWidgets('flat backgroundColor wins (ShadowSectionCell.java:50-59)',
        (WidgetTester tester) async {
      const Color flat = Color(0xFFABCDEF);
      await tester
          .pumpWidget(_host(const ShadowSectionCell(backgroundColor: flat)));
      expect(tester.widget<ColoredBox>(_coloredBox()).color, flat);
    });

    testWidgets('null backgroundKey renders a transparent spacer '
        '(the null Java background, ShadowSectionCell.java:74-77)',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(const ShadowSectionCell(backgroundKey: null)));
      expect(_coloredBox(), findsNothing);
      expect(tester.getSize(find.byType(ShadowSectionCell)).height, 12.0);
    });

    testWidgets('resources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color override = Color(0xFF224466);
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return ShadowSectionCell(
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.windowBackgroundGray: override,
            },
          ),
        );
      })));
      expect(tester.widget<ColoredBox>(_coloredBox()).color, override);
    });
  });

  group('hairlines', () {
    testWidgets('off by default (9-patches commented out upstream, '
        'ShadowSectionCell.java:74-92)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ShadowSectionCell()));
      expect(_customPaint(), findsNothing);
    });

    testWidgets('opt-in: 1 physical px in windowBackgroundGrayShadow',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(const ShadowSectionCell(hairlines: true)));
      final ShadowSectionHairlinePainter painter =
          tester.widget<CustomPaint>(_customPaint()).foregroundPainter!
              as ShadowSectionHairlinePainter;
      // Default test devicePixelRatio is 3.0.
      expect(painter.thickness, closeTo(1.0 / 3.0, 0.001));
      expect(
        painter.color,
        _dayTheme.color(TelegramColorKey.windowBackgroundGrayShadow),
      ); // the greydivider tint key (ShadowSectionCell.java:79, 85)
      // The fill still draws underneath.
      expect(
        tester.widget<ColoredBox>(_coloredBox()).color,
        _dayTheme.color(TelegramColorKey.windowBackgroundGray),
      );
    });

    testWidgets('respects an ambient MediaQuery devicePixelRatio',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const MediaQuery(
        data: MediaQueryData(devicePixelRatio: 2.0),
        child: ShadowSectionCell(hairlines: true),
      )));
      final ShadowSectionHairlinePainter painter =
          tester.widget<CustomPaint>(_customPaint()).foregroundPainter!
              as ShadowSectionHairlinePainter;
      expect(painter.thickness, 0.5);
    });
  });
}
