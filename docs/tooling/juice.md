# Juice: a fast performance proxy

Juice compares **instructions per completed application unit**, with baseline
100. A score of 92 means 8% fewer instructions for equivalent work. It does
**not** mean 8% less elapsed time. Allocation, copying, atomic operations,
generated code, source attribution and repeat variability help explain the
result. Ordinary use needs neither an idle machine nor a full production run.

Juice is built into the installed compiler: `mylang juice --help`. All six
commands run native Zig code; no Python interpreter, repository checkout or
companion script is needed. It supports generic native programs and mylang
applications. Capture currently requires Linux x86_64, a build toolchain and
`perf` or Valgrind. Binutils provides optional static diagnostics; `ldd` identifies
loaded libraries. Comparing, validating and calibrating saved JSON needs only
the compiler binary. The original `scripts/juice` Python tool remains a developer
reference for differential tests, not an installed dependency.

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
