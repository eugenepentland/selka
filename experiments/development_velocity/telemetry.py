"""Observed development timeline. Unmeasured time is never called model thinking."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import time

from experiments.application_comparison import session, tool_metrics
from experiments.application_comparison.execution import verify_adapter
from experiments.application_comparison.isolation import Limits, run
from experiments.application_comparison.participant_gateway import Gateway
from experiments.application_comparison.storage import (
    digest, inventory, locked, read_json, snapshot, source_files, write_json,
)

PURPOSES = frozenset(('inspect', 'edit', 'compile', 'test', 'debug', 'benchmark', 'other'))
INTERFACES = ('files', 'store')
# Only a store session interface reports these; a files arm leaves store_metrics null.
STORE_METRICS = ('bytes_returned', 'verb_counts', 'context_omitted_total',
                 'if_match_conflicts', 'batch_rejections')
# The declaration-store session verbs; there is no command verb in that arm.
STORE_VERBS = ('open', 'context', 'search', 'asset', 'batch', 'probe', 'check', 'output', 'finish')
# One store per phase: the timed attempt store, and the onboarding store beside it.
STORE_PHASES = {
    'preparing': {'database': 'practice-store.sqlite', 'session': 'practice-store',
                  'asset_root': '', 'protected': ()},
    'working': {'database': 'store.sqlite', 'session': 'store',
                'asset_root': '.trial-public', 'protected': ('main', 'io')},
}
# Omitted-row counts a context response reports; source_bytes is bytes, not rows.
CONTEXT_OMITTED = ('callees', 'callers', 'types', 'tests', 'entries')
# The single-context handoff. A participant that has finished practice calls
# `await-handoff` and blocks in its own context until the coordinator's `begin`
# starts the clock, so practice and the timed task share one context. The poll is
# recorded like any other operation; a record taken while the phase is still
# `preparing` is outside the application clock, exactly as every practice record is.
HANDOFF_POLL_SECONDS = 0.5
HANDOFF_WAIT_SECONDS = 540
HANDOFF_WAITING = 'still waiting; call await-handoff again'
DEFAULT_HANDOFF = ('The timed application is now active. Follow the application-phase '
                   'instructions of your onboarding prompt.')


def handoff_text(root):
    """The coordinator's handoff message, stored by `begin` before the clock started."""
    path = Path(root) / 'handoff.json'
    if not path.exists():
        return DEFAULT_HANDOFF
    record = read_json(path)
    if record.get('version') != 'attempt-handoff-v1' or digest(record.get('text')) != record.get('sha256'):
        raise ValueError('handoff message identity mismatch')
    return record['text']


def load_frozen(path):
    """Import one frozen coordinator script by path, so a cohort keeps the tool it froze."""
    path = Path(path).resolve(strict=True)
    name = 'frozen_' + path.stem + '_' + hashlib.sha256(str(path).encode()).hexdigest()[:16]
    module = sys.modules.get(name)
    if module is None:
        specification = importlib.util.spec_from_file_location(name, path)
        module = importlib.util.module_from_spec(specification)
        sys.modules[name] = module
        try:
            specification.loader.exec_module(module)
        except BaseException:
            del sys.modules[name]
            raise
    return module


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

    handoff_poll_seconds = HANDOFF_POLL_SECONDS
    handoff_wait_seconds = HANDOFF_WAIT_SECONDS

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
            work = self.work_path(phase)
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
                    before_files, before = self.source_receipt(work, phase)
                except (OSError, ValueError) as error:
                    before_error = str(error)
                capture_finished = session.clock()
                clean_arguments = {k: v for k, v in arguments.items() if k != 'purpose'} if isinstance(arguments, dict) else arguments
                dispatch_started = session.clock()
                try:
                    response = self.perform(name, clean_arguments, directory, index, phase)
                finally:
                    dispatch_finished = session.clock()
            except BaseException as error:
                failure = {'type': type(error).__name__, 'message': str(error)}
                raise
            finally:
                try:
                    files, after = self.source_receipt(work, phase)
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
                self.release()
            return self.finalize(response, index, name)

    # Interface hooks: a files arm reads the mounted work tree and runs argv; a store
    # arm reads its branch's rendered snapshot and runs verbs. Retention is identical.
    def work_path(self, phase):
        return self.root / ('practice' if phase == 'preparing' else 'work')

    def await_handoff(self, arguments, *, wait_seconds=None, poll_seconds=None):
        """Poll this attempt's phase until the coordinator begins, or the wait runs out.

        The clock starts at `begin`, not here, so a call made while the attempt is
        still `preparing` costs the participant nothing: `summarize` keeps only
        `working` records. Only the poll's own return latency, at most one interval,
        falls inside the clock.
        """
        if arguments != {}:
            raise ValueError('await-handoff takes no arguments')
        poll = self.handoff_poll_seconds if poll_seconds is None else poll_seconds
        limit = self.handoff_wait_seconds if wait_seconds is None else wait_seconds
        if poll <= 0 or limit < 0:
            raise ValueError('await-handoff needs a positive poll interval and a nonnegative wait')
        deadline = time.monotonic() + limit
        while True:
            if session.load(self.root)['phase'] == 'working':
                return {'phase': 'working', 'message': handoff_text(self.root)}
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return {'phase': 'ready', 'message': HANDOFF_WAITING}
            time.sleep(min(poll, remaining))

    def source_receipt(self, work, phase):
        return source_receipt(work)

    def perform(self, name, arguments, directory, index, phase):
        if name == 'await-handoff':
            return self.await_handoff(arguments)
        return (self.output(directory, index, arguments) if name == 'output'
                else Gateway.dispatch(self, name, arguments))

    def finalize(self, response, index, name):
        if name == 'await-handoff':  # The handoff contract is exactly phase and message.
            return response
        return dict(response, operation_record=index) if isinstance(response, dict) else response

    def release(self):
        """Drop per-dispatch resources; the files arm holds none between operations."""

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


