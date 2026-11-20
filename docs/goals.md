# Selka's goals and the evidence behind each

This page lists what the language is meant to guarantee and, for each goal, what backs it today: a proof, a checker, a
test, or nothing yet. It is the page to open when asking "is this still true, and how do we know".

**Status: a first draft, written on 11 November 2026 at main `2d371a50a`.** Since 12 November the gate checks that what
this page names exists and that its pinned examples pass; "How this page is checked" says what runs and what does not.
The work items (W1 to W24) and decisions (Q1 to Q10) it names are in section 9 of
`docs/audits/language-goals-audit-2026-11-11.md`.

## How to read an entry

Every goal has a level. "Proved" means different things for different goals, so the level says what kind of evidence
there is and what that evidence can rule out.

| Level | Evidence | What it rules out |
| --- | --- | --- |
| **Proved** | a Lean theorem about every program the compiler accepts, with its trust points listed | the stated fault, for every program, as long as the trust points hold |
| **Validated** | a checker that runs on each program as it is built | the fault in that build |
| **Gated** | a test over a fixed set of programs that runs in the gate | a regression on that set |
| **Probed** | pinned examples that are kept and can be run, but are not in the gate | nothing by themselves; they show the state when last run |
| **Measured** | numbers taken when someone asks | nothing; they record a state |
| **Stated** | a written rule | nothing |

Only the first two give "no bug of this kind", and only for the property the theorem or the checker states. A design
goal such as local reasoning has no theorem to prove; its honest top level is Gated.

An entry gives the claim, its level, the evidence by name, what the evidence rests on, the known exceptions, and what
would raise the level. An exception is something the goal says should not happen and that happens today.

## How this page is checked

The gate action `goals_register` (step `zig build test-goals`, driver `tests/goals_register.py`) reads this page and the
pinned examples and fails with one `file:line: message` for each rule below that is broken. It confirms that what the page
names exists; it does not confirm that the evidence says what the page says it does. It runs no Lean: the proofs are run by
the gate actions `ownership-proof`, `arith-proof`, `verify-ir-proof` and `cache-proof`.

The rules are the format an entry has to follow.

1. **Pinned examples pass.** The pages under `test/fixtures/goals/docs/` hold the pins. Each example states its expected
   verdict. A `H` example shows a goal holding. An `X` example pins a known exception to today's behaviour, so the day a
   fix lands the example fails and this page has to be updated with it. The gate runs the command below and requires exit
   status 0 and a last line that ends in `0 failed`. A pin marked `# doc: skip` is listed and not run; none is today. G10-H2 pins a
   trap and the runner expects it (`# doc: expect-trap R_LIST_BOUNDS`).

   ```bash
   zig-out/bin/selka doctest test/fixtures/goals
   ```

2. **A path exists.** A backquoted token with no space that contains a `/`, or that ends in a file extension (md, zig,
   lean, py, my, json, zon, toml, sh, txt, c, h), is a repository path and must exist, as a file or a directory. A file
   of another repository is written with that repository before a colon, as `port:docs/S1B-REPORT.md` for the port
   (`netlisp-selka-redo`); the gate cannot see it and does not check it.
3. **A theorem is declared where the page says.** A theorem is written as its Lean name with its namespace, in backquotes,
   followed by its file in backquotes inside parentheses: `Own.check_sound` (`proofs/ownership/Soundness.lean`). Names
   that share a file are joined by commas and "and" before the one parenthesis. The file must declare `theorem check_sound`
   (or `lemma`) inside `namespace Own`; the gate reads the text and does not run Lean.
4. **A gate action is registered.** Each name in backquotes written straight after the words "Gate action" or "Gate
   actions" (several joined by commas and "and", a parenthesis allowed after a name) must be an action `build.zig`
   registers: a `register("name"` call, or a declared input list that a step is keyed on. For example, Gate action
   `ownership-proof`.
5. **Example ids match the pins.** An example is cited by its id, `G9-H1` or `G7-X3`; `G9-H1 to G9-H9` cites every id from
   the first to the last. A pin starts a paragraph with its id in bold, `**G9-H1.**` or
   `**G7-X3 and G7-X4 (what it shows; W2).**`, and is followed by its example in a `selka` fence. Every cited id has a
   pin, every pin is cited, and an id is defined once.
6. **Exception counts agree.** An entry lists its exceptions as nested bullets under a `- **Exceptions.**` bullet, or as
   one `- **Exception.**` bullet when there is exactly one. `**Exceptions.** None ...` means there are none, as does an
   entry with neither. The "Open exceptions" column of the summary table is that number, and every entry has a row.
   A goal has one row, and an entry gives each labelled bullet (`- **Evidence.**`) once: a second row or a repeated label
   is a finding, because this page merges by union and a merge that keeps both sides of an edit leaves both.
7. **The action's inputs cover the page.** The `goals_register` list of `build_test_inputs.zig` holds the page, the pins,
   `build.zig`, this check's own files and every path the page names, so that editing, renaming or deleting one reruns the
   check. The failure names the path to add.

