# D9 RC live dictionary view lowering — 2026-09-26

The three failing `dictionary_views` guest cases were snapshots under RC because
an inline view retained an ordinary owner. A mapping write saw that owner and
made a COW copy. Builtin view descriptors now use the core `HOLD_POINTER` shape:
a view retains the dictionary header without contributing to sharing. Builtin
identity comes from `RecordShape.builtin`, not a display-name prefix.

View construction and replacement of the public `mapping` field acquire the new
H token before retiring any input. A projected dictionary uses journal flag 8;
hidden receiver locals preserve that role through loads, stores and moves.
Publishing a named dictionary binding or an owned return copies an O token
before dropping H, so refusal preserves the original guarded lifetime. An
ordinary O publication resets a local's prior H role. No view adds a pin.

A field replacement's dead hidden RHS owner must also retire at its proven last
read. Otherwise that temporary alone forces a later dictionary mutation to copy,
leaving the rebound view stale. The special update uses the existing solved
liveness table and requires a compiler temporary loaded immediately before the
update; user bindings retain their ordinary lifetime.

Validation uses the six unchanged `dictionary_views` guest bodies and three new
regressions: named mapping snapshots, mapping-field rebinding, and views stored
in lists across dictionary growth and clear. Both QBE and LLVM ReleaseFast run
all nine with identical counts:

| Counter | Both backends |
| --- | ---: |
| Heap allocations / retirements | 4,113 / 4,113 |
| Owner acquire / release | 4,017 / 8,130 |
| Hold acquire / release | 473 / 473 |
| Arena allocations | 8 |
| Clone shells | 2 |
| Saturated | false |

Debug compiler SHA-256:
`97b0e268a4b612c405f7a82655b250166aaa6a162821abddadaa51e2f5c9a868`.
The focused metadata tests pass 13/13 (two named, eleven root import tests),
including user-defined `DictValues` retaining ordinary owner shapes. The three
new guest regressions also pass with the GC runtime. Guardian's 88 checks pass.
Reproduction and full counts are in
[`experiments/d9-rc-held-views-20260926`](../../experiments/d9-rc-held-views-20260926).

Two integration requirements remain outside this lowering slice. Mutation
through the exposed `view.mapping[key]` receiver needs the compiler's generic
receiver treatment for an H field; that audit is assigned separately. Recursive
stored types can construct a dictionary → stored view → dictionary H cycle.
Before admission checking, the accepted-GC self-cycle probe also passes under
this RC lowering but reports four heap allocations, zero retirements, nine hold
acquires and eight releases. That is a confirmed unsupported cycle, not an
accepted cleanup result. The separate stored-type admission rule must join
before RC acceptance; this change does not add a cycle collector or silently
fall back to GC.

## Joined nested-shape and unwind audit

After joining stored-type admission `1a6352de` and plain-operand drop suppression
`ccefacbe`, three more guest cases pass on both backends: younger-arena escape
through records, lists and multiple held views into a dictionary with managed
values; a 257-node recursive boxed chain carrying live views; and an older heap
mapping retaining its identity when its view escapes an arena. The twelve-case
run reports 4,920 heap allocations and retirements, with balanced owner and hold
counts; see `deep-qbe.json` and `deep-llvm.json`. All six new regressions also
pass on GC. The recorded cycle source now receives `E_LIVE_VIEW_CYCLE` before
emission.

The `trap.my` probe leaves an active hidden H receiver when an assertion fails.
Both backends report `R_ASSERT` and fully clean up: eight allocations/retirements,
six owner acquires plus fourteen releases, and four hold acquires/releases.
`trap-qbe.json` and `trap-llvm.json` retain exact commands and diagnostics.

Backend evidence correction: the original LLVM-labeled basic/deep/trap records
used a later `--qbe` option and actually ran QBE. Those historical files remain
unchanged. New `llvm-corrected.json` and `trap-llvm-corrected.json` use actual
LLVM O3/LTO and confirm all twelve view assertions and expected trap cleanup
with balanced counts identical to the corresponding QBE results.
