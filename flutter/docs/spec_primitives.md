# Telegram Android → Flutter port: Primitive specs (Button, Avatar, Progress, Text field)

Extracted from Java sources for a faithful port. All paths relative to
`/home/user/Telegram/TMessagesProj/src/main/java/org/telegram/`.

Sources cited below:
- **BWC** = `ui/Stories/recorder/ButtonWithCounterView.java` (672 L) — THE canonical modern button (380 uses / 103 files)
- **AD** = `ui/ActionBar/AlertDialog.java` — flat text-button convention (full dialog spec: `spec_dialog_menu.md`)
- **AV** = `ui/Components/AvatarDrawable.java`
- **RPV** = `ui/Components/RadialProgressView.java`
- **CPD** = `ui/Components/CircularProgressDrawable.java`
- **LPV** = `ui/Components/LineProgressView.java`
- **ETB** = `ui/Components/EditTextBoldCursor.java`
- **OTC** = `ui/Components/OutlineTextContainerView.java`
- **SSLA** = `ui/Components/ScaleStateListAnimator.java`
- **TC** = `ui/ActionBar/ThemeColors.java`

Units: 1 Android dp = 1 Flutter logical px. `AndroidUtilities.bold()` = Roboto
Medium (`fonts/rmedium.ttf`). Curves already in `TgCurves`:
`EASE_OUT_QUINT`=(.23,1,.32,1), `EASE_BOTH`=(.42,0,.58,1), `DEFAULT`=(.25,.1,.25,1).
Android `OvershootInterpolator(t)` = back-out with tension t;
`DecelerateInterpolator` ≈ ease-out quad, `AccelerateInterpolator` ≈ ease-in quad,
`FastOutSlowInInterpolator` = Material standard curve (.4,0,.2,1).

### Theme-token defaults referenced in this spec (TC unless noted; `TELEGRAM_COLOR = 0xFF229AF0` TC:14, `TELEGRAM_COLOR_TEXT = 0xFF298ACF` TC:15, `DEFAULT_BLACK_TEXT = 0xFF1A1D21` TC:16)

| key | default | TC line |
|---|---|---|
| `featuredStickers_addButton` | `0xFF229AF0` | 596 |
| `featuredStickers_buttonText` | `0xffffffff` | 600 |
| `buttonNeutral` / `buttonNeutralText` | `0xFFE4E4E4` / `0xFF1A1D21` | 602-603 |
| `listSelector` | `0x0f000000` | 129 |
| `dialogButton` | `0xFF298ACF` | 50 |
| `dialogButtonSelector` | `0x0f000000` | 51 |
| `text_RedBold` / `text_RedRegular` | `0xffcc4747` / `0xffcc2929` | 97 / 96 |
| `progressCircle` | `0xff1c93e3` | 83 |
| `dialog_inlineProgress` / `...Background` | `0xff6b7378` / `0xf6f0f2f5` | 56 / 55 |
| `dialogLineProgress` / `...Background` | `0xff527da3` / `0xffdbdbdb` | 48-49 |
| `avatar_text` | `0xffffffff` | 152 |
| `windowBackgroundWhiteInputField` | `0xffdbdbdb` | 113 |
| `windowBackgroundWhiteInputFieldActivated` | `0xFF229AF0` | 114 |
| `windowBackgroundWhiteHintText` | `0xffa8a8a8` | 108 |
| `windowBackgroundWhiteBlackText` | `0xFF1A1D21` | 107 |
| `windowBackgroundWhiteValueText` | `0xFF298ACF` | 109 |

---

## 1. Filled button — `ButtonWithCounterView`

`FrameLayout implements Loadable` (BWC:40). Two visual modes via the `filled`
constructor flag / `setFilled` (BWC:90-101): **filled** (default) and
**text/outline-less** (transparent, tinted text).

### 1.1 Geometry
- **Height 48dp** — not set in the class; every call site places it at 48dp
  (grep of `createLinear/createFrame` around `new ButtonWithCounterView`: 48 in
  all matches, typically `MATCH_PARENT × 48` with 12-20dp side margins).
- **Corner radius 8dp** default (`radiusDp = 8`, BWC:44); `setRound()` → 24dp
  stadium (BWC:67-70); `setRoundRadius(dp)` arbitrary (BWC:80-88).
