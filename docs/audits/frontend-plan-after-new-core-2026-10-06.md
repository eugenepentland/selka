# The front end after the new core — plan, 2026-10-06

**Status: the user decided FE1–FE7 on 2026-10-06 (§7). Nothing here is implemented.**
The implementation plan is `docs/audits/frontend-implementation-plan-2026-10-06.md`.
This document stays the rationale and the record of facts. The work starts after
new-core stage S5 ("switch and delete"), when `mylang-core` is the only back end, except
for two early packages that touch only the new core or nothing.

**The user's goal (2026-10-06).** The language should work like Go: one way to
express each thing, so code is easy to read and performance is predictable. The
spelling stays Python's, because agents write Python first.

The evidence, the probes and the scripts are listed in §9.

## 1. Summary

The front end is fast enough. After `CATALOG-INTERN-1` (S4 §3.4), a merged check costs
0.45 s after an edit at 96k lines. A 12k-line program checks in 0.09 s. The reasons to
rework it are structure, surface and cost visibility:

- **The surface has second ways.** `src/features.json` lists 154 language features.
  About a dozen of them are a second spelling of another. Many second spellings have
  **zero uses** in the 26.8k lines of application code we have (§3.1).
- **Costs are hidden.** Whether a write copies a list depends on a runtime uniqueness
  test in about 8% of updates in the benchmark rows. Several O(n) operations look like
  O(1) operators (§3.2).
- **The front end does back-end work and whole-program inference.**
  - `typed.Program` is already desugared: it has 11 statement kinds and no `for`,
    comprehension, collection-literal or set nodes.
  - Two analyses (`effects`, `origins`) run call-graph fixed points whose results the
    signature-is-contract rules no longer need, but which two hashes still include (§5).
- **Eight caching layers with at least four identity schemes** were added to a
  whole-program checker after the fact, and they disagree on what an interface is (§5).

The plan has three parts:

| Part | What | Size |
|---|---|---|
| **A. One way** (§3.1) | Delete about 14 second spellings, each with a `mylang fix` migration | Small migrations: most have 0–70 uses |
| **B. Visible cost** (§3.2) | Per-function cost report first. Then rules that make copies and O(n) operations visible in source, decided on Lox/EDA data | Report: small. Rules: decided after measuring |
| **C. Front-end structure** (§5) | Source-shaped typed tree, desugaring moved to the core, local analyses, one generics path, one cache model, a lossless tree with error recovery | The bulk of the work; about 49k lines in scope |

Order (§6): delete dead code first (F0), then the cheap language deletions (F1), then
the structural work (F2–F4). The visible-cost rules come last (F5), once Lox and EDA
build under the new core and can be measured.

## 2. Where the front end will be after S5

- **The front end is 46.6k lines of Zig in 136 files.** That is everything reachable by
  `@import` from `sema.zig`, `parser.zig`, `lexer.zig` and `typed.zig`, without tests,
  on `codex/new-core-s3-integration`.
  - The front-end files did not change between `2e4f0f51` and `5ee5b8d2`.
  - Counting the embedded standard-library `.my` files, it is 48.8k lines in 150 files.
  - With the old back end deleted, it is about 72% of the compiler.

  | Group | Lines | Files | Largest |
  |---|---:|---:|---|
  | Sema core | 13.7k | 27 | `sema.zig` 2.1k, `sema_collections` 1.3k, `sema_expressions` 1.0k |
  | Generics and nominal types | 8.8k | 22 | `generic_bodies` 3.0k, `interfaces` 1.6k |
  | Whole-program analyses | 6.1k | 17 | `origins` 1.5k, `effects` 1.3k, `alias_warning` 0.8k |
  | Caching and incremental | 5.0k | 10 | `semantic_key` 1.3k, `semantic_store` 0.8k, `semantic_cache` 0.8k |
  | Parsing and syntax | 4.5k | 11 | `parser` 2.6k, `lexer` 0.6k, `ast` 0.4k |
  | Constants and formatting | 2.6k | 10 | `format_spec` 0.7k, `buffer_operations` 0.7k |
  | Other (stdlib `.my`, diagnostics, embed, lowering helpers) | 8.2k | 53 | `json.my` 0.7k, `project` 0.6k |

