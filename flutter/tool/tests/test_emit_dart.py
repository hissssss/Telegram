"""Unit + golden tests for emit_dart.py (plain asserts, run via run_tests.py)."""

import json
import shutil
import sys
import tempfile
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
TOOL_DIR = TESTS_DIR.parent
sys.path.insert(0, str(TOOL_DIR))

import emit_dart as e  # noqa: E402


def _raises(exc_type, fn, *args, **kwargs):
    try:
        fn(*args, **kwargs)
    except exc_type:
        return True
    except Exception as ex:  # noqa: BLE001
        raise AssertionError(f"expected {exc_type.__name__}, got {type(ex).__name__}: {ex}")
    raise AssertionError(f"expected {exc_type.__name__}, nothing raised")


# ---------------------------------------------------------------------------
# Naming helpers
# ---------------------------------------------------------------------------

def test_camelize():
    assert e.camelize("wallpaper_gradient_to1") == "wallpaperGradientTo1"
    assert e.camelize("White") == "white"
    assert e.camelize("inBubble") == "inBubble"
    assert e.camelize("telegram_color") == "telegramColor"
    assert e.camelize("fill_RedNormal") == "fillRedNormal"
    assert e.camelize("") == ""


def test_theme_ident():
    assert e.theme_ident("Blue") == ("theme_blue", "kBlueTheme")
    assert e.theme_ident("Dark Blue") == ("theme_dark_blue", "kDarkBlueTheme")
    assert e.theme_ident("Arctic Blue") == ("theme_arctic_blue", "kArcticBlueTheme")


def test_is_identifier():
    assert e.is_identifier("inBubble")
    assert e.is_identifier("switch2Track")
    assert not e.is_identifier("default")   # reserved word
    assert not e.is_identifier("switch")    # reserved word
    assert not e.is_identifier("2Track")    # leading digit
    assert not e.is_identifier("")
    assert not e.is_identifier("resolve")   # API member of the scheme classes


def test_assign_groups_longest_prefix_and_fallbacks():
    groups = {
        "chats": {"class": "DialogsColors", "prefixes": ["chats_"], "doc": "d"},
        "chat": {"class": "ChatColors", "prefixes": ["chat_"], "doc": "d"},
        "actionBar": {"class": "ActionBarColors", "prefixes": ["actionBar"], "doc": "d"},
        "switches": {"class": "SwitchColors", "prefixes": ["switch"], "doc": "d"},
    }
    keys = [
        "chats_name",          # chats_ wins over chat_ (longest prefix)
        "chat_inBubble",
        "actionBarDefault",    # remainder 'default' is reserved -> full name
        "switch2Track",        # remainder starts with a digit -> full name
        "switchTrack",
        "divider",             # no prefix -> ungrouped
    ]
    assigned, ungrouped = e.assign_groups(keys, groups)
    assert assigned["chats"] == [("name", "chats_name")]
    assert assigned["chat"] == [("inBubble", "chat_inBubble")]
    assert assigned["actionBar"] == [("actionBarDefault", "actionBarDefault")]
    assert assigned["switches"] == [
        ("switch2Track", "switch2Track"),
        ("track", "switchTrack"),
    ]
    assert ungrouped == ["divider"]


def test_assign_groups_rejects_member_collision():
    groups = {"g": {"class": "G", "prefixes": ["a_", "b_"], "doc": "d"}}
    _raises(e.EmitError, e.assign_groups, ["a_x", "b_x"], groups)


def test_wrap_arrow_forms():
    # Form 1: fits on one line.
    assert e._wrap_arrow("Color get x", "_resolve", "K.y") == [
        "  Color get x => _resolve(K.y);"
    ]
    # Form 2: break after `=>` with +4 continuation indent.
    member = "outSentCheckReadSelected"
    arg = "TelegramColorKey.chat_outSentCheckReadSelected"
    lines = e._wrap_arrow(f"Color get {member}xxxxxxxxxxxxxxxx", "_resolve", arg)
    assert lines[0].endswith("=>")
    assert lines[1].startswith("      _resolve(")
    # Form 3: block argument list when even form 2 overflows.
    arg = "TelegramColorKey.voipgroup_windowBackgroundWhiteInputFieldActivated"
    lines = e._wrap_arrow(
        "Color get windowBackgroundWhiteInputFieldActivated", "_resolve", arg
    )
    assert lines == [
        "  Color get windowBackgroundWhiteInputFieldActivated => _resolve(",
        f"    {arg},",
        "  );",
    ]
    # All produced lines respect the dartfmt page width.
    for form in (lines,):
        assert all(len(line) <= e.LINE_WIDTH for line in form)


