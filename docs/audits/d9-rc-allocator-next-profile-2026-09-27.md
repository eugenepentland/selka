# D9 WP-4: separate allocation cost from plain publication

The complete-constructor slice is committed as `cdec9ff5`. The next runtime audit
compares the allocation and retirement implementations with the accepted GC path,
then profiles the unchanged full-size `alloc_churn` workload using the parent's
frozen `7d68202d` compiler and executables. No runtime edits are in this report.

## Binary trees

The existing joined n12 profile attributes QBE instruction samples to `slab_take`
(14.67%), `myl_rc_storage_alloc` (6.29%), retirement (3.31%), flat edge release
(6.60%) and drain (8.47%). LLVM attributes 6.29% to `slab_take`, 3.90% to storage
allocation, 10.43% to retirement and 22.70% to drain. These are approximate
period-weighted instruction samples, not exact dynamic call costs. The preceding
constructor change does not change these runtime sources or event counts.

The accepted GC compiler emits prepaid inline bump allocation. Runtime code opens
and charges a contiguous window; generated code advances its cursor, writes the
two-word prefix and initializes the payload. RC disables this generated path and
calls native allocation for each object. Its small-object type/class cache avoids
repeat registration, but every allocation still selects a slab, pops a free slot
or advances its used count, updates live accounting, clears the variable-sized
slot and initializes the four-word prefix. The current QBE `slab_take` contains
inlined cold reserve/trim/new-slab code; its common path saves and restores five
callee-saved registers before tail-calling variable-size memset.

Thus allocation protocol work, not repeated host malloc alone, is a plausible
binary-trees target. The earlier prefix-zeroing experiment was measured neutral
or worse and remains rejected. A future prepaid RC window would need separate
reservation ownership, correct slab pinning/trim/settle behavior, actual allocation
event accounting, descriptor admission, custom-hook fallback and arena transition
handling. It is a larger allocator/compiler contract and is not implemented here.
Teardown must retain every O/H decrement, finalizer and immediate reuse event.

## Full-size allocation churn

The unchanged workload creates one million lists, appends sixteen integers to each
and folds them. Profiles use CPU 2 and `perf record -e cpu_core/instructions/u
-F 199`. Debug compiler and executable identities, commands and manifests are in
the receipts. Symbolized twins have byte-identical `.text` to the parent's frozen
corpus binaries:

- QBE text SHA-256:
  `51051d9f837190caa3135c13793e2e2d0ddbf94b81f2f4c58b076e953f3983f2`.
- LLVM O3/full-LTO text SHA-256:
  `2277a952067919ca47a9ea1a9629db73cdce19c6895f73eb39be586c4bda084d`.

QBE produced 549 samples and LLVM 189; neither lost samples. LLVM's shorter run
has coarse attribution, and interrupt skid limits interpreting an individual
instruction. Both profiles nevertheless identify the same generic publication
path rather than slab allocation as the large cost.

| Sampled function | QBE | LLVM |
| --- | ---: | ---: |
| descriptor lookup | 13.26% | inlined |
| shape resolution | 12.84% | inlined |
| `copy_many` | 7.39% | inlined |
| `myl_rc_native_retain` | 3.45% | 22.41% |
| value seed | 4.10% | 8.87% |
| frame preparation | in callers | 8.35% |
| drain | 5.52% | 10.15% |
| `slab_take` | 1.14% | 1.83% |
| retirement | 0.57% | 0.61% |

Both counted executions have exactly 4,000,000 allocations/retirements,
1,000,000 ordinary acquisitions, 5,000,000 ordinary releases, 1,000,000 balanced H
pairs, 16,000,000 uniqueness checks, no clones and no refusals. Each scalar append
passes through `rc_list_insert_at` and `myl_rc_native_retain`. The latter currently
resolves metadata, validates unique contents and prepares a generic retained-copy
walk even for a registered plain integer.

## Bounded next experiment

Prioritize plain `native_retain` publication, using the same prevalidated
`binding.flat.count == 0` authority as the existing plain replacement fast path.
That proof excludes raw unique fields and every descriptor callback, as well as
counted or held leaves. Registered disjoint nonzero values could copy directly,
with exact region refusal status and an emptied destination on failure. Zero-size,
alias/overlap, cold metadata and queued-death cases must keep their existing path.
Existing descriptor lookup can supply the fallback shape, avoiding an extra hot
lookup on managed values. No history, pin, count or allocator ABI changes belong
in this slice.

Required controls cover poisoned refusal output, adjacent disjoint buffers, alias
and overlap routing, zero-size values, cold registration at the byte budget, count
limits, H/unique exclusions and a queued finalizer mutating the original source.
The full one-million-list output and all counts must match before/after on both
actual backends, with median-three instruction measurements. Compiler loop
uniqueness is a separate peer-owned opportunity and is not part of this runtime
experiment.

All raw profiles and identities are archived under
`experiments/d9-rc-alloc-churn-profile-20260927/`. The broader acceptance diagnostic
and its GC comparisons remain parent-owned; this report makes no acceptance claim.
