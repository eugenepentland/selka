# Nothing implicit: hidden code, hidden state, and bugs that appear when parts meet (11 November 2026)

The question: the language should have no implicit code (no hidden copies, no hidden state machines and the like), so that code
is easy to understand and there are fewer bugs where parts that work on their own fail when they meet. How close is Selka, and
what would close the gap?

Read at main `5b2c6b5ef`. Nothing in the compiler was changed. This is the companion of
`language-goals-audit-2026-11-11.md`; where the two overlap this one refers to it by id (R2, P1 and so on).

**Status: a write-up, nothing scheduled.** Its changes and decisions are merged into the one work list of both audits, section 9
of the companion (W1 to W24, Q1 to Q10). Section 10 there proposes a register of the language's goals and their evidence.

## Short answer

1. **The usual sources of implicit code are absent, and that should be written down as a rule.** The compiler generates no state
   machine: there are no generators, no async, no closures. No user code is ever called implicitly: no destructors, no
   operator or conversion functions, no module initialisers. There are no exceptions, no mutable module state, no import
   cycles, no shadowing, and a result cannot be dropped without `_ =`.
2. **What is still implicit falls in six groups** (section 3). Three copies nobody wrote. A choice the compiler makes for you:
   `try` converts an error into the first enum case that fits, so reordering an enum changes behaviour. A release binary that
   skips code a debug build runs. Then conversions, inserted checks, shared state behind capabilities, and library functions
   whose source is not what runs. The compiler's own two tools disagree about what a hidden copy is.
3. **The bugs that appeared when parts met were not caused by implicit code.** Of 48 application bugs recorded in Selka
   projects, 5 were caught by the module's own tests; the rest needed a whole-program comparison, a differential check or a
   review. The leading causes: two modules disagreeing about a rule of representation (10), an unstated protocol between calls
   (7), a default standing in for missing data (4), and an update made on a copy (3). The language features that answer these
   are sealed types, must-use values and contracts. Two are planned or in flight and none is used by the port.
4. **The hazards I expected did not show up in the record.** Wildcard arms, `take`, `unwrap_or` and sentinel returns exist by
   the hundred in the port and no recorded bug traces to one. They should be measured before any becomes a rule.

Section 1 ranks the changes. Sections 2 and 3 are the inventory. Section 4 is the bug record. Section 5 lists your decisions.

**Method.** My own probes (25 small programs, in `experiments/implicit-code-audit-20261111/probes/` with their results) and two
read-only research agents: one inventoried what the compiler, runtime and standard library do that source does not spell; one
read the decision logs, friction logs, lane notes and commit histories of the two EDA ports, the protobuf library, the SQLite
binding and the earlier project trials for application bugs. I reran the claims this document leans on; section 7 lists what I
did not. Every hour figure is an estimate.

## 1. Ranked changes

| # | Change | Closes | Estimate (lane-hours) | Breaks programs? |
| ---: | --- | --- | ---: | --- |
| 1 | `try` converts an error only when exactly one case fits (I1) | an implicit choice | 2-5 | only an enum with two cases of one payload type |
| 2 | One meaning of "hidden copy", checked in every build (I2) | hidden copies | 8-16 | `old(x)` of a managed value is written `old(copy(x))` |
| 3 | `debug(...)` evaluates its arguments in every build, and the gate compares the language suites across build modes (I3) | mode-dependent behaviour | 6-12 | no |
| 4 | A write nothing can read is an error, and `mylang fix` never inserts a copy that later writes go into (I4) | lost updates | 8-16 | code with dead writes |
| 5 | A library function whose body never runs is declared as an intrinsic (I5) | source that is not what runs | 3-6 | no |
| 6 | Sealed types: a rule of representation lives in one constructor (S5 of the proof-steps plan) | the largest bug class | 10-18 | no |
| 7 | `@linear` records land, with a written idiom for state machines | unstated protocols | in flight, plus 4-8 | no |
| 8 | A fallible function can promise that its `mut` parameters are untouched on failure (I6) | half-updated values | 8-14 | no |
| 9 | Report-only lints for the unmeasured hazards, compared with the bug record before any becomes an error (I7) | wildcards, defaults, string errors, flags | 10-20 | no |
| 10 | Pool handles and symbols know their owner (I9) | untyped identity | 4-8 | the two modules' interfaces |
| 11 | `bytes` parameters carry their owner, so a whole `bytes` argument is lent, not copied (I10) | the common hidden copy | 10-20 | no |
| 12 | A generated reference of what each source form may copy, allocate and trap (with P1 of the companion audit) | the inventory going stale | with P1 | no |

