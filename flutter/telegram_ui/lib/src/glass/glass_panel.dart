// The themed glass surface widgets — the configuration layer over
// [RenderGlassSurface].
//
// Port of the view-facing surface of
// `java/org/telegram/ui/Components/blur3/drawable/BlurredBackgroundDrawable.java`
// as wired by its factory
// (`blur3/BlurredBackgroundDrawableViewFactory.java`): a view picks a color
// provider (here a [GlassSurfaceStyle] or a `GlassPresets` resolver), radii,
// drawable padding, and the liquid parameters, and the factory injects the
// page-wide tier permission — here the enclosing `GlassBackdropScope`
// resolution, with an optional per-panel [GlassPanel.tier] override
// (mirroring surfaces that force frosted, e.g. Android's frosted top bars,
// ARCHITECTURE.md section 3.5).
//
// [GlassPanel] resolves everything that needs a [BuildContext] — theme
// resources, scope tier/strategy, the shared `BackdropKey`, the device pixel
// ratio — and feeds the value-comparable results into the render object.
// [FrostedPanel] is the convenience that pins [GlassTier.frosted].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../theme/telegram_resources.dart';
import '../theme/telegram_theme.dart';
import '../tokens/theme_keys.g.dart';
import 'backdrop_scope.dart';
import 'geometry.dart';
import 'liquid_glass_settings.dart';
import 'presets.dart';
import 'strategy.dart';
import 'surface_colors.dart';
import 'render_glass_surface.dart';

/// A glass surface: shadow, backdrop-driven fill, child, hairline strokes —
/// the widget face of [RenderGlassSurface]
/// (ARCHITECTURE.md sections 3.2 and 6, "GlassPanel / FrostedPanel").
///
/// Style resolution order:
///
///  1. an explicit [style] wins;
///  2. else [preset] (a `GlassPresets` factory reference, e.g.
///     `GlassPanel(preset: GlassPresets.mainTabs)`) resolved against
///     [resources] (default: `TelegramTheme.resources(context)`) at the
///     effective tier;
///  3. else the themed default — `BlurredBackgroundColorProviderThemed` over
///     `windowBackgroundWhite` (the common Java default provider).
///
/// The liquid [settings]' tint is wired to the resolved style's background
/// color when left transparent, matching Android where the color provider's
/// `getBackgroundColor()` is what `LiquidGlassEffect.update` premultiplies
/// into the shader. The [borderRadius] drives both the clip and the shader
/// radii ([forceBottomZero] splits them, BlurredBackgroundDrawable.java:119-131).
class GlassPanel extends StatelessWidget {
  /// Creates a glass panel. At most one of [style] and [preset] may be given.
  const GlassPanel({
    super.key,
    this.style,
    this.preset,
    this.settings = const LiquidGlassSettings(),
    this.tier,
    this.borderRadius = GlassRadii.zero,
    this.forceBottomZero = false,
    this.padding = 0.0,
    this.resources,
    this.child,
  }) : assert(style == null || preset == null, 'Provide style OR preset, not both.');

  /// Explicit resolved style; wins over [preset].
  final GlassSurfaceStyle? style;

  /// A `GlassPresets` factory resolved at build time against [resources] and
  /// the effective tier.
  final GlassSurfaceStyleResolver? preset;

  /// Liquid refraction parameters (logical px). A transparent
  /// [LiquidGlassSettings.tintColor] is replaced by the resolved style's
  /// background color.
  final LiquidGlassSettings settings;

  /// Per-panel tier override. Null (default) uses the enclosing
  /// `GlassBackdropScope` resolution; an explicit value is taken as-is
  /// (the render object still degrades liquid to frosted on backends without
  /// shader-filter support).
  final GlassTier? tier;

  /// Corner radii of the surface — the Java `setRadius` values, driving the
  /// clip, strokes, outline, and (un-forced) the refraction SDF.
  final GlassRadii borderRadius;

  /// Squares the bottom clip corners while the shader keeps [borderRadius] —
  /// the Java `forceBottomZero` quirk for panels flush against the keyboard.
  final bool forceBottomZero;

  /// Symmetric inset of the glass visuals within the panel bounds, in
  /// logical px — the Java drawable padding (the main tab bar uses 7.666dp).
  /// Child layout is unaffected.
  final double padding;

  /// Palette for [preset]/default-style resolution; defaults to
  /// `TelegramTheme.resources(context)` (the `resourcesProvider` convention).
  /// Unused when [style] is given.
  final TelegramResources? resources;

  /// The panel content, wrapped in a [RepaintBoundary]
  /// (ARCHITECTURE.md section 3.5: one boundary around each glass surface's
  /// child).
  final Widget? child;

  /// The default themed recipe: `BlurredBackgroundColorProviderThemed` over
  /// `windowBackgroundWhite`.
  static GlassSurfaceStyle _themedDefault(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) => GlassSurfaceStyle.themed(
    resources: resources,
    colorKey: TelegramColorKey.windowBackgroundWhite,
    tier: tier,
  );

