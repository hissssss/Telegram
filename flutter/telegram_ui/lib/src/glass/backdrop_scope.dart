// Shared-backdrop scope of the glass system (ARCHITECTURE.md sections 3.2
// and 3.5, graft: PERF).
//
// Port of the shared-source architecture of
// `java/org/telegram/ui/Components/blur3/BlurredBackgroundDrawableViewFactory.java`:
// one factory per page owns the `BlurredBackgroundSource` whose downscaled
// `SourcePart` render nodes are recorded once per frame and sampled by every
// linked drawable (`DownscaleScrollableNoiseSuppressor.java:408-428`), and
// the factory is also where the page-wide liquid permission is injected
// (`setLiquidGlassEffectAllowed`,
// BlurredBackgroundDrawableViewFactory.java:57-86).
//
// The Flutter analog: [GlassBackdropScope] mounts one [BackdropGroup] per
// page — every glass panel below it that uses `BackdropFilter.grouped` (or
// passes the group's `BackdropKey`) shares a single backdrop snapshot per
// frame instead of triggering one readback each — and publishes an inherited
// [GlassScopeData] carrying the subtree's resolved [GlassTier] and
// [GlassStrategy]. Tier resolution consults `GlassSettings` (kill-switch +
// runtime probe, `runtime_probe.dart`) and the scope listens to it, so a
// late probe completion upgrades the whole subtree without any caller
// wiring.
library;

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'runtime_probe.dart';
import 'strategy.dart';

/// The resolved glass configuration [GlassBackdropScope] publishes to its
/// subtree.
///
/// [requestedTier]/[requestedStrategy] are what the scope asked for (they
/// flow into nested scopes that leave their own parameters null);
/// [tier]/[strategy] are the effective values after
/// [GlassSettings.resolvedTier] applied the kill-switch and probe verdict.
@immutable
class GlassScopeData {
  /// Creates scope data with explicit resolved values. Prefer
  /// [GlassScopeData.resolve], which derives them from [GlassSettings].
  const GlassScopeData({
    required this.requestedTier,
    required this.requestedStrategy,
    required this.tier,
    required this.strategy,
  });

  /// Resolves a request against [settings] (default [GlassSettings.instance]):
  /// [tier] via [GlassSettings.resolvedTier], and [strategy] forced to
  /// [GlassStrategy.tintOnly] when the tier resolved to [GlassTier.flat] —
  /// the flat floor never pays for a backdrop layer (ARCHITECTURE.md
  /// section 3.2, Strategy 3).
  factory GlassScopeData.resolve({
    GlassTier requestedTier = GlassTier.liquid,
    GlassStrategy requestedStrategy = GlassStrategy.backdropShader,
    GlassSettings? settings,
  }) {
    final GlassTier tier = (settings ?? GlassSettings.instance).resolvedTier(requestedTier);
    return GlassScopeData(
      requestedTier: requestedTier,
      requestedStrategy: requestedStrategy,
      tier: tier,
      strategy: tier == GlassTier.flat ? GlassStrategy.tintOnly : requestedStrategy,
    );
  }

  /// The tier the scope requested, before the kill-switch/probe.
  final GlassTier requestedTier;

  /// The strategy the scope requested, before the flat-tier downgrade.
  final GlassStrategy requestedStrategy;

  /// The effective tier for the subtree.
  final GlassTier tier;

  /// The effective strategy for the subtree.
  final GlassStrategy strategy;

  /// Whether panels under this scope should mount a backdrop-reading layer
  /// (`BackdropFilter.grouped`). False in snapshot/tint modes — the layer
  /// tree must then contain zero `BackdropFilterLayer`s (the layer-hygiene
  /// invariant of ARCHITECTURE.md section 3.5).
  bool get wantsBackdropLayer => strategy == GlassStrategy.backdropShader;

  @override
  bool operator ==(Object other) =>
      other is GlassScopeData &&
      other.requestedTier == requestedTier &&
      other.requestedStrategy == requestedStrategy &&
      other.tier == tier &&
      other.strategy == strategy;

  @override
  int get hashCode => Object.hash(requestedTier, requestedStrategy, tier, strategy);

  @override
  String toString() =>
      'GlassScopeData(tier: ${tier.name} (requested ${requestedTier.name}), '
      'strategy: ${strategy.name} (requested ${requestedStrategy.name}))';
}

