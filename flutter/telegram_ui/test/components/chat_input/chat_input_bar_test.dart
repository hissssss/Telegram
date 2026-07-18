// Tests for lib/src/components/chat_input/chat_input_bar.dart
// (flutter/docs/spec_chat_input.md sections 1-2), golden-free:
//
//  * constants against the Java values (ChatInputViewsContainer.java /
//    ChatActivityEnterView.java, cited per constant);
//  * shell wiring: GlassPresets.bottomPanelChat, radius 22dp, glass padding
//    7dp, liquid thickness 32dp / intensity 0.4 (CIVC:27, 81-82, 89-90) and
//    the oversized-panel geometry reproducing `inset(0, -dp(7))` (CIVC:268);
//  * bar geometry: resting height 44dp (CAEV:6410), emoji slot at left 3dp
//    (CAEV:14399), attach slot 44dp in from the right (CAEV:2660), send slot
//    at the bottom-right corner (CAEV:2897-2931), field frame 50/94/1.5dp
//    (CAEV:14402, 2660, 5763);
//  * slot presence and empty-slot tolerance;
//  * multi-line growth: island height max(44, field + 1.5) animated over
//    250ms (CAEV:2623-2628, 15456; ChatListItemAnimator.java:44-45), the
//    maxLines-6 cap (CAEV:5751), and the controller's expanded state;
//  * controller text/onTextChanged plumbing;
//  * color keys light + dark: chat_messagePanelText / Hint / Cursor /
//    chat_inTextSelectionHighlight (CAEV:5756-5762), and the resources
//    override convention.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/chat_input/chat_input_bar.dart';
import 'package:telegram_ui/src/glass/backdrop_scope.dart';
import 'package:telegram_ui/src/glass/geometry.dart';
import 'package:telegram_ui/src/glass/glass_panel.dart';
import 'package:telegram_ui/src/glass/liquid_glass_settings.dart';
import 'package:telegram_ui/src/glass/presets.dart';
import 'package:telegram_ui/src/glass/runtime_probe.dart';
import 'package:telegram_ui/src/theme/telegram_resources.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared themes (constructing the 777-key palettes once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();
final TelegramThemeData _nightTheme = TelegramThemeData.night();

/// Settings whose probe never resolves: liquid requests stay conservatively
/// frosted — the deterministic flutter_tester path (no ImageFilter.shader).
GlassSettings _manualSettings() =>
    GlassSettings(probe: () => Completer<GlassCapability>().future);

const double _barWidth = 400.0;

Widget _host(Widget child, {TelegramThemeData? theme}) {
  return TelegramTheme(
    data: theme ?? _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: GlassBackdropScope(
          settings: _manualSettings(),
          probeOnMount: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(width: _barWidth, child: child),
          ),
        ),
      ),
    ),
  );
}

double _barHeight(WidgetTester tester) =>
    tester.getSize(find.byType(ChatInputBar)).height;

