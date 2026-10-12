#!/usr/bin/env python3
"""Exercise real Zig/C formatter objects under both header layouts, with old control."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BEFORE_COMMIT = 'fbfcaa7a923186a8e773c3760f81c10aa345a432'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--phase', required=True)
args = parser.parse_args()
evidence = HERE / args.phase
assert not evidence.exists(), 'choose a fresh phase'
evidence.mkdir()
scratch = ROOT / '.tmp/memory-closeout/A04/formatting' / args.phase
scratch.mkdir(parents=True)
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
driver = (ROOT / 'src/core/driver.zig').read_text().split('pub const runtime_source =', 1)[1].split(';', 1)[0]
parts = [ROOT / 'src/core' / name for name in re.findall(r'@embedFile\("([^\"]+)"\)', driver)]
c_source = '\n'.join(p.read_text() for p in parts) + '\n' + (HERE / 'probe.c').read_text()
cfile = scratch / 'probe.c'
cfile.write_text(c_source)
report = {'base_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'candidate_diff': subprocess.check_output(['git', 'diff', '--', 'src/core/runtime/core_number.c', 'src/core/runtime/core_number_text.zig'], cwd=ROOT, text=True),
          'zig': os.environ['ZIG'], 'zig_sha256': digest(Path(os.environ['ZIG'])),
          'runtime_sources': {str(p.relative_to(ROOT)): digest(p) for p in parts},
          'c_source_sha256': digest(cfile), 'probe_sha256': digest(HERE / 'probe.c'), 'before_source_commit': BEFORE_COMMIT, 'objects': {}, 'runs': []}
unit_command = [os.environ['ZIG'], 'test', str(ROOT / 'src/core/runtime/core_number_text.zig'), '--test-filter', 'number text']
unit = subprocess.run(unit_command, capture_output=True, text=True, cwd=ROOT)
report['unit'] = {'command': unit_command, 'status': unit.returncode, 'stdout': unit.stdout, 'stderr': unit.stderr}
assert unit.returncode == 0, report['unit']
for variant in ('before', 'after'):
    folder = scratch / variant
    folder.mkdir()
    for name in ('core_number_parse.zig', 'core_number_format.zig', 'core_number_text.zig'):
        target = folder / name
        target.write_bytes((ROOT / 'src/core/runtime' / name).read_bytes())
    if variant == 'before':
        old = subprocess.check_output(['git', 'show', BEFORE_COMMIT + ':src/core/runtime/core_number_text.zig'], cwd=ROOT)
        (folder / 'core_number_text.zig').write_bytes(old)
    obj = folder / 'number.o'
    command = [os.environ['ZIG'], 'build-obj', str(folder / 'core_number_text.zig'), '-OReleaseFast',
               '-target', 'x86_64-linux-gnu.2.31', '-mcpu', 'baseline', '-fPIC', '-fno-stack-check',
               '-fno-stack-protector', '-lc', '-femit-bin=' + str(obj)]
    built = subprocess.run(command, capture_output=True, text=True, cwd=ROOT)
    object_row = {'command': command, 'status': built.returncode, 'stderr': built.stderr,
                  'sources': {p.name: digest(p) for p in folder.glob('*.zig')}}
    report['objects'][variant] = object_row
    if built.returncode:
        (evidence / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
        raise SystemExit(built.stderr)
    object_row['sha256'] = digest(obj)
    for mode, flags in [('ordinary', []), ('zero_rc', ['-DMYL_ZERO_RC'])]:
        binary = folder / mode
        command = [os.environ['ZIG'], 'cc', '-O1', '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections',
                   '-pthread', *flags, str(cfile), str(obj), '-lm', '-o', str(binary)]
        built = subprocess.run(command, capture_output=True, text=True, cwd=ROOT)
        row = {'variant': variant, 'mode': mode, 'build_command': command, 'build_status': built.returncode, 'build_stderr': built.stderr}
        if not built.returncode:
            ran = subprocess.run([str(binary)], capture_output=True, text=True, cwd=folder)
            row.update(status=ran.returncode, stdout=ran.stdout, stderr=ran.stderr, binary_sha256=digest(binary))
        report['runs'].append(row)
        (evidence / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
        print(variant, mode, row.get('status', 'build failed'), row.get('stderr', row['build_stderr'])[:500], flush=True)
for row in report['runs']:
    assert row['build_status'] == 0, row
    assert row['status'] == (1 if row['variant'] == 'before' and row['mode'] == 'zero_rc' else 0), row
report['summary'] = {'ordinary_before_after': 'passed', 'old_zero_rc': 'reproduced wrong ASCII field', 'new_zero_rc': 'passed'}
(evidence / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
