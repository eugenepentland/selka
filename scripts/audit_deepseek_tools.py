#!/usr/bin/env python3
"""Audit local DSH tool latency without executing logged commands or calling a model.

Reads legacy/versioned JSONL and concatenated Zstandard JSONL (requires zstd).
Each source is copied to a fixed-size temporary snapshot before decoding. Reports
contain timings, hashes and source coordinates; command text is opt-in.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys
import tempfile


SLEEP = re.compile(r"\bsleep\s+(\d+(?:\.\d+)?)([smh]?)\b")
BUILD = re.compile(r"\bzig\s+build\b")
SCRIPT_COMMAND = re.compile(r"(?:^|[;&|\n])\s*(?:\w+=\S+\s+)*(?:python[23]?|(?:[^\s;'\"|]*/)?selka)(?:\s|$)")
TIMEOUT = re.compile(r"^Your command timed out after \d+ seconds|\[Command timed out or OOM\]", re.M)
MANAGED_TIMEOUT = re.compile(r"^\[timed out after \d+ms\]$", re.M)
EXCLUDED = {'coordinator_sleep', 'agent_wait', 'human_wait', 'manual_exclusion'}

# Background-job lifecycle. The shell tool answers a background start with
# ``started background job <id>``; the jobs plugin then splices a notice whose
# text contains ``background job <id> ... finished [status: ...]``. Pairing those
# with the first ``job_output`` call for the id separates the job's execution
# wall time from the foreground seconds the model actually blocked.
BACKGROUND_START = re.compile(r"^started background job (\S+)$", re.M)
BACKGROUND_DONE = re.compile(
    r"^background job (\S+)\b[\s\S]*?\bfinished \[status: ([a-z]+)(?:, exit code: (-?\d+))?\]\. "
    r"Read its output with job_output\.$", re.M)
# Statuses a `job_output` read can report once the job is no longer running.
TERMINAL_JOB_STATUSES = frozenset({'completed', 'failed', 'killed'})
# One comparability key for a `zig build` invocation. Two runs are only a fair
# comparison when the target, `-Dtest-filter`, optimize mode and cache condition
# all match, so the audit groups by the complete key instead of by command text.
FILTER_ARG = re.compile(r'-Dtest-filter=(?:"([^"]*)"|(\S+))')
OPTIMIZE_ARG = re.compile(r'-Doptimize=(?:"?([A-Za-z]+)"?)|-D(release[a-z-]*)|--release(?:=([a-z]+))?')
CACHE_ARG = re.compile(r'--cache-dir[= ](?:"([^"]*)"|(\S+))|ZIG_LOCAL_CACHE_DIR=(?:"([^"]*)"|(\S+))')
# A `zig build` at a command position, after env assignments and common wrappers
# (`time`, `/usr/bin/time`, `env`). The capture stops at the first shell
# separator so a trailing pipeline (`| tail`) is not mistaken for the build step.
BUILD_PREFIX = r"(?:(?:\w+=\S+|time|/usr/bin/time|env|nohup|command)\s+(?:-\S+\s+)*)*"
BUILD_ARGV = re.compile(r"(?:^|[;&|]\s*|\n\s*)" + BUILD_PREFIX + r"zig\s+build\b([^|;&<>\n]*)")
# Flags whose next token is a value, not the build step being invoked.
BUILD_VALUE_FLAGS = {
    '--summary', '--prefix', '--cache-dir', '--global-cache-dir', '--seed', '--maxrss',
    '--system', '--libc', '--search-prefix', '--color', '--zig-lib-dir', '--build-file',
}


def seconds(intervals):
    """Union millisecond intervals; overlapping tool calls count only once."""
    end = None
    total = 0
    for start, finish in sorted(intervals):
        if finish < start:
            raise ValueError('negative interval')
        total += max(0, finish - max(start, end if end is not None else start))
        end = max(finish, end if end is not None else finish)
    return total / 1000


def summarize(rows):
    values = sorted(row['seconds'] for row in rows)
    return {
        'calls': len(rows), 'call_seconds': round(sum(values), 3),
        'median_ms': round(statistics.median(values) * 1000, 3) if values else 0,
        'p95_ms': round(values[math.ceil(len(values) * .95) - 1] * 1000, 3) if values else 0,
        'max_seconds': max(values, default=0),
        'tool_error_flags': sum(row['is_error'] for row in rows),
        'persistent_timeouts': sum(row['persistent_timeout'] for row in rows),
        'output_bytes': sum(row['output_bytes'] for row in rows),
    }


def grouped(rows, key):
    groups = defaultdict(list)
    for row in rows:
        groups[row[key]].append(row)
    return dict(sorted(((name, summarize(items)) for name, items in groups.items()),
                       key=lambda pair: pair[1]['call_seconds'], reverse=True))


def result_text(blocks):
    """Only read tool-result text, never model reasoning or user messages."""
    return '\n'.join(part.get('text', '') for block in blocks
                     if block.get('type') == 'tool-result'
                     for part in block.get('content', []) if part.get('type') == 'text')


def arguments(value):
    if isinstance(value, dict):
        return value
    try:
        decoded = json.loads(value)
    except (ValueError, TypeError):
        return {}
    return decoded if isinstance(decoded, dict) else {}


def first_group(match):
    """First participating capture group, or None when the pattern missed."""
    if match is None:
        return None
    return next((group for group in match.groups() if group is not None), None)


def build_dimensions(command):
    """The comparability key of a `zig build` invocation.

    Returns ``(target, test_filter, optimize, cache)``. Two runs are only a fair
    before/after comparison when every field matches; runs with different filters
    or optimize modes measure different work.
    """
    match = BUILD_ARGV.search(command)
    if match is None:
        return None
    target, expect_value, tokens = 'install', False, match.group(1).split()
    for token in tokens:
        if expect_value:
            expect_value = False
            continue
        if token.startswith('--'):
            expect_value = token in BUILD_VALUE_FLAGS
            continue
        if not token or token.startswith('-') or '=' in token:
            continue
        if any(character in token for character in '&|;<>'):
            continue
        if re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]*', token) is None:
            continue
        target = token
        break
    return (target,
            first_group(FILTER_ARG.search(command)),
            first_group(OPTIMIZE_ARG.search(command)) or 'default',
            first_group(CACHE_ARG.search(command)) or 'default')


def notice_text(event):
    """The model-visible text of a job-jobs completion notice, or an empty string."""
    data = event.get('data', {})
    if event.get('type') == 'agent/inbox/spliced':
        parts = [part for item in data.get('inserted', []) for part in item.get('content', [])]
    elif event.get('type') == 'user/message':
        source = data.get('source', {})
        if source.get('kind') != 'plugin' or source.get('form') != 'notice':
            return ''
        parts = data.get('content', [])
    else:
        return ''
    return '\n'.join(part.get('text', '') for part in parts if part.get('type') == 'text')


def parse_events(events, source):
    """Pair by call id inside one session; discard inherited seed events."""
    pending, steps, schema = {}, {}, {}
    calls, models, schemas, issues, notices = [], [], [], [], []
    header, seed_end, last_time, retries, orphan_results = {}, -1, None, 0, 0
    inherited_calls = 0
    for event in events:
        kind, data = event.get('type'), event.get('data', {})
        timestamp, seq = event.get('time'), event.get('seq', -1)
        if kind == 'session':
            header = event
            continue
        if isinstance(timestamp, (int, float)):
            last_time = max(timestamp, last_time or timestamp)
        if kind == 'session/end-seed':
            seed_end = seq
            inherited_calls += len(calls)
            calls.clear()
            models.clear()
            pending.clear()
            steps.clear()
            retries = orphan_results = 0
        elif kind == 'request/header':
            tools = data.get('header', {}).get('tools', [])
            bash = next((tool for tool in tools if tool.get('name') == 'bash'), None)
            if bash is not None:
                properties = bash.get('parameters', {}).get('properties', {})
                schema = {'bash_parameters': sorted(properties),
                          'background_supported': 'run_in_background' in properties}
                schemas.append(schema)
        elif kind == 'step/start':
            steps[(data.get('turn'), data.get('step'))] = timestamp
        elif kind == 'assistant/message':
            start = steps.pop((data.get('turn'), data.get('step')), None)
            if start is not None and timestamp is not None and timestamp >= start:
                models.append((start, timestamp))
        elif kind == 'llm/retry':
            retries += 1
        elif kind in {'agent/inbox/spliced', 'user/message'}:
            text = notice_text(event)
            # An inbox splice is the jobs plugin reacting to settlement; the
            # delivered copy is the same text entering the model's context. Keep
            # them apart so notification delay is not charged to execution.
            form = 'inbox' if kind == 'agent/inbox/spliced' else 'delivered'
            for match in BACKGROUND_DONE.finditer(text):
                if timestamp is not None:
                    notices.append({'session': header.get('id', source), 'job_id': match.group(1),
                                    'time_ms': timestamp, 'seq': seq, 'form': form, 'status': match.group(2),
                                    'exit_code': int(match.group(3)) if match.group(3) is not None else None})
        elif kind == 'tool/call':
            call_id = data.get('callId')
            if call_id in pending:
                issues.append(f'duplicate pending call id at seq {seq}')
            pending[call_id] = (event, schema.copy())
        elif kind == 'tool/result':
            message = data.get('message', {})
            blocks = message.get('content', [])
            call_id = message.get('source', {}).get('callId')
            if call_id is None:
                call_id = next((b.get('toolCallId') for b in blocks if b.get('type') == 'tool-result'), None)
            pair = pending.pop(call_id, None)
            if pair is None:
                orphan_results += 1
                continue
            call, call_schema = pair
            start = call.get('time')
            if start is None or timestamp is None or timestamp < start:
                issues.append(f'invalid call timestamps at seq {call.get("seq")}')
                continue
            request = call['data']
            args = arguments(request.get('arguments'))
            command = args.get('command', '')
            command = command if isinstance(command, str) else ''
            text = result_text(blocks)
            is_error = any(b.get('isError', False) for b in blocks if b.get('type') == 'tool-result')
            started = BACKGROUND_START.search(text)
            calls.append({
                'session': header.get('id', source), 'seq': call.get('seq'), 'result_seq': seq,
                'call_id': call_id, 'start_ms': start, 'end_ms': timestamp,
                'seconds': (timestamp - start) / 1000, 'name': request.get('name', 'unknown'),
                'depth': header.get('delegationDepth', 0), 'args': args, 'command': command,
                'command_sha256': hashlib.sha256(command.encode()).hexdigest() if command else None,
                'is_error': bool(is_error), 'persistent_timeout': bool(TIMEOUT.search(text)),
                'managed_timeout': bool(MANAGED_TIMEOUT.search(text)),
                'shell_reset': 'The persistent bash shell was reset' in text,
                'truncated': '<response clipped>' in text or '[output truncated]' in text,
                'output_bytes': len(text.encode()),
                'explicit_nonzero_exit': bool(re.search(r'\[(?:Command finished with exit code |exit code: )[1-9]\d*\]', text)),
                'guardian_failed': bool(re.search(r'guardian/test: FAIL|"failed"\s*:\s*[1-9]', text)),
                'background_started': args.get('run_in_background') is True,
                'background_job_id': started.group(1) if started else None,
                'job_status': first_group(re.search(r'\[status: ([a-z]+)', text)),
                'schema': call_schema, 'turn': request.get('turn'), 'step': request.get('step'),
            })
    return {'header': header, 'source': source, 'calls': calls, 'model_intervals': models,
            'notices': notices, 'unfinished_calls': len(pending), 'orphan_results': orphan_results,
            'issues': issues, 'last_event_ms': last_time, 'seed_end_seq': seed_end,
            'llm_retries': retries, 'schemas': schemas, 'inherited_calls_skipped': inherited_calls}


def read_session(path):
    """Decode an immutable per-file snapshot; surface incomplete live tails."""
    problems = []
    with tempfile.TemporaryFile() as snapshot, tempfile.TemporaryFile() as errors:
        before = path.stat()
        remaining = before.st_size
        digest = hashlib.sha256()
        with path.open('rb') as stream:
            while remaining:
                chunk = stream.read(min(remaining, 1024 * 1024))
                if not chunk:
                    problems.append('source became shorter while copying')
                    break
                snapshot.write(chunk)
                digest.update(chunk)
                remaining -= len(chunk)
        snapshot.seek(0)
        process = None
        decoded = snapshot
        if path.suffix == '.zstd':
            process = subprocess.Popen(['zstd', '-dc'], stdin=snapshot, stdout=subprocess.PIPE, stderr=errors)
            decoded = process.stdout

        def records():
            for number, line in enumerate(decoded, 1):
                try:
                    record = json.loads(line)
                except (ValueError, UnicodeDecodeError):
                    problems.append(f'invalid/incomplete JSON at line {number}')
                    continue
                if not isinstance(record, dict):
                    problems.append(f'non-object JSON at line {number}')
                    continue
                yield record

        try:
            session = parse_events(records(), str(path))
        finally:
            if process is not None:
                decoded.close()
                code = process.wait()
                if code:
                    problems.append(f'zstd exited {code}; decoded prefix only (possibly an active append)')
        after = path.stat()
    session['issues'].extend(problems)
    session['snapshot'] = {'bytes': before.st_size - remaining, 'sha256': digest.hexdigest(),
                           'mtime_ns': before.st_mtime_ns,
                           'changed_during_read': (after.st_size, after.st_mtime_ns) != (before.st_size, before.st_mtime_ns)}
    return session


def classify(row, coordinators, exclusions):
    """Conservative command-text hints; not a shell parser or CPU attribution."""
    if f'{row["session"]}:{row["seq"]}' in exclusions:
        return 'manual_exclusion'
    name, command = row['name'], row['command']
    if name in {'wait_agent', 'wait_agents', 'wait', 'list_agents'}:
        return 'agent_wait'
    if name in {'ask_user_question', 'request_user_input'}:
        return 'human_wait'
    if name == 'job_output':
        return 'job_collection'
    if name != 'bash':
        return 'other_tools'
    if SLEEP.search(command):
        # Deliberately excludes more than proven agent waits. Root/parent sleeps
        # can mix coordination and build polling; no inferred savings for them.
        if row['depth'] == 0 or row['session'] in coordinators:
            return 'coordinator_sleep'
        return 'worker_sleep_or_poll'
    if BUILD.search(command):
        if '-Dtest-filter' in command:
            return 'zig_build_filtered'
        if re.search(r'\bzig\s+build\s+test(?:\b|-)', command):
            return 'zig_test_unfiltered'
        return 'zig_build_other'
    if re.search(r'\bguardian-check\b', command):
        return 'guardian_command'
    if SCRIPT_COMMAND.search(command) or re.search(r'\.zig-cache/o/[^\s]+/test\b', command):
        return 'scripts_compiler_or_mixed'
    if re.search(r'\bgrep\s+-[A-Za-z]*[rR]', command):
        return 'recursive_grep'
    if re.search(r'\b(?:rg|grep|find|cat|sed|head|tail)\b', command):
        return 'read_search_or_mixed'
    if re.search(r'\bgit\s', command):
        return 'git_or_mixed'
    return 'other_shell'


def public_call(row, include_commands=False):
    result = {k: v for k, v in row.items() if k not in {'args', 'command'}}
    if include_commands:
        result['command'] = row['command']
    return result


def utc(milliseconds):
    return datetime.fromtimestamp(milliseconds / 1000, timezone.utc).isoformat() if milliseconds is not None else None


def job_waits(rows):
    """Every `job_output` call, whether or not it pairs with a started job."""
    waits = []
    for row in rows:
        if row['name'] != 'job_output':
            continue
        job_id = row['args'].get('job_id')
        waits.append({
            'session': row['session'], 'seq': row['seq'],
            'job_id': job_id if isinstance(job_id, str) else None,
            'read_seconds': round(row['seconds'], 3),
            'wait': row['args'].get('wait') is True,
            'status': row.get('job_status'),
        })
    return waits


def background_jobs(rows, notices):
    """Pair each managed background start with settlement, delivery and every read.

    ``completed_ms`` is the jobs plugin reacting to settlement (the inbox
    splice); ``delivered_ms`` is that same notice reaching the model. Every
    ``job_output`` call for the id is counted, and a terminal read bounds
    completion when no notice was captured.
    """
    notices_by_key = defaultdict(list)
    for notice in notices:
        notices_by_key[(notice['session'], notice['job_id'])].append(notice)
    reads_by_key = defaultdict(list)
    for row in rows:
        if row['name'] != 'job_output':
            continue
        job_id = row['args'].get('job_id')
        if isinstance(job_id, str):
            reads_by_key[(row['session'], job_id)].append(row)
    starts = sorted((row for row in rows if row.get('background_job_id')), key=lambda row: row['start_ms'])
    matched = {(row['session'], row['background_job_id']) for row in starts}
    jobs = []
    for start in starts:
        key = (start['session'], start['background_job_id'])
        events = sorted(notices_by_key.get(key, []), key=lambda event: (event['time_ms'], event['seq']))
        inbox = next((event for event in events if event['form'] == 'inbox'), None)
        delivered = next((event for event in events if event['form'] == 'delivered'), None)
        reads = sorted(reads_by_key.get(key, []), key=lambda row: row['start_ms'])
        terminal = [row for row in reads if row.get('job_status') in TERMINAL_JOB_STATUSES]
        read_bound = min((row['end_ms'] for row in terminal), default=None)
        completed = inbox['time_ms'] if inbox else (delivered['time_ms'] if delivered else read_bound)
        source = ('settlement-notice' if inbox else
                  'delivery-notice' if delivered else
                  'terminal-read' if read_bound is not None else None)
        consumed = reads[0]['start_ms'] if reads else None
        waited = [row for row in reads if row['args'].get('wait') is True]
        notice = inbox or delivered
        outcome = notice['status'] if notice else (terminal[0]['job_status'] if terminal else None)
        jobs.append({
            'job_id': start['background_job_id'], 'session': start['session'], 'start_seq': start['seq'],
            'started_at': utc(start['start_ms']),
            'completed_at': utc(completed) if completed is not None else None,
            'completion_source': source,
            'delivered_at': utc(delivered['time_ms']) if delivered else None,
            'consumed_at': utc(consumed) if consumed is not None else None,
            'execution_seconds': round((completed - start['start_ms']) / 1000, 3)
                                  if completed is not None and completed >= start['start_ms'] else None,
            'notification_delay_seconds': round((delivered['time_ms'] - completed) / 1000, 3)
                                          if delivered is not None and completed is not None and delivered['time_ms'] >= completed else None,
            'completion_to_consumption_seconds': round((consumed - completed) / 1000, 3)
                                                 if completed is not None and consumed is not None and consumed >= completed else None,
            'delivery_to_consumption_seconds': round((consumed - delivered['time_ms']) / 1000, 3)
                                               if delivered is not None and consumed is not None and consumed >= delivered['time_ms'] else None,
            'start_blocked_seconds': round(start['seconds'], 3),
            'read_count': len(reads),
            'read_blocked_seconds': round(sum(row['seconds'] for row in reads), 3),
            'wait_calls': len(waited),
            'wait_blocked_seconds': round(sum(row['seconds'] for row in waited), 3),
            'outcome': outcome,
            'exit_code': notice['exit_code'] if notice else None,
        })
    unmatched = []
    for (session, job_id), reads in reads_by_key.items():
        if (session, job_id) in matched:
            continue
        for row in reads:
            unmatched.append({'session': session, 'seq': row['seq'], 'job_id': job_id,
                              'read_seconds': round(row['seconds'], 3),
                              'wait': row['args'].get('wait') is True, 'status': row.get('job_status')})
    return jobs, unmatched


def summarize_jobs(jobs, waits, unmatched):
    """Aggregate background lifetime and every foreground wait."""
    finished = [job for job in jobs if job['execution_seconds'] is not None]
    delayed = [job for job in jobs if job['notification_delay_seconds'] is not None]
    collected = [job for job in jobs if job['completion_to_consumption_seconds'] is not None]
    return {
        'jobs': len(jobs), 'completed': len(finished),
        'execution_seconds': round(sum(job['execution_seconds'] for job in finished), 3),
        'start_blocked_seconds': round(sum(job['start_blocked_seconds'] for job in jobs), 3),
        'read_calls': len(waits),
        'read_blocked_seconds': round(sum(wait['read_seconds'] for wait in waits), 3),
        'wait_calls': sum(1 for wait in waits if wait['wait']),
        'wait_blocked_seconds': round(sum(wait['read_seconds'] for wait in waits if wait['wait']), 3),
        'unmatched_read_calls': len(unmatched),
        'unmatched_read_seconds': round(sum(wait['read_seconds'] for wait in unmatched), 3),
        'notification_delay_seconds': round(sum(job['notification_delay_seconds'] for job in delayed), 3),
        'completion_to_consumption_seconds': round(sum(job['completion_to_consumption_seconds'] for job in collected), 3),
        'max_execution_seconds': max((job['execution_seconds'] for job in finished), default=0),
        'max_completion_to_consumption_seconds': max((job['completion_to_consumption_seconds'] for job in collected), default=0),
    }


def comparable_build_groups(rows):
    """Summarize `zig build` calls inside one (target, filter, optimize, cache) key.

    Durations from different keys measure different work and must not be read as
    a before/after speedup.
    """
    groups = defaultdict(list)
    for row in rows:
        if row['name'] != 'bash' or not BUILD.search(row['command']):
            continue
        key = build_dimensions(row['command'])
        if key is not None:
            groups[key].append(row)
    result = [{'target': target, 'test_filter': test_filter, 'optimize': optimize, 'cache': cache, **summarize(items)}
              for (target, test_filter, optimize, cache), items in groups.items()]
    result.sort(key=lambda row: row['call_seconds'], reverse=True)
    return result


def make_report(sessions, project, include_commands=False, exclusions=()):
    selected = {s['header'].get('id') for s in sessions if s['header'].get('cwd') == str(project)}
    while True:
        children = {s['header'].get('id') for s in sessions if s['header'].get('parentSession') in selected}
        added = children - selected
        if not added:
            break
        selected.update(added)
    sessions = [s for s in sessions if s['header'].get('id') in selected]
    coordinators = {s['header'].get('parentSession') for s in sessions}
    rows = [row for session in sessions for row in session['calls']]
    for row in rows:
        row['category'] = classify(row, coordinators, set(exclusions))
    included = [r for r in rows if r['category'] not in EXCLUDED]
    excluded = [r for r in rows if r['category'] in EXCLUDED]
    timeout_rows = [r for r in included if r['persistent_timeout']]
    notices = [notice for session in sessions for notice in session['notices']]
    jobs, unmatched_reads = background_jobs(rows, notices)
    waits = job_waits(rows)
    # `timeout_ms` is only meaningful with `wait: true`; without it the read
    # returns immediately, so the model learns nothing and spends a turn.
    timeout_without_wait = [r for r in rows if r['name'] == 'job_output'
                            and r['args'].get('timeout_ms') is not None
                            and r['args'].get('wait') is not True]
    manifest, agent_seconds, model_seconds = [], 0, 0
    for session in sessions:
        own = [r for r in session['calls'] if r['category'] not in EXCLUDED]
        blocked = seconds((r['start_ms'], r['end_ms']) for r in own)
        pretool = seconds(session['model_intervals'])
        agent_seconds += blocked
        model_seconds += pretool
        manifest.append({'id': session['header'].get('id'), 'cwd': session['header'].get('cwd'),
                         'parent': session['header'].get('parentSession'),
                         'depth': session['header'].get('delegationDepth', 0),
                         'created_at': utc(session['header'].get('createdAt')),
                         'last_event_at': utc(session['last_event_ms']), 'source': session['source'],
                         'format_version': session['header'].get('version'),
                         'snapshot': session.get('snapshot'), 'issues': session['issues'],
                         'unfinished_calls': session['unfinished_calls'], 'orphan_results': session['orphan_results'],
                         'tool_blocked_seconds': round(blocked, 3), 'pre_tool_phase_seconds': round(pretool, 3),
                         'llm_retries': session['llm_retries'], 'seed_end_seq': session['seed_end_seq'],
                         'inherited_calls_skipped': session['inherited_calls_skipped']})
    by_day = defaultdict(list)
    for row in included:
        by_day[utc(row['start_ms'])[:10]].append(row)
    repeats = defaultdict(list)
    for row in included:
        if row['command_sha256']:
            repeats[(row['session'], row['command_sha256'])].append(row)
    repeated = []
    for (session_id, digest), matches in repeats.items():
        if len(matches) > 1:
            repeated.append({'session': session_id, 'command_sha256': digest,
                             'seqs': [r['seq'] for r in matches], **summarize(matches),
                             **({'command': matches[0]['command']} if include_commands else {})})
    repeated.sort(key=lambda row: row['call_seconds'], reverse=True)
    unsupported = [r for r in rows if r['name'] == 'bash' and r['schema'].get('bash_parameters') == ['command']
                   and any(k in r['args'] for k in ('timeoutMs', 'run_in_background', 'workdir'))]
    short = [r for r in included if r['seconds'] < 1]
    long = [r for r in included if r['seconds'] >= 30]
    flags = {key: summarize([r for r in included if r[key]]) for key in
             ('persistent_timeout', 'managed_timeout', 'shell_reset', 'truncated', 'explicit_nonzero_exit', 'guardian_failed')}
    result = {
        'version': 'deepseek-tool-audit-v3', 'generated_at': datetime.now(timezone.utc).isoformat(),
        'project': str(project), 'sessions': len(sessions), 'completed_calls': len(rows),
        'period_start': min((utc(r['start_ms']) for r in rows), default=None),
        'period_end': max((utc(r['end_ms']) for r in rows), default=None),
        'included': summarize(included), 'excluded': summarize(excluded),
        'tool_blocked_agent_seconds': round(agent_seconds, 3),
        'elapsed_union_tool_seconds': round(seconds((r['start_ms'], r['end_ms']) for r in included), 3),
        'pre_tool_phase_agent_seconds': round(model_seconds, 3),
        'under_one_second': summarize(short), 'at_least_30_seconds': summarize(long),
        'categories': grouped(rows, 'category'), 'tools': grouped(included, 'name'),
        'days': {day: summarize(items) for day, items in sorted(by_day.items())}, 'flags': flags,
        'unsupported_bash_arguments': len(unsupported),
        'bash_calls_with_background_schema': sum(r['name'] == 'bash' and r['schema'].get('background_supported', False) for r in rows),
        'explicit_background_starts': sum(r['name'] == 'bash' and r['args'].get('run_in_background') is True
                                         and r['schema'].get('background_supported', False) for r in rows),
        'top_calls': [public_call(r, include_commands) for r in sorted(included, key=lambda r: r['seconds'], reverse=True)[:30]],
        'timeout_calls': [public_call(r, include_commands) for r in timeout_rows],
        'repeated_commands': repeated[:30], 'manifest': manifest,
        'background_jobs': jobs, 'background_job_summary': summarize_jobs(jobs, waits, unmatched_reads),
        'job_waits': waits, 'unmatched_job_waits': unmatched_reads,
        'job_output_timeout_without_wait': len(timeout_without_wait),
        'job_output_misuse_calls': [public_call(r, include_commands) for r in timeout_without_wait[:30]],
        'comparable_build_groups': comparable_build_groups(included),
        'limitations': [
            'Call/result wall time includes queueing, policy, process work and persistence; CPU time is unavailable.',
            'Summed call seconds are agent-time, not project elapsed time or guaranteed savings. Per-agent and global interval unions are separate.',
            'All root/parent-agent shell calls containing sleep are conservatively excluded, including some build polls. Agent control waits and human input are also excluded.',
            'Worker sleep/poll time overlaps real background work; background_jobs reports execution, start/collection blocking and completion-to-consumption delay separately.',
            'Command categories are regex hints over whole commands and may include quoted code or mixed actions. Repeated commands do not establish redundant work.',
            'Build/test durations are comparable only within one comparable_build_groups key (target, -Dtest-filter, optimize mode, cache condition). Different filters or modes measure different work and are not a speedup ratio.',
            'Pre-tool phase is step/start to assistant/message, including request assembly, provider delay, retries and generation; it is not pure inference time.',
            'Only completed calls are timed. Live tails, unfinished calls, unmatched results and decode issues are reported per session.',
            'Logs are per-file snapshots, not one atomic snapshot across sessions. Source hashes identify the bytes read; no log content is modified.',
            'Failure/truncation markers are textual signals; shell pipelines may mask exit codes and old logs often omit explicit status.',
        ],
    }
    return result


def markdown(report):
    lines = ['# DeepSeek tool latency audit', '', f'Project: `{report["project"]}`', '',
             f'Observed {report["sessions"]} sessions and {report["completed_calls"]:,} completed calls, '
             f'{report["period_start"]} to {report["period_end"]}.', '',
             f'Included tool time: **{report["tool_blocked_agent_seconds"] / 3600:.2f} agent-hours** '
             '(overlaps removed within each agent). '
             f'Excluded coordination/human waits: **{report["excluded"]["call_seconds"] / 3600:.2f} call-hours**.', '',
             f'Elapsed union with at least one included tool outstanding: {report["elapsed_union_tool_seconds"] / 3600:.2f} hours. '
             f'Pre-tool/model phase: {report["pre_tool_phase_agent_seconds"] / 3600:.2f} agent-hours.', '',
             'Categories are command-text hints. Durations are observed blocking, not promised savings.', '',
             '| Category | Calls | Call-hours | Median ms | p95 ms |',
             '|---|---:|---:|---:|---:|']
    for name, row in report['categories'].items():
        label = f'{name} (excluded)' if name in EXCLUDED else name
        lines.append(f'| {label} | {row["calls"]:,} | {row["call_seconds"] / 3600:.3f} | {row["median_ms"]:.1f} | {row["p95_ms"]:.1f} |')
    lines += ['', '## Signals', '',
              f'- Included persistent-shell timeouts: {report["flags"]["persistent_timeout"]["calls"]}; '
              f'{report["flags"]["persistent_timeout"]["call_seconds"] / 60:.1f} minutes spent in those calls.',
              f'- Included managed-shell timeouts: {report["flags"]["managed_timeout"]["calls"]}; '
              f'{report["flags"]["managed_timeout"]["call_seconds"] / 60:.1f} minutes spent in those calls.',
              f'- Calls under one second: {report["under_one_second"]["calls"]:,}; '
              f'{report["under_one_second"]["call_seconds"] / 60:.1f} total minutes.',
              f'- Calls at least 30 seconds: {report["at_least_30_seconds"]["calls"]:,}; '
              f'{report["at_least_30_seconds"]["call_seconds"] / 3600:.2f} call-hours.',
              f'- Explicit managed background starts: {report["explicit_background_starts"]}; '
              f'bash calls with background support advertised: {report["bash_calls_with_background_schema"]:,}.',
              f'- Bash calls supplying timeout/background/workdir arguments absent from their command-only schema: {report["unsupported_bash_arguments"]}.',
              f'- Unfinished calls: {sum(s["unfinished_calls"] for s in report["manifest"])}; '
              f'unmatched results: {sum(s["orphan_results"] for s in report["manifest"])}; '
              f'sessions with parse/decode issues: {sum(bool(s["issues"]) for s in report["manifest"])}.',
               f'- job_output calls passing timeout_ms without wait: true (they return immediately): '
               f'{report["job_output_timeout_without_wait"]}.',
               f'- Managed background jobs: {report["background_job_summary"]["jobs"]}; '
               f'execution {report["background_job_summary"]["execution_seconds"] / 60:.1f} minutes, '
               f'notification delay {report["background_job_summary"]["notification_delay_seconds"]:.1f} s, '
               f'every read {report["background_job_summary"]["read_calls"]} calls / '
               f'{report["background_job_summary"]["read_blocked_seconds"]:.1f} s '
               f'(blocking waits {report["background_job_summary"]["wait_calls"]} / '
               f'{report["background_job_summary"]["wait_blocked_seconds"]:.1f} s), '
               f'unmatched reads {report["background_job_summary"]["unmatched_read_calls"]}, '
               f'completion-to-consumption {report["background_job_summary"]["completion_to_consumption_seconds"] / 60:.1f} minutes.',
               '', '## Managed background jobs', '',
               'Execution ends at the settlement notice; delivery delay is separate; every read is counted.', '',
               '| Job | Session | Execution s | Notify delay s | Start block s | Reads | Read block s | Wait calls | Complete->consume s | Outcome |',
               '|---|---|---:|---:|---:|---:|---:|---:|---:|---|']
    for job in sorted(report['background_jobs'], key=lambda item: item['execution_seconds'] or 0, reverse=True)[:20]:
        lines.append(f'| `{job["job_id"]}` | `{job["session"]}` | '
                     f'{job["execution_seconds"] if job["execution_seconds"] is not None else "-"} | '
                     f'{job["notification_delay_seconds"] if job["notification_delay_seconds"] is not None else "-"} | '
                     f'{job["start_blocked_seconds"]:.3f} | {job["read_count"]} | '
                     f'{job["read_blocked_seconds"]:.3f} | {job["wait_calls"]} | '
                     f'{job["completion_to_consumption_seconds"] if job["completion_to_consumption_seconds"] is not None else "-"} | '
                     f'{job["outcome"] or "running/unreported"} |')
    lines += ['', '## Comparable build groups', '',
              'Durations are only comparable within one key. Different filters, optimize modes or cache conditions measure different work.', '',
              '| Target | Filter | Optimize | Cache | Calls | Call-hours | Median ms |', '|---|---|---|---|---:|---:|---:|']
    for group in report['comparable_build_groups'][:20]:
        lines.append(f'| {group["target"]} | {group["test_filter"] or "-"} | {group["optimize"]} | {group["cache"]} | '
                     f'{group["calls"]:,} | {group["call_seconds"] / 3600:.3f} | {group["median_ms"]:.1f} |')
    lines += ['', '## Slowest included calls', '',
              '| Seconds | Category | Session | Call seq |', '|---:|---|---|---:|']
    for row in report['top_calls'][:15]:
        lines.append(f'| {row["seconds"]:.3f} | {row["category"]} | `{row["session"]}` | {row["seq"]} |')
    lines += ['', '## Interpretation limits', ''] + ['- ' + item for item in report['limitations']]
    return '\n'.join(lines) + '\n'


def session_files(root):
    """Find legacy and versioned event logs; duplicate session IDs remain errors."""
    names = re.compile(r'^session(?:\.v\d+)?\.jsonl(?:\.zstd)?$')
    return sorted(path for path in root.rglob('session*')
                  if path.is_file() and names.fullmatch(path.name))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--logs', type=Path, default=Path.home() / '.dsh/sessions')
    parser.add_argument('--project', type=Path, default=Path.cwd())
    parser.add_argument('--json-output', type=Path)
    parser.add_argument('--markdown-output', type=Path)
    parser.add_argument('--include-command-text', action='store_true', help='Opt in to copying shell command text into JSON; may contain private data')
    parser.add_argument('--exclude-call', action='append', default=[], metavar='SESSION:SEQ', help='Exclude an additional confirmed coordination wait')
    args = parser.parse_args()
    files = session_files(args.logs)
    if not files:
        parser.error(f'no session.jsonl[.zstd] logs under {args.logs}')
    if any(p.suffix == '.zstd' for p in files) and shutil.which('zstd') is None:
        parser.error('zstd executable is required for compressed logs')
    sessions = [read_session(path) for path in files]
    ids = [s['header'].get('id') for s in sessions]
    duplicates = [key for key, count in Counter(ids).items() if count > 1]
    if duplicates or None in ids:
        parser.error('missing or duplicate session ids; choose one current log generation per session')
    report = make_report(sessions, args.project.resolve(), args.include_command_text, args.exclude_call)
    if not report['sessions']:
        parser.error(f'no sessions have cwd {args.project.resolve()}')
    for path, content in ((args.json_output, json.dumps(report, indent=2) + '\n'),
                          (args.markdown_output, markdown(report))):
        if path:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    print(markdown(report))
    if any(s['issues'] for s in report['manifest']):
        print('Warning: report contains partial/invalid log data; inspect manifest issues.', file=sys.stderr)


if __name__ == '__main__':
    main()
