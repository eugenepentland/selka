#!/usr/bin/env python3
"""Immutable same-fixture verification counters; never a timing comparison."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SOURCE = ROOT / 'experiments/lox-eda-parity-20261013/source/eda'
WORK = ROOT / '.tmp/lox-eda-parity/P5'
COMPILER = Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-002/install/bin/mylang')
VERIFY = 'experiments/lox-eda-parity-20261013/source/eda/kicad_sch_verify.my'
BASE = '5a8bc86c67287a92219e28ea4287af80a86d8cc4'

LARGE = '''
func p5_count_labels(out: Stream, n: int) -> int:
    mut fields: bytes[] = []
    mut labels: bytes[] = []
    for i in range(n):
        mut name = b"NET" + str(i).encode()
        fields.append(b"  (global_label \\\"" + name + b"\\\" (at 43.18 36.83 180))\\n")
        labels.append(name)
    mut source = replace_owned(minimal_doc(), b"  (global_label \\\"NETA\\\" (at 43.18 36.83 180))\\n", b"".join(fields))
    mut want = minimal_expect()
    want.labels = labels
    match m.check(source, want):
        case Err(e):
            out.print("probe error: " + e)
            return 1
        case Ok(report):
            # Minimal label fixtures omit font effects and do not draw text.
            assert report.texts == 0 and report.overlaps == 0
            out.print(f"verify-labels:{n}:{report.texts}:{report.overlaps}")
            return 0
'''


def main():
    phase = sys.argv[1]
    assert phase in ('baseline', 'candidate', 'baseline-v2', 'candidate-v2')
    target = WORK / f'verify-{phase}'
    target.mkdir(parents=True, exist_ok=False)
    for path in SOURCE.glob('*.my'):
        (target / path.name).write_bytes(path.read_bytes())
    if phase.startswith('baseline'):
        old = subprocess.check_output(['git', 'show', f'{BASE}:{VERIFY}'], cwd=ROOT)
        (target / 'kicad_sch_verify.my').write_bytes(old)
    tests = (target / 'kicad_sch_verify_test.my').read_text()
    functions = re.findall(r'^public func (test_\w+)\(out: Stream\)', tests, re.M)
    assert len(functions) == 10, functions
    driver = '\nfunc main(args: str[], out: Stream) -> int:\n'
    driver += '    mut n = 16\n    if len(args) > 1 and args[1] == "64":\n        n = 64\n'
    driver += ''.join(f'    assert {name}(out)\n' for name in functions)
    driver += '    return p5_count_labels(out, n)\n'
    (target / 'kicad_sch_verify_test.my').write_text(tests + LARGE + driver)
    manifest = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(target.glob('*.my'))}
    env = dict(os.environ, MYL_CORE_LEAKCHECK='1')
    command = [str(ROOT / 'scripts/build-slot.sh'), 'build', str(COMPILER),
               'build', str(target / 'kicad_sch_verify_test.my'), '--release',
               '--experimental-zero-rc', '--counters', '--cache-dir',
               str(target / 'cache'), '-o', str(target / 'probe'),
               '--emit-llvm', str(target / 'probe.ll')]
    with (HERE / f'verify-{phase}-build.log').open('w') as output:
        status = subprocess.run(command, cwd=ROOT, env=env,
                                stdout=output, stderr=subprocess.STDOUT).returncode
    receipt = {'phase': phase, 'baseline_source_commit': BASE, 'command': command,
               'build_returncode': status, 'files': manifest,
               'compiler_sha256': hashlib.sha256(COMPILER.read_bytes()).hexdigest(),
               'label': 'bounded verification counters; no runtime/RSS claim', 'runs': []}
    if status == 0:
        receipt['binary_sha256'] = hashlib.sha256((target / 'probe').read_bytes()).hexdigest()
        (HERE / f'verify-{phase}-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        for n in (16, 64):
            counts = HERE / f'verify-{phase}-{n}-counters.json'
            run_env = dict(env, MYLANG_COUNTERS=str(counts))
            argv = [str(ROOT / 'scripts/build-slot.sh'), 'build', 'timeout', '30',
                    str(target / 'probe'), 'unused', str(n)]
            result = subprocess.run(argv, cwd=ROOT, env=run_env,
                                    text=True, capture_output=True)
            (HERE / f'verify-{phase}-{n}-stdout.txt').write_text(result.stdout)
            (HERE / f'verify-{phase}-{n}-stderr.txt').write_text(result.stderr)
            expected = f'verify-labels:{n}:0:0\n'
            receipt['runs'].append({'n': n, 'argv': argv, 'returncode': result.returncode,
                                    'stdout': result.stdout,
                                    'counters_sha256': hashlib.sha256(counts.read_bytes()).hexdigest()})
            (HERE / f'verify-{phase}-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
            assert result.returncode == 0 and result.stdout == expected, result
    (HERE / f'verify-{phase}-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    assert status == 0, status


if __name__ == '__main__':
    main()
