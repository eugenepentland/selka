#!/usr/bin/env python3
"""Labelled bounded allocation controls; no full-input runtime claims."""
from pathlib import Path
import subprocess,os,json,hashlib,shutil,re
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
WORK=ROOT/'.tmp/lox-eda-improvements/P4/probe'
COMPILER=Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-002/install/bin/mylang')
BASE=Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/experiments/lox-eda-zero-rc-20261012/eda/source/src')
CURRENT=ROOT/'experiments/lox-eda-improvements-20261012/source/eda'
WORK.mkdir(parents=True,exist_ok=True)
baseline_manifest=json.loads((HERE.parent/'source-baseline.json').read_text())['files']
for path in BASE.glob('*.my'):
    assert hashlib.sha256(path.read_bytes()).hexdigest()==baseline_manifest['eda/'+path.name],path
rows=[];builds=[]
env=dict(os.environ, TMPDIR=str(WORK/'tmp'))
(WORK/'tmp').mkdir(exist_ok=True)
for label in ['baseline','traversal-only','full']:
    source=WORK/label
    shutil.copytree(BASE if label=='baseline' else CURRENT,source,dirs_exist_ok=True)
    if label=='traversal-only':shutil.copy2(BASE/'sexpr_parser.my',source/'sexpr_parser.my')
    shutil.copy2(HERE/'bounded-probe.my',source/'p4_probe.my')
    hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(source.glob('*.my'))}
    binary=WORK/(label+'-counted')
    llvm=WORK/(label+'.ll')
    command=[str(COMPILER),'build',str(source/'p4_probe.my'),'--experimental-zero-rc','--release','--verify-facts','--counters','--cache-dir',str(WORK/('cache-'+label)),'--emit-llvm',str(llvm),'-o',str(binary)]
    with (HERE/(label+'-build.log')).open('w') as log:
        result=subprocess.run([str(ROOT/'scripts/build-slot.sh'),'build',*command],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    build={'label':label,'command':command,'returncode':result.returncode,'source_hashes':hashes,'compiler_sha256':hashlib.sha256(COMPILER.read_bytes()).hexdigest()}
    builds.append(build);(HERE/'probe-builds.json').write_text(json.dumps(builds,indent=2)+'\n')
    assert result.returncode==0,label
    ir=llvm.read_text()
    symbols=subprocess.check_output(['nm','--defined-only',str(binary)],text=True)
    rc_pattern=r'(?:myl_core_(?:retain|release)(?:_[A-Za-z0-9_]+)?|myl\.layout\.[0-9]+\.(?:retain|release))'
    build['binary_sha256']=hashlib.sha256(binary.read_bytes()).hexdigest()
    build['llvm_sha256']=hashlib.sha256(llvm.read_bytes()).hexdigest()
    build['rc_named_llvm_call_sites']=len(re.findall(r'call[^\n]*@'+rc_pattern,ir))
    build['rc_named_defined_symbols']=sorted(set(re.findall(rc_pattern,symbols)))
    assert build['rc_named_llvm_call_sites']==0 and not build['rc_named_defined_symbols'],label
    (HERE/'probe-builds.json').write_text(json.dumps(builds,indent=2)+'\n')
    for mode,n in [('width',16),('width',64),('depth',8),('depth',24),('symbols',4),('symbols',16)]:
        name=f'{label}-{mode}-{n}'
        counters=(HERE/(name+'.json')).resolve()
        runenv=dict(env,MYLANG_COUNTERS=str(counters),MYL_CORE_LEAKCHECK='1')
        # Tiny bounded counter runs remain under the normal shared build admission.
        command=[str(binary),mode,str(n)]
        result=subprocess.run([str(ROOT/'scripts/build-slot.sh'),'build','timeout','30',*command],cwd=ROOT,env=runenv,capture_output=True)
        (HERE/(name+'.stdout')).write_bytes(result.stdout);(HERE/(name+'.stderr')).write_bytes(result.stderr)
        expected={'width':3*n+1,'depth':n+1,'symbols':n}[mode]
        assert result.returncode==0 and result.stdout.strip()==str(expected).encode(),(name,result)
        data=json.loads(counters.read_text());t=data['totals']
        assert t['live_bytes_at_exit']==0 and t['runtime_retains']==t['runtime_releases']==t['shared_retains']==t['shared_releases']==0,name
        rows.append({'label':label,'mode':mode,'n':n,'command':command,'output':result.stdout.decode(),'totals':t,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest()})
        (HERE/'probe-summary.json').write_text(json.dumps({'label':'tiny bounded allocation probes; no timing comparison','rows':rows},indent=2)+'\n')
print('18 bounded allocation probes passed')