- Width: match-parent by convention; optional wrap-content
  (`setUseWrapContent`/`setMinWidth`, min-width clamp, BWC:650-663).

### 1.2 Colors / variants (BWC:114-119, 179-192)
- **Filled**: background rounded-rect `featuredStickers_addButton`; label
  `featuredStickers_buttonText`; label typeface **bold (Roboto Medium)**;
  ripple = `listSelector` masked to the same rounded rect (BWC:185).
- **Text mode** (`filled=false`): no background, label
  `featuredStickers_addButton`, **regular** typeface (BWC:96-98); ripple =
  label color at **10% alpha** rounded-rect (BWC:187, 170).
- **Neutral** (`setNeutral()`, BWC:72-78): filled with `buttonNeutral` bg /
  `buttonNeutralText` label — the "secondary/cancel" filled button.
- Custom: `setColor(int)` swaps the fill (BWC:164-172).

### 1.3 Label
- `AnimatedTextDrawable`, **14dp**, centered (BWC:121-128). Text changes
  animate per-glyph over **250ms EASE_OUT_QUINT** with vertical move-down
  (BWC:122, 250-257).
- Optional **subText** line: 12dp, alpha 200/255 (BWC:130-134, 468). When
  visible the main label shifts up 7dp (BWC:534) and subText sits +11dp below
  center (BWC:548), scaling in from 0.1 at its bottom edge; show/hide 200ms
  `DEFAULT` curve (BWC:288-318).

### 1.4 Press feedback
`ScaleStateListAnimator.apply(this, .02f, 1.2f)` (BWC:109): pressed → scale
**0.98** over **80ms**; released → back to 1.0 over **350ms** with
`OvershootInterpolator(1.2)` (SSLA:15-33).

### 1.5 Loading state (spinner swap)
`setLoading(bool)` (BWC:326-354): `loadingT` animates over **320ms
EASE_OUT_QUINT**. Draw (BWC:504-521):
- Spinner = `CircularProgressDrawable` tinted the **label color** (BWC:506;
  see §4.2 for its metrics), centered, sliding **down from −24dp** as it fades
  in (`y = (1−loadingT)·24dp`, alpha = loadingT).
- Label+counter simultaneously slide **up 24dp** and squash vertically to
  ×0.6 (`scale(1, 1−.4·loadingT)`) while fading out (BWC:517-521, 535).
- Alternative shimmer mode `setFlickeringLoading(true)`: instead of a spinner,
  a `LoadingDrawable` sweep over the fill — colors white 2% → white 37.5%
  alpha, gradientScale 2, no stroke (BWC:478-502).

### 1.6 Counter variant
`setCount(int|String, animated)` draws a pill after the label (BWC:558-596):
- Pill: height **18dp**, corner radius **10dp** (4dp when `withCounterIcon`),
  fill = `featuredStickers_buttonText` paint (i.e. **white pill on the blue
  button**) (BWC:118-119, 571-575).
- Count text: 12dp **bold**, colored `backgroundColor` (the button fill —
  inverse text) (BWC:136-142, 190).
- Gap label→pill: 5dp (filled pill) / 2dp (unfilled) (BWC:559); pill min
  content width 9dp + 4dp+4dp padding (BWC:561); total reserved width
  `dp(15.66) + countTextWidth` faded by counter alpha (BWC:527, 645).
- Appear/disappear: counter alpha `AnimatedFloat` **350ms EASE_OUT_QUINT**
  (BWC:50-51); on count change a bounce scale `OvershootInterpolator(2.0)`
  **200ms** from the pill center (BWC:364-387); digits roll via
  `AnimatedTextDrawable`.
- `setCountFilled(false)`: no pill — bare count text 14dp in label color at
  50% alpha (BWC:206-215, 579). Used by `setTimer(seconds, onDone)` which
  ticks the count down 1/s and re-enables the button at 0 (BWC:219-240).
- Digits are space-grouped (`formatNumber(count, ' ')`, BWC:413).

### 1.7 Disabled
`setEnabled` animates content alpha between ×0.5 and ×1.0 (lerp on `enabledT`,
BWC:432-448, applied at 535, 552, 572) — stock ValueAnimator (300ms,
accel/decel). Background does not change.

## 2. Flat dialog text button — AlertDialog convention

The de-facto "text button" of the app (AD:1060-1096; same for
negative/neutral). Port as `TgTextButton`:

