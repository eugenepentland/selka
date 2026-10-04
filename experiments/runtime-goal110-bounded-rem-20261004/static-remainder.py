#!/usr/bin/env python3
"""Read-only, exact-ELF-bound remainder inspection; no timing or objcopy."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

SYMBOL = 'myl_f_4c388c09641a7cf53a57c584f19db2c37bf5f9318d201409d2cca2d83d777934'
PINS = {
    'before-llvm': '02e90fd182b34d87d33b9f9b3cdbadc9bcf2025b9a21e2bb2d1ceac869545efb',
    'before-qbe': '6b7cd8aaa1c8bfd0bdcb921f6318c2d3202c38d7b25f62be60e0ed5d017ca48d',
    'after-llvm': 'fd657f721993a374cc9c0d6990a021c5380a9e0046fd61bb30cf14f63322ce1a',
    'after-qbe': '7d4480524c4a88fcbcea755c4fc50ec5a9f94191e4208f9761177cf894aa32e7',
}
# Manually reviewed append PC55 regions, valid only for the exact pinned ELFs.
REGIONS = {
    'before-llvm': {'fast_dividend_remainder': (0x1034c9a, 0x1034cd8)},
    'after-llvm': {'fast_dividend_remainder': (0x1034c88, 0x1034cab),
                   'original_checked_dividend_remainder': (0x1034ddc, 0x1034e2c)},
    'before-qbe': {'fast_dividend_remainder': (0x101bb94, 0x101bbe7)},
    'after-qbe': {'fast_dividend_remainder': (0x101bb91, 0x101bbbf)},
}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def renamed(text):
    names = {}; counters = {}
    def substitute(match):
        token = match[0]
        prefix = re.sub(r'\d+$', '', token)
        if token not in names:
            names[token] = prefix + str(counters.get(prefix, 0))
            counters[prefix] = counters.get(prefix, 0) + 1
        return names[token]
    return re.sub(r'%v\d+|@[A-Za-z_]+\d+', substitute, text)


def stored_policies(root, work, label):
    policies = {}
    for path in (root / 'mycache/frontend/fragments').glob('*/il/*'):
        if not path.is_file():
            continue
        with path.open('rb') as source:
            header = source.read(1024)
        if SYMBOL.encode() not in header:
            continue
        text = path.read_text()
        start = text.index('\n@fi55\n')
        original = text.index('\n@oi55\n', start)
        end = text.index('\n@i75\n', original)
        fast, fallback = text[start:original], text[original:end]
        policy = 'llvm' if ' rem ' in fallback else 'qbe'
        assert policy not in policies, 'ambiguous saved scalar policy'
        guard_start = text.rindex('# mylang-rc-append-range 55', 0, start)
        for name, body in (('guard', text[guard_start:start]), ('fast', fast), ('fallback', fallback)):
            (work / f'{label}-{policy}-{name}.ssa').write_text(body)
        policies[policy] = {'stored_il': str(path.resolve()), 'stored_il_sha256': digest(path),
                            'fast_signed_rem': fast.count(' rem '), 'fast_unsigned_rem': fast.count('urem'),
                            'fast_arithmetic_shift': len(re.findall(r'\bsar\b', fast)),
                            'fast_unsigned_multiply_high': len(re.findall(r'\bumulh\b', fast)),
                            'fallback_signed_rem': fallback.count(' rem '),
                            'normalized_guard_sha256': hashlib.sha256(renamed(text[guard_start:start]).encode()).hexdigest(),
                            'normalized_fallback_sha256': hashlib.sha256(renamed(fallback).encode()).hexdigest()}
    assert set(policies) == {'llvm', 'qbe'}
    return policies


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before-manifest', type=Path, required=True)
    parser.add_argument('--after-manifest', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    report = {'schema': 'mylang-goal110-bounded-rem-static-v1', 'status': 'complete',
              'helper_sha256': digest(__file__), 'symbol': SYMBOL, 'manifests': {}, 'binaries': {}, 'stored_policies': {},
              'limitations': ['Static instruction removal proves a mechanism, not a performance result.',
                              'SSA policies are identified independently; QBE IL is not evidence of LLVM emission.',
                              'Machine ranges are manually identified and admitted only for exact pinned ELF bytes.']}
    for label in ('before', 'after'):
        path = getattr(args, label + '_manifest').resolve()
        manifest = json.loads(path.read_text())
        report['manifests'][label] = {'path': str(path), 'sha256': digest(path),
                                     'source_revision': manifest['identity']['source_revision']}
        report['stored_policies'][label] = stored_policies(path.parent, args.work, label)
        for backend in ('llvm', 'qbe'):
            arm = label + '-' + backend
            binary = Path(manifest['identity']['binary_paths']['collections/my-' + backend])
            assert digest(binary) == PINS[arm] == manifest['binary_hashes']['collections/my-' + backend]
            nm = subprocess.check_output(['nm', '-S', '--defined-only', str(binary)], text=True)
            rows = [line.split() for line in nm.splitlines() if line.split()[-1] == SYMBOL]
            assert len(rows) == 1
            address, size = (int(value, 16) for value in rows[0][:2])
            sections = subprocess.check_output(['readelf', '-SW', str(binary)], text=True)
            section = re.search(r'\]\s+\.text\s+PROGBITS\s+\S+\s+\S+\s+(\S+)', sections)
            assert section
            assembly = subprocess.check_output(['objdump', '-d', '-Mintel', '--no-show-raw-insn', '--disassemble=' + SYMBOL, str(binary)], text=True)
            (args.work / (arm + '-batch.asm')).write_text(assembly)
            instructions = {}
            for line in assembly.splitlines():
                match = re.match(r'\s*([0-9a-f]+):\s+([a-z].*)$', line)
                if match:
                    instructions[int(match[1], 16)] = match[2].strip()
            regions = {}
            for name, (start, end) in REGIONS.get(arm, {}).items():
                assert address <= start < end <= address + size
                selected = {hex(pc): ins for pc, ins in instructions.items() if start <= pc < end}
                assert selected
                regions[name] = {'start': hex(start), 'end_exclusive': hex(end), 'instructions': selected,
                                 'instruction_count': len(selected)}
            report['binaries'][arm] = {'path': str(binary), 'sha256': digest(binary), 'batch_address': hex(address),
                                       'batch_bytes': size, 'whole_text_bytes': int(section[1], 16), 'regions': regions}
    before, after = report['stored_policies']['before'], report['stored_policies']['after']
    for backend in ('llvm', 'qbe'):
        assert before[backend]['normalized_guard_sha256'] == after[backend]['normalized_guard_sha256']
        assert before[backend]['normalized_fallback_sha256'] == after[backend]['normalized_fallback_sha256']
    assert before['llvm']['fast_signed_rem'] == after['llvm']['fast_unsigned_rem'] == 1
    assert after['llvm']['fast_signed_rem'] == 0 and after['llvm']['fallback_signed_rem'] == 1
    assert before['qbe']['fast_arithmetic_shift'] == 1 and after['qbe']['fast_arithmetic_shift'] == 0
    before_machine = report['binaries']['before-llvm']['regions']['fast_dividend_remainder']['instructions']
    after_machine = report['binaries']['after-llvm']['regions']['fast_dividend_remainder']['instructions']
    assert len(before_machine) == 15 and len(after_machine) == 7
    assert sum(ins.startswith('sar ') for ins in before_machine.values()) == 2
    assert not any(ins.startswith('sar ') for ins in after_machine.values())
    assert any(ins.startswith('mulx ') for ins in after_machine.values())
    fallback = report['binaries']['after-llvm']['regions']['original_checked_dividend_remainder']['instructions']
    assert any(ins.startswith('jo ') for ins in fallback.values())
    assert sum(ins.startswith('sar ') for ins in fallback.values()) == 2
    qbe_before = report['binaries']['before-qbe']['regions']['fast_dividend_remainder']['instructions']
    qbe_after = report['binaries']['after-qbe']['regions']['fast_dividend_remainder']['instructions']
    assert len(qbe_before) == 21 and len(qbe_after) == 9
    assert any(ins.startswith('sar ') for ins in qbe_before.values())
    assert not any(ins.startswith('sar ') for ins in qbe_after.values())
    for binary in report['binaries'].values():
        assert digest(binary['path']) == binary['sha256']
    for manifest in report['manifests'].values():
        assert digest(manifest['path']) == manifest['sha256']
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print('PASS exact-ELF static mechanism: LLVM15→7/QBE21→9 remainder instructions, signed checked original retained; both saved-policy guards and fallbacks identical')


if __name__ == '__main__':
    main()
