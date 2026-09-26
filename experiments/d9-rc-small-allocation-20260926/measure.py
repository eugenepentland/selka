import hashlib,json,statistics,subprocess,sys
from pathlib import Path
p=Path.cwd()/'.tmp-rc/profile'
sha=lambda x:hashlib.sha256(Path(x).read_bytes()).hexdigest()
expected=(p/'rc-n12.stdout').read_text()
arms=sys.argv[1:] or ['drop-before','flat-drop']
report={'source_sha256':sha(p/'binary_trees_n12.my'),'cpu':2,'kind':'private depth12 instruction diagnostic, not corpus acceptance','backends':{}}
for backend in ('qbe','llvm'):
 names={arm:arm+'-'+backend+'-rc-n12' for arm in arms}
 for name in names.values():
  meta=json.loads((p/(name+'.qbe-manifest.json')).read_text())
  assert meta['backend']==backend and meta['lto']==(backend=='llvm'),meta
 rows=[]
 for iteration in range(3):
  for arm in (arms if iteration%2==0 else list(reversed(arms))):
   cmd=['taskset','-c','2','perf','stat','-x,','-e','instructions:u,cycles:u','--',str(p/names[arm])]
   done=subprocess.run(cmd,text=True,capture_output=True,check=True)
   assert done.stdout==expected,(backend,arm,done.stdout)
   counters={f[2]:int(f[0]) for line in done.stderr.splitlines() if len(f:=line.split(','))>2 and f[0].isdigit()}
   rows.append({'arm':arm,'command':cmd,'counters':counters,'stderr':done.stderr,'stdout_sha256':hashlib.sha256(done.stdout.encode()).hexdigest()})
 counts={}
 for arm in arms:
  done=subprocess.run(['taskset','-c','2',str(p/(arm+'-'+backend+'-stats-n12'))],text=True,capture_output=True,check=True)
  assert done.stdout==expected and done.stderr.startswith('MYLANG_RC_COUNTS '),done
  counts[arm]=json.loads(done.stderr.removeprefix('MYLANG_RC_COUNTS '))
 assert all(c==counts[arms[0]] for c in counts.values()),counts
 assert counts[arms[0]]['heap_allocate']==counts[arms[0]]['retire']==669060
 assert counts[arms[0]]['owner_acquire']==19 and counts[arms[0]]['owner_release']==669079
 med={arm:statistics.median(r['counters']['cpu_core/instructions/u'] for r in rows if r['arm']==arm) for arm in names}
 report['backends'][backend]={'medians':med,'improvements':{arm:med[arms[0]]/med[arm] for arm in arms},'counts':counts,'measurements':rows,'binary_sha256':{arm:sha(p/name) for arm,name in names.items()}}
 print(backend,med,report['backends'][backend]['improvements'],flush=True)
report['compiler_sha256']={arm:sha(p/('install-'+arm+'/bin/mylang')) for arm in arms}
report['build_commands']=json.loads((p/'drop-build-commands.json').read_text())
(p/('measure-'+arms[-1]+'.json')).write_text(json.dumps(report,indent=2)+'\n')
