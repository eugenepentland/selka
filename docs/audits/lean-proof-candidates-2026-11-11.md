# Where else Lean proofs would pay (11 November 2026)

The question: is there anything else in the language or the compiler that would benefit from a Lean proof, to find bugs or to
show there are none, the way ownership was verified?

The short answer has three parts.

1. **The proofs work.** Since 8 October the proved parts of the compiler (ownership, facts, integer arithmetic) produced no
   silent wrong result. About 40 silent or unsound defects were found in the same period, all outside them.
2. **The cheapest gain needs no new Lean.** The validators the proofs are about run only in a Debug compiler, and the gate checks
   only debug builds. Projects build with an optimised compiler, so what they ship is not checked.
3. **Five new proofs are worth their cost**, in this order: the IR verifier, the invariant checks of contracts, record moves in
   emission, the task runtime's join, and the keys of the build engine. For the C runtime, the formatter, the parser and
   `mylang fix`, a different tool finds more for less.

Sources: two read-only research agents (one read the four Lean developments and their documents, one read the history since
8 October, 4,541 commits), and the coordinator's own reading of the code. Numbers from the history are one agent's
classification, about plus or minus 25%. Every hour figure below is an estimate, and this week's estimates for agent-built
work ran several times too high.

## 1. How ownership was verified

It is translation validation, not a proof about the Zig code.

- A compiler pass that already computes a table to do its job writes the table down beside the **final** IR: a certificate.
- A small validator that shares no code with the pass re-checks the certificate (checks J1 to J8 for ownership, F1 to F7 for
  facts).
- Lean proves one statement about a Lean copy of that validator: if it accepts, no execution of the program can go wrong in
  the stated way.
- The Zig validator and the Lean one are compared on every certificate the gate writes and on thousands of mutated ones.

So the complicated code (`src/core/own.zig`, 2,822 lines; `src/core/facts.zig`, 2,056) is never trusted. What is trusted is
small and listed: the exporter, the runtime's contracts, LLVM, and that the two validators agree.

## 2. What is proved today

| Development | What it guarantees | Lean lines | Rests on |
|---|---|---:|---|
| `proofs/ownership` | A function the checker accepts never reads or frees dead storage, frees twice, or leaks; whole program, with task groups | 14,680 | trust points A1 to A18, A7.1 to A7.8 |
| `proofs/facts` | Stated integer intervals hold, blocks stated dead are never entered, and a check removed as proven cannot fail | 11,330 | intervals accepted on trust (A6.1 to A6.3), SSA and typing from `verify_ir` |
| `proofs/arith` | The LLVM sequences for division, remainder, shifts, conversions and saturating add compute the mathematical result and trap exactly when they should | 2,640 | LLVM's semantics; formulas compared with the emitter by test |
| `proofs/cache` | A warm build equals a clean one, for an abstract build algorithm, the planner and test admission | 2,371 | every read goes through a recorded handle; the algorithm has no Zig counterpart yet |

Not covered by any of them: the lexer, parser and type checker; what a program means when it is lowered to IR; that the
optimizer's passes preserve meaning; emission other than nine arithmetic operations; the C runtime; how tasks actually run;
capabilities; the stage store and the front-end caches.

## 3. Where the bugs were (8 October to 11 November)

About 180 defects identified; S is a silent wrong result, an unsound acceptance or memory unsafety.

| Component | Defects | S | Found mostly by |
|---|---:|---:|---|
| Build engine, caches, stage store | 34 | 7 | real programs, the cache-read audit, `--verify-cache` |
| Source ownership checker | 35 | 5 | reviews, probes, real programs |
| Certificate validators (Zig) | 13 | 5 | the Lean models and mutants |
| Optimizer passes other than facts | 9 | 3 to 5 | the IR verifier, review |
| C runtime | 7 | 3 | real programs |
| `mylang fix` | 14 | 3 | migrations, review |
| Contracts | 5 | 2 | writing clauses on real code |
| Concurrency | 7 | 2 | one review |
| Capabilities and I/O permissions | 2 | 2 | a real program, review |
| LLVM emission | 6 | 2 | a lane's reasoning, the port |
| Type checking and names | 15 | 1 | the port |
| Lowering to IR | 8 | 1 | real programs |
| Drop placement | 5 | 1 | the ownership validator |
| Standard library in Selka | 2 | 1 | a real corpus |
| Facts | 3 | 0 | generated matrices |
| Lexer, parser, formatter | 5 | 0 | the port |

Three readings of this table:

- **Inside the proofs, nothing silent.** Facts had three defects, none a wrong result. Arithmetic lowering had none. Drop
  placement's one dangerous bug (a double release on a trap path) was caught by the ownership validator.
- **A Lean copy of a checker finds bugs in the checker.** The Lean models exposed about ten holes in the Zig validators before
  any showed up as wrong output. `verify_ir` has no Lean copy.
- **The worst bugs were found by luck or by a real program.** A wrong answer for `return Pair(x=w.y, y=w.x)` had passed 1,518
  conformance programs. A stale stage after an enum payload grew was invisible to `--verify-cache`. A double free in the C
  entry wrapper aborted half of one port's runs.

## 4. Candidates, ranked

### Tier 0: make the existing proofs cover what ships (no new Lean)

- **T0-1. Validate optimised builds.** The Zig validators run only in a Debug compiler or under `--verify-ownership` and
  `--verify-facts-static`. The port and the protobuf library are built with an optimised compiler, so a hole in the source
  checker reaches their binaries unchecked. Measure what the validators cost in an optimised compiler, then either turn them
  on by default or make them part of every project's build. Estimate: 2 to 4 lane-hours to measure and switch.
- **T0-2. Check release certificates in the gate.** Release-mode builds (inlining, stack promotion) are validated only with
  `-Dtest-release=true`, off since 28 October. The theorem therefore says nothing the gate has checked about a `--release`
  binary. This is the user's decision V4 again.
- **T0-3. Count what the fact proof accepts on trust.** A proven addition justified by checks on the edges into a loop
  (`edge-checked`) is counted, not validated, and intervals of record, dictionary and call results are accepted as stated
  (A6.1, A6.3). Report how many removed checks in the port rest on each. Estimate: 2 to 4 lane-hours.

### Tier 1: new proofs, same pattern, in order

- **L1. A Lean copy of `verify_ir`** (`src/core/verify_ir.zig`, 988 lines). Both theorems assume what it checks: every use is
  dominated by its definition, operands have the types their operation needs, and a function value has its type's signature
  (trust point A17). It is the one checker with no Lean mirror, and mirrors have found holes every time. Deliver: the typing
  rules in Lean, a differential on every gate program and on mutants, and the lemma that an accepted module meets the two
  proofs' hypotheses. Estimate: 30 to 60 lane-hours.
- **L2. Invariant checks cannot be skipped.** In two days the compiler was found to skip a record's `@invariant` on `take`,
  `exchange`, `append`, element writes and `mut` calls, and two paths are still open (`match mut` on an option field, a
  computed index). Each was found by listing write paths by hand. Make it a checked property of the final IR: every write
  into a record whose type carries an invariant is followed by that invariant's check before the record is read or
  returned. It needs the invariant's record types written into the certificate, one validator rule, and a short Lean
  lemma. It also gives sealed types (stage S5 of the proof-steps plan) their guarantee. Estimate: 20 to 35 lane-hours.
- **L3. Record moves in emission.** The period's worst bug was a record built from another record's fields in a different
  order: the emitter overwrote a field before reading it. That is the parallel-move problem, and its correctness proof is
  small and standard. Have the emitter write down the move sequence for each aggregate construction and return, validate
  that no move reads a clobbered home, and prove the validation sufficient. Then extend the arithmetic method (Lean formulas
  rendered and compared with the emitter) one operation at a time to the checked forms it leaves out: overflow-checked
  add, subtract and multiply, bounds checks, `int_to_float`. Estimate: 12 to 25 lane-hours for moves, 3 to 6 per operation.
