#!/usr/bin/env python3
"""Compare the previous kind constant with the repaired native octet helper."""
import hashlib,json,os,re,subprocess
from pathlib import Path
root=Path.cwd(); here=root/'experiments/memory-closeout-20261012/A04/repetition/kind'; scratch=root/'.tmp/memory-closeout/A04/repetition/kind';scratch.mkdir(parents=True,exist_ok=True)
driver=(root/'src/core/driver.zig').read_text().split('pub const runtime_source =',1)[1].split(';',1)[0]
parts=[root/'src/core'/name for name in re.findall(r'@embedFile\("([^\"]+)"\)',driver)]
source='\n'.join(p.read_text() for p in parts)+'\n'+(here/'probe.c').read_text()
assert not (here/'results.json').exists(), 'preserve old evidence'
result={'sources':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in parts},'runs':[]}
for variant,text in [('before',source.replace('block_new(kind_of(source), (int64_t)n + 1, 1)','block_new(MYL_KIND_STR, (int64_t)n + 1, 1)')),('after',source)]:
 for mode,flags in [('ordinary',[]),('zero_rc',['-DMYL_ZERO_RC'])]:
  prefix=scratch/(variant+'-'+mode); cfile=prefix.with_suffix('.c');cfile.write_text(text)
  command=[os.environ['ZIG'],'cc','-O1','-ffunction-sections','-fdata-sections','-Wl,--gc-sections','-pthread',*flags,str(cfile),'-lm','-o',str(prefix)]
  built=subprocess.run(command,capture_output=True,text=True);row={'variant':variant,'mode':mode,'source_sha256':hashlib.sha256(text.encode()).hexdigest(),'build_command':command,'build_status':built.returncode,'build_stderr':built.stderr}
  if not built.returncode:
   ran=subprocess.run([str(prefix)],capture_output=True,text=True);row.update(status=ran.returncode,stdout=ran.stdout,stderr=ran.stderr)
  result['runs'].append(row);print(variant,mode,row.get('status','build failed'),row.get('build_stderr','')[:160],flush=True)
(here/'results.json').write_text(json.dumps(result,indent=2)+'\n')
assert all(r['build_status']==0 and (r['status']!=0 if r['variant']=='before' else r['status']==0) for r in result['runs'])
