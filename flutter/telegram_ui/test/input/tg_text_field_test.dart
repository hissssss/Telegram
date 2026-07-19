// Ring-1/Ring-2 tests for lib/src/input/tg_text_field.dart — the
// `ui/Components/EditTextBoldCursor.java` (ETB) port — golden-free:
//
//  * constants against the Java values (cited per constant);
//  * styling: 18dp `windowBackgroundWhiteBlackText` text, block cursor
//    2dp x 24dp default color 0xff54a1db (ETB:121, 360, 416), forms/outlined
//    cursor 1.5dp x 20dp (ChangeNameActivity.java:110-111);
//  * hint: `windowBackgroundWhiteHintText`, 150ms linear fade (ETB:756-775);
//  * underline: 1dp resting / 2dp active expanding from the touch x, 150ms
//    EASE_BOTH; error snaps 2dp `text_RedRegular` and overrides focus
//    (ETB:977-1023);
//  * floating label: x0.7, 22dp rise, 200ms EASE_OUT_QUINT, hint ->
//    `windowBackgroundWhiteBlueHeader` (ETB:667-686, 814-827);
//  * outlined variant: wraps a TgOutlineContainer, selection follows focus
//    (LoginActivity.java:5384), label stays floated while filled;
//  * controlled via TextEditingController; textField semantics.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/tg_curves.dart';
import 'package:telegram_ui/src/input/tg_outline_container.dart';
import 'package:telegram_ui/src/input/tg_text_field.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

final TelegramThemeData _day = TelegramThemeData.day();

Widget _host({required Widget child}) {
  return TelegramTheme(
    data: _day,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 800),
          devicePixelRatio: 1.0,
        ),
        child: Center(
          child: SizedBox(width: 320, child: child),
        ),
      ),
    ),
  );
}

TgTextFieldState _state(WidgetTester tester) =>
    tester.state<TgTextFieldState>(find.byType(TgTextField));

EditableText _editable(WidgetTester tester) =>
    tester.widget<EditableText>(find.byKey(TgTextField.fieldKey));

Finder _underlineFinder() => find.byWidgetPredicate((Widget w) =>
    w is CustomPaint && w.foregroundPainter is TgTextFieldUnderlinePainter);

TgTextFieldUnderlinePainter _underline(WidgetTester tester) =>
    tester.widget<CustomPaint>(_underlineFinder()).foregroundPainter!
        as TgTextFieldUnderlinePainter;

