#!/usr/bin/env python3
"""Replay the source invariants for the committed counting-sort candidate."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

BASE = 'ffc2412fab9843081c749516a29d9599d585f86b'
CANDIDATE = '2a49da2960ad76471cbf2764c068d724cb9c5121'
ROOT = Path(__file__).resolve().parents[2]


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def function(text, name):
    match = re.search(r'(?m)^[^;{\n]*\b' + re.escape(name) + r'\([^;\n]*\)\s*\{', text)
    if not match:
        raise ValueError('missing function: ' + name)
    at, depth = match.end(), 1
    while depth:
        depth += (text[at] == '{') - (text[at] == '}')
        at += 1
    return text[match.start():at]


def normalized(text):
    return re.sub(r'\s+', ' ', re.sub(r'/\*.*?\*/', '', text, flags=re.S)).strip()


def main():
    def source(revision):
        return subprocess.check_output(['git', '-C', str(ROOT), 'show', revision + ':src/native_collections.c'], text=True)
    old, current = source(BASE), source(CANDIDATE)
    assert (ROOT / 'src/native_collections.c').read_text() == current
    changed = subprocess.check_output(['git', '-C', str(ROOT), 'diff', '--name-only', BASE, CANDIDATE, '--',
                                      'src', 'vendor/qbe', 'build.zig', 'build.zig.zon', '.zigversion', '.qbeversion'], text=True).splitlines()
    assert changed == ['src/native_collections.c']
    unchanged = {}
    for name in ('key_shape_decode', 'key_word', 'keyed_count', 'keyed_sort_words', 'keyed_sort_entries',
                 'myl_native_list_sort_keyed', 'myl_rc_list_sort_keyed', 'sort_elements', 'myl_native_list_sort'):
        left, right = function(old, name), function(current, name)
        assert left == right, name
        unchanged[name] = {'sha256': digest(left), 'byte_identical_to_baseline': True}
    gather = function(current, 'keyed_permute').replace(', unsigned shift', '').replace(
        '(uint32_t)(wide[i] >> shift)', '(uint32_t)wide[i]')
    assert normalized(gather) == normalized(function(old, 'keyed_permute'))
    place = function(current, 'keyed_place').replace('target->held, 0', 'target->held')
    assert normalized(place) == normalized(function(old, 'keyed_place'))
    pattern = r'    if \(target->values != target->source\) \{.*?\n    \}'
    copy = re.search(pattern, function(old, 'keyed_place_dest'), re.S).group()
    assert copy == re.search(pattern, function(current, 'keyed_place_dest'), re.S).group()
    report = {
        'schema': 'mylang-goal110-sort-static-v1', 'status': 'pass',
        'baseline_revision': BASE, 'candidate_revision': CANDIDATE,
        'production_files_changed': changed, 'source_path': 'src/native_collections.c',
        'baseline_source_sha256': digest(old), 'candidate_source_sha256': digest(current),
        'unchanged_functions': unchanged,
        'gather_cycle_normalized_unchanged_except_lane_selection': True,
        'ordinary_gather_normalized_unchanged_except_explicit_zero_lane': True,
        'sorted_copy_scatter_byte_identical': {'sha256': digest(copy), 'pass': True},
        'proof': [
            'Counting admission remains count<=UINT32_MAX and high-low<count.',
            'Stable slot assignment makes dest a bijection over 0..count-1, with each destination representable in 32 bits.',
            'Writing inverse into a destination high lane leaves every future low-lane destination read intact.',
            'Every high lane is assigned once, then forward compaction reads 8i before writing 4i.',
            'The same gather cycle preserves every full element byte and uses its original fixed-point/mark/prefetch handling.',
            'All scratch allocation calls/order/request sizes and before-movement refusals remain byte-identical; the 2*element temporary reservation remains.',
        ],
        'limitations': [
            'Static source proof is not performance evidence.',
            'Binary instruction/code-size inspection follows compiler/guest builds.',
            'Tests bound memory and correctness for tested widths/cycles; no exhaustive coverage of all representable list lengths.',
        ],
    }
    saved = json.loads(Path(__file__).with_name('static-source.json').read_text())
    assert saved == report
    print('PASS source scope/admission/refusal/copy/gather invariants ' + CANDIDATE)


if __name__ == '__main__':
    main()
