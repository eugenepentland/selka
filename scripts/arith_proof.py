#!/usr/bin/env python3
"""The gate action `arith-proof` (docs/audits/ownership-certificates-plan-2026-10-26.md, package C8).

    python3 scripts/arith_proof.py

It checks the Lean half of the arithmetic lowering proofs in `proofs/arith` and fails, never skips, when it cannot:

1. **The proofs.** `lake build` in `proofs/arith` (incremental: it rebuilds only what a change under `proofs/arith` touched).
   An `error`, a `sorry`, or any theorem that depends on an axiom other than `propext`, `Classical.choice` and `Quot.sound`
   (the `#assert_axioms` audit in `Arith/Check.lean` is part of the build) fails it.
2. **The templates.** `lake exe arith-templates --check proofs/arith/templates.txt`: the committed file is exactly the LLVM
   text the Lean formulas render. The emitter is compared with that file by `src/core/arith_lowering_test.zig`, a test of
   `zig build test-core`, so the formulas that are proved are the sequences the compiler emits.
3. **The formula document.** `lake exe arith-templates --md proofs/arith/FORMULAS.md`: every generated block of the document
   is what Lean renders.

Lean is a developer and gate tool only. `lake` is found through `SELKA_LAKE` or `$HOME/.elan/bin/lake`.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROOFS = ROOT / "proofs" / "arith"
TEMPLATES = PROOFS / "templates.txt"
FORMULAS = PROOFS / "FORMULAS.md"


class ProofError(Exception):
    """The action cannot certify: a tool is missing or a check failed."""


def find_lake(env=None) -> str:
    """The `lake` executable: `SELKA_LAKE`, else `$HOME/.elan/bin/lake`. A missing Lean fails the action."""
    env = os.environ if env is None else env
    chosen = env.get("SELKA_LAKE") or os.path.join(env.get("HOME", ""), ".elan", "bin", "lake")
    if os.path.isfile(chosen) and os.access(chosen, os.X_OK):
        return chosen
    raise ProofError(
        f"arith-proof: the Lean build tool `lake` is missing ({chosen}). Install elan with the toolchain pinned in "
        "proofs/arith/lean-toolchain (see proofs/ownership/README.md) or point SELKA_LAKE at lake. "
        "The complete gate needs Lean for this action and never skips it.")


def tool_env(lake: str) -> dict:
    """The environment for `lake`: its directory first on `PATH`, so the elan shim finds its siblings."""
    env = dict(os.environ)
    env["PATH"] = os.path.dirname(lake) + os.pathsep + env.get("PATH", "")
    return env


def run_lake(lake: str, arguments: list[str], run=subprocess.run) -> subprocess.CompletedProcess:
    return run([lake, *arguments], cwd=PROOFS, env=tool_env(lake), capture_output=True, text=True, errors="replace")


def lake_build(lake: str, run=subprocess.run) -> None:
    """`lake build`; a failure, an `error`, or a `sorry` fails the action."""
    built = run_lake(lake, ["build"], run)
    text = built.stdout + built.stderr
    if built.returncode != 0 or "sorry" in text or re.search(r"(^|\n)error", text):
        tail = "\n".join(text.splitlines()[-40:])
        raise ProofError(f"arith-proof: `lake build` in proofs/arith failed (exit {built.returncode}):\n{tail}")


def check_rendering(lake: str, run=subprocess.run) -> int:
    """The committed templates and the generated blocks of FORMULAS.md are what Lean renders; returns the case count."""
    for arguments in (["--check", str(TEMPLATES)], ["--md", str(FORMULAS)]):
        done = run_lake(lake, ["exe", "arith-templates", *arguments], run)
        if done.returncode != 0:
            raise ProofError(f"arith-proof: `lake exe arith-templates {' '.join(arguments)}` failed:\n" + (done.stdout + done.stderr)[-1500:])
    return len(re.findall(r"^case ", TEMPLATES.read_text(), re.M))


def main(argv=None, run=subprocess.run) -> int:
    started = time.monotonic()
    try:
        lake = find_lake()
        lake_build(lake, run)
        cases = check_rendering(lake, run)
    except ProofError as error:
        print(str(error), file=sys.stderr)
        return 1
    print(f"arith-proof: lake build ok (no error, no sorry, axioms audited); templates.txt and FORMULAS.md are what the "
          f"formulas render ({cases} cases); {time.monotonic() - started:.1f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
