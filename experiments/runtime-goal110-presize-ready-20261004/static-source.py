#!/usr/bin/env python3
"""Check that readiness638 changes only the certified presized guard's callee."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASE = '63df6b6c481b12fd711755ec40cdcb5d1c984ccc'
CANDIDATE = '63842d3c32ab3079d878cff89224478543f9b7f3'
MODULE = 'src/qbe_rc_append_loop.zig'
SCOPE = ('src', 'vendor/qbe', 'build.zig', 'build.zig.zon', '.zigversion', '.qbeversion')


def digest(value):
    return hashlib.sha256(value).hexdigest()


def source(revision, name):
    return subprocess.check_output(['git', '-C', str(ROOT), 'show', revision + ':' + name])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    before, after = source(BASE, MODULE), source(CANDIDATE, MODULE)
    assert (ROOT / MODULE).read_bytes() == after
    recovered = after.replace(
        b'/// either refusal enters the original loop. The identical hot query is an\n'
        b'/// inlining hint at this already-certified guard, not a new admission proof.\n'
        b'/// False emits nothing.\n',
        b'/// either refusal enters the original loop. False emits nothing.\n', 1)
    guard_start = recovered.index(b'pub fn presized(')
    guard_end = recovered.index(b'/// Only the certified root', guard_start)
    guard = recovered[guard_start:guard_end]
    assert guard.count(b'call $myl_rc_list_plain_ready_hot(') == 1
    ordinary_guard = guard.replace(b'call $myl_rc_list_plain_ready_hot(', b'call $myl_rc_list_plain_ready(', 1)
    assert recovered[:guard_start] + ordinary_guard + recovered[guard_end:] == before
    changed = subprocess.check_output(['git', '-C', str(ROOT), 'diff', '--name-only', BASE, CANDIDATE,
                                       '--', *SCOPE], text=True).splitlines()
    assert changed == [MODULE, 'src/qbe_rc_loop_codegen_test.zig']
    native = source(CANDIDATE, 'src/native_collections.c')
    assert native == source(BASE, 'src/native_collections.c')
    assert native.count(b'return plain_ready_query(heap,list);') == 2
    assert b'inline __attribute__((always_inline)) int myl_rc_list_plain_ready_hot(' in native
    report = {
        'schema': 'mylang-goal110-presize-ready-source-v1', 'status': 'pass',
        'baseline_revision': BASE, 'candidate_revision': CANDIDATE,
        'changed_source_files': changed, 'only_codegen_module_changed': MODULE,
        'module_before_sha256': digest(before), 'module_after_sha256': digest(after),
        'native_collections_unchanged_sha256': digest(native),
        'removing_only_comment_and_one_presized_callee_substitution_recovers_entire_module': True,
        'unchanged': ['All admission certificates and compile-work/refusal limits',
                      'Capacity/trip guard, generation<2^62, fallback edges and complete original loop',
                      'Per-append cached admission/invalidation and nested-only hot hint',
                      'Runtime metadata, pending-finalizer, widths and registration predicate',
                      'Accounting, COW, allocation order and failures; collector emission'],
        'scope': 'Every already-certified presized guard, without PC/case/fixture selection',
        'reachable_target': 'Presized scalar comprehensions such as sort_int setup',
        'append_control': 'Frozen list_append starts with zero spare capacity, so positive trip counts refuse before readiness; original fallback is unchanged.',
        'limitations': ['A forced inline predicate may alter register allocation/layout and code size; performance requires coordinated timing.',
                        'Debug host/ReleaseFast guest diagnostics are not normal goal confirmations.'],
    }
    if args.output:
        with args.output.open('x') as output:
            output.write(json.dumps(report, indent=2) + '\n')
    else:
        assert report == json.loads(Path(__file__).with_name('static-source.json').read_text())
    print('PASS exact presized-only callee substitution and shared unchanged readiness predicate')


if __name__ == '__main__':
    main()
