// Port of `ui/Components/AvatarDrawable.java` (spec_primitives.md §3): the
// placeholder avatar — a circle (or rounded rect) filled with a vertical
// two-stop gradient picked from a 7-pair palette by peer id, with uppercase
// initials drawn on top, designed at 50dp and canvas-scaled to the actual
// diameter.
//
// Faithful details:
// - gradient pair order Red, Orange, Violet, Green, Cyan, Blue, Pink
//   (Theme.java:3539-3540), resolved through the
//   `avatar_background*` / `avatar_background2*` theme keys;
// - `index = abs(id % 7)` with Java truncating-remainder semantics
//   (AvatarDrawable.java:179-181) — Dart's `%` is Euclidean, so the port
//   uses `remainder()`;
// - peer-color hue → index map (AvatarDrawable.java:166-177);
// - initials: emoji-aware first grapheme of `firstName` + first grapheme of
//   the LAST word of `lastName`, ZWNJ-joined (AvatarDrawable.java:509-542),
//   uppercased at draw time (AvatarDrawable.java:717); empty `firstName`
//   promotes `lastName` (AvatarDrawable.java:455-458);
// - text: 18dp Roboto Medium `avatar_text`, laid out once and canvas-scaled
//   by `size / 50dp` around the center (AvatarDrawable.java:130-133,
//   736-738);
// - Saved pair `avatar_backgroundSaved` → `avatar_background2Saved`
//   (AvatarDrawable.java:260-263), Archived flat `avatar_backgroundArchived`
//   (AvatarDrawable.java:602-605).
//
// Divergences (documented inline):
// - the multi-word-firstName fallback ports the evident intent — first
//   grapheme of the LAST word (spec_primitives.md §3.3) — not the Java
//   off-by-variable `firstName.substring(result.length())` quirk
//   (AvatarDrawable.java:531-535) which reads the second grapheme;
// - `takeFirstCharacter` uses Dart extended grapheme clusters, which agree
//   with the Java emoji-run + code-point logic for emoji and BMP text and
//   additionally keep combining marks attached.
//
// Deliberately NOT ported: the 20+ icon `avatarType`s and their
// `Theme.avatarDrawables` assets, the 4-stop `advancedGradients` profile
// style (AvatarDrawable.java:109-117), the story ring / rotate-45 background,
// the archived-folder Lottie arrow + hidden progress, `Emoji.replaceEmoji`
// image spans (Flutter shapes emoji natively), drawable `setAlpha` /
// `setColorFilter` plumbing (wrap in [Opacity] instead), the
// `needApplyColorAccent` accent re-tint (Theme.changeColorAccent), and the
// `MessagesController` peer-palette lookup (`setPeerColor` id >= 14 — pass an
// explicit [TgAvatar.peerColor] or [TgAvatar.color]/[TgAvatar.color2]
// instead).
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../foundation/tg_text_styles.dart';
import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';

/// Initials text size: 18dp (`namePaint.setTextSize(dp(18))`,
/// AvatarDrawable.java:132).
const double kTgAvatarTextSize = 18.0;

/// The diameter the initials are designed for: 50dp — the canvas is scaled
/// by `size / dp(50)` (AvatarDrawable.java:736-738), so a 56dp avatar draws
/// 20.16dp-effective initials.
const double kTgAvatarBaseSize = 50.0;

/// Number of gradient pairs: 7 (`Theme.keys_avatar_background.length`,
/// Theme.java:3539).
const int kTgAvatarColorCount = 7;

/// Zero-width non-joiner between the two initials
/// (`result.append("‌")`, AvatarDrawable.java:523-524).
const String kTgAvatarInitialsJoiner = '‌';

/// The 7-pair avatar gradient palette and its selection math
/// (AvatarDrawable.java:166-181, Theme.java:3539-3540).
abstract final class TgAvatarColors {
  /// Top gradient stops in palette order Red, Orange, Violet, Green, Cyan,
  /// Blue, Pink (`Theme.keys_avatar_background`, Theme.java:3539).
  static const List<int> backgroundKeys = <int>[
    TelegramColorKey.avatar_backgroundRed,
    TelegramColorKey.avatar_backgroundOrange,
    TelegramColorKey.avatar_backgroundViolet,
    TelegramColorKey.avatar_backgroundGreen,
    TelegramColorKey.avatar_backgroundCyan,
    TelegramColorKey.avatar_backgroundBlue,
    TelegramColorKey.avatar_backgroundPink,
  ];

