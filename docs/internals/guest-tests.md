# Guest tests: how it works

What the [guest tests guide](../tooling/guest-tests.md) leaves out: how the runner, its caches and its keys work, and the
measurements behind them. Each section keeps the heading of the guide's section it belongs to.

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
[batches and receipts](../tooling/guest-tests.md#batches-and-receipts) describes.
`SELKA_TEST_ISOLATE=1` gives every test its own process again, as the check
batching is tested against.

A trial's work is written beside the batch's response file, one record per trial
row (`<response>.work.<row>`), so batching needs no extra process and no reset:
each forked trial starts its own record at its own step and byte ceilings
([work per test](../tooling/guest-tests.md#work-per-test)). `SELKA_TEST_ISOLATE=1` runs the same trials
one process at a time and reports the same counts.

## Work per test

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
([how work grows](../tooling/guest-tests.md#how-work-grows)).

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

### Checking examples without running them

A passing example is remembered under the cache directory, keyed on the
compiler, the project configuration, the function, and the exact bytes of its
module and of every module that module imports, so a second run, a sibling entry
that imports the same module and the final report of `selka fix` do not compile

## Property tests

How the generator, the shrinker and the indexed campaign store work.

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

### Resumable indexed campaigns

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
module's [private declarations](../tooling/guest-tests.md#private-declarations) in the shared check as in its own.

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

## Reusing unaffected results

A passing test leaves a record in the incremental engine's store, under
`<cache>/engine-v1`, where `<cache>` is `--cache-dir DIR` or `.selka-cache/core` relative to the current directory. A later
run that asks for the same thing reports `cached` instead of building and executing the test. Failures, traps and timeouts
never become records, so they always run again. The engine is asked at two points: under the test's IR key before anything
is built, and under the digest of the test program once it is linked and before its first trial. A served pass is `cached`
with the `cache.reason` `engine-hit` (IR key), `engine-program-hit` (program) or, for a whole entry replayed without
checking it, `engine-report-hit`; an entry is replayed while every file its check read is as it was, a module source
counting as it was while its tokens are, so a comment edit or a line shift replays it too. A record holds the trial's work (`steps` and `peak_bytes`), so a cached result reports the
same numbers ([work per test](../tooling/guest-tests.md#work-per-test)).

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
