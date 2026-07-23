# Port status — 2026-07-23 (PLAN_UIKIT waves 0–3 landed: full widget kit + gallery)

Tree state: **verified** — `flutter analyze` clean (telegram_ui + example +
telegram_ui_lottie); `flutter test` 1218/1218 green (telegram_ui) + 8
(telegram_ui_lottie) + 2 (example); `python3 tool/tests/run_tests.py`
122/122; grep-gate clean (no `material.dart` import in `lib/` outside
`telegram_theme.dart`); (Flutter 3.44.6, SDK expected at
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
  persists hands-free, CANCEL/send resolve; capture stays callback slots),
  `attach/` (TgAttachSheet + showTgAttachSheet: ChatAttachAlert glass
  chrome — spring open, cascade button reveal, tab switcher, action-bar
  send pill with punched counter badge; gallery pipeline is a
  `thumbnailsBuilder` slot), `emoji_panel/` (EmojiPanel chrome: type-tab
  strip with pill indicator, category strip, search row, trending header;
  emoji/GIF/sticker content pipelines are `WidgetBuilder` slots)
- **PLAN_UIKIT.md build — COMPLETE (all waves).** Every MUST (M0–M12) and
  every SHOULD (S1–S7, including the S7 stretch) component landed, exported,
  Java-cited, and tested per the §1.3 blanket contract; nothing re-triaged.
  Component table (lib/src/ directory → contents → source):
  - `foundation/` adds: `TgTextStyles` (M0, binary w400/rmedium-w500 type
    roles), `TgMotion` + `TgCurves` additions (M0b, duration/dim/curve
    dictionary), and `progress/TgCircularProgress` (M0c,
    CircularProgressDrawable segment math)
  - `buttons/`: `TgButton` (M1, ButtonWithCounterView — filled/text/neutral,
    counter pill + digit roll, loading, subText, timer), `TgDialogButton`
    (M2, AlertDialog button row convention), `TgFab` (S5,
    FragmentFloatingButton)
  - `dialog/`: `TgAlertDialog` + `showTgAlertDialog` + `TgAlertDialogCell`
    (M3, AlertDialog message/items/buttons incl. vertical overflow)
  - `menu/`: `TgPopupMenu` + `showTgPopupMenu` + `TgMenuItem` + `TgMenuGap`
    (M4, ActionBarPopupWindow + ActionBarMenuSubItem, cascade reveal)
  - `controls/`: `TgCheckBox` (M5, CheckBoxBase, 3 ring recipes), `TgRadio`
    + `TgRadioCell` (M6, RadioButton/RadioCell), `TgSlider` (M7,
    SeekBarView — steps/two-sided/buffered), `TgSlideChooser` (S7,
    SlideChooseView)
  - `avatar/`: `TgAvatar` + `TgAvatarColors` (M8, AvatarDrawable — 7
    gradient pairs, initials, saved/archived)
  - `progress/`: `TgRadialProgress` (M9, RadialProgressView state machine),
    `TgLinearProgress` (M10, LineProgressView)
  - `input/`: `TgTextField` (M11, EditTextBoldCursor — underline/floating
    header/error) + `TgOutlineContainer` (OutlineTextContainerView spring
    outline)
  - `navigation/`: `TgPageRoute` + `TgPageTransition` +
    `TgPageTransitionsBuilder` (M12, ActionBarLayout push/pop + swipe-back
    physics)
  - `hint/`: `TgHint` (S1, HintView2 bubble + arrow)
  - `loading/`: `TgFlickerLoading` (S2, FlickerLoadingView skeleton sweep);
    `empty/`: `TgEmptyView` (S3, StickerEmptyView)
  - `chips/`: `TgChip` (S4, GroupCreateSpan delete-morph pill)
  - `components/bulletin/`: `Bulletin.showUndo` + `BulletinCountdown` (S6,
    the Bulletin undo/countdown variant)
  All exported from the `lib/telegram_ui.dart` umbrella; ARCHITECTURE.md §6
  carries the per-component constant summaries. Example gallery gained a
  fifth page, `widgets_demo.dart` (every new control at least once + a
  TgPageRoute detail-page push), and `tabs_demo`/`theme_browser` now use
  `TgAvatar` (the local `gradient_avatar.dart` helper was deleted).
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
  pages), glass_playground, widgets_demo (the PLAN_UIKIT catalog page),
  theme_browser
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
- PLAN_UIKIT §5 deliberate deferrals (unchanged): date/time/number pickers,
  nav drawer, reactions strip, rating bar, standalone AnimatedTextView,
  FragmentContextView banner, and the NICE dialog/menu/slider/text-field
  extras (blurred dialog bg, `fitItems`, nested swipe-back submenus, slider
  timestamps, TgLinearProgress shimmer, animated hint swap).
- ~~Premium counter-badge variant~~ DONE: `CounterBadgePainter`
  `premium: true` now draws the GlassTabView.java:196-206 pass — the
  4-stop `premiumGradient1..4` main-gradient round rect (the
  PremiumGradientTools shader math of PremiumGradient.java:211-222/258,
  96x16 matrix, ported standalone — the rest of PremiumGradient is not)
  plus the white 14dp `res/drawable/star.xml` path, visibility pinned
  to 1; `CounterBadgeDecoration(premium: true)` resolves the four keys
  through the theme/resources.
- GPLv2 licensing decision before any distribution (pubspec `publish_to: none`).

## Push path (platform git proxy is read-only, 403)
`GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null git push https://github.com/hissssss/telegram.git claude/design-ui-liquid-glass-17f6mv`
using the credential store configured in `.git/config` (owner-authorized token; owner
said they will revoke it when work concludes — a fresh session may need a new token).
