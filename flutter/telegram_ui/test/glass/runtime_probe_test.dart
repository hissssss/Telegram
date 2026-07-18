// Ring-1 tests for lib/src/glass/runtime_probe.dart (ARCHITECTURE.md
// section 3.5): the flutter_tester capability path — the CPU backend does
// not support `ui.ImageFilter.shader`, so the probe must resolve non-liquid
// with a reason and never crash under `flutter test` — plus GlassSettings
// tier resolution (probe downgrade, kill-switch forcing, late-completion
// notifications), the ports of Android's API-33 RuntimeShader gate and
// LiteMode switch (BlurredBackgroundDrawableViewFactory.java:57-86).

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/glass/liquid_glass_shader.dart';
import 'package:telegram_ui/src/glass/runtime_probe.dart';
import 'package:telegram_ui/src/glass/strategy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GlassCapability', () {
    test('named constructors, ==, hashCode, toString', () {
      const GlassCapability supported = GlassCapability.supported();
      expect(supported.liquidSupported, isTrue);
      expect(supported.reason, isNull);
      expect(supported, const GlassCapability(liquidSupported: true));
      expect(supported.hashCode, const GlassCapability(liquidSupported: true).hashCode);
      expect(supported.toString(), contains('supported'));

      const GlassCapability unsupported = GlassCapability.unsupported('no gpu');
      expect(unsupported.liquidSupported, isFalse);
      expect(unsupported.reason, 'no gpu');
      expect(unsupported, isNot(const GlassCapability.unsupported('other reason')));
      expect(unsupported.toString(), contains('no gpu'));
    });

    test('asserts on a reason/support mismatch', () {
      expect(
        () => GlassCapability(liquidSupported: true, reason: 'but why'),
        throwsAssertionError,
      );
      expect(() => GlassCapability(liquidSupported: false), throwsAssertionError);
    });
  });

  group('GlassRuntimeProbe under flutter_tester', () {
    test('CPU backend gate: resolves non-liquid with a reason, does not crash', () async {
      // The architecture-mandated assertion (section 3.5): flutter_tester
      // renders on a CPU backend where the shader image filter is
      // unavailable, so this is the deterministic downgrade path CI runs.
      expect(ui.ImageFilter.isShaderFilterSupported, isFalse);

      final GlassCapability capability = await GlassRuntimeProbe.run();
      expect(capability.liquidSupported, isFalse);
      expect(capability.reason, isNotNull);
      expect(capability.reason, contains('backend'));
    });

    test('the backend gate short-circuits before any shader load', () async {
      TgShaders.debugReset();
      await GlassRuntimeProbe.run();
      expect(TgShaders.isInitialized, isFalse);
    });

    test('bypassing the gate exercises shader load + 4x4 offscreen render', () async {
      TgShaders.debugReset();
      GlassRuntimeProbe.debugBypassBackendGate = true;
      addTearDown(() => GlassRuntimeProbe.debugBypassBackendGate = false);

      // Contract under test: run() never throws, warmup really loaded the
      // fragment program, and the probe scene renders end-to-end — including
      // the u_backdrop sampler binding, without which every backend throws
      // "missing sampler". flutter_tester's software canvas CAN execute
      // runtime effects; only the *filter* API gate (phase 1) is closed.
      final GlassCapability capability = await GlassRuntimeProbe.run();
      expect(TgShaders.isInitialized, isTrue);
      expect(capability, const GlassCapability.supported());
    });
  });

  group('GlassSettings.resolvedTier', () {
    test('unprobed: liquid conservatively downgrades one rung to frosted', () {
      final GlassSettings settings = GlassSettings();
      expect(settings.probed, isFalse);
      expect(settings.capability, isNull);
      expect(settings.resolvedTier(GlassTier.liquid), GlassTier.frosted);
      expect(settings.resolvedTier(GlassTier.frosted), GlassTier.frosted);
      expect(settings.resolvedTier(GlassTier.flat), GlassTier.flat);
    });

    test('unsupported capability keeps the liquid -> frosted downgrade', () {
      final GlassSettings settings = GlassSettings()
        ..applyCapability(const GlassCapability.unsupported('no gpu'));
      expect(settings.resolvedTier(GlassTier.liquid), GlassTier.frosted);
      expect(settings.resolvedTier(GlassTier.frosted), GlassTier.frosted);
      expect(settings.resolvedTier(GlassTier.flat), GlassTier.flat);
    });

    test('supported capability lets liquid through untouched', () {
      final GlassSettings settings = GlassSettings()
        ..applyCapability(const GlassCapability.supported());
      expect(settings.resolvedTier(GlassTier.liquid), GlassTier.liquid);
      expect(settings.resolvedTier(GlassTier.frosted), GlassTier.frosted);
      expect(settings.resolvedTier(GlassTier.flat), GlassTier.flat);
    });

    test('kill-switch forces any tier for every request, in both directions', () {
      final GlassSettings settings = GlassSettings()
        ..applyCapability(const GlassCapability.unsupported('no gpu'));

      // Downward: flat wins over everything.
      settings.forcedTier = GlassTier.flat;
      expect(settings.resolvedTier(GlassTier.liquid), GlassTier.flat);
      expect(settings.resolvedTier(GlassTier.frosted), GlassTier.flat);

      // Upward: liquid forced even though the probe said unsupported.
      settings.forcedTier = GlassTier.liquid;
      expect(settings.resolvedTier(GlassTier.liquid), GlassTier.liquid);
      expect(settings.resolvedTier(GlassTier.flat), GlassTier.liquid);

      // Clearing restores probe-driven resolution.
      settings.forcedTier = null;
      expect(settings.resolvedTier(GlassTier.liquid), GlassTier.frosted);
    });
  });

  group('GlassSettings probing and notifications', () {
    test('ensureProbed shares one run, caches the verdict, notifies once', () async {
      int probeRuns = 0;
      final GlassSettings settings = GlassSettings(
        probe: () async {
          probeRuns++;
          return const GlassCapability.supported();
        },
      );
      int notifications = 0;
      settings.addListener(() => notifications++);

      final List<GlassCapability> results = await Future.wait(<Future<GlassCapability>>[
        settings.ensureProbed(),
        settings.ensureProbed(),
      ]);
      expect(probeRuns, 1);
      expect(results, everyElement(const GlassCapability.supported()));
      expect(settings.probed, isTrue);
      expect(notifications, 1);

      // Already probed: immediate, no re-run, no re-notify.
      expect(await settings.ensureProbed(), const GlassCapability.supported());
      expect(probeRuns, 1);
      expect(notifications, 1);
    });

    test('a throwing probe folds into an unsupported capability', () async {
      final GlassSettings settings = GlassSettings(
        probe: () async => throw StateError('boom'),
      );
      final GlassCapability capability = await settings.ensureProbed();
      expect(capability.liquidSupported, isFalse);
      expect(capability.reason, contains('boom'));
      expect(settings.resolvedTier(GlassTier.liquid), GlassTier.frosted);
    });

    test('applyCapability notifies only on change; kill-switch likewise', () {
      final GlassSettings settings = GlassSettings();
      int notifications = 0;
      settings.addListener(() => notifications++);

      settings.applyCapability(const GlassCapability.unsupported('no gpu'));
      expect(notifications, 1);
      settings.applyCapability(const GlassCapability.unsupported('no gpu'));
      expect(notifications, 1); // Equal verdict: no notification.
      settings.applyCapability(const GlassCapability.supported());
      expect(notifications, 2);

      settings.forcedTier = GlassTier.flat;
      expect(notifications, 3);
      settings.forcedTier = GlassTier.flat;
      expect(notifications, 3); // Same value: no notification.
    });

    test('the shared instance runs the real probe: frosted under flutter_tester', () async {
      GlassSettings.instance.debugReset();
      addTearDown(GlassSettings.instance.debugReset);

      final GlassCapability capability = await GlassSettings.instance.ensureProbed();
      expect(capability.liquidSupported, isFalse);
      expect(capability.reason, contains('backend'));
      expect(GlassSettings.instance.resolvedTier(GlassTier.liquid), GlassTier.frosted);
    });

    test('debugReset clears verdict and kill-switch and notifies', () {
      final GlassSettings settings = GlassSettings()
        ..applyCapability(const GlassCapability.supported())
        ..forcedTier = GlassTier.flat;
      int notifications = 0;
      settings.addListener(() => notifications++);

      settings.debugReset();
      expect(notifications, 1);
      expect(settings.probed, isFalse);
      expect(settings.forcedTier, isNull);
      expect(settings.resolvedTier(GlassTier.liquid), GlassTier.frosted);
    });
  });
}
