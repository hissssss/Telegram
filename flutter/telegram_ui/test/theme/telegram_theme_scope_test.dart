// Ring-1 theme-scope tests (ARCHITECTURE.md sections 4.2 and 7):
// per-key rebuild granularity of the TelegramTheme InheritedModel (the
// marquee test: a widget depending on key A must NOT rebuild when only key B
// changes), TelegramResourcesScope override precedence, the Material
// ThemeExtension fallback path, and TelegramResources.isDark defaults
// (Theme.ResourcesProvider analog, Theme.java:2949).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/color_math.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_resources.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_fallbacks.g.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared mutable build counter (a const widget cannot hold a mutable int,
/// but it can hold a final reference to one).
class _BuildCounter {
  int count = 0;
}

/// Rebuild probe depending on a single color key via [TelegramTheme.colorOf].
class _ColorProbe extends StatelessWidget {
  const _ColorProbe({
    super.key,
    required this.colorKey,
    required this.counter,
  });

  final int colorKey;
  final _BuildCounter counter;

  @override
  Widget build(BuildContext context) {
    counter.count++;
    return ColoredBox(color: TelegramTheme.colorOf(context, colorKey));
  }
}

/// Rebuild probe depending on the whole theme via [TelegramTheme.of].
class _ThemeProbe extends StatelessWidget {
  const _ThemeProbe({required this.counter});

  final _BuildCounter counter;

  @override
  Widget build(BuildContext context) {
    counter.count++;
    return ColoredBox(
      color: TelegramTheme.of(
        context,
      ).color(TelegramColorKey.windowBackgroundWhite),
    );
  }
}

/// TelegramResources test double: a mutable single-slot palette, so tests can
/// observe that ResourcesOverride resolves through its parent at lookup time
/// (live) rather than flattening at construction.
class _FakeResources extends TelegramResources {
  _FakeResources({required this.windowBackground, required this.everythingElse});

  Color windowBackground;
  Color everythingElse;

  @override
  Color getColor(int key) => key == TelegramColorKey.windowBackgroundWhite
      ? windowBackground
      : everythingElse;
}

