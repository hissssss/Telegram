// Tests for lib/src/avatar/tg_avatar.dart (spec_primitives.md §3), golden-
// free:
//
//  * palette order + index math incl. Java truncating-remainder negatives
//    (AvatarDrawable.java:179-181, Theme.java:3539-3540);
//  * peer-color hue map boundary values (AvatarDrawable.java:166-177);
//  * initials extraction table — emoji, multi-word, empty-first-name
//    promotion, custom override (AvatarDrawable.java:455-458, 509-542);
//  * text canvas scale: 56dp avatar → 20.16dp effective
//    (AvatarDrawable.java:736-738);
//  * gradient stops resolving through theme keys and a resources override
//    (both directions).

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/avatar/tg_avatar.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_resources.dart';
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

TgAvatarPainter _painterOf(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(
    find
        .descendant(
          of: find.byType(TgAvatar),
          matching: find.byType(CustomPaint),
        )
        .first,
  );
  return paint.painter! as TgAvatarPainter;
}

/// Key-tagged fake palette: every key resolves to a distinct color.
class _FakeResources extends TelegramResources {
  const _FakeResources();

  @override
  Color getColor(int key) => Color(0xFF000000 | key);
}

/// A valid 1x1 transparent PNG (the classic `kTransparentImage` bytes).
final Uint8List _transparentPng = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

