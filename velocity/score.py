#!/usr/bin/env python3
"""Lane C of the velocity loop: Python fidelity over the idiom suite.

Lane C is defined in ``velocity/goal.json`` (``lanes.C``) and
``docs/velocity-loop.md`` section 2. It runs every probe under
``velocity/suites/idioms`` and measures three things:

* **C1 first-try fidelity** - the fraction of ``# oracle: cpython`` probes that
  selka accepts, runs to completion, and whose exit status (``& 0xFF``) and
  stdout equal CPython's.
* **C2 silent wrong answers** - a gate, reported twice. The strict reading is
  every probe selka accepts and runs to completion whose stdout or status
  disagrees with CPython, declared divergences included. The policy-adjusted
  reading, ``C2_policy``, counts only the disagreements no entry in
  ``velocity/divergences.json`` claims. ``--gate`` fails on ``C2_policy``: a
  declared divergence is a reviewed, documented language decision and does not
  block a package, while an undeclared silent wrong answer always does. A
  declared divergence is never normalised away - the strict number stays in the
  result JSON and the raw pair is preserved in the suite's
  ``divergence-evidence.json``.
* **C3 rejections that carry a fix** - the fraction of rejected probes (compile
  error, or a trap before any output) whose diagnostic carries the structured
  information goal.json defines: a non-null ``fix`` field or a note whose
  ``role`` is ``alternative``. A secondary text reading of the same rejections
  is reported beside it as ``C3_text_any`` against the prose the compiler
  already prints; the two are never merged, because that prose predates the
  field and its movement is not evidence about it.

The probe's own first line names its oracle, so the suite can grow without
editing this file::

    # oracle: cpython             run under CPython; compare status and stdout
    # oracle: rejected-by-design  valid Python the language rejects on purpose;
    #                             counts only toward C3
    # oracle: selka-only         uses Option/Result/record/union; no CPython
    #                             oracle

The CPython oracle runner is shared with ``tests/idiom_probes.py`` (backlog item
V0: lane C extends that driver rather than adding a second one), as is the
"this run did not complete" classifier.

The declared divergences live in ``velocity/divergences.json`` (a
``divergence-policy-v1`` document; override with ``--divergences``). Each entry
claims one or more probes by name or glob, names the documented language rule it
diverges from and the CPython behaviour it diverges to, and carries the
expression/value pairs ``velocity/divergence_evidence.py`` reproduces. A missing
policy file is measured as an empty policy and said so on stderr: that is the
conservative direction, because every disagreement then gates.

Every run re-executes every selected probe; nothing is cached, so a rerun can
never report a stale verdict. A probe that traps, times out or fails to build
is recorded and does not abort the run.

Examples::

    python3 velocity/score.py
    python3 velocity/score.py --binary zig-out/bin/selka-baseline-20260920 \\
        --write velocity/suites/idioms/score-baseline-2026-09-20.json
    python3 velocity/score.py --baseline velocity/suites/idioms/score-baseline-2026-09-20.json
    python3 velocity/score.py --gate --probe 'a6*'
    python3 velocity/score.py --divergences /dev/null --gate   # nothing is declared
"""
from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import fnmatch
import hashlib
import importlib.util
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SUITE = ROOT / 'velocity' / 'suites' / 'idioms'
DEFAULT_BINARY = ROOT / 'zig-out' / 'bin' / 'selka'
DEFAULT_IDENTITY_ENTRY = ROOT / 'examples' / 'corpus' / 'packet' / 'main.selka'
MANIFEST_NAME = 'manifest.json'
PROBE_GLOB = '*.selka'
ORACLE_TAGS = ('cpython', 'rejected-by-design', 'selka-only')
DEFAULT_ORACLE_RULE = (
    'cpython: run with runpy, call main(), compare exit & 0xFF and stdout; '
    'rejected-by-design: valid Python the language rejects on purpose, counts only '
    'toward C3; selka-only: uses Option/Result/record/union, no CPython oracle, '
    'needs an expect directive')
DEFAULT_MANIFEST_VERSION = 'idiom-suite-v1'
RESULT_VERSION = 'lane-c-score-v1'
DEFAULT_DIVERGENCE_POLICY = ROOT / 'velocity' / 'divergences.json'
DIVERGENCE_VERSION = 'divergence-policy-v1'
PREVIEW_CHARS = 240

# Verdicts a probe can receive. A rejection is a compile error ('reject', or
# 'reject-run' when only the run stage reported it) or a trap before any output
# ('trap'); all three feed C3. A 'wrong' verdict is C2.
REJECTION_VERDICTS = ('reject', 'reject-run', 'trap')

# C2 is reported under two readings off one measurement. 'C2' is the strict
# count of completed disagreements and is never reduced; 'C2_policy' is the
# subset no declared divergence claims, and it is the number --gate uses.
STRICT_C2_DEFINITION = (
    'every probe selka accepted and ran to completion whose exit status (& 0xFF) or '
    'stdout differs from CPython, declared divergences included')
POLICY_C2_DEFINITION = (
    'silent wrong answers no entry in the divergence policy claims; this is the '
    'number a package gate fails on')


class InstrumentError(Exception):
    """A setup failure that stops the run before any probe is measured."""


# --------------------------------------------------------------------------
# Probe headers and diagnostics
# --------------------------------------------------------------------------

def read_oracle_tag(path: Path) -> str:
    """Read the ``# oracle: TAG`` line every probe must carry.

    The tag is read from the file rather than a hardcoded list, so the suite can
    grow without touching the scorer. The convention is the first line; blank
    and comment lines before it are tolerated so a probe may still start with a
    copyright line later if that is ever wanted.
    """
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith('# oracle:'):
            tag = stripped[len('# oracle:'):].strip()
            if tag not in ORACLE_TAGS:
                raise InstrumentError(
                    f'{path}: unknown oracle tag {tag!r} (expected one of {", ".join(ORACLE_TAGS)})')
            return tag
        if number > 5:
            break
    raise InstrumentError(f'{path}: no "# oracle: <tag>" header on the first lines')


def diagnostic_records(stderr: str) -> list[dict]:
    """Parse ``diagnostic-v1`` JSON Lines out of a command's stderr.

    ``--diagnostics=json`` writes one JSON object per line and leaves any other
    stderr text in place. Non-JSON lines (guest output, host failures) are
    ignored here and kept in the raw stderr preview instead.
    """
    records = []
    for line in stderr.splitlines():
        stripped = line.strip()
        if not stripped.startswith('{'):
            continue
        try:
            payload = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        if payload.get('version') != 'diagnostic-v1':
            continue
        inner = payload.get('diagnostic') or {}
        records.append({
            'code': inner.get('code') or '',
            'severity': inner.get('severity') or '',
            'message': inner.get('message') or '',
            'notes': inner.get('notes') or [],
            'fix': inner.get('fix'),
        })
    return records


