# Fresh dictionary loop-entry uniqueness

The unchanged two-million-update `dict_count` now performs one dictionary
uniqueness check at loop entry, preserving the existing 1000 key-list setup
checks. The full counted result is 2,001,000 → 1001 checks on both backends.
All other counters and exact output are unchanged. This is a bounded compiler
proof; runtime uniqueness, dictionary writes and defaults are unchanged.

| Backend | Before instructions | After instructions | After/before | Accepted GC | After/GC |
| --- | ---: | ---: | ---: | ---: | ---: |
| QBE | 1,429,539,694 | 979,547,911 | 0.685219 | 661,305,020 | 1.481235 |
| LLVM O3/full LTO | 884,366,231 | 644,367,038 | 0.728620 | 441,034,623 | 1.461035 |

These are median-three retired user instructions on CPU11, at the original
source and size. All 18 production observations contain one active cpu_core
event at 100% running. Every run prints the exact expected output. The row
still exceeds the 1.3 limit: another 12.2354% QBE / 11.0220% LLVM reduction is
required. No RSS, whole-corpus or Stage4 acceptance claim follows from this
slice.

Before is committed key slice `a8f852b9784a40c048df9a7d9b6a33066b413269`, using
immutable Debug compiler `.tmp-rc/install-dict-key-prototype/bin/mylang`, SHA256
`106bd30f12bcedc96d040822039088adb46ce01ff1b648d83bf36c1c443a73b2`.
After is immutable Debug `.tmp-rc/install-dict-loop/bin/mylang`, SHA256
`25dad5001d2ddbf91c266ed19f4272849131adaedf70bb113f9c0864c2025625`.
The accepted GC binaries are unchanged; hashes and original build receipts are
included with the measured manifests. Native benchmarks use QBE ReleaseFast
and actual LLVM O3/full LTO; the compilers themselves were built in Debug.

## Physical proof and composition

The prior semantic analysis already proposed local5's PC64 check at loop head34,
backedge74. Existing RC list proofs deliberately declined dictionaries. The new
late refinement accepts only an already certified anchored immutable-string
key/write interval and a direct empty-dictionary constructor immediately
followed by the root's one canonical named store. The store takes the fresh
operand into the local, clearing operand and pending guards. It leaves one O
edge; there is no retained constructor local or inferred extra alias.

From that definition through the backedge, the proof excludes any other managed
producer, root publication, callback, reference, rebind, snapshot, history,
scope or arena transition. It reuses the existing key certificate for the exact
closed interval. Other instructions must be plain scalar operations (or a POP
with only plain, nonunique inputs). Complete-function CFG checks prevent
skipping the constructor, entering the loop interior or reentering from a later
publication without recreating the root. Post-loop owned return remains legal.

Every scheduled release edge from a scanned PC is conservatively inspected,
including branches, backedges and exits. Only the three independently proved
empty capture/key guards are exempt. This is stricter than current cleanup
emission, which only executes selected store/fallthrough edges. A tiny control
with an anchor dying at loop exit was therefore refused; its positive version
keeps that anchor observably live after the loop. The benchmark's later real
iterator already provides this lifetime. No release schedule is changed.

The refinement appends one `Loops.entries` item after original loop-version
veto and dictionary-tail finalization. All COW sites, checked flags, captures,
places, aliases, journals and terminal writes stay intact. Existing entry
routing emits `@ce34`; existing coverage suppresses the body check. The old
tail's first-check premise is discharged by this separate entry proof. The
`permitsVersion` query now explicitly accepts list entries only, so a late
dictionary entry cannot authorize cached-storage fast loops. Actual emission
has `@ce34`, no `@fi34`, unchanged key/tail markers, unchanged helper call-site
counts and one fewer uniqueness call inside the loop. Native QBE disassembly
has the same total call-site counts; the location, not the API, changed.

Runtime peer review confirmed the exact fresh success path is allocation,
drain, finalizer and refusal free, including zero iterations and inherited
arenas. It reads registered metadata and the existing header, then returns.
Builtin string/plain writes may acquire inserted-key edges and replace backing,
but cannot publish another owner or semantic SHARE on the dictionary header.
The original write retains its region/count/growth failures and drain boundary.

The optional proof refuses functions over4096 instructions and loop spans
over1024. Its262144 allowance charges definition/code, CFG successor and
inspected metadata rows; shape inspection retains its separate bounded work.
It is not a claim of262144 primitive operations. Exhaustion declines the
candidate, and no partial entry is installed. Multiple tails for one root,
previous root entries and uncertain roles retain original lowering.

## Validation and limits

Focused dictionary tests pass23/23. Structural controls cover the actual
benchmark, direct fresh positive, shared zero-iteration refusal, snapshots
inside the loop, mutable callback/reference, root rebinding, enclosing-loop
publication, skipped constructor, interior entry, backward entry, scan
exhaustion and branch-edge cleanup refusal. The new guest is a declared unit
input. Whole Guardian passes88 checks; formatting and diff checks pass.

Actual GC-stress and RC runs pass100 uncached assertions across QBE and LLVM:
the seven new loop cases, eleven key cases and seven tail cases in each mode
and backend. This includes inherited arenas, post-loop owned returns, real
iterator behavior and fallback snapshots/callbacks. The existing known GC
physical-floor timeout was not repeated.

The paired Debug trap/budget matrix has56 executions with identical before/
after output, exit status and non-counter trace. It covers bounds, overflow,
four step limits before/through the first write, zero iterations, heap growth
and inherited-arena operation. Heap growth fails at the original write at384K
and succeeds at512K. The first all-arena fixture's smaller budgets failed
setup rather than its write, so those diagnostic probes are preserved without
claiming write-refusal coverage from them.

A separate16-run inherited-arena fixture keeps the immutable key list in the
older heap region and publishes it canonically into the callee. Its dictionary
loop is admitted. At320K/384K/448K the original write fails with the same
`R_MEMORY_BUDGET` trace; at512K it succeeds, on both backends and compilers.
All owner/hold/retirement totals balance, including partial insertion failures.

Four embedding executions enter the admitted loop from a real finalizer while
a sibling death is queued. The sibling remains deferred until the guest
returns and the outer drain resumes. Exact phase/result observations and
balanced counts match on both backends before and after.

Full-size counted runs have O acquire/release2001/4030, H acquire/release2001,
heap allocate/retire2029, no arenas, clones or count refusals. Only uniqueness
changes. Reduced20K runs independently show21,000 → 1001 checks with all other
counters identical before expensive comparisons.

The archive retains initial compile errors, stale structural expectations,
the precise scalar POP refusal diagnosis, and the first emission-script label
search error (it matched a jump operand rather than a full label). These were
corrected before the reported measurements; production was frozen at the
after compiler hash for all final receipts.

Reproduce the archived checks with:

```
python3 experiments/d9-rc-dictionary-loop-20260927/verify.py
```

The archive contains raw perf text, manifests, exact sources, commands,
compiler/native identities, emitted IL, native disassembly, all control
receipts and logs. No default, ABI, runtime C or general dictionary optimization
is changed.