Not checked by anything: that a theorem or a test says what the page claims; that a pin marked `# doc: skip` still shows
what it says; the level given to a goal, which a person raises (see "Rules for keeping this page true"). The number of pins
and their run counts are the last line of the command in rule 1.

## Summary

| Id | Goal | Level today | Open exceptions |
| --- | --- | --- | ---: |
| G1 | Memory safety with no collector | Proved, and Validated on every build | 0 |
| G2 | A removed check cannot fail; integer operations compute what they say | Proved, and Validated on release builds | 0 |
| G3 | The IR is well formed | Proved for the Lean copy, Validated on every build | 1 |
| G4 | A warm build equals a clean build | Proved for an abstract algorithm only | 1 |
| G5 | An edit costs what the change costs | Measured | 1 |
| G6 | Run time within reach of Zig and Rust | Measured | 0 |
| G7 | Local reasoning: a caller is judged from signatures alone | Gated for calls across modules; Probed within one | 3 |
| G8 | `check` and `build` give one verdict | Gated | 3 |
| G9 | Nothing implicit: no hidden copy, no generated state machine, no implicit call | Validated on every build for copies; Probed otherwise | 4 |
| G10 | One meaning in every build mode | Gated on generated programs | 0 |
| G11 | No ambient authority | Gated | 2 |
| G12 | A lend cannot be told from a copy | Stated | 0 |
| G13 | A contract is never skipped | Validated at run time | 0 |
| G14 | One spelling for each thing | Stated | 5 |
| G15 | The toolchain needs no Python | Gated | 0 |
| G16 | A protocol between calls can be a type | Gated | 0 |
| G17 | A failed call says what it did to its arguments | Stated | 1 |
| G18 | An identity belongs to its owner | Probed | 1 |

The goals with the strongest evidence are the three about the final IR (G1 to G3). The goals about how code reads (G7,
G9, G10, G12, G14) hold mostly by care.

## A. Memory safety with no collector

### G1. No read or free of dead storage, no double free, no leak

- **Claim.** A program the compiler accepts never reads or destroys a dead allocation, never destroys one twice, never
  consumes a borrowed value, never lets a stack value escape, and leaks nothing at a normal return. Task groups are
  included.
- **Level.** Proved for the final IR. Validated on every guest build by every compiler since 11 November (the IR
  verifier and the ownership validator run in `build`, `run` and `test`).
- **Evidence.** `Own.check_sound` (`proofs/ownership/Soundness.lean`), `Own.runs_sound` and `Own.main_no_leak`
  (`proofs/ownership/Program.lean`). The validator's checks J1 to J8 (`src/core/validate_ownership.zig`). Gate action
  `ownership-proof`, which compares the Zig validator with the Lean checker on every certificate the language gate
  writes and on mutants. The rule-by-rule table is "Proof coverage" in `docs/ownership-rules.md`, held by
  `src/ownership_reference_test.zig`.
- **Rests on.** Trust points A1 to A18 and A7.1 to A7.8 (`proofs/ownership/AXIOMS.md`): the exporter, the C runtime's
  contracts, LLVM. A13 to A15 are enforced by both checkers and not covered by the theorem; A18 (frame storage) is not
  modelled. A7.2 also carries the view a task's environment holds for a view parameter (FR58): the validator does not
  follow that loan through the box. A build with `--no-validate` is outside the claim.
- **Not claimed.** That the source checker (`src/core/single_owner.zig`) is right. A hole in it is caught by the
  validator, as an internal error.
- **To raise it.** Close A14 and A18 (L6 of `docs/audits/lean-proof-candidates-2026-11-11.md`).

## B. Checked arithmetic at native speed

### G2. A removed check cannot fail, and the integer operations compute what they say

- **Claim.** An interval the optimizer states holds, a block it states dead is never entered, and an overflow,
  division, shift or bounds check it removes as proven could not have failed. Nine integer operations compute the
  mathematical result and trap exactly when they should.
- **Level.** Proved. Validated on every `--release` build that computed facts; a debug build defers the fact validator,
  and a Debug compiler validates every build.
- **Evidence.** `Facts.fact_certificates_sound` (`proofs/facts/Facts/Theorem.lean`); checks F1 to F7
  (`src/core/validate_facts.zig`); the operation theorems of `proofs/arith`. Gate actions `ownership-proof` (its facts
  half) and `arith-proof`.
- **Rests on.** Intervals accepted on trust for record, dictionary and call results (A6.1 to A6.3); additions justified
  by edge checks are counted, not validated; LLVM's semantics.
- **To raise it.** Derive the trusted intervals; count what rests on them (T0-3 of the proof audit).

### G3. The IR is well formed

- **Claim.** In the final IR every use is dominated by its definition, operands have the types their operation needs,
  and a function value points to a function with its type's signature.
