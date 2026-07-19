// Ring-1/Ring-2 tests for lib/src/input/tg_outline_container.dart — the
// `ui/Components/OutlineTextContainerView.java` (OTC) port — golden-free:
//
//  * constants against the Java values (cited per constant);
//  * palette: stroke `windowBackgroundWhiteInputField` ->
//    `...InputFieldActivated`, label `windowBackgroundWhiteHintText` ->
//    `...ValueText`, error -> `text_RedBold` (OTC:124-129), plus the
//    TelegramResources override path;
//  * springs: stiffness 500, critically damped (OTC:179-183), first build
//    snapped (OTC:155-164);
//  * painter geometry: label center<->gap float (OTC:196-205) and the
//    top-stroke gap (OTC:214-222).

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/tg_text_styles.dart';
import 'package:telegram_ui/src/input/tg_outline_container.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

final TelegramThemeData _day = TelegramThemeData.day();

Widget _host({required Widget child, double devicePixelRatio = 1.0}) {
  return TelegramTheme(
    data: _day,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          devicePixelRatio: devicePixelRatio,
        ),
        child: Center(
          child: SizedBox(width: 320, child: child),
        ),
      ),
    ),
  );
}

TgOutlineContainerPainter _painter(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(find.byWidgetPredicate(
      (Widget w) => w is CustomPaint && w.painter is TgOutlineContainerPainter));
  return paint.painter! as TgOutlineContainerPainter;
}

TgOutlineContainerState _state(WidgetTester tester) =>
    tester.state<TgOutlineContainerState>(find.byType(TgOutlineContainer));

/// The critically damped spring solution from 0 toward 1 with zero initial
/// velocity: `x(t) = 1 - (1 + w t) e^(-w t)`, `w = sqrt(stiffness)` —
/// SpringForce stiffness 500, DAMPING_RATIO_NO_BOUNCY (OTC:179-183).
double _criticalSpring(double tSeconds) {
  final double omega = math.sqrt(kTgOutlineSpringStiffness);
  return 1.0 - (1.0 + omega * tSeconds) * math.exp(-omega * tSeconds);
}

