# P1 report — stopped at the §9 scope boundary

2026-10-08. **P1 is not implemented or qualified.** The P1-0 audit found a
necessary emitter change outside §5's explicit ownership list. Work stopped
before P1-1, as §9 requires: “A needed change elsewhere is a stop and a report.”
The retained changes are this report, the plan's Status line, and isolated audit
tools/evidence. No compiler or runtime source was changed.

## 1. Branch, commits and what was built

- Branch: `codex/concurrency-p1`, created from `claude/concurrency-plan` at
  `c6606353b067b43636a78a27d77da8dac3fd7a4c`.
- Worktree: `/home/epentland/ai/canopy/mylang-concurrency-p1`.
- Launch `main`: `1edeef830913cf3557aed75417cc9adcd9fd3155`, an ancestor of the
  plan branch. `main` had not moved at the final audit check, so there was
  nothing to merge. No merge into `main`, push, or Claude-worktree edit occurred.
- Evidence commit: `4673418f136da26db0287858c984065f9a96c14f`
  (`audit: inventory P1 runtime and reproduce shared uniqueness race`).
  The following report commit records this stop and the plan Status update.
- Built with pinned Zig `0.17.0-dev.1683+5ceec001b`: two small LLVM/C TSan
  executables and an object containing the current runtime plus counting
  declarations/definitions for inventory validation. Every explicit compilation
  used `scripts/build-slot.sh build`; temporary files and caches were on disk
  under the Codex worktree and the shared Zig global cache.

### Required scope change: shared count readers

`src/core/emit_llvm.zig:212` defines `count_load_line` as an ordinary LLVM
`load i32`. `isUnique` at line 1822 uses it to read the count before comparing
with 1. A parent can perform this test after submission while a worker retains
or releases the same shared block. Atomic writes in the proposed slow helpers
do not make that ordinary read atomic. The unchanged comparison is correct;
the load feeding it is not safe under the proposed concurrency.

The experiment extracts the current instruction shape and metadata, pairs it
with a worker doing relaxed atomic increments and release atomic decrements,
and keeps two owners alive for the entire run. There is no reclamation race.

| Reader | Repetitions | Result |
|---|---:|---|
| Current ordinary load + `icmp eq ..., 1` | 1 | TSan data race, exit 66; atomic worker write conflicts with `p1_is_unique`'s read |
| Same load changed to `load atomic ... monotonic` | 100 | All exit 0, no TSan reports; every run prints `unique=0 count=80000002` |

Evidence: [race log](evidence/count-reader-plain-000.log),
[per-run results](evidence/count-reader.json),
[ordinary LLVM](evidence/count-reader-plain.ll),
[atomic LLVM](evidence/count-reader-atomic.ll).
This is a minimal two-thread probe, **not** P1-5's eight-thread suite, and it
does not establish the correctness of an unimplemented scheduler.

The smallest proposed scope extension is permission to change the common
`count_load_line` template (and its comment) to an atomic monotonic load,
covering `isUnique`, `countBlock` and `freeUnique`'s verification read. The
`count == 1` comparison and `[1, 0)` range remain unchanged. Plain count
**updates** can remain ordinary stores before publication. This extension
has not been applied. Its performance must be included in P1-1's early tax
measurement; no assumption about a zero performance cost substitutes for it.

§5 permits only `countBlock`, allocation/free text, the free-list declaration
and `sanitize_thread` in this emitter. Changing the common template affects
the explicitly excluded uniqueness path. Keeping it unchanged would leave
the demonstrated race; hiding the change inside an allowed function would
evade that scope boundary.

## 2. P1-0 inventory and ABI findings

The Clang AST inventory contains **103 named C declarations: 97 definitions
and 6 extern declarations**, including function-local statics and the counting
runtime. [static-storage.json](evidence/static-storage.json) records each name,
type, source line and enclosing function. Decisions below are the proposed
implementation treatment, not completed changes. Anonymous string literals
are immutable shared storage; automatic locals and types are not global state.

### `core_rt.c`

