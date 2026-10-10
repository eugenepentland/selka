#!/usr/bin/env python3
"""Render M0's measured diagnostic bounds and U2 wall-time exits."""
import json
from pathlib import Path

AREA = Path(__file__).resolve().parents[1]
M0 = AREA / 'M0'


def main():
    cpu10 = json.loads((M0 / 'counterfactual-cpu10.json').read_text())
    assert cpu10['complete'] and len(cpu10['groups']) == 8
    cpu8 = {}
    for name in ('lox', 'eda-rds3+flat', 'eda-labstation'):
        data = json.loads((M0 / ('counterfactual-cpu8-' + name + '.json')).read_text())
        for case, value in data['cases'].items():
            cpu8[name + ':' + case] = value['variants']
    lines = ['# M0 counterfactual bounds', '',
             'Diagnostic probes only. The production compiler retains every required check and count. The inherited norc probe removes inline count branches; C runtime count operations remain. Both EDA norc variants abort and provide no valid bound; they are not timed again on CPU 10. The valid EDA reference_at-inlining probe and all six Lox exit probes are confirmed. CPU 8 uses five interleaved perf rounds. CPU 10 uses nine interleaved wall-time rounds after two warmups, holding the timing lock and all build/gate slots. Every CPU-10 sample checks stdout, exit status, and EDA generated-file hashes.', '',
             'Ratios below use the unedited LLVM rebuild (`base`); the `real` arm is the direct compiler output and reveals rebuild/layout variation. Absolute timing is milliseconds. Both forms are retained in the raw receipts.', '',
             '| cell | variant | CPU-8 instructions ÷ base | CPU-8 cycles ÷ base | CPU-10 ms | CPU-10 ÷ base | CPU-10 ÷ real | output |',
             '|---|---|---:|---:|---:|---:|---:|---|']
    targets = []
    required = {'lox:vm/invocation', 'lox:vm/fib', 'lox:vm/method_call', 'lox:tree/equality'}
    for name, group in cpu10['groups'].items():
        assert group['all_outputs_match']
        variants = cpu8[name]
        base = variants['base']['median']
        for label, timing in group['arms'].items():
            counts = variants[label]
            assert counts['status'] == 0 and counts['output_matches_real']
            med = counts['median']
            lines.append(f"| {name} | {label} | {med['instructions']/base['instructions']:.3f} | {med['cycles']/base['cycles']:.3f} | {timing['median_ms']:.3f} | {timing['ratio_to_base']:.3f} | {timing['ratio_to_real']:.3f} | match |")
        for label, rejection in group.get('rejected_cpu8_variants', {}).items():
            lines.append(f"| {name} | {label} | invalid | invalid | — | — | — | CPU-8 exit {rejection['status']}; no bound |")
        if name in required:
            ratio = group['arms']['norc']['ratio_to_real']
            targets.append((name, ratio, 1 - 0.6 * (1 - ratio)))
    lines += ['', '## U2 cell exits', '',
              'For each required cell, closing 60% of the gap means final/base ≤ 1 − 0.60 × (1 − norc/real). The direct compiler output is the production base for this calculation; both direct and rebuilt controls are reported above.', '',
              '| cell | norc ÷ direct base | U2 final ÷ base ceiling |', '|---|---:|---:|']
    lines += [f'| {name} | {ratio:.3f} | {target:.3f} |' for name, ratio, target in targets]
    assert len(targets) == 4
    lines += ['', 'Generated per-layout release was not probed: cf.py has no such stub. The requested reference_at inlining probe is included for both EDA designs. U2 implements generated release with its own correctness gates.', '',
              'The first no-op norc attempt is invalid and excluded (`counterfactual-v1-invalid.json`). The current matcher changes reachable P1 count branches; its faster implementation exactly matches the completed Lox probe LLVM. See DECISIONS.md for both corrections.', '']
    (M0 / 'counterfactuals.md').write_text('\n'.join(lines))
    (M0 / 'u2-exits.json').write_text(json.dumps({name: {'norc_over_real': ratio, 'final_over_base_limit': target}
                                               for name, ratio, target in targets}, indent=1) + '\n')
    print('counterfactuals.md: eight cells, four U2 wall-time exits')


if __name__ == '__main__':
    main()