- **Speed.** Check is not the bottleneck; LLVM is (S4 §3.1: over 90% of every build).
  The front-end work here must not regress the S4 check budget: a merged check at
  96k lines after an edit ≤ 0.45 s.
- **S4 decisions this plan keeps.**
  - S4-1: codegen units are keyed by their emitted LLVM text.
  - S4-2: the new core reuses the old `semantic_cache` (formats `module-interface-v5`,
    `check-summaries-v6`, `mutation-v2`).

  §5 replaces S4-2's reuse with one cache model only after S5, and keeps S4-1.

## 3. Language changes (decisions for the user)

Rule for every change: **the one way is the spelling a Python-trained agent writes
first, and every removed spelling gets a targeted error naming the replacement and a
`mylang fix` rewrite.** The parser already does this for `try`, `**` and `del`.

Counts are lines in three application corpora: the EDA stage-1 port (`eda-bench`
`codex/s4-eda-stage1` `510c2e2`, 187 files, 19.8k non-blank lines), the Lox port
(`codex/s4-lox-value-semantics` `f44302d8`, 26 files, 4.2k) and the standard library
(`src/stdlib`, 25 files, 2.8k). Regex counts; §9 has the script.

### 3.1 Part A: one way

| # | Today | One way | EDA | Lox | stdlib | Deletes in the compiler |
|---|---|---|---:|---:|---:|---|
| A1 | `replace(r, f=v)` and `r.f = v` | field assignment | 6 vs 282 | 7 vs 183 | 1 vs 6 | `replace` builtin and its checks |
| A2 | Named and positional record construction | **dropped 2026-10-06; both stay** (§7) | 391 vs 7 | 48 vs 0 | 16 vs 0 | nothing |
| A3 | `& \| ^` operators and `bit_and`/`bit_or`/`bit_xor`/`shift_left`/`shift_right`; `<<`/`>>` rejected | operators, adding `<<` and `>>` | 0 vs 52 | 0 vs 9 | 0 vs 6 | five prelude functions |
| A4 | `effects(...)`, `noio` clauses and the derived ceiling | derived ceiling only | 0 | 0 | 69 + 4 | clause parsing, `W_DERIVED_EFFECTS`/`E_DERIVED_EFFECTS` |
| A5 | `noalloc` | **amended 2026-10-07 (AM2):** the attribute `@noalloc`, checked by the new core at build time | 0 | 0 | 4 | the checker's `noalloc` rule |
| A6 | `@requires`, `@ensures`, `@invariant` and `assert` | **reversed 2026-10-07 (AM1):** contracts stay, because trap search reads them | 0 | 0 | 0 | nothing |
| A7 | `module name` header that must equal the file name | the path is the name (lever L3) | 182 | 26 | 25 | header parsing, `E_MODULE_NAME` |
| A8 | `class` (legacy sharing mode), `with arena()`, `escape()` | value records; arenas already retired (N6) | 0 | 0 | 0 | the legacy mode, arena syntax |
| A9 | `type X = Y` aliases | none | 0 | 0 | 0 | alias resolution |
| A10 | Optional `;` separators | newline only | 0 | 0 | 0 | lexer case |
| A11 | `x is None` and `x == None` | `is None` | 514 vs 0 | 6 vs 0 | 0 | `None` equality special case |
| A12 | `str` methods and the `strings` module | methods; the module keeps what has no method | 6 module calls | 0 | 43 | duplicate implementations |
| A13 | `sorted()`/`.sort()` and the `sort` module | `sorted`, `.sort`; the module keeps binary search and dedup | 21 vs 0 | 0 | 4 vs 21 | duplicate implementations |
| A14 | Whole-path file helpers, the `fs.method(...)` spelling and `with open` | one of them (decide with the I/O owner) | — | — | — | two of three |
| A15 | Two spellings of a structural bound: inline `field(...)`/`op(...)` requirements and named `constraint` declarations | inline requirements; builtin requirements (copy, equality, integer, …) and const lengths stay | 0 `constraint` | 0 | 0 | `constraint_lookup`, named-constraint expansion |

