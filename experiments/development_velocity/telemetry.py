"""Observed development timeline. Unmeasured time is never called model thinking."""
import argparse
import json
import os
from pathlib import Path
import re

from experiments.application_comparison import session, tool_metrics
from experiments.application_comparison.participant_gateway import Gateway
from experiments.application_comparison.storage import (
    digest, inventory, locked, read_json, source_files, write_json,
)

PURPOSES = frozenset(('inspect', 'edit', 'compile', 'test', 'debug', 'benchmark', 'other'))


def host_sample():
    return {'load_average': list(os.getloadavg()), 'logical_cpus': os.cpu_count()}


def source_receipt(work):
    files = source_files(work)
    return files, inventory(files)


class ObservedGateway(Gateway):
    """Retain gateway overhead and edits, including rejected operations and crashes.

    Purpose labels are participant declarations. They do not classify the time
    preceding a command or the individual programs in a shell command.
    """

    def dispatch(self, name, arguments):
        directory = self.root / 'telemetry'
        directory.mkdir(exist_ok=True)
        with locked(directory):
            index = len(list(directory.glob('[0-9]' * 6)))
            attempt = directory / f'{index:06}'
            attempt.mkdir(exist_ok=False)
            started = session.clock()
            manifest = session.load(self.root)
            phase = manifest['phase']
            work = self.root / ('practice' if phase == 'preparing' else 'work')
            purpose = arguments.get('purpose') if isinstance(arguments, dict) else None
            request = {'version': 'development-operation-v1', 'operation': name,
                       'arguments': arguments, 'phase': phase, 'started': started,
                       'purpose_source': 'participant-declared' if purpose else None,
                       'host_before': host_sample(), 'session_before_sha256': digest(manifest)}
            write_json(attempt / 'request.json', request)
            response, failure, before, after = None, None, None, None
            before_error, after_error, files, before_files = None, None, {}, {}
            capture_start = session.clock()
            try:
                if purpose is not None and (name != 'command' or purpose not in PURPOSES):
                    raise ValueError('invalid command purpose')
                try:
                    before_files, before = source_receipt(work)
                except (OSError, ValueError) as error:
                    before_error = str(error)
                capture_finished = session.clock()
                clean_arguments = {k: v for k, v in arguments.items() if k != 'purpose'} if isinstance(arguments, dict) else arguments
                dispatch_started = session.clock()
                try:
                    response = (self.output(directory, index, clean_arguments) if name == 'output'
                                else super().dispatch(name, clean_arguments))
                finally:
                    dispatch_finished = session.clock()
            except BaseException as error:
                failure = {'type': type(error).__name__, 'message': str(error)}
                raise
            finally:
                try:
                    files, after = source_receipt(work)
                except (OSError, ValueError) as error:
                    after_error = str(error)
                changed = sorted(k for k in (before or {}).keys() | (after or {}).keys()
                                 if (before or {}).get(k) != (after or {}).get(k))
                for relative in changed:
                    if relative in files:
                        path = attempt / 'changed-source' / relative
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_bytes(files[relative])
                finished = session.clock()
                record = {'version': 'development-operation-v1', 'request_sha256': digest(request),
                          'finished': finished, 'host_after': host_sample(),
                          'elapsed_seconds': session.elapsed(started, finished),
                          'source_before': before, 'source_after': after,
                          'changed_files': sorted(k for k in before.keys() | after.keys() if before.get(k) != after.get(k))
                                           if before is not None and after is not None else None,
                          'source_capture_complete': before is not None and after is not None,
                          'source_capture_error': {'before': before_error, 'after': after_error},
                          'response': response, 'failure': failure}
                if before is not None and after is not None:
                    record['source_size_changes'] = [
                        {'file': name, 'before_bytes': len(before_files.get(name, b'')),
                         'after_bytes': len(files.get(name, b'')),
                         'before_lines': len(before_files.get(name, b'').splitlines()),
                         'after_lines': len(files.get(name, b'').splitlines())}
                        for name in changed if Path(name).suffix in ('.my', '.py')]
                else:
                    record['source_size_changes'] = None
                if 'capture_finished' in locals():
                    record['before_capture_seconds'] = session.elapsed(capture_start, capture_finished)
                if 'dispatch_finished' in locals():
                    record['dispatch_started'] = dispatch_started
                    record['dispatch_finished'] = dispatch_finished
                    record['dispatch_seconds'] = session.elapsed(dispatch_started, dispatch_finished)
                write_json(attempt / 'result.json', record)
            return dict(response, operation_record=index) if isinstance(response, dict) else response

    def output(self, directory, current, arguments):
        if not isinstance(arguments, dict) or set(arguments) != {'record', 'offset', 'limit'}:
            raise ValueError('output requires record, offset, limit')
        record, offset, limit = (arguments[key] for key in ('record', 'offset', 'limit'))
        if (type(record) is not int or not 0 <= record < current or type(offset) is not int or
                offset < 0 or type(limit) is not int or not 1 <= limit <= 8192):
            raise ValueError('invalid output range')
        previous = read_json(directory / f'{record:06}' / 'result.json')
        raw = json.dumps(previous['response'], ensure_ascii=False)
        return {'record': record, 'offset': offset, 'text': raw[offset:offset + limit],
                'total_characters': len(raw), 'next_offset': min(len(raw), offset + limit)}


