# Telegram Android → Flutter port: Attach sheet + Emoji panel spec

Extracted from Java sources for a faithful port. All paths relative to
`/home/user/Telegram/TMessagesProj/src/main/java/org/telegram/` unless noted.

Sources cited below:
- **CAA** = `ui/Components/ChatAttachAlert.java`
- **CAPL** = `ui/Components/ChatAttachAlertPhotoLayout.java` (header/action-bar metrics only)
- **GTV** = `ui/Components/glass/GlassTabView.java`
- **BPI** = `ui/Components/blur3/drawable/color/impl/BlurredBackgroundProviderImpl.java`
- **EV** = `ui/Components/EmojiView.java`
- **ETS** = `ui/Components/EmojiTabsStrip.java`
- **PSTS** = `ui/Components/PagerSlidingTabStrip.java`
- **CAEV** = `ui/Components/ChatActivityEnterView.java`
- **BS** = `ui/ActionBar/BottomSheet.java`
- **AB** = `ui/ActionBar/ActionBar.java`
- **T** = `ui/ActionBar/Theme.java`, **TC** = `ui/ActionBar/ThemeColors.java`
- **SSNC** = `ui/Cells/StickerSetNameCell.java`

Units: 1 Android dp = 1 Flutter logical px. Curves (already in `TgCurves`):
`EASE_OUT_QUINT`=(.23,1,.32,1), `EASE_OUT`=(0,0,.58,1), `EASE_IN`=(.42,0,1,1),
`EASE_BOTH`=(.42,0,.58,1), `DEFAULT`=(.25,.1,.25,1). `AndroidUtilities.bold()` =
Roboto Medium. Roboto **extra-bold** is used for selected attach-tab labels
(GTV:237). "Glass alpha" everywhere = **0.85** when `LiteMode.FLAG_LIQUID_GLASS`
is on, **0.76** otherwise (BPI:22 et al.).

Content pipelines (photo gallery, sticker sets, GIF search, attach-menu bots)
are **slot/provider parameters** in the Flutter port — never implemented here.

> **Important — this is the liquid-glass redesign.** The classic
> `chat_attachAlert*`/circle-icon attach buttons are **gone**: `grep attachAlert`
> color keys in CAA returns nothing. Attach buttons are now `GlassTabView`
> pills over a floating glass tab bar, identical in construction to the main
> bottom tab bar (`GlassPresets.mainTabs`, already ported).

---

## Part A — Attach sheet (`ChatAttachAlert`)

### A1. Sheet chrome & corner radius

- Base class `BottomSheet`; `occupyNavigationBarWithoutKeyboard = true` (CAA:1267).
- Sheet background/shadow = `R.drawable.sheet_shadow_round` 9-patch (BS:1194) —
  **12dp top corner radius** baked into the asset; drawn per-layout behind each
  `AttachAlertLayout` (CAA:1857-1859, 1976-1978), tinted to
  `getActionBarDrawableColor()` or the layout's `getCustomBackground()`
  (CAA:1853-1856).
- Dynamic corner flattening: `cornerRadius = 1.0f - moveProgress` as the sheet
  top scrolls under the action bar (CAA:5570); the explicit
  `drawRoundRect(rect, dp(12)*rad, ...)` calls are **commented out** in the glass
  build (CAA:1866, 1876, 1985, 2007) — only the 9-patch remains. Port: 12dp top
  radius, collapse to 0 as content docks under the app bar.
- Scroll handle (grabber): **36×4dp**, corner radius **2dp**, color
  `key_sheet_scrollUp` (0x20000000 when `actionBarType == 2`), centered, at
  `y = top + 20dp`; alpha = `(1 - headerAlpha) * rad` (CAA:1893-1913, 2011-2027).
- Keyboard-height panning via `AdjustPanLayoutHelper`; action bar/menu items
  follow `currentPanTranslationY` (CAA:1367-1419).

### A2. Action-button row — the layout switcher (bottom glass tab bar)

One row serves both purposes: it *is* the layout switcher (Gallery / File /
Location / Music / Poll / Contact / bots), selection state = current layout.

