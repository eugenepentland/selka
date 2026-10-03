#!/usr/bin/env python3
"""Validate completed compiler measurements and optionally seal their evidence."""
import argparse
import json
from pathlib import Path
import sys

# Read-only checks must not create bytecode caches beside guarded helpers.
sys.dont_write_bytecode = True

from archive import create, verify
from validation import require, validate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--check", type=Path, metavar="WORK", help="read-only receipt and identity validation")
    modes.add_argument("--archive", type=Path, metavar="DEST", help="create a new archive after validation")
    modes.add_argument("--verify", type=Path, metavar="ARCHIVE", help="read-only relocated object verification")
    parser.add_argument("--work", type=Path, help="work for --archive")
    parser.add_argument("--extra", type=Path, action="append", default=[], help="retain explicit external file/directory evidence")
    parser.add_argument("--originals", action="store_true", help="--verify also checks absolute original path identities")
    parser.add_argument("--expected-manifest", help="--verify require this independently retained manifest SHA")
    args = parser.parse_args()
    require(not args.originals or args.verify is not None, "--originals requires --verify")
    require(args.expected_manifest is None or args.verify is not None, "--expected-manifest requires --verify")
    require(args.verify is None or (not args.extra and args.work is None), "--verify takes no evidence input roots")
    if args.verify is not None:
        result = verify(args.verify, args.originals, args.expected_manifest)
    else:
        work = args.check if args.check is not None else args.work
        require(work is not None, "--archive requires --work")
        report, guards = validate(work)
        if args.check is not None:
            require(not args.extra and args.work is None, "--check takes only its work path")
            result = report
        else:
            here = Path(__file__).resolve().parent
            tools = list(here.glob("*.py")) + [here / "README.md"]
            result = create(work, guards, args.extra, report, args.archive, tools)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
