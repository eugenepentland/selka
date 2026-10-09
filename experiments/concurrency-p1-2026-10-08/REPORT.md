# P1 report — revision 3 in progress

## Current progress — 2026-10-09

- **Done:** P1 implementation and P2-0 analysis; full correctness and 300 TSan repetitions pass at `98cb3a49f`.
- **Measured:** Seven final runtime candidates have retained evidence. C has a complete five-corpus sweep below the 1.03 premise boundary, with strict target misses. G has only complete rows/EDA results and an interrupted parity run.
- **Decided:** Main advanced to `35df839be`; merge it with a real merge commit and adopt the simpler, fully measured candidate C. The user's latest instruction waives rerunning wall-time performance checks after integration. Hardware-independent output, counter and generated-code checks will supplement fresh correctness. Earlier timings do not certify performance on the merged version.
- **Next:** Integrate, rerun correctness, finalize evidence/report. P1 is not yet complete. No push or modification of main/Claude occurred.

### Revision-3 correctness checkpoint

The integrated B implementation passes the full Debug gate (**88/88 steps, 2,100 executed tests**), fmt, and qualification (**509 Core tests; conformance 1518/0/0 in both modes**). Frozen fuzz **9×50 and 9×200** passed with source/oracles unchanged and complete qualified matrices. Lox passes **246/246 VM and 241/241 tree** in both normal and stress runs, plus **65 port tests**. EDA passes **310 tests** and all **34 goldens**. All **45 parity arms** match expected outputs. All **132 counted/plain cells** have equal output and zero status: 48 Lox, 34 EDA, 4 parity, 46 row programs.

**Native fixture correction:** `zig cc -O2` defines `NDEBUG`, and the historical shared-count fixture put thread creation and validation inside `assert`. Those prior native contention/TSan claims are superseded. The fixture now explicitly enables assertions and reports **8 workers**; the rerun full gate passes **88/88 steps, 2,093 executed tests**, with the remaining seven tests cached. Its real contention and near-saturation checks passed. Final P1 will require fresh, asserted C and emitted-IR TSan evidence.

Raw logs, including failed attempts, are in [the P1-1 log archive](r3/p1-1-logs.tar.xz). [Qualification](r3/p1-1-qualify/), [fuzz 50](r3/fuzz-history.tar.xz), [fuzz 200](r3/fuzz-history.tar.xz), [counter JSON](raw/r3-counter-history.tar.xz) and [counted/plain summaries](results/r3-p1-1/) retain the underlying evidence. See [evidence storage and the lossless fuzz decoder](EVIDENCE.md). Archives retain paths relative to this package; counter members contain the original JSON bytes with their individual gzip layer removed. [Archive hashes](r3/evidence-archives.json) document the verified compression. Unpacked copies remain in this worktree's private cache.

### Revision-3 initial tax — selected B

Each cell uses the median of paired K=4,5,6 ratios, with CE-X's rounds and inputs, CPU 10 under `cpu10.lock`, and no own build jobs during timing. All output/checksum comparisons pass. The one-minute load range comes from all samples, including startup/warmups. EDA is close to the **1.03 hard-stop boundary** but below it; its result is not rounded into a pass. The target remains geomean ≤1.010 and every cell ≤1.03.

| corpus | cells | geomean | cells >1.03 | load range | detail |
|---|---:|---:|---:|---|---|
| rows | 92 | 1.001778 | 4 | 2.11–3.17 | [all cells / alignments](r3/results/p1-1-tax-rows.md) |
| EDA | 34 | 1.029827 | 19 | 3.08–29.25 | [all cells / alignments](r3/results/p1-1-tax-eda.md) |
| Lox, both engines | 26 | 1.016258 | 10 | 2.37–31.68 | [all cells / alignments](r3/results/p1-1-tax-lox.md) |
| Lox tree | 13 | 1.021800 | 4 | same run | same detail |
| Lox VM | 13 | 1.010745 | 6 | same run | same detail |
| parity | 45 | 0.999173 | 0 | 1.65–20.54 | [all cells / alignments](r3/results/p1-1-tax-parity.md) |

The row misses are `string_search/64` **1.044908**, `string_join/64` **1.295063**, `csv_aggregate/4096` **1.070642**, and `csv_aggregate/64` **1.082134**. Every table links to raw `.json.gz` samples in the same directory; these retain base and package wall times, all rounds, startup samples, load and binary hashes. The initial five-cell comparison and this full sweep are both retained; later measurements do not erase either.

### Revision-3 helper refinement — C selected

The emitted slow path remains the approved C alternative: a cold immortal check followed by one preserve-most call. Internally, `count_release_shared` also preserves registers, and a second preserve-most adapter isolates the ordinary C free call to the last shared owner. CAS loops, count memory order, and the plain path are unchanged. A new guest test joins immortal and allocated strings and verifies both output and leak-free destruction.

| comparison | B with refined helpers | C with refined helpers |
|---|---:|---:|
| R9 five-cell geomean | 1.023796 | **1.013078** |
| 92 row/size cells, geomean | 0.998804 | **0.996360** |
| row cells above 1.03 | 4 | 6 |
| `string_join/64` | 1.011527 | 0.996833 |
| EDA geomean | 1.015979 | **1.004482** |
| EDA cells above 1.03 | 1 | 0 |
| `json::read_value` bytes, K=4/5/6 | 8061/8061/8061 | 8472/8472/8472 |

[Every row, base/package time and alignment](r3/results/helper-tax-rows.md); [every EDA case](r3/results/helper-tax-eda.md); [compiler identities and sizes](r3/results/helper-variants.json); [build, native-test, full-gate and external logs](r3/helper-logs.tar.xz). C's remaining row misses are `list_append/64` 1.038567, `string_search/64` 1.040646, `csv_aggregate/4096` 1.037795, `csv_aggregate/64` 1.039146, `record_pass/4096` 1.051673 and `union_find/4096` 1.042637. These are checkpoint misses, not passes. [Pre-commit qualification](r3/C1-qualify/summary.json), [external status/times](r3/results/C1-external.json), [counted/plain summaries](results/r3-C1/), and [counter JSON](raw/r3-counter-history.tar.xz) retain this candidate's correctness evidence. The ReleaseFast compiler was built from the isolated C1 source archive before adoption; its implementation files match the adopted emitter/runtime (apart from a comment), and its binary hash is retained.

Committed qualification at `73737b94f` also passes **510 Core tests and 1518/0/0 in both modes**; [its source/compiler identity and logs](r3/C1-committed-qualify/summary.json) are retained separately from the pre-commit run. Frozen fuzz **9×50 and 9×200** passes with source/oracles unchanged. All historical and resumed fuzz runs are now in [one verified archive](r3/fuzz-history.tar.xz), with [member hashes](r3/fuzz-history-manifest.json.xz). Both resumed counter runs are in [one counter archive](raw/r3-counter-history.tar.xz), retaining original decoded JSON and paths. Earlier archive names in historical manifests refer to originals retained in the private cache; the replacement ledger names the current archives.

### Refined C: completed Lox and parity sweep

| corpus | cells | geomean | cells >1.03 | one-minute load range | detail |
|---|---:|---:|---:|---|---|
| Lox tree | 13 | 0.9972673812 | 0 | 0.35–2.59 | [all cells / alignments](r3/results/helper-tax-lox.md) |
| Lox VM | 13 | **1.0313247132** | 6 | same run | same detail |
| parity | 45 | 1.0001035352 | 0 | 0.78–1.30 | [all cells / alignments](r3/results/helper-tax-parity.md) |

