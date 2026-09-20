#!/usr/bin/env python3
"""Benchmark-scope golden/error/GC checks, NOT a full backend qualification."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--work',required=True)
    p.add_argument('--out',required=True)
    a=p.parse_args();work=Path(a.work)
    arms={'qbe':Path('/tmp/final-measure/qbe'),'original-llvm':Path('/tmp/final-measure/llvm-o2')}
    arms.update({x.stem:x for x in sorted(work.glob('*.bin'))})
    fixtures={n:Path(f) for n,f in (line.split('\t') for line in Path('experiments/sexpr-port/golden/manifest.tsv').read_text().splitlines())}
    special=work/'fixtures';special.mkdir(exist_ok=True)
    for name,raw in {'unicode':'(café "λ漢字😀" "a\\\"b")'.encode(), 'unterminated':b'(foo "oops',
                     'close':b')','unclosed':b'(a','empty':b'', 'invalid-utf8':b'("\xff")',
                     'numbers':b'(0 -1 1.25 100nF 3.3V 10mil 1mm 10mA 2%)'}.items():
        file=special/(name+'.sexp');file.write_bytes(raw);fixtures[name]=file
    report={'cases':[], 'arms':{n:{'path':str(b),'sha256':hashlib.sha256(b.read_bytes()).hexdigest()} for n,b in arms.items()}}
    for name,file in fixtures.items():
        for render in [False,True]:
            args=[str(file)]+(['--render'] if render else [])
            ref=subprocess.run([str(arms['qbe']),*args],capture_output=True,timeout=30)
            for arm,b in arms.items():
                for stress in ([False,True] if file.stat().st_size<2000 else [False]):
                    done=subprocess.run([str(b),*(['--gc-stress'] if stress else []),*args],capture_output=True,timeout=30)
                    ok=(done.returncode,done.stdout,done.stderr)==(ref.returncode,ref.stdout,ref.stderr)
                    golden=Path('experiments/sexpr-port/golden')/(name+'.txt')
                    if render and golden.exists():
                        ok=ok and done.returncode==0 and done.stdout==golden.read_bytes()+b'\n'
                    report['cases'].append({'arm':arm,'fixture':name,'render':render,'stress':stress,'match':ok,'status':done.returncode,
                                            'stdout_sha256':hashlib.sha256(done.stdout).hexdigest(),'stderr':done.stderr.decode('utf8','replace')})
                    if not ok: print('MISMATCH',arm,name,render,stress,flush=True)
    report['passed']=sum(c['match'] for c in report['cases']);report['total']=len(report['cases'])
    Path(a.out).write_text(json.dumps(report,indent=2)+'\n')
    print(report['passed'],'/',report['total'])
    if report['passed']!=report['total']:raise SystemExit(1)


if __name__=='__main__':main()
