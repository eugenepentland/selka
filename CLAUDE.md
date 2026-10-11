# mylang — working rules

A statically checked language with Python-inspired indentation and explicit declarations. Zig compiler (`src/`) whose back end is
the new core (`src/core/`): the checked program becomes Core IR, then LLVM text, which
the pinned Zig toolchain's clang (`zig cc`) compiles and links with the core C runtime
(`src/core/runtime/`), amd64 Linux only. `mylang run` builds the program and executes
it. There is no interpreter, no QBE, no bytecode and no garbage collector: memory is
one-count reference counting with copy-on-write. Zig is pinned by `.zigversion`; the
build panics on any other toolchain.

## Build

- `zig build` — compiles **and installs** `zig-out/bin/mylang`, the one compiler
  (front end and new core; `mylang-core` merged into it in S5). Run this after any
  `src/` change before using `zig-out/bin/mylang`.
- `zig build test` — runs the full gate. Focused `test-core`, `test-units` and
  `test-cli` **do not install**. After a `src/` change, run plain `zig build` before
  using `zig-out/bin/mylang` directly.
- `zig build test-compile` — type-checks every Zig test root without running anything.
- **Building and using mylang needs no Python.** `zig build` (the install graph) and
  every command of the installed compiler run none; `USE-WITHOUT-PYTHON-1` in
  `test/integration.zig` runs the user commands under an empty `PATH`. Python is
  fine in `zig build test` drivers, developer scripts, `bench/`, `velocity/` and
  `experiments/`. Never wire a Python step into the install graph or spawn one from
  `src/`.
- Use `zig build -Doptimize=ReleaseFast --prefix /path/to/install` for a compiler
  installation used by application agents, or to time the compiler itself. Default
  `zig build` produces a Debug compiler: it parses, checks and plans more slowly, but
  the compiler's optimization mode does not choose the guest's build mode
  (`--release` does). `-Dcompiler-only=true` is accepted for older scripts and
  changes nothing.
- Sharing the machine with other agents: run `zig build`, focused tests and gates
  through `scripts/build-slot.sh build|gate …`. It admits a job only when a slot
  and enough memory are free, and keeps the timing CPUs (`MYLANG_TIMING_CPUS`,
  default `2,3,10,11`) free of builds. Give every worktree its own
  `ZIG_LOCAL_CACHE_DIR` and set `TMPDIR` on disk (`/tmp` has a per-user quota; a
  full quota makes test processes exit 70). See `docs/tooling/many-agents.md`.
- Never point two source trees (a base checkout and a worktree) at one
  `ZIG_LOCAL_CACHE_DIR`. Zig reuses the cached configure phase across them, and its
  absolute paths name the first tree.

## Measuring guest programs

Time a guest with a `--release` build: `mylang build prog.my -o prog --release`
emits the whole program as one optimized LLVM unit, while a plain build is the
debug edit-loop build (one unit per module, no optimizing passes). Time the
binary, not `mylang run`, or use `mylang run prog.my --release --timings`
(`timings: native_ns=N`, the build excluded). Build a ReleaseFast compiler only
to time the compiler itself or to hand a compiler to other agents. Timing runs
go on the reserved timing CPUs, never beside a gate.

## Fast loops (use these while iterating)

- `zig build test-core -Dtest-filter=SUBSTRING` — the new core's tests
  (`src/core/root_test.zig`: unit tests plus the end-to-end slice under
  `test/core`) whose name contains SUBSTRING, in one process; unfiltered it runs
  in `-Dcore-shards=N` shards (default 8).
- `zig build test-units -Dtest-filter=SUBSTRING` — `src/root_test.zig` (front end,
  diagnostics, tooling, and programs run through `native_execute`, which builds
  them with `mylang run`). `zig build test-cli -Dtest-filter=…` does the same for
  `test/integration.zig`. Neither runs Python drivers, Guardian, or the install
  graph. The filter also applies to `zig build test` and `test-compile`. An
  explicitly empty `-Dtest-filter=` is rejected at configure time, and a filter
  that names nothing fails rather than reporting green, so filter one root at a
  time. These two steps are never sharded.
