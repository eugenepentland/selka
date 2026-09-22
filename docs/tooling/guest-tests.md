# Guest tests

`mylang test` is the compiler's own runner for tests written in the language. It
checks the project, finds the exported functions whose names begin with `test_`,
builds them natively and runs each one in its own process. Cases are configured
with one JSON file rather than with a framework inside the language, and the
runner itself needs no Python. The default `Debug` build uses QBE and stays
Python-free; `mylang test --mode ReleaseFast` builds the LLVM release path and
therefore needs the installed adapter, exactly as `mylang build` does. The
design record is
[the guest test workflow](../experiments/guest-tests.md).

## `mylang test`

The command discovers `test_` functions in the project's reachable public
schema. A parameter-free test returning `bool` asserts `true`; any other result
type needs an explicit expected typed JSON value, so an undeclared expectation is
a configuration error rather than a silent pass. `--cases FILE` supplies
arguments, expectations and skip reasons keyed by qualified test name, and
`--filter` selects qualified names case-sensitively: a pattern carrying no `*`,
`?` or `[` matches any substring of the qualified name, and one that carries them
is a shell-style glob. Each selected case runs
as a fresh native process bounded by `--max-steps`, `--max-frames`, `--max-calls`
and `--timeout-ms`, with no implicit clock, entropy, filesystem, network or
environment grants. `--json` prints a `native-tests-v1` report instead of the text
summary. Exit status is 0 when every selected runnable case passed, 1 on a
failure or trap, 2 on a setup failure, and 3 when the selection was empty or
entirely skipped — a filter that matches nothing is not a green run.

```console
$ mylang test examples/testing/main.my
passed main::test_square
passed main::test_sum
2 passed, 0 cached, 0 failed, 0 skipped
$ mylang test examples/testing/main.my --filter 'main::test_nothing'
0 passed, 0 cached, 0 failed, 0 skipped
$ echo $?
3
```

### Test entries

A test entry is a `.my` file, not necessarily a program. A library module without
`main`, or a standalone file named `*_test.my`, is accepted: the runner checks a
private copy with a stub `def main() -> int: return 0` appended, so the exported
`test_` functions run without editing the source or weakening the `main`
requirement for ordinary `run`. A bare `*_test.my` file without a `module`
declaration also gains a matching header in the private copy.

A standalone `*_test.my` may sit in a subdirectory of the project. The runner
resolves its `import`s and its module name from the enclosing project root: the
nearest ancestor holding `mylang.json`, or the nearest ancestor holding a
non-test `.my` source. `tests/parser_test.my` is therefore module
`tests.parser_test`, and `import sexpr.parser` reads `sexpr/parser.my` from the
project root. A file with no `module` header gains the dotted header
automatically; a file that writes one must spell the dotted path. A child
compiler's located diagnostic is reported on its own, with exit status 1 rather
than the generic host-failure line.

### Failure text

A failed expectation reports both sides of the comparison as
`expected <value>, got <value>` instead of a value-less sentence, and a failed
`assert` keeps its `R_ASSERT` code and source location and reports the message
written after the condition as `R_ASSERT: <message>`. Guest output written by
`print` is redirected off the runner's binary protocol channel and captured; the
runner appends it to a failure's text, so a debug print is visible without
aborting the run. A passing test's output is captured and discarded, and a
benchmarked function's output goes to the diagnostic stream so timing batches
never corrupt the protocol.

```console
$ mylang test main.my --filter test_total
failed main::test_total: expected 42, got 41
0 passed, 0 cached, 1 failed, 0 skipped
$ mylang test main.my --filter test_reading
failed main::test_reading: R_ASSERT: x should be two
  in main::test_reading at main.my:6:5

reading 41 rows
0 passed, 0 cached, 1 failed, 0 skipped
```

## Directory runs

The positional argument may be a directory instead of one entry. Every project
root beneath it is selected in sorted path order: a `.my` file that declares a
top-level `main`, plus standalone `*_test.my` files. A library module imported by
a root is not run as a program of its own, so a multi-module project is one
program rather than one `E_MAIN`/`E_MODULE_NAME` failure per module; its tests
run once, as part of that root. A library that declares a test (a `def test_`
function or an `@test` one) and that no root's import closure reaches is
selected as well and checked through the stub-`main` projection above, so a
test file needs neither `main` nor the `*_test.my` suffix. Of two such
libraries where one imports the other, only the importer is selected. Generated
`.mylang-cache`, `.zig-cache`, `zig-out` and `.git` trees are skipped, and each
root runs as its own child command, up to the machine's core count at a time.
The children share one object cache and one receipt directory, so an unchanged
program reuses its results instead of rebuilding, and the runtime archive every
program links is built once for the whole suite. Their reports merge into one
case listing, one count line naming how many programs took part, and the most
severe exit status: 2 if any program failed to set up, 1 if any case failed, 3
if the whole selection was empty or skipped, and 0 otherwise. `--cases` is
rejected for a directory run, because its keys name the tests of one project.

