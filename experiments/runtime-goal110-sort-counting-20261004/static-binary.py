#!/usr/bin/env python3
"""Replay the pinned LLVM guest's counting-sort assembly and code sizes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASE = Path('/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-harness-20261003/.mylang-cache/runtime-candidate-730a86e6-releasefast/runner/bin/collections-my-llvm')
CANDIDATE = ROOT / '.mylang-cache/goal110-sort-debug/runner/bin/collections-my-llvm'
PINS = {'baseline': 'b7ae862d780cdfc4535003f4bf0529e95f583e1b633ba3cbf1de3260899ec1c1',
        'candidate': 'f3795333fc89bec452c4e24abdd52536040457e16f235dc96177c11b01519538'}
NAMES = ('myl_native_list_sort_keyed', 'keyed_place', 'keyed_sort_words', 'keyed_sort_entries', 'keyed_permute')


def output(*args):
    return subprocess.check_output(args, text=True)


def describe(path, label):
    assert hashlib.sha256(path.read_bytes()).hexdigest() == PINS[label]
    symbols = {}
    for line in output('nm', '-S', '-n', str(path)).splitlines():
        fields = line.split()
        if len(fields) == 4 and fields[3] in NAMES:
            symbols[fields[3]] = {'address': '0x' + fields[0].lstrip('0'), 'bytes': int(fields[1], 16)}
    text = re.search(r'\]\s+\.text\s+PROGBITS\s+\S+\s+\S+\s+(\S+)', output('readelf', '-SW', str(path)))
    return {'path': str(path.resolve()), 'sha256': PINS[label], 'symbols': symbols,
            'listed_symbol_bytes': sum(row['bytes'] for row in symbols.values()), 'whole_text_bytes': int(text[1], 16)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, default=BASE)
    parser.add_argument('--candidate', type=Path, default=CANDIDATE)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    binaries = {'baseline': describe(args.baseline, 'baseline'), 'candidate': describe(args.candidate, 'candidate')}
    assembly = {name: output('objdump', '-d', '--no-show-raw-insn', '--disassemble=' + name, str(args.candidate))
                for name in ('keyed_sort_words', 'keyed_permute')}
    words, gather = assembly['keyed_sort_words'], assembly['keyed_permute']
    assert '10567a0:' in words and '10567e4:' in words
    assert 'mov    $0x20,%r9d' in words and 'call   1057350 <keyed_permute>' in words
    assert 'vpsrlvq' in gather and '10574a4:' in gather and '(%r15,%rcx,8),%rdx' in gather
    assert '1057842:' in gather and '0x10(%rsi),%rax' in gather and 'vmovdqu %xmm0,(%rdi)' in gather
    report = {'schema': 'mylang-goal110-sort-binary-v1', 'status': 'pass',
              'source_revision': '2a49da2960ad76471cbf2764c068d724cb9c5121',
              'compiler_policy': 'Candidate host Debug; LLVM guest ReleaseFast, O3, LTO. Baseline host ReleaseFast; same guest policy.',
              'binaries': binaries,
              'assembly_sha256': {name: hashlib.sha256(value.encode()).hexdigest() for name, value in assembly.items()},
              'observations': [
                  'LLVM keyed_sort_words writes the inverse high lanes at 0x10567a0..0x10567e4.',
                  'The counting path passes shift=32 to keyed_permute at 0x105680e..0x1056814.',
                  'keyed_permute compacts the selected lane, then gathers cycles using the original fixed-point/mark/prefetch handling.',
                  'The 24-byte nonclosing gather at 0x1057842..0x1057852 performs one full element transfer, instead of the former three transfers.',
              ],
              'limitations': ['Pinned assembly and code sizes are static evidence only, not a runtime performance result.',
                              'The host compiler modes differ; a ReleaseFast host receipt is still required for acceptance.']}
    if args.output:
        with args.output.open('x') as target:
            target.write(json.dumps(report, indent=2) + '\n')
    else:
        assert report == json.loads(Path(__file__).with_name('static-binary.json').read_text())
    print('PASS pinned LLVM counting inversion/gather and code-size inspection')


if __name__ == '__main__':
    main()
