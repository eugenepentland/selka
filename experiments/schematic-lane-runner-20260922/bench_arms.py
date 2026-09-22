#!/usr/bin/env python3
"""Interleaved fresh-process timing of schematic guest binaries and of the whole
`schematic-svg` runner, with every run's SVG hashed.

usage: bench_arms.py --arms arms.json --out results.json [--rounds 21] [--warmups 3] [--cpu 2]

arms.json: {"name": {"kind": "guest"|"runner"|"native", "binary": "/abs/path",
                     "args": ["--timeout=60", ...],          # guest arguments, or runner flags before --project
                     "declared": "io::a,io::b",              # guest only (provider registration)
                     "project": "/abs/src/schematic/guest"}} # runner only

A `guest` arm is a built guest executable invoked exactly as the host invokes it:
the three documents and the output path travel in the environment. A `runner` arm
is the installed `schematic-svg` executable, which checks and builds its guest
(warm object cache) before rendering, and writes the SVG to stdout. Every arm on
one case must produce the same SVG bytes as the reference arm (the first key).
"""
import argparse, hashlib, json, os, random, statistics, subprocess, time
from pathlib import Path

ROOT = Path(os.environ.get('AUDIT_ROOT', '/home/epentland/ai/canopy/mylang'))
BASE = Path(os.environ.get('AUDIT_BENCH', '/home/epentland/ai/canopy/mylang/.tmp/full-svg-benchmark-20260921'))
DOCS = ('lib/modules/straps-synth-lmx2595.sexp', 'lib/pinouts/lmx2595rhar.sexp', 'lib/interfaces/spi.sexp')
WORK = Path(os.environ.get('BENCH_WORK', str(ROOT / '.tmp/perf-audit-20260922/bench')))
WORK.mkdir(parents=True, exist_ok=True)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def clean_env():
    env = dict(os.environ)
    for key in list(env):
        if key.startswith('MYLANG_') or key in ('LD_PRELOAD', 'GOGC', 'GOMEMLIMIT', 'GODEBUG', 'GOMAXPROCS'):
            del env[key]
    env['MYLANG_MEMORY_LIMIT'] = '268435456'
    return env


def invoke(name, arm, case, cpu):
    project = BASE / 'projects' / case
    docs = [str(project / p) for p in DOCS]
    env = clean_env()
    command = ['taskset', '-c', str(cpu), arm['binary']]
    output = WORK / f'{name}.svg'
    if arm['kind'] == 'runner':
        command += [*arm.get('args', []), '--project', arm['project'], *docs]
        started = time.perf_counter_ns()
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, timeout=600)
        elapsed = (time.perf_counter_ns() - started) / 1e6
        if result.returncode != 0 or not result.stdout:
            raise AssertionError((name, case, result.returncode, result.stderr[:400]))
        output.write_bytes(result.stdout)
        return elapsed, sha(result.stdout)
    issue = WORK / f'{name}.issue'
    output.write_bytes(b''); issue.write_bytes(b'')
    if arm['kind'] == 'native':
        command += [*docs, str(output)]
    else:
        env.update(MYLANG_SCHEMATIC_DECLARED=arm['declared'], MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
        env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': p for i, p in enumerate(docs)})
        command += ['--print-result', *arm.get('args', [])]
    started = time.perf_counter_ns()
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, timeout=600)
    elapsed = (time.perf_counter_ns() - started) / 1e6
    expected = b'' if arm['kind'] == 'native' else b'0\n'
    if result.returncode != 0 or result.stdout != expected or issue.read_bytes():
        raise AssertionError((name, case, result.returncode, result.stdout[:200], result.stderr[:400], issue.read_bytes()[:200]))
    return elapsed, sha(output.read_bytes())


def percentile(values, fraction):
    values = sorted(values)
    point = (len(values) - 1) * fraction
    lower = int(point); upper = min(lower + 1, len(values) - 1)
    return values[lower] + (values[upper] - values[lower]) * (point - lower)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--arms', required=True); ap.add_argument('--out', required=True)
    ap.add_argument('--rounds', type=int, default=21); ap.add_argument('--warmups', type=int, default=3)
    ap.add_argument('--cpu', type=int, default=2); ap.add_argument('--cases', default='fixture')
    ap.add_argument('--seed', type=int, default=20260922); ap.add_argument('--reference', default=None)
    a = ap.parse_args()
    arms = json.loads(Path(a.arms).read_text())
    cases = a.cases.split(',')
    reference = a.reference or next(iter(arms))
    hashes = {}
    for case in cases:
        for name, arm in arms.items():
            _, digest = invoke(name, arm, case, a.cpu)
            hashes.setdefault(case, {})[name] = digest
        for name in arms:
            if hashes[case][name] != hashes[case][reference]:
                raise SystemExit(f'output mismatch: {name} on {case}: {hashes[case][name]} != {hashes[case][reference]}')
    rng = random.Random(a.seed)
    rows = []
    for number in range(-a.warmups, a.rounds):
        jobs = [(name, case) for name in arms for case in cases]
        rng.shuffle(jobs)
        values = {case: {} for case in cases}
        for name, case in jobs:
            elapsed, digest = invoke(name, arms[name], case, a.cpu)
            assert digest == hashes[case][reference], (name, case, digest)
            values[case][name] = elapsed
        if number >= 0:
            rows.append(values)
        print(f'round {number} done', flush=True)
    summary = {}
    for case in cases:
        medians = {name: statistics.median(r[case][name] for r in rows) for name in arms}
        ratios = {}
        for name in arms:
            if name == reference:
                continue
            boot = []
            for _ in range(2000):
                sample = rng.choices(rows, k=len(rows))
                boot.append(statistics.median(r[case][name] for r in sample) / statistics.median(r[case][reference] for r in sample))
            ratios[name] = {'ratio': medians[name] / medians[reference], 'ci95': [percentile(boot, .025), percentile(boot, .975)]}
        summary[case] = {'median_ms': medians,
                         'p10_p90': {n: [percentile([r[case][n] for r in rows], .1), percentile([r[case][n] for r in rows], .9)] for n in arms},
                         'min_ms': {n: min(r[case][n] for r in rows) for n in arms},
                         f'ratio_to_{reference}': ratios}
    Path(a.out).write_text(json.dumps({'cpu': a.cpu, 'rounds': a.rounds, 'warmups': a.warmups, 'seed': a.seed,
                                       'reference': reference, 'arms': arms, 'hashes': hashes,
                                       'summary': summary, 'rows': rows}, indent=1) + '\n')
    for case in cases:
        print(f'== {case}')
        for name in arms:
            m = summary[case]['median_ms'][name]
            band = summary[case]['p10_p90'][name]
            r = summary[case][f'ratio_to_{reference}'].get(name, {'ratio': 1.0, 'ci95': [1, 1]})
            print(f"  {name:26s} {m:8.3f} ms  [p10 {band[0]:7.3f} p90 {band[1]:7.3f}]  x{r['ratio']:.3f} [{r['ci95'][0]:.3f},{r['ci95'][1]:.3f}]")


if __name__ == '__main__':
    main()
