#!/usr/bin/env python3
"""Exercise a recursive Option whose boxed payload must survive shell reuse."""
import argparse,importlib.util,json,os,sys
from pathlib import Path
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
spec=importlib.util.spec_from_file_location('qualify',HERE.parent/'zero-rc-closeout-20261011/qualify.py')
q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
p=argparse.ArgumentParser(description=__doc__)
for name in ('compiler','zig','output'):p.add_argument('--'+name,type=Path,required=True)
a=p.parse_args()
for name in ('compiler','zig','output'):setattr(a,name,getattr(a,name).resolve())
a.output.mkdir(parents=True,exist_ok=True)
env=dict(os.environ,ZIG=str(a.zig),MYLANG_ZIG=str(a.zig),MYL_CORE_LEAKCHECK='1')
for name in ('MYLANG_OPTIONS','MYLANG_COUNTERS','MYLANG_CORE_SANITIZE'):env.pop(name,None)
result={}
for mode,flags in q.common.MODES.items():
    result[mode]=q.lane(a,env,'recursive_option',ROOT/'test/core/zero_rc_payload_box.my',['--experimental-zero-rc',*flags],mode,0,'none\n15\n15\n')
    llvm=(a.output/'recursive_option'/mode/'program.ll').read_text()
    assert 'call void @myl_core_box_drop_shell(' in llvm,mode
    print('pass boxed transfer',mode,flush=True)
(HERE/'boxed.json').write_text(json.dumps(result,indent=2)+'\n')
