#!/usr/bin/env python3
"""Validate frozen micro receipts and produce per-cell evidence; never run guests."""
import argparse,csv,gzip,hashlib,importlib.util,json,math,pathlib,random,re,statistics
MY=('mylang-original-rc','mylang-migrated-rc','mylang-zero-rc')
FOREIGN=('zig-safe','zig-fast','rust','go')
METRICS=('allocs','reallocs','alloc_bytes','realloc_added_bytes','cumulative_allocated_bytes','peak_live_bytes','live_bytes_at_exit','retain','release','runtime_retains','runtime_releases','shared_retains','shared_releases','unique_test','rc_events','direct_destructions','share_marks','text_copies','text_copy_bytes','list_copies','list_copy_bytes','dict_copies','dict_copy_bytes','buffer_copies','buffer_copy_bytes')
def digest(p): return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def load(p): return json.loads(gzip.open(p,'rt').read() if str(p).endswith('.gz') else pathlib.Path(p).read_text())
def require(ok,message):
 if not ok: raise ValueError(message)
def med(v): return statistics.median(v)
def interval(a,b,label,repetitions):
 require(set(a)==set(b),'unmatched rounds '+label)
 rounds=sorted(a); point=med(list(a.values()))/med(list(b.values()))
 rng=random.Random(int(hashlib.sha256(label.encode()).hexdigest()[:16],16)); values=[]
 for _ in range(repetitions):
  indices=[rng.choice(rounds) for _ in rounds]; values.append(med([a[i] for i in indices])/med([b[i] for i in indices]))
 values.sort()
 def quantile(p):
  position=(len(values)-1)*p; lo=math.floor(position); hi=math.ceil(position)
  return values[lo]+(values[hi]-values[lo])*(position-lo)
 return {'ratio':point,'ci95':[quantile(.025),quantile(.975)],'paired_rounds':len(rounds),'bootstrap_repetitions':repetitions,'estimator':'ratio of medians; matched round indices resampled jointly'}
def validate_guest(v,spec,expected):
 require(v['status']=='ok' and v.get('exit_status')==0 and v.get('stderr')=='','invalid accepted guest')
 if spec['protocol']=='kernel':
  match=re.fullmatch(r'([0-9]+) ([0-9]+)\n',v['stdout'])
  require(match is not None and int(match[1])==expected and int(match[2])==v.get('kernel_ns') and v['kernel_ns']>0,'kernel protocol mismatch')
 else: require(v['stdout']==expected,'fixed output mismatch')
 require(v['process_wall_ns']>0,'nonpositive wall time')
def metrics(raw):
 require(raw['version']=='mylang-counters-v1','counter schema')
 t,k=raw['totals'],raw['kinds']; result={n:t.get(n,0) for n in METRICS[:4]+('peak_live_bytes','live_bytes_at_exit','runtime_retains','runtime_releases','shared_retains','shared_releases')}
 result.update({n:k[n]['count'] for n in ('retain','release','unique_test','release_unique')})
 result['cumulative_allocated_bytes']=result['alloc_bytes']+result['realloc_added_bytes']
 result['rc_events']=sum(result[n] for n in ('retain','release','runtime_retains','runtime_releases','shared_retains','shared_releases'))
 result['direct_destructions']=result['release_unique']; return result

