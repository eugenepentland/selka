import hashlib
import json
from pathlib import Path
import re
import subprocess

root = Path.cwd()
folder = root / '.tmp/plain-guest'
folder.mkdir(parents=True, exist_ok=True)
compiler = root / '.tmp/plain/bin/mylang'
rows = []
for name, flags, inlined in [
    ('qbe', ['--backend', 'qbe'], False),
    ('llvm-none', ['--backend', 'llvm', '--llvm-opt', '3'], False),
    ('llvm-full', ['--backend', 'llvm', '--llvm-opt', '3', '--lto=full'], True),
    ('llvm-thin', ['--backend', 'llvm', '--llvm-opt', '3', '--lto=thin'], True),
]:
    dest = folder / name
    dest.mkdir(exist_ok=True)
    binary = dest / 'alloc_churn'
    command = [str(compiler), 'build', str(root / 'bench/parity/micro/alloc_churn.my'), '-o', str(binary), '--rc-runtime', '--keep-symbols', '--cache-dir', str(folder / 'cache')] + flags
    print('MODE', name, flush=True)
    build = subprocess.run(command, text=True, capture_output=True)
    (dest / 'build.stdout').write_text(build.stdout)
    (dest / 'build.stderr').write_text(build.stderr)
    assert build.returncode == 0, (name, build.stderr)
    run = subprocess.run([str(binary)], text=True, capture_output=True)
    (dest / 'run.stdout').write_text(run.stdout)
    (dest / 'run.stderr').write_text(run.stderr)
    assert run.returncode == 0 and run.stdout == '999739\n', (name, run.returncode, run.stdout, run.stderr)
    asm = subprocess.run(['objdump', '-d', str(binary)], text=True, capture_output=True, check=True).stdout
    (dest / 'assembly.txt').write_text(asm)
    calls = [line for line in asm.splitlines() if re.search(r'\bcall\w*\s.*<myl_rc_list_plain_ready(?:[+>])', line)]
    assert (len(calls) == 0) == inlined, (name, calls)
    rows.append({'mode': name, 'command': command, 'status': 0, 'stdout': run.stdout, 'plain_ready_machine_call_sites': calls, 'query_inlined': inlined, 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'assembly_sha256': hashlib.sha256(asm.encode()).hexdigest()})
(folder / 'receipt.json').write_text(json.dumps(rows, indent=2) + '\n')
