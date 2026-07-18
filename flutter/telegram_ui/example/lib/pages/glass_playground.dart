// Live liquid-glass playground: every LiquidGlassSettings field on a slider,
// a tier selector, and one GlassPanel floating over a deliberately busy
// background (gradient + pattern) so refraction is visible.

import 'package:flutter/material.dart';
import 'package:telegram_ui/telegram_ui.dart';

/// The glass playground page.
class GlassPlaygroundPage extends StatefulWidget {
  const GlassPlaygroundPage({super.key});

  @override
  State<GlassPlaygroundPage> createState() => _GlassPlaygroundPageState();
}

class _GlassPlaygroundPageState extends State<GlassPlaygroundPage> {
  double _thickness = kGlassThicknessDefaultDp;
  double _intensity = kGlassRefractIntensityDefault;
  double _index = kGlassRefractIndex;
  double _radius = 28.0;
  double _tintAlpha = kGlassTintAlphaLiquid;
  GlassTier _tier = GlassTier.liquid;

  @override
  Widget build(BuildContext context) {
    final Color tintBase = TelegramTheme.colorOf(
      context,
      TelegramColorKey.windowBackgroundWhite,
    );
    // Note: GlassPanel treats a fully transparent tint as "use the resolved
    // style's background color", so alpha 0 falls back to the themed default.
    final LiquidGlassSettings settings = LiquidGlassSettings(
      thickness: _thickness,
      refractIntensity: _intensity,
      refractIndex: _index,
      tintColor: tintBase.withValues(alpha: _tintAlpha),
      radii: GlassRadii.all(_radius),
    );
    final GlassCapability? capability = GlassSettings.instance.capability;
    final String probeLabel = capability == null
        ? 'probe pending — liquid renders frosted until it lands'
        : capability.liquidSupported
            ? 'probe: liquid supported'
            : 'probe: ${capability.reason}';

    return GlassBackdropScope(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const CustomPaint(painter: BusyBackgroundPainter()),
          SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: 260,
                      height: 150,
                      child: GlassPanel(
                        tier: _tier,
                        settings: settings,
                        borderRadius: GlassRadii.all(_radius),
                        child: Center(
                          child: Text(
                            'telegram_ui',
                            style: TextStyle(
                              fontSize: 20,
                              fontFamily: 'RobotoMedium',
                              package: 'telegram_ui',
                              fontWeight: FontWeight.w500,
                              color: TelegramTheme.colorOf(
                                context,
                                TelegramColorKey.windowBackgroundWhiteBlackText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _ControlPanel(
                  tier: _tier,
                  onTier: (GlassTier tier) => setState(() => _tier = tier),
                  probeLabel: probeLabel,
                  children: <Widget>[
                    _slider('Thickness', _thickness, 0, 40,
                        (double v) => setState(() => _thickness = v)),
                    _slider('Intensity', _intensity, 0, 2,
                        (double v) => setState(() => _intensity = v)),
                    _slider('Refract index', _index, 1, 3,
                        (double v) => setState(() => _index = v)),
                    _slider('Radius', _radius, 0, 75,
                        (double v) => setState(() => _radius = v)),
                    _slider('Tint alpha', _tintAlpha, 0, 1,
                        (double v) => setState(() => _tintAlpha = v)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 104,
          child: Text('$label\n${value.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.tier,
    required this.onTier,
    required this.probeLabel,
    required this.children,
  });

  final GlassTier tier;
  final ValueChanged<GlassTier> onTier;
  final String probeLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: FrostedPanel(
        borderRadius: const GlassRadii.all(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SegmentedButton<GlassTier>(
                segments: GlassTier.values
                    .map((GlassTier value) => ButtonSegment<GlassTier>(
                        value: value, label: Text(value.name)))
                    .toList(),
                selected: <GlassTier>{tier},
                onSelectionChanged: (Set<GlassTier> selection) =>
                    onTier(selection.first),
              ),
              const SizedBox(height: 4),
              Text(probeLabel, style: const TextStyle(fontSize: 11)),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Vivid gradient + circle/stripe pattern so glass has structure to refract.
class BusyBackgroundPainter extends CustomPainter {
  const BusyBackgroundPainter();

  static const List<Color> _gradient = <Color>[
    Color(0xFF1A2980),
    Color(0xFF26D0CE),
    Color(0xFFF8B500),
    Color(0xFFC33764),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradient,
        ).createShader(rect),
    );

    // Dot grid.
    final Paint dot = Paint()..color = const Color(0x66FFFFFF);
    const double step = 36;
    for (double y = step / 2; y < size.height; y += step) {
      for (double x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 5, dot);
      }
    }

    // Diagonal stripes.
    final Paint stripe = Paint()
      ..color = const Color(0x33000000)
      ..strokeWidth = 14;
    for (double x = -size.height; x < size.width; x += 90) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stripe,
      );
    }
  }

  @override
  bool shouldRepaint(BusyBackgroundPainter oldDelegate) => false;
}
