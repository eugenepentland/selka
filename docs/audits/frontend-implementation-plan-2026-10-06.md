# The front end after the new core: implementation plan, 2026-10-06 (updated 2026-10-08)

Status: **ready for Codex; one launch (below).**
- Decisions were accepted on 2026-10-06 (§2). The values-and-keys plan's AM1–AM3 amended
  them on 2026-10-07 (marked AM in §2).
- **Updated on 2026-10-08 for the S5 exit,** which is merged into `main` at `5a6b501d`:
  - §1 holds the S5 facts that were marked _finalize at the S5 exit_;
  - F0 is mostly done by S5 (§3), and its remainder moves into F1-0;
  - FP2 and FB1 now run in the first wave;
  - the budgets, migration volumes and citations are rechecked against `main`;
  - **§6.1 adds the slow-step rule.**
- The companion plan is `docs/audits/values-keys-trap-search-plan-2026-10-07.md`.
- The rationale, the measurements and the original file:line facts are in the proposal,
  `docs/audits/frontend-plan-after-new-core-2026-10-06.md` ("the proposal"). Its evidence
  is in `experiments/frontend-plan-20261006/`.

**The goal (the user, 2026-10-06):** the language works like Go. There is one way to
express each thing, and performance is predictable. The spelling stays Python's, because
agents write Python first.

## Launch instructions (for Codex)

> Implement the front-end plan `docs/audits/frontend-implementation-plan-2026-10-06.md`,
> as committed on branch `claude/frontend-plan`. Create `codex/frontend-integration` from
> that commit; it is `main` at `5a6b501d` plus this plan update.
>
> **Wave 1:**
> - F1-0 on the integration branch. It includes F0's remainder and the slow-step baseline
>   (§6.1).
> - FP2 on `codex/frontend-fp2`.
> - FB1 on `codex/frontend-fb1`.
> - Then F1-S, F1-M, F1-E and F1-L as slots free up, F1-D in the first free slot after
>   them, then F1-F and F1-X.
> - Merge FP2 and FB1 into the integration branch when they pass their exits.
>
> **Then** F2, F3, F4 and F5 in order.
>
> **Rules:**
> - Hold every gate in §5 and every rule in §6.
> - **§6.1:** every build, test or tool command is timed. Any command that takes more than
>   5 minutes gets a speed investigation, and a speedup is implemented when it keeps the
>   check identical.
> - **Stop at the end of every wave** with its report (§7) for the user's go. Also stop at
>   F2-C2's P4 list and at F5's decisions.
> - Never merge into `main` and never push.

## 1. Where it starts

- **The base is `main` at `5a6b501d`.** It holds the S5 exit (`ad8932de`, report
  `experiments/new-core-s5-20261007/REPORT.md`) plus two post-S5 fixes:
  - `mylang` starts without a stack trace per allocation (MYLANG-START-1);
  - a unit test's guest programs build as one parallel batch
    (NEW-CORE-S5-UNITS-BATCH-1).

  `mylang` is the only binary. It builds, runs and tests through the new core. The old back
  end, QBE, bytecode and the GC are deleted.
- **FE7 is done by S5:**
  - project `check` uses the merged check (S5-A);
  - `fix_command.zig` no longer imports old back-end files;
  - `mylang-core` merged into `mylang`.

  The developer commands are `mylang dump-typed`, `mylang dump-ir` and `mylang coverage`.
- **The oracle is the S5 compiler, in two forms:**
  - **Frozen answers.** S5-0's references (`experiments/new-core-s5-20261007/references/`):
    `conformance-v1.json` for 1,636 tests and `fuzz-v1.json.gz` for 9×200 fuzz cases, with
    the tools in `experiments/new-core-s5-20261007/tools/`. S5 matched them with 0
    mismatches, so they are the expected answers for every program they cover.
  - **The pin.** A program without a frozen answer runs on the pin. F1-0 builds the pin
    once from `5a6b501d`: `zig build -Doptimize=ReleaseFast --prefix <cache>/mylang-s5-pin`
    through `scripts/build-slot.sh build`. It records the SHA-256 and never rebuilds it.