The VM's per-alignment geomeans are **1.0301348688 / 1.0319328087 / 1.0359049233**. Its misses are closures 1.061041, equality 1.064152, fib 1.042783, invocation 1.048654, string_equality 1.040079 and strings 1.047803. All outputs pass. The combined-engine 1.014153 figure is retained in the raw summary but does not hide the separate VM failure. This is an open §9.1 premise investigation, not a passed checkpoint. The 958.29-second parity orchestration included waiting for another lane's CPU-10 lock; timing samples begin only after acquiring it.

P1-2 through P1-5 and P2-0 drafts remain in this worktree's ignored scratch directories, not the implementation. The latest native scheduler prototype passes an asserted eight-thread run with **1,010,000 simple submits, binary depth 12, a 2,048-level chain, zero live blocks and zero TSan reports**. This is preliminary C evidence, not the required final 100-repetition C/emitted-IR gate.

### Count-branch probability investigation — B2 selected

Count branches remain unlikely, but use 32:1 instead of 2000:1; allocator weights remain unchanged. Both approved paths share the refined runtime. [Five-cell comparison](r3/results/count-weight-five.md), [all Lox cells and alignments](r3/results/count-weight-lox.md), [compiler identities](r3/results/count-weight-identities.json) and [symbol sizes](r3/results/count-weight-sizes.json) retain the full comparison. B2 wins R9 at **1.0227152622**, versus C2 **1.0307566171**. JSON read_value is 8052 bytes at every alignment for B2 and 8466 for C2.

| arm | Lox tree | Lox VM | tree / VM cells >1.03 |
|---|---:|---:|---:|
| B1 control | 1.0127688215 | 1.0151924911 | 1 / 4 |
| **B2 selected** | **1.0140140429** | **1.0165376601** | **3 / 4** |
| C2 | 1.0201026497 | **1.0328550234** | 4 / 7 |

B2 resolves the premise failure under the mandated selection rule; target misses remain explicit. Its remaining corpus sweep is recorded below; its fresh correctness gates pass as recorded below.

### Selected B2: complete early tax checkpoint

| corpus | cells | geomean | cells >1.03 | one-minute load range | detail |
|---|---:|---:|---:|---|---|
| rows | 92 | 0.9990390412 | 5 | 2.21–5.19 | [all cells / alignments](r3/results/count-weight-rows.md) |
| eda | 34 | 1.0207970965 | 1 | 2.40–3.25 | [all cells / alignments](r3/results/count-weight-eda.md) |
| parity | 45 | 1.0005911305 | 0 | 1.16–2.40 | [all cells / alignments](r3/results/count-weight-parity.md) |

Lox’s separate engine results and complete table are immediately above. The five row misses are string_search/64 **1.056308**, string_join/64 **1.041056**, csv_aggregate/4096 **1.036686**, csv_aggregate/64 **1.090253** and json_transform/64 **1.030965**. EDA’s only cell above 1.03 is adf5901 **1.033970**. Parity has no misses. These are not rounded into passes.

The early investigation compared the original paths, internal register-preservation refinement, a direct B1 control and both paths at the revised branch probability. B2 resolves the broken-premise boundary while following the prescribed five-cell selection. Further tuning is deferred to the binding P1-6 check because TLS, publication and scheduling still change the same runtime. No correctness gate is waived; the adopted B2 checkpoint is pending.

The timing compiler’s implementation matches the adopted source: the experiment archive differs only in its alternate C2 emitter and an older test file; the saved B2 emitter hash matches this worktree exactly. [Build logs](r3/count-weight-logs.tar.xz) and all compiler/binary hashes remain available. [Prototype source/log snapshot](r3/prototypes-before-integration.tar.xz) retains the failed native TSan probe and successful follow-ups, as preliminary evidence only; it does not replace the final integrated gate.

## Historical P1-1 report (before revisions 2 and 3)

2026-10-08. **P1-1 is implemented; package P1 is not complete or qualified.**
The original early tax run passed the corpus geomean limit (0.998711×) but
failed the per-row limit: four of 92 row/size cells exceeded 1.03×, with
`json_transform/4096` at 1.040006×. Per §5 P1-1, implementation stopped before
P1-2. The required plain-load diagnostic is reported below; it does not replace
the original gate. TLS, the share walk, scheduler, task ABI bridge, internal
TSan build switch and P1-5 end-to-end suite remain unimplemented.

## 1. Branch, commits and what was built

| Item | Commit / status |
|---|---|
| Branch and worktree | `codex/concurrency-p1`, `/home/epentland/ai/canopy/mylang-concurrency-p1` |
| Original P1-0 inventory and report | `4673418f1`, `0034715e0`, retained by revision 1 |
| Requested fast-forward | `a633dbd5d5a3436ecb37e8d321db52b919baeca3` (`claude/concurrency-plan`) |
| CE2 integration on `main` | `12bf3f60b6fce5d11a8a9d04367c19002b66558e` |
| Real merge into P1, before implementation | `54eda9012525b7f3c15ef247a4a4082210578ece`; parents `a633dbd5d`, `12bf3f60b` |
| P1-1 implementation | `07b0b3dc3ed783f8191354666e8fcc0f041df4aa` |
| Comparison baseline | The merged resume base `54eda9012`, so CE2 changes do not contaminate the P1 tax comparison |

No merge into `main`, push, or Claude-worktree modification was performed.
The final evidence/report commit follows the implementation commit. The pinned
toolchain is Zig `0.17.0-dev.1683+5ceec001b`.

Implemented under `[SHARED-COUNTS-1]`:

- The plain/shared/immortal encoding, inline emitted thresholds, cold retain
  and release helpers, and common runtime count/uniqueness/cache helpers.
- LLVM `unordered` count loads with the original TBAA and `[1, 0)` range.
  Uniqueness comparisons stay `count == 1`; the free-list declaration is still
  an ordinary global. C count reads use relaxed atomics.
- All inventoried direct runtime RC sites and generated counting-runtime
  anchors moved to helpers. Child releases still use an iterative free walk.
  Shared text cannot acquire a lazy cache through these sites.
- Shared-retain/shared-release counters and reserved share-walk counter slots;
  share marks/bytes remain zero until P1-3. Counting state is not yet TLS.
- Boundary, immortal-constant, concurrent saturation, eight-thread count and
  100,000-level destruction tests; emitted-path checks; a typed source guard.
  The guard renames `myl_block.count` and only sanctioned access sites, then
  asks the C compiler to reject an unsanctioned access through an alias. It
  checks ordinary and generated counting sources without banning other
  structures' `count` fields. The existing RC emission test's load expectation
  was updated with the shared load template.

**Atomic implementation decision:** shared increments and decrements both use
compare-exchange loops, with relaxed retain, release decrement and an acquire
fence for the last owner. A sentinel check followed by unconditional
fetch-add/sub can race another thread's saturation, wrapping or decrementing
immortality. The CAS loops keep the immortal sentinel sticky; the contention
and near-saturation tests cover this decision. No plain-path atomic RMW was
added.

ReleaseFast compiler installs and SHA-256/source hashes are in
[evidence/p1-1-builds.json](evidence/p1-1-builds.json). The P1 compiler was
installed from the implementation sources before the commit; subsequent edits
before that commit affected tests only. The Debug compiler was qualified at
`07b0b3dc3`. All guest timing binaries use `--release`.

The plain-load diagnostic was built from an isolated source archive of
`07b0b3dc3` with only [plain-loads.patch.gz](evidence/plain-loads.patch.gz): the emitted
count load and C `count_load` return become plain reads. The encoding and
slow helpers remain identical. This is a single-thread diagnostic, not a safe
alternative for shared values; the branch retains the approved atomic reads.

