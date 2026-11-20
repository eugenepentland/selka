#!/usr/bin/env python3
"""The facts half of the gate action `ownership-proof` (docs/audits/ownership-certificates-plan-2026-10-26.md, packages C7.3 and C7.4).

    python3 scripts/fact_proof.py --compiler zig-out/bin/selka [--certificates DIR]

It is called by `scripts/ownership_proof.py` and runs alone for a developer. It does four things and fails, never skips:

1. **The proofs.** `lake build` in `proofs/facts` (incremental: it rebuilds only what a change under `proofs/facts` or
   `proofs/arith` touched). A `sorry`, any error, a failed `#guard` (the verdicts on the fixtures) or a failed axiom audit
   (`Facts/Check.lean`) fails it.
2. **The corpus.** Every function of every fact certificate (`NAME.fact-certificate`, docs/design/fact-certificates.md) that the
   language gate's runs wrote under DIR is checked by `selka validate-fact-certificates` and by the Lean checker
   (`lake exe factcheck`). One rejection fails it, so does a corpus with no fact certificate at all (the debug runs write
   them), and so does any difference between the two checkers: they must print the same line
   (the verdict, with the check, block and value of a rejection) for every function and the same summary.
3. **The mutants.** The programs in `test/fixtures/fact-proof/` are lowered (`selka dump-ir FILE --fact-certificate`), their
   certificates mutated (`selka mutate-fact-certificates`, the fault classes of `src/core/fact_mutants.zig`), and the Zig
   validator must reject every mutant in the function it edited and in no other; the Lean checker must give the same lines.
4. **The fixtures.** The certificates under `proofs/facts/fixtures/` have their expected verdicts beside them; the Lean checker
   must give them. So must both checkers for those under `test/fixtures/fact-proof/certificates/`.

Both checkers read the same files and take seconds for the whole corpus, so there is no size cap. The agreed verdict lines of a
certificate file are kept in the per-user verification store (`ownership_verdict_store.py`, kind `facts`) under the digest of the
file and the digest of the pair of checkers (the validator's sources; proofs/facts, proofs/arith and the Lean toolchain), so a run
checks only the files it has not seen: after an edit to `src/` only the programs whose final IR changed, after an edit to either
checker everything.

Python is allowed in gate drivers: nothing here is part of the install graph or of `src/`.
"""
from __future__ import annotations

import argparse
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
import ownership_verdict_store as verdicts  # noqa: E402  (the per-user store of verdicts, shared with ownership-proof)
CORPUS = ".selka-cache/ownership-certificates"
FIXTURES = ROOT / "test" / "fixtures" / "fact-proof"
PROOFS = ROOT / "proofs" / "facts"
ARITH = ROOT / "proofs" / "arith"
# What the Zig verdict depends on: the validator, the form and the reader of the text, the line format and the operation names.
ZIG_SOURCES = ("src/core/validate_facts.zig", "src/core/fact_function.zig", "src/core/fact_text.zig", "src/core/fact_commands.zig", "src/core/ir.zig")
KIND = "facts"
LEAN_FIXTURES = PROOFS / "fixtures"
# Certificates the validator and the Lean checker must both judge as the `.expected` beside each says (the Zig side of the fixtures).
SHARED_FIXTURES = FIXTURES / "certificates"
# The fault classes of `Class` in src/core/fact_mutants.zig; each must make a mutant on the fixtures.
MUTANT_CLASSES = 9
SUMMARY = re.compile(r"^summary files=(\d+) functions=(\d+) accept=(\d+) reject=(\d+) errors=(\d+) derived=(\d+) assumed=(\d+) proven=(\d+) unchecked=(\d+)$")


class FactError(RuntimeError):
    """The facts cannot be certified: a tool failed, a fact certificate was rejected or a mutant was accepted."""


def parse_summary(output: str) -> dict:
    """The counts of the `summary` line `validate-fact-certificates` ends with."""
    for line in reversed(output.splitlines()):
        found = SUMMARY.match(line.strip())
        if found:
            names = ("files", "functions", "accept", "reject", "errors", "derived", "assumed", "proven", "unchecked")
            return dict(zip(names, (int(x) for x in found.groups())))
    raise FactError("fact-proof: validate-fact-certificates printed no summary line: " + output[-300:])


# ---- the Lean checker ------------------------------------------------------------------------------------------------

