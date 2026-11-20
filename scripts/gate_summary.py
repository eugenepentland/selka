#!/usr/bin/env python3
"""Read a gate log and print the short summary an agent can afford.

This is a reader, never a second gate: it runs nothing, changes no verdict and
publishes no evidence. `verify_cache.py` uses it to summarise the complete
verification; `python3 scripts/gate_summary.py LOG` does the same for a log left
by a plain `zig build test --summary all`.
"""
import argparse
import re
from pathlib import Path
import sys

MAX_GREEN_LINES = 30
MAX_RED_LINES = 60
MAX_RED_PER_FAILURE = 10
MAX_LOG_BYTES = 16 * 1024 * 1024
# Between two files of one gate run in the text `read_logs` returns: a line of its own, a form feed, which no log has.
LOG_BOUNDARY = b'\n\x0c\n'
# The two files one gate step leaves, in the order they are read: the build runner's report is in standard error.
STEP_LOGS = ('stderr.log', 'stdout.log')

ACTION = re.compile(r'--action-id ([A-Za-z0-9_.-]+)')
STEP = re.compile(r'verification action ([A-Za-z0-9_.-]+) member')
FILE_LINE = re.compile(r'((?:[A-Za-z0-9_.+/-]+/)?[A-Za-z0-9_.+-]+\.(?:zig|py|selka|sh|zon)):([0-9]+)')
DEADLINE = re.compile(r'test deadline: .+ ran [0-9.]+ s \(limit [0-9.]+ s\); killed')
FAILURE = re.compile(r'(?:\berror:|\bpanic:|\bFAILED\b|\bFAIL\b|\bassertion\b|\bexpected\b|Error\b|\bcrash\b)')
TEST_FAILED = re.compile(r"error: '([^']+)' (?:failed|timed out|leaked|logged)")
PYTHON_FRAME = re.compile(r'File "([^"]+)", line ([0-9]+)')
TOOLCHAIN_PATH = re.compile(r'/(?:zig-toolchains|lib/std|lib/compiler|lib/python[0-9.]*)/')
REPOSITORY_ROOTS = ('src/', 'test/', 'tests/', 'scripts/', 'selfhost/', 'bench/', 'benchmarks/',
                    'examples/', 'docs/', 'experiments/', 'velocity/')
# The line `verify_cache.py --fail-fast` writes before the failure blocks it adds to the log of a build it ended. It starts as the
# build runner's own `Build Summary:` line does, which both this reader and its Selka port (`tools/selka/gate_summary.selka`) take
# as the end of what came before, so the killed build's output is no part of any block; it names no step counts, so no verdict.
FAIL_FAST_MARKER = 'Build Summary: ended by --fail-fast at the first failing step; its failures follow'
MAX_BLOCK_LINES = 400
MAX_LEFTOVER_LINES = 24
ZIG_FRAME = re.compile(r':[0-9]+:[0-9]+: 0x[0-9a-f]+ in ')
BUILD_SUMMARY = re.compile(r'Build Summary: ([0-9]+)/([0-9]+) steps succeeded')
# A failed member as the build runner's tree marks it, in its live failure report and in the closing summary: `failure`, or
# test counts with a failed, crashed or timed-out test. The marker, not a `failed command:` line, says a step failed.
FAILED_MEMBER = re.compile(r'verification action ([A-Za-z0-9_.-]+) member [0-9]+ (?:failure\b|.*\b[1-9][0-9]* '
                           r'(?:fail|failed|crash|crashed|timeout|timed out|leak|leaked)\b)')
# Any other failed step in the tree (a compile, an install): its name, then `failure` or an error count.
FAILED_STEP = re.compile(r'^[\s|+`\\-]*([A-Za-z][^|+`]*?) (?:failure|[0-9]+ errors?)$')
GREEN_MEMBER = re.compile(r'verification action [A-Za-z0-9_.-]+ member [0-9]+ success\b')
STEP_DEADLINE = re.compile(r'step deadline: .+ ran [0-9.]+ s \(limit [0-9.]+ s\); killed')
SCRIPT = re.compile(r'(?:^|\s)((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.(?:py|sh|selka))(?=\s|$)')
WRAPPERS = ('scripts/quiet-driver.sh', 'scripts/verification_native_telemetry.py')
MAX_TAIL_LINES = 3


