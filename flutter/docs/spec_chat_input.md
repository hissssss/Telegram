# Telegram Android → Flutter port: Chat input surface spec

Extracted from Java sources for a faithful port. All paths relative to
`/home/user/Telegram/TMessagesProj/src/main/java/org/telegram/` unless noted.
Primary source: `ui/Components/ChatActivityEnterView.java` (cited below as **CAEV**).
Other sources: `ui/Components/chat/ChatInputViewsContainer.java` (**CIVC**),
`ui/Components/InstantCameraView.java` (**ICV**),
`ui/Components/ChatActivityEnterViewAnimatedIconView.java` (**AIV**),
`ui/ChatActivity.java` (**CA**), `messenger/AndroidUtilities.java` (**AU**).

Units: `dp(v)` = `ceil(density*v)` (AU:2708-2713); `dpf2(v)` = `density*v` float
(AU:2747-2752); `dp2(v)` = `floor(density*v)` (AU:2722-2727). 1 Android dp = 1 Flutter
logical px. Curves: `CubicBezierInterpolator` `EASE_OUT_QUINT`=(.23,1,.32,1),
`EASE_OUT`=(0,0,.58,1), `EASE_BOTH`=(.42,0,.58,1), `DEFAULT`=(.25,.1,.25,1)
(Components/CubicBezierInterpolator.java:11-14) — already mirrored in `TgCurves`.
`ChatListItemAnimator.DEFAULT_DURATION` = **250ms**, `DEFAULT_INTERPOLATOR` =
cubic-bezier(0.199, 0.011, 0.279, 0.910) (androidx/recyclerview/widget/ChatListItemAnimator.java:44-45).
`AndroidUtilities.bold()` = Roboto Medium (rmedium.ttf).

Capture pipelines (mic amplitude, camera frames) are **callback slots** in the Flutter
port — never implemented here.

---

## 1. Glass wiring — the input "island" (CIVC + CA)

The glass-era input bar is a floating rounded **bubble** drawn by `ChatInputViewsContainer`,
not by the enter view itself (`shouldDrawBackground=false`; legacy opaque background in
§1.6).

Constants (CIVC:27-30):
- `INPUT_BUBBLE_RADIUS` = **22dp** — corner radius of the input island bubble.
- `INPUT_KEYBOARD_RADIUS` = **29dp** — top corner radius of the in-app keyboard panel.
- `INPUT_BUBBLE_BOTTOM` = **9dp** — gap between bubble bottom and the bottom inset.

Input island bubble drawable (CIVC:79-83):
- `BlurredBackgroundDrawable` with `setPadding(dp(7))`, `setRadius(dp(22))`.
- Color provider: `Theme.key_chat_messagePanelBackground` (CA:3547). Style = the existing
  `GlassPresets.bottomPanelChat` (`bottomPanelChatActivity`, tint 0.85 light / 0.76 dark,
  strokes 0.5dp) — already ported in `lib/src/glass/presets.dart`.
- Bounds: full width minus `inputBubbleOffsetLeft/Right`, height = island height, then
  `inset(0, -dp(7))` vertically (the 7dp padding above) and offset to
  `containerHeight - blurredHeight (+ translationY)` (CIVC:260-273).
- Island bottom = `measuredHeight - maxBottomInset - dp(9)` (CIVC:184-185, 229-235).

Under-keyboard glass panel (CIVC:85-91) — **confirmed**:
- radius **29dp** top-left/top-right, 0 bottom (device rounded-corner radii applied on
  API 31+, CIVC:168-181);
- `setThickness(dp(32))` — liquid lens thickness **32dp**;
- `setIntensity(0.4f)` — refraction intensity **0.4**;
- built from the **frosted** factory (CA:4542-4543, factory CA:2600) → backdrop blur
  38.34dp (`kFrostedBackdropBlurRadiusDp` in `tokens/glass_metrics.g.dart`).
- Blurred region height = `islandHeight + dp(9) + maxBottomInset` (CIVC:137).

Island height (CA:45923-45946):
- `inputIslandHeight = max(lerp(dp(44), enterViewIslandHeight, factor) * visibility, dp(44))`
  — minimum **44dp**; enterViewIslandHeight = animated text-field height + topView (reply/
  edit header) height (CAEV:15506-15516).

Touch: taps landing on either glass bubble (but not on a child) are swallowed
(CIVC:347-364).

## 2. Input bar geometry (CAEV)

