# D9 WP-4: joined constructor profile and next bounded experiment

Baseline source is cumulative `7d68202d59cf834bf9649fd77df2000f548ffec9`, real-merged
in the working branch as `4781613e`. The immutable Debug compiler is
`d9-rc-integration/.tmp-rc/install-scope-scalar/bin/mylang`, SHA-256
`7decd168a86694b21d9c69eda88f7097a351e161b033c18c8270225129460b48`.
The accepted GC controls are the preserved f6 depth-12 binaries from the earlier
allocator experiment; the new receipts retain their paths and SHA-256 identities.

## Matched diagnostic

The existing private depth-12 binary-trees workload runs unchanged. CPU 2 samples
alternate RC/GC order, median three. LLVM is actual O3/full LTO. All output matches
`expected.stdout`; counted RC remains allocations/retirements 669,060/669,060,
ordinary acquire/release 19/669,079, holds zero, clones zero and 33 unique checks.

| Backend | RC retired instructions | Accepted GC | RC/GC |
| --- | ---: | ---: | ---: |
| QBE | 434,531,494 | 105,803,350 | 4.10697 |
| LLVM | 239,809,166 | 50,532,266 | 4.74566 |

A separate 240-repetition executable provides instruction sampling with
`perf record -e cpu_core/instructions/u -F 199`; source, binary and build
identities are recorded. The table below weights samples by their periods.
There are no lost samples. These are approximate attributions, not exact dynamic
helper counts; interrupt skid especially prevents interpreting a hot store's
sample weight as that instruction's literal cost.

| Function | QBE share | LLVM share |
| --- | ---: | ---: |
| `make` | 26.09% | 48.28% |
| `slab_take` | 14.67% | 6.29% |
| `check` | 11.84% | 5.73% |
| `myl_rc_drain` | 8.47% | 22.70% |
| `myl_rc_edge_release` | 6.60% | inlined in drain |
| `myl_rc_storage_alloc` | 6.29% | 3.90% |
| `retire` | 3.31% | 10.43% |

`check(Node)` is symbol
`myl_f_20f65c28671b40937c5bf23acc7c6f37e5a5ec0622e347b57685725df5ba9e50`.
Its approximate absolute instruction budget is near GC: QBE 51.4M versus 45.5M,
LLVM 13.7M versus 13.6M. This does not support targeting it before `make`, whose
sampled budget is about 113–116M versus GC's 28–52M. Allocation and destruction
remain separate substantial costs.

## Proposed whole-constructor arm

The current fresh-field optimization checks each source role and retains a
possibly fallible generic transfer. Consequently each intermediate record,
box and variant still publishes an internal construction guard before its fields,
then publishes its complete result and clears the internal guard. The proposed
experiment specializes one entire constructor instruction, retaining the same
closed scalar-input, linear-owner, no-SHARE/no-loan/no-callback certificate.

Admission also bounds output and field sizes, rejects unusual output ABIs and
unique fields, and preflights every counted source's live ordinary role before
any mutation. Sources remain in their complete frame journal through managed
allocation. Only after allocation succeeds may the fast arm perform direct byte
moves, source guard transfers and complete result publication. This span cannot
allocate, release, drain, seed values or invoke contracts/finalizers. It therefore
has no fallible partial-body interval requiring an additional internal guard.
The original whole constructor, including every construction guard and generic
transfer, remains the fallback for every dynamic or static refusal.

The closed grammar proves a stable inherited region, including calls entered
inside a parent's arena; no requested escape region is changed. The result's
stable operand may reuse source slot zero only after all source bytes have moved
and all source guards have been consumed. Distinct aggregate/heap destination
storage remains authoritative during this handoff. Return lowering and its
independent live-role/ABI check are unchanged.

This is a proposal to measure, not a claim of a completed optimization or Stage-4
acceptance. Required controls include nullable/literal fields, named order,
allocation refusal after successful child construction, parent arena lifetime,
count/unique/finalizer refusal and ordinary trap cleanup. Frame/state linkage and
other agents' local extraction proofs are outside this slice.

All raw profiles, samples, commands, manifests, generated `make`/`check` IL and
native `make` disassembly are in `experiments/d9-rc-fresh-field-profile-20260927/`.
