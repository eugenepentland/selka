import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

root = Path('.tmp/list-image-scale').resolve()
root.mkdir(exist_ok=True)
roles = {
    'control': (Path('.tmp/list-image-control/bin/mylang').resolve(),
                '4059a85e3d081f8a73b370e03e7d86cba8eb8a47531bfcdd7c09e6cc109d74b1'),
    'candidate': (Path('.tmp/list-image-frozen/bin/mylang').resolve(),
                  '4f37d5a8e78c8c064e88249e6f95ebd929b78c222aa17bd1697be09f5bea82af'),
}
for compiler, digest in roles.values():
    assert hashlib.sha256(compiler.read_bytes()).hexdigest() == digest
receipt = {'protocol': 'Single shared-machine observations, admitted once before script; separate role/backend caches, source objects cold, runtime cache warmed by each 8-element row. Native runs verify stdout and exit status. Timeout 180 seconds terminates only the process group started by this script. Not median or corpus acceptance.',
           'compiler_sha256': {r: h for r, (_, h) in roles.items()},
           'source_commits': {'control': '80dd51906c97ae76bf208474ac48c9baac3a11cd',
                              'candidate': '8f67ab8ad02a92ab5a37f6875d52282164104d15'},
           'rows': []}

def invoke(command, stem):
    stat = root / (stem + '.time')
    start = time.monotonic()
    proc = subprocess.Popen(['/usr/bin/time', '-f', '%e %M', '-o', str(stat), *command],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    timed_out = False
    try:
        stdout, stderr = proc.communicate(timeout=180)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            stdout, stderr = proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            stdout, stderr = proc.communicate()
    elapsed = time.monotonic() - start
    (root / (stem + '.out')).write_bytes(stdout)
    (root / (stem + '.err')).write_bytes(stderr)
    metrics = {'status': proc.returncode, 'timeout': timed_out,
               'elapsed_seconds': round(elapsed, 6)}
    if stat.exists():
        parts = stat.read_text().splitlines()[-1].split()
        if len(parts) == 2:
            metrics['max_rss_kib'] = int(parts[1])
    return metrics, stdout, stderr

for family in ['int', 'str', 'bytes']:
    for count in [8, 250, 1000]:
        values = [str(i) for i in range(count)] if family == 'int' else [
            '"é😀"' if family == 'str' else 'b"\\x00\\xff"'] * count
        source = 'def main(out: Stream) -> int:\n    values = [' + ', '.join(values) + ']\n    out.print(len(values))\n    return 0\n'
        path = root / f'{family}-{count}.my'
        path.write_text(source)
        for role, (compiler, _) in roles.items():
            stem = f'{role}-{family}-{count}'
            emit, il, _ = invoke([str(compiler), 'emit-qbe', str(path)], stem + '-emit')
            row = {'role': role, 'family': family, 'elements': count,
                   'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                   'emit': emit, 'manifest_bytes': len(il), 'il_bytes': sum(len(u['il'].encode()) for u in json.loads(il)['functions']), 'il_lines': sum(u['il'].count('\n') for u in json.loads(il)['functions'])}
            assert emit['status'] == 0, row
            for backend in ['qbe', 'llvm']:
                target = root / f'{stem}-{backend}'
                flags = [] if backend == 'qbe' else ['--llvm-opt=3', '--lto']
                command = [str(compiler), 'build', str(path), '-o', str(target),
                           '--backend=' + backend, '--cache-dir=' + str(root / f'cache-{role}-{backend}'),
                           '--timings=json', *flags]
                metrics, _, stderr = invoke(command, stem + '-' + backend + '-build')
                phases = []
                for line in stderr.splitlines():
                    try:
                        phases.append(json.loads(line))
                    except (ValueError, UnicodeDecodeError):
                        pass
                metrics['phase_reports'] = phases
                if metrics['status'] == 0:
                    ran = subprocess.run([str(target)], capture_output=True, timeout=10)
                    metrics['run_status'] = ran.returncode
                    metrics['stdout'] = ran.stdout.decode('utf8', 'replace')
                    metrics['stderr'] = ran.stderr.decode('utf8', 'replace')
                    metrics['output_verified'] = ran.returncode == 0 and ran.stdout == f'{count}\n'.encode() and not ran.stderr
                    assert metrics['output_verified'], metrics
                row[backend] = metrics
            receipt['rows'].append(row)
            (root / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
            print(role, family, count, 'il', len(il), 'qbe', row['qbe']['status'], row['qbe']['elapsed_seconds'], 'llvm', row['llvm']['status'], row['llvm']['elapsed_seconds'], flush=True)