- **Level.** Proved for the Lean copy of the verifier. Validated on every guest build.
- **Evidence.** `VerifyIr.modWf_of_verdicts` and `VerifyIr.payload_of_verdict` (`proofs/verify_ir/VerifyIr/SsaProof.lean`)
  and `VerifyIr.a17` (`proofs/verify_ir/VerifyIr/FnProof.lean`); `payload_of_verdict` proves the union-tag rule (a payload
  is read only under its own tag) sound for the Lean copy's tag semantics. `src/core/verify_ir.zig`. Gate action
  `verify-ir-proof`, which compares the Zig verifier with its Lean copy on the gate's IR and on mutants, and refuses the
  union payload reads the rule cannot justify.
- **Rests on.** V1 to V9 (`proofs/verify_ir/AXIOMS.md`).
- **Exception.** The union-tag rule landed on 11 November (lane VL, stage V4) and a build does not refuse on it: a build
  counts a union payload read that no test of its tag justifies (`selka build --stats` prints `union-tags: N`) and the gate
  refuses it, so a program the gate never sees can run with such a read (the user's decision, D-VL-18; V7). A `list_get`
  value read under a test of the element's tag (shape M, at most 10 in the gate's corpus) is accepted, and the proof does
  not cover it.

## C. The development loop

### G4. A warm build equals a clean build

- **Claim.** A build that reuses stored results produces what a build from nothing produces.
- **Level.** Proved for an abstract build algorithm. Compared at each landing by `scripts/corpus_exact.py`; a user can
  ask with `--verify-cache`.
- **Evidence.** `Cache.warm_eq_clean` and `Cache.session_eq_clean` (`proofs/cache/Cache/Theorem.lean`); gate action `cache-proof`.
- **Exception.** The Zig code does not yet follow the proved algorithm: raw reads remain outside the recorded handle.
  The proof audit counted seven silent cache-key defects in a month, the most of any proved area.
- **To raise it.** The engine move and the key-closure lemma (L5 of the proof audit).

### G5. An edit costs what the change costs

- **Claim.** A build or a test run after an edit does work in proportion to the edit, not the repository.
- **Level.** Measured.
- **Evidence.** The figures in `CLAUDE.md` ("Measuring guest programs"), taken with a ReleaseFast compiler on the 99k
  and 400k ports.
- **Exception.** Selection is exact, but cost still follows repository size, and three exits of the test-loop plan are
  unmet (`docs/audits/test-loop-plan-2026-11-09.md`, section 10.4).
- **To raise it.** A budget per edit kind that the gate measures.

### G8. `check` and `build` give one verdict

- **Claim.** A program `check` accepts is a program `build` accepts.
- **Level.** Gated.
- **Evidence.** The ownership matrix, `test/ownership_matrix_cli_test.zig` (1,775 cells, none accepted and
  unbuildable); `src/core/check_build_agree_test.zig`, `test/check_build_agree_redo_cli_test.zig`,
  `src/core/check_build_corpus_test.zig`.
- **Exceptions.**
  - `@noalloc` is judged only at build (G8-X1; W14).
  - A typed hole is refused by `check`, built as a trap by a default build and refused by `--release` (G8-X2).
  - A plain `bytes` parameter given to a task (rule Z3, an executed example in `docs/ownership-rules.md`).

## D. Run time

### G6. Run time within reach of Zig and Rust

- **Claim.** A release build runs within about 1.10 times the same program in Zig or Rust.
- **Level.** Measured.
- **Evidence.** The parity suite and the port's release timings (`port:docs/S1B-REPORT.md`).
- **To raise it.** Track instructions, not wall time, in a recorded budget.

## E. Local reasoning

### G7. A caller is judged from signatures alone

- **Claim.** Whether a function is accepted, and what it does, depends on its own text and the signatures it names,
  never on another function's body.
- **Level.** Gated for calls across modules; Probed for calls within one module.
- **Evidence.** A module interface keeps a function's body only for the roles in `Role` (`src/module_interface.zig`): a
  generic template, a constant, a conversion, a foreign declaration and a function a constant evaluates; every other body
  is `pass`. The test `W9 the interface roles are a closed list and only declared bodies are replaced by pass`
  (`src/module_interface_test.zig`) fails when a role is added, removed or renamed or starts or stops keeping its body,
  and `W9 roleOf by example` pins the rule that picks a role. Gate action `interface_oracle` (step `test-interfaces`)
  runs the interface oracle (`selka interfaces oracle`, driver `tests/interface_oracle.py`), which checks every module
  of the language suite, the interface fixtures and the ownership fixture (the callers of
  `tests/fixtures/interfaces_ownership/lib.selka`), 669 modules on 12 November, against its imports' interfaces, where an
  ordinary body is `pass`, and against their full sources, and requires the same front-end results and the same Core refusals, of the ownership pass and of the
  `@noalloc` promises (`src/core/interface_ownership.zig`); a mutant that makes a caller's verdict read a callee's body
  fails it (`W9 the mutant ...` in `src/core/interface_ownership_test.zig`). Pinned examples G7-H1 to G7-H3. A bare call of a
  prelude name is always the builtin (`E_BUILTIN_FUNCTION_NAME`, `src/builtin_function_names.zig`, tested in
  `src/builtin_function_names_test.zig`; W6): pinned examples G7-H4 to G7-H6. A generic body is judged at its declaration
  for every kind of type argument its bounds admit, a text, a record with a managed field and a list beside a scalar
  (`diagnostic.Probes.declaration`, `src/sema_specialize.zig`; `test/check_generic_bodies_cli_test.zig`; W3): pinned
  examples G7-H7 and G7-H8. A `match mut` arm's binding keeps its place for every payload type: replacing the matched
  value before the binding's last use is refused (`src/match_mut_test.zig`; FX9): pinned example G7-H9.
