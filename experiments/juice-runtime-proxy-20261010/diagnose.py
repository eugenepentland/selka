#!/usr/bin/env python3
"""Bounded diagnostic experiment, separate from Juice accuracy qualification.

Use unchanged executable pairs from a retained suite. Alternate ASLR on/off for
copy workloads and short/16x-long tree workloads, with per-process perf evidence.
No system settings are changed. Requires Intel Alder Lake cpu_core events.
"""
import argparse
import copy
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import shutil
import subprocess
import sys
import time

HARDWARE = ["instructions", "cycles", "ref-cycles", "ld_blocks.address_alias",
            "ld_blocks.store_forward", "cycle_activity.stalls_l1d_miss",
            "mem_load_retired.l1_miss"]
BRANCH = ["instructions", "cycles", "ref-cycles", "branches",
          "br_misp_retired.all_branches", "int_misc.recovery_cycles", "resource_stalls.sb"]
FRONTEND = ["instructions", "cycles", "ref-cycles", "idq.dsb_uops",
            "idq.mite_uops", "idq.ms_uops", "idq_uops_not_delivered.core"]
LOOP = ["instructions", "cycles", "ref-cycles", "idq.dsb_uops",
        "idq.mite_uops", "lsd.uops", "idq_uops_not_delivered.core"]
SOFTWARE = ["duration_time", "task-clock", "context-switches", "cpu-migrations",
            "minor-faults", "major-faults"]


