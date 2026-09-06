"""Post-seal grading plans preserve common paired cases and resumable raw outcomes."""
from contextlib import ExitStack
import secrets
import shutil

import cases
import execution
from storage import digest, inventory, locked, read_json, utc, write_json


def comparable(left, right):
    if {left['language'], right['language']} != {'guest', 'zig'}:
        raise ValueError('a pair requires one guest and one Zig submission')
    for field in ('task', 'model', 'record_kind', 'harness', 'base_files', 'compiler_files', 'max_edits', 'max_checks'):
        if left[field] != right[field]:
            raise ValueError('pair configuration mismatch: ' + field)
    for tool in left['tools']:
        if left['tools'][tool]['sha256'] != right['tools'][tool]['sha256']:
            raise ValueError('pair tool mismatch: ' + tool)
    if left['record_kind'] == 'agent' and left['participant'] == right['participant']:
        raise ValueError('paired agent trials require separate participants')


def snapshots(root, rows):
    for row in rows:
        submitted = root / 'attempts' / f'{row["index"]:03}'
        if inventory(submitted / 'source') != read_json(submitted / 'snapshot.json'):
            raise ValueError('recorded source snapshot changed')


def plan(roots, manifests):
    members = sorted(str(root) for root in roots)
    existing = [manifest['grading_plan'] for manifest in manifests if 'grading_plan' in manifest]
    if existing:
        result = existing[0]
        if any(item != result for item in existing) or result['members'] != members:
            raise ValueError('submission belongs to a different grading plan')
        return result
    return {'seed': secrets.token_hex(32), 'generated': utc(), 'members': members,
            'paired': len(roots) == 2, 'sealed': [manifest['sealed'] for manifest in manifests]}


def one(root, manifest, rows, inputs):
    grading = root / 'grading'
    grading.mkdir(exist_ok=True)
    if not (grading / 'cases.json').exists():
        write_json(grading / 'cases.json', inputs)
    elif read_json(grading / 'cases.json') != inputs:
        raise ValueError('grading cases changed')
    results = []
    for row in rows:
        submitted = root / 'attempts' / f'{row["index"]:03}'
        destination = grading / f'{row["index"]:03}'
        destination.mkdir(exist_ok=True)
        saved = destination / 'result.json'
        if saved.exists():
            result = read_json(saved)
            if result['candidate_sha256'] != row['candidate_sha256']:
                raise ValueError('grading result does not match submission')
        else:
            runs = destination / 'runs'
            runs.mkdir(exist_ok=True)
            trial = runs / f'{len(list(runs.iterdir())):03}'
            trial.mkdir()
            shutil.copytree(submitted / 'source', trial / 'source')
            outcome = (row['outcome'] if row['outcome']['phase'] == 'source-boundary' else
                       execution.evaluate(trial, manifest, inputs))
            result = {'index': row['index'], 'candidate_sha256': row['candidate_sha256'], 'outcome': outcome}
            write_json(saved, result)
        results.append(result)
    first_edit = next((row['index'] for row in rows if row['edited_submission']), None)
    report = {'version': 1, 'kind': manifest['record_kind'], 'participant': manifest['participant'],
              'model': manifest['model'], 'language': manifest['language'], 'task': manifest['task'],
              'finish_reason': manifest['finish_reason'], 'grading_plan': manifest['grading_plan'],
              'participant_started': manifest.get('participant_started'), 'sealed': manifest['sealed'],
              'cases_sha256': digest(grading / 'cases.json'), 'attempts': results,
              'check_invocations': len(rows), 'edited_submissions': sum(row['edited_submission'] for row in rows),
              'first_edited_submission_passed': results[first_edit]['outcome']['passed'] if first_edit is not None else None,
              'final_passed': results[-1]['outcome']['passed'], 'comparative_claim': None}
    write_json(grading / 'report.json', report)
    manifest.update(status='graded', graded=utc())
    write_json(root / 'manifest.json', manifest)
    return report


def grade(root, validated, attempts, peer=None):
    roots = sorted({root, peer} if peer else {root})
    if peer == root:
        raise ValueError('paired submissions must be distinct')
    with ExitStack() as stack:
        for member in roots:
            stack.enter_context(locked(member))
        manifests = [validated(member) for member in roots]
        if all(manifest['status'] == 'graded' for manifest in manifests):
            raise ValueError('grade can run only once; retained completed results are authoritative')
        for manifest in manifests:
            if manifest['status'] not in ('sealed', 'grading', 'graded'):
                raise ValueError('grade requires sealed submissions')
        if len(manifests) == 2:
            comparable(*manifests)
        submissions = [attempts(member) for member in roots]
        for member, rows in zip(roots, submissions, strict=True):
            snapshots(member, rows)
        common = plan(roots, manifests)
        inputs = cases.units(common['seed']) if manifests[0]['task'] == 'units' else cases.boards(common['seed'])
        for member, manifest in zip(roots, manifests, strict=True):
            manifest['grading_plan'] = common
            if manifest['status'] != 'graded':
                manifest['status'] = 'grading'
            write_json(member / 'manifest.json', manifest)
        reports = [one(member, manifest, rows, inputs) for member, manifest, rows in zip(roots, manifests, submissions, strict=True)]
        return reports[0] if len(reports) == 1 else {'paired': True, 'reports': reports, 'comparative_claim': None}
