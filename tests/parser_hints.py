#!/usr/bin/env python3
"""Check the parser's hint table against the friction classifier, and the hints
against the compiler that prints them.

Two tables describe the same declaration forms: ``declaration_hints`` in
``src/parser.zig``, which decides the message and the accepted spelling the
parser prints, and the ``hints`` array plus the ``E_SYNTAX`` rows of
``velocity/friction/classifier.json``, which decides the idiom the suite files
the shape under. They are one table: a form present in one and absent from the
other is a failure here.

Without ``--compiler`` this is a static agreement check (no build needed).
With ``--compiler PATH`` it also runs one probe per hinted form plus the
headerless-script shape, so the messages, spans and exit statuses are checked
against the shipped compiler.
"""
import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PARSER = ROOT / 'src' / 'parser.zig'
CLASSIFIER = ROOT / 'velocity' / 'friction' / 'classifier.json'
PROBES = ROOT / 'velocity' / 'suites' / 'idioms'
TIMEOUT = 120

# The table row shape, one row per line: the test fails loudly when the table is
# reformatted rather than silently comparing nothing.
ROW = re.compile(
    r'\.form = \.(\w+), \.idiom = "([^"]+)", '
    r'\.message = "([^"]*)", \.accepted = "([^"]*)"')

# One shape per hinted idiom, with the source that must classify as that idiom.
CLASSIFY_CASES = [
    ('module-constant', 'E_SYNTAX', PROBES / 'a37_const.selka'),
    ('method', 'E_SYNTAX', PROBES / 'a38_class_methods.selka'),
    ('from-import', 'E_SYNTAX', PROBES / 'a39_dataclass.selka'),
    ('chained-assign', 'E_SYNTAX', PROBES / 'a10_chained_assign.selka'),
    ('exceptions', 'E_SYNTAX', PROBES / 'a40_try_except.selka'),
    ('match-literal', 'E_SYNTAX', PROBES / 'a49_match_literal.selka'),
    ('del', 'E_SYNTAX', PROBES / 'a51_del.selka'),
    ('string-prefix', 'E_SYNTAX', PROBES / 'a53_multiline_str.selka'),
    ('main-guard', 'E_SYNTAX', PROBES / 'a58_main_guard.selka'),
    ('option-unwrap', 'E_SYNTAX', PROBES / 'a61_result_unwrap.selka'),
    ('walrus', 'E_SYNTAX', PROBES / 'a73_while_else_walrus.selka'),
]

# The same shapes, with the location the rejected token keeps and the accepted
# spelling the note must name. The spans are the ones the former bare
# expectation messages reported.
PROBE_CASES = [
    ('module-constant', 'E_SYNTAX', 'a37_const.selka', 2, 1),
    ('method', 'E_SYNTAX', 'a38_class_methods.selka', 3, 5),
    ('from-import', 'E_SYNTAX', 'a39_dataclass.selka', 2, 1),
    ('chained-assign', 'E_SYNTAX', 'a10_chained_assign.selka', 3, 11),
    ('exceptions', 'E_SYNTAX', 'a40_try_except.selka', 3, 8),
    ('match-literal', 'E_SYNTAX', 'a49_match_literal.selka', 5, 14),
    ('match-literal', 'E_SYNTAX', 'a50_match_str.selka', 4, 14),
    ('del', 'E_SYNTAX', 'a51_del.selka', 4, 9),
    ('string-prefix', 'E_SYNTAX', 'a53_multiline_str.selka', 5, 10),
    ('main-guard', 'E_SYNTAX', 'a58_main_guard.selka', 5, 1),
    ('option-unwrap', 'E_SYNTAX', 'a61_result_unwrap.selka', 10, 21),
    ('walrus', 'E_SYNTAX', 'a73_while_else_walrus.selka', 4, 11),
]

HEADERLESS = """import strings

func main() -> int:
    match strings.ord("m"):
        case Ok(value):
            return value - 67
        case Err(_):
            return 1
"""


def hint_table():
    """The parser's hinted forms as (form, idiom, message, accepted) rows."""
    text = PARSER.read_text()
    start = text.find('pub const declaration_hints')
    if start < 0:
        raise SystemExit('src/parser.zig no longer declares `declaration_hints`')
    end = text.find('\n};', start)
    if end < 0:
        raise SystemExit('the `declaration_hints` table has no closing `};`')
    rows = ROW.findall(text[start:end])
    if not rows:
        raise SystemExit('the `declaration_hints` table parsed to zero rows')
    return rows