  /// Bottom gradient stops, same order (`Theme.keys_avatar_background2`,
  /// Theme.java:3540).
  static const List<int> background2Keys = <int>[
    TelegramColorKey.avatar_background2Red,
    TelegramColorKey.avatar_background2Orange,
    TelegramColorKey.avatar_background2Violet,
    TelegramColorKey.avatar_background2Green,
    TelegramColorKey.avatar_background2Cyan,
    TelegramColorKey.avatar_background2Blue,
    TelegramColorKey.avatar_background2Pink,
  ];

  /// Port of `getColorIndex(long id)`: `abs(id % 7)`
  /// (AvatarDrawable.java:179-181).
  ///
  /// Java's `%` truncates toward zero (`-8 % 7 == -1`, so `abs` gives 1)
  /// while Dart's `%` is Euclidean (`-8 % 7 == 6`); [int.remainder] restores
  /// the Java semantics.
  static int indexFor(int id) => id.remainder(kTgAvatarColorCount).abs();

  /// The hue → palette-index map of `getPeerColorIndex`
  /// (AvatarDrawable.java:170-176), for a hue in `0..360`.
  static int indexForHue(int hue) {
    if (hue >= 345 || hue < 29) return 0; // red
    if (hue < 67) return 1; // orange
    if (hue < 140) return 3; // green
    if (hue < 199) return 4; // cyan
    if (hue < 234) return 5; // blue
    if (hue < 301) return 2; // violet
    return 6; // pink
  }

  /// Port of `getPeerColorIndex(int color)` (AvatarDrawable.java:166-177):
  /// the color's HSV hue, truncated to an int like the Java `(int)` cast,
  /// through [indexForHue].
  static int peerColorIndex(Color color) =>
      indexForHue(HSVColor.fromColor(color).hue.toInt());

  /// The (top, bottom) theme-key pair for [id]
  /// (`Theme.keys_avatar_background[getColorIndex(id)]` /
  /// `keys_avatar_background2[...]`, AvatarDrawable.java:445-446).
  static ({int top, int bottom}) keysFor(int id) {
    final int index = indexFor(id);
    return (top: backgroundKeys[index], bottom: background2Keys[index]);
  }

  /// The resolved (top, bottom) gradient pair for [id] through [resources].
  static ({Color top, Color bottom}) pairFor(
    int id,
    TelegramResources resources,
  ) {
    final ({int top, int bottom}) keys = keysFor(id);
    return (
      top: resources.getColor(keys.top),
      bottom: resources.getColor(keys.bottom),
    );
  }
}

/// Port of `takeFirstCharacter` (AvatarDrawable.java:390-396): the first
/// grapheme of [text] — a leading emoji sequence is kept whole, otherwise
/// one user-perceived character (surrogate-safe).
///
/// The Java splits on `Emoji.parseEmojis` ranges or one code point; Dart
/// extended grapheme clusters make both cases (and combining marks) fall out
/// of `Characters.first`. Returns the empty string for empty input, like the
/// Java `codePointCount == 0` path.
String tgAvatarTakeFirstCharacter(String text) {
  if (text.isEmpty) {
    return '';
  }
  return text.characters.first;
}

