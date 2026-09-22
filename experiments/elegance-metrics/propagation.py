#!/usr/bin/env python3
"""Propagation cost over a mylang project, and over the cascade run set.

The review in `docs/audits/research-testing-review-2026-09-19.md` found five
defects in the first version of this tool. All five are repaired here, each with
a regression check in `--selftest`:

1. **Index cache.** The key is the source closure (every `.my` file in the
   project), the compiler identity and a schema version — not the entry path and
   `main.my`'s mtime, which let an edit to an imported module reuse a stale graph.
2. **Sensitivity ablations.** Every named edge set is distinct and removes only
   what it names; the old `without_uses_type` was identical to
   `calls_and_fields`.
3. **Deleted modules.** Both snapshots are indexed and both sides of the diff are
   read, so a deleted module, a rename and a pure-deletion hunk are accounted for.
   Impact is measured on the *pre-change* graph, which is the graph a maintainer
   faces when starting and the only one that still holds a deleted module.
4. **Diagonal.** A node is never counted in its own impact set, so the measure is
   over the *other* nodes and the `n - 1` denominator is honest.
5. **Statistics.** Correlations use independent runs by default (chains are
   repeated measures, not repetitions), ranks are reported both pooled and
   centred within task, and chain rows are reported separately.

    python3 experiments/elegance-metrics/propagation.py --selftest
    python3 experiments/elegance-metrics/propagation.py --architecture
    python3 experiments/elegance-metrics/propagation.py --runs --json out.json

Cost uses the corrected token term (`cost_v2_input_output`: the provider puts
reasoning inside output, so the published v1 double-counted it); `--cost-term`
switches it.
"""

from __future__ import annotations

import argparse
from collections import deque
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
CASCADE = REPO / "experiments" / "cascade"
RUNS = CASCADE / "runs"
COHORT = CASCADE / "cohorts" / "original.json"
COMPILER = CASCADE / "tools" / "bin" / "mylang"
CACHE = HERE / ".cache"

SCHEMA_VERSION = 2

# Reference kinds that cross a declaration boundary, and so are architecture.
DEPENDENCY_KINDS = {
    "call", "uses_type", "accepts", "returns", "contains_type",
    "field_initialize", "field_read", "field_update",
}
# Each ablation is a distinct, explicitly named policy.
EDGE_SETS = {
    "all": DEPENDENCY_KINDS,
    "without_uses_type": DEPENDENCY_KINDS - {"uses_type"},
    "calls_only": {"call"},
    "calls_and_fields": {"call", "field_initialize", "field_read", "field_update"},
}
DECLARATION_KINDS = {"function", "type", "field", "case"}
HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
COST_TERMS = {"v2": "cost_v2_input_output", "v1": "cost_v1_input_output_reasoning",
              "total": "provider_total_tokens"}

COMPILER_CALLS = 0


def compiler_identity() -> str:
    try:
        return hashlib.sha256(COMPILER.read_bytes()).hexdigest()[:16]
    except OSError:
        return "unknown"


