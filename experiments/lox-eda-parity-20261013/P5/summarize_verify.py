#!/usr/bin/env python3
"""Assert same-source fixture and zero-RC verification counter receipts."""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main():
    before = json.loads((HERE / 'verify-baseline-v2-receipt.json').read_text())
    after = json.loads((HERE / 'verify-candidate-v2-receipt.json').read_text())
    assert [k for k in before['files'] if before['files'][k] != after['files'][k]] == ['kicad_sch_verify.my']
    assert before['compiler_sha256'] == after['compiler_sha256']
    assert before['build_returncode'] == after['build_returncode'] == 0
    rows = []
    for n in (16, 64):
        result = {'labels': n}
        for phase, receipt in [('baseline-v2', before), ('candidate-v2', after)]:
            run = next(r for r in receipt['runs'] if r['n'] == n)
            assert run['returncode'] == 0 and run['stdout'] == f'verify-labels:{n}:0:0\n'
            counts = json.loads((HERE / f'verify-{phase}-{n}-counters.json').read_text())
            t = counts['totals']
            assert t['live_bytes_at_exit'] == 0
            assert all(t[k] == 0 for k in ['runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks'])
            assert counts['kinds']['unique_test']['count'] == 0
            functions = {f['name']: f for f in counts['functions']}
            result[phase] = {'allocation_bytes': t['alloc_bytes'],
                             'reallocation_added_bytes': t['realloc_added_bytes'],
                             'peak_live_bytes': t['peak_live_bytes'],
                             'buffer_copies': t['buffer_copies'], 'calls': t['calls'],
                             'bounds_checks': counts['kinds']['bounds_check']['count'],
                             'is_form_calls': functions['sexpr_ast::is_form']['calls'],
                             'check_buffer_copies': functions['kicad_sch_verify::check']['buffer_copies'],
                             'scan_label_allocation_bytes': functions['kicad_sch_verify::scan_label']['alloc_bytes'],
                             'scan_placed_allocation_bytes': functions['kicad_sch_verify::scan_placed']['alloc_bytes']}
        b, c = result['baseline-v2'], result['candidate-v2']
        assert b['allocation_bytes'] - c['allocation_bytes'] == 1408
        assert b['buffer_copies'] - c['buffer_copies'] == 22
        assert b['check_buffer_copies'] == 22 and c['check_buffer_copies'] == 0
        assert b['peak_live_bytes'] == c['peak_live_bytes']
        assert b['scan_label_allocation_bytes'] == c['scan_label_allocation_bytes']
        assert b['scan_placed_allocation_bytes'] == c['scan_placed_allocation_bytes']
        assert c['is_form_calls'] < b['is_form_calls'] and c['bounds_checks'] < b['bounds_checks']
        rows.append(result)
    (HERE / 'verify-counter-summary.json').write_text(json.dumps({'label':'bounded counters, not full benchmark timing/RSS', 'rows':rows}, indent=2) + '\n')


if __name__ == '__main__':
    main()