| Objects | Decision |
|---|---|
| `core_trap_marks_all` | Set in startup/test setup before any worker; immutable during guest execution. |
| `heap_ceiling` | Publish once before the pool. `heap_exhausted` currently clears it: replace that failure-path mutation with reporting that does not allocate or charge. |
| `heap_held` | Atomic accounting only when a ceiling is active, including overflow-safe charging/refunding. |
| `live_blocks` | Atomic carved/large-block count. At exit, subtract free blocks from **all** worker lists after quiescence, not just the caller's TLS list. |
| `myl_core_free_lists`, `chunk_next`, `chunk_end` | TLS; compare initial-exec and local-exec. A cross-thread free joins the freeing thread's list. Chunks remain allocated. Register worker allocator state for leak accounting. |
| `streams` | Preserve pre-pool buffering. Once workers start, use per-thread staging and a stream mutex per complete output unit, including units larger than the existing 64 KiB buffer. |
| `error_trace` | TLS ring and flags; crossing a task boundary does not carry this trace in phase 1. |
| `dwarf` | Lazy debug-section mapping restricted to the winning fatal reporter, or initialized once; avoid concurrent lazy writes. |
| `trap_capture`, `trap_capture_size`, `trap_lines_left` | TLS report scratch. Claim the process-wide trap winner before any reporting mutation. Losing reporters park. |
| `core_io_site` | TLS current capability-call location; otherwise a worker can overwrite another task's blame site. |
| `layout_blocks` | Immutable child-layout table. |
| `__ehdr_start` | Immutable linker-provided executable image base. |
| `output_refused::text`; `out_of_memory::{ceiling,message,record}`; `myl_core_args::refused`; `print_result_requested::wanted`; `myl_core_assert_fail::{codes,described}` | Immutable diagnostic/option strings and tables, shared unchanged. |

All fatal paths matter, including output refusal, OOM, assertions, I/O failure
and stack overflow. Taking a normal stream/I/O mutex from a synchronous signal
handler while the interrupted thread holds it can deadlock. The eventual
winner path must also avoid normal Host/provider cleanup racing with another
thread still running: C5 calls for a process exit, not concurrent unwinding.

### Text, numbers, sorting, bytes and value algorithms

| File / objects | Decision |
|---|---|
| `core_text.c`: `core_text_walked` | TLS counter registered for a sum at exit; preserve the diagnostic total. |
| `core_text.c`: `core_ascii`, `core_ascii_ready` | Complete the lazy immortal-character table before starting workers, or initialize it once under synchronization. Immortal does not mean safe to initialize concurrently. |
| `core_text.c`: `core_text_list_layout`, `core_repr_escape::hex` | Immutable. |
| `core_unicode_data.h`: `core_nonprintable` | Immutable Unicode range table. |
| `core_number.c`: `core_number_pairs`, `core_number_powers` | Immutable conversion tables. |
| `core_sort.c`: `s2_key_shape_decode::widths` | Immutable widths table. Sorting scratch is per invocation. |
| `core_bytes.c`: `myl_core_bytes_hex::digits` | Immutable hex table. |
| `core_dict.c`, `core_values.c` | No declared static objects. Dictionary metadata belongs to its block; equality/hash/render scratch is per invocation. |
| `core_number_text.zig`, `core_number_parse.zig`, `core_number_format.zig` | No mutable module storage. Imports/types and numeric limits are compile-time constants; `blanks` and literal tables are immutable. The extern `Block.count` field is declared but never accessed by these Zig files. |

Text also has **per-block mutable caches** that a static-object inventory alone
does not capture: `kind` flags, `reserved` hash/scalar caches, and the cursor
stored in `cap` or trailing spare bytes. Hashing, scalar counting and cursor
updates must cease writing them once the block is shared. Existing cached
values may be read after publication. Merely making the global walk counter
TLS would leave these races intact.

### `core_io.c`

| Objects | Decision |
|---|---|
| `core_io_native`, `core_io_embedding` | Initialize provider configuration before workers; immutable thereafter. Serialize calls to shared provider state unless the provider contract guarantees thread safety. |
| `core_io_initialized` | Once-only initialization before publication; no unsynchronized lazy initialization from worker capability calls. |
| `core_io_restricted`, `core_io_clock`, `core_io_entropy`, `core_io_environment`, `core_io_host` | Startup grants, immutable once workers exist. |
| `core_io_options`, `core_io_names`, `core_io_enumerated_names` | Startup option backing storage and name filters; immutable for pool lifetime. Delay normal cleanup until quiescence. |
| `core_io_grants`, `core_io_grant_count`, `core_io_option_argument` | Startup-only parser/grant state. No worker changes. |
| `core_io_real` | Its grant roots/endpoints are startup configuration; its handle slots and sequence counters need the I/O mutex. |
| `core_io_seed` | Startup seed; freeze before worker publication. Actual entropy progression also lives in each provider's `CoreIoState.value` and needs serialization. |
| `core_io_tail`, `core_io_open_count`, `core_io_family_open` | One mutex around handle admission, registration, unlinking, counters and cleanup. A check-then-increment must be one critical section. |
| `core_io_scratch_head` | Protect the scratch registry, including unlink/free and cleanup, with the I/O mutex. |
| `core_io_cap_layout`, `core_io_resource_layout`, `core_io_provider_layout`, `core_io_result_pointer_layout`, `core_io_result_scalar_layout`, `core_io_list_layout`, `core_io_raw_layout` | Immutable layouts. Provider layout currently omits the `pairs` child, which is released by a special finalizer: the common child iterator must cover it. |
| `core_io_file_error::verbs`, `myl_core_file_access::letters` | Read-only lookup tables (the `verbs` pointer slots are not declared const but are never written). |
| `myl_core_environment_names::environ` | External process environment. Guest environment access is read-only; externally supplied providers need serialized calls. |