## 2. Accepted P1-0 inventory and ABI findings

The following inventory is preserved from P1-0 at its original source lines.
Revision 1 §4.7 accepts it as the §4.3 design. Its table entries describe the
required final treatment, not completed P1 work. P1-1 implements the count
sites; the other treatments remain pending. R1 chooses unordered reads,
R2–R3 settle caches and fatal paths, R4–R5 settle the bridge and sites, and
R6–R8 settle allocator registration, providers and the source guard.

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

### ABI feasibility: historical finding, design decided by R4/R5

`test_builder.helper` declares `.runtime_c` helpers; `Builder.call` accepts
typed operands. Boxes and function values both emit as pointers. A generated
thunk can unbox arguments with `box_get`, call its target, then create an owned
result with **`box_make`** (the actual operation name, rather than `box_new`).
These building blocks do not suggest an `ir.zig` representation change.

P1-0 identified two details subsequently decided by revision 1 R4/R5:

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

P1-0 did not execute a hand-built task program before its original scope stop.
Revision 1 prescribes the bridge and return-address sites; their implementation
and end-to-end confirmation remain pending after this P1-1 tax stop.

## 3. Correctness gates

| Check | Result |
|---|---|
| `zig build test --summary all` | PASS, 88/88 steps; [retry log](r3/loose-logs.tar.xz) |
| `zig build fmt-check` | PASS, exit 0 after the full gate |
| `qualify_merge.py`, 64 Core shards | PASS, 505 tests; 32.68 s |
| Frozen full conformance with verification/leak checks | Debug 1518 matching / 0 mismatching / 0 unsupported; Release 1518/0/0; 23.16 s |
| Frozen fuzz 9×50 | PASS, all nine kinds, 450 accepted cases; [matrix](evidence/fuzz50.json), [full evidence archive](r3/fuzz-history.tar.xz) |
| Frozen fuzz 9×200 | PASS, all nine kinds, 1,800 accepted cases; [matrix](evidence/fuzz200.json), [full evidence archive](r3/fuzz-history.tar.xz) |
| Compiler/source identity during fuzz | Both matrices confirm unchanged source and oracle hashes |
| New shared-count tests | PASS, boundary/encoding, emitted paths and typed source guard; included in the full/Core gates |
| Current C count harness under TSan | PASS, one run with 8 workers, 0 reports, `shared counts ok`; [manifest](evidence/counts-tsan.json), [log](r3/loose-logs.tar.xz) |
| P1-0/R1 atomic-load probes | Historical evidence retained: monotonic and unordered each 100/100 without reports; ordinary load reproduced a race |
| Timing checksum agreement | All arms agree in every measured startup and timed sample |
| Counting output correctness | Existing counting tests pass in the full/Core gates; CE-X's complete ordinary/counting corpus comparison was not run |
| Guardian whole-tree implementation commit gate | PASS, all 88 checks; no waiver or snapshot relaxation |
| Lox conformance, EDA goldens/310 tests, parity expected outputs | NOT RUN: first-corpus early tax stop |
| Remaining EDA/Lox/parity tax corpora, TLS comparison | NOT RUN: first-corpus early tax stop, before P1-2 |
| P1-4 scheduler stress / 10⁶ submits | NOT IMPLEMENTED / NOT RUN |
| P1-5 generated thunks at 1/2/8 threads and 100 TSan repetitions | NOT IMPLEMENTED / NOT RUN; the C count harness is not a substitute |

[Qualification summary](qualify/summary.json) and
[full conformance log](r3/loose-logs.tar.xz) retain the commands and
results. The first full gate had two failures: an existing RC test expected
`load i32`, and the property-test timeout case failed its “not shrunk” text
assertion. The RC expectation was updated. The timeout test passed unchanged
on the complete retry (2.41 s versus 218.17 s initially); a standalone baseline
probe also produced the expected timeout. Its initial failure remains an
unexplained transient, not a claimed fixed runtime defect. Both full logs and
[the baseline probe](r3/loose-logs.tar.xz) are retained.

The first baseline archive build could not resolve the relative Guardian
dependency; linking the scratch sibling path to the existing Guardian checkout
resolved it. [The retry](r3/loose-logs.tar.xz) completed successfully.

Every build used `scripts/build-slot.sh`, with disk-backed temporary and cache
paths. The full gate and fuzz matrix did not overlap. Timing waited for this
lane's build/gate work to finish. Qualification's exclusive install waited
159.224 s for another lane before its measured 0.86 s build; no other lane's
process was stopped. [Build-speed notes](evidence/build-speed.json) record the
row-sweep admission costs. Guardian usage feedback is appended and committed
separately in `guardian-zig` at closeout.

## 4. Single-threaded tax and TLS comparison

The early gate compares the merged resume base against P1-1, with TLS still
plain. The CE-X row registry supplies all 46 programs, both sizes, iterations
and checksums. Each of three batches uses three one-iteration startup samples
and seven shuffled, interleaved rounds on CPU 10 under
`/run/user/1000/mylang-slots/cpu10.lock`. Wall time is the row's native
`CLOCK_MONOTONIC` measurement, with startup subtraction as in CE-X's cycle
normalization. Cycles and Python/perf process wall time are also retained as
diagnostics; perf-launch overhead is not allowed to dilute a short kernel's
tax. The protocol was fixed before timing.

See [timing protocol](evidence/timing-protocol.json),
[original raw samples](results/tax-rows.json.xz) and
[diagnostic raw samples](results/tax-rows-plain.json.xz), including binary
hashes and per-sample load. All corpora after the 46 rows are unmeasured because
this first corpus triggered the stop. The own EDA worktree is
`/home/epentland/ai/canopy/eda-bench-wt/codex-concurrency-p1` at `d45e0cd472d1`;
the prepared Lox copy is this worktree's `.mylang-cache/lox`. Neither is used to
claim external correctness or timing results.

### Original gate (binding stop)

Wall times are native CLOCK_MONOTONIC kernel times, with the median
one-iteration startup subtracted. Each time below is the median of
the three batch medians; each ratio is the median of the three
within-batch ratios. Consequently ratios need not equal the ratio
of the two displayed times.

| corpus / arm | cells | wall geomean vs base | cells >1.03 | verdict |
|---|---:|---:|---:|---|
| 46 rows / p1 | 92 | 0.998711 | 4 | FAIL |

CPU 10 under cpu10.lock. One-minute load across timed samples: 1.53–3.19.

