# Contributing to Selka

Selka is experimental and its compiler changes quickly. This page says how to build it from source, how to test a change and
what a change should carry. Using the language needs none of it: the [README](README.md) installs a release.

## What you need

- Linux on x86-64.
- git. A depth-1 clone builds: nothing reads history.
- Zig **0.17.1**, the stable release from <https://ziglang.org/download/>. `.zigversion` names it. The build accepts any 0.17
  release from 0.17.1 on and refuses a development snapshot; the tests and the continuous integration want exactly the
  release `.zigversion` names, and compiled programs are reused between builds only with the official 0.17.1 distribution.
- Python 3, for the drivers that `zig build test` runs today (see "Tests"). Building the compiler and using it need no Python.
- Lean 4 with its build tool `lake`, only for the proof actions, which run when you pass `-Dproofs=true`.

## Build

```sh
git clone https://github.com/eugenepentland/selka.git
cd selka
zig build                      # installs zig-out/bin/selka
zig-out/bin/selka run examples/factorial.selka
```

A plain `zig build` makes a Debug compiler (it checks and plans more slowly than a release one) and compiles the two
Selka components in `selfhost/components/` with the compiler it has just built. The compiler's optimisation mode does not
choose the build mode of the programs it compiles: `--release` does. Use `zig build -Doptimize=ReleaseFast` for a compiler
you hand to others or time.

For the inner loop of a compiler edit use `zig build -Dcomponents=reference`: it installs no component, and the compiler then
answers with its built-in test index and cache plan and says so in one line on standard error. `zig build --watch
-fincremental` rebuilds after each saved change; an incremental build is not always the same program as a normal one, so confirm
a failure that only the watcher shows with a normal `zig build`. Keep `TMPDIR` on a disk with room for large native runs.

## Tests

```sh
zig build test            # the whole suite
zig build fmt-check       # Zig and .selka formatting
```

`zig build test` runs the compiler's unit and command-line suites, the guest suite (`tests/lang`, Selka programs run with the
leak check), the documentation examples, `selka doc-coverage .`, the test runner's own tests and the Python drivers in `tests/`
and `scripts/`, so it needs Python 3 today. A result is cached until its test binary, the compiler, or a file it reads changes;
`-Dtest-rerun=true` reruns everything. `-Dproofs=true` adds the four Lean proof actions; without it each prints that it was
skipped and exits 0.

While you iterate, narrow a suite to the tests whose name contains some text, one root at a time (a filter that selects nothing
fails):

```sh
zig build test-core  -Dtest-filter=SUBSTRING     # the core (src/core, test/core)
zig build test-units -Dtest-filter=SUBSTRING     # src/root_test.zig: front end, diagnostics, tooling
zig build test-cli   -Dtest-filter=SUBSTRING     # test/integration.zig: the command line
zig build test-lang                              # tests/lang, tests/value_semantics, tests/ported
zig build test-docs                              # every fenced example in README.md and docs/
zig build test-compile                           # type-checks every test root without running it
zig-out/bin/selka test tests/lang --filter NAME  # one guest test
```

`zig build test-core`, `test-units` and `test-cli` do not install the compiler: run a plain `zig build` before using
`zig-out/bin/selka` directly after a `src/` change. `python3 scripts/verify_cache.py --zig "$(command -v zig)" --profile
complete` is the maintainer's complete check: everything `zig build test` runs plus `fmt-check`, with its evidence cached.

### Where tests live

- Language behaviour is tested in the language: a `public func test_*() -> bool` in `tests/lang/<area>.selka`. Write new
  guest-behaviour tests this way.
- The core's own tests (IR, passes, emission, caches, the test runner) are Zig tests under `src/core/`, with fixtures in
  `test/core`. Diagnostics, traps, formatting and the like are Zig tests in `src/root_test.zig`; command-line behaviour is in
  `test/integration.zig`. A test that reads a repository file declares it in `build_test_inputs.zig`; `zig build
  test-inputs-coverage` fails when it does not.
- [docs/tooling/test-layout.md](docs/tooling/test-layout.md) has the whole matrix, and
  [docs/tooling/compiler-map.md](docs/tooling/compiler-map.md) says where each kind of change and test goes.

## Previewing the documentation site

The user guides in `docs/` (the pages `src/user_docs.zig` lists) are published at <https://eugenepentland.github.io/selka/> by
`.github/workflows/pages.yml` on every push to `main`. To preview a change, install [mdBook](https://rust-lang.github.io/mdBook/)
(the workflow pins its version) and run `mdbook serve --open` in the repository root. A guide added to the list needs a line in
`docs/SUMMARY.md`; `scripts/build-site.sh`, `scripts/check-site-pages.sh` and `scripts/check-site-links.sh` build and check the site.

## Conventions no tool checks

A review may ask for these, but no build or test fails on them:

- A behavioural change ships with a test change in the same diff.
- A struct has at most 7 fields and a function at most 6 parameters; group the rest into a struct.
- Every `pub` declaration has a `///` doc comment that says what it does, not that it exists.
- No `@import` cycles, and every new `src/*.zig` file is reachable from a test root.
- No random numbers outside the module sanctioned for them, no wall-clock reads and no hardcoded absolute paths.
- A test has at least one `expect*` assertion and no `if`, `while` or `switch` (or extra `for`) at the top level of its body.
- A `.selka` file passes `selka fmt --check`.
- Logs, receipts, data files and other captured output stay out of git.

## Breaking changes ship a migration

A change that turns previously accepted code into a diagnostic carries the repair as a structured `fix` on that diagnostic
wherever the edit is certain, so `selka fix` moves a project across it with no hand edits. Add a pre-change corpus under
`test/fixtures/fix-migration/` and a test beside `FIX-MIGRATION-1` in `test/fix_cli_test.zig` that proves `selka fix` migrates
it to a clean check; [docs/tooling/fix.md](docs/tooling/fix.md) has the details. Describe the change in
[CHANGES.md](CHANGES.md), under "Unreleased", the way the entries there do: what breaks, and how the migration moves a project.

## Pull requests

Keep a pull request to one change, with its tests, and run `zig build test` and `zig build fmt-check` before you open it. The
continuous integration builds a fresh clone on Debian and Fedora, runs `zig build fmt-check` and the guest suite
(`zig build test-lang`) on every pull request.

Selka is released under the [MIT license](LICENSE).
