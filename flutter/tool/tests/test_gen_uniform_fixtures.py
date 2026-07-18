"""Tests for gen_uniform_fixtures.py (plain asserts, run via run_tests.py).

Covers the LiquidGlassEffect.update model (radius-pair rescale, 0.1f epsilon
dirty-check, premultiply), the RenderNode thickness clamp, fixture-file
freshness, and float32-stability of every epsilon verdict in the emitted
tables (the Java implementation compares float32; the tables are float64).
"""

import json
import sys
import tempfile
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
TOOL_DIR = TESTS_DIR.parent
sys.path.insert(0, str(TOOL_DIR))

import gen_uniform_fixtures as g  # noqa: E402

REPO_ROOT = TOOL_DIR.parent.parent
FIXTURES_JSON = TOOL_DIR / "fixtures/uniform_fixtures.json"


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


def _approx(a, b, tol=1e-12):
    assert abs(a - b) <= tol, f"{a} != {b} (tol {tol})"


# ---------------------------------------------------------------------------
# Thickness clamp (BlurredBackgroundDrawableRenderNode.java:115-118)
# ---------------------------------------------------------------------------

def test_clamp_default_dp11_per_density():
    assert g.clamp_thickness(0, 344, 57, 1.0) == 11
    assert g.clamp_thickness(0, 903, 150, 2.625) == 29  # ceil(28.875)
    assert g.clamp_thickness(0, 1032, 171, 3.0) == 33


def test_clamp_bounds_divisor_uses_int_division():
    # 40 / 5 = 8 beats dp(11)=11.
    assert g.clamp_thickness(0, 344, 40, 1.0) == 8
    # 59 / 5 = 11 in Java int division, not 11.8.
    assert g.clamp_thickness(0, 344, 59, 3.0) == 11


def test_clamp_floor_is_one():
    assert g.clamp_thickness(0, 4, 4, 1.0) == 1
    assert g.clamp_thickness(0, 0, 0, 1.0) == 1


def test_clamp_explicit_thickness():
    assert g.clamp_thickness(50, 100, 100, 1.0) == 20  # clamped to 100/5
    assert g.clamp_thickness(5, 344, 57, 1.0) == 5
    assert g.clamp_thickness(-5, 344, 57, 1.0) == 11  # <= 0 -> default


# ---------------------------------------------------------------------------
# Vertical radius-pair rescale (LiquidGlassEffect.java:56-65)
# ---------------------------------------------------------------------------

def test_rescale_left_pair_only():
    lt, rt, rb, lb = g.rescale_vertical_radius_pairs(40, 10, 10, 40, 56)
    _approx(lt, 28.0)
    _approx(lb, 28.0)
    assert (rt, rb) == (10, 10)


def test_rescale_proportional():
    # right pair 42+28=70 on h=56: a=0.6 -> 33.6 / 22.4.
    lt, rt, rb, lb = g.rescale_vertical_radius_pairs(8, 42, 28, 8, 56)
    assert (lt, lb) == (8, 8)
    _approx(rt, 56 * (42 / 70))
    _approx(rb, 56 * (1.0 - 42 / 70))
    _approx(rt + rb, 56.0)


def test_rescale_strict_greater_than():
    # sum == height exactly: untouched.
    assert g.rescale_vertical_radius_pairs(28, 28, 28, 28, 56) == (28, 28, 28, 28)


def test_rescale_zero_partner():
    lt, rt, rb, lb = g.rescale_vertical_radius_pairs(80, 12, 12, 0, 56)
    _approx(lt, 56.0)
    _approx(lb, 0.0)


def test_no_horizontal_clamp():
    # Horizontal sums exceed the width, vertical sums fit the height: no-op.
    assert g.rescale_vertical_radius_pairs(100, 100, 100, 100, 400) == (
        100, 100, 100, 100,
    )


# ---------------------------------------------------------------------------
# Premultiply (LiquidGlassEffect.java:85-88)
# ---------------------------------------------------------------------------

def test_premultiply_alpha_zero():
    assert g.premultiply(0x00FF8040) == (0.0, 0.0, 0.0, 0.0)


def test_premultiply_alpha_128():
    r, gr, b, a = g.premultiply(0x80FF8040)
    _approx(a, 128 / 255)
    _approx(r, 1.0 * a)
    _approx(gr, (128 / 255) * a)
    _approx(b, (64 / 255) * a)


def test_premultiply_opaque_identity():
    r, gr, b, a = g.premultiply(0xFF112233)
    assert a == 1.0
    _approx(r, 0x11 / 255)
    _approx(gr, 0x22 / 255)
    _approx(b, 0x33 / 255)


