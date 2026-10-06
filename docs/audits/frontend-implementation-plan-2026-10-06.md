# The front end after the new core: implementation plan, 2026-10-06

Status: **decisions accepted 2026-10-06 (§2). Ready for Codex in three launches (below);
the main waves start at the S5 exit.** Parts marked _finalize at the S5 exit_ are filled
in then. The rationale, the measurements and the file:line facts are in the proposal,
`docs/audits/frontend-plan-after-new-core-2026-10-06.md` ("the proposal"), with evidence
in `experiments/frontend-plan-20261006/`.

**The goal (the user, 2026-10-06):** the language works like Go. There is one way to
express each thing, and performance is predictable. The spelling stays Python's, because
agents write Python first.

## Launch instructions (for Codex)

**Now, optional, alongside S4.** Read-only; it needs no compiler change:

> Run probe FP2 of `docs/audits/frontend-implementation-plan-2026-10-06.md` (branch
> `claude/frontend-plan`) on a new branch `codex/frontend-fp2` from `claude/frontend-plan`.
> Change no compiler file. Hold S4's machine rules: at most one build-heavy process, and
> never time anything. Finish with FP2's report and stop.

**After the S4 exit, alongside S5:**

> Implement package FB1 of `docs/audits/frontend-implementation-plan-2026-10-06.md` on
> `codex/frontend-fb1`, created from the S4 exit commit. Merge `claude/frontend-plan` into
> it first. Touch only `src/core/` and FB1's docs. Never merge into `main` and never push.
> Finish with FB1's report, P1's table included, and stop.

**At the S5 exit, after the user's go:**

> Implement the front-end plan `docs/audits/frontend-implementation-plan-2026-10-06.md`.
> Create `codex/frontend-integration` from the S5 exit commit, merge
> `claude/frontend-plan` and `codex/frontend-fb1` into it, and fill in §1's
> _finalize at the S5 exit_ items. Run F0, then F1, F2, F3, F4 and F5, holding every gate
> in §5 and the rules in §6. **Stop at the end of every wave** with its report (§7) for
> the user's go. Never merge into `main` and never push.

## 1. Where it starts

- **The base is the S5 exit.** S5 makes the new core the only back end and deletes the
  old one. Until then the front end is shared by both cores, and the old core is S4's
  differential oracle. A front-end bug would pass that oracle, because both cores would
  receive the same wrong program. So no front-end code changes before S5, except the
  three early packages below, which touch only `src/core/` or nothing.
- **S5 itself carries the front-end work it cannot avoid** (decision FE7, §2):
  - module-mode `check` moves to the merged check plus the semantic cache (S4-2),
    because `module_compile.zig`, `module_interface_oracle.zig` and `incremental.zig`
    import `lower.zig` and `bytecode.zig`;
  - `fix_command.zig` drops its imports of `qbe_build_io.zig` and
    `native_test_snapshot.zig`;
  - `mylang-core` merges into `mylang` (N2).
- **The oracle after S5 is the pinned S5-exit compiler.** Build it once with
  `zig build -Doptimize=ReleaseFast --prefix <cache>/mylang-s5-pin` through
  `scripts/build-slot.sh build`, record its SHA-256, and never rebuild it. Every
  differential check in §5 compares a candidate against it.
- **The scale budget** comes from S4: on the synthetic projects
  (`experiments/new-core-s4-20261006/gen_program.py`), the merged check at 96k lines takes
  0.45 s after a one-function edit, 0.03 s unchanged and 1.09 s cold.
- **_Finalize at the S5 exit:_**
  - the S5 exit commit and the pin's hash;
  - the post-S5 full gate: its steps and its time;
  - the compiler rebuild time S5 measured, which becomes the rebuild budget;
  - which of C0's dead code (proposal §5) S5 already deleted;
  - S4's final check-budget numbers, if S4-F improved on 0.45 / 0.03 / 1.09 s;
  - the proposal's §5 file:line citations, rechecked against the S5 exit. Files move in
    S5.

## 2. Decisions (accepted 2026-10-06)