/// The opacity gating the always-mounted hint text.
double _hintOpacity(WidgetTester tester) => tester
    .widget<Opacity>(find
        .ancestor(of: find.text('Message'), matching: find.byType(Opacity))
        .first)
    .opacity;

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      // CIVC:27-30.
      expect(kChatInputBubbleRadiusDp, 22.0);
      expect(kChatInputKeyboardRadiusDp, 29.0);
      expect(kChatInputBubbleBottomGapDp, 9.0);
      // CIVC:81 setPadding(dp(7)).
      expect(kChatInputGlassPaddingDp, 7.0);
      // CIVC:89-90 setThickness(dp(32)) / setIntensity(0.4f).
      expect(kChatInputGlassThicknessDp, 32.0);
      expect(kChatInputGlassIntensity, 0.4);
      expect(kChatInputGlassSettings.thickness, 32.0);
      expect(kChatInputGlassSettings.refractIntensity, 0.4);
      // CAEV:6410 DEFAULT_HEIGHT.
      expect(kChatInputBarHeightDp, 44.0);
      // CAEV:5751-5754.
      expect(kChatInputFieldTextSizeDp, 18.0);
      expect(kChatInputFieldPaddingTopDp, 9.0);
      expect(kChatInputFieldPaddingBottomDp, 10.0);
      expect(kChatInputFieldMaxLines, 6);
      // CAEV:14402, 5763, 2660, 14399.
      expect(kChatInputFieldMarginLeftDp, 50.0);
      expect(kChatInputFieldMarginRightDp, 50.0);
      expect(kChatInputFieldBottomMarginDp, 1.5);
      expect(kChatInputFieldContainerRightMarginDp, 44.0);
      expect(kChatInputEmojiLeftMarginDp, 3.0);
      // ChatListItemAnimator.java:44-45 (via CAEV:15456).
      expect(kChatInputHeightDuration, const Duration(milliseconds: 250));
      expect(kChatInputHeightCurve.a, closeTo(0.199, 0.001));
      expect(kChatInputHeightCurve.b, closeTo(0.011, 0.001));
      expect(kChatInputHeightCurve.c, closeTo(0.279, 0.001));
      expect(kChatInputHeightCurve.d, closeTo(0.910, 0.001));
    });
  });

  group('glass shell', () {
    testWidgets('bottomPanelChat preset, radius 22, padding 7, liquid 32/0.4',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ChatInputBar()));

      final GlassPanel panel = tester.widget(find.byType(GlassPanel));
      expect(panel.preset, GlassPresets.bottomPanelChat);
      expect(panel.borderRadius, const GlassRadii.all(kChatInputBubbleRadiusDp));
      expect(panel.padding, kChatInputGlassPaddingDp);
      // CIVC:89-90 — the keyboard-panel liquid parameters as defaults.
      expect(panel.settings.thickness, kChatInputGlassThicknessDp);
      expect(panel.settings.refractIntensity, kChatInputGlassIntensity);
      expect(panel.tier, isNull); // scope-resolved, no pin.
    });

    testWidgets('panel oversized 7dp vertically: inset(0, -dp(7)) + padding 7',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ChatInputBar()));

      final Rect bar = tester.getRect(find.byType(ChatInputBar));
      final Rect panel = tester.getRect(find.byType(GlassPanel));
      // Bounds expanded 7dp above and below the island (CIVC:268); the
      // symmetric 7dp drawable padding then cancels vertically, leaving the
      // visible glass inset 7dp horizontally only.
      expect(panel.top, bar.top - kChatInputGlassPaddingDp);
      expect(panel.bottom, bar.bottom + kChatInputGlassPaddingDp);
      expect(panel.left, bar.left);
      expect(panel.right, bar.right);
      expect(panel.height, bar.height + 2 * kChatInputGlassPaddingDp);
    });

    testWidgets('custom settings override the default liquid parameters',
        (WidgetTester tester) async {
      const LiquidGlassSettings custom = LiquidGlassSettings(thickness: 5);
      await tester.pumpWidget(_host(const ChatInputBar(settings: custom)));
      final GlassPanel panel = tester.widget(find.byType(GlassPanel));
      expect(panel.settings.thickness, 5.0);
    });
  });

  group('geometry', () {
    testWidgets('resting bar height is 44dp', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ChatInputBar()));
      await tester.pumpAndSettle();
      expect(_barHeight(tester), kChatInputBarHeightDp);
      expect(tester.getSize(find.byType(ChatInputBar)).width, _barWidth);
    });

    testWidgets('slots sit in their Java frames', (WidgetTester tester) async {
      const Key emojiKey = Key('emoji');
      const Key attachKey = Key('attach');
      const Key sendKey = Key('send');
      await tester.pumpWidget(_host(const ChatInputBar(
        emojiSlot: SizedBox.expand(key: emojiKey),
        attachSlot: SizedBox.expand(key: attachKey),
        sendSlot: SizedBox(key: sendKey, width: 44, height: 44),
      )));
      await tester.pumpAndSettle();

      final Rect bar = tester.getRect(find.byType(ChatInputBar));

      // Emoji: 44x44 bottom-left, leftMargin 3dp (CAEV:2713, 14399).
      final Rect emoji = tester.getRect(find.byKey(emojiKey));
      expect(emoji.size, const Size(44, 44));
      expect(emoji.left, bar.left + kChatInputEmojiLeftMarginDp);
      expect(emoji.bottom, bar.bottom);

      // Attach: 44x44 at the field container's bottom-right — 44dp in from
      // the bar's right edge (CAEV:2660, 2783-2794).
      final Rect attach = tester.getRect(find.byKey(attachKey));
      expect(attach.size, const Size(44, 44));
      expect(attach.right, bar.right - kChatInputFieldContainerRightMarginDp);
      expect(attach.bottom, bar.bottom);

      // Send slot: bottom-right corner (sendButtonContainer,
      // CAEV:2897-2931).
      final Rect send = tester.getRect(find.byKey(sendKey));
      expect(send.right, bar.right);
      expect(send.bottom, bar.bottom);
    });

    testWidgets('field frame: left 50, right 94, bottom 1.5 + padding 9/10',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ChatInputBar()));
      await tester.pumpAndSettle();

      final Rect bar = tester.getRect(find.byType(ChatInputBar));
      final Rect field = tester.getRect(find.byType(EditableText));
      // Field horizontal padding is 0 (CAEV:5754), so the EditableText edges
      // are the frame margins: left 50dp (CAEV:14402); right 44dp container
      // margin + 50dp field margin (CAEV:2660, 5763).
      expect(field.left, bar.left + kChatInputFieldMarginLeftDp);
      expect(
        field.right,
        bar.right -
            kChatInputFieldContainerRightMarginDp -
            kChatInputFieldMarginRightDp,
      );
      // Vertical: 1.5dp frame bottom margin + 10dp field bottom padding.
      expect(
        field.bottom,
        bar.bottom -
            kChatInputFieldBottomMarginDp -
            kChatInputFieldPaddingBottomDp,
      );
    });

    testWidgets('all slots null renders without errors',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ChatInputBar()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(EditableText), findsOneWidget);
    });
  });

  group('multi-line growth', () {
    testWidgets('island height = max(44, field + 1.5), animated over 250ms',
        (WidgetTester tester) async {
      final ChatInputBarController controller = ChatInputBarController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(ChatInputBar(controller: controller)));
      await tester.pumpAndSettle();
      expect(_barHeight(tester), kChatInputBarHeightDp);
      expect(controller.expanded, isFalse);

      await tester.enterText(find.byType(EditableText), 'line one\nline two');
      await tester.pump(); // relayout; the retarget is scheduled post-frame
      await tester.pump(); // animation tick t=0
      expect(_barHeight(tester), kChatInputBarHeightDp);

      // Target: field natural height (2 lines + 9/10 padding) + 1.5 margin
      // (CAEV:2623-2628, 5754, 5763).
      final double fieldHeight =
          tester.getSize(find.byType(EditableText)).height +
              kChatInputFieldPaddingTopDp +
              kChatInputFieldPaddingBottomDp;
      final double target = fieldHeight + kChatInputFieldBottomMarginDp;
      expect(target, greaterThan(kChatInputBarHeightDp));

      // Mid-flight after 125 of 250ms: strictly between rest and target.
      await tester.pump(const Duration(milliseconds: 125));
      final double mid = _barHeight(tester);
      expect(mid, greaterThan(kChatInputBarHeightDp));
      expect(mid, lessThan(target));

      // Settled at the target after the full 250ms.
      await tester.pump(const Duration(milliseconds: 125));
      expect(_barHeight(tester), closeTo(target, 0.01));
      await tester.pumpAndSettle();
      expect(controller.expanded, isTrue);

      // Two 18dp test-font lines: 9 + 10 + 36 + 1.5 = 56.5.
      expect(_barHeight(tester), closeTo(56.5, 0.01));
    });

    testWidgets('clearing the text shrinks back to 44 and collapses expanded',
        (WidgetTester tester) async {
      final ChatInputBarController controller = ChatInputBarController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(ChatInputBar(controller: controller)));
      await tester.enterText(find.byType(EditableText), 'a\nb\nc');
      await tester.pumpAndSettle();
      expect(_barHeight(tester), greaterThan(kChatInputBarHeightDp));
      expect(controller.expanded, isTrue);

      await tester.enterText(find.byType(EditableText), '');
      await tester.pumpAndSettle();
      expect(_barHeight(tester), kChatInputBarHeightDp);
      expect(controller.expanded, isFalse);
    });

    testWidgets('field growth caps at maxLines 6 (CAEV:5751)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ChatInputBar()));
      await tester.enterText(
          find.byType(EditableText), List.filled(6, 'x').join('\n'));
      await tester.pumpAndSettle();
      final double sixLines = _barHeight(tester);

      await tester.enterText(
          find.byType(EditableText), List.filled(9, 'x').join('\n'));
      await tester.pumpAndSettle();
      expect(_barHeight(tester), sixLines);
      // 6 lines of 18dp test font + 9/10 padding + 1.5 margin.
      expect(sixLines, closeTo(9 + 10 + 6 * 18 + 1.5, 0.01));
    });
  });

  group('controller', () {
    testWidgets('text setter/getter round-trips through the field',
        (WidgetTester tester) async {
      final ChatInputBarController controller =
          ChatInputBarController(initialText: 'draft');
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(ChatInputBar(controller: controller)));
      await tester.pumpAndSettle();
      expect(find.text('draft'), findsOneWidget);

      controller.text = 'replaced';
      await tester.pumpAndSettle();
      expect(controller.text, 'replaced');
      expect(find.text('replaced'), findsOneWidget);
      expect(controller.textController.selection,
          const TextSelection.collapsed(offset: 'replaced'.length));
    });

    testWidgets('onTextChanged fires per text change, not on selection',
        (WidgetTester tester) async {
      final List<String> seen = <String>[];
      final ChatInputBarController controller =
          ChatInputBarController(onTextChanged: seen.add);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(ChatInputBar(controller: controller)));

      await tester.enterText(find.byType(EditableText), 'hi');
      expect(seen, <String>['hi']);

      // Selection-only change does not fire.
      controller.textController.selection =
          const TextSelection.collapsed(offset: 0);
      expect(seen, <String>['hi']);

      await tester.enterText(find.byType(EditableText), 'hi there');
      expect(seen, <String>['hi', 'hi there']);
    });

    testWidgets('notifies listeners on text and expanded changes',
        (WidgetTester tester) async {
      final ChatInputBarController controller = ChatInputBarController();
      addTearDown(controller.dispose);
      int notifications = 0;
      controller.addListener(() => notifications++);
      await tester.pumpWidget(_host(ChatInputBar(controller: controller)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText), 'a\nb');
      final int afterText = notifications;
      expect(afterText, greaterThan(0));
      await tester.pumpAndSettle();
      // The expanded flip adds a notification beyond the text change.
      expect(controller.expanded, isTrue);
      expect(notifications, greaterThan(afterText));
    });

    testWidgets('external TextEditingController is shared and not disposed',
        (WidgetTester tester) async {
      final TextEditingController text = TextEditingController(text: 'seed');
      addTearDown(text.dispose);
      final ChatInputBarController controller =
          ChatInputBarController(textController: text);
      await tester.pumpWidget(_host(ChatInputBar(controller: controller)));
      expect(find.text('seed'), findsOneWidget);

      controller.dispose();
      // The external controller survives the bar controller's dispose.
      text.text = 'still alive';
      expect(text.text, 'still alive');
    });

    testWidgets('works without an explicit controller',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ChatInputBar()));
      await tester.enterText(find.byType(EditableText), 'internal');
      await tester.pumpAndSettle();
      expect(find.text('internal'), findsOneWidget);
    });
  });

  group('hint', () {
    testWidgets('shown while empty, faded out once text exists',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ChatInputBar()));
      expect(find.text('Message'), findsOneWidget);
      expect(_hintOpacity(tester), 1.0);

      await tester.enterText(find.byType(EditableText), 'x');
      await tester.pump();
      expect(_hintOpacity(tester), 0.0);

      await tester.enterText(find.byType(EditableText), '');
      await tester.pump();
      expect(_hintOpacity(tester), 1.0);
    });

    testWidgets('custom hint text renders', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const ChatInputBar(hintText: 'Comment')));
      expect(find.text('Comment'), findsOneWidget);
    });
  });

  group('color keys (CAEV:5756-5762)', () {
    Future<void> expectFieldColors(
        WidgetTester tester, TelegramThemeData theme) async {
      await tester.pumpWidget(_host(const ChatInputBar(), theme: theme));

      final EditableText field = tester.widget(find.byType(EditableText));
      expect(field.style.color,
          theme.color(TelegramColorKey.chat_messagePanelText));
      expect(field.style.fontSize, kChatInputFieldTextSizeDp);
      expect(field.cursorColor,
          theme.color(TelegramColorKey.chat_messagePanelCursor));
      expect(field.selectionColor,
          theme.color(TelegramColorKey.chat_inTextSelectionHighlight));
      expect(field.maxLines, kChatInputFieldMaxLines);

      final Text hint = tester.widget(find.text('Message'));
      expect(hint.style!.color,
          theme.color(TelegramColorKey.chat_messagePanelHint));
      expect(hint.style!.fontSize, kChatInputFieldTextSizeDp);
    }

    testWidgets('light theme', (WidgetTester tester) async {
      await expectFieldColors(tester, _dayTheme);
    });

    testWidgets('dark theme', (WidgetTester tester) async {
      await expectFieldColors(tester, _nightTheme);
    });

    testWidgets('light and dark hint colors differ (sanity)',
        (WidgetTester tester) async {
      expect(_dayTheme.color(TelegramColorKey.chat_messagePanelHint),
          isNot(_nightTheme.color(TelegramColorKey.chat_messagePanelHint)));
    });

    testWidgets('resources override wins over the ambient theme',
        (WidgetTester tester) async {
      const TelegramResources resources = _MagentaResources();
      await tester
          .pumpWidget(_host(const ChatInputBar(resources: resources)));

      final EditableText field = tester.widget(find.byType(EditableText));
      expect(field.style.color, const Color(0xFFFF00FF));
      final GlassPanel panel = tester.widget(find.byType(GlassPanel));
      expect(panel.resources, same(resources));
    });
  });
}

/// Fixed-color resources for the override test.
class _MagentaResources extends TelegramResources {
  const _MagentaResources();

  @override
  Color getColor(int key) => const Color(0xFFFF00FF);
}
