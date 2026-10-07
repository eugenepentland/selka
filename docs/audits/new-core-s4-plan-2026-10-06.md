# New compiler core, stage S4: projects — implementation plan, 2026-10-06

Status: **ready for Codex.** S3 exited on 2026-10-06 (§1), Wave 0 is complete (S4-L,
S4-D; §3.5), and the S3-exit facts are filled in (S4-0). The design for the emission and cache packages is
`docs/design/new-core-s4.md`. The measurements behind it are §3, with evidence in
`experiments/new-core-s4-20261006/`.

The stage, from the new-core plan (`docs/audits/new-core-plan-2026-10-05.md` §6):

| Scope | Exit check |
|---|---|
| Modules and `.myi` interfaces, incremental per-module builds, `mylang test` on projects, the Lox port, an EDA slice. | The Lox port and the EDA slice pass their tests under the new core, with build and test times at or below the old core's. |

## Launch instruction (for Codex)

> Implement stage S4 of mylang's new compiler core following
> `docs/audits/new-core-s4-plan-2026-10-06.md` and `docs/design/new-core-s4.md`.
> Create `codex/new-core-s4-integration` from `codex/new-core-s3-integration` at
> `82c125dd` (the S3 exit report; its source is `d4994214`). Merge
> `claude/new-core-s4-design` and then `claude/new-core-s4-rows` into it (S4-0, S4-R),
> and integrate there. Run Wave A, then Wave B, then S4-X, holding every gate in §6
> and the rules in §7. Never merge into `main` and never push. Finish with the §8 exit
> report and stop for the user's go/stop decision on S5.

## 1. Where the new core starts

- **Front end.**
  - `src/core/frontend.zig` loads a module graph through `project_compile.Compilation`
    and checks the merged program with `check()`, which is `checkWithCache(null)`.
  - **The new core uses none of the old core's per-function check caches**: every
    build rechecks every module.
  - The old core's `mylang build` passes a `semantic_cache.Cache` (function bodies,
    symbolic generics, specializations; formats `module-interface-v5`,
    `check-summaries-v6`, `mutation-v2`).
- **Back end.**
  - `src/core/pipeline.zig` builds one Core IR module for the whole program, runs the
    release passes, emits one `.ll` and compiles it with one `zig cc` call.
  - Only the runtime object is cached. Nothing of the program is reused between
    builds.
- **Whole-program optimizations the back end relies on:**
  - the leaf inliner (`inline.zig`);
  - caller-derived parameter intervals (`NEW-CORE-FACTS-10`, which need every call
    site);
  - the ownership pass's callee summaries;
  - the merged standard library (S3-A).
- **Old-core reference numbers** (scale probe, 53k-line project, 2026-09-17): per-edit
  check 3–4 s, cold build 746 s, warm build 70 s.
- **The S3 exit** (`experiments/new-core-s3-20261006/wave-x/REPORT.md`): every S3 exit
  check green on `d4994214`. That includes 277/277 core tests, conformance
  1518/0/0 per mode, the full old gate, 25,800 fuzz comparisons, 80/80 row cells within
  both gates, and coverage 3,633/3,639. The new core accepts all of `tests/lang` except
  user modules and the retired arenas.

## 2. Decisions

### S4-1. Caching: whole-program analysis, per-module codegen units keyed by their text (accepted 2026-10-06)

**Every build runs the new core's own pipeline over the whole program:** Core IR,
facts, inlining, ownership and emission. Emission then splits the program into
**codegen units, one per source module**. Generic instances and the entry wrapper get
units of their own.

**Each unit is cached by the hash of its emitted LLVM text,** plus the target,
optimization level, Zig version and runtime ABI version. Only changed units go to
LLVM, in parallel, and the link takes every unit's object. The design, including the
runtime ABI change for trap sites, is `docs/design/new-core-s4.md`.

**Why this and not the two plain schemes:**

| | Per function | Per module (separate compilation) | **Hybrid (S4-1)** |
|---|---|---|---|
| Optimization across modules | full | only through interfaces; a public function loses caller-derived ranges; inlining needs bodies in the `.myi` | **full** |
| Multi-module program vs the same code in one file | same speed | can be slower | **same speed** |
| Cache-key correctness | every cross-function input must be in the key; a missed one is a silent miscompile | small key (module source + imported interfaces) | **the key is the emitted code itself; no dependency tracking** |
| Work every build | whole pipeline; changed functions to LLVM | unchanged modules skipped entirely | whole pipeline; changed units to LLVM |
| LLVM invocations | many tiny units unless grouped | one per module | one per changed module |
| Generic instances | natural | needs an owning module or deduplication | identical text, identical key |