def doc_coverage_findings(text):
    """`selka doc-coverage` prints its failures (`  ! slug: ...`) to standard output, outside the step's block."""
    return [line.strip() for line in text.splitlines() if line.strip().startswith('! ')]


def guardian_findings(text):
    """Guardian streams its report before the build runner's block; its blocking findings are the `- path: ...` items
    after `guardian: failures grouped by check`, each with the check named above it."""
    found, group, inside = [], None, False
    for line in text.splitlines():
        if line.startswith('guardian: failures grouped by check'):
            inside = True
            continue
        if not inside:
            continue
        heading = re.match(r'^  ([a-z0-9-]+) \([0-9]+ findings?\)$', line)
        item = re.match(r'^    - (\S+?): (.+)$', line)
        if heading:
            group = heading.group(1)
        elif item and group:
            found.append('%s: %s: %s' % (item.group(1), group, item.group(2)))
        elif not line.startswith('      '):
            inside = False
    return found


def guest_test_findings(text):
    """`selka test --json` prints its verdicts (`native-tests-v1`) to standard output: each failed test, its reason and
    its place."""
    import json
    found = []
    for line in text.splitlines():
        if not line.startswith('{"version":"native-tests-v1"'):
            continue
        try:
            tests = json.loads(line).get('tests', [])
        except ValueError:
            continue
        for test in tests:
            if isinstance(test, dict) and test.get('status') not in ('passed', 'cached', 'skipped', None):
                found.append('test %s %s: %s%s' % (test.get('name'), test.get('status'), test.get('reason') or '',
                                                   ' at ' + test['at'] if test.get('at') else ''))
    return found


# Actions whose command prints its findings outside its block in the build log.
LOG_FINDINGS = {'doc-coverage': doc_coverage_findings, 'guardian': guardian_findings,
                'language': guest_test_findings, 'guest': guest_test_findings, 'language_guard': guest_test_findings}
EXITED = re.compile(r'error: process exited with code [0-9]+$')
PATH_FIRST = re.compile(r'^-?\s*((?:[A-Za-z0-9_.+-]+/)+[A-Za-z0-9_.+-]+\.[A-Za-z]+): ')
VERIFICATION = re.compile(r'verification: (PASS|FAIL|PARTIAL)\b')
STEP_SECONDS = re.compile(r'verification action ([A-Za-z0-9_.-]+) member [0-9]+ success ([0-9]+(?:\.[0-9]+)?)(m?s)')


def log_order(path):
    """The gate's own logs first, standard error before standard output."""
    parts = path.parts
    return ('gate' not in parts, path.name != 'stderr.log', str(path))


def read_logs(directory, limit=MAX_LOG_BYTES):
    """Join the bounded logs of one gate run, searched recursively.

    The coordinator keeps them as `last-logs/{gate,inventory,preparation}/
    {stderr,stdout}.log`; the build runner's failure report is in the gate's
    standard error, so that file is read first.
    """
    chunks = []
    remaining = limit
    for path in sorted(Path(directory).rglob('*.log'), key=log_order):
        try:
            data = path.read_bytes()[:remaining]
        except OSError:
            continue
        chunks.append(data)
        remaining -= len(data)
        if remaining <= 0:
            break
    return LOG_BOUNDARY.join(chunks).decode('utf-8', 'replace')


def read_step_logs(path, limit=MAX_LOG_BYTES):
    """Join the pair of logs one gate step left beside `path`, standard error first.

    A green gate prints its `Build Summary` to `stderr.log` and nothing that names a verdict to `stdout.log`, so the
    file a person points at (usually `stdout.log`) cannot say whether the run passed; its partner can.
    """
    chunks = []
    remaining = limit
    for name in STEP_LOGS:
        try:
            data = (path.parent / name).read_bytes()[:remaining]
        except OSError:
            continue
        chunks.append(data)
        remaining -= len(data)
        if remaining <= 0:
            break
    return b'\n'.join(chunks).decode('utf-8', 'replace')


