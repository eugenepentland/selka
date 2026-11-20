# Development-speed lane: QBE by default, `--release`, and findable documentation — 23 September 2026

Branch `devspeed/defaults-and-docs`, from `base/devspeed-impl-20260923` (`371dbd17`).
It implements recommendations 2 and 8 of the
[development-speed audit](development-speed-2026-09-23.md) (on the audit branch
`mylang-worktrees/devspeed-audit-20260923`, not yet on this base) and the
discoverability half of recommendation 5.

## What changed

**QBE is the default backend in every mode** (`c4ff8a7a`). A `build`, `build --run`,
`run`, `run-project` or `test` that names no backend now resolves to QBE in
`ReleaseFast` as well as in `Debug` (`src/qbe_build_backend.zig`, and the run
cache's view of it in `src/native_run.zig`). `--mode` keeps its meaning and its
`ReleaseFast` default; only the unnamed backend changed. `--backend llvm
[--llvm-opt N] [--lto]` is unchanged.

**`--release`** is the shorthand for `--mode ReleaseFast --backend llvm --llvm-opt 3
--lto`, as `cargo build --release` is, on `build` (and `build --run`), `run`,
`run-project` and `test`:

- It refuses a control it already names (`--mode`, `--backend`, `--qbe`,
  `--llvm-opt`, `--lto`) in either order, keeps an `--llvm-adapter` written after
  it, accepts `--unchecked`, and after `--` belongs to the guest.
- It rides in `link_arguments` (build and test), so neither frozen `Options`
  struct grows and the type-size ratchet is untouched.
- `mylang test --release` hands `--release` to its child build instead of
  `--qbe … --mode …`, keys its receipts on it (a QBE result never answers for an
  LLVM run), and a directory run forwards it to each child in place of `--mode`.
- The link-input scan (`src/native_link.zig`) treated every bare switch it did not
  know as taking a value, so `--lto --link a.c` silently dropped `a.c`. It now knows
  every bare build and test switch, `--release` included.

**Harnesses that measured the old default** now name the release build: the
standing parity benchmark (`bench/parity/bench_parity.py`: arms `my`,
`my-unchecked`, `my-<variant>`, plus its README), the perf-parity-plan scripts
(`bench.py`, `counterfactual.py`, `parser_bench.py`, `results/wave0/arena_scaling.py`,
`results/wave4/traps/compare.py`, `results/wave4/checkedadd-{measure,placement}.sh`),
and the two integration tests that compare LLVM against QBE (the frame-map trap
and the checked-arithmetic intrinsics). The scripts spell out
`--backend llvm --llvm-opt 3 --lto` rather than `--release`, because several of
them time a second, older compiler (`-Dbench-mylang`, `BEFORE_MYLANG`) that predates
the shorthand; the flags build byte-for-byte the arm the old default built (same
resolved codegen, same cache keys). Everything else found by the search either
already names a backend (`host_native.zig`'s hosts, the schematic lane runners,
`native_boundary_matrix.py`, the selfhost drivers, `verify_pcb_latency.py`) or
runs guests for correctness only (`velocity/`, `tests/parser_hints.py`).
Experiments from before 21 September 17:27, when the LLVM default landed, get
back the QBE build they were written against.

**`mylang docs [TOPIC]`** (`92c0320a`). The user guides are embedded in the
compiler. With no argument it lists eighteen topics, primer first; with one it
prints that page's Markdown from any working directory; an unknown topic exits 2
and names the topics. The topics are the required eleven (`primer`, `syntax`,
`io`, `text`, `bytes`, `modules`, `tests`, `errors`, `effects`, `stdlib`, `build`)
plus `statements`, `records`, `functions`, `memory`, `arenas`, `navigation` and
`context`. One table, `src/user_docs.zig`, names them: `build.zig` imports it to
give each page an anonymous import and `src/docs_command.zig` embeds the page by
that name, so a moved page fails the build rather than the command. The sources
stay in `docs/`; the eighteen pages add 305 KB to the compiler.

**A one-page primer**, `docs/primer.md` (9.9 KB), from the trial kit's
`kit2/PRIMER.md`, updated for the base: `mylang test` and `fmt` take headerless and
module files alike (the "`test` needs the header" rule is gone), `[]` passed to a
method infers, `strings.format_float` rounds the exact binary value (the caution
now names the one remaining difference: an exact tie such as `0.125` rounds away
from zero, and `-0.001` prints `0.00`), `--help`, QBE by default and `--release`,
and `mylang docs`. Four of its blocks run with pinned output, two are
type-checked; the negative claims in its "not available" table were each checked
against the compiler (every one is still rejected).

**First contact.** `README.md` opens with "Start here" (primer, `mylang docs`,
`--release`, the navigation commands, the docs index). `docs/README.md` indexes
the user guides by task and keeps the compiler's own records (plans, proposals,
handoffs, `audits/`, `experiments/`, `adr/`, `legacy/`) in a separate section.
`mylang --help`'s first screen now points at `mylang docs primer`, lists
`build --release` and `docs [TOPIC]`, and has a "Working in a large project" block
naming `context --symbol`, `context --at`, `tests-for`, `list-interfaces` and
`test --affected --against` — commands that exist today; `mylang fix` is left to
its lane.

