# Juice: a fast performance proxy

Juice compares **instructions per completed application unit**, with baseline
100. A score of 92 means 8% fewer instructions for equivalent work. It does
**not** mean 8% less elapsed time. Allocation, copying, atomic operations,
generated code, source attribution and repeat variability help explain the
result. Ordinary use needs neither an idle machine nor a full production run.

Juice is built into the installed compiler: `mylang juice --help`. All seven
commands run native Zig code; no Python interpreter, repository checkout or
companion script is needed. It supports generic native programs and mylang
applications. Capture currently requires Linux x86_64, a build toolchain and
`perf` or Valgrind. Binutils provides optional static diagnostics; `ldd` identifies
loaded libraries. Comparing, validating and calibrating saved JSON needs only
the compiler binary. The original `scripts/juice` Python tool remains a developer
reference for differential tests, not an installed dependency.

An experimental [compile-only IR estimator](../../experiments/juice-ir-proxy-20261010/README.md)
derives counts for canonical scalar loops and adds a dependency-based cost score.
It runs no guest code. The first five-transformation evaluation had 16.1% median
timing-ratio error, substantial outliers and excessive timing spread; it does not
meet the 5% target or replace runtime validation. Collection operations and
data-dependent paths currently produce `unknown`.

A [final machine-code follow-up](../../experiments/juice-machine-proxy-20261010/README.md)
keeps Core's loop counts and uses LLVM MCA with independently checked instruction
latencies. On a fresh run of the same five transformations, median timing-ratio
error improves from 17.2% for Core to 3.3%; four of five point estimates are within
5%, with an 18.2% remaining miss. Timing spread still prevents qualified passes.
The mapping is manually audited for one binary, and memory and general control
flow are unsupported. This remains an advisory developer experiment.

## Runtime proxy and the 5% target

`record --profile runtime` adds a separate CPU runtime proxy. The default
`work` profile and baseline-100 instruction score retain their existing meaning.
The runtime profile requires Linux perf and collects a simultaneous group of
user-mode instructions, cycles and reference cycles on the selected CPU. All
three events must be positive, occur exactly once and report 100% running with
`--no-scale`; missing or multiplexed events leave an incomplete record. Hardware
that cannot supply the complete group cannot use this profile.

