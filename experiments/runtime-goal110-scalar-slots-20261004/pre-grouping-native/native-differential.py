"""Untimed actual LLVM O3/full-LTO scalar-slot default/legacy differential."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
ZIG = Path(shutil.which('zig')).resolve()
OUTPUT = ROOT / '.task-tmp/scalar-slots-native-differential'
INPUTS = [EVIDENCE / f'slot-{form}-{variant}.ll' for form in range(6) for variant in ('default', 'legacy')]
DRIVER = EVIDENCE / 'native-driver.c'
command = [str(ZIG), 'cc', '-O3', '-flto', *(str(path) for path in INPUTS), str(DRIVER), '-o', str(OUTPUT)]
compiled = subprocess.run(command, capture_output=True)
(EVIDENCE / 'native-link.stdout.log').write_bytes(compiled.stdout)
(EVIDENCE / 'native-link.stderr.log').write_bytes(compiled.stderr)
compiled.check_returncode()
run = subprocess.run([str(OUTPUT)], capture_output=True)
(EVIDENCE / 'native-execution.stdout.log').write_bytes(run.stdout)
(EVIDENCE / 'native-execution.stderr.log').write_bytes(run.stderr)
run.check_returncode()
assert run.stdout == b'630 default/legacy/oracle comparisons; 1260 native function executions passed\n'
assert not run.stderr

def artifact(path):
    return {'path': str(path), 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

report = {'kind': 'untimed-actual-LLVM-O3-fullLTO-default-legacy-oracle-differential',
          'source_revision_at_execution': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'production_source_sha256': {name: artifact(ROOT / name)['sha256'] for name in
              ('src/qbe_build_llvm_slots.zig', 'src/qbe_build_llvm_emit.zig', 'src/qbe_build_llvm_lower.zig')},
          'production_sources_uncommitted_at_execution': True,
          'zig': artifact(ZIG), 'command': command, 'compile_exit': compiled.returncode,
          'inputs': [artifact(path) for path in INPUTS], 'driver': artifact(DRIVER), 'binary': artifact(OUTPUT),
          'execution_exit': run.returncode, 'stdout': run.stdout.decode(), 'stderr': run.stderr.decode(),
          'cases': ['entry-loop slots', 'repeated nonentry allocation', 'callee escape', 'arithmetic alias',
                    'independent allocation identity', 'conditional non-dominating multidef allocation'],
          'counts': [-3, 0, 1, 2, 7, 16, 129], 'seeds': [-9223372036854775808, -17, 0, 1, 9223372036854775807],
          'repeated_calls': 3, 'comparisons': 630, 'function_executions': 1260,
          'limits': 'Low-level wrapped QBE arithmetic differential; full language trap/accounting holdouts run separately. Not runtime timing.'}
(EVIDENCE / 'native-differential.json').write_text(json.dumps(report, indent=2) + '\n')
print(run.stdout.decode(), end='')
