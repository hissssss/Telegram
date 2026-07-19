// Tests for lib/src/buttons/tg_dialog_button.dart (PLAN_UIKIT.md M2),
// golden-free:
//
//  * constants against the Java values (AlertDialog.java:1050-1096,
//    TextViewWithLoading.java, Theme.java:5515-5522, cited per constant);
//  * metrics: 40dp tall, 64dp min width, 12dp horizontal padding, label
//    rendered as given (no all-caps);
//  * label style: 16dp Roboto Medium (`bodyEmphasis`), `dialogButton`
//    default, `text_RedBold` destructive, resources override in both
//    directions;
//  * pressed pill: transparent at rest, 20dp-radius fill at 0x19 alpha of
//    the label color while pressed;
//  * disabled: 0.5 alpha + taps ignored;
//  * loading: 320ms EASE_OUT_QUINT label/spinner crossfade with the 6dp
//    slides, taps ignored while loading;
//  * semantics: button role, enabled state.

import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/buttons/tg_dialog_button.dart';
import 'package:telegram_ui/src/foundation/tg_curves.dart';
import 'package:telegram_ui/src/progress/tg_circular_progress.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_resources.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

/// A [TelegramResources] view over the day theme, the parent for sparse
/// [ResourcesOverride] layers in tests.
class _ThemeResources extends TelegramResources {
  const _ThemeResources(this.data);

  final TelegramThemeData data;

  @override
  Color getColor(int key) => data.color(key);
}

Widget _app(Widget child) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    ),
  );
}

Finder get _button => find.byType(TgDialogButton);

