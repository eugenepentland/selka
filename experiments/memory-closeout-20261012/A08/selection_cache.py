#!/usr/bin/env python3
"""Source-generated text/Optional selection cache qualification.

Every compiler process owns ordinary build admission. Results are correctness
evidence, not controlled timings. Stored typed-node tests and A04's full native
mode/refusal matrix are separate; this checks actual source cache transitions.
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
    fixtures = Path(__file__).with_name('typed-selection-cache')
    original = (fixtures / 'main.my').read_text()
    project = run.work / 'source'
    qualify.write(project / 'main.my', original)
    for phase in ('cold', 'warm', 'receipt', 'replay'):
        run.build('selection-' + phase, project, expected='', emit=phase in ('cold', 'warm'))
    relocated = run.work / 'relocated'
    shutil.copytree(project, relocated, ignore=shutil.ignore_patterns('cache'))
    run.build('selection-relocated-cold', relocated, expected='')
    run.build('selection-relocated-warm', relocated, expected='')
    prefix = 'record Earlier:\n    labels: bytes[]\nfunc earlier() -> Earlier:\n    return Earlier(labels=[b"a"])\n'
    edited = prefix + original.replace('func main() -> int:\n', 'func main() -> int:\n    const before = earlier()\n    assert len(before.labels[0]) == 1\n', 1)
    qualify.write(project / 'main.my', edited)
    run.build('selection-discovery-cold', project, expected='')
    run.build('selection-discovery-warm', project, expected='')
    for name, code in (
        ('first_parent_invalidated', 'E_SINGLE_OWNER_OVERLAP'),
        ('second_parent_invalidated', 'E_SINGLE_OWNER_OVERLAP'),
        ('optional_receiver_invalidated', 'E_SINGLE_OWNER_OVERLAP'),
        ('fresh_escape', 'E_SINGLE_OWNER_BORROW'),
    ):
        source = (fixtures / (name + '.my')).read_text()
        qualify.write(project / 'main.my', source)
        run.build('selection-invalid-' + name + '-warm', project, refuse=code, emit=False)
        cold = run.work / ('invalid-' + name)
        qualify.write(cold / 'main.my', source)
        run.build('selection-invalid-' + name + '-cold', cold, refuse=code, emit=False)
    qualify.write(project / 'main.my', original)
    for row in run.rows:
        if row['expected_refusal'] or not row['name'].endswith('-warm'):
            continue
        stages = (row['report'] or {}).get('stages', {})
        frontend = stages.get('frontend', {})
        lowering = stages.get('lowering', {})
        row['stage_reuse_verified'] = frontend.get('reused', 0) > 0 and lowering.get('reused', 0) > 0 and frontend.get('damaged', 0) == 0
        row['passed'] &= row['stage_reuse_verified']
    run.save()
    qualify.write(run.out / 'contract.json', json.dumps(dict(
        status='passed' if all(row['passed'] for row in run.rows) else 'failed',
        harness_sha256=qualify.digest(__file__), engine_sha256=qualify.digest(qualify.__file__),
        fixture_manifest_sha256=qualify.digest(fixtures / 'manifest.json'),
        compiler_revision=args.source_revision, compiler_sha256=qualify.digest(args.compiler), cases=len(run.rows),
        scope='Actual min/max/Optional typed selections, native release, exact oracle, LLVM RC audit, observed stage reuse, receipt replay, relocation, earlier physical catalog discovery and warm/cold root refusal.',
        boundaries='Semantic-cache-v9 wire/copy validation and A04 full mode matrix are separate. No timing or final milestone claim.'), indent=2) + '\n')
    raise SystemExit(0 if all(row['passed'] for row in run.rows) else 1)


if __name__ == '__main__':
    main()
