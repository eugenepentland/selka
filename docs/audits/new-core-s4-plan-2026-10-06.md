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

## 3. The parallel spike (now, during S3)

Read-only with respect to S3's files; runs on `claude/new-core-s4-design` from S3's
Wave B base (`8918de74`). Builds go through `scripts/build-slot.sh`, kept to a minimum
while Codex's four Wave B packages hold the slots. Evidence goes in
`experiments/new-core-s4-20261006/`.

1. **Phase costs at scale.** Synthetic programs of about 5k, 50k and 200k lines built
   from constructs the new core accepts, split into many modules' worth of functions.
   Time each phase: check, Core IR build, release passes, emission, LLVM `-O0` and
   `-O3`, link. Answers whether "whole pipeline every build" fits the edit-loop budget.
2. **Codegen units.** Split the emitted `.ll` into per-module units and compile them
   separately: total and per-unit LLVM time cold, against the single `.ll`; link time.
3. **Edit ripple and name stability.** Edit one function body, re-emit, and count the
   units whose text changes; list every global numbering that makes unrelated units
   change (requirement 1).
4. **Front-end reuse.** Per-edit check time with and without the semantic cache on the
   same programs.

The spike's results become §4 (design) and the Codex work packages; S4 is then ready
to launch at the user's S4 go.