/// Port of `getAvatarSymbols(firstName, lastName, custom, result)`
/// (AvatarDrawable.java:509-542) plus the empty-firstName promotion from
/// `setInfo` (AvatarDrawable.java:455-458):
///
/// - [custom] overrides everything;
/// - empty/null [firstName] promotes [lastName] into its place;
/// - result = first grapheme of firstName, then — ZWNJ-joined — the first
///   grapheme of the LAST word of lastName (AvatarDrawable.java:517-526);
/// - with no lastName, a multi-word firstName contributes the first grapheme
///   of its last word instead (AvatarDrawable.java:527-539; the Java
///   `firstName.substring(index)` where `index = result.length()` is an
///   off-by-variable quirk — the port follows the intent per
///   spec_primitives.md §3.3).
///
/// The result is NOT uppercased — the Java uppercases at draw time
/// (AvatarDrawable.java:717), as does [TgAvatar].
String tgAvatarInitials({String? firstName, String? lastName, String? custom}) {
  if (custom != null) {
    return custom;
  }
  // Empty firstName promotion (AvatarDrawable.java:455-458).
  if (firstName == null || firstName.isEmpty) {
    firstName = lastName;
    lastName = null;
  }
  final StringBuffer result = StringBuffer();
  if (firstName != null && firstName.isNotEmpty) {
    result.write(tgAvatarTakeFirstCharacter(firstName));
  }
  if (lastName != null && lastName.isNotEmpty) {
    // Last word of lastName (AvatarDrawable.java:518-522).
    String lastNameLastWord = lastName;
    final int index = lastNameLastWord.lastIndexOf(' ');
    if (index >= 0) {
      lastNameLastWord = lastNameLastWord.substring(index + 1);
    }
    result.write(kTgAvatarInitialsJoiner);
    result.write(tgAvatarTakeFirstCharacter(lastNameLastWord));
  } else if (firstName != null && firstName.isNotEmpty) {
    // Multi-word firstName fallback: the last space that is neither trailing
    // nor followed by another space (AvatarDrawable.java:528-530).
    for (int a = firstName.length - 1; a >= 0; a--) {
      if (firstName[a] == ' ') {
        if (a != firstName.length - 1 && firstName[a + 1] != ' ') {
          result.write(kTgAvatarInitialsJoiner);
          result.write(tgAvatarTakeFirstCharacter(firstName.substring(a + 1)));
          break;
        }
      }
    }
  }
  return result.toString();
}

/// The `AvatarDrawable.draw` port (AvatarDrawable.java:559-744, minus the
/// icon/archive branches): a circle — or a rounded rect when [roundRadius]
/// > 0 (AvatarDrawable.java:591-596) — filled with a vertical two-stop
/// CLAMP gradient (AvatarDrawable.java:571-578; flat when [color] ==
/// [color2], AvatarDrawable.java:579-582), with [initials] centered on top
/// at [textSize], canvas-scaled by `width / 50dp`
/// (AvatarDrawable.java:736-738).
class TgAvatarPainter extends CustomPainter {
  TgAvatarPainter({
    required this.color,
    required this.color2,
    this.initials = '',
    this.textColor = const Color(0xFFFFFFFF),
    this.textSize = kTgAvatarTextSize,
    this.roundRadius = 0.0,
    super.repaint,
  });

  /// Top gradient stop (`getColor()`, AvatarDrawable.java:572).
  final Color color;

  /// Bottom gradient stop (`getColor2()`, AvatarDrawable.java:573); equal to
  /// [color] for a flat fill (`setColor`, AvatarDrawable.java:359-364).
  final Color color2;

  /// Uppercased, ZWNJ-joined initials (AvatarDrawable.java:717); empty draws
  /// no text.
  final String initials;

  /// Initials color — the caller resolves `avatar_text`
  /// (AvatarDrawable.java:566).
  final Color textColor;

  /// Base text size laid out before canvas scaling, default 18dp
  /// (AvatarDrawable.java:132; `setTextSize`, AvatarDrawable.java:374-376).
  final double textSize;

  /// Rounded-rect corner radius; `<= 0` draws a circle
  /// (AvatarDrawable.java:591-596; `setRoundRadius`,
  /// AvatarDrawable.java:775-777).
  final double roundRadius;

