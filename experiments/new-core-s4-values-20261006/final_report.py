#!/usr/bin/env python3
"""Check completed S4-V receipts and write the package handoff manifest."""
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
SOURCE = '3c86c3122fdcc186aa777b52bbcf7f25b03c172f'


def read(name):
    return json.loads((EVIDENCE / name).read_text())


def main():
    feedback_commit = sys.argv[1]
    frozen = read('final-frozen-source-v3.json')
    for name, expected in frozen['frozen_inputs'].items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == expected, name
    for name, tool in frozen['tools'].items():
        assert hashlib.sha256(Path(tool['path']).read_bytes()).hexdigest() == tool['sha256'], name
    ir_changes = subprocess.check_output(['git', 'diff', '82c125dd', '--', 'src/core/ir.zig'], text=True)
    assert not ir_changes
    core = read('final-core-conformance-v7/core-component.json')
    correctness = read('final-core-conformance-v7/summary.json')
    assert correctness['qualified'] and core['tests'] == {'passed': 279, 'failed': 0, 'skipped': 0}
    conformance = Path(correctness['results'][1]['log']).read_text()
    modes = re.findall(r'(debug|release)\s+matching (\d+), mismatching (\d+), unsupported (\d+)', conformance)
    assert modes == [('debug', '1518', '0', '0'), ('release', '1518', '0', '0')]
    old = read('final-full-old-v3/summary.json')
    rows = read('final-rows-leak-verify-v2/summary.json')
    six = read('final-independent-oracles-v2/summary.json')
    supplement = read('supplement-v6/summary.json')
    performance = read('performance_summary_v2.json')
    rebuild = read('final-rebuild-v1.json')
    assert old['complete'] and old['qualified']
    assert rows['qualified'] and rows['native_comparisons'] == 414 and rows['rows'] == 46
    assert six['qualified'] and len(six['comparisons']) == 210
    assert supplement['qualified'] and len(supplement['commands']) == 25
    assert performance['qualified'] and performance['all_within_both_limits'] and not performance['misses']
    assert rebuild['qualified'] and rebuild['source_identical_rebuild'] and rebuild['seconds'] <= 10
    matrix = read('final-fuzz-v3/summary.json')
    assert matrix['qualified'] and len(matrix['results']) == 8
    for receipt in (core, correctness, rows, supplement, performance, matrix):
        assert receipt['core_sha256'] == frozen['tools']['mylang-core']['sha256']
    kinds = {}
    for kind in ('values', 'rc', 'rebinding', 'functions', 's1', 'dict', 'number', 'iteration'):
        item = read(f'final-fuzz-v3/{kind}/summary.json')
        assert item['qualified'] and item['complete'] and item['accepted'] == 50
        assert item['old_rejected'] == item['core_refused'] == item['core_build_failed'] == 0
        assert item['harness']['mismatch'] == 0
        if kind != 'rc':
            assert item['harness']['fact'] == 0
        kinds[kind] = {
            'seed': item['seed'], 'accepted': item['accepted'],
            'native_comparisons': item['harness']['compared'],
            'elapsed_seconds': item['elapsed_seconds'],
            'old_sha256': item['oracles']['old']['sha256'],
            'summary': f'final-fuzz-v3/{kind}/summary.json',
        }
    assert sum(item['native_comparisons'] for item in kinds.values()) == 5700
    blocker = read('provenance_integration_blocker.json')
    assert blocker['integration_blocker']
    report = {
        'listed_gates_passed': True, 'integration_blocked': True,
        'compiler_source': SOURCE,
        'evidence_head_before_report': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
        'branch': subprocess.check_output(['git', 'branch', '--show-current'], text=True).strip(),
        'tools': frozen['tools'], 'frozen_inputs': frozen['frozen_inputs'],
        'core': core, 'conformance': {'debug': 1518, 'verified_release': 1518, 'mismatches': 0},
        'old_gate': {'receipt': 'final-full-old-v3/summary.json', 'complete': True, 'qualified': True},
        'value_supplement_comparisons': 25, 'rows_leak_verify_comparisons': 414,
        'independent_six_oracle_comparisons': 210,
        'strict_fuzz': {'accepted': 400, 'native_comparisons': 5700, 'kinds': kinds,
                        'values_harness_kind': 'functions; custom value generator under values directory'},
        'performance': {'rows': 46, 'sizes': [64, 4096], 'rounds': 7, 'cpu': 10,
                        'max_new_over_old': performance['max_new_over_old'],
                        'max_new_over_zig': performance['max_new_over_zig'], 'gate_misses': []},
        'real_source_identical_rebuild': rebuild,
        'guardian_checks': 88, 'guardian_feedback_commit': feedback_commit,
        'integration_blocker': blocker,
        'next_step': 'Merge package evidence; qualify the combined S4-E provenance repair before clearing integration.',
        'ir_unchanged': True, 'pushed': False, 'merged_into_main': False,
    }
    assert report['branch'] == 'codex/new-core-s4-values'
    with (EVIDENCE / 'final_package_report.json').open('x') as output:
        output.write(json.dumps(report, indent=2) + '\n')
    print('400 accepted cases / 5700 comparisons; listed gates pass; native trap provenance integration blocker remains')


if __name__ == '__main__':
    main()
