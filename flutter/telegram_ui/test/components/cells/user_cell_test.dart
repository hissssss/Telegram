// Tests for lib/src/components/cells/user_cell.dart (ARCHITECTURE.md
// section 6, row "UserCell"), golden-free:
//
//  * geometry: 58dp row (UserCell.java:497), avatar slot 46x46 @
//    (7 + padding, 6) (UserCell.java:183), name 16dp box @ (64 + padding,
//    10), status @ top 32 (UserCell.java:191, 199), checkbox slot 24x24 @
//    (24 + padding, 36) (UserCell.java:215);
//  * status color: `windowBackgroundWhiteGrayText` offline
//    (UserCell.java:158, 720) vs `telegram_color_text` online
//    (UserCell.java:159, 716-718);
//  * add button: radius-14 `featuredStickers_addButton` round rect with
//    `featuredStickers_buttonText` 14dp text (UserCell.java:142-150), the
//    trailing text reserve (UserCell.java:151), and tap wiring;
//  * the 1-physical-px divider at the 68dp inset (UserCell.java:497,
//    771-774);
//  * dark-theme key resolution and the resources override.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/cells/text_cell.dart'
    show TextCellDividerPainter;
import 'package:telegram_ui/src/components/cells/user_cell.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared themes (constructing the 777-key palettes once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();
final TelegramThemeData _nightTheme = TelegramThemeData.night();

Widget _host(
  Widget child, {
  TelegramThemeData? theme,
  TextDirection textDirection = TextDirection.ltr,
}) {
  return TelegramTheme(
    data: theme ?? _dayTheme,
    child: Directionality(
      textDirection: textDirection,
      child: Align(alignment: Alignment.topCenter, child: child),
    ),
  );
}

CustomPaint _cellPaint(WidgetTester tester) => tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byType(UserCell),
            matching: find.byType(CustomPaint),
          )
          .first,
    );

Color _statusColor(WidgetTester tester, String status) =>
    tester.widget<Text>(find.text(status)).style!.color!;

/// The 20dp positioned box a text sits in — its nearest [Align] ancestor
/// (the host adds an outer Align of its own, hence `.first`).
Rect _textBox(WidgetTester tester, String text) => tester.getRect(
      find.ancestor(of: find.text(text), matching: find.byType(Align)).first,
    );

