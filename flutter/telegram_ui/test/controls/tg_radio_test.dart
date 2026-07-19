// Tests for lib/src/controls/tg_radio.dart (PLAN_UIKIT.md M6), golden-free:
//
//  * constants vs RadioButton.java / RadioCell.java;
//  * the triangle-wave circleProgress (RadioButton.java:161-166), breathing
//    ring radius (RadioButton.java:178), dot collapse (RadioButton.java:185)
//    and the second-half-only color flip (RadioButton.java:166-175);
//  * end-state radii for the 20dp RadioCell instance (ring 9, dot 5);
//  * 200ms accelerate-decelerate toggle (RadioButton.java:122-126);
//  * TgRadioCell: 50dp + 1-physical-px divider (RadioCell.java:85, 126-130),
//    disabled 0.5 alpha (RadioCell.java:114-119), radio semantics
//    (RadioCell.java:132-138), dialog key recipe (RadioCell.java:71-72);
//  * theme key resolution + resources override.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/cells/text_cell.dart'
    show TextCellDividerPainter;
import 'package:telegram_ui/src/controls/tg_radio.dart';
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
      child: Align(alignment: Alignment.topCenter, child: child),
    ),
  );
}

TgRadioPainter _radioPainter(WidgetTester tester) =>
    tester
        .widget<CustomPaint>(find.descendant(
          of: find.byType(TgRadio),
          matching: find.byType(CustomPaint),
        ))
        .painter! as TgRadioPainter;

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kTgRadioSize, 16.0); // RadioButton.java:45
      expect(kTgRadioCellRadioSize, 20.0); // RadioCell.java:70
      expect(kTgRadioCellRadioBox, 22.0); // RadioCell.java:76, 88
      expect(kTgRadioStroke, 2.0); // RadioButton.java:51
      expect(kTgRadioDuration,
          const Duration(milliseconds: 200)); // RadioButton.java:124
      expect(kTgRadioCellHeight, 50.0); // RadioCell.java:85
      expect(kTgRadioCellTextSize, 16.0); // RadioCell.java:61
      expect(kTgRadioCellPadding, 21.0); // RadioCell.java:40
      expect(kTgRadioCellRadioTopMargin, 14.0); // RadioCell.java:76
      expect(kTgRadioCellDividerInset, 20.0); // RadioCell.java:128
      expect(kTgRadioCellDisabledAlpha, 0.5); // RadioCell.java:114-119
    });

    test('triangle wave (RadioButton.java:161-166)', () {
      expect(TgRadioPainter.circleProgressFor(0.0), 0.0);
      expect(TgRadioPainter.circleProgressFor(0.25), 0.5);
      expect(TgRadioPainter.circleProgressFor(0.5), 1.0);
      expect(TgRadioPainter.circleProgressFor(0.75), 0.5);
      expect(TgRadioPainter.circleProgressFor(1.0), 0.0);
    });

    test('breathing ring radius (RadioButton.java:178): 20dp instance', () {
      // Rest: size/2 - 1dp = 9; midpoint: size/2 - 2dp = 8.
      expect(TgRadioPainter.ringRadiusFor(0.0, 20.0), 9.0);
      expect(TgRadioPainter.ringRadiusFor(0.5, 20.0), 8.0);
      expect(TgRadioPainter.ringRadiusFor(1.0, 20.0), 9.0);
    });

    test('end-state dot radius = size/4 (RadioButton.java:185): 20dp -> 5',
        () {
      expect(TgRadioPainter.dotRadiusFor(1.0, 20.0), 5.0);
      // Just past the midpoint the dot spans the full interior
      // (rad - 1dp): cp -> 1 gives size/4 + (rad-1-size/4)·1 = rad - 1.
      expect(TgRadioPainter.dotRadiusFor(0.5001, 20.0), closeTo(7.0, 0.01));
    });

    test('color flips only in the second half (RadioButton.java:161-175)',
        () {
      const Color unchecked = Color(0xFFB3B3B3);
      const Color checked = Color(0xFF229AF0);
      expect(TgRadioPainter.colorFor(0.0, unchecked, checked), unchecked);
      expect(TgRadioPainter.colorFor(0.25, unchecked, checked), unchecked);
      // Exactly at the midpoint the hue is still unchecked (`progress <=
      // 0.5f`, RadioButton.java:161).
      expect(TgRadioPainter.colorFor(0.5, unchecked, checked), unchecked);
      expect(
        TgRadioPainter.colorFor(0.75, unchecked, checked),
        Color.lerp(unchecked, checked, 0.5),
      );
      expect(TgRadioPainter.colorFor(1.0, unchecked, checked), checked);
    });
  });

  group('TgRadio widget', () {
    testWidgets('bare default: 16dp, radioBackground keys',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgRadio(checked: false)));
      expect(tester.getSize(find.byType(TgRadio)), const Size(16, 16));
      final TgRadioPainter painter = _radioPainter(tester);
      expect(painter.progress, 0.0);
      expect(painter.color, _dayTheme.color(TelegramColorKey.radioBackground));
      expect(painter.checkedColor,
          _dayTheme.color(TelegramColorKey.radioBackgroundChecked));
    });

    testWidgets(
        'toggle animates 200ms accelerate-decelerate '
        '(RadioButton.java:122-126)', (WidgetTester tester) async {
      bool checked = false;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return TgRadio(
            checked: checked,
            onSelected: () => setState(() => checked = true),
          );
        },
      )));
      final TgRadioState state = tester.state(find.byType(TgRadio));

      await tester.tap(find.byType(TgRadio));
      await tester.pump();
      expect(checked, isTrue);
      expect(state.debugProgress, 0.0);

      // AccelerateDecelerateInterpolator at t = 0.5 is exactly 0.5 — the
      // animation midpoint is the triangle-wave peak.
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.debugProgress, closeTo(0.5, 1e-9));
      expect(_radioPainter(tester).progress, closeTo(0.5, 1e-9));

      await tester.pump(const Duration(milliseconds: 100));
      expect(state.debugProgress, 1.0);
    });

    testWidgets('tap on an already-selected radio does not fire',
        (WidgetTester tester) async {
      int selections = 0;
      await tester.pumpWidget(_host(TgRadio(
        checked: true,
        onSelected: () => selections++,
      )));
      await tester.tap(find.byType(TgRadio));
      await tester.pump();
      expect(selections, 0);
    });

    testWidgets('radio semantics', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(TgRadio(
        checked: true,
        onSelected: () {},
      )));
      expect(
        tester.getSemantics(find.byType(TgRadio)),
        containsSemantics(
          isInMutuallyExclusiveGroup: true,
          hasCheckedState: true,
          isChecked: true,
        ),
      );
      handle.dispose();
    });
  });

  group('TgRadioCell', () {
    testWidgets('50dp row + 1 physical px divider (RadioCell.java:85)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _host(const TgRadioCell(text: 'Option', checked: false)));
      expect(tester.getSize(find.byType(TgRadioCell)), const Size(800, 50));

      await tester.pumpWidget(_host(const TgRadioCell(
        text: 'Option',
        checked: false,
        divider: true,
      )));
      // Default test devicePixelRatio is 3.0: 50dp + 1px = 50 + 1/3.
      expect(tester.getSize(find.byType(TgRadioCell)).height,
          closeTo(50.0 + 1.0 / 3.0, 0.001));
      final TextCellDividerPainter painter = tester
          .widget<CustomPaint>(find
              .descendant(
                of: find.byType(TgRadioCell),
                matching: find.byType(CustomPaint),
              )
              .first)
          .foregroundPainter! as TextCellDividerPainter;
      expect(painter.inset, 20.0); // RadioCell.java:128
      expect(painter.thickness, closeTo(1.0 / 3.0, 0.001));
      expect(painter.color, _dayTheme.color(TelegramColorKey.divider));
    });

    testWidgets('geometry: text at padding, radio 22x22 trailing at 14dp',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _host(const TgRadioCell(text: 'Option', checked: true)));
      expect(tester.getTopLeft(find.text('Option')).dx, 21.0);
      final Rect radio = tester.getRect(find.byType(TgRadio));
      // Frame 22x22 at end inset padding + 1, top 14 (RadioCell.java:76);
      // drawn size 20 centered in it (RadioCell.java:70).
      expect(radio.size, const Size(20, 20));
      expect(radio.top, 14.0 + 1.0); // (22 - 20) / 2 inside the frame
      expect(radio.right, 800.0 - 21.0 - 1.0 - 1.0);
      final TgRadioPainter painter = _radioPainter(tester);
      expect(painter.size, 20.0);
      expect(painter.progress, 1.0);
    });

    testWidgets('taps select once; selected rows do not re-fire',
        (WidgetTester tester) async {
      int selections = 0;
      await tester.pumpWidget(_host(TgRadioCell(
        text: 'Option',
        checked: false,
        onSelected: () => selections++,
      )));
      await tester.tap(find.byType(TgRadioCell));
      expect(selections, 1);

      await tester.pumpWidget(_host(TgRadioCell(
        text: 'Option',
        checked: true,
        onSelected: () => selections++,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TgRadioCell));
      expect(selections, 1);
    });

    testWidgets('disabled: 0.5 alpha on the content, taps ignored '
        '(RadioCell.java:111-120)', (WidgetTester tester) async {
      int selections = 0;
      await tester.pumpWidget(_host(TgRadioCell(
        text: 'Option',
        checked: false,
        enabled: false,
        onSelected: () => selections++,
      )));
      final Opacity opacity = tester.widget<Opacity>(find.descendant(
        of: find.byType(TgRadioCell),
        matching: find.byType(Opacity),
      ));
      expect(opacity.opacity, kTgRadioCellDisabledAlpha);
      await tester.tap(find.byType(TgRadioCell), warnIfMissed: false);
      expect(selections, 0);
    });

    testWidgets('dialog variant resolves the dialog keys '
        '(RadioCell.java:56-57, 71-72)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
          const TgRadioCell.dialog(text: 'Option', checked: false)));
      expect(
        tester.widget<Text>(find.text('Option')).style!.color,
        _dayTheme.color(TelegramColorKey.dialogTextBlack),
      );
      final TgRadioPainter painter = _radioPainter(tester);
      expect(painter.color,
          _dayTheme.color(TelegramColorKey.dialogRadioBackground));
      expect(painter.checkedColor,
          _dayTheme.color(TelegramColorKey.dialogRadioBackgroundChecked));
    });

    testWidgets('row semantics announce a radio (RadioCell.java:132-138)',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(TgRadioCell(
        text: 'Option',
        checked: true,
        onSelected: () {},
      )));
      expect(
        tester.getSemantics(find.byType(TgRadioCell)),
        containsSemantics(
          isInMutuallyExclusiveGroup: true,
          hasCheckedState: true,
          isChecked: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('resources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color override = Color(0xFF123456);
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return TgRadioCell(
          text: 'Option',
          checked: false,
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.radioBackground: override,
            },
          ),
        );
      })));
      expect(_radioPainter(tester).color, override);
    });
  });
}
