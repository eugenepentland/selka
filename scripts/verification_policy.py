"""Versioned report-only scoped limits; policy review never fabricates evidence."""
from __future__ import annotations

import collections
import math
import statistics

from verification_budgets import MIN_SAMPLES, MAX_SAMPLES, _digest, _json, _number

VERSION = 2
VERSIONS = (1, 2)
PROTOCOL_CLOCK = 'supported_runner_protocol_interval_including_reporting'
SCOPES = ('admitted_action', 'setup_build', 'individual_test')
TARGETS = ('expected_seconds', 'regression_seconds', 'hard_deadline_seconds',
           'memory_ceiling_bytes', 'work_ceiling')
CLOCKS = {
    'admitted_action': 'admission_handshake_to_lineage_closeout',
    'setup_build': 'explicit_setup_build_start_to_end',
    'individual_test': 'supported_runner_start_to_stop_including_teardown',
}


def validate_policy(document):
    """Validate bounded policy data, refusing unqualified enforcement and scope guessing.

    Queue and user cancellation are outcomes, not execution cost observations.
    Memory means aggregate concurrent resident bytes, and work counts declared
    completed units. Unknown observations stay unknown. No enforcement adapter
    is qualified yet: all controls here are report-only even with archived data.
    Explicit user-configured ProcessLimits remain a separate supported control.
    """
    _json(document)
    if not isinstance(document, dict) or set(document) != {'version', 'mode', 'entries'}:
        raise ValueError('policy document fields')
    if type(document['version']) is not int or document['version'] not in VERSIONS:
        raise ValueError('unsupported policy version')
    if document['mode'] != 'report_only':
        raise ValueError('policy enforcement is not qualified')
    entries = document['entries']
    if not isinstance(entries, list) or len(entries) > 4096:
        raise ValueError('policy entry bound')
    seen = set()
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) - {'action_id', 'member_id', 'test_id', 'scope', 'targets', 'exception', 'headroom_evidence', 'work_unit', 'clock'}:
            raise ValueError('policy entry fields')
        scope = entry.get('scope')
        if scope not in SCOPES:
            raise ValueError('policy clock scope')
        clock = entry.get('clock', CLOCKS[scope])
        if ('clock' in entry and document['version'] == 1) or clock not in (
                (CLOCKS[scope], PROTOCOL_CLOCK) if scope == 'individual_test' else (CLOCKS[scope],)):
            raise ValueError('policy observation clock')
        action = entry.get('action_id')
        member = entry.get('member_id')
        test = entry.get('test_id')
        if not isinstance(action, str) or not 0 < len(action) <= 256:
            raise ValueError('policy action identity')
        if member is not None and (not isinstance(member, str) or not 0 < len(member) <= 512):
            raise ValueError('policy member identity')
        if scope == 'individual_test':
            if member is None or not isinstance(test, str) or not 0 < len(test) <= 1024:
                raise ValueError('policy individual test identity')
        elif test is not None or (scope == 'admitted_action' and member is not None):
            raise ValueError('policy identity does not match clock scope')
        identity = (action, member, test, scope, clock)
        if identity in seen:
            raise ValueError('duplicate policy scope')
        seen.add(identity)
        targets = entry.get('targets')
        if not isinstance(targets, dict) or set(targets) - set(TARGETS):
            raise ValueError('policy target fields')
        for name, value in targets.items():
            if value is None:
                continue
            if not _number(value) or value <= 0:
                raise ValueError('policy targets must be positive finite or null')
            if name in ('memory_ceiling_bytes', 'work_ceiling') and type(value) is not int:
                raise ValueError('policy byte and work ceilings must be integers')
        work_unit = entry.get('work_unit')
        if work_unit is not None and (not isinstance(work_unit, str) or not 0 < len(work_unit) <= 128):
            raise ValueError('policy completed work unit')
        if targets.get('work_ceiling') is not None and work_unit is None:
            raise ValueError('policy work ceiling requires a declared unit')
        exception = entry.get('exception')
        if exception is not None:
            if (not isinstance(exception, dict) or set(exception) != {'name', 'reason', 'review_point'}
                or any(not isinstance(value, str) or not 0 < len(value) <= 1024 for value in exception.values())):
                raise ValueError('policy exception requires name, reason and review point')
        evidence = entry.get('headroom_evidence', [])
        if not isinstance(evidence, list) or len(evidence) > 64 or not all(_digest(item) for item in evidence):
            raise ValueError('policy headroom evidence digests')
    return document


def execution_identity(document):
    """Advisory policy changes preserve compatible execution captures."""
    validate_policy(document)
    return {}


