"""Source-origin binding and live qualification inputs; Capture stays frozen."""
import hashlib
import inspect
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile

import qualification_support as support

CAPTURE_SHA = "6f78a8ff7627b38c89aa4b5bd9e461aa1cdac214d78ab53297b3192da873f49f"
CONTROL_PRODUCER_SHA = "93c8c64a3dbec5bd562e1fbf4fde24aecd35c8c328aa16c1575a3776fa38b035"
LEGACY_SOURCE = "65036fe792ef540392d0eb00c41c9ec71c7b2c82"
LEGACY_RECEIPT_SHA = "c47616a8fa55b01c337ef9890cda337c06b4373f265315ccaf66d6a53a7802ce"
LEGACY_CHAIN = {
    "resume-context-old-full-gate-04.log": "f8316b9c01b4a1eafda033f08c4718609e095638ae8aa4ea0062519226329ec3",
    "resume-context-old-gate-validation.json": "bfb82cc8b0d7f4680f7607d678bf6a0db3b04b4da02eb4d4d835a32a76dc7185",
    "resume-context-old-install-01.log": "45644eb6ce2ec8d6224833cb0ead86bb6464ba6427b7fdf4817a936dd248124e",
}


def arguments(parser):
    parser.add_argument("--old-origin", type=Path, required=True,
                        help="Genuine immutable old compiler source/build receipt")
    parser.add_argument("--core-origin", type=Path, required=True,
                        help="Genuine immutable Core compiler source/build receipt")


def generation(value):
    return [value.st_dev, value.st_ino, value.st_mode, value.st_size,
            value.st_mtime_ns, value.st_ctime_ns]


def fingerprint(path):
    """Bind lexical alias, resolved selection, content and stable file generation."""
    path = Path(os.path.abspath(path))
    try:
        lexical = path.lstat()
    except FileNotFoundError:
        return {"path": str(path), "absent": True}
    resolved = path.resolve(strict=True)
    before = path.stat()
    if not stat.S_ISREG(before.st_mode):
        raise ValueError(f"expected regular qualification input: {path}")
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    after = path.stat()
    if (generation(before) != generation(after) or generation(lexical) != generation(path.lstat())
            or path.resolve(strict=True) != resolved):
        raise ValueError(f"qualification input changed while hashing: {path}")
    return {"path": str(path), "resolved": str(resolved), "sha256": digest,
            "generation": generation(after), "alias_generation": generation(lexical)}


def inventory(folder, extra_paths=(), generated=()):
    """Complete membership; exclusions require exact registered producer paths."""
    folder = Path(os.path.abspath(folder))
    excluded = tuple(Path(os.path.abspath(path)) for path in generated)
    values = {}

    def omitted(path):
        return any(path == root or path.is_relative_to(root) for root in excluded)

    def walk(directory):
        if directory.is_symlink():
            raise ValueError(f"directory alias needs explicit input closure: {directory}")
        info = directory.stat()
        # Generated siblings may change directory times; explicit membership below
        # guards additions without treating our own output writes as source edits.
        values[str(directory)] = {"directory": True, "resolved": str(directory.resolve(strict=True)),
            "identity": [info.st_dev, info.st_ino, info.st_mode]}
        for path in sorted(directory.iterdir()):
            if omitted(path):
                continue
            if path.is_dir():
                walk(path)
            else:
                values[str(path)] = fingerprint(path)

    walk(folder)
    for path in extra_paths:
        values[str(Path(os.path.abspath(path)))] = fingerprint(path)
    return values


