#!/usr/bin/env python3
"""check_shader_parity.py — AGSL vs GLSL liquid-glass shader parity lint.

Compares the Android ground-truth shader
``TMessagesProj/src/main/res/raw/liquid_glass_shader.agsl`` against the
Flutter port ``flutter/telegram_ui/shaders/liquid_glass.frag`` and fails
loudly on drift:

1. The semantic uniform sets map 1:1 through the explicit RENAME_TABLE
   (types compatible, no unmapped uniform on either side).
2. The declaration order of the mapped float uniforms is identical — the
   generated slot map depends on it.
3. The GLSL body preserves the AGSL math: after canonicalising names/types
   and stripping whitespace, every load-bearing expression (sdf per-corner
   select, n_cos formula, refract call, lens height h, ray length with the
   8.0 constant, uv displacement, srcOver) must appear in both files.

Exit code 0 = parity holds; 1 = drift (each failed check is listed).

Stdlib-only by design.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parent.parent

DEFAULT_AGSL = (
    REPO_ROOT / "TMessagesProj/src/main/res/raw/liquid_glass_shader.agsl"
)
DEFAULT_GLSL = REPO_ROOT / "flutter/telegram_ui/shaders/liquid_glass.frag"

# Explicit AGSL-name -> GLSL-name mapping. A new uniform on either side must
# be added here deliberately; anything unmapped is drift.
RENAME_TABLE = {
    "img": "u_backdrop",
    "resolution": "u_size",
    "center": "u_center",
    "size": "u_half_size",
    "radius": "u_radius",
    "thickness": "u_thickness",
    "refract_index": "u_refract_index",
    "refract_intensity": "u_refract_intensity",
    "foreground_color_premultiplied": "u_foreground_color",
}

# AGSL type -> compatible GLSL type.
TYPE_TABLE = {
    "shader": "sampler2D",
    "float": "float",
    "float2": "vec2",
    "float3": "vec3",
    "float4": "vec4",
}
SAMPLER_AGSL_TYPES = {"shader"}

UNIFORM_RE = re.compile(
    r"^\s*uniform\s+(?P<type>\w+)\s+(?P<name>\w+)\s*;", re.MULTILINE
)

# Load-bearing expressions, matched as substrings of the canonicalised
# (comment-stripped, renamed-to-AGSL-vocabulary, type-normalised,
# whitespace-free) shader text. `None` means "not expected in this file".
# fmt: off
BODY_CHECKS = [
    # (check name, expected in AGSL, expected in GLSL)
    ("sdf select right/left pair", "r.xy=(p.x>0.0)?r.xy:r.zw;", "r.xy=(p.x>0.0)?r.xy:r.zw;"),
    ("sdf select bottom/top", "r.x=(p.y>0.0)?r.x:r.y;", "r.x=(p.y>0.0)?r.x:r.y;"),
    ("sdf q term", "q=abs(p)-size+r.x;", "q=abs(p)-size+r.x;"),
    ("sdf distance", "length(max(q,0.0))+min(max(q.x,q.y),0.0)-r.x;", "length(max(q,0.0))+min(max(q.x,q.y),0.0)-r.x;"),
    ("interior gate", "if(sd<0.0)", "if(sd<0.0)"),
    ("finite difference x", "sdX=sdfRect(p+vec2(1.0,0.0),radius);", "sdX=sdfRect(p+vec2(1.0,0.0),radius);"),
    ("finite difference y", "sdY=sdfRect(p+vec2(0.0,1.0),radius);", "sdY=sdfRect(p+vec2(0.0,1.0),radius);"),
    ("n_cos formula", "n_cos=max(thickness+sd,0.0)/thickness;", "n_cos=max(thickness+sd,0.0)/thickness;"),
    ("n_sin formula", "n_sin=sqrt(1.0-n_cos2);", "n_sin=sqrt(1.0-n_cos2);"),
    ("normal formula", "normal=normalize(vec3((sdX-sd)*n_cos,(sdY-sd)*n_cos,n_sin));", "normal=normalize(vec3((sdX-sd)*n_cos,(sdY-sd)*n_cos,n_sin));"),
    ("refract call", "refract_vec=refract(vec3(0.0,0.0,-1.0),normal,1.0/refract_index);", "refract_vec=refract(vec3(0.0,0.0,-1.0),normal,1.0/refract_index);"),
    ("lens height h", "h=sd<-thickness?thickness:sqrt(sd*(-2.0*thickness-sd));", "h=sd<-thickness?thickness:sqrt(sd*(-2.0*thickness-sd));"),
    ("ray length (h + 8.0*thickness)", "refract_length=(h+8.0*thickness)/-refract_vec.z;", "refract_length=(h+8.0*thickness)/-refract_vec.z;"),
    ("uv displacement", "uv+=refract_vec.xy*refract_length*refract_intensity;", "uv+=refract_vec.xy*refract_length*refract_intensity;"),
    ("srcOver rgb", "src.rgb+dst.rgb*(1.0-src.a)", "src.rgb+dst.rgb*(1.0-src.a)"),
    ("srcOver alpha", "src.a+(1.0-src.a)*dst.a", "src.a+(1.0-src.a)*dst.a"),
    # Composite call sites differ mechanically: AGSL evals the input shader
    # directly, the GLSL port samples via sampleBackdrop (normalising by the
    # engine-set size); the tint must stay the src operand in both.
    ("tint composited in-shader", "srcOver(vec4(foreground_color_premultiplied),img.eval(uv))", "srcOver(foreground_color_premultiplied,sampleBackdrop(uv))"),
    ("backdrop sampling normalised by size", None, "uv=posPx/resolution;"),
    ("backdrop texture read", None, "texture(img,uv)"),
]
# fmt: on


def parse_uniforms(source: str):
    return [(m.group("type"), m.group("name")) for m in UNIFORM_RE.finditer(source)]


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    source = re.sub(r"//[^\n]*", "", source)
    return source


def canonicalise(source: str, rename: dict) -> str:
    """Comment-free, renamed, type-normalised, whitespace-free shader text."""
    text = strip_comments(source)
    # Drop preprocessor lines (#version/#include/#ifdef/#endif...).
    text = "\n".join(
        line for line in text.splitlines() if not line.lstrip().startswith("#")
    )
    # Identifier renames, longest name first so prefixes cannot shadow.
    for old in sorted(rename, key=len, reverse=True):
        text = re.sub(rf"\b{re.escape(old)}\b", rename[old], text)
    # Type canonicalisation: AGSL halfN/floatN and GLSL vecN -> vecN.
    for n in ("4", "3", "2"):
        text = re.sub(rf"\bhalf{n}\b", f"vec{n}", text)
        text = re.sub(rf"\bfloat{n}\b", f"vec{n}", text)
    text = re.sub(r"\bhalf\b", "float", text)
    return re.sub(r"\s+", "", text)


def run_checks(agsl_source: str, glsl_source: str):
    """Returns a list of failure strings (empty = parity holds)."""
    failures = []

    agsl_uniforms = parse_uniforms(agsl_source)
    glsl_uniforms = parse_uniforms(glsl_source)
    agsl_by_name = dict((n, t) for t, n in agsl_uniforms)
    glsl_by_name = dict((n, t) for t, n in glsl_uniforms)

    # 1a. Every AGSL uniform must be in the rename table.
    for _t, name in agsl_uniforms:
        if name not in RENAME_TABLE:
            failures.append(
                f"AGSL uniform '{name}' has no entry in RENAME_TABLE — "
                "upstream added a uniform?"
            )
    # 1b. Every table entry must exist on both sides.
    for agsl_name, glsl_name in RENAME_TABLE.items():
        if agsl_name not in agsl_by_name:
            failures.append(
                f"RENAME_TABLE entry '{agsl_name}' not found in the AGSL "
                "shader — table out of date"
            )
            continue
        if glsl_name not in glsl_by_name:
            failures.append(
                f"GLSL uniform '{glsl_name}' (mapped from '{agsl_name}') is "
                "missing from the .frag"
            )
            continue
        expected = TYPE_TABLE.get(agsl_by_name[agsl_name])
        if expected is None:
            failures.append(
                f"AGSL uniform '{agsl_name}' has unmapped type "
                f"'{agsl_by_name[agsl_name]}'"
            )
        elif glsl_by_name[glsl_name] != expected:
            failures.append(
                f"type mismatch for '{agsl_name}' -> '{glsl_name}': AGSL "
                f"{agsl_by_name[agsl_name]} should map to GLSL {expected}, "
                f"found {glsl_by_name[glsl_name]}"
            )
    # 1c. No extra GLSL uniform outside the mapped set.
    mapped_glsl = set(RENAME_TABLE.values())
    for _t, name in glsl_uniforms:
        if name not in mapped_glsl:
            failures.append(
                f"GLSL uniform '{name}' is not the image of any AGSL uniform "
                "— add a RENAME_TABLE entry or remove it"
            )

    # 2. Declaration order of the mapped float (non-sampler) uniforms.
    agsl_float_order = [
        RENAME_TABLE[n]
        for t, n in agsl_uniforms
        if t not in SAMPLER_AGSL_TYPES and n in RENAME_TABLE
    ]
    glsl_float_order = [
        n for t, n in glsl_uniforms if t != "sampler2D" and n in mapped_glsl
    ]
    if agsl_float_order != glsl_float_order:
        failures.append(
            "float uniform declaration order differs:\n"
            f"  AGSL (mapped): {agsl_float_order}\n"
            f"  GLSL:          {glsl_float_order}"
        )

    # 3. Load-bearing body expressions.
    agsl_canon = canonicalise(agsl_source, {})  # AGSL names are the canon.
    reverse = {glsl: agsl for agsl, glsl in RENAME_TABLE.items()}
    glsl_canon = canonicalise(glsl_source, reverse)
    for name, agsl_expr, glsl_expr in BODY_CHECKS:
        if agsl_expr is not None and agsl_expr not in agsl_canon:
            failures.append(f"AGSL body drift: '{name}' — expected `{agsl_expr}`")
        if glsl_expr is not None and glsl_expr not in glsl_canon:
            failures.append(f"GLSL body drift: '{name}' — expected `{glsl_expr}`")

    return failures


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agsl", type=Path, default=DEFAULT_AGSL)
    parser.add_argument("--glsl", type=Path, default=DEFAULT_GLSL)
    args = parser.parse_args(argv)

    failures = run_checks(
        args.agsl.read_text(encoding="utf-8"),
        args.glsl.read_text(encoding="utf-8"),
    )
    if failures:
        print(
            f"SHADER PARITY FAILED ({len(failures)} problem(s)) between\n"
            f"  {args.agsl}\n  {args.glsl}:",
            file=sys.stderr,
        )
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    n_checks = sum(
        (a is not None) + (g is not None) for _n, a, g in BODY_CHECKS
    )
    print(
        f"OK: uniform map 1:1 ({len(RENAME_TABLE)} uniforms, order preserved) "
        f"and {n_checks} body expression checks hold"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