### FE1. Part A: one way (proposal §3.1)

**Every removed spelling gets all of these:**
- an entry in the one removed-spellings table (F1-0);
- a targeted error code, `E_<NAME>_REMOVED`, following `E_EXPORT_REMOVED`, which names
  the replacement;
- a `fix` edit in the diagnostic when a mechanical rewrite exists, so `mylang fix`
  migrates code;
- a spec tag, a `SPEC.md` bullet and a test;
- its feature slug moved from `implemented` to `removed` in `src/features.json`, with a
  date and a note;
- its docs rewritten, and a `# doc: expect-error` example of the removed spelling.

**The rows, with the exact rule each package implements.** Counts are from the
2026-10-06 corpus scan (`spellings.txt`) and a scan of the repository at the S3 exit.

| Row | Removed | The one way | Fix rule |
|---|---|---|---|
| **A1** | the `replace` builtin, both its record form `replace(r, f=v)` and its list form `replace(xs, i, v)` | `r.f = v`, `xs[i] = v` | `y = replace(r, f=v)` becomes `y = r` then `y.f = v`. Elsewhere, a fresh local is assigned before the statement. `s.replace(a, b)` on text is a different method and is untouched. |
| **A2** | **dropped:** positional and named record construction both stay (see below) | | |
| **A3** | `bit_and`, `bit_or`, `bit_xor`, `shift_left`, `shift_right` | `&`, `\|`, `^`, and new `<<`, `>>`, `<<=`, `>>=` | Rewrite to the operator, parenthesized. The new operators take Python's precedence (looser than `+`, tighter than `&`) and today's function semantics: the count has the operand's type, `<<` discards high bits, `>>` is arithmetic for signed and logical for unsigned, and a negative or too-large count traps `R_INVALID_SHIFT` (`E_CONSTANT_ARITHMETIC` for a constant). |
| **A4** | `effects(...)` and `noio` clauses, on declarations, on `extern def` and on callback types; `W_DERIVED_EFFECTS` and `E_DERIVED_EFFECTS` | `noalloc` is the only effect annotation. Every other ceiling derives from parameter types, **including a callback type's from its own parameter types** | A clause that excludes `managed_allocation` from the derived ceiling becomes `noalloc`. Any other clause, and every `noio`, is deleted. |
| **A5** | nothing; `noalloc` stays | | |
| **A6** | `@requires`, `@ensures`, `@invariant` | `assert` | `@requires(e)` becomes `assert e` as the body's first statement. `@ensures` and `@invariant` have no mechanical fix (0 uses outside tests); their error names `assert`. |
| **A7** | the `module NAME` header, `E_MODULE_NAME`, and the headerless-entry restriction (`E_MODULE_HEADER`) | **the path is the name:** a file's module name is its path from the project root, without `.my`, with `/` read as `.`. The project root is the directory holding `mylang.json`, else the entry's directory. | Delete the header line. |
| **A8** | `class` (legacy sharing mode), `with arena()`, `escape()` | value records; arenas already retired (N6) | None; 0 uses. Code deleted in F0. |
| **A9** | `type X = Y` aliases | the type itself | Substitute `Y` at every use in the project, then delete the alias. |
| **A10** | `;` separators | newlines | Split the line. |
| **A11** | `x == None`, `x != None` on an `Option` | `is None`, `is not None` | Rewrite the operator. |
| **A12** | `strings` functions that have an exact `str` method or builtin equivalent | the method or builtin; the module keeps the rest | Rewrite the call. F1-L first builds the mapping table, with equivalence evidence. |
| **A13** | `sort` functions duplicating `sorted`, `.sort`, `min` and `max` | those; the module keeps binary search and the deduplication helpers | Rewrite the call; same mapping rule as A12. |
| **A14** | the free-function form of a capability operation that also has a method form: `read_text(fs, p)`, `open(fs, p, mode)` and the rest of `docs/io.md`'s table, and the same duplicates on other capabilities | the method, `fs.read_text(p)`; `with fs.open(...)` stays, because streaming is a different operation (Go keeps both `os.ReadFile` and `os.Open`) | Rewrite to the method. |
| **A15** | named `constraint` declarations | inline requirements; the builtin requirements and const lengths stay | Inline the constraint's requirements at each use. |

