# Ownership certificates, a small validator and a Lean model (plan, 2026-10-26)

**Status:** draft for approval. Nothing is implemented. Claude runs it after approval:
Sonnet 5.5 lanes for the compiler and the proofs, Haiku lanes for the corpus sweeps and
the documentation, and Claude integrating, gating and landing.

**What it is for.** The ownership rules work of 24–25 October (`docs/ownership-rules.md`,
`src/ownership_rules.zig`) made the rules explicit. Every refusal now names one of the 54
rules, Core alone decides moves and loans, every move is spelled `own`, and borrow sets
are in signatures (`-> T from p`). Nothing yet *proves* that a program the compiler
accepts is memory-safe; the evidence is the test suites, the leak check
(`MYL_CORE_LEAKCHECK=1`) and the sanitizer runs. This plan adds that proof, for each
compiled program, without trying to prove the 7,000 lines of ownership code in
`src/core/single_owner.zig` and `src/core/own.zig`.

**Inputs.**
- `docs/ownership-rules.md`: the 54 rules and their layers (Frontend, Core, both).
- `docs/design/new-core-s1.md` §6: ownership states, consuming uses, drop insertion,
  phis, traps.
- `src/core/ir.zig`: 106 operations, SSA with immutable values, and
  `ParameterPassing` and `BorrowContract` on signatures.
- `src/core/own.zig`: the pass that turns checked ownership into `drop`s and
  consuming transfers.
- `src/core/verify_ir.zig` and `src/core/pipeline.zig` (`checksIr`): the precedent of a
  verifier that runs in Debug compilers and under `--verify-facts`.
- Lean 4 is not installed on this machine (no `lean`, `lake` or `~/.elan`).

## 1. What the plan proves, and what it does not

**Proved, for every function the validator accepts:** in the IR the emitter lowers,
- no value is used after it is moved or destroyed;
- no owned value is destroyed twice, and every owned value is destroyed or transferred
  exactly once on every path that returns normally;
- a borrowed value, including a slice or string view, is only used while every owner
  it borrows from is still live;
- a borrowed parameter is never destroyed or taken by the callee;
- a borrowed return names, in its `from` contract, the parameters it borrows from;
- a call never takes an argument it also borrows, in another position of the same call
  (rule M5).

With every function of a program validated, the whole program has these properties
(a corollary by induction over calls, each callee trusted for its signature).

**Trusted, not proved:**
- the table that says what each IR operation does to ownership (§3.1);
- the runtime's destruction (`core_rt.c` frees a value and the managed children it
  owns);
- LLVM emission and LLVM itself;
- the Zig validator being the same function as the Lean checker. A differential test
  covers this, not a proof (§5).

**Not in this plan:**
- proving the source rules or the front end;
- task loans (K1–K3), which are stage 2 (§7, C6);
- integer, bounds and other runtime traps, which stay runtime checks;
- functional specifications of guest code (`mylang verify`, step 5 of the 24 October
  advice);
- trapping slices (step 2b), a separate small change with a `mylang fix` migration.

Traps run no destruction (RC-TRAP-TEARDOWN-1). The process exits, so a trap path is
allowed to end with owned values live.

## 2. The trust split

```
typed program ──single_owner.zig (54 rules, refusals)──▶ Core IR
Core IR ──own.zig + release passes──▶ final IR + certificate      (untrusted, large)
final IR + certificate ──validator (small, independent)──▶ accept / reject
Lean: checker (same algorithm) + soundness theorem                 (proved)
gate: Zig validator verdict == Lean checker verdict on the corpus  (tested)
```

The large passes find a schedule of moves and destructions; the validator only checks
it. A wrong schedule from `own.zig` becomes a rejected build in the gate instead of a
use-after-free at run time.

## 3. The certificate

### 3.1 Operation classes (trusted table)

`src/core/ownership_ops.zig` gives every `ir.Op` an ownership class through an
exhaustive `switch` (a new op will not compile without one):
- which operands it **reads** (they must be live);
- which it **consumes** (they die here);
- what its result is: a scalar, a **fresh owned** value, or a value **borrowed from**
  named operands;