- `python3 scripts/focused_test.py units fmt` — the supported wrapper over the
  same targets (`units`, `cli`, `golden`). It rejects an empty filter, prints the
  selected-test count and verdict, saves the full output under
  `.mylang-cache/focused-tests/` and exits with the wrapped command's status.
- `python3 scripts/affected_tests.py` — diffs against the merge-base with `main`
  (`--base REF` to choose), maps each changed file to the tests that most directly
  cover it and runs only those; `--dry-run` prints the selection. It says on every
  run that it is **not the gate**. Run it through the build slot.
- `zig-out/bin/mylang test <entry.my|dir> --filter SUBSTRING` — guest (`.my`)
  tests, each built by the new core and run in its own forked trial. A bare
  substring matches anywhere in the qualified name; `*`, `?` or `[` make it a glob.
  A directory runs every entry under it in parallel (`--jobs N`, `MYLANG_JOBS`).
  Results are reused per test (receipts keyed by the test's Core IR), so an
  unchanged rerun is near-free; `--force` reruns. The gate's second run is
  `--release --verify-facts` with `MYL_CORE_LEAKCHECK=1`.
- `zig build test-lang` — `tests/lang` and `tests/value_semantics` through
  `mylang test`, at debug and at release with the fact and leak checks.
- `zig build test-docs` — executes every fenced documentation example.
- `zig-out/bin/mylang doc-coverage .` — checks the feature/doc contract (below).
- Developer commands: `mylang dump-ir FILE.my [--facts]`, `mylang dump-typed
  FILE.my`, `mylang coverage FILE.my`, and `mylang build … --stats`,
  `--emit-llvm PATH`, `--cache-report`, `--verify-cache`.

## Where tests live

Language behaviour is tested in the language: a `public func test_*() -> bool` in
`tests/lang/<area>.my`, run by `mylang test` (`zig build test-lang`). The new core's
own tests (IR, passes, emission, driver, caches, test runner) are Zig tests under
`src/core/` with fixtures in `test/core`. Diagnostics, traps, host fixtures, caches,
formatting and allocation-failure tests are Zig tests in `src/root_test.zig`; CLI
behaviour is `test/integration.zig`. Write new guest-behaviour tests on the mylang
side; the rule and the backlog of Zig tests still to move are in
`docs/tooling/test-layout.md`.

## Full gate (run before finishing)

```
zig build test --summary all
zig build fmt-check
```

`python3 scripts/verify_cache.py --zig /path/to/pinned/zig` is the complete
inventory-based verification entry point. It owns build/gate admission and
checks reusable evidence before requesting shared slots; do not wrap it in
`build-slot.sh`. See `docs/tooling/many-agents.md` for its freshness boundaries,
force controls, normalized fixture environment and evidence reports.

`zig build test` runs Guardian, `test-core`, the sharded `src/root_test.zig` and
`test/integration.zig` roots, `test-lang`, `test-guest`, `mylang doc-coverage .`,
`mylang doctest .` and the tooling drivers, all on the new core. The QBE-era steps
(`test-qbe`, `test-qbe-build`, the native C-runtime harnesses, the host-application
roots) are gone with the old back end.

Test verdicts are cached like build outputs (`test-core` excepted: it always runs). A
test shard, a Python driver or the
doctest re-runs only when its test binary, the compiler it runs, its command,
the live environment (recorded as a digest), or one of the repository files it
reads changes; those files are declared per step in
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

`zig build test` splits its slow Zig roots across processes: `src/core/root_test.zig`
into `-Dcore-shards=N` shards (default 8), `src/root_test.zig` into
`-Dtest-shards=N` shards (default 12) and `test/integration.zig` into `N/2`, each
one run of the same test binary under Guardian's `--guardian-shard=K/N` with its own
`max_rss`, so the shards run concurrently and print one `test wall` and one verdict
each. They partition the root — every test runs exactly once, and the shards' selected
counts sum to the unsharded count. `-Dtest-shards=1` restores one process per root, and
`-Dtest-filter=…` falls back to it automatically. See `docs/tooling/runtime-budgets.md`.

## Memory ceilings (why a runaway guest no longer kills the machine)

Every `mylang run` and every `mylang test` child runs under a byte ceiling: the
runtime counts its chunks and large blocks and traps `R_MEMORY_BUDGET` past it,
and lowers its own `RLIMIT_AS` to the ceiling plus 256 MiB. Precedence:
`--max-memory=SIZE` on `run`, `build --run` and `test`, then `MYLANG_MEMORY_LIMIT`
(bytes, `K`/`M`/`G` suffixes), then `limits` in `mylang.json`, then the defaults of
4 GiB for a run and 512 MiB per test child; `0` removes it. A binary from
`mylang build -o` carries no ceiling. Steps and frames: a run is unbounded unless
`--max-steps`/`--max-frames` is given (compiled into `main`; a frame reserves 32 KiB
of stack under the ceiling); a test defaults to 1,000,000 steps, 1,024 frames and
`--timeout-ms 60000`. The compiler caps itself at 8 GiB
(`MYLANG_HOST_MEMORY_LIMIT`), `mylang test <dir>` fans out to `--jobs`,
`MYLANG_JOBS` or the CPU count (not to free memory), and every build step declares
`max_rss`, so `zig build --maxrss N` bounds the whole gate's concurrency. See
`docs/tooling/runtime-budgets.md`.

## Caches and worktrees (the disk fills up)

- Share Zig's global cache across worktrees:
  `export ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache`. Zig locks it
  per entry, so concurrent builds are safe.
- Never share `.zig-cache` (`ZIG_LOCAL_CACHE_DIR`) between worktrees: Zig's configure
  cache ignores the build root. Never share a `.mylang-cache` between worktrees running
  different compilers: each compiler generation evicts the others' objects.
- Reuse a merged, clean worktree for new work (`git switch -c <branch> main`) instead of
  creating one; remove a worktree you are done with (`git worktree remove <path>`).
- `scripts/prune-caches.sh` (hourly on the dev box; dry run unless `--apply`) deletes the
  caches, `zig-out` and scratch binaries of worktrees idle for 3 days, and any
  `.zig-cache` over 15 GiB. Keep evidence as text, not in caches.
- Versioned developer evidence uses `scripts/cache_retention.py`, whose collector
  honors process leases and explicit pins. The legacy pruner preserves whole
  `.mylang-cache` directories and scratch containing retention locks. Coordinators
  can share exact evidence using `--shared-cache-dir` outside worktrees; mutable
  inventories stay private. See `docs/tooling/cache-retention.md`.
- Builds keep content-keyed unit, runtime and number-text objects in one per-user
  store (`MYLANG_CORE_RUNTIME_CACHE`, else `~/.cache/mylang/core-runtime`) shared
  safely by every worktree, and linked programs, replay records, front-end caches
  and test receipts in the work directory (`--cache-dir`, default
  `.mylang-cache/core`). Every `zig` process a build starts gets a private
  `ZIG_LOCAL_CACHE_DIR` in a staging directory removed when the build ends, so
  guest builds add nothing to `.zig-cache`. `scripts/prune-caches.sh` evicts the
  per-user store too. See `docs/tooling/native-build.md#the-caches`.
- Optional shared compiler artifacts and native test receipts use v2 namespaces
  with process leases and automatic hourly LRU retention (10 GiB compiler,
  256 MiB tests, 100,000 entries each). Use `mylang cache gc` to preview,
  `--apply` to collect, and `mylang cache configure` to persist policy. Old v1
  namespaces remain separate and require idle-only manual cleanup. See
  `docs/tooling/cache-retention.md#native-cache-retention`.

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

- **Locals have lexical block scope.** Declare immutable values with `const` and
  writable values with `mut`; assignment only updates an existing writable binding.
  A declaration disappears at its block's end, and an active name cannot be shadowed.
  Declare a writable result before an `if` or loop when later code needs it.
  Loop variables and match payloads are readonly bindings scoped to their bodies.
  Ordinary parameters are readonly snapshots; a `mut` parameter updates caller
  storage, including scalar rebinding and nested fields or elements. Ordinary values
  have independent snapshot semantics, with copy-on-write for managed contents.
  Spell arrays `T[]`, options `T?`, fixed arrays `FixedArray[T, N]`, and unit `Unit`.
  A fallible function declares `-> T fails E`; extract a checked result with boundary
  `try`, or return its error with `fail`. `with arena():` remains retired.
- **`range()` is a comprehension source, just like in a `for` loop.** `[for x in
  range(10) yield x]` and `[for x in range(a, b) yield x]` build a list of the range's integer values;
  comprehending over a list, string or dictionary works too.
- **`func main() -> int`'s value is the process exit status**, truncated to the low 8
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
  for graph identity. `class` and builtin `Cell` are rejected; there is no
  legacy-sharing mode. See `docs/value-semantics.md`.
- **Memory is reference counted.** One count per object, copy-on-write, released
  when the last owner goes away; there is no collector and no runtime choice
  (`--gc-runtime`, `--gc-stress`, `--rc-runtime` are refused). See
  `docs/managed-memory.md`.
- **File access needs a capability parameter on the entry point.** Write
  `func main(fs: Filesystem) -> int` and thread `fs` through; there is no ambient
  filesystem. `Network`, `Clock`, `Entropy` and `Environment` work the same way.
- **Printing goes through a `Stream` parameter.** Write `func main(out: Stream) -> int`
  and call `out.print(...)`; `err: Stream` is standard error. The runtime supplies both
  streams, so printing itself needs no host grant. `stream.print` contributes the
  `output` effect, which an explicit `noio` bound withholds — write `effects(output)` on
  any function in the chain that prints. Bare `print(...)` is rejected with
  `E_OUTPUT_CAPABILITY`. See `docs/io.md`.
- **`mylang run` grants every capability** unless you pass `--restrict` — it builds the
  program natively and runs it in a child process. A binary from `mylang build` grants
  every capability too and hands `main` its argv unchanged; runtime options such as
  `--restrict`, `--allow-*` and `--print-result` go in the `MYLANG_OPTIONS`
  environment variable instead (`MYLANG_OPTIONS=--restrict ./prog`).
- **C interop is `extern func` plus `--link FILE.c`.** Scalar arguments only, `host:
  Host` first. `host func`, `mylang invoke` and the host applications are retired.
- Integers have fixed width, conditions must be `bool`, lists are homogeneous, ranges
  take one or two arguments, and slices have no step.

Details: `docs/python-syntax.md`, `docs/io.md`, `docs/effects.md`, `docs/statements.md`.

## Native builds

`mylang build prog.my -o prog` checks the program, builds Core IR, emits LLVM and
drives `zig cc` and the link itself — no Python. A build is a debug build (one LLVM
unit per source module, every check kept, an edit recompiles only the units whose
text changed) unless `--release` asks for the optimized one (the whole program as one
LLVM unit; any edit recompiles it all), so iterate in debug and ship or time
`--release`. Unit objects are content-keyed in the per-user store; an unchanged build
replays its last identical build without checking or starting a process.
`--report` prints one `cache-report-v1` JSON line (units linked, reused, compiled,
verified; program `linked`, `reused` or `replayed`), `--cache-report` the same as
text, `--stats` what the release passes and the ownership plan did, and
`--verify-cache` recompiles every served unit and fails on a byte difference.
`--no-cache` builds through an empty private cache. The old back end's commands and
flags (`emit-qbe`, `dump-bytecode`, `invoke`, `compile-module`, `--backend`, `--lto`,
`--gc-runtime`, `--library`, …) are refused with a one-line reason. See
`docs/tooling/native-build.md` and `docs/tooling/guest-tests.md`.