Spec: `BUILD-BACKEND-1`, `BUILD-BACKEND-2` (rewritten), `BUILD-RELEASE-1` (new),
`CLI-HELP-1` (rewritten), `CLI-DOCS-1` (new); `BUILD-BACKEND-5`'s text follows.
Features: `release-builds`, `docs-command`.

## Acceptance

| Rule | Evidence | Status |
| --- | --- | --- |
| `mylang build x.my -o x` uses QBE | `CLI build uses QBE when no backend is named and --release builds LLVM O3 with LTO` (receipt `"mode":"ReleaseFast"`, `"backend":"qbe","optimization":"default","lto":false`; Debug too) | met |
| `--release` produces the LLVM LTO build | same test: receipt `"backend":"llvm","optimization":"3","lto":true`, the binary exits 42; `run --release` prints 42; `--release` beside `--qbe` is a usage error | met |
| every harness that needs LLVM still gets it | the list above; the two LLVM integration tests pass with `--release` | met |
| `mylang docs` and `mylang docs primer` work from any directory | `CLI docs lists the embedded guides and prints one from a directory with no docs` (runs in an empty temp directory); unit test over every embedded page | met |
| the primer's examples pass doctest | `mylang doctest . --filter docs/primer.md`: 7 blocks, 4 run, 2 checked, 0 failed | met |
| doc-coverage and the full gate | see *Gate* | see below |

Manual check with the installed compiler:

```console
$ mylang build x.my -o x --report | grep -o '"backend".*'
"backend":"qbe","optimization":"default","lto":false}
$ mylang build x.my -o xr --release --report | grep -o '"backend".*'
"backend":"llvm","optimization":"3","lto":true}
$ mylang test t.my --release --mode Debug; echo $?
2
```

## Measurement: the Lox port's edit → build

The 4,182-line Lox port (`lox-mylang-full`, copied), built as its `bench.json`
builds it (`mylang build main.my --project -o … --cache-dir …`), with a
ReleaseFast compiler of this branch
(`zig build -Doptimize=ReleaseFast -Dcompiler-only --prefix …`), under
`taskset -c 0-11`. Arms: the new default (ReleaseFast on QBE), `--mode Debug`, and
`--release`, which is exactly the old default. Each arm has its own object cache.
The edits are `bench.json`'s four; each is applied, built (the sample), reverted
and built again. Two runs; load average 5.0–6.3 (run 1) and 13.1 → 6.3 (run 2) on
the shared 20-thread machine, so the integrator should re-measure on a quiet one.
The harness and both runs' JSON are in
[`experiments/devspeed-defaults-20260923/`](../../experiments/devspeed-defaults-20260923/)
(run 1 used it before each round's edit was made unique, so its later rounds hit
the object cache and measure only the relink):

```bash
cp -r /home/epentland/ai/trials/devspeed-20260923-private/lox-mylang-full "$W/lox"
taskset -c 0-11 python3 experiments/devspeed-defaults-20260923/lox_edit_build.py \
    "$PREFIX/bin/mylang" "$W/lox" "$W/work" "$W/lox-edit-build.json" --rounds 3
```

Wall seconds of the whole `mylang build` process. "First" is the first build of
an edit, which compiles the changed functions; the ranges cover both runs.

| Arm | cold | no-op | comment edit | leaf body edit (1 fn) | hub body edit (2 fns) | new public function |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **default (QBE, ReleaseFast)** | 10.6–14.3 | 0.35–0.48 | 0.65–0.88 first, 0.38–0.48 again | 0.75–0.89 | 0.79–0.91 | 0.70–0.75 |
| `--mode Debug` (QBE) | 12.3–12.6 | 0.46–0.49 | 0.74–0.82 | 0.76–0.87 | 0.97 | 0.83–0.92 |
| `--release` (the old default) | 11.6–15.9 | 0.33–0.40 | 3.0–3.9 | 4.8–5.0 | 4.5–4.8 | 4.1–5.1 |

