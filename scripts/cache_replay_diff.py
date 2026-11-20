#!/usr/bin/env python3
"""Differential of the Lean replay rule (`lake exe cacheplan replay`) against the Zig replay on real builds.

Package K4 of docs/audits/provable-cache-plan-2026-10-26.md.  Python is allowed here (a developer script);
nothing in src/ or the install graph runs it.

A replay of `selka build`/`run` (`src/core/build_replay.zig`) serves the program an identical earlier build produced
when every input the build read is as it was.  This script drives the cases and the edit chains of
`scripts/audit_cache_reads.py` (packages K0 and K1) and, just before every *warm* build, asks `cacheplan replay` what
the replay rule says about each record in the build's cache directory, with the live disk and the build's own
environment.  Afterwards it compares that verdict with what the Zig compiler did (`selka-core: cache: replayed`).

A record decides a replay only if its key (compiler, flags, entry, toolchain, keyed environment) is the warm build's;
the key is not recomputed here.  It is read off the cache directory: a build that did not replay writes a record
named `KEY.INPUTS`, and the warm build's key is that `KEY`.

Per warm build the outcomes are:

    agree-replayed     Zig replayed, and some record of its key is unchanged on disk (the specification agrees)
    agree-miss         Zig did not replay, and no record of its key is unchanged (or the key changed)
    conservative       Zig did not replay though a record of its key is unchanged: allowed (the toolchain, the
                       program entry or the environment contract can refuse); listed for triage
    outside-record     a conservative miss of a case that changes the replay key or the toolchain, which the record's
                       own input list does not carry (cases named env-*, link-env-*, toolchain-*)
    no-report          the warm build printed no cache line (it failed first); nothing to compare
    VIOLATION          Zig replayed and no record of its key is unchanged on disk: the guarantee failed
    STALE              the stat tuple of a recorded file was unchanged and its bytes were not (E2 failed)

    cache_replay_diff.py mutate --work DIR [--cases SUBSTR ...] [--jobs N]
    cache_replay_diff.py fuzz   --work DIR --target selka|eda|selka-test --steps N --seed S
    cache_replay_diff.py report --work DIR
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOME = Path(os.environ.get("HOME", "/"))
sys.path.insert(0, str(ROOT / "scripts"))
import audit_cache_reads as k0  # noqa: E402  (the K0/K1 harness: its cases, runner and edit chains)

CACHEPLAN = ROOT / "proofs" / "cache" / ".lake" / "build" / "bin" / "cacheplan"
STDLIB = ROOT / "src" / "stdlib"
LOCK = threading.Lock()
TRACES: list[dict] = []
CHECKPOINT = "SELKA_HOST_LIMIT_CHECKPOINT"


def records(cache: Path) -> dict[str, int]:
    """The replay records of a cache directory, with the modification time of each."""
    folder = cache / "replay-v1"
    if not folder.is_dir():
        return {}
    return {p.name: p.stat().st_mtime_ns for p in folder.iterdir() if p.is_file() and not p.name.endswith(".partial")}


def record_variable(path: Path, name: str) -> str | None:
    """The value of an environment variable a record keyed, if it did."""
    try:
        payload = json.loads(json.loads(path.read_text())["payload"])
    except (OSError, ValueError, KeyError):
        return None
    for item in payload.get("inputs", []):
        if item.get("kind") == "variable" and item.get("name") == name:
            return item.get("value")
    return None


def lean_replay(record: Path, env: dict[str, str], cwd: Path) -> dict:
    """Ask the Lean replay rule about one record under the build's environment."""
    lean_env = dict(env)
    # The compiler sets this variable itself, from its memory ceiling; a build under the same ceiling sets the same
    # value, so the record's own value stands for it unless the case changes the ceiling.
    recorded = record_variable(record, CHECKPOINT)
    if recorded is not None and "SELKA_HOST_MEMORY_LIMIT" not in env:
        lean_env[CHECKPOINT] = recorded
    started = time.time()
    proc = subprocess.run([str(CACHEPLAN), "replay", str(record), "--stdlib", str(STDLIB)], env=lean_env, cwd=cwd, capture_output=True, text=True)
    seconds = time.time() - started
    lines = proc.stdout.strip().splitlines()
    verdict = next((l for l in reversed(lines) if l.startswith("verdict ")), "")
    fields = dict(re.findall(r"(\w+)=(\w+)", verdict))
    return {
        "record": record.name,
        "status": proc.returncode,
        "truth": fields.get("truth") == "true",
        "zig": fields.get("zig") == "true",
        "program": fields.get("program_truth") == "true",
        "stale": int(fields.get("stale", "0")) if fields else 0,
        "inputs": int(fields.get("inputs", "0")) if fields else 0,
        "changed": [l for l in lines if l.startswith(("input ", "STALE "))][:6],
        "seconds": seconds,
        "error": proc.stderr.strip()[:300] if proc.returncode not in (0, 1, 3) else "",
    }


