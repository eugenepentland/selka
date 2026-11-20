# Selka against three of its goals: local reasoning, simple syntax, provability (11 November 2026)

The question: the fast development loop is mostly met. Is there more to do for the other three goals (clear local reasoning,
syntax that is simple and easy to understand, a language that is easy to write Lean proofs for), even if it needs a large
refactor?

Read at main `5b2c6b5ef`. Nothing in the compiler was changed.

**Status: a write-up, nothing scheduled.** The user said on 11 November to keep this as a write-up for later, and then asked
for the changes of the companion audit (`implicit-code-audit-2026-11-11.md`) to be added to it. **Section 9 is the one list of
work from both audits, with every open decision.** Section 10 answers how to keep the language's goals and the evidence behind
each in one place; the register it proposes now exists as a draft, `docs/goals.md`.

## Short answer

1. **Local reasoning holds for ordinary code and fails in seven named places.** A non-generic function is checked against the
   signatures it names and nothing else; the compiler's own interface files prove it, because they replace every such body with
   `pass`. The failures are: generic bodies, the inferred owner-or-borrower status of a local, `@noalloc`, the remaining
   check-accepts-build-refuses cases, builtin names a module can silently replace, `debug(...)` in release builds, and tasks
   that share a capability. Five of the seven have a small fix (changes 1, 2 and 4 below, and option (a) of decision D1).
2. **The syntax that programs use is small; the syntax the compiler carries is not.** The port uses about 25 forms heavily.
   Around them sit a half-finished move from methods to functions, 78 reserved words of which 29 are internal or retired,
   marker words (`own`, `mut`, `copy`) that are not reserved at all, 22 families of retired forms, and no written grammar.
   Several diagnostics advise a spelling the compiler then refuses.
3. **The proofs are sound and expensive to extend, and they say nothing about source programs.** Five Lean developments
   (34,272 lines, no `sorry`) each define the IR again. Nothing defines what a Selka program means, so nothing can be proved
   about lowering, and a proof about a user's function has no object to be about. The two changes that would matter most are a
   reference semantics of the source language written in Lean, and one description of the IR that the compiler and every proof
   are generated from.

Section 1 ranks the changes. Sections 2 to 4 give the evidence per goal. Section 5 lists the decisions that are yours.

**Method.** My own probes (31 small programs, kept in `experiments/language-goals-audit-20261111/probes/` with their verdicts),
and three read-only research agents: a census of the surface syntax, a census of non-local dependencies, and a census of what
makes the Lean proofs large. I reran every agent claim this document leans on; the ones I did not rerun are in section 7.
Counts in real code are from the EDA port (`netlisp-selka-redo`, 126,614 non-test lines) and `selka-protobuf` (6,557
hand-written lines). Every hour figure is an estimate, and this week's estimates for agent-built work ran several times too high.

## 1. Ranked changes

| # | Change | Serves | Estimate (lane-hours) | Breaks programs? |
| ---: | --- | --- | ---: | --- |
| 1 | An ownership refusal about a borrowing local names the statement that caused it, and tools show each local's status (R2) | reasoning | 6-12 | no |
| 2 | A generic body is judged where it is declared, for every kind of type argument (R1) | reasoning, proofs | 6-14 | only templates that pass for `int` alone |
| 3 | No diagnostic advises a spelling the compiler refuses, held by a gate test (S2) | syntax | 6-12 | no |
| 4 | A builtin name cannot be redeclared; `debug(...)` evaluates its arguments in every build (R5, R6) | reasoning | 3-8 | rarely; with a `mylang fix` |
| 5 | Locality becomes a tested property of the compiler (R0) | reasoning | 4-8 | no |
| 6 | One home for each operation: finish the move from methods to functions (S1) | syntax | 10-20 | yes; mechanical `mylang fix` |
| 7 | `@noalloc` becomes a contract in the signature, judged by `check` (R3) | reasoning | 8-16 | yes; 0 uses in the port |
| 8 | A reference semantics of the source language in Lean: a spike first (P3) | proofs | 10-15, then 60-120 | no |
| 9 | One table of IR operations and one of runtime functions, generated into Zig and Lean (P1) | proofs | 25-50 | no |
| 10 | Reserve the marker words, remove Selka's own retired forms, write the grammar down (S3 to S5) | syntax | 25-50 | yes; renames |
| 11 | Move runtime logic from C into Selka (P4) | proofs | 15-30 per file | no; run-time risk |
| 12 | One Lean definition of the IR for all the developments (P2) | proofs | 30-60 | no |

Changes 1 to 5 are small, certain and independent. Changes 8, 9, 11 and 12 are the large refactors. I would start 1 to 5 and the
spike of 8 together.

How these touch the development loop: change 2 adds a few representative checks per generic function (78 of the port's 5,662
functions are generic); change 7 replaces a build-time whole-program closure with a check-time test of one signature; changes
8, 9 and 12 run in the gate, never in the edit loop.

## 2. Local reasoning

The test: can a reader, or an agent, understand and safely edit one function from its own text and the signatures it names?

### 2.1 What holds, and should be protected

- **A caller is checked against signatures.** Two versions of a callee with one signature and different bodies give the caller
  the same verdict, for `mut` parameters, `from` results and records built from a parameter's fields. A result that borrows
  without a `from` clause is refused (`E_BORROW_UNDECLARED`); nothing is inferred from a body
  (`src/core/borrow_result.zig`: "No body-derived contract is inferred").
- **The compiler states its own exceptions.** A module interface keeps a function's body only for a generic template, a
  constant, a conversion, and a function a constant evaluates; "every other body is replaced by `pass`"
  (`src/module_interface.zig`, `Role`). That list is the complete set of reasons a dependent module reads a body.
