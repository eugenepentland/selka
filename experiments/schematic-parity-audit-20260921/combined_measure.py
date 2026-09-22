#!/usr/bin/env python3
"""Qualify and time the production implementation against the retained baseline."""
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
WORK = ROOT / '.tmp/schematic-implementation-20260921'
OUT = Path(__file__).resolve().parent
FIXTURE = ROOT / 'experiments/schematic/fixtures'
INPUTS = [FIXTURE / name for name in
          ('straps-synth-lmx2595.sexp', 'lmx2595rhar.sexp', 'spi.sexp')]
BINARIES = {name: WORK / name for name in ('before-unit-o3', 'after-o3', 'after-lto')}
sys.path.insert(0, str(ROOT / 'tests'))
from schematic_layout import geometry


def invoke(name, arguments=('--max-steps=100000000',), first=None):
    output = WORK / 'combined.svg'
    issue = WORK / 'combined.issue'
    output.write_bytes(b'')
    issue.write_bytes(b'')
    environment = dict(os.environ,
                       MYLANG_SCHEMATIC_DECLARED='io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue',
                       MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
    paths = [first or INPUTS[0], *INPUTS[1:]]
    environment.update({f'MYLANG_SCHEMATIC_INPUT_{i}': str(path) for i, path in enumerate(paths)})
    start = time.perf_counter_ns()
    result = subprocess.run(['taskset', '-c', '6', str(BINARIES[name]),
                             '--print-result', *arguments], env=environment,
                            capture_output=True, timeout=60)
    elapsed = (time.perf_counter_ns() - start) / 1e6
    return elapsed, (result.returncode, result.stdout, result.stderr,
                     issue.read_bytes(), output.read_bytes())


def summary(result):
    return {'status': result[0], 'stdout': result[1].decode(),
            'stderr': result[2].decode(), 'issue': result[3].decode(),
            'svg_bytes': len(result[4]), 'svg_sha256': hashlib.sha256(result[4]).hexdigest()}


def main():
    arms = list(BINARIES)
    _, reference = invoke(arms[0])
    assert reference[:4] == (0, b'0\n', b'', b'')
    geometry(ET.fromstring(reference[4]))
    cases = {}
    for name, arguments in [('fixture', ('--max-steps=100000000',)),
                            ('gc-stress', ('--max-steps=100000000', '--gc-stress')),
                            ('step-limit', ('--max-steps=100',)),
                            ('frame-limit', ('--max-frames=3',))]:
        _, expected = invoke(arms[0], arguments)
        for arm in arms[1:]:
            _, actual = invoke(arm, arguments)
            assert actual == expected, (name, arm, summary(expected), summary(actual))
        cases[name] = summary(expected)
    for name, source in [('unclosed', '('), ('unexpected-close', ')'),
                         ('bad-escape', '"\\q"'), ('missing-model', '(bogus)'),
                         ('changed-net', INPUTS[0].read_text().replace('LMX_CE', 'LMX_CE_COMBINED'))]:
        path = WORK / f'combined-{name}.sexp'
        path.write_text(source)
        _, expected = invoke(arms[0], first=path)
        for arm in arms[1:]:
            _, actual = invoke(arm, first=path)
            assert actual == expected, (name, arm, summary(expected), summary(actual))
        if name == 'changed-net':
            assert expected[0] == 0 and expected[4] != reference[4]
            geometry(ET.fromstring(expected[4]))
        cases[name] = summary(expected)
    (OUT / 'combined-qualification.json').write_text(json.dumps(cases, indent=2) + '\n')
    randomizer = random.Random(20260921)
    samples = []
    for round_number in range(-3, 21):
        order = arms.copy()
        randomizer.shuffle(order)
        values = {}
        for arm in order:
            values[arm], actual = invoke(arm)
            assert actual == reference, (arm, summary(actual))
        if round_number >= 0:
            samples.append({'round': round_number, 'order': order, 'ms': values})
    medians = {arm: statistics.median(row['ms'][arm] for row in samples) for arm in arms}
    ratios = {}
    for arm in arms[1:]:
        draws = []
        for _ in range(4000):
            chosen = randomizer.choices(samples, k=len(samples))
            draws.append(statistics.median(row['ms'][arm] for row in chosen) /
                         statistics.median(row['ms'][arms[0]] for row in chosen))
        draws.sort()
        ratios[arm] = {'ratio': medians[arm] / medians[arms[0]],
                       'paired_bootstrap_95': [draws[100], draws[3899]]}
    evidence = {'configuration': 'LLVM O3 with ordinary checks, collecting GC, step and frame accounting',
                'scope': 'warm-cache process launch, input read, SVG generation to private file, shutdown; compilation excluded',
                'cpu': 6, 'rounds': 21, 'warmups': 3, 'seed': 20260921,
                'binaries': {name: {'path': str(path.relative_to(ROOT)),
                                    'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                             for name, path in BINARIES.items()},
                'median_ms': medians, 'ratios_to_baseline': ratios, 'samples': samples}
    (OUT / 'combined-measurements.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({'median_ms': medians, 'ratios_to_baseline': ratios}, indent=2))


if __name__ == '__main__':
    main()