| row | size | base ms | p1 ms | p1/base |
|---|---:|---:|---:|---:|
| record_reads | 4096 | 15.3431 | 15.3746 | 1.00142 |
| record_reads | 64 | 15.3048 | 15.3605 | 1.00364 |
| tagged_stack | 4096 | 29.3186 | 29.3703 | 1.00039 |
| tagged_stack | 64 | 29.4234 | 29.2754 | 0.99872 |
| mutate_unique | 4096 | 12.8734 | 12.8292 | 0.99656 |
| mutate_unique | 64 | 12.8941 | 12.8753 | 1.00230 |
| mutate_shared | 4096 | 0.2599 | 0.2556 | 0.97011 |
| mutate_shared | 64 | 0.2439 | 0.2474 | 1.01722 |
| record_construct | 4096 | 22.8154 | 23.0578 | 1.01062 |
| record_construct | 64 | 22.9941 | 22.9480 | 0.99726 |
| record_update | 4096 | 22.9662 | 23.2056 | 1.00326 |
| record_update | 64 | 23.7573 | 23.7521 | 0.99978 |
| option_handle | 4096 | 7.6091 | 7.6152 | 1.00380 |
| option_handle | 64 | 8.6347 | 8.6426 | 1.01429 |
| result_propagate | 4096 | 14.4260 | 14.5644 | 1.00721 |
| result_propagate | 64 | 13.7788 | 13.8417 | 0.99432 |
| list_scan | 4096 | 15.1744 | 15.0631 | 0.99549 |
| list_scan | 64 | 15.7072 | 15.4564 | 0.98403 |
| list_append | 4096 | 24.1508 | 24.6696 | 1.02148 |
| list_append | 64 | 24.9831 | 25.6212 | 1.02554 |
| list_filter | 4096 | 28.6299 | 28.8245 | 1.00788 |
| list_filter | 64 | 33.7592 | 33.5647 | 0.99424 |
| alloc_short | 4096 | 4.5067 | 4.5814 | 1.00204 |
| alloc_short | 64 | 4.6257 | 4.6343 | 1.00122 |
| alloc_retained | 4096 | 32.1438 | 31.9296 | 0.99171 |
| alloc_retained | 64 | 32.3954 | 32.5044 | 1.00341 |
| mutate_nested | 4096 | 4.7404 | 4.6492 | 0.99940 |
| mutate_nested | 64 | 5.6017 | 5.6107 | 0.99851 |
| bytes_scan | 4096 | 0.1969 | 0.1974 | 1.01915 |
| bytes_scan | 64 | 0.9118 | 0.9362 | 1.03434 |
| string_equal | 4096 | 2.3710 | 2.3567 | 0.99400 |
| string_equal | 64 | 0.6950 | 0.6833 | 0.96872 |
| string_search | 4096 | 4.0992 | 4.1030 | 1.00229 |
| string_search | 64 | 0.6413 | 0.6632 | 1.03401 |
| string_split | 4096 | 24.0596 | 23.7869 | 0.98866 |
| string_split | 64 | 25.6321 | 25.7190 | 1.00339 |
| string_join | 4096 | 4.3135 | 4.2550 | 0.99061 |
| string_join | 64 | 5.0222 | 5.1264 | 1.00698 |
| dict_lookup | 4096 | 57.8025 | 57.6759 | 0.99876 |
| dict_lookup | 64 | 56.6232 | 56.8577 | 1.00443 |
| dict_lookup_str | 4096 | 88.3080 | 84.8793 | 0.96271 |
| dict_lookup_str | 64 | 74.8585 | 73.8888 | 0.98705 |
| dict_update | 4096 | 228.8548 | 225.1271 | 0.98637 |
| dict_update | 64 | 175.4902 | 177.3997 | 1.00036 |
| dict_update_str | 4096 | 303.8593 | 308.8104 | 1.01629 |
| dict_update_str | 64 | 232.5027 | 235.1244 | 1.01128 |
| set_dedup | 4096 | 94.8390 | 94.8225 | 1.00406 |
| set_dedup | 64 | 111.2336 | 110.0485 | 0.98935 |
| int_parse | 4096 | 25.4366 | 26.1010 | 1.02876 |
| int_parse | 64 | 24.3168 | 24.1252 | 0.99212 |
| int_format | 4096 | 63.7959 | 63.3788 | 0.99550 |
| int_format | 64 | 58.7727 | 58.2485 | 0.99108 |
| call_indirect | 4096 | 1.1752 | 1.1613 | 0.99694 |
| call_indirect | 64 | 1.1732 | 1.2080 | 1.00683 |
| sort_int | 4096 | 16.7936 | 16.8407 | 1.00276 |
| sort_int | 64 | 3.5796 | 3.5398 | 0.99082 |
| sort_records | 4096 | 11.7794 | 11.7469 | 0.99718 |
| sort_records | 64 | 15.3891 | 14.7682 | 0.95966 |
| int_math | 4096 | 1.3705 | 1.3870 | 1.00653 |
| int_math | 64 | 1.8661 | 1.8438 | 0.99400 |
| float_math | 4096 | 5.7500 | 5.8200 | 1.00178 |
| float_math | 64 | 6.2957 | 6.3226 | 1.00021 |
| call_direct | 4096 | 1.2051 | 1.1834 | 1.00947 |
| call_direct | 64 | 1.2270 | 1.2161 | 0.99796 |
| branch_predictable | 4096 | 1.5476 | 1.5470 | 0.99342 |
| branch_predictable | 64 | 1.8774 | 1.8834 | 1.00190 |
| branch_mixed | 4096 | 1.5467 | 1.5289 | 0.98924 |
| branch_mixed | 64 | 1.8862 | 1.8902 | 0.99736 |
| binary_search | 4096 | 11.7774 | 11.1965 | 0.95275 |
| binary_search | 64 | 6.8839 | 6.8204 | 0.99816 |
| word_count | 4096 | 13.3966 | 12.9090 | 0.96230 |
| word_count | 64 | 17.9932 | 17.9283 | 0.99023 |
| csv_aggregate | 4096 | 44.1378 | 44.1674 | 1.00067 |
| csv_aggregate | 64 | 40.5859 | 41.1675 | 1.01273 |
| json_transform | 4096 | 51.5794 | 53.6428 | 1.04001 |
| json_transform | 64 | 53.6671 | 55.4151 | 1.03265 |
| packet_decode | 4096 | 5.8236 | 5.6596 | 0.97631 |
| packet_decode | 64 | 5.6247 | 5.5327 | 0.99312 |
| lox_eval | 4096 | 8.0783 | 8.1261 | 0.99820 |
| lox_eval | 64 | 8.1371 | 8.1830 | 1.00044 |
| tree_build_walk | 4096 | 18.6150 | 17.8077 | 0.96210 |
| tree_build_walk | 64 | 13.7837 | 12.9511 | 0.95502 |
| record_pass | 4096 | 10.8854 | 10.9605 | 0.99659 |
| record_pass | 64 | 13.3038 | 13.1020 | 1.00302 |
| grid_dp | 4096 | 21.4872 | 21.5960 | 1.00437 |
| grid_dp | 64 | 17.7335 | 17.6621 | 0.99597 |
| union_find | 4096 | 29.4788 | 29.4495 | 0.99901 |
| union_find | 64 | 16.5631 | 16.5765 | 1.01305 |
| float_format | 4096 | 10.7724 | 10.8736 | 1.00940 |
| float_format | 64 | 12.1163 | 12.1258 | 0.99893 |
| buffer_write | 4096 | 12.6719 | 12.7230 | 1.00235 |
| buffer_write | 64 | 14.3582 | 14.2679 | 0.99371 |

### Required plain-load diagnostic

This is a fresh three-arm, three-batch comparison with the same protocol and
prebuilt baseline/P1 binaries. The original failed gate remains binding.

| comparison | geomean | cells over 1.03 | worst cell |
|---|---:|---:|---|
| p1 / base | 0.998008 | 2 | `json_transform/4096` 1.039446× |
| plain / base | 0.999325 | 3 | `binary_search/4096` 1.052164× |

With plain reads, `json_transform/4096` is still 1.031421×; `mutate_shared/64`
and `binary_search/4096` also exceed the row limit. The unordered repeat's two
JSON cells remain over the limit. The original small byte/string-search misses
do not recur in the unordered repeat, which shows why all batches and both
runs are retained. Plain reads improve this JSON cell in the diagnostic
(1.039446× to 1.031421×), but do not make the encoding pass. This experiment
separates builds with and without atomic read semantics; code-layout effects
mean their differences are not a universal additive “atomic instruction tax.”