Container:
- `buttonsRecyclerViewWrapper`: **MATCH_PARENT × 70dp**, gravity bottom-center
  (CAA:2735). For the poll-attach variant, width shrinks to
  `bitCount(allowedLayouts) * 80dp + 36dp` (CAA:2577-2580).
- Glass background: `iBlur3FactoryLiquidGlass.create(...,
  BlurredBackgroundProviderImpl.mainTabs(...))` with **radius 28dp** (`56/2`) and
  **glass padding 7dp** (CAA:2725-2728) — exactly `GlassPresets.mainTabs`
  (BPI:19-33: bg = solve(windowBackgroundWhite → glass_targetMainTabs, glass
  alpha); strokes top 0x11000000/0x06FFFFFF, bottom 0x20000000/0x11FFFFFF, width
  0.4dp; shadow 0x20000000/0x04FFFFFF blur 2.667dp dy 0.85dp).
- Inner `RecyclerView` (horizontal): padding **11dp** all sides, clipped to a
  rounded outline radius 28dp inset by 11dp (CAA:2729-2731). Content height =
  70 − 22 = **48dp** per tab.
- Horizontal edge fades when content overflows: 8dp `LinearGradient` masks
  (DST_IN) at each end, animated in/out with `BoolAnimator` 320ms
  `EASE_OUT_QUINT`; children are clipped to `[19dp, width−19dp]` while a fade is
  active, fade band drawn between 11dp and 19dp (CAA:2592-2658).
- Legacy `attachItemSize = dp(85)` still declared (CAA:1120) but tabs now
  self-measure (below).

Tab widths (self-measure, CAA:2661-2684 + GTV:485-489, 505-513):
- natural width = `min(84dp, textWidth + 2*padding)` where
  `padding = lerp(16dp, 8dp, clamp((textWidth − 40dp)/16dp, 0, 1))`;
- if the row underfills the viewport, the leftover is split equally and added to
  every tab (`setAdditionalWidth`).

Tab anatomy (`GlassTabView.createAttachTab`, GTV:441-454; base ctor GTV:80-104):
- icon: **24×24dp** RLottie animation, top margin 4dp, centered horizontally
  (GTV:448); icon set = `TabAnimation` enum pairs `tab_*` / `tab_*_reverse`
  (GALLERY, FILES, LOCATION, MUSIC, POLL, CHECKLIST, GIFT… GTV:545-569).
  Port contract: `TabIcon`/`TabAnimationController` (components/tabs/tab_icon.dart).
- label: **11dp**, Roboto Medium (bold()); horizontal text padding 8dp; single
  line, ellipsized; top margin **28.33dp**; when selected the typeface switches
  to Roboto **extra-bold** (GTV:445-446, 96, 237).
- selection pill: color `key_glass_tabSelected` at **9% alpha** × decelerate(alpha),
  full tab bounds, radius `min(w,h)/2`, scaled `lerp(0.6, 1, selectedFactor)`
  about center (GTV:154-165).
- color animation: icon/label tint blends `key_glass_tabUnselected` →
  `key_glass_tabSelected` / `key_glass_tabSelectedText` (GTV:254-265) driven by
  a `BoolAnimator` **320ms decelerate** (GTV:67); lottie icon plays
  outline→filled (forward) or reverse on deselect (GTV:319-397).
- bot tabs (`createAttachBotTab`, GTV:456-471): image 24×24 (bot icon,
  tinted like a normal tab) or user avatar 22×22 with 11.33dp round radius at
  top 5dp (GTV:641-667).

Color keys (defaults TC:822-828, fallbacks T:4482-4488):

| key | default (day) | fallback |
|---|---|---|
| `glass_tabUnselected` | `0xFF1A1D21` | `windowBackgroundWhiteBlackText` |
| `glass_tabSelected` | `0xFF1A91E6` | `chat_messagePanelSend` |
| `glass_tabSelectedText` | `0xFF0D7FCF` | `chat_messagePanelSend` |
| `glass_targetMainTabs` | `0xFFFFFFFF` | `dialogBackground` |
| `glass_defaultIcon` | `0x991B2227` | `chat_messagePanelIcons` |

Per-tab counter badge (used e.g. for selected-count on a tab; GTV:167-227):
- pill height **16dp**, width `max(16dp, counterTextWidth + 8dp)`; center at
  `(tabCenterX + 11dp, 10dp)`;
