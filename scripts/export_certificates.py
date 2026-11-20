#!/usr/bin/env python3
"""Export the ownership certificates of the clean corpus and count them.

The corpus is every program under `tests/lang`, `tests/value_semantics` and `tests/ported`,
the fixtures of `test/core`, `benchmarks/` and `examples/`. A test program is built by
`selka test --emit-certificates` (the build the tests run), any other program with a `main`
by `selka build --emit-certificates`. Each program's certificates land in a directory of its
own under OUT, one `.certificate` file per emitted unit (see
docs/design/ownership-certificates.md section 4.1).

    python3 scripts/export_certificates.py --out DIR [--mode MODE] [--twice] [--json]

The script prints, for every group and in total, the programs exported, the functions they hold, the
functions marked unchecked (by reason), and the functions or programs it could not describe, each with
its reason. With --twice it exports a second time and checks that every file is byte-identical.
It exits 1 when a program failed to export or the two runs differ.

Python is allowed in developer scripts: nothing here is part of the install graph or of `src/`.
"""
import argparse
import collections
import concurrent.futures
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# (group directory, how its programs are exported)
GROUPS = [
    ("tests/lang", "test"),
    ("tests/value_semantics", "test"),
    ("tests/ported", "test"),
    ("test/core", "auto"),
    ("benchmarks", "auto"),
    ("examples", "auto"),
]

MODES = {
    "optimized-debug": [],
    "release": ["--release"],
    "unoptimized": ["--unoptimized"],
}

# Files the compiler cannot take as an entry, with the reason: a local copy of an embedded standard module is ignored.
NOT_ENTRIES = {"examples/environment.selka": "a local copy of the embedded `environment` module, which the compiler ignores"}

MAIN = re.compile(r"^(public\s+)?(func|def)\s+main\s*\(", re.M)
TEST = re.compile(r"^\s*(public\s+)?(func|def)\s+test_", re.M)


def compiler(args):
    path = pathlib.Path(args.compiler) if args.compiler else ROOT / "zig-out" / "bin" / "selka"
    if not path.exists():
        sys.exit(f"export_certificates: no compiler at {path}; run `zig build` first")
    return str(path)


def classify(path):
    """How to export one `.selka` file: 'build' (it has a main), 'test' (it has tests) or None (a library)."""
    text = path.read_text(errors="replace")
    if MAIN.search(text):
        return "build"
    if TEST.search(text):
        return "test"
    return None


def run(command, env, timeout):
    try:
        done = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, "", "timed out"
    return done.returncode, done.stdout, done.stderr


def first_line(text):
    """The first line that names an error, else the first non-blank line."""
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    for line in lines:
        if "error" in line.lower() or "FAIL" in line or "failed" in line:
            return line[:240]
    return lines[0][:240] if lines else ""


def has_files(directory):
    return directory.exists() and any(directory.rglob("*.certificate"))


def classify_failure(code, text, wrote):
    """How a non-zero exit relates to the certificates.

    `describe`: the exporter reported a function it cannot describe (a real failure).
    `link`: the program needs a C helper (`--link`), so the build stopped after the certificates were written.
    `tests`: a test of a runner fixture failed on purpose or after the build; the certificates were written.
    `failed`: anything else.
    """
    if "E_CERTIFICATE" in text:
        return "describe"
    if wrote and ("ld.lld" in text or "undefined symbol" in text):
        return "link"
    if wrote and code == 1:
        return "tests"
    return "failed"


def export_group_tests(selka, group, out, mode, env, timeout, cache):
    """One `selka test GROUP` run: every test file is built as a program of its own."""
    target = out / group
    command = [selka, "test", group, "--force", "--cache-dir", str(cache / group.replace("/", "_")), "--emit-certificates", str(target)] + MODES[mode]
    code, stdout, stderr = run(command, env, timeout)
    failures = []
    if code != 0:
        kind = classify_failure(code, stderr + stdout, has_files(target))
        failures.append({"program": group, "exit": code, "kind": kind, "reason": first_line(stderr) or first_line(stdout)})
    return failures


