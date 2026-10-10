#!/usr/bin/env python3
"""Read-only M0 LLVM counterfactuals; all binaries and runtime objects are owned."""
import hashlib,json,os,pathlib,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'experiments/runtime-parity-3-20261009/tools'))
import ce,cf,cf_current
assert pathlib.Path(os.readlink('/proc/self/fd/9')).name.startswith('build')
BASE=pathlib.Path('/home/epentland/.cache/mylang/rp3-base-41ed360fb/bin/mylang')
area=ROOT/'experiments/runtime-parity-3-20261009/R'
work=ROOT/'.mylang-cache/rp3/R/base-probes'
work.mkdir(parents=True,exist_ok=True)
runtime=work/'runtime'
env=dict(os.environ,MYLANG_CORE_RUNTIME_CACHE=str(runtime))
programs={'calls':['base','srem'],'intloop':['base','srem'],'sort_quick':['base','checks','norc','checks+norc'],'matmul_tuned':['base','bounds','checks','inline'],'row-result_propagate':['base','no-barrier'],'row-option_handle':['base','no-barrier']}
if len(sys.argv)>1: programs={name:programs[name] for name in sys.argv[1:]}
receipt_name='row-probes' if len(sys.argv)>1 else 'base-probes'
receipts=[]
arms=[]
for name,variants in programs.items():
    local=work/name; local.mkdir(exist_ok=True)
    label=name if name.startswith('row-') else 'parity-'+name
    links=[]
    if name.startswith('row-'):
        source=ce.row_sources()[name.removeprefix('row-')]
        cell=ce.vp3_cells('rows')[name]
        args=[str(cell['size']),str(cell['iterations']),str(ce.row_registry().SEED)]
        if name=='row-option_handle':
            args[0]='64'
            # Match the registered /64 row's calibrated full-work iteration count.
            registry=ce.row_registry(); args[1]=str(registry.UNITS['option_handle'][3])
        links=['--link',str(ROOT/'benchmarks/runtime/ports/native_clock.c')]
    else: source=ROOT/('bench/parity/'+ce.PARITY[name]+'.my');args=[]
    real=local/'real';llvm=local/'original.ll'
    subprocess.run([str(BASE),'build',str(source),'-o',str(real),'--release','--emit-llvm',str(llvm),'--cache-dir',str(local/'cache'),*links],cwd=ROOT,env=env,check=True)
    expected=subprocess.check_output([str(real),*args],cwd=ROOT)
    text=llvm.read_text();objects=sorted(str(o) for o in runtime.glob('*.o') if 'count' not in o.name)
    if links:
        clock=local/'clock.o';subprocess.run(['zig','cc','-c','-O3',links[1],'-o',str(clock)],env=env,check=True);objects.append(str(clock))
    for variant in variants:
        edited=text.replace('  call void asm sideeffect "", "~{memory}"()\n','') if variant=='no-barrier' else cf_current.edit(text,variant)
        if variant=='no-barrier' and edited==text: raise RuntimeError(('empty probe',name,variant))
        ll=local/(variant+'.ll');ll.write_text(edited);obj=local/(variant+'.o');binary=local/(variant+'.exe')
        extra=['-mllvm','-inline-threshold=1000'] if variant=='inline' else []
        subprocess.run(['zig','cc','-c',*cf.ZIG_FLAGS,*extra,'-o',str(obj),str(ll)],env=env,check=True)
        subprocess.run(['zig','cc',*cf.ZIG_FLAGS,'-o',str(binary),*objects,str(obj),'-lm'],env=env,check=True)
        ran=subprocess.run([str(binary),*args],cwd=ROOT,capture_output=True)
        valid=ran.returncode==0 and (ran.stdout.split()[:1]==expected.split()[:1] if name.startswith('row-') else ran.stdout==expected)
        receipt={'program':name,'variant':variant,'binary':str(binary),'arguments':args,'sha256':ce.digest(binary),'llvm_sha256':ce.digest(ll),'status':ran.returncode,'output_matches':valid,'changed_lines':sum(a!=b for a,b in zip(text.splitlines(),edited.splitlines()))}
        receipts.append(receipt)
        if valid: arms.append({'program':name,'arm':variant,'argv':[str(binary),*args]})
        print(name,variant,valid,flush=True)
    (area/(receipt_name+'-receipts.json')).write_text(json.dumps(receipts,indent=1))
(work/'arms.json').write_text(json.dumps(arms))
subprocess.run([sys.executable,str(area.parent/'tools/pstat.py'),str(work/'arms.json'),'--rounds','3','--out',str(area/(receipt_name+'-cpu8.json'))],check=True)