**Base metrics**
- `DEFAULT_HEIGHT` = **44dp** (CAEV:6410) — the resting bar height, and the width/height
  of every button slot.
- `textFieldContainer`: bottom-aligned, `topMargin 1dp` + `paddingTop 1dp` (CAEV:2616-2617).
- `messageEditTextContainer` (holds field + emoji + attach): match-parent width, bottom
  gravity, **rightMargin 44dp** (CAEV:2660); measured height = `max(dp(44), content)`
  (CAEV:2623). Height changes animate through a `FactorAnimator` — **250ms**,
  ChatListItemAnimator default interpolator (CAEV:15456, 2624-2628).
- Adaptive height: the field grows with line count up to **maxLines 6** (CAEV:5751);
  everything below the animated separator (`measuredHeight - animatedFieldHeight`) is the
  live bar; topView (reply header) is clipped above it (CAEV:4640-4658).

**Message text field** (`createMessageEditText`, CAEV:5629-5763)
- Text size **18dp**, gravity bottom, `includeFontPadding false`, single-line false
  (CAEV:5746-5753).
- Padding: **top 9dp, bottom 10dp, left/right 0** (CAEV:5754); with slow-mode button the
  right padding becomes 16dp (premium 26dp) (CAEV:8695-8700).
- Frame margins: **left 52dp, right 50dp (isChat; 2dp otherwise), bottom 1.5dp**
  (CAEV:5763). Re-derived in onMeasure: default left **50dp**; with bot-commands menu
  `57dp + menuWidth`; with sender-select `54dp + selectWidth` (CAEV:14377-14406).
  `updateFieldRight`: right margin 50dp (attach only) / 98dp (attach + bot|notify|
  scheduled) / 146dp (attach + bot + scheduled) / 2dp (none), floored by
  `sendButton.width() - 44dp` (CAEV:8704-8731).
- Colors: text `chat_messagePanelText`, hint `chat_messagePanelHint`, cursor
  `chat_messagePanelCursor`, links `chat_messageLinkOut`, selection highlight
  `chat_inTextSelectionHighlight`, handles `chat_TextSelectionCursor` (CAEV:5756-5762).
- Hint text: default `TypeMessage` ("Message"); channels `SendAnonymously`, comment
  threads `Comment`/`Reply`, editing `Caption`/`TypeMessage` (CAEV:6734-6823).

**Emoji button** (CAEV:2662-2713)
- Slot **44x44dp**, bottom-left, leftMargin **2dp** at creation (CAEV:2713), normalized to
  **3dp** every measure (CAEV:14397); with bot menu `10dp + menuWidth` (CAEV:14373).
- Icon = `ChatActivityEnterViewAnimatedIconView` (default lottie size 32dp, AIV:33-35)
  with content padding **7.5dp** each side (CAEV:2676-2677).
- Tint `glass_defaultIcon`; ripple `listSelector` inset-round-rect radius 19dp
  (CAEV:2678-2679).
- Unread-sticker dot: 5dp-radius circle at `(w/2 + 9dp, h/2 - 8dp)`, color
  `chat_emojiPanelNewTrending` (CAEV:2666-2670).
- States SMILE/STICKER/GIF <-> KEYBOARD morph via dedicated lottie transitions (AIV:110-122).

**Attach button** (CAEV:2783-2794)
- **44x44dp**, bottom-right of the field container (margin 0); icon `msg_input_attach2`,
  tint `glass_defaultIcon`, ripple `listSelector`. Ignores touches when alpha < 0.5
  (CAEV:2786).
- `attachLayout` (notify button etc.): 44dp tall row, bottom-right with rightMargin
  **44dp** (left of attach button), pivotX = right edge (CAEV:2740-2750). Notify button
  44x44dp, `input_notify_on` + cross-out, tint `glass_defaultIcon` (CAEV:2752-2761).

**Send / mic container**
- `sendButtonContainer`: **100x44dp**, bottom-right of textFieldContainer; pivot at
  `(w-22dp, h-22dp)` (CAEV:2897-2931).
- `audioVideoButtonContainer` (mic/video button): **44x44dp**, right|bottom inside it
  (CAEV:3209). Behind the icon it paints a **38x38dp rounded rect, radius 19dp, margin
  3dp** from the container's bottom-right, fill `chat_messagePanelSend` (CAEV:3188-3203)
  — this is the colored circular send-area button. It scales with
  `1 - expandStickersButton.alpha` when the sticker-expand button shows (CAEV:3182-3201).