def analyze(root,path,spec,registry,args):
 d=load(path); cell=spec['cell']; require(d['schema']=='micro-ownership-cell-v1' and d['spec']==spec,'receipt/spec mismatch '+cell)
 require(d['identities']==d['identities_after'],'changed measurement identities '+cell)
 for p,h in d['identities'].items():
  require(re.fullmatch('[0-9a-f]{64}',h) is not None,'invalid hash')
  if args.check_artifacts: require(digest(pathlib.Path(p) if pathlib.Path(p).is_absolute() else root/p)==h,'current artifact changed '+p)
 require(set(d['arm_status'])==set(spec['arms'])==set(d['summary']),'arm inventory '+cell)
 require(set(d['counted'])==set(spec['counted'])==set(MY),'counted inventory '+cell)
 n=d['iterations']; require(type(n)==int and n>0,'iterations '+cell)
 expected=registry.checksum(spec['case'],spec['size'],n,spec['seed']) if spec['protocol']=='kernel' else spec['expected_stdout']
 require(expected==d['expected'],'independent oracle '+cell)
 if spec['protocol']=='kernel':
  require(d['calibration']['iterations']==n and d['calibration']['reason'] in ('target','iteration_cap','slowest_arm_budget','one_iteration_exceeds_budget','pilot_limit','no_admitted_arm'),'calibration '+cell)
  for pilot in d['pilots']:
   for v in pilot['arms']: validate_guest(v,spec,registry.checksum(spec['case'],spec['size'],pilot['iterations'],spec['seed']))
 output={'cell':cell,'case':spec['case'],'profile':spec.get('profile'),'size':spec.get('size'),'unit':spec['unit'],'protocol':spec['protocol'],'receipt':str(path),'receipt_sha256':digest(path),'iterations':n,'calibration':d.get('calibration'),'started_utc':d['started_utc'],'finished_utc':d['finished_utc'],'cpu':d['cpu'],'loadavg_before':d['loadavg_before'],'loadavg_after':d['loadavg_after'],'environment':d['environment'],'cpu_busy_percent':{cpu:100*(1-(after['idle']-d['cpu_ticks_before'][cpu]['idle'])/(after['total']-d['cpu_ticks_before'][cpu]['total'])) for cpu,after in d['cpu_ticks_after'].items() if after['total']>d['cpu_ticks_before'][cpu]['total']},'identities':d['identities'],'arms':{},'comparisons':{}}
 sample_maps={}
 for arm,entry in spec['arms'].items():
  require(entry['binary'] in d['identities'] and d['identities'][entry['binary']]==entry['sha256'] if entry.get('binary') else entry['status']!='ok','binary receipt '+cell+'/'+arm)
  state=d['arm_status'][arm]; require(d['summary'][arm]['status']==state,'summary status '+cell+'/'+arm); require(entry['status']=='ok' or state==entry,'refusal changed '+cell+'/'+arm); lists={phase:[v for v in d[phase] if v['arm']==arm] for phase in ('samples','warmups','rss')}
  for phase,values in lists.items():
   require(len({v['round'] for v in values})==len(values),'duplicate round '+cell+'/'+arm+'/'+phase)
   for v in values:
    validate_guest(v,spec,expected); require(v['iterations']==n,'different count '+cell)
    if phase=='rss': require(v['peak_rss_kib']>0,'rss '+cell)
  complete=state['status']=='ok' and len(lists['samples'])==spec['rounds'] and len(lists['warmups'])==spec['warmups'] and len(lists['rss'])==spec['rss_rounds']
  if state['status']=='ok': require(complete,'missing accepted rounds '+cell+'/'+arm)
  require(d['summary'][arm]['complete']==complete,'summary completeness '+cell+'/'+arm)
  values={v['round']:(v['kernel_ns']/n if spec['protocol']=='kernel' else v['process_wall_ns']) for v in lists['samples']}
  item={'status':state,'complete':complete,'binary_sha256':entry.get('sha256'),'source':entry.get('source'),'flags':entry.get('flags'),'sample_count':len(lists['samples']),'warmup_count':len(lists['warmups']),'rss_count':len(lists['rss']),'time_metric':'kernel_ns_per_iteration' if spec['protocol']=='kernel' else 'process_wall_ns','median':med(list(values.values())) if complete else None,'rss_median_kib':med([v['peak_rss_kib'] for v in lists['rss']]) if complete else None}
  if complete:
   sample_maps[arm]=values
   summary=d['summary'][arm]; key=item['time_metric']; require(summary[key]['median']==item['median'] and summary['peak_rss_kib']['median']==item['rss_median_kib'],'summary median '+cell+'/'+arm)
   require(set(values)==set(range(spec['rounds'])) and {v['round'] for v in lists['warmups']}==set(range(-spec['warmups'],0)) and {v['round'] for v in lists['rss']}==set(range(spec['rss_rounds'])),'round range '+cell+'/'+arm)
  if arm in d['counted']:
   count=d['counted'][arm]; item['counted_status']=count['status']; item['counted_raw']=count
   if 'counter_path' in count:
    cp=pathlib.Path(count['counter_path']); cp=cp if cp.is_absolute() else root/cp
    require(digest(cp)==count['counter_sha256'],'counter hash '+cell+'/'+arm)
    raw_counter=load(cp); computed=metrics(raw_counter); require(computed==count['metrics'],'counter metrics '+cell+'/'+arm); item['counter_totals']=raw_counter['totals']; item['counter_kinds']=raw_counter['kinds']; item['counters']={**computed,**{k:raw_counter['totals'].get(k,0) for k in METRICS if k not in computed}}
    if count['status']=='ok':
     require(count['iterations']==n,'counted iteration mismatch '+cell); counted_entry=spec['counted'][arm]; require(d['identities'].get(counted_entry['binary'])==counted_entry['sha256'],'counted binary identity '+cell+'/'+arm)
     validate_guest(count,spec,expected); require(computed['live_bytes_at_exit']==0,'exit-live '+cell+'/'+arm)
     if arm==MY[2]: require(computed['rc_events']==computed['unique_test']==raw_counter['totals'].get('share_marks',0)==0,'unexpected zero RC '+cell)
  output['arms'][arm]=item
 for a in MY:
  for b in MY+FOREIGN:
   if a!=b and a in sample_maps and b in sample_maps: output['comparisons'][a+'/'+b]=interval(sample_maps[a],sample_maps[b],cell+'/'+a+'/'+b,args.bootstrap)
 return output

