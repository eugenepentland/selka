#!/usr/bin/env python3
"""An untimed LLVM marker proves whether the removed inline-free branch executes."""
import json,os,pathlib,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'experiments/runtime-parity-3-20261009/tools'))
import ce,cf
assert pathlib.Path(os.readlink('/proc/self/fd/9')).name.startswith('build')
area=ROOT/'experiments/runtime-parity-3-20261009/R'
work=ROOT/'.mylang-cache/rp3/R/base-probes'
receipts=json.loads((area/'row-probes-receipts.json').read_text())
results=[]
for row in receipts:
    if row['variant']!='base': continue
    local=pathlib.Path(row['binary']).parent
    text=(local/'base.ll').read_text()
    before='  call void asm sideeffect "", "~{memory}"()\n'
    assert text.count(before)==1
    marked=text.replace(before,'  %r5.hit = call i32 @puts(ptr @r5_marker)\n')
    marked+='\n@r5_marker = private constant [12 x i8] c"RP3_BARRIER\\00"\ndeclare i32 @puts(ptr)\n'
    ll=local/'reach.ll';ll.write_text(marked)
    obj=local/'reach.o';binary=local/'reach.exe'
    subprocess.run(['zig','cc','-c',*cf.ZIG_FLAGS,'-o',str(obj),str(ll)],check=True)
    objects=sorted(str(o) for o in (work/'runtime').glob('*.o') if 'count' not in o.name)
    subprocess.run(['zig','cc',*cf.ZIG_FLAGS,'-o',str(binary),*objects,str(local/'clock.o'),str(obj),'-lm'],check=True)
    ran=subprocess.run(['taskset','-c','8',str(binary),*row['arguments']],capture_output=True)
    assert ran.returncode==0
    results.append({'program':row['program'],'arguments':row['arguments'],'status':ran.returncode,'marker_hits':ran.stdout.count(b'RP3_BARRIER'),'stdout':ran.stdout.decode(),'llvm_sha256':ce.digest(ll),'binary_sha256':ce.digest(binary),'binary':str(binary),'note':'Untimed reachability marker; excluded from performance samples.'})
(area/'barrier-reach.json').write_text(json.dumps(results,indent=1))
print(json.dumps(results,indent=1))
