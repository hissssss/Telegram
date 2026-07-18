"""Tests for gen_shader_bindings.py (plain asserts, run via run_tests.py)."""

import sys
import tempfile
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
TOOL_DIR = TESTS_DIR.parent
sys.path.insert(0, str(TOOL_DIR))

import gen_shader_bindings as g  # noqa: E402

REPO_ROOT = TOOL_DIR.parent.parent
FRAG = REPO_ROOT / "flutter/telegram_ui/shaders/liquid_glass.frag"
OUT = REPO_ROOT / "flutter/telegram_ui/lib/src/tokens/liquid_glass_uniforms.g.dart"

# The layout the rest of the port is built against (also asserted by
# test/shader_smoke_test.dart on the compiled shader).
EXPECTED_SLOTS = {
    "kUniformSizeX": 0,
    "kUniformSizeY": 1,
    "kUniformCenterX": 2,
    "kUniformCenterY": 3,
    "kUniformHalfSizeX": 4,
    "kUniformHalfSizeY": 5,
    "kUniformRadiusRightBottom": 6,
    "kUniformRadiusRightTop": 7,
    "kUniformRadiusLeftBottom": 8,
    "kUniformRadiusLeftTop": 9,
    "kUniformThickness": 10,
    "kUniformRefractIndex": 11,
    "kUniformRefractIntensity": 12,
    "kUniformForegroundColorR": 13,
    "kUniformForegroundColorG": 14,
    "kUniformForegroundColorB": 15,
    "kUniformForegroundColorA": 16,
}

SYNTHETIC_FRAG = """
uniform vec2 u_size;
uniform vec4 u_radius;
uniform vec2 u_center;
uniform vec2 u_half_size;
uniform float u_thickness;
uniform float u_refract_index;
uniform float u_refract_intensity;
uniform vec4 u_foreground_color;
uniform sampler2D u_backdrop;
"""


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


def test_real_frag_slot_layout():
    decls = g.parse_uniforms(FRAG.read_text())
    components, float_count, samplers = g.build_slots(decls)
    slots = {c["const"]: c["slot"] for c in components}
    assert slots == EXPECTED_SLOTS, slots
    assert float_count == 17
    assert len(samplers) == 1
    assert samplers[0]["const"] == "kUniformBackdropSampler"
    assert samplers[0]["index"] == 0


def test_declaration_order_defines_slots():
    # Moving u_radius to the front shifts everything that follows: the slot
    # map is purely declaration-order driven.
    decls = g.parse_uniforms(SYNTHETIC_FRAG)
    components, float_count, _ = g.build_slots(decls)
    slots = {c["const"]: c["slot"] for c in components}
    assert float_count == 17
    assert slots["kUniformRadiusRightBottom"] == 2
    assert slots["kUniformCenterX"] == 6
    assert slots["kUniformForegroundColorA"] == 16


def test_radius_component_names_follow_java_packing():
    # (RB, RT, LB, LT) — LiquidGlassEffect.java:93.
    decls = g.parse_uniforms(FRAG.read_text())
    components, _, _ = g.build_slots(decls)
    radius = [c["const"] for c in components if c["uniform"] == "u_radius"]
    assert radius == [
        "kUniformRadiusRightBottom",
        "kUniformRadiusRightTop",
        "kUniformRadiusLeftBottom",
        "kUniformRadiusLeftTop",
    ]


def test_unknown_uniform_type_fails():
    _raises(
        g.ShaderParseError,
        lambda: g.build_slots(
            g.parse_uniforms(SYNTHETIC_FRAG + "uniform mat4 u_matrix;\n")
        ),
    )


def test_stale_component_override_fails():
    # Overrides reference u_radius/u_foreground_color; a shader without them
    # means the table is stale and must fail loudly.
    _raises(
        g.ShaderParseError,
        lambda: g.build_slots(g.parse_uniforms("uniform vec2 u_size;")),
    )


def test_no_uniforms_fails():
    _raises(g.ShaderParseError, g.parse_uniforms, "void main() {}")


def test_rendered_dart_contains_bounds_const():
    rendered = g.render_dart(g.parse_uniforms(FRAG.read_text()))
    assert "const int kLiquidGlassUniformFloatCount = 17;" in rendered
    assert "const int kUniformCenterX = 2;" in rendered
    assert rendered.startswith("// GENERATED CODE - DO NOT MODIFY BY HAND.")


def test_generation_is_deterministic():
    decls = g.parse_uniforms(FRAG.read_text())
    assert g.render_dart(decls) == g.render_dart(decls)


def test_check_mode_is_green_on_committed_file():
    assert g.main(["--check"]) == 0


def test_check_mode_detects_drift():
    rendered = g.render_dart(g.parse_uniforms(FRAG.read_text()))
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "liquid_glass_uniforms.g.dart"
        out.write_text(rendered.replace("= 2;", "= 3;", 1))
        assert g.main(["--check", "--out", str(out)]) == 1
        out.write_text(rendered)
        assert g.main(["--check", "--out", str(out)]) == 0
        assert g.main(["--check", "--out", str(Path(td) / "missing.dart")]) == 1


def test_layout_sha_ignores_body_edits():
    decls_a = g.parse_uniforms(FRAG.read_text())
    decls_b = g.parse_uniforms(FRAG.read_text() + "\n// body-only comment\n")
    assert g.layout_sha(decls_a) == g.layout_sha(decls_b)