- for `call` and `call_indirect`, the callee's `ParameterPassing` and `BorrowContract`
  decide per argument.

Examples:
- `list_new`, `record_make` and `list_copy` produce fresh owned values;
  `record_make` consumes its managed fields.
- `list_get` of a managed element and `record_get` of a managed field produce values
  borrowed from the container.
- `str_view_of`, `list_view_of` and `list_slice_view` produce views borrowed from
  their source.
- `drop` consumes.
- A value-returning update such as `list_push` or `record_set` consumes its input and
  produces a fresh owned value. Whether storage is reused in place is the emitter's
  choice; it is safe because the input is consumed.
- `ret` consumes its operand when the result is owned, and reads it when the result is
  borrowed.

This table is the semantic interface between the compiler and the proof. It is
reviewed line by line (C1 exit) and exported verbatim into every certificate file.

### 3.2 What a certificate states

Per function instance (generic instances separately, after every pass, immediately
before LLVM emission):
- the state of each managed SSA value: `owned`, `stack` (owned, on the stack, must
  never escape) or `borrowed(owners)`, with the owner values it borrows from;
- for each parameter, its state from the signature: `owned` when `ownedAt` or
  `consumesAt`, otherwise `borrowed` from the caller;
- for the result, `owned` or `borrowed(from parameters)` from `BorrowContract`;
- for each phi, its state: `owned`, or `borrowed` with the union of its operands'
  owners (rule V5).

`own.zig` already computes all of this. It writes it down instead of discarding it.
Consumption events are not stated: the validator derives them from the IR and the
table.

### 3.3 Export format

`mylang dump-ir FILE.my --certificate` and `mylang build … --emit-certificates DIR`
write a versioned text format (`ownership-certificate-v1`):
- the operation-class table;
- per function: blocks, predecessors, each instruction reduced to its class and
  operands, and the state annotations.

It is deterministic (byte-identical across runs) and is what the Lean checker reads.

## 4. The validator (Zig, `src/core/validate_ownership.zig`)

**Independence.** It imports only `ir.zig`, `ownership_ops.zig` and the certificate
types. A test fails if it imports `own.zig`, `single_owner.zig` or any of their
helpers, so a bug cannot be shared through common code.

**Algorithm.** One forward dataflow per function over the reachable CFG. Each block
carries the set of live owned values. A join requires the same set on every incoming
edge, which is how rules B5 and B6 (joins and loops) appear at the IR level. The
checks, each a numbered judgment that the Lean model states identically:
- **J1 Classification:** every value's stated state agrees with its defining
  operation's class and with the signature.
- **J2 Exactly once:** an owned value is consumed exactly once on every path to `ret`.
  At `ret`, nothing owned is live except the returned value. `unreachable` ends a path
  with any set.
- **J3 No use after consumption:** every operand use is at a point where its value is
  live.
- **J4 Borrow lifetime:** at every use of a borrowed value, all its owners are live,
  transitively.
- **J5 Borrowed values are not taken:** a borrowed value is never consumed. It may be
  returned only when the result is borrowed and its owners are within the result's
  `from` parameters.
- **J6 Disjoint call arguments:** an argument consumed by a call is not also an
  argument, or an owner of an argument, that the same call borrows.
- **J7 Stack values stay put:** a `stack` value is never returned, stored or passed to
  an owned position.

**When it runs:**
- always in a Debug compiler, as `verify_ir` does today (`checksIr` in
  `pipeline.zig`);
- under `--verify-facts`, and so in the gate's release run;
- under a new `--verify-ownership` on `build`, `run` and `test` for ReleaseFast
  compilers.

A rejection is an internal compiler error (exit 2). It names the function, block,
instruction, the judgment and the nearest source rule, and it is never a user
refusal. Validation is part of the cache key of a unit object, so a cached unit
compiled without validation is never reused under it.

**Cost target:** at most 3% of a debug build's compile time with validation on, and
nothing with it off.

## 5. The Lean model (`proofs/ownership/`, a Lake project)

