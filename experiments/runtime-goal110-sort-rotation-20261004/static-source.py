#!/usr/bin/env python3
"""Replay the exact production scope and unchanged refusal path of rotation804."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASE = '957f97c6d9906ef11cf344ce055dada8be8446ea'
CANDIDATE = '8043c4d9e0ad907c8a1b9e8416a1e58815eef0df'
SCOPE = ('src', 'vendor/qbe', 'build.zig', 'build.zig.zon', '.zigversion', '.qbeversion')


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    def source(revision):
        return subprocess.check_output(['git', '-C', str(ROOT), 'show', revision + ':src/native_collections.c'], text=True)
    before, after = source(BASE), source(CANDIDATE)
    assert (ROOT / 'src/native_collections.c').read_text() == after
    changed = subprocess.check_output(['git', '-C', str(ROOT), 'diff', '--name-only', BASE, CANDIDATE, '--', *SCOPE], text=True).splitlines()
    assert changed == ['src/native_collections.c']
    start = after.index('    /* The first remaining left value exceeds the first right value.')
    end = after.index('    if (left <= right) {\n        /* Forward:', start)
    inserted = after[start:end]
    assert after[:start] + after[end:] == before
    assert 'if (sort_less(base + (last - 1) * size, base + first * size, kind))' in inserted
    assert inserted.count('memmove(') == 2 and inserted.count('memcpy(') == 4
    assert not any(token in inserted for token in ('malloc(', 'calloc(', 'realloc(', 'free(', 'myl_rc_'))
    report = {
        'schema': 'mylang-goal110-sort-rotation-source-v1', 'status': 'pass',
        'baseline_revision': BASE, 'candidate_revision': CANDIDATE,
        'production_files_changed': changed,
        'baseline_source_sha256': digest(before), 'candidate_source_sha256': digest(after),
        'inserted_block_sha256': digest(inserted), 'inserted_lines': len(inserted.splitlines()),
        'removing_only_inserted_block_recovers_entire_baseline_source_byte_for_byte': True,
        'proof': [
            'The existing upper trim leaves a left value strictly greater than the first right value; otherwise it returns.',
            'Because the left run is sorted, its last value is at least as large; the lower trim therefore retains at least that first right value.',
            'Both trimmed runs are nonempty, so reading last-1 is valid.',
            'The guard requires the greatest remaining right value to be strictly less than the least remaining left value.',
            'Keeping each run ordered while exchanging their positions is sorted and preserves every tie order within a run; strict separation permits no cross-run ties.',
            'Holding the shorter run uses at most floor(count/2) elements of the already reserved scratch.',
            'The original allocation order, sizes, failure-before-mutation behavior, merge fallback, key evaluation, COW/refcount handling, and keyed sorted-copy path are byte-identical outside the inserted block.',
        ],
        'limitations': ['Static equivalence and bounded tests do not establish performance or exhaustive behavior at every representable list length.'],
    }
    if args.output:
        with args.output.open('x') as output:
            output.write(json.dumps(report, indent=2) + '\n')
    else:
        assert report == json.loads(Path(__file__).with_name('static-source.json').read_text())
    print('PASS exact source scope/nonempty/stability/scratch/refusal invariants ' + CANDIDATE)


if __name__ == '__main__':
    main()
