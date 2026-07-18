# Liquid Glass Visual System — Complete Numeric Spec (Telegram Android → Flutter port)

All paths relative to `/home/user/Telegram/`. `dp(v)` = `ceil(density * v)` (AndroidUtilities.java:2708-2713); `dpf2(v)` = `density * v` exact float (AndroidUtilities.java:2747-2752). All hex colors are ARGB.

---

## 1. Shader uniforms + updateDisplayList computation

### AGSL shader (`TMessagesProj/src/main/res/raw/liquid_glass_shader.agsl`)

Uniforms (lines 1-10):
| uniform | type | meaning |
|---|---|---|
| `img` | shader | backdrop content (RuntimeShaderEffect input named "img") |
| `resolution` | float2 | node w/h — **declared and set but never read in `main()`** |
| `center` | float2 | rect center in node coords |
| `size` | float2 | **half**-width, **half**-height (line 53-54 of LiquidGlassEffect: `width/2`, `height/2`) |
| `radius` | float4 | corner radii, order below |
| `thickness` | float | lens rim thickness in px |
| `refract_index` | float | index of refraction |
| `refract_intensity` | float | displacement multiplier |
| `foreground_color_premultiplied` | float4 | tint, premultiplied RGBA |

Shader math (lines 12-46):
- SDF: `sdfRect` — rounded-box SDF selecting per-corner radius: `r.xy = (p.x > 0) ? r.xy : r.zw; r.x = (p.y > 0) ? r.x : r.y` (lines 13-14). So component mapping is **radius = (x: right-bottom, y: right-top, z: left-bottom, w: left-top)**.
- Inside (`sd < 0`): normal from SDF finite differences at +1px in x and y (lines 30-31); `n_cos = max(thickness + sd, 0) / thickness` (line 33 — flat interior beyond `thickness` from edge), `n_sin = sqrt(1 - n_cos²)`; normal = normalize((sdX−sd)·n_cos, (sdY−sd)·n_cos, n_sin) (line 36).
- Refraction: `refract((0,0,-1), normal, 1.0/refract_index)` (line 38); lens height `h = sd < -thickness ? thickness : sqrt(sd·(−2·thickness − sd))` (line 39); ray length `(h + 8.0·thickness) / −refract_vec.z` (line 40 — **constant 8.0**); `uv += refract_vec.xy * refract_length * refract_intensity` (line 42).
- Output: `srcOver(foreground_color_premultiplied, img.eval(uv))` (line 45) — the tint is composited **inside** the shader.

### LiquidGlassEffect.java (`TMessagesProj/src/main/java/org/telegram/ui/Components/blur3/LiquidGlassEffect.java`)

- Wraps the fill RenderNode with `RenderEffect.createRuntimeShaderEffect(shader, "img")` (line 24), recreated after each uniform change (line 98).
- `update(...)` (lines 39-100):
  - `center = ((left+right)/2, (top+bottom)/2)`, `size = (width/2, height/2)` (lines 50-54).
  - **Vertical-only radius clamp** (lines 56-65): if `radiusLeftTop + radiusLeftBottom > height`, both scaled proportionally to sum to `height` (same for right pair). No horizontal clamp.
  - Change-detection epsilon **0.1f** per float uniform (lines 67-82); exact int compare on color.
  - Premultiplied tint: `a = alpha/255; r = red/255·a; ...` (lines 85-88).
  - **Line 93 — radius uniform component order**: `setFloatUniform("radius", radiusRightBottom, radiusRightTop, radiusLeftBottom, radiusLeftTop)` — i.e. (RB, RT, LB, LT), matching the SDF's selection logic above.

### BlurredBackgroundDrawableRenderNode.updateDisplayList (`.../blur3/drawable/BlurredBackgroundDrawableRenderNode.java` lines 101-154)

