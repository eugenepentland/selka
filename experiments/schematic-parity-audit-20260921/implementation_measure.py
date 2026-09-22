#!/usr/bin/env python3
"""Matched application-only benchmark for schematic net normalization."""
import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import time
import xml.etree.ElementTree as ET
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.tmp/schematic-implementation-20260921'
OUT = Path(__file__).resolve().parent
FIXTURES = ROOT / 'experiments/schematic/fixtures'
INPUTS = [FIXTURES / n for n in ('straps-synth-lmx2595.sexp', 'lmx2595rhar.sexp', 'spi.sexp')]
ARMS = ('before', 'after')
BINARIES = {name: WORK / f'bench-{name}' for name in ARMS}
sys.path.insert(0, str(ROOT / 'tests'))
from schematic_layout import geometry

manifest = json.loads((ROOT / '.tmp/schematic-parity-20260921/manifest.json').read_text())
base_env = os.environ.copy()
base_env['MYLANG_SCHEMATIC_DECLARED'] = ','.join(d['name'] for d in manifest['host']['declarations'])
base_env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': str(path) for i, path in enumerate(INPUTS)})


def invoke(arm, inputs=INPUTS):
    output = WORK / f'benchmark-{arm}.svg'
    issue = WORK / f'benchmark-{arm}.issue'
    issue.write_bytes(b'')
    env = dict(base_env)
    env['MYLANG_SCHEMATIC_OUTPUT'] = str(output)
    env['MYLANG_SCHEMATIC_ISSUE'] = str(issue)
    env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': str(path) for i, path in enumerate(inputs)})
    command = ['taskset', '-c', '6', str(BINARIES[arm]), '--print-result', '--max-steps=100000000']
    start = time.perf_counter_ns()
    process = subprocess.run(command, capture_output=True, env=env, timeout=60)
    elapsed = (time.perf_counter_ns() - start) / 1e6
    return elapsed, (process.returncode, process.stdout, process.stderr, issue.read_bytes(), output.read_bytes())


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    _, reference = invoke('before')
    assert reference[:4] == (0, b'0\n', b'', b'')
    geometry(ET.fromstring(reference[4]))
    _, current = invoke('after')
    assert current == reference

    changed = WORK / 'implementation-changed-net.sexp'
    changed.write_text(INPUTS[0].read_text().replace('LMX_CE', 'LMX_CE_IMPLEMENTATION'))
    changed_inputs = [changed, *INPUTS[1:]]
    _, changed_before = invoke('before', changed_inputs)
    _, changed_after = invoke('after', changed_inputs)
    assert changed_before == changed_after and changed_before[0] == 0 and changed_before[4] != reference[4]
    geometry(ET.fromstring(changed_before[4]))

    source = INPUTS[0].read_text()
    lf1 = '    (instance "C_LF1" (cap-0402 "390pF" np0 "5%" "50V")   (pin 1 "LMX_CPOUT")   (pin 2 "GND") (id f1ff5923))           ;; C69\n'
    lf2 = '    (instance "C_LF2" (cap-0402 "0.068uF" x7r "10%" "25V") (pin 1 "LMX_CPOUT")   (pin 2 "LMX_LF_ZERO") (id f737b14f))   ;; C71\n'
    assert source.count(lf1 + lf2) == 1
    nc_label = 'SYNC — phase-sync input unused; the board runs one free-standing synth, no SYSREF/JESD204B'
    transformations = {
        'swapped_net_names': source.replace('LMX_CE', '__NET_SWAP__').replace('LMX_MUXOUT', 'LMX_CE').replace('__NET_SWAP__', 'LMX_MUXOUT'),
        'passive_declaration_order': source.replace(lf1 + lf2, lf2 + lf1),
        'passive_pin_order': source.replace('(pin 1 "LMX_VTUNE")   (pin 2 "LMX_CPOUT")', '(pin 2 "LMX_CPOUT") (pin 1 "LMX_VTUNE")'),
        'display_raw_namespace': source.replace('V_3V3', 'V_ALT'),
        'nc_raw_collision': source.replace(nc_label, 'LMX_CE'),
        'empty_net_rejected': source.replace('(pin 1 "LMX_CE")', '(pin 1 "")', 1),
    }
    transformed_results = {}
    for name, transformed in transformations.items():
        assert transformed != source, name
        path = WORK / f'implementation-{name}.sexp'
        path.write_text(transformed)
        transformed_inputs = [path, *INPUTS[1:]]
        _, before_result = invoke('before', transformed_inputs)
        _, after_result = invoke('after', transformed_inputs)
        assert before_result == after_result, name
        geometry_status = 'not applicable'
        if before_result[0] == 0:
            geometry(ET.fromstring(before_result[4]))
            geometry_status = 'passed'
        transformed_results[name] = {
            'status': before_result[0], 'issue': before_result[3].decode(),
            'between_arms': 'byte-identical', 'geometry': geometry_status,
            'svg_sha256': hashlib.sha256(before_result[4]).hexdigest() if before_result[4] else None,
        }

    randomizer = random.Random(20260921)
    samples = []
    for round_ in range(-3, 21):
        order = list(ARMS)
        randomizer.shuffle(order)
        values = {}
        for arm in order:
            elapsed, result = invoke(arm)
            assert result == reference, (round_, arm)
            values[arm] = elapsed
        if round_ >= 0:
            samples.append({'round': round_, 'order': order, 'ms': values})
    medians = {arm: statistics.median(sample['ms'][arm] for sample in samples) for arm in ARMS}
    draws = []
    for _ in range(4000):
        rounds = randomizer.choices(samples, k=len(samples))
        draws.append(statistics.median(s['ms']['after'] for s in rounds) /
                     statistics.median(s['ms']['before'] for s in rounds))
    draws.sort()
    compiler = WORK / 'before-mylang'
    receipts = {arm: json.loads((WORK / f'bench-{arm}.qbe-manifest.json').read_text()) for arm in ARMS}
    runtimes = {arm: Path(receipts[arm]['runtime_object']) for arm in ARMS}
    assert sha(runtimes['before']) == sha(runtimes['after'])
    evidence = {
        'cpu': 6, 'rounds': 21, 'warmups': 3, 'seed': 20260921, 'units': 'ms',
        'scope': 'process launch, input read, SVG to private file, shutdown; no compilation',
        'configuration': 'same retained compiler/runtime, per-function LLVM O3, step and frame accounting',
        'compiler': {'path': str(compiler.relative_to(ROOT)), 'sha256': sha(compiler)},
        'runtime_sha256': sha(runtimes['before']),
        'binaries': {arm: {'path': str(BINARIES[arm].relative_to(ROOT)), 'sha256': sha(BINARIES[arm])} for arm in ARMS},
        'input_bytes': sum(path.stat().st_size for path in INPUTS),
        'svg_bytes': len(reference[4]), 'svg_sha256': hashlib.sha256(reference[4]).hexdigest(),
        'samples': samples, 'median_ms': medians,
        'after_to_before': {'ratio': medians['after'] / medians['before'],
                            'reduction': 1 - medians['after'] / medians['before'],
                            'paired_bootstrap_95': [draws[100], draws[3899]]},
        'snapshot_limitation': 'before-guest was reconstructed from HEAD after editing began; every file was verified byte-identical to HEAD, but no independent copy of the initial dirty guest tree exists',
    }
    qualification = {
        'fixture': 'byte-identical', 'geometry': 'passed',
        'changed_net': 'byte-identical between arms, differs from fixture, geometry passed',
        'svg_bytes': len(reference[4]), 'svg_sha256': hashlib.sha256(reference[4]).hexdigest(),
        'transformed_cases': transformed_results,
    }
    (OUT / 'implementation-measurements.json').write_text(json.dumps(evidence, indent=2) + '\n')
    (OUT / 'implementation-qualification.json').write_text(json.dumps(qualification, indent=2) + '\n')
    print(json.dumps({'median_ms': medians, 'after_to_before': evidence['after_to_before']}, indent=2))


if __name__ == '__main__':
    main()
