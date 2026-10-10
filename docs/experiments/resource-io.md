# C: owned resource reads and writes

Status: source and backend reads/writes are implemented for injected filesystem
and network resource providers. Operations retain ownership and expose partial
progress. Fixed byte arrays are supported; the slice-based I/O, partial field move and
explicit arena/pool tracks this page once named were removed on 2026-09-13. [Resource permission
attenuation](attenuation.md) now limits acquisition and subsequent operations. The CLI still
provides no general operating-system resource adapter and no ambient authority: the
filesystem provider it does register is scoped to the same directory grants as
`open`.

```mylang
# doc: check
resource File: filesystem

result Open:
    ok: File,
    err: int

record Chunk:
    bytes: FixedArray[u8, 16]
    length: u64
    eof: bool

result Read:
    ok: Chunk,
    err: int

result Written:
    ok: u64,
    err: int

result Status:
    ok: int,
    err: int

func work(fs: Filesystem) -> Status effects(filesystem):
    mut request: FixedArray[u8, 1] = FixedArray[u8, 1]([42u8])
    mut file = try acquire_resource[Open](fs, request)
    mut chunk = try read_resource[Read](file)
    # The count reports actual write progress. This example sends one byte.
    mut payload: FixedArray[u8, 1] = FixedArray[u8, 1]([7u8])
    mut written = try write_resource[Written](file, payload)
    return Ok(int(chunk.length) + int(written))


func main(fs: Filesystem) -> int effects(filesystem):
    match work(fs):
        case Status.ok(value):
            return value
        case Status.err(code):
            return -code
```

The program above is the whole surface of this page;
[`examples/resource-io.my`](../../examples/resource-io.my) is the same program as
a standalone example.

Both operations take their owner from a live binding and leave it owned by the
caller, so the owner stays available for another read/write, transfer, completion,
or fallback release; reading may advance a stream cursor. Wrong resource types and
moved owners fail checking, and the owner operand must be a name rather than an
arbitrary expression, so `read_resource[Read](pick(fs))` is rejected where
`file = pick(fs)` followed by `read_resource[Read](file)` is accepted.

A read's declared result has a 64-bit `int` error and a nominal record success
containing exactly `bytes: [N]u8`, `length: u64`, and `eof: bool`, in any field
order. It makes one provider call, returns the reported prefix as an immutable
snapshot, and zeros all unused capacity. EOF is explicit and may accompany a
nonempty final chunk. A short or zero-length read alone does not imply EOF; a
zero-capacity read still uses the provider's explicit EOF indication. There is no
automatic refill loop.

A write's result has u64 success and int error. The input is a fixed `[N]u8`
array. Expressions producing those bytes evaluate before owner access; consuming
the owner in an input expression makes the subsequent write invalid. One provider
call returns its actual accepted byte count, which may be zero or less than the
input length. There is no implicit write-all loop, retry, durable flush, or
completion. Callers must inspect progress and apply an explicit policy; writing a
read buffer's entire fixed array would include its padding, so only intentionally
constructed data should be passed until slice/range I/O is added.

## Provider and error contract

A resource provider has optional synchronous `read` and `write` callbacks.
Existing lifecycle-only providers remain valid; an absent operation returns
recoverable `Unavailable = 1`. Other recoverable errors remain `Denied = 2` and
`Failed = 3`. Provider out-of-memory is a host failure. Buffers are borrowed only
for the callback; providers must not retain them. Callbacks report actual progress,
keep the host handle live on success and error, and cannot exceed supplied bounds.
The runtime checks returned counts; an invalid count produces host `InvalidProvider`.

Safe source cannot duplicate the resource owner. Owner identity and non-wrapping
generation checks run before callbacks. Failed operations keep the owner valid for
retry or cleanup, and the source binding keeps its owner on a recoverable error:
`?` propagation releases it only when the enclosing scope exits. Completion retains
its separate consuming, result-returning contract.

An error can follow partial external work, and a successful callback can precede
host allocation failure constructing its result. Neither generic rollback nor
exactly-once external I/O is promised. Normal recoverable errors and host
out-of-memory unwind owned handles under the existing trusted release contract.
These operations do not silently upgrade fallback cleanup into successful
completion.

Reads, writes, and cleanup contribute the resource kind's filesystem/network effect,
including through wrappers and helper calls. `noio` rejects them. The examples
use `effects(filesystem)` to describe guest authority; this legacy effect list
permits implementation allocation by resource adapters and result boxes.
Explicit `noalloc` additionally forbids those Core may-allocate sites, including
permission attenuation that creates a new capability block.
Lowering validates mutable owner metadata, result/input schemas, and independently
recomputes effects before emission. Read results reuse the bounded byte-record
validation and byte conversion shared with environment lookup. Exact discovery is
`exact-v22`, retaining I/O kind, owner slot, input expressions, nominal result
identity, and effect contracts.

`mylang run` registers a filesystem provider over the same directory authority as
`open`, and that provider accepts only requests naming a granted path; the
one-byte request here names none, so acquisition is denied and
`examples/resource-io.my` returns the recoverable `Denied = 2` code as `-2`.

## Checkpoint record

The acceptance evidence below was recorded against the bytecode runtime that was
this language's only runtime until 2026-09-14, and against the explicit storage
tier removed on 2026-09-13. It is kept as the record of what the experiment
established, not as a description of the current runtime.

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

The later borrowed-slice experiment ([resource slice I/O](../legacy/experiments/resource-slices.md))
accepted shared/exclusive byte views for writes and exclusive destinations for reads,
over fixed arrays, owned buffers, reference parameters and returned/narrowed views,
and could write only the populated range. Those reference and slice types went with
the explicit storage tier on 2026-09-13, so the fixed-array form above is what the
current surface offers.
