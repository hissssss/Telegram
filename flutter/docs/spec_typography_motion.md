# Telegram Android — Typography, Motion & Hairline Spec Extraction

Extracted 2026-07-19 from `/home/user/Telegram/TMessagesProj/src/main/java/org/telegram/` (branch `claude/design-ui-liquid-glass-17f6mv`). All line numbers verified against this checkout.

---

## 1. Typography

### 1.1 Font stack

`AndroidUtilities.java:250-254` declares the asset typefaces:

```java
public final static String TYPEFACE_ROBOTO_MEDIUM = "fonts/rmedium.ttf";
public final static String TYPEFACE_ROBOTO_EXTRA_BOLD = "fonts/rextrabold.ttf";
public final static String TYPEFACE_ROBOTO_MEDIUM_ITALIC = "fonts/rmediumitalic.ttf";
public final static String TYPEFACE_ROBOTO_MONO = "fonts/rmono.ttf";
public final static String TYPEFACE_MERRIWEATHER_BOLD = "fonts/mw_bold.ttf";
```

**CRITICAL MAPPING NOTE:** everything the codebase calls "bold" — `AndroidUtilities.bold()` (`AndroidUtilities.java:260-269`) — is **Roboto Medium (weight 500)**, not w700. The system-font fallback path makes this explicit: `Typeface.create(null, 500, false)` (line 263). In Flutter, every `setTypeface(AndroidUtilities.bold())` below maps to `FontWeight.w500` with the bundled `rmedium.ttf`. Regular text (default `TextView`/`Typeface.SANS_SERIF`) is Roboto Regular (w400). `rextrabold` appears only in specialty surfaces (tab selected-state per ARCHITECTURE.md risk table), `rmono` for code, Merriweather for Stories covers — none needed for the core scale.

### 1.2 The de-facto scale (role table)

There is no central type-scale class in Java; these are the recurring `(size dp, weight)` pairs swept from every ported component's source. Proposed Flutter token name in the first column.

| Token | Size / weight | Native usage (citations) |
|---|---|---|
| `title` | 20dp / medium | Portrait screen title: `ActionBar.java:1431,1443` (`glassMode ? 17 : landscape ? 18 : 20`, typeface set bold at `ActionBar.java:523`); sheet large title: `BottomSheet.java:1393-1394`; dialog title: `AlertDialog.java:791-792` |
| `titleCondensed` | 18dp / medium | Landscape/tablet action-bar title (`ActionBar.java:1431,1435`); dialog second title 18dp regular (`AlertDialog.java:801`) |
| `titleGlass` | 17dp / medium | Glass-mode app bar title on this branch (`ActionBar.java:1431,1435,1443`) |
| `input` | 18dp / regular | Chat composer `messageEditText` (`ChatActivityEnterView.java:5752`); in-bar search field + caption (`ActionBarMenuItem.java:1438,1491`) |
| `cellTitle` | 17dp / medium | Chat-list name, 2-line layout (`DialogCell.java:1247-1248,1261-1262`; paints made bold at `Theme.java:8386-8389`). Drops to 16dp in the 3-line layout (`DialogCell.java:1252-1253`) |
| `body` | 16dp / regular | Chat-list message preview (`DialogCell.java:1249,1263`); default chat message size (`SharedConfig.java:313`, tablet default 18 at `:603`); `TextCell` label + value (`TextCell.java:98,113,123`); dialog message (`AlertDialog.java:850,262`); sheet list item (`BottomSheet.java:1058`); popup-menu row (`ActionBarMenuSubItem.java:97`) |
| `bodyEmphasis` | 16dp / medium | `UserCell` name (`UserCell.java:188-189`); dialog action buttons (`AlertDialog.java:1076-1079,1115-1118,1156-1159,1197-1200`); sheet title small-variant is 14 (below) but search-result names are 16 bold (`Theme.java:8393-8396,8482-8483`) |
| `bodySecondary` | 15dp / regular | `UserCell` status (`UserCell.java:197`); online/offline status paints (`Theme.java:8479-8480`); Bulletin single-line text (`Bulletin.java:1359-1360,1382-1383`); 3-line chat-list message (`DialogCell.java:1254-1255`); bot keyboard button (`Theme.java:8612`); composer caption-limit 15 bold (`ChatActivityEnterView.java:3621-3623`) |
| `tab` | 15dp / medium | Text tab strip labels (`ScrollSlidingTextTabStrip.java:549-553`) |
| `label` | 14dp / medium | Section header (`HeaderCell.java:85-86,94-95` — colored `windowBackgroundWhiteBlueHeader`); button label (`ButtonWithCounterView.java:124-126`, weight toggled by `filled` at `:95-98`); `UserCell` "Add" pill (`UserCell.java:145-146`); Bulletin 2-line title (`Bulletin.java:1414-1415` and 4 repeats); dialog-list sender-name paint (`Theme.java:8398,8471`); admin rank label 14 regular (`UserCell.java:228`) |
| `subtitle` | 14dp / regular | Action-bar subtitle, phone-portrait (`ActionBar.java:1437,1446` — 16 on tablet/landscape-swap); dialog subtitle (`AlertDialog.java:810`); compact popup-menu row (`ActionBarMenuSubItem.java:198`) |
| `caption` | 13dp / regular | `TextCell` subtitle (`TextCell.java:105`); `HeaderCell` second line (`HeaderCell.java:106`); Bulletin subtitle (`Bulletin.java:1423-1424` etc.); `UserCell` compact-mode status (`UserCell.java:483`, name goes 15 at `:481`); popup-menu subtext (`ActionBarMenuSubItem.java:365`); action-bar "N selected" (`ActionBarMenuItem.java:98`) |
| `captionEmphasis` | 13dp / medium | Standalone counter badge (`CounterView.java:134-135`); large unread badge `dialogs_countTextPaint2` (`Theme.java:8364-8365,8372`); archive label (`Theme.java:8403,8477`) |
| `micro` | 12dp / regular | Chat-list timestamp (`Theme.java:8472`; bold variants same size `:8473-8476`); button sub-text (`ButtonWithCounterView.java:133`) |
| `microEmphasis` | 12dp / medium | Small unread badge `dialogs_countTextPaint` (`Theme.java:8363,8371`); button counter when filled (`ButtonWithCounterView.java:139-140`; 14 when outline, `:209`) |
| `tagSmall` | 11dp / medium | Small archive label (`Theme.java:8405,8478`) |
| `tag` | 10dp / medium | Chat-folder tag chips (`Theme.java:8409,8481`) |

