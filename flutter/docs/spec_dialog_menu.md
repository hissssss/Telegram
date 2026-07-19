# Telegram Android → Flutter port: AlertDialog + Popup/Context menu specs

Sources (paths relative to `/home/user/Telegram/TMessagesProj/src/main/java/org/telegram/`):
- `ui/ActionBar/AlertDialog.java` (1988 L)
- `ui/ActionBar/ActionBarPopupWindow.java` (1141 L)
- `ui/ActionBar/ActionBarMenuSubItem.java` (435 L)
- Supporting: `ui/ActionBar/TextViewWithLoading.java`, `ui/ActionBar/ThemeColors.java`, `messenger/AndroidUtilities.java`, `res/values/styles.xml`, `ui/Components/ItemOptions.java`.

`AndroidUtilities.bold()` = Roboto Medium (`fonts/rmedium.ttf`) — see spec_components.md header. All sizes dp unless noted.

---

## 1. AlertDialog — ui/ActionBar/AlertDialog.java

Telegram's own `Dialog` subclass (NOT android.app.AlertDialog). Variants: `ALERT_TYPE_MESSAGE` (0, default), `ALERT_TYPE_LOADING` (2), `ALERT_TYPE_SPINNER` (3) (L91-93).

### 1.1 Surface / container
- Window style `R.style.TransparentDialog` (L301): transparent window background, floating, translucent, **no `windowAnimationStyle` override** (res/values/styles.xml L139-153) — i.e. the enter/exit animation is the stock Android `Theme.Dialog` one (short fade + subtle scale-up, ≈150ms). There is no custom programmatic show/dismiss animation for the message dialog.
- Background: 9-patch `popup_fixed_alert4` (rounded rect + soft drop shadow) tinted with `key_dialogBackground` via MULTIPLY (L312-315); the 9-patch padding becomes `backgroundPaddings` (L315) and is added around the content.
- **Corner radius: 20dp** — clip outline `ViewOutlineProviderImpl.boundsWithPaddingRoundRect(dp(8), dp(20))` (bounds inset 8dp = the shadow ring, radius 20dp) (L663-664); the manual blur-background path also draws r=20dp (L575). (Legacy inconsistencies: spinner card r=18dp L565/L881; native-blur window shape r=12dp L1279-1280. Canonical for a port: **20dp**.)
- **Width**: window width = `min(maxWidth, screenWidth − 48dp)` + bg paddings (L1250-1262); `maxWidth` = **356dp phone**, 446dp small tablet, 496dp big tablet (L1252-1260). (Re-layout path on screen rotation uses screenWidth − 56dp, L490-505.)
- **Dim**: `dimAmount = 0.5` by default (`dimAlpha = 0.5f` L210; applied via FLAG_DIM_BEHIND L1241-1243); builder-overridable (`setDimAlpha` L1949-1952, `setDimEnabled` L1944-1947).
- Optional blurred-background mode (dark themes, high perf class): blur of screen + dim + background paint at `blurAlpha = 0.8` (L217, L306-316, L560-599). Treat as optional glass variant.
- Content column is a vertical LinearLayout (L643-644); message/items/custom view live inside a ScrollView with 3dp-tall edge shadows (`header_shadow` / reverse) that fade in/out over **150ms** when content scrolls under title/buttons (L816-845, `runShadowAnimation` duration 150 L1422-1432).

### 1.2 Title block
- Title: **20dp, Roboto Medium (bold()), `key_dialogTextBlack`**, start-aligned (L786-794). Container margin **24dp horizontal** (L784); title top margin **19dp**, bottom margin **10dp** (2 if subtitle follows, 14 if items list, 4/centered when `topAnimationIsNew`) (L794).
- Optional second title (right-aligned in same row): 18dp, `key_dialogTextGray3` (L798-803).
- Optional subtitle: 14dp, color `key_dialogIcon`, margins 24 horizontal, bottom 10 (14 with items) (L806-812).

### 1.3 Message
- **16dp, `key_dialogTextBlack`** (`key_windowBackgroundWhiteGrayText` + centered in the "new top animation" promo style) (L849-857); links `key_dialogTextLink` (L852).
- Margins: **24dp horizontal** (L893); block top margin 19dp when there is no title, bottom margin **20dp** (L453-455). With items/custom view below: bottom margin 8dp (L448-452) and message→content gap `customViewOffset` = 12dp default (L116, L893, L1896-1899).