def history(root,cells):
 inventory=root/'experiments/micro-ownership-20261012/references/history-confirmations.json'
 paths=[root/'benchmarks/runtime/expanded/results/baseline_main_20261003.json',root/'benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz']
 if inventory.exists():
  for report in load(inventory):
   for entry in report['linked_artifacts']:
    if entry.get('schema')=='mylang-runtime-expanded-v2' and entry['available']: paths.append(pathlib.Path(entry['path']))
 result=[]; seen=set()
 for p in paths:
  if str(p) in seen: continue
  seen.add(str(p))
  if not p.exists(): result.append({'path':str(p),'status':'unavailable'}); continue
  d=load(p); summaries={(v['case'],v['size'],v['arm']):v for v in d['summary']}; identity=d['identity']
  item={'path':str(p),'sha256':digest(p),'schema':d['schema'],'status':d.get('status'),'source_revision':identity.get('source_revision'),'candidate_id':identity.get('candidate_id'),'started_utc':d.get('started_utc'),'finished_utc':d.get('finished_utc'),'measurement_session_id':d.get('measurement_session_id'),'rounds':d.get('rounds'),'warmup_rounds':d.get('warmup_rounds'),'tools':identity.get('tools'),'target_policy':identity.get('target_policy'),'environment':d.get('environment'),'binary_hashes':d.get('binary_hashes'),'sources':identity.get('sources'),'compiler_build_receipt':identity.get('compiler_build_receipt'),'current_to_historical':[]}
  for cell in cells:
   if cell['protocol']!='kernel': continue
   for arm in MY:
    now=cell['arms'][arm]
    old=summaries.get((cell['case'],cell['size'],'my-llvm'))
    if now['complete'] and old:
     item['current_to_historical'].append({'cell':cell['cell'],'current_arm':arm,'historical_arm':'my-llvm','current_ns_per_iteration':now['median'],'historical_ns_per_iteration':old['median_ns_per_op'],'cross_date_ratio':now['median']/old['median_ns_per_op'],'interpretation':'descriptive only: different source/compiler/tool/host identities; no matched rounds or causal speedup claim'})
  result.append(item)
 return result

