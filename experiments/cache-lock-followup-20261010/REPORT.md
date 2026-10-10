# Cache lock-occupancy follow-up

This pass resumes the previously deferred Wave 2 measurements and reduces
avoidable serialized work in packed storage and verification. Main
`0488ebb2b59ebdd188d19ff612c75b580d6f0101` was merged as
`8a0bdb487e65ea59ea0b5cdf0117d4e1c3ef7058` before implementation. The clone has
no configured remote; this is the latest committed local main reviewed at the
start of the pass. Its updates add Juice runtime collectors and compile-only
performance experiments. The Zig pin remains `0.17.0-dev.1683+5ceec001b`.

## Changes

Packed storage retains a filename-to-ID map instead of linearly searching the
catalog on every directory entry. Saves prepare payload checksums and copies
before taking the interprocess sequence lock. Flush prepares, verifies,
compresses and writes each temporary pack before that lock, then revalidates the
open journal and its current path before renaming and publishing. Every chunk
retains original record sequences, so another writer's newer value still wins.
The source journal remains available until all chunks have committed.

Preparation keeps the existing per-State mutex: this allows independent stores
and processes to publish concurrently, without allowing callers sharing one
State to mutate its journal during preparation. Refresh still enumerates the
directory and validates new or foreign packs while publishing; this change does
not eliminate all catalog work. A single-pack flush now uses two short sequence
lock acquisitions, including final journal retirement, rather than one long
acquisition. Work counters expose lookup, refresh, preparation and acquisition
counts without changing storage formats or key semantics.

Verification retains whole-action evidence, with narrower prepared artifact
dependencies for 11 reviewed cohorts. Seven script cohorts do not use native
artifacts; four bind their specific native runner/builder/components. All retain
configuration, inventory, tools, environment and host identities, and the full
artifact snapshot remains watched through publication. Other native cohorts
keep conservative complete artifact identities. The new Juice runtime checker
is explicitly registered as fresh. The input-coverage checker also stays fresh:
its negative filesystem lookups can change when a previously missing fixture
appears outside its declared source list.

The inventory contains 77 required and registered actions, with no unknown
actions, grouped into 39 cohorts: 28 eligible for reuse and 11 fresh. Reports
separate admission wait/startup, post-admission validation, worker time, observed
held time, and preparation/lookup outside admission. The observed held interval
starts at the admitted child's greeting; it does not claim to include the short
wrapper/interpreter startup after lock acquisition.

## Qualification

- All 20 focused packed-store tests passed after the final source changes.
  They include corruption, concurrent publishers, automatic sealing, allocation
  failure sweeps, indexed lookup counts, independent publication during unlocked
  preparation, and rejection of same-byte/mtime restoration or path replacement.
- All 37 coordinator and 20 snapshot regressions passed. New checks exercise
  unrelated and selected artifact changes, always-fresh negative lookups, timing
  accounting, and rejection of a queued edit without starting a worker.
- Final preparation completed 40/40 build steps. The focused store/format build
  completed 22/22 steps and 20/20 native tests. Guardian passed 88 checks under its
  diff scope; whole-tree commit-hook qualification is recorded separately.
- A read-only independent review found no concrete defects in map ownership,
  unlocked preparation, sequence precedence, cleanup or artifact projection.
- Three trace-parser tests passed, covering unfinished syscalls, descriptor
  reuse, failed acquisition and incomplete traces.

Full verification completed 111/111 build steps and 2,605 native tests with no
failures. The 23,678 reported skips are the other partitions of the sharded test
roots, not unrun selected tests. All eight live matrix cases completed as
expected, including the deliberate failing edit. The added case increased the
observed coordinator suite from 37 to 38 tests; the failing version exited
nonzero and left the success-receipt map unchanged. Every temporary edit was
restored, and the final run again reused all 28 eligible groups. The ten frozen
product/documentation input hashes still match.

| Live case | Eligible groups executed | Observed gate hold |
| --- | --- | ---: |
| cold-force | Original full gate (forced) | 487.660 s |
| unchanged | None; all 28 reused | 21.729 s |
| private-script | `affected` | 20.959 s |
| shared-script | `my_format`, `my_format_self`, `noalloc_lint` | 23.510 s |
| added-test-passing | `verification_cache` | 30.466 s |
| added-test-failing | `verification_cache` | 31.430 s |
| nonembedded-documentation | `doc-coverage`, `doctest` | 24.057 s |
| restored-unchanged | None; all 28 reused | 22.326 s |

All non-forced calls also execute the 11 fresh groups. Cold-force means cold
outer receipts, with existing machine/Zig/preparation caches. Its process wall
was 2,274.396 seconds, including 1,773.823 seconds of admission wait/startup and
1.925 seconds of build admission; the full-gate hold itself was 487.660 seconds.
The first unchanged call used no build slot, held the gate for 21.729 seconds,
and completed in 32.310 seconds including lookup and process overhead. The
prose-only documentation edit needed 1.509 seconds of build admission, and
restoring that document state needed 1.512 seconds, in addition to their gate times. This is a qualification sequence, not a paired claim about
whole-gate speedup versus the previous implementation.

Exact phases, outcomes, resources and retained raw hashes are in
[qualification-summary.json](qualification-summary.json). The complete current
[inventory](inventory.json) and [frozen inputs](qualified-inputs.json) accompany
it. The normal commit hook performs the separate whole-tree Guardian check.


## Measurement contracts

