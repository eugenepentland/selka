#!/usr/bin/env python3
"""Fold a friction log into repair rounds per diagnostic code and per idiom.

A log is the `friction-log-v1` JSON-line file the compiler appends when a
command was given `--friction-log=PATH` (or `MYLANG_FRICTION_LOG=PATH`): one
record per command, carrying the compiler's build identity, the command, the
source path as typed, the source snapshot hash, each diagnostic's code,
severity and byte span, the exit status and the command's wall time.

A **repair round** is evidence that an error cost a command: a failing record
for a file, carrying an error-severity diagnostic code, followed within the
next `--window` records *for that same file* by a record whose status is a
passing check. Each (failing record, error code) pair counts at most once, so a
single repair that clears two codes is two rounds, one per code. Warnings never
seed a round (they do not block a check) and a passing record never seeds one
(it is the fix, not the friction). A fix that is never re-checked is not
counted: the log has no evidence for it. Every code the log observed is listed,
with zero rounds when no passing check followed it, because a code reported
often and repaired without a round is free rather than friction.

Idioms. `velocity/friction/classifier.json` maps (code, source regex) to an
idiom, but a record deliberately carries no source text, so only classifier rows
that need no source -- a wildcard regex such as "." -- can name a harvested
round. Codes the classifier cannot name without source fall back to
CODE_ONLY_IDIOMS below, a code-only extension documented in README.md; any code
in neither place is reported as `unclassified` rather than guessed at, because
one code can cover several idioms (an `E_SYNTAX` record may be a union comma, a
chained assignment or a comprehension, and only the source tells them apart).

Usage:
    harvest.py LOG [--json] [--top N] [--window N] [--classifier PATH]
"""

import argparse
import json
from pathlib import Path
import sys

VERSION = 'friction-harvest-v1'
DEFAULT_CLASSIFIER = Path(__file__).with_name('classifier.json')

# Default look-ahead, in records for the same file. The 2026-09-20 session in
# `session-2026-09-20.jsonl` shows every repair taking one or two commands
# (edit, check, fix, check), so five covers a repair that also runs or tests in
# between while bounding false credit: a passing check more than five same-file
# commands later is more likely a different repair. Records for other files do
# not consume the window. Raise it for sessions with long edit/build loops.
DEFAULT_WINDOW = 5

# Code-only idiom names for codes whose classifier rows all need source text.
# This is the harvested-log half of classifier.json: a record has a code and a
# span, never source, so these names must be true of every source that produces
# the code. The classifier's owner should absorb this table into classifier.json
# (see README.md); it lives here only because the log format is pinned first.
CODE_ONLY_IDIOMS = {
    'E_ARITY': 'call-arity',
    'E_MODULE_HEADER': 'module-header',
    'E_TYPE': 'type-mismatch',
    'E_LAMBDA_CAPTURE': 'lambda-capture',
    'E_UNBOUND': 'unbound-name',
    'E_UNKNOWN_FUNCTION': 'unknown-function',
    'E_EXPLICIT_DISCARD_REQUIRED': 'discarded-result',
    'W_UNUSED_BINDING': 'unused-binding',
}


def source_free_idioms(classifier_path):
    """Return {code: idiom} for classifier rows that match any source text.

    A code qualifies only when every row for it is a wildcard row with the same
    idiom, so the answer is what the classifier would return for any source. A
    code with one source-dependent row is left out: without source there is no
    honest choice between its idioms.
    """
    document = json.loads(Path(classifier_path).read_text())
    rows = {}
    for rule in document.get('rules', []):
        rows.setdefault(rule.get('code', ''), []).append((rule.get('regex', ''), rule.get('idiom', 'unclassified')))
    named = {}
    for code, code_rows in rows.items():
        wildcards = {idiom for regex, idiom in code_rows if regex in ('', '.', '.*')}
        if len(wildcards) == 1 and all(regex in ('', '.', '.*') for regex, _ in code_rows):
            named[code] = wildcards.pop()
    return named


def idiom_for(code, classifier):
    """Answer (idiom, source) for a code: classifier, the code-only extension,
    or `unclassified` when naming it would need source text the log lacks."""
    if code in classifier:
        return classifier[code], 'classifier'
    if code in CODE_ONLY_IDIOMS:
        return CODE_ONLY_IDIOMS[code], 'code-only'
    return 'unclassified', 'unclassified'


def read_records(path):
    """Read a JSON-line log, returning (records, skipped_lines).

    A truncated or corrupt line is skipped and counted rather than aborting the
    harvest: a killed compiler can leave one, and one bad line must not hide
    every other record in the log.
    """
    records, skipped = [], 0
    for line in Path(path).read_text().splitlines():
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            skipped += 1
            continue
        if not isinstance(record, dict):
            skipped += 1
            continue
        records.append(record)
    return records, skipped


def error_codes(record):
    """The distinct error-severity codes a failing record carried, in order."""
    codes = []
    for finding in record.get('diagnostics', []):
        if not isinstance(finding, dict) or finding.get('severity') != 'error':
            continue
        code = finding.get('code')
        if isinstance(code, str) and code not in codes:
            codes.append(code)
    return codes