Changes 1 to 5 remove implicit behaviour the language has today and are small. Changes 6 to 8 are the ones the bug record argues
for. Decision D2 (mixed integer and float arithmetic) is not in the table because it is a choice, not a defect.

## 2. What the language never does

These hold today (each confirmed by probe or by the checker refusing the form) and nothing states them as a rule. They are the
reason a function can be read top to bottom.

| Never | How it is held |
| --- | --- |
| A compiler-generated state machine | generators, `async`, lambdas, comprehensions and `match` expressions are refused |
| An implicit call to user code | no destructors, operators, conversion functions, getters or module initialisers; user code runs only through a function value the program passes |
| Unwinding | a trap flushes the streams and exits; no cleanup code runs |
| Hidden mutable state in a module | a top-level `mut` is a syntax error; module constants fold at check time |
| A cycle between modules | `E_IMPORT_CYCLE` |
| A name changing meaning | `E_SHADOWING`, with the exception R5 of the companion audit |
| A dropped result or failure | `E_EXPLICIT_DISCARD_REQUIRED`, `E_RESULT_UNHANDLED` |
| Two aliases of one writable value | exclusive `mut`; `E_SINGLE_OWNER_OVERLAP` |
| A collection changed while it is iterated | refused at `check` (rule R7) |
| A task result read twice | refused at `check` (`E_TASK_HANDLE`) |
| A hidden order of evaluation | left to right; the index of `xs[f()] += 1` and the middle of `0 < f() < 10` are evaluated once |
| Sharing with copy-on-write or counts | none; an update in place is the only update |
| A catch-all after a complete match | `E_WILDCARD_ARM` |
| Trap order changing with the build | identical output in five build modes on four probes; inlined frames stay in the trace |

**I0.** Adopt this table as the second half of the standing rule PD1 (decision D3 of the companion audit): no feature may add a
row's opposite. It costs nothing and it is what the rest of this document protects.

## 3. What is still implicit

### 3.1 Copies nobody wrote

| Copy | When | What the tools say |
| --- | --- | --- |
| **Frame block** | A record or a list of borrows holds a plain text, bytes or list parameter. The callee copies it once per call when the caller passed a slice, and always for `bytes`. | `cost --sites`: "hidden copies: 1", `written: false`. `--verify-facts`, whose job is to refuse an unwritten copy, accepts the build. `@noalloc` refuses it. (`frame_block_copy.my`) |
| **Dictionary key** | `d[k] = v` and `sets.include(mut s, k)` copy `k` when it is new. | `cost --sites` calls it `written: true`. `W_NEEDLESS_COPY` tells the writer to use this form. Documented in `docs/functions.md`. |
| **`old(x)` in `@ensures`** | A deep copy of `x` at every call, in every build, even when the clause is reported proved. | 106 allocations for 100 calls of a one-line `grow` (`agent_ct2.my`); `cost --sites` calls it written. |

- The frame block is the only one whose cost depends on code elsewhere: the same callee copies or does not according to the
  argument each caller writes. It exists because records that hold borrows are inferred (R2), and it was accepted on 10
  November when trust point A18 was widened. The port's main program has 5 such sites among 22,126 allocation sites, so it is
  rare today. Every one of the five copies on every call if its parameter is `bytes`, which is the port's text type.
- The reverse also happens: a written `copy(x)` is deleted when `x` is dead afterwards (`agent_el2.my`). That changes cost only,
  and the compiler warns about most such copies already.
- Copies a named operation makes are not hidden: `a + b` on text, `sorted`, `.encode()`, a slice returned without `from`. The
  name is the spelling.

**I2. One meaning of "hidden copy".** Today `cost --sites` and the hidden-copy check use different lists, and the check runs
only under `--verify-facts`.

