# New compiler core, stage S4: codegen units and the build cache

Status: design for S4's emission and cache packages (S4-E, S4-C), written during S3
on `claude/new-core-s4-design`. Implementation starts after the S3 exit and the
user's S4 go, against the S3 exit's emitter (§3 lists what S3 added). The decision it implements is S4-1 in
`docs/audits/new-core-s4-plan-2026-10-06.md`, and the measurements behind it are that
plan's §3.

## 1. The invariant

**A unit's LLVM text is a pure function of three things:**
- the functions assigned to it;
- the whole-program facts those functions consumed (inlined bodies, caller-derived
  ranges, ownership plans);
- the target.

Nothing in the text depends on another unit's content, except the declarations of what
it calls or reads.

That makes the build cache exact without any dependency tracking. If two builds emit the
same text for a unit, its object is the same, so the object is reused. If anything the
unit consumed changed, its text changed. Every rule below exists to keep this
invariant. A rule that would let an unrelated edit change a unit's text is a cache
miss, not a correctness bug. A rule that would let a consumed fact change *without*
changing the text is a correctness bug, and the `--verify-cache` check (§6) exists to
catch it.

## 2. Units

**Release builds are one unit (the user, 2026-10-07; plan S4-1a).** Everything in §2–§5
applies to debug builds, which include `mylang test` and the edit loop. A release build
emits the whole program as one unit under the same naming rules, cached by its text like
any unit. Splitting release builds lost LLVM's inlining across units: up to 1.39× on the
split applications.

- **One unit per source module** (file). A function belongs to the module its
  declaration came from; `"my.<module>::<name>"` already carries it.
- **The entry unit** holds `@main`, the entry wrapper and the program-wide constants
  that are genuinely global: `@myl_core_source_path` and the free-list table
  declaration.
- **Generic instances and compiler-generated helpers** (structural equality per type,
  adapters) get **a unit of their own each**, named by a hash of their text.
  - Two modules using `sort[Record]` share one object.
  - A module adding a new instance compiles only that instance.
  - Tiny units are compiled in one batched `zig cc -c a.ll b.ll …` call, so they do not
    each pay a process start (§6).
- **Runtime inline helpers** (`alwaysinline` `myl_core_*`) stay `internal` and are
  copied into each unit that uses them, as the single-unit emitter does today.

## 3. Names and linkage

**Functions:**
- **Program functions keep their stable source-derived names.** A function called from
  another unit is defined `hidden` (external linkage, not exported from the
  executable). Every other function stays `internal`.
- **Calling convention:** every program-defined function uses `fastcc` at its
  definition and at every call. Today LLVM gives internal functions `fastcc` on its
  own; an external definition would lose it.
- **Runtime and `extern_c` functions** keep the C convention.
- **Check:** S4-E measures the five applications split into units against their
  single-unit build, and the gap must be within noise.

**Today's emitter numbers seven things across the whole program** (`emit_llvm.zig`),
and all of them become unit-local:

| Today | S4 |
|---|---|
| `@myl.op.N`, `@myl.fn.N`: one per trap site, in program order | removed; the site record holds its strings (§4) |
| `@myl_core_sites`, `@myl_core_site_count`: one program table | removed; a private `@myl.site.N` record per site, per unit |
| `@myl.str.N`: by module string-table index | numbered per unit, by first use |
| `@myl.layout.N`: by first use in the program | numbered per unit, by first use |
| `@myl.dict.N`: by Core IR compound type id | numbered per unit, by first use (a type id depends on what other functions created first) |
| `!range`, loop and TBAA metadata: one counter | per unit |
| debug metadata: one compile unit, one file `program.my` | one `DICompileUnit` and the module's real `DIFile` per unit |

**S3 added four more** (checked at the S3 exit, `d4994214`). They follow the same
rules:

