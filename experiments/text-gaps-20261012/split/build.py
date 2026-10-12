"""Build unchanged full text fixture with private outputs and complete host install."""
import pathlib, subprocess, json, hashlib
ROOT = pathlib.Path(__file__).resolve().parents[3]
BASE = ROOT / '.tmp/text-gaps/split'
COMPILER = BASE / 'install/bin/mylang'
SOURCE = pathlib.Path(__file__).with_name('text.my')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

entries = []
for counted in (False, True):
    binary = BASE / ('text-counted' if counted else 'text-runtime')
    command = [str(COMPILER), 'build', str(SOURCE), '-o', str(binary), '--release', '--experimental-zero-rc',
               '--link', str(ROOT / 'benchmarks/runtime/ports/native_clock.c'), '--cache-dir', str(BASE / 'guest-cache')]
    if counted:
        command += ['--counters']
    else:
        command += ['--emit-llvm', str(BASE / 'text-runtime.ll')]
    ran = subprocess.run(command, capture_output=True, text=True)
    (BASE / ('build-counted.log' if counted else 'build-runtime.log')).write_text(ran.stdout + ran.stderr)
    entries.append(dict(command=command, status=ran.returncode, binary=str(binary), sha256=sha(binary) if ran.returncode == 0 else None))
    if ran.returncode:
        print(ran.stdout + ran.stderr)
        break
pathlib.Path(__file__).with_name('build-manifest.json').write_text(json.dumps(dict(
    compiler=str(COMPILER), compiler_sha256=sha(COMPILER), source=str(SOURCE), source_sha256=sha(SOURCE), entries=entries), indent=2) + '\n')
raise SystemExit(0 if len(entries) == 2 and all(row['status'] == 0 for row in entries) else 1)
