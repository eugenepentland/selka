#!/usr/bin/env python3
"""Make deterministic Guardian shard assignments from observed native test times.

Weights are per-test medians from at least three distinct observed runs.
This is a scheduling hint, never evidence of test success. Unknown tests retain
Guardian's named-position modulo fallback; unnamed blocks remain in shard zero.
Only assignments enter the plan, so timing noise that preserves the partition
cannot invalidate a cached run. Pass the plan to the run step with addFileArg.
"""
import argparse
import hashlib
import heapq
import json
from pathlib import Path


def observations(document, root):
    """Largest observed interval for each named test in a complete native member."""
    times = {}
    prefix = root + '::'
    for action in document['actions']:
        for member in action.get('test_telemetry', []):
            if (member.get('producer') != 'zig-test-protocol-v1'
                    or member.get('status') != 'observed' or member.get('complete') is not True):
                continue
            for row in member.get('tests', []):
                identity, ns = row.get('test_id', ''), row.get('elapsed_ns')
                if not isinstance(identity, str) or not identity.startswith(prefix):
                    continue
                name = identity[len(prefix):]
                if ('.test.' not in name or row.get('state') != 'passed'
                        or type(ns) is not int or ns < 0
                        or row.get('elapsed_scope') != 'runner-protocol-interval'):
                    continue
                times[name] = max(times.get(name, 0), ns)
    return times


def median_observations(documents, root):
    """Require three independent samples for each hint; sparse tests fall back.

    Repeated appearances inside one report are one observation, not extra runs.
    For an even sample count, round the exact integer midpoint down to ns.
    """
    if len(documents) < 3:
        raise ValueError('shard weights require at least three distinct reports')
    samples = {}
    for document in documents:
        for name, ns in observations(document, root).items():
            samples.setdefault(name, []).append(ns)
    times = {}
    for name, values in samples.items():
        if len(values) < 3:
            continue
        values.sort()
        middle = len(values) // 2
        times[name] = (values[middle] if len(values) % 2
                       else (values[middle - 1] + values[middle]) // 2)
    return times, dict(reports=len(documents), minimum_samples=3,
                       samples_per_test={name: len(samples[name]) for name in sorted(times)},
                       insufficient_samples=sorted(set(samples) - set(times)))


def assign(times, shards, root):
    """LPT partition with stable name/shard tie breaks; no duration in the plan."""
    if type(shards) is not int or not 1 <= shards <= 1024:
        raise ValueError('shards must be in 1..1024')
    if any(not isinstance(name, str) or '.test.' not in name
           or type(ns) is not int or ns < 0 for name, ns in times.items()):
        raise ValueError('expected named tests and nonnegative integer durations')
    queue = [(0, index) for index in range(shards)]
    heapq.heapify(queue)
    placement = {}
    for name, ns in sorted(times.items(), key=lambda item: (-item[1], item[0])):
        total, index = heapq.heappop(queue)
        placement[name] = index
        heapq.heappush(queue, (total + ns, index))
    loads = [0] * shards
    for total, index in queue:
        loads[index] = total
    largest = max(times.values(), default=0)
    denominator = max(largest, sum(loads) / shards)
    plan = dict(version=1, root=root, shards=shards,
                tests=[dict(name=name, shard=placement[name]) for name in sorted(placement)])
    summary = dict(root=root, shards=shards, observed_named_tests=len(times),
                   predicted_shard_ns=loads, largest_test_ns=largest,
                   longest_first=sorted(range(shards), key=lambda index: (-loads[index], index)),
                   max_to_lower_bound=max(loads) / denominator if denominator else None,
                   scope='historical runner intervals; predicted, not measured shard walls')
    return plan, summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path, nargs='+', help='at least three distinct verification last-run.json reports')
    parser.add_argument('--root', required=True, help='root identity, e.g. src/root_test.zig')
    parser.add_argument('--shards', required=True, type=int)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    try:
        contents = [path.read_bytes() for path in args.report]
        hashes = [hashlib.sha256(content).hexdigest() for content in contents]
        if len(set(hashes)) != len(hashes):
            raise ValueError('duplicate reports do not count as independent observations')
        times, samples = median_observations([json.loads(content) for content in contents], args.root)
        plan, summary = assign(times, args.shards, args.root)
        summary.update(samples, report_sha256=hashes, weighting='per-test median; even midpoint rounded down to ns')
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(plan, sort_keys=True, indent=2) + '\n')
    print(json.dumps(summary, sort_keys=True))


if __name__ == '__main__':
    main()
