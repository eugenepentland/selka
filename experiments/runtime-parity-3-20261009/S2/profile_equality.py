#!/usr/bin/env python3
"""Attribute baseline Lox string equality with instruction samples and bounded LBR."""
import collections
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'experiments/runtime-parity-3-20261009/tools'))
import corpus_perf
from profile_text import symbol_name

work = ROOT / '.mylang-cache/rp3/s2-equality-profile'
work.mkdir(parents=True, exist_ok=True)
results = {}
for arm in corpus_perf.arms_for('base'):
    if arm['program'] not in ('lox/tree/string_equality', 'lox/vm/string_equality'):
        continue
    name = arm['program'].split('/')[1]
    perf = work / (name + '.perf')
    command = [sys.executable, '-c', 'import subprocess,sys; [subprocess.run(sys.argv[1:],check=True,stdout=subprocess.DEVNULL) for _ in range(4)]', *arm['argv']]
    subprocess.run(['taskset', '-c', '8', 'perf', 'record', '-q', '-e', 'cpu_core/instructions/u', '-c', '100003', '--call-graph', 'lbr', '-o', str(perf), '--', *command], cwd=arm['cwd'], check=True)
    raw = subprocess.check_output(['perf', 'script', '-i', str(perf), '-F', 'comm,period,ip,sym', '--inline'], text=True)
    inclusive = collections.Counter()
    exclusive = collections.Counter()
    total = 0
    for event in raw.split('\n\n'):
        lines = event.splitlines()
        if not lines or not lines[0].startswith('lox-plain '):
            continue
        period = int(lines[0].split()[1])
        symbols = [symbol_name(line.strip().split(' ', 1)[1].strip()) for line in lines[1:] if ' ' in line.strip()]
        total += period
        if symbols:
            exclusive[symbols[0]] += period
        for symbol in set(symbols):
            inclusive[symbol] += period
    results[name] = {'sampled_period': total, 'exclusive': exclusive.most_common(40), 'inclusive': inclusive.most_common(40),
                     'text_equality_inclusive_period': inclusive['myl_core_str_eq'], 'text_equality_inclusive_share': inclusive['myl_core_str_eq'] / total,
                     'binary': arm['argv'][0], 'binary_sha256': hashlib.sha256(Path(arm['argv'][0]).read_bytes()).hexdigest(),
                     'perf_data': str(perf), 'perf_sha256': hashlib.sha256(perf.read_bytes()).hexdigest(),
                     'limitation': 'Bounded LBR stack reconstruction; inlined and +0x suffixes normalized; truncated chains may underattribute.'}
    print(name, results[name]['text_equality_inclusive_share'], flush=True)
(ROOT / 'experiments/runtime-parity-3-20261009/S2/equality-base-profile.json').write_text(json.dumps(results, indent=1) + '\n')
