"""Freeze, launch and retain matched attempts using the established isolated gateway.

Coordinator module. Participants invoke its CLI only; never inspect its source,
configuration, private cases, other attempts or previous results.
"""
import argparse
from datetime import datetime, timezone
from functools import wraps
import json
from pathlib import Path
import random
import re
import secrets
import shutil
import sys
import time

from experiments.application_comparison import (
    iteration_log, practice_pack, public_verification, session,
)
from experiments.application_comparison.execution import freeze_adapter, verify_adapter
from experiments.application_comparison.isolation import Limits
from experiments.application_comparison.preparation_gateway import PreparationGateway
from experiments.application_comparison.storage import (
    digest, inventory, locked, path_identity, read_json, snapshot, source_files,
    verify_snapshot, write_json,
)
from . import analysis, telemetry
from .corpus import catalog, pack

REPO = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LIMITS = Limits(wall_seconds=90, cpu_seconds=90, memory_bytes=4 * 1024 ** 3,
                output_bytes=16 * 1024 ** 2)


def utc():
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')


def coordinator_locked(function):
    @wraps(function)
    def wrapper(root, *args, **kwargs):
        with locked(root):
            return function(root, *args, **kwargs)
    return wrapper


def require_no_active_task(root):
    if any(read_json(path)['phase'] == 'working' for path in Path(root).glob('*/pair-*/*/session.json')):
        raise ValueError('wait for the active timed task before preparation or private grading')


def source_identity():
    paths = list((REPO / 'experiments/application_comparison').glob('*.py'))
    paths += list(HERE.glob('*.py')) + list((HERE / 'corpus').glob('*.py'))
    return {str(path.relative_to(REPO)): path_identity(path)['sha256'] for path in sorted(paths)}


