#!/usr/bin/env python3
"""Interleaved per-phase CPU comparison of two `phases_my.py` probe binaries.

usage: phases_ab.py <before-work-dir> <after-work-dir> <out.json> [rounds]

Each work directory is an `AUDIT_WORK` that `phases_my.py build` has filled, so
it holds `phases/probe` and `arms/o3.declared`. The two probes are invoked in a
randomized interleaved order on the same fixture, and every run's SVG hash must
match the first one's. Phase times are `CLOCK_PROCESS_CPUTIME_ID` intervals
inside the process, so they survive a loaded machine better than wall time, and
the reported interval is a paired bootstrap over rounds.
"""
import json
import random
import statistics
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'schematic-parity-gap-20260922/scripts'))
import bench_svg  # noqa: E402

CPU = '10'
PHASES = ['main::main', 'io::load', 'sexpr::parse', 'schematic::build', 'svg::render', 'io::flush']


def invoke(binary, declared, case='fixture'):
    project = bench_svg.BASE / 'projects' / case
    output, issue = bench_svg.WORK / 'ab.svg', bench_svg.WORK / 'ab.issue'
    output.write_bytes(b'')
    issue.write_bytes(b'')
    env = bench_svg.clean_env()
    docs = [str(project / p) for p in bench_svg.DOCS]
    env.update(MYLANG_SCHEMATIC_DECLARED=declared, MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
    env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': p for i, p in enumerate(docs)})
    started = time.perf_counter_ns()
    r = subprocess.run(['taskset', '-c', CPU, str(binary), '--print-result'], env=env, capture_output=True, timeout=60)
    elapsed = (time.perf_counter_ns() - started) / 1e6
    assert r.returncode == 0 and r.stdout == b'0\n' and not issue.read_bytes(), (binary, r.stderr[-400:])
    phases = {}
    for line in r.stderr.decode().splitlines():
        _, name, ns = line.split()
        phases.setdefault(name, 0)
        phases[name] += int(ns.split('=')[1])
    return elapsed, bench_svg.sha(output.read_bytes()), phases


def percentile(values, fraction):
    values = sorted(values)
    point = (len(values) - 1) * fraction
    lower = int(point)
    upper = min(lower + 1, len(values) - 1)
    return values[lower] + (values[upper] - values[lower]) * (point - lower)


def main() -> None:
    before, after, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    rounds = int(sys.argv[4]) if len(sys.argv) > 4 else 31
    arms = {
        'before': (before / 'phases/probe', (before / 'arms/o3.declared').read_text()),
        'after': (after / 'phases/probe', (after / 'arms/o3.declared').read_text()),
    }
    reference = invoke(*arms['before'])[1]
    assert invoke(*arms['after'])[1] == reference, 'the two arms render different SVG'
    rng = random.Random(20260922)
    rows = []
    for number in range(-3, rounds):
        order = list(arms)
        rng.shuffle(order)
        row = {}
        for name in order:
            elapsed, digest, phases = invoke(*arms[name])
            assert digest == reference, name
            row[name] = {'wall_ms': elapsed, 'phases': phases}
        if number >= 0:
            rows.append(row)
    summary = {}
    for phase in PHASES:
        values = {n: [r[n]['phases'].get(phase, 0) / 1000 for r in rows] for n in arms}
        medians = {n: statistics.median(values[n]) for n in arms}
        boot = []
        for _ in range(2000):
            sample = rng.choices(range(len(rows)), k=len(rows))
            b = statistics.median(values['before'][i] for i in sample)
            a = statistics.median(values['after'][i] for i in sample)
            boot.append(a - b)
        summary[phase] = {'before_us': medians['before'], 'after_us': medians['after'],
                          'delta_us': medians['after'] - medians['before'],
                          'ci95_us': [percentile(boot, .025), percentile(boot, .975)]}
    summary['wall_median_ms'] = {n: statistics.median(r[n]['wall_ms'] for r in rows) for n in arms}
    out.write_text(json.dumps({'rounds': rounds, 'cpu': CPU, 'summary': summary, 'rows': rows}, indent=1) + '\n')
    print(json.dumps(summary['wall_median_ms'], indent=1))
    for phase in PHASES:
        v = summary[phase]
        print(f"  {phase:20s} before {v['before_us']:8.1f}  after {v['after_us']:8.1f}  "
              f"delta {v['delta_us']:+8.1f} us [{v['ci95_us'][0]:+.1f},{v['ci95_us'][1]:+.1f}]")


if __name__ == '__main__':
    main()