def seconds(count, unit):
    value = float(count)
    return value / 1000 if unit == 'ms' else value


def step_seconds(text):
    """Per-action seconds when the log kept the `--summary all` step lines."""
    totals = {}
    for name, count, unit in STEP_SECONDS.findall(text):
        totals[name] = totals.get(name, 0.0) + seconds(count, unit)
    return sorted(totals.items(), key=lambda row: row[1], reverse=True)


def report_failures(report):
    """Failing and timed-out tests of actions this request executed."""
    failures = []
    for row in report.get('actions', []):
        if row.get('state') not in ('execute', 'fresh'):
            continue
        for telemetry in row.get('test_telemetry', []):
            for test in telemetry.get('tests', []):
                if test.get('state') in ('failed', 'timed_out'):
                    failures.append((row['id'], test['test_id'], test['state']))
    return failures


def report_seconds(report):
    """Recorded test-interval seconds per executed action, slowest first."""
    totals = {}
    for row in report.get('actions', []):
        total = 0
        for telemetry in row.get('test_telemetry', []):
            total += sum(test.get('elapsed_ns') or 0 for test in telemetry.get('tests', []))
        if total:
            totals[row['id']] = total / 1e9
    return sorted(totals.items(), key=lambda row: row[1], reverse=True)


def repository_path(path):
    """Shorten a worktree's absolute path to its repository-relative form."""
    if not path.startswith('/'):
        return path
    for root in REPOSITORY_ROOTS:
        index = path.find('/' + root)
        if index >= 0:
            return path[index + 1:]
    return path


def location(lines):
    """The first `file:line` inside the repository, skipping toolchain frames."""
    for line in lines:
        for pattern in (FILE_LINE, PYTHON_FRAME):
            for match in pattern.finditer(line):
                path, number = match.groups()
                if TOOLCHAIN_PATH.search(path):
                    continue
                return '%s:%s' % (repository_path(path), number)
    return None


def command_script(command):
    """The script a failed command runs, past the driver wrapper: `scripts/check_my_format.py`, or None."""
    for match in SCRIPT.finditer(command.split('failed command:', 1)[-1]):
        if match.group(1) not in WRAPPERS:
            return match.group(1)
    return None


def block(lines, command, beacon=False):
    """Describe one failed step from the lines printed before its command.

    `beacon` marks a block `--fail-fast` copied from a failing step's beacon: it failed by construction. Any other block
    is a failure only when its lines say so (a failure pattern) or the build's tree marks its action failed
    (`failure_details`), never because it printed a `failed command:` line.
    """
    # The build runner starts a failure report with the step's tree line; what came before it belongs to other steps.
    header = max((index for index, line in enumerate(lines) if FAILED_MEMBER.search(line)), default=None)
    other = max((index for index, line in enumerate(lines) if FAILED_STEP.match(line) and not STEP.search(line)),
                default=None)
    step_label = None
    if header is not None:
        lines = lines[max(0, header - 1):]
    elif other is not None:
        # A failed step outside the registered actions (a compile of the preparation build): named by its tree line.
        step_label = FAILED_STEP.match(lines[other]).group(1).strip()
        lines = lines[other:]
    action = ACTION.search(command)
    tests = []
    deadline = None
    diagnostics = []
    echo = 0
    for line in lines:
        text = line.strip()
        if ZIG_FRAME.search(text):
            echo = 2  # a Zig trace frame is followed by its source line and caret
            continue
        if echo:
            echo -= 1
            continue
        named = TEST_FAILED.search(text)
        if named:
            if named.group(1) not in tests:
                tests.append(named.group(1))
            continue
        if DEADLINE.search(text):
            deadline = deadline or text
            continue
        if text.startswith('test:'):
            continue
        if STEP_DEADLINE.search(text):
            deadline = deadline or text
            continue
        if FAILURE.search(text) and text not in diagnostics:
            diagnostics.append(text)
    if action is None and header is not None:
        # The failed member itself, not the parent above it in the tree (`verify-ir-proof` waits on `language`).
        action = FAILED_MEMBER.search(lines[min(1, len(lines) - 1)]) or FAILED_MEMBER.search(lines[0])
    if action is None:
        for line in lines:
            step = STEP.search(line)
            if step:
                action = step
                break
    if diagnostics and all(OVERSHOOT.search(line) for line in diagnostics) and not (tests or deadline or beacon):
        diagnostics = []  # a peak over the declared memory bound alone fails no step (`memory_overshoots`)
    found = {'action': action.group(1) if action else 'unknown', 'tests': tests,
             'deadline': deadline, 'lines': diagnostics, 'location': location(lines),
             'script': command_script(command), 'beacon': beacon, 'step': step_label,
             'green': header is None and any(GREEN_MEMBER.search(line) for line in lines),
             'failed': bool(tests or deadline or diagnostics or beacon)}
    # The step's own lines: what a summary shows when nothing matches a failure pattern (`formatting differs`), and
    # the lines naming a file (Guardian's `- src/x.zig: ...`) that come before the build runner's exit line.
    found['plain'] = plain_lines(lines)
    return found


