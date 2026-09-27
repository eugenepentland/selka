from pathlib import Path
import importlib.util,os,subprocess,json,hashlib,statistics
r=Path.cwd();w=r/'.tmp-rc/owned-loops-combined';perf=r.parent/'d9-rc-performance'
spec=importlib.util.spec_from_file_location('acceptance',perf/'experiments/d9-rc-acceptance-20260926/compare.py');A=importlib.util.module_from_spec(spec);spec.loader.exec_module(A);PC=A.pc
os.environ['TMPDIR']=str(r/'.tmp-rc/tmp');os.environ['ZIG_LOCAL_CACHE_DIR']=str(w/'zig-cache')
c=r/'.tmp-rc/install-owned-loops-combined/bin/mylang';base_path=A.WORK/'gc-builds.json';base=json.loads(base_path.read_text());assert base['compiler_sha256']==A.GC_SHA==A.sha(base['compiler']);assert base['inputs']==A.inputs()
names=['alloc_churn','sieve','list_append_sum','fannkuch_redux'];programs=[next(p for p in A.programs() if p['id'].endswith('/'+n)) for n in names]
d={'compiler':str(c),'compiler_sha256':A.sha(c),'compiler_source':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'gc_compiler':base['compiler'],'gc_compiler_sha256':base['compiler_sha256'],'gc_manifest_sha256':A.sha(base_path),'harness_sha256':A.sha(A.HARNESS),'cpu':10,'programs':programs,'source_hashes':{p['src']:A.sha(p['src']) for p in programs},'builds':[],'checks':[],'runs':[],'counts':[],'samples':{}}
def save():(w/'results.json').write_text(json.dumps(d,indent=2)+'\n')
for p in programs:
 for backend in ['qbe','llvm']:
  key=p['build_key']+'.'+backend;gc=A.WORK/'bin/gc'/key;assert A.sha(gc)==base['builds'][key]['sha256']
  for stats in [False,True]:
   binary=w/'bin'/(key+('.stats' if stats else ''));cmd,cwd=PC.build_command(p,str(c),backend,binary,w/'cache');cmd=[str(r/'scripts/build-slot.sh'),'build',*cmd,'--rc-runtime=stats' if stats else '--rc-runtime']
   job={'bin':binary,'cmd':cmd,'cwd':cwd};built=PC.do_build(job);row={'key':key,'stats':stats,'cwd':cwd,**built};d['builds'].append(row);save();assert built['ok'],row
  rc=w/'bin'/key;runs={'gc':PC.run_spec(p,gc,'fresh-gc-'+backend),'rc':PC.run_spec(p,rc,'fresh-rc-'+backend)}
  for side,run in runs.items():
   check=PC.check(p,run);d['checks'].append({'key':key,'side':side,'binary_sha256':A.sha(run['argv'][0]),'argv':run['argv'],'cwd':run['cwd'],'environment':{k:v for k,v in run['env'].items() if k.startswith('MYLANG_')},**check});save();assert check['ok'],check
  observations={'gc':[],'rc':[]};expected=Path(p['expected_path']).read_bytes()
  for repeat in range(3):
   for side in (['gc','rc'] if repeat%2==0 else ['rc','gc']):
    run=runs[side];stat=w/f'{key}-{side}-{repeat}.stat';cmd=['taskset','-c','10','perf','stat','-x,','-e','instructions:u','-o',str(stat),'--',*run['argv']]
    done=subprocess.run(cmd,cwd=run['cwd'],env=run['env'],capture_output=True,timeout=PC.RUN_TIMEOUT);raw=stat.read_text();count=next(int(line.split(',')[0]) for line in raw.splitlines() if 'instructions' in line and line.split(',')[0].isdigit())
    row={'key':key,'side':side,'repeat':repeat,'command':cmd,'status':done.returncode,'stdout':done.stdout.decode(),'stderr':done.stderr.decode(),'instructions':count,'perf':raw,'binary_sha256':A.sha(run['argv'][0])};d['runs'].append(row);save();assert done.returncode==0 and done.stdout==expected,row;observations[side].append(count)
  med={side:statistics.median(values) for side,values in observations.items()};d['samples'][key]={'medians':med,'rc_gc_ratio':med['rc']/med['gc']};save()
  counted=w/'bin'/(key+'.stats');run=PC.run_spec(p,counted,'fresh-counts-'+backend);done=subprocess.run(['taskset','-c','10',*run['argv']],env=run['env'],cwd=run['cwd'],capture_output=True,timeout=PC.RUN_TIMEOUT)
  row={'key':key,'status':done.returncode,'stdout':done.stdout.decode(),'stderr':done.stderr.decode(),'binary_sha256':A.sha(counted)};d['counts'].append(row);save();assert done.returncode==0 and done.stdout==expected,row
  counts=json.loads(next(s.removeprefix('MYLANG_RC_COUNTS ') for s in row['stderr'].splitlines() if s.startswith('MYLANG_RC_COUNTS ')));row['counts']=counts;assert counts['heap_allocate']==counts['retire'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'] and counts['hold_acquire']==counts['hold_release'];save()
  print(key,med,med['rc']/med['gc'],counts,flush=True)
assert base['inputs']==A.inputs() and d['compiler_sha256']==A.sha(c)
