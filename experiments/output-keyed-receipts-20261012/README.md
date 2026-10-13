# Output-keyed, path-free, shared verification: acceptance harness

This directory qualifies the plan in
[`docs/audits/output-keyed-shared-receipts-plan-2026-10-12.md`](../../docs/audits/output-keyed-shared-receipts-plan-2026-10-12.md)
(Lane F). It holds:

- `matrix.py`, which runs the thirteen rows of the plan's acceptance matrix
  (Section 4) as independent, re-runnable cases against a target worktree and
  judges each against the plan's expected decision;
- `matrix_test.py`, unit tests of the judging logic over recorded reports;
- [`cohorts.md`](cohorts.md), the Section 5 measurement cohorts as command
  sequences with their frozen manifests and baselines;
- [`phase2-checklist.md`](phase2-checklist.md), the documentation, feature-slug
  and integration-gate work that lands once Lanes B to E are merged;
- `fixtures/`: recorded reports for the tests and the row 8 environment probe.
  The source edits of rows 2 to 5 and 9 are in `matrix.py` (`EDITS`, `ROW9_*`).

The harness is developer tooling. It never enters the install graph and is not
declared in `build_test_inputs.zig`. Run it with `python3 -B`.

## Running it

Source the shared environment first; the harness refuses to run without `ZIG`
and `MYLANG_SLOT_DIR`:

```bash
source ~/.config/mylang/dev-env.sh
H=experiments/output-keyed-receipts-20261012
python3 -B $H/matrix_test.py                              # judging logic, no builds
python3 -B $H/matrix.py --tree "$PWD" --dry-run           # every planned command, nothing run
python3 -B $H/matrix.py --tree "$PWD" --rows 1:lang-debug --lang-entry tests/lang/frontend_numbers.my
python3 -B $H/matrix.py --tree /path/to/integration --rows 1,6,8,9,10,11:same-compiler
python3 -B $H/matrix.py --tree /path/to/integration --heavy            # all rows, scheduled
```

- `--tree PATH` is the worktree under test. Its installed `zig-out/bin/mylang`
  is the compiler for rows that do not rebuild; its `HEAD` seeds every scratch
  worktree. Build it first (`scripts/build-slot.sh build zig build`).
- `--rows` takes row numbers, optionally with a sub-case (`1:lang-debug`,
  `8:ld-preload`, `11:same-compiler`). The default is every row.
- Sub-cases marked heavy (a complete verification, a scratch compiler build or
  two) are skipped unless `--heavy` is given. `--dry-run` lists them all.
- `--lang-entry` replaces `tests/lang` in rows 1 to 6 for cheap smoke runs; a
  qualification uses the default. `--small-entry` is the entry of the negative
  controls and row 13 (default `tests/lang/frontend_numbers.my`).
- `--old-ref` is the pre-bump commit of row 13 (default `f6971a623`, the Lane A
  integration commit, which still writes v2 namespaces).
- `--build-env PATH` names the `build-env` host tool for rows 8 (projection)
  and 12 when it is not installed under `zig-out`.
- `--manifest-only LABEL` writes the frozen manifest to
  `evidence/manifests/LABEL.json` and runs nothing (used by the cohorts).
- `--keep-work` keeps scratch worktrees for inspection.

## The rows

| Row | Sub-cases | What it runs | Judging fields |
| --- | --- | --- | --- |
| 1 | `lang-debug`, `lang-facts-leak`, `complete` | `mylang test tests/lang` twice (debug; `--release --verify-facts` with `MYL_CORE_LEAKCHECK=1`), private cache; the coordinator twice | `cache.reason` and status per test; `last-run.json` action `state`, `action_key`, `language` `test_telemetry.executed` |
| 2 | `edit` | scratch worktree: build, warm `tests/lang`, comment-only `src/parser.zig` edit, rebuild, rerun | IR-tier reasons absent; `exec-receipt-hit` for every eligible test; zero executed; `exec_receipts.hits`; wall time recorded |
| 3 | `edit` | scratch worktree: a side-effecting `nop` in the whitespace-split cursor emitter, rerun, then a `--force` run | per-test outcome equality with `--force`; 0 < executed < eligible; per-test `program_key` when reported |
| 4 | `edit` | scratch worktree: comment in `src/core/test_runner_execute.zig` (a `runner_identity` input) | zero exec hits, zero IR hits |
| 5 | `edit` | scratch worktree: a retained static function appended to `src/core/runtime/core_rt.c` | zero exec hits |
| 6 | `modes` | facts, facts, leak, leak, facts, facts `--force` on one cache | hit/miss pattern by `cache.reason` and status |
| 7 | `two-worktrees` | two scratch worktrees at `HEAD` with different `CODEX_THREAD_ID`, `TERM`, `PWD`, `TMPDIR`, one row-private shared store; `tests/lang` and the coordinator in each | B's eligible tests all reused; all `action_key`s equal; B states only `reused`/`fresh`; `budget_context` equal; per-action `path_free`; `grep -a` root-path counts in installed `units`/`core`/`cli` |
| 8 | `memory-limit`, `ld-preload`, `projection` | warm then `MYLANG_MEMORY_LIMIT=600M`; `LD_PRELOAD=libc` twice on a fresh cache; `fixtures/env_probe.my` with and without `build-env project` | zero hits; `untracked-loader-environment`; probe exit status |
| 9 | `helper-edit` | scratch worktree, target compiler: break `replace_dict` in `tests/lang/mut_rebind_helpers.my`, rerun `mut_rebind_modules.my`, restore, rerun | the reaching test `failed`, the other `cached`, exit 1; then no failures |
| 10 | `forged-record` | build `examples/collatz.my` into a row-private shared store, rewrite the program record with different self-consistent bytes, drop replay, rebuild | build exit status; any `*mismatch*` counter in `cache-report-v1`; `mismatches.log` lines; forged record unchanged; the harness's integration check |
| 11 | `same-compiler`, `own-compilers` | `examples/collatz.my` built debug and `--release` from two roots | equal `sha256`; zero `grep -a` root-path occurrences; `program_key` when reported |
| 12 | `complete` | scratch worktree: the coordinator under `build-env project` with `--force` and a private shared evidence store | exit 0 and `success` |
| 13 | `test-receipts`, `coordinator` | old compiler (`--old-ref`) then the target compiler on one cache dir, then the old one again; a scratch coordinator seeded with the target's v2 evidence, run twice | new compiler: zero hits and zero failures, then all hits; old compiler still hits; a `-v3` namespace; v2 digest unchanged; first v3 gate reuses nothing, second reuses all cacheable groups |

