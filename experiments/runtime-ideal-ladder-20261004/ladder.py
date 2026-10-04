#!/usr/bin/env python3
"""Interleaved-round timing, checksum verification and perf-stat driver for the ladder.

  ladder.py verify CASE            checksum of every version vs the B0 rust binary
  ladder.py time CASE [--rounds 7] 7 interleaved, order-randomized rounds, CPU 10
  ladder.py perf CASE              cycles/instructions per iteration at the large size

Case definitions live in ladder_cases.py. Exploratory only: not campaign evidence.
"""
import argparse, json, os, random, statistics, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BUILD = HERE / 'build'
B0 = Path('/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-harness-20261003/'
          '.mylang-cache/runtime-candidate-730a86e6-releasefast/runner/bin')
CPU = '10'
sys.path.insert(0, str(HERE))
from ladder_cases import CASES  # noqa: E402


def data_file(case, size, seed):
    """Holdout data: the benchmark's own values written to a file by the case's `gen` mode."""
    c = CASES[case]
    path = BUILD / 'data' / f'{case}_{size}_{seed}.bin'
    if not path.exists():
        path.parent.mkdir(exist_ok=True)
        subprocess.run([str(BUILD / c['gen_exe']), 'gen', str(size), str(seed), str(path)], check=True)
    return str(path)


def arms(case):
    """All (label, argv-builder) pairs: ladder versions first, then B0 references."""
    c = CASES[case]
    out = []
    for ver in c['versions']:
        label, exe, n = ver[:3]
        holdout = len(ver) > 3 and ver[3] == 'file'
        out.append((label, lambda size, it, seed, exe=exe, n=n, holdout=holdout:
                    [str(BUILD / exe), str(n), str(size), str(it), str(seed)]
                    + ([data_file(case, size, seed)] if holdout else []) + c.get('extra', [])))
    for arm in c.get('b0', ['rust', 'go', 'zig-safe', 'zig-fast', 'my-llvm']):
        out.append(('B0 ' + arm, lambda size, it, seed, arm=arm:
                    [str(B0 / (c['group'] + '-' + arm)), c['bench'], str(size), str(it), str(seed)]))
    return out


def run_once(argv, cpu=CPU, env=None):
    p = subprocess.run(['taskset', '-c', cpu] + argv, capture_output=True, text=True, env=env)
    if p.returncode != 0:
        return None, None, p.stderr.strip()
    f = p.stdout.split()
    return int(f[0]), int(f[1]), ''


def cmd_verify(case):
    c = CASES[case]
    ok = True
    ref = [a for a in arms(case) if a[0] == 'B0 rust'][0][1]
    for size, it, seed in c['verify']:
        want, _, err = run_once(ref(size, it, seed))
        row = []
        for label, build in arms(case):
            if label.startswith('B0') and label != 'B0 my-llvm':
                continue
            got, _, err = run_once(build(size, it, seed))
            if got != want:
                ok = False
                row.append(f'{label}: {got} != {want} {err}')
        print(f'size={size} iters={it} seed={seed} checksum={want}',
              'OK' if not row else 'MISMATCH ' + '; '.join(row))
    print('ALL OK' if ok else 'FAILED')
    return 0 if ok else 1


