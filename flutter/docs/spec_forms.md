# Telegram Android → Flutter port: Form-control specs (CheckBox, Radio, Slider, Switch parity)

All paths relative to `/home/user/Telegram/TMessagesProj/src/main/java/org/telegram/`.
Shared curve constants (Components/CubicBezierInterpolator.java L11-14): `DEFAULT`=(.25,.1,.25,1), `EASE_OUT`=(0,0,.58,1), `EASE_OUT_QUINT`=(.23,1,.32,1), `EASE_IN`=(.42,0,1,1). Quad easings (Components/Easings.java L12-13): `easeInQuad`=(.55,.085,.68,.53), `easeOutQuad`=(.25,.46,.45,.94). `ObjectAnimator` with no interpolator set runs Android's default `AccelerateDecelerateInterpolator`.
Haptic used by the slider: `AndroidUtilities.vibrateCursor` = `HapticFeedbackConstants.TEXT_HANDLE_MOVE` with `FLAG_IGNORE_VIEW_SETTING` (messenger/AndroidUtilities.java L6543-6549).

Default theme color values referenced below (ui/ActionBar/ThemeColors.java; `TELEGRAM_COLOR = 0xFF229AF0`, L14):

| key | default | line |
|---|---|---|
| `checkbox` | `0xff5ec245` | L620 |
| `checkboxCheck` | `0xffffffff` | L621 |
| `checkboxDisabled` | `0xffb0b9c2` | L622 |
| `radioBackground` | `0xffb3b3b3` | L131 |
| `radioBackgroundChecked` | `0xff229AF0` | L132 |
| `player_progress` | `0xff54AAEB` | L559 |
| `player_progressBackground` | `0xffEBEDF0` | L557 |
| `player_progressCachedBackground` | `0xffC5DCF0` | L558 |
| `player_time` | `0xff8c9296` | L556 |
| `switchTrack` | `0xffa6adb3` | L115 |
| `switchTrackChecked` | `0xff229AF0` | L116 |
| `switch2Track` | `0xfff57e7e` | L123 |
| `switch2TrackChecked` | `0xff229AF0` | L124 |
| `fill_RedNormal` | `0xffeb5e5e` | L98 |
| `dialogBackground` | `0xffffffff` | L24 |

---

## 1. CheckBox — ui/Components/CheckBoxBase.java (engine) + ui/Components/CheckBox2.java (View wrapper)

`CheckBoxBase` is a canvas-only drawing object bound to a parent view; `CheckBox2` is the canonical widget wrapper (drawn in `onDraw`, CheckBox2.java L110-123; bounds bound to the whole view in `onLayout`, L104-107).

### Size & paints
- Size is a constructor parameter in **dp** (`CheckBoxBase(parent, sz, rp)`, L109-112). Canonical sizes across the app (grep of `new CheckBox2(context, N`): **21dp** (28 call sites — lists/settings), **24dp** (13 — photo picker/media grid), rare 20/22/26.
- `checkPaint` (the check mark): STROKE, **ROUND cap + ROUND join**, stroke width **1.9dp** (L116-120).
- `backgroundPaint` (unchecked ring / progress arc): STROKE, stroke width **1.2dp** (L122-124).
- `setBackgroundType` overrides the ring stroke (L250-268): types 12/13 → **1dp** (L255-256); types 4/5 → **1.9dp**, and type 5 also thins the check to **1.5dp** (L257-261); type 3 → **3dp** (L262-263); any other non-zero type → **1.5dp** (L264-266). Type 0 keeps the constructor 1.2dp.

### Geometry
- Radius `rad = dp(size/2)` (L396); types 12/13 force `rad = dp(10)` (L398-399); every type except 0/11 shaves the outer ring radius by **0.2dp** (L401-403). Drawing is centered in `bounds` (L409-410).
- Check-mark anchor: `x = cx − 1.5dp`, `y = cy + 4dp` (L632-633). Long arm length `9dp·scale·checkProgress`, short arm `4dp·scale·checkProgress` (L630-631), both projected at 45° (`side = sqrt(s²/2)`, L634, 637); path = `(x−s_small, y−s_small) → (x, y) → (x+s_long, y−s_long)` (L635-638). `scale` = 1.4 for backgroundType −1, 0.8 for type 5, else 1 (L624-629). Optional whole-check `checkScale` canvas scale around center (L39, L640-644).