**What separate compilation would cost:** `bytes_scan`'s vector loop exists only
because `NEW-CORE-FACTS-10` sees every call to `score`. Were `score` public in another
module, the overflow check would stay and the loop would stay scalar.

**Fallbacks, if S4's measurements miss the §6 targets:**
- **The whole-program pipeline is too slow at scale.** Cache Core IR per module as
  well, keyed by the module's checked source and the interfaces it imports, with the
  whole-program passes reading cached IR.
- **The edit loop is still too slow.** Debug builds use plain per-module separate
  compilation, and release builds keep S4-1.

### S4-1a. Release builds are one unit (the user, 2026-10-07)

**Debug builds keep S4-1:** one codegen unit per module, cached by its text. That covers
`mylang test` and `build` without `--release`, which is the edit loop.

**A release build emits the whole program as one unit,** as S3 did. That unit is still
cached by the hash of its text, so an unchanged program starts no `zig cc`. Any edit
recompiles the whole program at `-O3`.

**Why:** a split release build loses LLVM's inlining across units.
- In S4-E's measurements, applications split one module per file ran up to 1.39× their
  single-unit build (`Result` at 4096), and Lox missed as well.
- Five inlining and code-layout variants did not close the gap.
- Release code is what the 1.10× gates measure; the edit loop's speed is debug's.
- ThinLTO, which keeps per-unit caching with cross-unit inlining, is a possible spike
  after S4.

**What changes:**
- **S4-E** has no split-application timing gate. Code that exists only to speed up split
  release builds goes in the same change, for example the cross-unit private entry copies
  and their block limits. Anything that also helps the single-unit build stays only if the
  46 rows show it.
- **§6:** the two release-rebuild targets become reported numbers.
- **S4-P** compares debug builds on both sides, as the Wave 0 baselines did. Those used
  `mylang build` and `mylang test` without `--release`.

### S4-2. Front-end caching (accepted 2026-10-06)

Wire the old core's `semantic_cache` into `frontend.Session` (`checkWithCache`), so an
edit rechecks only the changed functions, as the old core's builds do.
- **Reuse it, don't reimplement it.** The formats stay `module-interface-v5`,
  `check-summaries-v6` and `mutation-v2` unless S4 changes one, which then bumps its
  version.
- **This is enough.** With `CATALOG-INTERN-1` the merged check costs 0.45 s after an
  edit at 96k lines (§3.4), so the new core does not need per-module checking.

### S4-3. The S4 exit programs (accepted 2026-10-06)

Codex runs both now, in parallel with S3, as Wave 0. Neither touches the compiler.
- **S4-L migrates the Lox port** to value semantics.
- **S4-D ports EDA Stage 1** (26,430 Zig lines), following `eda-bench/mylang/PLAN.md`.
  It becomes S4's EDA slice; the 5,169-line pilot is its first layer.

**Neither needs design work:**
- **The Lox port's objects already live in a handle-indexed heap.** Its 16 classes are
  compiler and VM state (parsers, the runtime, chunks, frames, scopes). The care goes
  into the roughly 50 places the value-semantics audit (P1, 2026-09-24) found relying
  on shared references.
- **The EDA port has a lane plan, a 1,400-line guide and a gap list with no blocker.**

**Both stop and report** if the current language cannot express something, rather
than changing the compiler.

## 3. The spike: results (2026-10-06)

Run on `claude/new-core-s4-design` from S3's Wave B base (`8918de74`), touching no S3
file. Evidence, scripts and logs: `experiments/new-core-s4-20261006/`.

**The programs.** `gen_program.py` writes synthetic multi-file projects: files of 100
"modules" (a record type and six functions each, ~40 lines) using loops, lists, a
str-keyed dict, records, text concatenation and split. Every module calls the next
module's small public helper, crossing files at file boundaries, so inlining and
caller-derived ranges cross files. Sizes: 4,821 lines (3 files), 48,101 (13) and
192,389 (49). A ReleaseFast `mylang-core` built from `8918de74`; timings on CPU 10
unless noted.

### 3.1 Where a build's time goes (`phases.py`, `phases.json`)

| Lines | Check | New core's own work (IR, passes, emission) debug / release | LLVM `-O0` | LLVM `-O3` | Link |
|---:|---:|---:|---:|---:|---:|
| 4,821 | 0.03 s | < 0.1 / < 0.1 s | 0.36 s | 3.95 s | 0.02 s |
| 48,101 | 0.70 s | 0.28 / 0.34 s | 3.23 s | 44.4 s | 0.03 s |
| 192,389 | 12.19 s | 1.35 / 2.49 s | 14.2 s | 195 s | 0.05 s |

