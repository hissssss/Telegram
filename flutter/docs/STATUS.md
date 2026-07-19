# Port status — 2026-07-19 (attach sheet + emoji panel + lottie adapter wired)

Tree state: **verified** — `flutter analyze` clean (telegram_ui + example +
telegram_ui_lottie); `flutter test` 731/731 green (telegram_ui) + 8
(telegram_ui_lottie) + 2 (example); `python3 tool/tests/run_tests.py`
122/122 (Flutter 3.44.6, SDK expected at /home/user/flutter-sdk or any
3.44+ stable).

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
  persists hands-free, CANCEL/send resolve; capture stays callback slots),
  `attach/` (TgAttachSheet + showTgAttachSheet: ChatAttachAlert glass
  chrome — spring open, cascade button reveal, tab switcher, action-bar
  send pill with punched counter badge; gallery pipeline is a
  `thumbnailsBuilder` slot), `emoji_panel/` (EmojiPanel chrome: type-tab
  strip with pill indicator, category strip, search row, trending header;
  emoji/GIF/sticker content pipelines are `WidgetBuilder` slots)
- Companion package `flutter/telegram_ui_lottie/`: the `package:lottie`
  adapter for animated tab icons — `LottieTabAnimation` implements the
  `TabAnimationController` contract (RLottieDrawable frame semantics:
  custom end frame, play-toward-end-frame direction), plus
  `lottieTabIcon` / `loadLottieAssetTabIcon` conveniences. `telegram_ui`
  itself still has zero lottie dependency.
- Public API: `lib/telegram_ui.dart` umbrella (now incl. attach +
  emoji_panel) + `lib/glass.dart` / `lib/theme.dart` entry points
  (template Calculator + template test deleted)
- Example gallery app (`example/`): tabs_demo (Calls tab icon is the real
  `TMessagesProj/src/main/res/raw/tab_calls.json` composition copied to
  `example/assets/lottie/` and driven through telegram_ui_lottie — forward
  on select, reverse on deselect), chat_demo (fake bubble list over a busy
  gradient with the composed ChatInput, fake record clock and synthesized
  amplitude feed; the bar's emoji slot toggles an EmojiPanel with a
  placeholder emoji grid that appends to the draft, the attach slot opens
  TgAttachSheet with colored placeholder thumbnails + file/location stub
  pages), glass_playground, theme_browser
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
