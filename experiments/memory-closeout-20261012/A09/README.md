# A09 performance evidence — baseline and controlled experiments

The fresh C0 installations and workload binaries are ready. Final integrated
compiler comparisons are pending; this report does not claim any of the three
closeout milestones. C0 is `fbfcaa7a923186a8e773c3760f81c10aa345a432`.

| Artifact | Optimize mode | SHA-256 |
| --- | --- | --- |
| C0 compiler for guest generation/correctness | Debug | `324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a` |
| C0 compiler for compile performance | ReleaseFast | `78ac31605c7505c7cb330d41bdf2d3a232043e032f487e599f454b3bc6f2bd37` |

Both are complete installations with `bin/`, `libexec/`, and `tools/` together.
Their manifests pin every installed file and the Zig distribution. Source inputs
for the ReleaseFast build match C0 exactly; intervening A09 commits only add
experiment evidence. The frozen source and binary identities remain distinct.
Installed C0 components still originate from the historical component seed;
this baseline package is not claimed RC-free.

The [guest build records](raw/C0-guests.json) cover JSON array/object selected
lookup, fresh owned record unpack and cheap/expensive source maps at 1/2/8 workers.
The [application records](raw/C0-applications.json) cover text counting, nested
JSON transformation, resource-backed file processing and useful prime mapping,
including multi-module helpers. Source and local imported-module hashes, binary
hashes, compiler hash, arguments and expected outputs are recorded. Runtime
binaries are uninstrumented Release builds; compiler Debug mode is not guest
Debug mode. Counting and sanitizer symbols are excluded from timing binaries.

## Allocation and RC observations

A03's [fresh C0 release census](../A03/C0-release/REPORT.md) passes 81 cases and
131 executions with zero observed RC events and no managed exit leaks. In the
original **migrated** 30-case denominator, 23 allocate and seven do not allocate
at either measured input size; none are refused. Separately, original unmigrated
source checks admit 21 and refuse nine. These distinctions are retained rather
than counting refused old source as a successful migration. The final compiler's
five-mode census remains a separate required result.

A01's scheduler experiment reduces wrapper allocation scaling; final integrated
runtime and RSS comparisons are pending. A02's [capacity decision](../A02/README.md)
retains existing growth. Starting lists at capacity one reduces singleton retained
storage but causes additional growth for five-element lists, so lower singleton
managed peak alone is insufficient to adopt it. Allocation traffic, managed peak
and RSS are separate metrics; none are substituted for another.

## Capacity-policy runtime and RSS continuation

These are fresh **native C0 runtime policy experiments**, not compiler-generated
final guest comparisons. A09 continued A02's fixed binaries, verified their hashes
before and after each window, removed instrumentation controls, used actual
allowed CPU 10, and ran two warmup plus nine alternating measured pairs. The
workloads were lengthened after the first replacement pilot was below 100 ms.

| Native workload | Repeats | Current median, ms (range) | Start-at-one median, ms (range) | Current/alternative RSS range, KiB |
| --- | ---: | --- | --- | --- |
| Three-element replacement | 10,000,000 | 171.04 (168.73–212.88) | 174.93 (172.20–179.00) | 2056–2060 / 2056–2060 |
| Million-byte growing buffer | 200 | 249.88 (230.41–605.42) | 281.02 (228.68–427.95) | 3568–3572 / 3564–3572 |
| Million-byte reserved buffer | 200 | 211.48 (206.01–229.25) | 215.93 (211.27–222.67) | 3512–3520 / 3516–3548 |

The buffer median difference crosses the 5% review trigger, but its broad overlapping
ranges do not establish a repeatable slowdown. The tested edit changes list initial
capacity and leaves byte-buffer growth unchanged, so this is also an unchanged-path
noise control. None of these samples supports a throughput or RSS saving claim.
The policy stays unchanged on A02's deterministic allocation tradeoff evidence.
All warmups, measured samples, outputs and artifact identities remain in
[replacement](raw/capacity-replacement-long.json),
[buffer](raw/capacity-buffer-long.json), and
[reserved buffer](raw/capacity-reserved-long.json) records. The tiny initial
replacement pilot is preserved separately and is not used for conclusions.

