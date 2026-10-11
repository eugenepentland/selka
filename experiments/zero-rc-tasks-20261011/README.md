# Stage 5: moved task captures (qualified backend prototype)

This branch has a Core IR task boundary and a native scheduler, but no source
syntax for launching tasks. This experiment extends that existing boundary; it
does not introduce a source task API or admit borrowed captures.

A group owns task handles. Submission transfers an environment box into the
group, the callback borrows it, and completion destroys it. The callback returns
an independent owned result. Taking a result removes it from the task slot.
Explicit group end and automatic group destruction both join pending tasks;
untaken results are destroyed with their handles. Scheduler synchronization
atomics are required and are not reference counts.

The fixture submits 64 independent mixed captures, each containing a string and
an integer list. Every third callback returns an error union; the others return
a record containing a list of strings. Each callback also indexes an ASCII
character, exercising the shared static character table. Its initialization now
uses `pthread_once`, preventing concurrent first-use writes. One variant takes 32 results and leaves
32 for group destruction, using one transferred result after group destruction.
The other exits with all results still in the group. Both run at 1, 2, and 8
threads, in unoptimized and verifying optimized configurations. Separate
ThreadSanitizer runs check cross-thread publication and cleanup. A negative IR
case reuses a moved capture; the zero-RC lowering guard must reject it.

All 212 counted executions passed the strict whole-program RC and managed-leak
audit: 12 matrix executions plus 200 repeated 8-thread executions. All 206
ThreadSanitizer executions passed: six matrix executions and 200 repetitions.
The invalid moved-capture case was rejected. Forty focused zero-RC and existing
task regressions passed before the ASCII fix; five tests covering both the
expanded fixture and existing mixed tasks passed after it. All 88 whole-tree
Guardian checks passed. [validation.json](validation.json) records hashes and
validation order; frozen final binaries are under
`.tmp/zero-rc-tasks-20261011/fixtures-final/`.

The 64-task release fixture performs 623 managed allocations and allocates
42,752 cumulative managed bytes. The take-results variant peaks at 17,824
managed bytes in the saved 1- and 8-thread samples; discarding all results peaks
at 19,680 in the saved 8-thread sample. Every run exits with zero live managed
bytes and zero runtime retains/releases. Scheduling can affect peaks. These
are absolute measurements, not a claim of lower memory than an equivalent RC
implementation; no paired RC task fixture was measured. Scheduler rings,
thread stacks, raw work buffers, allocator retention and process RSS are outside
the managed-block counters.

This completes the moved-capture prototype at the existing backend boundary.
Borrowed captures, source task syntax, escaping task handles and detached tasks
remain unavailable. The task failure coverage is recoverable error results;
a process-fatal trap still terminates the process. Static ownership and mandatory
joins are distinct from scheduler atomics, result-index checks and allocation.

Reproduce the matrix with the pinned Zig compiler and
`zig build test-core -Dtest-filter='zero RC task'`. Set
`MYLANG_ZERO_RC_TASK_OUTPUT` to export the fixtures. Then run
`repeat.py --fixtures <export-directory> --output <evidence-directory>` for the
100 repetitions of each release/sanitized variant at eight threads.
