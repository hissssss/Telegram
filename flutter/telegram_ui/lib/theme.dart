/// A-la-carte entry point: the Telegram theme system only — the 777-key
/// color-table runtime, generated tokens, and the `.attheme` codec, with no
/// glass rendering and no components (ARCHITECTURE.md section 2,
/// graft: API/DX).
///
/// Use this to theme an app with the Telegram palette without pulling the
/// glass engine into scope:
///
/// ```dart
/// import 'package:telegram_ui/theme.dart';
///
/// TelegramTheme(
///   data: TelegramThemeData.day(),
///   child: ...,
/// )
/// ```
///
/// Also exports `color_math.dart` (perceived brightness / composite / solve
/// helpers): `TelegramThemeData.brightness` and `ResourcesOverride` are
/// specified in terms of `isDarkColor`/`perceivedBrightness`, and custom
/// `TelegramResources` implementations routinely need them.
library;

// Foundation helpers the theme contracts are specified in terms of.
export 'src/foundation/color_math.dart';

// Generated tokens.
export 'src/tokens/color_scheme.g.dart';
export 'src/tokens/palettes/palettes.g.dart';
export 'src/tokens/theme_fallbacks.g.dart';
export 'src/tokens/theme_key_names.g.dart';
export 'src/tokens/theme_keys.g.dart';

// Theme runtime.
export 'src/theme/attheme_codec.dart';
export 'src/theme/resources_override.dart';
export 'src/theme/telegram_resources.dart';
export 'src/theme/telegram_theme.dart';
export 'src/theme/telegram_theme_data.dart';
