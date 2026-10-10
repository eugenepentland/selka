#!/usr/bin/env python3
"""Sample allocation/destruction instructions with identical bounded LBR attribution."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'experiments/runtime-parity-3-20261009/tools'))
import corpus_perf

ALL_FAMILY = {
    'block_new', 'block_new_slow', 'block_free', 'core_free_pending',
    'block_alloc', 'small_alloc', 'aligned_alloc',
    'myl_core_list_new', 'myl_core_list_new_slow', 'myl_core_list_grow',
    'myl_core_box_new', 'myl_core_free', 'myl_core_free_block',
    'core_children', 'core_dict_children', 'dict_release_part',
    'myl_core_release_child_pending', 'core_release_child', 'reference_at', 'guard_holds',
    'malloc', '__libc_malloc', '_int_malloc', 'calloc', '__libc_calloc',
    'realloc', '__libc_realloc', '_int_realloc', 'free', '__libc_free', '_int_free',
    'core_dict_finalize', 'myl_core_release', 'count_free_shared',
}


# These helpers also traverse references for sharing, retaining copied elements,
# or non-final decrements. Without an allocating/freeing ancestor the sampled
# instruction cannot be assigned to allocation/free alone.
AMBIGUOUS_FAMILY = {
    'core_children', 'core_dict_children', 'reference_at', 'guard_holds',
    'dict_release_part', 'myl_core_release',
}
FAMILY = ALL_FAMILY - AMBIGUOUS_FAMILY


def generated_release(symbol):
    return (symbol.startswith('myl.layout.') or symbol.startswith('myl.dict.')) and '.release' in symbol


def ambiguous(symbol):
    symbol = canonical(symbol)
    return symbol in AMBIGUOUS_FAMILY or generated_release(symbol) and (
        '.release.key' in symbol or '.release.value' in symbol)


def classify_stack(stack):
    strict = any(allocation(symbol) for symbol in stack)
    # A visible allocation/free frame owns all descendants in its sampled stack.
    # Ambiguity is disjoint, so one instruction period is never counted twice.
    return strict, not strict and any(ambiguous(symbol) for symbol in stack)


def canonical(symbol):
    return symbol.removesuffix(' (inlined)').split('+0x')[0]


def allocation(symbol):
    symbol = canonical(symbol)
    return symbol in FAMILY or generated_release(symbol) and not ambiguous(symbol)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--tag', required=True)
    p.add_argument('--cache-tag', help='Scratch namespace; --tag still selects qualified binaries')
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--repeat', type=int, default=40)
    a = p.parse_args()
    work = ROOT / '.mylang-cache/u2/profile' / (a.cache_tag or a.tag)
    work.mkdir(parents=True, exist_ok=True)
    result = {'tag': a.tag, 'cpu': 8, 'event': 'cpu_core/instructions/u', 'period': 100003, 'repeat': a.repeat,
              'attribution': 'Strict allocator/free frames and their visible descendants. Shared traversal and release-only helpers without a strict ancestor are reported separately as ambiguous. Each instruction period counted at most once.',
              'limitation': 'Bounded LBR stacks may omit ancestors. Emitted inline allocator/free code without distinct inline metadata stays in its guest symbol, so this is a measured lower bound, not proof of a share below15%.',
              'family': sorted(FAMILY), 'ambiguous_family': sorted(AMBIGUOUS_FAMILY), 'designs': {}}
    for arm in corpus_perf.arms_for(a.tag):
        if arm['program'] not in ('eda/rds3+flat', 'eda/labstation'):
            continue
        name = arm['program'].split('/')[1]
        perf = work / (name + '.perf')
        command = [sys.executable, '-c', 'import subprocess,sys; [subprocess.run(sys.argv[2:],check=True,stdout=subprocess.DEVNULL) for _ in range(int(sys.argv[1]))]', str(a.repeat), *arm['argv']]
        binary_sha256 = hashlib.sha256(Path(arm['argv'][0]).read_bytes()).hexdigest()
        subprocess.run(['taskset', '-c', '8', 'perf', 'record', '-q', '-e', result['event'], '-c', str(result['period']), '--call-graph', 'lbr', '-o', str(perf), '--', *command], cwd=arm['cwd'], check=True)
        raw = subprocess.check_output(['perf', 'script', '-i', str(perf), '-F', 'comm,period,ip,sym', '--inline'], text=True)
        symbols = collections.Counter()
        total = matched = ambiguous_period = 0
        examples = []
        for event in raw.split('\n\n'):
            lines = event.splitlines()
            if not lines or not lines[0].startswith('eda-plain '):
                continue
            period = int(lines[0].split()[1])
            stack = [canonical(line.strip().split(' ', 1)[1].strip()) for line in lines[1:] if ' ' in line.strip()]
            total += period
            if stack:
                symbols[stack[0]] += period
            strict, uncertain = classify_stack(stack)
            if uncertain:
                ambiguous_period += period
            if strict:
                matched += period
                if len(examples) < 3:
                    examples.append(stack)
        assert hashlib.sha256(Path(arm['argv'][0]).read_bytes()).hexdigest() == binary_sha256
        result['designs'][name] = {'total_period': total, 'allocation_release_period': matched,
            'allocation_release_share_lower_bound': matched / total,
            'ambiguous_period': ambiguous_period, 'ambiguous_share': ambiguous_period / total,
            'exclusive_family': {symbol: n for symbol, n in symbols.items() if allocation(symbol)},
            'top_exclusive': symbols.most_common(35), 'examples': examples,
            'binary_sha256': binary_sha256,
            'raw_sha256': hashlib.sha256(perf.read_bytes()).hexdigest(), 'raw_scratch': str(perf.relative_to(ROOT))}
        print(name, matched / total, flush=True)
    a.out.write_text(json.dumps(result, indent=1) + '\n')


if __name__ == '__main__':
    main()