Each child's `--json` report lists the project sources its check loaded as
`modules`. After merging, the directory run names every test-declaring source
beneath the directory that no reporting child loaded as `not run: <path>
(declares tests, but no program loaded it)`, adds `N test sources not loaded` to
the count line and `unloaded` to the JSON report, and exits 2. A test file can
therefore fail a run, but it can never silently drop out of one.

On a corpus of 100 small programs with 200 tests, a cold run takes about 7
seconds, an unchanged rerun about 0.6 seconds, and a run after editing one
program about 0.8 seconds — re-executing only the two tests that program owns.

```console
$ mylang test suite/ --cache-dir /tmp/suite-cache
passed prog000::test_scale0
passed prog000::test_sum0
200 passed, 0 cached, 0 failed, 0 skipped across 100 programs
$ mylang test suite/ --cache-dir /tmp/suite-cache --filter test_scale4
cached prog004::test_scale4
cached prog040::test_scale40
0 passed, 11 cached, 0 failed, 0 skipped across 100 programs
```

## Reusing unaffected results

Allocation and process-local mutation are deterministic for keyed test inputs,
so they do not prevent successful-result reuse. Actual external effects,
including output, clock, randomness and environment access, still prevent it.
The stricter `--pure-skip` signature rule still excludes declared mutation.

The source identity covers the resolved import closure and required configuration
and policy files. An edit to an unimported neighboring module neither discards
checked facts nor aborts an ordinary run with `SourceChanged`. Provider replacement
still verifies the full captured inventory because a fixture can introduce imports.
The environment fingerprint includes compiler/build controls rather than every
inherited variable, so shell/session metadata does not discard warm caches.
This includes native C search/link paths, Python adapter controls, Zig installation
overrides and reproducible-build settings as well as Mylang compiler controls.
Dynamic-loader overrides disable durable result reuse, and tests with environmental
effects remain non-cacheable. Resolved native tool stamps remain part of identity.

A warm unchanged deterministic run still checks project validity through the shared
query cache, but admits valid result receipts without lowering, emitting or linking
any code, so it executes zero tests. Receipt reuse is bound to the selected
dependency closure, contract and provider identities plus fixture, environment and
budget identities; a helper edit executes only its dependent tests. A fully cached
selection also needs durable checked facts (`native-test-graph-v3`), keyed by
compiler/tool stamps, mode, environment hash, source identity and canonical
provider identity. The graph stores the requested input key in its envelope,
checksums its payload, and rejects a missing, damaged, wrong-version or
structurally invalid graph; an intact graph copied under another key is a miss
rather than a stale success. `mylang test --report` emits a `work-report-v1`
line whose `executed_tests.performed`/`reused` counts reconcile with the
`native-tests-v1` `executed`/`cached` fields.
`--force` skips existing graph and result reuse but may publish refreshed graphs
and successful receipts, whereas `--no-cache` performs no durable result or graph
reads and writes at all.

When facts or receipts miss, one checked compilation per selected provider graph
produces the test facts and is retained in that graph's `native-test-compile`
session; the planner then selects only the uncached tests' reachable function
closure, including required adapters, specializations, runtime support and a
conservative set around indirect calls and codec boundaries. Selective lowering
consumes that same checked result, and the linking driver consumes its checked
frontend manifest (`--manifest-file`) instead of spawning a second frontend, so
each provider graph is fully checked once. Only that closure is lowered, emitted,
compiled and linked, so a helper edit does not rebuild the whole selected-provider
project. A whole-project request with no selection keeps its own frontend check
and is reported as a named `work-report-v1` bypass rather than hidden. Distinct
provider graphs stay isolated; identical graphs share one closure and library per
invocation.

A successful deterministic case leaves a receipt under `.mylang-cache/tests`, or
under `--cache-dir DIR`. The receipt's identity covers the case settings, the
call signature, the execution limits, the semantic dependency closure the test
actually used, and the compiler and native build environment, so a later run can
report `cached` instead of executing. Editing a helper invalidates the tests that
reach it and leaves the others reusable; whitespace and unrelated edits keep
results valid. Failures, traps and corrupt receipts are always re-executed, and
`--force` re-executes every selected unskipped case. This reuses result
receipts, native objects, per-function checked bodies and the reduced
preparation graph; project validity is still checked through the shared query
cache on every invocation.

