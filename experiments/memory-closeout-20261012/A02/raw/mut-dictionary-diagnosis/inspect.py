import hashlib,json,os,subprocess,time
from pathlib import Path
root=Path.cwd()
evidence=root/'experiments/memory-closeout-20261012/A02/raw/mut-dictionary-diagnosis'
compiler=Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support6-install/bin/mylang')
results={'compiler':str(compiler),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'commands':[]}
for source in ('original','child','root','list-child'):
 for mode,flags in [('check',[]),('dump-ir',[]),('dump-ir-facts',['--facts'])]:
  command=[str(compiler),mode.split('-facts')[0],str(evidence/(source+'.my')),'--experimental-zero-rc',*flags]
  start=time.monotonic()
  p=subprocess.run(command,text=True,capture_output=True,timeout=30)
  stem=source+'-'+mode
  (evidence/(stem+'.stdout')).write_text(p.stdout)
  (evidence/(stem+'.stderr')).write_text(p.stderr)
  results['commands'].append({'source':source,'mode':mode,'command':command,'status':p.returncode,'seconds':time.monotonic()-start})
  (evidence/'inspection.json').write_text(json.dumps(results,indent=2)+'\n')
  print(source,mode,p.returncode,flush=True)
