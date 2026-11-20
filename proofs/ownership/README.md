# Ownership certificates: the Lean model (package C3)

A Lake project holding the Lean 4 model of `docs/design/ownership-certificates.md`,
the executable checker `certcheck` that reads the compiler's real certificates, and (to be
redone, C3.4) the soundness proof of the checker. **Lean is a developer and
gate tool only.** It is never in the install graph and never spawned from `src/`;
building and using selka still needs only Zig.

## Toolchain (exact versions)

| Item | Version |
| --- | --- |
| `elan` (toolchain manager) | 4.2.4 (`227caca13 2026-08-25`) |
| Lean 4 (`lean-toolchain`) | `leanprover/lean4:v4.35.0` (stable, released 2026-10-12; commit `eb6cafb7290e8bd5f2937522d8d804f58f02bafc`) |
| Lake | 5.0.0 (bundled with Lean 4.35.0) |
| Dependencies | none: core Lean 4 only (no Batteries, never Mathlib); `lake-manifest.json` lists no packages |

### Install commands (Linux, amd64)

```sh
# 1. elan, from the official installer (github.com/leanprover/elan). No profile
#    edits, and no default toolchain: each project pins its own.
curl -sSf -o elan-init.sh https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh
sh elan-init.sh -y --no-modify-path --default-toolchain none     # installs ~/.elan

# 2. put it on PATH for the current shell (elan was installed with --no-modify-path)
export PATH="$HOME/.elan/bin:$PATH"

# 3. build; elan reads lean-toolchain and downloads Lean 4.35.0 on first use
cd proofs/ownership
lake build
lake exe certcheck fixtures        # verdicts for the hand-written fixtures
```

The first `lake build` downloads the pinned toolchain (about 3 GB installed) into
`~/.elan/toolchains`. `lake build` works from a clean checkout of this directory.
`.lake/` (build output) is ignored by git.

## Files

| File | Content |
| --- | --- |
| `Syntax.lean` | the IR fragment by operation class (design §3), the certificate, the export record types, the closing-update sets, the canonical form of a test |
| `Semantics.lean` | heap, small-step execution, faults, the contract of a function (design §6), revised to the real IR |
| `Checker.lean` | `check`, the executable J1-J8 algorithm (design §5): state `(L, D, R, P, G, F)`, solver and recheck |
| `CheckerTests.lean` | executable examples as `#guard`s: accepted shapes of the real corpus, guarded takes, loans, and one or more rejections per check |
| `Parse.lean`, `Render.lean` | the reader of `ownership-certificate-v1` (design §4.1) and a writer used by the tests |
| `Certcheck.lean`, `Main.lean` | the driver: `lake exe certcheck [--explain] [--dump FUNCTION] DIR_OR_FILE`; after its `summary` line it prints the census of the whole-program corollary (`summary corollary: programs meeting every checked hypothesis of the corollary: N of M`) and the call census; `certcheck --link PATH` is the program-level link alone |
| `ParseTests.lean`, `Selftest.lean` | reader tests; `lake exe selftest` compares `certcheck fixtures` with `fixtures/expected.txt` |
| `fixtures-zig/` | the task-group examples with real operation names and their Lean verdicts, for the Zig validator (`selka validate-certificates fixtures-zig`; `GenFixtures.lean` writes it too); `trap-region.cert` holds the cases the Zig validator accepts and Lean rejects, `loans.cert` the cases for loans carried through every consumer; `take.cert` the takes that carry their loans unless marked `noloans` |
| `fixtures-census/` | six small certificate files that pin the census of the corollary (`ParseTests.lean`): two units of one program, one of them leaking; an `emptied` call; a plain program |
| `fixtures/`, `tools/GenFixtures.lean` | certificate files written from the examples of `CheckerTests.lean` (`lake env lean --run tools/GenFixtures.lean` regenerates them) |
| `Facts`, `Invariant`, `Entry`, `InstBase`, `InstGuards`, `InstCtx`, `InstSlots`, `SlotEnds`, `InstPres`, `EdgeBase`, `EdgeStep`, `SoundBlock`, `SoundFacts`, `SoundRet`, `StaticFacts`, `Soundness` | the soundness proof: `check_sound` (see `NOTES.md`, "The proof") |
| `Abandon.lean` | an edge that abandons owners (the `abandon` lines of a trap-region block) preserves the invariant |
| `Link` | the program-level link of the callee tables to the functions they name (`certcheck --link`, C9.2) |
| `ProgramDefs`, `ProgramSite`, `ProgramCall`, `ProgramLink`, `Program` | the whole-program corollary `runs_sound` / `main_no_leak`; a call whose value is an `emptied` record dissolves the callee's result tree (A16) |
| `SoundnessExample.lean` | `check_sound` applied to two concrete functions (the checker accepts them by evaluation in the kernel) |
| `ProgramExample.lean` | the corollary applied to a three-function program with an `emptied` call and a unit call: its tables link, so `runs_sound` and `main_no_leak` apply (C9.4, C9.2) |
| `AXIOMS.md` | the trusted assumptions A1-A19 and A7.1-A7.8 (design §8, §10.5 and the additions) and where each appears in the model |
| `NOTES.md` | the single list for the Zig validator, every definition the design did not give, the proof's structure, the open gaps and the findings from the real corpus |

