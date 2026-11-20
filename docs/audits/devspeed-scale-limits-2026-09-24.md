# Development-speed lane: scale limits — 24 September 2026

Branch `devspeed/scale-limits`, from `main` `fd36abc2`, with `devspeed/integration`
`126a2b84` merged in at the end (as the coordinator asked). After the first round was
integrated (`ae5c9fd0`, fast-forwarded here), a follow-up made the cold 1M build fit the
default memory ceiling and scaled the remaining program-wide caps; see *Follow-up* below.
It implements items 4 and 5
of the compilation-model audit (branch `devspeed/compilation-model-audit`,
`docs/audits/compilation-model-2026-09-24.md` §9, §10.1, §11): lift the limits that
stopped a generated project from compiling past 200k lines, and stop an added function
from recompiling the shared metadata unit.

## Result

A generated 500k-line and a 1M-line project now `check`, `build` and `test` with no
`mylang.json`. The baseline (`fd36abc2`, ReleaseFast `integration-183251a9`) refuses
both at load time.

| Acceptance (audit §11) | Status |
| --- | --- |
| 500k and 1M `check` and `build` with no `mylang.json` under the default ceilings | **Yes, after the follow-up.** 1M cold build: 132 s, 5.52 GB peak, with no `MYLANG_HOST_MEMORY_LIMIT` (was 8.95 GB, needing 12G). 1M check: 8.2 s, 6.2 GB. 500k cold build: 66.7 s, 2.77 GB (was 4.50). |
| Adversarial generic and nominal fixtures still report their limits, per declaration | Yes. The field-work family is refused at its declaration `Uses`, the growing families at their instance and shape limits, and a 17-level alias chain at its use `T0`. New tests show two declarations that together exceed a budget, 60,000 materializations, and 3,200 ordinary records are accepted. |
| `evicted = 0` on an unchanged 500k rerun | Yes. An edit → check at 500k stores its entry, retains 147.8 MB (over the old 128 MiB) and evicts 0; at 1M it retains 294 MB and evicts 0. |
| `mylang test` works at 500k | Yes (3.8 s edit → test). Its 177 failures are all `R_FRAME_LIMIT`: the test of module *k* recurses *k* modules deep under the 1,024-frame test ceiling, as the audit found. At 1M it works too (1,377 such failures). |
| A deterministic regression test per fix | Yes, listed with each change below. |
| Item 5: adding a function keeps the shared metadata object (`metadata_reused: true`) | Yes: 0/5 → 5/5 interface edits at 200k; a CLI test asserts it. |
| Item 5: a ReleaseFast trap still names the frame | Yes: the same CLI test runs the rebuilt default-mode program and checks `in divide at` and `in main at`. |
| Item 5: the LTO build keeps every `_meta` | Yes: the full-table unit the LLVM arm links still roots every function (unit test). |

## What changed

Seven commits of work, one merge and one docs commit in the first round, two more in the
follow-up (below). Every behaviour has a SPEC.md bullet and a test tagged with it.

### 1. Both nominal `E_GENERIC_LIMIT` budgets are per declaration

`3dc1fa5d` — `NOMINAL-LAYOUT-BUDGET-1`, `NOMINAL-TEMPLATE-BUDGET-1`.

- **Layout graph** (`src/nominal_layouts.zig`, tripped at ~240k lines). The graph
  now opens a *request* for each declaration's symbolic root and for each concrete
  type the checker materializes. Work, instances and array shapes are charged to the
  request whose expansion first discovered a node (each queued node carries its
  request). Node order is still one BFS, so graph IDs, record order and output do not
  change. An exceeding request is reported at its declaration name or type spelling,
  with the type its expansion had reached as the related location.
- **Template index** (`src/nominal_templates.zig`, tripped at ~480k lines). The
  depth/visit budget restarts at every top-level type expression and reports at that
  spelling.
