/// Flutter port of the Telegram Android design system: liquid glass
/// rendering, theme tokens (.attheme compatible), and the component catalog.
///
/// See `flutter/docs/ARCHITECTURE.md` in the repository for the full design.
library;

// Foundation
export 'src/foundation/blur_math.dart';
export 'src/foundation/color_math.dart';
export 'src/foundation/dimens.dart';
export 'src/foundation/tg_curves.dart';

// Generated tokens
export 'src/tokens/color_scheme.g.dart';
export 'src/tokens/glass_metrics.g.dart';
export 'src/tokens/liquid_glass_uniforms.g.dart';
export 'src/tokens/palettes/palettes.g.dart';
export 'src/tokens/theme_fallbacks.g.dart';
export 'src/tokens/theme_key_names.g.dart';
export 'src/tokens/theme_keys.g.dart';

// Theme runtime
export 'src/theme/attheme_codec.dart';
export 'src/theme/resources_override.dart';
export 'src/theme/telegram_resources.dart';
export 'src/theme/telegram_theme.dart';
export 'src/theme/telegram_theme_data.dart';

// Glass engine
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

// Components
export 'src/components/app_bar/glass_app_bar.dart';
export 'src/components/app_bar/glass_app_bar_search_field.dart';
export 'src/components/attach/tg_attach_sheet.dart';
export 'src/components/bulletin/bulletin.dart';
export 'src/components/buttons/glass_icon_button.dart';
export 'src/components/cells/dialog_cell.dart';
export 'src/components/cells/header_cell.dart';
export 'src/components/cells/shadow_section_cell.dart';
export 'src/components/cells/text_cell.dart';
export 'src/components/cells/user_cell.dart';
export 'src/components/chat_input/chat_input.dart';
export 'src/components/chat_input/chat_input_bar.dart';
export 'src/components/chat_input/record_overlay.dart';
export 'src/components/chat_input/record_send_button.dart';
export 'src/components/emoji_panel/emoji_panel.dart';
export 'src/components/scaffold/tg_scaffold.dart';
export 'src/components/sheet/tg_bottom_sheet.dart';
export 'src/components/tabs/counter_badge.dart';
export 'src/components/tabs/glass_tab.dart';
export 'src/components/tabs/glass_tab_bar.dart';
export 'src/components/tabs/tab_contract.dart';
export 'src/components/tabs/tab_icon.dart';
