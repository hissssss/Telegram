// Tests for lib/src/components/buttons/glass_icon_button.dart
// (ARCHITECTURE.md section 6, row "GlassIconButton"), golden-free:
//
//  * geometry: 48dp box, 6dp glass padding, 18dp radius = (48 - 12)/2
//    (EmojiView.java:2679, 2927-2928) and the emojiViewButton preset wiring
//    (BlurredBackgroundProviderImpl.java:51-64);
//  * tap dispatch and disabled state;
//  * press feedback: 0.9 scale over 80ms, overshoot release over 350ms
//    (ScaleStateListAnimator.java:11-34);
//  * icon tint glass_defaultIcon @ 0.6 alpha (EmojiView.java:2651,
//    10135-10139) and semantics (setContentDescription analog,
//    EmojiView.java:2653).

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/buttons/glass_icon_button.dart';
import 'package:telegram_ui/src/glass/backdrop_scope.dart';
import 'package:telegram_ui/src/glass/geometry.dart';
import 'package:telegram_ui/src/glass/glass_panel.dart';
import 'package:telegram_ui/src/glass/presets.dart';
import 'package:telegram_ui/src/glass/runtime_probe.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

/// Settings whose probe never resolves: liquid requests stay conservatively
/// frosted — the deterministic flutter_tester path (no ImageFilter.shader).
GlassSettings _manualSettings() =>
    GlassSettings(probe: () => Completer<GlassCapability>().future);