The historical Wave 2 comparison uses the three retained ReleaseFast binaries
and the 510,436-line synthetic workload. It answers whether the earlier shared
catalog/planner optimization helped that historical baseline. It does not measure
the newly merged main or the packed-store changes in this pass. The optimized
after-profile is a separate diagnostic, with source parity and its path/cache
differences recorded. See [the Wave 2 plan](wave2/PLAN.json).

The packed-store experiment builds one harness against baseline and candidate
storage code with the same pin and ReleaseFast settings. Fixed store identities
and identical seeded bytes isolate the storage implementation. Each arm and
round receives its own store copy. Seeding, copying and compilation occur before
measurement admission. Cases use 128 and 3,500 retained packs, external updates
observed by a live reader, and four independent publishing threads. Every read
and published payload is verified; arm order alternates over three rounds.

`work_ns` excludes startup/catalog priming and, for concurrent writers, final
independent verification. Process wall/CPU/maximum-process RSS includes those
costs and deinitialization. Candidate counters include catalog priming. A separate
intrusive strace run records successful sequence-flock return through close and
flock syscall duration; those diagnostic durations are not mixed with normal
timings. Summed lock holds/waits across workers are resource occupancy, not
elapsed time. This microbenchmark does not establish a whole-gate speedup.

All timing batches enter through the normal FIFO gate admission and use CPUs
2 and 10; they never run beside another gate. Builds may run on the separate
build CPUs. Gate queue waiting is reported separately from occupied time.

## Resumed Wave 2 result

All 69 invocations passed, with 662 normalized verdicts per invocation, nine
candidate/forced key agreements, 27 restored-original key agreements and 27
distinct fresh edit signatures. All 333 source files returned to their original
bytes. Gate admission waited 0.049 seconds and occupied 725.213 seconds for the
complete batch, including its oracles and inventories.

| Historical workload | Before Wave 2 | Original Wave 2 | Earlier optimized Wave 2 |
| --- | ---: | ---: | ---: |
| Cold application/cache run, one sample | 38.606 s | 51.353 s | 41.533 s |
| Unchanged, one sample | 0.228 s | 0.285 s | 0.282 s |
| Private edit, median of three | 0.299 s | 0.349 s | 0.352 s |
| Shared-helper edit, median of three | 13.565 s | 18.148 s | 13.559 s |
| Three-file edit, median of three | 13.066 s | 17.850 s | 13.582 s |
| Restore helper, median of three | 6.797 s | 11.836 s | 7.554 s |
| Restore three files, median of three | 6.520 s | 11.682 s | 7.353 s |

The earlier optimization recovers most of the original Wave 2 regression: helper
and three-file edits improve by 25.3% and 23.9% against original Wave 2, and their
restores improve by 36.2% and 37.1%. It does not establish a generally faster edit
loop than the pre-Wave-2 compiler. Private edits and unchanged runs show no useful
improvement against original Wave 2; edit RSS remains about 662 MiB. These are
three-sample medians/ranges, without a significance claim. Full raw samples,
work counts, contexts and hashes are in [paired-summary.json](wave2/paired-summary.json).

The real artifact metadata also supports a separate identity experiment:
hypothetically changing only the prepared compiler invalidates all 28 eligible
cohorts under the old common-artifact rule, versus 17 with reviewed dependency
projection. Eleven retain their identity. This changes no binary, executes no
worker and makes no timing claim; actual source edits can invalidate additional
inputs or other native executables. See
[verification-identity-comparison.json](verification-identity-comparison.json).

## Packed-store result

All 24 normal samples and both trace diagnostics completed with verified payloads.
The batch waited 1,843.318 seconds for admission, then occupied the slot for
5.843 seconds. The following are three-round medians of the measured work loop,
excluding priming and final independent readback as defined above.

| Retained packs | Workload | Baseline | Candidate | Reduction |
| ---: | --- | ---: | ---: | ---: |
| 128 | Reader observes 32 external saves | 1.626 ms | 1.141 ms | 29.8% |
| 128 | Four publishers, 64 saves each | 61.476 ms | 30.638 ms | 50.2% |
| 3,500 | Reader observes 32 external saves | 394.555 ms | 19.545 ms | 95.0% |
| 3,500 | Four publishers, 64 saves each | 348.631 ms | 75.344 ms | 78.4% |

Including process startup, priming, readback and deinitialization, the 3,500-pack
refresh median changes from 0.582 to 0.194 seconds, and concurrent publishing
from 0.637 to 0.282 seconds. Peak process RSS increases in the larger concurrent
case: median 22.81 to 31.45 MiB; its refresh case changes from 7.91 to 8.23 MiB.
This is a speed/memory tradeoff under the measured contention, not a memory
reduction. The 128-pack concurrent case stays around 23 MiB.

In the separate intrusive 128-pack trace, summed sequence-lock occupancy changes
from 36.326 to 30.193 ms (16.9% lower), and summed flock syscall time from 85.227
to 68.631 ms (19.5% lower). Acquisitions increase from 68 to 72 because final
journal retirement acquires a separate short lock. This single instrumented pair
supports shorter occupancy in that case; strace overhead and scheduling prevent
claiming those percentages as general lock-time reductions.

The historical optimized profile also completed: helper 13.325 seconds and
restore 6.944 seconds, each verifying all 662 verdicts. Flat BLAKE3/SHA2 sample
shares fell from 45.38% to 15.58% for the helper and 58.78% to 23.63% for restore.
These are diagnostic sample shares, not wall-time attribution; incomplete symbol
resolution and path/cache differences remain limitations. See the
[Wave 2 report](wave2/REPORT.md) for full profile provenance and interpretation.

Raw task-owned evidence is under
`.mylang-cache/cache-lock-followup-20261010/`; compact results, source/binary
hashes and commands are retained here.