- The check counts frame blocks (`src/core/copy_sites.zig` omits `block_frame`), and it runs in every build.
- `cost --sites` reports three kinds: written, named operation, and implicit. Key copies and `old` copies are implicit.
- `old(x)` of a managed value is written `old(copy(x))`, so the copy is on the page; `old(len(x))` stays as it is.
- A project can then set "implicit copies are an error". With I10 the frame block copies only for a slice argument, and the
  setting can be on by default.

**I10. `bytes` parameters carry their owner.** Text and list parameters already pass their owner's block beside the view, which
is why a whole text argument is lent to a frame block without a copy. `bytes` parameters do not, so they always copy. Giving
them the same second word removes the common case. It is an ABI change inside the compiler, with a run-time cost to measure.

### 3.2 Choices and conversions

**`try` picks an enum case for you.** In a function that `fails AppErr`, `try parse(s)` where `parse` fails with `str` wraps
the text in the case of `AppErr` whose payload is `str`. If two cases carry `str`, it takes the one declared first, and `check`
says nothing.

```mylang
enum AppErr:
    Parse(value: str)      # try parse(s) yields AppErr.Parse(value='empty')
    Other(code: int)
```

Add `Io(message: str)` above `Parse` and the same line yields `AppErr.Io(message='empty')` (`try_converts_error.my`,
`try_converts_error_reordered.my`). An edit to a declaration in one place changes which error a call in another place reports.

**I1.** The conversion is allowed only when exactly one case fits; otherwise it is an error that asks for the case by name.

**Other conversions**, each local to the line it is on:

| Conversion | Note |
| --- | --- |
| `int` to `float` in mixed arithmetic, and `/` on two ints | exact below 2^53; above it the value changes silently: `9007199254740993 + 0.0` prints `9007199254740992.0` (`int_to_float_precision.my`). Assigning an `int` to a `float` is refused, so the rule is not uniform. Decision D2. |
| `return 3` into `int?`, an argument into a `T?` parameter, `opt == 3` | wraps in `Some` |
| `return v` in a `fails` function | wraps in `Ok` |
| a literal takes the width of its context | `u8(200) + 100` traps at width 8 |
| a slice clamps and an index traps | `xs[5:10]` of three elements is `[]`; `xs[5]` is `R_LIST_BOUNDS` (`slice_clamps.my`) |
| `round(2.5)` is 3.0 | Python gives 2 |

### 3.3 Checks and inserted control flow

- **Traps.** Every `+`, `-`, `*`, index, `/`, `d[k]` and narrowing cast can end the program. This is by design and is the
  alternative to undefined behaviour. The port's main program keeps 5,579 checks and proves 14,454 away. No tool lists the kept
  checks by site; stage S4 of the proof-steps plan would.
- **Contracts.** `@requires` runs at entry, `@ensures` at every `return` (not on `fail`), `@invariant` after every field write.
  They are visible in the declaration and in `list-interfaces`, not at the line that traps.
- **`mut` arguments.** A `mut` argument is copied out and written back: `bump(mut st.items[1].count)` becomes six operations
  (a read, the call, a second read and three stores) with two bounds checks. On the `fails` path the writes made before the
  failure are written back too (4.4).
- **Error traces.** Every `fail` and `try` records its site in a per-thread ring, in release builds too. It allocates nothing
  and is printed only when `main` returns an error.
- **`with`.** The exit runs on `return`, `fail`, `try`, `break` and `continue`.

None of these changes what a program computes. They are listed so that the reference can list them.

### 3.4 State

| State | Who can see it |
| --- | --- |
| **Capability providers** | Every copy of a capability shares one provider, and a plain parameter can change it: `tick(c: Clock)` advances the caller's clock and its alias (`capability_plain_parameter.my`). This is the design of 5C: the parameter's presence is the marker. It is the one case where a plain parameter changes something the caller can observe. |
| **`Entropy` and the real clock** | `mylang run` grants everything, so `Entropy` is seeded from the wall clock unless `--allow-random=SEED`. Tests get deterministic stand-ins. |
| **Tasks** | Tasks that share a capability interleave (R7 and decision D1 of the companion audit). |
| **The runtime** | Allocator free lists, stream buffers, the capability table, the worker pool and per-text caches are process-global and not visible to a program, except through `testing.allocations()` and the memory ceiling. Allocation counts depend on Core's passes: a split-and-iterate loop is 600 allocations with `--unoptimized` and 0 otherwise. |
| **Files** | `persistent_memo` and `durable` write and delete files through the `Filesystem` they are given. |
| **Field defaults and `take`** | A constructor that omits a field gets its default with no mark at the call. `take(mut place)` leaves an empty collection, `None`, or a record built from defaults; `take` of a type with no default is refused (`E_TAKE_TYPE`). |

