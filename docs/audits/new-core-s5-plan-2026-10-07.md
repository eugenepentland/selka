# New compiler core, stage S5: switch and delete — implementation plan, 2026-10-07

Status: **ready for Codex.** S4 exited on 2026-10-07 (`cbb1d69b` on `claude/s4-p`; report
`experiments/new-core-s4-20261006/finish/REPORT.md`). The user accepted every decision in
§3 on 2026-10-07.

The stage, from the new-core plan (`docs/audits/new-core-plan-2026-10-05.md` §6):

| Scope | Exit check |
|---|---|
| Make the new core the default for release and debug builds. Delete QBE IL emission, the translator, the GC, two-count RC and the old ownership lowering. | The full gate on the new core alone. A deletion count, and a compiler rebuild time below S0's baseline. |

## Launch instruction (for Codex)

> Implement stage S5 of mylang's new compiler core following
> `docs/audits/new-core-s5-plan-2026-10-07.md`. Create `codex/new-core-s5-integration`
> from `claude/s4-p` at `cbb1d69b` (the S4 exit) and merge `claude/new-core-s5-plan`
> into it. Integrate there. Run S5-0, then S5-A, then S5-B with S5-C, then S5-D, then
> S5-X, holding the gates in §6 and the rules in §7. Never merge into `main` and never
> push. Finish with the §8 exit report and stop.

## 1. Where S5 starts

**The new core** (`src/core`, 130 files, 37k lines, plus a 7.8k-line runtime) passes
everything S4 asked of it:
- `tests/lang` (1,518 tests per mode, arena tests excluded);
- the Lox port and the EDA slice, with all 12 build and test times at or below the old
  core's;
- the 46 rows within 1.10× Zig and the old core;
- the dev-loop targets.

It is the separate binary `mylang-core` (`build`, `check`, `test`, `coverage`,
`dump-typed`, `dump-ir`), built only by `zig build core`. It has no `run`.

**The old back end**, inventoried on `34c73982`:

| Part | Size |
|---|---|
| QBE emission, RC lowering and plans, ownership lowering, bytecode IR, the QBE→LLVM translator, the native build driver, per-module native builds, `invoke` | 360 Zig files, about 102k lines (about 26k of them tests) |
| C runtime (`src/*.c`, `*.h`): GC 1.9k lines, two-count RC 5.5k, arenas 0.7k, COW 0.7k | 72 files, 22k lines |
| `vendor/qbe` | 16k lines of C |
| Old-CLI-only code (`main.zig` and its helpers) | 36 files, 17k lines |
| Host apps on the old driver: `board-trial`, `schematic-svg`, `mylang-io` | 6k lines |

**How the two meet.**
- The new core imports the front end (`src/compiler.zig`). That module still imports old
  back-end files: `lower`, `bytecode*`, `qbe`, `qbe_fragments`, the `native_*` facts,
  `ownership_explain`, `mut_callback_abi`, `disassemble`, and re-exports
  `module_compile`, `module_link`, `module_physical` and `module_symbols`.
- `project_compile.zig` (used by `src/core/frontend.zig`) holds `emitQbe*`, lowering,
  fragments and native-test facts.
- `effects.zig`, `mutation.zig`, `incremental.zig`, `external_resources.zig` and
  `runtime_contract.zig` reach `bytecode_model`, `owner_transfer` and
  `native_variant_policy`.
- The only old file the core imports directly is the generated
  `qbe_build_assets.compiler_identity` (`build_qbe_assets.zig`), in
  `src/core/frontend_reuse.zig`.

**The CLI.**
- **Reach the old back end:** `mylang build`, `run`, `run-project`, `test`, `doctest`,
  `invoke`, `compile-module`, `link-modules`, `packages build`, `emit-qbe*`,
  `emit-runtime` and `dump-bytecode`.
- **`check`:** on a project it runs `module_build.check`, which reads `compile-module`
  records lowered through the old back end.
- **Front end only:** the formatter, lint, API and navigation commands.

**Tests.**
- **`src/*_test.zig`:** about 1,700 of the 2,200 Zig tests build and run programs.
  About 1,165 of them, in 109 files, go through one helper,
  `native_execute.run(compilation)` and its variants.
- **`test/integration.zig`:** 293 CLI tests; it calls `run` 193 times.
- **`tests/lang`:** the gate runs it under RC and again under GC stress.
- **Old-core oracles:** `tests/goldens/qbe_*.json` (683 KB), the S3/S4 conformance and
  fuzz tools, and the 46-row timing tool all use the old core as their reference.

**The gate today.** `zig build test` takes about 15 minutes (878 s on `34c73982`) and does
not run `test-core`. `test-qbe` takes 67 s and `test-qbe-build` 4 s.

**SPEC.** About 450 of 1,479 bullets describe the old back end (QBE-, RC-, NATIVE-, GC-,
ARENA-, COW-, LLVM-).

