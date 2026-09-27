exec(open('.tmp-mut-argument/scalar-readiness-prototype/validate.py').read().split('for side in sys.argv[1:]:')[0])
path=w/'embedding-final.json'
for side in compilers:
 for backend in ('qbe','llvm'):
  binary=w/('embed-'+side+'-'+backend+'.so');manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());functions={f['name']:f['symbol'] for f in manifest['functions']}
  for mode in range(1,14):
   cmd=[w/'embedding',binary,functions['grow'],functions['heap_frame'],functions['written'],str(mode)];p=run(cmd,60);r={'side':side,'backend':backend,'mode':mode,'command':list(map(str,cmd)),'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr};d['runs'].append(r);save();assert p.returncode==0,r
   counts=[json.loads(x.split(' ',1)[1]) for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')];assert len(counts)==1,r
   r['counts']=counts[0];n=counts[0];assert n['heap_allocate']==n['retire'] and n['owner_acquire']+n['heap_allocate']==n['owner_release'] and n['hold_acquire']==n['hold_release'],r;save();print(side,backend,mode,p.stdout.strip(),flush=True)
