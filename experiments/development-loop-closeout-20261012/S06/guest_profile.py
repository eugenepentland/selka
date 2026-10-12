#!/usr/bin/env python3
"""Capture every mandatory language action without inferring unsupported phases."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_admission import admission

SUITES = ('lang', 'value_semantics', 'ported')
MODES = {'optimized-debug': (), 'unoptimized': ('--unoptimized',),
         'release-facts-leaks': ('--release', '--verify-facts')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--tiers', nargs='+', choices=('cold', 'warm', 'force', 'no-cache'), default=['cold', 'warm', 'force'])
    parser.add_argument('--admission', choices=('build', 'timing'), default='build')
    args = parser.parse_args()
    if len(set(args.tiers)) != len(args.tiers):
        parser.error('tiers must be unique')
    if 'cold' in args.tiers and args.tiers[0] != 'cold':
        parser.error('cold must be the first tier')
    if 'warm' in args.tiers and 'cold' not in args.tiers:
        parser.error('warm requires a preceding cold tier in the private cache')
    if args.jobs < 1:
        parser.error('jobs must be positive')
    output = args.output.resolve()
    if output.exists():
        parser.error('output must be a new private directory')
    output.mkdir(parents=True)
    compiler, zig = args.compiler.resolve(), args.zig.resolve()
    rows = []
    manifest = {'version': 1, 'compiler': str(compiler), 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
                'zig': str(zig), 'zig_sha256': hashlib.sha256(zig.read_bytes()).hexdigest(),
                'source_sha': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'jobs': args.jobs, 'cpu_affinity': sorted(os.sched_getaffinity(0)),
                'qualification': 'operational only' if args.admission == 'build' else 'isolated observations; no p95 claim',
                'cache_scope': 'cold resets only private guest cache; shared Zig global cache remains available',
                'actions_expected': 9, 'phase_support': {name: None for name in ('discovery', 'startup', 'frontend', 'native_compile', 'native_link', 'execution')}, 'rows': rows}
    with admission(args.admission):
        for suite in SUITES:
            for mode, flags in MODES.items():
                inventory = None
                for tier in args.tiers:
                    cache = output / 'guest-cache' / f'{suite}-{mode}'
                    command = [str(compiler), 'test', str(ROOT / 'tests' / suite), *flags, '--json', '--jobs', str(args.jobs), '--zig', str(zig), '--cache-dir', str(cache)]
                    if tier == 'force':
                        command.append('--force')
                    if tier == 'no-cache':
                        command.append('--no-cache')
                    environment = dict(os.environ)
                    environment.pop('MYL_CORE_LEAKCHECK', None)
                    if mode == 'release-facts-leaks':
                        environment['MYL_CORE_LEAKCHECK'] = '1'
                    start = time.monotonic_ns()
                    result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, timeout=600)
                    stem = output / f'{suite}-{mode}-{tier}'
                    stem.with_suffix('.stdout').write_bytes(result.stdout)
                    stem.with_suffix('.stderr').write_bytes(result.stderr)
                    record = json.loads(result.stdout)
                    names = [test['name'] for test in record['tests']]
                    row = {'suite': suite, 'mode': mode, 'tier': tier, 'command': command, 'leakcheck': environment.get('MYL_CORE_LEAKCHECK'), 'status': result.returncode,
                           'selected': len(names), 'counts': {key: record.get(key) for key in ('passed', 'cached', 'failed', 'skipped', 'unsupported')},
                           'elapsed_ns_including_startup_collection_reporting': time.monotonic_ns() - start}
                    rows.append(row)
                    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
                    print(json.dumps(row), flush=True)
                    if result.returncode or not names or record.get('failed') or record.get('unsupported'):
                        raise RuntimeError('mandatory action did not pass')
                    if inventory is not None and inventory != names:
                        raise RuntimeError('tier changed selected test inventory')
                    inventory = names
                    if (tier in ('force', 'no-cache') or mode == 'release-facts-leaks') and record.get('cached'):
                        raise RuntimeError('required fresh action replayed a test')


if __name__ == '__main__':
    main()
