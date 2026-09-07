"""Validate independently authored references against draft packs, outside trials."""
from pathlib import Path
from . import task_pack
from .execution import correct, evaluate, freeze_adapter
from .inputs import decode_case
from .storage import digest, read_json, snapshot, verify_snapshot, write_json


def validate(pack, source, adapter, directory):
    manifest = task_pack.load(pack)
    directory = Path(directory)
    directory.mkdir(exist_ok=False)
    captured = snapshot(source, directory / 'source')
    plan = {'version': 'reference-validation-v1', 'pack_sha256': manifest['sha256'],
            'task': manifest['task'], 'source': captured, 'adapter': adapter,
            'record_kind': 'reference-construction', 'comparative_claim': False}
    write_json(directory / 'plan.json', plan)
    results = []
    for category in ('public', 'hidden'):
        cases = read_json(Path(pack) / category / 'cases.json')
        for index, item in enumerate(cases):
            request, raw, expected = decode_case(item['case'])
            execution = evaluate(directory / 'source', captured, adapter, request,
                                 directory / f'{category}-{index:03}', request_bytes=raw)
            results.append({'category': category, 'name': item['name'],
                            'passed': correct(execution['outcome'], expected),
                            'execution': execution})
    verify_snapshot(source, captured)
    if task_pack.load(pack) != manifest:
        raise ValueError('pack changed during reference validation')
    report = {'version': 'reference-validation-result-v1', 'plan_sha256': digest(plan),
              'task': manifest['task'], 'record_kind': 'reference-construction',
              'case_count': len(results), 'passed': all(result['passed'] for result in results),
              'results': results, 'comparative_claim': False}
    write_json(directory / 'result.json', report)
    return report


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pack', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--entry', default='main.py')
    args = parser.parse_args()
    if Path(args.entry).name != args.entry or not args.entry.endswith('.py'):
        parser.error('entry must be a Python filename within source')
    adapter = freeze_adapter('python', {}, [
        {'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', args.entry]}])
    report = validate(args.pack, args.source, adapter, args.directory)
    print(report['task'], 'passed' if report['passed'] else 'failed', report['case_count'], 'cases')
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
