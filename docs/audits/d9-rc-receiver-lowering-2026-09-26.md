# RC receiver lifetime integration

Experimental RC calls and pending receiver paths now use typed runtime scopes.
Mutable call arguments are made unique through their physical owning slots and
then held/pinned until the callee returns. A compiler receiver temporary borrows
its captured payload through a separate non-sharing scope, including its managed
ancestors and captured backing. That scope ends after the mutator publishes its
result. Callback replacement can therefore leave zero ordinary owners while the
pending receiver remains alive. Frame cleanup restores scopes before releasing
owners on every trap or return.

Finite inline-array paths prepare and pin candidate leaves before index callbacks.
Both the initial base read and later path projections borrow those candidates;
creating an ordinary snapshot at either point would mutate a detached temporary.
The runtime owns all pin restoration and hold counts. The emitter adds no inline
RC counter operations.

Debug compiler SHA-256:
`e0e8ca3693129b4c7558413d0f57ca0b33d47d59828b854199210976c984566a`.
The recorded focused results are:

- Nine ownership guests pass freshly on QBE Debug, LLVM ReleaseFast and default
  GC. The added parent-clear case exercises a receiver without an inline array.
- Three existing mutable argument-alias guests pass on both RC backends.
- Fifteen of nineteen existing pending-array callback guests pass on each RC
  backend. The three recursive-box cases and one arena case still abort; they are
  retained as failures requiring remaining aggregate/arena integration.
- The focused scope lowering test passes (one named plus 11 unconditional test
  blocks). Whole-tree Guardian passes all 88 checks.
- A direct callback-snapshot executable passes on both RC backends, with identical
  counts: 20 allocations/retirements, 7 acquired/released holds, 12 owner acquires,
  32 releases, 5 clone shells and 10 uniqueness checks.

## Preserved GC correctness finding

The callback-snapshot fixture is
`experiments/d9-rc-receiver-probes-20260926/snapshot_callback.my`. A receiver selected
as `rows[0]` must remain independent of a snapshot of `rows` published by its later
argument callback. RC passes. The accepted stage-3/4pre GC compiler at `f6bea5d9`,
SHA-256 `8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`,
fails this fresh test, as does current default GC. The fixture is preserved outside
the normal guest gate until a separate GC pinning correction is integrated; this
is an outstanding correctness issue, not a waived RC acceptance condition.

Complete logs, identities and direct execution counts are preserved in
[evidence/d9-rc-receiver-lowering.json.gz](evidence/d9-rc-receiver-lowering.json.gz).
This commit is a bounded integration slice, not WP-4 acceptance.
