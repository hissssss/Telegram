"""Tests for extract_metrics.py + extract_spec.yaml (run via run_tests.py)."""

import copy
import sys
import tempfile
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
TOOL_DIR = TESTS_DIR.parent
sys.path.insert(0, str(TOOL_DIR))

import extract_metrics as x  # noqa: E402

REPO_ROOT = TOOL_DIR.parent.parent
SPEC_PATH = TOOL_DIR / "extract_spec.yaml"


def _raises(exc_type, fn, *args, **kwargs):
    try:
        fn(*args, **kwargs)
    except exc_type:
        return True
    except Exception as e:  # noqa: BLE001
        raise AssertionError(
            f"expected {exc_type.__name__}, got {type(e).__name__}: {e}"
        )
    raise AssertionError(f"expected {exc_type.__name__}, nothing raised")


def _spec():
    return x.parse_mini_yaml(SPEC_PATH.read_text())


def _values():
    return {e["name"]: v for e, v in x.extract(_spec(), REPO_ROOT)}


# ---------------------------------------------------------------------------
# Mini YAML parser
# ---------------------------------------------------------------------------

def test_mini_yaml_agrees_with_pyyaml_when_available():
    try:
        import yaml  # noqa: PLC0415
    except ImportError:
        return  # optional cross-check only; the subset parser is authoritative
    assert x.parse_mini_yaml(SPEC_PATH.read_text()) == yaml.safe_load(
        SPEC_PATH.read_text()
    )


def test_mini_yaml_scalars():
    doc = x.parse_mini_yaml(
        "version: 1\n"
        "flag: true\n"
        "off: false\n"
        "name: 'it''s quoted: yes'\n"
        "items:\n"
        "  - name: a\n"
        "    groups: [1, 2, 3]\n"
        "  - name: b\n"
        "    pattern: 'x \\d+'\n"
    )
    assert doc["version"] == 1
    assert doc["flag"] is True
    assert doc["off"] is False
    assert doc["name"] == "it's quoted: yes"
    assert doc["items"][0] == {"name": "a", "groups": [1, 2, 3]}
    assert doc["items"][1]["pattern"] == "x \\d+"


def test_mini_yaml_rejects_orphan_indent():
    _raises(x.SpecError, x.parse_mini_yaml, "  stray: 1\n")


# ---------------------------------------------------------------------------
# Expression evaluator
# ---------------------------------------------------------------------------

def test_eval_java_expr():
    assert x.eval_java_expr("40 - 1.66f") == 40 - 1.66
    assert x.eval_java_expr("2 / 3f") == 2 / 3
    assert x.eval_java_expr("1 / 3f") == 1 / 3
    assert x.eval_java_expr("1") == 1.0
    assert x.eval_java_expr("2.667f") == 2.667


def test_eval_java_expr_rejects_code():
    _raises(x.ExtractionError, x.eval_java_expr, "__import__('os')")
    _raises(x.ExtractionError, x.eval_java_expr, "density * 2")


# ---------------------------------------------------------------------------
# Extraction against the real Android sources — the §3.4 table.
# ---------------------------------------------------------------------------

def test_extracted_values_match_spec_glass():
    v = _values()
    assert v["kGlassThicknessDefaultDp"] == 11
    assert v["kGlassThicknessBoundsDivisor"] == 5
    assert v["kGlassThicknessMinPx"] == 1
    assert v["kGlassRefractIntensityDefault"] == 0.75
    assert v["kGlassRefractIndex"] == 1.5
    assert v["kGlassTintAlphaLiquid"] == 0.85
    assert v["kGlassTintAlphaFrosted"] == 0.76
    assert v["kGlassDarkBrightnessThreshold"] == 0.721
    assert v["kGlassStrokeTopColorDark"] == 0x28FFFFFF
    assert v["kGlassStrokeBottomColorDark"] == 0x14FFFFFF
    assert v["kGlassShadowColorDark"] == 0x00000000
    assert v["kGlassStrokeTopColorLight"] == 0xFFFFFFFF
    assert v["kGlassStrokeBottomColorLight"] == 0xFFFFFFFF
    assert v["kGlassShadowColorLight"] == 0x20000000
    assert v["kGlassStrokeWidthTopDp"] == 1.0
    assert v["kGlassStrokeWidthBottomDp"] == 2 / 3
    assert v["kGlassShadowRadiusDp"] == 1.0
    assert v["kGlassShadowDxDp"] == 0
    assert v["kGlassShadowDyDp"] == 1 / 3
    assert v["kGlassBackdropDownscale"] == 4
    assert v["kGlassBackdropBlurRadiusDp"] == 6.0
    assert v["kFrostedBackdropDownscale"] == 8
    assert v["kFrostedBackdropBlurRadiusDp"] == 40 - 1.66  # 38.34
    assert v["kGlassBackdropSaturation"] == 3.0
    assert v["kFadeDefaultHeightDp"] == 40
    assert v["kFadeMainTabsHeightDp"] == 60
    assert v["kFadeStopAlphasOpacity"] == [0x00, 0x60, 0xB0, 0xE8]
    assert v["kFadeStopAlphaDivisorOpacity"] == 285
    assert v["kFadeStopAlphasDefault"] == [0x00, 0x60, 0xB0, 0xE8, 0xFF]
    assert v["kFadeStopAlphaDivisorDefault"] == 255
    assert v["kMainTabsTintAlphaLiquid"] == 0.85
    assert v["kMainTabsTintAlphaFrosted"] == 0.76
    assert v["kMainTabsStrokeTopColorLight"] == 0x11000000
    assert v["kMainTabsStrokeTopColorDark"] == 0x06FFFFFF
    assert v["kMainTabsStrokeBottomColorLight"] == 0x20000000
    assert v["kMainTabsStrokeBottomColorDark"] == 0x11FFFFFF
    assert v["kMainTabsShadowColorLight"] == 0x20000000
    assert v["kMainTabsShadowColorDark"] == 0x04FFFFFF
    assert v["kMainTabsShadowRadiusDp"] == 2.667
    assert v["kMainTabsShadowDxDp"] == 0.0
    assert v["kMainTabsShadowDyDp"] == 0.85
    assert v["kMainTabsStrokeWidthTopDp"] == 0.4
    assert v["kMainTabsStrokeWidthBottomDp"] == 0.4
    assert len(v) == 43