def find_lake(env=None) -> str:
    """The `lake` executable: `SELKA_LAKE`, else `$HOME/.elan/bin/lake`. A missing Lean fails the action."""
    env = os.environ if env is None else env
    chosen = env.get("SELKA_LAKE") or os.path.join(env.get("HOME", ""), ".elan", "bin", "lake")
    if os.path.isfile(chosen) and os.access(chosen, os.X_OK):
        return chosen
    raise FactError(
        f"fact-proof: the Lean build tool `lake` is missing ({chosen}). Install elan with the toolchain pinned in "
        "proofs/facts/lean-toolchain (see proofs/ownership/README.md) or point SELKA_LAKE at lake. "
        "The complete gate needs Lean for this action and never skips it.")


def tool_env(lake: str) -> dict:
    """The environment for `lake`: its directory first on `PATH`, so the elan shim finds its siblings."""
    env = dict(os.environ)
    env["PATH"] = os.path.dirname(lake) + os.pathsep + env.get("PATH", "")
    return env


def lake_build(lake: str, run=subprocess.run, proofs: Path | None = None) -> None:
    """`lake build` in proofs/facts; a failure, an `error`, or a `sorry` fails the action."""
    proofs = proofs or PROOFS
    built = run([lake, "build"], cwd=proofs, env=tool_env(lake), capture_output=True, text=True, errors="replace")
    text = built.stdout + built.stderr
    if built.returncode != 0 or "sorry" in text or "error:" in text:
        tail = "\n".join(text.splitlines()[-40:])
        raise FactError(f"fact-proof: `lake build` in proofs/facts failed (exit {built.returncode}):\n{tail}")


def factcheck_command(proofs: Path | None = None) -> list[str]:
    """The command that runs the built Lean checker (`lake build` builds it: it is a default target of proofs/facts)."""
    binary = (proofs or PROOFS) / ".lake" / "build" / "bin" / "factcheck"
    if not binary.is_file():
        raise FactError(f"fact-proof: `lake build` in proofs/facts did not build the Lean checker ({binary})")
    return [str(binary)]


def run_factcheck(lake: str, target: Path, run=subprocess.run, proofs: Path | None = None) -> str:
    """The output of the Lean checker on a directory or file (exit 0 when every function is accepted, 1 when one is not). It runs
    where the caller runs, so a relative `target` names the same files the Zig validator is given."""
    done = run(factcheck_command(proofs) + [str(target)], env=tool_env(lake), capture_output=True, text=True, errors="replace")
    if done.returncode not in (0, 1):
        raise FactError(f"fact-proof: the Lean checker failed on {target} (exit {done.returncode}): {(done.stdout + done.stderr)[-800:]}")
    return done.stdout


def differences(zig: str, lean: str, limit: int = 8) -> list[str]:
    """The lines on which two checkers' outputs differ (they must print the same line for every function, in the same order)."""
    zig_lines, lean_lines = zig.splitlines(), lean.splitlines()
    found = []
    for k in range(max(len(zig_lines), len(lean_lines))):
        a = zig_lines[k] if k < len(zig_lines) else "<nothing>"
        b = lean_lines[k] if k < len(lean_lines) else "<nothing>"
        if a != b:
            found.append(f"zig: {a}\n  lean: {b}")
            if len(found) >= limit:
                break
    return found


def fixture_expectations(directory: Path | None = None) -> dict[str, list[str]]:
    """The expected verdict lines (`NAME verdict`) of each certificate under proofs/facts/fixtures, from the `.expected` beside it."""
    directory = directory or LEAN_FIXTURES
    expected = {}
    for certificate in sorted(directory.glob("*.fact-certificate")):
        beside = certificate.with_suffix(".expected")
        if not beside.is_file():
            raise FactError(f"fact-proof: {certificate.name} has no .expected file beside it")
        expected[certificate.name] = [line for line in beside.read_text().splitlines() if line.strip()]
    if not expected:
        raise FactError(f"fact-proof: no fixtures under {directory}")
    return expected


def fixtures_check(lake: str, run=subprocess.run, directory: Path | None = None, proofs: Path | None = None) -> int:
    """The Lean checker's verdicts on proofs/facts/fixtures against the `.expected` files; the number of fixtures."""
    directory = directory or LEAN_FIXTURES
    expected = fixture_expectations(directory)
    out = run_factcheck(lake, directory, run, proofs)
    got: dict[str, list[str]] = {}
    for line in out.splitlines():
        parts = line.split(" ", 2)
        if len(parts) == 3 and parts[2].split(" ", 1)[0] in ("accept", "reject", "error"):
            got.setdefault(parts[0].rsplit("/", 1)[-1], []).append(parts[1] + " " + parts[2])
    wrong = [f"{name}: expected {want}, the Lean checker said {got.get(name)}" for name, want in expected.items() if got.get(name) != want]
    if wrong:
        raise FactError("fact-proof: the Lean checker's verdicts on proofs/facts/fixtures differ from the expected ones:\n  " + "\n  ".join(wrong[:10]))
    return len(expected)


