#!/usr/bin/env python3
"""Replay successor source snapshots, outcomes, qualification and ELF identity."""
import argparse
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts


def digest(data):
    return hashlib.sha256(data).hexdigest()


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), HERE / (name + '.py'))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--live', action='store_true')
    args = parser.parse_args()
    index = json.loads((HERE / 'archive-index.json').read_text())
    files = {}
    for entry in index['files']:
        packed = (HERE / entry['archive_path']).read_bytes()
        raw = gzip.decompress(packed)
        assert digest(packed) == entry['gzip_sha256']
        assert digest(raw) == entry['raw_sha256'] and len(raw) == entry['raw_bytes']
        assert entry['original_path'] not in files
        files[entry['original_path']] = raw
        if args.live:
            assert digest(Path(entry['original_path']).read_bytes()) == entry['raw_sha256']

    def document(name):
        matches = [raw for path, raw in files.items() if path.endswith('/' + name)]
        assert len(matches) == 1, name
        return json.loads(matches[0])

    source, compiler = document('source-readiness.json'), document('compiler-receipt.json')
    assert source['source_revision'] == compiler['source_revision'] == index['source_revision']
    assert set(source['source_bindings']) == set(index['production_sources'])
    for path, expected in source['source_bindings'].items():
        assert digest(gzip.decompress((HERE / index['production_sources'][path]).read_bytes())) == expected
        if args.live:
            assert digest((Path(compiler['source_root']) / path).read_bytes()) == expected
    logs = [raw for path, raw in files.items() if path.endswith('/unit-final.log')]
    assert len(logs) == 1
    pairs = [json.loads(line.split(' ', 1)[1]) for line in logs[0].decode().splitlines()
             if line.startswith('BOUNDED-REMAINDER-OUTCOME ')]
    assert len(pairs) == 38 and all(pair['ordinary'] == pair['fast'] for pair in pairs)
    assert source['focused_tests'] == dict(passed=58, failed=0, actual_exit_status=0)
    assert source['guardian'] == dict(passed=88, actual_exit_status=0)
    assert module('qualify').verify(document('qualification.json')) == 720
    assert holdouts.verify(document('holdouts.json')) == 516
    comparison = module('compare-executables')
    identity = document('executable-equivalence.json')
    assert identity['status'] == 'pass' and identity['script_sha256'] == digest((HERE / 'compare-executables.py').read_bytes())
    assert len(identity['rows']) == 8
    assert {(r['group'], r['backend']) for r in identity['rows']} == {
        (group, backend) for group in comparison.GROUPS for backend in ('llvm', 'qbe')}
    for row in identity['rows']:
        assert set(row['mapped_header_only_differences']) <= set(range(40, 48))
        if args.live:
            actual = comparison.compare(Path(row['before_path']), Path(row['after_path']))
            expected = {key: value for key, value in row.items() if key not in ('group', 'backend')}
            assert json.loads(json.dumps(actual)) == expected
    if args.live:
        manifest = document('runner/manifest.json')
        path = next(path for path in files if path.endswith('/runner/manifest.json'))
        holdouts.check_manifest(Path(path), digest(files[path]), manifest)
    print(f"PASS {len(files)} raw archives,11 source snapshots,38 native pairs,720 qualifications,"
          '516 holdouts,eight exact runtime images; no new timing')


if __name__ == '__main__':
    main()