- **L4. The task runtime's join.** The ownership proof leans on one statement about `src/core/runtime/core_tasks.c`
  (551 lines): a group's end returns only after all its tasks finish (A7.5). The model does not run tasks, and the two
  concurrency bugs of the period (a forged handle reaching another thread's group, a race on shared text caches) were found
  by one review, not by a test. Model the submit, help and join protocol and check it exhaustively for small thread and
  task counts, in Lean or a model checker; add typed handles so a forged one is refused. Estimate: 15 to 30 lane-hours.
- **L5. Engine keys.** Seven of the silent defects were a cache serving something a clean build would not, because a key
  missed an input (an enum payload, `T[]` and `T?`, an embedded build product). `proofs/cache` already proves warm equals
  clean, but for an algorithm the Zig code does not yet follow, and under the assumption that the key covers what is read:
  the place the bugs were. Two steps: finish routing every read through the recorded handle (raw reads remain in
  `driver.zig`, `unit_cache.zig`, `tool_identity.zig`, `build_replay.zig`), which is the deferred engine move; and prove the
  type-dependency closure complete over every type constructor, with the Zig walk written so that a new constructor cannot
  be forgotten. Estimate: the closure 10 to 20 lane-hours; the engine move is the larger, already-planned work.
- **L6. Finish what the proof documents already flag.** A14, loans through slots (25 to 40 hours by its own design note);
  A18, frame storage never returned, not modelled; the inner-loop reductions of the fact proof (150 to 250 lines by its
  note); and one place where the Lean ownership checker accepts a constructor the Zig one refuses.

### Tier 2: possible, costly, later

- **Optimizer passes** (`loop_hoist.zig`, `version.zig`, `vector.zig`, `fuse*.zig`, `promote.zig`, `forward.zig`). Nothing
  checks that they preserve meaning; the final-IR certificates only keep them memory-safe. A per-pass witness with a
  simulation proof over the fact proof's machine is feasible for hoisting and versioning, at an estimated 40 to 80 lane-hours
  per family. Do the cheap thing first: build every test program at each optimization level and compare outputs. The gate
  does not do that today.
- **Lowering.** A proof that lowering preserves meaning needs a formal semantics of the source language; that is a
  research project. A narrower model of how a `mut` argument is written back to a nested place would cover the one silent
  lowering bug (two writes into one list).
- **Type-system soundness.** It would prove the design, not the checker, and the final IR is re-checked anyway. Its one
  silent bug (writability not checked in generic bodies never called) is a rule to add, not a theorem.

## 5. Where Lean is the wrong tool

| Area | Why not Lean | What finds more for less |
|---|---|---|
| C runtime (13,760 lines; trusted by A2, A5, A7) | Lean does not check C | Move logic into Selka, where both validators already apply (sort, dictionary, text); bounded model checking of the allocator and size arithmetic; sanitizers and fuzzing for the rest |
| Lowering, passes and emission as a whole | Full proofs are out of reach | A reference interpreter of the typed tree used only as a test oracle, with generated programs; cross-mode output comparison |
| Formatter | The property is a round trip | A property test that formatting is idempotent and preserves the parse; the history review reports one non-idempotent case as seen and not fixed (not reproduced here) |
| Lexer and parser | See section 6 | Grammar-driven fuzzing; the self-hosted lexer and parser, when written, as a second implementation to compare |
| `mylang fix` | The property is "meaning unchanged" | For migrations that only change spelling, require byte-identical emitted code before and after; the exactness tool exists |
| Number formatting | The proof is long and known | Exhaustive comparison over every 32-bit float, random over 64-bit |

## 6. The syntax of the language

The parser is hand-written recursive descent, so it is deterministic by construction: there is no ambiguity for a proof to
rule out. Syntax produced five defects in the period and none was silent. What a proof could add is a machine-readable
grammar that documents the language, and that is better delivered as an executable grammar used to generate test programs
and to compare against the parser. The one syntax property with a reported open defect is the formatter's round trip (section 5).

The properties worth proving about the language's design are the ones already chosen: ownership, and what a contract clause
means. The rule that would extend them is PD1 of the proof-steps plan (no stored `mut` borrows, no capturing closures, no
shared mutable identity, no ambient effects): it is what keeps a function's meaning independent of its callers.

## 7. Recommended order, and decisions for the user

1. T0-1 and T0-3 now: they are measurements and a switch, and they decide how much the existing proofs are worth in practice.
2. L1 (the IR verifier), then L2 (invariant checks). L2 can be the first step of sealed types.
3. L3 (record moves) and L4 (the task join), in either order.
4. L5's closure lemma when the engine move is next scheduled; L6 as filler work.

Decisions:

- **LP1.** Validate every build with an optimised compiler too (T0-1), accepting its compile-time cost once measured.
- **LP2.** Release-mode tests and certificates back in the gate (T0-2; the same decision as V4).
- **LP3.** Which of L1 to L5 to start, and in what order. Recommended: L1, L2.
- **LP4.** For the C runtime: move logic into Selka, or keep it in C and add a bounded model checker to the gate.
- **LP5.** A reference interpreter as a test oracle only. The interpreter was removed from the product on purpose; this would
  bring one back for tests.

## 8. What this audit did not verify

- The defect counts were classified by one agent from commit messages and write-ups; about 15 are guesses, and the true
  total is probably 250 to 350.
- Whether the corpus agreement figures in the proof documents (13,200 functions on 26 October) still hold today.
- The cost of running the validators in an optimised compiler (T0-1 measures it).
- How many removed checks rest on the facts accepted on trust (T0-3 measures it).
- Every hour estimate.
