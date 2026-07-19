// Tests for lib/src/dialog/tg_alert_dialog.dart (PLAN_UIKIT.md M3),
// golden-free:
//
//  * constants against the Java values (AlertDialog.java, cited per
//    constant);
//  * route motion: pure 150ms fade open/close, no scale
//    (TgMotion.dialogFadeDuration; res/values/styles.xml:139-153);
//  * barrier: black 0.5 (AlertDialog.java:210, 1241-1243), tap-outside
//    dismiss, dimEnabled/dimAlpha overrides;
//  * width: min(356, screenWidth - 48) (AlertDialog.java:1250-1262);
//  * title/message styles, colors and margins (AlertDialog.java:784-794,
//    849-857, 444-456, 893);
//  * button placement LTR + RTL (AlertDialog.java:961-1013), 52dp row and
//    8dp gaps (AlertDialog.java:1053-1055), vertical-stack fallback
//    (AlertDialog.java:932-959, 1222-1226);
//  * destructive + loading button pass-through (AlertDialog.java:231-236,
//    1089, 1313-1335);
//  * items variant: 48dp rows, 23dp padding, 56dp icon indent, pressed
//    selector, tap -> callback + dismiss (AlertDialog.java:238-294,
//    905-922);
//  * theme resolution + resources override in both directions.

import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/buttons/tg_dialog_button.dart';
import 'package:telegram_ui/src/dialog/tg_alert_dialog.dart';
import 'package:telegram_ui/src/foundation/tg_motion.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_resources.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

const Size _screen = Size(800, 600);

/// A [TelegramResources] view over the day theme, the parent for sparse
/// [ResourcesOverride] layers in tests.
class _ThemeResources extends TelegramResources {
  const _ThemeResources(this.data);

  final TelegramThemeData data;

  @override
  Color getColor(int key) => data.color(key);
}

/// A bare app: theme + directionality + media query + navigator with an
/// empty home page.
Widget _app({
  Size size = _screen,
  TextDirection textDirection = TextDirection.ltr,
}) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: textDirection,
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: Navigator(
          onGenerateRoute: (RouteSettings settings) => PageRouteBuilder<void>(
            settings: settings,
            pageBuilder: (BuildContext context, _, _) =>
                const ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
    ),
  );
}

NavigatorState _navigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator));

Finder get _panel => find.byKey(TgAlertDialog.panelKey);

