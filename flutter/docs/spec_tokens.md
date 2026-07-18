# Telegram Android Theme Tokens — Spec Extraction Report

Source files (all paths absolute):
- `/home/user/Telegram/TMessagesProj/src/main/java/org/telegram/ui/ActionBar/ThemeColors.java` (1652 lines)
- `/home/user/Telegram/TMessagesProj/src/main/java/org/telegram/ui/ActionBar/Theme.java` (key declarations, fallbacks, .attheme loader)
- `/home/user/Telegram/TMessagesProj/src/main/assets/*.attheme` (bundled themes)

**Correction to prior context:** the color-key count is **777**, not ~1533. `Theme.java` declares 777 `key_*` constants; `ThemeColors.java` has 760 `defaultColors[...]` assignments and 773 `colorKeysMap.put` string-name entries. The gaps matter (see edge cases).

---

## 1. How keys are declared and defaults assigned

### 1a. Key declaration (Theme.java, starting line 3364)

Keys are **not enums or strings** — they are dense `int` indices minted by a mutable static counter, so *declaration order defines the index*:

```java
public static int colorsCount;
public static final int key_wallpaperFileOffset = colorsCount++;   // index 0
public static final int key_dialogBackground = colorsCount++;      // index 1
public static final int key_dialogBackgroundGray = colorsCount++;  // index 2
...
```
777 such lines. `Theme.colorsCount` ends at 777 and sizes every color array.

### 1b. Default assignment (ThemeColors.java)

`ThemeColors` defines three named constants (lines 14–16):

```java
public static final int TELEGRAM_COLOR = 0xFF229AF0;        // -14509328
public static final int TELEGRAM_COLOR_TEXT = 0xFF298ACF;   // -14054705
public static final int DEFAULT_BLACK_TEXT = 0xFF1A1D21;   // -15065823
```

`public static int[] createDefaultColors()` (lines 20–839) allocates `new int[Theme.colorsCount]` (zero-initialized, i.e. missing keys default to `0x00000000`) and fills it with one flat assignment per line. **There are no conditionals, loops, or branches in this method** — verified by grep; the only non-hex-literal right-hand sides are the three class constants, `Color.WHITE`, one `ColorUtils` call, and two negative decimal literals. Five verbatim example lines showing every pattern that occurs:

```java
defaultColors[key_dialogBackground] = 0xffffffff;                                        // line 24: hex literal
defaultColors[key_dialogTextBlack] = DEFAULT_BLACK_TEXT;                                 // line 26: class constant
defaultColors[key_premiumGradientBackgroundOverlay] = Color.WHITE;                       // line 781: android.graphics.Color constant
defaultColors[key_premiumCoinGradient1] = -15436801;                                     // line 784: signed decimal literal
defaultColors[key_premiumStartSmallStarsColor] = ColorUtils.setAlphaComponent(Color.WHITE, 90); // line 786: function call
```

Some lines carry trailing `//` comments, e.g. line 193: `defaultColors[key_actionBarActionModeDefaultIcon] = DEFAULT_BLACK_TEXT; // key_windowBackgroundWhiteBlackText` and line 211: `defaultColors[key_chats_tabUnreadActiveBackground] = 0xFF66ade1; //TELEGRAM_COLOR_TEXT;`.

### 1c. String-name map (ThemeColors.java lines 841–1620)

`createColorKeysMap()` maps int key → the **serialized string name used in .attheme files**:

```java
colorKeysMap.put(key_dialogBackground, "dialogBackground");
```

Critically, **the string name is not always the Java identifier minus `key_`**. Real mismatches in this file:
- `key_listSelector` → `"listSelectorSDK21"` (line 897)
- `key_graySectionText` → `"key_graySectionText"` (line 946 — upstream typo, the `key_` prefix is part of the on-disk name)
- `key_chat_inGreenCall` → `"chat_inDownCall"`, `key_chat_outGreenCall` → `"chat_outUpCall"` (lines 1113–1114)
- `key_actionBarDefaultArchivedSearchPlaceholder` → `"actionBarDefaultSearchArchivedPlaceholder"` (line 1036)