- Container row: LinearLayout **52dp** tall, padding 8dp all around, buttons
  right-aligned, **8dp gap** (AD:1050-1058, 937-950).
- Each button: **height 40dp**, `minWidth 64dp`, horizontal padding 12dp,
  text **16dp bold (Roboto Medium)**, color `dialogButton`
  (default `0xFF298ACF`), gravity center (AD:1074-1086). **No all-caps
  transform** — label rendered as given.
- Background: ripple-only rounded rect, radius **20dp**, in the text color
  (`Theme.getRoundRectSelectorDrawable(dp(20), color)` — ~12% alpha ripple, no
  fill) (AD:1071, 1081).
- Max width per button: `(dialogWidth − 24dp)/2` (AD:394-397). If combined
  width > screenWidth − 64dp the row stacks **vertically**, each button
  match-parent with 6dp top margin (AD:934-953, 1083-1084, 1224).
- Disabled: alpha 0.5 (AD:1063-1066). Destructive: swap text color to
  `text_RedBold` (`redPositive()`, AD:231-236). Loading: buttons are
  `TextViewWithLoading` — `setLoading` swaps label for an inline spinner
  (AD:1324-1330).
- Dialog **list item row** (`AlertDialogCell`, AD:238-294): height **48dp**,
  horizontal padding 23dp, text 16dp `dialogTextBlack`, optional leading icon
  (40dp slot, tinted `dialogIcon`) pushing text padding to 56dp; ripple
  `dialogButtonSelector`.

---

## 3. Avatar — `AvatarDrawable`

Circle (default) or rounded-rect if `roundRadius > 0` (AV:586-600, 775-777),
filled with a **vertical two-stop LinearGradient** top→bottom, `CLAMP`
(AV:571-578), initials or a themed icon on top.

### 3.1 Gradient pair table (index 0-6)
`keys_avatar_background` / `keys_avatar_background2` order: **Red, Orange,
Violet, Green, Cyan, Blue, Pink** (Theme.java:3539-3540). Defaults (TC:158-171):

| # | name | top (`avatar_backgroundX`) | bottom (`avatar_background2X`) |
|---|---|---|---|
| 0 | Red | `0xffFF845E` | `0xffD45246` |
| 1 | Orange | `0xffFEBB5B` | `0xffF68136` |
| 2 | Violet | `0xffB694F9` | `0xff6C61DF` |
| 3 | Green | `0xff9AD164` | `0xff46BA43` |
| 4 | Cyan | `0xff5BCBE3` | `0xff359AD4` |
| 5 | Blue | `0xff5CAFFA` | `0xff408ACF` |
| 6 | Pink | `0xffFF8AAC` | `0xffD95574` |

Special pairs: Saved/Replies/My-suggestion `avatar_backgroundSaved`
`0xff69BDF9` → `avatar_background2Saved` `0xff409FE1` (TC:154-155, AV:260-263);
Archived flat `0xffB8C2CC`, archived-hidden flat `TELEGRAM_COLOR` (TC:156-157).
A parallel `keys_avatar_nameInMessage[7]` exists for in-chat name tinting
(same index, Theme.java:3541, AV:212-214).

### 3.2 Color selection
- **By peer id**: `index = abs(id % 7)` (AV:179-181, 402-403, 445-446).
- **By explicit peer color** (accounts with custom colors): hue of color1 →
  index via `getPeerColorIndex`: hue ≥345 or <29 → 0 red; <67 → 1 orange;
  <140 → 3 green; <199 → 4 cyan; <234 → 5 blue; <301 → 2 violet; else 6 pink
  (AV:166-177). When the peer has an actual profile color, color1/color2 come
  from the peer palette directly (AV:430-437).
- 4-stop `advancedGradients` table (7 entries, AV:109-117) is used only for
  the profile-header/constructor style and the Anonymous
  (`0xFF837CFF,0xFFB063FF,0xFFFF72A9,0xFFE269FF`) / My-Notes
  (`0xFF4D8DFF,0xFF2BBFFF,0xFF20E2CD,0xFF0EE1F1`) types (AV:313-324) — NICE,
  not needed for list avatars.

### 3.3 Initials extraction (AV:390-396, 509-542)
- `takeFirstCharacter`: first **grapheme** — a leading emoji run is kept whole,
  else first code point (surrogate-safe).
- Symbols = first char of `firstName` + first char of the **last word of
  lastName**, joined with zero-width non-joiner `‌`.
