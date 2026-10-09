#!/usr/bin/env python3
"""Run P1's sequential correctness checkpoint with fresh evidence and explicit exits."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

import ce

ROOT = ce.ROOT
AREA = ce.AREA / 'r3'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    args = parser.parse_args()
    evidence = AREA / args.tag
    evidence.mkdir(parents=True, exist_ok=False)
    report = {'source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'steps': [], 'pass': False}
    env = ce.env()
    env['ZIG_GLOBAL_CACHE_DIR'] = '/home/epentland/ai/canopy/.zig-global-cache'

    def run(name, command):
        log = evidence / (name + '.log')
        start = time.monotonic()
        print('start', name, flush=True)
        with log.open('w') as output:
            output.write(json.dumps(command) + '\n')
            output.flush()
            code = subprocess.run(command, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT).returncode
        report['steps'].append({'name': name, 'command': command, 'status': code,
                                'seconds': time.monotonic() - start, 'log': str(log.relative_to(ROOT))})
        (evidence / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
        print('done', name, code, flush=True)
        if code:
            raise RuntimeError(f'{name}: exit {code}; see {log}')

    run('full-gate', ['scripts/build-slot.sh', 'gate', 'zig', 'build', 'test', '--summary', 'all'])
    run('fmt-check', ['scripts/build-slot.sh', 'build', 'zig', 'build', 'fmt-check', '--summary', 'all'])
    # Prebuild Debug so qualification's exclusive cached-install limit measures its intended path.
    run('debug-install', ['scripts/build-slot.sh', 'build', 'zig', 'build', 'install', '--summary', 'all'])
    run('qualify', ['python3', 'experiments/new-core-s5-20261007/tools/qualify_merge.py', '--shards', '64',
                    '--compiler', 'zig-out/bin/mylang', '--install', 'install', '--evidence', str(evidence / (args.tag + '-qualify'))])
    compiler = ROOT / 'zig-out/bin/mylang'
    report['compiler_sha256'] = hashlib.sha256(compiler.read_bytes()).hexdigest()
    for count in (50, 200):
        run(f'fuzz{count}', ['python3', 'experiments/new-core-s5-20261007/tools/fuzz_matrix.py',
                            '--references', 'experiments/new-core-s5-20261007/references/fuzz-v1.json.gz',
                            '--new', str(compiler), '--cases', str(count), '--evidence', str(evidence / f'fuzz{count}'), '--jobs', '3', '--qualified-head', report['source']])
    report['pass'] = True
    (evidence / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