- punch-out ring: outer round-rect inflated by **1.33dp** drawn with
  `Theme.PAINT_CLEAR` (radius 9.333dp), inner pill radius **8dp**;
- fill = blend(`key_telegram_color` → `key_fill_RedNormal`, errorFactor); text
  **10dp** bold white;
- appear/disappear + error blend: `BoolAnimator` **380ms EASE_OUT_QUINT**
  (GTV:68-69); premium variant draws the premium gradient + 14dp star
  (GTV:196-206).

Bottom fade under the bar: `BlurredBackgroundWithFadeDrawable` over the fade
factory, fade height **72dp**, bounds from `height − navBarHeight − 48dp` to
bottom (CAA:2703-2721). A `ChatActivityFadeView` adds 48dp top and 48dp bottom
content fades; top fade zone = statusBar + actionBarHeight + 5dp
(CAA:2525-2530); bottom fade disabled for layouts with `disableBottomFade()`
(CAA:4560-4566).

### A3. Header & glass action bar

Action bar (CAA:2177-2220):
- standard `ActionBar`, `occupyStatusBar = true`, initial alpha **0** (appears
  only when a layout scrolls to top); items & title color `key_dialogTextBlack`,
  item ripple `key_dialogButtonSelector`; forced menu width 46dp (CAA:2213).
- Glass treatment: `actionBar.setupGlass(iBlur3FactoryLiquidGlass,
  BlurredBackgroundProviderImpl.attachMenuActionBar(...))` (CAA:4075). In
  `setupGlass` (AB:213-252): background nulled; three glass pill drawables
  (title area, back button, menu) each **radius 23dp**, **glass padding 6dp**;
  menu translated −10dp, back icon +2dp. Forum variant radius (18.33, 23, 23,
  18.33) — not used here.
- `attachMenuActionBar` recipe (BPI:157-171), already ported as
  `GlassPresets.attachMenuActionBar`:
  - bg = `solveSrcColor(isDark ? windowBackgroundGray : dialogBackgroundGray →
    windowBackgroundWhite, glass alpha)`;
  - stroke top `0xFFFFFFFF` light / `0x28FFFFFF` dark, bottom `0xFFFFFFFF` /
    `0x14FFFFFF`; stroke width **1dp** light / **0.667dp** dark;
  - shadow color `0x20000000` / transparent, no shadow layer.
- Show/hide: alpha (+ search/menu item alpha & scale 0.6→1) animated **380ms
  EASE_OUT_QUINT** (CAA:5695-5736); tracked also by `animatorActionBarVisible`
  (`BoolAnimator` 380ms EASE_OUT_QUINT, CAA:213-226 family).

Floating header (visible while sheet is partially scrolled):
- `headerView` frame at left 23 / right 21 (CAA:2534); `selectedTextView`
  ("Gallery" / "N media selected") **16dp bold**, `key_dialogTextBlack`
  (CAA:2477-2481); mediaPreview title same 16dp bold with `attach_arrow_left`
  icon (CAA:2500-2514). Header translates with scroll:
  `scrollOffset − dp(25 + finalMove*moveProgress)`, finalMove = 12 portrait /
  6 landscape / 16 tablet (CAA:5572-5605); cross-fades against the action bar
  (`selectedTextView.alpha = 1 − actionBar.alpha`, CAA:2189-2191).
- Photo layout drop-down (CAPL:741-769): `dropDownContainer` added into the
  action bar at left margin 60, below status bar; `dropDown` TextView **17dp**
  bold (CAPL:4035), color `key_dialogTextBlack`, right padding 10dp, inner left
  margin 16dp, `ic_arrow_drop_down` suffix; opens album sub-menu.
- Top-right items: `selectedMenuItem` (⋮) 48×48 (translationX +1dp),
  `motionItem` 48×48 at right 48, `searchItem` 48×48 (CAA:2559-2563); shown at
  `ActionBar.height − 3dp − dp(37+finalMove)` when docked (CAA:5583-5602).
