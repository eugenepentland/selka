"""Untimed build, static capture and checksum qualification for the loop-copy candidate."""
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
WORK = ROOT / '.mylang-cache/goal110-calls-d14e26f4-guests'
SOURCE = ROOT / 'benchmarks/runtime/expanded/compute/main.my'
CLOCK = Path('/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-harness-20261003/.mylang-cache/runtime-candidate-730a86e6-releasefast/runner/native_clock.o')
COMPILER = ROOT / 'zig-out/bin/mylang'
QBE = ROOT / 'zig-out/bin/qbe'
BEFORE = Path('/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-harness-20261003/.mylang-cache/runtime-candidate-730a86e6-releasefast/runner/bin')


def artifact(path):
    return {'path': str(path), 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def stamp():
    return datetime.now(timezone.utc).isoformat()


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
receipt = {'kind': 'untimed-loop-copy-build-static-qualification', 'started_utc': stamp(),
           'source_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
           'compiler': artifact(COMPILER), 'source': artifact(SOURCE), 'clock': artifact(CLOCK),
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
