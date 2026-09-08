"""Scripted, model-free exercise of both development-velocity arms end to end.

Coordinator driver, never a participant tool. It freezes a cohort with a files arm
and a declaration-store arm, prepares every attempt, completes onboarding practice
with the three known practice repairs, performs one minimal real interaction per
task in each arm, seals, grades and projects. It does not attempt to solve any
task: every attempt is expected to end abandoned. Its purpose is to execute every
code path of both interfaces against the real compiler, adapter and store, so a
projection can be validated before any model participant is dispatched.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time

from experiments.application_comparison import iteration_log
from experiments.application_comparison.storage import path_identity, read_json, write_json
from . import report, runner

ARMS = [{'label': 'my-files', 'language': 'my', 'interface': 'files'},
        {'label': 'my-store', 'language': 'my', 'interface': 'store'}]
# The three onboarding repairs, in the authored text and in the store's canonical text.
FILES_REPAIRS = (('helper::multiply(6)', 'helper::multiply(7)'),
                 ('return missing_nine;', 'return nine;'),
                 ('ParsedDigit.err(discard) => { return 0; }',
                  'ParsedDigit.err(discard) => { return -1; }'))
STORE_REPAIRS = (('helper::multiply(6)', 'helper::multiply(7)'),
                 ('return missing_nine;', 'return nine;'),
                 ('return 0;', 'return -1;'))
EDIT_SCRIPT = """import pathlib
path = pathlib.Path('main.my')
text = path.read_text()
for before, after in %r:
    assert text.count(before) == 1, before
    text = text.replace(before, after)
path.write_text(text)
print('practice repairs applied')
"""
READ_SCRIPT = "print(open('.trial-public/TASK.md').read()[:512])"
MARKER = ('// Dry-run marker declaration; no task behavior.\n'
          'fn dry_run_marker(value: i64) -> i64 {\n    return value;\n}\n')
# Onboarding practises the other two operation shapes before the clock: one add, one remove.
SCRATCH = ('// Onboarding scratch declaration; added and removed during practice.\n'
           'fn practice_scratch(value: i64) -> i64 {\n    return value;\n}\n')
HANDOFF = ('The timed application is now active. Use your existing bridge: read the task and '
           'process documents, implement the complete task, run the required public check '
           'against your final source, and finish completed.')


def repaired(text, repairs):
    for before, after in repairs:
        if text.count(before) != 1:
            raise ValueError('practice repair anchor is not unique: ' + before)
        text = text.replace(before, after)
    return text


def readiness(directory):
    """A fixture readiness record with a real proof receipt; never a scored authorization."""
    proof = Path(directory) / 'dry-run-proof.txt'
    proof.write_text('Scripted harness dry run. Not a participant record and not a launch authorization.\n')
    path = Path(directory) / 'readiness.json'
    write_json(path, {'runtime_verified': True, 'library_verified': True, 'starters_verified': True,
                      'cases_reviewed': True, 'tasks': list(runner.catalog.IDS),
                      'proofs': [path_identity(proof)]})
    return path


def practice(root, task, pair, arm, interface, token):
    """Complete onboarding: the repairs, the store's add/remove drill, a check, then ready."""
    if interface == 'files':
        edit = runner.agent(root, token, 'command',
                            {'purpose': 'edit', 'argv': ['/usr/bin/python3', '-B', '-c',
                                                         EDIT_SCRIPT % (FILES_REPAIRS,)]})
        if edit['returncode'] != 0:
            raise ValueError('practice edit failed: ' + edit['stderr'][:512])
    else:
        runner.agent(root, token, 'open', {})
        context = runner.agent(root, token, 'context', {'ids': ['main::answer']})
        entry = context['entries'][0]
        committed = runner.agent(root, token, 'batch', {
            'ops': [{'op': 'replace', 'id': 'main::answer',
                     'source': repaired(entry['source'], STORE_REPAIRS)}],
            'if_match': {'main::answer': entry['hash']}})
        if committed.get('status') != 'committed':
            raise ValueError('practice batch rejected: ' + json.dumps(committed)[:512])
        added = runner.agent(root, token, 'batch',
                             {'ops': [{'op': 'add', 'module': 'helper', 'source': SCRATCH}],
                              'if_match': {}})
        if added.get('status') != 'committed':
            raise ValueError('practice add rejected: ' + json.dumps(added)[:512])
        scratch = added['applied'][0]
        removed = runner.agent(root, token, 'batch',
                               {'ops': [{'op': 'remove', 'id': scratch['id']}],
                                'if_match': {scratch['id']: scratch['hash']}})
        if removed.get('status') != 'committed':
            raise ValueError('practice remove rejected: ' + json.dumps(removed)[:512])
    checked = runner.agent(root, token, 'check', {})
    if not checked['passed']:
        raise ValueError('practice check failed: ' + json.dumps(checked)[:512])
    return runner.agent(root, token, 'finish', {'reason': 'completed'})