def classify(replayed: bool, before: dict[str, int], after: dict[str, int], lean: list[dict]) -> tuple[str, str]:
    """Compare what Zig did with what the replay rule says about the records that existed before the build."""
    written = [n for n in after if after[n] != before.get(n)]
    warm_keys = {n.split(".")[0] for n in written}
    by_name = {r["record"]: r for r in lean}
    if any(r["stale"] for r in lean):
        return "STALE", "a recorded stat tuple was unchanged while its bytes changed"
    unchanged = [r for r in lean if r["truth"] and r["program"]]
    if replayed:
        if unchanged:
            return "agree-replayed", ""
        return "VIOLATION", "replayed though no record is unchanged on disk"
    if not unchanged:
        return "agree-miss", ""
    if warm_keys and not any(r["record"].split(".")[0] in warm_keys for r in unchanged):
        return "agree-miss", "the key changed"
    return "conservative", "an unchanged record exists for the key" if warm_keys else "an unchanged record exists; the warm key is unknown"


OUTSIDE_RECORD = ("env-", "link-env-", "toolchain-")


def refine(case: str, outcome: str, why: str) -> tuple[str, str]:
    """A miss the record's own inputs cannot explain is one of three kinds the case name gives away: a keyed environment
    variable newly set (the key covers it; a variable unset at recording is not an input of the record), a placement
    variable that moves the tool memo, or a toolchain file (the toolchain identity covers it, the record lists none)."""
    if outcome == "conservative" and case.startswith(OUTSIDE_RECORD):
        return "outside-record", "the change is in the replay key or the toolchain identity, which the record's input list does not carry"
    return outcome, why


def install_trace() -> None:
    """Wrap the K0 runner so that every warm build of `build` or `run` is checked against the replay rule first."""
    original = k0.Runner.observe

    def traced(self, case, case_dir, project, command, env, cache, label, extra, compiler=None):
        expanded = self.expand(command, project, case_dir, case_dir / "out-x")
        kind = expanded[0]
        if label not in ("warm", "base") or kind not in ("build", "run") or "--no-cache" in extra or any(a.startswith("--cache-dir") for a in expanded):
            return original(self, case, case_dir, project, command, env, cache, label, extra, compiler)
        before = records(cache)
        lean = [lean_replay(cache / "replay-v1" / name, env, project) for name in sorted(before)]
        observation = original(self, case, case_dir, project, command, env, cache, label, extra, compiler)
        after = records(cache)
        replayed = observation.reuse == "replayed"
        if observation.reuse == "unknown":
            outcome, why = "no-report", "the build printed no cache line (it failed before the cache, or the command has none)"
        else:
            outcome, why = refine(case.name, *classify(replayed, before, after, lean))
        trace = {
            "case": case.name, "label": label, "zig_reuse": observation.reuse, "records": len(before), "outcome": outcome, "why": why,
            "lean": [{k: v for k, v in r.items() if k != "record"} | {"record": r["record"][:16]} for r in lean],
        }
        with LOCK:
            TRACES.append(trace)
        return observation

    k0.Runner.observe = traced


def make_runner(args: argparse.Namespace) -> k0.Runner:
    return k0.Runner(argparse.Namespace(compiler=args.compiler, zig=args.zig, work=args.work, other_compiler=None))


def ensure_corpus(args: argparse.Namespace) -> None:
    corpus = Path(args.work) / "corpus"
    if corpus.is_dir():
        return
    subprocess.run([sys.executable, str(ROOT / "scripts" / "audit_cache_reads.py"), "--work", args.work, "--compiler", args.compiler, "--zig", args.zig, "corpus"], check=True)