- **Measured at the S5 exit** (S5 report; ReleaseFast `mylang`; synthetic projects from
  `experiments/new-core-s4-20261006/gen_program.py`):

  | Measure | S5 exit | Budget for this plan |
  |---|---:|---:|
  | Merged check at 96k lines after a one-function edit | 0.226 s | **≤ 0.25 s** (was 0.45 s) |
  | The same, unchanged / cold | 0.025 s / 0.544 s | ≤ 0.03 s / ≤ 0.60 s |
  | Debug rebuild after a one-function edit, 48k / 192k lines | 0.97 s / 3.1 s | ≤ 1.1 s / ≤ 3.5 s |
  | Compiler rebuild after a one-line edit (`zig build`, Debug, Guardian included) | 4.3–4.5 s | ≤ 5.0 s |
  | Full gate (`zig build test`, 88 steps) | 155 s on `ad8932de`; `zig build test` 82 s on `main` | reported; §6.1 applies above 5 min |
  | `test-units` unsharded | 54 s warm, 99 s with every program rebuilt | reported |
  | Lox port: build after a one-function edit / tests after the edit | 0.143 s / 0.623 s | ≤ 110% |
  | EDA Stage 1: build after a one-function edit / tests after the edit | 0.658 s / 0.552 s | ≤ 110% |

- **The front end is 44.4k lines in 133 files.** That is the non-test `@import` closure
  of `sema.zig`, `parser.zig`, `lexer.zig` and `typed.zig`, outside `src/core`. It was
  46.6k lines in 136 files before S5.
- **What S5 already deleted of C0** (proposal §5; S5-D1, `6079efb2`):
  - legacy sharing mode, `class` and `Cell` (`alias_warning.zig` is gone);
  - `bytecode_model.zig` and the bytecode validators;
  - the VM values;
  - `mut_abi`'s caller-storage ABI;
  - the old typed fields;
  - `module_compile.zig` and `module_build.zig`.

  `typed.Type` moved to `type_identity.zig`. What is left is listed in F1-0 (§3).
- **The external corpora** are the trees S5 measured:
  - **Lox:** `codex/s4-lox-value-semantics` at `f44302d8`, path
    `benchmarks/lox/ports/mylang`; 974/974 conformance and 65 tests.
  - **EDA Stage 1:** `eda-bench` `claude/s4-eda-newcore` at `7e938b6`; 310 tests and
    34/34 goldens.
- **The citations below are rechecked against `5a6b501d`.** Proposal §5's line numbers
  are from before S5. Where they differ, this plan's numbers win.

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

**The rows, with the exact rule each package implements.** The rationale counts come from
the 2026-10-06 corpus scan (`spellings.txt`). The migration volumes in F1 were recounted on
`main` at `5a6b501d`.

