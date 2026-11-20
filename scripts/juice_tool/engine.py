"""Isolated builds, identical execution paths, immutable records and oracles."""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import time

from . import VERSION
from .collectors import code_inventory, runtime_identity, summarize
from .common import (JuiceError, digest, environment, executable, expand, file_hash, implementation_id,
                     read_json, run, tool_identity, write_json)


def copy_files(source, target, identities):
    for name, expected in identities.items():
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / name, destination)
        if file_hash(destination) != expected:
            raise JuiceError(f"input changed while capturing: {name}")


def dependencies(paths, root):
    result = {}
    for name in paths:
        path = Path(name).expanduser()
        path = path if path.is_absolute() else root / path
        if not path.exists():
            raise JuiceError(f"missing build dependency: {name}")
        members = sorted(p for p in path.rglob("*") if p.is_file()) if path.is_dir() else [path]
        for member in members:
            result[str(member.resolve())] = file_hash(member)
    return result


def compiler_config(manifest, override):
    b = manifest.data["build"]
    compiler = override or b.get("compiler") or b["command"][0]
    identity = tool_identity(compiler)
    tools = {name: tool_identity(name) for name in b["tools"]}
    if manifest.data["adapter"] == "selka":
        tools["zig"] = tool_identity("zig")
    dependency_hashes = dependencies(b["dependencies"], manifest.root)
    # Hash the live build environment without writing its potentially secret values.
    build_env = dict(os.environ)
    for name in ("PWD", "OLDPWD", "SHLVL", "_", "JUICE_VALGRIND", "VALGRIND_LIB"):
        build_env.pop(name, None)
    return {"compiler": identity, "tools": tools, "dependencies": dependency_hashes,
            "spec": b, "environment_sha256": digest(build_env)}


def build(manifest, workspace, cache, config, static, counted=True):
    project = workspace / "project"
    if project.exists():
        shutil.rmtree(project)
    project.mkdir()
    copy_files(manifest.root, project, {**manifest.sources, **manifest.inputs})
    key = digest({"version": VERSION, "tool_id": implementation_id(), "sources": manifest.sources, "inputs": manifest.inputs,
                  "adapter": manifest.data["adapter"], "config": config, "static": static, "counted": counted})
    stored = cache / "builds" / key
    receipt = stored / "receipt.json"
    if receipt.exists():
        result = read_json(receipt)
        for name, expected in result["artifacts"].items():
            if not (stored / name).is_file() or file_hash(stored / name) != expected:
                raise JuiceError(f"corrupt build cache: {stored / name}")
        return stored, {**result, "cached": True, "build_seconds": 0}
    stored.mkdir(parents=True, exist_ok=True)
    b = manifest.data["build"]
    values = {"root": project, "binary": workspace / "built-program", "compiler": config["compiler"]["path"]}
    env = dict(os.environ, LC_ALL="C", LANG="C", TZ="UTC", PWD=str(project))
    result = {"key": key, "cached": False, "build_seconds": 0, "artifacts": {}}
    kinds = ("plain", "counted") if manifest.data["adapter"] == "selka" and counted else ("plain",)
    for kind in kinds:
        output = Path(values["binary"])
        output.unlink(missing_ok=True)
        if manifest.data["adapter"] == "native":
            command = expand(b["prefix"], values) + expand(b["command"], values)
        else:
            command = expand(b["prefix"], values) + [values["compiler"], "build", str(project / b["entry"]),
                      "--release", "-o", str(output), *expand(b["flags"], values)]
            if kind == "counted":
                command.append("--counters")
        row = run(command, project, env, stored / (kind + "-build"), b["timeout_seconds"])
        result["build_seconds"] += row["wall_seconds"]
        if row["exit_code"] or not output.is_file():
            raise JuiceError(f"{kind} build failed; logs: {stored}")
        shutil.copy2(output, stored / kind)
        result["artifacts"][kind] = file_hash(stored / kind)
    result["code"] = code_inventory(stored / "plain")
    cost_flags = {"--no-facts", "--verify-facts"}
    if static and manifest.data["adapter"] == "selka" and any(f not in cost_flags for f in b["flags"]):
        result["static_cost"] = {"status": "unavailable", "reason": "build flags are not supported by the cost adapter"}
    elif static and manifest.data["adapter"] == "selka":
        command = expand(b["prefix"], values) + [values["compiler"], "cost", str(project / b["entry"]), "--json", *b["flags"]]
        row = run(command, project, env, stored / "cost", b["timeout_seconds"])
        result["build_seconds"] += row["wall_seconds"]
        if row["exit_code"]:
            raise JuiceError(f"selka cost failed; logs: {stored}")
        result["static_cost"] = read_json(stored / "cost.stdout")
    write_json(receipt, result)
    return stored, result


