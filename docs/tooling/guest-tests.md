# Guest tests

`selka test` is the compiler's own runner for tests written in the language. It
checks the project, finds the exported functions whose names begin with `test_`
and runnable function docstring examples,
builds them with the compiler's core (Core IR, LLVM, `zig cc`) and runs each one
in its own forked trial. Cases are configured with one JSON file rather than with a
framework inside the language, and the runner needs no Python. A run builds a
program in optimized debug by default: Core passes and per-module LLVM `-O0` (`selka build` and `run`
default to the [lean debug build](native-build.md#debug-code-generation) instead; `--debug-lean` asks the runner for it).
`--optimize-debug` uses LLVM `-O2`; `--unoptimized` runs no Core pass. `--release` builds the optimized whole program, as
`selka build --release` does, and all modes keep every overflow, cast and bounds
check that cannot be proved unnecessary. The design record is the guest test workflow (`docs/experiments/guest-tests.md`).

## `selka test`

```text
selka test FILE.selka|DIR [--release | --unoptimized | --optimize-debug | --debug-lean | --debug-o0] [--json] [--filter S] [--affected --against REF]
    [--no-cache] [--force] [--jobs N] [--cases PATH] [--max-steps N] [--max-frames N]
    [--max-memory SIZE] [--timeout-ms N] [--seed N] [--property-runs N]
    [--property-policy legacy|indexed-v1] [--link FILE.c]
    [--verify-facts | --no-facts] [--cache-dir DIR] [--shared-cache-dir DIR] [--zig PATH]
```

The command discovers `test_` functions in the project's reachable public
schema. A parameter-free test returning `bool` asserts `True`, and one returning
`Result[bool, E]` asserts `Ok(True)`, so it may use `try` and a failure it
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
| bytes the heap may hold | `--max-memory SIZE` (`K`/`M`/`G`) | `SELKA_MEMORY_LIMIT`, else `limits.test.max_memory`, else 512 MiB | `R_MEMORY_BUDGET` |
| wall clock per test | `--timeout-ms N` | 60,000 | the test fails, `timed out after N ms` |

`limits.test` lives in `selka.json`
([runtime budgets](runtime-budgets.md)). Raise `limits.test.max_steps` (or pass
`--max-steps N`) for a growth test that executes more blocks than the 1,000,000
default; `--max-steps 0` removes the ceiling, and the trial still counts and
reports the blocks it executed ([work per test](#work-per-test)). A frame
budget whose stack (32 KiB per frame plus 8 MiB) the byte ceiling cannot back is
refused before anything is built. The 1,024-frame default is a guard against runaway recursion, so a test
of a recursive parser's depth cap (10,000 levels of nesting, say) traps
`R_FRAME_LIMIT` under `selka test` although the same recursion runs in a built
binary: [Recursion and the frame budget](#recursion-and-the-frame-budget) has the message and the two ways out.

**A test on a long input meets the step budget.** The budget counts executed blocks, not time, and a built binary
counts none, so code that is linear still stops a test: a loop over the bytes of a text executes about six blocks per
byte (a scan of 400,000 bytes counted 2,400,068), and a test that builds `strings.repeat("[", 60000)` and makes a few
passes over it fails with `R_STEP_LIMIT` ("this test passed its budget of 1,000,000 steps (every test has one); raise it with
`selka test --max-steps=N` or `limits.test.max_steps` in `selka.json`") although a
built program runs the same code on that input with no such limit. Cut the input, or raise the budget for that one test: `--filter`
picks the test and `--max-steps` applies to the tests picked, so the others keep the default.

```console
$ selka test text_test.selka --filter test_long_input --max-steps 20000000
```

A project with several such tests sets `limits.test.max_steps` in `selka.json` instead, which every test of the project
then gets. `--json` reports each test's `steps`, so a passing run shows how far under the ceiling a test is (a count that
grows with the square of the input is the quadratic search the test was written to catch).

`--json` prints a `native-tests-v1` report instead of the text listing: one
object per test with `name`, `status` (`passed`, `cached`, `failed`, `skipped`
or `unsupported`), `reason`, `advice` (only for a test that returned `false`), `at`, and — when the test's trial ran, or its
receipt recorded them — `steps` and `peak_bytes`
([work per test](#work-per-test)), then the report's counts
(`passed`/`failed`/`skipped`/`cached`/`unsupported`, `exec_receipts`), the run's
`result` (`passed`, `failed` or `nothing ran`, the same rule as the exit status
below) and the project `sources` the check loaded.

Exit status:

| Status | When |
| --- | --- |
| 0 | every selected test passed or was replayed, with at least one not skipped |
| 1 | a test failed or trapped, a test could not be built (`unsupported`), or the project does not check |
| 2 | a usage error, an unreadable entry, a `selka.json` that does not load, an invalid cases file or provider fixture, or a frame budget the byte ceiling cannot back |
| 3 | nothing was selected (a filter or `--affected` that matches nothing), every selected test was skipped by its cases file, or the project's import policy denies an import |

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

Every call of a program function is a frame, and a test may hold 1,024 of them (`--max-frames`, or
`limits.test.max_frames`). A test that recurses deeper fails with `R_FRAME_LIMIT`: a parser fed 10,000 levels of nesting,
a walk down a long list or tree, or an interpreter written in the language evaluating a deeply nested program. The same
recursion runs under `selka run` (no frame budget) and in a built binary (the native stack, 8 MiB by default, holds
10,000 to 20,000 frames of a large function and far more of a small one; [what bounds a built
binary](runtime-budgets.md#what-bounds-a-built-binary)). The failure
prints the innermost sixteen frames, the count of the rest and the budget's advice (1,008 and 16 are the 1,024 frames of
the default):

```console
$ selka test deep_test.selka --filter test_deep
failed deep_test::test_deep: R_FRAME_LIMIT
  in deep_test::depth at deep_test.selka:4:16
  in deep_test::depth at deep_test.selka:4:16
  ... (16 lines in all)
  1008 frames omitted

this test went deeper than its budget of 1,024 nested calls (every test has one); raise it with `selka test --max-frames=N` or `limits.test.max_frames` in `selka.json` (each frame reserves 32 KiB of stack, so --max-memory must cover N x 32 KiB)
```

There are two ways out. Raise the budget for the test that needs it, `selka test deep_test.selka --filter test_deep
--max-frames 6000`, or set `limits.test.max_frames` in `selka.json` for every test of the project; a test may
map its `--max-memory` plus 256 MiB (768 MiB by default), so the default backs up to 23,296 frames, and a larger budget needs
`--max-memory` too (without it the run is refused before anything is built, exit status 2, `selka test: a call-depth
budget of 40000 frames (--max-frames) reserves 1.2 GiB of native stack (32 KiB per frame), but a test may map only 768
MiB: raise --max-memory to at least 2G, or lower --max-frames to at most 23296`). Or keep the deep case out of the unit
tests: a recursion that deep is a property of the built program, so check it in an acceptance run of the binary
(`selka build -o`, then the binary on a deep input), which has no frame budget. The step budget has its own paragraph
above; a recursion that is deep and also does work can meet both.

### Test entries

A test entry is a `.selka` file, not necessarily a program. A file with no `func
main(` line of its own, such as a library module or a standalone `*_test.selka`,
is checked with a stub `func main() -> int: return 0` appended, so its exported
`test_` functions run without editing the source. Any `.selka` file named on the command
line is a test entry, whatever its stem; the `*_test.selka` suffix matters only to
directory discovery. A file without a `module` header is module `<stem>`:
`solo_test.selka` holds `solo_test::test_alone`. Such a file may import standard
modules or project modules; its module identity comes from its path. A redundant
`module` header is rejected with `E_MODULE_HEADER`. A `--local-stdlib` replacement
is a standard module for import resolution, so a headerless test entry may import
the local `csv.selka` it deliberately replaces.

A standalone `*_test.selka` may sit in a subdirectory of the project. Its imports
and its module name resolve from the enclosing project root: the nearest
ancestor holding `selka.json`, or the nearest ancestor holding a non-test `.selka`
source. `tests/parser_test.selka` is therefore module `tests.parser_test`, and
`import sexpr.parser` reads `sexpr/parser.selka` from the project root with no module
header. A project that does not check prints its diagnostics and exits 1.

### Failure text

A failed expectation reports both sides as `expected <value>, got <value>`. A
failed `assert` keeps its `R_ASSERT` code and source location and reports the
message written after the condition. A test's output, written through an `out:
Stream` or `err: Stream` parameter, is captured: the runner appends it to a
failure's text and discards it when the test passes. A trap prints its code,
its message, the innermost sixteen frames that led to it (then `N frames
omitted` when there were more) and, for a budget's trap, the runtime's hint. A test whose last line is `return LEFT op RIGHT`
(`==`, `!=`, `<`, `<=`, `>`, `>=`) over integers, floats or texts and that returns `false` reports both values and the line of
the comparison beneath `expected true, got false`, worded and cut as a failing `assert`'s are (`returned comparison: left 6,
right 5`, then `in main::test_ints at main.selka:4:12`); the `reason` field of `--json` carries the same lines. A test that
returns any other `false` (an `and` of two facts, a `bool` or a record compared, a variable) is told what to do about it on a
line of its own after the failure (`advice:`; a field of the same name, beside `reason`, in `--json`): write one `assert` for
each fact, since a failing `assert left == right` prints both values. A failed `assert`, a trap and a returned comparison that
named its values get no advice.

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

Here `test_total` returns `int`, and `main.cases.json` beside the entry
expects `"42"` of it.

A test whose program the compiler's core cannot build is reported as
`unsupported NAME: E_CORE_UNSUPPORTED (REASON) at LINE:COLUMN` and left out of
the executable. The core is the only back end, so such a test did not run: the
summary line ends with `, N unsupported (not built, so not run: the run fails)`,
`--json` reports `"result":"failed"`, and the run exits 1, as for a failed test.
Before 14 November 2026 (lane FX10) it was neither a pass nor a failure and the
run could exit 0, which hid a test that a stored record had stopped from being
built.

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
`SELKA_TEST_ISOLATE=1` gives every test its own process again, as the check
batching is tested against.

A trial's work is written beside the batch's response file, one record per trial
row (`<response>.work.<row>`), so batching needs no extra process and no reset:
each forked trial starts its own record at its own step and byte ceilings
([work per test](#work-per-test)). `SELKA_TEST_ISOLATE=1` runs the same trials
one process at a time and reports the same counts.

## Work per test

Every test trial counts its work. `steps` is the executed blocks of program
functions, the count the step ceiling charges — one per block entry, so it
measures the test's own work in selka code rather than time. `peak_bytes` is
the peak of the byte ceiling's accounting: the 64 KiB chunks small blocks are
carved from (charged once and never refunded) plus each large block's usable
size while it lives. A trial starts from the bytes the process already holds,
so a test that allocates nothing still reports the chunk that was already
there. Both values appear in `--json` and in the test's receipt, so a cached
result carries them too:

```bash
selka test app/main.selka --json
# {"version":"native-tests-v1","tests":[{"name":"main::test_flow","status":"passed",
#  "reason":"","at":"","steps":41200,"peak_bytes":65536}], ...}
```

`allocations` is not reported. The byte ceiling's accounting charges 64 KiB
chunks and large blocks, not block events: a small block carved from a chunk is
a pointer bump and a recycled free-list block is charged nothing at all, so
counting managed-block allocations would put a counter update on every
allocation, the cost the ceiling's design exists to avoid. A candidate counter
in `small_alloc` and `block_alloc` cost about five instructions per allocation:
released, it raised a 500,000-allocation release program from 248,991,468 to
251,496,309 retired user instructions (+1.0%), so the field is left out rather
than paid for on every test's allocation path. `steps` and `peak_bytes` carry
the work and memory signal instead. A test that needs an allocation count asks
`testing.allocations` for one workload: counting is off around every ordinary
test and on only while that measurement runs
([how work grows](#how-work-grows)).

A plain `selka test` (without `--json`) prints one further line for each test
whose `steps` changed by 2x or more, in either direction, since the last run of
the same test in the same build mode:

```console
$ selka test http --cache-dir .selka-cache/core
passed http::test_headers
work: http::test_framing steps 41,200 → 168,900 (4.1×)
2 passed, 0 cached, 0 failed, 0 skipped
```

The ratio is the new count over the old one, so a shrink prints a fraction such
as `0.2×`. The previous values live in a small per-worktree store under the
cache directory (`--cache-dir`, default `.selka-cache/core`):
`tests/work-v1/<build mode>/<digest of the test name>.txt`, holding the test's
last `steps` and `peak_bytes`. A plain run that reports counts compares with
the record, prints the line when the steps crossed 2x and then replaces the
record, so an unchanged rerun is silent. A missing or damaged record, a zero
previous count (a ratio to zero is undefined) and a change in `peak_bytes`
alone print nothing. Because `--json` only reports the counts, a directory
run's child processes never consume the values the directory run's parent
compares against. Nothing else about the listing changes.

## How work grows

`testing` ([standard library](../standard-library.md#testing)) states a
workload's growth class instead of timing it. `testing.steps(work, n)` runs
`work(n)`, a `func(int) -> int`, and answers the blocks it executed — the same
count the step ceiling charges, so it measures work in program blocks rather
than seconds. `testing.allocations(work, n)` answers the managed blocks the
runtime allocated for it, one event per block the runtime allocator hands out:
the event `--counters` reports as `allocs`. A block reused from a thread's list
free list by the inline list fast path is not a new allocation, so a list-append
loop can show few allocations while its block count grows; allocations carry the
text-building shapes and blocks carry loops. `testing.allocations_writing(work,
out, n)` measures the same for a workload that needs a `Stream` to print what it
builds, such as the f-string print shape.

`testing.growth(work, small, large)` runs both sizes and answers the larger of
the two counts' growth ratios without judging it. `testing.linear(work, small,
large)` fails when either count grows by more than 1.5× the step: the ratio
limit is `1.5 × (large ÷ small)`, so at 1,000 → 4,000 an `n log n` workload
(about 4.8×) passes against 6× and a quadratic one (16×) fails. A count that is
zero at both sizes passes. `testing.constant(work, small, large)` allows 1.5×
plus two counts of slack, for a workload whose count does not depend on `n`. A
failure is an assertion whose message names the counter, both values and the
ratio, and `selka test` reports it as the failed test's first line:

```console
# A deliberately quadratic shape at a 4x step reports:
failed perf::test_scan_is_linear: R_ASSERT: testing.linear: steps grew 15.8× from 30506 at n=100 to 482006 at n=400; the limit is 6.0×
  in testing::within at @stdlib/testing.selka:52:12
  in testing::linear at @stdlib/testing.selka:104:9
  in perf::test_scan_is_linear at perf.selka:15:12
0 passed, 0 cached, 1 failed, 0 skipped
```

Both sizes run inside the trial's step budget, 1,000,000 executed blocks by
default, so a growth test whose two sizes execute more raises it with
`limits.test.max_steps` in the project's `selka.json` (or `--max-steps N` for
one run):

```console
$ selka test project/main.selka --max-steps 40000000
```

The allocation counter is not wired into every allocation path. Its flag-guarded
event exists only in the runtime variant that an executable linking a `testing`
counter reader compiles, so an ordinary program or test file keeps the allocation
path it had: a release loop of 500,000 managed allocations ran
148,176,879 instructions with and without the feature (the samples differ by the
launcher's noise). The program that does link a reader pays three instructions per
managed allocation while a measurement is inactive — 149,677,094 against
148,176,878 on the same loop, about +1.0% — and the counter update itself only
inside `work(n)`. A batched executable that includes a growth test therefore
carries that read for the tests it runs; a file or program without `testing` never
does.

The counts differ between optimized debug and release builds, so a test compares
growth, or asserts zero only where both modes agree. `tests/lang/performance_idioms.selka`
is the gated suite: each fixed idiom asserts its class, each quadratic idiom
asserts through `testing.growth` that `testing.linear` would fail, storing an
f-string allocates once per string, and printing one allocates nothing; the gate
runs it in both modes. The counter readers are reserved to `testing`: ordinary
source that spells `__test_blocks` or `__test_allocations` is `E_INTERNAL_NAME`.
A program that carries no executed-block accounting — a binary from `selka
build`, or `selka run` without `--max-steps` — traps `R_NO_STEP_ACCOUNTING`
when a check reads the counters; `selka test` always counts its blocks, even
under `--max-steps 0`.

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

A `>>> ` line begins an example and `... ` continues it. Expected output ends at
a blank line, another prompt or the docstring's end. Output is compared exactly;
`<BLANKLINE>` spells an empty line and `...` in expected output is literal text.
Strings and bytes display with `repr`; other non-unit expressions display as
`out.print` renders them. A statement or unit expression contributes only what
it writes to `out`.

All examples in one docstring share a generated function in their defining
module: local declarations persist between prompts, and private helpers are in
scope. The names `fs`, `net`, `clock`, `entropy`, `env` and `out` receive the same
stand-ins as ordinary capability parameters. The case is named
`module::function.example`, so `--filter .example` selects examples alone.

An example can `return`, as that generated function returns `bool`: the case ends
there, the output written so far is compared with the expected output of the
prompt it returned in, a later prompt never ran and fails as not reached, and
`return False` fails the case (`return True` ends it early with the output so
far right). `fail`, `try` and `break` or `continue` outside the example's own loop
are refused by the ordinary check. See
[runnable examples](../functions.md#runnable-examples).

The runner checks ordinary module code first, then checks each docstring
independently. A malformed example fails its case with the original checker
diagnostic and docstring line; other valid cases still run. Output mismatches
and traps also name the original prompt line. Every docstring uses the ordinary
forked trial, budgets, receipt keys and affected-test selection. Changing the
expected output invalidates its receipt.

Sidecar skip reasons, settings and dependency providers use the same displayed
`.example` name. A provider may replace an imported dependency, but cannot replace
the module defining that docstring. The transcript is always an assertion;
a sidecar expectation cannot override its expected output.

Directory discovery includes example-only modules. An imported module's
examples belong to the first root in sorted path order whose imports reach it;
an otherwise unreached example module becomes its own root. Directory scans
skip hidden directories, `build/` and configured `release.exclude` paths.

### Checking examples without running them

`selka check ENTRY.selka --examples` compiles every example of the modules the
entry loads exactly as `selka test` does (the probe, then the typed display, in
the function appended to the defining module) and runs none. A refused example is
reported where it is written: the diagnostic's location is the prompt line, and
the column is the byte inside it.

```console
$ selka check alts.selka --examples
alts.selka:256:28: error[E_OWN_MARKER]: a bare `text` only lends the local `text`, and the `mut` local `merged` needs its own value; write `own text` to give it, or `copy(text)` to keep both
      ...         merged = text
                             ^
  note: ownership rule B2
```

With `--diagnostics=json` the output is `diagnostic-v1` lines, so a refusal's
`fix` arrives as data. The edit is rewritten from the generated function back to
the docstring, and kept only when it lies wholly inside the text one `>>> ` or
`... ` line copies; an edit that touches anything the runner synthesized, spans
two lines, or would insert a line break, a backslash or a triple quote has no
`fix`, and the diagnostic carries a note saying so ([`selka fix`](fix.md#docstring-examples)
applies the kept ones). Warnings in examples are not reported, as in
`selka test`. A graph whose modules hold no `>>>` example is not checked, and the
entry's own bodies are checked only when some example has to be compiled, so run
plain `selka check` for the modules' own diagnostics.

A passing example is remembered under the cache directory, keyed on the
compiler, the project configuration, the function, and the exact bytes of its
module and of every module that module imports, so a second run, a sibling entry
that imports the same module and the final report of `selka fix` do not compile
it again. `--no-cache` turns that off. Exit status: 0 when every example
compiles, 1 when one is refused, 2 on a usage or host failure, 3 for an import
the project policy denies.

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
| `Entropy` | a SplitMix64 stream seeded with the first eight bytes, little-endian, of the SHA-256 of the test's qualified name, or with `N` under `selka test --seed N` |
| `Filesystem` | an empty in-memory filesystem whose root is `"."` |
| `Environment` | an environment with no names |
| `Network` | a network that refuses every connection with `network.denied_here()` |
| `Stop` | a stand-in no signal reaches, not yet requested; `process.request_stop` delivers the notice ([hearing a stop](../io.md#hearing-a-stop)) |

The test filesystem starts empty and its root is the path `"."`: `fs.listdir(".")`
lists it (`[]` before anything is written), and a file written there appears in
that listing. Reading the root itself reports `is a directory` rather than a grant
message; a nested `.` component such as `./a` is still denied.

No test is ever handed real authority: a `Host` parameter is never supplied,
and without cases-file arguments such a test fails as a property test whose
parameter cannot be generated (`a Host capability is never handed to a test`).
Every test gets its own stand-ins, so nothing one test writes is visible to
another, and each test's entropy stream is its own and stays the same from run
to run; renaming the test changes it, and `--seed N` pins every test's (a
directory run forwards it). The seed is part of a receipt's identity, so an
unchanged test that takes capabilities is reused like any other, and a
different seed executes it again.

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

```console
$ selka test app/main.selka
passed main::test_roll_stays_on_the_die
passed main::test_uptime_counts_whole_seconds
2 passed, 0 cached, 0 failed, 0 skipped
$ selka test app/main.selka
cached main::test_roll_stays_on_the_die
cached main::test_uptime_counts_whole_seconds
0 passed, 2 cached, 0 failed, 0 skipped
$ selka test app/main.selka --seed 7
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

Ordinary one-field records, including replacements for retired scalar domains,
are generated recursively like other records. Function values and `Host` are
never generated: a property test with a parameter whose type reaches
one fails, naming the parameter and the type, and so does one whose result is
not `bool` or `Result[bool, E]`. Types are spelled as source spells them (`int`, `main.Handler[]`, `main.Handler?`).
With a `test_callback(callback: func(int) -> int) -> bool`:

```console
$ selka test app/main.selka --filter test_callback
failed main::test_callback: property test parameter `callback: func(int) -> int` cannot be generated: a function value cannot be generated
0 passed, 0 cached, 1 failed, 0 skipped
```

### Preconditions and invariants

An input that breaks the test's own `@requires` is discarded, not failed:
`test_average_is_within_range` above never sees an empty list. A value the
runner generates was not built by a constructor, so every `test_` function also
checks, on entry, the [`@invariant`](../contracts.md#invariants) of every record
its parameters hold — in fields, list, set and dictionary elements,
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
$ selka test app/main.selka --filter test_picky
failed main::test_picky: too many discarded inputs: 1001 of 1001 generated inputs broke a precondition before 0 of 100 runs passed; most often test_picky requires `n == 12345`: a single value
  reproduce: selka test app/main.selka --filter 'main::test_picky' --seed 7017186523047142524
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
`None`. The report prints the minimal input as selka literals, one line per
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
$ selka test app/main.selka --filter test_budget --json | jq '.tests[0].property.failure.minimal'
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
$ selka test app/main.selka --filter test_reversing
passed main::test_reversing_twice_is_the_identity
1 passed, 0 cached, 0 failed, 0 skipped
$ selka test app/main.selka --filter test_reversing
cached main::test_reversing_twice_is_the_identity
0 passed, 1 cached, 0 failed, 0 skipped
$ selka test app/main.selka --filter test_reversing --property-runs 500
passed main::test_reversing_twice_is_the_identity
1 passed, 0 cached, 0 failed, 0 skipped
```


### Resumable indexed campaigns

Use `--property-policy indexed-v1` when you want to extend a property's budget or
resume after an interrupted command:

```console
$ selka test app/main.selka --filter test_reversing --seed 7 --property-policy indexed-v1 --property-runs 1000
$ selka test app/main.selka --filter test_reversing --seed 7 --property-policy indexed-v1 --property-runs 2000
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

The positional argument may be a directory instead of one entry. Every `.selka`
file beneath it is inventoried in sorted path order, in every folder but these: a
folder whose name begins with `.` (`.git`, `.zig-cache` and the default cache folder
`.selka-cache` among them), `build`, `zig-out` and `node_modules`, at any depth beneath the folder you name (the folder you
name is walked whatever it is called: `selka test build` runs the tests of a folder called `build`, and `selka test tools` leaves
`tools/build/` alone); the folder `--cache-dir` names; a folder or file listed in `release.exclude` of the
project's `selka.json` (`{"version": 2, "release": {"exclude": ["tmp/"]}}` leaves
`tmp/` out); and a link to a folder, which is not followed. Nothing else is
skipped: `tmp/`, `out/` and any scratch folder of yours are walked, so a scratch
`.selka` file there that declares `main` or a test is a root and runs, and one that
cannot be loaded is listed as failed. Keep scratch in a folder whose name begins with
`.`, or list it in `release.exclude`. A run that finds nothing to run says why on standard error, in one line that names the
folders it left alone that hold `.selka` sources (`note: no tests found under `tools`: `tools/build/` is left alone as a build-output
folder; name it to include it`); its standard output and exit status (3) are as before. `selka packages build DIR --command test` walks the same folders, by the same rule
([packages](packages.md#symbolic-links-repeated-warnings-and-interface-files)). A file that declares a top-level `main`, and
every `*_test.selka` file, is a root. A library that declares a test and that no
root's import closure reaches is a root as well, checked through the stub
`main` above, so a test file needs neither `main` nor the `*_test.selka` suffix; of
two such libraries where one imports the other, only the importer is a root. A
library imported by a root is not run on its own. Each test runs once in the run
and is listed once: a source that declares tests belongs to the first root, in
sorted path order, whose import closure holds it, and only that root runs its
tests. A root also runs every test its own [cases file](#per-entry-cases-files)
names, since a test's verdict under a root's cases is that root's own; such a test
can be listed once for each root that names it. A root is told only which
modules an earlier root owns (a child root with `--skip-test-modules FILE`, one
root-relative path a line), so a test no root claims is never left out. A single-file
run (`selka test FILE`) still runs every test its import closure declares, and a
pass is the test's, not its root's: a file run after a directory run, and a
directory run after a file run, rerun nothing the other ran unchanged.

With no `selka.json`, a file beneath the directory that cannot be loaded with its own folder as the import root, and can be
with the directory given as the root, takes the directory, as `selka check DIR` does for every file beneath it: in a folder
holding `rows.selka`, `rows_test.selka`, `rows/more.selka` and `rows/more_test.selka` (which imports `rows` and `rows.more`), the tests
run as `rows_test::test_size` and `rows.more_test::test_doubled`, the names a `selka.json` of `{"version": 1}` gives. A file
that loads with its own folder keeps it and its names (`one/helper_test.selka` importing `helper` from `one/` is `helper_test`),
so every recorded result of a tree that ran before is the one the run replays; a single-file run (`selka test rows/more_test.selka`)
takes the file's folder as before and refuses it (a directory run gives each child root that took the directory `--import-root DIR`). A file that cannot be loaded either way (a missing module, a syntax error) does
not stop the run: its diagnostic is printed and it is listed as `failed PATH: failed to check or build, so no tests ran`, and the
other entries run and report beside it. When such a file has no `selka.json` over it, the run ends with a note on standard error that
names the two ways to give it an import root: a `selka.json` of `{"version": 1}` in the folder its imports start from, or
`--import-root DIR` (relative to the working directory, or absolute) for the whole run. A `selka.json` of the directory itself that cannot be read does stop the
run, and its diagnostic names the file, the line and the reason.

Each root runs as `selka test ROOT --json` would, with the run's filter,
budgets, seed, property runs, `--release`/`--unoptimized`/`--optimize-debug`/`--debug-lean` (the default `-O0` build needs
no option), `--verify-facts`/`--no-facts`,
`--force`, `--affected --against REF` and `--link` inputs. Most roots run in the
directory run's own process (NEW-CORE-TEST-UNION-1). A headerless root that
declares no `main`, in a project whose configuration names no
import policy and no interface files, with no providers in its cases file, first
replays its recorded results; the roots of a project that miss are then checked
once, together, and each selects, builds and runs its tests from its share of that
check: the modules its own imports reach, which are what its own check would have
loaded. After an edit, a directory's roots used to check much the same import
graph once each. Every other root, and every root of a project whose shared check
fails, runs in a child process, whose own check reports its own diagnostics;
`SELKA_TEST_CHILDREN=1` gives every root a child. The shared check enters through a
generated module, `selka_directory_run`, that imports each root; like the entry a
directory check generates, it is no importer of a test file, so a test file keeps its
module's [private declarations](#private-declarations) in the shared check as in its own.

Roots share one worker budget (NEW-CORE-S4-TEST-1): `--jobs N`, else
`SELKA_JOBS`, else the CPU count capped by how many per-test memory ceilings
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

A passing test leaves a record in the incremental engine's store, under
`<cache>/engine-v1`, where `<cache>` is `--cache-dir DIR` or `.selka-cache/core` relative to the current directory. A later
run that asks for the same thing reports `cached` instead of building and executing the test. Failures, traps and timeouts
never become records, so they always run again. The engine is asked at two points: under the test's IR key before anything
is built, and under the digest of the test program once it is linked and before its first trial. A served pass is `cached`
with the `cache.reason` `engine-hit` (IR key), `engine-program-hit` (program) or, for a whole entry replayed without
checking it, `engine-report-hit`; an entry is replayed while every file its check read is as it was, a module source
counting as it was while its tokens are, so a comment edit or a line shift replays it too. A record holds the trial's work (`steps` and `peak_bytes`), so a cached result reports the
same numbers ([work per test](#work-per-test)).

A per-user tier of the records for ordinary project tests is shared across compatible worktrees by default, in
`$XDG_CACHE_HOME/selka/native-tests` (an absolute `XDG_CACHE_HOME`) or `~/.cache/selka/native-tests`. `--shared-cache-dir DIR` names
another root. `SELKA_TEST_SHARED_CACHE` supplies the same setting when the flag is absent; an empty environment value disables the tier.
The explicit flag wins, accepts `--shared-cache-dir=DIR`, and rejects an empty path. Directory runs forward the setting to their
workers. The tier does not change build or run caches.

Use a dedicated shared root, preferably outside the worktrees. The records live under `DIR/native-tests-v3/engine`;
`--cache-dir` still holds the private front-end, graph, executable and report caches. The tier holds the records of the work
directory under keys that name every path relative to the project root (RECEIPT-PATHS-1), so shared reuse requires the same
compiler or program, toolchain, execution settings and reachable program as a private hit would. A different checkout
location alone need not rerun an otherwise identical eligible test. A record is served only while it validates, so missing or
corrupt records are misses. A tree whose files differ from the tree that published first (two versions of one test or module) asks the
same key but reads different things: its record is another variant of the key, kept beside the first (up to four per key, told apart
by what they read) and served to the trees whose files match it, so the two do not displace each other. Only a record under the same key
that read the same things and gave a different result is a mismatch: the tier keeps its record, the
test runs, and the store appends one `mismatch engine …` line to `DIR/native-tests-v3/mismatches.log`. A record the engine
finds wrong (a check run of a served pass that now fails) is removed from the memo, the work directory and the tier. An
explicitly selected unusable store reports an error. With neither the flag nor the variable, a per-user default
(`~/.cache/selka/native-tests`) applies only when the compiler's `default_sharing` switch is on. A default store that cannot be
created is skipped quietly; one that exists but cannot be opened prints one warning that names the repair, and the run
continues without sharing. `--force` bypasses shared hits; `--no-cache` disables shared lookup and publication even when the
environment selects a store.

From the repository root, these two runs use separate private caches and the same shared records:

```bash
test_cache=$(mktemp -d)
trap 'rm -rf "$test_cache"' EXIT
selka test examples/testing/main.selka --cache-dir "$test_cache/private-a" --shared-cache-dir "$test_cache/shared"
selka test examples/testing/main.selka --cache-dir "$test_cache/private-b" --shared-cache-dir "$test_cache/shared"
```

Only the records of tests that are provably portable are shared: a test without live effects (no `Host` calls), whose
sources, assets, configuration and cases all lie inside the project root, under the legacy property policy, including property
tests and tests with capability stand-ins. A source extern, native links, provider overlays, docstring examples and, for a
result under the IR key, error traces and a callable digest, keep their records in the work directory. Configuration and
cases bytes, embedded values and literal strings remain part of the key. Fact-verification and leak-checked runs share under
their own keys; loader overrides run without records. The `native-tests-v3` namespace has its own format, separate from
developer verification and fuzz evidence stores. Native retention policies bound
its disk use with LRU eviction and protect storage operations with leases. The JSON test report remains `native-tests-v1`.

A test's IR key (NEW-CORE-S4-TEST-3, domains `core-test-settings-v3`, `core-test-keys-v2` and `core-test-ir-v4`) is made of:

- **the test's program** (NEW-CORE-S4-TEST-6, T1-SHIFT-1): the Core IR of the functions the
  test reaches, before any pass, hashed field by field without its source spans,
  and the entry's path relative to the project root. Passes and LLVM emission are
  pure functions of that IR, its spans and the settings below, so asking for a
  record emits no code. An edit to a function the test does not reach, a comment,
  a blank line or a function added above the ones it reaches keeps the key; an
  edit to a reached body, string, type or signature does not. Positions are left
  out because a pass cannot observe one: a position reaches a test's behaviour
  only through its debug lines, trap reports and error return traces, which a
  test reads only when it fails, and a failure is never recorded, so it runs
  again and reports the line it is on now. The program argument below, and the
  build caches, keep the positions;
- **the settings**: `--release`/`--unoptimized`/`--optimize-debug`/`--debug-lean`,
  `--no-facts`/`--verify-facts`, `--generic-vectors`, `--trap-frames`,
  `--counters`, the seed, the property runs, the step, frame, memory and time
  budgets, the `SELKA_CORE_LEAKCHECK` mode, the test's own cases-file entry and the
  cases file's bytes;
- **the paths, relative to the project root** (RECEIPT-PATHS-1): the entry (a
  single-file entry by its basename), the cases file, `selka.json` and its
  import policy. The same project checked out at two absolute paths keys alike,
  and the path a failing test's trap report prints is unchanged;
- **the compiler, runtime and toolchain identity**, including the `zig` the run
  uses and the cache planner, and the bytes of `selka.json` and its import
  policy. The compiler identity stays here because predicting "same IR, same
  program" is sound only while lowering, passes, emission and the runtime are
  unchanged;
- **the environment variables that can change an outcome**
  (NEW-CORE-S4-TEST-5): the keyed class of the
  environment identity contract in
  `src/environment_identity.zon` (ENV-IDENTITY-1). That is every `MYL_`
  and `SELKA_` variable except the placement ones (store locations such
  as `SELKA_CORE_RUNTIME_CACHE` and `SELKA_TEST_SHARED_CACHE`, job counts such as
  `SELKA_JOBS`, `SELKA_TEST_ISOLATE`, `SELKA_TEST_CHILDREN` and the telemetry
  directories), the C compiler and Zig toolchain inputs (`CPATH`,
  `C_INCLUDE_PATH`, `LIBRARY_PATH`, `ZIG`, `ZIG_LIB_DIR`, `SOURCE_DATE_EPOCH` and
  the like) and `LD_*`. The contract's host class (`PYTHON*`, the locale and
  `TZ`) is keyed only by host tooling, never by a record. A shell's `_` or
  `OLDPWD`, a terminal's variables or a wrapper such as `time` leave records
  valid.

The program argument keys what actually ran instead of how it was produced (EXEC-RECEIPT-1):

- **the linked program's exact key** (`driver.Outcome.program_key`): the link
  sanitizer, object format, optimize level, target and CPU, the toolchain digest,
  the digest of every linked object in order (the runtime object and `--link`
  objects included), `-lm` and the linker environment. It names no path and no
  compiler identity, but the objects' bytes are in it. A test program names its
  entry by basename in its `source_filename` and debug information
  (ENTRY-PATH-1), so an entry checked without a project root (no `selka.json`,
  as in `tests/lang`) keys alike in two checkouts at both points;
- **the settings** listed above, the test's name, the cases, configuration and
  policy bytes, and the keyed environment.

What decides the verdict beyond the program, the code that forks trials, applies budgets and judges outcomes, is the code the
engine's `test-exec` kind covers (`selka engine closure test-exec`): an edit to it retires every record of the kind, and an
edit to a file outside it (a comment in `src/parser.zig`, say) leaves the records of a program whose bytes it does not
change valid. After such a compiler edit the IR key misses, the program is lowered, emitted and linked from cached objects, and
the engine answers the test under the program's digest without a trial. `--json` reports the program argument's work as
`"exec_receipts": {"hits": N, "saves": N}` (hits are tests it answered, saves are passes the run recorded under a program; a
test's `cache.execution_key` names the program), and the text summary appends `, N exec-receipt hits` when there are any. The
report stays `native-tests-v1`. The program argument needs no cache planner.

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
`SELKA_TEST_KEYS=per-test` keys each test from its own lowering instead, as the
check the derived keys are tested against.

The Selka cache planner retains a complete dependency graph and uses reverse
dependencies to reuse unaffected test keys (NEW-CORE-TEST-GRAPH-1,
SELFHOST-CACHE-PLAN-2). Lost or corrupt metadata causes recomputation. These
records describe key derivation; passing records still authorize test reuse.
Global semantic checks continue to run after source changes.

`--json` includes current key-derivation work at `cache.work` on the first test
of each provider group. Its `scope` identifies that group. The report counts
fresh/reused canonical facts, the groups whose one record served their members' facts (`producer.facts.groups`), raw bodies restored, the functions keyed by the
engine's `module-check` part (`producer.lowering.by_part`), graph and closure work, and
planner request/reply bytes and process starts. `nanoseconds` contains monotonic
wall intervals; `storage` counts packed block reads and decoding, excluding
direct journal reads and ordinary cache metadata. `rule` is the entry's, on its
first group: `evaluations` counts runs of the shared tier's portability rule
(one for each record the tier is asked about), `paths` the paths those runs
resolved to real paths (the entry, its configuration and every source of the
checked program, for each run), and `proofs` the walks of a test's call tree by
the receipt proof, wherever the runner or the rule made one. A whole-report replay omits
historic work. `SELKA_CACHE_PLAN_MODE=shadow` independently lowers and hashes
the complete graph to check derived keys; `reference` uses the uncached Zig
path. These modes change the execution identity and are qualification tools.

Output and capabilities do not prevent reuse. A test that prints through a
`Stream` parameter is reused like any other, because its output is discarded on
a pass; a test that takes a `Clock`, `Entropy`, `Filesystem`, `Environment` or
`Network` gets a [deterministic stand-in](#capability-parameters) whose seed the
record binds. So does a callback: a test whose code stores function values in a
record and calls them through a field or a local (an evaluator with its recursion
hooks, a sort with a comparison function) is keyed by the functions it can reach,
which include every function value its call tree creates. A test is run again on
every invocation only when its call tree declares an `extern func`, has a host function, reaches a `Host`
capability, or calls a callback in a program that also asks for `function_digest`; `--json` then gives
the cache reason `live-effects: ` and names the function and the finding.

A run whose every selected test passed or replayed also records the whole
report, with the digest of every source, embedded file, cases file and
configuration file it loaded (the files a stored report depends on are read again
when it is asked for). An unchanged rerun replays that report without checking the
project (`engine-report-hit`); any changed byte falls back to the ordinary run,
which still serves each test's own record. A report is named by the settings, the
root, the entry, the filter and the modules a directory run gave the entry, and is
served only to that entry run in the same way (a root left nothing to skip names
its report as a file run of it does). A project
with `"interface_files": true` in `selka.json` never replays a whole report,
so its interface files are checked on every run.

Fact verification and leak checking are keyed modes, not refusals
(EXEC-RECEIPT-4): `--verify-facts` and a non-zero `SELKA_CORE_LEAKCHECK` enter the
settings of both arguments, so a second identical fact-verification or leak-checked
run is `cached`, and neither mode ever serves a plain run's records or each
other's. A gate that must observe both checks fresh passes `--force`.

What runs every test again:

- `--force` executes every selected test; a pass is still recorded;
- a run with `--link FILE.c` never asks for records, because the runner does not
  yet capture the headers a C input includes;
- a run with a non-empty `LD_*` variable never asks for records;
- `--no-cache` builds and runs through an empty private cache under the cache
  directory, removed when the command ends (NEW-CORE-S5-NO-CACHE-1): nothing is
  read from or published to the record, report, program, front-end, stage or
  shared test-receipt caches. The per-user object store of compiled units is
  still used (`build`, `run` and `run-project` take the same switch and skip the
  same stores: [native builds](native-build.md#--verify-cache-and---no-cache));
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

## Affected selection

`selka test --affected --against REF` narrows a run to the tests that reach a
declaration whose own source lines changed since the git revision `REF`
(NEW-CORE-S5-AFFECTED-1). It reads the changed lines of every `.selka` file from
one `git diff` under the project root (plus `git ls-files --others` for files
not yet added, which count as changed throughout) and maps each changed line
onto the top-level declaration that owns it, by indentation: a line inside a
function or constant changes that declaration, and a line anywhere else — an
import or a record — changes every declaration of the
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

To fake a capability, prefer [capability parameters](#capability-parameters) and
the deterministic stand-ins: a function that takes a `Clock` is tested by
passing it a simulated one, with no fixture file. Provider fixtures replace a
dependency's source wholesale, for a collaborator whose behaviour the test must
pin (NEW-CORE-S4-TEST-4).

A case may carry a `providers` object mapping existing dependency `.selka` paths,
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
$ selka test app/main.selka --filter test_stamp
failed main::test_stamp: property test parameter `host: Host` cannot be generated: a Host capability is never handed to a test
0 passed, 0 cached, 1 failed, 0 skipped
$ selka test app/uptime.selka
passed uptime::test_uptime_counts_whole_seconds
1 passed, 0 cached, 0 failed, 0 skipped
```

## Test files and their modules

### Private declarations

A module's test file may call the module's private declarations: a module named
`<name>_test` that no other module imports sees every non-`public` function,
type and constant of module `<name>`, so a helper need not become `public` just
to be tested. Any other importer, including another module's test file, still
gets `E_PRIVATE_SYMBOL`. The entries `selka check DIR` and a directory test run
generate to load a project's modules together import a test file only to load it, so
they do not count as importers. Whether the access holds depends on which modules
import the test file, so a test file's checked bodies and its engine records are kept
apart by it: a body checked with the access is never reused where another module
imports the test file, and that check refuses the private name as a fresh one does.

In `scanner.selka`:

```selka
# doc: project scanner-private
# doc: file scanner.selka
# doc: check
func is_digit(c: str) -> bool:
    return c in "0123456789"
```

In `scanner_test.selka`:

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

An entry's cases file sits beside it as `<stem>.cases.json`: `scaled_test.selka`
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
$ selka test .
passed scaled_test::test_scaled
cached scanner_test::test_is_digit
1 passed, 1 cached, 0 failed, 0 skipped
```

## Dropped flags

The runner on the compiler's core dropped the old runner's features below
(S5-D6). Each flag is refused with status 2 and a one-line reason.

| Flag | Replacement |
| --- | --- |
| `--diagnostics` | `selka check FILE.selka --diagnostics=json` reports the same diagnostics |
| `--report`, `--timings`, `--timings=json`, `--explain-invalidation` | `--json` reports each test, with `cached` for a replayed receipt; `selka run FILE.selka --timings` times one program |
| `--friction-log` | `selka check FILE.selka --friction-log=PATH` |
| `--pure-skip` | none: a failure is never replayed |
| `--max-calls` | `--max-steps` and `--max-frames` |
| `--bench`, `--bench-only`, `--bench-output`, `--bench-baseline`, `--bench-policy`, `--bench-profile`, `--bench-warmup`, `--bench-batches`, `--bench-batch-ms`, `--bench-timeout-ms`, and `selka bench-promote` | none: `bench_` functions, baselines and policies were dropped; time a built program instead |
| `--gc-stress`, `--gc-runtime`, `--rc-runtime`, `--legacy-sharing`, `--value-semantics` | none: checked ownership with value semantics is the only memory model |
| `--library`, `--provider`, `--link-library`, `--library-path` | `extern func` with `--link FILE.c` |

`--whole-program` is accepted and ignored, and `--qbe PATH` is ignored.