def export_one(selka, group, path, how, out, mode, env, timeout, cache):
    relative = path.relative_to(ROOT)
    name = str(relative.with_suffix("")).replace("/", "__")
    target = out / group / name
    cache_dir = cache / group.replace("/", "_") / name
    links = []
    if path.with_suffix(".c").exists():
        links = ["--link", str(path.with_suffix(".c").relative_to(ROOT))]
    if how == "build":
        binary = cache / "bin" / (group.replace("/", "_") + "__" + name)
        binary.parent.mkdir(parents=True, exist_ok=True)
        command = [selka, "build", str(relative), "-o", str(binary), "--cache-dir", str(cache_dir), "--emit-certificates", str(target)] + links + MODES[mode]
    else:
        command = [selka, "test", str(relative), "--force", "--cache-dir", str(cache_dir), "--emit-certificates", str(target)] + links + MODES[mode]
    code, stdout, stderr = run(command, env, timeout)
    if code != 0:
        kind = classify_failure(code, stderr + stdout, has_files(target))
        return {"program": str(relative), "exit": code, "kind": kind, "reason": first_line(stderr) or first_line(stdout)}
    return None


def export_group_auto(selka, group, out, mode, env, timeout, cache, jobs):
    files = sorted(p for p in (ROOT / group).rglob("*.selka"))
    work = []
    skipped = 0
    for path in files:
        how = classify(path)
        if how is None or str(path.relative_to(ROOT)) in NOT_ENTRIES:
            skipped += 1
            continue
        work.append((path, how))
    failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = [pool.submit(export_one, selka, group, p, how, out, mode, env, timeout, cache) for p, how in work]
        for future in futures:
            failure = future.result()
            if failure:
                failures.append(failure)
    return failures, len(work), skipped


FUNCTION = re.compile(r"^function (\S+) result (\S+) from (\S+) unchecked (\S+)$")


def count_certificates(directory):
    """Functions, unchecked reasons and files under `directory`."""
    stats = {"files": 0, "functions": 0, "unchecked": collections.Counter(), "names": set(), "programs": set()}
    for path in sorted(directory.rglob("*.certificate")):
        stats["files"] += 1
        parts = path.relative_to(directory).parts
        stats["programs"].add(parts[0] if len(parts) > 1 else "")
        with open(path, errors="replace") as handle:
            for line in handle:
                match = FUNCTION.match(line.rstrip("\n"))
                if not match:
                    continue
                stats["functions"] += 1
                stats["names"].add(match.group(1))
                if match.group(4) != "-":
                    stats["unchecked"][match.group(4)] += 1
    return stats


def lst(text):
    return [] if text == "-" else text.split(",")


def analyze(directory):
    """What the certificates under `directory` contain: states, takes, stores, features per function."""
    totals = collections.Counter()
    features = collections.Counter()
    functions = 0
    for path in sorted(directory.rglob("*.certificate")):
        function = None
        with open(path, errors="replace") as handle:
            for line in handle:
                t = line.split()
                if not t:
                    continue
                if t[0] == "function":
                    if function is not None:
                        functions += 1
                        features.update(function)
                    function = set()
                elif t[0] == "inst" and function is not None:
                    state = t[t.index("state") + 1]
                    op, cls = t[2], t[3]
                    totals["state " + state] += 1
                    if cls == "Project" and state == "owned":
                        totals["take " + op] += 1
                        function.add("takes")
                        if op in ("record_get", "array_get"):
                            function.add("takes of record or array slots")
                    if state == "emptied":
                        totals["emptied " + op] += 1
                        function.add("emptied")
                    if state == "stack":
                        function.add("stack")
                    if "released" in t:
                        totals["released " + t[t.index("released") + 1]] += 1
                    if "slot" in t and t[t.index("slot") + 1] == "tail":
                        totals["pop tail"] += 1
                    if state == "none" and cls == "Call":
                        function.add("call with no result")
                    if cls == "Update" and state == "scalar":
                        function.add("update of a scalar aggregate")
                    if cls == "Take" and state == "scalar":
                        function.add("take of a scalar payload")
                    if cls == "Construct" and state == "borrowed" and t[t.index("parents") + 1] == "-":
                        function.add("borrowed construct with no parents")
                    if op == "undef" and state == "immortal":
                        function.add("undef of a managed type")
                elif t[0] == "phi" and function is not None:
                    totals["phi " + t[2]] += 1
                    if t[2] == "none":
                        function.add("dead phi")
        if function is not None:
            functions += 1
            features.update(function)
    return {"functions": functions, "instructions": {k: v for k, v in sorted(totals.items())}, "functions_with": dict(sorted(features.items()))}