No initial-exec/local-exec comparison was made: that is P1-2, beyond the stop.
EDA, Lox and parity remain unmeasured. The following table gives all diagnostic
row medians as well as the corpus summary.

Wall times are native CLOCK_MONOTONIC kernel times, with the median
one-iteration startup subtracted. Each time below is the median of
the three batch medians; each ratio is the median of the three
within-batch ratios. Consequently ratios need not equal the ratio
of the two displayed times.

| corpus / arm | cells | wall geomean vs base | cells >1.03 | verdict |
|---|---:|---:|---:|---|
| 46 rows / p1 | 92 | 0.998008 | 2 | FAIL |
| 46 rows / plain | 92 | 0.999325 | 3 | FAIL |

CPU 10 under cpu10.lock. One-minute load across timed samples: 0.99–1.38.

| row | size | base ms | p1 ms | plain ms | p1/base | plain/base |
|---|---:|---:|---:|---:|---:|---:|
| record_reads | 4096 | 15.3572 | 15.3579 | 15.3448 | 1.00005 | 0.99766 |
| record_reads | 64 | 15.2361 | 15.2773 | 15.2714 | 1.00182 | 1.00164 |
| tagged_stack | 4096 | 29.5100 | 29.3910 | 29.7065 | 0.99803 | 1.00045 |
| tagged_stack | 64 | 29.2797 | 29.2602 | 29.2209 | 0.99933 | 0.99927 |
| mutate_unique | 4096 | 12.8116 | 12.8297 | 12.8327 | 0.99914 | 1.00165 |
| mutate_unique | 64 | 12.7993 | 12.8144 | 12.8180 | 1.00118 | 1.00146 |
| mutate_shared | 4096 | 0.2538 | 0.2536 | 0.2476 | 1.00144 | 0.97562 |
| mutate_shared | 64 | 0.2336 | 0.2405 | 0.2394 | 1.02190 | 1.04887 |
| record_construct | 4096 | 22.8288 | 22.7489 | 22.8688 | 1.00200 | 1.00175 |
| record_construct | 64 | 22.8252 | 22.7750 | 22.6938 | 0.99558 | 0.99634 |
| record_update | 4096 | 22.5803 | 22.5812 | 22.5903 | 1.00197 | 0.99966 |
| record_update | 64 | 23.5260 | 23.5193 | 23.5012 | 0.99971 | 0.99895 |
| option_handle | 4096 | 7.4609 | 7.4304 | 7.5582 | 0.99989 | 1.00937 |
| option_handle | 64 | 8.6886 | 8.7127 | 9.1482 | 1.00278 | 1.02233 |
| result_propagate | 4096 | 14.3158 | 14.2557 | 14.3962 | 0.99440 | 0.99329 |
| result_propagate | 64 | 13.6073 | 13.4928 | 13.5773 | 0.99158 | 1.00076 |
| list_scan | 4096 | 15.0919 | 14.9967 | 15.0284 | 0.99452 | 0.99579 |
| list_scan | 64 | 15.3315 | 15.0650 | 15.0596 | 0.98222 | 0.97535 |
| list_append | 4096 | 23.6761 | 24.1743 | 24.5058 | 1.02104 | 1.02000 |
| list_append | 64 | 24.7671 | 25.2548 | 25.2198 | 1.02121 | 1.01259 |
| list_filter | 4096 | 28.4751 | 28.7034 | 28.7396 | 1.00479 | 1.00929 |
| list_filter | 64 | 33.3860 | 33.1977 | 33.1209 | 0.99566 | 0.99206 |
| alloc_short | 4096 | 4.4805 | 4.5124 | 4.4613 | 1.00711 | 0.99884 |
| alloc_short | 64 | 4.5698 | 4.5801 | 4.5018 | 1.00245 | 0.99365 |
| alloc_retained | 4096 | 31.7726 | 31.3620 | 31.0180 | 0.98973 | 0.97625 |
| alloc_retained | 64 | 32.2727 | 32.2839 | 32.5037 | 1.00542 | 1.00175 |
| mutate_nested | 4096 | 4.6899 | 4.6226 | 4.6256 | 0.98565 | 0.99679 |
| mutate_nested | 64 | 5.5645 | 5.5446 | 5.5721 | 0.99629 | 1.00136 |
| bytes_scan | 4096 | 0.1978 | 0.1990 | 0.1993 | 1.00851 | 1.00752 |
| bytes_scan | 64 | 0.9105 | 0.9195 | 0.9224 | 1.00897 | 1.00907 |
| string_equal | 4096 | 2.3275 | 2.3422 | 2.3432 | 1.00316 | 1.01191 |
| string_equal | 64 | 0.6996 | 0.6816 | 0.6949 | 0.97614 | 0.97953 |
| string_search | 4096 | 4.0780 | 4.0796 | 4.0723 | 1.00229 | 1.00134 |
| string_search | 64 | 0.6411 | 0.6569 | 0.6354 | 1.02466 | 0.98868 |
| string_split | 4096 | 23.7637 | 23.5881 | 23.4912 | 0.99243 | 0.99165 |
| string_split | 64 | 25.3448 | 25.5082 | 25.3773 | 1.00323 | 1.00128 |
| string_join | 4096 | 4.2645 | 4.2649 | 4.2083 | 1.00010 | 0.99533 |
| string_join | 64 | 5.0289 | 5.1176 | 5.0417 | 1.01625 | 1.00117 |
| dict_lookup | 4096 | 57.1483 | 57.5280 | 57.2611 | 0.99667 | 0.99753 |
| dict_lookup | 64 | 56.4308 | 56.6477 | 56.5032 | 1.00434 | 1.00352 |
| dict_lookup_str | 4096 | 87.8588 | 84.1314 | 84.3173 | 0.95757 | 0.95804 |
| dict_lookup_str | 64 | 74.1491 | 73.1232 | 73.2050 | 0.98617 | 0.98727 |
| dict_update | 4096 | 227.5582 | 223.7155 | 224.2488 | 0.98568 | 0.98546 |
| dict_update | 64 | 172.5030 | 172.2616 | 173.2704 | 0.99166 | 0.98794 |
| dict_update_str | 4096 | 302.2579 | 308.4339 | 308.0452 | 1.02046 | 1.01918 |
| dict_update_str | 64 | 230.0825 | 233.1112 | 233.0661 | 1.01156 | 1.02166 |
| set_dedup | 4096 | 94.0158 | 94.4518 | 94.6772 | 1.00323 | 1.00584 |
| set_dedup | 64 | 110.1884 | 108.7890 | 109.4691 | 0.98906 | 0.99471 |
| int_parse | 4096 | 25.0849 | 25.7596 | 25.4586 | 1.02689 | 1.01619 |
| int_parse | 64 | 23.6937 | 23.6982 | 23.6676 | 0.99880 | 0.99890 |
| int_format | 4096 | 63.5779 | 63.3581 | 63.2388 | 0.99660 | 0.99766 |
| int_format | 64 | 58.4454 | 57.9046 | 58.0461 | 0.99258 | 0.99242 |
| call_indirect | 4096 | 1.1609 | 1.1704 | 1.1596 | 1.00418 | 0.99719 |
| call_indirect | 64 | 1.1994 | 1.1939 | 1.1929 | 0.99742 | 0.99484 |
| sort_int | 4096 | 16.7671 | 16.7931 | 17.0819 | 1.00155 | 1.01921 |
| sort_int | 64 | 3.6370 | 3.6811 | 3.6284 | 0.99144 | 0.98771 |
| sort_records | 4096 | 11.7021 | 11.6708 | 11.7542 | 0.99465 | 1.00177 |
| sort_records | 64 | 15.3226 | 14.5933 | 14.9007 | 0.95138 | 0.97360 |
| int_math | 4096 | 1.3566 | 1.3673 | 1.3725 | 1.01154 | 1.01009 |
| int_math | 64 | 1.8404 | 1.8494 | 1.8581 | 1.00602 | 1.00963 |
| float_math | 4096 | 5.6898 | 5.7660 | 5.7221 | 1.00617 | 1.00161 |
| float_math | 64 | 6.2087 | 6.2831 | 6.2943 | 1.00456 | 1.01378 |
| call_direct | 4096 | 1.1551 | 1.1510 | 1.1575 | 0.99861 | 1.00754 |
| call_direct | 64 | 1.2001 | 1.2036 | 1.2112 | 1.00141 | 0.99989 |
| branch_predictable | 4096 | 1.5140 | 1.5065 | 1.5071 | 0.99505 | 0.99103 |
| branch_predictable | 64 | 1.8774 | 1.8522 | 1.8546 | 0.98460 | 0.99319 |
| branch_mixed | 4096 | 1.5144 | 1.5145 | 1.5213 | 0.99581 | 1.00465 |
| branch_mixed | 64 | 1.8550 | 1.8441 | 1.8560 | 0.99410 | 1.00037 |
| binary_search | 4096 | 11.7528 | 11.1390 | 12.3659 | 0.94778 | 1.05216 |
| binary_search | 64 | 6.8010 | 6.7752 | 6.6668 | 0.99408 | 0.98436 |
| word_count | 4096 | 13.3146 | 12.9130 | 13.1353 | 0.96756 | 0.98905 |
| word_count | 64 | 17.9406 | 17.5357 | 17.8149 | 0.98672 | 0.99294 |
| csv_aggregate | 4096 | 42.9372 | 43.0755 | 43.3966 | 0.99563 | 1.00958 |
| csv_aggregate | 64 | 39.6432 | 40.0005 | 40.3727 | 1.00044 | 1.01820 |
| json_transform | 4096 | 50.1055 | 51.9504 | 51.6514 | 1.03945 | 1.03142 |
| json_transform | 64 | 51.7691 | 53.4349 | 52.8123 | 1.03218 | 1.02535 |
| packet_decode | 4096 | 5.6570 | 5.5600 | 5.4996 | 1.01178 | 0.97918 |
| packet_decode | 64 | 5.4960 | 5.4427 | 5.3393 | 0.99031 | 0.98998 |
| lox_eval | 4096 | 8.0027 | 8.0117 | 7.9916 | 0.99705 | 0.99087 |
| lox_eval | 64 | 8.1253 | 8.1160 | 8.1101 | 0.99962 | 1.00126 |
| tree_build_walk | 4096 | 18.1011 | 17.3659 | 17.1118 | 0.95747 | 0.94535 |
| tree_build_walk | 64 | 13.3127 | 12.7087 | 12.6660 | 0.95359 | 0.94833 |
| record_pass | 4096 | 10.7942 | 10.7246 | 10.7070 | 0.99824 | 0.99908 |
| record_pass | 64 | 12.8806 | 12.8699 | 12.8870 | 1.00422 | 1.00592 |
| grid_dp | 4096 | 21.2411 | 21.2709 | 21.3185 | 1.00140 | 1.00660 |
| grid_dp | 64 | 17.3884 | 17.2774 | 17.7583 | 1.00164 | 1.01716 |
| union_find | 4096 | 29.0391 | 29.0184 | 29.1645 | 0.99929 | 1.00179 |
| union_find | 64 | 16.2874 | 16.3860 | 16.5586 | 1.00356 | 1.00821 |
| float_format | 4096 | 10.7138 | 10.7178 | 10.5777 | 1.00138 | 0.98477 |
| float_format | 64 | 12.0709 | 12.0242 | 11.9246 | 0.99243 | 0.99009 |
| buffer_write | 4096 | 11.9105 | 11.9232 | 11.9114 | 1.00024 | 1.00007 |
| buffer_write | 64 | 13.4728 | 13.4378 | 13.3871 | 0.99909 | 0.99558 |

