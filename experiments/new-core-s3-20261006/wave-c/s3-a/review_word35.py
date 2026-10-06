#!/usr/bin/env python3
"""Check the exact six approved i64 dictionary-store replacements in retained LLVM.

This does not replace the raw or definition diffs. It applies only the approved
store expansion to the old definitions, removes its private spill slots, and
checks every remaining instruction and operand through a bijective SSA/label
rename. Labels retain their order and every branch/phi edge is compared.
"""
import argparse
import difflib
import importlib.util
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[4]


def imported(path):
    spec = importlib.util.spec_from_file_location("word35_exact", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expand(function):
    pattern = re.compile(
        r'^  store i64 (?P<value>%[A-Za-z0-9_.]+), ptr (?P<slot>%[A-Za-z0-9_.]+), align 8, !tbaa !7\n'
        r'  (?P<result>%[A-Za-z0-9_.]+) = call ptr @myl_core_dict_set\(ptr (?P<dict>%[A-Za-z0-9_.]+), i64 (?P<index>%[A-Za-z0-9_.]+), ptr (?P=slot)\)\n', re.M)
    matches = list(pattern.finditer(function))
    replacements = []
    for number, match in reversed(list(enumerate(matches))):
        slot = match['slot']
        assert len(re.findall(re.escape(slot) + r'(?![A-Za-z0-9_.])', function)) == 3, (slot, "spill escaped")
        assert re.search(r'^  ' + re.escape(slot) + r' = alloca \[8 x i8\], align 8$', function, re.M), slot
        prefix = f"%review_store{number}"
        replacement = (f"  {prefix}_scale = mul i64 {match['index']}, 16\n"
                       f"  {prefix}_offset = add i64 {prefix}_scale, 40\n"
                       f"  {prefix}_address = getelementptr inbounds i8, ptr {match['dict']}, i64 {prefix}_offset\n"
                       f"  store i64 {match['value']}, ptr {prefix}_address, align 8, !tbaa !7\n"
                       f"  {match['result']} = getelementptr inbounds i8, ptr {match['dict']}, i64 0\n")
        function = function[:match.start()] + replacement + function[match.end():]
        replacements.append(dict(value=match['value'], dictionary=match['dict'], index=match['index'], removed_private_slot=slot,
                                 stride=16, value_offset_from_block=40, value_type="i64", alignment=8))
    for replacement in replacements:
        function, removed = re.subn(r'^  ' + re.escape(replacement['removed_private_slot']) + r' = alloca \[8 x i8\], align 8\n', '', function, flags=re.M)
        assert removed == 1
    assert '@myl_core_dict_set(' not in function, "unreviewed set call"
    return function, list(reversed(replacements))


def label_order(function):
    return re.findall(r'^([A-Za-z0-9_.]+):$', function, re.M)


def canonical(function, labels):
    # A bijective name correspondence, retaining all instructions and CFG edges.
    for number, label in enumerate(labels):
        function = re.sub(r'(?m)^' + re.escape(label) + ':$', f'REVIEW_BLOCK_{number}:', function)
    names = {label: f'REVIEW_BLOCK_{number}' for number, label in enumerate(labels)}
    function = re.sub(r'%([A-Za-z0-9_.]+)', lambda m: '%' + names.get(m[1], m[1]), function)
    return function


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert not args.output.exists(), "preserve prior receipts"
    audit = imported(ROOT / 'experiments/new-core-s3-20261006/wave-b/s3-c/identity_audit.py')
    receipt = dict(qualified=False, rows=[], error=None,
                   method="Exact approved six scalar-store expansion, private spill removal, semantic metadata and bijective SSA/block names only; every remaining instruction/operand/branch/phi/trap compared; raw diffs remain unchanged.")
    try:
        for stem in ['row_dict_lookup', 'row_dict_lookup_str', 'row_dict_update', 'row_dict_update_str']:
            before = (args.cache / 'before' / f'{stem}.ll').read_text()
            after = (args.cache / 'after' / f'{stem}.ll').read_text()
            old_functions, new_functions = audit.functions(before), audit.functions(after)
            record = dict(row=stem, functions=[])
            for name, old in old_functions.items():
                if '@myl_core_dict_set(' not in old:
                    continue
                expanded, stores = expand(old)
                new = new_functions[name]
                old_labels, new_labels = label_order(expanded), label_order(new)
                assert len(old_labels) == len(new_labels), (stem, name, "block count changed")
                old_normal = audit.normalize(canonical(expanded, old_labels), audit.sites(before), audit.debug(before))
                new_normal = audit.normalize(canonical(new, new_labels), audit.sites(after), audit.debug(after))
                if old_normal != new_normal:
                    raise AssertionError(''.join(difflib.unified_diff(old_normal.splitlines(True), new_normal.splitlines(True), fromfile='approved-expansion', tofile='actual')))
                record['functions'].append(dict(function=name, exact=True, stores=stores, block_count=len(old_labels),
                                                renamed_blocks=[dict(before=left, after=right) for left, right in zip(old_labels, new_labels) if left != right]))
            receipt['rows'].append(record)
        assert sum(len(function['stores']) for row in receipt['rows'] for function in row['functions']) == 6
        receipt['qualified'] = True
    except Exception as error:
        receipt['error'] = str(error)
        raise
    finally:
        args.output.write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    main()
