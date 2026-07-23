// Tests for lib/src/hint/tg_hint.dart (PLAN_UIKIT.md S1), golden-free:
//
//  * constants vs HintView2.java (rounding :94, paddings :95/:227, arrow
//    :97-98, text 14dp :158, show 350ms :132, scale 0.75 :865, duration
//    3500ms :83);
//  * anchor geometry: arrow extent reserved above/below/left/right, arrow
//    tip on the correct edge, joint clamped r + halfWidth off the corners
//    (:962-979), multiline padding swap (:224-234);
//  * auto-hide timer (:83, :638-641) incl. the null (`duration < 0`, :489)
//    opt-out;
//  * show/hide animation: 350ms EASE_OUT_QUINT factor observed at partial
//    pumps, onHidden after the hide completes (:690-691);
//  * touch: tap-to-dismiss vs onTap precedence (:1105-1110), arrow area not
//    tappable (`containsTouch` uses bounds, :1090-1092);
//  * theme keys (undo_background / undo_infoColor) + resources override in
//    both directions;
//  * semantics: label + tap action while shown, excluded once hidden.

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/tg_curves.dart';
import 'package:telegram_ui/src/foundation/tg_text_styles.dart';
import 'package:telegram_ui/src/hint/tg_hint.dart';
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
      child: Center(child: child),
    ),
  );
}

TgHintState _state(WidgetTester tester) => tester.state(find.byType(TgHint));

