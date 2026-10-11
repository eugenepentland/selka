import json, os, shutil, subprocess
from pathlib import Path
root=Path('/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang')
work=Path('/home/epentland/.cache/mylang-tmp/selka-selfhost-pilots/b4-smoke')
work.mkdir(exist_ok=True); source=work/'sources';source.mkdir(exist_ok=True)
fixtures=root/'selfhost/tests/fixtures/body_check'
for f in fixtures.glob('*.input'):shutil.copy2(f,source/(f.stem+'.my'))
manifest=json.loads((fixtures/'manifest.json').read_text())
base={k:v for k,v in os.environ.items() if not k.startswith(('MYLANG_','BODY_','PILOT_'))}
base.update(MYLANG_COMPONENT_DIR=str(root/'zig-out/libexec/mylang/components'),MYLANG_ZIG='/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig',MYL_CORE_LEAKCHECK='1')
for mode in ('LEXER','PARSER','DECLARATION','TYPE_INTERFACE','BODY_CHECK','TEST_INDEX','CACHE_PLAN'):base['MYLANG_'+mode+'_MODE']='reference'
rows=[];failed=[]
for name,spec in sorted(manifest.items(),key=lambda item:(not item[0].startswith('record_'),item[0])):
    commands=[['check' if spec.get('library') else 'check-project',source/name,'--diagnostics=json']]
    if spec.get('typed') and not spec.get('library'):commands += [['dump-typed',source/name],['dump-ir',source/name]]
    for args in commands:
        results={}
        for mode in ('reference','component','shadow'):
            env=dict(base,MYLANG_BODY_CHECK_MODE=mode)
            proc=subprocess.run([str(root/'zig-out/bin/mylang'),*map(str,args)],env=env,cwd=work,capture_output=True,timeout=90)
            results[mode]=(proc.returncode,proc.stdout,proc.stderr)
        expected=spec['status']
        good=results['reference'][0]==(0 if expected==2 or args[0].startswith('dump') else expected)
        for mode in ('component','shadow'):
            good &= ((results[mode][0]==2 and not results[mode][1] and b'ComponentProfile' in results[mode][2]) if expected==2 else results[mode]==results['reference'])
        key=name+'-'+str(args[0]); rows.append({'name':name,'command':str(args[0]),'passed':good,'status':{m:r[0] for m,r in results.items()}})
        if not good:
            failed.append(key)
            for mode,(status,out,err) in results.items():
                (work/(key+'-'+mode+'.out')).write_bytes(out);(work/(key+'-'+mode+'.err')).write_bytes(err)
            print('FAIL',key,{m:r[0] for m,r in results.items()},flush=True)
        else:print('PASS',key,flush=True)
(work/'results.json').write_text(json.dumps(rows,indent=2)+'\n')
print('SUMMARY',len(rows),'workflows,',len(failed),'failed',flush=True)
raise SystemExit(bool(failed))
