# Guest tests

`mylang test` is the compiler's own runner for tests written in the language. It
checks the project, finds the exported functions whose names begin with `test_`,
builds them with the compiler's core (Core IR, LLVM, `zig cc`) and runs each one
in its own forked trial. Cases are configured with one JSON file rather than with a
framework inside the language, and the runner needs no Python. A run builds a
program in optimized debug by default: Core passes and per-module LLVM `-O2`.
`--optimize-debug` is an alias; `--unoptimized` skips optimization. `--release` builds the optimized whole program, as
`mylang build --release` does, and all modes keep every overflow, cast and bounds
check that cannot be proved unnecessary. The design record is [the guest test workflow](../experiments/guest-tests.md).

## `mylang test`

```text
mylang test FILE.my|DIR [--release | --unoptimized | --optimize-debug] [--json] [--filter S] [--affected --against REF]
    [--no-cache] [--force] [--jobs N] [--cases PATH] [--max-steps N] [--max-frames N]
    [--max-memory SIZE] [--timeout-ms N] [--seed N] [--property-runs N]
    [--property-policy legacy|indexed-v1] [--link FILE.c]
    [--verify-facts | --no-facts] [--cache-dir DIR] [--shared-cache-dir DIR] [--zig PATH]
```

The command discovers `test_` functions in the project's reachable public
schema. A parameter-free test returning `bool` asserts `True`, and one returning
`Result[bool, E]` asserts `Ok(True)`, so it may use `?` and a failure it
propagates is reported with its
[error return trace](../results-and-options.md#error-return-traces). Any other
result type needs an expected value in a cases file; without one the test fails
with `test result type is not bool`, so an undeclared expectation is never a
silent pass. A test with data parameters and no cases-file `arguments` is a
[property test](#property-tests): the runner generates its inputs.

`--cases FILE` supplies arguments, expectations, skip reasons and
[provider fixtures](#isolated-source-provider-fixtures) keyed by qualified test
name; without it the runner reads the entry's own
[cases file](#per-entry-cases-files) when there is one. `--filter` selects
qualified names case-sensitively: a pattern with no `*`, `?` or `[` matches any
substring of the qualified name, and one with them is a shell-style glob.

The selected tests are built into one executable, and each test runs as its own
process of it, so a trap or a hang ends one test, not the run. A test process
gets no clock, entropy, filesystem, network or environment authority; a test
that declares one of those capabilities as a parameter receives a deterministic
stand-in instead ([capability parameters](#capability-parameters)). Each process
runs under the test budgets:

| Budget | Flag | Default | Trap |
| --- | --- | --- | --- |
| executed blocks of program functions | `--max-steps N` (`0` removes it) | 1,000,000, else `limits.test.max_steps` | `R_STEP_LIMIT` |
| call depth of program functions | `--max-frames N` | 1,024, else `limits.test.max_frames` | `R_FRAME_LIMIT` |
| bytes the heap may hold | `--max-memory SIZE` (`K`/`M`/`G`) | `MYLANG_MEMORY_LIMIT`, else `limits.test.max_memory`, else 512 MiB | `R_MEMORY_BUDGET` |
| wall clock per test | `--timeout-ms N` | 60,000 | the test fails, `timed out after N ms` |

`limits.test` lives in `mylang.json`
([runtime budgets](runtime-budgets.md)). A frame budget whose stack (32 KiB per
frame plus 8 MiB) the byte ceiling cannot back is refused before anything is
built.

`--json` prints a `native-tests-v1` report instead of the text listing: one
object per test with `name`, `status` (`passed`, `cached`, `failed`, `skipped`
or `unsupported`), `reason` and `at`, the counts, and the project `sources` the
check loaded.

Exit status:

| Status | When |
| --- | --- |
| 0 | every selected test passed or was replayed, with at least one not skipped |
| 1 | a test failed or trapped, or the project does not check |
| 2 | a usage error, an unreadable entry, a `mylang.json` that does not load, an invalid cases file or provider fixture, or a frame budget the byte ceiling cannot back |
| 3 | nothing was selected (a filter or `--affected` that matches nothing), every selected test was skipped by its cases file, or the project's import policy denies an import |

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

A test entry is a `.my` file, not necessarily a program. A file with no `func
main(` line of its own, such as a library module or a standalone `*_test.my`,
is checked with a stub `func main() -> int: return 0` appended, so its exported
`test_` functions run without editing the source. A file without a `module`
header is module `<stem>`: `solo_test.my` holds `solo_test::test_alone`. Such a
file may import only standard modules; one that imports a project module must
start with its dotted header, and `E_MODULE_HEADER` names the header to write.

A standalone `*_test.my` may sit in a subdirectory of the project. Its imports
and its module name resolve from the enclosing project root: the nearest
ancestor holding `mylang.json`, or the nearest ancestor holding a non-test `.my`
source. `tests/parser_test.my` is therefore module `tests.parser_test`, starts
with `module tests.parser_test`, and `import sexpr.parser` reads
`sexpr/parser.my` from the project root. A project that does not check prints
its diagnostics and exits 1.

### Failure text

A failed expectation reports both sides as `expected <value>, got <value>`. A
failed `assert` keeps its `R_ASSERT` code and source location and reports the
message written after the condition. A test's output, written through an `out:
Stream` or `err: Stream` parameter, is captured: the runner appends it to a
failure's text and discards it when the test passes. A trap prints its code,
its message, the innermost sixteen frames that led to it (then `N frames
omitted` when there were more) and, for a budget's trap, the runtime's hint.

```console
$ mylang test main.my
failed main::test_flag: expected true, got false
failed main::test_reading: R_ASSERT: x should be two
  in main::test_reading at main.my:12:12

reading 41 rows
failed main::test_total: expected "42", got "41"
0 passed, 0 cached, 3 failed, 0 skipped
```

Here `test_total` returns `int`, and `main.cases.json` beside the entry
expects `"42"` of it.

A test that reaches a construct the compiler's core does not build yet is
reported as `unsupported NAME: E_CORE_UNSUPPORTED (REASON) at LINE:COLUMN` and
left out of the executable; the summary line then ends with `, N unsupported`.
It is neither a pass nor a failure.

### Test processes

A file's tests are built into one program, and its tests share that program's
processes (NEW-CORE-TEST-BATCH-1): each worker takes the next run of pending
tests, about the pending count over the worker count, and one process answers
them in order. Every test still runs in its own forked trial, with fresh
capability stand-ins, its own captured output and its own step, frame, memory
and wall-clock budgets, so it gets the verdict it would get alone; launching one
process per test cost about 10 ms each. A test that ends its process without
answering keeps the verdicts of the tests before it. A timeout is that test's
verdict (`timed out after N ms`); any other ending, such as a crash in an
extern, runs the test again alone for a verdict of its own, and the tests after
it continue in a new process. A property test keeps its own processes, as
[batches and receipts](#batches-and-receipts) describes.
`MYLANG_TEST_ISOLATE=1` gives every test its own process again, as the check
batching is tested against.

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

No test is ever handed real authority: a `Host` parameter is never supplied,
and without cases-file arguments such a test fails as a property test whose
parameter cannot be generated (`a Host capability is never handed to a test`).
Every test gets its own stand-ins, so nothing one test writes is visible to
another, and each test's entropy stream is its own and stays the same from run
to run; renaming the test changes it, and `--seed N` pins every test's (a
directory run forwards it). The seed is part of a receipt's identity, so an
unchanged test that takes capabilities is reused like any other, and a
different seed executes it again.

```mylang
# doc: expect True True
import random
import time

# Whole seconds since `start`, as a caller of the clock sees them.
func uptime(clock: Clock, start: time.Instant) -> int:
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
func roll(entropy: Entropy) -> int:
    match random.from_entropy(entropy):
        case Ok(sampled):
            mut generator = sampled
            match random.randint(mut generator, 1, 6):
                case Ok(value):
                    return value
                case Err(_):
                    return 0
        case Err(_):
            return 0

public func test_uptime_counts_whole_seconds(clock: Clock) -> bool:
    mut start = time.from_unix_nanoseconds(946684800000000000)
    _ = time.advance(clock, time.nanoseconds(90500000000))
    return uptime(clock, start) == 90

public func test_roll_stays_on_the_die(entropy: Entropy) -> bool:
    mut value = roll(entropy)
    return value >= 1 and value <= 6

func main(out: Stream) -> int:
    mut clock = time.simulated_clock(time.from_unix_nanoseconds(946684800000000000))
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
helper, an example — gets them: the constructors need no capability, and using
a stand-in is not an effect of a function whose own parameters supply none
([deterministic stand-ins](../effects.md#deterministic-stand-ins)).

## Property tests

A `test_` function with data parameters and no `arguments` in the cases file is
a property test. The runner generates an input for every data parameter from its
type, hands its capability parameters their
[deterministic stand-ins](#capability-parameters) as it does for any test, and
calls the test once per input: it passes when every input — 100 unless
`--property-runs N` (1 to 1,000,000) says otherwise — returns `True` (or
`Ok(True)`) without trapping. `False`, `Ok(False)`, an `Err` and a trap (a
failed `assert`, a broken contract, an index out of bounds, an overflow) are
failures. A cases-file entry with `arguments` still wins: the test then runs
once with exactly those. An `expected` value without `arguments` is refused,
because a property's verdict is its `bool` result.

```mylang
# doc: check

@invariant(self.low <= self.high, "a span never runs backwards")
public record Span:
    low: int
    high: int

func total(xs: int[]) -> int:
    mut sum = 0
    for x in xs:
        sum = sum + x
    return sum

public func test_reversing_twice_is_the_identity(xs: int[]) -> bool:
    mut ys = xs.copy()
    ys.reverse()
    ys.reverse()
    return ys == xs

@requires(len(xs) > 0, "an average needs a value")
public func test_average_is_within_range(xs: i32[]) -> bool:
    mut mean = total([for x in xs yield int(x)]) // len(xs)
    return int(min(xs)) <= mean and mean <= int(max(xs))

public func test_a_span_is_ordered(span: Span) -> bool:
    return span.low <= span.high

public func test_budget_stays_below_100(costs: int[]) -> bool:
    return total(costs) < 100

func main() -> int:
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
so run 37 of a property under the same generation policy and budget is the same
value on every machine, and renaming the test draws new ones. Under the default
`legacy` policy, sizes grow from 0 on the first run to 100 on the last: a
collection holds up to the size at the top level and half of it for every level
it is nested, and an input stops growing collections once it holds 4096 nodes.

| Type | What is generated |
| --- | --- |
| integers (`int`, `i8`…`u64`) | three draws in eight from the edges of the width — 0, 1, -1, the minimum and maximum, a power of two, one below it and its negation — one uniformly over the width, the rest near zero, growing with the size |
| `bool` | `True` or `False` |
| `float` | small binary fractions, bit patterns from the whole range, and on purpose both zeros, both infinities, NaN, the largest finite and the smallest subnormal magnitudes; the language observes each consistently (a NaN is `nan` and unequal to itself) |
| `str` | seven scalars in ten printable ASCII, plus tab, newline, NUL and other controls, well-known non-ASCII scalars (`é`, `Ω`, `中`, `😀`, a combining accent, U+FEFF, U+10FFFF) and scalars from the whole range |
| `bytes`, `byte_buffer` | octets, a quarter of them 0, 1, 0x7F, 0x80 or 0xFF; a `byte_buffer` is a fresh buffer per input, shrunk like `bytes` and shown as `byte_buffer(b"...")` |
| `list[T]`, `set[T]`, `dict[K, V]` | elements or entries of the element types; a set element or a dictionary key drawn twice is dropped, so keys of every hashable type work |
| records | fieldwise |
| fixed arrays, enum-indexed tables | every element or entry |
| enums, unions, `Option[T]`, `Result[T, E]` | a case drawn uniformly, then its payload |

A `domain` (built only through its own constructors), a function value and
`Host` are never generated: a property test with a parameter whose type reaches
one fails, naming the parameter and the type, and so does one whose result is
not `bool` or `Result[bool, E]`. With a
`test_callbacks(callbacks: list[func(int) -> int effects()]) -> bool`:

```console
$ mylang test app/main.my --filter test_callbacks
failed main::test_callbacks: property test parameter `callbacks: List<func(i64) -> i64 effects()>` cannot be generated: a function value cannot be generated
0 passed, 0 cached, 1 failed, 0 skipped
```

### Preconditions and invariants

An input that breaks the test's own `@requires` is discarded, not failed:
`test_average_is_within_range` above never sees an empty list. A value the
runner generates was not built by a constructor, so every `test_` function also
checks, on entry, the [`@invariant`](../contracts.md#invariants) of every record
or domain its parameters hold — in fields, list, set and dictionary elements,
arrays and every union case — and an input that breaks one is discarded the
same way: `test_a_span_is_ordered` only ever sees ordered spans. A
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
  reproduce: mylang test app/main.my --filter 'main::test_picky' --seed 7017186523047142524
0 passed, 0 cached, 1 failed, 0 skipped
```

### Shrinking and the report

The first failing input is shrunk before it is reported. Each parameter in turn
is replaced by the first of its simpler candidates that still fails (for any
reason), until no candidate of any parameter does or 2,000 candidates have run:
integers move toward 0 by halving the distance (100 tries 0, 50, 75, 88, 94, 97,
99), floats toward `0.0`, strings, bytes and collections first lose elements —
all of them, then halves, quarters and single ones — then shrink the ones left
(never into a set element or dictionary key another one holds), records shrink
field by field, and enums, unions and `Option` move toward earlier cases and
`None`. The report prints the minimal input as mylang literals, one line per
parameter, the input as generated and its run, the reason — the value returned
(an `Err` with its [error return trace](../results-and-options.md#error-return-traces)),
or a trap's code, message and frames — the original input's own reason when
shrinking reached a different failure, and a command that reproduces the whole
search. An input that ran past `--timeout-ms` is reported as generated, because
every candidate could run as long.

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

A property does not pay one process launch per input. The test process makes
one copied-value call per input and writes each answer as it finishes, so a
passing 100-run property is one process. Replacements for discarded inputs and
shrink candidates run in further batches. A child that dies or runs out of time
mid-batch keeps the answers of the inputs before the one it was running.

A passing property is reused like any other test. Its receipt's identity
includes the seed and the run count, so changing `--seed` or `--property-runs`
runs it again; a failure is never reused.

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


### Resumable indexed campaigns

Use `--property-policy indexed-v1` when you want to extend a property's budget or
resume after an interrupted command:

```console
$ mylang test app/main.my --filter test_reversing --seed 7 --property-policy indexed-v1 --property-runs 1000
$ mylang test app/main.my --filter test_reversing --seed 7 --property-policy indexed-v1 --property-runs 2000
```

This policy repeats the default 100-run size schedule independently of the
requested budget. Increasing the budget preserves every earlier generated
input. The default `legacy` policy keeps its existing budget-dependent schedule
and whole-test receipts.

An eligible indexed campaign retains a completed prefix after bounded batches.
Both passing and discarded inputs advance that prefix. An unchanged request can
reuse the completed prefix without starting a property-test process; an increased
budget continues from the next unclassified ordinal. Reuse still requires the
same target dependencies, generation and shrinking contract, seed, compiler,
providers, environment and execution limits. A smaller budget may run fresh.

If the command is interrupted, the next matching request can resume the last
committed prefix. The current unfinished batch may run again. A failing batch
never extends passing evidence, and a saved prefix alone cannot certify a larger
unfinished request as passed. Failure reports retain shrinking and include the
indexed policy in their reproduction command.

In JSON, `property.campaign` reports the policy, search inputs `generated`, trials
`submitted`, returned outcomes `observed`, `fresh_classified`, `reused` ordinals,
and `next_ordinal`. Submitted and observed work includes retries and shrinking;
fresh classification counts search outcomes in order, including the first
returned failure. It does not imply every submitted trial returned an outcome.
`next_ordinal` marks the last safe prefix; another run can reuse it only if its
stored checkpoint validates. The existing `property.counts.attempts` continues
to count shrinking attempts.

This progress is disposable cache data: removing the cache or losing a damaged
record runs work again. It is not a power-loss durability guarantee. `--force`,
`--verify-facts`, leak checking, native links and untracked effects keep their
fresh-execution rules. Indexed campaigns initially bypass whole-test and report
receipts so their case-level reuse remains observable.

## Directory runs

The positional argument may be a directory instead of one entry. Every `.my`
file beneath it is inventoried in sorted path order, skipping the cache
directory and generated `.mylang-cache*`, `.zig-cache`, `zig-out`,
`node_modules` and `.git` trees. A file that declares a top-level `main`, and
every `*_test.my` file, is a root. A library that declares a test and that no
root's import closure reaches is a root as well, checked through the stub
`main` above, so a test file needs neither `main` nor the `*_test.my` suffix; of
two such libraries where one imports the other, only the importer is a root. A
library imported by a root is not run on its own: its tests run once, as part of
that root.

Each root runs as `mylang test ROOT --json` would, with the run's filter,
budgets, seed, property runs, `--release`/`--unoptimized`/`--optimize-debug`, `--verify-facts`/`--no-facts`,
`--force`, `--affected --against REF` and `--link` inputs. Most roots run in the
directory run's own process (NEW-CORE-TEST-UNION-1). A root that opens with its
`module` header and declares no `main`, in a project whose configuration names no
import policy and no interface files, with no providers in its cases file, first
replays its recorded results; the roots of a project that miss are then checked
once, together, and each selects, builds and runs its tests from its share of that
check: the modules its own imports reach, which are what its own check would have
loaded. After an edit, a directory's roots used to check much the same import
graph once each. Every other root, and every root of a project whose shared check
fails, runs in a child process, whose own check reports its own diagnostics;
`MYLANG_TEST_CHILDREN=1` gives every root a child.

Roots share one worker budget (NEW-CORE-S4-TEST-1): `--jobs N`, else
`MYLANG_JOBS`, else the CPU count capped by how many per-test memory ceilings
`MemAvailable` holds (NEW-CORE-S5-FANOUT-1). At most that many roots run at once,
largest root file first, and a worker starts the next root as soon as its last one
ends (NEW-CORE-TEST-QUEUE-1). The budget also bounds the run's test processes: a
root in the run's process holds one permit per test process, so the root still
working uses the cores the finished ones gave back, and a child holds its share,
the budget divided by the roots that can still run beside it. Roots share the
run's cache directory, so an unchanged program replays its results instead of
rebuilding, and a result recorded in either kind of process replays in the other.

The roots' reports merge into one listing in root order and one summary
line. A root that produces no usable report (a project that does not check, a
setup failure) adds a failed line naming its path, with its diagnostics on
stderr. Every test-declaring source beneath the directory must appear in some
root's loaded `sources`; one that no root loaded fails the run as
`test-declaring source was not loaded by any test program`, so a test file can
fail a run but never silently drop out of one. A source, configuration or
toolchain change during the run fails it with `SourceChanged`. The exit status
is 2 if any root failed to set up (status 2), else that of the merged listing:
1 if any line failed, 3 if nothing was selected or every selected test was
skipped, 0 otherwise. `--cases` is refused for a directory run (status 2), because its
keys name the tests of one project; each entry's own
[cases file](#per-entry-cases-files) applies to that entry instead.

```console
$ mylang test . --cache-dir /tmp/suite-cache
passed scaled_test::test_scaled
passed scanner_test::test_is_digit
2 passed, 0 cached, 0 failed, 0 skipped
$ mylang test . --cache-dir /tmp/suite-cache --filter test_scaled
cached scaled_test::test_scaled
0 passed, 1 cached, 0 failed, 0 skipped
$ mylang test . --cases scaled_test.cases.json
error: --cases requires a single test entry
```

## Reusing unaffected results

A passing test leaves a receipt under `<cache>/tests/receipts-v2`, where
`<cache>` is `--cache-dir DIR` or `.mylang-cache/core` relative to the current
directory. A later run that computes the same identity reports `cached` instead
of building and executing the test. Failures, traps and timeouts never become
receipts, so they always run again.

`--shared-cache-dir DIR` opts into a second receipt store for ordinary project
tests across compatible worktrees. `MYLANG_TEST_SHARED_CACHE` supplies the same
setting when the flag is absent; an empty environment value disables it. The
explicit flag wins, accepts `--shared-cache-dir=DIR`, and rejects an empty path.
Directory runs forward the setting to their workers. With neither setting,
receipts stay private. This option does not change build or run caches.

Use a dedicated shared root, preferably outside the worktrees. Native test
receipts live under `DIR/native-tests-v2`; `--cache-dir` still holds the private
frontend, graph, executable and whole-report caches. Shared reuse requires a
compatible compiler, toolchain, execution settings and the test's complete
validated dependency closure. A different checkout location alone need not
rerun an otherwise identical eligible test. Unknown or unsupported identities
run normally, and missing or corrupt receipts are misses. The cache location
does not change a test's execution identity. An explicitly selected unusable
store reports an error. `--force` bypasses shared hits; `--no-cache` disables
shared lookup and publication even when the environment selects a store.

From the repository root, these two runs use separate private caches and the
same shared receipts:

```bash
test_cache=$(mktemp -d)
trap 'rm -rf "$test_cache"' EXIT
mylang test examples/testing/main.my --cache-dir "$test_cache/private-a" --shared-cache-dir "$test_cache/shared"
mylang test examples/testing/main.my --cache-dir "$test_cache/private-b" --shared-cache-dir "$test_cache/shared"
```

Shared receipts currently cover zero-argument `bool` tests under the legacy
property policy, with effects limited to managed allocation and mutation.
External providers, native links, provider overlays, `function_digest` and
error traces remain private. Project sources, configuration, cases and embedded
assets must stay inside the project root. Configuration and cases bytes, embedded
values and literal strings remain part of the identity. Fact verification, leak
checks and loader overrides also run without shared receipts. The `native-tests-v2`
namespace has its own format, separate from developer verification and fuzz
evidence stores. Native [retention policies](cache-retention.md#native-cache-retention)
bound its disk use with LRU eviction and protect storage operations with leases.
The JSON test report remains `native-tests-v1`.

A receipt's identity (NEW-CORE-S4-TEST-3) is:

- **the test's program** (NEW-CORE-S4-TEST-6): the Core IR of the functions the
  test reaches, before any pass, hashed field by field with every source span
  replaced by its file, line and column, and the entry path. Passes and LLVM
  emission are pure functions of that IR and the settings below, so looking up
  a receipt emits no code. An edit to a function the test does not reach, or
  one that only moves code in another file, keeps the key; whitespace edits that
  move a reached function's lines do not;
- **the settings**: `--release`/`--unoptimized`/`--optimize-debug`, `--no-facts`/`--verify-facts`, the seed, the
  property runs, the step, frame, memory and time budgets, the test's own
  cases-file entry and the cases file's bytes;
- **the compiler, runtime and toolchain identity**, including the `zig` the run
  uses, and the bytes of `mylang.json` and its import policy. The build also
  publishes a narrower `runner_identity` over the test runner, driver and
  pipeline sources (RUNNER-IDENTITY-1), which the planned execution receipts
  will bind; it is not yet part of any receipt key;
- **the environment variables that can change an outcome**
  (NEW-CORE-S4-TEST-5): the keyed class of the
  [environment identity contract](environment-identity.md) in
  `src/environment_identity.zon` (ENV-IDENTITY-1). That is every `MYL_`,
  `MYLANG_` and `SELKA_` variable except the placement ones (store locations such
  as `MYLANG_CORE_RUNTIME_CACHE` and `MYLANG_TEST_SHARED_CACHE`, job counts such as
  `MYLANG_JOBS`, `MYLANG_TEST_ISOLATE`, `MYLANG_TEST_CHILDREN` and the telemetry
  directories), the C compiler and Zig toolchain inputs (`CPATH`,
  `C_INCLUDE_PATH`, `LIBRARY_PATH`, `ZIG`, `ZIG_LIB_DIR`, `SOURCE_DATE_EPOCH` and
  the like) and `LD_*`. The contract's host class (`PYTHON*`, the locale and
  `TZ`) is keyed only by host tooling, never by a receipt. A shell's `_` or
  `OLDPWD`, a terminal's variables or a wrapper such as `time` leave receipts
  valid.

A program discovers the functions needed by all its ready tests together and
derives each test's key from their canonical facts (NEW-CORE-TEST-KEYS-1,
NEW-CORE-TEST-FACTS-1): every function gets a digest of what it means
(its callees by name and signature, its strings by their bytes, its types by
structure), and a test's key hashes the digests of the functions it reaches. The
key changes exactly when the test's own program above does, so an edit to a
function only some tests reach reruns only those. Validated facts live under
`<cache>/test-keys` in the existing packed store. An eligible edit lowers and
digests changed functions while reusing unchanged facts without restoring their
instruction bodies. Unknown metadata takes the complete-lowering path; source
movement, type changes and source-proof changes can require broader recomputation.
The program also keeps one key for
all its ready tests together (NEW-CORE-TEST-WHOLE-1): when it has a receipt, every
test is reused with a single lookup. `MYLANG_TEST_KEYS=per-test` keys each test
from its own lowering instead, as the check the derived keys are tested against.

The Selka cache planner retains a complete dependency graph and uses reverse
dependencies to reuse unaffected test keys (NEW-CORE-TEST-GRAPH-1,
SELFHOST-CACHE-PLAN-2). Lost or corrupt metadata causes recomputation. These
records describe key derivation; passing receipts still authorize test reuse.
Global semantic checks continue to run after source changes.

`--json` includes current key-derivation work at `cache.work` on the first test
of each provider group. Its `scope` identifies that group. The report counts
fresh/reused canonical facts, raw bodies restored, graph and closure work, and
planner request/reply bytes and process starts. `nanoseconds` contains monotonic
wall intervals; `storage` counts packed block reads and decoding, excluding
direct journal reads and ordinary cache metadata. A whole-report replay omits
historic work. `MYLANG_CACHE_PLAN_MODE=shadow` independently lowers and hashes
the complete graph to check derived keys; `reference` uses the uncached Zig
path. These modes change the execution identity and are qualification tools.

Output and capabilities do not prevent reuse. A test that prints through a
`Stream` parameter is reused like any other, because its output is discarded on
a pass; a test that takes a `Clock`, `Entropy`, `Filesystem`, `Environment` or
`Network` gets a [deterministic stand-in](#capability-parameters) whose seed the
receipt binds.

A run whose every selected test passed or replayed also records the whole
report in `<cache>/tests/manifests-v2`, with the digest of every source,
embedded file, cases file and configuration file it loaded. An unchanged rerun
replays that report without checking the project; any changed byte falls back
to the ordinary run, which still replays each test's own receipt. A project
with `"interface_files": true` in `mylang.json` never replays a whole report,
so its interface files are checked on every run.

What runs every test again:

- `--force` and `--verify-facts` execute every selected test; a pass still
  records its receipt;
- a run with `--link FILE.c` never reads receipts, because the runner does not
  yet capture the headers a C input includes;
- a run with `MYL_CORE_LEAKCHECK` set to anything but `0`, or with a non-empty
  `LD_*` variable, never reads receipts;
- `--no-cache` builds and runs through an empty private cache under the cache
  directory, removed when the command ends (NEW-CORE-S5-NO-CACHE-1): nothing is
  read from or published to the receipt, manifest, program or front-end
  caches. The per-user object store of compiled units is still used.

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
$ mylang test app/main.my --cache-dir /tmp/test-cache --force
passed main::test_square
passed main::test_sum
2 passed, 0 cached, 0 failed, 0 skipped
```

## Affected selection

`mylang test --affected --against REF` narrows a run to the tests that reach a
declaration whose own source lines changed since the git revision `REF`
(NEW-CORE-S5-AFFECTED-1). It reads the changed lines of every `.my` file from
one `git diff` under the project root (plus `git ls-files --others` for files
not yet added, which count as changed throughout) and maps each changed line
onto the top-level declaration that owns it, by indentation: a line inside a
function or constant changes that declaration, and a line anywhere else — the
module header, an import, a record, a domain — changes every declaration of the
module. A test then runs only when a function its Core IR build reaches (the
reachable set its receipt is keyed on) is a changed function, a specialization
of one, or a function of a wholly changed module. A changed constant is folded
into every reader, and a deleted function leaves nothing to reach, so a changed
name of a loaded module that no checked function carries keeps every test, as
does a test the core cannot build. A change in a module the program does not
load selects nothing. The selection costs a `git diff`, a line scan and one IR
build per test, never a second check of the project.

The derivation is a selection, never a verdict. `--filter` applies first. The
`affected: N selected, M skipped against REF` line and one `skipped NAME: no
changed declaration is reachable` line per dropped test go to stderr, so
`--json`'s report on stdout stays machine-readable, and an empty selection exits
3 exactly as a filter that matches nothing does. `--against` without
`--affected`, or the reverse, is a usage error, and a `REF` git cannot resolve
exits 2 with `--against names a revision git cannot resolve`. Such a run neither
replays nor records a whole-run report, while each selected test still replays
its own receipt; a directory run passes both switches to every child. CI and
`lint --gate` run the whole set.

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
passing it a simulated one, with no fixture file. Provider fixtures replace a
dependency's source wholesale, for a collaborator whose behaviour the test must
pin (NEW-CORE-S4-TEST-4).

A case may carry a `providers` object mapping existing dependency `.my` paths,
relative to the project root, to replacement source text. The runner first
checks the project as written, then checks it again with the replacements
applied in memory; the files on disk are never modified. A provider may replace
an existing dependency only, never the entry module or a path the project does
not load (`error: invalid test provider dependencies`). The replaced module's
own exported types and functions must keep their checked structure, and so must
the selected test's signature and every type it reaches; other modules' exports
are not compared, so a provider may import fewer modules. A provider that
changes them fails the run with `ProviderSignatureChanged`, or with the check
error a caller now sees. Cases that name the same providers share one check and
one build; each test still runs in its own trial. A case's providers are part
of its receipt's identity, so changing an injected source runs the case again.

```console
$ mylang test app/main.my
failed main::test_reading: expected true, got false
0 passed, 0 cached, 1 failed, 0 skipped
$ cat cases.json
{
  "main::test_reading": {
    "providers": {"reading.my": "module reading\n\npublic func sample() -> int:\n    return 42\n"}
  }
}
$ mylang test app/main.my --cases cases.json
passed main::test_reading
1 passed, 0 cached, 0 failed, 0 skipped
$ mylang test app/main.my --cases cases.json
cached main::test_reading
0 passed, 1 cached, 0 failed, 0 skipped
```

## Deterministic provider fixtures

A test runs with no ambient authority. The runner grants a test process no
clock, entropy, filesystem, network or environment of the machine: a capability
parameter gets a [deterministic stand-in](#capability-parameters), and a `Host`
parameter, which `extern func` C calls need, is never supplied. A test's outcome is therefore a function of its sources, its
cases-file entry and the keyed settings, which is what lets a receipt stand in
for it.

Code that needs the real machine takes a capability parameter, and the test
passes it the stand-in. When a test reaches a collaborator whose production
answer it must not depend on, a [provider fixture](#isolated-source-provider-fixtures)
replaces that module's source with one returning a fixed value; the replacement
is part of the receipt's identity, so the case stays reusable. Provider fixtures
are source replacements: they change what the guest computes, and they do not
validate a real implementation of the same declaration.

```console
$ mylang test app/main.my --filter test_stamp
failed main::test_stamp: property test parameter `host: host_cap` cannot be generated: a Host capability is never handed to a test
0 passed, 0 cached, 1 failed, 0 skipped
$ mylang test app/uptime.my
passed uptime::test_uptime_counts_whole_seconds
1 passed, 0 cached, 0 failed, 0 skipped
```

## Test files and their modules

### Private declarations

A module's test file may call the module's private declarations: a module named
`<name>_test` that no other module imports sees every non-`public` function,
type and constant of module `<name>`, so a helper need not become `public` just
to be tested. Any other importer, including another module's test file, still
gets `E_PRIVATE_SYMBOL`.

In `scanner.my`:

```mylang
# doc: project scanner-private
# doc: file scanner.my
# doc: check
func is_digit(c: str) -> bool:
    return c in "0123456789"
```

In `scanner_test.my`:

```mylang
# doc: project scanner-private
# doc: file scanner_test.my
# doc: entry scanner_test.my
import scanner


public func test_is_digit() -> bool:
    return scanner.is_digit("7") and not scanner.is_digit("x")
```

```console
$ mylang test .
passed scanner_test::test_is_digit
1 passed, 0 cached, 0 failed, 0 skipped
```

### Per-entry cases files

An entry's cases file sits beside it as `<stem>.cases.json`: `scaled_test.my`
owns `scaled_test.cases.json`. A run of the entry without `--cases` applies that
file, so a directory run applies each entry's file to that entry alone and a
single-file run of the same entry sees the same cases. An explicit `--cases FILE`
still takes precedence for a single entry. A cases file is a JSON object keyed
by qualified test name; each entry may carry `arguments` (typed JSON values by
parameter name), `expected`, `skip` (a reason string) and `providers`. An
unknown test name or field stops the run with `error: test cases: ...` and
status 2; a `skip`ped test is reported as `skipped NAME: REASON` and does not
fail the run, though a run whose every selected test was skipped exits 3.

```console
$ cat scaled_test.cases.json
{"scaled_test::test_scaled": {"arguments": {"n": "21"}, "expected": "42"}}
$ mylang test .
passed scaled_test::test_scaled
cached scanner_test::test_is_digit
1 passed, 1 cached, 0 failed, 0 skipped
```

## Dropped flags

The runner on the compiler's core dropped the old runner's features below
(S5-D6). Each flag is refused with status 2 and a one-line reason.

| Flag | Replacement |
| --- | --- |
| `--diagnostics` | `mylang check FILE.my --diagnostics=json` reports the same diagnostics |
| `--report`, `--timings`, `--timings=json`, `--explain-invalidation` | `--json` reports each test, with `cached` for a replayed receipt; `mylang run FILE.my --timings` times one program |
| `--friction-log` | `mylang check FILE.my --friction-log=PATH` |
| `--pure-skip` | none: a failure is never replayed |
| `--max-calls` | `--max-steps` and `--max-frames` |
| `--bench`, `--bench-only`, `--bench-output`, `--bench-baseline`, `--bench-policy`, `--bench-profile`, `--bench-warmup`, `--bench-batches`, `--bench-batch-ms`, `--bench-timeout-ms`, and `mylang bench-promote` | none: `bench_` functions, baselines and policies were dropped; time a built program instead |
| `--gc-stress`, `--gc-runtime`, `--rc-runtime`, `--legacy-sharing`, `--value-semantics` | none: one-count reference counting and value semantics are the only modes |
| `--library`, `--provider`, `--link-library`, `--library-path` | `extern func` with `--link FILE.c` |

`--whole-program` is accepted and ignored, and `--qbe PATH` is ignored.