| Today | S4 |
|---|---|
| `@myl.value.N` with `.children.N` and `.offsets.N` (`emit_values.zig`): descriptors for recursive equality and hashing, by Core IR type id | numbered per unit, by first use |
| `@myl.render.ID` with its `children`, `offsets`, `names` (`emit_render.zig`): render descriptors, by the lowering's metadata id | numbered per unit, by first use |
| `@myl.zeros` (`emit_llvm.zig`): one zeroed constant sized to the program's largest use | per unit, sized to the unit's largest use |
| `@myl_core_source_path`: one external constant that trap and trace text print | removed; each site record points at its module's path (§4) |

**The driver also decides two links by scanning the one `.ll` text** (`driver.zig`):
- the cached float-text object, when `number_runtime.needed(llvm)`;
- `-lm`, when the text calls `llvm.sin.f64` or `llvm.cos.f64`.

With units, each decision is the union over every unit in the program, cached or not.
So a unit's cache entry records its own two answers.

The spike's `--normalize` mode simulates exactly this renumbering. With it, a 48k-line
project's units changed only where the edit was, or where the edited function was
inlined (`units-ripple.json`).

## 4. Trap sites and error traces (a runtime ABI change)

**Today:**
- `myl_core_trap(i32 index, i64, i64)`, `myl_core_assert_fail(i32 index)` and
  `myl_core_err_trace(i32 index, i32 restarts)` index the program-wide
  `myl_core_sites` table;
- the error-trace ring and its origin store those indexes (`core_rt.c`).

**S4:**
- Each unit emits its sites as private `%myl.site` records, with the operation and
  function strings inline or as private constants.
- The three runtime entry points take `ptr` to the record.
- The trace ring and origin store `const myl_core_site *`.

**Cost:**
- Trap and assert calls are cold, so nothing changes on a hot path.
- An error-trace push stores 8 bytes instead of 4. S4-E measures `result_propagate` and
  the applications that propagate errors, and the gap must be within noise.

**Output:** trap reports, error traces and their text are byte-identical to today's.
The record carries the same kind, line, column, width, operation and function.
Conformance at 0 mismatches is the check.

## 5. Facts and determinism

- **Cross-unit facts are correct by construction.** A callee whose parameter ranges come
  from callers in other units (`NEW-CORE-FACTS-10`) carries those ranges, and their
  verify asserts, in its own text. A caller edit that changes them changes the
  callee's unit. Inlined bodies are in the caller's text.
- **Emission must be deterministic:** units, functions, constants and metadata in IR
  order, and no iteration over hash maps. Two builds of the same program must give
  byte-identical units. That is a test (§7).
- **Line numbers:** an edit that shifts lines changes only its own module's unit,
  because only that unit's debug metadata names those lines.

## 6. The cache and the driver (S4-C)

**Key:** BLAKE3 over all of these:
- the unit text;
- the optimization level;
- the resolved target, which means the host CPU's model and features rather than the
  string `-march=native`, so a cache copied to another machine cannot serve a wrong
  object;
- the Zig version;
- the core runtime ABI version;
- the emitter version.

**Store:** `.mylang-cache/core/units/<key>.o`, written to a temporary name and then
atomically renamed. `scripts/prune-caches.sh` evicts it like the other caches.

**Hits** spawn no process; that is why the cache is the core's own and not only Zig's.
Zig's own local cache also reuses an identical `.ll`, but at a process start per unit.

**Misses** compile in parallel:
- up to `MYLANG_JOBS`, else the available cores;
- small units are batched into one `zig cc -c` call with several inputs;
- the runtime object stays cached by content, as today;
- linking all objects with the runtime took 0.04–0.07 s for 49 units.

**`--verify-cache`** recompiles every unit the cache served and compares object
bytes. The new core's test suite runs it on a multi-module fixture, and S4-X runs it
once over the Lox port and the EDA slice.

**As built (S4-C, 2026-10-07; `src/core/unit_cache.zig`, `driver.zig`, `build_replay.zig`):**
- **Store location.** Unit objects live in the per-user runtime directory
  (`MYLANG_CORE_RUNTIME_CACHE`, else `$XDG_CACHE_HOME/mylang/core-runtime`, else
  `~/.cache/mylang/core-runtime`) under `units-v1/`, not in `.mylang-cache/core`: the
  key is the object's complete input, so sharing is safe, and fresh worktrees and test
  temporary directories reuse objects instead of recompiling them. Each `<key>.o` has a
  `<key>.sum` (size and BLAKE3 digest); a hit rehashes the object, so a damaged entry
  is a miss. A miss compiles beside its entry and is renamed into place (the store may be
  on another file system than the work directory). The runtime ABI in the key is the
  digest of the runtime source; the "emitter version" is `unit_cache.format`, since
  the text itself carries every emitter decision.
