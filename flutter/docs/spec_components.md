# Telegram Android → Flutter port: Component visual specs (extracted from Java sources)

All paths relative to `/home/user/Telegram/TMessagesProj/src/main/java/org/telegram/`.
Font facts (messenger/AndroidUtilities.java): `AndroidUtilities.bold()` = **fonts/rmedium.ttf** (Roboto Medium; system 500-weight if `useSystemBoldFont`, L260-269); `TYPEFACE_ROBOTO_EXTRA_BOLD` = **fonts/rextrabold.ttf** (L251). Curve constants (Components/CubicBezierInterpolator.java L11-14): `DEFAULT`=(.25,.1,.25,1), `EASE_OUT`=(0,0,.58,1), `EASE_OUT_QUINT`=(.23,1,.32,1), `EASE_IN`=(.42,0,1,1).

---

## 1. ActionBar — ui/ActionBar/ActionBar.java

**Heights**
- Bar height: **56dp portrait, 48dp landscape** (`getCurrentActionBarHeight()`, L1855-1861); + `statusBarHeight` when `occupyStatusBar` (L1389); + `extraHeight`.

**Back button**
- ImageView **54×54dp**, top-left (L269, measured 54dp wide × barHeight, L1393); content padding-left 1dp (L268); glass mode: translationX +2dp (L250).

**Title**
- Typeface: `AndroidUtilities.bold()` (rmedium) (L523); color key `Theme.key_actionBarDefaultTitle` (L520); vertical padding 8dp top/bottom (L525), drawable padding 4dp (L524), right-drawable top padding −1dp (L526).
- Text size (dp, set in onMeasure L1431-1443): **glass mode 17**; title-only: 20 (18 phone-landscape, 20 tablet); title+subtitle: 18 (20 tablet). Measured height cap: 24dp + paddings (L1455).
- Left position `textLeft`: with back button 72dp (80 tablet); without 18dp (26 tablet) (L1394-1396); **glass mode override: 76dp / 24dp** (L1511-1513).
- Vertical: title-only centered (L1531); with subtitle: `(h/2 − textH)/2 + 2dp + 3dp` (2dp landscape) (L1529); subtitle top `h/2 + (h/2 − textH)/2 − 2dp` (L1542).

**Subtitle**
- Color key `Theme.key_actionBarDefaultSubtitle` (L465, L476); size 14dp (16 tablet) when title present; 16dp alone (14 landscape) (L1437-1449); measured height cap 20dp (L1466).

**Menu / action mode**
- Menu width = parentWidth − 66dp (74 tablet) when search visible (L1407-1412); glass mode: menu translationX −10dp → −5dp lerped by `searchFieldVisibleAlpha` (L242, L1208).
- Action mode colors: `key_actionBarActionModeDefault` (L767), `key_actionBarActionModeDefaultTop` (L781, L1100). Show/hide fade **200ms** (L891, L1056).
- Avatar-search image 42×42dp at x = 56+8dp, vertically centered (L1477-1481, L1551-1558).

**Glass mode (setupGlass, L209-252)**
- Three `BlurredBackgroundDrawable` pills, each `.setPadding(dp(6))`:
  - main/title pill radius **23dp** (forum variant per-corner **18.33 / 23 / 23 / 18.33dp**, L224-228; animates 18.33→23 with `searchFieldVisibleAlpha`, L1200-1205);
  - back pill radius 23dp; menu pill radius 23dp (L231-239).
- Pill geometry (dispatchDraw L2152-2197): `p = 6dp`, `s = 46dp`; pill top `t = height − (barHeight+s)/2 − p`, pill height = `s + 2p` = **58dp**; back pill bounds `[0, t, 58dp, b]`; menu pill `[w − max(46,menuW) − 12dp, t, w, b]`; menu item width tracked by FactorAnimator **320ms EASE_OUT_QUINT** (L2115-2116); avatar container width animator **380ms EASE_OUT_QUINT** (L2112-2113); chat avatar min visual width 192dp (L2098).

**Animations**
- Search field show/hide: AnimatorSet **150ms**; hidden views scale 0.95, alpha 0 (L1196-1264).
- `setTitleAnimated`: new title translationY from ±20dp + alpha, caller-supplied duration; subtitle crossfade **220ms** (L1878-1909).
- Adaptive background color (scroll): ValueAnimator **320ms EASE_OUT_QUINT**, keys `key_windowBackgroundGray` (top) → `key_actionBarDefault` (L2287-2292, L2312-2313).
- Supported-transition set: **220ms `CubicBezierInterpolator.DEFAULT`** (L2055-2056).

