#!/usr/bin/env python3
"""Shadow mode of the edit check: did the selection cover every test that failed in a complete gate? (W6)

    python3 scripts/edit_check_shadow.py (--gate-log PATH | --failed NAME...) [--tests DIR] [--map PATH] [--store DIR]
                                         [--source NAME] [--timeout SECONDS] [--impact PATH]

It selects the tests the branch diff impacts (against the store's map, which must be an ancestor of HEAD) and takes
the tests the gate failed from `--failed` (the gate's own test ids, `test/integration.zig::x.test.y` or a guest
`area::test_name`) or from the FAIL lines of `--gate-log` (a verification log, or a directory of them). It appends one
JSON line to `<store>/shadow.jsonl`: the head, the map, the selection's size, the failures, and the failures the
selection missed. A gate with no failures records a clean sample (a real change with zero failures, which the mutant
study does not give). A new test that the selection did not know (`--tests` gives the current names) counts as
selected. A run that cannot decide (no map, no impact tool, the tool failing or passing `--timeout`) appends a record
with `error` and `covered: null` instead of nothing, and exits 2. Records may carry `source` (who ran it); readers of
the older lines need nothing new.

`verify_cache.py` starts it detached after the verdict of every gate that fails on a named test (stage 6).
Developer tool: not part of the install graph.
"""
import argparse
import json
import os
import re
import signal
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAIL_LINE = re.compile(r"^(?P<name>.+?)\.\.\.(?:\S*\s*)?FAIL\b")
LEADING_INDEX = re.compile(r"^\d+\s+")


def git(*args):
    return subprocess.check_output(["git", "-C", ROOT, *args], text=True).strip()


def failing_tests(path):
    """Test names the gate reports as FAIL, from one log file or from every log under a directory."""
    paths = []
    if os.path.isdir(path):
        for directory, _, names in os.walk(path):
            paths += [os.path.join(directory, name) for name in names if name.endswith(".log") or name.endswith(".txt")]
    else:
        paths = [path]
    failed = set()
    for item in paths:
        try:
            with open(item, errors="replace") as handle:
                for line in handle:
                    match = FAIL_LINE.match(line.strip())
                    if match and ".test." in match.group("name"):
                        failed.add(LEADING_INDEX.sub("", match.group("name")).strip())
        except OSError:
            continue
    return sorted(failed)


def selection_names(name, root=ROOT):
    """The names the edit check's selection could give one failed test: a Zig test id without its root
    (`test/integration.zig::fix_cli_test.test.x` is `fix_cli_test.test.x`), a guest test as its file
    (`a04_list_extrema::test_x` is `tests/lang/a04_list_extrema.selka`), and the name itself."""
    names = {name}
    if "::" in name:
        prefix, rest = name.split("::", 1)
        if prefix.endswith(".zig"):
            names.add(rest)
        elif "/" not in prefix:
            for directory, _, files in os.walk(os.path.join(root, "tests")):
                if prefix + ".selka" in files:
                    names.add(os.path.relpath(os.path.join(directory, prefix + ".selka"), root))
    return names


def append_record(store, record):
    """Append one record to `<store>/shadow.jsonl`."""
    os.makedirs(store, exist_ok=True)
    with open(os.path.join(store, "shadow.jsonl"), "a") as handle:
        handle.write(json.dumps(record) + "\n")


def newest_map(store, head):
    best = None
    if not os.path.isdir(store):
        return None
    for name in os.listdir(store):
        match = re.fullmatch(r"coverage-([0-9a-f]{40})\.json\.gz", name)
        if not match:
            continue
        commit = match.group(1)
        if subprocess.run(["git", "-C", ROOT, "merge-base", "--is-ancestor", commit, head]).returncode != 0:
            continue
        when = int(git("log", "-1", "--format=%ct", commit))
        if best is None or when > best[1]:
            best = (os.path.join(store, name), when)
    return best[0] if best else None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--gate-log")
    parser.add_argument("--failed", action="append", default=[], help="a test the gate failed, by its gate id; repeatable")
    parser.add_argument("--source", help="who ran the shadow (recorded as `source`)")
    parser.add_argument("--timeout", type=float, default=600.0,
                        help="seconds the impact tool may take; past them its whole process group ends")
    parser.add_argument("--unlisted", type=int, default=0,
                        help="failed tests not passed by name (the caller cut its list); `covered` is then undecided")
    parser.add_argument("--impact", default=os.path.join(ROOT, "zig-out", "tools", "edit-check-impact"))
    parser.add_argument("--tests", help="directory of tests-<root>.json (the current names); optional")
    parser.add_argument("--map")
    parser.add_argument("--store", default=os.environ.get("SELKA_EDIT_CHECK_STORE") or os.path.expanduser("~/.cache/selka/edit-check"))
    args = parser.parse_args()
    if not args.gate_log and not args.failed:
        parser.error("give --gate-log or --failed")
    head = git("rev-parse", "HEAD")
    failed = sorted(set(args.failed)) if args.failed else failing_tests(args.gate_log)
    base = {"head": head, "failed": failed, "time": time.strftime("%Y-%m-%dT%H:%M:%S")}
    if args.source:
        base["source"] = args.source
    if args.unlisted:
        base["unlisted"] = args.unlisted

    def undecided(reason, map_path=None):
        append_record(args.store, dict(base, map=os.path.basename(map_path) if map_path else None, selected=None,
                                       missed=None, covered=None, error=reason))
        print("shadow: head %s, failed in gate %d, undecided: %s" % (head[:12], len(failed), reason))
        return 2

    map_path = args.map or newest_map(args.store, head)
    if not map_path:
        return undecided("no map at or before HEAD in %s" % args.store)
    if not os.path.exists(args.impact):
        return undecided("no impact tool at %s (python3 scripts/edit_check.py builds it)" % args.impact, map_path)
    os.makedirs(args.store, exist_ok=True)
    selection = os.path.join(args.store, "shadow-selection-%d-%d.tsv" % (int(time.time()), os.getpid()))
    command = [args.impact, "--map", map_path, "--repo", ROOT, "--selection", selection]
    if args.tests:
        command += ["--tests", args.tests]
    try:
        # Its own process group, so a timeout ends whatever the tool started too.
        tool = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            code = tool.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            for signum in (signal.SIGTERM, signal.SIGKILL):
                try:
                    os.killpg(tool.pid, signum)
                except ProcessLookupError:
                    break
                try:
                    tool.wait(timeout=5)
                    break
                except subprocess.TimeoutExpired:
                    continue
            raise
        if code:
            raise subprocess.CalledProcessError(code, command)
        selected = set()
        with open(selection) as handle:
            for line in handle:
                root, kind, name, _ = (line.rstrip("\n").split("\t") + ["", ""])[:4]
                if kind == "named":
                    selected.add(name)
    except subprocess.TimeoutExpired:
        return undecided("the impact tool passed %.0f s" % args.timeout, map_path)
    except (subprocess.CalledProcessError, OSError) as error:
        return undecided("the impact tool failed: %s" % error, map_path)
    finally:
        if os.path.exists(selection):
            os.remove(selection)
    missed = [name for name in failed if not selection_names(name) & selected]
    # A miss is a miss; with unlisted failures and none missed among the listed ones, the answer is unknown.
    covered = False if missed else (None if args.unlisted else True)
    append_record(args.store, dict(base, map=os.path.basename(map_path), selected=len(selected), missed=missed,
                                   covered=covered))
    print("shadow: head %s, selected %d, failed in gate %d, missed %d" % (head[:12], len(selected), len(failed), len(missed)))
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main())