**A2 is dropped (the user, 2026-10-06).** Positional and named construction both stay,
as Python dataclasses allow. The evidence, found while writing this plan:
- The idiom suite `velocity/suites/idioms` records what agents write first. Its 16 probes
  that declare records construct them positionally 20 times and by name 3 times, for
  example `P("a", 3)`, `Counter(0)` and `Pair(a // b, a % b)`.
- The ports' 455 named against 7 positional constructions followed the porting guide.
- Under the proposal's own rule, that the one way is the spelling a Python-trained agent
  writes first, named-only construction would cost a repair round on most first
  attempts.

### FE2. What stays

- **Kept:** comprehensions (one or several `for` clauses and an optional `if`),
  conditional expressions, `lambda` and keyword arguments with defaults.
- **One narrowing: a `lambda` is accepted only directly as a call argument.** Elsewhere
  it is an error naming a top-level `def`. It has no fix, and nothing uses it.
- **The proposed one-`for` limit on comprehensions is dropped.** The idiom suite has
  `[x for row in grid for x in row]` (`a66_nested_comp.my`).

### FE3. A canonical `.my` format

- `mylang fmt` output is canonical, and the gate checks every live `.my` file. Live means
  everything except `experiments/` and the fixtures that test formatting or rejected
  syntax.
- There is one reformat commit, after F1's migrations.

### FE4–FE7

- **FE4, cost:** the per-function cost report comes early (FB1, alongside S5). The
  hidden-copy warning comes in F5. Whether an explicit `.copy()` is required is decided
  on FP1's data.
- **FE5, O(n) operators and literals:** B3 (O(n) operators) and B4 (fixed-array
  literals) are decided on FP2's typed count.
- **FE6, generics:** a template is checked once, symbolically, against its bounds. A
  specialization is instantiated by substitution, and errors stay at the definition.
- **FE7, S5:** the S5 plan includes the three items in §1. The new-core plan's S5 row
  says so.

## 3. Work packages

Each package runs in its own locked worktree. It commits with Guardian's checks and
records evidence under `experiments/frontend-<package>-<date>/`, one log per command run.
**Owns** lists the files a package may change. A change needed elsewhere goes through
the coordinator.

### Early packages (before S5)

#### FP2. Typed count of O(n) operators (now; about 2–3 h; no compiler change)

**What:**
- Write a walker over `mylang-core dump-typed` output.
- **The corpora:** the EDA slice (`eda-bench` `codex/s4-eda-stage1` `510c2e2`), the
  Lox port (`codex/s4-lox-value-semantics` `f44302d8`), `src/stdlib` and `tests/lang`.
- **What it counts,** each split by loop depth (0, 1, 2 or more):
  - `in` on a `list`;
  - `==` and `!=` on lists, records, dictionaries and sets;
  - `list + list`;
  - `seq * n`;
  - slices of `list`, `str` and `bytes`, with `bytes.view` counted for contrast;
  - `str` concatenation inside a loop.
- `typed.Program` is already desugared. A construct the walker cannot recognize after
  desugaring is reported as uncounted, never estimated.

**Exit:** a table per corpus, plus the script, under `experiments/frontend-fp2-*/`. It
is the data for FE5's B3 and B4 decisions.

#### FB1. Per-function cost report (after the S4 exit, alongside S5; about 4–6 h)

**What:**
- `mylang-core cost <entry> [function]`, with text and `--json` output. Per function,
  it reports:
  - checks kept and checks proved;
  - updates made in place, tested for uniqueness at run time, or copied;
  - allocations;
  - retains and releases;
  - inlined calls;
  - vectorized loops, read from LLVM's optimization remarks. Where `zig cc` cannot
    produce remarks, the loops are reported as unknown.
- **B6:** `noalloc` and the report share one definition of "allocates", so the report
  and the check cannot disagree.