---

## 2. Glass tab bar

### Container/activity — ui/MainTabsActivity.java (+ ui/DialogsActivity.java constants)
- Constants (DialogsActivity.java L289-291): `MAIN_TABS_HEIGHT = 56`, `MAIN_TABS_MARGIN = 8`, `MAIN_TABS_HEIGHT_WITH_MARGINS = 72` (dp).
- `tabsView` padding **12dp** all sides (`MAIN_TABS_MARGIN + 4`, L287); max width **dp(328 + 16) = 344dp** (L288); placed 72dp tall, bottom|center-h in wrapper (L359); wrapper bottom padding = navigationBar (L824).
- Glass background: `BlurredBackgroundDrawable` radius **28dp** (`MAIN_TABS_HEIGHT/2`, L343), padding **dp(8 − 0.334) ≈ 7.67dp** (L344); liquid-glass allowed iff `LiteMode.FLAG_LIQUID_GLASS` (L340).
- Glass color recipe (Components/blur3/drawable/color/impl/BlurredBackgroundProviderImpl.java `mainTabs`, L19-33): background solved from `key_windowBackgroundWhite` → `key_glass_targetMainTabs` at **alpha 0.85 (glass) / 0.76 (frosted)**; strokeTop `0x11000000`/dark `0x06FFFFFF`; strokeBottom `0x20000000`/`0x11FFFFFF`; shadow `0x20000000`/`0x04FFFFFF`, shadow layer radius 2.667dp, dy 0.85dp; stroke width 0.4dp.
- Bottom fade behind bar: `BlurredBackgroundWithFadeDrawable` fade height **60dp** (L352); fadeView height = navBar + updateLayout + 72dp (L805).
- Tabs show/hide: BoolAnimator **380ms EASE_OUT_QUINT** (L102-103); hidden = translationY +40dp, alpha=factor (L959-968; scale 0.85→1 computed L962 but not applied).
- Bulletin bottom offset above bar: navBar + dp(56+8) (L192).
- Tab bar's source hash includes `key_windowBackgroundWhite` (L122); source canvas drawColor `key_windowBackgroundWhite` (L155).

### Row layout — ui/MainTabsLayout.java
- Text auto-fit passes: sizes **{12, 12, 10}dp** with per-tab horizontal paddings **{16, 8, 4}dp** (L46-47); min total row width **320dp** (L69); tab width = textWidth + 2×padding, equalized/scaled to fit (L59-154).
- Child appear/disappear: alpha=factor, scale lerp(0.7→1) (L224-229).
- Long-press "lens" drag: custom selector = `key_glass_tabSelected` at **9% alpha** (`multAlpha 0.09`, L289), stadium round-rect radius = height/2 (L313-321).
- Springs (L356-369): selector position/offset X — `STIFFNESS_MEDIUM` (=1500), `DAMPING_RATIO_LOW_BOUNCY` (=0.75); whole-bar scaleX/Y springs stiffness 250, damping 0.25 (currently unused, commented at L516-537).
- Long-press bar scale **1.019**, BoolAnimator **380ms EASE_OUT_QUINT** (L436-439); long-press trigger at 75% of system duration (L485); selector restore delay 450ms (L493).
- Pressed-tab pivot warp: radial mapping `mappedR = 1.5r/(r+0.5)`, pivotY lerp ×3 (L563-604).