- `doneItem` ("Create", polls/todo): text **14dp bold**
  `key_featuredStickers_buttonText` over a rounded pill drawn ±14dp around
  vertical center → **28dp tall, radius 14dp**, fill
  `key_featuredStickers_addButton`, text padding 12dp, container height 48
  top-right (CAA:2272-2297, 2567).
- Caption bar (adjacent, for completeness): glass pill radius **22dp**, glass
  padding 7dp, content padding (7,5,7,5), preset `inputFieldDialogActivity`
  (= `topPanel`) (CAA:3038-3041); in-sheet emoji keyboard background = frosted
  factory, radius 29dp top corners, **thickness 32dp**, **intensity 0.4**
  (CAA:3032-3036).

### A4. Open / close / layout-switch animation

Open (`onCustomOpenAnimation`, CAA:5249-5298):
- container slides from full height to 0 with a **SpringAnimation: damping 0.75,
  stiffness 350** (CAA:5278-5286).
- dim (`backDrawable`) animates over **400ms, startDelay 20ms**, interpolator
  `OvershootInterpolator(0.7)` (CAA:5292-5298; openInterpolator CAA:1344).
- attach-tab cascade (CAA:5189-5228, 5257-5262): a master clock runs 0→400
  (400ms, delay 20ms). Each tab `a` starts at `32*(3−a)` ms; then over 200ms
  scale 0→**1.1** with `EASE_OUT` while alpha 0→1 with `EASE_BOTH`; then 100ms
  settle 1.1→1.0 with `EASE_IN`. Applied via `glassTabView.setAttachScale`
  (scales icon/label and the selection pill, GTV:491-503).

Close: default `BottomSheet` dismissal — containerView translationY to
`containerHeight + keyboard + 10dp + navBarInset` together with dim→0 over
**250ms EASE_OUT** (BS:2014-2033).

Layout switch (`showLayout`, CAA:4587-4652):
- outgoing layout: **180ms `DEFAULT`** — translationY → +78dp (+ scroll delta
  `t`), cross-fade via `ATTACH_ALERT_LAYOUT_TRANSLATION` 0→1, action bar
  alpha→0 (CAA:4605-4615).
- incoming layout: starts at alpha 0 / +78dp, then **SpringAnimation damping
  0.75, stiffness 500** to 0 (CAA:4606-4641).
- photo ⇄ photo-preview switch is horizontal: full-width translateX, spring
  `FloatValueHolder` 0→500, **stiffness 1000, damping 1.0**, header/media-preview
  labels cross-slide ±16dp (CAA:4654-4709).
- selected tab pills update immediately (`updateCheckedState(true)` → 320ms
  decelerate, CAA:4547-4557).

### A5. Send button & selected-count badge

- `writeButtonContainer` **110×50dp**, bottom-right; hidden state alpha 0,
  scale 0.2 (CAA:3503-3527); shown when selection starts (comments animator
  180ms, CAA:4999, 5103).
- `writeButton` = `ChatActivityEnterView.SendButton` with `send_plane_24` icon:
  `setCircleSize(dp(52), dp(38))` → pill **52dp wide × 38dp tall**;
  `setCirclePadding(dp(7), dp(6))`; `newCounterPos = true` (CAA:3556-3560);
  glass-era `blurredBackgroundDrawable` bounds inset −7dp (CAEV:15107-15112).
- count badge drawn by SendButton (CAEV:15166-15189):
  - size `sz = max(18dp, 9dp + counterTextWidth)` circle;
  - position (`newCounterPos`): `cx = pillRight − 50dp (+ width offset)`,
    `cy = pillTop + sz/2`, baseline nudge 0.66dp;
  - **punch-out**: clear circle radius `sz/2 + 2dp` (`Theme.PAINT_CLEAR`) behind
    a filled circle radius `sz/2` in the send-button background color; count
    text = `AnimatedTextDrawable`, scale-bounce on change (`countBounceScale`).
- Legacy `selectedCountView` (**not attached** — `addView` commented,
  CAA:4037-4061): 42×24dp; outer round-rect r12 `key_dialogBackground` (2dp
  border effect), inner r10 `key_chat_attachCheckBoxBackground`, text 12dp bold
  `key_dialogRoundCheckBoxCheck` (alpha 0.58→1.0 with enable progress). Keep
  only as a reference; port the SendButton badge.