- Total work is now bounded by *(number of declarations and spellings) × budget*,
  which is linear in the source. The instance and array-shape limits moved with the
  work limit. One consequence: a declaration's own symbolic root is no longer shared
  with another declaration's count, so the `Tag`/`Values` boundary test moves by one
  (4,095 fields accepted, 4,096 refused).
- **Overlap with `devspeed/navigation-scale`.** That lane had changed the layout
  budget to `max(100000, source bytes)` for the whole program (`NOMINAL-LAYOUT-WORK-1`).
  The merge takes this design instead, drops that bullet, and keeps its
  "3,200 ordinary records" test as a spec-case summing every request's work.
- Tests: `nominal layout budgets apply per declaration…`, `every materialized concrete
  type gets its own layout budget`, `a large ordinary project is not refused for its
  total layout work`, `nominal expression checking bounds each top-level expression…`.

### 2. Frontend cache retention scales with the working set

`4af784fe` — `FRONTEND-CACHE-RETAIN-1`.

- **The cause.** The cache trimmed its directory to a fixed 128 MiB after every store,
  oldest write first. From ~440k lines, one run's working set (8 bytes of cache per
  source byte) is bigger than that, so every run evicted everything it had stored.
- **Principle.** A run keeps its whole working set plus as much again of history.
  - A run now trims **once**, after the command and before its receipt, to
    `max(128 MiB, 2 × bytes this run read back or stored)`.
  - A successful read renews the entry's mtime, so eviction is least recently used
    first and the entries a run needs go last.
- Trimming once per run also removes a quadratic cost. The old code listed and
  `stat`ed the whole directory after *every* store: 2,400 × 2,400 at a cold 1M.
- **Disk cost.** The working set is 147.8 MB at 500k and 294 MB at 1M (8.0–8.4 bytes
  per source byte). The directory is bounded at twice that: ~16 bytes per source
  byte, ~560 MB for a million lines per compiler identity. The 128 MiB floor still
  covers small projects, and entries larger than 128 MiB are still bypassed. The
  largest entry at 1M, the summary slot, is 39 MB, so that per-entry cap is reached
  at ~3.3M lines; the follow-up scales it (`FRONTEND-CACHE-ENTRY-1`).
- Test: `the frontend cache keeps a working set larger than its floor and evicts
  least recently used history`.

### 3. `mylang test` follows the project's byte budget

`c308f2e4` — `PROJ-SCALE-1`.

- The snapshot now reads `mylang.json` before it walks the project and bounds its
  bytes by the configured `max_total_bytes`. So does a provider snapshot. It used to
  have a fixed 16 MiB cap, which `mylang.json` did not govern.
- The resolved identity loads under the configured budgets rather than the defaults.
- Test: `a test snapshot is bounded by the project's configured source budget…`.

### 4. Default project budgets admit a million lines

`c308f2e4` — `PROJ-SCALE-1`, `PROJ-6` amended.

- Defaults went from 16 MiB of source, 4,096 modules and 65,536 import edges to
  **64 MiB, 16,384 modules and 262,144 edges**. The 4 MiB per-file cap is unchanged.
- A generated 1M-line project is 35.1 MB in 2,401 modules. 64 MiB is ~1.9M lines of
  this shape. 16,384 modules allows a 64-line average module at 1M lines, and 4,096
  would have tripped a real project of ~250-line modules.
- All four stay configurable in `budgets`. `navigation-scale`'s actionable
  `E_PROJECT_BYTES` message (`PROJ-BUDGET-MESSAGE-1`) is kept.
- `docs/modules.md` still gave the pre-PROJ-6 limits (256 modules, 16 MiB); it now
  gives the current defaults.

### 5. Links go through response files; a refused tool start names its cause

`83790037` — `BUILD-LINK-RSP-1`, `HOST-FAILURE-CAUSE-1`.

