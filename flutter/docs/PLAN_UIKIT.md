# PLAN_UIKIT — completing `telegram_ui` as a general-purpose UI kit

Date: 2026-07-19. Branch `claude/design-ui-liquid-glass-17f6mv`.
Synthesized from the two gap audits (kit lens + forms lens) and the four spec extracts:
`spec_forms.md`, `spec_dialog_menu.md`, `spec_primitives.md`, `spec_typography_motion.md`
(all under `flutter/docs/`, all with Java file:line citations — **builders MUST read the
relevant spec file before writing a line of code**; the summaries below are indexes, not
replacements).

Package: `/home/user/Telegram/flutter/telegram_ui`. Baseline: ALL GREEN (757 pkg + 2
example + 8 lottie tests). Nothing in this plan may regress that.

---

## 1. Component list

### 1.1 MUST wave (fully specced; any app needs these)

Every MUST component has a written spec with citations. "Spec" column names the
authoritative doc. Test expectations are in addition to the blanket contract in §1.3.

#### M0. `TgTextStyles` — `lib/src/foundation/tg_text_styles.dart`
- **Source:** diffuse — the de-facto scale swept in `spec_typography_motion.md` §1.2
  (DialogCell.java, TextCell.java, AlertDialog.java, ActionBar.java, Theme.java paints…).
- **Spec:** 16-role scale, sizes 10–20dp, weights strictly w400/w500 (`bold()` = Roboto
  Medium `rmedium.ttf`, family `RobotoMedium`; w700 never appears). Roles: title 20/500,
  titleCondensed 18/500, titleGlass 17/500, input 18/400, cellTitle 17/500, body 16/400,
  bodyEmphasis 16/500, bodySecondary 15/400, tab 15/500, label 14/500, subtitle 14/400,
  caption 13/400, captionEmphasis 13/500, micro 12/400, microEmphasis 12/500,
  tagSmall 11/500, tag 10/500. Styles carry no color (color always resolves via theme
  keys at the use site). Pin `TextHeightBehavior(applyHeightToFirstAscent:false,
  applyHeightToLastDescent:false)` as a shared const.
- **Tests:** every role's size/weight/fontFamily asserted against the table; no w700
  anywhere in the class; height-behavior const exported.

#### M0b. `TgMotion` — `lib/src/foundation/tg_motion.dart` (+ additions to existing `tg_curves.dart`)
- **Source:** `CubicBezierInterpolator.java:11-22`, `ActionBarLayout.java`,
  `BottomSheet.java`, `ActionBarPopupWindow.java` — `spec_typography_motion.md` §2.
- **Spec:** pageDuration 150ms, pageSlide 48dp, pageCurve = `1-(1-t)^3`
  (DecelerateInterpolator(1.5)), pageScrimMax 0.376; sheetOpen 400ms EASE_OUT_QUINT
  (+20ms delay), sheetClose 250ms EASE_OUT; dialogDim 0.5 (decor dim fade 300ms);
  menuOpenBase 150ms + 16ms/item, menuClose 150ms; easeOut (0,0,.58,1),
  easeOutQuint (.23,1,.32,1), easeOutBack (.34,1.56,.64,1), overshoot(T) helper curve.
- **Tests:** curve math spot-checks (pageCurve(0.5) == 0.875; overshoot end == 1.0);
  constants table asserted.

#### M0c. `TgCircularProgressPainter` — `lib/src/progress/tg_circular_progress.dart`
- **Source:** `ui/Components/CircularProgressDrawable.java` — `spec_primitives.md` §4.2.
- **Spec:** arc 18dp diameter, 2.25dp stroke, round cap+join, default white; Material
  head/tail cycle period 5400ms — ends advance 1520°·t/5400 (tail leads 20°), 4 pulses
  of 250° per period, FastOutSlowIn over 667ms; sweep breathes ~20°↔~270°.
  This is the in-button spinner shared by TgButton, TgDialogButton, TgAlertDialog.