# ---------------------------------------------------------------------------
# Epsilon dirty-check semantics (LiquidGlassEffect.java:67-82)
# ---------------------------------------------------------------------------

def _update(model, l, t, r, b, radii=(28, 28, 28, 28), thickness=11.0,
            intensity=0.75, index=1.5, color=0xD9FFFFFF):
    return model.update(
        l, t, r, b, radii[0], radii[1], radii[2], radii[3],
        thickness, intensity, index, color, float(r - l), float(b - t),
    )


def test_first_update_pushes_then_identical_does_not():
    m = g.LiquidGlassEffectModel()
    assert _update(m, 0, 0, 344, 56) is True
    assert _update(m, 0, 0, 344, 56) is False


def test_sub_epsilon_move_does_not_push_and_keeps_old_values():
    m = g.LiquidGlassEffectModel()
    _update(m, 0, 0, 344, 56)
    before = dict(m.uniform_values())
    assert _update(m, 0.0625, 0, 344.0625, 56) is False
    assert m.uniform_values() == before  # state advances only on push


def test_super_epsilon_move_pushes():
    m = g.LiquidGlassEffectModel()
    _update(m, 0, 0, 344, 56)
    assert _update(m, 0.125, 0, 344.125, 56) is True
    _approx(m.center_x, 172.125)


def test_sub_epsilon_drift_accumulates_against_last_push():
    m = g.LiquidGlassEffectModel()
    _update(m, 0, 0, 344, 56)
    assert _update(m, 0.0625, 0, 344.0625, 56) is False
    # 0.125 from the last *pushed* center, though only 0.0625 from the last call.
    assert _update(m, 0.125, 0, 344.125, 56) is True


def test_push_carries_sub_epsilon_components():
    m = g.LiquidGlassEffectModel()
    _update(m, 0, 0, 344, 56)
    # Thickness jump forces the push; the tiny center move rides along.
    assert _update(m, 0.0625, 0, 344.0625, 56, thickness=5.0) is True
    _approx(m.center_x, 172.0625)
    _approx(m.thickness, 5.0)


def test_comparison_happens_after_rescale():
    m = g.LiquidGlassEffectModel()
    # 40/40 and 45/45 both rescale to 28/28 on h=56: second call is a no-op.
    assert _update(m, 0, 0, 344, 56, radii=(40, 10, 10, 40)) is True
    assert _update(m, 0, 0, 344, 56, radii=(45, 10, 10, 45)) is False


def test_color_compared_exactly():
    m = g.LiquidGlassEffectModel()
    _update(m, 0, 0, 344, 56, color=0xD9FFFFFF)
    assert _update(m, 0, 0, 344, 56, color=0xD9FFFFFE) is True


def test_uniform_packing_order():
    m = g.LiquidGlassEffectModel()
    _update(m, 0, 0, 344, 56, radii=(1, 2, 3, 4))  # LT, RT, RB, LB
    v = m.uniform_values()
    # Packed (RB, RT, LB, LT) — LiquidGlassEffect.java:93.
    assert v[("u_radius", 0)] == 3
    assert v[("u_radius", 1)] == 2
    assert v[("u_radius", 2)] == 4
    assert v[("u_radius", 3)] == 1


# ---------------------------------------------------------------------------
# Fixture file
# ---------------------------------------------------------------------------

def _load_fixtures():
    return json.loads(FIXTURES_JSON.read_text())


def test_fixture_file_is_fresh():
    assert g.main(["--check"]) == 0


def test_check_mode_detects_drift():
    rendered = g.render_json(g.DEFAULT_FRAG)
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "uniform_fixtures.json"
        out.write_text(rendered.replace('"changed": true', '"changed": false', 1))
        assert g.main(["--check", "--out", str(out)]) == 1
        out.write_text(rendered)
        assert g.main(["--check", "--out", str(out)]) == 0
        assert g.main(["--check", "--out", str(Path(td) / "missing.json")]) == 1


def test_fixture_shape():
    doc = _load_fixtures()
    assert doc["floatCount"] == 17
    assert doc["epsilon"] == 0.1
    assert doc["caseCount"] == len(doc["cases"])
    assert len(doc["cases"]) >= 40
    names = [c["name"] for c in doc["cases"]]
    assert len(names) == len(set(names))
    for case in doc["cases"]:
        assert case["steps"], case["name"]
        for s in case["steps"]:
            assert len(s["expected"]["uniforms"]) == 17, case["name"]
            assert isinstance(s["expected"]["changed"], bool)
            assert s["expected"]["thicknessPx"] >= 1


def test_fixture_covers_required_scenario_groups():
    names = " ".join(c["name"] for c in _load_fixtures()["cases"])
    for prefix in ("a0", "b0", "c0", "d0", "e0"):
        assert prefix in names


