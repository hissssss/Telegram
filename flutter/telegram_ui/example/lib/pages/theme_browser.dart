// Theme browser: the five bundled Android themes as swatch cards with an
// apply button, plus a live component demo section (cells, bulletin, sheet).

import 'package:flutter/material.dart';
import 'package:telegram_ui/telegram_ui.dart';

import '../main.dart';

/// The theme browser page.
class ThemeBrowserPage extends StatefulWidget {
  const ThemeBrowserPage({super.key});

  @override
  State<ThemeBrowserPage> createState() => _ThemeBrowserPageState();
}

class _ThemeBrowserPageState extends State<ThemeBrowserPage> {
  /// The five bundled themes, resolved once ('Blue', 'Dark Blue',
  /// 'Arctic Blue', 'Day', 'Night').
  late final Map<String, TelegramThemeData> _themes =
      <String, TelegramThemeData>{
    for (final String name in kBundledThemes.keys)
      name: TelegramThemeData.fromBundledTheme(name),
  };

  bool _notifications = true;

  Future<void> _showSheet(BuildContext context) async {
    final String? choice = await showTgBottomSheet<String>(
      context,
      title: 'Mute for...',
      items: const <TgBottomSheetItem<String>>[
        TgBottomSheetItem<String>(
          text: 'Mute for 1 hour',
          icon: Icon(Icons.notifications_paused_outlined),
          value: '1 hour',
        ),
        TgBottomSheetItem<String>(
          text: 'Mute for 8 hours',
          icon: Icon(Icons.nightlight_outlined),
          value: '8 hours',
        ),
        TgBottomSheetItem<String>(
          text: 'Mute forever',
          icon: Icon(Icons.notifications_off_outlined),
          value: 'forever',
        ),
      ],
    );
    if (choice != null && context.mounted) {
      Bulletin.show(context, text: 'Muted for $choice');
    }
  }

  @override
  Widget build(BuildContext context) {
    final GalleryTheme gallery = GalleryTheme.of(context);
    final Color background = TelegramTheme.colorOf(
      context,
      TelegramColorKey.windowBackgroundGray,
    );
    final Color cellBackground = TelegramTheme.colorOf(
      context,
      TelegramColorKey.windowBackgroundWhite,
    );
    return ColoredBox(
      color: background,
      child: SafeArea(
        child: ListView(
          children: <Widget>[
            const HeaderCell(text: 'Bundled themes'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: <Widget>[
                  for (final MapEntry<String, TelegramThemeData> entry
                      in _themes.entries)
                    _ThemeCard(
                      name: entry.key,
                      data: entry.value,
                      active: identical(gallery.data, entry.value),
                      onApply: () => gallery.setTheme(entry.value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const ShadowSectionCell(),
            ColoredBox(
              color: cellBackground,
              child: Column(
                children: <Widget>[
                  const HeaderCell(text: 'Cells'),
                  TextCell(
                    title: 'Notifications',
                    icon: const Icon(Icons.notifications_outlined),
                    checked: _notifications,
                    onChanged: (bool value) =>
                        setState(() => _notifications = value),
                    divider: true,
                  ),
                  TextCell(
                    title: 'Data and Storage',
                    icon: const Icon(Icons.data_usage_outlined),
                    value: '2.3 GB',
                    divider: true,
                    onTap: () {},
                  ),
                  TextCell(
                    title: 'Night mode',
                    icon: const Icon(Icons.dark_mode_outlined),
                    checked: gallery.isNight,
                    onChanged: (bool _) => gallery.toggle(),
                  ),
                  const UserCell(
                    name: 'Ariana',
                    status: 'online',
                    online: true,
                    avatar: TgAvatar(id: 2, firstName: 'Ariana', size: 46),
                    divider: true,
                  ),
                  const UserCell(
                    name: 'Marco Rossi',
                    status: 'last seen recently',
                    avatar: TgAvatar(id: 5, firstName: 'Marco', size: 46),
                  ),
                ],
              ),
            ),
            const ShadowSectionCell(),
            ColoredBox(
              color: cellBackground,
              child: Column(
                children: <Widget>[
                  const HeaderCell(text: 'Overlays'),
                  TextCell(
                    title: 'Show bulletin',
                    icon: const Icon(Icons.info_outline),
                    divider: true,
                    onTap: () => Bulletin.show(
                      context,
                      text: 'Chat archived',
                      actionText: 'Undo',
                      onAction: () {},
                    ),
                  ),
                  TextCell(
                    title: 'Show bottom sheet',
                    icon: const Icon(Icons.vertical_align_bottom),
                    onTap: () => _showSheet(context),
                  ),
                ],
              ),
            ),
            const ShadowSectionCell(),
          ],
        ),
      ),
    );
  }
}

/// One bundled-theme card: key swatches over the theme's own background,
/// name, and an apply button.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.name,
    required this.data,
    required this.active,
    required this.onApply,
  });

  final String name;
  final TelegramThemeData data;
  final bool active;
  final VoidCallback onApply;

  static const List<int> _swatchKeys = <int>[
    TelegramColorKey.actionBarDefault,
    TelegramColorKey.chat_outBubble,
    TelegramColorKey.chat_inBubble,
    TelegramColorKey.chats_unreadCounter,
    TelegramColorKey.windowBackgroundWhiteBlueHeader,
  ];

  @override
  Widget build(BuildContext context) {
    final Color background = data.color(TelegramColorKey.windowBackgroundWhite);
    final Color text =
        data.color(TelegramColorKey.windowBackgroundWhiteBlackText);
    final Color accent = data.color(TelegramColorKey.featuredStickers_addButton);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? accent : text.withValues(alpha: 0.15),
          width: active ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                for (final int key in _swatchKeys)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: data.color(key),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: text.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              name,
              style: TextStyle(
                color: text,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: 'RobotoMedium',
                package: 'telegram_ui',
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onApply,
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
