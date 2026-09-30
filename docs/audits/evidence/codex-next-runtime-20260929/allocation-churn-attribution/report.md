# Frozen LLVM alloc_churn instruction attribution

Read-only profiling of the rejected composed source `7f5068a54946bcbe0cf1f7e20abf844f120046cd` against the accepted A5 `m17-codex` binary, 2026-09-30. This is instruction attribution for one program, not a new acceptance gate or performance claim. The prior preliminary ABI5 module receipts remain untouched.

The regression comes predominantly from scalar append readiness checking becoming an out-of-line native call under LLVM LTO. Scope routines are absent from the executed path. Native retirement/release code adds a smaller, separately identified cost.

## Identity and execution

| Item | Control | Composed candidate |
|---|---|---|
| Frozen executable SHA256 | `668b41ae6dfa9d725523e344c92b321e83f9f2806c9da7a7a62f5bdbb07067bb` | `a96a5b7a53a710808b9de060b95d0838526d94b9ea8c0a8b2b33315371aa0879` |
| Frozen compiler SHA256 | `4059a85e3d081f8a73b370e03e7d86cba8eb8a47531bfcdd7c09e6cc109d74b1` | `62147872cb192d103106bdf37616071a287b6e6fe19395461fe152e0d1fb1a42` |
| Direct hardware instructions | 2,167,224,352 | 2,232,222,548 |
| Callgrind simulated instructions | 2,140,315,994 | 2,205,312,978 |
| Process result, every probe | exit 0, `999739\n` | exit 0, `999739\n` |

The direct hardware delta is **64,998,196 instructions (+2.99914%)**; the exact Callgrind simulated delta is **64,996,984**. Absolute Callgrind totals are lower than hardware because execution is emulated and library calls can be redirected. These are distinct measurements; the close deltas substantiate attribution without equating their absolute totals.

Both originals are stripped. Each frozen compiler rebuilt only this guest with its original LLVM 3/LTO/RC options plus `--keep-symbols`, entirely into the owned worktree. `profile.py` verified equality of **every allocated ELF section**, including addresses, flags, sizes and payload hashes, between the symbol-preserving counterpart and original. No machine code or allocated data changed. Original and owned frozen copies were hash-checked before/after. `inputs.json` retains the full relink admission commands. `profile-receipt.json` records the perf stat/record admission commands; `callgrind-receipt.json` records the Callgrind admission commands and exact results. All probes used `scripts/build-slot.sh build`, pinned CPU 0, and owned outputs/cache/TMPDIR. No reserved timing CPU was used.

Valgrind was initially unavailable. Package `valgrind_1%3a3.26.0-0ubuntu1_amd64.deb` was downloaded through an admitted command and extracted into `.tmp/alloc-churn-attribution/valgrind-local`; no system package installation occurred. Package SHA256: `70b10c31307700a388262baa9cff7a3b27814a9716b6f19e8f748a56bcbfa442`. Tool: `valgrind-3.26.0`. No Guardian gate was exercised, so this task requires no new Guardian feedback entry.

## Exact dynamic attribution

| Routine | Control self instructions | Candidate self instructions | Delta |
|---|---:|---:|---:|
| `myl_rc_list_plain_ready` | 0 | 60,000,016 | **+60,000,016** |
| `myl_rc_storage_retire` | 52,000,000 | 54,000,000 | +2,000,000 |
| `myl_rc_edge_release` | 144,999,972 | 145,999,971 | +999,999 |
| `myl_rc_hold_edge_release` | 48,999,951 | 49,999,950 | +999,999 |
| `drain_one` | 93,999,906 | 94,999,905 | +999,999 |
| `entry_run` | 747,000,195 | 747,000,183 | -12 |

The new helper self cost is 92.31% of the net regression, but that figure alone is not the causal savings an inlining patch guarantees: old inlined instructions were counted inside `entry_run`, and other changes within that function compensate. Its append region self count is 311,000,017 → 309,000,000; including the new helper, that region adds **57,999,999 instructions**. The before-append regions fall by 3,999,997; remaining guest/fold/release/cold regions add 6,000,002. The four native release/retirement rows add 4,999,997. Their sum gives a 64,999,999 hot-path difference; startup/library changes contribute -3,015 to the exact simulated net.

Call counts are unchanged for insertion (3,000,000), owner release (3,999,999), hold release (999,999), storage retirement (2,000,000) and `drain_one` (999,999). The candidate adds **3,000,000** calls to `myl_rc_list_plain_ready`, one after each capacity-growth slow call in every 16-element batch. Its cached-success path executes 20 instructions; 2,999,999/3,000,000 calls take the cache hit. Readiness proofs remain invalidated at slow calls.

The accepted control incorporates the readiness logic in `entry_run` at **0x100bc18**. The candidate calls it at **0x100dece**, entering **0x10120f0**. `native_collections.c`'s readiness function and both `qbe_rc_append.zig` / `qbe_rc_append_loop.zig` have unchanged relevant source between A5 and 7f. Therefore the lost inlining is an observed LLVM/LTO code-generation decision; its precise heuristic trigger is not proved by this read-only binary study.

The smaller native regressions are explicit extra reloads following stores through `object->retired_link`. For storage retirement, the candidate reloads the slab index after writing the retired link; its 2,000,000 executions explain +2,000,000 instructions. The same reload appears in `drain_one` 999,999 times. Owner and hold release each reload `heap->rc` once after the retired-link write on their death-list path, 999,999 times. `native-paths.diff` and per-instruction counts show the exact locations. This is consistent with alias pessimism introduced by the ABI5 union containing the count pair and retired link, but compiler alias metadata was not inspected; that causal explanation remains an inference.

## Actionable boundary

Investigate preserving readiness inlining or a narrower hot readiness fast path while keeping null checks, pending-death refusal, binding authority and slow-call invalidation intact. Independently consider caching the confirmed state/index across the retired-link store in native retirement/release paths. Source changes belong to the integrator/runtime owner; no source was edited here. Publication and scope changes do not explain the dominant measured cost. Exact post-fix counts and the required combined gates/corpus measurements remain necessary.

`exact-counts.json` contains all function self counts, call counts and executed instruction-address counts. The hardware samples are also retained, but their biased per-symbol percentages are not used as exact attribution. Raw Callgrind output and assembly are the primary routine/basic-block evidence.
