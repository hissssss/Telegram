// telegram_ui gallery app (ARCHITECTURE.md section 2: example/).
//
// Three pages:
//  * tabs demo        — a DialogsActivity-style replica (TgScaffold +
//                       GlassAppBar + DialogCells + GlassTabBar);
//  * glass playground — every LiquidGlassSettings field as a live slider
//                       over a busy background;
//  * theme browser    — the five bundled themes with swatches + apply, and a
//                       cell/bulletin/sheet component demo section.

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:telegram_ui/telegram_ui.dart';

import 'pages/glass_playground.dart';
import 'pages/tabs_demo.dart';
import 'pages/theme_browser.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Kick the capability probe + shader warmup before the first glass frame;
  // GlassBackdropScope re-resolves the whole tree when the verdict lands.
  unawaited(GlassSettings.instance.ensureProbed());
  runApp(const GalleryApp());
}

/// Root of the gallery: owns the current [TelegramThemeData] and exposes it
/// (plus a setter) to every page through [GalleryTheme].
class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key});

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  TelegramThemeData _theme = TelegramThemeData.day();

  void _setTheme(TelegramThemeData theme) {
    setState(() => _theme = theme);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'telegram_ui gallery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: _theme.brightness,
        // ThemeExtension bridge so Material theme animations could crossfade
        // the palette; the direct TelegramTheme below is the granular path.
        extensions: <ThemeExtension<dynamic>>[TelegramThemeExtension(_theme)],
      ),
      // Wrap the Navigator so every route (bottom sheets, bulletins in the
      // overlay) sees the ambient TelegramTheme.
      builder: (BuildContext context, Widget? child) => GalleryTheme(
        data: _theme,
        setTheme: _setTheme,
        child: TelegramTheme(data: _theme, child: child!),
      ),
      home: const GalleryHome(),
    );
  }
}

/// Inherited handle to the gallery's theme state: the active
/// [TelegramThemeData] and a setter, plus a day/night [toggle].
class GalleryTheme extends InheritedWidget {
  const GalleryTheme({
    super.key,
    required this.data,
    required this.setTheme,
    required super.child,
  });

  /// The active theme.
  final TelegramThemeData data;

  /// Replaces the active theme app-wide.
  final ValueChanged<TelegramThemeData> setTheme;

  /// Whether the active theme classifies as dark.
  bool get isNight => data.brightness == Brightness.dark;

  /// Flips between the default day ('Blue') and night ('Dark Blue') themes.
  void toggle() => setTheme(
        isNight ? TelegramThemeData.day() : TelegramThemeData.night(),
      );

  static GalleryTheme of(BuildContext context) {
    final GalleryTheme? scope =
        context.dependOnInheritedWidgetOfExactType<GalleryTheme>();
    assert(scope != null, 'No GalleryTheme ancestor found.');
    return scope!;
  }

  @override
  bool updateShouldNotify(GalleryTheme oldWidget) => data != oldWidget.data;
}

/// Bottom-navigation shell over the three gallery pages.
class GalleryHome extends StatefulWidget {
  const GalleryHome({super.key});

  @override
  State<GalleryHome> createState() => _GalleryHomeState();
}

class _GalleryHomeState extends State<GalleryHome> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          TabsDemoPage(),
          GlassPlaygroundPage(),
          ThemeBrowserPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (int index) => setState(() => _index = index),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            label: 'Tabs',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.blur_on_rounded),
            label: 'Glass',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.palette_outlined),
            label: 'Themes',
          ),
        ],
      ),
    );
  }
}
