// Widgets demo: the PLAN_UIKIT.md component catalog in one scrolling page —
// every wave-1/wave-2 control appears at least once (PLAN_UIKIT.md §4.2):
// buttons (+FAB), dialogs, popup menu, form controls, avatars, progress,
// text fields, empty/skeleton states, hints, chips, undo bulletin, and a
// TgPageRoute navigation push (swipe back from the left edge).

import 'package:flutter/material.dart' show Icons, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:telegram_ui/telegram_ui.dart';

/// The widgets catalog page.
class WidgetsDemoPage extends StatefulWidget {
  const WidgetsDemoPage({super.key});

  @override
  State<WidgetsDemoPage> createState() => _WidgetsDemoPageState();
}

class _WidgetsDemoPageState extends State<WidgetsDemoPage> {
  // Buttons.
  int _count = 0;
  bool _buttonLoading = false;
  bool _buttonEnabled = true;
  bool _fabVisible = true;

  // Form controls.
  bool _checkPlain = true;
  bool _checkSettings = false;
  bool _checkAvatar = true;
  int _radioIndex = 0;
  double _sliderValue = 0.3;
  double _stepValue = 0.5;
  double _twoSidedValue = 0.75;
  int _chooserIndex = 1;

  // Progress (shared by radial determinate + linear).
  double _progress = 0.4;

  // Empty / skeleton.
  bool _emptyLoading = false;

  // Hint.
  bool _hintShown = true;

  // Chips.
  final List<String> _chipNames = <String>['Ariana', 'Marco', 'Yuki', 'Nadia'];
  String? _chipDeleting;

