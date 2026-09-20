#!/usr/bin/env python3
"""Compiler-invocation events for the E1 pilot harness.

One event is one compiler process, written by ``harness/shim.py`` after the
process finished. The schema is ``compiler-invocation-v1``, the vocabulary the
M1 feedback study fixed (``experiments/diagnostic-feedback/events.py`` in the
main checkout); E1 adds the fields it needs and keeps M1's metric names
separate, so a wrapper cannot manufacture an apparent reduction:

    failed compiler invocations      completed processes rejected for source or
                                     invocation errors (infrastructure separate)
    failed checks on changed source  those whose source hash differs from the
                                     attempt's initial snapshot
    failed candidate versions        distinct changed source hashes with a
                                     failure; repeated checks on unchanged code
                                     count once
    repeated diagnostic              the same semantic diagnostic on distinct
                                     failed invocations

E1's additions are ``phase`` (which part of the work a process belongs to),
``stdout_bytes``/``stderr_bytes`` (tool-response bytes), ``wall_seconds`` and
``cache_dir`` (the cache policy the protocol freezes). A missing event is a
missing measurement, never a zero-invocation one.
"""
from __future__ import annotations

import hashlib
import json
import re
import time
from pathlib import Path

SCHEMA = 'compiler-invocation-v1'
REQUIRED = ('schema', 'attempt_id', 'invocation_id', 'command', 'argv', 'cwd',
            'source_sha256', 'compiler_sha256', 'started_monotonic_ns',
            'finished_monotonic_ns', 'exit_code', 'outcome', 'diagnostic_codes',
            'source_stable', 'phase', 'stdout_bytes', 'stderr_bytes', 'wall_seconds')
OUTCOMES = ('success', 'source_error', 'invocation_misuse', 'runtime_failure',
            'infrastructure_failure')
INVOCATION_CODES = ('E_MAIN', 'E_MODULE_NAME')
HEADER = re.compile(r'^(?P<path>.+?):(?P<line>\d+):(?P<column>\d+): '
                    r'(?P<severity>error|warning)\[(?P<code>[A-Z_]+)\]: (?P<message>.*)$',
                    re.MULTILINE)
HOST_FAILURE = re.compile(r'host failure|NativeToolFailed|ReadOnlyFileSystem|'
                          r'sub-compilation of .* failed|ToolNotFound')
EXCLUDED = ('.mylang-cache', '.cache-acceptance', '.cache-e1')

# Which part of the work a command belongs to. The plan asks for the phases
# separately; a process is counted once, in the phase its command name implies.
PHASES = {
    'context': 'reading context',
    'reference': 'reading context',
    'list-interfaces': 'reading context',
    'list-modules': 'reading context',
    'list-declarations': 'reading context',
    'index-project': 'reading context',
    'tests-for': 'reading context',
    'callers': 'reading context',
    'callees': 'reading context',
    'impact': 'reading context',
    'api-diff': 'reading context',
    'check': 'checking',
    'check-project': 'checking',
    'check-policy': 'checking',
    'check-session': 'checking',
    'run': 'compiling and running',
    'run-project': 'compiling and running',
    'build': 'compiling and running',
    'test': 'executing tests',
    'fmt': 'formatting',
    'fmt-module': 'formatting',
    'fmt-project': 'formatting',
}


def phase_for(argv: list[str]) -> str:
    """The phase a command line belongs to, from its subcommand."""
    for argument in argv[1:]:
        if argument.startswith('-'):
            continue
        return PHASES.get(argument, 'other')
    return 'other'


def command_for(argv: list[str]) -> str:
    """The tool and subcommand of an invocation, e.g. ``mylang run``."""
    name = Path(argv[0]).name if argv else 'unknown'
    for argument in argv[1:]:
        if not argument.startswith('-'):
            return f'{name} {argument}'
    return name


def parse_diagnostics(stderr: str) -> list[dict]:
    """The text diagnostics of one process, in order."""
    return [match.groupdict() for match in HEADER.finditer(stderr)]


