#!/usr/bin/env python3
"""Inspect on-disk block encodings in quiescent paired benchmark caches."""
import argparse
import json
from pathlib import Path
import struct

MAGIC = b'mylang-pack-v1!\n\0'
HEADER = len(MAGIC) + 72


def inspect(directory):
    result = dict(packs=0, records=0, raw_blocks=0, zlib_blocks=0,
                  encoded_bytes=0, plain_bytes=0)
    identities = set()
    for path in sorted(directory.glob('*.pack')):
        size = path.stat().st_size
        with path.open('rb') as stream:
            header = stream.read(HEADER)
            assert len(header) == HEADER and header.startswith(MAGIC), path
            identities.add(header[len(MAGIC):len(MAGIC) + 32].hex())
            index_length, = struct.unpack_from('<Q', header, len(MAGIC) + 32)
            assert 16 <= index_length <= 32 << 20, path
            index = stream.read(index_length)
            assert len(index) == index_length, path
            blocks, = struct.unpack_from('<Q', index)
            record_offset = 8 + blocks * 48
            records, = struct.unpack_from('<Q', index, record_offset)
            assert index_length == record_offset + 8 + records * 88, path
            for number in range(blocks):
                offset, encoded, plain = struct.unpack_from('<QII', index, 8 + number * 48)
                assert HEADER + index_length <= offset < size, path
                assert 1 <= encoded <= size - offset, path
                stream.seek(offset)
                marker = stream.read(1)
                assert marker in (b'\0', b'\1'), (path, number, marker)
                if marker == b'\0':
                    assert encoded == plain + 1, path
                result['raw_blocks' if marker == b'\0' else 'zlib_blocks'] += 1
                result['encoded_bytes'] += encoded
                result['plain_bytes'] += plain
            result['records'] += records
            result['packs'] += 1
    assert result['packs'] > 0, directory
    assert not list(directory.glob('*.journal')), directory
    assert len(identities) == 1, identities
    result['compiler_identity'] = identities.pop()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('benchmark', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = json.loads((args.benchmark / 'results.json').read_text())
    assert 'completed_utc' in report
    result = {'benchmark': str(args.benchmark.resolve()),
              'method': 'Header/index bounds and encoding-marker inspection after all edits. '
                        'Does not independently validate BLAKE3 checksums or decode payloads; '
                        'compiler reads and focused tests perform those checks.', 'caches': {}}
    for copies in report['sizes']:
        for variant, policy in report['cache_compression'].items():
            row = inspect(args.benchmark / copies / variant / 'cache/stages-packed-v1')
            if policy == 'none':
                assert row['zlib_blocks'] == 0
            else:
                assert row['zlib_blocks'] > 0
            result['caches'][f'{copies}/{variant}'] = row
    assert len({row['compiler_identity'] for row in result['caches'].values()}) == 1
    args.output.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
