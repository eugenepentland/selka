exec(open('.tmp-mut-argument/read-version/validate.py').read().split('for side,c in compilers.items():')[0])
path=w/'accounted.json';d={'rows':[]}
for side,c in compilers.items():
 for backend in ('qbe','llvm'):
  for options in (['--max-steps=1'],['--max-steps=400'],['--max-frames=1']):
   cmd=[root/'scripts/build-slot.sh','build',c,'run',w/'budget.my','--rc-runtime=stats',*options,'--cache-dir='+str(w/('cache-'+side))]
   if backend=='llvm':cmd+=['--release']
   p=run(cmd);r={'side':side,'backend':backend,'options':options,'command':list(map(str,cmd)),'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr};d['rows'].append(r);save();assert p.returncode!=0,r
   counts=[json.loads(x.split(' ',1)[1]) for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')];assert len(counts)==1,r;r['counts']=counts[0]
   n=counts[0];assert n['heap_allocate']==n['retire'] and n['owner_acquire']+n['heap_allocate']==n['owner_release'] and n['hold_acquire']==n['hold_release'],r;save()
   print(side,backend,options,flush=True)
for a in d['rows']:
 if a['side']!='before':continue
 b=next(r for r in d['rows'] if r['side']=='after' and r['backend']==a['backend'] and r['options']==a['options'])
 norm=lambda s:'\n'.join(x for x in s.splitlines() if not x.startswith('build-slot:'))
 assert a['counts']==b['counts'] and norm(a['stderr'])==norm(b['stderr']) and a['status']==b['status'],(a,b)
print('6 accounted failure pairs identical')