## Compilation, measurement limits and remaining work

A08 measures matched ReleaseFast compilers and separate cold, warm stage,
receipt creation, whole-build replay and valid-edit cases. C0 match depths 16 and 64
pass; match depth 128 reaches the existing 256-level parser nesting limit and remains
an explicit refusal, rather than disappearing from the scaling inventory.
Final compiler scaling and old-artifact invalidation remain required.

`tree_rss.py` samples simultaneous descendant RSS separately from clean timing.
Sampling can miss transients, and summing RSS double counts shared pages. The
current cgroup is not writable, so a dedicated cgroup peak is unavailable.
GNU time/wait4 child high-water values are identified as such and are not called
summed process-tree RSS. Managed counters omit some metadata, provider buffers,
task stacks and allocator overhead.

Exclusive timing admission drains cooperating jobs. Other session builds were
observed outside this admission queue; broad noise is reported rather than hidden.
CPU 10 was selected after actual topology inspection found CPU 0 sharing a busy
sibling. [Methodology](methodology.md), [host metadata](host.json), and the
[timing schedule](schedule.json) record these constraints.

Still required: freeze C1; compile candidate binaries from identical source/inputs;
run the full two-warmup/nine-pair runtime comparisons;
combine A03/A06/A08 evidence on that exact candidate; repeat affected measurements
after default promotion and retirement. Earlier artifacts will not be relabeled
as C1, C2 or C3 results. The prepared harness and baseline do not close those items.

The [one-shot workload pilot](raw/workload-pilot.json) is solely for input sizing.
It identifies short record/application/cheap-map cases needing more work.
Expensive-map prototype samples were slower, but allowing all hybrid P/E cores
is a material confound, especially at one worker. Final paired runs must pin
comparable core topology and investigate any repeatable slowdown above 5%.
A cancellation attempt did not prevent this already scripted pilot from running;
the schedule and handoff reflect its actual completion.


## Calibrated input and topology preparation

The [fixed-topology pilot](raw/workload-pilot-fixed-topology.json) preserves all
21 one-shot output checks. The apparent expensive-map slowdown in the earlier
all-CPU pilot was absent here; this is a calibration observation, with no paired
speedup or causality claim. Final paired inputs now use one million record
unpacks, longer application repetitions, and longer expensive maps. Cheap-map
repetitions are 65,536 / 16,384 / 8,192 at 1 / 2 / 8 workers so each faster arm
should exceed 100 ms while each baseline fits a bounded window. Raw wall times
across these worker cases are therefore not a scaling comparison. Every
before/after pair uses identical arguments, checksums and affinity.

The hybrid host's final worker affinity is CPU 10 for one worker, CPUs 8 and 10
for two workers, and CPUs 0–11 for eight workers. The last set is six physical
P cores with twelve logical CPUs; E cores are excluded. The
[calibrated guest](calibrated-manifest.json) and
[application](calibrated-applications-manifest.json) manifests and frozen binary
records retain those exact choices. Argument-only recalibration reuses verified
binary identities; it does not rebuild or relabel the compiler. The [final-input pilot](raw/workload-pilot-final-inputs.json) completed all 21
output checks in a 26.71-second admitted window; the shortest sample was 158.1 ms.
This completes input sizing, while final-candidate paired measurements remain pending.

`compare.py` prepares no binaries itself. Given frozen before/after build records,
it runs one case per timing lease and yields through an ordinary admission ticket
between cases. Completed cases survive resume; changed artifacts, unequal paired
arguments/environments and attempted evidence overwrites are refused.

## Migration blocker fixed during preparation

Commit `714ae7645b0315a38eb152e27b8a8b0bb44b79b6` fixes ordinary-mode loop
versioning reached by A02's migrated `index_return` fixture. An inlined early
return can join normal loop exit control flow; duplicating that join previously
copied an outside predecessor without its edge. The optimizer now keeps the
original loop when a region has an outside entry other than preheader to header.
The program remains supported. The regression fails before the fix, then passes
trusted/verified leak-checked execution; a positive control still unswitches.
Focused tests pass 2/2 and Guardian passes 88/88. Full integrated qualification
remains the coordinator's gate. Exact evidence is in
[the versioning report](raw/version/results.json).
