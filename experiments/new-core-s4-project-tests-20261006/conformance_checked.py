#!/usr/bin/env python3
"""Full S4 conformance: strict statuses, actual execution, retired arenas only.

The historical sweep already ran propagation's nine tests; its R-3 exclusion
label was stale. This adapter removes that label and always forces Core tests,
so cached successes cannot stand in for leak or fact verification.
"""
import importlib.util
from collections import Counter
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]


def imported(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_report(value, status, allow_cached=True, selected=lambda name: True):
    """Validate the wire report before any dictionary can collapse duplicate tests."""
    if not isinstance(value, dict) or value.get("version") != "native-tests-v1":
        raise ValueError("invalid native test report version/schema")
    tests = value.get("tests")
    if not isinstance(tests, list):
        raise ValueError("tests must be an array")
    names, counts = set(), Counter()
    allowed = {"passed", "cached", "failed", "skipped", "unsupported"}
    for test in tests:
        if not isinstance(test, dict):
            raise ValueError("test must be an object")
        name, verdict = test.get("name"), test.get("status")
        if not isinstance(name, str) or not name or name in names:
            raise ValueError("invalid or duplicate test name")
        if not isinstance(verdict, str) or verdict not in allowed:
            raise ValueError("invalid test status")
        if any(field in test and not isinstance(test[field], str) for field in ("reason", "at")):
            raise ValueError("test reason/position must be strings")
        names.add(name)
        counts[verdict] += 1
        if selected(name) and verdict == "unsupported":
            raise ValueError("selected test is unsupported")
        if selected(name) and verdict == "cached" and not allow_cached:
            raise ValueError("forced conformance test did not execute")
    for verdict in allowed:
        total = value.get(verdict, 0) if verdict == "unsupported" else value.get(verdict)
        if type(total) is not int or total < 0 or total != counts[verdict]:
            raise ValueError(f"report total disagrees with {verdict} verdicts")
    if "executed" in value:
        executed = value["executed"]
        if type(executed) is not int or not 0 <= executed <= counts["passed"] + counts["failed"]:
            raise ValueError("invalid executed total")
    expected = 1 if counts["failed"] else (0 if tests else 3)
    if status != expected:
        raise ValueError("compiler status disagrees with test report")
    return counts


def checked_report(original, done, what, selected):
    if done is None:
        return original(done, what)
    value = original(done, what)
    if isinstance(value, str):
        return value
    try:
        validate_report(value, done.returncode, allow_cached=not what.startswith("new core"), selected=selected)
    except (ValueError, TypeError) as error:
        return f"{what}: invalid report: {error}"
    return value


def main():
    sweep = imported("s4_conformance", ROOT / "experiments/new-core-s1-20261005/conformance.py")
    original = sweep.parse
    selected = lambda name: sweep.keep(name, "--include-arena" in sys.argv)
    sweep.parse = lambda done, what: checked_report(original, done, what, selected)
    sweep.EXCLUDED.pop("migrated/propagation", None)
    parent = sweep.Tool

    class Fresh(parent):
        def run(self, argv, *args, **kwargs):
            if len(argv) > 1 and argv[0] == self.core and argv[1] == "test":
                argv = [*argv, "--force"]
            return super().run(argv, *args, **kwargs)

    sweep.Tool = Fresh
    return sweep.main()


if __name__ == "__main__":
    raise SystemExit(main())