double _hintOpacity(WidgetTester tester) => tester
    .widget<Opacity>(find
        .ancestor(
            of: find.byKey(TgTextField.hintKey),
            matching: find.byType(Opacity))
        .first)
    .opacity;

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      // Block cursor (ETB:121, 416).
      expect(kTgTextFieldCursorWidth, 2.0);
      expect(kTgTextFieldCursorHeight, 24.0);
      // Forms cursor recipe (ChangeNameActivity.java:110-111).
      expect(kTgTextFieldFormsCursorWidth, 1.5);
      expect(kTgTextFieldFormsCursorHeight, 20.0);
      // Hardcoded default cursor color (ETB:360, 396).
      expect(kTgTextFieldCursorColor, const Color(0xFF54A1DB));
      // Line thicknesses (ETB:978, 982, 1014).
      expect(kTgTextFieldLineThickness, 1.0);
      expect(kTgTextFieldActiveLineThickness, 2.0);
      // lineY gap (ETB:605).
      expect(kTgTextFieldLineGap, 6.0);
      // Activeness 150ms (ETB:994), hint fade 150ms (ETB:764, 769), header
      // 200ms (ETB:678).
      expect(kTgTextFieldLineDuration, const Duration(milliseconds: 150));
      expect(kTgTextFieldHintFadeDuration, const Duration(milliseconds: 150));
      expect(kTgTextFieldHeaderDuration, const Duration(milliseconds: 200));
      // Header transform (ETB:815, 823).
      expect(kTgTextFieldHeaderScale, 0.7);
      expect(kTgTextFieldHeaderRise, 22.0);
      // Outlined inner padding (TwoStepVerificationSetupActivity.java:
      // 712-713).
      expect(kTgTextFieldOutlinedPadding, 16.0);
    });
  });

  group('styling (ChangeNameActivity.java:96-111, ETB:121, 416)', () {
    testWidgets('18dp windowBackgroundWhiteBlackText, 2x24 block cursor',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(child: const TgTextField(hintText: 'Name')));
      final EditableText field = _editable(tester);
      expect(field.style.fontSize, 18.0);
      expect(field.style.fontWeight, FontWeight.w400);
      expect(field.style.color,
          _day.color(TelegramColorKey.windowBackgroundWhiteBlackText));
      expect(field.cursorWidth, kTgTextFieldCursorWidth);
      expect(field.cursorHeight, kTgTextFieldCursorHeight);
      // The Java default cursor color is the hardcoded 0xff54a1db
      // (ETB:360, 396).
      expect(field.cursorColor, kTgTextFieldCursorColor);
      expect(field.maxLines, 1);
    });

    testWidgets('cursorColor overrides, like setCursorColor (ETB:469-477)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const TgTextField(cursorColor: Color(0xFF112233)),
      ));
      expect(_editable(tester).cursorColor, const Color(0xFF112233));
    });

    testWidgets('hint uses windowBackgroundWhiteHintText at 18dp '
        '(ChangeNameActivity.java:97)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(child: const TgTextField(hintText: 'Name')));
      final Text hint =
          tester.widget<Text>(find.byKey(TgTextField.hintKey));
      expect(hint.style!.fontSize, 18.0);
      expect(hint.style!.color,
          _day.color(TelegramColorKey.windowBackgroundWhiteHintText));
    });

    testWidgets('a TelegramResources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color textOverride = Color(0xFF224466);
      const Color lineOverride = Color(0xFF884422);
      await tester.pumpWidget(_host(
        child: Builder(builder: (BuildContext context) {
          return TgTextField(
            hintText: 'Name',
            resources: ResourcesOverride(
              parent: TelegramTheme.resources(context),
              overrides: const <int, Color>{
                TelegramColorKey.windowBackgroundWhiteBlackText: textOverride,
                TelegramColorKey.windowBackgroundWhiteInputField: lineOverride,
              },
            ),
          );
        }),
      ));
      expect(_editable(tester).style.color, textOverride);
      expect(_underline(tester).lineColor, lineOverride);

      // And back without the override.
      await tester.pumpWidget(_host(child: const TgTextField(hintText: 'N')));
      expect(_editable(tester).style.color,
          _day.color(TelegramColorKey.windowBackgroundWhiteBlackText));
      expect(_underline(tester).lineColor,
          _day.color(TelegramColorKey.windowBackgroundWhiteInputField));
    });
  });

  group('hint fade (ETB:753, 756-775)', () {
    testWidgets('typing fades the hint out over 150ms, linear',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(child: const TgTextField(hintText: 'Name')));
      expect(_hintOpacity(tester), 1.0);

      await tester.enterText(find.byType(EditableText), 'a');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(_hintOpacity(tester), closeTo(0.5, 1e-9));
      await tester.pump(const Duration(milliseconds: 80));
      expect(_hintOpacity(tester), 0.0);

      // Emptying fades it back in.
      await tester.enterText(find.byType(EditableText), '');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(_hintOpacity(tester), closeTo(0.5, 1e-9));
      await tester.pumpAndSettle();
      expect(_hintOpacity(tester), 1.0);
    });

    testWidgets('a field mounted with text hides the hint snapped',
        (WidgetTester tester) async {
      final TextEditingController controller =
          TextEditingController(text: 'prefilled');
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(
        child: TgTextField(controller: controller, hintText: 'Name'),
      ));
      expect(_hintOpacity(tester), 0.0);
    });
  });

  group('underline (ETB:977-1023)', () {
    testWidgets('resting: 1dp inputField line at the bottom, no active line',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(child: const TgTextField(hintText: 'Name')));
      final TgTextFieldUnderlinePainter painter = _underline(tester);
      expect(painter.lineActive, isFalse);
      expect(painter.lineActiveness, 0.0);
      expect(painter.lineColor,
          _day.color(TelegramColorKey.windowBackgroundWhiteInputField));
      const Size box = Size(320, 30);
      expect(painter.baseLineRect(box),
          const Rect.fromLTRB(0, 29, 320, 30)); // 1dp (ETB:978, 1007).
      expect(painter.activeLineRect(box), isNull); // ETB:1009.
    });

    testWidgets(
        'focus expands a 2dp activated line from the touch x, 150ms EASE_BOTH',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(child: const TgTextField(hintText: 'Name')));
      final Offset topLeft = tester.getTopLeft(find.byType(TgTextField));
      final Size fieldSize = tester.getSize(find.byType(TgTextField));
      // Tap 50dp from the field's left edge (ETB:723-730).
      await tester
          .tapAt(topLeft + Offset(50.0, fieldSize.height / 2));
      await tester.pump();
      expect(_state(tester).debugLastTouchX, 50.0);
      expect(_state(tester).debugFocusNode.hasFocus, isTrue);
      expect(_state(tester).debugLineActive, isTrue);

      await tester.pump(); // Consume the animation's zero-elapsed tick.
      await tester.pump(const Duration(milliseconds: 75));
      expect(_state(tester).debugLineActiveness, closeTo(0.5, 1e-9));
      final TgTextFieldUnderlinePainter painter = _underline(tester);
      expect(painter.lineActive, isTrue);
      expect(painter.activeLineColor,
          _day.color(
              TelegramColorKey.windowBackgroundWhiteInputFieldActivated));

      const Size box = Size(320, 30);
      final Rect active = painter.activeLineRect(box)!;
      // centerX 50 -> maxWidth = max(50, 270) * 2 = 540 (ETB:1004-1005);
      // width = 540 * easeBoth(0.5) (ETB:1010-1012).
      final double width = 540.0 * TgCurves.easeBoth.transform(0.5);
      expect(active.left, closeTo(0.0, 1e-3)); // clamped at 0.
      expect(active.right, closeTo(50.0 + width / 2, 1e-3));
      // Thickness is the full 2dp while activating (ETB:1014).
      expect(active.top, 28.0);
      expect(active.bottom, 30.0);
      // The resting line still shows under it (ETB:1006).
      expect(painter.baseLineRect(box), isNotNull);

      // Settled: full width, resting line gone.
      await tester.pumpAndSettle();
      final TgTextFieldUnderlinePainter settled = _underline(tester);
      expect(settled.lineActiveness, 1.0);
      expect(settled.baseLineRect(box), isNull);
      expect(settled.activeLineRect(box), const Rect.fromLTRB(0, 28, 320, 30));
    });

    testWidgets('unfocus keeps the width frozen and collapses the thickness '
        '(ETB:1011-1014)', (WidgetTester tester) async {
      final FocusNode focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(_host(
        child: TgTextField(focusNode: focusNode, hintText: 'Name'),
      ));
      focusNode.requestFocus();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(_state(tester).debugLineActiveness, 1.0);

      focusNode.unfocus();
      await tester.pump();
      expect(_state(tester).debugLineActive, isFalse);
      // The activeness at the flip is frozen (ETB:990-993).
      expect(_state(tester).debugFrozenLineActiveness, 1.0);

      await tester.pump(); // Consume the animation's zero-elapsed tick.
      await tester.pump(const Duration(milliseconds: 75));
      expect(_state(tester).debugLineActiveness, closeTo(0.5, 1e-9));
      final TgTextFieldUnderlinePainter painter = _underline(tester);
      const Size box = Size(320, 30);
      final Rect active = painter.activeLineRect(box)!;
      // Width stays at the frozen full expansion; thickness collapses with
      // the eased activeness: easeBoth(0.5) * 2dp = 1dp.
      expect(active.left, 0.0);
      expect(active.right, 320.0);
      expect(active.top, closeTo(29.0, 1e-3));

      await tester.pumpAndSettle();
      final TgTextFieldUnderlinePainter rest = _underline(tester);
      expect(rest.lineActiveness, 0.0);
      expect(rest.activeLineRect(box), isNull);
      expect(rest.baseLineRect(box), isNotNull);
    });

    testWidgets('error snaps the resting line to 2dp text_RedRegular and '
        'overrides focus (ETB:980-983)', (WidgetTester tester) async {
      final FocusNode focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(_host(
        child: TgTextField(focusNode: focusNode, hintText: 'Name'),
      ));
      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(_underline(tester).lineActive, isTrue);

      await tester.pumpWidget(_host(
        child: TgTextField(
            focusNode: focusNode, hintText: 'Name', errorText: 'Taken'),
      ));
      final TgTextFieldUnderlinePainter painter = _underline(tester);
      expect(painter.hasError, isTrue);
      // lineActive false even while focused (ETB:980-983).
      expect(painter.lineActive, isFalse);
      expect(painter.errorLineColor,
          _day.color(TelegramColorKey.text_RedRegular));

      // The blue line retreats over 150ms; the resting line reappears at
      // its snapped 2dp error thickness as soon as the activeness leaves 1
      // (ETB:980-982, 1006).
      const Size box = Size(320, 30);
      await tester.pump(); // Consume the animation's zero-elapsed tick.
      await tester.pump(const Duration(milliseconds: 75));
      expect(_underline(tester).lineActiveness, closeTo(0.5, 1e-9));
      expect(_underline(tester).baseLineRect(box),
          const Rect.fromLTRB(0, 28, 320, 30));
      await tester.pumpAndSettle();
      expect(_underline(tester).lineActiveness, 0.0);
      expect(_underline(tester).baseLineRect(box),
          const Rect.fromLTRB(0, 28, 320, 30));

      // Focusing in the error state does not re-activate.
      focusNode.unfocus();
      await tester.pumpAndSettle();
      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(_underline(tester).lineActive, isFalse);
      expect(_underline(tester).lineActiveness, 0.0);
    });

    testWidgets('the error string itself is not rendered (ETB:1040-1045)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const TgTextField(hintText: 'Name', errorText: 'Taken'),
      ));
      expect(find.text('Taken'), findsNothing);
    });
  });

  group('floating label (ETB:667-686, 814-827)', () {
    testWidgets('reserves 22dp of headroom', (WidgetTester tester) async {
      await tester.pumpWidget(_host(child: const TgTextField(hintText: 'Name')));
      final double plainHeight =
          tester.getSize(find.byType(TgTextField)).height;
      await tester.pumpWidget(_host(
        child: const TgTextField(hintText: 'Name', floatingLabel: true),
      ));
      final double floatingHeight =
          tester.getSize(find.byType(TgTextField)).height;
      expect(floatingHeight - plainHeight, kTgTextFieldHeaderRise);
    });

    testWidgets('focus floats the hint: x0.7, 22dp rise, 200ms '
        'EASE_OUT_QUINT, color to windowBackgroundWhiteBlueHeader',
        (WidgetTester tester) async {
      final FocusNode focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(_host(
        child: TgTextField(
            focusNode: focusNode, hintText: 'Name', floatingLabel: true),
      ));
      expect(_state(tester).debugHeaderProgress, 0.0);

      focusNode.requestFocus();
      await tester.pump();
      await tester.pump(); // Consume the animation's zero-elapsed tick.
      await tester.pump(const Duration(milliseconds: 100));
      final double progress = _state(tester).debugHeaderProgress;
      expect(progress, closeTo(TgCurves.easeOutQuint.transform(0.5), 1e-3));
      // Mid-flight color blend (ETB:824).
      final Text hint = tester.widget<Text>(find.byKey(TgTextField.hintKey));
      expect(
        hint.style!.color,
        Color.lerp(
          _day.color(TelegramColorKey.windowBackgroundWhiteHintText),
          _day.color(TelegramColorKey.windowBackgroundWhiteBlueHeader),
          progress,
        ),
      );

      await tester.pumpAndSettle();
      expect(_state(tester).debugHeaderProgress, 1.0);
      // Settled transforms: scale 0.7 (ETB:815), rise 22dp (ETB:823).
      final Iterable<Transform> transforms = tester.widgetList<Transform>(
        find.ancestor(
            of: find.byKey(TgTextField.hintKey),
            matching: find.byType(Transform)),
      );
      final Transform scale = transforms.first; // Innermost: the scale.
      final Transform translate = transforms.elementAt(1);
      expect(scale.transform.storage[0], closeTo(0.7, 1e-9));
      expect(translate.transform.getTranslation().y, closeTo(-22.0, 1e-9));
      expect(
          tester.widget<Text>(find.byKey(TgTextField.hintKey)).style!.color,
          _day.color(TelegramColorKey.windowBackgroundWhiteBlueHeader));
    });

    testWidgets('stays floated while non-empty, returns when emptied '
        '(ETB:668)', (WidgetTester tester) async {
      final FocusNode focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(_host(
        child: TgTextField(
            focusNode: focusNode, hintText: 'Name', floatingLabel: true),
      ));
      await tester.enterText(find.byType(EditableText), 'abc');
      await tester.pumpAndSettle();
      expect(_state(tester).debugHeaderProgress, 1.0);
      // The header branch keeps the hint fully opaque (ETB:814-827).
      expect(_hintOpacity(tester), 1.0);

      focusNode.unfocus();
      await tester.pumpAndSettle();
      expect(_state(tester).debugHeaderProgress, 1.0);

      await tester.enterText(find.byType(EditableText), '');
      await tester.pumpAndSettle();
      focusNode.unfocus();
      await tester.pumpAndSettle();
      expect(_state(tester).debugHeaderProgress, 0.0);
    });

    testWidgets('plain mode never floats', (WidgetTester tester) async {
      final FocusNode focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(_host(
        child: TgTextField(focusNode: focusNode, hintText: 'Name'),
      ));
      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(_state(tester).debugHeaderProgress, 0.0);
    });
  });

  group('controlled widget + callbacks', () {
    testWidgets('an external controller drives the text',
        (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(
        child: TgTextField(controller: controller, hintText: 'Name'),
      ));
      controller.text = 'from outside';
      await tester.pump();
      expect(find.text('from outside'), findsOneWidget);
    });

    testWidgets('onChanged and onSubmitted fire; textInputAction passes '
        'through', (WidgetTester tester) async {
      final List<String> changes = <String>[];
      final List<String> submits = <String>[];
      await tester.pumpWidget(_host(
        child: TgTextField(
          hintText: 'Name',
          textInputAction: TextInputAction.done,
          onChanged: changes.add,
          onSubmitted: submits.add,
        ),
      ));
      expect(_editable(tester).textInputAction, TextInputAction.done);
      await tester.enterText(find.byType(EditableText), 'cats');
      await tester.pumpAndSettle();
      expect(changes, <String>['cats']);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submits, <String>['cats']);
    });

    testWidgets('tapping anywhere on the field focuses it',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(child: const TgTextField(hintText: 'N')));
      expect(_state(tester).debugFocusNode.hasFocus, isFalse);
      await tester.tap(find.byType(TgTextField));
      await tester.pump();
      expect(_state(tester).debugFocusNode.hasFocus, isTrue);
      await tester.pumpAndSettle();
    });
  });

  group('semantics', () {
    testWidgets('exposes a text-field node', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(child: const TgTextField(hintText: 'N')));
      expect(tester.getSemantics(find.byKey(TgTextField.fieldKey)),
          isSemantics(isTextField: true));
      handle.dispose();
    });
  });

  group('outlined variant (OutlineTextContainerView wiring)', () {
    testWidgets('wraps a TgOutlineContainer, no underline, hint = label',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const TgTextField.outlined(hintText: 'Password'),
      ));
      expect(find.byType(TgOutlineContainer), findsOneWidget);
      expect(_underlineFinder(), findsNothing);
      // The inner hint Text is not built; the frame label is the hint.
      expect(find.byKey(TgTextField.hintKey), findsNothing);
      final TgOutlineContainer container =
          tester.widget<TgOutlineContainer>(find.byType(TgOutlineContainer));
      expect(container.label, 'Password');
      expect(container.selected, isFalse);
      expect(container.useCenter, isTrue);
      expect(container.error, isFalse);
    });

    testWidgets('forms cursor: 1.5x20 in windowBackgroundWhiteInputField'
        'Activated (TwoStepVerificationSetupActivity.java:714, 720-722)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const TgTextField.outlined(hintText: 'Password'),
      ));
      final EditableText field = _editable(tester);
      expect(field.cursorWidth, kTgTextFieldFormsCursorWidth);
      expect(field.cursorHeight, kTgTextFieldFormsCursorHeight);
      expect(
          field.cursorColor,
          _day.color(
              TelegramColorKey.windowBackgroundWhiteInputFieldActivated));
    });

    testWidgets('16dp inner padding '
        '(TwoStepVerificationSetupActivity.java:712-713)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const TgTextField.outlined(hintText: 'Password'),
      ));
      expect(
        find.byWidgetPredicate((Widget w) =>
            w is Padding &&
            w.padding == const EdgeInsets.all(kTgTextFieldOutlinedPadding)),
        findsOneWidget,
      );
    });

    testWidgets('selection follows focus (LoginActivity.java:5384); the '
        'label stays floated while filled (OTC:199)',
        (WidgetTester tester) async {
      final FocusNode focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(_host(
        child:
            TgTextField.outlined(focusNode: focusNode, hintText: 'Password'),
      ));
      focusNode.requestFocus();
      await tester.pump();
      await tester.pump(); // Focus applies late in the first frame.
      TgOutlineContainer container =
          tester.widget<TgOutlineContainer>(find.byType(TgOutlineContainer));
      expect(container.selected, isTrue);
      expect(container.useCenter, isTrue);

      await tester.enterText(find.byType(EditableText), 'hunter2');
      await tester.pumpAndSettle();
      container =
          tester.widget<TgOutlineContainer>(find.byType(TgOutlineContainer));
      // Non-empty: the label may no longer rest centered.
      expect(container.useCenter, isFalse);

      focusNode.unfocus();
      await tester.pumpAndSettle();
      container =
          tester.widget<TgOutlineContainer>(find.byType(TgOutlineContainer));
      expect(container.selected, isFalse);
      expect(container.useCenter, isFalse);
    });

    testWidgets('errorText drives the frame error blend',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const TgTextField.outlined(
            hintText: 'Password', errorText: 'Wrong'),
      ));
      final TgOutlineContainer container =
          tester.widget<TgOutlineContainer>(find.byType(TgOutlineContainer));
      expect(container.error, isTrue);
      expect(find.text('Wrong'), findsNothing);
    });
  });
}
