#!/usr/bin/env python3
"""Qualitative profile and exact ownership counts for the unchanged schematic."""
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('diagnostic', Path(__file__).with_name('run.py'))
D = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(D)
A, PC = D.A, D.PC
WORK = A.WORK / 'schematic-7d68202d'
COMPILER = ROOT.parent / 'd9-rc-integration/.tmp-rc/install-scope-scalar/bin/mylang'


def main():
    WORK.mkdir(exist_ok=True)
    state = json.loads((A.WORK / 'diagnostic-7d68202d/results.json').read_text())
    assert A.sha(COMPILER) == state['identity']['compiler_sha256']
    assert A.inputs() == state['identity']['inputs']
    program = next(p for p in A.programs() if p['id'] == 'schematic/fixture')
    result = {'profile_is_qualitative': True, 'compiler_sha256': A.sha(COMPILER),
              'driver_sha256': A.sha(__file__), 'commands': [], 'checks': {}}
    for mode in ('production', 'stats'):
        binary = WORK / mode
        command, cwd = PC.build_command(program, str(COMPILER), 'qbe', binary, WORK / 'cache')
        command = [str(ROOT / 'scripts/build-slot.sh'), 'build', *command, '--keep-symbols',
                   '--rc-runtime' + ('=stats' if mode == 'stats' else '')]
        done = subprocess.run(command, cwd=cwd, env=PC.clean_env(), capture_output=True, timeout=1200)
        result['commands'].append({'command': command, 'cwd': cwd, 'status': done.returncode,
                                   'stderr': done.stderr.decode(errors='replace')})
        assert done.returncode == 0, done.stderr.decode(errors='replace')
        result[mode + '_sha256'] = A.sha(binary)
        run = PC.run_spec(program, binary, 'profile-' + mode, state['schematic_declared'])
        result['checks'][mode] = PC.check(program, run)
        assert result['checks'][mode]['ok']
        result[mode + '_run'] = D.receipt(run)
    stats = result['checks']['stats']['stderr']
    result['counters'] = [json.loads(line.split(' ', 1)[1]) for line in stats.splitlines()
                          if line.startswith('MYLANG_RC_COUNTS ')]
    command, cwd = PC.emit_command(program, str(COMPILER))
    done = subprocess.run([str(ROOT / 'scripts/build-slot.sh'), 'build', *command, '--rc-runtime'],
                          cwd=cwd, env=PC.clean_env(), capture_output=True, timeout=1200)
    assert done.returncode == 0
    (WORK / 'emitted.json').write_bytes(done.stdout)
    run = PC.run_spec(program, WORK / 'production', 'profile-perf', state['schematic_declared'])
    command = ['perf', 'record', '-e', 'instructions:u', '-c', '1000000', '-g',
               '-o', str(WORK / 'profile.data'), '--', 'taskset', '-c', '11', *run['argv']]
    done = subprocess.run(command, cwd=run['cwd'], env=run['env'], capture_output=True, timeout=120)
    result['commands'].append({'command': command, 'status': done.returncode,
                               'stderr': done.stderr.decode(errors='replace')})
    assert done.returncode == 0
    assert PC.sha(run['svg'].read_bytes()) == PC.SCHEMATIC_SVG['fixture']
    report = subprocess.run(['perf', 'report', '--stdio', '--no-children', '--sort', 'symbol',
                             '-i', str(WORK / 'profile.data')], capture_output=True, check=True)
    (WORK / 'profile.txt').write_bytes(report.stdout)
    (WORK / 'identity.json').write_text(json.dumps(result, indent=2) + '\n')
    print('profile complete', result['counters'], flush=True)


if __name__ == '__main__':
    main()
