"""Unit + snapshot tests for gen_tokens.py (plain asserts, run via run_tests.py)."""

import json
import sys
import tempfile
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
TOOL_DIR = TESTS_DIR.parent
sys.path.insert(0, str(TOOL_DIR))

import gen_tokens as g  # noqa: E402

FIXTURES = TESTS_DIR / "fixtures"
MINI_REPO = FIXTURES / "mini_repo"
REAL_REPO = TOOL_DIR.parent.parent


def _raises(exc_type, fn, *args, **kwargs):
    try:
        fn(*args, **kwargs)
    except exc_type:
        return True
    except Exception as e:  # noqa: BLE001
        raise AssertionError(f"expected {exc_type.__name__}, got {type(e).__name__}: {e}")
    raise AssertionError(f"expected {exc_type.__name__}, nothing raised")


# ---------------------------------------------------------------------------
# Pass 1
# ---------------------------------------------------------------------------

def test_parse_keys_order_and_count():
    src = (
        "public static int colorsCount;\n"
        "public static final int key_a = colorsCount++;\n"
        "// comment line\n"
        "    public static final int key_b = colorsCount++;\n"
        "public static final int key_c_x = colorsCount++;\n"
    )
    assert g.parse_keys(src) == ["key_a", "key_b", "key_c_x"]


def test_parse_keys_rejects_duplicates():
    src = (
        "public static final int key_a = colorsCount++;\n"
        "public static final int key_a = colorsCount++;\n"
    )
    _raises(g.ExtractionError, g.parse_keys, src)


def test_parse_keys_rejects_unmatched_increment():
    # A colorsCount++ outside the declaration shape must fail the count guard.
    src = (
        "public static final int key_a = colorsCount++;\n"
        "int sneaky = colorsCount++;\n"
    )
    _raises(g.ExtractionError, g.parse_keys, src)


def test_parse_keys_rejects_empty():
    _raises(g.ExtractionError, g.parse_keys, "public class Theme {}\n")


# ---------------------------------------------------------------------------
# Pass 2 — RHS resolver
# ---------------------------------------------------------------------------

CONSTS = {"TELEGRAM_COLOR": 0xFF229AF0, "DEFAULT_BLACK_TEXT": 0xFF1A1D21}


def test_resolve_rhs_hex():
    assert g.resolve_rhs("0xffffffff", CONSTS) == 0xFFFFFFFF
    assert g.resolve_rhs("0x121A1D21", CONSTS) == 0x121A1D21
    assert g.resolve_rhs("0X10FFFFFF", CONSTS) == 0x10FFFFFF


def test_resolve_rhs_signed_decimal_masks():
    assert g.resolve_rhs("-15436801", CONSTS) == (-15436801) & 0xFFFFFFFF
    assert g.resolve_rhs("-1", CONSTS) == 0xFFFFFFFF
    assert g.resolve_rhs("0", CONSTS) == 0


def test_resolve_rhs_constants():
    assert g.resolve_rhs("TELEGRAM_COLOR", CONSTS) == 0xFF229AF0
    assert g.resolve_rhs("Color.WHITE", CONSTS) == 0xFFFFFFFF
    assert g.resolve_rhs("Color.BLACK", CONSTS) == 0xFF000000
    assert g.resolve_rhs("Color.TRANSPARENT", CONSTS) == 0x00000000


def test_resolve_rhs_set_alpha_component():
    assert g.resolve_rhs("ColorUtils.setAlphaComponent(Color.WHITE, 90)", CONSTS) == 0x5AFFFFFF
    assert (
        g.resolve_rhs("ColorUtils.setAlphaComponent(TELEGRAM_COLOR, 0)", CONSTS) == 0x00229AF0
    )


def test_resolve_rhs_raises_on_unknown():
    _raises(g.ExtractionError, g.resolve_rhs, "Build.VERSION.SDK_INT", CONSTS)
    _raises(g.ExtractionError, g.resolve_rhs, "getColor(key_a)", CONSTS)
    _raises(g.ExtractionError, g.resolve_rhs, "0xffffffff | mask", CONSTS)
    _raises(g.ExtractionError, g.resolve_rhs, "ColorUtils.setAlphaComponent(Color.WHITE, 300)", CONSTS)