- **What it rests on.** The oracle's fixed set: the language suite holds accepted programs only, so the refusals compared (12
  on 12 November) all come from the ownership fixture. A module is compared with its own bodies on both sides, so a call
  within one module is not covered. A module's test file may name the module's private declarations, which no interface
  carries, so the oracle checks a test file against the full source of the module it tests (FX10, 14 November): that one
  import is not judged from its interface.
- **Exceptions.**
  - Whether a local list or record owns or borrows is inferred from the whole function body (G7-X3 to G7-X6): a later line
    can make an earlier one an error. Since W2 the refusal names that later line in a note and `selka dump-typed` shows each
    local's status; whether the status should be written instead is the open decision Q2.
  - `@noalloc` reads callee bodies (G8-X1; W14).
  - An import hides a builtin (G7-X8; W6).
- **To raise it.** Within a module: an oracle that checks each function with every other function of its module stood in
  by its declaration, as an interface stands in another module's. Across modules: more refused callers in the oracle's
  set, for example the shapes of `src/ownership_rule_sites_test.zig` split across two modules. The known exceptions are
  reported by the oracle as known (`known_differences`), never failed: today only `@noalloc` (G8-X1) shows there.

## F. Nothing implicit

### G9. No hidden copy, no generated state machine, no implicit call

- **Claim.** What a function does is what its text says. The compiler adds no copy the source does not spell, generates
  no state machine, and never calls user code that is not named at the call.
- **Level.** Validated on every build for copies: every guest build checks its final IR and refuses a copy no source
  wrote (`E_CORE_HIDDEN_COPY`), with `--no-validate` as the way out, and the frame block and the dictionary-key copy are
  counted, not refused (N5). Probed for the rest of the claim.
- **Evidence.** Pinned examples G9-H1 to G9-H14: closures, comprehensions, module state, import cycles, dropped values,
  mutation during iteration, shadowing and a catch-all after a complete match are refused; evaluation happens once and
  in order; `try` and `fail` convert an error into an enum case only when exactly one case fits (`E_ERROR_CASE_AMBIGUOUS`
  otherwise); `old(x)` of a managed place is written `old(copy(x))` (`E_CONTRACT_OLD_COPY` otherwise). `selka cost
  --sites` and the hidden-copy check read one list of copy sites, and `cost --sites` labels each one written, a named
  operation, or implicit (`src/core/copy_sites.zig`). A standard-library function the compiler supplies is declared
  `builtin func`, with no body, and every spelling of its call is the operation (G9-H14; `src/builtin_functions.zig`).
  There are no destructors, operator functions or module initialisers in the language.
- **Exceptions.**
  - A dictionary key is copied when new (G9-X3). Decided on 12 November 2026: the one documented implicit copy, labelled
    "implicit (dictionary key)" by `selka cost --sites` and counted by the hidden-copy check.
  - A frame block copies a parameter when the caller passes a slice, and always for `bytes` (G9-X5; W4, W18, Q8).
  - An update made on a copy is lost with no diagnostic (G9-X6; W7).
  - An integer above 2^53 changes value in mixed arithmetic (G9-X7; decision Q7).
- **To raise it.** A lemma over the ownership certificate that an accepted function has no unwritten copy operation would
  make "no hidden copy" Proved; refusing the frame block (decision Q8) would leave the dictionary-key copy as the one
  implicit copy.

### G10. One meaning in every build mode

- **Claim.** A program behaves the same under `run`, a debug build, `--release` and `--unoptimized`, apart from speed
  and resource limits.
- **Level.** Gated on generated programs: the gate builds 13 generated programs (312 functions) in several modes and
  requires them to agree; nothing compares the modes on the language suites or on programs people write.
