# mylang — working rules

A Python-syntax statically checked language. Zig compiler (`src/`) with a QBE native
backend as its only runtime (amd64 Linux only) — `mylang run` builds the program and
executes it. Bytecode survives only as the internal IR QBE consumes; there is no
interpreter. QBE is vendored under `vendor/qbe` and built by
`zig build` into `zig-out/bin/qbe`. Zig is pinned by `.zigversion`; the build panics on
any other toolchain.

## Build

- `zig build` — compiles **and installs** `zig-out/bin/{mylang,mylang-io,qbe,board-trial,schematic-svg}`.
  Run this after any `src/` change before using `zig-out/bin/mylang`.
- `zig build test` — runs the gate. It **does not install**, so `zig-out/bin/mylang` stays
  stale unless you also ran `zig build`.
- `zig build test-compile` — type-checks every Zig test root without running anything.
- **Building and using mylang needs no Python.** `zig build` (the install graph) and
  every command of the installed compiler run none; `USE-WITHOUT-PYTHON-1` in
  `test/integration.zig` runs the user commands under an empty `PATH`. Python is
  fine in `zig build test` drivers, developer scripts, `bench/`, `velocity/` and
  `experiments/`. `--release` is no exception: the LLVM backend is built into the
  compiler (`src/qbe_build_llvm*.zig`), and the retired Python adapter under
  `experiments/llvm-backend/` is only an equivalence oracle. Never wire a Python
  step into the install graph or spawn one from `src/`.
- Use `zig build -Doptimize=ReleaseFast --prefix /path/to/install` for a compiler
  installation used by application agents, or to time the compiler itself. Default
  `zig build` produces a Debug compiler; cached guest tests still pay its parsing,
  JSON and dependency-planning costs. This setting optimizes the compiler itself,
  independently of the guest program's backend and optimization flags, so guest
  benchmarks do not need it (see "Measuring guest programs"). Add
  `-Dcompiler-only=true` when you only need `mylang`: it skips installing
  `board-trial`, `schematic-svg` and `mylang-io`, each of which re-optimizes the
  whole compiler.
- Sharing the machine with other agents: run `zig build`, focused tests and gates
  through `scripts/build-slot.sh build|gate …`. It admits a job only when a slot
  and enough memory are free, and keeps the timing CPUs (`MYLANG_TIMING_CPUS`,
  default `2,3,10,11`) free of builds. Give every worktree its own
  `ZIG_LOCAL_CACHE_DIR` and set `TMPDIR` on disk. See
  `docs/tooling/many-agents.md`.
- Never point two source trees (a base checkout and a worktree) at one
  `ZIG_LOCAL_CACHE_DIR`. Zig reuses the cached configure phase across them, and its
  absolute paths name the first tree. The build now fails with "this build
  configuration belongs to …" instead of quietly bundling the wrong runtime. See
  `docs/tooling/native-build.md#where-the-content-hash-comes-from`.

## Measuring guest programs

Time guest programs with the Debug `zig-out/bin/mylang` from a plain `zig build`
(about 15 s after a change). A Debug and a ReleaseFast compiler emit
byte-identical guest binaries. The compiler's optimization mode changes only how
fast the compiler runs, never the program it emits. `zig build bench-parity`,
`bench/parity/bench_parity.py` and `experiments/perf-parity-plan-20260922/bench.py`
all default to `zig-out/bin/mylang`. Build a ReleaseFast compiler
(`-Doptimize=ReleaseFast -Dcompiler-only=true --prefix …`, about 3 to 5 minutes)
only to time the compiler itself or to hand a compiler to other agents.
`bench_parity.py same-binaries --other PATH` re-checks the identity when in doubt.

## Fast loops (use these while iterating)