### 1.4 Button row
- Row: MATCH_PARENT × **52dp** appended to the column (L1055), padding **8dp** all sides (L1053) → visual button height **40dp**.
- Button widget = `TextViewWithLoading` (text button, no fill):
  - Text **16dp, Roboto Medium (bold()), gravity center** — NOT 14dp and NOT uppercased; the label renders as given (L1076-1080). Color key **`key_dialogButton`** (default 0xFF298ACF) (L123, L1077); destructive buttons re-colored `key_text_RedBold` (0xffcc4747) via `redPositive()` (L231-236) / `Builder.makeRed` (L1910-1929).
  - **minWidth 64dp** (L1074), horizontal padding **12dp** (L1082), height **40dp** (36dp for the rare BUTTON_NEGATIVE_2, L1207-1209).
  - Background: `Theme.getRoundRectSelectorDrawable(dp(20), color)` — transparent at rest, pill-shaped (r = **20dp**) ripple in the button color at 10% alpha (`(color & 0x00ffffff) | 0x19000000`) (L1081; Theme.java L5515-5522). BUTTON_NEGATIVE_2 uses r=6dp (L1204).
  - Disabled state: alpha 0.5 (L1062-1066).
  - Max width per button: (dialogWidth − 24dp)/2 (L390-398).
- **Horizontal placement** (custom FrameLayout, LTR): positive pinned to the right edge; negative immediately left of positive with an **8dp gap**; neutral pinned to the left edge (L961-1013). RTL mirrors.
- **Vertical fallback**: pre-measured with 16dp bold paint, 12+12dp padding per button and 8dp gaps (L932-951); if combined width > screenWidth − 64dp → vertical LinearLayout (L952-959). Vertical order: negative first (inserted at 0), then neutral (index 1), positive last-added; each MATCH_PARENT × 40dp with **6dp top margin** between buttons (L1124-1125, L1165-1166, L1222-1226).
- Click: positive/neutral → dismiss, negative/negative2 → cancel, unless `dismissDialogByButtons=false` (L1088-1096, L1129-1137).
- **Loading state** (`makeButtonLoading`, L1313-1335): label slides down 6dp + fades out while a `CircularProgressDrawable` spinner fades/slides in at center; animated float **320ms EASE_OUT_QUINT** (TextViewWithLoading.java L16, L46-73). Clicks ignored while loading (L1089).

### 1.5 Items-list variant (`Builder.setItems`)
`AlertDialogCell` rows in the scroll container (L905-922):
- Height **48dp** (onMeasure L266-269; added as 50dp LinearLayout rows, L914), padding **23dp horizontal** (L249).
- Text 16dp `key_dialogTextBlack` single-line (L256-262); optional left icon (40dp-tall centered frame, tint `key_dialogIcon` MULTIPLY, L251-254) with text left padding **56dp** (L284).
- Pressed selector `key_dialogButtonSelector` (0x0f000000) (L248). Tapping an item fires the callback and dismisses (L915-920).

### 1.6 Progress variants — note only (port later with progress components)
- `ALERT_TYPE_LOADING`: message 16dp + `LineProgressView` MATCH × **4dp** (margins 24 horiz), colors `key_dialogLineProgress` / `key_dialogLineProgressBackground`; percent label 14dp Roboto Medium `key_dialogTextGray2` below (L858-873).
- `ALERT_TYPE_SPINNER`: centered **86×86dp** card, r=18dp, bg `key_dialog_inlineProgressBackground`; `RadialProgressView` size **32dp**, color `key_dialog_inlineProgress` (L874-888). Show animation: scale 0→1, `OvershootInterpolator(1.3)`, **190ms** (L327-335). Not cancelable on outside touch (L875-876); touching it offers a "stop loading" confirm dialog (L350-366, L1400-1420).

### 1.7 Show/dismiss
- `show()` guards + records `shownAt` (L322-337); `dismissUnless(minDuration)` delays dismiss to enforce a minimum on-screen time (L1505-1512); `showDelayed(delay)` (L1696-1699).
- `dismiss()` is idempotent (`dismissed` flag) and has an interceptable `overridenDissmissListener` (L1519-1549).
- For Flutter: barrier color `black54` (dim 0.5), route transition ≈150ms fade + scale 0.95→1.0 ease-out (platform-default equivalence — inferred, not in Telegram code).

---

## 2. Popup / context menu — ui/ActionBar/ActionBarPopupWindow.java + ActionBarMenuSubItem.java

