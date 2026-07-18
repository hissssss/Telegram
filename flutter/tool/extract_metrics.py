#!/usr/bin/env python3
"""extract_metrics.py — glass scalar-constant extraction (ARCHITECTURE.md §3.4).

Reads the curated (file, regex, name) list in ``extract_spec.yaml``, pulls the
scalar constants of the liquid-glass system out of the Telegram Android Java
sources, evaluates arithmetic expressions where the Java value is one (e.g.
``40 - 1.66f`` -> 38.34, ``2 / 3f`` -> 0.666...), and emits
``flutter/telegram_ui/lib/src/tokens/glass_metrics.g.dart``.

Any upstream drift fails loudly: a regex that stops matching (or matches an
unexpected number of times) aborts extraction; a changed value shows up as a
diff under ``--check``.

The YAML subset used by extract_spec.yaml (top-level scalars + one list of
flat maps, single-quoted strings, inline int lists, full-line comments) is
parsed by the stdlib-only ``parse_mini_yaml`` below, so no PyYAML dependency
is required (ARCHITECTURE.md §1 goal 5). The file remains valid YAML for
humans and other tools.

Usage:
    python3 extract_metrics.py            # (re)generate
    python3 extract_metrics.py --check    # exit 1 if the committed file drifts
    python3 extract_metrics.py --print    # dump extracted values (debug)
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
DEFAULT_SPEC = TOOL_DIR / "extract_spec.yaml"

ALLOWED_KEYS = {
    "name", "doc", "file", "pattern", "kind", "dart",
    "group", "groups", "match", "matches", "dotall", "equal",
}
KINDS = {"int", "float", "expr", "color", "int_list"}
DEFAULT_DART_FOR_KIND = {
    "int": "int",
    "float": "double",
    "expr": "double",
    "color": "color",
    "int_list": "intList",
}
NAME_RE = re.compile(r"^k[A-Z][A-Za-z0-9]*$")


class SpecError(RuntimeError):
    pass


class ExtractionError(RuntimeError):
    pass


# --------------------------------------------------------------------------
# Mini YAML-subset parser (stdlib only).
# --------------------------------------------------------------------------

def _parse_scalar(text: str):
    text = text.strip()
    if text.startswith("'"):
        if not text.endswith("'") or len(text) < 2:
            raise SpecError(f"unterminated single-quoted scalar: {text!r}")
        return text[1:-1].replace("''", "'")
    if text.startswith("[") and text.endswith("]"):
        inner = text[1:-1].strip()
        if not inner:
            return []
        return [_parse_scalar(part) for part in inner.split(",")]
    if text == "true":
        return True
    if text == "false":
        return False
    try:
        return int(text)
    except ValueError:
        pass
    try:
        return float(text)
    except ValueError:
        pass
    return text


def parse_mini_yaml(text: str) -> dict:
    """Parses the restricted YAML subset used by extract_spec.yaml."""
    root: dict = {}
    current_list = None
    current_item = None
    for lineno, raw in enumerate(text.splitlines(), start=1):
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        try:
            if indent == 0:
                key, sep, rest = raw.partition(":")
                if not sep:
                    raise SpecError("expected 'key:' at top level")
                rest = rest.strip()
                if rest == "":
                    current_list = []
                    current_item = None
                    root[key.strip()] = current_list
                else:
                    root[key.strip()] = _parse_scalar(rest)
                    current_list = None
                    current_item = None
            else:
                if current_list is None:
                    raise SpecError("indented line outside a list block")
                body = stripped
                if body.startswith("- "):
                    current_item = {}
                    current_list.append(current_item)
                    body = body[2:].strip()
                if current_item is None:
                    raise SpecError("list entry must start with '- '")
                key, sep, rest = body.partition(":")
                if not sep:
                    raise SpecError("expected 'key: value' in list item")
                current_item[key.strip()] = _parse_scalar(rest.strip())
        except SpecError as exc:
            raise SpecError(f"extract_spec.yaml:{lineno}: {exc}") from None
    return root


# --------------------------------------------------------------------------
# Extraction.
# --------------------------------------------------------------------------

def eval_java_expr(text: str) -> float:
    """Evaluates a numeric Java expression like '40 - 1.66f' or '2 / 3f'.

    Only digits, '.', 'f'/'F' suffixes, + - * / ( ) and whitespace are
    allowed; anything else is a hard error.
    """
    cleaned = re.sub(r"(?<=[0-9.])[fF](?![0-9A-Za-z_])", "", text.strip())
    if not re.fullmatch(r"[0-9. +\-*/()]+", cleaned):
        raise ExtractionError(f"refusing to evaluate expression: {text!r}")
    try:
        value = eval(cleaned, {"__builtins__": {}}, {})  # noqa: S307
    except Exception as exc:  # pragma: no cover - defensive
        raise ExtractionError(f"failed to evaluate {text!r}: {exc}") from None
    return float(value)


def _parse_number(kind: str, text: str):
    if kind == "int":
        return int(text, 0)
    if kind == "color":
        return int(text, 0) & 0xFFFFFFFF
    if kind == "float":
        return float(text.rstrip("fF"))
    if kind == "expr":
        return eval_java_expr(text)
    raise ExtractionError(f"unknown scalar kind {kind!r}")


def validate_entry(entry: dict) -> None:
    unknown = set(entry) - ALLOWED_KEYS
    if unknown:
        raise SpecError(f"{entry.get('name', '<unnamed>')}: unknown keys {sorted(unknown)}")
    for required in ("name", "doc", "file", "pattern", "kind"):
        if required not in entry:
            raise SpecError(f"{entry.get('name', '<unnamed>')}: missing '{required}'")
    if not NAME_RE.match(entry["name"]):
        raise SpecError(f"{entry['name']}: not k-prefixed lowerCamelCase")
    if entry["kind"] not in KINDS:
        raise SpecError(f"{entry['name']}: unknown kind {entry['kind']!r}")
    if entry["kind"] == "int_list" and "groups" not in entry:
        raise SpecError(f"{entry['name']}: int_list requires 'groups'")


def extract(spec: dict, repo_root: Path):
    """Returns an ordered list of (entry, value) tuples."""
    entries = spec.get("constants")
    if not isinstance(entries, list) or not entries:
        raise SpecError("spec has no 'constants' list")
    seen_names = set()
    file_cache: dict = {}
    match_cache: dict = {}
    results = []
    for entry in entries:
        validate_entry(entry)
        name = entry["name"]
        if name in seen_names:
            raise SpecError(f"duplicate constant name {name}")
        seen_names.add(name)

        path = repo_root / entry["file"]
        if path not in file_cache:
            if not path.exists():
                raise ExtractionError(f"{name}: source file not found: {path}")
            file_cache[path] = path.read_text(encoding="utf-8")
        source = file_cache[path]

        flags = re.DOTALL if entry.get("dotall", False) else 0
        cache_key = (path, entry["pattern"], flags)
        if cache_key not in match_cache:
            match_cache[cache_key] = list(
                re.finditer(entry["pattern"], source, flags)
            )
        matches = match_cache[cache_key]

        expected = int(entry.get("matches", 1))
        if len(matches) != expected:
            raise ExtractionError(
                f"{name}: pattern matched {len(matches)} time(s) in "
                f"{entry['file']}, expected {expected} — upstream drift?"
            )
        m = matches[int(entry.get("match", 0))]

        for group_set in (entry.get("equal") or [],):
            if group_set:
                values = {m.group(g) for g in group_set}
                if len(values) != 1:
                    raise ExtractionError(
                        f"{name}: groups {group_set} were expected to be "
                        f"equal but differ: {sorted(values)}"
                    )

        kind = entry["kind"]
        if kind == "int_list":
            value = [int(m.group(g), 0) for g in entry["groups"]]
        else:
            value = _parse_number(kind, m.group(int(entry.get("group", 1))))
        results.append((entry, value))
    return results


# --------------------------------------------------------------------------
# Dart emission.
# --------------------------------------------------------------------------

def format_double(v: float) -> str:
    if v == int(v) and abs(v) < 1e15:
        return f"{int(v)}.0"
    return repr(v)


def _dart_decl(entry: dict, value) -> str:
    dart = entry.get("dart", DEFAULT_DART_FOR_KIND[entry["kind"]])
    name = entry["name"]
    if dart == "double":
        return f"const double {name} = {format_double(float(value))};"
    if dart == "int":
        return f"const int {name} = {int(value)};"
    if dart == "color":
        return f"const int {name} = 0x{int(value):08X};"
    if dart == "intList":
        elements = ", ".join(f"0x{v:02X}" for v in value)
        return f"const List<int> {name} = <int>[{elements}];"
    raise SpecError(f"{name}: unknown dart type {dart!r}")


def render_dart(results, spec_text: str) -> str:
    spec_sha = hashlib.sha256(spec_text.encode("utf-8")).hexdigest()
    lines = [
        "// GENERATED CODE - DO NOT MODIFY BY HAND.",
        "//",
        "// Generated by flutter/tool/extract_metrics.py from",
        "// flutter/tool/extract_spec.yaml — the scalar constants of the",
        "// liquid-glass system (ARCHITECTURE.md §3.4) extracted from the",
        "// Telegram Android sources under TMessagesProj/src/main/.",
        "// Regenerate: python3 flutter/tool/extract_metrics.py",
        "// Verify:     python3 flutter/tool/extract_metrics.py --check",
        "//",
        "// Values suffixed `Dp` are logical dp: multiply by the device pixel",
        "// ratio at runtime (dp()/dpf2() rounding semantics live in",
        "// foundation/dimens.dart).",
        "//",
        f"// Spec SHA-256: {spec_sha}",
        "",
    ]
    for entry, value in results:
        lines.append(f"/// {entry['doc']}")
        lines.append("///")
        lines.append(f"/// Source: `{entry['file']}`.")
        lines.append(_dart_decl(entry, value))
        lines.append("")
    return "\n".join(lines)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC)
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument(
        "--out",
        type=Path,
        default=None,
        help="override the output path from the spec",
    )
    parser.add_argument("--check", action="store_true")
    parser.add_argument(
        "--print", action="store_true", dest="print_values",
        help="print extracted values instead of writing the Dart file",
    )
    args = parser.parse_args(argv)

    spec_text = args.spec.read_text(encoding="utf-8")
    spec = parse_mini_yaml(spec_text)
    results = extract(spec, args.repo_root)

    if args.print_values:
        for entry, value in results:
            print(f"{entry['name']} = {value!r}")
        return 0

    out = args.out
    if out is None:
        output_rel = spec.get("output")
        if not output_rel:
            raise SpecError("spec is missing the 'output' path")
        out = args.repo_root / output_rel

    rendered = render_dart(results, spec_text)

    if args.check:
        if not out.exists():
            print(f"CHECK FAILED: {out} does not exist", file=sys.stderr)
            return 1
        existing = out.read_text(encoding="utf-8")
        if existing != rendered:
            print(
                f"CHECK FAILED: {out} is stale — regenerate with "
                "python3 flutter/tool/extract_metrics.py",
                file=sys.stderr,
            )
            sys.stderr.writelines(
                difflib.unified_diff(
                    existing.splitlines(keepends=True),
                    rendered.splitlines(keepends=True),
                    fromfile=str(out),
                    tofile="freshly generated",
                )
            )
            return 1
        print(f"OK: {out} is up to date")
        return 0

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(rendered, encoding="utf-8")
    print(f"wrote {out} ({len(results)} constants)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