- Thickness (lines 116-118): `thickness = max(min(liquidThickness <= 0 ? dp(11) : liquidThickness, min(boundsWidth, boundsHeight) / 5), 1)` — **default dp(11), clamped to min(w,h)/5, floor 1px**.
- `liquidGlassEffect.update(0, 0, w, h, shaderRadii[0], shaderRadii[2], shaderRadii[4], shaderRadii[6], thickness, liquidIntensity, liquidIndex, backgroundColor)` (lines 120-127) — parameters are (LT, RT, RB, LB); `shaderRadii` indices 0/2/4/6 = topLeft/topRight/bottomRight/bottomLeft (set in BlurredBackgroundDrawable.setRadius, lines 99-131).
- Fill node records the source translated by `-(boundsWithPadding.left + sourceOffsetX, boundsWithPadding.top + sourceOffsetY)` (lines 107-114).
- Composition (lines 134-142): if backgroundColor alpha == 255 → just `drawColor` (no glass); else draw fill node (glass shader applies tint itself); if **no** glass effect and bg alpha != 0, tint drawn via `drawColor` on top.
- Note: `shaderRadii` keeps the *un-forced* radii when `setRadius(..., forceBottomZero=true)` zeroes the clip `radii` (BlurredBackgroundDrawable.java:119-131) — the refraction keeps rounded bottom corners even when the clip is square.

---

## 2. Production values of liquid parameters

Defaults (BlurredBackgroundDrawable.java `Props`, lines 223-225): `liquidThickness = 0` (→ dp(11) at draw), **`liquidIntensity = 0.75f`**, **`liquidIndex = 1.5f`**.

**`liquidIndex` has no setter anywhere — it is always 1.5 in production.**

Setters: `setThickness(int)` (BlurredBackgroundDrawable.java:133), `setIntensity(float)` (line 139). (There is no `setLiquidThickness`; `setLiquidGlassEffectAllowed()` is the enable switch, gated on `LiteMode.FLAG_LIQUID_GLASS` + API 33.)

Caller values:
| Caller | thickness | intensity |
|---|---|---|
| ChatInputViewsContainer.java:89-90 (under-keyboard panel) | dp(32) | 0.4 |
| ChatAttachAlert.java:3035-3036 (emojiViewChildBg) | dp(32) | 0.4 |
| ShareAlert.java:1822-1823 (emojiViewChildBg) | dp(32) | 0.4 |
| Stories/recorder/CaptionContainerView.java:257-258 | dp(32) | 0.4 |
| Stories/PeerStoriesView.java:561 (emoji keyboard bg) | dp(32) | (default 0.75) |
| Components/RecyclerListView.java:1068 (fast-scroll tag) | dp(4) | default |
| Components/SearchTagsList.java:127, 797 (tag chips) | dp(5) | default |
| Everything else (tab bar, action bars, panels) | default dp(11) | default 0.75 |

`setLiquidGlassEffectAllowed(LiteMode.isEnabled(LiteMode.FLAG_LIQUID_GLASS))` call sites: MainTabsActivity.java:340, DialogsActivity.java:2803/2805, ChatActivity.java:2601/2609, ProfileActivity.java:2071, TopicsFragment.java:319, CallLogActivity.java:193, StatisticActivity.java:223, ShareAlert.java:429/431, ChatAttachAlert.java:1312/1314, SelectAudioAlert.java:176/178, StarGiftPreviewSheet.java:195, EmojiView.java:2849, ChannelAdminLogActivity.java:358/366.

---

## 3. DownscaleScrollableNoiseSuppressor (`.../blur3/DownscaleScrollableNoiseSuppressor.java`)

Per-`SourcePart` pipelines (constructor, lines 408-428):
- **Liquid glass enabled**:
  - `renderNodesForGlass`: downscale **4×4**, blur **dpf2(6)** chained with **saturation ×3** color-matrix effect (lines 410-412). This is the "glass" backdrop.
  - `renderNodesForBlur`: downscale **8×8**, blur **dpf2(40 − 1.66) = dpf2(38.34)** (lines 413-415). Input is the *restored glass output* (`SourcePart.invalidate`, lines 438-445) — i.e. **frosted = blur₃₈.₃₄(saturate₃(blur₆(src)))**.
