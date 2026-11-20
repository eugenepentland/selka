# Ownership certificates: what was proved, what is assumed, what it costs

Report of the ownership-certificates work of 26 October 2026 (packages C0 to C9.9 and the
documentation package C5), written on branch `certs/c5-docs` from main `226855429`. The plan is
[ownership-certificates-plan-2026-10-26.md](ownership-certificates-plan-2026-10-26.md); the design is
[`docs/design/ownership-certificates.md`](../design/ownership-certificates.md) and
[`docs/design/fact-certificates.md`](../design/fact-certificates.md); the guides are
[`docs/tooling/ownership-certificates.md`](../tooling/ownership-certificates.md) and
[`docs/tooling/fact-certificates.md`](../tooling/fact-certificates.md).

**How to read the numbers.** Every number comes from a committed file, cited by path. The few I
measured for this report are marked *new measurement* and give the command that produced them. The
coverage census, with the figures of the audited C9.2 run, is [section 7](#7-the-coverage-census).

## 1. Summary

- **Three Lean projects, one toolchain** (`leanprover/lean4:v4.35.0`, core Lean only, no Mathlib), none
  declaring an `axiom` and none containing a `sorry`. Every theorem below depends on `propext`,
  `Classical.choice` and `Quot.sound` and nothing else, and the build fails if that stops being true
  (`#print axioms` in `proofs/ownership/Soundness.lean` and `Program.lean`; `#assert_axioms` in
  `proofs/facts/Facts/Check.lean` and `proofs/arith/Arith/Check.lean`).
- **Ownership** (`proofs/ownership`): a function whose final Core IR passes the checks J1 to J8 never
  faults, and a program of such functions leaks nothing at a normal exit of `main`
  (`Own.check_sound`, `Own.runs_sound`, `Own.main_no_leak`).
- **Facts** (`proofs/facts`): a fact table a checker accepts is an inductive invariant of the IR, so no
  block stated dead is entered and no check marked `proven` is undefined behaviour
  (`Facts.fact_certificates_sound`).
- **Arithmetic** (`proofs/arith`): the LLVM sequence the emitter prints for nine integer and float
  operations equals the operation's mathematical specification at widths 8 to 64.
- **The 54 ownership rules.** 36 are safety rules the proof covers, 12 are source-clarity rules the
  proof does not need and 6 are type rules the model takes as given. The per-rule table, with the
  check, the Lean lemma and the assumptions each rule rests on, is
  [`docs/ownership-rules.md#proof-coverage`](../ownership-rules.md#proof-coverage).
- **What is assumed.** 16 numbered ownership assumptions (A1 to A6, A8 to A17) plus the eight runtime
  contracts of task groups, A7.1 to A7.8 (`proofs/ownership/AXIOMS.md`); the fact theorem's model, typing,
  hypotheses and five accepted-on-trust clauses (`proofs/facts/AXIOMS.md`); and the arithmetic theorems'
  seven model items, three hypotheses and two checked-not-proved items (`proofs/arith/AXIOMS.md`). Three of the ownership assumptions (A13 to A15) are checked by the
  validator and the Lean checker but not covered by the theorem.
- **What it costs.** Nothing in a ReleaseFast compiler without a flag. On EDA stage 2, the largest guest the
  lanes have, validation changed a ReleaseFast build's wall time by -1.2% in the latest timing-slot run
  (section 4.3). In the gate, the measured
  `ownership-proof` action is 1.2 to 46.9 s after a `src/` edit and 2.2 s unchanged (section 4.1); the
  complete gate of this branch passed (321.3 s before the rebase onto C9.2, 1,952.8 s after it, most of which was
  queueing on a shared machine).
- **What it found.** Two compiler changes the validator forced, two unsound cases in the validator's own
  trap handling that the Lean model exposed, a run of exporter gaps, and seven stale-cache cases in the
  separate cache audit (section 5).
- **Coverage.** Every program of the gate corpus (632 of 632), of EDA stage 2 (139 of 139) and of selka
  (86 of 86) has all its functions accepted and its callee tables linked, so every hypothesis of the
  whole-program corollary is enforced by a checker, by the link or by a numbered assumption (section 7).
- **Open.** The three loan assumptions and the points of section 8.

## 2. What is proved

### 2.1 Ownership

The Lean model abstracts the final Core IR to the operation classes of design section 3: a heap of
allocations with owner trees, blocks of class-level instructions, and small-step execution. A **fault**
is one of ten things (`Fault` in `proofs/ownership/Semantics.lean`): reading a dead allocation
(`readDead`), consuming one that is not a live root (`consumeDead`), destroying a tree twice in one
instruction (`destroyTwice`), consuming or destroying a borrowed value (`takeBorrowed`), consuming a
tree another operand still reads into (`overlap`), consuming a container with an open take (`stranded`),
a stack value escaping (`escape`), reading an owner whose loan operand is gone (`dangling`), destroying
a cell lent to a live group (`lentGone`), and a fault inside a callee (`calleeFault`).

| Theorem (`Own.`) | File | Statement |
| --- | --- | --- |
| `check_sound` | `Soundness.lean` | If `check f c = true` and `f`'s before-the-call condition holds, no execution of `f` faults and every normal return meets the after-return condition: owned arguments destroyed or reachable from the result, borrowed arguments unchanged, an owned result fresh, a borrowed result inside the trees its `from` set names |
| `runs_sound` | `Program.lean` | The same for every function of a well-formed program, by induction on the length of the run, so recursion is covered |
| `main_no_leak` | `Program.lean` | A scalar-result function started on an empty heap that returns normally leaves no allocation live |

Design section 6 states the contract; `proofs/ownership/NOTES.md` ("The proof") lists the files in
import order. Traps end the execution and are outside the theorem: they run no destruction
(`RC-TRAP-TEARDOWN-1`). Since C9.1 (design entry 55) an edge into a trap region names the owners the
path abandons, and `abandon_inv` shows that a leak is allowed on a path to a trap and on no other.

Coverage grew in steps, each recorded in design section 9: J7 (stack escape) at C3.6 (entry 44), loans of
every owned value at C3.8 (entries 50 and 51), task groups at C6 (entries 40 to 47), trap regions at
C9.1 (entry 55), calls that return an `emptied` record at C9.4 (entry 56, assumption A16), calls that name
their callee at C9.2 (entry 57, assumption A17: the call-site agreement `CallWf` became a check and a link,
not a hypothesis) and the removal of most forward takes at C9.9 (entry 58).

### 2.2 Facts

`Facts.fact_certificates_sound` (`proofs/facts/Facts/Theorem.lean`): if the checker accepts every function
of a module and the IR verifier's rule holds (every use is dominated by its definition), then every
execution from an external entry, with arguments in the stated parameter intervals, that honours the
assumptions of `proofs/facts/AXIOMS.md` satisfies three things at every configuration it reaches:
every integer or boolean value lies in its stated interval and its type's range; no block stated dead is
entered; no instruction accepted as `proven` is undefined behaviour. `Facts/Connect.lean` instantiates the
lowering theorems of `proofs/arith` (`lower_div`, `lower_shift`, `lower_convert`, `lower_arith`) with those
facts, so for a `proven` instruction the emitted sequence computes what the machine computes
(`proofs/facts/README.md`, "What is proved"). The counted loops' counters, the reductions by accumulator
chains and joins, and every list fact a list operation, a view or a phi derives are proved, not assumed
(`proofs/facts/AXIOMS.md`).

### 2.3 Arithmetic lowering

For `div`, `rem`, `floor_div`, `floor_rem`, `shift_left`, `shift_right`, `convert`, `float_to_int` and
`saturating_add`, at widths 8, 16, 32 and 64 and both signednesses, the sequence the emitter prints
equals the operation's specification on `Int` as an equality of outcomes (`ok r`, `trap kind`, `ub`,
`poison`), so one statement gives the result, the exact trap condition and the absence of undefined
behaviour (`proofs/arith/README.md`). The Lean formulas are rendered as LLVM text into
`proofs/arith/templates.txt` (409 cases), and `src/core/arith_lowering_test.zig` pins the emitter to them
(168 of the cases are also compiled from source programs; `proofs/arith/AXIOMS.md`, E1).

### 2.4 How the Zig validators are tied to the Lean checkers

Neither Lean checker runs inside a compile. The Zig validators run in every Debug compiler and the gate
makes them agree with the Lean checkers (`docs/tooling/ownership-certificates.md`, "The gate action
`ownership-proof`"):

- the Zig validator and `lake exe certcheck` must print the same verdict for every function of the
  certificates the language gate writes, or the action fails unless `tests/ownership-proof-known.json`
  lists the function with a reason; the list is empty;
- the hand-written functions of `src/core/validate_ownership_test.zig` go to both checkers, and
  `proofs/ownership/fixtures-zig` and `fixtures-zig-c9` hold Lean's verdicts for shapes with real operation
  names that the Zig validator is run against;
- since C9.2 the callee tables of each program are linked: every `program` entry must name a function of the
  program and describe its header (`certcheck --link` and `mylang link-certificates`); the gate runs the link
  over the corpus (section 6);
- the single-edit faults of `src/core/ownership_mutants.zig`, made from the certificates of
  `test/fixtures/ownership-proof/`, must be rejected by both, and every fault class must make a mutant;
- the facts half (`scripts/fact_proof.py`) does the same for `lake exe factcheck` against
  `mylang validate-fact-certificates`, line by line, on the release run's certificates, the mutants of
  `test/fixtures/fact-proof/` and the fixtures under `proofs/facts/fixtures/`;
- `arith-proof` (`scripts/arith_proof.py`) runs `lake build` of `proofs/arith` and checks that
  `templates.txt` and `FORMULAS.md` are what the formulas render.

That the Zig validator and the Lean checker mean the same thing is therefore tested, not proved
(`proofs/facts/AXIOMS.md` E1 says so for facts; the same holds for ownership). The agreement counts are in
[section 6](#6-zig-and-lean-agree).

## 3. What is assumed

The committed ownership list is A1 to A6, A8 to A17 and A7.1 to A7.8 (the single design assumption A7 of
task groups, made concrete in design section 10.5). A17 arrived with C9.2. Design section 8 numbers its list
differently from `AXIOMS.md` after A6 (it lists A7 for task groups and a retired A8 for J7, where `AXIOMS.md` has
A8 for decided tests and no design text for A17); `AXIOMS.md` is the list that mirrors the Lean model, so it is
the one below. `proofs/ownership/NOTES.md`, "Hypotheses of the whole-program corollary: who enforces what
(C9.2)", lists every hypothesis of the corollary and who enforces it; everything in it that is not a
numbered assumption is enforced by the checker, by the link or (the run premise of `main_no_leak`) is the
statement of what is run.

### 3.1 Ownership (`proofs/ownership/AXIOMS.md`)

Each assumption is a definition of the semantics (true of the model by construction, false of the real
system only if the runtime differs), a hypothesis of a theorem, or an assumption about the exporter that no
Lean statement can express. The last column says what would close it. Where no committed document says so,
the entry is marked *(author's reading)*.

| # | Assumption | Kind | What would close it |
| --- | --- | --- | --- |
| A1 | The operation-class table describes what the emitter and the runtime do | exporter + table | A table generated from the emitter instead of written beside it *(author's reading)*; today it is reviewed line by line (plan C1) and exercised by the corpus, the mutants and the Lean differential |
| A2 | `drop` frees exactly its operand's tree; allocation returns storage disjoint from every live tree | definition | A verified allocator in `core_rt.c`, outside this project *(author's reading)* |
| A3 | `undef` of a managed type is the null owner and is never freed | definition + exporter | Plan C9.7 (cleanup phis without `undef`) would remove part of it; dropped for now because the 16 phis are all in `tests/lang/owned_field_moves.my` (plan 7.3) |
| A4 | Immortals are never freed, and consuming one changes nothing | definition | As A2 *(author's reading)* |
| A5 | External functions (`myl_core_*`, `extern func`) and the reserved marker calls satisfy their signatures' contracts | definition; hypothesis of the corollary (`ExternRespects`) | For a function of the program the corollary proves it, since C9.2 from the callee table; the table's `runtime`, `extern` and `marker` entries are checked for arity only (J1 `call-arity`). For the C runtime, contracts proved or tested per function *(author's reading)* |
| A6 | LLVM emission keeps each function's instruction order for ownership effects | definition | Not closable inside the project: it is trust in the LLVM pipeline *(author's reading)* |
| A7.1 to A7.8 | The runtime contracts of task groups (a lent box has no layout; a task reads only what it was lent; submit, take, end and open behave as their signatures say; `group_end` returns only after every task finished; a group stays on its thread; `map` joins before it returns) | exporter + emission; modelling choice; runtime; mostly A5 | A7.5, the one the proof leans on, needs the runtime's join to be shown to wait for its tasks; the tasks themselves are not modelled (`AXIOMS.md`, A7.2) |
| A8 | A repeated pure `cmp`/`fcmp` of one predicate on unredefined operands gives the same answer | definition + exporter | Already a definition of the semantics; nothing to close |
| A9 | An argument for a `scalar` parameter is an immediate | hypothesis of `check_sound` (`ScalarArgs`); exporter | Since C9.2, J1 `call-scalar` checks it at every call through a `program` or function-value entry; it stays a hypothesis for the entry function (the run premise of `main_no_leak`) |
| A10 | A closing update through a value that holds no tree returns a value that holds no tree | definition | Nothing to close |
| A11 | A value in state `stack` is a stack list of this activation, and no other state is | definition + exporter | The exporter's table gives `Fresh`, a filling `Update` and a stack phi the state `stack`; J7 checks the rest |
| A12 | The parents the certificate lists for an owned value cover every allocation its contents point into | definition + exporter | A model with cells per slot (A14) *(author's reading)* |
| A13 | A take marked `noloans` carries no loans; a view into itself does not survive an update | definition + exporter | Plan C9.3 (exporter facts: which operand fills which field, `noloans`) removes the rest of (1); it is optional and later in the plan |
| A14 | Slot-level ends of loans: taking or closing a slot ends the loans on it | not a Lean statement; checker only | An export that records which operand fills which slot of a constructor and which cells belong to a slot, and a model of takes that moves those cells (`NOTES.md`, "Open gaps"); the export half is plan C9.3 |
| A15 | Forward-take views: a view written before the take that owns its storage points into the taken owner | not a Lean statement; checker only | A model that rebinds the footprint of a forward view, and of every copy of it, when the take runs, and a checker invariant that each copy still has its placeholder root (`NOTES.md`). C9.9 removed most of these views; the rule, the `fwd(n)` root and A15 stay for the remaining cases (design entry 58) |
| A16 | The storage of an `emptied` call result is the storage of the parts the caller takes out at once | definition + exporter | A model that splits a tree by slot (A14, A15) would replace the dissolution by adoption; the alternative, an IR form for `mut` write-back, was costed at 50 to 80 hours with call-ABI risk (plan 7.3). Evidence at run time is in `AXIOMS.md`, "Evidence for A16" |
| A17 | A function value points to a function with the signature of its type (C9.2) | not a Lean statement; the IR verifier (`verify_ir.zig` lines 765 and 766) | A call through a function value is checked against the entry of its function type (J1 `call-entry`, `call-arity`, `call-scalar`, `call-result`, `call-from`), but no certificate says which function the value points to, and naming the function at each `func_ref` would not narrow the assumption because the certificate follows no values (`AXIOMS.md`, A17). Closing it needs a certificate that follows function values to their calls, or a proof of the verifier's typing *(author's reading)* |

The theorem also takes the before-the-call condition as a hypothesis (live, disjoint owned arguments, live
borrowed arguments, `apart`, `wf`): call sites establish it through J6 and M5 for a checked caller, and for
`main` and the external entries it is an assumption about the caller. The corollary takes `ProgWf` and nothing else about the program: every function passes `check`, and the
callee tables link (`Link.lean`). Before C9.2 it also took `CallWf`, the call-site agreement, which only the
exporter checked, and `CallWf.dst`, which no one checked and which a call to a function that returns nothing
does not meet. Both are gone: the checker establishes the site half (J1 `callee-table`, `call-entry`,
`call-arity`, `call-scalar`, `call-result`, `call-from`), the link the entry half, and `callWf_of_site` derives
`CallWf` (design entry 57).

### 3.2 Facts (`proofs/facts/AXIOMS.md`)

The numbers in this table are the facts list's own: its A2, A5 and A6.x are not the ownership assumptions
of the same number.

| # | Assumption | What would close it |
| --- | --- | --- |
| M1 to M5 | The model: integers are mathematical and the three forms of an operation behave as design section 4 says; a list is a `List`; a call runs the callee's body in a new frame; an operation the checker has no model of returns any value its type allows; a trap ends the run | Part of the definition of the machine |
| TY1 to TY3 | The machine is typed: results fit their declared types, a fixed array has its declared length, operations read operands of the right kind | The IR verifier and the runtime's type safety give it |
| H1 to H3 | The checker accepts every function; every use is dominated by its definition (what `verify_ir.zig` checks); the external entry's arguments meet the stated parameter intervals | Hypotheses of the theorem |
| A6.1 | The stated interval of the result of an instruction the checker has no rule for (field reads, `float_to_int`, dictionary reads, the `take` family) holds | A rule for each operation; for stale list reads, a derivation at the right program point |
| A6.2 | A reduction phi whose growth passes an inner counted loop stays in its stated interval (12 of 152 reduction phis in `tests/lang`, 1 of 14 in `bench/`; `proofs/facts/NOTES.md`) | The same invariant for the inner loop's phi, relative to the accumulator |
| A2 | A fill cap holds: the runtime allocates what the builder asked for | The fill-list pattern validation as a derived rule |
| A6.3 | A stated list length or element interval with no derivation holds (a parameter, a call result, an operation `Ctx.deriveList` does not know) | Derivations for the missing operations |
| A5 | A call to a function without a body returns within the interval that function states | Nothing inside the module: a contract with the C runtime or `extern` code |
| E1 to E4 | Checked, not proved: the Lean checker is the Zig validator (tested over the corpus, fixtures and mutants); the emitter emits the three forms; edge-checked additions are counted, not validated (E4); every pass after the facts preserves them, covered by the certificate being of the final IR | E4 needs a proof of `overflow_edges.zig`'s alias argument |

### 3.3 Arithmetic (`proofs/arith/AXIOMS.md`)

M1 to M7 are model items (LLVM's integer semantics, poison never allowed to exist, a trap is defined
behaviour and the runtime's `@myl_core_trap` does stop the program, hardware saturating addition, the
binary64 model, every bit pattern decodes to a valid value, the eight `float_to_int` constants). H1 to H3
are hypotheses (a test the emitter omits for a constant divisor cannot fire; the `proven` forms hold under
the facts; signed division needs width at least 2). E1 is checked, not proved: that the formulas are what the
emitter emits is pinned by `arith_lowering_test.zig`. E2 is that LLVM compiles the IR as its semantics say.
Not covered: vector integer operations, overflow-checked `add`/`sub`/`mul`/`neg`, `int_to_float`, float
arithmetic, `saturating_sub` and `saturating_mul` (runtime calls).

### 3.4 What the theorems do not say

- That the source checker enforces a rule's predicate. The proof covers the run-time property a rule
  protects, in the final IR (design section 7).
- Anything about a run that traps, or about concurrency beyond the lend rules of task groups
  (`AXIOMS.md`, A7.2 and A7.7).
- That a certificate describes the final IR faithfully: that is A1 and the exporter.
- A14 and A15 gaps: a view whose storage a take moves, and a view written before its take, are checked by
  the validator and the Lean checker but the theorem does not say a late use is a fault
  (`proofs/ownership/AXIOMS.md`, "What the theorem does not cover").

## 4. What it costs

### 4.1 Against the budgets of plan section 5a

| Loop | Budget (plan 5a) | Measured | Source |
| --- | --- | --- | --- |
| Guest code with a ReleaseFast compiler | 0 | 0 by construction: `validate_ownership.enabled` and `validate_facts.enabled` are `builtin.mode == .debug`, so without a flag nothing runs and nothing in the build, the cache keys or the output changes | `src/core/validate_ownership.zig`, `src/core/pipeline.zig` (`checksOwnership`, `checksFacts`), `docs/tooling/native-build.md` |
| Compiler edit loop, validator inside each Debug guest build | at most 3% of guest compile time | On a large guest (EDA stage 2 `eval_design_block_test.my`, ReleaseFast compiler, timing slot, `--verify-ownership` on against off, median of 3): wall 62.34 s against 61.58 s (-1.2%), CPU 114.94 s against 112.92 s (-1.8%). On small programs on a loaded machine: not resolvable on a whole build; +4.0% to +4.7% of the CPU of the front end and passes alone | section 4.3; section 4.2 (*new measurement*) |
| Complete gate after a `src/` edit, few programs change | at most 15 s added | comment-only edit 6.3 s (action), 128.2 s (gate); `own.zig` edit, 15 functions changed, 1.2 s and 150.9 s | plan 5a, table "Measured at C4.5 and C4.6" |
| Complete gate after a `src/` edit, all programs change | at most 60 s added | IR-construction edit, 6,536 of 9,140 functions changed, 46.9 s and 165.5 s | plan 5a |
| Complete gate after a validator or `proofs/` edit | at most 3 min | validator comment edit 29.2 s; `proofs/` edit 148.2 s (before the fast checker); after C3.7, 16.7 s for a definition change in `proofs/` and 27.5 s from an empty private store | plan 5a; `proofs/ownership/NOTES.md`, "Cost (C6.2)" |
| Complete gate with nothing changed | 0 | the action is not executed; the gate takes 16.9 s | plan 5a |
| Peak memory of a guest compile with the validator | at most 25% added | 0.3% to 0.6% (EDA stage 2: 785 MB against 783 MB); in the later timing-slot run of section 4.3 the whole-process RSS was 1358 MB off and 1331 MB on (-1.9%); the action itself peaks at 125 MB with nothing to check and 500 MB with the four largest functions on the Lean checker | plan 5a; section 4.3 |

The plan's size cap on the Lean checker (100,000 bytes of certificate text, because four functions of about
180 KB took 57 to 128 s each) was lifted on 26 October: after C3.7 the largest corpus function takes 0.04 s
and `certcheck` checks 10,775 functions in 3.4 s (release) and 4.9 s (debug) on one thread, 0.4 s and 0.85 s
on all (`proofs/ownership/README.md`, "Speed"; `NOTES.md`, "Cost (C6.2)"). `lake build` of
`proofs/ownership` takes 14.7 s from a clean tree, `proofs/facts` about 25 s cold
(`proofs/facts/README.md`) and `arith-proof` 0.8 s (`docs/tooling/ownership-certificates.md`, example
output); each reruns only when a file under its `proofs/` directory changes.

### 4.2 The validators inside a compile, small programs on a loaded machine (new measurement)

Plan 5a sets 3% of a Debug guest build's compile time as the budget for the validator inside a compile,
and no committed report records the figure. This measurement is a bound with these caveats: it uses a
ReleaseFast compiler built from this branch (`zig build -Doptimize=ReleaseFast --prefix ~/.cache/mylang/c5-rf`)
with the validators switched on by flag, where a Debug compiler runs them always and is slower throughout;
it reports CPU time (user plus system, children included), not wall time, because the machine was shared
(load average 13 to 17 for the figures below, 40 to 73 for the first run kept beside them); and its programs
are small (`bench/parity/suite/json_roundtrip.my` has 25 functions, `tests/lang/constant_divisors.my` one).
`scripts/build-slot.sh timing` was not used: it would have stopped every other agent's admissions, and CPU
time was the quantity wanted. The script alternates the validated and unvalidated runs and takes medians
(`experiments/ownership-certificates-report-20261026/measure_validators.py`; raw output in the evidence
archive named in section 9).

| Measurement | Without | With | Change |
| --- | --- | --- | --- |
| Warm release build of `json_roundtrip.my`, both validators (`--verify-ownership --verify-facts-static`), 15 repetitions | 0.121 s | 0.127 s | +5.4% |
| The same, `--verify-ownership` only | 0.120 s | 0.124 s | +3.2% |
| The same, `--verify-facts-static` only | 0.116 s | 0.125 s | +7.2% |
| Warm default (optimized debug) build of `json_roundtrip.my`, `--verify-ownership` | 0.124 s | 0.116 s | -6.9%: noise |
| Warm release build of `constant_divisors.my` (one function), both validators | 0.120 s | 0.120 s | 0.0% |
| Cold release build (empty object store, so LLVM and clang run), `json_roundtrip.my`, 7 repetitions | 7.09 s | 6.00 s | the validated run was faster: noise |
| Cold release build, `constant_divisors.my`, 7 repetitions | 6.30 s | 5.80 s | noise |
| `dump-ir --certificate` with and without `--validate`, 126 modules of `tests/lang` that have a `main`, medians of 3, summed | 0.978 s | 1.024 s | +4.7% |
| `mylang validate-certificates` over the 8,097 functions of the 337 release certificate files of `tests/lang` (best of 3, parse included) | - | 0.46 s | 57 microseconds a function |

A "warm" build is one whose unit objects the per-user store serves, so it is the compiler's own work (front
end, passes, emission, link) without LLVM; it is the part of a build the validators sit next to. The first
run of the same script (load 40 to 73, kept as `validators-first.json`) gave +8.1%, +4.5%, -1.7% and +1.8% for the
four `json_roundtrip.my` rows and +4.0% for the `dump-ir` sweep, so differences below about 5% are not
resolved by 15 repetitions on this machine. What the figures support is: the validators add a few percent to
the compiler's own work, they are unmeasurable inside a cold build, and the validator is a small fixed cost per
function (57 microseconds, parse included) next to a compile of 0.12 s for the smallest programs and 6 to 7 s
cold. They do not show that the budget is met on a large guest program; section 4.3 does, from a measurement
taken in a timing slot.

### 4.3 A large guest in a timing slot

EDA stage 2 is not in this repository. The Zig lane of C6.1 and C9.1 measured its `eval_design_block_test.my`
with a ReleaseFast compiler in a `scripts/build-slot.sh timing` slot, `--verify-ownership` on against off. Each
run printed wall time, CPU time and RSS of the build, as the median of three (the coordinator's description of the
lane's script). The logs are copied from `~/.cache/mylang/certs-c6/` into the evidence archive (`certs-c6-cost/`)
and are named below as the lane named them. The run of 26 October 18:38 (`cost-c9.log`) is the latest:

| Program | Wall off | Wall on | CPU off | CPU on | RSS off | RSS on |
| --- | --- | --- | --- | --- | --- | --- |
| EDA `eval_design_block_test.my` | 62.34 s | 61.58 s (-1.2%) | 114.94 s | 112.92 s (-1.8%) | 1358 MB | 1331 MB (-1.9%) |
| `test/fixtures/ownership-proof/tasks.my` | 3.49 s | 3.44 s (-1.4%) | 3.57 s | 3.52 s (-1.4%) | 176 MB | 175 MB |
| `tests/lang/parallel_groups.my` | 3.91 s | 3.93 s (+0.5%) | 4.79 s | 4.81 s (+0.4%) | 175 MB | 172 MB |
| `tests/lang/borrowed_signatures.my` | 4.45 s | 4.36 s (-2.0%) | 4.95 s | 4.89 s (-1.2%) | 175 MB | 173 MB |

Two earlier runs of the same program, kept because they are part of the record:

| Log | Wall off | Wall on | CPU off | CPU on | RSS off | RSS on |
| --- | --- | --- | --- | --- | --- | --- |
| `cost-c38.log` (C3.8 stage) | 57.18 s | 62.50 s (+9.3%) | 105.48 s | 112.50 s (+6.7%) | 1304 MB | 1314 MB (+0.8%) |
| `cost-c61-eda.log` (C6.1 stage) | 55.86 s | 56.17 s (+0.6%) | 103.68 s | 104.42 s (+0.7%) | 1298 MB | 1337 MB (+3.0%) |

The C3.8 run is over the 3% budget on its own. The validator at that stage still had the trap meet that C9.1
later replaced (design entry 55); the log does not say why that run was slower and the two later ones were not,
so I do not claim a cause. The two later runs are inside 3% and the latest is slightly faster
with the validator on, which is noise of the size seen in section 4.2, not a saving. A third log, `cost-c6.log`,
holds the same measurement for four small task-group programs (wall within -2.3% to 0.0%, CPU within -4.4% to
+0.6%) and then stops with a `ZeroDivisionError` in the lane's script; the four printed lines are complete.

The validator alone over EDA's 1,703 functions took 0.42 s of user time and 67.7 MB, as the Zig lane reported to
the coordinator; that run's raw log is not among the four `cost-*.log` files, so it is cited here from the
coordinator's message and not from a file.

### 4.4 What there is to maintain (new measurement)

Counted with `wc -l` on this branch: the Zig side is `src/core/validate_ownership.zig` (1,783 lines),
`validate_facts.zig` (1,559), the exporters `ownership_export.zig` (761), `ownership_ops.zig` (251),
`fact_export.zig` (428) and the readers `ownership_parse.zig` (401) and `fact_text.zig` (492). The Lean
side is 13,086 lines in 32 files under `proofs/ownership`, 11,329 under `proofs/facts` and 2,640 under
`proofs/arith`. Lean is a developer and gate tool only: building and using mylang still needs only Zig, and a
machine without Lean fails the two proof actions with a message
(`docs/tooling/ownership-certificates.md`). The first `lake build` downloads the pinned toolchain, about 3 GB
(`proofs/ownership/README.md`).

## 5. What the work found

### 5.1 Compiler changes the validator forced

1. **A double release on a path that traps** (design entry 27, C2). `own.zig` dropped a container with an
   open take on a path ending in `unreachable`: the take leaves the slot's pointer in place, so the drop
   released it a second time before the trap. Three corpus functions showed it
   (`recursive::test_a_copied_recursive_box_shares_and_separates_nested_lists`,
   `recursive::test_repeated_write_through_a_boxed_child`,
   `recursive_values::test_writes_to_copies_leave_other_values_unchanged`). The fix schedules no drop in a
   block from which only trap blocks are reachable. Since C9.1 the certificate names what such a path
   abandons (entry 55).
2. **`lists.extend(mut rows[0], rows[0])`** (entry 34, commit `01d49437c`, C2). The lowering kept a run-time
   branch on `myl_core_owned_same_block` and, on the other arm, read a view of `rows[0]` while pushing onto
   `rows[0]`. Safe at run time because the arms are exclusive, but the certificate cannot see that and a
   view of a list that outlives an update of it is what J4 refuses. Both reads name one slot of one list
   statically, so the lowering is now one append. This one is a lowering the proof could not follow, not a
   wrong result.

A related lowering change came from the census of forward takes (C9.0): 160 of 168 were a dead view the
lowering left in front of a take, and C9.9 (entry 58, `take_first.zig`) removed them, which took the gate
corpus from 73 forward takes to 8 and left the release binaries byte for byte as before.

### 5.2 Holes in the Zig validator that the Lean model exposed (C3.8)

The Lean model was stricter than the Zig validator in several places, listed with their fixtures in
`proofs/ownership/NOTES.md` ("C3.8: the deviations from the Zig validator, one direction each"). Two were
real holes in Zig, both in the meet of a trap block (design entry 49, fixtures `bad_trap_meet_take_first`,
`bad_trap_meet_roots_swapped`):

- the meet kept the open takes of the first edge only, so a slot left open on a later edge was invisible
  and a second take of it passed (`reject J8`);
- the meet kept the roots of the first edge only, so a borrowed phi selecting views of two owners lost one
  root, and the drop of that owner and a read of the phi passed (`reject J4`).

C3.8 also made loans carried through every consumer (entries 50 to 52): before, a holder consumed by an
update or a call lost its loans, so `list_push` of a record that holds a view of `%0` followed by `drop %0`
left the view dangling (`bad_loan_lost_through_update`, `bad_loan_lost_through_call`). Design entry 55 records that
the trap meet "was the source of both real validator holes of C3.8, five Zig/Lean deviations and the C2.7
out-of-memory case" (a function with thousands of views took 3.4 GB to validate, entry 36), and that is why
C9.1 replaced it with explicit `abandon` lines, which plan 7.3 says deletes a 716-line Lean file.

The census run of C9.4 exposed one more such case: Lean rejected `eval_design_block::parse_board` (J1
`parentsOk`) in 24 of the 140 EDA programs that the Zig validator accepted, because the Lean rule for the
parents of a projection did not know the `from` list of the call (`docs/design/c9-write-back.md`, "A finding that
the census exposed"). `callFromOperand` in `Checker.lean` fixed it, and no proof changed.

The facts checker showed the same pattern. Lean checks more than the validator in nine
places (`proofs/facts/NOTES.md`, "Deviations"); two were findings reported and mirrored in Zig (an entry
block with a predecessor, and a counted loop whose body does not dominate its latch), and the shift check
(commit `a9d4e4257`: a `shift_left` whose left operand does not have the result's type is refused) mirrored
row 7, the one the table lists as not yet mirrored.

### 5.3 Exporter and table gaps

The exporter and the operation-class table were corrected where the corpus showed them wrong (design
section 9, entries 2 to 11, 20 to 23, 25, 48 and 57; `proofs/ownership/NOTES.md`, "Findings from the
corpus"):

- `text_frame(a, b)` exported the cache owner as its parent where the borrow-result rule and the functions'
  own `from` sets take the view `b`; three functions (`path::basename`, `path::dirname`,
  `dictionary_range_keys::built`) were rejected (entries 4 and 21);
- `undef` of a managed type, unit values named as operands, `copy` as a forwarding operation, `array_get` as
  a slot read, scalar results of updates and takes, calls with no result and marker calls were not in the
  first table (entries 2, 3, 5, 22);
- the compiler's `transferredRead` flag marks only four of the takes, while about 570 `record_get` takes
  occur in 1,272 sampled functions and about 300 `emptied` aggregates carry no marker in the IR (entry 6),
  and `dict_remove` needed a `taken` extra (entry 25);
- path-correlated takes and closes across a join needed guards, which came from two corpus functions
  (`m_none_keys::test_none_key_remove_reinsert_tombstones_and_defaults`,
  `rc_collection_builtins::test_dictionary_results_survive_receiver_clear`; entry 23);
- the call-site agreement `CallWf` was first the exporter's private check (entry 48, which made the part of the
  corollary's hypothesis that could be checked a fact); since C9.2 the certificate names each call's callee, the
  validator and Lean check the site, the link checks the entry, and the private check is deleted (entry 57).

### 5.4 Harness and gate defects

- Fixture differential between the two checkers: seven known disagreements at C4.3 (commit `81a545f14`),
  six resolved by decision at `188b213dd`, none now (`tests/ownership-proof-known.json`).
- Stale certificate directories: `mylang test` writes certificates only when it builds, so a test served
  from a receipt left old ones; each directory now carries a stamp (plan 5a, C4.6).
- The Zig fact-certificate reader skipped a symbolic link while the Lean checker followed it, so the gate saw
  `zig: files=0` (commit `f16ec260f`).
- A relative corpus path named different files for the validator and the Lean checker (commit `6e92ff05d`).
- `mylang dump-ir FILE` segfaults on EDA, the selka mains and 13 of 324 gate test modules
  (`docs/audits/ownership-certificates-plan-2026-10-26.md` section 7.3); the certificate flags are
  unaffected. That is a separate bug, outside this work.

### 5.5 Stale cache results (K0 of the provable-cache plan)

The cache read audit (`experiments/cache-read-audit-20261026/REPORT.md`) found seven results a cache could
serve that a clean build would not print or link, and fixed all seven with regression tests in
`src/core/cache_staleness_test.zig`: replay ignoring how the entry path or a `--link` source was spelled;
the shadowed-standard-module warning printed twice and kept after the file was deleted; a body replayed
from the checked-body store losing `W_DEPRECATED`; a `--link` object dropping the C compiler's warnings; an
import used only inside an `f"..."` hole becoming `W_UNUSED_IMPORT` once its module's bodies were replayed
(the cause of the `mylang fix` import removal seen at the 25 October integration); and a header beside a
`--link` source leaving a stale object. After the fixes the 388 mutation cases are 200 correct reuses, 182
correct misses and 6 stale; the 6 and the open items for K1 to K5 are listed in that report.

## 6. Zig and Lean agree

| Comparison | Count | Source |
| --- | --- | --- |
| Ownership, functions given to both checkers in the gate (six certificate directories) | 9,140, no disagreement (the known list is empty) | `docs/tooling/ownership-certificates.md`; `docs/audits/ownership-certificates-plan-2026-10-26.md` 5a; `tests/ownership-proof-known.json` |
| Ownership, a fresh export of 632 programs before the C9 changes | 10,775 functions, 10,775 accepted in debug and in release, 0 rejected, 0 `unchecked` | `proofs/ownership/NOTES.md`, "Third export" |
| Ownership, single-edit faults of 6 programs | 249 mutants, all rejected by both | `proofs/ownership/NOTES.md`, "Cost (C6.2)" |
| Ownership, expected verdicts of the Lean fixtures | 139 in `fixtures/expected.txt`, 40 in `fixtures-zig/expected.txt`, 19 in `fixtures-zig-c9/expected.txt` | `wc -l` on this branch (*new measurement*) |
| Ownership, mutants of the real task-group functions | 17 (lender dropped above the join) all `reject J4`; 38 (join replaced by a drop) all `reject J2` | `proofs/ownership/NOTES.md` |
| Facts, functions of `tests/lang` | 13,200, verdicts and statistics identical | `proofs/facts/NOTES.md`, `README.md` |
| Arithmetic, formulas against the emitter | 409 templates, 168 also compiled from source | `proofs/arith/README.md`, `AXIOMS.md` E1 |
| Gate run of this branch after C9.2, `ownership-proof` | 9,149 functions, 0 disagreements (0 known); callee tables linked: 754 programs, 18,088 functions, 20,428 entries, 0 rejects, 0 errors; 409 mutants of 7 programs rejected by both; 94 validator fixtures compared; 110.7 s with every verdict taken from the shared store | *new measurement*: complete gate of 27 October on the rebased branch, lines copied to `gate-rebased-stdout.log` in the evidence archive |
| The same gate before C9.2 (branch from `226855429`) | 9,140 functions, 0 disagreements; 312 mutants of 7 programs; 74 validator fixtures | `gate-stdout.log` in the evidence archive |
| Gate run of this branch after C9.2, `fact-proof` | 29,196 functions of 754 fact certificates accepted by the Zig validator and the Lean checker, which print the same line for each; 72 mutants of 4 programs rejected in their own function, the same by both; 19 fixtures judged as expected; 2.4 s | same run |
| Gate run of this branch after C9.2, `arith-proof` | `lake build` ok, no error, no `sorry`, axioms audited; 409 cases render as `templates.txt` and `FORMULAS.md`; 1.1 s | same run |

## 7. The coverage census

The whole-program corollary (`Own.runs_sound`, `Own.main_no_leak`) applies to a program only when its
hypothesis `ProgWf` holds: every function passes `check` and the callee tables link. `certcheck` counts a
program when exactly that holds, so every hypothesis of the corollary is enforced by the checker, by the link
or by a numbered assumption (`proofs/ownership/NOTES.md`, "Hypotheses of the whole-program corollary: who
enforces what (C9.2)", which lists each hypothesis and who enforces it; `proofs/ownership/AXIOMS.md`, A5, A16
and A17 for the assumptions). The figures are those of lane 2's audited C9.2 run (branch `c9/callees-lean`, merged
with the Zig lane's `c9/callees` at main `7a1a09382`), as the coordinator reported them; the plan records the same
three totals (`docs/audits/ownership-certificates-plan-2026-10-26.md`, section 7.3, C9.2).

| Corpus | Programs covered | Kept out before C9.2 by a call to a unit program function | Kept out before C9.4 by that or an `emptied` call |
| --- | --- | --- | --- |
| gate | 632 of 632 | 404 (64%) | 434 (69%) |
| EDA stage 2 | 139 of 139 | 21 (15%) | 106 (76%) |
| selka | 86 of 86 | 3 (3.5%) | 69 (80%) |

**A correction to C9.4.** The "632 of 632" that C9.4 reported (design entry 56, `docs/design/c9-write-back.md`) was
a count for the wrong statement: it counted programs whose every function is accepted and that no `emptied` call
excludes, which is not the same as meeting every hypothesis of the corollary. `CallWf.dst` required every call of a
program function to have a destination, nothing enforced it, and a call to a unit program function has none, so
404 of the 632 gate programs were still outside the corollary when C9.4 reported them covered. The "Kept out
before C9.2" column is the correction: it is what C9.4's count left out. The C9.2 figures in the first column are
the first that mean what the sentence above says. C9.2 removed `CallWf.dst`, made the site half of `CallWf` a check
in both checkers, and linked the entry half.

Calls in the gate corpus: 107,433 call lines. 14,555 are calls to program functions, all of whose callee tables
link; 97 go through function values (assumption A17); and 92,781 go to runtime, extern or marker functions, which
are judged for arity only and otherwise rest on A5. The three kinds add up to the total.

**The link in the gate.** In the complete gate of this branch after the rebase onto main `7a1a09382`
(*new measurement*; the same numbers the coordinator reported from C9.2's gate), the `ownership-proof` action
printed `callee tables linked (programs=754 functions=18088 entries=20428 reject=0 errors=0; 14.2 s Zig, 5.8 s
Lean)`, so 754 programs, 18,088 functions and 20,428 callee-table entries linked with no reject. The same action
rejected 409 mutants of 7 programs in both checkers, compared 94 validator fixtures and found 0 disagreements. The
754 and the 632 gate programs of the census are separate runs over separate sets of certificate files, and this report
does not reconcile them.

**What the census does not say.** It counts programs for which the hypotheses hold. It does not say anything about
a program for which a numbered assumption is false (A5, A16 and A17 are the three that apply to calls), and it is
a count over the corpora of this repository and of the EDA and selka trees, not over every program a user may write.
The run premise of `main_no_leak` (the entry function returns a scalar and starts on an empty heap with immediate
arguments) is the statement of what is run, not a property the census checks.

**Certificate size.** The callee table grew the certificates by 7.1% on the gate corpus and by 8.0% on EDA stage 2
(plan 7.3, C9.2). That is above the 2 to 4% that C9.0 estimated for a callee table (plan 7.3, C9.0 table;
`experiments/c9-measure-20261026/REPORT.md`), because each function repeats its own table: a callee that many
functions call is written once in each of them.

## 8. Open items and limits

- A13 to A15 (loans in the model), section 3.1. A17 (function values) is new with C9.2 and is closed by no
  certificate; the IR verifier's typing is what makes it hold.
- The inner-loop reductions of A6.2 and the `edge-checked` additions of E4, section 3.2.
- Task groups: the tasks themselves, the thread pool and group confinement are not modelled (A7.2, A7.5,
  A7.7); A7.5 is the one runtime assumption the proof leans on.
- The Lean checker is tested against the Zig validator, not proved equal to it.
- None of the 12 clarity rules or 6 type rules has a check of its own (the `own` and call markers, written
  copies, writability, the type split); for three of them, B2, W2 and L1, the property their spelling protects
  is proved through J2. The proof says nothing about whether the source checker enforces any of the 18.
- K0's open items (toolchain files edited in place, link-directory dependence, absence and enumeration in
  cache records) belong to K1 to K5 of `docs/audits/provable-cache-plan-2026-10-26.md`.

## 9. Reproduce

```bash
source ~/.config/mylang/dev-env.sh
python3 scripts/verify_cache.py --zig "$ZIG" --profile complete    # runs ownership-proof (with fact_proof.py) and arith-proof
python3 scripts/verify_cache.py --zig "$ZIG" --profile proofs      # the same with the Lean size cap lifted
zig-out/bin/mylang doc-coverage .
zig build test-docs
zig build -Doptimize=ReleaseFast --prefix ~/.cache/mylang/c5-rf       # the compiler the section 4.2 figures use
scripts/build-slot.sh build python3 -I experiments/ownership-certificates-report-20261026/measure_validators.py \
    --compiler ~/.cache/mylang/c5-rf/bin/mylang --reps 15 --cold-reps 7 --out DIR \
    --corpus .mylang-cache/ownership-certificates/tests/lang/release \
    --corpus .mylang-cache/ownership-certificates/tests/lang/debug    # section 4.2, after a gate wrote the corpus
```

The raw output is in
`~/ai/canopy/mylang-evidence-archive/docs/audits/ownership-certificates-report-2026-10-26/`: `measure.log` and
`validators.json` (the figures of section 4.2), `measure-first.log` and `validators-first.json` (the first,
noisier run), `gate.log` and `gate-stdout.log` (the gate run of section 6), and `certs-c6-cost/` (the logs of
section 4.3).
