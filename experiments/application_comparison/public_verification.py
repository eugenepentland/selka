"""Run complete public packs against one immutable source and one phase deadline."""
from .execution import correct, evaluate
from .build_reuse import BuildReuse
from .inputs import decode_case
from .storage import digest, write_json


def validate(cases):
    if not isinstance(cases, list):
        decode_case(cases)
        return
    if not cases or len(cases) > 64:
        raise ValueError('public pack requires 1..64 named cases')
    names = set()
    for item in cases:
        if (not isinstance(item, dict) or set(item) != {'name', 'case'} or
                not isinstance(item['name'], str) or not item['name'] or item['name'] in names):
            raise ValueError('invalid or duplicate public case name')
        names.add(item['name'])
        decode_case(item['case'])


def run(source, receipt, adapter, cases, directory, remaining):
    validate(cases)
    if not isinstance(cases, list):
        request, raw, expected = decode_case(cases)
        record = evaluate(source, receipt, adapter, request, directory,
                          request_bytes=raw, remaining_seconds=remaining)
        record['passed'] = correct(record['outcome'], expected) and remaining() > 0
        return record
    directory.mkdir(exist_ok=False)
    results = []
    builds = BuildReuse()
    for index, item in enumerate(cases):
        if remaining() <= 0:
            results.append({'name': item['name'], 'passed': False, 'status': 'not-run-deadline', 'record': None})
            continue
        request, raw, expected = decode_case(item['case'])
        record = evaluate(source, receipt, adapter, request, directory / f'{index:03}',
                          request_bytes=raw, remaining_seconds=remaining, build_reuse=builds)
        results.append({'name': item['name'], 'passed': correct(record['outcome'], expected) and remaining() > 0,
                        'status': 'executed', 'record': record})
    report = {'version': 'public-verification-pack-v1', 'source_sha256': receipt['sha256'],
              'cases_sha256': digest(cases), 'passed': all(item['passed'] for item in results),
              'results': results}
    write_json(directory / 'result.json', report)
    return report


def diagnostics(record, directory):
    result = []
    remaining_bytes = 65536
    records = [(None, record, directory)] if 'results' not in record else [
        (item['name'], item['record'], directory / f'{index:03}') for index, item in enumerate(record['results'])]
    for name, execution, path in records:
        if execution is None:
            result.append({'case': name, 'status': 'not-run-deadline'})
            continue
        for index, step in enumerate(execution.get('steps', [])):
            row = {'phase': step['phase'], 'returncode': step['returncode']}
            if name is not None:
                row['case'] = name
            for stream in ('stdout', 'stderr'):
                data = (path / f'{index:02}.{stream}').read_bytes()
                kept = min(len(data), 8192, remaining_bytes)
                row[stream] = data[-kept:].decode('utf-8', errors='replace') if kept else ''
                remaining_bytes -= kept
                if kept < len(data):
                    row[stream + '_truncated'] = True
            result.append(row)
    return result


def summary(record):
    return [{key: item[key] for key in ('name', 'passed', 'status')} for item in record.get('results', [])]
