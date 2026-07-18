# ARCHITECTURE.md — `telegram_ui` Flutter Port of the Telegram Android Design System

**Status:** Final synthesis (chief architect). Skeleton: FIDELITY-FIRST proposal; grafted with the PERFORMANCE-FIRST engine-sharing/benchmark discipline and the API/DX-first codegen and public-API structure. Judge disagreements resolved as follows: the three judges split 1/1/1, so the deciding criterion is the project's stated purpose — a *design-system port* whose acceptance test is visual parity with `blur3/` + `liquid_glass_shader.agsl`. FIDELITY-FIRST is therefore the skeleton (it is the only proposal whose rendering design can actually reproduce rim refraction, stroke rings, and fade masks, with every constant verified at line level), but its two weakest lenses — per-frame cost and codegen ergonomics — are replaced wholesale by grafts: BackdropGroup sharing, runtime probe/warmup, TimelineSummary budgets, and layer-count guards from PERFORMANCE-FIRST; the checked-in `theme_tokens.json` intermediate, split entry points, `groups.toml` typed accessors, and licensing flag from API/DX-first.

All Android source paths below are relative to `/home/user/Telegram/TMessagesProj/src/main/`.

---

## 1. Goals and non-goals

### Goals

1. **Pixel-parity port of the liquid-glass rendering system**: the SDF rounded-box refraction shader (`res/raw/liquid_glass_shader.agsl`), the downscaled blur/saturation pyramid (`java/org/telegram/ui/Components/blur3/DownscaleScrollableNoiseSuppressor.java`), the themed tint/stroke/shadow drawable (`blur3/drawable/BlurredBackgroundDrawable*.java`), and the edge fade (`blur3/BlurredBackgroundWithFadeDrawable.java`). Acceptance is measured against Android ground-truth captures, not eyeballs.
2. **Full theme-token parity**: all **777** int color keys (declared as `colorsCount++` in `ui/ActionBar/Theme.java` starting line 3364 — *not* ThemeColors.java, and *not* ~1533 as earlier context claimed), the 760 defaults and 773 attheme-name mappings from `ThemeColors.java`, the 183-entry fallback table, `.attheme` load/save, day/night, and a per-surface `ResourcesProvider` analog.
3. **Flagship surface**: the `MainTabsActivity` floating glass tab bar (`ui/Components/glass/GlassTabsView.java` / `GlassTabView.java`) reproduced exactly, plus a v1 component catalog (ActionBar, list cells, bulletin, bottom sheet).
4. **Performance floor**: 60fps (stretch 120fps) scroll with glass chrome on Adreno/Mali-6xx-class devices; zero shader-compile jank; bounded GPU memory; graceful tier degradation mirroring `LiteMode.FLAG_LIQUID_GLASS`.
5. **SDK-less developability**: all codegen is Python stdlib; generated Dart is committed; correctness that can be verified without a Flutter SDK (Python fixture parity, pytest snapshots) is verified that way; CI on pinned stable Flutter is the compile authority.
6. **Consumable API**: three altitudes — raw primitive (`LiquidGlass`), themed surface (`GlassSurface`), finished components — with a-la-carte entry points so a non-Telegram app can depend on the glass effect alone.

### Non-goals (v1)

- Wallpaper rendering, accent hue-shifting (`ThemeAccent.fillAccentColors`), and chat-specific theming beyond the token layer (the `.attheme` wallpaper blob is passed through as opaque bytes, never interpreted).
- Web/desktop rendering targets (Impeller-on-mobile is the target; other backends get the frosted/tint fallback and are untested for parity).
- Full RLottie fidelity for tab icons (frame-control *contract* ships in v1; a thorvg/rlottie FFI binding is future work).
- Continuous/squircle corners in `GlassShape` (the SDF is a rounded box; explicitly out of scope).
- Chat message rendering (ChatBubble is deferred; it is outside the extracted spec scope).
- pub.dev publication — **blocked on a licensing decision**: Telegram Android is GPLv2; porting its shader and tokens likely inherits copyleft obligations (see Risks).

---

## 2. Directory layout