  /// The canvas scale applied around the center before drawing initials:
  /// `size / dp(50)` (AvatarDrawable.java:736) — the Java uses
  /// `bounds.width()` as the size (AvatarDrawable.java:565).
  double textScaleFor(Size size) => size.width / kTgAvatarBaseSize;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = size.width; // `int size = bounds.width()` (AV:565).
    final Paint backgroundPaint = Paint();
    if (color != color2) {
      // Vertical two-stop LinearGradient, CLAMP, bottom at bounds.height()
      // (AvatarDrawable.java:574-577).
      backgroundPaint.shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0.0, size.height),
        <Color>[color, color2],
        null,
        TileMode.clamp,
      );
    } else {
      backgroundPaint.color = color;
    }
    if (roundRadius > 0.0) {
      // (AvatarDrawable.java:591-593.)
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0.0, 0.0, side, side),
          Radius.circular(roundRadius),
        ),
        backgroundPaint,
      );
    } else {
      // (AvatarDrawable.java:594-595.)
      canvas.drawCircle(Offset(side / 2.0, side / 2.0), side / 2.0, backgroundPaint);
    }

    if (initials.isEmpty) {
      return;
    }
    // 18dp Roboto Medium layout (AvatarDrawable.java:130-133, 721), then a
    // center-pivot scale of size/50 (AvatarDrawable.java:736-738).
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: initials,
        style: TextStyle(
          color: textColor,
          fontSize: textSize,
          fontWeight: FontWeight.w500,
          fontFamily: 'RobotoMedium',
          package: 'telegram_ui',
        ),
      ),
      textDirection: TextDirection.ltr,
      textHeightBehavior: kTgTextHeightBehavior,
    )..layout();
    final double scale = textScaleFor(size);
    canvas.save();
    canvas.translate(side / 2.0, side / 2.0);
    canvas.scale(scale, scale);
    canvas.translate(-side / 2.0, -side / 2.0);
    // `(size - textWidth) / 2 - textLeft, (size - textHeight) / 2`
    // (AvatarDrawable.java:738).
    textPainter.paint(
      canvas,
      Offset(
        (side - textPainter.width) / 2.0,
        (side - textPainter.height) / 2.0,
      ),
    );
    canvas.restore();
    textPainter.dispose();
  }

  @override
  bool shouldRepaint(TgAvatarPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.color2 != color2 ||
        oldDelegate.initials != initials ||
        oldDelegate.textColor != textColor ||
        oldDelegate.textSize != textSize ||
        oldDelegate.roundRadius != roundRadius;
  }
}

enum _TgAvatarVariant { normal, saved, archived }

/// The `ui/Components/AvatarDrawable.java` port — the initials/gradient
/// placeholder avatar that fills the DialogCell/UserCell avatar slots.
///
/// Background pair resolution order (mirroring `setInfo`,
/// AvatarDrawable.java:413-448 and `setColor`, AvatarDrawable.java:359-372):
///
/// 1. explicit [color] (+ optional [color2]) — the `setColor` ports;
/// 2. [peerColor] — hue-mapped to a palette pair
///    ([TgAvatarColors.peerColorIndex], AvatarDrawable.java:479-480);
/// 3. [id] — `abs(id % 7)` into the 7-pair palette
///    (AvatarDrawable.java:445-446).
///
/// [TgAvatar.saved] uses the Saved-Messages pair
/// (AvatarDrawable.java:260-263) and [TgAvatar.archived] the flat archived
/// gray (AvatarDrawable.java:602-605); both draw no initials (their icons
/// are not ported).
///
/// Like the Java drawable (`getIntrinsicWidth/Height` return 0,
/// AvatarDrawable.java:761-769) the widget has no intrinsic size: give it
/// bounds via [size] or a tight parent (an avatar slot). An [image] wins
/// over the placeholder, clipped to the same shape.
///
/// Like every component in this package, the avatar takes an optional
/// [resources] override that wins over the ambient theme (the Java
/// `resourcesProvider` convention); otherwise keys resolve through
/// [TelegramTheme.colorOf] for per-key rebuild granularity.
class TgAvatar extends StatelessWidget {
  /// Creates a normal avatar (`AVATAR_TYPE_NORMAL`).
  const TgAvatar({
    super.key,
    this.id = 0,
    this.firstName,
    this.lastName,
    this.custom,
    this.peerColor,
    this.color,
    this.color2,
    this.image,
    this.size,
    this.roundRadius = 0.0,
    this.textSize = kTgAvatarTextSize,
    this.resources,
  }) : _variant = _TgAvatarVariant.normal;

  /// Saved-Messages/Replies avatar: `avatar_backgroundSaved` →
  /// `avatar_background2Saved` gradient (AvatarDrawable.java:260-263), no
  /// initials.
  const TgAvatar.saved({
    super.key,
    this.image,
    this.size,
    this.roundRadius = 0.0,
    this.resources,
  })  : _variant = _TgAvatarVariant.saved,
        id = 0,
        firstName = null,
        lastName = null,
        custom = null,
        peerColor = null,
        color = null,
        color2 = null,
        textSize = kTgAvatarTextSize;

  /// Archived-folder avatar: flat `avatar_backgroundArchived`
  /// (AvatarDrawable.java:602-605; the hidden-state
  /// `avatar_backgroundArchivedHidden` blue of AvatarDrawable.java:258-259
  /// and the Lottie arrow are not ported), no initials.
  const TgAvatar.archived({
    super.key,
    this.image,
    this.size,
    this.roundRadius = 0.0,
    this.resources,
  })  : _variant = _TgAvatarVariant.archived,
        id = 0,
        firstName = null,
        lastName = null,
        custom = null,
        peerColor = null,
        color = null,
        color2 = null,
        textSize = kTgAvatarTextSize;