Rules of thumb the table encodes:
- Weight is binary: w400 or w500. w700 never appears in the core UI.
- Emphasis at the same size (name vs message, badge vs timestamp) is done with Roboto Medium, never by size bump.
- Badges/tags (10-13dp) are always medium; captions/subtitles (13-14dp) are regular unless they are headers/buttons.
- Sizes are `dp` set via `TypedValue.COMPLEX_UNIT_DIP` or `dp()` — map 1:1 to Flutter logical px.
- Pin `TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false)` per ARCHITECTURE.md §5 — Android `TextView` vs Flutter `Paragraph` metrics differ.

---

## 2. Motion

Interpolator dictionary (`ui/Components/CubicBezierInterpolator.java:11-22`):

| Name | cubic-bezier | Flutter |
|---|---|---|
| `DEFAULT` | (0.25, 0.1, 0.25, 1) | `Curves.ease` (identical control points) |
| `EASE_OUT` | (0, 0, 0.58, 1) | `Cubic(0, 0, .58, 1)` |
| `EASE_OUT_QUINT` | (0.23, 1, 0.32, 1) | `Curves.easeOutQuint`-alike; use `Cubic(.23, 1, .32, 1)` |
| `EASE_IN` | (0.42, 0, 1, 1) | `Curves.easeIn` (identical) |
| `EASE_BOTH` | (0.42, 0, 0.58, 1) | `Curves.easeInOut` (identical) |
| `EASE_OUT_BACK` | (0.34, 1.56, 0.64, 1) | `Cubic(.34, 1.56, .64, 1)` |
| `StandardDecelerate` | PathInterpolator(0, 0, 0, 1) | `Cubic(0, 0, 0, 1)` |
| `DecelerateInterpolator(1.5f)` (`ActionBarLayout.java:577`) | `1-(1-t)^3` | exactly `Curves.easeOutCubic`'s math; use `Cubic(0.215, 0.61, 0.355, 1)` or a custom `Curve` computing `1-pow(1-t, 3)` |
| `OvershootInterpolator(1.02f)` (`ActionBarLayout.java:578`) | tension 1.02 | `Curves.easeOutBack`-family; custom curve `(t-1)^2*((T+1)(t-1)+T)+1`, T=1.02 |
| `AccelerateDecelerateInterpolator` (`:579`, also `ObjectAnimator` default) | cos-based ease-in-out | `Curves.easeInOut` approximation |

