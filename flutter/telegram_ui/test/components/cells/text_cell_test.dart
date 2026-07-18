// Tests for lib/src/components/cells/text_cell.dart (ARCHITECTURE.md
// section 6, row "TextCell"), golden-free:
//
//  * geometry: 50dp row (60dp with subtitle, ThemeActivity.java:2688), text
//    left 23dp / 58dp over an icon (TextCell.java:61-63, 79), value right
//    inset leftPadding - 6 (TextCell.java:255), switch 37x20 @ 22dp
//    (TextCell.java:140);
//  * the 1-physical-px divider and its 20/58/72dp insets (TextCell.java:213,
//    835);
//  * TgSwitch toggle visuals: 200ms progress animation (Switch.java:238),
//    thumb travel x + 7 + 17 * progress (Switch.java:384), track color lerp
//    (Switch.java:425-450);
//  * color keys and the resources override;
//  * disabled 0.5 alpha (TextCell.java:221-236).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/cells/text_cell.dart';
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

CustomPaint _cellPaint(WidgetTester tester) => tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byType(TextCell),
            matching: find.byType(CustomPaint),
          )
          .first,
    );

TgSwitchPainter _switchPainter(WidgetTester tester) =>
    tester
        .widget<CustomPaint>(find.descendant(
          of: find.byType(TgSwitch),
          matching: find.byType(CustomPaint),
        ))
        .painter as TgSwitchPainter;

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kTextCellHeight, 50.0); // TextCell.java:62
      expect(kTextCellSubtitleHeight, 60.0); // ThemeActivity.java:2688
      expect(kTextCellLeftPadding, 23.0); // TextCell.java:79
      expect(kTextCellImageLeft, 16.0); // TextCell.java:63
      expect(kTextCellOffsetFromImage, 58.0); // TextCell.java:61
      expect(kTextCellTitleTextSize, 16.0); // TextCell.java:98
      expect(kTextCellSubtitleTextSize, 13.0); // TextCell.java:105
      expect(kTextCellValueTextSize, 16.0); // TextCell.java:113
      expect(kTextCellTitleSubtitleGap, 2.0); // TextCell.java:269
      expect(kTextCellTitleSubtitleGapTall, 4.0); // TextCell.java:269
      expect(kTextCellDividerInsetPlain, 20.0); // TextCell.java:835
      expect(kTextCellDividerInsetIcon, 58.0); // TextCell.java:835
      expect(kTextCellDividerInsetInDialogs, 72.0); // TextCell.java:835
      expect(kTextCellSwitchEndInset, 22.0); // TextCell.java:140
      expect(kTextCellDisabledAlpha, 0.5); // TextCell.java:227-236
      // Switch (TextCell.java:140, 211; Switch.java:380-384, 448-450, 497).
      expect(kTgSwitchSize, const Size(37, 20));
      expect(kTgSwitchTrackWidth, 31.0);
      expect(kTgSwitchTrackHeight, 14.0);
      expect(kTgSwitchTrackRadius, 7.0);
      expect(kTgSwitchThumbRadius, 10.0);
      expect(kTgSwitchThumbCoreRadius, 8.0);
      expect(kTgSwitchDuration, const Duration(milliseconds: 200));
    });

    test('dividerInsetFor mirrors TextCell.java:835', () {
      expect(TextCell.dividerInsetFor(hasIcon: false), 20.0);
      expect(TextCell.dividerInsetFor(hasIcon: false, inDialogs: true), 20.0);
      expect(TextCell.dividerInsetFor(hasIcon: true), 58.0);
      expect(TextCell.dividerInsetFor(hasIcon: true, inDialogs: true), 72.0);
    });

    test('thumbCenterX: x + dp(7) + dp(17) * progress (Switch.java:384)', () {
      // x = (37 - 31) / 2 = 3.
      expect(TgSwitch.thumbCenterX(0.0), 10.0);
      expect(TgSwitch.thumbCenterX(1.0), 27.0);
      expect(TgSwitch.thumbCenterX(0.5), 18.5);
    });
  });

  group('geometry', () {
    testWidgets('50dp tall, title at 23dp, vertically centered +1dp',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TextCell(title: 'Title')));
      expect(tester.getSize(find.byType(TextCell)), const Size(800, 50));
      final Offset topLeft = tester.getTopLeft(find.text('Title'));
      expect(topLeft.dx, 23.0); // leftPadding (TextCell.java:79, 266)
      // (50 - 16) / 2 + dp(1) (TextCell.java:275).
      expect(topLeft.dy, closeTo(18.0, 0.001));
    });

    testWidgets('icon at 16dp centered; title shifts to 58dp',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TextCell(
        title: 'Title',
        icon: SizedBox(width: 24, height: 24),
      )));
      final Rect icon = tester.getRect(find.byType(SizedBox).last);
      expect(icon.left, 16.0); // imageLeft (TextCell.java:63, 280)
      expect(icon.top, (50 - 24) / 2); // centered
      expect(icon.size, const Size(24, 24));
      // offsetFromImage (TextCell.java:61, 266).
      expect(tester.getTopLeft(find.text('Title')).dx, 58.0);
    });

    testWidgets('subtitle: 60dp default height, 4dp gap',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TextCell(
        title: 'Title',
        subtitle: 'Subtitle',
      )));
      // Callers set heightDp = 60 for subtitle rows
      // (ThemeActivity.java:2688, 2697).
      expect(tester.getSize(find.byType(TextCell)), const Size(800, 60));
      final Offset title = tester.getTopLeft(find.text('Title'));
      final Offset subtitle = tester.getTopLeft(find.text('Subtitle'));
      // (60 - 16 - 13 - 4) / 2 + 1 (TextCell.java:269-270, margin 4 as
      // heightDp > 50).
      expect(title.dy, closeTo(14.5, 0.001));
      expect(subtitle.dy - title.dy, closeTo(16.0 + 4.0, 0.001));
    });

    testWidgets('subtitle on a forced 50dp row uses the 2dp gap',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TextCell(
        title: 'Title',
        subtitle: 'Subtitle',
        height: 50,
      )));
      expect(tester.getSize(find.byType(TextCell)), const Size(800, 50));
      final double titleBottom =
          tester.getBottomLeft(find.text('Title')).dy;
      final double subtitleTop = tester.getTopLeft(find.text('Subtitle')).dy;
      // margin = heightDp > 50 ? 4 : 2 (TextCell.java:269).
      expect(subtitleTop - titleBottom, closeTo(2.0, 0.001));
    });

    testWidgets('value right edge at leftPadding - 6, shifted -2dp',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TextCell(
        title: 'Title',
        value: 'Value',
      )));
      final Rect value = tester.getRect(find.text('Value'));
      // width - dp(leftPadding - 6) (TextCell.java:255).
      expect(value.right, 800.0 - 17.0);
      // centered + setTranslationY(dp(-2)) (TextCell.java:116, 254).
      expect(value.top, closeTo((50 - 16) / 2 - 2.0, 0.001));
    });

    testWidgets('switch slot: 37x20 at 22dp from the trailing edge, centered',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TextCell(
        title: 'Title',
        checked: true,
      )));
      final Rect rect = tester.getRect(find.byType(TgSwitch));
      expect(rect.size, const Size(37, 20)); // TextCell.java:140, 211
      expect(rect.left, 800.0 - 22.0 - 37.0); // TextCell.java:291
      expect(rect.top, (50 - 20) / 2); // TextCell.java:290
    });

    testWidgets('RTL mirrors title, switch, and divider inset',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const TextCell(title: 'Title', checked: false, divider: true),
        textDirection: TextDirection.rtl,
      ));
      // TextCell.java:264: RTL text right edge at width - leftPadding.
      expect(tester.getTopRight(find.text('Title')).dx, 800.0 - 23.0);
      // TextCell.java:291: RTL switch at dp(22) from the left.
      expect(tester.getRect(find.byType(TgSwitch)).left, 22.0);
      final TextCellDividerPainter painter =
          _cellPaint(tester).foregroundPainter! as TextCellDividerPainter;
      expect(painter.textDirection, TextDirection.rtl);
    });
  });

  group('divider', () {
    testWidgets('adds one physical pixel to the height (TextCell.java:213)',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(const TextCell(title: 'T', divider: true)));
      // Default test devicePixelRatio is 3.0: 50dp + 1px = 50 + 1/3.
      expect(tester.getSize(find.byType(TextCell)).height,
          closeTo(50.0 + 1.0 / 3.0, 0.001));
      final TextCellDividerPainter painter =
          _cellPaint(tester).foregroundPainter! as TextCellDividerPainter;
      expect(painter.thickness, closeTo(1.0 / 3.0, 0.001));
      expect(painter.color, _dayTheme.color(TelegramColorKey.divider));
    });

    testWidgets('respects an ambient MediaQuery devicePixelRatio',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const MediaQuery(
        data: MediaQueryData(devicePixelRatio: 2.0),
        child: TextCell(title: 'T', divider: true),
      )));
      expect(tester.getSize(find.byType(TextCell)).height, 50.5);
    });

    testWidgets('no divider: exactly 50dp and no painter',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TextCell(title: 'T')));
      expect(tester.getSize(find.byType(TextCell)).height, 50.0);
      expect(_cellPaint(tester).foregroundPainter, isNull);
    });

    testWidgets('insets: 20 plain / 58 icon / 72 inDialogs / override',
        (WidgetTester tester) async {
      Future<double> insetOf(TextCell cell) async {
        await tester.pumpWidget(_host(cell));
        return (_cellPaint(tester).foregroundPainter!
                as TextCellDividerPainter)
            .inset;
      }

      expect(await insetOf(const TextCell(title: 'T', divider: true)), 20.0);
      expect(
        await insetOf(const TextCell(
          title: 'T',
          divider: true,
          icon: SizedBox(width: 24, height: 24),
        )),
        58.0,
      );
      expect(
        await insetOf(const TextCell(
          title: 'T',
          divider: true,
          inDialogs: true,
          icon: SizedBox(width: 24, height: 24),
        )),
        72.0,
      );
      // inDialogs without an icon still uses 20 (TextCell.java:835).
      expect(
        await insetOf(
            const TextCell(title: 'T', divider: true, inDialogs: true)),
        20.0,
      );
      expect(
        await insetOf(
            const TextCell(title: 'T', divider: true, dividerInset: 33.0)),
        33.0,
      );
    });
  });

  group('color keys', () {
    testWidgets('title/subtitle/value/icon default keys',
        (WidgetTester tester) async {
      Color? iconColor;
      await tester.pumpWidget(_host(TextCell(
        title: 'Title',
        subtitle: 'Subtitle',
        value: 'Value',
        icon: Builder(builder: (BuildContext context) {
          iconColor = IconTheme.of(context).color;
          return const SizedBox(width: 24, height: 24);
        }),
      )));
      expect(
        tester.widget<Text>(find.text('Title')).style!.color,
        _dayTheme.color(TelegramColorKey.windowBackgroundWhiteBlackText),
      ); // TextCell.java:97
      expect(
        tester.widget<Text>(find.text('Subtitle')).style!.color,
        _dayTheme.color(TelegramColorKey.windowBackgroundWhiteGrayText),
      ); // TextCell.java:104
      expect(
        tester.widget<Text>(find.text('Value')).style!.color,
        _dayTheme.color(TelegramColorKey.windowBackgroundWhiteValueText),
      ); // TextCell.java:111
      expect(
        iconColor,
        _dayTheme.color(TelegramColorKey.windowBackgroundWhiteGrayIcon),
      ); // TextCell.java:130
    });

    testWidgets('resources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color override = Color(0xFF123456);
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return TextCell(
          title: 'Title',
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.windowBackgroundWhiteBlackText: override,
            },
          ),
        );
      })));
      expect(tester.widget<Text>(find.text('Title')).style!.color, override);
    });
  });

  group('disabled state', () {
    testWidgets('text at 0.5 alpha and taps ignored (TextCell.java:221-236)',
        (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_host(TextCell(
        title: 'Title',
        enabled: false,
        onTap: () => taps++,
      )));
      final Opacity opacity = tester.widget<Opacity>(find.descendant(
        of: find.byType(TextCell),
        matching: find.byType(Opacity),
      ));
      expect(opacity.opacity, 0.5);
      await tester.tap(find.byType(TextCell), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('enabled: full alpha and onTap fires',
        (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_host(TextCell(
        title: 'Title',
        onTap: () => taps++,
      )));
      final Opacity opacity = tester.widget<Opacity>(find.descendant(
        of: find.byType(TextCell),
        matching: find.byType(Opacity),
      ));
      expect(opacity.opacity, 1.0);
      await tester.tap(find.byType(TextCell));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('disabled switch row does not toggle',
        (WidgetTester tester) async {
      final List<bool> changes = <bool>[];
      await tester.pumpWidget(_host(TextCell(
        title: 'Title',
        enabled: false,
        checked: false,
        onChanged: changes.add,
      )));
      await tester.tap(find.byType(TextCell), warnIfMissed: false);
      await tester.tap(find.byType(TgSwitch), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
    });
  });

  group('switch wiring', () {
    testWidgets('tapping the row toggles via onChanged',
        (WidgetTester tester) async {
      final List<bool> changes = <bool>[];
      await tester.pumpWidget(_host(TextCell(
        title: 'Title',
        checked: false,
        onChanged: changes.add,
      )));
      await tester.tap(find.byType(TextCell));
      await tester.pump();
      expect(changes, <bool>[true]);
    });

    testWidgets('explicit onTap wins over the toggle convenience',
        (WidgetTester tester) async {
      final List<bool> changes = <bool>[];
      int taps = 0;
      await tester.pumpWidget(_host(TextCell(
        title: 'Title',
        checked: false,
        onChanged: changes.add,
        onTap: () => taps++,
      )));
      // Tap the row outside the switch slot.
      await tester.tapAt(tester.getCenter(find.text('Title')));
      await tester.pump();
      expect(taps, 1);
      expect(changes, isEmpty);
    });
  });

  group('TgSwitch visuals', () {
    testWidgets('unchecked: progress 0, switchTrack colors',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgSwitch(checked: false)));
      expect(tester.getSize(find.byType(TgSwitch)), const Size(37, 20));
      final TgSwitchPainter painter = _switchPainter(tester);
      expect(painter.progress, 0.0);
      // TextCell recipe (TextCell.java:139).
      expect(painter.trackColor,
          _dayTheme.color(TelegramColorKey.switchTrack));
      expect(painter.thumbColor,
          _dayTheme.color(TelegramColorKey.windowBackgroundWhite));
    });

    testWidgets('checked: progress 1 without animation on first build',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgSwitch(checked: true)));
      final TgSwitchPainter painter = _switchPainter(tester);
      expect(painter.progress, 1.0); // Switch.java:287, unanimated
      expect(painter.trackColor,
          _dayTheme.color(TelegramColorKey.switchTrackChecked));
    });

    testWidgets('toggle animates the progress over 200ms (Switch.java:238)',
        (WidgetTester tester) async {
      bool checked = false;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return TgSwitch(
            checked: checked,
            onChanged: (bool value) => setState(() => checked = value),
          );
        },
      )));
      final TgSwitchState state = tester.state(find.byType(TgSwitch));

      await tester.tap(find.byType(TgSwitch));
      await tester.pump(); // rebuild with checked = true; animation starts
      expect(checked, isTrue);
      expect(state.debugProgress, 0.0);

      // AccelerateDecelerateInterpolator at t = 0.5 is exactly 0.5.
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.debugProgress, closeTo(0.5, 1e-9));
      expect(_switchPainter(tester).progress, closeTo(0.5, 1e-9));
      // Mid-flight the track color is between the two keys.
      expect(
        _switchPainter(tester).trackColor,
        Color.lerp(
          _dayTheme.color(TelegramColorKey.switchTrack),
          _dayTheme.color(TelegramColorKey.switchTrackChecked),
          state.debugProgress,
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(state.debugProgress, 1.0);
      await tester.pumpAndSettle();
      expect(_switchPainter(tester).progress, 1.0);
      expect(_switchPainter(tester).trackColor,
          _dayTheme.color(TelegramColorKey.switchTrackChecked));

      // And back.
      await tester.tap(find.byType(TgSwitch));
      await tester.pumpAndSettle();
      expect(checked, isFalse);
      expect(state.debugProgress, 0.0);
    });

    testWidgets('null onChanged is inert', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgSwitch(checked: false)));
      final TgSwitchState state = tester.state(find.byType(TgSwitch));
      await tester.tap(find.byType(TgSwitch));
      await tester.pumpAndSettle();
      expect(state.debugProgress, 0.0);
    });

    testWidgets('custom color keys are honored (Switch.java defaults)',
        (WidgetTester tester) async {
      // The bare Java Switch defaults (Switch.java:60-63).
      await tester.pumpWidget(_host(const TgSwitch(
        checked: false,
        trackColorKey: TelegramColorKey.fill_RedNormal,
        trackCheckedColorKey: TelegramColorKey.switch2TrackChecked,
      )));
      expect(_switchPainter(tester).trackColor,
          _dayTheme.color(TelegramColorKey.fill_RedNormal));
    });
  });
}