def priorities(cells):
 output=[]
 for cell in cells:
  comps=cell['comparisons']; z=comps.get(MY[2]+'/'+MY[1]); migration=comps.get(MY[1]+'/'+MY[0]); orig=cell['arms'][MY[0]]; zero=cell['arms'][MY[2]]
  if not zero['complete']:
   output.append({'category':'admission/correctness','cell':cell['cell'],'status':zero['status'],'score':1e9,'interpretation':'preserve refusal or failure; performance unavailable'}); continue
  if z and z['ci95'][0]>1.10:
   a=zero.get('counters',{}); b=cell['arms'][MY[1]].get('counters',{}); growth=a.get('cumulative_allocated_bytes',0)/b['cumulative_allocated_bytes'] if b.get('cumulative_allocated_bytes') else None
   output.append({'category':'mode on shared migrated source','cell':cell['cell'],'comparison':z,'cumulative_allocation_ratio':growth,'score':z['ci95'][0],'interpretation':'investigate necessary snapshots versus avoidable intermediate copies at collection boundaries using checked local borrows/moves; allocation counters corroborate traffic, not CPU attribution'})
  if migration and (migration['ci95'][0]>1.10 or migration['ci95'][1]<.90): output.append({'category':'shared source migration','cell':cell['cell'],'comparison':migration,'score':max(migration['ratio'],1/migration['ratio']),'interpretation':'RC-on-migrated versus RC-on-original changes source shape while holding memory mode'})
  foreign=[(arm,comps.get(MY[0]+'/'+arm)) for arm in FOREIGN]; foreign=[(arm,v) for arm,v in foreign if v and v['ci95'][0]>1.10]
  if foreign:
   arm,v=max(foreign,key=lambda pair:pair[1]['ci95'][0]); output.append({'category':'existing compiler/backend or language/library gap','cell':cell['cell'],'reference':arm,'comparison':v,'score':v['ci95'][0],'interpretation':'original RC is already slower; does not isolate ownership; native API and target policies may differ'})
 category_order={'admission/correctness':0,'mode on shared migrated source':1,'shared source migration':2,'existing compiler/backend or language/library gap':3}
 output.sort(key=lambda v:(category_order[v['category']],-v['score']))
 for item in output:
  case=item['cell'].split('/')[1]
  if item['category']=='mode on shared migrated source':
   if case in ('mutate_nested','mutate_shared'): item['interpretation']='independent-snapshot contract requires explicit copy; this measures necessary deep-copy semantics, not automatically a correctness or optimizer bug; cumulative traffic and peak/RSS remain separate'
   elif case=='sort_records': item['interpretation']='equal allocation count and cumulative bytes distinguish an implementation cost from extra allocation; core_sort.c owned keyed sort at849 uses in-place permutation cycles, versus RC copied output at827; source-supported follow-up hypothesis, not sampled CPU attribution'
   elif case=='int_format': item['interpretation']='kernel includes formatting and checksum encoding; extra allocation is attributed to text::score text.encode() at text.my:31, not established numeric formatter cost; investigate borrowed byte reads/avoidable intermediates while preserving owned encode-result semantics'
  elif case=='alloc_short': item['interpretation']='existing scalar-replacement/arithmetic-simplification or native-port gap; checked counters record only11 setup allocations and batch_result0; this does not measure managed allocator throughput'
  item.pop('score',None)
 return output