### 2.1 Fragment push/pop — `ui/ActionBar/ActionBarLayout.java`

**Standard push (open, non-preview).** Manual frame loop `startLayoutAnimation` (`:1816-1926`):
- Duration **150ms** (`float duration = preview && open ? 190.0f : 150.0f;`, `:1839`), frame dt clamped to 18ms (`:1835-1836`).
- Curve: `decelerateInterpolator` = `DecelerateInterpolator(1.5f)` (`:577`, applied `:1882`).
- Incoming fragment (`containerView`): `alpha 0→1` (`:1886`) **and** `translationX dp(48)→0` (`:1901`). The outgoing fragment underneath does not move.
- So the standard transition is a **48dp slide-in + crossfade**, not a full-width iOS push.

**Standard pop (back button, animated).** Same 150ms loop; outgoing fragment (`containerViewBack` after swap): `alpha 1→0` (`:1905`), `translationX 0→dp(48)` (`:1916`).

**Dim + edge shadow (drawn during any horizontal offset, i.e. gesture-driven `innerTranslationX`).** `drawChild` override (`:1189-1222`):
- Scrim over the *back* layer: `scrimPaint.setColor(Color.argb((int)(120 * opacity), 0, 0, 0))` where `opacity = clamp(widthOffset/width, 0, 0.8)` (`:1214-1215`). Max dim = `120*0.8 = 96/255 ≈ 37.6%` black when the top page is fully covering; linearly proportional to how much of the top page still covers.
- Edge shadow on the moving page's left edge: `layer_shadow` drawable, alpha ramps `255 * widthOffset / dp(20)` clamped (`:1192`), i.e. fully opaque once the page has moved 20dp; skipped on API 31+ except sheets (`:1202`).

**Swipe-back gesture (classic).**
- Start threshold: `dx >= AndroidUtilities.getPixelsInCM(0.4f, true) && dx/3 > dy` (`:1448`); flingstart alternative `velX >= 3500 && velX > |velY|` (`:1483`).
- During drag: `containerView.translationX = dx` — page tracks the finger full-width (`:1469-1470`).
- Release decision (`:1498`): dismiss if `x > width/3` (or fling), i.e. `backAnimation = x < width/3 && (velX < 3500 || |velX| < |velY|)`.
- Commit-back: animate to `width`, duration `max(200ms × remaining/width, 50ms)` (`:1616-1621`). Cancel: animate to 0, duration `max(320ms × x/width, 120ms)` (`:1628-1633`). No explicit interpolator in the classic path → `ObjectAnimator` default `AccelerateDecelerateInterpolator`.

