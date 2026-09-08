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
import tempfile
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
ROLES = ('candidate', 'comparator')
DEFAULT_ARMS = {'candidate': {'label': 'my', 'language': 'my', 'interface': 'files'},
                'comparator': {'label': 'python', 'language': 'python', 'interface': 'files'}}
STORE_TOOLS = {'store_importer': 'scripts/store.py', 'store_server': 'scripts/store_server.py'}


GATEWAYS = {'files': telemetry.ObservedGateway, 'store': telemetry.StoreGateway}
# Participant operations by interface; there is no command verb in the store arm.
# `await-handoff` belongs to both arms: it is the single-context bridge between
# onboarding practice and the timed task, not a source or execution operation.
HANDOFF = 'await-handoff'
OPERATIONS = {'files': ('command', 'check', 'finish', 'output', HANDOFF),
              'store': telemetry.STORE_VERBS + (HANDOFF,)}
# Onboarding in a store arm has to have committed each of these before the clock.
STORE_PRACTICE_OPS = ('add', 'remove')


def store_module(tools):
    """The frozen importer and renderer this cohort recorded, reached through its session server."""
    return telemetry.load_frozen(tools['store_server']).store


def import_store(module, database, compiler, source, *, edges=True):
    """One attempt store: import a tree as `base`, then branch `work` for the participant."""
    with module.Compiler(compiler) as tool:
        with module.Store(database, create=True, compiler=tool) as store:
            report = module.import_directory(store, tool, source, 'base', edges=edges)
            store.create_branch('base', 'work')
    return report


def canonicalize(directory, compiler, module):
    """Replace a `.my` tree by its store rendering so every arm receives identical source."""
    directory = Path(directory)
    with tempfile.TemporaryDirectory(prefix='store-canonical-') as temporary:
        database, rendered = Path(temporary) / 'canonical.sqlite', Path(temporary) / 'rendered'
        with module.Compiler(compiler) as tool:
            with module.Store(database, create=True, compiler=tool) as store:
                module.import_directory(store, tool, directory, 'base', edges=False)
                store.render_branch('base', rendered, compiler=tool)
        shutil.rmtree(directory)
        shutil.copytree(rendered, directory)
    return directory


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


def arm_definitions(arms):
    """Explicit arms as [comparator, candidate] or a role mapping; labels name directories."""
    if arms is None:
        arms = DEFAULT_ARMS
    if isinstance(arms, (list, tuple)):
        if len(arms) != 2:
            raise ValueError('arms must declare exactly one comparator and one candidate')
        arms = {'comparator': arms[0], 'candidate': arms[1]}
    if not isinstance(arms, dict) or set(arms) != set(ROLES):
        raise ValueError('arms must declare exactly one comparator and one candidate')
    result = {}
    for role in ROLES:
        arm = arms[role]
        if not isinstance(arm, dict) or set(arm) != {'label', 'language', 'interface'}:
            raise ValueError('each arm records label, language and interface')
        if not isinstance(arm['label'], str) or re.fullmatch('[a-z][a-z0-9-]{0,31}', arm['label']) is None:
            raise ValueError('arm label must be a plain lowercase name')
        if arm['language'] not in ('my', 'python') or arm['interface'] not in telemetry.INTERFACES:
            raise ValueError('unknown arm language or interface')
        result[role] = {key: arm[key] for key in ('label', 'language', 'interface')}
    if result['candidate']['label'] == result['comparator']['label']:
        raise ValueError('arm labels must be distinct')
    return result


def registered_arms(reg):
    """Legacy registrations without arms keep the literal my/python pair."""
    return arm_definitions(reg['configuration'].get('arms'))


def arm_row(reg, arm):
    for row in registered_arms(reg).values():
        if row['label'] == arm:
            return row
    raise ValueError('unregistered attempt')


