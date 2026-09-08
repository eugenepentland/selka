"""Validate complete raw runner cohorts and publish exclusive analysis projections."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

from experiments.application_comparison import session, execution
from experiments.application_comparison.inputs import decode_case, payload
from experiments.application_comparison.storage import digest, read_json, verify_snapshot
from . import analysis, runner, telemetry
from .corpus.catalog import IDS


def require(condition, message):
    if not condition: raise ValueError(message)


class Evidence:
    def __init__(self): self.files = {}; self.snapshots = []
    def note(self, path):
        path = Path(path)
        self.files[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    def read(self, path):
        self.note(path)
        return read_json(path)
    def snapshot(self, directory, receipt):
        verify_snapshot(directory, receipt)
        self.snapshots.append((directory, receipt))
    def check(self):
        for directory, receipt in self.snapshots:
            verify_snapshot(directory, receipt)
        for path, expected in self.files.items():
            require(hashlib.sha256(Path(path).read_bytes()).hexdigest() == expected,
                    'evidence changed during reporting: ' + path)


def timestamp(clock):
    # Keep raw nanoseconds in evidence; ISO text is a display projection only.
    seconds, nanos = divmod(clock['utc_ns'], 1_000_000_000)
    return datetime.fromtimestamp(seconds, timezone.utc).strftime('%Y-%m-%dT%H:%M:%S') + f'.{nanos:09}Z'


def arm_labels(registration):
    """Registered arm labels, candidate first; a legacy cohort is the my/python pair."""
    definitions = registration['configuration'].get('arms')
    if definitions is None:
        return None, ('my', 'python')
    return definitions, tuple(definitions[role]['label'] for role in runner.ROLES)


def identities(registration):
    labels = arm_labels(registration)[1]
    return [(task, pair, arm) for task in registration['tasks']
            for pair in task['pair_ids'] for arm in labels]


def review_record(path, source_sha256, evidence):
    if not path.exists(): return 'pending', None
    record = evidence.read(path)
    require(record.get('version') == 'development-source-review-v1' and
            record.get('source_sha256') == source_sha256 and source_sha256 is not None,
            'review source/version mismatch')
    require(record.get('decision') in ('approve', 'approve_with_nits', 'reject') and
            isinstance(record.get('findings'), list), 'invalid source review')
    return record['decision'], record


def verify_execution(directory, record, source, adapter, case, evidence):
    require(evidence.read(directory/'result.json') == record, 'embedded execution differs from raw receipt')
    request, raw, expected = decode_case(case)
    _, input_receipt = payload(request, raw)
    require(record.get('version') == 'application-check-v2' and
            record.get('source_sha256') == source['sha256'] and
            record.get('adapter_sha256') == adapter['sha256'] and
            record.get('request_sha256') == input_receipt['sha256'] and
            record.get('input') == input_receipt, 'execution input/source/adapter mismatch')
    # This projection supports .my/Python runner adapters, neither uses Zig build reuse.
    require('build_reuse' not in record, 'unexpected build reuse for my/Python execution')
    commands, steps = adapter['commands'], record['steps']
    require(isinstance(steps,list) and len(steps) <= len(commands), 'invalid execution step count')
    failed = None
    stdout = None
    for index,step in enumerate(steps):
        require(failed is None, 'execution continued after a failed step')
        command = commands[index]
        require(step.get('argv') == command['argv'] and step.get('phase') == command['phase'],
                'execution command differs from adapter')
        evidence.note(directory/f'{index:02}.stdout'); evidence.note(directory/f'{index:02}.stderr')
        stdout = (directory/f'{index:02}.stdout').read_bytes()
        if step.get('isolated') is not True or step.get('outcome') != 'exited' or step.get('returncode') != 0:
            failed = command['phase']
    outcome = record['outcome']
    require(type(outcome.get('passed')) is bool, 'invalid execution outcome verdict')
    if failed is not None:
        require(outcome['passed'] is False and outcome.get('phase') == failed,
                'failed execution claims successful outcome')
        return False
    if len(steps) < len(commands):
        require(outcome['passed'] is False and outcome.get('failure') == 'phase-deadline' and
                outcome.get('phase') == commands[len(steps)]['phase'], 'unfinished execution without deadline result')
        return False
    require(bool(steps) and commands[-1]['phase'] == 'run', 'missing run step')
    try:
        parsed = execution.parse_output(stdout)
    except (ValueError, UnicodeError, RecursionError):
        require(outcome.get('phase') == 'protocol' and outcome['passed'] is False,
                'invalid stdout claims behavior success')
        return False
    actual = {'phase':'behavior','passed':True,'output':parsed}
    require(outcome == actual, 'claimed output differs from actual stdout')
    return execution.correct(actual, expected)


def verify_pack(directory, record, source, adapter, cases, evidence):
    require(evidence.read(directory/'result.json') == record, 'pack differs from raw result')
    require(record.get('version') == 'public-verification-pack-v1' and
            record.get('source_sha256') == source['sha256'] and record.get('cases_sha256') == digest(cases),
            'grading source/cases mismatch')
    results = record['results']
    require(isinstance(results,list) and len(results) == len(cases) and len(cases)>0 and
            [x['name'] for x in results] == [x['name'] for x in cases], 'incomplete case result list')
    for index,(row,case) in enumerate(zip(results,cases)):
        require(type(row.get('passed')) is bool, 'invalid case verdict')
        if row.get('status') == 'not-run-deadline':
            require(row['passed'] is False and row.get('record') is None, 'unexecuted case claims pass')
        else:
            require(row.get('status') == 'executed' and isinstance(row.get('record'),dict), 'missing executed case receipt')
            actual = verify_execution(directory/f'{index:03}', row['record'], source, adapter, case['case'], evidence)
            require(not row['passed'] or actual, 'claimed case pass contradicts actual execution')
            # A correct answer marked false may have completed after a deadline.
    require(type(record.get('passed')) is bool and record['passed'] == all(x['passed'] for x in results),
            'pack verdict disagrees with cases')
    return record['passed']


def project_attempt(root, reg, task, pair, arm, evidence):
    definitions, _ = arm_labels(reg)
    definition = runner.arm_row(reg, arm)
    language = definition['language']
    path, checked_reg, checked_task = runner.attempt_path(root, task['task_id'], pair, arm)
    require(checked_reg == reg and checked_task == task, 'registration changed')
    manifest = session.load(path); evidence.note(path/'session.json')
    require(manifest['phase'] == 'sealed', 'unfinished attempt: ' + str(path))
    require((manifest['block'], manifest['pair_id'], manifest['language'], manifest['cohort']) ==
            (task['task_id'], pair, language, reg['candidate_id']), 'session identity mismatch')
    require(manifest['budgets']['task_seconds'] == task['budget_seconds'], 'session budget mismatch')
    binding = evidence.read(path/'registration-binding.json')
    require(binding == {'registration_sha256':digest(reg), 'variant_hash':task['variant_hash'],
                        'participant':manifest['participant']}, 'registration binding mismatch')
    context = evidence.read(path/'context-binding.json')
    require(context.get('version') == 'observed-agent-context-v1' and context.get('registration_sha256') == digest(reg)
            and context.get('fork_turns') == 'none' and isinstance(context.get('context_id'),str)
            and context['context_id'].startswith('/root/')
            and re.fullmatch('[0-9a-f]{64}', context.get('prompt_sha256','')) is not None,
            'invalid participant context binding')
    adapter=reg['configuration']['adapters'][arm]
    public_cases=evidence.read(Path(root)/task['task_id']/'pack/public/cases.json')
    baseline = manifest['baseline']['files']
    protected = {name:value for name,value in baseline.items() if '.trial-public' in Path(name).parts
                 or Path(name).name in ('main.my','main.py','io.my')}
    require(manifest['protected'] == protected, 'protected runtime inventory mismatch')
    # Baselines are keyed by arm label; a legacy cohort's labels are its language names.
    frozen_baseline = Path(root)/task['task_id']/(arm+'-baseline')
    evidence.snapshot(frozen_baseline, manifest['baseline'])
    for index, row in enumerate(manifest['submissions']):
        require(row['index'] == index, 'submission index mismatch')
        evidence.snapshot(path/'submissions'/f'{index:03}'/'source', row['source'])
        violations = [name for name, value in protected.items() if row['source']['files'].get(name) != value]
        if row['elapsed_seconds'] >= task['budget_seconds']:
            violations.append('task-budget-exceeded-during-capture')
        require(row['scope_violations'] == violations, 'protected source violation receipt mismatch')
        if row['check'] is not None:
            require(row['check']['source_sha256'] == row['source']['sha256'], 'public check source mismatch')
            check={key:value for key,value in row['check'].items() if key != 'finished'}
            check_directory=path/'submissions'/f'{index:03}'/'check'
            if row['scope_violations']:
                require(check.get('passed') is False and check == {
                    'source_sha256':row['source']['sha256'],'passed':False,
                    'scope_violations':row['scope_violations']}, 'invalid explicit scope rejection receipt')
                require(not check_directory.exists(), 'scope rejection unexpectedly has public execution artifacts')
            else:
                verify_pack(check_directory,check,row['source'],adapter,public_cases,evidence)
    final = manifest['final_submission']
    require(final == (len(manifest['submissions'])-1 if manifest['submissions'] else None), 'final submission mismatch')
    row = manifest['submissions'][final] if final is not None else None
    raw = evidence.read(path/'private-grading/result.json')
    summary = evidence.read(path/'grading-summary.json')
    require(summary['session_sha256'] == digest(manifest) and summary['registration_sha256'] == digest(reg)
            and summary['result_sha256'] == digest(raw), 'stale session or raw grading receipt')
    if row is None:
        require(raw == {'passed':False,'reason':'no-submission'}, 'invalid no-submission grade')
    else:
        cases = evidence.read(Path(root)/task['task_id']/'pack/private/cases.json')
        verify_pack(path/'private-grading',raw,row['source'],adapter,cases,evidence)
    verification = bool(row and row['check'] is not None and row['check']['passed'])
    eligible = bool(row and not row['scope_violations'] and manifest['seal_reason']=='completed')
    require(all(type(summary[k]) is bool for k in ('passed','behavior_pass','verification_pass','eligible')), 'invalid grading summary booleans')
    require(type(raw['passed']) is bool and summary['behavior_pass'] == raw['passed'] and
            summary['verification_pass'] == verification and summary['eligible'] == eligible and
            summary['passed'] == (raw['passed'] and verification and eligible), 'grading summary verdict mismatch')
    profile = evidence.read(path/'profile.json')
    require(profile == telemetry.summarize(path, arm=arm, interface=definition['interface']),
            'stale or inconsistent operation profile')
    # Profile recomputation rejects incomplete operations and uncommitted commands.
    for directory in ('telemetry','gateway'):
        for record in (path/directory).glob('*/request.json'):
            evidence.note(record); evidence.note(record.with_name('result.json'))
    elapsed = session.elapsed(manifest['task_started'], manifest['sealed'])
    require(elapsed == manifest['participant_seconds'], 'session elapsed mismatch')
    status = ('timed_out' if manifest['seal_reason']=='budget' or elapsed>task['budget_seconds'] else
              'abandoned' if manifest['seal_reason']=='abandoned' else
              'sealed' if summary['passed'] else 'failed')
    require(manifest['seal_reason'] in ('completed','budget','abandoned'), 'unknown seal reason')
    source = row['source']['sha256'] if row else None
    decision, review = review_record(path/'source-review.json', source, evidence)
    attempt = {'task_id':task['task_id'],'pair_id':pair,'language':language,
               **({} if definitions is None else {'arm':arm}),
               'attempt_id':manifest['participant'],'participant_id':context['context_id'],
               'registration_hash':digest(reg),'configuration_hash':reg['configuration_hash'],
               'variant_hash':task['variant_hash'],'started_at':timestamp(manifest['task_started']),
               'ended_at':timestamp(manifest['sealed']),'status':status,'behavior_pass':raw['passed'],
               'verification_pass':verification,'review':decision,
               'clock':{'boot_id':manifest['task_started']['boot_id'],
                        'started_monotonic_ns':manifest['task_started']['monotonic_ns'],
                        'ended_monotonic_ns':manifest['sealed']['monotonic_ns']},
               'telemetry':{'model_requests':profile.get('model_requests'), 'model_tokens':profile.get('model_tokens'),
                            'queue_wait_seconds':profile.get('queue_wait_seconds')}}
    detail = {'attempt_id':manifest['participant'],'source_sha256':source,'review':review,
              'arm':arm,'interface':definition['interface'],
              'raw_clocks':{'started':manifest['task_started'],'sealed':manifest['sealed']},
              'profile':profile,'preparation':manifest.get('preparation'),
              'submission_count':len(manifest['submissions']),
              'failed_public_checks':sum(r['check'] is not None and not r['check']['passed'] for r in manifest['submissions'])}
    return attempt, detail


def inventory(root):
    reg = runner.registered(root)
    definitions, _ = arm_labels(reg)
    rows=[]
    for task,pair,arm in identities(reg):
        definition=runner.arm_row(reg,arm)
        path=Path(root)/task['task_id']/pair/arm
        rows.append({'task':task['task_id'],'pair':pair,'arm':arm,'language':definition['language'],
            'interface':definition['interface'],
            'phase':read_json(path/'session.json')['phase'] if (path/'session.json').exists() else 'not-prepared',
            'grade_present':(path/'grading-summary.json').exists(),
            'review_present':(path/'source-review.json').exists()})
    # v2 lists the registered arms; rows carry the arm label, language and interface.
    return {'version':'development-inventory-v2','aggregate_available':False,'parity_claim':False,
            'arms':definitions,'attempts':rows}


def compiler_totals(attempts, details):
    groups={}
    for attempt, detail in zip(attempts, details):
        for record in detail['profile']['compiler_phase_records']:
            key=(attempt.get('arm',attempt['language']),attempt['language'],
                 record.get('tool'),record['name'],record['inclusive'])
            require(type(record['duration_ns']) is int and record['duration_ns'] >= 0 and
                    type(record['inclusive']) is bool, 'invalid phase timing')
            require((record.get('tool') is None or isinstance(record['tool'],str)) and
                    isinstance(record['name'],str), 'invalid phase identity')
            count,duration=groups.get(key,(0,0))
            groups[key]=(count+1,duration+record['duration_ns'])
    return [{'arm':arm,'language':lang,'tool':tool,'name':name,'inclusive':inclusive,
             'calls':count,'sum_duration_seconds':duration/1e9}
            for (arm,lang,tool,name,inclusive),(count,duration) in sorted(groups.items(),
                key=lambda item:(item[0][0],item[0][2] or '',item[0][3],item[0][4]))]


def store_totals(profiles):
    """Only a store session gateway reports these; a files arm projects null."""
    metrics=[profile.get('store_metrics') for profile in profiles]
    if not metrics or any(metric is None for metric in metrics):
        return {key:None for key in telemetry.STORE_METRICS}
    totals={}
    for key in telemetry.STORE_METRICS:
        values=[metric[key] for metric in metrics]
        if all(isinstance(value,dict) for value in values):
            counter=Counter()
            for value in values: counter.update(value)
            totals[key]=dict(counter)
        else:
            require(all(type(value) is int for value in values),'invalid store metric')
            totals[key]=sum(values)
    return totals


def project(root):
    root=Path(root).resolve(strict=True); reg=runner.registered(root)
    require({t['task_id'] for t in reg['tasks']}==set(IDS) and len(reg['tasks'])==12, 'full corpus requires twelve distinct tasks')
    expected=identities(reg);require(len(expected)>=24,'full cohort requires at least24 attempts')
    labels=arm_labels(reg)[1]
    e=Evidence();e.note(root/'registration.json'); readiness=e.read(root/'readiness.json')
    require(digest(readiness)==reg['configuration']['readiness_sha256'],'preparation record changed')
    attempts=[];details=[]
    for task,pair,arm in expected:
        attempt,detail=project_attempt(root,reg,task,pair,arm,e);attempts.append(attempt);details.append(detail)
    document={'schema_version':1,'registration':reg,'registration_hash':digest(reg),'attempts':attempts}
    result=analysis.analyze(document) # Rejects reused context IDs and incomplete paired identities.
    diagnostics=Counter(); operations=Counter(); output={}; observed={};unobserved={};store={}
    languages={arm:runner.arm_row(reg,arm)['language'] for arm in labels}
    for arm in labels:
        profiles=[d['profile'] for a,d in zip(attempts,details) if a.get('arm',a['language'])==arm]
        output[arm]=sum(p['gateway_metrics']['phases']['working']['captured_output_bytes'] for p in profiles)
        observed[arm]=sum(p['observed_operation_seconds'] for p in profiles) if all(p['observed_operation_seconds'] is not None for p in profiles) else None
        unobserved[arm]=sum(p['unobserved_seconds'] for p in profiles) if all(p['unobserved_seconds'] is not None for p in profiles) else None
        store[arm]=store_totals(profiles)
        for profile in profiles:
            for event in profile['diagnostic_history']: diagnostics.update((arm,code) for code in event['codes'])
            for purpose,seconds in (profile['operation_seconds_by_declared_purpose'] or {}).items():operations[(arm,purpose)]+=seconds
    result['observations']={'compiler_phases':compiler_totals(attempts,details),
        'compiler_phase_scope':'Timed application commands and public checks only; practice and private grading excluded. Nested/inclusive phase sums may overlap and are not added to operation or application wall time; not pure compiler CPU.',
        'diagnostics':[{'arm':arm,'language':languages[arm],'code':code,'operation_occurrences':count} for (arm,code),count in diagnostics.most_common()],
        'operation_seconds_by_declared_purpose':[{'arm':arm,'language':languages[arm],'purpose':purpose,'seconds':seconds} for (arm,purpose),seconds in sorted(operations.items())],
        'captured_output_bytes':output,'observed_operation_seconds':observed,'unobserved_wall_seconds':unobserved,
        'store_session_metrics':store,
        'store_metric_scope':'Only a declaration-store session interface reports these; files arms are null.'}
    result['attempt_evidence']=details;result['raw_evidence']=e.files
    result['preparation_record']=str(root/'readiness.json')
    result['preparation_journal']={}
    for name in ('iteration.json','events.jsonl'):
        path=root.parent/name
        if path.exists():
            e.note(path);result['preparation_journal'][name]=str(path)
    result['preparation_timing_policy']='No global preparation elapsed time is inferred. Explicit preparation-start-correction events supersede the original manually converted start when interpreting the journal; all originals remain retained.'
    # Re-verify after all reads; no new application commands or grading occurs.
    require(runner.registered(root)==reg,'registration changed during report')
    e.check()
    return document,result


def markdown(report):
    arms=report.get('arms')
    # Legacy cohorts keep their published my/Python wording; arm cohorts use labels.
    first,second=('my','python') if arms is None else ('candidate','comparator')
    names=('.my','Python') if arms is None else tuple(arms[role]['label'] for role in ('candidate','comparator'))
    lines=['# Development velocity cohort','',
           'Failure-inclusive capped costs; pending reviews and unsuccessful attempts receive their full registered budget. Development results cannot establish a stopping/parity claim.','',
           f'| Task | {names[0]} cost seconds | {names[1]} cost seconds | {names[0]} / {names[1]} qualified |',
           '|---|---:|---:|---|']
    for row in report['tasks']:lines.append(f"| {row['task_id']} | {row[first+'_cost']:.3f} | {row[second+'_cost']:.3f} | {row[first+'_qualified_count']} / {row[second+'_qualified_count']} |")
    lines+=['',f'| Family | {names[0]} cost | {names[1]} cost | {names[0]} completion | {names[1]} completion |','|---|---:|---:|---:|---:|']
    for family,row in report['families'].items():lines.append(f"| {family} | {row[first+'_cost']:.3f} | {row[second+'_cost']:.3f} | {row[first+'_completion']:.3f} | {row[second+'_completion']:.3f} |")
    lines+=['',f"Family-weighted {names[0]}/{names[1]} cost ratio: {report['aggregate']['cost_ratio']:.3f}.",'',
            'Observed output and time totals: '+json.dumps({k:v for k,v in report['observations'].items() if k not in ('diagnostics','operation_seconds_by_declared_purpose','compiler_phases','compiler_phase_scope','store_metric_scope')},sort_keys=True), '',
            'Repeated diagnostic codes (operation occurrences, not bugs):']
    lines+=['- '+str(row) for row in report['observations']['diagnostics'][:20]] or ['No diagnostic codes observed.']
    lines+=['','Declared operation time:']+['- '+str(row) for row in report['observations']['operation_seconds_by_declared_purpose']]
    lines+=['','| Arm | Tool | Phase | Inclusive | Calls | Sum seconds |', '|---|---|---|---|---:|---:|']
    for row in report['observations']['compiler_phases']:
        lines.append(f"| {row['arm']} | {row['tool'] or 'unknown'} | {row['name']} | {row['inclusive']} | {row['calls']} | {row['sum_duration_seconds']:.6f} |")
    lines+=['',report['observations']['compiler_phase_scope']]
    lines+=['','Unobserved wall time includes reasoning, drafting, scheduling and orchestration; its components are unknown. Output bytes and gateway commands are not tokens or model turns.', '',
            'Preparation record: '+report['preparation_record'], '',
            'summary.json retains all terminal attempts, raw clock values, nullable telemetry and hash-linked source/result/review references. Private inputs are not copied into this report.']
    return '\n'.join(lines)+'\n'


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('cohort',type=Path)
    parser.add_argument('--inventory',action='store_true');parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    if args.inventory:
        require(args.output is None,'inventory uses stdout only, not aggregate publication')
        print(json.dumps(inventory(args.cohort),indent=2));return
    require(args.output is not None,'--output NEW_DIRECTORY required')
    document,report=project(args.cohort)
    args.output.mkdir(parents=True,exist_ok=False)
    for name,value in [('analysis-input.json',document),('summary.json',report)]:
        with (args.output/name).open('x') as stream:json.dump(value,stream,indent=2,sort_keys=True,allow_nan=False);stream.write('\n')
    with (args.output/'report.md').open('x') as stream:stream.write(markdown(report))

if __name__=='__main__':main()