def classifier():
    """The classifier's hints list and its rules, in file order."""
    document = json.loads(CLASSIFIER.read_text())
    return document.get('hints', []), document['rules']


def classify(source, code, rules):
    """The idiom the first matching rule files this source under."""
    for rule in rules:
        if rule['code'] != code:
            continue
        if re.search(rule['regex'], source, re.MULTILINE):
            return rule['idiom']
    return 'unclassified'


def check_tables(verbose):
    """Assert the two tables name the same forms, with rules behind each."""
    rows = hint_table()
    hints, rules = classifier()
    failures = []
    if [row[1] for row in rows] != list(hints):
        failures.append(
            f'parser idioms {[row[1] for row in rows]} != '
            f'classifier hints {list(hints)}')
    for _, idiom, message, accepted in rows:
        if not message or not accepted:
            failures.append(f'{idiom}: empty message or accepted spelling')
        if not any(rule['code'] == 'E_SYNTAX' and rule['idiom'] == idiom
                   for rule in rules):
            failures.append(f'{idiom}: no E_SYNTAX rule in the classifier')
    for idiom, code, path in CLASSIFY_CASES:
        source = path.read_text()
        observed = classify(source, code, rules)
        if observed != idiom:
            failures.append(f'{idiom}: the classifier answers {observed!r}')
        elif verbose:
            print(f'classified {idiom:16s} from {path.name}')
    if failures:
        for failure in failures:
            print(f'table disagreement: {failure}', file=sys.stderr)
        return 1
    print(f'hint table and classifier agree on {len(rows)} forms')
    return 0


def compiler_failures(compiler, accepted):
    """Run the four probes and the headerless script; report every mismatch."""
    failures = []
    for idiom, code, name, line, column in PROBE_CASES:
        result = subprocess.run(
            [str(compiler), 'check', str(PROBES / name)],
            capture_output=True, text=True, timeout=TIMEOUT)
        stderr = result.stderr
        if result.returncode != 1:
            failures.append(f'{name}: exit {result.returncode}, expected 1')
        if f'error[{code}]' not in stderr:
            failures.append(f'{name}: no error[{code}] in the diagnostic')
        if f'{name}:{line}:{column}:' not in stderr:
            failures.append(f'{name}: no {line}:{column} location in the diagnostic')
        note = [part.strip() for part in stderr.splitlines()
                if part.strip().startswith('alternative:')]
        if not note or not note[0].endswith(accepted[idiom]):
            failures.append(f'{name}: alternative note {note} does not name {accepted[idiom]!r}')
    with tempfile.TemporaryDirectory() as work:
        enum = Path(work) / 'enum_cases.selka'
        enum.write_text('enum Event:\n    heartbeat\n    count(value: int)\n')
        result = subprocess.run(
            [str(compiler), 'check', str(enum)],
            capture_output=True, text=True, timeout=TIMEOUT)
        if result.returncode != 0:
            failures.append('enum_cases.selka: newline enum cases should parse and check')
        script = Path(work) / 'probe4.selka'
        script.write_text(HEADERLESS)
        checked = subprocess.run(
            [str(compiler), 'check', str(script)],
            capture_output=True, text=True, timeout=TIMEOUT)
        if checked.returncode != 0:
            failures.append(f'headerless script: check exit {checked.returncode}: {checked.stderr.strip()}')
        ran = subprocess.run(
            [str(compiler), 'run', str(script), '--print-result'],
            capture_output=True, text=True, timeout=TIMEOUT)
        if ran.stdout.strip() != '42' or ran.returncode != 42:
            failures.append(f'headerless script: stdout {ran.stdout.strip()!r} exit {ran.returncode}, expected 42/42')
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path)
    parser.add_argument('--verbose', action='store_true')
    args = parser.parse_args()
    status = check_tables(args.verbose)
    if args.compiler is None:
        return status
    accepted = {idiom: accepted for _, idiom, _, accepted in hint_table()}
    failures = compiler_failures(args.compiler.resolve(), accepted)
    for failure in failures:
        print(f'compiler disagreement: {failure}', file=sys.stderr)
    if failures:
        return 1
    print('probes print the hinted message, span and accepted spelling')
    return status


if __name__ == '__main__':
    sys.exit(main())