def cmd_time(case, rounds):
    c = CASES[case]
    A = arms(case)
    result = {'case': case, 'rounds': rounds, 'cpu': CPU, 'profiles': {}}
    for prof, size, it in zip(('small', 'large'), c['sizes'], c['iters']):
        seed = c.get('seed', 42)
        samples = {label: [] for label, _ in A}
        want = None
        # one warmup pass, then `rounds` rounds in a fresh random order each round
        for r in range(rounds + 1):
            order = list(A)
            random.shuffle(order)
            for label, build in order:
                cs, ns, err = run_once(build(size, it, seed))
                if cs is None:
                    print('FAILED', label, err, file=sys.stderr)
                    continue
                if want is None:
                    want = cs
                elif cs != want:
                    print('CHECKSUM DIFFERENCE', label, cs, want, file=sys.stderr)
                if r > 0:
                    samples[label].append(ns)
        rows = []
        unit = c.get('unit_div', 1)
        for label, _ in A:
            s = samples[label]
            if not s:
                continue
            med = statistics.median(s)
            rows.append({'label': label, 'median_ns_per_iter': med / it,
                         'ns_per_unit': med / it / (size if unit == 'size' else unit),
                         'min_ns_per_iter': min(s) / it, 'max_ns_per_iter': max(s) / it})
        rust = [x for x in rows if x['label'] == 'B0 rust'][0]['median_ns_per_iter']
        b0 = [x['median_ns_per_iter'] for x in rows if x['label'].startswith('B0')]
        fastest = min(b0)
        for x in rows:
            x['ratio_rust'] = x['median_ns_per_iter'] / rust
            x['ratio_fastest_b0'] = x['median_ns_per_iter'] / fastest
        result['profiles'][prof] = {'size': size, 'iterations': it, 'rows': rows}
        print(f'== {case} {prof}: size={size} iterations={it} checksum={want}')
        print(f'{"version":44s} {"ns/iter":>12s} {"ns/unit":>9s} {"x rust":>8s} {"x fastest":>9s}')
        for x in rows:
            print(f'{x["label"]:44s} {x["median_ns_per_iter"]:12.1f} {x["ns_per_unit"]:9.3f} '
                  f'{x["ratio_rust"]:8.3f} {x["ratio_fastest_b0"]:9.3f}')
    out = HERE / 'results' / f'{case}.json'
    out.write_text(json.dumps(result, indent=1))
    print('wrote', out)


def perf_cycles(argv):
    p = subprocess.run(['taskset', '-c', CPU, 'perf', 'stat', '-x,', '-e',
                        'cpu_core/cycles/u,cpu_core/instructions/u'] + argv,
                       capture_output=True, text=True)
    vals = {}
    for line in p.stderr.splitlines():
        f = line.split(',')
        if len(f) > 2 and f[2].startswith('cpu_core/'):
            vals[f[2].split('/')[1]] = int(f[0])
    return vals['cycles'], vals['instructions']


def cmd_perf(case):
    c = CASES[case]
    size, it = c['sizes'][1], c['iters'][1]
    seed = c.get('seed', 42)
    unit = size if c.get('unit_div', 1) == 'size' else c.get('unit_div', 1)
    print(f'== {case} perf: size={size} iterations={it}; per unit = {"element" if unit == size else unit}')
    print(f'{"version":44s} {"cyc/iter":>12s} {"instr/iter":>12s} {"cyc/unit":>9s} {"instr/unit":>10s}')
    res = {}
    for label, build in arms(case):
        if label.startswith('B0') and label not in ('B0 rust', 'B0 zig-fast', 'B0 zig-safe', 'B0 my-llvm'):
            continue
        c1, i1 = perf_cycles(build(size, 1, seed))
        cN, iN = perf_cycles(build(size, it, seed))
        cyc = (cN - c1) / (it - 1)
        ins = (iN - i1) / (it - 1)
        res[label] = {'cycles_per_iter': cyc, 'instr_per_iter': ins}
        print(f'{label:44s} {cyc:12.1f} {ins:12.1f} {cyc / unit:9.3f} {ins / unit:10.3f}')
    (HERE / 'results' / f'{case}.perf.json').write_text(json.dumps(res, indent=1))


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('mode', choices=['verify', 'time', 'perf'])
    ap.add_argument('case')
    ap.add_argument('--rounds', type=int, default=7)
    a = ap.parse_args()
    if a.mode == 'verify':
        sys.exit(cmd_verify(a.case))
    elif a.mode == 'time':
        cmd_time(a.case, a.rounds)
    else:
        cmd_perf(a.case)
