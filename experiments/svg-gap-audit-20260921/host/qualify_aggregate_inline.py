#!/usr/bin/env python3
"""Qualify aggregate-inline generic/typed host pairs without timing."""
import hashlib, json, os, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/svg-gap-audit-20260921/host'
BASE = ROOT / '.tmp/full-svg-benchmark-20260921'
CASES = ('fixture', 'changed-net', 'changed-value')
DOCS = ('lib/modules/straps-synth-lmx2595.sexp',
        'lib/pinouts/lmx2595rhar.sexp', 'lib/interfaces/spi.sexp')
ARMS = {
    'aggregate-inline-metadata-control': False,
    'aggregate-inline-typed-host': False,
    'aggregate-inline-bounded-metadata-control': True,
    'aggregate-inline-bounded-typed-host': True,
}
REFS = json.loads((ROOT / 'experiments/full-svg-benchmark/qualification.json').read_text())['cases']

def sha_bytes(value): return hashlib.sha256(value).hexdigest()
def sha(path): return sha_bytes(Path(path).read_bytes())

def invoke(name, case, extra=(), validate=True):
    project = BASE / 'projects' / case
    output, issue = WORK / f'{name}-{case}.svg', WORK / f'{name}-{case}.issue'
    output.write_bytes(b''); issue.write_bytes(b'')
    env = dict(os.environ)
    for key in list(env):
        if key.startswith('MYLANG_QBE_LLVM_') or key == 'LD_PRELOAD': env.pop(key)
    env.update(MYLANG_MEMORY_LIMIT='268435456',
      MYLANG_SCHEMATIC_DECLARED='io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue',
      MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
    env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': str(project / p) for i, p in enumerate(DOCS)})
    args = [str(WORK / name), '--print-result']
    if ARMS[name] and not any(x.startswith('--max-steps=') for x in extra):
        args.append('--max-steps=100000000')
    args.extend(extra)
    result = subprocess.run(args, cwd=ROOT, env=env, capture_output=True, timeout=90)
    if validate:
        assert (result.returncode, result.stdout, result.stderr, issue.read_bytes()) == (0, b'0\n', b'', b''), (name, case, result)
        assert sha(output) == REFS[case]['mylang-o3']['svg_sha256'], (name, case, sha(output))
    return result, output

evidence = {'passed': True, 'arms': {}}
for name, bounded in ARMS.items():
    arm = {'binary_sha256': sha(WORK / name), 'bounded': bounded, 'cases': {}}
    for case in CASES:
        result, output = invoke(name, case)
        invoke(name, case, ('--gc-stress',))
        arm['cases'][case] = {'svg_sha256': sha(output), 'svg_bytes': output.stat().st_size,
                              'status': result.returncode, 'stdout': result.stdout.decode(),
                              'stderr': result.stderr.decode(), 'gc_stress_checked': True,
                              'max_steps': 100000000 if bounded else None}
    if bounded:
        arm['budget_rejection'] = {}
        for option, marker in (('--max-steps=1', b'R_STEP_LIMIT'),
                               ('--max-frames=1', b'R_FRAME_LIMIT')):
            result, _ = invoke(name, 'fixture', (option,), validate=False)
            assert result.returncode != 0 and marker in result.stderr, (name, option, result)
            arm['budget_rejection'][option] = {
                'status': result.returncode, 'stderr': result.stderr.decode()}
    evidence['arms'][name] = arm
(HERE / 'aggregate-inline-qualification.json').write_text(json.dumps(evidence, indent=2) + '\n')
print(json.dumps({name: item['binary_sha256'] for name, item in evidence['arms'].items()}, indent=2))
