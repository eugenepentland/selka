"""Matched schedules and immutable cohort inputs. This module never launches agents."""
import itertools
from pathlib import Path
import random
import re
from .storage import digest, read_json, snapshot, verify_snapshot, write_json

LANGUAGES = ('my', 'python', 'zig')
FAMILIES = ('local-boundary', 'shared-contract', 'feature', 'rule-refactor')
BUDGET_KEYS = {'preparation_seconds', 'task_seconds', 'max_submissions', 'max_output_tokens', 'max_turns'}


def validate_configuration(kind, model_settings, budgets):
    if (kind not in ('fixture', 'calibration', 'agent') or not isinstance(model_settings, dict) or
            not isinstance(model_settings.get('model'), str) or not model_settings['model'].strip()):
        raise ValueError('explicit record kind and model settings required')
    if 'max_reported_tokens_per_phase' in model_settings and (type(model_settings['max_reported_tokens_per_phase']) is not int or model_settings['max_reported_tokens_per_phase'] <= 0):
        raise ValueError('reported token limit must be a positive integer')
    if (not isinstance(budgets, dict) or set(budgets) != BUDGET_KEYS or
            any(type(value) is not int or value <= 0 for value in budgets.values())):
        raise ValueError('explicit positive common budgets required')


def inventory(rows):
    return {'baselines': {f"{row['application']}/{row['tier']}/{row['language']}" for row in rows},
            'tasks': {row['block'] for row in rows}}


def identifier(value):
    return isinstance(value, str) and re.fullmatch(r'[a-z][a-z0-9_-]{0,63}', value) is not None


def schedule(blocks, *, seed, repetitions=2):
    if not isinstance(seed, str) or not seed or type(repetitions) is not int or repetitions <= 0:
        raise ValueError('explicit seed and positive repetitions required')
    if (not isinstance(blocks, list) or not blocks or
            any(not isinstance(block, dict) or set(block) != {'id', 'application', 'tier', 'family'}
                for block in blocks)):
        raise ValueError('invalid task blocks')
    for block in blocks:
        if (not identifier(block['id']) or not identifier(block['application']) or
                block['tier'] not in ('small', 'medium', 'large') or block['family'] not in FAMILIES):
            raise ValueError('invalid task block identity')
    if len({block['id'] for block in blocks}) != len(blocks):
        raise ValueError('duplicate task block')
    # Sort first so input mapping/JSON order cannot change the random assignment.
    matched = [(block, repeat) for block in sorted(blocks, key=lambda item: item['id'])
               for repeat in range(repetitions)]
    rng = random.Random(seed)
    rng.shuffle(matched)
    orders = list(itertools.permutations(LANGUAGES))
    rng.shuffle(orders)
    rows = []
    for index, (block, repeat) in enumerate(matched):
        # A full six-block cycle balances every order/position equally.
        if index and index % len(orders) == 0:
            rng.shuffle(orders)
        order = orders[index % len(orders)]
        for position, language in enumerate(order):
            rows.append({'session_id': f"{block['id']}-r{repeat + 1}-{language}",
                         'pair_id': f"{block['id']}-r{repeat + 1}", 'block': block['id'],
                         'application': block['application'], 'tier': block['tier'], 'family': block['family'],
                         'repetition': repeat + 1, 'language': language,
                         'sequence': len(rows), 'position_in_trio': position,
                         'status': 'not-launched'})
    return rows


def environment_keys(rows):
    return {f"{arm}/{row['block']}/{row['language']}" for row in rows
            for arm in ('main', 'language-focused')}


def validate_environments(environments, rows):
    from .environment_receipt import validate
    if not isinstance(environments, dict) or set(environments) != environment_keys(rows):
        raise ValueError('environment inventory must cover every scheduled arm, task and language')
    for receipt in environments.values():
        validate(receipt, require_system=True)


def validate_configurations(configurations, rows):
    from .trial_configuration import validate
    if not isinstance(configurations, dict) or set(configurations) != environment_keys(rows):
        raise ValueError('configuration inventory must cover every scheduled condition')
    applications = {row['block']: row['application'] for row in rows}
    for key, configuration in configurations.items():
        arm, block, language = key.split('/')
        validate(configuration)
        if (configuration['arm'], configuration['application'], configuration['language']) != (arm, applications[block], language):
            raise ValueError('configuration does not match scheduled condition')