- **Nothing is implicit at a call.** A plain parameter cannot be written (`E_IMMUTABLE`) or kept; a missing `mut` or `own` at
  the call is an error; arguments evaluate left to right; there is no overloading, no user-defined method call, no mutable
  module state and no closure.
- **Early exits are visible.** `try` is accepted only at the start of a statement's value (`E_TRY_POSITION` anywhere inside an
  expression), so every propagated failure sits at the left edge of a line.
- **The friction log agrees.** Of the port's 206 friction entries, none records an agent having to read another function's body
  to learn a verdict. The long hunts were bisections inside one function and the check-accepts-build-refuses cases.

### 2.2 Where it fails

**R1. A generic body's ownership verdict depends on who instantiates it.** Types are checked once against the declared bounds,
but ownership is checked per instance, and `check` tries an uninstantiated template with `int` only (`docs/generics.md`).

```mylang
func first[T](xs: T[]) -> T:
    const head = xs[0]
    return head
```

- With `first([1, 2, 3])` the program is accepted. With `first(["a", "b"])` the same body is refused, at the `return` inside
  the generic (`E_BORROW_UNDECLARED`). The message names neither the type nor the call (`generic_int.my`, `generic_str.my`).
- Across modules it is worse: `check lib.my` passes, and the error appears in `lib.my` when another module first passes a
  managed type. The port logged it (F-RA-801, still open).
- A body written with `copy(xs[0])` and `own x` is accepted for both (`generic_marked.my`), so the strict form already works
  for every type.
- **Change.** Judge each template where it is declared, with one representative per kind of argument the checker treats
  differently: a scalar, a text, a record, a list, and a move-only type where the bound allows one. Report an error that only
  an instance shows at the call, naming the instance, as a generic `from` mismatch is reported today. The larger form is one
  parametric verdict per template, which is what a proof per template would need; the representatives give the reader's
  guarantee without it.

**R2. Whether a local owns or borrows is inferred from the whole function body.** Three tables decide it, each a syntactic test
over every use of the local, shared by the checker and lowering (`src/core/single_owner.zig`):

| Table | A local or constructor borrows when |
| --- | --- |
| `borrowedMutLocals` | every store to a `mut` local is a bare read of a named place |
| `BorrowedRecords` | every managed field of a record constructor reads a place, at least one does, and the record is never stored or moved |
| `BorrowedCollections` | a `mut` list is made empty, never reassigned, every `append` stores a borrow or a text literal, every other use reads it, and it is never returned |

So the declaration `mut hits: Row[] = []` does not say what `hits` may do; the rest of the function does.

- Appending borrowed rows to `hits` and reading it is accepted (`borrow_list_ok.my`). Add one fresh row three lines later and
  the earlier `append` is refused (`borrow_list_mixed.my`). Move a write to the lender below the loop and the same `append` is
  refused (`borrow_list_later_write.my`). In each case the message is on the `append` and does not name the later line.
- `const r = Row(name=n, tags=t)` is accepted until a later `keep(own r)`; the error then lands on the constructor, three lines
  up, as `E_OWN_MARKER` (`borrow_record_later_own.my`).
- Whether `R(s=names[1])` borrows depends on the record's declaration: with a default `n: int = 0` it is accepted, with a
  default `tags: str[] = []` it is refused (`borrow_record_scalar_default.my`, `borrow_record_managed_default.my`; the port's
  F-RC-200).
- **What the inference bought.** In the port it removed 224 of about 3,560 `copy(` calls, worth about 1% of instructions and
  1.3 to 1.6% of wall time; 210 located sites still copy (`docs/S1B-REPORT.md` of the port, lane PB).
- **Change.** (a) Each of these refusals names the use that requires an owner, with a note at that line; where the cause is a
  field default, it says so. (b) `mylang check --typed` and `mylang context` print each local's status. (c) Whether to write
  the status in the declaration instead of inferring it is decision D2.

**R3. `@noalloc` reads the bodies of everything the function calls, and only at build.** Adding an allocation to a helper,
with no change to its signature, breaks a caller's promise. `check` accepts the program, `build` refuses it, and the error is
placed inside the helper (`noalloc_ok.my`, `noalloc_callee_allocates.my`). `mylang list-interfaces` does not print the
attribute. The port has no `@noalloc`; the standard library, tests and benchmarks have 37.

- **Change.** A `@noalloc` function may call only functions that declare `@noalloc`, plus operations known not to allocate.
  `check` judges it, the error is at the call, and the interface lists it. `mylang fix` can add the attribute down a call tree
  wherever today's closure proves it. The no-trap promise planned as S4 of the proof-steps plan should take this form from the
  start; that plan already notes it must be judged without whole-program facts.

**R4. `check` accepts and `build` refuses.** The port lost 207 minutes to five such entries. The reproducers the census reran
no longer split on main, and the ownership matrix has no such cell. What remains: R3; a plain `bytes` parameter given to
`group.submit` (rule Z3, documented); and hidden copies, which by `src/core/pipeline.zig` are refused only by a Debug compiler
or under `--verify-facts`. Running the
build's placement inside `check` was costed at 10 to 20 hours on 10 November and deferred. Nothing new to recommend beyond R3.

**R5. A module function can replace a builtin without a word.** A module that declares `func len(n: int)` and `func abs(n:
int)` compiles with no warning, and every `len(...)` in that module now means the module's function (`builtin_replaced.my`
exits 108). `import sort` makes the builtin `sort(mut xs)` unreachable (`import_hides_builtin.my`). Locals are inconsistent:
`const str` is `E_SHADOWING`, `const len` is accepted. A reader cannot know what `len(x)` means without scanning the module.

- **Change.** One rule: a prelude name cannot be redeclared by a function, a local or an import. The standard library already
  reaches its intrinsics under internal spellings, so `math.sqrt` does not need the exception.