### Animation (setChecked)
- `setChecked(checked, animated)` animates `progress` 0↔1 with an ObjectAnimator, **interpolator `CubicBezierInterpolator.EASE_OUT`**, duration `animationDuration` = **200ms** default (L277-294; overridable via `CheckBox2.setDuration`, CheckBox2.java L93-95). Not attached / not animated → progress jumps (L387-392).
- Two-phase split of `progress` (this is the signature look):
  - **Phase 1 (0→0.5): fill.** `roundProgress = progress ≥ .5 ? 1 : progress/0.5` (L407). The color disc is drawn as a full circle of radius `rad − 0.5dp` and a concentric **erase circle of radius `rad·(1−roundProgress)`** punched out with `Theme.PAINT_CLEAR` inside a saveLayer (L546-579) — the fill grows as an annulus from the ring inward. Types 12/13 instead scale a plain circle `rad·roundProgress` at alpha `255·roundProgress` (L556-562); `customRadius > 0` swaps circles for round-rects (L563-571).
  - **Phase 2 (0.5→1): check.** `checkProgress = progress < .5 ? 0 : (progress−0.5)/0.5` (L521); both arm lengths scale with `checkProgress` (L630-631). Number mode instead scales text horizontally by `checkProgress` (L619).

### Colors (default keys, L79-83)
- `checkColorKey = key_checkboxCheck` (L79), `backgroundColorKey = background2ColorKey = key_chat_serviceBackground` (L80-81), `strokeBackgroundKey = key_dialogBackground` (L82). `setColor(background, background2, check)` (L296-304).
- **Checked fill color:** `enabled ? key_checkbox : key_checkboxDisabled` for standard types (L530); types 11/6/7/10/14 — or `!drawUnchecked && backgroundColorKey >= 0` — use `backgroundColorKey` (L525-526); type 9 uses `background2ColorKey` (L523-524); a raw `backgroundColor` int wins if set (L527-528). At `alpha < 1` the fill blends toward the ring color (L534-535).
- **Check color:** `checkColorKey`, or forced `key_checkboxCheck` when `useDefaultCheck` (L537-541).
- **Unchecked drawing** (only when `drawUnchecked`, L450-467): default types draw a translucent interior `((serviceMessageColor & 0xffffff) | 0x28000000)` circle of radius `rad` (L429, 465) and (types 0/11) a ring in `checkColorKey` (L430, 485-486); types 8/10/14 draw only a ring of radius `rad − 1.5dp` in `background2ColorKey` (L426-427, 453-459); types 6/7 draw interior radius `rad − 1dp` + ring radius `rad − 1.5dp` (L461-463).
- **Progress-arc types** (L487-517): while animating, non-0/11/12/13 types draw the ring as a partial arc — type 1: start −90°, sweep `−270°·progress` (L494-496); default: start 90°, sweep `270°·progress` (mirrored in RTL, L497-502); type 6: start 0°, sweep `−360°·progress` over a `strokeBackgroundKey` backing arc (L491-493, 505-515). Type 3 (3dp stroke) + `setDrawUnchecked(false)` is the avatar-overlay recipe: the ring fades in from transparent white via `getOffsetColor(0x00ffffff, key, progress, backgroundAlpha)` (L432-434).

### Extra states
- **Number mode** (`setNum`, L354-368; draw L595-621): bold typeface (L598); size/baseline by digit count — ≤2 chars 14dp @ y=18dp, 3 chars 10dp @ 16.5dp, ≥4 chars 8dp @ 15.75dp (absolute from view top, tuned for the 24dp picker box; L600-615); color `checkColorKey` (L617).
- **Forbidden** (`setForbidden`, L212-218): forces progress 1 (L406) and replaces the check with a **dashed ring**: radius 9dp, stroke 1.66dp, dash pattern `[0.66dp, 4dp]`, color `key_switchTrack` (L583-593).
- **cutCheck** (`setCuttingCheck`, L54-63): checkPaint xfermode CLEAR — the check is punched *out of* the fill (transparent check), composited via saveLayer over the fill box (L412-415, 652-654).
- `drawUnchecked=false` hides the idle state entirely (select-overlay use) (L188-194).

### CheckBox2 wrapper specifics
- Accessibility: announces as `android.widget.Switch`, checkable + checked (CheckBox2.java L130-136).
- Icon mode (`setIcon`): swaps drawing for a centered drawable tinted `key_switch2Track` plus a 1.2dp ring of radius `cx − 1.5dp` (L111-120, 138-148).

