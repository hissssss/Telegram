#!/usr/bin/env python3
"""gen_shader_bindings.py — uniform slot codegen for liquid_glass.frag.

Parses the GLSL uniform declarations of
``flutter/telegram_ui/shaders/liquid_glass.frag`` **in declaration order** and
emits ``flutter/telegram_ui/lib/src/tokens/liquid_glass_uniforms.g.dart`` with
one ``const int`` slot index per float component (the argument to
``ui.FragmentShader.setFloat``), plus the total float count used as a bounds
assert by the uniform packer.

Sampler uniforms do not consume float slots; the single ``sampler2D`` (the
filter input) is emitted as sampler index 0.

Usage:
    python3 gen_shader_bindings.py            # (re)generate
    python3 gen_shader_bindings.py --check    # exit 1 if the committed file
                                              # does not match a fresh render

Stdlib-only by design (see ARCHITECTURE.md §4.3 / §5 "SDK-less
developability").
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import re
import sys
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parent.parent

DEFAULT_FRAG = REPO_ROOT / "flutter/telegram_ui/shaders/liquid_glass.frag"
DEFAULT_OUT = (
    REPO_ROOT
    / "flutter/telegram_ui/lib/src/tokens/liquid_glass_uniforms.g.dart"
)

# Float component count per GLSL type. Types not listed here (other than
# samplers) are a hard error: a new uniform type must be added deliberately.
FLOAT_TYPE_COMPONENTS = {
    "float": 1,
    "vec2": 2,
    "vec3": 3,
    "vec4": 4,
}
SAMPLER_TYPES = {"sampler2D"}

# Component-name overrides for uniforms whose packing is semantic rather than
# positional. u_radius packing is (RB, RT, LB, LT) — LiquidGlassEffect.java:93,
# the #1 silent-corruption hazard called out in ARCHITECTURE.md §3.3.
COMPONENT_SUFFIX_OVERRIDES = {
    "u_radius": ["RightBottom", "RightTop", "LeftBottom", "LeftTop"],
    "u_foreground_color": ["R", "G", "B", "A"],
}
DEFAULT_SUFFIXES = {1: [""], 2: ["X", "Y"], 3: ["X", "Y", "Z"], 4: ["X", "Y", "Z", "W"]}

# One-line doc per uniform, keyed by GLSL name.
UNIFORM_DOCS = {
    "u_size": "engine-set backdrop size in physical px (AGSL `resolution`)",
    "u_center": "panel rect center in px (AGSL `center`)",
    "u_half_size": "panel half extents in px (AGSL `size` — HALF width/height)",
    "u_radius": "corner radii packed (RB, RT, LB, LT) (AGSL `radius`)",
    "u_thickness": "glass lip thickness in px (AGSL `thickness`)",
    "u_refract_index": "index of refraction, 1.5 in production (AGSL `refract_index`)",
    "u_refract_intensity": "displacement multiplier, 0.75 default (AGSL `refract_intensity`)",
    "u_foreground_color": "premultiplied tint (AGSL `foreground_color_premultiplied`)",
    "u_backdrop": "backdrop texture, bound by the engine as the filter input (AGSL `img`)",
}

UNIFORM_RE = re.compile(
    r"^\s*uniform\s+(?P<type>\w+)\s+(?P<name>\w+)\s*;", re.MULTILINE
)


class ShaderParseError(RuntimeError):
    pass


def parse_uniforms(frag_source: str):
    """Returns the ordered list of (type, name) uniform declarations."""
    decls = []
    for m in UNIFORM_RE.finditer(frag_source):
        decls.append((m.group("type"), m.group("name")))
    if not decls:
        raise ShaderParseError("no uniform declarations found in shader")
    return decls


def build_slots(decls):
    """Maps declarations to float slots.

    Returns (components, float_count, samplers) where components is an ordered
    list of dicts {const, uniform, component, slot} and samplers an ordered
    list of dicts {const, uniform, index}.
    """
    components = []
    samplers = []
    slot = 0
    sampler_index = 0
    seen_consts = set()
    names = {name for _t, name in decls}
    for overridden in COMPONENT_SUFFIX_OVERRIDES:
        if overridden not in names:
            raise ShaderParseError(
                f"component-suffix override for '{overridden}' does not match "
                "any uniform in the shader — table out of date"
            )
    for gl_type, name in decls:
        if gl_type in SAMPLER_TYPES:
            const = f"kUniform{_camel(name)}Sampler"
            _check_unique(const, seen_consts)
            samplers.append(
                {"const": const, "uniform": name, "index": sampler_index}
            )
            sampler_index += 1
            continue
        if gl_type not in FLOAT_TYPE_COMPONENTS:
            raise ShaderParseError(
                f"unsupported uniform type '{gl_type}' for '{name}' — extend "
                "FLOAT_TYPE_COMPONENTS deliberately if this is intentional"
            )
        count = FLOAT_TYPE_COMPONENTS[gl_type]
        suffixes = COMPONENT_SUFFIX_OVERRIDES.get(name, DEFAULT_SUFFIXES[count])
        if len(suffixes) != count:
            raise ShaderParseError(
                f"override for '{name}' has {len(suffixes)} names but the "
                f"type {gl_type} has {count} components"
            )
        for comp, suffix in enumerate(suffixes):
            const = f"kUniform{_camel(name)}{suffix}"
            _check_unique(const, seen_consts)
            components.append(
                {"const": const, "uniform": name, "component": comp, "slot": slot}
            )
            slot += 1
    return components, slot, samplers


def _camel(uniform_name: str) -> str:
    base = uniform_name[2:] if uniform_name.startswith("u_") else uniform_name
    return "".join(part.capitalize() for part in base.split("_") if part)


def _check_unique(const: str, seen: set) -> None:
    if const in seen:
        raise ShaderParseError(f"duplicate generated constant name '{const}'")
    seen.add(const)


def layout_sha(decls) -> str:
    """Hash of the uniform layout only — body-only shader edits don't churn
    the generated file."""
    canonical = "\n".join(f"{t} {n}" for t, n in decls)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def render_dart(decls) -> str:
    components, float_count, samplers = build_slots(decls)
    lines = [
        "// GENERATED CODE - DO NOT MODIFY BY HAND.",
        "//",
        "// Generated by flutter/tool/gen_shader_bindings.py from",
        "// flutter/telegram_ui/shaders/liquid_glass.frag.",
        "// Regenerate: python3 flutter/tool/gen_shader_bindings.py",
        "// Verify:     python3 flutter/tool/gen_shader_bindings.py --check",
        "//",
        f"// Uniform layout SHA-256: {layout_sha(decls)}",
        "//",
        "// Float slot indices for ui.FragmentShader.setFloat, in shader",
        "// declaration order. The first vec2 (u_size) is set by the engine",
        "// when the shader runs as an ImageFilter; set it manually when",
        "// driving the shader through a Canvas.",
        "",
    ]
    for comp in components:
        doc = UNIFORM_DOCS.get(comp["uniform"], "")
        suffix = f" — {doc}" if doc else ""
        lines.append(
            f"/// `{comp['uniform']}` component {comp['component']}{suffix}."
        )
        lines.append(f"const int {comp['const']} = {comp['slot']};")
        lines.append("")
    lines.append("/// Total float uniform count — bounds assert for the uniform packer.")
    lines.append(f"const int kLiquidGlassUniformFloatCount = {float_count};")
    lines.append("")
    for sampler in samplers:
        doc = UNIFORM_DOCS.get(sampler["uniform"], "")
        suffix = f" — {doc}" if doc else ""
        lines.append(f"/// Sampler index of `{sampler['uniform']}`{suffix}.")
        lines.append(f"const int {sampler['const']} = {sampler['index']};")
        lines.append("")
    lines.append("/// Total sampler uniform count.")
    lines.append(f"const int kLiquidGlassUniformSamplerCount = {len(samplers)};")
    lines.append("")
    return "\n".join(lines)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frag", type=Path, default=DEFAULT_FRAG)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the committed file matches a fresh render; do not write",
    )
    args = parser.parse_args(argv)

    frag_source = args.frag.read_text(encoding="utf-8")
    rendered = render_dart(parse_uniforms(frag_source))

    if args.check:
        if not args.out.exists():
            print(f"CHECK FAILED: {args.out} does not exist", file=sys.stderr)
            return 1
        existing = args.out.read_text(encoding="utf-8")
        if existing != rendered:
            print(
                f"CHECK FAILED: {args.out} is stale — regenerate with "
                "python3 flutter/tool/gen_shader_bindings.py",
                file=sys.stderr,
            )
            sys.stderr.writelines(
                difflib.unified_diff(
                    existing.splitlines(keepends=True),
                    rendered.splitlines(keepends=True),
                    fromfile=str(args.out),
                    tofile="freshly generated",
                )
            )
            return 1
        print(f"OK: {args.out} is up to date")
        return 0

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(rendered, encoding="utf-8")
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
