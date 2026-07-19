// Smoke test for the gallery app: it builds, all four pages mount, and
// bottom navigation switches between them. Runs under flutter_tester, where
// the glass probe resolves non-liquid and every surface renders frosted/flat.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/telegram_ui.dart';
import 'package:telegram_ui_example/main.dart';
import 'package:telegram_ui_example/pages/chat_demo.dart';
import 'package:telegram_ui_example/pages/glass_playground.dart';
import 'package:telegram_ui_example/pages/tabs_demo.dart';
import 'package:telegram_ui_example/pages/theme_browser.dart';

void main() {
  setUp(() {
    GlassSettings.instance.debugReset();
  });

  testWidgets('gallery builds and navigates between all four pages',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const GalleryApp());
    await tester.pumpAndSettle();

    // Tabs demo is the initial page: app bar title + dialog cells + tab bar.
    expect(find.byType(TabsDemoPage), findsOneWidget);
    // App bar title (a seed DialogCell is also named 'Telegram').
    expect(find.text('Telegram'), findsWidgets);
    expect(find.byType(DialogCell), findsWidgets);
    expect(find.byType(GlassTabBar), findsOneWidget);

    // The Calls tab icon is the bundled tab_calls.json composition driven
    // through the telegram_ui_lottie adapter (loaded asynchronously, so it
    // must be present after settle). Selecting the tab plays it.
    expect(
      find.byWidgetPredicate(
          (Widget w) => w.runtimeType.toString() == 'Lottie'),
      findsOneWidget,
    );
    await tester.tap(find.text('Calls'));
    await tester.pumpAndSettle();

    // Chat demo: composed ChatInput docked over the bubble list.
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatDemoPage), findsOneWidget);
    expect(find.byType(ChatInput), findsOneWidget);
    expect(find.byType(ChatInputBar), findsOneWidget);
    expect(find.byType(RecordSendButton), findsOneWidget);

    // Emoji slot toggles the EmojiPanel (slides in under the input).
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(EmojiPanel), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_alt_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_alt_outlined));
    await tester.pumpAndSettle();

    // Attach slot opens the TgAttachSheet with the placeholder media grid;
    // tapping the barrier dismisses it.
    await tester.tap(find.byIcon(Icons.attach_file_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(TgAttachSheet), findsOneWidget);
    // 'Gallery' shows twice: page header title + switcher tab label.
    expect(find.text('Gallery'), findsNWidgets(2));
    await tester.tapAt(const Offset(195, 60));
    await tester.pumpAndSettle();
    expect(find.byType(TgAttachSheet), findsNothing);

    // Glass playground.
    await tester.tap(find.text('Glass'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassPlaygroundPage), findsOneWidget);
    expect(find.byType(GlassPanel), findsWidgets);
    expect(find.byType(Slider), findsNWidgets(5));

    // Theme browser.
    await tester.tap(find.text('Themes'));
    await tester.pumpAndSettle();
    expect(find.byType(ThemeBrowserPage), findsOneWidget);
    expect(find.text('Bundled themes'), findsOneWidget);
    expect(find.text('Apply'), findsNWidgets(5));
  });

  testWidgets('applying a bundled theme flips the ambient TelegramTheme',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const GalleryApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Themes'));
    await tester.pumpAndSettle();

    BuildContext context = tester.element(find.byType(ThemeBrowserPage));
    expect(TelegramTheme.of(context).brightness, Brightness.light);

    // 'Dark Blue' is the second card; its Apply button flips to night.
    await tester.tap(find.text('Apply').at(1));
    await tester.pumpAndSettle();

    context = tester.element(find.byType(ThemeBrowserPage));
    expect(TelegramTheme.of(context).brightness, Brightness.dark);
  });
}
