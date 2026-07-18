// Tests for lib/src/components/cells/dialog_cell.dart (ARCHITECTURE.md
// section 6, row "DialogCell"), golden-free:
//
//  * row heights: 70 + 1px separator (DialogCell.java:171, 1019-1023) and
//    the 76 + 1px three-line variant (L172), separator row reserved even
//    when the line is not painted (`useSeparator || true`, L1021);
//  * geometry via finders + rect assertions: avatar 52x52 @ (11, 9) /
//    56x56 @ (11, 11) (L2452, 2470 / L2429, 2447), name @ (76, 14) /
//    (78, 10) (L2466, 4081 / L2443), message @ (76, 39) / (78, 32)
//    (L2688 / L2682), time top 16 / 13 right-aligned at 15.666;
//  * unread badge min-width math for 1 / 99 / 999+ (L1224-1229, 2510-2515);
//  * separator inset 72 / full (L4774-4791);
//  * color keys light + dark: chats_name, chats_message(_threeLines),
//    chats_date, chats_unreadCounter(Muted|Text), divider.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/cells/dialog_cell.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_resources.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared themes (constructing the 777-key palettes once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();
final TelegramThemeData _nightTheme = TelegramThemeData.night();

/// Fixed cell width for rect assertions (the Ring-2 golden width).
const double _cellWidth = 393.0;

Widget _host(
  Widget child, {
  TelegramThemeData? theme,
  TextDirection direction = TextDirection.ltr,
}) {
  return TelegramTheme(
    data: theme ?? _dayTheme,
    child: Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: _cellWidth, child: child),
      ),
    ),
  );
}

/// Measures [text] exactly as the component does (same style + pinned
/// TextHeightBehavior), so expectations are font-agnostic.
double _measure(String text, TextStyle style) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textHeightBehavior: const TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    ),
  )..layout();
  final double width = painter.width;
  painter.dispose();
  return width;
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final Rect cell = tester.getRect(find.byType(DialogCell));
  return tester.getRect(finder).shift(-cell.topLeft);
}