def shared_fixtures_check(compiler: str, lake: str, run=subprocess.run, directory: Path | None = None, proofs: Path | None = None) -> int:
    """Both checkers' verdicts on the certificates under test/fixtures/fact-proof/certificates against the `.expected` beside each:
    the validator and the Lean checker must print the same verdict line for every function. The number of certificates."""
    directory = directory or SHARED_FIXTURES
    expected = fixture_expectations(directory)
    zig = run([compiler, "validate-fact-certificates", str(directory)], capture_output=True, text=True, errors="replace")
    if zig.returncode not in (0, 1):
        raise FactError(f"fact-proof: validate-fact-certificates failed on {directory} (exit {zig.returncode}): {(zig.stdout + zig.stderr)[-500:]}")
    lean = run_factcheck(lake, directory, run, proofs)
    wrong = []
    for tool, out in (("the Zig validator", zig.stdout), ("the Lean checker", lean)):
        got: dict[str, list[str]] = {}
        for line in out.splitlines():
            parts = line.split(" ", 2)
            if len(parts) == 3 and parts[2].split(" ", 1)[0] in ("accept", "reject", "error"):
                got.setdefault(parts[0].rsplit("/", 1)[-1], []).append(parts[1] + " " + parts[2])
        wrong += [f"{name}: expected {want}, {tool} said {got.get(name)}" for name, want in expected.items() if got.get(name) != want]
    if wrong:
        raise FactError("fact-proof: the two checkers' verdicts on test/fixtures/fact-proof/certificates differ from the expected ones:\n  " + "\n  ".join(wrong[:10]))
    return len(expected)


# ---- identities and the verdict store ----------------------------------------------------------------------------------

def digest_files(paths: list[Path], root: Path) -> str:
    hash = hashlib.sha256()
    for path in sorted(paths):
        hash.update(str(path.relative_to(root)).encode() + b"\0")
        hash.update(path.read_bytes())
        hash.update(b"\0")
    return hash.hexdigest()


def lean_sources(project: Path) -> list[Path]:
    """The files of a Lake project the proofs depend on: its Lean sources (not its build directory), manifest and toolchain pin."""
    found = [p for p in project.rglob("*.lean") if ".lake" not in p.relative_to(project).parts]
    found += [project / name for name in ("lakefile.toml", "lean-toolchain", "lake-manifest.json") if (project / name).is_file()]
    return found


def zig_identity(root: Path = ROOT) -> str:
    """Digest of the sources the Zig verdict depends on."""
    return digest_files([root / name for name in ZIG_SOURCES], root)


def lean_identity(lake: str, run=subprocess.run, proofs: Path | None = None, arith: Path | None = None) -> str:
    """Digest of the Lean checker: the sources of proofs/facts and of proofs/arith it depends on, and the toolchain version."""
    proofs, arith = proofs or PROOFS, arith or ARITH
    version = run([lake, "--version"], cwd=proofs, env=tool_env(lake), capture_output=True, text=True, errors="replace").stdout.strip()
    parts = [digest_files(lean_sources(proofs), proofs), digest_files(lean_sources(arith), arith) if arith.is_dir() else "", version]
    return hashlib.sha256("\0".join(parts).encode()).hexdigest()


def store_directory(requested: Path | None = None) -> Path:
    """Where the verdicts live: `requested`, else the verification coordinator's shared root (made a versioned store first),
    else a directory in the worktree."""
    if requested is not None:
        return requested
    root = verdicts.shared_root()
    if root is not None:
        try:
            verdicts.initialize_host(root)
            return root
        except Exception as error:  # an unusable default store never stops the gate; it only stops the sharing
            print(f"fact-proof: note: the shared verification store {root} is unusable ({str(error)[:120]}); keeping the verdicts in the worktree", file=sys.stderr)
    return ROOT / ".selka-cache" / "fact-proof"


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lines_by_file(output: str, root: Path) -> dict[str, list[str]]:
    """The verdict lines (`NAME verdict`) of each file of a `validate-fact-certificates`-style output, by path relative to `root`."""
    found: dict[str, list[str]] = {}
    for line in output.splitlines():
        parts = line.split(" ", 2)
        if len(parts) == 3 and parts[0] != "summary" and parts[2].split(" ", 1)[0] in ("accept", "reject", "error"):
            key = os.path.relpath(os.path.abspath(parts[0]), os.path.abspath(root))
            found.setdefault(key, []).append(parts[1] + " " + parts[2])
    return found


