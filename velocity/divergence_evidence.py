#!/usr/bin/env python3
"""Reproduce the declared CPython divergences and publish the observed pair.

``velocity/divergences.json`` says where the language intentionally answers
differently from CPython; this script is what keeps that declaration honest. For
every declared expression it evaluates the same expression text under
``selka`` (through a generated ``out: Stream`` program) and under CPython, and
compares both answers with the value the declaration records. For every probe a
declaration claims, it runs the probe both ways through the CPython oracle
``tests/idiom_probes.py`` shares with ``velocity/score.py`` and records the raw
status/stdout pair. The result is ``divergence-evidence.json``: the concrete
observed mismatch, kept in the suite beside the manifest instead of being
normalised away.

Exit status: 0 every declared value reproduced, 1 a declared value did not
reproduce or a claimed probe now agrees (the policy is stale), 2 a setup failure
(the compiler or the oracle could not run at all).

Examples::

    python3 velocity/divergence_evidence.py
    python3 velocity/divergence_evidence.py --check-only
    python3 velocity/divergence_evidence.py --binary zig-out/bin/selka-baseline-20260920
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import importlib.util
import json
import platform
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_POLICY = ROOT / 'velocity' / 'divergences.json'
DEFAULT_SUITE = ROOT / 'velocity' / 'suites' / 'idioms'
DEFAULT_BINARY = ROOT / 'zig-out' / 'bin' / 'selka'
DEFAULT_OUT = DEFAULT_SUITE / 'divergence-evidence.json'
SCRATCH = ROOT / '.tmp' / 'divergence-evidence'
EVIDENCE_VERSION = 'divergence-evidence-v1'
GUEST_HEADER = 'def main(out: Stream) -> int effects(output):\n'


class EvidenceError(Exception):
    """A setup failure that stops the run before anything is observed."""


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


def load_policy(path: Path) -> dict:
    """Read the declared divergence list and refuse a policy with no version."""
    try:
        payload = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise EvidenceError(f'cannot read divergence policy {path}: {error}') from error
    if not payload.get('version'):
        raise EvidenceError(f'{path}: no "version" key; this is not a divergence policy')
    if not isinstance(payload.get('entries'), list):
        raise EvidenceError(f'{path}: "entries" must be a list')
    return payload


def load_shared_driver():
    """Load ``tests/idiom_probes.py`` for the CPython oracle, as score.py does."""
    path = ROOT / 'tests' / 'idiom_probes.py'
    if not path.exists():
        raise EvidenceError(f'{path} is missing; the oracle is shared with it')
    spec = importlib.util.spec_from_file_location('idiom_probes', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def declared_cases(policy: dict) -> list[tuple[str, dict]]:
    """Every ``(entry id, case)`` the policy declares, in file order."""
    cases = []
    for entry in policy['entries']:
        for case in entry.get('cases') or []:
            if not isinstance(case.get('expression'), str):
                raise EvidenceError(f"entry {entry.get('id')!r}: a case has no expression")
            cases.append((entry.get('id') or '<unnamed>', case))
    return cases


def declared_probes(policy: dict) -> list[tuple[str, str]]:
    """Every ``(entry id, probe name)`` the policy claims, in file order."""
    claimed = []
    for entry in policy['entries']:
        for probe in entry.get('probes') or []:
            claimed.append((entry.get('id') or '<unnamed>', probe))
    return claimed


def guest_source(expressions: list[str]) -> str:
    """One selka program printing each expression on its own line."""
    lines = [GUEST_HEADER]
    for expression in expressions:
        lines.append(f'    out.print({expression})\n')
    lines.append('    return 0\n')
    return ''.join(lines)


def run_selka_expressions(binary: Path, expressions: list[str], timeout: float) -> list[str]:
    """Evaluate every expression under selka; one printed line per expression."""
    SCRATCH.mkdir(parents=True, exist_ok=True)
    path = SCRATCH / 'expressions.selka'
    path.write_text(guest_source(expressions))
    try:
        completed = subprocess.run([str(binary), 'run', str(path)],
                                   capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise EvidenceError(f'selka could not evaluate the declared cases: {error}') from error
    if completed.returncode != 0:
        raise EvidenceError(
            f'selka run exited {completed.returncode} for the declared cases: '
            f'{completed.stderr.strip()[:400]}')
    return completed.stdout.splitlines()


def run_cpython_expressions(expressions: list[str], timeout: float) -> list[str]:
    """Evaluate the same expression texts under CPython, one print per line."""
    program = ''.join(f'print({expression})\n' for expression in expressions)
    try:
        completed = subprocess.run([sys.executable, '-c', program],
                                   capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise EvidenceError(f'CPython could not evaluate the declared cases: {error}') from error
    if completed.returncode != 0:
        raise EvidenceError(f'CPython exited {completed.returncode}: {completed.stderr.strip()[:400]}')
    return completed.stdout.splitlines()


def reproduces(observed: str, declared) -> bool:
    """Whether an observed printed line matches the declared value.

    Numbers compare numerically so a declared ``3`` matches an observed ``3.0``;
    anything else compares as text.
    """
    if isinstance(declared, bool):
        return observed.strip().lower() == str(declared).lower()
    if isinstance(declared, (int, float)):
        try:
            return float(observed.strip()) == float(declared)
        except ValueError:
            return False
    return observed.strip() == str(declared).strip()


def case_records(binary: Path, cases: list[tuple[str, dict]], timeout: float) -> list[dict]:
    """Observe every declared expression under both runtimes."""
    if not cases:
        return []
    expressions = [case['expression'] for _, case in cases]
    selka_lines = run_selka_expressions(binary, expressions, timeout)
    cpython_lines = run_cpython_expressions(expressions, timeout)
    if len(selka_lines) != len(expressions) or len(cpython_lines) != len(expressions):
        raise EvidenceError(
            f'expected {len(expressions)} lines per runtime, saw '
            f'selka {len(selka_lines)} and cpython {len(cpython_lines)}')
    records = []
    for (entry_id, case), observed_selka, observed_cpython in zip(cases, selka_lines, cpython_lines):
        declared = case
        records.append({
            'entry': entry_id,
            'expression': case['expression'],
            'declared': {'selka': case.get('selka'), 'cpython': case.get('cpython')},
            'observed': {'selka': observed_selka, 'cpython': observed_cpython},
            'reproduces': {
                'selka': reproduces(observed_selka, case.get('selka')),
                'cpython': reproduces(observed_cpython, case.get('cpython')),
            },
        })
    return records


def probe_record(binary: Path, suite: Path, entry_id: str, name: str, driver, timeout: float) -> dict:
    """Run one claimed probe under selka and under the shared CPython oracle."""
    path = suite / name
    if not path.exists():
        return {'entry': entry_id, 'probe': name, 'error': f'{path} does not exist'}
    try:
        completed = subprocess.run([str(binary), 'run', str(path), '--print-result'],
                                   capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as error:
        return {'entry': entry_id, 'probe': name, 'error': f'selka run failed: {error}'}
    oracle = driver.cpython_oracle(path, timeout)
    return {
        'entry': entry_id,
        'probe': name,
        'selka': {'status': completed.returncode, 'value': completed.stdout.strip(),
                   'stderr_first_line': completed.stderr.strip().splitlines()[0]
                   if completed.stderr.strip() else ''},
        'cpython': {'status': oracle.get('status'), 'stdout': oracle.get('stdout', '').strip(),
                    'ok': bool(oracle.get('ok')), 'error': oracle.get('error')},
        'agrees': bool(oracle.get('ok')) and completed.returncode == (oracle.get('status') or 0),
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Command-line contract for the divergence evidence recorder."""
    parser = argparse.ArgumentParser(
        description='Reproduce the declared CPython divergences and record the observed pair.',
        formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    parser.add_argument('--binary', type=Path, default=DEFAULT_BINARY,
                        help='compiler to observe (default zig-out/bin/selka)')
    parser.add_argument('--policy', type=Path, default=DEFAULT_POLICY,
                        help='declared divergence list (default velocity/divergences.json)')
    parser.add_argument('--suite', type=Path, default=DEFAULT_SUITE,
                        help='the probe suite a declaration claims probes from')
    parser.add_argument('--out', type=Path, default=DEFAULT_OUT,
                        help='where to write the evidence JSON (default beside the manifest)')
    parser.add_argument('--timeout', type=float, default=60.0,
                        help='wall-clock ceiling per command, in seconds (default 60)')
    parser.add_argument('--check-only', action='store_true',
                        help='reproduce the declarations without writing the evidence file')
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Reproduce every declared divergence and write the observed evidence."""
    args = parse_args(sys.argv[1:] if argv is None else argv)
    binary = args.binary if args.binary.is_absolute() else (Path.cwd() / args.binary).resolve()
    if not binary.exists():
        print(f'divergence_evidence.py: no compiler at {binary}', file=sys.stderr)
        return 2
    try:
        policy = load_policy(args.policy.resolve())
        driver = load_shared_driver()
        cases = case_records(binary, declared_cases(policy), args.timeout)
        probes = [probe_record(binary, args.suite.resolve(), entry_id, name, driver, args.timeout)
                  for entry_id, name in declared_probes(policy)]
    except EvidenceError as error:
        print(f'divergence_evidence.py: {error}', file=sys.stderr)
        return 2

    document = {
        'version': EVIDENCE_VERSION,
        'measured_on': datetime.date.today().isoformat(),
        'policy': {'path': str(args.policy), 'version': policy.get('version'),
                   'sha256': file_sha256(args.policy)},
        'binary': {'path': str(binary), 'sha256': file_sha256(binary)},
        'python': {'executable': sys.executable, 'version': platform.python_version()},
        'cases': cases,
        'probes': probes,
        'commands': {
            'record': f'python3 velocity/divergence_evidence.py --binary {args.binary}',
            'strict_c2': "python3 velocity/score.py --probe 'd05*' --json",
        },
    }

    unreproduced = [f"{record['entry']}: {record['expression']}" for record in cases
                    if not all(record['reproduces'].values())]
    agreeing = [f"{record['entry']}: {record['probe']}" for record in probes
                if record.get('agrees') or record.get('error')]
    for record in cases:
        print(f"{record['expression']:24s} selka {record['observed']['selka']:>6s}  "
              f"cpython {record['observed']['cpython']:>6s}  "
              f"{'reproduces' if all(record['reproduces'].values()) else 'DOES NOT REPRODUCE'}")
    for record in probes:
        if record.get('error'):
            print(f"{record['probe']:24s} {record['error']}")
        else:
            print(f"{record['probe']:24s} selka {record['selka']['status']} "
                  f"{record['selka']['value']!r}  cpython {record['cpython']['status']} "
                  f"{record['cpython']['stdout']!r}  "
                  f"{'agrees' if record['agrees'] else 'diverges as declared'}")

    if not args.check_only:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(document, indent=1) + '\n')
        print(f'divergence_evidence.py: wrote {args.out}')

    if unreproduced:
        print('divergence_evidence.py: declared values did not reproduce: '
              + ', '.join(unreproduced), file=sys.stderr)
        return 1
    if agreeing:
        print('divergence_evidence.py: a claimed probe no longer diverges: '
              + ', '.join(agreeing), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
