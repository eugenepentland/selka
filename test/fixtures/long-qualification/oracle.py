#!/usr/bin/env python3
"""Require the forced driver to finish both concrete tests, never cached verdicts."""
import json
from pathlib import Path
import sys


def validate(value):
    keys = ("passed", "failed", "skipped", "cached", "unsupported")
    if (type(value) is not dict or value.get("version") != "native-tests-v1"
            or any(type(value.get(key)) is not int for key in keys)
            or [value.get(key) for key in keys] != [2, 0, 0, 0, 0]):
        raise ValueError("driver did not complete exactly two fresh passing tests")
    rows = value.get("tests")
    if (type(rows) is not list or len(rows) != 2
            or any(type(row) is not dict for row in rows)
            or {row.get("name") for row in rows} != {"cases::test_sum", "cases::test_values"}
            or any(row.get("status") != "passed" or row.get("reason") != "" for row in rows)):
        raise ValueError("driver test inventory or verdicts differ")


def main(argv):
    validate(json.loads(Path(argv[0]).read_text()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