def write(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_checksum(size, iterations, seed):
    # Independent closed-form contribution of each node; no executable oracle.
    weights = []

    def visit(lo, hi, depth):
        if lo < hi:
            mid = (lo + hi) // 2
            weights.append((mid, depth + 1))
            visit(lo, mid, depth + 1)
            visit(mid + 1, hi, depth + 1)

    visit(0, size, 0)
    period = [sum(weight * ((seed + batch + 13 * mid) % 1009)
                  for mid, weight in weights) for batch in range(1009)]
    cycles, tail = divmod(iterations, 1009)
    return (cycles * sum(period) + sum(period[:tail])) % 1000000007


def parse_perf(path, hardware):
    metrics = {}
    for line in path.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split(";")
        if len(fields) < 5:
            raise ValueError(f"invalid perf row: {line}")
        value, unit, event, running, percent = fields[:5]
        if float(percent) != 100:
            raise ValueError(f"counter was not continuously scheduled: {line}")
        key = event.removeprefix("cpu_core/").removesuffix("/u")
        if key in metrics:
            raise ValueError(f"duplicate event: {line}")
        metrics[key] = float(value)
    if set(metrics) != set(hardware + SOFTWARE):
        raise ValueError(f"missing/extra events: {set(metrics)}")
    return metrics


def proc_cpu():
    return {fields[0]: list(map(int, fields[1:9]))
            for line in Path('/proc/stat').read_text().splitlines()
            if (fields := line.split())[0].startswith('cpu')}


def cpu_delta(before, after, cpu):
    delta = [b - a for a, b in zip(before[cpu], after[cpu])]
    total = sum(delta)
    return 100 * (total - delta[3] - delta[4]) / total if total else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('suite', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cpu', type=int, default=10)
    parser.add_argument('--pairs', type=int, default=12, choices=range(5, 31))
    parser.add_argument('--profile', choices=['memory', 'branch', 'frontend', 'loop'], default='memory')
    parser.add_argument('--cases', nargs='+', default=['copy', 'large-copy', 'atomic', 'tree-short', 'tree-long'],
                        choices=['copy', 'large-copy', 'atomic', 'tree-short', 'tree-long'])
    parser.add_argument('--layouts', nargs='+', choices=['randomized', 'fixed'], default=['randomized', 'fixed'])
    options = parser.parse_args()
    hardware = {'memory': HARDWARE, 'branch': BRANCH, 'frontend': FRONTEND, 'loop': LOOP}[options.profile]
    root = options.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    suite = json.loads(options.suite.read_text())
    cases = {case['name']: case for case in suite['cases']}
    assert tree_checksum(4096, 272, 7) == int(cases['wave3-tree']['expected_stdout'])
    long_tree = copy.deepcopy(cases['wave3-tree'])
    long_tree['args'][1] = str(272 * 16)
    long_tree['expected_stdout'] = str(tree_checksum(4096, 272 * 16, 7))
    cases.update({'tree-short': cases['wave3-tree'], 'tree-long': long_tree})
    conditions = [(name, cases[name], layout) for name in options.cases for layout in options.layouts]
    inputs = root / 'inputs'
    inputs.mkdir()
    for _, case, _ in conditions:
        for arm in ('base', 'candidate'):
            source = Path(case[arm]['binary'])
            identity = case[arm]['sha256']
            assert sha(source) == identity
            target = inputs / identity
            if not target.exists():
                shutil.copy2(source, target)
            assert sha(target) == identity
    run = root / 'run'
    run.mkdir()
    for name in ('home', 'tmp'):
        (run / name).mkdir()
    environment = dict(PATH=os.defpath, LC_ALL='C', LANG='C', TZ='UTC',
                       HOME=str(run / 'home'), TMPDIR=str(run / 'tmp'), PWD=str(run))
    sibling = Path(f'/sys/devices/system/cpu/cpu{options.cpu}/topology/thread_siblings_list').read_text().strip()
    method = dict(cpu=options.cpu, siblings=sibling, pairs=options.pairs,
                  warmup_pairs=1, seed=20261010, kernel=platform.release(),
                  cpuinfo=Path('/proc/cpuinfo').read_text().split('\n\n')[0],
                  hardware=hardware, software=SOFTWARE, profile=options.profile,
                  suite_sha256=sha(options.suite), runner_sha256=sha(Path(__file__)),
                  conditions=[dict(name=n, case=c, layout=l) for n, c, l in conditions],
                  scope='Exploratory diagnostic counters; perf-instrumented elapsed time is not an independent accuracy label. No qualification thresholds changed.')
    method['argv'] = sys.argv
    method['tools'] = {tool: sha(Path(shutil.which(tool))) for tool in ('perf', 'setarch', 'taskset')}
    method['frequency_policy'] = {key: Path(f'/sys/devices/system/cpu/cpu{options.cpu}/cpufreq/{key}').read_text().strip()
                                  for key in ('scaling_driver', 'scaling_governor', 'scaling_min_freq', 'scaling_max_freq')}
    method['uclamp'] = [line.strip() for line in Path('/proc/self/sched').read_text().splitlines() if 'uclamp' in line]
    write(root / 'method.json', method)
    shutil.copy2(__file__, root / 'runner.py')
    lock_path = Path.home() / '.cache/mylang/runtime-parity-timing.lock'
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    with lock_path.open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        rng = random.Random(method['seed'])
        for index in range(options.pairs + 1):
            order = conditions.copy()
            rng.shuffle(order)
            for name, case, layout in order:
                arms = ('base', 'candidate') if index % 2 == 0 else ('candidate', 'base')
                for arm in arms:
                    prefix = root / f'{index:02}-{name}-{layout}-{arm}'
                    shutil.copy2(inputs / case[arm]['sha256'], run / 'program')
                    perf_file = prefix.with_suffix('.perf')
                    argv = ['setarch', 'x86_64'] + (['-R'] if layout == 'fixed' else [])
                    argv += ['taskset', '-c', str(options.cpu), 'perf', 'stat', '--no-scale',
                             '-x', ';', '-o', str(perf_file), '-e', ','.join(SOFTWARE),
                             '-e', '{' + ','.join(f'cpu_core/{event}/u' for event in hardware) + '}',
                             '--', str(run / 'program'), *case['args']]
                    before = proc_cpu()
                    started = time.monotonic()
                    process = subprocess.run(argv, cwd=run, env=environment, capture_output=True, timeout=30)
                    seconds = time.monotonic() - started
                    after = proc_cpu()
                    prefix.with_suffix('.stdout').write_bytes(process.stdout)
                    prefix.with_suffix('.stderr').write_bytes(process.stderr)
                    assert process.returncode == 0 and not process.stderr, (argv, process.stderr)
                    output = process.stdout.decode().strip().split()
                    assert output[0] == case['expected_stdout'].strip(), (name, output)
                    assert len(output) == (2 if name.startswith('tree-') else 1)
                    row = dict(name=name, layout=layout, arm=arm, round=index, warmup=index == 0,
                               command=argv, metrics=parse_perf(perf_file, hardware), wall_seconds=seconds,
                               internal_ns=int(output[1]) if name.startswith('tree-') else None,
                               cpu_busy_percent={key: cpu_delta(before, after, key) for key in before},
                               evidence={p.name: sha(p) for p in [perf_file, prefix.with_suffix('.stdout'), prefix.with_suffix('.stderr')]})
                    rows.append(row)
                    write(root / 'observations.json', rows)
            print(f'Completed diagnostic round {index}/{options.pairs}', flush=True)
    print(f'Retained {len(rows)} executions, including warmups, in {root}', flush=True)


if __name__ == '__main__':
    main()
