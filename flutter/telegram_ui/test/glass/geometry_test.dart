// Ring-1 tests for lib/src/glass/geometry.dart — the port of
// BlurredBackgroundDrawable's Props/drawStroke machinery and the
// LiquidGlassEffect radius clamps.
//
// Probe-point containment values below are hand-derived from circle
// geometry; every probe keeps >= 0.2 px of margin from any path boundary so
// Path.contains never sits on an edge.

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/blur_math.dart';
import 'package:telegram_ui/src/glass/geometry.dart';
import 'package:telegram_ui/src/tokens/glass_metrics.g.dart';
import 'package:telegram_ui/src/tokens/liquid_glass_uniforms.g.dart';

/// Locates flutter/tool/fixtures/uniform_fixtures.json from the test's
/// working directory (the package root) or any of its ancestors.
File _uniformFixtures() {
  const String rel = 'tool/fixtures/uniform_fixtures.json';
  Directory dir = Directory.current;
  for (int i = 0; i < 6; i++) {
    for (final String candidate in <String>['${dir.path}/$rel', '${dir.path}/flutter/$rel']) {
      final File file = File(candidate);
      if (file.existsSync()) {
        return file;
      }
    }
    dir = dir.parent;
  }
  fail('uniform_fixtures.json not found from ${Directory.current.path}');
}

