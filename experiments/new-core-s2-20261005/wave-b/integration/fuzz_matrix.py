#!/usr/bin/env python3
"""Run S2-X's complete strict 200-case matrix with at most two fuzz jobs."""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[4]
KINDS = ('s0', 's1', 'rc', 'rebinding', 'iteration', 'dict', 'text', 'number', 'functions')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kinds', default=','.join(KINDS))
    args = parser.parse_args()
    kinds = args.kinds.split(',')
    assert len(kinds) == len(set(kinds)) and set(kinds) <= set(KINDS)
    area = ROOT / 'experiments/new-core-s2-20261005/wave-b/integration/fuzz-200'
    cache = ROOT / '.mylang-cache/wave-b/s2-x/fuzz-200'
    area.mkdir(parents=True, exist_ok=True)
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()

    def run(kind):
        command = ['scripts/build-slot.sh', 'build', '--', 'python3',
                   'experiments/new-core-s2-20261005/wave-a/integration/fuzz_qualification.py',
                   '--kind', kind, '--cases', '200', '--seed', str(2201 + KINDS.index(kind)),
                   '--mylang', str(ROOT / '.mylang-cache/wave-b/baseline/mylang'), '--core', str(ROOT / 'zig-out/bin/mylang-core'),
                   '--evidence', str(area / kind), '--cache-root', str(cache / kind)]
        with (area / f'{kind}.txt').open('w') as log:
            log.write(f'source_commit={commit}\n$ {shlex.join(command)}\n')
            log.flush()
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            log.write(f'\nexit={result.returncode}\n')
        path = area / kind / 'summary.json'
        summary = json.loads(path.read_text()) if path.exists() else {}
        passed = result.returncode == 0 and summary.get('qualified') is True
        print(f'{kind}: {"PASS" if passed else "STOP"}; {summary.get("elapsed_seconds", "?")}s', flush=True)
        return kind, passed, summary

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(run, kinds))
    report = {'source_commit': commit, 'cases_per_kind': 200, 'maximum_parallel_jobs': 2,
              'kinds': {kind: {'passed': passed, 'summary': summary} for kind, passed, summary in results}}
    (area / 'matrix.json').write_text(json.dumps(report, indent=2) + '\n')
    if not all(passed for _, passed, _ in results):
        raise SystemExit('STOP: strict matrix qualification failed; inspect retained failures')


if __name__ == '__main__':
    main()
