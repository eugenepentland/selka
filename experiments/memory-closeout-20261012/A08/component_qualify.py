#!/usr/bin/env python3
"""Qualify reserved component sources, preserving the installed wire protocols.

Run inside one outer build admission. --scope-free-check removes only the known
filesystem acquisition from a disposable source copy to expose subsequent
ownership refusals; it is source-check evidence, never component qualification.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
BASE = 'fbfcaa7a923186a8e773c3760f81c10aa345a432'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--compiler-revision', required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--scope-free-check', action='store_true')
    parser.add_argument('--legacy-seed', action='store_true')
    parser.add_argument('--default-zero', action='store_true')
    args = parser.parse_args()
    args.compiler = args.compiler.resolve()
    args.work = args.work.resolve()
    args.output = args.output.resolve()
    if args.output.exists():
        raise ValueError('Choose an unused evidence output path')
    args.work.mkdir(parents=True, exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    for state in (('before', 'after') if args.scope_free_check else ('after',)):
        for component in ('test_index', 'cache_plan'):
            source = ROOT / 'selfhost/components' / component
            sources = {}
            project = args.work / state / component
            project.mkdir(parents=True, exist_ok=True)
            for path in source.glob('*.my'):
                text = subprocess.check_output(['git', 'show', f'{BASE}:{path.relative_to(ROOT)}'], cwd=ROOT).decode() if state == 'before' else path.read_text()
                sources[path.name] = hashlib.sha256(text.encode()).hexdigest()
                if args.scope_free_check and path.name == 'main.my':
                    text = text.replace('func exchange(fs: Filesystem, path: str)', 'func exchange(data: bytes)')
                    lines = text.splitlines(keepends=True)
                    text = ''.join(line for line in lines if not any(part in line for part in ('    mut data = b""', '    with try fs.open', '        data = file.read')))
                    text = text.replace('exchange(fs, args[1])', 'exchange(b"")')
                    text = text.replace('args: str[], fs: Filesystem, out: Stream', 'args: str[], out: Stream')
                (project / path.name).write_text(text)
            command = [str(args.compiler), 'check' if args.scope_free_check else 'build', str(project / 'main.my')]
            if not args.legacy_seed and not args.default_zero:
                command += ['--experimental-zero-rc']
            binary = project / component
            if args.scope_free_check:
                command += ['--no-cache']
            else:
                command += ['--release', '--zig', str(args.zig), '-o', str(binary), '--cache-dir', str(project / 'cache')]
                if not args.legacy_seed: command += ['--emit-llvm', str(project / (component + '.ll'))]
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=300)
            row = dict(state=state, component=component, sources=sources, command=command, status=result.returncode, stdout=result.stdout, stderr=result.stderr, passed=result.returncode == 0)
            if result.returncode == 0 and not args.scope_free_check:
                row['binary_sha256'] = sha(binary)
                oracle = ['python3', '-B', str(ROOT / 'selfhost/tests' / f'run_{component}_component.py'), '--component', str(binary)]
                run = subprocess.run(oracle, cwd=ROOT, capture_output=True, text=True, timeout=300)
                row.update(oracle=oracle, oracle_status=run.returncode, oracle_stdout=run.stdout, oracle_stderr=run.stderr)
                row['passed'] &= run.returncode == 0
                if not args.legacy_seed:
                    llvm = (project / (component + '.ll')).read_text()
                    row['llvm_rc_clean'] = not any(token in llvm for token in ('@myl_core_retain', '@myl_core_release', '@myl_core_share(', 'load atomic i32'))
                    row['passed'] &= row['llvm_rc_clean']
            rows.append(row)
            args.output.write_text(json.dumps(dict(compiler=str(args.compiler), compiler_sha256=sha(args.compiler), compiler_revision=args.compiler_revision, source_base=BASE, transformed_source_check=args.scope_free_check, seed_compatibility_only=args.legacy_seed, rows=rows, all_passed=all(row['passed'] for row in rows)), indent=2)+'\n')
            print(json.dumps(row), flush=True)
    raise SystemExit(0 if all(row['passed'] for row in rows) else 1)


if __name__ == '__main__':
    main()
