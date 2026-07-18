#!/usr/bin/env python3
"""gen_uniform_fixtures.py — Ring-0 fixtures for the liquid-glass uniform packer.

Python re-implementation of ``LiquidGlassEffect.update`` (from
``TMessagesProj/src/main/java/org/telegram/ui/Components/blur3/LiquidGlassEffect.java``)
including:

* center/half-size computation (lines 50-54),
* the **vertical-only** radius-pair rescale (lines 56-65): if a left or right
  vertical radius pair sums past the rect height, both members are scaled
  proportionally to sum exactly to the height; there is no horizontal clamp,
* the 0.1f-per-float dirty-check semantics (lines 67-82): uniforms are only
  re-pushed when at least one float moves by more than 0.1 from its **last
  pushed** value (comparison happens *after* the radius rescale), with an
  exact int compare on the color,
* the component-wise color premultiply (lines 85-88),
* the (RB, RT, LB, LT) radius uniform packing (line 93),

plus the thickness clamp of ``BlurredBackgroundDrawableRenderNode.java:115-118``:
``max(min(liquidThickness <= 0 ? dp(11) : liquidThickness, min(w, h) / 5), 1)``
with Java int division and ``dp(v) = ceil(density * v)``.

Emits ``flutter/tool/fixtures/uniform_fixtures.json``: deterministic
(input -> expected 17-float uniform array) tables consumed by the Dart
``LiquidGlassUniforms`` Ring-1 tests. Arithmetic is IEEE float64 (matching the
Dart consumer); the test suite verifies every epsilon verdict is stable under
float32 as well, so the tables also mirror the Java behaviour.

Usage:
    python3 gen_uniform_fixtures.py           # (re)generate
    python3 gen_uniform_fixtures.py --check   # exit 1 on drift

Stdlib-only by design.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))

import gen_shader_bindings  # noqa: E402  (sibling script, layout authority)

REPO_ROOT = TOOL_DIR.parent.parent
DEFAULT_FRAG = REPO_ROOT / "flutter/telegram_ui/shaders/liquid_glass.frag"
DEFAULT_OUT = TOOL_DIR / "fixtures/uniform_fixtures.json"

EPSILON = 0.1  # LiquidGlassEffect.java:67-82


def f32(x: float) -> float:
    """Rounds a Python float to float32 precision (Java `float`)."""
    return struct.unpack("f", struct.pack("f", x))[0]


def dp(value: float, density: float) -> int:
    """AndroidUtilities.dp: ceil(density * value), 0 for 0."""
    if value == 0:
        return 0
    return math.ceil(density * value)


def clamp_thickness(liquid_thickness: int, width: int, height: int, density: float) -> int:
    """BlurredBackgroundDrawableRenderNode.java:115-118.

    Java ints throughout: min(w, h) / 5 is integer division.
    """
    default = dp(11, density)
    t = default if liquid_thickness <= 0 else liquid_thickness
    return max(min(t, min(width, height) // 5), 1)


def rescale_vertical_radius_pairs(
    radius_left_top, radius_right_top, radius_right_bottom, radius_left_bottom, height
):
    """LiquidGlassEffect.java:56-65 — vertical pairs only, no horizontal clamp."""
    if radius_left_top + radius_left_bottom > height:
        a = radius_left_top / (radius_left_top + radius_left_bottom)
        radius_left_top = height * a
        radius_left_bottom = height * (1.0 - a)
    if radius_right_top + radius_right_bottom > height:
        a = radius_right_top / (radius_right_top + radius_right_bottom)
        radius_right_top = height * a
        radius_right_bottom = height * (1.0 - a)
    return radius_left_top, radius_right_top, radius_right_bottom, radius_left_bottom


def premultiply(color: int):
    """LiquidGlassEffect.java:85-88 — returns premultiplied (r, g, b, a)."""
    a = ((color >> 24) & 0xFF) / 255.0
    r = ((color >> 16) & 0xFF) / 255.0 * a
    g = ((color >> 8) & 0xFF) / 255.0 * a
    b = (color & 0xFF) / 255.0 * a
    return r, g, b, a


class LiquidGlassEffectModel:
    """Stateful model of LiquidGlassEffect: fields start at Java defaults
    (floats 0.0, color 0) and only advance when a push happens."""

    #: last-pushed values, field order mirrors the Java class
    def __init__(self):
        self.resolution_x = 0.0
        self.resolution_y = 0.0
        self.center_x = 0.0
        self.center_y = 0.0
        self.size_x = 0.0
        self.size_y = 0.0
        self.radius_left_top = 0.0
        self.radius_right_top = 0.0
        self.radius_right_bottom = 0.0
        self.radius_left_bottom = 0.0
        self.thickness = 0.0
        self.intensity = 0.0
        self.index = 0.0
        self.foreground_color = 0

    def update(
        self,
        left, top, right, bottom,
        radius_left_top, radius_right_top, radius_right_bottom, radius_left_bottom,
        thickness, intensity, index, foreground_color,
        resolution_x, resolution_y,
    ):
        """Returns True when the uniforms were (re)pushed."""
        center_x = (left + right) / 2
        center_y = (top + bottom) / 2
        width = right - left
        height = bottom - top
        size_x = width / 2
        size_y = height / 2

        (
            radius_left_top,
            radius_right_top,
            radius_right_bottom,
            radius_left_bottom,
        ) = rescale_vertical_radius_pairs(
            radius_left_top, radius_right_top, radius_right_bottom,
            radius_left_bottom, height,
        )

        changed = (
            abs(self.resolution_x - resolution_x) > EPSILON
            or abs(self.resolution_y - resolution_y) > EPSILON
            or abs(self.center_x - center_x) > EPSILON
            or abs(self.center_y - center_y) > EPSILON
            or abs(self.size_x - size_x) > EPSILON
            or abs(self.size_y - size_y) > EPSILON
            or abs(self.radius_left_top - radius_left_top) > EPSILON
            or abs(self.radius_right_top - radius_right_top) > EPSILON
            or abs(self.radius_right_bottom - radius_right_bottom) > EPSILON
            or abs(self.radius_left_bottom - radius_left_bottom) > EPSILON
            or abs(self.thickness - thickness) > EPSILON
            or abs(self.intensity - intensity) > EPSILON
            or abs(self.index - index) > EPSILON
            or self.foreground_color != foreground_color
        )
        if changed:
            self.resolution_x = resolution_x
            self.resolution_y = resolution_y
            self.center_x = center_x
            self.center_y = center_y
            self.size_x = size_x
            self.size_y = size_y
            self.radius_left_top = radius_left_top
            self.radius_right_top = radius_right_top
            self.radius_right_bottom = radius_right_bottom
            self.radius_left_bottom = radius_left_bottom
            self.thickness = thickness
            self.intensity = intensity
            self.index = index
            self.foreground_color = foreground_color
        return changed

    def uniform_values(self):
        """Currently pushed values keyed by (glsl uniform name, component),
        matching the shader layout: radius packed (RB, RT, LB, LT)
        (LiquidGlassEffect.java:90-97)."""
        r, g, b, a = premultiply(self.foreground_color)
        return {
            ("u_size", 0): self.resolution_x,
            ("u_size", 1): self.resolution_y,
            ("u_center", 0): self.center_x,
            ("u_center", 1): self.center_y,
            ("u_half_size", 0): self.size_x,
            ("u_half_size", 1): self.size_y,
            ("u_radius", 0): self.radius_right_bottom,
            ("u_radius", 1): self.radius_right_top,
            ("u_radius", 2): self.radius_left_bottom,
            ("u_radius", 3): self.radius_left_top,
            ("u_thickness", 0): self.thickness,
            ("u_refract_index", 0): self.index,
            ("u_refract_intensity", 0): self.intensity,
            ("u_foreground_color", 0): r,
            ("u_foreground_color", 1): g,
            ("u_foreground_color", 2): b,
            ("u_foreground_color", 3): a,
        }


def shader_layout(frag_path: Path):
    """(ordered component list, float count) parsed from the .frag — the
    fixtures inherit the slot order from the layout authority."""
    decls = gen_shader_bindings.parse_uniforms(
        frag_path.read_text(encoding="utf-8")
    )
    components, float_count, _samplers = gen_shader_bindings.build_slots(decls)
    return components, float_count


def step(
    left, top, right, bottom,
    radius_left_top, radius_right_top, radius_right_bottom, radius_left_bottom,
    liquid_thickness=0, density=1.0, intensity=0.75, index=1.5, color=0xD9FFFFFF,
):
    """One update call. The rect edges must produce integral width/height —
    the thickness clamp consumes Java-int bounds."""
    width = right - left
    height = bottom - top
    if width != int(width) or height != int(height):
        raise ValueError("fixture rects must have integral width/height")
    return {
        "left": float(left), "top": float(top),
        "right": float(right), "bottom": float(bottom),
        "radiusLeftTop": float(radius_left_top),
        "radiusRightTop": float(radius_right_top),
        "radiusRightBottom": float(radius_right_bottom),
        "radiusLeftBottom": float(radius_left_bottom),
        "liquidThickness": int(liquid_thickness),
        "density": float(density),
        "intensity": float(intensity),
        "refractIndex": float(index),
        "colorArgb": int(color) & 0xFFFFFFFF,
        "colorHex": f"0x{int(color) & 0xFFFFFFFF:08X}",
    }


def build_cases():
    """The curated fixture list. Deterministic — no randomness."""
    s = step
    white85 = 0xD9FFFFFF
    cases = [
        # --- Group A: production-shaped rects ------------------------------
        ("a01_main_tabs_density1",
         "mainTabs pill at density 1: 344x57, r=28, default thickness dp(11)=11",
         [s(0, 0, 344, 57, 28, 28, 28, 28)]),
        ("a02_main_tabs_density2625",
         "mainTabs pill at density 2.625: dp(11)=ceil(28.875)=29 < 150/5=30",
         [s(0, 0, 903, 150, 73.5, 73.5, 73.5, 73.5, density=2.625)]),
        ("a03_main_tabs_density3",
         "mainTabs pill at density 3: dp(11)=33 < 171/5=34",
         [s(0, 0, 1032, 171, 84, 84, 84, 84, density=3.0)]),
        ("a04_full_width_bar_square",
         "full-width bar with square corners (radius 0 everywhere)",
         [s(0, 0, 1080, 168, 0, 0, 0, 0, density=2.625)]),
        ("a05_fast_scroll_tag",
         "fast-scroll tag: explicit thickness dp(4)=11 at density 2.625",
         [s(0, 0, 131, 84, 42, 42, 42, 42, liquid_thickness=11, density=2.625)]),
        ("a06_tag_chip",
         "tag chip: explicit thickness dp(5)=15 at density 3",
         [s(0, 0, 150, 90, 45, 45, 45, 45, liquid_thickness=15, density=3.0)]),
        ("a07_keyboard_panel",
         "under-keyboard panel: thickness dp(32)=84 at density 2.625, "
         "intensity 0.4 (ChatInputViewsContainer.java:89-90)",
         [s(0, 0, 1080, 840, 52, 52, 0, 0, liquid_thickness=84,
            density=2.625, intensity=0.4)]),
        ("a08_circular_pill",
         "circular pill 84x84, radius 42 everywhere",
         [s(0, 0, 84, 84, 42, 42, 42, 42)]),
        ("a09_offset_rect",
         "rect not anchored at the origin: center offset from zero",
         [s(24, 906, 368, 963, 28, 28, 28, 28)]),
        # --- Group B: vertical radius-pair rescale --------------------------
        ("b01_left_pair_overflow",
         "left pair 40+40 > h=56 rescales to 28+28; right pair 10+10 untouched",
         [s(0, 0, 344, 56, 40, 10, 10, 40)]),
        ("b02_right_pair_overflow_asymmetric",
         "right pair 42+28=70 > h=56 -> a=0.6 -> 33.6/22.4; left pair untouched",
         [s(0, 0, 344, 56, 8, 42, 28, 8)]),
        ("b03_both_pairs_overflow",
         "left 100+50 -> 40+20 (h=60); right 60+60 -> 30+30",
         [s(0, 0, 400, 60, 100, 60, 60, 50)]),
        ("b04_sum_equals_height_no_rescale",
         "28+28 == h=56 exactly: strict `>` comparison, no rescale",
         [s(0, 0, 344, 56, 28, 28, 28, 28)]),
        ("b05_sum_just_over_height",
         "28.5+28 = 56.5 > 56: rescale kicks in just past the boundary",
         [s(0, 0, 344, 56, 28.5, 28, 28, 28)]),
        ("b06_zero_partner_radius",
         "80+0 > 56 with a=1.0: top absorbs the full height, bottom stays 0",
         [s(0, 0, 344, 56, 80, 12, 12, 0)]),
        ("b07_no_horizontal_clamp",
         "w=56 but horizontal sums (200) are NOT clamped; vertical sums fit h=400",
         [s(0, 0, 56, 400, 100, 100, 100, 100)]),
        ("b08_both_pairs_equal_overflow",
         "all radii 28 on h=40: both pairs rescale to 20+20",
         [s(0, 0, 344, 40, 28, 28, 28, 28)]),
        # --- Group C: 0.1f epsilon dirty-check ------------------------------
        ("c01_identical_updates",
         "second identical update does not re-push",
         [s(0, 0, 344, 56, 28, 28, 28, 28),
          s(0, 0, 344, 56, 28, 28, 28, 28)]),
        ("c02_sub_epsilon_center_shift",
         "center moves 0.0625 <= 0.1: no push, uniforms keep step-1 values",
         [s(0, 0, 344, 56, 28, 28, 28, 28),
          s(0.0625, 0, 344.0625, 56, 28, 28, 28, 28)]),
        ("c03_super_epsilon_center_shift",
         "center moves 0.125 > 0.1: push",
         [s(0, 0, 344, 56, 28, 28, 28, 28),
          s(0.125, 0, 344.125, 56, 28, 28, 28, 28)]),
        ("c04_sub_epsilon_drift_accumulates",
         "two 0.0625 moves: second no-push, third pushes (0.125 from last push)",
         [s(0, 0, 344, 56, 28, 28, 28, 28),
          s(0.0625, 0, 344.0625, 56, 28, 28, 28, 28),
          s(0.125, 0, 344.125, 56, 28, 28, 28, 28)]),
        ("c05_push_carries_sub_epsilon_values",
         "big thickness change forces a push that also carries a 0.0625 "
         "center move below epsilon",
         [s(0, 0, 344, 56, 28, 28, 28, 28),
          s(0.0625, 0, 344.0625, 56, 28, 28, 28, 28, liquid_thickness=5)]),
        ("c06_rescale_absorbs_radius_change",
         "raw left pair 40/40 then 45/45 both rescale to 28/28 on h=56: "
         "comparison is post-rescale, so no push",
         [s(0, 0, 344, 56, 40, 10, 10, 40),
          s(0, 0, 344, 56, 45, 10, 10, 45)]),
        ("c07_intensity_epsilon",
         "intensity 0.75 -> 0.8 (0.05, no push) -> 0.9 (0.15 from 0.75, push)",
         [s(0, 0, 344, 56, 28, 28, 28, 28, intensity=0.75),
          s(0, 0, 344, 56, 28, 28, 28, 28, intensity=0.8),
          s(0, 0, 344, 56, 28, 28, 28, 28, intensity=0.9)]),
        ("c08_index_epsilon",
         "refract index 1.5 -> 1.55 (no push) -> 1.65 (push)",
         [s(0, 0, 344, 56, 28, 28, 28, 28, index=1.5),
          s(0, 0, 344, 56, 28, 28, 28, 28, index=1.55),
          s(0, 0, 344, 56, 28, 28, 28, 28, index=1.65)]),
        ("c09_thickness_clamp_absorbs_change",
         "40x40 rect clamps both default (11) and explicit 100 to 40/5=8: no push",
         [s(0, 0, 40, 40, 8, 8, 8, 8),
          s(0, 0, 40, 40, 8, 8, 8, 8, liquid_thickness=100)]),
        ("c10_color_change_by_one_bit",
         "color is compared exactly: +1 on blue re-pushes everything",
         [s(0, 0, 344, 56, 28, 28, 28, 28, color=0xD9FFFFFF),
          s(0, 0, 344, 56, 28, 28, 28, 28, color=0xD9FFFFFE)]),
        ("c11_alpha_only_color_change",
         "alpha-only change re-pushes; premultiply scales all components",
         [s(0, 0, 344, 56, 28, 28, 28, 28, color=0xFF336699),
          s(0, 0, 344, 56, 28, 28, 28, 28, color=0xFE336699)]),
        ("c12_resize_pushes",
         "node resize changes resolution/center/size together: push",
         [s(0, 0, 344, 56, 28, 28, 28, 28),
          s(0, 0, 345, 56, 28, 28, 28, 28)]),
        ("c13_radius_epsilon",
         "radius 28 -> 28.05 (no push) -> 28.2 (push); h=100 keeps the "
         "vertical pairs clear of the rescale",
         [s(0, 0, 344, 100, 28, 28, 28, 28),
          s(0, 0, 344, 100, 28.05, 28, 28, 28),
          s(0, 0, 344, 100, 28.2, 28, 28, 28)]),
        ("c14_rescale_pulls_change_under_epsilon",
         "raw radius 28 -> 28.2 would push, but 28.2+28 > h=56 rescales to "
         "28.0996/27.9004: both deltas 0.0996 <= 0.1, so no push",
         [s(0, 0, 344, 56, 28, 28, 28, 28),
          s(0, 0, 344, 56, 28.2, 28, 28, 28)]),
        # --- Group D: color premultiply -------------------------------------
        ("d01_alpha_zero",
         "alpha 0 premultiplies every channel to 0",
         [s(0, 0, 344, 56, 28, 28, 28, 28, color=0x00FF8040)]),
        ("d02_alpha_128",
         "alpha 128: r=1*a, g=(128/255)*a, b=(64/255)*a with a=128/255",
         [s(0, 0, 344, 56, 28, 28, 28, 28, color=0x80FF8040)]),
        ("d03_alpha_255",
         "alpha 255: premultiply is identity on rgb",
         [s(0, 0, 344, 56, 28, 28, 28, 28, color=0xFF112233)]),
        ("d04_opaque_black",
         "opaque black: rgb 0, alpha 1",
         [s(0, 0, 344, 56, 28, 28, 28, 28, color=0xFF000000)]),
        ("d05_light_glass_tint",
         "light mainTabs-like tint (solveSrcColor output shape)",
         [s(0, 0, 344, 56, 28, 28, 28, 28, color=0xD9F7F7F7)]),
        ("d06_dark_glass_tint",
         "dark theme tint",
         [s(0, 0, 344, 56, 28, 28, 28, 28, color=0xC21E2A35)]),
        # --- Group E: thickness clamp ----------------------------------------
        ("e01_default_thickness_density1",
         "default: dp(11)=11 at density 1",
         [s(0, 0, 344, 57, 28, 28, 28, 28, density=1.0)]),
        ("e02_default_thickness_density2625",
         "default: dp(11)=ceil(28.875)=29 at density 2.625",
         [s(0, 0, 903, 150, 73.5, 73.5, 73.5, 73.5, density=2.625)]),
        ("e03_default_thickness_density3",
         "default: dp(11)=33 at density 3",
         [s(0, 0, 1032, 171, 84, 84, 84, 84, density=3.0)]),
        ("e04_clamped_by_bounds",
         "min(w,h)/5 clamp: 344x40 -> 40/5=8 < 11",
         [s(0, 0, 344, 40, 20, 20, 20, 20, density=1.0)]),
        ("e05_floor_one",
         "degenerate 4x4 rect: 4/5=0 (int division) floored to 1",
         [s(0, 0, 4, 4, 2, 2, 2, 2, density=1.0)]),
        ("e06_explicit_above_clamp",
         "explicit 50 clamps to 100/5=20",
         [s(0, 0, 100, 100, 30, 30, 30, 30, liquid_thickness=50)]),
        ("e07_negative_thickness_uses_default",
         "liquidThickness <= 0 falls back to dp(11)",
         [s(0, 0, 344, 57, 28, 28, 28, 28, liquid_thickness=-5)]),
        ("e08_integer_division",
         "h=59: 59/5=11 in Java int division (not 11.8) beats dp(11)=33 at d=3",
         [s(0, 0, 344, 59, 28, 28, 28, 28, density=3.0)]),
    ]
    return cases


def run_model(cases, components, float_count):
    """Executes every case through the model, returning JSON-ready dicts."""
    out = []
    for name, description, steps in cases:
        model = LiquidGlassEffectModel()
        rendered_steps = []
        for inp in steps:
            width = int(inp["right"] - inp["left"])
            height = int(inp["bottom"] - inp["top"])
            thickness_px = clamp_thickness(
                inp["liquidThickness"], width, height, inp["density"]
            )
            changed = model.update(
                inp["left"], inp["top"], inp["right"], inp["bottom"],
                inp["radiusLeftTop"], inp["radiusRightTop"],
                inp["radiusRightBottom"], inp["radiusLeftBottom"],
                float(thickness_px), inp["intensity"], inp["refractIndex"],
                inp["colorArgb"],
                float(width), float(height),
            )
            values = model.uniform_values()
            uniforms = [0.0] * float_count
            for comp in components:
                uniforms[comp["slot"]] = values[(comp["uniform"], comp["component"])]
            rendered_steps.append({
                "input": inp,
                "expected": {
                    "thicknessPx": thickness_px,
                    "changed": changed,
                    "uniforms": uniforms,
                },
            })
        out.append({
            "name": name,
            "description": description,
            "steps": rendered_steps,
        })
    return out


def render_json(frag_path: Path) -> str:
    components, float_count = shader_layout(frag_path)
    cases = run_model(build_cases(), components, float_count)
    doc = {
        "$comment": (
            "GENERATED by flutter/tool/gen_uniform_fixtures.py - DO NOT EDIT. "
            "Python re-implementation of LiquidGlassEffect.update (radius "
            "rescale, 0.1f epsilon, premultiply) + the thickness clamp of "
            "BlurredBackgroundDrawableRenderNode.java:115-118. 'uniforms' is "
            "the currently-bound 17-float array after each step in shader "
            "slot order; slots 0-1 (u_size) carry the node width/height "
            "(engine-set in production). Expected float tolerance for the "
            "Dart consumer: 1e-6."
        ),
        "schemaVersion": 1,
        "epsilon": EPSILON,
        "uniformOrder": [
            f"{comp['uniform']}[{comp['component']}]"
            for comp in sorted(components, key=lambda c: c["slot"])
        ],
        "floatCount": float_count,
        "caseCount": len(cases),
        "cases": cases,
    }
    return json.dumps(doc, indent=2) + "\n"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frag", type=Path, default=DEFAULT_FRAG)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the committed fixtures match a fresh render; do not write",
    )
    args = parser.parse_args(argv)

    rendered = render_json(args.frag)

    if args.check:
        if not args.out.exists():
            print(f"CHECK FAILED: {args.out} does not exist", file=sys.stderr)
            return 1
        if args.out.read_text(encoding="utf-8") != rendered:
            print(
                f"CHECK FAILED: {args.out} is stale — regenerate with "
                "python3 flutter/tool/gen_uniform_fixtures.py",
                file=sys.stderr,
            )
            return 1
        print(f"OK: {args.out} is up to date")
        return 0

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(rendered, encoding="utf-8")
    n_steps = sum(len(c[2]) for c in build_cases())
    print(f"wrote {args.out} ({len(build_cases())} cases, {n_steps} steps)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
