// Tests for lib/src/buttons/tg_button.dart (PLAN_UIKIT.md M1,
// spec_primitives.md §1), golden-free:
//
//  * constants vs ButtonWithCounterView.java / ScaleStateListAnimator.java;
//  * variant colors through theme keys (BWC:114-119, 179-192) + resources
//    override in both directions;
//  * press scale 0.98/80ms + Overshoot(1.2)/350ms release (BWC:109,
//    SSLA:15-33);
//  * loading crossfade 320ms EASE_OUT_QUINT hides the label (BWC:326-354,
//    504-521);
//  * counter pill appear (350ms alpha) / bounce (Overshoot(2.0) 200ms) /
//    digit roll (BWC:50-51, 364-387, 404-415);
//  * disabled ignores taps and halves content alpha (BWC:428-448);
//  * subText show/hide 200ms and the 7dp label lift (BWC:278-319, 534);
//  * timer mode ticks once per second and blocks taps (BWC:219-240);
//  * semantics (button role, enabled state, label).

import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/buttons/tg_button.dart';
import 'package:telegram_ui/src/foundation/color_math.dart';
import 'package:telegram_ui/src/foundation/tg_text_styles.dart';
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
      child: Center(child: SizedBox(width: 320, child: child)),
    ),
  );
}

TgButtonContentPainter _painter(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(find.descendant(
    of: find.byType(TgButton),
    matching: find.byType(CustomPaint),
  ));
  return paint.painter! as TgButtonContentPainter;
}