**Kept on purpose, although Go has none of them:**
- comprehensions (EDA 22, Lox 2);
- conditional expressions (EDA 10);
- `lambda` (EDA 9);
- keyword arguments and defaults (about 490 call lines in EDA, including constructors);
- `while` beside `for`.

They are what an agent writes first, and the counts show they are used. Deleting them is
a separate experiment: the dialect A/B design in `cascading-levers-2026-09-21.md` §5,
scored by failed checks and repair rounds. Two narrowings cost nothing:
- a comprehension takes one `for` and an optional `if`;
- `lambda` appears only as a call argument.

**Formatting is part of "one way".** Make `mylang fmt` canonical and gate every `.my`
file on it, as gofmt does. Today `zig build fmt-check` checks only Zig formatting
(`build.zig:1388`).

**The docs must state one way too.** `docs/python-syntax.md:528` still lists
`if r is None:` as rejected. The checker accepts it, and the corpora use it 520 times.
`doc-coverage` should fail when a "rejected spelling" example is accepted.

### 3.2 Part B: visible cost

Go's performance is predictable because cost is visible in the code and the optimizer is
simple. mylang's new core is a strong optimizer, so the plan is: **report what it did per
function, make the guarantees documented rules, and turn hidden costs into source-visible
ones where the data says it is cheap to do.**

| # | Change | Evidence | Recommendation |
|---|---|---|---|
| B1 | **Per-function cost report** (`mylang cost <entry> [function]`, and the same data in `list-interfaces --cost`): checks kept and proved, updates in place, runtime uniqueness tests, copies, allocations, retains/releases, inlined calls, vectorized loops | The new core already counts all of these for `--stats`, whole-program only | **Do first.** It needs no language change, and it is the measurement tool for B2–B5 |
| B2 | **Explicit copies.** Where the core cannot prove a write is in place, it either tests uniqueness at run time or copies. Make those sites visible: first a warning `W_HIDDEN_COPY` naming the binding; later, if the data supports it, require `.copy()` or a restructure | 33 benchmark rows: 242 updates proven in place, 11 tested at run time, 11 copied (8% of updates). 100 `tests/lang` programs: 1,291 / 193 / 161 (many are RC tests that aim at these paths) | Warning in F5. Decide the error after measuring Lox and EDA under the new core |
| B3 | **O(n) operations look like calls.** `x in some_list`, `==` on lists and records, `list + list`, `seq * n` and slices (which copy, while `bytes.view` does not) | Not countable by regex; needs a typed count (§8 P2) | Decide on the typed count. Candidates: `in` on `list` becomes `xs.contains(x)`; slices keep copying but are reported by B1 |
| B4 | **One meaning per literal.** `[1, 2, 3]` is a fixed `[N]T` array or a growable list depending on context, and they copy differently | `[N]T` annotations: EDA 7, stdlib 3 | Give fixed arrays an explicit constructor; the literal is always a list |
| B5 | **Documented optimizer guarantees.** Write the check-elimination cases as rules ("indexing `xs` inside `for i in range(len(xs))` has no bounds check"), test each rule, and report misses in B1 | `binary_search`: 138 cycles with checks against 80 without, because a fact was not proved | With B1 |
| B6 | **`noalloc` as the allocation assertion** (A5) | 4 stdlib uses | Keep; make the B1 report and `noalloc` share one definition of "allocates" |
| B7 | **String costs.** One rule for `str[i]` (S2 accepted O(n/32) non-ASCII indexing), and building text in a loop through `byte_buffer`. `acc = acc + s` in a loop gets a lint | Readiness audit 2026-09-18: 200k appends took 3.76 s | Lint now; revisit after B1 |

