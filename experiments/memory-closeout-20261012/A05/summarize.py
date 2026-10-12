#!/usr/bin/env python3
"""Associate exact passing fixture artifacts with A05's public export inventory."""
# spec: NEW-CORE-ZERO-RC-LIBRARY-1
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]

def main():
    runs={}
    for report in sorted((HERE/'evidence').glob('*.json')):
        data=json.loads(report.read_text())
        if data.get('check_only',True):
            continue
        for case,modes in data.get('cases',{}).items():
            for mode,value in modes.items():
                if value.get('passed'):
                    runs.setdefault(value['original_source'],[]).append({
                        'report':str(report.relative_to(ROOT)), 'case':case, 'mode':mode,
                        'compiler_sha256':data.get('compiler_sha256'),
                        'source_sha256':value['original_sha256'],
                        'overlay':data.get('overlay',False),
                        'binary_sha256':value['binary_sha256'],
                    })
    items=[]
    for row in json.loads((HERE/'exports.json').read_text())['exports']:
        evidence=[entry for path in row['source_coverage'] for entry in runs.get(path,[])]
        items.append({
            'module':row['module'],'name':row['name'],'kind':row['kind'],
            'contract':row['ownership_contract'],
            'baseline_executable_source_references':evidence,
            'final_C1_qualification':'pending',
            'note':'Source reference plus passing full fixture. This is not a per-branch coverage trace; original inventory source hash remains C0.',
        })
    report={
        'scope':'C0 and interim/overlay fixture evidence, not final integrated export qualification',
        'public_declarations':len(items),
        'public_functions':sum(x['kind']=='func' for x in items),
        'declarations_with_at_least_one_passing_fixture_reference':sum(bool(x['baseline_executable_source_references']) for x in items),
        'items':items,
    }
    (HERE/'export-status.json').write_text(json.dumps(report,indent=2)+'\n')
    print(report['declarations_with_at_least_one_passing_fixture_reference'],'of',len(items),'have passing fixture references; C1 remains pending')

if __name__=='__main__':main()
