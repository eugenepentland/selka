#!/usr/bin/env python3
"""The gate action `ownership-proof` (docs/audits/ownership-certificates-plan-2026-10-26.md, package C4).

    python3 scripts/ownership_proof.py --compiler zig-out/bin/selka [--certificates DIR] [--store DIR] [--jobs N]

It does three things (and then the facts half below) and fails, never skips, when any of them cannot be done:

1. **The proof check.** `lake build` in `proofs/ownership` (incremental: it rebuilds only what a change under
   `proofs/` touched), and `lake exe selftest`. A `sorry` or any error fails it.
2. **The differential.** Every function of every ownership certificate the language gate wrote
   (`selka test SUITE --emit-certificates DIR`, one directory per suite and mode) is checked by the Zig validator
   (`selka validate-certificates`) and by the Lean checker (`certcheck`). The two must give the same verdict per
   function: `accept`, or `reject` with the same judgment, block and instruction, or `unchecked` with the same reason.
3. **The link.** The callee tables (design §9, entry 57) of each program are linked to the callees' own `function` lines by name
   (`selka link-certificates` and `certcheck --link` over the certificate root); the two must print the same lines, and any
   line is a failure. The link spans the functions of a program, so no per-function verdict can hold it: it runs each time.
4. **The mutants.** Fixed programs in `test/fixtures/ownership-proof/` are lowered, their certificates mutated
   (`selka mutate-certificates`, the fault-injection classes of `src/core/ownership_mutants.zig`), and both checkers must
   reject every mutant.

Then the facts half (`scripts/fact_proof.py`, plan C7.4): the fact certificates the language gate's runs wrote are checked by
`selka validate-fact-certificates` and by the Lean checker of `proofs/facts` (`lake build` there, then `factcheck`), which must
print the same line for every function, and the mutants of `test/fixtures/fact-proof/` must all be rejected, by both.

Lean is a developer and gate tool only. `lake` is found through `SELKA_LAKE` or `$HOME/.elan/bin/lake`.

**The size cap.** Off by default since the fast Lean checker (C3.7, 26 October): the largest corpus function takes 0.04 s.
`--lean-cap-bytes N` skips a function above N bytes of certificate text that the checker has no verdict for and says how many
it skipped; the Zig validator checks them all. The cap never applies when a checker changed, nor in the `proofs` profile
(`verify_cache.py --profile proofs`).

**The runs.** The gate checks the debug runs' certificates (`--verify-facts` builds). Release builds are not part of the gate;
`--with-release-certificates` (set by `-Dtest-release=true`) adds the release runs' directories and regenerates them, and without
it a release directory an earlier release run left is removed (`scripts/ownership_corpus.py`, `retire`), so it is never checked.

**The certificates.** `selka test` writes a program's certificates only when it builds the program, and a test served from
a receipt builds nothing, so each certificate directory carries a stamp (`scripts/ownership_corpus.py`): the compiler's
identity and a digest of the suite's inputs. `scripts/test_lang.py` writes it after a complete run, and empties and rebuilds
(`--force`) a directory whose stamp is not the current one. Before it reads the directories this driver checks the stamps
again and regenerates a stale directory the same way.

**The verdicts** are kept per function in the per-user shared verification store (`scripts/ownership_verdict_store.py`), keyed
by the digest of the function's certificate text and the digest of the checker: a Zig verdict under the digest of the
validator's sources, a Lean verdict under the digest of `proofs/ownership`. Every worktree and session of the user shares them.
A run checks only the functions it has no verdict for, so after a compiler edit only programs whose final IR changed are
checked again, and `lake build` reruns only when `proofs/` changed. Known disagreements are listed with reasons in
`tests/ownership-proof-known.json`; none is allowed otherwise.

Python is allowed in gate drivers: nothing here is part of the install graph or of `src/`.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import ownership_corpus as corpus  # noqa: E402  (the stamps on the certificate directories)
import ownership_verdict_store as verdicts  # noqa: E402  (the per-user store of verdicts)
import fact_proof  # noqa: E402  (the facts half: fact certificates and their mutants, plan C7.4)

PROOFS = ROOT / "proofs" / "ownership"
KNOWN = ROOT / "tests" / "ownership-proof-known.json"
FIXTURES = ROOT / "test" / "fixtures" / "ownership-proof"
FIXTURE_SOURCE = ROOT / "src" / "core" / "validate_ownership_test.zig"
FIXTURE = re.compile(r'\.\{ \.name = "([^"]+)",(?: \.reject = \.(j\d),)? \.text =\n((?:\s*\\\\[^\n]*\n)+)')
MIN_FIXTURES = 40
VALIDATOR_SOURCES = (
    "src/core/validate_ownership.zig", "src/core/ownership_parse.zig", "src/core/ownership_function.zig",
    "src/core/ownership_ops.zig", "src/core/ownership_certificate.zig", "src/core/ownership_commands.zig",
    "src/core/ownership_mutants.zig", "src/core/ir.zig", "src/core/flags.zig",
)
MUTANT_CLASSES = 12
STORE_VERSION = 1
LEAN_CAP_BYTES = 0
BATCH_BYTES = 64_000


class ProofError(RuntimeError):
    """The action cannot certify: a tool is missing, a check failed or the two checkers disagree."""


# ---- tools -----------------------------------------------------------------------------------------------------------

def find_lake(env=None) -> str:
    """The `lake` executable: `SELKA_LAKE`, else `$HOME/.elan/bin/lake`. A missing Lean fails the action."""
    env = os.environ if env is None else env
    chosen = env.get("SELKA_LAKE") or os.path.join(env.get("HOME", ""), ".elan", "bin", "lake")
    if os.path.isfile(chosen) and os.access(chosen, os.X_OK):
        return chosen
    raise ProofError(
        f"ownership-proof: the Lean build tool `lake` is missing ({chosen}). Install elan with the toolchain pinned in "
        "proofs/ownership/lean-toolchain (see proofs/ownership/README.md) or point SELKA_LAKE at lake. "
        "The complete gate needs Lean for this action and never skips it.")


def tool_env(lake: str) -> dict:
    """The environment for `lake`: its directory first on `PATH`, so the elan shim finds its siblings."""
    env = dict(os.environ)
    env["PATH"] = os.path.dirname(lake) + os.pathsep + env.get("PATH", "")
    return env


def run_lake(lake: str, arguments: list[str], run=subprocess.run) -> subprocess.CompletedProcess:
    return run([lake, *arguments], cwd=PROOFS, env=tool_env(lake), capture_output=True, text=True, errors="replace")


def lake_build(lake: str, run=subprocess.run) -> None:
    """`lake build` and `lake exe selftest`; a failure, an `error`, or a `sorry` fails the action."""
    built = run_lake(lake, ["build"], run)
    text = built.stdout + built.stderr
    if built.returncode != 0 or "sorry" in text or "error:" in text:
        tail = "\n".join(text.splitlines()[-40:])
        raise ProofError(f"ownership-proof: `lake build` in proofs/ownership failed (exit {built.returncode}):\n{tail}")
    selftest = run_lake(lake, ["exe", "selftest"], run)
    if selftest.returncode != 0:
        raise ProofError("ownership-proof: `lake exe selftest` failed:\n" + (selftest.stdout + selftest.stderr)[-2000:])


def certcheck_binary(lake: str) -> list[str]:
    """The command that runs the built checker: its binary when it exists, else `lake exe certcheck`."""
    binary = PROOFS / ".lake" / "build" / "bin" / "certcheck"
    return [str(binary)] if binary.is_file() else [lake, "exe", "certcheck"]


# ---- identities ------------------------------------------------------------------------------------------------------

def digest_files(paths: list[Path], root: Path) -> str:
    hash = hashlib.sha256()
    for path in sorted(paths):
        hash.update(str(path.relative_to(root)).encode() + b"\0")
        hash.update(path.read_bytes())
        hash.update(b"\0")
    return hash.hexdigest()


def lean_identity(lake: str, run=subprocess.run) -> str:
    """Digest of the Lean project: its sources, manifest, toolchain pin and the reported toolchain version."""
    files = [p for p in PROOFS.iterdir() if p.is_file() and (p.suffix == ".lean" or p.name in ("lean-toolchain", "lakefile.toml", "lake-manifest.json"))]
    version = run_lake(lake, ["--version"], run).stdout.strip()
    return hashlib.sha256((digest_files(files, PROOFS) + "\0" + version).encode()).hexdigest()


def zig_identity() -> str:
    """Digest of the sources the Zig verdict depends on: the validator, the reader and the line format."""
    return digest_files([ROOT / name for name in VALIDATOR_SOURCES], ROOT)


# ---- certificate text ------------------------------------------------------------------------------------------------

def functions_of(text: str) -> list[tuple[str, str]]:
    """The (name, block) of each function of a certificate file; a block runs from its `function` line to its `end`."""
    found, current, name = [], None, ""
    for line in text.splitlines():
        if current is None:
            if line.startswith("function "):
                current, name = [line], line.split(" ", 2)[1]
        else:
            current.append(line)
            if line == "end":
                found.append((name, "\n".join(current) + "\n"))
                current = None
    return found


def header_of(text: str) -> str:
    """The version line and the operation-class table that open a certificate file."""
    lines = []
    for line in text.splitlines():
        if line.startswith("function "):
            break
        lines.append(line)
    return "\n".join(lines) + "\n"


def block_digest(block: str) -> str:
    return hashlib.sha256(block.encode()).hexdigest()


# ---- the verdict store -----------------------------------------------------------------------------------------------

class Store:
    """The corpus the certificate directory holds now (file to function digests, and the text of each function) and the verdicts
    of each checker, which live in the per-user shared store (`ownership_verdict_store.py`): a verdict is read by the digest of
    the function's certificate and the digest of the checker, whichever worktree computed it."""

    def __init__(self, directory: Path, zig_id: str, lean_id: str):
        self.shared = verdicts.VerdictStore(directory)
        self.zig_id, self.lean_id = zig_id, lean_id
        self.corpus: dict[str, list] = {}
        self.blocks: dict[str, str] = {}
        self.header = ""
        # A checker no run has completed with yet (a changed validator or proof, or a store that never saw this one) is one
        # whose verdicts are not all here: the size cap does not apply.
        self.zig_fresh = not self.shared.established("zig", zig_id)
        self.lean_fresh = not self.shared.established("lean", lean_id)
        self.zig: dict[str, str] = {}
        self.lean: dict[str, str] = {}
        self.computed: dict[str, set] = {"zig": set(), "lean": set()}

    def load_verdicts(self) -> None:
        """Fetch the stored verdicts of the functions in the corpus."""
        wanted = {digest for entries in self.corpus.values() for digest, _ in entries}
        self.zig.update(self.shared.get_many("zig", self.zig_id, wanted - set(self.zig)))
        self.lean.update(self.shared.get_many("lean", self.lean_id, wanted - set(self.lean)))

    def record(self, tool: str, digest: str, verdict: str) -> None:
        (self.zig if tool == "zig" else self.lean)[digest] = verdict
        self.computed[tool].add(digest)

    def remember(self, digest: str, block: str) -> None:
        self.blocks[digest] = block

    def block(self, digest: str) -> str:
        return self.blocks[digest]

    def mutant_summary(self, key: str) -> dict | None:
        found = self.shared.get_many("mutants", "all", [key]).get(key)
        try:
            return json.loads(found) if found else None
        except ValueError:
            return None

    def keep_mutant_summary(self, key: str, summary: dict) -> None:
        self.shared.put_many("mutants", "all", {key: json.dumps(summary, sort_keys=True, separators=(",", ":"))})

    def save(self) -> None:
        """Publish the verdicts this run computed, and mark both checkers as having completed a run."""
        for tool, checker in (("zig", self.zig_id), ("lean", self.lean_id)):
            table = self.zig if tool == "zig" else self.lean
            self.shared.put_many(tool, checker, {d: table[d] for d in self.computed[tool]})
            self.shared.establish(tool, checker)
        self.computed = {"zig": set(), "lean": set()}