- **Response files.** Every command whose argument list grows with the program now
  passes everything after `zig cc`/`zig ld.lld` through `@link.rsp` beside the
  output:
  - the driver link;
  - the `zig cc -###` recording run;
  - the direct `zig ld.lld` link from a template;
  - the full-LTO frame-map link's two commands.
- **Quoting.** Arguments with whitespace or a leading `#` are double-quoted. An
  argument with a quote or a backslash keeps the whole command on the command line,
  because Zig's reader (Windows-style backslash rules, `'` as a quote) and LLVM's
  (GNU) read those differently.
- **`zig cc`'s own limit.** `zig cc` still starts its `ld.lld` child with every object
  named. `zig` raises its own stack limit, so that child can take ~6 MB, not the 2 MB
  `ARG_MAX` of an 8 MiB stack. When the recording run fails having printed its linker
  command, the build links directly from the printed command through a response file
  and keeps it as the template. A real link error fails that link too and is reported
  from `zig cc` as before.
- **Naming the cause.** The spawner maps `E2BIG` to `ArgumentListTooLong`, not
  `Unexpected`. Any other errno it has no name for is written to stderr
  (`mylang: execve TOOL failed: errno NAME`) before the generic failure.
- At 1M the first link of the shape (19,007 objects) now succeeds. The cold build
  below links through it.
- Tests:
  - `a response file carries every argument after the kept ones…`;
  - `a link naming more object bytes than one execve can carry…`: 7,000 objects
    under 900-byte paths, 6.3 MB. The raw command is refused as
    `ArgumentListTooLong`, and both the recorded and the direct link produce a
    program that exits 7;
  - `an argument list past the kernel's limit is refused as ArgumentListTooLong`.

### 6. Address space follows resident memory

`311cc177` — `ARENA-BOUNDED-1`.

