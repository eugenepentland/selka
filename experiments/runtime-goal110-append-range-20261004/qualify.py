#!/usr/bin/env python3
"""Run the frozen expanded qualification cells and discard every elapsed value."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
import run as expanded
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify(report):
    assert report['schema'] == 'mylang-runtime-sort-qualification-v1'
    assert report['status'] == 'correctness_complete'
    assert report['edge_probes'] == [list(probe) for probe in expanded.EDGE_PROBES]
    assert report['arms'] == list(expanded.ARMS)
    expected = {(case, size, seed, iterations, arm) for case in expanded.inventory()
                for size, seed, iterations in expanded.EDGE_PROBES for arm in expanded.ARMS}
    seen = set()
    for row in report['checks']:
        key = tuple(row[name] for name in ('case', 'size', 'seed', 'iterations', 'arm'))
        assert key in expected and key not in seen
        seen.add(key)
        value = expanded.checksum(key[0], key[1], key[3], key[2])
        assert type(row['checksum']) is int and row['checksum'] == row['expected_checksum'] == value
        assert row['exit_status'] == 0 and row['clock_protocol_validated'] is True
        assert not any(name in row for name in ('kernel_ns', 'process_wall_ns', 'elapsed_ns'))
    assert seen == expected
    return len(seen)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--cpu', type=int, default=4)
    parser.add_argument('--verify', type=Path)
    args = parser.parse_args()
    if args.verify:
        print('PASS qualification replay: ' + str(verify(json.loads(args.verify.read_text()))) + ' cells')
        return
    if args.manifest is None or args.output is None:
        parser.error('--manifest and --output required')
    path = args.manifest.resolve()
    manifest_hash = digest(path)
    manifest = json.loads(path.read_text())
    holdouts.check_manifest(path, manifest_hash, manifest)
    report = {'schema': 'mylang-runtime-sort-qualification-v1', 'status': 'correctness_in_progress',
              'purpose': 'Frozen checksum qualification only; elapsed values discarded; no performance evidence',
              'manifest_path': str(path), 'manifest_sha256': manifest_hash,
              'identity': manifest['identity'], 'binary_hashes': manifest['binary_hashes'],
              'helper_sha256': digest(__file__), 'cpu': args.cpu, 'edge_probes': expanded.EDGE_PROBES,
              'arms': list(expanded.ARMS), 'checks': [], 'started_utc': datetime.now(timezone.utc).isoformat()}
    for case, metadata in expanded.inventory().items():
        print('Qualifying ' + case, flush=True)
        for size, seed, iterations in expanded.EDGE_PROBES:
            for arm in expanded.ARMS:
                binary = Path(manifest['identity']['binary_paths'][metadata['group'] + '/' + arm])
                expected = expanded.checksum(case, size, iterations, seed)
                result = expanded.common.invoke(binary, case, size, iterations, seed, args.cpu, expected)
                result.pop('kernel_ns')
                result.pop('process_wall_ns')
                report['checks'].append({'case': case, 'size': size, 'seed': seed, 'iterations': iterations,
                                         'arm': arm, 'expected_checksum': expected, 'clock_protocol_validated': True,
                                         **result})
    holdouts.check_manifest(path, manifest_hash, manifest)
    assert report['helper_sha256'] == digest(__file__)
    report.update(status='correctness_complete', finished_utc=datetime.now(timezone.utc).isoformat())
    count = verify(json.loads(json.dumps(report)))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as output:
        output.write(json.dumps(report, indent=2) + '\n')
    print('PASS untimed qualification: ' + str(count) + ' cells')


if __name__ == '__main__':
    main()
