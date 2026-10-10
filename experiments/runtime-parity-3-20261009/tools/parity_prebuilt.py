#!/usr/bin/env python3
"""Repeat full parity qualification and timing from a hashed completed build set."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import parity_locked as locked


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--build-manifest', type=Path, required=True)
    args, rest = parser.parse_known_args()
    manifest = json.loads(args.build_manifest.read_text())
    compiler = Path(rest[rest.index('--mylang') + 1])
    with locked.bp.OffTimingCpus():
        assert hashlib.sha256(compiler.read_bytes()).hexdigest() == manifest['compiler_sha256']
    def retained(job, tools, work):
        name = job['bench'] + '.' + job['arm']
        entry = manifest['entries'][name]
        assert hashlib.sha256(job['bin'].read_bytes()).hexdigest() == entry['binary_sha256'], name
        assert hashlib.sha256(job['src'].read_bytes()).hexdigest() == entry['source_sha256'], name
        assert job['flags'] == entry['flags'], name
        return {'cmd': ['retained-build', str(job['bin'])], 'ok': True, 'seconds': None,
                'stderr': '', 'reused_verified_build': True}
    locked.bp.build = retained
    sys.argv = [sys.argv[0], *rest]
    try:
        return locked.bp.main()
    finally:
        for guard in reversed(locked.held):
            guard.__exit__(None, None, None)


if __name__ == '__main__':
    raise SystemExit(main())