The new core's own work is from an `strace` of when it starts `zig cc`, minus the
check. **LLVM is over 90% of every build; the whole-program pipeline S4-1 reruns on
each build costs 0.3 s at 50k lines and 1.4–2.5 s at 200k.** The check was the
other large cost, and it grew quadratically (§3.4).

### 3.2 Codegen units (`split_ll.py`, `units.py compile`, `units-compile.json`)

`split_ll.py` simulates S4-1's emission in text: one unit per source file, cross-file
callees made `hidden`, shared helpers copied, metadata closed per unit. Each unit
compiled alone (fresh zig cache), linked with the runtime, run: **output identical to
the whole-program build in all four cases.**

| Lines | Level | Units | One `.ll` | Sum of units | Largest unit | 8 workers | 16 workers |
|---:|---|---:|---:|---:|---:|---:|---:|
| 48,101 | `-O0` | 13 | 3.33 s | 3.42 s | 0.27 s | 0.55 s | 0.27 s |
| 48,101 | `-O3` | 13 | 50.3 s | 46.1 s | 4.0 s | 7.6 s | 4.0 s |
| 192,389 | `-O0` | 49 | 17.1 s | 17.8 s | 0.72 s | 2.5 s | 1.4 s |
| 192,389 | `-O3` | 49 | 218 s | 225 s | 7.3 s | 28.4 s | 15.0 s |

Worker columns are the longest-processing-time schedule of the measured unit times.
Linking 49 objects takes 0.04–0.07 s. **Splitting costs nothing, and it parallelizes
the cold build:** a 200k-line release build drops from 218 s to about 15 s on 16
workers (the old core took 746 s cold for 53k lines).

### 3.3 Edit ripple (`units.py ripple`, `units-ripple.json`)

48,101 lines, 13 units; edits in module 650 (file `p6`) and 600 (first of `p6`).

| Edit | Units changed, today's emitter | Units changed, unit-local numbering |
|---|---:|---:|
| A constant in a function body | 1 | 1 |
| An added statement (a new checked operation) | **13 of 13** | 1 |
| A small public helper another file's caller inlines, release | 2 | 2 (its unit and the caller's) |
| The same helper, debug (no inlining) | 2 | 1 |

**Today's emitter numbers things across the whole program, so one added checked
operation changes every unit:**
- private constants;
- trap sites, indexed in one program-wide table;
- metadata.

`docs/design/new-core-s4.md` §3 lists all seven numberings. With unit-local numbering
and per-unit site records (simulated by `--normalize`), an edit changes exactly its own
unit plus the units that inlined from it.

### 3.4 The front end (`gen_program.py`, `perf`)

- **The merged-program check was quadratic.** 60–77% of its time was
  `record_layouts.validate` and its helpers: `nominal_catalog.Builder.complete` ran
  full layout validation over every record each time the checker materialized a type,
  including types the catalog already held (every `list[T]` use goes through
  `collection_lower.listType`). Next was `identify` re-inserting every identity into
  the `by_type` index on each call.
- **Fixed on this branch** (`CATALOG-INTERN-1`, `src/nominal_catalog.zig`): `complete`
  returns early when no record was added, and `identify` indexes only the identities
  it resolves (highest node wins, as before). Same CPU (12), before → after:
  48k lines 1.50 → 0.36 s; 96k 5.58 → 0.79 s; 192k 25.3 → 1.78 s. Now close to linear.
  A follow-up (`e86ac0bc`) returns an already-held type before any graph pass when
  no graph node was added. Focused tests (nominal 97, generic 177, record 187, callback
  86, array 77, tuple 31) and `test-core` 219/219 pass, and **the full old gate is
  green** on `e86ac0bc`: `zig build test` 115/115 steps with 3,003 tests,
  `test-qbe` 519/519, `test-qbe-build` 29/29, `fmt-check` 2/2 (`gate/`).
- **The old core's checks on the 96k-line project** (24 files), CPU 12, before the fix:
  per-module `mylang check` cold 1.65 s, unchanged 0.03 s, after one edit 0.10 s;
  merged `mylang check-project` (the path the new core uses) cold 5.01 s, unchanged
  0.03 s (verdict replay), after one edit 3.30 s, of which 77% was the quadratic.
- **With the fix** (old compiler rebuilt from this branch, same project and CPU):
  merged `check-project` cold 5.01 → **1.09 s**, after one edit 3.30 → **0.45 s**;
  per-module `check` unchanged (1.58 s cold, 0.10 s after an edit). The merged path
  the new core uses now costs 0.45 s after an edit at 96k lines, so wiring the
  semantic cache into `frontend.Session` (S4-2) is enough; the new core does not need
  per-module checking.

### 3.5 The S4 exit programs after Wave 0 (2026-10-06)