---

## Part B — Emoji panel (`EmojiView`)

### B1. Panel height rules

- EmojiView's height is imposed by the chat screen, not self-measured:
  `height = keyboardHeight` where `keyboardHeight` = last measured IME height,
  persisted as `kbd_height` (default **200dp**; landscape `kbd_height_land3`,
  also 200dp default), minus any bottom-tabs height of the nav layout
  (CAEV:12597-12621, 3510-3512). Flutter port: panel height parameter, default
  200 logical px, caller passes real IME height.
- Nav-bar inset handling: `setBottomInset(h)` adds `44dp + inset` bottom padding
  to all three grids and translates the bottom tab strip (EV:2956-2972,
  4448-4453); a bottom gradient fade of the panel background color covers the
  navbar zone (EV:4552-4560).

### B2. Structure

`ViewPager` with up to 3 pages — **0 emoji, 1 GIFs, 2 stickers** (EV:196,
2810) — plus per-page `SearchField`, per-page category strip, a shared
`bottomTabContainer`, and two bulletin containers (100dp tall, bottom offsets
40dp/64dp, EV:2663-2670).

### B3. Bottom tab strip (emoji / GIF / sticker switcher)

- `bottomTabContainer`: MATCH_PARENT × **48dp**, gravity bottom (EV:2678);
  legacy opaque strip `bottomTabContainerBackground` 40dp tall
  (`key_chat_emojiPanelBackground`, EV:2674-2675, 5813) — hidden in glass mode
  (`hideBottomTabContainerBackground`, EV:2917-2921).
- Without search (`needSearch=false`): container shrinks to 56×48 holding only
  the backspace round button, background = 56dp circle of
  `key_chat_emojiPanelBackground` (EV:2798-2807).
- `typeTabs` (`PagerSlidingTabStrip`): centered, WRAP × 48dp; not expanded;
  own padding **(4, 11, 4, 11)** → 26dp inner height; per-tab horizontal
  padding **11dp**; `underlineHeight 0`; `indicatorHeight 3` (used only as a
  non-zero flag — see indicator geometry below) (EV:2697-2705).
- Tab icons: `smiles_tab_smiles` / `smiles_tab_gif` / `smiles_tab_stickers`
  selector drawables — unselected `glass_defaultIcon@40%` (glass) else
  `key_chat_emojiPanelBackspace`; selected `glass_defaultIcon@80%` else
  `key_chat_emojiPanelIconSelected` (EV:1583-1585; re-themed EV:5903-5904 with
  `key_chat_emojiBottomPanelIcon` as the non-glass unselected key).
- Selected indicator: **pill behind the active tab**, spanning the strip's inner
  height (paddingTop→height−paddingBottom) and the tab content width **+11dp on
  each side**, radius = height/2; color `key_chat_emojiPanelIconSelected` at
  alpha **20/255** (EV:2701, PSTS:295-300). Position/width animate between tabs
  with `AnimatedFloat` **350ms EASE_OUT_QUINT** (PSTS:249-250), and track finger
  drags proportionally during pager scroll (PSTS:273-289).
- Glass backgrounds (EV:2923-2951): `typeTabs`, `backspaceButton`,
  `searchButton`, `stickerSettingsButton` each get a factory drawable with
  `emojiViewButton` provider, **radius 18dp**, **glass padding 6dp** — already
  ported as `GlassPresets.emojiViewButton` (BPI:51-64: bg =
  windowBackgroundWhite × glass alpha; strokes `0xFFFFFFFF`/`0x28FFFFFF` top,
  `0xFFFFFFFF`/`0x14FFFFFF` bottom, width 0.5dp; shadow `0x40000000` light only,
  blur 3.667dp, dy 0.667dp).
- Side buttons: backspace 48×48 bottom-right margin 2 (EV:2679); sticker
  settings 48×48 same slot, page 2 only (EV:2689, 2745); search button 48×48
  bottom-left margin 2, hidden by default (EV:2769-2776). Icon tint
  `glass_defaultIcon@60%` (glass) else `key_chat_emojiPanelBackspace`
  (EV:2651, 2684, 2771). All get `ScaleStateListAnimator` press-scale.
