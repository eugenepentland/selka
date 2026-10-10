# Wave 5 qualification

Baseline: Wave 4B `bb2007483`; branch `codex/selka-cache-wave5`. The compiler
uses pinned Zig `0.17.0-dev.1683+5ceec001b`. No compiler pin change is included.

## Implemented behavior

Native `juice plan` exports the authoritative dependency and measurement contract
without a build, guest execution, cache lock or workspace write. The developer
coordinator uses explicit workload closure declarations and checks retained
evidence before requesting server admission. Only missing captures take a gate.
Private source changes select their workload; shared dependencies select their
consumers. Changing a shared executable invalidates every physical consumer.

Receipts retain the original native record, exact plain/counted binaries and raw
collector/oracle evidence. Validation reconciles native counts with raw profiles,
re-resolves supported ELF providers, and holds live source, tool, loader cache,
library-search membership and absent-path guards. Unknown provider behavior or
incomplete dependency contracts remain fresh. A subreaper supervises collector
children across separate process groups through cancellation and cleanup.

Measurement policy is explicit: fresh requests execute, deterministic software
counts need a closed execution contract, and physical counter reuse is historical
evidence with `fresh: false`. Threshold/model changes re-evaluate saved evidence
through native comparison with zero measurement admission. Comparison preserves
original inputs and checks runtime identities through final publication.

`mylang cost` caches final-Core function facts and successful exact-unit LLVM
remark queries. Its contract includes structural types, allocation provenance,
physical direct-callee identity, optimization events and reachability. Failed
remark queries remain unknown; supplied counters and YAML are read anew.

The installed compiler and source-build install graph remain Python-free. These
optional repository coordinators use Python, matching earlier caching waves.

## Qualification

Static cost qualification passed all 23 actual compiler invocations: cold/warm,
reachable private and shared edits, fresh parity, verification, corrupt/missing
records, external counters/YAML changes, debug/no-facts/verify-facts modes. Cold
computed three rows and invoked LLVM once; warm reused all three rows and the
remark unit with zero LLVM processes. Both edits recomputed two rows and reused
one. See [cost-native/summary.json](cost-native/summary.json) and
[cost-qualify.py](cost-qualify.py).

Native plan regressions passed 6/6, native cost tests passed 25/25 (including the
nine new cache tests), evidence-store tests passed 26/26, provider tests passed
18/18, process-supervisor tests passed 11/11, snapshot tests passed 41/41, and
coordinator tests passed 35/35. All four new Python suites also passed inside the
final gate, and the full native Juice CLI suite passed 22/22 against Debug.

The [loader candidate probe](provider-candidate-aba.md) demonstrates why search
membership must also watch immediate symlink targets: glibc can skip a wrong-class
ELF candidate, then select it after its external target changes, without changing
the search-directory link. The final snapshot regression guards both transitions,
including restored bytes, without recursively following unrelated directories.

Earlier qualification attempts remain retained: `native-perf-01` and `-02` were
canceled during initial planning before any measurement admission. `-03` passed
cold/warm, private/shared edits and reverts, then was canceled to close output
publication and provider-candidate races. It is explicitly unsuccessful overall.
The first full-gate attempt was also canceled before successful qualification;
its output is [verification-cancelled.log](verification-cancelled.log).

The real `perf` matrix's twelve core checks passed in
[native-perf-04/results.json](native-perf-04/results.json):

| Request | Captures | Reused workloads | Admissions |
|---|---:|---:|---:|
| Cold, three isolated workloads | 3 | 0 | 3 |
| Warm | 0 | 3 | 0 |
| Private edit | 1 | 2 | 1 |
| Private revert | 0 | 3 | 0 |
| Shared-helper edit | 2 | 1 | 2 |
| Shared-helper revert | 0 | 3 | 0 |
| Repetition/context change | 3 | 0 | 3 |
| Warm under changed context | 0 | 3 | 0 |
| Explicit fresh request | 3 | 0 | 3 |
| One corrupted record | 1 | 2 | 1 |

Threshold-only comparisons produced the expected pass at 101 and failure at 99,
both with zero captures or admission. Every retained sample has raw `perf` evidence
and output checks. These are historical instruction observations, not fresh timing.
Real collectors in this pass used `perf`; software-collector validation is covered
by fixture tests and is not claimed as a new real-collector qualification here.

The additional Selka attempt in `-04` correctly stayed fresh because its sidecar
omitted `libpthread.so.0`: both captures were explicitly unqualified, so `-04` is
unsuccessful overall despite passing all twelve core checks. The corrected Selka
closure passed all three checks in
[native-perf-05/results.json](native-perf-05/results.json), without changing the
implementation. Its cold run captured once with one admission; its warm run
reused the plain/counted evidence with zero captures and zero admission. Both
records were qualified, with nonempty verified dynamic-library identities.

The first completed gate ran all 2,650 native tests successfully but exposed a
10-second deadline in the new lock-avoidance CLI regression. Debug's full compiler
ELF hashing exceeded that deadline. The regression now uses the existing suite's
60-second bound while holding the lock throughout; it passed against Debug in
26.305 seconds. This does not relax the requirement that planning avoid the lock.
See [verification-timeout.log](verification-timeout.log) and
[juice-native-debug-lock.log](juice-native-debug-lock.log).

The final full gate passed **121/121 steps and all 2,650 native tests**. All 41
verification groups ran, with stable inputs confirmed; the inventory covers all
85 required actions with none unclassified. Formatting, documentation coverage
and all 88 diff-scoped Guardian checks passed. Native result records report zero
failures and zero skips; the build summary's 23,993 skipped entries are tests
assigned to other shards. See [verification.log](verification.log) and
[verification.json](verification.json).

The command was `python3 scripts/verify_cache.py --zig
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig -- -j3 --maxrss
8589934592`, with worktree-local Zig cache, shared global cache and on-disk
temporary storage. It owned admission. Preparation held a build slot for 2.171
seconds; the gate waited 857.353 seconds and held 618.151 seconds. These are
operational verification durations, not an isolated performance comparison.
The normal commit hook separately enforces whole-tree Guardian checks.

[qualification-summary.json](qualification-summary.json) lists the exact successful
checks used from each run, with retained report digests. Earlier failed attempts
remain explicit; they are not relabeled as successful runs. The implementation
file identities are recorded in [qualified-inputs.json](qualified-inputs.json).

No elapsed-time speedup or memory improvement is claimed. The ReleaseFast
qualification compiler SHA256 is
`c9d01d4dae08be861d9f5b365b39a93293491b805ea3f5522bb3c94232ad5785`.
ReleaseFast install passed all 12 steps and all 88 Guardian checks. Its optimization
mode affects planning cost, independently of guest compilation mode.

## Scope and limits

Workload closures are explicit attestations, not a sandbox or automatic discovery
of arbitrary external reads. Native source-glob directory scopes are conservative.
Static amd64 ELF and ordinary glibc dependencies are supported; RPATH/RUNPATH,
unknown loaders, loader injection and unbound providers remain fresh. Explicit
resources are still needed for dynamic loading, child tools, SDKs and checkers.
Physical observations bind whole executable/link layout and machine context.

Storage is bounded, local and disposable. Wave 6 still covers sharing across
worktrees, retention/leases/GC and reducing the no-op planning floor. Durable
application journals and restart guarantees remain future work. Debug builds hash
their own large compiler executable slowly during planning; qualification uses
ReleaseFast without weakening executable identity.
