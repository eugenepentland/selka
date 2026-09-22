#!/usr/bin/env python3
"""Controlled audit timing, phase traces, and userspace sample collection."""
import argparse
import bisect
from collections import Counter, defaultdict
import hashlib
import json
import os
from pathlib import Path
import random
import re
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/svg-slowdown-20260921'
BASE = ROOT / '.tmp/full-svg-benchmark-20260921'
sys.path.insert(0, str(ROOT / 'experiments/full-svg-benchmark'))
from measure import command, percentile

ARMS = {
    'netlisp': (BASE / 'netlisp-llvm-fast', 'netlisp-llvm-fast'),
    'o3': (BASE / 'mylang-o3', 'mylang-o3'),
    'lto': (BASE / 'mylang-o3-lto', 'mylang-o3-lto'),
    'bounded': (BASE / 'mylang-o3-bounded', 'mylang-o3-bounded'),
    'part-pin-index': (WORK / 'algorithms/mylang-o3-part-pin', 'mylang-o3'),
    'host-control': (WORK / 'host/control', 'mylang-o3'),
    'host-scalar': (WORK / 'host/scalar-fast', 'mylang-o3'),
    'guest-lto-runtime-native': (WORK / 'lto/guest-lto-runtime-native', 'mylang-o3'),
    'guest-native-runtime-lto': (WORK / 'lto/guest-native-runtime-lto', 'mylang-o3'),
    'lto-guest-noinline': (WORK / 'lto/lto-guest-noinline', 'mylang-o3'),
    'lto-guest-avx2': (WORK / 'lto/lto-guest-avx2', 'mylang-o3'),
    'lto-partpin-avx2': (WORK / 'lto/lto-partpin-avx2', 'mylang-o3'),
    'part-pin-index-bounded': (WORK / 'algorithms/mylang-o3-part-pin-bounded', 'mylang-o3-bounded'),
}
REFS = json.loads((ROOT / 'experiments/full-svg-benchmark/qualification.json').read_text())['cases']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def execute(name, case='fixture', extra=(), preload=False, phase=False):
    path, base = ARMS[name]
    args, environment, _, _ = command(base, case, extra)
    args[3] = str(path)
    svg = WORK / 'audit.svg'
    issue = WORK / 'audit.issue'
    svg.write_bytes(b'')
    issue.write_bytes(b'')
    if base.startswith('netlisp'):
        args[6] = str(svg)
    else:
        environment.update(MYLANG_SCHEMATIC_OUTPUT=str(svg), MYLANG_SCHEMATIC_ISSUE=str(issue))
    if preload:
        environment.update(LD_PRELOAD=str(WORK / 'sample.so'),
                           MYLANG_AUDIT_SAMPLES=str(WORK / f'samples-{name}.txt'))
    start = time.perf_counter_ns()
    result = subprocess.run(args, env=environment, capture_output=True, timeout=60, cwd=ROOT)
    elapsed = (time.perf_counter_ns() - start) / 1e6
    assert result.returncode == 0, (name, result)
    assert result.stdout == (b'' if base.startswith('netlisp') else b'0\n'), (name, result)
    assert not issue.read_bytes(), (name, issue.read_bytes())
    assert phase or not result.stderr, (name, result.stderr)
    assert sha(svg) == REFS[case][base]['svg_sha256'], (name, case)
    return elapsed, result.stderr.decode()


