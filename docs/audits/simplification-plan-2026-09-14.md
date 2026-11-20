# Simplification and escape-hatch plan — 14 September 2026

Execution plan for the [language simplicity audit](language-simplicity-2026-09-14.md). It
converts that audit's findings into file-level workstreams that can run in parallel without
stepping on each other, and states what "done" means for each.

Decisions taken before planning (from the person directing the work):

- **Baseline:** start after `worktree-agent-a19af21c1f3b18345` (the native-run change) lands,
  on a fresh worktree branched from it.
- **Scope of this pass:** the five simplifications plus the performance escape hatch, minus
  three design projects (see §7).
- **Deletions:** remove the duplicate spellings outright and fail with a migration error that
  names the canonical spelling.

Because the interpreter is out of the run path and out of the test path on that baseline,
this plan is **QBE-only**: nothing here is implemented in `src/vm.zig`, `src/bytecode.zig` or
the dispatch modes, and VM parity is explicitly not a goal. That halves the backend work in
the audit's §2–§5 and removes the largest source of duplicated effort.

---

## 0. Baseline and prerequisites

The native-run branch is 15 commits ahead of this worktree and touches 93 files (7,494
insertions, 964 deletions): `src/main.zig`'s run path, new `src/native_run.zig` and
`src/native_execute.zig`, ~30 unit suites converted to native execution, new
`tests/goldens/qbe_*.json` parity fixtures. `src/vm.zig` and `src/bytecode.zig` are *not*
touched and still exist.

**Status — round 3 (execution).** The native-run work merged (`8779a3e`): `src/vm.zig` is
gone, `mylang run` builds and executes natively, and the doc gate is `mylang doctest .`.
`claude/simplify-20260914` was rebased onto it and carries W8 plus two small fixes (below).

Two facts that change how the rest of this plan should be run:

1. **The repository owner is working the same plan in the same worktrees, in parallel.**
   During round 3 their commits landed on branches this plan created: `c1fa6d3` on
   `claude/simplify-w3-collections` (16:56), `8927580` on `claude/simplify-w6-perf` (17:17)
   and `f3a76bd` on `claude/simplify-w4-builtins` (17:19), each committing working-tree state
   that the agents for those workstreams had produced. Two writers in one worktree produced a
   broken intermediate tree at least once (`src/sema.zig:1155`, an anonymous-struct type
   mismatch between `checkDictionaryMethod` and `checkManagedAccess`, since repaired by taking
   a named `ManagedAccess`). Workstreams must therefore be assigned to exactly one writer
   before they start, and the parallel fan-out below is only safe with distinct worktrees.
2. **`[N]T` is copied per element access, not per call.** Measured in the W6 worktree: a scan
   over `[4096]int` runs 6.15 s against 0.21 s for the same scan over `list[int]` (~29×), and
   the emitted IL shows four `blit`s of 32,768 bytes — one at entry and one per element read.
   The audit said "copied on every call", which understates it; the workstream's conclusion is
   that by-reference parameters are an analysis plus an ABI change, and it documented the cost
   in `docs/performance.md` instead of half-doing it.

Landed on `claude/simplify-20260914` (rebased, green):

- `d896864` — W8, the idiom probe harness: `tests/idiom_probes.py`, `tests/fixtures/idioms/`
  (55 probes + manifest + README). The `test-idioms` build step was dropped in the rebase
  because the gate no longer runs Python; the driver is run by hand. On the merged baseline
  it reports **11 probes at target, 44 unchanged, 0 changed, 0 regressions**.
- `2e0da58` — the `extern fn` → `extern def` correction in `src/features.json` (audit §7).
- `3ad0436` — the example corpus stops spelling the integer type `i64` (297 spellings, 91
  files in `examples/` and `test/fixtures/`, the duplicated pairs kept identical).
- `9aab482` — `wordUsed` no longer treats `//` as a comment, so floor division cannot hide a
  prelude type named later on its line (`PRELUDE-TYPES-1`, one primary test plus two coverage
  tests). Probes: 12 of 55 at target, no regressions. The sibling case — a program whose only
  byte-string use is a method result, `raw = "hi".encode()` with no `bytes` spelled anywhere —
  is deliberately not fixed here: the catalog index is a `*const`, so it needs on-demand
  materialisation or an AST walk over statement bodies rather than another text heuristic.