class InputPhase:
    """A verified input phase changes only at an explicit harness mutation."""
    def __init__(self, folder, extra_paths=(), generated=()):
        self.folder = Path(folder)
        self.extra_paths = tuple(extra_paths)
        self.generated = tuple(generated)
        self.expected = inventory(self.folder, self.extra_paths, self.generated)

    def check(self):
        if inventory(self.folder, self.extra_paths, self.generated) != self.expected:
            raise ValueError(f"live qualification inputs changed: {self.folder}")

    def advance(self, changed):
        """Seal a deliberate mutation without accepting unrelated concurrent edits."""
        allowed = {str(Path(os.path.abspath(path))) for path in changed}
        current = inventory(self.folder, self.extra_paths, self.generated)
        if any(self.expected.get(path) != current.get(path) for path in set(self.expected) | set(current)
               if path not in allowed):
            raise ValueError("unrelated input changed during deliberate phase mutation")
        self.expected = current
        self.check()

    def record(self):
        return {"root": str(self.folder), "inputs": self.expected,
                "generated_paths": list(map(str, self.generated)),
                "extra_paths": list(map(str, self.extra_paths))}


def project_candidates(source):
    """Guard nearest-config discovery, including higher-priority absences."""
    candidates = []
    for directory in (source.parent, *source.parent.parents):
        config = directory / "mylang.json"
        candidates.append(config)
        if config.exists():
            value = json.loads(config.read_text())
            policy = value.get("import_policy")
            if policy is not None:
                if not isinstance(policy, str) or not policy:
                    raise ValueError("invalid qualification import policy path")
                candidates.append(Path(policy) if Path(policy).is_absolute() else directory / policy)
            return directory, candidates
    return source.parent, candidates