```console
$ mylang test app/main.my --cache-dir /tmp/test-cache
passed main::test_square
passed main::test_sum
2 passed, 0 cached, 0 failed, 0 skipped
$ sed -i 's/return left + right/return right + left/' app/main.my
$ mylang test app/main.my --cache-dir /tmp/test-cache
cached main::test_square
passed main::test_sum
1 passed, 1 cached, 0 failed, 0 skipped
```

## Collector stress

`mylang test --gc-stress` runs every collected test's copied-value call with the
runtime's stress collector, the same collector coverage the Zig root's
`native_execute` tests get from the `--gc-stress` argument they pass to a guest.
A directory run forwards the flag to every child, so one invocation reports one
collector condition, and the flag is part of the execution identity a receipt
binds: a result recorded without stress is not reused as a stressed pass, and a
stressed pass is not reused for a later run without the flag.

```console
$ mylang test tests/lang --cache-dir /tmp/lang-cache --gc-stress
passed integers::test_width_conversions
...
6 passed, 0 cached, 0 failed, 0 skipped
$ mylang test tests/lang --cache-dir /tmp/lang-cache --gc-stress
cached integers::test_width_conversions
...
0 passed, 6 cached, 0 failed, 0 skipped
```

## Affected selection

`mylang test --affected --against REF` narrows a run to the tests that reach a
declaration whose own source lines changed since `REF`. It reads the changed
lines from `git diff` in the entry file's own repository, checks the project, and
walks the resolved call graph from each discovered test; a test runs only when a
changed declaration is reachable from it. The derivation is a selection, never a
verdict: the selected count and every skipped test are printed on stderr, so
`--json`'s stdout report stays machine-readable, and an empty derivation exits 3
exactly as a filter that matches nothing does. `--filter` still applies first,
`lint --gate` and CI run the whole set, `--against` without `--affected` (or the
reverse) is a usage error, and a `REF` that `git` cannot resolve is a host
failure. A project that cannot be checked for another reason runs the whole
discovered set rather than silently skipping tests.

```console
$ mylang test app/main.my --affected --against HEAD
affected: 1 selected, 1 skipped against HEAD
skipped main::test_unrelated: no changed declaration is reachable
passed main::test_total
1 passed, 0 cached, 0 failed, 0 skipped
$ mylang test app/main.my --affected --against HEAD   # nothing changed since HEAD
affected: 0 selected, 2 skipped against HEAD
skipped main::test_total: no changed declaration is reachable
skipped main::test_unrelated: no changed declaration is reachable
0 passed, 0 cached, 0 failed, 0 skipped
$ echo $?
3
```

## Isolated source provider fixtures

A case may carry a `providers` object mapping existing dependency `.my` paths to
replacement source text. The runner parses every reachable module and validates
its exported declarations and interfaces first, then copies a bounded inventory
of the project's sources into a private directory, applies the replacements
there, and fully checks only the selected provider graph. A replacement is
validated against every public contract it replaces — names, defaults, types
and nominal identities, data shapes, generic requirements, declared effects,
mutation footprints and return-origin bounds — with the directional subset
relation: a narrower implementation is accepted, a stronger one rejects. The
unselected production bodies are not checked, so an unfinished body may be
`todo[T]()` or contain a body type error while its declarations stay valid,
but a production interface error or a syntax error still rejects. The original files are never modified. A
fixture cannot replace the test entry or introduce a path the project does not
already have; source snapshots reject symbolic links and are bounded to 16 MiB,
with at most 128 files for a provider snapshot. Invalid fixture source or a
changed public contract is a setup failure, and the fixture settings are part of
the receipt identity, so changing an injected value re-executes the case.
Cases that select the same provider graph share one declaration validation,
checked project and prepared native library within an invocation, while each
case still executes in its own isolated request directory and process. Receipt
acceptance uses the selected test's dependency closure plus the contract and
provider identities; an unrelated source edit does not invalidate an unaffected
case.

```console
$ mylang test app/main.my
failed main::test_reading: actual value does not match expected value
0 passed, 0 cached, 1 failed, 0 skipped
$ cat cases.json
{
  "main::test_reading": {
    "providers": {"reading.my": "module reading\nexport sample\n\ndef sample() -> int:\n    return 42\n"}
  }
}
$ mylang test app/main.my --cases cases.json
passed main::test_reading
1 passed, 0 cached, 0 failed, 0 skipped
```

