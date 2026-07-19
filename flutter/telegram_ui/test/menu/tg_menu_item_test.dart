// Tests for lib/src/menu/tg_menu_item.dart (PLAN_UIKIT.md M4), golden-free:
//
//  * constants against the Java values (ActionBarMenuSubItem.java, cited per
//    constant);
//  * row height forced 48 (ActionBarMenuSubItem.java:126-131);
//  * indent 18 -> 61 (18 + 43) with an icon, 52 (18 + 34) with the check
//    (ActionBarMenuSubItem.java:84, 217, 112-113), RTL mirror;
//  * right icon frame + 8dp icon-side padding (ActionBarMenuSubItem.java:
//    159-176);
//  * subtext metrics: label/subtext centers at 19/29dp of the 48dp row
//    (ActionBarMenuSubItem.java:356-378);
//  * pressed selector `dialogButtonSelector` with 12dp first/last corner
//    rounding, own flags and via TgMenuRowScope (ActionBarMenuSubItem.java:
//    47, 81, 395-416);
//  * disabled 0.5 alpha + non-tappable (ActionBarPopupWindow.java:886);
//  * check slot: CheckBoxBase arm geometry, 200ms toggle
//    (CheckBoxBase.java:277-292, 623-645);
//  * semantics (button/enabled/checked);
//  * theme resolution + resources override in both directions.

import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/menu/tg_menu_item.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_resources.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

const double _hostWidth = 300.0;

/// A [TelegramResources] view over the day theme, the parent for sparse
/// [ResourcesOverride] layers in tests.
class _ThemeResources extends TelegramResources {
  const _ThemeResources(this.data);

  final TelegramThemeData data;

  @override
  Color getColor(int key) => data.color(key);
}

Widget _host(
  Widget child, {
  TextDirection textDirection = TextDirection.ltr,
}) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: textDirection,
      child: Center(child: SizedBox(width: _hostWidth, child: child)),
    ),
  );
}

Finder get _item => find.byType(TgMenuItem);

