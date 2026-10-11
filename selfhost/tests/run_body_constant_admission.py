#!/usr/bin/env python3
"""Exact scalar constant source admission through authentic installed schema 11."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import run_body_check_qualification as D

SCHEMA=11
FIXTURES=Path(__file__).with_name('fixtures')/'body_constant_candidate'
COUNTS={'fixtures':158,'success':79,'diagnostic':79}
MODES=('reference','shadow','component')


def selection():
    manifest=json.loads((FIXTURES/'selection.json').read_text())
    D.F.require(len(manifest)==COUNTS['fixtures'],'constant fixture inventory incomplete')
    D.F.require(sum(v['status']==0 for v in manifest.values())==COUNTS['success'],'constant success inventory differs')
    D.F.require(sum(v['status']==1 for v in manifest.values())==COUNTS['diagnostic'],'constant diagnostic inventory differs')
    D.F.require(set(manifest)=={p.name for p in FIXTURES.glob('*.my')},'unselected constant fixture')
    for name,spec in manifest.items():
        D.F.require(Path(name).name==name and name.endswith('.my'),'unsafe constant source name')
        D.F.require(D.F.digest(FIXTURES/name)==spec['source_sha256'],'constant source changed: '+name)
    return manifest


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',type=Path,required=True)
    parser.add_argument('--component-dir',type=Path,required=True)
    parser.add_argument('--zig',type=Path,required=True)
    parser.add_argument('--builder',type=Path,required=True)
    parser.add_argument('--source-root',type=Path,default=D.ROOT)
    parser.add_argument('--report',type=Path,required=True)
    parser.add_argument('--release',action='store_true',help='run optimized guest programs with fact verification')
    args=parser.parse_args()
    manifest=selection()
    dependencies={str(p.relative_to(FIXTURES)):D.F.digest(p) for p in sorted(FIXTURES.rglob("*.my"))}
    before={'compiler_sha256':D.F.digest(args.compiler),'packages':D.packages(args.component_dir,body_schema=SCHEMA)}
    report={'complete':False,'selected_admission':'pending','scope':'general scalar constants and bounded source interpretation; no full compiler/bootstrap claim','body_schema':SCHEMA,'runtime_mode':'release' if args.release else 'normal',**COUNTS,**before,'records':[],'failures':[],'source_selection':manifest,'dependency_sha256':dependencies}
    args.report.parent.mkdir(parents=True,exist_ok=True)
    def save():args.report.write_text(json.dumps(report,indent=2)+'\n')
    save()
    result=D.F.execute([args.builder,'--root',args.source_root,'--zig',args.zig,'--cache-dir',Path('/home/epentland/.cache/mylang/components'),'--seed-only'],D.coordinator_environment(),args.source_root,600)
    report['seed_verification']={'status':result[0],'stdout_hex':result[1].hex(),'stderr_hex':result[2].hex()};save()
    lines=result[1].decode().strip().splitlines()
    D.F.require(result[0]==0 and len(lines)==1 and Path(lines[0]).is_file(),'constant seed receipt verification failed')
    report['qualified_seed_sha256']=D.F.digest(Path(lines[0]))
    D.F.require(report['qualified_seed_sha256']=='c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b','constant seed changed')
    with tempfile.TemporaryDirectory(prefix='constant-admission-') as directory:
        work=Path(directory);empty=work/'empty';empty.mkdir()
        for name,spec in manifest.items():
            entry=FIXTURES/name
            phases=['syntax','check']+(['typed','runtime'] if spec['status']==0 else [])
            for phase in phases:
                if phase=='syntax':command=['dump-syntax',entry]
                elif phase=='check':command=['check-project',entry,'--no-cache','--diagnostics=json']
                elif phase=='typed':command=['dump-typed',entry]
                else:command=['run-project',entry,'--no-cache',*(['--release','--verify-facts'] if args.release else []),'--print-result','--diagnostics=json','--cache-dir',work/'guest-cache',f'--zig={args.zig}']
                outputs=[]
                for mode in MODES:
                    env=D.environment(mode,args.component_dir,empty)
                    if phase=='syntax':env.update(MYLANG_BODY_CHECK_MODE='reference',MYLANG_PARSER_MODE=mode)
                    result=D.F.execute([args.compiler,*command],env,work,600)
                    outputs.append(result)
                    report['records'].append({'name':name,'phase':phase,'mode':mode,'source_sha256':spec['source_sha256'],'command':list(map(str,[args.compiler,*command])),'status':result[0],'stdout_hex':result[1].hex(),'stderr_hex':result[2].hex(),'stdout_sha256':hashlib.sha256(result[1]).hexdigest(),'stderr_sha256':hashlib.sha256(result[2]).hexdigest()});save()
                expected=(spec['status'] if phase=='check' else (8 if name=='source_while.my' else 7) if phase=='runtime' else 0)
                if outputs[0][0]!=expected or not(outputs[0]==outputs[1]==outputs[2]):
                    report['failures'].append({'name':name,'phase':phase});save();print('DIFF',name,phase,flush=True)
                else:
                    D.F.require(phase not in ('syntax','typed') or bool(outputs[0][1]),'empty native frontend oracle')
                    if phase=='runtime':
                        expected_result=8 if name=='source_while.my' else 7
                        D.F.require(outputs[0][1].strip()==str(expected_result).encode(),'native constant runtime changed: '+name)
                    print('exact',name,phase,flush=True)
        D.F.require(before=={'compiler_sha256':D.F.digest(args.compiler),'packages':D.packages(args.component_dir,body_schema=SCHEMA)},'constant deployment changed')
    D.F.require(selection()==manifest,'constant selection changed during replay')
    D.F.require(dependencies=={str(p.relative_to(FIXTURES)):D.F.digest(p) for p in sorted(FIXTURES.rglob("*.my"))},'constant dependency source changed during replay')
    expected=COUNTS['success']*12+COUNTS['diagnostic']*6
    D.F.require(len(report['records'])==expected,'constant operation accounting incomplete')
    report.update(complete=True,operations=expected,failed=len(report['failures']),skipped=0,selected_admission='passed' if not report['failures'] else 'pending');save()
    D.F.require(not report['failures'],'constant selected admission differs from native')
    print('Constant source admission passed:',COUNTS['fixtures'],'fixtures,',expected,'operations')


if __name__=='__main__':main()