**R6. `debug(...)` behaves differently in a release binary.** Its arguments are not evaluated there, so `debug(xs[i])` with a
bad index traps under `mylang run` and in a debug binary and exits 0 from a `--release` binary (`debug_release.my`). It is also
the one way to write output without a capability.

- **Change.** Evaluate the arguments in every build and drop only the write, or refuse `debug` under `--release`.

**R7. Tasks that share a capability are not deterministic.** Three tasks printing to one `Stream` gave 16 different outputs in
60 runs (`tasks_shared_stream.my`). The guide says so ("Scheduling is not ordered"). Every other capability except `Host` and
open files may be passed to a task. No project uses tasks: the port, protobuf, the SQLite binding and `examples/` have no
`parallel.` call; `tests/lang` has 62. This is decision D1.

### 2.3 Accepted, with a note

- **Constants run function bodies at check time**, so an edit to a function can move an error to a constant elsewhere. The
  interface marks those functions (`evaluated`).
- **A capability can be kept by a plain parameter** (`ctx.log = out`), because capabilities are shared handles. It is the one
  exception to "a plain parameter cannot keep its argument", by the design of 5C.
- **A dictionary key is copied without `copy(`** when it is new (`dict_key_copied.my`), while the value beside it needs
  `copy(...)` (`dict_value_needs_copy.my`). `docs/functions.md` documents it. The reference's rule C1 ("copies are written")
  should name this exception.
- **Types that are not written:** `return 3` into `int?` and `return v` in a `fails` function wrap; `if x is None: return`
  changes the type of `x` below it; a literal takes the type of its context. All are local to the function.
- **A callee's cost can depend on the caller's argument.** A record that holds a plain text, bytes or list parameter uses a
  frame block, which copies once per call when the argument is a slice or any `bytes`. `build --stats` reports the sites. Only
  the view fold removes it, and that was decided against on 10 November (D7).

### 2.4 Keep it true

**R0.** Locality is true today because of care, not because anything tests it. Two cheap guards: a gate test that pins the
`Role` list, so a new reason to keep a body in an interface fails until someone decides it; and the interface oracle
(`mylang interfaces oracle`) extended to Core's ownership pass, so that a caller's verdict from interfaces alone is compared
with its verdict from full sources over the language suites. (Whether the oracle already covers Core is not verified; on one
probe it reported no difference where Core raises an error.)

## 3. Syntax

### 3.1 How big it is

| Part | Count | Note |
| --- | ---: | --- |
| Declaration forms | 12 | plus 8 attributes; `result Name:` and `resource Name:` are live and undocumented |
| Statement forms | 22 | |
| Expression forms | about 31 | 24 operators, 12 integer-operation words, 8 width casts |
| `for` header shapes | 7 | `enumerate`, `zip` and `range` are loop words, not values |
| Pattern forms | 9 | plus `match mut` and `match own` |
| Names available without an import | about 104 | `mylang docs operations` lists 41 |
| Reserved words | 78 | 27 structure a program and 9 are type names; 9 are capability internals, 14 start with `__`, 6 are retired, 12 are integer operations, 1 is `todo` |
| Diagnostic codes | 422 | 22 are `E_..._REMOVED` families |
| Ownership rules | 54 | the view-fold plan's section 8 offers 45 or 34 by refiling; undecided |

What the port's 126,614 lines actually use:

| Used heavily | Uses | Used rarely or never | Uses |
| --- | ---: | --- | ---: |
| `mut` at a call or place | 12,128 | all 8 attributes | 0 |
| `func` | 5,662 | `with`, `named`, `extern`, bind-or-else, `zip`, `Result[T, E]` annotations | 0 |
| `for` / `while` | 3,729 / 405 | `parallel.` | 0 |
| `Some(` | 3,856 | `enumerate` | 1 |
| `copy(` | 3,342 | f-strings | 3 (protobuf: 225) |
| `match` | 2,003 | `match mut` | 7 |
| `try` / `fails` / `fail` | 1,734 / 698 / 834 | `exchange(` | 15 |
| `own` markers | 1,703 | `for ... in own` | 19 |
| `record` / `enum` | 1,236 / 236 | generic functions | 78 |

The port was translated from Zig, so it underuses the Python-shaped forms (f-strings, `enumerate`); protobuf, written fresh,
uses them. The rare column is where to look before adding anything, not a removal list.

### 3.2 Findings

**S1. Operations have two homes, and which one is live depends on the argument count.** Collection methods were retired in
favour of functions (69 rows in `src/retired_methods.zig`), but the move stopped partway:

- `s.split(",")` is refused and `s.split()` is accepted; `s.strip()` is refused and `s.strip("x")` is accepted
  (`method_with_argument.my`, `method_without_argument.my`).
- 32 file and process operations are both a method and a bare function: `fs.exists(p)` and `exists(fs, p)`
  (`capability_two_spellings.my`).
- `abs`, `min`, `max`, `round`, `floor`, `sqrt` exist in the prelude and in `math`, with different signatures (`math.abs` is
  `-> int fails str`). `parse_int(s)`, `s.parse_int()` and `strings.to_int(s)` are all live. `sets.add` and `sets.include`
  differ only in who copies.
- **Change.** One rule a reader can hold: `x.name(...)` means `x` is a module, a capability or a handle; text, bytes, lists,
  dictionaries, sets and options have functions only. File operations keep the method form and lose their 32 bare names, which
  takes the prelude from about 104 names to about 72. Each retired method already names its replacement in the diagnostic; this
  finishes the table.

**S2. Diagnostics advise spellings the compiler refuses.** In an agent's loop each one costs a round trip.

