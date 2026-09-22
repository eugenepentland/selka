#!/usr/bin/env python3
import hashlib, json, os, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/svg-gap-audit-20260921/host'
BASE = ROOT / '.tmp/full-svg-benchmark-20260921'
DOCS = ('lib/modules/straps-synth-lmx2595.sexp',
        'lib/pinouts/lmx2595rhar.sexp', 'lib/interfaces/spi.sexp')
CASES = ('fixture', 'changed-net', 'changed-value')
ARMS = ('control', 'counts', 'unchecked', 'memory-output',
        'metadata-control', 'typed-host')
REFS = json.loads((ROOT / 'experiments/full-svg-benchmark/qualification.json').read_text())['cases']

def sha_bytes(value): return hashlib.sha256(value).hexdigest()
def sha(path): return sha_bytes(Path(path).read_bytes())

def run(arm, case, stress=False, counts=False):
    project = BASE / 'projects' / case
    output, issue = WORK / f'{arm}-{case}.svg', WORK / f'{arm}-{case}.issue'
    output.write_bytes(b''); issue.write_bytes(b'')
    env = dict(os.environ)
    for key in list(env):
        if key.startswith('MYLANG_QBE_LLVM_') or key in ('LD_PRELOAD',): env.pop(key)
    env.update(MYLANG_MEMORY_LIMIT='268435456',
      MYLANG_SCHEMATIC_DECLARED='io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue',
      MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
    env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': str(project / p) for i, p in enumerate(DOCS)})
    if counts: env['MYLANG_HOST_COUNTS'] = '1'
    command = [str(WORK / arm), '--print-result'] + (['--gc-stress'] if stress else [])
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, timeout=90)
    expected_stderr = result.stderr if counts else b''
    assert (result.returncode, result.stdout, result.stderr, issue.read_bytes()) == (0, b'0\n', expected_stderr, b'')
    data = output.read_bytes()
    assert sha_bytes(data) == REFS[case]['mylang-o3']['svg_sha256'], (arm, case, sha_bytes(data))
    return result, data, command

evidence = {'passed': True, 'arms': {}}
for arm in ARMS:
    evidence['arms'][arm] = {'binary_sha256': sha(WORK / arm), 'cases': {}}
    for case in CASES:
        result, data, command = run(arm, case, counts=(arm == 'counts'))
        run(arm, case, stress=True, counts=(arm == 'counts'))
        entry = {'svg_sha256': sha_bytes(data), 'svg_bytes': len(data),
                 'status': result.returncode, 'stdout': result.stdout.decode(),
                 'gc_stress_checked': True, 'command': command}
        if arm == 'counts':
            entry['host_counts'] = {line.split()[1]: int(line.split()[2])
              for line in result.stderr.decode().splitlines() if line.startswith('HOST_COUNT ')}
        evidence['arms'][arm]['cases'][case] = entry
(HERE / 'qualification.json').write_text(json.dumps(evidence, indent=2) + '\n')
print(json.dumps({case: evidence['arms']['counts']['cases'][case]['host_counts'] for case in CASES}, indent=2))
