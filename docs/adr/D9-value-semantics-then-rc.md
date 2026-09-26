# D9: Move to value semantics, then to a reference-counted runtime

Status: accepted as the direction on 2026-09-24. Stages 1 and 2 and the
value-model components of stage 3 are implemented. The stage 3 default flip
is being validated against its full and performance gates; reference counting
and concurrency remain planned. Each stage ships only after its gate passes.

## Rule

mylang is heading towards the memory model of the Weft design draft
(2026-09-24):

- Every value is independent: assignment, argument passing, stores and returns
  never make two names reach the same mutable object.
- A callee changes a caller's value only through a `mut` parameter, marked
  `mut` at the call site.
- Object graphs are records plus `pool` ids instead of `class` references, so
  the heap is acyclic.
- Memory is reclaimed by reference counting with copy-on-write instead of the
  tracing collector. Arenas remain the bulk-release tool.

Order matters. Reference counting reclaims everything only when the heap has no
cycles, and the heap has no cycles only under value semantics. So the aliasing
model is settled before the runtime changes. Syntax and other surface rules stay
open to experiment. The aliasing model does not, once the runtime depends on it.

## Why

- **Deterministic reclamation.** Memory and resources are released when their
  last owner goes away. That supports scope-bound resource cleanup, no
  collection pauses and lower peak memory (E2b: 0.89× geomean on the parity
  suite).
- **Concurrency.** With value semantics, mutable memory is reachable from one
  task at a time, which is what rules out data races. Reference counting stays
  single-threaded and cheap until a value crosses a task boundary.
- **Removing the GC tax.** Root registration, frame records and safepoints were
  among the largest costs in the performance audits. Reference counting doesn't
  need them.

## Evidence (experiment branches, 2026-09-24)

Plan: `docs/audits/value-semantics-experiment-plan-2026-09-24.md` on
`exp/e2-value-semantics`. Data lives under `experiments/value-semantics-20260924/`
on the branches named below.

- **P1, census** (`exp/e2-value-semantics`): 101 meaning-change sites in 31,311
  lines (3.2 per 1,000). 61 of them involve `class` and 50 are in the Lox port.
  Code written with records and `mut` parameters (standard library, schematic,
  sexpr port, self-host lexer, agent trials: 11k lines) has none. Precision
  about 96% on manual review; recall unmeasured.
- **P2, recorded agent sessions** (`exp/e2-value-semantics`): no silent
  aliasing mistakes in 15 sessions where an agent wrote a mylang program. Six of
  the seven incidents were conservative `E_MUTATION_OVERLAP` rejections. The
  current model isn't visibly hurting agents, so the motivation is the runtime
  and concurrency, not agent error rates.
- **P3, eager-copy value semantics under the GC** (`exp/e2-p3-value-copies`):
  1.80× instructions on QBE and 1.47× on LLVM, dominated by copying read-only
  list arguments. Copies are not a viable implementation.
- **E2b, reference counting with copy-on-write** (`exp/e2b-rc-runtime`):
  - Parity suite: 0.989× instructions and 0.89× peak memory against the GC.
  - Schematic: 1.29× instructions, from count updates on records returned by
    value, which borrow inference removes.
  - Hoisting copy-on-write checks out of loops was essential (1.27× geomean
    without it).
  - `class` and arenas were refused, so object graphs are unmeasured.
- **P4, agent A/B:** passed its rule on 18 of 18 runs in both arms, with no
  wrong answer exiting 0. The value arm took 2.22 repair rounds against 3.11
  for the shared-reference arm, within noise. The kit is at
  `/home/epentland/ai/trials/value-semantics-20260924/`.

## Stages and gates

1. **Confirm agents handle value semantics (P4).** Run the agent A/B with the
   value arm's checker fixed to follow value semantics.
   *Gate:* the plan's rule 1 — the value arm is not worse on first-submission
   correctness beyond the pilot's spread, and has no more wrong answers that
   exit 0. If agents do clearly worse, stop and revisit this record.
2. **Shared compiler analyses on the current runtime.** Last-use/move analysis,
   borrow inference for reads and returned elements, and copy-on-write placement
   with loop hoisting. These also cut GC root traffic, so they pay off before
   the runtime changes.
   *Gate:* the full gate is green, and the parity suite doesn't regress.
3. **Value semantics on the GC.**
   - Collections become independent values, implemented with copy-on-write over
     the existing collector.
   - `class` is replaced by records plus `pool` ids.
   - Every site whose meaning changes gets a diagnostic, with a mechanical
     migration for the repository's own code.
   - Includes a precision fix for `E_MUTATION_OVERLAP`, which P2 found
     rejecting calls that shared nothing.

   *Gate:* the plan's rule 3 (every meaning-changing site diagnosable), and
   parity cost within 1.05× of the pre-stage baseline.
4. **Reference-counted runtime.** Swap the collector for reference counting once
   the heap is acyclic by construction; arenas stay.
   *Gate:* the plan's E2b rule (≤ 1.0× the GC geomean, no program over 1.3×,
   lower median peak memory), now also measured on graph-heavy programs rewritten
   with `pool` ids, such as the Lox port.
5. **Concurrency.** Structured tasks, with atomic counts only on values that
   cross a task boundary.

Each stage merges on its own and can be reverted on its own.

## Rejected alternatives

- **Keep the tracing GC and arenas indefinitely.** It's simpler and handles
  graphs with no redesign, and P2 shows agents cope with it. It was rejected for
  the long term because of nondeterministic reclamation, the GC bookkeeping tax,
  and the cost of a multithreaded collector.
- **Reference counting with today's shared references plus a cycle collector
  (the CPython model).** Rejected because the cycle collector gives back the
  determinism and the freedom from collector machinery that motivate the move.
- **Value semantics implemented by eager copies.** Rejected by P3's
  measurements.

## Compatibility consequence

- **Supersedes the 2026-09-17 aliasing decision** (`class` as a shared
  reference) for the default value model. The old rule remains available for
  one migration release through `--legacy-sharing`.
- **Supersedes D3's tracing-GC clause** once stage 4 lands. The rest of D3
  (managed, value-oriented defaults and opt-in systems tools) is unchanged.
- **Python semantics:** `b = a; b.append(x)` will no longer change `a`. Stage 3's
  diagnostics and documentation must make that visible, because the syntax still
  looks like Python.
