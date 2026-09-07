"""Descriptive fixture outcomes over all assigned attempts; no causal language claims."""
from pathlib import Path
import statistics
import itertools
import math
from . import adjudication, cohort, session, tool_metrics
from .storage import digest, locked, read_json


def partial_phases(root, state):
    """Recover completed phase receipts when the overall driver has no result."""
    result, receipts, tokens = {}, {}, []
    for name, active in (('preparation', 'preparing'), ('task', 'working')):
        directory = Path(root) / ('model-' + name)
        if not (directory / 'result.json').exists():
            continue
        report = read_json(directory / 'result.json')
        config = read_json(directory / 'configuration.json')
        if (report.get('version') != 'participant-model-loop-v1' or
                report.get('configuration_sha256') != digest(config) or
                report.get('record_kind') != state['record_kind'] or
                config.get('record_kind') != state['record_kind'] or
                config.get('model') != state['model'] or config.get('phase') != active):
            raise ValueError('partial phase report provenance mismatch')
        usage = report['reported_usage']
        if (any(type(usage.get(key)) is not int or usage[key] < 0
                for key in ('input_tokens', 'output_tokens', 'total_tokens')) or
                usage['input_tokens'] + usage['output_tokens'] != usage['total_tokens']):
            raise ValueError('invalid partial phase usage')
        result[name + '_stop'] = report['stop']
        tokens.append(usage['total_tokens'])
        receipts[name] = {'result_sha256': digest(report), 'configuration_sha256': digest(config),
                          'reported_usage': usage, 'usage_complete': report['usage_complete']}
    return dict(result, partial_reported_tokens=sum(tokens) if tokens else None, partial_phase_receipts=receipts)


def aggregate(rows):
    def reasons(field):
        known = [row[field] for row in rows if isinstance(row.get(field), str)]
        return {'counts': {reason: known.count(reason) for reason in sorted(set(known))},
                'observed': len(known), 'missing': len(rows) - len(known)}
    def timing(field):
        known = [row[field] for row in rows if row.get(field) is not None]
        return {'observed': len(known), 'missing': len(rows) - len(known),
                'total_seconds': sum(known) if known else None,
                'median_seconds': statistics.median(known) if known else None}
    accepted = sum(row.get('accepted') is True for row in rows)
    graded = sum(row['status'] == 'graded' for row in rows)
    usage = [row['reported_tokens'] for row in rows if row.get('reported_tokens') is not None]
    partial = [row['partial_reported_tokens'] for row in rows if row.get('partial_reported_tokens') is not None]
    return {'assigned': len(rows), 'graded': graded, 'accepted': accepted,
            'accepted_fraction_of_assigned': accepted / len(rows) if rows else None,
            'grading_complete': graded == len(rows),
            'status_counts': {status: sum(row['status'] == status for row in rows) for status in sorted({row['status'] for row in rows})},
            'preparation': timing('preparation_seconds'), 'task': timing('task_seconds'),
            'reported_tokens': sum(usage) if usage else None,
            'partial_reported_tokens': sum(partial) if partial else None,
            'partial_token_observations': len(partial),
            'token_observations': len(usage), 'token_telemetry_complete': all(row.get('usage_complete') is True for row in rows),
            'preparation_stops': reasons('preparation_stop'), 'task_stops': reasons('task_stop'),
            'seal_reasons': reasons('seal_reason'), 'interruption_types': reasons('interruption_type'),
            'review_categories': reasons('review_category'), 'review_statuses': reasons('review_status'),
            'cost_per_accepted_change': None}