# ---------------------------------------------------------------------------
# Pass 2 — method scanning
# ---------------------------------------------------------------------------

DEFAULTS_TEMPLATE = """
public class ThemeColors {{
    public static final int TELEGRAM_COLOR = 0xFF229AF0;
    public static int[] createDefaultColors() {{
        int[] defaultColors = new int[Theme.colorsCount];
{body}
        return defaultColors;
    }}
}}
"""


def test_parse_defaults_last_write_wins_and_comments():
    body = (
        "        defaultColors[key_a] = 0xff000001; // trailing comment\n"
        "        defaultColors[key_b] = TELEGRAM_COLOR;\n"
        "        defaultColors[key_a] = -1;\n"
    )
    src = DEFAULTS_TEMPLATE.format(body=body)
    defaults, count = g.parse_defaults(src, ["key_a", "key_b"], {"TELEGRAM_COLOR": 0xFF229AF0})
    assert count == 3
    assert defaults == {"key_a": 0xFFFFFFFF, "key_b": 0xFF229AF0}


def test_parse_defaults_raises_at_nested_depth():
    body = (
        "        if (something) {\n"
        "            defaultColors[key_a] = 0xff000001;\n"
        "        }\n"
    )
    src = DEFAULTS_TEMPLATE.format(body=body)
    _raises(g.ExtractionError, g.parse_defaults, src, ["key_a"], {})


def test_parse_defaults_raises_on_unknown_key():
    body = "        defaultColors[key_zzz] = 0xff000001;\n"
    src = DEFAULTS_TEMPLATE.format(body=body)
    _raises(g.ExtractionError, g.parse_defaults, src, ["key_a"], {})


def test_parse_defaults_raises_on_weird_use():
    body = "        defaultColors[key_a]++;\n"
    src = DEFAULTS_TEMPLATE.format(body=body)
    _raises(g.ExtractionError, g.parse_defaults, src, ["key_a"], {})


# ---------------------------------------------------------------------------
# Pass 3
# ---------------------------------------------------------------------------

def test_parse_names_and_mismatch():
    src = (
        'colorKeysMap.put(key_listSelector, "listSelectorSDK21");\n'
        'colorKeysMap.put(key_graySectionText, "key_graySectionText");\n'
    )
    names = g.parse_names(src, ["key_listSelector", "key_graySectionText"])
    assert names == {
        "key_listSelector": "listSelectorSDK21",
        "key_graySectionText": "key_graySectionText",
    }


def test_parse_names_rejects_duplicate_key():
    src = (
        'colorKeysMap.put(key_a, "a");\n'
        'colorKeysMap.put(key_a, "b");\n'
    )
    _raises(g.ExtractionError, g.parse_names, src, ["key_a"])


def test_parse_names_rejects_duplicate_string():
    src = (
        'colorKeysMap.put(key_a, "same");\n'
        'colorKeysMap.put(key_b, "same");\n'
    )
    _raises(g.ExtractionError, g.parse_names, src, ["key_a", "key_b"])


def test_parse_fallbacks_theme_prefix_and_overwrite():
    src = (
        "fallbackKeys.put(key_a, key_b);\n"
        "fallbackKeys.put(key_c, Theme.key_a);\n"
        "fallbackKeys.put(key_a, key_c);\n"
    )
    fallbacks, puts = g.parse_fallbacks(src, ["key_a", "key_b", "key_c"])
    assert puts == 3
    assert fallbacks == {"key_a": "key_c", "key_c": "key_a"}


def test_parse_forced_opaque():
    src = (
        "int color = x;\n"
        "if (key_windowBackgroundWhite == key || key_windowBackgroundGray == key "
        "|| key_actionBarDefault == key || key_actionBarDefaultArchived == key) {\n"
        "    color |= 0xff000000;\n"
        "}\n"
    )
    keys = [
        "key_windowBackgroundWhite", "key_windowBackgroundGray",
        "key_actionBarDefault", "key_actionBarDefaultArchived",
    ]
    assert g.parse_forced_opaque(src, keys) == keys