## Running over the real corpus

```sh
export PATH="$HOME/.elan/bin:$PATH"
cd proofs/ownership
lake build
lake exe certcheck --explain /path/to/corpus-debug     # one verdict line per function, then a summary
lake exe certcheck --dump 'path::basename' FILE        # the entry states the solver proposed
```

`certcheck` exits 0 when every function is accepted or `unchecked`, 1 when one is rejected and
2 for a usage error or a malformed file.

## What the theorem does not cover

The slot-level end of a loan (A14), views written before the take that owns their storage (A15) and a
`noloans` mark on a take and a view into itself (A13) are checked, not covered; see
`AXIOMS.md` and `NOTES.md` ("Open gaps"). J7 (stack escape), the task groups of C6 and the loans of
every owned value (a cell held by a live tree is not destroyed before its holder; `Fault.lentGone`)
are covered.

Leaks are covered, relative to A1. `main_no_leak` (`Program.lean`) proves that an accepted program leaves
nothing allocated, and J2 `ret-live` rejects an owner still live at a `ret`. Both rest on `Xform`, which
destroys every tree an instruction consumes, or moves it into the result tree. A1 trusts the operation
table to say what the emitter does, and the model does not check the table's per-state conditions. One of
them is the Construct row of design §3: a constructor's result is borrowed only when nothing is consumed.
The emitter lays a borrowed record (1A) over its lent fields and never drops it, so it destroys nothing it
consumes. The Zig validator checks that condition (J1 `consumesNothingOwned`). Lean's `classOk` allows
`borrowed` for any `Construct`. So a borrowed constructor that consumes a fresh owner beside a borrowed
field is rejected by Zig (J1). Lean accepts it, because in the model the constructor destroys the owner it
consumes. At run time that owner would leak. The Zig rule is the one the design states. The disagreement
is a gap in what Lean checks of A1, not a fault of either checker on its own terms. The lowering never
emits this shape: every managed field of a borrowed record is lent. Because the gate's `ownership-proof`
fails on any fixture the two checkers judge differently, the shape is not a validator fixture. Lane O2
found it (D-O2-12), and lane G confirmed it on 6 November 2026 (`experiments/cert-check-20261106/DECISIONS.md`, D-G-2).

The construct-read rule (J6 `construct-read`, lane VAL) is checked and not covered. Both checkers refuse a constructor
whose result is owned or `emptied` and that reads a borrow rooted outside the owners it consumes, unless an owned result
lists it as a loan (`constructReadOk`). The model gives every take a fresh tree (NOTES.md item 13), so it cannot show the
fault the rule prevents: lane FX6's plan, an `emptied` item record whose take handed a dictionary's key out as an owner,
freed the keys twice at run time and is no fault of the model. The theorem is proved of the stricter checker with no new
`sorry`, axiom or assumption; it does not use the check.

## Speed

`certcheck` checks a corpus of about 10,700 functions in about 4 s on one core (the largest function
in 0.04 s) and checks the files of a directory in parallel on the runtime's thread pool
(`LEAN_NUM_THREADS`).

## Status

C3.3b (the model revised to the compiler's real IR), C3.5 (`certcheck` over the real corpus),
guarded takes and loans, C3.4 (`check_sound`), C3.4b (`runs_sound`, `main_no_leak`) and C3.6 item 1
(J7) are done, with only the standard axioms.