def evaluate(document, observations):
    """Evaluate exact scoped observations without adding nested elapsed durations.

    Rows require action/member/test identities and the declared clock; missing
    durations, aggregate memory, or completed work are explicitly unknown.
    No saved row here authorizes reuse, publication, or enforced limits.
    """
    validate_policy(document)
    _json(observations)
    if not isinstance(observations, list) or len(observations) > 4096:
        raise ValueError('policy observation bound')
    result = []
    for entry in document['entries']:
        matching = [row for row in observations if isinstance(row, dict)
                    and all(row.get(name) == entry.get(name) for name in ('action_id', 'member_id', 'test_id', 'scope'))
                    and row.get('clock') == entry.get('clock', CLOCKS[entry['scope']])
                    and row.get('complete') is True and row.get('successful') is True
                    and row.get('fresh') is True
                    and not any(row.get(name) is True for name in ('cancelled', 'timed_out', 'incomplete', 'truncated'))]
        evaluations = {}
        for target, ceiling in entry['targets'].items():
            values = _values(entry, matching, target)
            known = bool(values)
            evaluations[target] = {
                'threshold': ceiling, 'observed_maximum': max(values) if known else None,
                'status': 'not_configured' if ceiling is None else 'unknown' if not known else
                          'exceeded' if max(values) > ceiling else 'within_observed_samples',
                'enforced': False,
            }
        result.append({'action_id': entry['action_id'], 'member_id': entry.get('member_id'),
                       'test_id': entry.get('test_id'), 'scope': entry['scope'],
                       'clock': entry.get('clock', CLOCKS[entry['scope']]), 'sample_count': len(matching),
                       'evaluations': evaluations, 'exception': entry.get('exception'),
                       'calibration': _calibrate_scope(entry, observations),
                       'headroom_status': 'unqualified', 'work_unit': entry.get('work_unit'), 'additive': False})
    output = {'version': document['version'], 'mode': 'report_only', 'entries': result, 'enforced': False}
    _json(output)
    return output


def _metric(target):
    return ('elapsed_seconds' if target.endswith('_seconds') else
            'aggregate_peak_rss_bytes' if target == 'memory_ceiling_bytes' else 'completed_work')


def _values(entry, rows, target):
    metric = _metric(target)
    values = [row.get(metric) for row in rows]
    if not values or not all(_number(value) for value in values):
        return []
    if target in ('memory_ceiling_bytes', 'work_ceiling') and not all(type(value) is int for value in values):
        return []
    if target == 'work_ceiling' and not all(row.get('work_unit') == entry.get('work_unit') for row in rows):
        return []
    return values


def _headroom(values, threshold):
    maximum = max(values) if values else None
    ratio = maximum / threshold if maximum is not None and threshold is not None else None
    if ratio is not None and not math.isfinite(ratio):
        ratio = None
    return {'sample_count': len(values), 'observed_maximum': maximum,
            'threshold': threshold,
            'remaining': threshold - maximum if threshold is not None and maximum is not None else None,
            'maximum_to_threshold_ratio': ratio,
            'samples_exceeding': sum(value > threshold for value in values) if threshold is not None else None,
            'status': 'not_configured' if threshold is None else 'unknown' if not values else
                      'exceeded' if maximum > threshold else 'within_observed_samples'}


def calibrate_scope(entry, observations, *, cohort=None):
    """Describe compatible captured work and independent holdout headroom only.

    Digests are provenance supplied by authenticated collectors, not signatures
    or authority to publish success. The measurement-context digest must cover
    source/tool/flags/mode/cache/CPU and collector protocol. Caller order chooses
    the latest cohort unless one is explicit. No sample count qualifies limits.
    """
    _json(observations)
    if not isinstance(observations, list) or len(observations) > 4096:
        raise ValueError('calibration observation bound')
    validate_policy({'version': VERSION, 'mode': 'report_only', 'entries': [entry]})
    result = _calibrate_scope(entry, observations, cohort=cohort)
    _json(result)
    return result


