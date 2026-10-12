# Combined native retirement draft on Support7

Status: **scratch preview passed; production retirement is not activated**. This
combines the A01, A02, A04 and A05 runtime drafts on frozen Support7
`bed11cf3bf3102ffec44487e431a1573fdf02ad5`. The test commands pass neither a
`MYL_ZERO_RC` definition nor an ownership-mode selector. All embedded runtime
inputs contain no `MYL_ZERO_RC` selectors after applying the archived drafts.

The combined runtime SHA256 is
`ca2ded335995f2d6f76c9900b172d74c20800cbe2885af4f3d39bf72a1eb7ca1`.
Every pinned source hash, patch hash, patch result, compiler identity, native
command, raw output and binary identity is recorded in `inputs.json` and
`results.json`. Patches apply with zero fuzz. The A01 patch also changes the
`parallel.my` explanatory comment; that complete patch is preserved and applied
in scratch, while only the C runtime enters the native binaries.

The capacity fixture passes all 13 original success/OOM/budget cases unchanged.
The owned fixture passes its 32-byte layout/offset assertions, independent
managed-child copies, same-block mutation, rotation/reversal, removed-child
transfer, zero-sized elements, box-shell transfer, independent buffer copy and
zero final live blocks. Both fixtures enable `MYL_CORE_LEAKCHECK`. Compiling
`offsetof(myl_block, count)` fails because the retired member is absent. Linked
symbols contain no audited legacy RC helpers or public legacy task helpers.

Native binaries:

- capacity: `cf808091050065b6fb95885dc45270596e937066b967eb767848a38b0293e5ae`
- owned: `dc470f2e9e137691770af79c5c10eb1fa377bd5a99e4b4cf8de7f4cb26fa01bb`

`initial-unclassified-results.json` preserves the first aggregate false result:
its source search counted names in `#pragma GCC poison` as active operations.
Those directives forbid legacy identifiers. `results.json` classifies them
explicitly, without modifying or rerunning native sources, binaries or samples.
The fixture checks passed in that initial run as well. The corrected harness
performs this classification before deciding success on future runs.

The build ran under shared build admission, FIFO ticket 957. Reproduce with a
new scratch directory (the harness refuses to reuse an existing directory):

```bash
source /home/epentland/.config/mylang/dev-env.sh
scripts/build-slot.sh build python3 -B \
  experiments/memory-closeout-20261012/A02/retirement/combined-support7/preview.py \
  --source-root /home/epentland/ai/canopy/mylang-memory-20261012 \
  --scratch .tmp/memory-closeout/A02/retirement-combined-support7-rerun
```

This is a native runtime compatibility check. It does not qualify generated
guest LLVM, compiler cache invalidation, command defaults, task stress, installed
components or the complete registered verification gate. The task functions are
linked, but these two fixtures do not execute task scheduling. A01 owns that
qualification; A09 owns counted-runtime anchor qualification on this exact
combined source. There are no timing or RSS claims. Production C3 activation
still depends on the coordinator's qualified C2 and final integrated checks.

Direct destruction, including `layout_release`, stays valid. Descriptor child
counts and task pending-work counters stay valid. Reserved zero RC telemetry
names are outside this native source and remain a separate A09 contract.
