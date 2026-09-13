"""Cohort coordinator for matched files/store arms. Convenience only; the frozen runner owns all clocks and validation.

Usage: python3 -B experiments/development_velocity/cohort/coordinate.py --study DIR --cohort NAME [--prefix LABEL] ACTION ARG
Actions: prepare N | watch N | grade N | status N | packet TASK | ingest TASK, with N the 1-based dispatch index.
The copy that ran declaration-store-dev-20260908/development-001 is retained in that study directory.
"""
import hashlib
import json
from pathlib import Path
import sys
import time

sys.path.insert(0, '/home/epentland/ai/canopy/mylang')
from experiments.development_velocity import runner
from experiments.application_comparison import iteration_log
from experiments.application_comparison.storage import path_identity, write_json, snapshot

STUDY = None
ROOT = None
PROMPTS = None
PREFIX = 'ds'
REPO = '/home/epentland/ai/canopy/mylang'
TEMPLATES = {'files': Path(REPO) / 'experiments/development_velocity/PROMPT-FILES.md',
             'store': Path(REPO) / 'experiments/development_velocity/PROMPT-STORE.md'}
HANDOFF = {
    'files': 'The timed application is now active. Use your existing bridge to read .trial-public/TASK.md, PROCESS.md, WORKFLOW.md and QUALITY.md plus the supplied language/library guides. Implement the complete task, run the required public check against final source, and finish completed. If unable to complete, finish abandoned. All application work must remain within the bridge and the declared scope.',
    'store': 'The timed application is now active. Use your existing bridge: open to list declarations and documents, asset to read TASK.md, PROCESS.md, WORKFLOW.md and QUALITY.md plus the supplied language/library guides, context to read the application declarations. Implement the complete task with batch, run the required public check against the final branch, and finish completed. If unable to complete, finish abandoned. All application work must remain within the bridge and the declared scope.',
}


def item(index):
    row = runner.registered(ROOT)['configuration']['dispatch_order'][index - 1]
    return row, f'{PREFIX}_{index:02}_{row["arm"]}'


def attempt_dir(row):
    return ROOT / row['task'] / row['pair'] / row['arm']


def agent_name(label):
    """Launcher-safe context name; preserve canonical arm and prompt paths."""
    return label.replace('-', '_')


def prepare(index):
    row, label = item(index)
    result = runner.prepare(ROOT, row['task'], row['pair'], row['arm'])
    PROMPTS.mkdir(exist_ok=True)
    content = (TEMPLATES[row['interface']].read_text().replace('COHORT_ROOT', str(ROOT))
               .replace('PARTICIPANT_TOKEN', result['token']).replace('REPOSITORY_ROOT', REPO)
               .replace('LANGUAGE', row['language']))
    assert result['token'] in content and str(ROOT) in content and 'REPOSITORY_ROOT' not in content
    doc = PROMPTS / (label + '.md')
    with doc.open('x') as stream:
        stream.write(content)
    message = f'Read the public onboarding instructions at {doc}. Follow them to complete practice, then wait for the task handoff exactly as they describe and complete the task.'
    record = dict(row, agent_name=agent_name(label), initial_message=message,
                  initial_message_sha256=hashlib.sha256(message.encode()).hexdigest(),
                  document=path_identity(doc), token=result['token'])
    write_json(PROMPTS / (label + '.json'), record)
    iteration_log.append(STUDY, 'participant-public-prompt', {k: record[k] for k in ('task', 'pair', 'arm', 'agent_name', 'initial_message_sha256', 'document')})
    return {'agent_name': agent_name(label), 'initial_message': message}


def bind(index):
    row, label = item(index)
    prompt = runner.read_json(PROMPTS / (label + '.json'))
    return runner.bind_context(ROOT, row['task'], row['pair'], row['arm'], '/root/' + agent_name(label), prompt['initial_message_sha256'])


def begin(index):
    row, label = item(index)
    message = HANDOFF[row['interface']]
    result = runner.begin(ROOT, row['task'], row['pair'], row['arm'], handoff=message)
    write_json(PROMPTS / (label + '-handoff.json'), dict(row, agent_name=agent_name(label), message=message,
               message_sha256=hashlib.sha256(message.encode()).hexdigest(), prepared_at=runner.utc(), started=result))
    return {'agent_name': agent_name(label), 'started': result}


