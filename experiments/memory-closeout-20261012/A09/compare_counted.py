#!/usr/bin/env python3
"""Compare same-adapter, same-input managed counters without treating peaks as traffic."""
import argparse
import json
from pathlib import Path

import measure


def cases(report):
    assert report['passed']
    result = {}
    for group in report['groups']:
        assert group['status'] == 'passed' and group['structural']['passed']
        for case in group['cases']:
            assert case['status'] == 'passed' and case['audit']['observed_rc_free']
            assert case['audit']['managed_leak_free']
            result[case['id']] = (case, group['artifact'])
    assert len(result) == report['case_denominator']
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('preserve existing comparisons')
    reports = [json.loads(path.read_text()) for path in (args.before, args.after)]
    for field in ('method', 'adapter_commit', 'adapter_source', 'adapter_sha256'):
        assert reports[0][field] == reports[1][field], field
    before, after = map(cases, reports)
    assert before.keys() == after.keys()
    rows = []
    for name in before:
        old, old_artifact = before[name]
        new, new_artifact = after[name]
        for field in ('source_inputs_sha256', 'args', 'env', 'cpus', 'expected'):
            assert old[field] == new[field], (name, field)
        row = {'id': name, 'source_inputs_sha256': old['source_inputs_sha256'],
               'args': old['args'], 'env': old['env'], 'cpus': old['cpus'],
               'before': old['whole_program_managed_totals'],
               'after': new['whole_program_managed_totals'],
               'before_counter_sha256': old['audit']['counter_sha256'],
               'after_counter_sha256': new['audit']['counter_sha256'],
               'before_artifact': old_artifact, 'after_artifact': new_artifact,
               'before_direct_drops': old['audit']['direct_frees'],
               'after_direct_drops': new['audit']['direct_frees'],
               'both_rc_event_audits_zero': True, 'both_managed_exit_live_zero': True}
        rows.append(row)
    result = {'method': reports[0]['method'], 'case_denominator': len(rows),
              'adapter_commit': reports[0]['adapter_commit'],
              'adapter_sha256': reports[0]['adapter_sha256'],
              'before_source': reports[0]['source_commit'], 'after_source': reports[1]['source_commit'],
              'before_compiler_sha256': reports[0]['compiler_sha256'],
              'after_compiler_sha256': reports[1]['compiler_sha256'],
              'input_reports': {str(path): measure.digest(path) for path in (args.before, args.after)},
              'cases': rows,
              'limitations': ['Whole-program counts on the exact runtime inputs; separate from original30/pinned81+6 census.',
                              'Allocation/reallocation/copy traffic, peak managed bytes and exit-live bytes are separate metrics.',
                              'Managed peaks are observations, never subtracted as traffic and never interpreted as RSS.',
                              'C0 descriptor-driven list-copy traffic was undercounted; the later hook changes telemetry independently of actual allocations.',
                              'Runtime/RSS observations use separate uninstrumented binaries and runs.',
                              'Support7 is an intermediate candidate with known release-inventory blockers; no qualified milestone is asserted.']}
    measure.save(args.output, result)
    print(f'{len(rows)} exact-input managed comparisons verified')


if __name__ == '__main__':
    main()