def write_traces(args: argparse.Namespace, label: str) -> Path:
    out = Path(args.work) / "replay-diff"
    out.mkdir(parents=True, exist_ok=True)
    path = out / f"{label}.jsonl"
    with open(path, "w") as sink:
        for trace in TRACES:
            sink.write(json.dumps(trace) + "\n")
    return path


def summarize(traces: list[dict]) -> dict:
    counts: dict[str, int] = {}
    for t in traces:
        counts[t["outcome"]] = counts.get(t["outcome"], 0) + 1
    return counts


def command_mutate(args: argparse.Namespace) -> int:
    ensure_corpus(args)
    install_trace()
    runner = make_runner(args)
    cases = [c for c in k0.all_cases(Path(args.zig), False) if c.command[0] in ("build", "run") and not c.other_compiler]
    if args.cases:
        cases = [c for c in cases if any(sel in c.name or sel == c.group for sel in args.cases)]
    print(f"{len(cases)} build/run cases", flush=True)
    results = []

    def one(case):
        try:
            return case.name, runner.run_case(case)
        except Exception as error:  # a broken case is reported, never hidden
            return case.name, {"verdict": "HARNESS ERROR", "why": f"{type(error).__name__}: {error}"}

    started = time.time()
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for name, result in pool.map(one, cases):
            results.append((name, result))
            print(f"  {name:40s} {result['verdict']}", flush=True)
    path = write_traces(args, args.label)
    counts = summarize(TRACES)
    stale = [n for n, r in results if r["verdict"].startswith("STALE")]
    print(f"{len(results)} cases in {time.time() - started:.0f} s; {len(TRACES)} warm builds traced: {counts}; K0 stale verdicts: {len(stale)}; traces in {path}")
    return 1 if counts.get("VIOLATION") or counts.get("STALE") else 0


def command_fuzz(args: argparse.Namespace) -> int:
    ensure_corpus(args)
    install_trace()
    ns = argparse.Namespace(compiler=args.compiler, zig=args.zig, work=args.work, other_compiler=None, evidence=str(Path(args.work) / "fuzz-evidence"), target=args.target, steps=args.steps, seed=args.seed)
    status = k0.command_fuzz(ns)
    path = write_traces(args, f"fuzz-{args.target}-{args.seed}")
    print(f"{len(TRACES)} warm builds traced: {summarize(TRACES)}; traces in {path}")
    return status


def command_report(args: argparse.Namespace) -> int:
    traces = []
    for path in sorted((Path(args.work) / "replay-diff").glob("*.jsonl")):
        rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
        for row in rows:
            row["outcome"], row["why"] = refine(row["case"], row["outcome"], row["why"])
        print(f"{path.name}: {len(rows)} warm builds {summarize(rows)}")
        traces += rows
    print(f"total {len(traces)} warm builds {summarize(traces)}")
    seconds = [r["seconds"] for t in traces for r in t["lean"]]
    if seconds:
        print(f"{len(seconds)} records checked by Lean, total {sum(seconds):.1f} s, max {max(seconds):.2f} s; {sum(r['inputs'] for t in traces for r in t['lean'])} inputs")
    for t in traces:
        if t["outcome"] in ("VIOLATION", "STALE", "conservative", "outside-record"):
            print(t["outcome"], t["case"], t["zig_reuse"], t["why"], [r["changed"][:2] for r in t["lean"] if not r["truth"]][:1])
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", default=str(ROOT / "zig-out" / "bin" / "selka"))
    parser.add_argument("--zig", default=os.environ.get("ZIG", "zig"))
    parser.add_argument("--work", default=str(HOME / ".cache" / "selka" / "certs-c8" / "replay-diff-work"))
    sub = parser.add_subparsers(dest="command", required=True)
    m = sub.add_parser("mutate")
    m.add_argument("--cases", nargs="*", default=[])
    m.add_argument("--jobs", type=int, default=3)
    m.add_argument("--label", default="k0-table")
    f = sub.add_parser("fuzz")
    f.add_argument("--target", choices=["selka", "eda", "selka-test"], default="selka")
    f.add_argument("--steps", type=int, default=40)
    f.add_argument("--seed", type=int, default=1)
    sub.add_parser("report")
    args = parser.parse_args()
    return {"mutate": command_mutate, "fuzz": command_fuzz, "report": command_report}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