- **simpleMode, no glass**: single chain, downscale **8×8** (or **16×16** if `allowNoiseSuppress`), blur **dpf2(40)** + saturation ×3 (lines 416-420).
- **non-simple, no glass**: downscale 8×8, blur dpf2(40), with secondary effect [1] = saturation ×3 (lines 421-427). Result semantics (comment lines 291-294): Glass mode: `[0]` weak blur+sat, `[1]` strong blur+sat; Blur mode: `[0]` strong blur no matrix, `[1]` strong blur+sat.

Saturation effect: `ColorMatrix.setSaturation(3f)` → `RenderEffect.createColorFilterEffect` (RenderNodeEffects.java:28-36; ×2 and ×4 variants also exist, lines 18-26/38-46).

Radius↔sigma conversion (lines 256-277), mirroring Android hwui:
- `BLUR_SIGMA_SCALE = 0.57735f` (= 1/√3, line 261)
- `convertRadiusToSigma(r) = r > 0 ? 0.57735·r + 0.5 : 0` (line 263-265)
- `convertSigmaToRadius(s) = s > 0.5 ? (s − 0.5)/0.57735 : 0` (line 267-269)
- `downscaleRadius(r, scale) = max(1, sigmaToRadius(radiusToSigma(r)/scale))` (line 271-273) — applied per axis when setting blur on the downsampled node (lines 134-153).
- `MAX_RADIUS_FOR_FAST_BLUR = 2.595f` (line 276).

Other constants: capture prescale `k` = 1 when glass or noise-suppress, else 8 (line 40); source-part rects snapped to a **16 px** grid (roundDown/roundUp, lines 431-436, 448-454); scroll noise suppression phase-wraps translation modulo the scale factor (lines 239-252). Draw modes: `DRAW_GLASS = −2`, `DRAW_FROSTED_GLASS = −3`, `DRAW_FROSTED_GLASS_NO_SATURATION = −4` (lines 49-51).

---

## 4. BlurredBackgroundColorProviderThemed (`.../blur3/drawable/color/BlurredBackgroundColorProviderThemed.java`)

- Default tint alpha: **0.85 when liquid glass enabled, 0.76 otherwise** (line 16). `backgroundColor = multAlpha(themeColor, alpha)` (line 41).
- Dark detection: `computePerceivedBrightness(color) < 0.721f` (lines 34-37); brightness = `(0.2126·R + 0.7152·G + 0.0722·B)/255` (AndroidUtilities.java:4973-4975).
- Dark theme (lines 43-46): strokeTop `0x28FFFFFF`, strokeBottom `0x14FFFFFF`, shadow `0`.
- Light theme (lines 47-51): strokeTop `0xFFFFFFFF`, strokeBottom `0xFFFFFFFF`, shadow `0x20000000`.

### Per-surface builder providers (`.../color/impl/BlurredBackgroundProviderImpl.java`)
Builder color args are `(light, dark)` (BlurredBackgroundProviderBuilder.java:29-42); builder defaults: shadow layer `(dpf2(1), 0, dpf2(1/3))`, stroke widths `(dpf2(1), dpf2(2/3))` (lines 15-16). Key production recipe — **mainTabs** (lines 19-33): bg = `solveSrcColor(windowBackgroundWhite → glass_targetMainTabs @ alpha 0.85/0.76)`; strokeTop `0x11000000`/`0x06FFFFFF`; strokeBottom `0x20000000`/`0x11FFFFFF`; shadow `0x20000000`/`0x04FFFFFF`; shadow layer radius `dpf2(2.667)`, dx 0, dy `dpf2(0.85)`; stroke widths `dpf2(0.4)`/`dpf2(0.4)`. `solveSrcColor` (lines 288-316) inverse-solves src-over so the composite over `bgColor` lands exactly on `outColor`: `src = clamp((out − bg·(1−a))/a)`. Other surfaces (topPanel, emojiViewButton, bottomPanelChatActivity, etc.) at lines 35-286 follow the same pattern with values as listed in the file.