- `python3 scripts/affected_tests.py` — **the inner loop for a change.** It diffs
  against the merge-base with `main` (plus staged, unstaged and untracked files; `--base
  REF` to choose), maps each changed file to the tests that most directly cover it and
  runs only those: `src/foo.zig` → the Zig tests in and beside it (`foo_test.zig`, test
  files importing it), tests carrying a `spec:` tag, diagnostic code or function the
  diff touches, plus a guest smoke; `src/*.c` → `test-native-memory`, `test-native-heap`
  and the guest areas using that runtime part; `tests/lang/x.my` → `mylang test` on it;
  a doc page → its doctest and `doc-coverage`; the retired LLVM adapter (the
  translator's equivalence oracle) → `test-llvm-adapter` plus an LLVM guest smoke; a driver under `tests/` → its build step. It prints what it
  selected and why (`--dry-run` stops there), runs Zig selections as sharded
  processes, and says on every run that it is **not the gate**. Measured 2026-09-23
  on a loaded machine: 1–2 s for a `.my` or doc edit, 14 s for `src/sema.zig`, 25 s
  for a `src/native_*.c`, 57 s for `src/qbe.zig` (its 108 Zig tests). Run it through
  the build slot like any build. The full gate below is still required before you
  finish.
- `zig build test-units -Dtest-filter=SUBSTRING` — runs only `src/root_test.zig` tests
  whose name contains SUBSTRING. `-Dtest-filter=arena` is 34 tests in about 1.5 s; the whole
  root is 1113 tests in about 73 s (measured warm 2026-09-18; `zig build test` shards it). `zig build test-cli -Dtest-filter=…` does the same for
  `test/integration.zig`. Neither runs Python drivers, Guardian, or the install graph:
  they depend only on their test binary plus unattached copies of `qbe` and the compiler. The filter also
  applies to `zig build test` and `test-compile`. An explicitly empty
  `-Dtest-filter=` is rejected at configure time, and a filter that names nothing fails
  rather than reporting green, so filter one root at a time. These two steps are never
  sharded, so their selected-test count and verdict are one process's.
- `python3 scripts/focused_test.py units arena` — the supported wrapper over the same
  targets (`units`, `cli`, `golden`). It rejects a missing/empty/whitespace filter before
  invoking Zig, prints the runner's selected-test count and PASS/FAIL verdict, saves the
  full output under `.mylang-cache/focused-tests/`, reports wall time, and exits with the
  wrapped command's status. Use `python3 scripts/focused_test.py full` for the explicit
  whole-suite request; it refuses a filter.
- `zig-out/bin/mylang test <entry.my|dir> --filter SUBSTRING` — guest (`.my`) tests,
  each built and run as its own native process.
  A bare substring matches anywhere in the qualified name; a pattern containing
  `*`, `?` or `[` is a glob. A directory runs every `.my` entry under it in parallel.
  Results are reused per test, so an unchanged rerun is near-free. A first run pays
  for the native build; the object cache makes later runs cheap.
- `zig build test-docs` — executes every fenced documentation example.
- `zig-out/bin/mylang doc-coverage .` — checks the feature/doc contract (below).
- Targeted Python drivers: `zig build test-qbe-build`, `test-native-tests`, `test-byte-io`, …
  (see `zig build -l`).

## Where tests live

Language behaviour is tested in the language: a `public def test_*() -> bool` in
`tests/lang/<area>.my`, run by `mylang test` (`zig build test-lang`, which runs the
suite under the default RC runtime and again under `--gc-runtime --gc-stress`). Diagnostics,
traps, host fixtures, caches, formatting and allocation-failure tests are Zig tests in
`src/root_test.zig`; CLI behaviour is `test/integration.zig`. Write new guest-behaviour
tests on the mylang side; the rule, the inner-loop costs and the backlog of Zig tests
still to move are in `docs/tooling/test-layout.md`.

## Full gate (run before finishing)

```
zig build test --summary all
zig build test-qbe --summary all
zig build test-qbe-build --summary all
zig build fmt-check
```

`zig build test` also runs `mylang doc-coverage .` and `mylang doctest .`.

Test verdicts are cached like build outputs. A test shard, a Python driver or the
doctest re-runs only when its test binary, the compiler or `qbe` it runs, its command,
one of the environment variables it depends on (`PATH`, `HOME`, `TMPDIR`, `MYLANG_*`,
…), or one of the repository files it reads changes; those files are declared per step in
`build_test_inputs.zig`, and `zig build test` fails (`test-inputs-coverage`) when a
test names a repository path its step does not declare. An unchanged `zig build test`
takes seconds, and a `.my` or doc edit re-runs only what reads it. A cached step
prints no test count, so the `Build Summary` total counts only what ran:
`-Dtest-rerun=true` re-runs every test step (full counts, or to rule out a stale
verdict you suspect). When a test starts reading a new fixture, declare it in
`build_test_inputs.zig`. Test steps always run in the live environment of the
`zig build` that runs them: never call `Step.Run.setEnvironmentVariable` in
`build.zig` (a cached configuration freezes the whole environment it copies, and
the build refuses to configure); pass variables through `withTools`.

`zig build test` splits its two slow Zig roots across processes: `src/root_test.zig`
into `-Dtest-shards=N` shards (default 12) and `test/integration.zig` into `N/2`, each
one run of the same test binary under Guardian's `--guardian-shard=K/N` with its own
`max_rss`, so the shards run concurrently and print one `test wall` and one verdict
each. They partition the root — every test runs exactly once, and the shards' selected
counts sum to the unsharded count. `-Dtest-shards=1` restores one process per root, and
`-Dtest-filter=…` falls back to it automatically. See `docs/tooling/runtime-budgets.md`.

## Memory ceilings (why a runaway guest no longer kills the machine)

Every process that runs guest code runs under a byte ceiling: the managed heap
traps `R_MEMORY_BUDGET` at it and the runtime backs it with `RLIMIT_AS` at the
budget plus 256 MiB. `MYLANG_MEMORY_LIMIT` carries it (bytes, `K`/`M`/`G`
suffixes); `--max-memory=BYTES` on `run`, `build --run` and `test` outranks it;
the defaults are 512 MiB per test child and 4 GiB for a single run. The compiler
caps itself at 8 GiB (`MYLANG_HOST_MEMORY_LIMIT`), `mylang test <dir>` sizes its
fan-out from `MemAvailable` as well as cores (`--jobs N`, `MYLANG_JOBS`), and
every build step declares `max_rss`, so `zig build --maxrss N` bounds the whole
gate's concurrency. See `docs/tooling/runtime-budgets.md`.

## Guardian rules that actually bite

Guardian runs **inside** `zig build test` and blocks; there are no baselines.

- **Spec tag per behavioral change.** Every added behavioral line under `src/` needs a
  test carrying `// spec: TAG` and a matching `- [TAG] …` bullet in `SPEC.md`.
- **Structs: at most 7 fields. Functions: at most 6 parameters.** Group into a struct.
- **`///` doc comment on every `pub` declaration** (fn, type, const). Say what it does,
  not that it exists.
- **No `@import` cycles**, and every new `src/*.zig` file must be reachable from a root
  listed in `guardian.toml` (`orphan_files.roots`, `test_reachability.roots`).
- **No RNG** outside the sanctioned module; no wall clock, no hardcoded absolute paths.
- **Type-size ratchet must not grow.** If you legitimately need a wider struct:
  `../guardian-zig/zig-out/bin/guardian-check accept type-size .` and commit
  `.guardian/baselines/type-size.txt`.
- **Tests need at least one `expect*` assertion** and **no `if`/`while`/`switch` or extra
  `for` at the top level of a test body**. Write straight-line assertions.

## Breaking changes land with their `mylang fix` migration

A change that turns previously accepted code into a diagnostic must carry the
repair as a structured `fix` on that diagnostic (`diagnostic.Fix`, rendered as
`diagnostic-v1` `fix.edits`) wherever the edit is certain, so `mylang fix` moves
a project across it with no hand edits — no per-change script under `scripts/`.
Add a pre-change corpus under `test/fixtures/fix-migration/` with a test beside
`FIX-MIGRATION-1` (`test/fix_cli_test.zig`) proving `mylang fix` migrates it to a
clean check. See `docs/tooling/fix.md`.

## Merging `SPEC.md` (run once per clone)

```
sh scripts/setup-git.sh
```

It registers the `spec-bullets` merge driver that `.gitattributes` names for `SPEC.md`
(`scripts/merge_spec.py`) in the clone's shared `.git/config`, so every worktree gets it.
The driver merges bullets by tag: both sides' appends to one section are kept (ours,
then theirs), a bullet amended on one side keeps only the new text, and only a tag both
sides changed differently, or prose both sides edited, is left as a conflict. Without the
setup git ignores the attribute and falls back to its plain line merge, where parallel
appends conflict and a hand union can repeat an amended tag (Guardian rejects that).
Tests: `zig build test-spec-merge`.

