# Telegram Design System — Flutter Port

A Flutter port of the Telegram Android design system: the liquid glass
rendering pipeline (`blur3/` + `liquid_glass_shader.agsl`), the theme token
system (777 int-keyed colors, `.attheme` compatible), and the core component
catalog (glass tab bar, action bar, cells, sheets, bulletins).

- `telegram_ui/` — the Flutter package (see `telegram_ui/example/` for the gallery app)
- `tool/` — Python (stdlib-only) codegen: Java sources → `theme_tokens.json` → generated Dart
- `docs/` — architecture and extracted design specs

## Architecture

Read `docs/ARCHITECTURE.md` first. Short version: one public API with tiered
rendering — `liquid` (SDF refraction shader via `ImageFilter.shader`, Impeller
only), `frosted` (downscaled blur + saturation), `flat` (tint only) — mirroring
Android's `DRAW_GLASS` / `DRAW_FROSTED_GLASS` / LiteMode-off ladder. Theme
tokens are generated from the Java sources and preserve key ordinals exactly.

## Usage

Depend on the package by path (it is not published — see Licensing):

```yaml
dependencies:
  telegram_ui:
    path: ../flutter/telegram_ui   # adjust to your checkout layout
```

Import the umbrella (`package:telegram_ui/telegram_ui.dart`), or a-la-carte
entry points: `package:telegram_ui/theme.dart` (theme system only) and
`package:telegram_ui/glass.dart` (glass primitives + minimal deps).

### Theme setup

Install a `TelegramThemeData` above your widget tree — either directly:

```dart
TelegramTheme(
  data: TelegramThemeData.day(),   // or .night(), .fromBundledTheme('Arctic Blue')
  child: home,
)
```

or through Material's extension mechanism (theme switches then animate):

```dart
MaterialApp(
  theme: ThemeData(
    extensions: [TelegramThemeExtension(TelegramThemeData.day())],
  ),
)
```

Components resolve colors via `TelegramTheme.colorOf(context, TelegramColorKey.*)`
(per-key rebuild granularity) and take an optional `TelegramResources?
resources` override, mirroring the Android `resourcesProvider` convention.

### Glass in ten lines

```dart
GlassBackdropScope(              // one per page; TgScaffold mounts one for you
  child: SizedBox(
    width: 260, height: 150,
    child: GlassPanel(
      preset: GlassPresets.mainTabs,             // Android color recipe
      borderRadius: const GlassRadii.all(28),
      settings: const LiquidGlassSettings(),      // thickness 11, intensity 0.75
      child: const Center(child: Text('liquid glass')),
    ),
  ),
)
```

Call `GlassSettings.instance.ensureProbed()` at startup to run the capability
probe + shader warmup; liquid requests render frosted until it proves the
backend can run the refraction shader (Impeller required).

### Gallery

`telegram_ui/example/` is the gallery app: a DialogsActivity-style tabs demo,
a liquid-glass playground with live sliders, and a bundled-theme browser.

<!-- TODO: capture a gallery screenshot on a device and embed it here as
     docs/gallery_screenshot.png — flutter_tester cannot render the liquid
     tier. -->

## Toolchain

- Flutter: pinned stable (developed against 3.44.6 / Dart 3.12). The liquid
  tier requires Impeller (`ui.ImageFilter.isShaderFilterSupported`).
- Codegen: Python 3, stdlib only. Regenerate with
  `python3 tool/gen_tokens.py && python3 tool/emit_dart.py`; CI runs both with
  `--check`.

## Licensing

Telegram Android is GPLv2; this port derives its shader, tokens, and component
specs from those sources and therefore carries the same copyleft obligations.
It must not be published to pub.dev or distributed outside this repository
until an explicit licensing decision is made. Apps depending on this package
must be GPL-compatible.
