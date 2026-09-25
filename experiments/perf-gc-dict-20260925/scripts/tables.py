#!/usr/bin/env python3
"""Three-side instruction table from a pc.py results file.

usage: tables.py results.json [--sides base,mid,new] [--metric instructions|cycles]

Prints one row per program and arm with each side's median count and the last
side's ratio to every earlier side, then geomeans per family and arm.
"""
import argparse, json, math, statistics


def median(entry, metric):
    values = [x.get(metric) for x in entry.get('perf', []) if x.get(metric)]
    return statistics.median(values) if values else None


def geomean(values):
    values = [v for v in values if v]
    return math.exp(sum(math.log(v) for v in values) / len(values)) if values else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('results')
    ap.add_argument('--sides', default='base,mid,new')
    ap.add_argument('--metric', default='instructions')
    ap.add_argument('--rss', action='store_true', help='also print peak RSS ratios')
    o = ap.parse_args()
    sides = o.sides.split(',')
    last = sides[-1]
    data = json.load(open(o.results))
    rows = []
    for key, entry in data['samples'].items():
        program, arm = key.split('|')
        counts = {s: median(entry.get(s, {}), o.metric) for s in sides}
        rss = {s: statistics.median(entry[s]['rss_kb']) if entry.get(s, {}).get('rss_kb') else None for s in sides}
        rows.append((program, arm, counts, rss))
    ratios = [f'{last}/{s}' for s in sides[:-1]]
    head = ['program', 'arm'] + [f'{o.metric} {s}' for s in sides] + ratios
    if o.rss:
        head += [f'RSS {last}/{s}' for s in sides[:-1]]
    print('| ' + ' | '.join(head) + ' |')
    print('|---|---|' + '---:|' * (len(head) - 2))
    groups = {}
    for program, arm, counts, rss in rows:
        cells = [program, arm] + [f'{counts[s]:,.0f}' if counts[s] else '—' for s in sides]
        for s in sides[:-1]:
            r = counts[last] / counts[s] if counts[last] and counts[s] else None
            cells.append('—' if r is None else f'{r:.4f}')
            for g in (f"{program.split('/')[0]} {arm}", f'all {arm}'):
                groups.setdefault(g, {}).setdefault(s, []).append(r)
        if o.rss:
            for s in sides[:-1]:
                r = rss[last] / rss[s] if rss[last] and rss[s] else None
                cells.append('—' if r is None else f'{r:.3f}')
        print('| ' + ' | '.join(cells) + ' |')
    print()
    print('| group | n | ' + ' | '.join(f'geomean {last}/{s}' for s in sides[:-1]) + ' |')
    print('|---|---:|' + '---:|' * (len(sides) - 1))
    for g in sorted(groups):
        n = len(groups[g][sides[0]])
        print(f'| {g} | {n} | ' + ' | '.join(f'{geomean(groups[g][s]):.4f}' for s in sides[:-1]) + ' |')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