- No lastName → first char of firstName + first char of the **last word** of
  firstName (skips to text after the last space, only if multi-word).
- Empty firstName → lastName promoted to firstName first (AV:455-458).
- `custom` string overrides everything. Rendered **UPPERCASE** (AV:717).

### 3.4 Text scaling
- Paint: **bold (Roboto Medium), 18dp**, color `avatar_text` (white)
  (AV:130-133, 566). Laid out once at 18dp, then the canvas is scaled by
  `size / 50dp` around the center (AV:736-738) — i.e. **initials are designed
  for a 50dp avatar and scale linearly with diameter** (56dp avatar → 20.16dp
  effective). `setTextSize` exists for custom cases (AV:374-376);
  `setScaleSize` scales the icon types (AV:247-249, 685-689).

---

## 4. Progress indicators

### 4.1 `RadialProgressView` — standalone spinner (indeterminate + determinate)
- **Arc box 40dp** default (`size = dp(40)`, RPV:63; the view centers it,
  RPV:228-231), `setSize` to override — AlertDialog spinner uses 32dp in an
  86dp card of `dialog_inlineProgressBackground` r=18dp (AD:881-888).
- **Stroke 3dp**, round cap, style STROKE (RPV:68-71); color key
  **`progressCircle`** (default `0xff1c93e3`, RPV:65).
- **Rotation**: continuous `radOffset += 360·dt/2000` → one revolution / **2s**
  (RPV:41, 134).
- **Indeterminate sweep** (`noProgress=true`, RPV:150-169): alternating 500ms
  phases (`risingTime = 500`, RPV:42) — grow `4° + 266°·accelerate(t)` then
  shrink `4° − 270°·(1−decelerate(t))` (negative sweep) with a +270° offset
  jump between phases; sweep oscillates 4°↔270°.
- **Determinate** (`setProgress`): sweep = `max(4°, 360°·progress)`, progress
  eased over **200ms decelerate** (RPV:189-201); rotation keeps spinning.
- `toCircle` morph to full ring: +360° over 220ms in, back over 400ms out
  (RPV:138-148).

### 4.2 `CircularProgressDrawable` — in-button spinner
What `ButtonWithCounterView` and `TextViewWithLoading` embed.
- **Arc diameter 18dp, thickness 2.25dp**, round cap+join, default color white
  (CPD:19-20, 22-27, 52-56); intrinsic bounds = size+thickness, centered in
  whatever bounds are set (CPD:86-96, 116-123).
- Material-style head/tail animation, period **5400ms** (CPD:37-50): both ends
  advance linearly `1520°·t/5400` (tail leads head by 20°), plus **4 pulses per
  period** of 250° each with `FastOutSlowIn` over 667ms — head pulses at
  `t−i·1350`, tail at `t−(667+i·1350)`. Net: sweep breathes ~20°↔~270° while
  rotating ~5.06 rev/period.

### 4.3 `LineProgressView` — determinate line
- Filled rounded bar: radius = **height/2**, drawn full-height of the view
  (LPV:113-121); canonical height **4dp** (AlertDialog places it
  `MATCH_PARENT × 4`, hmargins 24, AD:865, 474).
- Track (`setBackColor`) drawn only while progress < 1 (LPV:110-116); colors in
  dialogs: progress `dialogLineProgress` `0xff527da3` on
  `dialogLineProgressBackground` `0xffdbdbdb` (AD:863-864); percent label 14dp
  bold `dialogTextGray2` (AD:867-872).
- Progress animates over **300ms decelerate** (LPV:57-68); at 1.0 the whole bar
  **fades out over 200ms** (LPV:71-77).
- A `CellFlickerDrawable` shimmer sweeps the filled part (speedScale 0.8,
  repeatProgress 1.2, LPV:123-133) — optional polish.

---

## 5. General text field — `EditTextBoldCursor` (+ `OutlineTextContainerView`)

The base for every form/login/dialog input. Port as `TgTextField` with an
`outlined` variant.

### 5.1 Cursor
- Rectangular block cursor, **width 2dp default** (`cursorWidth = 2.0f`,
  ETB:121, `setCursorWidth`), **height `cursorSize` default 24dp** (ETB:416,
  `setCursorSize`) vertically centered on the line (ETB:926-927).
