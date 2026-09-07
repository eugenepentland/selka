"""Grade one sealed exploratory .my run without inventing comparator participants."""
from pathlib import Path
from . import session, task_pack, trial_configuration
from .execution import evaluate, correct
from .inputs import decode_case
from .storage import digest, locked, read_json, verify_snapshot, write_json


def grade(pack, root, configuration, directory):
    root, directory, pack = Path(root), Path(directory), Path(pack)
    frozen_pack = task_pack.load(pack)
    trial_configuration.verify(configuration)
    directory.mkdir(exist_ok=True)
    with locked(directory), locked(root):
        participant = session.load(root)
        if (participant['phase'] != 'sealed' or participant['language'] != 'my' or
                participant['record_kind'] != 'calibration' or participant['block'] != frozen_pack['task']):
            raise ValueError('single-language grading requires a sealed matching exploratory .my session')
        if configuration['language'] != 'my':
            raise ValueError('configuration language mismatch')
        plan = {'version': 'single-language-grading-v1', 'pack_sha256': frozen_pack['sha256'],
                'session_sha256': digest(participant), 'configuration_sha256': configuration['sha256'],
                'scored': False}
        plan_file = directory / 'plan.json'
        if plan_file.exists() and read_json(plan_file) != plan:
            raise ValueError('single-language grading plan changed')
        write_json(plan_file, plan)
        final = participant['final_submission']
        row = participant['submissions'][final] if final is not None else None
        source = root / 'submissions' / f'{final:03}' / 'source' if row else None
        if row:
            verify_snapshot(source, row['source'])
        eligible = bool(row and not row['scope_violations'] and row['check'] and row['check']['passed'] and
                        session.elapsed(participant['task_started'], row['check']['finished']) <= participant['budgets']['task_seconds'])
        cases = read_json(pack / 'hidden/cases.json')
        outcomes = []
        for index, item in enumerate(cases):
            result_path = directory / f'case-{index:03}.json'
            if result_path.exists():
                result = read_json(result_path)
                if result.get('plan_sha256') != digest(plan):
                    raise ValueError('single-language case receipt changed')
            else:
                result = {'name': item['name'], 'plan_sha256': digest(plan), 'behavior_passed': False,
                          'development_accepted_in_budget': eligible, 'execution': None}
                if row and not row['scope_violations']:
                    request, raw, expected = decode_case(item['case'])
                    execution_dir = directory / f'case-{index:03}-execution'
                    if execution_dir.exists():
                        raise ValueError('unfinished grading execution requires explicit recovery: ' + str(execution_dir))
                    execution = evaluate(source, row['source'], configuration['task_adapter'], request,
                                         execution_dir, request_bytes=raw)
                    result.update(execution=execution, behavior_passed=correct(execution['outcome'], expected))
                result['accepted'] = result['behavior_passed'] and eligible
                write_json(result_path, result)
            outcomes.append(result)
        if task_pack.load(pack) != frozen_pack or digest(session.load(root)) != plan['session_sha256']:
            raise ValueError('pack or session changed during grading')
        if row:
            verify_snapshot(source, row['source'])
        trial_configuration.verify(configuration)
        result = {'version': 'single-language-result-v1', 'scored': False, 'comparative_claim': False,
                  'plan_sha256': digest(plan), 'case_count': len(outcomes), 'cases': outcomes,
                  'accepted': bool(outcomes) and all(item['accepted'] for item in outcomes),
                  'failed_cases': [item['name'] for item in outcomes if not item['accepted']]}
        write_json(directory / 'result.json', result)
        return result