# ---------------------------------------------------------------------------
# Golden / determinism / --check
# ---------------------------------------------------------------------------

def test_build_files_is_deterministic():
    a = e.build_files(e.DEFAULT_TOKENS, e.DEFAULT_GROUPS)
    b = e.build_files(e.DEFAULT_TOKENS, e.DEFAULT_GROUPS)
    assert a == b
    assert set(a) == {
        "theme_keys.g.dart",
        "theme_key_names.g.dart",
        "theme_fallbacks.g.dart",
        "color_scheme.g.dart",
        "palettes/default_colors.g.dart",
        "palettes/palettes.g.dart",
        "palettes/theme_blue.g.dart",
        "palettes/theme_dark_blue.g.dart",
        "palettes/theme_arctic_blue.g.dart",
        "palettes/theme_day.g.dart",
        "palettes/theme_night.g.dart",
    }


def test_generated_files_match_committed():
    files = e.build_files(e.DEFAULT_TOKENS, e.DEFAULT_GROUPS)
    for rel, content in files.items():
        on_disk = (e.DEFAULT_OUT_DIR / rel).read_bytes()
        assert on_disk == content.encode("utf-8"), f"{rel} drifted — rerun emit_dart.py"


def test_generated_files_respect_page_width_except_comments():
    # dartfmt never wraps comment-only overflow it did not create; every
    # non-comment line we emit must fit the 80-column page width.
    files = e.build_files(e.DEFAULT_TOKENS, e.DEFAULT_GROUPS)
    for rel, content in files.items():
        for i, line in enumerate(content.splitlines(), 1):
            if line.lstrip().startswith(("//", "///")):
                continue
            if "//" in line:  # trailing comments are exempt (dartfmt keeps them)
                continue
            assert len(line) <= e.LINE_WIDTH, f"{rel}:{i} too long: {line!r}"


def test_check_mode_green_and_drift():
    assert e.main(["--check"]) == 0
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "tokens"
        shutil.copytree(e.DEFAULT_OUT_DIR, out)
        # Introduce drift in one generated file.
        target = out / "theme_keys.g.dart"
        target.write_text(target.read_text().replace("= 776;", "= 999;"))
        assert e.main(["--check", "--out-dir", str(out)]) == 1
        # A missing file is drift too.
        target.unlink()
        assert e.main(["--check", "--out-dir", str(out)]) == 1
        # A stale palette overlay (e.g. renamed upstream theme) is drift.
        shutil.copytree(e.DEFAULT_OUT_DIR, out, dirs_exist_ok=True)
        assert e.main(["--check", "--out-dir", str(out)]) == 0
        (out / "palettes" / "theme_zombie.g.dart").write_text("// stale\n")
        assert e.main(["--check", "--out-dir", str(out)]) == 1


def test_header_stamps_input_hashes():
    files = e.build_files(e.DEFAULT_TOKENS, e.DEFAULT_GROUPS)
    tokens_sha = e.sha256_file(e.DEFAULT_TOKENS)
    groups_sha = e.sha256_file(e.DEFAULT_GROUPS)
    for rel, content in files.items():
        assert tokens_sha in content, f"{rel} missing theme_tokens.json sha"
    assert groups_sha in files["color_scheme.g.dart"]
    # groups.toml only affects color_scheme.g.dart; other files must not
    # churn when only the grouping changes.
    assert groups_sha not in files["theme_keys.g.dart"]


def test_scheme_covers_every_key_exactly_once():
    tokens = json.loads(e.DEFAULT_TOKENS.read_text())
    groups, _ = e.load_groups(e.DEFAULT_GROUPS)
    assigned, ungrouped = e.assign_groups(tokens["keys"], groups)
    total = sum(len(v) for v in assigned.values()) + len(ungrouped)
    assert total == len(tokens["keys"]) == 777
