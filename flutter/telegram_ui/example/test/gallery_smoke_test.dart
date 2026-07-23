// Smoke test for the gallery app: it builds, all five pages mount, and
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
import 'package:telegram_ui_example/pages/widgets_demo.dart';

void main() {
  setUp(() {
    GlassSettings.instance.debugReset();
  });

  testWidgets('gallery builds and navigates between all five pages',
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

    // Widgets demo — the PLAN_UIKIT catalog. The page hosts self-ticking
    // animations (indeterminate TgRadialProgress, TgFlickerLoading sweep),
    // so fixed pumps replace pumpAndSettle while it is on stage.
    await tester.tap(find.text('Widgets'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(WidgetsDemoPage), findsOneWidget);
    // The FAB floats over the list; the buttons section opens it.
    expect(find.byType(TgFab), findsOneWidget);
    expect(find.byType(TgButton), findsWidgets);
    expect(find.byType(TgCheckBox), findsWidgets);

    // The catalog ListView is lazy: scroll each remaining section into view
    // before asserting its controls exist.
    final Finder catalogList = find.byType(Scrollable).first;
    // Manual drag-until-found: scrollUntilVisible needs a single-match
    // finder and chokes on multi/empty matches, and the list is lazy so the
    // target widget does not exist until its section scrolls into build
    // range.
    Future<void> scrollTo(Finder finder) async {
      for (int i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
        await tester.drag(catalogList, const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
    }
    await scrollTo(find.byType(TgRadioCell));
    expect(find.byType(TgRadioCell), findsWidgets);
    await scrollTo(find.byType(TgSlideChooser));
    expect(find.byType(TgSlider), findsWidgets);
    await scrollTo(find.byType(TgAvatar));
    expect(find.byType(TgAvatar), findsWidgets);
    await scrollTo(find.byType(TgRadialProgress));
    expect(find.byType(TgRadialProgress), findsWidgets);
    await scrollTo(find.byType(TgLinearProgress));
    await scrollTo(find.byType(TgTextField));
    expect(find.byType(TgTextField), findsWidgets);
    await scrollTo(find.byType(TgEmptyView));
    await scrollTo(find.byType(TgFlickerLoading));
    await scrollTo(find.byType(TgHint));
    await scrollTo(find.byType(TgChip));
    expect(find.byType(TgChip), findsWidgets);

    // Push the detail page through TgPageRoute and swipe-free pop via the
    // Back button (150ms slide+fade each way).
    await scrollTo(find.text('Push detail page'));
    await tester.ensureVisible(find.text('Push detail page'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Push detail page'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Detail page'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Detail page'), findsNothing);

    // Theme browser (the IndexedStack mutes the widgets page's tickers, so
    // pumpAndSettle is safe again).
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
