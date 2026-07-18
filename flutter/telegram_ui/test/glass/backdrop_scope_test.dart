// Ring-1/Ring-2 tests for lib/src/glass/backdrop_scope.dart
// (ARCHITECTURE.md sections 3.2 and 3.5): scope lookup, tier/strategy
// override propagation through nested scopes, late-probe upgrade and
// kill-switch rebuilds via the GlassSettings listener, BackdropKey
// stability, and the layer-hygiene foundation — a widget test walking the
// layer tree counting BackdropFilterLayers (2 grouped panels -> 2 layers
// sharing ONE BackdropKey in Strategy 1; zero backdrop layers in
// snapshot/flat modes).

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show BackdropFilterLayer, BackdropKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/glass/backdrop_scope.dart';
import 'package:telegram_ui/src/glass/runtime_probe.dart';
import 'package:telegram_ui/src/glass/strategy.dart';

/// Records the [GlassScopeData] seen on every build.
class _ScopeReader extends StatelessWidget {
  const _ScopeReader({required this.log});

  final List<GlassScopeData> log;

  @override
  Widget build(BuildContext context) {
    log.add(GlassBackdropScope.of(context));
    return const SizedBox.shrink();
  }
}

/// A minimal stand-in for GlassPanel's layer behavior: mounts a grouped
/// backdrop blur when the scope wants a backdrop layer, otherwise a plain
/// box (the snapshot/tint path mounts zero backdrop layers).
class _FakeGlassPanel extends StatelessWidget {
  const _FakeGlassPanel();

  @override
  Widget build(BuildContext context) {
    final GlassScopeData data = GlassBackdropScope.of(context);
    const Widget body = SizedBox(width: 40, height: 40);
    if (!data.wantsBackdropLayer) {
      return body;
    }
    return ClipRect(
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: body,
      ),
    );
  }
}