- **Tests:** painter geometry at t=0 / quarter-period samples; repaint on tick;
  configurable size + color.

#### M1. `TgButton` — `lib/src/buttons/tg_button.dart`
- **Source:** `ui/Stories/recorder/ButtonWithCounterView.java` (the canonical modern
  button, 380 uses) + `ScaleStateListAnimator.java` — `spec_primitives.md` §1.
- **Spec:** 48dp tall, r8 (`.round` = r24 stadium); filled = `featuredStickers_addButton`
  bg / `featuredStickers_buttonText` 14dp w500 label, text mode = transparent + regular
  weight + 10%-alpha ripple, neutral = `buttonNeutral`/`buttonNeutralText`. Press scale
  0.98 in 80ms, release 350ms Overshoot(1.2). Loading: 320ms EASE_OUT_QUINT crossfade —
  spinner (M0c, label color) drops from −24dp while label rises 24dp and squashes to
  0.6y. Counter pill: h18 r10, 12dp w500 count in fill color, gap 5dp, alpha 350ms
  EASE_OUT_QUINT, change-bounce Overshoot(2.0) 200ms; `setCountFilled(false)` bare
  14dp@50%; timer mode ticks 1/s. Disabled = animated content alpha 0.5.
- **Tests:** variant colors resolve through theme keys; press-scale animates on tap-down
  (pump 80ms) and overshoots on release; loading swap hides label; counter pill appears/
  bounces on count change; disabled ignores tap + halves alpha; subText layout shift.

#### M2. `TgDialogButton` — `lib/src/buttons/tg_dialog_button.dart`
- **Source:** `ui/ActionBar/AlertDialog.java:1050-1096` + `TextViewWithLoading.java` —
  `spec_primitives.md` §2, `spec_dialog_menu.md` §1.4.
- **Spec:** flat text button 40dp tall, minWidth 64dp, h-padding 12dp, label 16dp w500
  `dialogButton` (0xFF298ACF), **no all-caps**; ripple-only r20 pill at 10% of the label
  color; destructive = `text_RedBold`; disabled alpha 0.5; loading = label↔spinner swap
  320ms EASE_OUT_QUINT (spinner = M0c).
- **Tests:** metrics (40/64/12), no text transform, destructive color, loading swap
  timing, ripple absent at rest (transparent background).

#### M3. `TgAlertDialog` (+ `showTgAlertDialog`, `TgAlertDialogRoute`, `TgDialogItem`) — `lib/src/dialog/tg_alert_dialog.dart`
- **Source:** `ui/ActionBar/AlertDialog.java` (+ `AlertDialogDecor.java`) —
  `spec_dialog_menu.md` §1.
- **Spec:** surface `dialogBackground` r20, width min(356dp, screenW−48dp), barrier
  black 0.5 (fade 150ms; content = pure fade, no scale — window-anim parity); title
  20/500 `dialogTextBlack` (24dp gutters, 19 top/10 bottom), message 16/400 (24dp
  gutters, 20 bottom, links `dialogTextLink`); button row 52dp pad 8 → 40dp buttons
  (M2), positive right-pinned, 8dp gaps, auto vertical stack when combined width >
  screenW−64dp with 6dp spacing; scroll-edge shadows fade 150ms. Items variant:
  48dp rows, 23dp h-padding, 16dp text, 56dp indent with icon, `dialogButtonSelector`
  pressed. Progress variants (LOADING 4dp line + 14dp w500 percent; SPINNER 86dp r18
  card + 32dp radial, pop-in Overshoot(1.3) 190ms) built on M9/M10.
- **Tests:** route pumps open/closed at 150ms; width clamps at 356 and at screenW−48;
  button placement LTR + RTL; vertical-stack fallback triggers on long labels;
  destructive + loading button pass-through; items variant tap → callback + dismiss.

