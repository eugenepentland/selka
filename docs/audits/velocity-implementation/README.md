# Development velocity: execution ledger

Status: **W0 in progress — baseline established, contracts frozen 2026-09-15.**

Plan: [development-velocity-implementation-plan-2026-09-15.md](../development-velocity-implementation-plan-2026-09-15.md)
Handoff: [development-velocity-agent-handoff-2026-09-15.md](../development-velocity-agent-handoff-2026-09-15.md)

This directory is the W0 deliverable. One row per package. The integrator owns
this file; feature agents report their commit SHA and evidence through their
completion report, and the integrator writes the row.

## Baseline

| Item | Value |
| --- | --- |
| Selected baseline commit | `9ce142e98cb22e684622ed1d5678071d6944206e` |
| Baseline parent | `a9e29d4845ab2f8a700eeb238ed03023d2ac701e` (audit HEAD) |
| Baseline content | audit HEAD plus the previously uncommitted named-constraint review fixes and the 2026-09-15 audit/plan/handoff documents |
| Integration checkout | `/home/epentland/ai/canopy/mylang` |
| Integration branch | `codex/velocity-integration` |
| Pinned Zig | `0.17.0-dev.1683+5ceec001b` at `/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig` (also on PATH) |
| Baseline compiler identity | `fff3e012da1d2ae9e5a60c916245f2479ace96d82d4ba743c21a3733f5b965f4` (`zig-out/bin/mylang --features`, Debug) |
| QBE | built from `vendor/qbe` by `zig build` into `zig-out/bin/qbe` |
| OS/arch | Linux x86_64 |
| Baseline focused evidence | `zig build test-units -Dtest-filter=constraint` → 64/64 passed (2026-09-15) |

The audit recorded executable identity `c54d594e5ad60689…`; the rebuilt baseline
identity above is different and is the authority for this plan. Historical audit
probe JSON is preserved unchanged.

## Frozen contracts

Shared encodings are frozen in [contracts.md](contracts.md). No package may
redefine them silently; a proposed change goes through the integrator and updates
that file, the cache/validator versions and this ledger together.

## Ownership and worktrees

Branches are cut from the baseline SHA. Worktrees live under
`/home/epentland/ai/canopy/mylang-worktrees/`.

| Package | Owner branch | Worktree | Base SHA | Depends on | Status |
| --- | --- | --- | --- | --- | --- |
| W0 | `codex/velocity-integration` | main checkout | `9ce142e` | — | **done** — baseline, contracts, evidence; integrated |
| W0Q | `codex/velocity-w0-verify` | `velocity-w0-verify` | `9ce142e` | W0 | **done** — 42 probes re-run, gates recorded, merged in `1c79941` |
| F1 | `codex/velocity-f1` | `velocity-f1` | `9ce142e` | W0 | **done** — canonical formatter; merged in `0594e61` |
| D1 | `codex/velocity-d1` | `velocity-d1` | `9ce142e` | W0 | **done** — structured trap detail; merged in `5591945` |
| C0 | `codex/velocity-c0` | `velocity-c0` | `9ce142e` | W0 | **done** — work-report-v1; merged in `3d505be` |
| E1 | `codex/velocity-e1` | `velocity-e1` | `9ce142e` | W0 | **done** — directional callable assignability; merged in `55aee27` |
| E2 | `codex/velocity-e2` | `velocity-e2` | `161c4e4` | E1 | **in progress** |
| M1 | `codex/velocity-m1` | `velocity-m1` | W0 + serialized effects | W0 | blocked on effects ownership |
| M2 | `codex/velocity-m2` | `velocity-m2` | M1+E1 integrated | M1, E1 | blocked |
| M3 | `codex/velocity-m3` | `velocity-m3` | M2+E2 integrated | M2, E2 | blocked |
| C1 | `codex/velocity-c1` | `velocity-c1` | C0+E2+M1 integrated | C0, E2, M1 | blocked |
| C2 | `codex/velocity-c2` | `velocity-c2` | C1+M2 integrated | C1, M2 | blocked |
| C3 | `codex/velocity-c3` | `velocity-c3` | C2 integrated | C2 | blocked |
| C4 | `codex/velocity-c4` | `velocity-c4` | C3+P1 integrated | C3, P1 | blocked |
| P1 | `codex/velocity-p1` | `velocity-p1` | M3+E2 integrated | E2, M3 | blocked |
| A1 | `codex/velocity-a1` | `velocity-a1` | `161c4e4` | W0 | **in progress** |
| S1 | `codex/velocity-s1` | `velocity-s1` | C0 integrated | C0 (+ final core) | blocked |
| D2 | `codex/velocity-d2` | `velocity-d2` | final core | each feature | blocked |

## Shared-file ownership by wave

| Wave | Package | Exclusive shared files |
| --- | --- | --- |
| 1 | F1 | `src/formatter.zig`, `src/formatter_test.zig`, formatter CLI/docs paths |
| 1 | D1 | `src/qbe_runtime.h`, `src/qbe_runtime.c`, `src/qbe_managed.zig`, `src/native_run.zig`, `src/native_execute.zig`, native collection/diagnostic runners |
| 1 | C0 | `src/invalidation.zig`, `src/invalidation_*`, `src/frontend_cache.zig`, `src/semantic_cache.zig`, reporting sections of `src/main.zig` |
| 2 | E1 | `src/callables.zig`, callable checks in `src/sema.zig`, `src/structural_constraints.zig`, callable IR validation |
| 2 | M1 | `src/effect_set.zig`, `src/effects.zig`, `src/buffer_operations.zig`, `src/typed.zig` mutation/effect fields, schema rendering |
| 1/3 | A1 | `src/import_policy.zig`, project/CLI policy configuration, policy receipts |
| integrator | — | `build.zig`, `src/root_test.zig`, `SPEC.md`, `src/features.json`, shared goldens, this ledger |

Consumers of a representation wait for its owner to land before editing it.
Never share a mutable checkout, installed binary or `zig-out`/`.zig-cache`.

## Integration log

| Date | Integration SHA | Packages merged | Notes |
| --- | --- | --- | --- |
| 2026-09-15 | `9ce142e` | baseline | W0 baseline commit; focused constraint tests 64/64 |
| 2026-09-15 | `1c79941` | W0Q | baseline evidence, 42-probe comparison, gate record, incremental-status reconciliation |
| 2026-09-15 | `55aee27` | E1 | directional callable assignability; 949 unit / 80 CLI tests on the package tree |
| 2026-09-15 | `5591945` | D1 | structured native trap detail; test-qbe 106/106 on the integration tree |
| 2026-09-15 | `0594e61` | F1 | canonical formatter; format 49/49 units, 3/3 CLI, docs gate unblocked |
| 2026-09-15 | `3d505be` | C0 | work-report-v1; 29 invalidation / 54 cache tests |
| 2026-09-15 | `20a8938` | D1 follow-up | runtime-abi-v1 freeze; cache/invalidation/qbe_build focused suites green |
| 2026-09-15 | `6572623` | baseline fix | narrow enum tag decode + Debug-only alloc sweep; `test-units -Doptimize=ReleaseFast` 960 passed / 0 failed / 1 skipped |
