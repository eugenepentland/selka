"""Read-only bootstrap evidence diagnostics; partial components never grant completion."""
import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zlib

SUPPORTED_OWNER_COMMIT = "dff9304b9cd7bc72e66f9feb20f1b05281d67333"
PACKAGES = {"test-index": ("test_index", 1, 1), "cache-plan": ("cache_plan", 2, 2),
            "lexer-pilot": ("lexer_pilot", 1, 2), "parser-pilot": ("parser_pilot", 1, 2),
            "declaration-index": ("declaration_index", 1, 1),
            "type-interface": ("type_interface", 1, 1), "body-check": ("body_check", 1, 11)}
ARCHIVES = ("selka-body-wave-integration-20261011", "selka-bootstrap-gate-repairs-20261011")
REQUIRED = ("source-current schema11 deployment and full producer/seed/tool/runtime ABI closure",
            "owner-approved admission migration with authenticated timing provenance",
            "complete language/compiler ownership and required correctness/fact/leak parity",
            "seed to stage1 to stage2 to stage3 manifests and artifact equivalence",
            "every mandatory workload median and p95 <=1.5x frozen Zig with raw samples")


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def pairs(values):
    result = {}
    for key, value in values:
        if key in result:
            raise ValueError("duplicate JSON key: " + key)
        result[key] = value
    return result


def parse(data):
    value = json.loads(data, object_pairs_hook=pairs)
    if not isinstance(value, dict):
        raise ValueError("evidence JSON must be an object")
    return value


def digest(value):
    if not isinstance(value, str) or not re.fullmatch("[0-9a-f]{64}", value):
        raise ValueError("missing or malformed content digest")
    return value


def basename(value):
    if not isinstance(value, str) or not value or Path(value).name != value or value in (".", ".."):
        raise ValueError("unsafe artifact/archive name")
    return value


class Observations:
    """Bound streaming reads and retain input digests, never persistent success authority."""
    def __init__(self, byte_budget=2 * 1024 * 1024 * 1024):
        self.byte_budget = byte_budget
        self.bytes_read = 0
        self.seeds = {}
        self.inputs = {}
        self.metadata = {}
        self.trees = {}

    def read(self, path, role, *, limit=8 * 1024 * 1024, retain=True):
        path = Path(path).absolute()
        link = path.lstat()
        with path.open("rb") as source:
            before = os.fstat(source.fileno())
            sha = hashlib.sha256()
            chunks = []
            size = 0
            while chunk := source.read(65536):
                size += len(chunk)
                self.bytes_read += len(chunk)
                if self.bytes_read > self.byte_budget:
                    raise ValueError("aggregate diagnostic byte budget exceeded")
                if size > limit:
                    raise ValueError("input exceeds bounded read: " + str(path))
                sha.update(chunk)
                if retain:
                    chunks.append(chunk)
            after = os.fstat(source.fileno())
        current = path.stat()
        fields = lambda stat: (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)
        if fields(before) != fields(after) or fields(after) != fields(current) or fields(link) != fields(path.lstat()):
            raise ValueError("input changed during read: " + str(path))
        identity = {"path": str(path), "role": role, "sha256": sha.hexdigest(), "bytes": size}
        previous = self.inputs.get(str(path))
        if previous and previous["sha256"] != identity["sha256"]:
            raise ValueError("input changed between reads: " + str(path))
        metadata = (fields(after), fields(path.lstat()), str(path.resolve()))
        if str(path) in self.metadata and self.metadata[str(path)] != metadata:
            raise ValueError("input metadata/alias changed between reads: " + str(path))
        self.metadata[str(path)] = metadata
        self.inputs[str(path)] = identity
        return b"".join(chunks) if retain else identity["sha256"]

    def tree(self, root):
        result = {}
        for directory, subdirs, files in os.walk(root, followlinks=False):
            subdirs[:] = sorted(name for name in subdirs if name != "__pycache__")
            for name in sorted(files):
                if name.endswith(".pyc"):
                    continue
                path = Path(directory) / name
                if path.is_file():
                    result[path.relative_to(root).as_posix()] = self.read(path, "component-source", retain=False)
                if len(result) > 4096:
                    raise ValueError("source inventory exceeds bridge bound")
        self.trees[str(root)] = result
        return result

    def recheck(self):
        # Re-read content; this observation is not a watch or a reusable live snapshot.
        for root, expected in list(self.trees.items()):
            if self.tree(Path(root)) != expected:
                raise ValueError("source membership changed during observation: " + root)
        for value in list(self.inputs.values()):
            self.read(value["path"], value["role"], limit=max(value["bytes"], 1), retain=False)


