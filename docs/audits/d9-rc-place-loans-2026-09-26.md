# RC mutable paths through private inline loans

The cumulative `19e16e1d` compiler aborted in
`field_augmented::test_augmented_list_field_writeback_preserves_record_snapshot`
on both QBE and LLVM. The other 841 cases in each RC sweep passed. This change
preserves a hidden inline record's LOAN16 representation while detaching its
mutable leaves. It fixes the abort and retains observable iterator identity.

## Failure and ownership contract

A private record capture holds H tokens for its managed leaves. The old field
path treated those leaves as O edges: detaching `items` released an owner held by
another record and replaced the pointer without replacing the capture's hold.
Later unloan cleanup released a hold on the new pointer and aborted.

The emitter now carries the guarded local's dynamic loan role through inline
record and fixed-array projections. Uniqueness replaces an H leaf with another
H leaf. An immutable box similarly detaches through an H slot, preserving the
existing semantic child-sharing transaction. Dereferencing a managed body resets
the path role: its actual child fields own O edges. The scoped path walker applies
the same transition, including arrays of boxes. Existing ordinary uniqueness,
public layouts, ABI3 offsets and GC emission remain unchanged.

Replacement first constructs the new payload and acquires its hold, then publishes
the pointer and releases the former hold and fresh ordinary owner. Count or
allocation refusal leaves the original leaf token and bytes intact. Fresh shells
have zero holds, so their final first hold cannot overflow. Box clone child-history
marks use the existing transactional clone mechanism. Successful prefix detaches
in a multi-step scope retain the existing equivalent-prefix contract.

Converting the entire hidden capture to O was tested and rejected. It fixed the
abort but added a physical alias that detached an unshared list. A loop over
`holder.items` then failed to see `holder.items += [9]`: GC and frozen RC printed
`7` and trapped `R_LIST_ITERATION_MUTATION`, while that candidate completed.
The negative source and raw receipts are retained; its `after-rc` label denotes
the rejected candidate, not this implementation.

## Validation

The Debug compiler used for corrected guests has SHA-256
`26ea2be612a3fcd1041e02fc51f402843847cbd8a8850663a2b59be7fb21427c`.
Its immutable installation is recorded with source and binary hashes in
[`identities.json`](../../experiments/d9-rc-place-loans-20260926/identities.json).
LLVM runs use `--release` and never a later `--qbe` option.

- Nine guest files: **93/93 assertions per combination** of QBE/LLVM and
  GC stress/RC counting, **372 total**, including the original failure, snapshots,
  scoped callbacks, boxed paths, views, fixed arrays and arenas.
- Six unaccounted standalone assertions per backend all print `True`. Both
  backends report 87 heap allocations/retirements, 30 arena allocations,
  39 O acquisitions/126 releases and 68 balanced H pairs.
- The permanent iterator negative traps on both backends with `7` output,
  zero clones, five balanced heap allocations and eight balanced H pairs.
- Eight new native history cases cover O0/H1 and O1/H1 reuse, held box detachment,
  heap/arena identity, late child-count and allocation refusal, and the transition
  from inline array loan leaves to ordinary heap-body children. The history suite
  now has **35 cases**. All **23 native memory suites** pass ASan and UBSan.
- Focused RC tests **69/69**, COW **19/19**, dedicated trap filter **12/12**,
  formatting and whole-tree Guardian **88/88** pass.

This is focused correctness evidence. The parent integration owns the subsequent
full gate and uncached sweeps. WP-4 performance acceptance remains open.

## Reproduction and evidence

[`experiments/d9-rc-place-loans-20260926`](../../experiments/d9-rc-place-loans-20260926)
contains the failure receipt and emitted IL, the rejected ownership-normalization
controls, corrected guest commands/results, counter records, compiler identities
and check logs. The standalone module driver imports copies of the two permanent
fixtures with their respective module headers. Large receipts are gzip-compressed.

Replay the guest matrix from this worktree with its own cache and temporary
directory, through one build slot:

```sh
scripts/build-slot.sh build python3 experiments/d9-rc-place-loans-20260926/check.py \
  /path/to/installed/mylang /path/to/output
```

The native fixtures are permanent in `tests/native_rc_history_test.c`; use
`MYLANG_TEST_ASAN=1 scripts/build-slot.sh build python3 scripts/test_native_memory.py`
to repeat the sanitizer driver. The root gate exercises the permanent language
and iterator regressions.
