#!/usr/bin/env python3
"""Qualify exact installed guest components and current compiler pure tests."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('source','install','identity','output','zig'):
        parser.add_argument('--'+name,type=lambda value:Path(value).resolve(),required=True)
    args=parser.parse_args()
    if os.environ.get('MYLANG_ADMISSION_KIND'):
        parser.error('this harness acquires one shared build lease per command; do not nest admission')
    args.output.mkdir(parents=True,exist_ok=False)
    identity=json.loads(args.identity.read_text())
    revision=subprocess.check_output(['git','-C',str(args.source),'rev-parse','HEAD'],text=True).strip()
    assert revision==identity['source_revision']
    assert not subprocess.check_output(['git','-C',str(args.source),'status','--porcelain','--untracked-files=all'],text=True).strip()
    sources={str(p.relative_to(args.source)):digest(p) for p in (args.source/'selfhost/components').rglob('*.my')}
    oracles={str(p.relative_to(args.source)):digest(p) for p in (args.source/'selfhost/tests').glob('run_*_component.py')}
    installation=identity['files']
    def intact():
        assert all(digest(args.install/p)==value for p,value in installation.items()),'installed artifact changed'
        assert all(digest(args.source/p)==value for p,value in {**sources,**oracles}.items()),'component source/oracle changed'
    intact()
    saved=args.output/'identities';saved.mkdir()
    shutil.copy2(args.identity,saved/args.identity.name)
    component_dir=args.install/'libexec/mylang/components'
    installed={}
    receipts={}
    for name,folder in [('test-index','test_index'),('cache-plan','cache_plan')]:
        manifest=json.loads((component_dir/(name+'.json')).read_text())
        shutil.copy2(component_dir/(name+'.json'),saved/(name+'-manifest.json'))
        metadata=identity['component_receipts'][name]
        receipt_path=args.identity.parent/metadata['path']
        assert digest(receipt_path)==metadata['sha256']
        shutil.copy2(receipt_path,saved/(name+'-receipt.json'))
        receipt=json.loads(receipt_path.read_text()); receipts[name]=receipt
        assert manifest['memory_mode']=='zero-rc-v1'
        assert receipt['sha256']==manifest['sha256']
        assert manifest['artifact']==Path(manifest['artifact']).name
        installed[name]=component_dir/manifest['artifact']
        assert digest(installed[name])==manifest['sha256']
        for path,expected in receipt['identity']['sources'].items():
            assert digest(args.source/'selfhost/components'/folder/path)==expected,(name,path)
    spec=importlib.util.spec_from_file_location('native_qualification',args.source/'selfhost/test_component_native.py')
    contract=importlib.util.module_from_spec(spec);spec.loader.exec_module(contract)
    environment=dict(os.environ)
    environment.update(MYLANG_ZIG=str(args.zig),MYLANG_CORE_RUNTIME_CACHE='',MYL_CORE_LEAKCHECK='1',
        ZIG_LOCAL_CACHE_DIR=str(args.output/'zig-local'),TMPDIR=str(args.output/'tmp'))
    # Exercise the actual bin/../libexec discovery path of the frozen install.
    environment.pop('MYLANG_COMPONENT_DIR',None)
    (args.output/'tmp').mkdir()
    compiler=args.install/'bin/mylang'; rows=[]
    def run(label,command):
        intact()
        directory=args.output/label;directory.mkdir()
        admitted=[str(args.source/'scripts/build-slot.sh'),'build',*map(str,command)]
        start=time.monotonic()
        completed=subprocess.run(admitted,cwd=args.source,env=environment,capture_output=True)
        (directory/'stdout').write_bytes(completed.stdout);(directory/'stderr').write_bytes(completed.stderr)
        row={'label':label,'argv':admitted,'cwd':str(args.source),'status':completed.returncode,
             'elapsed_including_queue_seconds':time.monotonic()-start,
             'stdout_sha256':digest(directory/'stdout'),'stderr_sha256':digest(directory/'stderr')}
        rows.append(row)
        (directory/'command.json').write_text(json.dumps(row,indent=2)+'\n')
        intact()
        summary={'source_revision':revision,'compiler_sha256':digest(compiler),'installation':installation,
                 'component_sources':sources,'oracle_sources':oracles,'rows':rows,
                 'scope':'Support7 exact installed package and compiler qualification; C2/C3 unchanged',
                 'passed':all(r['status']==0 and r.get('contract_passed',True) for r in rows)}
        (args.output/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
        assert completed.returncode==0,(label,completed.stderr.decode(errors='replace'))
        print(label,'PASS',flush=True)
        return row,completed.stdout
    test_count=0
    for name,folder in [('test-index','test_index'),('cache-plan','cache_plan')]:
        for mode,flags in [('debug',[]),('release',['--release'])]:
            label=f'{name}-{mode}-pure'
            row,output=run(label,[compiler,'test',args.source/f'selfhost/components/{folder}/tests.my',
                '--json','--no-cache','--cache-dir',args.output/(label+'-cache'),'--verify-facts',
                '--experimental-zero-rc',*flags])
            try:
                contract.require_completed_tests(output)
            except Exception:
                row['contract_passed']=False
                (args.output/'results.json').write_text(json.dumps({'source_revision':revision,'rows':rows,'passed':False},indent=2)+'\n')
                raise
            report=json.loads(output);test_count+=report['passed']+report['cached']
            row['test_counts']={key:report[key] for key in ('passed','cached','failed','skipped','unsupported')}
        release=args.output/(name+'-release')
        run(name+'-fresh-release',[compiler,'build',args.source/f'selfhost/components/{folder}/main.my',
            '--release','--verify-facts','--no-cache','--cache-dir',args.output/(name+'-release-cache'),
            '--experimental-zero-rc','-o',release])
        oracle=args.source/f'selfhost/tests/run_{folder}_component.py'
        run(name+'-fresh-protocol',[sys.executable,'-B',oracle,'--component',release])
        run(name+'-installed-protocol',[sys.executable,'-B',oracle,'--component',installed[name]])
        _,symbols=run(name+'-installed-symbols',['nm',installed[name]])
        forbidden=[line for line in symbols.decode().splitlines() if any(line.endswith(' '+word) for word in
            ('myl_core_retain','myl_core_release','myl_core_count_retain','myl_core_count_release','myl_core_share','myl_core_is_unique'))]
        assert not forbidden,forbidden
    final=json.loads((args.output/'results.json').read_text())
    final['rows']=rows;final['pure_test_executions']=test_count
    assert test_count==42,test_count
    final['passed']=True
    (args.output/'results.json').write_text(json.dumps(final,indent=2)+'\n')
    print('PASS',test_count,'pure tests and fresh/installed protocols; installed identities unchanged',flush=True)


if __name__=='__main__':main()