class StoreGateway(ObservedGateway):
    """The declaration-store session as a participant gateway; see declaration-store.md 3.5.

    Verbs replace `command`. Every request and response is retained twice: as a
    `development-operation-v1` record beside the files arm's records, and whole in
    the session's own record file. The participant never receives a path, and no
    verb reads the attempt directory. `check` renders the branch, publishes it as the
    submission source, and runs the frozen adapter exactly as the files arm does.
    """

    def __init__(self, root, tools, limits=None, *, adapter=None, public_case=None,
                 retain_command_cache=False):
        super().__init__(root, tools, limits, adapter=adapter, public_case=public_case,
                         retain_command_cache=retain_command_cache)
        for name in ('store_server', 'compiler'):
            if name not in self.tools:
                raise ValueError('a declaration-store arm mounts the frozen ' + name)
        if self.adapter is None:
            raise ValueError('a declaration-store arm requires the frozen public adapter')
        self.server = load_frozen(self.tools['store_server']['path'])
        self.preparation = None  # The coordinator's practice gateway, set for the practice phase.
        self.sessions = {}

    # Sessions ---------------------------------------------------------------
    def session(self, phase):
        """One store session per phase, opened lazily and closed at the end of the dispatch."""
        if phase not in STORE_PHASES:
            raise ValueError('the declaration store has no source in this phase')
        if phase not in self.sessions:
            settings = STORE_PHASES[phase]
            database = self.root / settings['database']
            if not database.exists():
                raise ValueError('this attempt has no declaration store; prepare the arm first')
            opened = self.server.StoreSession(
                database, 'work', self.tools['compiler']['path'], self.probe_adapter(),
                self.root / settings['session'], asset_root=settings['asset_root'],
                protected_modules=settings['protected'],
                check=lambda record, phase=phase: self.public_check(record, phase),
                limits=dict(self.limits.__dict__))
            cache = self.root / settings['session'] / 'renders.json'
            if cache.exists():
                opened.cached_snapshot(read_json(cache)['snapshot'])
            self.sessions[phase] = opened
        return self.sessions[phase]

    def release(self):
        for opened in self.sessions.values():
            try:
                opened.close()
            except (OSError, ValueError):
                pass
        self.sessions = {}

    def remember(self, phase):
        """Persist the branch's rendered snapshot so the next dispatch need not re-render."""
        record = self.sessions[phase].cached_snapshot()
        if record is not None:
            write_json(self.root / STORE_PHASES[phase]['session'] / 'renders.json',
                       {'snapshot': record})
        return record

    def probe_adapter(self):
        """`probe` runs the frozen adapter on a copy of the private snapshot, under trial limits."""
        adapter = self.adapter

        def call(work, request_bytes):
            verify_adapter(adapter)
            limits = Limits(**adapter['limits'])
            tools = {name: item['path'] for name, item in adapter['tools'].items()}
            started = time.monotonic()
            with tempfile.TemporaryDirectory(prefix='store-probe-') as temporary:
                copy = Path(temporary) / 'work'
                snapshot(work, copy)
                result = None
                for command in adapter['commands']:
                    result = run(copy, command['argv'], tools=tools, limits=limits,
                                 input_bytes=request_bytes if command['phase'] == 'run' else b'')
                    if result['outcome'] != 'exited' or result['returncode'] != 0:
                        break
            return {'outcome': result['outcome'], 'returncode': result['returncode'],
                    'stdout': result['stdout'], 'stderr': result['stderr'],
                    'stdout_bytes': len(result['stdout']), 'stderr_bytes': len(result['stderr']),
                    'elapsed_seconds': time.monotonic() - started}
        return call

    # Snapshots --------------------------------------------------------------
    def materialize(self, record, target):
        """Publish the rendered branch as the coordinator's checkable tree; never a participant read."""
        target = Path(target)
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(record['path'], target)
        return target

    def source_receipt(self, work, phase):
        """Source identity is the branch's rendered snapshot, not the coordinator's staging tree."""
        opened = self.session(phase)
        record = opened.cached_snapshot() or opened.snapshot()
        self.remember(phase)
        directory = Path(record['path'])
        files = {name: (directory / name).read_bytes() for name in sorted(record['inventory'])}
        return files, inventory(files)

    # Verbs ------------------------------------------------------------------
    def public_check(self, record, phase):
        """The existing public check, on the rendered branch; the same receipts as the files arm."""
        self.materialize(record, self.work_path(phase))
        if phase == 'working':
            return Gateway.check(self)
        if self.preparation is None:
            raise ValueError('practice checking is not configured for this session')
        return self.preparation.dispatch('check', {})

    def finish(self, opened, arguments, phase):
        """A final snapshot, then the existing seal; grading and review are unchanged."""
        if phase != 'working':
            raise ValueError('practice completion is a coordinator step')
        if set(arguments) != {'reason'} or arguments['reason'] not in ('completed', 'abandoned'):
            raise ValueError('invalid participant completion reason')
        manifest = session.load(self.root)
        if manifest['phase'] != 'working':
            raise ValueError('completion requires active task')
        response = opened.dispatch('finish', {'reason': arguments['reason']})
        self.remember(phase)
        if response.get('verb') != 'finish':
            return response
        self.materialize(opened.final_snapshot, self.work_path(phase))
        late = session.elapsed(manifest['task_started'], session.clock()) >= manifest['budgets']['task_seconds']
        sealed = session.seal(self.root, 'budget' if late else arguments['reason'])
        return dict(response, phase=sealed['phase'], reason=sealed['seal_reason'],
                    final_submission=sealed['final_submission'])

    def perform(self, name, arguments, directory, index, phase):
        if name == 'await-handoff':
            return self.await_handoff(arguments)
        if name not in STORE_VERBS:
            raise ValueError('unknown participant operation for a declaration-store arm')
        if not isinstance(arguments, dict):
            raise ValueError('store verb arguments are a JSON object')
        opened = self.session(phase)
        if name == 'finish':
            return self.finish(opened, arguments, phase)
        response = opened.dispatch(name, arguments)
        self.remember(phase)
        return response

    def finalize(self, response, index, name):
        # The session's own `record` number is what `output` pages; no second numbering.
        return response