void main() {
  group('constants (AvatarDrawable.java)', () {
    test('18dp text designed for 50dp, 7 pairs, ZWNJ joiner', () {
      expect(kTgAvatarTextSize, 18.0); // AvatarDrawable.java:132
      expect(kTgAvatarBaseSize, 50.0); // AvatarDrawable.java:736
      expect(kTgAvatarColorCount, 7); // Theme.java:3539
      expect(kTgAvatarInitialsJoiner, '‌'); // AvatarDrawable.java:524
    });
  });

  group('TgAvatarColors palette order (Theme.java:3539-3540)', () {
    test('Red, Orange, Violet, Green, Cyan, Blue, Pink', () {
      expect(TgAvatarColors.backgroundKeys, const <int>[
        TelegramColorKey.avatar_backgroundRed,
        TelegramColorKey.avatar_backgroundOrange,
        TelegramColorKey.avatar_backgroundViolet,
        TelegramColorKey.avatar_backgroundGreen,
        TelegramColorKey.avatar_backgroundCyan,
        TelegramColorKey.avatar_backgroundBlue,
        TelegramColorKey.avatar_backgroundPink,
      ]);
      expect(TgAvatarColors.background2Keys, const <int>[
        TelegramColorKey.avatar_background2Red,
        TelegramColorKey.avatar_background2Orange,
        TelegramColorKey.avatar_background2Violet,
        TelegramColorKey.avatar_background2Green,
        TelegramColorKey.avatar_background2Cyan,
        TelegramColorKey.avatar_background2Blue,
        TelegramColorKey.avatar_background2Pink,
      ]);
      expect(TgAvatarColors.backgroundKeys, hasLength(kTgAvatarColorCount));
      expect(TgAvatarColors.background2Keys, hasLength(kTgAvatarColorCount));
    });

    test('defaults resolve to the ThemeColors.java:158-171 base values '
        'where the day palette does not restyle them', () {
      // Colors are never re-declared in components — the generated palette is
      // authoritative (API convention §2.4); spot-check two keys the day
      // theme leaves at their ThemeColors defaults.
      expect(
        _dayTheme.color(TelegramColorKey.avatar_backgroundRed),
        const Color(0xFFFF845E),
      );
      expect(
        _dayTheme.color(TelegramColorKey.avatar_background2Pink),
        const Color(0xFFD95574),
      );
    });
  });

  group('TgAvatarColors.indexFor (AvatarDrawable.java:179-181)', () {
    test('abs(id % 7) for non-negative ids', () {
      expect(TgAvatarColors.indexFor(0), 0);
      expect(TgAvatarColors.indexFor(1), 1);
      expect(TgAvatarColors.indexFor(6), 6);
      expect(TgAvatarColors.indexFor(7), 0);
      expect(TgAvatarColors.indexFor(13), 6);
      expect(TgAvatarColors.indexFor(10), 3);
    });

    test('negative ids use Java truncating-remainder semantics', () {
      // Java: -1 % 7 == -1 → abs 1 (Dart's Euclidean % would give 6).
      expect(TgAvatarColors.indexFor(-1), 1);
      expect(TgAvatarColors.indexFor(-8), 1);
      expect(TgAvatarColors.indexFor(-13), 6);
      expect(TgAvatarColors.indexFor(-7), 0);
      // -1001234567890 % 7 == -4 in Java (truncating), abs → 4.
      expect(TgAvatarColors.indexFor(-1001234567890), 4);
    });
  });

  group('TgAvatarColors hue map (AvatarDrawable.java:166-177)', () {
    test('boundary hues', () {
      // ≥345 or <29 → red.
      expect(TgAvatarColors.indexForHue(0), 0);
      expect(TgAvatarColors.indexForHue(28), 0);
      expect(TgAvatarColors.indexForHue(345), 0);
      expect(TgAvatarColors.indexForHue(359), 0);
      // <67 orange.
      expect(TgAvatarColors.indexForHue(29), 1);
      expect(TgAvatarColors.indexForHue(66), 1);
      // <140 green (index 3).
      expect(TgAvatarColors.indexForHue(67), 3);
      expect(TgAvatarColors.indexForHue(139), 3);
      // <199 cyan (index 4).
      expect(TgAvatarColors.indexForHue(140), 4);
      expect(TgAvatarColors.indexForHue(198), 4);
      // <234 blue (index 5).
      expect(TgAvatarColors.indexForHue(199), 5);
      expect(TgAvatarColors.indexForHue(233), 5);
      // <301 violet (index 2).
      expect(TgAvatarColors.indexForHue(234), 2);
      expect(TgAvatarColors.indexForHue(300), 2);
      // else pink.
      expect(TgAvatarColors.indexForHue(301), 6);
      expect(TgAvatarColors.indexForHue(344), 6);
    });

    test('peerColorIndex truncates the color hue like the Java (int) cast',
        () {
      expect(TgAvatarColors.peerColorIndex(const Color(0xFFFF0000)), 0);
      // 0xFFFF003C: hue 60·(6 − 60/255) ≈ 345.9 → 345 → red;
      // 0xFFFF0040: hue ≈ 344.9 → 344 → pink.
      expect(TgAvatarColors.peerColorIndex(const Color(0xFFFF003C)), 0);
      expect(TgAvatarColors.peerColorIndex(const Color(0xFFFF0040)), 6);
      // Green 120°, pure blue 240° → violet band (<301).
      expect(TgAvatarColors.peerColorIndex(const Color(0xFF00FF00)), 3);
      expect(TgAvatarColors.peerColorIndex(const Color(0xFF0000FF)), 2);
      // Cyan 180°.
      expect(TgAvatarColors.peerColorIndex(const Color(0xFF00FFFF)), 4);
    });
  });

  group('TgAvatarColors key/pair lookup', () {
    test('keysFor pairs top and bottom at the same index', () {
      expect(
        TgAvatarColors.keysFor(0),
        (
          top: TelegramColorKey.avatar_backgroundRed,
          bottom: TelegramColorKey.avatar_background2Red,
        ),
      );
      expect(
        TgAvatarColors.keysFor(5),
        (
          top: TelegramColorKey.avatar_backgroundBlue,
          bottom: TelegramColorKey.avatar_background2Blue,
        ),
      );
    });

    test('pairFor resolves through the given resources', () {
      const _FakeResources resources = _FakeResources();
      final ({Color top, Color bottom}) pair =
          TgAvatarColors.pairFor(1, resources);
      expect(
        pair.top,
        resources.getColor(TelegramColorKey.avatar_backgroundOrange),
      );
      expect(
        pair.bottom,
        resources.getColor(TelegramColorKey.avatar_background2Orange),
      );
    });
  });

  group('tgAvatarTakeFirstCharacter (AvatarDrawable.java:390-396)', () {
    test('plain text: one character; empty stays empty', () {
      expect(tgAvatarTakeFirstCharacter('John'), 'J');
      expect(tgAvatarTakeFirstCharacter(''), '');
    });

    test('a leading emoji is kept whole', () {
      expect(tgAvatarTakeFirstCharacter('🎉Party'), '🎉');
      expect(tgAvatarTakeFirstCharacter('🇺🇸 Team'), '🇺🇸');
      expect(tgAvatarTakeFirstCharacter('👨‍👩‍👧‍👦 fam'), '👨‍👩‍👧‍👦');
    });

    test('combining marks stay attached (grapheme divergence, documented)',
        () {
      expect(tgAvatarTakeFirstCharacter('étienne'), 'é');
    });
  });

  group('tgAvatarInitials (AvatarDrawable.java:509-542)', () {
    test('first + last name, ZWNJ-joined', () {
      expect(
        tgAvatarInitials(firstName: 'John', lastName: 'Smith'),
        'J‌S',
      );
    });

    test('single first name', () {
      expect(tgAvatarInitials(firstName: 'John'), 'J');
      expect(tgAvatarInitials(firstName: 'John '), 'J');
    });

    test('last word of a multi-word lastName (AvatarDrawable.java:518-522)',
        () {
      expect(
        tgAvatarInitials(firstName: 'John', lastName: 'van der Berg'),
        'J‌B',
      );
    });

    test('multi-word firstName falls back to its last word '
        '(spec_primitives.md §3.3; intent of AvatarDrawable.java:527-539)',
        () {
      expect(tgAvatarInitials(firstName: 'John Smith'), 'J‌S');
      expect(tgAvatarInitials(firstName: 'Anna Maria Luisa'), 'A‌L');
      // Trailing/double spaces: the last space must be followed by a
      // non-space (AvatarDrawable.java:530).
      expect(tgAvatarInitials(firstName: 'John  Smith'), 'J‌S');
    });

    test('empty firstName promotes lastName (AvatarDrawable.java:455-458)',
        () {
      expect(tgAvatarInitials(firstName: '', lastName: 'Smith'), 'S');
      expect(
        tgAvatarInitials(lastName: 'Anna Maria'),
        'A‌M', // promoted, then the multi-word fallback applies
      );
    });

    test('custom overrides everything (AvatarDrawable.java:511-512)', () {
      expect(
        tgAvatarInitials(
          firstName: 'John',
          lastName: 'Smith',
          custom: 'ᴠɪᴘ',
        ),
        'ᴠɪᴘ',
      );
    });

    test('emoji initials survive whole', () {
      expect(
        tgAvatarInitials(firstName: '🎉Party', lastName: 'Time'),
        '🎉‌T',
      );
    });

    test('nothing to extract → empty', () {
      expect(tgAvatarInitials(), '');
      expect(tgAvatarInitials(firstName: '', lastName: ''), '');
    });
  });

  group('TgAvatarPainter', () {
    test('text canvas scale: size / 50dp — 56dp → 20.16dp effective '
        '(AvatarDrawable.java:736-738)', () {
      final TgAvatarPainter painter = TgAvatarPainter(
        color: const Color(0xFFFF845E),
        color2: const Color(0xFFD45246),
      );
      expect(painter.textScaleFor(const Size(56.0, 56.0)), closeTo(1.12, 1e-9));
      expect(
        kTgAvatarTextSize * painter.textScaleFor(const Size(56.0, 56.0)),
        closeTo(20.16, 1e-9),
      );
      expect(painter.textScaleFor(const Size(50.0, 50.0)), 1.0);
    });

    test('shouldRepaint on any field change, false when identical', () {
      TgAvatarPainter make({
        Color color = const Color(0xFFFF845E),
        Color color2 = const Color(0xFFD45246),
        String initials = 'J‌S',
        double textSize = kTgAvatarTextSize,
        double roundRadius = 0.0,
      }) {
        return TgAvatarPainter(
          color: color,
          color2: color2,
          initials: initials,
          textSize: textSize,
          roundRadius: roundRadius,
        );
      }

      final TgAvatarPainter base = make();
      expect(make().shouldRepaint(base), isFalse);
      expect(
        make(color: const Color(0xFF5CAFFA)).shouldRepaint(base),
        isTrue,
      );
      expect(
        make(color2: const Color(0xFF408ACF)).shouldRepaint(base),
        isTrue,
      );
      expect(make(initials: 'A').shouldRepaint(base), isTrue);
      expect(make(textSize: 20.0).shouldRepaint(base), isTrue);
      expect(make(roundRadius: 8.0).shouldRepaint(base), isTrue);
    });

    test('paints circle, rounded rect, flat and initialed without error', () {
      for (final TgAvatarPainter painter in <TgAvatarPainter>[
        TgAvatarPainter(
          color: const Color(0xFFFF845E),
          color2: const Color(0xFFD45246),
          initials: 'J‌S',
        ),
        TgAvatarPainter(
          color: const Color(0xFFB8C2CC),
          color2: const Color(0xFFB8C2CC), // flat: no gradient branch
        ),
        TgAvatarPainter(
          color: const Color(0xFF69BDF9),
          color2: const Color(0xFF409FE1),
          roundRadius: 8.0,
        ),
      ]) {
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final Canvas canvas = Canvas(recorder);
        painter.paint(canvas, const Size(50.0, 50.0));
        recorder.endRecording().dispose();
      }
    });
  });

  group('TgAvatar widget', () {
    testWidgets('id selects the pair through the ambient theme '
        '(AvatarDrawable.java:445-446)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgAvatar(id: 0, size: 50.0)));
      TgAvatarPainter painter = _painterOf(tester);
      expect(
        painter.color,
        _dayTheme.color(TelegramColorKey.avatar_backgroundRed),
      );
      expect(
        painter.color2,
        _dayTheme.color(TelegramColorKey.avatar_background2Red),
      );

      await tester.pumpWidget(_host(const TgAvatar(id: 3, size: 50.0)));
      painter = _painterOf(tester);
      expect(
        painter.color,
        _dayTheme.color(TelegramColorKey.avatar_backgroundGreen),
      );
      expect(
        painter.color2,
        _dayTheme.color(TelegramColorKey.avatar_background2Green),
      );
    });

    testWidgets('resources override flips the gradient stops '
        '(both directions)', (WidgetTester tester) async {
      const Color top = Color(0xFF123456);
      const Color bottom = Color(0xFF654321);
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return TgAvatar(
          id: 0,
          size: 50.0,
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.avatar_backgroundRed: top,
              TelegramColorKey.avatar_background2Red: bottom,
            },
          ),
        );
      })));
      final TgAvatarPainter painter = _painterOf(tester);
      expect(painter.color, top);
      expect(painter.color2, bottom);
      // Unrelated keys still resolve through the theme.
      expect(
        painter.textColor,
        _dayTheme.color(TelegramColorKey.avatar_text),
      );
    });

    testWidgets('peerColor hue-maps into the palette '
        '(AvatarDrawable.java:479-480)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgAvatar(
        id: 0,
        peerColor: Color(0xFF00FF00), // hue 120 → green (index 3)
        size: 50.0,
      )));
      expect(
        _painterOf(tester).color,
        _dayTheme.color(TelegramColorKey.avatar_backgroundGreen),
      );
    });

    testWidgets('explicit colors win (setColor, AvatarDrawable.java:359-372)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgAvatar(
        color: Color(0xFF111111),
        color2: Color(0xFF222222),
        size: 50.0,
      )));
      TgAvatarPainter painter = _painterOf(tester);
      expect(painter.color, const Color(0xFF111111));
      expect(painter.color2, const Color(0xFF222222));

      // Single color → flat fill (color2 defaults to color).
      await tester.pumpWidget(_host(const TgAvatar(
        color: Color(0xFF333333),
        size: 50.0,
      )));
      painter = _painterOf(tester);
      expect(painter.color, const Color(0xFF333333));
      expect(painter.color2, const Color(0xFF333333));
    });

    testWidgets('saved variant: Saved pair, no initials '
        '(AvatarDrawable.java:260-263)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgAvatar.saved(size: 50.0)));
      final TgAvatarPainter painter = _painterOf(tester);
      expect(
        painter.color,
        _dayTheme.color(TelegramColorKey.avatar_backgroundSaved),
      );
      expect(
        painter.color2,
        _dayTheme.color(TelegramColorKey.avatar_background2Saved),
      );
      expect(painter.initials, isEmpty);
    });

    testWidgets('archived variant: flat avatar_backgroundArchived '
        '(AvatarDrawable.java:602-605)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgAvatar.archived(size: 50.0)));
      final TgAvatarPainter painter = _painterOf(tester);
      final Color archived =
          _dayTheme.color(TelegramColorKey.avatar_backgroundArchived);
      expect(painter.color, archived);
      expect(painter.color2, archived);
      expect(painter.initials, isEmpty);
    });

    testWidgets('initials are uppercased at draw time and colored '
        'avatar_text (AvatarDrawable.java:566, 717)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgAvatar(
        firstName: 'john',
        lastName: 'smith',
        size: 50.0,
      )));
      final TgAvatarPainter painter = _painterOf(tester);
      expect(painter.initials, 'J‌S');
      expect(
        painter.textColor,
        _dayTheme.color(TelegramColorKey.avatar_text),
      );
      expect(painter.textSize, kTgAvatarTextSize);
    });

    testWidgets('size and roundRadius flow through',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgAvatar(
        id: 1,
        size: 56.0,
        roundRadius: 12.0,
        textSize: 20.0,
      )));
      expect(tester.getSize(find.byType(TgAvatar)), const Size(56.0, 56.0));
      final TgAvatarPainter painter = _painterOf(tester);
      expect(painter.roundRadius, 12.0);
      expect(painter.textSize, 20.0);
    });

    testWidgets('no intrinsic size: fills a tight parent like the '
        'zero-intrinsic Java drawable (AvatarDrawable.java:761-769)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(width: 52.0, height: 52.0, child: TgAvatar(id: 2)),
      ));
      expect(tester.getSize(find.byType(TgAvatar)), const Size(52.0, 52.0));
    });

    testWidgets('image slot renders cover-fit inside an oval clip',
        (WidgetTester tester) async {
      final MemoryImage provider = MemoryImage(_transparentPng);
      await tester.pumpWidget(_host(TgAvatar(
        id: 0,
        size: 50.0,
        image: provider,
      )));
      final Image image = tester.widget<Image>(find.byType(Image));
      expect(image.image, same(provider));
      expect(image.fit, BoxFit.cover);
      expect(
        find.descendant(
          of: find.byType(TgAvatar),
          matching: find.byType(ClipOval),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('image slot clips to the rounded rect when roundRadius > 0',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgAvatar(
        id: 0,
        size: 50.0,
        roundRadius: 8.0,
        image: MemoryImage(_transparentPng),
      )));
      final ClipRRect clip = tester.widget<ClipRRect>(find.descendant(
        of: find.byType(TgAvatar),
        matching: find.byType(ClipRRect),
      ));
      expect(clip.borderRadius, BorderRadius.circular(8.0));
      expect(find.byType(ClipOval), findsNothing);
    });
  });
}