| Row | Removed | The one way | Fix rule |
|---|---|---|---|
| **A1** | the `replace` builtin, both its record form `replace(r, f=v)` and its list form `replace(xs, i, v)` | `r.f = v`, `xs[i] = v` | `y = replace(r, f=v)` becomes `y = r` then `y.f = v`. Elsewhere, a fresh local is assigned before the statement. `s.replace(a, b)` on text is a different method and is untouched. |
| **A2** | **dropped:** positional and named record construction both stay (see below) | | |
| **A3** | `bit_and`, `bit_or`, `bit_xor`, `shift_left`, `shift_right` | `&`, `\|`, `^`, and new `<<`, `>>`, `<<=`, `>>=` | Rewrite to the operator, parenthesized. The new operators take Python's precedence (looser than `+`, tighter than `&`) and today's function semantics: the count has the operand's type, `<<` discards high bits, `>>` is arithmetic for signed and logical for unsigned, and a negative or too-large count traps `R_INVALID_SHIFT` (`E_CONSTANT_ARITHMETIC` for a constant). |
| **A4** (with AM2) | `effects(...)` and `noio` clauses, on declarations, on `extern def` and on function types; the `noalloc` clause; `W_DERIVED_EFFECTS` and `E_DERIVED_EFFECTS` | **no effect annotations.** Authority reaches a body only through its parameters. The attribute `@noalloc` on a declaration is the one allocation promise. | On a declaration, a clause that excludes `managed_allocation` from the derived ceiling, and every `noalloc` clause, becomes `@noalloc`. Any other clause, every `noio`, and every clause on a function type is deleted. |
| **A5** (with AM2) | the `noalloc` clause becomes `@noalloc` (A4) | `@noalloc`, checked by the new core at build time (F2-C2) | — |
| **A6** | **dropped (AM1):** `@requires`, `@ensures` and `@invariant` stay | | Trap search reads them (values-and-keys plan §3.4–§3.5). |
| **A7** | the `module NAME` header, `E_MODULE_NAME`, and the headerless-entry restriction (`E_MODULE_HEADER`) | **the path is the name:** a file's module name is its path from the project root, without `.my`, with `/` read as `.`. The project root is the directory holding `mylang.json`, else the entry's directory. | Delete the header line. |
| **A8** | `class` (legacy sharing mode), `with arena()`, `escape()` | value records; arenas already retired (N6) | **Mostly done by S5:** `class`, `Cell` and legacy sharing are gone. `with arena():` still parses and only warns `W_ARENA_RETIRED` (`src/arena_fix.zig`), and 12 `tests/lang` files use it. F1-0 makes it `E_ARENA_REMOVED`; `mylang fix` already removes the line. |
| **A9** | `type X = Y` aliases | the type itself | Substitute `Y` at every use in the project, then delete the alias. |
| **A10** | `;` separators | newlines | Split the line. |
| **A11** | `x == None`, `x != None` on an `Option` | `is None`, `is not None` | Rewrite the operator. |
| **A12** | `strings` functions that have an exact `str` method or builtin equivalent | the method or builtin; the module keeps the rest | Rewrite the call. F1-L first builds the mapping table, with equivalence evidence. |
| **A13** | `sort` functions duplicating `sorted`, `.sort`, `min` and `max` | those; the module keeps binary search and the deduplication helpers | Rewrite the call; same mapping rule as A12. |
| **A14** | the free-function form of a capability operation that also has a method form: `read_text(fs, p)`, `open(fs, p, mode)` and the rest of `docs/io.md`'s table, and the same duplicates on other capabilities | the method, `fs.read_text(p)`; `with fs.open(...)` stays, because streaming is a different operation (Go keeps both `os.ReadFile` and `os.Open`) | Rewrite to the method. |
| **A15** | named `constraint` declarations | inline requirements; the builtin requirements and const lengths stay | Inline the constraint's requirements at each use. |
| **A16** (AM3) | `domain D: base:` declarations, `wrap[D](v)` and `unwrap(d)` | `record D: value: base`, with the validating member as `@invariant(...)`; members become top-level functions in the module, and `private def` members module-private | `wrap[D](v)` becomes `D(value=v)` and `unwrap(d)` becomes `d.value`. The declarations are migrated by hand. |

**AM1–AM3 (the user, 2026-10-07)** come from the values-and-keys plan's VK7–VK9:
- **AM1 keeps contracts.** Trap search uses `@requires` to discard inputs and blame
  callers, `@invariant` to filter generated records, and `@ensures` as a property.
  `docs/contracts.md` states the rule for `@requires`, `Result`/`Option` and `assert`.