Standard-library state (`memo.Cache`, `random.Random`, `pool.Pool`, `symbols.Table`) is an explicit value passed with `mut`.

### 3.5 Build modes and tests

- **A release binary skips code.** `debug(bump(mut counter))` runs `bump` under `mylang run`, `mylang run --release` and
  `mylang test --release`, and does not run it in a `mylang build --release` binary, which prints 0 where the others print 1
  (`debug_argument_writes.my`). `debug` is also the only output that needs no capability.
- **A test is a different program.** `mylang test` inserts a step count at the start of every block and applies 1,000,000
  steps, 1,024 frames, 60 seconds, 512 MiB and one thread. A correct 2,000,000-iteration loop passes `mylang run` and fails
  `mylang test` (`test_step_limit.my`). These are limits, not meaning, and the message names the flag.
- **`todo[T]()`** is refused by `check`, accepted by a default `build` (the binary traps `R_TYPED_HOLE` when it gets there),
  and refused by `--release` when `main` can reach it.

**I3.** `debug` evaluates its arguments in every build and drops only the write. The gate builds each language-suite program
with `--unoptimized`, the default and `--release` and requires the same output and status; nothing compares them today.

### 3.6 Source that is not what runs

`parallel.map` in the standard library is a sequential loop; a call lowers to a runtime entry and a generated worker. The
bodies of `dicts.get`, `keys`, `values`, `items`, `pop` and `clear` are "only checked, never called" (`src/stdlib/dicts.my`). A
reader who opens the library to see what a call does reads code that does not run.

**I5.** Declare such a function without a body, with a word that says the compiler supplies it, as `extern func` does for C.
The standard library is the only place the form is allowed.

## 4. Bugs that appear when parts meet

### 4.1 The record

48 application bugs in Selka code: 34 in code ported from Zig (the two ports of the EDA tool and a KiCad converter) and 14 in
code written fresh (protobuf, a Markdown renderer, an HTTP server). Compiler defects are excluded.

| Found by | Bugs |
| --- | ---: |
| The module's own tests, or the compiler | 5 |
| A whole-program golden comparison, or another lane's code calling it | 14 |
| A differential check or fuzz against a reference | 15 |
| An external conformance suite | 6 |
| Review, a migration, or a repro before landing | 8 |

- Twelve have their root cause in the contract between two modules.
- On the first three-lane merge of the first port every lane's suites were green and 6 of 34 whole-program outputs differed.
  Each of the three causes was one line.
- Ported unit tests caught 1 of 4 mutants of one module; the differential harness caught 39 of 48, and the other 9 were
  equivalent.

| Cause | Bugs | Example |
| --- | ---: | --- |
| Representation, encoding or normalisation differs across a boundary | 10 | Three callers hit one path helper: an absolute path lost its root, `./x` did not match `x`, `./backups` tried to create `.` |
| An unstated protocol or invariant between calls | 7 | A Markdown heading took the slot of a paragraph, because the helper it called closes the open paragraph first and appends it |
| Order: hash order, sort ties, evaluation order | 6 | Matching Zig's hash-map order; Selka's own dictionaries and sort are ordered and stable |
| Arithmetic or float text against the reference | 6 | A constant one unit in the last place off moved 388 results |
| A default or empty value stood in for missing data | 4 | A proto2 required field equal to its default was not written |
| An update made on a copy | 3 | `mylang fix` turned `mut scratch = self` into `copy(self)`; the module checked, the tests passed, and every write went to a discarded copy |
| An error contract between modules | 3 | A warning the reference prints was never printed |
| Local logic, and others | 9 | |

Three readings.