TgDialogButtonState _state(WidgetTester tester) =>
    tester.state<TgDialogButtonState>(_button);

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kTgDialogButtonHeight, 40.0); // AlertDialog.java:1084-1086
      expect(kTgDialogButtonMinWidth, 64.0); // AlertDialog.java:1074
      expect(kTgDialogButtonHorizontalPadding, 12.0); // AlertDialog.java:1082
      expect(kTgDialogButtonTextSize, 16.0); // AlertDialog.java:1076
      expect(kTgDialogButtonRippleRadius, 20.0); // AlertDialog.java:1081
      expect(kTgDialogButtonRippleAlpha, 0x19); // Theme.java:5519
      expect(kTgDialogButtonDisabledAlpha, 0.5); // AlertDialog.java:1065
      // TextViewWithLoading.java:16.
      expect(
        kTgDialogButtonLoadingDuration,
        const Duration(milliseconds: 320),
      );
      expect(kTgDialogButtonLoadingCurve, TgCurves.easeOutQuint);
      // TextViewWithLoading.java:56, 63.
      expect(kTgDialogButtonLoadingSlide, 6.0);
    });
  });

  group('metrics', () {
    testWidgets('40dp tall and 64dp minimum wide with a short label',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(
        TgDialogButton(text: 'OK', onPressed: () {}),
      ));
      // 'OK' at 16dp test font = 32dp + 24dp padding = 56 < 64 -> minWidth.
      expect(tester.getSize(_button), const Size(64, 40));
      // Gravity.CENTER (AlertDialog.java:1078).
      expect(tester.getCenter(find.text('OK')), tester.getCenter(_button));
    });

    testWidgets('wraps a wide label with 12dp horizontal padding',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(
        TgDialogButton(text: 'Delete chat', onPressed: () {}),
      ));
      // 11 glyphs * 16dp + 2 * 12dp.
      expect(tester.getSize(_button), const Size(11 * 16.0 + 24.0, 40));
      expect(
        tester.getRect(find.text('Delete chat')).left,
        tester.getRect(_button).left + kTgDialogButtonHorizontalPadding,
      );
    });

    testWidgets('renders the label as given — no all-caps transform '
        '(AlertDialog.java:1080)', (WidgetTester tester) async {
      await tester.pumpWidget(_app(
        TgDialogButton(text: 'Save draft', onPressed: () {}),
      ));
      expect(find.text('Save draft'), findsOneWidget);
      expect(find.text('SAVE DRAFT'), findsNothing);
    });
  });

  group('label style and colors', () {
    testWidgets('16dp Roboto Medium in dialogButton by default '
        '(AlertDialog.java:1076-1079)', (WidgetTester tester) async {
      await tester.pumpWidget(_app(
        TgDialogButton(text: 'OK', onPressed: () {}),
      ));
      final Text label = tester.widget<Text>(find.text('OK'));
      expect(label.style!.fontSize, kTgDialogButtonTextSize);
      expect(label.style!.fontWeight, FontWeight.w500);
      expect(label.style!.fontFamily, 'packages/telegram_ui/RobotoMedium');
      expect(
        label.style!.color,
        _dayTheme.color(TelegramColorKey.dialogButton),
      );
      expect(label.textHeightBehavior, isNotNull);
      expect(label.textHeightBehavior!.applyHeightToFirstAscent, isFalse);
      expect(label.textHeightBehavior!.applyHeightToLastDescent, isFalse);
    });

    testWidgets('destructive re-colors to text_RedBold '
        '(AlertDialog.java:231-236)', (WidgetTester tester) async {
      await tester.pumpWidget(_app(
        TgDialogButton(text: 'Delete', destructive: true, onPressed: () {}),
      ));
      final Text label = tester.widget<Text>(find.text('Delete'));
      expect(
        label.style!.color,
        _dayTheme.color(TelegramColorKey.text_RedBold),
      );
    });

    testWidgets('explicit colorKey wins over the destructive default',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(
        TgDialogButton(
          text: 'X',
          destructive: true,
          colorKey: TelegramColorKey.dialogTextGray2,
          onPressed: () {},
        ),
      ));
      final Text label = tester.widget<Text>(find.text('X'));
      expect(
        label.style!.color,
        _dayTheme.color(TelegramColorKey.dialogTextGray2),
      );
    });

    testWidgets('resources override flips the color in both directions',
        (WidgetTester tester) async {
      const Color override = Color(0xFF12AB34);
      // Without the override: the ambient theme value.
      await tester.pumpWidget(_app(
        TgDialogButton(text: 'OK', onPressed: () {}),
      ));
      expect(
        tester.widget<Text>(find.text('OK')).style!.color,
        _dayTheme.color(TelegramColorKey.dialogButton),
      );
      // With the override: the override value.
      await tester.pumpWidget(_app(
        TgDialogButton(
          text: 'OK',
          onPressed: () {},
          resources: ResourcesOverride(
            parent: _ThemeResources(_dayTheme),
            overrides: const <int, Color>{
              TelegramColorKey.dialogButton: override,
            },
          ),
        ),
      ));
      expect(tester.widget<Text>(find.text('OK')).style!.color, override);
    });
  });

  group('pressed pill', () {
    testWidgets('transparent at rest; 20dp pill at 0x19 alpha while pressed '
        '(Theme.java:5515-5522)', (WidgetTester tester) async {
      await tester.pumpWidget(_app(
        TgDialogButton(text: 'OK', onPressed: () {}),
      ));
      final Finder decorated = find.descendant(
        of: _button,
        matching: find.byType(DecoratedBox),
      );
      // No background at rest (ripple-only drawable).
      expect(decorated, findsNothing);
      expect(_state(tester).debugPressed, isFalse);

      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(_button));
      await tester.pump();
      expect(_state(tester).debugPressed, isTrue);
      final BoxDecoration decoration =
          tester.widget<DecoratedBox>(decorated).decoration as BoxDecoration;
      expect(
        decoration.color,
        _dayTheme
            .color(TelegramColorKey.dialogButton)
            .withAlpha(kTgDialogButtonRippleAlpha),
      );
      expect(
        decoration.borderRadius,
        BorderRadius.circular(kTgDialogButtonRippleRadius),
      );

      await gesture.up();
      await tester.pump();
      expect(decorated, findsNothing);
    });
  });

  group('disabled', () {
    testWidgets('renders at 0.5 alpha and ignores taps '
        '(AlertDialog.java:1062-1066)', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_app(
        TgDialogButton(text: 'OK', enabled: false, onPressed: () => taps++),
      ));
      final Opacity alpha = tester.widget<Opacity>(find
          .ancestor(
            of: find.byKey(TgDialogButton.labelKey),
            matching: find.byType(Opacity),
          )
          .first);
      expect(alpha.opacity, kTgDialogButtonDisabledAlpha);

      await tester.tap(_button);
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('enabled renders at full alpha and fires onPressed',
        (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_app(
        TgDialogButton(text: 'OK', onPressed: () => taps++),
      ));
      final Opacity alpha = tester.widget<Opacity>(find
          .ancestor(
            of: find.byKey(TgDialogButton.labelKey),
            matching: find.byType(Opacity),
          )
          .first);
      expect(alpha.opacity, 1.0);

      await tester.tap(_button);
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('loading', () {
    testWidgets('crossfades label to spinner over 320ms EASE_OUT_QUINT '
        '(TextViewWithLoading.java:16, 46-73)', (WidgetTester tester) async {
      await tester.pumpWidget(_app(
        TgDialogButton(text: 'OK', onPressed: () {}),
      ));
      expect(_state(tester).debugLoadingFactor, 0.0);
      expect(find.byKey(TgDialogButton.spinnerKey), findsNothing);

      await tester.pumpWidget(_app(
        TgDialogButton(text: 'OK', loading: true, onPressed: () {}),
      ));
      // Halfway: t = easeOutQuint(160/320).
      await tester.pump(const Duration(milliseconds: 160));
      final double t = TgCurves.easeOutQuint.transform(0.5);
      expect(_state(tester).debugLoadingFactor, moreOrLessEquals(t));
      expect(
        tester
            .widget<Opacity>(find.byKey(TgDialogButton.labelKey))
            .opacity,
        moreOrLessEquals(1.0 - t),
      );
      expect(
        tester
            .widget<Opacity>(find.byKey(TgDialogButton.spinnerKey))
            .opacity,
        moreOrLessEquals(t),
      );
      // Label slides down 6dp * t (TextViewWithLoading.java:56); the spinner
      // center slides in from -6dp * (1 - t) (TextViewWithLoading.java:63).
      final Offset buttonCenter = tester.getCenter(_button);
      expect(
        tester.getCenter(find.text('OK')).dy,
        moreOrLessEquals(buttonCenter.dy + kTgDialogButtonLoadingSlide * t),
      );
      expect(
        tester.getCenter(find.byType(TgCircularProgress)).dx,
        moreOrLessEquals(
          buttonCenter.dx - kTgDialogButtonLoadingSlide * (1.0 - t),
        ),
      );

      // Settled: label hidden, spinner opaque and centered.
      await tester.pump(const Duration(milliseconds: 160));
      expect(_state(tester).debugLoadingFactor, 1.0);
      expect(
        tester.widget<Opacity>(find.byKey(TgDialogButton.labelKey)).opacity,
        0.0,
      );
      expect(
        tester.widget<Opacity>(find.byKey(TgDialogButton.spinnerKey)).opacity,
        1.0,
      );
      expect(
        tester.getCenter(find.byType(TgCircularProgress)),
        buttonCenter,
      );

      // Unmount to dispose the spinner ticker.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('taps are ignored while loading (AlertDialog.java:1089)',
        (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_app(
        TgDialogButton(text: 'OK', loading: true, onPressed: () => taps++),
      ));
      await tester.pump(const Duration(milliseconds: 320));
      await tester.tap(_button);
      await tester.pump(const Duration(milliseconds: 20));
      expect(taps, 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('loading=false animates back and removes the spinner',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(
        TgDialogButton(text: 'OK', loading: true, onPressed: () {}),
      ));
      expect(_state(tester).debugLoadingFactor, 1.0);

      await tester.pumpWidget(_app(
        TgDialogButton(text: 'OK', onPressed: () {}),
      ));
      await tester.pump(const Duration(milliseconds: 160));
      expect(_state(tester).debugLoadingFactor,
          moreOrLessEquals(1.0 - TgCurves.easeOutQuint.transform(0.5)));
      await tester.pump(const Duration(milliseconds: 160));
      expect(_state(tester).debugLoadingFactor, 0.0);
      expect(find.byKey(TgDialogButton.spinnerKey), findsNothing);
      expect(
        tester.widget<Opacity>(find.byKey(TgDialogButton.labelKey)).opacity,
        1.0,
      );
    });
  });

  group('semantics', () {
    testWidgets('reports a button, enabled per state',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(
        TgDialogButton(text: 'OK', onPressed: () {}),
      ));
      final SemanticsData data =
          tester.getSemantics(_button).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);

      await tester.pumpWidget(_app(
        TgDialogButton(text: 'OK', enabled: false, onPressed: () {}),
      ));
      final SemanticsData disabled =
          tester.getSemantics(_button).getSemanticsData();
      expect(disabled.flagsCollection.isEnabled, Tristate.isFalse);
      handle.dispose();
    });
  });
}
