#!/usr/bin/env python3
"""The IR verifier differential: the Zig verifier (`selka verify-ir`) against its Lean copy (`proofs/verify_ir`,
`lake exe irverify`).

    python3 scripts/verify_ir_proof.py --compiler zig-out/bin/selka [--certificates DIR] [--work DIR] [--per-class N] [--gate]

1. **The build.** `lake build` in `proofs/verify_ir`; an error or a `sorry` fails, and so does a changed axiom set: the
   build runs `VerifyIr/Audit.lean`, whose `#assert_axioms` refuses any theorem of the two proofs that depends on an
   axiom beyond `propext`, `Classical.choice` and `Quot.sound`.
2. **The corpus.** Every `program.core-ir` under DIR (the final IR the language gate's builds wrote with
   `--emit-certificates`, one per program) is checked by both; they must print the same lines, and every line must be an
   acceptance (the Debug compiler that wrote them verified each module in memory). The union-tag rule's count is printed,
   `N payload reads justified, M not justified (shape M)`, and more than `SHAPE_M_CEILING` reads of shape M fail.
3. **The mutants.** `scripts/verify_ir_mutants.py` makes single-rule mutants of the corpus; both checkers must print the
   same lines for every mutant file, and the mutated function must be refused for the class's rule. A class with no
   mutant on its rule fails, except the ones listed in `EMPTY_CLASSES` (no site in the corpus, with the reason).
4. **The translation** (`--gate`). `lake exe irverify --facts DIR`: every program's fact certificate is the translation of
   its IR (`translatesB`, the hypothesis of `VerifyIr.modWf_of_verdicts` that ties the H2 theorem to the build); a mismatch or
   a program without a certificate fails. The fixture `test/fixtures/verify-ir-proof/translation-mismatch/` (a certificate
   with one operand changed by hand) must be reported, so the check is shown able to fail.
5. **The C interop programs** (`--gate`). `test/core/c_interop.selka`, `c_interop_linear.selka` and `c_on_fail.selka` are built, and
   `test/core/c_interop_tests.selka` tested with `--allow-host`, all with `--link test/core/c_interop.c --emit-certificates` into
   the work directory: the first programs
   with user-written `extern func` span parameters. Both checkers must agree on them and on their mutants (no class
   coverage is required of so small a corpus), and their certificates must be their IR's translation.
6. **The pinned real program** (`--gate`). `test/fixtures/verify-ir-proof/protobuf-addressbook/` (the protobuf library's
   addressbook example and its generated decoders, vendored: `PROVENANCE.txt`) is built with `--emit-certificates`; both
   checkers must accept it identically, its certificates must translate, and its union-tag counts are printed.

Lean is a developer and gate tool only; `lake` is found through `SELKA_LAKE` or `$HOME/.elan/bin/lake`. Python is allowed
in gate drivers: nothing here is part of the install graph or of `src/`.
"""
from __future__ import annotations

import argparse
import collections
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROOFS = ROOT / "proofs" / "verify_ir"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify_ir_mutants as mutants  # noqa: E402

# Classes with no site in today's corpus, with the reason: reported, not failed.
EMPTY_CLASSES = {
    "shallow-copy": "the corpus has no list_copy of managed elements marked as a place copy (the only form the class can unmark)",
}
# The payload reads of the corpus the union-tag rule does not justify but lets through: a `list_get` value read under a test
# of an element's tag (shape M, the reads that need alias reasoning; experiments/verify-ir-lean-20261111/DECISIONS.md). The
# action prints the count and fails when it grows past this ceiling, so a new unjustified read cannot pass unnoticed.
# 11 since lane FX12 (15 November 2026): `tests/lang/match_mut_receivers.selka` adds one more `match mut` on a list element.
SHAPE_M_CEILING = 11
FIXTURE = ROOT / "test" / "fixtures" / "verify-ir-proof" / "translation-mismatch"
# A pinned real program (`PROVENANCE.txt`): the protobuf addressbook example and its generated decoders, vendored.
PINNED = ROOT / "test" / "fixtures" / "verify-ir-proof" / "protobuf-addressbook"
C_SOURCE = "test/core/c_interop.c"