Parallel workstreams started in round 3, their work now on the owner's branches:
`claude/simplify-w7-docs` (six commits of its own: two experiment pages rewritten, one moved
to `docs/legacy/`, the guide reordered, twelve current pages corrected; `doc-coverage` 0
failures and `doctest` 103 run / 19 checked / 0 failed), `claude/simplify-w6-perf` (trap text
names the raising flag, `build` defaults to ReleaseFast, `math.sqrt` calls the intrinsic —
2.30 s → 0.42 s over 300k calls — plus `docs/performance.md`), `claude/simplify-w4-builtins`
(nine prelude builtins in a new `src/prelude_builtins.zig`, 21 of 55 probes at target on that
tree) and `claude/simplify-w3-collections` (slice step; augmented assignment, whose ordering
bug the agent diagnosed as "the combined init must follow the receiver, index and refresh").

Steps, in order:

1. Confirm the branch's own gate is green (`zig build test --summary all` in its worktree)
   and that it has no uncommitted work.
2. `git worktree add ../mylang-simplify -b claude/simplify-20260914 <that branch>`.
3. Verify the new baseline before writing anything:
   - `zig build` installs; `zig-out/bin/mylang run examples/factorial.my --print-result`.
   - `grep -rn "vm.zig\|VM" src/root_test.zig test/integration.zig` — establish which suites
     still execute the interpreter, and whether they must be ported to
     `src/native_execute.zig` or simply left alone.
   - `zig-out/bin/mylang run examples/factorial.my --print-result --max-steps=1` — confirm
     budgets still reach the program natively, because the escape-hatch work depends on it.
   - `zig build test-units -Dtest-filter=<something>` — confirm the fast loop still works
     now that unit tests execute natively.
4. Record the outcome in this file (a short "baseline verified" note) so every workstream
   starts from the same facts.

**Ownership rule.** One writer per file per wave. `src/parser.zig`, `src/sema.zig` and
`src/buffer_operations.zig` are the three contended files; every workstream that needs them
either owns them for its wave or is sequenced behind the one that does. New shared tables get
their own new small file so two workstreams can reference them without editing one file.

---

## 1. Workstreams

### W8 — Idiom acceptance harness (start first; nothing else depends on it)

**Goal.** Turn the audit's probe files into a checked-in driver so "did we simplify it?" has a
machine answer, and so each other workstream has a concrete list of probes to flip.

**Deliverable.** `tests/idiom_probes.py` plus `tests/fixtures/idioms/*.my` and an expectation
file. Each probe carries its expected outcome today (`error[E_LIST_METHOD]`) and its target
outcome (`42`). The driver runs every probe through the installed compiler and reports three
counts: still-failing-as-expected, newly-passing, regressed.

**Files owned.** `tests/idiom_probes.py`, `tests/fixtures/idioms/**`, `build.zig` (one driver
step). Nothing under `src/`.

**Done when.** The driver runs under `zig build test` and its report names each probe's state;
the probe set covers audit §2.1–§2.3, §5.1–§5.4 and §5.7 (roughly 60 programs).

**Size** S. **Risk** none. **Parallel with** everything.

### W7 — Documentation and example consolidation

**Goal.** One guide, one reference, one performance page; history out of the reader's path;
docs and examples stop teaching removed spellings.

**Work.** Fix the `extern fn` summary in `src/features.json`; add or remove the `domain`
feature entry with the doc anchor it needs; refresh the 25 brace-era `docs/experiments/*.md`
pages (or move them under `docs/legacy/`); update the 61 example files that declare
`-> i64` to `int`; front-load nothing advanced in the first 50 lines of
`docs/python-syntax.md`; add a gate that fails when a *current* page contains a removed
spelling (the list already exists in `features.json` `removed`).

**Files owned.** `docs/**` (except `docs/audits/**` until the end), `examples/**`,
`src/features.json`, `README.md`.