Both were ported under the pinned old compiler (`a16a324e`) by Codex in Wave 0, with
no language blocker.

**The ports:**
- **Lox:** `codex/s4-lox-value-semantics` at `f44302d8`. The 16 classes became
  records over the existing object-handle heap. Conformance passes 974/974 (both
  engines, normal and gc-stress), and all 65 tests pass (the 63 originals plus 2
  regressions). Evidence: `experiments/new-core-s4-lox-20261006/REPORT.md` on that
  branch.
- **EDA Stage 1:** `eda-bench` branch `codex/s4-eda-stage1` at `510c2e2`. The port is
  121 files and 17,965 non-blank lines, and covers layers L1–L13. 310 tests pass,
  279/279 Zig counterparts are present, and **34/34 golden outputs are
  byte-identical**. Evidence: `experiments/new-core-s4-eda-20261006/README.md` on
  that branch.

**Old-core baselines** (pinned compiler, CPU 10, empty caches, one test worker; these
are the S4 exit targets):

| Program | Build cold | Build unchanged | Build after a one-function edit | Tests cold | Tests unchanged | Tests after the edit |
|---|---:|---:|---:|---:|---:|---:|
| Lox port | 7.66 s | 0.007 s | 0.195 s | 22.0 s | 0.145 s | 0.648 s |
| EDA Stage 1 | 81.1 s | 0.017 s | 1.15 s | 234.5 s | 1.65 s | 1.67 s |

The old core's cold EDA build peaks at about 6.0 GiB (6.4 GiB for cold tests),
against its 8 GiB self-imposed ceiling, at 18k lines.

**New-core coverage today** (S3 integration build `2f041d14`, before S4):
- **EDA Stage 1:** 1,873 of 1,874 functions accepted. The refusal is `assert` with
  a message value.
- **Lox:** 304 of 487 functions accepted. All 183 refusals have one reason, `record
  field type`: `build.zig`'s `stored()` refuses a capability token (`Type.cap`) as a
  record field, and the port's `Output` record holds `out: Stream` and
  `err: Stream`. No `tests/lang` test stores a capability in a record, so S3 did not
  need it.

**S3's coverage sweep checked neither port.** The four corpora are `examples`,
`bench/parity`, `tests/lang` and the runtime benchmarks. S4-0 adds both ports.

### 3.6 Six new benchmark rows (2026-10-06)

Six rows cover mechanisms the 40 existing rows don't.
- **Where:** branch `claude/new-core-s4-rows` (from S3 integration `02f796a8`),
  `experiments/new-core-s4-rows-20261006/`. That holds `CONTRACT.md` and, per case,
  `row.my` plus Rust, Zig and Go references and a Python oracle.
- **Verified:** all five arms (old core, new core, Rust, Zig ReleaseSafe, Go) match the
  oracle at every probe. There were no refusals and no wrong answers.
- **Measured:** `rows.py measure`, CPU 10, 7 interleaved rounds. The rest of the
  machine was loaded (load average about 33) while CPU 10 was idle. Each cell is new
  core ÷ the reference, at sizes 4096 / 64:

| Row | ÷ Zig ReleaseSafe | ÷ Rust | ÷ old core | Gate |
|---|---:|---:|---:|---|
| `tree_build_walk` | 0.69 / 0.68 | 0.73 / 0.75 | 0.23 / 0.23 | pass |
| `record_pass` | 0.68 / 0.71 | 1.05 / 1.09 | 0.51 / 0.53 | pass |
| `grid_dp` | **3.46 / 3.46** | 4.06 / 3.70 | **2.43** / 0.79 | **miss** |
| `union_find` | **2.06 / 2.25** | 2.06 / 2.50 | 1.05 / 0.89 | **miss (Zig)** |
| `float_format` | 0.73 / 0.75 | 0.75 / 0.79 | 0.57 / 0.57 | pass |
| `buffer_write` | 0.89 / 0.87 | 1.02 / 0.97 | 1.04 / 1.02 | pass |

**Findings, all for S4-V:**
1. **`grid_dp`: a nested write copies the inner row every time.** For `dp[i][j] = v`,
   the new core emits `myl_core_list_copy` of the row before every write, with no
   uniqueness branch, then stores the row back and releases the old one. A direct
   `xs[i] = v` does check uniqueness.
   - The cost is linear in row width: 42 cycles per write at width 16, 58 at 64 and 550
     at 512, against 4–8 in the old core.
   - Repro: `grid_dp/repro-nested-write-copy.my`.
2. **`union_find`: about 2× Zig.**
   - `find` (a loop) is not inlined, and it returns `{i64, ptr}` (the possibly-copied
     `mut` list) on every call.
   - Multi-block inlining, or a cheaper `mut`-list return when the callee cannot
     reallocate the list, is the lever.