class ProofError(RuntimeError):
    """The differential cannot certify: a tool failed, or the two checkers disagree."""


def find_lake() -> str:
    chosen = os.environ.get("SELKA_LAKE") or os.path.join(os.environ.get("HOME", ""), ".elan", "bin", "lake")
    if os.path.isfile(chosen) and os.access(chosen, os.X_OK):
        return chosen
    raise ProofError(f"verify-ir-proof: the Lean build tool `lake` is missing ({chosen}); see proofs/verify_ir/README.md")


def lake_build(lake: str) -> Path:
    env = dict(os.environ)
    env["PATH"] = os.path.dirname(lake) + os.pathsep + env.get("PATH", "")
    built = subprocess.run([lake, "build"], cwd=PROOFS, env=env, capture_output=True, text=True, errors="replace")
    text = built.stdout + built.stderr
    if built.returncode != 0 or "sorry" in text or "error:" in text:
        raise ProofError(f"verify-ir-proof: `lake build` in proofs/verify_ir failed (exit {built.returncode}):\n" +
                         "\n".join(text.splitlines()[-40:]))
    return PROOFS / ".lake" / "build" / "bin" / "irverify"


def verdicts(command: list[str], target: Path, summaries: list[str] | None = None) -> list[str]:
    """The verdict lines a checker prints for `target`, without its summary lines (appended to `summaries` when given);
    exit 0 and 1 are verdicts, others fail."""
    done = subprocess.run(command + [str(target)], capture_output=True, text=True, errors="replace")
    if done.returncode not in (0, 1):
        raise ProofError(f"verify-ir-proof: `{' '.join(command)} {target}` failed (exit {done.returncode}): "
                         f"{(done.stdout + done.stderr)[-800:]}")
    lines = done.stdout.splitlines()
    if summaries is not None:
        summaries.extend(line for line in lines if line.startswith("summary "))
    return [line for line in lines if not line.startswith("summary ")]


def union_counts(summaries: list[str]) -> tuple[int, int]:
    """(justified, shape M) from irverify's `summary union-tags justified=N shape-m=M` line."""
    for line in summaries:
        if line.startswith("summary union-tags "):
            fields = dict(item.split("=") for item in line.split()[2:])
            return int(fields["justified"]), int(fields["shape-m"])
    raise ProofError("verify-ir-proof: irverify printed no union-tag counts")


def first_difference(left: list[str], right: list[str]) -> str:
    for a, b in zip(left, right):
        if a != b:
            return f"zig: {a}\n  lean: {b}"
    return f"zig printed {len(left)} lines, lean {len(right)}"


def corpus(zig: list[str], lean: list[str], root: Path, summaries: list[str] | None = None) -> int:
    files = sorted(root.rglob("*.core-ir"))
    if not files:
        raise ProofError(f"verify-ir-proof: no core-ir text under {root}; the language gate writes them with --emit-certificates")
    left, right = verdicts(zig, root), verdicts(lean, root, summaries)
    if left != right:
        raise ProofError("verify-ir-proof: the checkers disagree on the corpus:\n  " + first_difference(left, right))
    refused = [line for line in left if " reject " in line or " error " in line]
    if refused:
        raise ProofError("verify-ir-proof: the corpus holds IR the verifiers refuse:\n  " + "\n  ".join(refused[:10]))
    return len(files)