def corpus_check(compiler: str, certificates: Path, run=subprocess.run, lake: str | None = None, store=None, identity: str = "") -> dict:
    """Validate every fact certificate under `certificates` with the Zig validator and, given `lake`, the Lean checker; the
    counts of the run. The two must print the same lines. With a `store` (and the `identity` of the two checkers), a file whose
    digest has a verdict from this pair of checkers is not checked again: only the files the store has not seen are."""
    files = sorted(certificates.rglob("*.fact-certificate"))
    digests = {path: file_digest(path) for path in files} if store is not None else {}
    cached = store.get_many(KIND, identity, set(digests.values())) if store is not None else {}
    pending = [path for path in files if store is None or digests[path] not in cached]
    target = certificates
    scratch = None
    if store is not None and len(pending) < len(files):
        # Only the files the store has not seen: the same relative paths in a scratch directory (links), so the lines compare.
        scratch = Path(tempfile.mkdtemp(prefix="fact-proof-corpus-", dir=os.environ.get("TMPDIR") or None))
        for path in pending:
            link = scratch / path.relative_to(certificates)
            link.parent.mkdir(parents=True, exist_ok=True)
            link.symlink_to(path.resolve())
        target = scratch
    try:
        counts = {"files": 0, "functions": 0, "accept": 0, "reject": 0, "errors": 0, "derived": 0, "assumed": 0, "proven": 0, "unchecked": 0}
        if pending or store is None:
            done = run([compiler, "validate-fact-certificates", str(target)], capture_output=True, text=True, errors="replace")
            if done.returncode not in (0, 1):
                raise FactError(f"fact-proof: validate-fact-certificates failed on {certificates} (exit {done.returncode}): {(done.stdout + done.stderr)[-800:]}")
            counts = parse_summary(done.stdout)
            if store is None and counts["files"] == 0:
                raise FactError(f"fact-proof: no fact certificates under {certificates}; the language gate's debug run writes them (selka test --emit-certificates)")
            if counts["errors"] != 0 or counts["reject"] != 0 or done.returncode != 0:
                rejected = [line for line in done.stdout.splitlines() if " reject " in line][:12]
                raise FactError(f"fact-proof: {counts['reject']} functions rejected, {counts['errors']} files unreadable:\n  " + "\n  ".join(rejected))
            if lake is not None:
                lean_out = run_factcheck(lake, target, run)
                different = differences(done.stdout, lean_out)
                if different:
                    raise FactError("fact-proof: the Zig validator and the Lean checker disagree on the corpus:\n  " + "\n  ".join(different))
                counts["lean"] = counts["functions"]
            if store is not None:
                found = lines_by_file(done.stdout, target)
                store.put_many(KIND, identity, {digests[path]: json.dumps(found.get(str(path.relative_to(certificates)), []))
                                                for path in pending if found.get(str(path.relative_to(certificates)))})
    finally:
        if scratch is not None:
            shutil.rmtree(scratch, ignore_errors=True)
    if store is not None and not files:
        raise FactError(f"fact-proof: no fact certificates under {certificates}; the language gate's debug run writes them (selka test --emit-certificates)")
    counts["corpus_files"] = len(files) if store is not None else counts["files"]
    counts["reused_files"] = len(files) - len(pending) if store is not None else 0
    counts["corpus_functions"] = counts["functions"] + sum(len(json.loads(cached[digests[path]])) for path in files if store is not None and digests[path] in cached)
    return counts


def manifest_of(output: str) -> list[tuple[str, str, str]]:
    """The mutants `mutate-fact-certificates` wrote, as (file name, class, function)."""
    rows = []
    for line in output.splitlines():
        parts = line.split(" ", 2)
        if len(parts) == 3:
            rows.append((parts[0], parts[1], parts[2].strip()))
    return rows


def verdicts_of(output: str) -> dict[tuple[str, str], bool]:
    """(file name, function) to whether the validator rejected it, from `validate-fact-certificates` lines."""
    found = {}
    for line in output.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[2] in ("accept", "reject"):
            found[(parts[0].rsplit("/", 1)[-1], parts[1])] = parts[2] == "reject"
    return found


def judge_mutants(manifest: list[tuple[str, str, str]], verdicts: dict[tuple[str, str], bool], program: str) -> list[str]:
    """What is wrong with the verdicts on one program's mutants: a mutant accepted, or another function rejected."""
    problems = []
    for name, class_name, function in manifest:
        if not verdicts.get((name, function), False):
            problems.append(f"accepted mutant {program}/{name} ({class_name} in {function})")
        for (other_name, other), rejected in verdicts.items():
            if other_name == name and other != function and rejected:
                problems.append(f"rejected {other} of mutant {program}/{name} ({class_name} edited {function})")
    return problems


