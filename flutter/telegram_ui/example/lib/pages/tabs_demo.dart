// DialogsActivity-style replica: TgScaffold + GlassAppBar('Telegram') +
// a chat list of fake DialogCells + the floating GlassTabBar with five tabs.
//
// The Calls tab icon is the real Android composition
// (TMessagesProj/src/main/res/raw/tab_calls.json, TabAnimation.CALLS in
// GlassTabView.java) driven through the telegram_ui_lottie adapter — played
// forward on select, in reverse on deselect. The other tabs stay static
// Material glyphs.

import 'package:flutter/material.dart';
import 'package:telegram_ui/telegram_ui.dart';
import 'package:telegram_ui_lottie/telegram_ui_lottie.dart';

import '../main.dart';
import '../widgets/gradient_avatar.dart';

class _FakeDialog {
  const _FakeDialog(this.name, this.message, this.time,
      {this.unread = 0, this.pinned = false, this.muted = false});

  final String name;
  final String message;
  final String time;
  final int unread;
  final bool pinned;
  final bool muted;
}

const List<_FakeDialog> _seedDialogs = <_FakeDialog>[
  _FakeDialog('Saved Messages', 'Design spec — glass tab bar.pdf', '12:41',
      pinned: true),
  _FakeDialog('Flutter News', 'Impeller is now the default renderer', '12:30',
      unread: 3, pinned: true),
  _FakeDialog('Ariana', 'See you at 7 then!', '11:52', unread: 1),
  _FakeDialog('Design Team', 'Nadia: pushed the new tokens', '11:20',
      unread: 12, muted: true),
  _FakeDialog('Marco Rossi', 'Photo', '10:05'),
  _FakeDialog('Weekend Plans', 'Lena: who brings the drone?', '09:48',
      unread: 5),
  _FakeDialog('Dev Null', 'Sticker', '09:12', muted: true),
  _FakeDialog('Mom', 'Call me when you land ❤️', 'Thu'),
  _FakeDialog('Telegram', 'Your login code is never shared', 'Thu'),
  _FakeDialog('Book Club', 'Sam: chapter 12 discussion tonight', 'Wed',
      unread: 2),
];

/// The tabs demo page — a static replica of the Android main screen.
class TabsDemoPage extends StatefulWidget {
  const TabsDemoPage({super.key});

  @override
  State<TabsDemoPage> createState() => _TabsDemoPageState();
}

class _TabsDemoPageState extends State<TabsDemoPage>
    with TickerProviderStateMixin {
  static const List<String> _tabTitles = <String>[
    'Telegram',
    'Contacts',
    'Calls',
    'Settings',
    'Profile',
  ];

  int _tab = 0;

  /// Animated Calls icon; null until the asset composition loads (the tab
  /// shows a static glyph in the meantime).
  TabIcon? _callsIcon;

  @override
  void initState() {
    super.initState();
    loadLottieAssetTabIcon('assets/lottie/tab_calls.json', vsync: this)
        .then((TabIcon icon) {
      if (!mounted) {
        _disposeIcon(icon);
        return;
      }
      setState(() => _callsIcon = icon);
    });
  }

  @override
  void dispose() {
    if (_callsIcon != null) {
      _disposeIcon(_callsIcon!);
    }
    super.dispose();
  }

  static void _disposeIcon(TabIcon icon) {
    ((icon as AnimatedTabIcon).controller as LottieTabAnimation).dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GalleryTheme gallery = GalleryTheme.of(context);
    return TgScaffold(
      appBar: GlassAppBar(
        title: _tabTitles[_tab],
        animateTitleChange: true,
        actions: <Widget>[
          GlassIconButton(
            icon: Icon(
              gallery.isNight
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            tooltip: 'Toggle day/night',
            onPressed: gallery.toggle,
          ),
        ],
      ),
      body: Builder(
        // Builder so the list reads the MediaQuery padding TgScaffold grew
        // by the app bar extent and the 72dp tab-bar inset.
        builder: (BuildContext context) {
          final EdgeInsets padding = MediaQuery.paddingOf(context);
          return ListView.builder(
            padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
            itemCount: 30,
            itemBuilder: (BuildContext context, int index) {
              final _FakeDialog dialog =
                  _seedDialogs[index % _seedDialogs.length];
              final Color pinColor = TelegramTheme.colorOf(
                context,
                TelegramColorKey.chats_pinnedIcon,
              );
              return DialogCell(
                name: dialog.name,
                message: dialog.message,
                time: dialog.time,
                unreadCount: index < _seedDialogs.length ? dialog.unread : 0,
                countMuted: dialog.muted,
                pinned: dialog.pinned && index < _seedDialogs.length,
                pinnedIcon: Icon(Icons.push_pin, size: 16, color: pinColor),
                avatar: GradientAvatar(name: dialog.name, seed: index),
              );
            },
          );
        },
      ),
      tabBar: GlassTabBar(
        initialIndex: _tab,
        onSelected: (int index) => setState(() => _tab = index),
        items: <GlassTabBarItem>[
          const GlassTabBarItem(
            id: 'chats',
            label: 'Chats',
            icon: TabIcon.static(
              child: Icon(Icons.chat_bubble_outline_rounded),
            ),
            badgeCount: 21,
          ),
          const GlassTabBarItem(
            id: 'contacts',
            label: 'Contacts',
            icon: TabIcon.static(child: Icon(Icons.people_outline_rounded)),
          ),
          GlassTabBarItem(
            id: 'calls',
            label: 'Calls',
            // The real Android tab_calls composition once loaded; a static
            // glyph before that.
            icon: _callsIcon ??
                const TabIcon.static(child: Icon(Icons.call_outlined)),
            badgeCount: 2,
          ),
          const GlassTabBarItem(
            id: 'settings',
            label: 'Settings',
            icon: TabIcon.static(child: Icon(Icons.settings_outlined)),
          ),
          GlassTabBarItem(
            id: 'profile',
            label: 'Ariana',
            avatar: const GradientAvatar(name: 'Ariana', seed: 2),
          ),
        ],
      ),
    );
  }
}