- `audioVideoSendButton`: animated icon view, lottie size **24dp**, content padding
  **10dp** each side, 44x44dp frame (CAEV:3387-3407). When recording is forbidden it
  draws static outline drawables `input_mic`/`input_video` tinted `glass_defaultIcon`
  inset 7.5dp (CAEV:3391-3399).
- `SendButton` uses `send_plane_24` (schedule mode: `input_schedule`) (CAEV:3435).
- Mic/send swap on text: buttons scale to/from **0.1** with alpha, **220ms**
  EASE_OUT_QUINT (CAEV:8187, 7968-7969); reverse (text cleared) **150ms** (CAEV:8604).

**Top hairline / legacy background** (pre-glass path, `shouldDrawBackground=true` only)
- `Theme.chat_composeShadowDrawable` hairline across the top + panel fill
  `chat_messagePanelBackground` (blur rect when chat blur on), fallback paint key
  `paint_chatComposeBackground` (CAEV:4668-4701). In the glass design this is replaced
  entirely by the CIVC island (§1).

## 3. Record button behavior (audioVideoButtonContainer touch logic, CAEV:2933-3207)

**Mic <-> video toggle (tap)**
- On DOWN: if `hasRecordVideo`, `recordAudioVideoRunnable` is scheduled with a
  **150ms delay** (CAEV:3013-3016); otherwise it runs immediately (CAEV:3018).
- On UP **before** the runnable fires (a tap): the runnable is cancelled and the mode
  toggles — `onSwitchRecordMode(!isInVideoMode)`, `setRecordVideoButtonVisible(!video,
  true)`, KEYBOARD_TAP haptic (CAEV:3063-3073). Mode persists to prefs
  `currentModeVideo`/`currentModeVideoChannel` (CAEV:6112-6120).
- Icon morph: single lottie `R.raw.voice_and_video`; VOICE→VIDEO plays frames from
  progress 0.5 to frame 60, VIDEO→VOICE frames 0→30; static states: progress 0.5 = voice,
  0 = video (AIV:42-76).
- Hold ≥150ms → `recordAudioVideoRunnable` starts recording: sets
  `recordingAudioVideo=true`, `updateRecordInterface(RECORD_STATE_ENTER)`; audio mode also
  starts the timer at 0 and `showWaves(true)`; video mode `showWaves(false)`
  (CAEV:895-956).

**RecordCircle — the expanding circle** (CAEV:1945-2555)
- View: match-parent width x **194dp**, bottom-aligned in the chat's root layout
  (CAEV:2118-2121, 4460-4462). Center: `cx = width - dp2(26)`, `cy = 170dp` from view top
  = **24dp above layout bottom** (CAEV:2139-2140).
- Radius: `circleRadius = dpf2(41)`; + `dp(30) * amplitude` (mic amplitude 0..1)
  (CAEV:1960-1961, 2182). Amplitude input = `min(1800, value)/1800`
  (`WaveDrawable.MAX_AMPLITUDE`, CAEV:2025-2030); smoothing toward target over
  `100 + 500*0.55 = 375`ms (CAEV:2030, WaveDrawable.java:31,45).
- Enter scale animation: `scale` 0→1 over **300ms**, DecelerateInterpolator (set-level,
  CAEV:8923-8927, 8961). Scale mapping is a manual overshoot (CAEV:2152-2160):
  `scale<=0.5 → sc=scale/0.5`; `0.5<scale<=0.75 → sc=1-0.4(scale-0.5)` (dips to 0.9);
  `>0.75 → sc=0.9+0.4(scale-0.75)` (back to 1.0).
- Fill color `chat_messagePanelVoiceBackground`; during seekbar morph step3 blends to
  `chat_recordedVoiceBackground` (CAEV:2227-2231).
- Icon inside: `input_mic_pressed` / `input_video_pressed` tinted
  `chat_messagePanelVoicePressed` (multiply), 24x24dp box (`cx±12dp`) (CAEV:2005-2016,
  2249-2252).