- **Evidence.** Gate action `mode_differential` (driver `tests/mode_differential.py`, item GEN): fixed seeds give small
  valid programs over integers of every width near their limits, floats, texts, records, lists, dictionaries, sets,
  options, unions with `match` and `match mut`, loops, `mut` parameters, `fails` and `try`, `take` and `exchange`; each is
  built with the plain build, `--release` and `selka test`, one in four also with `--debug-o0`, `--unoptimized` and
  `selka test --unoptimized`, and every function's printed value, trap and test verdict must agree, with no internal
  error in any mode. A `bool` function's test returns the value, so its verdict must be what `main` prints. With lane FX3's
  fix reverted the action fails on two of its programs. Pinned examples G10-H1 to G10-H3: a `debug(...)` line evaluates its arguments, once each and left to
  right, in every build mode, a `build --release` binary included (before 12 November such a binary dropped the whole
  line). G10-H4: a list element that always overflows traps `R_OVERFLOW` in every mode (before 12 November `--release`
  and `selka test` refused it with `E_FACT_VALIDATION`); `src/core/trapping_elements_test.zig` checks 26 shapes of it.
  G10-H5: an operation on a value that always overflows (a shift count, a divisor) traps `R_OVERFLOW` in every mode (before
  12 November the compiler crashed in every build that runs the fact pass); `src/core/trapping_operands_test.zig` checks 24
  shapes of it. G10-H6: a vector loop with a loop-invariant byte operand builds and agrees in every mode (before 12 November
  every build that vectorizes failed with `ToolFailed`); `src/core/vector_test.zig` builds and runs one invariant of each
  width against the lanes. The Core tests of `src/core/debug_arguments_test.zig` lower with `drop_debug` set, check that the calls and the
  element read stay and that nothing is written, and run the result with the leak check on, in the gate. The release half
  of `src/core/cli_flags_test.zig` builds real `--release` binaries and runs only under `-Dtest-release=true`. The
  mode-by-mode table of the two probes is in the write-up of item W5.
- **Exceptions.** None known.
- **Not exceptions.** Allocation counts differ with `--unoptimized`. `selka test` adds step, frame, time and memory
  limits. A release binary writes nothing for a `debug(...)` line, and that is the line's output, not its meaning.
- **To raise it.** W5b: the gate builds each language-suite program in three modes and compares output and status. It
  waits for release builds to return to the gate (the decision of 28 October 2026). The generator covers no capability,
  text formatting specification, generic record, module boundary or concurrency; widening it widens the claim.

### G11. No ambient authority

- **Claim.** Output, files, time, randomness, the environment and processes are reached only through a capability
  parameter that starts at `main`.
- **Level.** Gated.
- **Evidence.** `E_OUTPUT_CAPABILITY`, `E_UNUSED_CAPABILITY` and `E_TASK_CAPABILITY` (pinned as G11-H1, G11-H2 and
  G11-H3; tested in `src/io_print_test.zig`, `src/effects_test.zig` and `src/core/task_capability_test.zig`). A `Filesystem`
  narrowed by `fs.dir` follows no symbolic link in any run, so it cannot be used to reach what lies outside its directory
  (tested in `src/io_paths_test.zig`, "a directory narrowing refuses them the same way in a run with no restriction", and in
  `tests/lang/filesystem_symlinks.selka`). An append through a final link under a grant is refused the same way, and writes or
  creates nothing outside it (tested in `src/io_paths_test.zig`, "an append under a grant refuses a final link", and in
  `tests/lang/filesystem_symlinks.selka`, "an append through a link is refused").
- **Exceptions.**
  - `debug` writes to standard error with no capability (G11-X1).
  - A capability is shared state, and a plain parameter can change it (G11-X2; decision Q9, by design).

### G12. A lend cannot be told from a copy

- **Claim.** Replacing every read-only lend by a copy changes no program's result, only its cost. This is what lets a
  function be read as a mathematical function of its arguments.
- **Level.** Stated: it follows from the Exclusion rule and nothing tests it.
- **To raise it.** W19: the reference semantics has no lends, so agreement with it is this goal. Stage S8 of the
  proof-steps plan is the cheaper differential.

## G. Parts that work alone work together

### G13. A contract is never skipped

- **Claim.** A `@requires`, `@ensures`, `@invariant` or `assert` is checked in every build mode unless the compiler
  proves it cannot fail.
- **Level.** Validated at run time. A clause reported proved is removed under G2.
- **Evidence.** The traps `R_REQUIRES`, `R_ENSURES`, `R_INVARIANT`, `R_ASSERT`; the executed examples of
  `docs/contracts.md`; `selka cost FILE --clauses`. Pinned example G13-H1: a `match mut` write breaking an invariant
  traps at the write.
- **Exceptions.** None known. A write through a `match mut` payload binding into a field of a record with an
  `@invariant` is checked since item FX7b (G13-H1); before it, no check followed such a write.
- **To raise it.** L2 of the proof audit: make "every write to a record with an invariant is followed by its check" a
  checked property of the final IR.

### G16. A protocol between calls can be a type

- **Claim.** A value that must be used exactly once, and a state that only its own module can construct, can be
  declared, so that a call order is checked and not a convention.
- **Level.** Gated, for must-use values and for sealed construction.
- **Evidence.** `@linear` records (landed 11 November): `src/linear_rules_test.zig`; `@sealed` records (landed 12 November,
  W11): `src/sealed_rules_test.zig` and `tests/lang/sealed_records.selka`; pinned examples G16-H1 to G16-H5.
- **Exceptions.** None reproduced on 12 November: a `@sealed` record is built and changed only by its own module and that
  module's test file. Until item FX8b (13 November) a `match mut` of a `@linear` owner counted as its consumption, so a
  program could drop the owner unconsumed; it now lends the owner (G16-H5).