## 5. Surprises and information for a later phase

- The corpus geomean passes while local regressions breach the required row
  limit. Aggregate “zero tax” is insufficient under this plan's acceptance
  rule. Preserve the original result rather than replacing it with a
  diagnostic repeat.
- `json_transform/4096` exceeded 1.03 in all three original batches:
  1.0400, 1.0388 and 1.0446. Its small-size cell also exceeded 1.03 in
  all three. `bytes_scan/64` was noisier (1.0491, 1.0343, 0.9964).
- `json::read_value` grew from 7,068 bytes in the baseline to 8,160 with P1,
  and remains 8,155 bytes with plain reads. The encoding/dispatch changes
  materially alter code size/layout even when both load forms lower to normal
  machine loads. [Symbol sizes](evidence/json-symbols.json) and the three
  `json-read-value-*.asm` files are retained. This is an investigation lead,
  not proof that code size alone explains the measured difference.
- Preserve sticky saturation when revisiting the slow helpers: blind atomic
  increments/decrements after a sentinel check are not sufficient.
- The revision-1 choices on the thread-local allocator registry, cache policy,
  bounded fatal path, provider operations, thunk bridge and source sites remain
  prerequisites for the rest of P1. They were not implemented or disproved by
  this count-only stage. A plain-load performance control cannot replace the
  approved atomic reads in a concurrent runtime.
- The accepted historical AST inventory is retained. Its pinned `zig cc`
  AST-only wrapper returned `FileNotFound` after producing the complete AST;
  the separate object compile passed. That historical tooling quirk is not a
  current compilation failure.

P1-2 and later steps, P2 and phase 2 were not started. No user-facing parallel
surface was added. Text logs and disassembly have trailing whitespace normalized for review;
[raw-text.tar.gz](raw-text.tar.gz) retains their exact original bytes.
Evidence archives contain the full fuzz commands, sources
and outcomes; compiled executables, source archives, caches and redundant
uncompressed evidence remain outside the package directory. The retained
package evidence is below 10 MB.

## Reproduction

Use the committed `07b0b3dc3` sources for P1-1 and `54eda9012` for the merged
baseline. Build ReleaseFast compiler installs through `scripts/build-slot.sh`
with separate on-disk caches, then build the row arms:

```sh
python3 experiments/concurrency-p1-2026-10-08/tools/tax_rows.py build --compiler BASE_COMPILER --tag base
python3 experiments/concurrency-p1-2026-10-08/tools/tax_rows.py build --compiler P1_COMPILER --tag p1
python3 experiments/concurrency-p1-2026-10-08/tools/tax_rows.py measure --tags base,p1 --output NEW_EVIDENCE.json
```

For the diagnostic, decompress and apply `evidence/plain-loads.patch.gz` to a separate P1-1 source
archive, install that ReleaseFast compiler, build `--tag plain`, then measure
`--tags base,p1,plain`. `tax_rows.py` wraps guest builds with the shared build
slot and takes CPU 10's lock for timing. Set TMPDIR and Zig caches to disk paths
as in the retained build/gate logs; wait for this lane's gates and builds before
timing. Render either raw JSON/gzip file using `tools/tax_table.py`.