def record_path(record):
    """The source path exactly as the solver typed it."""
    invocation = record.get('invocation')
    return invocation.get('path', '') if isinstance(invocation, dict) else ''


def record_command(record):
    """The command spelling a record was written for."""
    invocation = record.get('invocation')
    return invocation.get('command', '') if isinstance(invocation, dict) else ''


def harvest(records, window):
    """Fold records into repair rounds.

    Rounds are attributed in log order and grouped per file, so an unrelated
    file's commands never consume a window. Returns (rounds, uncoded_failures),
    where each round names the file, code, seeding record and passing record.
    """
    files = {}
    for index, record in enumerate(records):
        files.setdefault(record_path(record), []).append((index, record))
    rounds, uncoded = [], 0
    for path, entries in files.items():
        for position, (index, record) in enumerate(entries):
            if record.get('status', 0) == 0:
                continue
            codes = error_codes(record)
            if not codes:
                uncoded += 1
                continue
            passing = next((later for _, later in entries[position + 1:position + 1 + window]
                            if later.get('status', 0) == 0), None)
            if passing is None:
                continue
            for code in codes:
                rounds.append({'path': path, 'code': code, 'record': index,
                               'command': record_command(record), 'passed': record_command(passing)})
    return rounds, uncoded


def tally(records, rounds, classifier, top):
    """Count rounds per code and per idiom, sorted by rounds then name.

    Every code the log observed appears, including codes that earned no round,
    because "reported twice, never repaired" is itself ranking input: a code
    with many observations and zero rounds is free to fix, not friction.
    """
    counted, seen = {}, {}
    for round_ in rounds:
        counted[round_['code']] = counted.get(round_['code'], 0) + 1
    for record in records:
        for finding in record.get('diagnostics', []):
            code = finding.get('code') if isinstance(finding, dict) else None
            if isinstance(code, str):
                seen[code] = seen.get(code, 0) + 1
    code_rows = []
    for code in sorted(set(counted) | set(seen), key=lambda name: (-counted.get(name, 0), name)):
        idiom, source = idiom_for(code, classifier)
        code_rows.append({'code': code, 'rounds': counted.get(code, 0), 'records': seen.get(code, 0),
                          'idiom': idiom, 'idiom_source': source})
    idioms = {}
    for row in code_rows:
        idioms[row['idiom']] = idioms.get(row['idiom'], 0) + row['rounds']
    idiom_rows = [{'idiom': idiom, 'rounds': idioms[idiom]}
                  for idiom in sorted(idioms, key=lambda name: (-idioms[name], name))]
    return (code_rows[:top] if top else code_rows), (idiom_rows[:top] if top else idiom_rows)


def report(document, codes, idioms, out):
    """Render the human table beside the classifier."""
    out.write(f"friction harvest: {document['records']} records for {document['files']} files, "
              f"{document['rounds']} repair rounds (window={document['window']}, "
              f"skipped={document['skipped']}, uncoded failures={document['uncoded_failures']})\n")
    out.write('\nrepair rounds per code\n')
    out.write(f"  {'rounds':>6}  {'records':>7}  {'code':<26} {'idiom':<22} named by\n")
    for row in codes:
        out.write(f"  {row['rounds']:>6}  {row['records']:>7}  {row['code']:<26} {row['idiom']:<22} {row['idiom_source']}\n")
    out.write('\nrepair rounds per idiom\n')
    out.write(f"  {'rounds':>6}  idiom\n")
    for row in idioms:
        out.write(f"  {row['rounds']:>6}  {row['idiom']}\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('log', help='friction-log-v1 JSON-line file to fold')
    parser.add_argument('--json', action='store_true', help='emit one machine-readable document instead of tables')
    parser.add_argument('--top', type=int, default=0, metavar='N', help='show only the N largest rows per table (0 = all)')
    parser.add_argument('--window', type=int, default=DEFAULT_WINDOW, metavar='N',
                        help=f'records to look ahead within one file (default {DEFAULT_WINDOW})')
    parser.add_argument('--classifier', default=str(DEFAULT_CLASSIFIER), metavar='PATH',
                        help='idiom classifier to read (default velocity/friction/classifier.json)')
    arguments = parser.parse_args(argv)
    if arguments.window < 1:
        parser.error('--window must be at least 1: a round needs a later passing record')
    if arguments.top < 0:
        parser.error('--top cannot be negative')
    records, skipped = read_records(arguments.log)
    classifier = source_free_idioms(arguments.classifier)
    rounds, uncoded = harvest(records, arguments.window)
    codes, idioms = tally(records, rounds, classifier, arguments.top)
    document = {'version': VERSION, 'records': len(records), 'skipped': skipped,
                'files': len({record_path(record) for record in records}), 'window': arguments.window,
                'rounds': len(rounds), 'uncoded_failures': uncoded, 'by_code': codes, 'by_idiom': idioms}
    if arguments.json:
        json.dump(document, sys.stdout, indent=2)
        sys.stdout.write('\n')
    else:
        report(document, codes, idioms, sys.stdout)
    return 0


if __name__ == '__main__':
    sys.exit(main())