def interact(root, token, interface, operations):
    """One minimal real interaction per task; no attempt is made to solve it."""
    if interface == 'files':
        operations.append(runner.agent(root, token, 'command',
                                       {'purpose': 'inspect',
                                        'argv': ['/usr/bin/python3', '-B', '-c', READ_SCRIPT]}))
        operations.append(runner.agent(root, token, 'check', {}))
        return operations[-1]
    opened = runner.agent(root, token, 'open', {})
    operations.append(opened)
    writable = [row['module'] for row in opened['modules'] if not row['protected']]
    identifier = next(row['id'] for row in opened['declarations'] if not row['protected'])
    module = writable[0]
    operations.append(runner.agent(root, token, 'context', {'ids': [identifier]}))
    operations.append(runner.agent(root, token, 'search', {'text': 'return'}))
    operations.append(runner.agent(root, token, 'asset',
                                   {'name': '.trial-public/TASK.md', 'offset': 0, 'limit': 2048}))
    committed = runner.agent(root, token, 'batch', {'ops': [{'op': 'add', 'module': module,
                                                             'source': MARKER}], 'if_match': {}})
    operations.append(committed)
    if committed.get('status') != 'committed':
        raise ValueError('marker batch rejected: ' + json.dumps(committed)[:512])
    operations.append(runner.agent(root, token, 'probe', {'request': {}}))
    operations.append(runner.agent(root, token, 'check', {}))
    return operations[-1]


def attempt(root, entry, index, log):
    task, pair, arm, interface = (entry[key] for key in ('task', 'pair', 'arm', 'interface'))
    started = time.monotonic()
    prepared = runner.prepare(root, task, pair, arm)
    token = prepared['token']
    practice(root, task, pair, arm, interface, token)
    workflow = Path(root) / task / (arm + '-baseline') / '.trial-public/WORKFLOW.md'
    runner.bind_context(root, task, pair, arm, f'/root/dry-run-{index:03}',
                        hashlib.sha256(workflow.read_bytes()).hexdigest())
    runner.begin(root, task, pair, arm, HANDOFF)
    operations = []
    checked = interact(root, token, interface, operations)
    reason = 'completed' if checked['passed'] else 'abandoned'
    sealed = runner.agent(root, token, 'finish', {'reason': reason})
    graded = runner.grade(root, task, pair, arm)
    row = {'task': task, 'pair': pair, 'arm': arm, 'interface': interface,
           'operations': len(operations), 'check_passed': bool(checked['passed']),
           'seal_reason': sealed.get('reason'), 'graded_pass': graded['passed'],
           'application_seconds': graded['application_seconds'],
           'wall_seconds': round(time.monotonic() - started, 3)}
    log.append(row)
    print(json.dumps(row), flush=True)
    return row


def run(study, cohort='store-dry-run'):
    started = time.monotonic()
    study = Path(study)
    study.parent.mkdir(parents=True, exist_ok=True)
    iteration_log.create(study, {'kind': 'scripted-harness-dry-run-not-agent-evaluation'})
    frozen = runner.freeze(study, cohort, readiness(study), pairs=1, arms=ARMS)
    root = Path(frozen['cohort'])
    print(json.dumps({'cohort': str(root), 'attempts': len(frozen['dispatch_order'])}), flush=True)
    log = []
    for index, entry in enumerate(frozen['dispatch_order']):
        attempt(root, entry, index, log)
    listing = report.inventory(root)
    output = root / 'dry-run-report'
    document, projection = report.project(root)
    output.mkdir(exist_ok=False)
    for name, value in (('analysis-input.json', document), ('summary.json', projection)):
        with (output / name).open('x') as stream:
            json.dump(value, stream, indent=2, sort_keys=True, allow_nan=False)
            stream.write('\n')
    (output / 'report.md').write_text(report.markdown(projection))
    result = {'version': 'store-harness-dry-run-v1', 'cohort': str(root), 'report': str(output),
              'wall_seconds': round(time.monotonic() - started, 3),
              'inventory_phases': sorted({row['phase'] for row in listing['attempts']}),
              'counts': projection['counts'], 'attempts': log,
              'cost_ratio': projection['aggregate']['cost_ratio'],
              'store_session_metrics': projection['observations']['store_session_metrics']}
    write_json(root / 'dry-run-result.json', result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('study', type=Path, help='a study directory outside the repository')
    parser.add_argument('--cohort', default='store-dry-run')
    arguments = parser.parse_args()
    print(json.dumps(run(arguments.study, arguments.cohort), indent=2))


if __name__ == '__main__':
    main()