**Done when.** `zig build test-docs` and `mylang doc-coverage .` pass; no current page uses a
removed spelling; the example corpus checks clean.

**Size** M. **Risk** low, but it touches the same `features.json` that every feature
workstream edits — so it takes `features.json` in Wave A and later workstreams append their
slugs in their own waves.

**Parallel with** W8, W6a.

### W1 — The three defects a beginner meets first

**Goal.** One `len`, one shadowing rule, no source-text type scanning.

**Work.**
1. `len(x)` and `x.len()` return the same type (`int`). Decide which spelling survives —
   recommendation: `len(x)` only, with `x.len()` deleted in W2 and a migration error until
   then.
2. A declared function shadows a prelude operation consistently (`sqrt` wins today;
   `len`/`replace` do not). One rule, applied in `src/parser.zig:749`-adjacent routing.
3. Delete `src/nominal_type_syntax.zig`'s byte-scanning (`wordUsed`, `bytesSyntax`,
   `preludeUsed`, `textRequired` path) and register `str`/`dict`/`bytes`/`float`
   unconditionally in `src/nominal_templates.zig`'s `addPrelude`. This removes a class of
   "moving an operator changes whether the program compiles" bugs and deletes a subsystem.

**Files owned.** `src/parser.zig`, `src/sema.zig`, `src/buffer_operations.zig`,
`src/nominal_type_syntax.zig`, `src/nominal_templates.zig`, their tests, `SPEC.md`,
`src/features.json`.

**Done when.** The audit's §5.1–§5.3 probes pass; the full corpus (examples + corpus + stdlib
+ schematic) checks and runs; new `// spec:` tags exist for each rule change.

**Size** M. **Risk** medium on item 3: catalog selection changes for every program, so run
the whole corpus and the golden parity set, not just focused tests.

**Blocks** W2, W3 (both edit `buffer_operations.zig`/`sema.zig`).

### W6a — Escape-hatch truth and discoverability

**Goal.** The documented performance story matches the implementation, and the cheap fixes are in.

**Work.** Write `docs/performance.md` (write Python-shaped code; 20–34× from native; build
with `--mode ReleaseFast`; raise budgets with `--max-steps=`; keep `[N]T` off the hot path for
now; `extern def` for C; measure with `mylang run --timings` and `/usr/bin/time`). Default
`mylang build` to ReleaseFast (or print the mode prominently in `--report`). Add "raise it with
`--max-steps=N`" to the `R_STEP_LIMIT` trap text in `src/qbe_runtime.c`. Document
`mylang run --timings` and the budget flags in `docs/tooling/`. Resolve `nogc`: implement the
bound or correct `docs/audits/memory-concurrency-2026-09-13.md:43,88-90`.

**Files owned.** `docs/performance.md`, `docs/tooling/**`, `src/qbe_runtime.c`,
`src/qbe_build_options.zig`, `src/main.zig` (mode default only — coordinate: the native-run
branch owns the rest of that file, which is why this starts after it lands).

**Done when.** Each claim on the page is reproducible from the page's own commands; the
`R_STEP_LIMIT` message names the flag; `--report` states the mode.

**Size** S–M. **Risk** low. **Parallel with** W8, W7.

### W6b — Escape-hatch structural fixes

**Goal.** The performance path stops being self-defeating.

**Work.** (1) Pass `[N]T` parameters by reference in QBE instead of blitting per call (the
audit measured native being *slower* than the interpreter at `[4096]int`). This is an ABI
change: bump `mylang-qbe-native-v3` and regenerate `tests/goldens/qbe_*.json`. (2) Decide and
implement the writable-buffer story — either allow indexed assignment into a local array, or
state that the managed `list` is the mutable buffer and remove the "fixed array as fast
buffer" implication from the docs. (3) `math.sqrt` calls the intrinsic instead of a guest
Newton loop (11.6× measured), which needs the `float`↔bits bridge or a non-shadowed intrinsic
name. (4) Optional, larger: let `extern def` take a buffer so a C kernel can see guest data.

**Files owned.** `src/qbe_*.zig` lowering, `src/native_*.c`/`.h`, `tests/goldens/**`,
`tests/qbe_*.py`, `src/stdlib/math.my`.

