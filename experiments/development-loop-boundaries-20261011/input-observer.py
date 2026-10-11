#!/usr/bin/env python3
"""Diagnostic observer only; never authorizes coordinator cache evidence."""
import contextlib, datetime, json, os, select, sys, time
from pathlib import Path
root=Path('/home/epentland/.codex/worktrees/selka-selfhost-wave1/mylang')
os.chdir(root)
sys.path.insert(0,str(root/'scripts'))
import verify_cache as v
import verification_snapshot as s

def emit(**entry):
 print(json.dumps(dict(time=datetime.datetime.now(datetime.timezone.utc).isoformat(),**entry)),flush=True)
with contextlib.ExitStack() as stack:
 tools=v.tool_contract(Path('/home/epentland/.local/bin/zig'),v.normalized_environment(root))
 plan=v.inventory(root/'zig-out/verification/inventory.json')
 contracts=[('tools',*tools),('configuration',v.CONFIG_INPUTS+v.COORDINATOR_INPUTS,[]),('sources',v.PREPARE_INPUTS,[]),('artifacts',[],v.artifact_paths(root)),('inputs',sorted({item for g in plan['groups'] for item in g['inputs']}),[])]
 watched={}
 for label,recipes,extras in contracts:
  snap=stack.enter_context(s.Snapshot(root,recipes,extras))
  watcher=snap._watcher
  paths={}
  for path,wd in watcher.paths.items():paths.setdefault(wd,[]).append(str(path))
  watched[watcher.fd]=(label,snap,watcher,paths)
 emit(event='ready',contracts=list(x[0] for x in contracts))
 while True:
  ready,_,_=select.select(list(watched),[],[],5)
  for fd in ready:
   label,snap,watcher,paths=watched[fd]
   while True:
    try:data=os.read(fd,1<<16)
    except BlockingIOError:break
    if not data:raise RuntimeError('observer watch closed')
    at=0
    while at<len(data):
     wd,mask,cookie,length=s._EVENT.unpack_from(data,at);at+=s._EVENT.size
     name=data[at:at+length].split(b'\0',1)[0];at+=length
     watch=watcher.watches.get(wd)
     relevant=bool(mask&(s._Q_OVERFLOW|s._IGNORED|s._DELETE_SELF|s._MOVE_SELF|s._UNMOUNT)) or watch is None or bool(mask&s._MASK and watch.relevant(name,mask))
     if relevant:emit(event='relevant',contract=label,paths=paths.get(wd,[]),name=os.fsdecode(name),mask=hex(mask))