## Deterministic provider fixtures

The native runner registers no host callbacks and grants no ambient authority, so
a test that reaches a clock, an entropy source or the environment through a
`host def` declaration fails with `HostMissingRegistration` rather than reading
the real machine. A case makes such a dependency deterministic by replacing the
module that declares it with ordinary guest source returning a fixed value. The
substitution lives in the private snapshot, is captured in the receipt identity,
and is therefore stable across runs and reusable. These are source-level
replacements, not registered native providers: they change what the guest
computes, and they do not validate a real host implementation of the same
declaration.

```console
$ mylang test app/main.my
failed main::test_stamp: HostMissingRegistration

0 passed, 0 cached, 1 failed, 0 skipped
$ cat cases.json
{
  "main::test_stamp": {
    "providers": {"clock.my": "module clock\nexport now\n\n\ndef now() -> i64:\n    return 1700000000\n"}
  }
}
$ mylang test app/main.my --cases cases.json
passed main::test_stamp
1 passed, 0 cached, 0 failed, 0 skipped
```

## Performance benchmarks

`mylang test --bench PATTERN` discovers exported `bench_` functions beside the
`test_` functions, runs the correctness tests first, and measures only after they
pass. One invocation of a benchmark function is one operation; the harness owns
repetition. Benchmark filtering is independent of `--filter`, and `--cases` is
shared: a benchmark uses the same typed arguments, expectations, skips and
provider substitutions as a test, and may declare `sizes` so one function covers
small, medium and large inputs. Boolean results default to `true`; other result
types need an explicit expectation. `--bench-only` skips the correctness pass for
local iteration.

```console
$ mylang test app/main.my --bench '*' --mode ReleaseFast
passed main::test_square
1 passed, 0 cached, 0 failed, 0 skipped
bench main::bench_sum[small] measured median=12.40 ns/op spread=1.20% samples=9
benchmarks: 1 measured, 0 compared, passed
$ cat cases.json
{
  "main::bench_sum": {
    "sizes": {"small": {"arguments": {"limit": "1000"}, "expected": "499500"}}
  }
}
```

The declared timing boundary is the complete native copied-value call, including
argument and result codec costs. Compilation, process startup, library loading,
fixture preparation and report serialization are excluded. Every operation is a
fresh copied-value call, so no guest state carries between operations, and the
returned value is validated outside every timed region. A trap, an incorrect
result, a timeout or an invalid output fails the run and is listed in the
candidate's failures instead of producing a measurement. `--bench-warmup`,
`--bench-batches` and `--bench-batch-ms` tune sampling, and `--bench-timeout-ms`
bounds the whole child. A directory run measures one program at a time so timing
batches never compete, and it rejects `--bench-output`, `--bench-baseline` and
`--bench-policy` because it has no single aggregate report.

### Reviewed baselines

`--bench-output FILE` writes an atomic candidate report containing provenance,
raw batch durations, medians and spreads. A candidate is not an approved
baseline: promote it with `bench-promote`, which requires a complete, passing
candidate and records the approver, reason, revision and the replaced
measurements in retained history. The approved file is never modified by a
comparison.

```console
$ mylang test app/main.my --bench '*' --mode ReleaseFast \
    --bench-output perf/candidate.json
$ mylang bench-promote --candidate perf/candidate.json --baseline perf/baseline.json \
    --approver maintainer --reason "accept 4% growth" --revision testrev
$ mylang test app/main.my --bench '*' --mode ReleaseFast \
    --bench-baseline perf/baseline.json --bench-policy perf/policy.json
```

`perf/policy.json` supplies default and per-benchmark `allowed_growth_percent`,
`minimum_meaningful_delta_ns` and an independent `max_ns_per_op` ceiling, the
`required` benchmark suite and the noise budget. A relative regression is flagged
only when both the percentage limit and the absolute floor are exceeded;
equality with a limit passes and zero percent tolerance is valid. Runs are
compared only when their optimization mode, runner profile, boundary version,
sampling configuration, workload version and fixture identity match, so ordinary
code and compiler revisions stay comparable. New, removed, skipped, incompatible
and unresolved-noise results are explicit non-pass verdicts, and a near-limit or
noisy sample earns at most one predefined confirmation whose batches are
evaluated together. Malformed artifacts, unknown schema versions, duplicate
benchmark IDs, invalid numbers and nonpositive baselines are rejected.
