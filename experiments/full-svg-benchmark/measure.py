#!/usr/bin/env python3
"""Qualify, then time actual NetLisp and mylang source-to-SVG implementations.

This is an implementation comparison, not a matched-algorithm language test.
Each process starts fresh; input reads, evaluation/validation, layout/routing,
SVG serialization, private-file output and process shutdown are timed.
Compilation, Python preparation and output verification are outside the timer.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import re
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/full-svg-benchmark-20260921'
# The three native arms are byte-identical ports of the mylang guest built by
# build_native.py: Rust and Zig at -O3 (opt-level=3 and ReleaseFast) and Go at
# its default optimizing compilation. They take the three documents and the
# output path as arguments instead of the mylang host's environment contract,
# and read each document once instead of through io.byte.
NATIVE_ARMS = ('rust-o3', 'go-fast', 'zig-o3')
# The ratio base for the matched-algorithm comparison: the fastest arm that runs
# the mylang guest's own algorithm and produces its exact SVG bytes.
NATIVE_REFERENCE = 'zig-o3'
ARMS = ('netlisp-llvm-fast', 'netlisp-llvm-safe', 'mylang-o3',
        'mylang-o3-lto', 'mylang-o3-bounded') + NATIVE_ARMS
CASES = ('fixture', 'changed-net', 'changed-value')
DOCUMENTS = ('lib/modules/straps-synth-lmx2595.sexp',
             'lib/pinouts/lmx2595rhar.sexp', 'lib/interfaces/spi.sexp')
CPU = 6
SEED = 20260921
GUEST_IO = ROOT / 'src/schematic/guest/io.my'


def declared_hosts():
    """The host functions the schematic guest declares, as the runtime wants them.

    The launcher registers exactly the names it is handed, so this list has to
    follow the guest rather than a copy of it: when the bulk-I/O host calls were
    added to io.my, the hardcoded list here named seven of eleven and every
    mylang arm trapped HostMissingRegistration.  Reading the declarations keeps
    the harness correct across guest changes; an empty result is an error rather
    than a silently empty contract.
    """
    names = re.findall(r'^(?:public )?host def ([a-z_][a-z0-9_]*)',
                       GUEST_IO.read_text(), re.M)
    if not names:
        raise SystemExit(f'no host declarations found in {GUEST_IO}')
    return ','.join(f'io::{name}' for name in names)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def command(arm, case, extra=()):
    project = WORK / 'projects' / case
    output = WORK / f'{arm}.svg'
    issue = WORK / f'{arm}.issue'
    output.write_bytes(b'')
    issue.write_bytes(b'')
    environment = dict(os.environ)
    # Keep user machine configuration unchanged, while excluding unrelated
    # library overrides from the benchmark's frozen dependency closure.
    for key in ('NETLISP_LIB_DIR', 'NETLISP_STDLIB_DIR'):
        environment.pop(key, None)
    args = ['taskset', '-c', str(CPU), str(WORK / arm)]
    if arm.startswith('netlisp'):
        args += [str(project), 'straps-synth-lmx2595', str(output), *extra]
    elif arm in NATIVE_ARMS:
        args += [str(project / path) for path in DOCUMENTS]
        args += [str(output), *extra]
    else:
        environment.update(
            MYLANG_SCHEMATIC_DECLARED=declared_hosts(),
            MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
        environment.update({f'MYLANG_SCHEMATIC_INPUT_{i}': str(project / path)
                            for i, path in enumerate(DOCUMENTS)})
        args += ['--print-result']
        if arm == 'mylang-o3-bounded':
            args += ['--max-steps=100000000']
        args += list(extra)
    return args, environment, output, issue


def invoke(arm, case, extra=(), memory=False):
    args, environment, output, issue = command(arm, case, extra)
    rss_file = WORK / 'rss.txt'
    if memory:
        args = ['/usr/bin/time', '-f', '%M', '-o', str(rss_file), *args]
    start = time.perf_counter_ns()
    result = subprocess.run(args, env=environment, capture_output=True,
                            timeout=60, cwd=ROOT)
    elapsed = (time.perf_counter_ns() - start) / 1e6
    expected_stdout = b'' if arm.startswith('netlisp') or arm in NATIVE_ARMS else b'0\n'
    assert (result.returncode, result.stdout, result.stderr, issue.read_bytes()) == (
        0, expected_stdout, b'', b''), (arm, case, result, issue.read_bytes())
    svg = output.read_bytes()
    assert svg, (arm, case, 'empty SVG')
    return elapsed, svg, int(rss_file.read_text()) if memory else None


def percentile(values, proportion):
    ordered = sorted(values)
    point = (len(ordered) - 1) * proportion
    lower = int(point)
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (point - lower)


def ratios_to(relevant, medians, base, randomizer):
    """Paired-bootstrap ratio of every arm to `base` over the same rounds."""
    ratios = {}
    for arm in ARMS:
        if arm == base:
            continue
        bootstrap = []
        for _ in range(4000):
            sample = randomizer.choices(relevant, k=len(relevant))
            bootstrap.append(statistics.median(r['ms'][arm] for r in sample) /
                             statistics.median(r['ms'][base] for r in sample))
        ratios[arm] = {'ratio': medians[arm] / medians[base],
                       'paired_bootstrap_95': [percentile(bootstrap, .025),
                                                percentile(bootstrap, .975)]}
    return ratios


def summarize(rows, case):
    relevant = [r for r in rows if r['case'] == case]
    medians = {arm: statistics.median(r['ms'][arm] for r in relevant) for arm in ARMS}
    randomizer = random.Random(SEED)
    return {'median_ms': medians,
            'p10_p90_ms': {arm: [percentile([r['ms'][arm] for r in relevant], .1),
                                 percentile([r['ms'][arm] for r in relevant], .9)]
                            for arm in ARMS},
            'ratios_to_netlisp_fast': ratios_to(relevant, medians, ARMS[0], randomizer),
            'ratios_to_zig_o3': ratios_to(relevant, medians, NATIVE_REFERENCE, randomizer)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rounds', type=int, default=31)
    parser.add_argument('--warmups', type=int, default=3)
    args = parser.parse_args()
    qualification = json.loads((OUT / 'qualification.json').read_text())
    assert qualification['passed']
    expected = {}
    for case in CASES:
        for arm in ARMS:
            _, svg, _ = invoke(arm, case)
            expected[case, arm] = digest(svg)
            assert expected[case, arm] == qualification['cases'][case][arm]['svg_sha256']
    # The harness, all guest binaries, and both Zig builds are finished before
    # entering this loop. No build or qualification work runs concurrently.
    randomizer = random.Random(SEED)
    rows = []
    for round_number in range(-args.warmups, args.rounds):
        cases = list(CASES)
        randomizer.shuffle(cases)
        for case in cases:
            order = list(ARMS)
            randomizer.shuffle(order)
            values = {}
            for arm in order:
                values[arm], svg, _ = invoke(arm, case)
                assert digest(svg) == expected[case, arm], (round_number, arm, case)
            if round_number >= 0:
                rows.append({'round': round_number, 'case': case,
                             'order': order, 'ms': values})
    rss = {}
    for case in CASES:
        rss[case] = {}
        for arm in ARMS:
            samples = []
            for _ in range(5):
                _, svg, peak = invoke(arm, case, memory=True)
                assert digest(svg) == expected[case, arm]
                samples.append(peak)
            rss[case][arm] = {'peak_rss_kib': samples,
                              'median_peak_rss_kib': statistics.median(samples)}
    evidence = {
        'schema': 'actual-netlisp-full-svg-v2', 'cpu': CPU, 'seed': SEED,
        'rounds': args.rounds, 'warmups': args.warmups,
        'scope': 'warm-filesystem-cache fresh-process source-to-SVG to private file; includes launch/read/evaluate-or-validate/layout/route/serialize/write/shutdown; excludes compile/HTTP/HTML/ERC-review/browser/parent mylang driver',
        'comparison': ('mylang and the rust-o3/go-fast/zig-o3 ports run one algorithm and '
                       'produce identical SVG bytes, so their differences are language, '
                       'runtime, codegen and host-interface cost; netlisp is a different '
                       'engine with different algorithms and output and is not matched'),
        'native_arms': list(NATIVE_ARMS),
        'binaries': {arm: {'path': str((WORK / arm).relative_to(ROOT)),
                            'bytes': (WORK / arm).stat().st_size,
                            'sha256': digest((WORK / arm).read_bytes())}
                     for arm in ARMS},
        'summary': {case: summarize(rows, case) for case in CASES},
        'samples': rows,
    }
    (OUT / 'measurements.json').write_text(json.dumps(evidence, indent=2) + '\n')
    (OUT / 'memory.json').write_text(json.dumps(rss, indent=2) + '\n')
    print(json.dumps(evidence['summary'], indent=2))


if __name__ == '__main__':
    main()
