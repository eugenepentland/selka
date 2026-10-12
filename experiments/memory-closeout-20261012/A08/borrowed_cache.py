#!/usr/bin/env python3
"""Cold/warm/receipt/relocation ownership contracts for borrowed managed defaults.

This is correctness qualification. Elapsed values include ordinary admission when
selected and are not controlled timings. Use --admission held only inside one
coordinator-approved bounded build lease; do not nest admission.
"""
import argparse
import json
from pathlib import Path
import shutil

import qualify

NEGATIVE = '''func overwrite(mut values: int[]) -> int:
    values.clear()
    return 0
func replace(mut values: dict[str, int[]]) -> int:
    values.clear()
    return 0
func use(values: int[], ignored: int) -> int:
    return len(values)
func main() -> int:
    mut values = {"present": [1, 2, 3]}
    mut fallback = [4, 5]
    return use(values.get("absent", fallback), {mutation})
'''


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
    project = run.work / 'source'
    fixture = Path(__file__).with_name('borrow-selection-cache') / 'main.my'
    original = fixture.read_text()
    qualify.write(project / 'main.my', original)
    expected = '3 2\n1 3\n'
    for phase in ('cold', 'warm', 'receipt', 'replay'):
        run.build('borrow-' + phase, project, expected=expected, emit=phase in ('cold', 'warm'))
    relocated = run.work / 'relocated'
    shutil.copytree(project, relocated, ignore=shutil.ignore_patterns('cache'))
    run.build('borrow-relocated-cold', relocated, expected=expected)
    run.build('borrow-relocated-warm', relocated, expected=expected)
    prefix = 'record Earlier:\n    labels: bytes[]\nfunc earlier() -> Earlier:\n    return Earlier(labels=[b"a"])\n'
    edited = prefix + original.replace('    mut values', '    const before = earlier()\n    assert len(before.labels) == 1\n    mut values', 1)
    qualify.write(project / 'main.my', edited)
    run.build('borrow-physical-edit-cold', project, expected=expected)
    run.build('borrow-physical-edit-warm', project, expected=expected)
    for owner, mutation in (('fallback', 'overwrite(mut fallback)'), ('dictionary', 'replace(mut values)')):
        invalid = NEGATIVE.replace('{mutation}', mutation)
        qualify.write(project / 'main.my', invalid)
        run.build('borrow-invalid-' + owner + '-warm', project, refuse='E_SINGLE_OWNER_OVERLAP', emit=False)
        cold = run.work / ('invalid-' + owner)
        qualify.write(cold / 'main.my', invalid)
        run.build('borrow-invalid-' + owner + '-cold', cold, refuse='E_SINGLE_OWNER_OVERLAP', emit=False)
    qualify.write(project / 'main.my', original)
    qualify.write(run.out / 'contract.json', json.dumps(dict(
        status='passed' if all(row['passed'] for row in run.rows) else 'failed',
        harness_sha256=qualify.digest(__file__), engine_sha256=qualify.digest(qualify.__file__),
        fixture_sha256=qualify.digest(fixture), compiler_revision=args.source_revision,
        compiler_sha256=qualify.digest(args.compiler), cases=len(run.rows),
        scope='Native release correctness, LLVM RC audit, receipt replay, physical discovery edit, relocation and both-root source refusals.',
        boundaries='Pure IR cache-corruption and debug-stage restoration have separate registered tests. No timing claim. No final milestone implied by an intermediate compiler.'), indent=2) + '\n')
    raise SystemExit(0 if all(row['passed'] for row in run.rows) else 1)


if __name__ == '__main__':
    main()
