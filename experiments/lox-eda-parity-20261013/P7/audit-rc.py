#!/usr/bin/env python3
import os,pathlib,subprocess,json,hashlib
root=pathlib.Path.cwd();out=root/'experiments/lox-eda-parity-20261013/P7/rc-audit-007';out.mkdir();work=root/'.tmp/lox-eda-parity/P7/rc-audit-007';work.mkdir()
compiler=root/'.tmp/lox-eda-parity/P7/green-install-007/bin/mylang'
text=(root/'src/core/list_exchange_test.zig').read_text();text=text.split('    const fixture =\n',1)[1].split('    ;',1)[0];source=work/'snapshot.my';source.write_text('\n'.join(line.split('\\\\',1)[1] for line in text.splitlines())+'\n')
rows=[]
for mode,flags in [('release',['--release']),('debug',['--unoptimized']),('verified',['--release','--verify-facts'])]:
 binary=work/mode;counts=work/(mode+'.counts.json')
 for name,argv in [('build',[str(compiler),'build',str(source),*flags,'--counters','--cache-dir',str(work/('cache-'+mode)),'--emit-llvm',str(work/(mode+'.ll')),'-o',str(binary)]),('run',[str(binary)])]:
  r=subprocess.run(argv,capture_output=True,env={**os.environ,'MYLANG_JOBS':'4','MYLANG_COUNTERS':str(counts),'MYL_CORE_LEAKCHECK':'1'})
  (out/(mode+'-'+name+'.stdout')).write_bytes(r.stdout);(out/(mode+'-'+name+'.stderr')).write_bytes(r.stderr)
  rows.append({'mode':mode,'phase':name,'argv':argv,'returncode':r.returncode,'counters':json.loads(counts.read_text()) if name=='run' and counts.exists() else None});(out/'results.json').write_text(json.dumps(rows,indent=2)+'\n')
print([(r['mode'],r['phase'],r['returncode']) for r in rows])
