#!/usr/bin/env python3
"""Per-test conformance of the new core against the old one (docs/design/new-core-s1.md §9).

For every file it runs

  old      `mylang test FILE --json`                 (the oracle)
  debug    `mylang-core test FILE --json`
  release  `mylang-core test FILE --json --release`

and requires, per test function: the same set of test names, the same verdict (pass,
false, or a trap with the same `R_...` code; the trap position may differ), and nothing
the new core cannot build counts against it: a test it refuses is `unsupported`
(`E_CORE_UNSUPPORTED`), reported separately from mismatches. Arena tests are excluded
(§11): the five arena files and every test whose name matches `*arena*`.

usage:
  conformance.py [--set clean13|s1|excluded|all | FILE...] [--modes debug,release]
                 [--why] [--verbose] [--jobs N] [--pin PATH] [--include-arena]
                 [--mylang P] [--core P] [--cache-dir D] [--verbose]

FILE is a path, or a bare name that means tests/lang/NAME.my. Exit status 1 when any
test mismatches or a file cannot be compared.
"""
import argparse, collections, concurrent.futures, fnmatch, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LANG = os.path.join(ROOT, "tests", "lang")

# The 13 files that use only S1 features (§9); most of their tests wait for lanes V and O.
CLEAN13 = """rc_element_moves rc_plain_projection local_stack_list rc_loop_uniqueness
mut_record_call_window mut_collection_call_window exclusive_ownership argument_evaluation_order
gc_mut_argument_roots rc_mut_aliases rc_mut_uniqueness rc_plain_update_paths rc_readonly_body""".split()

# S1 adds 18 files: 15 that need only the interim arena rule or floats, 3 that need a small text subset.
S1_MORE = """rc_named_record_writes rc_plain_record_writes closed_record_inout
rc_fresh_constructors rc_fresh_spans rc_fresh_returns
positive_list_index rc_read_list_versions rc_fresh_loop_roots rc_scalar_loops
rc_scope_inline rc_empty_frames rc_inert_receivers rc_plain_list_writes rc_loop_versions
rc_tree_drains move_elision rc_inline_glue""".split()

S1 = CLEAN13 + S1_MORE

# Files left out of S1, with the feature that blocks them (§9, §11).
EXCLUDED = {
    "python_variants": "generics",
    "option_equality": "generics", "option_methods": "generics", "option_narrowing": "generics",
    "option_niche": "generics", "option_propagation": "generics",
    "migrated/generic_results": "generics",
    "rc_plain_appends": "other list methods, tuples or fixed arrays",
    "rc_append_loops": "other list methods, tuples or fixed arrays",
    "rc_plain_retains": "other list methods, tuples or fixed arrays",
    "rc_plain_aggregates": "other list methods, tuples or fixed arrays",
    "rc_match_scalars": "other list methods, tuples or fixed arrays",
    "migrated/propagation": "imports (R-3; a split single-module copy goes in test/core)",
    "error_traces": "a capability (Filesystem)",
    "arena_managed": "arena feature (§11)", "arena_scopes": "arena feature (§11)",
    "arena_class_escape": "arena feature (§11)", "arena_regions": "arena feature (§11)",
    "rc_arena_values": "arena feature (§11)",
}
ARENA_FILES = {name for name, why in EXCLUDED.items() if why.startswith("arena")}
ARENA_TESTS = "*arena*"


def resolve(name):
    """The path of a file argument: a bare name means tests/lang/NAME.my."""
    if os.path.exists(name):
        return os.path.abspath(name)
    return os.path.join(LANG, name + ".my")


def short(path):
    """A file's name relative to tests/lang, without the extension."""
    base = os.path.relpath(path, LANG) if path.startswith(LANG) else os.path.basename(path)
    return base[:-3] if base.endswith(".my") else base


class Tool:
    def __init__(self, args):
        self.mylang = args.mylang
        self.core = args.core
        self.cache = args.cache_dir
        # Keep every child off the reserved timing CPUs (2, 3, 11) and off 10, the measurement CPU.
        allowed = sorted(set(os.sched_getaffinity(0)) - {2, 3, 10, 11})
        self.cpus = ",".join(map(str, allowed)) if allowed else None

    def run(self, argv, timeout=600):
        if self.cpus and os.path.exists("/usr/bin/taskset"):
            argv = ["taskset", "-c", self.cpus] + argv
        try:
            done = subprocess.run(argv, capture_output=True, text=True, cwd=ROOT, timeout=timeout)
        except subprocess.TimeoutExpired:
            return None
        return done

    def old(self, path):
        done = self.run([self.mylang, "test", path, "--json"])
        return parse(done, "old core")

    def new(self, path, release):
        argv = [self.core, "test", path, "--json", "--cache-dir", self.cache]
        if release:
            argv.append("--release")
        done = self.run(argv)
        return parse(done, "new core " + ("release" if release else "debug"))