class FuzzInputs:
    """Actual input paths remain unchanged; only proved generator cleanup is allowed."""
    def __init__(self, args):
        self.args = args
        self.roots, self.sources, self.generated = {}, {}, set()
        self.owned, self.cleaning, self.cleaned = {}, set(), set()
        self.phases, self.cleanup_proofs = [], []
        self.directory = args.evidence / "input-guards"
        (self.directory / "blobs").mkdir(parents=True, exist_ok=False)
        self.save()

    def save(self):
        (self.directory / "inventory.json").write_text(json.dumps({
            "schema": "s4-fuzz-live-inputs-v1", "sources": self.sources,
            "phases": self.phases, "roots": [phase.record() for phase in self.roots.values()],
            "cleanups": self.cleanup_proofs}, indent=2) + "\n")

    def declare_generated(self, path, source):
        path = Path(os.path.abspath(path))
        if source == path or source.is_relative_to(path):
            raise ValueError("generated path overlaps a qualification source")
        if path not in self.generated:
            if path.exists() and (not path.is_dir() or any(path.iterdir())):
                raise ValueError("unproved existing output/cache cannot be excluded")
            self.generated.add(path)

    def retain(self, phase, source):
        copies = {}
        for path, item in phase.expected.items():
            if "sha256" not in item:
                continue
            target = self.directory / "blobs" / item["sha256"]
            if not target.exists():
                target.write_bytes(Path(path).read_bytes())
            if support.identity(target)["sha256"] != item["sha256"]:
                raise ValueError("live input changed during retention")
            copies[path] = support.identity(target)
        phase.check()
        self.phases.append({"source": str(source), **phase.record(), "retained": copies})
        self.save()

    def check_sources(self):
        for path, expected in self.sources.items():
            source = Path(path)
            if any(source.is_relative_to(root) for root in self.cleaned):
                if source.exists():
                    raise ValueError("cleaned generator input unexpectedly reappeared")
                continue
            if fingerprint(source) != expected:
                raise ValueError("fuzz source changed across compiler modes: " + path)

    def before(self, argv):
        building = len(argv) > 2 and argv[1] == "build"
        if not building:
            self.check()
            return
        source = Path(os.path.abspath(argv[2]))
        output = argv[argv.index("-o") + 1]
        self.declare_generated(output, source)
        cache = (argv[argv.index("--cache-dir") + 1] if "--cache-dir" in argv else
                 self.args.cache_root / ("frontend-old" if Path(argv[0]).resolve() == self.args.old else "frontend-core"))
        self.declare_generated(cache, source)
        root, extra = project_candidates(source)
        if root != source.parent and not any(root == owned or root.is_relative_to(owned) for owned in self.owned):
            raise ValueError("fuzz project discovers an unowned enclosing input tree")
        if str(source) not in self.sources:
            if Path(argv[0]).resolve() != self.args.old:
                raise ValueError("new case must first be built by the old oracle")
            self.check_sources()
            prior = self.roots.get(root)
            if prior is not None:
                # A generator creates exactly this next case source between fully
                # verified phases. Any other edit/member addition fails here.
                if inventory(root, prior.extra_paths, (*self.generated, source)) != prior.expected:
                    raise ValueError("inputs changed before declaring the next fuzz case")
            self.sources[str(source)] = fingerprint(source)
            phase = InputPhase(root, extra, self.generated)
            self.roots[root] = phase
            self.retain(phase, source)
        else:
            self.check()

    def check(self):
        self.check_sources()
        for root, phase in self.roots.items():
            if root in self.cleaned:
                if root.exists():
                    raise ValueError("cleaned input root unexpectedly reappeared")
                continue
            phase.generated = tuple(self.generated)
            phase.check()

    def created(self, root, producer):
        root = Path(root).absolute()
        if root in self.owned:
            raise ValueError("temporary input root was registered twice")
        self.owned[root] = producer

    def before_cleanup(self, root, producer):
        root = Path(root).absolute()
        if root not in self.owned:
            raise ValueError("input cleanup has no task-owned creation proof")
        self.check()
        affected = [str(path) for path in self.sources if Path(path).is_relative_to(root)]
        proof = {"root": str(root), "created_by": self.owned[root], "cleanup_by": producer,
                 "sources": affected, "inputs_verified_before_cleanup": True,
                 "cleanup_complete": False}
        self.cleanup_proofs.append(proof)
        self.cleaning.add(root)
        self.save()
        return proof

    def after_cleanup(self, root, proof):
        root = Path(root).absolute()
        self.cleaning.remove(root)
        if root.exists():
            raise ValueError("intentional generator cleanup did not remove its owned root")
        # Config/policy paths outside the cleaned tree still need a final guard.
        for phase_root, phase in self.roots.items():
            if phase_root == root or phase_root.is_relative_to(root):
                self.cleaned.add(phase_root)
                for path in phase.extra_paths:
                    if not Path(path).is_relative_to(root) and fingerprint(path) != phase.expected[str(Path(os.path.abspath(path)))]:
                        raise ValueError("external project input changed at cleanup")
        self.cleaned.add(root)
        proof["cleanup_complete"] = True
        self.save()

    def finish(self):
        if self.cleaning:
            raise ValueError("generator cleanup is incomplete")
        self.check()
        # Removed roots have a checked intentional cleanup proof. Their external
        # config/policy dependencies remain live through the final aggregate.
        for root, phase in self.roots.items():
            if root in self.cleaned:
                for path in phase.extra_paths:
                    if not any(Path(path).is_relative_to(removed) for removed in self.cleaned):
                        if fingerprint(path) != phase.expected[str(Path(os.path.abspath(path)))]:
                            raise ValueError("external project input changed after cleanup")
        self.save()


