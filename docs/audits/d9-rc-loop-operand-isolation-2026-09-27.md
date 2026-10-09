# Fast-loop word isolation: measured byte scanning

This bounded compiler change reuses existing write-only, unescaped operand
slots for an already accepted quiet fast loop. The full unchanged byte-scan
workload now meets the 1.3× instruction cap on both backends. No runtime,
ownership, frame-layout, cache-identity, or default-mode policy changes.

## Matched result

The source is `bench/parity/micro/bytes_scan.my`: 8 MiB scanned sixteen times,
expected stdout `8388728`. CPU11 retired-user-instruction medians use three
runs of each immutable executable, actual LLVM O3/full LTO, and independent
counted builds. All 18 instruction observations have one active event at
100.00% running. All 22 executions produce the exact expected output.

| Backend | Accepted GC | Before | After | After / before | After / GC |
| --- | ---: | ---: | ---: | ---: | ---: |
| QBE | 1,503,648,599 | 3,171,679,827 | 1,661,730,323 | 0.523928 | 1.105132 |
| LLVM | 195,528,212 | 210,365,220 | 210,365,260 | 1.000000 | 1.075882 |

The row is respectively 14.99% and 17.24% below the 1.3× limit. This is one
row, not a corpus geomean or lower-RSS acceptance claim. LLVM is unchanged
within negligible measurement variation; QBE improves by 47.61%.

All four complete count records are identical: 12 heap allocations and
retirements, 2 owner acquisitions, 14 owner releases, no holds or arena
allocations, one clone, 131072 uniqueness checks, no saturation or limits.
No physical traffic was removed.

Before is the immutable Debug compiler `install-loop-guard-pc/bin/mylang`,
SHA256 `4897e476a4b56af33dc18a040d60635563bdd90a6f1ba7061bb84eb6040d7393`,
production source `238db806`. Candidate is immutable Debug
`install-loop-operands-prototype/bin/mylang`, SHA256
`9ffefb4c851823a9ab45ba1f0bc9e37a0a1534017cb00fc11d7fcee1115aa96d`.
Its production diff is based on design HEAD `d68f06f2`; only tests, guest
expectations and evidence changed after that build. Absolute paths, workload
hash, native manifests, binaries' hashes, complete perf strings and commands
are preserved in the archive. The accepted GC executables were not rebuilt.

## What the two proofs establish

The first proof reuses the final planned loop and existing quiet-copy veto.
It checks the whole instruction CFG, empty head/back/exit stacks, absence of
foreign interior entry, and only normalized word states or exact byte-read
borrow states. It runs only for RC native frames. Step-enabled code has no
accepted fast copy; heap retry uses ordinary text and original offsets.

The second proof sees the complete emitted function. It recognizes exact
paired markers and labels, classifies complete percent tokens, and selects
only slots with one existing `alloc8 8` and no reads or address escapes
anywhere in the original text. Full-word stores into those slots are allowed.
Every source reference inside a marked region must be a direct `loadl` or
`storel` address. Quoted strings are never rewritten; comments and malformed
identifiers cannot create false authority. All regions are accepted together
or the entire original function is returned unchanged.

The body also refuses RC/root/scope/pending/aggregate storage, `blit`, narrow
stores and computed-address stores. This stricter implementation gate catches
an indirect guard publication even when its address was formed outside the
candidate. Initial eligibility therefore remains scalar/read-oriented.
Calls, ownership events and other unsupported effects refuse through the
existing generated-body check. Source-proof refusal and final-parser refusal
both retain the valid unisolated fast copy; neither becomes an InternalError.
Allocation failure still propagates as OutOfMemory.

Code is capped at 4096 instructions, existing bodies at 200 instructions,
eight word positions and 32 planned loops. Each source candidate charges
instruction, stack-element and explicit-edge visits against 262144 logical
visits. This is not a primitive-operation bound. Each quiet body is capped at
1 MiB; the complete text at 4 MiB and 4096 slot identifiers. The final inventory
uses bounded region membership checks and one original-text token scan, not
one full scan per destination.

## Actual native path and corrected diagnostic

Root's original accounting-mode experiment used slots 62 and 63. They were
**write-only**, not unmentioned: each already had an allocation and a setup
literal store. Its original six SSA/assembly inputs and identity receipt are
archived verbatim with that correction. It was static motivation, not timed
evidence.

The actual normal ReleaseFast candidate independently chooses `s0=s3 s1=s4`.
The measured QBE binary's disassembly at `0x1008580..0x10085a9` has a twelve
instruction successful byte iteration, no operand stack stores, and a
conditional move for the matching byte. The prior fast body repeatedly
spilled these words because their original addresses escaped elsewhere.
Entry guards and the complete original fallback remain outside the rewrite.
No slot or allocation was added; actual frame accounting is unchanged.

Original write-only setup stores remain present. Multiple disjoint accepted
regions can reuse the same bank because every ordinary boundary is empty.
The bank never escapes, so failure helpers abandon no owner and finalizer
reentry cannot reach the suspended frame's evaluation words.

## Validation and limits

Six named proof/emission tests (17 total including existing unconditional
tests) pass. They cover full identifiers, quotes, address-as-value, metadata
and computed stores, missing banks, global aliases/reads, malformed/nested
markers, all-or-nothing refusal, foreign entry, empty boundaries, checked
fallback, step refusal, and actual forced heap-frame lowering. The permanent
guest covers zero/one/many iterations, both branches, outer reentry, genuine
iterator tokens, snapshots and inherited arenas.

The paired standalone controls retain exact bounds/overflow/step/logical
frame trap codes and source traces, normal and failing heap frames, physical
stack-floor refusal, and balanced ownership on both actual backends. Physical
floor recursion depth is not an instruction-stability promise: generated
native stack use can differ while the same floor and unwind protocol remain.
Separate GC controls keep identical before/after emitted text. The adjacent
dictionary/byte-loop guest preserves its prior exact output and counts.

A C embedding control runs a real guest fast copy from an active RC finalizer
while another finalizer is queued. Both backends and both compilers return 30;
the queued callback runs only after the guest returns. The checked frontend
manifest explicitly drops step checks and the library is built from that
manifest, so this exercises the isolated body. Execution uses the documented
unbounded sentinel, not an invalid zero budget. Ordinary library builds keep
step checks and would not establish this property.

Early validation failures are retained: one fixture incorrectly expected six
matches in the first sixteen bytes (the before compiler correctly returned
four), the driver requested an unsupported frame-accounting spelling, a
library probe lacked its required main, and zero was an invalid embedding
budget. They required only driver/expectation corrections. Initial compiler
syntax, three production Guardian findings and a final test-only conditional
finding were fixed normally; no check suppression
or tolerance was introduced. Whole-tree Guardian is the 88-check source gate,
not the four-command integration gate. Root owns the combined integration
run and centralized feedback.

Reproduce or independently inspect the compressed receipts with
`experiments/d9-rc-loop-operand-isolation-20260927/verify.py`; `--live` also
checks the immutable compiler and executable hashes. No repeated full corpus
or broad GC-stress sweep was run for this slice.
