#!/usr/bin/env python3
"""Immutable corrected M build trace in task-owned caches; no production edit."""
import hashlib
import json
import os
import shutil
import signal
import subprocess
from pathlib import Path

ROOT = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-frontend')
EVIDENCE = ROOT / 'experiments/new-core-s4-frontend-20261006/c-prep-full-closure-audit-01'
WORK = ROOT / '.mylang-cache/s4-frontend/c-prep-full-closure-audit-01'
SOURCE = ROOT / '.mylang-cache/s4-frontend/c-prep-core-foreign-header-01/mylang-core-corrected'
EXPECTED = 'd6e4220ad8a833f3d56510eb5958637e25f9c367071949db281d64584d3bface'
ZIG = Path('/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(name, command, environment, timeout=300):
    with (EVIDENCE / (name+'.stdout')).open('wb') as out, (EVIDENCE / (name+'.stderr')).open('wb') as err:
        process = subprocess.Popen(command, cwd=WORK, env=environment, stdout=out,
                                   stderr=err, start_new_session=True)
        timed_out = False
        try:
            status = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGKILL)
            status = process.wait()
    value = dict(command=command, status=status, timed_out=timed_out)
    (EVIDENCE / (name+'.json')).write_text(json.dumps(value,indent=2)+'\n')
    return value


assert digest(SOURCE) == EXPECTED
WORK.mkdir(parents=True)
compiler = WORK / 'mylang-core'
shutil.copy2(SOURCE, compiler)
compiler.chmod(0o555)
assert digest(compiler) == EXPECTED
(WORK/'app.my').write_text('module app\ndef main() -> int:\n    return 7\n')
shutil.copy2(WORK/'app.my', EVIDENCE/'app.my')
environment = os.environ.copy()
environment['ZIG_GLOBAL_CACHE_DIR'] = str(WORK/'zig-global')
environment['ZIG_LOCAL_CACHE_DIR'] = str(WORK/'zig-local')
environment['XDG_CACHE_HOME'] = str(WORK/'xdg')
argv = [str(compiler), 'build', str(WORK/'app.my'), '-o', str(WORK/'guest'),
        '--emit-llvm', str(WORK/'program.ll'), '--zig', str(ZIG),
        '--cache-dir', str(WORK/'core-cache')]
invocation = dict(command=argv, compiler_sha256=EXPECTED, zig_sha256=digest(ZIG),
                  affinity=sorted(os.sched_getaffinity(0)),
                  environment_overrides={key:environment[key] for key in ('XDG_CACHE_HOME','ZIG_LOCAL_CACHE_DIR','ZIG_GLOBAL_CACHE_DIR')},
                  trace_scope='Full trace is retained privately; curated descendants identify native actions without treating Core helper hashing as compiler consumption.')
(EVIDENCE/'invocation.json').write_text(json.dumps(invocation,indent=2)+'\n')
trace = ['strace','-f','-yy','-s','4096','-e',
         'trace=%file,%process,read,pread64,mmap,getdents64,getcwd,close',
         '-o',str(WORK/'full.strace')]
build = run('build', trace+argv,environment)
assert build['status'] == 0 and not build['timed_out'], build
native = run('native',[str(WORK/'guest')],environment,30)
assert native['status'] == 7 and not native['timed_out'],native
shutil.copy2(WORK/'program.ll',EVIDENCE/'program.ll')
summary = dict(build=build,native=native, compiler_sha256=digest(compiler),
               input_sha256=digest(WORK/'app.my'), llvm_sha256=digest(WORK/'program.ll'),
               executable_sha256=digest(WORK/'guest'), full_trace=dict(path=str(WORK/'full.strace'),
                    size=(WORK/'full.strace').stat().st_size,sha256=digest(WORK/'full.strace')),
               scope='Read-only closure audit; no timing or qualification claim.')
(EVIDENCE/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print('build',build['status'],'guest',native['status'],'trace bytes',summary['full_trace']['size'],flush=True)