- **Batching** is not done: `zig cc -c a.ll b.ll` merges its inputs into one object,
  which would lose per-unit objects, and a tiny unit's compile costs about 20 ms, which
  parallel lanes absorb.
- **Program store.** The linked executable is kept in the work directory's
  `programs-v1/`, keyed by every linked object's bytes and the link settings, and copied
  to the output; a build whose objects all match starts no process.
- **Foreign C sources** (`--link`) compile with `-MMD` into `foreign-v1/`, keyed by
  their path, spelling, working directory and bytes; a manifest lists the depfile's
  headers with their digests, and the object is reused only while all keep their
  bytes. A file whose status changed after a marker created before the compile is not
  pinned, and nothing is cached for that build.
- **Whole-build replay.** `replay-v1/<key>` holds, per entry and settings, every file the
  build read with the digest of the bytes it used, the program entry and the report.
  An unchanged build rereads and rehashes those files, revalidates the toolchain and
  copies the program: no front end, no pipeline and no process (48k lines: 5 ms).
- Every `zig` process gets a fresh local cache inside a staging directory removed at
  the end of the build, so successful builds no longer retain `program-<nonce>`
  directories and Zig's cache no longer keeps a second copy of every object.

### Intermediate reuse (2026-10-09)

Edited builds also use the compiler-bound `stages-v1` store before the native
object store. Each artifact is one atomic file containing its input key, payload
checksum, and bounded plain-data encoding. Missing, damaged or unavailable entries
fall back to fresh computation. `--verify-cache` bypasses frontend and intermediate
reuse before checking native objects against freshly emitted LLVM.

- Checked ordinary bodies beyond the 16 MiB retained-memory budget are loaded
  from durable storage on demand, copied into the current checked program, and
  released. Cold checks publish the nonretained suffix one body at a time. The
  per-project durable limit grows with source bytes, capped at 4 GiB; this does
  not enlarge the memory retention budget or the 64 MiB individual-entry limit.
- After lowering, the backend owns the names, literal bytes and source metadata
  it still needs, so the frontend session can release its syntax and checked
  trees before optimization. Inlining safety proofs use caller-local scratch;
  only cloned IR and its source ancestry survive the caller's inline pass.
- Raw lowering artifacts capture each function and its ordered declaration,
  type, string, and pending-function discoveries. Replay relocates current source
  positions and string slots, then runs the existing module transforms. Saved
  source-backed IR and inline ancestry restore line/column positions against the
  current file; an earlier same-line length edit cannot install old byte offsets. Checked
  trees are hashed by content, including expanded generic/default bodies and
  embedded inputs. A rolling discovery guard avoids rescanning the growing IR.
- Optimizer artifacts preserve the original caller mutation order. Separate
  keys cover leaf/CFG inlining, unswitching, exploratory return/argument
  summaries, parameter-aware inlining, and final facts/ownership/vector results.
  Keys include the callee bodies or summaries actually consulted, incoming
  parameter intervals, source ancestry, and pass mode. An unchanged transform
  can restore a validated no-op receipt without copying another IR body.
  Ordinary optimized Debug builds retain final analysis as verified encoded
  bytes. LLVM keys use the analysis digest; only units that need rendering
  decode their functions' dense tables into private worker scratch. Statistics,
  fact verification, and whole-program LLVM requests retain the eager path.
- Function/type catalog changes conservatively invalidate lowering and optimizer
  artifacts across the module. Ordinary body and literal edits can reuse
  independent functions. This first implementation does not promise a narrow
  rebuild after every declaration or type-graph edit.