- Show/hide on scroll/search: `bottomTabVisibility` `BoolAnimator` **380ms
  EASE_OUT_QUINT** interpolating translationY between hidden
  (`+45dp` with search rows / `+50dp` without) and shown (`−bottomInset`)
  (EV:5135-5148, 4448-4456).

### B4. Category strips

Emoji page — `EmojiTabsStrip` (recent + 8 categories + emoji packs):
- container height **36dp** (EV:1965) with a shadow line
  (`key_chat_emojiPanelShadowLine`) pinned at y = 36 (EV:1967-1973); scrolls
  away with the grid (translationY clamped to −36, EV:5186-5207).
- tab buttons **30×30dp** (ETS:1237); content padding left/right **11dp**
  (`5+6`, ETS:647-655); leftover width distributed as equal margins
  (ETS:196).
- selection pill: radius **8dp**, or **height/2** in glass design (ETS:268-272);
  color = `glass_defaultIcon@5%` (glass) else `chat_emojiPanelIcon@18%`
  (accent@9% for reply-icon pickers) (ETS:743-752).
- selection move: `ValueAnimator` **350ms EASE_OUT_QUINT** sliding the pill
  between tab bounds with a mid-flight squash — width ×(1 + 0.3·isMiddle),
  height ×(1 − 0.05·isMiddle) where `isMiddle = 4t(1−t)` (ETS:702-711,
  255-259). Pill fade in/out: `AnimatedFloat` 350ms EOQ (ETS:246-249).
- emoji-pack subtabs expand from a 30dp button to a multi-icon strip
  (lerp 30dp→maxWidth, ETS:1453-1456) clipped by a 15dp-radius circle
  (ETS:284-286).

Sticker page — `ScrollSlidingTabStrip` (`Type.TAB`, draggable):
- height **36dp** (EV:2510-2513), hosted in `stickersTabContainer` overlay that
  paints `key_chat_emojiPanelBackground` behind it (EV:2483-2511);
- indicator color `key_chat_emojiPanelStickerPackSelectorLine`, underline
  `key_chat_emojiPanelShadowLine`, underline shown only when the grid can
  scroll up (EV:2478-2481);
- scrolls away with content: `tabsMinusDy` clamped to −(48×6)dp, strip
  translationY clamped to −48dp (EV:5166-5176); snap animation **200ms**
  (EV:5204-5208); slides up 50dp when search opens (EV:4463, 4474).

GIF page — same `ScrollSlidingTabStrip` styling: indicator
`chat_emojiPanelStickerPackSelectorLine`, underline `chat_emojiPanelShadowLine`,
background `chat_emojiPanelBackground` (EV:2128-2133); tabs = recent /
trending + emoji-keyed GIF sections.

### B5. Search field row (one per page)

`searchFieldHeight = 50dp` (EV:1579); the row = `SearchField` (EV:796-1010):
- `backgroundView` MATCH × 50dp `key_chat_emojiPanelBackground` (when
  `shouldDrawBackground`), bottom shadow line `key_chat_emojiPanelShadowLine`
  (EV:800-809); field container added MATCH × (50 + shadow) (EV:1942).
- `box`: MATCH × **36dp**, corner radius **18dp**, margins left/right 10dp,
  top 6dp (8dp for sticker-type), bottom 8dp; fill = `glass_defaultIcon@6%`
  (glass) else `key_chat_emojiSearchBackground`; clipped to outline
  (EV:811-819).
- search icon: 36×36 at left, `SearchStateDrawable` (search⇄back⇄progress),
  color `glass_defaultIcon@40%` (glass) else `key_chat_emojiSearchIcon`
  (EV:845-868).
- input: `EditTextBoldCursor` **16dp**, in a 40dp-tall input box inset left
  38dp / right 28dp; hint "Search", hint color `glass_defaultIcon@45%` (glass)
  else `key_chat_emojiSearchIcon`; text color `glass_defaultIcon@80%` (glass)
  else `key_windowBackgroundWhiteBlackText`; cursor
  `key_featuredStickers_addedIcon`, size 20dp, width 1.5; translationY −2dp
  (EV:870-901).