# C3 has two detectors and they are never merged.
#
# ``structured`` is the metric goal.json defines: "diagnostic-v1 has a `fix`
# field or a note with role `alternative`". It is the primary number and it is
# what the before/after comparison and any acceptance claim use.
#
# ``text`` is a secondary, clearly-labelled reading of the same rejections
# against the prose the compiler already printed. It exists because the
# structured field does not exist yet and because the prose is real repair
# information, but it must not be mistaken for the field: it counts text that
# predates D1, so its before number is not zero and its movement is not evidence
# about D1.
SPELLING_PATTERNS = (
    # "use `pop`", "use 'x'"
    re.compile(r'\buse\s+[`\'"][^`\'"]+[`\'"]', re.I),
    # "use a top-level function"
    re.compile(r'\buse\s+(?:a|an|the)\s+\S', re.I),
    # "requires `_ =`"
    re.compile(r'\brequires?\s+[`\'"][^`\'"]+[`\'"]', re.I),
    # "write `x` instead"
    re.compile(r'\binstead\b', re.I),
    # "replace the receiver with `split(separator)`"
    re.compile(r'\breplace\b[^.;]{0,80}\bwith\b', re.I),
)
REPAIR_VERB = re.compile(
    r'\b(?:use|add|write|convert|declare|annotate|prefer|rename|replace)\s+\S', re.I)
NEGATED_CLAUSE = re.compile(
    r'\bno replacement\b|\bcannot\b|\bcan not\b|\bnot supported\b|\bnot accepted\b'
    r'|\bmust not\b|\bmay not\b|\bunsupported\b', re.I)


def _note_texts(diagnostic: dict) -> list[str]:
    """Every human-readable string a diagnostic carries besides its message."""
    texts = []
    for note in diagnostic.get('notes') or []:
        if isinstance(note, str):
            texts.append(note)
            continue
        if not isinstance(note, dict):
            continue
        for key in ('message', 'text', 'label', 'detail'):
            value = note.get(key)
            if isinstance(value, str):
                texts.append(value)
    return texts


def _has_fix(diagnostic: dict) -> bool:
    """Whether a diagnostic carries a usable structured ``fix``.

    ``fix`` is omitted from ``diagnostic-v1`` when it is null, so an absent key,
    an explicit null and an empty fix all mean "no fix".
    """
    fix = diagnostic.get('fix')
    return fix not in (None, False, '', {}, [])


def alternative_reason(diagnostic: dict, mode: str = 'structured') -> str | None:
    """Why this diagnostic carries an alternative or a fix, if it does.

    Returns a match kind, or ``None``:

    ``fix``               a structured ``fix`` field is present (D1's field).
    ``note-alternative``  a note whose ``role`` is ``alternative``.
    ``text-spelling``     the fallback matched a clause that names the accepted
                          spelling for the rejected construct.
    ``text-repair``       the fallback matched a clause with a repair verb
                          ("add `out: Stream` ... and pass one from main").

    ``mode`` selects which signals count: ``structured`` (the first two only),
    ``text`` (the fallback only) or ``any`` (both, for inspection only - the
    scorer never merges them into one metric).
    """
    if mode in ('any', 'structured'):
        if _has_fix(diagnostic):
            return 'fix'
        for note in diagnostic.get('notes') or []:
            if not isinstance(note, dict):
                continue
            if (note.get('role') or '').lower() == 'alternative':
                return 'note-alternative'
            if _has_fix(note):
                return 'fix'
    if mode == 'structured':
        return None
    text = ' '.join([diagnostic.get('message') or ''] + _note_texts(diagnostic))
    for clause in re.split(r'[;.]', text):
        if not clause.strip():
            continue
        if any(pattern.search(clause) for pattern in SPELLING_PATTERNS):
            return 'text-spelling'
        if REPAIR_VERB.search(clause) and not NEGATED_CLAUSE.search(clause):
            return 'text-repair'
    return None


def names_alternative(diagnostic: dict) -> bool:
    """Whether a diagnostic carries the structured alternative C3 counts.

    This is goal.json's rule: a non-null ``fix`` field, or a note whose ``role``
    is ``alternative``. ``names_alternative_text`` is the documented text
    fallback and is reported separately as ``C3_text_any``.
    """
    return alternative_reason(diagnostic, 'structured') is not None


def names_alternative_text(diagnostic: dict) -> bool:
    """Whether the documented text fallback finds repair information.

    It matches a clause of the message or of any note that either names the
    accepted spelling (``use <a|an|the> ...``, ``use `x` ``, ``requires `x` ``,
    ``instead``, ``replace ... with``) or contains a repair verb
    (``use|add|write|convert|declare|annotate|prefer|rename|replace`` followed by
    an argument). A clause that says there is no replacement, cannot be done, or
    is not supported never matches. This is secondary evidence only; it is not
    C3.
    """
    return alternative_reason(diagnostic, 'text') is not None


# --------------------------------------------------------------------------
# The declared divergence policy
# --------------------------------------------------------------------------
#
# An intentional, documented divergence and a silent wrong answer are the same
# observation to a CPython oracle: a completed run that disagrees. They differ
# only in whether a reviewed declaration claims the disagreement. The policy
# file holds those claims; ``velocity/divergence_evidence.py`` reproduces their
# values, and this scorer splits the wrong verdicts with them.

def load_divergence_policy(path: Path) -> dict:
    """Read the declared divergence list; a missing file is an empty policy.

    An empty policy is the conservative reading rather than a silent pass: every
    completed disagreement then counts as undeclared and gates. ``problem``
    carries why the file could not be used, and the caller reports it.
    """
    policy = {'version': None, 'path': str(path), 'entries': [], 'problem': ''}
    try:
        payload = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        policy['problem'] = str(error)
        return policy
    if not isinstance(payload.get('entries'), list):
        policy['problem'] = 'no "entries" list'
        return policy
    policy['version'] = payload.get('version')
    policy['entries'] = payload['entries']
    if policy['version'] != DIVERGENCE_VERSION:
        policy['problem'] = f"version {policy['version']!r}, expected {DIVERGENCE_VERSION!r}"
    return policy