3. **`buffer_write`: `byte_buffer.append_int` and `append_float` allocate a temporary
   `str` per value** (`build_bytes.zig:138–139`, `myl_core_str_from_i64`), then push
   digit by digit with a copy-on-write check per byte. The old core formats into a
   20-byte stack array. The row passes only because the per-byte checksum fold
   dominates it.
4. **Language, both cores:** `[0] * w` with a non-literal count is rejected with
   `E_LIST_TYPE`, while `[0] * 3` checks fine. Repro: `grid_dp/repro-list-repeat.my`.
5. **Friction:**
   - `byte_buffer()` takes no zero-argument form; write `byte_buffer([])`.
   - Discarding `append_*`'s result needs `_ =`.

## 4. Work packages

Each package runs in its own locked worktree from the S4 integration branch, commits
with Guardian's 88 checks, and records evidence under `experiments/new-core-s4-*/`,
one log file per command run.

### Wave 0 (done 2026-10-06; results in §3.5, kept here as the record)

**The pinned compiler for both packages.**
- Build it once from `claude/new-core-s4-design` at `a16a324e`:
  `zig build -Doptimize=ReleaseFast --prefix <cache>/mylang-s4-pin`, through
  `scripts/build-slot.sh build`.
- That commit is S3's Wave B base, so it has D2, `MUT-OVERLAP-RECEIVER-1` and
  `MUT-REBIND-CALLER-1`, plus `CATALOG-INTERN-1`. Its language is what the new core
  compiles.
- Record the compiler's hash in each package's evidence.

**Machine:**
- S3's Wave B holds up to four build-heavy agents, and guest builds and tests compete
  for the same cores.
- Run S4-L as one agent, and S4-D's lanes A and B, with `mylang test --jobs 4`.
- Start lanes C and D when S3 exits or when A and B finish, whichever is first.
- Never time on CPUs 2, 3 or 11; baselines are timed on CPU 10.

#### S4-L. Migrate the Lox port to value semantics (one agent; about 3–5 h)

**Where:**
- branch `codex/s4-lox-value-semantics`, created from the benchmark tree's commit
  `4e48a0922` (worktree `.tmp/lox-bench/tree`, path `benchmarks/lox/ports/mylang`);
- in a new worktree. Never edit the existing `.tmp/lox-bench` checkouts.

**What:**
- Replace the 16 `class` types with records and recursive unions, threading `mut`
  parameters. Use the port's existing heap handles, or new pool handles, where two
  places must see one mutable object.
- Keep the port's structure, its tests (`*_test.my`, `driver_tests.my`,
  `driver_cases.json`) and `bench.json`'s build commands.
- Fix anything D2 or the `mut` rules now reject the same way.

**Exit:**
- conformance through the benchmark harness (`harness/lox_bench.py`, both engines,
  normal and gc-stress) at the oracle's output, and all 63 unit tests passing;
- old-core baselines recorded, pinned to CPU 10: build cold, unchanged and after a
  one-function edit on `main`'s path; tests with `--jobs 1` cold, unchanged and after
  that edit;
- `NOTES.md` updated, and no compiler file touched.

#### S4-D. Port EDA Stage 1 (lanes A–D; `eda-bench/mylang/PLAN.md`)

**Where:**
- `eda-bench` repository, a branch `codex/s4-eda-stage1` and lane branches as
  `PLAN.md` describes;
- each lane in its own worktree.

**First:**
- re-pin `harness/langs.toml`'s mylang compiler to the S4 pin above;
- rerun the pilot (support modules and `main`);
- update `PORTING-MYLANG.md` and `GAPS.md` for any rule that changed since its pin
  `c523da46` (D2, `MUT-OVERLAP-RECEIVER-1`, `MUT-REBIND-CALLER-1`, and so on).

**What:** port layers L1–L13 by the lane plan.
- Record new gaps in `GAPS.md` with their classification: blocker, workaround or
  friction.
- Stop and report a blocker; don't change the compiler.

**Exit:**
- `bench.py equiv mylang` passes all 34 golden cases;
- the Zig tests' counterparts pass (`tools/check_tests.py`);
- old-core baselines recorded as for S4-L.

### Wave A (after the S3 exit and the user's S4 go)

#### S4-0. Base (coordinator)