## 4. What stays

- Python syntax, indentation, `def`, `record`, `union`, `match`, `Result` with `?`,
  `Option` with `is None` narrowing and `unwrap_or`, tuples, keyword-only parameters.
- `mut` at the parameter and at the call site; capability parameters, which are the only
  way authority reaches a body (effect checking is deleted, AM2).
- Value semantics with one-count RC; no classes, closures, exceptions or methods.
- `@noalloc`, `assert`, `debug(...)`, and the contracts `@requires`, `@ensures` and
  `@invariant` (AM1).

_Amended 2026-10-07 by the values-and-keys plan (AM1–AM3,
`docs/audits/values-keys-trap-search-plan-2026-10-07.md`); the implementation plan's §2
has the details._

## 5. Part C: front-end structure

Facts are from a read of `codex/new-core-s3-integration` at `5ee5b8d2`, with file:line
citations; the front-end files are the same as at `2e4f0f51`.

### C0. Cut the front end loose from the old back end (must happen in S5)

**Deleting the old back end breaks module-mode `check`, not just `build`.**
- `module_compile.zig:24-25` and `module_interface_oracle.zig:22-23` import `lower.zig`
  and `bytecode.zig`, and `incremental.zig:12` imports `bytecode.zig`.
- Per-module `check` reads `compile-module` records, which are lowered through the old
  back end.

**The S5 plan must replace per-module checking with S4-2's path:** the merged check plus
the semantic cache. It must also drop `fix_command.zig`'s imports of
`qbe_build_io.zig` and `native_test_snapshot.zig` (`fix_command.zig:12-13`).

**Dead once the old back end is gone (about 1.0k lines):**
- `bytecode_model.zig` (167);
- the bytecode validators: `effects.zig:1028-1197` and `mutation.instruction`;
- the VM parts of `runtime_values.zig` (about 180 of 373) and `io_render.zig` (about 200
  of 217);
- `mut_abi`'s caller-storage ABI (about 120);
- `value_semantics.zig`'s lowering facts (about 100);
- typed fields only the old core reads: `owned_cleanup`, `caller_storage`,
  `borrow_origin`, and `loop_exit.arenas`.

**Legacy sharing mode (A8), about 1k more:**
- `alias_warning.zig` (764), which returns at once under value semantics
  (`alias_warning.zig:128`);
- the overlap path in `origins`;
- the `class`/`Cell` branches.

**Also in C0:**
- **Move `typed.Type` out of the VM file** `runtime_values.zig:7`, into the type
  catalog.
- **Merge `mylang-core` into `mylang`**, as N2 planned once the old back end is deleted.

### C1. A source-shaped typed tree; desugaring moves to the core

**Today the front end lowers as it checks.**
- `typed.Program` has 11 statement kinds (`typed.zig:585-597`).
- For-each and `range` loops become index locals, a guard and a `loop`
  (`sema_loops.zig:95-184`, `353-417`).
- List literals become a buffer acquisition plus appends (`collection_lower.zig:304-316`).
- Set operators become dictionary writes and walk loops (`set_lower.zig:62-160`).
- `is_none`/`unwrap_or` become `match` (`option_flow.zig:136-172`).
- **Comprehensions are lowered in two places.**
  - The parser turns filtered, multi-clause and generator forms into loops
    (`parser.zig:2052-2075`).
  - Sema lowers the single-clause form (`sema_collections.zig:315-490`).
  - The filter branch at `sema_collections.zig:401-405` is unreachable.

**Change.**
- Sema produces a typed tree with `for`, comprehensions, collection literals, set
  operations and Option operations as nodes, each with its span.
- One desugaring pass, owned by the core (`src/core/desugar.zig`), produces today's
  `typed.Program` shape, so the Core IR builder changes little.

**Why.**
- The B1 cost report and diagnostics can point at source constructs.
- Navigation and `mylang fix` read the same tree.
- There is one comprehension path.
- The core can lower sets and dictionary iteration directly instead of through index
  loops.

