#!/usr/bin/env python3
"""Differential of the Lean test planner (`lake exe cacheplan plan`) against the Zig planner on real runs.

Package K4 of docs/audits/provable-cache-plan-2026-10-26.md.  Python is allowed here (a developer script);
nothing in src/ or the install graph runs it.

The test runner sends the planner one `SLKCP002` request per `selka test` run and receives a reply from the
cache-plan component.  `capture` runs `selka test` over real entries through a recording component directory
(`SELKA_COMPONENT_DIR`), whose executable stores each request and the real component's reply and answers with
that reply, so the run is unchanged.  `compare` feeds every recorded request to `cacheplan plan` and compares what
Lean decides with what the component answered:

    reused flags       exactly                       (the admission decision: proved against `Cache.Admit`)
    batches            exactly                       (the closure of each planned test, sorted)
    groups, reverse    exactly                       (the strongly connected groups and the transpose)
    work counts        affected, reused, planned     (index and closure counts are algorithm specific; see the report)

Each entry runs four steps against a private `--cache-dir`: a cold run, an identical rerun, a run after one integer
literal of the entry is bumped, and a run after it is put back.  The reruns exercise `prior`, `candidates` and
`changed` with real values.

    cache_plan_diff.py capture --work DIR [--entries a.selka b.selka | --all-of tests/lang] [--jobs N]
    cache_plan_diff.py compare --work DIR
    cache_plan_diff.py random  --work DIR [--count N --seed S]   random graphs through the component directly
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOME = Path(os.environ.get("HOME", "/"))
CACHEPLAN = ROOT / "proofs" / "cache" / ".lake" / "build" / "bin" / "cacheplan"
LITERAL = re.compile(r"(?<![\w.\"'])(\d+)(?![\w.\"'])")


def real_components() -> Path:
    """The directory of the real components: `SELKA_COMPONENT_DIR` (the gate sets it), else the installed prefix of this tree."""
    return Path(os.environ.get("SELKA_COMPONENT_DIR") or ROOT / "zig-out" / "libexec" / "selka" / "components")


def component_directory(work: Path, real_dir: Path | None = None) -> Path:
    """A component directory whose `cache-plan` records each request and reply and then answers with the real one."""
    real_dir = real_dir or real_components()
    manifest = json.loads((real_dir / "cache-plan.json").read_text())
    real = real_dir / manifest["artifact"]
    out = work / "component"
    out.mkdir(parents=True, exist_ok=True)
    wrapper = out / "cache-plan-wrapper"
    wrapper.write_text(
        "#!/bin/sh\n"
        "# Records each planner request and its reply, then answers with the real component's reply.\n"
        f"REAL={real}\n"
        'dir="${CACHE_PLAN_CAPTURE:?}"\n'
        'id="$(date +%s%N)-$$"\n'
        'cp "$2" "$dir/$id.req"\n'
        '"$REAL" "$@" > "$dir/$id.rep"\n'
        "status=$?\n"
        'cat "$dir/$id.rep"\n'
        "exit $status\n"
    )
    wrapper.chmod(0o755)
    digest = hashlib.sha256(wrapper.read_bytes()).hexdigest()
    (out / "cache-plan.json").write_text(json.dumps({"artifact": "cache-plan-wrapper", "component": "cache-plan", "format": 1, "protocol": 2, "schema": 2, "sha256": digest}))
    return out


def case_environment(capture: Path, components: Path) -> dict:
    """The environment of one captured `selka test`: the recording planner, and a test tier shared by this case's steps alone.

    The test kinds publish to the per-user shared tier (`SELKA_TEST_SHARED_CACHE`), where an entry's graph head is addressed by the
    entry's project-relative path, which every scratch copy of `tests/lang` has in common. The changed-list check assumes that the
    generation a step builds on is the one the previous step of the same case left, so a case must not read what another run (a
    concurrent gate, another lane) wrote there: each case gets an empty directory of its own (F36)."""
    env = dict(os.environ)
    env.update({"CACHE_PLAN_CAPTURE": str(capture), "SELKA_COMPONENT_DIR": str(components), "SELKA_TEST_SHARED_CACHE": str(capture.parent / "shared-tests")})
    env.pop("SELKA_CACHE_PLAN_MODE", None)
    return env


def run_test(compiler: Path, entry: Path, cache: Path, capture: Path, components: Path, timeout: int) -> tuple[int, list[Path]]:
    """One `selka test ENTRY`; the requests it made, in order."""
    capture.mkdir(parents=True, exist_ok=True)
    before = set(capture.glob("*.req"))
    env = case_environment(capture, components)
    try:
        proc = subprocess.run([str(compiler), "test", str(entry), "--cache-dir", str(cache)], env=env, capture_output=True, timeout=timeout, cwd=entry.parent)
        status = proc.returncode
    except subprocess.TimeoutExpired:
        status = -9
    made = sorted(set(capture.glob("*.req")) - before)
    return status, made


def candidate_lines(text: str) -> list[int]:
    """Lines inside function bodies with a bare integer literal outside comments and strings."""
    lines = text.splitlines()
    found = []
    for number, line in enumerate(lines):
        if not line.startswith("    ") or line.lstrip().startswith("#") or '"' in line or "'" in line:
            continue
        if LITERAL.search(line):
            found.append(number)
    return found


def bump(text: str, number: int) -> str:
    lines = text.splitlines(keepends=True)
    line = lines[number]
    match = LITERAL.search(line)
    value = int(match.group(1))
    lines[number] = line[: match.start(1)] + str(value + 1) + line[match.end(1):]
    return "".join(lines)


def capture_entry(args: argparse.Namespace, entry: Path, corpus: Path, work: Path, components: Path) -> dict:
    name = entry.name
    case = work / "cases" / name
    shutil.rmtree(case, ignore_errors=True)
    cache = case / "cache"
    capture = case / "capture"
    steps = []
    original = entry.read_text()
    log = {"entry": str(entry.relative_to(corpus)), "steps": steps}

    def step(label: str) -> list[Path]:
        status, made = run_test(Path(args.compiler), entry, cache, capture, components, args.timeout)
        steps.append({"step": label, "status": status, "requests": [p.name for p in made]})
        return made

    step("cold")
    step("rerun")
    lines = candidate_lines(original)
    # a deterministic order that depends on the entry, so reruns of the script mutate the same lines
    seed = int(hashlib.sha256(name.encode()).hexdigest(), 16)
    order = [lines[(seed + 7 * i) % len(lines)] for i in range(min(len(lines), 8))] if lines else []
    edited = False
    for number in order:
        entry.write_text(bump(original, number))
        made = step(f"edit:{number + 1}")
        if made:
            edited = True
            break
    entry.write_text(original)
    if edited:
        step("revert")
    log["edited"] = edited
    return log


def command_capture(args: argparse.Namespace) -> int:
    work = Path(args.work)
    work.mkdir(parents=True, exist_ok=True)
    components = component_directory(work)
    corpus = work / "corpus"
    if args.all_of:
        source = Path(args.all_of)
        shutil.rmtree(corpus, ignore_errors=True)
        shutil.copytree(source, corpus, symlinks=True)
        entries = sorted(p for p in corpus.glob("*.selka"))
    else:
        entries = [Path(e) for e in args.entries]
        corpus = entries[0].parent
    if args.limit:
        entries = entries[: args.limit]
    start = time.time()
    results = []
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for result in pool.map(lambda e: capture_entry(args, e, corpus, work, components), entries):
            results.append(result)
            made = sum(len(s["requests"]) for s in result["steps"])
            print(f"{result['entry']:48s} {made} requests", flush=True)
    (work / "capture.json").write_text(json.dumps({"entries": results, "seconds": time.time() - start}, indent=1))
    print(f"captured {sum(len(s['requests']) for r in results for s in r['steps'])} requests from {len(results)} entries in {time.time() - start:.0f} s")
    return 0


def command_project(args: argparse.Namespace) -> int:
    """Run `selka test` over a real project, then after each of a chain of edits, recording every planner request.

    The edits are those of the K0 fuzzer that keep the project valid: an integer literal raised (behavioural), a
    comment line added (not), and a module put back to an earlier text, all in modules that are not test files."""
    import random
    work = Path(args.work)
    components = component_directory(work)
    corpus = Path(args.corpus)
    template, subdir = {"selka": ("selka", "markdown"), "eda": ("eda", "stage2/selka/src")}[args.target]
    rng = random.Random(args.seed)
    case = work / "cases" / f"project-{args.target}"
    shutil.rmtree(case, ignore_errors=True)
    project = case / "p"
    shutil.copytree(corpus / template, project, symlinks=True)
    root = project / subdir
    cache = case / "cache"
    capture = case / "capture"
    modules = sorted(p for p in root.rglob("*.selka") if "oracle" not in p.parts and not p.name.endswith("_test.selka"))
    history: dict[Path, list[str]] = {}
    steps = []
    index = {"entries": [{"entry": f"project-{args.target}", "steps": steps}]}

    def run(label: str) -> None:
        started = time.time()
        env = dict(os.environ)
        env.update({"CACHE_PLAN_CAPTURE": str(capture), "SELKA_COMPONENT_DIR": str(components)})
        capture.mkdir(parents=True, exist_ok=True)
        before = set(capture.glob("*.req"))
        proc = subprocess.run([args.compiler, "test", ".", "--cache-dir", str(cache)], env=env, cwd=root, capture_output=True, timeout=args.timeout)
        made = sorted(set(capture.glob("*.req")) - before)
        steps.append({"step": label, "status": proc.returncode, "requests": [p.name for p in made]})
        print(f"{label:48s} exit {proc.returncode} {len(made)} requests {time.time() - started:.0f} s", flush=True)

    run("cold")
    for number in range(args.steps):
        path = rng.choice(modules)
        text = path.read_text()
        history.setdefault(path, []).append(text)
        kind = rng.choice(["literal", "literal", "comment", "undo"])
        rel = path.relative_to(root)
        if kind == "literal":
            lines = text.split("\n")
            spots = [(i, m) for i, line in enumerate(lines) if line.startswith("    ") and not line.lstrip().startswith("#") and '"' not in line
                     for m in re.finditer(r"(?<![\w.])(\d{1,3})(?![\w.])", line)]
            if not spots:
                continue
            i, m = rng.choice(spots)
            lines[i] = lines[i][: m.start(1)] + str(int(m.group(1)) + 1) + lines[i][m.end(1):]
            path.write_text("\n".join(lines))
        elif kind == "comment":
            path.write_text("# chain\n" + text)
        else:
            earlier = history[path]
            if len(earlier) < 2:
                continue
            path.write_text(earlier[rng.randrange(len(earlier) - 1)])
        run(f"edit {number}: {rel} {kind}")
    (work / "capture.json").write_text(json.dumps(index, indent=1))
    return 0


# --------------------------------------------------------------------------- compare


def decode(payload: bytes) -> dict:
    """Decode a reply payload (the reply minus its 64-byte envelope)."""
    at = 0

    def word() -> int:
        nonlocal at
        (v,) = struct.unpack_from("<I", payload, at)
        at += 4
        return v

    def row() -> list[int]:
        nonlocal at
        n = word()
        r = list(struct.unpack_from(f"<{n}I", payload, at))
        at += 4 * n
        return r

    work = dict(zip(["index_nodes", "index_edges", "affected_nodes", "closure_nodes", "closure_edges", "reused_tests", "planned_tests"], struct.unpack_from("<7Q", payload, 0)))
    at = 56
    n = word()
    tests = word()
    groups = list(struct.unpack_from(f"<{n}I", payload, at))
    at += 4 * n
    reverse = [row() for _ in range(n)]
    reused, batches = [], []
    for _ in range(tests):
        reused.append(word())
        batches.append(row())
    assert at == len(payload), "trailing bytes in a reply payload"
    return {"work": work, "groups": groups, "reverse": reverse, "reused": reused, "batches": batches}


def is_v1(data: bytes) -> bool:
    """A version-one request or reply (`SLKCP001`, closures of root sets): the test runner sends them beside version two."""
    return data[:8] == b"SLKCP001"


def request_summary(request: bytes) -> dict:
    if is_v1(request):
        n, tests = struct.unpack_from("<2I", request, 64 + 12)
        return {"nodes": n, "tests": tests, "changed": 0, "prior": False, "bytes": len(request), "v1": True}
    n, tests, changed, prior = struct.unpack_from("<4I", request, 64 + 12 + 32)
    return {"nodes": n, "tests": tests, "changed": changed, "prior": bool(prior), "bytes": len(request), "v1": False}


def reused_count(reply: bytes) -> int:
    """Tests reused in a version-two reply; a version-one reply decides nothing."""
    if is_v1(reply):
        return 0
    try:
        return sum(decode(reply[64:])["reused"])
    except (struct.error, AssertionError):
        return 0  # a malformed reply: the host rejects it and so does `cacheplan diff`


def lean_diff(requests: list[Path], chunk: int = 300) -> tuple[int, int, int, list[str], float]:
    """`cacheplan diff` over many requests (each beside its `.rep`): agree, differ, certified, DIFF lines, seconds."""
    agree = differ = certified = 0
    lines: list[str] = []
    started = time.time()
    for at in range(0, len(requests), chunk):
        proc = subprocess.run([str(CACHEPLAN), "diff", *map(str, requests[at: at + chunk])], capture_output=True, text=True)
        lines += [l for l in proc.stdout.splitlines() if l.startswith("DIFF")]
        summary = next((l for l in proc.stdout.splitlines() if l.startswith("diff requests=")), "")
        fields = dict(re.findall(r"(\w+)=(\d+)", summary))
        agree += int(fields.get("agree", 0))
        differ += int(fields.get("differ", len(requests[at: at + chunk])))
        certified += int(fields.get("certified", 0))
        if not summary:
            lines.append(f"DIFF cacheplan diff failed: {proc.stderr.strip()[:200]}")
    return agree, differ, certified, lines, time.time() - started


def command_compare(args: argparse.Namespace) -> int:
    work = Path(args.work)
    requests = [r for r in sorted((work / "cases").glob("*/capture/*.req")) if r.with_suffix(".rep").exists()]
    summaries = [request_summary(r.read_bytes()) for r in requests]
    agree, differ, certified, lines, seconds = lean_diff(requests)
    print(f"{len(requests)} requests: {agree} agree, {differ} differ; Lean certified the dirty set in {certified}; {seconds:.1f} s")
    for kind in ("cold (no prior)", "warm (prior present)"):
        want = kind.startswith("warm")
        subset = [s for s in summaries if s["prior"] == want and not s["v1"]]
        print(f"  {kind}: {len(subset)} requests, {sum(s['nodes'] for s in subset)} nodes, {sum(s['tests'] for s in subset)} tests, {sum(1 for s in subset if s['changed'])} with changed nodes")
    reused = sum(reused_count(r.with_suffix(".rep").read_bytes()) for r in requests)
    print(f"  {sum(1 for s in summaries if s['v1'])} of the requests are version one (closures only); {reused} of {sum(s['tests'] for s in summaries if not s['v1'])} tests reused by the component (and by Lean, since the replies agree)")
    for line in lines[:20]:
        print(line)
    return 1 if differ else 0


# --------------------------------------------------------------------------- random graphs


def encode_request(digests: list[bytes], callees: list[list[int]], roots: list[list[int]], candidates: list[bool], changed: list[int], topology: bytes, prior: bool, request_id: int) -> bytes:
    """An `SLKCP002` request, byte for byte as `cache_plan_protocol_v2.request` writes it."""
    def row(values: list[int]) -> bytes:
        return struct.pack(f"<I{len(values)}I", len(values), *values)

    body = bytearray()
    body += struct.pack("<3I", 0, 0, 0) + topology
    body += struct.pack("<4I", len(digests), len(roots), len(changed), int(prior))
    for d, r in zip(digests, callees):
        body += d + row(r)
    for flag, r in zip(candidates, roots):
        body += struct.pack("<I", int(flag)) + row(r)
    body += struct.pack(f"<{len(changed)}I", *changed)
    if prior:
        reverse: list[list[int]] = [[] for _ in digests]
        for source, targets in enumerate(callees):
            for target in targets:
                reverse[target].append(source)
        body += topology + struct.pack(f"<{len(digests)}I", *range(len(digests)))
        for r in reverse:
            body += row(r)
    snapshot = hashlib.sha256(bytes(body)).digest()
    header = b"SLKCP002" + struct.pack("<4I", 2, 2, 0, len(body)) + struct.pack("<Q", request_id) + snapshot
    return header + bytes(body)


def parse_request(data: bytes) -> dict:
    """The fields of an `SLKCP002` request (the inverse of `encode_request`)."""
    at = 64 + 12
    topology = data[at: at + 32]
    at += 32
    n, tests, nchanged, has_prior = struct.unpack_from("<4I", data, at)
    at += 16

    def row() -> list[int]:
        nonlocal at
        (count,) = struct.unpack_from("<I", data, at)
        values = list(struct.unpack_from(f"<{count}I", data, at + 4))
        at += 4 + 4 * count
        return values

    digests, callees = [], []
    for _ in range(n):
        digests.append(data[at: at + 32])
        at += 32
        callees.append(row())
    roots, candidates = [], []
    for _ in range(tests):
        (flag,) = struct.unpack_from("<I", data, at)
        at += 4
        candidates.append(bool(flag))
        roots.append(row())
    changed = list(struct.unpack_from(f"<{nchanged}I", data, at))
    return {"digests": digests, "callees": callees, "roots": roots, "candidates": candidates, "changed": changed, "topology": topology, "prior": bool(has_prior)}


def run_changed(work: Path, index: dict) -> dict:
    """Check, on real edits, that the nodes the host did not list as changed all exist, by body digest and callee count, in
    the previous generation; and that the check catches a deliberately dropped entry."""
    checked = bad = controls = control_caught = nodes = 0
    problems: list[str] = []
    scratch = work / "changed"
    scratch.mkdir(exist_ok=True)
    for entry in index["entries"]:
        name = Path(entry["entry"]).name
        capture = work / "cases" / name / "capture"
        steps = entry["steps"]
        for before, after in zip(steps, steps[1:]):
            if not (after["step"].startswith("edit") or after["step"] == "revert"):
                continue
            if not before["requests"] or not after["requests"]:
                continue

            # pair each new request with the old one of the same shape (tests and roots per test); skip if ambiguous
            def shape(name_: str) -> tuple:
                data = (capture / name_).read_bytes()
                if is_v1(data):
                    return ("v1",)
                parsed = parse_request(data)
                return (len(parsed["roots"]), tuple(len(r) for r in parsed["roots"]))

            olds: dict[tuple, list[str]] = {}
            for name_ in before["requests"]:
                olds.setdefault(shape(name_), []).append(name_)
            for new_name in after["requests"]:
                if shape(new_name) == ("v1",):
                    continue
                candidates = olds.get(shape(new_name), [])
                if len(candidates) != 1:
                    continue
                old, new = capture / candidates[0], capture / new_name
                proc = subprocess.run([str(CACHEPLAN), "changed", str(old), str(new)], capture_output=True, text=True)
                checked += 1
                fields = dict(re.findall(r"(\w+)=(\d+)", proc.stdout))
                nodes += int(fields.get("new_nodes", 0))
                if proc.returncode != 0:
                    bad += 1
                    problems.append(f"UNCOVERED {name} {candidates[0]} -> {new_name}: {proc.stdout.strip()}")
                # control: drop from `changed` a node whose body digest the old graph never had
                o, n = parse_request(old.read_bytes()), parse_request(new.read_bytes())
                old_digests = set(o["digests"])
                dropped = [c for c in n["changed"] if n["digests"][c] not in old_digests]
                if dropped:
                    controls += 1
                    kept = [c for c in n["changed"] if c != dropped[0]]
                    mutated = encode_request(n["digests"], n["callees"], n["roots"], n["candidates"], kept, n["topology"], False, 1)
                    mpath = scratch / f"{name}-{new_name}.mutated"
                    mpath.write_bytes(mutated)
                    again = subprocess.run([str(CACHEPLAN), "changed", str(old), str(mpath)], capture_output=True, text=True)
                    if again.returncode == 1:
                        control_caught += 1
    return {"pairs": checked, "satisfied": checked - bad, "violations": bad, "nodes": nodes, "controls": controls, "caught": control_caught, "problems": problems}


def command_changed(args: argparse.Namespace) -> int:
    work = Path(args.work)
    result = run_changed(work, json.loads((work / "capture.json").read_text()))
    for line in result["problems"]:
        print(line)
    print(f"{result['pairs']} consecutive request pairs across a real edit or revert: {result['satisfied']} satisfy the necessary condition, {result['violations']} do not; {result['nodes']} new-graph nodes")
    print(f"controls: in {result['controls']} pairs one genuinely new node was dropped from `changed`; the check caught {result['caught']}")
    return 1 if result["violations"] or result["caught"] != result["controls"] else 0


def random_request(rng, size: int, density: float, tests: int, shape: str) -> bytes:
    n = size
    digests = [rng.randbytes(32) if rng.random() < 0.9 else b"\x00" * 31 + bytes([rng.randrange(3)]) for _ in range(n)]  # some equal digests
    callees: list[list[int]] = []
    for node in range(n):
        count = min(n, int(rng.expovariate(1 / max(density, 0.01))))
        if shape == "dag":
            targets = [rng.randrange(node + 1, n) for _ in range(count)] if node + 1 < n else []
        elif shape == "layers":
            targets = [min(n - 1, node + 1 + rng.randrange(3)) for _ in range(count)] if node + 1 < n else []
        else:  # cyclic, with self edges and repeated edges
            targets = [rng.randrange(n) for _ in range(count)]
        callees.append(targets)
    roots = [[rng.randrange(n) for _ in range(rng.randrange(1, 4))] for _ in range(tests)]
    candidates = [rng.random() < 0.8 for _ in range(tests)]
    changed = rng.sample(range(n), min(n, rng.choice([0, 1, 1, 2, 5, max(1, n // 10)])))
    return encode_request(digests, callees, roots, candidates, changed, rng.randbytes(32), rng.random() < 0.5, rng.randrange(1 << 62))


def run_random(work: Path, component: Path, count: int, seed: int, large: int, large_size: int) -> dict:
    """Random graphs through the component directly, then `cacheplan diff` over the requests and replies."""
    import random
    rng = random.Random(seed)
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    made: list[Path] = []
    refused = 0
    totals = {"nodes": 0, "tests": 0, "reused": 0}
    zig_seconds = 0.0
    for i in range(count):
        size = rng.choice([1, 2, 3, 5, 8, 20, 60, 200, 1000]) if i < count - large else large_size
        shape = rng.choice(["dag", "layers", "cyclic"])
        request = random_request(rng, size, rng.choice([0.3, 1.0, 2.5]), rng.choice([1, 3, 10, 40]), shape)
        path = work / f"r{i}.req"
        path.write_bytes(request)
        t = time.time()
        proc = subprocess.run([str(component), "--request", str(path)], capture_output=True)
        zig_seconds += time.time() - t
        if proc.returncode != 0:
            refused += 1
            continue
        path.with_suffix(".rep").write_bytes(proc.stdout)
        summary = request_summary(request)
        totals["nodes"] += summary["nodes"]
        totals["tests"] += summary["tests"]
        totals["reused"] += reused_count(proc.stdout)
        made.append(path)
    agree, differ, certified, lines, lean_seconds = lean_diff(made)
    return {"requests": len(made), "refused": refused, "agree": agree, "differ": differ, "certified": certified, "lines": lines,
            "zig_seconds": zig_seconds, "lean_seconds": lean_seconds, **totals}


def command_random(args: argparse.Namespace) -> int:
    real_dir = real_components()
    manifest = json.loads((real_dir / "cache-plan.json").read_text())
    started = time.time()
    r = run_random(Path(args.work) / "random", real_dir / manifest["artifact"], args.count, args.seed, args.large, args.large_size)
    for line in r["lines"][:20]:
        print(line)
    print(f"{args.count} random requests (seed {args.seed}, {args.large} of {args.large_size} nodes): {r['agree']} agree, {r['differ']} differ, {r['certified']} certified, {r['refused']} refused by the component; {r['nodes']} nodes, {r['tests']} tests, {r['reused']} reused; component {r['zig_seconds']:.1f} s, Lean {r['lean_seconds']:.1f} s; {time.time() - started:.0f} s")
    return 1 if r["differ"] else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", default=str(ROOT / "zig-out" / "bin" / "selka"))
    parser.add_argument("--work", default=str(HOME / ".cache" / "selka" / "certs-c8" / "plan-diff"))
    sub = parser.add_subparsers(dest="command", required=True)
    c = sub.add_parser("capture")
    c.add_argument("--entries", nargs="*", default=[])
    c.add_argument("--all-of", help="copy this directory (for example tests/lang) and run every *.selka in it")
    c.add_argument("--limit", type=int, default=0)
    c.add_argument("--jobs", type=int, default=3)
    c.add_argument("--timeout", type=int, default=900)
    d = sub.add_parser("compare")
    d.add_argument("--jobs", type=int, default=4)
    pr = sub.add_parser("project", help="a chain of edits to a real project, `selka test` after each")
    pr.add_argument("target", choices=["selka", "eda"])
    pr.add_argument("--corpus", default=str(HOME / ".cache" / "selka" / "certs-c8" / "replay-diff-work" / "corpus"))
    pr.add_argument("--steps", type=int, default=12)
    pr.add_argument("--seed", type=int, default=1)
    pr.add_argument("--timeout", type=int, default=3600)
    sub.add_parser("changed", help="the host's `changed` list on consecutive real requests (needs a capture)")
    r = sub.add_parser("random", help="random graphs: cyclic, acyclic, layered, with repeated edges and equal digests")
    r.add_argument("--count", type=int, default=2000)
    r.add_argument("--seed", type=int, default=1)
    r.add_argument("--large", type=int, default=3, help="how many of the requests are large")
    r.add_argument("--large-size", type=int, default=100000)
    args = parser.parse_args()
    return {"capture": command_capture, "compare": command_compare, "random": command_random, "changed": command_changed, "project": command_project}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