def analyze(manifest, options):
    """Inspect release code and Core/LLVM remarks without executing the application."""
    cache = Path(options.cache_dir).expanduser().resolve() / manifest.data["name"]
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / ".lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        workspace = cache / "workspace"
        workspace.mkdir(exist_ok=True)
        config = compiler_config(manifest, options.compiler)
        _, result = build(manifest, workspace, cache, config, True, counted=False)
        return {"version": "juice-analysis-v1", "tool_id": implementation_id(),
                "source_root": str(manifest.root), "sources": manifest.sources, "build_config": config,
                "build": result, "scope": "static sites, optimization remarks and code bytes; no execution or juice score"}


def prepare(workspace, stored, kind, manifest):
    work = workspace / "run"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir()
    copy_files(manifest.root, work, manifest.inputs)
    shutil.copy2(stored / kind, work / "program")
    return work, environment(work, manifest.data["environment"])


def check_output(workload, row, prefix, work, project, env):
    stdout = Path(str(prefix) + ".stdout").read_bytes()
    stderr = Path(str(prefix) + ".stderr").read_bytes()
    if row["exit_code"] != workload["exit_code"]:
        raise JuiceError(f"{workload['name']}: exit {row['exit_code']} is not a completed workload")
    normalized = stdout
    if workload.get("stdout_regex"):
        match = re.fullmatch(workload["stdout_regex"], stdout.decode(), re.DOTALL)
        if not match:
            raise JuiceError(f"{workload['name']}: stdout does not match the declared normalization")
        normalized = match[1].encode()
    import hashlib
    output_hash = hashlib.sha256(normalized).hexdigest()
    if "expected_stdout" in workload and normalized != workload["expected_stdout"].encode():
        raise JuiceError(f"{workload['name']}: incorrect stdout; logs: {prefix}")
    if "stdout_sha256" in workload and output_hash != workload["stdout_sha256"]:
        raise JuiceError(f"{workload['name']}: incorrect stdout digest; logs: {prefix}")
    if stderr != workload["expected_stderr"].encode():
        raise JuiceError(f"{workload['name']}: incorrect stderr; logs: {prefix}")
    if workload["check"]:
        values = {"stdout": str(prefix) + ".stdout", "stderr": str(prefix) + ".stderr",
                  "work": work, "root": project, "binary": work / "program"}
        check = run(expand(workload["check"], values), work, env,
                    Path(str(prefix) + "-oracle"), workload["timeout_seconds"])
        if check["exit_code"]:
            raise JuiceError(f"{workload['name']}: correctness command failed; logs: {prefix}-oracle")
    outputs = {}
    for name in workload["outputs"]:
        path = work / name
        if not path.is_file() or not path.resolve().is_relative_to(work):
            raise JuiceError(f"{workload['name']}: missing or escaping output: {name}")
        outputs[name] = file_hash(path)
    return {"stdout": output_hash, "stderr": row["stderr_sha256"], "files": outputs}


def normalize_attribution(rows, project, work):
    merged = {}
    for source in rows:
        row = dict(source)
        for field in ("file", "object"):
            row[field] = row[field].replace(str(project), "{root}").replace(str(work), "{work}")
        identity = tuple(row.get(k) for k in ("file", "function", "object", "line"))
        if identity not in merged:
            merged[identity] = row
        else:
            for metric in ("instructions", "data_reads", "data_writes", "atomics"):
                if metric in row:
                    merged[identity][metric] += row[metric]
    return sorted(merged.values(), key=lambda r: r.get("instructions", 0), reverse=True)


