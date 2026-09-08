"""Freeze validated velocity tools, baselines, capability readiness and public guides."""
import sys,json,shutil,re,hashlib
from pathlib import Path
from datetime import datetime,timezone
sys.path.insert(0,'/home/epentland/ai/canopy/mylang')
from experiments.application_comparison import dependency_audit,trial_configuration,parity_readiness,iteration_log
from experiments.application_comparison.storage import write_json,path_identity
R=Path(__file__).parent;REPO=Path('/home/epentland/ai/canopy/mylang');H=REPO/'experiments/application_comparison'
validation=REPO/'experiments/validation/velocity-v1'
log=(validation/'final-test-install.log').read_text()
assert re.search(r'Build Summary: (\d+)/\1 steps succeeded',log),'final suite must finish successfully before freeze'
assert (validation/'application-harness.log').exists(),'application harness validation required'
assert '\nOK\n' in (validation/'application-harness.log').read_text(),'application harness must pass'
(R/'toolchain/bin').mkdir(parents=True)
for name in ('mylang','mylang-io'):shutil.copy2(REPO/'zig-out/bin'/name,R/'toolchain/bin'/name)
workflow=R/'toolchain/workflow';workflow.mkdir()
for name in ('project.py','navigate.py','verify.py'):shutil.copy2(REPO/'scripts'/name,workflow/name)
shutil.copytree(REPO/'scripts/verification',workflow/'verification',ignore=shutil.ignore_patterns('__pycache__'))
(R/'baselines').mkdir()
for app in ('eda','planner'):
 shutil.copytree(H/'baselines'/app/'my',R/'baselines'/app,ignore=shutil.ignore_patterns('__pycache__'))
 cfg=trial_configuration.freeze('my',app,'main',byte_io=R/'toolchain/bin/mylang-io',compiler=R/'toolchain/bin/mylang',navigate=workflow/'navigate.py',workflow=workflow)
 write_json(R/(app+'-configuration.json'),cfg)
modules={p.stem:p.read_bytes() for p in (REPO/'src/stdlib').glob('std_*.my')}
dep={}
for app in ('eda','planner'):
 for language in ('my','python','zig'):
  entry='main.my' if language=='my' else 'src/main.zig' if language=='zig' else 'inspector.py' if app=='eda' else 'planner.py'
  dep[app+':'+language]=dependency_audit.audit(H/'baselines'/app/language,language,entry,standard_modules=modules if language=='my' else None)
  assert not dep[app+':'+language]['review_required']
write_json(validation/'dependencies.json',dep)
reference=['standard-library.md','stdlib-application-parity.md','borrow-syntax.md','experiments/plain-json-ergonomics.md','experiments/callbacks.md']
(R/'library-guide.md').write_text('\n\n'.join((REPO/'docs'/name).read_text() for name in reference))
(R/'workflow-guide.md').write_text('''Optional combined feedback (source context + declared tests):
/usr/bin/python3 -B /tools/workflow/project.py --compiler /tools/compiler --entry /work/main.my --manifest /work/verify.json --query validate --cache-dir /cache/project --report /cache/attempt-001.json
Use --only 'cli*' for a short existing-contract check; the full planner manifest also includes resource-bound tests. Add meaningful tests for the requested behavior. This optional workflow does not replace the trusted gateway check required to seal.
Use a new report name for each invocation. Each command has its own /cache, retained by the coordinator after execution; no cache is reused across commands. Keep generated artifacts out of /work so source identity remains stable. Direct tool argv is counted explicitly; shell-wrapped invocations remain visible in raw logs but are not classified as direct navigation usage.
Direct source formatting: /tools/compiler fmt-module file.my (prints formatted source). Export declarations belong after imports and before types/functions. Use readonly literal slice arguments directly. Whole initialized slice borrowing uses owner[..]; independent borrow clauses may share one lexical block. Existing ownership and effect rules still apply.
''')
matrix=json.loads((H/'stdlib-parity-planner-dependency-lags-20260907.json').read_text())
for row in matrix['capabilities']:
 row['evidence']=['acceptance','dependency_inventory','library_reference','task_scope','independent_reviews']
 if row['id']=='json-transport':row['my_api']='std_text::read; std_json parser; std_json_view typed nodes, cursors, required/default/bounds/allowed-field helpers'
 if row['id']=='ordering':
  row['my_api']='std_order descriptors; std_collections::sort_by/lower_bound_by with explicit readonly document context'
  row['notes']='Both mechanisms use bounded O(n log n) heapsort. Callback contexts are synchronous readonly loans, no escaping reference result. Planner uses direct node IDs and shared comparator.'
 if row['id']=='testing':row['my_api']+='; scripts/project.py combines checked source context with declared verification and exclusive per-attempt reports'
matrix['review']={'reviewer':'root integration; library_parity JSON/tooling/callback/planner audit; slack_zig independent EDA review','completed_at':datetime.now(timezone.utc).isoformat(),'notes':'Eight distinct existing tasks; required general facilities implemented before clocks; no domain trial features added to baselines.'}
matrix['accounting']={'application_seconds':0,'agent_turns':None,'tokens':None,'compute_cost':None,'human_minutes':None,'notes':'Preparation started 2026-09-07T23:41:57Z; journal records phase boundaries; parallel agent compute and exact total adoption cost unknown.'}
mp=H/'stdlib-parity-velocity-v1.json';mp.write_text(json.dumps(matrix,indent=2)+'\n')
reviews={name:path_identity(R/name) for name in ('tooling-review.json','callback-review.json','planner-preparation-review.json','eda-preparation-review.json')}
write_json(validation/'reviews.json',reviews)
inputs={'compiler':R/'toolchain/bin/mylang','byte_io':R/'toolchain/bin/mylang-io','python':'/usr/bin/python3','python_stdlib':'/usr/lib/python3.14','zig':'/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b','stdlib':REPO/'src/stdlib','acceptance':validation/'final-test-install.log','dependency_inventory':validation/'dependencies.json','library_reference':R/'library-guide.md','task_scope':R/'task-scope.md','workflow_guide':R/'workflow-guide.md','freeze_code':R/'freeze.py','independent_reviews':validation/'reviews.json','harness_acceptance':validation/'application-harness.log','cohort_code':R/'cohort.py','participant_bridge':R/'participant.py'}
for name in reviews:inputs['review:'+name]=R/name
for app in ('eda','planner'):
 for language in ('my','python','zig'):inputs['baseline:'+app+':'+language]=R/'baselines'/app if language=='my' else H/'baselines'/app/language
 inputs['contract:'+app]=H/'contracts'/('workflow-planner-v1.md' if app=='planner' else 'eda-inspector-v1.md')
receipt=parity_readiness.capture(mp,inputs=inputs,output=R/'readiness.json')
shutil.copy2(R/'readiness.json',H/'evidence/velocity-v1-readiness.json')
iteration_log.append(R,'readiness-frozen',{'readiness_sha256':receipt['sha256'],'tools':{name:path_identity(R/'toolchain/bin'/name) for name in ('mylang','mylang-io')},'all_participants_unstarted':True})
print('Readiness and tools frozen for eight .my task retests.')