def paired_outcomes(rows):
    pairs = {}
    for row in rows:
        if row['language'] not in cohort.LANGUAGES:
            raise ValueError('unknown paired language')
        pair = pairs.setdefault(row['pair_id'], {})
        if row['language'] in pair:
            raise ValueError('duplicate language in matched attempt')
        pair[row['language']] = row
    comparisons = {}
    for left, right in itertools.combinations(cohort.LANGUAGES, 2):
        counts = dict(both_accepted=0, left_only_accepted=0, right_only_accepted=0, neither_accepted=0, incomplete=0)
        ratios = []
        for pair in pairs.values():
            a, b = pair.get(left), pair.get(right)
            if a is None or b is None or a['status'] != 'graded' or b['status'] != 'graded':
                counts['incomplete'] += 1
                continue
            if type(a.get('accepted')) is not bool or type(b.get('accepted')) is not bool:
                raise ValueError('graded paired outcomes require explicit acceptance')
            if a['accepted'] and b['accepted']:
                counts['both_accepted'] += 1
                times = (a.get('task_seconds'), b.get('task_seconds'))
                if all(type(value) in (int, float) and math.isfinite(value) and value > 0 for value in times):
                    ratios.append(times[0] / times[1])
            elif a['accepted']:
                counts['left_only_accepted'] += 1
            elif b['accepted']:
                counts['right_only_accepted'] += 1
            else:
                counts['neither_accepted'] += 1
        graded = len(pairs) - counts['incomplete']
        comparisons[left + '_vs_' + right] = dict(counts, left=left, right=right,
            assigned_pairs=len(pairs), graded_pairs=graded,
            paired_acceptance_difference=((counts['left_only_accepted'] - counts['right_only_accepted']) / graded if graded else None),
            task_time_ratio_when_both_accepted={'numerator': left, 'denominator': right, 'observed_pairs': len(ratios),
                'missing_timing_pairs': counts['both_accepted'] - len(ratios),
                'median_ratio': statistics.median(ratios) if ratios else None},
            interpretation='Descriptive within-cohort counts; conditional timing does not measure overall productivity.')
    return comparisons