void main() {
  group('constants mirror the Java values', () {
    test('layout constants (DialogCell.java:169-174)', () {
      expect(DialogCellMetrics.avatarStart, 11.0);
      expect(DialogCellMetrics.messagePaddingStart, 72.0);
      expect(DialogCellMetrics.heightDefault, 70.0);
      expect(DialogCellMetrics.heightThreeLines, 76.0);
      expect(DialogCellMetrics.separatorHeight, 1.0);
    });

    test('two-line geometry (DialogCell.java:2451-2470, 2688, 4081)', () {
      expect(DialogCellMetrics.avatarSize(), 52.0);
      expect(DialogCellMetrics.avatarTop(), 9.0);
      expect(DialogCellMetrics.textStart(), 76.0);
      expect(DialogCellMetrics.nameTop(), 14.0);
      expect(DialogCellMetrics.messageTop(), 39.0);
      expect(DialogCellMetrics.timeTop(), 16.0);
      expect(DialogCellMetrics.countTop(), 38.0);
      expect(DialogCellMetrics.pinTop(), 39.0);
      // messageWidth = w - dp(72 + 20 - 12) (L2459).
      expect(DialogCellMetrics.messageWidthInset(), 80.0);
    });

    test('three-line geometry (DialogCell.java:2428-2449, 2682, 4081)', () {
      expect(DialogCellMetrics.avatarSize(threeLines: true), 56.0);
      expect(DialogCellMetrics.avatarTop(threeLines: true), 11.0);
      expect(DialogCellMetrics.textStart(threeLines: true), 78.0);
      expect(DialogCellMetrics.nameTop(threeLines: true), 10.0);
      expect(DialogCellMetrics.messageTop(threeLines: true), 32.0);
      expect(DialogCellMetrics.timeTop(threeLines: true), 13.0);
      expect(DialogCellMetrics.countTop(threeLines: true), 42.33);
      expect(DialogCellMetrics.pinTop(threeLines: true), 43.0);
      // messageWidth = w - dp(72 + 21) (L2436).
      expect(DialogCellMetrics.messageWidthInset(threeLines: true), 93.0);
    });

    test('badge constants (DialogCell.java:1224-1229, 5291, 5298)', () {
      expect(DialogCellMetrics.badgeTextPadding, 6.333);
      expect(DialogCellMetrics.badgeTextMinWidth, 8.0);
      // BADGE_SIZE = BADGE_TEXT_PADDING * 2 + BADGE_TEXT_MIN_WIDTH (L1224).
      expect(DialogCellMetrics.badgeHeight, closeTo(20.666, 1e-9));
      expect(DialogCellMetrics.badgeGap, 17.0); // 25 - 8 (L1228).
      expect(DialogCellMetrics.badgeMargin, 15.666);
      expect(DialogCellMetrics.badgeRadius, 11.5);
      expect(DialogCellMetrics.badgeTextTop, 3.0);
    });

    test('text sizes (DialogCell.java:1252-1254, Theme.java:8371-8372, 8472)',
        () {
      expect(DialogCellMetrics.nameFontSize, 16.0);
      expect(DialogCellMetrics.messageFontSize, 15.0);
      expect(DialogCellMetrics.timeFontSize, 12.0);
      expect(DialogCellMetrics.countFontSize, 13.0);
      expect(DialogCell.nameStyle(const Color(0xFF000000)).fontWeight,
          FontWeight.w500);
      expect(DialogCell.nameStyle(const Color(0xFF000000)).fontFamily,
          'packages/telegram_ui/RobotoMedium');
    });

    test('misc metrics (DialogCell.java:2290, 2491, 2891, 4427-4471)', () {
      expect(DialogCellMetrics.nameTrailingGap, 22.0); // dp(14 + 8).
      expect(DialogCellMetrics.pinRightMargin, 14.0);
      expect(DialogCellMetrics.glyphGap, 6.0);
      expect(DialogCellMetrics.muteGlyphDx(), -1.0);
      expect(DialogCellMetrics.muteGlyphDx(threeLines: true), 0.0);
      expect(DialogCellMetrics.muteGlyphTop(), 17.5);
      expect(DialogCellMetrics.muteGlyphTop(threeLines: true), 13.5);
      expect(DialogCellMetrics.verifiedGlyphDx, -1.0);
      expect(DialogCellMetrics.verifiedGlyphTop(), 16.5);
      expect(DialogCellMetrics.verifiedGlyphTop(threeLines: true), 13.5);
      expect(DialogCellMetrics.timeRightMargin, 15.666);
      expect(DialogCellMetrics.messageMinWidth, 12.0);
    });
  });

  group('badge min-width math (DialogCell.java:2510, 2515)', () {
    test('floor: text narrower than 8 pads to the circular BADGE_SIZE', () {
      // countWidth = max(dp(8), ceil(w)); badge = countWidth + 2 * 6.333.
      expect(DialogCellMetrics.badgeWidthFor(0.0), DialogCellMetrics.badgeHeight);
      expect(DialogCellMetrics.badgeWidthFor(4.0), DialogCellMetrics.badgeHeight);
      expect(DialogCellMetrics.badgeWidthFor(7.9), DialogCellMetrics.badgeHeight);
    });

    test('ceil: fractional text widths round up before padding', () {
      expect(DialogCellMetrics.badgeWidthFor(13.2),
          14.0 + 2 * DialogCellMetrics.badgeTextPadding);
      expect(DialogCellMetrics.badgeWidthFor(26.0),
          26.0 + 2 * DialogCellMetrics.badgeTextPadding);
    });
  });

  group('row heights', () {
    testWidgets('two-line: 70 + 1px separator', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const DialogCell(name: 'Alice')));
      expect(tester.getSize(find.byType(DialogCell)),
          const Size(_cellWidth, 71.0));
    });

    testWidgets('three-line: 76 + 1px separator', (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(const DialogCell(name: 'Alice', threeLines: true)));
      expect(tester.getSize(find.byType(DialogCell)),
          const Size(_cellWidth, 77.0));
    });

    testWidgets(
        'separator row is reserved even when not painted '
        '(useSeparator || true, L1021)', (WidgetTester tester) async {
      await tester.pumpWidget(
          _host(const DialogCell(name: 'Alice', drawSeparator: false)));
      expect(tester.getSize(find.byType(DialogCell)),
          const Size(_cellWidth, 71.0));
    });
  });

  group('avatar slot', () {
    testWidgets('two-line: tight 52x52 at (11, 9)', (WidgetTester tester) async {
      const Key key = Key('avatar');
      await tester.pumpWidget(_host(const DialogCell(
        name: 'Alice',
        avatar: SizedBox(key: key),
      )));
      expect(_rectOf(tester, find.byKey(key)),
          const Rect.fromLTWH(11.0, 9.0, 52.0, 52.0));
    });

    testWidgets('three-line: tight 56x56 at (11, 11)',
        (WidgetTester tester) async {
      const Key key = Key('avatar');
      await tester.pumpWidget(_host(const DialogCell(
        name: 'Alice',
        threeLines: true,
        avatar: SizedBox(key: key),
      )));
      expect(_rectOf(tester, find.byKey(key)),
          const Rect.fromLTWH(11.0, 11.0, 56.0, 56.0));
    });
  });

  group('text positions (LTR)', () {
    testWidgets('two-line: name (76, 14), message (76, 39), time top 16 '
        'right-aligned 15.666', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const DialogCell(
        name: 'Alice',
        message: 'Hello there',
        time: '12:30',
      )));

      final Rect name = _rectOf(tester, find.text('Alice'));
      expect(name.left, 76.0);
      expect(name.top, 14.0);

      final Rect message = _rectOf(tester, find.text('Hello there'));
      expect(message.left, 76.0);
      expect(message.top, 39.0);

      final Rect time = _rectOf(tester, find.text('12:30'));
      expect(time.top, 16.0);
      expect(_cellWidth - time.right, moreOrLessEquals(15.666));
    });

    testWidgets('three-line: name (78, 10), message (78, 32), time top 13',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const DialogCell(
        name: 'Alice',
        message: 'Hello there',
        time: '12:30',
        threeLines: true,
      )));

      final Rect name = _rectOf(tester, find.text('Alice'));
      expect(name.left, 78.0);
      expect(name.top, 10.0);

      final Rect message = _rectOf(tester, find.text('Hello there'));
      expect(message.left, 78.0);
      expect(message.top, 32.0);

      final Rect time = _rectOf(tester, find.text('12:30'));
      expect(time.top, 13.0);
      expect(_cellWidth - time.right, moreOrLessEquals(15.666));

      // Three-line variant allows two message lines (StaticLayoutEx maxLines
      // 2, DialogCell.java:2758).
      expect(tester.widget<Text>(find.text('Hello there')).maxLines, 2);
    });

    testWidgets(
        'name field width = w - nameLeft - 22 - ceil(timeWidth) '
        '(DialogCell.java:2264, 2290)', (WidgetTester tester) async {
      const String longName =
          'A very very very very very very very very long dialog name';
      const String time = '12:30';
      await tester.pumpWidget(_host(const DialogCell(
        name: longName,
        time: time,
      )));

      final double timeWidth = _measure(
        time,
        DialogCell.timeStyle(const Color(0xFF000000)),
      ).ceilToDouble();
      final Rect name = _rectOf(tester, find.text(longName));
      expect(name.width,
          moreOrLessEquals(_cellWidth - 76.0 - 22.0 - timeWidth));
    });
  });

  group('unread badge', () {
    Future<Rect> pumpAndBadgeRect(
      WidgetTester tester, {
      int unreadCount = 0,
      String? countText,
      bool threeLines = false,
    }) async {
      await tester.pumpWidget(_host(DialogCell(
        name: 'Alice',
        message: 'Hello',
        unreadCount: unreadCount,
        countText: countText,
        threeLines: threeLines,
      )));
      return _rectOf(tester, find.byType(DialogCellUnreadBadge));
    }

    testWidgets('count 1: width = badgeWidthFor(measured "1"), height 20.666, '
        'right margin 15.666, top 38', (WidgetTester tester) async {
      final Rect badge = await pumpAndBadgeRect(tester, unreadCount: 1);
      final double textWidth =
          _measure('1', DialogCellUnreadBadge.textStyle(const Color(0xFF000000)));
      expect(badge.width,
          moreOrLessEquals(DialogCellMetrics.badgeWidthFor(textWidth)));
      expect(badge.height, moreOrLessEquals(20.666));
      expect(_cellWidth - badge.right, moreOrLessEquals(15.666));
      expect(badge.top, 38.0);
    });

    testWidgets('count 99 widens by the measured text',
        (WidgetTester tester) async {
      final Rect badge = await pumpAndBadgeRect(tester, unreadCount: 99);
      final double textWidth = _measure(
          '99', DialogCellUnreadBadge.textStyle(const Color(0xFF000000)));
      expect(badge.width,
          moreOrLessEquals(DialogCellMetrics.badgeWidthFor(textWidth)));
      expect(_cellWidth - badge.right, moreOrLessEquals(15.666));
    });

    testWidgets('countText "999+" overrides the label and sizes the badge',
        (WidgetTester tester) async {
      final Rect badge =
          await pumpAndBadgeRect(tester, unreadCount: 1000, countText: '999+');
      final double textWidth = _measure(
          '999+', DialogCellUnreadBadge.textStyle(const Color(0xFF000000)));
      expect(badge.width,
          moreOrLessEquals(DialogCellMetrics.badgeWidthFor(textWidth)));
      final RenderDialogCellUnreadBadge render = tester
              .renderObject(find.byType(DialogCellUnreadBadge))
          as RenderDialogCellUnreadBadge;
      expect(render.text, '999+');
    });

    testWidgets('three-line: badge top 42.33', (WidgetTester tester) async {
      final Rect badge =
          await pumpAndBadgeRect(tester, unreadCount: 5, threeLines: true);
      expect(badge.top, moreOrLessEquals(42.33));
    });

    testWidgets('standalone floor: a badge whose text is narrower than 8 '
        'is the 20.666 circle', (WidgetTester tester) async {
      // No text at all: countWidth clamps to dp(8) (DialogCell.java:2510).
      // Loose constraints (Center) so the badge self-sizes.
      await tester.pumpWidget(TelegramTheme(
        data: _dayTheme,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: DialogCellUnreadBadge(text: '')),
        ),
      ));
      final Size size = tester.getSize(find.byType(DialogCellUnreadBadge));
      expect(size.width, moreOrLessEquals(20.666));
      expect(size.height, moreOrLessEquals(20.666));
    });

    testWidgets('message field shrinks by countWidth + 17 when a badge shows '
        '(DialogCell.java:2512-2513)', (WidgetTester tester) async {
      const String longMessage =
          'A very very very very very very very very very long message text';
      await tester.pumpWidget(_host(const DialogCell(
        name: 'Alice',
        message: longMessage,
        unreadCount: 999,
      )));
      final Rect badge = _rectOf(tester, find.byType(DialogCellUnreadBadge));
      final double countWidth =
          badge.width - 2 * DialogCellMetrics.badgeTextPadding;
      final Rect message = _rectOf(tester, find.text(longMessage));
      expect(
        message.width,
        moreOrLessEquals(_cellWidth - 80.0 - (countWidth + 17.0)),
      );
    });

    testWidgets('fill chats_unreadCounter / muted chats_unreadCounterMuted, '
        'text chats_unreadCounterText — light + dark',
        (WidgetTester tester) async {
      for (final TelegramThemeData theme in <TelegramThemeData>[
        _dayTheme,
        _nightTheme,
      ]) {
        await tester.pumpWidget(_host(
          const DialogCell(name: 'Alice', unreadCount: 3),
          theme: theme,
        ));
        RenderDialogCellUnreadBadge render = tester
                .renderObject(find.byType(DialogCellUnreadBadge))
            as RenderDialogCellUnreadBadge;
        expect(render.fillColor,
            theme.color(TelegramColorKey.chats_unreadCounter));
        expect(render.textColor,
            theme.color(TelegramColorKey.chats_unreadCounterText));

        await tester.pumpWidget(_host(
          const DialogCell(name: 'Alice', unreadCount: 3, countMuted: true),
          theme: theme,
        ));
        render = tester.renderObject(find.byType(DialogCellUnreadBadge))
            as RenderDialogCellUnreadBadge;
        expect(render.fillColor,
            theme.color(TelegramColorKey.chats_unreadCounterMuted));
      }
    });
  });

  group('pin slot', () {
    testWidgets('pinned icon at (w - width - 14, 39)',
        (WidgetTester tester) async {
      const Key key = Key('pin');
      await tester.pumpWidget(_host(const DialogCell(
        name: 'Alice',
        pinned: true,
        pinnedIcon: SizedBox(key: key, width: 16, height: 16),
      )));
      expect(_rectOf(tester, find.byKey(key)),
          const Rect.fromLTWH(_cellWidth - 16.0 - 14.0, 39.0, 16.0, 16.0));
    });

    testWidgets('three-line: pin top 43', (WidgetTester tester) async {
      const Key key = Key('pin');
      await tester.pumpWidget(_host(const DialogCell(
        name: 'Alice',
        threeLines: true,
        pinned: true,
        pinnedIcon: SizedBox(key: key, width: 16, height: 16),
      )));
      expect(_rectOf(tester, find.byKey(key)).top, 43.0);
    });

    testWidgets('a badge suppresses the pin (DialogCell.java:4517-4523)',
        (WidgetTester tester) async {
      const Key key = Key('pin');
      await tester.pumpWidget(_host(const DialogCell(
        name: 'Alice',
        pinned: true,
        unreadCount: 2,
        pinnedIcon: SizedBox(key: key, width: 16, height: 16),
      )));
      expect(find.byKey(key), findsNothing);
      expect(find.byType(DialogCellUnreadBadge), findsOneWidget);
    });
  });

  group('name glyph slots', () {
    testWidgets('verified at (nameEnd + 6 - 1, 16.5); mute alone at '
        '(nameEnd + 6 - 1, 17.5)', (WidgetTester tester) async {
      const Key verified = Key('verified');
      await tester.pumpWidget(_host(const DialogCell(
        name: 'Alice',
        verifiedGlyph: SizedBox(key: verified, width: 20, height: 20),
      )));
      final Rect name = _rectOf(tester, find.text('Alice'));
      final Rect verifiedRect = _rectOf(tester, find.byKey(verified));
      expect(verifiedRect.left,
          moreOrLessEquals(name.left + name.width + 6.0 - 1.0));
      expect(verifiedRect.top, 16.5);

      const Key mute = Key('mute');
      await tester.pumpWidget(_host(const DialogCell(
        name: 'Alice',
        muteGlyph: SizedBox(key: mute, width: 20, height: 20),
      )));
      final Rect muteRect = _rectOf(tester, find.byKey(mute));
      expect(muteRect.left,
          moreOrLessEquals(name.left + name.width + 6.0 - 1.0));
      expect(muteRect.top, 17.5);
    });

    testWidgets('three-line tops 13.5; mute dx 0 (DialogCell.java:4427-4467)',
        (WidgetTester tester) async {
      const Key mute = Key('mute');
      await tester.pumpWidget(_host(const DialogCell(
        name: 'Alice',
        threeLines: true,
        muteGlyph: SizedBox(key: mute, width: 20, height: 20),
      )));
      final Rect name = _rectOf(tester, find.text('Alice'));
      final Rect muteRect = _rectOf(tester, find.byKey(mute));
      expect(muteRect.left, moreOrLessEquals(name.left + name.width + 6.0));
      expect(muteRect.top, 13.5);
    });

    testWidgets('both slots: mute stacks 6dp after verified',
        (WidgetTester tester) async {
      const Key verified = Key('verified');
      const Key mute = Key('mute');
      await tester.pumpWidget(_host(const DialogCell(
        name: 'Alice',
        verifiedGlyph: SizedBox(key: verified, width: 20, height: 20),
        muteGlyph: SizedBox(key: mute, width: 20, height: 20),
      )));
      final Rect verifiedRect = _rectOf(tester, find.byKey(verified));
      final Rect muteRect = _rectOf(tester, find.byKey(mute));
      expect(muteRect.left,
          moreOrLessEquals(verifiedRect.right + 6.0 - 1.0));
    });
  });

  group('separator', () {
    DialogCellSeparatorPainter? painterOf(WidgetTester tester) {
      final CustomPaint paint = tester.widget<CustomPaint>(find.descendant(
        of: find.byType(DialogCell),
        matching: find.byWidgetPredicate((Widget w) =>
            w is CustomPaint &&
            (w.foregroundPainter == null ||
                w.foregroundPainter is DialogCellSeparatorPainter)),
      ));
      return paint.foregroundPainter as DialogCellSeparatorPainter?;
    }

    testWidgets('inset 72, divider color — light + dark',
        (WidgetTester tester) async {
      for (final TelegramThemeData theme in <TelegramThemeData>[
        _dayTheme,
        _nightTheme,
      ]) {
        await tester
            .pumpWidget(_host(const DialogCell(name: 'Alice'), theme: theme));
        final DialogCellSeparatorPainter painter = painterOf(tester)!;
        expect(painter.inset, 72.0);
        expect(painter.thickness, 1.0);
        expect(painter.color, theme.color(TelegramColorKey.divider));
      }
    });

    testWidgets('fullSeparator: inset 0 (DialogCell.java:4775-4780)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _host(const DialogCell(name: 'Alice', fullSeparator: true)));
      expect(painterOf(tester)!.inset, 0.0);
    });

    testWidgets('drawSeparator false: no painter, height keeps the 1px row',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _host(const DialogCell(name: 'Alice', drawSeparator: false)));
      expect(painterOf(tester), isNull);
      expect(tester.getSize(find.byType(DialogCell)).height, 71.0);
    });
  });

  group('color keys light + dark', () {
    testWidgets('name chats_name, message chats_message, time chats_date',
        (WidgetTester tester) async {
      for (final TelegramThemeData theme in <TelegramThemeData>[
        _dayTheme,
        _nightTheme,
      ]) {
        await tester.pumpWidget(_host(
          const DialogCell(name: 'Alice', message: 'Hello', time: '12:30'),
          theme: theme,
        ));
        expect(tester.widget<Text>(find.text('Alice')).style!.color,
            theme.color(TelegramColorKey.chats_name));
        expect(tester.widget<Text>(find.text('Hello')).style!.color,
            theme.color(TelegramColorKey.chats_message));
        expect(tester.widget<Text>(find.text('12:30')).style!.color,
            theme.color(TelegramColorKey.chats_date));
      }
    });

    testWidgets('three-line message uses chats_message_threeLines '
        '(DialogCell.java:1257)', (WidgetTester tester) async {
      for (final TelegramThemeData theme in <TelegramThemeData>[
        _dayTheme,
        _nightTheme,
      ]) {
        await tester.pumpWidget(_host(
          const DialogCell(name: 'Alice', message: 'Hello', threeLines: true),
          theme: theme,
        ));
        expect(tester.widget<Text>(find.text('Hello')).style!.color,
            theme.color(TelegramColorKey.chats_message_threeLines));
      }
    });

    testWidgets('resources override wins (ResourcesProvider convention)',
        (WidgetTester tester) async {
      const Color override = Color(0xFF123456);
      await tester.pumpWidget(_host(DialogCell(
        name: 'Alice',
        resources: ResourcesOverride(
          parent: _ThemeResources(_dayTheme),
          overrides: const <int, Color>{
            TelegramColorKey.chats_name: override,
          },
        ),
      )));
      expect(
          tester.widget<Text>(find.text('Alice')).style!.color, override);
    });
  });

  group('RTL mirror', () {
    testWidgets('avatar and name mirror; time left margin 15.666',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const DialogCell(
          name: 'Alice',
          time: '12:30',
          avatar: SizedBox(key: Key('avatar')),
        ),
        direction: TextDirection.rtl,
      ));
      final Rect avatar = _rectOf(tester, find.byKey(const Key('avatar')));
      expect(avatar.right, _cellWidth - 11.0);
      expect(avatar.top, 9.0);
      final Rect name = _rectOf(tester, find.text('Alice'));
      expect(name.right, _cellWidth - 76.0);
      final Rect time = _rectOf(tester, find.text('12:30'));
      expect(time.left, moreOrLessEquals(15.666));
    });
  });
}

/// Minimal [TelegramResources] view over a theme for override-chain tests.
class _ThemeResources extends TelegramResources {
  const _ThemeResources(this.data);

  final TelegramThemeData data;

  @override
  Color getColor(int key) => data.color(key);

  @override
  bool get isDark => false;
}
