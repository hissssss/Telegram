#!/usr/bin/env python3
"""gen_tokens.py — Stage 1 of the telegram_ui token codegen pipeline.

Extracts the Telegram Android theme-token tables into a checked-in,
reviewable JSON intermediate (`theme_tokens.json`).  See
flutter/docs/ARCHITECTURE.md §4.3 (codegen pipeline) and §4.4 (.attheme
semantics), and flutter/docs/spec_tokens.md.

Four passes, all stdlib-only:

  Pass 1  Ordered `public static final int key_X = colorsCount++;`
          declarations from ui/ActionBar/Theme.java.  Line order defines the
          dense int ordinal, exactly like the Java `colorsCount++` counter.
  Pass 2  `defaultColors[key_X] = <rhs>;` assignments from
          ui/ActionBar/ThemeColors.java (createDefaultColors), comments
          stripped first, RHS resolved by a strict evaluator that RAISES on
          any unknown shape or any assignment at unexpected brace depth.
          Last write wins (Java array-store semantics).
  Pass 3  `colorKeysMap.put(key_X, "name")` attheme-name mappings from
          ThemeColors.java, `fallbackKeys.put(a, b)` pairs from Theme.java,
          the forced-opaque key set from Theme.getColor, and the bundled
          theme registrations (name -> assetName) from Theme.java.
  Pass 4  The bundled assets/*.attheme files, parsed with Android-exact
          semantics: a faithful re-implementation of
          Theme.getThemeFileValues's 1024-byte chunked scanner (only
          `\n`-terminated lines are consumed, so a final unterminated line
          is silently dropped — replicated on purpose, with a warning),
          `WLS=` wallpaper-link capture, `WPS` stop marker,
          Color.parseColor for `#hex` values, Utilities.parseInt (the
          non-Windows branch, including its quirks) for everything else,
          and unknown names warned + ignored.

Output shape (all colors serialized as `0xAARRGGBB` strings):

  { "meta":      { sources+sha256, counts, constants, forcedOpaqueKeys, ... },
    "keys":      [ 777 bare key names, ordinal order ],
    "defaults":  { bare key name -> color, assignment coverage only },
    "names":     { bare key name -> attheme serialized name },
    "fallbacks": { bare key name -> bare fallback key name },
    "themes":    { android theme name -> { bare key name -> color } } }

Usage:
  python3 gen_tokens.py            # regenerate flutter/tool/theme_tokens.json
  python3 gen_tokens.py --check    # regenerate to memory, byte-compare, exit 1 on drift
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parent.parent

THEME_JAVA = "TMessagesProj/src/main/java/org/telegram/ui/ActionBar/Theme.java"
THEME_COLORS_JAVA = "TMessagesProj/src/main/java/org/telegram/ui/ActionBar/ThemeColors.java"
ASSETS_DIR = "TMessagesProj/src/main/assets"
DEFAULT_OUT = TOOL_DIR / "theme_tokens.json"

KEY_PREFIX = "key_"

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------


class ExtractionError(RuntimeError):
    """Raised when the Java sources no longer match the shapes we rely on."""


def warn(msg: str) -> None:
    print(f"gen_tokens.py: warning: {msg}", file=sys.stderr)


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def strip_block_comments(text: str) -> str:
    """Remove /* ... */ comments, preserving line structure (defensive)."""

    def repl(m: re.Match) -> str:
        return "\n" * m.group(0).count("\n")

    return re.sub(r"/\*.*?\*/", repl, text, flags=re.S)


def strip_line_comment(line: str) -> str:
    return re.sub(r"//.*", "", line)


def hex_color(value: int) -> str:
    return f"0x{value & 0xFFFFFFFF:08X}"


def bare(key: str) -> str:
    if not key.startswith(KEY_PREFIX):
        raise ExtractionError(f"key without '{KEY_PREFIX}' prefix: {key!r}")
    return key[len(KEY_PREFIX):]


# ---------------------------------------------------------------------------
# Pass 1 — ordered key declarations from Theme.java
# ---------------------------------------------------------------------------

KEY_DECL_RE = re.compile(
    r"^\s*public\s+static\s+final\s+int\s+(key_\w+)\s*=\s*colorsCount\+\+\s*;"
)


def parse_keys(theme_java: str) -> list[str]:
    keys: list[str] = []
    for line in theme_java.splitlines():
        m = KEY_DECL_RE.match(line)
        if m:
            keys.append(m.group(1))
    if not keys:
        raise ExtractionError("Pass 1 matched no key declarations in Theme.java")
    if len(keys) != len(set(keys)):
        dupes = sorted({k for k in keys if keys.count(k) > 1})
        raise ExtractionError(f"duplicate key declarations: {dupes}")
    # Every colorsCount++ occurrence must be one of our declarations, so the
    # ordinal counter cannot drift silently.
    total_incr = len(re.findall(r"colorsCount\+\+", theme_java))
    if total_incr != len(keys):
        raise ExtractionError(
            f"colorsCount++ appears {total_incr} times but only {len(keys)} "
            "declarations matched the Pass-1 shape"
        )
    return keys


# ---------------------------------------------------------------------------
# Pass 2 — defaults from ThemeColors.createDefaultColors()
# ---------------------------------------------------------------------------

CONST_DECL_RE = re.compile(
    r"^\s*public\s+static\s+final\s+int\s+(\w+)\s*=\s*(0[xX][0-9a-fA-F]{1,8}|-?\d+)\s*;"
)
ASSIGN_RE = re.compile(r"defaultColors\[\s*(key_\w+)\s*\]\s*=\s*(.+?)\s*;")

ANDROID_COLOR_CONSTS = {
    "Color.WHITE": 0xFFFFFFFF,
    "Color.BLACK": 0xFF000000,
    "Color.TRANSPARENT": 0x00000000,
}


def parse_class_constants(theme_colors_java: str) -> dict[str, int]:
    """The named int constants declared at ThemeColors class level."""
    consts: dict[str, int] = {}
    for line in theme_colors_java.splitlines():
        m = CONST_DECL_RE.match(strip_line_comment(line))
        if m:
            name, literal = m.groups()
            consts[name] = _parse_int_literal(literal)
    return consts


def _parse_int_literal(literal: str) -> int:
    if literal.lower().startswith("0x"):
        return int(literal, 16) & 0xFFFFFFFF
    return int(literal) & 0xFFFFFFFF


def resolve_rhs(rhs: str, consts: dict[str, int]) -> int:
    """Strict evaluator for createDefaultColors right-hand sides.

    Handles exactly the shapes present upstream (hex ints, signed decimals,
    the ThemeColors class constants, android.graphics.Color constants and
    ColorUtils.setAlphaComponent) and raises on anything else so new
    upstream patterns force a human decision instead of a wrong token.
    """
    rhs = rhs.strip()
    if m := re.fullmatch(r"0[xX]([0-9a-fA-F]{1,8})", rhs):
        return int(m.group(1), 16)
    if re.fullmatch(r"-?\d+", rhs):
        return int(rhs) & 0xFFFFFFFF  # Java signed int -> unsigned ARGB
    if rhs in consts:
        return consts[rhs]
    if rhs in ANDROID_COLOR_CONSTS:
        return ANDROID_COLOR_CONSTS[rhs]
    if m := re.fullmatch(r"ColorUtils\.setAlphaComponent\(\s*(.+?)\s*,\s*(\d+)\s*\)", rhs):
        alpha = int(m.group(2))
        if not 0 <= alpha <= 255:
            raise ExtractionError(f"setAlphaComponent alpha out of range: {rhs!r}")
        return (resolve_rhs(m.group(1), consts) & 0x00FFFFFF) | (alpha << 24)
    raise ExtractionError(f"unhandled defaultColors RHS: {rhs!r}")


def extract_method_body(source: str, signature_re: str) -> list[tuple[int, str, int]]:
    """Yield (line_number, line, brace_depth_at_line_start) for a method body.

    Depth is relative: the method's opening line has depth 0 before it and
    the body proper runs at depth 1.  Comments must be stripped by the
    caller beforehand (block comments) / are stripped per line here.
    """
    lines = source.splitlines()
    sig = re.compile(signature_re)
    start = None
    for i, line in enumerate(lines):
        if sig.search(line):
            start = i
            break
    if start is None:
        raise ExtractionError(f"method not found: {signature_re}")
    depth = 0
    out: list[tuple[int, str, int]] = []
    for i in range(start, len(lines)):
        line = strip_line_comment(lines[i])
        out.append((i + 1, line, depth))
        depth += line.count("{") - line.count("}")
        if depth <= 0 and i > start:
            return out
    raise ExtractionError(f"unterminated method body: {signature_re}")


def parse_defaults(
    theme_colors_java: str, keys: list[str], consts: dict[str, int]
) -> tuple[dict[str, int], int]:
    """Returns ({key -> ARGB}, assignment_count). Last write wins."""
    body = extract_method_body(
        theme_colors_java, r"public\s+static\s+int\[\]\s+createDefaultColors\s*\(\s*\)\s*\{"
    )
    key_set = set(keys)
    defaults: dict[str, int] = {}
    count = 0
    for lineno, line, depth in body:
        matches = list(ASSIGN_RE.finditer(line))
        if not matches:
            # Guard against shapes we would silently miss (e.g. copies like
            # `defaultColors[a] = defaultColors[b];` would match ASSIGN_RE,
            # but a bare `defaultColors[` with no `=` would not).
            if "defaultColors[" in line:
                raise ExtractionError(
                    f"ThemeColors.java:{lineno}: unrecognized defaultColors use: {line.strip()!r}"
                )
            continue
        if depth != 1:
            # Method body level is depth 1; anything deeper means upstream
            # introduced conditionals — a human must decide.
            raise ExtractionError(
                f"ThemeColors.java:{lineno}: assignment at brace depth {depth} "
                f"(expected 1 — conditional assignment?): {line.strip()!r}"
            )
        for m in matches:
            key, rhs = m.groups()
            if key not in key_set:
                raise ExtractionError(f"ThemeColors.java:{lineno}: unknown key {key!r}")
            defaults[key] = resolve_rhs(rhs, consts)
            count += 1
    return defaults, count


# ---------------------------------------------------------------------------
# Pass 3 — attheme names, fallbacks, forced-opaque keys, theme registrations
# ---------------------------------------------------------------------------

NAME_RE = re.compile(r'colorKeysMap\.put\(\s*(key_\w+)\s*,\s*"([^"]*)"\s*\)\s*;')
FALLBACK_RE = re.compile(
    r"fallbackKeys\.put\(\s*(?:Theme\.)?(key_\w+)\s*,\s*(?:Theme\.)?(key_\w+)\s*\)\s*;"
)
FORCED_OPAQUE_RE = re.compile(
    r"if\s*\(((?:\s*key_\w+\s*==\s*key\s*(?:\|\|)?)+)\)\s*\{\s*color\s*\|=\s*0xff000000\s*;",
    re.S,
)


def parse_names(theme_colors_java: str, keys: list[str]) -> dict[str, str]:
    key_set = set(keys)
    names: dict[str, str] = {}
    seen_strings: dict[str, str] = {}
    for m in NAME_RE.finditer(theme_colors_java):
        key, string_name = m.groups()
        if key not in key_set:
            raise ExtractionError(f"colorKeysMap.put for unknown key {key!r}")
        if key in names:
            raise ExtractionError(f"duplicate colorKeysMap.put for {key!r}")
        if string_name in seen_strings:
            raise ExtractionError(
                f"attheme name {string_name!r} mapped from both "
                f"{seen_strings[string_name]!r} and {key!r}"
            )
        names[key] = string_name
        seen_strings[string_name] = key
    if not names:
        raise ExtractionError("Pass 3 matched no colorKeysMap.put entries")
    return names


def parse_fallbacks(theme_java: str, keys: list[str]) -> tuple[dict[str, str], int]:
    key_set = set(keys)
    fallbacks: dict[str, str] = {}
    puts = 0
    for m in FALLBACK_RE.finditer(theme_java):
        src, dst = m.groups()
        if src not in key_set or dst not in key_set:
            raise ExtractionError(f"fallbackKeys.put with unknown key: {src!r} -> {dst!r}")
        fallbacks[src] = dst  # SparseIntArray.put: last write wins
        puts += 1
    if not fallbacks:
        raise ExtractionError("Pass 3 matched no fallbackKeys.put entries")
    return fallbacks, puts


def parse_forced_opaque(theme_java: str, keys: list[str]) -> list[str]:
    m = FORCED_OPAQUE_RE.search(theme_java)
    if not m:
        raise ExtractionError("forced-opaque block (`color |= 0xff000000`) not found")
    found = re.findall(r"key_\w+", m.group(1))
    key_set = set(keys)
    for k in found:
        if k not in key_set:
            raise ExtractionError(f"forced-opaque references unknown key {k!r}")
    if not found:
        raise ExtractionError("forced-opaque block matched but captured no keys")
    return found


THEME_NAME_RE = re.compile(r'themeInfo\.name\s*=\s*"([^"]+)"\s*;')
THEME_ASSET_RE = re.compile(r'themeInfo\.assetName\s*=\s*"([^"]+\.attheme)"\s*;')


def parse_theme_registrations(theme_java: str) -> list[tuple[str, str]]:
    """(theme display name, asset file name) pairs, Theme.java static-init order."""
    events: list[tuple[int, str, str]] = []
    for m in THEME_NAME_RE.finditer(theme_java):
        events.append((m.start(), "name", m.group(1)))
    for m in THEME_ASSET_RE.finditer(theme_java):
        events.append((m.start(), "asset", m.group(1)))
    events.sort()
    pairs: list[tuple[str, str]] = []
    pending_name: str | None = None
    for _, kind, value in events:
        if kind == "name":
            pending_name = value
        elif pending_name is not None:
            pairs.append((pending_name, value))
            pending_name = None
    if not pairs:
        raise ExtractionError("no bundled theme registrations found in Theme.java")
    return pairs


# ---------------------------------------------------------------------------
# Pass 4 — .attheme parsing with Android-exact semantics
# ---------------------------------------------------------------------------


def java_integer_parse_int(s: str) -> int:
    """Integer.parseInt: optional sign + decimal digits, 32-bit signed range."""
    if not re.fullmatch(r"[+-]?\d+", s):
        raise ValueError(f"NumberFormatException: {s!r}")
    v = int(s)
    if not -(2**31) <= v <= 2**31 - 1:
        raise ValueError(f"NumberFormatException (overflow): {s!r}")
    return v


def utilities_parse_int(value: str | None) -> int:
    """Faithful port of Utilities.parseInt (the non-Windows branch).

    Scans for the first run of allowed chars ('-' or digits).  Quirk kept
    on purpose: when a disallowed char terminates a started run, Java does
    `end++` before breaking, so the offending char is INCLUDED in the
    parsed substring, Integer.parseInt throws, and the catch returns 0
    (e.g. "500x" -> 0, not 500).  Clean values like "-1" parse exactly.
    """
    if value is None:
        return 0
    val = 0
    start = -1
    end = 0
    n = len(value)
    while end < n:
        ch = value[end]
        allowed = ch == "-" or "0" <= ch <= "9"
        if allowed and start < 0:
            start = end
        elif not allowed and start >= 0:
            end += 1
            break
        end += 1
    if start >= 0:
        try:
            val = java_integer_parse_int(value[start:end])
        except ValueError:
            val = 0
    return val


def java_color_parse_color(s: str) -> int:
    """android.graphics.Color.parseColor for '#'-prefixed strings.

    `#RRGGBB` gets an implicit FF alpha; `#AARRGGBB` is taken as-is; any
    other length (or non-hex payload) raises, which Theme.java catches and
    routes to Utilities.parseInt.  Returns a Java int (signed 32-bit view
    not needed here — we keep the unsigned 32-bit value).
    """
    body = s[1:]
    # Long.parseLong(body, 16): optional sign + hex digits, else throws.
    if not re.fullmatch(r"[+-]?[0-9a-fA-F]+", body) or len(body) > 16:
        raise ValueError(f"unparseable color: {s!r}")
    color = int(body, 16)
    if len(s) == 7:
        color |= 0xFF000000
    elif len(s) != 9:
        raise ValueError(f"unknown color length: {s!r}")
    # (int) cast: Java truncates the long to a signed 32-bit int.
    color &= 0xFFFFFFFF
    return color - 0x100000000 if color >= 0x80000000 else color


def parse_color_value(param: str) -> int:
    """Theme.getThemeFileValues value parsing: '#' -> Color.parseColor with
    Utilities.parseInt as the exception fallback; otherwise Utilities.parseInt.
    Returns the Java signed 32-bit int; unsigned masking happens when the
    overlay is built (build_theme_overlay)."""
    if param.startswith("#"):
        try:
            return java_color_parse_color(param)
        except ValueError:
            return utilities_parse_int(param)
    return utilities_parse_int(param)


class AtthemeParse:
    def __init__(self) -> None:
        self.entries: list[tuple[str, int]] = []  # (attheme name, ARGB) file order
        self.wallpaper_link: str | None = None
        self.wallpaper_file_offset = -1
        self.consumed = 0
        self.finished_by_wps = False

    @property
    def dropped_tail(self) -> bytes | None:
        return None  # filled in by parse_attheme_bytes


def parse_attheme_bytes(data: bytes) -> tuple[AtthemeParse, bytes]:
    """Faithful re-implementation of Theme.getThemeFileValues's scanner.

    Reads in 1024-byte chunks from the current position; only `\n`-terminated
    lines inside a chunk are consumed; after each chunk the stream is
    repositioned to the end of the last consumed line.  Consequences we
    replicate exactly:
      * a final line with no trailing `\n` is silently dropped (true for
        day.attheme and arctic.attheme on Android);
      * a single line of >= 1024 bytes aborts parsing (previousPosition ==
        currentPosition bailout);
      * a `WPS` line stops parsing and everything after it is wallpaper bytes.

    Returns (parse_result, dropped_tail_bytes).
    """
    result = AtthemeParse()
    current_position = 0
    finished = False
    while True:
        chunk = data[current_position:current_position + 1024]
        if not chunk:  # stream.read() == -1
            break
        previous_position = current_position
        start = 0
        for a in range(len(chunk)):
            if chunk[a] == 0x0A:
                length = a - start + 1
                line = chunk[start:start + length - 1].decode("utf-8", errors="replace")
                if line.startswith("WLS="):
                    result.wallpaper_link = line[4:]
                elif line.startswith("WPS"):
                    result.wallpaper_file_offset = current_position + length
                    finished = True
                    break
                else:
                    idx = line.find("=")
                    if idx != -1:
                        name = line[:idx]
                        param = line[idx + 1:]
                        result.entries.append((name, parse_color_value(param)))
                start += length
                current_position += length
        if previous_position == current_position:
            break
        if finished:
            break
    result.consumed = current_position
    result.finished_by_wps = finished
    if finished:
        dropped = b""
    else:
        dropped = data[current_position:]
    return result, dropped


def build_theme_overlay(
    parse: AtthemeParse,
    attheme_name_to_key: dict[str, str],
    asset_label: str,
) -> tuple[dict[str, int], list[str]]:
    """Map parsed (attheme name, value) entries onto bare key names.

    Unknown names are warned and ignored (ThemeColors.stringKeyToInt == -1
    tolerance).  Duplicate names: last write wins (SparseIntArray.put).
    Finally, like Android's `stringMap.put(key_wallpaperFileOffset, offset)`,
    the wallpaperFileOffset slot is overwritten with the computed offset
    (-1 when the file has no WPS marker).
    """
    overlay: dict[str, int] = {}
    unknown: list[str] = []
    for name, value in parse.entries:
        key = attheme_name_to_key.get(name)
        if key is None:
            unknown.append(name)
            warn(f"{asset_label}: unknown attheme key {name!r} ignored")
            continue
        overlay[key] = value & 0xFFFFFFFF
    overlay["wallpaperFileOffset"] = parse.wallpaper_file_offset & 0xFFFFFFFF
    return overlay, unknown


# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------


def build_tokens(repo_root: Path) -> dict:
    theme_java_path = repo_root / THEME_JAVA
    theme_colors_path = repo_root / THEME_COLORS_JAVA
    assets_dir = repo_root / ASSETS_DIR

    theme_java = strip_block_comments(theme_java_path.read_text(encoding="utf-8"))
    theme_colors_java = strip_block_comments(theme_colors_path.read_text(encoding="utf-8"))

    # Pass 1
    keys = parse_keys(theme_java)
    ordinal = {k: i for i, k in enumerate(keys)}

    # Pass 2
    consts = parse_class_constants(theme_colors_java)
    defaults, assignment_count = parse_defaults(theme_colors_java, keys, consts)

    # Pass 3
    names = parse_names(theme_colors_java, keys)
    fallbacks, fallback_puts = parse_fallbacks(theme_java, keys)
    forced_opaque = parse_forced_opaque(theme_java, keys)
    registrations = parse_theme_registrations(theme_java)
    attheme_name_to_key = {v: bare(k) for k, v in names.items()}

    # Pass 4
    themes: dict[str, dict[str, str]] = {}
    theme_meta: dict[str, dict] = {}
    asset_sources: dict[str, dict] = {}
    bundled_assets = sorted(p.name for p in assets_dir.glob("*.attheme"))
    registered_assets = [asset for _, asset in registrations]
    for asset in bundled_assets:
        if asset not in registered_assets:
            warn(f"asset {asset} is bundled but not registered in Theme.java; skipped")
    for theme_name, asset in registrations:
        asset_path = assets_dir / asset
        data = asset_path.read_bytes()
        parse, dropped = parse_attheme_bytes(data)
        overlay, unknown = build_theme_overlay(parse, attheme_name_to_key, asset)
        if dropped:
            warn(
                f"{asset}: final unterminated line dropped for Android parity: "
                f"{dropped.decode('utf-8', errors='replace')!r}"
            )
        themes[theme_name] = {
            k: hex_color(v)
            for k, v in sorted(overlay.items(), key=lambda kv: ordinal[KEY_PREFIX + kv[0]])
        }
        theme_meta[theme_name] = {
            "asset": asset,
            "entries": len(overlay),
            "wallpaperFileOffset": parse.wallpaper_file_offset,
            "wallpaperLink": parse.wallpaper_link,
            "droppedFinalLine": dropped.decode("utf-8", errors="replace") if dropped else None,
            "unknownNames": unknown,
        }
        asset_sources[asset] = {
            "path": f"{ASSETS_DIR}/{asset}",
            "sha256": sha256_file(asset_path),
        }

    bare_keys = [bare(k) for k in keys]
    key_set = set(keys)
    keys_without_default = [bare(k) for k in keys if k not in defaults]
    keys_without_name = [bare(k) for k in keys if k not in names]
    assert set(defaults) <= key_set and set(names) <= key_set

    tokens = {
        "meta": {
            "generator": "flutter/tool/gen_tokens.py",
            "sources": {
                "Theme.java": {"path": THEME_JAVA, "sha256": sha256_file(theme_java_path)},
                "ThemeColors.java": {
                    "path": THEME_COLORS_JAVA,
                    "sha256": sha256_file(theme_colors_path),
                },
                **asset_sources,
            },
            "counts": {
                "keys": len(keys),
                "defaultsAssigned": len(defaults),
                "defaultAssignments": assignment_count,
                "names": len(names),
                "fallbacks": len(fallbacks),
                "fallbackPuts": fallback_puts,
                "themes": len(themes),
            },
            "constants": {k: hex_color(v) for k, v in sorted(consts.items())},
            "forcedOpaqueKeys": [bare(k) for k in forced_opaque],
            "keysWithoutDefault": keys_without_default,
            "keysWithoutName": keys_without_name,
            "themes": theme_meta,
        },
        "keys": bare_keys,
        "defaults": {
            bare(k): hex_color(defaults[k]) for k in keys if k in defaults
        },
        "names": {bare(k): names[k] for k in keys if k in names},
        "fallbacks": {
            bare(k): bare(fallbacks[k]) for k in keys if k in fallbacks
        },
        "themes": themes,
    }
    return tokens


def render_json(tokens: dict) -> str:
    return json.dumps(tokens, indent=2, ensure_ascii=False) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="regenerate and byte-compare against the checked-in "
                             "theme_tokens.json; exit 1 on drift")
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args(argv)

    tokens = build_tokens(args.repo_root)
    rendered = render_json(tokens).encode("utf-8")

    if args.check:
        if not args.out.exists():
            print(f"gen_tokens.py --check: {args.out} does not exist", file=sys.stderr)
            return 1
        current = args.out.read_bytes()
        if current != rendered:
            print(
                f"gen_tokens.py --check: {args.out} is stale "
                f"({len(current)} bytes on disk vs {len(rendered)} regenerated); "
                "re-run python3 flutter/tool/gen_tokens.py",
                file=sys.stderr,
            )
            return 1
        print(f"gen_tokens.py --check: {args.out} is up to date")
        return 0

    args.out.write_bytes(rendered)
    counts = tokens["meta"]["counts"]
    print(
        f"wrote {args.out}: {counts['keys']} keys, "
        f"{counts['defaultsAssigned']} defaults, {counts['names']} names, "
        f"{counts['fallbacks']} fallbacks, {counts['themes']} themes"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
