#!/usr/bin/env python3
"""Validate a complete row batch, freeze binary identities, and gzip its raw receipt."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path

S4 = {'tree_build_walk', 'record_pass', 'grid_dp', 'union_find', 'float_format', 'buffer_write'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('raw', type=Path)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    data = json.loads(args.raw.read_text())
    assert data['valid'] and data['rounds'] == 7 and data['cpu'] == 10 and len(data['rows']) == 46
    binaries = {}
    samples = 0
    for name, row in data['rows'].items():
        assert set(row['sizes']) == {'64', '4096'}
        for size, cell in row['sizes'].items():
            expected = {'old core --release', 'new core release', 'Rust', 'Zig ReleaseSafe', 'Go'}
            if name not in S4:
                expected.add('Zig ReleaseFast')
            assert set(cell['configurations']) == expected, (name, size)
            for label, arm in cell['configurations'].items():
                assert arm['cycles_per_unit'] > 0 and len(arm['runs']) == 7 and len(arm['startup']) == 3
                assert all(r['status'] == 0 and r['cycles'] > 0 and r['checksum'] == cell['checksum'] for r in arm['runs'])
                assert all(r['status'] == 0 and r['cycles'] > 0 for r in arm['startup'])
                samples += len(arm['runs'])
                command = arm['runs'][0]['command']
                binary = Path(command[command.index('cpu_core/cycles/u') + 1])
                if str(binary) not in binaries:
                    binaries[str(binary)] = digest(binary)
    assert samples == 3780 and len(binaries) == 126
    zipped = args.raw.with_suffix(args.raw.suffix + '.gz')
    with gzip.open(zipped, 'wb', compresslevel=9) as output:
        output.write(args.raw.read_bytes())
    receipt = {'valid': True, 'cpu': 10, 'rounds': 7, 'startup_rounds': 3, 'rows': 46,
               'size_cells': 92, 'timed_samples': samples, 'binaries_sha256': binaries,
               'speed_gate_misses': data['speed_gate_misses'], 'quiet_log_sha256': digest(args.log),
               'raw_gzip_sha256': digest(zipped)}
    args.out.write_text(json.dumps(receipt, indent=1) + '\n')
    args.raw.unlink()
    print(f'{args.raw.name}: {samples} checked timing samples, {len(binaries)} binaries; {zipped.stat().st_size} gzip bytes')


if __name__ == '__main__':
    main()
