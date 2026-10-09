#!/usr/bin/env python3
"""R10 tax for CE-X's EDA, both Lox engines and all mylang parity arms.

Identical inputs, golden outputs, CPU 10 flock, interleaved paired samples.
The three batches use alignments 4, 5, 6. EDA has 10 measured samples per
batch, Lox 3 and parity 9, as CE-X; all builds precede the timing lock.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import random
import statistics
import subprocess
import time

import ce

ROOT = ce.ROOT
AREA = ce.AREA / 'r3'
BIN = ROOT / '.mylang-cache/concurrency-p1/tax-corpora'


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


EDA = module('eda_runtime', ROOT / 'experiments/bench-newcore-20261008/eda/runtime.py')
PARITY = module('parity_registry', ROOT / 'bench/parity/bench_parity.py')


def cells(group):
    if group == 'eda':
        return {c['id']: {'program': 'eda', 'source': ce.EDA_SRC / 'src/main.my',
                         'cwd': ce.EDA_SRC, 'case': c} for c in
                json.loads((ce.EDA / 'golden/manifest.json').read_text())['cases']}
    if group == 'lox':
        sizes = json.loads((ce.LOX / 'bench/sizes.json').read_text())
        return {f'{name}/{engine}': {'program': 'lox', 'source': ce.LOX_SRC / 'main.my',
                 'cwd': ce.LOX_SRC, 'args': [f'--engine={engine}', str(ce.lox_script(name, size[engine]))],
                 'expected': (ce.LOX / f'bench/expected/{name}.{engine}.out').read_bytes()}
                for name, size in sizes.items() if not name.startswith('_') for engine in ('tree', 'vm')}
    result = {}
    for case in PARITY.discover([]):
        for arm in PARITY.arms_for(case['ports']):
            if arm['lang'] != 'my':
                continue
            name = f"{case['group']}/{case['name']}/{arm['arm']}"
            result[name] = {'program': name.replace('/', '-'), 'source': arm['src'],
                            'cwd': ROOT, 'args': [], 'expected': case['expected']}
    return result


def build_one(compiler, tag, layout, cell):
    directory = BIN / tag / str(layout)
    directory.mkdir(parents=True, exist_ok=True)
    command = [str(compiler), 'build', str(cell['source']), '--release', '-o', str(directory / cell['program']),
               '--cache-dir', str(directory / 'cache')]
    status, stdout, stderr = ce.run(command, cwd=cell['cwd'], slot=True,
                                    extra_env={'MYLANG_CORE_LAYOUT': str(layout)})
    log = AREA / 'logs' / f'tax-corpora-{tag}-{layout}' / (cell['program'] + '.log')
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(json.dumps(command) + '\n' + stdout.decode() + stderr.decode() + f'\nexit={status}\n')
    if status != 0:
        raise RuntimeError(f'build failed: {log}')
    print('built', tag, layout, cell['program'], flush=True)


def sample(group, tag, layout, key, cell):
    binary = BIN / tag / str(layout) / cell['program']
    load = os.getloadavg()
    if group == 'eda':
        output = BIN / 'eda-output' / tag / key
        result = EDA.run_case(str(binary), cell['case'], ce.EDA / 'golden', output, 10)
        problems = EDA.verify(cell['case'], ce.EDA / 'golden', output)
        if result['code'] != 0 or problems:
            raise RuntimeError(f'{tag}/{key}: {result}, {problems}')
    else:
        start = time.monotonic_ns()
        run = subprocess.run([str(binary), *cell['args']], cwd=cell['cwd'], capture_output=True, timeout=900)
        elapsed = time.monotonic_ns() - start
        if run.returncode != 0 or run.stdout != cell['expected'] or run.stderr:
            raise RuntimeError(f'{tag}/{key}: exit={run.returncode} stdout={run.stdout[:500]!r} stderr={run.stderr[:500]!r}')
        result = {'wall_s': elapsed / 1e9, 'code': 0, 'stdout_sha256': hashlib.sha256(run.stdout).hexdigest()}
    return {**result, 'load_before': load, 'load_after': os.getloadavg()}


def measure(group, tags, output):
    selected = cells(group)
    rounds = {'eda': 10, 'lox': 3, 'parity': 9}[group]
    report = {'source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True, cwd=ROOT).strip(),
              'corpus': group, 'tags': tags, 'cpu': 10, 'layouts': [4, 5, 6], 'rounds': rounds,
              'load_start': os.getloadavg(), 'rows': {}, 'valid': False, 'binary_sha256': {}}
    for tag in tags:
        report['binary_sha256'][tag] = {f"{layout}/{cell['program']}": hashlib.sha256(
            (BIN / tag / str(layout) / cell['program']).read_bytes()).hexdigest()
            for layout in (4, 5, 6) for cell in selected.values()}
    output.parent.mkdir(parents=True, exist_ok=True)
    rng = random.Random(5171)
    with open('/run/user/1000/mylang-slots/cpu10.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        os.sched_setaffinity(0, {10})
        for layout in (4, 5, 6):
            for key, cell in selected.items():
                warmups = {tag: [sample(group, tag, layout, key, cell) for _ in range(2 if group == 'parity' else 1)] for tag in tags}
                runs = {tag: [] for tag in tags}
                for _ in range(rounds):
                    order = list(tags)
                    rng.shuffle(order)
                    for tag in order:
                        runs[tag].append(sample(group, tag, layout, key, cell))
                medians = {tag: statistics.median(r['wall_s'] for r in runs[tag]) for tag in tags}
                row = report['rows'].setdefault(key, {'batches': []})
                row['batches'].append({'layout': layout, 'warmups': warmups, 'runs': runs, 'medians': medians})
                output.write_text(json.dumps(report, separators=(',', ':')) + '\n')
                print(group, layout, key, {tag: medians[tag] / medians['base'] for tag in tags[1:]}, flush=True)
    report['load_end'] = os.getloadavg()
    report['valid'] = True
    report['summary'] = {}
    for tag in tags[1:]:
        ratios = {key: statistics.median(batch['medians'][tag] / batch['medians']['base'] for batch in row['batches'])
                  for key, row in report['rows'].items()}
        gm = math.exp(statistics.mean(math.log(r) for r in ratios.values()))
        failures = {key: ratio for key, ratio in ratios.items() if ratio > 1.03}
        report['summary'][tag] = {'geomean': gm, 'rows_over_1_03': failures, 'ratios': ratios,
                                  'pass': gm <= 1.010 and not failures}
        print(group, tag, 'geomean', gm, 'over 1.03', failures, flush=True)
    output.write_text(json.dumps(report, separators=(',', ':')) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('build', 'measure'))
    parser.add_argument('group', choices=('eda', 'lox', 'parity'))
    parser.add_argument('--compiler', type=Path)
    parser.add_argument('--tag')
    parser.add_argument('--tags', default='base,B')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.action == 'build':
        assert args.compiler and args.tag
        programs = {cell['program']: cell for cell in cells(args.group).values()}
        jobs = [(layout, cell) for layout in (4, 5, 6) for cell in programs.values()]
        with ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(lambda job: build_one(args.compiler, args.tag, *job), jobs))
    else:
        measure(args.group, args.tags.split(','), args.output or AREA / 'results' / f'tax-{args.group}.json')


if __name__ == '__main__':
    main()