**Predictive back (Android 14 system gesture / this branch's "new back").**
- `onBackProgress(t)`: `dx = dp(56) * StandardDecelerate(t)` — the page peels only 56dp (`:1577-1583`).
- Touch-driven variant maps drag to `dx/width * 5*dp(56)` (`:1465-1467`).
- Commit: duration `max(..., 380ms)`, cancel `max(..., 320ms)`, both `EASE_OUT_QUINT` (`:1617-1637`).

**Preview (peek & pop).**
- Open: **190ms**, `OvershootInterpolator(1.02)` (`:1839,1877`); `scale 0.7→1.0` + fade (`:1888-1889`); dim `previewBackgroundDrawable` alpha `0x2e` (46/255 ≈ 18%) (`:1896`); attached preview menu translates `dp(40+30)` and scales 0.95→1 (`:1891-1894`).
- Close: `EASE_OUT_QUINT` (`:1879`), back layer `scale 0.9→1.0` + fade (`:1907-1908`).
- Promote preview→full: `scaleX/Y 1.0→1.05→1.0`, **200ms**, `cubic-bezier(0.42, 0, 0.58, 1)` (`:2516-2519`).

**Root-level layout fade (`useAlphaAnimations`, first fragment of an overlay layout).**
- Open: `alpha 0→1` + `scale 0.9→1`, **200ms**, `EASE_OUT_QUINT` (`:2164-2178`).
- Close: `alpha 1→0` + `scale 1→0.9`, **200ms**, `AccelerateDecelerateInterpolator` (`:2716-2726`); background view fades 180ms (`:2857`).

**Flutter mapping.** One `TgPageRoute`/`PageTransitionsBuilder`: `transitionDuration: 150ms`; primary animation drives `Opacity(0→1)` × `Transform.translate(dx: 48*(1-easeOutCubic(t)))`; `secondaryAnimation` unused for movement (previous page static) but should drive the ≤37.6% black scrim on the page below during user-gesture pops. Gesture pop mirrors `CupertinoRouteTransitionMixin`'s drag mechanics with commit threshold width/3 and the duration formulas above.

### 2.2 BottomSheet open/close physics — `ui/ActionBar/BottomSheet.java`

- Defaults: `openDuration = 400`, `openInterpolator = EASE_OUT_QUINT` (`:210-211`); `dimBehind = true`, `dimBehindAlpha = 51` (= 20% black, `:218-219`).
- Open (`:1701-1746`): start at `translationY = containerViewHeight + keyboardHeight + dp(10) + min(navBarHeight, bottomInset)` (`:1710-1713`); animate `translationY→0`, dim `0→51`, nav-bar alpha `→1` together, **400ms EASE_OUT_QUINT**, `startDelay 20ms` (`:1745`, 0 when waiting for keyboard).
- `transitionFromRight` variant (sub-sheet slide): `translationX dp(48)→0` + `alpha 0→1`, **250ms `DEFAULT`** (`:1705-1707,1738-1740`); its close is **200ms `DEFAULT`** (`:2028-2030`).
- Dismiss (`:1992-2034`): `translationY → containerViewHeight + keyboard + dp(10) + insets`, dim `→0`, **250ms `EASE_OUT`** (`:2032-2033`).
- Button-row dismiss (`dismissWithButtonClick`): **180ms** `EASE_OUT` (330ms for the call cell type) (`:1870-1871`).
- Drag release (`checkDismiss`, `:375-399`): dismiss unless `translationY < 0.8cm && (velY < 3500 || |velY| < |velX|)`; snap-back duration is proportional: `250ms × translationY / 0.8cm`, `DEFAULT` curve (`:398-399`).
- The 0.4cm/0.8cm thresholds are physical (`getPixelsInCM`) — in Flutter approximate with `0.4cm ≈ 25.2` / `0.8cm ≈ 50.4` logical px at 160dpi-equivalent, or use `kTouchSlop`-scaled values.

### 2.3 Dialog (AlertDialog) fade/scale

- Window path: `AlertDialog` extends `Dialog(context, R.style.TransparentDialog)` (`AlertDialog.java:301`); `TransparentDialog` (`res/values/styles.xml:139-153`) sets no `windowAnimationStyle`, so it inherits the **system dialog fade** from `@android:style/Theme.Dialog` (~150ms decelerate fade in/out at the window level).
- Dim: `dimAlpha = 0.5f` black via `WindowManager.LayoutParams.dimAmount` + `FLAG_DIM_BEHIND` (`AlertDialog.java:210,1241-1243`).
- In-layout variant `AlertDialogDecor.java` (modern, used when attached inside the view tree): dim view `Color.BLACK × dimAmount`, fades alpha 0→1 over **`DIM_DURATION = 300ms`** on show and 1→0 on dismiss (`AlertDialogDecor.java:39,52-54,103-105,193-196`).
- Spinner-type dialog content pops: `scale 0→1`, **190ms**, `OvershootInterpolator(1.3)` (`AlertDialog.java:327-334`).
- Generic XML scale-in used by assorted popups: `scale 0.5→1 + alpha 0→1`, **150ms** (`res/anim/scale_in.xml`).
- Recommended Flutter constants: barrier black 50%, barrier/dialog fade 150ms (window parity) or 300ms if replicating the decor dim, content `ScaleTransition 0.95→1` + fade with `Curves.ease` — Telegram has no content scale on the standard alert, only the fade, so a pure `FadeTransition` is the faithful default.

### 2.4 Popup/context menu (for the upcoming ActionBarPopupWindow port)

- Open: `backScaleY 0→1` + `backAlpha 0→255` with per-item cascade — each row `translationY (1-t)*dp(-6)` + alpha, staggered via `AndroidUtilities.cascade(t, index, count, 4)`; total duration **`150 + 16 × visibleItemCount` ms** (`ActionBarPopupWindow.java:880-896,965`).
- Dismiss: **150ms** default (`dismissAnimationDuration`, `:69,1063-1068`).

---

## 3. Hairline / divider conventions

- Single shared paint: `Theme.dividerPaint`, `strokeWidth(1)` — **1 physical pixel, not 1dp** (`Theme.java:3089,8212-8214`). In Flutter: `1 / MediaQuery.devicePixelRatioOf(context)` logical px (the kit's `dialog_cell.dart` separator already does this).
- Color: theme key **`divider`** (index 101; `Theme.java:3467`, name map `ThemeColors.java:944`), set on the paint at `Theme.java:8302-8305`. Light default `0xFFD9D9D9` (`ThemeColors.java:136`); night theme overrides to opaque black `0xFF000000` (`assets/night.attheme:101`, `divider=-16777216`). Fallback: `table_border → divider` (`Theme.java:4477`).
- Per-cell override hook: `resourcesProvider.getPaint(Theme.key_paint_divider)` (`"paintDivider"`, `Theme.java:4275,10547`; usage `TextCell.java:830-834`).
- Placement: drawn in `onDraw` as a line at `y = getMeasuredHeight() - 1`, RTL-mirrored, only when the cell's `needDivider`/`useSeparator` flag is set (owner list decides — no automatic last-item suppression widget-side).
- Left insets (light up to text column, full-bleed on the right):
  - `DialogCell`: `dp(72)` (`messagePaddingStart`, `DialogCell.java:170`, draw `:4774-4796`); becomes full-bleed (`left = 0`) for the archive-adjacent separator cases (`fullSeparator`, `:4776-4780`).
  - `UserCell`: `dp(68)` (`UserCell.java:773`).
  - `TextCell`: `dp(72)` in-dialogs / `dp(58)` with icon / `dp(20)` text-only (`TextCell.java:835`).
  - `TextSettingsCell`: `dp(71)` with icon / `dp(20)` (`TextSettingsCell.java:367-368`).
- Section-gap "divider" (the fat gray band) is a different mechanism — `ShadowSectionCell` with `greydivider*` drawables, already ported.

---

## 4. Suggested Flutter tokens (summary)

```dart
abstract final class TgTextStyles {
  // all "medium" = FontWeight.w500 (rmedium.ttf), never w700
  static const title          = /* 20, w500 */;
  static const titleGlass     = /* 17, w500 */;   // glass app bar on this branch
  static const input          = /* 18, w400 */;
  static const cellTitle      = /* 17, w500 */;   // dialog-list name
  static const body           = /* 16, w400 */;
  static const bodyEmphasis   = /* 16, w500 */;   // user name, dialog buttons
  static const bodySecondary  = /* 15, w400 */;
  static const tab            = /* 15, w500 */;
  static const label          = /* 14, w500 */;   // section header, button
  static const subtitle       = /* 14, w400 */;
  static const caption        = /* 13, w400 */;
  static const captionEmphasis= /* 13, w500 */;   // badges
  static const micro          = /* 12, w400 */;   // timestamps
  static const microEmphasis  = /* 12, w500 */;   // small badges
  static const tag            = /* 10, w500 */;   // folder tags
}

abstract final class TgMotion {
  static const pageDuration = Duration(milliseconds: 150);
  static const pageSlide = 48.0;                       // dp, in + fade
  static const pageCurve = Cubic(0.215, 0.61, 0.355, 1); // DecelerateInterpolator(1.5)
  static const pageScrimMax = 0.376;                   // 120/255 * 0.8 black
  static const sheetOpenDuration = Duration(milliseconds: 400);
  static const sheetOpenDelay = Duration(milliseconds: 20);
  static const sheetCloseDuration = Duration(milliseconds: 250);
  static const easeOutQuint = Cubic(0.23, 1, 0.32, 1);
  static const easeOut = Cubic(0, 0, 0.58, 1);
  static const sheetDim = 0.2;                         // 51/255
  static const dialogDim = 0.5;
  static const dialogDimDuration = Duration(milliseconds: 300);
  static const menuOpenBase = Duration(milliseconds: 150); // +16ms per item
}
```