**Check.** `dump-ir` output is identical before and after, over `tests/lang`, the rows,
Lox and EDA.

### C2. Local analyses instead of call-graph inference

**Today:**
- `effects.zig` propagates inferred effects over the call graph on every check
  (`effects.zig:640`, `sema.zig:1950`).
- `origins.zig` runs a budgeted fixed point over `mutates`, `return_origin` and
  `borrow_origin`, widening when the budget runs out (`origins.zig:724-760`).
- **Two hashes contradict `docs/effects.md`:** `module_interface.interfaceHash` and
  `semantic_key.contractDigest` include these inferred facts
  (`module_interface.zig:349-365`, `semantic_key.zig:162-190`).
  - Only `incremental.zig`'s `interface_sha256` excludes them.
  - So an inferred-effect change in a body still invalidates its callers.

**Change.** Every cross-function fact comes from the callee's signature.
- **Effects.** A call contributes the callee's derived ceiling, not its inferred body
  set. The per-body check against the caller's ceiling (`E_EFFECT_BOUND`) and
  `E_UNUSED_CAPABILITY` stay. `noalloc` is checked the same way: callees must be
  `noalloc`. _Amended 2026-10-07 (AM2):_ effect checking is deleted instead, and
  `E_UNUSED_CAPABILITY` stays. `@noalloc` is checked by the new core at build time.
- **CALLBACK-SLOT-1.** Slot ceilings (`effects.zig:862-869`) use the callback type's
  declared ceiling.
- **Contract purity** (`effects.zig:810`) goes with A6.
- **Mutation is declared.**
  - The body check is local: a write through a parameter not marked `mut` is an error,
    and a `mut` argument needs a `mut` parameter.
  - The new core then reads `declared_mutates` only. Today `core/build.zig:202` refuses a
    function whose inferred and declared sets differ.
  - `build_host.zig:43` writes the declared ceiling.
- **Deleted:**
  - `return_origin`, `borrow_origin` and `caller_storage`, which the new core never
    reads;
  - the call-graph passes;
  - the inferred fields in both hashes.

**Open question to check first.** Whether any accepted program relies on an inferred fact
that a signature cannot state. §8 P4 runs the change behind a flag over every corpus and
counts the new errors.

### C3. One generics path

**Today a template body is checked twice:**
- symbolically, by `generic_bodies.zig` (2,964 lines, its own call, expression and
  statement checker, `generic_bodies.zig:1609-2496`), plus an abstract effect inference
  that is never cached;
- then each specialization concretely, from the `checkBodies` worklist
  (`sema.zig:1689-1701`).

The core receives only monomorphic functions.

**Change.**
- Check a template once, symbolically, against its bounds.
- Instantiate a specialization by substitution, without rechecking its body.
- Errors stay at the definition, which is what agents need.
- After A15 the bounds are the builtin requirements, inline structural requirements and
  const lengths.

**Check.** Every specialization the old path accepted is accepted. The specialized Core
IR is identical.

### C4. One cache model

**Today:**
- Eight layers: `syntax_cache`, `check_cache`, `frontend_cache`, `semantic_cache` with
  `semantic_store`, `generic_cache`, `semantic_summary`, `module_interface`/`compile`/
  `build`, and `incremental` with `invalidation`.
- At least four identity schemes:
  - the semantic-key dependency digest;
  - the module-interface hash;
  - `interface_sha256`;
  - the front-end input SHA.
- Bypasses: `interned_record`, function values, generic specializations, `over_budget`,
  and retention budgets (`semantic_store.zig:34-38`, 128 MiB / 65,536 entries).

**Change, after C2 and C5:**
- **One query per declaration**, keyed by the declaration's source hash plus the digest of
  the signatures it resolves.
- **One on-disk store with one format version.** Today the header says
  `semantic-cache-v2` while the store writes v3.
- The api-diff and explain-invalidation receipts derive from the same keys.
- Codegen keeps S4-1's LLVM-text keys.