### G17. A failed call says what it did to its arguments

- **Claim.** A caller can tell from a signature whether a failed call left its `mut` arguments as they were.
- **Level.** Stated.
- **Exception.** A failed call keeps every write it made before failing, and no signature says so (G17-X1; W15).

### G18. An identity belongs to its owner

- **Claim.** An index, a handle or an id cannot be used on a collection it did not come from.
- **Level.** Probed.
- **Evidence.** One-field records are distinct types at no cost (G18-H1).
- **Exception.** A `pool` handle reads another pool's slot, a hand-built handle works, and `symbols` accepts another
  table's symbol (G18-X1; W17).

## H. Simple syntax

### G14. One spelling for each thing

- **Claim.** Each operation, type and form has one spelling, and a diagnostic never advises a spelling the compiler
  refuses.
- **Level.** Stated. There is no written grammar to hold it against.
- **Evidence.** The gate test of W8, `src/advice_tables_test.zig`: every replacement that a message of the three advice
  tables (`src/retired_methods.zig`, `src/removed_names.zig`, `declaration_hints` in `src/parser.zig`) names in backquotes is
  built into a program that must check clean, so a diagnostic never advises a spelling the compiler refuses. About 90
  advice strings in other files are not covered yet (the W8 write-up under `experiments` lists them by file). Since
  W13-S5 an operation on text, bytes, a buffer, a list or a set has one spelling, the function: every method form and
  second spelling is refused with its rewrite, so one `selka fix` moves a project across (the grid of every row
  against every receiver shape, lane W13-S5's write-up). Pinned examples G14-H1 to G14-H4.
- **Exceptions.** Work item W21.
  - Marker words usable as names (G14-X4).
  - A reserved internal name that blocks a capability method (G14-X5).
  - A one-hole f-string (G14-X6, G14-X7).
  - A literal match on a text field (G14-X8).
  - `try` in a call's argument or an operand, beside the value declared first (G14-X10; TRYARG and TRY-2, the user's
    decisions).
- **To raise it.** A grammar file checked against the parser (W21), and the advice strings outside the three tables moved
  into them.

## I. Toolchain

### G15. The toolchain needs no Python

- **Claim.** Building the compiler and every command of the installed compiler run no Python.
- **Level.** Gated.
- **Evidence.** `USE-WITHOUT-PYTHON-1` in `test/integration.zig`, which runs the user commands under an empty `PATH`.

## Rules for keeping this page true

1. A plan says which goal ids it touches, in its "Stops" section. A change that would add an exception needs a decision.
2. A fix for an exception updates its pinned example and this page in the same change. The example failing is the
   reminder.
3. A level goes up only when the evidence named in "To raise it" exists and is named here.
4. An audit updates this page. It does not start a new list of goals.

## Changes

- 11 November 2026: first draft, from `docs/audits/language-goals-audit-2026-11-11.md`,
  `docs/audits/implicit-code-audit-2026-11-11.md` and `docs/audits/lean-proof-candidates-2026-11-11.md`. Pinned examples
  verified on main `2d371a50a`.
- 12 November 2026 (item W24): the gate action `goals_register` checks this page and the pins. "How this page is checked" now
  states the format it reads. Entries that did not follow it were changed in form only: G4 names its theorems with the
  `Cache.` namespace; G6 writes the port's report as `port:docs/S1B-REPORT.md`; the exceptions of G8 and G14 are nested
  bullets and G10's single exception is `**Exception.**`.
- 12 November 2026 (W9): G7 is Gated for calls across modules. The `Role` list is pinned by a test, and the interface
  oracle compares Core's ownership and `@noalloc` refusals.
- 12 November 2026: W8. The `try` position exception of G14 (`try` inside an expression reported a type error) is fixed and its example is now
  G14-H1; the exceptions of G14 go from 7 to 6, and the gate test of the three advice tables is named as its evidence.
- 12 November 2026 (item W1): G9's exception "`try` converts an error into the first enum case that fits" is fixed: `try`
  and `fail` convert an error only when exactly one case fits, and refuse with `E_ERROR_CASE_AMBIGUOUS` otherwise. Its two
  pinned exceptions became G9-H10 (two fitting cases are refused) and G9-H11 (one fitting case converts); G9 has 5 open
  exceptions and W4 alone raises it to Validated.
- 12 November 2026 (item W5): G10 has no open exception. A `build --release` binary evaluates the arguments of `debug(...)`
  and drops only the formatting and the write; the two pinned exceptions are now held examples G10-H1 to G10-H3. W5 did not
  address G11-X1 (`debug` writes to standard error with no capability): the example and its exception stand.
- 12 November 2026 (item W2): G7's exception about borrowing locals stays (G7-X3 to G7-X6; the inference is unchanged, decision
  Q2), reworded: the refusal now carries a note at the line that made the local own, and `selka dump-typed` prints each
  local's status. G9-X6 stays an exception, since a `copy` written by hand still loses an update with no diagnostic, but
  `selka fix` no longer writes that copy by itself for a binding a later line writes through.
