#!/usr/bin/env python3
"""One fresh per-arm native compile diagnostic; ordinary admission, not app timing."""
import hashlib,json,os,pathlib,subprocess,time
root=pathlib.Path.cwd();out=root/'experiments/lox-eda-parity-20261013/P2/reader-inline-001';work=root/'.tmp/lox-eda-parity/P2/reader-inline-001';r=json.loads((out/'receipt.json').read_text());assert os.environ['MYLANG_ADMISSION_KIND']=='build';zig=next(p for p in r['inputs'] if p.endswith('/zig'));rows=[]
for arm in ['baseline','inline']:
 ll=work/(arm+'.ll');assert hashlib.sha256(ll.read_bytes()).hexdigest()==r['binaries'][arm]['llvm_sha256'];private=work/'cost-001'/arm;private.mkdir(parents=True);env={**os.environ,'ZIG_LOCAL_CACHE_DIR':str(private/'local'),'ZIG_GLOBAL_CACHE_DIR':str(private/'global')};metrics=private/'time.txt';obj=private/'candidate.o';argv=[zig,'cc','-c','-O3',*r['native_flags'],'-Wno-override-module','-o',str(obj),str(ll)]
 p=subprocess.run(['/usr/bin/time','-f','%e %U %S %M','-o',str(metrics),*argv],capture_output=True,env=env,timeout=120);(out/(arm+'.cost.stderr')).write_bytes(p.stderr);assert p.returncode==0,p.stderr
 vals=metrics.read_text().split();rows.append({'arm':arm,'argv':argv,'fresh_private_cache':str(private),'wall_seconds':float(vals[0]),'user_seconds':float(vals[1]),'system_seconds':float(vals[2]),'maxrss_kib':int(vals[3]),'llvm_sha256':hashlib.sha256(ll.read_bytes()).hexdigest(),'object_sha256':hashlib.sha256(obj.read_bytes()).hexdigest()});(out/'compile-cost.json').write_text(json.dumps({'label':'single fresh native compile pair; diagnostic, not repeatable compiler benchmark','script_sha256':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),'samples':rows},indent=2)+'\n')
print('fresh compile diagnostics completed')