def _calibrate_scope(entry, observations, *, cohort=None):
    # The public entry points validate once, avoiding serialization per policy
    # entry when evaluating a bounded complete report.
    cohort_was_explicit = cohort is not None
    clock = entry.get('clock', CLOCKS[entry['scope']])
    rejected = collections.Counter()
    valid, seen, conflicts = [], {}, set()
    fields = ('context', 'action_key', 'measurement_context', 'run_id', 'evidence_sha256')
    for row in observations:
        if not isinstance(row, dict) or any(row.get(name) != entry.get(name) for name in ('action_id', 'member_id', 'test_id', 'scope')):
            continue
        if row.get('clock') != clock:
            rejected['different_clock'] += 1
            continue
        if (any(row.get(name) is not True for name in ('fresh', 'complete', 'successful'))
                or any(row.get(name) is True for name in ('cancelled', 'timed_out', 'incomplete', 'truncated'))):
            rejected['not_fresh_complete_successful'] += 1
            continue
        if not all(_digest(row.get(name)) for name in fields):
            rejected['missing_capture_provenance'] += 1
            continue
        if row.get('measurement_kind') not in ('operational', 'isolated') or row.get('sample_role') not in ('calibration', 'validation'):
            rejected['unknown_measurement_or_sample_role'] += 1
            continue
        identity = row['run_id']
        signature = _json({name: row.get(name) for name in (*fields, 'measurement_kind', 'sample_role',
                          'elapsed_seconds', 'aggregate_peak_rss_bytes', 'completed_work', 'work_unit')})
        if identity in seen:
            rejected['duplicate_run' if seen[identity] == signature else 'conflicting_run'] += 1
            if seen[identity] != signature:
                conflicts.add(identity)
            continue
        seen[identity] = signature
        valid.append(row)
    valid = [row for row in valid if row['run_id'] not in conflicts]
    cohort_fields = ('context', 'action_key', 'measurement_context', 'measurement_kind')
    if cohort is not None:
        if (not isinstance(cohort, dict) or set(cohort) != set(cohort_fields)
                or not all(_digest(cohort.get(name)) for name in cohort_fields[:3])
                or cohort.get('measurement_kind') not in ('operational', 'isolated')):
            raise ValueError('calibration cohort contract')
    elif valid:
        cohort = {name: valid[-1][name] for name in cohort_fields}
    compatible = [row for row in valid if all(row.get(name) == value for name, value in (cohort or {}).items())]
    rejected['incompatible_cohort'] += len(valid) - len(compatible)
    roles = {}
    for role in ('calibration', 'validation'):
        candidates = [row for row in compatible if row['sample_role'] == role]
        rejected['history_evicted'] += max(0, len(candidates) - MAX_SAMPLES)
        roles[role] = candidates[-MAX_SAMPLES:]
    values = _values(entry, roles['calibration'], 'expected_seconds')
    result = {'version': 1, 'cohort': cohort, 'clock': clock,
              'cohort_selection': 'explicit' if cohort_was_explicit else 'latest_in_caller_order',
              'calibration_samples': len(roles['calibration']), 'validation_samples': len(roles['validation']),
              'candidate_expected_seconds': statistics.median(values) if len(values) >= MIN_SAMPLES else None,
              'minimum_descriptive_samples': MIN_SAMPLES, 'sample_limit_per_role': MAX_SAMPLES,
              'status': 'report_only_candidate' if len(values) >= MIN_SAMPLES else
                        'insufficient_samples' if compatible else 'unavailable',
              'headroom': {target: {role: _headroom(_values(entry, rows, target), threshold)
                                   for role, rows in roles.items()}
                           for target, threshold in entry['targets'].items()},
              'capture_evidence': [row['evidence_sha256'] for role in roles.values() for row in role],
              'rejections': {name: count for name, count in rejected.items() if count},
              'qualification': 'not_qualified', 'enforced': False,
              'notes': ['independent validation runs are never training samples',
                        'observed headroom does not establish tail safety or enforcement',
                        'no hard deadline, memory or work limit is inferred from expected cost']}
    result['unresolved_declared_evidence'] = sorted(set(entry.get('headroom_evidence', [])) - set(result['capture_evidence']))
    result['evidence_gaps'] = [name for name, missing in (
        ('compatible_capture_provenance', not compatible),
        ('descriptive_calibration_samples', len(values) < MIN_SAMPLES),
        ('independent_validation_runs', not roles['validation']),
        ('isolated_measurement', not cohort or cohort['measurement_kind'] != 'isolated'),
        ('declared_evidence_not_resolved', bool(result['unresolved_declared_evidence'])),
    ) if missing]
    result['unknown_metrics'] = {role: [target for target, threshold in entry['targets'].items()
                                      if threshold is not None and not _values(entry, rows, target)]
                                 for role, rows in roles.items()}
    result['holdout_status'] = ('not_observed' if not roles['validation'] else
        'contains_exceedances' if any(values['validation']['status'] == 'exceeded' for values in result['headroom'].values())
        else 'observed_only')
    return result
