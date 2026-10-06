# New compiler core, stage S4: projects — plan, 2026-10-06

Status: **draft.** Decisions recorded as the user makes them. S4 implementation starts
after the S3 exit report and the user's S4 go. Design work and measurements run now, in
parallel with S3, on `claude/new-core-s4-design`, and touch nothing S3's packages own.

The stage, from the new-core plan (`docs/audits/new-core-plan-2026-10-05.md` §6):

| Scope | Exit check |
|---|---|
| Modules and `.myi` interfaces, incremental per-module builds, `mylang test` on projects, the Lox port, an EDA slice. | The Lox port and the EDA slice pass their tests under the new core, with build and test times at or below the old core's. |

## 1. Where the new core starts

- **Front end.** `src/core/frontend.zig` loads a module graph through
  `project_compile.Compilation` and checks the merged program with `check()`, which is
  `checkWithCache(null)`. **The new core uses none of the old core's per-function
  check caches today**: every build rechecks every module. The old core's `mylang build`
  passes a `semantic_cache.Cache` (function bodies, symbolic generics, specializations,
  module interfaces `module-interface-v5`, `check-summaries-v6`, `mutation-v2`).
- **Back end.** `src/core/pipeline.zig` builds one Core IR module for the whole program,
  runs the release passes over it, emits one `.ll` and compiles it with one `zig cc`
  call. Only the runtime object is cached (by content). Nothing of the program is
  reused between builds.
- **Whole-program optimizations the back end relies on:** the leaf inliner
  (`inline.zig`), caller-derived parameter intervals (`NEW-CORE-FACTS-10`, which
  needs every call site), the ownership pass's callee summaries, and the merged
  standard library (S3-A).
- **Old-core reference numbers** (scale probe, 53k-line project, 2026-09-17): per-edit
  check 3–4 s, cold build 746 s, warm build 70 s. S4's exit compares against the old
  core's numbers on the Lox port and the EDA slice, remeasured at S4 start.

## 2. Decisions

### S4-1. Caching: whole-program analysis, per-module codegen units keyed by their text (accepted 2026-10-06)

**The rule.** Every build runs the new core's own pipeline over the whole program
(Core IR, facts, inlining, ownership, emission). Emission then splits the program into
**codegen units, one per source module** (generic instances and the entry wrapper in
units of their own, below). Each unit is cached by the hash of **its emitted LLVM text**
plus the target, optimization level, LLVM/Zig version and runtime ABI version. A unit
whose text hash is cached reuses its object; only changed units go to LLVM. The link
step takes every unit's object plus the runtime object.

**Why this and not the two plain schemes** (the comparison, 2026-10-06):

| | Per function | Per module (separate compilation) | **Hybrid (S4-1)** |
|---|---|---|---|
| Optimization across modules | full | only through interfaces; a public function loses caller-derived ranges; inlining needs bodies in the `.myi` | **full** |
| Multi-module program vs the same code in one file | same speed | can be slower | **same speed** |
| Cache-key correctness | every cross-function input must be in the key; a missed one is a silent miscompile | small key (module source + imported interfaces) | **the key is the emitted code itself; no dependency tracking** |
| Work every build | whole pipeline; changed functions to LLVM | unchanged modules skipped entirely | whole pipeline; changed units to LLVM |
| LLVM invocations | many tiny units unless grouped | one per module | one per changed module |
| Generic instances | natural | needs an owning module or deduplication | identical text, identical key |

The concrete cost of separate compilation: `bytes_scan`'s vector loop exists only
because `NEW-CORE-FACTS-10` sees every call to `score`. Were `score` public in another
module, the overflow check would stay and the loop would stay scalar. The hybrid keeps
that, and an edit still recompiles only its own unit plus any unit that inlined the
edited function or took ranges from its calls.

