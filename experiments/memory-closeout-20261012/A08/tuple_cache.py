#!/usr/bin/env python3
"""Actual generic tuple-unpack cache contracts after producer/Core integration.

Prepared source qualification only until run against an exact integrated compiler.
Reuse is reported by the compiler; matching output alone is not a cache-hit claim.
"""
import argparse
import json
from pathlib import Path
import shutil

import qualify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--admission', choices=('build', 'held'), default='build')
    parser.add_argument('--default-zero', action='store_true')
    parser.add_argument('--timeout', type=int, default=120)
    args = parser.parse_args()
    if args.work.exists() or args.output.exists():
        parser.error('Choose fresh work and evidence paths')
    args.compiler = args.compiler.resolve()
    args.zig = args.zig.resolve()
    args.candidate = None
    args.candidate_revision = None
    args.candidate_default_zero = False
    args.memory_wrapper = None
    run = qualify.Run(args)
    fixture = Path(__file__).with_name('tuple-source-cache') / 'main.my'
    original = fixture.read_text()
    project = run.work / 'source'
    qualify.write(project / 'main.my', original)
    expected = 'tuple-generic generic-9 3 2 8\n'
    for phase in ('cold', 'warm', 'receipt', 'replay'):
        run.build('tuple-' + phase, project, expected=expected, emit=phase in ('cold', 'warm'))
    relocated = run.work / 'relocated'
    shutil.copytree(project, relocated, ignore=shutil.ignore_patterns('cache'))
    run.build('tuple-relocated-cold', relocated, expected=expected)
    run.build('tuple-relocated-warm', relocated, expected=expected)
    prefix = 'record Earlier:\n    labels: bytes[]\nfunc earlier() -> Earlier:\n    return Earlier(labels=[b"a"])\n'
    edited = prefix + original.replace('    const text_pair', '    const before = earlier()\n    assert len(before.labels) == 1\n    const text_pair', 1)
    qualify.write(project / 'main.my', edited)
    run.build('tuple-declaration-edit-cold', project, expected=expected)
    run.build('tuple-declaration-edit-warm', project, expected=expected)
    valid = edited.replace('first((8, 0))', 'first((9, 0))')
    qualify.write(project / 'main.my', valid)
    run.build('tuple-valid-edit', project, expected=expected.replace(' 8\n', ' 9\n'))
    invalid = original.replace('    const original_rows, _ = rows_pair', '    const original_rows, _ = rows_pair\n    const repeated, _ = rows_pair\n    assert len(repeated) == 2', 1)
    qualify.write(project / 'main.my', invalid)
    run.build('tuple-invalid-edit-warm', project, refuse='E_SINGLE_OWNER_MOVED', emit=False)
    cold = run.work / 'invalid-cold'
    qualify.write(cold / 'main.my', invalid)
    run.build('tuple-invalid-edit-cold', cold, refuse='E_SINGLE_OWNER_MOVED', emit=False)
    qualify.write(project / 'main.my', original)
    qualify.write(run.out / 'contract.json', json.dumps(dict(
        status='passed' if all(row['passed'] for row in run.rows) else 'failed',
        harness_sha256=qualify.digest(__file__), engine_sha256=qualify.digest(qualify.__file__),
        fixture_sha256=qualify.digest(fixture), compiler_revision=args.source_revision,
        compiler_sha256=qualify.digest(args.compiler), cases=len(run.rows),
        scope='Actual generic source tuple split: native release, LLVM RC audit, replay, relocation, earlier declarations, valid/invalid edits.',
        boundaries='Semantic-cache-v8 malformed payload and specialization serialization are separate registered tests. Mode rollout and installed package remain separate gates. No timing claim.'), indent=2) + '\n')
    raise SystemExit(0 if all(row['passed'] for row in run.rows) else 1)


if __name__ == '__main__':
    main()
