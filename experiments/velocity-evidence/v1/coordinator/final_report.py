"""Read-only final evidence collection. Publish requires complete 8+6+6 evidence."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent
REPO = Path('/home/epentland/ai/canopy/mylang')
OLD = ROOT.parent / 'maintenance-20260907'
TASKS = ('eda-clearance-boundary','planner-input-boundary','eda-pin-roles','planner-priority','eda-rotation','planner-cycle-groups','planner-dependency-lags','planner-slack')
RUNS = tuple(f'{p}-stage{s}' for p in ('a','b') for s in (1,2,3))


def require(ok, message):
    if not ok: raise ValueError(message)


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def exact_members(rows, key, expected):
    actual = [row[key] for row in rows]
    require(len(actual) == len(expected) and set(actual) == set(expected), 'Missing, duplicate or unexpected ' + key)


class Evidence:
    def __init__(self): self.references = {}
    def read(self, path):
        path = Path(path)
        raw = path.read_bytes()
        self.references[str(path)] = hashlib.sha256(raw).hexdigest()
        return json.loads(raw)
    def reference(self, path):
        self.references[str(path)] = sha(path)
    def verify_all(self):
        for path, expected in self.references.items():
            require(sha(path) == expected, 'Evidence changed during collection: ' + path)


def verify_files(directory, receipt):
    actual = {str(p.relative_to(directory)): sha(p) for p in directory.rglob('*') if p.is_file()}
    require(actual == receipt['files'], 'Sealed source inventory changed: ' + str(directory))


def grade_behavior(grade):
    outcomes = grade['outcomes']
    require(isinstance(outcomes, list) and all(type(row.get('passed')) is bool for row in outcomes),
            'Invalid maintenance case verdict')
    expected = bool(outcomes) and all(row['passed'] for row in outcomes)
    require(type(grade['behavior_passed']) is bool and grade['behavior_passed'] == expected,
            'Maintenance behavior verdict disagrees with case outcomes')
    return expected


def maintenance_eligible(seal, *grades):
    return (seal.get('reason') == 'completed' and seal.get('final_checked') is True and
            seal.get('last_checked') == seal['source'] and
            all(grade.get('final_checked') is True and grade.get('last_checked') == seal['source']
                for grade in grades))


def main_totals(rows):
    totals = {key:sum(r[key] for r in rows) for key in ('old_seconds','new_seconds','old_trusted_check_failures','new_trusted_check_failures')}
    for metric in ('command_count','failed_commands','captured_output_bytes'):
        for prefix in ('old','new'):
            totals[prefix+'_'+metric]=sum(r[prefix+'_working_metrics'][metric] for r in rows)
    totals['delta_seconds'] = totals['new_seconds'] - totals['old_seconds']
    totals['all_accepted'] = bool(rows) and all(r['fresh_accepted'] and r['historical_replay_accepted'] and r['original_accepted'] for r in rows)
    totals['all_declared_tests_passed'] = bool(rows) and all(r['declared_tests_passed'] for r in rows)
    totals['comparison_eligible'] = totals['all_accepted'] and totals['all_declared_tests_passed']
    totals['elapsed_change_percent'] = 100*(totals['new_seconds']/totals['old_seconds']-1) if totals['comparison_eligible'] else None
    return totals


def maintenance(e, name):
    base = ROOT / name
    review = e.read(base/'source-review/quality-review.json')
    exact_members(review['stages'], 'stage', RUNS)
    historical = e.read(base/'historical-replays/summary.json')
    exact_members(historical['rows'], 'run', RUNS)
    e.reference(base/'freeze.json'); e.reference(base/'config.json')
    rows = []
    for run in RUNS:
        d = base/'runs'/run
        seal = e.read(d/'seal.json'); grade = e.read(d/'grade.json')
        replay = e.read(base/'historical-replays'/run/'grade.json')
        oldseal = e.read(OLD/run/'seal.json'); oldgrade = e.read(OLD/run/'grade.json')
        verify_files(d/'sealed', seal['source'])
        verify_files(OLD/run/'sealed', oldseal['source'])
        require(grade['source'] == replay['source'] == seal['source'], 'Maintenance grading/source mismatch')
        for result in (grade, replay, oldgrade): grade_behavior(result)
        receipt = next(x for x in historical['rows'] if x['run'] == run)
        require(receipt['grade_sha256'] == sha(base/'historical-replays'/run/'grade.json'), 'Maintenance replay hash mismatch')
        require(receipt['historical_grade_sha256'] == sha(OLD/run/'grade.json'), 'Historical grade hash mismatch')
        timings = {}
        for label, directory in [('historical',OLD/run),('current',d)]:
            gateway = e.read(directory/'gateway.json')
            require(gateway['pending'] is None, 'Unfinished maintenance command')
            commands = [directory/'commands'/f'{i:03}' for i in range(1,gateway['commands']+1)]
            require(bool(commands), 'Maintenance stage has no executed command')
            requests = [e.read(p/'request.json') for p in commands]
            results = [e.read(p/'result.json') for p in commands]
            timings[label] = {'start_to_last_command_seconds':max(x['time'] for x in results)-gateway['started_unix'],
                'begin_to_first_command_seconds':requests[0]['time']-gateway['started_unix'],
                'gateway_requests':gateway['requests'], 'executed_commands':gateway['commands'],
                'edited_submissions':gateway['edited_checks']}
        stage_review = next(x for x in review['stages'] if x['stage']==run)
        rows.append({'run':run, **timings, 'fresh_accepted':grade['behavior_passed'],
            'historical_replay_accepted':replay['behavior_passed'], 'original_accepted':oldgrade['behavior_passed'],
            'current_development_eligible':maintenance_eligible(seal, grade, replay),
            'original_development_eligible':maintenance_eligible(oldseal, oldgrade),
            'seal_reason':seal['reason'], 'final_checked':seal['final_checked'],
            'source_sha256':seal['source']['sha256'], 'historical_source_sha256':oldseal['source']['sha256'],
            'program_source_identical_to_historical':seal['source']['files']==oldseal['source']['files'],
            'review_verdict':stage_review['verdict']})
    old_total=sum(row['historical']['start_to_last_command_seconds'] for row in rows)
    new_total=sum(row['current']['start_to_last_command_seconds'] for row in rows)
    accepted=all(row['fresh_accepted'] and row['historical_replay_accepted'] and row['original_accepted'] and row['current_development_eligible'] and row['original_development_eligible'] for row in rows)
    return {'cohort':name,'rows':rows,'review_verdict':review['verdict'],
        'all_accepted':accepted, 'all_program_sources_identical_to_historical':all(row['program_source_identical_to_historical'] for row in rows),
        'summed_stage_seconds':{'historical':old_total,'current':new_total},
        'elapsed_change_percent':100*(new_total/old_total-1) if accepted and name=='maintenance-matched' else None,
        'historical_speed_comparison_eligible':name=='maintenance-matched',
        'clock_method':'coordinator begin before stage handoff' if name=='maintenance-matched' else 'autonomous first-check begin; supplemental only'}


def collect():
    e = Evidence()
    combined = e.read(ROOT/'reporting/publication-001/combined.json')
    exact_members([r['comparison'] for r in combined['comparisons']], 'task', TASKS)
    rows=[]
    for row in combined['comparisons']:
        c=row['comparison']; task=c['task']; base=ROOT/task
        summary=e.read(base/'summary.json'); session=e.read(base/'my/session.json')
        fresh=e.read(base/'grading/result.json'); replay=e.read(ROOT/'reporting/replays'/task/'result.json')
        tests=e.read(base/'declared-tests/result.json'); review=e.read(ROOT/'source-reviews'/task/'quality-review.json')
        require(session['phase']=='sealed', 'Unsealed main session')
        source=session['submissions'][session['final_submission']]['source'] if session['final_submission'] is not None else None
        if source: verify_files(base/'my/submissions'/f"{session['final_submission']:03}"/'source', source)
        require(tests['source_sha256']==(source['sha256'] if source else None), 'Declared tests refer to different source')
        require(fresh['cases'] and replay['cases'], 'Incomplete main grading')
        require(c['current']['application_seconds']==session['participant_seconds']==summary['participants']['my']['task_seconds'], 'Main timing mismatch')
        require(c['current']['fresh_pack_accepted']==fresh['accepted'] and c['current']['historical_pack_accepted']==replay['accepted'], 'Main acceptance mismatch')
        priorref=row['references']['historical_evidence']['summary']
        old=e.read(priorref['path']); require(sha(priorref['path'])==priorref['sha256'], 'Historical summary changed')
        require(old['participants']['my']['task_seconds']==c['previous']['application_seconds'], 'Historical timing mismatch')
        for key in ('summary','configuration','protocol','fresh_result','historical_replay'):
            ref=row['references'][key]; e.reference(ref['path']);require(sha(ref['path'])==ref['sha256'],'Combined reference changed')
        rows.append({'task':task,'old_seconds':c['previous']['application_seconds'],'new_seconds':c['current']['application_seconds'],
            'fresh_accepted':fresh['accepted'],'historical_replay_accepted':replay['accepted'],
            'original_accepted':c['previous']['accepted'],'declared_tests_passed':tests['passed'],
            'review_verdict':review['verdict'],'review_findings':review.get('findings',[]),
            'old_trusted_check_failures':old['participants']['my']['failed_public_submissions'],
            'new_trusted_check_failures':summary['participants']['my']['failed_public_submissions'],
            'old_working_metrics':row['historical_metrics']['phases']['working'],
            'new_working_metrics':row['metrics']['phases']['working']})
    totals = main_totals(rows)
    autonomous=maintenance(e,'maintenance'); matched=maintenance(e,'maintenance-matched')
    audit=e.read(ROOT/'maintenance/clock-placement-audit.json')
    for row in matched['rows']:
        auto=next(x for x in autonomous['rows'] if x['run']==row['run'])
        row['program_source_identical_to_autonomous']=row['source_sha256']==auto['source_sha256']
    followups=[]
    for task in ('eda-clearance-boundary','planner-slack'):
        d=ROOT/'review-followups'/task
        provenance=e.read(d/'provenance.json'); validation=e.read(d/'validation.json')
        require(validation['timed_submission_changed'] is False and provenance['development_clock_adjustment'] is None,'Followup changed timed observation')
        followups.append({'task':task,'passed':validation['passed'],'change':provenance['change'],'timed_source_changed':False,'clock_adjustment':None})
    ledger=e.read(REPO/'experiments/validation/velocity-v1/ledger.json')
    e.reference(REPO/'experiments/validation/velocity-v1/final-test-install.log')
    e.reference(REPO/'experiments/validation/velocity-v1/application-harness.log')
    e.reference(ROOT/'readiness.json'); e.reference(ROOT/'iteration.json'); e.reference(ROOT/'host-observations.jsonl')
    e.reference(Path(__file__))
    report={'version':'velocity-v1-final-evidence-v1','scored':False,'causal_claim':False,
        'main':{'rows':rows,'totals':totals},'maintenance_autonomous':autonomous,'maintenance_matched':matched,
        'maintenance_method_finding':audit['finding'],'review_followups':followups,
        'preparation':{'language_tests':1089,'harness_tests':185,'implementation_revision':'b6776e7','additional_frozen_revision':'eb05e80',
            'started_utc':'2026-09-07T23:41:57Z','frozen_utc':'2026-09-08T00:29:22Z','wall_seconds':2845,
            'interpretation':'47.4 minutes elapsed preparation wall time, not summed CPU or development savings'},
        'limitations':['No aggregate application delivery speed improvement if elapsed total increases; command/failure reductions are observed proxies, not proven fewer bugs or model turns.',
            'Background concurrent VM work was observed; elapsed results include scheduling interference and uncontrolled agent/dispatch variation.',
            'Main trials changed syntax, standard library, baseline structure, workflow and test workload together; no individual feature effect or causal attribution.',
            'Autonomous maintenance is excluded from historical speed comparisons because its clock began at first check.',
            'Matched maintenance retains begin-to-first-command gaps without correction; identical small program solutions do not establish general development advantage.',
            'Exact model identity, model turns, tokens and cost are unknown. Gateway output bytes are captured output, not model context.',
            'Separate followup test repairs do not alter timed submissions, acceptance or clocks.'],
        'next_experiments':['Repeat matched tasks with multiple fresh contexts, identical declared verification workload and randomized order.',
            'Separate syntax/library changes from workflow changes in controlled arms.',
            'Implement and independently test required standard-library mechanisms before freezing baselines or starting application clocks.',
            'Add a medium-size application with cross-module changes and meaningful error-handling requirements.'],
        'references':e.references}
    e.verify_all()
    return report


def markdown(r):
    t=r['main']['totals']
    eligible=t['comparison_eligible']
    lines=['# Velocity v1 evidence report','',('Acceptance or declared-test failure prevents an aggregate speed comparison; raw elapsed totals and failures are retained in the JSON report.' if not eligible else (f"Across eight main tasks, recorded delivery time changed from {t['old_seconds']:.3f}s to {t['new_seconds']:.3f}s ({t['elapsed_change_percent']:+.3f}%). This provides no aggregate speed improvement." if t['new_seconds']>=t['old_seconds'] else 'Observed elapsed total decreased; this uncontrolled comparison cannot establish causality.')),'',
        f"Working commands: {t['old_command_count']} → {t['new_command_count']}; failed commands: {t['old_failed_commands']} → {t['new_failed_commands']}; trusted-check failures: {t['old_trusted_check_failures']} → {t['new_trusted_check_failures']}. Captured output bytes: {t['old_captured_output_bytes']} → {t['new_captured_output_bytes']}. These are not model turns or proven bug counts.",'',
        '| Main task | Old seconds | New seconds | Fresh / historical accepted | Declared tests | Review |','|---|---:|---:|---|---|---|']
    for row in r['main']['rows']:
        lines.append(f"| {row['task']} | {row['old_seconds']:.3f} | {row['new_seconds']:.3f} | {row['fresh_accepted']} / {row['historical_replay_accepted']} | {row['declared_tests_passed']} | {row['review_verdict']} |")
    lines += ['', 'Autonomous maintenance remains supplemental because its clock started at first check. The matched repeat uses explicit begin before handoff; gaps remain part of delivery time.', '', '| Matched maintenance | Old seconds | New seconds | Old / new begin gaps | Fresh / historical accepted | Identical old / autonomous source |','|---|---:|---:|---|---|---|']
    for row in r['maintenance_matched']['rows']:
        a=row['historical'];b=row['current']
        lines.append(f"| {row['run']} | {a['start_to_last_command_seconds']:.3f} | {b['start_to_last_command_seconds']:.3f} | {a['begin_to_first_command_seconds']:.3f} / {b['begin_to_first_command_seconds']:.3f} | {row['fresh_accepted']} / {row['historical_replay_accepted']} | {row['program_source_identical_to_historical']} / {row['program_source_identical_to_autonomous']} |")
    lines += ['', 'Two review followups strengthened test completeness separately; timed sources and clocks remain unchanged.', '', 'Preparation validated 1089 language tests and 185 harness tests. The recorded preparation interval was 23:41:57–00:29:22 UTC, approximately 47.4 minutes wall time, not summed CPU time.', '', *r['limitations'], '', 'Next experiments:', '', *['- '+x for x in r['next_experiments']], '', 'The JSON report contains complete cohort observations and source-file hashes/raw evidence references. Private case contents and seeds are omitted.']
    return '\n'.join(lines)+'\n'


def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('--output',type=Path);p.add_argument('--check',action='store_true');a=p.parse_args()
    require(a.check or a.output is not None,'Use --check or --output NEW_DIRECTORY')
    report=collect()
    if a.check:
        print(json.dumps({'complete':True,'main_tasks':8,'autonomous_stages':6,'matched_stages':6,'main_totals':report['main']['totals']}));return
    a.output.mkdir(parents=True,exist_ok=False)
    (a.output/'summary.json').write_text(json.dumps(report,indent=2,sort_keys=True,allow_nan=False)+'\n')
    (a.output/'report.md').write_text(markdown(report))


if __name__=='__main__':
    try:main()
    except (ValueError,OSError,KeyError) as error:
        print(json.dumps({'publish':'refused','reason':str(error)}));raise SystemExit(1)
