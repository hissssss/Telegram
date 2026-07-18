## 0.1.0

Initial port of the Telegram Android design system.

* Glass engine: tiered rendering (liquid SDF refraction shader / frosted
  double-blur + saturation / flat tint), `GlassPanel`/`FrostedPanel`,
  `GlassBackdropScope` shared-backdrop grouping, `GlassEdgeFade`, the Android
  color-recipe presets, runtime capability probe + shader warmup, and the
  `GlassSettings` tier kill-switch.
* Theme runtime: the 777 int-keyed color tokens generated from Theme.java
  (ordinals preserved), bundled day/night/dark palettes, `.attheme` codec,
  `TelegramTheme`/`TelegramResources` with per-key rebuild granularity.
* Component catalog: `GlassTabBar` (+ tabs, counter badge), `GlassAppBar`,
  `TgScaffold`, `GlassIconButton`, cells (`DialogCell`, `UserCell`,
  `TextCell` + `TgSwitch`, `HeaderCell`, `ShadowSectionCell`),
  `TgBottomSheet`, `Bulletin`.
* Example gallery app: tabs demo, liquid-glass playground, theme browser.
* Not published (`publish_to: none`) pending the GPLv2 licensing decision —
  see `LICENSE` and `flutter/README.md`.