  @override
  Widget build(BuildContext context) {
    final GlassScopeData scope = GlassBackdropScope.resolve(context);
    final GlassTier tier = this.tier ?? scope.tier;
    final GlassStrategy strategy =
        tier == GlassTier.flat ? GlassStrategy.tintOnly : scope.strategy;

    GlassSurfaceStyle? style = this.style;
    if (style == null) {
      final TelegramResources resolved = resources ?? TelegramTheme.resources(context);
      style = (preset ?? _themedDefault)(resolved, tier: tier);
    }

    final LiquidGlassSettings settings = this.settings.tintColor.a == 0
        ? this.settings.copyWith(tintColor: style.backgroundColor)
        : this.settings;

    final BackdropKey? backdropKey = strategy == GlassStrategy.backdropShader
        ? BackdropGroup.of(context)?.backdropKey
        : null;
    final double devicePixelRatio =
        MediaQuery.maybeDevicePixelRatioOf(context) ?? View.of(context).devicePixelRatio;
    final int themeRevision = TelegramTheme.maybeOf(context)?.revision ?? 0;

    return _RawGlassSurface(
      tier: tier,
      strategy: strategy,
      style: style,
      settings: settings,
      radii: borderRadius,
      forceBottomZero: forceBottomZero,
      padding: padding,
      devicePixelRatio: devicePixelRatio,
      themeRevision: themeRevision,
      backdropKey: backdropKey,
      child: child == null ? null : RepaintBoundary(child: child),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<GlassSurfaceStyle>('style', style, defaultValue: null))
      ..add(DiagnosticsProperty<LiquidGlassSettings>('settings', settings))
      ..add(EnumProperty<GlassTier>('tier', tier, defaultValue: null))
      ..add(DiagnosticsProperty<GlassRadii>('borderRadius', borderRadius))
      ..add(FlagProperty('forceBottomZero', value: forceBottomZero, ifTrue: 'square bottom clip'))
      ..add(DoubleProperty('padding', padding, defaultValue: 0.0));
  }
}

/// A [GlassPanel] pinned to [GlassTier.frosted] — the tier Android uses for
/// full-width bars (`GlassAppBar` defaults to frosted; documented area
/// budget of ARCHITECTURE.md section 3.5).
class FrostedPanel extends StatelessWidget {
  /// Creates a frosted panel. At most one of [style] and [preset] may be
  /// given.
  const FrostedPanel({
    super.key,
    this.style,
    this.preset,
    this.settings = const LiquidGlassSettings(),
    this.borderRadius = GlassRadii.zero,
    this.forceBottomZero = false,
    this.padding = 0.0,
    this.resources,
    this.child,
  }) : assert(style == null || preset == null, 'Provide style OR preset, not both.');

  /// See [GlassPanel.style].
  final GlassSurfaceStyle? style;

  /// See [GlassPanel.preset].
  final GlassSurfaceStyleResolver? preset;

  /// See [GlassPanel.settings]. Refraction parameters are inert in the
  /// frosted tier but preserved for tier crossfades.
  final LiquidGlassSettings settings;

  /// See [GlassPanel.borderRadius].
  final GlassRadii borderRadius;

  /// See [GlassPanel.forceBottomZero].
  final bool forceBottomZero;

  /// See [GlassPanel.padding].
  final double padding;

  /// See [GlassPanel.resources].
  final TelegramResources? resources;

  /// See [GlassPanel.child].
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      tier: GlassTier.frosted,
      style: style,
      preset: preset,
      settings: settings,
      borderRadius: borderRadius,
      forceBottomZero: forceBottomZero,
      padding: padding,
      resources: resources,
      child: child,
    );
  }
}

/// The leaf render-object widget backing [GlassPanel]: every field is already
/// resolved and value-comparable.
class _RawGlassSurface extends SingleChildRenderObjectWidget {
  const _RawGlassSurface({
    required this.tier,
    required this.strategy,
    required this.style,
    required this.settings,
    required this.radii,
    required this.forceBottomZero,
    required this.padding,
    required this.devicePixelRatio,
    required this.themeRevision,
    required this.backdropKey,
    super.child,
  });

  final GlassTier tier;
  final GlassStrategy strategy;
  final GlassSurfaceStyle style;
  final LiquidGlassSettings settings;
  final GlassRadii radii;
  final bool forceBottomZero;
  final double padding;
  final double devicePixelRatio;
  final int themeRevision;
  final BackdropKey? backdropKey;

  @override
  RenderGlassSurface createRenderObject(BuildContext context) => RenderGlassSurface(
    tier: tier,
    strategy: strategy,
    style: style,
    settings: settings,
    radii: radii,
    forceBottomZero: forceBottomZero,
    padding: padding,
    devicePixelRatio: devicePixelRatio,
    themeRevision: themeRevision,
    backdropKey: backdropKey,
  );

  @override
  void updateRenderObject(BuildContext context, RenderGlassSurface renderObject) {
    renderObject
      ..tier = tier
      ..strategy = strategy
      ..style = style
      ..settings = settings
      ..radii = radii
      ..forceBottomZero = forceBottomZero
      ..padding = padding
      ..devicePixelRatio = devicePixelRatio
      ..themeRevision = themeRevision
      ..backdropKey = backdropKey;
  }
}
