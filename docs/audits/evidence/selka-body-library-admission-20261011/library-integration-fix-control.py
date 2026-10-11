from pathlib import Path
import sys,shutil,json
sys.path.insert(0,str(Path.cwd()/'selfhost/tests'));import run_body_library_admission as R
work=Path.cwd()/'.tmp/library-integration-fix';empty=work/'empty';empty.mkdir(exist_ok=True)
R.stage_donors(work)
host=Path('/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang/zig-out/bin/mylang');components=host.parent.parent/'libexec/mylang/components'
out={'host_sha256':R.F.digest(host),'packages':R.D.packages(components),'records':[]}
for stem in ('imported_literal_constants','constant_private_import_error'):
 source=work/(stem+'.my');shutil.copyfile(R.FIXTURES/(stem+'.input'),source)
 for mode in ('reference','shadow','component'):
  result=R.F.execute([host,'check-project',source,'--no-cache','--diagnostics=json'],R.D.environment(mode,components,empty),work,600)
  out['records'].append({'source':stem,'mode':mode,'status':result[0],'stdout':result[1].decode(),'stderr':result[2].decode()});print(stem,mode,result[0],result[2].decode(),flush=True)
(work/'controls.json').write_text(json.dumps(out,indent=2)+'\n')