```
flutter/                                       # NEW top-level directory in this repo
├── README.md                                  # setup, licensing note, SDK version pin
├── telegram_ui/                               # the pub package
│   ├── pubspec.yaml                           # name: telegram_ui; flutter: { shaders: [shaders/liquid_glass.frag] }
│   │                                          # pinned SDK constraint (exact stable minor; see Risks)
│   ├── shaders/
│   │   └── liquid_glass.frag                  # hand-ported GLSL of res/raw/liquid_glass_shader.agsl
│   ├── lib/
│   │   ├── telegram_ui.dart                   # umbrella export
│   │   ├── glass.dart                         # a-la-carte: glass primitives only          [graft: API/DX]
│   │   ├── theme.dart                         # a-la-carte: theme system only              [graft: API/DX]
│   │   └── src/
│   │       ├── foundation/
│   │       │   ├── dimens.dart                # dp()/dpf2() semantics + opt-in fidelityRounding
│   │       │   ├── blur_math.dart             # radiusToSigma/sigmaToRadius/downscaleRadius (verbatim port)
│   │       │   ├── color_math.dart            # multAlpha, compositeColors, perceivedBrightness, solveSrcColor
│   │       │   └── tg_curves.dart             # CubicBezier constants, BoolFactor (BoolAnimator analog)
│   │       ├── tokens/                        # ALL generated by tool/ (committed, CI --check'd)
│   │       │   ├── theme_keys.g.dart          # 777 const int keys, identical ordinals to Theme.java
│   │       │   ├── theme_key_names.g.dart     # attheme name<->key maps (from createColorKeysMap)
│   │       │   ├── theme_fallbacks.g.dart     # 183-entry fallback map
│   │       │   ├── palettes/                  # defaults + bundled-theme overlay maps
│   │       │   ├── color_scheme.g.dart        # grouped typed accessors (groups.toml)      [graft: API/DX]
│   │       │   ├── glass_metrics.g.dart       # scalar constants extracted per extract_spec.yaml
│   │       │   └── liquid_glass_uniforms.g.dart  # uniform slot indices parsed from the .frag
│   │       ├── theme/
│   │       │   ├── telegram_theme_data.dart   # Int32List-backed data model, copyWith/lerp
│   │       │   ├── telegram_resources.dart    # TelegramResources (ResourcesProvider analog)
│   │       │   ├── resources_override.dart    # sparse per-surface delta
│   │       │   ├── telegram_theme.dart        # InheritedModel scope + ThemeExtension bridge
│   │       │   └── attheme_codec.dart         # decode/encode, wallpaper blob passthrough
│   │       ├── glass/
│   │       │   ├── strategy.dart              # GlassTier {liquid,frosted,flat} × strategy {backdrop,snapshot,tint}
│   │       │   ├── runtime_probe.dart         # GlassRuntimeProbe (capability probe + shader warmup) [graft: PERF]
│   │       │   ├── geometry.dart              # GlassBoundsGeometry (Props port: stroke rings, shadow path)
│   │       │   ├── surface_colors.dart        # GlassSurfaceStyle + builder (BlurredBackgroundProviderBuilder port)
│   │       │   ├── presets.dart               # GlassPresets (BlurredBackgroundProviderImpl port, exact hex)
│   │       │   ├── liquid_glass_settings.dart # immutable value type, copyWith/lerp        [graft: API/DX]
│   │       │   ├── liquid_glass_shader.dart   # LiquidGlassUniforms (epsilon-diffed packer)
│   │       │   ├── backdrop_scope.dart        # GlassBackdropScope: BackdropGroup owner    [graft: PERF]
│   │       │   ├── glass_panel.dart           # GlassPanel / FrostedPanel widgets
│   │       │   ├── render_glass_surface.dart  # RenderGlassSurface: shadow -> backdrop -> child -> strokes
│   │       │   ├── glass_fade.dart            # GlassEdgeFade (dstIn gradient mask)
│   │       │   └── source_host.dart           # Strategy 2: GlassSourceHost + SnapshotBlurPipeline (phase 6)
│   │       └── components/
│   │           ├── tabs/     glass_tab_bar.dart, glass_tab.dart, tab_icon.dart, counter_badge.dart
│   │           ├── app_bar/  glass_app_bar.dart
│   │           ├── scaffold/ tg_scaffold.dart
│   │           ├── cells/    dialog_cell.dart, text_cell.dart, header_cell.dart, user_cell.dart,
│   │           │             shadow_section_cell.dart
│   │           ├── buttons/  glass_icon_button.dart
│   │           ├── sheet/    tg_bottom_sheet.dart
│   │           └── bulletin/ bulletin.dart
│   ├── test/                                  # Tier 1 + Tier 2 (flutter_tester-safe)
│   ├── integration_test/                      # Tier 3 device fidelity + perf goldens
│   └── example/                               # gallery app (pub `example/` convention)
│       ├── pubspec.yaml
│       ├── lib/  main.dart, pages/tabs_demo.dart, pages/glass_playground.dart, pages/theme_browser.dart
│       ├── integration_test/perf/             # TimelineSummary benchmark scenes           [graft: PERF]
│       └── test_driver/perf_driver.dart
└── tool/                                      # Python only, stdlib-only — no Flutter SDK required
    ├── gen_tokens.py                          # Theme.java + ThemeColors.java + assets/*.attheme -> theme_tokens.json
    ├── theme_tokens.json                      # CHECKED-IN intermediate (reviewable diffs)  [graft: API/DX]
    ├── groups.toml                            # prefix -> typed-group mapping, ungrouped catch-all
    ├── emit_dart.py                           # theme_tokens.json -> lib/src/tokens/*.g.dart (byte-stable)
    ├── extract_spec.yaml                      # curated (java file, regex, const) scalar extraction list
    ├── gen_shader_bindings.py                 # .frag uniforms -> liquid_glass_uniforms.g.dart
    ├── check_shader_parity.py                 # AGSL vs GLSL uniform name/order lint
    ├── gen_uniform_fixtures.py                # Python re-impl of LiquidGlassEffect.update -> test tables
    ├── fidelity_diff.py                       # SSIM + deltaE region-budgeted compare
    ├── tests/                                 # pytest (runs in this environment today)
    └── fixtures/                              # synthetic backdrops + android_ref/ ground-truth PNGs
```

---

## 3. Glass rendering design

### 3.1 The Android pipeline being ported (reference model)

Three stages, all numbers verified in source:

1. **Backdrop pyramid** (`DownscaleScrollableNoiseSuppressor.java:408-428`):
   - *Glass chain*: downscale **4×**, blur **dpf2(6)**, saturation **×3** color matrix.
   - *Frosted chain*: downscale **8×**, blur **dpf2(40 − 1.66) = dpf2(38.34)** — applied to the *restored glass output* (`SourcePart.invalidate`, lines 438-445), i.e. **frosted = blur₃₈.₃₄(saturate₃(blur₆(src)))**. This double-blur composition is mandatory (judge-confirmed graft; naive single-blur frosted is wrong).
   - Radius↔sigma: `sigma = 0.57735·r + 0.5` (r > 0), `radius = (sigma − 0.5)/0.57735`, `downscaleRadius(r,k) = max(1, sigmaToRadius(radiusToSigma(r)/k))` (lines 261-273). `MAX_RADIUS_FOR_FAST_BLUR = 2.595`.
   - Source rects snap to a **16 px grid**; scroll noise suppression phase-wraps translation modulo the downscale factor.
2. **Refraction shader** (`liquid_glass_shader.agsl` + `LiquidGlassEffect.java`): SDF rounded box; per-corner radius selection; normal from 1-px finite differences; `n_cos = max(thickness + sd, 0)/thickness`; `refract((0,0,-1), n, 1/refract_index)`; lens height `h = sd < −thickness ? thickness : sqrt(sd·(−2·thickness − sd))`; ray length `(h + 8.0·thickness)/−refract.z`; `uv += refract.xy · length · refract_intensity`; output = `srcOver(foreground_color_premultiplied, img.eval(uv))` — **the themed tint is composited inside the shader**.
3. **Vector overlay** (`BlurredBackgroundDrawable.java`): blurred drop shadow drawn *before* the node; dual top/bottom hairline stroke rings clipped to the corner-radius bands drawn *after*.

