#!/usr/bin/env python3
"""Explicit isolated build and qualification entry point; inherits strict prior helpers."""
import argparse, importlib.util, json, os, pathlib, subprocess, sys, hashlib, re
P=pathlib.Path
HERE=P(__file__).resolve().parent

def sha(p):return hashlib.sha256(P(p).read_bytes()).hexdigest()
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2)+'\n')
def sources(root):return {str(p.relative_to(root)):sha(p) for p in sorted(root.rglob('*')) if p.is_file() and (p.suffix=='.my' or p.name=='mylang.json')}
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('command',choices=['build','qualify','matrix']);p.add_argument('application',choices=['lox','eda'])
    for name in ['root','compiler','install','common-receipt','prior-root']:p.add_argument('--'+name,type=P,required=True)
    p.add_argument('--lox-harness',type=P);p.add_argument('--attempt',required=True);p.add_argument('--source',type=P,required=True)
    a=p.parse_args();root=a.root.resolve();dest=HERE/'attempts'/a.attempt;work=root/'.tmp/lox-eda-parity/P6'/a.attempt/a.application
    common=json.loads(a.common_receipt.read_text());assert common['compiler_sha256']==sha(a.compiler)
    assert P(common['installation']).resolve()==a.install.resolve()
    for entry in common['installation_files']:assert sha(a.install/entry['path'])==entry['sha256']
    previous_path=a.prior_root/'build'/a.application/'build-receipt.json';previous=json.loads(previous_path.read_text())
    if a.command=='build':
        evidence=dest/'build'/a.application;evidence.mkdir(parents=True,exist_ok=False);work.mkdir(parents=True,exist_ok=False)
        original=P(previous['sources']['original']['root']);migrated=a.source.resolve()
        manifests={n:{'root':str(s),'files':sources(s)} for n,s in [('original',original),('migrated',migrated)]}
        assert manifests['original']['files']==previous['sources']['original']['files'], 'original control changed'
        receipt={'application':a.application,'checkout_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'compiler_source_commit':common['source_commit'],'compiler':str(a.compiler),'compiler_sha256':sha(a.compiler),'common_receipt':str(a.common_receipt),'common_receipt_sha256':sha(a.common_receipt),'sources':manifests,'binaries':{},'previous_receipt':str(previous_path),'previous_receipt_sha256':sha(previous_path),'comparison_note':'Fresh candidate/source controls use this compiler; frozen previous combines application and compiler effects.'}
        env=dict(os.environ,MYLANG_JOBS='4',TMPDIR=str(work),MYLANG_COMPONENT_DIR=str(a.install/'libexec/mylang/components'));env.pop('MYLANG_COUNTERS',None);env.pop('MYL_CORE_LEAKCHECK',None)
        for label,source,checked in [('original-rc',original,False),('migrated-rc',migrated,False),('zero-rc',migrated,True)]:
            for counted in [False,True]:
                name=label+('-counted' if counted else '');binary=work/name
                flags=['--release']+(['--experimental-zero-rc'] if checked else [])+(['--counters'] if counted else [])
                for manifest in manifests.values():assert sources(P(manifest['root']))==manifest['files'], 'build inputs changed'
                cmd=[str(a.compiler),'build',str(source/'main.my'),*flags,'--cache-dir',str(work/('cache-'+name)),'-o',str(binary)]
                if checked and not counted:cmd+=['--emit-llvm',str(work/'zero-rc.ll')]
                with (evidence/(name+'.log')).open('w') as log:r=subprocess.run([str(root/'scripts/build-slot.sh'),'build',*cmd],cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT)
                entry={'path':str(binary),'status':'ok' if r.returncode==0 else 'build_failed','returncode':r.returncode,'command':cmd,'flags':flags,'counted':counted,'checked_ownership':checked,'source':'migrated' if source==migrated else 'original'}
                if r.returncode==0:
                    entry['sha256']=sha(binary);binary.chmod(0o555)
                    if checked and not counted:entry['llvm']={'path':str(work/'zero-rc.ll'),'sha256':sha(work/'zero-rc.ll')}
                for manifest in manifests.values():assert sources(P(manifest['root']))==manifest['files'], 'build inputs changed'
                receipt['binaries'][name]=entry;save(evidence/'build-receipt.json',receipt);assert r.returncode==0
        # Optional same-compiler previous checked control makes compiler and application changes distinguishable.
        old_source=P(previous['sources']['migrated']['root']);old_files=sources(old_source)
        assert old_files==previous['sources']['migrated']['files']
        cmd=[str(a.compiler),'build',str(old_source/'main.my'),'--release','--experimental-zero-rc','--cache-dir',str(work/'before-cache'),'-o',str(work/'before-same-compiler')]
        with (evidence/'before-same-compiler.log').open('w') as log:r=subprocess.run([str(root/'scripts/build-slot.sh'),'build',*cmd],cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT)
        assert sources(old_source)==old_files
        receipt['before_same_compiler']={'command':cmd,'status':'ok' if r.returncode==0 else 'build_failed','returncode':r.returncode,'source_root':str(old_source),'sources':old_files,'path':str(work/'before-same-compiler')}
        if r.returncode==0:receipt['before_same_compiler']['sha256']=sha(work/'before-same-compiler')
        save(evidence/'build-receipt.json',receipt);save(dest/'build'/(a.application+'-selected.json'),{'path':str(evidence/'build-receipt.json'),'sha256':sha(evidence/'build-receipt.json')});return
    # Private copies let existing subprocess helpers write only this attempt's destinations.
    helper_hashes={}
    error_work=root/'.tmp/lox-eda-parity/P6'/a.attempt/'eda/error-paths'
    for name in ['receipts.py','qualify_goldens.py','check-error-paths.py']:
        target=dest/name
        adapted=(a.prior_root/name).read_text().replace("workspace/'.tmp/lox-eda-improvements-20261012/eda/error-paths'", "pathlib.Path("+repr(str(error_work))+")").replace("ROOT = HERE.parents[1]", 'ROOT = Path('+repr(str(root))+')')
        if target.exists():assert target.read_text()==adapted, 'qualification helper changed'
        else:target.write_text(adapted)
        helper_hashes[str(target)]=sha(target)
    save(dest/'adapted-helpers.json',helper_hashes)
    sys.path.insert(0,str(dest))
    source=(a.prior_root/(a.command+'.py')).read_text()
    if a.command=='qualify' and a.application=='lox':
        assert a.lox_harness and a.lox_harness.exists(), 'provide recovered pinned Lox harness/corpus'
        source=source.replace('/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/harness/lox_bench.py',str(a.lox_harness.resolve()))
    inventory=[]
    for path in sorted(a.source.rglob('*.my')):
        for match in re.finditer(r'^\s*(?:public\s+)?func\s+(test_[A-Za-z0-9_]+)\s*\(',path.read_text(),re.M):inventory.append(str(path.relative_to(a.source))+':'+match.group(1))
    assert inventory, 'no test declarations found'
    save(dest/(a.application+'-declaration-inventory.json'),{'declarations':inventory,'sources':sources(a.source),'count':len(inventory)})
    source=source.replace('75 if app == \'lox\' else 317',str(len(inventory)))
    source=source.replace("ROOT = Path(__file__).resolve().parents[2]",'ROOT = Path('+repr(str(root))+')')
    source=source.replace("HERE = Path(__file__).resolve().parent",'HERE = Path('+repr(str(dest))+')')
    source=source.replace("HERE / 'P1/verify.py'",'Path('+repr(str(a.prior_root/'P1/verify.py'))+')')
    # Keep the actual adapted driver reviewable and reproducible. Each application
    # has a different test inventory, so it needs its own driver identity.
    driver=dest/(a.command+'-'+a.application+'.py')
    if driver.exists():assert driver.read_text()==source, 'qualification driver changed'
    else:driver.write_text(source)
    module={'__name__':'isolated_'+a.command,'__file__':str(driver)};exec(compile(source,module['__file__'],'exec'),module)
    sys.argv=[module['__file__'],str(dest/'build'/a.application/'build-receipt.json') if a.command=='qualify' else a.application,'--work-root',str(work/a.command)]
    module['main']()
if __name__=='__main__':main()