`stringKeyToInt(String)` (line 1633) inverts this map and is what the .attheme parser uses. Any codegen **must** use this map, never a string-munging heuristic.

### 1d. Fallback keys (Theme.java line 4281+)

`private static SparseIntArray fallbackKeys` gets 183 entries in a static block:

```java
fallbackKeys.put(key_chat_inQuote, key_featuredStickers_addButtonPressed);
fallbackKeys.put(key_graySectionText, key_windowBackgroundWhiteGrayText2);
```

Runtime resolution order in `Theme.getColor(int)` (line 9552→9560): `animatingColors` (theme-transition) → `currentColors` (loaded theme + accent) → `fallbackKeys` lookup into `currentColors` → `getDefaultColor(key)` = `defaultColors[key]`. Special cases: `key_chat_serviceBackground`/`Selected` are computed from the wallpaper at runtime (no default entry at all), and `key_windowBackgroundWhite`, `key_windowBackgroundGray`, `key_actionBarDefault`, `key_actionBarDefaultArchived` are forced opaque (`color |= 0xff000000`, line ~9614).

---

## 2. Python codegen strategy (Java → Dart token file)

Single script, stdlib-only (`re`), reading both Java files. Four extraction passes, then emission.

### Pass 1 — ordered key list from Theme.java
```python
KEY_DECL = re.compile(r'^\s*public\s+static\s+final\s+int\s+(key_\w+)\s*=\s*colorsCount\+\+\s*;')
```
Scan line-by-line; ordinal = order of match (this reproduces the `colorsCount++` numbering exactly). Result: `keys: list[str]` of length 777, `index_of: dict[str,int]`.

