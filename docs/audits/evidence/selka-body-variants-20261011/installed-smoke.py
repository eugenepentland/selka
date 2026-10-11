from pathlib import Path
import hashlib,json,shutil,sys
root=Path('/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang');sys.path.insert(0,str(root/'selfhost/tests'))
import run_body_check_qualification as D
base=Path('/home/epentland/.cache/mylang-tmp/selka-selfhost-pilots');work=base/'b5-installed-smoke';work.mkdir(exist_ok=True)
source=work/'source';source.mkdir(exist_ok=True);empty=work/'empty';empty.mkdir(exist_ok=True)
for path in D.FIXTURES.rglob('*.input'):
 target=source/path.relative_to(D.FIXTURES).with_suffix('.my');target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,target)
compiler=root/'zig-out/bin/mylang';packages=root/'zig-out/libexec/mylang/components'
manifest=json.loads((D.FIXTURES/'manifest.json').read_text());results=[]
for name,spec in manifest.items():
 commands=['check' if spec.get('library') else 'check-project']
 if spec.get('typed') and not spec.get('library'):commands+=['dump-typed','dump-ir']
 for command in commands:
  args=[compiler,command,source/name,'--diagnostics=json']
  reference=D.F.execute(args,D.environment('reference',packages,empty),work)
  for mode in ['component','shadow']:
   actual=D.F.execute(args,D.environment(mode,packages,empty),work)
   if spec['status']==2:
    matched=reference[0]==0 and actual[0]==2 and not actual[1] and b'ComponentProfile' in actual[2]
   else:matched=actual==reference and reference[0]==spec['status']
   record={'source':name,'command':command,'mode':mode,'matched':matched,'expected':spec['status'],'native_status':reference[0],'status':actual[0]}
   if not matched:record.update(stdout=actual[1].decode(),stderr=actual[2].decode(),native_stdout=reference[1].decode(),native_stderr=reference[2].decode());print(json.dumps(record),flush=True)
   results.append(record)
report={'scope':'Installed check/typed/Core smoke; full generated runtime, hostile replies and edit qualification separate.','host_sha256':D.F.digest(compiler),'packages':D.packages(packages),'passed':sum(r['matched'] for r in results),'comparisons':len(results),'cases':results}
(work/'results.json').write_text(json.dumps(report,indent=2)+'\n');print(report['passed'],report['comparisons'],flush=True)
sys.exit(0 if report['passed']==report['comparisons'] else 1)