- **Ports and fresh code fail differently.** In the ported code, representation, order and arithmetic (19 bugs) are mostly
  "match the reference's bytes, order or digits". The fresh code leads with unstated protocols (4 of its 14).
- **Explicit state moved a hazard without removing it.** Selka has no module-level variable, so five of the Zig tool's
  singletons became values passed by hand. Two bugs are one caller not having the value.
- **The Zig original's own history points the same way.** 21 of its past bugs survive as comments in the port. Eleven are two
  modules disagreeing about one rule, or a check that silently did nothing because a lookup returned empty.

### 4.2 What each class needs

**A rule of representation in one place** (10 bugs, and 5 more "duplicated rule drifted" in the Zig original). The fix each
time was to put the rule in one function. Nothing in the language makes that stick: a `public record` can be built by any
module, so a `Path` or a `NetName` record cannot promise it was normalised. Sealed types (stage S5 of the proof-steps plan, not
started) are exactly this: only the declaring module constructs the value, and its `@invariant` states the rule. One-field
records already give distinct types at no cost: `NetId` and `PartId` do not mix, work as dictionary keys and build under
`@noalloc` (`typed_ids.my`). The port has 3 such records and 106 `int` fields and parameters named like an index or an id.

**Protocols** (7 bugs). See 4.3.

**Lost updates** (3 bugs). A copy is changed and the change is never read or written back. The compiler says nothing and
`mylang lint` reports nothing (`lost_update_on_copy.my`); the earlier `E_DEAD_RECORD_WRITE` no longer exists.

- **I4.** A write to a local, or to a field or element of a local, that no later read can see is an error. With value semantics
  and no aliases such a write is always dead code or a bug, and the ownership pass already knows each local's last use.
- `mylang fix` does not offer `copy(...)` as the repair for a `mut` binding that is later written or passed with `mut`. That
  repair is what produced the recorded bug.
- This does not catch a copy that is read later but should have been shared (a child scope holding a copy of its parent). That
  one is the model working as designed, and the answer is a pool or an index.

**Defaults** (4 bugs, and 6 "silent no-op" bugs in the Zig original). 46% of the port's record fields have a default, and 84%
of its 1,085 `unwrap_or` calls supply an empty value, zero or `False`. The failure is always the same: a missing value becomes
an empty one and a check passes. An option makes absence a different value, and the language has options. Nothing more is
recommended than the lint of I7.

**Errors** (3 bugs). All 698 fallible functions in the port fail with `str`; it has 193 string constants as error codes and 74%
of its `case Err` arms ignore the value. Protobuf, written fresh, uses error enums throughout. The three recorded bugs are a
warning never printed, a diagnostic raised where the reference only logs, and a message that blamed the wrong cause; none is a
mismatched string.

### 4.3 State machines

The compiler generates none. Programs contain them as flags and call order:

- 59 records in the port have two or more `bool` fields and 21 fields are state flags (`open`, `held`, `started`, `finished`,
  `locked`). 57 of 69 fields named `state`, `kind`, `mode` or `status` are already enums.
- About 10 are real begin-and-finish protocols. `infra/atomic_write.my`: `Staged` has `open: bool`; `staged_begin`, then
  `staged_write`, `staged_chmod`, and `staged_commit` or `staged_abandon`; each fails `err_not_staged` unless `open`. The type
  allows any order.
- 16 comments say "caller must", "assumes" or "before calling".

What the language has for this, and what is missing:

| Tool | State |
| --- | --- |
| An enum per state, with a match that must be complete | built; a wildcard after a complete match is refused |
| A transition that consumes the old state (`own`) | built, but `copy(d)` duplicates a state and any module can construct the next one: a draft is sent twice and a `Sent` is forged (`typestate_copy_and_forge.my`) |
| A value that must be consumed exactly once | `@linear` records, approved on 11 November and in flight on the FFI lane; the SQLite binding uses them and its misuse cases are check-time errors |
| A value only its module can build | sealed types, planned (S5), not started |
| A rule about a cursor or a slot | `@ensures`; protobuf writes them on its wire cursor, the port has none |

With `@linear` and sealed types together a protocol is a type: `staged_begin` returns a `Staged` that must reach
`staged_commit(own s)` or `staged_abandon(own s)`, and no other module can make one. The same mechanism answers one of the
seven protocol bugs directly: collision warnings were stored in a record that nothing printed, and a diagnostics value that must
be consumed cannot be dropped on the floor.