def store_directory(requested: Path | None, certificates: Path) -> Path:
    """Where the verdicts live: `--store`, else the verification coordinator's shared root (made a versioned store first, as the
    coordinator would), else, when sharing is off or unusable, a directory in the worktree."""
    if requested is not None:
        return requested
    root = verdicts.shared_root()
    if root is not None:
        try:
            verdicts.initialize_host(root)
            return root
        except Exception as error:  # an unusable default store never stops the gate; it only stops the sharing
            print(f"ownership-proof: note: the shared verification store {root} is unusable ({str(error)[:120]}); keeping the verdicts in the worktree", file=sys.stderr)
    return ROOT / ".selka-cache" / "ownership-proof"


def collect(root: Path, store: Store) -> tuple[int, int]:
    """Read every certificate file under `root` as the store's corpus; a file the directory no longer holds is not in it.
    Returns (files, functions) seen."""
    store.corpus.clear()
    files = functions = 0
    for path in sorted(root.rglob("*.certificate")):
        text = path.read_text(errors="replace")
        key = str(path.relative_to(root))
        blocks = functions_of(text)
        if not blocks:
            continue
        store.header = header_of(text)
        entries = []
        for name, block in blocks:
            digest = block_digest(block)
            store.remember(digest, block)
            entries.append([digest, name])
        store.corpus[key] = entries
        files += 1
        functions += len(entries)
    store.load_verdicts()
    return files, functions