The qualification and fuzz archives retain exact commands. Their `--evidence`
arguments must name new directories on reproduction. P1-0's inventory and
count-reader scripts describe their historical source snapshot; reproduce
those original probes at the P1-0 commit, not by assuming their old plain-load
assertion still describes P1-1.

### Selected B2: fresh correctness complete

At `9c2559a45`, the full Debug gate passes **88/88 steps and 2,101 tests**, with fmt green. [Qualification](r3/B2-committed-qualify/summary.json) passes **510 Core tests and conformance 1518/0/0 in both modes**. Both frozen matrices, **9×50 and 9×200**, report complete, qualified, source unchanged and oracles unchanged; their original case outputs and summaries are in [the verified fuzz archive](r3/fuzz-history.tar.xz), under `r3/B2-fuzz50` and `r3/B2-fuzz200`. [Checkpoint commands and timings](r3/B2-gates/resumed-summary.json) are retained; associated logs use `.log.gz` after lossless compression.

[External gates](r3/results/B2-external.json) pass: Lox **246 VM / 241 tree** in normal and stress modes and **65 port tests**; EDA **310 tests / 34 goldens**. All **132 counted/plain cells** match (48 Lox, 34 EDA, 4 parity, 46 rows), with zero statuses and valid counters. [Counter summaries](results/r3-B2/) and [original decoded JSON](raw/r3-counter-history.tar.xz) retain the evidence. The complete tax run also validates all **45 parity arms**. This closes P1-1's required correctness checkpoint.

The first qualification launch failed before compilation because the generic evidence basename collided with an older private cache directory. Its failed log is retained in `r3/B2-gates/qualify.log.gz`; the successful retry used the unique `B2-committed-qualify` name. The checkpoint helper now uses a tag-specific qualification name and explicitly binds fuzz to the recorded committed HEAD. Long prototype/port-test waits were shared-slot admission, not slow test execution; no other lane was interrupted.

### P1-2: per-thread runtime integrated

The allocator, error/site state, stacks and counting records now use TLS; shared accounting is atomic, provider operations serialize, and output commits complete units. Retired-thread allocator records remain valid for quiescent leak/text reports. Fatal fixtures cover one-winner behavior, held IO/stream locks and worker stack overflow; normal fixtures cover eight workers, cross-thread frees, exact counts and large output units. Dynamic print boundaries are emitted by `src/core/build_cap.zig`; native pthread flags are in `src/core/driver.zig`.

Validation: **18/18 focused tests**, full Debug **88/88 steps succeeded; 2107/21680 tests passed (19573 skipped)**, and **fmt passed**. [Focused evidence](r3/loose-logs.tar.xz), [full gate](r3/loose-logs.tar.xz), [fmt](r3/loose-logs.tar.xz). TLS-model timing remains pending; final package gates will cover the later scheduler integration.

### P1-3: shared child traversal integrated

Publication and destruction now enumerate the same managed edges, including dictionary tombstones, guarded payloads, view owners and provider pairs. The iterative walk marks before enqueueing children, preserves alias ownership multiplicity, and stops at shared/immortal nodes. Plain saturation first publishes descendants before making the root immortal.

The focused matrix passes **14/14 tests**, including the independent child/ownership differential, a **100,000-level** graph, exact **100,033** share marks, and the eight-thread saturation boundary (**2 marks / 128 bytes**). Existing count/source-guard/counting checks also pass, as does fmt. [Focused evidence](r3/loose-logs.tar.xz), [fmt](r3/loose-logs.tar.xz).

P1-3’s whole-tree commit check caught an unused future export and missing fixture environment cleanup. Both were fixed without exemptions; the affected two tests and fmt passed again. [Failure](r3/loose-logs.tar.xz), [rerun](r3/loose-logs.tar.xz).

### P1-4: lazy work-stealing scheduler integrated

The runtime now supports groups, submit/result, helping waits, range chunk counts and lazy N−1 worker creation. Chase–Lev queues use round-robin stealing and futex parking. Group ownership preserves task/result lifetimes; global quiescence precedes leak/text/count reports. Batch parents cannot start workers, and worker processes cannot fork trials. Every emitted unit supplies the retained C-to-fastcc bridge; generated range thunks can update their exact current item.

[Focused tests](r3/loose-logs.tar.xz) and [fmt](r3/loose-logs.tar.xz) pass. The scheduler matrix runs at **1, 2 and 8 threads**, with **1,010,000 submits**, binary depth **12**, chain depth **2,048**, own-deque waits, lazy/budget modes, post-close result ownership and fork guards. The retained share/thread/count tests also pass. TSan repetitions and actual emitted-code proof remain P1-5 work.

The P1-4 commit check also required the scheduler matrix to receive its allocator from the test body. That was corrected; the complete scheduler matrix passed again. The same review correction was applied to the forthcoming IR matrix helpers.

### P1-5: emitted-code integration checkpoint

The internal sanitizer switch instruments every emitted LLVM definition, native runtime and linked C source, with separate cache identities. The hand-built IR proofs exercise lists, records, dictionaries, allocated strings and nested lists; mutate a parent after submission; read results twice; and gather range results in input order. Error tests resolve captured PCs, preserve the required unknown-site fallback and report the exact current map item.

The integrated matrix passes **11/11 tests**, including Debug and counted/verified ownership at **1/2/8 threads**, actual LLVM ThreadSanitizer captures/ranges, native million-submit ThreadSanitizer, and ordinary/sanitized/ordinary cache separation. Fmt passes. [Initial run](r3/loose-logs.tar.xz), [post-review run](r3/loose-logs.tar.xz), [fmt](r3/loose-logs.tar.xz). **The required 100 repetitions at eight threads are still pending**, as are final package gates/tax.

### P1-2: TLS comparison complete — local-exec selected

| model | cells | GM/base | cells >1.03 | target |
|---|---:|---:|---:|---|
| initial-exec | 92 | 1.0150306005 | 20 | MISS |
| **local-exec** | 92 | **1.0124433780** | 18 | MISS |

Direct paired LE/IE GM: **0.9979028166**. Load: **0.47–1.98**. [Every cell, base/package time and K=4/5/6 ratio](r3/results/tls-rows.md), [raw samples](r3/results/tls-rows.json.xz), [compiler identities](r3/results/tls-identities.json), [source equivalence](r3/results/tls-source-equivalence.json). Source is P1-2 commit `9d2524f5e`; later steps were integrated separately while these immutable archives built. Both variants preserve outputs. Local-exec is now selected in C and both emitters. This does not claim the final package tax passes: P1-6 is binding.


Local-exec integration passes **15/15 focused tests** and fmt ([tests](r3/loose-logs.tar.xz), [fmt](r3/loose-logs.tar.xz)). The [whole-package review](SELF-REVIEW.md) is complete, with a [fresh typed inventory](r3/final-inventory/inventory.json) of **128 static declarations / 8 managed count-access lines**. [P2-0](P2-0.md) records the successful existing-IR lowering proof and future checker/builder work. Final qualification, 100-repetition TSan and binding tax remain outstanding.


### P1-6: final correctness complete before binding timing

The first final full gate (`P1-final-01`) failed two old native C harness links because no LLVM unit supplied the task bridge; `98cb3a49f` adds their explicit C adapters and successful compile/run checks. The fresh `P1-final-02` checkpoint passes full Debug, fmt, qualification and both frozen matrices. All nine families are complete/qualified with unchanged source and oracle hashes. The ReleaseFast compiler built at `f4eb26606` is production-source-identical to the test-only fixture fix; [source equivalence](r3/results/final-compiler-source-equivalence.json) records all 577 identical source hashes.

