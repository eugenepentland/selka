# Guarded immutable-byte loop result

This isolated slice reduces the unchanged `bytes_scan` instruction median by
40.65% on QBE and 91.46% on LLVM. LLVM now meets the 1.3× per-program instruction
limit for this workload; QBE remains above it. This is not Stage 4 acceptance and
makes no runtime-default change.

| Backend | Before instructions | After instructions | After / before | After / accepted GC |
|---|---:|---:|---:|---:|
| QBE | 5,344,329,541 | 3,171,680,414 | 0.593466 | 2.109321 |
| LLVM | 2,476,600,655 | 211,414,364 | 0.085365 | 1.081241 |

Direct guest RSS medians were 10,768→10,788 KiB on QBE and
10,828→10,812 KiB on LLVM. These small changes do not establish a memory benefit.
Every full output matched the unchanged expected file. Counted variants agree
exactly before/after and between backends: 12 allocations/retirements, O acquire
2/release 14, zero H pairs, one clone, 131,072 uniqueness checks. The improvement
removes generated empty-drop/check overhead and permits loop optimization; it
does not remove any real ownership operation.

## Source and proof

Base `45b4b62970d23d4724458bd1f0b86dead4b17a0c` contains production 49c and later
report changes. Before compiler is the fixed Debug `install-loops-fixed` with
SHA `49a8df2d575b65b16d3e7b455a8b0d6a3aa11ac4eccc13ad34dc3eeb8b54ebd5`.
Measured and final compiler/binary hashes, source patches and build commands are
in the archive identity and receipts below. All compilers are Debug; LLVM guest
builds explicitly use LLVM O3/LTO, verified in each manifest.

The [reviewed design](d9-rc-immutable-byte-loop-design-2026-09-27.md) extends the
existing read-only loop certificate with at most eight exact immutable-bytes
LOAD_LOCAL / i64 LOAD_LOCAL / GET_INDEX-u8 triples. The measured PC124 read is
admitted. A live ordinary O journal anchors the immutable header/backing; the
actual receiver operand guard must be zero before the fast loop starts. The
entire scalar-only body and all successor edges preserve that fact. The narrow
drop exception applies only to the exact active fast-copy PC/operand; checked
fallback, H/mutable sources, unknown effects and all normal drops are unchanged.
The generated-copy no-call veto is unchanged.

Root review found a missing charge for `mayHold`'s nested iteration-owner scans
after measurements had completed. The correction charges a conservative full
instruction scan per matching local, including named ones; a 4096-instruction,
256-local test accepts 63 matches and refuses 64 under the 262144 allowance.
The successor scan now calls the common exhaustive explicit-target helper.
These are compiler admission changes, not guest changes. The archive retains
both source identities and verifies the final compiler's emission and all four
full-workload guest binaries against the measured ones before reusing receipts.
The existing eight-element fixed membership loops are bounded separately.

## Validation and measurement

- New focused selection: 17/17, including exact fast/fallback IL, H/mutable/call/
  step refusal, switch/Result suffix targets, absent physical guard, exact PC
  scoping and charged-work boundaries. Existing list read-version selection:
  15/15. Counts include the shared test-runner checks.
- Five permanent guest assertions run before/after on actual QBE and LLVM in RC
  counting and GC stress: 40 passes. Heap snapshots, backing growth/rebind,
  parent/nested arenas, empty/short/negative-index scans, loop reentry, multiple
  owners and held/mutable fallbacks preserve outputs and exact RC counts.
- A separate diagnostic compiler disables only the new drop elision. The
  unchanged generated-text veto rejects its speculative fast copy. Original
  bounds/drop emission remains; both actual backend executions pass the same
  five assertions (10 additional passes), with production source restored.
- The exact QBE operand-guard snippet executes with 0, 1, 8, 16, 65536,
  0x80000000 and 0xffffffff. Only zero selects fast; all stored guards remain
  unchanged. This tests generated guard representation without forging a guest
  ownership token.
- Before/after actual QBE/LLVM controls preserve upper/lower bounds, overflow,
  and Debug step traps: 24 matching traps, including eight at two loop-body
  budgets; 12 matching success controls. Every counted exit is balanced.
- Whole Guardian: 88 checks pass, no baseline change. Root owns the combined
  full gate after integration and the central Guardian feedback entry.

CPU10 ran interleaved median-three instruction measurements for the unchanged
8 MiB × 16 scan. All 12 raw instruction samples report 100% event running.
Twelve separate `/usr/bin/time` samples measure direct guest RSS, not a perf
wrapper's memory; four separate counted executions validate ownership traffic.
Accepted GC instruction denominators are 1,503,649,715 QBE and 195,529,307 LLVM,
from the exact `joined-parity-49c6ca07` samples, preserved in the archive rather
than recomputed or silently replaced. The accepted baseline is untouched.

Archive: [`experiments/d9-rc-immutable-byte-loop-20260927`](../../experiments/d9-rc-immutable-byte-loop-20260927).
Run `python3 experiments/d9-rc-immutable-byte-loop-20260927/verify.py --live`
from this worktree to additionally check retained compiler/binary identities.
Initial fixture API/type errors and the mistaken bounds-code expectation were
corrected before accepted controls; those diagnostic receipts remain archived.
The first build's Guardian condition-complexity refusal was fixed by equivalent
sequential checks. No failing control was relabeled as passing.