def digest_tree(directory):
    """Relative path to sha256 of every file under `directory`."""
    result = {}
    for path in sorted(p for p in directory.rglob("*") if p.is_file()):
        result[str(path.relative_to(directory))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def export_all(selka, args, out, groups):
    env = dict(os.environ)
    env.setdefault("SELKA_ZIG", env.get("ZIG", ""))
    cache = out.parent / (out.name + "-cache")
    summary = {}
    for group, how in groups:
        if how == "test":
            failures = export_group_tests(selka, group, out, args.mode, env, args.timeout, cache)
            programs = None
        else:
            failures, programs, skipped = export_group_auto(selka, group, out, args.mode, env, args.timeout, cache, args.jobs)
        stats = count_certificates(out / group) if (out / group).exists() else count_certificates(out / "_missing")
        summary[group] = {
            "analysis": analyze(out / group) if (out / group).exists() else {},
            "programs": len(stats["programs"] - {""}) if programs is None else programs,
            "files": stats["files"],
            "functions": stats["functions"],
            "distinct_function_names": len(stats["names"]),
            "unchecked": dict(stats["unchecked"]),
            "failures": failures,
        }
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True, help="directory to export into (replaced)")
    parser.add_argument("--mode", choices=sorted(MODES), default="optimized-debug")
    parser.add_argument("--compiler", help="selka binary (default zig-out/bin/selka)")
    parser.add_argument("--group", action="append", help="only this corpus group (repeatable)")
    parser.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) // 2))
    parser.add_argument("--timeout", type=int, default=900, help="seconds per program or group")
    parser.add_argument("--twice", action="store_true", help="export a second time and compare every byte")
    parser.add_argument("--json", action="store_true", help="print the summary as JSON")
    args = parser.parse_args()
    selka = compiler(args)
    groups = [g for g in GROUPS if not args.group or g[0] in args.group]
    out = pathlib.Path(args.out).resolve()
    for stale in (out, out.parent / (out.name + "-cache")):
        shutil.rmtree(stale, ignore_errors=True)
    summary = export_all(selka, args, out, groups)
    report = {"mode": args.mode, "groups": summary}
    status = 0
    if any(failure["kind"] in ("describe", "failed") for group in summary.values() for failure in group["failures"]):
        status = 1
    if args.twice:
        second = out.parent / (out.name + "-second")
        for stale in (second, second.parent / (second.name + "-cache")):
            shutil.rmtree(stale, ignore_errors=True)
        export_all(selka, args, second, groups)
        first_tree, second_tree = digest_tree(out), digest_tree(second)
        differing = sorted(k for k in set(first_tree) | set(second_tree) if first_tree.get(k) != second_tree.get(k))
        report["deterministic"] = not differing
        report["files_compared"] = len(first_tree)
        report["differing_files"] = differing[:20]
        if differing:
            status = 1
        shutil.rmtree(second, ignore_errors=True)
        shutil.rmtree(second.parent / (second.name + "-cache"), ignore_errors=True)
    total = {"programs": 0, "files": 0, "functions": 0, "unchecked": collections.Counter(), "failures": collections.Counter()}
    for group in summary.values():
        total["programs"] += group["programs"]
        total["files"] += group["files"]
        total["functions"] += group["functions"]
        total["failures"].update(failure["kind"] for failure in group["failures"])
        total["unchecked"].update(group["unchecked"])
    total["unchecked"] = dict(total["unchecked"])
    total["failures"] = dict(total["failures"])
    report["total"] = total
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(f"mode {args.mode}")
        for name, group in summary.items():
            print(f"{name}: {group['programs']} programs, {group['files']} files, {group['functions']} functions, unchecked {group['unchecked'] or 0}, {len(group['failures'])} programs that stopped")
            for failure in group["failures"]:
                print(f"  {failure['kind'].upper()} {failure['program']} (exit {failure['exit']}): {failure['reason']}")
            features = group["analysis"].get("functions_with", {})
            if features:
                print("  functions with: " + ", ".join(f"{k} {v}" for k, v in features.items()))
        print(f"total: {total['programs']} programs, {total['files']} files, {total['functions']} functions, unchecked {total['unchecked'] or 0}, programs that stopped {total['failures'] or 0}")
        print("(describe = a function the exporter could not describe; failed = no certificates; link = needs a C helper after the certificates were written; tests = a test failed after the build)")
        if args.twice:
            print(f"byte-identical across two runs: {report['deterministic']} ({report['files_compared']} files compared)")
            for name in report["differing_files"]:
                print(f"  DIFFERS {name}")
    sys.exit(status)


if __name__ == "__main__":
    main()