Widget _boilerplate(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

/// Settings whose probe never runs on its own (mount-probe disabled per
/// test) or resolves only when the test says so.
GlassSettings _manualSettings() =>
    GlassSettings(probe: () => Completer<GlassCapability>().future);

void main() {
  group('GlassScopeData', () {
    test('resolve applies settings and forces tintOnly at the flat floor', () {
      final GlassSettings settings = GlassSettings();

      final GlassScopeData unprobed = GlassScopeData.resolve(settings: settings);
      expect(unprobed.requestedTier, GlassTier.liquid);
      expect(unprobed.tier, GlassTier.frosted); // Conservative pre-probe downgrade.
      expect(unprobed.requestedStrategy, GlassStrategy.backdropShader);
      expect(unprobed.strategy, GlassStrategy.backdropShader);
      expect(unprobed.wantsBackdropLayer, isTrue);

      settings.forcedTier = GlassTier.flat;
      final GlassScopeData flat = GlassScopeData.resolve(settings: settings);
      expect(flat.tier, GlassTier.flat);
      expect(flat.requestedStrategy, GlassStrategy.backdropShader);
      expect(flat.strategy, GlassStrategy.tintOnly); // Flat never pays for a backdrop.
      expect(flat.wantsBackdropLayer, isFalse);
    });

    test('==, hashCode, toString', () {
      final GlassSettings settings = GlassSettings()
        ..applyCapability(const GlassCapability.supported());
      final GlassScopeData a = GlassScopeData.resolve(settings: settings);
      final GlassScopeData b = GlassScopeData.resolve(settings: settings);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(GlassScopeData.resolve(requestedTier: GlassTier.flat, settings: settings)));
      expect(a.toString(), contains('liquid'));

      final GlassScopeData snapshot = GlassScopeData.resolve(
        requestedStrategy: GlassStrategy.snapshotCache,
        settings: settings,
      );
      expect(snapshot.wantsBackdropLayer, isFalse);
    });
  });

  group('scope lookup', () {
    testWidgets('maybeOf is null and of throws without a scope', (WidgetTester tester) async {
      GlassScopeData? maybe;
      Object? ofError;
      await tester.pumpWidget(
        _boilerplate(
          Builder(
            builder: (BuildContext context) {
              maybe = GlassBackdropScope.maybeOf(context);
              try {
                GlassBackdropScope.of(context);
              } on FlutterError catch (error) {
                ofError = error;
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(maybe, isNull);
      expect(ofError, isA<FlutterError>());
      expect('$ofError', contains('GlassBackdropScope.of()'));
    });

    testWidgets('resolve falls back to defaults without a scope', (WidgetTester tester) async {
      GlassSettings.instance.debugReset();
      addTearDown(GlassSettings.instance.debugReset);
      late GlassScopeData data;
      await tester.pumpWidget(
        _boilerplate(
          Builder(
            builder: (BuildContext context) {
              data = GlassBackdropScope.resolve(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(data.requestedTier, GlassTier.liquid);
      expect(data.tier, GlassTier.frosted); // Unprobed instance downgrades.
    });

    testWidgets('of finds the scope and mounts a BackdropGroup', (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final List<GlassScopeData> log = <GlassScopeData>[];
      BackdropKey? groupKey;
      await tester.pumpWidget(
        _boilerplate(
          GlassBackdropScope(
            settings: settings,
            probeOnMount: false,
            child: Builder(
              builder: (BuildContext context) {
                groupKey = BackdropGroup.of(context)?.backdropKey;
                return _ScopeReader(log: log);
              },
            ),
          ),
        ),
      );
      expect(log, hasLength(1));
      expect(log.single.requestedTier, GlassTier.liquid);
      expect(log.single.tier, GlassTier.frosted); // Unprobed settings.
      expect(log.single.strategy, GlassStrategy.backdropShader);
      expect(groupKey, isNotNull);
    });

    testWidgets('the BackdropKey stays stable across scope rebuilds', (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final List<BackdropKey> keys = <BackdropKey>[];
      Widget build(GlassTier? tier) => _boilerplate(
            GlassBackdropScope(
              settings: settings,
              probeOnMount: false,
              tier: tier,
              child: Builder(
                builder: (BuildContext context) {
                  keys.add(BackdropGroup.of(context)!.backdropKey);
                  return const SizedBox.shrink();
                },
              ),
            ),
          );

      await tester.pumpWidget(build(null));
      await tester.pumpWidget(build(GlassTier.frosted)); // New widget config, same State.
      expect(keys, hasLength(2));
      expect(keys[0], same(keys[1]));
    });
  });

  group('tier and strategy propagation', () {
    testWidgets('overrides propagate; nested scopes inherit REQUESTED values',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final List<GlassScopeData> outerLog = <GlassScopeData>[];
      final List<GlassScopeData> inheritedLog = <GlassScopeData>[];
      final List<GlassScopeData> overriddenLog = <GlassScopeData>[];
      await tester.pumpWidget(
        _boilerplate(
          GlassBackdropScope(
            settings: settings,
            probeOnMount: false,
            tier: GlassTier.flat,
            child: Column(
              children: <Widget>[
                _ScopeReader(log: outerLog),
                GlassBackdropScope(
                  settings: settings,
                  probeOnMount: false,
                  child: _ScopeReader(log: inheritedLog),
                ),
                GlassBackdropScope(
                  settings: settings,
                  probeOnMount: false,
                  tier: GlassTier.frosted,
                  strategy: GlassStrategy.snapshotCache,
                  child: _ScopeReader(log: overriddenLog),
                ),
              ],
            ),
          ),
        ),
      );

      // Outer: flat forces tintOnly.
      expect(outerLog.single.tier, GlassTier.flat);
      expect(outerLog.single.strategy, GlassStrategy.tintOnly);

      // Nested with nulls: inherits the requested flat tier and the requested
      // (NOT the flat-downgraded) strategy, then re-resolves.
      expect(inheritedLog.single.requestedTier, GlassTier.flat);
      expect(inheritedLog.single.tier, GlassTier.flat);
      expect(inheritedLog.single.requestedStrategy, GlassStrategy.backdropShader);
      expect(inheritedLog.single.strategy, GlassStrategy.tintOnly);

      // Nested with overrides: replaces both.
      expect(overriddenLog.single.tier, GlassTier.frosted);
      expect(overriddenLog.single.strategy, GlassStrategy.snapshotCache);
      expect(overriddenLog.single.wantsBackdropLayer, isFalse);
    });

    testWidgets('late probe completion upgrades a liquid subtree in place',
        (WidgetTester tester) async {
      final Completer<GlassCapability> probe = Completer<GlassCapability>();
      final GlassSettings settings = GlassSettings(probe: () => probe.future);
      final List<GlassScopeData> log = <GlassScopeData>[];
      await tester.pumpWidget(
        _boilerplate(
          GlassBackdropScope(
            settings: settings,
            child: _ScopeReader(log: log), // probeOnMount default kicks ensureProbed.
          ),
        ),
      );
      expect(log, hasLength(1));
      expect(log.last.tier, GlassTier.frosted); // Conservative while probing.

      probe.complete(const GlassCapability.supported());
      await tester.pumpAndSettle();
      expect(log, hasLength(2)); // Exactly one settings-driven rebuild.
      expect(log.last.tier, GlassTier.liquid);
      expect(log.last.strategy, GlassStrategy.backdropShader);
    });

    testWidgets('kill-switch flips rebuild the subtree', (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      final List<GlassScopeData> log = <GlassScopeData>[];
      await tester.pumpWidget(
        _boilerplate(
          GlassBackdropScope(
            settings: settings,
            probeOnMount: false,
            child: _ScopeReader(log: log),
          ),
        ),
      );
      expect(log.last.tier, GlassTier.frosted);

      settings.forcedTier = GlassTier.flat;
      await tester.pump();
      expect(log.last.tier, GlassTier.flat);
      expect(log.last.strategy, GlassStrategy.tintOnly);

      settings.forcedTier = GlassTier.liquid; // Forced past the missing probe.
      await tester.pump();
      expect(log.last.tier, GlassTier.liquid);
    });
  });

  group('settings swap (didUpdateWidget)', () {
    testWidgets(
        'swapping settings migrates the listener: the old instance no longer '
        'rebuilds (or crashes after dispose), the new one does',
        (WidgetTester tester) async {
      final GlassSettings a = _manualSettings();
      final GlassSettings b = _manualSettings();
      final List<GlassScopeData> log = <GlassScopeData>[];
      Widget scope(GlassSettings settings) => _boilerplate(GlassBackdropScope(
            settings: settings,
            probeOnMount: false,
            child: _ScopeReader(log: log),
          ));

      await tester.pumpWidget(scope(a));
      expect(log.last.tier, GlassTier.frosted); // unprobed liquid degrades

      await tester.pumpWidget(scope(b));
      final int buildsAfterSwap = log.length;

      // Notifying the OLD settings must not rebuild the scope — a
      // wrong-instance removeListener in didUpdateWidget would leave a's
      // listener attached.
      a.applyCapability(const GlassCapability.supported());
      await tester.pump();
      expect(log.length, buildsAfterSwap);
      expect(log.last.tier, GlassTier.frosted);

      // The NEW settings' notification re-resolves the subtree.
      b.applyCapability(const GlassCapability.supported());
      await tester.pump();
      expect(log.last.tier, GlassTier.liquid);

      // After the scope is disposed, notifying either instance must be
      // harmless (the dangling old listener produced setState-after-dispose
      // on the next probe/kill-switch notification).
      await tester.pumpWidget(const SizedBox());
      a.forcedTier = GlassTier.flat;
      b.forcedTier = GlassTier.flat;
      expect(tester.takeException(), isNull);
    });

    testWidgets('swapping in unprobed settings re-kicks ensureProbed',
        (WidgetTester tester) async {
      final GlassSettings a = _manualSettings();
      int probeRuns = 0;
      final GlassSettings b = GlassSettings(probe: () async {
        probeRuns++;
        return const GlassCapability.supported();
      });
      Widget scope(GlassSettings settings) => _boilerplate(GlassBackdropScope(
            settings: settings,
            child: const SizedBox.shrink(),
          ));

      await tester.pumpWidget(scope(a));
      expect(probeRuns, 0);
      await tester.pumpWidget(scope(b));
      await tester.pump();
      expect(probeRuns, 1); // didUpdateWidget kicked the new instance.
      expect(b.probed, isTrue);
    });
  });

  group('layer hygiene (ARCHITECTURE.md section 3.5)', () {
    Widget twoPanelScene(GlassSettings settings) => _boilerplate(
          GlassBackdropScope(
            settings: settings,
            probeOnMount: false,
            child: Stack(
              textDirection: TextDirection.ltr,
              children: const <Widget>[
                Positioned(left: 0, top: 0, child: _FakeGlassPanel()),
                Positioned(left: 60, top: 60, child: _FakeGlassPanel()),
              ],
            ),
          ),
        );

    testWidgets('Strategy 1: two grouped panels -> two BackdropFilterLayers, ONE shared key',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      await tester.pumpWidget(twoPanelScene(settings));

      final List<BackdropFilterLayer> layers =
          tester.layers.whereType<BackdropFilterLayer>().toList();
      expect(layers, hasLength(2));

      // The scope's single BackdropGroup key is what makes the engine take
      // ONE backdrop snapshot for both panels.
      final Set<BackdropKey?> keys =
          layers.map((BackdropFilterLayer layer) => layer.backdropKey).toSet();
      expect(keys, hasLength(1));
      expect(keys.single, isNotNull);
    });

    testWidgets('flat mode: zero backdrop layers', (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings()..forcedTier = GlassTier.flat;
      await tester.pumpWidget(twoPanelScene(settings));
      expect(tester.layers.whereType<BackdropFilterLayer>(), isEmpty);
    });

    testWidgets('snapshot strategy: zero backdrop layers', (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      await tester.pumpWidget(
        _boilerplate(
          GlassBackdropScope(
            settings: settings,
            probeOnMount: false,
            strategy: GlassStrategy.snapshotCache,
            child: const _FakeGlassPanel(),
          ),
        ),
      );
      expect(tester.layers.whereType<BackdropFilterLayer>(), isEmpty);
    });
  });
}