Ordinary cycles capture the cost of instruction mix, stalls and memory access.
Reference cycles run at a fixed reference frequency while the process executes,
which makes their ratio a useful first estimate of CPU-bound elapsed time even
when the core frequency changes. See Intel's
[reference-cycle definition](https://perfmon-events.intel.com/platforms/haswell/core-events/core/).
The report includes both ratios and the change in cycles per instruction (CPI).
It does not add separate stall or allocation penalties on top of cycles.

The estimate is candidate reference cycles per completed unit divided by the
baseline's. Both captures must have matching contexts and contracts. For independent captures, a spread
above 3% in either arm suppresses the estimate. For explicitly paired captures,
Juice uses the median of candidate/baseline ratios and applies the same 3% limit
to those ratios, so shared drift need not cause an automatic abstention. Both
arms must name the same pairing session and have at least five complete,
equal-sized groups; pairing is never inferred from unrelated records. A stable estimate still has
`accuracy_validated: false`: the **5% relative error is a target, not an error
bound**. Repeat ranges are observations, not confidence intervals. User-mode
counters exclude kernel work, descheduling and I/O waits; different machines,
contention, changed working sets and very short programs need separate checks.

```bash
mylang juice doctor --profile runtime --cpu 10
# Use the same cache, CPU and profile for both captures; choose representative work.
scripts/build-slot.sh build mylang juice record app/juice.toml \
  --name before --profile runtime --cpu 10 --repeats 9
# Build/capture the candidate, then compare its record with before/record.json.
mylang juice validate-runtime comparison.json timing.json --output validation.json
```

`timing.json` uses the existing `juice-timing-evidence-v1` format: `base_id`,
`candidate_id` and `context_id` copied from the comparison, a `workload` name,
a nonempty `method`, and `pairs` of `[baseline_seconds, candidate_seconds]`.
Use at least five independent, alternating baseline/candidate executions of
the exact compared artifacts, on the same CPU, inputs, environment and scope.
Do not use the collector's `wall_seconds` as timing evidence. The caller is
responsible for the timing method; the validator checks identities, positive
finite durations, repeatability and the fixed target. It returns 0 only when
`abs(estimated_ratio / measured_ratio - 1) <= 0.05` and the estimate and timings
are repeatable. It returns 1 for outside-target or uncertain results, and 2 for
invalid evidence. A pass applies to that measured case only.

The developer driver `scripts/juice_runtime_bench.py` runs this process on a
declared suite of prebuilt executable pairs. It verifies SHA-256 identities,
alternates counter captures, records scheduling/frequency policy, reuses cached
builds, retains original and aggregated
records, checks output oracles on every execution, and measures elapsed time in
separate alternating runs. It takes a nonblocking shared runtime timing lock, so
a busy timing runner produces an immediate error. Example:

```bash
python3 scripts/juice_runtime_bench.py suite.json --compiler /path/to/mylang \
  --cpu 10 --output /new/evidence/directory
```

The suite's `cases` each contain `name`, `family`, `base` and `candidate` objects
with absolute `binary` paths and `sha256`, an `args` array and `expected_stdout`.
Optional `stdout_regex` follows the manifest's single-group normalization;
`units` defaults to one. This driver currently handles standalone executables
without external input files. It uses five alternating counter pairs (two
samples per arm per pair), nine independent timing pairs, and one discarded
warmup pair per phase. All failed or uncertain cases remain in the results.

During independent timing, the driver keeps its controller off the measured CPU
and its SMT siblings when the inherited affinity allows it. The workload still
runs on the requested CPU; native capture retains its original affinity because
the collector validates the requested CPU against that mask. Placement is
recorded in `method.json`, and the original affinity is restored after timing,
including on failure. This reduces interference from the controller without
reserving CPUs from other applications.

Each `timing-runs.json` entry includes user/system CPU time, voluntary/involuntary
context switches and minor/major page faults. These are per-command deltas from
`getrusage(RUSAGE_CHILDREN)` in the serial driver, sampled outside the elapsed
interval. They help diagnose interruptions; they neither replace elapsed-time
labels nor cause automatic sample exclusion.

Stronger scheduling isolation belongs on the nightly benchmark host: reserve a
physical core and its SMT siblings from other workloads, and use a dedicated
runner where possible. Linux's
[exclusive cpuset partitions](https://docs.kernel.org/admin-guide/cgroup-v2.html#cpuset)
can prevent tasks outside the partition from using its CPUs; isolated partitions
also disable scheduler load balancing and exclude unbound workqueues. CPU
affinity alone does not provide that guarantee. Longer batches help amortize
startup effects, but neither priority nor a longer scheduling slice guarantees
uninterrupted execution. This driver changes no machine-wide scheduling policy.

For eventual merge screening, use short scenarios that preserve production
working sets and algorithm boundaries. Use independent longer runs on nightly
builds to test new changes and families and track error, missed regressions,
false alarms and abstentions. Until that held-out evidence exists, the runtime
proxy is advisory. `--fail-above` remains an instruction-work gate; it does not
certify runtime performance. No recurring job is installed by these commands.

### Initial evaluation (2026-10-10)

The [retained experiment](../../experiments/juice-runtime-proxy-20261010/method.json)
contains seven selected changes: an identical build, bit-count optimization,
added atomics, copying at two working-set sizes, disabled compiler optimization,
and the preserved Wave 3 tree regression. It uses five alternating counter pairs
and nine independent elapsed-time pairs per case on CPU 10 of an i7-12700H.
The first shared-host run was uncertain in all seven cases.

A follow-up used a faster capture executable and a process-local utilization
clamp (`uclampset -m 1024 -M 1024`); no global frequency settings changed. Paired
aggregation was added after seeing the initial drift, so this remains exploratory
analysis, **not held-out validation**. All observations remain in the archive.
The diagnostic median error was 2.86%, with maximum 4.23%, but only two cases met
both the accuracy target and repeatability rules:

| Case | Diagnostic relative error | Validation |
|---|---:|---|
| Identical executable | 0.29% | Within target |
| Bit-count optimization | 3.57% | Within target |
| Added atomics | 2.86% | Uncertain |
| Added copying | 0.95% | Uncertain |
| Disabled optimization | 4.23% | Uncertain |
| Larger copying working set | 2.88% | Uncertain |
| Wave 3 tree regression | 0.73% | Uncertain |

Diagnostic errors include unstable point estimates; they are not accepted accuracy
claims. [Full results](../../experiments/juice-runtime-proxy-20261010/results-02.json)
retain the counter and timing spreads and every validation verdict. The fixed
5% target is promising on these cases, but **not established as a reliable merge
gate**. A 5% prediction-error budget also cannot reliably enforce a 3%
regression limit. The next qualification needs stable independent timings and unseen changes
and workload families, including memory pressure, system calls, concurrency and
I/O. Broad runtime checks remain necessary until that evidence exists.

### Quiet-machine rerun (2026-10-10)

The [third run](../../experiments/juice-runtime-proxy-20261010/quiet-rerun-method.json)
repeated the same seven executable pairs with unchanged capture and analysis
binaries, CPU, scheduling policy, sample counts, estimator and thresholds.
Before measurement, a one-second sample showed 0.8% aggregate CPU use and
about 1% use on CPUs 2 and 10; this is a starting observation, not
continuous host isolation.

Diagnostic median error improved to **0.69%**, with maximum **2.17%**. All seven
point estimates were within 5%, but **three of seven** passed both accuracy and
repeatability checks (previously two). The other four exceeded the unchanged
3% spread limit for counters, independent timings, or both:

| Case | Diagnostic relative error | Counter pair spread | Timing pair spread | Validation |
|---|---:|---:|---:|---|
| Identical executable | 0.29% | 0.38% | 0.69% | Within target |
| Bit-count optimization | 2.17% | 0.46% | 1.53% | Within target |
| Added atomics | 1.72% | 0.61% | 3.58% | Uncertain |
| Added copying | 1.07% | 8.88% | 10.37% | Uncertain |
| Disabled optimization | 0.69% | 0.46% | 1.48% | Within target |
| Larger copying working set | 0.06% | 5.42% | 5.29% | Uncertain |
| Wave 3 tree regression | 0.22% | 4.35% | 4.12% | Uncertain |

[Full results](../../experiments/juice-runtime-proxy-20261010/results-03.json)
and [archived evidence](../../experiments/juice-runtime-proxy-20261010/quiet-rerun-archive.json)
retain all observations. These results use the paired estimator frozen before
the rerun; the older capture executable's unpaired log summary is superseded by
the paired analysis. This improves the evidence for the selected cases, but
uncertain estimates remain diagnostic and the same-case repeat does not
establish accuracy on unseen changes or workload families.

### Noise diagnostics (2026-10-10)

Six bounded diagnostic experiments retained **702 executions**, including one
warmup pair and twelve measured pairs per condition. They used the same input
binaries on CPU 10, except for an explicitly separate unrolled-copy control.
Each execution checked its output and recorded continuously scheduled grouped
hardware counters, task CPU time, context switches, migrations and page faults.
Conditions alternated baseline/candidate order and shuffled condition order
with a recorded seed. Address randomization was disabled only in individual
`setarch -R` processes; global settings stayed unchanged. The tree's longer
scenario increased iterations from 272 to 4,352, keeping size and seed fixed;
an independent node-contribution oracle checked its new checksum.

The copying fixtures' variation tracks **instruction-front-end delivery**.
In diagnostic-04, candidate cycle counts correlated with unfilled instruction
delivery slots at Pearson r > 0.9998 in all four size/layout conditions.
In diagnostic-05, slower runs received fewer operations from the loop-stream
detector (r = -0.90 to -0.999). These interpretations follow
[Intel's Alder Lake counter definitions](https://perfmon-events.intel.com/platforms/alderlake/core-events/p-core/).
The memory and branch probes did not show enough cache-stall, store-forwarding,
branch-recovery or store-buffer-stall activity to explain the large variation.
Disabling ASLR did not eliminate it. The recorded sibling CPU 11 was idle during
the memory and front-end probes; a brief sibling activity sample in the branch
probe remains in the evidence. There were no measured CPU migrations or major
page faults in any phase.

An intervention expanded the eight volatile stores into eight explicit statements,
preserving their order and subsequent load. The control used the same compiler
flags and output oracle. Individual candidate cycle spreads fell substantially:

| Fixture | Original loop, ASLR on | Explicit stores, ASLR on | Original loop, ASLR off | Explicit stores, ASLR off |
|---|---:|---:|---:|---:|
| Copying | 26.47% | 0.59% | 14.23% | 1.00% |
| Larger copying working set | 14.59% | 0.63% | 10.31% | 0.52% |

These are diagnostic-05 versus diagnostic-06 spreads, not prediction errors.
Together, the counters and intervention strongly implicate the tiny loop's
interaction with front-end delivery. They do not identify the exact hardware
trigger for changes in loop-cache use. The control is a different executable,
so it does not replace or qualify the original noisy cases.

The remaining noise also includes **real scheduling interruptions**. One
explicit-store run took 82.96 ms elapsed versus 70.54 ms of task CPU time and
recorded 467 context switches. A long, fixed-layout tree run took 302.96 ms
elapsed versus 291.32 ms of task CPU time, with 407 context switches. The latter
condition had only 1.12% spread in paired reference-cycle ratios but 3.67% in
the tree's internal elapsed-time ratios. Thus even a stable CPU-cost estimate
can miss the repeatability limit when the process is interrupted. These probes
do not identify the competing process or the cause of the earlier run's delays.

Lengthening the tree improved randomized-layout internal timing spread from
6.08% to 2.50% in diagnostic-03. However, the initial longer trial still had
5.75% spread, and a short fixed-layout trial had an on-CPU outlier retained in
full. Longer runs help with short-duration sensitivity but do not ensure
repeatability. The atomic diagnostic had 0.15% paired cycle spread, 2.76%
reference-cycle spread and 2.95% instrumented elapsed spread; it provides no
evidence of intrinsically unstable atomic work in this run.

[Summary and correlations](../../experiments/juice-runtime-proxy-20261010/diagnostic-summary.json),
[archive receipt](../../experiments/juice-runtime-proxy-20261010/diagnostic-archive.json),
and the [diagnostic runner](../../experiments/juice-runtime-proxy-20261010/diagnose.py)
retain all phases, including failures to stabilize a case. The archive includes
the exact runner version per phase, raw profiles, outputs, source intervention
and build identity. The earlier quiet-host observation sampled CPU 2, not the
currently reported sibling CPU 11; the description above is corrected accordingly.

These instrumented elapsed times are **not independent accuracy labels**. No
5% accuracy or 3% repeatability threshold changed, and the seven-case
qualification remains three accepted and four uncertain. Next qualification
should retain the original difficult cases, add the explicit-store control as
a separate fixture, and use longer tree batches with scheduling telemetry and
stronger CPU isolation. Neither ASLR suppression nor dropping outliers is
supported as a general fix by these results.

### Implemented copy fixture fix (2026-10-10)

The `EXTRA_COPY` path in `examples/juice/native/kernel.c` now uses eight explicit
volatile stores, preserving their order and the subsequent load. This applies
the successful diagnostic control to the fixture; it is not a compiler runtime
optimization. The historical loop measurements remain retained.

Both arms were rebuilt from the updated source, with the original compiler flags,
and measured under distinct `copy-unrolled` and `large-copy-unrolled` case names.
The standard five counter pairs and nine independent timing pairs were used with
the existing paired estimator and thresholds, plus the controller placement and
timing diagnostics described above:

| Fixed fixture | Prediction error | Paired cycle spread | Paired reference-cycle spread | Timing ratio spread | Verdict |
|---|---:|---:|---:|---:|---|
| Copying | 0.33% | 0.36% | 2.45% | 1.68% | Within target |
| Larger working set | 1.14% | 0.60% | 3.07% | 2.41% | Uncertain |

The larger case's diagnostic point estimate is within 5%, but its reference-cycle
spread slightly exceeds the unchanged 3% repeatability limit. No retry or sample
exclusion was used to turn that verdict into a pass. Independent timing runs
recorded two to five involuntary context switches per execution, plus one
voluntary switch. These observations do not isolate the effect of controller
placement from other host changes. Both fixture oracles passed throughout.

[Results](../../experiments/juice-runtime-proxy-20261010/copy-fix-results.json)
and [archived evidence](../../experiments/juice-runtime-proxy-20261010/copy-fix-archive.json)
include raw captures, timing diagnostics, source/build identities, and paired
reanalysis. The frozen older capture executable's unpaired log summary is
superseded by this paired analysis. An initial integration attempt was rejected
before measurement because applying controller affinity during native capture
excluded the requested CPU; the final driver restricts placement to independent
timing, and the rejected attempt is retained separately. These two updated cases
do not requalify the other five or establish accuracy on unseen workloads.

## First comparison

Use a private application copy and choose a baseline label you have not used
before. The cache directory must stay the same between captures; execution
paths affect some applications' work. Use the build slot in this repository:

```bash
mylang juice doctor
scripts/build-slot.sh build mylang juice record examples/juice/native/juice.toml --name before
# Edit kernel.c: change '#define SLOW 1' to '#define SLOW 0'.
scripts/build-slot.sh build mylang juice record examples/juice/native/juice.toml --name after
mylang juice compare \
  ~/.cache/mylang/juice/juice-native-example/records/before/record.json \
  ~/.cache/mylang/juice/juice-native-example/records/after/record.json \
  --mode application --output /tmp/juice-comparison.json
```

The comparison writes JSON and a Markdown sibling. Record labels are immutable;
use a new label for each edit. Raw outputs, collector profiles and incomplete
attempts are retained alongside `record.json`. Baseline capture is reused simply
by comparing later candidate records against it. No baseline rerun is needed.

For mylang, use `examples/juice/mylang/juice.toml`. A manifest compiler of
`"mylang"` resolves to the running compiler binary, including after installation
or relocation. Pass `--compiler /path/to/another/mylang` to test another build. Its adapter builds an ordinary release executable
for native counts and a separate `--counters` executable for explanations. Both
must produce the same verified result. `--static` also collects `mylang cost`
(an extra compile). Compiler host optimization and guest `--release` are separate;
an already-built Debug compiler can emit release guest code.

Comparison modes enforce what is held fixed:

| Mode | Required unchanged |
|---|---|
| `application` | Compiler, build recipe, flags, dependencies and build environment |
| `backend` | Application source contents |
| `combined` (default) | Workload contract and measurement context |

For a backend experiment, keep application source fixed and change
`--compiler` or build flags. When both application and compiler change, capture
the four combinations to separate their effects. Changed fixed inputs, oracles,
units, collector, CPU, installed library contents or execution paths refuse
comparison. Adding/removing a linked library is a program change: it is reported
explicitly, with its startup/work included, and prevents a clean runtime estimate.

## Workload contract

Place `juice.toml` (or an equivalent JSON object) next to the application sources.
The native TOML reader supports the schema shown here: bare keys, ordinary
single/double quoted strings, finite numbers, booleans, arrays (including multiline
arrays and comments), tables and arrays of tables. It rejects multiline strings,
dotted/quoted keys and inline tables; use JSON for contracts needing those forms. Commands are argument arrays,
never implicit shell strings. A minimal native example:

```toml
version = 1
name = "document-parser"
adapter = "native"
sources = ["src/**/*.c", "include/**/*.h"]
inputs = ["fixtures/documents.json"]

[build]
compiler = "cc"
command = ["{compiler}", "-O2", "-g", "{root}/src/main.c", "-o", "{binary}"]
tools = []
dependencies = []
timeout_seconds = 300

[environment]
APP_SEED = "17"

[[workloads]]
name = "documents-quick"
family = "document-parsing"
tier = "quick"
args = ["fixtures/documents.json", "--batches", "4"]
unit = "document"
units = 400
expected_stdout = "checksum=12884\n"
timeout_seconds = 30
weight = 1
```

The checksum above is illustrative; supply your application's oracle. Every
workload requires `expected_stdout`, `stdout_sha256` or a `check` command.
Exit status must be zero and stderr defaults to empty (`expected_stderr` can
declare another exact value). For output files, list their relative names in
`outputs`; their hashes must agree across every repetition and both builds.
An application-specific `check` can validate those files against a golden too.

`check` receives placeholders `{stdout}`, `{stderr}`, `{work}`, `{root}` and
`{binary}`; it runs outside measurement and must exit zero. Put a fixed checker
in `inputs`, so changing the oracle invalidates comparison. If stdout includes a
timestamp, `stdout_regex` must match the **whole** output and have exactly one
capture group containing the semantic result. The expected value/hash and paired
comparison then use that group; original output remains in the evidence.
The native normalizer is a bounded byte regex: one capturing group, noncapturing
`(?:...)`, alternatives, byte classes/ranges, `.`, `^`, `$`, greedy `* + ? {m,n}`,
and ASCII `\d \s \w` (plus their negations). Dot includes newlines. Lookaround,
backreferences, lazy/possessive repeats and Unicode character classes are refused.
Use an explicit `check` command for more elaborate oracles. No host regex library
or interpreter is loaded.

`sources` and `inputs` are disjoint, nonempty-matching relative globs. Sources
are copied into a stable build project, inputs into that project and into a
fresh runtime directory before each trial. `{root}` names the copied project;
`{work}` names the execution directory. Workload arguments can use both. The
executable always runs at `{work}/program`, including the counted mylang build.
No previous trial's output or allocator process state is reused.

Runtime environment is deliberately small: `PATH` is the system default,
locale is C, timezone UTC, and HOME/TMPDIR are private paths. Declare needed
environment values in `[environment]`. HOME, TMPDIR, PWD and collector control
variables cannot be overridden there. Build commands inherit the live build
environment; its digest, not its potentially secret values, is recorded.

Build caching keys all declared source/input contents, build recipe, compiler
hash/version, named `tools`, explicit `dependencies` and build environment.
Declare external SDKs, headers, libraries, build helpers and compiler resources
in `build.dependencies` (files or directories). A compiler launcher alone does
not identify an entire toolchain. Undeclared external build dependencies are
outside the cache contract. An altered cached executable is an error, not a hit.

For mylang, replace `[build]` with:

```toml
[build]
compiler = "mylang"
entry = "main.my"
flags = []
prefix = []
counter_semantics = "my-counter-hook-contract-1"
```

`prefix` can supply a build wrapper. `flags` adds build options without changing
release mode, outputs or instrumentation. Declare imported application modules
and project configuration in `sources`. Installed compiler resources or linked
foreign code outside the snapshot belong in `dependencies`. The adapter also
records the Zig tool identity (`ZIG`, then `MYLANG_ZIG`, then `zig`).

`counter_semantics` is an explicit contract identifier: update it when the
meaning or coverage of runtime hooks changes, even if the JSON format remains
`mylang-counters-v1`. Unlike instruction counts, counter deltas are suppressed
across different hook contracts. Existing allocation-byte counters describe
allocator size classes/usable sizes, **not requested bytes**; realloc movement
and peak footprint are also allocator-dependent. They remain diagnostic fields.

## Fast scenarios for long jobs

Choose application units such as documents processed, records reduced or
queries answered. Do not normalize by internal loop iterations, calls, seconds
or a fixed instruction budget: an optimization may remove that internal work.

Prefer fewer repetitions over unrealistically small data. Preserve working-set
size, data distributions and important branches. Supply several short scenarios
for different input shapes, plus `tier = "validation"` cases with more work.
Use `--tier validation`, `--tier all` or repeat `--workload NAME` to select cases.

For an expensive late phase, write a small harness that loads a representative
saved fixture and calls that phase directly. Fixtures belong in `inputs` and
retain their exact content identities. This avoids repeating the entire setup.
Juice does not automatically checkpoint arbitrary running processes or infer
that a program's first few seconds represent all later phases.

Callgrind also supports `region = "emitted_function_name"`. This measures the
selected function and callees while checking the whole program's output. It
**still executes setup**. A missing/optimized-away region fails with zero work;
for inlined functions use a harness or a surviving enclosing symbol. Region
selection is part of the workload contract and is not supported by `perf`.

Compare quick and larger records separately, then check whether the quick cases
predict the direction and magnitude of that **same source/compiler change**:

```bash
mylang juice validate quick-comparison.json validation-comparison.json \
  --output scenario-validation.json
```

Matching `family` values link the sizes. Default agreement tolerance is 3%;
directions must agree and repetitions must be stable. This establishes agreement
for the measured changes and inputs, not universal whole-job coverage. The
weighted geometric suite index is likewise a summary of selected scenarios,
not a forecast of a full application's duration.

## Collectors, attribution and noise

`perf` is the fast default. It pins the process tree to an allowed CPU, avoiding
this repository's reserved timing CPUs by default. On hybrid x86 it selects that
CPU's explicit PMU. Only user instructions count; another process's CPU work is
not added. Events must report 100% running, without scaling. Unavailable events,
permissions errors and multiplexed counts fail. `--cpu` fixes a chosen CPU;
there is no quiet-machine wait or timing lock.

`--collector callgrind` counts software-observed instructions and atomic events,
with self costs attributed to symbols/source lines where the executable supplies
debug information. Inclusive call arcs are not added twice. `cachegrind` is also
supported. Both operate on the ordinary optimized executable, preserve its
optimization flags and check output against an ordinary execution. Valgrind
cache/branch simulation is disabled; it is not a modern-machine runtime model.
Unsupported instructions fail rather than silently rebuilding for a weaker ISA.

Valgrind must be installed separately. `--valgrind /path/to/valgrind` selects a
launcher; a private installation may also need `VALGRIND_LIB`. Its engine identity
is recorded. Use the same collector and configuration in both arms. Software
instrumentation is slower, so apply it to short cases or harnesses.

Native `perf stat` supplies totals, not per-function counts. Mylang semantic
function/site counters and static code changes can explain those totals;
Callgrind/Cachegrind supply machine-level function/line attribution. Missing
debug information remains unknown. Line moves appear as added/removed locations;
the report does not invent correspondence across edits. Mylang's existing
source metadata is incomplete for some optimized instructions.

For feedback before any application execution, use `analyze`. It builds the
ordinary optimized executable, inventories code and collects Core costs/LLVM
remarks for mylang. An optional prior analysis produces static differences:

```bash
scripts/build-slot.sh build mylang juice analyze examples/juice/native/juice.toml \
  --output /tmp/static-before.json
scripts/build-slot.sh build mylang juice analyze examples/juice/native/juice.toml \
  --against /tmp/static-before.json --output /tmp/static-after.json
```

This mode requires no collector and produces no juice score. For mylang, cost
collection supports default flags, `--no-facts` and `--verify-facts`; other build
flags leave the Core cost report explicitly unavailable rather than collecting
remarks for different code. Binary measurements still use the requested flags.

The index is `100 * (candidate instructions / units) / (baseline instructions /
units)`. The report includes observed min/max repeat ranges, not confidence
intervals. Default limits are 0.5% within-arm spread and a 0.1% material-change
floor (`--max-spread`, `--min-change`). Unstable/overlapping results are uncertain;
instruction savings with increased atomic, copying or allocation work are mixed.
Static atomic/division-site increases also flag unresolved hotness. Code bytes
are always diagnostic and never substituted for execution counts.

`--fail-above 101` opts into a **work** gate: uncertain/mixed results or any case
above 101 fail. No elapsed-time target is certified. More threads, contention,
cache misses, I/O, dependency chains and expensive instructions can change
runtime without proportionally changing instruction count. Total CPU work does
not measure parallel latency or time spent waiting.

## Optional runtime calibration

No runtime model ships as validated. Juice can fit a CPU-bound trend model using
explicit timing evidence, but never trains from capture wall time automatically.
Wall time in records tells you how long the development loop took on this host.

The model is `runtime_ratio = instruction_ratio ** exponent`, with ratio 1 fixed
at 1. Calibration needs at least six training observations across two families
and three held-out observations from disjoint families. Each timing evidence
file must identify the comparison's exact `base_id`, `candidate_id`, `context_id`
and workload, describe its method, and contain at least five paired durations.
Ratio spread above 3%, duplicate observations, unresolved cost risks, max
held-out error above 10% or direction accuracy below 80% reject calibration.

Dataset format (repeat `points` for the required observations):

```json
{"version":"juice-calibration-data-v1","points":[
  {"comparison":"comparison.json","workload":"documents-quick",
   "timing_evidence":"timing.json","split":"train"}
]}
```

Timing format (IDs copied from the comparison, times measured independently):

```json
{"version":"juice-timing-evidence-v1","method":"describe the actual timing protocol",
 "base_id":"...","candidate_id":"...","context_id":"...",
 "workload":"documents-quick","pairs":[[1.0,0.9],[1.0,0.9],[1.0,0.9],[1.0,0.9],[1.0,0.9]]}
```

```bash
mylang juice calibrate calibration-data.json --output model.json
mylang juice compare before/record.json after/record.json \
  --model model.json --output comparison.json
```

Models refuse a different measurement context and abstain on unseen families,
changes outside the calibrated range, unstable counts or unresolved cost risks.
Held-out error is reported as validation evidence, not a statistical guarantee.
Representative timing calibration is occasional work; the edit loop continues
to use instruction measurements without waiting for an idle host.

## Verification and retained evidence

`zig build test-juice` runs the reference tests and native CLI tests, including
relocation with an empty `PATH`, comparison/calibration parity, cache integrity,
immutable captures, failed oracles and incomplete counts. It needs no PMU or
Valgrind and is part of the full gate. `test-core -Dtest-filter=Juice` covers the
native parsers, normalization and process deadlines.
Real collector qualification, including load interference and known regressions:

```bash
scripts/build-slot.sh build python3 scripts/juice_validate.py \
  --output .mylang-cache/juice-qualification \
  --compiler /path/to/mylang --valgrind /path/to/valgrind
```

The output directory must be new. All source changes occur in private copies.
`--base-compiler` optionally adds a pre-P1/P1 backend comparison using distinct
counter contracts. Qualification covers algorithm changes, backend optimization,
extra copies, atomics, missed vectorization, selected phases, source attribution,
short/large agreement and same-CPU competing processes. It does not establish
elapsed-time prediction accuracy. See the implementation's saved
[qualification report](../audits/performance-proxy-2026-10-09.md).

## Saved evidence and native identities

Native Juice reads existing `juice-v1` records, checks their evidence hashes and
writes the same report schemas. The native canonical JSON identity scheme is
named `mylang-juice-native-v1`; it is distinct from Python's JSON serialization.
Existing captures can be reused, but regenerate comparison reports before
combining native quick/large validation or matching timing evidence. Never edit
old identity fields to force compatibility. Calibrations use the identities in
the supplied reports and reject mismatches. Native build receipts additionally
include the embedded compiler source/toolchain/optimization identity, so a tool
upgrade invalidates build reuse without repeatedly hashing the large host binary.
An external guest compiler is fingerprinted by executable bytes. The running
mylang compiler uses its existing embedded source/toolchain/optimization identity,
explicitly labeled `mylang-embedded-build-v1` with `source_sha256`, not an executable
SHA-256. This preserves the fast loop with Debug compiler installations too.

Windows, macOS and ARM capture are future work. See the
[cross-platform design](juice-portability.md) for collector capabilities,
per-target baselines and the planned portable instrumentation fallback.
