"""Read validated runtime receipts; preserve pairs and conservative chunk overlap."""
import datetime as dt
import hashlib
import json
import pathlib
import statistics as st
ROOT=pathlib.Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012')
BASE=ROOT/'experiments/lox-eda-parity-20261013'
ATT=BASE/'attempts/runtime-004'
OUT=pathlib.Path(__file__).resolve().parent
P7=pathlib.Path('/home/epentland/ai/canopy/mylang-lox-runtime-stack-20261013-p7/experiments/lox-eda-parity-20261013/P7-micro-final-004/concurrent-analysis-context.json')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def utc(s):return dt.datetime.fromisoformat(s.replace('Z','+00:00'))
report=ATT/'parity-report.json'
assert sha(report)=='5f069e3f1532fc6151df0ccc565555b05a128ee1f0011279e3d0f396c4fbedf6'
pub=json.loads((BASE/'coordinator/report-validation-004/publication.json').read_text())
validation=json.loads((BASE/'coordinator/report-validation-004/validation.json').read_text())
assert pub['sha256']==validation['report_sha256']==sha(report) and pub['byte_identical']
context=json.loads((BASE/'coordinator/measurement-context-004.json').read_text());p7=json.loads(P7.read_text())
windows={'coordinator_search':['2026-10-13T09:35:01Z','2026-10-13T09:36:06Z'],'worker_analysis':[p7['analysis']['start_bound'],p7['analysis']['finish_output_bound']],'worker_compression':[p7['compression']['start_file_birth'],p7['compression']['finish_archive_lastwrite']],'worker_archive_verification':[p7['archive_verification']['start_lower_bound'],p7['archive_verification']['finish_upper_bound']]}
rows=[]
for name,cell in sorted(json.loads(report.read_text())['cells'].items()):
 files=[ATT/'runtime'/f'{name}.chunk{i:02d}.json' for i in range(13)];rs=[json.loads(p.read_text()) for p in files]
 assert all(rs[i]['prior_receipt']['sha256']==sha(files[i-1]) for i in range(1,13))
 samples=[]
 for i,r in enumerate(rs):
  overlap=[k for k,(a,b) in windows.items() if utc(r['started_utc'])<=utc(b) and utc(r['finished_utc'])>=utc(a)]
  vals={s['arm']:s['value'] for s in r['wall_samples']}
  if vals:samples.append({'chunk':i,'started_utc':r['started_utc'],'finished_utc':r['finished_utc'],'values':vals,'possible_overlap':overlap})
 arms=cell['arms'];censors={a:v for a,v in rs[-1]['arm_status'].items() if v['status']!='ok'}
 row={'cell':name,'censors':censors,'samples':samples,'receipt_hashes':[sha(p) for p in files]}
 if arms['mylang-before']['status']==arms['mylang-zero-rc']['status']=='ok':
  assert len(samples)==9 and all('mylang-before' in s['values'] and 'mylang-zero-rc' in s['values'] for s in samples)
  ratios=[s['values']['mylang-zero-rc']/s['values']['mylang-before'] for s in samples]
  row.update(paired_ratios=ratios,paired_median=st.median(ratios),paired_range=[min(ratios),max(ratios)],slower_pairs=sum(v>1 for v in ratios),over_5_percent_pairs=sum(v>1.05 for v in ratios),median_quotient=arms['mylang-zero-rc']['wall_seconds']/arms['mylang-before']['wall_seconds'],flag=st.median(ratios)>1.05)
 rows.append(row)
result={'report_sha256':sha(report),'validation_sha256':sha(BASE/'coordinator/report-validation-004/validation.json'),'publication_sha256':sha(BASE/'coordinator/report-validation-004/publication.json'),'measurement_context':context,'worker_context':p7,'overlap_windows':windows,'overlap_resolution':'Whole chunk interval only; exact individual launch times unavailable. Possible overlap is conservative, not proof of contention.','cells':rows}
(OUT/'final-screen.json').write_text(json.dumps(result,indent=2)+'\n')
print('cells',len(rows),'paired',sum('paired_ratios' in r for r in rows))
for r in rows:
 if r.get('flag') or r['censors']:print(r['cell'],{k:v for k,v in r.items() if k not in ['samples','receipt_hashes','paired_ratios']})
print('overlap cells',sum(any(s['possible_overlap'] for s in r['samples']) for r in rows))
print('widest',sorted([(max(r['paired_ratios'])-min(r['paired_ratios']),r['cell'],r['paired_median'],r['slower_pairs']) for r in rows if 'paired_ratios' in r],reverse=True)[:8])
