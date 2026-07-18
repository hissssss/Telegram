// Ring-1 tests for lib/src/glass/liquid_glass_shader.dart (TgShaders +
// LiquidGlassUniforms) and lib/src/glass/liquid_glass_settings.dart.
//
// The packer is driven against the Ring-0 fixture tables of
// flutter/tool/fixtures/uniform_fixtures.json — the Python
// re-implementation of LiquidGlassEffect.update (gen_uniform_fixtures.py):
// 45 cases / 63 update steps covering the radius-pair rescale, the 0.1f
// dirty-check epsilon (including no-op steps), the thickness clamp, and the
// color premultiply. Every step asserts the full currently-bound 17-float
// array, the push verdict, and the setFloat call accounting.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/glass/geometry.dart';
import 'package:telegram_ui/src/glass/liquid_glass_settings.dart';
import 'package:telegram_ui/src/glass/liquid_glass_shader.dart';
import 'package:telegram_ui/src/glass/strategy.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.FragmentProgram program;

  setUpAll(() async {
    program = await TgShaders.ensureInitialized();
  });

  group('TgShaders', () {
    test('ensureInitialized caches and liquidGlassProgram is synchronous', () async {
      expect(TgShaders.isInitialized, isTrue);
      expect(TgShaders.liquidGlassProgram, same(await TgShaders.ensureInitialized()));
    });

    test('liquidGlassProgram throws StateError before initialization', () async {
      TgShaders.debugReset();
      expect(TgShaders.isInitialized, isFalse);
      expect(() => TgShaders.liquidGlassProgram, throwsStateError);
      // Re-initialize (exercises the dual asset-key load a second time).
      final ui.FragmentProgram reloaded = await TgShaders.ensureInitialized();
      expect(TgShaders.isInitialized, isTrue);
      expect(TgShaders.liquidGlassProgram, same(reloaded));
    });

    test('a fresh shader accepts exactly the generated float slot range', () {
      final ui.FragmentShader shader = program.fragmentShader();
      for (int i = 0; i < kLiquidGlassUniformFloatCount; i++) {
        shader.setFloat(i, 0);
      }
      expect(() => shader.setFloat(kLiquidGlassUniformFloatCount, 0), throwsRangeError);
      shader.dispose();
    });
  });

  group('LiquidGlassUniforms vs Ring-0 fixtures', () {
    test('reproduces every expected float array (45 cases, 63 steps)', () {
      final Map<String, dynamic> doc =
          jsonDecode(_uniformFixtures().readAsStringSync()) as Map<String, dynamic>;

      // The fixture layout and the generated bindings share one authority.
      expect(doc['floatCount'], kLiquidGlassUniformFloatCount);
      expect((doc['epsilon'] as num).toDouble(), kUniformDirtyEpsilon);
      expect((doc['uniformOrder'] as List<dynamic>).length, kLiquidGlassUniformFloatCount);

      final List<dynamic> cases = doc['cases'] as List<dynamic>;
      expect(cases.length, doc['caseCount']);
      expect(cases.length, 45);

      int totalSteps = 0;
      for (final dynamic c in cases) {
        final Map<String, dynamic> caseMap = c as Map<String, dynamic>;
        final String name = caseMap['name'] as String;
        final List<dynamic> steps = caseMap['steps'] as List<dynamic>;

        // Fresh packer per case: fields start all-zero exactly like a new
        // LiquidGlassEffect.
        final LiquidGlassUniforms packer = LiquidGlassUniforms.fromProgram(program);
        int expectedWrites = 0;

        for (int i = 0; i < steps.length; i++) {
          final Map<String, dynamic> step = steps[i] as Map<String, dynamic>;
          final Map<String, dynamic> input = step['input'] as Map<String, dynamic>;
          final Map<String, dynamic> expected = step['expected'] as Map<String, dynamic>;
          final String reason = '$name step $i';

          double readD(String key) => (input[key] as num).toDouble();
          final double width = readD('right') - readD('left');
          final double height = readD('bottom') - readD('top');

          packer.update(
            coverageSize: ui.Size(width, height),
            panelRect: ui.Rect.fromLTRB(
              readD('left'),
              readD('top'),
              readD('right'),
              readD('bottom'),
            ),
            radii: GlassRadii(
              topLeft: readD('radiusLeftTop'),
              topRight: readD('radiusRightTop'),
              bottomRight: readD('radiusRightBottom'),
              bottomLeft: readD('radiusLeftBottom'),
            ),
            tint: ui.Color((input['colorArgb'] as num).toInt()),
            thickness: readD('liquidThickness'),
            intensity: readD('intensity'),
            index: readD('refractIndex'),
            devicePixelRatio: readD('density'),
          );

          final bool changed = expected['changed'] as bool;
          expect(packer.dirty, changed, reason: '$reason (changed)');
          expect(
            packer.resolvedThickness,
            (expected['thicknessPx'] as num).toDouble(),
            reason: '$reason (thickness clamp)',
          );

          // A push re-writes every slot; a clean update writes nothing.
          expectedWrites += changed ? kLiquidGlassUniformFloatCount : 0;
          expect(packer.uniformWrites, expectedWrites, reason: '$reason (setFloat count)');

          final List<double> bound = packer.boundUniforms;
          final List<num> uniforms = (expected['uniforms'] as List<dynamic>).cast<num>();
          expect(uniforms.length, kLiquidGlassUniformFloatCount, reason: reason);
          for (int slot = 0; slot < uniforms.length; slot++) {
            expect(
              bound[slot],
              closeTo(uniforms[slot].toDouble(), 1e-6),
              reason: '$reason (slot $slot)',
            );
          }
          totalSteps++;
        }
        packer.dispose();
      }
      expect(totalSteps, 63);
    });
  });

  group('engineSetsSize', () {
    test('true skips the two u_size slots but keeps them in the dirty check', () {
      final LiquidGlassUniforms packer = LiquidGlassUniforms.fromProgram(program);
      addTearDown(packer.dispose);

      packer.update(
        coverageSize: const ui.Size(344, 57),
        panelRect: const ui.Rect.fromLTRB(0, 0, 344, 57),
        radii: const GlassRadii.all(28),
        tint: const ui.Color(0xD9FFFFFF),
        engineSetsSize: true,
      );
      expect(packer.dirty, isTrue);
      // 17 slots minus u_size[0] and u_size[1].
      expect(packer.uniformWrites, kLiquidGlassUniformFloatCount - 2);
      // The mirror still tracks the coverage size for the dirty check.
      expect(packer.boundUniforms[kUniformSizeX], 344);
      expect(packer.boundUniforms[kUniformSizeY], 57);

      // A coverage-only resize must still re-push (Java compares resolution).
      packer.update(
        coverageSize: const ui.Size(600, 57),
        panelRect: const ui.Rect.fromLTRB(0, 0, 344, 57),
        radii: const GlassRadii.all(28),
        tint: const ui.Color(0xD9FFFFFF),
        engineSetsSize: true,
      );
      expect(packer.dirty, isTrue);
      expect(packer.uniformWrites, 2 * (kLiquidGlassUniformFloatCount - 2));
      expect(packer.boundUniforms[kUniformSizeX], 600);

      // And an identical update writes nothing at all.
      packer.update(
        coverageSize: const ui.Size(600, 57),
        panelRect: const ui.Rect.fromLTRB(0, 0, 344, 57),
        radii: const GlassRadii.all(28),
        tint: const ui.Color(0xD9FFFFFF),
        engineSetsSize: true,
      );
      expect(packer.dirty, isFalse);
      expect(packer.uniformWrites, 2 * (kLiquidGlassUniformFloatCount - 2));
    });

    test('false writes all 17 slots', () {
      final LiquidGlassUniforms packer = LiquidGlassUniforms.fromProgram(program);
      addTearDown(packer.dispose);
      packer.update(
        coverageSize: const ui.Size(344, 57),
        panelRect: const ui.Rect.fromLTRB(0, 0, 344, 57),
        radii: const GlassRadii.all(28),
        tint: const ui.Color(0xD9FFFFFF),
      );
      expect(packer.uniformWrites, kLiquidGlassUniformFloatCount);
    });
  });

  group('LiquidGlassSettings', () {
    test('defaults are the Android production values', () {
      const LiquidGlassSettings settings = LiquidGlassSettings();
      expect(settings.thickness, kGlassThicknessDefaultDp);
      expect(settings.refractIntensity, kGlassRefractIntensityDefault);
      expect(settings.refractIndex, kGlassRefractIndex);
      expect(settings.tintColor, const ui.Color(0x00000000));
      expect(settings.radii, GlassRadii.zero);
    });

    test('copyWith replaces only the given fields', () {
      const LiquidGlassSettings base = LiquidGlassSettings();
      final LiquidGlassSettings keyboard = base.copyWith(thickness: 32, refractIntensity: 0.4);
      expect(keyboard.thickness, 32);
      expect(keyboard.refractIntensity, 0.4);
      expect(keyboard.refractIndex, base.refractIndex);
      expect(keyboard.tintColor, base.tintColor);
      expect(keyboard.radii, base.radii);
      expect(base.copyWith(), base);
    });

    test('== and hashCode are value-based', () {
      const LiquidGlassSettings a = LiquidGlassSettings(
        tintColor: ui.Color(0xD9FFFFFF),
        radii: GlassRadii.all(28),
      );
      const LiquidGlassSettings b = LiquidGlassSettings(
        tintColor: ui.Color(0xD9FFFFFF),
        radii: GlassRadii.all(28),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(a.copyWith(thickness: 4)));
    });

    test('lerp interpolates every field and short-circuits at the ends', () {
      const LiquidGlassSettings a = LiquidGlassSettings(
        tintColor: ui.Color(0xFF000000),
        radii: GlassRadii.all(0),
      );
      const LiquidGlassSettings b = LiquidGlassSettings(
        thickness: 32,
        refractIntensity: 0.4,
        refractIndex: 1.5,
        tintColor: ui.Color(0xFFFFFFFF),
        radii: GlassRadii.all(28),
      );
      expect(LiquidGlassSettings.lerp(a, b, 0), same(a));
      expect(LiquidGlassSettings.lerp(a, b, 1), same(b));

      final LiquidGlassSettings mid = LiquidGlassSettings.lerp(a, b, 0.5);
      expect(mid.thickness, closeTo((kGlassThicknessDefaultDp + 32) / 2, 1e-12));
      expect(mid.refractIntensity, closeTo((kGlassRefractIntensityDefault + 0.4) / 2, 1e-12));
      expect(mid.refractIndex, kGlassRefractIndex);
      expect(mid.radii.topLeft, 14);
      expect(mid.radii.bottomRight, 14);
    });
  });

  group('strategy enums', () {
    test('tiers mirror DRAW_GLASS / DRAW_FROSTED_GLASS / LiteMode-off', () {
      expect(GlassTier.values, <GlassTier>[GlassTier.liquid, GlassTier.frosted, GlassTier.flat]);
      expect(GlassStrategy.values, <GlassStrategy>[
        GlassStrategy.backdropShader,
        GlassStrategy.snapshotCache,
        GlassStrategy.tintOnly,
      ]);
    });
  });
}
