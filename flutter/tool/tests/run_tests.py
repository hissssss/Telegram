#!/usr/bin/env python3
"""Plain-Python test runner for flutter/tool (pytest is not available in the
SDK-less environment; this discovers test_*.py modules and runs every
top-level test_* function with assert-based checks).

Usage: python3 flutter/tool/tests/run_tests.py [substring-filter]
"""

from __future__ import annotations

import importlib.util
import sys
import traceback
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent


def main(argv: list[str]) -> int:
    name_filter = argv[0] if argv else ""
    passed, failed = 0, 0
    failures: list[str] = []
    for mod_path in sorted(TESTS_DIR.glob("test_*.py")):
        spec = importlib.util.spec_from_file_location(mod_path.stem, mod_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for attr in sorted(dir(module)):
            if not attr.startswith("test_"):
                continue
            full_name = f"{mod_path.stem}::{attr}"
            if name_filter and name_filter not in full_name:
                continue
            try:
                getattr(module, attr)()
                passed += 1
                print(f"PASS {full_name}")
            except Exception:  # noqa: BLE001
                failed += 1
                failures.append(full_name)
                print(f"FAIL {full_name}")
                traceback.print_exc()
    print(f"\n{passed} passed, {failed} failed")
    if failures:
        for f in failures:
            print(f"  FAILED: {f}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