def capture(manifest, collector, options):
    """Every successful record names its complete workload and immutable raw evidence."""
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", options.name):
        raise JuiceError("record name must be a simple identifier, at most 64 characters")
    if not 2 <= options.repeats <= 30:
        raise JuiceError("repeats must be 2..30")
    workloads = manifest.select(options.tier, options.workload)
    cache = Path(options.cache_dir).expanduser().resolve() / manifest.data["name"]
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / ".lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        destination = cache / "records" / options.name
        if destination.exists():
            raise JuiceError(f"record already exists (records are immutable): {destination}")
        destination.mkdir(parents=True)
        workspace = cache / "workspace"
        workspace.mkdir(exist_ok=True)
        record = {"version": VERSION, "tool_id": implementation_id(), "name": options.name, "status": "incomplete",
                  "manifest": manifest.data, "source_root": str(manifest.root), "sources": manifest.sources,
                  "contract": manifest.contract(workloads), "collector": collector.identity,
                  "workloads": {}, "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
        record_path = destination / "record.json"
        write_json(record_path, record)
        try:
            config = compiler_config(manifest, options.compiler)
            record["build_config"] = config
            stored, build_record = build(manifest, workspace, cache, config, options.static)
            record["build"] = build_record
            cpuinfo = Path("/proc/cpuinfo").read_text()
            block = next((b for b in cpuinfo.split("\n\n") if re.search(
                rf"^processor\s*:\s*{collector.cpu}$", b, re.M)), "")
            cpu_model = {k.strip(): v.strip() for k, _, v in (line.partition(":") for line in block.splitlines())
                         if k.strip() in ("vendor_id", "cpu family", "model", "model name", "stepping", "microcode", "flags")}
            staged_work, staged_env = prepare(workspace, stored, "plain", manifest)
            record["context"] = {"system": platform.system(), "kernel": platform.release(),
                                 "machine": platform.machine(), "cpu": cpu_model,
                                 "libraries": runtime_identity(staged_work / "program", staged_env),
                                 "execution_path": str(workspace / "run"), "collector": collector.identity}
            project = workspace / "project"
            for workload in workloads:
                print(f"juice: {workload['name']} ({collector.kind}, {options.repeats} samples)", flush=True)
                samples = []
                # Software instrumentation must also agree with an ordinary execution.
                trial_kinds = (["native"] if collector.kind != "perf" else []) + ["sample"] * options.repeats
                if manifest.data["adapter"] == "selka":
                    trial_kinds += ["counted"]
                cell = {"units": workload["units"], "unit": workload["unit"], "family": workload["family"],
                        "tier": workload["tier"], "region": workload.get("region"),
                        "scope": "selected function and callees" if workload.get("region") else "complete scenario",
                        "weight": workload["weight"]}
                for index, kind in enumerate(trial_kinds):
                    work, env = prepare(workspace, stored, "counted" if kind == "counted" else "plain", manifest)
                    values = {"root": project, "work": work, "binary": work / "program"}
                    argv = [str(work / "program"), *expand(workload["args"], values)]
                    prefix = destination / f"{workload['name']}-{index}-{kind}"
                    if kind == "counted":
                        env["SELKA_COUNTERS"] = str(work / "counters.json")
                    if kind == "sample":
                        row = collector.collect(argv, work, env, prefix, workload)
                    else:
                        row = run(argv, work, env, prefix, workload["timeout_seconds"], collector.cpu)
                    correctness = check_output(workload, row, prefix, work, project, env)
                    if "correctness" in cell and correctness != cell["correctness"]:
                        raise JuiceError(f"{workload['name']}: runs disagree on output")
                    cell["correctness"] = correctness
                    if kind == "sample":
                        for key in ("functions", "lines"):
                            row[key] = normalize_attribution(row[key], project, work)
                        samples.append(row)
                    elif kind == "counted":
                        document = read_json(work / "counters.json")
                        if document.get("version") != "selka-counters-v1" or not isinstance(document.get("totals"), dict):
                            raise JuiceError("unsupported selka counter document")
                        cell["semantic"] = document
                        for site in document.get("sites", []):
                            site["path"] = site.get("path", "").replace(str(project) + "/", "")
                        cell["counter_semantics"] = config["spec"]["counter_semantics"]
                        shutil.copy2(work / "counters.json", destination / f"{workload['name']}-counters.json")
                cell["metrics"] = summarize(samples)
                cell["samples"] = samples
                # Pick an actual sample nearest the median, never scale partial rows.
                chosen = min(samples, key=lambda s: abs(s["metrics"]["instructions"] - cell["metrics"]["instructions"]["median"]))
                cell["functions"], cell["lines"] = chosen["functions"], chosen["lines"]
                record["workloads"][workload["name"]] = cell
                write_json(record_path, record)
            record["status"] = "complete"
            record["evidence"] = {p.name: file_hash(p) for p in destination.iterdir() if p.is_file() and p != record_path}
            write_json(record_path, record)
        except (JuiceError, OSError, ValueError, subprocess.SubprocessError) as error:
            record["error"] = str(error)
            write_json(record_path, record)
            raise JuiceError(f"{error}\nincomplete record retained: {record_path}") from error
        return record_path
