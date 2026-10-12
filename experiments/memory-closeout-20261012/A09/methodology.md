# Measurement contract

C0 is `fbfcaa7a923186a8e773c3760f81c10aa345a432`, rebuilt on this host
with the pinned Zig distribution and Guardian revision. `C0-installation.json`
pins every file in the complete Debug compiler installation. The compiler
installation remains immutable; candidate artifacts use separate prefixes.
The baseline build succeeded. This does not qualify a final candidate.

`measure.py build` owns one build admission per distinct source/option pair.
It produces uninstrumented Release guest binaries, records compiler/source/
binary hashes and exact commands, and checks symbol tables for the counting
runtime. `measure.py run` requires an enclosing `scripts/build-slot.sh timing`
lease and accepts only prepared binaries. Queue wait is excluded from samples.
Do not wrap `build` in admission again.

Each comparison has two warmup pairs and nine measured pairs, alternating arm
order. Both warmup and measured samples are retained. Each sample must return
the independently specified output with exit status zero and empty stderr.
The harness verifies source/compiler/binary identities instead of reusing an
old report's labels. Runtime environment removes counters, sanitizer and
leak-check controls. Any required capability grants are explicit per-case
environment entries. Identical runtime arguments, environment, worker count and CPU affinity apply to
both arms. Final serial cases use CPU 10. On this hybrid i7-12700H, logical CPUs
0–11 are the six P cores with two threads each; CPUs 12–19 are E cores. The final
map/application matrix pins worker 1 to CPU 10, worker 2 to CPUs 8 and 10 (distinct
P cores), and worker 8 to CPUs 0–11. Eight workers therefore share six physical
P cores; this topology is explicit and identical before/after. The original
all-CPU pilot is retained as calibration only, with hybrid scheduling a confound.
Initial manifests record CPU 0 or all allowed CPUs; `calibrated-manifest.json` and
`calibrated-applications-manifest.json` supersede their sizing and affinity for the
final paired runs. The result records effective affinity. `--cases` permits one bounded window per case, with durable
append to a result only when all artifact identities match.

Wall time uses a monotonic nanosecond clock around spawning and waiting for
the guest. It includes process launch and exit. Binaries with median times
below 100 ms must be lengthened before interpreting ratios. Ranges and paired
samples remain visible. A repeatable candidate slowdown above 5% requires
review; overlapping noisy samples do not establish a speedup.

Linux `wait4` records each invocation's maximum resident set in KiB, user time
and system time without cumulative-child contamination. RSS includes guest
threads. If a workload spawns child processes, this measurement is not the
simultaneous summed process-tree peak. Dedicated cgroup measurement is not
available to this session (the cgroup filesystem is not writable); compiler
RSS reported by A08's GNU time method is explicitly a child high-water metric,
not a process-tree aggregate. `tree_rss.py` adds separate memory-only executions
that sample the simultaneous descendant RSS sum every 10 ms, following children
across all process threads. These sampled sums can miss short transients and
double count shared pages; they are not a cgroup measurement. Their elapsed
times are instrumented and excluded from primary timing. No managed-counter
observation is called RSS.

A03's counted runs separately provide allocation/reallocation events,
cumulative bytes, peak live managed bytes, exit-live bytes and RC events.
Managed counters omit some metadata, provider buffers, task stacks and allocator
overhead. Peaks are observations and are never subtracted as if they were
allocation traffic. A01 separates scheduler storage from final and temporary
result storage; A02's policy experiments may close with a measured rejection.

Compile measurements use matched ReleaseFast compilers and matched cold/warm/edit
cache state. A08 owns those cases and requests a separate exclusive window.
The initial C0 compiler is Debug and is used for correctness and generating
Release guest binaries. The separate C0-releasefast installation is built and frozen for
compiler throughput measurements; Debug compiler smoke timings are not results. Whole-build replay and warm stages are measured separately: requesting LLVM
emission disables whole replay. Checked ownership disables lazy/demand
restoration, rather than all replay.

The initial nine guest cases retain JSON array/object lookup and owned record
unpack, extended from historical sources to avoid tiny process timings, plus
cheap/expensive parallel maps at 1/2/8 workers. Larger application sources from
A06 join the matrix when their correctness checks pass. Historical source
files and reports are read only. Candidate/default/retirement changes require
new binaries and affected-case reruns; earlier binaries are never relabeled.

## Timing schedule

- A02 may enqueue one approximately one-minute native capacity-policy timing
  window after compiling all plain binaries. It must send its actual start/end
  and result paths. No nested admission is permitted.
- A09 guest baseline builds are ordinary admitted work. Final paired runtime
  windows await the frozen candidate. Initial baseline pilots only determine
  workload size; they are not before/after performance results.
- A08 compilation scaling runs first as correctness smoke checks; it requests
  a timing window after confirming source acceptance and case sizes.

The shared host permits unrelated activity outside this session. Exclusive
admission drains cooperating builds and gates; it is not complete host isolation.

The A06 application timing manifest is preserved separately as
`applications-manifest.json`: word counts, nested JSON transforms, resource file
processing and prime mapping all repeat fixed checksummed work. `--source-root`
permits building the same module files from A06's worktree before integration.
Build records hash the entrypoint and its local imported modules. Refused cases
stay in build records and paired results explicitly mark them not comparable;
they are not silently removed from the application denominator.


`measure.py build --reuse-builds PATH` reuses only an existing binary with the
same compiler, source/local modules, flags and verified binary hash. This permits
calibrating runtime arguments without recompiling or relabeling an artifact.
Prepared artifact files and completed samples refuse overwrite. Paired runs
explicitly reject unequal arguments or environments as well as unequal outputs
and affinity. Default promotion may change only the compiler's ownership selector
flags; the guest workload inputs remain identical within every paired case.

`compare.py` sequences one case per exclusive timing lease, with an ordinary
no-op admission barrier between cases. It records each lease's log, preserves
completed cases on resume, and stops after an admission or measurement failure.
Do not wrap it in another admission lease. Initial cheap-map repetitions differ
by worker case to keep the faster arm measurable without making the baseline
window excessively long; raw wall times across those worker cases are not a
worker-scaling claim. Within each before/after case, repetitions are identical.

Some earlier Guardian hooks did not participate in shared admission. A10 reported
hook completion times 01:02:36, 01:08:23, 01:16:01, 01:23:37 and 01:27:30 UTC;
exact start times were not retained. A09's earlier commit ending 00:46:58 falls
inside A02's already-noisy nested-five window; its hook admission is not established
by preserved metadata. These are additional possible sources of interference.
Future A09 commits explicitly run under `scripts/build-slot.sh gate git commit`.