#### M4. `TgPopupMenu` + `TgMenuItem` — `lib/src/menu/tg_popup_menu.dart`, `lib/src/menu/tg_menu_item.dart`
- **Source:** `ui/ActionBar/ActionBarPopupWindow.java` + `ActionBarMenuSubItem.java`
  (+ `ItemOptions.java` conventions) — `spec_dialog_menu.md` §2.
- **Spec:** surface `actionBarDefaultSubmenuBackground` r12 with shadow; open = height
  reveal from top-right pivot, 150+16·n ms, per-item cascade (−6dp slide + fade,
  wavelength 4); dismiss 150ms fade + 5dp slide (or scaleOut 0.8); optional dim 0.2.
  Rows exactly 48dp, 18dp h-padding, 16dp text `actionBarDefaultSubmenuItem`, 24dp icon
  with 43dp text indent, optional 13dp subtext / right icon / check; first/last row
  selector corners r12; separator = 8dp band `actionBarDefaultSubmenuSeparator`.
  Defer: fitItems width equalization, nested swipe-back. Include: scroll when taller
  than screen.
- **Tests:** open duration scales with item count; cascade order (item 0 lands first);
  row height forced 48; indent switches 18→43 with icon; separator height 8; dismiss
  removes overlay; tap fires + closes; disabled row alpha 0.5 and non-tappable.

#### M5. `TgCheckBox` — `lib/src/controls/tg_check_box.dart`
- **Source:** `ui/Components/CheckBoxBase.java` + `CheckBox2.java` (+ `CheckBoxCell.java`
  recipe) — `spec_forms.md` §1.
- **Spec:** size param dp (default 21; picker 24); check stroke 1.9dp round cap/join,
  ring 1.2dp (recipe overrides: settings-arc 1.5dp, avatar-overlay type-3 3dp); single
  progress 0↔1, 200ms EASE_OUT, phase 1 (0–.5) fills annulus from ring inward, phase 2
  (.5–1) draws check arms 9dp/4dp at 45° from anchor (cx−1.5dp, cy+4dp); fill
  `checkbox` (0xff5ec245) / `checkboxDisabled`, check `checkboxCheck` white. Expose the
  three real recipes as named constructors — `TgCheckBox` (plain type 0),
  `.settingsRow` (type 10 + drawBackgroundAsArc), `.avatarOverlay` (type 3, no
  unchecked, ring fade-in) — not all 14 magic ints.
- **Tests:** painter probes at progress 0 / .25 / .5 / .75 / 1 (annulus then check);
  200ms timing; controlled-widget semantics (checkbox a11y, checked state); recipe
  stroke widths; disabled fill color.

#### M6. `TgRadio` (+ `TgRadioCell`) — `lib/src/controls/tg_radio.dart`
- **Source:** `ui/Components/RadioButton.java` + `ui/Cells/RadioCell.java` —
  `spec_forms.md` §2.
- **Spec:** bare default 16dp, cell recipe 20dp in 22×22 box; 2dp STROKE ring; 200ms
  accel-decel; circleProgress = triangle wave — first half fills interior inward, ring
  radius breathes size/2−dp(1+cp), second half collapses to dot r=size/4 while color
  lerps `radioBackground` (0xffb3b3b3) → `radioBackgroundChecked` (0xff229AF0) — raw
  colors in Java, but the port resolves the two keys. End state: ring r=size/2−1dp +
  dot r=size/4. `TgRadioCell`: 50dp row + 1-physical-px divider (20dp inset), text
  16/400, disabled alpha 0.5 whole row, radio a11y.
- **Tests:** triangle-wave midpoint (max breathe, unchecked hue); end-state dot/ring
  radii for 20dp instance (9/5); color flip only in second half; cell height + divider
  physical px; disabled alpha.