def diagnostic_identity(diagnostic: dict) -> str:
    """A stable identity for a diagnostic: the code alone is too coarse."""
    parts = (diagnostic.get('code', ''), diagnostic.get('message', ''))
    return hashlib.sha256('\x1f'.join(parts).encode()).hexdigest()[:16]


def classify(exit_code: int, stderr: str, diagnostics: list[dict]) -> str:
    """What happened, from the process status first and the text second.

    A command that exits 0 succeeded even when it echoed a project diagnostic:
    ``mylang context`` answers its JSON while repeating the ``E_TYPED_HOLE`` the
    project carries, and counting that as a failed invocation would overstate the
    failure count. The diagnostics are still recorded under ``diagnostic_codes``.
    """
    if HOST_FAILURE.search(stderr):
        return 'infrastructure_failure'
    if exit_code == 0:
        return 'success'
    errors = [diagnostic for diagnostic in diagnostics if diagnostic.get('severity') == 'error']
    if errors:
        codes = {diagnostic['code'] for diagnostic in errors}
        return 'invocation_misuse' if codes & set(INVOCATION_CODES) else 'source_error'
    return 'runtime_failure'


def inventory(root: Path) -> tuple[str, dict[str, str]]:
    """Hash every guest source file by relative path, additions included.

    Caches and coordinator-owned reports stay outside the inventory: a compiler
    cache changing between two checks must not look like an edit by the agent.
    """
    entries: dict[str, str] = {}
    for path in sorted(root.rglob('*.my')):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        if any(part in relative for part in EXCLUDED):
            continue
        entries[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    digest = hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()
    return digest, entries


def build_event(argv: list[str], cwd: Path, log: Path, compiler_sha256: str,
                attempt_id: str, invocation_id: str, exit_code: int,
                started_ns: int, finished_ns: int, stdout_bytes: int, stderr_bytes: int,
                source_sha256: str, source_stable: bool, stderr: str,
                diagnostics: list[dict]) -> dict:
    """One ``compiler-invocation-v1`` event, complete enough to validate."""
    return {
        'schema': SCHEMA,
        'attempt_id': attempt_id,
        'invocation_id': invocation_id,
        'command': command_for(argv),
        'argv': argv,
        'cwd': str(cwd),
        'source_sha256': source_sha256,
        'compiler_sha256': compiler_sha256,
        'started_monotonic_ns': started_ns,
        'finished_monotonic_ns': finished_ns,
        'exit_code': exit_code,
        'outcome': classify(exit_code, stderr, diagnostics),
        'diagnostic_codes': [diagnostic['code'] for diagnostic in diagnostics],
        'error_diagnostic_codes': [diagnostic['code'] for diagnostic in diagnostics
                                   if diagnostic.get('severity') == 'error'],
        'diagnostic_identities': [diagnostic_identity(diagnostic) for diagnostic in diagnostics],
        'source_stable': source_stable,
        'phase': phase_for(argv),
        'stdout_bytes': stdout_bytes,
        'stderr_bytes': stderr_bytes,
        'wall_seconds': round((finished_ns - started_ns) / 1e9, 6),
        'cache_dir': cache_dir_of(argv),
        'log': str(log),
    }


def cache_dir_of(argv: list[str]) -> str:
    """The ``--cache-dir=`` value of an invocation, or an empty string."""
    for argument in argv:
        if argument.startswith('--cache-dir='):
            return argument.split('=', 1)[1]
    return ''


def append_event(log: Path, event: dict) -> None:
    """Append one validated event to the JSON Lines log."""
    missing = [field for field in REQUIRED if field not in event]
    if missing:
        raise ValueError(f'event is missing {", ".join(missing)}')
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('a') as handle:
        handle.write(json.dumps(event) + '\n')


def read_events(path: Path) -> tuple[list[dict], dict]:
    """Validated events, deduplicated by invocation id, plus coverage flags."""
    events: list[dict] = []
    seen: set[str] = set()
    problems: list[str] = []
    duplicates = truncated = 0
    if not path.is_file():
        return [], {'missing': True, 'duplicates': 0, 'truncated': 0, 'invalid': 0}
    for index, line in enumerate(path.read_text(errors='replace').splitlines()):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            truncated += 1
            problems.append(f'line {index + 1}: unparseable')
            continue
        missing = [field for field in REQUIRED if field not in event]
        if missing:
            problems.append(f'line {index + 1}: missing {", ".join(missing)}')
            continue
        if event['schema'] != SCHEMA:
            problems.append(f"line {index + 1}: schema {event['schema']!r}")
            continue
        if event['invocation_id'] in seen:
            duplicates += 1
            continue
        seen.add(event['invocation_id'])
        events.append(event)
    return events, {'missing': False, 'duplicates': duplicates, 'truncated': truncated,
                    'invalid': len(problems), 'problems': problems[:5]}


def aggregate(events: list[dict], initial_source_sha256: str) -> dict:
    """The observed counts, each named separately and never merged into one."""
    by_phase: dict[str, dict] = {}
    failed_invocations = infrastructure = failed_on_changed = repeated = 0
    failed_versions: set[str] = set()
    checked_versions: set[str] = set()
    stdout_bytes = stderr_bytes = 0
    wall_seconds = 0.0
    diagnostic_codes: dict[str, int] = {}
    identities: dict[str, int] = {}
    for event in sorted(events, key=lambda item: item.get('started_monotonic_ns') or 0):
        phase = event.get('phase') or 'other'
        bucket = by_phase.setdefault(phase, {'invocations': 0, 'failed': 0, 'wall_seconds': 0.0,
                                             'stdout_bytes': 0, 'stderr_bytes': 0})
        bucket['invocations'] += 1
        bucket['wall_seconds'] = round(bucket['wall_seconds'] + event.get('wall_seconds', 0.0), 6)
        bucket['stdout_bytes'] += event.get('stdout_bytes', 0)
        bucket['stderr_bytes'] += event.get('stderr_bytes', 0)
        stdout_bytes += event.get('stdout_bytes', 0)
        stderr_bytes += event.get('stderr_bytes', 0)
        wall_seconds += event.get('wall_seconds', 0.0)
        for code in event.get('diagnostic_codes') or []:
            diagnostic_codes[code] = diagnostic_codes.get(code, 0) + 1
        outcome = event.get('outcome')
        if outcome == 'infrastructure_failure':
            infrastructure += 1
            continue
        if outcome == 'success':
            checked_versions.add(event.get('source_sha256', ''))
            continue
        failed_invocations += 1
        bucket['failed'] += 1
        changed = event.get('source_sha256') != initial_source_sha256
        if changed and not event.get('source_stable', True):
            continue  # the source moved under the compiler: invalid measurement
        if changed:
            failed_on_changed += 1
            failed_versions.add(event['source_sha256'])
        for identity_value in event.get('diagnostic_identities') or []:
            identities[identity_value] = identities.get(identity_value, 0) + 1
    repeated = sum(count - 1 for count in identities.values() if count > 1)
    return {
        'invocations': len(events),
        'failed_compiler_invocations': failed_invocations,
        'infrastructure_failures': infrastructure,
        'failed_checks_on_changed_source': failed_on_changed,
        'failed_candidate_versions': len(failed_versions),
        'checked_candidate_versions': len(checked_versions),
        'repeated_diagnostics': repeated,
        'distinct_diagnostics': len(identities),
        'diagnostic_codes': diagnostic_codes,
        'stdout_bytes': stdout_bytes,
        'stderr_bytes': stderr_bytes,
        'invocation_wall_seconds': round(wall_seconds, 6),
        'phases': by_phase,
    }


def now_ns() -> int:
    """A monotonic nanosecond reading, the clock M1's events use."""
    return time.monotonic_ns()