- Amplitude waves (two `BlobDrawable`s, LiteMode gated): tiny blob min radius **47dp**,
  max `47 + 15*0.6 = 56dp`; big blob min **50dp**, max `50 + 12*0.6 = 57.2dp`
  (CAEV:2269-2274). Draw scale = `scale * (1-toSeekbarStep1) * slideProgress' * enter *
  (SCALE_MIN + 1.4*amp)` with `SCALE_BIG_MIN=0.878`, `SCALE_SMALL_MIN=0.926`
  (CAEV:2295-2306, BlobDrawable.java:19-28). Wave colors:
  `chat_messagePanelVoiceBackground` at alpha **0.30** (big) / **0.15** (tiny)
  (CAEV:2448-2450, WaveDrawable.java:32-33). Waves enter: `+0.04/frame`, EASE_OUT
  (CAEV:2288-2295).
- Idle bobbing driver: `idleProgress` ping-pongs ±0.01/frame (CAEV:2255-2267).

**Morph to send (locked state)**
- Once locked, tapping the big circle sends; the circle icon becomes `attach_send`
  (tint `chat_messagePanelVoicePressed`) cross-scaled against the outgoing mic/camera
  icon by `progressToSendButton`, which advances `dt/150` (**150ms** linear)
  (CAEV:2236-2248, 2402-2431).
- Send tap → stop recording, then `updateRecordInterface(RECORD_STATE_SENDING)` after a
  **200ms** delay (lock-send path, CAEV:2992-3000) or **500ms** (release-to-send path,
  CAEV:3110-3118).

## 4. Record overlay: slide-to-cancel, lock, timer

**Record panel** (`createRecordPanel`, CAEV:9677-9703)
- Full-width x 44dp overlay inside the field container; swallows all touches.
- `SlideTextView` fills it with **leftMargin 45dp**.
- `recordTimeContainer`: horizontal row, paddingLeft **13dp**, centered vertically;
  RecordDot **28x28dp**, then TimerView with leftMargin **6dp**.

**Slide-to-cancel** (CAEV:3122-3170 gesture; SlideTextView CAEV:13871-14145)
- Cancel distance `distCanMove = 35% of layout width, capped 140dp` (CAEV:3135-3141).
- `slideProgress = clamp(1 + dx/distCanMove, 0, 1)`; reaching 0 cancels immediately
  (CAEV:3143-3169). On release, `slideProgress < 0.45` cancels (`alpha < 0.45`,
  CAEV:3048-3062); otherwise the recording is sent.
- The circle translates by `slideDelta = -min(0.35w, 140dp) * (1 - slideProgress)`
  (CAEV:1913-1921) and scales by `0.7 + 0.3*slideProgress` (CAEV:2176-2181). Cancel-by-
  gesture shrink: `0.7 * EASE_OUT(1-slideProgress)`, min radius clamp 19dp, alpha fades
  over slideProgress 0.7→1.0 (CAEV:2177-2178, 2223-2225, 2309-2311).
- Text: `SlideToCancel2` = **"Slide to cancel"**, grey paint **15dp** (13dp when screen
  width <= 320dp), color `chat_recordTime`; "CANCEL" (uppercased `Cancel`) **15dp bold**,
  color `chat_recordVoiceCancel` (CAEV:13958-13977, 14047-14049). Text centered
  horizontally (+5dp), drifting left by `-width/4 * (1-slideProgress) +
  circleTranslationX*0.3` (CAEV:14076-14089).
- Arrow: stroked chevron 4x10dp (points (4,-5)→(0,0)→(4,5); small screens 2.5x6.24),
  stroke **1.6dp** (small 1.0dp) round cap/join, drawn 10dp (small 7dp) left of the text,
  same grey (CAEV:13969-13973, 14024-14033, 14086-14091). Idle bob: xOffset ping-pongs
  ±6dp at 3dp/250ms while slideProgress > 0.8 (CAEV:14055-14071).
- Cancel morph (after lock): grey text fades out (`alpha *= (1-cancelToProgress) *
  slideProgress`), CANCEL fades in aligned to the "cancel" substring position when the
  translation exists in the locale, else slides up 12dp (CAEV:14074-14122). CANCEL hit
  rect = text bounds inset **-16dp**; ripple = 60dp-radius circle selector of
  `chat_recordVoiceCancel` @ alpha 26/255 (CAEV:13989, 14110-14117).

**Lock** (ControlsView, CAEV:1162-1875; threshold CAEV:2094-2114)
- Drag **up 57dp** from the touch start → locked (`sendButtonVisible=true`)
  (CAEV:2106-2112). Lock ignored once `slideToCancelProgress < 0.7` (CAEV:2103).
- ControlsView measures width x `dp(194 + 44 + 12)` = **250dp**, bottom-aligned
  (CAEV:1307-1329, 4465-4472).