void main() {
  // The mainTabs pill at density 1: 344x57 (56.668dp rounded up in tests for
  // clean numbers), uniform radius 28.
  final Rect pillRect = const Rect.fromLTRB(0, 0, 344, 57);

  group('GlassRadii shader quad packing', () {
    test('is (RB, RT, LB, LT) per LiquidGlassEffect.java:93', () {
      const GlassRadii radii = GlassRadii(topLeft: 1, topRight: 2, bottomRight: 3, bottomLeft: 4);
      expect(radii.shaderQuad, <double>[3, 2, 4, 1]);
    });

    test('quad indices line up with the generated uniform slots', () {
      // Slots 6..9 are (RB, RT, LB, LT); quad[i] must land on slot 6+i.
      expect(kUniformRadiusRightBottom, 6);
      expect(kUniformRadiusRightTop, 7);
      expect(kUniformRadiusLeftBottom, 8);
      expect(kUniformRadiusLeftTop, 9);
    });
  });

  group('rescaleVerticalPairs (LiquidGlassEffect.java:56-65)', () {
    test('no-op when both pairs fit', () {
      const GlassRadii radii = GlassRadii.all(28);
      expect(radii.rescaleVerticalPairs(100), radii);
    });

    test('strict >: sum exactly equal to height is untouched (fixture b04)', () {
      const GlassRadii radii = GlassRadii.all(28);
      expect(radii.rescaleVerticalPairs(56), radii);
    });

    test('asymmetric right-pair overflow splits proportionally (fixture b02)', () {
      const GlassRadii radii = GlassRadii(topLeft: 8, topRight: 42, bottomRight: 28, bottomLeft: 8);
      final GlassRadii out = radii.rescaleVerticalPairs(56);
      // a = 42/70 = 0.6 -> RT = 33.6, RB = 22.4; left pair untouched.
      expect(out.topRight, closeTo(33.6, 1e-9));
      expect(out.bottomRight, closeTo(22.4, 1e-9));
      expect(out.topLeft, 8);
      expect(out.bottomLeft, 8);
    });

    test('zero partner radius: one corner absorbs the full height (fixture b06)', () {
      const GlassRadii radii = GlassRadii(
        topLeft: 80,
        topRight: 12,
        bottomRight: 12,
        bottomLeft: 0,
      );
      final GlassRadii out = radii.rescaleVerticalPairs(56);
      expect(out.topLeft, closeTo(56, 1e-9));
      expect(out.bottomLeft, closeTo(0, 1e-9));
      expect(out.topRight, 12);
      expect(out.bottomRight, 12);
    });

    test('no horizontal clamp (fixture b07)', () {
      const GlassRadii radii = GlassRadii.all(100);
      // Width 56 would overflow horizontally; only height 400 matters.
      expect(radii.rescaleVerticalPairs(400), radii);
    });
  });

  group('capUniform (Props.build:253-258, getOutline:342)', () {
    test('uniform radius above min(w,h)/2 is capped', () {
      expect(const GlassRadii.all(100).capUniform(344, 56), const GlassRadii.all(28));
    });

    test('uniform radius at or below the cap is untouched', () {
      expect(const GlassRadii.all(28).capUniform(344, 56), const GlassRadii.all(28));
      expect(const GlassRadii.all(10).capUniform(344, 56), const GlassRadii.all(10));
    });

    test('non-uniform radii are never capped (Java parity)', () {
      const GlassRadii radii = GlassRadii(
        topLeft: 100,
        topRight: 100,
        bottomRight: 100,
        bottomLeft: 99,
      );
      expect(radii.capUniform(344, 56), radii);
    });
  });

  group('uniform fixture parity (flutter/tool/fixtures/uniform_fixtures.json)', () {
    test('rescaleVerticalPairs + shaderQuad match every pushed step', () {
      final Map<String, dynamic> data =
          jsonDecode(_uniformFixtures().readAsStringSync()) as Map<String, dynamic>;
      final List<dynamic> cases = data['cases'] as List<dynamic>;
      expect(cases.length, data['caseCount']);

      int checked = 0;
      for (final dynamic c in cases) {
        final Map<String, dynamic> caseMap = c as Map<String, dynamic>;
        final String name = caseMap['name'] as String;
        final List<dynamic> steps = caseMap['steps'] as List<dynamic>;
        for (int i = 0; i < steps.length; i++) {
          final Map<String, dynamic> step = steps[i] as Map<String, dynamic>;
          final Map<String, dynamic> expected = step['expected'] as Map<String, dynamic>;
          if (expected['changed'] != true) {
            // Un-pushed steps keep the previously bound radii; the bound
            // values do not correspond to this step's input.
            continue;
          }
          final Map<String, dynamic> input = step['input'] as Map<String, dynamic>;
          final double height =
              (input['bottom'] as num).toDouble() - (input['top'] as num).toDouble();
          final GlassRadii raw = GlassRadii(
            topLeft: (input['radiusLeftTop'] as num).toDouble(),
            topRight: (input['radiusRightTop'] as num).toDouble(),
            bottomRight: (input['radiusRightBottom'] as num).toDouble(),
            bottomLeft: (input['radiusLeftBottom'] as num).toDouble(),
          );
          final List<double> quad = raw.rescaleVerticalPairs(height).shaderQuad;
          final List<num> uniforms = (expected['uniforms'] as List<dynamic>).cast<num>();
          final String reason = '$name step $i';
          expect(
            quad[0],
            closeTo(uniforms[kUniformRadiusRightBottom].toDouble(), 1e-6),
            reason: '$reason (RB)',
          );
          expect(
            quad[1],
            closeTo(uniforms[kUniformRadiusRightTop].toDouble(), 1e-6),
            reason: '$reason (RT)',
          );
          expect(
            quad[2],
            closeTo(uniforms[kUniformRadiusLeftBottom].toDouble(), 1e-6),
            reason: '$reason (LB)',
          );
          expect(
            quad[3],
            closeTo(uniforms[kUniformRadiusLeftTop].toDouble(), 1e-6),
            reason: '$reason (LT)',
          );
          checked++;
        }
      }
      // 45 cases, most single-step and all with a pushed first step.
      expect(checked, greaterThanOrEqualTo(45));
    });
  });

  group('stroke clamp bands (drawStroke, BlurredBackgroundDrawable.java:410/451)', () {
    test('top band spans top .. top + topLeftRadius*2', () {
      final GlassGeometry g = GlassGeometry(bounds: pillRect, radii: const GlassRadii.all(28));
      expect(g.strokeBandTop, const Rect.fromLTRB(0, 0, 344, 56));
    });

    test('bottom band spans bottom - bottomRightRadius*2 .. bottom', () {
      final GlassGeometry g = GlassGeometry(bounds: pillRect, radii: const GlassRadii.all(28));
      expect(g.strokeBandBottom, const Rect.fromLTRB(0, 1, 344, 57));
    });

    test('bands clamp to the rect height', () {
      final GlassGeometry g = GlassGeometry(
        bounds: const Rect.fromLTRB(0, 0, 344, 40),
        radii: const GlassRadii.all(28),
      );
      expect(g.strokeBandTop, const Rect.fromLTRB(0, 0, 344, 40));
      expect(g.strokeBandBottom, const Rect.fromLTRB(0, 0, 344, 40));
    });

    test('top band keys off topLeft, bottom band off bottomRight (Java quirk)', () {
      final GlassGeometry g = GlassGeometry(
        bounds: const Rect.fromLTRB(0, 0, 344, 200),
        radii: const GlassRadii(topLeft: 10, topRight: 40, bottomRight: 12, bottomLeft: 44),
      );
      expect(g.strokeBandTop.bottom, 20); // 10*2, not 40*2
      expect(g.strokeBandBottom.top, 200 - 24); // 12*2, not 44*2
    });

    test('zero radius yields an empty band and thus no hairline', () {
      final GlassGeometry g = GlassGeometry(bounds: pillRect);
      expect(g.strokeBandTop.isEmpty, isTrue);
      expect(g.strokeBandBottom.isEmpty, isTrue);
    });
  });

  group('stroke rings — round corners (pill 344x57, r=28, sw 1 / 2/3)', () {
    // Top ring: outer arc center (28, 28) radius 28; shifted-down copy arc
    // center (28, 29) radius 28.
    final GlassGeometry g = GlassGeometry(
      bounds: pillRect,
      radii: const GlassRadii.all(28),
      // Defaults: strokeWidthTop = 1, strokeWidthBottom = 2/3.
    );

    test('defaults are the BlurredBackgroundDrawable.java:46-53 values', () {
      expect(g.strokeWidthTop, 1.0);
      expect(g.strokeWidthBottom, closeTo(2 / 3, 1e-12));
      expect(kGlassStrokeWidthTopDp, 1.0);
      expect(kGlassStrokeWidthBottomDp, closeTo(2 / 3, 1e-12));
    });

    test('top ring contains the top edge strip', () {
      // (172, 0.5): inside the outer rrect, above the shifted copy (y < 1).
      expect(g.strokeRingTop.contains(const Offset(172, 0.5)), isTrue);
    });

    test('top ring excludes the interior (inside both rrects)', () {
      expect(g.strokeRingTop.contains(const Offset(172, 2)), isFalse);
      expect(g.strokeRingTop.contains(const Offset(172, 28)), isFalse);
      // Near the left edge below the corner arc: both rrects share x=left.
      expect(g.strokeRingTop.contains(const Offset(0.5, 28)), isFalse);
    });

    test('top ring contains the corner crescent and excludes across it', () {
      // 45-degree diagonal from the outer arc center (28, 28):
      // d=27.8 from (28,28) -> inside outer; distance from the shifted
      // center (28,29) is 28.52 -> outside the copy: in the ring.
      expect(g.strokeRingTop.contains(const Offset(8.3424, 8.3424)), isTrue);
      // d=27.0: inside both (27.72 from the shifted center): not in the ring.
      expect(g.strokeRingTop.contains(const Offset(8.9081, 8.9081)), isFalse);
      // d=28.3: outside both: not in the ring.
      expect(g.strokeRingTop.contains(const Offset(7.99, 7.99)), isFalse);
    });

    test('top ring is clipped to the drawStroke band', () {
      // (172, 57.5) lies in the raw evenOdd difference (inside only the
      // down-shifted copy, y in 57..58) but past the band bottom y=56.
      expect(g.strokeRingTop.contains(const Offset(172, 57.5)), isFalse);
    });

    test('bottom ring contains the bottom edge strip', () {
      // Strip spans y in 56.333..57 (strokeWidthBottom = 2/3).
      expect(g.strokeRingBottom.contains(const Offset(172, 56.7)), isTrue);
      expect(g.strokeRingBottom.contains(const Offset(172, 56.0)), isFalse);
    });

    test('bottom ring contains the bottom-right crescent', () {
      // Outer arc center (316, 29) r=28; up-shifted copy center (316, 28.333).
      // d=27.8 diagonal: inside outer, 28.28 from the copy center -> ring.
      expect(g.strokeRingBottom.contains(const Offset(335.6576, 48.6576)), isTrue);
      // d=26.45: inside both -> not in the ring.
      expect(g.strokeRingBottom.contains(const Offset(334.7, 47.7)), isFalse);
    });

    test('bottom ring is clipped to the drawStroke band', () {
      // (172, -0.3) is in the raw difference (inside only the up-shifted
      // copy) but above the band top y=1.
      expect(g.strokeRingBottom.contains(const Offset(172, -0.3)), isFalse);
    });
  });

  group('stroke rings — square corners', () {
    test('zero radii produce empty rings (Android draws no hairline)', () {
      final GlassGeometry g = GlassGeometry(bounds: pillRect);
      expect(g.strokeRingTop.getBounds().isEmpty, isTrue);
      expect(g.strokeRingBottom.getBounds().isEmpty, isTrue);
      expect(g.strokeRingTop.contains(const Offset(172, 0.5)), isFalse);
      expect(g.strokeRingBottom.contains(const Offset(172, 56.7)), isFalse);
    });

    test('zero stroke width produces an empty ring', () {
      final GlassGeometry g = GlassGeometry(
        bounds: pillRect,
        radii: const GlassRadii.all(28),
        strokeWidthTop: 0,
      );
      expect(g.strokeRingTop.getBounds().isEmpty, isTrue);
      // The bottom ring keeps its default width and stays present.
      expect(g.strokeRingBottom.contains(const Offset(172, 56.7)), isTrue);
    });
  });

  group('stroke rings — uniform min(w,h)/2 cap (Props.build tmpRadii)', () {
    // 344x40 with uniform r=28 > radiusMax=20: the ring round-rects are
    // rebuilt with r=20, so the top-left arc center moves to (20, 20).
    final GlassGeometry g = GlassGeometry(
      bounds: const Rect.fromLTRB(0, 0, 344, 40),
      radii: const GlassRadii.all(28),
    );

    test('radiusMax is min(w,h)/2', () {
      expect(g.radiusMax, 20);
    });

    test('crescent sits on the capped 20 px arc', () {
      // d=19.9 from (20,20): inside outer; 20.62 from the shifted center
      // (20,21): outside the copy -> in the ring.
      expect(g.strokeRingTop.contains(const Offset(5.9285, 5.9285)), isTrue);
      // The uncapped 28 px arc location is interior to both capped rrects.
      expect(g.strokeRingTop.contains(const Offset(8.3424, 8.3424)), isFalse);
    });
  });

  group('forceBottomZero dual radii (BlurredBackgroundDrawable.java:119-131)', () {
    final GlassGeometry g = GlassGeometry(
      bounds: pillRect,
      radii: const GlassRadii.all(28),
      forceBottomZero: true,
    );

    test('clip radii lose the bottom corners, shader radii keep them', () {
      expect(
        g.clipRadii,
        const GlassRadii(topLeft: 28, topRight: 28, bottomRight: 0, bottomLeft: 0),
      );
      expect(g.shaderRadii, const GlassRadii.all(28));
    });

    test('shader quad still carries the rounded bottom corners', () {
      expect(g.shaderRadiusQuad, <double>[28, 28, 28, 28]);
    });

    test('outer rrect goes square at the bottom', () {
      expect(g.outerRRect.brRadius, Radius.zero);
      expect(g.outerRRect.blRadius, Radius.zero);
      expect(g.outerRRect.tlRadius, const Radius.circular(28));
    });

    test('bottom band and ring vanish, top ring survives', () {
      expect(g.strokeBandBottom.isEmpty, isTrue);
      expect(g.strokeRingBottom.getBounds().isEmpty, isTrue);
      expect(g.strokeRingTop.contains(const Offset(172, 0.5)), isTrue);
    });

    test('without forceBottomZero both radii sets are identical', () {
      final GlassGeometry plain = GlassGeometry(bounds: pillRect, radii: const GlassRadii.all(28));
      expect(plain.clipRadii, plain.shaderRadii);
    });
  });

  group('shadow (BlurredBackgroundDrawable.java:46-53)', () {
    test('defaults: radius 1dp, dx 0, dy 1/3dp', () {
      final GlassGeometry g = GlassGeometry(bounds: pillRect);
      expect(g.shadowRadius, kGlassShadowRadiusDp);
      expect(g.shadowDx, 0);
      expect(g.shadowDy, closeTo(1 / 3, 1e-12));
    });

    test('shadowSigma is radiusToSigma(radius)', () {
      final GlassGeometry g = GlassGeometry(bounds: pillRect);
      expect(g.shadowSigma, closeTo(0.57735 * 1 + 0.5, 1e-12));
      expect(g.shadowSigma, radiusToSigma(g.shadowRadius));
    });

    test('shadowPath is outerPath shifted by (dx, dy)', () {
      final GlassGeometry g = GlassGeometry(
        bounds: pillRect,
        radii: const GlassRadii.all(28),
        shadowDx: 2,
        shadowDy: 3,
      );
      final Rect outer = g.outerPath.getBounds();
      final Rect shadow = g.shadowPath.getBounds();
      expect(shadow.left, closeTo(outer.left + 2, 1e-9));
      expect(shadow.top, closeTo(outer.top + 3, 1e-9));
      expect(shadow.right, closeTo(outer.right + 2, 1e-9));
      expect(shadow.bottom, closeTo(outer.bottom + 3, 1e-9));
    });

    test('mask filter is null only for a zero blur radius', () {
      expect(GlassGeometry(bounds: pillRect).shadowMaskFilter, isNotNull);
      expect(GlassGeometry(bounds: pillRect, shadowRadius: 0).shadowMaskFilter, isNull);
    });
  });

  group('padding and outer geometry (Props.build:241-251)', () {
    test('boundsWithPadding insets all sides', () {
      final GlassGeometry g = GlassGeometry(
        bounds: const Rect.fromLTRB(0, 0, 344, 72),
        radii: const GlassRadii.all(28),
        padding: 7.666,
      );
      expect(g.boundsWithPadding, const Rect.fromLTRB(7.666, 7.666, 344 - 7.666, 72 - 7.666));
      expect(g.outerRRect.outerRect, g.boundsWithPadding);
      // Bands follow the padded rect.
      expect(g.strokeBandTop.top, 7.666);
      expect(g.strokeBandTop.left, 7.666);
    });

    test('empty padded bounds produce empty rings without throwing', () {
      final GlassGeometry g = GlassGeometry(
        bounds: const Rect.fromLTRB(0, 0, 10, 10),
        radii: const GlassRadii.all(4),
        padding: 6,
      );
      expect(g.boundsWithPadding.isEmpty, isTrue);
      expect(g.strokeRingTop.getBounds().isEmpty, isTrue);
      expect(g.strokeRingBottom.getBounds().isEmpty, isTrue);
    });
  });

  group('outlinePath (getOutline, BlurredBackgroundDrawable.java:338-356)', () {
    test('uniform radii are capped to min(w,h)/2', () {
      final GlassGeometry g = GlassGeometry(
        bounds: const Rect.fromLTRB(0, 0, 344, 40),
        radii: const GlassRadii.all(28),
      );
      final Path outline = g.outlinePath;
      expect(outline.getBounds(), const Rect.fromLTRB(0, 0, 344, 40));
      expect(outline.contains(const Offset(172, 20)), isTrue);
      // (0.5, 0.5) is 27.58 px from the capped 20 px arc center (20, 20).
      expect(outline.contains(const Offset(0.5, 0.5)), isFalse);
    });

    test('non-uniform radii pass through raw', () {
      final GlassGeometry g = GlassGeometry(
        bounds: pillRect,
        radii: const GlassRadii(topLeft: 28, topRight: 0, bottomRight: 28, bottomLeft: 0),
      );
      final Path outline = g.outlinePath;
      // Square top-right corner is inside; round top-left corner is not.
      expect(outline.contains(const Offset(343.5, 0.5)), isTrue);
      expect(outline.contains(const Offset(0.5, 0.5)), isFalse);
    });
  });

  group('value semantics', () {
    test('equal inputs compare equal', () {
      final GlassGeometry a = GlassGeometry(
        bounds: pillRect,
        radii: const GlassRadii.all(28),
        forceBottomZero: true,
      );
      final GlassGeometry b = GlassGeometry(
        bounds: pillRect,
        radii: const GlassRadii.all(28),
        forceBottomZero: true,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing inputs compare unequal', () {
      final GlassGeometry a = GlassGeometry(bounds: pillRect, radii: const GlassRadii.all(28));
      expect(a, isNot(GlassGeometry(bounds: pillRect, radii: const GlassRadii.all(27))));
      expect(
        a,
        isNot(GlassGeometry(bounds: pillRect, radii: const GlassRadii.all(28), padding: 1)),
      );
      // forceBottomZero changes only the clip radii set.
      expect(
        a,
        isNot(
          GlassGeometry(bounds: pillRect, radii: const GlassRadii.all(28), forceBottomZero: true),
        ),
      );
    });
  });
}