def parse(done, what):
    """The JSON report of a test run, or a string describing why there is none."""
    if done is None:
        return "%s: timed out" % what
    for chunk in (done.stdout, done.stderr):
        start = chunk.find('{"version"')
        if start >= 0:
            try:
                return json.loads(chunk[start:].splitlines()[0])
            except ValueError:
                pass
    return "%s: no report (exit %d): %s" % (what, done.returncode, (done.stderr or done.stdout).strip()[:300])


def verdict_old(test):
    """(kind, detail) for an old-core test: pass, false, trap CODE or skip."""
    if test["status"] in ("passed", "cached"):
        return ("pass", "")
    if test["status"] == "failed":
        found = re.match(r"(R_[A-Z_]+)", test.get("reason", ""))
        return ("trap", found.group(1)) if found else ("false", "")
    return ("skip", "")


def verdict_new(test):
    """(kind, detail) for a new-core test: pass, false, trap CODE, error or unsupported."""
    if test["status"] == "passed":
        return ("pass", "")
    if test["status"] == "unsupported":
        return ("unsupported", test.get("reason", ""))
    reason = test.get("reason", "")
    found = re.match(r"(R_[A-Z_]+)", reason)
    if found:
        return ("trap", found.group(1))
    if reason.startswith("expected true, got false"):
        return ("false", "")
    return ("error", reason.splitlines()[0] if reason else "")


def keep(name, include_arena):
    return include_arena or not fnmatch.fnmatchcase(name, ARENA_TESTS)


def compare(path, old, news, include_arena):
    """Per-file result: old/new test tables compared, for each mode."""
    result = {"file": short(path), "tests": 0, "modes": {}, "problems": [], "reasons": collections.Counter(), "unsupported": {}, "pass": [], "known_fail": []}
    if isinstance(old, str):
        result["problems"].append(old)
        return result
    old_tests = {t["name"]: verdict_old(t) for t in old["tests"] if keep(t["name"], include_arena)}
    result["tests"] = len(old_tests)
    passed = {name: True for name in old_tests}
    failed = set()
    for mode, report in news.items():
        stats = {"match": 0, "mismatch": 0, "unsupported": 0, "names": 0}
        result["modes"][mode] = stats
        if isinstance(report, str):
            # No report at all (a crash or a timeout): one problem for the file, not one per test.
            result["problems"].append(report)
            stats["mismatch"] += 1
            passed = {}
            continue
        new_tests = {t["name"]: (verdict_new(t), t) for t in report["tests"] if keep(t["name"], include_arena)}
        for name in sorted(set(old_tests) ^ set(new_tests)):
            side = "only in the old core" if name in old_tests else "only in the new core"
            result["problems"].append("%s: test name %s (%s)" % (mode, name, side))
            stats["names"] += 1
        stats["mismatch"] += stats["names"]
        for name, expected in old_tests.items():
            if name not in new_tests:
                continue
            got, raw = new_tests[name]
            if got[0] != "pass":
                passed.pop(name, None)
            if got[0] == "unsupported":
                stats["unsupported"] += 1
                if mode == next(iter(news)):
                    result["reasons"][got[1]] += 1
                    result["unsupported"][name] = got[1]
            elif got == expected and expected[0] != "skip":
                stats["match"] += 1
            else:
                stats["mismatch"] += 1
                result["problems"].append("%s: %s: old %s%s, new %s%s" % (
                    mode, name, expected[0], " " + expected[1] if expected[1] else "",
                    got[0], " " + got[1] if got[1] else ""))
            if raw["status"] == "failed":
                failed.add(name)
    # A test is pinned as passing when the old core and every level of the new core pass it;
    # one the new core fails at any level is a known failure (a bug to fix, never an unsupported test).
    result["pass"] = sorted(n for n in passed if old_tests[n][0] == "pass")
    result["known_fail"] = sorted(failed)
    return result


def table(results, modes, why):
    """The per-file table and totals; returns the text."""
    width = max([len(r["file"]) for r in results] + [24])
    head = "%-*s %5s" % (width, "file", "tests")
    for mode in modes:
        head += " | %-7s %5s %5s %5s" % (mode, "match", "misma", "unsup")
    lines = [head, "-" * len(head)]
    totals = {m: collections.Counter() for m in modes}
    all_tests = 0
    for r in results:
        line = "%-*s %5d" % (width, r["file"], r["tests"])
        all_tests += r["tests"]
        for mode in modes:
            s = r["modes"].get(mode) or {"match": 0, "mismatch": 0, "unsupported": 0}
            line += " | %-7s %5d %5d %5d" % ("", s["match"], s["mismatch"], s["unsupported"])
            for key in ("match", "mismatch", "unsupported"):
                totals[mode][key] += s[key]
        lines.append(line)
    lines.append("-" * len(head))
    lines.append("%-*s %5d" % (width, "TOTAL", all_tests))
    for mode in modes:
        t = totals[mode]
        lines.append("  %-8s matching %d, mismatching %d, unsupported %d (of %d tests; %d supported)" % (
            mode, t["match"], t["mismatch"], t["unsupported"], all_tests, t["match"] + t["mismatch"]))
    return "\n".join(lines), totals


