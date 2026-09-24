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
3. scripts a mylang user runs to use or upgrade their code (list them, do not
   port them: the paused `mylang fix` lane is meant to replace the migrations);
4. user-facing documentation that tells someone to run `python3` to build or use
   mylang.

No port had been started when the scope changed, so nothing was reverted. The
LLVM adapter (`experiments/llvm-backend/*.py`) belongs to the `llvm-zig` lane and
is untouched.

## Findings

### 1. The install graph runs no Python

The one Python step `build.zig` creates outside its named test steps is `tests/input_manifest.py`
(`addInputManifests`), but only cached **test** runs read its output, so the
install step never schedules it. The only other Python on the install path is
data: `zig build` copies the adapter's five `.py` files to `lib/mylang-llvm/`.
The runtime prebuild (`mylang emit-runtime --llvm-adapter …`) builds the two LLVM
runtime archives with `zig cc` and never starts the adapter.

Evidence: a cold build (fresh `--cache-dir` and `--prefix`) under an environment
with no Python, every `execve` traced:

```sh
# nopy-bin holds symlinks to zig, sh, bash, env, git, coreutils, grep, sed, awk,
# find, xargs, diff, strace and nothing else; `command -v python3` finds nothing.
env -i HOME=$HOME TMPDIR=$TMPDIR PATH=$PWD/nopy-bin \
  strace -f -qq -e trace=execve -o build.strace \
  zig build [-Dcompiler-only=true] --cache-dir FRESH --prefix FRESH
```

| Build (lane head `884f4625`) | Exit | Wall | Programs executed (execve count) | Python execs |
| --- | --- | --- | --- | --- |
| `zig build -Dcompiler-only=true` | 0 | 58 s | zig 163, `cc` 31 (lookups that miss; harmless), git 21, guardian-check 2, qbe-build-assets 1, mylang 1 (`emit-runtime`), maker 1, configurer 1 | 0 |
| `zig build` (full install) | 0 | 40 s | zig 166, `cc` 31, git 21, guardian-check 2, qbe-build-assets 1, mylang 1, maker 1, configurer 1 | 0 |

Both installs carry all four runtime archives (QBE Debug, QBE ReleaseFast, LLVM,
LLVM+LTO) and the two formatter objects; the full install also has
`board-trial`, `schematic-svg` and `mylang-io`. The same result held on `main`
`fd36abc2` before any change (compiler-only 34 s, full 39 s, 0 Python execs).

### 2. The installed compiler runs no Python except for `--release`

The compiler spawns `git` (`ref_diff.zig`, for `--against REF`), itself, `zig`,
`qbe` and the guest; the only Python it can start is the LLVM adapter, which
`--release` and `--backend llvm` resolve. Every user command was run on a
two-module sample project (an entry that prints, a module, two tests) with the
installed compiler from the Python-free install above, under the same
Python-free environment, each traced:

| Command | Exit | Python execs |
| --- | --- | --- |
| `check`, `check-project` | 0 | 0 |
| `build -o OUT`, then `OUT` | 0 | 0 |
| `run` | 0 | 0 |
| `test`, `test --filter '*count*'` | 0 | 0 |
| `fmt`, `fmt --check`, `fmt-project --check` | 0 | 0 |
| `docs primer`, `docs build`, `reference --query` | 0 | 0 |
| `index-project`, `context --symbol`, `tests-for`, `list-interfaces` | 0 | 0 |
| `lint`, `api-diff --write`, `project-dependencies`, `emit-project-qbe`, `dump-tokens`, `invoke --describe` | 0 | 0 |
| `build --release` | 2 | 1: `env: 'python3': No such file or directory` from `lib/mylang-llvm/qbe_llvm.py` |

`build --release` is the one remaining Python dependency of using mylang, and it
is the `llvm-zig` lane's to remove.

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

Two documented tooling features are Python prototypes that drive the compiler
from outside. Neither is needed to build, check, run or test a program; both are
now labelled as prototypes in their guides:

| Script | Feature (`src/features.json`) | State on `main` |
| --- | --- | --- |
| `scripts/packages.py` (`lock`, `build`) | `local-locked-packages` | works; its own test `tests/packages.py` fails because `run-project` now exits with `main`'s value (42), and no build step runs it |
| `scripts/laws.py` (+ `scripts/test_project.py`) | `named-executable-laws` | works on a `public def test_*` law; `tests/laws.py` writes a non-public law and fails with `UnknownTestCase`, and no build step runs it |

A native `mylang packages` and a laws mode for `mylang test` would each be a small
port; they are recommended follow-ups, not done here (scope item 3).
`scripts/navigate.py` is superseded for users by `mylang context`, `tests-for`
and `index-project`; it stays because developer scripts import it.
`scripts/verify.py` runs this repository's own `verify.json`; the README now says
so instead of presenting it as a user workflow.