| Diagnostic | Advice | What happens |
| --- | --- | --- |
| `del xs[0]` | write `_ = xs.pop(index)` | `E_METHOD_REMOVED` (`del_advice.my`) |
| removed `mutates(...)` | write `name: mut T` | refused; the form is `mut name: T` |
| `sets.add(mut seen, e.key)` | write `copy(e.key)` | then `W_NEEDLESS_COPY`: pass `e.key` to `sets.include` (`set_add_lent.my`, `set_add_copy.my`) |
| `a && b` | "`&` was removed; write `mut value`" | the answer is `and` |
| `sum += try half(x) + 1` | `E_TYPE` expected Result, found int | the cause is `try` inside an expression (`try_inside_expression.my`) |
| signatures in messages | `list[bool]`, `Option[int]`, `-> None` | all three spellings are refused in source |

- **Change.** The structured `fix` of a diagnostic is already tested by applying it. Do the same for prose advice: a gate test
  extracts each backquoted replacement from the message tables and checks that it parses and resolves.

**S3. The reserved words are the wrong ones.** `acquire_resource`, `clock_now`, `random_u64`, `domain`, `arena`, `wrap` and
`conversion` are reserved, so `entropy.random_u64()` cannot be written (`reserved_method_name.my`) and `f(type=1)` is an error.
The words that carry the language's meaning are not reserved: `mut own = 1`, `mut mut = 2` and `const copy = 3` compile
(`marker_words_as_names.my`), and `own [1]` is an unknown name because `own` is only a marker before an identifier.

- **Change.** Reserve the markers (`own`, `mut`, `copy`, and probably `take`, `exchange`, `try`). By a rough count the port
  uses `own` as a name 19 times and `copy` 7; `from` (125) and `fail` (70) are common field and local names and should stay
  contextual. Stop reserving the internal names in the lexer; the parser already refuses them in user code
  (`E_INTERNAL_NAME`). Make the 12 integer-operation words ordinary prelude functions.

**S4. Retired forms are still in the parser, the syntax tree and the token set.** By the census's file list and greps: 22
dedicated files (4,696 lines), about 500 lines of `parser.zig`, 25 token kinds nothing lexes to, and syntax-tree nodes for
lambdas, comprehensions, tuples and domains. They are two different things:

- **Python forms** (lambda, comprehension, tuple, `a if c else b`, `del`, `try`/`except`, methods on collections). Agents will
  write these from habit for as long as the language looks like Python. Recognising them and saying what to write instead is a
  permanent feature. Keep it, as one table.
- **Selka's own past** (`domain`, `arena`, `wrap`, `class`, `host func`, `effects`, `noio`, `mutates`, borrow views, the
  `module` header). Nobody will write these again once the projects have migrated. Remove them, after a search of the projects
  shows no use.

**S5. There is no grammar.** `docs/python-syntax.md` teaches by example over 802 lines; the inventory in 3.1 had to be read out
of `parser.zig`. A grammar file would be the reference for agents, the generator of test programs (the earlier audit's section
6), and the target for the self-hosted parser, which otherwise copies the parser's accidents. With S4 done it fits on two
pages.

**S6. One-line irregularities, each cheap.**

- `const s = f"{a}"` is refused (`E_OWN_MARKER`) and `f"x{a}"` is accepted: a one-hole f-string is treated as the hole
  (`fstring_single_hole.my`).
- `match entry.text:` with a literal arm is refused (`E_LITERAL_ARM`); the same match on a local or a parameter is accepted
  (`match_text_field.my`, `match_text_local.my`). It is filed under rule C1 and is a lowering limit.
- An enum case is built qualified (`Shape.rect(w=1.0, h=2.0)`) and matched bare (`case rect(w=w, h=h)`); a qualified pattern is
  refused at the top level and accepted when nested; a bare name in a nested position is a binding, not a case.
- `Result[T, E]` is accepted as the type of a local or a field and refused as a return type.
- An option is read six ways (`is None`, `is Some(v)`, `match`, `const v = x else None:`, `unwrap_or`, `try`), and narrowing
  works on a name and not on a field.
- An `@invariant` is checked after every field write, so two writes that together keep it trap between them
  (`invariant_two_writes.my`; `replace(...)` is the way). This is the simplest rule to reason and prove with, so it is worth
  keeping, but it is the first thing a new writer hits and belongs in the message.

## 4. Proofs

"Easy to write Lean proofs for the language" has two readings: proofs about the compiler and the language, and proofs about
programs written in it. The earlier audit of today (`lean-proof-candidates-2026-11-11.md`) ranked which compiler parts deserve
a proof next. This section asks what in the design makes every proof cost what it does.

### 4.1 Where things stand

- Five developments, 34,272 Lean lines, no `sorry` and no `axiom`: ownership 14,680, facts 11,330, `verify_ir` 3,251, arith
  2,640, cache 2,371. They rest on 83 numbered trust points and 5 unnumbered gaps.
- They are all about the final IR. Nothing covers the type checker, lowering, the optimizer's passes or the C runtime, and
  nothing says whether the source checker enforces any of the 54 rules.
- For programs: contracts exist, the facts prove about 9% of them (10 of 115 in the trial; the first step of S2 landed and did
  not change that), 37 of 55 clauses the trial wanted cannot be written, and nothing exports a function to a prover.

### 4.2 What makes them expensive

