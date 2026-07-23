// Tests for lib/src/chips/tg_chip.dart (PLAN_UIKIT.md S4), golden-free:
//
//  * constants vs GroupCreateSpan.java (heights, radii, offsets, 120ms);
//  * the Java color blends — background `(int)` channel lerp
//    (GroupCreateSpan.java:346) and `ColorUtils.blendARGB` text blend
//    (GroupCreateSpan.java:367);
//  * measured width `extra + ceil(textWidth)` (GroupCreateSpan.java:317-320)
//    for both sizes, plus the maxNameWidth ellipsis cap;
//  * the 120ms linear delete crossfade (GroupCreateSpan.java:331-341) and the
//    avatar `progress != 1` visibility gate (GroupCreateSpan.java:348-350);
//  * onTap / onDeleted arming recipe (GroupCreateActivity span click);
//  * theme key resolution + resources override (both directions);
//  * semantics label (GroupCreateSpan.java:376).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/avatar/tg_avatar.dart';
import 'package:telegram_ui/src/chips/tg_chip.dart';
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
      child: Center(child: child),
    ),
  );
}

TgChipPainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byWidgetPredicate(
      (Widget w) => w is CustomPaint && w.painter is TgChipPainter,
    ))
    .painter! as TgChipPainter;

TgChipDeletePainter _deletePainter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byWidgetPredicate(
      (Widget w) => w is CustomPaint && w.foregroundPainter is TgChipDeletePainter,
    ))
    .foregroundPainter! as TgChipDeletePainter;

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kTgChipHeight, 32.0); // GroupCreateSpan.java:319, 345
      expect(kTgChipSmallHeight, 28.0); // GroupCreateSpan.java:319, 345
      expect(kTgChipRadius, 16.0); // GroupCreateSpan.java:347
      expect(kTgChipSmallRadius, 14.0); // GroupCreateSpan.java:347
      expect(kTgChipAvatarSize, 32.0); // GroupCreateSpan.java:231
      expect(kTgChipSmallAvatarSize, 28.0); // GroupCreateSpan.java:231
      expect(kTgChipAvatarTextSize, 20.0); // GroupCreateSpan.java:101
      expect(kTgChipTextSize, 14.0); // GroupCreateSpan.java:93
      expect(kTgChipSmallTextSize, 13.0); // GroupCreateSpan.java:93
      expect(kTgChipTextX, 41.0); // GroupCreateSpan.java:364 (32 + 9)
      expect(kTgChipSmallTextX, 35.0); // GroupCreateSpan.java:364 (26 + 9)
      expect(kTgChipTextY, 8.0); // GroupCreateSpan.java:364
      expect(kTgChipSmallTextY, 6.0); // GroupCreateSpan.java:364
      expect(kTgChipWidthExtra, 57.0); // GroupCreateSpan.java:318 (32 + 25)
      expect(kTgChipSmallWidthExtra, 45.0); // GroupCreateSpan.java:318
      expect(kTgChipDeleteDuration,
          const Duration(milliseconds: 120)); // GroupCreateSpan.java:332
      expect(kTgChipDeleteIconRotation, 45.0); // GroupCreateSpan.java:358
      expect(kTgChipDeleteIconInset, 11.0); // GroupCreateSpan.java:359
      expect(kTgChipSmallDeleteIconInset, 9.0); // GroupCreateSpan.java:359
      expect(kTgChipDeleteIconSize, 10.0); // GroupCreateSpan.java:359 (21-11)
      expect(kTgChipBackgroundAlpha, 0.05); // GroupCreateSpan.java:263
    });

    test('name styles are the TgTextStyles roles at the Java sizes', () {
      // 14dp regular (GroupCreateSpan.java:93; no medium typeface is set).
      expect(TgTextStyles.subtitle.fontSize, kTgChipTextSize);
      expect(TgTextStyles.subtitle.fontWeight, FontWeight.w400);
      expect(TgTextStyles.caption.fontSize, kTgChipSmallTextSize);
      expect(TgTextStyles.caption.fontWeight, FontWeight.w400);
    });

    test('background blend: Java (int) channel lerp (GroupCreateSpan.java:346)',
        () {
      const Color from = Color(0x0D101820);
      const Color to = Color(0xFF5294EC);
      expect(tgChipBackgroundColor(from, to, 0.0), from);
      expect(tgChipBackgroundColor(from, to, 1.0), to);
      final Color mid = tgChipBackgroundColor(from, to, 0.5);
      // a: 0x0D + (int)((0xFF - 0x0D) * .5) = 13 + 121 = 134.
      expect((mid.a * 255.0).round(), 134);
      // r: 0x10 + (int)((0x52 - 0x10) * .5) = 16 + 33 = 49.
      expect((mid.r * 255.0).round(), 49);
      // g: 0x18 + (int)((0x94 - 0x18) * .5) = 24 + 62 = 86.
      expect((mid.g * 255.0).round(), 86);
      // b: 0x20 + (int)((0xEC - 0x20) * .5) = 32 + 102 = 134.
      expect((mid.b * 255.0).round(), 134);
    });

    test('text blend: ColorUtils.blendARGB (GroupCreateSpan.java:367)', () {
      const Color from = Color(0xFF64717D);
      const Color to = Color(0xFFFFFFFF);
      expect(tgChipTextColor(from, to, 0.0), from);
      expect(tgChipTextColor(from, to, 1.0), to);
      final Color mid = tgChipTextColor(from, to, 0.5);
      // r: (int)(0x64 * .5 + 0xFF * .5) = (int)177.5 = 177.
      expect((mid.r * 255.0).round(), 177);
      // g: (int)(0x71 * .5 + 0xFF * .5) = (int)184.0 = 184.
      expect((mid.g * 255.0).round(), 184);
    });
  });

  group('layout', () {
    testWidgets('width = 57 + ceil(textWidth), height 32 '
        '(GroupCreateSpan.java:317-320)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgChip(name: 'Alice')));
      final double textWidth = TgChip.nameWidth('Alice');
      expect(
        tester.getSize(find.byType(TgChip)),
        Size(kTgChipWidthExtra + textWidth, kTgChipHeight),
      );
      expect(_painter(tester).radius, kTgChipRadius);
    });

    testWidgets('small: width = 45 + ceil(textWidth), height 28',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgChip(name: 'Alice', small: true)));
      final double textWidth = TgChip.nameWidth('Alice', small: true);
      expect(
        tester.getSize(find.byType(TgChip)),
        Size(kTgChipSmallWidthExtra + textWidth, kTgChipSmallHeight),
      );
      expect(_painter(tester).radius, kTgChipSmallRadius);
      expect(_painter(tester).small, isTrue);
      expect(_deletePainter(tester).small, isTrue);
    });

    testWidgets('maxNameWidth ellipsizes (GroupCreateSpan.java:243)',
        (WidgetTester tester) async {
      const String long = 'A very long chip participant name';
      await tester
          .pumpWidget(_host(const TgChip(name: long, maxNameWidth: 40.0)));
      final Size size = tester.getSize(find.byType(TgChip));
      expect(size.width, lessThanOrEqualTo(kTgChipWidthExtra + 40.0));
      expect(size.width, lessThan(kTgChipWidthExtra + TgChip.nameWidth(long)));
    });

    testWidgets('newlines flatten to spaces (GroupCreateSpan.java:240)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgChip(name: 'Ann\nSmith')));
      expect(_painter(tester).name, 'Ann Smith');
      expect(
        tester.getSize(find.byType(TgChip)).width,
        kTgChipWidthExtra + TgChip.nameWidth('Ann Smith'),
      );
    });

    testWidgets('avatar slot renders at 32dp top-left, hidden once deleted '
        '(GroupCreateSpan.java:348-350)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgChip(
        name: 'Alice',
        avatar: TgAvatar(id: 1, firstName: 'Alice'),
      )));
      expect(find.byType(TgAvatar), findsOneWidget);
      expect(
        tester.getSize(find.byType(TgAvatar)),
        const Size(kTgChipAvatarSize, kTgChipAvatarSize),
      );
      expect(
        tester.getTopLeft(find.byType(TgAvatar)),
        tester.getTopLeft(find.byType(TgChip)),
      );

      await tester.pumpWidget(_host(const TgChip(
        name: 'Alice',
        avatar: TgAvatar(id: 1, firstName: 'Alice'),
        deleting: true,
      )));
      await tester.pumpAndSettle();
      // `if (progress != 1f) imageReceiver.draw(...)` — gone at 1.
      expect(find.byType(TgAvatar), findsNothing);
    });
  });

  group('delete animation', () {
    testWidgets('toggle ramps linearly over 120ms '
        '(GroupCreateSpan.java:331-341)', (WidgetTester tester) async {
      bool deleting = false;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return TgChip(
            name: 'Alice',
            avatar: const TgAvatar(id: 1, firstName: 'Alice'),
            deleting: deleting,
            onTap: () => setState(() => deleting = true),
            onDeleted: () {},
          );
        },
      )));
      final TgChipState state = tester.state(find.byType(TgChip));
      expect(state.debugProgress, 0.0);
      expect(_deletePainter(tester).progress, 0.0);

      await tester.tap(find.byType(TgChip));
      await tester.pump();
      expect(deleting, isTrue);
      expect(state.debugProgress, 0.0);

      // Linear ramp: halfway through 120ms sits exactly at 0.5.
      await tester.pump(const Duration(milliseconds: 60));
      expect(state.debugProgress, closeTo(0.5, 1e-3));
      expect(_deletePainter(tester).progress, closeTo(0.5, 1e-3));
      // Mid-flight the avatar is still drawn (progress != 1).
      expect(find.byType(TgAvatar), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 60));
      expect(state.debugProgress, 1.0);
      expect(find.byType(TgAvatar), findsNothing);
    });

    testWidgets('cancel animates back down (cancelDeleteAnimation, '
        'GroupCreateSpan.java:294-301)', (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(const TgChip(name: 'Alice', deleting: true)));
      final TgChipState state = tester.state(find.byType(TgChip));
      // Fresh mount snaps (controlled-widget convention).
      expect(state.debugProgress, 1.0);

      await tester
          .pumpWidget(_host(const TgChip(name: 'Alice', deleting: false)));
      await tester.pump(const Duration(milliseconds: 60));
      expect(state.debugProgress, closeTo(0.5, 1e-3));
      await tester.pumpAndSettle();
      expect(state.debugProgress, 0.0);
    });

    testWidgets('background and text blend with the progress '
        '(GroupCreateSpan.java:346, 367)', (WidgetTester tester) async {
      final Color base = Color(multAlpha(
        _dayTheme
            .color(TelegramColorKey.windowBackgroundWhiteBlackText)
            .toARGB32(),
        kTgChipBackgroundAlpha,
      ));
      final Color selected =
          _dayTheme.color(TelegramColorKey.avatar_backgroundBlue);

      await tester.pumpWidget(_host(const TgChip(name: 'Alice')));
      expect(_painter(tester).backgroundColor, base);
      expect(_painter(tester).textColor,
          _dayTheme.color(TelegramColorKey.groupcreate_spanText));

      await tester
          .pumpWidget(_host(const TgChip(name: 'Alice', deleting: true)));
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        _painter(tester).backgroundColor,
        tgChipBackgroundColor(base, selected, tester
            .state<TgChipState>(find.byType(TgChip))
            .debugProgress),
      );

      await tester.pumpAndSettle();
      expect(_painter(tester).backgroundColor, selected);
      expect(_painter(tester).textColor,
          _dayTheme.color(TelegramColorKey.avatar_text));
      expect(_deletePainter(tester).circleColor, selected);
    });
  });

  group('callbacks', () {
    testWidgets('tap fires onTap at rest and onDeleted while deleting',
        (WidgetTester tester) async {
      int taps = 0;
      int deletes = 0;
      bool deleting = false;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return TgChip(
            name: 'Alice',
            deleting: deleting,
            onTap: () {
              taps++;
              setState(() => deleting = true);
            },
            onDeleted: () => deletes++,
          );
        },
      )));

      await tester.tap(find.byType(TgChip));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(deletes, 0);

      // Second tap on the armed chip deletes (GroupCreateActivity recipe).
      await tester.tap(find.byType(TgChip));
      expect(taps, 1);
      expect(deletes, 1);
    });

    testWidgets('no callbacks -> inert, not a semantic button',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const TgChip(name: 'Alice')));
      await tester.tap(find.byType(TgChip), warnIfMissed: false);
      await tester.pump();
      expect(
        tester.getSemantics(find.byType(TgChip)),
        isSemantics(label: 'Alice', isButton: false, hasTapAction: false),
      );
      handle.dispose();
    });

    testWidgets('semantics: name label + button + tap '
        '(GroupCreateSpan.java:376)', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(TgChip(name: 'Alice', onTap: () {})));
      expect(
        tester.getSemantics(find.byType(TgChip)),
        isSemantics(label: 'Alice', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });

  group('colors', () {
    testWidgets('delete cross tinted groupcreate_spanDelete '
        '(GroupCreateSpan.java:264, 273)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgChip(name: 'Alice')));
      expect(_deletePainter(tester).iconColor,
          _dayTheme.color(TelegramColorKey.groupcreate_spanDelete));
    });

    testWidgets('explicit selectedColor wins over the key',
        (WidgetTester tester) async {
      const Color custom = Color(0xFFAA3355);
      await tester.pumpWidget(_host(const TgChip(
        name: 'Alice',
        selectedColor: custom,
        deleting: true,
      )));
      await tester.pumpAndSettle();
      expect(_deletePainter(tester).circleColor, custom);
      expect(_painter(tester).backgroundColor, custom);
    });

    testWidgets('selectedColorKey resolves through the theme',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgChip(
        name: 'Alice',
        selectedColorKey: TelegramColorKey.avatar_backgroundGreen,
        deleting: true,
      )));
      await tester.pumpAndSettle();
      expect(_painter(tester).backgroundColor,
          _dayTheme.color(TelegramColorKey.avatar_backgroundGreen));
    });

    testWidgets('resources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color override = Color(0xFF123456);
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return TgChip(
          name: 'Alice',
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.groupcreate_spanText: override,
            },
          ),
        );
      })));
      expect(_painter(tester).textColor, override);

      // And without the override the theme value resolves again.
      await tester.pumpWidget(_host(const TgChip(name: 'Alice')));
      expect(_painter(tester).textColor,
          _dayTheme.color(TelegramColorKey.groupcreate_spanText));
    });
  });
}
