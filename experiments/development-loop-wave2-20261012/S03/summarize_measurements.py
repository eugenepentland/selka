#!/usr/bin/env python3
"""Summarize qualified paired cohorts; keep incomplete/cold limits explicit."""
import json
import math
from pathlib import Path
import statistics

OUT = Path(__file__).resolve().parent

def metrics(rows, p95=False):
    result = {}
    for key in ('wall_s','first_useful_feedback_s','max_process_rss_kib','sampled_command_rss_kib','artifact_bytes'):
        values = sorted(row[key] for row in rows if row.get(key) is not None)
        if not values:
            continue
        result[key] = {'median':statistics.median(values),'range':[min(values),max(values)]}
        if p95:
            result[key]['empirical_p95'] = values[math.ceil(.95*len(values))-1]
    return result

summary = {'schema':'s03-paired-boundary-summary-v2','warm_estimator':'median; empirical nearest-rank p95 (38th of40), not population/stable p95',
           'cold_estimator':'paired descriptive median/range; no cold p95 claim','scope':'isolated test-artifact recipe; excludes admission/full verification coordinator',
           'warm_edits':None,'cold_pairs':[],'incomplete_cold_records':[]}
warm = OUT / 'warm-edits-pair-00.json'
if warm.exists():
    data = json.loads(warm.read_text())
    variants = {}
    for label in ('C0','B0'):
        rows = [row for row in data['rows'] if row['label']==label]
        assert len(rows)==40 and len({row['artifact_sha256'] for row in rows})==40
        assert all(row['status']==0 and row['named_selected']==8 for row in rows)
        variants[label] = {'executions':40,'distinct_artifacts':40,'named_selected_each':8,
                           'wrappers_each':7 if label=='C0' else 1,'metrics':metrics(rows,p95=True)}
    ratios = []
    for edit in range(40):
        before = next(row for row in data['rows'] if row['label']=='C0' and row['edit']==edit)
        after = next(row for row in data['rows'] if row['label']=='B0' and row['edit']==edit)
        assert before['fixture_sha256']==after['fixture_sha256']
        ratios.append(after['wall_s']/before['wall_s'])
    summary['warm_edits'] = {'variants':variants,'paired_wall_ratio_B0_C0':{'median':statistics.median(ratios),'range':[min(ratios),max(ratios)]}}
cohorts = {}
for pattern in ('build-pair-*.json','all-units-pair-*.json'):
    for path in sorted(OUT.glob(pattern)):
        record = json.loads(path.read_text())
        key = (record['cohort'],record['pair'])
        cohort = cohorts.setdefault(key,{'records':[],'rows':[]})
        cohort['records'].append(record)
        cohort['rows'].extend(record['rows'])
for (cohort,pair), data in sorted(cohorts.items()):
    labels = {row['label'] for row in data['rows']}
    if labels != {'C0','B0'}:
        summary['incomplete_cold_records'].append({'cohort':cohort,'pair':pair,'labels':sorted(labels)})
        continue
    for field in ('cpu_affinity','harness_sha256','recipe_sha256','tool_authority_sha256'):
        assert all(record[field]==data['records'][0][field] for record in data['records']), field
    phases = sorted({row.get('phase','full_compile') for row in data['rows']})
    for phase in phases:
        [before] = [row for row in data['rows'] if row['label']=='C0' and row.get('phase','full_compile')==phase]
        [after] = [row for row in data['rows'] if row['label']=='B0' and row.get('phase','full_compile')==phase]
        assert before['status']==after['status']==0
        item = {'cohort':cohort,'pair':pair,'phase':phase,'variants':{'C0':metrics([before]),'B0':metrics([after])},
                'wall_ratio_B0_C0':after['wall_s']/before['wall_s']}
        if cohort=='build':
            assert before['named_selected']==after['named_selected']==8
            assert before['selected']==[15] and after['selected']==[9]
            item['compiled']={'C0':before['compiled'],'B0':after['compiled']}
        summary['cold_pairs'].append(item)
(OUT / 'measurement-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
