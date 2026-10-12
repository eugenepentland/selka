#!/usr/bin/env python3
"""Prepare seven-arm trials: original C0, frozen common, candidate, references."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
loader = importlib.util.spec_from_file_location('prepare_candidate', HERE / 'prepare_candidate.py')
prepare = importlib.util.module_from_spec(loader)
loader.loader.exec_module(prepare)


def common_inputs(path):
    manifest = prepare.load(path)
    assert prepare.digest(manifest['compiler']) == manifest['compiler_sha256']
    entries = {}
    for kind in ('runtime', 'counted'):
        matches = [entry for entry in manifest['entries'] if entry['kind'] == kind]
        assert len(matches) == 1
        entries[kind] = {**prepare.verify(matches[0]), 'zero_rc': True}
        assert '--release' in entries[kind]['flags'] and '--experimental-zero-rc' in entries[kind]['flags']
        assert ('--counters' in entries[kind]['flags']) == (kind == 'counted')
    assert entries['runtime']['source_sha256'] == entries['counted']['source_sha256']
    files = {str(path.resolve()), manifest['compiler']}
    for file in manifest.get('installation_files', []):
        installed = Path(manifest['installation']) / file['path']
        assert prepare.digest(installed) == file['sha256']
        files.add(str(installed))
    for entry in entries.values():
        files.add(entry['source'])
        for index, flag in enumerate(entry['flags']):
            if flag == '--link':
                linked = entry['flags'][index + 1]
                assert prepare.digest(linked) == prepare.digest(prepare.ROOT / 'benchmarks/runtime/ports/native_clock.c')
                files.add(linked)
    return manifest, entries, files


def augment(spec, manifest, entries, files, manifest_path):
    assert entries['runtime']['source_sha256'] == spec['arms']['checked-baseline']['source_sha256']
    assert (spec['warmups'], spec['rounds'], spec['rss_rounds']) == (3, 15, 3)
    spec['arms'] = {'checked-baseline': spec['arms']['checked-baseline'],
                    'checked-common': entries['runtime'],
                    **{name: entry for name, entry in spec['arms'].items() if name != 'checked-baseline'}}
    spec['counted']['checked-common'] = entries['counted']
    spec['files'] = sorted(set(spec['files']) | files | {str(Path(__file__).resolve())})
    spec['provenance']['checked_common'] = {
        'manifest': str(manifest_path.resolve()), 'manifest_sha256': prepare.digest(manifest_path),
        'compiler_sha256': manifest['compiler_sha256'], 'source_commit': manifest.get('source_commit'),
        'meaning': 'Frozen common compiler; checked-baseline remains original C0.'}
    spec['provenance']['arm_order'] = list(spec['arms'])
    spec['provenance']['measurement_protocol'] = 'Seven arms; three warmups, fifteen rotated/reversed paired rounds, three separate RSS observations, separate counted binaries.'
    return spec


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', required=True)
    parser.add_argument('--common-manifest', type=Path, required=True)
    parser.add_argument('--candidate-runtime', type=Path, required=True)
    parser.add_argument('--candidate-counted', type=Path, required=True)
    parser.add_argument('--candidate-manifest', type=Path, required=True)
    args = parser.parse_args()
    manifest, entries, files = common_inputs(args.common_manifest)
    subprocess.run([sys.executable, '-B', str(HERE / 'prepare_candidate.py'), '--run', args.run,
                    '--candidate-runtime', str(args.candidate_runtime), '--candidate-counted', str(args.candidate_counted),
                    '--candidate-manifest', str(args.candidate_manifest)], check=True)
    for path in sorted((prepare.BENCH / 'runs' / args.run / 'specs').glob('*.json')):
        spec = augment(prepare.load(path), manifest, entries, files, args.common_manifest)
        path.write_text(json.dumps(spec, indent=2) + '\n')


if __name__ == '__main__':
    main()
