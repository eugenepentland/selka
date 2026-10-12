#!/usr/bin/env python3
"""Archive one immutable size-aligned counted run, preserving every outcome."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('refusing to overwrite an evidence archive')
    results = json.loads((args.input / 'results.json').read_text())
    args.output.mkdir(parents=True)
    shutil.copy2(args.input / 'results.json', args.output / 'results.json')
    records = {}

    def compressed(path, relative):
        raw = path.read_bytes()
        packed = gzip.compress(raw, mtime=0)
        output = args.output / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(packed)
        records[str(relative)] = {'compressed_sha256': hashlib.sha256(packed).hexdigest(),
                                  'uncompressed_sha256': hashlib.sha256(raw).hexdigest()}

    for path in sorted(args.input.glob('*.json')):
        if path.name != 'results.json':
            compressed(path, Path('metadata') / (path.name + '.gz'))
    for group in results['groups']:
        name = group['cases'][0]['id']
        directory = args.input / name
        for path in sorted(directory.rglob('*')):
            if path.is_file() and path.suffix in ('.json', '.ll', '.stdout', '.stderr'):
                compressed(path, Path(name) / (str(path.relative_to(directory)) + '.gz'))
        case = group['cases'][0]
        source = Path(case['source'])
        for filename, expected in case['source_inputs_sha256'].items():
            path = source.parent / filename
            if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                raise ValueError('source changed after counted execution: ' + str(path))
            compressed(path, Path(name) / 'sources' / (filename + '.gz'))
    (args.output / 'archive.json').write_text(json.dumps({'files': records,
        'scope': 'Exact source/LLVM/command/counter evidence; results retain all passed and failed cases.',
        'original_results_sha256': hashlib.sha256((args.input / 'results.json').read_bytes()).hexdigest()}, indent=2) + '\n')
    print(f'archived {len(records)} files')


if __name__ == '__main__':
    main()