def shown_lines(found):
    """A failed block's diagnostic lines in the order a summary shows them: its failure lines, then the lines that
    name a file, then the build runner's `process exited` line; at most MAX_TAIL_LINES."""
    errors = [line for line in found['lines'] if not EXITED.match(line)]
    named = [line for line in found.get('plain', []) if FILE_LINE.search(line) or PATH_FIRST.match(line)]
    # A command whose findings are printed outside its block (doc-coverage's standard output, Guardian's report).
    named = found.get('elsewhere', []) + named
    if not errors and not named:
        named = found.get('plain', [])
    shown = []
    for line in errors + named + [line for line in found['lines'] if EXITED.match(line)]:
        if line not in shown:
            shown.append(line)
    return shown[:MAX_TAIL_LINES]


def plain_lines(lines):
    """A failed step's own output when nothing in it matches a failure pattern: lines that name a file first, then the
    rest, without the build runner's tree, wrapper chatter and trace frames."""
    kept = []
    for line in lines:
        text = line.strip()
        if (not text or text.startswith(('+-', '|', '`-', 'test:', 'build-slot:', 'Build Summary'))
                or ZIG_FRAME.search(text) or text == '^' or re.fullmatch(r'verification-[A-Za-z0-9_.-]+', text)):
            continue
        if text not in kept:
            kept.append(text)
    located = [text for text in kept if FILE_LINE.search(text) or PATH_FIRST.match(text)]
    return (located + [text for text in kept if text not in located])[:MAX_TAIL_LINES]


def failure_details(text):
    """Extract one bounded diagnostic block per failed command in a build log.

    The pinned build runner prints a failing step's header, its captured standard
    error and its `error:` lines first, and the `failed command:` line last, so a
    step's block is what was printed since the previous failed command or build
    summary. A green step writes nothing, so it prints no block.
    """
    blocks = []
    pending = []
    beacons = False
    for line in text.splitlines():
        if line.startswith('failed command:'):
            blocks.append(block(pending, line, beacon=beacons))
            pending = []
        elif line.startswith('Build Summary:'):
            pending = []
            beacons = line.startswith(FAIL_FAST_MARKER)
        else:
            pending.append(line)
            if len(pending) > MAX_BLOCK_LINES:
                del pending[0]
    marked = failed_actions(text)
    for found in blocks:
        if found.get('green') and not found['beacon']:
            # Its own member line says `success`: a green step that wrote to standard error.
            found['failed'] = False
            continue
        if not found['failed'] and found['action'] in marked:
            # The tree marks this action failed although its lines match no failure pattern (`formatting differs`).
            found['failed'] = True
        elif found['failed'] and marked and not found['beacon'] and found['action'] not in marked \
                and found['action'] != 'unknown' and not (found['tests'] or found['deadline']):
            # Its lines look like a failure, but the tree marks other actions failed and this one not: a green step
            # that wrote to standard error (its `failed command:` line is printed all the same).
            found['failed'] = False
    return [found for found in blocks if found['failed']]


