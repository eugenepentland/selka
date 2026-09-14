# mylang — working rules

A Python-syntax statically checked language. Zig compiler (`src/`), bytecode VM plus a
QBE native backend (amd64 Linux only). QBE is vendored under `vendor/qbe` and built by
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
  whose name contains SUBSTRING. `-Dtest-filter=arena` is 37 tests in 1.5 s; the whole
  root is 889 tests in 25 s. `zig build test-cli -Dtest-filter=…` does the same for
  `test/integration.zig`. Neither runs Python drivers or Guardian. The filter also
  applies to `zig build test` and `test-compile`. A filter that names nothing fails
  rather than reporting green, so filter one root at a time.
- `zig-out/bin/mylang test <entry.my|dir> --filter SUBSTRING` — guest (`.my`) tests.
  A bare substring matches anywhere in the qualified name; a pattern containing
  `*`, `?` or `[` is a glob. A directory runs every `.my` entry under it in parallel.
  Results are reused per test, so an unchanged rerun is near-free.
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

`zig build test` also runs `mylang doc-coverage .` and `tests/docs_examples.py`.

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

- **Locals are block-scoped.** A name first assigned inside `with`, `if` or `for` is not
  visible after the block. Pre-declare it before the block and reassign inside.
- **`range()` is not accepted as a comprehension source.** `[x for x in range(10)]` is
  rejected; comprehend over a list, or use a `for` loop.
- **`def main() -> int`'s value is not the exit status.** It is printed by
  `mylang run prog.my --print-result`. The process exit status is separate.
- **No tuples. No methods on classes. No closures.** Records are values; functions are
  top-level and take their state as parameters.
- **File access needs a capability parameter on the entry point.** Write
  `def main(fs: Filesystem) -> int` and thread `fs` through; there is no ambient
  filesystem. `Network`, `Clock`, `Entropy` and `Environment` work the same way.
- **`print` contributes the `output` effect.** An unbounded `def main() -> int` may
  print, but under an explicit bound (`noio`) it is rejected — write `effects(output)`
  on any function in the chain that prints.
- **`mylang run` grants every capability** unless you pass `--restrict`. Native builds
  (`mylang build`) grant only what the entry point's parameters ask for.
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