- clear button: 36×36 at right, `CloseProgressDrawable2` (7dp side),
  `key_chat_emojiSearchIcon`, circular ripple `key_listSelector` r15
  (EV:937-963).
- category mini-strip: `StickerCategoriesListView` rendered inside the box to
  the right of the hint (`setDontOccupyWidth(hintWidth + 16dp)`); background
  `blendOver(emojiPanelBackground, emojiSearchBackground)`; scrolling it
  translates the edit text left and enables an 18dp left DST_OUT fade
  (EV:826-841, 966-993). Selecting a category hides the bottom tab strip
  (EV:970).

### B6. Trending / featured headers

- Trending row inside sticker grid: `TrendingListView` — row height **52dp**,
  padding (8, 4, 8, 0), 2dp item gaps, horizontal covers list; click opens
  trending alert (EV:6845-6858).
- Section headers: `StickerSetNameCell` — height **27dp** (SSNC:234), title
  **15dp** (SSNC:79) color `key_chat_emojiPanelStickerSetName`; "ADD" chip 11dp
  with 9dp-radius background (SSNC:97-101); constructed with the same
  `glassDesign` flag (EV:6778).
- Trending dot: `dotPaint` = `key_chat_emojiPanelNewTrending` (EV:1618) drawn
  on the featured tab icon.
- Search-results pack header: `FoundStickerPacksHeaderCell`, height =
  `searchFieldHeight` (50dp), replaces the search row when browsing a found
  pack (EV:1953-1956).
- "Create sticker" tile: rounded 13dp `chat_emojiPanelIcon@12%` background,
  24dp icon + 11dp bold label, both `key_chat_emojiPanelIcon` (EV:6861-6886).
- Add-pack floating button: 48dp tall, margins (10, 5, 10, 10), bottom-pinned
  (EV:1978, 2579).

### B7. `chat_emojiPanel*` color key usage

| key | used for |
|---|---|
| `chat_emojiPanelBackground` | panel bg, grid glow, tab-strip bg, navbar fade (EV:807, 1752, 2133, 4554) |
| `chat_emojiPanelShadowLine` | search-row & tab-strip 1px shadows, strip underlines (EV:802, 1970, 2481) |
| `chat_emojiSearchBackground` | search box fill (non-glass) (EV:812) |
| `chat_emojiSearchIcon` | search & clear icon, hint (non-glass) (EV:848, 888, 943) |
| `chat_emojiPanelIcon` | unselected category icons, selector @18%, create-tile (ETS:751, EV:5910, 6877) |
| `chat_emojiPanelIconSelected` | selected icons; bottom-tab indicator @20/255 (EV:1583-1600, 2701) |
| `chat_emojiBottomPanelIcon` | unselected bottom-tab icons (non-glass) (EV:5903, 5918) |
| `chat_emojiPanelBackspace` | backspace/settings/search tint (non-glass) (EV:2651, 2684, 2771) |
| `chat_emojiPanelStickerPackSelectorLine` | sticker/GIF strip indicator, search dot (EV:2480, 2131, 1594) |
| `chat_emojiPanelStickerSetName` | section headers, lock/mark views (EV:3908-3924) |
| `chat_emojiPanelNewTrending` | trending dot (EV:1618) |
| `chat_emojiPanelEmptyText` | GIF-search empty state (EV:5896-5897) |

Glass mode replaces most icon tints with
`glass_defaultIcon` at fixed alphas: **0.4 unselected / 0.8 selected / 0.6
buttons / 0.45 hint / 0.06 search fill / 0.05 selector** (EV:10135-10139,
ETS:754-758, PSTS:343-347).

### B8. Tab-switch animation

- Page switch: standard ViewPager horizontal scroll; the bottom-tab indicator
  pill tracks `positionOffset` live and settles with 350ms EOQ (PSTS:273-300);
  grid visibility toggles at half-offset (`checkGridVisibility`, EV:2709).
- Backspace visible only on page 0; sticker-settings only on page 2 — both
  swapped with animated visibility (EV:2744-2745); bottom strip re-shows on any
  page scroll (EV:2711).
- Category-strip icon morphs are the selector drawables (crossfade), pack icons
  animate via lottie when `FLAG_ANIMATED_EMOJI_REACTIONS` (EV:980-982).