### Canonical row recipe — ui/Cells/CheckBoxCell.java (round variant)
- `new CheckBox2(context, 21, rp)` + `setDrawUnchecked(true)` + `setDrawBackgroundAsArc(10)`; framed **21×21dp**, leading, top margin 16dp (L194-199). Type 10 = 1.5dp ring in `background2` when unchecked, fill from `backgroundColorKey` when checked.
- `setCheckBoxColor(background, background1, check)` forwards `(background, background, check)` — the middle argument is **ignored** (quirk, L527-531); callers pass e.g. `(colorKey, key_windowBackgroundWhiteGrayIcon, key_checkboxCheck)` (ui/CacheControlActivity.java L2545).
- List-multiselect recipe (over avatars): `setColor(key_checkbox, key_radioBackground, key_checkboxCheck)` (ui/ProxyListActivity.java L164, ui/CachedMediaLayout.java L1030), usually with `setDrawUnchecked(false)` + `setDrawBackgroundAsArc(3)`.

**Flutter port notes:** implement `TgCheckBox` as a leaf `CustomPaint` sized `Size.square(size)` (default 21); animate a single 0..1 progress with `Curves` equivalent of EASE_OUT over 200ms; phase-split as above; erase-circle compositing maps to `saveLayer` + `BlendMode.clear` or (simpler, identical result) drawing the fill as an even-odd annulus path. Expose `backgroundType` only as the three recipes actually used (plain 0, settings-row 10, avatar-overlay 3) rather than all 14 magic ints.

---

## 2. RadioButton — ui/Components/RadioButton.java (+ ui/Cells/RadioCell.java row)

### Size & paints
- Default intrinsic size **16dp** (`size = dp(16)`, L45); `setSize` takes **px** (L81-86). RadioCell sets **20dp** (`setSize(dp(20))`, RadioCell.java L70) inside a **22×22dp** frame (RadioCell.java L76, 88).
- Ring paint: STROKE, width **2dp** (L50-52); `checkedPaint` fill; `eraser` = CLEAR xfermode (L53-56). All three are class-static (shared).

### Colors
- Takes **raw colors**, not keys: `setColor(color, checkedColor)` (L100-104). RadioCell passes `key_radioBackground` / `key_radioBackgroundChecked` (RadioCell.java L74), or dialog variants `key_dialogRadioBackground` / `key_dialogRadioBackgroundChecked` (L72).

### Animation & draw (onDraw, L159-201)
- `setChecked(checked, animated)` → ObjectAnimator `progress` 0↔1, **200ms**, default (accelerate-decelerate) interpolator (L122-126, 140-152).
- `circleProgress` is a triangle wave: `progress ≤ .5 ? progress/0.5 : 2 − progress/0.5` (L161-166) — 0→1 during the first half, 1→0 during the second.
- **Color:** first half stays at the unchecked `color`; second half lerps per-channel `color → checkedColor` by `(1 − circleProgress)` (L162-175) — so the hue flips entirely during the collapse phase.
- **Ring radius breathes:** `rad = size/2 − (1 + circleProgress)·density px` = `size/2 − dp(1 + circleProgress)` (L178) — 1dp inset at rest, 2dp at the animation midpoint.
- **First half (progress ≤ .5):** inner disc of radius `rad − 1dp` is drawn (L182), then an erase circle of radius `(rad − 1dp)·(1 − circleProgress)` is punched out (L183) — the interior fills from the ring inward (same annulus trick as the checkbox). All composited in a `saveLayerAlpha` (L177).
- **Second half (progress > .5):** a solid dot of radius `size/4 + (rad − 1dp − size/4)·circleProgress` (L185) — collapses from the full interior down to the resting dot.
- **End states:** unchecked = 2dp ring at radius `size/2 − 1dp`, hollow. Checked = same ring + **dot of radius `size/4`**, both in `checkedColor`. For the 20dp RadioCell instance: ring radius 9dp, dot radius 5dp.
- Icon mode (`setIcon`, L88-94): the dot phase is skipped (L180); a centered drawable is tinted `lerp(color → checkedColor, clamp(progress))` (L189-201).

### RadioCell row wrapper
- Row height **50dp + 1px divider** (RadioCell.java L85); radio 22×22 trailing, top margin 14dp (L76); text 16dp `windowBackgroundWhiteBlackText` with 17dp side padding (L67 area); disabled = **alpha 0.5 on the whole radio + text** (L114-119); divider = `Theme.dividerPaint`, leading inset 20dp (L128); accessibility class `android.widget.RadioButton` (L135).

