// Smoke test for the gallery app: it builds, all three pages mount, and
// bottom navigation switches between them. Runs under flutter_tester, where
// the glass probe resolves non-liquid and every surface renders frosted/flat.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/telegram_ui.dart';
import 'package:telegram_ui_example/main.dart';
import 'package:telegram_ui_example/pages/glass_playground.dart';
import 'package:telegram_ui_example/pages/tabs_demo.dart';
import 'package:telegram_ui_example/pages/theme_browser.dart';

void main() {
  setUp(() {
    GlassSettings.instance.debugReset();
  });

  testWidgets('gallery builds and navigates between all three pages',
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