- **Edit → build is 5–7× faster by default**: 0.7–0.9 s against 4.1–5.1 s. The
  `--release` time is the LTO link, 2.6–4.4 s on every rebuild whose object set
  changed — including a comment-only edit, which moves positions and relinks
  (3.0–3.9 s against 0.4–0.9 s). The audit's 4 s comment-edit relink reproduces.
- On QBE a build after an edit is now mostly the frontend (0.3 s) plus 0.29–0.44 s
  of codegen for the changed functions' metadata and objects, and a 0.04 s link.
- A no-op build is the same on every arm (the executable-reuse rule keeps the
  release link from being paid twice); a cold build is dominated by per-function
  codegen on every arm (10–14 s here), not by the backend. The audit's 17–39 s
  agent builds combined cold LLVM codegen with the LTO link; the cold cost is
  recommendation 1's, not this lane's.

## Gate

All green on `92c0320a` plus this report's documentation edits, each step under
`slot.sh` and `capbuild`:

| Step | Result |
| --- | --- |
| `zig build test --summary all --maxrss 8000000000` | 80/80 steps; Guardian green; `doc-coverage`: 183 features, 0 failures; `doctest`: 408 files, 180 run, 48 checked, 11 skipped, 0 failed (the primer: 4 run, 2 checked) |
| `zig build test-qbe --summary all` | 49/49 steps, 317/317 tests |
| `zig build test-qbe-build --summary all` | 31/31 steps |
| `zig build fmt-check` | clean |
| `zig-out/bin/mylang test tests/lang` | 569 passed across 106 programs |

## Known gaps and follow-ups

- **Recommendation 2's own acceptance** ("the maintenance trial's mylang toolchain
  seconds under 30 s per task") needs the maintenance trials rerun; this lane
  measured the build loop only.
- **`mylang test --release`** builds each test library with LLVM and LTO, so it is
  slow by design; it exists so the capability `--mode ReleaseFast` used to give
  (LLVM test builds) is not lost. `mylang test --mode ReleaseFast` now builds QBE.
- **Other lanes' measurements.** The scale ladder's `run_scale.py` (outside the
  repository) comments that `mylang build` defaults to LLVM `-O3` + LTO; its
  `mylang` arm now measures the QBE ReleaseFast build. Pass `--release` there to
  keep the old arm, or read the `mylang` arm as the new default.
- **The primer will need edits when other lanes land**: lane 3 changes what a
  test may take ("a test may take `out: Stream`, but not `Filesystem`…"), lane 4
  adds `mylang fix` (to the `--help` first screen and the primer's command list),
  and lane 7 would remove rows from the "not available" table. The primer's
  doctest catches example drift, not prose drift.
- `docs/audits/` and `docs/experiments/` stay under `docs/` (the lane prompt keeps
  them there); `docs/README.md` separates them instead. `mylang doctest` still
  scans them, and `mylang docs` never lists them.
- `mylang docs` prints raw Markdown; relative links inside a page name repository
  paths, which a reader outside the repository cannot follow (the topic names
  are the way between pages).

## For the integrator

Small, localized edits in shared files, in the order a merge will meet them:

- `src/main.zig`: the `everyday_help` block (lane 4 adds its `mylang fix` line
  there), one `docs [TOPIC]` line in `usage`, the `run` usage sentence about
  `--release`, a `docs` dispatch line after `reference`, and `executionOption`'s
  `--qbe=` branch moved into a new `codegenOption` helper (cognitive-complexity
  limit).
- `SPEC.md`: `BUILD-BACKEND-1`/`-2` rewritten in place, `BUILD-RELEASE-1` inserted
  after `BUILD-BACKEND-2`, `BUILD-BACKEND-5` wording; `CLI-HELP-1` rewritten and
  `CLI-DOCS-1` inserted after it.
- `src/features.json`: `release-builds` and `docs-command` after
  `native-default-releasefast`.
- `build.zig`: `addUserDocs` (called for the `mylang` executable and the unit test
  root) and two comments.
- `src/root_test.zig`: one `docs_command.zig` import.
- `src/native_test_options.zig`, `native_test_session.zig`,
  `native_test_directory.zig`: small `--release` hooks; lane 3 (directory runs,
  `--cases`) is likely to touch the same `argv` function.
- `test/integration.zig`: two new tests (after the `BUILD-MODE-1` test and after
  the `CLI-HELP-1` test), extra assertions in the `CLI-HELP-1` test, and
  `--release` added to two LLVM builds.
- Any lane whose benchmark or harness expects LLVM from a plain `mylang build`
  must now pass `--release` (or the explicit flags); `CLAUDE.md`'s "Native builds"
  says so.