class GeneratorCleanup:
    """Scope hooks to reviewed generator call sites and registered owned roots."""
    def __init__(self, inputs, producers):
        self.inputs = inputs
        self.producers = {str(Path(path).resolve()) for path in producers}

    def approved(self, frame):
        return str(Path(frame.f_code.co_filename).resolve()) in self.producers

    def __enter__(self):
        self.old_mkdtemp, self.old_rmtree, self.old_temporary = tempfile.mkdtemp, shutil.rmtree, tempfile.TemporaryDirectory
        owner = self

        def made(*args, **kwargs):
            result = owner.old_mkdtemp(*args, **kwargs)
            caller = inspect.currentframe().f_back
            if owner.approved(caller):
                owner.inputs.created(result, {"path": caller.f_code.co_filename, "line": caller.f_lineno,
                                               "operation": "mkdtemp"})
            return result

        def removed(path, *args, **kwargs):
            root = Path(path).absolute()
            if root in owner.inputs.cleaning:
                return owner.old_rmtree(path, *args, **kwargs)
            affected = any(root == known or known.is_relative_to(root) or root.is_relative_to(known)
                           for known in owner.inputs.roots)
            caller = inspect.currentframe().f_back
            if root in owner.inputs.owned and owner.approved(caller):
                proof = owner.inputs.before_cleanup(root, {"path": caller.f_code.co_filename,
                    "line": caller.f_lineno, "operation": "rmtree"})
                result = owner.old_rmtree(path, *args, **kwargs)
                owner.inputs.after_cleanup(root, proof)
                return result
            if affected:
                raise ValueError("unproved generator input removal")
            return owner.old_rmtree(path, *args, **kwargs)

        class Temporary(owner.old_temporary):
            def __init__(self, *args, **kwargs):
                caller = inspect.currentframe().f_back
                self.guard_owned = owner.approved(caller)
                super().__init__(*args, **kwargs)
                if self.guard_owned:
                    owner.inputs.created(self.name, {"path": caller.f_code.co_filename,
                        "line": caller.f_lineno, "operation": "TemporaryDirectory"})

            def cleanup(self):
                if not self.guard_owned:
                    return super().cleanup()
                if Path(self.name).absolute() in owner.inputs.cleaned:
                    return super().cleanup()
                proof = owner.inputs.before_cleanup(self.name, {"operation": "TemporaryDirectory.cleanup"})
                super().cleanup()
                owner.inputs.after_cleanup(self.name, proof)

            @classmethod
            def _cleanup(cls, name, warn_message, ignore_errors=False, delete=True):
                root = Path(name).absolute()
                if not delete or root not in owner.inputs.owned or root in owner.inputs.cleaned:
                    return super()._cleanup(name, warn_message, ignore_errors, delete)
                proof = owner.inputs.before_cleanup(root, {"operation": "TemporaryDirectory.finalizer"})
                super()._cleanup(name, warn_message, ignore_errors, delete)
                owner.inputs.after_cleanup(root, proof)

        tempfile.mkdtemp, shutil.rmtree, tempfile.TemporaryDirectory = made, removed, Temporary
        return self

    def __exit__(self, *failure):
        tempfile.mkdtemp, shutil.rmtree, tempfile.TemporaryDirectory = self.old_mkdtemp, self.old_rmtree, self.old_temporary


def fuzz_unchanged(summary):
    """Recheck completed workers again at the matrix's final aggregate boundary."""
    record = checked_identity(summary["input_inventory"])
    value = json.loads(Path(record["path"]).read_text())
    if value.get("schema") != "s4-fuzz-live-inputs-v1" or value.get("cleanups") != summary.get("intentional_cleanups"):
        raise ValueError("worker input/cleanup receipt differs")
    removed = []
    for proof in value["cleanups"]:
        if proof.get("cleanup_complete") is not True or proof.get("inputs_verified_before_cleanup") is not True:
            raise ValueError("unproved incomplete worker input cleanup")
        removed.append(Path(proof["root"]))
    for path, expected in value["sources"].items():
        source = Path(path)
        if any(source.is_relative_to(root) for root in removed):
            if source.exists():
                raise ValueError("cleaned worker input unexpectedly reappeared")
        elif fingerprint(source) != expected:
            raise ValueError("completed worker input changed before final aggregate")
    for phase in value["roots"]:
        root = Path(phase["root"])
        if any(root == cleaned or root.is_relative_to(cleaned) for cleaned in removed):
            if root.exists():
                raise ValueError("completed worker cleanup root reappeared")
            for path in phase["extra_paths"]:
                if not any(Path(path).is_relative_to(cleaned) for cleaned in removed):
                    if fingerprint(path) != phase["inputs"][str(Path(os.path.abspath(path)))]:
                        raise ValueError("completed worker external input changed")
        elif inventory(root, phase["extra_paths"], phase["generated_paths"]) != phase["inputs"]:
            raise ValueError("completed worker input membership changed before final aggregate")
    return True