- **AM2 deletes effect checking.** Authority reaches a body only through its parameters,
  so after A4 the per-body check enforces nothing the types don't.
  - **`@noalloc` is checked by the new core at build time, not by trap search** (the
    user's change to VK8).
  - The check runs over the whole program before optimization, so debug and release
    agree. It follows every path through callees, and callees need no annotation.
  - A call through a function value whose target the core cannot resolve counts as
    allocating.
  - A violation is the warning `W_NOALLOC_ALLOCATES`, naming the allocation site and the
    call chain. `mylang lint --gate` blocks on it, and `check` never rejects for it.
    That keeps VK4 (no whole-program proof obligations in `check`) and C2 (no call-graph
    inference in the checker).
- **AM3 adds A16.** It needs AM1, because `@invariant` is what keeps a domain's values
  valid.

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

- **FE4, cost:** the per-function cost report comes early (FB1, in wave 1). The
  hidden-copy warning comes in F5. Whether an explicit `.copy()` is required is decided
  on P1's data (FB1's exit).
- **FE5, O(n) operators and literals:** B3 (O(n) operators) and B4 (fixed-array
  literals) are decided on FP2's typed count.
- **FE6, generics:** a template is checked once, symbolically, against its bounds. A
  specialization is instantiated by substitution, and errors stay at the definition.
- **FE7, S5: done.** S5 carried all three items (§1).

## 3. Work packages

Each package runs in its own locked worktree. It commits with Guardian's checks and
records evidence under `experiments/frontend-<package>-<date>/`, one log per command run.
**Owns** lists the files a package may change. A change needed elsewhere goes through
the coordinator.

### Wave 1 data packages (with F1-0)

These two run beside F1-0, each on its own branch. Neither touches the front end.

#### FP2. Typed count of O(n) operators (about 2–3 h; no compiler change)

**What:**
- Write a walker over `mylang dump-typed` output.
- **The corpora:** the EDA slice (`eda-bench` `claude/s4-eda-newcore` `7e938b6`), the
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

#### FB1. Per-function cost report (about 4–6 h)

**What:**
- `mylang cost <entry> [function]`, with text and `--json` output. Per function, it
  reports:
  - checks kept and checks proved;
  - updates made in place, tested for uniqueness at run time, or copied;
  - allocations;
  - retains and releases;
  - inlined calls;
  - vectorized loops, read from LLVM's optimization remarks. Where `zig cc` cannot
    produce remarks, the loops are reported as unknown.
- **B6:** the report and `@noalloc`'s build-time check (F2-C2) share one definition of
  "allocates", so they cannot disagree.

**Owns:**
- `src/core/`: a new `cost.zig` and the stats plumbing it reads;
- the `cost` entry in `src/core/cli.zig`;
- the docs for the command;
- its `features.json` slug.

**Exit:**
- On all 46 rows, the report's totals equal `--stats`'s.
- Tests cover every count.
- **P1:** the report over the Lox port and the EDA slice, with in-place, tested and
  copied counts per function and the 20 functions with the most copies.
- `list-interfaces --cost` is added by the coordinator once FB1 merges.
- FB1 keeps the branch name `codex/frontend-fb1`, because the values-and-keys plan's VP3
  starts from it.

### F0. Cut loose from the old back end: done by S5, remainder in F1-0

S5-D1 (`6079efb2`) did proposal §5 C0:
- legacy sharing, `class` and `Cell`, and `alias_warning.zig`;
- `bytecode_model.zig` and the bytecode validators;
- the VM values;
- `mut_abi`'s caller-storage ABI;
- the old typed fields;
- `module_compile.zig` and `module_build.zig`;
- `typed.Type`, moved to `type_identity.zig`.

What is left is small and goes into F1-0, so there is no separate F0 wave:
- **`with arena():` becomes the error `E_ARENA_REMOVED`.**
  - Today it is the warning `W_ARENA_RETIRED`.
  - Migrate the 12 `tests/lang` files that use it with `mylang fix`, which removes the
    line and dedents the body:
    - `option_niche`, `discard_names`, `record_field_snapshots`;
    - nine `rc_*` files.
  - Retire the slug with the rest of Part A's.
