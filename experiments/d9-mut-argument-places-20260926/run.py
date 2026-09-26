"""Replay exact before/after output, direct success and trap cleanup probes."""
import argparse, hashlib, json, re, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--compiler',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--baseline',action='store_true')
    args=parser.parse_args(); compiler=args.compiler.resolve(); rows=[]
    source=ROOT/'tests/lang/mut_argument_places.my'
    text=source.read_text().replace('module mut_argument_places', 'module driver', 1); names=re.findall(r'^public def (test_\w+)\(',text,re.M)
    driver=HERE/'driver.my'
    driver.write_text(text+'\n\ndef main() -> int:\n'+''.join('    assert '+n+'(), "'+n+'"\n' for n in names)+'    return 0\n')
    cases=[('change',ROOT/'experiments/d9-mut-argument-checker-20260926/change.my')]
    if not args.baseline: cases += [('driver',driver),('callee-trap',HERE/'callee_trap.my'),('argument-trap',HERE/'argument_trap.my')]
    for backend in ('qbe','llvm'):
        for mode in ('gc','rc'):
            for name,path in cases:
                cmd=[str(compiler),'build',str(path),'--run','--max-memory=512M']+(['--rc-runtime=stats'] if mode=='rc' else ['--gc-stress'])+(['--release'] if backend=='llvm' else [])
                run=subprocess.run(cmd,cwd=ROOT,text=True,capture_output=True,timeout=360)
                counts=[json.loads(l.removeprefix('MYLANG_RC_COUNTS ')) for l in run.stderr.splitlines() if l.startswith('MYLANG_RC_COUNTS ')]
                row={'backend':backend,'mode':mode,'name':name,'command':cmd,'source_sha256':sha(path),'compiler_sha256':sha(compiler),'exit':run.returncode,'stdout':run.stdout,'stderr':run.stderr,'counts':counts}
                rows.append(row); args.output.write_text(json.dumps(rows,indent=2)+'\n')
                expected=1 if name.endswith('trap') else 0
                assert run.returncode==expected,row
                if name=='change': assert run.stdout==('13\n13\n' if mode=='gc' else '7\n7\n') if args.baseline else run.stdout=='7\n13\n',row
                elif name.endswith('trap'): assert 'R_ASSERT' in run.stderr and 'mut '+('callee' if name=='callee-trap' else 'argument')+' unwind' in run.stderr,row
                if mode=='rc':
                    assert len(counts)==1,row
                    c=counts[0]; assert not c['saturated'],row
                    assert c['heap_allocate']==c['retire'],row
                    assert c['heap_allocate']+c['owner_acquire']==c['owner_release'],row
                    assert c['hold_acquire']==c['hold_release'],row
                print(backend,mode,name,run.returncode,repr(run.stdout),counts,flush=True)

if __name__=='__main__': main()
