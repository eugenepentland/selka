#!/usr/bin/env python3
import hashlib,json,os,pathlib,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[4]
area=root/'experiments/runtime-parity-3-20261009/R'
work=root/'.mylang-cache/rp3/R/nbody-ladder'
work.mkdir(parents=True,exist_ok=True)
assert pathlib.Path(os.readlink('/proc/self/fd/9')).name.startswith('build')
base=root/'.mylang-cache/rp3/ce/bin/base/parity-nbody-plain'
expected=subprocess.check_output([str(base)])
arms=[{'program':'nbody','arm':'mylang-base','argv':[str(base)]}]
for rung in range(3):
    binary=work/str(rung)
    subprocess.run(['zig','cc','-O3','-march=native','-ffp-contract=off',f'-DRUNG={rung}',str(area/'ladders/nbody.c'),'-o',str(binary)],check=True)
    output=subprocess.check_output([str(binary),'5'])
    assert output==expected,(rung,output,expected)
    arms.append({'program':'nbody','arm':f'rung{rung}','argv':[str(binary),'5']})
(work/'arms.json').write_text(json.dumps(arms))
subprocess.run([sys.executable,str(area.parent/'tools/pstat.py'),str(work/'arms.json'),'--rounds','5','--out',str(area/'nbody-ladder-cpu8.json')],check=True)
