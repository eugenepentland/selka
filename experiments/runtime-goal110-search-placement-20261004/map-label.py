#!/usr/bin/env python3
"""Map original LTO local labels using disposable zero-byte symbol aliases."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
WORK = ROOT / '.mylang-cache/goal110-search-placement'
CAPTURE = WORK / 'capture'
MAP = WORK / 'mapping'
MAP.mkdir(parents=True, exist_ok=True)
KERNEL = 'myl_f_1af80ea2572d9d5f91426ffa7805826aa9a97e2ce757b902d5901fdbfc722f76'


def binding(path):
    return {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'bytes': path.stat().st_size}


build = json.loads((CAPTURE / 'capture-build.json').read_text())
assert build['exact_guest_reproduction'] and build['exit_status'] == 0
calls = [json.loads(path.read_text()) for path in (CAPTURE / 'tool-calls').glob('*/call.json')]
lto, = [call for call in calls if 'raw_assembly' in call]
raw_path = Path(lto['raw_assembly']['saved']['path'])
raw = raw_path.read_text()
assert binding(raw_path)['sha256'] == lto['raw_assembly']['saved']['sha256']
start = raw.index('\n' + KERNEL + ':')
end = raw.index('\n.Lfunc_end', start)
body = raw[start:end]
labels = re.findall(r'^(\.LBB[0-9]+_[0-9]+):', body, re.MULTILINE)
assert len(labels) == len(set(labels)) > 10
aliases = '\n'.join('\t.globl myl_diag_' + label[1:] + '\n\t.set myl_diag_' + label[1:] + ', ' + label
                    for label in labels)
modified = raw[:end] + '\n' + aliases + '\n' + raw[end:]
mapping = MAP / 'mapping-only.s'
mapping.write_text(modified)
object_path = MAP / 'mapping-only.o'
real = lto['real_zig']['path']
command = [str(ROOT / 'scripts/build-slot.sh'), 'build', real, 'cc', '-g0', '-c', str(mapping), '-o', str(object_path)]
result = subprocess.run(command, capture_output=True, text=True, check=True)
assert not result.stdout and not result.stderr
symbols = subprocess.check_output(['nm', '-S', '--defined-only', str(object_path)], text=True)
(MAP / 'symbols.txt').write_text(symbols)
kernel_line, = [line for line in symbols.splitlines() if line.split()[-1] == KERNEL]
kernel_at = int(kernel_line.split()[0], 16)
matches = [line for line in symbols.splitlines() if line.split()[-1].startswith('myl_diag_')
           and int(line.split()[0], 16) - kernel_at == 0xd60]
loop_line, = matches
label = '.' + loop_line.split()[-1].removeprefix('myl_diag_')
assert label in labels
raw_lines = raw.splitlines()
line, = [index for index, value in enumerate(raw_lines) if value.split('#', 1)[0].strip() == label + ':']
assert any(re.search(r'\bj(?:ne|nz)\s+' + re.escape(label) + r'\b', value) for value in raw_lines[line:line + 250])
report = {'status': 'mapped', 'source_revision': build['source_revision'], 'driver': binding(Path(__file__)),
          'capture_build': binding(CAPTURE / 'capture-build.json'), 'original_raw_assembly': binding(raw_path),
          'original_guest': build['guest'], 'mapping_assembly': binding(mapping), 'mapping_object': binding(object_path),
          'symbols': binding(MAP / 'symbols.txt'), 'command': command, 'stdout': result.stdout, 'stderr': result.stderr,
          'kernel_symbol': KERNEL, 'kernel_object_offset': kernel_at, 'loop_offset': 0xd60,
          'loop_label': label, 'source_line': line + 1, 'context': raw_lines[line - 6:line + 15],
          'alias_policy': 'Global symbol aliases added only to disposable mapping object; no code/data bytes or performance guest altered.'}
(MAP / 'label-proof.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS mapped', label, 'offset0xd60; disposable aliases only')
