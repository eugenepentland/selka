"""Count optimized executables; semantic counters are explanatory, separate runs."""
from __future__ import annotations

import glob
import math
import os
from pathlib import Path
import re
import statistics
import subprocess

from .common import JuiceError, digest, executable, file_hash, run, tool_identity


def cpu_set(text):
    result = set()
    for item in text.strip().split(","):
        if not item:
            continue
        bounds = list(map(int, item.split("-")))
        result.update(range(bounds[0], bounds[-1] + 1))
    return result


def perf_event(cpu):
    # Explicit PMU on hybrid x86 avoids an uncounted cpu_core/cpu_atom pseudo-event.
    for name in ("cpu_core", "cpu_atom"):
        path = Path("/sys/bus/event_source/devices") / name / "cpus"
        if path.exists() and cpu in cpu_set(path.read_text()):
            return f"{name}/instructions/u"
    return "instructions:u"


def parse_perf(text, event):
    rows = []
    for line in text.splitlines():
        fields = line.split(";")
        if len(fields) < 5 or fields[2].strip() != event:
            continue
        try:
            count = int(fields[0].strip())
            runtime = float(fields[3].strip())
            fraction = float(fields[4].strip())
        except ValueError as error:
            raise JuiceError(f"perf did not count {event}: {line}") from error
        # --no-scale plus 100% running: a partial count must never look like a win.
        if count <= 0 or not math.isfinite(runtime) or runtime <= 0 or fraction != 100.0:
            raise JuiceError(f"invalid or multiplexed perf count: {line}")
        rows.append(count)
    if len(rows) != 1:
        raise JuiceError(f"expected one {event} event, found {len(rows)}")
    return {"instructions": rows[0]}


def parse_grind(text):
    """Parse self costs, excluding call arcs; support compressed names/positions."""
    events, positions = [], ["line"]
    summary, totals = None, None
    names = {"file": {}, "function": {}, "object": {}}
    current = {"file": "???", "function": "???", "object": "???"}
    previous = [0]
    functions, lines = {}, {}
    skip_arc = False

    def resolve(kind, value):
        match = re.fullmatch(r"\((\d+)\)(?: (.*))?", value)
        if not match:
            return value
        number, name = match.groups()
        if name is not None:
            names[kind][number] = name
        if number not in names[kind]:
            raise JuiceError(f"unknown compressed {kind}: {value}")
        return names[kind][number]

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("events:"):
            events = line.split()[1:]
        elif line.startswith("positions:"):
            positions = line.split()[1:]
            previous = [0] * len(positions)
        elif line.startswith("summary:"):
            summary = list(map(int, line.split()[1:]))
        elif line.startswith("totals:"):
            totals = list(map(int, line.split()[1:]))
        elif "=" in line:
            tag, value = line.split("=", 1)
            kind = {"fl": "file", "fi": "file", "fe": "file", "cfl": "file", "cfi": "file",
                    "fn": "function", "cfn": "function", "ob": "object", "cob": "object"}.get(tag)
            if kind:
                name = resolve(kind, value)
                if not tag.startswith("c"):
                    current[kind] = name
            elif tag == "calls":
                skip_arc = True
        elif line[0].isdigit() or line[0] in "+-*":
            if not events:
                raise JuiceError("cost row precedes event definitions")
            cells = line.split()
            if len(cells) < len(positions) + 1:
                raise JuiceError("truncated cost row")
            for i, value in enumerate(cells[:len(positions)]):
                if value != "*":
                    number = int(value, 16 if "x" in value.lower() else 10)
                    previous[i] = previous[i] + number if value.startswith(("+", "-")) else number
            values = list(map(int, cells[len(positions):]))
            if len(values) > len(events) or any(v < 0 for v in values):
                raise JuiceError("invalid cost row")
            values += [0] * (len(events) - len(values))
            if skip_arc:
                skip_arc = False
                continue
            key = (current["file"], current["function"], current["object"])
            target = functions.setdefault(key, [0] * len(events))
            for i, value in enumerate(values):
                target[i] += value
            lineno = previous[positions.index("line")] if "line" in positions else 0
            target = lines.setdefault((*key, lineno), [0] * len(events))
            for i, value in enumerate(values):
                target[i] += value
    # Callgrind's summary may be zero with collection toggles; totals is the
    # sum of self costs for this dump. Never aggregate inclusive call costs.
    total = totals if totals is not None else summary
    if not events or total is None or len(total) > len(events) or "Ir" not in events or any(v < 0 for v in total):
        raise JuiceError("missing or incompatible Valgrind totals/events")
    total += [0] * (len(events) - len(total))
    summed = [sum(v[i] for v in functions.values()) for i in range(len(events))]
    if summed != total:
        raise JuiceError(f"Valgrind self costs do not reconcile: {summed} != {total}")

    def metrics(values):
        mapping = {"Ir": "instructions", "Dr": "data_reads", "Dw": "data_writes", "Ge": "atomics"}
        return {mapping[e]: v for e, v in zip(events, values) if e in mapping}

    return {"metrics": metrics(total), "functions": [
        {"file": k[0], "function": k[1], "object": k[2], **metrics(v)}
        for k, v in functions.items()], "lines": [
        {"file": k[0], "function": k[1], "object": k[2], "line": k[3], **metrics(v)}
        for k, v in lines.items()]}


