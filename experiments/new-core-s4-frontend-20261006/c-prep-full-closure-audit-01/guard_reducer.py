#!/usr/bin/env python3
"""Current helper gap under an owned approved Zig/lib copy; no host mutation."""
import hashlib
import json
import os
import shutil
import signal
import subprocess
from pathlib import Path

ROOT=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-frontend')
HERE=ROOT/'experiments/new-core-s4-frontend-20261006/c-prep-full-closure-audit-01'
WORK=ROOT/'.mylang-cache/s4-frontend/c-prep-full-closure-audit-01/guard-reducer'
M=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-project-tests')
ZIG=Path('/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig')
LLVM=ROOT/'experiments/new-core-s4-frontend-20261006/c-prep-e-debug-cwd-01/actual-unit.ll'


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def run(name,argv,env,timeout=180):
    with (HERE/(name+'.stdout')).open('wb') as out,(HERE/(name+'.stderr')).open('wb') as err:
        p=subprocess.Popen(argv,cwd=WORK,env=env,stdout=out,stderr=err,start_new_session=True)
        expired=False
        try:status=p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            expired=True;os.killpg(p.pid,signal.SIGKILL);status=p.wait()
    row={'command':argv,'status':status,'timed_out':expired,'affinity':sorted(os.sched_getaffinity(0))}
    (HERE/(name+'.json')).write_text(json.dumps(row,indent=2)+'\n')
    print(name,status,flush=True)
    assert status==0 and not expired,row
    return row


WORK.mkdir(parents=True)
distribution=WORK/'tool/distribution'
distribution.mkdir(parents=True)
copy=distribution/'zig'
shutil.copy2(ZIG,copy);copy.chmod(0o555)
shutil.copytree(ZIG.parent/'lib',distribution/'lib')
assert sha(copy)==sha(ZIG)
resource=WORK/'tool/lib/clang/22/share/ubsan_ignorelist.txt'
resource.parent.mkdir(parents=True)
assert not resource.exists()
env=os.environ.copy();env['XDG_CACHE_HOME']=str(WORK/'xdg')
env['ZIG_GLOBAL_CACHE_DIR']=str(WORK/'build-global');env['ZIG_LOCAL_CACHE_DIR']=str(WORK/'build-local')
probe=WORK/'guard-probe'
compile_cmd=[str(ZIG),'build-exe','-OReleaseFast','--dep','tool','-Mroot='+str(HERE/'guard_probe.zig'),
             '--dep','core_tool_platform','-Mtool='+str(M/'src/core/tool_identity.zig'),
             '-Mcore_tool_platform='+str(M/'src/config_core_tool_platform.zig'),'-femit-bin='+str(probe)]
run('guard-compile',compile_cmd,env)
run('guard-current',[str(probe),str(copy),str(resource),str(WORK/'helper-cache')],env)
values={}
for line in (HERE/'guard-current.stderr').read_text().splitlines():
    k,v=line.split('=',1);values[k]=v
assert values['unchanged']=='true',values
assert values['before_digest']==values['after_digest'],values
assert values['before_generation']==values['after_generation'],values
private=WORK/'native-after';private.mkdir()
name='canonical-'+sha(LLVM)+'.ll';shutil.copy2(LLVM,private/name)
env['ZIG_GLOBAL_CACHE_DIR']=str(private/'global');env['ZIG_LOCAL_CACHE_DIR']=str(private/'local')
cc=[str(copy),'cc','-c','-O0','-target','x86_64-linux-gnu.2.31','-march=native',
    '-mllvm','-x86-experimental-pref-innermost-loop-alignment=6','-Wno-override-module',
    '-o',str(private/'fresh.o'),str(private/name)]
trace=['strace','-f','-yy','-s','4096','-e','trace=%file,read,pread64,mmap,getdents64,getcwd,close',
       '-o',str(HERE/'guard-native-after.strace')]+cc
run('guard-native-after',trace,env)
records={'classification':'RED: actual production helper accepts changed external compiler input.',
         'helper_sha256':sha(M/'src/core/tool_identity.zig'),'platform_sha256':sha(M/'src/config_core_tool_platform.zig'),
         'tool_copy':str(copy),'tool_sha256':sha(copy),'resource':str(resource),
         'resource_sha256':sha(resource),'values':values,'object_sha256':sha(private/'fresh.o'),
         'probe_sha256':sha(probe),'probe_source_sha256':sha(HERE/'guard_probe.zig'),
         'scope':'No changed-output assertion: proves unchanged/digest/generation omission for a subsequently read external resource.'}
(HERE/'guard-red-summary.json').write_text(json.dumps(records,indent=2)+'\n')
assert str(resource) in (HERE/'guard-native-after.strace').read_text()
