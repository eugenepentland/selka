"""Coordinator-only adapter; the repository maintenance pack and gateway stay unchanged."""
import argparse
from datetime import datetime, timezone
import difflib
import json
import os
from pathlib import Path
import secrets
import shutil
import sys
import time

sys.dont_write_bytecode = True
BASE = Path(__file__).resolve().parent
REPO = Path('/home/epentland/ai/canopy/mylang')
sys.path.insert(0, str(REPO / 'experiments/maintenance_trial'))
import pack
import gateway
from experiments.application_comparison.storage import (
    digest, inventory, locked, path_identity, read_json, source_files, write_json,
)
PARTICIPANTS = ('A', 'B')
STAGES = (1, 2, 3)
DOCS = (
    'current-language.md', 'const-length-generics.md', 'module-constants.md',
    'range-iteration.md', 'match-expressions.md', 'type-aliases.md',
    'experiments/borrowing.md', 'experiments/ownership.md', 'experiments/results.md',
    'experiments/generic-results.md', 'experiments/buffer-operations.md',
    'experiments/source-arenas.md', 'borrow-syntax.md', 'generic-containers.md',
    'standard-library.md', 'stdlib-collections.md', 'stdlib-text-data.md',
)
ARTIFACTS = ('coordinator.py', 'participant_bridge.py', 'tooling_test.py',
             'README.md', 'participant-prompt.txt')


def utc():
    return datetime.now(timezone.utc).isoformat()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def artifact_inventory():
    return inventory({name: (BASE / name).read_bytes() for name in ARTIFACTS})


def freeze():
    require(not (BASE / 'freeze.json').exists(), 'freeze already exists; never overwrite a cohort')
    require(not list(BASE.glob('runs/*/gateway.json')), 'cannot freeze after clocks start')
    docs = BASE / 'docs'
    seeds = BASE / 'grading'
    docs.mkdir()
    seeds.mkdir(mode=0o700)
    for name in DOCS:
        destination = docs / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(REPO / 'docs' / name, destination)
        destination.chmod(0o444)
    for path in sorted(docs.rglob('*'), reverse=True):
        if path.is_dir():
            path.chmod(0o555)
    docs.chmod(0o555)
    seed_hashes = {}
    for stage in STAGES:
        path = seeds / f'stage{stage}-seed.txt'
        path.write_text(secrets.token_hex(32) + '\n')
        path.chmod(0o600)
        seed_hashes[str(stage)] = path_identity(path)['sha256']
    receipt = {
        'version': 'velocity-maintenance-freeze-v1', 'frozen_utc': utc(),
        'authoring': pack.authoring_receipt(), 'adapter': artifact_inventory(),
        'documentation': path_identity(docs), 'documentation_files': inventory(source_files(docs)),
        'seed_sha256': seed_hashes, 'seed_policy': 'one private seed per stage, shared by A/B, frozen before every clock',
        'participants': list(PARTICIPANTS), 'stages': list(STAGES),
        'historical_evidence': str(REPO / 'experiments/maintenance-evidence/20260907'),
        'timing_definition': 'max(executed command result.time) - gateway.started_unix',
        'exact_model_tokens': None, 'status': 'frozen-no-clocks',
    }
    write_json(BASE / 'freeze.json', receipt)
    return {'status': receipt['status'], 'documentation_files': len(DOCS), 'private_seeds': 3}


def frozen():
    receipt = read_json(BASE / 'freeze.json')
    require(receipt['adapter'] == artifact_inventory(), 'coordinator adapter changed after freeze')
    require(receipt['authoring'] == pack.authoring_receipt(), 'repository maintenance harness changed after freeze')
    require(receipt['documentation'] == path_identity(BASE / 'docs'), 'frozen documentation changed')
    for stage in STAGES:
        require(receipt['seed_sha256'][str(stage)] == path_identity(BASE / 'grading' / f'stage{stage}-seed.txt')['sha256'],
                'frozen private seed changed')
    return receipt


def config():
    frozen()
    value = read_json(BASE / 'config.json')
    require(value['compiler'] == path_identity(value['compiler']['path']), 'frozen compiler changed')
    return value


def stage_path(participant, stage):
    require(participant in PARTICIPANTS and stage in STAGES, 'unknown participant or stage')
    return BASE / 'runs' / f'{participant.lower()}-stage{stage}'


