# WP-5 design: structured tasks over D9 ownership

Status: proposed design, not accepted or implemented. WP-4 performance acceptance
is pending. This document authorizes no concurrency runtime work before that gate.
It refines [WP-5](d9-closeout-plan-2026-09-26.md#wp-5-concurrency), not the stage-4
acceptance criteria in [D9](../adr/D9-value-semantics-then-rc.md).

## Sources and changes from the earlier proposal

The starting point is [the September 13 proposal](../concurrency-proposal.md):
ordinary blocking functions, bounded task groups, snapshots at submission,
checked outcomes, cancellation followed by joining, and explicit capability
delegation. Its VM-first implementation order, shared ordinary aliases,
cycle-preserving transport and tracing-heap assumptions are historical. The
current implementation targets QBE and LLVM native execution; D9 values are
independent, its RC heap is acyclic, and arenas remain.

D9 and the close-out plan attribute structured tasks and counts that become
atomic at task boundaries to the Weft design draft dated September 24. No
standalone draft or structured-task implementation was found in the available
local documents/projects. The `weft-n2` directory is another mylang worktree,
not evidence of an independent Weft implementation. Accordingly, only those two
requirements are attributed to Weft here. Syntax, scheduler, promotion protocol
and all acceptance thresholds below are proposals requiring review.

The current constraints come from [native_rc.h](../../src/native_rc.h),
[native_rc_internal.h](../../src/native_rc_internal.h),
[native_rc_alloc.c](../../src/native_rc_alloc.c),
[qbe_runtime.h](../../src/qbe_runtime.h), the
[held mutation contract](d9-rc-held-mutation-2026-09-26.md), and
[live-view cycle admission](d9-rc-live-view-acyclicity-2026-09-26.md).
The old [process workers](../experiments/workers.md) have been removed; they
supply historical semantics, not an available scheduler or transport.

## Proposed application contract

The initial surface is `parallel.map` over independent calls, followed by scoped
`TaskGroup` and bounded channels. All names are illustrative, not new syntax.
Ordinary calls remain sequential. A group owns every child; handles cannot
escape, be stored in ordinary aggregates, or be discarded without observing an
outcome or explicitly cancelling and joining. No detached tasks are included.

Submission evaluates arguments in source order and completes one snapshot
transaction before returning. Each evaluated argument keeps ordinary call
capture/pin semantics while later arguments are evaluated; transport must not
defer an earlier snapshot past a later mutating argument expression. One memo
then relates the finalized operand values. A successful submission publishes
exactly one child; failure publishes none and leaves every input usable.
Rollback does not undo external effects already performed while evaluating
argument expressions. Parent and child
may mutate their own values afterwards without seeing one another's writes.
Canonical function calls return owned results; the compiler's borrowed alternate
entry ABI never crosses a task boundary. A `mut` parameter or second-class
reference cannot be a spawned entry parameter in the first version. A wrapper
can instead accept a value, make a local binding, and call a mutating helper.

`result()` consumes its handle once and yields `Result[T, TaskError[E]]` for a
child returning `Result[T,E]`. Domain errors remain inspectable values. They do
not cancel primitive siblings until the parent propagates the error or requests
cancellation. `parallel.map` watches all active children, preserves input order,
and cancels and joins remaining work on its first observed failure. Simultaneous
failures need a recorded observation order; scheduling does not promise the
lowest failed input index is observed first.

Pending tasks, runnable tasks, worker threads, parked stack bytes, and queued
message bytes have separate limits. `spawn` refuses exhausted admission rather
than parking for a worker that may need another child to make progress. `map`
can pace independent jobs and must not allocate a million live task records for
a million inputs. Completed output size is still charged.

## O, H, pins and the boundary packet

O is semantic ownership; H is a nonsharing lifetime token. Local uniqueness
continues to ignore H, and retirement requires both O and H to be zero. A pin
adds its hold and imposes snapshot behavior during a pending mutation. Neither
H nor a pin grants authority to mutate another task's object.

| Boundary item | Proposed treatment |
| --- | --- |
| Plain scalar, inline plain value, immutable literal | Copy bits; no new managed token. Literal/code lifetime is the loaded program's lifetime. |
| Ordinary owner-bearing value | Snapshot into a packet, then establish owned receiving slots before dropping packet ownership. Each physical output edge receives one O. |
| Compiler borrow, argument loan, receiver cursor | Materialize a value through the semantic copy protocol while its anchor is alive. Never transmit an address into a frame. |
| Active pin or pending mutable receiver | Snapshot affected values; never move pin state, prepared slots or caller writeback authority into the child. |
| Persistent H edge, including a dictionary view | Clone its referent into the receiving task's identity graph, preserving H as H. It observes that task's dictionary, never the sender's subsequent mutations. |
| Arena payload | Copy reachable arena nodes into transport storage; no arena header is promoted or retained by another task. |
| Unique resource, raw pointer, host reference, arena binding | Reject without an explicit transfer/delegation adapter. Ordinary value transport must not infer ownership from pointer bits. |

One packet uses one iterative memo across **all** arguments, or all fields of a
message/result. This preserves repeated physical edges and the relationship
between a dictionary and a view referring to it within that snapshot. It does
not introduce source-level aliasing between ordinary value parameters: those
still detach on mutation. Distinct submissions have independent local identity
graphs. Recursive value types and DAG sharing are supported; existing acyclic
admission still applies.

An H-only referent may have O=0. Construction temporarily owns its new shell,
installs all O/H edges, acquires the destination H, and only then discharges the
shell's construction O. Failure drops exactly the initialized edges, including
partly built arena outputs. No step silently changes an H slot into an O slot.
Dynamic dictionary descriptors, canonical byte backing and live logical element
ranges follow the existing ownership adapters, not raw backing scans.

A packet has a unique runtime owner: producer, queue, consumer, or cancellation
cleanup. Release/acquire publication transfers that ownership; two workers never
operate on its private heap concurrently. The baseline copies identity-sensitive
nodes into a private delivery domain, then into the receiving task's heap before
releasing the packet. A prepared, not-yet-runnable child's heap can later serve
as the destination directly. Adopting a delivery domain without a second copy is
an optimization requiring allocator/metadata lifetime proof, not the baseline.

## Shared storage and atomic promotion

Use two physical reclamation domains:

- A **task-local domain** contains mutable objects, arenas, scope journals,
  allocator state, failure status and descriptor-walk scratch. Only its executing
  task, or the unique owner of an unpublished packet, accesses it.
- An **execution-owned shared domain** contains immutable, COW-safe heap objects
  that cross a boundary. It owns its allocator, metadata and release capacity
  independently of the task that first published an object. Counts and retirement
  transactions are synchronized. It survives until its last packet/task edge is
  released and all drains complete.

A shared object can refer only to immutable literals or other shared objects.
Dictionary headers and persistent H referents remain task-local in the first
version. An ancestor reaching such a node must also be copied locally at the
boundary; a shared ancestor must never retain a pointer into a task-local heap.
Share eligibility is established transitively by the transport plan, not by
checking the root kind alone. Shareable leaves beneath a copied dictionary may
still use the shared domain. Unique finalizers and provider state are never
embedded in shared ordinary objects.

This partition deliberately avoids applying `myl_rc_unique_held` concurrently:
today it can reuse O=0/H=1 or O=1/H>0 dictionary storage. Making its count words
atomic would not make those simultaneous reads and writes safe. Copying each
boundary's dictionary/view identity graph preserves live views inside one task
without silently changing them into lists or making them live across tasks.

The proposed reference protocol is:

1. Reserve task/queue admission, byte budget, descriptor bindings, iterative
   construction workspace and rollback journal before any publication.
2. Snapshot local input nodes into private output shells. Share-eligible shells
   are allocated in the shared domain; other shells belong to the delivery
   domain. Reuse already-shared immutable descendants with checked O acquisition.
3. Initialize all edges and counts. Complete invariants/adapter checks. Discharge
   construction tokens only after the packet owns the finished roots.
4. Publish the packet with release ordering; its consumer uses acquire ordering.
   Commit the admission receipt. Cancellation racing publication sees either no
   packet or one packet with one cleanup owner, never a partial graph.

This is **promotion by snapshot**. It gives a concrete correct first transport
without retaining the sender's entire heap or changing count access underneath
an existing alias. Its first crossing costs O(reachable copied nodes/edges).
Already-shared immutable storage can cross again by acquiring roots, without
recopying its closed shared descendants. That cost distinction must be measured.

**In-place promotion is deferred.** It could avoid the first copy only after
proving all of the following: allocator extents and native type identities can
outlive their allocating task; every reachable local descendant is promoted;
no persistent H identity or pin needs local mutation; the sender is at an
exclusive transition point; prior ordinary count accesses have completed; and
publication occurs after the final mode transition. Root O=1 is not that proof.
No ordinary instruction may cache an old non-atomic mode across a potentially
publishing call. A partial transition must remain private and safely releasable.

## Shared counts, death and demotion

Local values keep the WP-4 count and layout fast paths. Shared objects require
an explicitly versioned ABI and mode dispatch **before** any local O/H access.
The proposal does not reserve a header bit or promise today's 32-byte RC prefix
can hold every concurrency field. Arena and literal 16-byte prefixes remain
separate and must be recognized before any extended prefix access.

The initial shared-count reference implementation uses one per-object atomic
lock/state transition around O/H updates, overflow checks and the joint death
decision. It performs no allocation or callback while locked. Removing the last
token marks DYING and gives the releasing operation one exclusive retirement
token. It unlocks before publishing that token to a drain, then makes no further
header access. Nobody else can retire the allocation between those two steps. Acquiring from a raw/weak pointer without an already-live anchor is
forbidden. This is an atomic O/H transaction, not a proposed lock-free algorithm.

A pair of independent atomic decrements followed by ordinary zero tests is
insufficient: it can miss joint zero or race another final releaser. A later
packed state or lock-free scheme needs a memory-model proof, overflow policy,
exactly-once death, and safe completion of losing operations. It may not reduce
the supported count range silently. C atomic storage/access rules must be valid
on both native backends; casting today's plain words to atomic pointers is not
a specification. If atomic storage is used uniformly, local increments may use
exclusive loads/stores rather than synchronized read-modify-write operations;
validate emitted instructions and sequential overhead.

Shared immutability also strengthens uniqueness: **O=1 is never permission to
mutate a shared payload in place.** A write detaches the affected path into the
current task's local region; untouched shared children keep atomic ownership.
H still affects lifetime only. A local receiver may pin its detached object;
shared headers must not inherit today's mutable task-local pin bit protocol.

The baseline has no in-place demotion. A local copy is local immediately, but its
shared children stay shared. A full local rehome copies the required graph.
After join, O=1 does not prove the absence of another task's H, queued messages,
shared descendants, provider callbacks, weak probes or in-flight releases.
Optional in-place demotion requires a closed ownership domain, quiescence of all
participants and queues, complete O/H accounting, and an exclusive mode change.
Until those are proved and beneficial, once-shared storage remains synchronized
until destruction. Only objects that have crossed a boundary pay that policy.

## Allocator, metadata, budgets and bounded destruction

The current heap's descriptor stack, pending death list, weak dictionary cache,
allocator reuse epoch and sticky failure are mutable serial state. Atomic object
counts do not make one `myl_native_heap` concurrently callable. Tasks receive
separate `MylQbeContext` instances; no process-global active heap is introduced.
Immutable compiled code/frame maps may be shared, but task stacks, traps, resource
registries and provider execution state cannot be borrowed from the parent.

Shared descriptors must be registered and stable before publication. Each
executing drain gets exclusive, pre-reserved traversal storage; registration
must reserve enough capacity for every permitted drain before publishing a
shape that requires it. Alternatively, an initial serialized shared drain can
own one reserved walker. Its lock may protect queue transfer, but never encompass
a user finalizer or a local recursive drop. Shared objects have no guest
finalizers in the initial admissible subset.

Death remains intrusive and iterative. Enqueue exactly once, enumerate only live
logical edges, clear them, then retire storage. Release must neither allocate
nor recurse with graph depth. The baseline drains before its public release
boundary returns to guest code; task completion/join also waits for cleanup drains.
An asynchronous reclaimer would require a separate reclamation-latency contract.
Immediate allocator reuse invalidates weak probes;
shared caches must have an explicit synchronized lease/epoch contract or be
disabled. Do not reuse an address while an admitted probe still holds a lease.

The execution budget charges real task stacks, arena caches, descriptors,
transport scratch, packets, shared allocations and scheduler/wait records.
Objects are physically charged once; task/group admission reservations are
separate from that accounting. Shared/result charges outlive the producing task
until storage actually retires. A budget record cannot disappear with its task
while other tasks still reference its allocations. Refusal at any reservation
point publishes no task/message and rolls back all fresh tokens. Per-domain
count statistics must aggregate without double-counting transfers.

## Arenas, suspension and task lifetime

A task owns its arena stack. Suspending preserves its native stack, arena chunks,
registered edges and charges; migrating a task transfers exclusive execution of
that entire context. Start with worker affinity. Never interpret equal numeric
arena depths from different tasks as a lifetime relationship. Region identities
include task/domain identity at boundary validation; ordinary intra-task stores
can keep their existing depth rule.

The child starts with its own default heap region, not the parent's current
scratch arena. Argument snapshots finish before admission returns, so the sender
can close its arena while the child continues. Results/queued messages own
non-sender-arena transport storage before the producing task closes its arenas.
A receiving task may materialize local parts into its active arena, preserving
normal confinement/escape checks. Shared immutable references are older external
heap edges owned by that arena and released on its close.

Lexical cleanup order remains strict: a group inside an arena joins before the
arena closes. An arena inside a group may close before children finish because
no child retains its storage. During cancellation, pending I/O must first release
or cancel-and-acknowledge any pointer lease into the task before its arena can
close. A deadline does not justify freeing a buffer still used by a provider.
RC arena teardown keeps the existing all-finalizers, all-logical-edges, then
bulk-release order. Retained chunks remain budgeted under the RC contract.

## Completion, cancellation and resources

A task has one terminal outcome and one cleanup owner. Completion and cancellation
arbitrate through a synchronized task state; a published result remains a result
if cancellation loses that race. An unobserved completed result is still dropped
when its group cancels and joins. Cancellation is cooperative, not a cross-thread
`longjmp` or stack kill.

| Event | Required behavior |
| --- | --- |
| Successful child | Publish an owned result packet, finish local cleanup, then mark joined/completed. The parent cannot observe a result whose producer still owns an untracked temporary. |
| Domain `Err` | Publish the owned error payload; primitive siblings continue until their parent chooses propagation/cancellation. |
| Cancellation/deadline | Stop admission, wake channel/join/I/O waits, reach a safe checkpoint, cancel children, join, and unwind. No successful result is fabricated. |
| Guest trap | Preserve its code and source frames; cancel and join the execution's remaining tasks before reporting it. Bounded secondary cleanup failures do not overwrite the primary trap. |
| Host call that cannot cooperate | Join may be delayed; use a separate process for forced termination. A timeout must not pretend the thread has stopped. |

Checkpoints occur at bounded loop backedges/calls and suspendable operations,
including optimized loops. Count transitions and publication journals are
non-suspending critical sections. Nested task groups unwind before their owning
frames disappear. Restore pending mutation scopes/pins, end pointer leases, and
release initialized frame slots through the existing guarded cleanup contract.
Unique finalizers run once while their managed dependencies remain alive, before
those dependencies are dropped. Arena cleanup follows afterward in region order.
No shared-domain lock is held while finalization reenters guest code.

Closing an owned resource and successfully completing a fallible operation are
distinct. Cancellation cannot certify a file flush/commit or undo an external
write. Completion errors remain checked outcomes; cleanup still releases the
resource exactly once. Resource acquisition, partially initialized wrappers,
result publication and cancellation each need explicit journal checkpoints.

## Capabilities, channels and acyclic admission

[D8](../adr/D8-authority-is-an-argument.md) continues to govern authority. Spawn
never grants filesystem, network, entropy, environment, clock or host access
implicitly. A delegation adapter must retain immutable narrowed permissions,
share quota/revocation state safely, define callback affinity/cancellation, and
own its cleanup state. Copying today's context-relative capability bits is not
delegation. Unsupported providers fail structural boundary checking with a field
path. Unique resources remain local unless a future explicit move adapter proves
no outstanding borrow, exactly-once close and thread-compatible ownership.

Start channels with a bounded queue or rendezvous. Successful send commits one
owned packet; cancellation before commit commits none. A receive removes one
packet into its unique consumer owner, then materializes an owned value. Closing
wakes waiters; queued messages drain before end-of-stream. Closing/cancelling a
group drops orphaned messages and resolves wait registrations before freeing
channel state. A future select commits only its winner.

Task/group/channel control records live in an execution-owned registry with
explicit lexical close, not in arbitrary guest RC graphs. First-version scoped
handles/endpoints cannot be stored in messages or ordinary aggregates. This
avoids creating channel→message→channel retention cycles or escaped task handles.
First-class actor endpoints require a separate cycle/lifetime design and tests.
Wait-for deadlocks are distinct from heap cycles and need diagnostics/cancellation.

Keep the existing `LIVE-VIEW-ACYCLIC-1` stored-type SCC restriction, including its
conservative behavior for disjoint instances. No transport operation restores
legacy class cycles or adds a tracing fallback. `pool` ids are scalar links inside
an owned pool value; they do not by themselves authorize access to another task's
pool or constitute transferable unique pool ownership. Recursive ordinary data
and repeated DAG children use iterative memoization, never a fixed depth cutoff.
Capability adapters and runtime registries must also avoid hidden strong cycles.

## Compiler and scheduler migration

1. After WP-4 is accepted, freeze this semantic contract and diagnostics. Add a
   versioned task/transport artifact identity, structural boundary admission,
   and a transitive suspension/publication effect. The absence of allocation
   must not imply absence of suspension. Direct/indirect calls and host adapters
   carry the new summary; cache keys include it and the boundary ABI.
2. Implement the packet protocol and shared-count reference model independently
   of parallel scheduling. Preserve canonical owned calls. Reject a spawned
   borrowed alternate entry, caller storage address or borrowed return token.
3. Add one-worker native task groups, guarded stacks, result waits and cancellation.
   A task is not an OS thread. The existing native stack trampoline/frame maps
   are inputs to this work, not an already-resumable scheduler. Implement both
   backend contracts; do not revive the removed VM as an acceptance oracle.
4. Add bounded workers with affinity, shared reclamation and delegated providers.
   Only one worker executes a task/context at once. Host blocking uses a bounded
   executor with owned request buffers, or audited suspend/resume adapters.
5. Add `parallel.map`, then channels and I/O waits. Add replay events covering task
   admission, scheduling, communication choices and external completions. A seed
   alone is insufficient. Until replay is complete, concurrent tests cannot reuse
   sequential deterministic result-cache entries.
6. Consider in-place promotion, demotion, domain adoption, worker migration,
   transferable resources or first-class endpoints only against measured need
   and the additional proof obligations above.

All existing RC optimizations need a boundary audit: scalar/nested read loans,
borrowed entries, constructor takes, local/field/held uniqueness, mutation-scope
elision and physical loop hoists. Suspension/publication invalidates proofs that
assume stable local ownership unless their effect/lifetime analysis explicitly
covers the interval. Mere suspension of a task does not permit another task to
mutate its local data; publishing a value and delegated provider callbacks are
separate effects. Mark this distinction in the analysis instead of disabling
all optimizations forever. No existing `noalloc` promise changes silently.

## Acceptance plan and unresolved proof obligations

WP-4 must first meet its full correctness, GC-geomean/outlier and median-RSS
criteria. A WP-5 design commit is not evidence that it has. Every implementation
stage above needs the normal four-command gate, Guardian with no waiver, fresh
QBE/LLVM execution, and a frozen source/compiler/runtime identity.

| Area | Required evidence before concurrency release |
| --- | --- |
| Snapshot/copy semantics | Parent writes immediately after spawn; nested list/dict records; a dict plus its live view in one packet; H-only referent; repeated submissions; pinned pending receivers; no cross-task view updates. |
| Atomic lifetime | O/H limit refusal, simultaneous last O/H release, promotion/publication cancellation races, no resurrection, weak-probe reuse, no access after a last release; model/stress tests and sanitizers supported by the toolchain. |
| Failure atomicity | Refusal at every packet/task/metadata reservation, partial graph/result/error construction, cancelled send/receive, callback failure; source unchanged and exact count/budget balance. |
| Bounded teardown | Million-node chains, wide/shared DAGs, deep inline variants, H-only chains, cancelled queued graphs under a small native stack and exact memory ceiling; no allocation during release. |
| Arenas/resources | Sender arena closes before child runs; equal depths in different tasks; task suspended in arena; cancellation at each acquisition/lease/completion state; joins before region release and exactly-once finalizers. |
| Authority/scheduling | Narrowed capability quotas cannot multiply; callback affinity; CPU-loop fairness; wait-cycle handling; sibling failure during I/O; a blocked foreign call reports delayed join honestly. |
| Tooling/parity | Worker counts 1/2/N; actual QBE/LLVM; controlled replay; stable trap frame maps; warm/cold cache invalidation after callback/publication-effect edits. |

Performance acceptance numbers for WP-5 are **not fixed by D9**. Freeze them
before implementation measurements rather than choosing thresholds after a run.
The proposed baseline is the accepted WP-4 compiler/runtime, with matched inputs
and full output validation. Measure serial programs that never spawn, coarse and
fine CPU maps, skewed jobs, large shared reads, dictionaries/live views, nested
arenas, pipelines, cancellation and bounded I/O. Record retired instructions,
wall/CPU time, peak RSS, per-task stack/metadata bytes, copy volume, local versus
shared count traffic, contention, queue depth and cancellation/join latency.
Scale worker counts and repeat enough to distinguish scheduling noise.

Outstanding assumptions are explicit:

- Promotion by copying and delivery-domain copies may cost too much for large or
  fine-grained workloads. D9's rejected eager-copy ordinary-call result does not
  establish task-boundary cost either way. Measure before admitting zero-copy
  complexity; the current design claims correctness structure, not speed.
- Shared-domain mode checks, joint O/H transitions and reserved walkers may affect
  serial code size, cache behavior and memory. Confirm that values never crossing
  a boundary retain WP-4's intended fast path and memory advantage.
- Native task stacks, unwind, scheduler checkpoints and provider cancellation have
  not been implemented or proved. Fairness and join latency require measured
  bounds; forceful termination is outside this model.
- The proposed dictionary/H transport identity rule and scoped-handle restrictions
  need language review and adversarial examples. They are not inherited silently
  from the old cycle-preserving proposal or an unavailable Weft implementation.
- In-place promotion/demotion, lock-free count transitions, zero-copy domain
  adoption and task migration remain separate correctness/performance projects.

## Validation of this design change

Only documentation is changed by this slice. Proposed APIs above are prose,
not executable examples. Validation checks local links, document coverage and
Guardian; it makes no runtime, concurrency-correctness or performance claim.
