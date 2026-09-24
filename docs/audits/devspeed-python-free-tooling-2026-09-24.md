# Python-free building and use — 24 September 2026

Branch `devspeed/python-free-tooling`, from `main` `fd36abc2` (full gate green).

## Scope

The lane started as "remove Python from the build, the test gate and the
development tooling". Before any port was written the user narrowed it: Python
stays fine in tests, developer tools, `bench/`, `velocity/` and `experiments/`;
the rule is that **building, compiling and using mylang on its own needs no
Python**. In scope were:

1. whatever plain `zig build` and `zig build -Dcompiler-only` run;
2. whatever the installed `mylang` runs for its user commands;
3. scripts a mylang user runs to use or upgrade their code (list them; the
   paused `mylang fix` lane is meant to replace the migrations);
4. user-facing documentation that tells someone to run `python3` to build or use
   mylang.

No port had been started when the scope changed, so nothing was reverted. The
LLVM adapter (`experiments/llvm-backend/*.py`) belongs to the `llvm-zig` lane and
is untouched.

A second round of instructions added three follow-ups, done here: fix the
stale-environment bug in `build.zig` (§5), make local packages a native
command (§6), and move the sampled-law runner into `experiments/` (§7).

## Findings

### 1. The install graph runs no Python

The one Python step `build.zig` creates outside its named test steps is
`tests/input_manifest.py` (`addInputManifests`), but only cached **test** runs
read its output, so the install step never schedules it. The only other Python
on the install path is data: `zig build` copies the adapter's five `.py` files
to `lib/mylang-llvm/`. The runtime prebuild (`mylang emit-runtime
--llvm-adapter …`) builds the two LLVM runtime archives with `zig cc` and never
starts the adapter.

