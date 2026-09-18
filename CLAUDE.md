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

## Fast loops (use these while iterating)

- `zig build test-units -Dtest-filter=SUBSTRING` — runs only `src/root_test.zig` tests
  whose name contains SUBSTRING. `-Dtest-filter=arena` is 34 tests in about 1.5 s; the whole
  root is 1236 tests in about 84 s (measured warm 2026-09-18; `zig build test` shards it). `zig build test-cli -Dtest-filter=…` does the same for
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

## Full gate (run before finishing)

```
zig build test --summary all
zig build test-qbe --summary all
zig build test-qbe-build --summary all
zig build fmt-check
```

`zig build test` also runs `mylang doc-coverage .` and `mylang doctest .`.

`zig build test` splits its two slow Zig roots across processes: `src/root_test.zig`
into `-Dtest-shards=N` shards (default 8) and `test/integration.zig` into `N/2`, each
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
- **File access needs a capability parameter on the entry point.** Write
  `def main(fs: Filesystem) -> int` and thread `fs` through; there is no ambient
  filesystem. `Network`, `Clock`, `Entropy` and `Environment` work the same way.
- **`print` contributes the `output` effect.** An unbounded `def main() -> int` may
  print, but under an explicit bound (`noio`) it is rejected — write `effects(output)`
  on any function in the chain that prints.
- **`mylang run` grants every capability** unless you pass `--restrict` — it builds the
  program natively and runs it in a child process. A binary from `mylang build` grants
  every capability too; `--restrict` after `--` denies them.
- Integers have fixed width, conditions must be `bool`, lists are homogeneous, ranges
  take one or two arguments, and slices have no step.

Details: `docs/python-syntax.md`, `docs/io.md`, `docs/effects.md`, `docs/statements.md`.

## Native builds

`mylang build prog.my -o prog` drives QBE, the assembler and the linker directly — no
Python. Objects are content-addressed under `.mylang-cache/qbe` (override with
`--cache-dir`); the bundled runtime is published once per content hash and linked as one
static archive with `--gc-sections`, so a program that never prints does not carry the
printing runtime. `--report` prints a JSON timing/reuse breakdown. See
`docs/tooling/native-build.md` and `docs/tooling/guest-tests.md`.