def test_parse_theme_registrations():
    src = (
        'themeInfo.name = "Blue";\n'
        'themeInfo.assetName = "bluebubbles.attheme";\n'
        'themeInfo.name = "NoAsset";\n'
        'themeInfo.name = "Dark Blue";\n'
        'themeInfo.assetName = "darkblue.attheme";\n'
    )
    assert g.parse_theme_registrations(src) == [
        ("Blue", "bluebubbles.attheme"),
        ("Dark Blue", "darkblue.attheme"),
    ]


# ---------------------------------------------------------------------------
# Pass 4 — value parsing (Android-exact)
# ---------------------------------------------------------------------------

def test_utilities_parse_int_clean_values():
    assert g.utilities_parse_int("-1") == -1
    assert g.utilities_parse_int("285212671") == 285212671
    assert g.utilities_parse_int("-15198183") == -15198183
    assert g.utilities_parse_int("0") == 0


def test_utilities_parse_int_quirks():
    # The Java loop includes the terminating bad char (end++ before break),
    # so Integer.parseInt throws and the result is 0 — replicated exactly.
    assert g.utilities_parse_int("500x") == 0
    assert g.utilities_parse_int("-15honk") == 0
    assert g.utilities_parse_int("12-3") == 0  # '-' allowed mid-run -> "12-3" -> throw -> 0
    assert g.utilities_parse_int("abc") == 0
    assert g.utilities_parse_int("") == 0
    assert g.utilities_parse_int(None) == 0
    assert g.utilities_parse_int("#123") == 123  # leading '#' skipped, clean digit run
    assert g.utilities_parse_int("x-5") == -5
    assert g.utilities_parse_int("99999999999") == 0  # int overflow -> catch -> 0


def test_java_color_parse_color():
    # Returns the Java signed int, exactly like (int) Color.parseColor(...).
    assert g.java_color_parse_color("#1A1D21") == -15065823        # 0xFF1A1D21
    assert g.java_color_parse_color("#80112233") == 0x80112233 - 0x100000000
    assert g.java_color_parse_color("#ffffff") == -1               # 0xFFFFFFFF
    assert g.java_color_parse_color("#10FFFFFF") == 0x10FFFFFF     # positive stays
    _raises(ValueError, g.java_color_parse_color, "#123")       # bad length
    _raises(ValueError, g.java_color_parse_color, "#xyzxyz")    # bad hex


def test_parse_color_value_hash_fallback():
    # '#123' fails Color.parseColor, falls back to Utilities.parseInt -> 123.
    assert g.parse_color_value("#123") == 123
    assert g.parse_color_value("#1A1D21") == -15065823
    assert g.parse_color_value("-1") == -1
    assert g.parse_color_value("garbage") == 0


# ---------------------------------------------------------------------------
# Pass 4 — streaming scanner
# ---------------------------------------------------------------------------

def test_attheme_basic_and_final_line_dropped():
    data = b"a=-1\nb=2\nfinal=-3"
    parse, dropped = g.parse_attheme_bytes(data)
    assert parse.entries == [("a", -1), ("b", 2)]
    assert dropped == b"final=-3"
    assert parse.wallpaper_file_offset == -1
    assert parse.wallpaper_link is None


def test_attheme_trailing_newline_keeps_final_line():
    parse, dropped = g.parse_attheme_bytes(b"a=-1\nfinal=-3\n")
    assert parse.entries == [("a", -1), ("final", -3)]
    assert dropped == b""


def test_attheme_wls_and_wps():
    data = (
        b"a=-1\n"
        b"WLS=https://t.me/bg/slug\n"
        b"b=7\n"
        b"WPS\n"
        b"\x89binary\nnot=parsed\n"
    )
    parse, dropped = g.parse_attheme_bytes(data)
    assert parse.entries == [("a", -1), ("b", 7)]
    assert parse.wallpaper_link == "https://t.me/bg/slug"
    # offset = total bytes of the four consumed lines (incl. their '\n')
    assert parse.wallpaper_file_offset == data.index(b"WPS\n") + 4
    assert parse.finished_by_wps
    assert dropped == b""


def test_attheme_line_without_equals_ignored():
    parse, _ = g.parse_attheme_bytes(b"noequals\nx=1\n")
    assert parse.entries == [("x", 1)]