**Done when.** The array-parameter benchmark in `tests/qbe_benchmark.py` shows native faster
than the interpreter at `[1024]int` and `[4096]int`; `math.sqrt` matches the prelude `sqrt`
within noise; goldens regenerated and reviewed.

**Size** L (items 1 and 4) / S (item 3). **Risk** high on the ABI change — it invalidates
cached objects and any external embedder; do it in its own branch with its own gate run.

**Parallel with** W1 (different files).

### W2 — Tier collapse and duplicate removal

**Goal.** One spelling per operation, with a migration error that names the replacement.

**Work.** Add `src/removed_names.zig`: a table of removed spellings → canonical spelling and
the diagnostic to emit. Delete `push`, `x.len()`, `d.contains`, the `List` alias, the 15
`f64_*` keywords, `codec_encode`/`codec_decode` (if the codec tier stays), the `*_cap`
spellings, the dead `std_result` lookup in `src/nominal_templates.zig:72`, and the dead `&`
and `=>` tokens. Replace the standard library's duplicates with delegation or delete them:
`strings.upper/lower/strip/lstrip/rstrip/count/find/starts_with/ends_with/is_digit/is_alpha/
is_space/to_int/lines/substitute` (15 of its 25 exports), `math.trunc/floor/ceil/sqrt/abs`
(5 of 25).

**Files owned.** `src/lexer.zig`, `src/removed_names.zig` (new), `src/prelude.zig`,
`src/nominal_templates.zig`, `src/stdlib/*.my`, `src/parser.zig` (keyword table only — after
W1 releases it), their tests, `features.json`, `SPEC.md`.