def control_path(participant):
    require(participant in PARTICIPANTS, 'participant must be A or B')
    return BASE / 'control' / participant


def prepare(model, compiler):
    frozen()
    require(not (BASE / 'config.json').exists(), 'participants already prepared')
    require(bool(model.strip()), 'record the actual common model/configuration label')
    compiler = compiler.resolve(strict=True)
    require(compiler.is_file() and os.access(compiler, os.X_OK), 'compiler must be an executable file')
    (BASE / 'runs').mkdir()
    (BASE / 'control').mkdir()
    settings = {'version': 'velocity-maintenance-configuration-v1', 'compiler': path_identity(compiler),
                'model': model, 'kind': 'agent', 'prepared_utc': utc(),
                'exact_serving_model_id': None, 'model_tokens': None,
                'launch_status': 'prepared-unreviewed; no participant clocks started'}
    for participant in PARTICIPANTS:
        directory = stage_path(participant, 1)
        pack.prepare(directory, compiler, 1, participant, model, 'agent')
        control_path(participant).mkdir()
        write_json(control_path(participant) / 'state.json',
                   {'participant': participant, 'stage': 1, 'status': 'prepared', 'sealed_stages': []})
    write_json(BASE / 'config.json', settings)
    return {'status': 'prepared', 'stages_prepared': ['A:1', 'B:1'], 'clocks_started': 0}


def command_records(directory):
    state = read_json(directory / 'gateway.json')
    rows = []
    for index in range(1, state['commands'] + 1):
        folder = directory / 'commands' / f'{index:03}'
        if not (folder / 'result.json').exists() and state['pending'] == index:
            continue
        rows.append((read_json(folder / 'request.json'), read_json(folder / 'result.json'), folder))
    return rows


def check_passed(request, result, folder):
    if (request['operation'] != 'check' or result.get('outcome') != 'exited' or
            result.get('returncode') != 0 or result.get('boundary_error') is not None or
            result.get('isolated') is not True or result.get('source_before') != result.get('source_after')):
        return False
    try:
        output = read_json(folder / 'stdout')
        checks = output['checks']
        return bool(checks) and all(row.get('passed') is True for row in checks)
    except (ValueError, OSError, KeyError, TypeError):
        return False


def latest_success(directory):
    state = read_json(directory / 'gateway.json')
    require(state['pending'] is None, 'pending command requires coordinator review')
    current = pack.source_receipt(directory / 'public/work')
    require(current == state['expected_source'] == state['last_checked'] and state['has_check'],
            'finish requires the intact source from the latest check')
    checks = [row for row in command_records(directory) if row[0]['operation'] == 'check']
    require(bool(checks), 'finish requires a public check')
    request, result, folder = checks[-1]
    require(check_passed(request, result, folder), 'finish requires a successful latest public check')
    require(request['source_before'] == current, 'latest successful check belongs to different source')
    return request['index']


def preserve_initial(directory, reply):
    initial = directory / 'initial-unchanged-check.json'
    if initial.exists():
        return
    rows = command_records(directory)
    require(len(rows) == 1 and rows[0][0]['operation'] == 'check', 'first executed command must be the unchanged public check')
    request, result, folder = rows[0]
    start = read_json(directory / 'setup.json')['start']
    require(request['source_before'] == start and not request['edited_check'], 'initial source differs from frozen stage start')
    write_json(initial, {'kind': 'initial-unchanged-public-check', 'index': request['index'],
                        'source': start, 'passed': check_passed(request, result, folder),
                        'returncode': reply['returncode'], 'outcome': reply['outcome'],
                        'duration_seconds': reply['duration_seconds'],
                        'raw_evidence': str(folder),
                        'counts_as_edited_submission': False})


def participant_event(participant, value):
    path = control_path(participant) / 'bridge.jsonl'
    with path.open('a') as stream:
        stream.write(json.dumps({'time': time.time(), **value}, sort_keys=True) + '\n')
        stream.flush()
        os.fsync(stream.fileno())


