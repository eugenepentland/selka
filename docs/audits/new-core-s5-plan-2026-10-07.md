# New core S5 plan: switch and delete, 2026-10-07

Status: **draft for the user's decisions (§3).** Base: the S4 exit `cbb1d69b` on `claude/s4-p`
(report `experiments/new-core-s4-20261006/finish/REPORT.md`). Nothing is pushed or merged
into `main`.

## 1. Goal and exit

From the new-core plan (§6): make the new core the default for release and debug builds,
then delete QBE IL emission, the translator, the GC, two-count RC and the old ownership
lowering.

**Exit:**
- the full gate passes on the new core alone, with no QBE, old runtime or old back end
  left in the build;
- every `tests/lang` file passes through `mylang test` (arena files per S5-D3);
- the Lox port and the EDA slice pass, with S4's build and test times or better;
- the 46 rows within both 1.10 gates (release code generation is unchanged by S5, so
  this is a check, not new work);
- a deletion count, and a compiler rebuild time below S0's baseline (20–31 s after a
  one-line edit);
- a gate time report: today `zig build test` alone takes about 15 minutes.

## 2. What exists today

Measured on `34c73982` (inventory 2026-10-07).

| Part | Size |
|---|---|
| Old back end in `src/` (QBE emission, RC lowering and plans, ownership lowering, bytecode IR, the QBE→LLVM translator, the native build driver, per-module native builds, `invoke`) | 360 Zig files, about 102k lines (about 26k of them tests) |
| Old C runtime (`src/*.c`, `*.h`): GC 1.9k lines, two-count RC 5.5k, arenas 0.7k, COW 0.7k | 72 files, 22k lines |
| `vendor/qbe` | 16k lines of C |
| Old-CLI-only code (`main.zig` and its helpers) | 36 files, 17k lines |
| Host apps on the old driver: `board-trial`, `schematic-svg`, `mylang-io` | 6k lines |
| The new core (`src/core`) | 130 files, 37k lines, plus a 7.8k-line runtime |

**How the two cores meet.** The new core imports the front end (`src/compiler.zig`). That
module still imports old back-end files: `lower`, `bytecode*`, `qbe`, `qbe_fragments`,
`native_*` facts, `ownership_explain`, `mut_callback_abi` and `disassemble`; and
`project_compile.zig`, `effects.zig`, `mutation.zig`, `incremental.zig`,
`external_resources.zig` and `runtime_contract.zig` reach `bytecode_model`,
`owner_transfer` and `native_variant_policy`. That is about 8k lines of front-end code to
untangle.

**Tests.**
- About 1,700 of the 2,200 Zig tests in `src/*_test.zig` build and run programs. Most go
  through one helper, `native_execute.run(compilation)`, used by 109 files.
- `test/integration.zig` has 293 CLI tests; it calls `run` 193 times.
- `tests/lang` has 1,623 test functions; the gate runs them under RC and again under GC
  stress.
- `tests/goldens/qbe_*.json` (683 KB) and the S4 fuzz and conformance tools all use the
  old core as the oracle.

**CLI.** `mylang build`, `run`, `run-project`, `test`, `doctest`, `invoke`,
`compile-module`, `link-modules` and `packages build` reach the old back end. `check`, the
formatter, lint, API and navigation commands are front end only. `mylang-core` has
`build`, `check`, `test`, `coverage` and `dump-*`, and no `run`.

**SPEC.** About 450 of 1,479 bullets describe the old back end (QBE-, RC-, NATIVE-, GC-,
ARENA-, COW-, LLVM-).

## 3. Decisions for the user

Each has a recommendation. The packages in §4 assume the recommendations.

- **S5-D1. Rollout: one switch.** Release and debug move to the new core together. S4
  qualified both modes the same way; switching them separately doubles the qualification
  for no gain. *(The new-core plan said release first.)*
- **S5-D2. The oracle after deletion: freeze it.** Before anything is deleted (S5-0),
  record the old core's outputs as goldens in the repo: the conformance corpus, a fixed
  fuzz corpus of 9 kinds × 200 with expected outputs, and the `tests/goldens` cases. Keep
  the oracle binaries (old core `d366…`, QBE `b613…`) outside the repo under
  `~/.cache/mylang/oracles/` for differential runs during S5. After S5 the fuzzer compares
  the new core's debug, release and verify builds with each other and with the frozen
  corpus.
- **S5-D3. Arenas: a plain block with a warning.** `with arena():` keeps parsing, runs as
  an ordinary block (as the new core already lowers it) and warns `W_ARENA_RETIRED`.
  `mylang fix` removes it. `E_ARENA_ESCAPE` and the other arena checks, the 118 arena
  tests and `docs/arenas.md` go. *(Alternative: a hard error now. Either way, N6 retired
  arenas.)*
- **S5-D4. GC and runtime modes: delete.** `--gc-runtime`, `--gc-stress`, `--rc-runtime`,
  `--legacy-sharing` and `--value-semantics`, and the `test-lang-gc`,
  `test-legacy-sharing` and `test-value-semantics` gate steps. One-count RC is the only
  memory model.
- **S5-D5. Host functions and the host apps: retire.** `host def`, `invoke`,
  `--library`, `--provider`, `--link-library`/`--library-path`, and the `board-trial`,
  `schematic-svg` and `mylang-io` apps. `host def` is used only by those apps, one
  native fixture and one core test. `extern` with `--link` stays and covers C interop.
  *(Alternative: port host functions and the three apps to the new driver, about 8–12 h
  more.)*
- **S5-D6. Old test-runner flags.**
  - Port `--affected`/`--against`, `--no-cache`, and `--report` (as the cache report).
  - Accept `--whole-program` as a no-op: release is whole-program since S4-1a.
  - Drop `--bench*` and `bench-promote`, `--pure-skip`, `--diagnostics` and `--max-calls`
    unless you use them.
