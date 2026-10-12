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
environment entries. An identical worker count and CPU affinity applies to
both arms. Serial cases use the first CPU actually allowed by this host;
parallel cases retain the allowed set for the 1/2/8-worker matrix.

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
not a process-tree aggregate. No managed-counter observation is called RSS.

A03's counted runs separately provide allocation/reallocation events,
cumulative bytes, peak live managed bytes, exit-live bytes and RC events.
Managed counters omit some metadata, provider buffers, task stacks and allocator
overhead. Peaks are observations and are never subtracted as if they were
allocation traffic. A01 separates scheduler storage from final and temporary
result storage; A02's policy experiments may close with a measured rejection.

Compile measurements use matched compiler modes and matched cold/warm/edit
cache state. A08 owns those cases and requests a separate exclusive window.
The C0 compiler is Debug; Debug compiler timings are identified as such and
cannot be described as production compiler throughput. Whole-build replay and warm stages are measured separately: requesting LLVM
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