def freeze(study, cohort_name, readiness_path, *, pairs=1, arms=None):
    """No task clocks start here. All construction checks must already pass."""
    study = Path(study).resolve(strict=True)
    arms = arm_definitions(arms)
    ordered = [arms[role] for role in ROLES]
    for arm in ordered:
        if arm['interface'] == 'store':
            for relative in STORE_TOOLS.values():
                if not (REPO / relative).is_file():
                    raise ValueError('store interface requires ' + relative +
                                     '; freeze a store arm only after the importer and session server exist')
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
    by_language = {
        'my': {'compiler': str(toolchain / 'mylang'), 'byte_io': str(toolchain / 'mylang-io'),
               'stdlib': str(toolchain / 'stdlib'), 'workflow': str(toolchain / 'workflow')},
        'python': {'profile_python': str(toolchain / 'profile_python.py')},
    }
    commands = {
        'my': [{'phase': 'run', 'argv': ['/tools/byte_io', '--project', '/work', '--timings=json']}],
        'python': [{'phase': 'run', 'argv': ['/usr/bin/python3', '-B', '/tools/profile_python']}],
    }
    toolchains, adapters, store_tools, practice_receipts = {}, {}, {}, {}
    for arm in ordered:
        label, language = arm['label'], arm['language']
        toolchains[label] = dict(by_language[language])
        if arm['interface'] == 'store':
            # The store server and importer are frozen with the rest of the workflow scripts.
            for name, relative in STORE_TOOLS.items():
                toolchains[label][name] = str(toolchain / 'workflow' / Path(relative).name)
            store_tools[label] = {name: path_identity(toolchains[label][name]) for name in STORE_TOOLS}
        # Verification adapters stay identical across arms of one language; only the
        # participant interface differs, and store scripts never mount into a check.
        adapters[label] = freeze_adapter(language, by_language[language], commands[language], LIMITS)
        practice_path = root / (label + '-frozen-practice')
        practice_pack.create(practice_path, language=language, interface=arm['interface'])
        practice_receipts[label] = path_identity(practice_path)
    configuration = {'version': 'development-cohort-v1', 'arms': arms, 'tools': toolchains,
                     'adapters': adapters,
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
    if store_tools:
        configuration['store_tools'] = store_tools
    # A store arm receives the branch rendering of its baseline. Every `.my` arm then
    # gets that same canonical source, so the arms differ only in their interface.
    canonical_my = any(arm['interface'] == 'store' and arm['language'] == 'my' for arm in ordered)
    store_source = store_module(next(toolchains[arm['label']] for arm in ordered
                                     if arm['interface'] == 'store')) if canonical_my else None
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
        # Baselines are per arm label, so each arm carries its own WORKFLOW.md. Arm
        # labels default to the language names, keeping legacy directory identities.
        for arm in ordered:
            label, language = arm['label'], arm['language']
            baseline = directory / (label + '-baseline')
            shutil.copytree(HERE / 'runtime' / language, baseline)
            starter = HERE / 'starters' / task / language
            if starter.exists():
                shutil.copytree(starter, baseline, dirs_exist_ok=True)
            elif item['kind'] == 'bugfix' or item['family'] == 'multi-module-maintenance':
                raise ValueError('equivalent maintenance starter missing: ' + task + '/' + language)
            if canonical_my and language == 'my':
                canonicalize(baseline, toolchain / 'mylang', store_source)
            shutil.copytree(directory / 'pack/public', baseline / '.trial-public')
            shutil.copy2(HERE / ('PARTICIPANT-STORE.md' if arm['interface'] == 'store' else 'PARTICIPANT.md'),
                         baseline / '.trial-public/WORKFLOW.md')
            shutil.copy2(HERE / 'QUALITY.md', baseline / '.trial-public/QUALITY.md')
            if language == 'my':
                shutil.copy2(REPO / 'docs/current-language.md', baseline / '.trial-public/LANGUAGE.md')
                shutil.copy2(REPO / 'docs/stdlib-text-data.md', baseline / '.trial-public/TEXT-DATA.md')
                shutil.copy2(REPO / 'docs/borrow-syntax.md', baseline / '.trial-public/BORROWS.md')
                shutil.copy2(HERE / 'LIBRARY.md', baseline / '.trial-public/LIBRARY.md')
            baselines[label] = {'files': inventory(source_files(baseline))}
            baselines[label]['sha256'] = digest(baselines[label]['files'])
        frozen_inputs[task] = {'pack': path_identity(directory / 'pack'), 'baselines': {
            arm['label']: path_identity(directory / (arm['label'] + '-baseline')) for arm in ordered}}
        variant_hash = digest({'task': task, 'contract': path_identity(directory / 'pack/public/TASK.md')['sha256'],
                               'process': path_identity(directory / 'pack/public/PROCESS.md')['sha256'],
                               'baselines': baselines, 'cases_sha256': path_identity(directory / 'pack/private/cases.json')['sha256']})
        pair_ids = [f'pair-{i + 1:02}' for i in range(pairs)]
        tasks.append({'task_id': task, 'variant_hash': variant_hash, 'family': item['family'],
                      'kind': item['kind'], 'budget_seconds': 1200 if item['tier'] == 'small' else 1800,
                      'pair_ids': pair_ids})
        for pair in pair_ids:
            order = list(ordered)
            randomizer.shuffle(order)
            dispatch.append([{'task': task, 'pair': pair, 'arm': arm['label'], 'language': arm['language'],
                              'interface': arm['interface']} for arm in order])
    randomizer.shuffle(dispatch)
    configuration['dispatch_order'] = [item for pair in dispatch for item in pair]
    configuration['frozen_inputs'] = frozen_inputs
    registration = {'study_id': study.name, 'candidate_id': cohort_name, 'phase': 'development', 'look': 0,
                    'frozen_at': utc(), 'analysis': {'version': analysis.version_for(configuration), 'seed': 20260908,
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
    for identities in reg['configuration'].get('store_tools', {}).values():
        for identity in identities.values():
            if path_identity(identity['path']) != identity:
                raise ValueError('frozen store tool changed')
    return reg


def attempt_path(root, task, pair, arm):
    """Attempts live at task/pair/<arm label>; arms of one language share a baseline."""
    reg = registered(root)
    matching = [row for row in reg['tasks'] if row['task_id'] == task and pair in row['pair_ids']]
    if len(matching) != 1:
        raise ValueError('unregistered attempt')
    arm_row(reg, arm)
    inputs = reg['configuration']['frozen_inputs'][task]
    for identity in [inputs['pack'], *inputs['baselines'].values()]:
        if path_identity(identity['path']) != identity:
            raise ValueError('frozen task inputs changed')
    return Path(root) / task / pair / arm, reg, matching[0]


@coordinator_locked
def prepare(root, task, pair, arm):
    require_no_active_task(root)
    attempt, reg, row = attempt_path(root, task, pair, arm)
    definition = arm_row(reg, arm)
    language = definition['language']
    attempt.parent.mkdir(exist_ok=True)
    baseline = Path(root) / task / (arm + '-baseline')
    protected = [str(p.relative_to(baseline)) for p in baseline.rglob('*') if p.is_file() and (
        '.trial-public' in p.parts or p.name in ('main.my', 'main.py', 'io.my'))]
    config = reg['configuration']
    practice = attempt.parent / (arm + '-practice-pack')
    shutil.copytree(config['practice'][arm]['path'], practice)
    participant = '-'.join((reg['candidate_id'], task, pair, arm))
    session.prepare(attempt, baseline, language=language, block=task, cohort=reg['candidate_id'],
                    participant=participant, model=config['model'], pair_id=pair, kind='calibration',
                    arm='declaration-store' if definition['interface'] == 'store' else 'main',
                    preparation_seconds=1200, task_seconds=int(row['budget_seconds']),
                    protected=protected, max_submissions=20)
    shutil.copytree(practice / 'starter', attempt / 'practice', dirs_exist_ok=True)
    shutil.copy2(practice / 'contract.md', attempt / 'practice/CONTRACT.md')
    if definition['interface'] == 'store':
        # Per-attempt stores, base and work. No `.my` source is placed under attempt/work:
        # the store is the only source channel, and `check` publishes its rendering there.
        module = store_module(config['tools'][arm])
        import_store(module, attempt / 'store.sqlite', config['tools'][arm]['compiler'], baseline)
        import_store(module, attempt / 'practice-store.sqlite', config['tools'][arm]['compiler'],
                     attempt / 'practice')
    session.start_preparation(attempt)
    write_json(attempt / 'registration-binding.json', {'registration_sha256': digest(reg),
               'variant_hash': row['variant_hash'], 'participant': participant})
    token = secrets.token_hex(16)
    write_json(attempt / 'participant-token.json', {'token': token, 'task': task, 'pair': pair,
               'arm': arm, 'registration_sha256': digest(reg)})
    iteration_log.append(Path(root).parent, 'attempt-prepared', {'cohort': Path(root).name,
                         'task': task, 'pair': pair, 'arm': arm, 'language': language,
                         'participant': participant})
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
    return participant(root, row['task'], row['pair'], row['arm'], operation, arguments)


def practiced_operations(attempt):
    """Batch operation kinds the onboarding store session actually committed."""
    directory = Path(attempt) / telemetry.STORE_PHASES['preparing']['session'] / 'records'
    kinds = set()
    for path in sorted(directory.glob('[0-9]' * 6 + '.json')) if directory.is_dir() else ():
        record = read_json(path)
        response = record.get('response') or {}
        if record.get('verb') == 'batch' and response.get('status') == 'committed':
            kinds.update(row['op'] for row in response.get('applied', ()))
    return sorted(kinds)


@coordinator_locked
def begin(root, task, pair, arm, handoff=None):
    attempt, reg, _ = attempt_path(root, task, pair, arm)
    pending = []
    for entry in reg['configuration']['dispatch_order']:
        path = Path(root) / entry['task'] / entry['pair'] / entry['arm'] / 'session.json'
        if not path.exists() or read_json(path)['phase'] != 'sealed':
            pending.append(entry)
    if not pending or (pending[0]['task'], pending[0]['pair'], pending[0]['arm']) != (task, pair, arm):
        raise ValueError('follow the frozen dispatch order; retain unfinished attempts')
    ready = read_json(attempt / 'practice-ready.json')
    read_json(attempt / 'context-binding.json')
    if digest(session.load(attempt)) != ready['session_sha256']:
        raise ValueError('preparation changed after completion')
    verify_snapshot(attempt / 'practice', ready['source'])
    if handoff is not None:
        # Stored before the clock starts: `await-handoff` returns exactly this text to a
        # participant waiting in its own context, so practice and the task share one context.
        if not isinstance(handoff, str) or not handoff.strip():
            raise ValueError('a handoff message is nonempty text')
        write_json(attempt / 'handoff.json', {'version': 'attempt-handoff-v1', 'text': handoff,
                                              'sha256': digest(handoff)})
    # The caller hands off only after this returns; never begin in participant finish.
    manifest = session.start_task(attempt, ready['outcome'])
    if arm_row(reg, arm)['interface'] == 'store':
        # Only the store holds this arm's source; `check` publishes its rendering here.
        for path in sorted((attempt / 'work').rglob('*.my')):
            path.unlink()
    iteration_log.append(Path(root).parent, 'attempt-started', {'cohort': Path(root).name,
                         'task': task, 'pair': pair, 'arm': arm, 'at': manifest['task_started']})
    return {'phase': manifest['phase'], 'task_started': manifest['task_started'],
            'handoff_sha256': None if handoff is None else digest(handoff)}


def bind_context(root, task, pair, arm, context_id, prompt_sha256):
    attempt, reg, _ = attempt_path(root, task, pair, arm)
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


def participant(root, task, pair, arm, operation, arguments):
    attempt, reg, _ = attempt_path(root, task, pair, arm)
    definition = arm_row(reg, arm)
    cfg = reg['configuration']
    gateway = GATEWAYS[definition['interface']](attempt, cfg['tools'][arm], LIMITS,
        adapter=cfg['adapters'][arm], public_case=read_json(Path(root) / task / 'pack/public/cases.json'),
        retain_command_cache=True)
    manifest = session.load(attempt)
    if operation == HANDOFF:
        # The participant waits here, in its own context, across the coordinator's `begin`.
        if manifest['phase'] not in ('preparing', 'working'):
            raise ValueError('this attempt is not awaiting a task handoff')
        return gateway.dispatch(operation, arguments)
    if manifest['phase'] == 'preparing':
        for other in Path(root).glob('*/pair-*/*/session.json'):
            if read_json(other)['phase'] == 'working':
                raise ValueError('pause practice commands while a timed application is active')
        practice = attempt.parent / (arm + '-practice-pack')
        preparation = PreparationGateway(gateway, cfg['adapters'][arm], read_json(practice / 'cases.json'))
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
                practiced = practiced_operations(attempt) if definition['interface'] == 'store' else []
                if arguments['reason'] == 'completed' and definition['interface'] == 'store':
                    missing = [name for name in STORE_PRACTICE_OPS if name not in practiced]
                    if missing:
                        raise ValueError('onboarding practice must commit each batch operation; '
                                         'still missing: ' + ', '.join(missing))
                current = inventory(source_files(attempt / 'practice'))
                outcome = ('budget' if session.elapsed(manifest['preparation_started'], session.clock()) >= 1200
                           else 'passed' if arguments['reason'] == 'completed' else 'failed')
                write_json(attempt / 'practice-ready.json', {'outcome': outcome,
                    'source': {'files': current, 'sha256': digest(current)},
                    'batch_operations': practiced,
                    'session_sha256': digest(session.load(attempt)), 'at': session.clock()})
            return {'phase': 'ready', 'message': 'Practice is complete. Stay in this context and call '
                    'await-handoff with {} until it returns phase working, then follow its message.'}
        if (attempt / 'practice-ready.json').exists():
            raise ValueError('practice already finished; await coordinator')
        if definition['interface'] == 'store':
            # Verbs are retained by the store gateway; its check hook uses this practice gateway.
            gateway.preparation = preparation
            return gateway.dispatch(operation, arguments)
        return preparation.dispatch(operation, arguments)
    if manifest['phase'] != 'working':
        raise ValueError('attempt is not active')
    return gateway.dispatch(operation, arguments)


@coordinator_locked
def grade(root, task, pair, arm):
    require_no_active_task(root)
    attempt, reg, _ = attempt_path(root, task, pair, arm)
    definition = arm_row(reg, arm)
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
        result = public_verification.run(source, row['source'], reg['configuration']['adapters'][arm],
                 read_json(Path(root) / task / 'pack/private/cases.json'), directory, lambda: deadline - time.monotonic())
    attempt_path(root, task, pair, arm)  # Verify tools and private inputs again after execution.
    verification_pass = final is not None and manifest['submissions'][final]['check'] is not None and manifest['submissions'][final]['check']['passed']
    eligible = final is not None and not manifest['submissions'][final]['scope_violations'] and manifest['seal_reason'] == 'completed'
    passed = result['passed'] and verification_pass and eligible
    write_json(attempt / 'grading-summary.json', {'passed': passed, 'behavior_pass': result['passed'],
               'verification_pass': verification_pass, 'eligible': eligible, 'result_sha256': digest(result),
               'session_sha256': digest(manifest), 'registration_sha256': digest(reg)})
    profile = telemetry.summarize(attempt, arm=arm, interface=definition['interface'])
    write_json(attempt / 'profile.json', profile)
    iteration_log.append(Path(root).parent, 'attempt-graded', {'cohort': Path(root).name,
                         'task': task, 'pair': pair, 'arm': arm, 'passed': passed,
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
    parser.add_argument('--arm')  # A registered arm label, not a language.
    parser.add_argument('--cohort'); parser.add_argument('--readiness', type=Path)
    parser.add_argument('--pairs', type=int, default=1)
    parser.add_argument('--arms', default=None)  # JSON [comparator, candidate] arm definitions.
    parser.add_argument('--context-id'); parser.add_argument('--prompt-sha256')
    parser.add_argument('--token')
    parser.add_argument('--handoff', default=None)  # Coordinator handoff text, stored by begin.
    # Files arms use command/check/finish/output; store arms use the session verbs.
    # Both accept await-handoff, the single-context bridge into the timed task.
    parser.add_argument('--tool', choices=sorted(set(OPERATIONS['files']) | set(OPERATIONS['store'])))
    parser.add_argument('--arguments', default='{}')
    args = parser.parse_args()
    if args.operation == 'freeze':
        result = freeze(args.root, args.cohort, args.readiness, pairs=args.pairs,
                        arms=None if args.arms is None else json.loads(args.arms))
    elif args.operation == 'bind-context':
        result = bind_context(args.root, args.task, args.pair, args.arm, args.context_id, args.prompt_sha256)
    elif args.operation == 'participant':
        result = participant(args.root, args.task, args.pair, args.arm, args.tool, json.loads(args.arguments))
        result = bounded_feedback(result)
    elif args.operation == 'agent':
        result = bounded_feedback(agent(args.root, args.token, args.tool, json.loads(args.arguments)))
    elif args.operation == 'begin':
        result = begin(args.root, args.task, args.pair, args.arm, args.handoff)
    else:
        result = {'prepare': prepare, 'grade': grade}[args.operation](args.root, args.task, args.pair, args.arm)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