#### M7. `TgSlider` — `lib/src/controls/tg_slider.dart`
- **Source:** `ui/Components/SeekBarView.java` — `spec_forms.md` §3.
- **Spec:** 38dp tall; track 3dp r2, inset 16dp each end (selectorWidth 32); thumb
  visible r6→r8 pressed (~120ms linear at 1dp/60ms), travel width−32dp; colors
  `player_progress` fill+thumb / `player_progressBackground` track /
  `player_progressCachedBackground` buffered (port honors the inner-color param — do
  NOT replicate the Java clobber quirk); steps snap via 60ms EASE_OUT AnimatedFloat +
  `HapticFeedback.selectionClick`; animated setProgress = 225ms double-circle swap (old
  collapses easeInQuad·3, new grows easeOutQuad); tap-to-seek; two-sided mode (center
  notch 2×12dp, 2dp fill from center); minProgress 50%-alpha segment. API:
  `value`, `onChanged`, `onChangeEnd`, `buffered`, `minValue`, `stepCount`, `twoSided`,
  `lineWidth`.
- **Tests:** geometry (insets, radii); drag streams onChanged and clamps; tap jumps;
  press radius animates; step snap fires haptic per step (mock HapticFeedback);
  225ms animated jump draws two circles mid-flight; two-sided mapping [−1,1].

#### M8. `TgAvatar` + `TgAvatarColors` — `lib/src/avatar/tg_avatar.dart`
- **Source:** `ui/Components/AvatarDrawable.java` — `spec_primitives.md` §3.
- **Spec:** circle (or rounded-rect) with vertical two-stop gradient; 7 pairs in order
  Red, Orange, Violet, Green, Cyan, Blue, Pink (defaults FF845E→D45246 …
  FF8AAC→D95574, resolved via `avatar_background*`/`avatar_background2*` keys);
  index = abs(id % 7); peer-color hue→index map (≥345|<29 red, <67 orange, <140 green,
  <199 cyan, <234 blue, <301 violet, else pink). Initials: emoji-aware first grapheme
  of firstName + first grapheme of LAST word of lastName (ZWNJ-joined; fallback last
  word of firstName), UPPERCASED; text `avatar_text` white 18dp w500 designed for 50dp,
  canvas-scaled by size/50. Saved pair 69BDF9→409FE1; archived flat B8C2CC. Optional
  `image` provider slot (fills DialogCell/UserCell avatar slots).
- **Tests:** index math incl. negatives; hue map boundary values; initials extraction
  table (emoji, multi-word, empty-first-name promotion, custom override); text scale at
  56dp = 20.16 effective; gradient stops resolve through resources override.

#### M9. `TgRadialProgress` — `lib/src/progress/tg_radial_progress.dart`
- **Source:** `ui/Components/RadialProgressView.java` — `spec_primitives.md` §4.1.
- **Spec:** 40dp default box (dialog uses 32), 3dp round-cap stroke, key
  `progressCircle` (0xff1c93e3); rotation 360°/2s continuous; indeterminate sweep
  alternates 500ms grow 4°+266°·accel / shrink phases with +270° offset jumps
  (oscillates 4°↔270°); determinate sweep = max(4°, 360°·p), progress eased 200ms
  decelerate; `toCircle` morph 220ms in / 400ms out.
- **Tests:** sweep bounds over a full cycle; determinate minimum 4°; size/color params;
  animation ticks without a Material dependency.

#### M10. `TgLinearProgress` — `lib/src/progress/tg_linear_progress.dart`
- **Source:** `ui/Components/LineProgressView.java` — `spec_primitives.md` §4.3.
- **Spec:** rounded bar radius = height/2, canonical 4dp; progress animates 300ms
  decelerate; at 1.0 whole bar fades out 200ms; track drawn only while p<1; dialog
  colors `dialogLineProgress`/`dialogLineProgressBackground`. Shimmer sweep optional —
  skip in v1.
- **Tests:** radius = h/2; 300ms progress ease; completion fade; track visibility.

#### M11. `TgTextField` (+ `TgOutlineContainer`) — `lib/src/input/tg_text_field.dart`, `lib/src/input/tg_outline_container.dart`
- **Source:** `ui/Components/EditTextBoldCursor.java` + `OutlineTextContainerView.java` —
  `spec_primitives.md` §5.
