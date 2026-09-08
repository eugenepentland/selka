"""Retain frozen inputs, fresh .my runs and private grading for velocity iteration v1."""
import sys,json,shutil,hashlib
from pathlib import Path
sys.path.insert(0,'/home/epentland/ai/canopy/mylang')
from experiments.application_comparison import session,task_pack,practice_pack,trial_configuration,seeded_regressions,coordinator_receipt,parity_readiness,single_language_grading,tool_metrics,iteration_log
from experiments.application_comparison.storage import write_json,read_json,snapshot,digest,verify_snapshot
R=Path(__file__).parent
H=Path('/home/epentland/ai/canopy/mylang/experiments/application_comparison')
REPO=H.parents[1]
TASKS=['eda-clearance-boundary','planner-input-boundary','eda-pin-roles','planner-priority','eda-rotation','planner-cycle-groups','planner-dependency-lags','planner-slack']

def prepare(task):
    r=R/task;app=task.split('-')[0]
    readiness=read_json(R/'readiness.json')
    write_json(r/'readiness-before-setup.json',parity_readiness.verify(readiness))
    cfg=read_json(R/(app+'-configuration.json'))
    trial_configuration.verify(cfg)
    write_json(r/'my-configuration.json',cfg)
    practice_pack.create(r/'my-practice',language='my')
    clean=r/'my-clean-baseline'
    if task=='planner-slack':
        previous=R/'planner-dependency-lags'
        result=read_json(previous/'summary.json')
        if not result['participants']['my']['hidden']['accepted']:
            raise ValueError('accepted predecessor required; recovery must be separately recorded')
        m=session.load(previous/'my');idx=m['final_submission'];row=m['submissions'][idx]
        source=previous/'my/submissions'/f'{idx:03}'/'source'
        verify_snapshot(source,row['source'])
        shutil.copytree(source,clean,ignore=shutil.ignore_patterns('.trial-public','__pycache__'))
        inherited={k:v for k,v in row['source']['files'].items() if not k.startswith('.trial-public/')}
        actual=task_pack.receipt(clean)
        assert actual['files']==inherited
        write_json(r/'predecessor.json',{'summary_sha256':hashlib.sha256((previous/'summary.json').read_bytes()).hexdigest(),'source':row['source'],'inherited':actual,'recovery':None})
    else:
        shutil.copytree(R/'baselines'/app,clean)
    base=r/'my-baseline'
    if task in ('eda-clearance-boundary','planner-input-boundary'):
        receipt=task_pack.receipt(clean)
        write_json(r/'mutation.json',seeded_regressions.create(clean,base,receipt,task=task,language='my'))
    else:shutil.copytree(clean,base)
    task_pack.provision_public(r/'pack',base/'.trial-public')
    contract=(H/'contracts'/('workflow-planner-v1.md' if app=='planner' else 'eda-inspector-v1.md')).read_text()
    if task=='planner-slack':contract+='\n\n'+(H/'pilot_tasks/planner-dependency-lags.md').read_text()
    (base/'.trial-public/CONTRACT.md').write_text(contract)
    shutil.copy(r/'my-practice/starter/GUIDE.md',base/'.trial-public/GUIDE.md')
    (base/'.trial-public/LIBRARY.md').write_text((R/'library-guide.md').read_text())
    (base/'.trial-public/WORKFLOW.md').write_text((R/'workflow-guide.md').read_text())
    protected=['.trial-public/'+p.name for p in (base/'.trial-public').iterdir()]
    session.prepare(r/'my',base,language='my',block=task,cohort=R.name,participant=task+'-my-v1',model='inherited-coding-agent-exact-id-unavailable',kind='calibration',protected=protected,preparation_seconds=1200,task_seconds=1800,trial_configuration_sha256=cfg['sha256'])
    shutil.copytree(r/'my-practice/starter',r/'my/practice',dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copy(r/'my-practice/contract.md',r/'my/practice/CONTRACT.md')
    write_json(r/'coordinator-source.json',coordinator_receipt.source_inventory(H))
    write_json(r/'protocol.json',{'task':task,'cohort':R.name,'scored':False,'languages':['my'],'baseline':task_pack.receipt(clean),'readiness_sha256':readiness['sha256'],'configuration_sha256':cfg['sha256'],'build_policy':'suite-build-reuse-v1','dispatch_order':TASKS,'limits':['instruction-only whole-agent confinement; namespace commands','exact model ID/turn/token/cost unknown','combined intervention versus historical runs; no causal attribution']})
    iteration_log.append(R,'session-prepared',{'task':task,'baseline_sha256':task_pack.receipt(clean)['sha256'],'configuration_sha256':cfg['sha256']})
    print('Prepared '+task)

def grade(task):
    r=R/task;cfg=read_json(r/'my-configuration.json')
    assert coordinator_receipt.source_inventory(H)==read_json(r/'coordinator-source.json')
    write_json(r/'readiness-before-grading.json',parity_readiness.verify(read_json(R/'readiness.json')))
    result=single_language_grading.grade(r/'pack',r/'my',cfg,r/'grading')
    m=session.load(r/'my');metrics=tool_metrics.summarize(r/'my')
    assert not metrics['uncommitted_command_records']
    row={'preparation_seconds':m['preparation']['elapsed_seconds'],'practice_outcome':m['preparation']['outcome'],'task_seconds':m['participant_seconds'],'public_submissions':len(m['submissions']),'failed_public_submissions':sum(x['check'] is not None and not x['check']['passed'] for x in m['submissions']),'seal_reason':m['seal_reason'],'hidden':{k:result[k] for k in ('accepted','failed_cases')},'metrics':metrics,'source':m['submissions'][m['final_submission']]['source'] if m['final_submission'] is not None else None}
    write_json(r/'summary.json',{'task':task,'cohort':R.name,'scored':False,'comparative_claim':False,'hidden_case_groups':result['case_count'],'participants':{'my':row},'protocol':read_json(r/'protocol.json')})
    iteration_log.append(R,'trial-graded',{'task':task,'application_seconds':row['task_seconds'],'accepted':result['accepted'],'summary_sha256':hashlib.sha256((r/'summary.json').read_bytes()).hexdigest(),'raw_directory':str(r)})
    print(json.dumps({k:v for k,v in row.items() if k not in ('metrics','source')}))

if __name__=='__main__':
    operation,task=sys.argv[1:3]
    if task not in TASKS:raise ValueError('task')
    {'prepare':prepare,'grade':grade}[operation](task)
