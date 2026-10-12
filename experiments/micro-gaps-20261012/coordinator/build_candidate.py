#!/usr/bin/env python3
"""Build unchanged checked-owned fixtures and derive paired C0/candidate specs.

Each guest build owns one shared admission lease. Historical inputs and results
are read only; every output lives in the new micro-gaps experiment.
"""
import argparse
import concurrent.futures
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
OLD = ROOT / 'experiments/micro-ownership-20261012'
NEW = ROOT / 'experiments/micro-gaps-20261012'
WORK = ROOT / '.tmp/micro-gaps/coordinator'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('compiler', type=Path)
    parser.add_argument('--jobs', type=int, default=3)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    compiler_hash = sha(compiler)
    assert os.environ.get('MYLANG_SLOT_DIR'), 'source the shared development environment'
    assert not (NEW / 'coordinator/builds.json').exists(), 'preserve existing run'
    specs = []
    jobs = {}
    for suite in ('parity', 'expanded'):
        for path in sorted((OLD / ('specs-' + suite)).glob('*.json')):
            spec = json.loads(path.read_text())
            specs.append((suite, path.name, spec))
            for kind, field in (('runtime', 'arms'), ('counted', 'counted')):
                old = spec[field]['mylang-zero-rc']
                key = (suite, spec.get('group', spec['case']), kind)
                if key in jobs:
                    assert jobs[key]['old']['binary'] == old['binary']
                else:
                    jobs[key] = {'old': old, 'suite': suite, 'kind': kind,
                                 'name': '-'.join(key)}
    assert len(specs) == 91 and len(jobs) == 30

    def build(job):
        old = job['old']
        assert sha(old['binary']) == old['sha256']
        source = Path(old['source'])
        source_hash = sha(source)
        if 'source_sha256' in old:
            assert old['source_sha256'] == source_hash
        out = WORK / 'bin' / job['name']
        cache = WORK / 'cache' / job['name']
        log = NEW / 'coordinator/build-logs' / (job['name'] + '.log')
        out.parent.mkdir(parents=True, exist_ok=True)
        log.parent.mkdir(parents=True, exist_ok=True)
        command = [str(compiler), 'build', str(source), '--release',
                   '--experimental-zero-rc', '-o', str(out), '--cache-dir', str(cache)]
        if job['kind'] == 'counted':
            command += ['--counters']
        if job['suite'] == 'expanded':
            command += ['--link', str(ROOT / 'benchmarks/runtime/ports/native_clock.c')]
        start = time.monotonic()
        env = dict(os.environ, MYLANG_JOBS='4')
        with log.open('w') as stream:
            result = subprocess.run([str(ROOT / 'scripts/build-slot.sh'), 'build', *command],
                                    cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
        assert sha(compiler) == compiler_hash and sha(source) == source_hash
        entry = {**old, 'arm': 'mylang-zero-rc', 'binary': str(out),
                 'sha256': sha(out) if result.returncode == 0 else None,
                 'source_sha256': source_hash, 'command': command, 'flags': command[3:],
                 'diagnostic': str(log), 'returncode': result.returncode,
                 'status': 'ok' if result.returncode == 0 else 'build_failed',
                 'elapsed_with_admission_seconds': time.monotonic() - start}
        if result.returncode == 0:
            out.chmod(0o555)
        print(job['name'], entry['status'], flush=True)
        return entry

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = dict(zip(jobs, pool.map(build, jobs.values())))
    save(NEW / 'coordinator/builds.json', {
        'compiler': str(compiler), 'compiler_sha256': compiler_hash,
        'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'entries': list(results.values()),
        'compile_measurement_note': 'Elapsed includes admission; not a compiler throughput comparison.'})
    assert all(r['status'] == 'ok' for r in results.values()), 'failed builds retained'
    for suite, name, old in specs:
        spec = copy.deepcopy(old)
        spec['baseline_cell'] = old['cell']
        spec['cell'] = 'micro-gaps/' + old['cell']
        for kind, field in (('runtime', 'arms'), ('counted', 'counted')):
            baseline = {**old[field]['mylang-zero-rc'], 'arm': 'baseline-zero-rc'}
            candidate = results[(suite, old.get('group', old['case']), kind)]
            spec[field] = {'baseline-zero-rc': baseline, 'mylang-zero-rc': candidate}
        spec['files'] += [str(NEW / 'coordinator/builds.json'), str(compiler), __file__]
        save(NEW / ('specs-' + suite) / name, spec)
    print('READY: 30 binaries; 91 paired cells', flush=True)


if __name__ == '__main__':
    main()