def clipped_interval(start, finish, lower, upper):
    session.elapsed(start, finish)
    session.elapsed(lower, upper)
    if start['boot_id'] != lower['boot_id']:
        raise ValueError('timeline boot identity mismatch')
    lo = max(start['monotonic_ns'], lower['monotonic_ns'])
    hi = min(finish['monotonic_ns'], upper['monotonic_ns'])
    return (lo, hi) if hi > lo else None


def diagnostic_codes(text):
    return sorted(set(re.findall(r'\bE_[A-Z][A-Z_0-9]+\b', text)))


def failure_diagnostic_codes(response):
    """Exclude successful source/doc reads containing examples of error codes."""
    streams = []
    if response.get('returncode', 0) not in (None, 0):
        streams.append(response.get('stderr', ''))
    if response.get('passed') is False:
        streams.extend(row.get('stderr', '') for row in response.get('diagnostics', [])
                       if row.get('returncode', 0) not in (None, 0))
    return diagnostic_codes('\n'.join(streams))


def phase_records(data):
    """Keep individual measurements; nested/inclusive records are not summed."""
    records = []
    for line in data.splitlines():
        if not line.startswith('{'):
            continue
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if not isinstance(row, dict) or row.get('version') != 'phase-timings-v1':
            continue
        if (row.get('kind') != 'timing' or type(row.get('duration_ns')) is not int or
                row['duration_ns'] < 0 or type(row.get('inclusive')) is not bool or
                not isinstance(row.get('name'), str)):
            raise ValueError('invalid compiler phase timing record')
        records.append(row)
    return records


def summarize(root):
    root = Path(root)
    manifest = session.load(root)
    if manifest['phase'] != 'sealed':
        raise ValueError('profile requires a sealed attempt; retain pending attempts separately')
    lower, upper = manifest['task_started'], manifest['sealed']
    duration = session.elapsed(lower, upper)
    operations, intervals, categories, diagnostic_history = [], [], {}, []
    paths = sorted((root / 'telemetry').glob('[0-9]' * 6))
    for path in paths:
        request = read_json(path / 'request.json')
        result = read_json(path / 'result.json')  # Missing completion is an error, never silently excluded.
        if result['request_sha256'] != digest(request):
            raise ValueError('operation request identity mismatch')
        if request['phase'] != 'working':
            continue
        interval = clipped_interval(request['started'], result['finished'], lower, upper)
        if interval is not None:
            intervals.append(interval)
        response = result['response'] or {}
        codes = failure_diagnostic_codes(response)
        arguments = request['arguments'] if isinstance(request['arguments'], dict) else {}
        label = arguments.get('purpose') or request['operation']
        if interval is not None:
            categories[label] = categories.get(label, 0) + (interval[1] - interval[0]) / 1e9
        row = {'record': path.name, 'operation': request['operation'],
               'purpose': arguments.get('purpose'),
               'purpose_source': request['purpose_source'],
               'start_seconds': session.elapsed(lower, request['started']),
               'elapsed_seconds': result['elapsed_seconds'],
               'dispatch_seconds': result.get('dispatch_seconds'),
               'changed_files': result['changed_files'], 'diagnostic_codes': codes,
               'source_size_changes': result.get('source_size_changes'),
               'failed': result['failure'] is not None or response.get('passed') is False or
                         response.get('returncode', 0) not in (None, 0),
               'request_sha256': digest(request), 'result_sha256': digest(result)}
        operations.append(row)
        if codes:
            diagnostic_history.append({'record': path.name, 'codes': codes})
    if any(b[0] < a[1] for a, b in zip(sorted(intervals), sorted(intervals)[1:])):
        raise ValueError('serialized operation timelines overlap')
    covered = tool_metrics.interval_seconds(intervals)
    metrics = tool_metrics.summarize(root)
    if metrics['uncommitted_command_records']:
        raise ValueError('incomplete gateway commands are present')
    compiler = []
    streams = [path for path in sorted(root.glob('gateway/*/stderr'))
               if read_json(path.with_name('request.json'))['phase'] == 'working']
    streams += sorted(root.glob('submissions/*/check/**/*.stderr'))
    for path in streams:
        for row in phase_records(path.read_text(errors='replace')):
            compiler.append({'evidence': str(path.relative_to(root)), **row})
    observed = bool(paths)
    return {'version': 'development-profile-v1', 'session_sha256': digest(manifest),
            'task': manifest['block'], 'language': manifest['language'],
            'application_seconds': duration, 'operation_telemetry_available': observed,
            'observed_operation_seconds': covered if observed else None,
            'unobserved_seconds': max(0, duration - covered) if observed else None,
            'start_to_first_operation_seconds': operations[0]['start_seconds'] if operations else None,
            'operation_seconds_by_declared_purpose': categories if observed else None,
            'operations': operations, 'diagnostic_history': diagnostic_history,
            'compiler_phase_records': compiler, 'gateway_metrics': metrics,
            'model_requests': None, 'model_tokens': None, 'queue_wait_seconds': None,
            'limitations': [
                'Unobserved time includes drafting, reasoning, scheduling and orchestration; its components are unknown.',
                'Purpose labels are participant declarations, not measured cognitive activity.',
                'Operation time includes hashing, source capture, namespace setup and feedback publication.',
                'Compiler phases are nested within operations; inclusive durations must not be added to them.',
                'Diagnostic disappearance does not prove a fix; command selection may have changed.',
                'Captured output bytes are not model tokens or source bytes read.',
            ]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('session', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = summarize(args.session)
    with args.output.open('x') as stream:
        json.dump(report, stream, indent=2, allow_nan=False)
        stream.write('\n')


if __name__ == '__main__':
    main()
