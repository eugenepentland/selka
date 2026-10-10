#!/usr/bin/env python3
"""Instruction-sampled materialization call chains on the two binding EDA designs."""
import argparse
import collections
import json
import hashlib
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'experiments/runtime-parity-3-20261009/tools'))
import corpus_perf


def symbol_name(value):
    value = value.removesuffix(' (inlined)')
    return re.sub(r'\+0x[0-9a-fA-F]+(?:/0x[0-9a-fA-F]+)?$', '', value)


def file_digest(path):
    with Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--tag', required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--repeat', type=int, default=40)
    p.add_argument('--reuse', action='store_true')
    p.add_argument('--callgraph', choices=('dwarf', 'lbr'), default='lbr')
    a = p.parse_args()
    work = ROOT / '.mylang-cache/rp3/s2-profile' / a.tag
    work.mkdir(parents=True, exist_ok=True)
    results = {}
    for arm in corpus_perf.arms_for('base'):
        if arm['program'] not in ('eda/rds3+flat', 'eda/labstation'):
            continue
        name = arm['program'].split('/')[1]
        if a.tag != 'base':
            arm['argv'] = list(arm['argv'])
            arm['argv'][0] = str(corpus_perf.ce.CACHE / 'bin' / a.tag / 'eda-plain')
            output = work / 'out' / name
            output.mkdir(parents=True, exist_ok=True)
            arm['argv'][arm['argv'].index('--out-dir') + 1] = str(output)
        perf = work / (name + ('.lbr.perf' if a.callgraph == 'lbr' else '.perf'))
        # The wrapper runs no builds and gives every EDA arm an absolute owned output.
        command = [sys.executable, '-c', 'import subprocess,sys; [subprocess.run(sys.argv[2:],check=True,stdout=subprocess.DEVNULL) for _ in range(int(sys.argv[1]))]', str(a.repeat), *arm['argv']]
        if not a.reuse:
            subprocess.run(['taskset', '-c', '8', 'perf', 'record', '-q', '-e', 'cpu_core/instructions/u', '-c', '100003', '--call-graph', ('lbr' if a.callgraph == 'lbr' else 'dwarf,8192'), '-o', str(perf), '--', *command], cwd=arm['cwd'], check=True)
        report = subprocess.check_output(['perf', 'report', '-i', str(perf), '--stdio', '--no-children', '--sort', 'comm,symbol', '--field-separator', ';', '--show-total-period', '--percent-limit', '0'], text=True)
        (work / (name + '.report')).write_text(report)
        symbols = collections.Counter()
        for line in report.splitlines():
            fields = line.split(';')
            if len(fields) < 4 or fields[2].strip() != 'eda-plain':
                continue
            symbols[symbol_name(fields[3].strip().removeprefix('[.] '))] += int(fields[1])
        total = sum(symbols.values())
        material = {'str_from', 'core_octets_copy', 'core_text_known', 'core_text_publish', 'myl_core_bytes_slice', 'myl_core_ir_str_slice', 'myl_core_ir_str_from_span', 'myl_core_ir_str_from_view', 'myl_core_str_concat', 'myl_core_bytes_concat', 'myl_core_str_join', 'myl_core_bytes_decode_text', 'core_text_append_bytes'}
        union = sum(n for s, n in symbols.items() if s in material)
        results[name] = {'sampled_instruction_period': total, 'materialization_period': union, 'materialization_share': union / total if total else None,
                         'exclusive': {s: {'period': n, 'share': n / total} for s, n in symbols.most_common() if s in material or 'token' in s or 'lex' in s or 'slice' in s},
                         'top_exclusive': symbols.most_common(30), 'perf_data': str(perf), 'perf_sha256': file_digest(perf),
                         'binary': arm['argv'][0], 'binary_sha256': file_digest(arm['argv'][0]),
                         'materialization_symbols': sorted(material), 'definition': 'normalized-inline-family-union-v2',
                         'limitation': 'DWARF call chains do not unwind guest code. These are exclusive symbol shares; allocation and library memcpy callers are not attributed. No zero inclusive share is inferred.'}
        if a.callgraph == 'lbr':
            raw = subprocess.check_output(['perf', 'script', '-i', str(perf), '-F', 'comm,period,ip,sym', '--inline'], text=True)
            periods = collections.Counter()
            examples = []
            for event in raw.split('\n\n'):
                lines = event.splitlines()
                if not lines or not lines[0].startswith('eda-plain '):
                    continue
                period = int(lines[0].split()[1])
                symbols_in_stack = [symbol_name(line.strip().split(' ', 1)[1].strip()) for line in lines[1:] if ' ' in line.strip()]
                periods['total'] += period
                if any(symbol in material for symbol in symbols_in_stack):
                    periods['material_inclusive'] += period
                if 'myl_core_bytes_slice' in symbols_in_stack:
                    periods['bytes_slice_inclusive'] += period
                    if any('sexpr_tokenizer::make_token' in symbol for symbol in symbols_in_stack):
                        periods['stored_token_slice_inclusive'] += period
                        if len(examples) < 2:
                            examples.append(symbols_in_stack)
            results[name]['inclusive_periods'] = periods
            results[name]['inclusive_shares'] = {key: value / periods['total'] for key, value in periods.items()}
            results[name]['stored_token_examples'] = examples
            results[name]['limitation'] = 'LBR reconstructs bounded hardware call chains with inline symbols. Family union counts each instruction sample once; truncated chains can underattribute descendants. Baseline and candidate use this identical method.'
        print(name, results[name], flush=True)
    a.out.write_text(json.dumps(results, indent=2) + '\n')

if __name__ == '__main__':
    main()
