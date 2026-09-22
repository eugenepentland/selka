"""Version 2 input inventories and successful execution receipts.

Complete declarations are a trust contract, not an OS sandbox. Jobs must declare
all inputs and tools; network, clock, random and undeclared host reads require
complete=false. No existing gate is switched to affected mode automatically.
"""
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import time
import stat
import subprocess


def module_graph(root, filename):
    """Use compiler receipts only when every declared byte and edge is current."""
    if not filename:
        return None
    try:
        receipt = json.loads((root / filename).read_text())
        if receipt["version"] != "project-dependencies-v1" or receipt["complete"] is not True:
            raise ValueError("incomplete receipt")
        modules = {item["module"] for item in receipt["inputs"]}
        generated = {item["module"] for item in receipt.get("manifests", [])}
        for item in receipt.get("manifests", []) + receipt["inputs"]:
            path = Path(item["path"])
            if path.is_absolute() or ".." in path.parts:
                raise ValueError("external receipt input")
            generated_source = item in receipt["inputs"] and item["module"] in generated
            compiler_source = item in receipt["inputs"] and item["path"].startswith("@stdlib/")
            if not generated_source and not compiler_source and file_hash(root / path) != item["sha256"]:
                raise ValueError("stale or external receipt input")
            if any(edge["module"] not in modules for edge in item.get("imports", [])):
                raise ValueError("incomplete import graph")
        return {"valid": True, "receipt": receipt, "receipt_sha256": file_hash(root / filename)}
    except (OSError, ValueError, KeyError, TypeError):
        return {"valid": False, "reason": "module graph unavailable, incomplete or stale; full uncached fallback"}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def bounded_bytes(path, limit=512 * 1024 * 1024):
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError(f"nonregular input: {path}")
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise ValueError(f"input exceeds byte budget: {path}")
        return data


def file_hash(path):
    return hashlib.sha256(bounded_bytes(path)).hexdigest()


_REPORTED_IDENTITIES = {}


def compiler_identities(root, tools):
    """Build-time identities reported by whichever declared tools are mylang compilers.

    A compiler receipt records the compiler's own identity - a build-time digest of its
    sources and toolchain - not a hash of its executable, so pinning a receipt to a
    declared tool means asking that tool who it is. Answers are memoized per path and
    content hash, and a tool that does not answer contributes no identity.
    """
    found = set()
    for tool in tools.values():
        path = Path(tool["path"])
        key = (tool["path"], tool["sha256"])
        if key not in _REPORTED_IDENTITIES:
            _REPORTED_IDENTITIES[key] = reported_identity(path if path.is_absolute() else root / path)
        if _REPORTED_IDENTITIES[key] is not None:
            found.add(_REPORTED_IDENTITIES[key])
    return found


def reported_identity(path):
    try:
        result = subprocess.run([str(path), "--features"], capture_output=True, timeout=60)
        report = json.loads(result.stdout) if result.returncode == 0 else {}
        identity = report.get("compiler_sha256") if report.get("version") == "language-features-v1" else None
        return identity if isinstance(identity, str) else None
    except (OSError, ValueError, subprocess.SubprocessError):
        return None


def capture_tree(root, destination, entries):
    destination.mkdir(parents=True)
    for name, (_, mode) in entries.items():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(bounded_bytes(root / name, 128 * 1024 * 1024))
        target.chmod(mode)


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".receipt-")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream, sort_keys=True)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def lock_path(cache_dir, key):
    """A fixed 256-shard namespace bounds lock inodes without unlink races."""
    return Path(cache_dir) / "locks" / (hashlib.sha256(key.encode()).hexdigest()[:2] + ".lock")