Evidence: cold builds (fresh `--cache-dir` and `--prefix`, so the configure
phase also ran without Python) under an environment with no Python, every
`execve` traced (see [Acceptance](#acceptance) for the lane head's numbers):

```sh
# nopy-bin holds symlinks to zig, sh, bash, env, git, coreutils, grep, sed, awk,
# find, xargs, diff, strace and nothing else; `command -v python3` finds nothing.
env -i HOME=$HOME TMPDIR=$TMPDIR PATH=$PWD/nopy-bin \
  strace -f -qq -e trace=execve -o build.strace \
  zig build [-Dcompiler-only=true] --cache-dir FRESH --prefix FRESH
```

Both installs carry all four runtime archives (QBE Debug, QBE ReleaseFast, LLVM,
LLVM+LTO) and the two formatter objects; the full install also has
`board-trial`, `schematic-svg` and `mylang-io`. The same held on `main`
`fd36abc2` before any change (compiler-only 34 s, full 39 s, 0 Python execs).

### 2. The installed compiler runs no Python except for `--release`

The compiler spawns `git` (`ref_diff.zig`, for `--against REF`), itself, `zig`,
`qbe` and the guest; the only Python it can start is the LLVM adapter, which
`--release` and `--backend llvm` resolve. Every user command was run on a
two-module sample project (an entry that prints, a module, two tests) and a
packages sample, with the compiler from a Python-free install and under the
same Python-free environment, each traced; the table is in
[Acceptance](#acceptance). `build --release` is the one remaining Python
dependency of using mylang, and it is the `llvm-zig` lane's to remove.

### 3. Scripts a user runs on their own code

None is wired into the compiler, and no user guide or diagnostic tells a user to
run one. They are listed for the `mylang fix` lane:

| Script | What it does | Driven by |
| --- | --- | --- |
| `scripts/migrate_derived_effects.py` | deletes an `effects(...)`/`noio` clause that only restates the ceiling the parameters imply | text rewrite |
| `scripts/migrate_unused_capability.py` | removes a capability parameter no body reads, the argument that fed it, and clauses left stale, round after round | `E_UNUSED_CAPABILITY`, `E/W_DERIVED_EFFECTS`, `E_ARITY` |
| `scripts/migrate_mut_clause.py` | turns a `mutates(a, b)` clause into `a: mut T` parameters | text rewrite |
| `scripts/migrate_mut_arguments.py` | inserts or removes `mut` call-argument markers | `E_MUTATION_MARKER` spans |
| `scripts/fix_mut_markers.py` | older single-purpose version of the above (adds markers only) | `E_MUTATION_MARKER` pastes |
| `scripts/fix_mut_modules.py` | runs `fix_mut_markers` on library modules without a `main` through a scratch entry | `E_MUTATION_MARKER` |
| `scripts/migrate-print-to-stream.py` | rewrites bare `print`/`eprint` to `out.print`/`err.print` and threads `Stream` parameters, in `.my`, Markdown fences and Zig fixtures | text rewrite |
| `scripts/migrate-host-capability.py` | adds `host: Host` as the first parameter of every `extern def`/`host def` (wave-4 migration, hard-coded to this repository's roots) | text rewrite |
| `scripts/migrate_zig_fixtures.py` | the same derived-effect cleanup inside Zig test fixtures (developer-only) | `E/W_DERIVED_EFFECTS`, `E_UNUSED_CAPABILITY` |

Every compiler-driven one applies a fix the diagnostic already names, which is
exactly what a `mylang fix` needs to emit.

Two documented tooling features were Python prototypes driving the compiler
from outside: `scripts/packages.py` (`local-locked-packages`) is now the native
`mylang packages` (§6), and `scripts/laws.py` (`named-executable-laws`) moved to
`experiments/guest-laws/` and out of the feature list (§7).
`scripts/navigate.py` is superseded for users by `mylang context`, `tests-for`
and `index-project`; it stays because developer scripts import it.
`scripts/verify.py` runs this repository's own `verify.json`; the README now says
so instead of presenting it as a user workflow.

### 4. User documentation

| Page | Was | Now |
| --- | --- | --- |
| `docs/tooling/navigation.md` (also `mylang docs navigation`) | `python3 -c` over the index JSON; `python3 scripts/navigate.py` | the compiler's own `index-project` and `context` output; `mylang context`/`tests-for` for focused questions |
| `docs/tooling/invocation.md` | four `\| python3 -c 'import json…'` pipes | the relevant part of the JSON `invoke` prints |
| `docs/tooling/packages.md` | `python3 scripts/packages.py lock/build` | `mylang packages lock/build`, with the refusals, exit status and receipt timing (§6) |
| `docs/tooling/agent-tools.md` | `python3 scripts/laws.py` presented as a feature | "an experiment, not part of mylang"; the native single-case route `mylang test --cases` |
| `README.md` | `python3 scripts/navigate.py`; "Project verification uses `python3 scripts/verify.py`", "the Python driver tests also run under `zig build test`" (false) | `mylang context`/`tests-for`; verify.py described as the repository's workflow runner; a paragraph stating what needs Python and what does not |
| `CLAUDE.md` | — | the rule, its guard test, "never wire Python into the install graph or spawn it from `src/`", and the live-environment rule for `build.zig` (§5) |

Developer and test pages (`docs/tooling/test-layout.md`, `runtime-budgets.md`,
`many-agents.md`, `timings.md`, `docs/performance.md`, `docs/byte-io-bulk.md`,
`docs/current-language.md`'s feature-surface receipt) keep their Python.
`docs/tooling/native-build.md` still says the LLVM adapter needs `python3`, which
is true until the `llvm-zig` lane lands.

### 5. Fixed: a cached configuration froze the environment of most test steps

**The bug.** Running a Python-free `zig build` in this worktree's own
`.zig-cache` and then the normal gate in the same cache made every driver in the
gate run with the Python-free `PATH` (`python3` exited 127, `test-spec-merge` and
the LLVM integration tests failed). A small probe project shows the mechanism:

```sh
# build.zig: two has_side_effects Run steps echoing $FOO; the second also calls
# run.setEnvironmentVariable("BAR", "x").
FOO=first  zig build   # plain FOO=first    with-env FOO=first
FOO=second zig build   # plain FOO=second   with-env FOO=first
```

`Step.Run.setEnvironmentVariable` copies the whole configure-time environment
into the step; the build runner stores that copy in the cached configuration,
whose key is the `-D` options and the build scripts but not the environment.
`bounded()` and `focused()` set `ZIG_GLOBAL_CACHE_DIR`, `MYLANG_QBE`,
`MYLANG_ZIG` and `MYLANG_LLVM_ADAPTER` on nearly every test step, so those steps
kept the `PATH`, `HOME`, `TMPDIR` and `MYLANG_*` of whichever build first
configured that set of `-D` options in that cache, whatever the environment of a
later `zig build test`. The frozen copy was also part of each cached verdict's
key, so the verdicts were keyed on the stale environment too.

**The fix** (`9f2ca0e6`), the more robust of the two options the first report
proposed (a `-D` option would still have needed every caller to pass it):

- `withTools` prefixes each such command with `sh -c '…' with-tools
  MYLANG_QBE=… MYLANG_ZIG=… [MYLANG_LLVM_ADAPTER=…]`. The shell resolves Zig's
  global cache exactly as `std.zig.resolveGlobalCacheDir` does, at make time,
  exports it, and `exec env NAME=value… CMD…` adds the tool paths (which depend
  only on the configuration). No Run step carries an environment map any more,
  so every child inherits the environment of the `zig build` that runs it. Test
  binaries keep the test-runner protocol: the wrapper `exec`s them with the same
  standard streams.
- A live environment is not in a step's cache key, so a new step, "record the
  test environment", writes the sorted `PATH`, `HOME`, `TMPDIR`,
  `XDG_CACHE_HOME`, `ZIG_GLOBAL_CACHE_DIR`, `ZIG_LOCAL_CACHE_DIR` and `MYLANG_*`
  of each build, and every cached test step (and the runtime-identity driver)
  declares that file as an input: a changed variable re-runs the cached
  verdicts, an unchanged one keeps them.
- **Regression check:** `requireLiveEnvironment` walks every step reachable
  from a top-level step at configure time and refuses the configuration when any
  Run step carries its own environment map. Adding
  `identity_run.setEnvironmentVariable("PROBE", "1")` makes `zig build -l` fail
  with `error: build step 'run python3' sets its own environment, which a cached
  configuration freezes; pass variables through withTools instead`.
- `CLAUDE.md` and `docs/tooling/runtime-budgets.md` state the rule.

The verification sequence and its results are in [Acceptance](#acceptance).

### 6. `mylang packages` replaces `scripts/packages.py`

`src/packages_command.zig` (`71ab14fe`) ports the tool with the same behaviour:

- `mylang packages lock CONFIG --output LOCK`: the namespace rule (ASCII
  identifier, never `std_`, unique), roots resolved against the configuration's
  directory, every `.my` source hashed with SHA-256 under the same 16 MiB and
  50,000-entry budgets, symbolic-link sources and directories refused, every
  source inside `name.my`/`name/`, empty packages refused.
- `mylang packages build ENTRY --lock LOCK [--command check-project|run-project|index-project|emit-project-qbe] [--receipt FILE]`:
  re-inventories the application directory and each locked package; refuses
  drift, doubled namespaces, shared module paths, `std_` module names and
  symbolic links before anything compiles; copies the re-hashed bytes and the
  nearest `mylang.json` (with its policy when it sits beside the entry) into a
  private directory under `TMPDIR`; runs `project-dependencies` and the command
  there; removes the staging directory.
- Formats are unchanged: the lock is byte-identical to what the Python tool
  wrote (`json.dumps(indent=2)`), and `lock_sha256` matches Python's
  `sha256(json.dumps(lock, separators=(',', ':')))` (checked on a sample:
  `7b983d8f…`).

**What was broken, and the smallest coherent fix.** `tests/packages.py` failed
on `main` because `run-project` now exits with `main`'s value (42 in its own
test) while the tool wrote the receipt only when the command exited 0, so a
successful run could never produce a receipt. The receipt is now written as soon
as the staged snapshot checks (`project-dependencies`, which type-checks, exits
0) and before the command runs; the command's exit status is forwarded, for
`run-project` the program's own. A refused build or a failing check leaves an
earlier receipt untouched.

**One deliberate difference:** `--compiler` is gone. The command runs this same
executable over the snapshot, and requires the dependency report's
`implementation.compiler_sha256` to equal its own identity, which the receipt
records; that replaces the Python tool's "compiler changed during package build"
check.

Coverage (`tests/packages.py` had one script; each of its checks is now a Zig
assertion, run under an empty `PATH`):

| `tests/packages.py` check | Zig test |
| --- | --- |
| lock succeeds; lock unchanged by later builds | `PACKAGES-BUILD-1` (byte comparison) |
| two applications build through one lock, print `42`; receipt `package-build-v1` with `dependencies`; app tree unchanged | `PACKAGES-BUILD-1` (also: exit status 42, receipt carries this compiler's `--features` identity, staging removed, default `check-project`) |
| edited library → exit 2, "changed"; lock unchanged | `PACKAGES-BUILD-1` spec-case (also: earlier receipt untouched) |
| app module colliding with the package → "duplicate" | same test |
| doubled lock → "incompatible" | same test |
| library replaced by a symlink → exit 2 | same test ("symbolic-link sources are rejected") |
| — (new) | same test: `std_` module name, unsupported lock version |
| — (new) | `PACKAGES-LOCK-1`: lock layout, resolved root, per-module SHA-256; reserved/invalid/duplicate namespace, missing root, empty package, source outside the namespace, missing `--output`; no output written on refusal |
| — (new) | three unit tests in `src/packages_command.zig`: namespace rule, inventory sorting and symlink refusal, command-line parsing |

`scripts/packages.py` and `tests/packages.py` are deleted;
`scripts/profile_large_project.py`'s limit table now points at the Zig file.
`src/features.json` (`local-locked-packages`), `SPEC.md` (`PACKAGES-LOCK-1`,
`PACKAGES-BUILD-1`), `docs/tooling/packages.md` and the design record describe
the command; the guide's console example was replayed under a Python-free
`PATH` and matches.

### 7. The law runner is an experiment

`scripts/laws.py`, its only helper `scripts/test_project.py` and its check
`tests/laws.py` moved to `experiments/guest-laws/` (`laws.py`,
`test_project.py`, `test_laws.py`, `a9bd1b54`), with their default compiler
paths adjusted. The check had been failing with `UnknownTestCase`: `mylang test`
runs only exported test functions and the fixture law was not `public`. With
that one word added, `python3 experiments/guest-laws/test_laws.py --compiler
zig-out/bin/mylang` passes. `named-executable-laws` moved from
`src/features.json`'s implemented list to `removed` (so `mylang --features` and
`mylang reference` no longer claim it). `docs/tooling/agent-tools.md` says it is
an experiment and shows the native single-case route (`mylang test --cases`);
the design record carries the run instructions; `current-language.md`,
`tests/guest/README.md`, `docs/experiments/guest-tests.md` and
`velocity/dogfood.md` point at the new place.

## What changed (commits)

| Commit | Change |
| --- | --- |
| `57dfa721` | `USE-WITHOUT-PYTHON-1` (`test/integration.zig`): `check`, `build`, the built executable, `run`, `test`, `fmt-project --check`, `docs`, `index-project` and `context` on a two-module project with `PATH` naming only an empty directory; rule stated in `CLAUDE.md` and the README |
| `7c4cb9c8` | navigation, invocation, packages and laws guides stop telling users to run `python3` |
| `884f4625` | deleted `examples/domain-codecs/use_calls.py`, `examples/schema/use_bindings.py`, `examples/workers/run.py` (they import modules only the removed `scripts/bindings.py`/`scripts/workers.py` provided) |
| `9f2ca0e6` | test steps run in the live environment; environment record keys cached verdicts; configure-time refusal of step environment maps (§5) |
| `71ab14fe` | `mylang packages lock|build`; `scripts/packages.py` and `tests/packages.py` deleted (§6) |
| `a9bd1b54` | law runner moved to `experiments/guest-laws/` and fixed (§7) |

## Classification of the tracked `.py` outside `experiments/` (now 182; 190 on `main`)

| Class | Files | Disposition |
| --- | --- | --- |
| Install graph (`zig build`, `-Dcompiler-only`) | none run; the adapter's 5 files are installed as data | `llvm-zig` lane |
| Installed compiler commands | none, except the adapter behind `--release` | `llvm-zig` lane |
| Gate drivers (`zig build test` and its named steps) | 10 in `tests/` (`input_manifest`, `test_inputs_coverage`, `idiom_probes`, `incremental_diff`, `parser_hints`, `test_friction_harvest`, `test_spec_merge`, `runtime_identity_cache`, `native_boundary_matrix`, `test_affected_tests`) + `scripts/test_native_memory.py` | kept (tests may use Python) |
| Developer tools, documented | `scripts/focused_test.py`, `scripts/affected_tests.py`, `scripts/merge_spec.py` (git merge driver), `bench/parity/*.py` (2), `velocity/*.py` (3), `selfhost/tests/*.py` (3) | kept |
| Other developer and research scripts | 29 in `scripts/` (verify + `verification/`, navigate, project, store, store_server, intent/, trace, test_contract, test_providers, benchmark_*, profile_*, summarize_profile_warm, verify_pcb_latency, audit_deepseek_tools, safety_*, worker_snapshot) | kept, liveness not audited |
| User-code migrations | 8 in `scripts/` + `migrate_zig_fixtures.py` (§3) | listed for `mylang fix` |
| User feature in Python | `scripts/packages.py` (+ `tests/packages.py`) | **ported** to `mylang packages`, deleted |
| Experiment presented as a feature | `scripts/laws.py`, `scripts/test_project.py`, `tests/laws.py` | **moved** to `experiments/guest-laws/`, fixed |
| Tests no build step runs | 37 top-level `tests/*.py`, `tests/application_comparison/` (53, testing `experiments/application_comparison`), `tests/development_velocity/` (13), `tests/verification/` (5) | kept |
| Dated research records | 14 under `docs/audits/` | kept |
| Dead user-facing examples | 3 under `examples/` | **deleted** |

## Acceptance

All results below are for the code at `a9bd1b54` (the report commit changes
only this page). Machine load average 11-14 during the runs.

**No Python on `PATH`**: fresh `--cache-dir`/`--prefix` for each build, so the
configure phase also ran without Python; every `execve` traced.

| Check | Result |
| --- | --- |
| `zig build -Dcompiler-only=true` | exit 0 (21 s); zig 163, `cc` 31 (lookups that miss; harmless), git 21, guardian-check 2, qbe-build-assets 1, mylang 1 (`emit-runtime`), maker 1, configurer 1; **0 Python execs** |
| `zig build` | exit 0 (24 s); the same plus 3 zig; **0 Python execs** |
| 26 user commands of the compiler-only install: `check`, `check-project`, `build -o` and the built program, `run`, `test`, `test --filter`, `fmt`, `fmt --check`, `fmt-project --check`, `docs primer`, `docs build`, `reference --query`, `index-project`, `context`, `tests-for`, `list-interfaces`, `lint`, `emit-project-qbe`, `api-diff --write`, `project-dependencies`, `dump-tokens`, `invoke --describe`, **`packages lock`**, **`packages build --command run-project --receipt`** (exit 42, the program's value, as expected), **`packages build`** (check) | all as expected, **0 Python execs** |
| `build --release` | exit 2: `python3` not found (the LLVM adapter, `llvm-zig` lane) |
| `USE-WITHOUT-PYTHON-1`, `PACKAGES-LOCK-1`, `PACKAGES-BUILD-1` (in the gate, empty `PATH`) | pass |

**Stale-environment regression and the normal gate** (Python available), all
in the worktree's own `.zig-cache`. Step 1 configures that cache under the
Python-free environment, which is the order that failed before the fix. Steps
2-4 are the sequence the coordinator asked for: gate, Python-free build in the
same cache, gate again.

| Step | Result |
| --- | --- |
| 0. `rm -rf .zig-cache` | — |
| 1. Python-free `zig build` (configures the cache) | exit 0 |
| 2. `zig build test --summary all --maxrss 8000000000` | **93/93 steps succeeded**, 1907 tests passed in the steps that ran (163 s, cold); `test-spec-merge`, the idiom, parser-hint, boundary and native-memory drivers all ran `python3` successfully (before the fix, each exited 127 here) |
| 2. `zig build test-qbe --summary all` | 52/52 steps, 390/390 tests passed |
| 2. `zig build test-qbe-build --summary all` | 34/34 steps succeeded |
| 2. `zig build fmt-check` | exit 0 |
| 2. `zig-out/bin/mylang test tests/lang` | 569 passed across 106 programs |
| 3. Python-free `zig build` in the same cache | exit 0 |
| 4. `zig build test` again | 93/93 steps succeeded (6 s: every verdict cached, same environment) |
| 5. `zig build test-native-memory` | driver `cached` |
| 6. the same again | driver `cached` |
| 7. the same with `MYLANG_JOBS=3` | driver re-ran (5 s): a changed recorded variable invalidates the verdict |

The configure-time guard was checked by hand: adding one
`setEnvironmentVariable` call makes `zig build -l` refuse the configuration
(§5).

Gate steps that still run Python (allowed): the drivers in the classification
table, `test-llvm-adapter` (`python3 -m unittest` in `experiments/llvm-backend`),
and every `--release` test, which starts the adapter.

The scripts used here are small shell files outside the repository:
- a `nopy-bin` directory of symlinks (zig, sh, bash, env, git, strace,
  coreutils, grep, sed, awk, find, xargs, diff; no python);
- `env -i HOME TMPDIR PATH=nopy-bin` around each command;
- `strace -f -e trace=execve` on each, and a count of the executed programs whose
  path names python.

## For the integrator

- **When `llvm-zig` lands:** add `build --release` (and a run of its output) to
  `USE-WITHOUT-PYTHON-1`, and drop the `--release` exception from the SPEC bullet,
  `CLAUDE.md` ("Build") and the README paragraph under "Build and use"; update
  `docs/tooling/native-build.md`'s adapter paragraph and README's "The installed
  adapter requires Python 3". `llvm-zig` also edits the adapter install in
  `build.zig`; if it sets any variable on a Run step it must go through
  `withTools` (or the configure check refuses the build).
- **Conflict risk:**
  - `build.zig`: `bounded()`/`focused()` lost their `setEnvironmentVariable`
    lines, `cached()` gained one input, and four helpers and two calls were
    added near `addInputManifests`/the end of `build()`.
  - `SPEC.md`: three bullets after `BUILD-BACKEND-4`.
  - `test/integration.zig`: four tests after `spawnWithEnv`.
  - `src/main.zig`: one dispatch block and one usage line.
  - `src/root_test.zig`: one import.
  - `src/features.json`: two entries edited or moved.
  - `docs/tooling/navigation.md`: two console blocks and one sentence, in case
    `navigation-scale` edits the page.
- **Test-verdict caching now follows the environment:** a cached test verdict
  re-runs when `PATH`, `HOME`, `TMPDIR`, `XDG_CACHE_HOME`, the Zig cache
  variables or any `MYLANG_*` differ from the last run in that cache. Sessions
  whose `PATH` differs, for example with a different set of plugin directories,
  no longer share cached verdicts. Before the fix they shared the verdicts
  keyed on whatever environment first configured the cache, which was wrong.
- **Follow-up offered, not done:** a laws mode for `mylang test` if sampled laws
  should become part of mylang.