### Tab — ui/Components/glass/GlassTabView.java
- Icon: RLottieImageView default frame 44×44dp, top −6dp (L83); main tabs 24×24dp, top 4dp (L406); avatar tab 22×22dp top 5dp, round radius 11dp (L424-427); attach-bot avatar 24×24 top 4 / 22×22 top 5 radius 11.33dp (L643, L666-667).
- Label: **12dp**, bold (rmedium), single line, gravity center, top margin **28.33dp** (L88-96); attach tabs **11dp** + 8dp horizontal text padding (L445-446, L460-461).
- Selected label swaps to **Roboto ExtraBold** (`fonts/rextrabold.ttf`); unselected = bold/rmedium (L237).
- Colors (L268-270, keys in ui/ActionBar/ThemeColors.java L822-828): `key_glass_tabUnselected` (default `0xFF1A1D21`), `key_glass_tabSelected` (`0xFF1a91e6`), `key_glass_tabSelectedText` (`0xFF0d7fcf`); icon tint blends unselected→selected; text blends unselected→selectedText (L254-265).
- Selection pill behind tab (L154-165): color = selected @ **9% alpha × decel(alpha)**; stadium radius = min(w,h)/2; scale lerp(0.6→1, selectedFactor).
- Selection animator: **320ms DECELERATE** (L67); counter show/error animators: **380ms EASE_OUT_QUINT** (L68-69).
- Counter badge (L98-103, L175-213): text **10dp** bold white; center x = w/2 + 11dp, y = 10dp; height **16dp**, width = max(16dp, textW + 8dp); inner radius **8dp**, punch-out ring gap **1.33dp** with outer radius **9.333dp** (cut via `Theme.PAINT_CLEAR` in saveLayer); fill = blend(`key_telegram_color` → `key_fill_RedNormal`) by error factor (L208).
- Premium badge: PremiumGradient round-rect (matrix 96×16dp) + `R.drawable.star` 14×14dp centered (L196-206).
- Attach tab self-width: `min(84dp, textW + 2×lerp(16dp→8dp over textW 40→56dp))` (L485-489).
- Icon lotties 24×24: enum `TabAnimation` (L545-569) — CHATS/CONTACTS/CALLS/SETTINGS single lottie plays forward on select, reverse on deselect (L385-397); paired `*_reverse` variants for attach tabs; BOOSTS(mid 25,end 49), MONETIZATION(19,45) frame-segment animations.

### ui/Components/glass/GlassTabsView.java (attach-panel variant)
- Padding 8dp all sides (L34); lens foreground inset −7dp × visibility (L61-65).

---

## 3. DialogCell (key metrics) — ui/Cells/DialogCell.java

- Layout constants (L169-174): `avatarStart = 11`, `messagePaddingStart = 72`, `heightDefault = 70`, `heightThreeLines = 76`, `addHeightForTags = 3`, `addForumHeightForTags = 11` (all dp); checkbox padding top 42dp (L182). Measured height = base + tags + **1px separator** (L994; `useSeparator || true` in getCollapsedHeight L1021); forum cell (expanded): **91dp** (86 three-line) (L1006); two-line name +20dp (L1024-1025).
- Text (buildLayout L1246-1268 — note `|| true` forces paintIndex=1): name **16dp** bold (rmedium) (`dialogs_namePaint[1]`), message **15dp** regular; the [0] variants are 17/16dp. Time **12dp** (Theme.java L8472), messageName 14dp (L8471), archive 13/11dp, online/offline 15dp, tag text 10dp bold, searchName 16dp bold (L8477-8483). Counter text 12dp / 13dp bold (Theme.java L8371-8372).
- Two-line (default) geometry (L2452-2472): avatar **52×52dp** at x=11dp, y=9dp; text left = `messagePaddingStart+4` = **76dp**; messageNameTop 31dp; timeTop 16dp; errorTop 38dp; pinTop 39dp; countTop 38dp (topic 35dp); checkTop 17dp; thumb 19dp at avatarLeft+56+11. Name baseline top = **14dp** (L4081), −9dp if tags.
- Three-line geometry (L2429-2449): avatar **56×56dp** at (11, 11); text left 78dp; nameTop 10dp; timeTop 13; error/count 42.33; pin 43; check 13; thumbs 18dp.
- Unread badge (L1225-1233): height **20.666dp** (= 2×6.333 text pad + 8 min width), gap 17dp, margin 15.666dp, drawable-in-badge 16dp.
- Separator: 1px `Theme.dividerPaint` line, inset left `messagePaddingStart` (72dp) unless full separator (L4774-4791).
- Color keys used: `key_chats_name`, `key_chats_secretName`, `key_chats_nameArchived`, `key_chats_message`, `key_chats_message_threeLines`, `key_chats_nameMessage(_threeLines)`, `key_chats_draft`, `key_chats_actionMessage`, `key_chats_attachMessage`, `key_chats_pinnedOverlay`, `key_chats_onlineCircle`, `key_chats_unreadCounterText`, `key_chats_verifiedBackground`, `key_chats_archiveBackground`, `key_chats_archivePinBackground` (grep L1144-6443).

---

## 4. TextCell — ui/Cells/TextCell.java

