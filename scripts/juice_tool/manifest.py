"""Strict workload contracts. Source changes are separate from experiment changes."""
from __future__ import annotations

import math
from pathlib import Path
import re
import tomllib

from .common import JuiceError, digest, file_hash


def keys(value, allowed, where):
    if not isinstance(value, dict):
        raise JuiceError(f"{where} must be a table")
    unknown = value.keys() - set(allowed.split())
    if unknown:
        raise JuiceError(f"unknown {where} fields: {', '.join(sorted(unknown))}")


def strings(value, where, nonempty=False):
    if not isinstance(value, list) or any(not isinstance(x, str) or not x for x in value):
        raise JuiceError(f"{where} must be an array of nonempty strings")
    if nonempty and not value:
        raise JuiceError(f"{where} must not be empty")
    return value


def positive(value, where):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
        raise JuiceError(f"{where} must be finite and positive")


def relative(value):
    path = Path(value)
    if path.is_absolute() or ".." in path.parts or value in ("", "."):
        raise JuiceError(f"path must stay inside the project: {value}")
    return path


def files(root, patterns):
    result = {}
    for pattern in patterns:
        relative(pattern)
        matches = sorted(p for p in root.glob(pattern) if p.is_file())
        if not matches:
            raise JuiceError(f"declared input matches no files: {pattern}")
        for path in matches:
            if not path.resolve().is_relative_to(root):
                raise JuiceError(f"input symlink escapes the project: {path}")
            result[path.relative_to(root).as_posix()] = file_hash(path)
    return result


class Manifest:
    def __init__(self, path):
        self.path = Path(path).resolve()
        self.root = self.path.parent
        self.data = tomllib.loads(self.path.read_text())
        d = self.data
        keys(d, "version name adapter sources inputs environment build workloads", "manifest")
        if type(d.get("version")) is not int or d["version"] != 1:
            raise JuiceError("manifest version must be 1")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", d.get("name", "")):
            raise JuiceError("name must be 1..64 letters, digits, hyphens or underscores")
        d.setdefault("adapter", "native")
        if d["adapter"] not in ("native", "mylang"):
            raise JuiceError("adapter must be native or mylang")
        self.sources = files(self.root, strings(d.get("sources"), "sources", True))
        self.inputs = files(self.root, strings(d.setdefault("inputs", []), "inputs"))
        if self.sources.keys() & self.inputs.keys():
            raise JuiceError("sources and fixed inputs must be disjoint")
        if any(name.split("/")[0] in ("program", "counters.json", "collector") or
               name.split("/")[0].startswith("collector.") for name in self.inputs):
            raise JuiceError("input path collides with a runner control file")
        env = d.setdefault("environment", {})
        if not isinstance(env, dict) or any(not isinstance(v, str) for v in env.values()):
            raise JuiceError("environment must map names to strings")
        if set(env) & {"HOME", "TMPDIR", "PWD", "MYLANG_COUNTERS", "VALGRIND_LIB"}:
            raise JuiceError("HOME, TMPDIR, PWD and collector control variables are reserved")
        b = d.get("build")
        keys(b, "command compiler entry flags prefix dependencies tools timeout_seconds counter_semantics", "build")
        b.setdefault("timeout_seconds", 300)
        positive(b["timeout_seconds"], "build.timeout_seconds")
        for key in ("flags", "prefix", "dependencies", "tools"):
            strings(b.setdefault(key, []), "build." + key)
        if d["adapter"] == "native":
            strings(b.get("command"), "build.command", True)
            if not any("{binary}" in a for a in b["command"]):
                raise JuiceError("build.command must write {binary}")
            if b["command"][0] == "{compiler}" and not isinstance(b.get("compiler"), str):
                raise JuiceError("a {compiler} command needs build.compiler")
        else:
            if "command" in b:
                raise JuiceError("mylang builds are generated; use compiler, entry, flags and prefix")
            b.setdefault("compiler", "mylang")
            if not isinstance(b.get("entry"), str) or b["entry"] not in self.sources:
                raise JuiceError("mylang build.entry must be a declared source file")
            if not isinstance(b.get("counter_semantics"), str) or not b["counter_semantics"]:
                raise JuiceError("mylang requires build.counter_semantics identifying the counter hook contract")
            if any(f.split("=")[0] in ("--counters", "--debug", "--output", "--run") or f.startswith("-o") for f in b["flags"]):
                raise JuiceError("mylang flags cannot override release mode, output or instrumentation")
        workloads = d.get("workloads")
        if not isinstance(workloads, list) or not workloads:
            raise JuiceError("at least one [[workloads]] is required")
        names = set()
        for w in workloads:
            keys(w, "name family tier args units unit timeout_seconds expected_stdout stdout_sha256 stdout_regex expected_stderr exit_code check outputs region weight", "workload")
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", w.get("name", "")) or w["name"] in names:
                raise JuiceError("workload names must be unique simple identifiers")
            names.add(w["name"])
            w.setdefault("family", w["name"])
            if not isinstance(w["family"], str) or not w["family"]:
                raise JuiceError("workload.family must be a nonempty string")
            w.setdefault("tier", "quick")
            if w["tier"] not in ("quick", "validation"):
                raise JuiceError("workload tier must be quick or validation")
            if not isinstance(w.get("unit"), str) or not w["unit"]:
                raise JuiceError("workloads need a completed application unit (e.g. documents)")
            positive(w.get("units"), "workload.units")
            positive(w.setdefault("weight", 1), "workload.weight")
            positive(w.setdefault("timeout_seconds", 30), "workload.timeout_seconds")
            for key in ("args", "check", "outputs"):
                strings(w.setdefault(key, []), "workload." + key)
            for path in w["outputs"]:
                relative(path)
            if not any(key in w for key in ("expected_stdout", "stdout_sha256")) and not w["check"]:
                raise JuiceError("every workload needs expected_stdout, stdout_sha256 or a check command")
            if "stdout_regex" in w:
                pattern = re.compile(w["stdout_regex"], re.DOTALL)
                if pattern.groups != 1:
                    raise JuiceError("stdout_regex must full-match output and have exactly one capture group")
            w.setdefault("expected_stderr", "")
            for key in ("expected_stdout", "stdout_sha256", "expected_stderr"):
                if key in w and not isinstance(w[key], str):
                    raise JuiceError(f"workload.{key} must be a string")
            if "stdout_sha256" in w and not re.fullmatch(r"[a-f0-9]{64}", w["stdout_sha256"]):
                raise JuiceError("stdout_sha256 must be a lowercase SHA-256 digest")
            w.setdefault("exit_code", 0)
            if not isinstance(w["exit_code"], int) or w["exit_code"] != 0:
                raise JuiceError("performance workloads must complete successfully (exit_code = 0)")
            if "region" in w and (not isinstance(w["region"], str) or not w["region"]):
                raise JuiceError("region must be a nonempty emitted function name")

    def select(self, tier, names):
        selected = [w for w in self.data["workloads"]
                    if (tier == "all" or w["tier"] == tier) and (not names or w["name"] in names)]
        if not selected or (names and set(names) - {w["name"] for w in selected}):
            raise JuiceError("workload selection is empty or names a workload outside the selected tier")
        return selected

    def contract(self, workloads):
        return {"name": self.data["name"], "inputs": self.inputs,
                "environment": self.data["environment"], "workloads": workloads}

    def source_id(self):
        return digest(self.sources)
