// Adversarial probe for the code-review finding: "Late shader load never
// repaints panels with an explicit liquid tier override".
//
// Mechanism under test: after TgShaders.isInitialized flips true and
// GlassSettings notifies (the late-probe-completion path), does the paint
// boundary containing a GlassPanel(tier: GlassTier.liquid) get repainted?
// The scope-resolved sibling is the control: its resolved tier flips
// frosted -> liquid, the render-object tier setter fires markNeedsPaint, and
// its boundary repaints.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/telegram_ui.dart';

class _CountPainter extends CustomPainter {
  _CountPainter(this.onPaint);
  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) => onPaint();

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  testWidgets('late shader load: repaint scheduling per panel kind', (tester) async {
    TgShaders.debugReset();
    addTearDown(TgShaders.debugReset);

    final GlassSettings settings = GlassSettings(
      probe: () async => const GlassCapability.supported(),
    );

    int scopedPaints = 0;
    int explicitPaints = 0;
    const Key scopedKey = Key('scoped');
    const Key explicitKey = Key('explicit');
    const GlassSurfaceStyle style = GlassSurfaceStyle(
      backgroundColor: Color(0xD9FFFFFF),
      strokeColorTop: Color(0x28FFFFFF),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GlassBackdropScope(
          settings: settings,
          probeOnMount: false,
          child: Column(
            children: <Widget>[
              RepaintBoundary(
                child: SizedBox(
                  width: 120,
                  height: 60,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: CustomPaint(painter: _CountPainter(() => scopedPaints++)),
                      ),
                      const Positioned.fill(
                        child: GlassPanel(key: scopedKey, style: style),
                      ),
                    ],
                  ),
                ),
              ),
              RepaintBoundary(
                child: SizedBox(
                  width: 120,
                  height: 60,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: CustomPaint(painter: _CountPainter(() => explicitPaints++)),
                      ),
                      const Positioned.fill(
                        child: GlassPanel(
                          key: explicitKey,
                          tier: GlassTier.liquid, // explicit override
                          style: style,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final RenderGlassSurface scoped =
        tester.renderObject<RenderGlassSurface>(find.byKey(scopedKey));
    final RenderGlassSurface explicit =
        tester.renderObject<RenderGlassSurface>(find.byKey(explicitKey));

    // Pre-probe state: scope resolves liquid request down to frosted; the
    // explicit override is taken as-is.
    expect(scoped.tier, GlassTier.frosted);
    expect(explicit.tier, GlassTier.liquid);
    expect(scopedPaints, greaterThan(0));
    expect(explicitPaints, greaterThan(0));

    // The late shader load + probe completion (device order: TgShaders
    // initializes inside GlassRuntimeProbe.run, THEN applyCapability
    // notifies).
    await TgShaders.ensureInitialized();
    expect(TgShaders.isInitialized, isTrue);

    final int scopedBefore = scopedPaints;
    final int explicitBefore = explicitPaints;

    settings.applyCapability(const GlassCapability.supported());
    await tester.pump();

    // Control: the scope-resolved panel rebuilt with tier liquid -> setter
    // fired markNeedsPaint -> its boundary repainted.
    expect(scoped.tier, GlassTier.liquid, reason: 'scope data must have flipped');
    expect(scopedPaints, greaterThan(scopedBefore),
        reason: 'scope-resolved panel boundary must repaint on upgrade');

    // The claim under test: the explicit-override panel's boundary is never
    // repainted, so on Impeller it would keep showing the degraded frosted
    // output even though effectiveTier now returns liquid.
    expect(explicitPaints, explicitBefore,
        reason: 'FINDING CONFIRMED if equal: no repaint scheduled for the '
            'explicit-tier panel after the shader became available');

    // Extra pumps do not help either — nothing is scheduled at all.
    await tester.pump();
    await tester.pump();
    expect(explicitPaints, explicitBefore);
  });
}