- Height **50dp** (`heightDp`, L62) + 1px divider (L213); `offsetFromImage = 58dp` (52 for colorful icon, L824-826); `imageLeft = 16dp` (18 for drawable variants, L398/421); default `leftPadding = 23dp` (L79).
- Title `SimpleTextView` **16dp**, key `key_windowBackgroundWhiteBlackText` (dialog: `key_dialogTextBlack`) (L96-98); subtitle **13dp**, `key_windowBackgroundWhiteGrayText`/`key_dialogTextGray` (L103-105); value `AnimatedTextView` **16dp**, `key_windowBackgroundWhiteValueText`/`key_dialogTextBlue2`, translationY −2dp, vertical padding 18dp (L110-116); icon tint `key_windowBackgroundWhiteGrayIcon`/`key_dialogIcon` MULTIPLY (L130).
- Measure: title width = w − 71dp − leftPadding − valueWidth; components measured at 20dp height (L193-202); value right inset `leftPadding − 6` (L255).
- Title/subtitle stack: inter-gap 4dp if heightDp>50 else 2dp (L269); icon top-pad 7dp (6 for drawable) (L372, L411); Switch **37×20dp**, 22dp from edge, centered (L140).
- Divider: 1px, left inset 20dp (no icon) / 58dp (icon) / 72dp (inDialogs), paint `key_paint_divider` else `Theme.dividerPaint` (L829-836).
- Loading stripe: right 21dp, height 6dp, radius 3dp, color `key_dialogSearchBackground`, fade 150ms-ish (progress += 16/150 per frame), pulse alpha 0.6-1.0 (L916-963).
- Disabled alpha 0.5 (L221-236).

---

## 5. HeaderCell — ui/Cells/HeaderCell.java

- Nominal height **40dp** (`height`, L44; textView minHeight = height − topMargin, L98); default padding **18dp** horizontal wait — constructor default `padding = 18` … actual common calls pass 21; top margin default **7dp**, bottom margin default 0 (L49-61).
- Text: **14dp**, `AndroidUtilities.bold()` (rmedium), color key default `key_windowBackgroundWhiteBlueHeader` (L49, L94-99).
- Optional right text2: SimpleTextView **13dp**, top margin 21dp (L105-108).
- Measured with UNSPECIFIED height (wraps) (L160-162). Disabled alpha 0.5 (L142-149).

---

## 6. ShadowSectionCell — ui/Cells/ShadowSectionCell.java

- Default height **12dp** (L32-36), EXACTLY in onMeasure (L107-109).
- Current code: background is **null** (or flat `backgroundColor` if provided) — the classic `greydivider`/`greydivider_top`/`greydivider_bottom` 9-patches tinted `key_windowBackgroundGrayShadow` are commented out (L74-92, resource ids L94-104). Port as a plain 12dp spacer with optional top/bottom inner shadow assets.

---

## 7. UserCell — ui/Cells/UserCell.java

- Height **58dp** (call style **56dp**) + 1px divider (L494-498).
- Avatar: **46×46dp**, round radius 24dp, left = 7+padding dp, top 6dp (L182-183).
- Name: SimpleTextView **16dp bold** (rmedium), key `key_windowBackgroundWhiteBlackText`; left 64+padding, top 10, line-height box 20dp (L186-191). Call style: 15dp (L481-482).
- Status: **15dp**, top 32, left 64+padding (L196-199); colors: `key_windowBackgroundWhiteGrayText` normal, `key_telegram_color_text` online (L158-159). Call style 13dp (L483-484).
- Emoji status / bot-verification drawables 20dp (L193-194). Left icon tint `key_windowBackgroundWhiteGrayIcon`, left margin 16 (L201-205).
- Checkboxes: CheckBoxSquare 18×18 right 19; CheckBox2 size 21 in 24×24 at left 24+padding top 36 (moves to 37+padding/top 32 in call style, L488); check3 24×24 right 10+padding tint `key_featuredStickers_addButton` (L207-223).
- Add button: height **28dp**, text 14dp bold, `key_featuredStickers_buttonText` on `filledRectByKey(key_featuredStickers_addButton, 14)` (radius 14dp), h-padding 17dp, top 15, right 14 (L142-150).
- Admin label 14dp `key_profile_creatorIcon`, top 10, right 23; role-pill variants: pad 6dp, bg `multAlpha(color, .12)` radius 32dp; keys `key_chat_tagCreator`/`key_chat_tagAdmin`/`key_chat_inAdminText` (L226-296).
- Divider 1px `Theme.dividerPaint`, left inset **68dp** (L771-774).

---

## 8. Bulletin (metrics only) — ui/Components/Bulletin.java

