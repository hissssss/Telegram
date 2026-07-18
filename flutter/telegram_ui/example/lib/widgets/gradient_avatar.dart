// Colorful gradient avatar circles for the gallery's fake data — vivid
// content so the liquid-glass surfaces have something to refract.

import 'package:flutter/widgets.dart';

/// The classic Telegram avatar gradient pairs (red, orange, violet, green,
/// cyan, blue, pink — AvatarDrawable's palette, approximated).
const List<List<Color>> kAvatarGradients = <List<Color>>[
  <Color>[Color(0xFFFF845E), Color(0xFFD45246)], // red
  <Color>[Color(0xFFFEBB5B), Color(0xFFF68136)], // orange
  <Color>[Color(0xFFB694F9), Color(0xFF6C61DF)], // violet
  <Color>[Color(0xFF9AD164), Color(0xFF46BA43)], // green
  <Color>[Color(0xFF53EDD6), Color(0xFF28C9B7)], // cyan
  <Color>[Color(0xFF5CAFFA), Color(0xFF408ACF)], // blue
  <Color>[Color(0xFFFF8AAC), Color(0xFFD95574)], // pink
];

/// A circular gradient avatar with the name's initial, sized by the parent's
/// tight constraints (falls back to 46x46 when unconstrained).
class GradientAvatar extends StatelessWidget {
  const GradientAvatar({super.key, required this.name, this.seed = 0});

  /// The display name; the first rune becomes the initial.
  final String name;

  /// Selects the gradient pair (`seed % kAvatarGradients.length`).
  final int seed;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(46),
      painter: GradientAvatarPainter(name: name, seed: seed),
    );
  }
}

/// Paints a vertical-gradient circle filling the square and a centered
/// white initial at ~42% of the diameter.
class GradientAvatarPainter extends CustomPainter {
  const GradientAvatarPainter({required this.name, required this.seed});

  final String name;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final List<Color> colors = kAvatarGradients[seed % kAvatarGradients.length];
    final Rect rect = Offset.zero & size;
    final double radius = size.shortestSide / 2;
    final Paint fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ).createShader(rect);
    canvas.drawCircle(rect.center, radius, fill);

    if (name.isEmpty) {
      return;
    }
    final TextPainter text = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(name.runes.first).toUpperCase(),
        style: TextStyle(
          color: const Color(0xFFFFFFFF),
          fontSize: radius * 0.84,
          fontWeight: FontWeight.w500,
          fontFamily: 'RobotoMedium',
          package: 'telegram_ui',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(
      canvas,
      rect.center - Offset(text.width / 2, text.height / 2),
    );
    text.dispose();
  }

  @override
  bool shouldRepaint(GradientAvatarPainter oldDelegate) =>
      oldDelegate.name != name || oldDelegate.seed != seed;
}
