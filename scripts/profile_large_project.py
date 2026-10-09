#!/usr/bin/env python3
"""Generate deterministic multi-module workloads and measure complete check/test feedback.

This is the repaired successor to the earlier scalar-only generator. It validates
every generated project against the current language before it times anything,
records compiler-verified structure and real execution-site stage counts, and
preserves every raw sample.

Families:
  ordinary    scalar call graphs with a shared exported constant and a defaulted
              exported signature, built as a module import chain.
  managed     records, enums, unions, list iteration and generic functions over a
              named constraint, instantiated by many concrete providers.
  maintained  the repository's current schematic and self-host programs, copied
              into the scratch tree so edits do not touch the checkout.

States (each timed as a fresh process so process start is inside the sample):
  cold                    empty persistent cache, check-project
  unchanged               warm persistent cache, no edit, check-project
  no_cache                --no-cache, check-project
  implementation_edit     private body edit, warm cache
  constant_edit           exported shared constant edit, warm cache
  signature_edit          exported default-argument edit, warm cache
  union_edit              union variant add/remove plus match arm, warm cache
  effect_edit             exported effect ceiling change plus caller, warm cache
  provider_edit           consumer selects a different concrete provider, warm cache
  forced_tests            mylang test --force --json on the workload's tests

Every edit sample writes a deterministic edit token unique to that sample, so a
stored whole-project verdict for the previous sample can never satisfy the next
one.  That keeps successive edit samples independent.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import re
import select
import selectors
import shutil
import signal
import sys
import tempfile
import time
from pathlib import Path

MIB = 1024 * 1024


# --------------------------------------------------------------------------- #
# statistics and process execution
# --------------------------------------------------------------------------- #

def percentile_nearest_rank(values, fraction):
    """Nearest-rank percentile: sort ascending and index ceil(fraction*n)-1."""
    ordered = sorted(values)
    index = max(0, math.ceil(fraction * len(ordered)) - 1)
    return ordered[index]


def summarize(values):
    if not values:
        return {"samples": [], "count": 0, "median_ms": None, "p95_ms": None,
                "min_ms": None, "max_ms": None}
    ordered = sorted(values)
    return {
        "samples_ms": ordered,
        "count": len(ordered),
        "median_ms": ordered[len(ordered) // 2] if len(ordered) % 2
        else (ordered[len(ordered) // 2 - 1] + ordered[len(ordered) // 2]) / 2,
        "p95_ms": percentile_nearest_rank(ordered, 0.95),
        "min_ms": ordered[0],
        "max_ms": ordered[-1],
        "percentile_method": "nearest-rank; sorted ascending; index ceil(0.95*n)-1",
    }


def run_measured(argv, cwd=None, timeout=900.0, stdin_data=None, env=None):
    """Run argv in a fresh process group and report wall time, peak RSS and output.

    Wall time covers process start, dynamic linking, source loading and the whole
    command.  `rusage.ru_maxrss` is the maximum resident set of this child.
    """
    argv = [str(item) for item in argv]
    start = time.monotonic()
    out_r, out_w = os.pipe()
    err_r, err_w = os.pipe()
    in_r = in_w = None
    if stdin_data is not None:
        in_r, in_w = os.pipe()
    pid = os.fork()
    if pid == 0:  # pragma: no cover - child never returns
        try:
            os.setsid()
            os.dup2(out_w, 1)
            os.dup2(err_w, 2)
            if in_r is not None:
                os.dup2(in_r, 0)
            else:
                devnull = os.open(os.devnull, os.O_RDONLY)
                os.dup2(devnull, 0)
                os.close(devnull)
            for descriptor in (out_r, err_r, out_w, err_w):
                try:
                    os.close(descriptor)
                except OSError:
                    pass
            if in_w is not None:
                os.close(in_w)
            if cwd is not None:
                os.chdir(cwd)
            os.execvpe(argv[0], argv, env if env is not None else os.environ)
        except BaseException:
            os._exit(127)
    os.close(out_w)
    os.close(err_w)
    if in_r is not None:
        os.close(in_r)
    if stdin_data is not None:
        os.write(in_w, stdin_data.encode())
        os.close(in_w)
    stdout = bytearray()
    stderr = bytearray()
    selector = selectors.DefaultSelector()
    selector.register(out_r, selectors.EVENT_READ)
    selector.register(err_r, selectors.EVENT_READ)
    open_fds = {out_r, err_r}
    deadline = start + timeout
    timed_out = False
    while open_fds:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            timed_out = True
            break
        for key, _ in selector.select(min(remaining, 1.0)):
            data = os.read(key.fd, 65536)
            if not data:
                selector.unregister(key.fd)
                open_fds.discard(key.fd)
            elif key.fd == out_r:
                stdout += data
            else:
                stderr += data
    if timed_out:
        try:
            os.killpg(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    _, status, rusage = os.wait4(pid, 0)
    for descriptor in (out_r, err_r):
        try:
            os.close(descriptor)
        except OSError:
            pass
    return {
        "wall_ms": (time.monotonic() - start) * 1000.0,
        "peak_rss_kb": rusage.ru_maxrss,
        "exit": os.waitstatus_to_exitcode(status),
        "stdout": bytes(stdout).decode("utf-8", "replace"),
        "stderr": bytes(stderr).decode("utf-8", "replace"),
        "timed_out": timed_out,
    }


def extract_work_report(text):
    """Return the work-report-v1 object emitted on stderr, or None."""
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if record.get("version") == "work-report-v1":
            return record
    return None


def extract_native_tests(text):
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if record.get("version") == "native-tests-v1":
            return record
    return None


def extract_protocol_records(text, version):
    """Return every JSON Lines record with `version`, in stream order."""
    records = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if record.get("version") == version:
            records.append(record)
    return records


def extract_phase_timings(text):
    """Preserve every phase-timings-v1 record emitted for one sample."""
    return extract_protocol_records(text, "phase-timings-v1")


def extract_frontend_cache(text):
    """Return the first frontend-cache-v1 comparison receipt, or None."""
    records = extract_protocol_records(text, "frontend-cache-v1")
    return records[0] if records else None


def work_stage(report, name):
    stage = (report or {}).get(name)
    return stage if isinstance(stage, dict) else {}


def work_count(report, name, field):
    value = work_stage(report, name).get(field)
    return value if isinstance(value, int) else None


def semantic_retention(report):
    """Semantic retention totals, per-kind bytes and evictions (not frontend)."""
    semantic = (report or {}).get("semantic_cache")
    return semantic if isinstance(semantic, dict) else None


def one_shot_success(sample):
    """A sample is successful only when it exited 0 and emitted a work receipt."""
    return (not sample.get("timed_out") and sample.get("exit") == 0
            and sample.get("work_report") is not None)


def summarize_ns(values):
    if not values:
        return {"count": 0, "p50_ns": None, "p95_ns": None, "min_ns": None,
                "max_ns": None}
    ordered = sorted(values)
    return {
        "count": len(ordered),
        "p50_ns": ordered[len(ordered) // 2] if len(ordered) % 2
        else (ordered[len(ordered) // 2 - 1] + ordered[len(ordered) // 2]) // 2,
        "p95_ns": percentile_nearest_rank(ordered, 0.95),
        "min_ns": ordered[0],
        "max_ns": ordered[-1],
    }


def summarize_phase_timings(records):
    """Per-phase nearest-rank p50/p95 over successful samples only."""
    grouped = {}
    for record in records:
        if not one_shot_success(record):
            continue
        for phase in record.get("phase_timings") or []:
            name = phase.get("name")
            duration = phase.get("duration_ns")
            if not isinstance(name, str) or not isinstance(duration, int) or duration < 0:
                continue
            entry = grouped.setdefault(name, {"inclusive": bool(phase.get("inclusive")), "values": []})
            entry["values"].append(duration)
    return {name: {"inclusive": entry["inclusive"], **summarize_ns(entry["values"])}
            for name, entry in grouped.items()}


def semantic_budget_bytes():
    try:
        return int(os.environ.get("MYLANG_SEMANTIC_BUDGET", str(16 * MIB)))
    except ValueError:
        return 16 * MIB


def host_snapshot():
    """Small bounded host-load and memory snapshot for reproducible evidence."""
    snapshot = {"loadavg": None, "cpu_count": os.cpu_count()}
    try:
        snapshot["loadavg"] = Path("/proc/loadavg").read_text().strip()
    except OSError:
        pass
    try:
        meminfo = {}
        for line in Path("/proc/meminfo").read_text().splitlines():
            key, _, rest = line.partition(":")
            if key in ("MemTotal", "MemAvailable", "SwapTotal", "SwapFree"):
                meminfo[key] = rest.strip()
        snapshot["meminfo"] = meminfo
    except OSError:
        pass
    return snapshot


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    return sha256_bytes(Path(path).read_bytes())


# --------------------------------------------------------------------------- #
# generators (current Python-indented language only)
# --------------------------------------------------------------------------- #

def _write(path, lines):
    Path(path).write_text("\n".join(lines) + "\n")


def generate_ordinary_modules(root, modules, functions, token=1):
    """Write the ordinary family. Returns (entry, edited_paths)."""
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    _write(root / "conf.my", [
        "",
        "",
        f"public const STEP: int = {token}",
        "",
    ])
    for module in range(modules):
        name = f"m{module:03d}"
        body = ['', "import conf"]
        if module > 0:
            body.append(f"import m{module - 1:03d}")
        body += [
            "",
            "public func base(x: int) -> int effects():",
            "    return x + conf.STEP",
            "",
        ]
        previous = "base"
        for index in range(functions):
            current = f"f{index}"
            body += [
                f"func {current}(x: int) -> int effects():",
                f"    return {previous}(x) + 1",
                "",
            ]
            previous = current
        body += [
            "public func value(seed: int) -> int effects():",
        ]
        if module > 0:
            body.append(f"    return {previous}(seed) + m{module - 1:03d}.value(seed)")
        else:
            body.append(f"    return {previous}(seed)")
        body += [
            "",
            "public func ping(seed: int = 0) -> int effects():",
            f"    return {previous}(seed)",
            "",
        ]
        _write(root / f"{name}.my", body)
    main = [""]
    for module in range(modules):
        main.append(f"import m{module:03d}")
    main += [
        "import conf",
        "",
        "func main() -> int effects():",
        "    return " + " + ".join(f"m{module:03d}.value(0)" for module in range(modules)) + " + m000.ping() + conf.STEP",
        "",
        "",
        "public func test_ordinary() -> bool effects():",
        "    return m000.value(1) >= 0",
        "",
    ]
    _write(root / "main.my", main)
    return root / "main.my", {
        "ordinary_module": root / "m000.my",
        "constant": root / "conf.my",
        "signature": root / "m000.my",
        "main": root / "main.my",
    }


def generate(root, modules, functions):
    """Backward-compatible scalar workload used by profile_navigation.py."""
    entry, _ = generate_ordinary_modules(root, modules, functions)
    return entry


def _provider_lines(name, functions, token=1, union_variant="branch", effect="effects()", extra_variant=None):
    lines = [
        '',
        "import conf",
        "",
        "public record Row:",
        "    index: int",
        "    weight: int",
        "",
        "public enum Kind:",
        "    light",
        "    heavy",
        "",
        "public enum Node:",
        "    leaf(value: int)",
    ]
    if union_variant == "branch":
        if extra_variant is not None:
            lines.append("    branch(value: Row)")
            lines.append(f"    {extra_variant}")
        else:
            lines.append("    branch(value: Row)")
    else:
        lines.append("    branch(value: Row)")
        lines.append("    empty")
    lines += [
        "",
        f"public func classify(row: Row) -> Kind {effect}:",
        "    if row.weight > 10:",
        "        return Kind.heavy",
        "    return Kind.light",
        "",
        f"func classify_chain(row: Row) -> Kind {effect}:",
        "    return classify(row)",
        "",
        "public func summarize(rows: Row[]) -> int effects():",
        "    mut total = 0",
        "    for row in rows:",
        "        total = total + row.weight * conf.SCALE",
        "    return total",
        "",
        "func size(node: Node) -> int effects():",
        "    match node:",
        "        case Node.leaf(value=value):",
        "            return value",
        "        case Node.branch(value=row):",
        "            return row.weight",
    ]
    if union_variant != "branch":
        lines += [
            "        case Node.empty:",
            "            return 0",
        ]
    elif extra_variant is not None:
        lines += [
            f"        case Node.{extra_variant}:",
            "            return 0",
        ]
    lines += [""]
    previous = "size"
    for index in range(functions):
        current = f"h{index}"
        if index == 0:
            lines += [
                f"func {current}(x: int) -> int effects():",
                f"    return {previous}(Node.leaf(value=x)) + {token}",
                "",
            ]
        else:
            lines += [
                f"func {current}(x: int) -> int effects():",
                f"    return {previous}(x) + {index % 5 + 1}",
                "",
            ]
        previous = current
    lines += [
        "public domain Policy: int:",
        "    func make(seed: int) -> Policy effects():",
        "        return wrap[Policy](seed)",
        "",
        "    func price(policy: Policy, subtotal: int) -> int effects():",
        "        return subtotal - unwrap(policy)",
        "",
        "    func tag(policy: Policy) -> int effects():",
        "        return unwrap(policy)",
        "",
    ]
    return lines


def generate_managed(root, providers, functions, token=1):
    """Write the managed/generic family. Returns (entry, edited_paths)."""
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    _write(root / "conf.my", [
        "",
        "",
        f"public const SCALE: int = {token}",
        "",
    ])
    _write(root / "contracts.my", [
        "",
        "",
        "public constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects()) + op(tag(policy: P) -> int effects())",
        "",
    ])
    names = [f"provider{index:03d}" for index in range(providers)]
    for index, name in enumerate(names):
        _write(root / f"{name}.my", _provider_lines(name, functions, token=token))
    _write(root / "pricing.my", [
        "",
        "import contracts",
        "",
        "public func apply[P: contracts.Prices](policy: P, subtotal: int) -> int effects():",
        "    return P.price(policy, subtotal) + P.tag(policy)",
        "",
        "public func bundle[P: contracts.Prices](policy: P, subtotal: int) -> int effects():",
        "    return apply[P](policy, subtotal) + 1",
        "",
    ])
    main = ["", "import pricing"]
    for name in names:
        main.append(f"import {name}")
    main += [
        "",
        "func total(subtotal: int) -> int effects():",
        "    mut value = 0",
    ]
    for index, name in enumerate(names):
        main.append(f"    value = value + pricing.bundle({name}.Policy.make({index % 97}), subtotal)")
    main += [
        "    return value",
        "",
        "func main() -> int effects(managed_allocation):",
        f"    const rows = [{names[0]}.Row(index=0, weight=3), {names[0]}.Row(index=1, weight=11)]",
        f"    _ = {names[0]}.summarize(rows)",
        "    return total(2000)",
        "",
        "",
        "public func test_managed() -> bool effects():",
        "    return total(2000) > 0",
        "",
    ]
    _write(root / "main.my", main)
    return root / "main.my", {
        "managed_provider": root / f"{names[0]}.my",
        "constant": root / "conf.my",
        "pricing": root / "pricing.my",
        "main": root / "main.my",
        "provider_entry": names[0],
        "providers": names,
    }


# --------------------------------------------------------------------------- #
# edits
# --------------------------------------------------------------------------- #

def apply_ordinary_edit(paths, kind, token):
    """Rewrite one generated file for the requested edit kind. Deterministic."""
    if kind == "implementation_edit":
        path = paths["ordinary_module"]
        text = path.read_text()
        text = text.replace("    return base(x) + 1", f"    return base(x) + {token}")
        path.write_text(text)
        return path
    if kind == "constant_edit":
        path = paths["constant"]
        path.write_text("\n\npublic const STEP: int = %d\n" % token)
        return path
    if kind == "signature_edit":
        path = paths["signature"]
        text = path.read_text()
        text = text.replace("func ping(seed: int = 0)", f"func ping(seed: int = {token})")
        path.write_text(text)
        return path
    raise ValueError(f"unsupported ordinary edit: {kind}")


def apply_managed_edit(paths, kind, token, providers):
    if kind == "implementation_edit":
        path = paths["managed_provider"]
        text = path.read_text()
        text = text.replace("    return size(Node.leaf(value=x)) + 1", f"    return size(Node.leaf(value=x)) + {token}")
        path.write_text(text)
        return path
    if kind == "constant_edit":
        path = paths["constant"]
        path.write_text("\n\npublic const SCALE: int = %d\n" % token)
        return path
    if kind == "union_edit":
        path = paths["managed_provider"]
        name = path.stem
        _write(path, _provider_lines(name, _functions_of(path), token=1,
                                     extra_variant=f"extra_{token}"))
        return path
    if kind == "provider_edit":
        path = paths["main"]
        text = path.read_text()
        # Rotate the first concrete provider selecting the generic specialization.
        target = providers[token % len(providers)]
        text = re.sub(r"(value = value \+ pricing\.bundle\()provider\d{3}\.Policy\.make",
                      rf"\1{target}.Policy.make", text, count=1)
        path.write_text(text)
        return path
    if kind == "effect_edit":
        pricing = paths["pricing"]
        text = pricing.read_text()
        effect = "effects(clock)" if token % 2 else "effects()"
        text = text.replace("func bundle[P: contracts.Prices](policy: P, subtotal: int) -> int effects():",
                            f"func bundle[P: contracts.Prices](policy: P, subtotal: int) -> int {effect}:")
        text += f"# s1 effect edit token {token}\n"
        pricing.write_text(text)
        main = paths["main"]
        main_text = main.read_text()
        caller_effect = "effects(clock)" if token % 2 else "effects()"
        main_text = main_text.replace("func total(subtotal: int) -> int effects():",
                                      f"func total(subtotal: int) -> int {caller_effect}:")
        main_text += f"# s1 effect edit token {token}\n"
        main.write_text(main_text)
        return pricing
    raise ValueError(f"unsupported managed edit: {kind}")


def _functions_of(path):
    text = path.read_text()
    match = re.search(r"func h(\d+)\(", text)
    if not match:
        return 0
    return int(match.group(1)) + 1


def snapshot_files(paths):
    return {Path(path): Path(path).read_text() for path in paths}


def restore_files(snapshot):
    for path, text in snapshot.items():
        Path(path).write_text(text)


# --------------------------------------------------------------------------- #
# sizing helpers
# --------------------------------------------------------------------------- #

def source_lines_and_bytes(root):
    lines = 0
    total_bytes = 0
    files = sorted(Path(root).rglob("*.my"))
    for path in files:
        data = path.read_bytes()
        total_bytes += len(data)
        lines += data.count(b"\n") + (0 if data.endswith(b"\n") else 1)
    return lines, total_bytes, len(files)


def size_ordinary(root, target_lines, modules, functions_hint):
    functions = functions_hint
    best = None
    for _ in range(8):
        generate_ordinary_modules(root, modules, functions)
        lines, total_bytes, _ = source_lines_and_bytes(root)
        best = (functions, lines, total_bytes)
        if abs(lines - target_lines) <= max(8, target_lines // 100):
            break
        delta = target_lines - lines
        adjust = delta // (3 * modules)
        if adjust == 0:
            adjust = -1 if delta < 0 else 1
        functions = max(1, functions + adjust)
    return best


def size_managed(root, target_lines, providers, functions_hint):
    functions = functions_hint
    best = None
    for _ in range(8):
        generate_managed(root, providers, functions)
        lines, total_bytes, _ = source_lines_and_bytes(root)
        best = (functions, lines, total_bytes)
        if abs(lines - target_lines) <= max(8, target_lines // 100):
            break
        delta = target_lines - lines
        adjust = delta // (3 * providers)
        if adjust == 0:
            adjust = -1 if delta < 0 else 1
        functions = max(1, functions + adjust)
    return best


# --------------------------------------------------------------------------- #
# compiler-verified structure and stage counts
# --------------------------------------------------------------------------- #

def parse_list_modules(text):
    modules = []
    imports = []
    current = None
    for line in text.splitlines():
        if line.startswith(""):
            continue
        match = re.match(r"", line)
        if match:
            current = match.group(1)
            modules.append({"module": current, "path": match.group(2), "sha256": match.group(3)})
            continue
        match = re.match(r"\s+import (\S+) as (\S+)", line)
        if match and current is not None:
            imports.append({"from": current, "to": match.group(1), "alias": match.group(2)})
    return modules, imports


def graph_depth(modules, imports):
    outgoing = {module["module"]: [] for module in modules}
    for edge in imports:
        if edge["from"] in outgoing and edge["to"] in outgoing:
            outgoing[edge["from"]].append(edge["to"])
    order = [module["module"] for module in modules]
    depth = {}

    def walk(name):
        if name in depth:
            return depth[name]
        depth[name] = 1
        best = 0
        for target in outgoing.get(name, []):
            if target == name:
                continue
            best = max(best, walk(target))
        depth[name] = 1 + best
        return depth[name]

    best = 0
    for name in order:
        best = max(best, walk(name))
    return best


def collect_structure(compiler, entry):
    result = run_measured([compiler, "list-modules", entry, "--no-cache"], timeout=300)
    if result["exit"] != 0:
        return {"status": "rejected", "exit": result["exit"], "stderr": result["stderr"][:2000]}
    modules, imports = parse_list_modules(result["stdout"])
    return {
        "status": "ok",
        "modules": len(modules),
        "imports": len(imports),
        "module_depth": graph_depth(modules, imports),
        "list_modules_ms": result["wall_ms"],
        "list_modules_peak_rss_kb": result["peak_rss_kb"],
    }


def collect_call_depth(compiler, entry):
    result = run_measured([compiler, "index-project", entry, "--full", "--no-cache"], timeout=600)
    if result["exit"] != 0 or not result["stdout"].strip():
        return {"status": "unsupported", "exit": result["exit"],
                "stderr": result["stderr"][:300], "wall_ms": result["wall_ms"]}
    try:
        document = json.loads(result["stdout"])
    except ValueError:
        return {"status": "unsupported", "reason": "index-project did not emit navigation JSON",
                "wall_ms": result["wall_ms"]}
    edges = {}
    for reference in document.get("references", []):
        if reference.get("kind") == "call":
            edges.setdefault(reference["from"], []).append(reference["to"])
    memo = {}

    def depth(name):
        if name in memo:
            return memo[name]
        memo[name] = 1
        best = 0
        for target in edges.get(name, []):
            if target == name:
                continue
            best = max(best, depth(target))
        memo[name] = 1 + best
        return memo[name]

    best = 0
    for name in edges:
        best = max(best, depth(name))
    return {"status": "ok", "call_depth": best, "symbols": len(document.get("symbols", [])),
            "references": len(document.get("references", [])), "wall_ms": result["wall_ms"],
            "peak_rss_kb": result["peak_rss_kb"]}


def collect_metrics(compiler, entry, work_report, with_call_depth=True):
    lines, total_bytes, files = source_lines_and_bytes(Path(entry).parent)
    structure = collect_structure(compiler, entry)
    functions = None
    specializations = None
    checked_bodies = None
    specialization_bodies = None
    symbolic_templates = None
    if work_report is not None:
        checked_bodies = work_report["checked_bodies"]["performed"]
        # `instantiated_specializations` counts concrete functions in the checked
        # program and its reused field is zero by construction. Keep it as a
        # program-shape metric; use `specialization_bodies` for body replay.
        specializations = work_report["instantiated_specializations"]["performed"]
        specialization_bodies = work_report.get("specialization_bodies")
        symbolic_templates = work_report.get("symbolic_templates")
        functions = checked_bodies
    metrics = {
        "lines": lines,
        "bytes": total_bytes,
        "my_files": files,
        "module_report": structure,
        "functions_checked": functions,
        "checked_bodies": checked_bodies,
        "instantiated_specializations": specializations,
        "specialization_bodies": specialization_bodies,
        "symbolic_templates": symbolic_templates,
    }
    if with_call_depth:
        metrics["call_graph"] = collect_call_depth(compiler, entry)
    return metrics


# --------------------------------------------------------------------------- #
# validation
# --------------------------------------------------------------------------- #

def validate(compiler, entry, run=False, timeout=600):
    check = run_measured([compiler, "check-project", entry, "--no-cache", "--report"], timeout=timeout)
    report = extract_work_report(check["stderr"])
    result = {
        "exit": check["exit"],
        "wall_ms": check["wall_ms"],
        "peak_rss_kb": check["peak_rss_kb"],
        "work_report": report,
        "diagnostic": check["stderr"][:2000] if check["exit"] != 0 else "",
        "accepted": check["exit"] == 0 and report is not None,
    }
    if run:
        ran = run_measured([compiler, "run-project", entry, "--print-result", "--no-cache"], timeout=timeout)
        printed = ran["stdout"].strip()
        ran_ok = bool(re.fullmatch(r"-?\d+", printed)) and "error[" not in ran["stderr"].lower()
        result["run"] = {
            "exit": ran["exit"],
            "wall_ms": ran["wall_ms"],
            "peak_rss_kb": ran["peak_rss_kb"],
            "stdout": printed[:200],
            "stderr": ran["stderr"][:500],
            "accepted": ran_ok,
            "acceptance": "stdout is a decimal guest result and stderr carries no diagnostic; exit is the truncated guest return value",
        }
        if not ran_ok:
            result["accepted"] = False
    return result


# --------------------------------------------------------------------------- #
# state measurement
# --------------------------------------------------------------------------- #

def one_shot_sample(compiler, entry, cache_dir, state, timeout):
    argv = [compiler, "check-project", entry, "--report", "--timings=json"]
    if state == "cold":
        shutil.rmtree(cache_dir, ignore_errors=True)
        argv += ["--cache-dir=" + str(cache_dir)]
    elif state == "no_cache":
        argv += ["--no-cache"]
    else:
        argv += ["--cache-dir=" + str(cache_dir)]
    result = run_measured(argv, timeout=timeout)
    report = extract_work_report(result["stderr"])
    phase_timings = extract_phase_timings(result["stderr"])
    frontend_cache = extract_frontend_cache(result["stderr"])
    return {
        "state": state,
        "wall_ms": result["wall_ms"],
        "peak_rss_kb": result["peak_rss_kb"],
        "exit": result["exit"],
        "timed_out": result["timed_out"],
        "success": one_shot_success({
            "exit": result["exit"], "timed_out": result["timed_out"],
            "work_report": report,
        }),
        # Complete receipt, not a hand-picked subset. Convenience `stages`
        # remains for existing raw-JSON readers, but new analyses should read
        # `work_report` directly.
        "work_report": report,
        "phase_timings": phase_timings,
        "frontend_cache": frontend_cache,
        "stages": None if report is None else {
            "parsed_modules": report["parsed_modules"],
            "checked_bodies": report["checked_bodies"],
            "instantiated_specializations": report["instantiated_specializations"],
            "symbolic_templates": report.get("symbolic_templates"),
            "specialization_bodies": report.get("specialization_bodies"),
            "lowered_functions": report["lowered_functions"],
            "emitted_fragments": report["emitted_fragments"],
            "links": report["links"],
            "executed_tests": report["executed_tests"],
            "reused": report.get("reused"),
            "bypassed": report.get("bypassed"),
        },
        "semantic_retention": semantic_retention(report),
        "diagnostic": result["stderr"][:500] if result["exit"] != 0 else "",
    }


def measure_one_shot_state(compiler, entry, cache_dir, state, samples, timeout, edit=None, restore=None):
    cache_dir = Path(cache_dir)
    warm_up = None
    if state not in ("cold", "no_cache"):
        # One successful warm check is required before any sample may be
        # labeled warm. A failed/timed-out warm-up blocks the state instead of
        # manufacturing a warm measurement.
        shutil.rmtree(cache_dir, ignore_errors=True)
        warm_up = one_shot_sample(compiler, entry, cache_dir, "unchanged", timeout)
        if not one_shot_success(warm_up):
            reason = "warm-up timed out" if warm_up["timed_out"] else (
                "warm-up exited nonzero" if warm_up["exit"] != 0 else
                "warm-up emitted no work-report-v1")
            return {
                "state": state,
                "status": "blocked",
                "reason": reason,
                "warm_up": warm_up,
                "summary": summarize([]),
                "phase_summary": {},
                "peak_rss_kb_max": None,
                "samples": [],
                "successful_samples": 0,
                "failed_samples": 0,
            }
    records = []
    for index in range(samples):
        if edit is not None:
            if restore is not None:
                restore()
            edit(index)
        records.append(one_shot_sample(compiler, entry, cache_dir, state, timeout))
    successful = [record for record in records if one_shot_success(record)]
    return {
        "state": state,
        "summary": summarize([record["wall_ms"] for record in successful]),
        "phase_summary": summarize_phase_timings(records),
        "peak_rss_kb_max": max((record["peak_rss_kb"] for record in successful), default=None),
        "successful_samples": len(successful),
        "failed_samples": len(records) - len(successful),
        "warm_up": warm_up,
        "samples": records,
    }


def _test_record(result):
    report = extract_native_tests(result["stdout"])
    return {
        "wall_ms": result["wall_ms"],
        "peak_rss_kb": result["peak_rss_kb"],
        "exit": result["exit"],
        "timed_out": result["timed_out"],
        "passed": None if report is None else report.get("passed"),
        "failed": None if report is None else report.get("failed"),
        "cached": None if report is None else report.get("cached"),
        "executed": None if report is None else report.get("executed"),
        "selected": None if report is None else report.get("selected"),
        "diagnostic": result["stderr"][:500] if result["exit"] != 0 else "",
    }


def measure_forced_tests(compiler, entry, cache_dir, samples, timeout):
    """Warm the native object/test cache, then measure forced re-execution.

    The warm run is the complete first build (check + lower + emit + link +
    execute); it is recorded separately as `cold_build`.  Recorded samples then
    measure `--force` feedback with warm objects, still including process start
    and the whole-project check that precedes test selection at this baseline.
    Child build processes (QBE/Zig) are not reflected in the direct child's
    ru_maxrss, so the memory number is a lower bound for this state.
    """
    argv_base = [compiler, "test", entry, "--json", "--cache-dir=" + str(cache_dir)]
    warm = run_measured(argv_base, timeout=timeout)
    warm_record = _test_record(warm)
    warm_record["role"] = "cold_build"
    warm_ok = (not warm_record["timed_out"] and warm_record["exit"] == 0
               and warm_record.get("passed") is not None)
    if not warm_ok:
        warm_record["blocked_reason"] = "warm first build did not produce a successful native-tests-v1 receipt"
        return {
            "state": "forced_tests",
            "status": "blocked",
            "reason": warm_record["blocked_reason"],
            "cold_build": warm_record,
            "summary": summarize([]),
            "phase_summary": {},
            "peak_rss_kb_max": None,
            "successful_samples": 0,
            "failed_samples": 0,
            "samples": [],
            "memory_note": "direct-child ru_maxrss only; host build children are not included",
        }
    argv_force = [compiler, "test", entry, "--force", "--json", "--cache-dir=" + str(cache_dir)]
    records = []
    for _ in range(samples):
        records.append(_test_record(run_measured(argv_force, timeout=timeout)))
    successful = [record for record in records
                  if not record["timed_out"] and record["exit"] == 0 and record.get("passed") is not None]
    return {
        "state": "forced_tests",
        "cold_build": warm_record,
        "summary": summarize([record["wall_ms"] for record in successful]),
        "phase_summary": {},
        "peak_rss_kb_max": max([warm_record["peak_rss_kb"]] +
                               [record["peak_rss_kb"] for record in successful], default=None),
        "successful_samples": len(successful),
        "failed_samples": len(records) - len(successful),
        "memory_note": "direct-child ru_maxrss only; host build children are not included",
        "samples": records,
    }


def start_session(compiler, entry, cwd=None):
    """Start the existing check-session protocol with a bounded read timeout."""
    import subprocess
    return subprocess.Popen(
        [str(compiler), "check-session", str(entry)],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, bufsize=1, cwd=cwd)


def session_request(process, action, timeout):
    """Send one check-session line and return (wall_ms, parsed reply)."""
    started = time.monotonic()
    process.stdin.write(action + "\n")
    process.stdin.flush()
    ready, _, _ = select.select([process.stdout], [], [], timeout)
    if not ready:
        raise TimeoutError(f"check-session {action!r} exceeded {timeout:g}s")
    line = process.stdout.readline()
    if not line:
        raise RuntimeError("check-session exited unexpectedly")
    try:
        record = json.loads(line)
    except ValueError as exc:
        raise RuntimeError(f"check-session reply was not JSON: {line[:160]!r}") from exc
    return (time.monotonic() - started) * 1000.0, record


def stop_session(process):
    if process.poll() is None:
        try:
            process.stdin.write("quit\n")
            process.stdin.flush()
        except (BrokenPipeError, OSError, ValueError):
            pass
        try:
            process.wait(timeout=10)
        except Exception:
            process.kill()
            process.wait()


def session_success(reply):
    return isinstance(reply, dict) and reply.get("status") == 0


def summarize_session_replies(records):
    successful = [record for record in records if session_success(record.get("reply"))]
    phase_summary = {}
    return {
        "summary": summarize([record["wall_ms"] for record in successful]),
        "phase_summary": phase_summary,
        "successful_samples": len(successful),
        "failed_samples": len(records) - len(successful),
        "samples": records,
    }


def measure_session_edits(compiler, entry, cwd, restore, edit, samples, warmup, timeout):
    """In-process check-session edit latency. Excludes process startup."""
    process = start_session(compiler, entry, cwd)
    records = []
    warm_replies = []
    try:
        restore()
        warm_ok = True
        for _ in range(max(1, warmup)):
            _, reply = session_request(process, "check", timeout)
            warm_replies.append(reply)
            if not session_success(reply):
                warm_ok = False
                break
        if not warm_ok:
            return {
                "state": "session_edit",
                "status": "blocked",
                "reason": "session warm-up check did not return status 0",
                "warm_up": warm_replies,
                "summary": summarize([]),
                "phase_summary": {},
                "successful_samples": 0,
                "failed_samples": 0,
                "samples": [],
            }
        for index in range(samples):
            restore()
            edit(index)
            elapsed, reply = session_request(process, "check", timeout)
            work = reply.get("work") or {}
            records.append({
                "wall_ms": elapsed,
                "status": reply.get("status"),
                "reused": work.get("reused"),
                "request": work.get("request"),
                "diagnostic": reply.get("failure"),
                # Keep the complete check-session-v1 reply, including retention
                # totals, per-kind counters and labelled miss reasons.
                "reply": reply,
            })
    except Exception as exc:  # preserve the failed/blocked state instead of emitting partial summaries
        return {
            "state": "session_edit",
            "status": "blocked",
            "reason": f"{type(exc).__name__}: {exc}",
            "warm_up": warm_replies,
            "summary": summarize([]),
            "phase_summary": {},
            "successful_samples": 0,
            "failed_samples": len(records),
            "samples": records,
        }
    finally:
        stop_session(process)
    result = summarize_session_replies(records)
    result.update({"state": "session_edit"})
    return result


def collect_session_probe(compiler, entry, cwd, timeout, checks=3, restore=None, edit=None):
    """Bounded retention/miss probe over the existing check-session protocol.

    It keeps every raw `check-session-v1` reply, including semantic retention
    totals, per-kind bytes, eviction counters, specialization-body counters and
    labelled ordinary/symbolic/specialization miss reasons.
    """
    process = start_session(compiler, entry, cwd)
    replies = []
    try:
        if restore is not None and edit is not None:
            restore()
            warm_started = time.monotonic()
            _, warm_reply = session_request(process, "check", timeout)
            replies.append({
                "role": "warmup",
                "probe_index": None,
                "wall_ms": (time.monotonic() - warm_started) * 1000.0,
                "reply": warm_reply,
            })
            edit(9000)
        for index in range(max(1, checks)):
            started = time.monotonic()
            _, reply = session_request(process, "check", timeout)
            replies.append({
                "role": "measurement",
                "probe_index": index,
                "wall_ms": (time.monotonic() - started) * 1000.0,
                "reply": reply,
            })
        return {
            "status": "measured",
            "protocol": "check-session-v1",
            "checks": len([reply for reply in replies if reply["role"] == "measurement"]),
            "replies": replies,
        }
    except Exception as exc:
        return {
            "status": "blocked",
            "reason": f"{type(exc).__name__}: {exc}",
            "protocol": "check-session-v1",
            "checks": len(replies),
            "replies": replies,
        }
    finally:
        if restore is not None and edit is not None:
            restore()
        stop_session(process)


# --------------------------------------------------------------------------- #
# bounded project limits
# --------------------------------------------------------------------------- #

LIMITS = [
    {
        "subsystem": "checking/build loader",
        "source": "src/project.zig",
        "budgets": {"max_modules": 4096, "max_imports": 65536,
                    "max_file_bytes": 4 * MIB, "max_total_bytes": 16 * MIB,
                    "max_file_bytes_human": "4 MiB", "max_total_bytes_human": "16 MiB"},
        "patterns": ["max_modules: usize = 4096", "max_imports: usize = 65536",
                     "max_file_bytes: usize = 4 * 1024 * 1024", "max_total_bytes: usize = 16 * 1024 * 1024"],
    },
    {
        "subsystem": "project configuration",
        "source": "src/project_config.zig",
        "budgets": {"max_config_bytes": 1 * MIB, "max_config_bytes_human": "1 MiB"},
        "patterns": ["max_config_bytes = 1024 * 1024"],
    },
    {
        "subsystem": "navigation index",
        "source": "src/navigation.zig",
        "budgets": {"max_symbols": 50000, "max_references": 250000},
        "patterns": ["symbols: usize = 50000", "references: usize = 250000"],
    },
    {
        "subsystem": "native test snapshot/provider materialization",
        "source": "src/native_test_snapshot.zig",
        "budgets": {"max_bytes": 16 * MIB, "max_entries": 50000, "max_bytes_human": "16 MiB"},
        "patterns": ["byte_limit = 16 * 1024 * 1024", "visited > 50000"],
    },
    {
        "subsystem": "python navigation source inventory",
        "source": "scripts/navigate.py",
        "budgets": {"max_bytes": 16 * MIB, "max_entries": 50000, "max_bytes_human": "16 MiB"},
        "patterns": ["16 * 1024 * 1024 - total", "visited > 50000"],
    },
    {
        "subsystem": "package materialization",
        "source": "src/packages_command.zig",
        "budgets": {"max_bytes": 16 * MIB, "max_bytes_human": "16 MiB"},
        "patterns": ["package_byte_budget: usize = 16 * 1024 * 1024"],
    },
    {
        "subsystem": "agent store materialization",
        "source": "scripts/store.py",
        "budgets": {"max_file_bytes": 8 * MIB, "max_total_bytes": 64 * MIB,
                    "max_file_bytes_human": "8 MiB", "max_total_bytes_human": "64 MiB"},
        "patterns": ["MAX_FILE_BYTES = 8 * 1024 * 1024", "MAX_TOTAL_BYTES = 64 * 1024 * 1024"],
    },
]


def limit_findings():
    """Concrete, source-located inconsistencies between bounded subsystems."""
    return [
        {
            "finding": "module/import counts are bounded only by the loader",
            "detail": "src/project.zig defaults to 4096 modules and 65536 import edges (overridable through a "
                      "mylang.json budgets object) and rejects the next module with E_MODULE_LIMIT, "
                      "but src/native_test_snapshot.zig, scripts/navigate.py and src/packages_command.zig enforce only "
                      "byte/entry budgets, so a project that large can be snapshotted or materialized and then "
                      "fail ordinary checking.",
            "sources": ["src/project.zig", "src/native_test_snapshot.zig", "scripts/navigate.py", "src/packages_command.zig"],
            "action": "reported, not changed: a consistent fix must add the shared module/import budget to the "
                      "snapshot, inventory and package paths, not only to project.zig.",
        },
        {
            "finding": "store byte budgets are larger than the compiler budgets",
            "detail": "scripts/store.py allows 8 MiB per file and 64 MiB total; the loader allows 4 MiB per file and "
                      "16 MiB total. The store accepts projects the compiler later rejects with E_PROJECT_BYTES.",
            "sources": ["scripts/store.py", "src/project.zig"],
            "action": "reported, not changed: lowering the store without measuring existing store users would be a "
                      "behavior change outside the S1 measurement package.",
        },
        {
            "finding": "navigation has its own symbol/reference budgets",
            "detail": "src/navigation.zig caps navigation at 50000 symbols and 250000 references. The measured 100k-line "
                      "ordinary workload checks in a few seconds but index-project reports host failure NavigationLimit; "
                      "navigation limits are not part of the loader/snapshot/package budget set.",
            "sources": ["src/navigation.zig"],
            "action": "reported; the measured NavigationLimit is preserved in workload metrics and is an unsupported "
                      "workload for navigation, never a timing sample.",
        },
        {
            "finding": "configuration budget is a separate 1 MiB ceiling",
            "detail": "src/project_config.zig caps mylang.json and a relative import policy at 1 MiB independently of the "
                      "source budget.",
            "sources": ["src/project_config.zig"],
            "action": "documented in the shared limits table; no measurement justifies changing it.",
        },
    ]


def verify_limit_sources(repo_root):
    report = []
    for entry in LIMITS:
        source = Path(repo_root) / entry["source"]
        text = source.read_text() if source.is_file() else ""
        missing = [pattern for pattern in entry["patterns"] if pattern not in text]
        report.append({
            "subsystem": entry["subsystem"],
            "source": entry["source"],
            "budgets": entry["budgets"],
            "all_patterns_present": not missing,
            "missing_patterns": missing,
        })
    return report


def probe_bounded_failures(compiler, scratch):
    """Actively confirm that excessive input still fails with the documented limit."""
    scratch = Path(scratch)
    records = []

    # A configured module budget of one -> E_MODULE_LIMIT
    module_root = scratch / "limit-modules"
    shutil.rmtree(module_root, ignore_errors=True)
    module_root.mkdir(parents=True)
    for index in range(2):
        body = ['']
        if index + 1 < 2:
            body.append(f"import m{index + 1:03d}")
        body += ["", f"func value() -> int effects():", f"    return {index}"]
        _write(module_root / f"m{index:03d}.my", body)
    _write(module_root / "mylang.json", ['{"version": 1, "budgets": {"max_modules": 1}}'])
    result = run_measured([compiler, "check-project", module_root / "m000.my", "--no-cache"], timeout=120)
    records.append({
        "probe": "project over its configured module budget",
        "expected": "E_MODULE_LIMIT",
        "exit": result["exit"],
        "observed": "E_MODULE_LIMIT" if "E_MODULE_LIMIT" in result["stderr"] else None,
        "bounded_failure": result["exit"] != 0 and "E_MODULE_LIMIT" in result["stderr"],
        "diagnostic": result["stderr"].splitlines()[0] if result["stderr"] else "",
    })

    # Oversized single file -> E_PROJECT_BYTES
    bytes_root = scratch / "limit-bytes"
    shutil.rmtree(bytes_root, ignore_errors=True)
    bytes_root.mkdir(parents=True)
    padding = "\n".join(f"# pad {index:07d}" for index in range(5 * MIB // 16))
    _write(bytes_root / "main.my", ["", "", padding, "",
                                    "func main() -> int effects():", "    return 0"])
    result = run_measured([compiler, "check-project", bytes_root / "main.my", "--no-cache"], timeout=120)
    records.append({
        "probe": "single source file over 4 MiB",
        "expected": "E_PROJECT_BYTES",
        "exit": result["exit"],
        "observed": "E_PROJECT_BYTES" if "E_PROJECT_BYTES" in result["stderr"] else None,
        "bounded_failure": result["exit"] != 0 and "E_PROJECT_BYTES" in result["stderr"],
        "diagnostic": result["stderr"].splitlines()[0] if result["stderr"] else "",
    })

    # Total project over 16 MiB -> E_PROJECT_BYTES
    total_root = scratch / "limit-total"
    shutil.rmtree(total_root, ignore_errors=True)
    total_root.mkdir(parents=True)
    for index in range(6):
        padding = "\n".join(f"# pad {index:07d}" for _ in range(250000))
        _write(total_root / f"m{index}.my", ['', "", padding, "",
                                             "public func value() -> int effects():", "    return 0"])
    entry_lines = [""] + [f"import m{index}" for index in range(6)]
    entry_lines += ["", "func main() -> int effects():",
                    "    return " + " + ".join(f"m{index}.value()" for index in range(6))]
    _write(total_root / "main.my", entry_lines)
    result = run_measured([compiler, "check-project", total_root / "main.my", "--no-cache"], timeout=180)
    records.append({
        "probe": "project source over 16 MiB",
        "expected": "E_PROJECT_BYTES",
        "exit": result["exit"],
        "observed": "E_PROJECT_BYTES" if "E_PROJECT_BYTES" in result["stderr"] else None,
        "bounded_failure": result["exit"] != 0 and "E_PROJECT_BYTES" in result["stderr"],
        "diagnostic": result["stderr"].splitlines()[0] if result["stderr"] else "",
    })
    return records


# --------------------------------------------------------------------------- #
# workload orchestration
# --------------------------------------------------------------------------- #

def copy_maintained(source_entry, destination):
    """Copy the maintained project directory; return the copied entry path."""
    source_entry = Path(source_entry)
    destination = Path(destination)
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source_entry.parent, destination)
    return destination / source_entry.name


SESSION_STATE_SOURCES = {
    "session_implementation_edit": "implementation_edit",
    "session_constant_edit": "constant_edit",
    "session_signature_edit": "signature_edit",
    "session_union_edit": "union_edit",
    "session_provider_edit": "provider_edit",
    "session_effect_edit": "effect_edit",
}


def state_samples(state, options):
    if state in ("cold", "unchanged", "no_cache"):
        return options.baseline_samples or options.samples
    if state in ("implementation_edit", "constant_edit", "signature_edit"):
        return options.samples
    if state in SESSION_STATE_SOURCES:
        return options.session_samples or min(options.samples, 5)
    return options.extra_samples or min(options.samples, 5)


def measure_workload(compiler, workload, options, scratch):
    family = workload["family"]
    label = workload["label"]
    target = workload.get("target_lines")
    root = Path(scratch) / "sources" / label
    edits = None
    if family == "ordinary":
        modules = options.modules if options.modules else (64 if target is None else 64)
        functions_hint = options.functions if options.functions else max(1, (target or 3000) // (3 * modules))
        functions, lines, total_bytes = size_ordinary(root, target or 3000, modules, functions_hint)
        entry, paths = generate_ordinary_modules(root, modules, functions)
        workload["generated"] = {"modules": modules, "functions_per_module": functions,
                                 "lines": lines, "bytes": total_bytes}
        edits = {
            "implementation_edit": lambda index: apply_ordinary_edit(paths, "implementation_edit", 1000 + index),
            "constant_edit": lambda index: apply_ordinary_edit(paths, "constant_edit", 1000 + index),
            "signature_edit": lambda index: apply_ordinary_edit(paths, "signature_edit", 1000 + index),
        }
    elif family == "managed":
        providers = options.providers or 64
        functions_hint = options.functions if options.functions else max(1, (target or 3000) // (3 * providers))
        functions, lines, total_bytes = size_managed(root, target or 3000, providers, functions_hint)
        entry, paths = generate_managed(root, providers, functions)
        workload["generated"] = {"providers": providers, "functions_per_provider": functions,
                                 "lines": lines, "bytes": total_bytes}
        edits = {
            "implementation_edit": lambda index: apply_managed_edit(
                paths, "implementation_edit", 1000 + index, paths["providers"]),
            "constant_edit": lambda index: apply_managed_edit(
                paths, "constant_edit", 1000 + index, paths["providers"]),
            "union_edit": lambda index: apply_managed_edit(
                paths, "union_edit", 1000 + index, paths["providers"]),
            "provider_edit": lambda index: apply_managed_edit(
                paths, "provider_edit", 1000 + index, paths["providers"]),
            "effect_edit": lambda index: apply_managed_edit(
                paths, "effect_edit", 1000 + index, paths["providers"]),
        }
    elif family == "maintained":
        source = Path(options.repo_root) / workload["source"]
        entry = copy_maintained(source, root)
        paths = {"main": entry}
        edit_target = maintained_edit_target(root)
        workload["_maintained_target"] = str(edit_target)
        workload["generated"] = {"copied_from": workload["source"], "edit_target": str(edit_target)}
        edits = {"implementation_edit": lambda index, edit_target=edit_target: apply_maintained_edit(edit_target, index)}
    else:
        raise ValueError(f"unknown family: {family}")

    entry = str(Path(entry).resolve())
    run_validation = options.validate_run and (target is not None and target <= 2000)
    validation = validate(compiler, entry, run=run_validation, timeout=options.timeout)
    workload["entry"] = entry
    workload["validation"] = validation
    if not validation["accepted"]:
        workload["status"] = "rejected"
        return workload
    workload["status"] = "measured"
    workload["metrics"] = collect_metrics(
        compiler, entry, validation["work_report"],
        with_call_depth=options.call_depth and (target is None or target <= 200000))

    cache_dir = Path(scratch) / "caches" / label
    shutil.rmtree(cache_dir, ignore_errors=True)
    pristine = snapshot_files(edits_paths(workload, family, root))
    restore = lambda: restore_files(pristine)
    restore()
    states = {}
    for state in options.states:
        if state == "forced_tests" or state in SESSION_STATE_SOURCES:
            continue
        print(f"[s1]   state {state} ...", flush=True)
        edit = None
        if state in ("implementation_edit", "constant_edit", "signature_edit", "union_edit",
                     "provider_edit", "effect_edit"):
            if edits is None or state not in edits:
                states[state] = {"state": state, "status": "unsupported",
                                 "reason": "no edit recipe for this family"}
                continue
            edit = edits[state]
        samples = state_samples(state, options)
        measured = measure_one_shot_state(compiler, entry, cache_dir, state, samples,
                                          options.timeout, edit=edit, restore=restore)
        if "status" not in measured:
            measured["status"] = "measured" if measured.get("successful_samples", 0) > 0 else "failed"
        states[state] = measured
    if edits:
        originals = pristine
        for state in options.states:
            base = SESSION_STATE_SOURCES.get(state)
            if base is None:
                continue
            if base not in edits:
                states[state] = {"state": state, "status": "unsupported",
                                 "reason": "no edit recipe for this family"}
                continue
            print(f"[s1]   state {state} ...", flush=True)
            session_cwd = Path(scratch) / "session-cwd" / label
            session_cwd.mkdir(parents=True, exist_ok=True)
            measured = measure_session_edits(
                compiler, entry, session_cwd,
                lambda: restore_files(originals), edits[base],
                options.samples, 1, options.timeout)
            if "status" not in measured:
                measured["status"] = "measured" if measured.get("successful_samples", 0) > 0 else "failed"
            states[state] = measured
    if "forced_tests" in options.states:
        print("[s1]   state forced_tests ...", flush=True)
        measured = measure_forced_tests(
            compiler, entry, cache_dir, options.test_samples, options.timeout)
        if "status" not in measured:
            measured["status"] = "measured" if measured.get("successful_samples", 0) > 0 else "failed"
        states["forced_tests"] = measured
    workload["states"] = states
    if getattr(options, "session_probe", False):
        print(f"[s1]   session probe {label} ...", flush=True)
        probe_edit = (edits or {}).get("implementation_edit")
        workload["session_probe"] = collect_session_probe(
            compiler, entry, Path(scratch) / "session-cwd" / label,
            options.timeout, checks=options.session_probe_checks,
            restore=lambda: restore_files(pristine), edit=probe_edit)
    return workload


def edits_paths(workload, family, root):
    """Return the files an edit recipe may rewrite, for exact restoration."""
    if family == "ordinary":
        return [Path(root) / "m000.my", Path(root) / "conf.my"]
    if family == "managed":
        return [Path(root) / "provider000.my", Path(root) / "conf.my",
                Path(root) / "main.my", Path(root) / "pricing.my"]
    if family == "maintained":
        target = workload.get("_maintained_target")
        return [Path(target)] if target else []
    return []


def maintained_edit_target(root):
    """Largest maintained module, chosen deterministically for a safe private edit."""
    files = sorted(Path(root).rglob("*.my"), key=lambda item: (-item.stat().st_size, str(item)))
    if not files:
        raise ValueError("maintained workload has no .my files")
    return files[0]


def apply_maintained_edit(target, index):
    """Append a unique private helper; it does not change any exported contract."""
    target = Path(target)
    text = target.read_text()
    if not text.endswith("\n"):
        text += "\n"
    text += f"\nfunc s1_maintained_edit_{index}() -> int effects():\n    return {1000 + index}\n"
    target.write_text(text)
    return target


def evaluate_objectives(workload):
    if workload.get("status") != "measured":
        return {"status": "unsupported"}
    states = workload["states"]
    assessment = {"target_lines": workload.get("target_lines")}
    for state_name in ("implementation_edit", "constant_edit", "signature_edit", "cold"):
        state = states.get(state_name)
        if state and state.get("status") == "measured":
            p95 = state["summary"]["p95_ms"]
            assessment[state_name] = {
                "p95_ms": p95,
                "under_500ms": None if p95 is None else p95 < 500.0,
            }
    forced = states.get("forced_tests")
    if forced and forced.get("status") == "measured":
        p95 = forced["summary"]["p95_ms"]
        assessment["forced_tests"] = {"p95_ms": p95, "under_1000ms": None if p95 is None else p95 < 1000.0}
    return assessment


# --------------------------------------------------------------------------- #
# CSV
# --------------------------------------------------------------------------- #

CSV_COLUMNS = [
    "workload", "family", "target_lines", "state", "sample", "wall_ms", "peak_rss_kb", "exit",
    "timed_out", "success", "parsed_performed", "parsed_reused", "checked_performed", "checked_reused",
    "specializations_performed", "specialization_bodies_performed", "specialization_bodies_reused",
    "symbolic_templates_performed", "symbolic_templates_reused",
    "semantic_retained_bytes", "semantic_ordinary_bytes", "semantic_symbolic_bytes",
    "semantic_specialization_bytes", "semantic_evicted",
    "lowered_performed", "emitted_performed", "links_performed",
    "tests_performed", "tests_cached", "tests_executed", "reused_results", "bypassed",
    "phase_count",
]


def write_csv(path, workloads):
    with open(path, "w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(CSV_COLUMNS)
        for workload in workloads:
            for state_name, state in (workload.get("states") or {}).items():
                for index, sample in enumerate(state.get("samples") or []):
                    report = sample.get("work_report")
                    reply = sample.get("reply") or {}
                    stages = sample.get("stages") or {}
                    def performed(key):
                        if report is not None:
                            return work_count(report, key, "performed")
                        value = stages.get(key)
                        return value.get("performed") if isinstance(value, dict) else None
                    def reused(key):
                        if report is not None:
                            return work_count(report, key, "reused")
                        value = stages.get(key)
                        return value.get("reused") if isinstance(value, dict) else None
                    spec_bodies = work_stage(report, "specialization_bodies") if report is not None else reply.get("specialization_bodies") or {}
                    symbolic = work_stage(report, "symbolic_templates") if report is not None else reply.get("symbolic_templates") or {}
                    retention = (semantic_retention(report) if report is not None
                                 else reply.get("semantic_retention")) or {}
                    writer.writerow([
                        workload["label"], workload["family"], workload.get("target_lines"),
                        state_name, index, f"{sample.get('wall_ms', 0):.3f}", sample.get("peak_rss_kb"),
                        sample.get("exit"), sample.get("timed_out"), sample.get("success"),
                        performed("parsed_modules"), reused("parsed_modules"),
                        performed("checked_bodies"), reused("checked_bodies"),
                        performed("instantiated_specializations"),
                        spec_bodies.get("performed", spec_bodies.get("checked")),
                        spec_bodies.get("reused"),
                        symbolic.get("performed", symbolic.get("checked")),
                        symbolic.get("reused"),
                        retention.get("retained_bytes"),
                        retention.get("ordinary_bytes"),
                        retention.get("symbolic_bytes"),
                        retention.get("specialization_bytes"),
                        retention.get("evicted"),
                        performed("lowered_functions"),
                        performed("emitted_fragments"), performed("links"),
                        performed("executed_tests"), sample.get("cached"),
                        sample.get("executed"), stages.get("reused_results"),
                        json.dumps(stages.get("bypassed")) if stages.get("bypassed") is not None else "",
                        len(sample.get("phase_timings") or []),
                    ])


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

def smoke_validation(compiler, scratch):
    """Build one small project per family and confirm it checks and runs before scaling."""
    reports = {}
    ordinary_root = Path(scratch) / "smoke-ordinary"
    entry, _ = generate_ordinary_modules(ordinary_root, 8, 3)
    reports["ordinary"] = validate(compiler, entry, run=True, timeout=300)
    managed_root = Path(scratch) / "smoke-managed"
    entry, _ = generate_managed(managed_root, 3, 5)
    reports["managed"] = validate(compiler, entry, run=True, timeout=300)
    maintained_root = Path(scratch) / "smoke-maintained"
    entry = copy_maintained(Path(__file__).resolve().parents[1] / "src/schematic/guest/main.my", maintained_root)
    reports["maintained"] = validate(compiler, entry, run=False, timeout=300)
    return reports


def default_workloads(options):
    workloads = []
    sizes = options.sizes or [10000, 100000]
    families = options.families
    if "ordinary" in families:
        for size in sizes:
            workloads.append({"family": "ordinary", "label": f"ordinary-{size // 1000}k",
                              "target_lines": size})
    if "managed" in families:
        for size in sizes:
            workloads.append({"family": "managed", "label": f"managed-{size // 1000}k",
                              "target_lines": size})
    if "maintained" in families:
        for source in options.maintained:
            workloads.append({"family": "maintained", "label": "maintained-" + Path(source).parent.name,
                              "source": source})
    return workloads


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--workdir", type=Path, default=None)
    parser.add_argument("--sizes", type=lambda value: [int(item) for item in value.split(",")],
                        default=None, help="comma-separated line targets, e.g. 10000,100000,500000")
    parser.add_argument("--families", type=lambda value: value.split(","),
                        default=["ordinary", "managed", "maintained"])
    parser.add_argument("--maintained", action="append", default=None,
                        help="repo-relative entry for a maintained workload (repeatable)")
    parser.add_argument("--samples", type=int, default=20,
                        help="samples for implementation/constant/signature edits and sessions")
    parser.add_argument("--baseline-samples", type=int, default=None,
                        help="samples for cold/unchanged/no-cache (default: --samples)")
    parser.add_argument("--extra-samples", type=int, default=None,
                        help="samples for union/provider/effect edits (default: min(--samples,5))")
    parser.add_argument("--test-samples", type=int, default=3)
    parser.add_argument("--session-samples", type=int, default=None,
                        help="samples for in-process session edits (default: min(--samples,5))")
    parser.add_argument("--timeout", type=float, default=900.0)
    parser.add_argument("--session-probe", action="store_true",
                        help="run a bounded check-session-v1 retention/miss probe per workload")
    parser.add_argument("--session-probe-checks", type=int, default=3,
                        help="bounded post-edit check-session probe requests (default 3)")
    parser.add_argument("--states", type=lambda value: value.split(","),
                        default=["cold", "unchanged", "no_cache", "implementation_edit",
                                 "constant_edit", "signature_edit", "union_edit",
                                 "provider_edit", "effect_edit", "forced_tests",
                                 "session_implementation_edit", "session_constant_edit"])
    parser.add_argument("--modules", type=int, default=None, help="ordinary family module count")
    parser.add_argument("--functions", type=int, default=None, help="functions per module/provider hint")
    parser.add_argument("--providers", type=int, default=None, help="managed family provider count")
    parser.add_argument("--no-call-depth", dest="call_depth", action="store_false", default=True)
    parser.add_argument("--no-validate-run", dest="validate_run", action="store_false", default=True)
    parser.add_argument("--probe-limits", action="store_true")
    parser.add_argument("--quick", action="store_true",
                        help="one small workload per family, three samples; smoke test only")
    parser.add_argument("--only", default=None, help="substring filter for workload labels")
    # legacy flags
    parser.add_argument("--repeats", type=int, default=None)
    return parser.parse_args(argv)


def write_outputs(args, document):
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2) + "\n")
    write_csv(args.output.with_suffix(".csv"), document["workloads"])


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    if args.repeats:
        args.samples = args.repeats
    if args.samples < 2:
        args.samples = 2
    repo_root = Path(__file__).resolve().parents[1]
    args.repo_root = repo_root
    if args.maintained is None:
        args.maintained = ["src/schematic/guest/main.my", "selfhost/prototype/bench.my"]
    if args.quick:
        args.sizes = [1000]
        args.families = ["ordinary", "managed"]
        args.samples = 3
        args.test_samples = 1
    workloads = default_workloads(args)
    if args.only:
        workloads = [item for item in workloads if args.only in item["label"]]

    scratch = Path(args.workdir) if args.workdir else Path(os.environ.get("MYLANG_S1_WORKDIR") or Path(tempfile.gettempdir()) / "mylang-s1-work")
    scratch.mkdir(parents=True, exist_ok=True)
    compiler = str(args.compiler.resolve())

    features = run_measured([compiler, "--features"], timeout=120)
    try:
        feature_document = json.loads(features["stdout"]) if features["exit"] == 0 else {}
    except ValueError:
        feature_document = {}

    smoke = smoke_validation(compiler, scratch)
    host_before = host_snapshot()
    document = {
        "version": "large-project-profile-v3",
        "schema": {
            "sample_work_report": "complete work-report-v1 object under sample.work_report; convenience stage views under sample.stages",
            "sample_phase_timings": "complete phase-timings-v1 JSON records under sample.phase_timings; exclusive records are disjoint, total is inclusive",
            "semantic_vs_frontend_retention": "sample.semantic_retention is the semantic checked-body store; sample.frontend_cache.retained_bytes is the syntax/frontend cache and must not be conflated with it",
            "successful_summary": "only samples with exit 0, no timeout and a work-report-v1 receipt enter summary/phase_summary",
            "warm_label": "state.status == measured only after a successful warm-up; failed/timed-out warm-ups are status blocked",
            "session_probe": "bounded raw check-session-v1 replies including semantic retention, per-kind bytes, evictions, specialization-body counters and labelled miss reasons",
        },
        "smoke_validation": smoke,
        "generated_at_unix": time.time(),
        "generator_sha256": sha256_file(__file__),
        "host": {"before": host_before, "after": None},
        "compiler": {
            "path": compiler,
            "sha256": sha256_file(compiler),
            "features_compiler_sha256": feature_document.get("compiler_sha256"),
            "zig_version": feature_document.get("zig_version"),
        },
        "method": {
            "wall_time": "process-start-to-exit, including dynamic linking, source load and command work; successful samples exclude nonzero exit and timeouts",
            "memory": "child ru_maxrss from wait4, max over successful samples",
            "percentile": "nearest-rank; sorted ascending; index ceil(0.95*n)-1",
            "samples_per_state": args.samples,
            "forced_test_samples": args.test_samples,
            "warmup": "one successful warm check is required before unchanged/edit states are measured; failed warm-up marks the state blocked",
            "edit_independence": "each sample writes a deterministic edit token unique to that sample",
            "validation": "check-project --no-cache --report must exit 0 before any timing; run-project for <=20k-line workloads",
            "phase_convention": "phase records are disjoint and inclusive=false except total (inclusive=true); nested parent phases are not emitted",
            "semantic_budget_env": "MYLANG_SEMANTIC_BUDGET",
            "semantic_budget_bytes": semantic_budget_bytes(),
        },
        "limits": verify_limit_sources(repo_root),
        "limit_findings": limit_findings(),
        "workloads": [],
    }

    if args.probe_limits:
        document["bounded_failure_probes"] = probe_bounded_failures(compiler, scratch / "limits")

    for workload in workloads:
        print(f"[s1] measuring {workload['label']} ...", flush=True)
        measured = measure_workload(compiler, workload, args, scratch)
        measured["objectives"] = evaluate_objectives(measured)
        document["workloads"].append(measured)
        write_outputs(args, document)
        print(f"[s1] {workload['label']}: {measured.get('status')}", flush=True)

    document["host"]["after"] = host_snapshot()
    write_outputs(args, document)
    print(json.dumps({
        "output": str(args.output),
        "workloads": [{"label": item["label"], "status": item.get("status"),
                       "objectives": item.get("objectives")} for item in document["workloads"]],
    }, indent=2))


if __name__ == "__main__":
    main()
