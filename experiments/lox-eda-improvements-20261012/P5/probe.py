#!/usr/bin/env python3
"""Tiny labelled overlap counters/oracle, never full benchmark timing."""
import json, hashlib, shutil, subprocess, os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
WORK=ROOT/'.tmp/lox-eda-improvements/P5'
COMPILER=Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-002/install/bin/mylang')
MAIN='''
func probe_case(out: Stream, n: int, step: int, width: int, height: int, shift: int):
    mut items: Item[] = []
    for i in range(n):
        items.append(Item(box=Box(x0=shift+i*step, y0=shift, x1=shift+i*step+width, y1=shift+height), kind=Kind.caption, text=str(i).encode()+b"LONG_TEXT"))
    mut report = overlaps_of(items)
    mut a = -1
    mut b = -1
    match report.first:
        case Some(pair):
            out.print(f"{n},{step},{width},{height},{shift}:{report.texts},{report.overlaps}:{strs.text(pair.a)},{strs.text(pair.b)}:{pair.x},{pair.y}")
        case None:
            out.print(f"{n},{step},{width},{height},{shift}:{report.texts},{report.overlaps}:none")

func main(args: str[], out: Stream) -> int:
    mut n = 64
    if len(args) > 1 and args[1] == "128":
        n = 128
    probe_case(out, 0, 0, 100, 100, 0)
    probe_case(out, 1, 0, 100, 100, 0)
    probe_case(out, 4, 0, 100, 100, -250)
    probe_case(out, 4, 90, 100, 100, -250)
    probe_case(out, 4, 89, 100, 100, -250)
    probe_case(out, 4, 0, 100, 10, 0)
    probe_case(out, n, 1000, 100, 100, -250)
    probe_case(out, n, 0, 100, 100, -250)
    return 0
'''
def oracle(output):
    for line in output.splitlines():
        config,counts,*pair=line.split(':')
        n,step,width,height,shift=map(int,config.split(','))
        hits=[(i,j) for i in range(n) for j in range(i+1,n) if width-(j-i)*step>10 and height>10]
        expected=f'{n},{len(hits)}'
        assert counts==expected,(line,expected)
        if hits:
            i,j=hits[0]
            assert pair==[f'{i}LONG_TEXT,{j}LONG_TEXT',f'{shift+j*step},{shift}'],line
        else: assert pair==['none'],line

def main():
    import argparse
    ap=argparse.ArgumentParser(); ap.add_argument('phase'); ap.add_argument('--source',type=Path)
    a=ap.parse_args(); target=WORK/a.phase; target.mkdir(parents=True,exist_ok=True)
    src=ROOT/'experiments/lox-eda-improvements-20261012/source/eda'
    for p in src.glob('*.my'): shutil.copy2(p,target/p.name)
    source=a.source or src/'kicad_sch_textbox.my'
    snapshot=source.read_bytes()
    (target/'kicad_sch_textbox.my').write_text(snapshot.decode()+MAIN)
    env=dict(os.environ,TMPDIR=str(WORK/'tmp'))
    (WORK/'tmp').mkdir(exist_ok=True)
    cmd=[str(ROOT/'scripts/build-slot.sh'),'build',str(COMPILER),'build',str(target/'kicad_sch_textbox.my'),'--release','--experimental-zero-rc','--counters','--cache-dir',str(target/'cache'),'-o',str(target/'probe')]
    with (HERE/(a.phase+'-build.log')).open('w') as f: rc=subprocess.run(cmd,cwd=ROOT,env=env,stdout=f,stderr=subprocess.STDOUT).returncode
    receipt={'command':cmd,'build_status':rc,'compiler_sha256':hashlib.sha256(COMPILER.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256(snapshot).hexdigest(),'label':'tiny bounded overlap probe; no runtime claims'}
    if rc==0:
        for n in (64,128):
            counter=HERE/f'{a.phase}-{n}-counters.json'; env.update(MYLANG_COUNTERS=str(counter),MYL_CORE_LEAKCHECK='1')
            run=subprocess.run([str(ROOT/'scripts/build-slot.sh'),'build','timeout','30',str(target/'probe'),'unused',str(n)],cwd=ROOT,env=env,text=True,capture_output=True)
            (HERE/f'{a.phase}-{n}-output.txt').write_text(run.stdout+run.stderr)
            assert run.returncode==0,run.stderr
            oracle(run.stdout)
            receipt[str(n)]={'status':run.returncode,'oracle':'pass'}
    (HERE/(a.phase+'-receipt.json')).write_text(json.dumps(receipt,indent=2)+'\n')
    assert rc==0,rc
if __name__=='__main__': main()
