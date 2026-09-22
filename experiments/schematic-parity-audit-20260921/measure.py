#!/usr/bin/env python3
"""Matched SVG timing and correctness evidence for private diagnostic builds."""
import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.tmp/schematic-parity-20260921'
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tests'))
from schematic_layout import geometry

ARMS = ['unit-o3', 'relinked', 'regenerated', 'stack', 'prebind', 'both', 'whole-o3', 'whole-both']
FIXTURES = ROOT / 'experiments/schematic/fixtures'
INPUTS = [FIXTURES / n for n in ('straps-synth-lmx2595.sexp', 'lmx2595rhar.sexp', 'spi.sexp')]
MANIFEST = json.loads((WORK / 'manifest.json').read_text())
ENV = os.environ.copy()
ENV.update(MYLANG_SCHEMATIC_DECLARED=','.join(d['name'] for d in MANIFEST['host']['declarations']),
           MYLANG_SCHEMATIC_OUTPUT=str(WORK / 'output.svg'), MYLANG_SCHEMATIC_ISSUE=str(WORK / 'issue'))
ENV.update({f'MYLANG_SCHEMATIC_INPUT_{i}': str(p) for i, p in enumerate(INPUTS)})


def invoke(arm, arguments=('--max-steps=100000000',), environment=None, prefix=()):
    (WORK / 'issue').write_bytes(b'')
    command = [*prefix, 'taskset', '-c', '6', str(WORK / arm), '--print-result', *arguments]
    start = time.perf_counter_ns()
    p = subprocess.run(command, capture_output=True, env=environment or ENV, timeout=60)
    elapsed = (time.perf_counter_ns()-start)/1e6
    return elapsed, (p.returncode, p.stdout, p.stderr, (WORK / 'issue').read_bytes(), (WORK / 'output.svg').read_bytes())


def counters_only(reference):
    counters = {}
    for arm in ('regenerated', 'both', 'whole-o3', 'whole-both'):
        rounds = []
        for i in range(5):
            dest = WORK / 'perf-stat.txt'
            _, result = invoke(arm, prefix=['perf', 'stat', '-x', ';', '-o', str(dest), '-e', 'task-clock,cpu_core/cycles/,cpu_core/instructions/,page-faults'])
            if b'No supported events found' in result[2] or b'No permission' in result[2]:
                (OUT / 'counters.json').write_text(json.dumps({'available': False, 'reason': result[2].decode()}, indent=2)+'\n')
                print('Hardware counters unavailable; wall-time evidence retained.', flush=True)
                return
            assert result == reference, (arm, result[:4])
            rounds.append(dest.read_text())
        counters[arm] = rounds
    (OUT / 'counters.json').write_text(json.dumps(counters, indent=2)+'\n')


def main():
    tag = 'lto-' if '--lto' in sys.argv else ''
    if tag:
        ARMS[:] = ['unit-o3', 'regenerated', 'whole-o3', 'whole-both', 'zlink-plain', 'zlink-both', 'lto-plain', 'lto-both']
    _, reference = invoke('unit-o3')
    assert reference[:4] == (0, b'0\n', b'', b'')
    if '--counters-only' in sys.argv:
        counters_only(reference)
        return
    geometry(ET.fromstring(reference[4]))
    qualification = {'geometry': 'passed', 'valid': {}, 'cases': {}}
    for arm in ARMS:
        _, result = invoke(arm)
        assert result == reference, arm
        qualification['valid'][arm] = 'byte-identical'
    _, counts = invoke('counts')
    assert counts[0:2] == reference[0:2] and counts[3:] == reference[3:]
    qualification['host_calls'] = {line.split()[1]: int(line.split()[2]) for line in counts[2].decode().splitlines()}
    for name, args in [('step-limit', ('--max-steps=100',)), ('frame-limit', ('--max-frames=3',)), ('gc-stress', ('--max-steps=100000000', '--gc-stress'))]:
        _, ref = invoke('unit-o3', args)
        for arm in ARMS:
            _, result = invoke(arm, args)
            assert result == ref, (name, arm)
        qualification['cases'][name] = {'status': ref[0], 'stderr': ref[2].decode(), 'issue': ref[3].decode(), 'all_equal': True}
    for name, source in [('unclosed', '('), ('unexpected-close', ')'), ('bad-escape', '"\\q"'), ('missing-model', '(bogus)'),
                         ('changed-net', INPUTS[0].read_text().replace('LMX_CE', 'LMX_CE_AUDIT'))]:
        changed = WORK / f'{name}.sexp'
        changed.write_text(source)
        env = {**ENV, 'MYLANG_SCHEMATIC_INPUT_0': str(changed)}
        _, ref = invoke('unit-o3', environment=env)
        for arm in ARMS:
            _, result = invoke(arm, environment=env)
            assert result == ref, (name, arm)
        if name == 'changed-net':
            assert ref[0] == 0 and ref[4] != reference[4]
            geometry(ET.fromstring(ref[4]))
        qualification['cases'][name] = {'status': ref[0], 'stderr': ref[2].decode(), 'issue': ref[3].decode(), 'all_equal': True}
    (OUT / (tag+'qualification.json')).write_text(json.dumps(qualification, indent=2)+'\n')
    print('qualification passed; host calls:', sum(qualification['host_calls'].values()), flush=True)
    randomizer = random.Random(20260921)
    samples = []
    for round_ in range(-3, 21):
        order = ARMS.copy()
        randomizer.shuffle(order)
        values = {}
        for arm in order:
            elapsed, result = invoke(arm)
            assert result == reference, (round_, arm)
            values[arm] = elapsed
        if round_ >= 0:
            samples.append({'round': round_, 'order': order, 'ms': values})
    medians = {a: statistics.median(s['ms'][a] for s in samples) for a in ARMS}
    ratios = {}
    for arm in ARMS:
        draws = []
        for _ in range(4000):
            rounds = randomizer.choices(samples, k=len(samples))
            draws.append(statistics.median(s['ms'][arm] for s in rounds) /
                         statistics.median(s['ms']['regenerated'] for s in rounds))
        draws.sort()
        ratios[arm] = {'ratio': medians[arm]/medians['regenerated'], 'paired_bootstrap_95': [draws[100], draws[3899]]}
    facts = {'cpu': 6, 'rounds': 21, 'warmups': 3, 'units': 'ms', 'scope': 'process launch, input read, SVG to private file, shutdown; no compilation',
             'stdout_sha256': hashlib.sha256(reference[4]).hexdigest(), 'svg_bytes': len(reference[4]),
             'input_bytes': sum(p.stat().st_size for p in INPUTS), 'samples': samples, 'median_ms': medians, 'ratios_to_regenerated': ratios}
    (OUT / (tag+'measurements.json')).write_text(json.dumps(facts, indent=2)+'\n')
    print(json.dumps({'median_ms': medians, 'ratios': ratios}, indent=2), flush=True)
    if not tag:
        counters_only(reference)


if __name__ == '__main__':
    main()