# ---------------------------------------------------------------------------
# Drift / failure modes
# ---------------------------------------------------------------------------

def test_pattern_that_stops_matching_fails_loudly():
    spec = _spec()
    spec["constants"][0]["pattern"] = "THIS_WILL_NEVER_MATCH_(\\d+)"
    _raises(x.ExtractionError, x.extract, spec, REPO_ROOT)


def test_unexpected_match_count_fails_loudly():
    spec = _spec()
    # The themed stroke pattern matches twice; demanding one must fail.
    entry = next(
        e for e in spec["constants"] if e["name"] == "kGlassStrokeTopColorDark"
    )
    entry["matches"] = 1
    _raises(x.ExtractionError, x.extract, spec, REPO_ROOT)


def test_equal_group_divergence_fails():
    spec = _spec()
    entry = next(
        e for e in spec["constants"] if e["name"] == "kGlassBackdropDownscale"
    )
    # setScale(4, 4): groups 1 and 2 are equal; comparing group 1 with a
    # group that captures something else must fail.
    entry["pattern"] = (
        r"renderNodesForGlass\.setScale\((\d+), (\d+)\);\s*"
        r"renderNodesForGlass\.setPrimaryEffectBlur\(dpf2\(([0-9.]+)f?\)"
    )
    entry["equal"] = [1, 3]
    _raises(x.ExtractionError, x.extract, spec, REPO_ROOT)


def test_unknown_entry_key_fails():
    spec = _spec()
    spec["constants"][0]["regex"] = "typo-key"
    _raises(x.SpecError, x.extract, spec, REPO_ROOT)


def test_duplicate_name_fails():
    spec = _spec()
    spec["constants"].append(copy.deepcopy(spec["constants"][0]))
    _raises(x.SpecError, x.extract, spec, REPO_ROOT)


def test_missing_source_file_fails():
    spec = _spec()
    spec["constants"][0]["file"] = "TMessagesProj/does/not/exist.java"
    _raises(x.ExtractionError, x.extract, spec, REPO_ROOT)


def test_bad_constant_name_fails():
    spec = _spec()
    spec["constants"][0]["name"] = "GlassThing"
    _raises(x.SpecError, x.extract, spec, REPO_ROOT)


# ---------------------------------------------------------------------------
# Dart emission + check mode
# ---------------------------------------------------------------------------

def test_dart_formatting():
    assert x.format_double(11.0) == "11.0"
    assert x.format_double(2 / 3) == "0.6666666666666666"
    assert x.format_double(40 - 1.66) == "38.34"
    assert x.format_double(0.721) == "0.721"


def test_rendered_dart_declarations():
    spec_text = SPEC_PATH.read_text()
    rendered = x.render_dart(x.extract(_spec(), REPO_ROOT), spec_text)
    assert "const double kGlassThicknessDefaultDp = 11.0;" in rendered
    assert "const double kGlassRefractIntensityDefault = 0.75;" in rendered
    assert "const double kFrostedBackdropBlurRadiusDp = 38.34;" in rendered
    assert (
        "const double kGlassStrokeWidthBottomDp = 0.6666666666666666;"
        in rendered
    )
    assert "const int kGlassStrokeTopColorDark = 0x28FFFFFF;" in rendered
    assert (
        "const List<int> kFadeStopAlphasOpacity = <int>[0x00, 0x60, 0xB0, 0xE8];"
        in rendered
    )
    assert "const int kFadeStopAlphaDivisorOpacity = 285;" in rendered
    assert rendered.startswith("// GENERATED CODE - DO NOT MODIFY BY HAND.")


def test_check_mode_is_green_on_committed_file():
    assert x.main(["--check"]) == 0


def test_check_mode_detects_drift():
    spec_text = SPEC_PATH.read_text()
    rendered = x.render_dart(x.extract(_spec(), REPO_ROOT), spec_text)
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "glass_metrics.g.dart"
        out.write_text(rendered.replace("= 11.0;", "= 12.0;", 1))
        assert x.main(["--check", "--out", str(out)]) == 1
        out.write_text(rendered)
        assert x.main(["--check", "--out", str(out)]) == 0
        assert x.main(["--check", "--out", str(Path(td) / "missing.dart")]) == 1