/// The add-button reserve as the widget computes it (UserCell.java:151),
/// using the same 14dp RobotoMedium style.
double _addReserve(String text) => UserCell.addButtonReservedWidth(
      text,
      const TextStyle(
        fontSize: kUserCellAddButtonTextSize,
        fontFamily: 'RobotoMedium',
        package: 'telegram_ui',
        fontWeight: FontWeight.w500,
      ),
      TextScaler.noScaling,
    );

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kUserCellHeight, 58.0); // UserCell.java:497
      expect(kUserCellCallHeight, 56.0); // UserCell.java:497
      expect(kUserCellAvatarSize, 46.0); // UserCell.java:183
      expect(kUserCellAvatarRadius, 24.0); // UserCell.java:182
      expect(kUserCellAvatarLeft, 7.0); // UserCell.java:183
      expect(kUserCellAvatarTop, 6.0); // UserCell.java:183
      expect(kUserCellTextLeft, 64.0); // UserCell.java:191, 199
      expect(kUserCellNameTop, 10.0); // UserCell.java:191
      expect(kUserCellNameTextSize, 16.0); // UserCell.java:189
      expect(kUserCellTextBoxHeight, 20.0); // UserCell.java:191, 199
      expect(kUserCellStatusTop, 32.0); // UserCell.java:199
      expect(kUserCellStatusTextSize, 15.0); // UserCell.java:197
      expect(kUserCellTextEndInset, 28.0); // UserCell.java:191, 199
      expect(kUserCellDividerInset, 68.0); // UserCell.java:773
      expect(kUserCellAddButtonHeight, 28.0); // UserCell.java:150
      expect(kUserCellAddButtonRadius, 14.0); // UserCell.java:147
      expect(kUserCellAddButtonTextSize, 14.0); // UserCell.java:145
      expect(kUserCellAddButtonHPadding, 17.0); // UserCell.java:149
      expect(kUserCellAddButtonTop, 15.0); // UserCell.java:150
      expect(kUserCellAddButtonEndInset, 14.0); // UserCell.java:150
      expect(kUserCellAddButtonReserve, 48.0); // UserCell.java:151 (34 + 14)
      expect(kUserCellCheckboxSize, 24.0); // UserCell.java:215
      expect(kUserCellCheckboxLeft, 24.0); // UserCell.java:215
      expect(kUserCellCheckboxTop, 36.0); // UserCell.java:215
    });

    test('addButtonReservedWidth: ceil(textWidth + 48) (UserCell.java:151)',
        () {
      const TextStyle style = TextStyle(fontSize: 14.0);
      final TextPainter painter = TextPainter(
        text: const TextSpan(text: 'Add', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final double expected = (painter.width + 48.0).ceilToDouble();
      painter.dispose();
      expect(
        UserCell.addButtonReservedWidth('Add', style, TextScaler.noScaling),
        expected,
      );
    });
  });

  group('geometry', () {
    testWidgets('58dp tall; avatar at (7,6) 46x46; texts at 64, tops 10/32',
        (WidgetTester tester) async {
      const Key avatarKey = Key('avatar');
      await tester.pumpWidget(_host(const UserCell(
        name: 'Name',
        status: 'Status',
        avatar: SizedBox(key: avatarKey),
      )));
      expect(tester.getSize(find.byType(UserCell)), const Size(800, 58));
      // Avatar slot (UserCell.java:183).
      expect(
        tester.getRect(find.byKey(avatarKey)),
        const Rect.fromLTWH(7, 6, 46, 46),
      );
      // Name: 20dp box at top 10, text (16dp tall under the test font)
      // centered -> top 12 (UserCell.java:191).
      final Offset name = tester.getTopLeft(find.text('Name'));
      expect(name.dx, 64.0);
      expect(name.dy, closeTo(10.0 + (20.0 - 16.0) / 2, 0.001));
      // Status: 20dp box at top 32, 15dp text -> top 34.5
      // (UserCell.java:199).
      final Offset status = tester.getTopLeft(find.text('Status'));
      expect(status.dx, 64.0);
      expect(status.dy, closeTo(32.0 + (20.0 - 15.0) / 2, 0.001));
      // Name box trailing margin 28 (UserCell.java:191): the box (the
      // Align filling the positioned slot) ends at width - 28.
      final Rect nameBox = _textBox(tester, 'Name');
      expect(nameBox.right, 800.0 - 28.0);
      expect(nameBox.height, 20.0);
    });

    testWidgets('padding shifts avatar (7+p), texts (64+p), checkbox (24+p)',
        (WidgetTester tester) async {
      const Key avatarKey = Key('avatar');
      const Key checkKey = Key('check');
      await tester.pumpWidget(_host(const UserCell(
        name: 'Name',
        padding: 8.0,
        avatar: SizedBox(key: avatarKey),
        checkbox: SizedBox(key: checkKey),
      )));
      expect(tester.getRect(find.byKey(avatarKey)).left, 7.0 + 8.0);
      expect(tester.getTopLeft(find.text('Name')).dx, 64.0 + 8.0);
      // Checkbox slot 24x24 at (24 + padding, 36) (UserCell.java:215).
      expect(
        tester.getRect(find.byKey(checkKey)),
        const Rect.fromLTWH(24.0 + 8.0, 36.0, 24.0, 24.0),
      );
    });

    testWidgets('RTL mirrors the slots', (WidgetTester tester) async {
      const Key avatarKey = Key('avatar');
      await tester.pumpWidget(_host(
        const UserCell(
          name: 'Name',
          avatar: SizedBox(key: avatarKey),
          divider: true,
        ),
        textDirection: TextDirection.rtl,
      ));
      // UserCell.java:183 RTL branch: avatar right margin 7 + padding.
      expect(tester.getRect(find.byKey(avatarKey)).right, 800.0 - 7.0);
      // UserCell.java:191 RTL branch: name right edge at width - 64.
      expect(tester.getTopRight(find.text('Name')).dx, 800.0 - 64.0);
      final TextCellDividerPainter painter =
          _cellPaint(tester).foregroundPainter! as TextCellDividerPainter;
      expect(painter.textDirection, TextDirection.rtl);
    });

    testWidgets('row tap fires onTap', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_host(UserCell(
        name: 'Name',
        onTap: () => taps++,
      )));
      await tester.tap(find.byType(UserCell));
      expect(taps, 1);
    });
  });

  group('status color', () {
    testWidgets('offline: windowBackgroundWhiteGrayText (UserCell.java:158)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const UserCell(
        name: 'Name',
        status: 'last seen recently',
      )));
      expect(
        _statusColor(tester, 'last seen recently'),
        _dayTheme.color(TelegramColorKey.windowBackgroundWhiteGrayText),
      );
    });

    testWidgets('online: telegram_color_text (UserCell.java:159, 716-718)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const UserCell(
        name: 'Name',
        status: 'online',
        online: true,
      )));
      expect(
        _statusColor(tester, 'online'),
        _dayTheme.color(TelegramColorKey.telegram_color_text),
      );
    });

    testWidgets('custom status keys are honored (setStatusColors, '
        'UserCell.java:500-503)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const UserCell(
        name: 'Name',
        status: 'online',
        online: true,
        statusOnlineColorKey: TelegramColorKey.windowBackgroundWhiteBlueText4,
      )));
      expect(
        _statusColor(tester, 'online'),
        _dayTheme.color(TelegramColorKey.windowBackgroundWhiteBlueText4),
      );
    });
  });

  group('add button', () {
    testWidgets(
        'radius-14 featuredStickers_addButton round rect, 28dp tall at '
        '(top 15, end 14), buttonText 14dp label',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const UserCell(
        name: 'Name',
        addButtonText: 'Add',
      )));
      final Finder box = find.ancestor(
        of: find.text('Add'),
        matching: find.byType(DecoratedBox),
      );
      final BoxDecoration decoration =
          tester.widget<DecoratedBox>(box).decoration as BoxDecoration;
      // filledRectByKey(key_featuredStickers_addButton, 14)
      // (UserCell.java:147).
      expect(
        decoration.color,
        _dayTheme.color(TelegramColorKey.featuredStickers_addButton),
      );
      expect(
        decoration.borderRadius,
        BorderRadius.circular(kUserCellAddButtonRadius),
      );
      // Frame: height 28 at top 15, trailing 14 (UserCell.java:150).
      final Rect rect = tester.getRect(box);
      expect(rect.height, 28.0);
      expect(rect.top, 15.0);
      expect(rect.right, 800.0 - 14.0);
      // Label: 14dp buttonText (UserCell.java:144-145) with 17dp side
      // padding (UserCell.java:149).
      final TextStyle style = tester.widget<Text>(find.text('Add')).style!;
      expect(style.fontSize, 14.0);
      expect(
        style.color,
        _dayTheme.color(TelegramColorKey.featuredStickers_buttonText),
      );
      expect(tester.getTopLeft(find.text('Add')).dx, rect.left + 17.0);
    });

    testWidgets('reserves ceil(textWidth + 48) next to the name/status '
        '(UserCell.java:151, 191)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const UserCell(
        name: 'Name',
        status: 'Status',
        addButtonText: 'Add',
      )));
      final double reserve = _addReserve('Add');
      expect(_textBox(tester, 'Name').right, 800.0 - 28.0 - reserve);
      expect(_textBox(tester, 'Status').right, 800.0 - 28.0 - reserve);
    });

    testWidgets('tap fires onAddTap, not the row onTap',
        (WidgetTester tester) async {
      int addTaps = 0;
      int rowTaps = 0;
      await tester.pumpWidget(_host(UserCell(
        name: 'Name',
        addButtonText: 'Add',
        onAddTap: () => addTaps++,
        onTap: () => rowTaps++,
      )));
      await tester.tap(find.text('Add'));
      expect(addTaps, 1);
      expect(rowTaps, 0);
      // Tapping outside the button still fires the row.
      await tester.tapAt(tester.getCenter(find.text('Name')));
      expect(addTaps, 1);
      expect(rowTaps, 1);
    });
  });

  group('divider', () {
    testWidgets('adds one physical pixel at the 68dp inset '
        '(UserCell.java:497, 773)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const UserCell(
        name: 'Name',
        divider: true,
      )));
      // Default test devicePixelRatio is 3.0: 58dp + 1px = 58 + 1/3.
      expect(tester.getSize(find.byType(UserCell)).height,
          closeTo(58.0 + 1.0 / 3.0, 0.001));
      final TextCellDividerPainter painter =
          _cellPaint(tester).foregroundPainter! as TextCellDividerPainter;
      expect(painter.inset, 68.0);
      expect(painter.thickness, closeTo(1.0 / 3.0, 0.001));
      expect(painter.color, _dayTheme.color(TelegramColorKey.divider));
    });

    testWidgets('no divider: exactly 58dp and no painter',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const UserCell(name: 'Name')));
      expect(tester.getSize(find.byType(UserCell)).height, 58.0);
      expect(_cellPaint(tester).foregroundPainter, isNull);
    });

    testWidgets('dividerInset override', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const UserCell(
        name: 'Name',
        divider: true,
        dividerInset: 20.0,
      )));
      final TextCellDividerPainter painter =
          _cellPaint(tester).foregroundPainter! as TextCellDividerPainter;
      expect(painter.inset, 20.0);
    });
  });

  group('theme keys', () {
    testWidgets('night theme resolves every key from the night palette',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const UserCell(
          name: 'Name',
          status: 'online',
          online: true,
          addButtonText: 'Add',
          divider: true,
        ),
        theme: _nightTheme,
      ));
      expect(
        tester.widget<Text>(find.text('Name')).style!.color,
        _nightTheme.color(TelegramColorKey.windowBackgroundWhiteBlackText),
      );
      expect(
        _statusColor(tester, 'online'),
        _nightTheme.color(TelegramColorKey.telegram_color_text),
      );
      final BoxDecoration decoration = tester
          .widget<DecoratedBox>(find.ancestor(
            of: find.text('Add'),
            matching: find.byType(DecoratedBox),
          ))
          .decoration as BoxDecoration;
      expect(
        decoration.color,
        _nightTheme.color(TelegramColorKey.featuredStickers_addButton),
      );
      expect(
        tester.widget<Text>(find.text('Add')).style!.color,
        _nightTheme.color(TelegramColorKey.featuredStickers_buttonText),
      );
      expect(
        (_cellPaint(tester).foregroundPainter! as TextCellDividerPainter)
            .color,
        _nightTheme.color(TelegramColorKey.divider),
      );
      // Day and night must actually differ for the keys under test.
      expect(
        _nightTheme.color(TelegramColorKey.windowBackgroundWhiteBlackText),
        isNot(_dayTheme.color(TelegramColorKey.windowBackgroundWhiteBlackText)),
      );
    });

    testWidgets('resources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color override = Color(0xFF123456);
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return UserCell(
          name: 'Name',
          status: 'online',
          online: true,
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.telegram_color_text: override,
            },
          ),
        );
      })));
      expect(_statusColor(tester, 'online'), override);
    });
  });
}
