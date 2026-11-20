# Publication review and next stage — 2026-09-16

## Decision

The per-body sync problem is addressed in `bcd0c652`, on the frozen baseline
`fd103f82`. Treat this as an implemented publication milestone with a documented
filesystem-wide flush limitation. The overall performance acceptance remains
open: 100k checking and affected tests still exceed their targets, and the
productivity trial has not run. Self-hosting frontend development can continue
independently.

Next: correct the native profiling attribution, then optimize the cost of
compiling genuinely changed native objects. Do not weaken generic invalidation
to reduce the count from this benchmark.

## Review findings

### 1. Native phase timings are a separate experiment, not a test decomposition

`next-publication-2026-09-16/profile_native_path.py:119` runs `mylang test`, then
at line 129 runs a separate `build --select-file`. The second build uses the
top-level cache directory. Native tests use its `objects/<environment-hash>`
subdirectory (`src/native_test_session.zig:76`). Thus its 64 compiled objects
and 1.886-second codegen receipt belong to another invocation and cache.
They support the codegen hypothesis but are not direct timing of the test child.

The script also restores pristine files at lines 209–210 before collecting
`used_helper_edit.check_phases_ms` at line 228. That measurement is of restored
source. It retains only the final build receipt, alongside a median of three
test timings, and does not enforce success for every profiled subprocess.

Correct the harness to capture the actual nested build receipt for each test
sample, preserve the edited source during phase measurement, and keep failed
or incomplete samples out of summaries. Label any separate reproduction as
such. Measure QBE and assembly separately and retain changed function identities.

### 2. The 64-object change has a valid dependency explanation

The managed probe edits `pricing.apply[P]` itself. The generator creates 64
provider types and calls `pricing.bundle` for all of them; `bundle` calls
`apply[P]`. The edit therefore changes 64 concrete implementations.

An independent four-provider probe using the reported compiler
`16ddcf8b8d40e7f592869e4b0475a4371bcd515156be25e137da7c04ebb0606c`
captured QBE inputs from the actual `mylang test` children:

- Cold: 22 compiled function fragments.
- Unchanged forced run: 0.
- Shared generic body edit: 4. Each changed fragment gained the edited
  `+ 1000` operation; symbols stayed the same.
- Unchanged forced run after the edit: 0.
- One-provider body edit, with the same environment and tool identities: 1.

These are diagnostic work counts, not latency benchmarks. They support correct
specialization invalidation. Keep a separate one-provider body-edit workload
to distinguish local changes from shared-template changes.

[Captured counts, IL hashes and diffs](publication-review-2026-09-16/probe.json)
and [probe driver](publication-review-2026-09-16/probe.py). The driver expects
the recorded local compiler/tool paths and uses its own directory for scratch;
copy it into an empty temporary directory before rerunning.

### 3. `syncfs` synchronizes the containing filesystem

`src/semantic_store.zig:601` invokes `syncfs` on the namespace directory.
This flushes the entire containing filesystem, including unrelated dirty files;
it does not restrict synchronization to the cache or the publication batch.
[Linux syscall documentation](https://man7.org/linux/man-pages/man2/sync.2.html)
also specifies that Linux waits for I/O completion.

One syscall per batch therefore does not bound the amount of I/O or the wait.
The low-load improvement is valid; latency isolation from other disk activity
is unproven. Document that limit and measure under controlled background writes
before claiming predictable publication latency. If it is material, use bounded
cache-owned segment files with file and directory synchronization. Do not drop
validation or silently remove the agreed persistence guarantees.

Also replace the report's claim that the ext4 penalty is gone with a narrower
claim: per-body synchronous flushes are gone. Its own table retains measurable
filesystem differences, especially for cold managed population.

## Next implementation package: cheaper changed-object compilation

1. Capture real test-child build telemetry as described above. Preserve the
   one-check-per-provider-graph and selective-lowering contracts.
2. Classify changed object identities and emitted bytes. Preserve all required
   generic specializations. Any proposed invalidation fix needs unchanged-code
   evidence, not simply a count of 64.
3. Profile subprocess overhead and QBE versus assembly time. The current path
   iterates objects serially (`src/qbe_build.zig:408`) and invokes QBE followed
   by `zig cc -c` for every miss (`src/qbe_build_cache.zig:160`). First evaluate
   bounded parallel compilation while preserving per-function object keys.
   Evaluate tool batching only if measurements justify its cache tradeoffs.
4. Bound worker count and memory, preserve deterministic outputs and diagnostics,
   reap children on error, and retain concurrent publication and damaged-object
   fallback. Repeated unchanged/forced runs should compile zero function objects.
5. Measure ordinary local edits, one-provider body edits, shared generic body
   edits, unused-helper edits, forced runs, and cold builds independently. Use
   pinned compiler/tool identities, 10k/100k, both tmpfs and ext4, wall p50/p95,
   peak memory, object counts, process counts, and actual child phase timings.
6. Run the relevant native/cache gates and the normal integration gate. Update
   the central ledger and `final-status.md`, which currently still identify
   `936b3e69` and the older S1 measurements as the final state.

Keep the default 16 MiB retention budget during this package. Investigate
managed replay/retention cost separately afterward; the current managed cached
check still loses to its no-cache control. Do not claim one backend optimization
will satisfy the check-time target.

## Acceptance remaining

Current recorded ext4 results:

| 100k workload | Check edit p95 | Used-helper test edit p95 |
| --- | ---: | ---: |
| Ordinary | 645 ms | 1,452 ms |
| Managed | 811 ms | 3,587 ms |
| Target | <500 ms | <1,000 ms |

The publication package can be closed with the qualifications above. Full
performance acceptance requires the targets to pass, or an explicit decision
to revise/defer them. The comparative productivity trial is a separate open
acceptance item; neither these gates nor synthetic latency results complete it.

## Review scope

Reviewed the committed diff, report, raw evidence, native build/cache path, and
benchmark generator. Ran the existing ReleaseFast compiler against a private
small project with a QBE capture wrapper. No compiler implementation changed,
no full repository gates were rerun, and no Guardian gate was exercised.
