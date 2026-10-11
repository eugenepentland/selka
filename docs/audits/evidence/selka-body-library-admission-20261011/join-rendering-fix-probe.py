from pathlib import Path
import sys,json
sys.path.insert(0,str(Path.cwd()/'selfhost/tests'))
import run_body_library_join as J
work=Path.cwd()/'.tmp/join-rendering-fix';empty=work/'empty';empty.mkdir(exist_ok=True)
original=Path('/home/epentland/.cache/mylang-tmp/selka-selfhost-pilots/b6-library-final-debug-admission-join-exchanges')
host=Path('/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang/zig-out/bin/mylang')
private=original/'fixture-deployment'
report={'scope':'retained authentic join capture replay, hostile plain diagnostic rendering','host_before':J.F.digest(host),'packages_before':J.D.packages(private),'records':[]}
for name,payload in J.mutations((original/'capture-reply-component.bin').read_bytes()[64:]).items():
 path=work/(name+'.bin');path.write_bytes(payload)
 env=J.D.environment('component',private,empty);env['BODY_REPLY']=str(path)
 command=[host,'check-project',original/'join_capture.my','--no-cache','--diagnostics=json']
 result=J.F.execute(command,env,work,600)
 record={'name':name,'command':list(map(str,command)),'payload_sha256':J.F.digest(path),'status':result[0],'stdout':result[1].decode(),'stderr':result[2].decode()};report['records'].append(record)
 print(json.dumps(record),flush=True)
 J.require_rejection(result)
 (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
report['host_after']=J.F.digest(host);report['packages_after']=J.D.packages(private)
J.F.require(report['host_before']==report['host_after'] and report['packages_before']==report['packages_after'],'deployment drift')
(work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
