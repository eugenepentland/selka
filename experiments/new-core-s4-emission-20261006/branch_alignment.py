#!/usr/bin/env python3
"""Private paired whole/split branch-alignment control; caller owns build slot."""
import argparse
import collections
import fcntl
import hashlib
import json
import random
import re
import shlex
import shutil
import statistics
import subprocess
from pathlib import Path
from types import SimpleNamespace
import paired_units as paired
from entry_assembly import text_section


def identity(path):
    return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def layout(binary, private):
    assembly = subprocess.check_output(['objdump', '-d', '--disassemble=main', str(binary)], text=True)
    (private / 'main.asm').write_text(assembly)
    instructions = []
    for line in assembly.splitlines():
        match = re.match(r'\s*([0-9a-f]+):\s+((?:[0-9a-f]{2} )+)\s*([a-z][a-z0-9]*)\s*(.*)', line)
        if match:
            address = int(match[1], 16)
            instructions.append({'address': address, 'bytes': match[2].strip(), 'mnemonic': match[3], 'operands': match[4]})
    branches = []
    for index, instruction in enumerate(instructions):
        if instruction['mnemonic'].startswith(('j', 'call', 'ret')):
            extent = len(instruction['bytes'].split())
            branches.append({**instruction, 'previous': instructions[max(index - 1, 0)],
                             'crosses16': instruction['address'] % 16 + extent > 16,
                             'crosses32': instruction['address'] % 32 + extent > 32})
    address, body = text_section(binary, 'main')
    return {'main_address': address, 'main_bytes': len(body), 'main_sha256': hashlib.sha256(body).hexdigest(),
            'instruction_counts': dict(collections.Counter(x['mnemonic'] for x in instructions)),
            'branches': branches}


def compare(values, left, right, rng):
    ratios = [a / b for a, b in zip(values[left], values[right])]
    bootstrap = sorted(statistics.median(rng.choices(ratios, k=len(ratios))) for _ in range(10000))
    interval = [bootstrap[250], bootstrap[9749]]
    return {'ratio': statistics.median(values[left]) / statistics.median(values[right]),
            'paired_ratios': ratios, 'paired_median_bootstrap95': interval, 'within_noise': interval[0] <= 1 <= interval[1]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--attributes', type=Path, required=True)
    parser.add_argument('--paired', type=Path, required=True)
    parser.add_argument('--actual', type=Path, required=True)
    parser.add_argument('--whole', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    area = args.evidence.resolve()
    area.relative_to(paired.ROOT / 'experiments')
    area.mkdir(exist_ok=False)
    split_argv = json.loads((args.attributes / 'summary.json').read_text())['cases']['result_propagate']['traced_argv']
    whole_argv = shlex.split((args.paired / 'compile-result_propagate.log').read_text().splitlines()[0][2:])
    inputs = sorted({Path(x) for argv in (split_argv, whole_argv) for x in argv if x.endswith(('.ll', '.o', '.c'))})
    before = [identity(path) for path in inputs]
    policies = {'baseline': [], 'align16': ['-mllvm', '-x86-align-branch-boundary=16', '-mllvm', '-x86-align-branch=fused+jcc+jmp+call+ret'],
                'align32': ['-mbranches-within-32B-boundaries']}
    report = {'production_change': False, 'complete': False, 'tool': identity(Path(shutil.which(split_argv[0])).resolve()),
              'original_split_argv': split_argv, 'original_whole_argv': whole_argv,
              'inputs_before': before, 'policies': policies, 'arms': {}}
    try:
        for policy, added_flags in policies.items():
            for kind, argv, actual in [('whole', whole_argv, args.whole), ('split', split_argv, args.actual)]:
                label = kind + '_' + policy
                private = area / label
                private.mkdir()
                command = argv[:2] + added_flags + argv[2:]
                command[command.index('-o') + 1] = str(private / 'program')
                diagnostic = command[:command.index('-o')] + ['-###', '-c', '-o', str(private / 'dry-run.o'), next(x for x in argv if x.endswith('/entry.ll') or x.endswith('whole-result_propagate.ll'))]
                with (private / 'resolved-flags.log').open('x') as stream:
                    stream.write('$ ' + shlex.join(diagnostic) + '\n')
                    stream.flush()
                    resolved = subprocess.run(diagnostic, stdout=stream, stderr=subprocess.STDOUT)
                    stream.write(f'\nexit={resolved.returncode}\n')
                # Zig still attempts to load the nonexistent output after Clang's -###.
                # Keep that dry-run status separate from actual compile/link status.
                paired.run_build(command, private / 'compile.log')
                binary = private / 'program'
                if policy == 'baseline' and text_section(binary, 'main') != text_section(actual, 'main'):
                    raise ValueError('baseline main address/opcodes differ from actual ' + kind)
                report['arms'][label] = {'argv': command, 'resolved_diagnostic_argv': diagnostic, 'resolved_diagnostic_status': resolved.returncode,
                                         'binary': identity(binary), 'layout': layout(binary, private)}
        if before != [identity(path) for path in inputs]:
            raise ValueError('diagnostic input mutated during native compilation')
        alternatives = {'whole': args.whole, 'actual': args.actual,
                        **{label: area / label / 'program' for label in report['arms']}}
        with Path('/run/user/1000/mylang-slots/cpu10.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            measurement = paired.comparison(SimpleNamespace(rounds=7), 'result_propagate', alternatives, random.Random(91285))
        for size, data in measurement['sizes'].items():
            values = data['cycles_per_unit']
            data['matched_policy_comparisons'] = {policy: compare(values, 'split_' + policy, 'whole_' + policy, random.Random(91824 + int(size)))
                                                 for policy in policies}
        report['measurement'] = measurement
        report['complete'] = True
    finally:
        (area / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