class Collector:
    def __init__(self, kind, cpu=None, perf="perf", valgrind="valgrind"):
        if kind not in ("perf", "cachegrind", "callgrind"):
            raise JuiceError("collector must be perf, cachegrind or callgrind")
        allowed = os.sched_getaffinity(0)
        reserved = cpu_set(os.environ.get("MYLANG_TIMING_CPUS", "2,3,10,11"))
        usable = allowed - reserved
        self.cpu = cpu if cpu is not None else min(usable or allowed)
        if self.cpu not in allowed:
            raise JuiceError(f"CPU {self.cpu} is outside the allowed affinity")
        self.kind = kind
        self.tool = tool_identity(perf if kind == "perf" else valgrind)
        self.event = perf_event(self.cpu) if kind == "perf" else "Ir"
        self.identity = {"kind": kind, "tool": self.tool, "event": self.event, "cpu": self.cpu,
                         "scope": "user instructions; process and inherited children; whole workload"}
        self.extra_env = {}
        if kind != "perf" and os.environ.get("VALGRIND_LIB"):
            library = Path(os.environ["VALGRIND_LIB"]).resolve()
            self.extra_env["VALGRIND_LIB"] = str(library)
            # Include the actual instrumentation engine, not just the launcher.
            self.identity["engines"] = {p.name: file_hash(p) for p in library.glob(f"{kind}-*") if p.is_file()}

    def collect(self, argv, work, env, prefix, workload):
        raw = str(work / "collector")
        if workload.get("region") and self.kind != "callgrind":
            raise JuiceError("function regions require callgrind; use a short harness with perf")
        if self.kind == "perf":
            command = [self.tool["path"], "stat", "--no-big-num", "--no-scale", "-x", ";",
                       "-e", self.event, "-o", raw, "--", *argv]
        else:
            command = [self.tool["path"], f"--tool={self.kind}", "--trace-children=yes",
                       "--cache-sim=no", "--branch-sim=no", f"--log-file={raw}.log.%p",
                       f"--{self.kind}-out-file={raw}.%p"]
            if self.kind == "callgrind":
                command += ["--collect-bus=yes", "--dump-line=yes", "--dump-instr=yes"]
                if workload.get("region"):
                    command += [f"--toggle-collect={workload['region']}"]
            command += argv
        result = run(command, work, {**env, **self.extra_env}, prefix,
                     workload["timeout_seconds"], self.cpu)
        result.update(functions=[], lines=[])
        if result["exit_code"] != 0:
            raise JuiceError(f"collector/program exited {result['exit_code']}; logs: {prefix}")
        import shutil
        if self.kind == "perf":
            result["metrics"] = parse_perf(Path(raw).read_text(), self.event)
            shutil.copy2(raw, str(prefix) + ".perf")
        else:
            paths = [Path(p) for p in glob.glob(raw + ".*") if re.fullmatch(re.escape(raw) + r"\.\d+", p)]
            if not paths:
                raise JuiceError("Valgrind did not write a profile")
            result["metrics"] = {}
            for index, path in enumerate(sorted(paths)):
                parsed = parse_grind(path.read_text())
                for key, value in parsed["metrics"].items():
                    result["metrics"][key] = result["metrics"].get(key, 0) + value
                for key in ("functions", "lines"):
                    result[key].extend(parsed[key])
                shutil.copy2(path, str(prefix) + f".grind-{index}")
            for index, path in enumerate(sorted(glob.glob(raw + ".log.*"))):
                shutil.copy2(path, str(prefix) + f".valgrind-{index}.log")
        if result["metrics"].get("instructions", 0) <= 0:
            raise JuiceError("no measured instructions: region may be absent or optimized away")
        return result


def summarize(samples):
    result = {}
    for metric in samples[0]["metrics"]:
        values = [s["metrics"][metric] for s in samples]
        middle = statistics.median(values)
        result[metric] = {"samples": values, "median": middle, "min": min(values), "max": max(values),
                          "spread": (max(values) - min(values)) / middle if middle else 0}
    return result


def code_inventory(binary):
    """Static sites are explanatory, never weighted as executed instructions."""
    result = {"sections": {}, "functions": {}, "available": False}
    try:
        sizes = subprocess.check_output(["size", "-A", str(binary)], text=True, timeout=15)
        symbols = subprocess.check_output(["nm", "-S", "--defined-only", str(binary)], text=True, timeout=15)
        assembly = subprocess.check_output(["objdump", "-d", "--no-show-raw-insn", str(binary)], text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return result
    for line in sizes.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[0].startswith("."):
            result["sections"][fields[0]] = int(fields[1])
    for line in symbols.splitlines():
        fields = line.split(maxsplit=3)
        if len(fields) == 4 and fields[2] in ("t", "T"):
            result["functions"][fields[3]] = {"bytes": int(fields[1], 16)}
    current = None
    for line in assembly.splitlines():
        header = re.match(r"^[0-9a-f]+ <(.+)>:$", line)
        if header:
            current = result["functions"].setdefault(header[1], {"bytes": 0})
        elif current is not None:
            ins = re.match(r"\s*[0-9a-f]+:\s+(\S+)(.*)", line)
            if ins:
                op = ins[1]
                memory_exchange = op.startswith("xchg") and "(" in ins[2]
                kind = ("atomic_sites" if op == "lock" or memory_exchange else
                        "divide_sites" if op.startswith(("div", "idiv", "vdiv")) else
                        "vector_sites" if op.startswith("v") else None)
                if kind:
                    current[kind] = current.get(kind, 0) + 1
    result["available"] = True
    return result


def runtime_identity(binary, env=None):
    result = subprocess.run([executable("ldd"), str(binary)], capture_output=True, text=True, timeout=15, env=env)
    if "=> not found" in result.stdout:
        raise JuiceError("executable has an unresolved shared library")
    libs = {}
    for line in result.stdout.splitlines():
        match = re.search(r"(?:=>\s+)?(/\S+)", line)
        if match and Path(match[1]).is_file():
            libs[match[1]] = file_hash(match[1])
    if result.returncode and "not a dynamic executable" not in result.stderr + result.stdout:
        raise JuiceError("cannot determine executable's shared-library identity")
    return libs