- 12 November 2026 (item W6): G7's exception "a module function silently replaces a builtin" is fixed: a module function or
  a re-export with a prelude function's name is refused when its own module uses the name bare (the user's narrowed rule,
  and "same rule" for re-exports), with the rename as its repair. The pinned exception became G7-H4, beside G7-H5 (a
  qualified call of such a function is accepted) and G7-H6 (a re-export is refused). G7 has 4 open exceptions; G7-X8 (an
  import hides a builtin) stays.
- 12 November 2026 (item W3, step 1): G7's two generic-body exceptions stay exceptions; nothing changes by default. The developer command
  `selka template-stand-ins FILE.selka` counts what judging generic bodies at their declaration would refuse (every template
  tried with `int`, `str`, a record, a list and a resource); the count and the decision it asks for are in W3's write-up.
- 12 November 2026 (item W7, step 1): G9-X6 stays an exception, and nothing changes for a user by default. A count exists:
  `selka lint FILE --rule=dead-write` reports the writes no later read sees (off in every profile, report only; see
  `docs/tooling/lint.md`), and the W7 write-up (experiments/audit-work-20261111/W7.md) holds its count over the repository
  and the three projects.
- 12 November 2026 (item W4): `selka cost --sites` and the hidden-copy check read one list of copy sites, the frame block
  included, and `cost --sites` labels each copy written, a named operation, or implicit. G9's exception "`old(x)`
  deep-copies at every call" is fixed: `old(x)` of a managed place is refused (`E_CONTRACT_OLD_COPY`) unless written
  `old(copy(x))`, which `selka fix` writes; its pin became G9-H12 (the refusal) beside G9-H13 (the written copy). G9-X3
  stays an exception, decided: the dictionary-key copy is the one documented implicit copy, labelled by the tools. G9-X5
  stays, with decision Q8 open. G9 has 4 open exceptions; the check still runs only under `--verify-facts`, so G9 stays
  Probed.
- 12 November 2026 (item W10): G9's unpinnable exception "some library functions have a body that never runs" is gone.
  The 90 functions the compiler supplies are declared `builtin func` with no body, a test holds each declaration to the
  compiler's own table, and every spelling of a call (an alias, a re-export, keyword or type arguments) is the operation;
  the new pin G9-H14 holds it. Nothing of it is left: the library's remaining bodies all run. G9 keeps 4 open exceptions
  and stays Probed.
- 12 November 2026 (item N5): the hidden-copy check runs in every guest build, debug and `--release`, under the policy of
  the IR verifier and the ownership validator (`--no-validate` turns it off; a final record says `validated` only when the
  check passed it). G9 is Validated on every build for copies and Probed otherwise; its exceptions are unchanged (4).
- 12 November 2026 (item W3, step 2): G7's exception "a generic body's ownership verdict depends on who instantiates it" is
  fixed: `check` judges every generic body at its declaration for every kind of type argument its bounds admit and refuses
  it there, naming the type parameter and the kinds, with ` from x` or `copy(...)` as the fix. The pinned exceptions became
  G7-H7 and G7-H8; G7 has 3 open exceptions.
- 12 November 2026 (item FX2): G3's exception is brought up to date. The union-tag rule it called in flight landed on
  11 November (lane VL, stage V4, decision D-VL-18): the verifier counts a payload read no tag test justifies in a build and
  the gate action `verify-ir-proof` refuses it, with the theorem `VerifyIr.payload_of_verdict` behind the rule. What remains
  is that a build does not refuse, and shape M. G3 keeps 1 open exception and its level.
- 12 November 2026 (item FX2): the example runner learned `# doc: expect-trap R_CODE` (`selka doctest`: the example runs and must
  stop with that runtime trap), so G10-H2, the one pin that was skipped because a trap counted as a failed run, now runs. No
  pin is skipped. G10 keeps 0 open exceptions and its level.
- 12 November 2026 (item FX3): a list element whose checked arithmetic or conversion always overflows traps in every mode;
  `--release` and `selka test` refused such a program with `E_FACT_VALIDATION`, because the fact pass stated the list's
  elements from the never-produced value's empty interval. New held example G10-H4. G10 keeps 0 open exceptions and its
  level.
- 12 November 2026 (item FX5): an operation that reads a value whose checked arithmetic always overflows (a shift count, a
  divisor, an exclusive-or, a loop bound) traps in every mode; the fact pass crashed the compiler on three of them in every
  build that runs it, and stated loop facts the validator refused on others. New held example G10-H5. G10 keeps 0 open
  exceptions and its level.
- 12 November 2026 (item GEN): G10 is Gated on generated programs: the gate action `mode_differential` builds 13 generated
  programs in up to six modes and requires every function's value, trap and test verdict to agree. The one difference it
  found on its seeds, a test returning `not A and B` that passed when the value was False, was fixed by item FX4 before
  it landed. G10 keeps 0 open exceptions.
