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
