import json
from pathlib import Path
import subprocess
import sys
import time

root = Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012')
evidence = root / 'experiments/lox-eda-parity-20261013'
attempt = evidence / 'attempts/runtime-004'
work = root / '.tmp/lox-eda-parity/coordinator/runtime-004-finalization'
work.mkdir(exist_ok=False)
assert len(list((attempt / 'runtime').glob('*.chunk[0-9][0-9].json'))) == 780
assert len(list((attempt / 'runtime').glob('*.chunk12.json'))) == 60
install = root / '.tmp/lox-eda-parity/coordinator/common-004/install'
args = [
    '--root', str(root), '--compiler', str(install / 'bin/mylang'),
    '--install', str(install), '--attempt', 'runtime-004',
    '--prior-root', str(root / 'experiments/lox-eda-improvements-20261012'),
    '--lox-build', str(evidence / 'attempts/native-004/build/lox/build-receipt.json'),
    '--eda-build', str(evidence / 'attempts/native-004/build/eda/build-receipt.json'),
]
commands = [
    ('count', [sys.executable, '-B', str(evidence / 'pipeline.py'), 'count', *args]),
    ('report', [str(root / 'scripts/build-slot.sh'), 'build', sys.executable, '-B', str(evidence / 'report_verified.py'), '--output',
                str(evidence / 'coordinator/report-validation-004'), '--', 'report', *args]),
    ('summary', [sys.executable, '-B', str(evidence / 'summarize.py'),
                 str(attempt / 'parity-report.json'), str(attempt / 'summary')]),
]
for name, command in commands:
    (work / (name + '.command.json')).write_text(json.dumps(command, indent=2) + '\n')
    start = time.monotonic()
    with (work / (name + '.log')).open('w') as log:
        code = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT).returncode
    result = {'step': name, 'returncode': code, 'elapsed_seconds_including_admission': time.monotonic() - start}
    (work / (name + '.status.json')).write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)
    if code:
        sys.exit(code)