- Default color hardcoded `0xff54a1db` (ETB:360, 396); `setCursorColor`
  overrides. Blink: 500ms on / 500ms off (`(uptime − showCursor) % 1000 < 500`,
  ETB:896).
- **Forms convention** (ChangeNameActivity:96-111, repeated in
  ChangeBio/Passport): text 18dp `windowBackgroundWhiteBlackText`, hint color
  `windowBackgroundWhiteHintText`, cursor color = text color, cursorSize
  **20dp**, cursorWidth **1.5dp**, row height 36dp with 24dp side margins.

### 5.2 Underline (`setLineColors(color, active, error)`, ETB:490-500, 977-1023)
- Inactive: **1dp** line in `windowBackgroundWhiteInputField` (`0xffdbdbdb`)
  across the full width, sitting ~6dp under the text baseline
  (`lineY = hint bottom + 6dp`, ETB:605; bottom−2dp when no hint, ETB:608).
- Focused: **2dp** line in `windowBackgroundWhiteInputFieldActivated`
  (`0xFF229AF0`) that **expands horizontally from the touch x** (falls back to
  center) to full width — activeness eased **150ms EASE_BOTH**, thickness
  animates 0→2dp on the reverse transition (ETB:994-1022).
- Error (`setErrorText` non-empty): line snaps to **2dp** in the error color —
  callers pass `text_RedRegular` (`0xffcc2929`) (ETB:980-983; usage grep).
  Error caption paint is **11dp** (ETB:331-332, drawing currently commented
  out — callers render the error label themselves).

### 5.3 Hint & floating label
- Hint drawn only while empty (ETB:753); visibility fades linearly over
  **150ms** (`hintAlpha ± dt/150`, ETB:756-775); positioned on the text line,
  RTL-aware (ETB:808-813).
- **Floating-label mode** `setTransformHintToHeader(true)`: when focused or
  non-empty, the hint animates to a header — **scale ×0.7**
  (`1 − 0.3·progress`), **translate up 22dp**, color blends `hintColor` →
  `headerHintColor` — over **200ms EASE_OUT_QUINT** (ETB:667-686, 814-827).
  Callers use `windowBackgroundWhiteHintText` → `windowBackgroundWhiteBlueHeader`
  (= `0xFF298ACF`, TC:112).
- Hint text can hot-swap with a per-substring slide animation
  (`setHintText(text, animated)`, ETB:621-651) — NICE.

### 5.4 Outlined variant — `OutlineTextContainerView` (login/modern forms)
Wraps the EditText and draws a Material-outlined frame (OTC):
- Rounded-rect outline **radius 8dp** (OTC:211); stroke idle
  `max(2px, 0.5dp)` → focused **1.6667dp** (OTC:64-65); top padding 6dp
  reserves label space (OTC:87).
- Label: 16dp (OTC:81); floats from field-center to a **gap cut in the top
  stroke** at scale **0.75** (OTC:196-227); left inset 14dp, 4dp text side-gaps
  (OTC:23).
- Colors (OTC:124-129): label blends `windowBackgroundWhiteHintText` →
  `windowBackgroundWhiteValueText`; stroke blends
  `windowBackgroundWhiteInputField` → `windowBackgroundWhiteInputFieldActivated`;
  error blends both toward `text_RedBold`.
- All transitions are springs: stiffness **500**, damping 1 (no bounce), on
  0→100 scaled progress (OTC:25, 173-184).

---

## Port mapping (telegram_ui)

| Java | Flutter widget | Notes |
|---|---|---|
| ButtonWithCounterView | `TgButton` | `filled`/`text`/`neutral` variants, `loading`, `count`, `subText`, `timer`; 48×∞, r8 |
| AlertDialog buttons | `TgDialogButton` (or `TgButton.dialog`) | 40dp flat, 16 bold, r20 ripple |
| AvatarDrawable | `TgAvatar` | fills `DialogCell.avatar` / `UserCell.avatar` slots; `TgAvatarColors.pairFor(id)` |
| RadialProgressView | `TgProgressIndicator` | indeterminate default, `.progress` for determinate |
| CircularProgressDrawable | `TgButtonSpinner` painter | internal to TgButton / dialog buttons |
| LineProgressView | `TgLinearProgress` | 4dp bar, fade-out on completion |
| EditTextBoldCursor(+Outline...) | `TgTextField` | `underline` (default) and `outlined` styles |