- Lock pill: centered at `cx = width - dp2(26)`; width 36dp (`cx±18dp`), corner radius
  **18dp**; height `lockSize` = **50dp at rest → 36dp fully dragged**
  (`36 + 14*moveProgress`, `moveProgress = 1 - yAdd/57dp`); locked: fixed 36dp
  (CAEV:1354-1391, 1521). Y: `dp(60) + (viewHeight - dp(194)) + 30dp*(1-enterScale) -
  yAdd` + idle bob `-8dp*idleProgress*moveProgress` (CAEV:1385-1386).
- Background: glass `BlurredBackgroundDrawable` radius 18dp padding 3dp, color key
  `chat_messagePanelVoiceLockBackground` (CAEV:1683-1699); non-glass fallback:
  `lock_round_shadow` drawable tinted `chat_messagePanelVoiceLockShadow` + rounded rect
  `chat_messagePanelVoiceLockBackground` (CAEV:1211-1212, 1523-1536).
- Lock glyph: body = rounded rect ~12x12dp (cx±6, +2dp swell when unlocked), radius 3dp;
  shackle = 8x8dp arc, stroke **1.7dp** round cap; keyhole dot radius 2dp in background
  color; rotation 9° * (1-moveProgress), snapping to -15° * snapProgress on lock; colors:
  `glass_defaultIcon` in glass design, else `chat_messagePanelVoiceLock`
  (CAEV:1207-1209, 1546-1632, 1722-1727).
- After lock the pill morphs into a **pause button** (`transformToPauseProgress`): body
  splits into two 3.3dp-gapped bars, radii 3→1.5dp (CAEV:1593-1612). When resuming is
  possible the pause morphs to mic/video glyph (`input_mic`/`input_video` at scale
  0.9285) (CAEV:1588-1628). Pause auto-hides at video 59s: `AnimatedFloat` 350ms
  EASE_OUT_QUINT (CAEV:1339, 1460, 1518).
- Lock exit slide: vertical dy up to **72dp** (`maxTranslationDy`, CAEV:1509-1517);
  fade/scale driver `slideToCancelLockProgress` ramps ±0.12/frame when slideProgress
  crosses 0.7 (CAEV:1492-1507).
- Snap animation on lock (`startLockTransition`, CAEV:4607-4630): KEYBOARD_TAP haptic;
  `lockAnimatedTranslation` back to start **350ms** delay 100ms; `snapAnimationProgress`
  0→1 **250ms** EASE_OUT_QUINT; `slideToCancelProgress`→1 **200ms**; slideText
  `cancelToProgress`→1 (default 300ms).
- Tooltip "Slide up to lock recording" (`SlideUpToLock`): text 14dp
  `chat_gifSaveHintText` on `chat_gifSaveHintBackground` round-rect radius 5dp, layout
  width 220dp, drawn right-aligned (right edge inset 44dp), with `tooltip_arrow` under it
  and an animated white chevron (5x4dp legs, stroke 1.5dp) bobbing 3dp near the right
  edge; fade in/out `dt/150` (150ms), shown 200ms after hold while `lockRecordAudioVideoHint
  < 3` (CAEV:1213-1217, 1232-1237, 1312, 1393-1455).
- "Once" (view-once) toggle: appears when locked (`snapAnimationProgress` scale), 36x36dp
  rounded 18dp pill **12dp above** the lock, same glass background; `PeriodDrawable`
  colors: fg `glass_defaultIcon` (fallback `chat_messagePanelVoiceLock`), circle
  `chat_messagePanelVoiceBackground`, white check (CAEV:1636-1670, 1712-1716).

**Duration timer** (TimerView, CAEV:14147-14354)
- Text **15dp bold** (rmedium), color `chat_recordTime` (CAEV:14193-14197).
- Format `m:ss,cc` (`formatTimerDurationFast`: minutes unpadded, seconds 2-digit, comma,
  hundredths; hours branch `h:mm:ss,cc`) (CAEV:14199-14218, AU:986-1001).
- Digit roll: when the seconds digit changes, old/new layouts crossfade sliding
  **15dp** vertically; transition decays 0.15/frame (~7 frames) (CAEV:14162-14165,
  14272-14330).
- Sends "typing" every **5000ms** (record-audio=1 / record-round=7) (CAEV:14213-14216).
- Video auto-stop at **t >= 59500ms** (CAEV:14204-14211).

