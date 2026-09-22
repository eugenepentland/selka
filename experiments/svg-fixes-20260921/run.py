#!/usr/bin/env python3
"""Build, qualify and compare production SVG fixes with retained audit binaries.

Compilation and verification are outside the timed fresh-process boundary.
The EDA NetLisp executable calls its real functional SVG implementation; its
algorithm, validation, memory policy and output differ from mylang's.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/svg-fixes-20260921'
BASE = ROOT / '.tmp/full-svg-benchmark-20260921'
CPU = 6
SEED = 20260923
CASES = ('fixture', 'changed-net', 'changed-value')
NEW = {
    'after-o3': (),
    'after-lto': ('--lto',),
    'after-bounded': ('--step-accounting',),
    'after-lto-bounded': ('--lto', '--step-accounting'),
}
ARMS = {
    'netlisp': BASE / 'netlisp-llvm-fast',
    'before-o3': BASE / 'mylang-o3',
    'before-lto': BASE / 'mylang-o3-lto',
    'before-bounded': BASE / 'mylang-o3-bounded',
    **{name: WORK / name for name in NEW},
}
REFS = json.loads((ROOT / 'experiments/full-svg-benchmark/qualification.json').read_text())['cases']
DOCS = ('lib/modules/straps-synth-lmx2595.sexp',
        'lib/pinouts/lmx2595rhar.sexp', 'lib/interfaces/spi.sexp')
sys.path.insert(0, str(ROOT / 'tests'))
from schematic_layout import geometry


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def environment():
    env = dict(os.environ)
    # Freeze build policy and dependencies without changing machine settings.
    for key in list(env):
        if key.startswith('MYLANG_QBE_LLVM_') or key in (
                'NETLISP_LIB_DIR', 'NETLISP_STDLIB_DIR', 'LD_PRELOAD'):
            del env[key]
    return env


def build():
    WORK.mkdir(parents=True, exist_ok=True)
    records = {}
    for name, flags in NEW.items():
        command = [str(ROOT / 'zig-out/bin/mylang'), 'build',
                   'src/schematic/guest/main.my', '--project', '--provider',
                   'src/schematic/native_schematic.c', '--backend', 'llvm',
                   '--llvm-opt', '3', *flags, '--keep-symbols', '--cache-dir',
                   str(WORK / 'cache'), '--report', '-o', str(ARMS[name])]
        started = time.perf_counter()
        result = subprocess.run(command, env=environment(), cwd=ROOT,
                                capture_output=True, timeout=1200)
        (OUT / f'{name}-build.stdout').write_bytes(result.stdout)
        (OUT / f'{name}-build.stderr').write_bytes(result.stderr)
        assert result.returncode == 0, (name, result.stderr.decode(errors='replace'))
        records[name] = {'command': command, 'elapsed_seconds': time.perf_counter() - started,
                         'binary_sha256': sha(ARMS[name]),
                         'receipt': json.loads(Path(str(ARMS[name]) + '.qbe-manifest.json').read_text())}
        print(f'Built {name}', flush=True)
    source_paths = [*sorted((ROOT / 'src/schematic/guest').glob('*.my')),
                    ROOT / 'src/qbe_host_runtime.c', ROOT / 'src/schematic/native_schematic.c',
                    *sorted((ROOT / 'experiments/llvm-backend').glob('*.py')),
                    *sorted((ROOT / 'src').glob('qbe_build*.zig'))]
    evidence = {'compiler_sha256': sha(ROOT / 'zig-out/bin/mylang'),
                'sources': {str(p.relative_to(ROOT)): sha(p) for p in source_paths},
                'builds': records}
    (OUT / 'builds.json').write_text(json.dumps(evidence, indent=2) + '\n')


def execute(name, case, extra=(), validate=True):
    project = BASE / 'projects' / case
    output = WORK / 'measured.svg'
    issue = WORK / 'measured.issue'
    output.write_bytes(b'')
    issue.write_bytes(b'')
    env = environment()
    command = ['taskset', '-c', str(CPU), str(ARMS[name])]
    if name == 'netlisp':
        command += [str(project), 'straps-synth-lmx2595', str(output), *extra]
    else:
        env.update(MYLANG_SCHEMATIC_DECLARED='io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue',
                   MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
        env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': str(project / path) for i, path in enumerate(DOCS)})
        command += ['--print-result']
        if name.endswith('bounded') and not any(arg.startswith('--max-steps=') for arg in extra):
            command += ['--max-steps=100000000']
        command += list(extra)
    started = time.perf_counter_ns()
    result = subprocess.run(command, env=env, cwd=ROOT, capture_output=True, timeout=90)
    elapsed_ms = (time.perf_counter_ns() - started) / 1e6
    if validate:
        assert (result.returncode, result.stdout, result.stderr, issue.read_bytes()) == (
            0, b'' if name == 'netlisp' else b'0\n', b'', b''), (name, case, result, issue.read_bytes())
        reference = 'netlisp-llvm-fast' if name == 'netlisp' else 'mylang-o3'
        assert sha(output) == REFS[case][reference]['svg_sha256'], (name, case, sha(output))
    return elapsed_ms, result, output.read_bytes()


def qualify():
    WORK.mkdir(parents=True, exist_ok=True)
    evidence = {}
    for name in ARMS:
        cases = {}
        for case in CASES:
            _, _, svg = execute(name, case)
            if name in NEW:
                geometry(ET.fromstring(svg))
                execute(name, case, ('--gc-stress',))
            cases[case] = {'svg_sha256': hashlib.sha256(svg).hexdigest(),
                           'svg_bytes': len(svg), 'matches_retained_reference': True,
                           'gc_stress_checked': name in NEW}
        evidence[name] = {'binary': str(ARMS[name].relative_to(ROOT)),
                          'binary_sha256': sha(ARMS[name]), 'cases': cases}
    for name in ('after-bounded', 'after-lto-bounded'):
        limits = {}
        for option, code in [('--max-steps=1', b'R_STEP_LIMIT'), ('--max-frames=1', b'R_FRAME_LIMIT')]:
            _, result, _ = execute(name, 'fixture', (option,), validate=False)
            assert result.returncode != 0 and code in result.stderr, (name, option, result)
            limits[option] = {'exit_code': result.returncode, 'stderr': result.stderr.decode()}
        evidence[name]['budget_rejection'] = limits
    (OUT / 'qualification.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print('All binaries match retained SVGs; new builds pass geometry, GC stress and accounting-limit checks.', flush=True)


def percentile(values, fraction):
    values = sorted(values)
    point = (len(values) - 1) * fraction
    lower = int(point)
    upper = min(lower + 1, len(values) - 1)
    return values[lower] + (values[upper] - values[lower]) * (point - lower)


def measure():
    qualified = json.loads((OUT / 'qualification.json').read_text())
    for name, path in ARMS.items():
        assert sha(path) == qualified[name]['binary_sha256'], f'{name} changed after qualification'
    rng = random.Random(SEED)
    rows = []
    for number in range(-3, 31):
        jobs = [(name, case) for name in ARMS for case in CASES]
        rng.shuffle(jobs)
        values = {case: {} for case in CASES}
        for name, case in jobs:
            values[case][name] = execute(name, case)[0]
        if number >= 0:
            rows.append({'round': number, 'order': jobs, 'ms': values})
    summaries = {}
    pairs = [(name, 'netlisp') for name in ARMS if name != 'netlisp']
    pairs += [(f'after-{mode}', f'before-{mode}') for mode in ('o3', 'lto', 'bounded')]
    pairs += [('after-lto-bounded', 'before-bounded')]
    for case in CASES:
        medians = {name: statistics.median(r['ms'][case][name] for r in rows) for name in ARMS}
        comparisons = {}
        for numerator, denominator in pairs:
            bootstrap = []
            for _ in range(4000):
                sample = rng.choices(rows, k=len(rows))
                bootstrap.append(statistics.median(r['ms'][case][numerator] for r in sample) /
                                 statistics.median(r['ms'][case][denominator] for r in sample))
            comparisons[f'{numerator}/{denominator}'] = {
                'ratio': medians[numerator] / medians[denominator],
                'paired_bootstrap_95': [percentile(bootstrap, .025), percentile(bootstrap, .975)]}
        summaries[case] = {'median_ms': medians, 'comparisons': comparisons}
    evidence = {'cpu': CPU, 'seed': SEED, 'rounds': 31, 'warmup_rounds': 3,
                'scope': 'fresh process: input read, model, placement, routing, SVG private-file output, shutdown; excludes compilation and verification',
                'all_timed_outputs_hash_checked': True, 'timed_runs': len(rows) * len(ARMS) * len(CASES),
                'binary_sha256': {name: sha(path) for name, path in ARMS.items()},
                'summary': summaries, 'samples': rows}
    (OUT / 'measurements.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(summaries, indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('build', 'qualify', 'measure'))
    args = parser.parse_args()
    {'build': build, 'qualify': qualify, 'measure': measure}[args.action]()