- Completed development LLVM units and generated-helper seeds use canonical
  input keys covering facts, effects, descriptor aliasing, exported symbols,
  located spans, inline ancestry, and emission options. Release emission remains
  one whole-program unit. Verified artifacts include runtime dependency flags,
  so hits do not rescan LLVM text for number helpers, math or counters. Bulk byte
  copies preserve the codec's original wire format. Native object keys and
  runtime optimization stay the same.
- Emission and native compiles use private worker scratch and both job-count and
  estimated-byte admission limits. The transient admission budget is at most
  1 GiB and at most one quarter of currently available memory; an oversized
  individual unit runs alone. This is a concurrency estimate, not a hard ceiling
  on the complete compiler process or an individual clang process.

The existing single-line `--report` JSON includes a `stages` object with actual
frontend, lowering, optimizer and emission reuse counters. Its `nanoseconds`
fields include lookup, hashing, decoding and publication in their stage times.
`native` includes object handling and linking; `linker` separately records time
inside the linker process and is zero when the program store serves the output.
Whole-build replay reports `stages: null`, since none of those stages ran.
`frontend_misses` uses `semantic_cache.MissReason` order and includes publication
bypasses. Expanded defaults with positions outside a retained declaration can
still require fresh checking; a rejected relocation never installs a partial body.

The scaling harness is `experiments/incremental-stages-20261009/benchmark.py`.
It takes `SCALING_COMPILER`, `SCALING_SEED`, `SCALING_DEPENDENCIES`, and
`SCALING_GOLDENS` paths through the environment. Run it through the build-slot
wrapper on the reserved benchmark CPUs with `--copies 12 32 --repeats 3
--few-edits --dependency-edits --threshold 1000 --output <fresh-directory>`.
The 12-copy project has 191,416 physical lines; the 32-copy project has 510,436.
Every replica is called and every generated project module is imported. This
is a synthetic scale test of the EDA port, not a separate 500k-line application.
It checks usage text, export goldens and leaks after each measured build. The
reported RSS is GNU time's largest process peak, not simultaneous process-tree
memory. Fixture generation, cache preparation and output validation are excluded
from build latency. Broad declaration changes are measured separately from
ordinary edits; a changed shared helper intentionally reaches all replicas.

### Scaling validation of intermediate reuse (2026-10-09)

Implementation `c48cfc24b` and source-position correction `7ab53ba6a` implement
all five stages: temporary-memory reclamation, durable checked/lowered/optimizer/
LLVM reuse, dependency invalidation, bounded emission/native work, and the large
EDA scaling matrix. Runtime optimization remains O2.
The corrected version passed the complete test gate: 91/91 build steps and
2,253 executed tests, plus all 88 whole-tree Guardian checks.

The final measurements and reproducible harnesses are in
`experiments/incremental-stages-20261009/`. `comparison.json` summarizes the
measurements; `matrix.json` and `reserved-edits.json` retain every sample, compiler
hash, source hash, cache counter, phase time, load reading and RSS measurement.
All 47 final large build invocations/setup builds passed all-replica usage,
blinky-breakout export goldens, and runtime leak checks.

| Synthetic EDA size | Entry edit median | Helper edit median | Three-file edit median | Steady-edit peak RSS, median |
|---|---:|---:|---:|---:|
| 191,416 lines | 8.51 s | 6.65 s | 7.08 s | 1.20 GiB |
| Approximately 510k lines | 22.57 s | 33.29 s | 23.18 s | 3.18 GiB |

These are three-sample medians on reserved CPUs 2,3,10,11: two physical P cores
with four threads, `MYLANG_JOBS=4`, with the compiler itself built ReleaseFast.
The guest is optimized Debug. This repeat uses fresh same-length edits and keeps
the reachable declaration added during the main matrix (510,440 lines versus
510,436 initially). Unrelated work on the shared host can still affect package
throughput and memory/I/O; these are measured results, not isolated hardware
limits. The earlier matrix used four physical P cores (0,4,6,8) and experienced
substantial contention. Its full samples remain in `matrix.json`, including
510k declaration-edit and shared-helper medians of 40.98 and 46.90 seconds. Do
not interpret the different runs as a controlled comparison of core counts.

