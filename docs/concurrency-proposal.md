# Concurrency proposal: scoped tasks with isolated data

Status: design proposal, not implemented or accepted. Reviewed against checkout
`244f747` on 2026-09-13. All examples below are proposed syntax, not executable
documentation. No compiler build or Guardian gate was run for this review.

The [WP-5 D9 design](audits/d9-wp5-concurrency-design-2026-09-26.md) now refines
this historical proposal for value semantics, RC ownership/holds, native tasks
and acyclic heaps. That follow-up is also a proposal; implementation waits for
WP-4 acceptance. The older VM, GC and cycle-preserving statements below remain
as historical context, not the current implementation contract.

The design goal is ordinary Python-shaped functions, Go-like blocking calls,
automatic task lifetime management, and explicit access to more control.

## Recommendation

Make `parallel.map` the first thing application authors learn. Underneath it,
provide scoped tasks and typed channels. Each task owns its mutable heap;
arguments and results cross task boundaries as snapshots. The runtime schedules
tasks over a bounded pool of OS threads. A task is not an OS thread or a process.

Use the same task semantics for I/O and CPU work. No `async def`, mandatory
`await`, or separate process-pool programming model. Ordinary calls remain
sequential; only explicit concurrency operations start additional tasks.

This borrows ordinary blocking function calls and channels from
[Go](https://go.dev/doc/effective_go#concurrency), scope-bound task lifetimes from
[Python TaskGroup](https://docs.python.org/3/library/asyncio-task.html#task-groups),
and isolation of mutable objects from
[Dart isolates](https://dart.dev/language/concurrency). It does not adopt those
languages' complete scheduling, error, or object models.

The cost is copying and per-task execution state. This is a substantive tradeoff:
benchmark fine-grained work and large graphs before committing to this default.

## What existing language behavior supports this

- [Python syntax](python-syntax.md) already gives ordinary functions, typed
  records, aliased mutable collections, and checked `Result` propagation.
- [Managed arenas](managed-memory.md#retired-arenas) (since retired) gave the intended progression: ordinary types
  first, explicit lifetime control when needed. Concurrency can use that pattern.
- [Process workers](experiments/workers.md) already establish copied requests,
  isolated execution, bounded admission, cancellation, and scope cleanup. Their
  current typed JSON transport does not support arbitrary managed graphs or
  capabilities; it is a precedent, not a ready implementation of this proposal.
- The former VM (`src/vm.zig`, since removed) had explicit frames, locals,
  operands, owners, borrows, provider state, and arena stacks. These were useful
  ingredients for a resumable execution context, but `runValues` then ran one
  execution to completion. The current WP-5 design uses native execution.
- [Effects](../src/effect_set.zig) are inferred transitively. Add a suspension
  effect and an optional `nosuspend` bound, including through callbacks and host
  declarations. Today that effect does not exist. `nogc` and `noalloc` must not
  accidentally acquire a non-suspension guarantee.

The QBE back end and its managed lowering were retired in October 2026 (S5); the
new compiler core lowers through Core IR and LLVM. Backend support must be checked
against implementation and acceptance tests, not inferred from one older document.

## The easy path

```text
# Proposed API; analyze returns Result[Report, AnalysisError].
reports = parallel.map(analyze, files)?
```

The helper uses bounded active work and bounded pending submissions, preserves
input order in the result, and cancels and joins remaining work on the first
observed failure. It returns a checked error containing the failed input index
and the underlying error. It does not create one live task for every input in a
million-element list. Output storage still grows with output size; a streaming
variant can come later.

For different operations, expose the underlying scope:

```text
# Proposed syntax; referenced application types/functions are illustrative.
def page(id: int, net: NetworkCap) -> Result[Page, TaskError[FetchError]]:
    with TaskGroup() as group:
        user_task = group.spawn(fetch_user, id, net)
        orders_task = group.spawn(fetch_orders, id, net)
        user = user_task.result()?
        orders = orders_task.result()?
        return Ok(Page(user=user, orders=orders))
```

Both calls start before either result is requested. `result()` parks the calling
task when necessary. Network operations also park tasks rather than occupying a
worker thread while waiting. The capability here requires a new explicit
delegation contract; the existing worker API cannot pass `net`.

Every child belongs to a group. Leaving it always joins its children; propagating
an error or cancellation first requests cancellation of unfinished children.
Returning successfully while leaving unobserved task outcomes is a checker
error. Task handles are scoped, must-handle values and cannot escape the group.
An explicit cancel-and-join operation can satisfy that obligation while still
reporting a failure that completed before cancellation.

Keep domain errors as values. For a child returning `Result[T, E]`, the proposed
`result()` returns `Result[T, TaskError[E]]`: one wrapper covering the child's
domain error, cancellation, and deadline expiry, with no double `??`. Infallible
child functions need only the runtime error alternatives. Guest traps keep their
diagnostic identity and abort the enclosing execution after cleanup.

Unlike `parallel.map`, a primitive task returning `Err` does not immediately
cancel its siblings: the parent may intentionally inspect and handle that
outcome. In the example, cancellation starts when `?` propagates an observed
error. If `orders_task` fails first, waiting on `user_task` can delay observing
it. A later fail-fast collector can watch all handles, with typed aggregation;
do not invent implicit exception propagation to hide this distinction.

## The most important rule: crossing a task boundary snapshots data

```text
items = [1, 2]
with TaskGroup() as group:
    task = group.spawn(total, items)
    items.append(3)
    answer = task.result()?
# answer is 3; the parent items is [1, 2, 3].
```

Ordinary calls and assignment retain today's aliasing semantics. Only task
submission and channel delivery introduce the snapshot boundary. Mutable
descendants must be copied, including lists inside value records. Preserve
cycles and repeated references across all arguments of one submission using
one graph-copy map. Different submissions receive independent snapshots.

Submission finishes its snapshot before the parent can mutate the inputs again.
Results are copied into the receiving task's current allocation region before
the producing heap is destroyed. A channel queue owns its message independently
of either task and any sender arena. Cancellation releases queued ownership.

Check admissible types structurally at the boundary, explaining the offending
field path. Ordinary data needs no user-authored `Send`/`Sync` declarations.
References, raw pointers, arena bindings, and resource owners are not copied.
Channels and explicitly delegable capabilities have separate runtime contracts.
Delegation must preserve shared quotas and cannot amplify filesystem/network
authority. Reject providers without a supported delegation adapter.

This prevents unsynchronized access to ordinary mutable guest objects across
tasks. It does not prevent protocol deadlocks, conflicting filesystem writes,
or database races.

## Progressively more control

| Need | Proposed escape hatch |
| --- | --- |
| Limit throughput or memory | `parallel.map(..., limit=8)`, group task/message budgets, deadlines, cancellation |
| Build a pipeline | Typed `Channel[T]`, blocking send/receive, bounded capacity, explicit close and end-of-stream |
| Maintain state across jobs | A long-lived task that owns the state and receives commands; an actor library can wrap this |
| Reuse large read-only inputs | `Frozen[T]`: a deep immutable snapshot with a lifetime independent of any task or arena |
| Transfer a large mutable payload without copying | A dedicated move-only transferable buffer or region, invalidating the sender |
| Control hardware placement | Explicit executor, thread count, affinity, or dedicated blocking worker |
| Share mutable storage for specialized code | Initially trusted host wrappers; later a distinct restricted `SharedBuffer`, locks and atomics if workloads justify it |

Start channels with rendezvous behavior (`capacity=0`); positive capacity gives
bounded buffering. Sending snapshots mutable data even when both tasks happen
to execute on one OS thread. A cancellable send is admitted atomically: it either
publishes one message or publishes none. Closing wakes waiters; receive drains
queued messages and then reports end-of-stream. A later select operation must
reserve only the winning operation, not perform speculative sends/receives.

Define pending-task limits separately from worker-thread count. Do not silently
block `spawn` waiting for a worker slot: a producer might need the parent to
spawn its consumer before it can finish. `parallel.map` can manage admission
because its independent-call contract is narrower. Primitive exhaustion should
be an explicit execution-budget failure, never an unexplained wait.

`Frozen[T]` must freeze the entire reachable graph, not merely its root. It can
initially copy and later share storage with independent lifetime management.
Moving an ordinary list binding is insufficient for zero-copy transfer: aliases
may reach its children from elsewhere. Require a dedicated ownership boundary,
or retain copying. Current GC root counts do not prove graph uniqueness.

These are staged extensions, not prerequisites for the first release. Ordinary
lists should not change their sharing semantics based on executor choice.

## Scheduling, memory, and cancellation

Only one worker executes a given task/heap at a time. Different heaps can execute
in parallel. Start with worker affinity if migrating provider state is unsafe.
Use scheduling/cancellation checkpoints at bounded VM intervals and native loop
backedges/calls; audit optimized paths too. A CPU loop must not starve its peer
tasks indefinitely. A step-budget trap is not a substitute for yielding fairly.

Task cancellation is cooperative unwinding with resource cleanup. It must wake
channel, join, timer, and I/O waits. Do not swallow cancellation as an ordinary
successful result. Preserve existing fallible completion obligations: cancelling
a file write is not a successful flush, and cannot undo already-visible effects.
A deadline requests cancellation; a non-cooperative foreign call may delay the
join. A process boundary is the option when bounded forced termination is needed.

Each isolated task has its own heap and arena stack. A child's allocations must
not accidentally inherit the parent's active scratch arena. Snapshot arguments
before that arena can end. This is materially simpler than allowing independent
tasks to suspend inside arenas on one shared heap: today's region-depth ordering
assumes a single nested stack. Task-local depth alone cannot distinguish two
unrelated arenas at the same depth; that alternative needs region identities and
ancestry-aware barriers, or an explicit restriction on arena suspension.

The current host interface is synchronous. It needs suspend/resume I/O adapters
or a bounded blocking-call executor with copied arguments and explicit provider
ownership. Calling today's blocking callback on a scheduler thread would block
every task assigned to that thread.

## Changes to the earlier audit's recommendation

The [earlier audit](audits/memory-concurrency-2026-09-13.md) recommends isolates
plus shared cooperative tasks within each isolate. I agree with isolation,
structured lifetimes, and channels, but would expose isolated tasks as the one
initial application model. Shared cooperative tasks preserve aliases and avoid
copies, but also introduce interleaving bugs across hidden suspension points and
a separate model for CPU parallelism. Revisit that choice if measured copying
or task overhead dominates representative applications.

Three other details need correction or qualification:

- A shared heap does not logically require a concurrent collector; a coordinated
  stop-the-world collector is possible. Its synchronization and rooting work,
  and ordinary shared mutation, are the reasons to defer it.
- Root reference count one does not establish exclusive ownership of a graph.
- A scheduler seed does not reproduce external I/O completion order, time,
  randomness, or parallel channel races. Reproducible tests need controlled
  scheduling plus recorded/replayed external events and communication choices.
  Existing sequential host transcripts and test-cache eligibility must be
  extended or conservatively invalidated for concurrent execution.

## Suggested first implementation

1. Specify snapshot, result, cancellation, and lifetime semantics with examples.
   Prototype graph transport for ordinary lists/dicts/records and cyclic data.
2. Refactor VM execution into resumable task state; implement groups, result
   waits, cancellation checkpoints, and strict resource cleanup on one worker.
3. Add bounded CPU parallelism and `parallel.map` over independent heaps. Verify
   allocator/provider ownership and immutable program metadata before sharing
   them. No compiler process or recompilation per task.
4. Add channels and suspendable I/O. Compare behavior on one and several workers.
5. Implement the same observable semantics for QBE. Existing native stack support
   is a starting point, not a scheduler: resumable stacks, per-task context,
   rooting, cleanup, and host integration all need acceptance coverage.
6. Measure startup latency, memory per parked task, throughput, copy volume,
   cancellation latency, and incremental compile/test cost. Add frozen data or
   transferable storage only where measurements establish a need.

Acceptance should cover alias-preserving snapshots, parent mutation immediately
after spawn, sender-arena exit, pending-message roots under GC stress, child
failure during sibling I/O, cancellation at each resource transition, quota
preservation, CPU-loop fairness, channel close races, and wait-cycle diagnostics.
Run semantic parity across VM/native execution and worker counts as supported.