- **`value_semantics.zig`'s leftover "lowering facts".** Delete whatever has no reader
  left; the module's own doc comment still names them.
- **A sweep for files no one imports**, by `@import` closure over every root in
  `guardian.toml`, with Guardian's orphan check as the judge.

### F1. Part A and the format gate (about 17–24 h)

#### F1-0. Shared tools, baselines and F0's remainder (coordinator; about 4–6 h)

- **F0's remainder** (above), committed first.
- **The slow-step baseline (§6.1).**
  - Time every command §5 runs, once, uncontended, on `5a6b501d`.
  - Record each in the ledger `experiments/frontend-integration-<date>/slow-steps.md`.
  - Open an investigation for each command over 5 minutes.
- **Freeze the oracle's answers.** For every corpus program that S5-0's references do not
  cover, record the pin's output once, in the same reference format: Lox, EDA,
  `examples`, `src/stdlib` and `test/core`. Every later differential then reads answers
  instead of running the pin. S5-0 did this for the old core and cut the 9×50 fuzz
  matrix from 16 to 2 minutes.

- **The removed-spellings table: one file.**
  - Move the parser's `declaration_hints`, its ad hoc `alternative` branches and
    `removed_names.zig` into it.
  - The parser, `doc-coverage` and the velocity classifier read it.
  - `doc-coverage` fails when an entry lacks a `# doc: expect-error` example. That
    replaces prose lists such as `docs/python-syntax.md:528`, which still calls the
    accepted `is None` rejected.
  - `src/syntax_table.zig` exists only as an untracked file in the main checkout. It is
    another session's work and on no branch; reuse it only if the user lands it.
