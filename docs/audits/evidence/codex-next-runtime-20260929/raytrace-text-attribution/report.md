# Frozen A5 versus composed 7f instruction attribution

This is read-only attribution, not candidate acceptance. No source was edited,
no Guardian gate ran, and no reserved timing CPUs were claimed. The owned
review worktree is at `27b170076d1a21286857f7fc00583bded555497d`.
The compared candidate is `7f5068a54946bcbe0cf1f7e20abf844f120046cd`.

## Identity and protocol

`receipt.json` records all four original binary hashes, both frozen compiler
hashes, and every build-slot admission command, including `perf stat`.
All four symbol-preserving guest builds have identical allocated ELF sections
(address, type, flags, size and payload hash) to their original stripped frozen
binaries. Hardware perf counted the copied frozen binaries; Callgrind counted
their identical-code/data symbol-preserving counterparts. Every execution
returned zero and byte-matched the checked-in expected output. Original root
binary hashes were rechecked unchanged.

Every guest build and heavy probe used this worktree's `scripts/build-slot.sh
build`, own caches/TMPDIR, and CPU0 for counting. Valgrind3.26.0 was extracted
locally from the previously recorded package; no system installation occurred.
Callgrind counts are exact simulated executed instructions, not exact per-routine
hardware counts. Startup/library redirection can change absolute totals.
`original-results/` preserves all six original dev/smoke/full JSON results;
the probes are attribution only, not a replacement corpus measurement.

| Workload | Hardware control | Hardware candidate | Hardware delta | Callgrind delta |
| --- | ---: | ---: | ---: | ---: |
| LLVM raytrace | 1,261,221,486 | 1,274,689,343 | +13,467,857 | +13,466,416 |
| QBE text_ops | 1,756,008,488 | 1,773,912,829 | +17,904,341 | +17,901,149 |

## LLVM raytrace

`entry_run` self cost rises by13,472,548 instructions. Two hot hold-acquisition
sites execute2,073,600 and1,294,536 times, respectively. The unchecked A5
memory increment is replaced by load/increment/overflow branch/store: three
additional instructions per acquisition, totaling10,104,408.
These MAX/overflow checks are required; this report does not propose removing
them. The remaining3,368,136 hot instructions are new `vxorpd %xmm5,%xmm5,%xmm5`
zero initializations, once after each normal acquisition continuation. Four
entry startup instructions and−6,132 other startup instructions complete the
total. `prove.py` asserts this decomposition against raw instruction counts.

The two A5 increments are at0x1010f1c and0x10112ec. Candidate guarded sequences
start at0x1013790 and0x1013a30. The candidate zero instructions are at
0x1013458 (2,073,600 executions) and0x1013a43 (1,294,536 executions).
A5 initializes the same xmm5 floating+0.0 at0x1010d0c before the pixel loop.

This value serves the inlined `intersect()` source comparisons `disc <0.0`,
the sqrt-domain check, and `(0.0-b)` in `raytrace.my:43–49`. Primary uses are
0x1013532/0x101353c/0x1013546; shadow uses are
0x101393a/0x1013940/0x101394a. Another sqrt-domain check uses it at0x101371c.
Candidate overflow cold paths can call `fail`, while the normal continuations
rematerialize zero. That placement and live value are observed in assembly;
the compiler's precise live-range/hoisting reason is an inference, not proven.

Saving only these redundant normal-path zero instructions, while retaining
MAX admission, would arithmetically reduce the observed1.06786% increase to
about0.8008%. This is an opportunity estimate, not a measured implementation.
There is no hot scope/native-call cost in this case.

## QBE text_ops

The following self-cost deltas sum to17,905,659; other startup/library effects
sum to−4,510, giving the exact17,901,149 simulated instruction increase.
The two relocated anonymous routines at0x1035b10/0x1036100 each cost44,533,514
and cancel; they are not new work.

| Routine/group | Additional executed instructions |
| --- | ---: |
| long_piece plus view | 3,230,000 |
| generated str-list append | 4,371,458 |
| text_ops::main | 3,514,237 |
| myl_rc_edges_release | 2,942,842 |
| myl_rc_edge_release | 1,199,997 |
| strings::repeat | 971,420 |
| drain_one | 589,998 |
| myl_rc_storage_retire | 467,140 |
| text_ops::pad | 428,568 |
| myl_rc_hold_edge_release | 189,999 |

### Lost view inlining

Both binaries call `long_piece`190,000 times. A5 executes103 instructions per
call and inlines `view`; candidate executes46 instructions plus an out-of-line
74-instruction `view`, adding17×190,000=3,230,000. The `view` C source is
byte-identical; `prove.py` verifies the copied compiler-emitted runtime source.
The new `myl_native_text_tail` is an additional view caller. Changed compiler
inlining decisions correlate with that addition, but the heuristic cause has
not been established. Preserving inlining without altering any view body,
allocation/refusal/admission/fallback logic is the narrow isolated opportunity.
It represents about0.184% of A5 text_ops instructions.

### Generated append and guest count checks

The generated str-list append executes1,400,010 times. At742,862 ordinary
counted-owner admissions, A5's memory increment plus jump is replaced by
load/compare-MAX/overflow branch/increment/store/source reload, adding four
instructions. Candidate also has one common jump for each1,400,010 source
value:4×742,862+1,400,010=4,371,458 exactly. Candidate count admission is at
0x103576f–0x1035780; common jump0x1035786. A5 increment/jump are
0x1034cc3/0x1034cc7. The new MAX guards and publication-after-admission behavior
must remain.

`pad`'s entire428,568 delta is three extra checked-acquisition instructions on
142,856 successful counted owners (0x1034d85–0x1034d9f versus
0x1034799–0x10347aa). `main` has seven hot checked hold sites, each200,000
executions, plus register/branch/decrement-path changes. `repeat` also has
checked hold/owner paths and register changes. `proof-summary.json` gives
their exact instruction-site execution histograms, and the three focused
normalized diffs plus both counted assembly listings preserve every block.
Those guest routines' totals are exact; not every register-allocation change
has been assigned to a unique source edit.

### Native reloads and hash probes

`myl_rc_edges_release` adds exactly942,852 executed `heap->rc` reloads at
0x1052627 after the intrusive retired-link store. Its hash loop also performs
599,998 probes versus399,999 in A5 for the same399,999 calls. The extra199,999
probes each execute ten instructions, adding1,999,990. Together they give
2,942,842 exactly. Loop starts are candidate0x1052510/control0x10512d0.
The reason for differing collision placement is not proven; ASLR is a possible
explanation. Candidate original dev instructions are about2M below smoke/full,
consistent with this variable path, but that consistency is not causal proof.

The other native release/retire routines have additional pointer reloads after
intrusive union/link writes, as in the separate alloc_churn attribution. They
are not scope cost. Their exact routine self deltas and individual instruction
execution counts are preserved. No layout/aliasing repair was attempted here.

## Evidence boundaries

Raw profiles, assembly, copied frozen binaries, symbol counterparts, source
copies, admission/status logs, original JSON results, exact-count parser output,
assertion script and package manifest are retained. Guest configure/object
caches and the local Valgrind tool installation are omitted from the raw
package; source files consumed from those caches are copied separately.
The independent preliminary module receipts and alloc_churn archive are
untouched. Later plain-ready changes and later performance samples are owned
by the integrator and are not measured or accepted by this report.
