#!/usr/bin/env python3
"""Bounded report-only budget recommendations; never authorizes cache reuse."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import statistics

MAX_BYTES = 2 * 1024 * 1024
MAX_REPORTS = 128
MAX_ACTIONS = 1024
MAX_MEMBERS = 4096
MAX_SAMPLES = 64
MAX_REJECTIONS = 64
MAX_TOTAL_SAMPLES = 1024
MIN_SAMPLES = 5
_DIGEST = re.compile(r'[0-9a-f]{64}')


def _digest(value):
    return isinstance(value, str) and _DIGEST.fullmatch(value) is not None


def _number(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def _json(value):
    # Bound construction before JSON serialization, including deeply nested input.
    pending = [(value, 0)]
    nodes = size = 0
    while pending:
        item, depth = pending.pop()
        nodes += 1
        if nodes > 65536 or depth > 32:
            raise ValueError('budget input complexity bound')
        if isinstance(item, str):
            size += len(item)
            if size > MAX_BYTES:
                raise ValueError('budget input string bound')
        elif isinstance(item, dict):
            if len(item) > 16384 or not all(isinstance(key, str) for key in item):
                raise ValueError('budget mapping bound')
            pending.extend((key, depth + 1) for key in item)
            pending.extend((child, depth + 1) for child in item.values())
        elif isinstance(item, (list, tuple)):
            if len(item) > 16384:
                raise ValueError('budget list bound')
            pending.extend((child, depth + 1) for child in item)
        elif item is not None and type(item) not in (int, float, bool):
            raise ValueError('budget JSON type')
    encoded = json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
    if len(encoded) > MAX_BYTES:
        raise ValueError('budget serialized byte bound')
    return encoded


def _mapping(inventory):
    _json(inventory)
    if not isinstance(inventory, dict):
        raise ValueError('budget inventory shape')
    groups = inventory.get('groups', [])
    metadata = inventory.get('action_metadata', [])
    if not isinstance(groups, list) or not isinstance(metadata, list) or len(groups) > MAX_ACTIONS or len(metadata) > MAX_ACTIONS:
        raise ValueError('budget inventory bound')
    if not all(isinstance(group, dict) and isinstance(group.get('id'), str) for group in groups):
        raise ValueError('budget group shape')
    ids = [group['id'] for group in groups]
    if len(set(ids)) != len(ids) or not all(0 < len(item) <= 256 for item in ids):
        raise ValueError('budget action identity')
    members = {identifier: [] for identifier in ids}
    labels = {}
    seen = set()
    count = 0
    for action in metadata:
        if not isinstance(action, dict) or not isinstance(action.get('id'), str) or 'steps' not in action:
            raise ValueError('budget metadata shape')
        identifier = action['id']
        if identifier not in members or identifier in seen:
            raise ValueError('budget metadata action identity')
        seen.add(identifier)
        steps = action['steps']
        if not isinstance(steps, list):
            raise ValueError('budget members')
        for member in steps:
            if not isinstance(member, dict) or 'label' not in member:
                raise ValueError('budget member shape')
            label = member['label']
            if not isinstance(label, str) or not 0 < len(label) <= 512:
                raise ValueError('budget member label')
            count += 1
            if count > MAX_MEMBERS:
                raise ValueError('budget member bound')
            # Duplicate labels are ambiguous even within the same group.
            labels[label] = None if label in labels else identifier
            members[identifier].append(label)
    return members, labels


def collect_report(report, inventory):
    """Extract only complete fresh successful exact-label observations.

    Required provenance: report.budget_context and actions[].action_key are SHA256
    digests supplied by the coordinator. Missing capture integrity is unknown.
    """
    members, labels = _mapping(inventory)
    result = {'observations': [], 'rejections': []}
    def reject(reason):
        if len(result['rejections']) < MAX_REJECTIONS:
            result['rejections'].append(reason)
    try:
        # The embedded evaluation is derived from these same observations. Its
        # presence or later target-only reevaluation must not create a new run.
        source_report = ({key: value for key, value in report.items() if key != 'action_budgets'}
                         if isinstance(report, dict) else report)
        report_digest = hashlib.sha256(_json(source_report)).hexdigest()
    except (ValueError, TypeError, OverflowError, RecursionError):
        reject('malformed or oversized report')
        return result
    if not isinstance(report, dict):
        reject('malformed report')
        return result
    if report.get('success') is not True or type(report.get('status')) is not int or report['status'] != 0:
        reject('report failed or incomplete')
        return result
    if report.get('inputs_stable') is not True:
        reject('execution inputs were not proven stable')
        return result
    report_metadata = report.get('action_metadata')
    if not isinstance(report_metadata, list) or len(report_metadata) > MAX_ACTIONS:
        reject('report member mapping unavailable')
        return result
    recorded = {}
    ambiguous = set()
    for metadata in report_metadata:
        if not isinstance(metadata, dict) or not isinstance(metadata.get('id'), str):
            continue
        identifier = metadata['id']
        if identifier in recorded:
            ambiguous.add(identifier)
        recorded[identifier] = metadata
    matching = {metadata['id'] for metadata in inventory.get('action_metadata', [])
                if metadata['id'] not in ambiguous and recorded.get(metadata['id']) == metadata}
    context = report.get('budget_context')
    if not _digest(context):
        reject('execution compatibility context unavailable')
        return result
    actions = report.get('actions')
    if not isinstance(actions, list) or len(actions) > MAX_ACTIONS:
        reject('action provenance unavailable')
        return result
    fresh = {}
    duplicates = set()
    action_seen = set()
    for action in actions:
        if not isinstance(action, dict):
            continue
        identifier = action.get('id')
        if not isinstance(identifier, str):
            continue
        if identifier in action_seen:
            duplicates.add(identifier)
        action_seen.add(identifier)
        if identifier not in matching:
            reject('report member mapping differs from current inventory')
            continue
        if identifier in members and action.get('state') in ('execute', 'fresh') and _digest(action.get('action_key')):
            fresh[identifier] = action['action_key']
    for identifier in duplicates:
        fresh.pop(identifier, None)
    candidates = []
    admissions = report.get('admissions', [])
    if not isinstance(admissions, list) or len(admissions) > 64:
        reject('admission provenance unavailable')
        return result
    for admission_index, admission in enumerate(admissions):
        if not isinstance(admission, dict) or admission.get('kind') != 'gate':
            continue
        if (admission.get('admitted') is not True or type(admission.get('status')) is not int or admission['status'] != 0
            or any(admission.get(key) is not False for key in ('timed_out', 'cancelled', 'incomplete'))):
            reject('gate not completed successfully')
            continue
        if admission.get('log_errors') != []:
            reject('capture diagnostics unavailable or contain errors')
            continue
        logs = admission.get('logs', [])
        if not isinstance(logs, list) or len(logs) > 2:
            reject('log provenance unavailable')
            continue
        for log_index, log in enumerate(logs):
            if not isinstance(log, dict):
                reject('malformed capture')
                continue
            parsed = log.get('observed_steps')
            if (log.get('capture_available') is not True or log.get('capture_complete') is not True
                or log.get('truncated') is not False or not isinstance(parsed, dict)
                or parsed.get('status') != 'observed' or parsed.get('truncated') is not False
                or parsed.get('malformed') is not False):
                reject('capture unavailable, incomplete, malformed or truncated')
                continue
            observations = parsed.get('observations')
            if not isinstance(observations, list) or len(observations) > 256:
                reject('observation bound')
                continue
            for observation_index, observation in enumerate(observations):
                if not isinstance(observation, dict):
                    reject('malformed observation')
                    continue
                label = observation.get('node')
                identifier = labels.get(label) if isinstance(label, str) else None
                seconds = observation.get('elapsed_seconds')
                if identifier is None or identifier not in fresh:
                    reject('unmapped, ambiguous or reused action observation')
                    continue
                if observation.get('state') != 'success' or observation.get('source') != 'zig-summary' or not _number(seconds):
                    reject('observation not fresh successful finite execution')
                    continue
                candidates.append(dict(action_id=identifier, member=label, seconds=float(seconds),
                    context=context, action_key=fresh[identifier], report_sha256=report_digest,
                    source='zig-summary', provenance=[admission_index, log_index, observation_index]))
    # A label appearing twice in one report has unknown execution multiplicity.
    multiplicity = {}
    for item in candidates:
        multiplicity[item['member']] = multiplicity.get(item['member'], 0) + 1
    for item in candidates:
        if multiplicity[item['member']] == 1:
            result['observations'].append(item)
        else:
            reject('duplicate member observation in report')
    return result


def _policy(policy, identifier):
    value = (policy or {}).get(identifier, {})
    if not isinstance(value, dict):
        raise ValueError('budget policy shape')
    result = {}
    for field in ('expected_seconds', 'regression_seconds', 'hard_deadline_seconds'):
        target = value.get(field)
        if target is not None and (not _number(target) or target == 0):
            raise ValueError('budget targets must be positive finite or null')
        result[field] = target
    return result


def calibrate_observations(observations, inventory, *, policy=None, context=None, action_keys=None):
    """Reevaluate bounded saved telemetry; thresholds never become cache identity.

    Default cohort is the last observation's context and each action's last key.
    Recommendations concern individual named step elapsed time, never a sum of
    overlapping steps or a complete developer-loop deadline.
    """
    members, labels = _mapping(inventory)
    if not isinstance(observations, list) or len(observations) > MAX_REPORTS * 512:
        raise ValueError('budget observation bound')
    if policy is not None:
        _json(policy)
        if not isinstance(policy, dict) or set(policy) - set(members):
            raise ValueError('budget policy action identity')
    valid = []
    seen = set()
    for item in observations:
        if (not isinstance(item, dict) or not isinstance(item.get('member'), str) or labels.get(item.get('member')) != item.get('action_id')
            or not isinstance(item.get('action_id'), str) or item.get('action_id') not in members or not _number(item.get('seconds'))
            or not all(_digest(item.get(key)) for key in ('context', 'action_key', 'report_sha256'))
            or item.get('source') != 'zig-summary'):
            continue
        provenance = item.get('provenance')
        if not isinstance(provenance, list) or len(provenance) != 3 or not all(type(index) is int and 0 <= index < 512 for index in provenance):
            continue
        identity = (item['report_sha256'], item['member'])
        if identity not in seen:
            seen.add(identity)
            valid.append(item)
    if context is None and valid:
        context = valid[-1]['context']
    if context is not None and not _digest(context):
        raise ValueError('budget context digest')
    keys = dict(action_keys or {})
    if set(keys) - set(members) or not all(_digest(value) for value in keys.values()):
        raise ValueError('budget action contract digest')
    for item in valid:
        if item['context'] == context and item['action_id'] not in (action_keys or {}):
            keys[item['action_id']] = item['action_key']
    valid = valid[-MAX_TOTAL_SAMPLES:]
    actions = []
    for identifier, names in members.items():
        member_reports = []
        targets = _policy(policy, identifier)
        for name in dict.fromkeys(names):
            samples = [item for item in valid if item['member'] == name and item['context'] == context
                       and item['action_key'] == keys.get(identifier)][-MAX_SAMPLES:]
            values = [item['seconds'] for item in samples]
            enough = len(values) >= MIN_SAMPLES
            regression = max(values) * 1.5 if enough else None
            if regression is not None and not math.isfinite(regression):
                regression = None
            member_reports.append(dict(label=name, sample_count=len(values),
                status='report_only_candidate' if enough else 'insufficient_samples' if values else 'unknown',
                minimum_seconds=min(values) if values else None, maximum_seconds=max(values) if values else None,
                median_seconds=statistics.median(values) if values else None,
                recommendation={'expected_seconds': statistics.median(values) if enough else None,
                                'regression_seconds': regression,
                                'hard_deadline_seconds': None},
                regression_evaluation={
                    'scope': 'named member elapsed observations',
                    'status': 'not_configured' if targets['regression_seconds'] is None else
                              'unknown' if not values else
                              'exceeded' if max(values) > targets['regression_seconds'] else 'within_observed_samples',
                    'threshold_seconds': targets['regression_seconds'],
                    'samples_exceeding': sum(value > targets['regression_seconds'] for value in values)
                                        if targets['regression_seconds'] is not None else None,
                    'enforced': False},
                provenance=samples))
        actions.append(dict(id=identifier, targets=targets, members=member_reports,
                            action_elapsed_seconds=None,
                            reason='member graph elapsed durations cannot establish complete action elapsed time'))
    result = dict(version=1, enforced=False, context=context, actions=actions,
                  sample_limit=MAX_SAMPLES, minimum_samples=MIN_SAMPLES,
                  notes=['shared-host operational observations; no isolated latency qualification',
                         'no percentile or hard deadline calibration',
                         'recommendations require review; legacy actions remain report-only'])
    _json(result)
    return result


def calibrate(reports, inventory, **kwargs):
    """Collect bounded reports and evaluate them without affecting execution."""
    if not isinstance(reports, list) or len(reports) > MAX_REPORTS:
        raise ValueError('budget report bound')
    observations, rejections = [], []
    for report in reports:
        collected = collect_report(report, inventory)
        observations.extend(collected['observations'])
        rejections.extend(collected['rejections'])
    result = calibrate_observations(observations, inventory, **kwargs)
    result['rejections'] = rejections[:MAX_REJECTIONS]
    _json(result)
    return result


def read_json(path):
    """Read strict bounded JSON; malformed telemetry is never a sample."""
    with Path(path).open('rb') as source:
        raw = source.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise ValueError('budget input byte bound')
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('duplicate JSON key')
            result[key] = value
        return result
    value = json.loads(raw, object_pairs_hook=pairs, parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite JSON')))
    _json(value)
    return value


def _test_policy_observations(report):
    """Consume S01's validated per-member supported-runner records when available."""
    observations = []
    actions = report.get('actions', [])
    if not isinstance(actions, list) or len(actions) > MAX_ACTIONS:
        raise ValueError('policy action observation bound')
    for action in actions:
        if not isinstance(action, dict) or action.get('state') not in ('execute', 'fresh'):
            continue
        telemetry = action.get('test_telemetry', [])
        if not isinstance(telemetry, list) or len(telemetry) > MAX_MEMBERS:
            raise ValueError('policy test telemetry bound')
        for record in telemetry:
            if (not isinstance(record, dict) or record.get('status') != 'observed'
                or record.get('complete') is not True or record.get('truncated') is not False
                or record.get('action_id') != action.get('id')
                or not isinstance(record.get('member_id'), str)):
                continue
            tests = record.get('tests')
            if (not isinstance(tests, list) or len(tests) > MAX_MEMBERS
                or type(record.get('selected')) is not int or len(tests) != record['selected']):
                continue
            names = [row.get('test_id') for row in tests if isinstance(row, dict)]
            if (len(names) != len(tests) or not all(isinstance(name, str) and name for name in names)
                or len(set(names)) != len(names)):
                continue
            for row in tests:
                ns = row.get('elapsed_ns')
                if row.get('state') != 'passed' or type(ns) is not int or ns < 0:
                    continue
                observations.append(dict(action_id=record['action_id'], member_id=record['member_id'],
                    test_id=row['test_id'], scope='individual_test',
                    clock='supported_runner_start_to_stop_including_teardown', elapsed_seconds=ns / 1e9,
                    fresh=True, complete=True, successful=True))
                if len(observations) > MAX_MEMBERS:
                    raise ValueError('policy test observation bound')
    return observations