def scope(cases, final=False):
    if final:
        if cases != 200:
            raise ValueError("final fuzz requires 200 cases per kind")
        return "final"
    return "package" if cases == 50 else "diagnostic"


def bind_compilers(tool, receipt):
    """Execute the recorded canonical files, independently of supplied aliases."""
    tool.mylang = receipt["oracles"]["old"]["path"]
    tool.core = receipt["oracles"]["core"]["path"]


def bind_scope(receipt, selected_scope):
    if selected_scope not in ("diagnostic", "package", "final"):
        raise ValueError("invalid qualification scope")
    if selected_scope != "diagnostic" and receipt["core_source_diff"]:
        raise ValueError("Core origin differs from the active package compiler source")
    receipt["scope"] = selected_scope


def checked_identity(item):
    if not isinstance(item, dict) or set(item) != {"path", "sha256"}:
        raise ValueError("invalid origin artifact identity")
    if support.identity(item["path"]) != item:
        raise ValueError("origin artifact bytes changed: " + str(item["path"]))
    return item


def tree_files(root, commit, paths=()):
    text = support.git(root, "ls-tree", "-r", "-z", commit, "--", *paths)
    result = {}
    for entry in text.split("\0"):
        if not entry:
            continue
        info, name = entry.split("\t", 1)
        mode, kind, oid = info.split()
        if kind != "blob" or mode not in ("100644", "100755"):
            if not name.startswith("experiments/"):
                raise ValueError("origin tree has an unsupported file type")
            continue
        result[name] = oid
    return result


def blob_digests(root, objects):
    ordered = sorted(set(objects))
    data = subprocess.check_output(["git", "cat-file", "--batch"], cwd=root,
                                   input=("\n".join(ordered) + "\n").encode())
    cursor, result = 0, {}
    for oid in ordered:
        end = data.index(b"\n", cursor)
        actual, kind, size = data[cursor:end].decode().split()
        if actual != oid or kind != "blob":
            raise ValueError("invalid source tree blob")
        cursor = end + 1
        size = int(size)
        result[oid] = hashlib.sha256(data[cursor:cursor + size]).hexdigest()
        cursor += size + 1
    if cursor != len(data):
        raise ValueError("extra origin source blob output")
    return result


def source_tree(root, source, build_source, source_files, inputs):
    if support.git(root, "diff", "--name-only", source, build_source, "--", "src", "build.zig", "build.zig.zon"):
        raise ValueError("build compiler source differs from asserted production source")
    expected = tree_files(root, source, ("src", "build.zig", "build.zig.zon"))
    recorded = {}
    for item in source_files:
        name = str(Path(item["path"]).relative_to(root))
        if name in recorded or set(item) != {"path", "sha256"}:
            raise ValueError("duplicate or invalid origin source file")
        recorded[name] = item["sha256"]
    if set(recorded) != set(expected):
        raise ValueError("origin compiler source inventory is incomplete")
    tracked = {name: oid for name, oid in tree_files(root, build_source).items()
               if not name.startswith("experiments/")}
    digests = blob_digests(root, [*expected.values(), *tracked.values()])
    if any(recorded[name] != digests[oid] for name, oid in expected.items()):
        raise ValueError("origin source bytes disagree with production source tree")
    if any(str(root / name) not in inputs or inputs[str(root / name)]["sha256"] != digests[oid]
           for name, oid in tracked.items()):
        raise ValueError("origin consumed repository input inventory is incomplete or mislabeled")