---

## 5. BlurredBackgroundDrawable base (`.../blur3/drawable/BlurredBackgroundDrawable.java`)

Constructor defaults (lines 46-53): strokeWidthTop **dpf2(1)**, strokeWidthBottom **dpf2(2/3)**; shadowLayerRadius **dpf2(1)**, dx **0**, dy **dpf2(1/3)**. `setColorProvider` overrides these when the provider is a `BlurredBackgroundProvider` (lines 189-199). Shadow paint has color 0 + `setShadowLayer(radius, dx, dy, multAlpha(shadowColor, nodeAlpha·shadowAlpha))` → only the shadow renders (RenderNode drawable, lines 186-190); `inAppKeyboardOptimization` clips the shadow to `top + radii[0]·2` (lines 284-297).

### drawStroke (static, lines 392-490 — the version used by the RenderNode drawable)
- Stroke is a STROKE-style paint of width `strokeWidth`; `strokeHalf = strokeWidth/2` (line 403).
- **Top** (isTop=true): clip to `(left, top, right, clamp(top + radii[0]·2, top, bottom))` then draw round-rect at `(left − strokeHalf, top + strokeHalf, right + strokeHalf, bottom + strokeHalf)` (lines 405-420) — i.e. inflated horizontally/downward so **only the top edge + top corner arcs of the stroke land inside the clip**, inset by half the stroke so the line straddles the edge inward.
- **Bottom** (isTop=false): clip to `(left, clamp(bottom − radii[4]·2, top, bottom), right, bottom)`, round-rect at `(left − strokeHalf, top − strokeHalf, right + strokeHalf, bottom − strokeHalf)` (lines 448-461).
- If the 4 top (or bottom) radii differ, it splits at `cx = (left+right)/2` and draws two clipped passes with per-corner radii pairs (lines 421-447, 462-488).
- The software-path equivalent uses filled ring **paths** instead (`strokePathTop/Bottom`: outer round-rect CW + inset round-rect CCW, capped at `radii·` extent; Props.build lines 260-281), radii capped at `min(w,h)/2` when uniform (lines 253-258).

---

## 6. BlurredBackgroundWithFadeDrawable (`.../blur3/BlurredBackgroundWithFadeDrawable.java`)

Wraps a `BlurredBackgroundDrawable` and masks it with a vertical alpha gradient (DST_IN xfermode, line 56) — used for the edge-fade under floating bars.
- Default fade height **dp(40)**, `opacity=false` (line 58); MainTabsActivity uses **dp(60), opacity=true** (MainTabsActivity.java:352).
- Gradient (`createGradient`, lines 211-230): a 1-px-tall `LinearGradient(0,0 → 0,1)` scaled to `fadeHeight` via matrix (lines 71-76); negative `fadeHeight` flips it and anchors to the bottom (`offset = bounds.height() + fadeHeight`, lines 73-74, 112-114, 179-181). Stops evenly spaced (positions=null):
  - `opacity=true` (4 stops): alphas `0, 0x60·a/285, 0xB0·a/285, 0xE8·a/285` — **note divisor 285**, so max ≈ 0.813·a (lines 214-220).
  - `opacity=false` (5 stops): alphas `0, 0x60·a/255, 0xB0·a/255, 0xE8·a/255, 0xFF·a/255` (lines 223-229).
- Fast paths: solid-color source → draws only the gradient in that color (lines 101-123); bitmap source → `ComposeShader(bitmapShader, gradient, DST_IN)` (lines 125-172); otherwise saveLayer + drawable + DST_IN gradient rect (lines 177-186).

---

## 7. Tab bar geometry

Constants (DialogsActivity.java:289-291): **`MAIN_TABS_HEIGHT = 56`** (dp), **`MAIN_TABS_MARGIN = 8`**, **`MAIN_TABS_HEIGHT_WITH_MARGINS = 72`**.

