"""Coordinator-only historical replay/reporting; never launches a participant."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import uuid

HERE = Path(__file__).resolve().parent
COHORT = HERE.parent
REPO = Path('/home/epentland/ai/canopy/mylang')
sys.dont_write_bytecode = True
sys.path.insert(0, str(REPO))
from experiments.application_comparison import (coordinator_receipt, iteration_log,
    session, single_language_grading, task_pack, tool_metrics)
from experiments.application_comparison.storage import digest, read_json, verify_snapshot


def file_ref(path):
    path = Path(path)
    return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def immutable(path, data):
    path = Path(path)
    if path.exists():
        if read_json(path) != data:
            raise ValueError('Existing evidence differs; use a new explicitly versioned report: ' + str(path))
        return
    with path.open('x') as stream:
        stream.write(json.dumps(data, indent=2, sort_keys=True, allow_nan=False) + '\n')


def catalog():
    result = read_json(HERE / 'historical.json')
    for row in result['tasks']:
        for ref in row['references'].values():
            if file_ref(ref['path']) != ref:
                raise ValueError('Historical evidence changed: ' + ref['path'])
    return result


def current(task):
    directory = COHORT / task
    manifest = session.load(directory / 'my')
    if manifest['phase'] != 'sealed':
        raise ValueError('Sealed participant required: ' + task)
    summary = read_json(directory / 'summary.json')
    row = summary['participants']['my']
    if summary['task'] != task or row['task_seconds'] != manifest['participant_seconds']:
        raise ValueError('Summary/session timing mismatch: ' + task)
    source = manifest['submissions'][manifest['final_submission']]['source'] if manifest['final_submission'] is not None else None
    if source is not None:
        verify_snapshot(directory / 'my/submissions' / f"{manifest['final_submission']:03}" / 'source', source)
    if row['source'] != source:
        raise ValueError('Summary/session source mismatch: ' + task)
    metrics = tool_metrics.summarize(directory / 'my')
    if metrics['uncommitted_command_records']:
        raise ValueError('Uncommitted gateway command evidence: ' + task)
    return directory, manifest, summary, row, metrics


def replay(row):
    task = row['task']
    directory, manifest, summary, participant, metrics = current(task)
    destination = HERE / 'replays' / task
    destination.mkdir(parents=True, exist_ok=True)
    configuration = read_json(directory / 'my-configuration.json')
    inventory = coordinator_receipt.source_inventory(REPO / 'experiments/application_comparison')
    immutable(destination / 'inputs.json', {
        'task': task, 'historical': row, 'configuration': file_ref(directory / 'my-configuration.json'),
        'session': file_ref(directory / 'my/session.json'), 'summary': file_ref(directory / 'summary.json'),
        'coordinator_source': inventory, 'helper': file_ref(__file__),
        'interpretation': 'Post-seal historical-pack acceptance replay with current frozen tools; no development time adjustment.'})
    # grade preserves individual case receipts and refuses unfinished executions.
    # It never changes the participant or its historical development clocks.
    result = single_language_grading.grade(row['pack'], directory / 'my', configuration, destination)
    immutable(destination / 'receipt.json', {
        'task': task, 'accepted': result['accepted'], 'case_count': result['case_count'],
        'failed_case_count': len(result['failed_cases']), 'plan_sha256': result['plan_sha256'],
        'result': file_ref(destination / 'result.json'), 'inputs': file_ref(destination / 'inputs.json')})
    return {'task': task, 'historical_replay_accepted': result['accepted']}


def checked_result(directory, manifest, configuration, pack):
    result = read_json(directory / 'result.json')
    plan = read_json(directory / 'plan.json')
    expected = {'version': 'single-language-grading-v1',
        'pack_sha256': task_pack.load(pack)['sha256'], 'session_sha256': digest(manifest),
        'configuration_sha256': configuration['sha256'], 'scored': False}
    if plan != expected or result['plan_sha256'] != digest(plan):
        raise ValueError('Grading receipt does not match session/configuration/pack')
    if result['case_count'] != len(result['cases']) or not result['cases']:
        raise ValueError('Incomplete grading result')
    if result['accepted'] != all(case['accepted'] for case in result['cases']):
        raise ValueError('Inconsistent grading acceptance')
    return result


def collect():
    rows = []
    for historical in catalog()['tasks']:
        task = historical['task']
        directory, manifest, summary, participant, metrics = current(task)
        replay_dir = HERE / 'replays' / task
        receipt = read_json(replay_dir / 'receipt.json')
        if file_ref(receipt['result']['path']) != receipt['result']:
            raise ValueError('Replay result changed: ' + task)
        if file_ref(receipt['inputs']['path']) != receipt['inputs']:
            raise ValueError('Replay inputs changed: ' + task)
        inputs = read_json(replay_dir / 'inputs.json')
        if inputs['session'] != file_ref(directory / 'my/session.json') or inputs['summary'] != file_ref(directory / 'summary.json'):
            raise ValueError('Replay source session/summary changed: ' + task)
        configuration = read_json(directory / 'my-configuration.json')
        if inputs['configuration'] != file_ref(directory / 'my-configuration.json'):
            raise ValueError('Replay configuration changed: ' + task)
        historical_result = checked_result(replay_dir, manifest, configuration, historical['pack'])
        fresh_result = checked_result(directory / 'grading', manifest, configuration, directory / 'pack')
        if participant['hidden']['accepted'] != fresh_result['accepted']:
            raise ValueError('Fresh summary/grading acceptance mismatch: ' + task)
        previous = dict(historical['observation'])
        now = {'task': task, 'language': 'my', 'application_seconds': participant['task_seconds'],
               'accepted': bool(fresh_result['accepted'] and historical_result['accepted']),
               'fresh_pack_accepted': fresh_result['accepted'], 'historical_pack_accepted': historical_result['accepted']}
        comparison = iteration_log.compare(task, now, previous)
        # Whitelist output fields: no private seeds, names, requests, responses or source.
        rows.append({'comparison': comparison, 'preparation_seconds': participant['preparation_seconds'],
            'public_submissions': participant['public_submissions'],
            'failed_public_submissions': participant['failed_public_submissions'],
            'seal_reason': participant['seal_reason'], 'metrics': metrics,
            'historical_metrics': historical['metrics'],
            'historical_preparation_seconds': historical['preparation_seconds'],
            'historical_source_sha256': historical['source_sha256'],
            'source_sha256': participant['source']['sha256'] if participant['source'] else None,
            'references': {'summary': file_ref(directory / 'summary.json'),
                'configuration': file_ref(directory / 'my-configuration.json'),
                'protocol': file_ref(directory / 'protocol.json'),
                'fresh_result': file_ref(directory / 'grading/result.json'),
                'historical_replay': file_ref(replay_dir / 'receipt.json'),
                'historical_evidence': historical['references']}})
    return {'version': 'velocity-v1-matched-report-v1', 'scored': False,
        'complete_task_count': len(rows), 'comparisons': rows,
        'acceptance_rule': 'Current speed reduction is reported only if fresh AND historical packs accept current development and original historical development was accepted.',
        'limitations': ['Exploratory combined intervention; changed baselines, agents, tools, guides and cases prevent causal attribution.',
            'Eight distinct tasks, not independent replications; slack inherits current accepted lag code.',
            'Historical development times are original observations; post-seal replay uses current tools and adds no development time.',
            'Gateway commands are not model turns; exact model identity, turns, tokens and cost remain unknown.',
            'Direct project-workflow counts do not establish cache reuse or relevant navigation.',
            'Source-quality reviews and owner/generic sequence must be reported separately; this report makes no code-quality claim.'],
        'historical_catalog': file_ref(HERE / 'historical.json'), 'helper': file_ref(__file__)}


def markdown(report):
    lines = ['# Velocity v1 matched historical observations', '',
        'Exploratory .my observations; no causal claim or language ranking. All eight sessions and both grading sets are complete.', '',
        '| Task | Historical seconds | Current seconds | Current fresh / replay accepted | Reduction if accepted | Workflow commands |',
        '|---|---:|---:|---|---:|---:|']
    for row in report['comparisons']:
        c = row['comparison']; now = c['current']; old = c['previous']; reduction = c['reduction_percent']
        count = row['metrics']['phases']['working']['language_tool_commands'].get('project-workflow', 0)
        lines.append(f"| {c['task']} | {old['application_seconds']:.3f} | {now['application_seconds']:.3f} | {now['fresh_pack_accepted']} / {now['historical_pack_accepted']} | {'n/a' if reduction is None else f'{reduction:.1f}%'} | {count} |")
    lines += ['', *report['limitations'], '', 'Traceable file hashes and per-task evidence references are in combined.json. Private cases and outputs are omitted.']
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='operation', required=True)
    sub.add_parser('status')
    replay_parser = sub.add_parser('replay'); replay_parser.add_argument('task', help='exact task or all')
    publish = sub.add_parser('publish'); publish.add_argument('--output', type=Path, required=True, help='new directory; all eight required')
    args = parser.parse_args()
    catalog_rows = catalog()['tasks']
    if args.operation == 'status':
        for row in catalog_rows:
            task = row['task']
            print(json.dumps({'task': task, 'summary_exists': (COHORT/task/'summary.json').exists(),
                              'replay_exists': (HERE/'replays'/task/'receipt.json').exists()}))
    elif args.operation == 'replay':
        selected = [row for row in catalog_rows if args.task in ('all', row['task'])]
        if not selected: raise ValueError('Unknown task')
        failed = False
        for row in selected:
            try:
                print(json.dumps(replay(row)))
            except Exception as error:
                # Preserve failed attempts without rewriting prior results.
                failures = HERE / 'attempts'; failures.mkdir(exist_ok=True)
                immutable(failures / (uuid.uuid4().hex + '.json'), {'task': row['task'], 'error_type': type(error).__name__, 'error': str(error)})
                print(json.dumps({'task': row['task'], 'replay': 'incomplete', 'error_type': type(error).__name__}))
                failed = True
        if failed: raise SystemExit(1)
    else:
        report = collect()  # Reject partial data before creating output.
        args.output.mkdir(parents=True, exist_ok=False)
        immutable(args.output/'combined.json', report)
        (args.output/'combined.md').write_text(markdown(report))


if __name__ == '__main__':
    main()