Additional reachable state is dynamic: `CoreIoState.value` (clock/entropy),
`CoreIoState.memory` (`MemoryFs` entries, handles, IDs), scoped handle tables,
and provider contexts. Sharing a capability is allowed by C3/C6 and does not
make this state immutable. Lock provider operations as well as the global
handle table. Owned resource arguments remain a P2 checker rejection.

### `core_host.c`

| Objects | Decision |
|---|---|
| `core_host_scratch_head`, `core_host_types`, `core_host_declarations`, `core_host_cache`, `core_host_calls`, `core_host_work`, `core_host_budget_initialized`, `core_host_invoking` | Main-thread-only Host state. P2 rejects Host in tasks, so ordinary execution needs no worker access. Fatal cleanup from a worker must not traverse this state while the parent is in a Host call. No change to this out-of-scope file was made. |

### `core_test.c`

| Objects | Decision |
|---|---|
| `core_test_input`, `core_test_output`, `core_test_values`, `core_test_path`, `core_test_trials` | Batch/child control and property exchange, confined to runner/main-thread protocol. Batch parent must never start the pool. |
| `core_test_steps`, `core_test_bounded`, `core_test_frame_limit`, `core_test_depth` | Preserve deterministic counters; any active step/frame budget forces one thread before submission. |
| `myl_core_run_controls::installed` | Startup-only installation, before workers. |
| `core_stack_top` | TLS; each worker records its own bound. Each worker also installs its own alternate signal stack, whose backing mapping is currently an automatic pointer to a persistent mapping. |
| `core_test_body` | Main-thread trial trampoline, set before guest execution; no worker writes. |
| `core_test_table`, `core_test_rows`, `core_test_capacity` | Batch-parent registration table, complete before trials; read-only inherited child snapshot. |
| `core_run_timed_out::message`, `core_run_arm::refused`, `core_test_trapped::marker` | Immutable strings/record marker. |

The `SIGSEGV` handler disposition is process-wide even though `sigaltstack` is
per thread. Install the handler before starting workers. `setitimer`/`SIGALRM`
is process-wide: workers block `SIGALRM`; main handles timeouts. The test
runner's fork points and `RLIMIT_AS` are process state, not C global objects,
and still require the plan's pool-start prohibition and stack headroom.

### `core_count.c` and emitted globals

| Objects | Decision |
|---|---|
| `myl_count_current`, `myl_count_copy_site`, `myl_count_push_site` | TLS current records/sites; both C and emitted declarations must agree. |
| `myl_count_outside` | Per-thread outside-function counter storage, summed at quiescent exit. |
| `myl_count_live`, `myl_count_peak` | Process-wide atomic live total and atomic maximum: allocations can be freed on a different thread, so summing clamped per-thread totals would be wrong. |
| `myl_count_written` | One report writer; normal dump waits for completed tasks. Fatal dump must avoid reading concurrently modified non-atomic counters. |
| `myl_count_kinds`, `myl_count_slot_names` | Immutable tables, extended for shared retains/releases and walk marks/bytes. |
| `__start_myl_count_fns`, `__stop_myl_count_fns`, `__start_myl_count_sites`, `__stop_myl_count_sites` | Linker section bounds. Immutable metadata; counters in the sections currently mutate and need per-thread storage/aggregation. |
| `@myl_core_free_lists` (ordinary and counting emitter text) | TLS declaration in both paths; measure TLS models. |
| `@myl_count_current`, `@myl_count_copy_site`, `@myl_count_push_site` | TLS declarations matching C definitions. |
| `@myl.cf.N`, `@myl.cs.N` | Separate immutable identity/location metadata from per-thread counters and aggregate at exit. TLS current pointers alone do not make these shared slot arrays safe. |
| `@llvm.used` | Linker retention array, unchanged at runtime. |
| `@myl.zeros`, `@myl.layout.N`, `@myl.path.N`, `@myl.op.N`, `@myl.fn.N`, `@myl.site.N`, `@myl.str.N` | Immutable zero storage, layouts, diagnostics and immortal literals. |
| `@myl.dict.N` and its `.layout`; `@myl.value.N`, `.children.N`, `.offsets.N`; `@myl.render.ID`, `.children.ID`, `.offsets.ID`, `.name.ID.N`, `.names.ID`; `@myl.cstr.N` | Immutable dictionary/value/render descriptors and counter strings. No synchronization required. |

