#!/usr/bin/env python3
"""Retain five-mode native and trap evidence for consuming owned-list mutations."""
import argparse, hashlib, json, os, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def run(argv, env=None):
    p = subprocess.run(list(map(str, argv)), capture_output=True, text=True, env=env, cwd=ROOT, timeout=180)
    return dict(status=p.returncode, stdout=p.stdout, stderr=p.stderr, argv=list(map(str, argv)))

def main():
    p=argparse.ArgumentParser();p.add_argument('--compiler',type=Path,required=True);p.add_argument('--output',type=Path,required=True);args=p.parse_args()
    args.output=args.output.resolve();args.output.mkdir(parents=True,exist_ok=True)
    source=ROOT/'src/core/a02_list_methods_fixture.my'
    result=dict(compiler=str(args.compiler),compiler_sha256=sha(args.compiler),source_sha256=sha(source),harness_sha256=sha(__file__),modes={})
    for mode, flags in [('release',['--release']),('debug',['--unoptimized']),('verify',['--release','--verify-facts']),('optimized_debug',['--optimize-debug']),('no_facts',['--release','--no-facts'])]:
        directory=args.output/mode;directory.mkdir(exist_ok=True);binary=directory/'program';llvm=directory/'program.ll';counts=directory/'counts.json'
        row=run([args.compiler,'build',source,'--experimental-zero-rc','--counters','--cache-dir',args.output/'cache','--zig',os.environ['ZIG'],'--emit-llvm',llvm,'-o',binary,*flags]);result['modes'][mode]=row
        if row['status']==0:
            row.update(binary_sha256=sha(binary),llvm_sha256=sha(llvm));env=dict(os.environ,MYLANG_COUNTERS=str(counts),MYL_CORE_LEAKCHECK='1');row['run']=run([binary],env);row['counts']=json.loads(counts.read_text());row['traps']={name:run([binary,name], dict(os.environ, MYLANG_COUNTERS=str(directory/(name+'-counts.json')))) for name in ['negative','positive','empty','missing']}
            ir=llvm.read_text();row['llvm_clean']=all(s not in ir for s in ['@myl_core_retain','@myl_core_release','@myl_core_share(','@myl_core_free_block(']);row['methods_present']=all(s in ir for s in ['@myl_core_owned_list_rotate','@myl_core_owned_list_reverse'])
            symbols=run(['nm',binary])['stdout'];row['symbols_clean']=all(s not in symbols for s in ['myl_core_retain','myl_core_release','myl_core_share'])
            row['pass']=row['run']['status']==0 and row['run']['stdout']=='500\n' and row['run']['stderr']=='' and row['counts']['totals']['live_bytes_at_exit']==0 and row['llvm_clean'] and row['symbols_clean'] and row['methods_present']
            for name,t in row['traps'].items():
                diagnostic='R_LIST_VALUE' if name=='missing' else 'R_LIST_BOUNDS'
                row['pass'] &= t['status']==1 and diagnostic in t['stderr']
                if name!='missing':
                    idx,length={'negative':(-3,2),'positive':(2,2),'empty':(0,0)}[name]
                    row['pass'] &= f'"operation":"pop","index":{idx},"length":{length}' in t['stderr']
        (args.output/'results.json').write_text(json.dumps(result,indent=2)+'\n');print(mode,row.get('pass',False),flush=True)
    assert all(row.get('pass') for row in result['modes'].values())
    assert sha(args.compiler)==result['compiler_sha256']
if __name__=='__main__':main()
