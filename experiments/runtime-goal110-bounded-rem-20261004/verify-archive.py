#!/usr/bin/env python3
"""Replay archived raw identities, exact native pairs and timing intervals."""
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
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
import verify as expanded_verify


def digest(data):
    return hashlib.sha256(data).hexdigest()


def module(name):
    path = HERE / (name + '.py')
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), path)
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

    def raw(name):
        found = [data for path, data in files.items() if path.endswith('/' + name)]
        assert len(found) == 1, name
        return found[0]

    def document(name):
        return json.loads(raw(name))

    assert module('time-paired').replay(document('paired.json')) == 8
    assert module('time-paired-repeat').replay(document('paired-repeat.json')) == 4
    assert module('time-supplement').replay(document('supplement-timing.json')) == 96
    assert expanded_verify.verify(document('screen.json'), artifacts=args.live, focused=True) == 48
    assert module('qualify').verify(document('qualification.json')) == 720
    assert holdouts.verify(document('holdouts.json')) == 516
    pairs = [json.loads(line.split(' ', 1)[1]) for line in raw('unit-final.log').decode().splitlines()
             if line.startswith('BOUNDED-REMAINDER-OUTCOME ')]
    assert len(pairs) == 38
    for pair in pairs:
        assert pair['ordinary'] == pair['fast']
    semantic = document('actual-llvm-semantics.json')
    width = document('actual-llvm-width.json')
    groups = [semantic, *width['variants'].values()]
    assert sum(len(group['outcomes']) for group in groups) == 18
    for group in groups:
        for pair in group['outcomes']:
            assert pair['accounted']['run'] == pair['unaccounted']['run']
        if args.live:
            for build in group['builds'].values():
                assert digest(Path(build['binary']).read_bytes()) == build['binary_sha256']
                assert digest(Path(build['backend_manifest']).read_bytes()) == build['backend_manifest_sha256']
    source = document('source-readiness.json')
    receipt = document('compiler-receipt.json')
    assert source['source_revision'] == index['candidate_source_revision']
    assert receipt['source_revision'] == index['candidate_source_revision']
    assert set(index['production_sources']) == set(source['source_bindings'])
    for path, expected in source['source_bindings'].items():
        snapshot = gzip.decompress((HERE / index['production_sources'][path]).read_bytes())
        assert digest(snapshot) == expected
        if args.live:
            assert digest((Path(receipt['source_root']) / path).read_bytes()) == expected
    if args.live:
        manifest = document('runner/manifest.json')
        path = next(path for path in files if path.endswith('/runner/manifest.json'))
        holdouts.check_manifest(Path(path), digest(files[path]), manifest)
        supplement = document('supplement-build.json')
        for build in supplement['builds'].values():
            assert digest(Path(build['binary']).read_bytes()) == build['binary_sha256']
            assert digest(Path(build['backend_manifest']).read_bytes()) == build['backend_manifest_sha256']
    print(f"PASS {len(files)} raw archives,11 source snapshots,48 six-arm groups,38 native pairs,"
          '18 actual LLVM pairs,720 qualifications,516 holdouts,576 matched/supplement outcomes')


if __name__ == '__main__':
    main()