def watch(index, limit=1500):
    """Wait for practice to finish, then bind the context and start the clock; the participant's await-handoff returns."""
    row, label = item(index)
    ready = attempt_dir(row) / 'practice-ready.json'
    deadline = time.monotonic() + limit
    while not ready.exists():
        if time.monotonic() > deadline:
            return {'agent_name': agent_name(label), 'watch': 'practice did not finish within the watch limit'}
        time.sleep(1)
    outcome = runner.read_json(ready)['outcome']
    if outcome != 'passed':
        return {'agent_name': agent_name(label), 'watch': 'practice outcome ' + outcome + '; not starting the task'}
    bound = bind(index)
    started = begin(index)
    return {'agent_name': agent_name(label), 'context_id': bound['context_id'], 'started': started['started']}


def grade(index):
    row, _ = item(index)
    return runner.grade(ROOT, row['task'], row['pair'], row['arm'])


def status(index):
    row, label = item(index)
    path = attempt_dir(row)
    manifest = runner.session.load(path)
    return dict(row, agent_name=agent_name(label), phase=manifest['phase'],
                practice_ready=(path / 'practice-ready.json').exists(),
                submissions=len(manifest['submissions']), seal_reason=manifest.get('seal_reason'),
                elapsed_seconds=runner.session.elapsed(manifest['task_started'], runner.session.clock())
                if manifest['phase'] == 'working' else manifest.get('participant_seconds'))


def packet(task):
    """Timing-blind review packet for one task: both sealed sources, no timings or private results."""
    runner.require_no_active_task(ROOT)
    directory = STUDY / 'review-packets' / task
    directory.mkdir(parents=True, exist_ok=False)
    entries = []
    reg = runner.registered(ROOT)
    for role in ('comparator', 'candidate'):
        arm = reg['configuration']['arms'][role]['label']
        attempt = ROOT / task / 'pair-01' / arm
        manifest = runner.session.load(attempt)
        if manifest['phase'] != 'sealed':
            raise ValueError('both attempts must be sealed')
        final = manifest['final_submission']
        if final is None:
            continue
        captured = snapshot(attempt / 'submissions' / f'{final:03}' / 'source', directory / arm)
        if captured != manifest['submissions'][final]['source']:
            raise ValueError('sealed source identity mismatch')
        entries.append({'arm': arm, 'source_sha256': captured['sha256'], 'directory': str(directory / arm)})
    write_json(directory / 'request.json', {'task': task, 'entries': entries, 'output': str(directory / 'review.json'),
        'rubric': 'Read each source directory .trial-public/QUALITY.md and TASK.md. Review source without timing or private results.'})
    iteration_log.append(STUDY, 'timing-blind-review-packet', {'task': task, 'packet': path_identity(directory / 'request.json'),
                         'timing_and_grading_results_included': False})
    return {'request': str(directory / 'request.json'), 'entries': [e['arm'] for e in entries]}


def ingest_review(task):
    directory = STUDY / 'review-packets' / task
    reviews = runner.read_json(directory / 'review.json')
    requested = runner.read_json(directory / 'request.json')['entries']
    if len(reviews) != len(requested) or {r['arm'] for r in reviews} != {r['arm'] for r in requested}:
        raise ValueError('incomplete or duplicate reviews')
    out = []
    for review in reviews:
        attempt = ROOT / task / 'pair-01' / review['arm']
        manifest = runner.session.load(attempt)
        if review['source_sha256'] != manifest['submissions'][manifest['final_submission']]['source']['sha256']:
            raise ValueError('review source identity mismatch')
        if review['version'] != 'development-source-review-v1' or review['decision'] not in ('approve', 'approve_with_nits', 'reject'):
            raise ValueError('invalid review decision')
        record = {k: review[k] for k in ('version', 'source_sha256', 'decision', 'findings')}
        write_json(attempt / 'source-review.json', record)
        iteration_log.append(STUDY, 'source-reviewed', {'task': task, 'arm': review['arm'], 'decision': review['decision'], 'findings': len(review['findings'])})
        out.append({'arm': review['arm'], 'decision': review['decision']})
    return out


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--study', required=True, type=Path)
    parser.add_argument('--cohort', required=True)
    parser.add_argument('--prefix', default='ds')
    parser.add_argument('action', choices=('prepare', 'bind', 'begin', 'watch', 'grade', 'status', 'packet', 'ingest'))
    parser.add_argument('arg')
    args = parser.parse_args()
    STUDY = args.study.resolve(strict=True)
    ROOT = STUDY / args.cohort
    PROMPTS = STUDY / 'public-prompts'
    PREFIX = args.prefix
    action, arg = args.action, args.arg
    fn = {'prepare': prepare, 'bind': bind, 'begin': begin, 'watch': watch, 'grade': grade, 'status': status,
          'packet': packet, 'ingest': ingest_review}[action]
    print(json.dumps(fn(int(arg) if action not in ('packet', 'ingest') else arg), ensure_ascii=False))
