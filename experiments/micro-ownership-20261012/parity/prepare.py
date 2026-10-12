#!/usr/bin/env python3
"""Build and qualify under one caller-owned build admission; never time."""
import concurrent.futures, hashlib, json, os, subprocess, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
E=Path(__file__).resolve().parent
W=ROOT/'.tmp/micro-ownership/parity'
COMPILER=Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/lox-eda-20261012/gate-4034-install/bin/mylang')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def build(job):
    name,arm,source,flags,lang=job
    binary=W/'bin'/f'{name}-{arm}'
    cache=W/'cache'/f'{name}-{arm}'
    if lang=='my': cmd=[str(COMPILER),'build',str(source),'--release',*flags,'-o',str(binary),'--cache-dir',str(cache)]
    elif lang=='zig': cmd=[os.environ['ZIG'],'build-exe',source.name,*flags,f'-femit-bin={binary}','--cache-dir',str(cache),'--global-cache-dir',str(W/'cache/global')]
    else: cmd=['/home/epentland/.cargo/bin/rustc','--edition','2021','-C','opt-level=3','-C','codegen-units=1','-C','target-cpu=native','-C','panic=abort',*flags,str(source),'-o',str(binary)]
    r=subprocess.run(cmd,cwd=source.parent,capture_output=True,timeout=1800)
    log=E/'logs'/f'{name}-{arm}.build.log';log.write_bytes(r.stdout+r.stderr)
    d=dict(kernel=name,arm=arm,source=str(source),source_sha256=sha(source),binary=str(binary),command=cmd,build_status=r.returncode,build_log=str(log.relative_to(ROOT)))
    if r.returncode==0:
        d['binary_sha256']=sha(binary)
        if 'count' not in arm:
            start=time.monotonic(); q=subprocess.run([str(binary)],capture_output=True,timeout=600);d['qualification_elapsed_seconds']=time.monotonic()-start
            (E/'logs'/f'{name}-{arm}.stdout').write_bytes(q.stdout);(E/'logs'/f'{name}-{arm}.stderr').write_bytes(q.stderr)
            expected=(E/'expected'/f'{name}.expected').read_bytes()
            d.update(qualification_status=q.returncode,qualified=q.returncode==0 and q.stdout==expected,stdout_sha256=hashlib.sha256(q.stdout).hexdigest(),expected_sha256=hashlib.sha256(expected).hexdigest())
    print(name,arm,d.get('qualified',d['build_status']),flush=True)
    return d
if __name__=='__main__':
    jobs=[]
    for p in sorted((E/'expected').glob('*.expected')):
        n=p.stem
        for arm,folder,flags in [('original-rc','original',[]),('migrated-rc','migrated',[]),('zero-rc','migrated',['--experimental-zero-rc'])]:
            for counted in [False,True]: jobs.append((n,arm+('-count' if counted else ''),E/folder/f'{n}.my',flags+(['--counters'] if counted else []),'my'))
        for arm,flags in [('zig-fast',['-O','ReleaseFast']),('zig-safe',['-O','ReleaseSafe'])]: jobs.append((n,arm,ROOT/'bench/parity/micro'/f'{n}.zig',flags,'zig'))
        jobs.append((n,'rust',ROOT/'bench/parity/micro'/f'{n}.rs',[],'rust'))
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: results=list(pool.map(build,jobs))
    manifest={'compiler':str(COMPILER),'compiler_sha256':sha(COMPILER),'arms':results,'versions':{tool:subprocess.run([tool,'version'] if tool==os.environ['ZIG'] else [tool,'--version'],capture_output=True,text=True).stdout.strip() for tool in [os.environ['ZIG'],'/home/epentland/.cargo/bin/rustc']}}
    (E/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
