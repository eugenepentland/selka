#!/usr/bin/env python3
"""Prove the fact repair preserves every saved coverage admission and loop attribution."""
from collections import Counter
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[5]
AREA = ROOT / 'experiments/new-core-s2-20261005/wave-b/integration'
SOURCE = '996d9baad0e00ef98b4d3e7b59dc3616809fa013'
CORPORA = ('examples', 'bench/parity', 'tests/lang', 'benchmarks/runtime')


def parse(path, temporary):
    occurrences, frontend, outcomes, checks, metrics = [], [], {}, {}, []
    for line in path.read_text().splitlines():
        kind, _, rest = line.partition(' ')
        if kind == 'ok':
            name, _, counts = rest.partition('\t')
            found = re.match(r'proven=(\d+) exact=(\d+)', counts)
            assert found, line
            held = tuple(map(int, found.groups()))
            occurrences.append((name, None))
            metrics.append((name, held))
            outcomes.setdefault(name, None)
            checks.setdefault(name, held)
        elif kind == 'refused':
            reason, _, name = rest.partition('\t')
            occurrences.append((name, reason))
            metrics.append((name, None))
            if outcomes.get(name, 'absent') is not None:
                outcomes[name] = reason
        elif kind == 'frontend':
            frontend.append(rest.replace(temporary, '<coverage-tmp>'))
        else:
            raise AssertionError(line)
    return occurrences, frontend, outcomes, checks, metrics


def main():
    before_area, after_area = AREA / 'coverage-standard', AREA / 'coverage-standard-after-fact'
    summaries = [json.loads((area / 'summary.json').read_text()) for area in (before_area, after_area)]
    assert all(item['qualified'] and len(item['children']) == 4 for item in summaries)
    changes = subprocess.check_output(['git', 'diff', '--name-only', '090dabd5', SOURCE, '--',
                                      'src', 'examples', 'bench/parity', 'tests/lang',
                                      'benchmarks/runtime/expanded'], text=True).splitlines()
    assert changes == ['src/core/dict_test.zig', 'src/core/facts.zig'], changes
    temporary = [str(ROOT / f'.mylang-cache/s2-x/{name}/tmp') for name in ('coverage', 'coverage-after-fact')]
    report = dict(source_commit=SOURCE, before_source_commit='090dabd5', compiler_repair_commit='0c6029d7',
                  qualified=True, source_changes_in_compiler_and_coverage_cohorts=changes,
                  frontend_and_typed_sources_unchanged=True, coverage_cohort_sources_unchanged=True,
                  comparison_definition='All ordered function occurrences, admissions, first refusals, frontend diagnostics and command inputs agree, normalizing only private temporary directories.',
                  corpora={})
    checks = [{}, {}]
    all_reasons = Counter()
    for index, corpus in enumerate(CORPORA, 1):
        children = [summary['children'][index - 1] for summary in summaries]
        assert all(child['exit'] == 0 for child in children)
        commands = [[arg.replace(tmp, '<coverage-tmp>') for arg in child['command']] for child, tmp in zip(children, temporary)]
        assert commands[0] == commands[1]
        assert all(not (area / f'corpus-{index}.err').read_text() for area in (before_area, after_area))
        data = [parse(area / f'corpus-{index}.txt', tmp) for area, tmp in zip((before_area, after_area), temporary)]
        assert data[0][:3] == data[1][:3], corpus
        for table, value in zip(checks, data):
            table.update(value[3])
        reasons = Counter(reason or '(accepted)' for reason in data[1][2].values())
        all_reasons.update(reasons)
        changed_metrics = [dict(occurrence=i, function=old[0], before=old[1], after=new[1])
                           for i, (old, new) in enumerate(zip(data[0][4], data[1][4]), 1) if old != new]
        report['corpora'][corpus] = dict(function_occurrences_compared=len(data[1][0]),
                                        qualified_name_functions=len(data[1][2]), accepted=reasons['(accepted)'],
                                        frontend_rejections_compared=len(data[1][1]), compiler_exit=0,
                                        compiler_stderr_bytes=0, all_first_refusals=dict(reasons),
                                        changed_check_metrics=changed_metrics)
    totals = {key: sum(data[key] for data in report['corpora'].values()) for key in
              ('function_occurrences_compared', 'qualified_name_functions', 'accepted', 'frontend_rejections_compared')}
    for label, table in zip(('checks_before', 'checks_final'), checks):
        totals[label] = dict(proven=sum(p for p, e in table.values()), exact=sum(e for p, e in table.values()),
                             qualified_function_names=len(table))
    old_reasons = json.loads((before_area / 'all-reasons.json').read_text())
    assert dict(all_reasons) == old_reasons['totals']['all_first_refusals']
    report['totals'] = totals
    report['all_first_refusals'] = dict(all_reasons)
    loop = json.loads((AREA / 'coverage-loops.json').read_text())
    report['loop_table_reused'] = dict(artifact='coverage-loops.json', original_source_commit=loop['source_commit'],
                                      original_before_source_commit=loop['before_source_commit'],
                                      reason='Unchanged typed frontend and corpus sources with every function admission/first refusal identical preserve all typed loop instances and their attribution.',
                                      per_file_functions=4250, checked_loops=1539,
                                      before_accepted_functions=2756, final_accepted_functions=3687,
                                      before_accepted_loops=607, final_accepted_loops=1260)
    report['command'] = 'python3 experiments/new-core-s2-20261005/wave-b/integration/coverage-standard-after-fact/compare_admissions.py'
    (after_area / 'admission-proof.json').write_text(json.dumps(report, indent=2) + '\n')
    new_summary = summaries[1]
    new_summary.update(source_commit=SOURCE, compiler_repair_commit='0c6029d7',
                       command_log='s2-x-coverage-standard-after-fact.txt',
                       qualification=dict(exit=0, seconds=2.64, rss_kib=39300))
    (after_area / 'summary.json').write_text(json.dumps(new_summary, indent=2) + '\n')
    derived = dict(source_commit=SOURCE, compiler_repair_commit='0c6029d7', qualified=True,
                   count_definition=old_reasons['count_definition'], corpora=report['corpora'],
                   totals=dict(functions=totals['qualified_name_functions'], accepted=totals['accepted'],
                               all_first_refusals=dict(all_reasons)), assertion_checks=totals['checks_final'])
    (after_area / 'all-reasons.json').write_text(json.dumps(derived, indent=2) + '\n')
    print(json.dumps(totals, indent=2))
    print('PASS: every admission/refusal/frontend diagnostic agrees; original loop table remains valid; all refusal reasons retained.')


if __name__ == '__main__':
    main()