def captured_process(value, compiler, chain):
    process = checked_identity(value["process"])
    chain.append(process)
    record = json.loads(Path(process["path"]).read_text())
    finished = record.get("supervisor_result", {})
    if (type(record.get("status")) is not int or record["status"] != 0
            or record.get("timed_out") is not False or type(record.get("supervisor_status")) is not int
            or record["supervisor_status"] != 0 or type(finished.get("status")) is not int
            or finished["status"] != 0 or finished.get("timed_out") is not False
            or finished.get("error") is not None or finished.get("remaining_children") != []):
        raise ValueError("origin lacks a successful completed Capture build")
    for field in ("stdout", "stderr"):
        chain.append(checked_identity(record[field]))
    stem = Path(process["path"]).with_suffix("")
    for suffix in (".job.json", ".result.json", ".supervisor.stdout", ".supervisor.stderr"):
        chain.append(support.identity(str(stem) + suffix))
    job = json.loads(Path(str(stem) + ".job.json").read_text())
    raw_result = json.loads(Path(str(stem) + ".result.json").read_text())
    if (raw_result != finished or job.get("argv") != record.get("argv")
            or job.get("options", {}).get("cwd") != record.get("cwd")
            or job.get("timeout") != record.get("timeout") or job.get("input") is not False
            or job.get("merged_stderr") is not False
            or record.get("supervisor", [])[1:] != [value["helpers"]["capture"]["path"], "--supervise", str(stem) + ".job.json"]):
        raise ValueError("origin raw Capture job/result contradict the process receipt")
    argv = record["argv"]
    root, zig = value["root"], value["zig"]["path"]
    if (not isinstance(argv, list) or len(argv) != 9
            or argv[:5] != [str(Path(root) / "scripts/build-slot.sh"), "build", zig, "build", "core"]
            or argv[5] != "--prefix" or argv[7] != "--cache-dir" or record["cwd"] != root):
        raise ValueError("origin build argv/cwd does not identify the recorded Core action")
    prefix = Path(argv[argv.index("--prefix") + 1])
    if (compiler["path"] != str(prefix / "bin/mylang-core")
            or argv[argv.index("--cache-dir") + 1] != str(prefix / "zig-local")
            or record.get("environment", {}).get("ZIG_GLOBAL_CACHE_DIR") != str(prefix / "zig-global")):
        raise ValueError("origin build does not bind fresh native caches and its output")


def control_origin(root, value, role):
    if (type(value.get("schema")) is not int or value["schema"] != 1
            or value.get("kind") != "control-compiler-origin" or role != "core"
            or value.get("qualified") is not True or value.get("complete") is not True
            or value.get("error") is not None or value.get("compiler_source_diff") != []):
        raise ValueError("unsupported or incomplete genuine build-origin receipt")
    compiler = value["compiler"]
    if not isinstance(compiler, dict) or set(compiler) != {"path", "sha256"}:
        raise ValueError("invalid origin compiler identity")
    source = support.git(root, "rev-parse", "--verify", value["source_commit"] + "^{commit}")
    build_source = support.git(root, "rev-parse", "--verify", value["build_source_commit"] + "^{commit}")
    if value.get("core_source_commit") != source:
        raise ValueError("origin production source fields disagree")
    origin_root = Path(value["root"])
    if not origin_root.is_absolute():
        raise ValueError("origin build root must be absolute")
    before, after = value["inputs_before"], value["inputs_after"]
    if not isinstance(before, list) or not before or before != after:
        raise ValueError("origin input generations changed or are missing")
    inputs = {}
    for item in before:
        if (not isinstance(item, dict) or set(item) != {"path", "sha256", "stat"}
                or not Path(item["path"]).is_absolute() or item["path"] in inputs
                or not isinstance(item["stat"], list) or len(item["stat"]) != 6
                or any(type(number) is not int for number in item["stat"])
                or item["stat"][2] < 0 or not stat.S_ISREG(item["stat"][3])
                or not isinstance(item["sha256"], str) or len(item["sha256"]) != 64
                or any(letter not in "0123456789abcdef" for letter in item["sha256"])):
            raise ValueError("invalid or duplicate consumed origin input")
        inputs[item["path"]] = item
    source_tree(origin_root, source, build_source, value["source_files"], inputs)
    helpers = value["helpers"]
    if helpers["capture"]["sha256"] != CAPTURE_SHA or helpers["origin"]["sha256"] != CONTROL_PRODUCER_SHA:
        raise ValueError("origin build producer/Capture was not reviewed")
    chain = [checked_identity(helpers["capture"]), checked_identity(helpers["origin"])]
    if any(item["path"] not in inputs or inputs[item["path"]]["sha256"] != item["sha256"]
           for item in [*chain, value["zig"]]):
        raise ValueError("origin lacks producer/tool input binding")
    captured_process(value, compiler, chain)
    return source, build_source, compiler["sha256"], chain