- **The finding.** `std.heap.ArenaAllocator` makes each node half again the last. The
  project arena (every module's syntax and the checked program) is one arena, so at
  1M its next node would have been 3.3 GB, nearly all untouched. It crossed the 8 GiB
  ceiling with 4.24 GB resident. The smaps of a 500k check show the chain: 25, 39,
  58, …, 675, 1,013 MB resident, then a 1,521 MB node with 17 MB touched.
- **New `src/chunked_arena.zig`.**
  - Shared chunks grow by half up to 64 MiB.
  - An allocation of 4 MiB or more gets its own mapping. It grows by the child's
    `remap` (`mremap`) and is returned by `free`, so program-wide lists that grow
    leave no dead copies.
  - The untouched reservation is at most one chunk.
  - Its state sits behind one pointer, so copies of a project share it. It is
    single-threaded, like the frontend.
- It backs the project arena and the native emission's whole-program arena. The
  emission's `std` arena had a 752 MB node with 21 MB touched at 1M.
- A module's tokens (raw and layout-lowered, ~420 MB at 1M) are now lexed from the
  child allocator and freed after the parse. Nothing reads them afterwards.
- The parser takes the allocator its syntax lives in (`storage`) instead of a
  `*std.heap.ArenaAllocator`.
- Tests: `the chunked arena reserves at most one chunk beyond what it holds…` and an
  allocation-failure sweep.

### 7. A cold `mylang test` gives back each header load

`48b26186` — `NATIVE-TEST-MEMO-MEMORY-1`. This was found at 1M.

- **The symptom.** `mylang test` failed with `OutOfMemory` within half a second, at
  453 MB resident.
- **The cause.** A cold snapshot identity loads each module the import memo has not
  seen, to read its header. Each load allocated a project arena and a 1 MiB header
  scratch from the build context's arena, which frees nothing: 2,401 loads, 3.8 GB,
  and a 10.7 GB next node (`strace -k`).
- **The fix.** Those loads now run on the context's parent allocator and return their
  memory. The names they keep are still copied into the context.
- Test: a cold capture of a 64-module chain grows the context by less than 16 MiB. It
  fails without the fix.

### 8. Item 5: frame-map roots only in the LTO unit

`f2754227` — `QBE-FRAMEMAP-ROOTS-1`, `QBE-BATCH-3`/`-4` amended.

- **The change.** `metadataUnit` now emits the `used` roots array (and its `extern`
  list) only with the full tables. That is the LLVM arm's unit, the one a full-LTO
  link optimizes. It is one line:
  `const roots = tables and usesFrameMap(functions);`.
- **Why it is safe.** A batched QBE build is never LTO. Its frame-map sections already
  reference each `_meta` their entries reach, and `--gc-sections` keeps them. So the
  shared C unit names no function, and adding one leaves its key unchanged.
- **Scope.** The signature of `sharedMetadata` is unchanged. This differs from the
  audit's prototype, which threaded an `lto` flag through; that is always false in
  the batched arm.
- Tests:
  - unit: the shared unit is byte-identical for one and two frame-map functions, and
    the full-table unit still roots them;
  - CLI: `CLI default build keeps the shared metadata object when a function is added
    and its trap still names every frame`.

## Gate

Run once on the final tree (`48b26186` plus this report), through the build slots:

| Step | Result |
| --- | --- |
| `zig build test --summary all --maxrss 8000000000` | 93/93 steps succeeded (1,929 tests run, the rest cached verdicts) |
| `zig build test-qbe --summary all` | 52/52 steps, 402/402 tests |
| `zig build test-qbe-build --summary all -Dtest-rerun=true` | 34/34 steps, 118/118 tests |
| `zig build fmt-check` | clean |
| `zig-out/bin/mylang test tests/lang` | 569 passed, 0 failed, across 106 programs |

The whole unit root, run unsharded after the arena change, passed 1,678/1,678.

The follow-up's gate, on `5e5925f5` plus this report:

| Step | Result |
| --- | --- |
| `zig build test --summary all --maxrss 8000000000` | 93/93 steps (1,938 tests run, the rest cached verdicts) |
| `zig build test-qbe --summary all` | 52/52 steps, 403/403 tests |
| `zig build test-qbe-build --summary all -Dtest-rerun=true` | 34/34 steps, 118/118 tests |
| `zig build fmt-check` | clean |
| `zig-out/bin/mylang test tests/lang` | 569 passed, 0 failed, across 106 programs |

The unsharded unit root passed 1,700/1,700.

## Measurements

**Setup.**
- Compilers, all ReleaseFast and `-Dcompiler-only`:
  - *base*: the shared `fd36abc2` compiler
    (`trials/devspeed-20260923-private/compilers/integration-183251a9`);
  - *branch*: this branch. v4 is head `51b34d33` (after the merge). v5 adds the
    test-memo fix and is used only for the 1M `test` rows.
- Tiers: `gen_scale.py tNNNk M 38`, mylang only.
- Driver: `experiments/scale-limits-20260924/ladder.py`. It is `run_scale.py`'s
  ladder: taskset `0-11`, `/usr/bin/time %M` for the peak RSS of the command's
  process tree, and the minimum of 3 edit samples.
- Load: the machine was shared with the other lanes. The 1-minute load was 3.5–8.3
  during the ladders and **17–23 during the 1M test rows**. Treat walls as upper
  bounds; the integrator re-measures quietly.

### 200k (load 3.6–7.9)

| Row | base | branch |
| --- | --- | --- |
| cold build | 24.8 s, 1.94 GB | 28.5 s, 1.83 GB (load 6.8 against 3.6) |
| no-op build | 0.258 s | 0.260 s |
| edit → check | 0.557 s, 458 MB | 0.542 s, 444 MB |
| edit → build | 1.922 s, 979 MB | 1.831 s, 965 MB |
| edit → test | 1.611 s, 1.12 GB | 1.510 s, 1.10 GB |
| interface → build | 2.034 s, 949 MB | 1.844 s, 935 MB |

**Item 5 at 200k.** Five interleaved interface edits per compiler on the warmed work
dirs (`ab_iface.py`, load 5.0–5.5):

| | base | branch |
| --- | --- | --- |
| `metadata_reused` | 0 of 5 | **5 of 5** |
| codegen phase, min (of 5) | 0.314 s | **0.150 s** |
| codegen phase, all | 0.31–0.57 s | 0.15–0.35 s |
| wall, min | 1.842 s | 1.684 s |

The deterministic counter and the codegen phase are the evidence: −0.16 s of codegen
per interface edit, matching the audit's 0.26 s at load 5. Walls are dominated by
link noise (0.32–0.88 s per link at this load).

### 500k (branch; load 3.8–7.9)

| Row | base (no `mylang.json`) | base + `budgets.max_total_bytes` | **branch (no `mylang.json`)** | audit proto2 (patched base, load 6–18) |
| --- | --- | --- | --- | --- |
| cold build | `E_PROJECT_BYTES` at `m045` | `E_GENERIC_LIMIT` at `m581` | **65.0 s, 4.50 GB** | 89 s, 4.80 GB |
| no-op build | — | — | **0.611 s** | 1.47 s (with `--report`) |
| edit → check | — | — | **1.18 s, 1.06 GB** | 1.55 s, 1.12 GB |
| edit → build | — | — | **4.14 s, 2.27 GB** | 5.6 s, 2.40 GB |
| edit → test | `InvalidTestSnapshot` | `InvalidTestSnapshot` | **3.84 s, 2.66 GB** | 4.8–6.1 s, 2.78 GB |
| interface → build | — | — | **4.24 s, 2.27 GB** (`metadata_reused: true`, codegen 0.43 s) | 5.1 s |
| cold `test` | — | — | 11.2 s, 3.59 GB | 13.0 s, 3.95 GB |
| cold `check` | — | — | 4.9 s, 3.18 GB (4.7 GB address space) | — |
| frontend cache after an edit | — | — | `evicted: 0`, `retained_bytes: 147,773,908` | `evicted: 1203` (unpatched) |

### 1M (branch; load 3.5–8.3, test rows 17–23)

| Row | base | **branch** | audit (patched, load 7–9) |
| --- | --- | --- | --- |
| cold `check` | `E_PROJECT_BYTES` at `m1263`; with a budget, `E_GENERIC_LIMIT` at `m1821` | **8.2 s, 6.23 GB resident, 6.53 GB address space** | 11.7 s, 6.3 GB (14 GiB ceiling) |
| cold build | same | **fails at the default 8 GiB**: frontend `OutOfMemory` at 9.3 s, 8.36 GB resident. **With `MYLANG_HOST_MEMORY_LIMIT=12G`: 131.4 s, 8.99 GB peak**, linked through the response file | not reached (`E2BIG`) |
| no-op build | — | **1.45 s, 280 MB** | — |
| edit → check | — | **2.65 s, 2.08 GB** | 4.8–5.3 s, 2.31 GB |
| edit → build | — | **10.57 s, 4.59 GB** | projected 10–12 s |
| interface → build | — | **10.45 s, 4.51 GB** (`metadata_reused: true`, codegen 2.07 s) | — |
| cold `test` (v5) | `InvalidTestSnapshot` | **64.8 s, 7.28 GB peak**; 1,023 passed, 1,377 `R_FRAME_LIMIT` | — |
| edit → test (v5, load 17.6) | — | **11.2 s, 5.27 GB** (it re-runs the 1,377 failing tests, which never cache) | — |
| frontend cache after an edit | — | `evicted: 0`, `retained_bytes: 294,395,311` | — |

All the edit rows run under the default 8 GiB ceiling with no `mylang.json`.

## Follow-up: memory and the remaining caps

Two commits after the integration merge `ae5c9fd0`: `9d424db1` (memory) and `5e5925f5`
(caps).

### A cold 1M build under the default 8 GiB ceiling (`9d424db1`)

**How the memory was found.** `phase_rss.py` samples the frontend child
(`emit-project-qbe`, as `mylang build` runs it) every 20 ms and aligns the samples with
its `--timings=json` phases. At 500k, the phase that parses (+1.04 GB) and the phase that
lowers (+1.14 GB) grew far more than the data they produce. Most of that was growth
buffers left behind in arenas, plus tables nobody read again:

- **The parser's node and statement lists (`PARSE-EXACT-1`).** They grew by appending
  in the project arena. Each regrowth abandoned the old buffer: three times the final
  list, per module. They now grow in the arena's freeing parent and are copied in at
  their exact length when the parse ends.
- **Lowering (`LOWER-EXACT-1`).** Each function's work stack, labels, fixups, loop
  table and instruction list grew in the output arena, and so did bytecode
  validation's tables. They now live in a per-function scratch arena over a freeing
  allocator (`lower.Allocators`); only the finished instructions are copied out. The
  scratch resets with `.free_all`: a `.retain_capacity` reset reallocates, and would
  swallow its own allocation failure (the allocation-failure tests caught this).
- **Merged syntax after check (`SYNTAX-RELEASE-1`).** In a whole-program
  `emit-project-qbe`, lowering and emission read only the typed program and bytecode.
  So once the program is checked, the merged node and statement tables are returned;
  they have mappings of their own in the chunked arena, so the memory goes back to the
  system. The emitted program is byte-identical (tested).
- **The replay record (`MANIFEST-STREAM-1`).** It is written piece by piece around the
  manifest, hashing as it goes, instead of being assembled in one buffer. The frontend
  holds its manifest once, not twice.

**Cold build frontend, peak resident memory** (ReleaseFast; `fe.sh`, fresh cache, load
~6):

| Tier | before (`de222eb6`) | after (`5e5925f5`) | peak address space after |
| --- | --- | --- | --- |
| 200k | 1,826 MB | **1,129 MB** (−38%) | 1,240 MB |
| 500k | 4,490 MB | **2,751 MB** (−39%) | 2,895 MB |
| 1M | 8,950 MB (fails at 8 GiB) | **5,517 MB** (−38%) | 5,872 MB |

**Resident memory at the end of each 1M phase, after** (MB; 61.5 s cold frontend):

| parse | merge | keys | body check | effects | lowering | emission | peak |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 880 | 1,561 | 2,208 | 3,901 | 4,217 | 4,266 | 5,407 | 5,517 |

Merged syntax is released before lowering, so lowering adds 49 MB net. Before, it added
1.9 GB.

**Whole cold `build` peak, the largest process in the tree** (`/usr/bin/time %M`):
- 200k: 1,828 → 1,132 MB;
- 500k: 4,497 → 2,767 MB;
- 1M: 8,985 MB with `MYLANG_HOST_MEMORY_LIMIT=12G` → **5,522 MB with no override**.

The build driver peaks at 2.1 GB at 1M, after the frontend exits. Edit builds dropped
too:
- 200k: 935 → 826 MB;
- 500k: 2,251 → 2,008 MB;
- 1M: 4,513 → 3,982 MB.

A cold `mylang test` dropped as well:
- 500k: 3,591 → 2,970 MB;
- 1M: fails → 5,876 MB.

**What was not done, and why.**
- **Dropping each module's syntax after the merge.** Name resolution during check
  still reads the per-module declaration tables (`interfaces.Index` readers of
  `units[m].syntax.types`). Those tables share an arena with the bodies, so dropping
  the bodies alone needs a second arena for them. After `PARSE-EXACT-1`, per-module
  syntax is 2.4× smaller: 0.44 GB for the whole 500k parse phase, 0.88 GB at 1M.
- **Streaming the manifest to stdout.** The build driver reads the whole manifest
  from the pipe anyway, and the replay record stores it with the warnings before it.
  Full streaming needs a writer-based emitter API and a replay format with the warnings
  after the manifest. The remaining end-of-run spike is ~110 MB at 1M.
- **Releasing the typed program before emission.** An executable's stand-in emission
  may lower more functions mid-emission (`lowerMore`), and that reads it.

**What remains at 1M** (5.5 GB), from largest:
- the check: typed program and semantic keys, +1.7 GB;
- emission's per-unit records, +1.1 GB;
- per-module syntax plus the index, 0.88 GB;
- the merged syntax until check ends, +0.68 GB;
- dependency keys, +0.65 GB.

Per-module compilation (audit item 1) removes all of them from any one process.

### The remaining program-wide caps (`5e5925f5`)

| Cap | Before | After (effective limit) | Adversarial safeguard kept | Test |
| --- | --- | --- | --- | --- |
| Generic function instances (`GENERIC-INSTANCE-BUDGET-1`) | 4,096 per program | **4,096 per generic declaration**; the program total grows with its generic declarations | polymorphic recursion multiplies one declaration's instances: `grow[T]` calling `grow[list[T]]` still stops with `E_GENERIC_LIMIT`, and so does the expanding-array fixture | registry: one declaration refused at 4,097 while 4,097 others are accepted (8,193 in all); program: 4,097 generic declarations check |
| Generic array shapes (`GENERIC-SITE-BUDGET-1`) | 4,096 per program, byte literals included | **4,096 per source spelling** | a spelling makes a new shape only when a generic body is instantiated at new types, so recursion through it stops (in practice the declaration's instance budget meets it first); a byte literal is one spelling with one shape | `chargeSite`: one spelling refused at 4,097; another spelling and the other family at the same spelling keep theirs |
| Callback signatures (`GENERIC-SITE-BUDGET-1`) | 4,096 per program | **4,096 per source spelling** | as for arrays | same test |
| Nominal display names (`NOMINAL-NAME-BUDGET-1`) | 1 MiB per program | **max(1 MiB, one byte per source byte)** total; each name still ≤ 1 MiB | nested generic names grow with the square of their depth, so the `Chain` fixture still stops a small program at 1 MiB | 2,000 records with 600-byte names (1.2 MB of names, 1.3 MB of source) check; `largeNames` still refused |
| Frontend-cache entry (`FRONTEND-CACHE-ENTRY-1`) | 128 MiB | **max(128 MiB, 8 bytes per source byte)** once a project is loaded, so ≥ 280 MB at 1M against a 39 MB summary slot | a damaged length still cannot make a read allocate more than the project could have produced | a 1,500-byte entry is bypassed under a 1,000-byte ceiling and stored after fitting to a 200-byte project |

`callables.intern` still scans every record to find an equal signature: O(records) per
interned callback type. That is not a cap, but at 100k types with many function-typed
values it is quadratic. Replacing it with an index needs every callback record
registered, including the nominal ones `nominal_catalog` creates, so it was left alone.

## Notes for the integrator

- **`src/parser.zig`.** `Parser.arena: *std.heap.ArenaAllocator` is now
  `Parser.storage: std.mem.Allocator`. Any branch that constructs a `parser.Parser`
  must write `.storage = x.allocator()`; this branch updated its 9 sites.
- **`src/project.zig`.** `Project.arena` is a `ChunkedArena`. `.allocator()`,
  `.child_allocator` and `.deinit()` work as before. Code that passes `&project.arena`
  as a `*std.heap.ArenaAllocator` breaks.
- **LLVM arm (`llvm-zig` lane).**
  - `src/qbe_build_outputs.zig`: one changed line in `metadataUnit`, plus comments.
    Its LTO metadata unit is unchanged.
  - `src/qbe_build.zig` `linkAssembled`: two command lines now go through
    `direct_link.responseArgv`.
  - **`qbe_build_cache.declareSignatures` still passes one `.ssa` path per unit** to
    the adapter. At ~20k units that is past `ARG_MAX`, so the Zig adapter should read
    a response file or a directory.
- **`src/main.zig`.** `run()` calls `frontend_cache.finish()` before the receipt, on
  both the success and the error path. `buildIndex` fits the frontend cache to the
  loaded project (`fitProject`), and `listModulesWithCache` releases the merged
  syntax of a checked whole-program `emit-project-qbe` (`releaseCheckedSyntax`).
- **Follow-up API changes.**
  - `lower.lowerWith` and `lower.lowerSelectedWith` take `lower.Allocators{ output,
    scratch }` instead of one allocator; `scratch` must be a freeing allocator (the
    project arena's `child_allocator`).
  - `parser.Parser` takes an optional `.syntax = .{ .growth = gpa }`, and a caller
    that sets it must `defer p.release()`.
  - `project_compile.Compilation.releaseSyntax` empties `compilation.syntax.nodes`
    and `.statements`. Any new reader of the merged syntax after check, in the build
    frontend, must go before it.
  - `type_catalog.Catalog.chargeSite` replaces the `arrays.specialized` counter.
- **SPEC.md.**
  - New: `NOMINAL-LAYOUT-BUDGET-1`, `NOMINAL-TEMPLATE-BUDGET-1`, `PROJ-SCALE-1`,
    `FRONTEND-CACHE-RETAIN-1`, `BUILD-LINK-RSP-1`, `HOST-FAILURE-CAUSE-1`,
    `ARENA-BOUNDED-1`, `NATIVE-TEST-MEMO-MEMORY-1`, `QBE-FRAMEMAP-ROOTS-1`.
  - New in the follow-up: `PARSE-EXACT-1`, `LOWER-EXACT-1`, `SYNTAX-RELEASE-1`,
    `MANIFEST-STREAM-1`, `GENERIC-INSTANCE-BUDGET-1`, `GENERIC-SITE-BUDGET-1`,
    `NOMINAL-NAME-BUDGET-1`, `FRONTEND-CACHE-ENTRY-1`.
  - Amended: `NOMINAL-LAYOUT-1`, `NOMINAL-TEMPLATE-CHECK-1`, `PROJ-6`,
    `QBE-BATCH-3`, `QBE-BATCH-4`, and in the follow-up `GENERIC-INSTANCE-1`,
    `NOMINAL-INSTANCE-1`.
  - Removed: `NOMINAL-LAYOUT-WORK-1` (superseded; see §1).
- **Timing.** A cold 200k `check` with the chunked arena was within noise of the
  `std` arena (1.61 against 1.70 s minimum of 3, at load 6.5–9.7) and used 105 MB
  less (1,118 against 1,223 MB). The integrator should re-time the 200k and 500k rows
  quietly.

## Reproduction

```bash
# tiers (mylang only), in a scratch directory on disk
python3 experiments/scale-limits-20260924/gen_mylang.py        # writes t200k t500k t1m beside it
M=/path/to/ReleaseFast/bin/mylang
~/capbuild python3 experiments/scale-limits-20260924/ladder.py t500k $M branch
~/capbuild python3 experiments/scale-limits-20260924/ladder.py t1m $M branch --cold-env MYLANG_HOST_MEMORY_LIMIT=12G
python3 experiments/scale-limits-20260924/ab_iface.py t200k 5 base=$BASE branch=$M   # after both ladders
bash experiments/scale-limits-20260924/evict.sh t500k/work-branch $M m600.my         # frontend cache receipts
# address space against resident memory, with smaps at every 256 MB of growth
~/capbuild python3 experiments/scale-limits-20260924/vmprobe.py out.json -- $M check main.my
strace -f -k -e trace=mmap,mremap -o trace.txt $M emit-project-qbe ... && python3 experiments/scale-limits-20260924/bigmaps.py trace.txt 40
```

The results these tables come from are in `experiments/scale-limits-20260924/results/`:
`ladder-*.jsonl`, `vm-*.json` (address space and resident memory with smaps) and
`fe1m-*-timings.jsonl`.