def mutant_run(zig: list[str], lean: list[str], root: Path, work: Path, per_class: int, coverage: bool = True) -> tuple[int, dict]:
    out = work / "mutants"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    sources = sorted(root.rglob("*.core-ir"))
    manifest = []
    for n, (name, rule, function, module) in enumerate(mutants.mutants(sources, per_class)):
        path = out / f"{name}-{n:04d}.core-ir"
        path.write_text(module.render())
        manifest.append((path.name, name, rule, function))
    left, right = verdicts(zig, out), verdicts(lean, out)
    if left != right:
        raise ProofError("verify-ir-proof: the checkers disagree on a mutant:\n  " + first_difference(left, right))
    by_file = collections.defaultdict(list)
    for line in left:
        by_file[Path(line.split()[0]).name].append(line.split())
    hits = collections.Counter()
    for file, name, rule, function in manifest:
        target = "types" if rule in ("view-storage", "type-table") else function
        lines = [w for w in by_file[file] if w[1] == target]
        got = lines[0][3] if lines and lines[0][2] == "reject" else "accept"
        hits[(name, got == rule)] += 1
    missing = [name for name, _, _ in mutants.CLASSES if hits[(name, True)] == 0 and name not in EMPTY_CLASSES]
    if missing and coverage:
        raise ProofError("verify-ir-proof: no mutant of these classes was refused for its rule: " + ", ".join(missing))
    return len(manifest), hits


def facts_check(lean: list[str], root: Path, expect_mismatch: bool = False) -> int:
    """`irverify --facts ROOT`: the number of programs, every one with a certificate that is its IR's translation (or, for the
    fixture, exactly one mismatched function)."""
    done = subprocess.run(lean + ["--facts", str(root)], capture_output=True, text=True, errors="replace")
    summary = [line for line in done.stdout.splitlines() if line.startswith("facts programs=")]
    if not summary:
        raise ProofError(f"verify-ir-proof: `irverify --facts {root}` printed no summary: {(done.stdout + done.stderr)[-500:]}")
    fields = dict(item.split("=") for item in summary[-1].split()[1:])
    programs, mismatches, missing = int(fields["programs"]), int(fields["mismatches"]), int(fields["without-certificate"])
    if expect_mismatch:
        if done.returncode != 1 or mismatches != 1 or "translate-mismatch" not in done.stdout:
            raise ProofError(f"verify-ir-proof: the translation check did not report the changed certificate of {root}: {done.stdout[-500:]}")
        return programs
    if done.returncode != 0 or mismatches or missing or programs == 0:
        raise ProofError(f"verify-ir-proof: fact certificates that are not their IR's translation under {root}:\n" +
                         "\n".join(done.stdout.splitlines()[-12:]))
    return programs


def pinned_program(compiler: str, work: Path) -> Path:
    """Build the vendored protobuf addressbook (`PINNED`) with certificates; their root."""
    root = work / "pinned"
    shutil.rmtree(root / "certs", ignore_errors=True)
    argv = [str(Path(compiler).resolve()), "build", "main.selka", "-o", str((root / "addressbook").resolve()), "--verify-facts",
            "--emit-certificates", str((root / "certs").resolve()), "--cache-dir", str((root / "cache").resolve())]
    done = subprocess.run(argv, cwd=PINNED, capture_output=True, text=True, errors="replace")
    if done.returncode != 0:
        raise ProofError(f"verify-ir-proof: the pinned program {PINNED} failed to build (exit {done.returncode}): "
                         f"{(done.stdout + done.stderr)[-800:]}")
    return (root / "certs").resolve()


