// Tests for lib/src/buttons/tg_fab.dart (PLAN_UIKIT.md S5), golden-free:
//
//  * constants vs FragmentFloatingButton.java (FFB) /
//    ScaleStateListAnimator.java (SSLA);
//  * geometry: 56dp default, 48dp compact (FFB:173, 181-192);
//  * key resolution: featuredStickers_addButton circle +
//    featuredStickers_addButtonPressed pressed + chats_actionIcon icon
//    (FFB:163-170) and the resources override in both directions;
//  * press scale 0.9/80ms + Overshoot(1.5)/350ms release (FFB:71,
//    SSLA:11-33) with the pressed fill blend;
//  * show/hide: 380ms EASE_OUT_QUINT alpha + scale + 40dp slide with the
//    0.99 clickability threshold (FFB:38-39, 125-126, 250-259);
//  * semantics (button role, enabled state, tooltip).

import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/buttons/tg_fab.dart';
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

BoxDecoration _decoration(WidgetTester tester) {
  final DecoratedBox box = tester.widget<DecoratedBox>(find.descendant(
    of: find.byType(TgFab),
    matching: find.byType(DecoratedBox),
  ));
  return box.decoration as BoxDecoration;
}

TgFabState _state(WidgetTester tester) => tester.state(find.byType(TgFab));

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kTgFabSize, 56.0); // FFB:188-192 (createDefaultLayoutParamsBig)
      expect(kTgFabSizeCompact, 48.0); // FFB:173 (SIZE = 48)
      // BoolAnimator(EASE_OUT_QUINT, 380) (FFB:38-39).
      expect(kTgFabVisibilityDuration, const Duration(milliseconds: 380));
      expect(kTgFabHideSlide, 40.0); // FFB:126
      expect(kTgFabHiddenScale, 0.4); // FFB:256-257
      expect(kTgFabClickableThreshold, 0.99); // FFB:125
      // ScaleStateListAnimator.apply(this) defaults (SSLA:11-12, 25, 33).
      expect(kTgFabPressScale, 0.1);
      expect(kTgFabReleaseTension, 1.5);
      expect(kTgFabPressDuration, const Duration(milliseconds: 80));
      expect(kTgFabReleaseDuration, const Duration(milliseconds: 350));
    });
  });

  group('geometry', () {
    testWidgets('56dp circle by default', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgFab(icon: const SizedBox(), onPressed: () {})));
      expect(tester.getSize(find.byType(TgFab)), const Size(56, 56));
      expect(_decoration(tester).shape, BoxShape.circle);
    });

    testWidgets('48dp compact size', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgFab(
        icon: const SizedBox(),
        onPressed: () {},
        size: kTgFabSizeCompact,
      )));
      expect(tester.getSize(find.byType(TgFab)), const Size(48, 48));
    });
  });

  group('key resolution', () {
    testWidgets('addButton fill and chats_actionIcon icon tint (FFB:163-170)',
        (WidgetTester tester) async {
      Color? seenIcon;
      await tester.pumpWidget(_host(TgFab(
        onPressed: () {},
        icon: Builder(builder: (BuildContext context) {
          seenIcon = IconTheme.of(context).color;
          return const SizedBox();
        }),
      )));
      expect(_decoration(tester).color,
          _dayTheme.color(TelegramColorKey.featuredStickers_addButton));
      expect(seenIcon, _dayTheme.color(TelegramColorKey.chats_actionIcon));
    });

    testWidgets('classic chats_action* keys can be substituted',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgFab(
        icon: const SizedBox(),
        onPressed: () {},
        backgroundColorKey: TelegramColorKey.chats_actionBackground,
        pressedColorKey: TelegramColorKey.chats_actionPressedBackground,
      )));
      expect(_decoration(tester).color,
          _dayTheme.color(TelegramColorKey.chats_actionBackground));
    });

    testWidgets('resources override wins over the ambient theme (both directions)',
        (WidgetTester tester) async {
      const Color override = Color(0xFF123456);
      // Direction 1: ambient theme.
      await tester.pumpWidget(_host(TgFab(icon: const SizedBox(), onPressed: () {})));
      expect(_decoration(tester).color,
          _dayTheme.color(TelegramColorKey.featuredStickers_addButton));
      // Direction 2: override flips the resolved color.
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return TgFab(
          icon: const SizedBox(),
          onPressed: () {},
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.featuredStickers_addButton: override,
            },
          ),
        );
      })));
      expect(_decoration(tester).color, override);
    });
  });

  group('press feedback (ScaleStateListAnimator defaults)', () {
    testWidgets('press-in reaches 0.9 in 80ms with the pressed fill; release overshoots',
        (WidgetTester tester) async {
      int presses = 0;
      await tester.pumpWidget(_host(TgFab(icon: const SizedBox(), onPressed: () => presses++)));
      final TgFabState state = _state(tester);
      expect(state.debugPressScale, 1.0);

      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(find.byType(TgFab)));
      await tester.pump(); // start the press animation
      await tester.pump(kTgFabPressDuration);
      expect(state.debugPressScale, closeTo(0.9, 1e-9));
      // Fully pressed: the fill is the pressed color
      // (createSimpleSelectorCircleDrawable, FFB:166-169).
      expect(_decoration(tester).color,
          _dayTheme.color(TelegramColorKey.featuredStickers_addButtonPressed));

      await gesture.up();
      await tester.pump(); // start the release animation
      await tester.pump(const Duration(milliseconds: 245));
      expect(state.debugPressScale, greaterThan(1.0));
      await tester.pump(const Duration(milliseconds: 105));
      expect(state.debugPressScale, closeTo(1.0, 1e-9));
      expect(presses, 1);
      // Released: back to the resting fill.
      expect(_decoration(tester).color,
          _dayTheme.color(TelegramColorKey.featuredStickers_addButton));
    });

    testWidgets('null onPressed: inert', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgFab(icon: SizedBox())));
      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(find.byType(TgFab)));
      await tester.pump(kTgFabPressDuration);
      expect(_state(tester).debugPressScale, 1.0);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('show/hide (BoolAnimator EASE_OUT_QUINT 380ms)', () {
    testWidgets('hiding animates alpha/scale/slide and blocks taps',
        (WidgetTester tester) async {
      int presses = 0;
      await tester.pumpWidget(_host(TgFab(icon: const SizedBox(), onPressed: () => presses++)));
      expect(_state(tester).debugVisibilityFactor, 1.0);

      await tester
          .pumpWidget(_host(TgFab(icon: const SizedBox(), onPressed: () => presses++, visible: false)));
      await tester.pump(); // first animation tick
      await tester.pump(const Duration(milliseconds: 190));
      final double mid = _state(tester).debugVisibilityFactor;
      expect(mid, greaterThan(0.0));
      expect(mid, lessThan(1.0));
      // Mid-flight the button is already unclickable (factor < 0.99, FFB:125).
      await tester.tap(find.byType(TgFab), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 190));
      expect(_state(tester).debugVisibilityFactor, 0.0);
      final Opacity opacity = tester.widget<Opacity>(find.descendant(
        of: find.byType(TgFab),
        matching: find.byType(Opacity),
      ));
      expect(opacity.opacity, 0.0); // setAlpha(f) (FFB:255)

      await tester.tap(find.byType(TgFab), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(presses, 0);
    });

    testWidgets('showing again restores clickability at factor 1',
        (WidgetTester tester) async {
      int presses = 0;
      Widget build(bool visible) =>
          _host(TgFab(icon: const SizedBox(), onPressed: () => presses++, visible: visible));
      await tester.pumpWidget(build(false));
      expect(_state(tester).debugVisibilityFactor, 0.0);

      await tester.pumpWidget(build(true));
      await tester.pump();
      await tester.pump(kTgFabVisibilityDuration);
      expect(_state(tester).debugVisibilityFactor, 1.0);

      await tester.tap(find.byType(TgFab));
      await tester.pumpAndSettle();
      expect(presses, 1);
    });
  });

  group('semantics', () {
    testWidgets('button node with tooltip and tap action', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(TgFab(
        icon: const SizedBox(),
        onPressed: () {},
        tooltip: 'New message',
      )));
      final SemanticsData data =
          tester.getSemantics(find.byType(TgFab)).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.tooltip, 'New message');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('hidden or callback-less: reports enabled=false',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
          _host(TgFab(icon: const SizedBox(), onPressed: () {}, visible: false)));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byType(TgFab)).getSemanticsData().flagsCollection.isEnabled,
        Tristate.isFalse,
      );

      await tester.pumpWidget(_host(const TgFab(icon: SizedBox())));
      expect(
        tester.getSemantics(find.byType(TgFab)).getSemanticsData().flagsCollection.isEnabled,
        Tristate.isFalse,
      );
      handle.dispose();
    });
  });
}