[P1-final-02 checkpoint](r3/P1-final-02/summary.json), [qualification](r3/P1-final-02/P1-final-02-qualify/summary.json), [external checks](r3/results/P1-final-01-external.json), and [sanitizer repetition manifest](r3/P1-final-02-tsan/summary.json) identify exact commits, commands, binaries and results. The [300 recorded outcomes](r3/P1-final-02-tsan/repetitions.jsonl.gz) preserve each status, stdout, stderr and duration without retries or suppressions. Native stress executes 1,010,000 simple submits plus nested/own-deque waits in every repetition. All outputs match their exact one-thread expectations.


### P1-6 initial binding sweep — investigation required

The source is `98cb3a49f`, using the production-identical f4eb26606 ReleaseFast compiler and matching base/candidate K=4/5/6 binaries. All completed cells have matching outputs/checksums, CPU 10 locked, and no own concurrent builds or stress. Lox is complete, with separate tree/VM verdicts. These misses remain evidence even if an improved candidate is later selected.

| corpus | cells | geomean | cells >1.03 | one-minute load | all cells / alignments |
|---|---:|---:|---:|---|---|
| rows | 92 | 1.0246636851 | 25 | 1.34–4.41 | [table](r3/results/P1-final-01-tax-rows.md) |
| EDA | 34 | 1.0269590951 | 11 | 1.11–1.34 | [table](r3/results/P1-final-01-tax-eda.md) |
| parity | 45 | 1.0291120904 | 8 | 0.99–1.25 | [table](r3/results/P1-final-01-tax-parity.md) |
| Lox tree | 13 | 1.0137666153 | 3 | 0.95–1.16 | [table](r3/results/P1-final-01-tax-lox.md) |
| Lox VM | 13 | 1.0063016225 | 1 | same run | [table](r3/results/P1-final-01-tax-lox.md) |

The largest retained misses include allocation-retained 1.242857/1.224735, string split 1.205813/1.199199, parity record sorting 1.282263 and parity binary-tree arms 1.205–1.216. The first private candidates inline the common child enumeration (A), or also inline the TLS registration check with a cold initializer and avoid locked live-count RMW before worker publication (B). Both retain atomic live storage and identical parallel accounting. No candidate is adopted before all-corpus comparison and subsequent correctness qualification.


### P1-6 A/B investigation — allocation gains, dictionary-inlining regression

Both private runtime candidates pass all 20 focused tests. All keep the B2 emitted-count path. A forces common/dictionary child traversal and the release visitor inline; B also uses inline registration checks with a cold initializer and cheaper pre-pool atomic accounting. Their exact source patches and compiler identities are retained in `r3/candidates/` and `r3/results/P1-final-candidates.json`. Neither is adopted: EDA exceeds 1.03 in both arms. The Lox sweep is complete; both engines are reported separately.

| corpus | A geomean | A cells >1.03 | B geomean | B cells >1.03 | one-minute load | all cells / alignments |
|---|---:|---:|---:|---:|---|---|
| rows | 1.0146208208 | 20 | 1.0065124883 | 16 | 1.03–1.31 | [table](r3/results/P1-final-AB-tax-rows.md) |
| eda | 1.0625164386 | 34 | 1.0315034862 | 21 | 1.01–1.31 | [table](r3/results/P1-final-AB-tax-eda.md) |
| parity | 1.0187897081 | 7 | 1.0079163950 | 4 | 0.96–1.24 | [table](r3/results/P1-final-AB-tax-parity.md) |
| Lox tree | 1.0180553953 | 2 | 1.0167185440 | 2 | 0.97–1.18 | [table](r3/results/P1-final-AB-tax-lox.md) |
| Lox vm | 1.0044192526 | 1 | 1.0003576986 | 1 | 0.97–1.18 | [table](r3/results/P1-final-AB-tax-lox.md) |

Candidate C keeps B’s allocation changes and generic/release inlining with ordinary dictionary traversal; D keeps B’s allocation changes with the original traversal structure. Both passed all 20 focused tests, built their ReleaseFast compilers and every benchmark, and are running the full matching-layout comparison. All failed cells and raw samples are retained.



### P1-6 C/D investigation — complete matching-layout sweep

The private source identities and exact patches are retained in `r3/results/P1-final-CD-candidates.json` and `r3/candidates/`. Every output/checksum passes. CPU 10 was locked; no own builds or stress overlapped timing. All three paired K=4/5/6 ratios and raw samples remain available, including failures. These candidates do not change the B2 emitted count path.

| corpus | C geomean | C cells >1.03 | D geomean | D cells >1.03 | one-minute load | all cells / alignments |
|---|---:|---:|---:|---:|---|---|
| rows | 1.0027158207 | 12 | 1.0124092025 | 17 | 1.07–1.55 | [table](r3/results/P1-final-CD-tax-rows.md) |
| eda | 1.0190069662 | 0 | 1.0013986091 | 0 | 1.07–1.19 | [table](r3/results/P1-final-CD-tax-eda.md) |
| parity | 1.0035887383 | 1 | 1.0147620501 | 7 | 0.99–1.08 | [table](r3/results/P1-final-CD-tax-parity.md) |
| Lox tree | 1.0145199288 | 2 | 1.0062901883 | 1 | 1.00–1.20 | [table](r3/results/P1-final-CD-tax-lox.md) |
| Lox vm | 1.0024991900 | 0 | 1.0037479335 | 0 | 1.00–1.20 | [table](r3/results/P1-final-CD-tax-lox.md) |

C improves rows and parity, while D gives the best EDA and tree-walk results in this sweep. Both pass the Lox VM target; no candidate corpus crosses the 1.03 premise boundary. The remaining misses motivate the final E/F registration-hoisting comparison, including the counting-hook anchor update recorded in DECISIONS.md. No production change has yet been adopted.


### P1-6 E/F investigation — complete matching-layout sweep

The private source identities and exact patches are retained in `r3/results/P1-final-EF-candidates.json` and `r3/candidates/`. Every output/checksum passes. CPU 10 was locked; no own builds or stress overlapped timing. All three paired K=4/5/6 ratios and raw samples remain available, including failures. These candidates do not change the B2 emitted count path.

| corpus | E geomean | E cells >1.03 | F geomean | F cells >1.03 | one-minute load | all cells / alignments |
|---|---:|---:|---:|---:|---|---|
| rows | 1.0150209161 | 19 | 1.0006356946 | 8 | 1.04–1.75 | [table](r3/results/P1-final-EF-tax-rows.md) |
| eda | 0.9965783262 | 0 | 1.0302100374 | 16 | 1.04–1.12 | [table](r3/results/P1-final-EF-tax-eda.md) |
| parity | 1.0132406980 | 7 | 1.0036991700 | 0 | 1.01–1.11 | [table](r3/results/P1-final-EF-tax-parity.md) |
| Lox tree | 1.0063927105 | 1 | 1.0142948885 | 3 | 1.00–1.39 | [table](r3/results/P1-final-EF-tax-lox.md) |
| Lox vm | 1.0030616825 | 0 | 1.0064462021 | 0 | 1.00–1.39 | [table](r3/results/P1-final-EF-tax-lox.md) |

E's registration hoist retains D's general tradeoff: EDA and Lox VM pass, but row and parity misses remain. F passes parity and Lox VM and reduces the row misses to eight, but its EDA geomean is 1.0302100374, above the premise boundary; F is not eligible for adoption. Its complete failure table remains. G is the single final follow-up: force the small already-registered free helper inline, retaining F's other behavior and its exact counter hook. It is tested and measured before selecting from the eligible candidates.
