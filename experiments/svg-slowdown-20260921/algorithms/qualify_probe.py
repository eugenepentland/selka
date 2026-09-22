#!/usr/bin/env python3
import hashlib, json, os, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / '.tmp/svg-slowdown-20260921/algorithms'
FIXTURES = ROOT / '.tmp/full-svg-benchmark-20260921/projects'
REFERENCE = ROOT / 'experiments/full-svg-benchmark/artifacts'
BINARY = Path(os.environ.get('SCHEMATIC_PROBE_BINARY', WORK / 'mylang-o3-part-pin'))
RESULT = Path(os.environ.get('SCHEMATIC_PROBE_RESULT', Path(__file__).with_name('probe-qualification.json')))
CASES = ('fixture', 'changed-net', 'changed-value')

def sha(data): return hashlib.sha256(data).hexdigest()
def invoke(case, stress=False):
    project = FIXTURES / case
    output = WORK / f'{case}{"-stress" if stress else ""}.svg'
    issue = WORK / f'{case}.issue'
    issue.write_bytes(b'')
    env = dict(os.environ, MYLANG_SCHEMATIC_DECLARED='io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue', MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
    for i, path in enumerate(('lib/modules/straps-synth-lmx2595.sexp','lib/pinouts/lmx2595rhar.sexp','lib/interfaces/spi.sexp')):
        env[f'MYLANG_SCHEMATIC_INPUT_{i}'] = str(project / path)
    args=[str(BINARY),'--print-result']
    if BINARY.name.endswith('-bounded'):
        args.append('--max-steps=100000000')
    args += (['--gc-stress'] if stress else [])
    p=subprocess.run(args,cwd=ROOT,env=env,capture_output=True,timeout=60)
    assert (p.returncode,p.stdout,p.stderr,issue.read_bytes()) == (0,b'0\n',b'',b''), (case,stress,p,issue.read_bytes())
    return output.read_bytes()

def main():
    result={'passed':True,'cases':{}}
    for case in CASES:
        actual=invoke(case); expected=(REFERENCE/f'{case}-mylang-o3.svg').read_bytes()
        assert actual == expected
        stress=invoke(case,True); assert stress == actual
        result['cases'][case]={'svg_sha256':sha(actual),'svg_bytes':len(actual),'equals_baseline':True,'gc_stress_equals_normal':True}
    RESULT.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
if __name__ == '__main__': main()
