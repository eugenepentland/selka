exec(open('.tmp-mut-argument/read-version/validate.py').read().split('for side,c in compilers.items():')[0])
path=w/'embedding.json';d=json.loads(path.read_text()) if path.exists() else {'builds':[],'runs':[]}
for side,c in compilers.items():
 for backend in ('qbe','llvm'):
  source=w/'embed.my';binary=w/f'embed-{side}-{backend}.so'
  if not any(r['side']==side and r['backend']==backend for r in d['builds']):
   cmd=[root/'scripts/build-slot.sh','build',c,'build',source,'--library','--rc-runtime=stats','--backend='+backend,'--mode=ReleaseFast','-o',binary,'--cache-dir='+str(w/('cache-'+side))]
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   p=run(cmd);assert p.returncode==0,p.stderr
   row={'side':side,'backend':backend,'source':str(source),'source_sha256':sha(source),'compiler_sha256':sha(c),'command':list(map(str,cmd)),'stderr':p.stderr,'binary':str(binary),'sha256':sha(binary),'manifest':json.loads(Path(str(binary)+'.qbe-manifest.json').read_text())};d['builds'].append(row);save()
  manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend
  functions={f['name']:f['symbol'] for f in manifest['functions']}
  for mode in range(1,15):
   if any(r['side']==side and r['backend']==backend and r['mode']==mode for r in d['runs']):continue
   cmd=[w/'embedding',binary,*[functions[f] for f in ('fold','fresh','indexed','heap_frame')],str(mode)]
   p=run(cmd,60);r={'side':side,'backend':backend,'mode':mode,'command':list(map(str,cmd)),'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr};d['runs'].append(r);save();assert p.returncode==0,r
   counts=[json.loads(x.split(' ',1)[1]) for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')];assert len(counts)==1,r
   r['counts']=counts[0];n=counts[0];assert n['heap_allocate']==n['retire'] and n['owner_acquire']+n['heap_allocate']==n['owner_release'] and n['hold_acquire']==n['hold_release'],r;save();print(side,backend,mode,p.stdout.strip(),flush=True)
for a in d['runs']:
 if a['side']!='before':continue
 b=next(r for r in d['runs'] if r['side']=='after' and r['backend']==a['backend'] and r['mode']==a['mode'])
 assert a['stdout']==b['stdout'] and a['counts']==b['counts'],(a,b)
print('all 28 pairs exact counts/output/trap code and line')