def mutant_check(compiler: str, scratch: Path, run=subprocess.run, fixtures: Path = FIXTURES, lake: str | None = None) -> dict:
    """Lower the fixture programs, mutate their fact certificates and require the validator to reject every mutant (and, given
    `lake`, the Lean checker to say the same about each)."""
    programs = sorted(fixtures.glob("*.selka"))
    if not programs:
        raise FactError(f"fact-proof: no mutant programs under {fixtures}")
    summary = {"programs": len(programs), "mutants": 0, "classes": {}}
    problems: list[str] = []
    for program in programs:
        dumped = run([compiler, "dump-ir", str(program), "--fact-certificate"], capture_output=True, text=True, errors="replace")
        if dumped.returncode != 0:
            raise FactError(f"fact-proof: cannot lower {program.name}: {(dumped.stdout[-300:] + dumped.stderr[-800:])}")
        directory = scratch / "fact-mutants" / program.stem
        shutil.rmtree(directory, ignore_errors=True)
        directory.mkdir(parents=True)
        base = directory / "base.fact-certificate"
        base.write_text(dumped.stdout)
        made = directory / "made"
        listing = run([compiler, "mutate-fact-certificates", str(base), str(made)], capture_output=True, text=True, errors="replace")
        if listing.returncode != 0:
            raise FactError(f"fact-proof: mutate-fact-certificates failed on {program.name}: {listing.stderr[-500:]}")
        manifest = manifest_of(listing.stdout)
        if not manifest:
            raise FactError(f"fact-proof: {program.name} produced no mutants")
        judged = run([compiler, "validate-fact-certificates", str(made)], capture_output=True, text=True, errors="replace")
        if judged.returncode not in (0, 1):
            raise FactError(f"fact-proof: validate-fact-certificates failed on the mutants of {program.name}: {(judged.stdout + judged.stderr)[-500:]}")
        problems += judge_mutants(manifest, verdicts_of(judged.stdout), program.name)
        if lake is not None:
            problems += [f"{program.name}: {line}" for line in differences(judged.stdout, run_factcheck(lake, made, run))]
        summary["mutants"] += len(manifest)
        for _, class_name, _ in manifest:
            summary["classes"][class_name] = summary["classes"].get(class_name, 0) + 1
    if problems:
        raise FactError("fact-proof: mutants the validator did not reject in their own function, or the Lean checker judges differently:\n  " + "\n  ".join(problems[:20]))
    if len(summary["classes"]) < MUTANT_CLASSES:
        raise FactError(f"fact-proof: only {len(summary['classes'])} of {MUTANT_CLASSES} fault classes produced mutants: {sorted(summary['classes'])}")
    return summary


def run_all(compiler: str, certificates: Path, run=subprocess.run, store_parent: Path | None = None) -> str:
    """All the checks; the one-line report. Raises `FactError` when any fails."""
    started = time.monotonic()
    lake = find_lake()
    lake_build(lake, run)
    store = verdicts.VerdictStore(store_directory(store_parent))
    identity = hashlib.sha256((zig_identity() + "\0" + lean_identity(lake, run)).encode()).hexdigest()
    counts = corpus_check(compiler, certificates, run, lake, store, identity)
    scratch = Path(tempfile.mkdtemp(prefix="fact-proof-"))
    try:
        mutants = mutant_check(compiler, scratch, run, lake=lake)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    fixtures = fixtures_check(lake, run) + shared_fixtures_check(compiler, lake, run)
    return (f"fact-proof: proofs/facts built (no sorry, axioms audited); {counts['corpus_functions']} functions of {counts['corpus_files']} fact certificates accepted "
            f"by the Zig validator and the Lean checker, which print the same line for each ({counts['reused_files']} of the files reused from the store; "
            f"checked this run: {counts['functions']} functions of {counts['files']} files, with {counts['proven']} proven checks validated, "
            f"{counts['unchecked']} left unchecked, {counts['assumed']} intervals assumed); "
            f"{mutants['mutants']} mutants of {mutants['programs']} programs rejected in their own function, the same by both; "
            f"{fixtures} fixtures judged as expected; {time.monotonic() - started:.1f} s")


def main(argv=None, run=subprocess.run) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--certificates", type=Path, default=ROOT / CORPUS)
    args = parser.parse_args(argv)
    try:
        print(run_all(args.compiler, args.certificates, run))
        return 0
    except FactError as error:
        print(error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
