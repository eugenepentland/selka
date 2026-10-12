import hashlib,json,os,subprocess,time
from pathlib import Path
root=Path.cwd()
evidence=root/'experiments/memory-closeout-20261012/A02/raw/mut-dictionary-diagnosis'
work=root/'.tmp/memory-closeout/A02/mut-dictionary-diagnosis'
compiler=Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support6-install/bin/mylang')
results={'compiler':str(compiler),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'commands':[]}
def call(source,mode,args):
 command=[str(compiler),*args];start=time.monotonic()
 p=subprocess.run(command,text=True,capture_output=True,timeout=30)
 stem=source+'-'+mode
 (evidence/(stem+'.stdout')).write_text(p.stdout);(evidence/(stem+'.stderr')).write_text(p.stderr)
 results['commands'].append({'source':source,'mode':mode,'command':command,'status':p.returncode,'seconds':time.monotonic()-start})
 (evidence/'reductions.json').write_text(json.dumps(results,indent=2)+'\n')
 print(source,mode,p.returncode,flush=True)
 return p.returncode
for source in ('returned-child','returned-list-child','returned-root'):
 file=str(evidence/(source+'.my'))
 call(source,'check',['check',file,'--experimental-zero-rc'])
 call(source,'dump-ir-facts',['dump-ir',file,'--experimental-zero-rc','--facts'])
for source,mode,flags in [('returned-child','release',['--release']),('returned-child','debug',['--unoptimized']),('child','debug',['--unoptimized']),('list-child','debug',['--unoptimized']),('returned-list-child','release',['--release']),('returned-root','release',['--release'])]:
 file=str(evidence/(source+'.my'));binary=work/(source+'-'+mode)
 status=call(source,mode,['build',file,'--experimental-zero-rc','--cache-dir',str(work/'cache'),'--zig',os.environ['ZIG'],*flags,'--counters','--emit-llvm',str(binary)+'.ll','-o',str(binary)])
 if status==0:
  env=os.environ.copy();env['MYLANG_COUNTERS']=str(evidence/(source+'-'+mode+'-counts.json'));env['MYL_CORE_LEAKCHECK']='1'
  p=subprocess.run([str(binary)],env=env,capture_output=True,text=True,timeout=10)
  results['commands'].append({'source':source,'mode':mode+'-run','command':[str(binary)],'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest()})
  (evidence/'reductions.json').write_text(json.dumps(results,indent=2)+'\n')
  print(source,mode+'-run',p.returncode,repr(p.stdout),flush=True)
