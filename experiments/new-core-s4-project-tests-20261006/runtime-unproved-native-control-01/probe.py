#!/usr/bin/env python3
"""Actual native-cache control for an unproved environment; no source edits."""
import hashlib, json, os, shutil, signal, subprocess, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
AREA=Path(__file__).resolve().parent
WORK=ROOT/'.mylang-cache/s4-m/runtime-unproved-native-control-01'
WORK.mkdir(parents=True, exist_ok=False)
CORE=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-frontend/.mylang-cache/s4-frontend/c-prep-core-foreign-header-01/mylang-core-corrected')
ZIG=Path('/home/epentland/.local/bin/zig').resolve()

def identity(path):
    return {'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
assert identity(CORE)['sha256']=='d6e4220ad8a833f3d56510eb5958637e25f9c367071949db281d64584d3bface'
env=os.environ.copy()
env.update(CPATH=str(WORK/'headers'), ZIG_GLOBAL_CACHE_DIR=str(WORK/'shared-global'))
(WORK/'headers').mkdir()
(WORK/'app.my').write_text('module app\n\ndef main() -> int:\n    assert False\n    return 0\n')
header=WORK/'headers/unistd.h'
rows=[]

def run(label,argv):
    start=time.monotonic()
    with subprocess.Popen(argv,cwd=WORK,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True) as p:
        try:
            out,err=p.communicate(timeout=300)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid,signal.SIGKILL)
            out,err=p.communicate()
            raise
    (AREA/(label+'.stdout')).write_bytes(out)
    (AREA/(label+'.stderr')).write_bytes(err)
    value={'argv':argv,'status':p.returncode,'seconds':time.monotonic()-start,
           'stdout':identity(AREA/(label+'.stdout')),'stderr':identity(AREA/(label+'.stderr'))}
    (AREA/(label+'.json')).write_text(json.dumps(value,indent=2)+'\n')
    return value

before=None
for value in (7,8):
    header.write_text('#include_next <unistd.h>\n#define _exit(x) _Exit('+str(value)+')\n')
    if before is None:
        before=header.stat()
    else:
        os.utime(header,ns=(before.st_atime_ns,before.st_mtime_ns))
        assert header.stat().st_size==before.st_size and header.stat().st_mtime_ns==before.st_mtime_ns
    shutil.copyfile(header,AREA/('unistd-'+str(value)+'.h.txt'))
    argv=[str(CORE),'build',str(WORK/'app.my'),'-o',str(WORK/'guest'),'--zig',str(ZIG),'--cache-dir',str(WORK/'core-cache')]
    built=run('build-'+str(value),argv)
    row={'expected':value,'header':identity(header),'build':built}
    if built['status']==0:
        row['native']=run('native-'+str(value),[str(WORK/'guest')])
        row['correct']=row['native']['status']==value
    else:
        row['correct']=False
    rows.append(row)
    print(json.dumps(row),flush=True)
summary={'compiler':identity(CORE),'zig':identity(ZIG),'inputs':[identity(WORK/'app.my')],
         'environment':{k:env[k] for k in ('CPATH','ZIG_GLOBAL_CACHE_DIR')},'rows':rows,
         'correct':all(row['correct'] for row in rows),'qualification':False}
(AREA/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
shutil.copyfile(WORK/'app.my',AREA/'app.my.txt')
