# C: owned resource reads and writes

Status: source and backend reads/writes are implemented for injected filesystem
and network resource providers. Operations retain ownership and expose partial
progress. Fixed byte arrays are supported; the slice-based I/O, partial field move and
explicit arena/pool tracks this page once named were removed on 2026-09-13. [Resource permission
attenuation](attenuation.md) now limits acquisition and subsequent operations. The CLI still
provides no operating-system resource adapter or ambient authority.

```text
struct Chunk { bytes: [16]u8, length: u64, eof: bool }
result Read { ok: Chunk, err: i64 }
result Written { ok: u64, err: i64 }

let mut file = acquire_resource<Open>(fs, new [1]u8 [42u8])?;
let chunk = read_resource<Read>(file)?;
let written = write_resource<Written>(file, new [1]u8 [7u8])?;
```

Both operations require a live mutable resource binding. Reading may advance a
stream cursor, so it also requires `let mut`. Each operation leaves the owner
available for another read/write, transfer, completion, or fallback release. Wrong
resource types, moved owners, and immutable bindings fail checking. Reference/slice
names and arbitrary owner expressions are not accepted by this form.

A read's declared result has i64 error and a nominal record success containing
exactly `bytes: [N]u8`, `length: u64`, and `eof: bool`, in any field order. It makes
one provider call, returns the reported prefix as an immutable snapshot, and zeros
all unused capacity. EOF is explicit and may accompany a nonempty final chunk.
A short or zero-length read alone does not imply EOF; a zero-capacity read still
uses the provider's explicit EOF indication. There is no automatic refill loop.

A write's result has u64 success and i64 error. The input is a fixed `[N]u8` array.
Expressions producing those bytes evaluate before owner access; consuming the owner
in an input expression makes the subsequent write invalid. One provider call returns
its actual accepted byte count, which may be zero or less than the input length.
There is no implicit write-all loop, retry, durable flush, or completion. Callers
must inspect progress and apply an explicit policy; writing a read buffer's entire
fixed array would include its padding, so only intentionally constructed data
should be passed until slice/range I/O is added.

## Provider and error contract

`external_resources.Provider` has optional synchronous `read` and `write` callbacks.
Existing lifecycle-only providers remain valid; an absent operation returns
recoverable `Unavailable = 1`. Other recoverable errors remain `Denied = 2` and
`Failed = 3`. Provider `OutOfMemory` is a host failure. Buffers are borrowed only
for the callback; providers must not retain them. Callbacks report actual progress,
keep the host handle live on success and error, and cannot exceed supplied bounds.
The runtime checks returned counts; an invalid count produces host `InvalidProvider`.

Safe source cannot duplicate the resource owner. Backend owner identity and
non-wrapping generation checks run before callbacks. Failed operations keep the
backend owner valid for retry or cleanup. The guest owner remains in its local slot
on recoverable errors. `try` propagation releases it only when leaving its owning
scope. Completion retains its separate consuming/result-returning contract.

An error can follow partial external work, and a successful callback can precede
host allocation failure constructing its result. Neither generic rollback nor
exactly-once external I/O is promised. Normal recoverable errors and host OOM unwind
owned handles under the existing trusted release contract. These operations do not
silently upgrade fallback cleanup into successful completion.

Reads, writes, and cleanup contribute the resource kind's filesystem/network effect,
including through wrappers and helper calls. Noio rejects them; noalloc retains its
guest buffer-backing meaning and does not constrain trusted adapter allocation.
Bytecode validates mutable owner metadata, result/input schemas, and independently
recomputes effects. VM checks validate provider/store ownership and values.
Read results reuse bounded byte-record validation and byte conversion shared with
environment lookup. Exact discovery is `exact-v22`, retaining I/O kind, owner slot,
input expressions, nominal result identity, and effect contracts.

## Acceptance

331 tests pass in Debug and ReleaseFast (297 core, 34 actual CLI). Tests cover partial
read/write counts, EOF with final data, raw bytes and zero padding, zero-capacity
operations, unsupported callbacks, stale owners, invalid provider counts, mutable/
move/type checks, consuming write arguments, noio bounds, recoverable write retry,
and all provider errors including host OOM. Allocation-failure sweeps exercise I/O,
result construction, completion, dumps, and discovery without leaked host owners.
Traps at every instruction boundary either release or complete the acquired resource
once. 10,000 read/write cycles fit within 16 KiB live VM storage under one resource.
CLI tests cover checking, dumps, denied execution without providers, and mutability
rejection across commands. Formatting/whitespace checks pass on the pinned Zig.


## Subsequent borrowed-slice integration

[Resource slice I/O](../legacy/experiments/resource-slices.md) now accepts shared/exclusive byte views for
writes and exclusive destinations for reads. It supports fixed arrays, owned buffers,
reference parameters, and returned/narrowed views, and can write only the populated
range. The fixed-array-only restriction above describes this earlier checkpoint.