`ActionBarPopupWindow` (PopupWindow subclass) + `ActionBarPopupWindowLayout` (the surface) + `ActionBarMenuSubItem` rows; `ui/Components/ItemOptions.java` is the fluent builder used by modern code.

### 2.1 Container (ActionBarPopupWindowLayout)
- Background: 9-patch **`popup_fixed_alert2`** (rounded rect + shadow), tinted MULTIPLY with **`key_actionBarDefaultSubmenuBackground`** (default 0xffffffff) (L153, L164-171); layout padding **8dp** all around = the shadow ring (L166).
- **Corner radius: 12dp** — the gap-clip path insets the drawable bounds by 8dp and rounds them at `dp(12)` (L542-549); matches the default row `selectorRad = 12` (ActionBarMenuSubItem L47).
- Structure: vertical LinearLayout inside an optional ScrollView (L185-203, L205-265); optional swipe-back sublayout for nested menus (`FLAG_USE_SWIPEBACK` L104, L180-183); `FLAG_SHOWN_FROM_BOTTOM` (L105) anchors reveal at the bottom.
- `fitItems`: equalizes all row widths to the widest row (L206-248).
- **Separator (GapView)**: full-width band, color **`key_actionBarDefaultSubmenuSeparator`** (default 0xfff5f5f5) with a `greydivider` shadow overlay tinted `key_windowBackgroundGrayShadow` (L1110-1140); canonical height **8dp** (ItemOptions.java L786-792). The background drawable is split around the gap (gap zone = gapStartY..gapStartY+6dp, L231-235, L467-523).
- **Dim**: opt-in `dimBehind()`, default amount **0.2** (L783-795) (ItemOptions and chat menus use it; plain overflow menus often don't).
- Rows' pressed-selector corners follow the container: first visible row rounds its top corners, last visible rounds bottom, radius 12dp (`updateRadialSelectors` L612-643 → `ActionBarMenuSubItem.updateSelectorBackground` L395-412). Legacy `setupRadialSelectors` used 6dp (L604-610).

### 2.2 Open animation (`startAnimation`, static L843-914 / member L916-995)
- **Pivot: top-right** (`pivotX = measuredWidth`, `pivotY = 0`, L847-848, L937-938); `shownFromBottom` reveals upward from the bottom instead (bg rect anchored at bottom, L491-493).
- The container does NOT view-scale: the background drawable's drawn bounds grow vertically — `backScaleY` 0→1 animated together with `backAlpha` 0→255 (L891-895, L962-964).
- **Duration: 150ms + 16ms × visibleItemCount** (L896, L965).
- **Item stagger**:
  - Static variant: every item runs translationY **−6dp→0** (+6 from bottom) + alpha 0→1 (0.5 if disabled) on one ValueAnimator, offset per index via `AndroidUtilities.cascade(t, index, count, waveLength=4)` (L875-895; cascade = sliding clamp window, AndroidUtilities.java L5273-5278); reversed order when shownFromBottom (L884).
  - Member variant: rows are kicked off as the reveal front passes them (row slot treated as 48dp, L337, L356): each row animates alpha 0→1 + translationY ∓6dp→0, **180ms, DecelerateInterpolator** (`startChildAnimation` L380-404, trigger logic in `setBackScaleY` L324-369).
- Lottie row icons start playing when their row lands (`onItemShown`, ActionBarMenuSubItem L340-344).

### 2.3 Dismiss animation (`dismiss`, L1024-1100)
- Default: whole popup translationY → **−5dp** (+5 if shownFromBottom) + alpha → 0; duration **150ms** (`dismissAnimationDuration` L69, L1064-1068).
- `scaleOut` variant: scaleX/Y → **0.8** + alpha → 0, 150ms (L74, L1058-1063).
- Dim is removed immediately at dismiss start (L1026, L813-831).

### 2.4 Menu row (ActionBarMenuSubItem)
- **Height: exactly 48dp** (`itemHeight` default 48, L51; forced in onMeasure L126-131; +8dp if a two-line label overflows in `expandIfMultiline` mode).
- Padding **18dp horizontal** (L84); when a right icon exists, the icon-side padding drops to 8dp (L176).
- **Text: 16dp**, single line, ellipsize end, start-aligned, vertically centered, color **`key_actionBarDefaultSubmenuItem`** (default 0xFF1A1D21) (L91-98, L78). Multiline mode: 2 lines at 14dp (L195-204).
- Optional subtext: 13dp, `key_groupcreate_sectionText`, same 43dp indent; main label gets 10dp bottom margin when subtext shown (L356-378).
- **Left icon**: centered in a 40dp-tall wrap frame at the start (L86-89); assets are 24dp glyphs (animated icons explicitly sized 24×24, L335-338); tint **`key_actionBarDefaultSubmenuItemIcon`** MULTIPLY (L79, L88). Text start padding **43dp** when an icon (or checkbox) is present (L217).
- Optional right icon: 24dp-wide end frame, label end margin 32dp (L159-183); mirrored (scaleX −1) in RTL (L164-166).
- Optional check: `CheckBox2` size 26, draws check only (no unchecked circle), colored `key_actionBarDefaultSubmenuItem` (L104-119); label padding 34dp on the check side.
- **Pressed selector**: `Theme.createRadSelectorDrawable(key_dialogButtonSelector (0x0f000000), topRad, bottomRad)` — ripple clipped to rounded top/bottom corners, **12dp** on the container's first/last row, 0 elsewhere (L47, L81, L414-416; Theme.java L6100-6108).
- Disabled rows: alpha 0.5 (enforced by the popup animators, ActionBarPopupWindow L886, L908, L989); animated enable/disable color blend uses EASE_OUT_QUINT (L273-319).

### 2.5 Default light-theme colors (ui/ActionBar/ThemeColors.java)
| Key | Default | Used for |
|---|---|---|
| `key_dialogBackground` | 0xffffffff (L24) | dialog surface |
| `key_dialogTextBlack` | 0xFF1A1D21 (L16, L26) | title, message, item text |
| `key_dialogButton` | 0xFF298ACF (L15, L50) | dialog buttons |
| `key_dialogButtonSelector` | 0x0f000000 (L51) | pressed state (dialog items + menu rows) |
| `key_dialogTextLink` | 0xff2678b6 (L27) | message links |
| `key_dialogTextGray2` / `Gray3` | 0xff757575 / 0xff999999 (L33-34) | progress %, second title |
| `key_dialogIcon` | 0xFF1A1D21 (L37) | subtitle, item icons |
| `key_text_RedBold` | 0xffcc4747 (L97) | destructive button |
| `key_actionBarDefaultSubmenuBackground` | 0xffffffff (L202) | popup surface |
| `key_actionBarDefaultSubmenuItem` | 0xFF1A1D21 (L200) | menu row text/check |
| `key_actionBarDefaultSubmenuItemIcon` | 0xFF1A1D21 (L201) | menu row icons |
| `key_actionBarDefaultSubmenuSeparator` | 0xfff5f5f5 (L203) | menu gap |
| `key_dialogLineProgress` / `Background` | 0xff527da3 / 0xffdbdbdb (L48-49) | loading dialog bar |
| `key_dialog_inlineProgress` / `Background` | 0xff6b7378 / 0xf6f0f2f5 (L55-56) | spinner dialog |
| `key_windowBackgroundWhiteGrayText` | 0xff808384 (L99) | promo-style message |

---

## 3. Flutter port notes
- **TgAlertDialog**: surface r=20dp, max width 356dp, insets ≥24dp from screen edges, barrier 50% black; title 20/medium, message 16/regular with 24dp gutters (19dp above title, 20dp below message); button row 52dp with 8dp padding, `TgDialogButton` = 40dp-tall 16dp-medium text button, minWidth 64dp, 12dp horizontal padding, 20dp-radius ink splash at 10% of the label color; auto-switch to vertical stack when labels overflow (threshold: combined width > screenW − 64dp), 6dp spacing. Loading state per TextViewWithLoading (320ms easeOutQuint label↔spinner swap). Route transition: 150ms fade + 0.95→1 scale.
- **TgPopupMenu**: surface `key_actionBarDefaultSubmenuBackground`, r=12dp, 8dp shadow padding; open = clip-height reveal from top-right pivot (150 + 16·n ms) with per-item cascade (−6dp slide + fade, wavelength 4); close = 150ms fade + 5dp slide (or scale-to-0.8 variant); optional barrier dim 0.2. `TgMenuItem`: 48dp tall, 18dp side padding, 16dp text, 24dp icon with 43dp text indent, optional 13dp subtext / right icon / check; first/last-item selector corners 12dp; separator = 8dp band in `...SubmenuSeparator`.
- The width-equalization (`fitItems`) and swipe-back nested menu can be deferred; scroll behavior needed when the menu exceeds screen height.
