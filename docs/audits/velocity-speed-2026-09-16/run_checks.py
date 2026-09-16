import sys,os,json,pathlib,tempfile,shutil,subprocess,time,importlib.util
repo=pathlib.Path('/home/epentland/ai/canopy/mylang')
spec=importlib.util.spec_from_file_location('profile',repo/'scripts/profile_large_project.py');h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
base=pathlib.Path(tempfile.mkdtemp(prefix='mylang-speed-20260916-'));(base/'sources').mkdir();(base/'cwd').mkdir()
info={'scratch':str(base),'source_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'date':'2026-09-16','generator_sha256':h.sha256_file(repo/'scripts/profile_large_project.py'),'machine':subprocess.check_output(['uname','-a'],text=True).strip(),'load_start':os.getloadavg(),'compilers':{}}
zig='/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig'
for mode,tree in [('release','final-release'),('debug','final-debug')]:
 gate=repo.parent/'mylang-worktrees'/tree; dest=base/mode;(dest/'bin').mkdir(parents=True)
 for name in ['mylang','qbe']:shutil.copy2(gate/'zig-out/bin'/name,dest/'bin'/name)
 (dest/'lib').symlink_to(gate/'zig-out/lib');(dest/'bin/zig').symlink_to(zig)
 compiler=dest/'bin/mylang';features=json.loads(subprocess.check_output([str(compiler),'--features'],text=True));info['compilers'][mode]={'path':str(compiler),'binary_sha256':h.sha256_file(compiler),'compiler_identity':features['compiler_sha256'],'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=gate,text=True).strip()}
pathlib.Path('/tmp/mylang-speed-current.json').write_text(json.dumps(info,indent=2))
output=repo/'docs/audits/development-velocity-speed-2026-09-16.json';doc={'provenance':info,'method':{'checks':'Three fresh-cache runs; five no-cache and unchanged runs; 20 unique private edits after warm-up, timed sequentially in fresh processes','cold':'Empty mylang cache; OS page cache is not flushed','clock':'Existing profile_large_project.run_measured: process start to exit','rss':'Direct-child wait4 ru_maxrss; does not cover all native build descendants'},'workloads':[]}
def save():output.write_text(json.dumps(doc,indent=2)+'\n')
def measured(compiler,entry,cache,state):
 flags=['--no-cache'] if state=='no_cache' else ['--cache-dir='+str(cache)]
 r=h.run_measured([compiler,'check-project',str(entry),'--report']+flags,cwd=base/'cwd',timeout=90)
 w=h.extract_work_report(r['stderr']);return {'wall_ms':r['wall_ms'],'peak_rss_kb':r['peak_rss_kb'],'exit':r['exit'],'timed_out':r['timed_out'],'work':w,'stderr':r['stderr'] if r['exit'] else ''}
def summarize(records):return {'summary':h.summarize([r['wall_ms'] for r in records if r['exit']==0 and not r['timed_out']]),'peak_rss_kb':max([r['peak_rss_kb'] for r in records],default=0),'samples':records}
def benchmark(label,mode,family,size=None,source=None):
 compiler=info['compilers'][mode]['path'];root=base/'sources'/(label+'-'+mode)
 if family=='ordinary':
  count,_,_=h.size_ordinary(root,size,64,max(1,size//192));entry,paths=h.generate_ordinary_modules(root,64,count)
  edit=lambda i:h.apply_ordinary_edit(paths,'implementation_edit',1000+i)
 elif family=='managed':
  count,_,_=h.size_managed(root,size,64,max(1,size//192));entry,paths=h.generate_managed(root,64,count)
  edit=lambda i:h.apply_managed_edit(paths,'implementation_edit',1000+i,paths['providers'])
 else:
  entry=h.copy_maintained(repo/source,root);target=h.maintained_edit_target(root);edit=lambda i:h.apply_maintained_edit(target,i)
 originals=h.snapshot_files(list(root.rglob('*.my')));cache=base/'cache'/(label+'-'+mode)
 w={'name':label,'compiler':mode,'family':family,'entry':str(entry),'lines_bytes_files':h.source_lines_and_bytes(root),'states':{}};doc['workloads'].append(w);save();print('START',label,mode,w['lines_bytes_files'],flush=True)
 # Validate generated/maintained source before accepting timing samples.
 valid=measured(compiler,entry,cache,'no_cache');w['validation']=valid;save()
 if valid['exit']!=0:print('REJECT',label,valid['stderr'][:300],flush=True);return
 for state,n in [('no_cache',5),('cold',3),('unchanged',5),('implementation_edit',20)]:
  h.restore_files(originals);records=[]
  if state in ['unchanged','implementation_edit']:w.setdefault('warmups',{})[state]=measured(compiler,entry,cache,'unchanged')
  for i in range(n):
   if state=='cold':shutil.rmtree(cache,ignore_errors=True)
   if state=='implementation_edit':h.restore_files(originals);edit(i)
   row=measured(compiler,entry,cache,state);records.append(row)
   if row['exit']!=0 or row['timed_out']:break
  w['states'][state]=summarize(records);save();s=w['states'][state]['summary'];last=records[-1];print(label,mode,state,'n',s['count'],'median',round(s['median_ms'] or 0,2),'p95',round(s['p95_ms'] or 0,2),'bodies',(last.get('work') or {}).get('checked_bodies'),'exit',last['exit'],flush=True)
 h.restore_files(originals)
for args in [('ordinary-10k','release','ordinary',10000),('ordinary-100k','release','ordinary',100000),('managed-10k','release','managed',10000),('selfhost-prototype','release','maintained',None,'selfhost/prototype/bench.my'),('schematic','release','maintained',None,'src/schematic/guest/main.my'),('ordinary-10k','debug','ordinary',10000)]:benchmark(*args)
doc['provenance']['load_finish']=os.getloadavg();save();print('CHECKS COMPLETE',output,flush=True)
