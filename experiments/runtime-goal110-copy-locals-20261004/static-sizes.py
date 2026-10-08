"""Pin paired guest artifacts and measure whole-entry static costs.

Instruction and stack-reference counts include all untaken paths. They do not
estimate executed kernel costs. Both host compilers are Debug; guest policy is
ReleaseFast, with actual LLVM optimization 3 and full LTO.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
HARNESS = ROOT.parent / 'runtime-parity-harness-20261003'
ENTRY = 'myl_f_b5d931620df636deef979a0d59c3f9f39f360f8d212025d8bcb427e874f639a5'
records = []
for arm in ('before', 'candidate'):
    for backend in ('llvm', 'qbe'):
        binary = (HARNESS / '.mylang-cache/runtime-candidate-730a86e6-debug/runner/bin' / f'compute-my-{backend}'
                  if arm == 'before' else ROOT / '.mylang-cache/goal110-calls-d14e26f4-guests' / f'compute-my-{backend}')
        symbols = subprocess.check_output(['nm', '-S', '--defined-only', str(binary)], text=True)
        matches = [line.split() for line in symbols.splitlines() if line.split()[-1] == ENTRY]
        assert len(matches) == 1
        address, size = [int(part, 16) for part in matches[0][:2]]
        sections = subprocess.check_output(['readelf', '-SW', str(binary)], text=True)
        section = re.search(r'\]\s+\.text\s+\S+\s+\S+\s+\S+\s+(\S+)', sections)
        assert section
        disassembly = subprocess.check_output(['objdump', '-d', f'--disassemble={ENTRY}', str(binary)], text=True)
        (EVIDENCE / f'{backend}-{arm}-entry.s').write_text(disassembly)
        instructions = [line for line in disassembly.splitlines()
                        if len(line.split('\t')) >= 3 and re.match(r'^\s*[0-9a-f]+:\s', line)]
        manifest = Path(str(binary) + '.qbe-manifest.json')
        policy = json.loads(manifest.read_text())
        assert policy['backend'] == backend
        assert backend != 'llvm' or (str(policy['optimization']) == '3' and policy['lto'])
        records.append({'backend': backend, 'arm': arm, 'binary': str(binary),
                        'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                        'manifest_sha256': hashlib.sha256(manifest.read_bytes()).hexdigest(),
                        'entry_symbol': ENTRY, 'entry_address': address, 'entry_bytes': size,
                        'whole_text_bytes': int(section.group(1), 16), 'static_instructions': len(instructions),
                        'frame_allocations': [line.strip() for line in instructions if re.search(r'\bsub\s+\$[^,]+,%rsp', line)],
                        'instructions_referencing_rsp_or_rbp': sum('%rsp' in line or '%rbp' in line for line in instructions)})
report = {'kind': 'whole-entry-static-cost-not-executed-kernel-cost',
          'source_revision': 'd14e26f4473d6c50f56751736ed8ef325adcaecd',
          'before_source_revision': '730a86e6', 'host_mode': 'Debug', 'guest_mode': 'ReleaseFast',
          'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'records': records}
(EVIDENCE / 'static-sizes.json').write_text(json.dumps(report, indent=2) + '\n')
for record in records:
    print(record['arm'], record['backend'], record['entry_bytes'], record['whole_text_bytes'], record['binary_sha256'])