def probe_divergence_id(entry: dict | None) -> str:
    """A one-token label for a claimed entry, for reports and records."""
    entry = entry or {}
    return entry.get('id') or entry.get('title') or 'declared'


def declared_divergence(policy: dict, probe: str) -> dict | None:
    """The policy entry that claims a probe, or ``None`` when it is undeclared."""
    for entry in policy.get('entries') or []:
        for pattern in entry.get('probes') or []:
            if fnmatch.fnmatch(probe, str(pattern)):
                return entry
    return None


def divergence_accounting(records: list[dict], policy: dict) -> tuple[list[dict], list[dict], list[dict]]:
    """Split the wrong verdicts into declared and undeclared, and list stale claims.

    Stale means the policy claims a probe that this selection either did not
    measure or measured with a verdict other than ``wrong``: the declaration no
    longer describes the tree, and the report says so instead of leaving an
    entry that quietly exempts nothing.
    """
    wrong = [record for record in records if record['verdict'] == 'wrong']
    declared, undeclared = [], []
    for record in wrong:
        entry = declared_divergence(policy, record['probe'])
        record['divergence'] = probe_divergence_id(entry) if entry else None
        record['c2_declared'] = entry is not None
        (declared if entry else undeclared).append(record)
    stale = []
    for entry in policy.get('entries') or []:
        for pattern in entry.get('probes') or []:
            matched = [r for r in records if fnmatch.fnmatch(r['probe'], str(pattern))]
            if not matched:
                stale.append({'entry': probe_divergence_id(entry), 'probe': str(pattern),
                              'reason': 'no selected probe matches (not exercised here)'})
            elif not any(r['verdict'] == 'wrong' for r in matched):
                stale.append({'entry': probe_divergence_id(entry), 'probe': str(pattern),
                              'reason': f"the selected probe measured {matched[0]['verdict']}, "
                                        f'not a wrong answer'})
    return declared, undeclared, stale


# --------------------------------------------------------------------------
# Running commands and probes
# --------------------------------------------------------------------------

