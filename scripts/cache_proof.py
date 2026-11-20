#!/usr/bin/env python3
"""The gate action `cache-proof` (docs/audits/provable-cache-plan-2026-10-26.md, package K4).

    python3 scripts/cache_proof.py --compiler zig-out/bin/selka [--sample-every N] [--random N] [--jobs N]

It checks the Lean model of the build cache in `proofs/cache` and compares the Lean test planner with the Zig one on real
requests, and fails, never skips, when it cannot:

1. **The proofs.** `lake build` in `proofs/cache` (incremental: it rebuilds only what a change under `proofs/cache` touched).
   An `error`, a `sorry`, or any theorem that depends on an axiom other than `propext`, `Classical.choice` and `Quot.sound`
   (the `#assert_axioms` audit in `Cache/Check.lean` is part of the build) fails it.
2. **The fixtures.** `proofs/cache/fixtures/check.sh`: seven planner requests (four recorded, three random) with the component's replies, and the
   replay rule on a scratch directory changed five ways (and a stat tuple left over changed bytes, which must be reported).
3. **The planner differential on real requests.** Every N-th entry of `tests/lang` (a copy, so nothing in the repository
   changes) runs `selka test` through a recording component directory in four steps (cold, rerun, one integer literal
   raised, put back); each request the test runner sends the planner and the cache-plan component's reply are kept, and
   `cacheplan diff` must agree with every reply on the reuse decision, the batches, the strongly connected groups and the
   reverse index. `cacheplan changed` checks, on the pairs of consecutive requests across an edit, a necessary condition of
   the host's list of changed nodes, and that dropping a genuinely new node from the list is caught.
4. **The planner differential on random graphs.** Random requests (cyclic, acyclic, layered, repeated edges, equal digests,
   one of 100 000 nodes) go to the component and to `cacheplan diff`.

The replay differential (`scripts/cache_replay_diff.py`) is not part of the action: it waits for the record format of K3.

Lean is a developer and gate tool only. `lake` is found through `SELKA_LAKE` or `$HOME/.elan/bin/lake`.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
PROOFS = ROOT / "proofs" / "cache"
CACHEPLAN = PROOFS / ".lake" / "build" / "bin" / "cacheplan"


class ProofError(Exception):
    """The action cannot certify: a tool is missing or a check failed."""


def find_lake(env=None) -> str:
    """The `lake` executable: `SELKA_LAKE`, else `$HOME/.elan/bin/lake`. A missing Lean fails the action."""
    env = os.environ if env is None else env
    chosen = env.get("SELKA_LAKE") or os.path.join(env.get("HOME", ""), ".elan", "bin", "lake")
    if os.path.isfile(chosen) and os.access(chosen, os.X_OK):
        return chosen
    raise ProofError(
        f"cache-proof: the Lean build tool `lake` is missing ({chosen}). Install elan with the toolchain pinned in "
        "proofs/cache/lean-toolchain (see proofs/ownership/README.md) or point SELKA_LAKE at lake. "
        "The complete gate needs Lean for this action and never skips it.")


def tool_env(lake: str) -> dict:
    """The environment for `lake`: its directory first on `PATH`, so the elan shim finds its siblings."""
    env = dict(os.environ)
    env["PATH"] = os.path.dirname(lake) + os.pathsep + env.get("PATH", "")
    return env


def lake_build(lake: str, run=subprocess.run) -> None:
    """`lake build` in proofs/cache; a failure, an `error`, or a `sorry` fails the action."""
    built = run([lake, "build"], cwd=PROOFS, env=tool_env(lake), capture_output=True, text=True, errors="replace")
    text = built.stdout + built.stderr
    if built.returncode != 0 or "sorry" in text or re.search(r"(^|\n)error", text):
        tail = "\n".join(text.splitlines()[-40:])
        raise ProofError(f"cache-proof: `lake build` in proofs/cache failed (exit {built.returncode}):\n{tail}")


def run_fixtures(run=subprocess.run) -> None:
    """The fixture script of the Lean project; it prints `fixtures ok` last."""
    done = run(["sh", str(PROOFS / "fixtures" / "check.sh")], cwd=ROOT, env=dict(os.environ, CACHEPLAN=str(CACHEPLAN)), capture_output=True, text=True, errors="replace")
    if done.returncode != 0 or "fixtures ok" not in done.stdout:
        raise ProofError("cache-proof: proofs/cache/fixtures/check.sh failed:\n" + (done.stdout + done.stderr)[-2000:])


def sample(entries: list[Path], every: int) -> list[Path]:
    """Every `every`-th entry of the sorted list, starting with the first: the same sample on every run."""
    return sorted(entries)[:: max(1, every)]


def planner_differential(compiler: Path, every: int, jobs: int, scratch: Path, real_dir: Path) -> dict:
    """Capture requests from a sample of tests/lang, compare them with the component's replies, check the `changed` lists."""
    import argparse as ap
    from concurrent.futures import ThreadPoolExecutor
    import cache_plan_diff as diff
    corpus = scratch / "corpus"
    shutil.copytree(ROOT / "tests" / "lang", corpus, symlinks=True)
    entries = sample(list(corpus.glob("*.selka")), every)
    components = diff.component_directory(scratch, real_dir)
    arguments = ap.Namespace(compiler=str(compiler), timeout=900)
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        results = list(pool.map(lambda e: diff.capture_entry(arguments, e, corpus, scratch, components), entries))
    index = {"entries": results}
    requests = [r for r in sorted((scratch / "cases").glob("*/capture/*.req")) if r.with_suffix(".rep").exists()]
    if not requests:
        raise ProofError("cache-proof: the recording planner saw no request: the test runner did not use SELKA_COMPONENT_DIR")
    agree, differ, certified, lines, seconds = diff.lean_diff(requests)
    summaries = [diff.request_summary(r.read_bytes()) for r in requests]
    reused = sum(diff.reused_count(r.with_suffix(".rep").read_bytes()) for r in requests)
    changed = diff.run_changed(scratch, index)
    return {"entries": len(entries), "requests": len(requests), "warm": sum(1 for s in summaries if s["prior"]), "tests": sum(s["tests"] for s in summaries),
            "reused": reused, "agree": agree, "differ": differ, "certified": certified, "lines": lines, "lean_seconds": seconds, "changed": changed}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--sample-every", type=int, default=12)
    parser.add_argument("--random", type=int, default=400)
    parser.add_argument("--random-large", type=int, default=100000)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args(argv)
    started = time.monotonic()
    compiler = Path(args.compiler).resolve()
    import cache_plan_diff as diff
    # the gate names the components of its install prefix in SELKA_COMPONENT_DIR; the compiler it runs sits in the build cache
    components = Path(os.environ["SELKA_COMPONENT_DIR"]) if os.environ.get("SELKA_COMPONENT_DIR") else compiler.parent.parent / "libexec" / "selka" / "components"
    scratch = Path(tempfile.mkdtemp(prefix="cache-proof-", dir=os.environ.get("TMPDIR") or None))
    try:
        lake = find_lake()
        lake_build(lake)
        built = time.monotonic()
        if not CACHEPLAN.is_file():
            raise ProofError(f"cache-proof: `lake build` produced no {CACHEPLAN}")
        run_fixtures()
        planner = planner_differential(compiler, args.sample_every, args.jobs, scratch, components)
        problems = list(planner["lines"][:10])
        changed = planner["changed"]
        problems += changed["problems"][:10]
        if planner["differ"] or planner["certified"] != planner["requests"]:
            problems.append(f"cache-proof: {planner['differ']} of {planner['requests']} recorded requests differ from the component's reply, {planner['requests'] - planner['certified']} uncertified")
        if changed["violations"] or changed["caught"] != changed["controls"]:
            problems.append(f"cache-proof: the changed-list check found {changed['violations']} uncovered nodes and caught {changed['caught']} of {changed['controls']} dropped ones")
        manifest = json.loads((components / "cache-plan.json").read_text())
        rnd = diff.run_random(scratch / "random", components / manifest["artifact"], args.random, args.seed, 1, args.random_large)
        problems += rnd["lines"][:10]
        if rnd["differ"] or rnd["certified"] != rnd["requests"] or rnd["refused"]:
            problems.append(f"cache-proof: {rnd['differ']} of {rnd['requests']} random requests differ from the component's reply ({rnd['refused']} refused)")
        if problems:
            raise ProofError("\n".join(problems))
    except ProofError as error:
        print(str(error), file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    print(f"cache-proof: lake build ok (no error, no sorry, axioms audited, {built - started:.1f} s); fixtures ok; planner: "
          f"{planner['requests']} recorded requests ({planner['warm']} with a retained index, {planner['tests']} tests, {planner['reused']} reused) from {planner['entries']} "
          f"tests/lang entries agree with the component; changed lists: {changed['pairs']} pairs ok, {changed['caught']}/{changed['controls']} controls caught; "
          f"{rnd['requests']} random graphs ({rnd['nodes']} nodes) agree; {time.monotonic() - started:.1f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