def explain(results, verbose):
    """Unsupported tests grouped by the construct that blocks them, then the blocking features of each file."""
    by_reason = collections.Counter()
    files = collections.defaultdict(set)
    for r in results:
        for reason, n in r["reasons"].items():
            by_reason[reason] += n
            files[reason].add(r["file"])
    lines = ["", "blocking features of the unsupported tests (tests / files):"]
    for reason, n in by_reason.most_common():
        lines.append("  %4d / %2d  %s" % (n, len(files[reason]), reason))
    lines += ["", "blocking features per file (file: tests unsupported of tests; the features, most common first):"]
    for r in results:
        if not r["reasons"]:
            continue
        total = sum(r["reasons"].values())
        lines.append("  %-30s %3d of %3d: %s" % (r["file"], total, r["tests"], ", ".join("%s x%d" % kv for kv in r["reasons"].most_common())))
        if verbose:
            for name, reason in sorted(r["unsupported"].items()):
                lines.append("      %s: %s" % (name, reason))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*")
    ap.add_argument("--set", choices=["clean13", "s1", "excluded", "all"], default=None)
    ap.add_argument("--modes", default="debug,release")
    ap.add_argument("--why", action="store_true", help="list each blocking feature, and why excluded files are excluded")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--pin", default=None, help="write the pins file test-core checks (tests passing everywhere)")
    ap.add_argument("--include-arena", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--mylang", default=os.path.join(ROOT, "zig-out/bin/mylang"))
    ap.add_argument("--core", default=os.path.join(ROOT, "zig-out/bin/mylang-core"))
    ap.add_argument("--cache-dir", default=os.path.join(ROOT, ".mylang-cache", "core-conformance"))
    args = ap.parse_args()
    modes = args.modes.split(",")
    if args.set == "clean13":
        names = CLEAN13
    elif args.set == "excluded":
        names = [n for n in EXCLUDED if n not in ARENA_FILES or args.include_arena]
    elif args.set == "all":
        names = sorted(short(os.path.join(dp, f)) for dp, _, fs in os.walk(LANG) for f in fs if f.endswith(".my"))
    elif args.files:
        names = args.files
    else:
        names = S1
    if not args.include_arena and args.set != "excluded":
        names = [n for n in names if n not in ARENA_FILES]
    paths = [resolve(n) for n in names]
    tool = Tool(args)
    os.makedirs(args.cache_dir, exist_ok=True)

    def one(path):
        old = tool.old(path)
        news = {mode: tool.new(path, mode == "release") for mode in modes}
        return compare(path, old, news, args.include_arena)

    # The first build compiles the runtime object; do it alone so parallel builds do not race on it.
    results = [one(paths[0])] if paths else []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results += list(pool.map(one, paths[1:]))
    text, totals = table(results, modes, args.why)
    print(text)
    bad = False
    for r in results:
        for problem in r["problems"]:
            bad = True
            print("PROBLEM %s: %s" % (r["file"], problem))
    if args.why:
        print(explain(results, args.verbose))
        for name in names:
            if name in EXCLUDED:
                print("  excluded %-28s %s" % (name, EXCLUDED[name]))
    if args.pin:
        with open(args.pin, "w") as out:
            out.write("# Generated by experiments/new-core-s1-20261005/conformance.py --pin; regenerate it when a lane lands.\n")
            out.write("# `file NAME` lists a tests/lang file the gate runs at debug and release. `pass TEST` pins a test\n")
            out.write("# that passes in the old core and at both levels in the new one: it must keep passing. `known-fail\n")
            out.write("# TEST` names a test the new core fails today (a new-core bug; it may fail or pass). Any other test\n")
            out.write("# of a listed file may be unsupported but must not fail; a crash or a missing test fails the gate.\n")
            for r in results:
                out.write("file %s\n" % r["file"])
                for name in r["pass"]:
                    out.write("pass %s\n" % name)
                for name in r["known_fail"]:
                    out.write("known-fail %s\n" % name)
    return 1 if bad or any(totals[m]["mismatch"] for m in modes) else 0


if __name__ == "__main__":
    sys.exit(main())