# ---- running the checkers --------------------------------------------------------------------------------------------

def available_cpus() -> int:
    """The CPUs this process may use: the admission slot narrows the affinity, so this follows it."""
    try:
        return len(os.sched_getaffinity(0))
    except AttributeError:
        return os.cpu_count() or 1


def default_jobs() -> int:
    return max(1, min(16, available_cpus() - 1))


def batches_of(digests: list[str], sizes: dict[str, int], target: int = BATCH_BYTES) -> list[list[str]]:
    """Group `digests` into batches of about `target` bytes, largest first, so that a pool fed in this order keeps every
    worker busy to the end. A function above half the target is a batch of its own and starts first: the Lean checker takes
    minutes on a large function, and two of them in one batch would run one after the other."""
    batches: list[list[str]] = []
    current: list[str] = []
    load = 0
    for digest in sorted(digests, key=lambda d: (-sizes[d], d)):
        if current and (load + sizes[digest] > target or sizes[digest] > target // 2 or sizes[current[0]] > target // 2):
            batches.append(current)
            current, load = [], 0
        current.append(digest)
        load += sizes[digest]
    if current:
        batches.append(current)
    return batches


def parse_verdicts(output: str, directory: Path, expected: list[tuple[str, str]], tool: str) -> list[str]:
    """The verdict of each function of a batch file, in order. `expected` is the (digest, name) of each function."""
    lines = [line for line in output.splitlines() if line and not line.startswith("summary ")]
    errors = [line for line in lines if line.split(" ", 2)[1:2] == ["error"]]
    if errors:
        raise ProofError(f"ownership-proof: {tool} could not read a batch file: " + "; ".join(errors)[:400])
    verdicts: list[str] = []
    if len(lines) != len(expected):
        raise ProofError(f"ownership-proof: {tool} printed {len(lines)} verdicts for {len(expected)} functions")
    for line, (digest, name) in zip(lines, expected):
        parts = line.split(" ", 2)
        if len(parts) < 3 or parts[1] != name:
            raise ProofError(f"ownership-proof: {tool} answered for {parts[1] if len(parts) > 1 else '?'} where {name} was asked: {line[:200]}")
        verdicts.append(parts[2].strip())
    return verdicts


def run_checker(command: list[str], batch: Path, tool: str, env=None, run=subprocess.run) -> str:
    done = run(command + [str(batch)], capture_output=True, text=True, errors="replace", env=env)
    if done.returncode not in (0, 1):
        raise ProofError(f"ownership-proof: {tool} failed on {batch.name} (exit {done.returncode}): {(done.stdout + done.stderr)[-1500:]}")
    return done.stdout


def check_batches(store: Store, missing: dict[str, list[str]], commands: dict[str, list[str]], jobs: int, scratch: Path, envs: dict) -> None:
    """Run each checker over the functions it has no verdict for; fill the store's verdict tables."""
    for tool, digests in missing.items():
        if not digests:
            continue
        sizes = {d: len(store.block(d)) for d in digests}
        batches = batches_of(digests, sizes)
        directory = scratch / tool
        directory.mkdir(parents=True, exist_ok=True)
        names = {}
        for d in digests:
            names[d] = store.block(d).split("\n", 1)[0].split(" ", 2)[1]
        work = []
        for index, group in enumerate(batches):
            batch = directory / f"batch{index}.certificate"
            batch.write_text(store.header + "".join(store.block(d) for d in group))
            work.append((batch, group))
        pool = concurrent.futures.ThreadPoolExecutor(max_workers=max(1, jobs))
        try:
            futures = [(group, pool.submit(run_checker, commands[tool], batch, tool, envs.get(tool))) for batch, group in work]
            for group, future in futures:
                verdicts = parse_verdicts(future.result(), directory, [(d, names[d]) for d in group], tool)
                for digest, verdict in zip(group, verdicts):
                    store.record(tool, digest, verdict)
        finally:
            pool.shutdown(wait=True, cancel_futures=True)


# ---- the differential ------------------------------------------------------------------------------------------------

def load_known(path: Path = KNOWN) -> dict[str, str]:
    """Exact known disagreements: digest to reason. No wildcards."""
    if not path.is_file():
        return {}
    value = json.loads(path.read_text())
    if not isinstance(value, dict) or set(value) != {"version", "disagreements"} or value["version"] != 1:
        raise ProofError(f"{path}: expected an object with version 1 and disagreements")
    known = {}
    for entry in value["disagreements"]:
        if not isinstance(entry, dict) or set(entry) != {"digest", "function", "reason"} or not str(entry["reason"]).strip():
            raise ProofError(f"{path}: each entry needs digest, function and a nonempty reason")
        known[entry["digest"]] = entry["reason"]
    return known


def disagreements(store: Store, digests: set[str]) -> list[tuple[str, str, str]]:
    """The functions on which the two checkers differ; one the Lean checker skipped (no verdict) is not compared."""
    return sorted((d, store.zig[d], store.lean[d]) for d in digests if d in store.lean and store.zig[d] != store.lean[d])


def where(store: Store, digest: str) -> list[str]:
    return [f"{key}:{name}" for key, entries in store.corpus.items() for d, name in entries if d == digest][:3]


def is_unchecked(block: str) -> bool:
    """Whether a function's line says the exporter did not describe it (`unchecked REASON`): a checker only reads the line."""
    return block.split("\n", 1)[0].rsplit(" ", 1)[-1] != "-"


def lean_plan(store: Store, wanted: set[str], cap: int) -> tuple[list[str], list[str]]:
    """The functions the Lean checker is asked about and those it skips for size. Only a function it has no verdict for can
    be skipped, only above `cap` bytes of certificate text, never an unchecked one (it costs nothing), and never when a
    checker changed since the verdicts were kept (then every function is checked) or when `cap` is 0."""
    missing = sorted(d for d in wanted if d not in store.lean)
    if cap <= 0 or store.zig_fresh or store.lean_fresh:
        return missing, []
    skipped = [d for d in missing if len(store.block(d)) > cap and not is_unchecked(store.block(d))]
    return [d for d in missing if d not in set(skipped)], skipped


def differential(store: Store, lake: str, compiler: str, jobs: int, scratch: Path, cap: int = LEAN_CAP_BYTES, run=subprocess.run) -> dict:
    wanted = {digest for entries in store.corpus.values() for digest, _ in entries}
    lean_run, skipped = lean_plan(store, wanted, cap)
    missing = {"zig": sorted(d for d in wanted if d not in store.zig), "lean": lean_run}
    commands = {"zig": [compiler, "validate-certificates"], "lean": certcheck_binary(lake)}
    check_batches(store, missing, commands, jobs, scratch, {"lean": tool_env(lake)})
    return {"functions": len(wanted), "zig_checked": len(missing["zig"]), "lean_checked": len(missing["lean"]), "wanted": wanted,
            "skipped": skipped, "skipped_bytes": sum(len(store.block(d)) for d in skipped)}


# ---- the validator's own fixtures ---------------------------------------------------------------------------------------

def fixtures_of(source: Path = FIXTURE_SOURCE) -> list[tuple[str, str]]:
    """The (name, function text) of each hand-written function the validator's tests judge, read from those tests."""
    found = []
    for match in FIXTURE.finditer(source.read_text()):
        lines = [line.strip()[2:] for line in match.group(3).splitlines() if line.strip().startswith("\\\\")]
        found.append((match.group(1), "\n".join(lines) + "\n"))
    return found


def fixture_differential(header: str, lake: str, compiler: str, scratch: Path) -> list[tuple[str, str, str, str]]:
    """Run both checkers on each fixture (one file each, so a file one refuses does not hide the rest). Returns the
    (digest, name, zig, lean) of those they judge differently."""
    fixtures = fixtures_of()
    if len(fixtures) < MIN_FIXTURES:
        raise ProofError(f"ownership-proof: found {len(fixtures)} fixtures in {FIXTURE_SOURCE.name}, expected at least {MIN_FIXTURES}")
    directory = scratch / "fixtures"
    directory.mkdir(parents=True)
    for index, (_, text) in enumerate(fixtures):
        (directory / f"{index:03d}.certificate").write_text(header + text.replace("ownership-certificate-v2\n", "", 1))
    verdicts = {}
    for tool, command, env in (("zig", [compiler, "validate-certificates"], None), ("lean", certcheck_binary(lake), tool_env(lake))):
        done = subprocess.run(command + [str(directory)], capture_output=True, text=True, errors="replace", env=env)
        if done.returncode not in (0, 1, 2):
            raise ProofError(f"ownership-proof: {tool} failed on the fixtures: {(done.stdout + done.stderr)[-800:]}")
        for line in done.stdout.splitlines():
            parts = line.split(" ", 2)
            if len(parts) == 3 and parts[0].endswith(".certificate"):
                verdicts.setdefault(parts[0].rsplit("/", 1)[-1], {})[tool] = "error" if parts[1] == "error" else parts[2].strip()
    different = []
    for index, (name, text) in enumerate(fixtures):
        pair = verdicts.get(f"{index:03d}.certificate", {})
        if pair.get("zig") != pair.get("lean"):
            different.append((block_digest(text), name, pair.get("zig", "?"), pair.get("lean", "?")))
    return different


# ---- the link ---------------------------------------------------------------------------------------------------------

def link_programs(compiler: str, lake: str, certificates: Path, run=subprocess.run) -> dict:
    """Link the callee tables of every program under `certificates` with both checkers (design §9, entry 57). Their lines
    (`DIR CALLER link-reject ENTRY TAG`) must agree, and there must be none. Returns the counts and the time each took."""
    lines, seconds, summary = {}, {}, ""
    for tool, command, env in (("zig", [compiler, "link-certificates"], None), ("lean", certcheck_binary(lake) + ["--link"], tool_env(lake))):
        started = time.monotonic()
        done = run(command + [str(certificates)], capture_output=True, text=True, errors="replace", env=env)
        seconds[tool] = time.monotonic() - started
        if done.returncode not in (0, 1):
            raise ProofError(f"ownership-proof: {tool} could not link the callee tables (exit {done.returncode}): {(done.stdout + done.stderr)[-800:]}")
        lines[tool] = [line for line in done.stdout.splitlines() if line and not line.startswith("summary ")]
        if tool == "zig":
            summary = next((line for line in done.stdout.splitlines() if line.startswith("summary ")), "")
    if lines["zig"] != lines["lean"]:
        only = sorted(set(lines["zig"]) ^ set(lines["lean"]))
        raise ProofError("ownership-proof: the two link checks disagree:\n  " + "\n  ".join(only[:20]))
    if lines["zig"]:
        raise ProofError("ownership-proof: callee table entries that do not match their callee:\n  " + "\n  ".join(lines["zig"][:20]))
    return {"summary": summary, "zig_seconds": seconds["zig"], "lean_seconds": seconds["lean"]}


# ---- the mutants -----------------------------------------------------------------------------------------------------

def mutant_check(store: Store, lake: str, compiler: str, jobs: int, scratch: Path, run=subprocess.run) -> dict:
    """Lower the fixed programs, mutate their certificates and require both checkers to reject every mutant."""
    programs = sorted(FIXTURES.glob("*.selka"))
    if not programs:
        raise ProofError(f"ownership-proof: no mutant programs under {FIXTURES}")
    summary = {"programs": len(programs), "mutants": 0, "classes": {}, "reused": 0}
    for program in programs:
        done = run([compiler, "dump-ir", str(program), "--certificate"], capture_output=True, text=True, errors="replace")
        if done.returncode != 0:
            raise ProofError(f"ownership-proof: cannot lower {program.name}: {(done.stdout[-300:] + done.stderr[-800:])}")
        base = done.stdout
        key = hashlib.sha256((base + store.zig_id + store.lean_id).encode()).hexdigest()
        cached = store.mutant_summary(key)
        if cached:
            summary["mutants"] += cached["count"]
            summary["reused"] += 1
            for name, count in cached["classes"].items():
                summary["classes"][name] = summary["classes"].get(name, 0) + count
            continue
        directory = scratch / "mutants" / program.stem
        shutil.rmtree(directory, ignore_errors=True)
        directory.mkdir(parents=True)
        base_file = directory / "base.certificate"
        base_file.write_text(base)
        made = directory / "made"
        listing = run([compiler, "mutate-certificates", str(base_file), str(made)], capture_output=True, text=True, errors="replace")
        if listing.returncode != 0:
            raise ProofError(f"ownership-proof: mutate-certificates failed on {program.name}: {listing.stderr[-500:]}")
        manifest = [line.split(" ", 2) for line in listing.stdout.splitlines() if line.strip()]
        if not manifest:
            raise ProofError(f"ownership-proof: {program.name} produced no mutants")
        classes: dict[str, int] = {}
        for _, class_name, _ in manifest:
            classes[class_name] = classes.get(class_name, 0) + 1
        problems = []
        for tool, command, env in (("zig", [compiler, "validate-certificates"], None), ("lean", certcheck_binary(lake), tool_env(lake))):
            out = run_checker(command, made, tool, env)
            rejected = {line.split(" ", 1)[0].rsplit("/", 1)[-1] for line in out.splitlines() if " reject " in line}
            for name, class_name, function in manifest:
                if name not in rejected:
                    problems.append(f"{tool} accepted mutant {program.name}/{name} ({class_name} in {function})")
        if problems:
            raise ProofError("ownership-proof: mutants that a checker did not reject:\n  " + "\n  ".join(problems[:20]))
        store.keep_mutant_summary(key, {"count": len(manifest), "classes": classes})
        summary["mutants"] += len(manifest)
        for name, count in classes.items():
            summary["classes"][name] = summary["classes"].get(name, 0) + count
    if len(summary["classes"]) < MUTANT_CLASSES:
        raise ProofError(f"ownership-proof: only {len(summary['classes'])} of {MUTANT_CLASSES} fault classes produced mutants: {sorted(summary['classes'])}")
    return summary


# ---- the action ------------------------------------------------------------------------------------------------------

def main(argv=None, run=subprocess.run) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--certificates", type=Path, default=ROOT / ".selka-cache" / "ownership-certificates")
    parser.add_argument("--store", type=Path, default=None,
                        help="the directory that holds the verdict store (default: the verification coordinator's shared root, else .selka-cache/ownership-proof)")
    parser.add_argument("--jobs", type=int, default=default_jobs(), help="concurrent checker processes (default: the allowed CPUs less one, at most 16)")
    parser.add_argument("--lean-cap-bytes", type=int, default=LEAN_CAP_BYTES,
                        help="the Lean checker skips a function above this size of certificate text unless a checker changed (default %d; 0 = no cap, the proofs profile)" % LEAN_CAP_BYTES)
    parser.add_argument("--known", type=Path, default=KNOWN)
    parser.add_argument("--with-release-certificates", action="store_true",
                        help="also check the release runs' certificates (the gate runs them with -Dtest-release=true)")
    args = parser.parse_args(argv)
    started = time.monotonic()
    try:
        lake = find_lake()
        lake_build(lake, run)
        regenerated = []
        retired = []
        if args.certificates.resolve() == (ROOT / corpus.CORPUS).resolve():
            try:
                regenerated = corpus.regenerate(args.compiler, ROOT, args.jobs, run, release=args.with_release_certificates)
            except corpus.CorpusError as error:
                raise ProofError(f"ownership-proof: {error}") from error
            if not args.with_release_certificates:
                retired = corpus.retire(ROOT)
        store = Store(store_directory(args.store, args.certificates), zig_identity(), lean_identity(lake, run))
        files, functions = collect(args.certificates, store)
        if not store.corpus:
            raise ProofError(f"ownership-proof: no certificates under {args.certificates}; the language gate writes them (selka test --emit-certificates)")
        scratch = Path(tempfile.mkdtemp(prefix="ownership-proof-", dir=os.environ.get("TMPDIR") or None))
        try:
            outcome = differential(store, lake, args.compiler, args.jobs, scratch, args.lean_cap_bytes, run)
            links = link_programs(args.compiler, lake, args.certificates, run)
            mutants = mutant_check(store, lake, args.compiler, args.jobs, scratch, run)
            fixtures = fixture_differential(store.header, lake, args.compiler, scratch)
        finally:
            shutil.rmtree(scratch, ignore_errors=True)
        known = load_known(args.known)
        found = [(d, ", ".join(where(store, d)), zig, lean) for d, zig, lean in disagreements(store, outcome["wanted"])] + fixtures
        unexpected = [d for d in found if d[0] not in known]
        store.save()
        for digest, label, zig, lean in found:
            status = "known" if digest in known else "DISAGREEMENT"
            print(f"ownership-proof: {status}: {label} [{digest}] zig={zig!r} lean={lean!r}" + (f" ({known[digest]})" if digest in known else ""))
        for digest in outcome["skipped"][:6]:
            print(f"ownership-proof: skipped on the Lean side: {', '.join(where(store, digest))[:200]} ({len(store.block(digest))} bytes)")
        agreed = {d[0] for d in found}
        stale = [d for d in known if d not in agreed]
        for digest in stale:
            print(f"ownership-proof: note: known disagreement {digest[:12]} no longer applies; remove it from {args.known.name}")
        if regenerated:
            print(f"ownership-proof: regenerated {len(regenerated)} certificate directories whose stamp was not this compiler's and these suites': {', '.join(regenerated)}")
        if retired:
            print(f"ownership-proof: removed {len(retired)} release certificate directories (release builds are off): {', '.join(retired)}")
        print(f"ownership-proof: lake build ok; {outcome['functions']} functions in the corpus ({files} files read), "
              f"{outcome['zig_checked']} checked by the Zig validator and {outcome['lean_checked']} by the Lean checker this run; "
              f"{len(outcome['skipped'])} skipped on the Lean side for size ({outcome['skipped_bytes'] // 1000} KB, above {args.lean_cap_bytes} bytes; the Zig validator checked them); "
              f"callee tables linked ({links['summary'].replace('summary ', '')}; {links['zig_seconds']:.1f} s Zig, {links['lean_seconds']:.1f} s Lean); "
              f"{mutants['mutants']} mutants of {mutants['programs']} programs rejected by both; "
              f"{len(found)} disagreements ({len(found) - len(unexpected)} known; {len(fixtures_of())} validator fixtures compared); {time.monotonic() - started:.1f} s")
        print(fact_proof.run_all(args.compiler, args.certificates, run, store.shared.parent))
        if unexpected:
            return 1
        return 0
    except (ProofError, fact_proof.FactError) as error:
        print(error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