  @override
  Widget build(BuildContext context) {
    final Color background = TelegramTheme.colorOf(
      context,
      TelegramColorKey.windowBackgroundGray,
    );
    return ColoredBox(
      color: background,
      child: SafeArea(
        child: Stack(
          children: <Widget>[
            ListView(
              children: <Widget>[
                _buildButtonsSection(context),
                _buildDialogsSection(context),
                _buildMenuSection(context),
                _buildControlsSection(context),
                _buildAvatarsSection(context),
                _buildProgressSection(context),
                _buildTextFieldsSection(context),
                _buildEmptySection(context),
                _buildHintSection(context),
                _buildChipsSection(context),
                _buildOverlaysSection(context),
                _buildNavigationSection(context),
                const SizedBox(height: 88),
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: TgFab(
                visible: _fabVisible,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Bulletin.show(context, text: 'FAB pressed'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- Buttons ------------------------------------------------------------

  Widget _buildButtonsSection(BuildContext context) {
    return _Section(
      title: 'Buttons',
      children: <Widget>[
        TgButton(
          text: 'Filled button',
          onPressed: () {},
        ),
        const SizedBox(height: 8),
        TgButton(
          text: 'Text button',
          variant: TgButtonVariant.text,
          onPressed: () {},
        ),
        const SizedBox(height: 8),
        TgButton(
          text: 'Neutral button',
          variant: TgButtonVariant.neutral,
          onPressed: () {},
        ),
        const SizedBox(height: 8),
        TgButton(
          text: 'Add member',
          count: _count,
          onPressed: () => setState(() => _count++),
          subText: _count > 0 ? 'tap to add another' : null,
        ),
        const SizedBox(height: 8),
        TgButton(
          text: _count > 0 ? 'Clear counter' : 'Counter is empty',
          variant: TgButtonVariant.neutral,
          enabled: _count > 0,
          onPressed: () => setState(() => _count = 0),
        ),
        const SizedBox(height: 8),
        TgButton(
          text: _buttonLoading ? 'Stop loading' : 'Start loading',
          loading: _buttonLoading,
          onPressed: () => setState(() => _buttonLoading = !_buttonLoading),
        ),
        const SizedBox(height: 8),
        TgButton(
          text: 'Disabled while unchecked',
          enabled: _buttonEnabled,
          onPressed: () {},
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            TgCheckBox.settingsRow(
              checked: _buttonEnabled,
              onChanged: (bool value) =>
                  setState(() => _buttonEnabled = value),
            ),
            const SizedBox(width: 12),
            const Expanded(child: _Label('Enable the button above')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            TgCheckBox.settingsRow(
              checked: _fabVisible,
              onChanged: (bool value) => setState(() => _fabVisible = value),
            ),
            const SizedBox(width: 12),
            const Expanded(child: _Label('Show the FAB (bottom right)')),
          ],
        ),
      ],
    );
  }

  // -- Dialogs ------------------------------------------------------------

  Widget _buildDialogsSection(BuildContext context) {
    return _Section(
      title: 'Dialogs',
      children: <Widget>[
        TgButton(
          text: 'Message dialog',
          variant: TgButtonVariant.neutral,
          onPressed: () => showTgAlertDialog<void>(
            context,
            title: 'Telegram',
            message: 'A classic title + message alert with the two-button '
                'row. Tap outside to dismiss.',
            positiveButton: TgAlertDialogAction(text: 'OK', onPressed: () {}),
            negativeButton: TgAlertDialogAction(text: 'Cancel'),
          ),
        ),
        const SizedBox(height: 8),
        TgButton(
          text: 'Destructive confirm',
          variant: TgButtonVariant.neutral,
          onPressed: () async {
            final bool? confirmed = await showTgAlertDialog<bool>(
              context,
              title: 'Delete chat',
              message: 'Are you sure you want to delete the chat with '
                  'Marco Rossi?',
              positiveButton: TgAlertDialogAction(
                text: 'Delete',
                destructive: true,
                onPressed: () {},
              ),
              negativeButton: TgAlertDialogAction(text: 'Cancel'),
            );
            if (confirmed == null && context.mounted) {
              // Dialog resolved without an item; nothing else to do.
            }
          },
        ),
        const SizedBox(height: 8),
        TgButton(
          text: 'Items dialog',
          variant: TgButtonVariant.neutral,
          onPressed: () async {
            final String? choice = await showTgAlertDialog<String>(
              context,
              title: 'Notifications',
              items: const <TgDialogItem<String>>[
                TgDialogItem<String>(
                  text: 'Enable all',
                  icon: Icon(Icons.notifications_active_outlined),
                  value: 'all',
                ),
                TgDialogItem<String>(
                  text: 'Mute for 8 hours',
                  icon: Icon(Icons.nightlight_outlined),
                  value: '8h',
                ),
                TgDialogItem<String>(
                  text: 'Disable',
                  icon: Icon(Icons.notifications_off_outlined),
                  value: 'off',
                ),
              ],
            );
            if (choice != null && context.mounted) {
              Bulletin.show(context, text: 'Picked: $choice');
            }
          },
        ),
        const SizedBox(height: 8),
        TgButton(
          text: 'Loading button dialog',
          variant: TgButtonVariant.neutral,
          onPressed: () => showTgAlertDialog<void>(
            context,
            title: 'Signing in…',
            message: 'The positive button shows the in-button spinner while '
                'a fake request runs.',
            positiveButton: const TgAlertDialogAction(
              text: 'Sign in',
              loading: true,
            ),
            negativeButton: TgAlertDialogAction(text: 'Cancel'),
          ),
        ),
      ],
    );
  }

  // -- Menu ---------------------------------------------------------------

  Future<void> _showOverflowMenu(BuildContext anchorContext) async {
    final RenderBox button = anchorContext.findRenderObject()! as RenderBox;
    final RenderBox overlay = Navigator.of(anchorContext)
        .overlay!
        .context
        .findRenderObject()! as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    final String? choice = await showTgPopupMenu<String>(
      anchorContext,
      position: position,
      entries: const <TgPopupMenuEntry<String>>[
        TgPopupMenuItem<String>(
          text: 'Reply',
          icon: Icon(Icons.reply_outlined),
          value: 'reply',
        ),
        TgPopupMenuItem<String>(
          text: 'Copy',
          icon: Icon(Icons.copy_outlined),
          value: 'copy',
        ),
        TgPopupMenuItem<String>(
          text: 'Pin',
          icon: Icon(Icons.push_pin_outlined),
          subtext: 'Notify all members',
          value: 'pin',
        ),
        TgPopupMenuGap<String>(),
        TgPopupMenuItem<String>(
          text: 'Enable sound',
          checked: true,
          value: 'sound',
        ),
        TgPopupMenuGap<String>(),
        TgPopupMenuItem<String>(
          text: 'Delete',
          icon: Icon(Icons.delete_outline),
          textColorKey: TelegramColorKey.text_RedRegular,
          iconColorKey: TelegramColorKey.text_RedRegular,
          value: 'delete',
        ),
      ],
    );
    if (choice != null && mounted) {
      Bulletin.show(context, text: 'Menu: $choice');
    }
  }

  Widget _buildMenuSection(BuildContext context) {
    return _Section(
      title: 'Menu',
      children: <Widget>[
        Builder(
          builder: (BuildContext anchorContext) => TgButton(
            text: 'Show overflow menu',
            variant: TgButtonVariant.neutral,
            onPressed: () => _showOverflowMenu(anchorContext),
          ),
        ),
      ],
    );
  }

  // -- Form controls ------------------------------------------------------

  Widget _buildControlsSection(BuildContext context) {
    return _Section(
      title: 'Form controls',
      inset: false,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 8),
          child: Row(
            children: <Widget>[
              TgCheckBox(
                checked: _checkPlain,
                onChanged: (bool value) => setState(() => _checkPlain = value),
              ),
              const SizedBox(width: 18),
              TgCheckBox.settingsRow(
                checked: _checkSettings,
                onChanged: (bool value) =>
                    setState(() => _checkSettings = value),
              ),
              const SizedBox(width: 18),
              // The avatar-overlay recipe over an avatar, as in share sheets.
              SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  children: <Widget>[
                    const Positioned.fill(
                      child: TgAvatar(id: 4, firstName: 'Yuki'),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: TgCheckBox.avatarOverlay(
                        checked: _checkAvatar,
                        onChanged: (bool value) =>
                            setState(() => _checkAvatar = value),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (int i = 0; i < 3; i++)
          TgRadioCell(
            text: const <String>['Default', 'Enabled', 'Disabled'][i],
            checked: _radioIndex == i,
            onSelected: () => setState(() => _radioIndex = i),
            divider: i < 2,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 21),
          child: TgSlider(
            value: _sliderValue,
            onChanged: (double value) => setState(() => _sliderValue = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 21),
          child: TgSlider(
            value: _stepValue,
            stepCount: 4,
            onChanged: (double value) => setState(() => _stepValue = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 21),
          child: TgSlider(
            value: _twoSidedValue,
            twoSided: true,
            onChanged: (double value) =>
                setState(() => _twoSidedValue = value),
          ),
        ),
        TgSlideChooser(
          options: const <String>['Off', '1 hour', '8 hours', 'Forever'],
          selectedIndex: _chooserIndex,
          onOptionSelected: (int index) =>
              setState(() => _chooserIndex = index),
        ),
      ],
    );
  }

  // -- Avatars ------------------------------------------------------------

  Widget _buildAvatarsSection(BuildContext context) {
    const List<String> names = <String>[
      'Ruby',
      'Oscar',
      'Violet',
      'Greta',
      'Cyrus',
      'Blake',
      'Piper',
    ];
    return _Section(
      title: 'Avatars',
      children: <Widget>[
        // The seven AvatarDrawable gradient pairs, indexed by id % 7.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (int i = 0; i < names.length; i++)
              TgAvatar(id: i, firstName: names[i], size: 50),
          ],
        ),
        const SizedBox(height: 12),
        // Initials edge cases + the special variants.
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            // Two-word name: first + last initials.
            TgAvatar(id: 5, firstName: 'Marco', lastName: 'Rossi', size: 50),
            // Emoji-leading name keeps the full emoji cluster.
            TgAvatar(id: 3, firstName: '🚀 Rocket', size: 50),
            // Custom text override.
            TgAvatar(id: 1, custom: '+99', size: 50),
            // Rounded-square shape.
            TgAvatar(
              id: 6,
              firstName: 'Squircle',
              size: 50,
              roundRadius: 14,
            ),
            // Saved messages / archived folder recipes (icons are app
            // assets, so the demo shows the gradient plates).
            TgAvatar.saved(size: 50),
            TgAvatar.archived(size: 50),
          ],
        ),
      ],
    );
  }

  // -- Progress -----------------------------------------------------------

  Widget _buildProgressSection(BuildContext context) {
    return _Section(
      title: 'Progress',
      children: <Widget>[
        Row(
          children: <Widget>[
            const TgRadialProgress(),
            const SizedBox(width: 24),
            TgRadialProgress(progress: _progress),
            const SizedBox(width: 24),
            Expanded(child: TgLinearProgress(progress: _progress)),
          ],
        ),
        TgSlider(
          value: _progress,
          onChanged: (double value) => setState(() => _progress = value),
        ),
        _Label('Drag to drive the determinate ring and bar'),
      ],
    );
  }

  // -- Text fields --------------------------------------------------------

  Widget _buildTextFieldsSection(BuildContext context) {
    return _Section(
      title: 'Text fields',
      children: <Widget>[
        const TgTextField(hintText: 'Underline field'),
        const SizedBox(height: 16),
        const TgTextField(hintText: 'Floating label', floatingLabel: true),
        const SizedBox(height: 16),
        const TgTextField.outlined(hintText: 'Outlined field'),
        const SizedBox(height: 16),
        const TgTextField(
          hintText: 'Username',
          errorText: 'This username is already taken',
        ),
      ],
    );
  }

  // -- Empty + skeleton ---------------------------------------------------

  Widget _buildEmptySection(BuildContext context) {
    return _Section(
      title: 'Empty and skeleton states',
      inset: false,
      children: <Widget>[
        SizedBox(
          height: 380,
          child: TgEmptyView(
            image: const Text('🕵️', style: TextStyle(fontSize: 72)),
            title: 'No results',
            subtitle: 'Try a different search term or invite friends '
                'to Telegram.',
            buttonText: _emptyLoading ? 'Stop loading' : 'Simulate loading',
            onButtonPressed: () =>
                setState(() => _emptyLoading = !_emptyLoading),
            loading: _emptyLoading,
          ),
        ),
        const SizedBox(height: 8),
        const SizedBox(
          height: 219, // 3 x 73dp dialog-cell skeleton rows.
          child: TgFlickerLoading(),
        ),
        const SizedBox(
          height: 128, // 2 x 64dp users skeleton rows.
          child: TgFlickerLoading(type: TgFlickerLoadingType.users),
        ),
      ],
    );
  }

  // -- Hints --------------------------------------------------------------

  Widget _buildHintSection(BuildContext context) {
    return _Section(
      title: 'Hints',
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            TgHint(
              text: 'Forwarded messages keep the sender name',
              shown: _hintShown,
              autoHideDuration: null,
              hideByTouch: false,
            ),
            const SizedBox(height: 8),
            TgButton(
              text: _hintShown ? 'Hide hint' : 'Show hint',
              variant: TgButtonVariant.neutral,
              onPressed: () => setState(() => _hintShown = !_hintShown),
            ),
          ],
        ),
      ],
    );
  }

  // -- Chips --------------------------------------------------------------

  Widget _buildChipsSection(BuildContext context) {
    return _Section(
      title: 'Chips',
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String name in _chipNames)
              TgChip(
                name: name,
                avatar: TgAvatar(
                  id: _chipNames.indexOf(name),
                  firstName: name,
                ),
                selectedColor: TgAvatarColors.pairFor(
                  _chipNames.indexOf(name),
                  TelegramTheme.resources(context),
                ).top,
                deleting: _chipDeleting == name,
                onTap: () => setState(() => _chipDeleting = name),
                onDeleted: () => setState(() {
                  _chipNames.remove(name);
                  _chipDeleting = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _Label('Tap a chip to arm delete, tap again to remove'),
        if (_chipNames.length < 4) ...<Widget>[
          const SizedBox(height: 8),
          TgButton(
            text: 'Restore chips',
            variant: TgButtonVariant.neutral,
            onPressed: () => setState(() {
              _chipNames
                ..clear()
                ..addAll(const <String>['Ariana', 'Marco', 'Yuki', 'Nadia']);
              _chipDeleting = null;
            }),
          ),
        ],
      ],
    );
  }

  // -- Overlays -----------------------------------------------------------

  Widget _buildOverlaysSection(BuildContext context) {
    return _Section(
      title: 'Undo bulletin',
      children: <Widget>[
        TgButton(
          text: 'Delete chat (undoable)',
          variant: TgButtonVariant.neutral,
          onPressed: () => Bulletin.showUndo(
            context,
            text: 'Chat deleted',
            undoText: 'Undo',
            onUndo: () {},
            onCommit: () {},
          ),
        ),
      ],
    );
  }

  // -- Navigation ---------------------------------------------------------

  Widget _buildNavigationSection(BuildContext context) {
    return _Section(
      title: 'Navigation',
      children: <Widget>[
        TgButton(
          text: 'Push detail page',
          onPressed: () => Navigator.of(context).push(
            TgPageRoute<void>(
              builder: (BuildContext context) => const _DetailPage(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _Label('Swipe from the left edge to go back'),
      ],
    );
  }
}

/// A white section card: [HeaderCell] title + content, closed by a
/// [ShadowSectionCell], matching the settings-screen rhythm.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.inset = true,
  });

  final String title;
  final List<Widget> children;

  /// Whether the content gets the standard 21dp horizontal inset (off for
  /// full-bleed rows such as cells and skeletons).
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final Color cellBackground = TelegramTheme.colorOf(
      context,
      TelegramColorKey.windowBackgroundWhite,
    );
    return Column(
      children: <Widget>[
        ColoredBox(
          color: cellBackground,
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                HeaderCell(text: title),
                Padding(
                  padding: inset
                      ? const EdgeInsets.fromLTRB(21, 4, 21, 16)
                      : const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ],
            ),
          ),
        ),
        const ShadowSectionCell(),
      ],
    );
  }
}

/// A secondary-gray caption line.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: TelegramTheme.colorOf(
          context,
          TelegramColorKey.windowBackgroundWhiteGrayText,
        ),
      ),
    );
  }
}

/// The detail page pushed via [TgPageRoute]: demonstrates the 150ms
/// slide+fade push and the ActionBarLayout swipe-back gesture.
class _DetailPage extends StatelessWidget {
  const _DetailPage();

  @override
  Widget build(BuildContext context) {
    final Color background = TelegramTheme.colorOf(
      context,
      TelegramColorKey.windowBackgroundGray,
    );
    final Color cellBackground = TelegramTheme.colorOf(
      context,
      TelegramColorKey.windowBackgroundWhite,
    );
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: ListView(
          children: <Widget>[
            ColoredBox(
              color: cellBackground,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const HeaderCell(text: 'Detail page'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(21, 4, 21, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const _Label(
                            'Pushed with TgPageRoute: 48dp slide + fade in '
                            '150ms. Swipe from the left edge (or tap below) '
                            'to go back.'),
                        const SizedBox(height: 16),
                        TgButton(
                          text: 'Back',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
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