**Blinking red dot** (RecordDot, CAEV:961-1067)
- 5dp-radius circle, color `chat_recordedVoiceDot`, centered in its 28x28dp slot
  (CAEV:1055).
- Pulse: alpha ramps down then up at `dt/600` per direction — **600ms fade-out + 600ms
  fade-in (1.2s period)**, continuous (CAEV:1032-1049). Held at alpha 1 during the enter
  animation (CAEV:1033-1034).
- Enter: scale 0→1 within the 150ms enter set (CAEV:8826-8858).
- Cancel: plays lottie `chat_audio_record_delete_2` at 28dp (dot → trashcan), layers
  tinted dot-color/`chat_messagePanelBackground` (CAEV:989-1008, 1060-1066, 9532-9534).

**Record interface transitions** (`updateRecordInterface`, CAEV:8758-9647)
- ENTER (CAEV:8831-8963): whole set DecelerateInterpolator. 150ms: emoji scale/alpha→0,
  dot scale→1, timer & slideText translationX 20dp→0 + alpha→1, controls alpha→1,
  audioVideoButtonContainer alpha→0, messageEditText translationX→+20dp alpha→0,
  attach translationX→+30dp alpha→0 scale→0.5. 300ms: recordCircle scale→1 (and controls
  scale, unless resuming from pause).
- SENDING (CAEV:9535-9619): icons back 150ms delay 200ms; timer/slideText out 150ms
  translationX +40dp; `exitTransition`→1 **360ms** (220ms if the message send transition
  runs); editText alpha-in 200ms delay 150ms (450ms when emoji padding hidden).
  Exit geometry: radius +16dp over step1 (0..0.6 EASE_BOTH), then shrink *(1-exitStep2);
  alpha-out over 0.6..1.0 (CAEV:2205-2221).
