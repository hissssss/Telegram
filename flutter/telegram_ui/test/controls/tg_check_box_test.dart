// Tests for lib/src/controls/tg_check_box.dart (PLAN_UIKIT.md M5),
// golden-free:
//
//  * constants vs CheckBoxBase.java (sizes, strokes, anchors, 200ms);
//  * the two-phase progress split (CheckBoxBase.java:407, 521) and the
//    EASE_OUT timing (CheckBoxBase.java:291);
//  * recipe ring strokes 1.2/1.5/3 (CheckBoxBase.java:122-124, 250-268);
//  * disabled fill `checkboxDisabled` (CheckBoxBase.java:530);
//  * avatar-overlay ring fade from transparent white
//    (CheckBoxBase.java:432-434);
//  * checkbox semantics and the controlled-widget contract;
//  * theme key resolution + resources override (both directions).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/controls/tg_check_box.dart';
import 'package:telegram_ui/src/foundation/tg_curves.dart';
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

TgCheckBoxPainter _painter(WidgetTester tester) =>
    tester
        .widget<CustomPaint>(find.descendant(
          of: find.byType(TgCheckBox),
          matching: find.byType(CustomPaint),
        ))
        .painter! as TgCheckBoxPainter;

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kTgCheckBoxSize, 21.0); // CheckBoxCell.java:194
      expect(kTgCheckBoxPickerSize, 24.0); // spec_forms.md §1
      expect(kTgCheckBoxCheckStroke, 1.9); // CheckBoxBase.java:120
      expect(kTgCheckBoxRingStroke, 1.2); // CheckBoxBase.java:124
      expect(kTgCheckBoxSettingsRingStroke, 1.5); // CheckBoxBase.java:264-266
      expect(kTgCheckBoxAvatarRingStroke, 3.0); // CheckBoxBase.java:262-263
      expect(kTgCheckBoxDuration,
          const Duration(milliseconds: 200)); // CheckBoxBase.java:277
      expect(kTgCheckBoxCurve, TgCurves.easeOut); // CheckBoxBase.java:291
      expect(kTgCheckBoxCheckAnchor,
          const Offset(-1.5, 4.0)); // CheckBoxBase.java:632-633
      expect(kTgCheckBoxCheckLongArm, 9.0); // CheckBoxBase.java:630
      expect(kTgCheckBoxCheckShortArm, 4.0); // CheckBoxBase.java:631
      expect(kTgCheckBoxOuterRadiusInset, 0.2); // CheckBoxBase.java:401-403
      expect(kTgCheckBoxFillInset, 0.5); // CheckBoxBase.java:564, 573
      expect(kTgCheckBoxSettingsRingInset, 1.5); // CheckBoxBase.java:459
      expect(kTgCheckBoxUncheckedInteriorAlpha, 0x28); // CheckBoxBase.java:429
      expect(kTgCheckBoxArcStartAngle, 90.0); // CheckBoxBase.java:498
      expect(kTgCheckBoxArcSweepAngle, 270.0); // CheckBoxBase.java:499
    });

    test('phase split (CheckBoxBase.java:407, 521)', () {
      expect(TgCheckBox.roundProgressFor(0.0), 0.0);
      expect(TgCheckBox.roundProgressFor(0.25), 0.5);
      expect(TgCheckBox.roundProgressFor(0.5), 1.0);
      expect(TgCheckBox.roundProgressFor(0.75), 1.0);
      expect(TgCheckBox.roundProgressFor(1.0), 1.0);
      expect(TgCheckBox.checkProgressFor(0.0), 0.0);
      expect(TgCheckBox.checkProgressFor(0.25), 0.0);
      expect(TgCheckBox.checkProgressFor(0.5), 0.0);
      expect(TgCheckBox.checkProgressFor(0.75), 0.5);
      expect(TgCheckBox.checkProgressFor(1.0), 1.0);
    });

    test('ring fade: transparent white -> target (CheckBoxBase.java:432-434)',
        () {
      const Color target = Color(0xFFB3B3B3);
      expect(tgCheckBoxRingFadeColor(target, 0.0), const Color(0x00FFFFFF));
      expect(tgCheckBoxRingFadeColor(target, 1.0), target);
      // Midpoint: alpha 127, channels between 0xB3 and 0xFF.
      final Color mid = tgCheckBoxRingFadeColor(target, 0.5);
      expect((mid.a * 255).round(), 127);
      expect((mid.r * 255).round(), 217); // (int)(255 + (179-255)*0.5) = 217
    });
  });

  group('painter probes', () {
    testWidgets('progress 0 / 1 snap without animation on first build',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgCheckBox(checked: false)));
      expect(_painter(tester).progress, 0.0);
      expect(tester.getSize(find.byType(TgCheckBox)), const Size(21, 21));

      await tester.pumpWidget(_host(const TgCheckBox(checked: true)));
      // A rebuild with a changed `checked` animates; a fresh mount snaps
      // (CheckBoxBase.java:387-392).
      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pumpWidget(_host(const TgCheckBox(checked: true)));
      expect(_painter(tester).progress, 1.0);
    });

    testWidgets('toggle animates 200ms EASE_OUT (CheckBoxBase.java:277-294)',
        (WidgetTester tester) async {
      bool checked = false;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return TgCheckBox(
            checked: checked,
            onChanged: (bool value) => setState(() => checked = value),
          );
        },
      )));
      final TgCheckBoxState state = tester.state(find.byType(TgCheckBox));

      await tester.tap(find.byType(TgCheckBox));
      await tester.pump();
      expect(checked, isTrue);
      expect(state.debugProgress, 0.0);

      // At half the duration the progress sits on the EASE_OUT curve.
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.debugProgress,
          closeTo(TgCurves.easeOut.transform(0.5), 1e-3));
      // Mid-flight: phase 1 complete, phase 2 under way.
      expect(_painter(tester).progress, greaterThan(0.5));
      expect(_painter(tester).progress, lessThan(1.0));

      await tester.pump(const Duration(milliseconds: 100));
      expect(state.debugProgress, 1.0);

      // And back.
      await tester.tap(find.byType(TgCheckBox));
      await tester.pumpAndSettle();
      expect(checked, isFalse);
      expect(state.debugProgress, 0.0);
    });
  });

  group('recipes', () {
    testWidgets('ring strokes: plain 1.2 / settingsRow 1.5 / avatarOverlay 3',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgCheckBox(checked: false)));
      expect(_painter(tester).style, TgCheckBoxStyle.plain);
      expect(_painter(tester).ringStrokeWidth, kTgCheckBoxRingStroke);

      await tester
          .pumpWidget(_host(const TgCheckBox.settingsRow(checked: false)));
      expect(_painter(tester).style, TgCheckBoxStyle.settingsRow);
      expect(_painter(tester).ringStrokeWidth, kTgCheckBoxSettingsRingStroke);

      await tester
          .pumpWidget(_host(const TgCheckBox.avatarOverlay(checked: false)));
      expect(_painter(tester).style, TgCheckBoxStyle.avatarOverlay);
      expect(_painter(tester).ringStrokeWidth, kTgCheckBoxAvatarRingStroke);
    });

    testWidgets('avatar-overlay ring fades with the progress',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(const TgCheckBox.avatarOverlay(checked: false)));
      // Unchecked: fully transparent white (CheckBoxBase.java:433 at 0).
      expect(_painter(tester).ringColor, const Color(0x00FFFFFF));

      await tester
          .pumpWidget(_host(const TgCheckBox.avatarOverlay(checked: true)));
      await tester.pumpAndSettle();
      // Checked: the full radioBackground target (ProxyListActivity recipe).
      expect(
        _painter(tester).ringColor,
        tgCheckBoxRingFadeColor(
          _dayTheme.color(TelegramColorKey.radioBackground),
          1.0,
        ),
      );
    });

    testWidgets('settingsRow uses one key for ring and fill '
        '(CheckBoxCell.java:527-531)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgCheckBox.settingsRow(
        checked: true,
        colorKey: TelegramColorKey.radioBackgroundChecked,
      )));
      final TgCheckBoxPainter painter = _painter(tester);
      final Color expected =
          _dayTheme.color(TelegramColorKey.radioBackgroundChecked);
      expect(painter.fillColor, expected);
      expect(painter.ringColor, expected);
    });
  });

  group('colors', () {
    testWidgets('defaults: checkbox fill, checkboxCheck check, service '
        'interior at 0x28', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgCheckBox(checked: true)));
      final TgCheckBoxPainter painter = _painter(tester);
      expect(painter.fillColor,
          _dayTheme.color(TelegramColorKey.checkbox)); // CheckBoxBase.java:530
      expect(painter.checkColor,
          _dayTheme.color(TelegramColorKey.checkboxCheck));
      expect(
        painter.uncheckedInteriorColor,
        _dayTheme
            .color(TelegramColorKey.chat_serviceBackground)
            .withAlpha(0x28),
      ); // CheckBoxBase.java:429
    });

    testWidgets('disabled fill = checkboxDisabled (CheckBoxBase.java:530), '
        'taps ignored', (WidgetTester tester) async {
      final List<bool> changes = <bool>[];
      await tester.pumpWidget(_host(TgCheckBox(
        checked: true,
        enabled: false,
        onChanged: changes.add,
      )));
      expect(_painter(tester).fillColor,
          _dayTheme.color(TelegramColorKey.checkboxDisabled));
      await tester.tap(find.byType(TgCheckBox), warnIfMissed: false);
      await tester.pump();
      expect(changes, isEmpty);
    });

    testWidgets('resources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color override = Color(0xFF123456);
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return TgCheckBox(
          checked: true,
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.checkbox: override,
            },
          ),
        );
      })));
      expect(_painter(tester).fillColor, override);

      // And without the override the theme value resolves again.
      await tester.pumpWidget(_host(const TgCheckBox(checked: true)));
      expect(_painter(tester).fillColor,
          _dayTheme.color(TelegramColorKey.checkbox));
    });
  });

  group('semantics + control contract', () {
    testWidgets('announces checked state and toggles via onChanged',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final List<bool> changes = <bool>[];
      await tester.pumpWidget(_host(TgCheckBox(
        checked: false,
        onChanged: changes.add,
      )));
      expect(
        tester.getSemantics(find.byType(TgCheckBox)),
        isSemantics(
          hasCheckedState: true,
          isChecked: false,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.byType(TgCheckBox));
      expect(changes, <bool>[true]);

      await tester.pumpWidget(_host(const TgCheckBox(checked: true)));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byType(TgCheckBox)),
        isSemantics(hasCheckedState: true, isChecked: true),
      );
      handle.dispose();
    });

    testWidgets('null onChanged is inert', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgCheckBox(checked: false)));
      final TgCheckBoxState state = tester.state(find.byType(TgCheckBox));
      await tester.tap(find.byType(TgCheckBox), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(state.debugProgress, 0.0);
    });

    testWidgets('custom size flows to layout and painter',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgCheckBox(
        checked: false,
        size: kTgCheckBoxPickerSize,
      )));
      expect(tester.getSize(find.byType(TgCheckBox)), const Size(24, 24));
      expect(_painter(tester).diameter, 24.0);
    });
  });
}