def ratio_text(v): return f"{v['ratio']:.3f} [{v['ci95'][0]:.3f}, {v['ci95'][1]:.3f}]" if v else 'unavailable'
def markdown(report):
 lines=[f"# {'DRAFT: incomplete ' if report['draft'] else ''}Microbenchmark ownership evidence",'',f"Validated {len(report['cells'])}/91 receipts; {len(report['pending'])} pending. This report keeps each case and documented iteration unit separate. No overall score pools unrelated workloads.",'',
 'Current MyLang guests use the supported LLVM-only command path. Historical my-llvm/my-qbe receipts retain their original compiler and executable identities; there is no fresh QBE measurement. Parity compares six arms and uses the canonical Rust native-target policy; expanded compares seven arms and uses portable Rust, Go GOAMD64=v1, and host-default Zig. Canonical parity MyLang ports retain fixed literal bounds, while supplied Zig opaqueN and Rust black_box obscure loop bounds. These are the supplied canonical ports, not a claim of uniform optimization barriers or target policy. Target/API differences remain part of each suite comparison.','',
 'Parity time is full-process wall time, including startup; very short cases can be sensitive to the launch floor. Expanded time is native kernel ns per documented CLI iteration, excluding fixture setup. Child peak RSS is the median of three separate uninstrumented GNU-time runs and includes setup/runtime state. Counted runs are separate: allocation/reallocation/cumulative bytes, managed peak, exit-live and RC events include the whole program and fixture setup. Direct destruction is not an RC event. Foreign allocation counters are unavailable.','',
 'Ratios are numerator/comparison arm; above one means slower. Intervals use a deterministic 95% paired bootstrap of the ratio of medians, jointly resampling matched round indices. Intervals containing one do not establish a speed difference. These single-session exploratory intervals need independent confirmation. Counted time never supplies a timing sample.','',
 'The inherited calibration can label <5% growth termination as slowest_arm_budget even when the fastest pilot is just below 50 ms and the slowest is well below 1 s. Raw fastest/slowest durations and all limits appear below; that reason alone does not establish reaching the slowest cap.','',
 f"Sibling activity above5%: {len(report['interference_warnings'])} cell/sibling entries; full percentages are retained in JSON. Average activity cannot rule out brief interference or enforce exclusive CPU ownership.",'', '## Per-case comparisons','', '| Cell | Unit/time | Original RC | Migrated RC | Zero RC | Zero/original [95%] | Migrated/original [95%] | Zero/migrated [95%] |','|---|---|---:|---:|---:|---|---|---|']
 for c in report['cells']:
  display=[]
  for a in MY:
   v=c['arms'][a]; display.append(f"{v['median']:.3f}" if v['complete'] else v['status']['status'])
  lines.append('| '+ ' | '.join([c['cell'],('ns/iteration: '+c['unit']) if c['protocol']=='kernel' else 'wall ns/execution',*display,*[ratio_text(c['comparisons'].get(a+'/'+b)) for a,b in ((MY[2],MY[0]),(MY[1],MY[0]),(MY[2],MY[1]))]])+' |')
 lines.extend(['','## Foreign comparisons','','| Cell | MyLang arm | / Zig Safe [95%] | / Zig Fast [95%] | / Rust [95%] | / Go [95%] |','|---|---|---|---|---|---|'])
 for c in report['cells']:
  for arm in MY: lines.append('| '+ ' | '.join([c['cell'],arm,*['not in parity suite' if b=='go' and c['protocol']=='fixed' else ratio_text(c['comparisons'].get(arm+'/'+b)) for b in FOREIGN]])+' |')
 lines.extend(['','## Separate RSS and managed counts','','All byte/count values below are whole-program totals at the recorded iteration count, not per-iteration allocation. Raw compiler/runtime/shared RC components and uniqueness tests are retained in JSON/CSV.','','| Cell | Arm | Child RSS KiB | Allocs | Reallocs | Cumulative bytes | Managed peak bytes | Exit-live bytes | RC events | Unique tests | Direct destructions |','|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|'])
 for c in report['cells']:
  for arm,v in c['arms'].items():
   m=v.get('counters',{}); lines.append('| '+ ' | '.join([c['cell'],arm,str(v['rss_median_kib']) if v['rss_median_kib'] is not None else 'unavailable',*[str(m.get(k,'unavailable')) for k in ('allocs','reallocs','cumulative_allocated_bytes','peak_live_bytes','live_bytes_at_exit','rc_events','unique_test','direct_destructions')]])+' |')
 lines.extend(['','## Calibration, refusals and failures','','| Cell | Iterations | Fastest pilot ms | Slowest pilot ms | Reason | Limited |','|---|---:|---:|---:|---|---|'])
 for c in report['cells']:
  cal=c['calibration']
  if cal: lines.append(f"| {c['cell']} | {c['iterations']} | {(cal['fastest_ns'] or 0)/1e6:.3f} | {(cal['slowest_ns'] or 0)/1e6:.3f} | {cal['reason']} | {cal['limited']} |")
 for c in report['cells']:
  for arm,v in c['arms'].items():
   if not v['complete']: lines.extend(['',f"- Runtime {c['cell']} / {arm}: `{json.dumps(v['status'],sort_keys=True)}`"])
   if v.get('counted_status') not in (None,'ok'): lines.extend(['',f"- Counted {c['cell']} / {arm}: `{json.dumps(v['counted_raw'],sort_keys=True)}`"])
 lines.extend(['','## Investigation priorities','','Application evidence sets the practical order: first investigate the snapshot/copy boundaries behind Lox VM frame execution and EDA list slicing/accessors. The full application report records zero/migrated EDA wall ratio 10.458; Lox VM has three uninstrumented 120 s censors and counted Fibonacci 2,712,877,890 allocations versus 460 in RC. The application report retains its own compiler/reference identities; these ratios are context rather than pooled micro evidence. These application observations and micro counters corroborate an allocation/copy investigation; they do not measure CPU attribution or establish an unavoidable zero-RC lower bound.','',
 'The migrated RC versus original RC comparison identifies shared source-migration changes. Checked zero-RC versus migrated RC uses the same migrated source and isolates the mode comparison within that implementation. Original RC versus foreign code exposes an already-existing compiler/backend/library gap. Investigations must preserve local checked borrows/moves and explicit independent copies. Separate necessary value snapshots from avoidable intermediate copies; these priorities do not propose RC/COW, lifetime syntax or broad whole-program ownership inference. No optimization has been made by this analysis.',''])
 for p in report['priorities'][:20]: lines.append(f"- {p['cell']}: {p['category']}; {ratio_text(p.get('comparison'))}. {p['interpretation']}.")
 churn=[c for c in report['cells'] if c['case']=='alloc_churn']
 if churn and all(c['arms'][a].get('counters',{}).get('allocs')==0 for c in churn for a in MY): lines.extend(['','The parity alloc_churn case records zero managed heap allocations in every current MyLang mode. Despite its name it no longer isolates heap-allocation cost; its timing must not be read as allocator throughput.'])
 lines.extend(['','Expanded alloc_short likewise does not isolate managed heap churn: checked counters show11 setup allocations (<outside>5, main6) and batch_result0 at both sizes. Ordinary scalar replacement/arithmetic simplification is permitted by the canonical contract; its large foreign gap is an existing optimization/native-port difference, not allocator throughput.','','int_format includes formatting plus checksum encoding. Raw checked counters attribute the extra allocation to text::score/text.encode() at text.my:31. This is not established numeric formatter cost. Independent mutate_nested snapshots require explicit nested.copy(); their traffic is necessary value-snapshot semantics. sort_records instead has equal mode allocation counts/cumulative bytes and lower checked managed peak; its mode gap needs a distinct keyed-sort implementation investigation.','', 'Known-core-RC symbol audit: '+(str(report['symbol_audit'].get('path'))+' (SHA256 '+str(report['symbol_audit'].get('sha256'))+')' if report['symbol_audit'].get('path') else 'pending')+'. Symbol absence is a static audit separate from executed counters; neither proves arbitrary unreachable code behavior.', '', '## Historical context','','history.json records the complete October3 expanded-v1 baseline, the complete expanded-v2 final730a86e6 run and available October4 independently confirmed B1/G2/G4 subsets, with their own source/tool/target/host metadata. current_to_historical rows compare only the historical my-llvm arm descriptively. Historical QBE is never pooled into a current mode comparison. Cross-date ratios have no paired interval and establish no causal compiler/ownership speedup. G4 is a later confirmed six-case subset, not a complete replacement baseline.','',f"Application comparison source: {report['application_evidence']['path']} (SHA256 {report['application_evidence']['sha256']}).",'',f"Pending receipts: {', '.join(report['pending']) if report['pending'] else 'none'}."])
 return '\n'.join(lines)+'\n'

