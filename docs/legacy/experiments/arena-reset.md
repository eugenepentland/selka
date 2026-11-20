# C: explicit arena reset with typed results
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

`reset_arena<Result>(allocator)` now releases unused backing chunks within an active
lexical arena. The result declaration must have `ok: bool` and `err: i64` payloads.
Success returns `true`; it does not report a byte count or retained-capacity outcome.

```text
result Status { ok: bool, err: i64 }
arena heap as scratch {
    let buffer = try acquire_buffer<Open>(scratch, 16);
    // Use the buffer, then release its owner before reclaiming arena chunks.
    discard buffer;
    discard try reset_arena<Status>(scratch);
    let next = try acquire_buffer<Open>(scratch, 16);
}
```

Reset keeps the scope and its allocator capability valid. Existing capability copies
can allocate afterward, and normal scope exit still closes the region. The operation
frees all unused arena chunks without allocating backing and is permitted under
`noalloc`. The existing VM distinction still applies: result/stack bookkeeping may
allocate through the host allocator and can fail with `OutOfMemory`.

| Error code | Meaning |
| --- | --- |
| `1` | Buffer/pool owners or embedding backing leases still retain this region |
| `2` | Child regions are still active |
| `3` | Capability is invalid, foreign, closed, or the execution/root allocator |

Child checks precede backing-user checks. Rejection leaves storage, owner identity,
borrowed views, and capability authority unchanged. The ordinary execution allocator
is not a lexical arena, including with `--memory=arena`; root reset therefore returns
error `3`. The separate embedding `Arena.reset` API keeps its existing contract.

Every buffer and pool pins its backing, including zero-capacity owners. Clearing a
pool invalidates its node IDs but retains its registry allocation, so the pool owner
must also be released before its arena can reset. Borrowed buffer views necessarily
keep their owner backing live. Reset does not silently destroy live owners or invalidate
borrowed views. Use lexical cleanup or explicit ownership transfer/discard first.

Snapshots use the execution allocator and can survive reset after their pool owner
is destroyed. Inert IDs may remain, but a new pool still has a distinct identity;
reset cannot make a destroyed pool's IDs valid again. Reset never changes buffer/pool
quotas or region-slot identity, so allocator copies cannot bypass shared limits.

Like other fallible operations, reset requires matching, propagation, transfer, or
explicit acknowledgement. Ordinary discard rejects the result. A helper taking an
allocator can perform reset and return its typed status without allocating guest
backing. The existing arena escape analysis is unchanged because a bool/i64 result
contains no regional storage or capability.

`src/arena_reset_test.zig` covers live-buffer/borrow and child rejection, copied
capability reuse, root/foreign/closed rejection, pool pinning across clear, independent
snapshots, physical chunk reclamation, all host allocation failures, every instruction
budget through completion on both execution backends, result obligations, noalloc
helpers, duplicate identity, and invalid bytecode result schemas. Its long-lived-arena
fixture performs 10,000 reset cycles and 20,000 buffer acquisitions within 16 KiB live
runtime storage. Removing reset from that fixture exhausts the same bound; both paths
unwind to zero bytes. These are fixture bounds, not universal memory guarantees.

`examples/arena-reset.my` returns `3` after checking failures, resetting an empty child
without closing it, and successfully resetting/reusing its parent. Actual CLI tests
run/check/dump the fixture and preserve diagnostics across analysis commands.
Formatting round trips now cover 32 valid fixtures. Exact discovery is `exact-v28`;
reset remains a distinct checked operation. Native emission still reports
`E_NATIVE_FEATURE` for the unsupported arena/capability operations.