**Owns:** `src/core/` (a new `cost.zig` and the stats plumbing it reads) and the docs
for the command.

**Exit:**
- On all 46 rows, the report's totals equal `--stats`'s.
- Tests cover every count.
- **P1:** the report over the Lox port and the EDA slice, with in-place, tested and
  copied counts per function and the 20 functions with the most copies.
- S5's merge carries the command into `mylang`. F0 adds `list-interfaces --cost`.

### F0. Cut loose from the old back end (after S5; about 4–6 h)

**What:** the rest of proposal §5 C0, which is whatever S5 left:
- **dead code:** `bytecode_model.zig`, the bytecode validators in `effects.zig`,
  `mutation.instruction`, the VM parts of `runtime_values.zig` and `io_render.zig`,
  `mut_abi`'s caller-storage ABI, `value_semantics.zig`'s lowering facts, and the typed
  fields only the old core read (`owned_cleanup`, `caller_storage`, `borrow_origin`,
  `loop_exit.arenas`);
- **A8:** the legacy sharing mode (`alias_warning.zig`, the overlap path in `origins`,
  the `class`/`Cell` branches), arena syntax and `escape()`, each with its
  removed-spelling error;
- `typed.Type` moves out of `runtime_values.zig` into the type catalog;
- `list-interfaces --cost` (FB1).

**Exit:**
- the post-S5 full gate;
- no file imports a deleted module;
- `dump-ir` identical over the corpora (§5), except programs using A8 spellings, which
  are now rejected;
- line deltas per file group.

### F1. Part A and the format gate (about 15–21 h)

#### F1-0. Shared tools and baselines (coordinator; about 3–4 h)

- **The removed-spellings table: one file.**
  - Move the parser's `declaration_hints`, its ad hoc `alternative` branches and
    `removed_names.zig` into it.
  - The parser, `doc-coverage` and the velocity classifier read it.
  - `doc-coverage` fails when an entry lacks a `# doc: expect-error` example. That
    replaces prose lists such as `docs/python-syntax.md:528`, which still calls the
    accepted `is None` rejected.
  - The untracked `src/syntax_table.zig` in the main checkout is another session's work
    and on no branch. Reuse it only if the user lands it.