def evaluate_scoped_policy(path, report, inventory):
    """Read an optional policy and report exact available scopes without enforcement.

    The coordinator supplies supported telemetry in scoped_budget_observations.
    Shared gate elapsed time cannot be assigned to individual action/test scopes.
    Parsing or incomplete telemetry is an advisory unavailable result; it never
    masks verification status, alters execution identity, or certifies headroom.
    """
    if path is None:
        return {'version': 1, 'status': 'not_configured', 'mode': 'report_only', 'enforced': False}
    try:
        # Import locally: policy shares this module's bounded strict JSON reader.
        from verification_policy import evaluate, validate_policy
        document = validate_policy(read_json(path))
        members, _ = _mapping(inventory)
        if any(entry['action_id'] not in members for entry in document['entries']):
            raise ValueError('policy action is absent from current inventory')
        if not isinstance(report, dict):
            raise ValueError('policy report shape')
        observations = report.get('scoped_budget_observations', [])
        if not isinstance(observations, list):
            raise ValueError('scoped policy observation shape')
        observations = list(observations)
        observations.extend(_test_policy_observations(report))
        if report.get('success') is not True or report.get('inputs_stable') is not True:
            observations = []
        result = evaluate(document, observations)
        result['status'] = 'evaluated'
        result['observation_contract'] = 'explicit fresh complete successful clock scopes only'
        result['notes'] = ['shared gate wall time is not an individual action duration',
                           'headroom and enforcement remain unqualified',
                           'advisory policy does not authorize reuse or success publication']
        return result
    except (OSError, ValueError, TypeError, KeyError, OverflowError, RecursionError) as error:
        return {'version': 1, 'status': 'unavailable', 'mode': 'report_only',
                'enforced': False, 'reason': str(error)[:512]}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory', required=True, type=Path)
    parser.add_argument('--policy', type=Path)
    parser.add_argument('reports', nargs='+', type=Path)
    args = parser.parse_args(argv)
    try:
        if len(args.reports) > MAX_REPORTS:
            raise ValueError('budget report bound')
        result = calibrate([read_json(path) for path in args.reports], read_json(args.inventory),
                           policy=read_json(args.policy) if args.policy else None)
        print(json.dumps(result, sort_keys=True, allow_nan=False))
        return 0
    except (OSError, ValueError, KeyError, TypeError, RecursionError) as error:
        print('budget calibration unavailable: ' + str(error))
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
