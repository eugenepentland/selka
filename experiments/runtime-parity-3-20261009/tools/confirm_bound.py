#!/usr/bin/env python3
"""Confirm prebuilt ladder bounds against X, checking every timed output.

Spec: {"name": ..., "expected_stdout_sha256": ..., "reference": "ladder",
       "arms": {"ladder": [binary, ...], "final": [binary, ...]}}.
This is an additive bound comparison; it never replaces full-corpus timing.
Rows must use the inherited startup-subtracted row method instead.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import time

from quiet import quiet


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--spec', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    spec = json.loads(args.spec.read_text())
    assert spec['reference'] in spec['arms'] and len(spec['arms']) >= 2
    hashes = {label: digest(argv[0]) for label, argv in spec['arms'].items()}
    samples = {label: [] for label in spec['arms']}
    rng = random.Random(20261010)
    affinity = os.sched_getaffinity(0)
    result = {'spec': spec, 'cpu': 10, 'rounds': 9, 'warmups': 2, 'binary_sha256': hashes, 'complete': False}
    try:
        with quiet():
            os.sched_setaffinity(0, {10})
            result['load_start'] = os.getloadavg()
            for round_index in range(11):
                order = list(spec['arms'])
                rng.shuffle(order)
                for label in order:
                    start = time.perf_counter_ns()
                    ran = subprocess.run(spec['arms'][label], capture_output=True, timeout=600)
                    elapsed = (time.perf_counter_ns() - start) / 1e9
                    assert ran.returncode == 0, (label, ran.returncode, ran.stderr[-2000:])
                    assert hashlib.sha256(ran.stdout).hexdigest() == spec['expected_stdout_sha256'], label
                    if round_index >= 2:
                        samples[label].append(elapsed)
            result['load_end'] = os.getloadavg()
    finally:
        os.sched_setaffinity(0, affinity)
    assert all(digest(spec['arms'][label][0]) == value for label, value in hashes.items())
    medians = {label: statistics.median(values) for label, values in samples.items()}
    result['arms'] = {label: {'samples_s': values, 'median_s': medians[label],
                             'ratio_to_reference': medians[label] / medians[spec['reference']]}
                      for label, values in samples.items()}
    result['all_outputs_match'] = result['complete'] = True
    args.out.write_text(json.dumps(result, indent=1) + '\n')
    print(spec['name'], {label: value['ratio_to_reference'] for label, value in result['arms'].items()})


if __name__ == '__main__':
    main()