def c_interop(compiler: str, work: Path) -> Path:
    """Build and test the C interop programs with certificates; their certificate root."""
    root = work / "c-interop"
    shutil.rmtree(root / "certs", ignore_errors=True)
    cache = str(root / "cache")
    runs = [
        [compiler, "build", "test/core/c_interop.selka", "-o", str(root / "c_interop"), "--link", C_SOURCE, "--verify-facts",
         "--emit-certificates", str(root / "certs" / "c_interop"), "--cache-dir", cache],
        [compiler, "test", "test/core/c_interop_tests.selka", "--link", C_SOURCE, "--allow-host", "--force", "--verify-facts",
         "--emit-certificates", str(root / "certs" / "tests"), "--cache-dir", cache],
    ]
    # The other C-backed programs that link the same fixture: `@linear` records and `on fail:` over C results.
    for name in ("c_interop_linear", "c_on_fail"):
        runs.append([compiler, "build", f"test/core/{name}.selka", "-o", str(root / name), "--link", C_SOURCE, "--verify-facts",
                     "--emit-certificates", str(root / "certs" / name), "--cache-dir", cache])
    for argv in runs:
        done = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, errors="replace")
        if done.returncode != 0:
            raise ProofError(f"verify-ir-proof: `{' '.join(argv[1:3])}` failed (exit {done.returncode}): {(done.stdout + done.stderr)[-800:]}")
    return root / "certs"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--certificates", default=str(ROOT / ".selka-cache" / "ownership-certificates"))
    parser.add_argument("--work", default=None)
    parser.add_argument("--per-class", type=int, default=6)
    parser.add_argument("--gate", action="store_true", help="also the translation check, its fixture and the C interop programs")
    parser.add_argument("--supplementary", action="store_true",
                        help="a small corpus: require agreement but not a mutant of every class; print the classes it reached")
    args = parser.parse_args()
    try:
        lake = find_lake()
        lean = [str(lake_build(lake))]
        zig = [args.compiler, "verify-ir"]
        root = Path(args.certificates)
        work = Path(args.work) if args.work else Path(tempfile.mkdtemp(prefix="verify-ir-proof-"))
        summaries: list[str] = []
        files = corpus(zig, lean, root, summaries)
        justified, shape_m = union_counts(summaries)
        print(f"verify-ir-proof: {justified} payload reads justified, {shape_m} not justified (shape M)")
        if shape_m > SHAPE_M_CEILING:
            raise ProofError(f"verify-ir-proof: {shape_m} payload reads of shape M, past the ceiling of {SHAPE_M_CEILING}: a new "
                             "read the union-tag rule does not justify (raise SHAPE_M_CEILING only with the reason in DECISIONS.md)")
        count, hits = mutant_run(zig, lean, root, work, args.per_class, coverage=not args.supplementary)
        if args.supplementary:
            reached = sorted(name for (name, ok), n in hits.items() if ok and n)
            print("verify-ir-proof: classes refused for their rule: " + ", ".join(reached))
        on = sum(v for (n, ok), v in hits.items() if ok)
        print(f"verify-ir-proof: corpus {files} programs agree (all accepted); {count} mutants in {len(mutants.CLASSES)} "
              f"classes agree, {on} refused for their class's rule")
        for name, reason in EMPTY_CLASSES.items():
            if hits[(name, True)] == 0:
                print(f"verify-ir-proof: class {name} has no site: {reason}")
        if args.gate:
            translated = facts_check(lean, root)
            facts_check(lean, FIXTURE, expect_mismatch=True)
            ffi = c_interop(args.compiler, work)
            ffi_summaries: list[str] = []
            ffi_files = corpus(zig, lean, ffi, ffi_summaries)
            ffi_justified, ffi_shape_m = union_counts(ffi_summaries)
            ffi_count, _ = mutant_run(zig, lean, ffi, work / "c-interop-mutants", 3, coverage=False)
            facts_check(lean, ffi)
            pinned = pinned_program(args.compiler, work)
            pinned_summaries: list[str] = []
            corpus(zig, lean, pinned, pinned_summaries)
            facts_check(lean, pinned)
            pinned_justified, pinned_shape_m = union_counts(pinned_summaries)
            print(f"verify-ir-proof: the pinned protobuf addressbook agrees, translates, and has {pinned_justified} payload reads "
                  f"justified, {pinned_shape_m} of shape M")
            print(f"verify-ir-proof: {translated} fact certificates are their IR's translation (the changed fixture is "
                  f"reported); C interop {ffi_files} programs and {ffi_count} mutants agree, and translate; their payload reads "
                  f"{ffi_justified} justified, {ffi_shape_m} of shape M")
        if not args.work:
            shutil.rmtree(work, ignore_errors=True)
        return 0
    except ProofError as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