@contextlib.contextmanager
def locked(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def validate(data, legacy):
    if set(data) != {"version", "policy", "steps"} or data.get("version") != 2:
        raise ValueError("v2 manifest requires version, policy, steps")
    if not isinstance(data["policy"], str) or not data["policy"]:
        raise ValueError("policy must be a nonempty identity")
    stripped = []
    for step in data["steps"]:
        for field in ("inputs", "tools", "env"):
            values = step.get(field, [])
            if not isinstance(values, list) or any(not isinstance(v, str) or not v or "\0" in v for v in values):
                raise ValueError(f"{field} must be strings")
        if "module_graph" in step and (not isinstance(step["module_graph"], str) or not step["module_graph"]):
            raise ValueError("module_graph must name a receipt")
        for pattern in step.get("inputs", []) + ([step["module_graph"]] if "module_graph" in step else []) + ([step["path"]] if "path" in step else []):
            if Path(pattern).is_absolute() or ".." in Path(pattern).parts:
                raise ValueError("input patterns must stay inside the project")
        if type(step.get("complete", False)) is not bool:
            raise ValueError("complete must be boolean")
        stripped.append({k: v for k, v in step.items() if k not in {"inputs", "tools", "env", "complete", "module_graph"}})
    legacy.validate({"version": 1, "steps": stripped})
    return data["steps"]


def tree(root):
    """Fail closed above 50k entries/128 MiB; never read devices or links."""
    result = {}
    total = 0
    count = 0
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(name for name in dirs if name != ".git")
        for name in dirs + sorted(files):
            if name == ".git":
                continue
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            info = path.lstat()
            count += 1
            if count > 50000:
                raise ValueError("snapshot exceeds 50000 entries; use a smaller verification root")
            if stat.S_ISDIR(info.st_mode):
                continue
            if not stat.S_ISREG(info.st_mode):
                raise ValueError(f"snapshot rejects nonregular file: {relative}")
            total += info.st_size
            if total > 128 * 1024 * 1024:
                raise ValueError("snapshot exceeds 128 MiB; use a smaller verification root")
            result[relative] = [file_hash(path), info.st_mode & 0o777]
    return result


def inputs(root, patterns):
    result = {}
    for pattern in patterns:
        members = {}
        for path in sorted(root.glob(pattern)):
            if path.is_file():
                members[path.relative_to(root).as_posix()] = [file_hash(path), path.stat().st_mode & 0o777]
        result[pattern] = members
    return result


def tools_for(step, root):
    if any(not Path(part).is_absolute() for part in os.environ.get("PATH", os.defpath).split(os.pathsep)):
        raise ValueError("verification requires absolute nonempty PATH entries")
    identities = {}
    names = set(step.get("tools", []))
    names.update(command[0] for command in step.get("commands", []))
    for name in sorted(names):
        candidate = root / name if "/" in name and not Path(name).is_absolute() else Path(shutil.which(name) or name)
        if not candidate.is_file():
            raise ValueError(f"tool not found: {name}")
        identities[name] = {"sha256": file_hash(candidate.resolve()), "path": str(candidate.resolve()), "mode": candidate.stat().st_mode & 0o777}
        if candidate.is_relative_to(root):
            identities[name]["path"] = candidate.relative_to(root).as_posix()
    return identities


def inventory(root, data):
    jobs = {}
    for step in data["steps"]:
        patterns = step.get("inputs", []) + ([step["path"]] if step["kind"] == "spec" else [])
        graph = module_graph(root, step.get("module_graph"))
        jobs[step["id"]] = {"module_graph": graph,"definition": step, "inputs": inputs(root, patterns),
                            "tools": tools_for(step, root),
                            "env": {name: os.environ.get(name) for name in step.get("env", [])},
                            "policy": data["policy"], "protocol": 2,
                            "driver": {path.name: file_hash(path) for path in sorted(Path(__file__).parent.glob("*.py"))}
                                      | {"verify.py": file_hash(Path(__file__).parents[1] / "verify.py")},
                            "path_environment": os.environ.get("PATH", os.defpath)}
        if graph and graph["valid"]:
            compiler_hash = graph["receipt"].get("implementation", {}).get("compiler_sha256")
            if compiler_hash not in compiler_identities(root, jobs[step["id"]]["tools"]):
                graph.update(valid=False, reason="receipt compiler must be a declared current tool")
        complete = step.get("complete", False) and (graph is None or graph["valid"])
        complete = complete and all(jobs[name]["complete"] for name in step.get("depends_on", []))
        jobs[step["id"]]["complete"] = complete
        if not complete:
            jobs[step["id"]]["conservative_tree"] = tree(root)
        jobs[step["id"]]["dependencies"] = {name: digest(jobs[name]) for name in step.get("depends_on", [])}
    return jobs


def cached(path, key):
    try:
        wrapper = json.loads(path.read_text())
        row = wrapper["receipt"]
        if wrapper["sha256"] != digest(row) or row["job_key"] != key or row["status"] != "executed" or not row["passed"]:
            return None
        for command in row.get("commands", []):
            import base64
            for name in ("stdout", "stderr"):
                content = base64.b64decode(command[name + "_base64"], validate=True)
                if hashlib.sha256(content).hexdigest() != command[name + "_sha256"]:
                    return None
        return dict(row, status="cached", executed=False, original_execution=row["finished_at"])
    except (OSError, ValueError, KeyError, TypeError):
        return None


def execute_step(step, root, legacy, environment):
    if step["kind"] == "spec":
        path = root / step["path"]
        passed = path.is_file() and step["contains"].encode() in path.read_bytes()
        return {"passed": passed, "executed": True}
    results = [legacy.command(argv, root, step, env=environment)
               for _ in range(step.get("repeats", 1)) for argv in step["commands"]]
    passed = all(row["passed"] for row in results)
    if step["kind"] == "parity" and passed:
        passed = all((r["exit"], r["stdout_base64"]) == (results[0]["exit"], results[0]["stdout_base64"]) for r in results)
    return {"passed": passed, "executed": any(row["executed"] for row in results), "commands": results}


def run_manifest(manifest, *, cache_dir, previous=None, mode="full", patterns=(), executor=None):
    import importlib.util
    spec = importlib.util.spec_from_file_location("verification_legacy", Path(__file__).parents[1] / "verify.py")
    legacy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(legacy)
    manifest = Path(manifest).resolve()
    raw_manifest = bounded_bytes(manifest, 1024 * 1024)
    data = json.loads(raw_manifest, object_pairs_hook=legacy.unique_object)
    if data.get("version") == 1:
        return legacy.run(manifest, patterns)
    steps = validate(data, legacy)
    if mode not in {"full", "affected", "shadow"}:
        raise ValueError("unknown selection mode")
    root = manifest.parent
    cache_dir = Path(cache_dir).resolve()
    if cache_dir == root or root in cache_dir.parents:
        raise ValueError("verification cache must be outside the source root")
    disabled_path = cache_dir / "policies" / (digest(data["policy"]) + ".disabled.json")
    disabled = disabled_path.exists()
    start = time.monotonic()
    before = tree(root)
    with tempfile.TemporaryDirectory(prefix="verification-capture-") as temporary:
        capture = Path(temporary) / "source"
        capture_tree(root, capture, before)
        if before != tree(root) or before != tree(capture) or bounded_bytes(capture / manifest.name) != raw_manifest:
            raise ValueError("source changed during snapshot capture; retry")
        jobs = inventory(capture, data)
        old = (previous or {}).get("inventory", {})
        requested, selected = legacy.select(steps, patterns)
        affected = {name for name in selected if jobs[name] != old.get(name)}
        if disabled or not all(job["complete"] for job in jobs.values()) or not old:
            affected = set(selected)
        for step in reversed(steps):
            if step["id"] in affected:
                affected.update(step.get("depends_on", []))
        actual = affected if mode == "affected" else selected
        rows = []
        states = {}
        selection_seconds = time.monotonic() - start
        for step in steps:
            name = step["id"]
            key = digest(jobs[name])
            row = {"id": name, "kind": step["kind"], "job_key": key, "executed": False, "passed": False}
            if name not in actual:
                row.update(status="not-selected", reason="unchanged declared dependency closure" if name in selected else "manual selector")
            elif any(not states[d]["passed"] for d in step.get("depends_on", [])):
                row.update(status="blocked", reason="prerequisite has no successful evidence")
            else:
                reusable = jobs[name]["complete"] and step["kind"] != "benchmark" and mode != "shadow" and not disabled
                def perform(step=step, row=row, key=key, reusable=reusable):
                    receipt_path = cache_dir / "receipts" / (key + ".json")
                    with locked(lock_path(cache_dir, key)):
                        hit = cached(receipt_path, key) if reusable else None
                        if hit:
                            return hit
                        workspace = cache_dir / "work" / key
                        if workspace.exists():
                            shutil.rmtree(workspace)
                        shutil.copytree(capture, workspace)
                        environment = {k: v for k, v in jobs[step["id"]]["env"].items() if v is not None}
                        # PATH is part of executable resolution and is always keyed below.
                        environment["PATH"] = os.environ.get("PATH", os.defpath)
                        result = {**row, **execute_step(step, workspace, legacy, environment if jobs[step["id"]]["complete"] else None)}
                        result.update(status="executed" if result["passed"] else "failed", finished_at=time.time())
                        if reusable and result["passed"]:
                            if inventory(root, data) != jobs or inventory(workspace, data)[step["id"]] != jobs[step["id"]]:
                                result.update(status="failed", passed=False, reason="inputs changed during verification")
                            elif executor is None:
                                atomic_json(receipt_path, {"receipt": result, "sha256": digest(result)})
                        shutil.rmtree(workspace)
                        return result
                row = executor(key if reusable else key + "-" + str(time.time_ns()), perform) if executor else perform()
                if executor and reusable and row["passed"] and row["status"] == "executed":
                    if inventory(root, data) != jobs:
                        row.update(status="failed", passed=False, reason="inputs changed before fenced publication")
                    else:
                        atomic_json(cache_dir / "receipts" / (key + ".json"), {"receipt": row, "sha256": digest(row)})
            states[name] = row
            rows.append(row)
        unchanged = tree(root) == before and inventory(root, data) == jobs
        if not unchanged:
            for row in rows:
                if row["passed"]:
                    row.update(passed=False, status="failed", reason="source or tool changed before final receipt validation")
        report = {"source_unchanged": unchanged, "version": 2, "policy": data["policy"], "inventory": jobs, "snapshot_sha256": digest(before),
                  "mode": mode, "selected": sorted(actual), "affected": sorted(affected), "steps": rows,
                  "selection_seconds": selection_seconds, "runtime_coverage": "not measured"}
        report["selected_passed"] = bool(actual) and all(states[n]["passed"] for n in actual)
        report["full_manifest_passed"] = all(row["passed"] for row in rows)
        report["shadow_omissions"] = [row["id"] for row in rows if mode == "shadow" and row["id"] not in affected and not row["passed"]]
        if report["shadow_omissions"]:
            atomic_json(disabled_path, {"policy": data["policy"], "omissions": report["shadow_omissions"], "time": time.time()})
        report["selection_disabled"] = disabled or bool(report["shadow_omissions"])
        return report


def collect_cache(cache_dir, max_bytes=512 * 1024 * 1024):
    """Bound receipts and abandoned workspaces; never remove an active job."""
    cache_dir = Path(cache_dir)
    receipts = sorted((cache_dir / "receipts").glob("*.json"), key=lambda path: path.stat().st_mtime)
    total = sum(path.stat().st_size for path in receipts)
    removed = 0
    for path in receipts:
        if total <= max_bytes:
            break
        lock = lock_path(cache_dir, path.stem)
        with lock.open("a") as stream:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                continue
            try:
                size = path.stat().st_size
                path.unlink()
                total -= size
                removed += 1
            except FileNotFoundError:
                pass
    for path in (cache_dir / "work").glob("*"):
        with lock_path(cache_dir, path.name).open("a") as stream:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                continue
            shutil.rmtree(path, ignore_errors=True)
    return {"receipts_removed": removed, "receipt_bytes": total}