/// One shared backdrop + resolved glass configuration per page
/// (ARCHITECTURE.md section 3.2: `TgScaffold` mounts exactly one).
///
/// The scope:
///
///  * mounts a [BackdropGroup] with a [BackdropKey] that stays stable across
///    rebuilds, so all grouped backdrop filters below share one backdrop
///    snapshot per frame — the analog of blur3's shared `SourcePart` nodes;
///  * publishes [GlassScopeData] (looked up via [of]/[maybeOf]) resolving
///    the requested [tier]/[strategy] through [GlassSettings];
///  * listens to its [GlassSettings] and kicks [GlassSettings.ensureProbed]
///    on mount (disable via [probeOnMount]), so the subtree re-resolves when
///    the runtime probe completes late or the kill-switch flips.
///
/// Nested scopes inherit the enclosing scope's *requested* tier/strategy for
/// any parameter left null, then re-resolve — so a page-level tier override
/// propagates, while a probe downgrade never compounds.
class GlassBackdropScope extends StatefulWidget {
  /// Creates a scope. Null [tier]/[strategy] inherit from an enclosing scope,
  /// falling back to [GlassTier.liquid] / [GlassStrategy.backdropShader].
  const GlassBackdropScope({
    super.key,
    this.tier,
    this.strategy,
    this.settings,
    this.probeOnMount = true,
    required this.child,
  });

  /// Requested tier for the subtree; the effective tier still passes through
  /// [GlassSettings.resolvedTier].
  final GlassTier? tier;

  /// Requested strategy for the subtree.
  final GlassStrategy? strategy;

  /// Settings to resolve against and listen to; null uses
  /// [GlassSettings.instance].
  final GlassSettings? settings;

  /// Whether mounting the scope fires [GlassSettings.ensureProbed]
  /// (idempotent). Disable in tests that drive capability manually.
  final bool probeOnMount;

  /// The subtree the scope applies to.
  final Widget child;

  /// The [GlassScopeData] of the nearest enclosing scope, or null when there
  /// is none. Registers an inherited dependency either way.
  static GlassScopeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassScopeMarker>()?.data;

  /// The [GlassScopeData] of the nearest enclosing scope. Throws a
  /// [FlutterError] when there is none — see [resolve] for a lenient lookup.
  static GlassScopeData of(BuildContext context) {
    final GlassScopeData? data = maybeOf(context);
    if (data == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('GlassBackdropScope.of() called with a context that does '
            'not contain a GlassBackdropScope.'),
        ErrorHint('Wrap the page in a GlassBackdropScope (TgScaffold does '
            'this), or use GlassBackdropScope.resolve() for a scope-less '
            'default.'),
        context.describeElement('The context used was'),
      ]);
    }
    return data;
  }

  /// Like [of], but a missing scope yields default-request data resolved
  /// against [GlassSettings.instance] instead of throwing.
  ///
  /// Note that without a scope nothing listens to the settings on the
  /// caller's behalf — a caller that must react to late probe completion
  /// should sit under a scope (or listen to [GlassSettings] itself).
  static GlassScopeData resolve(BuildContext context) =>
      maybeOf(context) ?? GlassScopeData.resolve();

  @override
  State<GlassBackdropScope> createState() => _GlassBackdropScopeState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<GlassTier>('tier', tier, defaultValue: null))
      ..add(EnumProperty<GlassStrategy>('strategy', strategy, defaultValue: null))
      ..add(FlagProperty('probeOnMount', value: probeOnMount, ifFalse: 'no probe on mount'));
  }
}

class _GlassBackdropScopeState extends State<GlassBackdropScope> {
  /// One page-lifetime key: `BackdropGroup`'s default constructor mints a
  /// fresh `BackdropKey` per build, which would re-notify every dependent on
  /// every rebuild; owning the key here keeps the group stable.
  final BackdropKey _backdropKey = BackdropKey();

  GlassSettings get _settings => widget.settings ?? GlassSettings.instance;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    if (widget.probeOnMount) {
      unawaited(_settings.ensureProbed());
    }
  }

  @override
  void didUpdateWidget(GlassBackdropScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    final GlassSettings oldSettings = oldWidget.settings ?? GlassSettings.instance;
    if (!identical(oldSettings, _settings)) {
      oldSettings.removeListener(_onSettingsChanged);
      _settings.addListener(_onSettingsChanged);
      if (widget.probeOnMount) {
        unawaited(_settings.ensureProbed());
      }
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    setState(() {
      // Resolution happens in build; the settings notification (probe
      // completion / kill-switch flip) may change its outcome.
    });
  }

  @override
  Widget build(BuildContext context) {
    final GlassScopeData? parent = GlassBackdropScope.maybeOf(context);
    final GlassScopeData data = GlassScopeData.resolve(
      requestedTier: widget.tier ?? parent?.requestedTier ?? GlassTier.liquid,
      requestedStrategy:
          widget.strategy ?? parent?.requestedStrategy ?? GlassStrategy.backdropShader,
      settings: _settings,
    );
    return _GlassScopeMarker(
      data: data,
      child: BackdropGroup(backdropKey: _backdropKey, child: widget.child),
    );
  }
}

/// The inherited carrier of [GlassScopeData]; notifies on value change only.
class _GlassScopeMarker extends InheritedWidget {
  const _GlassScopeMarker({required this.data, required super.child});

  final GlassScopeData data;

  @override
  bool updateShouldNotify(_GlassScopeMarker oldWidget) => data != oldWidget.data;
}