def test_attheme_long_line_aborts_parsing():
    # A >=1024-byte line never yields a '\n' inside the 1KB chunk, so the
    # previousPosition == currentPosition bailout stops parsing entirely.
    data = b"a=-1\n" + b"b=" + b"9" * 2000 + b"\nc=3\n"
    parse, dropped = g.parse_attheme_bytes(data)
    assert parse.entries == [("a", -1)]
    assert dropped == data[5:]


def test_attheme_chunk_boundary_line():
    # A line straddling the 1024-byte chunk boundary must be re-read intact.
    filler = b"k=1\n" * 250  # 1000 bytes
    data = filler + b"straddler=-14054705\nz=5\n"
    parse, _ = g.parse_attheme_bytes(data)
    assert ("straddler", -14054705) in parse.entries
    assert ("z", 5) in parse.entries
    assert len(parse.entries) == 252


def test_build_theme_overlay_unknown_and_duplicates():
    parse = g.AtthemeParse()
    parse.entries = [("known", 1), ("mystery", 2), ("known", -1)]
    parse.wallpaper_file_offset = -1
    overlay, unknown = g.build_theme_overlay(parse, {"known": "known"}, "test")
    assert overlay == {"known": 0xFFFFFFFF, "wallpaperFileOffset": 0xFFFFFFFF}
    assert unknown == ["mystery"]


# ---------------------------------------------------------------------------
# Snapshot: mini fixture repo end-to-end
# ---------------------------------------------------------------------------

def test_mini_repo_snapshot():
    tokens = g.build_tokens(MINI_REPO)
    expected = json.loads((FIXTURES / "mini_expected.json").read_text())
    # Byte-level comparison of everything except volatile absolute paths
    # (there are none: paths are repo-relative) — full deep equality.
    assert tokens == expected, "mini_repo extraction drifted from mini_expected.json"


def test_mini_repo_semantics():
    tokens = g.build_tokens(MINI_REPO)
    assert tokens["keys"][0] == "wallpaperFileOffset"
    assert tokens["keys"][1] == "dialogBackground"
    assert len(tokens["keys"]) == 14
    # last-write-wins duplicate assignment
    assert tokens["defaults"]["graySectionText"] == "0xFF9A9C9E"
    # ColorUtils.setAlphaComponent(Color.WHITE, 90)
    assert tokens["defaults"]["premiumStartSmallStarsColor"] == "0x5AFFFFFF"
    # fallback overwrite: chat_serviceBackground re-put to dialogBackground
    assert tokens["fallbacks"]["chat_serviceBackground"] == "dialogBackground"
    assert tokens["fallbacks"]["glass_tabSelected"] == "telegram_color"
    assert tokens["meta"]["keysWithoutDefault"] == ["chat_serviceBackground"]
    assert tokens["meta"]["keysWithoutName"] == ["premiumStartSmallStarsColor"]
    assert tokens["meta"]["forcedOpaqueKeys"] == [
        "windowBackgroundWhite", "windowBackgroundGray",
        "actionBarDefault", "actionBarDefaultArchived",
    ]
    blue = tokens["themes"]["Mini Blue"]
    assert blue["windowBackgroundWhite"] == "0xFF181819"      # -15198183
    assert blue["dialogBackground"] == "0xFF1A1D21"           # #1A1D21 gets FF alpha
    assert blue["listSelector"] == "0x80112233"               # #AARRGGBB kept
    assert blue["graySectionText"] == "0xFFFFFFFF"            # via typo name
    assert blue["chat_inBubble"] == "0xFF298ACF"              # dup: last write wins
    assert blue["telegram_color"] == "0x10FFFFFF"             # low-alpha positive
    assert "unknownKeyName" not in blue
    assert blue["wallpaperFileOffset"] == "0xFFFFFFFF"        # -1: no WPS marker
    night = tokens["themes"]["Mini Night"]
    assert "telegram_color" not in night                      # dropped final line
    assert night["actionBarDefault"] == "0x0000007B"          # '#123' fallback -> 123
    assert night["glass_tabSelected"] == "0x00000000"         # '-15honk' -> 0
    assert tokens["meta"]["themes"]["Mini Night"]["droppedFinalLine"] == (
        "telegram_color=-14509328"
    )
    wall = tokens["themes"]["Mini Wall"]
    assert wall["wallpaperFileOffset"] == "0x00000055"        # offset 85
    assert tokens["meta"]["themes"]["Mini Wall"]["wallpaperFileOffset"] == 85
    assert tokens["meta"]["themes"]["Mini Wall"]["wallpaperLink"] == (
        "https://example.com/wall"
    )
    assert "evil" not in wall                                 # nothing after WPS


