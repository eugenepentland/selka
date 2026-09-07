"""Measured preparation/task phases and multi-file immutable submissions.

This is a coordinator API, not a participant-facing RPC service. Source becomes
available only at start_task; an agent gateway must enforce these phase mounts.
"""
from pathlib import Path
import time
from .storage import digest, inventory, locked, read_json, snapshot, source_files, verify_snapshot, write_json

LANGUAGES = frozenset(('my', 'python', 'zig'))


def clock():
    return {'utc_ns': time.time_ns(), 'monotonic_ns': time.monotonic_ns(),
            'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip()}


def elapsed(start, end):
    if start['boot_id'] != end['boot_id'] or end['monotonic_ns'] < start['monotonic_ns']:
        raise ValueError('session timing interrupted by clock/reboot change')
    return (end['monotonic_ns'] - start['monotonic_ns']) / 1_000_000_000


def load(root):
    manifest = read_json(Path(root) / 'session.json')
    if manifest['version'] != 'application-session-v2':
        raise ValueError('unknown session format')
    verify_snapshot(Path(root) / 'baseline', manifest['baseline'])
    return manifest


def save(root, manifest, event, **details):
    events = manifest['events']
    prior = events[-1]['sha256'] if events else None
    item = {'sequence': len(events), 'event': event, 'at': clock(), 'details': details, 'previous': prior}
    events.append(dict(item, sha256=digest(item)))
    write_json(Path(root) / 'session.json', manifest)


def prepare(root, baseline, *, language, block, cohort, participant, model,
            arm='main', kind='fixture', preparation_seconds=1200, task_seconds=1800,
            max_submissions=20, protected=(), pair_id=None, environment_sha256=None, trial_configuration_sha256=None, coordinator_sha256=None, max_reported_tokens_per_phase=None):
    if language not in LANGUAGES or arm not in ('main', 'language-focused') or kind not in ('fixture', 'calibration', 'agent'):
        raise ValueError('invalid session condition')
    if any(type(value) is not int or value <= 0 for value in (preparation_seconds, task_seconds, max_submissions)):
        raise ValueError('session budgets must be positive integers')
    if not all(isinstance(value, str) and value for value in (block, cohort, participant, model)):
        raise ValueError('session identities must be explicit')
    if pair_id is not None and (not isinstance(pair_id, str) or not pair_id):
        raise ValueError('matched attempt identity must be nonempty')
    if max_reported_tokens_per_phase is not None and (type(max_reported_tokens_per_phase) is not int or max_reported_tokens_per_phase <= 0):
        raise ValueError('reported token limit must be a positive integer')
    if coordinator_sha256 is not None and (not isinstance(coordinator_sha256, str) or
            len(coordinator_sha256) != 64 or any(c not in '0123456789abcdef' for c in coordinator_sha256)):
        raise ValueError('invalid coordinator identity')
    if trial_configuration_sha256 is not None and (not isinstance(trial_configuration_sha256, str) or
            len(trial_configuration_sha256) != 64 or any(c not in '0123456789abcdef' for c in trial_configuration_sha256)):
        raise ValueError('invalid trial configuration identity')
    if environment_sha256 is not None and (not isinstance(environment_sha256, str) or
            len(environment_sha256) != 64 or any(c not in '0123456789abcdef' for c in environment_sha256)):
        raise ValueError('invalid environment identity')
    root = Path(root)
    root.mkdir(parents=True, exist_ok=False)
    receipt = snapshot(baseline, root / 'baseline')
    protected = tuple(protected)
    if any(name not in receipt['files'] for name in protected):
        raise ValueError('protected file missing from baseline')
    (root / 'submissions').mkdir()
    (root / 'practice').mkdir()
    manifest = {'version': 'application-session-v2', 'phase': 'prepared', 'language': language,
                'block': block, 'cohort': cohort, 'participant': participant, 'model': model,
                'pair_id': block if pair_id is None else pair_id,
                'arm': arm, 'record_kind': kind, 'baseline': receipt,
                'protected': {name: receipt['files'][name] for name in protected},
                'budgets': {'preparation_seconds': preparation_seconds, 'task_seconds': task_seconds,
                            'max_submissions': max_submissions}, 'events': [], 'submissions': []}
    if environment_sha256 is not None:
        manifest['environment_sha256'] = environment_sha256
    if trial_configuration_sha256 is not None:
        manifest['trial_configuration_sha256'] = trial_configuration_sha256
    if coordinator_sha256 is not None:
        manifest['coordinator_sha256'] = coordinator_sha256
    if max_reported_tokens_per_phase is not None:
        manifest['max_reported_tokens_per_phase'] = max_reported_tokens_per_phase
    save(root, manifest, 'prepared')
    return manifest


def start_preparation(root):
    with locked(root):
        manifest = load(root)
        if manifest['phase'] != 'prepared':
            raise ValueError('preparation already started or session ended')
        manifest.update(phase='preparing', preparation_started=clock())
        save(root, manifest, 'preparation-started')
        return manifest


def start_task(root, practice_outcome):
    with locked(root):
        manifest = load(root)
        if manifest['phase'] != 'preparing' or practice_outcome not in ('passed', 'failed', 'budget'):
            raise ValueError('task requires a recorded preparation outcome')
        now = clock()
        preparation = elapsed(manifest['preparation_started'], now)
        manifest['preparation'] = {'elapsed_seconds': preparation, 'outcome': practice_outcome,
                                   'budget_exceeded': preparation > manifest['budgets']['preparation_seconds']}
        # Failure at practice does not remove the participant from the cohort.
        manifest.update(phase='working', task_started=now)
        snapshot(Path(root) / 'baseline', Path(root) / 'work')
        save(root, manifest, 'task-started', preparation=manifest['preparation'])
        return manifest


def submit(root):
    with locked(root):
        manifest = load(root)
        if manifest['phase'] != 'working':
            raise ValueError('only active tasks can submit')
        if elapsed(manifest['task_started'], clock()) >= manifest['budgets']['task_seconds']:
            raise ValueError('task time budget exhausted')
        submissions = manifest['submissions']
        if len(submissions) >= manifest['budgets']['max_submissions']:
            raise ValueError('submission budget exhausted')
        directory = Path(root) / 'submissions' / f'{len(submissions):03}'
        directory.mkdir(exist_ok=False)
        receipt = snapshot(Path(root) / 'work', directory / 'source')
        violations = [name for name, expected in manifest['protected'].items()
                      if receipt['files'].get(name) != expected]
        row = {'index': len(submissions), 'source': receipt, 'submitted': clock(),
               'elapsed_seconds': elapsed(manifest['task_started'], clock()),
               'scope_violations': violations, 'check': None}
        if row['elapsed_seconds'] >= manifest['budgets']['task_seconds']:
            row['scope_violations'].append('task-budget-exceeded-during-capture')
        prior = submissions[-1]['source']['files'] if submissions else manifest['baseline']['files']
        row['changed_files'] = sorted(name for name in set(prior) | set(receipt['files'])
                                      if prior.get(name) != receipt['files'].get(name))
        submissions.append(row)
        save(root, manifest, 'submitted', index=row['index'], sha256=receipt['sha256'])
        return row


def record_check(root, index, result):
    """Record a trusted coordinator check against a specific frozen submission."""
    with locked(root):
        manifest = load(root)
        if manifest['phase'] != 'working' or not 0 <= index < len(manifest['submissions']):
            raise ValueError('invalid check target')
        row = manifest['submissions'][index]
        verify_snapshot(Path(root) / 'submissions' / f'{index:03}' / 'source', row['source'])
        if row['check'] is not None:
            raise ValueError('check result already recorded')
        if type(result.get('passed')) is not bool:
            raise ValueError('check must explicitly report passed as a boolean')
        if result.get('source_sha256') != row['source']['sha256']:
            raise ValueError('check result refers to another source')
        row['check'] = dict(result, finished=clock())
        save(root, manifest, 'check-recorded', index=index)


def seal(root, reason):
    with locked(root):
        manifest = load(root)
        if manifest['phase'] != 'working' or reason not in ('completed', 'budget', 'abandoned'):
            raise ValueError('invalid seal state or reason')
        now = clock()
        duration = elapsed(manifest['task_started'], now)
        submissions = manifest['submissions']
        latest = submissions[-1] if submissions else None
        if reason == 'completed':
            if not latest or latest['check'] is None or latest['scope_violations']:
                raise ValueError('completion requires a checked in-scope submission')
            current = inventory(source_files(Path(root) / 'work'))
            if current != latest['source']['files']:
                raise ValueError('final edits have not been submitted and checked')
            if duration >= manifest['budgets']['task_seconds']:
                raise ValueError('completed claim exceeds task budget; seal as budget')
        manifest.update(phase='sealed', sealed=now, seal_reason=reason,
                        participant_seconds=duration, final_submission=latest['index'] if latest else None)
        save(root, manifest, 'sealed', reason=reason)
        return manifest


def matched_trio(roots):
    if len(roots) != 3:
        raise ValueError('grading requires three sealed languages')
    manifests = [load(root) for root in roots]
    if {item['language'] for item in manifests} != LANGUAGES:
        raise ValueError('grading requires my, python and zig exactly once')
    if any(item['phase'] != 'sealed' for item in manifests):
        raise ValueError('all three submissions must be sealed before grading')
    for field in ('block', 'cohort', 'model', 'arm', 'record_kind', 'budgets'):
        if any(item[field] != manifests[0][field] for item in manifests[1:]):
            raise ValueError('unmatched comparison field: ' + field)
    if any(item.get('pair_id', item['block']) != manifests[0].get('pair_id', manifests[0]['block'])
           for item in manifests[1:]):
        raise ValueError('unmatched comparison field: pair_id')
    return manifests