  final _TgAvatarVariant _variant;

  /// Peer id driving palette selection, `abs(id % 7)`
  /// (AvatarDrawable.java:179-181, 445-446).
  final int id;

  /// First name feeding the initials (AvatarDrawable.java:514-516).
  final String? firstName;

  /// Last name feeding the initials — first grapheme of its last word
  /// (AvatarDrawable.java:517-526).
  final String? lastName;

  /// Custom initials override (`custom`, AvatarDrawable.java:511-512).
  final String? custom;

  /// An account's custom color: hue-mapped into the palette
  /// (`getPeerColorIndex`, AvatarDrawable.java:166-177, 479-480). Ignored
  /// when [color] is set.
  final Color? peerColor;

  /// Explicit top color (`setColor`, AvatarDrawable.java:359-372) — also the
  /// direct peer-palette path (AvatarDrawable.java:435-436). Wins over
  /// [peerColor] and [id].
  final Color? color;

  /// Explicit bottom color; defaults to [color] (flat fill,
  /// AvatarDrawable.java:359-364).
  final Color? color2;

  /// Photo replacing the placeholder, clipped to the avatar shape and
  /// cover-fit — the ImageReceiver slot this drawable backs in Java cells.
  final ImageProvider? image;

  /// Side length; null defers to the parent constraints (the Java drawable
  /// has intrinsic size 0, AvatarDrawable.java:761-769).
  final double? size;

  /// Rounded-rect corner radius; 0 (default) draws a circle
  /// (`setRoundRadius`, AvatarDrawable.java:775-777).
  final double roundRadius;

  /// Base initials size before the `size / 50dp` canvas scale, default 18dp
  /// (AvatarDrawable.java:132; `setTextSize`, AvatarDrawable.java:374-376).
  final double textSize;

  /// Per-surface palette override; defaults to the ambient theme (the Java
  /// `resourcesProvider` convention, AvatarDrawable.java:127-129).
  final TelegramResources? resources;

  Color _resolve(BuildContext context, int key) {
    final TelegramResources? resources = this.resources;
    if (resources != null) {
      return resources.getColor(key);
    }
    return TelegramTheme.colorOf(context, key);
  }

  ({Color top, Color bottom}) _pair(BuildContext context) {
    switch (_variant) {
      case _TgAvatarVariant.saved:
        return (
          top: _resolve(context, TelegramColorKey.avatar_backgroundSaved),
          bottom: _resolve(context, TelegramColorKey.avatar_background2Saved),
        );
      case _TgAvatarVariant.archived:
        final Color flat =
            _resolve(context, TelegramColorKey.avatar_backgroundArchived);
        return (top: flat, bottom: flat);
      case _TgAvatarVariant.normal:
        final Color? color = this.color;
        if (color != null) {
          return (top: color, bottom: color2 ?? color);
        }
        final Color? peerColor = this.peerColor;
        final int index = peerColor != null
            ? TgAvatarColors.peerColorIndex(peerColor)
            : TgAvatarColors.indexFor(id);
        return (
          top: _resolve(context, TgAvatarColors.backgroundKeys[index]),
          bottom: _resolve(context, TgAvatarColors.background2Keys[index]),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ({Color top, Color bottom}) pair = _pair(context);
    final String initials = _variant == _TgAvatarVariant.normal
        ? tgAvatarInitials(
            firstName: firstName,
            lastName: lastName,
            custom: custom,
          )
        // Uppercased at draw time (AvatarDrawable.java:717).
            .toUpperCase()
        : '';
    final ImageProvider? image = this.image;
    Widget result = CustomPaint(
      painter: TgAvatarPainter(
        color: pair.top,
        color2: pair.bottom,
        initials: initials,
        textColor: _resolve(context, TelegramColorKey.avatar_text),
        textSize: textSize,
        roundRadius: roundRadius,
      ),
      child: image == null
          ? null
          : _clip(
              Image(
                image: image,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
    );
    final double? size = this.size;
    if (size != null) {
      result = SizedBox.square(dimension: size, child: result);
    }
    return result;
  }

  Widget _clip(Widget child) {
    if (roundRadius > 0.0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(roundRadius),
        child: child,
      );
    }
    return ClipOval(child: child);
  }
}