# ---------------------------------------------------------------------------
# Snapshot: the real repo (counts + spot checks + --check gate)
# ---------------------------------------------------------------------------

def test_real_repo_counts_and_spot_values():
    tokens = json.loads((TOOL_DIR / "theme_tokens.json").read_text())
    counts = tokens["meta"]["counts"]
    assert counts["keys"] == 777, "ARCHITECTURE.md says 777 — source drifted?"
    assert counts["defaultsAssigned"] == 760
    assert counts["names"] == 773
    assert counts["fallbacks"] == 183
    assert counts["themes"] == 5
    assert len(tokens["keys"]) == 777
    # First ordinals (Theme.java:3365+)
    assert tokens["keys"][:3] == ["wallpaperFileOffset", "dialogBackground", "dialogBackgroundGray"]
    # spec_tokens.md §3 spot values
    assert tokens["defaults"]["windowBackgroundWhite"] == "0xFFFFFFFF"
    assert tokens["defaults"]["windowBackgroundGray"] == "0xFFF1F1F3"
    assert tokens["defaults"]["telegram_color"] == "0xFF229AF0"
    assert tokens["defaults"]["glass_tabSelected"] == "0xFF1A91E6"
    assert tokens["defaults"]["chat_outBubble"] == "0xFFEFFFDE"
    # The 4 known name mismatches (spec_tokens.md §1c)
    assert tokens["names"]["listSelector"] == "listSelectorSDK21"
    assert tokens["names"]["graySectionText"] == "key_graySectionText"
    assert tokens["names"]["chat_inGreenCall"] == "chat_inDownCall"
    assert tokens["names"]["chat_outGreenCall"] == "chat_outUpCall"
    assert tokens["names"]["actionBarDefaultArchivedSearchPlaceholder"] == (
        "actionBarDefaultSearchArchivedPlaceholder"
    )
    # Fallbacks + forced-opaque
    assert tokens["fallbacks"]["graySectionText"] == "windowBackgroundWhiteGrayText2"
    assert tokens["meta"]["forcedOpaqueKeys"] == [
        "windowBackgroundWhite", "windowBackgroundGray",
        "actionBarDefault", "actionBarDefaultArchived",
    ]
    # Bundled themes: registration names + dropped-final-line parity
    assert set(tokens["themes"]) == {"Blue", "Dark Blue", "Arctic Blue", "Day", "Night"}
    assert tokens["meta"]["themes"]["Day"]["droppedFinalLine"] == (
        "chat_editMediaButton=-15033089"
    )
    assert tokens["meta"]["themes"]["Arctic Blue"]["droppedFinalLine"] == (
        "chat_editMediaButton=-15033089"
    )
    assert tokens["meta"]["themes"]["Dark Blue"]["droppedFinalLine"] is None
    assert "chat_editMediaButton" not in tokens["themes"]["Day"]
    assert "chat_editMediaButton" not in tokens["themes"]["Arctic Blue"]
    # night.attheme:235 windowBackgroundWhite=-15198183
    assert tokens["themes"]["Night"]["windowBackgroundWhite"] == "0xFF181819"
    # bluebubbles ends with a newline: its final entry must be present
    assert tokens["themes"]["Blue"]["dialogTopBackground"] == "0xFF326A98"


def test_real_repo_check_mode_is_green():
    assert g.main(["--check"]) == 0


def test_check_mode_detects_drift():
    tokens = g.build_tokens(REAL_REPO)
    rendered = g.render_json(tokens)
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "theme_tokens.json"
        out.write_text(rendered.replace("0xFF229AF0", "0xFF229AF1", 1))
        assert g.main(["--check", "--out", str(out)]) == 1
        out.write_text(rendered)
        assert g.main(["--check", "--out", str(out)]) == 0
        missing = Path(td) / "nope.json"
        assert g.main(["--check", "--out", str(missing)]) == 1
