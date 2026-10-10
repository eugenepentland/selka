#!/usr/bin/env python3
"""Run the unchanged Lox/EDA gates using owned caches and retain exact receipts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
TOOLS = ROOT / 'experiments/runtime-parity-3-20261009/tools'
sys.path.insert(0, str(TOOLS))
import ce


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    lock = Path(os.readlink('/proc/self/fd/9'))
    assert lock.name.startswith('build') and lock.suffix == '.lock'
    compiler = args.compiler.resolve()
    work = ROOT / '.mylang-cache/u2/external' / args.tag
    work.mkdir(parents=True, exist_ok=False)
    runtime = work / 'runtime'
    env = dict(os.environ, MYLANG_CORE_RUNTIME_CACHE=str(runtime))
    binary = ce.CACHE / 'bin' / args.tag / 'lox-plain'
    jobs = [
        ('lox-conformance', ce.LOX, [sys.executable, 'harness/lox_bench.py', 'conformance', '--binary', binary, '--engine', 'both', '--stress', '-j', '4']),
        ('lox-tests', ce.LOX_SRC, [compiler, 'test', '.', '--jobs', '3', '--force', '--max-steps=100000000', '--cache-dir', work / 'lox-tests']),
        ('eda-tests', ce.EDA_SRC, [compiler, 'test', 'src', '--jobs', '3', '--force', '--max-frames', '30000', '--max-steps', '4000000000', '--max-memory', '2G', '--cache-dir', work / 'eda-tests']),
    ]
    result = {'compiler': str(compiler), 'compiler_sha256': ce.digest(compiler), 'binary_sha256': ce.digest(binary), 'results': {}}
    for name, cwd, command in jobs:
        log = work / (name + '.log')
        started = time.monotonic()
        with log.open('x') as output:
            status = subprocess.run(list(map(str, command)), cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT).returncode
        text = log.read_text()
        summaries = [line for line in text.splitlines() if 'conformance engine=' in line or re.search(r'\d+ passed, \d+ cached, \d+ failed, \d+ skipped', line)]
        result['results'][name] = {'command': list(map(str, command)), 'cwd': str(cwd), 'status': status,
            'seconds': time.monotonic() - started, 'summary': summaries,
            'raw_log': str(log.relative_to(ROOT)), 'log_sha256': hashlib.sha256(log.read_bytes()).hexdigest()}
        args.out.write_text(json.dumps(result, indent=1) + '\n')
        print(name, status, summaries, flush=True)
        if status:
            raise RuntimeError(f'{name} failed: {log}')
    assert result['results']['lox-conformance']['summary'] == [
        'conformance engine=vm gc=normal: 246/246 passed',
        'conformance engine=vm gc=gc-stress: 246/246 passed',
        'conformance engine=tree gc=normal: 241/241 passed',
        'conformance engine=tree gc=gc-stress: 241/241 passed']
    for name, count in [('lox-tests', 65), ('eda-tests', 310)]:
        assert result['results'][name]['summary'][-1] == f'{count} passed, 0 cached, 0 failed, 0 skipped'
    result['qualified'] = True
    args.out.write_text(json.dumps(result, indent=1) + '\n')


if __name__ == '__main__':
    main()