Widget _host(Widget child) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: GlassBackdropScope(
        settings: _manualSettings(),
        probeOnMount: false,
        child: Center(child: child),
      ),
    ),
  );
}

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      // EmojiView.java:2679, 2776: createFrame(48, 48, ...).
      expect(kGlassIconButtonSize, 48.0);
      // EmojiView.java:2927-2928: setRadius(dp(18)).setPadding(dp(6)).
      expect(kGlassIconButtonGlassPadding, 6.0);
      expect(kGlassIconButtonRadius, 18.0);
      expect(kGlassIconButtonRadius,
          (kGlassIconButtonSize - 2 * kGlassIconButtonGlassPadding) / 2);
      // EmojiView.java:2651: getGlassIconColor(0.6f).
      expect(kGlassIconButtonIconAlpha, 0.6);
      // ScaleStateListAnimator.java:12, 25, 32-33.
      expect(kGlassIconButtonPressScale, 0.1);
      expect(kGlassIconButtonReleaseTension, 1.5);
      expect(kGlassIconButtonPressDuration, const Duration(milliseconds: 80));
      expect(kGlassIconButtonReleaseDuration, const Duration(milliseconds: 350));
    });
  });

  group('geometry and preset wiring', () {
    testWidgets('48dp box, emojiViewButton preset, 18dp radius, 6dp padding',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        GlassIconButton(icon: const SizedBox(), onPressed: () {}),
      ));
      expect(tester.getSize(find.byType(GlassIconButton)), const Size(48, 48));

      final GlassPanel panel = tester.widget(find.byType(GlassPanel));
      expect(panel.preset, GlassPresets.emojiViewButton);
      expect(panel.borderRadius, const GlassRadii.all(kGlassIconButtonRadius));
      expect(panel.padding, kGlassIconButtonGlassPadding);
      expect(panel.tier, isNull); // scope-resolved, no pin.
      expect(tester.getSize(find.byType(GlassPanel)), const Size(48, 48));
    });

    testWidgets('custom size keeps the circle: radius = (size - 2*padding)/2',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        GlassIconButton(icon: const SizedBox(), onPressed: () {}, size: 60),
      ));
      expect(tester.getSize(find.byType(GlassIconButton)), const Size(60, 60));
      final GlassPanel panel = tester.widget(find.byType(GlassPanel));
      expect(panel.borderRadius, const GlassRadii.all((60 - 2 * 6) / 2));
      expect(tester.widget<GlassIconButton>(find.byType(GlassIconButton)).glassRadius, 24.0);
    });
  });

  group('tap', () {
    testWidgets('fires onPressed once per tap', (WidgetTester tester) async {
      int presses = 0;
      await tester.pumpWidget(_host(
        GlassIconButton(icon: const SizedBox(), onPressed: () => presses++),
      ));
      await tester.tap(find.byType(GlassIconButton));
      await tester.pumpAndSettle();
      expect(presses, 1);
      await tester.tap(find.byType(GlassIconButton));
      await tester.pumpAndSettle();
      expect(presses, 2);
    });

    testWidgets('null onPressed: inert and scale stays resting',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const GlassIconButton(icon: SizedBox()),
      ));
      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(find.byType(GlassIconButton)));
      await tester.pump(kGlassIconButtonPressDuration);
      final GlassIconButtonState state =
          tester.state(find.byType(GlassIconButton));
      expect(state.debugPressScale, 1.0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(state.debugPressScale, 1.0);
    });
  });

  group('press feedback (ScaleStateListAnimator)', () {
    testWidgets('press-in reaches 0.9 in 80ms; release overshoots past 1 and settles',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        GlassIconButton(icon: const SizedBox(), onPressed: () {}),
      ));
      final GlassIconButtonState state = tester.state(find.byType(GlassIconButton));
      expect(state.debugPressScale, 1.0);

      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(find.byType(GlassIconButton)));
      await tester.pump(); // start the press animation
      await tester.pump(kGlassIconButtonPressDuration);
      // pressed scale = 1 - 0.1 (ScaleStateListAnimator.java:12, 22-25).
      expect(state.debugPressScale, closeTo(0.9, 1e-9));

      await gesture.up();
      await tester.pump(); // start the release animation
      // OvershootInterpolator(1.5) exceeds 1 for t > 0.4 of the 350ms run
      // (ScaleStateListAnimator.java:32): the scale swings above 1.0.
      await tester.pump(const Duration(milliseconds: 245));
      expect(state.debugPressScale, greaterThan(1.0));
      // And settles exactly at rest (f(1) = 1).
      await tester.pump(const Duration(milliseconds: 105));
      expect(state.debugPressScale, closeTo(1.0, 1e-9));
      await tester.pumpAndSettle();
      expect(state.debugPressScale, 1.0);
    });
  });

  group('icon tint', () {
    testWidgets('defaults to glass_defaultIcon with alpha replaced by 0.6',
        (WidgetTester tester) async {
      Color? seen;
      await tester.pumpWidget(_host(
        GlassIconButton(
          onPressed: () {},
          icon: Builder(builder: (BuildContext context) {
            seen = IconTheme.of(context).color;
            return const SizedBox();
          }),
        ),
      ));
      // setAlphaComponent(glass_defaultIcon, (int) (255 * 0.6f))
      // (EmojiView.java:10136-10138): alpha replaced, not multiplied.
      final Color expected = _dayTheme
          .color(TelegramColorKey.glass_defaultIcon)
          .withAlpha((255 * 0.6).toInt());
      expect(seen, expected);
    });

    testWidgets('iconColor override wins', (WidgetTester tester) async {
      Color? seen;
      await tester.pumpWidget(_host(
        GlassIconButton(
          onPressed: () {},
          iconColor: const Color(0xFFABCDEF),
          icon: Builder(builder: (BuildContext context) {
            seen = IconTheme.of(context).color;
            return const SizedBox();
          }),
        ),
      ));
      expect(seen, const Color(0xFFABCDEF));
    });
  });

  group('semantics', () {
    testWidgets('button node with tooltip and tap action', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(
        GlassIconButton(
          icon: const SizedBox(),
          onPressed: () {},
          tooltip: 'Backspace',
        ),
      ));
      final SemanticsNode node = tester.getSemantics(find.byType(GlassIconButton));
      final SemanticsData data = node.getSemanticsData();
      expect(data.tooltip, 'Backspace');
      expect(data.flagsCollection.isButton, isTrue);
      // hasEnabledState + isEnabled: the tristate resolves to true.
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('disabled button reports enabled=false', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(
        const GlassIconButton(icon: SizedBox(), tooltip: 'Backspace'),
      ));
      final SemanticsData data =
          tester.getSemantics(find.byType(GlassIconButton)).getSemanticsData();
      // hasEnabledState + !isEnabled: the tristate resolves to false.
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      handle.dispose();
    });
  });
}