### 4.4 Hazards with no recorded bug

- **A failed call leaves its `mut` arguments half-updated.** After `withdraw(mut a, 25)` returns `Err`, the balance is -15 and
  the log has an entry (`fail_leaves_partial_update.my`). 471 of the port's 698 fallible functions take a `mut` parameter. A
  caller cannot tell from the signature which of them are safe to retry.
  **I6.** An attribute on a fallible function promises that on failure its `mut` parameters are as they were. The check is
  local to the callee: no write to a `mut` parameter comes before a `fail` or a `try` on any path. It is also the first
  `fail`-path postcondition, the largest class of clause the proof-steps trial could not write.
- **A wildcard absorbs a case added later.** 93 of the port's 181 `case _:` arms are over an enum, and 112 arms return a default
  or do nothing.
- **Errors as text.** A handler compares against `"NotFound"` and the callee fails with `"notfound"` (`error_string_mismatch.my`).
- **A handle used on the wrong owner.** A `pool` handle reads a slot of another pool with the same element type, a hand-built
  handle works, and `symbols.name` accepts another table's symbol (`pool_handle_wrong_pool.my`, `agent_pl.my`).
  **I9.** The pool and the table carry a tag given at creation, the handle carries it, and a lookup with the wrong tag is
  `None`. After sealed types the handle cannot be hand-built.

**I7.** For the wildcard, the `unwrap_or` default, `fails str` on a public function and a `bool` field that several functions
test before failing: add each as a report-only lint, run it over the port and protobuf, and compare its findings with the 48
recorded bugs and with the next ones. A lint that would have flagged none of them stays a report.

## 5. Decisions for the user

- **D1. The dictionary-key copy.** Keep it as the one documented implicit copy, labelled as such by the tools (recommended), or
  require `copy(k)` and always copy. The second costs a copy for every insert of a key that is already present.
- **D2. Mixed integer and float arithmetic.** Keep the silent conversion; require `float(n)`, as an assignment already does; or
  keep the form and trap when the conversion is not exact, as integer overflow traps. Recommended: the trap. It keeps the
  Python shape and removes the silent change of value.
- **D3. Frame-block copies.** After I2 they are counted. With I10 they remain only for a slice argument. Decide whether a
  project default refuses them (recommended once I10 has landed and the port's five sites are checked).
- **D4. Capabilities that change state through a plain parameter.** This is the design of 5C and I am not recommending a
  change. Say so in the reference's Exclusion rule as its one exception, beside decision D1 of the companion audit (tasks).
- **D5. The order of 6, 7 and 8.** Recommended: let `@linear` land with the FFI lane, then sealed types, then the failure
  promise. Sealed types answer the largest class and are additive.

## 6. Not recommended

- **Removing checked arithmetic and bounds checks from the list of implicit code.** They are the cheapest correct meaning of
  the operators. Listing the kept checks by site (S4) is the way to make them visible.
- **Refusing field defaults or `unwrap_or`.** No recorded bug traces to the form itself, and both are how fresh code states an
  intended default.
- **A rule against flag records.** Most of the 59 are bags of independent options. The protocols among them are better served
  by 4.3 than by a ban.
- **Making every allocation count identical across build modes.** Stack promotion and view fusion change cost only.

## 7. What this audit did not verify

- The 48 bugs, their classes and their "found by" are one agent's reading of decision logs, notes and commit messages. It read
  about 35 of the redo's 206 friction entries closely and scanned the rest; four class assignments are marked likely in its
  table. Detection is bounded by what the projects' oracles compared, so "no recorded bug" is not "no bug".
- The runtime's global state, the trap list and the per-thread error trace are from reading the C source, not from probes.
- Whether LLVM at `-O3` can reorder two traps; the probes showed no difference.
- Whether lane VT's work on validators in optimised compilers already runs the hidden-copy check in every build.
- The counts of flags, protocols, wildcards and defaults in the port are regular-expression and script counts.
- The frame-block count is from the port's pinned compiler of 9 November, before the list-of-borrows stage (H5) landed.
- Every hour estimate.
