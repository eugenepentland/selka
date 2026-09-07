"""Common hidden inputs, sealed three-way grading and resumable per-language records."""
from contextlib import ExitStack
from pathlib import Path
from . import environment_receipt, session
from .inputs import payload
from .execution import correct, evaluate, verify_adapter
from .storage import digest, locked, read_json, verify_snapshot, write_json


def grade(roots, adapters, request, expected, directory, *, grader_identity, request_bytes=None, build_reuse=None):
    """Called only by the trusted coordinator after the block is sealed.

The caller owns the frozen oracle/generator and records its identity. This API
never returns hidden feedback to the participant; that routing is gateway policy.
"""
    _, input_receipt = payload(request, request_bytes)
    roots = [Path(root).resolve() for root in roots]
    directory = Path(directory)
    if not grader_identity:
        raise ValueError('grader identity required')
    directory.mkdir(exist_ok=True)
    with ExitStack() as stack:
        stack.enter_context(locked(directory))
        for root in sorted(set(roots)):
            stack.enter_context(locked(root))
        manifests = session.matched_trio(roots)
        if set(adapters) != session.LANGUAGES:
            raise ValueError('all three language adapters are required')
        for language, adapter in adapters.items():
            if adapter['language'] != language:
                raise ValueError('adapter language mismatch')
            verify_adapter(adapter)
        if manifests[0]['record_kind'] in ('agent', 'calibration') and manifests[0]['arm'] == 'main':
            from .guardian_adapter import require
            require(adapters['zig'])
        identities = {}
        for root, manifest in zip(roots, manifests, strict=True):
            index = manifest['final_submission']
            row = manifest['submissions'][index] if index is not None else None
            if row:
                verify_snapshot(root / 'submissions' / f'{index:03}' / 'source', row['source'])
            identities[manifest['language']] = {'session_sha256': digest(manifest),
                                                'source_sha256': row['source']['sha256'] if row else None,
                                                'environment': environment_receipt.grading_evidence(root, manifest)}
        plan = {'version': 'application-grading-v2', 'cohort': manifests[0]['cohort'],
                'block': manifests[0]['block'], 'record_kind': manifests[0]['record_kind'],
                'pair_id': manifests[0].get('pair_id', manifests[0]['block']),
                'grader': grader_identity, 'input': input_receipt, 'expected': expected,
                'participants': identities,
                'adapters': {language: adapter['sha256'] for language, adapter in adapters.items()}}
        plan_file = directory / 'plan.json'
        if plan_file.exists():
            if read_json(plan_file) != plan:
                raise ValueError('frozen grading plan changed; new seeds or participants are not allowed')
        else:
            write_json(plan_file, plan)
        outcomes = {}
        for root, manifest in zip(roots, manifests, strict=True):
            language = manifest['language']
            result_file = directory / (language + '.json')
            if result_file.exists():
                result = read_json(result_file)
                if result.get('plan_sha256') != digest(plan):
                    raise ValueError('grading result identity mismatch')
                outcomes[language] = result
                continue
            index = manifest['final_submission']
            row = manifest['submissions'][index] if index is not None else None
            if row is None:
                result = {'accepted': False, 'reason': 'no-submission'}
            elif row['scope_violations']:
                result = {'accepted': False, 'reason': 'source-boundary', 'violations': row['scope_violations']}
            else:
                execution = directory / (language + '-execution')
                if execution.exists():
                    # Preserve interrupted work; never silently reuse or delete it.
                    raise ValueError('unfinished grading execution requires explicit recovery: ' + str(execution))
                record = evaluate(root / 'submissions' / f'{index:03}' / 'source', row['source'],
                                  adapters[language], request, execution, request_bytes=request_bytes, build_reuse=build_reuse)
                behavior_passed = correct(record['outcome'], expected)
                checked_in_time = (row['check'] is not None and row['check'].get('passed') is True and
                                   session.elapsed(manifest['task_started'], row['check']['finished']) <= manifest['budgets']['task_seconds'])
                result = {'accepted': behavior_passed and checked_in_time,
                          'behavior_passed': behavior_passed, 'development_accepted_in_budget': checked_in_time,
                          'reason': record['outcome']['phase'], 'execution': record}
            result.update(plan_sha256=digest(plan), language=language,
                          record_kind=manifest['record_kind'], participant=manifest['participant'],
                          participant_seconds=manifest['participant_seconds'],
                          preparation_seconds=manifest['preparation']['elapsed_seconds'])
            write_json(result_file, result)
            outcomes[language] = result
        report = {'version': 'application-block-result-v2', 'record_kind': plan['record_kind'],
                  'block': plan['block'], 'pair_id': plan['pair_id'], 'plan_sha256': digest(plan), 'outcomes': outcomes,
                  'comparative_claim': False}
        write_json(directory / 'result.json', report)
        return report