### Pass 2 — defaults from ThemeColors.java
Strip comments first (`re.sub(r'//.*', '', line)` per line; also strip `/* */` defensively), then:
```python
ASSIGN = re.compile(r'defaultColors\[\s*(key_\w+)\s*\]\s*=\s*(.+?)\s*;')
```
Resolve the RHS with a small evaluator (fail loudly on anything unknown so new upstream patterns can't silently produce wrong tokens):
```python
CONSTS = {
    'TELEGRAM_COLOR': 0xFF229AF0,
    'TELEGRAM_COLOR_TEXT': 0xFF298ACF,
    'DEFAULT_BLACK_TEXT': 0xFF1A1D21,   # parse these three from lines 14-16 rather than hardcoding
    'Color.WHITE': 0xFFFFFFFF, 'Color.BLACK': 0xFF000000,
    'Color.TRANSPARENT': 0x00000000,
}
def resolve(rhs):
    rhs = rhs.strip()
    if m := re.fullmatch(r'0[xX]([0-9a-fA-F]{1,8})', rhs): return int(m.group(1), 16)
    if re.fullmatch(r'-?\d+', rhs): return int(rhs) & 0xFFFFFFFF        # Java signed int -> ARGB
    if rhs in CONSTS: return CONSTS[rhs]
    if m := re.fullmatch(r'ColorUtils\.setAlphaComponent\(\s*(.+?)\s*,\s*(\d+)\s*\)', rhs):
        return (resolve(m.group(1)) & 0x00FFFFFF) | (int(m.group(2)) << 24)
    raise ValueError(f'unhandled RHS: {rhs!r}')
```

### Pass 3 — string-name map and fallbacks
```python
NAME  = re.compile(r'colorKeysMap\.put\(\s*(key_\w+)\s*,\s*"([^"]*)"\s*\)')
FALLB = re.compile(r'fallbackKeys\.put\(\s*(key_\w+)\s*,\s*(key_\w+)\s*\)')   # run over Theme.java
```

### Pass 4 — .attheme overlays (dark theme)
Parse `darkblue.attheme` / `night.attheme` with the same semantics as `Theme.getThemeFileValues` (see §4): split on `\n`, first `=` splits key/value, value is signed decimal (`int(v) & 0xFFFFFFFF`) or `#hex` (`int(v[1:],16)`, add `FF` alpha when 6 digits — Android `Color.parseColor` semantics), skip `WLS=` lines, stop at a line starting with `WPS`, ignore names not present in the Pass-3 map.

### Edge cases the script must handle
1. **Keys with no default** (777 declared vs 760 assigned, e.g. `key_chat_serviceBackground`, `key_fill_RedDark`): emit `0x00000000` to match Java's zero-init array, but tag them — `chat_serviceBackground*` are runtime-computed from wallpaper and `fill_RedDark` resolves via `fallbackKeys`.
2. **Fallback chains**: bake resolution into the generated Dart getter (`color(key) => overrides[key] ?? themeFile[key] ?? themeFile[fallback[key]] ?? defaults[key]`) rather than flattening at codegen time, so per-surface overrides (ResourcesProvider equivalent) keep fallback behavior.
3. **Conditional assignments**: none exist today in `createDefaultColors()`, but historical upstream versions had `if (Build.VERSION...)` blocks. Track `{`/`}` brace depth inside the method and **raise** if an `ASSIGN` match occurs at depth > method level — forces a human decision instead of a silently wrong token.
4. **Duplicate assignments**: last-write-wins (dict overwrite) matches Java semantics.
5. **Name mismatches** (§1c): the attheme-name map is authoritative; verify every Pass-4 attheme key resolves, warn on unknowns.
6. **Signedness**: attheme values like `-1` are Java signed ints → mask with `& 0xFFFFFFFF` → `0xFFFFFFFF`.
7. **Forced-opaque keys**: replicate `|= 0xff000000` for the four keys listed in §1d in generated Dart.
8. **Missing trailing newline**: `day.attheme` and `arctic.attheme` do not end with `\n`; the Java parser only consumes `\n`-terminated lines, so their final entry (`chat_editMediaButton=-15033089` in day.attheme) is *silently dropped on Android*. Decide explicitly (recommend: replicate Android behavior for pixel parity, log a warning).

### Dart emission
Generate `flutter/lib/src/theme/telegram_colors.g.dart`: (a) `abstract final class TelegramColorKey { static const int dialogBackground = 1; ... }` preserving indices; (b) `const List<int> kDefaultColors = [...]` length 777; (c) `const Map<int,int> kFallbackKeys`; (d) `const Map<String,int> kAttThemeNames`; (e) per-bundled-theme override maps (`kDarkBlueTheme`, `kNightTheme`, ...) generated from the assets; (f) a typed convenience facade (`TelegramThemeData.chatInBubble` etc.) for the ~40 v1 keys below. All `int` ARGB, wrapped in `Color()` at the facade layer only.

---

## 3. Forty most important keys for the v1 port (light-theme defaults, from ThemeColors.java)

`TELEGRAM_COLOR = 0xFF229AF0`, `TELEGRAM_COLOR_TEXT = 0xFF298ACF`, `DEFAULT_BLACK_TEXT = 0xFF1A1D21` (constants resolved below).

| # | Key (`key_` prefix omitted) | Group | Default ARGB | Source line |
|---|---|---|---|---|
| 1 | windowBackgroundWhite | Window | `0xFFFFFFFF` | 79 |
| 2 | windowBackgroundGray | Window | `0xFFF1F1F3` | 133 |
| 3 | windowBackgroundWhiteBlackText | Text | `0xFF1A1D21` | 107 |
| 4 | windowBackgroundWhiteGrayText | Text | `0xFF808384` | 99 |
| 5 | windowBackgroundWhiteHintText | Text | `0xFFA8A8A8` | 108 |
| 6 | windowBackgroundWhiteLinkText | Text | `0xFF298ACF` | 110 |
| 7 | divider | Window | `0xFFD9D9D9` | 136 |
| 8 | graySection | Window | `0xFFF5F5F5` | 137 |
| 9 | actionBarDefault | Action bar | `0xFFFFFFFF` | 189 |
| 10 | actionBarDefaultIcon | Action bar | `0xFF1A1D21` | 190 |
| 11 | actionBarDefaultTitle | Action bar | `0xFF1A1D21` | 194 |
| 12 | actionBarDefaultSubtitle | Action bar | `0xFF79817E` | 195 |
| 13 | actionBarDefaultSelector | Action bar | `0x121A1D21` | 196 |
| 14 | actionBarDefaultSubmenuBackground | Action bar | `0xFFFFFFFF` | 202 |
| 15 | actionBarTabActiveText | Action bar | `0xFF298ACF` | 208 |
| 16 | actionBarTabUnactiveText | Action bar | `0xFF777C7F` | 209 |
| 17 | actionBarTabLine | Action bar | `0xFF298ACF` | 210 |
| 18 | chats_name | Dialogs list | `0xFF1A1D21` | 234 |
| 19 | chats_message | Dialogs list | `0xFF75787A` | 239 |
| 20 | chats_nameMessage | Dialogs list | `0xFF298ACF` | 243 |
| 21 | chats_date | Dialogs list | `0xFF848688` | 249 |
| 22 | chats_unreadCounter | Dialogs list | `0xFF229AF0` | 227 |
| 23 | chats_unreadCounterMuted | Dialogs list | `0xFFBEC3C7` | 228 |
| 24 | chats_unreadCounterText | Dialogs list | `0xFFFFFFFF` | 229 |
| 25 | chats_sentReadCheck | Dialogs list | `0xFF46AA36` | 254 |
| 26 | chats_onlineCircle | Dialogs list | `0xFF4BCB1C` | 226 |
| 27 | chat_inBubble | Chat bubbles | `0xFFFFFFFF` | 304 |
| 28 | chat_inBubbleSelected | Chat bubbles | `0xFFECF7FD` | 305 |
| 29 | chat_outBubble | Chat bubbles | `0xFFEFFFDE` | 307 |
| 30 | chat_outBubbleSelected | Chat bubbles | `0xFFD9F7C5` | 309 |
| 31 | chat_messageTextIn | Chat bubbles | `0xFF000000` | 315 |
| 32 | chat_messageTextOut | Chat bubbles | `0xFF000000` | 316 |
| 33 | chat_messageLinkIn | Chat bubbles | `0xFF2678B6` | 317 |
| 34 | chat_inTimeText | Chat bubbles | `0xFFA1AAB3` | 398 |
| 35 | chat_outTimeText | Chat bubbles | `0xFF70B15C` | 400 |
| 36 | chat_messagePanelBackground | Chat input | `0xFFFFFFFF` | 486 |
| 37 | chat_messagePanelHint | Chat input | `0xFF858A84` | 488 |
| 38 | dialogBackground | Alert dialogs | `0xFFFFFFFF` | 24 |
| 39 | dialogTextBlack | Alert dialogs | `0xFF1A1D21` | 26 |
| 40 | telegram_color | Accent | `0xFF229AF0` | 835 |

Adjacent accent keys the v1 facade should also carry: `dialogButton` = `0xFF298ACF` (l.50), `featuredStickers_addButton` = `0xFF229AF0` (l.596), `switchTrackChecked` = `0xFF229AF0` (l.116), `checkbox` = `0xFF5EC245` (l.620), and the glass-tab keys `glass_tabSelected` = `0xFF1A91E6`, `glass_tabSelectedText` = `0xFF0D7FCF`, `glass_tabUnselected` = `0xFF1A1D21`, `glass_defaultIcon`/`glass_defaultText` = `0x991B2227` (lines 822–828).

---

## 4. Where dark-theme values come from

### 4a. Bundled theme assets (`/home/user/Telegram/TMessagesProj/src/main/assets/`)

Five `.attheme` files:

| File | Size / lines | Registered as (Theme.java static init) |
|---|---|---|
| `bluebubbles.attheme` | 5,876 B / 185 | `"Blue"` — **default day theme** (`currentDayTheme = defaultTheme`), line 4612 |
| `day.attheme` | 9,663 B / 305 | `"Day"`, line 4686 |
| `darkblue.attheme` | 15,195 B / 477 | `"Dark Blue"` — **default night theme** (`currentNightTheme`), line 4638 |
| `night.attheme` | 15,882 B / 498 | `"Night"`, line 4710 |
| `arctic.attheme` | 8,922 B / 279 | `"Arctic Blue"`, line 4662 |

Each gets a `ThemeInfo` with `assetName`, preview colors, `sortIndex`, and large `setAccentColorOptions(...)` tables (16–18 accent variants per theme with pattern-wallpaper slugs and gradient colors).

### 4b. .attheme file format

Plain text (no sections, no quoting), one `name=value` per line. First lines of `night.attheme`:

```
actionBarDefaultTitle=-1
actionBarDefaultIcon=-1
profile_title=-1
actionBarDefaultArchived=-14474458
```

- **name** = the string from `createColorKeysMap()` (e.g. `windowBackgroundWhite`, `listSelectorSDK21`).
- **value** = ARGB color as **signed 32-bit decimal** (Java int): `-1` = `0xFFFFFFFF`, `-14474458` = `0xFF232E3C`, `-15198183` = `0xFF181F27` (night's `windowBackgroundWhite`). Positive values encode colors with alpha < 0x80 (e.g. `285212671` = `0x10FFFFFF`). The parser also accepts `#RRGGBB`/`#AARRGGBB` via `Color.parseColor`, but no bundled asset uses it.
- Optional `WLS=<url>` line = wallpaper link; optional `WPS` marker line, after which **raw wallpaper image bytes** are appended (the byte offset is stored under `key_wallpaperFileOffset`). None of the five bundled assets contain `WLS`/`WPS`.
- Themes are **sparse overlays**: only keys that differ are listed (185–498 lines vs 777 keys); everything else resolves through `fallbackKeys` then `defaultColors`.
- Gotcha: `day.attheme` and `arctic.attheme` lack a trailing newline, and the Java parser only consumes `\n`-terminated lines, so each file's final entry is dropped on Android (see §2 edge case 8).

### 4c. How Theme.java loads them

`Theme.getThemeFileValues(File file, String assetName, String[] wallpaperLink)` (line 8135):
1. If `assetName != null`, `getAssetFile(assetName)` (line 7791) copies the APK asset to the app files dir (re-copying if the asset size changed) and returns that `File`.
2. Streams the file in 1 KB chunks, splitting on `\n`. For each line: `WLS=` → wallpaper link out-param; line starting `WPS` → record `wallpaperFileOffset` and stop; otherwise split at first `=`, parse value (`#` → `Color.parseColor`, else `Utilities.parseInt`, which extracts the first `-?[0-9]+` run — line 157 of `/home/user/Telegram/TMessagesProj/src/main/java/org/telegram/messenger/Utilities.java`), map name → int key via `ThemeColors.stringKeyToInt`, ignore unknown names, and store into a `SparseIntArray`.
3. Callers (`applyTheme`/`applyDayNightThemeMaybe`, e.g. lines 6357–6370) put the result in `currentColorsNoAccent`, read `key_wallpaperFileOffset`, then apply the selected accent via `ThemeAccent.fillAccentColors` (line ~1404) — a hue/saturation shift (`changeColorAccent`) applied to every non-excluded key, honoring `fallbackKeys` so a fallback-provided color isn't double-shifted — producing `currentColors`.
4. `Theme.getColor(key)` then resolves: `animatingColors` → `currentColors` → `fallbackKeys` → `defaultColors`, with the wallpaper-derived `chat_serviceBackground` special case and the 4 forced-opaque keys.

**Flutter takeaway:** generate the dark token set by running the Python attheme parser over `darkblue.attheme` (default night theme; optionally also `night.attheme` as an alternative dark scheme) layered over the generated defaults with fallback resolution — this exactly reproduces Android's un-accented dark palette; accent hue-shifting can be a later, optional feature.