def seed_identity(observations, cache, seed, pin, zig):
    if seed["recipe"]["pin"] != pin:
        raise ValueError("producer seed pin differs from current immutable pin")
    key = hashlib.sha256(canonical(seed["recipe"])).hexdigest()
    if key in observations.seeds:
        previous, result = observations.seeds[key]
        if previous != seed:
            raise ValueError("same seed recipe has conflicting qualifications")
        return result
    directory = cache / "seeds" / key
    receipt = parse(observations.read(directory / "receipt.json", "seed-receipt"))
    if receipt != seed:
        raise ValueError("embedded qualification differs from selected seed receipt")
    compiler = directory / "source/zig-out/focus/mylang"
    if observations.read(compiler, "seed-executable", limit=512 * 1024 * 1024, retain=False) != digest(seed["sha256"]):
        raise ValueError("qualified seed executable content differs")
    if zig is not None and observations.read(zig, "zig-executable", limit=512 * 1024 * 1024, retain=False) != digest(seed["recipe"]["zig_sha256"]):
        raise ValueError("seed tool executable content differs")
    result = {"key": key, "sha256": seed["sha256"], "pin_commit": pin["commit"],
              "scope": "receipt and binary observed; full tool-library/runtime closure remains unqualified"}
    observations.seeds[key] = (receipt, result)
    return result


def package(observations, root, cache, name, pin, zig):
    source, protocol, schema = PACKAGES[name]
    installed = root / "zig-out/libexec/mylang/components"
    manifest = parse(observations.read(installed / (name + ".json"), "component-manifest"))
    if manifest.get("component") != name or type(manifest.get("format")) is not int or manifest.get("format") != 1:
        raise ValueError("wrong selected component manifest")
    if type(manifest.get("protocol")) is not int or type(manifest.get("schema")) is not int:
        raise ValueError("component wire versions must be integers")
    artifact = installed / basename(manifest.get("artifact"))
    if observations.read(artifact, "component-executable", limit=64 * 1024 * 1024, retain=False) != digest(manifest.get("sha256")):
        raise ValueError("selected component artifact digest differs")
    key = digest(manifest.get("key"))
    receipt = parse(observations.read(cache / "artifacts" / key / "receipt.json", "producer-receipt"))
    identity = receipt["identity"]
    if not isinstance(identity, dict) or not isinstance(identity.get("sources"), dict):
        raise ValueError("malformed producer identity/source map")
    if hashlib.sha256(canonical(identity)).hexdigest() != key or receipt["sha256"] != manifest["sha256"]:
        raise ValueError("producer receipt is not bound to manifest key/artifact")
    for field in ("component", "protocol", "schema"):
        if identity[field] != manifest[field]:
            raise ValueError("manifest and producer contract differ: " + field)
    if identity.get("build_cache_root") != str(cache):
        raise ValueError("producer cache-root identity differs from requested store")
    seed = seed_identity(observations, cache, identity["seed"], pin, zig)
    current_sources = observations.tree(root / "selfhost/components" / source)
    if not current_sources:
        raise ValueError("component source inventory is empty")
    current = identity["sources"] == current_sources
    changed = sorted(path for path in set(identity["sources"]) | set(current_sources)
                     if identity["sources"].get(path) != current_sources.get(path))
    versions = manifest["protocol"] == protocol and manifest["schema"] == schema
    return {"component": name, "manifest_key": key, "artifact_sha256": manifest["sha256"],
            "protocol": manifest["protocol"], "schema": manifest["schema"], "expected_schema": schema,
            "schema_current": versions, "source_current": current, "source_files": len(current_sources),
            "changed_source_paths": changed[:32], "changed_source_count": len(changed),
            "changed_source_paths_truncated": len(changed) > 32,
            "seed": seed, "complete": False}