## Documentation gate

Every feature slug in `src/features.json` needs `{kind, summary, doc}` and the `doc`
anchor must resolve to a real section containing a runnable example. Language features
use a ```mylang block; `kind: "tooling"` features may use a ```bash or ```console block.
`mylang doc-coverage .` tells you exactly which slug is missing what.

## Where the language differs from Python

- **Locals are function-scoped, like Python.** An assignment to a name anywhere in the
  body is one binding, in scope from its first assignment to the end of the function, and
  a nested block reassigns the same binding. Reading a name on a path that may not have
  assigned it yet is a static `E_UNBOUND`; a name never assigned is `E_UNKNOWN_NAME`.
  Because every `while`, ordinary `for`, `range`, `reversed` and `zip` loop may execute
  zero times, an assignment made only in the loop body does not make the name definitely
  assigned after the loop; predeclare it before the loop. The `for` loop variable and
  `match` payload binding stay scoped to their block. A managed value first assigned
  inside `with arena()` is confined: reading it after the block is `E_ARENA_ESCAPE`, not a
  dangling read.
- **`range()` is a comprehension source, just like in a `for` loop.** `[x for x in
  range(10)]` and `[x for x in range(a, b)]` build a list of the range's integer values;
  comprehending over a list, string or dictionary works too.
- **`def main() -> int`'s value is the process exit status**, truncated to the low 8
  bits (POSIX `status = value & 0xFF`), for `mylang run`, `run-project` and a native
  executable — the way Python and Go return an exit code. `--print-result` still prints
  the value to stdout and is orthogonal to the status. A runtime trap outranks the
  return and exits 1; source/check errors exit 1, usage/host failures exit 2.
- **No tuples. No methods on classes. No closures.** Records are values; functions are
  top-level and take their state as parameters.
- **Managed collections are values.** Assignment, argument passing, stores and
  returns preserve independent lists, dictionaries, sets and byte buffers. A
  helper changes the caller's value through a `mut` parameter and a marked
  argument. Use records and recursive unions for finite trees, and pool handles
  for graph identity. `class` and builtin `Cell` are rejected under the default
  value model; `--legacy-sharing` temporarily enables the old rules during
  migration. See `docs/value-semantics.md`.
- **Memory is reference counted by default.** Values are released when their last
  owner goes away (copy-on-write, no collector). `--gc-runtime` (or
  `MYLANG_RUNTIME=gc-v1`) opts out to the tracing GC, and `--gc-stress` selects
  it too; `--gc-stress` next to `--rc-runtime` is a usage error, and an RC-built
  binary refuses `MYLANG_OPTIONS=--gc-stress`. `--legacy-sharing` always uses GC.
  See `docs/managed-memory.md#runtime-selection`.