**Flutter port notes:** `TgRadio` = leaf `CustomPaint`, default box 22, drawn circle size 20 (keep 16 as the bare-widget default to match Java). Single 200ms linear-ish (accel-decel) controller; derive `circleProgress` + color lerp exactly as above. The saveLayer/eraser can again become an even-odd annulus path.

---

## 3. Slider — ui/Components/SeekBarView.java

A `FrameLayout` that draws everything itself. Canonical layout in settings: **MATCH_PARENT × 38dp** (ui/ThemeActivity.java L341, 425).

### Metrics
- `selectorWidth` = **32dp** (L115) — the track is inset `selectorWidth/2` = **16dp** on each side (L451); thumb travel range = `width − 32dp`, thumb *center* runs 16dp → width−16dp (L447, 527).
- `thumbSize` = **24dp** (L116) — the logical grab box; the visible thumb is a filled circle of radius **6dp at rest, 8dp pressed** (L117, 490), centered at `(thumbX + 16dp, height/2)` (L523-527).
- Track height = `lineWidthDp` = **3dp** default (L77; `setLineWidth`, L341-343), vertically centered (L450-452), rounded-rect **radius 2dp** (L658).
- Hover ripple: `Theme.createSelectorDrawable(player_progress @ alpha 40/255, radius 16dp)` (L119-123), drawn as a **32×32dp** circle centered on the thumb (L483-487).

### Colors
- Filled portion + thumb: `outerPaint1` = `key_player_progress` (L112-113).
- Track background: **hard-set every frame** to `key_player_progressBackground` in `onDraw` (L448) — this clobbers `setColors`/`setInnerColor` (L176-194); only a `resourcesProvider` override actually changes it (quirk worth preserving *not* replicating: the Flutter port should honor its inner-color parameter).
- Buffered segment: `key_player_progressCachedBackground` from `left` to `bufferedProgress` fraction (L456-459).
- `minProgress` region: segment `[0, minProgress]` in outer color at **50% alpha**, active fill starts at `minProgress` (L469-476); thumb clamped to `minProgress` (L337-339).

### Progress model
- `progress = thumbX / (width − selectorWidth)` ∈ [0,1] (L359-364); `setProgress` before layout is deferred (L64, 370-374, 413-416).
- **Two-sided mode** (`setTwoSided`, L184-190): progress ∈ [−1, 1] measured from center; a center notch **2×12dp** (`±1dp × ±6dp`) is drawn (L462); the fill is a thin **2dp** bar from center to thumb (L463-467); mapping in `setProgress` (L377-384).
- **Steps** (`setSeparatorsCount`, L172-174): the *drawn* thumb snaps to the nearest step through `animatedThumbX` = `AnimatedFloat(delay 0, **60ms**, EASE_OUT)` (L62, 440-442); each step change during drag fires the `vibrateCursor` haptic (L350-356). `delegate.needVisuallyDivideSteps()` snaps without animation (L443-446).

### Drag behavior (onTouch, L231-335)
- DOWN records the touch, returns true (L232-235). MOVE: rejected if vertical travel exceeds slop before capture (L279-281); captured after horizontal slop + `requestDisallowInterceptTouchEvent` (L282-284).
- Grab is **forgiving**: the thumb hit-area is `thumbX ± (height − thumbSize)/2` wide; grabbing outside it re-centers the thumb at the finger (L285-294); inside it, `thumbDX` keeps the grab offset (L295).
- During drag `thumbX = x − thumbDX`, clamped to `[minThumbX, width − selectorWidth]` (L308-313). `setReportChanges(true)` streams `onSeekBarDrag(stop=false, progress)` live (L213-215, 314-325).
- UP: a **tap** (vertical travel < slop) outside the thumb jumps the thumb to the tap point and completes as a drag (L238-252); release fires `onSeekBarDrag(stop=true, progress)` (single-sided; two-sided release passes `stop=false`, L255-265); `onSeekBarPressed(false)` (L270); `pressed` clears immediately, `pressedDelayed` after 50ms (L272).
- Delegate interface (L83-96): `onSeekBarDrag(boolean stop, float progress)`, `onSeekBarPressed(boolean)`, `getStepsCount()`, `needVisuallyDivideSteps()`.

