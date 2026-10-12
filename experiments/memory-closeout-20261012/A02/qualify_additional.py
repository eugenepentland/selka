#!/usr/bin/env python3
"""Preserve original output, property failures and traps through explicit ownership migration."""
import argparse, hashlib, json, os, re, subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
DEFAULT_C0=Path('/home/epentland/ai/canopy/mylang-memory-20261012-A09/.tmp/memory-closeout/A09/C0/bin/mylang')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def call(argv,env):
    p=subprocess.run(list(map(str,argv)),env=env,cwd=ROOT,capture_output=True,text=True,timeout=300)
    return {'argv':list(map(str,argv)),'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr}


def scenarios(name):
    if name=='f2_index':return [[],['all','x'],['next_trap'],['fill_inside'],['shrink_trap'],['loop_shrink','x'],['bump_trap'],['same_length_trap']]
    if name=='ce_appends':return [[],['grow','100000']]
    if name=='rc_lists':return [['a','b']]
    if name=='rc_mut':return [[],['a','b']]
    if name in ('u1_growth','u1_hoist'):return [[],['x']]
    return [[]]


def guest_test_valid(name,row):
    if row['stderr']:return False
    try:r=json.loads(row['stdout'])
    except ValueError:return False
    passed,failed={'b_buffer_values':(2,0),'c_runner_byte_buffer':(2,2),'m_list_methods':(4,4),'v_dynamic_repeat':(1,0),'v_nested_lengths':(1,0),'v_nested_places':(1,0)}[name]
    if row['status']!=(1 if failed else 0) or (r['passed'],r['failed'],r['unsupported'])!=(passed,failed,0):return False
    if name=='m_list_methods':
        return all(s in row['stdout'] for s in ['R_LIST_VALUE','R_LIST_BOUNDS','R_SLICE_STEP','R_LIST_BOUNDS (index -99, length 2)'])
    if name=='c_runner_byte_buffer':
        def named(suffix):return next(x for x in r['tests'] if x['name'].endswith('::'+suffix))
        if any(named(n)['property']['counts']['passed']!=12 for n in ['test_buffer_copy_appends_alone','test_buffers_inside_records_lists_and_options']):return False
        minimal=named('test_short_buffer')['property']['failure']['minimal']['literals']['buffer']
        return minimal=='byte_buffer(b"\\x00\\x00\\x00")' and 'returned Err(byte_buffer(b"\\x00\\x00\\x00"))' in named('test_buffer_error_result')['reason']
    return True


def main():
    p=argparse.ArgumentParser();p.add_argument('--compiler',type=Path,required=True);p.add_argument('--baseline',type=Path,default=DEFAULT_C0);p.add_argument('--output',type=Path,required=True);p.add_argument('--files',nargs='+',required=True);args=p.parse_args();args.output=args.output.resolve();args.output.mkdir(parents=True,exist_ok=True)
    originals=json.loads((HERE/'additional/originals.json').read_text());result={'compiler':str(args.compiler),'compiler_sha256':sha(args.compiler),'baseline':str(args.baseline),'baseline_sha256':sha(args.baseline),'harness_sha256':sha(__file__),'cases':{}}
    for name in args.files:
        old=originals[name];source=ROOT/name;original=HERE/'additional/originals'/name;directory=args.output/source.stem;directory.mkdir(exist_ok=True);entry={'original_sha256':sha(original),'migrated_sha256':sha(source),'lanes':{}};result['cases'][name]=entry
        assert entry['original_sha256']==old['sha256']
        assert re.findall(r'^(?:public )?func (test_\w+)\(',source.read_text(),re.M)==old['test_names']
        for lane,compiler,input_source,flags in [('original',args.baseline,original,[]),('owned',args.compiler,source,['--experimental-zero-rc'])]:
            env=dict(os.environ,MYL_CORE_LEAKCHECK='1');env.pop('MYLANG_COUNTERS',None)
            if old['test_names']:
                row=call([compiler,'test',input_source,*flags,'--release','--json','--seed','7','--property-runs','12','--zig',os.environ['ZIG'],'--cache-dir',args.output/('cache-'+lane)],env)
                row['pass']=guest_test_valid(source.stem,row);entry['lanes'][lane]=row
            else:
                binary=directory/lane;llvm=directory/(lane+'.ll');row=call([compiler,'build',input_source,*flags,'--release','--counters','--zig',os.environ['ZIG'],'--cache-dir',args.output/('cache-'+lane),'--emit-llvm',llvm,'-o',binary],env);entry['lanes'][lane]=row
                if row['status']==0:
                    row['binary_sha256']=sha(binary);row['llvm_sha256']=sha(llvm);row['runs']=[]
                    for i,argv in enumerate(scenarios(source.stem)):
                        counts=directory/(lane+f'-{i}-counts.json');env['MYLANG_COUNTERS']=str(counts);ran=call([binary,*argv],env)
                        if counts.exists():ran['counts']=json.loads(counts.read_text());ran['rc_events']=sum(s['count'] for s in ran['counts']['sites'] if s['kind'] in ['retain','release','release_unique','unique_test','uniqueness']) + sum(ran['counts']['totals'].get(k,0) for k in ['runtime_retains','runtime_releases','shared_retains','shared_releases','share_marks'])
                        row['runs'].append(ran)
                    if lane=='owned':
                        symbols=subprocess.check_output(['nm',str(binary)],text=True);row['symbols_clean']=all(x not in symbols for x in ['myl_core_retain','myl_core_release','myl_core_share'])
        a=entry['lanes']['original'];b=entry['lanes']['owned']
        if old['test_names']:entry['pass']=a.get('pass',False) and b.get('pass',False)
        elif a['status']==0 and b['status']==0:
            entry['pass']=b['symbols_clean']
            for x,y in zip(a['runs'],b['runs']):
                same=x['status']==y['status'] and x['stdout']==y['stdout']
                if x['status']==0:same &= y['stderr']=='' and y['counts']['totals']['live_bytes_at_exit']==0 and y['rc_events']==0
                else:same &= re.findall(r'error\[([^]]+)\]',x['stderr'])==re.findall(r'error\[([^]]+)\]',y['stderr']) and re.findall(r'\{"version":.*',x['stderr'])==re.findall(r'\{"version":.*',y['stderr'])
                y['same_as_original']=same;entry['pass'] &= same
        else:entry['pass']=False
        (args.output/'results.json').write_text(json.dumps(result,indent=2)+'\n');print(name,entry['pass'],flush=True)
    assert sha(args.compiler)==result['compiler_sha256'] and sha(args.baseline)==result['baseline_sha256']
if __name__=='__main__':main()
