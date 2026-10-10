#!/usr/bin/env python3
"""Time qualified parity programs without a Zig reference, using the same timer.

The native runner skips these after qualification. This additive adapter keeps
all recorded native results and records absolute timing, with no invented peer.
In paired runs both compilers are interleaved within every round.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import statistics

import parity_locked as locked


def complete(data, work, bp):
    registry = {bench['name']: bench for bench in bp.discover([])}
    groups = []
    for name, entry in data['benchmarks'].items():
        if any(arm['arm'] == bp.REFERENCE for arm in bp.arms_for(registry[name]['ports'])):
            continue
        assert entry.get('failure') == 'no qualified ' + bp.REFERENCE, name
        jobs = []
        for label, arm in entry['arms'].items():
            assert arm['build']['ok'] and arm['status'] == 0 and arm['matches_expected']
            assert 'wall' not in arm, 'refuse to replace an existing measurement'
            binary = work / 'bin' / (name + '.' + label)
            assert hashlib.sha256(binary.read_bytes()).hexdigest() == arm['binary_sha256']
            stdout, status = bp.run_captured(binary)
            assert status == 0 and stdout == registry[name]['expected'], (name, label)
            jobs.append({'bench': name, 'arm': label, 'bin': binary})
        groups.append((name, jobs))
    assert groups, 'no qualified standalone program needs timing'
    opts = argparse.Namespace(rounds=data['rounds'], warmups=data['warmups'])
    assert opts.rounds == 9 and opts.warmups == 2
    rng = random.Random(20261009)
    original_timer = bp.run_timed

    def checked_timer(binary):
        wall, cpu, status = original_timer(binary)
        assert status == 0 and wall > 0 and cpu > 0, (binary, status)
        return wall, cpu, status

    bp.run_timed = checked_timer
    try:
        with bp.Pinned(data['cpu']):
            load_start = os.getloadavg()
            for name, jobs in groups:
                sibling_cpus = bp.siblings(data['cpu'])
                before = bp.cpu_times(sibling_cpus)
                samples = bp.measure(jobs, opts, rng)
                entry = data['benchmarks'][name]
                entry['sibling_busy'] = bp.busy_fraction(before, bp.cpu_times(sibling_cpus))
                for label, sample in samples.items():
                    entry['arms'][label].update(wall=sample['wall'], cpu=sample['cpu'],
                        wall_median=statistics.median(sample['wall']), cpu_median=statistics.median(sample['cpu']))
                    if 'base-my' in samples:
                        entry['arms'][label]['ratio_base'] = bp.paired(sample['wall'], samples['base-my']['wall'])
                entry['reference_unavailable'] = entry.pop('failure')
                entry['rp3_standalone'] = True
            load_end = os.getloadavg()
    finally:
        bp.run_timed = original_timer
    for name, jobs in groups:
        for job in jobs:
            stdout, status = bp.run_captured(job['bin'])
            assert status == 0 and stdout == registry[name]['expected'], (name, job['arm'])
    data['rp3_standalone_timing'] = {'programs': [name for name, _ in groups],
        'load_start': load_start, 'load_end': load_end, 'rounds': opts.rounds, 'warmups': opts.warmups,
        'method': 'Native run_timed/measure, output checked before and after; all timed exits checked. No reference ratio is fabricated.'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    assert args.input.resolve() != args.output.resolve(), 'preserve the original runner receipt'
    allowed = os.sched_getaffinity(0) - {2, 3, 10, 11}
    assert allowed
    os.sched_setaffinity(0, allowed)
    data = json.loads(args.input.read_text())
    data['rp3_native_receipt'] = {'path': str(args.input), 'sha256': hashlib.sha256(args.input.read_bytes()).hexdigest()}
    try:
        complete(data, args.work.resolve(), locked.bp)
        args.output.write_text(json.dumps(data, indent=1) + '\n')
    finally:
        for guard in reversed(locked.held):
            guard.__exit__(None, None, None)
    print('standalone timing complete; every native result retained')


if __name__ == '__main__':
    main()