def timed():
    qualification = {}
    for name, (path, base) in ARMS.items():
        for case in REFS:
            execute(name, case)
        if not base.startswith('netlisp'):
            execute(name, extra=('--gc-stress',))
        qualification[name] = {'binary': str(path), 'sha256': sha(path),
                               'three_inputs_exact_output': True,
                               'gc_stress': not base.startswith('netlisp')}
    rng = random.Random(20260922)
    rows = []
    for number in range(-3, 31):
        order = list(ARMS)
        rng.shuffle(order)
        values = {name: execute(name)[0] for name in order}
        if number >= 0:
            rows.append({'round': number, 'order': order, 'ms': values})
    medians = {name: statistics.median(row['ms'][name] for row in rows) for name in ARMS}
    comparisons = {}
    for name, base in [('part-pin-index', 'o3'), ('host-scalar', 'host-control'),
                       ('host-control', 'o3'), ('lto', 'o3'), ('bounded', 'o3'),
                       ('guest-lto-runtime-native', 'o3'),
                       ('guest-native-runtime-lto', 'o3'), ('lto-guest-noinline', 'lto'),
                       ('lto-guest-avx2', 'lto'), ('lto-partpin-avx2', 'lto'),
                       ('part-pin-index-bounded', 'bounded')]:
        boot = []
        for _ in range(4000):
            sample = rng.choices(rows, k=len(rows))
            boot.append(statistics.median(r['ms'][name] for r in sample) /
                        statistics.median(r['ms'][base] for r in sample))
        comparisons[f'{name}/{base}'] = {'ratio': medians[name] / medians[base],
                                         'paired_bootstrap_95': [percentile(boot, .025), percentile(boot, .975)]}
    evidence = {'scope': 'same full-svg fresh-process boundary; baseline and isolated probes interleaved',
                'cpu': 6, 'warmups': 3, 'rounds': 31, 'seed': 20260922,
                'qualification': qualification, 'median_ms': medians,
                'comparisons': comparisons, 'samples': rows}
    (OUT / 'measurements.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({'median_ms': medians, 'comparisons': comparisons}, indent=2), flush=True)


def phases():
    names = []
    for base in ('mylang-o3', 'mylang-o3-bounded'):
        name = base + '-phases'
        ARMS[name] = (WORK / 'phases' / name, base)
        names.append(name)
        ARMS[base + '-phase-control'] = (WORK / 'phases' / (base + '-control'), base)
    rows = []
    calibration = []
    rng = random.Random(20260922)
    for number in range(-3, 31):
        order = names.copy()
        rng.shuffle(order)
        for name in order:
            elapsed, stderr = execute(name, phase=True)
            base = ARMS[name][1]
            control_ms, _ = execute(base + '-phase-control')
            original_ms, _ = execute('bounded' if base.endswith('bounded') else 'o3')
            entries = []
            for line in stderr.splitlines():
                if line.startswith('PHASE '):
                    tokens = line.split()
                    entries.append({'name': tokens[1], **{k: int(v) for k, v in (t.split('=') for t in tokens[2:])}})
            assert len(entries) == 8, (name, stderr)
            if number >= 0:
                rows.append({'round': number, 'arm': name, 'wall_ms': elapsed, 'phases': entries})
                calibration.append({'round': number, 'arm': name, 'phase_ms': elapsed,
                                    'relinked_control_ms': control_ms, 'original_ms': original_ms})
    summaries = {}
    for name in names:
        values = defaultdict(list)
        facts = None
        for row in rows:
            if row['arm'] != name:
                continue
            inclusive = defaultdict(int)
            for phase in row['phases']:
                inclusive[phase['name']] += phase['ns']
            exclusive = {'parse': inclusive['sexpr::parse'], 'model': inclusive['schematic::build'],
                         'placement': inclusive['layout::build'], 'routing': inclusive['layout_routes::build'],
                         'svg_emission': inclusive['svg::render'] - inclusive['layout::build'] - inclusive['layout_routes::build'],
                         'guest_total': inclusive['main::main']}
            for phase, duration in exclusive.items():
                values[phase].append(duration / 1e6)
            facts = row['phases']
        summaries[name] = {'median_cpu_ms': {key: statistics.median(v) for key, v in values.items()},
                           'allocation_collection_step_counts': facts,
                           'median_wall_calibration_ms': {key: statistics.median(r[key] for r in calibration if r['arm'] == name)
                                                          for key in ('phase_ms', 'relinked_control_ms', 'original_ms')}}
    (OUT / 'phases.json').write_text(json.dumps({'method': 'low-frequency linker wrappers; unchanged per-function guest/runtime objects; system linker control; CPU clock; nested times subtracted; calibration sampled phase then control then original in each round', 'summary': summaries, 'samples': rows, 'calibration': calibration}, indent=2) + '\n')
    print(json.dumps(summaries, indent=2), flush=True)


def sampled(count):
    names = ['o3', 'lto', 'bounded', 'part-pin-index', 'lto-guest-avx2']
    for name in names:
        (WORK / f'samples-{name}.txt').write_text('')
    rng = random.Random(20260922)
    for _ in range(count):
        order = names.copy()
        rng.shuffle(order)
        for name in order:
            execute(name, preload=True)
    summaries = {}
    for name in names:
        path, base = ARMS[name]
        receipt_path = Path(str(path) + '.qbe-manifest.json')
        receipt = json.loads(receipt_path.read_text())
        friendly = {f['symbol']: f['name'] for f in receipt['functions']}
        symbols = []
        nm = subprocess.check_output(['nm', '-n', '-S', '--defined-only', str(path)], text=True)
        for line in nm.splitlines():
            fields = line.split()
            if len(fields) == 4 and fields[2] in ('t', 'T'):
                symbols.append((int(fields[0], 16), int(fields[1], 16), fields[3]))
        addresses = [entry[0] for entry in symbols]
        totals = Counter()
        pcs = Counter()
        outside = overflow = runs = samples = unmapped = 0
        for line in (WORK / f'samples-{name}.txt').read_text().splitlines():
            fields = line.split()
            if fields[0] == 'run':
                runs += 1
                samples += int(fields[3]); outside += int(fields[5]); overflow += int(fields[7])
            else:
                pc, hits = int(fields[0], 16), int(fields[1])
                pcs[pc] += hits
                index = bisect.bisect_right(addresses, pc) - 1
                if index < 0 or pc >= symbols[index][0] + symbols[index][1]:
                    unmapped += hits
                    continue
                totals[friendly.get(symbols[index][2], symbols[index][2])] += hits
        assert overflow == 0
        summaries[name] = {'runs': runs, 'samples': samples, 'outside_main_executable': outside,
                           'unmapped_inside': unmapped, 'overflow': overflow,
                           'functions': [{'name': function, 'samples': hits, 'percent_all_samples': hits * 100 / samples}
                                         for function, hits in totals.most_common()],
                           'top_pcs': [{'address': hex(pc), 'samples': hits} for pc, hits in pcs.most_common(25)]}
    (OUT / 'sampling.json').write_text(json.dumps({'method': 'LD_PRELOAD SIGPROF ITIMER_PROF userspace PC sampling, 500us requested, kernel tick limited; exact PCs, no stack attribution; CPU samples including outside executable; all SVG outputs verified; not hardware cycles', 'sampler_sha256': sha(WORK / 'sample.so'), 'summary': summaries}, indent=2) + '\n')
    print(json.dumps({name: {**{k:v for k,v in entry.items() if k not in ('functions','top_pcs')}, 'top_functions': entry['functions'][:8]} for name, entry in summaries.items()}, indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=('time', 'phases', 'sample'))
    parser.add_argument('--samples', type=int, default=200)
    args = parser.parse_args()
    {'time': timed, 'phases': phases, 'sample': lambda: sampled(args.samples)}[args.mode]()