OVERSHOOT = re.compile(r'error: memory usage peaked at ([0-9.]+[KMG]?B) \([0-9]+ bytes\), exceeding the declared upper '
                       r'bound of ([0-9.]+[KMG]?B)')
MEMBER_MARK = re.compile(r'verification action ([A-Za-z0-9_.-]+) member ([0-9]+) ')


def memory_overshoots(text):
    """Members whose only failure is a peak over their declared `max_rss`: the build runner marks them `failure` in its
    tree but counts them as succeeded and exits 0, so they fail nothing. [(action, member, peak, bound)] in order."""
    found = []
    lines = text.splitlines()
    for index, line in enumerate(lines):
        mark = MEMBER_MARK.search(line)
        if not mark or not FAILED_MEMBER.search(line):
            continue
        rest = [item.strip() for item in lines[index + 1:index + 4] if item.strip()]
        overshoot = OVERSHOOT.search(rest[0]) if rest else None
        if overshoot and (len(rest) < 2 or rest[1].startswith('failed command:') or not rest[1].startswith('error:')):
            item = (mark.group(1), int(mark.group(2)), overshoot.group(1), overshoot.group(2))
            if item not in found:
                found.append(item)
    return found


def failed_actions(text):
    """The actions the build runner's tree marks failed, in the order it first names them, without the members whose
    only failure is a memory overshoot (`memory_overshoots`: the build does not fail those)."""
    overshot = {(action, member) for action, member, _peak, _bound in memory_overshoots(text)}
    names = []
    for line in text.splitlines():
        match = FAILED_MEMBER.search(line)
        mark = MEMBER_MARK.search(line)
        if not match or (mark and (mark.group(1), int(mark.group(2))) in overshot):
            continue
        if match.group(1) not in names:
            names.append(match.group(1))
    return names


def failed_steps(text):
    """Other steps the tree marks failed (a compile, an install), by name, in order."""
    names = []
    for line in text.splitlines():
        if STEP.search(line):
            continue
        match = FAILED_STEP.match(line)
        if match and 'transitive failure' not in line and match.group(1) not in names:
            names.append(match.group(1).strip())
    return names


def error_lines(text):
    """The build log's own `error:` lines and file:line diagnostics, outside any failure block, first few."""
    found = []
    for line in text.splitlines():
        stripped = line.strip()
        if (stripped.startswith('error:') or ': error:' in stripped) and stripped not in found:
            found.append(stripped)
        if len(found) >= MAX_TAIL_LINES:
            break
    return found


def tail_lines(text):
    """The last non-empty lines of a log, for a failure nothing else names."""
    return [line.strip()[:400] for line in text.splitlines() if line.strip()][-MAX_TAIL_LINES:]


def leftover_report(text):
    """What the supervisor of an action said when it ended 125 (incomplete), one line each, or [].

    An action whose steps all pass can still end 125: something it started was still running two seconds after it
    finished (`verification_process._report_leftovers`), or the supervisor itself failed (`_report_failure`). No step
    fails, so without these lines the log names nothing; with them the failure is a process (pid, parent, session,
    start, directory and command) or an exception and where it was raised.

    The supervisor wraps the whole build and reports when the build has ended, so its lines come after the build's last
    summary. A `supervisor:` line before it is output of the build: the supervisor of a test that runs one of its own,
    quoted in that test's failure message (the nightly of 15 November took one for a process that outlived its action,
    and skipped the flaky rerun for a helper its test had already killed). The rule holds per file of the joined logs
    (`read_logs` separates them with LOG_BOUNDARY); a log in which no file has a summary is read whole.
    """
    files = text.split(LOG_BOUNDARY.decode())
    summarized = any(BUILD_SUMMARY.search(file) for file in files)
    found = []
    for file in files:
        lines = file.splitlines()
        ends = [index for index, line in enumerate(lines) if BUILD_SUMMARY.search(line)]
        if summarized and not ends:
            continue
        for line in lines[ends[-1] + 1:] if ends else lines:
            if line.startswith('supervisor: ') and line not in found:
                found.append(line[:600])
    return found[:MAX_LEFTOVER_LINES]


TEST_PREFIX = re.compile(r"""prefix\s*=\s*["']([A-Za-z0-9_.-]+)["']""")