def archives(observations, root, name):
    directory = root / "docs/audits/evidence" / name
    receipt = parse(observations.read(directory / "receipt.json", "historical-receipt"))
    entries = receipt.get("evidence", receipt.get("artifacts"))
    if not isinstance(entries, list) or not entries or len(entries) > 128:
        raise ValueError("missing or oversized historical evidence inventory")
    seen = set()
    for item in entries:
        if not isinstance(item, dict) or type(item.get("bytes")) is not int or item["bytes"] < 0:
            raise ValueError("malformed historical evidence entry")
        filename = basename(item.get("compressed", item["name"]))
        if filename in seen:
            raise ValueError("duplicate historical archive")
        seen.add(filename)
        raw = observations.read(directory / filename, "historical-gzip", limit=32 * 1024 * 1024)
        expected = digest(item.get("compressed_sha256", item.get("archive_sha256")))
        if hashlib.sha256(raw).hexdigest() != expected:
            raise ValueError("historical compressed digest differs")
        # Incremental decompression bounds hostile expansion and verifies uncompressed bytes.
        sha = hashlib.sha256()
        size = 0
        with gzip.GzipFile(fileobj=io.BytesIO(raw)) as stream:
            while chunk := stream.read(65536):
                size += len(chunk)
                if size > 128 * 1024 * 1024:
                    raise ValueError("historical decompression bound exceeded")
                sha.update(chunk)
        if size != item["bytes"] or sha.hexdigest() != digest(item["sha256"]):
            raise ValueError("historical uncompressed identity differs")
    return {"receipt": name, "scope": receipt.get("scope"), "archive_files_authenticated": len(entries),
            "body_schema": receipt.get("body_schema"), "full_gate": receipt.get("full_gate", "not supplied"),
            "complete": False}


def evaluate_bootstrap(root, cache, expected_commit, *, zig=None):
    """Return authenticated diagnostic observations; never a full-bootstrap capability.

    Callers must bind returned paths to their request-local live snapshots. This
    function has no persistent evidence store or authority after its final check.
    """
    root, cache = Path(root).absolute(), Path(cache).absolute()
    observations = Observations()
    report = {"schema": "bootstrap-evidence-diagnostics-v1", "complete": False, "status": "partial",
              "expected_commit": expected_commit, "packages": [], "archives": [], "diagnostics": [],
              "required_owner_deliverables": list(REQUIRED)}
    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(root), *arguments], text=True).strip()
    try:
        if expected_commit != SUPPORTED_OWNER_COMMIT:
            raise ValueError("owner protocol/source contract has not been reviewed for this commit")
        if not re.fullmatch("[0-9a-f]{40}", expected_commit) or git("rev-parse", "HEAD") != expected_commit:
            raise ValueError("external source revision differs from requested frozen owner commit")
        if git("status", "--porcelain", "--untracked-files=no"):
            raise ValueError("external tracked source has uncommitted changes")
        pin_path = root / "selfhost/component-seed.json"
        pin_bytes = observations.read(pin_path, "seed-pin")
        pinned = subprocess.check_output(["git", "-C", str(root), "show", expected_commit + ":selfhost/component-seed.json"])
        if pin_bytes != pinned:
            raise ValueError("seed pin differs from frozen owner source")
        pin = parse(pin_bytes)
        if observations.read(root / ".zigversion", "source-tool-pin").decode().strip() != pin["zig"]:
            raise ValueError("source and seed Zig version pins differ")
        try:
            host_digest = observations.read(root / "zig-out/bin/mylang", "external-host-executable",
                                            limit=512 * 1024 * 1024, retain=False)
            report["host"] = {"sha256": host_digest, "source_recipe_qualification": "not established by bridge"}
        except (ValueError, OSError) as error:
            report["diagnostics"].append({"code": "host-evidence-unavailable", "reason": str(error)})
        for name in PACKAGES:
            try:
                value = package(observations, root, cache, name, pin, zig)
                report["packages"].append(value)
                if not value["schema_current"] or not value["source_current"]:
                    report["diagnostics"].append({"code": "installed-producer-stale", "component": name,
                                                  "owner": "bootstrap", "required": "rebuild and requalify exact current source/schema"})
            except (ValueError, OSError, KeyError, TypeError, EOFError, zlib.error) as error:
                report["status"] = "invalid"
                report["diagnostics"].append({"code": "component-evidence-invalid", "component": name, "reason": str(error)})
        for name in ARCHIVES:
            try:
                report["archives"].append(archives(observations, root, name))
            except (ValueError, OSError, KeyError, TypeError, EOFError, zlib.error) as error:
                report["status"] = "invalid"
                report["diagnostics"].append({"code": "archive-evidence-invalid", "receipt": name, "reason": str(error)})
        observations.recheck()
        if git("rev-parse", "HEAD") != expected_commit or git("status", "--porcelain", "--untracked-files=no"):
            raise ValueError("external owner source changed during diagnostic observation")
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        report["status"] = "invalid"
        report["diagnostics"].append({"code": "snapshot-unqualified", "reason": str(error)})
    report["inputs"] = sorted(observations.inputs.values(), key=lambda value: value["path"])
    report["bytes_read"] = observations.bytes_read
    report["byte_budget"] = observations.byte_budget
    report["authority"] = "request-local content observation only; caller must establish live stability"
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--zig", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = evaluate_bootstrap(args.root, args.cache, args.expected_commit, zig=args.zig)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    sys.exit(2 if report["status"] == "invalid" else 0)