def store_metrics(root, phase='working'):
    """The five session metrics, read from the retained records without re-running anything."""
    directory = Path(root) / STORE_PHASES[phase]['session'] / 'records'
    totals = {'bytes_returned': 0, 'verb_counts': {}, 'context_omitted_total': 0,
              'if_match_conflicts': 0, 'batch_rejections': 0}
    for path in sorted(directory.glob('[0-9]' * 6 + '.json')) if directory.is_dir() else ():
        record = read_json(path)
        if record.get('version') != 'store-session-v1':
            raise ValueError('unknown store session record: ' + str(path))
        verb, returned = record['verb'], record['returned']
        totals['verb_counts'][verb] = totals['verb_counts'].get(verb, 0) + 1
        totals['bytes_returned'] += len(json.dumps(returned, ensure_ascii=False).encode('utf-8'))
        if verb == 'context':
            for name in CONTEXT_OMITTED:
                value = returned.get('omitted', {}).get(name)
                totals['context_omitted_total'] += value if type(value) is int else 0
            for entry in returned.get('entries', []):
                for name in CONTEXT_OMITTED:
                    value = entry.get('omitted', {}).get(name)
                    totals['context_omitted_total'] += value if type(value) is int else 0
        if verb == 'batch' and record['response'].get('status') == 'rejected':
            totals['batch_rejections'] += 1
            # One conflict is reported twice, once for the operation and once for the
            # whole batch, so a conflict counts by the declaration it names.
            totals['if_match_conflicts'] += len({row.get('detail')
                                                 for row in record['response'].get('rejections', [])
                                                 if row.get('reason') == 'if-match-mismatch'})
    return totals


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


def summarize(root, *, arm=None, interface='files'):
    """`arm` is the registered arm label; it defaults to the session language."""
    root = Path(root)
    if interface not in INTERFACES:
        raise ValueError('unknown session interface')
    if arm is not None and (not isinstance(arm, str) or not arm):
        raise ValueError('arm label must be a nonempty string')
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
    # v2 adds arm, interface and the store_metrics slot; v1 profiles cannot be recomputed.
    return {'version': 'development-profile-v2', 'session_sha256': digest(manifest),
            'task': manifest['block'], 'language': manifest['language'],
            'arm': manifest['language'] if arm is None else arm, 'interface': interface,
            # StoreGateway fills STORE_METRICS here; a files arm has no such counts.
            'store_metrics': store_metrics(root) if interface == 'store' else None,
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
