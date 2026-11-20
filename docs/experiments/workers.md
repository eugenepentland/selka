# Bounded isolated workers

Status: removed. `scripts/workers.py` is gone, and `examples/workers/run.py`,
which imported it, was deleted on 2026-09-24; `examples/workers/main.my` remains
an ordinary program. This page is the design record.

`scripts/workers.py` provides a host API for concurrent guest function calls. Each
worker is a separate compiler/VM process with its own arena, references, refcounts
and allocator bookkeeping. Source files and typed-call-v1 messages are copied
before submission returns. Only serialized typed-json-v1 output returns to the
caller; borrowed references, owned resources and capability arguments cannot
cross this boundary. There is no guest spawn syntax or shared-memory threading
in this first model.

Run a complete application:

```sh
python3 examples/workers/run.py --compiler zig-out/bin/mylang
# {"sum": 136, "squares": 1496}
python3 tests/workers.py --compiler zig-out/bin/mylang
```

The example submits four numeric batches, executes up to two simultaneously and
combines their typed results. Use `Pool.schema(sources)` followed by
`schema_identity(result.output)` to create requests pinned to the exact exported
schema. Each result also records compiler, source and request SHA-256 identities.
The compiler binary is copied once per pool. A versioned, sorted source manifest
includes the entry path and each source file's content hash, so identities remain
stable across temporary directories and caller dictionary order. Rebuilding the
original compiler or changing caller source/message buffers cannot change an
already-admitted job.

The default pool admits eight running/queued jobs, runs two processes at once,
and limits each source snapshot to 2 MiB, request and response to 1 MiB, diagnostics
to 64 KiB and runtime to ten seconds. VM invocation additionally has instruction,
frame, codec-call and codec-memory budgets. Results publish only after successful
exit and complete response validation. Failed, cancelled, timed-out and oversized
responses publish no partial output. Completed results are caller-owned bytes;
callers remain responsible for retaining a reasonable number of those results.
These are admission/message/runtime limits, not a hard operating-system RSS cap.

`cancel(job)` terminates the process group, escalates to kill after a bounded grace
period if necessary, reaps it and deletes its snapshot before returning. Cancelling
a queued job does not launch it. `wait(job)` services other workers while joining
one result. Use the pool as a context manager: exit cancels and joins every
unfinished process before deleting the compiler snapshot. No worker can retain
caller arena storage because none is passed to it. Cooperative shared-memory
cleanup is unnecessary; each process owns its entire guest memory lifetime.

The coordinator API belongs to its creating thread and rejects calls from another
thread. Child stdin and inherited descriptors are closed; no host registry,
filesystem/network grants or parent environment capabilities are provided. The
normal checked invocation rules still reject references and effectful functions.
This is execution/lifetime isolation, not an operating-system sandbox for a
compromised compiler. The implementation currently requires POSIX process groups.

Tests execute real language programs and check two launched child processes,
copied-buffer mutation, stable identities, bounded queue admission, running and
queued cancellation, process reaping, reuse after cancellation, deadline/output
and step limits, scope cleanup, stale schema rejection, denied reference/provider
arguments and coordinator-thread ownership.