| Cause | Evidence |
| --- | --- |
| **The IR is defined three times in Lean** | `proofs/ownership` (operations as strings with read and consume lists, a heap, no values), `proofs/facts` (44 operations, 66 of the IR's folded into `other`, integers, no heap), `proofs/verify_ir` (one-to-one, types only). Three text formats, three exporters (1,244 Zig lines), three parsers, dominators proved twice, and a 241-line file that only translates one model into another. The two soundness theorems are about different machines, so there is no single statement about a program both validators accept. |
| **The IR is not shaped for checking** | An instruction's `data: u64` is a flag, a block, a callee, a tag or a field path depending on the operation, and operand roles are positional (`src/core/ir.zig`). One of the verifier holes found this week came from that (stray operand fields that were never checked, F-VL-8). The ownership class of each operation is a table written beside the emitter (trust point A1). |
| **Runtime calls are an open set** | Lowering can declare any runtime function by name (`runtimeFunction`). In the gate corpus 92,781 of 107,433 calls go to runtime, extern or marker functions and are judged for arity only (A5). |
| **A third of the operations exist to call C** | About 33 of 108 operations (dictionary 12, text about 14, buffer 6, sort 1). About 6,400 of the runtime's 13,777 lines are logic, not operating-system interface: text 1,860 plus 747 of tables, sort 925, dictionary 487, value copy 447, bytes 221, SHA-256 187, number text 1,473 in Zig. The Selka standard library wraps them (`dicts.my` is 89 lines). |
| **`mut` write-back and takes** | Trust points A8, A13 to A16 and about 960 Lean lines. Closing A14 is costed at 25 to 40 hours and a multi-result IR form for A16 at 50 to 80, by their own notes. |
| **Borrowed values** | A12 and A18 and about 1,200 Lean lines; frame blocks (A18) are not modelled at all. |
| **Task groups** | 8 of the ownership proof's 25 trust points; tasks are not modelled. No project uses them (R7). |
| **Removing integer checks** | The facts and arith developments are 41% of all Lean and hold 32 trust points. This is the price of run-time parity, not a design fault. |
| **No source semantics** | `SPEC.md` is frozen, there is no interpreter, and lowering (11,360 lines) makes at least a dozen decisions no document states: how a `mut` argument is written back to a nested place, how `take` rebuilds its path, when `for x in own xs` transfers, where drops go. The typed tree has 57 expression kinds, 12 statement kinds, 40 binary and 43 unary operations. |

### 4.3 Changes

**P1. One table of operations and one of runtime functions.** A data file states, for each IR operation, its operands with
their roles and types, its result, its ownership class, whether it can trap or allocate, and its fact rule or "opaque"; and for
each runtime function its signature and the same properties. The Zig enum and tables and each Lean model's operation type are
generated from it, and lowering may call only listed functions. This closes the "written beside the emitter" half of A1,
narrows A5, removes the positional-operand class of verifier hole, and gives `@noalloc`'s allow-list and S4's trap list one
source.

**P2. One Lean definition of the IR.** Since 11 November the compiler writes the final IR as text (`program.core-ir`). The
ownership and fact certificates can become annotations on that one text, read by one parser into one syntax, with each
development keeping its own abstract machine. A new property (the earlier audit's L2 and L3, or a pass witness) then costs a
checker and a proof, not another exporter, format and parser. A single machine with both values and a heap is research-sized
and worth it only if proofs of optimizer passes are wanted.

**P3. A reference semantics of the source language, in Lean.** An interpreter of the typed tree with plain value semantics: a
lend is a copy, a `mut` argument is copied in and out, and ownership does not exist. Lean compiles it to a native program, and
the gate runs the language suites through it and requires the same verdicts and output as the compiled tests. One artifact is
then four things the project lacks:

- the definition of what a program means, which no document gives;
- the test oracle of decision LP5, for lowering, passes and emission, where this month's worst bugs were found by luck;
- the evidence of S8 (a lend equals a copy), because the reference has no lends;
- the object a proof about a user's function is about, and what S6's export to Lean has to agree with.

It is deliberately outside the product: the interpreter was removed from the compiler on purpose, and this one runs only in
the gate. The long pole is text formatting and the operations implemented in C. A spike (10 to 15 hours) covers integers,
booleans, records, lists, options, control flow and traps, and reports how many `tests/lang` tests it runs.

**P4. Move logic from C into Selka** (decision LP4, open). Sort, the dictionary, text operations, value copy and number text can
be Selka if the standard library gets one internal primitive: storage with capacity apart from length. Each file moved removes
IR operations, removes a runtime contract from the trusted base, and puts the code under both validators. The dictionary's
probing and the sort are tuned; measure each move.

**P5. Programs.** Keep the proof-steps plan, and reorder it by its own trial:

- `fail`-path postconditions first: the largest class of clauses that cannot be written (15 of 37), and it needs no prover.
- Sealed types (S5) and the promise not to trap (S4) in R3's signature form.
- The prover spike (S6) after P3's spike, so the export has something to be checked against.
- Record two facts in every interface, both derivable today: a function with no capability parameter and no `mut` parameter is
  pure (once R6 is fixed), and a function with no `while` and no recursion, whose callees are the same, terminates. An exported
  definition of such a function needs no state and no termination proof.

## 5. Decisions for the user

- **D1. Tasks** (R7, 4.2). Groups cost two ownership rules (K1, K2), 7 of the 8 task trust points and the `g.submit` and
  `t.result()` forms; `parallel.map` alone needs one trust point. No project uses either. Options: (a) refuse a capability
  that can write or read the outside world as a task argument, which makes tasks deterministic and is cheap now; (b) also
  narrow the surface to `parallel.map` until a program needs groups; (c) keep everything and model the join protocol (the
  earlier audit's L4, 15 to 30 hours). Recommended: (a) now, and decide (b) against (c) when the first real program wants
  concurrency.
- **D2. The status of a borrowing local** (R2). Keep inferring it and fix the messages (change 1), or write it: one word on the
  declaration of a local that holds loans, checked statement by statement. Recommended: keep inferring, and add no further
  inferred shape. Stages 3 and 4 of the record-borrows plan (mixed records, `mut` out-parameters; held) would each add another
  whole-function condition. If they are wanted, that is the point to switch to a written status.
- **D3. PD1 of the proof-steps plan**, still open: never add returned or stored `mut` borrows, capturing closures, shared
  mutable identity or ambient effects. Recommended: adopt it, with one addition: the reasons a dependent reads a body stay the
  ones in `module_interface.Role`.
- **D4. Which large refactor first.** Recommended: P3's spike, then P1. P3 is the only change here that makes proofs about
  programs possible at all, and its spike is cheap enough to decide by result.
- **D5. Breaking cleanups** (changes 6, 7 and 10). Each needs a `mylang fix` migration and a pass over the port, protobuf and
  the SQLite binding. Recommended: 6 first, because it removes the most surprises per line changed.

## 6. Not recommended, or already decided

- **The view fold** (one layout for text, bytes and lists, 80 to 150 hours). It would remove frame blocks, A18's clause and
  five rule ids, and it was decided against on 10 November (D7) because no measured program needs it and every program would
  pay for it. Nothing in this audit changes that; P1 and P3 do more for proofs at less risk.
- **Lifetimes, regions, reference counting, implicit copies, dropping the `mut` and `own` markers.** All are earlier decisions,
  and the markers are what makes section 2.1 true.
- **A proof that lowering preserves meaning.** P3 gives a differential test of it, which finds the bugs; the proof remains a
  research project.

## 7. What this audit did not verify

- The totals of trust points (83 and 5), their attribution and the attribution of Lean lines to features, the count of about
  33 operations that call C, the typed tree's kind counts and the size of lowering are one agent's reading and greps. My own
  count of the operation enum is 108; the agent's is 109.
- Frequencies in the port and protobuf are regular-expression counts over stripped source.
- Whether the interface oracle already covers Core's ownership pass (R0).
- Whether release-only inlining can change a caller's build verdict when a callee's body changes: the documents suggest it, and
  no probe showed it.
- Whether the retired Selka forms of S4 are unused in every project.
- The port's whole-program IR could not be dumped to count borrowing locals: `mylang dump-ir src/main.my` reached the
  compiler's 8 GiB ceiling in 11 seconds. So the cost of a written status in D2 (how many declarations would carry the word) is
  not known.
- Every hour estimate.

## 8. Small defects seen in passing

None is fixed. Each is one line for a cleanup lane.

- The Z3 message for a `bytes` parameter given to a task reads "does not support a task cannot take a bytes parameter yet ...
  yet".
- `mut domain = 1` reports "expected a newline" where `const domain = 1` reports a reserved word.
- `p.norm()` on a record reports `E_UNKNOWN_TYPE`.
- A typed hole in an unreached function fails `check` and passes `build`.
- `docs/primer.md` line 78 writes `{copy(args[0])}`, which the compiler itself flags as `W_NEEDLESS_COPY`.
- `docs/python-syntax.md` lists `case 1:` as rejected; literal arms are accepted.
- `mylang docs operations` says a name appears once; `abs`, `min`, `max` and `round` appear in the prelude and in `math`.

## 9. The combined work list (both audits)

Added on 11 November at the user's request. It merges the twelve changes of section 1 with the twelve of
`implicit-code-audit-2026-11-11.md`, and replaces neither audit's evidence: the "From" column says where each is argued.
"A" is this audit and "B" is the implicit-code audit. Where the two audits proposed the same thing it is one row. Estimates are
lane-hours, and all are estimates. Nothing here is started.

Main moved from `5b2c6b5ef` to `2d371a50a` while the audits were written (`@linear` records, validation in every compiler, the
`verify-ir-proof` gate action). All 56 probes of the two audits were rerun on `2d371a50a` that evening with the same results.

### 9.1 Small and independent

| # | Change | From | Estimate | Breaks programs? |
| ---: | --- | --- | ---: | --- |
| W1 | `try` converts an error only when exactly one enum case fits | B: I1 | 2-5 | only an enum with two cases of one payload type |
| W2 | An ownership refusal about a borrowing local names the statement that caused it; tools show each local's status | A: R2 | 6-12 | no |
| W3 | A generic body is judged where it is declared, for every kind of type argument | A: R1 | 6-14 | only templates that pass for `int` alone |
| W4 | One meaning of "hidden copy", checked in every build; `old(x)` of a managed value is written `old(copy(x))` | B: I2 | 8-16 | the `old(...)` spelling |
| W5 | `debug(...)` evaluates its arguments in every build; the gate compares the language suites across build modes | A: R6, B: I3 | 6-12 | no |
| W6 | A builtin name cannot be redeclared by a function, a local or an import | A: R5 | 2-5 | rarely; with a `mylang fix` |
| W7 | A write nothing can read is an error; `mylang fix` never inserts a copy that later writes go into | B: I4 | 8-16 | code with dead writes |
| W8 | No diagnostic advises a spelling the compiler refuses, held by a gate test | A: S2 | 6-12 | no |
| W9 | Locality is a tested property: the interface `Role` list is pinned and the interface oracle covers Core's ownership pass | A: R0 | 4-8 | no |
| W10 | A library function whose body never runs is declared as an intrinsic | B: I5 | 3-6 | no |
| W24 | The goals register (`docs/goals.md`) is checked in the gate: its pinned examples run, and every theorem, test and gate action it names is confirmed to exist | section 10 | 4-10 | no |

### 9.2 Medium

| # | Change | From | Estimate | Breaks programs? |
| ---: | --- | --- | ---: | --- |
| W11 | Sealed types: only the declaring module constructs the record, so a rule of representation lives in one place | B: 4.2; stage S5 of the proof-steps plan | 10-18 | no |
| W12 | A written idiom for state machines on `@linear` records, which landed on main on 11 November | B: 4.3 | 4-8 | no |
| W13 | One home for each operation: finish the move from methods to functions | A: S1 | 10-20 | yes; mechanical `mylang fix` |
| W14 | `@noalloc` becomes a contract in the signature, judged by `check` | A: R3 | 8-16 | yes; no use in the port |
| W15 | A fallible function can promise that its `mut` parameters are untouched on failure | B: I6 | 8-14 | no |
| W16 | Report-only lints for the unmeasured hazards (wildcard over an enum, an empty `unwrap_or` default, `fails str` on a public function, a flag that guards a call order), compared with the bug record before any becomes an error | B: I7 | 10-20 | no |
| W17 | Pool handles and symbols know their owner | B: I9 | 4-8 | the two modules' interfaces |
| W18 | `bytes` parameters carry their owner, so a whole `bytes` argument is lent, not copied | B: I10 | 10-20 | no |

### 9.3 Large

| # | Change | From | Estimate | Breaks programs? |
| ---: | --- | --- | ---: | --- |
| W19 | A reference semantics of the source language in Lean: a spike, then the full interpreter | A: P3 | 10-15, then 60-120 | no |
| W20 | One table of IR operations and one of runtime functions, generated into Zig and Lean; the reference of what each source form may copy, allocate and trap is generated from it | A: P1, B: change 12 | 25-50 | no |
| W21 | Reserve the marker words, remove Selka's own retired forms, write the grammar down | A: S3 to S5 | 25-50 | yes; renames |
| W22 | Move runtime logic from C into Selka | A: P4 | 15-30 per file | no; run-time risk |
| W23 | One Lean definition of the IR for all the developments | A: P2 | 30-60 | no |

Also carried, with no number: the small defects of section 8, and the proof-steps plan's own stages (the `fail`-path
postcondition, the no-trap promise, the prover spike), reordered as section 4.3's P5 says.

### 9.4 Suggested order when work starts

The plan for step 1 is `audit-work-plan-2026-11-11.md`. It located each item in the compiler and counted what each breaks,
and its section 2 corrects several rows of 9.1 (W5, W6, W7 and W10 above all).

1. W1 to W10. Each is independent of the others and of every decision below except Q6 (for W4).
2. W11 and W12, then W15: the three the bug record argues for.
3. W19's spike beside them: it is cheap and decides whether the largest refactor is worth doing.
4. W13, W14 and W21 as one pass over the projects, since each needs a `mylang fix` migration.
5. W20, then W22 and W23 as the proof work calls for them.

### 9.5 Every open decision

| # | Decision | From | Recommended |
| --- | --- | --- | --- |
| Q1 | Tasks: which capabilities a task may take, and whether groups stay or only `parallel.map` | A: D1 | refuse capabilities that reach the outside world now; decide groups when a program needs concurrency |
| Q2 | A borrowing local: keep inferring its status, or write it on the declaration | A: D2 | keep inferring, and add no further inferred shape |
| Q3 | A standing rule: no returned or stored `mut` borrows, closures, shared mutable identity or ambient effects (PD1), plus the "never" table of the implicit-code audit and the pinned `Role` list | A: D3, B: I0 | adopt it |
| Q4 | Which large refactor first | A: D4 | W19's spike, then W20 |
| Q5 | The order of the breaking cleanups W13, W14, W21 | A: D5 | W13 first |
| Q6 | The dictionary-key copy: keep it as the one documented implicit copy, or require `copy(k)` | B: D1 | keep it, labelled by the tools |
| Q7 | Mixed integer and float arithmetic: silent, explicit `float(n)`, or a trap when the conversion is not exact | B: D2 | the trap |
| Q8 | Refuse frame-block copies by default | B: D3 | yes, after W18 and a look at the port's five sites |
| Q9 | Capabilities that change state through a plain parameter | B: D4 | no change; name it in the reference as the one exception |
| Q10 | The order of W11, W12 and W15 | B: D5 | sealed types, then the failure promise; `@linear` has landed, so W12 is only its idiom |

**Answered on 12 November 2026, for lane W4.** Q6: "You can keep your recommendation": the dictionary-key copy stays as
the one documented implicit copy, and `mylang cost --sites` labels it "implicit (dictionary key)". A second question of
the lane, whether a managed value inside `old(...)` must carry a written copy: "Require it": `old(x)` of a managed place
is refused unless written `old(copy(x))` (`E_CONTRACT_OLD_COPY`, with its `mylang fix` repair). Q8 stays open.

## 10. Keeping the goals and their evidence in one place

The user asked how best to keep a list of the language's goals with the proofs that back each one, so that it can be consulted
later and so that there is confidence the goals have no bugs. This section is the recommendation and a first sketch.

**Drafted on 11 November, when the user said to draft it.** The register is `docs/goals.md`: 18 goals, G1 to G18, written
against main `2d371a50a`, which by then had `@linear` records and validation in every compiler. Its pinned examples are
`test/fixtures/goals/docs/*.md`: 51 examples that the existing example runner checks with
`mylang doctest test/fixtures/goals`. Two things differ from the sketch below. The pins are documentation examples, not `.my`
files with a new header, so no new tool was needed to check them. And three goals were added from the implicit-code audit: G16
(a protocol as a type), G17 (the failure contract) and G18 (identities). The gate action is not built; it is W24 in section
9.1. The sketch in 10.3 is kept as written, and `docs/goals.md` is the current version.

### 10.1 What a goal's entry has to say

"Proved" means different things for different goals, so the list is only useful if every entry states what kind of evidence it
has. Six kinds, strongest first:

| Level | Evidence | What it rules out |
| --- | --- | --- |
| Proved | a Lean theorem about every program the compiler accepts, with its trust points listed | the stated fault, for every program, as long as the trust points hold |
| Validated | a checker that runs on each program as it is built | the fault in that build |
| Gated | a test over a fixed corpus that runs in the gate | a regression on that corpus |
| Probed | small programs with a pinned verdict, kept but not in the gate | nothing by themselves; they show the state on the day they ran |
| Measured | numbers taken when someone asks | nothing; they record a state |
| Stated | a written rule | nothing |

Only the first two give "no bug of this kind", and only for the property the theorem or the checker states. For a design goal
such as local reasoning there is no theorem to prove; the honest top level is Gated. An entry therefore has:

- an id and one sentence a user would recognise;
- the exact property claimed, which is usually narrower than the sentence;
- its level, and the artefacts by name: the theorem, the validator's checks, the gate action, the test, the probe files;
- what it rests on: the trust points, by id;
- its known exceptions, each with a probe;
- what would raise it one level.

### 10.2 How to keep it honest

A list written by hand goes stale. The project already has the pattern that prevents it: `src/features.json` is checked against
the documents by `mylang doc-coverage`, and the proof-coverage table of `docs/ownership-rules.md` is held by
`src/ownership_reference_test.zig`. The same for goals:

- **One page, `docs/goals.md`**, one section per goal with the fields above. It is the page to open when asking "is this still
  true".
- **Pinned probes, `test/fixtures/goals/`.** Each program states its expected verdict. A known exception is a probe pinned to
  today's wrong or limited behaviour, so fixing it fails the test until the page is updated. The 56 programs of the two audits
  are the first set.
- **One gate action** that reads the page and fails when: a named theorem is missing from its development's axiom audit
  (`#assert_axioms`, which four of the five developments already run); a named gate action is not in the verification
  inventory; a named test does not exist; a probe's verdict differs from its pin; or a goal lists no evidence for its level.
- **Two habits.** A plan says which goal ids it touches, in its "Stops" section. An audit updates this page and does not start
  a new list.

A dashboard page can be generated from `docs/goals.md` for reading; the file in the repository stays the source, because only
the gate can check it.

### 10.3 A first sketch of the entries

From what the two audits and the earlier proof audit established. The levels are today's.

| Goal | Level today | Backed by | Rests on, or open exceptions | Next level needs |
| --- | --- | --- | --- | --- |
| G1. Memory safety: no read or free of dead storage, no double free, no leak at a normal return, tasks included | Proved for the final IR; Validated only by a Debug compiler | `Own.check_sound`, `Own.runs_sound`, `Own.main_no_leak`; checks J1 to J8; gate action `ownership-proof` | trust points A1 to A18 and A7.1 to A7.8; A13 to A15 and A18 are not covered by the theorem; optimised compilers do not validate yet (lane VT) | validation in every build; the source checker is not proved and need not be |
| G2. A removed arithmetic or bounds check cannot fail, and the integer operations compute what they say | Proved | `Facts.fact_certificates_sound`; the nine operation theorems of `proofs/arith`; gate actions `ownership-proof` (facts half) and `arith-proof` | intervals accepted on trust (A6.1 to A6.3); `edge-checked` additions counted, not validated | the trusted intervals derived |
| G3. The IR is well formed (definitions dominate uses, operands have their types) | Proved for the Lean copy, compared with the Zig verifier | `VerifyIr.modWf_of_verdicts`, `VerifyIr.a17`; differential on 443 programs | its gate action is in flight (lane VL); union payload tags trusted until its stage V4 | the gate action |
| G4. A warm build equals a clean build | Proved for an abstract algorithm; compared at each landing by the exactness tool | `warm_eq_clean`, `session_eq_clean`; gate action `cache-proof`; `--verify-cache` | the Zig code does not follow the proved algorithm yet; 7 silent cache-key defects in a month | the engine move, and the key-closure lemma (L5 of the proof audit) |
| G5. The edit loop costs what the change costs | Measured | the figures in `CLAUDE.md` | cost still follows repository size | a gate budget per edit kind |
| G6. Run time within reach of Zig and Rust | Measured | the parity suite and the port's timings | none listed | a tracked instruction budget |
| G7. Local reasoning: a caller is judged from signatures alone | Probed | `module_interface.Role`; the probes of this audit | R1 generics, R2 borrowing locals, R3 `@noalloc`, R5 builtin names | W9 makes it Gated; W2, W3, W6, W14 remove the exceptions |
| G8. `check` and `build` give one verdict | Gated | the ownership matrix (1,775 cells) and the check-build agreement tests | `@noalloc`, a `bytes` parameter to a task, a typed hole | W14 |
| G9. Nothing implicit: no hidden copy, no generated state machine, no implicit call | Probed; the hidden-copy check runs only under `--verify-facts` | the refusals in section 2 of the implicit-code audit; `E_CORE_HIDDEN_COPY` | frame blocks, the dictionary key, `old(...)`, the `try` conversion | W1 and W4 make it Validated; a short lemma over the ownership certificate could make "no unwritten copy" Proved |
| G10. One meaning in every build mode | Probed | five-mode probes | `debug(...)` in a release binary; `todo[T]()` | W5 makes it Gated |
| G11. No ambient authority: output, files, time and randomness arrive as parameters | Gated | `E_OUTPUT_CAPABILITY`, `E_UNUSED_CAPABILITY`, the capability tests | `debug`; shared providers (Q9); tasks (Q1) | a statement of what a capability-free function cannot do, tested |
| G12. A lend cannot be told from a copy (value semantics) | Stated | the Exclusion rule | not tested | W19: the reference semantics has no lends, so agreement with it is this goal |
| G13. A contract is never skipped | Validated at run time; a proved clause is Proved by G2 | `R_REQUIRES`, `R_ENSURES`, `R_INVARIANT` in every build | two write paths still skip an invariant (`match mut` on an option field, a computed index) | L2 of the proof audit |
| G14. Syntax with one spelling per thing | Stated | none | section 3 of this audit | W8, W13, W21; the grammar as the Gated artefact |
| G15. The toolchain needs no Python | Gated | `USE-WITHOUT-PYTHON-1` | none | none |

Two things this table shows already. The goals with the strongest evidence are the three about the final IR (G1 to G3), and
the goals this audit was asked about (G7, G9, G10, G12, G14) are at Probed or Stated: they are true mostly by care. And the
cheapest gain in confidence is not a new proof: it is W4, W5 and W9, which move three goals from Probed to Validated or Gated
for about 18 to 36 lane-hours together.
