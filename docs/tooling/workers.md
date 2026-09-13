# Isolated workers

The language has no spawn syntax and no shared-memory threads. Parallel work is
instead arranged by a host: `scripts/workers.py` runs guest function calls in
separate compiler processes and copies typed messages in and out. The design
record is [bounded isolated workers](../experiments/workers.md).

## Isolated process workers

Each worker is its own process with its own arena, references, refcounts and
allocator bookkeeping, so no guest memory lifetime is shared and no cooperative
cleanup between workers is needed. Source files and `typed-call-v1` request
messages are copied before `submit` returns, and only serialized `typed-json-v1`
output comes back: borrowed references, owned resources and capability arguments
cannot cross the boundary, and the ordinary checked invocation rules still reject
effectful functions. Requests are pinned to an exact exported schema, and every
result records the compiler, source and request SHA-256 identities, so rebuilding
the compiler or mutating a caller's buffers cannot change a job that was already
admitted. The default pool admits eight running or queued jobs, runs two
processes at once, and bounds each source snapshot to 2 MiB, request and response
to 1 MiB, diagnostics to 64 KiB and runtime to ten seconds; results publish only
after a successful exit and a complete response validation, so failed, cancelled,
timed-out and oversized jobs publish nothing partial. `cancel` terminates the
process group, escalates to a kill after a bounded grace period, reaps the child
and deletes its snapshot; using the pool as a context manager does the same for
every unfinished process on exit. These are admission, message and runtime
limits, not an operating-system memory cap or a sandbox for a compromised
compiler, and the implementation currently requires POSIX process groups.

```console
$ python3 examples/workers/run.py --compiler zig-out/bin/mylang
{"sum": 136, "squares": 1496}
```
