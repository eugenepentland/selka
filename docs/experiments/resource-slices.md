# C: resource I/O through borrowed byte slices

Status: resource reads into exclusive byte slices and writes from shared/exclusive
byte slices are implemented for fixed arrays and owned buffers. Existing narrowed
views, reborrowing, reference parameters, and returned-view contracts apply. Partial
field moves, arenas/pools, and other roadmap tracks remain pending.

```text
struct Progress { length: u64, eof: bool }
result Read { ok: Progress, err: i64 }
result Written { ok: u64, err: i64 }

let mut count = 0u64;
borrow mut bytes[0..4] as destination {
    let progress = try read_resource_slice<Read>(file, destination);
    count = progress.length;
}
borrow bytes[0..count] as input {
    let written = try write_resource_slice<Written>(file, input);
    // Inspect written to decide whether another write is needed.
}
```

The resource must remain a live mutable binding. The second operand names an active
slice of u8 elements. Reads require an exclusive slice, including an exclusive
reference parameter; writes accept shared or exclusive slices. A suspended parent
view, expired view, wrong element type, whole-value reference, or shared destination
cannot bypass the existing borrow checks. The resource and slice remain owned/active
after a recoverable result. Ending their scopes follows the existing cleanup rules.

Read results have i64 error and nominal record success containing exactly
`length: u64` and `eof: bool`, in either field order. One provider call receives the
selected slice's capacity. Success replaces only the reported prefix of that slice;
the unread suffix and all bytes outside it remain unchanged. EOF is explicit, even
for empty slices. Existing fixed-array snapshots remain valid and unchanged.

Write results have u64 success and i64 error. One provider call receives exactly the
selected bytes, so callers can write a populated prefix or remaining subrange without
including capacity padding. Reported progress may be partial or zero; callers choose
retry/progress policies explicitly. No hidden write-all or read-fill loop is added.
Resource permissions, provider availability, error codes, and explicit completion
retain the [resource I/O](resource-io.md) and [attenuation](attenuation.md) contracts.

## Staging, costs, and failure behavior

Guest memory is not exposed as an unchecked host pointer. `byte_slices.Prepared`
checks the lease, permission, element type, and range before invoking the resource
provider. Host scratch storage stages each operation. Writes copy the selected bytes
into that storage. Reads stage provider output before changing guest storage.

For fixed-array destinations, an immutable replacement array is prepared before the
provider call, then updated once and installed after success. This copies the array
storage, preserving earlier snapshots and avoiding one array copy per byte. Owned
buffer destinations update their initialized elements directly after successful
staging. Neither route grows guest buffer capacity. Staging/result metadata still
uses the host allocator; no zero-copy or physical host no-allocation guarantee is
claimed. Read cost includes scratch capacity and, for fixed arrays, their full
replacement storage; writes copy the selected slice.

Recoverable provider failure leaves destination bytes unchanged, even if the provider
wrote its scratch buffer before returning an error. A successful read commits its
reported prefix. A later host failure constructing the guest result is terminal and
does not undo that successful I/O or destination update. External stream position
and other provider effects are not transactional. Providers must not retain borrowed
buffers or reenter the VM/its memory while a callback is in progress.

Runtime lease checks remain active for empty slices and catch suspended/read-only/
invalid views before I/O. Source effect inference and independent emission validation
include the resource kind's filesystem/network effects, ownership cleanup, and the
resolved slice metadata. Internal bytecode checks reject invalid reference IDs,
permissions, types, and operand schemas. Exact discovery is `exact-v24`, retaining
slice reference identities in addition to owner, I/O kind, inputs, and result types.

## Acceptance

351 tests pass in Debug and ReleaseFast (315 core, 36 actual CLI). Tests cover prefix
updates with untouched suffix/outside bytes, immutable array snapshots, initialized
owned buffers, writes of exact populated ranges, shared/exclusive/type/scope checks,
suspended parents, returned narrowed views through parameters, empty slices with EOF,
provider errors after scratch writes, and malformed bytecode metadata.

Allocation-failure sweeps cover preparation, I/O/results, dumps, and discovery while
unwinding resources and borrows. Every instruction-budget boundary of fixed-array
and owned-buffer scenarios releases live resources. 10,000 slice read/write cycles
fit within 16 KiB live VM storage and release all allocations. CLI fixtures cover
checking, dumps, missing-provider denial, and shared-destination rejection across
commands. Formatting and whitespace checks pass on Guardian's pinned Zig snapshot.