DecoratedBox _selectorBox(WidgetTester tester) => tester.widget<DecoratedBox>(
      find.descendant(of: _item, matching: find.byType(DecoratedBox)).first,
    );

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kTgMenuItemHeight, 48.0); // ActionBarMenuSubItem.java:51, 126-131
      expect(kTgMenuItemHorizontalPadding, 18.0); // :84
      expect(kTgMenuItemRightIconSidePadding, 8.0); // :176
      expect(kTgMenuItemTextSize, 16.0); // :97
      expect(kTgMenuItemSubtextSize, 13.0); // :365
      expect(kTgMenuItemSubtextMargin, 10.0); // :367, 374
      expect(kTgMenuItemIconIndent, 43.0); // :217
      expect(kTgMenuItemCheckIndent, 34.0); // :112-113
      expect(kTgMenuItemIconFrameHeight, 40.0); // :89
      expect(kTgMenuItemIconSize, 24.0); // :337
      expect(kTgMenuItemCheckSize, 26.0); // :106
      expect(kTgMenuItemRightIconWidth, 24.0); // :167
      expect(kTgMenuItemRightIconTextMargin, 32.0); // :171-173
      expect(kTgMenuItemSelectorRadius, 12.0); // :47
      // ActionBarPopupWindow.java:886, 908, 989.
      expect(kTgMenuItemDisabledAlpha, 0.5);
      // CheckBoxBase.java:277, 292.
      expect(kTgMenuItemCheckDuration, const Duration(milliseconds: 200));
      expect(TgMenuCheckPainter.strokeWidth, 1.9); // CheckBoxBase.java:120
      expect(TgMenuCheckPainter.longArm, 9.0); // CheckBoxBase.java:630
      expect(TgMenuCheckPainter.shortArm, 4.0); // CheckBoxBase.java:631
    });
  });

  group('geometry', () {
    testWidgets('row is exactly 48dp tall and fills the width '
        '(ActionBarMenuSubItem.java:126-131)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgMenuItem(text: 'Reply')));
      expect(tester.getSize(_item), const Size(_hostWidth, kTgMenuItemHeight));
    });

    testWidgets('text: 16dp regular actionBarDefaultSubmenuItem at the 18dp '
        'padding (ActionBarMenuSubItem.java:84, 91-98)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgMenuItem(text: 'Reply')));
      final Rect item = tester.getRect(_item);
      final Rect text = tester.getRect(find.text('Reply'));
      expect(text.left, item.left + kTgMenuItemHorizontalPadding);
      expect(text.center.dy, item.center.dy);

      final Text label = tester.widget<Text>(find.text('Reply'));
      expect(label.style!.fontSize, kTgMenuItemTextSize);
      expect(label.style!.fontWeight, FontWeight.w400);
      expect(label.maxLines, 1);
      expect(label.overflow, TextOverflow.ellipsis);
      expect(
        label.style!.color,
        _dayTheme.color(TelegramColorKey.actionBarDefaultSubmenuItem),
      );
    });

    testWidgets('leading icon indents the text 43dp and is tinted '
        'actionBarDefaultSubmenuItemIcon (ActionBarMenuSubItem.java:86-89, '
        '217)', (WidgetTester tester) async {
      const Key iconKey = ValueKey<String>('icon');
      await tester.pumpWidget(_host(const TgMenuItem(
        text: 'Reply',
        icon: SizedBox(key: iconKey, width: 24, height: 24),
      )));
      final Rect item = tester.getRect(_item);
      expect(
        tester.getRect(find.text('Reply')).left,
        item.left + kTgMenuItemHorizontalPadding + kTgMenuItemIconIndent,
      );
      final Rect icon = tester.getRect(find.byKey(iconKey));
      expect(icon.left, item.left + kTgMenuItemHorizontalPadding);
      // 40dp frame, CENTER_VERTICAL (ActionBarMenuSubItem.java:89).
      expect(icon.center.dy, item.center.dy);
      expect(
        IconTheme.of(tester.element(find.byKey(iconKey))).color,
        _dayTheme.color(TelegramColorKey.actionBarDefaultSubmenuItemIcon),
      );
      expect(
        IconTheme.of(tester.element(find.byKey(iconKey))).size,
        kTgMenuItemIconSize,
      );
    });

    testWidgets('RTL mirrors the indent (ActionBarMenuSubItem.java:217)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const TgMenuItem(
          text: 'Reply',
          icon: SizedBox(width: 24, height: 24),
        ),
        textDirection: TextDirection.rtl,
      ));
      final Rect item = tester.getRect(_item);
      expect(
        tester.getRect(find.text('Reply')).right,
        item.right - kTgMenuItemHorizontalPadding - kTgMenuItemIconIndent,
      );
    });

    testWidgets('right icon: 24dp end frame, icon-side padding 8dp '
        '(ActionBarMenuSubItem.java:159-176)', (WidgetTester tester) async {
      const Key rightKey = ValueKey<String>('right');
      await tester.pumpWidget(_host(const TgMenuItem(
        text: 'Reply',
        rightIcon: SizedBox(key: rightKey, width: 24, height: 24),
      )));
      final Rect item = tester.getRect(_item);
      final Rect right = tester.getRect(find.byKey(rightKey));
      expect(right.right, item.right - kTgMenuItemRightIconSidePadding);
      expect(right.width, kTgMenuItemRightIconWidth);
      expect(right.center.dy, item.center.dy);
    });

    testWidgets('subtext: 13dp groupcreate_sectionText; label/subtext '
        'centers at 19/29dp (ActionBarMenuSubItem.java:356-378)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgMenuItem(
        text: 'Auto-delete',
        subtext: 'After 1 week',
      )));
      final Rect item = tester.getRect(_item);
      // CENTER_VERTICAL with bottomMargin 10 / topMargin 10
      // (ActionBarMenuSubItem.java:367, 374): centers at 24 -/+ 5.
      expect(
        tester.getRect(find.text('Auto-delete')).center.dy,
        item.top + kTgMenuItemHeight / 2 - kTgMenuItemSubtextMargin / 2,
      );
      expect(
        tester.getRect(find.text('After 1 week')).center.dy,
        item.top + kTgMenuItemHeight / 2 + kTgMenuItemSubtextMargin / 2,
      );
      final Text subtext = tester.widget<Text>(find.text('After 1 week'));
      expect(subtext.style!.fontSize, kTgMenuItemSubtextSize);
      expect(
        subtext.style!.color,
        _dayTheme.color(TelegramColorKey.groupcreate_sectionText),
      );
    });
  });

  group('pressed selector', () {
    testWidgets('press fills dialogButtonSelector, square by default '
        '(ActionBarMenuSubItem.java:81, 414-416)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgMenuItem(text: 'Reply', onTap: () {})));
      BoxDecoration decoration() =>
          _selectorBox(tester).decoration as BoxDecoration;
      expect(decoration().color, const Color(0x00000000));

      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(_item));
      await tester.pump();
      expect(
        decoration().color,
        _dayTheme.color(TelegramColorKey.dialogButtonSelector),
      );
      // Middle rows keep square corners (ActionBarMenuSubItem.java:415).
      expect(decoration().borderRadius, BorderRadius.zero);

      await gesture.up();
      await tester.pump();
      expect(decoration().color, const Color(0x00000000));
    });

    testWidgets('roundTop/roundBottom round the corners at 12dp '
        '(ActionBarMenuSubItem.java:47, 404-416)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgMenuItem(
        text: 'Reply',
        roundTop: true,
        onTap: () {},
      )));
      final BoxDecoration decoration =
          _selectorBox(tester).decoration as BoxDecoration;
      expect(
        decoration.borderRadius,
        const BorderRadius.vertical(
          top: Radius.circular(kTgMenuItemSelectorRadius),
        ),
      );
    });

    testWidgets('TgMenuRowScope drives the flags when the row has none '
        '(ActionBarPopupWindow.java:612-643)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgMenuRowScope(
        roundTop: true,
        roundBottom: true,
        child: TgMenuItem(text: 'Reply', onTap: () {}),
      )));
      final BoxDecoration decoration =
          _selectorBox(tester).decoration as BoxDecoration;
      expect(
        decoration.borderRadius,
        BorderRadius.circular(kTgMenuItemSelectorRadius),
      );
    });

    testWidgets('own flags win over the scope', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgMenuRowScope(
        roundTop: true,
        roundBottom: true,
        child: TgMenuItem(
          text: 'Reply',
          roundTop: false,
          roundBottom: false,
          onTap: () {},
        ),
      )));
      final BoxDecoration decoration =
          _selectorBox(tester).decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.zero);
    });
  });

  group('interaction', () {
    testWidgets('tap fires onTap', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_host(TgMenuItem(
        text: 'Reply',
        onTap: () => taps++,
      )));
      await tester.tap(_item);
      expect(taps, 1);
    });

    testWidgets('disabled row draws at 0.5 alpha and ignores taps '
        '(ActionBarPopupWindow.java:886)', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_host(TgMenuItem(
        text: 'Reply',
        enabled: false,
        onTap: () => taps++,
      )));
      final Opacity opacity = tester.widget<Opacity>(
        find.descendant(of: _item, matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, kTgMenuItemDisabledAlpha);
      await tester.tap(_item);
      expect(taps, 0);
    });

    testWidgets('enabled row content is opaque', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgMenuItem(text: 'Reply', onTap: () {})));
      final Opacity opacity = tester.widget<Opacity>(
        find.descendant(of: _item, matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, 1.0);
    });
  });

  group('check', () {
    Finder checkPaint() => find.descendant(
          of: _item,
          matching: find.byWidgetPredicate(
            (Widget w) => w is CustomPaint && w.painter is TgMenuCheckPainter,
          ),
        );
    TgMenuCheckPainter painter(WidgetTester tester) =>
        tester.widget<CustomPaint>(checkPaint()).painter!
            as TgMenuCheckPainter;

    testWidgets('checked row shows the 26dp check slot at the 34dp indent '
        '(ActionBarMenuSubItem.java:104-113)', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(const TgMenuItem(text: 'Mute', checked: true)),
      );
      final Rect item = tester.getRect(_item);
      expect(
        tester.getRect(find.text('Mute')).left,
        item.left + kTgMenuItemHorizontalPadding + kTgMenuItemCheckIndent,
      );
      expect(
        tester.getSize(checkPaint()),
        const Size.square(kTgMenuItemCheckSize),
      );
      expect(painter(tester).progress, 1.0);
      // `checkView.setColor(-1, -1, key_actionBarDefaultSubmenuItem)`
      // (ActionBarMenuSubItem.java:108).
      expect(
        painter(tester).color,
        _dayTheme.color(TelegramColorKey.actionBarDefaultSubmenuItem),
      );
    });

    testWidgets('unchecked keeps progress 0; toggling animates over 200ms '
        '(CheckBoxBase.java:277-292)', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(const TgMenuItem(text: 'Mute', checked: false)),
      );
      expect(painter(tester).progress, 0.0);

      await tester.pumpWidget(
        _host(const TgMenuItem(text: 'Mute', checked: true)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final double mid = painter(tester).progress;
      expect(mid, greaterThan(0.0));
      expect(mid, lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(painter(tester).progress, 1.0);
    });

    testWidgets('a leading icon wins the slot over the check',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgMenuItem(
        text: 'Mute',
        checked: true,
        icon: SizedBox(width: 24, height: 24),
      )));
      expect(checkPaint(), findsNothing);
      expect(
        tester.getRect(find.text('Mute')).left,
        tester.getRect(_item).left +
            kTgMenuItemHorizontalPadding +
            kTgMenuItemIconIndent,
      );
    });
  });

  group('semantics', () {
    testWidgets('row reports button + enabled '
        '(ActionBarMenuSubItem.java:145-153)', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(TgMenuItem(text: 'Reply', onTap: () {})));
      final SemanticsData data =
          tester.getSemantics(_item).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('disabled row reports not enabled',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(TgMenuItem(
        text: 'Reply',
        enabled: false,
        onTap: () {},
      )));
      final SemanticsData data =
          tester.getSemantics(_item).getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });

    testWidgets('checked row reports the checked state '
        '(ActionBarMenuSubItem.java:148-152)', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const TgMenuItem(text: 'Mute', checked: true)),
      );
      expect(
        tester.getSemantics(_item).getSemanticsData().flagsCollection.isChecked,
        CheckedState.isTrue,
      );

      await tester.pumpWidget(
        _host(const TgMenuItem(text: 'Mute', checked: false)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(_item).getSemanticsData().flagsCollection.isChecked,
        CheckedState.isFalse,
      );
      handle.dispose();
    });
  });

  group('theme', () {
    testWidgets('resources override recolors text and selector in both '
        'directions', (WidgetTester tester) async {
      const Color overrideText = Color(0xFF123456);
      final TelegramResources resources = ResourcesOverride(
        parent: _ThemeResources(_dayTheme),
        overrides: const <int, Color>{
          TelegramColorKey.actionBarDefaultSubmenuItem: overrideText,
        },
      );
      await tester.pumpWidget(_host(TgMenuItem(
        text: 'Reply',
        resources: resources,
        onTap: () {},
      )));
      expect(
        tester.widget<Text>(find.text('Reply')).style!.color,
        overrideText,
      );

      // Without the override the ambient theme wins.
      await tester.pumpWidget(_host(TgMenuItem(text: 'Reply', onTap: () {})));
      expect(
        tester.widget<Text>(find.text('Reply')).style!.color,
        _dayTheme.color(TelegramColorKey.actionBarDefaultSubmenuItem),
      );
    });
  });

  group('check painter', () {
    test('paints nothing at progress 0 and the two arms at 1 '
        '(CheckBoxBase.java:623-645)', () {
      const TgMenuCheckPainter zero =
          TgMenuCheckPainter(progress: 0.0, color: Color(0xFF000000));
      const TgMenuCheckPainter full =
          TgMenuCheckPainter(progress: 1.0, color: Color(0xFF000000));
      expect(zero.shouldRepaint(full), isTrue);
      expect(
        full.shouldRepaint(
          const TgMenuCheckPainter(progress: 1.0, color: Color(0xFF000000)),
        ),
        isFalse,
      );
    });
  });
}