**Toolchain.** A pinned `lean-toolchain` (current stable Lean 4 at the time C3
starts), core Lean and Batteries only, no Mathlib, so a proof check builds in
minutes. Lean is a developer and gate tool, under the same rule as Python: never in
the install graph, never spawned from `src/`. Building and using mylang still needs
only Zig.

**Files:**
- `Syntax.lean`: the IR fragment by operation class (§3.1): values, blocks, phis,
  calls with passing conventions, `drop`, `ret`, branches, `unreachable`.
- `Semantics.lean`: small-step execution over a heap of allocations. A destroyed
  allocation is gone. Reading or destroying one that is gone, or destroying a
  caller's borrowed allocation, is a stuck state named `fault`. Calls follow their
  signature contracts (assume-guarantee).
- `Checker.lean`: `check : Function → Certificate → Bool`, the J1–J7 algorithm of
  §4, written as an executable function.
- `Soundness.lean`: if `check f c = true`, no execution of `f` from a heap that
  satisfies its parameter states reaches `fault`. At every normal `ret`, each
  allocation `f` owned is destroyed exactly once or is the owned result. Then the
  whole-program corollary.
- `Main.lean`: `lake exe certcheck DIR` reads `ownership-certificate-v1` files and
  prints one verdict per function.

The theorem statement is fixed at C0 and reviewed before any proving starts. The
proof may use only the axioms listed in `proofs/ownership/AXIOMS.md` (the destruction
behaviour of the runtime, nothing about the checker). A `sorry` fails the build.

**Tying Zig to Lean.** A gate action exports certificates for the whole corpus and
runs both the Zig validator and `certcheck`. The verdicts must agree on every
function, and so must the rejections on every fault-injected variant (§6, C4).

## 5a. What it costs the development cycle (budgets, measured at C2 and C4)

| Loop | What runs | Budget |
| --- | --- | --- |
| Writing guest code with a ReleaseFast compiler (`check`, `build`, `run`, `test`, `fix`) | Nothing, unless `--verify-ownership` is given | 0 |
| Compiler edit loop (`zig build --watch`, focused tests) | The Zig validator inside each guest build a Debug compiler makes | ≤ 3% of guest compile time |
| Complete gate after a `src/` edit | The validator in every guest build, plus `ownership-proof` | ≤ 15 s wall added when few programs' final IR changed; ≤ 60 s when all did |
| Complete gate after a validator or `proofs/` edit | `lake build` of the model; the Lean checker on every function | ≤ 3 min |
| Complete gate with nothing changed | All reused | 0 |
| Peak memory of a guest compile with the validator on | The validator's state, freed with each function | ≤ 25% added to the compile's own peak (EDA stage 2 `eval_design_block_test.my` stays under about 1.7 GB, against 1.35 GB without) |
| EDA and selka | Not in the gate; swept at C2's exit and on request | n/a |

How `ownership-proof` stays inside its budget:
- It does not lower anything itself. The `test-lang` build writes each program's
  certificates as it compiles them, so no second lowering pass is needed.
- Verdicts are kept per function, keyed by the certificate's digest and the checker's digest, in the namespace
  `ownership-verdicts-v1` of the per-user verification store (C4.6), so every worktree and session shares them. After a
  compiler edit only functions whose final IR changed are checked again, by both Zig and Lean, and a new worktree pays for
  none of the functions an earlier gate checked.
- Each certificate directory is stamped with the compiler and the suite that wrote it (C4.6), because `mylang test` writes
  a program's certificates only when it builds the program and a test served from a receipt builds nothing. A directory with
  another stamp is emptied and rebuilt with `--force` (about 20 s for all six).
- `lake build` reruns only when a file under `proofs/` changes.
- The Lean checker had a size cap of 100000 bytes of certificate text (C4.5), because four functions of about 180 KB took
  57 to 128 s each. Lifted on 26 October: the fast checker (C3.7) takes 0.04 s on the largest function and about 4 s on
  the whole corpus, so the cap is off by default (`--lean-cap-bytes 0`).
- The checkers run in batches, the largest functions first and alone, in as many processes as the admission slot allows
  CPUs (at most 16).