## 2. What S5 delivers

- **One binary:** `mylang` runs the new core for every command that builds or runs code.
  `mylang-core` goes, and `zig build` installs no QBE.
- **The old back end is deleted:**
  - QBE and its IL emission;
  - the translator;
  - the GC and two-count RC with their C runtime;
  - the old ownership lowering;
  - bytecode IR;
  - the native build driver;
  - `invoke` and the host apps;
  - the front-end code only they used.
- **The gate runs on the new core alone.** `tests/lang` runs through the new `mylang test`.
- **The old core's answers survive as frozen references** (S5-0). The oracle binaries stay
  outside the repo.

## 3. Decisions (all accepted by the user, 2026-10-07)

- **S5-D1. Rollout: one switch.** Release and debug builds move together. S4 qualified
  both modes the same way. *(The new-core plan said release first.)*
- **S5-D2. The oracle: frozen.** Before anything is deleted (S5-0):
  - the old core's outputs become reference files in the repo;
  - the oracle binaries (old core `d36658db…`, QBE `b6139650…`) are archived under
    `~/.cache/mylang/oracles/` with a manifest of their SHA-256, for differential runs
    during S5;
  - after S5, fuzzing compares the new core's debug, release and verify builds with each
    other and with the frozen references.
- **S5-D3. Arenas: a plain block with a warning.**
  - `with arena():` still parses and runs as an ordinary block, as the new core already
    lowers it, and warns `W_ARENA_RETIRED`;
  - `mylang fix` removes it;
  - `E_ARENA_ESCAPE` and the other arena checks, the 118 arena tests and
    `docs/arenas.md` go.
- **S5-D4. GC and runtime modes: deleted.**
  - The flags: `--gc-runtime`, `--gc-stress`, `--rc-runtime`, `--legacy-sharing`,
    `--value-semantics`.
  - Their gate steps: `test-lang-gc`, `test-legacy-sharing`, `test-value-semantics`.
  - Legacy sharing mode (front-end plan A8) goes with them.
  - One-count RC is the only memory model.
- **S5-D5. Host functions and host apps: retired.**
  - What goes: `host def`, `invoke`, `--library`, `--provider`,
    `--link-library`/`--library-path`, and the `board-trial`, `schematic-svg` and
    `mylang-io` apps with their gate steps.
  - Only those apps, one native fixture and one core test use `host def`.
  - `extern` with `--link FILE.c` stays and covers C interop.
- **S5-D6. Old test-runner flags.**
  - **Ported:** `--affected`/`--against`, `--no-cache`, and `--report` (as the cache
    report).
  - **Accepted and ignored:** `--whole-program`; release is whole-program since S4-1a.
  - **Dropped:** `--bench*`, `bench-promote`, `--pure-skip`, `--diagnostics` and
    `--max-calls`.
- **S5-D7. SPEC: retired, not ported.** The old back end's bullets are deleted with their
  tests, as `docs/design/new-core-s2.md` §10 item 7 says. Behaviour the new core keeps
  already has `NEW-CORE-*` bullets; a gap found on the way gets a new one.
- **S5-D8. One binary.** `mylang-core`'s commands become `mylang` commands; `dump-ir` and
  `coverage` stay as developer commands. This is front-end plan C0's last item and the
  N2 plan.

## 4. Work packages

**One owner per shared file per wave,** as in S3 and S4.

### S5-0. Freeze the oracle (coordinator; about 2–3 h; first)

**References,** recorded with the old core at `d36658db…`. Keep them small, within the
10 MB rule (§7): expected stdout, exit status and trap code per case, never build trees.
- **Conformance:** for every `tests/lang` test, the old core's verdict and trap code, as
  `conformance.py` compares them.
- **Fuzz:**
  - For each of the 9 kinds, the matrix's 200 cases: seed, source hash and the old core's
    expected outputs.
  - If the generator is not deterministic for a seed, store the sources too, compressed.
- **The 46 rows:** the old core's cycles per unit from `x-all46-01.json` (S4 exit, 7
  rounds) become the frozen old-core column.
- **`tests/goldens/qbe_*.json`:** these already hold expected outputs. Only the runner
  changes, in S5-C.

**Tools.** Copy S3's qualification tools into `experiments/new-core-s5-<date>/tools/`
with two changes each: the oracle is the references, and the compiler under test is a
flag (`mylang-core` until S5-A lands, then `mylang`).
- `qualify_merge.py`: install, `test-core`, conformance against the references;
- `fuzz_matrix.py`: against the frozen corpus;
- the 46-row tool: against the frozen old-core column.

**Archive** the two oracle binaries with their manifest.

**Exit:** on `cbb1d69b`, each new tool gives the same verdicts against the references as
the S3 tool gives against the live oracle.