[emitted-globals.txt](evidence/emitted-globals.txt) preserves emission sites.
`emit_constants.zig` and unit assembly transport these existing definitions;
they do not introduce another mutable global family.

### Every runtime count site

The typed AST finds **19 source lines** with direct `myl_block.count` member
access; repeated reads/writes on a line are retained in its source text in
[count-accesses.json](evidence/count-accesses.json).

| File: lines / functions | Required treatment |
|---|---|
| `core_rt.c:187` / `block_alloc` | Initialize fresh unpublished count to 1. |
| `core_rt.c:386` / `retain_block` | Common retain helper, saturating plain counts before the shared-bit boundary. |
| `core_rt.c:460,461,464` / `myl_core_free_block` | Common release helper with an explicit last-owner result; enqueue final children iteratively. |
| `core_rt.c:474,475,476` / `myl_core_release` | Same common release semantics; null/immortal handling. |
| `core_dict.c:208` / `myl_core_dict_insert` | Atomic uniqueness read in verification. |
| `core_dict.c:312` / `myl_core_dict_copy` | Common retain for children. |
| `core_dict.c:341,342,345` / `core_dict_free_pending` | Common release for children, using the same iterator as sharing. |
| `core_text.c:67,102,129` / hash, scalar count, cursor cache | Atomic count classification; no cache mutation for shared or immortal blocks. |
| `core_text.c:287` / `core_text_append_bytes` | Common uniqueness check. |
| `core_io.c:975` / `core_io_retain` | Common retain, including null handling. |
| `core_bytes.c:121` / `core_buffer_owned` | Common uniqueness check. |

Count-bearing operations without `->count` must also be handled explicitly:

- `core_text.c:235` initializes the whole immortal ASCII header; initialize the
  table before publication.
- `core_rt.c:myl_core_list_grow` reallocates/copies an entire header on the
  unique/plain path. Allocator free-list links overwrite dead headers only
  after the final release has established exclusive reclamation.
- `count_runtime.zig` injects additional immortal tests into generated C and
  anchors patches on several lines above. Migrate both the injected tests and
  their anchors together with the runtime helpers.
- Other `->count` uses in `core_values.c`, `core_sort.c`, `core_io.c` and
  `core_host.c` are shape lengths, stack lengths, provider/collection lengths
  or declaration arities, not RC. A source guard cannot ban that token blindly.
- The source guard needs explicit handling for count initialization, shared
  marking and the atomic helper implementations, as well as retain/release/
  uniqueness. These are distinct from unrelated fields also named `count`.

The child walk must include guarded list/box fields, dictionary live-entry
fields, capability provider/parent/scope, resource authority, and provider
`pairs` (currently released in `core_io_finalize`). A `str_view` is an SSA
`{ptr,len}` borrowed span, not a distinct managed block kind at this base;
its retained owner is represented by ownership operations. New task result
and environment ownership still need the scheduler implementation/tests.

### ABI feasibility: not yet confirmed end to end

`test_builder.helper` declares `.runtime_c` helpers; `Builder.call` accepts
typed operands. Boxes and function values both emit as pointers. A generated
thunk can unbox arguments with `box_get`, call its target, then create an owned
result with **`box_make`** (the actual operation name, rather than `box_new`).
These building blocks do not suggest an `ir.zig` representation change.

There are two details for the resumed P1-0/P2-0 ABI check:

1. `func_ref` resolves directly to the generated function symbol.
   `emitFunction` defines it with LLVM **`fastcc`**, and the verifier requires
   internal linkage for a function value. The proposed C
   `myl_block *(*run)(myl_block *)` uses the C calling convention. Do not assume
   a C call through that pointer is supported merely because one pointer
   argument/return appears to use the same registers on this target. Establish
   an explicit C-to-internal thunk bridge, potentially in the runtime's LLVM
   assets, and test it before claiming this ABI works. P1-0 explicitly allows
   missing ABI details to be recorded for P2-0; this is not a request to change
   the frozen IR.