def advance(participant, state, settings, reason):
    stage = state['stage']
    directory = stage_path(participant, stage)
    if not (directory / 'seal.json').exists():
        require((directory / 'gateway.json').exists(), 'cannot seal a stage whose clock never started')
        if reason == 'completed':
            latest_success(directory)
        pack.seal(directory, reason)
    else:
        require(read_json(directory / 'seal.json')['reason'] == reason, 'stage already sealed with a different stopping reason')
    if stage not in state['sealed_stages']:
        state['sealed_stages'].append(stage)
    if stage < 3:
        following = stage_path(participant, stage + 1)
        if not following.exists():
            pack.prepare(following, Path(settings['compiler']['path']), stage + 1, participant,
                         settings['model'], 'agent', directory)
        else:
            require((following / 'setup.json').exists(), 'partial next-stage preparation requires coordinator review')
            require(read_json(following / 'setup.json')['previous_source'] == read_json(directory / 'seal.json')['source']['sha256'],
                    'next stage does not retain this participant source')
        require(not (following / 'gateway.json').exists(), 'next stage unexpectedly started')
        state.update(stage=stage + 1, status='prepared')
    else:
        state['status'] = 'sequence-sealed'
    write_json(control_path(participant) / 'state.json', state)
    return {'sealed_stage': stage, 'reason': reason, 'status': state['status'],
            'next_stage': None if stage == 3 else stage + 1, 'next_clock_started': False,
            'next_action': None if stage == 3 else 'check'}


def invoke(participant, operation, payload):
    require(participant in PARTICIPANTS, 'participant must be A or B')
    require(type(payload) is dict, 'payload must be a JSON object')
    with locked(control_path(participant)):
        participant_event(participant, {'event': 'request', 'operation': operation, 'payload': payload})
        try:
            settings = config()
            state = read_json(control_path(participant) / 'state.json')
            require(state['status'] != 'sequence-sealed', 'all three stages are already sealed')
            directory = stage_path(participant, state['stage'])
            if operation in ('finish', 'stop'):
                if operation == 'finish':
                    require(not payload, 'finish takes an empty object')
                    reason = 'completed'
                else:
                    require(set(payload) == {'reason'} and payload['reason'] in ('budget', 'abandoned'),
                            'stop requires budget or abandoned reason')
                    reason = payload['reason']
                answer = advance(participant, state, settings, reason)
            else:
                require(operation in ('command', 'check'), 'unknown operation')
                if operation == 'check':
                    require(not payload, 'check takes an empty object')
                    argv = []
                else:
                    require(set(payload) == {'argv'} and type(payload['argv']) is list and payload['argv'] and
                            all(type(arg) is str for arg in payload['argv']), 'command requires a nonempty string argv array')
                    argv = payload['argv']
                if not (directory / 'gateway.json').exists():
                    require(operation == 'check', 'first command of each stage must be check; no clock started')
                    gateway.begin(directory, BASE / 'docs')
                answer = gateway.command(directory, 'run' if operation == 'command' else 'check', argv)
                if read_json(directory / 'gateway.json')['commands'] == 1:
                    preserve_initial(directory, answer)
                answer = {'stage': state['stage'], **answer}
            participant_event(participant, {'event': 'result', 'operation': operation, 'stage': state['stage'],
                                            'status': answer.get('status', answer.get('outcome'))})
            return answer
        except (ValueError, OSError) as error:
            participant_event(participant, {'event': 'rejected', 'operation': operation, 'error': str(error)})
            raise


def grade(resume=False):
    config()
    directories = [stage_path(p, s) for p in PARTICIPANTS for s in STAGES]
    require(all((d / 'seal.json').exists() for d in directories), 'grading waits until all six stages are sealed')
    require(resume or not any((d / 'grade.json').exists() for d in directories), 'grading exists; use --resume to retain completed reports')
    output = []
    for directory in directories:
        stage = read_json(directory / 'setup.json')['stage']
        seed = (BASE / 'grading' / f'stage{stage}-seed.txt').read_text()
        if (directory / 'grade.json').exists():
            report = read_json(directory / 'grade.json')
            require(report['private_seed'] == seed and report['source'] == read_json(directory / 'seal.json')['source'],
                    'existing grading report identity mismatch')
        else:
            report = pack.grade(directory, seed)
        output.append({'run': directory.name, 'passed': report['behavior_passed'], 'observations': len(report['outcomes'])})
    return {'graded': output, 'structure_and_protocol_review': 'still required'}


def source_changes(directory):
    if not (directory / 'commands/001/before').exists():
        return []
    changes = []
    for name in pack.checks.FILES:
        before = (directory / 'commands/001/before' / name).read_text().splitlines()
        after = (directory / 'sealed' / name).read_text().splitlines()
        added = removed = 0
        for tag, a, b, c, d in difflib.SequenceMatcher(None, before, after).get_opcodes():
            if tag in ('replace', 'delete'):
                removed += b - a
            if tag in ('replace', 'insert'):
                added += d - c
        if added or removed:
            changes.append({'file': name, 'added_lines': added, 'removed_lines': removed})
    return changes