def leftover_owner(root, lines):
    """The test file whose scratch directory a leftover runs in, or None: a `supervisor: leftover` line names the
    process's directory (`cwd=`), and a test makes its directory with a `prefix=` of its own (`slot-test-`, followed by
    eight random characters). That file is the test to blame for a process that outlived its action."""
    for line in lines:
        directory = re.search(r' cwd=(\S+)', line)
        if not directory:
            continue
        for part in directory.group(1).split('/'):
            prefix = re.fullmatch(r'(.+?-)[a-z0-9_]{8}', part)
            if not prefix:
                continue
            for path in sorted(Path(root).glob('scripts/*_test.py')) + sorted(Path(root).glob('test/*.py')):
                try:
                    if prefix.group(1) in TEST_PREFIX.findall(path.read_text()):
                        return str(path.relative_to(root))
                except OSError:
                    continue
    return None


def inferred_verdict(text):
    """The verdict of joined logs: FAIL when any build summary counts a failed step or `--fail-fast` ended the gate
    (a preparation log's green summary does not outvote the gate's), PASS when every summary passed."""
    counts = BUILD_SUMMARY.findall(text)
    if any(done != total for done, total in counts) or FAIL_FAST_MARKER in text:
        return 'FAIL'
    if counts:
        return 'PASS'
    match = VERIFICATION.search(text)
    return match.group(1) if match else 'UNKNOWN'


def script_actions(plan):
    """Each script a gate action's declared inputs name, mapped to those actions (from the coordinator's inventory)."""
    owners = {}
    for group in (plan or {}).get('groups', []):
        for entry in group.get('inputs', []):
            if entry.endswith(('.py', '.sh', '.selka')):
                owners.setdefault(entry, []).append(group['id'])
    return owners


def step_name(found, owners, executed=None):
    """What a failed block is called: its action; for a beacon of a driver, the action whose inputs name its script
    (`my_format (scripts/check_my_format.py)`), among those this request executed when that is known; else the
    script itself."""
    if found['action'] != 'unknown':
        return found['action']
    if found.get('step'):
        return found['step']
    script = found.get('script')
    if script is None:
        return 'unknown step'
    candidates = owners.get(script, [])
    if executed is not None and any(name in executed for name in candidates):
        candidates = [name for name in candidates if name in executed]
    if len(candidates) == 1:
        return '%s (%s)' % (candidates[0], script)
    if candidates:
        return '%s (%s)' % (' or '.join(candidates[:3]), script)
    return script


def unnamed_failure(report, text):
    """Lines for a failed run in which no step's block was found: what the tree, the report and the log do say."""
    marked = failed_actions(text)
    if marked:
        return ['failure: the build marks %s failed; its own output is not in the log' % ', '.join(marked[:6])]
    steps = failed_steps(text)
    if steps:
        return (['failure: the build step %s failed' % ', '.join(steps[:3])]
                + ['  ' + line[:400] for line in error_lines(text)])
    report = report or {}
    status = report.get('status')
    timed_out = [event for event in report.get('admissions', []) if event.get('timed_out')]
    if timed_out:
        limit = (timed_out[-1].get('execution_limits') or {}).get('timeout_seconds')
        return ['failure: the %s build passed its deadline%s and was ended (status 124)' % (
            timed_out[-1].get('kind', 'gate'), '' if limit is None else ' (%s s)' % limit)]
    if status == 75:
        reasons = ((report.get('stability_diagnostics') or {}).get('reasons') or [])
        # A watched path that changed says more than a watcher closed in consequence.
        named = [reason for reason in reasons if isinstance(reason, dict) and reason.get('facet') == 'watch']
        first = named[0] if named else (reasons[0] if reasons else None)
        if isinstance(first, dict) and first.get('name') not in (None, 'None'):
            first = '%s (%s)' % (first['name'], first.get('reason', 'changed'))
        return ['failure: inputs changed while the gate ran (status 75), so no receipt was kept'
                + ('; first changed: %s' % str(first)[:300] if first else '')]
    if report.get('error'):
        return ['failure: %s stage: %s' % (report.get('stage', 'coordinator'), str(report['error'])[:400])]
    named = error_lines(text)
    if named:
        return ['failure: no step is marked failed; the log\'s error lines:'] + ['  ' + line[:400] for line in named]
    tail = tail_lines(text)
    return (['failure: no step is marked failed%s; the log ends:' % (
        '' if status is None else ' and the gate ended %s' % status)] + ['  ' + line for line in tail])