**Done when.** Every deleted spelling produces a located error naming its replacement; the
stdlib still exports everything the examples use (after W7's example refresh); doc-coverage
passes with the reduced feature list.

**Size** M. **Risk** medium: deleting keywords breaks fixtures and docs that use them; grep
for each spelling across `examples/`, `test/`, `docs/` first and land those updates with it.

**Sequenced after** W1.

### W3 — Everyday collection vocabulary

**Goal.** `xs.pop()`, `sorted(xs)`, `d.items()`, `x[i] += v` behave like Python.

**Work.** List methods `extend`, `insert`, `pop`, `remove`, `index`, `reverse`, `sort`,
`copy`, `clear`; dict `items`, `pop`, `update`, `setdefault` (decide the set); augmented
assignment on subscripts (`x[i] += v`, `d[k] += 1`) and `+=` for float/str/list; slice step
(`xs[a:b:n]`); destructuring iteration over `d.items()`.

**Implementation note.** Each method needs: a name in `src/buffer_operations.zig`'s table, a
type rule in `src/sema.zig`, lowering in `src/qbe_managed.zig`, runtime support in
`src/native_collections.c`, a `// spec:` test, and a doc anchor. Budget one small commit per
method so a failure is isolated.

**Files owned.** `src/buffer_operations.zig`, `src/parser.zig` (subscript augmented
assignment, slice step), `src/sema.zig`, `src/qbe_managed.zig`, `src/native_collections.c`,
`src/collection_lower.zig`, tests, docs, `features.json`.

**Done when.** Every collection probe in the W8 harness passes; list operations have defined
mutation-during-iteration and bounds behaviour matching the existing contracts.

**Size** L. **Risk** medium. **Sequenced after** W2 (shared `buffer_operations.zig`).

### W4 — Prelude builtins

**Goal.** `sum`, `min`, `max`, `sorted`, `abs(int)`, `round`, `any`, `all`, `zip`,
`reversed` exist without an import, and `abs` is total for `int`.

**Implementation note — prefer guest source.** These are total, side-effect-free, and already
exist in the standard library under other names. The cheapest implementation is to resolve
them to *embedded guest functions* the compiler injects (the same mechanism that embeds the
ten standard modules), so the frontend recognizes the bare name and the body is ordinary
mylang over `list`/`Option`. That removes almost all backend work and gets native support for
free. Where that is impractical (`zip` needs a new iteration shape; `abs(int)` needs the
`-2^63` decision), implement in the checker plus lowering.

**Files owned.** `src/sema.zig`, `src/prelude_builtins.zig` (new, embedded source),
`src/embedded_project.zig`, `src/parser.zig`, `src/stdlib/sort.my`, tests, docs,
`features.json`.

**Done when.** The builtins work in single-file programs, return the types Python users
expect (`min(xs)` → `Option[T]` where absent-able, or trap — decide and document), and carry
the right effects (`sorted` allocates, `sum` does not).

**Size** M. **Risk** medium on `zip`/`reversed` (new iteration shapes).

**Parallel with** W5b, W5c.

### W5 — Program edge

Four independent slices; three of them are file-disjoint.

- **W5a `lambda`** — parse `lambda x: expr` into the existing non-capturing
  `def(T) -> U effects()` value. Parser + checker only; no captures, no new semantics.
  Files: `src/parser.zig`, `src/ast.zig`, `src/sema.zig`. Size S.
- **W5b `main` returns a renderable `Result`** — accept `def main(...) -> Result[None, E]`
  for renderable `E`, print the `Err` payload to stderr, exit non-zero. Files:
  `src/entry_adapter.zig`, `src/native_run.zig`, `src/qbe_*` entry emission, tests. Size M.
  Risk medium (entry ABI, exit codes, every fixture that returns `int`).
- **W5c `const` holds `bytes`/`str` literals** — a literal initializer is static and
  allocates nothing. Files: `src/constant_values.zig`, `src/sema.zig`, tests, docs. Size S.
  Removes 23 wrapper functions and a 16-line ladder from the schematic alone.
- **W5d `?` on `Option`** — propagate `None` in an `Option`-returning function. Files:
  `src/sema.zig`, `src/qbe_*` propagation lowering, tests. Size S–M.

**Done when.** Each slice has its spec tag, its probe flips in the W8 harness, and the
schematic/invoice corpus loses the boilerplate the audit quoted.

### W9 — One `run` command (small, may be folded into W5b)

`mylang run file.my` accepts a file with `module`/`import`/`export` headers and does the
project load itself, so a single file can use `math`, `sort` and `strings`. `run-project`
stays as an explicit alias. Files: `src/main.zig` (after the native-run branch lands),
`docs/python-syntax.md`, `docs/modules.md`. Size S.

---

## 2. Waves

The constraint is that `parser.zig`, `sema.zig` and `buffer_operations.zig` each have one
writer. Parallelism therefore comes from separating frontend, backend, runtime, library and
documentation work, not from running five frontend features at once.

| Wave | In parallel | Serialized in the wave |
| --- | --- | --- |
| A | W8 harness (`tests/`) · W7 docs+examples (`docs/`, `examples/`, `features.json`) · W6a perf truth (`qbe_runtime.c`, build defaults, new `docs/performance.md`) | — |
| B | W1 defects (frontend core) · W6b array ABI + `math.sqrt` (lowering + runtime C) | — |
| C | W2 tier collapse (lexer, stdlib, removed-name table) | — |
| D | W4 prelude builtins (new embedded file + sema) · W5b main-Result (entry path) · W5c const bytes/str (constants) | W5b and W5c are frontend-adjacent but file-disjoint from W4 |
| E | W3 collections (the largest, alone on `buffer_operations.zig`/`sema.zig`/`qbe_managed.zig`) · W5a lambda (parser/ast/sema — coordinate, sequential if W3 is mid-flight) | W5a after W3 if `sema.zig` is contended |
| F | W5d `?` on Option · W9 one `run` command · final docs pass | — |

Every wave ends with the gate (§4) and a merge into the simplification branch.

---

## 3. Definition of done for every workstream

Carried from `CLAUDE.md` and the Guardian policy, because these are what actually block a
merge here:

- **Spec tag per behavioural change:** every added behavioural line under `src/` has a test
  carrying `// spec: TAG` and a matching `- [TAG] …` bullet in `SPEC.md`.
- **Feature/doc contract:** each new or changed feature slug in `src/features.json` has
  `{kind, summary, doc}`, and the `doc` anchor resolves to a section with a runnable example;
  `mylang doc-coverage .` passes.
- **Guardian limits:** ≤7 struct fields, ≤6 function parameters, `///` on every `pub`
  declaration, no `@import` cycles, new files reachable from the roots in `guardian.toml`,
  no type-size ratchet growth (accept a baseline only deliberately).
- **Test style:** at least one `expect*` per test, straight-line bodies (no top-level
  `if`/`while`/`switch`).
- **Fast loop while working:** `zig build test-units -Dtest-filter=SUBSTRING`,
  `zig build test-cli -Dtest-filter=SUBSTRING`, `zig-out/bin/mylang test <dir> --filter …`,
  `zig build test-docs` (which is `mylang doctest .` under a step name).
- **Sandbox notes that cost time to rediscover:** `ZIG_GLOBAL_CACHE_DIR` must point somewhere
  writable (`/tmp/mylang-zig-global` works) or every `zig build` fails with
  `manifest_create AccessDenied`; `mylang run`/`build`/`test` invoke Zig for the runtime, so
  they need it too. `/tmp` is per-shell-call here, so scratch files belong inside the
  worktree. A `std.debug.print` left in `src/` fails the `debug-print-ban` Guardian check.

---

## 4. Gate per merge

```sh
zig build test --summary all
zig build test-qbe --summary all
zig build test-qbe-build --summary all
zig build fmt-check
```

Plus three corpus checks that catch what unit tests miss:

```sh
zig-out/bin/mylang check-project examples/corpus/invoice/main.my
zig-out/bin/mylang run-project examples/corpus/invoice/main.my --print-result   # 7019
zig-out/bin/mylang test tests/fixtures --filter '*'                             # guest tests
```

`python3 tests/idiom_probes.py --compiler zig-out/bin/mylang` is the acceptance spine: no
regressions, and a monotonically shrinking "not yet" count. It is deliberately **not** wired
into `zig build test` any more — the gate stopped running Python in the interpreter-removal
change — so run it by hand as part of the merge, and port it to a Zig-native path if it is to
become a step again.

## 5. Merge order and rollback

W8 → W7 → W6a → W1 → W6b → W2 → W3 → W5c → W5b → W4 → W5a → W5d → W9 → final docs.

Docs land first so the guide describes the target, but the *feature* docs for each new
feature are written by that feature's workstream. Each workstream is its own branch, so a
failed gate reverts exactly one thing.

## 6. Risks

| Risk | Where | Mitigation |
| --- | --- | --- |
| `[N]T` by-reference ABI break | W6b | its own branch, ABI version bump, regenerate and review goldens, keep the old convention behind a flag if embedders depend on it |
| Prelude-type registration change alters catalog selection for every program | W1 | run the full corpus and the golden parity set, not just focused tests |
| `main` returning `Result` changes exit codes | W5b | keep `int`/`None` entry behaviour byte-identical; add cases before changing the adapter |
| Deleting keywords/methods breaks fixtures, docs, stdlib | W2 | grep each spelling across `examples/`, `test/`, `docs/`, `src/stdlib/` and land the updates in the same branch |
| `const` evaluator is shared with module constants and schemas | W5c | literal-only initializer keeps it static; test the schema and input-manifest paths |
| Doc gate blocks every feature that adds a slug | all | treat the doc anchor as part of the feature commit, never a follow-up |

## 7. Deferred by decision (not in this pass)

- Methods or `Type.func(value)` namespacing on classes (audit recom. 14).
- `export` prefix replacing directive lists (audit recom. 13).
- A declared domain representation conversion (audit recom. 12) — revisit with the `domain`
  tier decision, which W7's doc work will force.
- Tuples, record equality, truthiness, exceptions: keep excluded.
- `extern def` taking a buffer, unless W6b item 4 is pulled in.

---

## 8. First actions when the baseline lands

1. Verify the branch is finished and its gate is green; create
   `../mylang-simplify` on `claude/simplify-20260914`.
2. Run the §0 baseline checks and append the results here.
3. Start Wave A: W8 (harness), W7 (docs/examples), W6a (perf truth) in parallel.
4. Report the wave-A results, then start Wave B.
