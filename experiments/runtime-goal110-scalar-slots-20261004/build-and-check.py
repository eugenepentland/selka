"""Untimed build, static capture and checksum qualification for direct scalar-slot pointer lowering."""
from datetime import datetime, timezone
import hashlib
import importlib.util
import itertools
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
WORK = ROOT / '.mylang-cache/goal110-scalar-slots-guests'
SOURCE = ROOT / 'benchmarks/runtime/expanded/compute/main.my'
CONTROL = Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-text-rf-host-20261004/.mylang-cache/goal110-join/join-runner')
CLOCK = CONTROL / 'native_clock.o'
COMPILER_RECEIPT = EVIDENCE / 'compiler-build-receipt.json'
CONTROL_RECEIPT = CONTROL.parent / 'join-compiler-receipt.json'
COMPILER = ROOT / 'zig-out/bin/mylang'
QBE = ROOT / 'zig-out/bin/qbe'
BEFORE = CONTROL / 'bin'


def artifact(path):
    return {'path': str(path), 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def stamp():
    return datetime.now(timezone.utc).isoformat()


compiler_build = json.loads(COMPILER_RECEIPT.read_text())
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
assert compiler_build['schema'] == 'mylang-runtime-compiler-build-v1'
assert compiler_build['status'] == 'complete' and compiler_build['exit_status'] == 0
assert compiler_build['source_revision'] == revision and compiler_build['compiler_optimize'] == 'Debug'
assert compiler_build['sources_before'] == compiler_build['sources_after']
assert compiler_build['compiler_sha256'] == artifact(COMPILER)['sha256']
for name, expected in compiler_build['sources_after'].items():
    assert artifact(ROOT / name)['sha256'] == expected, name
for name, expected in compiler_build['installed_assets'].items():
    assert artifact(Path(name))['sha256'] == expected, name
control_manifest_path = CONTROL / 'manifest.json'
control_manifest = json.loads(control_manifest_path.read_text())
control_identity = control_manifest['identity']
assert control_identity['source_revision'] == '5a60ef1039aca32657ef5877a464eb8a81d6c115'
control_receipt_binding = control_identity['compiler_build_receipt']
assert artifact(CONTROL_RECEIPT)['sha256'] == control_receipt_binding['sha256']
control_build = json.loads(CONTROL_RECEIPT.read_text())
assert control_build == control_receipt_binding['receipt']
assert control_build['status'] == 'complete' and control_build['exit_status'] == 0
assert control_build['compiler_optimize'] == 'Debug'
assert control_build['source_revision'] == control_identity['source_revision']
assert artifact(SOURCE)['sha256'] == control_identity['sources']['expanded/compute/main.my']
control_binding = {'manifest': artifact(control_manifest_path),
                   'compiler_build_receipt': artifact(CONTROL_RECEIPT),
                   'source_revision': control_identity['source_revision'],
                   'guest_policy': control_identity['target_policy'],
                   'binaries': {}, 'commands': {}}
for backend in ('llvm', 'qbe'):
    key = 'compute/my-' + backend
    control_binary = Path(control_identity['binary_paths'][key])
    assert control_binary == BEFORE / ('compute-my-' + backend)
    proof = artifact(control_binary)
    assert proof['sha256'] == control_manifest['binary_hashes'][key]
    control_binding['binaries'][backend] = proof
    command = control_identity['actual_build_commands'][key]
    assert command[command.index('--backend') + 1] == backend
    assert command[command.index('--mode') + 1] == 'ReleaseFast'
    if backend == 'llvm':
        assert command[command.index('--llvm-opt') + 1] == '3' and '--lto' in command
    control_binding['commands'][backend] = command
assert artifact(CLOCK)['sha256'] == control_manifest['binary_hashes']['native_clock.o']


WORK.mkdir(parents=True, exist_ok=True)
(WORK / 'tmp').mkdir(exist_ok=True)
environment = {**os.environ, 'TMPDIR': str(WORK / 'tmp'),
               'ZIG_GLOBAL_CACHE_DIR': str(ROOT / '.task-tmp/zig-global')}
environment.pop('MYLANG_OPTIONS', None)
environment.pop('MYLANG_MEMORY_LIMIT', None)
environment['MYLANG_LLVM_DUMP'] = str(WORK / 'llvm-dump')
spec = importlib.util.spec_from_file_location('compute_oracle', SOURCE.with_name('oracle.py'))
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)
receipt = {'kind': 'untimed-scalar-slot-pointer-build-static-qualification', 'started_utc': stamp(),
           'source_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
           'compiler': artifact(COMPILER), 'compiler_build_receipt': artifact(COMPILER_RECEIPT),
           'source': artifact(SOURCE), 'clock': artifact(CLOCK), 'control': control_binding,
           'runner': artifact(Path(__file__)), 'host_mode': 'Debug', 'guest_mode': 'ReleaseFast',
           'builds': [], 'qualification': []}
for backend in ('llvm', 'qbe'):
    binary = WORK / ('compute-my-' + backend)
    command = [str(ROOT / 'scripts/build-slot.sh'), 'build', str(COMPILER), 'build', str(SOURCE),
               '-o', str(binary), '--cache-dir', str(WORK / 'mycache'), '--link', str(CLOCK),
               '--qbe', str(QBE), '--mode', 'ReleaseFast', '--backend', backend, '--keep-symbols']
    if backend == 'llvm':
        command += ['--llvm-opt', '3', '--lto']
    log = EVIDENCE / (backend + '-guest-build.log')
    with log.open('wb') as output:
        result = subprocess.run(command, cwd=ROOT, env=environment, stdout=output, stderr=subprocess.STDOUT)
    result.check_returncode()
    manifest_path = Path(str(binary) + '.qbe-manifest.json')
    manifest = json.loads(manifest_path.read_text())
    assert manifest['backend'] == backend
    assert backend != 'llvm' or (manifest['optimization'] == '3' and manifest['lto'])
    disassembly = EVIDENCE / (backend + '-candidate-entry.s')
    with disassembly.open('wb') as output:
        subprocess.run(['objdump', '-d', '--disassemble=' + manifest['entry'], str(binary)], stdout=output, check=True)
    receipt['builds'].append({'backend': backend, 'command': command, 'status': result.returncode,
                              'binary': artifact(binary), 'manifest': artifact(manifest_path),
                              'build_log': artifact(log), 'entry_disassembly': artifact(disassembly)})
    print('built and backend-checked', backend, flush=True)
    for case, metadata in oracle.CASES.items():
        inputs = [(size, 3, seed) for size, seed in itertools.product(metadata['sizes'], (1, 424242, 1000000))]
        inputs += [(size, iterations, seed) for size, iterations, seed in ((2, 1, 2), (7, 17, 17), (67, 19, 999983))]
        for size, iterations, seed in inputs:
            command = [str(binary), case, str(size), str(iterations), str(seed)]
            result = subprocess.run(command, capture_output=True, env=environment)
            expected = oracle.checksum(case, size, iterations, seed)
            pieces = result.stdout.decode().split()
            assert result.returncode == 0 and not result.stderr and len(pieces) == 2, (command, result)
            assert int(pieces[0]) == expected and int(pieces[1]) > 0, (command, pieces, expected)
            receipt['qualification'].append({'backend': backend, 'case': case, 'size': size,
                                             'iterations': iterations, 'seed': seed, 'checksum': expected})
    print('qualified', backend, len(oracle.CASES) * 9, 'untimed inputs', flush=True)
receipt['finished_utc'] = stamp()
(EVIDENCE / 'guest-build-qualification.json').write_text(json.dumps(receipt, indent=2) + '\n')
