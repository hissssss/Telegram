# Port status — 2026-07-18 (chat input composed + wired)

Tree state: **verified** — `flutter analyze` clean (package + example);
`flutter test` 672/672 green + 2 example tests; `python3
tool/tests/run_tests.py` 122/122 (Flutter 3.44.6, SDK expected at
/home/user/flutter-sdk or any 3.44+ stable).

## Complete
- Architecture + extracted specs (`docs/`), token codegen pipeline (`tool/`)
- `lib/src/tokens/` (generated), `foundation/`, `theme/` (data, scope, attheme codec)
- `lib/src/glass/` — full engine: geometry, uniforms packer, presets, backdrop scope,
  runtime probe, RenderGlassSurface (liquid/frosted/flat), GlassPanel, GlassEdgeFade
- Components: `tabs/` (GlassTabBar + GlassTab + TabIcon + CounterBadge),
  `app_bar/GlassAppBar`, `scaffold/TgScaffold`, `buttons/GlassIconButton`,
  `cells/` (DialogCell, UserCell, TextCell + TgSwitch, HeaderCell,
  ShadowSectionCell), `sheet/TgBottomSheet`, `bulletin/Bulletin`,
  `chat_input/` (ChatInputBar island + ChatInputBarController,
  RecordSendButton mic/video/send + RecordCircle, RecordOverlay
  slide-to-cancel/lock/timer/round-video chrome + RecordOverlayController,
  and the composed ChatInput wiring all three through the CAEV state
  machine — typing -> send morph, hold-to-record, slide cancel, lock
  persists hands-free, CANCEL/send resolve; capture stays callback slots)
- Public API: `lib/telegram_ui.dart` umbrella + `lib/glass.dart` /
  `lib/theme.dart` entry points (template Calculator + template test deleted)
- Example gallery app (`example/`): tabs_demo, chat_demo (fake bubble list
  over a busy gradient with the composed ChatInput, fake record clock and
  synthesized amplitude feed), glass_playground, theme_browser
- Package metadata: real README (usage guide + licensing warning),
  example/README, CHANGELOG 0.1.0, LICENSE (GPLv2 + derivation notice)
- Adversarial review pass applied (this session), notably:
  - `shaders/liquid_glass.frag` now clips its output to the SDF (1-px
    smoothstep feather) — without it every liquid panel painted a square
    blurred/tinted halo across its bleed-inflated rect clip on Impeller;
  - Bulletin overlay-entry lifecycle (same-frame hide, external overlay
    teardown) removes + disposes the entry unconditionally;
  - late `TgShaders` load now repaints explicit-liquid panels
    (`TgShaders.initialized` listener in RenderGlassSurface);
  - TextCell title measure cap matches TextCell.java:201
    (`width - dp(71 + leftPadding) - valueWidth`, anchored to leftPadding);
  - DialogCell time right margin is dp(15) (DialogCell.java:2268; the
    15.666 value stays badge-only);
  - `searchFloatingDate` stroke width is 1 *physical* px
    (`GlassSurfaceStyle.strokeWidthPhysicalPx`);
  - CounterBadgeDecoration reuses one disposed-on-teardown TextPainter
    instead of allocating one per animation tick;
  - TgScaffold forwards tier/strategy/settings/probeOnMount named exactly
    like GlassBackdropScope (glass* prefixes dropped);
  - drift gate: kDarkThemeBrightnessThreshold == kGlassDarkBrightnessThreshold;
  - lifecycle tests: scope settings swap, tab-bar controller swap,
    bulletin host teardown.

## Remaining
- Gallery screenshot for flutter/README.md (needs a device capture —
  flutter_tester cannot render the liquid tier).
- Premium counter-badge variant (PremiumGradient + star) is still a
  documented `UnimplementedError` stub.
- GPLv2 licensing decision before any distribution (pubspec `publish_to: none`).

## Push path (platform git proxy is read-only, 403)
`GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null git push https://github.com/hissssss/telegram.git claude/design-ui-liquid-glass-17f6mv`
using the credential store configured in `.git/config` (owner-authorized token; owner
said they will revoke it when work concludes — a fresh session may need a new token).
