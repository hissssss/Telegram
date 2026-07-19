// Tests for lib/src/progress/tg_linear_progress.dart (spec_primitives.md
// §4.3), golden-free:
//
//  * radius = height/2 and the width·progress fill
//    (LineProgressView.java:113-121);
//  * 300ms decelerate ease, forward-only animated sets, snap sets
//    (LineProgressView.java:57-70, 88-103);
//  * completion fade over 200ms and the track-only-while-p<1 rule
//    (LineProgressView.java:71-77, 110);
//  * dialog color keys `dialogLineProgress` / `dialogLineProgressBackground`
//    (AlertDialog.java:863-864) with a resources override (both directions).

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/progress/tg_linear_progress.dart';
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
      child: Center(child: SizedBox(width: 200.0, child: child)),
    ),
  );
}

TgLinearProgressPainter _painterOf(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(TgLinearProgress),
      matching: find.byType(CustomPaint),
    ),
  );
  return paint.painter! as TgLinearProgressPainter;
}

void main() {
  group('constants', () {
    test('4dp bar, 300ms ease, 200ms fade', () {
      expect(kTgLinearProgressHeight, 4.0); // AlertDialog.java:866
      expect(kTgLinearProgressProgressTimeMs, 300.0); // LineProgressView.java:61
      expect(kTgLinearProgressFadeTimeMs, 200.0); // LineProgressView.java:72
    });
  });

  group('TgLinearProgressAnimation (LineProgressView.java:52-103)', () {
    test('unanimated set snaps', () {
      final TgLinearProgressAnimation anim = TgLinearProgressAnimation()
        ..setProgress(0.4, animated: false);
      expect(anim.animatedProgressValue, 0.4);
      expect(anim.isAnimating, isFalse);
    });

    test('animated set eases over 300ms decelerate', () {
      final TgLinearProgressAnimation anim = TgLinearProgressAnimation()
        ..setProgress(0.6);
      expect(anim.isAnimating, isTrue);
      anim.update(150.0);
      // decelerate(0.5) = 0.75 → 0.6·0.75 = 0.45.
      expect(anim.animatedProgressValue, closeTo(0.45, 1e-9));
      anim.update(150.0);
      expect(anim.animatedProgressValue, 0.6);
      expect(anim.isAnimating, isFalse);
    });

    test('animated set to a LOWER value never eases — the Java '
        '`progressDiff > 0` quirk (LineProgressView.java:59)', () {
      final TgLinearProgressAnimation anim = TgLinearProgressAnimation()
        ..setProgress(0.6, animated: false)
        ..setProgress(0.3);
      expect(anim.isAnimating, isFalse);
      anim.update(300.0);
      expect(anim.animatedProgressValue, 0.6); // unchanged
      // Unanimated backward set snaps.
      anim.setProgress(0.3, animated: false);
      expect(anim.animatedProgressValue, 0.3);
    });

    test('completion: snap to 1, then the whole bar fades over 200ms '
        '(LineProgressView.java:71-77)', () {
      final TgLinearProgressAnimation anim = TgLinearProgressAnimation()
        ..setProgress(1.0);
      anim.update(150.0);
      expect(anim.animatedProgressValue, closeTo(0.75, 1e-9));
      expect(anim.animatedAlphaValue, 1.0); // fade waits for exactly 1
      anim.update(150.0);
      expect(anim.animatedProgressValue, 1.0);
      // The same update starts depleting alpha: 1 − 150/200.
      expect(anim.animatedAlphaValue, closeTo(0.25, 1e-9));
      anim.update(60.0);
      expect(anim.animatedAlphaValue, 0.0);
      expect(anim.isAnimating, isFalse);
    });

    test('any progress != 1 restores alpha (LineProgressView.java:95-97)',
        () {
      final TgLinearProgressAnimation anim = TgLinearProgressAnimation()
        ..setProgress(1.0, animated: false);
      anim.update(200.0);
      expect(anim.animatedAlphaValue, 0.0);
      anim.setProgress(0.5, animated: false);
      expect(anim.animatedAlphaValue, 1.0);
    });
  });

  group('TgLinearProgressPainter (LineProgressView.java:109-136)', () {
    test('radius = height/2; fill spans width·progress', () {
      final TgLinearProgressPainter painter = TgLinearProgressPainter(
        progress: 0.5,
        color: const Color(0xFF527DA3),
        backColor: const Color(0xFFDBDBDB),
      );
      const Size size = Size(200.0, 4.0);
      final RRect track = painter.trackRRectFor(size);
      expect(track.outerRect, const Rect.fromLTRB(0.0, 0.0, 200.0, 4.0));
      expect(track.tlRadius, const Radius.circular(2.0));
      final RRect fill = painter.fillRRectFor(size);
      expect(fill.outerRect, const Rect.fromLTRB(0.0, 0.0, 100.0, 4.0));
      expect(fill.tlRadius, const Radius.circular(2.0));
      // A taller bar keeps radius = h/2.
      expect(
        painter.trackRRectFor(const Size(200.0, 6.0)).tlRadius,
        const Radius.circular(3.0),
      );
    });

    test('track only while progress < 1 and a backColor exists '
        '(LineProgressView.java:110)', () {
      TgLinearProgressPainter make({
        double progress = 0.5,
        Color? backColor = const Color(0xFFDBDBDB),
      }) {
        return TgLinearProgressPainter(
          progress: progress,
          color: const Color(0xFF527DA3),
          backColor: backColor,
        );
      }

      expect(make().paintsTrack, isTrue);
      expect(make(progress: 1.0).paintsTrack, isFalse);
      expect(make(backColor: null).paintsTrack, isFalse);
    });

    test('shouldRepaint on progress/alpha/color change, false when identical',
        () {
      TgLinearProgressPainter make({
        double progress = 0.5,
        double alpha = 1.0,
        Color color = const Color(0xFF527DA3),
        Color? backColor = const Color(0xFFDBDBDB),
      }) {
        return TgLinearProgressPainter(
          progress: progress,
          color: color,
          backColor: backColor,
          alpha: alpha,
        );
      }

      final TgLinearProgressPainter base = make();
      expect(make().shouldRepaint(base), isFalse);
      expect(make(progress: 0.75).shouldRepaint(base), isTrue);
      expect(make(alpha: 0.25).shouldRepaint(base), isTrue);
      expect(
        make(color: const Color(0xFF229AF0)).shouldRepaint(base),
        isTrue,
      );
      expect(make(backColor: null).shouldRepaint(base), isTrue);
    });

    test('paints without error at partial, full and faded states', () {
      for (final TgLinearProgressPainter painter in <TgLinearProgressPainter>[
        TgLinearProgressPainter(
          progress: 0.5,
          color: const Color(0xFF527DA3),
          backColor: const Color(0xFFDBDBDB),
        ),
        TgLinearProgressPainter(
          progress: 1.0,
          color: const Color(0xFF527DA3),
          backColor: const Color(0xFFDBDBDB),
          alpha: 0.25,
        ),
        TgLinearProgressPainter(
          progress: 0.0,
          color: const Color(0xFF527DA3),
        ),
      ]) {
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final Canvas canvas = Canvas(recorder);
        painter.paint(canvas, const Size(200.0, 4.0));
        recorder.endRecording().dispose();
      }
    });
  });

  group('TgLinearProgress widget', () {
    testWidgets('fills the parent width at 4dp (MATCH_PARENT × 4, '
        'AlertDialog.java:866); height override flows',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgLinearProgress(progress: 0.3)));
      expect(
        tester.getSize(find.byType(TgLinearProgress)),
        const Size(200.0, 4.0),
      );
      await tester.pumpWidget(_host(
        const TgLinearProgress(progress: 0.3, height: 6.0),
      ));
      expect(tester.getSize(find.byType(TgLinearProgress)).height, 6.0);
    });

    testWidgets('dialog recipe keys resolve via the theme, and a resources '
        'override flips them (both directions)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgLinearProgress(progress: 0.3)));
      TgLinearProgressPainter painter = _painterOf(tester);
      expect(
        painter.color,
        _dayTheme.color(TelegramColorKey.dialogLineProgress),
      );
      expect(
        painter.backColor,
        _dayTheme.color(TelegramColorKey.dialogLineProgressBackground),
      );

      const Color fill = Color(0xFF112233);
      const Color track = Color(0xFF445566);
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return TgLinearProgress(
          progress: 0.3,
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.dialogLineProgress: fill,
              TelegramColorKey.dialogLineProgressBackground: track,
            },
          ),
        );
      })));
      painter = _painterOf(tester);
      expect(painter.color, fill);
      expect(painter.backColor, track);
    });

    testWidgets('raw color overrides and a null backColorKey',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgLinearProgress(
        progress: 0.3,
        progressColor: Color(0xFF111111),
        backColor: Color(0xFF222222),
      )));
      TgLinearProgressPainter painter = _painterOf(tester);
      expect(painter.color, const Color(0xFF111111));
      expect(painter.backColor, const Color(0xFF222222));

      await tester.pumpWidget(_host(const TgLinearProgress(
        progress: 0.3,
        backColorKey: null,
      )));
      painter = _painterOf(tester);
      expect(painter.backColor, isNull);
      expect(painter.paintsTrack, isFalse);
    });

    testWidgets('the first build snaps; increases ease over 300ms',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgLinearProgress(progress: 0.3)));
      expect(_painterOf(tester).progress, 0.3); // no start-from-zero sweep
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(_host(const TgLinearProgress(progress: 0.9)));
      expect(_painterOf(tester).progress, 0.3); // eases, not snaps
      await tester.pump(); // first tick anchors the clock
      await tester.pump(const Duration(milliseconds: 150));
      // 0.3 + 0.6·decelerate(0.5) = 0.3 + 0.45.
      expect(_painterOf(tester).progress, closeTo(0.75, 1e-9));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_painterOf(tester).progress, 0.9);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse); // ticker stopped
    });

    testWidgets('unanimated updates snap (animated: false)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgLinearProgress(progress: 0.2)));
      await tester.pumpWidget(_host(
        const TgLinearProgress(progress: 0.8, animated: false),
      ));
      expect(_painterOf(tester).progress, 0.8);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('completion fades the bar out and stops ticking',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgLinearProgress(progress: 0.5)));
      await tester.pumpWidget(_host(const TgLinearProgress(progress: 1.0)));
      await tester.pump(); // first tick anchors the clock
      await tester.pump(const Duration(milliseconds: 150));
      expect(_painterOf(tester).progress, closeTo(0.875, 1e-9));
      expect(_painterOf(tester).alpha, 1.0);
      await tester.pump(const Duration(milliseconds: 150));
      expect(_painterOf(tester).progress, 1.0);
      expect(_painterOf(tester).alpha, closeTo(0.25, 1e-9));
      expect(_painterOf(tester).paintsTrack, isFalse); // p == 1 hides track
      await tester.pump(const Duration(milliseconds: 100));
      expect(_painterOf(tester).alpha, 0.0);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposes its ticker cleanly mid-animation',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgLinearProgress(progress: 0.1)));
      await tester.pumpWidget(_host(const TgLinearProgress(progress: 0.9)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  });
}