def test_fixture_spot_check_a01():
    doc = _load_fixtures()
    case = next(c for c in doc["cases"] if c["name"] == "a01_main_tabs_density1")
    u = case["steps"][0]["expected"]["uniforms"]
    a = 0xD9 / 255
    expected = [344.0, 57.0, 172.0, 28.5, 172.0, 28.5,
                28.0, 28.0, 28.0, 28.0, 11.0, 1.5, 0.75,
                a, a, a, a]
    assert u == expected, u


def test_fixture_spot_check_b01_rescale():
    doc = _load_fixtures()
    case = next(c for c in doc["cases"] if c["name"] == "b01_left_pair_overflow")
    u = case["steps"][0]["expected"]["uniforms"]
    # radius slots 6..9 = (RB, RT, LB, LT): right pair untouched, left 28/28.
    assert u[6:10] == [10.0, 10.0, 28.0, 28.0], u[6:10]


def test_fixture_epsilon_verdicts():
    doc = _load_fixtures()
    expected_changed = {
        "c01_identical_updates": [True, False],
        "c02_sub_epsilon_center_shift": [True, False],
        "c03_super_epsilon_center_shift": [True, True],
        "c04_sub_epsilon_drift_accumulates": [True, False, True],
        "c05_push_carries_sub_epsilon_values": [True, True],
        "c06_rescale_absorbs_radius_change": [True, False],
        "c07_intensity_epsilon": [True, False, True],
        "c08_index_epsilon": [True, False, True],
        "c09_thickness_clamp_absorbs_change": [True, False],
        "c10_color_change_by_one_bit": [True, True],
        "c11_alpha_only_color_change": [True, True],
        "c12_resize_pushes": [True, True],
        "c13_radius_epsilon": [True, False, True],
        "c14_rescale_pulls_change_under_epsilon": [True, False],
    }
    by_name = {c["name"]: c for c in doc["cases"]}
    for name, verdicts in expected_changed.items():
        got = [s["expected"]["changed"] for s in by_name[name]["steps"]]
        assert got == verdicts, f"{name}: {got}"


def test_no_push_steps_keep_previous_uniforms():
    doc = _load_fixtures()
    for case in doc["cases"]:
        prev = None
        for s in case["steps"]:
            if not s["expected"]["changed"]:
                assert prev is not None, case["name"]
                assert s["expected"]["uniforms"] == prev, case["name"]
            prev = s["expected"]["uniforms"]


def test_epsilon_verdicts_stable_under_float32():
    """The Java implementation compares float32 (0.1f); the fixtures are
    float64. Every emitted verdict must hold in both precisions, otherwise
    a fixture sits on the representability boundary and must be moved."""
    f32 = g.f32
    eps32 = f32(0.1)
    doc = _load_fixtures()
    for case in doc["cases"]:
        prev = None  # last-pushed values under float32
        for s in case["steps"]:
            inp = s["input"]
            width = inp["right"] - inp["left"]
            height = inp["bottom"] - inp["top"]
            thickness = g.clamp_thickness(
                inp["liquidThickness"], int(width), int(height), inp["density"]
            )
            lt, rt, rb, lb = g.rescale_vertical_radius_pairs(
                inp["radiusLeftTop"], inp["radiusRightTop"],
                inp["radiusRightBottom"], inp["radiusLeftBottom"], height,
            )
            new = [
                f32(width), f32(height),
                f32((inp["left"] + inp["right"]) / 2),
                f32((inp["top"] + inp["bottom"]) / 2),
                f32(width / 2), f32(height / 2),
                f32(lt), f32(rt), f32(rb), f32(lb),
                f32(thickness), f32(inp["intensity"]),
                f32(inp["refractIndex"]),
            ]
            color = inp["colorArgb"]
            if prev is None:
                prev_floats, prev_color = [0.0] * len(new), 0
            else:
                prev_floats, prev_color = prev
            changed32 = prev_color != color or any(
                abs(f32(a - b)) > eps32 for a, b in zip(prev_floats, new)
            )
            assert changed32 == s["expected"]["changed"], (
                f"{case['name']}: float32 verdict {changed32} != fixture "
                f"{s['expected']['changed']}"
            )
            if changed32:
                prev = (new, color)
            elif prev is None:
                prev = (prev_floats, prev_color)


def test_step_rejects_non_integral_rect():
    _raises(ValueError, g.step, 0, 0, 344.5, 56, 28, 28, 28, 28)


def test_generation_is_deterministic():
    assert g.render_json(g.DEFAULT_FRAG) == g.render_json(g.DEFAULT_FRAG)