def flaky_lines(flaky):
    """What the flaky rerun did (item 4d): each test that passed alone, with its first diagnostic from the gate; or,
    when the gate still fails, which tests failed again alone and which passed."""
    if not flaky:
        return []
    if not flaky.get('rerun'):
        return ['no flaky rerun: %s' % flaky.get('reason', 'not eligible')] if flaky.get('reason') else []
    lines = []
    for row in flaky.get('tests', [])[:5]:
        if flaky.get('passed'):
            lines.append('flaky: %s %s failed in the gate and passed alone in %.1f s%s' % (
                row.get('action'), row.get('test'), row.get('seconds') or 0.0, ' (F22 signature)' if row.get('f22') else ''))
            lines += ['  ' + line[:300] for line in row.get('failure', [])[:1]]
        else:
            lines.append('rerun alone: %s %s %s' % (row.get('action'), row.get('test'),
                                                  'passed' if row.get('passed') else 'failed again'))
    if not flaky.get('passed') and flaky.get('reason'):
        lines.append('rerun alone: %s' % flaky['reason'])
    return lines


def summarize(report=None, log_directory=None, text=None, verbose=False, plan=None):
    """Return the bounded summary lines for a coordinator report or a saved log.

    A red summary always names something: each failed step with its first diagnostics, else the failed steps the build
    tree marks, the supervisor's report, a deadline, changed inputs, the coordinator's error, or the log's last lines.
    `plan`, the coordinator's inventory, names the action of a driver whose beacon carries only its command.
    """
    if text is None and log_directory is not None:
        text = read_logs(log_directory)
    text = text or ''
    blocks = failure_details(text) if text else []
    owners = script_actions(plan)
    executed = None if report is None else {row.get('id') for row in report.get('actions', [])
                                            if row.get('state') in ('execute', 'fresh')}
    for found in blocks:
        found['name'] = step_name(found, owners, executed)
        if found['action'] in LOG_FINDINGS:
            found['elsewhere'] = LOG_FINDINGS[found['action']](text)[:MAX_TAIL_LINES]
    if report is not None:
        verdict = 'PASS' if report.get('success') else 'FAIL'
        elapsed = report.get('elapsed_seconds')
        reused = sum(row.get('state') == 'reused' for row in report.get('actions', []))
        executed = sum(row.get('state') in ('execute', 'fresh') for row in report.get('actions', []))
        failures = report_failures(report) if not report.get('success') else []
        if not report.get('success'):
            # A driver or command can fail without per-test telemetry (a step over its memory bound, a failed driver);
            # the log still names its action and diagnostic lines, beside the actions whose tests failed.
            named = {action for action, _test, _state in failures}
            failures += [(found['name'], None, 'failed') for found in blocks
                         if found['name'] not in named and found['action'] not in named]
        slowest = report_seconds(report)[:3]
    else:
        verdict = inferred_verdict(text)
        elapsed = None
        reused = executed = None
        failures = [(found['name'], None, 'failed') for found in blocks] if verdict != 'PASS' else []
        slowest = [(name, value) for name, value in step_seconds(text)[:3]]
    leftovers = leftover_report(text)
    if leftovers and verdict == 'PASS':
        verdict = 'FAIL'  # a log that reports leftovers is an action that ended 125, whatever its build summary says
    lines = []
    pieces = ['verification: ' + verdict]
    if elapsed is not None:
        pieces.append('in %.1f s' % elapsed)
    if reused is not None:
        pieces.append('%d reused, %d executed' % (reused, executed))
    if report is not None and report.get('disk_wait', {}).get('seconds', 0) >= 1:
        wait = report['disk_wait']
        pieces.append('waited %.0f s for the disk%s' % (wait['seconds'], ' (gave up)' if wait.get('gave_up') else ''))
    flaky = (report or {}).get('flaky') or {}
    if flaky.get('passed'):
        pieces.append('%d flaky test(s) passed when rerun alone' % len(flaky.get('tests', [])))
    if report is not None and report.get('restarts'):
        pieces.append('restarted %d time(s): %s changed' % (len(report['restarts']), ', '.join(
            str(item.get('path')) for item in report['restarts'])))
    if log_directory is not None:
        pieces.append('log: ' + str(log_directory))
    lines.append('; '.join(pieces))
    if slowest and not failures and verdict == 'PASS':
        lines.append('slowest actions (recorded test seconds): ' + ', '.join('%s %.1f s' % row for row in slowest[:3]))
    lines += flaky_lines(flaky)
    for action, member, peak, bound in memory_overshoots(text)[:3]:
        lines.append('note: %s member %d exceeded its declared memory bound: %s against %s (the build fails no step for '
                     'it)' % (action, member, peak, bound))
    if not failures:
        if verdict == 'FAIL' and leftovers:
            lines.append('failure: an action ended 125 (incomplete) with no failing step; its supervisor reports:')
            lines += ['  ' + line for line in leftovers]
        elif verdict == 'FAIL':
            lines += unnamed_failure(report, text)
        if verdict == 'FAIL' and log_directory is not None:
            lines.append('  log: ' + str(log_directory))
        return lines[:MAX_GREEN_LINES]
    by_action = {}
    for found in blocks:
        merged = by_action.setdefault(found['name'], {'tests': [], 'lines': [], 'deadline': None, 'location': None})
        merged['tests'] += [name for name in found['tests'] if name not in merged['tests']]
        merged['lines'] += [line for line in shown_lines(found) if line not in merged['lines']]
        merged['deadline'] = merged['deadline'] or found['deadline']
        merged['location'] = merged['location'] or found['location']
    # One entry per failing action: its failing tests, then what the log says.
    groups = []
    for action, test, state in failures:
        group = next((entry for entry in groups if entry[0] == action), None)
        if group is None:
            group = (action, [])
            groups.append(group)
        if test:
            group[1].append('%s (%s)' % (test, state))
    for number, (action, tests) in enumerate(groups, 1):
        found = by_action.get(action, {})
        names = tests or ['%s (failed)' % name for name in found.get('tests', [])]
        lines.append('failure %d/%d: %s' % (number, len(groups), action))
        for name in names[:3]:
            lines.append('  test: ' + name[:400])
        if len(names) > 3:
            lines.append('  ... and %d more failing tests' % (len(names) - 3))
        if found.get('deadline'):
            lines.append('  ' + found['deadline'][:400])
        for line in found.get('lines', [])[:3]:
            lines.append('  ' + line[:400])
        if found.get('location'):
            lines.append('  at ' + found['location'])
        if log_directory is not None:
            lines.append('  log: ' + str(log_directory))
    if leftovers:
        lines.append('also: the supervisor of an action reports:')
        lines += ['  ' + line for line in leftovers]
    budget = MAX_RED_LINES + MAX_RED_PER_FAILURE * (len(groups) - 1)
    if len(lines) > budget:
        lines = lines[:budget]
        lines.append('verification: summary truncated; read the log for the rest')
    return lines


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path, help='gate log file or the directory holding its *.log files')
    parser.add_argument('--max-lines', type=int, default=0,
                        help='cut the summary to N lines (default: the green and red budgets)')
    args = parser.parse_args(argv)
    if not args.log.exists():
        parser.error('no such log: ' + str(args.log))
    text = None
    directory = args.log if args.log.is_dir() else None
    if directory is None and args.log.name in STEP_LOGS:
        text = read_step_logs(args.log)
        directory = args.log.parent
    if text is None and directory is None:
        text = args.log.read_text(errors='replace')[:MAX_LOG_BYTES]
    lines = summarize(log_directory=directory, text=text)
    if args.max_lines > 0:
        lines = lines[:args.max_lines]
    for line in lines:
        print(line)
    return 0


if __name__ == '__main__':
    sys.exit(main())