- Create `codex/new-core-s4-integration` from `codex/new-core-s3-integration` at
  `82c125dd` (source `d4994214`). Merge `claude/new-core-s4-design`, then
  `claude/new-core-s4-rows` (S4-R).
  - Both merges are clean: a `git merge-tree` trial of both, in that order, on
    2026-10-06 gave no conflict.
  - The design branch brings `CATALOG-INTERN-1` (full old gate green on `e86ac0bc`),
    this plan, the design note and the spike tools.
  - **`CATALOG-INTERN-1` touches shared front-end files, so the merged base runs the
    full old gate once.**
- Rerun `test-core`, full conformance and, after S4-R, the 46 rows. This is the S4
  baseline every package compares against.
- **Add both ports to the coverage sweep**, which then has six corpora:
  - the Lox port: branch `codex/s4-lox-value-semantics` at `f44302d8`;
  - the EDA slice: `eda-bench` branch `codex/s4-eda-stage1` at `510c2e2`.
  - Record their acceptance on the S4 base. Before S3's exit it was Lox 304/487 and
    EDA 1,873/1,874 (§3.5).

**Facts from the S3 exit, for the packages that own these files:**
- **`tests/lang` left for S4:** one file, `tests/lang/migrated/propagation.my` (9
  tests, user-module imports). The retired arena tests are 118 in five files
  (`arena_class_escape`, `arena_managed`, `arena_regions`, `arena_scopes`,
  `rc_arena_values`). The source is S3's `exceptions-final-run02.json`.
- **`frontend.zig`** is unchanged since the design branch's base (`8918de74`).
- **`driver.zig`** changed in 7 lines, which matter to S4-E and S4-C:
  - the runtime source now also concatenates `core_host.c`, `core_values.c`,
    `core_test.c` and the Unicode data;
  - the driver links a separately cached float-text object (`number_runtime`) when
    `number_runtime.needed(llvm)` says so, and adds `-lm` when the text contains
    `llvm.sin.f64` or `llvm.cos.f64`.
  - **Both decisions scan the one `.ll` text**, so with units they must cover every
    unit, including units served from the cache.
- **The emitter gained program-wide names** that the design's numbering table
  (`new-core-s4.md` §3) now lists:
  - `@myl.value.N` (recursive equality and hashing descriptors, by Core IR type id);
  - `@myl.render.ID` (render descriptors);
  - `@myl.zeros`, sized to the program's largest zeroed constant.
  - `@myl_core_source_path` was already there. It is the one source path that trap
    and trace text prints, and it moves into the site records (design §4).
- **`test_runner*.zig`** gained the property runner (`test_runner_property.zig`) and
  batched test programs (`test_runner_batch.zig`). S4-M builds on both.

#### S4-R. The six new rows join the gate (coordinator, in S4-0)

- Move each `row.my` to `test/core/row_<case>.my`.
- Add the four-language references to the measured registry, so S3's `measure_all40`
  becomes `measure_all46`. Their Rust and Zig binaries are built by the measurement
  tool, because the frozen runtime baseline lacks them.
- Keep `CONTRACT.md` and the oracles.

From then on, every one of the 46 rows must be within 1.10× Zig ReleaseSafe and 1.10×
the old core.

#### S4-V. Value-path performance (one agent; about 4–5 h; parallel with S4-F)

**Fix §3.6's findings 1–4:**
1. **Nested writes:**
   - `a[i][j] = v`, and any deeper nested place write, checks the inner collection's
     uniqueness and writes in place when it is unique, as direct writes do.
   - The copy happens only on the shared path.
   - Every uniqueness claim gets a verify assert.
2. **`union_find`:** reach 1.10× Zig, by inlining small loop functions (the S3-M
   multi-block-inlining stretch) or by a `mut`-list return path that avoids the
   aggregate return when the callee cannot replace the list. Measure both and keep what
   meets the gate.
3. **`byte_buffer.append_int` and `append_float`:** format into a stack buffer and
   append in one reserve-and-copy, with no temporary `str` and no per-byte check.
4. **`[0] * w` with a non-literal `int` count** type-checks (shared checker, spec
   tagged) and lowers in both cores.

**Owns:**
- `src/core/own.zig`, `build*.zig` and `emit*.zig` for these paths;
- `runtime/core_bytes.c`;
- the checker file for list repetition, which is shared, so the full old gate runs.

**Exit:**
- `grid_dp`, `union_find` and `buffer_write` within both gates;
- no other row regresses;
- conformance at 0 mismatches;
- leak and verify sweeps clean.

#### S4-F. Front-end caching (one agent; about 3–4 h)

**What:**
- S4-2: the semantic cache in `frontend.Session` for both `build` and `test`.
- Any remaining superlinear front-end cost found by profiling the synthetic projects
  (`gen_program.py`).

**Owns:** `src/core/frontend.zig` and the shared front-end files it must touch. Shared
files mean the full old gate.

