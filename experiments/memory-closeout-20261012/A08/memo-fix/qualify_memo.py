#!/usr/bin/env python3
"""Reproduce native memo cold/warm contracts on a fixed compiler; each build is admitted."""
import argparse
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import qualify

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--compiler', type=Path, required=True)
p.add_argument('--zig', type=Path, required=True)
p.add_argument('--source-revision', required=True)
p.add_argument('--work', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
args = p.parse_args()
args.admission = 'build'
args.timeout = 120
args.default_zero = args.candidate_default_zero = False
args.candidate_revision = args.candidate = args.memory_wrapper = None
args.compiler = args.compiler.resolve()
args.zig = args.zig.resolve()
if args.work.exists() or args.output.exists():
    p.error('Choose unused work and output paths')
run = qualify.Run(args)
sources = Path(__file__).with_name('sources')
for sample, modes in [('original', {'release': (), 'debug': ('--unoptimized',), 'verified': ('--verify-facts',), 'optimized-debug': ('--optimize-debug',), 'no-facts': ('--no-facts',)}), ('minimal', {'debug': ('--unoptimized',)})]:
    project = run.work / sample
    qualify.write(project / 'main.my', (sources / (sample+'.my')).read_text())
    for mode, flags in modes.items():
        args.build_mode = '--unoptimized' if mode == 'debug' else '--optimize-debug' if mode == 'optimized-debug' else '--release'
        extra = tuple(f for f in flags if f not in ('--unoptimized', '--optimize-debug'))
        for state in ('cold', 'warm'):
            row = run.build(sample+'-'+mode+'-'+state, project, expected='', extra=extra)
            if state == 'warm' and row['status'] == 0:
                front = (row['report'] or {}).get('stages', {}).get('frontend', {})
                row['independent_reuse_observed'] = front.get('reused', 0) > 0 and front.get('damaged', 0) == 0
                row['passed'] &= row['independent_reuse_observed']
            run.save()
raise SystemExit(0 if all(r['passed'] for r in run.rows) else 1)
