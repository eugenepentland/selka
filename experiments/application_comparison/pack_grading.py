"""Exercise complete draft grading packs against sealed fixture trios only."""
from pathlib import Path
from . import grading, session, task_pack
from .inputs import decode_case
from .build_reuse import BuildReuse
from .storage import digest, locked, read_json, write_json


def grade_fixture(pack, roots, adapters, directory):
    return _grade(pack, roots, adapters, directory, kind='fixture')


def grade_calibration(pack, roots, adapters, directory):
    return _grade(pack, roots, adapters, directory, kind='calibration')


def _grade(pack, roots, adapters, directory, *, kind):
    manifest = task_pack.load(pack)
    participants = session.matched_trio(roots)
    if any(item['record_kind'] != kind or item['block'] != manifest['task'] for item in participants):
        raise ValueError(f'draft pack requires a matching {kind} trio; agent scoring is disabled')
    cases = read_json(Path(pack) / 'hidden/cases.json')
    directory = Path(directory)
    directory.mkdir(exist_ok=True)
    with locked(directory):
        plan = {'version': 'draft-pack-grading-v1', 'execution_policy': 'suite-build-reuse-v1', 'pack_sha256': manifest['sha256'],
                'sessions': {item['language']: digest(item) for item in participants},
                'adapters': {language: adapter['sha256'] for language, adapter in adapters.items()}}
        if kind == 'calibration':
            plan['record_kind'] = kind
        plan_file = directory / 'plan.json'
        if plan_file.exists() and read_json(plan_file) != plan:
            raise ValueError('draft pack grading plan changed')
        write_json(plan_file, plan)
        results = []
        builds = BuildReuse()
        for index, item in enumerate(cases):
            request, raw, expected = decode_case(item['case'])
            result = grading.grade(roots, adapters, request, expected, directory / f'case-{index:03}',
                                   grader_identity='task-pack:' + manifest['sha256'], request_bytes=raw, build_reuse=builds)
            results.append({'name': item['name'], 'result': result})
        if task_pack.load(pack) != manifest:
            raise ValueError('task pack changed during grading')
        outcomes = {language: {'accepted': all(row['result']['outcomes'][language]['accepted'] for row in results),
                               'failed_cases': [row['name'] for row in results
                                                if not row['result']['outcomes'][language]['accepted']]}
                    for language in session.LANGUAGES}
        report = {'version': 'draft-pack-result-v1', 'record_kind': kind,
                  'plan_sha256': digest(plan), 'case_count': len(cases), 'outcomes': outcomes,
                  'cases': results, 'comparative_claim': False}
        write_json(directory / 'result.json', report)
        return report