A check whose field or mechanism does not exist on the target tree is recorded
as `not-judged` with the missing feature named (the features are probed
statically at start and listed by `--dry-run`); it is never a pass. A row's
decision is `fail` if any check fails, `error` if a harness step failed, `pass`
if every check passed, `partial` if some passed and the rest were not judged,
and `not-judged` if nothing could be judged. Rows 1 to 6 count a test as
*eligible* unless its `cache.reason` is one of the documented refusals
(`live-effects`, `native-links`, `uncacheable-toolchain`,
`untracked-loader-environment`, `uncacheable-metadata`, skipped, unsupported);
`verify-facts`, `leak-check` and `missing-cache-plan` count as misses, because
the plan expects those tests to hit.

## Isolation and admission

- Rows that edit sources (2, 3, 4, 5, 9) edit a scratch worktree created with
  `git worktree add --detach` under `work/`, never the target tree, restore the
  file and remove the worktree in steps that run even after a failure. Rows 7,
  11, 12 and 13 create their worktrees the same way. Scratch worktrees sit
  directly under `work/`, beside a `work/guardian-zig` link to the target's
  `../guardian-zig`, so the build's relative Guardian dependency resolves.
- Every command run in a tree gets that tree's `ZIG_LOCAL_CACHE_DIR`, `TMPDIR`
  and `PWD`, as sourcing `dev-env.sh` there would. `mylang test` and
  `mylang build` runs also get row-private `MYLANG_TEST_SHARED_CACHE` and
  `MYLANG_COMPILER_SHARED_CACHE`, so no other agent's store decides a row (row 7
  gives both worktrees the same private store on purpose). Coordinator runs get
  nothing else, so their identities match an ordinary run in that tree. When
  the target tree has the `MYLANG_TEST_EXEC_RECEIPTS` switch (rollout week 2),
  the harness sets it to `1` and records it.
- Builds and `mylang` runs go through `scripts/build-slot.sh build`. Complete
  verification runs `python3 -B scripts/verify_cache.py --zig "$ZIG" --profile
  complete` directly: the coordinator owns its admission and must not be wrapped.
- Row 1's `complete` sub-case runs in the target tree and writes its normal
  `.mylang-cache` evidence there; nothing else touches the target tree.
- The machine is shared. Run heavy rows one at a time, in a scheduled window;
  rows 7, 12 and 13 each include a cold complete verification.

## Evidence

Each sub-case writes `evidence/<row-id>/<sub-case>/`:

- `NN-<step>.stdout` and `.stderr` for every command, and for coordinator
  steps a copy of `last-run.json` (`NN-<step>.last-run.json`);
- `result.json`: the decision, every check with expected and observed values,
  every step (argv, cwd, the environment the harness set or unset, exit status,
  harness timestamps and the harness's wall clock *including admission queue*,
  report summaries) and the SHA-256 of each compiler used.

`evidence/<row-id>/row.json` adds the frozen manifest (compiler and harness
SHA-256, tree `HEAD` and dirty-state digest, options, probed features, the
environment projection with launcher variables by digest only).
`evidence/summary.json` collects every row's latest decision. The harness clock
is not a measurement: timed cohorts follow [cohorts.md](cohorts.md).
`evidence-phase1-smoke/` holds the phase 1 smoke run on the Lane A integration
tree.

## Measurement protocol (plan Section 5)

- **Frozen manifests.** Before a cohort, write its manifest
  (`matrix.py --manifest-only LABEL`): compiler hash, tree hash and dirty
  digest, options, environment projection. Re-hash the compiler after the
  cohort; a changed hash voids it.
- **Exclusive timing windows.** Timed commands run under
  `scripts/build-slot.sh timing …`, except the coordinator, which takes its own
  window with `--timing-window-seconds`. Builds that prepare a sample run under
  `build`, outside the window.
- **Queue time recorded separately.** Record admission wait (the coordinator's
  `admissions[].admission_wait_seconds`; the `build-slot:` line for wrapped
  commands) beside each sample; never add it to the sample.
- **No summing of overlapping steps.** Zig build-summary steps and coordinator
  members overlap; report the request window and gate occupancy, never a sum of
  step durations.
- **Small samples.** Five samples support a decision (a median and a range);
  they do not support a p95 claim. Report every sample and every unknown.
