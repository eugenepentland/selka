#!/usr/bin/env python3
"""Prove the combined package's exact approved deltas against qualified C LLVM.

Keep complete before/after LLVM and raw diffs. Apply only the six private i64
dictionary-store replacements and the exact constant-mode trace ABI changes.
Compare every remaining instruction, operand, CFG edge, phi and trap using
bijective SSA/block names and semantic site/debug metadata. Compare all module
content outside function definitions byte-for-byte after the two trace
declarations replace the original declaration.
"""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re
import subprocess

from review_word35 import canonical, expand, imported, label_order

ROOT = Path(__file__).resolve().parents[4]
OLD_DECL = 'declare void @myl_core_err_trace(i32, i32) nounwind cold'
NEW_DECL = ('declare preserve_mostcc void @myl_core_err_trace_origin_preserve_most(i32) nounwind cold\n'
            'declare preserve_mostcc void @myl_core_err_trace_append_preserve_most(i32) nounwind cold')


def trace_calls(function):
    changes = []

    def replace(match):
        action = 'origin' if match[2] == '0' else 'append'
        changes.append(dict(site=int(match[1]), mode=int(match[2]), action=action))
        return f'call preserve_mostcc void @myl_core_err_trace_{action}_preserve_most(i32 {match[1]})'

    result = re.sub(r'call void @myl_core_err_trace\(i32 (-?\d+), i32 ([01])\)', replace, function)
    return result, changes


def module_remainder(text):
    return re.sub(r'^define .*?^\}', '', text, flags=re.M | re.S)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    out = args.evidence.resolve()
    assert out.is_relative_to(ROOT / 'experiments') and not out.exists(), 'fresh private evidence required'
    out.mkdir(parents=True)
    rows = imported(Path(__file__).with_name('measure_all40.py'))
    audit = imported(ROOT / 'experiments/new-core-s3-20261006/wave-b/s3-c/identity_audit.py')
    report = dict(source=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                  qualified=False, rows=[], definitions=0, exact_scalar_stores=0, exact_trace_calls=0, error=None,
                  method=__doc__)
    try:
        for row in rows.UNITS:
            if row in rows.APPLICATIONS:
                continue
            stem = rows.stem(row)
            before = (args.before / f'{stem}.ll').read_text()
            after = (args.after / f'{stem}.ll').read_text()
            (out / f'{stem}-before.ll').write_text(before)
            (out / f'{stem}-after.ll').write_text(after)
            (out / f'{stem}.raw.diff').write_text(''.join(difflib.unified_diff(
                before.splitlines(True), after.splitlines(True), fromfile='qualified-C', tofile='combined-A')))
            left, right = audit.functions(before), audit.functions(after)
            assert left.keys() == right.keys(), (row, 'function set changed')
            report['definitions'] += len(left)
            assert audit.sites(before) == audit.sites(after), (row, 'site metadata changed')
            assert module_remainder(before).replace(OLD_DECL, NEW_DECL) == module_remainder(after), (row, 'unapproved module delta')
            record = dict(row=row, before_sha256=hashlib.sha256(before.encode()).hexdigest(),
                          after_sha256=hashlib.sha256(after.encode()).hexdigest(), changed_functions=[],
                          definitions=len(left),
                          module_delta='exact trace declarations only')
            for name, old in left.items():
                prepared, traces = trace_calls(old)
                stores = []
                if '@myl_core_dict_set(' in prepared:
                    prepared, stores = expand(prepared)
                new = right[name]
                labels_before, labels_after = label_order(prepared), label_order(new)
                assert len(labels_before) == len(labels_after), (row, name, 'block count changed')
                normalized_before = audit.normalize(canonical(prepared, labels_before), audit.sites(before), audit.debug(before))
                normalized_after = audit.normalize(canonical(new, labels_after), audit.sites(after), audit.debug(after))
                if normalized_before != normalized_after:
                    difference = ''.join(difflib.unified_diff(normalized_before.splitlines(True), normalized_after.splitlines(True)))
                    (out / f'{stem}.residual.diff').write_text(difference)
                    raise AssertionError((row, name, difference))
                if old != new:
                    record['changed_functions'].append(dict(function=name, scalar_stores=stores, trace_calls=traces,
                        renamed_blocks=[dict(before=a, after=b) for a, b in zip(labels_before, labels_after) if a != b],
                        every_remaining_instruction_exact=True))
                report['exact_scalar_stores'] += len(stores)
                report['exact_trace_calls'] += len(traces)
            report['rows'].append(record)
            print(f'{row}: exact approved deltas; zero residual', flush=True)
        assert len(report['rows']) == 35
        assert report['definitions'] == 343
        assert report['exact_scalar_stores'] == 6
        assert report['exact_trace_calls'] == 2
        report['qualified'] = True
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        (out / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