### Transition animations
- **Thumb press radius:** 6dp↔8dp, animated linearly at **1dp per 60ms** per frame tick (`currentRadius ± dp(1)·(dt/60)`, dt capped 16-17ms; L489-509) — ≈120ms for the full 2dp change.
- **Animated setProgress** (`setProgress(p, animated=true)`, L388-393): `transitionProgress` runs 0→1 at `dt/225` (**225ms**, L510-517). The **old** thumb circle collapses with radius factor `1 − easeInQuad(min(1, t·3))` (gone in the first ~75ms; L520, 523); the **new** thumb grows with `easeOutQuad(t)` at the target position (L521, 525). Both drawn in the outer color.
- Timestamp/chapter machinery (L537-891: 12dp `player_time` labels, gap-split track segments) is chat-media-specific — skip for the generic kit component.

### Accessibility
- `FloatSeekBarAccessibilityDelegate`; a11y increments use `1/stepsCount` when the delegate reports steps (L141-169).

**Flutter port notes:** `TgSlider` as a 38dp-tall `LayoutBuilder`+`CustomPaint` with a horizontal-drag recognizer; parameters `progress`, `onChanged(stop, value)` (or Flutter-idiomatic `onChanged`/`onChangeEnd`), `bufferedProgress`, `minProgress`, `stepCount`, `twoSided`, `lineWidth`, color keys `player_progress`/`player_progressBackground`/`player_progressCachedBackground`. Reproduce: 16dp end insets, 2dp track radius, 6→8dp press growth (~120ms linear), 60ms EASE_OUT step snap + `HapticFeedback.selectionClick`, 225ms double-circle animated jump, tap-to-seek.

---

## 4. TgSwitch parity re-verification — ui/Components/Switch.java vs lib/src/components/cells/text_cell.dart

Port location: `/home/user/Telegram/flutter/telegram_ui/lib/src/components/cells/text_cell.dart` (`TgSwitch`, `TgSwitchPainter`, L520-765).

Every cited constant re-checked against the current Java source — **all line citations still accurate; no geometric drift found**:

| fact | Java | port |
|---|---|---|
| view slot 37×20dp | TextCell.java L140 | `kTgSwitchSize` (L522) ✓ |
| track 31×14dp, radius 7dp | Switch.java L380, 383, 448-449 | `kTgSwitchTrackWidth/Height/Radius` (L525-531) ✓ |
| thumb outer r=10dp in *track* color | Switch.java L450 | painter L751 ✓ |
| thumb core r=8dp in thumb color | Switch.java L497 | painter L753-757 ✓ |
| travel `x + 7dp + 17dp·progress` | Switch.java L384 | `kTgSwitchThumbInset/Travel` (L542-545, 736-738) ✓ |
| 200ms toggle, accelerate-decelerate | Switch.java L237-246 | `kTgSwitchDuration`/`kTgSwitchCurve` (L549-553) ✓ |
| per-channel track/thumb color lerp | Switch.java L425-445, 480-495 | `Color.lerp` (L700-701) ✓ equivalent |
| TextCell key recipe `switchTrack`/`switchTrackChecked`/`windowBackgroundWhite`×2 | TextCell.java L139 | defaults (L584-587) ✓ |
| bare-widget Java defaults differ (`fill_RedNormal`/`switch2TrackChecked`, Switch.java L60-63) | — | documented in port doc comment ✓ |

Known, documented omissions (unchanged; acceptable for the kit): ripple (Switch.java L157-218, radius 18dp, keys `switchTrackBlueSelector[Checked]`), check/lock icon overlays (L514-545), icon-drawable visibility animator (BoolAnimator 380ms EASE_OUT_QUINT, L42, 500-513), override-color snapshot machinery (L332-372, 405-460), RTL note (Java `onDraw` itself never mirrors — fixed LTR math, L380-385).

Minor drift notes (non-blocking):
1. **Pixel rounding:** Java truncates the thumb x to whole px (`(int)(dp(17)·progress)`, Switch.java L384) and draws at int centers; the port animates sub-pixel. Visually smoother, ≤1px difference — keep as-is.
2. **Haptics:** Java enables view haptics (`setHapticFeedbackEnabled(true)`, Switch.java L108) though it never calls `performHapticFeedback` itself; the port performs no haptics. Parity-neutral; if row-level haptics are added later they belong on `TextCell`, not `TgSwitch`.
3. **Callback semantics:** Java's `setChecked` fires `onCheckedChanged` even on programmatic change (Switch.java L289-291); the port is a controlled widget and only reports taps. Intentional Flutter idiom — no change needed.

**Verdict: TgSwitch is at parity for the TextCell configuration; no fixes required.**
