#!/usr/bin/env python3
"""Summarize one mylang-counters-v1 document: totals per kind, and the top sites.

usage: count_summary.py COUNTS.json [--instructions N] [--top 15]
With --instructions (the ordinary build's user-space instructions retired), every
kind is also given per thousand instructions.
"""
import gzip, json, sys
from collections import defaultdict

def load(path):
    opener = gzip.open if path.endswith('.gz') else open
    with opener(path, 'rt') as f:
        return json.load(f)

def main():
    path = sys.argv[1]
    instr = int(sys.argv[sys.argv.index('--instructions') + 1]) if '--instructions' in sys.argv else None
    top = int(sys.argv[sys.argv.index('--top') + 1]) if '--top' in sys.argv else 15
    d = load(path)
    print(f"## {path}")
    print("| kind | count | per ki |" if instr else "| kind | count |")
    print("|---|---:|---:|" if instr else "|---|---:|")
    for k, v in d['kinds'].items():
        if v['count']:
            print(f"| {k} | {v['count']:,} | {v['count']/instr*1000:.2f} |" if instr else f"| {k} | {v['count']:,} |")
    t = d['totals']
    for k in ('calls', 'allocs', 'runtime_retains', 'runtime_releases', 'text_appends', 'buffer_pushes', 'buffer_appends'):
        print(f"| fn:{k} | {t.get(k,0):,} | {t.get(k,0)/instr*1000:.2f} |" if instr else f"| fn:{k} | {t.get(k,0):,} |")
    sites = sorted(d['sites'], key=lambda s: -s['count'])[:top]
    print("\n| function | origin | line | kind | detail | count |")
    print("|---|---|---:|---|---|---:|")
    for s in sites:
        print(f"| {s['function']} | {s['origin']} | {s['path'].split('/')[-1]}:{s['line']} | {s['kind']} | {s['detail']} | {s['count']:,} |")

if __name__ == '__main__':
    main()