- 12 November 2026 (item W11, step 2): `@sealed` records landed: only the declaring module and its `<module>_test` file build
  one, write its fields, `replace` or `take` it, or take it as a test input (`E_SEALED_RECORD`). G16's exception, "any
  code can construct the next state directly", is fixed; its pin became G16-H4, a two-module protocol whose forged
  state is refused. G16 has 0 open exceptions and is Gated.
- 12 November 2026 (item FX7): a vector loop with a loop-invariant operand narrower or wider than an `i64` builds in
  every mode; every build that vectorizes refused it with `ToolFailed` (clang read the splat's type wrong), and so did a
  function with more than twenty vector loops (two values named alike). New held example G10-H6. G10 keeps 0 open
  exceptions and its level. G13's exception list is brought up to date: the `@invariant` that a `match mut` write skips
  (lane W11's probe) is open, so G13 has 1 open exception; its designs wait for the user (FX7, item 3).
- 13 November 2026 (item FX7b): G13's exception is fixed, by the user's decision of 13 November ("Check after writes"):
  after each write through a `match mut` payload binding, every record with an `@invariant` on the matched place is
  checked, read from the place's root, as after a direct write. New held example G13-H1 (the probe that printed -5).
  G13 has 0 open exceptions.
- 13 November 2026 (item DL5): this page and CHANGES.md merge by union (`.gitattributes`), so two lanes' entries no longer
  conflict. The check gains the two findings that union can leave behind, a second summary row for a goal and a labelled
  bullet given twice in one entry. Of the 18 hand merges of this page in the last 10 days, union leaves three with such a
  repeat, and the new rules refuse all three and none of the 18 hand resolutions.
- 13 November 2026 (item FX8b): by the user's decision of 13 November (LIN, "Should `match mut` stop counting as using up a
  `@linear` value?": yes), a `match mut` lends a `@linear` owner and does not end it. Its binding is read, written and
  lent `mut` in place (refused before as "already consumed"), and a program whose only use of an owner was a `match mut`
  is refused. New held example G16-H5. G16 keeps 0 open exceptions and its level.
- 13 November 2026 (item FX9): the user's decision HOLD. A write that replaces the matched value of a `match mut` (or a
  container of it) while a payload binding of the arm is still used afterwards is refused for every payload type, as it
  was already for text and lists. New held example G7-H9. G7 keeps its open exceptions.
- 14 November 2026 (item W28): the user's decision Q1. A task may not take a capability that reads or writes the outside
  world: `Stream`, `Filesystem`, `Network`, `Clock`, `Entropy`, `Environment`, `Process` and `Input` are refused as a
  task argument or a map's items, directly or inside a record, list, dictionary, option or union (`E_TASK_CAPABILITY`;
  `Host` keeps `E_TASK_HOST`). Tasks that shared a `Stream` printed in a different order from run to run; that program is
  now refused, the new held example G11-H3. G11 has 2 open exceptions.
- 15 November 2026 (item W13-S5): the W13 warnings became refusals (`E_METHOD_REMOVED` for a method on text, bytes, a
  buffer, a list or a set; `E_REMOVED_SPELLING` for a second spelling such as `math.min`, the bare `unwrap_or(x, d)` or
  `exists(fs, p)`). The three exceptions of W13 are now held examples G14-H2, G14-H3 and G14-H4; G14 has 4 open
  exceptions. G16's pin of a pool handle writes the option's method, the one spelling of `unwrap_or`.
- 16 November 2026 (item FSDIR, the user's decision ACM-1): a `Filesystem` narrowed by `fs.dir` refuses symbolic links in every
  run, as it does under `--restrict`: a link on the way, at the end or as the narrowing's prefix is refused where a run without
  `--restrict` followed it out of the directory. The unnarrowed handle of such a run still follows links. G11 keeps its 2 open
  exceptions; the new tests are named in its evidence, and no pinned example was added (a documentation example runs in the
  gate's working directory, and a link it made would land in the repository).
- 16 November 2026 (item FSAPPEND, the user's decision of that day): an append (`open(path, "a")`) through a root other than the
  unnarrowed one of a run with no restriction refuses a symbolic link as the last component of its path, as every other call on
  that root did: under `--restrict` it had written through a link to a file outside the grant and created the file a dangling
  link names. G11 keeps its 2 open exceptions; the new tests are named in its evidence.
- 17 November 2026 (item TRYARG, the user's decision of that day): `try` is accepted as a call's argument, so `f(try g())` and
  the value declared first are two spellings of one program. G14 has a new exception, G14-X10, and goes from 4 open exceptions
  to 5; G14-H1 (`try` under an operator) still holds.
- 17 November 2026 (item TRYOP, the user's decision TRY-2): `try` is accepted as an operand of any expression computed at run
  time (`try f() + 1`, `if n > 5 and try ok(n):`, `assert try f() == x`), evaluated left to right. G14-X10 covers operands
  too; no new exception. G14-H1 now pins a `try` over an operator expression (`try (half(x) + 1)`), still refused.