void main() {
  group('TelegramTheme rebuild granularity', () {
    testWidgets(
      'widget depending on key A does not rebuild when only key B changes',
      (WidgetTester tester) async {
        final TelegramThemeData base = TelegramThemeData.day();
        final _BuildCounter actionBarBuilds = _BuildCounter();
        final _BuildCounter chatsBuilds = _BuildCounter();
        final _BuildCounter wholeThemeBuilds = _BuildCounter();

        // A single widget instance reused across pumps: Element.updateChild
        // short-circuits on an identical child widget, so only InheritedModel
        // dependency notifications can rebuild the probes below.
        final Widget probes = Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: <Widget>[
              _ColorProbe(
                key: const ValueKey<String>('actionBar'),
                colorKey: TelegramColorKey.actionBarDefaultTitle,
                counter: actionBarBuilds,
              ),
              _ColorProbe(
                key: const ValueKey<String>('chats'),
                colorKey: TelegramColorKey.chats_name,
                counter: chatsBuilds,
              ),
              _ThemeProbe(counter: wholeThemeBuilds),
            ],
          ),
        );

        await tester.pumpWidget(TelegramTheme(data: base, child: probes));
        expect(actionBarBuilds.count, 1);
        expect(chatsBuilds.count, 1);
        expect(wholeThemeBuilds.count, 1);

        // Same data instance: no notification at all.
        await tester.pumpWidget(TelegramTheme(data: base, child: probes));
        expect(actionBarBuilds.count, 1);
        expect(chatsBuilds.count, 1);
        expect(wholeThemeBuilds.count, 1);

        // Change ONLY chats_name (a chat-list key).
        const Color red = Color(0xFFFF0000);
        final TelegramThemeData changed = base.copyWith(
          overrides: const <int, Color>{TelegramColorKey.chats_name: red},
        );
        // Contract preconditions: distinct palettes get distinct revisions
        // (the revision short-circuit relies on it), and no other probe key
        // was disturbed.
        expect(changed.revision, isNot(base.revision));
        expect(changed.color(TelegramColorKey.chats_name), red);
        expect(
          changed.color(TelegramColorKey.actionBarDefaultTitle),
          base.color(TelegramColorKey.actionBarDefaultTitle),
        );
        expect(changed.brightness, base.brightness);

        await tester.pumpWidget(TelegramTheme(data: changed, child: probes));
        // The chats_name dependent rebuilt and sees the new color...
        expect(chatsBuilds.count, 2);
        expect(
          tester
              .widget<ColoredBox>(
                find.descendant(
                  of: find.byKey(const ValueKey<String>('chats')),
                  matching: find.byType(ColoredBox),
                ),
              )
              .color,
          red,
        );
        // ...the aspect-less of() dependent rebuilt...
        expect(wholeThemeBuilds.count, 2);
        // ...and the marquee assertion: the actionBarDefaultTitle dependent
        // did NOT rebuild.
        expect(actionBarBuilds.count, 1);

        // A brightness flip (day -> night) notifies every dependent, keyed
        // or not.
        await tester.pumpWidget(
          TelegramTheme(data: TelegramThemeData.night(), child: probes),
        );
        expect(actionBarBuilds.count, 2);
        expect(chatsBuilds.count, 3);
        expect(wholeThemeBuilds.count, 3);
      },
    );
  });

  group('TelegramResourcesScope', () {
    testWidgets('scope override wins over the ambient theme', (
      WidgetTester tester,
    ) async {
      final TelegramThemeData day = TelegramThemeData.day();
      const Color overrideColor = Color(0xFF123456);
      late Color viaResources;
      late Color viaColorOf;
      late Color untouchedKey;

      await tester.pumpWidget(
        TelegramTheme(
          data: day,
          child: Builder(
            builder: (BuildContext context) {
              return TelegramResourcesScope(
                resources: ResourcesOverride(
                  parent: TelegramTheme.resources(context),
                  overrides: const <int, Color>{
                    TelegramColorKey.chats_name: overrideColor,
                  },
                ),
                child: Builder(
                  builder: (BuildContext inner) {
                    final TelegramResources resources = TelegramTheme.resources(
                      inner,
                    );
                    viaResources = resources.getColor(
                      TelegramColorKey.chats_name,
                    );
                    viaColorOf = TelegramTheme.colorOf(
                      inner,
                      TelegramColorKey.chats_name,
                    );
                    untouchedKey = resources.getColor(
                      TelegramColorKey.actionBarDefaultTitle,
                    );
                    return const SizedBox();
                  },
                ),
              );
            },
          ),
        ),
      );

      expect(viaResources, overrideColor);
      expect(viaColorOf, overrideColor, reason: 'colorOf honors the scope');
      expect(
        untouchedKey,
        day.color(TelegramColorKey.actionBarDefaultTitle),
        reason: 'non-overridden keys resolve through the ambient theme',
      );
    });

    testWidgets('TelegramResourcesScope.of throws without a scope ancestor', (
      WidgetTester tester,
    ) async {
      late FlutterError error;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            try {
              TelegramResourcesScope.of(context);
            } on FlutterError catch (e) {
              error = e;
            }
            return const SizedBox();
          },
        ),
      );
      expect(error.message, contains('TelegramResourcesScope'));
    });
  });

  group('ResourcesOverride', () {
    test('consults the override map through the fallback table', () {
      // ChatActivity.ThemeDelegate.getColor step 2 (ChatActivity.java:43056):
      // overriding a fallback TARGET recolors keys that fall back onto it.
      // Precondition from the generated table:
      // graySectionText -> windowBackgroundWhiteGrayText2.
      expect(
        kFallbackKeys[TelegramColorKey.graySectionText],
        TelegramColorKey.windowBackgroundWhiteGrayText2,
      );

      const Color target = Color(0xFF654321);
      const Color parentColor = Color(0xFF111111);
      final ResourcesOverride override = ResourcesOverride(
        parent: _FakeResources(
          windowBackground: const Color(0xFFFFFFFF),
          everythingElse: parentColor,
        ),
        overrides: const <int, Color>{
          TelegramColorKey.windowBackgroundWhiteGrayText2: target,
        },
      );

      expect(
        override.getColor(TelegramColorKey.windowBackgroundWhiteGrayText2),
        target,
      );
      expect(
        override.getColor(TelegramColorKey.graySectionText),
        target,
        reason: 'fallback hop lands in the override map',
      );
      expect(
        override.getColor(TelegramColorKey.chats_name),
        parentColor,
        reason: 'misses delegate to the parent',
      );
    });

    test('fallback resolution stays live through the parent', () {
      final _FakeResources parent = _FakeResources(
        windowBackground: const Color(0xFFFFFFFF),
        everythingElse: const Color(0xFF101010),
      );
      final ResourcesOverride override = ResourcesOverride(
        parent: parent,
        overrides: const <int, Color>{
          TelegramColorKey.chats_name: Color(0xFFABCDEF),
        },
      );

      expect(
        override.getColor(TelegramColorKey.chat_inBubble),
        const Color(0xFF101010),
      );
      // Mutate the parent: the override is a live view, never a flattened
      // snapshot, so the change is observed immediately.
      parent.everythingElse = const Color(0xFF202020);
      expect(
        override.getColor(TelegramColorKey.chat_inBubble),
        const Color(0xFF202020),
      );
    });
  });

  group('ThemeExtension bridge', () {
    testWidgets('TelegramTheme.of falls back to the Material extension', (
      WidgetTester tester,
    ) async {
      final TelegramThemeData night = TelegramThemeData.night();
      late TelegramThemeData resolved;
      late Color background;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: <ThemeExtension<dynamic>>[
              TelegramThemeExtension(night),
            ],
          ),
          home: Builder(
            builder: (BuildContext context) {
              resolved = TelegramTheme.of(context);
              background = TelegramTheme.colorOf(
                context,
                TelegramColorKey.windowBackgroundWhite,
              );
              return const SizedBox();
            },
          ),
        ),
      );

      expect(resolved, night);
      expect(
        background,
        night.color(TelegramColorKey.windowBackgroundWhite),
      );
    });

    testWidgets('maybeOf returns null with no theme and no extension', (
      WidgetTester tester,
    ) async {
      TelegramThemeData? resolved = TelegramThemeData.day();
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            resolved = TelegramTheme.maybeOf(context);
            return const SizedBox();
          },
        ),
      );
      expect(resolved, isNull);
    });

    test('extension lerp delegates to TelegramThemeData.lerp', () {
      final TelegramThemeExtension day = TelegramThemeExtension(
        TelegramThemeData.day(),
      );
      final TelegramThemeExtension night = TelegramThemeExtension(
        TelegramThemeData.night(),
      );

      // Endpoints preserve the underlying data instances (and revisions).
      expect(identical(day.lerp(night, 0.0).data, day.data), isTrue);
      expect(identical(day.lerp(night, 1.0).data, night.data), isTrue);

      // Midpoint: per-key Color.lerp of the palettes (quantized to 8-bit
      // ARGB, as the Int32List-backed data model stores colors).
      final TelegramThemeExtension mid = day.lerp(night, 0.5);
      expect(
        mid.data.color(TelegramColorKey.chats_name),
        Color(
          Color.lerp(
            day.data.color(TelegramColorKey.chats_name),
            night.data.color(TelegramColorKey.chats_name),
            0.5,
          )!.toARGB32(),
        ),
      );

      // Non-matching other returns this.
      expect(identical(day.lerp(null, 0.5), day), isTrue);
    });
  });

  group('isDark', () {
    testWidgets('resources(context).isDark follows the theme brightness', (
      WidgetTester tester,
    ) async {
      Future<bool> isDarkUnder(TelegramThemeData data) async {
        late bool isDark;
        await tester.pumpWidget(
          TelegramTheme(
            data: data,
            child: Builder(
              builder: (BuildContext context) {
                isDark = TelegramTheme.resources(context).isDark;
                return const SizedBox();
              },
            ),
          ),
        );
        return isDark;
      }

      expect(await isDarkUnder(TelegramThemeData.day()), isFalse);
      expect(await isDarkUnder(TelegramThemeData.night()), isTrue);
    });

    test('TelegramResources default isDark uses perceived brightness', () {
      // ResourcesProvider.isDark analog: perceivedBrightness(
      // getColor(windowBackgroundWhite)) < 0.721
      // (BlurredBackgroundColorProviderThemed.java:34-37).
      TelegramResources withBackground(Color color) => _FakeResources(
            windowBackground: color,
            everythingElse: const Color(0xFF888888),
          );

      expect(withBackground(const Color(0xFFFFFFFF)).isDark, isFalse);
      // night.attheme windowBackgroundWhite (0xFF181F27).
      expect(withBackground(const Color(0xFF181F27)).isDark, isTrue);

      // Threshold agreement with the foundation predicate on both sides of
      // 0.721: pure gray 0xB8 (brightness ~0.722) vs 0xB7 (~0.718).
      expect(computePerceivedBrightness(0xFFB8B8B8), greaterThan(0.721));
      expect(withBackground(const Color(0xFFB8B8B8)).isDark, isFalse);
      expect(computePerceivedBrightness(0xFFB7B7B7), lessThan(0.721));
      expect(withBackground(const Color(0xFFB7B7B7)).isDark, isTrue);
    });

    test('ResourcesOverride reclassifies isDark via its override map', () {
      final ResourcesOverride darkened = ResourcesOverride(
        parent: _FakeResources(
          windowBackground: const Color(0xFFFFFFFF),
          everythingElse: const Color(0xFF888888),
        ),
        overrides: const <int, Color>{
          TelegramColorKey.windowBackgroundWhite: Color(0xFF181F27),
        },
      );
      expect(darkened.isDark, isTrue);
      expect(darkened.parent.isDark, isFalse);
    });
  });
}