- Durations: `DURATION_SHORT = 1500ms`, `DURATION_LONG = 2750ms`, `DURATION_PROLONG = 5000ms` (L89-91).
- Base `Layout`: min height **48dp**, padding **16dp horizontal / 8dp vertical**, background = round rect **16dp** radius, color key `key_undo_background`; press scale via ScaleStateListAnimator(.02, 1.5) (L794-818). Wide screen (tablet/landscape): wrap-content width, center-h (L864-871).
- Enter/exit transitions: default **spring, dampingRatio 0.8, stiffness 400** on offsetY (L1121-1172); alternative `DefaultTransition` enter 255ms easeOutQuad / exit 175ms easeInQuad (L1056-1119). Blur-out variant renders snapshot at radius 10dp, 6 iterations (L1200).
- Swipe-dismiss: threshold width/3, 200ms accelerate (L645-648); spring stiffness 100 no-bouncy for fling (L594-597).
- LottieLayout (single-line): lottie icon frame **56×48dp** start-aligned; text **15dp** `Typeface.SANS_SERIF`, v-padding 8dp, margins start 56 / end 16; colors `key_undo_infoColor` text + `key_undo_cancelColor` links, bg `key_undo_background` (L1980-2008).
- TwoLineLayout: image 30×30 @ (12,8); text block margin start 56 (L1377-1384); user-avatar variants: avatar 32×32 or 56×48, text column margins (52, 8, 8, 8), title 14dp bold, subtitle 13dp (L1449-1702, sizes at L1617, L1693-1702).
- ProgressLayout: 32dp progress ring (stroke 2dp) with 28dp inner image radius 14dp; text 15dp AnimatedTextView (L1932-1942).
- UndoButton TimerView: countdown text **12dp** (L2377), ring stroke 2dp (L2382), inset 1dp (L2397).
- Gradient clip at container edge: 8dp linear-gradient DST_OUT (L1241-1254).

---

## 9. BottomSheet (metrics only) — ui/ActionBar/BottomSheet.java

- Background: `R.drawable.sheet_shadow_round` 9-patch tinted `key_dialogBackground` (MULTIPLY); its intrinsic padding becomes `backgroundPaddingLeft/Top` (L1193-1198). Container padding: `backgroundPaddingLeft` sides; top `+8dp` (if applyTopPadding) `+backgroundPaddingTop − 1`; bottom `+8dp` (L1357).
- Title row: fixed height **48dp** (L1389, L1411-1413). Big title: **20dp bold**, `key_dialogTextBlack`, padding (21, 6 [14 multiline], 21, 8). Normal: **16dp**, `key_dialogTextGray2`, padding (16, 0 [8 multiline], 16, 8) (L1391-1399).
- Item cells (`BottomSheetCell`, L1019-1083): height **48dp** (type 2 button cell **80dp**); icon frame 56×48, tint `key_dialogIcon` MULTIPLY; right icon tint `key_radioBackgroundChecked`; text: type 0 → 16dp `key_dialogTextBlack` left/CENTER_VERTICAL; type 1 → 14dp bold centered; type 2 → 14dp bold `key_featuredStickers_buttonText` on `filledRect(key_featuredStickers_addButton, 6)` (6dp radius) with 16dp margins.
- Items stack: each cell 48dp, `topOffset += 48` (L1440-1441).
- Animations: open = translationY→0, **250ms `CubicBezierInterpolator.DEFAULT`** (custom `openDuration` overridable; declared `openInterpolator = EASE_OUT_QUINT` L211, L1739-1742); dismiss **180ms EASE_OUT** (330ms for CELL_TYPE_CALL) (L1870-1871); dismissWithButtonClick 200ms DEFAULT / plain dismiss 250ms EASE_OUT (L2029-2033); swipe-release settle duration scaled by distance ~250ms DEFAULT (L398-399); nav-bar/dim companion animators 320ms EASE_OUT_QUINT (L502-512); inset animation 180ms DEFAULT (L960-961).

---

### Cross-cutting notes for the Flutter port
- Recurring motion grammar: **380ms EASE_OUT_QUINT** for structural/emphasis changes, **320ms EASE_OUT_QUINT** for width/color tracking, 200-250ms DEFAULT for modal fades, springs (stiffness 250-1500, damping 0.25-0.8) for gesture-driven motion.
- Recurring glass grammar: pill radius = height/2 (tab bar 28dp, action-bar pills 23dp), content padding 6-8dp around glass, tint alpha 0.85 (liquid) / 0.76 (frosted), hairline strokes 0.4dp with different top/bottom colors per brightness.
- "Bold" in Telegram = Roboto Medium (rmedium.ttf), not w700; selected tab uses rextrabold.ttf — map to Flutter `FontWeight.w500`/`w800` with bundled fonts.