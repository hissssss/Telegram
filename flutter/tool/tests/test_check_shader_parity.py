"""Tests for check_shader_parity.py (plain asserts, run via run_tests.py)."""

import re
import sys
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
TOOL_DIR = TESTS_DIR.parent
sys.path.insert(0, str(TOOL_DIR))

import check_shader_parity as p  # noqa: E402

REPO_ROOT = TOOL_DIR.parent.parent
AGSL = (REPO_ROOT / "TMessagesProj/src/main/res/raw/liquid_glass_shader.agsl").read_text()
GLSL = (REPO_ROOT / "flutter/telegram_ui/shaders/liquid_glass.frag").read_text()


def test_real_shaders_hold_parity():
    failures = p.run_checks(AGSL, GLSL)
    assert failures == [], failures


def test_cli_green_on_real_files():
    assert p.main([]) == 0


def test_missing_glsl_uniform_fails():
    tampered = GLSL.replace("uniform float u_thickness;", "")
    failures = p.run_checks(AGSL, tampered)
    assert any("u_thickness" in f for f in failures), failures


def test_extra_glsl_uniform_fails():
    tampered = GLSL.replace(
        "uniform float u_thickness;",
        "uniform float u_thickness;\nuniform float u_extra;",
    )
    failures = p.run_checks(AGSL, tampered)
    assert any("u_extra" in f for f in failures), failures


def test_new_agsl_uniform_fails():
    tampered = AGSL.replace(
        "uniform float thickness;",
        "uniform float thickness;\nuniform float new_upstream_knob;",
    )
    failures = p.run_checks(tampered, GLSL)
    assert any("new_upstream_knob" in f for f in failures), failures


def test_type_mismatch_fails():
    tampered = GLSL.replace("uniform float u_thickness;", "uniform vec2 u_thickness;")
    failures = p.run_checks(AGSL, tampered)
    assert any("type mismatch" in f for f in failures), failures


def test_declaration_order_drift_fails():
    # Swap u_center and u_half_size declarations only — body untouched.
    tampered = GLSL.replace(
        "uniform vec2 u_center;", "uniform vec2 SWAP_SENTINEL;"
    ).replace(
        "uniform vec2 u_half_size;", "uniform vec2 u_center;"
    ).replace(
        "uniform vec2 SWAP_SENTINEL;", "uniform vec2 u_half_size;"
    )
    failures = p.run_checks(AGSL, tampered)
    assert any("order differs" in f for f in failures), failures


def test_ray_length_constant_drift_fails():
    tampered = GLSL.replace("8.0 * u_thickness", "7.0 * u_thickness")
    failures = p.run_checks(AGSL, tampered)
    assert any("ray length" in f for f in failures), failures


def test_ncos_formula_drift_fails():
    tampered = GLSL.replace(
        "max(u_thickness + sd, 0.0) / u_thickness",
        "max(u_thickness + sd, 0.0) / (u_thickness * 2.0)",
    )
    failures = p.run_checks(AGSL, tampered)
    assert any("n_cos" in f for f in failures), failures


def test_sdf_select_drift_fails():
    tampered = GLSL.replace(
        "r.xy = (p.x > 0.0) ? r.xy : r.zw;",
        "r.xy = (p.x < 0.0) ? r.xy : r.zw;",
    )
    failures = p.run_checks(AGSL, tampered)
    assert any("sdf select" in f for f in failures), failures


def test_refract_call_drift_fails():
    tampered = GLSL.replace("1.0 / u_refract_index", "u_refract_index")
    failures = p.run_checks(AGSL, tampered)
    assert any("refract call" in f for f in failures), failures


def test_lens_height_drift_fails():
    tampered = GLSL.replace(
        "sqrt(sd * (-2.0 * u_thickness - sd))",
        "sqrt(sd * (-1.0 * u_thickness - sd))",
    )
    failures = p.run_checks(AGSL, tampered)
    assert any("lens height" in f for f in failures), failures


def test_srcover_drift_fails():
    tampered = GLSL.replace(
        "src.rgb + dst.rgb * (1.0 - src.a)",
        "src.rgb + dst.rgb * (1.0 - dst.a)",
    )
    failures = p.run_checks(AGSL, tampered)
    assert any("srcOver" in f for f in failures), failures


def test_agsl_side_drift_also_fails():
    tampered = AGSL.replace(
        "uv += refract_vec.xy * refract_length * refract_intensity;",
        "uv += refract_vec.xy * refract_length;",
    )
    failures = p.run_checks(tampered, GLSL)
    assert any("uv displacement" in f for f in failures), failures


def test_canonicalise_renames_and_strips():
    canon = p.canonicalise(
        "// comment\nuniform half4 foo;\n#version 460\nfloat2 q = a - b;\n",
        {"foo": "bar"},
    )
    assert "comment" not in canon
    assert "#version" not in canon
    assert "vec4bar" in canon
    assert "vec2q=a-b;" in canon


def test_whitespace_only_reformat_passes():
    # Reformatting (indent/newlines) must not trip the body checks.
    reformatted = re.sub(r"[ \t]+", " ", GLSL)
    failures = p.run_checks(AGSL, reformatted)
    assert failures == [], failures
