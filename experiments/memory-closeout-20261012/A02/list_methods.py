#!/usr/bin/env python3
"""Retain five-mode native and trap evidence for consuming owned-list mutations."""
import argparse, json, os
from pathlib import Path
from qualification_support import (artifact_audit, call, clean_env, counter_audit,
                                   fresh_output, mode_flags, owned_clean, save, sha)

ROOT = Path(__file__).resolve().parents[3]

def run(argv, env=None):
    return call(argv, env=clean_env() if env is None else env, cwd=ROOT, timeout=180)

def main():
    p=argparse.ArgumentParser();p.add_argument('--compiler',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--ownership', choices=['zero','default'], default='zero');args=p.parse_args()
    args.compiler=args.compiler.resolve();args.output=fresh_output(args.output)
    source=ROOT/'src/core/a02_list_methods_fixture.my'
    result=dict(compiler=str(args.compiler),compiler_sha256=sha(args.compiler),source_sha256=sha(source),harness_sha256=sha(__file__),support_sha256=sha(Path(__file__).with_name('qualification_support.py')),ownership=args.ownership,complete=False,qualified=False,modes={})
    save(args.output/'results.json',result)
    for mode, flags in [('release',['--release']),('debug',['--unoptimized']),('verify',['--release','--verify-facts']),('optimized_debug',['--optimize-debug']),('no_facts',['--release','--no-facts'])]:
        directory=args.output/mode;directory.mkdir(exist_ok=True);binary=directory/'program';llvm=directory/'program.ll';counts=directory/'counts.json'
        row=run([args.compiler,'build',source,*mode_flags(args.ownership),'--counters','--cache-dir',args.output/'cache','--zig',os.environ['ZIG'],'--emit-llvm',llvm,'-o',binary,*flags]);result['modes'][mode]=row
        if row['status']==0:
            row.update(artifact_audit(binary,llvm));env=dict(clean_env(),MYLANG_COUNTERS=str(counts),MYL_CORE_LEAKCHECK='1');row['run']=run([binary],env);row.update(counter_audit(counts));row['traps']={name:run([binary,name], dict(clean_env(), MYLANG_COUNTERS=str(directory/(name+'-counts.json')))) for name in ['negative','positive','empty','missing']}
            ir=llvm.read_text();row['methods_present']=all(s in ir for s in ['@myl_core_owned_list_rotate','@myl_core_owned_list_reverse'])
            row['pass']=row['run']['status']==0 and row['run']['stdout']=='500\n' and row['run']['stderr']=='' and owned_clean(row,row) and row['methods_present']
            for name,t in row['traps'].items():
                diagnostic='R_LIST_VALUE' if name=='missing' else 'R_LIST_BOUNDS'
                row['pass'] &= t['status']==1 and diagnostic in t['stderr']
                if name!='missing':
                    idx,length={'negative':(-3,2),'positive':(2,2),'empty':(0,0)}[name]
                    row['pass'] &= f'"operation":"pop","index":{idx},"length":{length}' in t['stderr']
        (args.output/'results.json').write_text(json.dumps(result,indent=2)+'\n');print(mode,row.get('pass',False),flush=True)
    assert sha(args.compiler)==result['compiler_sha256']
    assert sha(source)==result['source_sha256']
    result['complete']=True;result['qualified']=all(row.get('pass',False) for row in result['modes'].values());save(args.output/'results.json',result)
    return 0 if result['qualified'] else 1
if __name__=='__main__':raise SystemExit(main())