**Requirements this puts on emission** (S4 must meet all of them; the spike in §3
measures where today's emitter falls short):
1. **Stable, content-derived names.** A unit's text must not depend on anything outside
   the unit except the declarations it uses. Global counters (string-literal numbering,
   type-descriptor ids, metadata numbering, trap-site tables, label counters that span
   functions) must become unit-local or content-hashed, or one added literal in one
   module changes every later unit's text and nothing is reused.
2. **Cross-unit linkage.** Functions called across units become `hidden` external
   definitions with deterministic mangled names; everything else stays `internal`.
   Shared constants (literal blocks, descriptors) are either emitted per unit as
   `linkonce_odr`/COMDAT or owned by one unit and declared elsewhere.
3. **Generic instances** go into units keyed by their own text (one per instance or
   grouped by the generic's defining module), so two modules using `sort[Record]`
   share one object.
4. **Debug information and trap locations** carry file/line per unit without a global
   numbering pass.
5. **Determinism:** the same program emits byte-identical units on every build and on
   every machine with the same toolchain.

**Correctness guard.** A clean build and an incremental build must produce the same
objects. S4 adds a check (in the test suite and as a hidden `--verify-cache` mode)
that rebuilds every reused unit from scratch and compares object hashes.

**Fallbacks, if the spike or S4 measurements say so:**
- **The whole-program pipeline is too slow at EDA scale.** Cache the front half per
  module as well: Core IR per module, keyed by the module's checked source and the
  interfaces it imports (that half is the per-module scheme), with the whole-program
  passes reading cached IR.
- **Still too slow in the edit loop.** Debug builds (where cross-module optimization
  matters least) use plain per-module separate compilation; release builds keep S4-1.

### S4-2. Front-end caching (proposed, for the user)

Wire the old core's `semantic_cache` into `frontend.Session` (`checkWithCache`), so an
edit rechecks only changed functions, as `mylang build` does. Reuse, not reimplement:
the cache formats stay `module-interface-v5`, `check-summaries-v6` and `mutation-v2`
unless S4 changes them (then bump).

## 3. The parallel spike: results (2026-10-06)

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

**Today's emitter numbers three things globally, so one added checked operation
changes every unit** (requirement 1 of S4-1):
- private constants `@myl.op.N`, `@myl.fn.N`, `@myl.str.N`, `@myl.dict.N`;
- trap sites: `myl_core_trap(i32 N, …)` indexes one program-wide `@myl_core_sites`
  table;
- debug metadata ids `!N`.

With unit-local numbering and a site table per unit (simulated by `--normalize`), an
edit changes exactly its own unit plus the units that inlined from it.

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
  Focused tests: nominal 96, generic 176, record 187, callback 86, array 77, tuple 31,
  all passing; `test-core` 219/219. The full old gate is still owed before it merges.
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

## 4. What the spike means for S4 (draft)

**S4-1 holds.** The whole-program pipeline is cheap enough to rerun every build, LLVM
is where the time goes, and per-file units both cache and parallelize it. The build:
1. **Check** the merged program with the semantic cache (S4-2) and `CATALOG-INTERN-1`.
2. **Build, analyze and emit** the whole program (0.3 s at 50k lines).
3. **Emit one unit per source file.** Generic instances go into units keyed by their
   own text, so files sharing an instance share its object.
4. **Look up each unit** by the hash of its text, target flags, optimization level,
   Zig version and runtime ABI, in `.mylang-cache/core/units/`.
5. **Compile the changed units in parallel,** as build slots allow, then link.

**Expected edit loop at 50k lines, debug:** about 1 s (incremental check, 0.3 s of
our own work, one unit at `-O0` ~0.3 s, link 0.03 s). Release adds one unit at `-O3`,
about 4 s for a 4k-line file. **Cold release build at 200k lines:** about 15 s of LLVM
on 16 workers instead of 218 s.

**Work packages (to be finalized after S3 exits, since S3-A changes the driver and
the standard-library import path):**
- **S4-F, front end:** `CATALOG-INTERN-1` (done here; needs the full old gate);
  `identify`'s remaining scan over every graph node per call; the semantic cache in
  `frontend.Session` (target: the merged check after an edit at or below the old
  core's 0.45 s at 96k lines).
- **S4-E, emission:** unit-local constant and metadata numbering, a site table per
  unit (`myl_core_trap` takes the unit's table or a site pointer), cross-unit `hidden`
  linkage, deterministic output, and `--verify-cache` (rebuild reused units and
  compare objects).
- **S4-C, cache and driver:** the unit cache, parallel `zig cc` under the build
  slots, the link step, cache eviction with `scripts/prune-caches.sh`.
- **S4-M, modules:** user modules and `.myi` interfaces admitted by the new core;
  `mylang test` on projects; the S4-only `tests/lang` exclusions from S3.
- **S4-P, projects:** the Lox port and an EDA slice under the new core; build and test
  times against the old core's, remeasured at S4 start.