/// Offset of the text within the hint.
Offset _textOffset(WidgetTester tester) =>
    tester.getTopLeft(find.byType(Text)) - tester.getTopLeft(find.byType(TgHint));

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kTgHintDuration, const Duration(milliseconds: 3500)); // HintView2:83
      expect(kTgHintShowDuration, const Duration(milliseconds: 350)); // HintView2:132
      expect(kTgHintHiddenScale, 0.75); // HintView2:865-866
      expect(kTgHintRounding, 8.0); // HintView2:94
      // innerPadding = RectF(dp(11), dp(6), dp(11), dp(7)) (HintView2:95).
      expect(kTgHintInnerPadding, const EdgeInsets.fromLTRB(11, 6, 11, 7));
      // multiline innerPadding.set(dp(15), dp(8), dp(15), dp(8)) (HintView2:227).
      expect(kTgHintInnerPaddingMultiline, const EdgeInsets.fromLTRB(15, 8, 15, 8));
      expect(kTgHintArrowHalfWidth, 7.0); // HintView2:97
      expect(kTgHintArrowHeight, 6.0); // HintView2:98
      expect(kTgHintArrowShoulder, 2.0); // HintView2:1018
      expect(kTgHintArrowTipFlat, 1.0); // HintView2:1020
      expect(kTgHintTextSize, 14.0); // HintView2:158
      // 14dp regular is the TgTextStyles.subtitle role (API convention 5).
      expect(TgTextStyles.subtitle.fontSize, kTgHintTextSize);
      expect(TgTextStyles.subtitle.fontWeight, FontWeight.w400);
    });
  });

  group('anchor geometry', () {
    testWidgets('bottom hint reserves the arrow below the bubble',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgHint(
        text: 'Saved',
        autoHideDuration: null,
      )));
      await tester.pumpAndSettle();
      final Size textSize = tester.getSize(find.byType(Text));
      // width = 11 + text + 11; height = 6 + text + 7 + 6dp arrow.
      expect(
        tester.getSize(find.byType(TgHint)),
        Size(textSize.width + 22.0, textSize.height + 13.0 + kTgHintArrowHeight),
      );
      // Text at the inner padding origin — no arrow inset on top.
      expect(_textOffset(tester), const Offset(11.0, 6.0));

      final TgHintState state = _state(tester);
      final Rect bubble = state.debugBubbleBounds!;
      final Size hintSize = tester.getSize(find.byType(TgHint));
      expect(bubble,
          Rect.fromLTRB(0, 0, hintSize.width, hintSize.height - kTgHintArrowHeight));
      // Centered joint: arrow tip below the bubble at the bottom edge.
      expect(state.debugArrowTip, Offset(hintSize.width / 2.0, hintSize.height));
    });

    testWidgets('top hint reserves the arrow above the bubble',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgHint(
        text: 'Saved',
        direction: TgHintDirection.top,
        autoHideDuration: null,
      )));
      await tester.pumpAndSettle();
      // Content shifts down by the 6dp arrow extent.
      expect(_textOffset(tester), Offset(11.0, 6.0 + kTgHintArrowHeight));
      final TgHintState state = _state(tester);
      final Size hintSize = tester.getSize(find.byType(TgHint));
      expect(state.debugBubbleBounds,
          Rect.fromLTRB(0, kTgHintArrowHeight, hintSize.width, hintSize.height));
      expect(state.debugArrowTip, Offset(hintSize.width / 2.0, 0.0));
    });

    testWidgets('left hint reserves the arrow before the bubble',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgHint(
        text: 'Saved',
        direction: TgHintDirection.left,
        autoHideDuration: null,
      )));
      await tester.pumpAndSettle();
      expect(_textOffset(tester), Offset(11.0 + kTgHintArrowHeight, 6.0));
      final TgHintState state = _state(tester);
      expect(state.debugArrowTip!.dx, 0.0);
      expect(state.debugBubbleBounds!.left, kTgHintArrowHeight);
    });

    testWidgets('joint 0 clamps r + arrowHalfWidth off the corner (HintView2:967)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgHint(
        text: 'A longer hint message',
        joint: 0.0,
        autoHideDuration: null,
      )));
      await tester.pumpAndSettle();
      expect(_state(tester).debugArrowTip!.dx,
          kTgHintRounding + kTgHintArrowHalfWidth);
    });

    testWidgets('jointTranslate shifts the arrow along the edge (HintView2:594-602)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgHint(
        text: 'A longer hint message',
        jointTranslate: 10.0,
        autoHideDuration: null,
      )));
      await tester.pumpAndSettle();
      final Size hintSize = tester.getSize(find.byType(TgHint));
      expect(_state(tester).debugArrowTip!.dx, hintSize.width / 2.0 + 10.0);
    });

    testWidgets('multiline uses the 15/8 padding (HintView2:227)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgHint(
        text: 'line one\nline two',
        multiline: true,
        autoHideDuration: null,
      )));
      await tester.pumpAndSettle();
      final Size textSize = tester.getSize(find.byType(Text));
      expect(_textOffset(tester), const Offset(15.0, 8.0));
      expect(
        tester.getSize(find.byType(TgHint)),
        Size(textSize.width + 30.0, textSize.height + 16.0 + kTgHintArrowHeight),
      );
    });

    testWidgets('maxTextWidth caps the text (HintView2:296-299)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgHint(
        text: 'wrap wrap wrap wrap wrap wrap',
        multiline: true,
        maxTextWidth: 100.0,
        autoHideDuration: null,
      )));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Text)).width, lessThanOrEqualTo(100.0));
    });
  });

  group('show/hide animation (AnimatedFloat 350ms EASE_OUT_QUINT)', () {
    testWidgets('animates in from 0 on mount with the quint curve',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgHint(text: 'x', autoHideDuration: null)));
      expect(_state(tester).debugShowFactor, 0.0);
      await tester.pump(const Duration(milliseconds: 175));
      expect(
        _state(tester).debugShowFactor,
        closeTo(TgCurves.easeOutQuint.transform(0.5), 1e-6),
      );
      await tester.pump(const Duration(milliseconds: 175));
      expect(_state(tester).debugShowFactor, 1.0);
    });

    testWidgets('shown=false animates out over 350ms, then onHidden fires',
        (WidgetTester tester) async {
      int hidden = 0;
      Widget build(bool shown) => _host(TgHint(
            text: 'x',
            shown: shown,
            autoHideDuration: null,
            onHidden: () => hidden++,
          ));
      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      expect(_state(tester).debugShowFactor, 1.0);

      await tester.pumpWidget(build(false));
      await tester.pump(const Duration(milliseconds: 175));
      expect(
        _state(tester).debugShowFactor,
        closeTo(1.0 - TgCurves.easeOutQuint.transform(0.5), 1e-6),
      );
      expect(hidden, 0); // not until the animation completes (HintView2:690-691)
      await tester.pump(const Duration(milliseconds: 175));
      expect(_state(tester).debugShowFactor, 0.0);
      await tester.pumpAndSettle();
      expect(hidden, 1);
    });

    testWidgets('re-showing after a hide animates back in',
        (WidgetTester tester) async {
      Widget build(bool shown) =>
          _host(TgHint(text: 'x', shown: shown, autoHideDuration: null));
      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();
      expect(_state(tester).debugShowFactor, 0.0);
      await tester.pumpWidget(build(true));
      await tester.pump(const Duration(milliseconds: 175));
      final double mid = _state(tester).debugShowFactor;
      expect(mid, greaterThan(0.0));
      expect(mid, lessThan(1.0));
      await tester.pumpAndSettle();
      expect(_state(tester).debugShowFactor, 1.0);
    });
  });

  group('auto-hide timer', () {
    testWidgets('hides itself after 3500ms and reports onHidden',
        (WidgetTester tester) async {
      int hidden = 0;
      await tester.pumpWidget(_host(TgHint(text: 'x', onHidden: () => hidden++)));
      await tester.pump(kTgHintShowDuration); // show animation completes
      expect(_state(tester).debugAutoHideScheduled, isTrue);

      // 1ms short of the 3500ms deadline: still up.
      await tester.pump(kTgHintDuration - kTgHintShowDuration - const Duration(milliseconds: 1));
      expect(_state(tester).debugEffectivelyShown, isTrue);

      await tester.pump(const Duration(milliseconds: 1));
      expect(_state(tester).debugEffectivelyShown, isFalse);
      expect(_state(tester).debugAutoHideScheduled, isFalse);
      await tester.pump(kTgHintShowDuration);
      expect(_state(tester).debugShowFactor, 0.0);
      await tester.pumpAndSettle();
      expect(hidden, 1);
    });

    testWidgets('null duration disables auto-hide (HintView2:489)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgHint(text: 'x', autoHideDuration: null)));
      await tester.pumpAndSettle();
      expect(_state(tester).debugAutoHideScheduled, isFalse);
      await tester.pump(const Duration(seconds: 10));
      expect(_state(tester).debugEffectivelyShown, isTrue);
      expect(_state(tester).debugShowFactor, 1.0);
    });
  });

  group('touch (HintView2:1105-1110)', () {
    testWidgets('tap on the bubble hides by default', (WidgetTester tester) async {
      int hidden = 0;
      await tester.pumpWidget(_host(TgHint(
        text: 'x',
        autoHideDuration: null,
        onHidden: () => hidden++,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TgHint));
      expect(_state(tester).debugEffectivelyShown, isFalse);
      await tester.pumpAndSettle();
      expect(_state(tester).debugShowFactor, 0.0);
      expect(hidden, 1);
    });

    testWidgets('onTap wins over hide-by-touch', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_host(TgHint(
        text: 'x',
        autoHideDuration: null,
        onTap: () => taps++,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TgHint));
      await tester.pump();
      expect(taps, 1);
      expect(_state(tester).debugEffectivelyShown, isTrue);
      expect(_state(tester).debugShowFactor, 1.0);
    });

    testWidgets('hideByTouch: false makes the bubble inert',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgHint(
        text: 'x',
        autoHideDuration: null,
        hideByTouch: false,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TgHint), warnIfMissed: false);
      await tester.pump();
      expect(_state(tester).debugEffectivelyShown, isTrue);
    });

    testWidgets('the arrow area is not tappable (containsTouch, HintView2:1090)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgHint(text: 'x', autoHideDuration: null)));
      await tester.pumpAndSettle();
      // Bottom-center of the widget lies inside the 6dp arrow band, outside
      // the bubble bounds.
      final Offset arrowArea =
          tester.getBottomLeft(find.byType(TgHint)) + const Offset(2.0, -2.0);
      await tester.tapAt(arrowArea);
      await tester.pump();
      expect(_state(tester).debugEffectivelyShown, isTrue);
    });
  });

  group('theme keys', () {
    testWidgets('defaults resolve undo_background / undo_infoColor',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgHint(text: 'x', autoHideDuration: null)));
      await tester.pumpAndSettle();
      expect(_state(tester).debugBackgroundColor,
          _dayTheme.color(TelegramColorKey.undo_background));
      final Text text = tester.widget<Text>(find.byType(Text));
      expect(text.style!.color, _dayTheme.color(TelegramColorKey.undo_infoColor));
    });

    testWidgets('resources override wins over the ambient theme (both directions)',
        (WidgetTester tester) async {
      const Color bgOverride = Color(0xFF123456);
      const Color textOverride = Color(0xFF654321);
      // Direction 1: ambient theme.
      await tester.pumpWidget(_host(const TgHint(text: 'x', autoHideDuration: null)));
      await tester.pumpAndSettle();
      expect(_state(tester).debugBackgroundColor,
          _dayTheme.color(TelegramColorKey.undo_background));
      // Direction 2: override flips both resolved colors.
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return TgHint(
          text: 'x',
          autoHideDuration: null,
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.undo_background: bgOverride,
              TelegramColorKey.undo_infoColor: textOverride,
            },
          ),
        );
      })));
      await tester.pumpAndSettle();
      expect(_state(tester).debugBackgroundColor, bgOverride);
      final Text text = tester.widget<Text>(find.byType(Text));
      expect(text.style!.color, textOverride);
    });
  });

  group('semantics', () {
    testWidgets('shown: label + tap action; hidden: excluded',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      Widget build(bool shown) =>
          _host(TgHint(text: 'Saved to gallery', shown: shown, autoHideDuration: null));
      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Saved to gallery'), findsOneWidget);
      final SemanticsNode tapNode = tester.getSemantics(find.byType(GestureDetector));
      expect(tapNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Saved to gallery'), findsNothing);
      handle.dispose();
    });
  });
}
