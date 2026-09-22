#!/usr/bin/env python3
"""Interleaved fresh-process timing of schematic SVG arms (mylang guest builds and native ports).

usage: bench_svg.py --arms arms.json --out results.json [--rounds 31] [--warmups 3] [--cpu 6] [--cases fixture,changed-net,changed-value]

arms.json: {"name": {"binary": "/abs/path", "kind": "mylang"|"native", "bounded": bool, "declared": "io::a,io::b"}}
Every run's SVG is hashed and must equal the first arm's hash for that case (the reference arm is the first key).
"""
import argparse, hashlib, json, os, random, statistics, subprocess, time
from pathlib import Path

ROOT = Path(os.environ.get('AUDIT_ROOT', '/home/epentland/ai/canopy/mylang'))
BASE = Path(os.environ.get('AUDIT_BENCH', '/home/epentland/ai/canopy/mylang/.tmp/full-svg-benchmark-20260921'))
DOCS = ('lib/modules/straps-synth-lmx2595.sexp', 'lib/pinouts/lmx2595rhar.sexp', 'lib/interfaces/spi.sexp')
WORK = Path(os.environ.get('BENCH_WORK', str(ROOT / '.tmp/perf-audit-20260922/bench')))  # set BENCH_WORK per lane
WORK.mkdir(parents=True, exist_ok=True)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def clean_env():
    env = dict(os.environ)
    for key in list(env):
        if key.startswith('MYLANG_') or key in ('LD_PRELOAD', 'GOGC', 'GOMEMLIMIT', 'GODEBUG', 'GOMAXPROCS', 'NETLISP_LIB_DIR', 'NETLISP_STDLIB_DIR'):
            del env[key]
    env['MYLANG_MEMORY_LIMIT'] = '268435456'
    return env


def invoke(name, arm, case, cpu, extra=(), env_extra=None):
    project = BASE / 'projects' / case
    output, issue = WORK / f'{name}.svg', WORK / f'{name}.issue'
    output.write_bytes(b''); issue.write_bytes(b'')
    env = clean_env()
    docs = [str(project / p) for p in DOCS]
    command = ['taskset', '-c', str(cpu), arm['binary']]
    if arm['kind'] == 'native':
        command += [*docs, str(output)]
    else:
        env.update(MYLANG_SCHEMATIC_DECLARED=arm['declared'], MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
        env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': p for i, p in enumerate(docs)})
        command += ['--print-result']
        if arm.get('bounded'):
            command += ['--max-steps=100000000']
    command += list(extra)
    if env_extra:
        env.update(env_extra)
    if 'LD_PRELOAD' in env:
        assignments = [f'{k}={env.pop(k)}' for k in ('LD_PRELOAD', 'MYLANG_AUDIT_SAMPLES') if k in env]
        command[3:3] = ['/usr/bin/env', *assignments]
    started = time.perf_counter_ns()
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, timeout=120)
    elapsed = (time.perf_counter_ns() - started) / 1e6
    expected_stdout = b'' if arm['kind'] == 'native' else b'0\n'
    if result.returncode != 0 or result.stdout != expected_stdout or issue.read_bytes():
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
    ap.add_argument('--rounds', type=int, default=31); ap.add_argument('--warmups', type=int, default=3)
    ap.add_argument('--cpu', type=int, default=6); ap.add_argument('--cases', default='fixture,changed-net,changed-value')
    ap.add_argument('--seed', type=int, default=20260922); ap.add_argument('--reference', default=None)
    a = ap.parse_args()
    arms = json.loads(Path(a.arms).read_text())
    cases = a.cases.split(',')
    reference = a.reference or next(iter(arms))
    hashes = {}
    for case in cases:
        expected = None
        for name, arm in arms.items():
            _, digest = invoke(name, arm, case, a.cpu)
            if name == reference:
                expected = digest
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
            assert digest == hashes[case][reference], (name, case)
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
        summary[case] = {'median_ms': medians, 'p10_p90': {n: [percentile([r[case][n] for r in rows], .1), percentile([r[case][n] for r in rows], .9)] for n in arms},
                         'min_ms': {n: min(r[case][n] for r in rows) for n in arms}, f'ratio_to_{reference}': ratios}
    Path(a.out).write_text(json.dumps({'cpu': a.cpu, 'rounds': a.rounds, 'warmups': a.warmups, 'seed': a.seed, 'reference': reference,
                                       'arms': arms, 'hashes': hashes, 'summary': summary, 'rows': rows}, indent=1) + '\n')
    for case in cases:
        print(f'== {case}')
        for name in arms:
            m = summary[case]['median_ms'][name]
            r = summary[case][f'ratio_to_{reference}'].get(name, {'ratio': 1.0, 'ci95': [1, 1]})
            print(f"  {name:28s} {m:8.3f} ms  min {summary[case]['min_ms'][name]:7.3f}  x{r['ratio']:.2f} [{r['ci95'][0]:.2f},{r['ci95'][1]:.2f}]")


if __name__ == '__main__':
    main()