### S5-A. One binary (one agent; about 6–10 h)

**`mylang build`, `build --run`, `run`, `run-project` and `test`** call the new core's
pipeline (`src/core/pipeline.zig`, `driver.zig`, `test_runner.zig`).

**`run` keeps CLAUDE.md's contract:**
- **Exit status:** `main`'s value `& 0xFF`; a trap exits 1, check errors 1, usage and
  host failures 2.
- `--print-result`.
- **Grants:** `--restrict`, `--allow-*` and `MYLANG_OPTIONS`.
- **Budgets:** `--max-steps`, `--max-frames`, `--timeout`, `--max-memory`. A run defaults
  to 4 GiB, from `MYLANG_MEMORY_LIMIT` when it is set; the runtime backs the ceiling with
  `RLIMIT_AS`, as the core's test runner already does (NEW-CORE-S4-MEMORY-1).

**`check` on a project** uses S4-2's path, the merged check plus the semantic cache,
instead of `module_build.check` and `compile-module` records. This is front-end plan C0's
first item.

**`doctest`** runs on the new `run`.

**One binary:**
- `mylang-core`'s commands join `mylang` (S5-D8);
- `zig build` installs `mylang` built with the new core;
- the old back end stays in the tree, unreachable from these commands, until S5-D.

**The S5-D3, S5-D4 and S5-D5 flags and commands** are refused with a short message that
names the retirement. `with arena():` warns.

**Exit:**
- every `test/integration.zig` test that runs `build`, `run` or `test` passes on the new
  path, or is listed for S5-C with its reason;
- `zig build test-docs` passes;
- conformance and `test-core` pass;
- S4's dev-loop and port numbers hold.

### S5-B. Gaps the switch exposes (one agent; about 3–6 h; with S5-C)

- **Capabilities in collections:** `[N]Stream` and lists of capabilities. Old-core
  programs used them; the core refuses them today.
- **`extern`** with an aggregate ABI or a `mut` parameter.
- **The S5-D6 flags:** `--affected`/`--against`, `--no-cache` and `--report`.
- **Anything S5-A and S5-C list as refused** that the old core accepted and no
  retirement covers.

### S5-C. Tests onto the new core (two agents, split by test area; about 10–16 h)

**Retarget** `native_execute.run`, `runWithOptions`, `runUnaccounted` and `runWithPolicy`
to the new core. A `gc_stress` option or a GC/legacy policy marks a test for deletion
(S5-D4). Then retarget `test/integration.zig` and `test/golden_parity.zig`.

**Classify every test that then fails:**
1. **The new core is wrong.** Fix the core, through S5-B if it is a missing feature.
2. **The test asserts old internals:** QBE text, RC plans, GC counts, bytecode, the old
   cache layout. Delete it with its SPEC bullet (S5-D7). The commit names the old file it
   asserted on.
3. **The test asserts a retired feature** (S5-D3 to D5). Delete it with its bullet.

**Gate steps:**
- `test-lang` runs `tests/lang` through the new `mylang test` in debug, and in release
  with the leak and verify checks;
- `test-lang-gc`, `test-legacy-sharing` and `test-value-semantics` go;
- `test-core` joins `zig build test`.

**Exit:**
- the counts per class, and per file for classes 2 and 3;
- nothing deleted for any other reason;
- `zig build test` green with the old back end still in the tree but reached by no test.

### S5-D. Delete (one agent; about 8–12 h; after S5-A, S5-B and S5-C)

**Old back end:**
- `vendor/qbe`, the old back-end and C runtime files of §1, and `main.zig`'s old-only
  commands;
- `build.zig`'s QBE, native-harness, host-app and runtime-asset steps (`build_qbe_assets.zig`
  goes once `src/core/frontend_reuse.zig` takes its compiler identity from the new
  core's own sources);
- `guardian.toml`'s roots.

**Front end (front-end plan C0):**
- Cut `src/compiler.zig`'s and `project_compile.zig`'s imports of old files.
- `fix_command.zig` drops its imports of `qbe_build_io.zig` and `native_test_snapshot.zig`.
  Move the general I/O helpers it needs into a front-end file.
- Delete what only the old back end used, about 1.0k lines:
  - `bytecode_model.zig`;
  - the bytecode validators (`effects.zig`, `mutation.instruction`);
  - the VM parts of `runtime_values.zig` and `io_render.zig`;
  - `mut_abi`'s caller-storage ABI;
  - `value_semantics.zig`'s lowering facts;
  - the typed fields `owned_cleanup`, `caller_storage`, `borrow_origin` and
    `loop_exit.arenas`.
- Delete legacy sharing (A8), about 1k lines: `alias_warning.zig`, the overlap path in
  `origins`, and the `class`/`Cell` branches.
- Move `typed.Type` out of `runtime_values.zig` into the type catalog.

