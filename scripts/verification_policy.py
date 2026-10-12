"""Versioned report-only scoped limits; policy review never fabricates evidence."""
from __future__ import annotations

from verification_budgets import _digest, _json, _number

VERSION = 1
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
    if type(document['version']) is not int or document['version'] != VERSION:
        raise ValueError('unsupported policy version')
    if document['mode'] != 'report_only':
        raise ValueError('policy enforcement is not qualified')
    entries = document['entries']
    if not isinstance(entries, list) or len(entries) > 4096:
        raise ValueError('policy entry bound')
    seen = set()
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) - {'action_id', 'member_id', 'test_id', 'scope', 'targets', 'exception', 'headroom_evidence', 'work_unit'}:
            raise ValueError('policy entry fields')
        scope = entry.get('scope')
        if scope not in SCOPES:
            raise ValueError('policy clock scope')
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
        identity = (action, member, test, scope)
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
                    and row.get('clock') == CLOCKS[entry['scope']]
                    and row.get('complete') is True and row.get('successful') is True
                    and row.get('fresh') is True]
        evaluations = {}
        for target, ceiling in entry['targets'].items():
            metric = ('elapsed_seconds' if target.endswith('_seconds') else
                      'aggregate_peak_rss_bytes' if target == 'memory_ceiling_bytes' else 'completed_work')
            values = [row.get(metric) for row in matching]
            known = bool(values) and all(_number(value) for value in values)
            if target == 'work_ceiling':
                known = known and all(row.get('work_unit') == entry.get('work_unit') for row in matching)
            evaluations[target] = {
                'threshold': ceiling, 'observed_maximum': max(values) if known else None,
                'status': 'not_configured' if ceiling is None else 'unknown' if not known else
                          'exceeded' if max(values) > ceiling else 'within_observed_samples',
                'enforced': False,
            }
        result.append({'action_id': entry['action_id'], 'member_id': entry.get('member_id'),
                       'test_id': entry.get('test_id'), 'scope': entry['scope'],
                       'clock': CLOCKS[entry['scope']], 'sample_count': len(matching),
                       'evaluations': evaluations, 'exception': entry.get('exception'),
                       'headroom_status': 'unqualified', 'work_unit': entry.get('work_unit'), 'additive': False})
    return {'version': VERSION, 'mode': 'report_only', 'entries': result, 'enforced': False}