def _load_shared_driver():
    """Load ``tests/idiom_probes.py`` for its CPython oracle and run classifier.

    Share, do not copy: backlog item V0 asks lane C to extend that driver
    instead of adding a second runner.
    """
    path = ROOT / 'tests' / 'idiom_probes.py'
    if not path.exists():
        raise InstrumentError(
            f'{path} is missing; velocity/score.py shares the CPython oracle with it')
    spec = importlib.util.spec_from_file_location('idiom_probes', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def measurement_environment() -> dict:
    """The environment probe commands run under.

    The native backend drives zig as its assembler and linker, and a global cache
    the process cannot write fails every ``selka run`` with
    ``manifest_create ReadOnlyFileSystem`` and ``host failure: NativeToolFailed``.
    That failure would otherwise read as a probe rejection - it did, once:
    ``d05_round_half.selka`` measured as ``reject-run`` with a read-only cache, which
    put a toolchain problem in the C3 denominator and hid the divergence the probe
    exists to expose. The scorer therefore supplies a writable cache of its own
    unless the caller names one.
    """
    env = dict(os.environ)
    if not env.get('ZIG_GLOBAL_CACHE_DIR'):
        cache = ROOT / '.selka-cache' / 'zig-global'
        cache.mkdir(parents=True, exist_ok=True)
        env['ZIG_GLOBAL_CACHE_DIR'] = str(cache)
    return env


def run_command(argv: list[str], timeout: float, env: dict | None = None) -> dict:
    """Run one command under a wall-clock ceiling, killing its process group.

    ``selka run`` builds and then executes a native child. Killing only the
    compiler would leave that child alive, so each command gets its own session
    and the whole group is killed on timeout.
    """
    started = time.monotonic()
    try:
        process = subprocess.Popen(
            argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            start_new_session=True, env=env if env is not None else measurement_environment())
    except OSError as error:
        return {'status': None, 'stdout': '', 'stderr': f'{argv[0]}: {error}',
                'timed_out': False, 'seconds': 0.0}
    try:
        stdout, stderr = process.communicate(timeout=timeout)
        timed_out = False
    except subprocess.TimeoutExpired:
        _kill_process_group(process)
        stdout, stderr = process.communicate()
        timed_out = True
    return {'status': process.returncode, 'stdout': stdout, 'stderr': stderr,
            'timed_out': timed_out, 'seconds': time.monotonic() - started}


def _kill_process_group(process: subprocess.Popen) -> None:
    """Kill a timed-out command together with any guest process it spawned."""
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        process.kill()


def preview(text: str, limit: int = PREVIEW_CHARS) -> str:
    """A bounded, single-value view of captured output for the JSON record."""
    if len(text) <= limit:
        return text
    return text[:limit] + f'... [{len(text) - limit} more bytes]'


def first_error_code(diagnostics: list[dict]) -> str | None:
    """The primary (first error) diagnostic code, or the first code seen."""
    for diagnostic in diagnostics:
        if diagnostic.get('severity') == 'error':
            return diagnostic.get('code') or None
    for diagnostic in diagnostics:
        if diagnostic.get('code'):
            return diagnostic['code']
    return None


def trap_record(stderr: str, diagnostics: list[dict]) -> dict:
    """A diagnostic-shaped record for a runtime failure with no JSON payload."""
    if diagnostics:
        return diagnostics[0]
    return {'code': _trap_code(stderr), 'severity': 'error', 'message': stderr.strip(),
            'notes': [], 'fix': None}


def _trap_code(stderr: str) -> str:
    """The R_ code of a trap reported as text, when one is visible."""
    match = re.search(r'error\[([A-Z_]+)\]', stderr)
    return match.group(1) if match else ''


def probe_record(path: Path) -> dict:
    """The empty per-probe record every measurement path starts from."""
    return {
        'probe': path.name, 'path': str(path), 'oracle': '', 'verdict': '',
        'accepts': False, 'completes': False, 'status': None,
        'code': None, 'codes': [], 'diagnostics': [],
        'c1': False, 'c2': False, 'c3': False,
        'c2_declared': False, 'divergence': None,
        'c3_text_any': False, 'c3_text_spelling': False,
        'alternative': None, 'alternative_text_kind': None,
        'alternative_structured': False, 'alternative_text': False,
        'seconds': 0.0, 'stdout_preview': '', 'stderr_preview': '',
        'oracle_status': None, 'oracle_stdout_preview': '', 'oracle_error': None,
    }


def measure_probe(path: Path, binary: Path, timeout: float, driver) -> dict:
    """Measure one probe: check it, run it if accepted, and compare oracles.

    Never raises for probe-level trouble: a trap, timeout, build failure or an
    oracle that cannot run all become a recorded verdict.
    """
    record = probe_record(path)
    record['oracle'] = read_oracle_tag(path)
    started = time.monotonic()
    checked = run_command([str(binary), 'check', str(path), '--diagnostics=json'], timeout)
    record['seconds'] = time.monotonic() - started
    record['diagnostics'] = diagnostic_records(checked['stderr'])
    if checked['timed_out']:
        record['verdict'] = 'check-timeout'
        record['stderr_preview'] = preview(checked['stderr'])
        return record
    if checked['status'] is None:
        # The compiler could not even start; do not read that as a rejection.
        record['verdict'] = 'check-error'
        record['stderr_preview'] = preview(checked['stderr'])
        return record
    if checked['status'] != 0:
        record['verdict'] = 'reject'
        record['code'] = first_error_code(record['diagnostics'])
        record['codes'] = [d['code'] for d in record['diagnostics'] if d.get('code')]
        record['stderr_preview'] = preview(checked['stderr'])
        return record

    record['accepts'] = True
    ran = run_command([str(binary), 'run', str(path), '--diagnostics=json'], timeout)
    record['seconds'] = time.monotonic() - started
    record['status'] = ran['status']
    record['stdout_preview'] = preview(ran['stdout'])
    run_diagnostics = diagnostic_records(ran['stderr'])
    if ran['timed_out']:
        record['verdict'] = 'run-timeout'
        record['stderr_preview'] = preview(ran['stderr'])
        return record
    if ran['status'] is None:
        record['verdict'] = 'run-error'
        record['stderr_preview'] = preview(ran['stderr'])
        return record
    if driver.host_failure(ran):
        # A host failure is a broken measurement, never a guest rejection: it
        # must not enter the C3 denominator or leave a probe looking unmeasured.
        record['verdict'] = 'host-error'
        record['stderr_preview'] = preview(ran['stderr'])
        return record
    failed = any(d.get('severity') == 'error' for d in run_diagnostics) or driver.failed_run(ran)
    if failed:
        record['diagnostics'] = run_diagnostics or [trap_record(ran['stderr'], run_diagnostics)]
        record['code'] = first_error_code(record['diagnostics']) or _trap_code(ran['stderr'])
        record['codes'] = [d['code'] for d in record['diagnostics'] if d.get('code')]
        record['stderr_preview'] = preview(ran['stderr'])
        if ran['stdout']:
            # Output already reached the user, so this is not a rejection the
            # C3 denominator counts; it is still not a completed run.
            record['verdict'] = 'trapped-after-output'
        else:
            record['verdict'] = 'trap' if (record['code'] or '').startswith('R_') else 'reject-run'
        return record

    record['completes'] = True
    if record['oracle'] != 'cpython':
        record['verdict'] = 'complete'
        return record
    oracle = driver.cpython_oracle(path, timeout)
    record['oracle_status'] = oracle.get('status')
    record['oracle_error'] = oracle.get('error')
    if not oracle.get('ok'):
        record['verdict'] = 'oracle-unavailable'
        record['stderr_preview'] = preview(oracle.get('stderr') or '')
        return record
    if (oracle['status'] == (ran['status'] & 0xFF)) and oracle['stdout'] == ran['stdout']:
        record['verdict'] = 'agree'
        record['c1'] = True
        return record
    record['verdict'] = 'wrong'
    record['c2'] = True
    record['oracle_stdout_preview'] = preview(oracle['stdout'])
    return record


def classify_c3(record: dict) -> None:
    """Decide what a rejected probe's diagnostics carry.

    Only error diagnostics count. A probe counts when at least one of them
    carries the information, because the agent reads all of them. The structured
    flag is the C3 metric; the text flags are reported beside it and never
    merged into it.
    """
    if record['verdict'] not in REJECTION_VERDICTS:
        return
    for diagnostic in record['diagnostics']:
        if diagnostic.get('severity') not in ('error', ''):
            continue
        structured = alternative_reason(diagnostic, 'structured')
        if structured:
            record['alternative_structured'] = True
            record['alternative'] = structured
        text = alternative_reason(diagnostic, 'text')
        if text:
            record['alternative_text'] = True
            record['alternative_text_kind'] = text
    record['c3'] = bool(record['alternative_structured'])
    record['c3_text_any'] = bool(record['alternative_text'])
    record['c3_text_spelling'] = record.get('alternative_text_kind') == 'text-spelling'


# --------------------------------------------------------------------------
# Identity and aggregation
# --------------------------------------------------------------------------

def file_sha256(path: Path) -> str:
    """Lowercase SHA-256 of a file, or an empty string when it is unreadable."""
    digest = hashlib.sha256()
    try:
        with path.open('rb') as handle:
            for block in iter(lambda: handle.read(1 << 20), b''):
                digest.update(block)
    except OSError:
        return ''
    return digest.hexdigest()


def compiler_identity(binary: Path, entry: Path, timeout: float) -> dict | None:
    """Best-effort compiler identity from ``schema-project --schema-report``.

    ``implementation.compiler_sha256`` is the build-time digest of the
    compiler's own sources, Zig version and optimize mode, so it names a
    compiler build better than the installed file's hash does. Returns ``None``
    when the entry is absent or the command fails.
    """
    if not entry.exists():
        return None
    result = run_command([str(binary), 'schema-project', str(entry), '--schema-report'], timeout)
    if result['status'] != 0:
        return None
    for line in result['stdout'].splitlines():
        stripped = line.strip()
        if not stripped.startswith('{'):
            continue
        try:
            payload = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        implementation = (payload.get('source') or {}).get('implementation')
        if implementation:
            return implementation
    return None


def binary_facts(binary: Path, entry: Path, timeout: float) -> dict:
    """Everything the result records about the binary that produced it."""
    digest = file_sha256(binary)
    facts = {
        'path': str(binary), 'sha256': digest,
        'mtime': datetime.datetime.fromtimestamp(
            binary.stat().st_mtime, datetime.timezone.utc).isoformat()
        if binary.exists() else None,
        'compiler_identity': compiler_identity(binary, entry, timeout),
    }
    return facts


def display_path(path: Path) -> str:
    """A repository-relative path when the file is inside the repository."""
    resolved = Path(path).resolve()
    return str(resolved.relative_to(ROOT)) if resolved.is_relative_to(ROOT) else str(resolved)


def binary_label(facts: dict) -> str:
    """A one-line identity for a manifest's ``binary`` field."""
    label = f"sha256:{facts['sha256']} {display_path(Path(facts['path']))}"
    identity = facts.get('compiler_identity') or {}
    if identity.get('compiler_sha256'):
        label += f" compiler:{identity['compiler_sha256']}"
    return label


def _fraction(count: int, total: int) -> float:
    """A metric value that is 0.0 rather than undefined on an empty selection."""
    return count / total if total else 0.0


def summarize(records: list[dict], policy: dict) -> dict:
    """Compute C1, C2 (strict and policy-adjusted) and C3 from the measured probes.

    ``C3`` is the structured metric goal.json defines. ``C3_text_any`` and
    ``C3_text_spelling`` are the secondary text readings and are never merged
    into ``C3``. ``C2`` is the strict count of completed disagreements and is
    never reduced by the policy; ``C2_policy`` is the subset no declared
    divergence claims and is the number ``--gate`` uses.
    """
    cpython = [r for r in records if r['oracle'] == 'cpython']
    agreements = [r for r in cpython if r['verdict'] == 'agree']
    wrong = [r for r in records if r['verdict'] == 'wrong']
    declared, undeclared, stale = divergence_accounting(records, policy)
    rejected = [r for r in records if r['verdict'] in REJECTION_VERDICTS]
    structured = [r for r in rejected if r['c3']]
    text = [r for r in rejected if r['c3_text_any']]
    spelling = [r for r in rejected if r['c3_text_spelling']]
    histogram: dict[str, int] = {}
    for record in records:
        if record['code']:
            key = record['code']
        elif record['verdict'] in ('agree', 'complete'):
            key = 'OK'
        elif record['verdict'] == 'wrong':
            key = 'OK/SILENT-WRONG' + ('/DECLARED' if record['c2_declared'] else '')
        else:
            key = record['verdict']
        histogram[key] = histogram.get(key, 0) + 1

    def wrong_row(record: dict) -> dict:
        """One per-probe wrong-answer row, with the claimed divergence if any."""
        return {'probe': record['probe'], 'stdout': record['stdout_preview'],
                'oracle_stdout': record['oracle_stdout_preview'],
                'status': record['status'], 'oracle_status': record['oracle_status'],
                'divergence': record['divergence']}

    return {
        'C1': {
            'value': _fraction(len(agreements), len(cpython)),
            'numerator': len(agreements), 'denominator': len(cpython),
            'agreed': [r['probe'] for r in agreements],
        },
        'C2': {
            'definition': STRICT_C2_DEFINITION,
            'value': len(wrong), 'gate': False,
            'probes': [wrong_row(r) for r in wrong],
        },
        'C2_policy': {
            'definition': POLICY_C2_DEFINITION,
            'value': len(undeclared), 'gate': True,
            'probes': [wrong_row(r) for r in undeclared],
            'declared': [wrong_row(r) for r in declared],
            'stale': stale,
            'policy': {'path': policy.get('path'), 'version': policy.get('version'),
                       'problem': policy.get('problem') or None,
                       'entries': len(policy.get('entries') or [])},
        },
        'C3': {
            'definition': 'diagnostic-v1 carries a non-null fix or a note whose role is alternative',
            'value': _fraction(len(structured), len(rejected)),
            'numerator': len(structured), 'denominator': len(rejected),
            'matched': [{'probe': r['probe'], 'code': r['code'], 'kind': r['alternative']}
                        for r in structured],
            'unmatched': [{'probe': r['probe'], 'code': r['code'],
                           'message': r['diagnostics'][0]['message'] if r['diagnostics'] else ''}
                          for r in rejected if not r['c3']],
        },
        'C3_text_any': {
            'definition': 'secondary text heuristic: the message or a note names a '
                          'replacement spelling or carries a repair verb',
            'value': _fraction(len(text), len(rejected)),
            'numerator': len(text), 'denominator': len(rejected),
            'matched': [{'probe': r['probe'], 'code': r['code'],
                         'kind': r['alternative_text_kind']} for r in text],
        },
        'C3_text_spelling': {
            'definition': 'subset of C3_text_any that names an accepted spelling',
            'value': _fraction(len(spelling), len(rejected)),
            'numerator': len(spelling), 'denominator': len(rejected),
        },
        'verdicts': {verdict: sum(1 for r in records if r['verdict'] == verdict)
                     for verdict in sorted({r['verdict'] for r in records})},
        'histogram': dict(sorted(histogram.items(), key=lambda item: (-item[1], item[0]))),
    }


def result_document(records: list[dict], suite: Path, selection: str, binary: dict,
                    elapsed: float, policy: dict) -> dict:
    """The ``lane-c-score-v1`` JSON document a run writes."""
    return {
        'version': RESULT_VERSION,
        'measured_on': datetime.date.today().isoformat(),
        'suite': str(suite.relative_to(ROOT)) if suite.is_relative_to(ROOT) else str(suite),
        'selection': selection,
        'binary': binary,
        'elapsed_seconds': round(elapsed, 3),
        'metrics': summarize(records, policy),
        'probes': records,
    }


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

def format_delta(before: float | None, after: float, digits: int = 3) -> str:
    """The ``[baseline X, +Y]`` suffix of a metric line."""
    if before is None:
        return ''
    return f'  [baseline {before:.{digits}f}, {after - before:+.{digits}f}]'


def print_report(document: dict, baseline: dict | None) -> None:
    """The human-readable report: metrics, histogram, then every probe."""
    metrics = document['metrics']
    binary = document['binary']
    identity = binary.get('compiler_identity') or {}
    print(f"lane C scorer - {document['suite']} ({document['selection']}), "
          f"{len(document['probes'])} probes, {document['elapsed_seconds']:.1f}s")
    print(f"binary {binary['path']} sha256 {binary['sha256'][:16]}...")
    if identity:
        print(f"compiler compiler_sha256 {identity.get('compiler_sha256')} "
              f"zig {identity.get('zig_version')} {identity.get('optimize')} "
              f"{identity.get('architecture')}-{identity.get('os')}-{identity.get('abi')}")
    else:
        print('compiler identity unavailable (schema-project --schema-report did not answer)')
    before = (baseline or {}).get('metrics', {})

    c1 = metrics['C1']
    c2 = metrics['C2']
    c2_policy = metrics['C2_policy']
    c3 = metrics['C3']
    text = metrics['C3_text_any']
    print()
    print(f"C1 first-try fidelity      {c1['value']:.3f}  "
          f"({c1['numerator']}/{c1['denominator']} oracle: cpython probes)"
          f"{format_delta(before.get('C1', {}).get('value'), c1['value'])}")
    print(f"C2 silent wrong answers    {c2['value']}  (strict: every completed probe that "
          f"disagrees with CPython)"
          f"{format_delta(before.get('C2', {}).get('value'), float(c2['value']), 0)}")
    for wrong in c2['probes']:
        claimed = f"  [declared: {wrong['divergence']}]" if wrong['divergence'] else '  [UNDECLARED]'
        print(f"     {wrong['probe']}: selka {wrong['status']} {wrong['stdout']!r} "
              f"vs cpython {wrong['oracle_status']} {wrong['oracle_stdout']!r}{claimed}")
    gate = '  *** GATE: undeclared silent wrong answers ***' if c2_policy['value'] else ''
    print(f"C2 undeclared (gate)       {c2_policy['value']}  "
          f"(not claimed by the divergence policy; this is what --gate fails on)"
          f"{format_delta(before.get('C2_policy', {}).get('value'), float(c2_policy['value']), 0)}"
          f"{gate}")
    policy_facts = c2_policy['policy']
    version = policy_facts['version'] or 'unversioned'
    print(f"     divergence policy: {display_path(Path(policy_facts['path']))} "
          f"({version}, {policy_facts['entries']} entr"
          f"{'y' if policy_facts['entries'] == 1 else 'ies'})")
    if policy_facts['problem']:
        print(f"     policy problem: {policy_facts['problem']}; every disagreement is "
              f"counted as undeclared")
    for stale in c2_policy['stale']:
        print(f"     stale declaration: {stale['probe']} ({stale['entry']}): {stale['reason']}")
    print(f"C3 rejections with a fix   {c3['value']:.3f}  "
          f"({c3['numerator']}/{c3['denominator']} rejected)"
          f"{format_delta(before.get('C3', {}).get('value'), c3['value'])}")
    print(f"     definition: {c3['definition']}")
    print(f"     C3_text_any (secondary, existing prose, not C3): {text['value']:.3f} "
          f"({text['numerator']}/{text['denominator']})"
          f"{format_delta(before.get('C3_text_any', {}).get('value'), text['value'])}")
    spelling = metrics['C3_text_spelling']
    print(f"     of which name a replacement spelling:            {spelling['value']:.3f} "
          f"({spelling['numerator']}/{spelling['denominator']})")
    kinds: dict[str, int] = {}
    for matched in text['matched']:
        kinds[matched['kind']] = kinds.get(matched['kind'], 0) + 1
    if kinds:
        print('     text match kinds: ' + ', '.join(f'{kind} {count}' for kind, count in sorted(kinds.items())))

    print('\nper-code histogram (primary diagnostic per probe)')
    for code, count in metrics['histogram'].items():
        print(f'  {count:3d} {code}')

    print('\nper-probe table')
    print(f"  {'probe':30s} {'oracle':20s} {'verdict':22s} {'code':22s} C1 C2 C3 C3t diverg")
    for record in document['probes']:
        print(f"  {record['probe']:30s} {record['oracle']:20s} {record['verdict']:22s} "
              f"{(record['code'] or '-'):22s} "
              f"{_mark(record['c1'])}  {_mark(record['c2'])}  {_mark(record['c3'])}  "
              f"{_mark(record['c3_text_any'])} "
              f"{record['divergence'] or ('!' if record['c2'] else '')}")
    print('  C3 = structured fix/alternative field; C3t = secondary text heuristic; '
          'diverg = declared divergence id or ! for an undeclared wrong answer')
    print_histogram_legend(document, baseline)


def _mark(value: bool) -> str:
    """A one-column yes/no marker for the per-probe table."""
    return ' x' if value else ' .'


def print_histogram_legend(document: dict, baseline: dict | None) -> None:
    """Probe-level changes against a previous result, when one was supplied."""
    if not baseline:
        return
    previous = {record['probe']: record for record in baseline.get('probes', [])}
    selected = {record['probe'] for record in document['probes']}
    changes = []
    for record in document['probes']:
        old = previous.get(record['probe'])
        if old is None:
            changes.append(f"  + {record['probe']}: new ({record['verdict']})")
        elif old['verdict'] != record['verdict']:
            changes.append(f"  ~ {record['probe']}: {old['verdict']} -> {record['verdict']}"
                           f" ({old.get('code') or '-'} -> {record['code'] or '-'})")
    missing = [name for name in previous if name not in selected]
    if not changes and not missing:
        return
    print('\nchanges against the supplied baseline result')
    for line in changes:
        print(line)
    if missing:
        print(f'  - {len(missing)} baseline probes were not selected in this run')
    if baseline.get('selection') != document['selection']:
        print(f"  ! baseline selection {baseline.get('selection')!r} differs from this run's "
              f"{document['selection']!r}; the metric deltas above compare different probe sets")


# --------------------------------------------------------------------------
# Manifest output
# --------------------------------------------------------------------------

def read_manifest_template(suite: Path) -> tuple[str, str]:
    """The ``version`` and ``oracle_rule`` strings the suite manifest already uses."""
    path = suite / MANIFEST_NAME
    if path.exists():
        try:
            payload = json.loads(path.read_text())
        except json.JSONDecodeError:
            payload = {}
        return (payload.get('version') or DEFAULT_MANIFEST_VERSION,
                payload.get('oracle_rule') or DEFAULT_ORACLE_RULE)
    return DEFAULT_MANIFEST_VERSION, DEFAULT_ORACLE_RULE


def manifest_document(records: list[dict], suite: Path, binary: dict,
                      measured_on: str, policy: dict) -> dict:
    """A ``manifest.json``-shaped record of a run.

    ``agree`` follows the existing file: ``null`` for ``selka-only`` probes
    (there is no CPython oracle to agree with), a boolean otherwise. A
    ``rejected-by-design`` probe always reports ``false`` because there is no
    agreement to assert, whether or not selka accepted it. ``silent_wrong``
    stays the strict reading; ``declared_divergence`` names the policy entry
    that claims the probe, so a regenerated manifest cannot lose the exemption
    a declaration grants.
    """
    version, oracle_rule = read_manifest_template(suite)
    probes = []
    for record in sorted(records, key=lambda item: item['probe']):
        tag = record['oracle']
        probes.append({
            'name': record['probe'],
            'oracle': tag,
            'baseline': {
                'selka_accepts': bool(record['accepts']),
                'agree': None if tag == 'selka-only' else bool(record['verdict'] == 'agree'),
                'silent_wrong': bool(record['c2']),
            },
            'declared_divergence': record['divergence'],
        })
    return {
        'version': version,
        'measured_on': measured_on,
        'binary': binary_label(binary),
        'oracle_rule': oracle_rule,
        'divergence_policy': {'path': display_path(Path(policy['path'])),
                              'version': policy.get('version')},
        'probes': probes,
    }


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------

def selected_probes(suite: Path, pattern: str) -> list[Path]:
    """Every probe in the suite matching the glob, in name order."""
    probes = sorted(suite.glob(PROBE_GLOB))
    if pattern == '*':
        return probes
    return [path for path in probes if _matches(path.name, pattern)]


def _matches(name: str, pattern: str) -> bool:
    """Glob a probe name, treating a bare pattern as a substring match."""
    return fnmatch.fnmatch(name, pattern)


# Fixed cases for --self-test: each is (name, diagnostic, structured, text).
DETECTOR_CASES = (
    ('plain syntax error', {'message': 'unexpected token; expected def', 'notes': []}, False, False),
    ('fix present', {'message': 'x', 'notes': [], 'fix': {'edits': [{'at': 3, 'text': ','}]}}, True, False),
    ('fix absent', {'message': 'x', 'notes': []}, False, False),
    ('fix null', {'message': 'x', 'notes': [], 'fix': None}, False, False),
    ('note role alternative', {'message': 'x', 'notes': [
        {'role': 'alternative', 'message': 'use split(separator)'}]}, True, True),
    ('note role alternative, no prose hit', {'message': 'x', 'notes': [
        {'role': 'alternative', 'message': 'split(separator)'}]}, True, False),
    ('note role related', {'message': 'x', 'notes': [{'role': 'related', 'message': 'see also'}]},
     False, False),
    ('note carries fix', {'message': 'x', 'notes': [{'role': 'related', 'fix': {'text': ','}}]},
     True, False),
    ('text: lambda capture', {'message': 'lambda cannot capture local `k`; use a top-level '
                                         'function or pass the value as an explicit state parameter',
                              'notes': []}, False, True),
    ('text: output capability', {'message': 'print needs a Stream; add `out: Stream` to this '
                                            'function and pass one from main', 'notes': []}, False, True),
    ('text: no replacement', {'message': '`&` was removed and has no replacement', 'notes': []},
     False, False),
    ('text: trap detail', {'message': 'native execution failed (add: left 1, right 1, width 64)',
                           'notes': []}, False, False),
    ('text: signature only', {'message': 'list method argument count does not match its signature',
                              'notes': []}, False, False),
    ('text: requires backtick', {'message': 'a standalone non-unit value requires `_ =` or result '
                                            'handling', 'notes': []}, False, True),
)

# Fixed cases for --self-test: (name, entries, probe, expected declared id).
DIVERGENCE_CASES = (
    ('exact name claimed', [{'id': 'a', 'probes': ['p1.selka']}], 'p1.selka', 'a'),
    ('glob claimed', [{'id': 'b', 'probes': ['d0*.selka']}], 'd05_round_half.selka', 'b'),
    ('later entry claims it', [{'id': 'a', 'probes': ['x.selka']},
                               {'id': 'b', 'probes': ['p?.selka']}], 'p1.selka', 'b'),
    ('unclaimed probe', [{'id': 'a', 'probes': ['x.selka']}], 'p1.selka', None),
    ('empty policy declares nothing', [], 'p1.selka', None),
)


def policy_self_test() -> int:
    """Check the declared/undeclared split and the stale-claim report.

    No compiler is needed: the records are the same shape ``probe_record``
    produces, with only the verdict and the two C2 flags filled in.
    """
    failures = []
    for name, entries, probe, wanted in DIVERGENCE_CASES:
        policy = {'version': DIVERGENCE_VERSION, 'path': 'self-test', 'entries': entries,
                  'problem': ''}
        entry = declared_divergence(policy, probe)
        observed = probe_divergence_id(entry) if entry else None
        if observed != wanted:
            failures.append(f'{name}: claimed {observed!r}, expected {wanted!r}')

    records = [probe_record(Path('p1.selka')), probe_record(Path('p2.selka'))]
    for record in records:
        record['verdict'] = 'wrong'
        record['c2'] = True
    policy = {'version': DIVERGENCE_VERSION, 'path': 'self-test',
              'entries': [{'id': 'a', 'probes': ['p1.selka']}], 'problem': ''}
    metrics = summarize(records, policy)
    checks = (
        ('strict C2 counts every disagreement', metrics['C2']['value'] == 2),
        ('policy C2 counts only the unclaimed one', metrics['C2_policy']['value'] == 1),
        ('the declared row names its entry', metrics['C2_policy']['declared'][0]['divergence'] == 'a'),
        ('the undeclared row has no entry', metrics['C2_policy']['probes'][0]['divergence'] is None),
        ('a declared probe is still a strict C2', bool(records[0]['c2'] and records[0]['c2_declared'])),
    )
    failures.extend(name for name, passed in checks if not passed)

    records[0]['verdict'] = 'agree'
    stale = summarize(records, policy)['C2_policy']['stale']
    if not any(item['probe'] == 'p1.selka' for item in stale):
        failures.append('a claimed probe that agrees is not reported as a stale declaration')

    if failures:
        print('lane C divergence policy self-test failed: ' + '; '.join(failures), file=sys.stderr)
        return 1
    print(f'lane C divergence policy self-test: {len(DIVERGENCE_CASES) + len(checks) + 1} passed')
    return 0


def self_test() -> int:
    """Check the C3 detectors, the divergence policy split and the CPython oracle."""
    failures = [name for name, diagnostic, structured, text in DETECTOR_CASES
                if (names_alternative(diagnostic), names_alternative_text(diagnostic))
                != (structured, text)]
    if failures:
        print('lane C detector self-test failed: ' + ', '.join(failures), file=sys.stderr)
        return 1
    print(f'lane C detector self-test: {len(DETECTOR_CASES)} passed')
    if policy_self_test() != 0:
        return 1
    return _load_shared_driver().oracle_self_test()


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Command-line contract for the lane C scorer."""
    parser = argparse.ArgumentParser(
        description='Measure lane C (Python fidelity) over the idiom suite.',
        formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    parser.add_argument('--binary', type=Path, default=DEFAULT_BINARY,
                        help='compiler to measure (default zig-out/bin/selka)')
    parser.add_argument('--json', action='store_true',
                        help='write the lane-c-score-v1 JSON document to stdout instead of the table')
    parser.add_argument('--baseline', type=Path,
                        help='a previously written result JSON to print before/after deltas against')
    parser.add_argument('--write', type=Path, help='write the result JSON to this path')
    parser.add_argument('--write-manifest', type=Path, metavar='PATH',
                        help='write a manifest.json-shaped file for this run (the lead runs this '
                             'once the packages land; it is not run against the suite manifest here)')
    parser.add_argument('--probe', default='*', metavar='GLOB',
                        help="only probes whose name matches GLOB (default '*')")
    parser.add_argument('--jobs', type=int, default=min(8, os.cpu_count() or 1),
                        help='probes measured concurrently (default min(8, cpus))')
    parser.add_argument('--timeout', type=float, default=60.0,
                        help='wall-clock ceiling per command, in seconds (default 60)')
    parser.add_argument('--gate', action='store_true',
                        help='exit 1 when an UNDECLARED silent wrong answer exists (C2_policy > 0); '
                             'a divergence declared in velocity/divergences.json is reported but '
                             'does not fail the gate')
    parser.add_argument('--divergences', type=Path, default=DEFAULT_DIVERGENCE_POLICY,
                        metavar='PATH',
                        help='declared divergence list (default velocity/divergences.json); a '
                             'missing file declares nothing and every disagreement then gates')
    parser.add_argument('--self-test', action='store_true',
                        help='check the C3 detectors and the shared CPython oracle, then exit')
    parser.add_argument('--suite', type=Path, default=DEFAULT_SUITE, help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Measure every selected probe and report C1, C2 (strict and policy) and C3."""
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if args.self_test:
        return self_test()
    suite = args.suite.resolve()
    binary = args.binary if args.binary.is_absolute() else (Path.cwd() / args.binary).resolve()
    policy_path = args.divergences if args.divergences.is_absolute() \
        else (Path.cwd() / args.divergences).resolve()
    policy = load_divergence_policy(policy_path)
    if policy['problem']:
        print(f"score.py: warning: divergence policy {policy_path} is unusable "
              f"({policy['problem']}); declaring nothing, so every completed disagreement "
              f"counts as an undeclared silent wrong answer", file=sys.stderr)
    if not binary.exists():
        print(f'score.py: no compiler at {binary}', file=sys.stderr)
        return 2
    if not suite.is_dir():
        print(f'score.py: no suite directory at {suite}', file=sys.stderr)
        return 2
    probes = selected_probes(suite, args.probe)
    if not probes:
        print(f'score.py: no probes match {args.probe!r} in {suite}', file=sys.stderr)
        return 2

    try:
        driver = _load_shared_driver()
    except InstrumentError as error:
        print(f'score.py: {error}', file=sys.stderr)
        return 2

    facts = binary_facts(binary, DEFAULT_IDENTITY_ENTRY, args.timeout)
    started = time.monotonic()
    records: list[dict] = []
    jobs = max(1, args.jobs)
    print(f'score.py: measuring {len(probes)} probes with {binary} '
          f'({jobs} job{"s" if jobs != 1 else ""})', file=sys.stderr)
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = {pool.submit(measure_probe, path, binary, args.timeout, driver): path
                   for path in probes}
        for future in concurrent.futures.as_completed(futures):
            path = futures[future]
            try:
                records.append(future.result())
            except Exception as error:  # a broken probe must not abort the run
                broken = probe_record(path)
                broken['verdict'] = 'scorer-error'
                broken['stderr_preview'] = f'{type(error).__name__}: {error}'
                records.append(broken)
    records.sort(key=lambda item: item['probe'])
    for record in records:
        classify_c3(record)
    elapsed = time.monotonic() - started

    if facts['sha256'] != file_sha256(binary):
        print('score.py: warning: the compiler binary changed during the run; '
              'rerun for a consistent measurement', file=sys.stderr)
    document = result_document(records, suite, args.probe, facts, elapsed, policy)

    baseline = None
    if args.baseline:
        try:
            baseline = json.loads(args.baseline.read_text())
        except (OSError, json.JSONDecodeError) as error:
            print(f'score.py: cannot read --baseline {args.baseline}: {error}', file=sys.stderr)
            return 2
        if baseline.get('version') != RESULT_VERSION:
            print(f'score.py: warning: --baseline is {baseline.get("version")!r}, '
                  f'expected {RESULT_VERSION!r}', file=sys.stderr)
        if baseline.get('selection') != document['selection']:
            print(f'score.py: warning: --baseline covered {baseline.get("selection")!r} but '
                  f'this run covers {document["selection"]!r}; the deltas compare '
                  f'different probe sets', file=sys.stderr)

    if args.json:
        print(json.dumps(document, indent=1))
    else:
        print_report(document, baseline)

    if args.write:
        args.write.parent.mkdir(parents=True, exist_ok=True)
        args.write.write_text(json.dumps(document, indent=1) + '\n')
        print(f'score.py: wrote {args.write}', file=sys.stderr)
    if args.write_manifest:
        if args.probe != '*':
            print('score.py: warning: --probe is set, so the manifest describes only '
                  'the selected probes', file=sys.stderr)
        args.write_manifest.parent.mkdir(parents=True, exist_ok=True)
        document_manifest = manifest_document(records, suite, facts, document['measured_on'],
                                              policy)
        args.write_manifest.write_text(json.dumps(document_manifest, indent=1) + '\n')
        print(f'score.py: wrote {args.write_manifest} '
              f'({len(document_manifest["probes"])} probes)', file=sys.stderr)

    if args.gate:
        metrics = document['metrics']
        undeclared = metrics['C2_policy']['value']
        declared = metrics['C2']['value'] - undeclared
        if undeclared:
            names = ', '.join(row['probe'] for row in metrics['C2_policy']['probes'])
            print(f'score.py: gate failed: {undeclared} undeclared silent wrong answer(s): '
                  f'{names}; declare one only by adding a reviewed entry to '
                  f'{display_path(policy_path)}', file=sys.stderr)
            return 1
        if declared:
            names = ', '.join(f"{row['probe']} ({row['divergence']})"
                              for row in metrics['C2_policy']['declared'])
            print(f'score.py: gate passed: {declared} declared divergence(s) reported and '
                  f'exempt by {display_path(policy_path)}: {names}', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