Finder _buttonWithText(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(TgDialogButton));

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kTgAlertDialogCornerRadius, 20.0); // AlertDialog.java:663-664
      expect(kTgAlertDialogMaxWidth, 356.0); // AlertDialog.java:1252-1260
      expect(kTgAlertDialogScreenInset, 48.0); // AlertDialog.java:1250-1262
      // dimAlpha 0.5 (AlertDialog.java:210).
      expect(kTgAlertDialogBarrierColor, const Color(0x80000000));
      expect(kTgAlertDialogHorizontalMargin, 24.0); // AlertDialog.java:784
      expect(kTgAlertDialogTitleTopMargin, 19.0); // AlertDialog.java:794
      expect(kTgAlertDialogTitleBottomMargin, 10.0); // AlertDialog.java:794
      expect(kTgAlertDialogTitleBottomMarginItems, 14.0); // :794
      expect(kTgAlertDialogMessageTopMargin, 19.0); // AlertDialog.java:454
      expect(kTgAlertDialogMessageBottomMargin, 20.0); // AlertDialog.java:455
      expect(kTgAlertDialogItemsBlockMargin, 8.0); // AlertDialog.java:451-452
      expect(kTgAlertDialogMessageItemsGap, 12.0); // AlertDialog.java:116, 893
      expect(kTgAlertDialogButtonRowHeight, 52.0); // AlertDialog.java:1055
      expect(kTgAlertDialogButtonRowPadding, 8.0); // AlertDialog.java:1053
      expect(kTgAlertDialogButtonGap, 8.0); // AlertDialog.java:982-988
      expect(kTgAlertDialogVerticalButtonGap, 6.0); // AlertDialog.java:1224
      expect(kTgAlertDialogVerticalOverflowInset, 64.0); // :952
      expect(kTgAlertDialogButtonMaxWidthInset, 24.0); // AlertDialog.java:396
      expect(kTgAlertDialogItemHeight, 48.0); // AlertDialog.java:266-269
      expect(kTgAlertDialogItemPadding, 23.0); // AlertDialog.java:249
      expect(kTgAlertDialogItemTextSize, 16.0); // AlertDialog.java:262
      expect(kTgAlertDialogItemIconIndent, 56.0); // AlertDialog.java:284
      expect(kTgAlertDialogItemIconFrameHeight, 40.0); // AlertDialog.java:254
    });

    test('route defaults mirror the Java dialog defaults', () {
      final TgAlertDialogRoute<void> route = TgAlertDialogRoute<void>();
      // ~150ms stock Theme.Dialog fade (TgMotion.dialogFadeDuration).
      expect(route.transitionDuration, TgMotion.dialogFadeDuration);
      expect(route.reverseTransitionDuration, TgMotion.dialogFadeDuration);
      expect(route.transitionDuration, const Duration(milliseconds: 150));
      // dimAlpha = 0.5 (AlertDialog.java:210).
      expect(route.barrierColor, kTgAlertDialogBarrierColor);
      expect(route.barrierDismissible, isTrue);
      expect(route.dismissByButtons, isTrue);
    });

    test('dimEnabled=false removes the barrier; dimAlpha rescales it '
        '(AlertDialog.java:1944-1952)', () {
      expect(TgAlertDialogRoute<void>(dimEnabled: false).barrierColor, isNull);
      expect(
        TgAlertDialogRoute<void>(dimAlpha: 51 / 255).barrierColor,
        const Color(0x33000000),
      );
    });
  });

  group('route motion', () {
    testWidgets('opens with a pure 150ms fade — no scale',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(
        title: 'Title',
        message: 'Message',
      ));
      await tester.pump(); // Build the route at t = 0.

      FadeTransition fade() => tester.widget<FadeTransition>(
            find
                .ancestor(of: _panel, matching: find.byType(FadeTransition))
                .first,
          );
      expect(fade().opacity.value, 0.0);
      // Content fades only — nothing scales.
      expect(
        find.ancestor(of: _panel, matching: find.byType(ScaleTransition)),
        findsNothing,
      );

      await tester.pump(const Duration(milliseconds: 75));
      expect(fade().opacity.value, moreOrLessEquals(0.5));

      await tester.pump(const Duration(milliseconds: 75));
      expect(fade().opacity.value, 1.0);
    });

    testWidgets('closes with the same 150ms fade',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(message: 'M'));
      await tester.pumpAndSettle();

      _navigator(tester).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      final FadeTransition fade = tester.widget<FadeTransition>(
        find.ancestor(of: _panel, matching: find.byType(FadeTransition)).first,
      );
      expect(fade.opacity.value, moreOrLessEquals(0.5));

      await tester.pump(const Duration(milliseconds: 75));
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
    });

    testWidgets('modal barrier carries the 0.5 black dim and dismisses on '
        'outside tap', (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      final Future<String?> result = showTgAlertDialog<String>(
        _navigator(tester).context,
        message: 'M',
      );
      await tester.pumpAndSettle();
      final AnimatedModalBarrier barrier = tester
          .widget<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier));
      expect(barrier.color.value, kTgAlertDialogBarrierColor);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
      expect(await result, isNull);
    });

    testWidgets('barrierDismissible=false keeps the dialog on outside tap',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(
        message: 'M',
        barrierDismissible: false,
      ));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(_panel, findsOneWidget);
    });
  });

  group('width', () {
    testWidgets('clamps at 356dp on a wide screen '
        '(AlertDialog.java:1252-1260)', (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(message: 'M'));
      await tester.pumpAndSettle();
      expect(tester.getSize(_panel).width, kTgAlertDialogMaxWidth);
      // Centered.
      expect(tester.getCenter(_panel).dx, _screen.width / 2);
    });

    testWidgets('clamps at screenWidth - 48 on a narrow screen '
        '(AlertDialog.java:1250-1262)', (WidgetTester tester) async {
      await tester.pumpWidget(_app(size: const Size(300, 600)));
      _navigator(tester).push(TgAlertDialogRoute<void>(message: 'M'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(_panel).width,
        300.0 - kTgAlertDialogScreenInset,
      );
    });
  });

  group('title and message', () {
    testWidgets('title 20dp RobotoMedium dialogTextBlack at 24dp gutters, '
        '19dp top / 10dp bottom (AlertDialog.java:784-794)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(
        title: 'Title',
        message: 'Message',
        positiveButton: const TgAlertDialogAction(text: 'OK'),
      ));
      await tester.pumpAndSettle();

      final Rect panel = tester.getRect(_panel);
      final Rect title = tester.getRect(find.text('Title'));
      expect(title.left, panel.left + kTgAlertDialogHorizontalMargin);
      expect(title.top, panel.top + kTgAlertDialogTitleTopMargin);

      final Text titleText = tester.widget<Text>(find.text('Title'));
      expect(titleText.style!.fontSize, 20.0);
      expect(titleText.style!.fontWeight, FontWeight.w500);
      expect(titleText.style!.fontFamily, 'packages/telegram_ui/RobotoMedium');
      expect(
        titleText.style!.color,
        _dayTheme.color(TelegramColorKey.dialogTextBlack),
      );

      // Message 16dp regular, 10dp below the title (AlertDialog.java:794,
      // 849-850).
      final Rect message = tester.getRect(find.text('Message'));
      expect(message.left, panel.left + kTgAlertDialogHorizontalMargin);
      expect(message.top, title.bottom + kTgAlertDialogTitleBottomMargin);
      final Text messageText = tester.widget<Text>(find.text('Message'));
      expect(messageText.style!.fontSize, 16.0);
      expect(messageText.style!.fontWeight, FontWeight.w400);
      expect(
        messageText.style!.color,
        _dayTheme.color(TelegramColorKey.dialogTextBlack),
      );

      // 20dp below the message the 52dp button row ends the panel
      // (AlertDialog.java:455, 1055): 19+20+10+16+20+52.
      expect(panel.height, 19.0 + 20.0 + 10.0 + 16.0 + 20.0 + 52.0);
    });

    testWidgets('message-only dialog: 19dp top margin '
        '(AlertDialog.java:453-455)', (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(message: 'Message'));
      await tester.pumpAndSettle();
      final Rect panel = tester.getRect(_panel);
      final Rect message = tester.getRect(find.text('Message'));
      expect(message.top, panel.top + kTgAlertDialogMessageTopMargin);
      // 19 + 16 + 20, no buttons.
      expect(panel.height, 19.0 + 16.0 + 20.0);
    });

    testWidgets('panel fills dialogBackground clipped at r20 '
        '(AlertDialog.java:312-315, 663-664)', (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(message: 'M'));
      await tester.pumpAndSettle();
      final ClipRRect clip = tester.widget<ClipRRect>(_panel);
      expect(
        clip.borderRadius,
        BorderRadius.circular(kTgAlertDialogCornerRadius),
      );
      final ColoredBox fill = tester.widget<ColoredBox>(
        find.descendant(of: _panel, matching: find.byType(ColoredBox)).first,
      );
      expect(fill.color, _dayTheme.color(TelegramColorKey.dialogBackground));
    });

    testWidgets('resources override recolors the surface in both directions',
        (WidgetTester tester) async {
      const Color background = Color(0xFF123456);
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(
        message: 'M',
        resources: ResourcesOverride(
          parent: _ThemeResources(_dayTheme),
          overrides: const <int, Color>{
            TelegramColorKey.dialogBackground: background,
          },
        ),
      ));
      await tester.pumpAndSettle();
      final ColoredBox fill = tester.widget<ColoredBox>(
        find.descendant(of: _panel, matching: find.byType(ColoredBox)).first,
      );
      expect(fill.color, background);
    });
  });

  group('button row', () {
    testWidgets('LTR: positive right-pinned, negative 8dp before it, '
        'neutral left-pinned, 40dp tall in the 52dp row '
        '(AlertDialog.java:961-1013, 1053-1055)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(
        message: 'M',
        positiveButton: const TgAlertDialogAction(text: 'OK'),
        negativeButton: const TgAlertDialogAction(text: 'Cancel'),
        neutralButton: const TgAlertDialogAction(text: 'Later'),
      ));
      await tester.pumpAndSettle();

      final Rect panel = tester.getRect(_panel);
      final Rect positive = tester.getRect(_buttonWithText('OK'));
      final Rect negative = tester.getRect(_buttonWithText('Cancel'));
      final Rect neutral = tester.getRect(_buttonWithText('Later'));

      expect(positive.height, kTgDialogButtonHeight);
      expect(negative.height, kTgDialogButtonHeight);
      // Laid from the padded top of the 52dp row (AlertDialog.java:1053).
      expect(
        positive.top,
        panel.bottom -
            kTgAlertDialogButtonRowHeight +
            kTgAlertDialogButtonRowPadding,
      );
      // Positive pinned right (AlertDialog.java:976).
      expect(
        positive.right,
        panel.right - kTgAlertDialogButtonRowPadding,
      );
      // Negative immediately left with an 8dp gap (AlertDialog.java:986-988).
      expect(negative.right, positive.left - kTgAlertDialogButtonGap);
      // Neutral pinned left (AlertDialog.java:995-997).
      expect(neutral.left, panel.left + kTgAlertDialogButtonRowPadding);
    });

    testWidgets('RTL mirrors the placement (AlertDialog.java:973-997)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(textDirection: TextDirection.rtl));
      _navigator(tester).push(TgAlertDialogRoute<void>(
        message: 'M',
        positiveButton: const TgAlertDialogAction(text: 'OK'),
        negativeButton: const TgAlertDialogAction(text: 'Cancel'),
        neutralButton: const TgAlertDialogAction(text: 'Later'),
      ));
      await tester.pumpAndSettle();

      final Rect panel = tester.getRect(_panel);
      final Rect positive = tester.getRect(_buttonWithText('OK'));
      final Rect negative = tester.getRect(_buttonWithText('Cancel'));
      final Rect neutral = tester.getRect(_buttonWithText('Later'));

      expect(positive.left, panel.left + kTgAlertDialogButtonRowPadding);
      expect(negative.left, positive.right + kTgAlertDialogButtonGap);
      expect(neutral.right, panel.right - kTgAlertDialogButtonRowPadding);
    });

    testWidgets('button tap fires the listener then dismisses '
        '(AlertDialog.java:1088-1096)', (WidgetTester tester) async {
      int pressed = 0;
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(
        message: 'M',
        positiveButton:
            TgAlertDialogAction(text: 'OK', onPressed: () => pressed++),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(pressed, 1);
      expect(_panel, findsNothing);
    });

    testWidgets('dismissByButtons=false keeps the dialog open '
        '(AlertDialog.java:1093-1095, 1954-1957)',
        (WidgetTester tester) async {
      int pressed = 0;
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(
        message: 'M',
        dismissByButtons: false,
        positiveButton:
            TgAlertDialogAction(text: 'OK', onPressed: () => pressed++),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(pressed, 1);
      expect(_panel, findsOneWidget);
    });

    testWidgets('destructive pass-through colors the button text_RedBold '
        '(AlertDialog.java:231-236)', (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(
        message: 'M',
        positiveButton:
            const TgAlertDialogAction(text: 'Delete', destructive: true),
        negativeButton: const TgAlertDialogAction(text: 'Cancel'),
      ));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('Delete')).style!.color,
        _dayTheme.color(TelegramColorKey.text_RedBold),
      );
      expect(
        tester.widget<Text>(find.text('Cancel')).style!.color,
        _dayTheme.color(TelegramColorKey.dialogButton),
      );
    });

    testWidgets('loading pass-through shows the spinner and blocks the tap '
        '(AlertDialog.java:1089, 1313-1335)', (WidgetTester tester) async {
      int pressed = 0;
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(
        message: 'M',
        positiveButton: TgAlertDialogAction(
          text: 'OK',
          loading: true,
          onPressed: () => pressed++,
        ),
      ));
      // No pumpAndSettle: the spinner ticks forever.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        find.descendant(
          of: _buttonWithText('OK'),
          matching: find.byKey(TgDialogButton.spinnerKey),
        ),
        findsOneWidget,
      );

      await tester.tap(_buttonWithText('OK'));
      await tester.pump(const Duration(milliseconds: 20));
      expect(pressed, 0);
      expect(_panel, findsOneWidget);

      // Unmount to dispose the spinner ticker.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('vertical fallback stacks negative/neutral/positive '
        'full-width with 6dp gaps (AlertDialog.java:952-959, 1124-1166, '
        '1222-1226)', (WidgetTester tester) async {
      const String positiveText = 'Confirm the important operation';
      const String negativeText = 'Cancel the important operation';
      const String neutralText = 'Remind me about this much later';
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(
        message: 'M',
        positiveButton: const TgAlertDialogAction(text: positiveText),
        negativeButton: const TgAlertDialogAction(text: negativeText),
        neutralButton: const TgAlertDialogAction(text: neutralText),
      ));
      await tester.pumpAndSettle();

      final Rect panel = tester.getRect(_panel);
      final Rect negative = tester.getRect(_buttonWithText(negativeText));
      final Rect neutral = tester.getRect(_buttonWithText(neutralText));
      final Rect positive = tester.getRect(_buttonWithText(positiveText));

      // MATCH_PARENT x 40 inside the 8dp padding (AlertDialog.java:1125).
      final double innerWidth = panel.width - 2 * kTgAlertDialogButtonRowPadding;
      expect(negative.width, innerWidth);
      expect(neutral.width, innerWidth);
      expect(positive.width, innerWidth);
      expect(negative.height, kTgDialogButtonHeight);

      // Order: negative, neutral, positive (AlertDialog.java:1124-1166) with
      // 6dp top margins (AlertDialog.java:1222-1226).
      expect(neutral.top, negative.bottom + kTgAlertDialogVerticalButtonGap);
      expect(positive.top, neutral.bottom + kTgAlertDialogVerticalButtonGap);
      // Stack: 8 + 40*3 + 6*2 + 8.
      expect(positive.bottom, panel.bottom - kTgAlertDialogButtonRowPadding);
    });

    testWidgets('horizontal buttons cap at (width - 24) / 2 '
        '(AlertDialog.java:390-398)', (WidgetTester tester) async {
      // Two 18-glyph labels: 18*16 + 24 = 312 each, combined 632 < 736, so
      // the row stays horizontal, but each exceeds the (356-24)/2 = 166 cap.
      const String a = 'First long label a';
      const String b = 'Other long label b';
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<void>(
        message: 'M',
        positiveButton: const TgAlertDialogAction(text: a),
        negativeButton: const TgAlertDialogAction(text: b),
      ));
      await tester.pumpAndSettle();

      final double cap =
          (kTgAlertDialogMaxWidth - kTgAlertDialogButtonMaxWidthInset) / 2.0;
      expect(tester.getSize(_buttonWithText(a)).width, cap);
      expect(tester.getSize(_buttonWithText(b)).width, cap);
    });
  });

  group('items variant', () {
    testWidgets('48dp rows at 23dp padding, 56dp icon indent, dialogIcon '
        'tint (AlertDialog.java:238-294)', (WidgetTester tester) async {
      const Key iconKey = ValueKey<String>('icon');
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<String>(
        items: const <TgDialogItem<String>>[
          TgDialogItem<String>(text: 'One', value: 'one'),
          TgDialogItem<String>(
            text: 'Two',
            value: 'two',
            icon: SizedBox(key: iconKey, width: 24, height: 24),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      final Rect panel = tester.getRect(_panel);
      final Finder cells = find.byType(TgAlertDialogCell);
      expect(cells, findsNWidgets(2));
      expect(tester.getSize(cells.first).height, kTgAlertDialogItemHeight);
      expect(tester.getSize(cells.first).width, panel.width);
      // Items block top margin 8 with no title/message
      // (AlertDialog.java:451).
      expect(
        tester.getTopLeft(cells.first).dy,
        panel.top + kTgAlertDialogItemsBlockMargin,
      );
      // Rows stack contiguously (48dp each).
      expect(
        tester.getTopLeft(cells.last).dy - tester.getTopLeft(cells.first).dy,
        kTgAlertDialogItemHeight,
      );
      // Panel: 8 + 48*2 + 8.
      expect(panel.height, 112.0);

      // Text at the 23dp padding; 56dp indent with an icon
      // (AlertDialog.java:249, 284).
      expect(
        tester.getRect(find.text('One')).left,
        panel.left + kTgAlertDialogItemPadding,
      );
      expect(
        tester.getRect(find.text('Two')).left,
        panel.left + kTgAlertDialogItemPadding + kTgAlertDialogItemIconIndent,
      );

      // Icon start-aligned inside the padding, centered vertically
      // (AlertDialog.java:254).
      final Rect icon = tester.getRect(find.byKey(iconKey));
      expect(icon.left, panel.left + kTgAlertDialogItemPadding);
      expect(
        icon.center.dy,
        tester.getRect(cells.last).center.dy,
      );
      expect(
        IconTheme.of(tester.element(find.byKey(iconKey))).color,
        _dayTheme.color(TelegramColorKey.dialogIcon),
      );

      // 16dp dialogTextBlack (AlertDialog.java:261-262).
      final Text text = tester.widget<Text>(find.text('One'));
      expect(text.style!.fontSize, kTgAlertDialogItemTextSize);
      expect(
        text.style!.color,
        _dayTheme.color(TelegramColorKey.dialogTextBlack),
      );
    });

    testWidgets('title above items uses the 14dp bottom margin '
        '(AlertDialog.java:794)', (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<String>(
        title: 'Pick',
        items: const <TgDialogItem<String>>[
          TgDialogItem<String>(text: 'One', value: 'one'),
        ],
      ));
      await tester.pumpAndSettle();
      final Rect title = tester.getRect(find.text('Pick'));
      expect(
        tester.getTopLeft(find.byType(TgAlertDialogCell)).dy,
        title.bottom + kTgAlertDialogTitleBottomMarginItems,
      );
    });

    testWidgets('message above items keeps the 12dp gap '
        '(AlertDialog.java:116, 893)', (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<String>(
        message: 'Message',
        items: const <TgDialogItem<String>>[
          TgDialogItem<String>(text: 'One', value: 'one'),
        ],
      ));
      await tester.pumpAndSettle();
      final Rect message = tester.getRect(find.text('Message'));
      expect(
        tester.getTopLeft(find.byType(TgAlertDialogCell)).dy,
        message.bottom + kTgAlertDialogMessageItemsGap,
      );
    });

    testWidgets('tap fires the row callback and pops with its value '
        '(AlertDialog.java:915-920)', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_app());
      final Future<String?> result = showTgAlertDialog<String>(
        _navigator(tester).context,
        items: <TgDialogItem<String>>[
          const TgDialogItem<String>(text: 'One', value: 'one'),
          TgDialogItem<String>(
            text: 'Two',
            value: 'two',
            onTap: () => taps++,
          ),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(_panel, findsNothing);
      expect(await result, 'two');
    });

    testWidgets('pressed row fills with dialogButtonSelector '
        '(AlertDialog.java:248)', (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<String>(
        items: const <TgDialogItem<String>>[
          TgDialogItem<String>(text: 'One', value: 'one'),
        ],
      ));
      await tester.pumpAndSettle();

      final Finder fill = find.descendant(
        of: find.byType(TgAlertDialogCell),
        matching: find.byType(ColoredBox),
      );
      expect(
        tester.widget<ColoredBox>(fill).color,
        const Color(0x00000000),
      );
      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(find.text('One')));
      await tester.pump();
      expect(
        tester.widget<ColoredBox>(fill).color,
        _dayTheme.color(TelegramColorKey.dialogButtonSelector),
      );
      await gesture.up();
      await tester.pump();
      expect(
        tester.widget<ColoredBox>(fill).color,
        const Color(0x00000000),
      );
    });

    testWidgets('rows report button semantics', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<String>(
        items: const <TgDialogItem<String>>[
          TgDialogItem<String>(text: 'One', value: 'one'),
        ],
      ));
      await tester.pumpAndSettle();
      final SemanticsData data = tester
          .getSemantics(find.byType(TgAlertDialogCell))
          .getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('a tall items list scrolls inside the panel',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgAlertDialogRoute<int>(
        items: <TgDialogItem<int>>[
          for (int i = 0; i < 20; i++) TgDialogItem<int>(text: 'Item $i', value: i),
        ],
      ));
      await tester.pumpAndSettle();
      // 20 * 48 + 16 > 600: the panel caps at the screen and scrolls.
      expect(tester.getSize(_panel).height, lessThanOrEqualTo(600.0));
      expect(
        find.descendant(
          of: _panel,
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
    });
  });
}