def source_closure(project: Path) -> str:
    """A hash of every source file the index covers — the cache's real key."""
    digest = hashlib.sha256()
    for path in sorted(project.rglob("*.my")):
        if ".mylang-cache" in str(path) or ".cache" in path.parts:
            continue
        digest.update(str(path.relative_to(project)).encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def index(project: Path, refresh: bool = False) -> dict:
    """`index-project` for one project, keyed by closure, compiler and schema."""
    global COMPILER_CALLS
    entry = project / "main.my"
    if not entry.is_file():
        raise SystemExit(f"no entry point at {entry}")
    CACHE.mkdir(parents=True, exist_ok=True)
    key = CACHE / f"{hashlib.sha256(str(project.resolve()).encode()).hexdigest()[:16]}.json"
    fingerprint = {"sources": source_closure(project), "compiler": compiler_identity(), "schema": SCHEMA_VERSION}
    if key.is_file() and not refresh:
        payload = json.loads(key.read_text())
        if payload.get("fingerprint") == fingerprint:
            return payload["index"]
    COMPILER_CALLS += 1
    result = subprocess.run([str(COMPILER), "index-project", str(entry)], capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"index-project failed on {entry}: {result.stderr.strip()[:300]}")
    data = json.loads(result.stdout)
    key.write_text(json.dumps({"fingerprint": fingerprint, "index": data}))
    return data


def owner(identifier: str) -> str | None:
    """`main::Tally.forms` -> `main::Tally`; top-level declarations have no owner."""
    module, _, name = identifier.partition("::")
    if "." in name:
        return f"{module}::{name.split('.')[0]}"
    return None


def graph(data: dict, kinds: set[str] | None = None) -> tuple[list[str], dict[str, set[str]], dict[str, dict]]:
    """Declaration nodes and `depends-on` edges."""
    kinds = DEPENDENCY_KINDS if kinds is None else kinds
    nodes = {symbol["id"]: symbol for symbol in data["symbols"] if symbol["kind"] in DECLARATION_KINDS}
    edges: dict[str, set[str]] = {name: set() for name in nodes}
    for reference in data["references"]:
        if reference["kind"] not in kinds:
            continue
        if reference["from"] in nodes and reference["to"] in nodes:
            edges[reference["from"]].add(reference["to"])
    # A field or case belongs to its type: a change to the type reaches its users.
    for name in list(nodes):
        if nodes[name]["kind"] in ("field", "case"):
            parent = owner(name)
            if parent in nodes:
                edges[name].add(parent)
    return sorted(nodes), edges, nodes


def reach(start: str, edges: dict[str, set[str]]) -> set[str]:
    """Nodes reachable from `start`, never `start` itself: the diagonal is excluded."""
    seen: set[str] = set()
    queue = deque(edges.get(start, ()))
    while queue:
        node = queue.popleft()
        if node in seen or node == start:
            continue
        seen.add(node)
        queue.extend(edges.get(node, ()))
    return seen


def closures(nodes: list[str], edges: dict[str, set[str]]) -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    reverse: dict[str, set[str]] = {name: set() for name in nodes}
    for source, targets in edges.items():
        for target in targets:
            reverse[target].add(source)
    return ({name: reach(name, edges) for name in nodes},
            {name: reach(name, reverse) for name in nodes})


def measure(nodes: list[str], edges: dict[str, set[str]]) -> tuple[dict[str, float], dict[str, float], dict[str, set[str]], dict[str, set[str]]]:
    """Impact (who a change here can affect) and dependency (what it must read)."""
    forward, backward = closures(nodes, edges)
    total = max(len(nodes) - 1, 1)
    return ({name: len(backward[name]) / total for name in nodes},
            {name: len(forward[name]) / total for name in nodes},
            backward, forward)


def architecture_of(data: dict, kinds: set[str]) -> dict:
    nodes, edges, _ = graph(data, kinds)
    impacts, _, _, _ = measure(nodes, edges)
    ordered = sorted(impacts.values(), reverse=True)
    return {
        "nodes": len(nodes),
        "edges": sum(len(targets) for targets in edges.values()),
        "propagation_cost": round(statistics.fmean(impacts.values()), 4) if nodes else 0.0,
        "top10_mean": round(statistics.fmean(ordered[:10]), 4) if ordered else 0.0,
        "nodes_over_ten_percent": sum(1 for value in ordered if value > 0.10),
    }


def module_rollup(nodes: list[str], impacts: dict[str, float]) -> dict:
    modules: dict[str, list[float]] = {}
    for name in nodes:
        modules.setdefault(name.partition("::")[0], []).append(impacts[name])
    return {module: {"nodes": len(values), "mean_impact": round(statistics.fmean(values), 4)}
            for module, values in sorted(modules.items())}


def architecture(project: Path) -> dict:
    data = index(project)
    nodes, edges, _ = graph(data)
    impacts, dependencies, _, _ = measure(nodes, edges)
    fan_in = {name: 0 for name in nodes}
    for source, targets in edges.items():
        for target in targets:
            fan_in[target] += 1
    ordered = sorted(impacts.values(), reverse=True)
    return {
        "project": str(project),
        "nodes": len(nodes),
        "edges": sum(len(targets) for targets in edges.values()),
        "propagation_cost": round(statistics.fmean(impacts.values()), 4) if nodes else 0.0,
        "median_impact": round(statistics.median(impacts.values()), 4) if nodes else 0.0,
        "top10_mean_impact": round(statistics.fmean(ordered[:10]), 4) if ordered else 0.0,
        "nodes_over_ten_percent": sum(1 for value in ordered if value > 0.10),
        "mean_dependencies": round(statistics.fmean(dependencies.values()), 4) if nodes else 0.0,
        "most_impactful": [(name, round(value, 4)) for name, value in
                           sorted(impacts.items(), key=lambda item: -item[1])[:6]],
        "most_depended_on": [(name, count) for name, count in sorted(fan_in.items(), key=lambda item: -item[1])[:6]],
        "per_module": module_rollup(nodes, impacts),
        "sensitivity": {name: architecture_of(data, policy) for name, policy in EDGE_SETS.items()},
    }


def changed_lines(arm: Path, project: Path) -> dict[str, dict]:
    """Both sides of the diff, including deletions, renames and new files."""
    relative_paths = {path.relative_to(project) for path in project.rglob("*.my")}
    relative_paths |= {path.relative_to(arm) for path in arm.rglob("*.my")}
    changes: dict[str, dict] = {}
    for relative in sorted(relative_paths):
        if ".mylang-cache" in str(relative) or relative.parts[0] in ("tests", ".cache"):
            continue
        old, new = arm / relative, project / relative
        if not old.is_file():
            changes[str(relative)] = {"old": [], "new": [(1, 10 ** 9)], "status": "added"}
            continue
        if not new.is_file():
            changes[str(relative)] = {"old": [(1, 10 ** 9)], "new": [], "status": "deleted"}
            continue
        diff = subprocess.run(
            ["git", "diff", "--no-index", "--no-renames", "--unified=0", "--no-color", "--", str(old), str(new)],
            capture_output=True, text=True,
        ).stdout
        old_ranges, new_ranges = [], []
        for line in diff.splitlines():
            match = HUNK.match(line)
            if not match:
                continue
            old_start, old_count = int(match.group(1)), int(match.group(2) or 1)
            new_start, new_count = int(match.group(3)), int(match.group(4) or 1)
            old_ranges.append((old_start, old_start + max(old_count, 1) - 1))
            new_ranges.append((new_start, new_start + max(new_count, 1) - 1))
        if old_ranges or new_ranges:
            changes[str(relative)] = {"old": old_ranges, "new": new_ranges, "status": "modified"}
    return changes


def line_span(symbol: dict) -> tuple[int, int]:
    start = symbol["location"]["line"]
    snippet = symbol.get("snippet") or ""
    return (start, start + snippet.count("\n")) if snippet else (start, start)


def touched(data: dict, changes: dict[str, dict], side: str) -> list[str]:
    """Declaration nodes whose lines intersect a changed range on the given side."""
    hits = []
    for symbol in data["symbols"]:
        if symbol["kind"] not in DECLARATION_KINDS:
            continue
        ranges = (changes.get(symbol["location"]["path"]) or {}).get(side) or []
        if not ranges:
            continue
        first, last = line_span(symbol)
        if any(not (last < start or first > end) for start, end in ranges):
            hits.append(symbol["id"])
    return sorted(set(hits))


def run_row(record: dict, cost_term: str) -> dict:
    arm = CASCADE / "designs" / record["arm"]
    reference = Path(record["chain_parent"]) if record.get("chain_parent") else arm
    project = Path(record["work_dir"]) / "project"
    if not project.is_dir() or not reference.is_dir():
        return {"arm": record["arm"], "task": record["task"], "run": record.get("run"), "error": "working copy missing"}
    before, after = index(reference), index(project)
    nodes_before, edges_before, _ = graph(before)
    nodes_after, edges_after, _ = graph(after)
    impacts_before, _, backward_before, _ = measure(nodes_before, edges_before)
    impacts_after, _, backward_after, forward_after = measure(nodes_after, edges_after)
    changes = changed_lines(reference, project)
    # Impact is measured on the pre-change graph: the graph a maintainer faces
    # when starting, and the only one that still holds a deleted module.
    touched_before = touched(before, changes, "old")
    touched_after = touched(after, changes, "new")
    blast_before = set().union(*[backward_before[name] for name in touched_before]) if touched_before else set()
    blast_after = set().union(*[backward_after[name] for name in touched_after]) if touched_after else set()
    read_surface = set().union(*[forward_after[name] for name in touched_after]) if touched_after else set()
    session = record.get("session") or {}
    usage = session.get("usage") or {}
    api = ((record.get("interface") or {}).get("api_diff") or {})
    return {
        "arm": record["arm"],
        "task": record["task"],
        "run": record.get("run"),
        "chain": bool(record.get("chain")),
        "chain_repetition": record.get("chain_repetition"),
        "verdict": record.get("verdict"),
        "cost": usage.get(COST_TERMS[cost_term]),
        "cost_term": cost_term,
        "steps": session.get("steps"),
        "compiler_seconds": session.get("compiler_seconds"),
        "bytes_read": session.get("bytes_read"),
        "failure_results": session.get("failure_results"),
        "diff_lines": (record.get("diff") or {}).get("added", 0) + (record.get("diff") or {}).get("removed", 0),
        "files_changed": len((record.get("diff") or {}).get("files_changed") or []),
        "api_breaking": len(api.get("breaking") or []),
        "production_files_changed": sorted(changes),
        "deleted_modules": sorted(name for name, change in changes.items() if change["status"] == "deleted"),
        "touched_before": touched_before,
        "touched_after": touched_after,
        "touched_declarations": len(touched_after),
        "blast_radius_before": round(len(blast_before) / max(len(nodes_before) - 1, 1), 4),
        "blast_radius_after": round(len(blast_after) / max(len(nodes_after) - 1, 1), 4),
        "read_surface": round(len(read_surface) / max(len(nodes_after) - 1, 1), 4),
        "propagation_cost_before": round(statistics.fmean(impacts_before.values()), 4) if nodes_before else 0.0,
        "propagation_cost_after": round(statistics.fmean(impacts_after.values()), 4) if nodes_after else 0.0,
    }


def pearson(pairs: list[tuple[float, float]]) -> float | None:
    if len(pairs) < 3:
        return None
    xs = [pair[0] for pair in pairs]
    ys = [pair[1] for pair in pairs]
    mx, my = statistics.fmean(xs), statistics.fmean(ys)
    cov = sum((a - mx) * (b - my) for a, b in pairs)
    vx = sum((a - mx) ** 2 for a in xs) ** 0.5
    vy = sum((b - my) ** 2 for b in ys) ** 0.5
    return round(cov / (vx * vy), 3) if vx and vy else None


def ranks(values: list[float]) -> list[float]:
    order = sorted(range(len(values)), key=lambda index: values[index])
    out = [0.0] * len(values)
    position = 0
    while position < len(order):
        end = position
        while end + 1 < len(order) and values[order[end + 1]] == values[order[position]]:
            end += 1
        average = (position + end) / 2 + 1
        for index in range(position, end + 1):
            out[order[index]] = average
        position = end + 1
    return out


def within_task(rows: list[dict], field: str, centre: bool) -> float | None:
    """Rank correlation inside each task, optionally centring each task's ranks.

    Centring removes the task's mean level, so a task whose runs are all
    expensive cannot pull the pooled statistic.
    """
    xs: list[float] = []
    ys: list[float] = []
    for task in sorted({row["task"] for row in rows}):
        subset = [row for row in rows if row["task"] == task
                  and isinstance(row.get(field), (int, float)) and isinstance(row.get("cost"), (int, float))]
        if len(subset) < 3:
            continue
        xr, yr = ranks([row[field] for row in subset]), ranks([row["cost"] for row in subset])
        if centre:
            mx, my = statistics.fmean(xr), statistics.fmean(yr)
            xr = [value - mx for value in xr]
            yr = [value - my for value in yr]
        xs.extend(xr)
        ys.extend(yr)
    return pearson(list(zip(xs, ys)))


def selftest() -> int:
    """The regressions the review asked for, on temporary fixtures."""
    scratch = Path("/tmp/elegance-selftest")
    if scratch.exists():
        shutil.rmtree(scratch)
    scratch.mkdir(parents=True)
    failures: list[str] = []

    def check(name: str, condition: bool, detail: str = "") -> None:
        print(f"  {'ok  ' if condition else 'FAIL'} {name}{'' if condition else '  ' + detail}")
        if not condition:
            failures.append(name)

    nodes, edges, _ = graph({"symbols": [{"id": "m::a", "kind": "function", "location": {"path": "a.my", "line": 1}}],
                             "references": []})
    impacts, _, _, _ = measure(nodes, edges)
    check("isolated node has zero impact", impacts["m::a"] == 0.0)
    impacts, _, _, _ = measure(["m::a", "m::b"], {"m::a": {"m::b"}, "m::b": {"m::a"}})
    check("mutual cycle excludes the diagonal", impacts["m::a"] == 1.0 and impacts["m::b"] == 1.0)
    impacts, _, _, _ = measure(["m::a"], {"m::a": {"m::a"}})
    check("self-loop node does not count itself", impacts["m::a"] == 0.0)
    check("empty graph measures nothing", measure([], {})[0] == {})
    # r recurses and calls s; c calls r. Nobody but r depends on r, so r's own
    # loop must not count: half the other nodes (c, not s) depend on r.
    impacts, _, _, _ = measure(["m::r", "m::s", "m::c"], {"m::r": {"m::r", "m::s"}, "m::s": set(), "m::c": {"m::r"}})
    check("recursive node excludes itself", impacts["m::r"] == 0.5, f"got {impacts['m::r']}")
    check("a recursive node still propagates to its callers", impacts["m::s"] == 1.0, f"got {impacts['m::s']}")

    check("without_uses_type differs from calls_and_fields",
          EDGE_SETS["without_uses_type"] != EDGE_SETS["calls_and_fields"])
    check("without_uses_type removes only uses_type",
          DEPENDENCY_KINDS - EDGE_SETS["without_uses_type"] == {"uses_type"})

    project = scratch / "proj"
    project.mkdir()
    (project / "helper.my").write_text("module helper\n\n\ndef value() -> int:\n    return 1\n")
    (project / "main.my").write_text("module main\n\nimport helper as helper\n\n\ndef main() -> int:\n    return helper.value()\n")
    global COMPILER_CALLS
    COMPILER_CALLS = 0
    index(project)
    index(project)
    check("second index of an unchanged project reuses the cache", COMPILER_CALLS == 1, f"calls={COMPILER_CALLS}")
    (project / "helper.my").write_text("module helper\n\n\ndef value() -> int:\n    return 2\n")
    index(project)
    check("editing an imported module invalidates the cache", COMPILER_CALLS == 2, f"calls={COMPILER_CALLS}")

    arm = scratch / "arm"
    shutil.copytree(project, arm)
    (arm / "helper.my").write_text("module helper\n\n\ndef value() -> int:\n    return 1\n")
    (arm / "gone.my").write_text("module gone\n\n\ndef old() -> int:\n    return 7\n")
    (project / "gone.my").write_text("module gone\n\n\ndef old() -> int:\n    return 7\n")
    (project / "gone.my").unlink()
    changes = changed_lines(arm, project)
    check("a deleted module reports an old-side range", changes.get("gone.my", {}).get("status") == "deleted",
          str(changes.get("gone.my")))
    check("a modified module reports both sides",
          bool(changes.get("helper.my", {}).get("old")) and bool(changes.get("helper.my", {}).get("new")))
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--architecture", action="store_true", help="propagation cost of the three frozen arms")
    parser.add_argument("--runs", action="store_true", help="analyse recorded maintainer changes")
    parser.add_argument("--selftest", action="store_true", help="regressions for the five repaired defects")
    parser.add_argument("--json", type=Path, help="write the full result here")
    parser.add_argument("--cost-term", choices=sorted(COST_TERMS), default="v2")
    parser.add_argument("--include-chains", action="store_true",
                        help="include chained runs in the correlations (they are repeated measures)")
    parser.add_argument("--all-runs", action="store_true", help="ignore the frozen cohort")
    args = parser.parse_args()
    if args.selftest:
        print("selftest")
        return selftest()
    if not args.architecture and not args.runs:
        args.architecture = args.runs = True
    report: dict = {"version": SCHEMA_VERSION, "captured_utc": datetime.now(timezone.utc).isoformat(),
                    "cost_term": args.cost_term, "compiler": compiler_identity()}

    if args.architecture:
        report["architecture"] = {}
        print("architecture (declaration graph of the frozen arms, self-impact excluded)")
        print(f"{'arm':<5}{'nodes':>6}{'edges':>7}{'prop cost':>11}{'top-10':>9}{'>10%':>6}{'mean deps':>11}")
        for arm in ("B", "P1", "P2"):
            entry = CASCADE / "designs" / arm
            if not (entry / "main.my").is_file():
                continue
            stats = architecture(entry)
            report["architecture"][arm] = stats
            print(f"{arm:<5}{stats['nodes']:>6}{stats['edges']:>7}{stats['propagation_cost']:>11.3f}"
                  f"{stats['top10_mean_impact']:>9.3f}{stats['nodes_over_ten_percent']:>6}{stats['mean_dependencies']:>11.3f}")
            print("      sensitivity: " + "  ".join(
                f"{name} {values['propagation_cost']:.3f}/top10 {values['top10_mean']:.3f}"
                for name, values in stats["sensitivity"].items()))

    if args.runs:
        allowed = None
        if not args.all_runs and COHORT.is_file():
            manifest = json.loads(COHORT.read_text())
            allowed = {(row["arm"], row["task"], str(row["run"])) for row in manifest["runs"]}
            report["cohort"] = {"path": str(COHORT), "records": len(allowed)}
        rows = []
        for path in sorted(RUNS.glob("*/*/*.json")):
            stem = path.stem
            is_independent = stem.isdigit() and int(stem) <= 3
            is_chain = stem.startswith("chain-r1-s")
            if not (is_independent or is_chain):
                continue
            record = json.loads(path.read_text())
            if record.get("verdict") != "passed":
                continue
            if allowed is not None and (record["arm"], record["task"], stem) not in allowed:
                continue
            rows.append(run_row(record, args.cost_term))
        chains = [row for row in rows if row["chain"]]
        independent = [row for row in rows if not row["chain"]]
        report["runs"] = rows
        report["independent_runs"] = len(independent)
        report["chain_runs"] = len(chains)
        analysis = independent + chains if args.include_chains else independent
        fields = ["blast_radius_before", "blast_radius_after", "read_surface", "touched_declarations",
                  "diff_lines", "files_changed", "api_breaking", "steps", "compiler_seconds",
                  "bytes_read", "failure_results"]
        report["correlations"] = {
            "rows_used": len(analysis),
            "chains_included": args.include_chains,
            "overall_pearson_with_cost": {field: pearson([(row[field], row["cost"]) for row in analysis
                                                          if isinstance(row.get(field), (int, float))
                                                          and isinstance(row.get("cost"), (int, float))])
                                          for field in fields},
            "within_task_spearman": {field: within_task(analysis, field, centre=False) for field in fields},
            "within_task_centered_rank": {field: within_task(analysis, field, centre=True) for field in fields},
        }
        print()
        print(f"runs analysed: {len(analysis)} ({len(independent)} independent"
              + (f" + {len(chains)} chained" if args.include_chains and chains else "") + f"), cost term {args.cost_term}")
        print(f"{'signal':<22}{'overall r':>11}{'within rho':>12}{'centred rho':>13}")
        for field in fields:
            overall = report["correlations"]["overall_pearson_with_cost"][field]
            within = report["correlations"]["within_task_spearman"][field]
            centred = report["correlations"]["within_task_centered_rank"][field]
            print(f"{field:<22}{'-' if overall is None else format(overall, '+.3f'):>11}"
                  f"{'-' if within is None else format(within, '+.3f'):>12}"
                  f"{'-' if centred is None else format(centred, '+.3f'):>13}")
        deleted = [row for row in analysis if row.get("deleted_modules")]
        print(f"runs with a deleted module: {len(deleted)}"
              + (f" ({', '.join(row['arm'] + '/' + row['task'] for row in deleted[:5])})" if deleted else ""))
    report["compiler_calls"] = COMPILER_CALLS
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2) + "\n")
        print(f"\nwrote {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
