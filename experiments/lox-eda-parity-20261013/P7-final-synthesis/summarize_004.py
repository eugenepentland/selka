#!/usr/bin/env python3
"""Derive concise final metrics from the validated extraction; no guest execution."""
import csv
import hashlib
import json
import os
from pathlib import Path
import statistics

HERE = Path(__file__).resolve().parent
BASE = Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/experiments/lox-eda-parity-20261013')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    assert os.environ['MYLANG_ADMISSION_KIND']=='build'
    out=HERE/'extracted-004';s=json.loads((out/'synthesis.json').read_text());receipt=json.loads((out/'receipt.json').read_text());assert not (out/'derived-summary.json').exists()
    pins={str(HERE/'summarize_004.py'):sha(HERE/'summarize_004.py'),str(out/'synthesis.json'):sha(out/'synthesis.json'),str(out/'receipt.json'):sha(out/'receipt.json')}
    rc=[]
    for case,arms in s['managed']['cases'].items():
        for arm,value in arms.items():
            if value['status']!='ok':continue
            path=Path(value['counter_path']);assert sha(path)==receipt['inputs'][str(path)];pins[str(path)]=receipt['inputs'][str(path)];raw=json.loads(path.read_text());t=raw['totals'];k=raw['kinds']
            checks={name:t.get(name,0) for name in ['runtime_retains','runtime_releases','shared_retains','shared_releases','share_marks','live_bytes_at_exit']};checks.update({name:k[name]['count'] for name in ['retain','release','unique_test']});assert all(v==0 for v in checks.values()),(case,arm,checks)
            rc.append({'case':case,'arm':arm,'zero_checked_metrics':checks,'direct_destructions':k['release_unique']['count'],'counter_path':str(path),'counter_sha256':pins[str(path)]})
    compiled={}
    for app in ['lox','eda']:
        records=[v['receipt'] for v in s['compilation_observations'] if v['receipt']['application']==app];assert len(records)==3
        app_data={}
        for cache in ['cold-guest-cache','warm-guest-cache']:
            samples={a:[v for r in records for v in r['samples'] if v['arm']==a and v['cache_state']==cache] for a in ['before','before-same-compiler','after']}
            assert all(len(v)==3 and all(x['status']=='ok' and x['returncode']==0 for x in v) for v in samples.values())
            app_data[cache]={'arms':{a:{'seconds':statistics.median(x['elapsed_seconds'] for x in v),'gnu_time_maxrss_kib':statistics.median(x['gnu_time_maxrss_kib'] for x in v),'observations':3,'raw':v} for a,v in samples.items()},'paired_median_ratios':{a+'/'+b:statistics.median([samples[a][i]['elapsed_seconds']/samples[b][i]['elapsed_seconds'] for i in range(3)]) for a,b in [('after','before'),('before-same-compiler','before'),('after','before-same-compiler')]}}
        app_data.update(method=records[0]['method'],rss_limit=records[0]['rss_limit']);compiled[app]=app_data
    screen_path=BASE/'P1/runtime-004-regression-screen/final-screen.json';screen=json.loads(screen_path.read_text());pins[str(screen_path)]=sha(screen_path);assert screen['report_sha256']=='5f069e3f1532fc6151df0ccc565555b05a128ee1f0011279e3d0f396c4fbedf6'
    matches=[v for c in screen['cells'] for v in c['samples'] if 'mylang-zero-rc' in v['values'] and 'mylang-before' in v['values']];wins=sum(v['values']['mylang-zero-rc']<v['values']['mylang-before'] for v in matches);assert len(matches)==wins==531
    overlaps=[c['cell'] for c in screen['cells'] if any(v['possible_overlap'] for v in c['samples'])]
    archive_path=BASE/'archives/runtime-004.json';archive=json.loads(archive_path.read_text());pins[str(archive_path)]=sha(archive_path);assert archive['verified'] and archive['archive_sha256']=='37880c8af762b3470f810cdd927bc1ebe37567d1fdc80c0a531d33251b624ce6'
    (out/'archive-verification-snapshot.json').write_text(json.dumps(archive,indent=2)+'\n');(out/'regression-screen-snapshot.json').write_text(json.dumps(screen,indent=2)+'\n')
    result={'scope':60,'completed_runtime_pairs':59,'parity_pass':1,'parity_unmet':True,'counted_invocations_verified':len(rc),'rc_and_exit_live':rc,'compilation':compiled,'matched_pairs':len(matches),'matched_candidate_wins':wins,'conservative_overlap_cases':overlaps,'overlap_resolution':screen['overlap_resolution'],'archive':{'metadata_path':str(archive_path),'verified':True,'archive_sha256':archive['archive_sha256'],'note':'Coordinator verification metadata pinned; archive not rehashed/recompressed by synthesis.'},'inputs':pins}
    assert all(sha(p)==h for p,h in pins.items());(out/'derived-summary.json').write_text(json.dumps(result,indent=2)+'\n')
    rows=s['runtime_and_rss']['cases']
    with (out/'cases.csv').open('w',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    print('derived60case metrics;',len(rc),'counted invocations verified;531/531matched improvements retained')


if __name__=='__main__':main()