- CANCEL (delete) / CANCEL_BY_GESTURE (CAEV:9367-9534): icons 150ms delay **700ms**;
  timer/slideText out 200ms delay 200ms translationX −20dp; editText in 200ms delay
  300/700ms; lock translation reset 200ms. Gesture: `slideToCancelProgress`→1 200ms
  EASE_BOTH (circle slides back & fades). Non-gesture: `exitTransition` 360ms delay
  **490ms** (waits for the dot's delete lottie).
- CANCEL_BY_TIME / fast exit (CAEV:9008-9070): everything restored in one 150ms set.
- PREPARING (locked, stop→preview) morph-to-seekbar (CAEV:9071-9365, 2188-2204):
  `transformToSeekbar` 0→1 over **580ms audio / 490ms video**; steps (each EASE_BOTH):
  step1 = t/0.38 (radius +16dp), step2 = (t-0.38)/0.25 (radius → 8dp), step3 =
  (t-0.63)/0.37 (circle rect lerps into the audio timeline rect, fill blends to
  `chat_recordedVoiceBackground`). Icons out 150ms delay 150ms; video timeline fade-in
  150ms delay 430ms.

## 5. Round video mode (ICV)

- **Circle preview diameter**: `AndroidUtilities.roundPlayingMessageSize` =
  `min(screenW, screenH) - dp(28)` on phones (tablet: `minTabletSide - dp(28)`);
  if the available height (minus bottom padding) <= width*1.3, falls back to
  `roundMessageSize` = `min(screenW, screenH) * 0.6` (AU:2800-2810; ICV:509-526).
  Centered in the fragment (ICV:317, 428).
- **Mask**: `ViewOutlineProvider` oval 0,0,size,size + `clipToOutline` on the camera
  container; the overlay `BackupImageView` uses round radius size/2 (ICV:308-314, 522).
  Placeholder while camera warms up: last-frame thumb (`icthumb.jpg`) or `icplaceholder`,
  black overlay alpha 40/255 + `CellFlickerDrawable` sweep inset 1dp (ICV:408-427,
  715-729, 745).
- **Progress ring**: rect = circle bounds inset **-8dp**; stroke **3dp**, round cap,
  color **0xFFFFFFFF**; arc from **-90°**, sweep `360 * progress`;
  `progress = min(1, recordedTime / 60000)` — 60s cap (ICV:284-287, 612-629).
- Open/close animation (ICV:869-930): **180ms DecelerateInterpolator**; open:
  translateY height/2→0, scale 0.1→1, alpha 0→1, ring paint alpha 0→255; close: reverse,
  and if recordedTime > 300ms the circle also slides toward x = `24dp - width/2`
  (left edge, toward the chat bubble).
- Buttons row (flip camera / flash): container 56dp tall, bottom-left (leftMargin 1),
  padding 6dp; buttons **44x44dp**, icon size 24dp (new design; legacy 28) — flip icon
  lottie `roundcamera_flip`; glass background radius **21dp**, padding 6dp
  (ICV:260-267, 321-330, 385-387, 434-439, 708-713).
- Camera flip: rotationY sweep ±90° swap at midpoint, **580ms EASE_OUT_QUINT**, camera
  distance `height * 8` (ICV:342-382).
- Mute icon: `video_mute` 48x48dp, centered, shown at `topMargin size/2 - 24dp`
  (ICV:402-406, 521).
- Recording stop: TimerView stops video at 59.5s (§4); ControlsView hides pause >= 59s.

## 6. Theme color keys used

| Key | Used by |
|---|---|
| `chat_messagePanelBackground` | island glass tint (CA:3547); RecordDot lottie line layers (CAEV:999); legacy panel fill (CAEV:4691) |
| `chat_messagePanelText` / `chat_messagePanelHint` / `chat_messagePanelCursor` | text field (CAEV:5756-5761) |
| `chat_messageLinkOut`, `chat_inTextSelectionHighlight`, `chat_TextSelectionCursor` | field links/selection (CAEV:5757-5762) |
| `glass_defaultIcon` | emoji/attach/notify/delete-draft icons, mic/video outline drawables, slide arrow, lock glyph + once glyph (glass) (CAEV:2678, 2791, 2757, 3381-3385, 13969, 1723-1727) |
| `listSelector` | button ripples (CAEV:2679, 2793 …) |
| `chat_messagePanelSend` | 38dp send-area circle fill (CAEV:3189) |
| `chat_messagePanelVoiceBackground` | record circle fill, waves (alpha .30/.15), once-pill circle (CAEV:2228-2230, 2448-2450, 1714) |
| `chat_recordedVoiceBackground` | circle→seekbar color blend target (CAEV:2228) |
| `chat_messagePanelVoicePressed` | mic/camera/send icons inside record circle (CAEV:2010-2016) |
| `chat_messagePanelVoiceLock` | lock/pause glyph (non-glass) (CAEV:1723-1727) |
| `chat_messagePanelVoiceLockBackground` | lock + once pill background (CAEV:1687, 1722) |
| `chat_messagePanelVoiceLockShadow` | lock shadow drawable tint (CAEV:1212) |
| `chat_messagePanelVoiceDelete` | recorded-audio delete icon (CAEV:10350) |
| `chat_recordedVoiceDot` | blinking red dot (CAEV:998) |
| `chat_recordTime` | timer text + "Slide to cancel" + arrow (CAEV:14197, 13985, 14047-14050) |
| `chat_recordVoiceCancel` | CANCEL text + its ripple (CAEV:13986-13989) |
| `chat_gifSaveHintBackground` / `chat_gifSaveHintText` | "Slide up to lock" tooltip (CAEV:1213, 1718-1720) |
| `chat_messagePanelCancelInlineBot` | inline-bot cancel progress (CAEV:3415) |
| `chat_emojiPanelNewTrending` | emoji-button unread dot (CAEV:2569) |
| `telegram_color` | ephemeral send outline `send_outline` (CAEV:2894) |
| `paint_chatComposeBackground` | legacy no-blur panel paint (CAEV:4699) |

All keys above exist in `flutter/telegram_ui/lib/src/tokens/theme_keys.g.dart`
(`TelegramColorKey`) and resolve through `TelegramTheme.colorOf` with the standard
fallback chain.

## 7. Port notes

- The island bubble/keyboard glass already have Flutter counterparts:
  `GlassPresets.bottomPanelChat` (tint/strokes) and the frosted backdrop constant
  `kFrostedBackdropBlurRadiusDp = 38.34`; the keyboard panel additionally needs
  thickness 32dp / intensity 0.4 via `LiquidGlassSettings` (§1).
- Optional `TelegramResources? resources` parameter convention applies to every widget.
- Mic amplitude, camera preview frames, and encoder hooks are **callback slots**
  (`ValueListenable<double>` amplitude, `Widget?` preview builder); never implement
  capture.
- `dp2(26)` (floor) for the record-circle center is intentionally not `dp(26)` (ceil);
  at 1:1 logical px both are 26.0.
