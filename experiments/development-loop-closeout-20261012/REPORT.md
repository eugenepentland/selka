# Development-loop ten-agent execution report

The ten-agent changes are integrated and the frozen candidate passes complete
verification. **The development-loop and self-hosting milestones remain open**:
this execution does not establish ordinary-edit latency, calibrated enforcement,
all runner timing hooks, the full live edit/cold matrix or full compiler-port
acceptance. The detailed [required matrix](S10/final-matrix.md) preserves every
unqualified requirement and distinguishes controlled fixtures from live cases.

## Reviewable candidate

- Branch: `codex/dl-closeout-20261012-integration`.
- C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432`, fetched development lineage.
- Tested C1: `a9a3208a4f3edbf17170cfc18d57f5f999af49c3`.
- Changes after C1 are closeout evidence only. Main, the published snapshot,
  bootstrap checkout and memory-management worktrees were not integrated into
  or rewritten by this execution.
- Coordinator plus ten Sol 6.1 workers used separate worktrees, private local
  caches, shared admission and fixed commits. [Ownership/commit ledger](status.md).
- The exact current configuration was explicitly reviewed by S04 and coordinator;
  qualified pin `686631858644a1ce4535ac1f981f3338421ff46e3f0f3ca10d7e5de43c14b655`.
  See [qualification evidence](coordinator/qualification.md).

## Delivered behavior

- The verification report accounts for all 46 groups and 101 required members.
  Supported Python telemetry captured all 286 selected tests in 11 members;
  timing remains explicitly unknown for the other 90 members. Reports preserve
  per-process RSS scope and never sum overlapping durations as wall time.
- Sticky, bounded invalidation diagnostics identify changed input roles and paths,
  including source changes accompanying failed tests. Exceptional publication
  cannot leave a stale successful last-run report.
- Process supervision owns and reaps its descendant lineage without killing
  unrelated admission helpers. Execution limits remain distinct from report-only
  policy estimates and targets; no uncalibrated hard policy was enabled.
- The independent scalar root runs eight existing named tests and one import
  wrapper. Exact moved names, wrapper counts and the seven-file closure were
  audited; a changed oracle fails, a matching filter passes and an absent filter
  fails. Both pure native roots use actual authenticated producer metadata and
  conservative fallback through the production artifact/action path.
- Quick feedback reports partial status and remaining work. Complete mode retains
  full coverage. Long qualification reports missing external obligations rather
  than inventing completion. Fuzz and Juice adapters support bounded work and
  report-only reevaluation through existing evidence stores.
- Golden checks retain all 222 compiler executions and fresh mutable fixtures,
  while preparing 165 distinct source payloads instead of 222. Snapshot setup
  avoids proven redundant work without weakening metadata validation.

## Passed qualification

S10 independently reviewed the full forced C1 gate, formatting and both unchanged
requests. All returned status0 with stable inputs, exact inventory coverage and
zero outstanding required groups. The normal C1 commit hook also passed all
88 whole-tree Guardian checks; the diff-scoped build check is not substituted
for that whole-tree evidence.

| Request | Executed / reused groups | Gate admission | Coordinator elapsed |
| --- | --- | --- | --- |
| C0 forced complete | 45 / 0 | 1034.160 s | See raw baseline report |
| C1 forced complete | 46 / 0 | 985.953 s | 1012.058 s |
| C1 unchanged 1 | 11 / 35 | 65.862 s | 73.310 s |
| C1 unchanged 2 | 11 / 35 | 91.618 s | 101.175 s |

These are operational runs, with shared-host work and different source/configuration
contexts. They are not isolated before/after comparisons or a p95 estimate.
Both C1 unchanged requests performed zero file hashing and zero directory
enumeration; each still required 175,816 metadata observations and 11 fresh groups.
No warm latency improvement is claimed. C0's first retained request selected all
work again and was intentionally canceled with status143; it is not warm evidence.

Focused evidence also includes coordinator74, process33 and session15 checks,
producer/stability/telemetry27 follow-ups, native preparation41/41, scalar9/9,
S06's 18 mandatory cold/warm guest actions plus eight controls, and existing
component correctness/seed fixtures. The final gate runs the registered current
suites, including the new helpers. [Raw evidence and acceptance](S10/acceptance-report.md).

Frozen compiler artifacts are pinned in the existing retention store:

| Mode | SHA-256 | Bytes |
| --- | --- | ---: |
| Debug | `e018f4dc02cba5020dcdb9c74a8bdd4354d11b49d2dfaacf5030b0aa82f176f3` | 239001890 |
| ReleaseFast | `75935fabfbde64f8045d0aaba92122b304d344bee06839699b7b21563dcae9b1` | 68298936 |

## Rejected changes and concrete follow-ups

1. Guest discovery indexing was rejected. Twenty isolated paired samples showed
   large synthetic improvements but regressions on small and shared-root fixtures.
   Production discovery and SPEC remain at C0; the exact candidate is archived.
   Continue with supported startup/discovery/compile/execute phase instrumentation
   through the runner owner before another optimization.
2. Cross-snapshot stat memoization was rejected because watcher authority did not
   prove remote-filesystem/mount changes. Preserve fail-closed validation while
   measuring the remaining metadata cost; do not trade correctness for zero stats.
3. One-shot and retained startup can conservatively differ in loaded-code identity.
   S08 reproduced unequal marshal hashes for equal code when constant references
   change. The actual startup contributors are still unproven. Implement and
   qualify a bounded canonical loaded-code encoder and version its receipts;
   test loader contexts, semantic changes and unknown constants before adoption.
4. Obtain supported native/guest timing hooks; collect compatible headroom and
   concurrent-subscriber evidence before enforced per-action policy. Qualify live
   edit/revert/second-worktree behavior and paired cold compile/link/RSS costs.
5. Complete authenticated long-qualification orchestration and real work-counter
   capture. Valgrind was unavailable; synthetic counters and passing smoke cases
   do not qualify performance. Measure named ordinary-edit workloads against the
   five-second feedback and fifteen-second p95 targets using bounded timing windows.
6. The active bootstrap owner must supply qualified stages, seed/ABI transitions,
   full bootstrap parity and every workload median and p95 at most 1.5 times the
   frozen Zig reference. The schema11/ownership/admission handoff is archived;
   no competing port or memory-mode rollout was introduced.

Each remaining requirement is visible in the [ledger](status.md) and
[required matrix](S10/final-matrix.md). No roadmap wave is called complete from
scaffolding, partial coverage, an instruction proxy or an unmeasured optimization.
