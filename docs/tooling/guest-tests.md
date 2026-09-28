# Guest tests

`mylang test` is the compiler's own runner for tests written in the language. It
checks the project, finds the exported functions whose names begin with `test_`,
builds them natively and runs each one in its own process. Cases are configured
with one JSON file rather than with a framework inside the language, and the
runner itself needs no Python. Its builds use QBE in either mode (`Debug` by
default) and stay Python-free; `mylang test --release` builds the LLVM release
path (ReleaseFast, `-O3` with LTO) and therefore needs the installed adapter,
exactly as `mylang build --release` does. The
design record is
[the guest test workflow](../experiments/guest-tests.md).

## `mylang test`

The command discovers `test_` functions in the project's reachable public
schema. A parameter-free test returning `bool` asserts `true`, and one returning
`Result[bool, E]` asserts `Ok(True)`, so it may use `?` and a failure it
propagates is reported with its
[error return trace](../results-and-options.md#error-return-traces); any other result
type needs an explicit expected typed JSON value, so an undeclared expectation is
a configuration error rather than a silent pass. A test with data parameters and
no cases-file `arguments` is a [property test](#property-tests): the runner
generates its inputs. `--cases FILE` supplies
arguments, expectations and skip reasons keyed by qualified test name, and
`--filter` selects qualified names case-sensitively: a pattern carrying no `*`,
`?` or `[` matches any substring of the qualified name, and one that carries them
is a shell-style glob. Each selected case runs
as a fresh native process bounded by `--max-steps`, `--max-frames`, `--max-calls`
and `--timeout-ms`, with no implicit clock, entropy, filesystem, network or
environment grants; a test that declares one of those capabilities as a
parameter receives a deterministic stand-in instead
([capability parameters](#capability-parameters)). The cases run concurrently: `--jobs N` (then `MYLANG_JOBS`,
then the cores the run may use, capped by how many per-test memory ceilings the
machine's free memory holds) worker threads each start one test process at a
time without copying the runner, and every result is reported in the same order
whichever finished first. `--json` prints a `native-tests-v1` report instead of the text
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
requirement for ordinary `run`. Any file without a `module` declaration — a bare
`*_test.my`, or a single-file script with its own `main` and `test_` functions —
also gains a matching header in the private copy, written in front of the first
line so that every diagnostic and failure keeps the line number of your file.
`mylang test` therefore accepts every file that `check`, `run` and `build` accept.

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

## Capability parameters

A test may declare `clock: Clock`, `entropy: Entropy`, `fs: Filesystem`,
`env: Environment` and `net: Network` parameters, beside `out: Stream` and
`err: Stream`, and pass them to the code under test. None of them needs a
cases-file argument: the runner hands each one a deterministic stand-in, the same
ones [`time.simulated_clock`, `random.seeded_entropy`, `filesystem.memory`,
`environment.fixed` and `network.denied`](../effects.md#deterministic-stand-ins)
build.

| Parameter | What the test receives |
| --- | --- |
| `Clock` | a simulated clock reading 2000-01-01T00:00:00Z (`946684800000000000` Unix nanoseconds) until `time.advance` moves it |
| `Entropy` | a SplitMix64 stream seeded with the first eight bytes, little-endian, of the SHA-256 of the test's qualified name, or with `N` under `mylang test --seed N` |
| `Filesystem` | an empty in-memory filesystem |
| `Environment` | an environment with no names |
| `Network` | a network that refuses every connection with `network.denied_here()` |

No test is ever handed real authority: a `Host` parameter is not supplied, and
without cases-file arguments such a test fails as a property test whose `Host`
parameter cannot be generated. Every test gets its own
stand-ins, so nothing one test writes is visible to another, and each test's
entropy stream is its own and stays the same from run to run; renaming the test
changes it, and `--seed N` pins every test's (a directory run forwards it). The
seed and the start instant are part of a result receipt's identity, so an
unchanged test that takes capabilities is reused like any other, and a
different seed executes it again.

```mylang
# doc: expect True True
import random
import time

# Whole seconds since `start`, as a caller of the clock sees them.
def uptime(clock: Clock, start: time.Instant) -> int:
    match time.now(clock):
        case Ok(current):
            match time.elapsed(start, current):
                case Ok(span):
                    return time.to_milliseconds(span) // 1000
                case Err(_):
                    return -1
        case Err(_):
            return -1

# A die roll drawn from the entropy a caller supplies.
def roll(entropy: Entropy) -> int:
    match random.from_entropy(entropy):
        case Ok(sampled):
            generator = sampled
            match random.randint(mut generator, 1, 6):
                case Ok(value):
                    return value
                case Err(_):
                    return 0
        case Err(_):
            return 0

public def test_uptime_counts_whole_seconds(clock: Clock) -> bool:
    start = time.from_unix_nanoseconds(946684800000000000)
    _ = time.advance(clock, time.nanoseconds(90500000000))
    return uptime(clock, start) == 90

public def test_roll_stays_on_the_die(entropy: Entropy) -> bool:
    value = roll(entropy)
    return value >= 1 and value <= 6

def main(out: Stream) -> int:
    clock = time.simulated_clock(time.from_unix_nanoseconds(946684800000000000))
    out.print(test_uptime_counts_whole_seconds(clock), test_roll_stays_on_the_die(random.seeded_entropy(1)))
    return 0
```

```console
$ mylang test app/main.my
passed main::test_roll_stays_on_the_die
passed main::test_uptime_counts_whole_seconds
2 passed, 0 cached, 0 failed, 0 skipped
$ mylang test app/main.my
cached main::test_roll_stays_on_the_die
cached main::test_uptime_counts_whole_seconds
0 passed, 2 cached, 0 failed, 0 skipped
$ mylang test app/main.my --seed 7
passed main::test_roll_stays_on_the_die
passed main::test_uptime_counts_whole_seconds
2 passed, 0 cached, 0 failed, 0 skipped
```

`main` above builds the same stand-ins itself, which is how any code — a
helper, an example, a benchmark — gets them: the constructors need no
capability, and using a stand-in is not an effect of a function whose own
parameters supply none ([deterministic stand-ins](../effects.md#deterministic-stand-ins)).

## Property tests

A `test_` function with data parameters and no `arguments` in the cases file is
a property test. The runner generates an input for every data parameter from its
type, hands its capability parameters their
[deterministic stand-ins](#capability-parameters) as it does for any test, and
calls the test once per input: it passes when every input — 100 unless
`--property-runs N` says otherwise — returns `True` (or `Ok(True)`) without
trapping. `False`, `Ok(False)`, an `Err` and a trap (a failed `assert`, a broken
contract, an index out of bounds, an overflow) are failures. A cases-file entry
with `arguments` still wins: the test then runs once with exactly those.

```mylang
# doc: check
module main

@invariant(self.low <= self.high, "a span never runs backwards")
public record Span:
    low: int
    high: int

def total(xs: list[int]) -> int:
    sum = 0
    for x in xs:
        sum = sum + x
    return sum

public def test_reversing_twice_is_the_identity(xs: list[int]) -> bool:
    ys = xs.copy()
    ys.reverse()
    ys.reverse()
    return ys == xs

@requires(len(xs) > 0, "an average needs a value")
public def test_average_is_within_range(xs: list[i32]) -> bool:
    mean = total([int(x) for x in xs]) // len(xs)
    return int(min(xs)) <= mean and mean <= int(max(xs))

public def test_a_span_is_ordered(span: Span) -> bool:
    return span.low <= span.high

public def test_budget_stays_below_100(costs: list[int]) -> bool:
    return total(costs) < 100

def main() -> int:
    return 0
```

```console
$ mylang test app/main.my
passed main::test_a_span_is_ordered
passed main::test_average_is_within_range
failed main::test_budget_stays_below_100: falsified after 8 passing runs (seed 8562780449005306539)
  minimal input (62 shrinks, 512 attempts):
    costs = [100]
  original input (run 9):
    costs = [1, 9223372036854775807]
  reason: returned False
  original reason: R_OVERFLOW (add: left 1, right 9223372036854775807, width 64)
      in main::total at main.my:11:19
      in main::test_budget_stays_below_100 at main.my:29:12
  reproduce: mylang test app/main.my --filter 'main::test_budget_stays_below_100' --seed 8562780449005306539
passed main::test_reversing_twice_is_the_identity
3 passed, 0 cached, 1 failed, 0 skipped
```

### Generated inputs

Inputs are deterministic. They are drawn from a SplitMix64 stream seeded by the
test's seed — the same one its `Entropy` stand-in gets: the first eight bytes of
the SHA-256 of its qualified name, or `N` under `--seed N` — and the run number,
so run 37 of a property is the same value on every machine, and renaming the test
draws new ones. Sizes grow from 0 on the first run to 100 on the last: a
collection holds up to the size at the top level and half of it for every level
it is nested, and an input stops growing collections once it holds 4096 nodes.

| Type | What is generated |
| --- | --- |
| integers (`int`, `i8`…`u64`) | three draws in eight from the edges of the width — 0, 1, -1, the minimum and maximum, a power of two, one below it and its negation — one uniformly over the width, the rest near zero, growing with the size |
| `bool` | `True` or `False` |
| `float` | small binary fractions, bit patterns from the whole range, and on purpose both zeros, both infinities, NaN, the largest finite and the smallest subnormal magnitudes; the language observes each consistently (a NaN is `nan` and unequal to itself) |
| `str` | seven scalars in ten printable ASCII, plus tab, newline, NUL and other controls, well-known non-ASCII scalars (`é`, `Ω`, `中`, `😀`, a combining accent, U+FEFF, U+10FFFF) and scalars from the whole range |
| `bytes` | octets, a quarter of them 0, 1, 0x7F, 0x80 or 0xFF |
| `list[T]`, `set[T]`, `dict[K, V]` | elements or entries of the element types; a set element or a dictionary key drawn twice is dropped, so keys of every hashable type work |
| tuples, records | fieldwise |
| fixed arrays, enum-indexed tables | every element or entry |
| enums, unions, `Option[T]`, `Result[T, E]` | a case drawn uniformly, then its payload |

A `class` (its values have identity), a `domain` (built only through its own
constructors), a function value and `Host` are never generated: a property test
with a parameter whose type reaches one fails, naming the parameter and the
type, and so does one whose result is not `bool` or `Result[bool, E]`. With a
`class Box` and a `test_boxes(boxes: list[Box]) -> bool` in the same module:

```console
$ mylang test app/main.my --filter test_boxes
failed main::test_boxes: property test parameter `boxes: List<main::Box>` cannot be generated: it holds main::Box, and a class value has identity, so it is built by its own code rather than generated
0 passed, 0 cached, 1 failed, 0 skipped
```

### Preconditions and invariants

An input that breaks the test's own `@requires` is discarded, not failed:
`test_average_is_within_range` above never sees an empty list. A value the
runner generates was not built by a constructor, so every `test_` function also
checks, on entry, the [`@invariant`](../contracts.md#invariants) of every record
or domain its parameters hold — in fields, list, set and dictionary elements,
arrays, tuples and every union case — and an input that breaks one is discarded
the same way: `test_a_span_is_ordered` only ever sees ordered spans. A
precondition that a function the test calls breaks is a failure like any other.
Discarded inputs are replaced by more runs; when more than ten times the
requested runs have been discarded the test fails, naming the clause that
rejected the most. A collection of invariant-carrying records is accepted or
discarded as a whole, so a long `list[Span]` is rarely valid; generate the
fields and build the records in the test when that matters. A test that asks
for one exact value, `@requires(n == 12345, "a single value")` on
`test_picky(n: int)`, gives up:

```console
$ mylang test app/main.my --filter test_picky
failed main::test_picky: too many discarded inputs: 1001 of 1001 generated inputs broke a precondition before 0 of 100 runs passed; most often test_picky requires `n == 12345`: a single value
  reproduce: mylang test app/main.my --filter 'main::test_picky' --seed 4128163384585622329
0 passed, 0 cached, 1 failed, 0 skipped
```

### Shrinking and the report

The first failing input is shrunk before it is reported. Each parameter in turn
is replaced by the first of its simpler candidates that still fails (for any
reason), until no candidate of any parameter does or 2,000 candidates have run:
integers move toward 0 by halving the distance (100 tries 0, 50, 75, 88, 94, 97,
99), floats toward `0.0`, strings, bytes and collections first lose elements —
all of them, then halves, quarters and single ones — then shrink the ones left
(never into a set element or dictionary key another one holds), records and
tuples shrink field by field, and enums, unions and `Option` move toward earlier
cases and `None`. The report prints the minimal input as mylang literals, one
line per parameter, the input as generated and its run, the reason — the value
returned (an `Err` with its [error return trace](../results-and-options.md#error-return-traces)), or a
trap's code, message and frames — the original input's own reason
when shrinking reached a different failure, and a command that reproduces the
whole search. An input that ran past `--timeout-ms` is reported as generated,
because every candidate could run as long.

`--json` adds a `property` object to every property test's result: its `seed`,
its `counts` (`runs`, `passed`, `discarded`, `processes`, `shrinks`,
`attempts`) and, for a failure, a `failure` object whose `minimal` and
`original` inputs carry the typed JSON `arguments` a cases file takes and the
`literals` the text report prints.

```console
$ mylang test app/main.my --filter test_budget --json | jq '.tests[0].property.failure.minimal'
{
  "arguments": {"costs": ["100"]},
  "literals": {"costs": "[100]"}
}
```

### Batches and receipts

A property does not pay one process launch per input. The harness process makes
one copied-value call per input and writes each answer as it finishes, so a
passing 100-run property is one process, and every property's first batch runs
beside the others. Replacements for discarded inputs and shrink candidates run
in further batches. A child that dies or runs out of time mid-batch keeps the
answers of the inputs before the one it was running; that input runs alone in a
process of its own, and the rest of the batch in another. On the Debug compiler
a warm 100-run property over `list[int]` takes about 0.2 seconds of
`mylang test`, the whole command included.

A passing property is reused like any other test. Its receipt identity adds the
seed, the run count and the generator version, so changing `--seed`,
`--property-runs` or the compiler's generator runs it again; a failure is never
reused.

```console
$ mylang test app/main.my --filter test_reversing
passed main::test_reversing_twice_is_the_identity
1 passed, 0 cached, 0 failed, 0 skipped
$ mylang test app/main.my --filter test_reversing
cached main::test_reversing_twice_is_the_identity
0 passed, 1 cached, 0 failed, 0 skipped
$ mylang test app/main.my --filter test_reversing --property-runs 500
passed main::test_reversing_twice_is_the_identity
1 passed, 0 cached, 0 failed, 0 skipped
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

Each run materializes its private source snapshot under `$TMPDIR/.pending/` when
`TMPDIR` is set and non-empty, and under `/tmp/.pending/` otherwise. On a host
whose `/tmp` is a small or quota-bound tmpfs, point `TMPDIR` at disk; otherwise
a full `/tmp` fails every test with `host failure: DiskQuota`. The snapshot sits
at the same path on every run of one project from one cache
(`.pending/snapshot-<key>`), because the compiler's caches of check verdicts,
parsed modules and emitted functions are keyed by source path as well as bytes;
a second run of the same project that starts while the first still holds that
path stages at a fresh private one instead.

A run removes that staging on every exit it controls — a pass, a failing test,
a rejected project, a host error. A run killed outright (`SIGKILL`, a crash)
cannot, so each run's staging directory carries a `.owner` marker it holds an
exclusive `flock` on for as long as it lives. The next run reclaims every
`.pending/` sibling whose marker it can lock, because the kernel releases a
dead process's locks; directories without a marker (another tool's, or an
older compiler's) and markers a live run still holds are never touched. The
same applies to the report workspace a directory run keeps under its cache.

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

Allocation, process-local mutation and output are deterministic for keyed test
inputs, so they do not prevent successful-result reuse. A test that takes
`out: Stream` or `err: Stream` is reused like any other: the runner captures a
test process's standard output and standard error and discards both when the
test passes, and a receipt records only a pass, so a cached pass shows exactly
what an executed pass shows. A failure's captured output is part of its report,
and a failure is never reused. The clock, entropy, the environment, the
filesystem and the network do not prevent reuse either: a test process holds no
host-granted capability and registers no host provider, so every one it can use
is a [deterministic stand-in](#capability-parameters) whose seed and start
instant the receipt binds. Only a call into host-provided code prevents reuse.
The stricter
`--pure-skip` signature rule still excludes declared mutation and any capability
parameter, `Stream` included.

The source identity covers the resolved import closure and required configuration
and policy files. An edit to an unimported neighboring module neither discards
checked facts nor aborts an ordinary run with `SourceChanged`. Provider replacement
still verifies the full captured inventory because a fixture can introduce imports.
The environment fingerprint includes compiler/build controls rather than every
inherited variable, so shell/session metadata does not discard warm caches.
This includes native C search/link paths, Python adapter controls, Zig installation
overrides and reproducible-build settings as well as Mylang compiler controls.
Dynamic-loader overrides disable durable result reuse, and tests that call
host-provided code remain non-cacheable. Resolved native tool stamps remain part of identity.

A warm unchanged deterministic run still checks project validity through the shared
query cache, but admits valid result receipts without lowering, emitting or linking
any code, so it executes zero tests. That validity check replays the verdict the
previous run's check recorded, and the declaration contracts come from the cache
under the same resolved source identity, so an unchanged rerun starts exactly one
compiler process and costs about what an unchanged `mylang check` does. Receipt reuse is bound to the selected
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

The work of a run after an edit follows the edit rather than the project. The
checked facts describe only what the discovered tests and benchmarks reach; a
test whose closure does not contain the edited function is answered from its
receipt and is not linked into the library; the functions that are rebuilt reuse
every emitted unit whose inputs did not change; and the compiled test harness is
kept in the cache. When no case names a provider fixture, the body check starts
alongside the declaration check instead of after it, and it reads the check
summaries the way `build` does, so the effect passes revisit only changed bodies.
On a generated 200,000-line project where an edit reaches half of the 480 tests,
the run after the edit takes about 1.2 seconds, against 0.4 for `mylang check`
(`docs/audits/devspeed-test-loop-scale-2026-09-24.md`).

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
Only the tracing collector has anything to stress, so the flag selects
`--gc-runtime` when no runtime flag is given (the default is reference counting)
and is a usage error next to an `--rc-runtime` flag.
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

To fake a capability, prefer [capability parameters](#capability-parameters) and
the deterministic stand-ins: a function that takes a `Clock` is tested by
passing it a simulated one, with no fixture file. Provider fixtures remain for
replacing a dependency's source wholesale — a `host def` module, or a
collaborator whose behaviour the test must pin.

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
already have; source snapshots reject symbolic links and are bounded by the
project's `max_total_bytes` budget (64 MiB unless `mylang.json` sets it),
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

A test that needs a deterministic clock, entropy stream, filesystem, environment
or network should declare it as a [capability parameter](#capability-parameters)
or build a stand-in; this section covers dependencies that bypass capabilities.
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
$ mylang test app/main.my --bench '*' --release
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
$ mylang test app/main.my --bench '*' --release \
    --bench-output perf/candidate.json
$ mylang bench-promote --candidate perf/candidate.json --baseline perf/baseline.json \
    --approver maintainer --reason "accept 4% growth" --revision testrev
$ mylang test app/main.my --bench '*' --release \
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
