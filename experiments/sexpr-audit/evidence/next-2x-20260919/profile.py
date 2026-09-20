from pathlib import Path
import subprocess,json,os,statistics,random,sys
w=Path(sys.argv[1]).resolve()
os.sched_setaffinity(0,{6})
commands={'base':[str(w/'census'),str(w/'input.sexp')],'scalar_string':[str(w/'census_scalar'),str(w/'input.sexp')],'no_text_upper_bound':[str(w/'census_no_text'),str(w/'input.sexp')],'zig':[str(w/'bin/zig-bench'),str(w/'input.sexp')],'scan':[str(w/'e_scan'),str(w/'input.sexp')],'scan_once':[str(w/'scan_once'),str(w/'input.sexp')],'render':[str(w/'census'),str(w/'input.sexp'),'--render'],'zig_render':[str(w/'bin/zig-bench'),str(w/'input.sexp'),'--render']}
outputs={k:subprocess.check_output(v) for k,v in commands.items()}
assert outputs['base']==outputs['scalar_string']==outputs['no_text_upper_bound']==outputs['zig']
assert outputs['scan']==outputs['scan_once']
assert outputs['render']==outputs['zig_render']
results={k:[] for k in commands};rng=random.Random(19)
for i in range(7):
 order=list(commands);rng.shuffle(order)
 for name in order:
  r=subprocess.run(['perf','stat','-x,','-e','instructions:u,cycles:u,branches:u,branch-misses:u,task-clock','--',*commands[name]],capture_output=True,text=True,check=True)
  (w/f'perf-{name}-{i}.txt').write_text(r.stderr)
  sample={}
  for line in r.stderr.splitlines():
   parts=line.split(',')
   if len(parts)>2 and parts[0].strip().replace('.','',1).isdigit():sample[parts[2]]=float(parts[0])
  results[name].append(sample)
summary={name:{k:statistics.median(v[k] for v in values) for k in values[0]} for name,values in results.items()}
(w/'counters.json').write_text(json.dumps({'summary':summary,'samples':results},indent=2)+'\n')
print(json.dumps(summary,indent=2),flush=True)
for mode,args in [('census',[]),('render',['--render'])]:
 command='for i in $(seq 1 150); do "$1" "$2" '+('"$3"' if args else '')+' >/dev/null; done'
 subprocess.run(['perf','record','-q','-F','4000','-e','cycles:u','-o',str(w/f'{mode}.perf'),'--','sh','-c',command,'profile',str(w/'census'),str(w/'input.sexp'),*args],check=True)
 report=subprocess.check_output(['perf','report','-i',str(w/f'{mode}.perf'),'--stdio','--no-children','--comms','census','--percent-limit','0.5','--sort','symbol'],text=True)
 manifest=json.loads((w/'census.qbe-manifest.json').read_text())
 for f in manifest['functions']:report=report.replace(f['symbol'],f['name'])
 (w/f'{mode}-profile.txt').write_text(report)
 print(mode,report[:6500],flush=True)