def freeze(directory, *, blocks, seed, model_settings, budgets, baseline_paths, task_paths, kind='fixture', practice_paths=None, environments=None, configurations=None, coordinator=None):
    """Capture supplied task packs/baselines and configuration, with no launch claim.

Task packs may contain coordinator-only hidden material and must never be mounted
wholesale for a participant. Separate public provisioning belongs to the launcher.
"""
    if kind == 'calibration' and (configurations is None or coordinator is None):
        raise ValueError('calibration requires full frozen configuration and coordinator provenance')
    rows = schedule(blocks, seed=seed)
    validate_configuration(kind, model_settings, budgets)
    expected_inventory = inventory(rows)
    if set(baseline_paths) != expected_inventory['baselines'] or set(task_paths) != expected_inventory['tasks']:
        raise ValueError('baseline/task inventory does not match scheduled blocks')
    if practice_paths is not None and set(practice_paths) != set(LANGUAGES):
        raise ValueError('practice inventory requires all three languages')
    if coordinator is not None:
        from .coordinator_receipt import validate
        if configurations is None:
            raise ValueError('coordinator-bound cohort requires full configurations')
        validate(coordinator, transport_identity=coordinator['transport_identity'])
    if configurations is not None:
        if environments is not None:
            raise ValueError('configured cohort derives environments; do not override them')
        validate_configurations(configurations, rows)
        environments = {key: value['environment'] for key, value in configurations.items()}
    if environments is not None:
        if practice_paths is None:
            raise ValueError('environment-bound cohorts require frozen practice')
        validate_environments(environments, rows)
    directory = Path(directory)
    directory.mkdir(exist_ok=False)
    receipts = {'baselines': {}, 'tasks': {}}
    captures = [('baselines', baseline_paths), ('tasks', task_paths)]
    if practice_paths is not None:
        receipts['practice'] = {}
        captures.append(('practice', practice_paths))
    for category, paths in captures:
        for key, source in sorted(paths.items()):
            destination = directory / category / key
            destination.parent.mkdir(parents=True, exist_ok=True)
            receipts[category][key] = snapshot(source, destination)
    manifest = {'version': 'application-cohort-v1' if practice_paths is None else 'application-cohort-v2', 'record_kind': kind, 'seed': seed,
                'blocks': sorted(blocks, key=lambda item: item['id']), 'schedule': rows,
                'model_settings': model_settings, 'budgets': budgets, 'receipts': receipts,
                'launch_authorized': False, 'comparative_claim': False}
    if environments is not None:
        manifest.update(version='application-cohort-v3', environments=environments)
    if configurations is not None:
        manifest.update(version='application-cohort-v4', configurations=configurations)
    if coordinator is not None:
        manifest.update(version='application-cohort-v5', coordinator=coordinator)
    write_json(directory / 'cohort.json', dict(manifest, sha256=digest(manifest)))
    return load(directory)


def load(directory):
    directory = Path(directory)
    manifest = read_json(directory / 'cohort.json')
    fields = {'version', 'record_kind', 'seed', 'blocks', 'schedule', 'model_settings',
              'budgets', 'receipts', 'launch_authorized', 'comparative_claim', 'sha256'}
    if isinstance(manifest, dict) and manifest.get('version') in ('application-cohort-v3', 'application-cohort-v4', 'application-cohort-v5'):
        fields.add('environments')
    if isinstance(manifest, dict) and manifest.get('version') in ('application-cohort-v4', 'application-cohort-v5'):
        fields.add('configurations')
    if isinstance(manifest, dict) and manifest.get('version') == 'application-cohort-v5':
        fields.add('coordinator')
    if not isinstance(manifest, dict) or set(manifest) != fields:
        raise ValueError('invalid cohort fields')
    body = {key: value for key, value in manifest.items() if key != 'sha256'}
    if manifest.get('version') not in ('application-cohort-v1', 'application-cohort-v2', 'application-cohort-v3', 'application-cohort-v4', 'application-cohort-v5') or digest(body) != manifest.get('sha256'):
        raise ValueError('cohort definition changed')
    if manifest['record_kind'] == 'calibration' and manifest['version'] != 'application-cohort-v5':
        raise ValueError('calibration requires v5 provenance')
    expected = schedule(manifest['blocks'], seed=manifest['seed'])
    validate_configuration(manifest['record_kind'], manifest['model_settings'], manifest['budgets'])
    if (expected != manifest['schedule'] or manifest['launch_authorized'] is not False or
            manifest['comparative_claim'] is not False):
        raise ValueError('invalid construction cohort schedule or launch state')
    if manifest['version'] in ('application-cohort-v3', 'application-cohort-v4', 'application-cohort-v5'):
        validate_environments(manifest['environments'], expected)
    if manifest['version'] in ('application-cohort-v4', 'application-cohort-v5'):
        validate_configurations(manifest['configurations'], expected)
        if manifest['environments'] != {key: value['environment'] for key, value in manifest['configurations'].items()}:
            raise ValueError('configuration environment mismatch')
    if manifest['version'] == 'application-cohort-v5':
        from .coordinator_receipt import validate
        validate(manifest['coordinator'], transport_identity=manifest['coordinator']['transport_identity'])
    expected_inventory = inventory(expected)
    if manifest['version'] in ('application-cohort-v2', 'application-cohort-v3', 'application-cohort-v4', 'application-cohort-v5'):
        expected_inventory['practice'] = set(LANGUAGES)
    if (not isinstance(manifest['receipts'], dict) or set(manifest['receipts']) != set(expected_inventory) or
            any(not isinstance(manifest['receipts'][category], dict) or
                set(manifest['receipts'][category]) != keys for category, keys in expected_inventory.items())):
        raise ValueError('cohort inventory does not match scheduled blocks')
    for category, receipts in manifest['receipts'].items():
        if category not in ('baselines', 'tasks', 'practice'):
            raise ValueError('unknown cohort inventory')
        for key, receipt in receipts.items():
            parts = key.split('/')
            expected_parts = 3 if category == 'baselines' else 1
            if len(parts) != expected_parts or not all(identifier(part) for part in parts):
                raise ValueError('invalid cohort inventory key')
            verify_snapshot(directory / category / key, receipt)
            if category == 'practice':
                from . import practice_pack
                if practice_pack.load(directory / category / key)['language'] != key:
                    raise ValueError('practice pack language mismatch')
    return manifest
