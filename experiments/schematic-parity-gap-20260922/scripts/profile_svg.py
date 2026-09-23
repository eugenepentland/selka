#!/usr/bin/env python3
"""Self-PC SIGPROF profile of one schematic arm over many fresh runs (dense sampler).

usage: profile_svg.py --arms arms.json --arm NAME --count 4000 --out profile.json [--manifest receipt.qbe-manifest.json]
"""
import argparse, bisect, gzip, json, os, subprocess, sys
from collections import Counter
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bench_svg

ROOT = bench_svg.ROOT
SAMPLER_SRC = Path('/home/epentland/ai/canopy/mylang/.tmp/perf-audit-20260922/bench/sample_fast.c')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--arms', required=True); ap.add_argument('--arm', required=True)
    ap.add_argument('--count', type=int, default=4000); ap.add_argument('--out', required=True)
    ap.add_argument('--manifest', default=None); ap.add_argument('--cpu', type=int, default=6)
    ap.add_argument('--case', default='fixture')
    a = ap.parse_args()
    arms = json.loads(Path(a.arms).read_text())
    arm = arms[a.arm]
    work = bench_svg.WORK
    library = work / 'sample_dense.so'
    subprocess.run(['cc', '-shared', '-fPIC', '-O2', str(SAMPLER_SRC), '-o', str(library), '-ldl'], check=True)
    samples_path = work / f'samples-{a.arm}.txt'
    samples_path.write_text('')
    _, expected = bench_svg.invoke(a.arm, arm, a.case, a.cpu)
    for number in range(a.count):
        _, digest = bench_svg.invoke(a.arm, arm, a.case, a.cpu, env_extra={'LD_PRELOAD': str(library), 'MYLANG_AUDIT_SAMPLES': str(samples_path)})
        assert digest == expected
        if (number + 1) % 500 == 0:
            print(f'{number + 1} sampled runs', flush=True)
    friendly = {}
    manifest = a.manifest or (arm['binary'] + '.qbe-manifest.json')
    if Path(manifest).exists():
        for f in json.loads(Path(manifest).read_text())['functions']:
            friendly[f['symbol']] = f['name']
    symbols = []
    for line in subprocess.check_output(['nm', '-n', '-S', '--defined-only', arm['binary']], text=True).splitlines():
        fields = line.split()
        if len(fields) == 4 and fields[2] in ('t', 'T', 'W', 'w'):
            symbols.append((int(fields[0], 16), int(fields[1], 16), fields[3]))
    addresses = [s[0] for s in symbols]
    totals, pcs = Counter(), Counter()
    outside = overflow = runs = samples = unmapped = 0
    raw = samples_path.read_text()
    with gzip.open(a.out + '.samples.gz', 'wt') as stream:
        stream.write(raw)
    for line in raw.splitlines():
        fields = line.split()
        if fields[0] == 'run':
            runs += 1; samples += int(fields[3]); outside += int(fields[5]); overflow += int(fields[7]); continue
        pc, hits = int(fields[0], 16), int(fields[1])
        pcs[pc] += hits
        index = bisect.bisect_right(addresses, pc) - 1
        if index < 0 or pc >= symbols[index][0] + symbols[index][1]:
            unmapped += hits
        else:
            symbol = symbols[index][2]
            totals[friendly.get(symbol, symbol)] += hits
    result = {'binary': arm['binary'], 'runs': runs, 'samples': samples, 'outside_main_executable': outside,
              'percent_outside': outside * 100 / samples, 'unmapped_inside': unmapped, 'overflow': overflow,
              'functions': [{'name': n, 'samples': h, 'percent': h * 100 / samples} for n, h in totals.most_common()],
              'top_pcs': [{'address': hex(pc), 'samples': h, 'percent': h * 100 / samples} for pc, h in pcs.most_common(40)]}
    Path(a.out).write_text(json.dumps(result, indent=1) + '\n')
    print(f"runs {runs} samples {samples} outside {outside} ({outside*100/samples:.1f}%) unmapped {unmapped}")
    for f in result['functions'][:30]:
        print(f"  {f['percent']:6.2f}%  {f['name']}")


if __name__ == '__main__':
    main()