### 4. User documentation

| Page | Was | Now |
| --- | --- | --- |
| `docs/tooling/navigation.md` (also `mylang docs navigation`) | `python3 -c` over the index JSON; `python3 scripts/navigate.py` | the compiler's own `index-project` and `context` output; `mylang context`/`tests-for` for focused questions |
| `docs/tooling/invocation.md` | four `\| python3 -c 'import json…'` pipes | the relevant part of the JSON `invoke` prints |
| `README.md` | `python3 scripts/navigate.py`; "Project verification uses `python3 scripts/verify.py`", "the Python driver tests also run under `zig build test`" (false) | `mylang context`/`tests-for`; verify.py described as the repository's workflow runner; a paragraph stating what needs Python and what does not |
| `docs/tooling/packages.md`, `docs/tooling/agent-tools.md` | the prototype scripts presented as the feature | a status sentence: Python prototype outside the compiler; `mylang test --cases` runs a single law case natively |
| `CLAUDE.md` | — | the rule, its guard test, and "never wire Python into the install graph or spawn it from `src/`" |

Developer and test pages (`docs/tooling/test-layout.md`, `runtime-budgets.md`,
`many-agents.md`, `timings.md`, `docs/performance.md`, `docs/byte-io-bulk.md`,
`docs/current-language.md`'s feature-surface receipt) keep their Python.
`docs/tooling/native-build.md` still says the LLVM adapter needs `python3`, which
is true until the `llvm-zig` lane lands.

### 5. Hazard: a cached configuration freezes the environment of most test steps

Running the no-Python `zig build` in this worktree's own `.zig-cache` and then
the normal gate in the same cache made every driver in the gate run with the
Python-free `PATH` (`python3` exited 127, `test-spec-merge` and the LLVM
integration tests failed). A small probe project shows why:

```sh
# build.zig: two has_side_effects Run steps echoing $FOO; the second also calls
# run.setEnvironmentVariable("BAR", "x").
FOO=first  zig build   # plain FOO=first    with-env FOO=first
FOO=second zig build   # plain FOO=second   with-env FOO=first
```

A Run step that sets any variable copies the configure-time environment into
itself, that copy is stored with the cached configuration, and the
configuration's cache key does not include the environment. `bounded()` and
`focused()` in `build.zig` set `ZIG_GLOBAL_CACHE_DIR`, `MYLANG_QBE`, `MYLANG_ZIG`
and `MYLANG_LLVM_ADAPTER` on nearly every test step, so those steps keep the
`PATH`, `TMPDIR`, `HOME` and `MYLANG_*` of whichever build first configured that
set of `-D` options in that cache directory, whatever the environment of a later
`zig build test`. Consequences:

- a gate run after an environment change can test the old environment (a false
  red here; a false green is equally possible);
- every no-Python measurement in this report used a fresh `--cache-dir`, so its
  configure phase ran without Python.

Not fixed here (it is `build.zig` plumbing, outside this lane). Possible fixes:
pass the tool variables as `env VAR=value` arguments of the step's command
instead of `setEnvironmentVariable`, or fold the relevant environment into a
`-D` option so it keys the configuration.

## What changed

- **Guard** (`57dfa721`): `USE-WITHOUT-PYTHON-1` in `test/integration.zig` runs
  `check`, `build`, the built executable, `run`, `test`, `fmt-project --check`,
  `docs`, `index-project` and `context` on a two-module project with `PATH`
  naming only an empty directory and nothing but `--zig`/`--qbe` handed in, so a
  command that reached for `python3` (or any other unnamed program) fails the
  gate. About 16 s in one CLI shard. SPEC bullet beside `BUILD-BACKEND-4`.
- **Docs** (`7c4cb9c8`): the table in §4.
- **Deleted** (`884f4625`): `examples/domain-codecs/use_calls.py`,
  `examples/schema/use_bindings.py` and `examples/workers/run.py`. The first two
  import modules only the removed `scripts/bindings.py` generated; the third
  imports the removed `scripts/workers.py`; none could run. Their design records
  under `docs/experiments/` say so.

## Classification of the tracked `.py` outside `experiments/` (190 files)

| Class | Files | Disposition |
| --- | --- | --- |
| Install graph (`zig build`, `-Dcompiler-only`) | none run; the adapter's 5 files are installed as data | `llvm-zig` lane |
| Installed compiler commands | none, except the adapter behind `--release` | `llvm-zig` lane |
| Gate drivers (`zig build test` and its named steps) | 10 in `tests/` (`input_manifest`, `test_inputs_coverage`, `idiom_probes`, `incremental_diff`, `parser_hints`, `test_friction_harvest`, `test_spec_merge`, `runtime_identity_cache`, `native_boundary_matrix`, `test_affected_tests`) + `scripts/test_native_memory.py` | kept (tests may use Python) |
| Developer tools, documented | `scripts/focused_test.py`, `scripts/affected_tests.py`, `scripts/merge_spec.py` (git merge driver), `bench/parity/*.py` (2), `velocity/*.py` (3), `selfhost/tests/*.py` (3) | kept |
| Other developer and research scripts | 30 in `scripts/` (verify + `verification/`, navigate, project, store, store_server, intent/, trace, test_project, test_contract, test_providers, benchmark_*, profile_*, summarize_profile_warm, verify_pcb_latency, audit_deepseek_tools, safety_*, worker_snapshot) | kept, liveness not audited |
| User-code migrations | 8 in `scripts/` + `migrate_zig_fixtures.py` (§3) | listed for `mylang fix` |
| User-feature prototypes | `scripts/packages.py`, `scripts/laws.py` (§3) | documented as prototypes; port recommended |
| Tests no build step runs | 39 top-level `tests/*.py`, `tests/application_comparison/` (53, testing `experiments/application_comparison`), `tests/development_velocity/` (13), `tests/verification/` (5) | kept; `tests/packages.py` and `tests/laws.py` are known to fail |
| Dated research records | 14 under `docs/audits/` | kept |
| Dead user-facing examples | 3 under `examples/` | **deleted** |

## Acceptance

**No Python on `PATH`** (lane head `884f4625`, fresh `--cache-dir`/`--prefix`
for each build so its configure phase also ran without Python; §5):

| Check | Result |
| --- | --- |
| `zig build -Dcompiler-only=true` | exit 0, 0 Python execs (§1) |
| `zig build` | exit 0, 0 Python execs (§1) |
| 23 user commands of the compiler-only install on the sample project (§2) | all exit 0, 0 Python execs |
| `build --release` | exit 2: `python3` not found (the LLVM adapter, `llvm-zig` lane) |
| `USE-WITHOUT-PYTHON-1` (in the gate) | passes |

The scripts are small: a `nopy-bin` directory of symlinks (zig, sh, bash, env,
git, strace, coreutils, grep, sed, awk, find, xargs, diff; no python),
`env -i HOME TMPDIR PATH=nopy-bin` around each command, `strace -f -e
trace=execve` on each, and a count of executed programs whose path names
python.

**Normal gate** (Python allowed; machine load average 18-24 during the run):

| Step | Result |
| --- | --- |
| `zig build test --summary all --maxrss 8000000000` | 92/92 steps succeeded (129 s from a clean local cache) |
| `zig build test-qbe --summary all` | 51/51 steps, 390/390 tests passed |
| `zig build test-qbe-build --summary all` | 33/33 steps succeeded |
| `zig build fmt-check` | exit 0 |
| `zig-out/bin/mylang test tests/lang` | 569 passed across 106 programs |

Gate steps that still run Python (allowed; listed because the original brief
asked): the drivers in the classification table, `test-llvm-adapter`
(`python3 -m unittest` in `experiments/llvm-backend`), and every `--release`
test, which starts the adapter.

## For the integrator

- **When `llvm-zig` lands:** add `build --release` (and a run of its output) to
  `USE-WITHOUT-PYTHON-1`, and drop the `--release` exception from the SPEC bullet,
  `CLAUDE.md` ("Build") and the README paragraph under "Build and use"; update
  `docs/tooling/native-build.md`'s adapter paragraph and README's "The installed
  adapter requires Python 3".
- **Conflict risk:** `SPEC.md` gains one bullet after `BUILD-BACKEND-4`, where
  `llvm-zig` may amend `BUILD-BACKEND-*` (the `spec-bullets` merge driver merges
  by tag). `test/integration.zig` gains one test after `spawnWithEnv`.
  `docs/tooling/navigation.md` changes only in its two console blocks and one
  sentence, in case `navigation-scale` edits the page. `README.md` and
  `CLAUDE.md` edits are single paragraphs.
- **Environment hazard (§5):** a `zig build test` in a cache first configured
  under another environment runs most test steps with that old environment.
  Anyone repeating the no-Python checks should use a separate `--cache-dir`, as
  here; the `build.zig` fix is a separate change.
- **Follow-ups offered, not done:** native `mylang packages lock|build` and a
  laws mode for `mylang test`, which would retire the last two user-facing Python
  prototypes; repair or delete `tests/packages.py` and `tests/laws.py`.
