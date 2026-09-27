#!/usr/bin/env python3
"""Group a `--rc-runtime=sites` JSON report (MYLANG_RC_SITES) for analysis.

usage: summarize.py REPORT.json... [--by operation|function|site|type|opfn] [--top N] [--event NAME]

With several reports, each program's sites are weighted by their share of that
program's events (or of the one --event), so every program counts equally.
"""
import argparse, collections, json, os


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('reports', nargs='+')
    ap.add_argument('--by', default='operation')
    ap.add_argument('--top', type=int, default=30)
    ap.add_argument('--event', help='rank by one event (e.g. hold_acquire) instead of all events')
    opts = ap.parse_args()
    groups = collections.defaultdict(lambda: {'events': 0.0, 'calls': 0, 'sites': 0, 'counts': collections.Counter()})
    calls = 0
    for path in opts.reports:
        doc = json.load(open(path))
        calls += doc['calls']
        weight = lambda s: s['counts'].get(opts.event, 0) if opts.event else s['events']
        total = sum(weight(s) for s in doc['sites']) or 1
        scale = 1.0 / total if len(opts.reports) > 1 else 1.0
        for s in doc['sites']:
            pos = f"{os.path.basename(s['path'])}:{s['line']}"
            key = {'operation': s['operation'], 'function': s['function'], 'type': s['type'],
                   'opfn': f"{s['operation']} @ {s['function']}",
                   'site': f"{s['operation']} {s['type'] or '-'} {s['function']} {pos} pc {s['pc']}"}[opts.by]
            g = groups[key]
            g['events'] += weight(s) * scale
            g['calls'] += s['calls']
            g['sites'] += 1
            g['counts'].update(s['counts'])
    total = sum(g['events'] for g in groups.values())
    shares = len(opts.reports) > 1
    print(f"total {opts.event or 'events'}: {total:,.0f}{' (sum of per-program shares)' if shares else ''}  calls: {calls:,}")
    for key, g in sorted(groups.items(), key=lambda kv: -kv[1]['events'])[:opts.top]:
        counts = ' '.join(f"{k}={v}" for k, v in g['counts'].most_common())
        value = f"{g['events'] / len(opts.reports):8.2%}" if shares else f"{g['events']:>12,.0f} {g['events'] / total:6.1%}"
        print(f"{value} {g['calls']:>12,} {g['sites']:>5}  {key}  [{counts}]")


if __name__ == '__main__':
    main()