def legacy_origin(path, value, role):
    if (role != "old" or support.identity(path)["sha256"] != LEGACY_RECEIPT_SHA
            or value.get("source_commit") != LEGACY_SOURCE or value.get("qualified") is not True):
        raise ValueError("unreviewed legacy source-origin receipt")
    chain = []
    for name, digest in LEGACY_CHAIN.items():
        item = support.identity(path.parent / name)
        if item["sha256"] != digest:
            raise ValueError("legacy origin build/gate evidence differs")
        chain.append(item)
    artifact = next(item for item in value["files"] if item["name"] == "mylang")
    # Legacy evidence never claimed a separate build/evidence HEAD or Capture job.
    return LEGACY_SOURCE, None, artifact["sha256"], chain


def origin(root, path, artifact, assertion, role):
    path = Path(path).resolve(strict=True)
    receipt = support.identity(path)
    value = json.loads(path.read_text())
    try:
        if receipt["sha256"] == LEGACY_RECEIPT_SHA:
            source, build_source, digest, chain = legacy_origin(path, value, role)
            codec = "reviewed-s3-c-legacy-v1"
        else:
            source, build_source, digest, chain = control_origin(root, value, role)
            codec = "reviewed-control-compiler-origin-v1"
    except (KeyError, TypeError, AttributeError, StopIteration) as failure:
        raise ValueError("invalid or incomplete compiler source-origin schema") from failure
    if support.git(root, "rev-parse", "--verify", assertion + "^{commit}") != source:
        raise ValueError(f"{role} asserted source differs from genuine artifact origin")
    if support.identity(artifact, True)["sha256"] != digest:
        raise ValueError(f"{role} compiler bytes differ from genuine artifact origin")
    return {"codec": codec, "receipt": receipt, "chain": chain,
            "production_source_commit": source, "build_source_commit": build_source,
            "artifact_sha256": digest}


def manifest(root, old, core, args, sources, extra_tools=()):
    origins = {role: origin(root, getattr(args, role + "_origin"), artifact,
                           getattr(args, role + "_source"), role)
               for role, artifact in (("old", old), ("core", core))}
    receipts = [item for value in origins.values() for item in [value["receipt"], *value["chain"]]]
    value = support.manifest(root, old, core, args, [*sources, *(item["path"] for item in receipts)], extra_tools)
    difference = support.git(root, "diff", "--name-only", origins["core"]["production_source_commit"],
                             value["source_commit"], "--", "src", "build.zig", "build.zig.zon").splitlines()
    return {**value, "schema": "s4-qualification-v2", "compiler_origins": origins,
            "qualification_head": value["source_commit"], "core_source_diff": difference}


def unchanged(root, receipt):
    if receipt.get("schema") != "s4-qualification-v2" or receipt.get("qualification_head") != receipt.get("source_commit"):
        return False
    if not support.unchanged(root, receipt):
        return False
    try:
        return all(support.identity(item["path"]) == item
                   for value in receipt["compiler_origins"].values() for item in [value["receipt"], *value["chain"]])
    except (OSError, ValueError, KeyError):
        return False