/// Width of [label] measured exactly like the painter (16dp body role,
/// OTC:81, 205).
double _labelWidth(String label) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: label, style: TgTextStyles.body),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
    textHeightBehavior: kTgTextHeightBehavior,
    maxLines: 1,
  )..layout();
  final double width = tp.width;
  tp.dispose();
  return width;
}

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      // PADDING_LEFT / PADDING_TEXT (OTC:23).
      expect(kTgOutlinePaddingLeft, 14.0);
      expect(kTgOutlinePaddingText, 4.0);
      // SPRING_MULTIPLIER (OTC:25).
      expect(kTgOutlineSpringMultiplier, 100.0);
      // strokeWidthRegular = max(2px, dp(0.5)) / strokeWidthSelected
      // (OTC:64-65).
      expect(kTgOutlineStrokeWidthIdle, 0.5);
      expect(kTgOutlineStrokeWidthIdleMinPx, 2.0);
      expect(kTgOutlineStrokeWidthSelected, 1.6667);
      // textPaint.setTextSize(dp(16)) (OTC:81).
      expect(kTgOutlineLabelTextSize, 16.0);
      // setPadding(0, dp(6), 0, 0) (OTC:87).
      expect(kTgOutlineTopPadding, 6.0);
      // SpringForce(stiffness 500, DAMPING_RATIO_NO_BOUNCY) (OTC:180-182).
      expect(kTgOutlineSpringStiffness, 500.0);
      expect(kTgOutlineSpringDampingRatio, 1.0);
      // textOffset = textSize/2 - dp(1.75) (OTC:196).
      expect(kTgOutlineLabelBaselineOffset, 1.75);
      // scaleX floated (OTC:204).
      expect(kTgOutlineLabelFloatedScale, 0.75);
      // drawRoundRect r8 (OTC:211).
      expect(kTgOutlineRadius, 8.0);
      // right = width - stroke - dp(6) (OTC:215).
      expect(kTgOutlineLineRightInset, 6.0);
    });

    test('idleStrokeWidth floors at 2 physical px (OTC:64)', () {
      // Low density: the 2px floor wins over dp(0.5).
      expect(TgOutlineContainer.idleStrokeWidth(1.0), 2.0);
      expect(TgOutlineContainer.idleStrokeWidth(2.0), 1.0);
      // High density: 0.5dp wins.
      expect(TgOutlineContainer.idleStrokeWidth(4.0), 0.5);
      expect(TgOutlineContainer.idleStrokeWidth(8.0), 0.5);
    });
  });

  group('theme resolution (updateColor, OTC:124-129)', () {
    testWidgets('resting colors: inputField stroke, hintText label',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const TgOutlineContainer(
          label: 'Label',
          child: SizedBox(height: 48),
        ),
      ));
      final TgOutlineContainerPainter painter = _painter(tester);
      expect(
          painter.outlineColor,
          _day.color(TelegramColorKey.windowBackgroundWhiteInputField));
      expect(painter.labelColor,
          _day.color(TelegramColorKey.windowBackgroundWhiteHintText));
      // Idle stroke at dpr 1 = max(2/1, 0.5) = 2 (OTC:64).
      expect(painter.strokeWidth, 2.0);
    });

    testWidgets('selected snaps on first build: activated stroke at 1.6667dp',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const TgOutlineContainer(
          label: 'Label',
          selected: true,
          child: SizedBox(height: 48),
        ),
      ));
      // First build snaps (animateSelection(..., false) path, OTC:155-164).
      expect(_state(tester).debugSelectionProgress, 1.0);
      expect(_state(tester).debugTitleProgress, 1.0);
      final TgOutlineContainerPainter painter = _painter(tester);
      expect(
          painter.outlineColor,
          _day.color(
              TelegramColorKey.windowBackgroundWhiteInputFieldActivated));
      expect(painter.labelColor,
          _day.color(TelegramColorKey.windowBackgroundWhiteValueText));
      expect(painter.strokeWidth, closeTo(kTgOutlineStrokeWidthSelected, 1e-9));
    });

    testWidgets('idle stroke honors the density floor (dpr 4 -> 0.5dp)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        devicePixelRatio: 4.0,
        child: const TgOutlineContainer(
          label: 'Label',
          child: SizedBox(height: 48),
        ),
      ));
      expect(_painter(tester).strokeWidth, 0.5);
    });

    testWidgets('error blends both paints to text_RedBold (OTC:126, 128)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const TgOutlineContainer(
          label: 'Label',
          error: true,
          child: SizedBox(height: 48),
        ),
      ));
      final TgOutlineContainerPainter painter = _painter(tester);
      final Color red = _day.color(TelegramColorKey.text_RedBold);
      expect(painter.outlineColor, red);
      expect(painter.labelColor, red);
    });

    testWidgets('a TelegramResources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color strokeOverride = Color(0xFF123456);
      const Color labelOverride = Color(0xFF654321);
      await tester.pumpWidget(_host(
        child: Builder(builder: (BuildContext context) {
          return TgOutlineContainer(
            label: 'Label',
            resources: ResourcesOverride(
              parent: TelegramTheme.resources(context),
              overrides: const <int, Color>{
                TelegramColorKey.windowBackgroundWhiteInputField:
                    strokeOverride,
                TelegramColorKey.windowBackgroundWhiteHintText: labelOverride,
              },
            ),
            child: const SizedBox(height: 48),
          );
        }),
      ));
      expect(_painter(tester).outlineColor, strokeOverride);
      expect(_painter(tester).labelColor, labelOverride);

      // And back without the override: ambient theme resolution.
      await tester.pumpWidget(_host(
        child: const TgOutlineContainer(
          label: 'Label',
          child: SizedBox(height: 48),
        ),
      ));
      expect(
          _painter(tester).outlineColor,
          _day.color(TelegramColorKey.windowBackgroundWhiteInputField));
      expect(_painter(tester).labelColor,
          _day.color(TelegramColorKey.windowBackgroundWhiteHintText));
    });
  });

  group('springs (OTC:173-184)', () {
    testWidgets('selection runs the 500-stiffness critically damped spring',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const TgOutlineContainer(
          label: 'Label',
          child: SizedBox(height: 48),
        ),
      ));
      await tester.pumpWidget(_host(
        child: const TgOutlineContainer(
          label: 'Label',
          selected: true,
          child: SizedBox(height: 48),
        ),
      ));
      await tester.pump(); // Simulation start frame.
      await tester.pump(const Duration(milliseconds: 100));
      final double expected = _criticalSpring(0.100);
      expect(_state(tester).debugSelectionProgress, closeTo(expected, 1e-6));
      // Stroke width lerps idle(2 @dpr1) -> 1.6667 with the progress
      // (OTC:30).
      expect(
        _painter(tester).strokeWidth,
        closeTo(2.0 + (kTgOutlineStrokeWidthSelected - 2.0) * expected, 1e-6),
      );
      // No bounce: never exceeds the target.
      await tester.pump(const Duration(milliseconds: 100));
      expect(_state(tester).debugSelectionProgress,
          lessThanOrEqualTo(1.0 + 1e-9));
      await tester.pumpAndSettle();
      expect(_state(tester).debugSelectionProgress, closeTo(1.0, 1e-3));
      expect(_painter(tester).strokeWidth,
          closeTo(kTgOutlineStrokeWidthSelected, 1e-2));
    });

    testWidgets('floating defaults to selected; explicit value decouples it',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const TgOutlineContainer(
          label: 'Label',
          selected: true,
          floating: false,
          child: SizedBox(height: 48),
        ),
      ));
      expect(_state(tester).debugSelectionProgress, 1.0);
      expect(_state(tester).debugTitleProgress, 0.0);
      // Dropping the explicit value re-couples it to `selected`.
      await tester.pumpWidget(_host(
        child: const TgOutlineContainer(
          label: 'Label',
          selected: true,
          child: SizedBox(height: 48),
        ),
      ));
      await tester.pumpAndSettle();
      expect(_state(tester).debugTitleProgress, closeTo(1.0, 1e-3));
    });

    testWidgets('error spring drives the color blend',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const TgOutlineContainer(
          label: 'Label',
          child: SizedBox(height: 48),
        ),
      ));
      await tester.pumpWidget(_host(
        child: const TgOutlineContainer(
          label: 'Label',
          error: true,
          child: SizedBox(height: 48),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final double progress = _state(tester).debugErrorProgress;
      expect(progress, closeTo(_criticalSpring(0.100), 1e-6));
      expect(
        _painter(tester).outlineColor,
        Color.lerp(
          _day.color(TelegramColorKey.windowBackgroundWhiteInputField),
          _day.color(TelegramColorKey.text_RedBold),
          progress,
        ),
      );
      await tester.pumpAndSettle();
      expect(_state(tester).debugErrorProgress, closeTo(1.0, 1e-3));
    });
  });

  group('painter geometry (onDraw, OTC:192-228)', () {
    const Size box = Size(320, 54);

    TgOutlineContainerPainter painterAt({
      required double titleProgress,
      bool useCenter = true,
      double leftPadding = 0.0,
      double strokeWidth = 1.0,
      String label = 'Label',
    }) {
      return TgOutlineContainerPainter(
        label: label,
        labelColor: const Color(0xFF000000),
        outlineColor: const Color(0xFF000000),
        strokeWidth: strokeWidth,
        titleProgress: titleProgress,
        useCenter: useCenter,
        leftPadding: leftPadding,
      );
    }

    test('label rests centered: baseline h/2 + 8, full scale (OTC:198-204)',
        () {
      final TgOutlineContainerPainter painter = painterAt(titleProgress: 0.0);
      final ({double baselineY, double x, double scaleX}) g =
          painter.labelGeometry(box);
      expect(g.baselineY, box.height / 2 + kTgOutlineLabelTextSize / 2);
      expect(g.scaleX, 1.0);
      expect(g.x, kTgOutlinePaddingLeft);
    });

    test('floated label: baseline topY = 6 + 16/2 - 1.75, scale 0.75 '
        '(OTC:196-204)', () {
      final TgOutlineContainerPainter painter = painterAt(titleProgress: 1.0);
      final ({double baselineY, double x, double scaleX}) g =
          painter.labelGeometry(box);
      expect(g.baselineY, closeTo(6.0 + 8.0 - 1.75, 1e-9));
      expect(g.scaleX, kTgOutlineLabelFloatedScale);
      expect(g.x, kTgOutlinePaddingLeft);
    });

    test('leftPadding shifts the resting label and scales away (OTC:201)', () {
      final ({double baselineY, double x, double scaleX}) rest =
          painterAt(titleProgress: 0.0, leftPadding: 40.0).labelGeometry(box);
      expect(rest.x, kTgOutlinePaddingLeft + 40.0);
      final ({double baselineY, double x, double scaleX}) floated =
          painterAt(titleProgress: 1.0, leftPadding: 40.0).labelGeometry(box);
      expect(floated.x, kTgOutlinePaddingLeft);
    });

    test('useCenter false pins the label floated regardless of progress '
        '(OTC:199-204)', () {
      final ({double baselineY, double x, double scaleX}) g =
          painterAt(titleProgress: 0.0, useCenter: false).labelGeometry(box);
      expect(g.baselineY, closeTo(6.0 + 8.0 - 1.75, 1e-9));
      expect(g.scaleX, kTgOutlineLabelFloatedScale);
    });

    test('floated: the top stroke is interrupted by the label gap '
        '(OTC:214-222)', () {
      final TgOutlineContainerPainter painter = painterAt(
          titleProgress: 1.0, strokeWidth: kTgOutlineStrokeWidthSelected);
      final ({
        double lineY,
        double leftStart,
        double leftEnd,
        double rightStart,
        double rightEnd,
      }) runs = painter.topStroke(box);
      final double scaledLabel =
          _labelWidth('Label') * kTgOutlineLabelFloatedScale;
      // lineY = paddingTop + stroke (OTC:214).
      expect(runs.lineY,
          kTgOutlineTopPadding + kTgOutlineStrokeWidthSelected);
      // Left run collapses to a point at dp(10) (OTC:222).
      expect(runs.leftStart, 10.0);
      expect(runs.leftEnd, closeTo(10.0, 1e-9));
      // Right run starts past the label: left + textWidth + dp(10)
      // (OTC:217, 219) -> the gap is open.
      expect(runs.rightStart, closeTo(10.0 + scaledLabel + 10.0, 1e-6));
      expect(runs.rightStart, greaterThan(runs.leftEnd));
      // ... and ends at width - stroke - dp(6) (OTC:215).
      expect(runs.rightEnd,
          box.width - kTgOutlineStrokeWidthSelected - kTgOutlineLineRightInset);
    });

    test('centered: the two runs overlap — no gap (OTC:219, 222)', () {
      final ({
        double lineY,
        double leftStart,
        double leftEnd,
        double rightStart,
        double rightEnd,
      }) runs = painterAt(titleProgress: 0.0).topStroke(box);
      final double labelWidth = _labelWidth('Label');
      // At titleProgress 0 (scale 1): left run reaches textWidth/2 + 4dp
      // past dp(10); the right run starts textWidth/2 past dp(10) — they
      // overlap by the 4dp text gap.
      expect(runs.leftEnd, closeTo(10.0 + labelWidth / 2 + 4.0, 1e-6));
      expect(runs.rightStart, closeTo(10.0 + labelWidth / 2, 1e-6));
      expect(runs.rightStart, lessThanOrEqualTo(runs.leftEnd));
    });

    test('useCenter false keeps the gap fully open at progress 0 '
        '(OTC:219, 222)', () {
      final ({
        double lineY,
        double leftStart,
        double leftEnd,
        double rightStart,
        double rightEnd,
      }) runs =
          painterAt(titleProgress: 0.0, useCenter: false).topStroke(box);
      expect(runs.leftEnd, closeTo(runs.leftStart, 1e-9));
      expect(runs.rightStart, greaterThan(runs.leftEnd));
    });
  });

  group('layout', () {
    testWidgets('the child is padded 6dp from the top (OTC:87)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const TgOutlineContainer(
          label: 'Label',
          child: SizedBox(height: 48),
        ),
      ));
      final Padding padding = tester.widget<Padding>(find
          .descendant(
              of: find.byType(TgOutlineContainer),
              matching: find.byType(Padding))
          .first);
      expect(padding.padding,
          const EdgeInsets.only(top: kTgOutlineTopPadding));
      // 48dp child + 6dp top reserve.
      expect(
          tester.getSize(find.byType(TgOutlineContainer)), const Size(320, 54));
    });
  });
}