TgButtonState _state(WidgetTester tester) => tester.state(find.byType(TgButton));

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      // Call-site convention: MATCH_PARENT x 48 (spec_primitives.md §1.1).
      expect(kTgButtonHeight, 48.0);
      expect(kTgButtonRadius, 8.0); // BWC:44
      expect(kTgButtonRoundRadius, 24.0); // BWC:67-70
      // ScaleStateListAnimator.apply(this, .02f, 1.2f) (BWC:109; SSLA:25,33).
      expect(kTgButtonPressScale, 0.02);
      expect(kTgButtonReleaseTension, 1.2);
      expect(kTgButtonPressDuration, const Duration(milliseconds: 80));
      expect(kTgButtonReleaseDuration, const Duration(milliseconds: 350));
      // Loading (BWC:350, 508, 519-520).
      expect(kTgButtonLoadingDuration, const Duration(milliseconds: 320));
      expect(kTgButtonLoadingShift, 24.0);
      expect(kTgButtonLoadingSquash, 0.4);
      // Text-mode ripple (BWC:170, 187).
      expect(kTgButtonTextRippleAlpha, 0.10);
      // Counter (BWC:51, 384-385, 137, 558-575, 527, 209, 579).
      expect(kTgButtonCountAlphaDuration, const Duration(milliseconds: 350));
      expect(kTgButtonCountBounceDuration, const Duration(milliseconds: 200));
      expect(kTgButtonCountBounceTension, 2.0);
      expect(kTgButtonCountRollDuration, const Duration(milliseconds: 250));
      expect(kTgButtonCountRollAmplitude, 0.3);
      expect(kTgButtonCountPillHeight, 18.0);
      expect(kTgButtonCountPillRadius, 10.0);
      expect(kTgButtonCountPillPadding, 4.0);
      expect(kTgButtonCountPillMinTextWidth, 9.0);
      expect(kTgButtonCountGapFilled, 5.0);
      expect(kTgButtonCountGapBare, 2.0);
      expect(kTgButtonCountReservedExtra, 15.66);
      expect(kTgButtonBareCountAlpha, 0.5);
      expect(kTgButtonBareCountTextSize, 14.0);
      // SubText (BWC:300, 468, 534, 548, 550).
      expect(kTgButtonSubTextShift, 7.0);
      expect(kTgButtonSubTextOffset, 11.0);
      expect(kTgButtonSubTextAlpha, 200 / 255);
      expect(kTgButtonSubTextDuration, const Duration(milliseconds: 200));
      expect(kTgButtonSubTextStartScale, 0.1);
      // Disabled (BWC:428-448, 535).
      expect(kTgButtonDisabledAlpha, 0.5);
      expect(kTgButtonEnableDuration, const Duration(milliseconds: 300));
      expect(kTgButtonLabelNudge, 1.0); // BWC:530-532
    });
  });

  group('tgFormatNumber (LocaleController.java:1636-1646)', () {
    test('groups digits in threes with spaces', () {
      expect(tgFormatNumber(0), '0');
      expect(tgFormatNumber(7), '7');
      expect(tgFormatNumber(999), '999');
      expect(tgFormatNumber(1000), '1 000');
      expect(tgFormatNumber(1234567), '1 234 567');
      expect(tgFormatNumber(-1234), '-1 234');
      expect(tgFormatNumber(1000000, ','), '1,000,000');
    });
  });

  group('geometry', () {
    testWidgets('48dp tall, match-parent wide, r8 default', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgButton(text: 'Continue', onPressed: () {})));
      expect(tester.getSize(find.byType(TgButton)), const Size(320, 48));
      expect(_painter(tester).radius, kTgButtonRadius);
    });

    testWidgets('round radius and custom height', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgButton(
        text: 'Continue',
        onPressed: () {},
        radius: kTgButtonRoundRadius,
        height: 44,
      )));
      expect(tester.getSize(find.byType(TgButton)).height, 44.0);
      expect(_painter(tester).radius, 24.0);
    });
  });

  group('variant colors (theme keys)', () {
    testWidgets('filled: addButton fill, buttonText bold label, listSelector ripple',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgButton(text: 'Continue', onPressed: () {})));
      final TgButtonContentPainter painter = _painter(tester);
      expect(painter.backgroundColor,
          _dayTheme.color(TelegramColorKey.featuredStickers_addButton)); // BWC:115, 181
      expect(painter.labelStyle.color,
          _dayTheme.color(TelegramColorKey.featuredStickers_buttonText)); // BWC:183
      expect(painter.rippleColor, _dayTheme.color(TelegramColorKey.listSelector)); // BWC:185
      // 14dp Roboto Medium (BWC:124-126) via the TgTextStyles.label role.
      expect(painter.labelStyle.fontSize, 14.0);
      expect(painter.labelStyle.fontWeight, FontWeight.w500);
      expect(painter.labelStyle.fontFamily, TgTextStyles.label.fontFamily);
      // Pill paint is always featuredStickers_buttonText (BWC:191).
      expect(painter.pillColor,
          _dayTheme.color(TelegramColorKey.featuredStickers_buttonText));
    });

    testWidgets('text mode: transparent, regular addButton label, 10%-alpha ripple',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgButton(
        text: 'Skip',
        onPressed: () {},
        variant: TgButtonVariant.text,
      )));
      final TgButtonContentPainter painter = _painter(tester);
      expect(painter.backgroundColor, isNull); // setBackground(null), BWC:97
      final Color label = _dayTheme.color(TelegramColorKey.featuredStickers_addButton);
      expect(painter.labelStyle.color, label); // BWC:183
      expect(painter.labelStyle.fontWeight, FontWeight.w400); // BWC:96-98
      // Theme.multAlpha(textColor, .10f) (BWC:187).
      expect(painter.rippleColor,
          Color(multAlpha(label.toARGB32(), kTgButtonTextRippleAlpha)));
    });

    testWidgets('neutral: buttonNeutral fill, buttonNeutralText label',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgButton(
        text: 'Cancel',
        onPressed: () {},
        variant: TgButtonVariant.neutral,
      )));
      final TgButtonContentPainter painter = _painter(tester);
      expect(painter.backgroundColor,
          _dayTheme.color(TelegramColorKey.buttonNeutral)); // BWC:75, 181
      expect(painter.labelStyle.color,
          _dayTheme.color(TelegramColorKey.buttonNeutralText)); // BWC:183
    });

    testWidgets('custom color replaces the fill (setColor, BWC:164-167)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgButton(
        text: 'Buy',
        onPressed: () {},
        color: const Color(0xFF112233),
      )));
      expect(_painter(tester).backgroundColor, const Color(0xFF112233));
    });

    testWidgets('resources override wins over the ambient theme (both directions)',
        (WidgetTester tester) async {
      const Color override = Color(0xFF654321);
      // Direction 1: no override — ambient theme resolves the key.
      await tester.pumpWidget(_host(TgButton(text: 'Go', onPressed: () {})));
      expect(_painter(tester).backgroundColor,
          _dayTheme.color(TelegramColorKey.featuredStickers_addButton));
      // Direction 2: the override flips the resolved color.
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return TgButton(
          text: 'Go',
          onPressed: () {},
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.featuredStickers_addButton: override,
            },
          ),
        );
      })));
      expect(_painter(tester).backgroundColor, override);
    });
  });

  group('press feedback (ScaleStateListAnimator .02/1.2)', () {
    testWidgets('press-in reaches 0.98 in 80ms; release overshoots past 1 and settles',
        (WidgetTester tester) async {
      int presses = 0;
      await tester.pumpWidget(_host(TgButton(text: 'Send', onPressed: () => presses++)));
      final TgButtonState state = _state(tester);
      expect(state.debugPressScale, 1.0);

      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(find.byType(TgButton)));
      await tester.pump(); // start the press animation
      await tester.pump(kTgButtonPressDuration);
      // pressed scale = 1 - 0.02 (BWC:109; SSLA:22-25).
      expect(state.debugPressScale, closeTo(0.98, 1e-9));

      await gesture.up();
      await tester.pump(); // start the release animation
      // OvershootInterpolator(1.2) exceeds 1 for t > ~0.45 of the 350ms run:
      // the scale swings above 1.0.
      await tester.pump(const Duration(milliseconds: 245));
      expect(state.debugPressScale, greaterThan(1.0));
      await tester.pump(const Duration(milliseconds: 105));
      expect(state.debugPressScale, closeTo(1.0, 1e-9));
      expect(presses, 1);
    });
  });

  group('loading (setLoading, BWC:326-354)', () {
    testWidgets('320ms EASE_OUT_QUINT crossfade hides the label and shows the spinner',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgButton(text: 'Send', onPressed: () {})));
      expect(_painter(tester).loadingT, 0.0);
      expect(_painter(tester).labelOpacity, 1.0);

      await tester.pumpWidget(_host(TgButton(text: 'Send', onPressed: () {}, loading: true)));
      await tester.pump(); // first animation tick
      await tester.pump(const Duration(milliseconds: 160));
      final TgButtonContentPainter mid = _painter(tester);
      // EASE_OUT_QUINT is front-loaded: past 0.5 at half time.
      expect(mid.loadingT, greaterThan(0.5));
      expect(mid.loadingT, lessThan(1.0));
      expect(mid.labelOpacity, lessThan(0.5));

      await tester.pump(const Duration(milliseconds: 160));
      expect(_painter(tester).loadingT, 1.0);
      expect(_painter(tester).labelOpacity, 0.0); // label fully hidden

      // The spinner clock ticks while loading (BWC:504-513).
      final Duration t0 = _painter(tester).spinnerElapsed;
      await tester.pump(const Duration(milliseconds: 48));
      expect(_painter(tester).spinnerElapsed - t0,
          const Duration(milliseconds: 48));
    });

    testWidgets('unloading returns to the label and stops the spinner clock',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgButton(text: 'Send', onPressed: () {}, loading: true)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(_host(TgButton(text: 'Send', onPressed: () {})));
      await tester.pump();
      await tester.pump(kTgButtonLoadingDuration);
      expect(_painter(tester).loadingT, 0.0);
      expect(_painter(tester).labelOpacity, 1.0);
      await tester.pump(const Duration(milliseconds: 32));
      // No transient callbacks left: the spinner ticker stopped.
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('counter (setCount, BWC:404-426)', () {
    testWidgets('count 0 hides the pill; showZero keeps it', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgButton(text: 'Share', onPressed: () {})));
      expect(_painter(tester).countAlpha, 0.0);
      await tester.pumpWidget(_host(TgButton(text: 'Share', onPressed: () {}, showZero: true)));
      await tester.pump();
      await tester.pump(kTgButtonCountAlphaDuration);
      expect(_painter(tester).countAlpha, 1.0);
      expect(_painter(tester).countText, '0');
    });

    testWidgets('pill appears over 350ms EASE_OUT_QUINT on a new count',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgButton(text: 'Share', onPressed: () {})));
      await tester.pumpWidget(_host(TgButton(text: 'Share', onPressed: () {}, count: 5)));
      expect(_painter(tester).countText, '5');
      await tester.pump(); // first animation tick
      await tester.pump(const Duration(milliseconds: 175));
      final double mid = _painter(tester).countAlpha;
      expect(mid, greaterThan(0.0));
      expect(mid, lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 175));
      expect(_painter(tester).countAlpha, 1.0);
      expect(_painter(tester).countFilled, isTrue);
    });

    testWidgets('count change between visible counts bounces (Overshoot(2.0) 200ms) and rolls',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgButton(text: 'Share', onPressed: () {}, count: 5)));
      await tester.pumpWidget(_host(TgButton(text: 'Share', onPressed: () {}, count: 6)));
      await tester.pump(); // first animation tick
      await tester.pump(const Duration(milliseconds: 111));
      final TgButtonContentPainter mid = _painter(tester);
      // Overshoot(2.0) peaks ~1.13 at t ≈ 5/9 (BWC:364-387).
      expect(mid.countBounceScale, greaterThan(1.0));
      // The 250ms digit roll is still in flight: old text retained.
      expect(mid.oldCountText, '5');
      expect(mid.countText, '6');
      expect(mid.rollT, lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 250));
      expect(_painter(tester).countBounceScale, 1.0);
      expect(_painter(tester).oldCountText, isNull);
    });

    testWidgets('no bounce when the counter appears from 0 (BWC:408)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgButton(text: 'Share', onPressed: () {})));
      await tester.pumpWidget(_host(TgButton(text: 'Share', onPressed: () {}, count: 5)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 111));
      expect(_painter(tester).countBounceScale, 1.0);
    });

    testWidgets('counts are space-grouped (BWC:413)', (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(TgButton(text: 'Share', onPressed: () {}, count: 1234567)));
      expect(_painter(tester).countText, '1 234 567');
    });

    testWidgets('countFilled=false: bare 14dp bold count (BWC:206-215)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgButton(
        text: 'Resend',
        onPressed: () {},
        count: 5,
        countFilled: false,
      )));
      final TgButtonContentPainter painter = _painter(tester);
      expect(painter.countFilled, isFalse);
      expect(painter.countStyle.fontSize, kTgButtonBareCountTextSize);
      expect(painter.countStyle.fontWeight, FontWeight.w500);
      // Bare count uses the label color (drawn at 50% alpha, BWC:210-214, 579).
      expect(painter.countStyle.color, painter.labelStyle.color);
    });

    testWidgets('filled count text uses the fill color (BWC:190)',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(TgButton(text: 'Share', onPressed: () {}, count: 5)));
      final TgButtonContentPainter painter = _painter(tester);
      expect(painter.countStyle.color, painter.backgroundColor);
      expect(painter.countStyle.fontSize, 12.0); // BWC:139
    });
  });

  group('disabled (setEnabled, BWC:428-448)', () {
    testWidgets('ignores taps and animates content alpha to 0.5 over 300ms',
        (WidgetTester tester) async {
      int presses = 0;
      await tester.pumpWidget(_host(TgButton(text: 'Send', onPressed: () => presses++)));
      expect(_painter(tester).contentAlpha, 1.0);
      await tester
          .pumpWidget(_host(TgButton(text: 'Send', onPressed: () => presses++, enabled: false)));
      await tester.pump(); // first animation tick
      await tester.pump(const Duration(milliseconds: 150));
      final double mid = _painter(tester).enabledT;
      expect(mid, greaterThan(0.0));
      expect(mid, lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_painter(tester).enabledT, 0.0);
      expect(_painter(tester).contentAlpha, kTgButtonDisabledAlpha);

      await tester.tap(find.byType(TgButton));
      await tester.pumpAndSettle();
      expect(presses, 0);
    });

    testWidgets('no press scale while disabled', (WidgetTester tester) async {
      await tester.pumpWidget(
          _host(TgButton(text: 'Send', onPressed: () {}, enabled: false)));
      await tester.pumpAndSettle();
      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(find.byType(TgButton)));
      await tester.pump(kTgButtonPressDuration);
      expect(_state(tester).debugPressScale, 1.0);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('null onPressed is inert without the disabled fade',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgButton(text: 'Send')));
      expect(_painter(tester).enabledT, 1.0); // no 0.5-alpha dim
      await tester.tap(find.byType(TgButton));
      await tester.pumpAndSettle();
      expect(_state(tester).debugPressScale, 1.0);
    });
  });

  group('subText (setSubText, BWC:278-319)', () {
    testWidgets('shows over 200ms and lifts the label 7dp', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgButton(text: 'Buy', onPressed: () {})));
      expect(_painter(tester).subTextT, 0.0);
      expect(_painter(tester).subText, isNull);
      await tester
          .pumpWidget(_host(TgButton(text: 'Buy', onPressed: () {}, subText: 'per month')));
      await tester.pump(); // first animation tick
      await tester.pump(const Duration(milliseconds: 100));
      final TgButtonContentPainter mid = _painter(tester);
      expect(mid.subText, 'per month');
      expect(mid.subTextT, greaterThan(0.0));
      expect(mid.subTextT, lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_painter(tester).subTextT, 1.0);
      // The 7dp label lift is subTextT-proportional (BWC:534).
      expect(kTgButtonSubTextShift * _painter(tester).subTextT, 7.0);
    });

    testWidgets('hides over 200ms, keeping the outgoing string until done',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(TgButton(text: 'Buy', onPressed: () {}, subText: 'per month')));
      await tester.pumpWidget(_host(TgButton(text: 'Buy', onPressed: () {})));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Mid-fade the outgoing string is still drawn (BWC:286-302).
      expect(_painter(tester).subText, 'per month');
      await tester.pump(const Duration(milliseconds: 100));
      expect(_painter(tester).subTextT, 0.0);
      expect(_painter(tester).subText, isNull);
    });
  });

  group('timer mode (setTimer, BWC:219-240)', () {
    testWidgets('ticks down once per second, blocks taps, fires onTimerDone at 0',
        (WidgetTester tester) async {
      int presses = 0;
      int done = 0;
      Widget build() => _host(TgButton(
            text: 'Resend',
            onPressed: () => presses++,
            timerSeconds: 2,
            onTimerDone: () => done++,
          ));
      await tester.pumpWidget(build());
      expect(_painter(tester).countText, '2');
      expect(_painter(tester).countFilled, isFalse); // setCountFilled(false), BWC:222
      expect(_state(tester).isTimerActive, isTrue);

      await tester.tap(find.byType(TgButton));
      await tester.pump();
      expect(presses, 0); // clicks blocked until the timer is up

      await tester.pump(const Duration(seconds: 1));
      expect(_painter(tester).countText, '1');
      expect(_state(tester).timerRemaining, 1);

      await tester.pump(const Duration(seconds: 1));
      expect(_state(tester).timerRemaining, 0);
      expect(done, 1);
      expect(_state(tester).isTimerActive, isFalse);
      // The zero count fades out (countAlpha target 0, showZero forced off).
      await tester.pump(kTgButtonCountAlphaDuration);
      await tester.pumpAndSettle();
      expect(_painter(tester).countAlpha, 0.0);

      await tester.tap(find.byType(TgButton));
      await tester.pumpAndSettle();
      expect(presses, 1); // setClickable(true) at 0 (BWC:231)
    });
  });

  group('semantics', () {
    testWidgets('button node with label, enabled state and tap action',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(TgButton(text: 'Continue', onPressed: () {})));
      final SemanticsNode node = tester.getSemantics(find.byType(TgButton));
      final SemanticsData data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.label, 'Continue'); // setContentDescription (BWC:255)
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('disabled button reports enabled=false with no tap action',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
          _host(TgButton(text: 'Continue', onPressed: () {}, enabled: false)));
      await tester.pumpAndSettle();
      final SemanticsData data =
          tester.getSemantics(find.byType(TgButton)).getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });
  });
}