### 3.2 Widget tree and strategies

One public API, tiered rendering. Tier (`liquid` / `frosted` / `flat`, mirroring `DRAW_GLASS` / `DRAW_FROSTED_GLASS` / LiteMode-off) is orthogonal to strategy (`backdropShader` / `snapshotCache` / `tintOnly`).

```
TgScaffold
└── GlassBackdropScope                 // owns BackdropGroup; one per page  [graft: PERF]
    ├── RepaintBoundary                // scrollable body content
    │   └── body (ListView …)
    └── Stack overlay slots
        ├── GlassEdgeFade(60dp)        // behind the tab bar
        ├── GlassAppBar → GlassPanel(frosted)
        └── GlassTabBar → GlassPanel(liquid, GlassPresets.mainTabs)
                          └── RenderGlassSurface (RenderProxyBox)
                              paint order: shadow → backdrop layer → child → strokes
```

**Strategy 1 — `backdropShader` (default).** `RenderGlassSurface.paint()`:

1. **Shadow phase**: `drawPath(GlassBoundsGeometry.path)` translated by `(shadowDx, shadowDy)`, `MaskFilter.blur(normal, radiusToSigma(shadowRadius))`, color `multAlpha(shadowColor, opacity·shadowAlpha)`. Defaults: radius **dpf2(1)**, dx **0**, dy **dpf2(1/3)** (`BlurredBackgroundDrawable.java:46-53`).
2. **Fill phase**: pushes a `BackdropFilterLayer` participating in the enclosing `BackdropGroup` (grouped backdrops share **one** backdrop snapshot per frame — the Flutter analog of blur3's shared `SourcePart` nodes). The filter is the composed chain, inner-first matching Android:
   - liquid: `compose(outer: ImageFilter.shader(fragShader), inner: compose(outer: saturation×3 ColorFilter, inner: compose(matrix(1/4)·blur(downscaleSigma(6dp·dpr, 4), clamp)·matrix(4))))`
   - frosted: liquid's blur+saturate stage **then** `blur(downscaleSigma(38.34dp·dpr, 8))` with the 8× matrix sandwich; no refraction shader; tint painted as one `drawRRect` at alpha **0.76**. Optional `emulateDownscale` (default on for frosted) keeps the matrix sandwich to reproduce 8× bilinear-upsample softness.
   - The filter coverage rect is the panel rect **inflated by `bleed = ceil(8 · thickness · refractIntensity)` px** (derived from the shader's ray-length constant 8.0), and clipping is done **in-shader** via the SDF (transparent outside `sd > 0` with a 1-px smoothstep feather) rather than `ClipRRect` — a plain clip would clamp backdrop sampling and kill rim refraction. This is the single most fidelity-critical decision and is validated by **Spike Task 0** (see Phases), because backdrop-input coordinate/extent semantics are under-documented (cf. flutter/flutter#170820).
3. **Stroke phase**: `GlassBoundsGeometry` ports `Props.build()` — top ring = outer RRect (top radii) + copy shifted down by `strokeWidthTop`, `PathFillType.evenOdd`, clipped to the band `top … top + radii[0]·2`; mirrored for bottom. Filled, not stroked. Defaults **dpf2(1)** top / **dpf2(2/3)** bottom; radii capped at `min(w,h)/2` when uniform.

**Strategy 2 — `snapshotCache` (opt-in, phase 6).** Blur3-faithful cross-frame cache: `GlassSourceHost` wraps content in a RepaintBoundary; the boundary's `paint()` invocation is the free content-change signal (Flutter only paints a boundary when content changed — the analog of `Blur3HashImpl`, graft from PERF replacing an explicit hash delegate). On invalidation: `OffsetLayer.toImageSync(pixelRatio: dpr/k)` at k=4 and k=8, rects snapped to 16 px, blurred once into cached GPU `ui.Image`s (~650 KB + ~165 KB for a 1080×2400 backdrop); panels sample the cache through the same fragment shader via `sourceOffset`, tracked post-layout by `GlassSourceLink` (ViewPositionWatcher analog). `ScrollReprojector` ports `onScrolled`: translate by `scroll % k` between refreshes. Static frames cost one textured quad per surface. Escape hatch for heaviest screens and Skia-only targets.

**Strategy 3 — `tintOnly`**: rounded rect of `compositeColors(backgroundColor, sourceColor)` + strokes + shadow, no backdrop layer at all (the tier switch swaps the subtree; flat mode has zero readback cost). Also the deterministic path for Tier-2 goldens.

### 3.3 GLSL shader port

`shaders/liquid_glass.frag` is a mechanical port: `#include <flutter/runtime_effect.glsl>`, `FlutterFragCoord()`, `uniform sampler2D` bound as the filter input, `half → float`. Two deliberate additions: coverage-local coordinate handling (uniforms `center`/`size` set in filter-coverage pixels) and the SDF output clip (§3.2). Uniform table (order guarded by generated `liquid_glass_uniforms.g.dart` + `check_shader_parity.py`):

| uniform | value / convention |
|---|---|
| `resolution` | node w/h — set but never read in `main()` (kept for parity) |
| `center` | rect center |
| `size` | **half**-width, **half**-height (`LiquidGlassEffect.java:50-54`) |
| `radius` | float4 packed **(rightBottom, rightTop, leftBottom, leftTop)** — `LiquidGlassEffect.java:93`; the #1 silent-corruption hazard |
| `thickness` | px |
| `refract_index` | **1.5 always** — `liquidIndex` has no setter anywhere in production |
| `refract_intensity` | default **0.75** |
| `foreground_color_premultiplied` | tint, component-wise premultiplied |

### 3.4 Exact parameter defaults (from SPEC-GLASS)

| Parameter | Value | Source |
|---|---|---|
| Thickness | `max(min(dp(11), min(w,h)/5), 1)`; default **dp(11)** | BlurredBackgroundDrawableRenderNode.java:116-118 |
| Intensity / index | **0.75** / **1.5** | BlurredBackgroundDrawable.java:223-225 |
| Caller overrides | keyboard/attach panels: thickness **dp(32)**, intensity **0.4**; fast-scroll tag **dp(4)**; tag chips **dp(5)** | ChatInputViewsContainer.java:89-90 et al. |
| Uniform dirty epsilon | **0.1f** per float; exact int on color | LiquidGlassEffect.java:67-82 |
| Radius rescale | vertical pairs only: if `rLT+rLB > h` (or right pair), scale both to sum to `h`; no horizontal clamp | LiquidGlassEffect.java:56-65 |
| Glass blur / downscale / saturation | **6dp / 4× / ×3** | DownscaleScrollableNoiseSuppressor.java:410-412 |
| Frosted blur / downscale | **38.34dp / 8×**, over the glass output | ibid.:413-415, 438-445 |
| Tint alpha | **0.85** liquid / **0.76** frosted | BlurredBackgroundColorProviderThemed.java:16 |
| Dark threshold | `perceivedBrightness < 0.721`, brightness = `(0.2126R+0.7152G+0.0722B)/255` | ibid.:34-37; AndroidUtilities.java:4973-4975 |
| Themed strokes | dark: top `0x28FFFFFF`, bottom `0x14FFFFFF`, shadow 0; light: white/white, shadow `0x20000000` | ibid.:43-51 |
| Default stroke widths / shadow | **1dp / 0.667dp**; shadow **1dp**, dy **0.333dp** | BlurredBackgroundDrawable.java:46-53 |
| mainTabs preset | bg `solveSrcColor(windowBackgroundWhite → glass_targetMainTabs @ 0.85/0.76)`; strokeTop `0x11000000`/`0x06FFFFFF`; strokeBottom `0x20000000`/`0x11FFFFFF`; shadow `0x20000000`/`0x04FFFFFF`, radius **2.667dp**, dy **0.85dp**; strokes **0.4dp** | BlurredBackgroundProviderImpl.java:19-33 |
| Edge fade | default **40dp**, opacity=false: 5 evenly-spaced stops `0, 0x60, 0xB0, 0xE8, 0xFF` (÷255); MainTabs **60dp**, opacity=true: 4 stops `0, 0x60, 0xB0, 0xE8` **÷285** (max ≈ 0.813·a); DST_IN | BlurredBackgroundWithFadeDrawable.java:58, 211-230; MainTabsActivity.java:352 |
| `solveSrcColor` invariant | `composite(solve(bg, target, a), bg) == target` (±1/255/channel) — property-tested | BlurredBackgroundProviderImpl.java:288-316 |
| forceBottomZero quirk | shader radii keep un-forced values when the clip radii are zeroed — refraction stays rounded when the clip is square | BlurredBackgroundDrawable.java:119-131 |

### 3.5 Tier resolution, warmup, and layer hygiene (grafts: PERF)

- `TgShaders.ensureInitialized()` loads `FragmentProgram.fromAsset('packages/telegram_ui/shaders/liquid_glass.frag')` at startup; `GlassRuntimeProbe.run()` renders a 4×4 offscreen scene through the full liquid chain via `Picture.toImageSync` in try/catch — simultaneously detecting non-Impeller backends (auto-downgrade liquid → frosted) and pre-compiling the pipeline. A `GlassSettings` kill-switch forces any tier.
- Documented area budget: **liquid tier for small floating surfaces (tab bar, pills, chips); frosted for full-width bars** (GlassAppBar defaults to frosted, matching Android's frosted top bars).
- Debug assert bans `Opacity`/`ShaderMask`/`ColorFiltered` inside glass content; a widget test walks the layer tree asserting **exactly one shared backdrop snapshot per scope** in Strategy 1 and zero backdrop layers in snapshot/flat modes.
- RepaintBoundary rules: one around the scrollable body under the scope; one around each glass surface's child.
- Platform views (video/maps/WebView) under glass auto-degrade to frosted-with-solid-tint; documented limitation.

---

## 4. Theming

### 4.1 Token model

Android's model is kept verbatim, then wrapped in Flutter idiom:

- **Keys**: 777 dense int ordinals minted by `colorsCount++` in `Theme.java:3364+`. Generated `theme_keys.g.dart` preserves ordinals exactly; codegen asserts the parsed count (**777**, not ~1533) and fails on drift.
- **Defaults**: `ThemeColors.createDefaultColors()` — 760 flat assignments, zero-initialized array for the 17 unassigned keys (e.g. `chat_serviceBackground`, runtime-computed from wallpaper; `fill_RedDark`, resolved via fallback). Constants: `TELEGRAM_COLOR = 0xFF229AF0`, `TELEGRAM_COLOR_TEXT = 0xFF298ACF`, `DEFAULT_BLACK_TEXT = 0xFF1A1D21`.
- **Names**: `createColorKeysMap()` is authoritative — never derive names by string-munging. Known mismatches replicated: `key_listSelector → "listSelectorSDK21"`, `key_graySectionText → "key_graySectionText"` (upstream typo preserved), `key_chat_inGreenCall → "chat_inDownCall"`, `key_actionBarDefaultArchivedSearchPlaceholder → "actionBarDefaultSearchArchivedPlaceholder"`.
- **Resolution order** (port of `Theme.getColor`, Theme.java:9552-9614): `animatingColors → currentColors → fallbackKeys(currentColors) → defaultColors`, with 4 forced-opaque keys (`windowBackgroundWhite`, `windowBackgroundGray`, `actionBarDefault`, `actionBarDefaultArchived`: `|= 0xFF000000`). Fallbacks resolve at lookup time (not flattened at codegen), so sparse overrides keep fallback behavior.

### 4.2 Runtime classes

```dart
class TelegramThemeData {          // Int32List-backed; O(1) lookup, no map allocation
  final Int32List _argb; final Brightness brightness; final int revision;
  Color color(int key);            // full 777-key escape hatch
  final TelegramColorScheme colors; // generated typed groups: theme.colors.chat.inBubble
  factory TelegramThemeData.day();          // = "Blue" (bluebubbles.attheme is default day)
  factory TelegramThemeData.night();        // = "Dark Blue" (darkblue.attheme, default night)
  factory TelegramThemeData.fromAttheme(String src, {TelegramThemeData? base});
  TelegramThemeData copyWith(...);  static TelegramThemeData lerp(a, b, t);
}
abstract class TelegramResources { // Theme.ResourcesProvider analog (Theme.java:2949)
  Color getColor(int key);
  bool get isDark;                 // default: perceivedBrightness(getColor(windowBackgroundWhite)) < 0.721
}
class ResourcesOverride implements TelegramResources { parent + Map<int, Color> overrides; }
class TelegramTheme extends InheritedModel<int> { … }   // per-key aspects: minimal rebuilds
class TelegramResourcesScope extends InheritedWidget { … } // push override for a subtree
```

Every component takes an optional `TelegramResources? resources` constructor param that wins over the scope (mirroring the Java `resourcesProvider` convention). Glass surfaces retint via a `Listenable` driving `markNeedsPaint` + uniform updates — theme crossfade rebuilds zero elements under the bars. `ThemeExtension` bridge: `TelegramTheme.of` falls back to `Theme.of(context).extension<TelegramThemeExtension>()` inside a MaterialApp.

### 4.3 Codegen pipeline (Python, stdlib-only)

Three stages, intermediate checked in:

1. **Extract** (`gen_tokens.py`): Pass 1 — ordered `key_* = colorsCount++` decls from **Theme.java** (regex, line order = ordinal). Pass 2 — `defaultColors[...] = …` from ThemeColors.java, comments stripped first; RHS resolved by a strict evaluator (hex, signed decimal `& 0xFFFFFFFF`, the three class constants parsed from lines 14-16, `Color.WHITE/BLACK/TRANSPARENT`, `ColorUtils.setAlphaComponent`); **raise** on any unknown RHS or any assignment at brace depth > method level (guards against future conditionals). Last-write-wins on duplicates. Pass 3 — `colorKeysMap.put` names + `fallbackKeys.put` pairs. Pass 4 — parse the 5 bundled `.attheme` assets with Android-exact semantics, **including** dropping the final non-`\n`-terminated line of `day.attheme`/`arctic.attheme` (Android silently drops it; we replicate for parity and log a warning). Output: **`theme_tokens.json`** — checked in, so upstream Java churn arrives as reviewable JSON diffs.
2. **Group** (`groups.toml`): explicit prefix → group mapping (`chat_` → ChatColors, `chats_` → DialogsColors, `actionBar` → ActionBarColors, `glass_` → GlassColors, …) with an `ungrouped` catch-all + lint reporting newly-ungrouped keys — new upstream keys never break generation.
3. **Emit** (`emit_dart.py`): byte-stable, pre-formatted, header stamped with source SHA-256s. Outputs: `theme_keys.g.dart`, `theme_key_names.g.dart`, `theme_fallbacks.g.dart`, `palettes/*.g.dart` (defaults length 777 + sparse overlay maps for Blue/Day/Dark Blue/Night/Arctic Blue), `color_scheme.g.dart`, plus `glass_metrics.g.dart` from `extract_spec.yaml` (curated regex extraction of the scalar constants in §3.4 and §6, so drive-by Java edits surface as codegen diffs).

CI gates: `gen_tokens.py --check`, `emit_dart.py --check`, `check_shader_parity.py`, pytest snapshots — all runnable in this SDK-less environment.

### 4.4 `.attheme` support

`AtthemeDecoder`: line-per-entry `name=value`; values are Java signed-int decimals (`-1 → 0xFFFFFFFF`) or `#hex` (`Color.parseColor` semantics: 6-digit gets `FF` alpha); value parsing uses `Utilities.parseInt` semantics (first `-?[0-9]+` run); `WLS=` captured as wallpaper link; `WPS` marker stops parsing and the trailing bytes surface as `Uint8List? wallpaper` (opaque passthrough); unknown names warned and ignored (Theme.java tolerance). Themes are sparse overlays (185–498 lines vs 777 keys) resolved through fallbacks then defaults. `AtthemeEncoder` provides round-trip and doubles as the parser's test oracle. Day/night switching = `TelegramThemeData.lerp` driven by an AnimationController; `TelegramResourcesScope.attheme(asset)` scopes a theme to a subtree (per-chat-theme shape).

---

## 5. Typography and iconography

**Fonts** (facts from `AndroidUtilities.java`):
- Telegram "bold" = **Roboto Medium** (`fonts/rmedium.ttf`, `AndroidUtilities.bold()`, L260-269) → bundle `rmedium.ttf`, map to `FontWeight.w500`.
- Selected tab label = **Roboto ExtraBold** (`fonts/rextrabold.ttf`, `TYPEFACE_ROBOTO_EXTRA_BOLD`, L251) → bundle, map to `FontWeight.w800`.
- Bundle regular Roboto for body text and golden determinism. `TgTypography` exposes named styles matching the extracted sizes (title 20/18/17dp, name 16dp medium, message 15dp, subtitle 14dp, label 12dp, counter 10dp bold, time 12dp). Pin `TextHeightBehavior` (no leading distribution, `applyHeightToFirstAscent/LastDescent: false`) — TextView and Paragraph metrics differ by default and this is golden-load-bearing.

**Curves/motion** (`CubicBezierInterpolator.java:11-14` → `tg_curves.dart`): `DEFAULT=(.25,.1,.25,1)`, `EASE_OUT=(0,0,.58,1)`, `EASE_OUT_QUINT=(.23,1,.32,1)`, `EASE_IN=(.42,0,1,1)`, plus Android `DECELERATE`. Motion grammar: **380ms EASE_OUT_QUINT** structural/emphasis, **320ms EASE_OUT_QUINT** width/color tracking, **200-250ms DEFAULT** modal fades, springs (stiffness 250–1500, damping 0.25–0.8) for gestures. `BoolFactor` ports `BoolAnimator`.

**Iconography / Lottie**: `TabIcon` abstraction with `TabIcon.static(ImageProvider)` and `TabIcon.lottie(...)` implementing the `TabAnimation` contract (`GlassTabView.java:545-569`): CHATS/CONTACTS/CALLS/SETTINGS play forward on select and reverse on deselect; paired `*_reverse` files for attach tabs; frame-segment animations BOOSTS (mid 25, end 49) and MONETIZATION (19, 45). The pub `lottie` adapter lives in the **example app** for v1 (keeps the dependency out of the core package); rlottie/thorvg FFI is future work. Static icon assets exported from the Android drawables at 24dp.

---

## 6. Component catalog v1

Each component doc-comments its Java source path and mirrors constants file-for-file. Anything Android draws with Canvas becomes a leaf CustomPainter/RenderBox.

| Component | Port of | Spec summary (extracted numbers) |
|---|---|---|
| **GlassPanel / FrostedPanel** | `BlurredBackgroundDrawableRenderNode` | §3 in full: thickness dp(11) clamp min(w,h)/5; intensity 0.75; index 1.5; alphas 0.85/0.76; strokes 1/0.667dp; shadow 1dp dy 0.333dp |
| **GlassEdgeFade** | `BlurredBackgroundWithFadeDrawable` | default 40dp / 5 stops ÷255; MainTabs 60dp opacity=true / 4 stops ÷285; DST_IN mask via saveLayer |
| **GlassBackdropScope** | shared `SourcePart` nodes | one BackdropGroup per page; layer-count-asserted |
| **GlassPresets** | `BlurredBackgroundProviderImpl` | all surface factories with exact hex (mainTabs per §3.4; topPanel, emojiViewButton, bottomPanelChat, attachMenuActionBar, scrimMenu, counterMini, premiumButton, photoViewer, searchFloatingDate, shadow) |
| **GlassTabBar** | `MainTabsActivity` + `MainTabsLayout` | height **56dp**, margin **8dp**, with-margins **72dp**; radius **28dp**; drawable padding **7.666dp**; view padding **12dp**; max width **344dp**; min row width **320dp**; text auto-fit passes {12,12,10}dp / paddings {16,8,4}dp; placement `bottom = h − navBar − 8dp`, content inset `navBar + 72dp`; show/hide translationY +40dp, 380ms EASE_OUT_QUINT; long-press bar scale **1.019**; drag selector `glass_tabSelected` @ **0.09** alpha, radius h/2, springs stiffness 1500/damping 0.75; pivot warp `mappedR = 1.5r/(r+0.5)`, pivotY lerp ×3 |
| **GlassTab** | `GlassTabView` | icon 24×24dp top 4dp; label **12dp** rmedium, top **28.33dp**, → rextrabold when selected; selection pill selected-color @ 0.09·decel(alpha), scale 0.6→1, **320ms DECELERATE**; color keys `glass_tabUnselected 0xFF1A1D21` / `glass_tabSelected 0xFF1A91E6` / `glass_tabSelectedText 0xFF0D7FCF`; avatar tab 22×22 top 5 radius 11dp |
| **CounterBadge** | `GlassTabView` L175-213 | punch-out via saveLayer + BlendMode.clear: height **16dp**, width `max(16, textW+8)`dp, inner r **8dp**, outer clear r **9.333dp**, gap **1.33dp**; center `(w/2 + 11dp, 10dp)`; text **10dp** bold white; fill blend(`telegram_color` → `fill_RedNormal`) by error factor; 380ms EASE_OUT_QUINT; premium variant: 96×16dp gradient + 14dp star |
| **GlassAppBar** | `ui/ActionBar/ActionBar.java` | 56dp portrait / 48dp landscape + status bar; glass pills radius **23dp**, `.setPadding(6dp)`, pill height **58dp** (`s=46dp, p=6dp`); back pill `[0, t, 58dp, b]`; glass title **17dp** rmedium, textLeft **76dp** (back) / **24dp**; subtitle 14dp `actionBarDefaultSubtitle`; forum per-corner 18.33/23/23/18.33dp animating with search alpha; menu width tracking 320ms EASE_OUT_QUINT; search fade 150ms; title swap ±20dp translate, subtitle crossfade 220ms; scroll color 320ms `windowBackgroundGray → actionBarDefault`; defaults to **frosted** tier |
| **DialogCell** | `ui/Cells/DialogCell.java` | height **70dp** (+3 tags) + 1px separator inset 72dp; avatar **52×52dp** @ (11, 9); text left **76dp**; name **16dp** rmedium baseline-top 14dp; message **15dp**; time **12dp** top 16; count top 38; unread badge height **20.666dp** (6.333 text pad, min width 8+pads), margin 15.666dp; three-line variant: 76dp tall, avatar 56×56 @ (11,11), text left 78dp; color keys `chats_*` per token table |
| **TextCell** | `ui/Cells/TextCell.java` | height **50dp** + 1px divider (inset 20/58/72dp); left padding 23dp; imageLeft 16dp; offsetFromImage **58dp**; title 16dp `windowBackgroundWhiteBlackText`; subtitle 13dp; value 16dp `windowBackgroundWhiteValueText`; switch 37×20dp @ 22dp from edge; disabled alpha 0.5 |
| **HeaderCell** | `ui/Cells/HeaderCell.java` | height **40dp**; text **14dp** rmedium `windowBackgroundWhiteBlueHeader`; padding 21dp h, top margin 7dp |
| **ShadowSectionCell** | `ui/Cells/ShadowSectionCell.java` | plain **12dp** spacer (9-patch shadows are commented out upstream) |
| **UserCell** | `ui/Cells/UserCell.java` | height **58dp** + 1px divider inset 68dp; avatar **46×46dp** @ (7+pad, 6); name 16dp rmedium @ (64+pad, 10); status **15dp** @ top 32, online color `telegram_color_text`; add-button height 28dp, radius 14dp, text 14dp bold |
| **Bulletin** | `ui/Components/Bulletin.java` | min height **48dp**; padding 16/8dp; radius **16dp**; bg `undo_background`; durations 1500/2750/5000ms; enter/exit **spring damping 0.8 stiffness 400**; lottie frame 56×48dp; text 15dp; swipe threshold w/3, 200ms; 8dp DST_OUT edge gradient; glass variant via `GlassPresets.bulletin` |
| **TgBottomSheet** | `ui/ActionBar/BottomSheet.java` | title row 48dp (big 20dp bold `dialogTextBlack`, normal 16dp `dialogTextGray2`); item cells **48dp** (button cell 80dp), icon frame 56×48 tint `dialogIcon`; open 250ms DEFAULT, dismiss 180ms EASE_OUT, companions 320ms EASE_OUT_QUINT |
| **GlassIconButton** | emojiViewButton preset | per `BlurredBackgroundProviderImpl` values |
| **TgScaffold** | — | installs GlassBackdropScope, `extendBodyBehindBars`, injects bottom inset `navBar + 72dp` |
| **Theme runtime + AtthemeCodec** | §4 | — |

---

## 7. Testing and verification strategy

The hard constraint: this dev environment has **no Flutter SDK**, and `flutter test` renders on a CPU backend where `ImageFilter.shader` does not run. Four rings, ordered by where they execute:

**Ring 0 — Python, runs here today.** pytest snapshot tests for `gen_tokens.py` against vendored Java fixtures; emitter goldens for all `.g.dart` outputs; `--check` regeneration diff as pre-commit + CI gate; attheme round-trip at JSON level; `gen_uniform_fixtures.py` — a Python re-implementation of `LiquidGlassEffect.update` (from the Java source) emitting `(input → expected uniform values)` tables covering the radius-pair rescale, the 0.1f epsilon, thickness clamp, and premultiply. Ring 0 carries codegen correctness entirely and pre-verifies the uniform driver's math before any Dart compiles.

**Ring 1 — Dart unit tests (CI, pinned stable Flutter).** `blur_math` vs hand-computed values (`radiusToSigma(6·3)=10.89…`, `downscaleRadius` at k=4/8/16); `solveSrcColor` property test (`composite(solve(bg,t,a), bg) == t` ±1/255); `perceivedBrightness` threshold cases around 0.721; `LiquidGlassUniforms` vs the Ring-0 fixture tables; token tests (count == **777**, 30 spot-checked key/name/color triples from §3 of the token spec, name-map handling of the 4 known mismatches); fallback-chain resolution; forced-opaque keys; `AtthemeCodec` against the 5 bundled assets including the dropped-final-line behavior; `GlassBoundsGeometry` evenOdd probe-point coverage; rebuild-granularity tests (change a chat key, assert an actionBar-dependent widget did not rebuild).

**Ring 2 — CPU-renderable goldens (flutter_test, CI).** Rendered with `tintOnly`/frosted paths (Skia-test-harness-safe): stroke rings at 0.4/1/0.667dp across DPR 2.0/2.625/3.0; shadow mask; fade gradients (both stop tables); GlassTabBar layout, selection pill, counter punch-out (BlendMode.clear); light + dark presets; all cells at fixed 393×852@3 with bundled Roboto. Layer-count regression test (§3.5). Shader-path goldens are tagged/quarantined — never gating.

**Ring 3 — device tests (integration_test, Android emulator + macOS, Impeller on; nightly).**
- *Fidelity*: each preset rendered over committed synthetic backdrops (hue gradient, checkerboard, photo) → `tool/fidelity_diff.py` compares against (a) self-references (regression, mean ΔE < 0.5) and (b) **Android ground truth** — one-time instrumentation captures of the real `GlassTabsView`/`BlurredBackgroundDrawableRenderNode` over the same backdrops, committed under `tool/fixtures/android_ref/`. Acceptance budgets evaluated per region: interior fill, 12px refraction edge band, stroke band — SSIM > 0.98 and mean ΔE < 1.5. A shader-only harness (full-screen quad sampling a fixture image) diffs the GLSL against AGSL renders of the identical scene, isolating port errors (uniform order, premultiply, uv normalization) from pipeline errors. A forced-degradation test (break FragmentProgram load, assert frosted fallback renders).
- *Performance* (graft: PERF): `flutter drive --profile` TimelineSummary scenes — 5s fling of a 500-row list under GlassTabBar; 5 grouped surfaces (stress the single-snapshot claim); animated day/night crossfade while scrolling; cold start with `--purge-persistent-cache` asserting no frame > 32ms post-warmup; Strategy 1 vs 2 A/B. Budgets: 90th pct raster < 8ms, build < 4ms (120Hz target); 99th pct raster < 16ms; missed frames == 0 on the reference mid-range device; JSON archived per commit.

**CI wiring**: Ring 0 + `--check` + shader parity lint on every PR (runs without SDK); Ring 1+2 + `flutter analyze --fatal-infos` + example-APK build on every PR (SDK runner); Ring 3 nightly. Because code is written blind, every PR must be CI-green before merge — small PRs mandatory.

---

## 8. Implementation phases

Ordered milestones; tasks within a phase are file-scoped for parallel AI-agent implementation. Dependencies point only backward.

**Phase 0 — Spikes + bootstrap (serial, blocking).**
- `S0a` *Backdrop semantics spike*: on-device prototype of `BackdropFilterLayer` with composed `blur → colorFilter → ImageFilter.shader`, inflated coverage, in-shader SDF clip, and `BackdropGroup` interaction. Decides: inflated-coverage design viable vs fall back to ClipRRect + documented rim clamp vs accelerate Strategy 2. Deliverable: written findings + captured frames.
- `S0b` `shaders/liquid_glass.frag` first port + shader-only harness scene.
- `S0c` CI bootstrap: python job, pinned-Flutter job, example skeleton, `perf_driver.dart`.

**Phase 1 — Codegen + foundation (parallel: 5 agents).**
- `tool/gen_tokens.py` + `tool/tests/` (agent A); `tool/emit_dart.py` + `groups.toml` (B); `tool/extract_spec.yaml` + `glass_metrics.g.dart` emission, `gen_shader_bindings.py`, `check_shader_parity.py`, `gen_uniform_fixtures.py` (C); `foundation/` — `dimens.dart`, `blur_math.dart`, `color_math.dart`, `tg_curves.dart` + Ring-1 tests (D); commit all `tokens/*.g.dart` + token tests (E).

**Phase 2 — Theme runtime (parallel: 3 agents).**
- `telegram_theme_data.dart` + `palettes` wiring + lerp (A); `telegram_resources.dart`, `resources_override.dart`, `telegram_theme.dart` + ThemeExtension bridge + rebuild-granularity tests (B); `attheme_codec.dart` + fixtures + round-trip tests (C).

**Phase 3 — Glass engine, Strategy 1 (parallel: 5 agents; consumes S0a findings).**
- `geometry.dart` (stroke rings, shadow path) + probe tests (A); `surface_colors.dart` + `presets.dart` with all hex constants + solveSrcColor property test (B); `liquid_glass_settings.dart` + `liquid_glass_shader.dart` (epsilon-diffed uniforms vs Ring-0 fixtures) (C); `backdrop_scope.dart` + `runtime_probe.dart` + warmup + layer-count test (D); `render_glass_surface.dart` + `glass_panel.dart` + `glass_fade.dart` + Tier-2 goldens (E).

**Phase 4 — Flagship (parallel: 4 agents).**
- `glass_tab_bar.dart` layout engine (auto-fit passes, springs, long-press) (A); `glass_tab.dart` + `tab_icon.dart` (selection pill, color blends, lottie contract) (B); `counter_badge.dart` (punch-out) + its dedicated golden (C); example app: `tabs_demo.dart` MainTabsActivity replica, `glass_playground.dart` (every uniform as a live slider — the eyeball-parity harness), `theme_browser.dart` (D).

**Phase 5 — Component wave (parallel: 6 agents, one file each).**
`glass_app_bar.dart`; `tg_scaffold.dart` + `glass_icon_button.dart`; `dialog_cell.dart`; `text_cell.dart` + `header_cell.dart` + `shadow_section_cell.dart`; `user_cell.dart`; `bulletin.dart` + `tg_bottom_sheet.dart`. Each with Tier-2 goldens from the §6 numbers.

**Phase 6 — Strategy 2 + performance ring (parallel: 3 agents).**
`source_host.dart` (`GlassSourceHost`, `SnapshotBlurPipeline`, `GlassSourceLink`, `ScrollReprojector`, image lifecycle/leak tests) (A); perf benchmark scenes + budget assertions + A/B (B); Strategy 1↔2 API integration + platform-view fallback (C).

**Phase 7 — Fidelity acceptance (serial-ish).**
Android instrumentation capture harness (one-time, produces `android_ref/`); `fidelity_diff.py` + region budgets; Ring-3 suite wiring; parity triage and shader/pipeline fixes; ship review incl. licensing decision.

---

## 9. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| 1 | **`ImageFilter.shader` backdrop semantics** (Impeller-only; coordinate space/extent of the backdrop input under-documented; flutter/flutter#170820 showed composed blur+shader breakage) — the inflated-coverage + in-shader-clip design depends on it | Spike Task 0 before any engine code; `snapshotCache` (Strategy 2) is a committed fallback, not descopeable; pin exact stable Flutter version; runtime probe with kill-switch |
| 2 | Non-Impeller backends silently can't run the shader | `GlassRuntimeProbe` try/catch auto-downgrade liquid → frosted; forced-degradation integration test; fidelity ladder is first-class API |
| 3 | **Per-frame backdrop cost** — no cross-frame cache in Strategy 1; Impeller blur on Mali-class GPUs historically lags | BackdropGroup single-snapshot sharing; downscale-before-blur matrix sandwich; frosted-for-full-width-bars policy; hard TimelineSummary budgets in CI; ladder k=8→16, frosted→flat; Strategy 2 for heaviest screens |
| 4 | **AGSL→GLSL port drift**: half vs float precision on the 1-px finite-difference normals; `refract()` grazing angles; premultiply conventions; the (RB, RT, LB, LT) radius packing | Generated uniform slot map; `check_shader_parity.py`; shader-only diff harness vs AGSL renders; Ring-0 uniform fixtures |
| 5 | Blur appearance mismatch (Android 4×/8× pyramid + bilinear upsample vs Impeller's own decimation), esp. the 8× frosted path and screen edges | `emulateDownscale` matrix sandwich; verbatim sigma math (0.57735·r + 0.5); region-budgeted ΔE acceptance rather than exact-pixel |
| 6 | `BackdropFilter.grouped`/`BackdropGroup` is young API; semantics may shift across releases; overlapping glass surfaces don't refract each other | Version pin; layer-count regression test; document the (Android-matching) non-mutual-refraction behavior |
| 7 | Strategy-2 `toImageSync` image lifetime (leaks, context loss on background) and 1-frame position lag | Strict ownership in the pipeline controller; leak tests; post-layout `GlassSourceLink`; Strategy 2 stays opt-in |
| 8 | Codegen brittleness on upstream merges (regex over Theme.java/ThemeColors.java) | Checked-in `theme_tokens.json` intermediate (reviewable diffs); count assertion (777) and ordinal-pinning; strict RHS evaluator that raises on unknowns; brace-depth guard; `--check` CI |
| 9 | No local Flutter SDK — API misuse discovered late | Ring 0 carries all pre-compilable correctness; small PRs; CI as compile authority; conservative API usage outside the shader path |
| 10 | dp rounding: `dp()` = `ceil(density·v)` vs Flutter logical doubles — 0.4dp hairlines land on different pixels at DPR 2.625 | `TgDimens.fidelityRounding` opt-in per surface; goldens at three DPRs |
| 11 | Typography parity (TextView vs Paragraph metrics; extra-bold selected label) | Bundle rmedium/rextrabold/regular Roboto; pinned TextHeightBehavior; font-locked goldens |
| 12 | Counter punch-out (saveLayer + BlendMode.clear inside scaled canvas) has had Impeller edges | Dedicated Ring-3 golden |
| 13 | RLottie frame-control doesn't map 1:1 to pub `lottie` | v1 ships the `TabAnimation` contract + static-icon path; adapter in example; FFI binding deferred |
| 14 | 120Hz pacing not guaranteed on all OEMs | Per-device-profile budget parameterization in `perf_driver.dart` |
| 15 | **Licensing**: Telegram Android is GPLv2; the ported shader and tokens likely carry copyleft | Explicit decision gate before any distribution beyond this repo; package stays in-repo until resolved; note in README |