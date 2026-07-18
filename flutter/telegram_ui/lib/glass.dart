/// A-la-carte entry point: the liquid-glass rendering primitives only —
/// no components, no full theme runtime (ARCHITECTURE.md section 2,
/// graft: API/DX).
///
/// Exports the glass engine (`GlassPanel`, `GlassBackdropScope`,
/// `GlassPresets`, tiers/strategies, the runtime probe) together with its
/// minimal dependency closure:
///
///  * the foundation helpers (`TgDimens`, blur/color math, `TgCurves`) —
///    used throughout the glass geometry and referenced by public doc
///    contracts;
///  * the generated glass constants (`glass_metrics.g.dart`) and shader
///    uniform slots (`liquid_glass_uniforms.g.dart`) — defaults of
///    `LiquidGlassSettings` and `TgShaders`;
///  * `TelegramColorKey` (`theme_keys.g.dart`) and [TelegramResources] with
///    its `ResourcesOverride` helper — every preset resolver takes a
///    `TelegramResources` and reads `TelegramColorKey.*` ordinals, so the
///    glass layer cannot be used without them.
///
/// Deliberately NOT exported: the theme widgets (`TelegramTheme`,
/// `TelegramThemeData`, the `.attheme` codec) and the component catalog.
/// `GlassPanel` falls back to `TelegramTheme.resources(context)` only when
/// its `resources` parameter is null — callers of this entry point should
/// pass resources explicitly (or import `package:telegram_ui/theme.dart` /
/// the umbrella `package:telegram_ui/telegram_ui.dart`).
library;

// Foundation (dependency closure of the glass geometry + curves).
export 'src/foundation/blur_math.dart';
export 'src/foundation/color_math.dart';
export 'src/foundation/dimens.dart';
export 'src/foundation/tg_curves.dart';

// Generated tokens the glass layer depends on.
export 'src/tokens/glass_metrics.g.dart';
export 'src/tokens/liquid_glass_uniforms.g.dart';
export 'src/tokens/theme_keys.g.dart';

// Minimal theme surface: the ResourcesProvider analog that presets resolve
// against (not the full theme runtime).
export 'src/theme/resources_override.dart';
export 'src/theme/telegram_resources.dart';

// The glass engine.
export 'src/glass/backdrop_scope.dart';
export 'src/glass/geometry.dart';
export 'src/glass/glass_fade.dart';
export 'src/glass/glass_panel.dart';
export 'src/glass/liquid_glass_settings.dart';
export 'src/glass/liquid_glass_shader.dart';
export 'src/glass/presets.dart';
export 'src/glass/render_glass_surface.dart';
export 'src/glass/runtime_probe.dart';
export 'src/glass/strategy.dart';
export 'src/glass/surface_colors.dart';