**Measuring.** C4 times four cases on the complete gate, and the peak memory of the largest guest compile of the corpus with and
without validation (a counting-allocator test, `validate_ownership_memory_test.zig`, pins the validator's own bytes):
- a comment-only `src/` edit;
- an edit to `own.zig`;
- an edit to IR construction that changes most programs;
- an unchanged rerun.

**Measured at C4.5 and C4.6** (26 October, the complete gate on the C4 branch; the action's own time, then the whole gate; the
edited gates that fail do so in `core`, whose tests pin IR shapes the synthetic edits change on purpose, not in `ownership-proof`).
C4.5's first table was taken on a certificate directory that held stale certificates (C4.6 found the hole) and is replaced:

| Case | Functions checked (Zig / Lean) | `ownership-proof` | Gate | Budget |
| --- | --- | --- | --- | --- |
| Comment-only `src/` edit | 0 / 0 | 6.3 s | 128.2 s | 15 s |
| `own.zig` edit, 15 functions change | 15 / 15 | 1.2 s | 150.9 s | 15 s |
| IR-construction edit, 6536 of 9140 change | 6536 / 6529 (7 skipped for size, 1206 KB) | 46.9 s | 165.5 s | 60 s |
| Validator source edit (comment) | 9140 / 0 | 29.2 s | 118.5 s | 3 min |
| `proofs/` edit | 0 / 9140 | 148.2 s | 183.7 s | 3 min |
| Edit, build, revert, then edit `proofs/` (stale directories rebuilt) | 0 / 9140 | 130.0 s | 170.6 s | 3 min |
| First gate in a new worktree (verdicts shared) | 0 / 0 | 17.0 s | 112.5 s | n/a |
| Same action on an empty private store | 9140 / 9140 | 122.7 s | n/a | n/a |
| Unchanged rerun | none | not executed | 16.9 s | 0 |

The gate's wall time moves by 20 to 30 s from run to run with the load other agents put on the machine; the Lean checker's
long pole is the one function that takes 128 s alone. A validator edit made while the store holds no Lean verdict for the
four large functions (their certificates changed and no full run has happened since) costs up to 179 s: the first full run of
a checker is the 120 to 150 s of those functions plus the Zig side. Before the cap and the batching fix, the same all-change
edit cost 142 s and the `proofs/` edit 147 to 172 s.

Peak memory of the action (the driver and every checker process it has running at once, sampled every 0.1 s): 125 MB when it
checks nothing; 206 to 244 MB when it checks thousands of small functions (19 processes; the driver holds 125 MB of certificate
text); up to 500 MB when the Lean checker works on the four large functions at once. The validator inside a compile adds
0.3% to 0.6% to the compile's peak (EDA stage 2: 785 MB against 783 MB).

**If a budget is missed.** Decided on 26 October when the all-change case took 142 s: the size cap above, a `proofs` profile
(`verify_cache.py --profile proofs`: the complete gate plus an uncapped run of the action's driver), run before landing a
change to `own.zig`, the validator, `ownership_*` or `proofs/`, and a full Lean run whenever a checker changed. The
validator itself stays in the gate.

## 6. Evidence the validator is not vacuous

**Fault injection** (`src/core/validate_ownership_faults_test.zig`). For every
function of a fixed corpus, mutate the final IR or certificate in eight ways:
- delete a `drop`;
- duplicate a `drop`;
- move a `drop` above a later use;
- consume a borrowed parameter;
- destroy an owner while a view of it is live;
- mark a borrowed argument consumed;
- return a borrowed value outside `from`;
- let a `stack` value escape.

Each applicable mutation must be rejected. Every class must be rejected at least
once, and no mutant may be accepted.

**Clean corpus.** The validator, with zero rejections, runs over:
- `tests/lang`, `tests/value_semantics`, `tests/ported`;
- the `test/core` fixtures, `benchmarks/` and `examples/`;
- EDA stage 1 and stage 2;
- selka.

Any rejection there is either a validator defect or a real `own.zig` defect. A real
defect gets its own fix and test before the package exits.

## 7. Packages

| Package | Work | Exit | Estimate |
| --- | --- | --- | --- |
| **C0** | `docs/design/ownership-certificates.md`: the operation classes, the states, J1–J7 as inference rules, the theorem statement, and for each of the 54 rules whether it is a safety rule this proof covers, a source-clarity rule (`own` markers, M3 call markers, C1 written copies) or a type rule. | Claude reviews it; the theorem statement is fixed. | 3–5 h |
| **C1** | `ownership_ops.zig` (exhaustive table); `own.zig` and the release passes keep the certificate data; `dump-ir --certificate`; `--emit-certificates`; format v1. | Every function of the clean corpus exports; byte-identical across two runs; table reviewed line by line. | 8–14 h |
| **C2** | `validate_ownership.zig`, its wiring in `pipeline.zig`, `--verify-ownership`, the independence test, the fault-injection suite, cost measurement. | Zero rejections on the clean corpus; every fault class rejected; the validator within §5a's 3%; complete gate passes. | 10–16 h |
| **C3** | The Lean model: syntax, semantics, checker, soundness, `certcheck`. | `lake build` with no `sorry`; only listed axioms; the theorem matches C0. | 20–40 h, the largest risk |
| **C4** | Gate action `ownership-proof`: `lake build`, Zig vs Lean verdicts on the corpus certificates `test-lang` writes and on the mutants, per-program verdict reuse keyed by certificate digest; registered in the verification inventory with declared inputs. | Complete gate passes with it; the four §5a cases are within budget; an unchanged rerun reuses it. | 6–10 h |
| **C5** | Docs: a "Proved by" column in `docs/ownership-rules.md`, `--verify-ownership` in the native-build guide and CLAUDE.md, a report with the measurements. | Doc gate passes. | 2–4 h |
| **C6** (stage 2, separate approval) | Task loans K1–K3: a loan held until the group joins, in the table, the validator and the model. | As C2–C4 for programs that use `parallel`. | 12–24 h |
| **C7** (stage 3, after stage 1) | Fact certificates (§7.1). | Every `proven` check and every `!range` in the clean corpus validated; Zig and Lean verdicts agree; fault classes rejected; within §5a's budgets. | 28–50 h |
| **C8** (stage 3, after stage 1) | Arithmetic lowering lemmas (§7.2). | Each formula proved; a test pins the emitted sequences to the proved ones. | 6–12 h |
| **C9** (stage 4, after C3.8 and C7 land; not started) | Proof-friendly Core IR (§7.3): make explicit in the IR what the checkers now reconstruct or assume. | Each part deletes the special cases and assumptions it names, in Zig and in Lean; corpus, EDA and selka at 0 rejects; §5a budgets met; guest runtime unchanged. | 45–80 h |

Stage 1 is C0–C5, about 50–90 agent hours. C6–C8 start only after stage 1 lands.

A related track, a provable build cache (packages K0–K5), is planned in
`docs/audits/provable-cache-plan-2026-10-26.md`. It shares this plan's Lean project,
gate wiring and tracker.

### 7.1 Fact certificates (C7)

In a release build, `src/core/facts.zig` computes:
- an integer range for every value, refined by the branches that guard it;
- list lengths for counted fills;
- loop reductions.

It then marks checks `proven`. The emitter drops their guards and emits `nsw`/`nuw`
arithmetic, unsigned division and `!range` metadata, so a wrong fact is an
out-of-bounds access or LLVM undefined behaviour that appears only in release
builds. Today `--verify-facts` checks the facts at run time, but only on the
inputs the tests run. C7 makes this a check of every compiled program, reusing C1–C4.

| Part | Work | Estimate |
| --- | --- | --- |
| C7.1 | The certificate: each value's range, each list-length and reduction fact, and the reason each check is `proven` (the operand ranges or the guarding branch) | 6–10 h |
| C7.2 | Validator `validate_facts.zig`, independent of `facts.zig`. Each range follows from its operands' ranges and the dominating branch edge. A loop's stated range survives one more trip (an inductive check, no fixed point). Each `proven` check follows from the ranges, and so does each `!range`. | 8–14 h |
| C7.3 | Lean: the integer semantics of the checked, wrapping and proven forms; soundness of every transfer rule and of the loop rule; the theorem "a `proven` check never fires and every `!range` holds", mostly by `omega` | 10–20 h |
| C7.4 | Fault injection (widen or narrow a range, drop a branch refinement, mark an unjustified check), corpus sweep, the facts half of `ownership-proof`, and cost | 4–6 h |

### 7.2 Arithmetic lowering lemmas (C8)

Python floor division and remainder, checked shifts, `convert`, `float_to_int` and
`saturating_add` are lowered to LLVM sequences with sign fix-ups.

| Part | Work | Estimate |
| --- | --- | --- |
| C8.1 | Write each emitted sequence as a formula, from `emit_llvm` | 1–2 h |
| C8.2 | Lean proofs that each formula equals the operation's integer specification | 3–6 h |
| C8.3 | A test that pins the emitter's sequences to the proved formulas | 2–4 h |

**Lanes after C0:**
- C1 → C2 run on one branch.
- C3 starts as soon as C0 is fixed, because it depends on the classes and judgments,
  not on Zig code.
- C4 waits for C2 and C3.

### 7.3 Proof-friendly Core IR (C9)

Added 2026-10-26 after C3.8 and C7.3. The language's rules (`own` and `mut` markers,
no closures, no aliasing through methods) are what made the ownership proof possible.
Almost every special case the lanes met came from the lowering instead: the checkers
reconstruct something the front end knew, or assume something the IR does not say.
C9 makes those things explicit, so the validators get smaller and the assumptions in
`proofs/ownership/AXIOMS.md` and `proofs/facts/AXIOMS.md` shrink.

| Part | Work | Removes | Estimate |
| --- | --- | --- | --- |
| C9.0 | Measure before building. Count, on the corpus, EDA and selka: trap-only blocks and the values live into them; `emptied` call results (1,041 on the corpus at C6.1); forward takes; `phi(owner, undef)` cleanup phis; reduction phis behind an inner loop. Rank C9.1–C9.8 by what each count says. | Guesswork in the order below | 1–2 h |
| C9.1 | **Trap paths say what they abandon.** `own.zig` releases nothing on a path to `unreachable` (`own.zig` ~610), so the edges into a trap block disagree about what is live. The `unreachable` terminator (or the edge into a trap block) lists the owners the path abandons; the certificate states it. Every block then merges like any other. | Zig: `trapOnly`, the trap meet, `trap-group`/`trap-holder` and the chain rules. Lean: the trap shadow and its deviations. These were the source of both real validator holes of C3.8, five Zig/Lean deviations and the C2.7 out-of-memory case. | 8–14 h |
| C9.2 | **Calls name their callee in the certificate,** with the callee's parameter kinds and result kind. | **done 2026-10-26** (main 7a1a09382): a per-function callee table, the site checks in both checkers and a program-level link; CallWf is derived, not assumed; a void call is covered. The audited census: 632/632 gate, 139/139 EDA, 86/86 selka programs meet every hypothesis or a numbered assumption (A17 new). Certificates +7.1% (gate), +8.0% (EDA) | 3–6 h |
| C9.3 | **Small exporter facts.** Which constructor operand fills which field, so a loan can end on one field; `noloans` on takes, if C3.8 has not already landed it. | started after C9.2 (A14, field-level loan ends), with a stop if the model change outweighs the 6–18 constructors per corpus | 2–4 h |
| C9.4 | **`mut` write-back as its own IR form.** A function with `mut` parameters returns a record of its result and write-back parts (`build_fn.zig`), which the caller empties at once (`own.zig`, `emptied`). A multi-result call, or a write-back operation, says this directly. Includes a runtime check on the parity suite, because it touches the call ABI. | The `emptied` state's constructor special cases (entries 28, 41), CallWf's `noEmptied` hypothesis | 8–14 h |
| C9.5 | **Task groups as IR operations.** `group_begin`, `group_lend` and `group_join` replace `box_make` with the lent flag and the `myl_core_owned_group_*` calls (`build_parallel.zig`, `build_task.zig`), with rows in the operation table; the emitter lowers them to the same runtime calls. | Name-prefix recognition; A7.5 narrows to "the runtime join waits for its tasks"; the lent-to bit becomes an operation's effect | 6–10 h |
| C9.6 | **Loop annotations for facts.** The front end records the counter, start, bound and step of each `for … in range(...)` loop; `facts.zig` uses them, the fact certificate states them, and `validate_facts.zig` checks them instead of finding counted loops from dominators and latches. | Loop rediscovery in both fact checkers; most of A6.2 (reductions behind an inner loop); cases like `json_roundtrip::parse_number` if C9.0 shows they are loops of this kind | 6–10 h |
| C9.7 | **Cleanup phis without `undef`** (conditional on C9.0). Replace `phi(owner, undef)` with an explicit maybe-moved flag or drop. Design first: the cost and the emitted code must stay the same. | Part of A3 (undef); the cleanup-phi case of entry 18 | 6–10 h |
| C9.8 | **Language: one call may not pass a place both `mut` and read-only** (conditional on C9.0 and on the user's approval, since it refuses accepted code). `lists.extend(mut rows[0], rows[0])` becomes an error whose `mylang fix` edit writes `copy(rows[0])`, with a `FIX-MIGRATION` corpus. | Forward takes (entry 29) and A15 | 4–8 h |

**Order.** C9.0 first; then C9.1, C9.2 and C9.3, which are small and remove the
most; then C9.4, C9.5 and C9.6; C9.7 and C9.8 only if C9.0 shows they matter. Each
part lands on its own: compiler change, Zig validator, Lean model and the fixtures
that pinned the old behaviour move together, behind a passing complete gate.

**C9.0 result (2026-10-26, `experiments/c9-measure-20261026/REPORT.md`).** Counted on
the gate corpus (6,659 functions), EDA stage 2 (6,162) and selka (2,502). The order
and scope change as follows:

| Part | Finding | Decision | Revised estimate |
| --- | --- | --- | --- |
| C9.4 | `emptied` call results in 26% of gate programs, 73% of EDA's, 80% of selka's; the whole-program corollary excluded them all (`noEmptied`) | **done 2026-10-26**: option (b), a Lean semantics that dissolves the returned record, with no compiler change (the IR form was costed at 50–80 h with call-ABI risk). No program is now excluded by an `emptied` call (632/632, 140/140, 86/86 have every function accepted); programs with a call of a unit program function stay outside until C9.2 (`CallWf.dst`, found in C9.2's review); new documented assumption A16; design entry 56; `docs/design/c9-write-back.md`. Entries 28 and 41 stay; entry 48's last clause and the "Outside the corollary" paragraph went. | about 5 h |
| C9.1 | trap-only regions in 1,033 / 1,550 / 182 functions; edges that disagree in only 61 / 16 / 0 blocks; certificate growth under 0.25% | **done 2026-10-26** (main f96da6281): abandon lines on edges into the trap region; the trap meet and its rules are gone from Zig, TrapShadow.lean and about 550 more lines from Lean; release LLVM byte-identical | 8–12 h |
| C9.9 (new) | 160 of 168 forward-take views are never read: the lowering emits a dead view before the take; the other 8 are views of a call's written-back part | **done 2026-10-26** (main 226855429): forward takes 73 -> 8 (gate), 31 -> 7, 53 -> 32 (EDA); binaries byte-identical. The rest have a call or check between view and take; removing them would change trap order, so entry 29 and A15 stay | 3–6 h |
| C9.2 | program calls 51–68% of calls, runtime calls 31–48%; certificate +2–4% with a callee table | **do, after C9.1** | 4–7 h |
| C9.3 | 6–18 constructors per corpus affected | later, optional | 2–4 h |
| C9.5 | 38 lends, all in 3 test programs; none in EDA or selka | dropped for now | — |
| C9.6 | the counted-loop pattern already finds 92% / 86% of loops; the 14 assumed reductions need a Lean induction, not a bound | dropped | — |
| C9.7 | 16 phis, all in `tests/lang/owned_field_moves.my` | dropped | — |
| C9.8 | the source has 4 call sites in 2 files; entry 29's example no longer makes a forward take | dropped; not proposed to the user | — |

Recommended parts total 27–43 h. C9.0 also found that plain `mylang dump-ir FILE`
segfaults on EDA, the selka mains and 13 of 324 gate test modules (the certificate
flags work); that is a separate bug, outside C9.

**Hard stops for C9** (in addition to §11): any change in a guest program's output
or exit status; a release-build runtime regression above 1% on the parity suite;
C9.8 before the user approves it.

## 8. How the lanes run

- **Agents:**
  - **Sonnet 5.5 lane 1:** C1, then C2, in one worktree.
  - **Sonnet 5.5 lane 2:** C3, in its own worktree, touching only `proofs/`.
  - **Haiku lanes:** the clean-corpus sweeps (EDA, selka), fault-injection
    bookkeeping, and the C5 documentation.
  - **Claude:** writes C0, reviews every package, runs the complete gate and lands.
- **Branches:** each package lands on main only after Claude's review and a passing
  complete gate. The usual rules apply: claimed worktrees, `TMPDIR` on disk, no
  pushes.
- **Measurements:** compile-time costs use a ReleaseFast compiler and
  `scripts/build-slot.sh timing`.
- **Stop rule for C3:** if a lemma makes no progress in two consecutive working
  sessions (about 4 h), the lane stops and reports the stuck lemma and what it
  tried. Claude then decides whether to change the model, restate the lemma, or
  move the lane to Opus.

## 9. Decisions

| # | Decision | Recommendation |
| --- | --- | --- |
| D1 | **What is proved.** A validator checks each compiled function; Lean proves the validator's algorithm sound; a differential test ties the Zig validator to the Lean checker. The alternative, proving `own.zig` itself correct, is several times larger and would have to be redone for every change to the pass. | Validator plus proof. |
| D2 | **Lean on this machine.** Install elan with a pinned Lean 4 and Batteries, with no Mathlib, as a developer and gate tool. The complete gate gains `ownership-proof`, which fails when Lean is missing rather than skipping. The alternative is a separate `proofs` profile outside `complete`. | In `complete`, failing when Lean is missing. |
| D3 | **Scope of stage 1.** Sequential ownership: moves, destruction, borrows, views, borrowed returns, stack values and resources as ordinary owned values. Task loans (K1–K3) come later as C6. | As stated. |
| D4 | **When the validator runs.** Always in Debug compilers and the gate, and behind `--verify-ownership` for ReleaseFast compilers. A rejection is an internal error, never a user refusal. | As stated. |
| D5 | **Staffing.** Sonnet for C1–C4, Haiku for sweeps and documentation, Claude integrating. The C3 stop rule hands a stuck proof back to Claude rather than letting the lane spend hours. | As stated. |

## 10. Risks

- **The operation table is wrong for some op** (for example, a field read the table
  calls borrowed, while the emitter moves it). Mitigations: the table is reviewed
  line by line, the clean corpus runs under the leak check and ASAN too, and the
  fault suite includes field moves.
- **`own.zig` cannot state a borrowed value's owners in some case** (borrow chains
  through phis of views). The certificate may then mark the function `unchecked` with
  a reason. The validator counts such functions, and C2's exit requires that count to
  be zero on the clean corpus or each case to be explained and listed. An unchecked
  function never counts as validated.
- **The proof is harder than estimated**, mostly the phi and loop cases of J2. The
  C0 theorem keeps the model small (operation classes, not 106 ops). The stop rule in
  §8 bounds the cost.
- **Cost in Debug compilers:** if validation exceeds 3% of a debug build, it moves
  behind `--verify-ownership` for Debug compilers too. The gate keeps it on.

## 11. Hard stops (report and wait for Claude)

- A real `own.zig` defect that the fix would make visible to users: a program that
  ran before now refused, or output that changes.
- The clean corpus shows a rejection that is neither a validator defect nor fixable
  within the package.
- The Lean theorem has to be weakened from its C0 statement.
- Anything that would put Lean or Python into the install graph or into `src/`.
