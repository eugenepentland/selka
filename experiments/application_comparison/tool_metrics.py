"""Observed tool-work proxies; never infer navigation relevance or cache hits."""
from pathlib import Path
import re
from . import session
from .storage import digest, read_json


def language_tool(argv, tools):
    """Recognize direct invocations of declared mounts, not strings inside scripts."""
    if not argv:
        return None
    if 'navigate' in tools:
        if argv[0] == '/tools/navigate':
            return 'navigation-client'
        if argv[0] == '/usr/bin/python3':
            index = 1
            while index < len(argv) and argv[index] in ('-S', '-B', '-I', '-u'):
                index += 1
            if index < len(argv) and argv[index] == '/tools/navigate':
                return 'navigation-client'
    if 'compiler' in tools and argv[0] == '/tools/compiler' and len(argv) > 1:
        return {'index-project': 'compiler-index', 'project-dependencies': 'compiler-dependencies',
                'check-project': 'compiler-check', 'check': 'compiler-check',
                'schema-project': 'compiler-schema', 'list-interfaces': 'compiler-schema',
                'report-project-quality': 'compiler-quality', 'report-quality': 'compiler-quality',
                'discover-project-duplicates': 'compiler-duplicates',
                'discover-duplicates': 'compiler-duplicates'}.get(argv[1])
    return None


def interval_seconds(intervals):
    """Union monotonic intervals, avoiding double counting overlapping commands."""
    end = None
    total = 0
    for start, finish in sorted(intervals):
        if finish < start:
            raise ValueError('invalid tool interval')
        total += max(0, finish - max(start, end if end is not None else start))
        end = max(finish, end if end is not None else finish)
    return total / 1_000_000_000


def summarize(root):
    root = Path(root)
    manifest = session.load(root)
    phases = {phase: {'command_count': 0, 'direct_search_commands': 0, 'failed_commands': 0,
                     'language_tool_commands': {}, 'failed_language_tool_commands': {},
                     'captured_output_bytes': 0, 'intervals': []} for phase in ('preparing', 'working')}
    recorded = set()
    for event in manifest['events']:
        if event['event'] != 'participant-command':
            continue
        details = event['details']
        name = details['record']
        if not isinstance(name, str) or re.fullmatch(r'[0-9]{6,}', name) is None or name in recorded:
            raise ValueError('invalid or duplicate tool record identity')
        recorded.add(name)
        directory = root / 'gateway' / name
        request, result = read_json(directory / 'request.json'), read_json(directory / 'result.json')
        if (digest(request) != details['request_sha256'] or digest(result) != details['result_sha256'] or
                result['request_sha256'] != digest(request)):
            raise ValueError('tool metrics record identity mismatch')
        session.elapsed(request['started'], result['finished'])
        phase = phases[request['phase']]
        phase['command_count'] += 1
        phase['direct_search_commands'] += Path(request['argv'][0]).name in ('rg', 'grep', 'find')
        phase['failed_commands'] += result['outcome'] != 'exited' or result['returncode'] != 0
        role = language_tool(request['argv'], request['tools'])
        if role is not None:
            counts = phase['language_tool_commands']
            counts[role] = counts.get(role, 0) + 1
            if result['outcome'] != 'exited' or result['returncode'] != 0:
                failed = phase['failed_language_tool_commands']
                failed[role] = failed.get(role, 0) + 1
        phase['captured_output_bytes'] += sum((directory / name).stat().st_size for name in ('stdout', 'stderr'))
        phase['intervals'].append((request['started']['monotonic_ns'], result['finished']['monotonic_ns']))
    for phase in phases.values():
        phase['command_interval_seconds'] = interval_seconds(phase.pop('intervals'))
    checks = [row for row in manifest['submissions'] if row['check'] is not None]
    repeated = sum(a['source']['sha256'] == b['source']['sha256'] for a, b in zip(checks, checks[1:]))
    latencies = [session.elapsed(row['submitted'], row['check']['finished']) for row in checks]
    pending = [path.parent.name for path in (root / 'gateway').glob('*/request.json') if path.parent.name not in recorded]
    return {'version': 'observed-tool-metrics-v1', 'session_sha256': digest(manifest), 'phases': phases,
            'task_checks': len(checks), 'adjacent_unchanged_task_checks': repeated,
            'submission_to_check_seconds': latencies, 'uncommitted_command_records': sorted(pending),
            'cache_hits': None, 'queue_wait_seconds': None, 'relevant_location_seconds': None,
            'limitations': ['Direct search counts exclude searches embedded in shells or scripts.',
                           'Language-tool counts recognize direct declared mounts only; they do not establish successful navigation, relevance, diagnostics repaired, or cache reuse.',
                           'Output bytes are captured command output, not source bytes read or model context.',
                           'Unchanged checks do not prove cache reuse; check latency is not isolated execution time.']}