2. Generated `myl_core_site` constants are emitter-owned. A helper-only
   lowering needs an explicit way to pass the submit/map location (for example
   a runtime-owned site representation), rather than treating a managed box
   header as the raw `myl_core_site *` payload address.

No hand-built Core program was executed against a task ABI: the runtime does
not exist, and the scope stop was reached first. Thus P1-0's executable ABI
confirmation remains open.

## 3. Correctness gates

| Check | Status |
|---|---|
| Current runtime + counting declarations/definitions compile | PASS, pinned `zig cc`, exit 0. This validates the inventory translation unit, not concurrency. |
| Ordinary uniqueness-load TSan probe | Expected race reproduced, exit 66. |
| Atomic uniqueness-load TSan control | PASS, 100/100 runs, no reports. |
| Guardian commit gate for evidence commit | PASS, 88 checks. Existing file-size/function-length/line-length/ABI-layout findings were report-only. |
| Python tool syntax and evidence JSON | Validated. |
| `git diff --check` | PASS before evidence commit; checked again for report closeout. |
| `zig build test --summary all`; `zig build fmt-check` | NOT RUN: stopped before compiler/runtime changes. The commit's static Guardian gate is not the full gate. |
| `qualify_merge.py`: test-core and 1518/0/0 in both modes | NOT RUN. |
| Frozen fuzz 9×50, then 9×200 | NOT RUN. |
| Lox conformance, EDA goldens and 310 tests, parity expected outputs | NOT RUN; no external benchmark worktrees were needed before this stop. |
| Counting/ordinary output equality | NOT RUN. |
| P1-4 C scheduler unit/stress tests and 10⁶ submits | NOT IMPLEMENTED / NOT RUN. |
| P1-5 hand-built IR at 1, 2, 8 threads and TSan 100×8 | NOT IMPLEMENTED / NOT RUN. The small load probe does not substitute for this gate. |

Guardian was exercised by the commit hook; the required feedback entry is
appended and committed separately in `guardian-zig` at closeout.

## 4. Tax and TLS-model comparison

**Not measured.** No candidate compiler/runtime implementation was produced.
There are no base/package wall times, per-row medians, corpus geomeans or
measurement-load samples to report. The 46 CE-X rows, EDA, both Lox engines
and parity remain unmeasured. Initial-exec/local-exec TLS comparison was not
started. No performance gate is claimed passed or failed.

On resumption, include atomic count **reads** in P1-1's candidate before
measuring the early tax with the free-list declaration still plain. Apply the
exact ≤1.010 corpus-geomean and ≤1.03 row-median stop thresholds; only then
proceed to TLS and the remaining package steps.

## 5. Surprises and next-phase information

- The plan explicitly makes the share walk's reads atomic but does not cover
  the existing generated uniqueness load. This is the demonstrated stop.
- The inventory is larger than process-wide scalar globals: text caches,
  provider state, all-thread allocator leak accounting and counting-record
  slots must also be considered. A TLS free-list declaration alone is not
  sufficient for correct cross-thread destruction/reporting.
- The proposed C callback ABI needs the calling-convention/site checks above.
- Clang produced a complete AST, but the pinned `zig cc` wrapper returned
  `FileNotFound` after the AST-only action (there is no object to collect).
  [inventory.json](evidence/inventory.json) and
  [inventory-ast.log](evidence/inventory-ast.log) retain that status. A separate
  actual object compilation passed. The tool accepts only this specific
  wrapper error and requires valid complete AST JSON.
- Tracked report/tools/evidence are well below the 10 MB package cap. ASTs,
  objects, executable probes and caches remain untracked scratch on disk.
- P2 and phase 2 were not started. No user-facing parallel surface or feature
  claim was added. P1 requires a revised scope before implementation resumes.

## Reproduction

From the P1 worktree root:

```sh
python3 experiments/concurrency-p1-2026-10-08/tools/inventory.py
python3 experiments/concurrency-p1-2026-10-08/tools/count-reader.py
```

The scripts set on-disk temporary/cache paths and acquire build slots for
their compilations. The race probe's ordinary-load run is expected to fail
under TSan; the script itself succeeds only when that race is reproduced and
all 100 atomic-load controls succeed.
