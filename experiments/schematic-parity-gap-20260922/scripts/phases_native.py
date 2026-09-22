#!/usr/bin/env python3
"""Interleaved per-phase timing of the phase-instrumented Zig and Rust ports (PHASE lines on stderr)."""
import json, os, random, statistics, subprocess, sys, time
from pathlib import Path

W = Path(os.environ.get('AUDIT_WORK', '/home/epentland/ai/canopy/mylang/.tmp/perf-audit-20260922'))
B = Path(os.environ.get('AUDIT_BENCH', '/home/epentland/ai/canopy/mylang/.tmp/full-svg-benchmark-20260921'))
CPU = os.environ.get('BENCH_CPU', '6')
DOCS = ('lib/modules/straps-synth-lmx2595.sexp', 'lib/pinouts/lmx2595rhar.sexp', 'lib/interfaces/spi.sexp')
ARMS = {'zig-phases': W / 'bench/zig-phases/zig-phases', 'rust-phases': W / 'bench/rust-phases/rust-phases'}
EXPECTED = '68157ea785ee3766c039714d1d081ea1c7a55def6cf9124660495f8b797ed388'


def invoke(binary):
    out = W / 'bench/phase-native.svg'
    out.write_bytes(b'')
    docs = [str(B / 'projects/fixture' / p) for p in DOCS]
    started = time.perf_counter_ns()
    r = subprocess.run(['taskset', '-c', CPU, str(binary), *docs, str(out)], capture_output=True, timeout=60)
    elapsed = (time.perf_counter_ns() - started) / 1e6
    assert r.returncode == 0 and not r.stdout, r
    import hashlib
    assert hashlib.sha256(out.read_bytes()).hexdigest() == EXPECTED
    phases = {}
    for line in r.stderr.decode().splitlines():
        _, name, ns = line.split()
        phases[name] = phases.get(name, 0) + int(ns.split('=')[1])
    return elapsed, phases


rounds, warmups = 31, 3
rng = random.Random(20260922)
rows = []
for number in range(-warmups, rounds):
    order = list(ARMS); rng.shuffle(order)
    row = {}
    for name in order:
        elapsed, phases = invoke(ARMS[name])
        row[name] = {'wall_ms': elapsed, 'phases': phases}
    if number >= 0:
        rows.append(row)
summary = {}
for name in ARMS:
    keys = rows[0][name]['phases'].keys()
    summary[name] = {'wall_median_ms': statistics.median(r[name]['wall_ms'] for r in rows),
                     'phases_us': {k: statistics.median(r[name]['phases'][k] for r in rows) / 1000 for k in keys}}
    print(name, f"wall {summary[name]['wall_median_ms']:.3f} ms")
    for k, v in summary[name]['phases_us'].items():
        print(f"  {k:10s} {v:8.1f} us")
(W / 'phases/native-phases.json').write_text(json.dumps({'summary': summary, 'rows': rows}, indent=1) + '\n')
