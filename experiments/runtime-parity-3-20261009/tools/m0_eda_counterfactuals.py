#!/usr/bin/env python3
"""Complete EDA M0 probes with the equivalent scalable matcher, then confirm all probes."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
AREA = Path(__file__).resolve().parents[1]
WORK = ROOT / '.mylang-cache/rp3/counterfactuals-v2'
EDA = Path('/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore')


def main():
    cases = json.loads((EDA / 'golden/manifest.json').read_text())['cases']
    for name in ('rds3+flat', 'labstation'):
        case = next(case for case in cases if case['id'] == name)
        output = WORK / ('eda-output-' + name)
        argv = ['--model', str(EDA / 'golden/cases' / name / 'model.sexp'),
                '--project-dir', str(EDA / 'golden/projects' / case['project']),
                '--out-dir', str(output), *case['flags']]
        command = [str(ROOT / 'scripts/build-slot.sh'), 'build', sys.executable, str(AREA / 'tools/cf_current.py'),
                   '--program', str(ROOT / '.mylang-cache/eda-src/src/main.my'),
                   '--mylang', '/home/epentland/.cache/mylang/rp3-base-41ed360fb/bin/mylang',
                   '--work', str(WORK), '--name', 'eda-' + name, '--cwd', str(ROOT / '.mylang-cache/eda-src'),
                   '--variants', 'base,norc,checks+norc,reference-inline', '--rounds', '5', '--cpu', '8', '--keep',
                   '--outdir-check', str(output), '--case', name + '=' + json.dumps(argv)]
        with (ROOT / '.tmp/rp3' / ('cf-eda-' + name + '-fast-matcher.log')).open('w') as log:
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        data = json.loads((WORK / ('eda-' + name) / 'result.json').read_text())
        (AREA / 'M0' / ('counterfactual-cpu8-eda-' + name + '.json')).write_text(json.dumps(data, indent=1) + '\n')
    with (ROOT / '.tmp/rp3/counterfactual-cpu10.log').open('w') as log:
        subprocess.run([sys.executable, str(AREA / 'tools/confirm_cf.py'), '--work', str(WORK),
                        '--out', str(AREA / 'M0/counterfactual-cpu10.json')], cwd=ROOT,
                       stdout=log, stderr=subprocess.STDOUT, check=True)


if __name__ == '__main__':
    main()