- **Spec:** underline style (default): text 18/400 `windowBackgroundWhiteBlackText`,
  hint `windowBackgroundWhiteHintText` fading 150ms; 1dp line `…InputField`
  (0xffdbdbdb) ~6dp under baseline → focused 2dp `…InputFieldActivated` expanding from
  touch-x, 150ms EASE_BOTH; error snaps 2dp `text_RedRegular`; block cursor 2dp×24dp
  (forms recipe 1.5×20), blink 500/500ms; floating-label mode scales ×0.7 + up 22dp,
  200ms EASE_OUT_QUINT, hint→`windowBackgroundWhiteBlueHeader`. Outlined variant:
  r8 outline, stroke 0.5dp→1.6667dp focused, label floats into a gap cut in the top
  stroke at ×0.75 (14dp left inset, 4dp gaps), color/stroke blends via spring
  (stiffness 500, damping 1), error → `text_RedBold`. Built on `EditableText`
  (widgets-layer, no Material).
- **Tests:** underline thickness/color per state; focus expansion animates from tap x;
  error overrides focus; floating label metrics (0.7/22dp/200ms); outlined gap
  interrupts top stroke while floated; cursor dimensions; controlled via
  TextEditingController.

#### M12. `TgPageRoute` + `TgPageTransitionsBuilder` — `lib/src/navigation/tg_page_route.dart`
- **Source:** `ui/ActionBar/ActionBarLayout.java` — `spec_typography_motion.md` §2.1.
- **Spec:** push = 48dp slide-in + crossfade (NOT full-width), 150ms,
  curve 1−(1−t)^3; page underneath never moves; pop mirrors. Gesture pop: black scrim
  on the back layer up to 37.6% proportional to coverage + 20dp edge-shadow ramp;
  swipe-back commit threshold width/3, commit duration max(200·remaining/width, 50)ms,
  cancel max(320·x/width, 120)ms. Implement as `PageRoute` + a
  `PageTransitionsBuilder` so apps can install it theme-wide.
- **Tests:** transition duration 150ms; incoming offset 48→0 with fade; secondary
  route static during push; scrim opacity vs drag fraction; commit/cancel duration
  formulas; back-gesture threshold.

### 1.2 SHOULD wave (audited, native source verified; spec inline from Java at build time)

#### S1. `TgHint` — `lib/src/hint/tg_hint.dart`
- **Source:** `ui/Stories/recorder/HintView2.java` (modern; `Tooltip.java`/`HintView.java` legacy).
- **Spec:** rounded bubble + arrow anchored to a target; auto-hide with duration;
  multiline text 14dp; extract paddings/radius/arrow metrics + show/hide scale-fade
  timings from HintView2 during build (cite lines).
- **Tests:** anchor placement above/below; auto-hide timer; show/hide animation runs;
  text style/colors via keys.

#### S2. `TgFlickerLoading` — `lib/src/loading/tg_flicker_loading.dart`
- **Source:** `ui/Components/FlickerLoadingView.java` + `LoadingDrawable.java`.
- **Spec:** skeleton placeholder rows (dialog-cell and user-cell shapes first) with a
  moving highlight gradient sweep; row geometry mirrors DialogCell/UserCell metrics;
  sweep period + gradient alphas cited from Java at build time.
- **Tests:** row shapes for the two list types; sweep animates continuously; respects
  theme background keys.

#### S3. `TgEmptyView` — `lib/src/empty/tg_empty_view.dart`
- **Source:** `ui/Components/StickerEmptyView.java`, `EmptyTextProgressView.java`.
- **Spec:** centered column — image/lottie slot, title (bodyEmphasis), subtitle
  (subtitle role), optional button (TgButton text mode); progress↔content crossfade as
  in StickerEmptyView; metrics cited at build time.