- **S5-D7. SPEC: retire, don't port.** Delete the old back end's bullets with their tests,
  as `docs/design/new-core-s2.md` §10 item 7 says. Behaviour the new core keeps already
  has `NEW-CORE-*` bullets; any gap found gets a new one.
- **S5-D8. One binary.** `mylang` runs the new core for `build`, `run`, `run-project` and
  `test`. `mylang-core`'s commands become `mylang` commands and the separate binary goes;
  `zig build` installs `mylang` and nothing QBE.

## 4. Packages

### S5-0. Freeze the oracle (coordinator, about 2–3 h)
- Record the goldens of S5-D2 with the old core at `d366…`. They must stay small (S4 §7):
  expected stdout, status and trap kind per case, not build trees.
- Archive the two oracle binaries with their SHA-256 in a manifest.
- New qualification tools read the goldens:
  - `qualify_merge.py` (install, `test-core`, conformance against goldens);
  - `fuzz_matrix.py` against the frozen corpus.
- **Exit:** the tools pass on the S4 exit commit against the goldens, with the same
  results as against the live oracle.

### S5-A. One binary (one agent, about 6–10 h)
- `mylang build`, `run`, `run-project`, `build --run` and `test` call the new core's
  pipeline.
- **`run`:**
  - the exit status (`& 0xFF`; a trap exits 1, check errors 1, usage 2);
  - `--print-result`;
  - grants (`--restrict`, `--allow-*`, `MYLANG_OPTIONS`);
  - budgets (`--max-steps`, `--max-frames`, `--timeout`, `--max-memory`, with the 4 GiB
    run default and `MYLANG_MEMORY_LIMIT`), as CLAUDE.md states them.
- `check` on a project no longer goes through `module_build.zig`.
- `doctest` runs on the new `run`.
- `mylang-core`'s commands move into `mylang` (S5-D8); `dump-ir` and `coverage` stay as
  developer commands.
- **Exit:**
  - `test/integration.zig`'s `run`, `build` and `test` tests pass on the new path, or are
    listed with their reason;
  - `zig build test-docs` passes;
  - the dev-loop numbers match S4's.

### S5-B. Gaps the switch exposes (one agent, about 3–6 h, parallel to S5-C)
- Capabilities in collections (`[N]Stream`, lists of capabilities).
- `extern` with an aggregate ABI or a `mut` parameter.
- The S5-D6 flags.
- Whatever S5-A and S5-C list as refused.

### S5-C. Tests onto the new core (two agents, about 10–16 h)
- Retarget `native_execute.run` and its variants to the new core: about 1,165 tests in
  109 files.
- Retarget `test/integration.zig`.
- Then classify every failure:
  - the new core is wrong: fix it;
  - the test asserts old internals (QBE text, RC plans, GC counts, bytecode): delete it
    with its SPEC bullet;
  - the test asserts a retired feature (S5-D3 to D5): delete it.
- `test-lang` runs `tests/lang` through the new `mylang test` in debug, and in release
  with the leak and verify checks. `test-lang-gc`, `test-legacy-sharing` and
  `test-value-semantics` go (S5-D4).
- `test-core` joins `zig build test`.
- **Exit:**
  - the counts per class;
  - no test deleted for a reason other than those three classes.

### S5-D. Delete (one agent, about 8–12 h, after S5-A to S5-C)
- **Code:** `vendor/qbe`, the old back-end and C runtime files of §2, and `main.zig`'s
  old-only commands.
- **Front end:** cut its imports of old files (§2, about 8k lines).
- **Build:** `build.zig`'s QBE, native-harness and host-app steps; `guardian.toml` roots.
- **Retired features:**
  - the retired SPEC bullets (S5-D7);
  - `features.json`: `primary_backend` set to `llvm`, and the old entries deleted;
  - docs: `docs/tooling/native-build.md` rewritten, `arenas.md` and `managed-memory.md`
    deleted;
  - `CLAUDE.md`'s build, gate, runtime and memory sections.
- **Exit:** the full gate on the new core alone, and the deletion count.

### S5-X. Exit (coordinator, about 3–4 h)
- the full gate;
- 9 × 200 fuzz against the frozen corpus;
- conformance in both modes, with leak and verify;
- the 46 rows;
- Lox and EDA times;
- the dev-loop table;
- the compiler rebuild time and the gate time;
- the deletion count.

## 5. Order and estimate

| Wave | Packages | Notes |
|---|---|---|
| 0 | S5-0 | before anything else |
| A | S5-A | the switch |
| B | S5-B and S5-C in parallel | S5-C may split into two agents by test area |
| C | S5-D | after B; the deletion is mechanical once nothing reaches the old core |
| X | S5-X | |

**Total: about 32–51 hours of work,** with S5-D5's alternative adding 8–12. S5-C is the
widest range: how many of the 1,700 tests assert behaviour the new core does not have yet.

**Alongside S5:** package DL (debug LLVM, `claude/debug-llvm-plan`) touches the core's
debug emission and link flags. It can run in parallel with S5-0 and S5-A if it merges
before S5-D. The front-end plan's FB1 waits for S5-A, and F0–F5 for S5's exit, as planned.

## 6. Rules

S4's §7 rules still apply, including "How much qualification":
- S3's tools until S5-0, the golden-based tools after it;
- 50 fuzz cases per kind per package, 200 at S5-X;
- evidence under 10 MB per run;
- no pushes and nothing merged into `main`;
- builds through `scripts/build-slot.sh`; timing on CPU 10 only.

**New for S5:** a deletion lands only when the gate is green without the deleted code,
never by skipping a test. A test deleted as "old internals" must name the old file it
asserted on.
