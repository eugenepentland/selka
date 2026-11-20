import os,sys,json,pathlib,shutil,importlib.util,time
repo=pathlib.Path('/home/epentland/ai/canopy/mylang');info=json.loads(pathlib.Path('/tmp/mylang-speed-current.json').read_text());base=pathlib.Path(info['scratch']);spec=importlib.util.spec_from_file_location('profile',repo/'scripts/profile_large_project.py');h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
compiler=info['compilers']['release']['path'];zig=str(base/'release/bin/zig');qbe=str(base/'release/bin/qbe');output=repo/'docs/audits/development-velocity-speed-native-2026-09-16.json';doc={'provenance':info,'method':{'clock':'process start to exit; reused existing run_measured helper','guest_mode':'Debug, for the development test/build loop; host compiler ReleaseFast','timeout_seconds':180,'rss':'direct child only, build grandchildren excluded'},'workloads':[]}
def save():output.write_text(json.dumps(doc,indent=2)+'\n')
def measure(args,timeout=180):
 r=h.run_measured(args,cwd=base/'cwd',timeout=timeout);records=[]
 for line in (r['stdout']+'\n'+r['stderr']).splitlines():
  try:records.append(json.loads(line))
  except ValueError:pass
 test=next((j for j in records if j.get('version')=='native-tests-v1'),None);build=next((j for j in records if j.get('version')=='qbe-build-v1'),None)
 row={k:r[k] for k in ['wall_ms','peak_rss_kb','exit','timed_out']};row['command']=[str(x) for x in args]
 if test:row['tests']={k:test.get(k) for k in ['passed','cached','failed','executed','skipped']};row['case_statuses']=[{'name':t['name'],'status':t['status'],'key':t['key']} for t in test['tests']]
 if build:row['build']={k:v for k,v in build.items() if k!='functions'}
 if r['exit']!=0:row['stderr']=r['stderr'][-3500:];row['stdout']=r['stdout'][-1000:]
 return row
def state(w,name,n,args,edit=None):
 records=[]
 for i in range(n):
  if edit:edit(i)
  r=measure(args);records.append(r);w['states'][name]={'summary':h.summarize([r['wall_ms'] for r in records if r['exit']==0]),'samples':records};save()
  if r['exit']!=0:break
 s=w['states'][name]['summary'];print(w['name'],name,'n',s['count'],'median',round(s['median_ms'] or 0,2),'p95',round(s['p95_ms'] or 0,2),'counts',records[-1].get('tests') or records[-1].get('build'),'exit',records[-1]['exit'],flush=True)
 return records[-1]['exit']==0
# Existing 10k fixture: cold native test includes emission/object compilation/link/execution.
root=base/'sources/ordinary-10k-release';entry=root/'main.my';originals=h.snapshot_files(list(root.rglob('*.my')));w={'name':'ordinary-10k-tests','lines_bytes_files':h.source_lines_and_bytes(root),'states':{}};doc['workloads'].append(w);cache=base/'native/ordinary-10k';args=[compiler,'test',str(entry),'--json','--zig',zig,'--qbe',qbe,'--cache-dir',str(cache)];print('START native 10k cold test',flush=True)
if state(w,'cold',1,args):
 state(w,'unchanged',20,args);state(w,'forced',5,args+['--force'])
 def edit(i):
  h.restore_files(originals);h.apply_ordinary_edit({'ordinary_module':root/'m000.my'},'implementation_edit',4000+i)
 state(w,'implementation_edit',20,args,edit)
h.restore_files(originals)
# Compilation of the maintained prototype, without executing its runtime benchmark.
entry=base/'sources/selfhost-prototype-release/bench.my';cache=base/'native/selfhost-build';w={'name':'selfhost-prototype-build','lines_bytes_files':h.source_lines_and_bytes(entry.parent),'states':{}};doc['workloads'].append(w)
args=[compiler,'build',str(entry),'--project','-o',str(base/'prototype-bench'),'--report','--zig',zig,'--qbe',qbe,'--mode','Debug','--cache-dir',str(cache)]
if state(w,'cold',1,args):
 state(w,'unchanged',5,args);original=entry.read_text()
 def edit(i):entry.write_text(original.replace('    line_count = 4000',f'    line_count = {4001+i}'))
 state(w,'implementation_edit',5,args,edit);entry.write_text(original)
# Fixed project, vary selected case count to quantify repeated preparation.
root=base/'sources/test-count';entry,paths=h.generate_ordinary_modules(root,8,32);text=entry.read_text().replace('test_ordinary','probe_original')
for i in range(32):
 name=f'test_a{i:02d}' if i<8 else f'test_b{i-8:02d}';text+=f'\nexport {name}\n\ndef {name}() -> bool effects():\n    return m000.value(1) >= 0\n'
entry.write_text(text);cache=base/'native/test-count';w={'name':'test-count-scaling','lines_bytes_files':h.source_lines_and_bytes(root),'states':{}};doc['workloads'].append(w);args=[compiler,'test',str(entry),'--json','--zig',zig,'--qbe',qbe,'--cache-dir',str(cache)]
# Seed every case once, then compare identical sources and cached receipts.
if state(w,'seed_all_32',1,args):
 for n,pattern in [(1,'*::test_a00'),(8,'*::test_a*'),(32,'*::test_*')]:state(w,f'cached_{n}',5,args+['--filter',pattern])
doc['load_finish']=os.getloadavg();save();print('NATIVE COMPLETE',output,flush=True)