def freeze(study, cohort_name, readiness_path, *, pairs=1):
    """No task clocks start here. All construction checks must already pass."""
    study = Path(study).resolve(strict=True)
    if type(pairs) is not int or not 1 <= pairs <= 20:
        raise ValueError('pairs must be 1..20')
    if not cohort_name or Path(cohort_name).name != cohort_name or cohort_name in ('.', '..'):
        raise ValueError('plain cohort name required')
    readiness = read_json(readiness_path)
    for field in ('runtime_verified', 'library_verified', 'starters_verified', 'cases_reviewed'):
        if readiness.get(field) is not True:
            raise ValueError('preparation incomplete: ' + field)
    if set(readiness['tasks']) != set(catalog.IDS):
        raise ValueError('readiness must cover every registered task')
    for proof in readiness['proofs']:
        if path_identity(proof['path']) != proof:
            raise ValueError('readiness proof changed')
    if not readiness['proofs']:
        raise ValueError('preparation proof receipts required')
    root = study / cohort_name
    root.mkdir(exist_ok=False)
    write_json(root / 'readiness.json', readiness)
    toolchain = root / 'tools'
    toolchain.mkdir()
    for name in ('mylang', 'mylang-io'):
        shutil.copy2(REPO / 'zig-out/bin' / name, toolchain / name)
    shutil.copytree(REPO / 'src/stdlib', toolchain / 'stdlib')
    shutil.copytree(REPO / 'scripts', toolchain / 'workflow', ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copy2(HERE / 'runtime/profile_python.py', toolchain / 'profile_python.py')
    toolchains = {
        'my': {'compiler': str(toolchain / 'mylang'), 'byte_io': str(toolchain / 'mylang-io'),
               'stdlib': str(toolchain / 'stdlib'), 'workflow': str(toolchain / 'workflow')},
        'python': {'profile_python': str(toolchain / 'profile_python.py')},
    }
    adapters = {
        'my': freeze_adapter('my', toolchains['my'], [{'phase': 'run', 'argv': [
            '/tools/byte_io', '--project', '/work', '--timings=json']}], LIMITS),
        'python': freeze_adapter('python', toolchains['python'], [{'phase': 'run', 'argv': [
            '/usr/bin/python3', '-B', '/tools/profile_python']}], LIMITS),
    }
    practice_receipts = {}
    for language in ('my', 'python'):
        practice_path = root / (language + '-frozen-practice')
        practice_pack.create(practice_path, language=language)
        practice_receipts[language] = path_identity(practice_path)
    configuration = {'version': 'development-cohort-v1', 'tools': toolchains, 'adapters': adapters,
                     'harness': source_identity(), 'readiness_sha256': digest(readiness),
                     'quality_rubric_sha256': path_identity(HERE / 'QUALITY.md')['sha256'],
                     'feedback_policy': 'bounded-16384-characters-full-raw-retained-v1',
                     'clock_policy': 'coordinator-start-before-task-handoff-v1',
                     'model': 'inherited-coding-agent-exact-serving-id-unavailable',
                     'model_identity': None, 'model_settings_source': 'inherited',
                     'system_python': path_identity('/usr/bin/python3'),
                     'system_environment': 'shared host namespace system mounts; not an immutable OS image',
                     'practice': practice_receipts,
                     'limits': LIMITS.__dict__, 'preparation_seconds': 1200,
                     'confinement': 'namespace commands; whole-agent access instruction-confined'}
    tasks, dispatch, frozen_inputs = [], [], {}
    randomizer = random.Random(20260908 + pairs)
    for item in catalog.catalog()['tasks']:
        task = item['id']
        directory = root / task
        directory.mkdir()
        pack.create(directory / 'pack', task, secrets.token_hex(32))
        cases = read_json(directory / 'pack/public/cases.json')
        public_verification.validate(cases)
        public_verification.validate(read_json(directory / 'pack/private/cases.json'))
        baselines = {}
        for language in ('my', 'python'):
            baseline = directory / (language + '-baseline')
            shutil.copytree(HERE / 'runtime' / language, baseline)
            starter = HERE / 'starters' / task / language
            if starter.exists():
                shutil.copytree(starter, baseline, dirs_exist_ok=True)
            elif item['kind'] == 'bugfix' or item['family'] == 'multi-module-maintenance':
                raise ValueError('equivalent maintenance starter missing: ' + task + '/' + language)
            shutil.copytree(directory / 'pack/public', baseline / '.trial-public')
            shutil.copy2(HERE / 'PARTICIPANT.md', baseline / '.trial-public/WORKFLOW.md')
            shutil.copy2(HERE / 'QUALITY.md', baseline / '.trial-public/QUALITY.md')
            if language == 'my':
                shutil.copy2(REPO / 'docs/current-language.md', baseline / '.trial-public/LANGUAGE.md')
                shutil.copy2(REPO / 'docs/stdlib-text-data.md', baseline / '.trial-public/TEXT-DATA.md')
                shutil.copy2(REPO / 'docs/borrow-syntax.md', baseline / '.trial-public/BORROWS.md')
                shutil.copy2(HERE / 'LIBRARY.md', baseline / '.trial-public/LIBRARY.md')
            baselines[language] = {'files': inventory(source_files(baseline))}
            baselines[language]['sha256'] = digest(baselines[language]['files'])
        frozen_inputs[task] = {'pack': path_identity(directory / 'pack'), 'baselines': {
            language: path_identity(directory / (language + '-baseline')) for language in ('my', 'python')}}
        variant_hash = digest({'task': task, 'contract': path_identity(directory / 'pack/public/TASK.md')['sha256'],
                               'process': path_identity(directory / 'pack/public/PROCESS.md')['sha256'],
                               'baselines': baselines, 'cases_sha256': path_identity(directory / 'pack/private/cases.json')['sha256']})
        pair_ids = [f'pair-{i + 1:02}' for i in range(pairs)]
        tasks.append({'task_id': task, 'variant_hash': variant_hash, 'family': item['family'],
                      'kind': item['kind'], 'budget_seconds': 1200 if item['tier'] == 'small' else 1800,
                      'pair_ids': pair_ids})
        for pair in pair_ids:
            languages = ['my', 'python']
            randomizer.shuffle(languages)
            dispatch.append([{'task': task, 'pair': pair, 'language': language} for language in languages])
    randomizer.shuffle(dispatch)
    configuration['dispatch_order'] = [item for pair in dispatch for item in pair]
    configuration['frozen_inputs'] = frozen_inputs
    registration = {'study_id': study.name, 'candidate_id': cohort_name, 'phase': 'development', 'look': 0,
                    'frozen_at': utc(), 'analysis': {'version': analysis.VERSION, 'seed': 20260908,
                    'bootstrap_samples': 20000, 'speed_margin': 1.0, 'quality_margin': 0.0},
                    'configuration': configuration, 'configuration_hash': digest(configuration),
                    'tasks': tasks, 'prior_variant_hashes': []}
    write_json(root / 'registration.json', {'registration': registration, 'sha256': digest(registration)})
    iteration_log.append(study, 'cohort-frozen', {'cohort': cohort_name, 'registration_sha256': digest(registration),
                                               'attempt_count': len(configuration['dispatch_order'])})
    return {'cohort': str(root), 'registration_sha256': digest(registration),
            'dispatch_order': configuration['dispatch_order']}


def registered(root):
    value = read_json(Path(root) / 'registration.json')
    reg = value['registration']
    if digest(reg) != value['sha256'] or digest(reg['configuration']) != reg['configuration_hash']:
        raise ValueError('registration changed')
    if source_identity() != reg['configuration']['harness']:
        raise ValueError('harness changed since freeze; create a new cohort')
    for adapter in reg['configuration']['adapters'].values():
        verify_adapter(adapter)
    if path_identity('/usr/bin/python3') != reg['configuration']['system_python']:
        raise ValueError('system Python interpreter changed')
    for identity in reg['configuration']['practice'].values():
        if path_identity(identity['path']) != identity:
            raise ValueError('frozen practice changed')
    return reg


def attempt_path(root, task, pair, language):
    reg = registered(root)
    matching = [row for row in reg['tasks'] if row['task_id'] == task and pair in row['pair_ids']]
    if len(matching) != 1 or language not in ('my', 'python'):
        raise ValueError('unregistered attempt')
    inputs = reg['configuration']['frozen_inputs'][task]
    for identity in [inputs['pack'], *inputs['baselines'].values()]:
        if path_identity(identity['path']) != identity:
            raise ValueError('frozen task inputs changed')
    return Path(root) / task / pair / language, reg, matching[0]


@coordinator_locked
def prepare(root, task, pair, language):
    require_no_active_task(root)
    attempt, reg, row = attempt_path(root, task, pair, language)
    attempt.parent.mkdir(exist_ok=True)
    baseline = Path(root) / task / (language + '-baseline')
    protected = [str(p.relative_to(baseline)) for p in baseline.rglob('*') if p.is_file() and (
        '.trial-public' in p.parts or p.name in ('main.my', 'main.py', 'io.my'))]
    config = reg['configuration']
    practice = attempt.parent / (language + '-practice-pack')
    shutil.copytree(config['practice'][language]['path'], practice)
    participant = '-'.join((reg['candidate_id'], task, pair, language))
    session.prepare(attempt, baseline, language=language, block=task, cohort=reg['candidate_id'],
                    participant=participant, model=config['model'], pair_id=pair, kind='calibration',
                    preparation_seconds=1200, task_seconds=int(row['budget_seconds']),
                    protected=protected, max_submissions=20)
    shutil.copytree(practice / 'starter', attempt / 'practice', dirs_exist_ok=True)
    shutil.copy2(practice / 'contract.md', attempt / 'practice/CONTRACT.md')
    session.start_preparation(attempt)
    write_json(attempt / 'registration-binding.json', {'registration_sha256': digest(reg),
               'variant_hash': row['variant_hash'], 'participant': participant})
    token = secrets.token_hex(16)
    write_json(attempt / 'participant-token.json', {'token': token, 'task': task, 'pair': pair,
               'language': language, 'registration_sha256': digest(reg)})
    iteration_log.append(Path(root).parent, 'attempt-prepared', {'cohort': Path(root).name,
                         'task': task, 'pair': pair, 'language': language, 'participant': participant})
    return {'phase': 'preparing', 'participant': participant, 'token': token}


def agent(root, token, operation, arguments):
    """Opaque routing keeps the future task name out of the onboarding prompt."""
    if not isinstance(token, str) or re.fullmatch('[0-9a-f]{32}', token) is None:
        raise ValueError('invalid participant token')
    matches = []
    for path in Path(root).glob('*/pair-*/*/participant-token.json'):
        row = read_json(path)
        if row['token'] == token:
            matches.append(row)
    if len(matches) != 1:
        raise ValueError('unknown or duplicate participant token')
    row = matches[0]
    reg = registered(root)
    if row['registration_sha256'] != digest(reg):
        raise ValueError('participant routing registration changed')
    return participant(root, row['task'], row['pair'], row['language'], operation, arguments)


@coordinator_locked
def begin(root, task, pair, language):
    attempt, reg, _ = attempt_path(root, task, pair, language)
    pending = []
    for entry in reg['configuration']['dispatch_order']:
        path = Path(root) / entry['task'] / entry['pair'] / entry['language'] / 'session.json'
        if not path.exists() or read_json(path)['phase'] != 'sealed':
            pending.append(entry)
    if not pending or pending[0] != {'task': task, 'pair': pair, 'language': language}:
        raise ValueError('follow the frozen dispatch order; retain unfinished attempts')
    ready = read_json(attempt / 'practice-ready.json')
    read_json(attempt / 'context-binding.json')
    if digest(session.load(attempt)) != ready['session_sha256']:
        raise ValueError('preparation changed after completion')
    verify_snapshot(attempt / 'practice', ready['source'])
    # The caller hands off only after this returns; never begin in participant finish.
    manifest = session.start_task(attempt, ready['outcome'])
    iteration_log.append(Path(root).parent, 'attempt-started', {'cohort': Path(root).name,
                         'task': task, 'pair': pair, 'language': language, 'at': manifest['task_started']})
    return {'phase': manifest['phase'], 'task_started': manifest['task_started']}


def bind_context(root, task, pair, language, context_id, prompt_sha256):
    attempt, reg, _ = attempt_path(root, task, pair, language)
    if not isinstance(context_id, str) or not context_id.startswith('/root/'):
        raise ValueError('coordinator observed agent context identifier required')
    if not isinstance(prompt_sha256, str) or re.fullmatch('[0-9a-f]{64}', prompt_sha256) is None:
        raise ValueError('initial public prompt hash required')
    if (attempt / 'context-binding.json').exists():
        raise ValueError('context already bound')
    for existing in Path(root).parent.glob('*/**/context-binding.json'):
        if read_json(existing)['context_id'] == context_id:
            raise ValueError('participant context already used in this study')
    record = {'version': 'observed-agent-context-v1', 'context_id': context_id,
              'prompt_sha256': prompt_sha256, 'fork_turns': 'none', 'model_override': None,
              'source': 'coordinator observation of collaboration.spawn_agent',
              'registration_sha256': digest(reg), 'recorded_at': utc(),
              'limitation': 'coordinator attestation; no provider-side context or serving-model telemetry'}
    write_json(attempt / 'context-binding.json', record)
    return record


def participant(root, task, pair, language, operation, arguments):
    attempt, reg, _ = attempt_path(root, task, pair, language)
    cfg = reg['configuration']
    gateway = telemetry.ObservedGateway(attempt, cfg['tools'][language], LIMITS,
        adapter=cfg['adapters'][language], public_case=read_json(Path(root) / task / 'pack/public/cases.json'),
        retain_command_cache=True)
    manifest = session.load(attempt)
    if manifest['phase'] == 'preparing':
        for other in Path(root).glob('*/pair-*/*/session.json'):
            if read_json(other)['phase'] == 'working':
                raise ValueError('pause practice commands while a timed application is active')
        practice = attempt.parent / (language + '-practice-pack')
        preparation = PreparationGateway(gateway, cfg['adapters'][language], read_json(practice / 'cases.json'))
        if operation == 'finish':
            if arguments not in ({'reason': 'completed'}, {'reason': 'abandoned'}):
                raise ValueError('finish requires completed or abandoned reason')
            with locked(attempt):
                if (attempt / 'practice-ready.json').exists():
                    raise ValueError('practice already finished; await coordinator')
                checks = read_json(attempt / 'preparation-checks/checks.json')
                if arguments['reason'] == 'completed' and (not checks or not checks[-1]['passed']):
                    raise ValueError('practice requires passing public check')
                if arguments['reason'] == 'completed':
                    verify_snapshot(attempt / 'practice', checks[-1]['source'])
                current = inventory(source_files(attempt / 'practice'))
                outcome = ('budget' if session.elapsed(manifest['preparation_started'], session.clock()) >= 1200
                           else 'passed' if arguments['reason'] == 'completed' else 'failed')
                write_json(attempt / 'practice-ready.json', {'outcome': outcome,
                    'source': {'files': current, 'sha256': digest(current)},
                    'session_sha256': digest(session.load(attempt)), 'at': session.clock()})
            return {'phase': 'ready', 'message': 'Practice is complete. Stop and await the coordinator task handoff.'}
        if (attempt / 'practice-ready.json').exists():
            raise ValueError('practice already finished; await coordinator')
        return preparation.dispatch(operation, arguments)
    if manifest['phase'] != 'working':
        raise ValueError('attempt is not active')
    return gateway.dispatch(operation, arguments)


@coordinator_locked
def grade(root, task, pair, language):
    require_no_active_task(root)
    attempt, reg, _ = attempt_path(root, task, pair, language)
    manifest = session.load(attempt)
    if manifest['phase'] != 'sealed':
        raise ValueError('seal before private grading')
    directory = attempt / 'private-grading'
    if directory.exists():
        raise ValueError('private grading already exists; retain interrupted records and recover explicitly')
    final = manifest['final_submission']
    if final is None:
        directory.mkdir()
        result = {'passed': False, 'reason': 'no-submission'}
        write_json(directory / 'result.json', result)
    else:
        row = manifest['submissions'][final]
        source = attempt / 'submissions' / f'{final:03}' / 'source'
        verify_snapshot(source, row['source'])
        deadline = time.monotonic() + 7200
        result = public_verification.run(source, row['source'], reg['configuration']['adapters'][language],
                 read_json(Path(root) / task / 'pack/private/cases.json'), directory, lambda: deadline - time.monotonic())
    attempt_path(root, task, pair, language)  # Verify tools and private inputs again after execution.
    verification_pass = final is not None and manifest['submissions'][final]['check'] is not None and manifest['submissions'][final]['check']['passed']
    eligible = final is not None and not manifest['submissions'][final]['scope_violations'] and manifest['seal_reason'] == 'completed'
    passed = result['passed'] and verification_pass and eligible
    write_json(attempt / 'grading-summary.json', {'passed': passed, 'behavior_pass': result['passed'],
               'verification_pass': verification_pass, 'eligible': eligible, 'result_sha256': digest(result),
               'session_sha256': digest(manifest), 'registration_sha256': digest(reg)})
    profile = telemetry.summarize(attempt)
    write_json(attempt / 'profile.json', profile)
    iteration_log.append(Path(root).parent, 'attempt-graded', {'cohort': Path(root).name,
                         'task': task, 'pair': pair, 'language': language, 'passed': passed,
                         'application_seconds': manifest['participant_seconds'], 'profile_sha256': digest(profile)})
    return {'passed': passed, 'application_seconds': manifest['participant_seconds']}


def bounded_feedback(result, limit=16384):
    """Feedback shaping only; raw evidence is preserved by the gateway."""
    if type(limit) is not int or limit < 256:
        raise ValueError('feedback limit must be at least 256 characters')
    if len(json.dumps(result, ensure_ascii=False)) <= limit:
        return result
    result = dict(result)
    if 'diagnostics' in result:
        failures = {row['name'] for row in result.get('cases', []) if not row['passed']}
        result['diagnostics'] = [row for row in result['diagnostics'] if row.get('case') in failures]
    for key in ('stdout', 'stderr'):
        if len(result.get(key, '')) > limit // 4:
            value = result[key]
            result[key] = value[:limit // 8] + '\n... [middle omitted; full output retained] ...\n' + value[-limit // 8:]
            result[key + '_characters'] = len(value)
    encoded = json.dumps(result, ensure_ascii=False)
    if len(encoded) > limit:
        result = {'feedback_truncated': True, 'summary': '', 'full_evidence_retained': True}
        low, high = 0, min(len(encoded), limit)
        while low < high:
            middle = (low + high + 1) // 2
            result['summary'] = encoded[:middle]
            if len(json.dumps(result, ensure_ascii=False)) <= limit:
                low = middle
            else:
                high = middle - 1
        result['summary'] = encoded[:low]
        return result
    result = dict(result, feedback_truncated=True, full_evidence_retained=True)
    if len(json.dumps(result, ensure_ascii=False)) > limit:
        return bounded_feedback({'stdout': encoded}, limit)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('freeze', 'prepare', 'begin', 'bind-context', 'participant', 'agent', 'grade'))
    parser.add_argument('root', type=Path)
    parser.add_argument('--task'); parser.add_argument('--pair', default='pair-01')
    parser.add_argument('--language', choices=('my', 'python'))
    parser.add_argument('--cohort'); parser.add_argument('--readiness', type=Path)
    parser.add_argument('--pairs', type=int, default=1)
    parser.add_argument('--context-id'); parser.add_argument('--prompt-sha256')
    parser.add_argument('--token')
    parser.add_argument('--tool', choices=('command', 'check', 'finish', 'output'))
    parser.add_argument('--arguments', default='{}')
    args = parser.parse_args()
    if args.operation == 'freeze':
        result = freeze(args.root, args.cohort, args.readiness, pairs=args.pairs)
    elif args.operation == 'bind-context':
        result = bind_context(args.root, args.task, args.pair, args.language, args.context_id, args.prompt_sha256)
    elif args.operation == 'participant':
        result = participant(args.root, args.task, args.pair, args.language, args.tool, json.loads(args.arguments))
        result = bounded_feedback(result)
    elif args.operation == 'agent':
        result = bounded_feedback(agent(args.root, args.token, args.tool, json.loads(args.arguments)))
    else:
        result = {'prepare': prepare, 'begin': begin, 'grade': grade}[args.operation](args.root, args.task, args.pair, args.language)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
