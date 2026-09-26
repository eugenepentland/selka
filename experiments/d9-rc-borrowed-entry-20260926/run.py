#!/usr/bin/env python3
"""Validate and count the exact three D9 schematic cases on two saved compilers."""
import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def counts(checked):
    rows = [line.removeprefix('MYLANG_RC_COUNTS ') for line in checked['stderr'].splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
    assert len(rows) == 1, checked
    value = json.loads(rows[0])
    assert not value['saturated']
    assert value['heap_allocate'] == value['retire']
    assert value['owner_acquire'] + value['heap_allocate'] == value['owner_release']
    assert value['hold_acquire'] == value['hold_release']
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before-prefix', type=Path, required=True)
    parser.add_argument('--after-prefix', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=HERE)
    parser.add_argument('--lox-root', type=Path, default=ROOT.parent / 'd9-rc-performance/.tmp-rc-performance/lox')
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('d9_compare', ROOT / 'experiments/d9-rc-acceptance-20260926/compare.py')
    compare = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compare)
    pc = compare.pc
    pc.LOX_PORT = args.lox_root / 'benchmarks/lox/ports/mylang'
    pc.LOX_BENCH = args.lox_root / 'bench'
    programs = [program for program in compare.programs() if program['kind'] == 'schematic']
    assert len(programs) == 3
    args.output.mkdir(parents=True, exist_ok=True)
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    os.environ['TMPDIR'] = str(work)
    os.environ['ZIG_LOCAL_CACHE_DIR'] = str(ROOT / '.zig-cache-rc-collections')
    for side, prefix in [('before', args.before_prefix), ('after', args.after_prefix)]:
        compiler = prefix.resolve() / 'bin/mylang'
        qbe = prefix.resolve() / 'bin/qbe'
        pc.WORK = work / side
        for backend in ('qbe', 'llvm'):
            binary = pc.WORK / ('schematic.' + backend)
            command, cwd = pc.build_command(programs[0], str(compiler), backend, binary, pc.WORK / ('cache-' + backend))
            command += ['--rc-runtime=stats', '--qbe=' + str(qbe)]
            result = {'compiler_sha256': digest(compiler), 'qbe_sha256': digest(qbe)}
            result['build'] = pc.do_build({'bin': binary, 'cmd': [str(ROOT / 'scripts/build-slot.sh'), 'build', *command], 'cwd': cwd})
            assert result['build']['ok'], result['build']
            emit, cwd = pc.emit_command(programs[0], str(compiler))
            emitted = subprocess.run([*emit, '--rc-runtime=stats'], cwd=cwd, env=pc.clean_env(), capture_output=True, timeout=1200, check=True)
            declared = pc.declared_of(emitted.stdout)
            result['checks'] = {}
            for program in programs:
                invocation = pc.run_spec(program, binary, side + '-' + backend, declared)
                checked = pc.check(program, invocation)
                result['checks'][program['id']] = checked
                assert checked['ok'], checked
                checked['counts'] = counts(checked)
                print(side, backend, program['id'], checked['svg_sha256'], flush=True)
            (args.output / f'{side}-{backend}.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