- **The embedded-source migration tool** `scripts/migrate_embedded.py`.
  - It runs `mylang fix` over three shapes, like `scripts/migrate-print-to-stream.py`:
    `.my` files, ```` ```mylang ```` blocks in `.md` files, and Zig multiline literals
    in tests.
  - Tests and docs embed many sources, for example about 1,040 `module` headers inside
    Zig test literals.
  - Python is acceptable here: the script maintains the repository and is never needed
    to build or use mylang.
- **Baselines:**
  - `velocity/score.py --json`: C1 first-try fidelity, C2 silent wrong answers and C3
    rejections carrying a fix;
  - the spelling counts, with `count_spellings.py` extended to the live repository and
    embedded sources;
  - every corpus program's output under the pinned S5 compiler, for the migration check
    in §5.

#### F1-S, F1-M, F1-E, F1-L (four agents in parallel, after F1-0)

| Package | Rows | Owns | Estimate |
|---|---|---|---|
| **F1-S** syntax and expressions | A1, A3, A6, A9, A10, A11, A15, the `lambda` narrowing | `parser.zig`, `lexer.zig`, the sema files for those builtins and operators, contract and invariant checking, alias resolution, `constraint_lookup` | 6–8 h |
| **F1-M** modules | A7 | project loading and import resolution, `mylang run`'s project detection, the header rule in the parser (coordinated with F1-S) | 5–7 h |
| **F1-E** effects | A4 | effect-clause parsing and checking in `effects.zig`, callback-type ceilings, `docs/effects.md`, `docs/functions.md`, the `effects(output)` line in `CLAUDE.md` | 4–6 h |
| **F1-L** library | A12, A13, A14 | `src/stdlib/strings.my` and `sort.my`, the capability free-function builtins, `docs/io.md`, `docs/standard-library.md` | 3–5 h |

**Common to the four:**
- **Each migrates every live source with its fixes,** through `mylang fix` and the
  migration tool, in its own commit. That includes tests, docs, examples, `src/stdlib`,
  `velocity/suites`, `bench/` and `test/`.
- **Migration volume** at the S3 exit:
  - A7: 580 `.my` files and about 1,040 embedded headers;
  - A4: about 450 clauses in `.my` files and 680 embedded;
  - A3: about 90 calls in `.my` files.

**Rules specific to rows:**
- **F1-M:**
  - A file whose path is not a dotted identifier path can be an entry but cannot be
    imported. The import's error says why.
  - `mylang run` loads the reachable graph whenever the entry imports a non-standard
    module.
- **F1-E:** if a fix makes an accepted program reject, stop and report. The rewrite
  only widens ceilings, so that must not happen.
- **F1-L:** a function is removed only when a property test over random inputs shows the
  replacement gives the same result on every input. For text, that includes non-ASCII
  input; for floats, NaN and signed zero. Otherwise the function stays.

#### F1-F. The canonical format gate (after the four merge; about 2–3 h)

- `mylang fmt` is idempotent over every live `.my`: formatting twice gives the same
  bytes.
- The gate gains a `.my` step beside `fmt-check`.
- One reformat commit.

#### F1-X. External corpora and the wave exit (coordinator; about 3–5 h)

- **Lox and EDA:** apply `mylang fix` and `mylang fmt` on new branches from their S4-P
  states.
  - Lox conformance stays 974/974 with its 65 tests.
  - EDA stays at 310 tests and 34 byte-identical goldens.
- **The idiom suite:**
  - C2 stays 0;
  - every probe that F1 newly rejects is listed with its error and its fix, and C3
    counts it;
  - C1 is reported against F1-0's baseline.
- **The spelling counts:** 0 for every removed spelling in live sources.

### F2. Local analyses and stable type identity (about 12–16 h)

#### F2-C2. Signature-only analyses (one agent; about 8–10 h)

1. **P4 first.** Implement proposal §5 C2 behind a flag. Run it over `tests/lang`, the
   rows, Lox, EDA and stdlib, and list every program whose verdict changes.
   - **Stop and report** if any accepted program is rejected for a fact a signature
     cannot state.
   - The fallback, if the user takes it, keeps inferred facts as diagnostics only,
     never in hashes.
2. **Then make it the default and delete:**
   - the call-graph passes;
   - `return_origin`, `borrow_origin` and `caller_storage`;
   - the inferred fields in `module_interface.interfaceHash` and
     `semantic_key.contractDigest`, which brings them in line with `docs/effects.md`;
   - `core/build.zig:202`'s refusal when inferred and declared mutation sets differ.
     The core reads `declared_mutates` only.
   - Contract purity went with A6.

**Owns:** `effects.zig`, `origins.zig`, `module_interface.zig`'s hash,
`semantic_key.zig`'s digest, and `core/build.zig`'s mutation read.

**Exit:**
- P4's list reviewed;
- an inferred-effect change in a body no longer changes its callers' keys (a test);
- the check budget held.

#### F2-C5. Stable type identity (one agent; about 6–8 h; parallel with C2)

**What:** proposal §5 C5. A type is identified by the hash of its canonical spelling,
and a per-compilation table maps the hash to a dense index. This deletes the
`interned_record` cache bypass.

**Owns:** the type catalog, `collection_lower.zig`'s interning, `type_catalog.zig`, and
the bypass in `semantic_store.zig`.

**Exit:**
- the body-reuse rate on the synthetic projects after a one-function edit, measured
  before and after. The 2026-09-17 scale probe bypassed 4,799 of 4,800 bodies.
- outputs identical to the pin, and `dump-ir` identical up to type numbering;
- the check budget held.

**Shared file:** `semantic_key.zig` is touched by both F2 packages. The coordinator
merges them one at a time and bumps each persisted format once for the wave.

### F3. A source-shaped tree and one generics path (about 22–31 h)

#### F3-0. The `dump-ir` differential (coordinator; about 2–3 h)

- **The tool:** for every program in the corpora (§5), `mylang dump-ir` with F3's base
  compiler, pinned, against the candidate's. They must be byte-identical.
- A difference is either a bug or a listed intended change, and F3 lists none.

#### F3-C1. Source-shaped typed tree; desugaring moves to the core (one agent; about 12–16 h)

**What:** proposal §5 C1.
- **Sema produces a typed tree with spans,** with nodes for `for`, comprehensions,
  collection literals, set operations and `Option` operations.
- **`src/core/desugar.zig` produces today's `typed.Program` shape** from that tree, so
  the Core IR builder changes little.
- There is one comprehension path. The parser's lowering (`parser.zig:2052-2075`) and
  the unreachable filter branch (`sema_collections.zig:401-405`) go.

**Owns:** `typed.zig`, `sema_loops.zig`, `sema_collections.zig`, `collection_lower.zig`,
`set_lower.zig`, `option_flow.zig`, the parser's comprehension lowering, and
`src/core/desugar.zig` with its call site.

**Exit:** `dump-ir` identical over every corpus, and the check budget held.

#### F3-C3. One generics path (one agent; about 8–12 h; after C1 merges)

**What:** proposal §5 C3.
- A template is checked once, symbolically, against its bounds.
- A specialization is instantiated by substituting into the source-shaped tree, then
  desugared, with no recheck.
- After A15 the bounds are the builtin requirements, inline requirements and const
  lengths.

**Owns:** `generic_bodies.zig`, sema's `checkBodies` worklist, and instantiation.

**Exit:**
- every specialization accepted before is accepted, with identical `dump-ir`;
- generic errors are reported at the definition;
- line delta reported (about 3k expected).

**Why sequential:** C1 changes the tree that C3 substitutes into. Running them in
parallel would make C3 build on a shape that is about to change.

### F4. One cache model and a lossless tree (about 12–16 h)

#### F4-C4. One cache model (one agent; about 8–12 h)

**What:** proposal §5 C4.
- **One query per declaration,** keyed by the declaration's source hash and the digest
  of the signatures it resolves.
- **One on-disk store with one format version,** fixing today's mismatch: the header
  says `semantic-cache-v2` while the store writes v3.
- `api-diff` and `explain-invalidation` derive from the same keys.
- **Seven of the eight layers fold into it:**
  - `check_cache`;
  - `frontend_cache`;
  - `semantic_cache` with `semantic_store`;
  - `generic_cache`;
  - `semantic_summary`;
  - `module_interface`, `compile` and `build`;
  - `incremental` with `invalidation`.
- `syntax_cache` stays the parse cache, under F4-C6. Codegen keeps S4-1's
  LLVM-text keys.

**Exit:**
- no cache bypass left;
- after an edit, the 96k check stays at or under the budget (§1); unchanged and cold
  stay within budget too;
- a corrupted store entry is detected and rebuilt (a test).

#### F4-C6. Lossless tree with error recovery (one agent; about 10–14 h; parallel with C4)

**What:** proposal §5 C6.
- a lossless tree of tokens, comments and whitespace, with an AST view;
- recovery at a newline or dedent, so one run reports every syntax error;
- the formatter, `mylang fix` and navigation all run over the tree;
- the parser reads F1-0's table.

**Owns:** `lexer.zig`, `parser.zig`, `ast.zig`, `formatter.zig`, `fix_command.zig`,
`syntax_cache`, and the diagnostic-recovery code.

**Exit:**
- multi-error files report every error (tests);
- the formatter's output byte-identical to F1-F's canonical format on every live `.my`;
- `dump-ir` identical.

### F5. Visible cost (about 5–8 h, then a stop for decisions)

**What:**
- **B2:** the warning `W_HIDDEN_COPY`, naming the binding at each site where the core
  copies or tests uniqueness at run time.
- **B5:** the check-elimination guarantees written as rules, one test per rule, with
  misses reported by `mylang cost`.
- **B7:** the lint for `acc = acc + s` in a loop, pointing at `byte_buffer`.

**Then stop.** The user decides, on FP1's and FP2's data:
- B2's error: is `.copy()` required, or does the code need restructuring?
- B3: which O(n) operators change spelling, for example `xs.contains(x)`.
- B4: an explicit fixed-array constructor.

A follow-up plan implements those decisions.

## 4. Order and expected time

| Wave | Packages | Starts after | Expected wall time |
|---|---|---|---|
| Early | FP2; FB1 with P1 | now; the S4 exit | 2–3 h; 4–6 h |
| F0 | F0 | the S5 exit and the user's go | 4–6 h |
| F1 | F1-0, then F1-S, F1-M, F1-E, F1-L in parallel, then F1-F and F1-X | F0 | 15–21 h |
| F2 | F2-C2 and F2-C5 in parallel | F1 | 12–16 h |
| F3 | F3-0, then F3-C1, then F3-C3 | F2 | 22–31 h |
| F4 | F4-C4 and F4-C6 in parallel | F3 | 12–16 h |
| F5 | B2, B5, B7; then the user's decisions | F4 and FP1 | 5–8 h |

**Total, F0 to F5:** about 70–100 hours of Codex work, three to four times S4's
estimate, plus a stop at every wave. **F3-C1 is the widest range:** it touches every
construct, and the `dump-ir` differential is what keeps it safe.

## 5. Gates

**For every package:**
- **The post-S5 full gate,** including Guardian and the `.my` format step after F1-F.
- **Differential against the pinned S5 compiler:**
  - 50 strict fuzz cases per kind for the package's kinds, and 200 per kind at each
    wave exit, with S3's tools (`experiments/new-core-s3-20261006/wave-x/integration/fuzz_matrix.py` and
    `fuzz_qualification.py`), using the pin as the `--old` oracle;
  - the generators emit only spellings both compilers accept. After A3 they keep using
    the operators the pin knows.
- **Migrations:** every migrated corpus program's output equals its unmigrated output
  under the pin.
- **`dump-ir` identical** wherever a package claims no change in meaning: F0, F3 and
  F4-C6.
- **The corpora:**
  - `tests/lang`, with 0 failures;
  - Lox: conformance 974/974 and its 65 tests;
  - EDA: 310 tests and 34 byte-identical goldens;
  - also `test/core` (the rows), `bench/parity`, `examples` and `src/stdlib`.
- **Check timing** on the synthetic projects at 48k, 96k and 192k lines, measured on
  CPU 10: after a one-function edit, unchanged, and cold, all within §1's budget.
- **Compiler rebuild** within 10% of S5's measured time, uncontended.
- **The idiom suite** (F1 and later): C2 = 0, and C1 and C3 reported.
- **Line deltas** per package, by the proposal's §2 file groups.

## 6. Rules

- **A wrong answer is never acceptable.** A fuzz or migration mismatch is reduced to a
  regression fixture before it is fixed.
- **Stop at the end of every wave** for the user's go. Also stop at F2-C2's P4 list and
  at F5's decisions.
- **No pushes,** and nothing merged into `main` unless the user says so.
- **Persisted formats** bump their version once per wave when they change.
- **`ir.zig` stays frozen through F0–F4.** C1's desugaring produces today's
  `typed.Program` shape. A package that needs an IR change stops and reports.
- **External corpora:** Lox and EDA are migrated on new branches. Never edit an existing
  branch in place.
- **Machine:**
  - builds go through `scripts/build-slot.sh`;
  - timing only on CPU 10, and never on CPUs 2, 3 or 11;
  - never prune `runtime-baseline-20261003`;
  - at most four build-heavy agents;
  - never run the full gate while a fuzz matrix runs;
  - commit large evidence in batches of one directory each.
- **Out-of-scope front-end bugs** get a regression fixture and a report. A package fixes
  one only if the fix is small and inside its owned files.

## 7. Reports

**Every wave's report has:**
- package commits;
- the gate receipts in §5;
- line deltas;
- check timings against the budget;
- for F1, the idiom-suite table and the migration counts;
- every remaining limit.

**The F5 report** carries the decision tables for B2, B3 and B4.