**SPEC, docs and repo instructions:**
- the retired SPEC bullets (S5-D7);
- `features.json`: `primary_backend` set to `llvm`, and the old entries deleted, with
  `mylang doc-coverage .` green;
- docs: `docs/tooling/native-build.md` rewritten for the new driver; `arenas.md` and
  `managed-memory.md` deleted; `caches.md`, `runtime-budgets.md`, `ownership.md`,
  `guest-tests.md` and `c-ffi.md` updated;
- `CLAUDE.md`'s build, gate, runtime, memory and native-build sections, and `README.md`.

**Exit:**
- the full gate on the new core alone;
- the deletion count (files and lines: Zig, C, tests, SPEC bullets, docs).

### S5-X. Exit (coordinator; about 3–4 h)

- the full gate, with its time;
- `fuzz_matrix.py`, 9 kinds × 200, against the frozen corpus and across the new core's
  debug, release and verify builds;
- conformance in both modes with leak and verify, against the references;
- the 46 rows against Zig and the frozen old-core column;
- Lox and EDA build and test times (`measure_ports.py`, three runs, medians);
- the dev-loop table (S4 §6);
- the compiler rebuild time after a one-line edit;
- the deletion count.

## 5. Order

| Wave | Packages | Notes |
|---|---|---|
| 0 | S5-0 | before anything else |
| A | S5-A | the switch |
| B | S5-B and S5-C in parallel | S5-C as two agents by test area; at most four build-heavy agents |
| C | S5-D | after B; mechanical once nothing reaches the old back end |
| X | S5-X | |

**Total: about 32–51 hours of work.** S5-C is the widest range: how many of the 1,700
retargeted tests expose behaviour the new core still lacks.

**Alongside S5.** These touch `src/core/` only:
- **Package DL** (debug LLVM speed, `claude/debug-llvm-plan`).
- **The front-end plan's FB1** (per-function cost report).

Each can run beside S5-0 to S5-C, on its own branch from `cbb1d69b`. It merges into
the S5 integration before S5-D, with S5's gates. The front-end plan's F0–F5 start after
S5's exit, as planned.

## 6. Gates

**Before S5-C changes the gate,** every merge holds S4's gates (S4 plan §6):
- `test-core` and conformance at 0 mismatches, now against the S5-0 references;
- 50 fuzz cases per kind for packages that touch code generation or the runtime;
- the full old gate for any package that touches files outside `src/core/`.

**From S5-C on:**
- The gate is `zig build test`, which now includes `test-core` and the new `test-lang`,
  plus `fmt-check`.
- `test-qbe` and `test-qbe-build` stay until S5-D deletes them, and pass until then.

**Every package:**
- S4's dev-loop targets still hold;
- the Lox and EDA numbers do not regress beyond noise: measure with three runs and take
  the median before calling a regression.

## 7. Rules

S4's §7 rules still apply:
- a wrong answer is never acceptable;
- the machine rules, and builds through `scripts/build-slot.sh`;
- timing on CPU 10 only;
- one log per command run;
- persisted formats bump their version when they change;
- "How much qualification": qualify with the S5-0 tools unchanged, build no new
  qualification machinery, and commit evidence of at most 10 MB per package;
- never run the full gate beside a fuzz matrix;
- reduce a fuzz mismatch to a regression fixture before fixing it;
- no pushes and nothing merged into `main`.

**New in S5:**
- **Delete only behind a green gate.** A deletion lands only when the gate is green
  without the deleted code, never by skipping or weakening a test.
- **Name what each deleted test asserted.** A test deleted as old internals (S5-C class
  2) names the old file it asserted on.
- **`ir.zig` stays frozen.** A package that thinks it needs an IR change stops and reports.
- **The oracle binaries are never rebuilt.** If a reference looks wrong, rerun the
  archived binary; the references are never edited by hand.
- **Before deleting a doc or SPEC section,** check `src/features.json` and
  `mylang doc-coverage .`. A feature the new core keeps must keep a documented section
  with a runnable example.
- **`/tmp` has a per-user quota.** Keep `TMPDIR` and caches on disk; a full quota makes
  test processes exit 70.

## 8. S5 exit check and report

**Exit:**
- the full gate on the new core alone, with no QBE, old runtime or old back end in the
  build;
- every `tests/lang` file passes through `mylang test`;
- the Lox port and the EDA slice pass, with S4's build and test times or better;
- the 46 rows within 1.10× Zig and 1.10× the frozen old-core column;
- the compiler rebuild after a one-line edit is below S0's baseline of 20–31 s (the
  new-core plan's target is 10 s).

**The report:**
- package commits;
- the deletion count;
- the S5-C classification counts;
- the gate time;
- the dev-loop table;
- the port and row tables;
- fuzz, conformance, leak and verify;
- every remaining limit.

It then stops for the user.
