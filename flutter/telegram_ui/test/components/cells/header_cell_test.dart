// Tests for lib/src/components/cells/header_cell.dart (ARCHITECTURE.md
// section 6, row "HeaderCell"), golden-free:
//
//  * geometry: 40dp nominal height realized as topMargin(7) +
//    minHeight(height - topMargin) (HeaderCell.java:44, 49-61, 98), 21dp
//    horizontal padding (production call sites), height/margin overrides;
//  * text style: 14dp RobotoMedium (AndroidUtilities.bold(),
//    HeaderCell.java:94-95) in `windowBackgroundWhiteBlueHeader`
//    (HeaderCell.java:49);
//  * the resources override;
//  * disabled 0.5 alpha (HeaderCell.java:142-149).

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/cells/header_cell.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

Widget _host(Widget child, {TextDirection textDirection = TextDirection.ltr}) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: textDirection,
      child: Align(alignment: Alignment.topCenter, child: child),
    ),
  );
}

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kHeaderCellHeight, 40.0); // HeaderCell.java:44
      expect(kHeaderCellTextSize, 14.0); // HeaderCell.java:94
      expect(kHeaderCellPadding, 21.0); // Stars/StarsIntroActivity.java:682
      expect(kHeaderCellTopMargin, 7.0); // HeaderCell.java:49
      expect(kHeaderCellDisabledAlpha, 0.5); // HeaderCell.java:142-149
    });
  });

  group('geometry', () {
    testWidgets('40dp tall; text at 21dp, centered in the min-height box',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const HeaderCell(text: 'Header')));
      // topMargin(7) + minHeight(40 - 7 = 33) (HeaderCell.java:98).
      expect(tester.getSize(find.byType(HeaderCell)), const Size(800, 40));
      final Rect text = tester.getRect(find.text('Header'));
      expect(text.left, 21.0); // padding (HeaderCell.java:101)
      // CENTER_VERTICAL inside the 33dp min-height under the 7dp top margin
      // (HeaderCell.java:97-98).
      expect(text.center.dy, closeTo(7.0 + 33.0 / 2.0, 0.001));
    });

    testWidgets('height override drives the min height (setHeight)',
        (WidgetTester tester) async {
      // PrivacyUsersActivity.java:433 (`headerCell.setHeight(43)`;
      // HeaderCell.java:122-128).
      await tester
          .pumpWidget(_host(const HeaderCell(text: 'Header', height: 43)));
      expect(tester.getSize(find.byType(HeaderCell)).height, 43.0);
    });

    testWidgets('top and bottom margins add up (HeaderCell.java:101)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const HeaderCell(
        text: 'Header',
        topMargin: 14,
        bottomMargin: 5,
      )));
      // 14 + (40 - 14) + 5 (the Adapters/ContactsAdapter.java:431 recipe).
      expect(tester.getSize(find.byType(HeaderCell)).height, 45.0);
      expect(tester.getRect(find.text('Header')).center.dy,
          closeTo(14.0 + 26.0 / 2.0, 0.001));
    });

    testWidgets('RTL mirrors the leading padding',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const HeaderCell(text: 'Header'),
        textDirection: TextDirection.rtl,
      ));
      expect(tester.getTopRight(find.text('Header')).dx, 800.0 - 21.0);
    });
  });

  group('text style and color keys', () {
    testWidgets('14dp RobotoMedium in windowBackgroundWhiteBlueHeader',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const HeaderCell(text: 'Header')));
      final TextStyle style =
          tester.widget<Text>(find.text('Header')).style!;
      expect(style.fontSize, 14.0); // HeaderCell.java:94
      // AndroidUtilities.bold() = rmedium (AndroidUtilities.java:260-269).
      expect(style.fontFamily, 'packages/telegram_ui/RobotoMedium');
      expect(style.fontWeight, FontWeight.w500);
      expect(
        style.color,
        _dayTheme.color(TelegramColorKey.windowBackgroundWhiteBlueHeader),
      ); // HeaderCell.java:49
    });

    testWidgets('custom color key', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const HeaderCell(
        text: 'Header',
        textColorKey: TelegramColorKey.windowBackgroundWhiteBlackText,
      )));
      expect(
        tester.widget<Text>(find.text('Header')).style!.color,
        _dayTheme.color(TelegramColorKey.windowBackgroundWhiteBlackText),
      );
    });

    testWidgets('resources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color override = Color(0xFF654321);
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return HeaderCell(
          text: 'Header',
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.windowBackgroundWhiteBlueHeader: override,
            },
          ),
        );
      })));
      expect(
          tester.widget<Text>(find.text('Header')).style!.color, override);
    });
  });

  group('disabled state', () {
    testWidgets('text at 0.5 alpha (HeaderCell.java:142-149)',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(const HeaderCell(text: 'Header', enabled: false)));
      final Opacity opacity = tester.widget<Opacity>(find.descendant(
        of: find.byType(HeaderCell),
        matching: find.byType(Opacity),
      ));
      expect(opacity.opacity, 0.5);
    });

    testWidgets('enabled: full alpha', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const HeaderCell(text: 'Header')));
      final Opacity opacity = tester.widget<Opacity>(find.descendant(
        of: find.byType(HeaderCell),
        matching: find.byType(Opacity),
      ));
      expect(opacity.opacity, 1.0);
    });
  });

  group('semantics', () {
    testWidgets('is a heading (HeaderCell.java:111)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const HeaderCell(text: 'Header')));
      final SemanticsNode node = tester.getSemantics(find.text('Header'));
      expect(node.flagsCollection.isHeader, isTrue);
    });
  });
}