For 191k lines, the prior memory-fixed compiler used 3.274 GiB on steady edits;
this version used 1.204 GiB, a **63.2% reduction**. The initial passes with empty
frontend/intermediate caches peaked at 2.05 GiB (191k) and 4.70 GiB (510k), both
within the default compiler host-memory limit. Those final setup builds reused
760/2,020 validated native objects and are explicitly labelled
`cold_stages_warm_native`, not fully cold builds. The separate shared fixture
has 510,470 lines and reused 2,021 native objects for setup. The older fully cold
native reference is qualified in `cold-native-reference.json`; no Release guest
builds were run. RSS is GNU time's largest process peak, not simultaneous
compiler-plus-worker memory.

The **15-second target is not yet met at 510k lines**. A representative repeated
entry edit spent 11.28 seconds in the frontend, 1.09 in lowering, 3.95 in optimizer
work/cache processing, 3.80 in emission/cache processing, and 1.85 in native
handling (including a 0.11-second linker process). It reused 2,019 of 2,020 native
units. Further progress needs less whole-program frontend and cache processing;
native recompilation and linking are already a small share of ordinary edits.
Declaration changes conservatively invalidate the ordered catalog. A changed
common helper invalidates its own and 32 callers' inlining artifacts even when
only the shared native unit needs recompilation.

The source-position regression tests compare exact fresh/cached LLVM, lowered
spans and reachable nested inline ancestry after an earlier literal grows on the
same line. Object auditing against the previous compiler found 760 of 775 objects
byte-identical; all 15 edited pairs have identical instructions, literal values,
DWARF line/info sections and runtime trap descriptors. Only literal-pool ordering/
alignment and corresponding reference addresses differ. See
`object-equivalence.json` for each pair.

The `--native-seed <completed-matrix-root>` option copies only completed object/
checksum pairs published before the source matrix's cold-build metrics cutoff;
edited variants are excluded. It asserts that frontend, lowering, optimizer and
emission caches start cold and that native objects are reused. Without the
option, the harness still measures full cold builds. The `repeat_edits.py`
companion takes `--input <completed-matrix-root> --output <fresh-result-root>
--copies 12 32 --repeats 3`, uses the identical recorded compiler and caches,
saves the original edited files, and requires exactly one or three native
compiles for every fresh edit. It leaves the fixture in its final edited state.

### Demand-driven body reuse (2026-10-09)

Edited builds can now omit an unchanged ordinary function's checked tree. The
frontend validates its declaration region, semantic dependencies and touched
record shapes, then propagates changes through the persisted reverse call and
function-reference graph. The remaining functions may use their saved facts and
diagnostics when a compact lowering manifest supplies their prior typed-body
digest or records that the previous completed build never reached them. Demand
checks publish updated summaries after every successful check.
Concrete generic-instance IDs are excluded from the ordinary summary table's
edges; those instances and their unsupported consumers still check normally.
Managed byte literals no longer eagerly create unused fixed-array types. Growing
a `b"..."` constant therefore leaves unrelated type-catalog entries stable;
actual fixed-array contexts still intern and check the decoded element count.
Type-suffix resolution shares an index keyed by both ends of each source span.
Nested list/optional suffixes can start at the same byte, so indexing only the
start is insufficient. This removes repeated scans of every suffix in the program
from ordinary, generic and symbolic type resolution.

Dependency keys resolve full dotted import qualifiers and retain domain suffixes.
Signature, visibility and record-shape changes invalidate stored consumers in
validation-only checks too. If checking with stand-ins encounters a body error,
it repeats without stand-ins so cached checks report the same complete error diagnostics
as a fresh check. Regression tests cover retained typed-body caches as well as
summary-only checking.