**Budget.**
- After an edit, the merged check at 96k lines stays at or under 0.45 s.
- An unchanged check stays at 0.03 s.
- Cold, it stays at or under 1.09 s.

### C5. Stable type identity

**Today:**
- A type is an index into an append-only, per-compilation record catalog
  (`runtime_values.zig:32`, `sema.zig:1941`).
- `list[T]`, sets, options, arrays, tuples and callables are interned lazily while bodies
  are checked (`collection_lower.zig:17-49`, `type_catalog.zig:97-200`).
- So identity depends on checking order, and the semantic cache cannot reuse a body that
  names a type interned after `initial_record_count`. That is the `interned_record`
  bypass. In the 2026-09-17 scale probe, it bypassed 4,799 of 4,800 bodies.

**Change.** Identify a type by a hash of its canonical spelling (`list[int]`,
`module.Record`). A table maps that hash to a dense index inside one compilation, so the
identity no longer depends on order.

### C6. One lossless syntax tree with error recovery

**Today:**
- The parser stops at its first error. It has 75 fail sites (`diagnostic.zig:187-190`),
  and recovery starts only after a successful parse (`docs/diagnostic-recovery.md:32`).
- The lexer drops comments (`lexer.zig:413-416`). The formatter reads them back from the
  gaps between tokens (`formatter.zig:1-20`).
- `mylang fix` runs a child `check` and applies byte edits (`fix_command.zig:5-9`).
- Rejected spellings come from three mechanisms:
  - the `declaration_hints` table, 12 forms (`parser.zig:66-100`);
  - 9 ad hoc `alternative` branches (`parser.zig:216-229`, `1463`, `1608`, `2358`,
    `2486`);
  - `removed_names.zig`, 28 removed mylang names.

**Change.**
- **A lossless tree** of tokens plus comments and whitespace, with an AST view over it.
- **Statement-level recovery** that resynchronizes at a newline or dedent, so one run
  reports every syntax error.
- **One tree for every tool:** the formatter, `mylang fix` migrations and navigation all
  run over it.
- **One table** for all rejected and removed spellings, which `doc-coverage` and the
  velocity classifier also read. The untracked `src/syntax_table.zig` in the main
  checkout may be the start of this.

### Size

Deletions, roughly, before any re-addition:
- C0: about 2k lines;
- C2: about 2–3k (`origins` and the call-graph part of `effects`);
- C3: one of the two generics checkers, about 3k;
- C4: about 2–3k of the 5k cache code.

That is 9–11k of 46.6k lines. These are estimates from file sizes, not measured; each
package reports its real count.

## 6. Order

| Wave | Packages | Starts after | Exit check |
|---|---|---|---|
| **F0** | C0. The module-check replacement and the `fix` imports belong in the S5 plan itself | S5 | The full gate on one binary; module projects check without the old back end |
| **F1** | Part A deletions with `mylang fix` migrations applied to Lox, EDA and stdlib; the canonical `.my` format gate; B1 cost report | F0 and the user's A decisions | Corpora pass; every removed spelling has a targeted error and a fix |
| **F2** | C5 stable type identity; C2 local analyses | F1 | Same accepted programs (P4); interface hashes exclude inferred facts; check budget held |
| **F3** | C1 source-shaped tree and core-owned desugaring; C3 one generics path | F2 | `dump-ir` identical over every corpus |
| **F4** | C4 one cache model; C6 lossless tree with recovery | F3 | Check budget held with no bypasses; multi-error syntax reports |
| **F5** | B2–B7 visible-cost rules | B1 data from Lox and EDA under the new core | User decides each rule on the counts |

**Rules for every wave:**
- `tests/lang` passes under the new core.
- Lox conformance stays 974/974, with its 65 tests.
- EDA keeps 310 tests and 34 byte-identical goldens.
- Check timings are measured with the S4 synthetic projects.
- Line deltas are reported per package.

As with S2–S4, Codex implements and the plan stops for the user at each wave.

## 7. Decisions (the user, 2026-10-06)