- **File access needs a capability parameter on the entry point.** Write
  `def main(fs: Filesystem) -> int` and thread `fs` through; there is no ambient
  filesystem. `Network`, `Clock`, `Entropy` and `Environment` work the same way.
- **Printing goes through a `Stream` parameter.** Write `def main(out: Stream) -> int`
  and call `out.print(...)`; `err: Stream` is standard error. The runtime supplies both
  streams, so printing itself needs no host grant. `stream.print` contributes the
  `output` effect, which an explicit `noio` bound withholds — write `effects(output)` on
  any function in the chain that prints. Bare `print(...)` is rejected with
  `E_OUTPUT_CAPABILITY`. See `docs/io.md`.
- **`mylang run` grants every capability** unless you pass `--restrict` — it builds the
  program natively and runs it in a child process. A binary from `mylang build` grants
  every capability too and hands `main` its argv unchanged; runtime options such as
  `--restrict`, `--allow-*` and `--gc-stress` (for a `--gc-runtime` build) go in the
  `MYLANG_OPTIONS` environment variable instead (`MYLANG_OPTIONS=--restrict ./prog`).
- Integers have fixed width, conditions must be `bool`, lists are homogeneous, ranges
  take one or two arguments, and slices have no step.

Details: `docs/python-syntax.md`, `docs/io.md`, `docs/effects.md`, `docs/statements.md`.

## Native builds

`mylang build prog.my -o prog` drives QBE, the assembler and the linker directly — no
Python. QBE is the backend of every `build`, `run` and `test` unless `--release`
asks for the optimized one (`--mode ReleaseFast --backend llvm --llvm-opt 3 --lto`,
like `cargo build --release`): use it for a binary you ship or time, not in the edit
loop, since each rebuild pays the LTO link. A harness that measures the optimized
build must say so (`--backend llvm --llvm-opt 3 --lto` works on older compilers
too). Objects are content-addressed under `.mylang-cache/qbe` (override with
`--cache-dir`); the bundled runtime is published once per content hash and linked as one
static archive with `--gc-sections`, so a program that never prints does not carry the
printing runtime. `--report` prints a JSON timing/reuse breakdown. See
`docs/tooling/native-build.md` and `docs/tooling/guest-tests.md`.