def main():
 p=argparse.ArgumentParser(description=__doc__); p.add_argument('--input-root',type=pathlib.Path,required=True); p.add_argument('--output',type=pathlib.Path,required=True); p.add_argument('--draft',action='store_true'); p.add_argument('--check-artifacts',action='store_true'); p.add_argument('--bootstrap',type=int,default=5000); args=p.parse_args()
 require(args.bootstrap>=100,'bootstrap repetitions'); root=args.input_root.resolve(); base=root/'experiments/micro-ownership-20261012'; out=args.output.resolve()
 require(not out.exists(),'never overwrite existing report output')
 if args.draft: require('.tmp' in out.parts,'draft output must be private .tmp')
 sp=importlib.util.spec_from_file_location('report_registry',root/'benchmarks/runtime/expanded/registry.py'); registry=importlib.util.module_from_spec(sp); sp.loader.exec_module(registry)
 specs=[]
 for suite in ('parity','expanded'):
  files=sorted((base/('specs-'+suite)).glob('*.json')); require(len(files)==(11 if suite=='parity' else 80),'expected spec count '+suite)
  for path in files:
   s=load(path); require(set(s['arms'])==set(MY+FOREIGN[:3]+(('go',) if suite=='expanded' else ())), 'spec arms '+s['cell']); require(s['rounds']==(9 if suite=='parity' else 15) and s['warmups']==(2 if suite=='parity' else 3) and s['rss_rounds']==3,'sampling policy '+s['cell']); specs.append((suite,path,s))
 require(len({s['cell'] for _,_,s in specs})==91,'duplicate cells')
 require({s['case'] for suite,_,s in specs if suite=='parity'}==set(('intloop','calls','fib','records','list_append_sum','list_records','dict_count','str_build','alloc_churn','float_loop','bytes_scan')),'parity inventory')
 actual={(s['case'],s['size'],s['profile']) for suite,_,s in specs if suite=='expanded'}; expected={(c,n,p) for c,meta in registry.inventory().items() for n,p in zip(meta['sizes'],('small','large'))}; require(actual==expected,'expanded inventory')
 cells=[]; pending=[]
 for suite,path,s in specs:
  receipt=base/'results'/suite/path.name
  if not receipt.exists(): pending.append(s['cell']); continue
  cells.append(analyze(root,receipt,s,registry,args))
 require(args.draft or not pending,'final report requires all91 frozen receipts')
 app=root/'experiments/lox-eda-zero-rc-20261012/bench/full-final/COMPARISON.md'; require(app.exists(),'application evidence missing')
 report={'schema':'micro-ownership-report-v1','draft':args.draft,'receipt_coverage':{'expected':91,'received':len(cells),'pending':pending},'pending':pending,'input_root':str(root),'generator_sha256':digest(__file__),'bootstrap':args.bootstrap,'application_evidence':{'path':str(app),'sha256':digest(app)},'cells':cells,'priorities':priorities(cells),'build_evidence':{name:{'sha256':digest(base/name),'content':load(base/name)} for name in ('parity/handoff.json','expanded/manifest.json','references/manifest.json')}}
 report['coordinator_evidence']={name:{'sha256':digest(base/'coordinator'/name),'content':load(base/'coordinator'/name)} for name in ('measurement-host.json','session.json')}
 host=report['coordinator_evidence']['measurement-host.json']['content']; require(all(c['cpu']==host['cpu'] for c in cells),'measurement CPU mismatch')
 siblings=[]
 for token in host['topology']['thread_siblings_list'].split(','):
  bounds=token.split('-'); siblings.extend(range(int(bounds[0]),int(bounds[-1])+1))
 report['interference_warnings']=[{'cell':c['cell'],'sibling_cpu':cpu,'average_busy_percent':c['cpu_busy_percent'].get('cpu'+str(cpu))} for c in cells for cpu in siblings if cpu!=c['cpu'] and c['cpu_busy_percent'].get('cpu'+str(cpu),0)>5]
 audit=base/'coordinator/symbol-audit.json'
 report['symbol_audit']={'path':str(audit),'sha256':digest(audit),'content':load(audit)} if audit.exists() else {'status':'pending'}
 if not args.draft: require(audit.exists(),'final symbol audit missing')
 if audit.exists():
  entries=report['symbol_audit']['content']['entries']; require(len(entries)==90 and len({e['binary'] for e in entries})==90,'symbol audit inventory'); checked=[e for e in entries if e['arm']==MY[2]]; require(len(checked)==30 and all(not e['known_core_rc_symbols'] for e in checked),'checked symbol audit')
  for entry in entries:
   if args.check_artifacts: require(digest(entry['binary'])==entry['sha256'],'symbol audit binary changed')
 hist=history(root,cells); out.mkdir(parents=True)
 (out/'report.json').write_text(json.dumps(report,indent=2)+'\n'); (out/'history.json').write_text(json.dumps(hist,indent=2)+'\n'); (out/'REPORT.md').write_text(markdown(report))
 fields=['cell','case','profile','size','unit','iterations','arm','runtime_status','complete','time_metric','median','rss_median_kib','counted_status',*METRICS]
 with (out/'per-arm.csv').open('w',newline='') as stream:
  writer=csv.DictWriter(stream,fieldnames=fields); writer.writeheader()
  for c in cells:
   for arm,v in c['arms'].items(): writer.writerow({**{k:c.get(k) for k in ('cell','case','profile','size','unit','iterations')},'arm':arm,'runtime_status':v['status']['status'],**{k:v.get(k) for k in ('complete','time_metric','median','rss_median_kib','counted_status')},**{k:v.get('counters',{}).get(k) for k in METRICS}})
 print(f"validated {len(cells)}/91 receipts; pending={len(pending)}; draft={args.draft}; output={out}")
if __name__=='__main__': main()