**Exit:**
- on the synthetic projects, the check after a one-function edit is at or below the
  old core's `check-project` at every size (0.45 s at 96k lines);
- cold check close to linear in size;
- the full old gate green.

#### S4-E. Codegen units (one agent; about 5–6 h)

**What:** `docs/design/new-core-s4.md` §2–§5 and §7:
- units per module, per generic instance and for the entry;
- unit-local names and metadata;
- `fastcc` program functions with `hidden` cross-unit linkage;
- per-unit site records, and the runtime taking site pointers in `myl_core_trap`,
  `myl_core_assert_fail`, `myl_core_err_trace` and the trace ring;
- per-unit debug information;
- deterministic output;
- the stability tests;
- the runtime link decisions (`number_runtime`, `-lm`) taken over every unit, not one
  `.ll` text (S4-0's facts).

**Owns:** `src/core/emit_*.zig` (a new `emit_units.zig`), `src/core/runtime/core_rt.c`
(sites and traces only), and `driver.zig`'s link decisions until S4-C takes the driver.

**Exit:**
- every §7 stability test passes;
- conformance at 0 mismatches, debug and release, with the leak and verify sweeps;
- trap and trace output identical;
- the 46 rows unchanged within noise as single-module programs;
- a release build emits exactly one unit (S4-1a);
- debug builds of the five applications, split one module per file, give output
  identical to their single-unit build. There is no timing gate on split builds.

#### S4-M. Module projects and project tests (one agent; about 3–4 h; parallel with S4-E)

**What:**
- **Projects:** module projects through the new core (`mylang.json`, import policy,
  interface files where the front end uses them).
- **Tests:** `mylang-core test` over a project directory, with the old runner's
  per-test reuse (a test reruns only when its program changed) and parallel workers.
- **Exclusions:** the `tests/lang` files S3 left for S4.

**Owns:** `src/core/test_runner*.zig` and `src/core/pipeline.zig`'s project entry.

**Exit:**
- every `tests/lang` file at 0 mismatches except the retired arena tests;
- `mylang-core test` on the Lox port (after S4-L) and the EDA slice runs every test;
- an unchanged rerun executes nothing.

### Wave B

#### S4-C. Unit cache and parallel driver (one agent; about 3–4 h; after S4-E merges)

**What:** `docs/design/new-core-s4.md` §6:
- the key and store;
- hits without a process;
- batched and parallel misses;
- the link;
- `--verify-cache`;
- eviction in `scripts/prune-caches.sh`.

**Owns:** `src/core/driver.zig` and a new `src/core/unit_cache.zig`.

**Exit:** the §6 dev-loop targets on the synthetic projects, and the cache tests of
design §7.

#### S4-P. Projects under the new core (one agent; after S4-C and S4-M)

**Known items from Wave 0 (§3.5):**
- capability tokens (`Stream`, `Host`, `Type.cap`) as record fields and payloads. A
  token is an `i64`; ownership and authority rules are unchanged. This blocks 183
  Lox functions.
- `assert` with a message value (1 EDA function).

**What:**
- build and test the Lox port and the EDA slice under the new core;
- measure against the old-core baselines from S4-L and S4-D, with the same commands
  and CPUs;
- fix what they expose.

**Exit:**
- both pass their tests under the new core;
- build and test times at or below the old core's: cold, unchanged, and after a
  one-function edit.

### S4-X. Integration and exit (coordinator)

The full bar once:
- the full old gate;
- strict 200 fuzz cases of every kind;
- full leak and verify sweeps;
- all 46 rows against both 1.10 gates;
- coverage including both ports;
- `--verify-cache` over the Lox port and the EDA slice;
- the dev-loop table (§6).

## 5. Order

| Wave | Packages | Notes | Expected wall time |
|---|---|---|---|
| 0 | S4-L, S4-D | done 2026-10-06 | — |
| A | S4-0 (with S4-R), then S4-F, S4-V, S4-E, S4-M in parallel | at the user's go; at most four build-heavy agents | S4-0 about 2 h, then about 7–9 h, set by S4-E and four merge qualifications |
| B | S4-C after S4-E; S4-P after S4-C and S4-M | | S4-C 3–4 h, then S4-P 4–8 h (the widest range: what the two ports expose) |
| X | S4-X | after all packages | about 4–5 h |

**Total: about 20–28 hours of continuous work.** For calibration, S3 took about 17 hours
from S3-0 to the last package merge, plus about 3 for S3-X. Two outcomes would add a
package:
- the dev-loop targets miss, and a §2 fallback is needed;
- S4-P finds new-core defects at the ports' scale.

## 6. Gates

S3's gates apply unchanged:
- `test-core` (8 shards by default, under 5 min; S3's qualification runs passed
  `-Dcore-shards=64` and took 146 s);
- conformance at 0 mismatches;
- 50 strict fuzz cases of each package's kinds;
- every row within 1.10× Zig ReleaseSafe and within 1.10× the old core;
- a `mylang-core` rebuild of at most 10 s, measured uncontended;
- the full old gate for any package that touches files outside `src/core/`.

**New in S4, the dev-loop targets.** Measured on the synthetic projects
(`gen_program.py`) and on both exit programs. Timings use CPU 10 for single-process
steps and the build CPUs for parallel compilation, reported separately.

| Measure | Target |
|---|---|
| Debug rebuild after a one-function edit, 48k lines | ≤ 2 s |
| Unchanged rebuild, any size, debug or release | no `zig cc` process |
| Check after a one-function edit, 96k lines | ≤ 0.45 s |
| Release rebuild after a one-function edit, 48k lines | reported; whole-program `-O3` under S4-1a |
| Cold release build, 192k lines | reported; one unit under S4-1a |

## 7. Rules

S3's §6 rules still apply:
- a wrong answer is never acceptable;
- machine rules;
- one log per command run;
- persisted formats bump their version when they change;
- no pushes and nothing merged into `main`.

**How much qualification (the user, 2026-10-07).** In Wave A's first 13 hours nothing
was merged. One fuzz kind took 51 minutes, of which 4 were compiling and running.
From now on:
- **Qualify with S3's tools unchanged:**
  - `qualify_merge.py`;
  - `full_old_gate.py`;
  - `fuzz_matrix.py`: 50 cases per kind per package, 200 at S4-X;
  - the all-rows timing tool, extended to 46 rows, 7 rounds.
- **Don't build more qualification machinery.** That means:
  - no new fuzz adapters;
  - no capture envelopes;
  - no prospective timing protocol;
  - no independent replays of passing results;
  - no reviews of helper scripts.
- **A 9-kind × 50-case matrix should take 15–20 minutes** at 3 jobs. Much longer means
  stop and report.
- **Commit summary JSON and command logs only,** at most 10 MB per package.
  - Raw outputs, binaries, LLVM text and archives stay untracked under `.mylang-cache`
    and may be deleted.
  - A failed run gets a short note in the state file, not an archive.
  - A harness defect is fixed and the run repeated; the failed run is not kept.
- **Native cache keys follow `docs/design/new-core-s4.md` §6.** Foreign C sources add
  their compiler depfile (`-MD`). Don't inventory host toolchain files.
- **"A wrong answer is never acceptable" is about the compiler's output.** It does not
  mean every qualification tool needs its own proof.

**New in S4:**
- **`ir.zig` stays frozen.** S4 needs no IR change. A package that thinks it needs one
  stops and reports.
- **The runtime ABI change is S4-E's only.** Site pointers replace site indexes, and
  nothing else in the runtime ABI moves.
- **The unit cache is never trusted over correctness.** Any doubt about a key's
  completeness is a bug to fix, not a test to skip. `--verify-cache` runs in
  `test-core`.
- **External checkouts:** S4-L and S4-D work on their own branches. Nothing edits
  `.tmp/lox-bench` or `eda-bench` in place.
- **Old-core changes:** S4-F's shared front-end changes are allowed, with the full old
  gate. Any other old-core change stops and reports.

**Learned in S3-X:**
- **Never run the full old gate while a fuzz matrix runs.**
  - The matrix's workers run at `nice 10`. With the gate beside them, the old compiler
    oracle hit its 60 s build timeout in four kinds, with no mismatch.
  - Run them one after the other. A timeout-only stop is rerun with
    `wave-x/integration/fuzz_matrix_rerun.py`, never by editing evidence.
- **Commit large evidence in batches** of one directory each. Guardian's commit hook
  fails with `GitSpawnFailed` on a commit of about 2,400 files.
- **A fuzz mismatch is reduced to a regression fixture before it is fixed**, as
  `NEW-CORE-RC-13` was (`wave-x/rebinding-repair/`).
- **Only `ir.zig` is frozen.** The ownership pass (`own.zig`) and the rest of
  `src/core/` change under the gates.

## 8. S4 exit check and report

**Exit:**
- the Lox port and the EDA slice pass their tests under the new core;
- build and test times at or below the old core's (§6);
- every §6 dev-loop target met;
- every `tests/lang` file at 0 mismatches except the retired arena tests;
- the S4-X bar green.

**The report:**
- package commits;
- the dev-loop table against the old core;
- the 46 rows;
- conformance and coverage, both ports included;
- fuzz, leak and verify;
- every remaining limit.

It then stops for the user's go/stop on S5: making the new core the default and
deleting the old core.