- **Tests:** loading↔content swap; slots render; style roles from TgTextStyles.

#### S4. `TgChip` — `lib/src/chips/tg_chip.dart`
- **Source:** `ui/Components/GroupCreateSpan.java` (input chip: avatar + name + delete
  morph); `ui/Adapters/FiltersView.java` (filter chip) as variant reference.
- **Spec:** 32dp pill, leading 32dp avatar (TgAvatar), name 14dp, tap toggles
  avatar↔delete-icon crossfade, selected tint `avatar_backgroundBlue`-family keys;
  exact radii/paddings/anim cited from GroupCreateSpan at build time.
- **Tests:** delete-state toggle animation; onDeleted callback; avatar slot; colors.

#### S5. `TgFab` — `lib/src/buttons/tg_fab.dart`
- **Source:** `ui/Components/FragmentFloatingButton.java`.
- **Spec:** 56dp circular glass/filled button, `chats_actionBackground` /
  `chats_actionIcon` keys, press scale per ScaleStateListAnimator, show/hide
  slide+scale; constants cited at build time.
- **Tests:** size, key resolution, press scale, show/hide animation.

#### S6. Bulletin undo variant — edits `lib/src/components/bulletin/bulletin.dart` (existing file)
- **Source:** `ui/Components/UndoView.java` countdown recipe, expressed as a Bulletin
  layout variant (per kit-lens audit #19), not a new component.
- **Spec:** leading countdown circle (seconds text inside a depleting 2dp ring) +
  "Undo" trailing action; auto-dismiss when the ring empties; constants cited from
  UndoView at build time.
- **Tests:** countdown ticks; undo callback cancels dismiss; existing bulletin tests
  stay green (this agent owns the whole file).

#### S7. `TgSlideChooser` — `lib/src/controls/tg_slide_chooser.dart`
- **Source:** `ui/Components/SlideChooseView.java` (discrete labeled slider —
  settings "message size" control).
- **Spec:** discrete dots + labels over a slider track, moving label emphasis;
  reuses TgSlider step machinery where possible; constants cited at build time.
- **Tests:** option snap, label highlight follows value, callback per stop.

### 1.3 Blanket test contract (every component)

1. Constants test: each `kXxx` asserted against the spec number.
2. Theme test: default key resolution via `TelegramTheme.colorOf` + a
   `TelegramResources` override that flips the color (both directions).
3. Animation test: durations/curves observed with `tester.pump(partial)` frames — no
   golden files (flutter_tester cannot render the liquid tier).
4. Semantics test where interactive (button/checkbox/radio/slider/textfield roles).
5. No `package:flutter/material.dart` import (widgets layer only; enforced by a grep in
   the integration pass). `flutter analyze` clean, zero new warnings.

---

## 2. API conventions (carried over — non-negotiable)

These are the existing package conventions; every new file follows them (see
`header_cell.dart` as the reference exemplar):

1. **`resources` param.** Every component takes an optional
   `TelegramResources? resources` that wins over the ambient theme — the Java
   `resourcesProvider` convention. Otherwise keys resolve through
   **`TelegramTheme.colorOf(context, key)`** for per-key rebuild granularity. Never
   `Theme.of`, never hardcoded colors (where Java hardcodes raw ints — RadioButton —
   resolve the equivalent keys and document the divergence).
2. **Logical px = dp.** 1 Android dp maps 1:1 to a Flutter logical pixel. Hairlines are
   **1 physical px** (`1 / MediaQuery.devicePixelRatioOf(context)`), per
   `Theme.dividerPaint` (`Theme.java:3089`) — the `dialog_cell.dart` separator is the
   precedent.
3. **Doc-comment citations.** Every constant is a `const kXxx` with a doc comment citing
   `File.java:line`; each file opens with a `// Port of ui/....java` header block noting
   what is deliberately NOT ported. Class doc comments summarize the recipe with key
   numbers.
4. **Theme keys** come from the generated `theme_keys.g.dart` (`ThemeKeys.*` ints);
   defaults live in the generated palettes — never re-declare color values in
   components.
5. **Typography:** "bold" = `FontWeight.w500` + family `RobotoMedium` (bundled
   `rmedium.ttf`); w700 is forbidden. After M0 lands, components consume `TgTextStyles`
   roles instead of hand-rolled sizes.
6. **Curves** come from `TgCurves`/`TgMotion` (foundation) — no inline `Cubic(...)`
   literals in components.
7. **Controlled widgets.** State in, callbacks out (TgSwitch precedent): `TgCheckBox`
   takes `checked` + `onChanged`; programmatic changes animate; no internal
   toggle-state ownership.
8. **Widgets layer only** — `package:flutter/widgets.dart` (+ services for haptics/
   clipboard); the sole Material import in the package stays in `telegram_theme.dart`.
9. **Exports:** components do NOT touch `lib/telegram_ui.dart`; the integration task
   adds all exports at once (avoids the one genuinely shared file).

---

## 3. Parallel build breakdown (file-scoped agents)

Rule: **no two agents may write the same file.** Dependencies flow strictly
wave→wave; within a wave, agents depend only on prior-wave + existing package code.
Each agent also owns the mirrored `test/` files for its `lib/` files.

### Wave 0 — foundation (ONE agent, blocks everything)
**Agent A0** — files: `lib/src/foundation/tg_text_styles.dart`,
`lib/src/foundation/tg_motion.dart`, `lib/src/foundation/tg_curves.dart` (additions),
`lib/src/progress/tg_circular_progress.dart`;
tests: `test/foundation/tg_text_styles_test.dart`, `test/foundation/tg_motion_test.dart`,
`test/progress/tg_circular_progress_test.dart`.
Delivers M0, M0b, M0c. Nothing else starts until A0 is green.

### Wave 1 — MUST components (7 agents in parallel)
| Agent | Components | Files owned (lib + mirrored test) |
|---|---|---|
| B1 | M1 TgButton, S5 TgFab | `buttons/tg_button.dart`, `buttons/tg_fab.dart` |
| B2 | M2 TgDialogButton, M3 TgAlertDialog | `buttons/tg_dialog_button.dart`, `dialog/tg_alert_dialog.dart` (bundled: the dialog consumes the button — same agent so the dependency never crosses agents) |
| B3 | M4 TgPopupMenu + TgMenuItem | `menu/tg_popup_menu.dart`, `menu/tg_menu_item.dart` |
| B4 | M5 TgCheckBox, M6 TgRadio, M7 TgSlider (+S7 TgSlideChooser stretch) | `controls/tg_check_box.dart`, `controls/tg_radio.dart`, `controls/tg_slider.dart`, `controls/tg_slide_chooser.dart` |
| B5 | M8 TgAvatar, M9 TgRadialProgress, M10 TgLinearProgress | `avatar/tg_avatar.dart`, `progress/tg_radial_progress.dart`, `progress/tg_linear_progress.dart` (note: does NOT touch `tg_circular_progress.dart` — A0 owns it) |
| B6 | M11 TgTextField + TgOutlineContainer | `input/tg_text_field.dart`, `input/tg_outline_container.dart` |
| B7 | M12 TgPageRoute | `navigation/tg_page_route.dart` |

Cross-agent notes: B2's SPINNER/LOADING dialog variants depend on M9/M10 (B5) — B2
builds the message+items+buttons dialog first and lands the progress variants in a
follow-up commit of the same files once B5 is green (or wave-2 polish). B4's slider and
B2's dialog both consume TgMotion curves from A0 only. Nobody edits existing component
files in wave 1.

### Wave 2 — SHOULD components (4 agents in parallel)
| Agent | Components | Files owned |
|---|---|---|
| C1 | S1 TgHint | `hint/tg_hint.dart` |
| C2 | S2 TgFlickerLoading, S3 TgEmptyView | `loading/tg_flicker_loading.dart`, `empty/tg_empty_view.dart` (may consume TgButton/TgRadialProgress from wave 1) |
| C3 | S4 TgChip | `chips/tg_chip.dart` (consumes TgAvatar) |
| C4 | S6 Bulletin undo variant | `components/bulletin/bulletin.dart` — sole owner of this existing file for the whole build |

### Wave 3 — integration (ONE agent; see §4)

---

## 4. Integration tasks (single agent, after wave 2)

1. **Umbrella exports:** add every new file to `lib/telegram_ui.dart` under a
   `// Components` (and `// Foundation`) section, alphabetized per directory, matching
   the existing grouping.
2. **Example gallery:** new page `example/lib/pages/widgets_demo.dart` registered in
   `example/lib/main.dart` — a scrolling showcase with a `HeaderCell` per section:
   Buttons (filled/text/neutral/counter/loading/disabled/FAB), Dialogs (message /
   destructive / items / loading buttons — launch buttons), Menu (anchored overflow
   demo), Form controls (checkbox recipes, radio group, sliders incl. steps/two-sided,
   slide chooser), Avatars (7 gradient pairs + initials edge cases + saved/archived),
   Progress (radial ind/det, linear, in-button), Text fields (underline / floating
   label / outlined / error), Empty + skeleton states, Hints, Chips, Undo bulletin —
   **every new control appears at least once**. Navigation demo: push a detail page via
   `TgPageRoute`. Replace the example's local `widgets/gradient_avatar.dart` usage with
   `TgAvatar` where it fits.
3. **Docs:** update `flutter/docs/STATUS.md` (component table + test counts + this
   plan's completion state); note new directories in `ARCHITECTURE.md` §6 catalog table.
4. **Quality gates:** `flutter analyze` clean; full `flutter test` (package + example +
   lottie) green; grep-gate: no `material.dart` imports outside `telegram_theme.dart`;
   spot-check every exported symbol has a doc comment with citations.

---

## 5. Out of scope (explicitly skipped)

Per the kit-lens audit — invent nothing without a Telegram-native source; defer
app-specific machinery:

- **Pull-to-refresh** — Telegram lists never pull-to-refresh; the archive pull
  (`PullForegroundDrawable.java`) is not a refresh control. No source → skip.
- **iOS-style segmented control** — no native equivalent; `GlassTabBar` fills the role.
- **Date/time/calendar pickers** — native source exists (`AlertsCreator.java:3854/4045/
  6405` on `NumberPicker.java`) but is a large dependency chain; deferred to a future
  wave together with a standalone `TgNumberPicker`. Not in this build.
- **Nav drawer** (`DrawerLayoutContainer.java`) — only needed for full Telegram-shell
  replication, not a general kit.
- **Reactions strip** (`ReactionsContainerLayout.java`) — chat-message-specific; needs
  a message roadmap first.
- **Rating bar** (`BetterRatingView.java`) — call-rating only.
- **Animated text/number roll** (`AnimatedTextView.java`) — CounterBadge and TgButton's
  counter cover the real uses; standalone port deferred (TgButton may inline a minimal
  digit-roll painter, scoped to its own file).
- **Persistent top banner** (`FragmentContextView.java`) — music/call return chrome,
  app-specific.
- **Dialog niceties deferred:** blurred-background dialog mode, `AlertDialogDecor`
  in-tree attachment, popup `fitItems` width equalization, nested swipe-back submenus,
  slider timestamp/chapter machinery, TgLinearProgress shimmer, text-field animated
  hint-swap — all noted in specs as NICE; skip in this build.

---

## 6. Definition of done

All MUST components exported, cited, tested per §1.3; SHOULD components landed or
explicitly re-triaged in STATUS.md; `widgets_demo` shows every new control; full test
suite green (baseline 757+2+8 strictly increased); no shared-file conflicts occurred
(verifiable: one owner per file in git history for this build).