MainTabsActivity.java:
- tabsView padding **dp(12)** on all sides (`MAIN_TABS_MARGIN + 4`, line 287); max width **dp(344)** (`328 + 8·2`, line 288).
- Glass background: **corner radius dp(28)** (`MAIN_TABS_HEIGHT/2`, line 343); drawable padding **dp(7.666)** (`MAIN_TABS_MARGIN − 0.334`, line 344) → visible pill is 56.668dp tall inside the 72dp view; color provider `BlurredBackgroundProviderImpl.mainTabs` (line 342).
- tabsView placed at height 72dp, bottom-center of wrapper (line 359); bottom fade view: `setFadeHeight(dp(60), true)` (lines 350-353).
- Vertical placement (DialogsActivity.java:14167-14168, mirrored in ContactsActivity/ProfileActivity/SettingsActivity/CallLogActivity/TopicsFragment/StatisticActivity): `tabBottom = viewHeight − navigationBarHeight − dp(8)`, `tabTop = tabBottom − dp(56)`. Content bottom inset: `navigationBarHeight + dp(72)` (DialogsActivity.java:2978; MainTabsActivity.java:192 uses `navBar + dp(56+8)` for offset).

MainTabsLayout.java: text auto-size passes `PASS_TEXT_SIZES_DP = {12, 12, 10}` with `PASS_PADDINGS_DP = {16, 8, 4}` dp side padding (lines 46-47); min total tab width **dp(320)** (line 69); tabs get equal-weight growth, shrink multiplicatively if overflowing (lines 97-133). Long-press: bar scales to **1.019** over 380ms EASE_OUT_QUINT (lines 436-439); floating selector = round rect of interpolated tab width, height = layout height minus padding, radius = height/2, color `glass_tabSelected` @ **0.09** alpha (lines 289, 310-324); springs: selector position stiffness MEDIUM / damping LOW_BOUNCY, scale springs stiffness 250 / damping 0.25 (lines 356-369); long-press duration = default × 0.75 (line 485); pivot mapping `mappedR = 1.5·r/(r+0.5)`, pivotY lerp factor 3 (lines 563-604).

GlassTabView.java:
- Default icon: RLottie 44×44dp at top offset −6dp (line 83); main tabs re-layout icon to **24×24dp, top margin 4dp** (line 406); label **12dp bold**, top margin **28.33dp** (lines 88, 96); avatar tab: 22×22dp at top 5dp, round radius dp(11) (lines 424-427).
- Selected pill behind tab (lines 154-165): color = selected color @ **0.09·alpha**, radius `min(w,h)/2`, scale `lerp(0.6, 1, selectedFactor)`, DECELERATE interpolated; selection animator 320ms DECELERATE (line 67).
- Counter badge (lines 175-212): punch-out gap **dpf2(1.33)**, center `(w/2 + dpf2(11), dpf2(10))`, height **dpf2(16)**, width `max(height, textWidth + dp(8))`, outer clear radius **dpf2(9.333)**, inner fill radius **dpf2(8)**, text 10dp bold white (line 103); counter show animator 380ms EASE_OUT_QUINT (lines 68-69).
- Attach-tab width: `min(dp(84), textWidth + 2·lerp(dpf2(16), dp(8), clamp((textWidth − dp(40))/dp(16), 0, 1)))`, text 11dp (lines 485-489, 445).
- Colors from theme keys `glass_tabUnselected` / `glass_tabSelected` / `glass_tabSelectedText` (lines 407-409); defaults `0xFF1A1D21` / `0xFF1a91e6` / `0xFF0d7fcf`, targets `glass_targetMainTabs`/`glass_targetMainTopPanel` default `0xFFFFFFFF` (ThemeColors.java:824-828; fallbacks Theme.java:4484-4488).

GlassTabsView.java (attach-menu variant): padding dp(8) (line 34), lens foreground inset `−dp(7·lensVisibility)` (line 62).

Related: StrokeDrawable (`.../blur3/StrokeDrawable.java`) draws stroke-only circles/rects with fixed widths dpf2(1) top / dpf2(2/3) bottom (lines 57-60, 82-85).