- **The embedded-source migration tool** `scripts/migrate_embedded.py`.
  - It runs `mylang fix` over three shapes, like `scripts/migrate-print-to-stream.py`:
    `.my` files, ```` ```mylang ```` blocks in `.md` files, and Zig multiline literals
    in tests.
  - Tests and docs embed many sources, for example about 630 `module` headers inside
    Zig test literals on `main`.
  - Python is acceptable here: the script maintains the repository and is never needed
    to build or use mylang.
- **Baselines:**
  - `velocity/score.py --json`: C1 first-try fidelity, C2 silent wrong answers and C3
    rejections carrying a fix;
  - the spelling counts, with `count_spellings.py` extended to the live repository and
    embedded sources;
  - every corpus program's output under the pinned S5 compiler, for the migration check
    in §5.

#### F1-S, F1-M, F1-E, F1-L, then F1-D (four agents in parallel after F1-0; F1-D takes the first free slot)

| Package | Rows | Owns | Estimate |
|---|---|---|---|
| **F1-S** syntax and expressions | A1, A3, A9, A10, A11, A15, the `lambda` narrowing | `parser.zig`, `lexer.zig`, the sema files for those builtins and operators, alias resolution, `constraint_lookup` | 5–7 h |
| **F1-M** modules | A7 | project loading and import resolution, `mylang run`'s project detection, the header rule in the parser (coordinated with F1-S) | 5–7 h |
| **F1-E** effects | A4, A5 | effect-clause parsing in the parser and `effects.zig`, function-type clauses, the `@noalloc` attribute (still checked by today's rule until F2-C2), `docs/effects.md`, `docs/functions.md`, the `effects(output)` line in `CLAUDE.md` | 4–6 h |
| **F1-L** library | A12, A13, A14 | `src/stdlib/strings.my` and `sort.my`, the capability free-function builtins, `docs/io.md`, `docs/standard-library.md` | 3–5 h |
| **F1-D** domains (AM3) | A16 | domain declarations in the parser and sema, `src/domain_codecs.zig`, `examples/domains.my`, `examples/domain-codecs/`, `docs/domains.md` | 4–6 h; starts when the first of the other four finishes, to hold the four-agent limit |

**Common to the four** (and to F1-D):
- **Each migrates every live source with its fixes,** through `mylang fix` and the
  migration tool, in its own commit. That includes tests, docs, examples, `src/stdlib`,
  `velocity/suites`, `bench/` and `test/`.
- **Migration volume on `main` at `5a6b501d`,** as lines in live `.my` files plus lines
  in Zig tests and docs. `experiments/` and design docs are excluded. These are regex
  counts; F1-0's extended `count_spellings.py` is authoritative.

  | Row | `.my` | Zig and docs |
  |---|---:|---:|
  | A7 module headers | 566 | ~630 |
  | A4 effect clauses | 366 | ~560 in Zig literals, plus docs |
  | A1 `replace(` | 54 | 76 |
  | A3 `bit_*`/`shift_*` | 59 | 44 |
  | A12 `strings.` calls | 58 | 56 |
  | A13 `sort.` calls | 31 | 24 |
  | A16 `domain` declarations | 27 | 25 |
  | A11 `== None` | 20 | 6 |
  | A15 `constraint` declarations | 14 | 6 |
  | A9 type aliases | 6 | 3 |

**Rules specific to rows:**
- **F1-M:**
  - A file whose path is not a dotted identifier path can be an entry but cannot be
    imported. The import's error says why.
  - `mylang run` loads the reachable graph whenever the entry imports a non-standard
    module.
- **F1-E:** if a fix makes an accepted program reject, stop and report. The rewrite
  only widens ceilings, so that must not happen.
- **F1-D:**
  - first inventory every domain declaration in the live sources, Lox and EDA, with
    their members and codecs;
  - a domain's one-field record must have the same layout and cost as its field in the
    core: check it with FB1's report and `dump-ir` on the migrated examples;
  - the removed spelling is `E_DOMAIN_REMOVED`, naming the record form.
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

### F2. Local analyses and stable type identity (about 13–18 h)

#### F2-C2. Signature-only analyses, without effect checking (one agent; about 10–12 h)

1. **P4 first.** Implement proposal §5 C2 behind a flag, **with effect checking removed
   (AM2)**. Run it over `tests/lang`, the rows, Lox, EDA and stdlib, and list every
   program whose verdict changes.
   - The only expected changes are programs that relied on `noalloc` being checked by
     the checker. The build-time `@noalloc` check (step 3) covers them.
   - **Stop and report** if any other accepted program changes verdict, or if a program
     is rejected for a fact a signature cannot state.
   - The fallback, if the user takes it, keeps inferred facts as diagnostics only,
     never in hashes.
2. **Then make it the default and delete:**
   - the call-graph passes;
   - the per-body effect check (`E_EFFECT_BOUND`), the inferred effect sets and the
     callback-type ceilings;
   - `return_origin`, `borrow_origin` and `caller_storage`;
   - the inferred fields in `module_interface.interfaceHash` and
     `semantic_key.contractDigest`;
   - `core/build.zig:217`'s refusal when inferred and declared mutation sets differ.
     The core reads `declared_mutates` only.
   - **`E_UNUSED_CAPABILITY` stays,** moved into sema's binding-usage check.
   - **Contract purity** (`CONTRACT-PURE-1`, `effects.zig:804`) becomes a local rule:
     a contract condition passes no capability and no `mut` argument.
   - **`docs/effects.md`** is rewritten as the capability rules: authority through
     parameters, `E_UNUSED_CAPABILITY` and `@noalloc`.
3. **The build-time `@noalloc` check in the new core** (AM2, §2): whole-program, before
   optimization, through every callee. It reports `W_NOALLOC_ALLOCATES` with the site and
   the call chain, the lint gate blocks on it, and FB1's definition of "allocates" is
   used.

**Owns:** `effects.zig`, `origins.zig`, sema's binding-usage check,
`module_interface.zig`'s hash, `semantic_key.zig`'s digest, `core/build.zig`'s mutation
read, the core's `@noalloc` check (a new `src/core/noalloc.zig`) and `docs/effects.md`.

**Exit:**
- P4's list reviewed;
- an effect change in a body no longer changes its callers' keys (a test);
- `@noalloc` tests: an allocation directly, in a callee two calls down, on a cold error
  path, and through an unresolved function value, each warned; an allocation-free
  function, not warned;
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
- **The remaining layers fold into it.** S5 deleted `module_compile` and
  `module_build`; these are left:
  - `check_cache`;
  - `frontend_cache`;
  - `semantic_cache` with `semantic_store`;
  - `generic_cache`;
  - `semantic_summary`;
  - `module_interface` with `module_interface_oracle`;
  - `incremental` with `invalidation`.
- **S5 limit 4:** `check-project --explain-invalidation` still lists the old lower,
  emit and link stages. This package removes them with the report-format bump.
- **Unchanged:**
  - `syntax_cache` stays the parse cache, under F4-C6;
  - codegen keeps S4's unit cache: debug builds cache LLVM-text units per module, and
    release builds are one unit (S4-1a).

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

**Then stop.** The user decides, on P1's (FB1) and FP2's data:
- B2's error: is `.copy()` required, or does the code need restructuring?
- B3: which O(n) operators change spelling, for example `xs.contains(x)`.
- B4: an explicit fixed-array constructor.

A follow-up plan implements those decisions.

## 4. Order and expected time

| Wave | Packages | Starts after | Expected wall time |
|---|---|---|---|
| 1 | F1-0 (with F0's remainder, the slow-step baseline and the frozen answers), FP2 and FB1 in parallel; then F1-S, F1-M, F1-E, F1-L as slots free, F1-D in the first free slot, then F1-F and F1-X | the user's go | 19–28 h |
| F2 | F2-C2 and F2-C5 in parallel | F1's exit and the user's go | 13–18 h |
| F3 | F3-0, then F3-C1, then F3-C3 | F2 | 22–31 h |
| F4 | F4-C4 and F4-C6 in parallel | F3 | 12–16 h |
| F5 | B2, B5, B7; then the user's decisions | F4 and FB1's P1 | 5–8 h |

**Total:** about 71–101 hours of Codex wall time, plus a stop at every wave. That is
F0's 4–6 h less than before, because S5 did most of F0, and FP2 and FB1 now run inside
wave 1.

- **Calibration:** S4 took about 22 h against its 20–28 h estimate. S5 took about 7 h
  against 32–51 h of package work, because most of it was parallel deletion.
- **This plan's critical path is mostly sequential:** F1's tail, then F2-C2, then F3-C1
  and F3-C3.
- **F3-C1 is the widest range.** It touches every construct, and the `dump-ir`
  differential is what keeps it safe.
- **The four-agent limit is shared:**
  - in wave 1, with FB1 and the values-and-keys plan's VP2 (VP1 builds nothing);
  - from F2 on, with that plan's T wave, which starts at F1's exit (its launch
    instructions). Front-end packages take free slots first.

## 5. Gates

**For every package:**
- **The post-S5 full gate,** including Guardian and the `.my` format step after F1-F.
- **Differential against the S5 oracle (§1).**
  - **Fuzz:** 50 strict cases per kind for the package's kinds, and 200 per kind at each
    wave exit, with S5-0's frozen tools in `experiments/new-core-s5-20261007/tools/`
    (`fuzz_matrix.py --references`, `qualify_merge.py`, `conformance_ref.py`).
  - **Generators:** they emit only spellings both the pin and the candidate accept. After
    A3 they keep the operators the pin knows.
  - **A changed generator** produces sources with no frozen answer, and the frozen tools
    stop on them. The coordinator then records the pin's answers for the changed kind
    once, in a new reference file (`fuzz-v2`), and says so in the wave report.
- **Migrations:** every migrated corpus program's output equals its unmigrated output
  under the oracle, read from F1-0's frozen answers.
- **`dump-ir` identical** wherever a package claims no change in meaning: F1-0's F0
  remainder, F3 and F4-C6.
- **The corpora:**
  - `tests/lang`, with 0 failures;
  - Lox: conformance 974/974 and its 65 tests;
  - EDA: 310 tests and 34 byte-identical goldens;
  - also `test/core` (the rows), `bench/parity`, `examples` and `src/stdlib`.
- **Check timing** on the synthetic projects at 48k, 96k and 192k lines, measured on
  CPU 10: after a one-function edit, unchanged, and cold, all within §1's budget.
- **Compiler rebuild** at or under 5.0 s after a one-line edit, uncontended (S5: 4.3–4.5 s).
- **Lox and EDA dev loop** within §1's budget: build and tests after a one-function edit.
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

### 6.1 The slow-step rule (the user, 2026-10-08)

**Any build, test, gate step, tool or measurement that takes more than about 5 minutes
of wall time gets a speed investigation.** The point is to keep the loop fast for every
agent after this one, not just to finish this plan.

1. **Time everything.** Every command a package runs goes in its evidence log with its
   wall time, its CPU affinity and whether another build-heavy process was running.
   F1-0 records the uncontended baseline of every §5 command in the ledger
   `experiments/frontend-integration-<date>/slow-steps.md`.
2. **Over 5 minutes, uncontended, investigate:**
   - measure where the time goes, using `--timings`, `--report`, per-test durations,
     `perf` or `strace` on a single run;
   - write down the cause.

   Look for these causes first:
   - work repeated across runs that a cache could hold;
   - work done serially that is independent;
   - an oracle or reference run again when its answer could be frozen;
   - a Debug compiler where a ReleaseFast one would give the same verdict;
   - rebuilding programs a test or gate did not change;
   - a quadratic step in the compiler itself.
3. **Implement the speedup** when all three hold:
   - it keeps the check identical: the same tests, cases, programs, modes and verdicts;
   - it fits in about 2 hours;
   - it lives in tooling, test drivers, the build script or the package's own files.

   Commit it alone, with before and after times and proof that the check is the same: the
   same counts and the same verdicts on a deliberately broken input.
4. **Otherwise, write a follow-up item** in the ledger with the measurement, the cause and
   the proposed fix, and carry on. Each wave report lists the open items, and the user
   decides which become packages.
5. **Never speed a step up by weakening it.** Do not drop tests, cases, programs, fuzz
   counts, corpora, modes (debug, release, verify) or leak checks. Do not raise a
   threshold or skip a step on a cache hit that is not proven equal. Any of these needs
   the user's go.

**Known candidates to check first** (from S5's evidence):
- **The frozen fuzz matrix at 200 per kind.** S5's final run spent 1,600 s summed over
  the nine kinds: from 109 s for `rc` to 310 s for `dict`.
  - Check how its kinds and cases are scheduled across free CPUs.
  - Check whether candidate builds of identical generated sources are cached.
- **The new differentials this plan adds:**
  - `dump-ir` over every corpus, twice per package;
  - P4's verdict sweep;
  - the migration-output check.

  Each should run its programs in parallel and reuse the oracle's frozen answers.
- **The pin's one-time ReleaseFast build** and any ReleaseFast install a package needs.
  Reuse one install per checkpoint.
- **A cold `test-units` run after a compiler change** took 99 s unsharded after S5's
  batching. Watch it as the front end changes, because every unit test runs `mylang`.

## 7. Reports

**Every wave's report has:**
- package commits;
- the gate receipts in §5;
- line deltas;
- check timings against the budget;
- the slow-step ledger (§6.1): every command over 5 minutes, what was found, what was
  sped up, with before and after times, and the open items;
- for F1, the idiom-suite table and the migration counts;
- every remaining limit.

**The F5 report** carries the decision tables for B2, B3 and B4.
