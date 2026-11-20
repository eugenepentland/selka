# Guest tests

`selka test` runs the tests you write in Selka: each exported `test_` function and each runnable
[docstring example](#docstring-examples), every one in its own forked process. Settings live in `selka.json` and a JSON
cases file.

## `selka test`

```text
selka test FILE.selka|DIR [--release | --unoptimized | --optimize-debug | --debug-lean | --debug-o0] [--json] [--filter S] [--affected --against REF]
    [--no-cache] [--force] [--jobs N] [--cases PATH] [--max-steps N] [--max-frames N]
    [--max-memory SIZE] [--timeout-ms N] [--seed N] [--property-runs N]
    [--property-policy legacy|indexed-v1] [--link FILE.c]
    [--verify-facts | --no-facts] [--cache-dir DIR] [--shared-cache-dir DIR] [--zig PATH]
```

The default build is Core passes with LLVM `-O0` per module (also `--debug-o0`). `--debug-lean` asks for the
[lean debug build](native-build.md#debug-code-generation), `--optimize-debug` for LLVM `-O2`, `--unoptimized` for no Core
pass, `--release` for the optimized whole program. Every mode keeps each overflow, cast and bounds check that cannot be
proved unnecessary.

- A parameter-free test returning `bool` passes on `True`. Returning `Result[bool, E]`, it passes on `Ok(True)`, may use
  `try`, and shows a propagated failure's [error return trace](../results-and-options.md#error-return-traces).
- Any other result type needs an `expected` value in a cases file, else `test result type is not bool`.
- Data parameters with no cases-file `arguments` make a [property test](#property-tests).

`--cases FILE` supplies arguments, expectations, skip reasons and [provider fixtures](#isolated-source-provider-fixtures)
by qualified test name; without it the entry's own [cases file](#per-entry-cases-files) applies. `--filter S` is a
case-sensitive substring of the qualified name, or a shell glob when it holds `*`, `?` or `[`.

Each test runs as its own process with no clock, entropy, filesystem, network or environment authority (a capability
parameter gets a [deterministic stand-in](#capability-parameters)), so a trap or a hang ends one test. Budgets:

| Budget | Flag | Default | Trap |
| --- | --- | --- | --- |
| executed blocks of program functions | `--max-steps N` (`0` removes it) | 1,000,000, else `limits.test.max_steps` | `R_STEP_LIMIT` |
| call depth of program functions | `--max-frames N` | 1,024, else `limits.test.max_frames` | `R_FRAME_LIMIT` |
| bytes the heap may hold | `--max-memory SIZE` (`K`/`M`/`G`) | `SELKA_MEMORY_LIMIT`, else `limits.test.max_memory`, else 512 MiB | `R_MEMORY_BUDGET` |
| wall clock per test | `--timeout-ms N` | 60,000 | the test fails, `timed out after N ms` |

`limits.test` lives in `selka.json` ([runtime budgets](runtime-budgets.md)).

**Long inputs meet the step budget.** It counts executed blocks, not time (a loop over a text's bytes runs about six per
byte), and a built binary counts none, so linear code can fail with `R_STEP_LIMIT`. Cut the input, or raise the budget for
one test (`--filter` picks it, `--max-steps` applies to it) or the project (`limits.test.max_steps`).

```console
$ selka test text_test.selka --filter test_long_input --max-steps 20000000
```

`--json` prints a `native-tests-v1` report: per test `name`, `status` (`passed`, `cached`, `failed`, `skipped`,
`unsupported`), `reason`, `advice`, `at`, `steps`, `peak_bytes`; then the counts, `exec_receipts`, the run's `result`
(`passed`, `failed`, `nothing ran`) and the `sources` loaded.

| Exit | When |
| --- | --- |
| 0 | every selected test passed or was replayed, and at least one was not skipped |
| 1 | a test failed, trapped or is `unsupported`, or the project does not check |
| 2 | a usage error, an unreadable entry, a bad `selka.json`, cases file or provider fixture, or a frame budget the byte ceiling cannot back |
| 3 | nothing selected (a filter or `--affected` matching nothing), every selected test skipped, or the import policy denies an import |

```console
$ selka test examples/testing/main.selka
passed main::test_square
passed main::test_sum
2 passed, 0 cached, 0 failed, 0 skipped
$ selka test examples/testing/main.selka --filter 'main::test_nothing'
0 passed, 0 cached, 0 failed, 0 skipped
$ echo $?
3
```

### Recursion and the frame budget

A test may hold 1,024 call frames. Deeper recursion (a parser fed 10,000 levels, a long list or tree walk) fails with
`R_FRAME_LIMIT`, although the same code runs under `selka run` and in a built binary ([what bounds a built
binary](runtime-budgets.md#what-bounds-a-built-binary)). The failure prints the innermost sixteen frames and the advice:

```console
$ selka test deep_test.selka --filter test_deep
failed deep_test::test_deep: R_FRAME_LIMIT
  in deep_test::depth at deep_test.selka:4:16
  in deep_test::depth at deep_test.selka:4:16
  ... (16 lines in all)
  1008 frames omitted

this test went deeper than its budget of 1,024 nested calls (every test has one); raise it with `selka test --max-frames=N` or `limits.test.max_frames` in `selka.json` (each frame reserves 32 KiB of stack, so --max-memory must cover N x 32 KiB)
```

- Raise the budget (`--filter test_deep --max-frames 6000`) or set `limits.test.max_frames`. A test may map `--max-memory`
  plus 256 MiB (768 MiB by default), so the default backs up to 23,296 frames at 32 KiB each; more needs `--max-memory`
  too, or the run is refused (status 2) before anything is built.
- Or check the deep case in an acceptance run of the built binary (`selka build -o`), which has no frame budget.

### Test entries

- Any `.selka` file named on the command line is an entry; `*_test.selka` matters only to directory discovery. A file
  without `func main(` gets a stub `main`, so a library or a `*_test.selka` runs unedited.
- Without a `module` header the module is `<stem>` (`solo_test.selka` holds `solo_test::test_alone`); a redundant header is
  `E_MODULE_HEADER`. A `--local-stdlib` replacement counts as a standard module.
- A `*_test.selka` in a subdirectory resolves imports and its module name from the project root: the nearest ancestor
  holding `selka.json`, else one holding a non-test `.selka` source (`tests/parser_test.selka` is `tests.parser_test`).
- A project that does not check prints its diagnostics and exits 1.

### Failure text

- A failed expectation reports `expected <value>, got <value>`; a failed `assert` keeps `R_ASSERT`, its location and your
  message.
- Output to an `out: Stream` or `err: Stream` parameter is captured: shown with a failure, discarded on a pass.
- A trap prints its code, message and the innermost sixteen frames (then `N frames omitted`), plus a budget's hint.
- A false `return LEFT op RIGHT` (`==`, `!=`, `<`, `<=`, `>`, `>=` over integers, floats or texts) reports both values and
  the comparison's line. Any other `false` (an `and`, a record compared, a variable) gets an `advice:` line, also a field
  in `--json`: write one `assert` for each fact.
- A test the core cannot build is `unsupported NAME: E_CORE_UNSUPPORTED (REASON) at LINE:COLUMN`. It did not run, so the
  run fails (exit 1, `"result":"failed"`).

```console
$ selka test main.selka
failed main::test_ints: expected true, got false
  returned comparison: left 6, right 5
  in main::test_ints at main.selka:4:12
failed main::test_flag: expected true, got false
  advice: this test returned false from one expression, so the report cannot say which fact failed: write one `assert` for each fact, and a failing `assert left == right` prints both values
failed main::test_reading: R_ASSERT: x should be two
  in main::test_reading at main.selka:12:12

reading 41 rows
failed main::test_total: expected "42", got "41"
0 passed, 0 cached, 3 failed, 0 skipped
```

`test_total` returns `int`, and `main.cases.json` expects `"42"` of it.

### Test processes

Tests of one file share worker processes, but each runs in its own forked trial with fresh stand-ins and its own budgets,
so its verdict is the one it would get alone. A timeout is that test's verdict; any other death reruns it alone.
`SELKA_TEST_ISOLATE=1` gives every test its own process.

## Work per test

Every trial counts `steps` (executed blocks, what the step ceiling charges) and `peak_bytes` (the byte ceiling's peak: 64
KiB chunks plus live large blocks). Both appear in `--json` and in the receipt, so a cached result carries them:

```bash
selka test app/main.selka --json
# {"version":"native-tests-v1","tests":[{"name":"main::test_flow","status":"passed",
#  "reason":"","at":"","steps":41200,"peak_bytes":65536}], ...}
```

A plain run prints a `work:` line for each test whose `steps` changed 2x or more, either way, since its last run in the
same build mode. There is no allocation count; `testing.allocations` measures one workload.

```console
$ selka test http --cache-dir .selka-cache/core
passed http::test_headers
work: http::test_framing steps 41,200 → 168,900 (4.1×)
2 passed, 0 cached, 0 failed, 0 skipped
```

## How work grows

`testing` ([standard library](../standard-library.md#testing)) states a workload's growth class instead of timing it;
`work` is a `func(int) -> int`.

| Function | Answers |
| --- | --- |
| `testing.steps(work, n)` | the blocks `work(n)` executed |
| `testing.allocations(work, n)` | the managed blocks allocated |
| `testing.allocations_writing(work, out, n)` | the same for a workload that prints to a `Stream` |
| `testing.growth(work, small, large)` | the larger growth ratio, without judging it |
| `testing.linear(work, small, large)` | fails when a count grows by more than 1.5 × (large ÷ small): from 1,000 to 4,000, `n log n` (about 4.8×) passes against 6×, quadratic (16×) fails |
| `testing.constant(work, small, large)` | fails above 1.5× plus two counts of slack |

Zero at both sizes passes. A failure names the counter, both values and the ratio:

```console
# A deliberately quadratic shape at a 4x step reports:
failed perf::test_scan_is_linear: R_ASSERT: testing.linear: steps grew 15.8× from 30506 at n=100 to 482006 at n=400; the limit is 6.0×
  in testing::within at @stdlib/testing.selka:52:12
  in testing::linear at @stdlib/testing.selka:104:9
  in perf::test_scan_is_linear at perf.selka:15:12
0 passed, 0 cached, 1 failed, 0 skipped
```

- Both sizes run inside the step budget: raise `limits.test.max_steps` or `--max-steps`.
- Counts differ between optimized debug and release: compare growth, or assert zero only where both modes agree.
- Ordinary source that spells `__test_blocks` or `__test_allocations` is `E_INTERNAL_NAME`. A program without block
  accounting (a `selka build` binary, `selka run` without `--max-steps`) traps `R_NO_STEP_ACCOUNTING` when a check reads
  the counters.

## Docstring examples

A function docstring can carry a transcript:

```selka
# doc: expect 42
public func answer() -> int:
    """The answer as an executable example.

    >>> answer()
    42
    >>> '42'
    '42'
    >>> print(out, 'before\n\nafter')
    before
    <BLANKLINE>
    after
    """
    return 42


func main(out: Stream) -> int:
    print(out, answer())
    return 0
```

- `>>> ` begins an example and `... ` continues it. Expected output ends at a blank line, another prompt or the docstring's
  end and is compared exactly (`<BLANKLINE>` spells an empty line; `...` is literal).
- Strings and bytes display with `repr`, other non-unit expressions as `out.print` renders them; a statement contributes
  only what it writes to `out`.
- One docstring's examples share a generated function in its module: locals persist, private helpers are in scope, and
  `fs`, `net`, `clock`, `entropy`, `env` and `out` get the [capability stand-ins](#capability-parameters).
- The case is `module::function.example`: `--filter .example` selects examples alone, and sidecar skip reasons, settings
  and providers use that name. A provider may replace an imported dependency, not the module defining the docstring.
- An example may `return` (the case ends there, output so far compared; a later prompt fails as not reached; `return False`
  fails). `fail`, `try`, and `break` or `continue` outside the example's own loop are refused. See
  [runnable examples](../functions.md#runnable-examples).
- A malformed example fails its own case with the checker's diagnostic and docstring line; the rest still run. A sidecar
  never overrides the transcript.
- Directory runs include example-only modules; an imported module's examples belong to the first root that reaches it.

### Checking examples without running them

`selka check ENTRY.selka --examples` compiles every example of the modules the entry loads, as `selka test` does, and runs
none; a refusal points at its prompt line.

```console
$ selka check alts.selka --examples
alts.selka:256:28: error[E_OWN_MARKER]: a bare `text` only lends the local `text`, and the `mut` local `merged` needs its own value; write `own text` to give it, or `copy(text)` to keep both
      ...         merged = text
                             ^
  note: ownership rule B2
```

- `--diagnostics=json` gives `diagnostic-v1` lines. A `fix` is kept only when its edit lies inside the text one `>>> ` or
  `... ` line copies ([`selka fix`](fix.md#docstring-examples) applies it); otherwise a note says why not.
- Warnings are not reported. A graph with no `>>>` example is not checked, and the entry's own bodies only when an example
  needs compiling: run plain `selka check` for those.
- Passing examples are cached (`--no-cache` skips that). Exit status: 0 all compile, 1 one is refused, 2 usage or host
  failure, 3 an import the policy denies.

## Capability parameters

A test may declare `clock: Clock`, `entropy: Entropy`, `fs: Filesystem`, `env: Environment` and `net: Network` parameters
beside `out: Stream` and `err: Stream`. None needs a cases-file argument: the runner passes
[deterministic stand-ins](../effects.md#deterministic-stand-ins) (`time.simulated_clock`, `random.seeded_entropy`,
`filesystem.memory`, `environment.fixed`, `network.denied`).

| Parameter | What the test receives |
| --- | --- |
| `Clock` | a simulated clock at 2000-01-01T00:00:00Z (`946684800000000000` Unix nanoseconds) until `time.advance` moves it |
| `Entropy` | SplitMix64 seeded with the first eight bytes, little-endian, of the SHA-256 of the test's qualified name, or `N` under `--seed N` |
| `Filesystem` | empty, in memory, root `"."` (`fs.listdir(".")` lists it; reading the root reports `is a directory`) |
| `Environment` | no names |
| `Network` | refuses every connection with `network.denied_here()` |
| `Stop` | no signal reaches it; `process.request_stop` delivers the notice ([hearing a stop](../io.md#hearing-a-stop)) |

A `Host` parameter is never supplied: without cases-file arguments the test fails as a property test (`a Host capability is
never handed to a test`). Each test has its own stand-ins, so nothing leaks between tests; its entropy is stable across
runs, renaming the test changes it, and `--seed N` pins every test's (the seed is part of the receipt's identity).

```selka
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
            mut generator = own sampled
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
    print(out, test_uptime_counts_whole_seconds(clock), test_roll_stays_on_the_die(random.seeded_entropy(1)))
    return 0
```

## Property tests

A `test_` function with data parameters and no `arguments` in the cases file is a property test. The runner generates an
input for each data parameter from its type and calls the test once per input. It passes when every input returns `True`
(or `Ok(True)`) without trapping: 100 inputs unless `--property-runs N` (1 to 1,000,000) says otherwise. `False`,
`Ok(False)`, an `Err` and a trap (a failed `assert`, a broken contract, an index out of bounds, an overflow) fail it. A
cases-file entry with `arguments` wins and runs once; an `expected` without `arguments` is refused.

```selka
# doc: check
import lists

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
    mut ys = copy(xs)
    lists.reverse(mut ys)
    lists.reverse(mut ys)
    return ys == xs

@requires(len(xs) > 0, "an average needs a value")
public func test_average_is_within_range(xs: i32[]) -> bool:
    mut converted: int[] = []
    for x in xs:
        append(mut converted, int(x))
    mut mean = total(converted) // len(xs)
    return int(min(xs)) <= mean and mean <= int(max(xs))

public func test_a_span_is_ordered(span: Span) -> bool:
    return span.low <= span.high

public func test_budget_stays_below_100(costs: int[]) -> bool:
    return total(costs) < 100

func main() -> int:
    return 0
```

```console
$ selka test app/main.selka
passed main::test_a_span_is_ordered
passed main::test_average_is_within_range
failed main::test_budget_stays_below_100: falsified after 8 passing runs (seed 8562780449005306539)
  minimal input (62 shrinks, 512 attempts):
    costs = [100]
  original input (run 9):
    costs = [1, 9223372036854775807]
  reason: returned False
  original reason: R_OVERFLOW (add: left 1, right 9223372036854775807, width 64)
      in main::total at main.selka:11:19
      in main::test_budget_stays_below_100 at main.selka:29:12
  reproduce: selka test app/main.selka --filter 'main::test_budget_stays_below_100' --seed 8562780449005306539
passed main::test_reversing_twice_is_the_identity
3 passed, 0 cached, 1 failed, 0 skipped
```

### Generated inputs

Inputs are deterministic: seeded by the test's seed and the run number, so run 37 is the same everywhere, and renaming the
test draws new ones. Under the default `legacy` policy sizes grow from 0 to 100 over the runs. Integers favour the edges of
their width, floats include both zeros, infinities and NaN, and strings include controls, NUL and non-ASCII scalars; every
other type generates each case, element or field of its type.

Function values and `Host` are never generated: a property test with such a parameter, or a result that is not `bool` or
`Result[bool, E]`, fails naming it.

### Preconditions and invariants

- An input that breaks the test's `@requires` is discarded, not failed; a precondition broken inside a function the test
  calls is a failure.
- Generated values bypass constructors, so each `test_` function checks the [`@invariant`](../contracts.md#invariants) of
  every record its parameters hold and discards inputs that break one. A list of invariant-carrying records is accepted or
  discarded as a whole: generate the fields and build the records in the test.
- More runs replace discards; past ten times the requested runs the test fails, naming the clause that rejected most:

```console
$ selka test app/main.selka --filter test_picky
failed main::test_picky: too many discarded inputs: 1001 of 1001 generated inputs broke a precondition before 0 of 100 runs passed; most often test_picky requires `n == 12345`: a single value
  reproduce: selka test app/main.selka --filter 'main::test_picky' --seed 7017186523047142524
0 passed, 0 cached, 1 failed, 0 skipped
```

### Shrinking and the report

The first failing input is shrunk (at most 2,000 candidates): integers move toward 0, floats toward `0.0`, strings, bytes
and collections lose elements, records shrink field by field, enums, unions and `Option` move toward earlier cases and
`None`. The report shows the minimal input as literals, the generated input and its run, the reason (with an `Err`'s
[error return trace](../results-and-options.md#error-return-traces), or a trap's code, message and frames) and a command
that reproduces it.

`--json` adds `property`: `seed`, `counts` (`runs`, `passed`, `discarded`, `processes`, `shrinks`, `attempts`) and, on
failure, `failure.minimal` and `failure.original` with typed JSON `arguments` and `literals`.

```console
$ selka test app/main.selka --filter test_budget --json | jq '.tests[0].property.failure.minimal'
{
  "arguments": {"costs": ["100"]},
  "literals": {"costs": "[100]"}
}
```

### Batches and receipts

A passing 100-run property is one process; replacements and shrink candidates run in further batches. A passing property
is reused, and changing `--seed` or `--property-runs` reruns it. A failure is never reused.

### Resumable indexed campaigns

`--property-policy indexed-v1` extends a property's budget or resumes an interrupted command:

```console
$ selka test app/main.selka --filter test_reversing --seed 7 --property-policy indexed-v1 --property-runs 1000
$ selka test app/main.selka --filter test_reversing --seed 7 --property-policy indexed-v1 --property-runs 2000
```

- It repeats the 100-run size schedule independently of the budget, so a larger budget keeps every earlier input; the
  default `legacy` policy keeps its budget-dependent schedule and whole-test receipts.
- A completed prefix is kept: an unchanged request reuses it without a process, a larger budget continues from it, and an
  interrupted command resumes from it. Reuse needs the same dependencies, seed, compiler, providers, environment and
  limits. A failing batch never extends passing evidence.
- JSON `property.campaign` reports `policy`, `generated`, `submitted`, `observed`, `fresh_classified`, `reused` and
  `next_ordinal`. The progress is disposable cache data; `--force`, `--verify-facts`, leak checking, native links and
  untracked effects run fresh.

## Directory runs

`selka test DIR` runs every `.selka` file beneath `DIR` in sorted path order, except folders starting with `.` (`.git`,
`.zig-cache`, `.selka-cache`), `build`, `zig-out` and `node_modules` at any depth beneath the folder you name (that folder
is walked whatever it is called), the folder `--cache-dir` names, links to folders, and anything in `release.exclude` of
`selka.json` (`{"version": 2, "release": {"exclude": ["tmp/"]}}`).

Everything else is walked: a scratch `.selka` file that declares `main` or a test is a root and runs, and one that cannot
be loaded is listed as failed, so keep scratch in a `.` folder or in `release.exclude`. A run that finds nothing says why
on standard error (exit 3). `selka packages build DIR --command test` walks the same folders
([packages](packages.md#symbolic-links-repeated-warnings-and-interface-files)).

- A file declaring a top-level `main`, every `*_test.selka`, and a library that declares a test and that no root reaches
  is a root, so a test file needs neither `main` nor the suffix (of two such libraries, the importer).
- Each test runs once and is listed once, under the first root, in sorted order, whose import closure holds it. A root also
  runs every test its own [cases file](#per-entry-cases-files) names, which can list a test under several roots.
- `selka test FILE` runs every test its closure declares and shares passes with directory runs.
- With no `selka.json`, a file that loads only with the directory as import root takes it, as `selka check DIR` does
  (`rows/more_test.selka` is `rows.more_test`); one that loads with its own folder keeps it. A file that loads neither way
  is listed as `failed PATH: failed to check or build, so no tests ran` and the rest run, with a note to add a
  `selka.json` of `{"version": 1}` where its imports start or to pass `--import-root DIR`. An unreadable `selka.json` of
  the directory stops the run.
- `--jobs N`, else `SELKA_JOBS`, else the CPU count capped by available memory, bounds the roots running at once (largest
  first) and the test processes.
- A test-declaring source that no root loaded fails the run as `test-declaring source was not loaded by any test program`;
  a source, configuration or toolchain change during the run fails it with `SourceChanged`. `--cases` is refused (status
  2): each entry's own cases file applies.

The exit status is 2 if any root failed to set up, else 1 if any line failed, 3 if nothing was selected or all were
skipped, else 0.

```console
$ selka test . --cache-dir /tmp/suite-cache
passed scaled_test::test_scaled
passed scanner_test::test_is_digit
2 passed, 0 cached, 0 failed, 0 skipped
$ selka test . --cache-dir /tmp/suite-cache --filter test_scaled
cached scaled_test::test_scaled
0 passed, 1 cached, 0 failed, 0 skipped
$ selka test . --cases scaled_test.cases.json
error: --cases requires a single test entry
```

## Reusing unaffected results

A passing test leaves a record in `<cache>/engine-v1` (`<cache>` is `--cache-dir DIR` or `.selka-cache/core`); a later run
that asks for the same thing prints `cached` instead of building and running it. Failures, traps and timeouts are never
recorded. `--json` gives `cache.reason`: `engine-hit` (IR key), `engine-program-hit` (linked program) or
`engine-report-hit` (whole entry replayed without a check).

A record stays valid when you edit code the test does not reach, a comment or a blank line; editing a reached body,
string, type or signature invalidates it. Records are also keyed by:

- build mode, `--no-facts`/`--verify-facts`, `--generic-vectors`, `--trap-frames`, `--counters`, the seed, property runs,
  budgets, `SELKA_CORE_LEAKCHECK`, the test's cases-file entry, `selka.json` and its import policy, and the compiler and
  toolchain (paths relative to the project root);
- every `SELKA_*` variable except the placement ones (`SELKA_CORE_RUNTIME_CACHE`, `SELKA_TEST_SHARED_CACHE`, `SELKA_JOBS`,
  `SELKA_TEST_ISOLATE`, `SELKA_TEST_CHILDREN`, the telemetry directories), and the C compiler and Zig inputs (`CPATH`,
  `C_INCLUDE_PATH`, `LIBRARY_PATH`, `ZIG`, `ZIG_LIB_DIR`, `SOURCE_DATE_EPOCH`, `LD_*`).

Output, [stand-ins](#capability-parameters) (the record binds the seed) and stored callbacks do not prevent reuse. A test
reruns every time only when its call tree declares an `extern func`, has a host function, reaches a `Host` capability, or
calls a callback in a program that asks for `function_digest`; `--json` then gives the reason `live-effects: ` naming the
function.

A fully passing or replayed run also records the whole report, replayed while nothing it loaded changed (never in a project
with `"interface_files": true`). `--verify-facts` and a non-zero `SELKA_CORE_LEAKCHECK` are keyed modes: a repeat is
`cached`, and neither serves a plain run's records.

What runs every test again:

- `--force` (a pass is still recorded), `--link FILE.c`, and a non-empty `LD_*` variable.
- `--no-cache`: an empty private cache, removed afterward, so no record, report, program, front-end, stage or shared cache
  is read or written ([native builds](native-build.md#--verify-cache-and---no-cache) lists the object store it still
  uses).
- `SELKA_ENGINE_SHADOW=0` turns the engine off.

```console
$ selka test app/main.selka --cache-dir /tmp/test-cache
passed main::test_square
passed main::test_sum
2 passed, 0 cached, 0 failed, 0 skipped
$ sed -i 's/return left + right/return right + left/' app/main.selka
$ selka test app/main.selka --cache-dir /tmp/test-cache
cached main::test_square
passed main::test_sum
1 passed, 1 cached, 0 failed, 0 skipped
$ selka test app/main.selka --cache-dir /tmp/test-cache --force
passed main::test_square
passed main::test_sum
2 passed, 0 cached, 0 failed, 0 skipped
```

Qualification switches (they change the identity): `SELKA_TEST_CHILDREN=1` runs every root of a directory run
in a child process, `SELKA_TEST_KEYS=per-test` keys each test from its own lowering, and `SELKA_CACHE_PLAN_MODE=shadow`
or `reference` cross-checks the cache planner.

### Sharing results between worktrees

- Records of ordinary project tests are shared across compatible worktrees in `$XDG_CACHE_HOME/selka/native-tests` or
  `~/.cache/selka/native-tests`. `--shared-cache-dir DIR` or `SELKA_TEST_SHARED_CACHE` names another
  root: the flag wins, an empty environment value turns sharing off, an empty flag path is rejected.
- Records live under `DIR/native-tests-v3/engine`; prefer a dedicated root outside the worktrees. A different checkout
  path alone does not rerun a test. A same-key record that gave a different result is a mismatch: the test runs and
  `DIR/native-tests-v3/mismatches.log` gains a `mismatch engine …` line.
- A named store that is unusable is an error; an unusable default is skipped. `--force` bypasses shared hits; `--no-cache`
  disables lookup and publication.
- Only provably portable tests are shared: no live effects, everything inside the project root, legacy property policy. A
  source extern, native links, provider overlays and docstring examples keep records in the work directory.

```bash
test_cache=$(mktemp -d)
trap 'rm -rf "$test_cache"' EXIT
selka test examples/testing/main.selka --cache-dir "$test_cache/private-a" --shared-cache-dir "$test_cache/shared"
selka test examples/testing/main.selka --cache-dir "$test_cache/private-b" --shared-cache-dir "$test_cache/shared"
```

## Affected selection

`selka test --affected --against REF` runs only the tests that reach a declaration whose source lines changed since the
git revision `REF`.

- Changed lines come from one `git diff` (files not yet added count as changed throughout). A line inside a function or
  constant changes that declaration; a line elsewhere (an import, a record) changes every declaration of the module.
- A test runs when a function it reaches is changed, a specialization of one, or in a wholly changed module. A test the
  core cannot build keeps running, and a change in a module the program does not load selects nothing.
- `--filter` applies first. `affected: N selected, M skipped against REF` and a
  `skipped NAME: no changed declaration is reachable` line per dropped test go to standard error, so `--json` stays
  machine-readable. An empty selection exits 3.
- `--against` without `--affected`, or the reverse, is a usage error; an unresolvable `REF` exits 2
  (`--against names a revision git cannot resolve`).
- Such a run neither replays nor records a whole-run report. CI and `lint --gate` run the whole set.

```console
$ selka test app/main.selka --affected --against HEAD
affected: 1 selected, 1 skipped against HEAD
skipped main::test_unrelated: no changed declaration is reachable
passed main::test_total
1 passed, 0 cached, 0 failed, 0 skipped
$ selka test app/main.selka --affected --against HEAD   # nothing changed since HEAD
affected: 0 selected, 2 skipped against HEAD
skipped main::test_total: no changed declaration is reachable
skipped main::test_unrelated: no changed declaration is reachable
0 passed, 0 cached, 0 failed, 0 skipped
$ echo $?
3
```

## Isolated source provider fixtures

To fake a capability, prefer [capability parameters](#capability-parameters). A provider fixture replaces a dependency's
source wholesale, for a collaborator whose behaviour the test must pin: a case's `providers` object maps existing
dependency `.selka` paths, relative to the project root, to replacement source text. The runner checks the project as
written, then again with the replacements applied in memory; files on disk are never modified.

- A provider replaces an existing dependency only, never the entry module or a path the project does not load
  (`error: invalid test provider dependencies`).
- The replaced module's exports, the selected test's signature and every type it reaches must keep their checked
  structure, or the run fails with `ProviderSignatureChanged` or the check error a caller now sees.
- Cases naming the same providers share one check and one build. A case's providers are part of its receipt's identity, so
  changing a source runs the case again.

```console
$ selka test app/main.selka
failed main::test_reading: expected true, got false
0 passed, 0 cached, 1 failed, 0 skipped
$ cat cases.json
{
  "main::test_reading": {
    "providers": {"reading.selka": "public func sample() -> int:\n    return 42\n"}
  }
}
$ selka test app/main.selka --cases cases.json
passed main::test_reading
1 passed, 0 cached, 0 failed, 0 skipped
$ selka test app/main.selka --cases cases.json
cached main::test_reading
0 passed, 1 cached, 0 failed, 0 skipped
```

## Deterministic provider fixtures

A test has no ambient authority, so its outcome is a function of its sources, its cases-file entry and the keyed settings:
that is what lets a receipt stand in for it. Code that needs the real machine takes a
[capability parameter](#capability-parameters); for a collaborator whose production answer the test must not depend on, a
[provider fixture](#isolated-source-provider-fixtures) returns a fixed value and the case stays reusable. A fixture
changes what the guest computes; it does not validate a real implementation.

```console
$ selka test app/main.selka --filter test_stamp
failed main::test_stamp: property test parameter `host: Host` cannot be generated: a Host capability is never handed to a test
0 passed, 0 cached, 1 failed, 0 skipped
$ selka test app/uptime.selka
passed uptime::test_uptime_counts_whole_seconds
1 passed, 0 cached, 0 failed, 0 skipped
```

## Test files and their modules

### Private declarations

A test file `<name>_test` that no other module imports sees every non-`public` function, type and constant of module
`<name>`, so a helper need not become `public` to be tested. Any other importer, another module's test file included, gets
`E_PRIVATE_SYMBOL`. The entries that `selka check DIR` and a directory run generate import a test file only to load it, so
they do not count. In `scanner.selka` and `scanner_test.selka`:

```selka
# doc: project scanner-private
# doc: file scanner.selka
# doc: check
func is_digit(c: str) -> bool:
    return c in "0123456789"
```

```selka
# doc: project scanner-private
# doc: file scanner_test.selka
# doc: entry scanner_test.selka
import scanner


public func test_is_digit() -> bool:
    return scanner.is_digit("7") and not scanner.is_digit("x")
```

```console
$ selka test .
passed scanner_test::test_is_digit
1 passed, 0 cached, 0 failed, 0 skipped
```

### Per-entry cases files

An entry's cases file sits beside it as `<stem>.cases.json` (`scaled_test.selka` owns `scaled_test.cases.json`). A run of
the entry without `--cases` applies it, so a directory run gives each entry its own file; an explicit `--cases FILE` wins
for a single entry. A cases file is a JSON object keyed by qualified test name; each entry may carry:

| Key | Holds |
| --- | --- |
| `arguments` | typed JSON values by parameter name |
| `expected` | the expected result |
| `skip` | a reason, reported as `skipped NAME: REASON`; not a failure, but a run whose selected tests were all skipped exits 3 |
| `providers` | replacement sources |

An unknown test name or key stops the run with `error: test cases: ...` and status 2.

```console
$ cat scaled_test.cases.json
{"scaled_test::test_scaled": {"arguments": {"n": "21"}, "expected": "42"}}
$ selka test .
passed scaled_test::test_scaled
cached scanner_test::test_is_digit
1 passed, 1 cached, 0 failed, 0 skipped
```

## Dropped flags

These flags are refused with status 2 and a one-line reason. `--whole-program` and `--qbe PATH` are ignored.

| Flag | Replacement |
| --- | --- |
| `--diagnostics` | `selka check FILE.selka --diagnostics=json` |
| `--report`, `--timings`, `--timings=json`, `--explain-invalidation` | `--json`; `selka run FILE.selka --timings` times one program |
| `--friction-log` | `selka check FILE.selka --friction-log=PATH` |
| `--pure-skip` | none: a failure is never replayed |
| `--max-calls` | `--max-steps` and `--max-frames` |
| `--bench`, `--bench-only`, `--bench-output`, `--bench-baseline`, `--bench-policy`, `--bench-profile`, `--bench-warmup`, `--bench-batches`, `--bench-batch-ms`, `--bench-timeout-ms`, `selka bench-promote` | none: time a built program |
| `--gc-stress`, `--gc-runtime`, `--rc-runtime`, `--legacy-sharing`, `--value-semantics` | none: checked ownership is the only memory model |
| `--library`, `--provider`, `--link-library`, `--library-path` | `extern func` with `--link FILE.c` |

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/guest-tests.md).