---

## Part C — blur3 / glass wiring & LiquidGlassSettings

### C1. ChatAttachAlert (imports CAA:140-153)

Uses `blur3` factories + `glass/GlassTabView`. Three factories (CAA:1273-1322):
- `iBlur3FactoryLiquidGlass` — source: RenderNode painting
  `key_windowBackgroundWhite` + noise-suppressed `DRAW_GLASS` capture of the
  current layouts (API ≥ 31); liquid-glass allowed iff
  `LiteMode.FLAG_LIQUID_GLASS`.
- `iBlur3FactoryFrostedLiquidGlass` — same but `DRAW_FROSTED_GLASS`.
- `iBlur3FactoryFade` — plain color source (for the bottom fade).
- Fallback below API 31: all factories use the flat `BlurredBackgroundSourceColor`.
- Capture: current + next attach layout, alpha-weighted cross-fade
  (CAA:1324-1338).

Consumers → presets:

| surface | factory | provider | radius/pad |
|---|---|---|---|
| attach tab bar | liquid | `mainTabs` | r28 / pad7 (CAA:2725-2728) |
| action bar pills | liquid | `attachMenuActionBar` | r23 / pad6 (CAA:4075, AB:221-239) |
| caption bar | liquid | `inputFieldDialogActivity` (=`topPanel`) | r22 / pad7 (CAA:3038-3041) |
| top caption container | liquid | `inputFieldDialogActivity` | (CAA:3447) |
| in-sheet emoji keyboard | **frosted** | `inputFieldDialogActivity` | r29 top (CAA:3032-3034) |
| grid fast-scroll | liquid | `topPanel` | (CAA:4069) |
| bottom fade | fade | — | fadeHeight 72dp (CAA:2717-2721) |
| search fields (contacts/audio/quick replies) | liquid | `attachMenuSearch` via `setupBlurredSearchField` | (CAA:4828-4870) |

**LiquidGlassSettings overrides**: only the in-sheet emoji keyboard sets
`setThickness(dp(32))` and `setIntensity(0.4f)` (CAA:3035-3036) — the same
32dp/0.4 lens as the chat input keyboard panel (see spec_chat_input.md §1).
Everything else uses factory defaults.

### C2. EmojiView (imports EV:138-146)

- Own factory (EV:2846-2857): API ≥ 31 → `BlurredBackgroundSourceRenderNode`
  re-recorded every `dispatchDraw` with `key_windowBackgroundWhite` +
  `DownscaleScrollableNoiseSuppressor.DRAW_GLASS` (EV:4503-4512); liquid-glass
  allowed iff `LiteMode.FLAG_LIQUID_GLASS`; below API 31 → flat color source.
- Captures: the three grids via `ViewGroupPartRenderer` (stickers also render
  overlay pre-draw) (EV:2866-2895). Blur rect = typeTabs bounds, inset 0 in
  liquid-glass mode / −48dp otherwise, extended to full width (EV:4518-4527).
- Consumers: typeTabs + backspace + search + settings buttons, all
  `emojiViewButton` r18/pad6 (EV:2923-2951). **No LiquidGlassSettings
  overrides** (no `setThickness`/`setIntensity` calls in EV).
- An external factory can be injected (`setBlurredBackgroundDrawableFactory`,
  EV:2923) — the attach sheet passes its own so the panel blurs sheet content.

### C3. Flutter mapping

- `GlassPresets.mainTabs`, `GlassPresets.attachMenuActionBar`,
  `GlassPresets.emojiViewButton` already exist (`lib/src/glass/presets.dart`).
- Attach tab = `GlassTab`-style widget with the `TabIcon` /
  `TabAnimationController` contract (`components/tabs/tab_icon.dart`); bar
  surface = `GlassPanel(preset: GlassPresets.mainTabs)` like `GlassTabBar`.
- Sheet container: `TgBottomSheet` (`components/sheet/tg_bottom_sheet.dart`).
- Frosted keyboard lens (thickness 32 / intensity 0.4) maps to the existing
  `LiquidGlassSettings` values used by the chat-input keyboard panel.
- Gallery thumbnails, sticker sets, GIF search, attach-menu bots: provider/slot
  parameters only.