def summarize(cohort_directory, grading_directories, *, arm='main', reviews=None):
    root = Path(cohort_directory)
    manifest = cohort.load(root)
    if manifest['record_kind'] not in ('fixture', 'calibration') or arm not in ('main', 'language-focused'):
        raise ValueError('summary supports unscored fixture/calibration cohorts and declared arms only')
    records = []
    if reviews is not None:
        with locked(reviews):
            records = adjudication.read_records(reviews)
    graded = {}
    for directory in map(Path, grading_directories):
        result = read_json(directory / 'result.json')
        configuration = read_json(directory / 'configuration.json')
        verified = read_json(directory / 'verified/result.json')
        pack = read_json(directory / 'verified/pack/result.json')
        if (any(item.get('record_kind') != manifest['record_kind'] for item in (result, verified, pack)) or
                (directory / 'interrupted.json').exists() or (directory / 'verified/interrupted.json').exists() or
                result['cohort_sha256'] != manifest['sha256'] or configuration['cohort_sha256'] != manifest['sha256'] or
                result['grading'] != verified or result['verified_grading_sha256'] != digest(verified) or
                verified['grading'] != pack or verified['pack_result_sha256'] != digest(pack)):
            raise ValueError('grading report provenance mismatch')
        pair = configuration['pair_id']
        if pair in graded:
            raise ValueError('duplicate grading result for matched attempt')
        graded[pair] = (configuration, pack)
    rows = []
    used = set()
    for scheduled in manifest['schedule']:
        row = dict(session_id=scheduled['session_id'], pair_id=scheduled['pair_id'], language=scheduled['language'],
                   status='not-launched', accepted=None, preparation_seconds=None, task_seconds=None,
                   reported_tokens=None, usage_complete=False, preparation_stop=None, task_stop=None,
                   partial_reported_tokens=None, partial_phase_receipts={},
                   review_status='not-requested' if reviews is None else 'unreviewed',
                   review_category=None, review_sha256=None,
                   seal_reason=None, interruption_type=None, interruption_phase=None)
        registry = root / (manifest['record_kind'] + '-reservations') / arm / row['session_id'] / 'reservation.json'
        if registry.exists():
            reservation = read_json(registry)
            if reservation.get('status') != 'prepared':
                row['status'] = 'provisioning-incomplete'
            else:
                state_root = Path(reservation['directory']) / 'session'
                state = session.load(state_root)
                if state['cohort'] != manifest['sha256'] or state['participant'] != row['session_id'] or state['arm'] != arm:
                    raise ValueError('session summary identity mismatch')
                if reviews is not None:
                    row.update(adjudication.for_session(records, state_root, state))
                row['tool_metrics'] = tool_metrics.summarize(state_root)
                if row['tool_metrics']['session_sha256'] != digest(state):
                    raise ValueError('session changed during tool summary')
                row['status'] = 'sealed-ungraded' if state['phase'] == 'sealed' else 'in-progress'
                if state.get('preparation') is not None:
                    row['preparation_seconds'] = state['preparation']['elapsed_seconds']
                if state['phase'] == 'sealed':
                    row.update(preparation_seconds=state['preparation']['elapsed_seconds'], task_seconds=state['participant_seconds'],
                               seal_reason=state['seal_reason'])
                driver = state_root / 'driver/result.json'
                if driver.exists():
                    observed = read_json(driver)
                    if observed['session_sha256'] != digest(state):
                        raise ValueError('driver summary identity mismatch')
                    row.update(reported_tokens=observed['reported_usage']['total_tokens'], usage_complete=observed['usage_complete'])
                    row.update(preparation_stop=observed['preparation']['stop'], task_stop=observed['task']['stop'])
                else:
                    row.update(partial_phases(state_root, state))
                if (state_root / 'driver/interrupted.json').exists():
                    interruption = read_json(state_root / 'driver/interrupted.json')
                    row['status'] = 'infrastructure-failure'
                    row.update(interruption_type=interruption.get('type'), interruption_phase=interruption.get('phase'))
                if row['pair_id'] in graded:
                    configuration, pack = graded[row['pair_id']]
                    if configuration['sessions'].get(row['language']) != digest(state) or state['phase'] != 'sealed':
                        raise ValueError('graded summary session mismatch')
                    outcome = pack['outcomes'][row['language']]
                    row.update(status='graded', accepted=outcome['accepted'], failed_cases=outcome['failed_cases'])
                    used.add(row['pair_id'])
        rows.append(row)
    if used != set(graded):
        raise ValueError('grading results do not belong to the assigned arm and attempts')
    return {'version': manifest['record_kind'] + '-cohort-summary-v1', 'record_kind': manifest['record_kind'], 'cohort_sha256': manifest['sha256'], 'arm': arm,
            'languages': {language: aggregate([row for row in rows if row['language'] == language]) for language in cohort.LANGUAGES},
            'attempts': rows, 'paired': paired_outcomes(rows), 'comparative_claim': False,
            'reviews_head_sha256': records[-1]['sha256'] if records else None,
            'limitations': ['Unfinished assignments remain in the denominator.', 'Reported tokens are not monetary cost.',
                           'Phase times include successful and unsuccessful observed attempts; parallel durations are not experiment wall time.',
                           'Stop reasons and interruption types are recorded events, not independently reviewed root-cause labels; absent reasons remain unknown.',
                           'Partial tokens cover completed phase receipts without a final driver result; unfinished-phase usage may be missing and is never inferred as zero.',
                           'Human review categories describe current evidence only; stale reviews do not fall back to earlier labels and never change acceptance or assignment counts.',
                           'Behavioral rejection does not establish an independently reviewed root-cause defect.']}


def main():
    import argparse
    from .storage import write_json
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cohort', type=Path, required=True)
    parser.add_argument('--grading', type=Path, action='append', default=[])
    parser.add_argument('--arm', choices=('main', 'language-focused'), default='main')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reviews', type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(args.output)
    result = summarize(args.cohort, args.grading, arm=args.arm, reviews=args.reviews)
    write_json(args.output, result)
    for language, values in result['languages'].items():
        print(f"{language}: {values['accepted']} accepted / {values['assigned']} assigned; {values['graded']} graded")
    print(result['record_kind'] + ' summary only; no comparative claim. Details:', args.output)


if __name__ == '__main__':
    main()
