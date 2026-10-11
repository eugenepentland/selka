# Wave 9 — Shared immutable compiler artifacts

Branch `codex/selka-cache-wave9`, based on Wave 8 commit `8bb95ab0c`.
Main `1d202d41b` is already an ancestor. The primary integration checkout was
left untouched.

Set `MYLANG_COMPILER_SHARED_CACHE` to the same dedicated local directory in
participating worktrees. Each retains its own `--cache-dir` and
`ZIG_LOCAL_CACHE_DIR`. The native compiler uses
`compiler-artifacts-v1/{syntax,typed,program}` independently of Wave 8's
`MYLANG_TEST_SHARED_CACHE` successes. Installation and native use require no
Python.

Ordinary parsed syntax can cross paths; exact source bytes, body start,
compiler/contract and parser authority still match. Qualified ordinary typed
bodies reconstruct references against fresh declarations. Their shared keys
also bind exact merged source/layout and every fresh embedded-input proof.
Only complete concrete requests participate; cold demand requests have no prior
summaries and can share, while warm demand and validation-only requests retain
private behavior. Unproved module origins, generic-template references and
external source proofs miss conservatively. Existing local incremental keys
are unchanged.

Linked programs share only with identical ordered native object bytes and
compatible compiler/toolchain/linker settings. SOURCE_DATE_EPOCH and ZERO_AR_DATE
also enter the private program key, preventing a previously local executable
from being relabeled under a changed shared identity. Existing logical module
paths can share across roots; absolute provenance can cause correct misses.
No source location or string literal is rewritten. Foreign links and
unqualified tools bypass shared programs.

The requesting worktree still checks, lowers and emits before a shared program
lookup. A restored program becomes a verified private executable. The new JSON
`program_shared` flag distinguishes this from a local replay or object-only hit.
Whole-check verdicts, rendered warnings, summaries and mutable indexes stay
private. Enabling sharing does not backfill artifacts hidden behind an existing
private whole-build or verdict replay.

## Storage and lock scope

Records repeat kind/key/length and carry a BLAKE3 checksum, bounded to 128 MiB.
Missing, truncated, corrupted, symlink or special-file records cannot supply a
hit. Configured storage/format failures are explicit, including before private
replay; conflicting valid same-key payloads raise DeterminismMismatch while
preserving the existing record. The native store has no conflict-poison ledger.

Publication stages and hashes before a permanent per-key lock. The lock covers
comparison of a prior record and atomic replacement, never compiler work.
Readers use opened immutable files without publication locks. A directory lock
covers format initialization. Executable publication and materialization use a
64 KiB stack buffer instead of a whole-file allocation; the storage test copies
a 512 KiB payload using a 16 KiB allocator budget.

`--no-cache` and `--verify-cache` suppress shared compiler lookup/publication,
including directory children. Compiler-scoped environment changes preserve the
original guest environment. The existing per-user native object store remains
independent of these controls.

## Qualification

The acceptance matrix is in [PLAN.md](PLAN.md). Focused checks passed:

- Eight actual independent-root native tests, plus one frontend CLI test.
  Receiving caches are empty before sharing assertions. Successful transport
  requires syntax hits, typed reuse, and `program_shared=true` with zero compiled
  units and zero compiler/linker processes. Tests execute the resulting programs.
- Edits/reverts, relevant modes/environment/configuration, same-size embeds,
  literal paths, receiving diagnostics/traps, checksum corruption/refill,
  opt-out/no-cache/verification, concurrent publishers and empty-PATH commands.
- Two syntax tests and three typed tests, including all contract dimensions,
  unrelated declaration edits, standalone-path refusal, embedded-input proofs
  and exclusion of incomplete demand requests. Focused unit totals include the
  seven pre-existing unnamed root test blocks: 9/9 and 10/10 respectively.
- Three direct storage tests, including bounded streaming, InputChanged,
  permanent lock ownership, special files and preservation of unknown formats.
- Five core policy/key tests: native and private linker environment identity,
  compiler suppression, directory guest-environment preservation and configured
  frontend storage errors.
- Existing JSON report compatibility regression: 1/1 passed. The new field is
  appended after the existing fields, preserving the tested report prefix.
- Compiler installation: 14/14 steps and 88 Guardian checks passed.

Complete repository verification passed: all 42 groups selected, 126/126 build
steps succeeded, with stable input snapshots (`verification.log` and
`verification-final.json`). This includes formatting, documentation, the new
cross-worktree matrix and the existing application-recovery coverage.

The first complete gate passed all compiler tests but found an existing process
cleanup assertion race in `scripts/fuzz_coverage_test.py`: the reaped child's
`/proc/<pid>/stat` disappeared between `exists()` and `read_text()`. The helper
now accepts that disappearance as successful cleanup while retaining the live
process check. Its 25-test suite passed, then the full gate passed. The initial
failed gate traceback and summary remain in `verification-initial.log` /
`verification-initial.json`; its complete raw log is retained privately.
An earlier queued snapshot invalidation ran no tests and published no success;
that diagnostic is retained only in private iteration logs.

The successful full gate used installed compiler SHA-256
`c6dd56dde509e28e83852df767cae4ae6b81e3bfed8a6eafb456f7cd0214e718`.
No optional duplicate warm gate was run.
`qualification-summary.json` distinguishes the earlier focused revisions from
the final combined gate. `source-hashes.json` binds the frozen source/docs and
installed compiler used for final verification.

## Boundaries and next stage

No isolated performance measurements or speedup claims were made. A successful
cross-worktree hit avoids native tool processes but still performs validation,
frontend work, lowering/emission, hashing and materialization.

Use trusted cooperative local producers. Checksums detect corruption, not
malicious writers. This disposable namespace has no total retention budget,
online collector, pins/lease protocol, cross-machine claim or application
power-loss durability promise. Clear it only while every user is stopped; never
unlink active permanent locks. Materialized private executables remain usable
after shared eviction.

Wave 10 remains: retain validated graph state to reduce repeated warm validation
and coordinate duplicate concurrent computation. Wave 9's storage alone does
not remove that work.