The manifest does not bypass raw lowering's ordered catalog, discovery, source
position or artifact validation. Only trees with local source positions receive
receipts; ordinary callee declaration positions relocate through the fresh
catalog. If an omitted body's artifact is missing or invalid, the pipeline
discards partial IR and diagnostics and repeats with complete checked trees.
Previously unreachable bodies use the same fallback if an edit makes them
reachable. Missing receipts and reached functions with unsafe source positions
never count as proof of unreachability. Lambda offsets are normalized only in
catalog and discovery guards; restored declarations take fresh names and spans,
so growing earlier text does not invalidate every unrelated lowered body.
`stages.lowering.deferred` counts actual frontend body omissions, and `fallbacks`
counts these retries. `--verify-cache` keeps the full-check oracle.

The optimizer also stores a compact index of raw bodies, exploratory summaries,
incoming parameter intervals and final artifact keys. An unchanged function can
skip intermediate stage lookups when all of its earlier transformation stages
were identity. Changed callees and function references invalidate callers;
changed incoming intervals demote candidates before parameter-aware inlining.
Recursive cycles use the existing ordered path. Final IR and facts still undergo
artifact validation. `stages.optimizer.bypassed` counts accepted final shortcuts.

This reduces repeated body work without promising that every build visits only
changed functions. Declaration collection, catalog validation, raw IR restoration,
some module analyses and LLVM-unit handling still process the wider program.
Declaration/type changes can invalidate the ordered catalog, and call-graph
changes can alter lowering's discovery order; either can trigger a broad fallback.
The optimizer still guards full names of reachable lambdas, so moving those
names can invalidate its layout even when raw lowering reuses unrelated bodies.
Native compilation remains per source module.

The paired harness `experiments/demand-builds-20261009/compare.py` runs both compiler
versions on identical source paths and fresh edits, with separate caches and
alternating execution order. Every sample changes source length. Changed native objects must have identical code,
literal values/references, debugger data and trap descriptors; only literal-pool
ordering/alignment may differ. Each executable must execute every replica and
pass the export goldens with leak checking.
Its setup starts with empty intermediate caches and validated cold native objects;
setup and validation time are excluded from edited-build medians.

The completed paired run is recorded in
[`experiments/demand-builds-20261009/README.md`](../../experiments/demand-builds-20261009/README.md):

| Lines | Edit | Previous median | Demand median |
|---:|---|---:|---:|
| 191,416 | Entry / helper / three files | 9.17 / 6.81 / 7.68 s | 5.94 / 4.83 / 5.45 s |
| 510,436 | Entry / helper / three files | 25.47 / 23.94 / 23.04 s | 14.25 / 12.69 / 13.65 s |

Eight of nine 510k edits finish within 15 seconds; the first entry edit after
setup takes 19.04 seconds, so the strict maximum remains unmet. Later edits range
from 12.49 to 14.25 seconds. Median incremental peak RSS is about 3.25 GiB at
510k lines. All 20 paired executables and 30 edited native-object pairs are
byte-identical. The full gate passes 93/93 steps with 2,275 executed tests.

The first-edit misses still include checked loop ordinals that differ between a
cold check and one that skips cached bodies. Fixing those requires consistent
function-local numbering through Core loop metadata and downstream receipts;
hash-only normalization would not preserve the exact fresh-IR oracle. Wider
artifact loading and validation also remain on the incremental path.

## 7. Tests S4 adds

- **Unit text stability:**
  - build a multi-module fixture twice; every unit is byte-identical;
  - change one function body; exactly its unit changes;
  - add a statement with a new checked operation; still only its unit;
  - change a small public helper that another module inlines; its unit and the
    caller's unit, and no other.
- **Cache:**
  - a second build of an unchanged program compiles nothing;
  - an edit compiles exactly the changed units;
  - `--verify-cache` passes;
  - a corrupted cache entry is detected and rebuilt, never linked.
- **Behavior:**
  - full conformance, debug and release, at 0 mismatches, with the leak and verify
    sweeps;
  - trap and error-trace text identical across a multi-unit build;
  - the 46 rows, all single-module programs, emit one unit plus the entry unit, and
    their timings stay unchanged.
- **Release mode (S4-1a):**
  - a release build of a multi-module program emits exactly one unit;
  - an unchanged release build starts no `zig cc`;
  - a split debug build's output equals the release build's on the five applications.