| # | Decision | Recommendation | Decided |
|---|---|---|---|
| **FE1** | Adopt the Part A rows (A1–A15), row by row | Adopt all; A14 needs a choice of file-access spelling | **Adopted.** A14: keep the `fs.method(...)` spelling and `with fs.open(...)`; delete the free-function forms. **A2 is dropped:** positional and named construction both stay, because the idiom suite constructs records positionally 20 times against 3 (implementation plan §2). |
| **FE2** | Keep comprehensions, conditional expressions, `lambda` and keyword arguments | Keep, with the two narrowings; A/B test removal later if wanted | **Keep, with the `lambda` narrowing only.** Multi-`for` comprehensions stay; the idiom suite uses one. |
| **FE3** | Gate `.my` formatting canonically | Yes | **Yes** |
| **FE4** | B1 cost report in F1; B2 as a warning in F5; the `.copy()` error decided on Lox/EDA data | Yes | **Yes;** B1 moves earlier, alongside S5 |
| **FE5** | B3 and B4 decided on the typed count (P2) | Yes | **Yes;** P2 may run now |
| **FE6** | Generics: check templates once, symbolically; instantiate by substitution | Yes (the alternative, checking only specializations, reports errors at use sites) | **Yes** |
| **FE7** | Put C0's module-check replacement into the S5 plan | Yes; S5 cannot delete the old back end without it | **Yes;** the new-core plan's S5 row now says so |

C2's signature-only hashes need no decision: they make the code match `docs/effects.md`.

## 8. Probes before the decisions

- **P1. Hidden copies on real programs.** Run `mylang-core build --release --stats` over
  Lox and EDA once S4 builds them. Today they stop at capability types under S3. Record
  in-place, tested and copied counts per function.
- **P2. Typed count of O(n) operators.** Use a `dump-typed` walker over the three corpora
  to count `in` on `list`, `==` on aggregates, `list + list`, `seq * n` and slices,
  inside and outside loops.
- **P3. Agent first attempts (optional).** Only if FE2 is reconsidered: run the dialect
  A/B from `cascading-levers-2026-09-21.md` §5.
- **P4. Signature-only analyses.** Run C2 behind a flag over `tests/lang`, the rows, Lox,
  EDA and stdlib, and list every program that changes verdict.

## 9. Evidence

Scripts and raw outputs are in `experiments/frontend-plan-20261006/`:
- `classify_src.py`: the front-end/back-end/tooling line split by `@import` closure.
- `count_spellings.py` and `spellings.txt`: the §3 corpus counts (regex, approximate),
  over the EDA stage-1 port (`eda-bench` `510c2e2`), the Lox port (`f44302d8`) and
  `src/stdlib` (`2e4f0f51`).
- `gen_program.py`: the synthetic N-function program used for the compile-time numbers
  in the 2026-10-06 conversation.
- `ownership_rows.txt` and `ownership_tests_lang.txt`: `mylang-core build --release
  --stats` over 33 rows and 100 `tests/lang` programs, built ReleaseFast from
  `2e4f0f51`.

The front-end architecture facts in §5 come from a read-only pass over `5ee5b8d2` with
file:line citations. The key ones were re-checked by hand:
- `core/build.zig:202`;
- the `lower`/`bytecode` imports in `module_compile.zig` and
  `module_interface_oracle.zig`;
- the inferred facts in `module_interface.zig:349-365`;
- the statement kinds at `typed.zig:585-597`.

## 10. Risks

- **C1 is the largest change and touches every construct.** The `dump-ir` differential is
  what makes it safe; without it, do not start.
- **C2 may reject programs that rely on inference** (P4 measures it). The fallback is to
  keep inferred facts as diagnostics only, never in hashes.
- **The front end stays shared with the old core until S5.** Nothing here starts before
  S5, so there is no dual-maintenance window.
- **Part A removes spellings agents may still produce from older docs and examples.** The
  targeted errors and `mylang fix` cover it; F1 also sweeps `docs/` and `examples/`.
