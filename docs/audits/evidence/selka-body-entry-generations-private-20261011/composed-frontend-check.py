from pathlib import Path
import hashlib,json,sys
root=Path('/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang')
sys.path.insert(0,str(root/'selfhost/tests'))
import run_frontend_qualification as F
import run_body_check_qualification as D
source=Path('/home/epentland/ai/canopy/.selka-agent-cache/lexer-b7/source')
prefix=Path('/home/epentland/ai/canopy/.selka-agent-cache/lexer-b7/prefix')
work=Path('/home/epentland/ai/canopy/.selka-agent-cache/bootstrap-20261011/tmp/b7-composed-frontend-check')
work.mkdir(exist_ok=False);empty=work/'empty';empty.mkdir()
components=prefix/'libexec/mylang/components';compiler=prefix/'bin/mylang'
def identity():
 packages=D.packages(components,body_schema=7)
 files={str(p.relative_to(source)):F.digest(p) for p in sorted((source/'selfhost/components').rglob('*')) if p.is_file() and not any(part.startswith('.') for part in p.relative_to(source/'selfhost/components').parts)}
 return {'host':F.digest(compiler),'packages':packages,'sources':files}
report={'scope':'Private B7 seven-component composed frontend diagnostic checks; no build/generation/performance claim','identity':identity(),'records':[],'complete':False}
def checkpoint(): (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
checkpoint()
entries=['body_check/main.my','test_index/main.my','cache_plan/main.my','lexer_pilot/main.my','parser_pilot/full_adapter.my','declaration_index/main.my','type_interface/main.my']
for entry in entries:
 command=[compiler,'check',source/'selfhost/components'/entry,'--no-cache','--diagnostics=json']
 results={}
 for mode in ['reference','component']:
  env=D.environment(mode,components,empty)
  for name in ['LEXER','PARSER','DECLARATION','TYPE_INTERFACE','BODY_CHECK','TEST_INDEX','CACHE_PLAN']:env['MYLANG_'+name+'_MODE']=mode
  result=F.execute(command,env,work,600)
  results[mode]=result
  report['records'].append({'entry':entry,'mode':mode,'command':list(map(str,command)),'status':result[0],'stdout_hex':result[1].hex(),'stderr_hex':result[2].hex()});checkpoint()
 print(entry,results['reference'][0],results['component'][0],results['reference']==results['component'],flush=True)
report['unchanged']=identity()==report['identity']
report['complete']=True
report['exact']=sum(report['records'][i]['status']==report['records'][i+1]['status']==0 and report['records'][i]['stdout_hex']==report['records'][i+1]['stdout_hex'] and report['records'][i]['stderr_hex']==report['records'][i+1]['stderr_hex'] for i in range(0,len(report['records']),2))
checkpoint()
sys.exit(0 if report['exact']==7 and report['unchanged'] else 1)
