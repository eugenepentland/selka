#!/usr/bin/env python3
"""Qualify embedded numeric-object invalidation and repair using private cache files.

The preserved C0 object is read-only input. This script proves candidate behavior,
not successful execution of the Unicode fixture on an old compiler.
"""
import argparse
import json
from pathlib import Path
import shutil
from types import SimpleNamespace

import qualify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--old-object-provenance', type=Path, required=True)
    parser.add_argument('--default-zero', action='store_true')
    parser.add_argument('--admission', choices=('build', 'held'), default='build')
    args = parser.parse_args()
    proof = json.loads(args.old_object_provenance.read_text())
    if len(proof['objects']) != 1:
        parser.error('Select exactly one preserved numeric object')
    old = proof['objects'][0]
    old_path = Path(old['path'])
    if qualify.digest(old_path) != old['sha256']:
        parser.error('Preserved object bytes changed')
    compiler_bytes = Path(proof['compiler']).read_bytes()
    if qualify.digest(proof['compiler']) != proof['compiler_sha256']:
        parser.error('Preserved compiler identity changed')
    start = old['offset_in_C0_compiler']
    if compiler_bytes[start:start + old['bytes']] != old_path.read_bytes():
        parser.error('Preserved object no longer matches embedded C0 bytes')
    settings = SimpleNamespace(**vars(args), candidate=None, candidate_revision=None,
                               candidate_default_zero=False, memory_wrapper=None, timeout=120)
    settings.compiler = settings.compiler.resolve()
    settings.zig = settings.zig.resolve()
    run = qualify.Run(settings)
    objects = run.work / 'objects'
    objects.mkdir()
    private_old = objects / old_path.name
    shutil.copyfile(old_path, private_old)
    project = run.work / 'numeric-source'
    fixture = Path(__file__).with_name('numeric-abi.my')
    qualify.write(project / 'main.my', fixture.read_text())
    expected = 'ééé1.25ééé\n10 é\n'
    audit = dict(harness_sha256=qualify.digest(__file__), fixture_sha256=qualify.digest(fixture),
                 baseline_provenance=proof, baseline_provenance_sha256=qualify.digest(args.old_object_provenance),
                 candidate_revision=args.source_revision, candidate_compiler_sha256=qualify.digest(args.compiler),
                 scope='Embedded numeric object key/byte validation plus Unicode behavior; old fixture execution is not claimed.',
                 checks={})
    qualify.write(run.out / 'object-audit.json', json.dumps(audit, indent=2) + '\n')
    first = run.build('numeric-first-over-old-object', project, expected=expected)
    new_paths = [path for path in objects.glob('core_number_text-*.o') if path.name != old_path.name]
    audit['checks']['first_build_passed'] = first['passed']
    audit['checks']['one_distinct_candidate_object'] = len(new_paths) == 1
    if len(new_paths) == 1:
        new = new_paths[0]
        expected_hash = qualify.digest(new)
        audit['candidate_object'] = dict(name=new.name, sha256=expected_hash, bytes=new.stat().st_size)
        audit['checks']['candidate_bytes_differ'] = expected_hash != old['sha256']
        run.build('numeric-receipt', project, expected=expected, emit=False)
        run.build('numeric-replay', project, expected=expected, emit=False)
        # Only a disposable candidate cache entry is damaged. Emitting LLVM
        # suppresses whole-build replay and reaches number_runtime.object.
        shutil.copyfile(private_old, new)
        repaired = run.build('numeric-stale-bytes-repaired', project, expected=expected)
        audit['checks']['stale_bytes_repaired'] = repaired['passed'] and qualify.digest(new) == expected_hash
    audit['checks']['preserved_input_unchanged'] = qualify.digest(old_path) == old['sha256']
    audit['checks']['private_old_unchanged'] = qualify.digest(private_old) == old['sha256']
    audit['all_passed'] = all(audit['checks'].values()) and all(row['passed'] for row in run.rows)
    qualify.write(run.out / 'object-audit.json', json.dumps(audit, indent=2) + '\n')
    raise SystemExit(0 if audit['all_passed'] else 1)


if __name__ == '__main__':
    main()