def summary_row(participant, stage):
    directory = stage_path(participant, stage)
    row = {'participant': participant, 'stage': stage, 'status': 'not-prepared'}
    if not (directory / 'setup.json').exists():
        return row
    setup = read_json(directory / 'setup.json')
    row.update(status='prepared-not-started', previous_source_sha256=setup['previous_source'])
    if not (directory / 'gateway.json').exists():
        return row
    state = read_json(directory / 'gateway.json')
    rows = command_records(directory)
    checks = [{'index': request['index'], 'edited': request['edited_check'],
               'exit': result['returncode'], 'passed': check_passed(request, result, folder),
               'seconds': result['duration_seconds']} for request, result, folder in rows if request['operation'] == 'check']
    edited = [item for item in checks if item['edited']]
    elapsed = max((result['time'] for _, result, _ in rows), default=state['started_unix']) - state['started_unix']
    row.update(status='started', initial_unchanged_check=read_json(directory / 'initial-unchanged-check.json') if (directory / 'initial-unchanged-check.json').exists() else None,
               public_checks=checks, first_edited_submission_passed=edited[0]['passed'] if edited else None,
               failed_edited_submissions=sum(not c['passed'] for c in edited),
               start_to_last_command_seconds=elapsed,
               tool_invocations=state['requests'], executed_commands=state['commands'], edited_submissions=state['edited_checks'],
               command_seconds=sum(result['duration_seconds'] for _, result, _ in rows),
               model_tokens=None, pending_command=state['pending'])
    if (directory / 'seal.json').exists():
        sealed = read_json(directory / 'seal.json')
        row.update(status='sealed', reason=sealed['reason'], final_checked=sealed['final_checked'],
                   source_sha256=sealed['source']['sha256'], gateway_metrics=sealed['gateway_metrics'],
                   coordinator_delay_until_seal_seconds=sealed['gateway_metrics']['wall_seconds_at_seal'] - elapsed,
                   source_changes=source_changes(directory), structure_review='coordinator-required', protocol_review='coordinator-required')
    if (directory / 'grade.json').exists():
        report = read_json(directory / 'grade.json')
        row.update(behavior_passed=report['behavior_passed'], private_observations=len(report['outcomes']))
    return row


def summary():
    frozen()
    rows = [summary_row(p, s) for p in PARTICIPANTS for s in STAGES]
    value = {'version': 'velocity-maintenance-observation-v1', 'captured_utc': utc(),
             'planned_fresh_participants': 2, 'participants_started': sum((stage_path(p, 1) / 'gateway.json').exists() for p in PARTICIPANTS),
             'freshness_review': 'agent-history review required', 'sequential_stages_each': 3, 'denominator': 6,
             'rows': rows, 'model_tokens': None, 'comparative_claim': False,
             'timing_definition': 'max(executed command result.time) - gateway.started_unix; excludes later coordinator sealing delay',
             'bridge_control_requests': 'separately retained in control/A/bridge.jsonl and control/B/bridge.jsonl; not redefined as historical gateway command counts',
             'limitations': ['initial unchanged checks remain separate from edited failures',
                            'stage timing includes reasoning and waits; command timing includes public-check driver/compile/VM work',
                            'inherited tools require separate transcript boundary review',
                            'ownership, generic helper, modules and error propagation require independent source review']}
    write_json(BASE / 'observations.json', value)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='operation', required=True)
    sub.add_parser('freeze')
    prepare_parser = sub.add_parser('prepare')
    prepare_parser.add_argument('--compiler', type=Path, default=BASE.parent / 'toolchain/bin/mylang')
    prepare_parser.add_argument('--model', required=True)
    grade_parser = sub.add_parser('grade')
    grade_parser.add_argument('--resume', action='store_true')
    sub.add_parser('summary')
    args = parser.parse_args()
    if args.operation == 'freeze':
        result = freeze()
    elif args.operation == 'prepare':
        result = prepare(args.model, args.compiler)
    elif args.operation == 'grade':
        result = grade(args.resume)
    else:
        result = summary()
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        print(json.dumps({'outcome': 'rejected', 'error': str(error)}))
        raise SystemExit(1)
