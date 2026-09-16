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
| E2 | `codex/velocity-e2` | `velocity-e2` | `161c4e4` | E1 | **done** — exported ceilings; merged in `2c0e270` |
| M1 | `codex/velocity-m1` | `velocity-m1` | `14f6f0c` | W0 + E2 | **done** — mutation classification/metadata; merged in `44a0bfe` |
| M2 | `codex/velocity-m2` | `velocity-m2` | `44a0bfe` | M1, E1 | **done** — origin/alias/call enforcement; merged in `8d5b84b` |
| M3 | `codex/velocity-m3` | `velocity-m3` | `8d5b84b` | M2, E2 | **done** — corpus repair, navigation exposure, runnable docs; merged in `75bb69a` |
| C1 | `codex/velocity-c1` | `velocity-c1` | `44a0bfe` | C0, E2, M1 | **done** — per-function deps/remap; merged in `b8a512a` |
| C1R | `codex/velocity-c1r` | `velocity-c1r` | `d150335` | C1 | **done** — module/dependency/eligibility/contract-binding gaps; merged in `86ffbb7c` |
| C2 | `codex/velocity-c2` | `velocity-c2` | `86ffbb7c` | C1, C1R, M2 | **done** — durable validated checked bodies; merged in `88691e7b` |
| C3 | `codex/velocity-c3` | `velocity-c3` | `88691e7b` | C2 | **not started** — specialization/template reuse |
| C4 | `codex/velocity-c4` | `velocity-c4` | C3 integrated | C3 | **not started** |
| P1 | `codex/velocity-p1` | `velocity-p1` | `d150335` | E2, M3 | **done** — checked provider substitution; merged in `354c0e8` |
| A1 | `codex/velocity-a1` | `velocity-a1` | `161c4e4` | W0 | **done** — required project policy; merged in `1f3a...` (`88e7fb6`) |
| S1 | `codex/velocity-s1` | `velocity-s1` | `5988575` | C0 (+ final core) | **done (partial evidence)** — harness repaired, 10k/100k samples; objectives not met; merged in `21d104e` |
| D2 | `codex/velocity-d2` | `velocity-d2` | final core | each feature | **not started** |

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
| 2026-09-15 | `2c0e270` | E2 | explicit exported ceilings + repository migration; focused interface/export/generic/navigation green |
| 2026-09-15 | `88e7fb6` / `5988575` | A1 | required project import policy; 20 policy units / 9 policy CLI tests green |
| 2026-09-15 | `44a0bfe` | M1 | mutation effect + `mutates` grammar + write/origin metadata; 23 M1 regressions green |
| 2026-09-15 | `b8a512a` | C1 | per-function body reuse + stable remapping; 36 semantic / 25 incremental / 30 invalidation / 61 cache tests green |
| 2026-09-15 | `8d5b84b` | M2 | deep origin/alias/call-permission enforcement; 78 effect tests + audit reject/permit pairs |
| 2026-09-15 | `21d104e` | S1 | repaired workload harness + 10k/100k/maintained evidence; objectives not met |
| 2026-09-15 | `75bb69a` | M3 | corpus activation, navigation exposure, runnable mutation docs |
| 2026-09-15 | `75bb69a` | final gate | cold build + Debug 1110/1110 (39/39 steps); ReleaseFast 1109/1110, 1 skipped (39/39 steps); Guardian 88/88 |
| 2026-09-15 | `26e8121` | follow-up | formatter `mutates(...)` spacing + standalone runner trailing-option tolerance; final gate Debug 1128/1128, ReleaseFast 1127/1128 (1 skipped), Guardian 88/88 |
| 2026-09-15 | `d150335` | C1R/P1 start | C1 gap closure and checked-provider substitution launched from the integrated tree |
| 2026-09-15 | `354c0e8` | P1 | declaration/interface gate + selected-provider contract validation + receipt identities; 4 CLI regressions and 101 native units green |
| 2026-09-15 | `86ffbb7c` | C1R | module-qualified keys, resolved-declaration deps, contract-bound reuse; plus a check-session bypass-slice fix |
| 2026-09-15 | `86ffbb7c` | C2 start | persistence package launched |
| 2026-09-15 | `88691e7b` | C1R/P1/C2 checkpoint | pre-C2 gates 1147/1147 Debug and 1146/1147 ReleaseFast; post-C2 gates 1153/1153 Debug and 1152/1153 ReleaseFast (1 skipped) |
| 2026-09-15 | (note) | build cache | a warm `.zig-cache` can keep a stale generated `qbe_build_assets` module after large `src/` edits; cold `zig build test-units` passes 969/969. Final gate must be cold. |

## Corrective pass — C2/P1 review 2026-09-16 (R1–R4 + carried gaps)

Source: [development-velocity-c2-p1-review-2026-09-16.md](../development-velocity-c2-p1-review-2026-09-16.md).

| ID | Finding | Owner branch | Worktree | Base | Status |
| --- | --- | --- | --- | --- | --- |
| R1/R2 | Bind receipt reuse to the selected dependency closure; memoize preparation/executor per selected provider graph | `codex/velocity-r12` | `velocity-r12` | `6a99ef4b` | **done** `1ed663b9`, merged `720d9a7d` |
| R3 | Canonical declaration-level type descriptors for discovery and provider comparison | `codex/velocity-r3` | `velocity-r3` | `6a99ef4b` | **done** `bc462aa6` (manifest `interface-contracts-v2`) |
| R4 | Amortize persistent-cache inventory/eviction (quadratic → linear) | `codex/velocity-r4` | `velocity-r4` | `6a99ef4b` | **done** `d54cc302`; statx 128/256/512/1024 → 260/516/1028/2052 |
| HASH | Declared mutation positions + return-origin in the public API fingerprint | `codex/velocity-hash` | `velocity-hash` | `6a99ef4b` | **done** `4e2d1600` (function/project hashes now change on `mutates(a)`→`mutates(b)`) |
| WARM | Generated `qbe_build_assets` warm-build invalidation | `codex/velocity-warm` | `velocity-warm` | `6a99ef4b` | **done** `70eecedf` — per-file `dependOnFileContents`; warm in-place runtime edits refresh identity/archive/materialized bytes |

Acceptance for the pass: R1 unused edits execute zero tests; R2 two ordinary cases share
one preparation and one native library while distinct graphs stay isolated; R3 boolean
aliases discover and `int`/`i64` providers match while different scalar/nominal types
reject; R4 initial namespace population is approximately linear in `statx` work with
bounds/races/damage intact; HASH changes the function and project interface hashes on a
`mutates(a)`→`mutates(b)` edit; WARM picks up a changed bundled runtime source without a
clean build. C2/P1 positive probes must remain green.

| 2026-09-16 | `720d9a7d` | R3 + R1/R2 | canonical `interface-contracts-v2` descriptors; closure-bound receipts and shared per-provider-graph preparation |
| 2026-09-16 | `4e2d1600` | HASH | declared `mutates` positions and exported return-origin bound in the API fingerprint |
| 2026-09-16 | `d54cc302` | R4 | batched semantic-store inventory; statx 128/256/512/1024 → 260/516/1028/2052 |
| 2026-09-16 | `70eecedf` | WARM | per-file content dependency; warm in-place runtime edits refresh content hash/archives |

## C3/C4 continuation — correction review 2026-09-16

| ID | Work | Owner branch | Worktree | Base | Status |
| --- | --- | --- | --- | --- | --- |
| ORDER | Canonicalize provider-map order before graph hashing | integration | main checkout | `81cd79bb` | **done** `8def75e8` — sorted length-prefixed path/source pairs; native 102/102 |
| C3 | Symbolic-template reuse, then concrete-specialization reuse | `codex/velocity-c3` + `codex/velocity-c3s` | `velocity-c3`, `velocity-c3s` | `8def75e8` | **done** symbolic `8b212f7e`, keys `b0b156e8`, concrete reuse `f444ddc5` |
| C4 | Shared cached test preparation and lazy lowering/emission; two-provider reversed-order regression | `codex/velocity-c4` | `velocity-c4` | C3 integrated | blocked on C3 |

The correction review's remaining P2 (provider ordering) is fixed ahead of C4; C4's
acceptance includes the end-to-end two-provider, two-case reversed-order regression.

### C3 split — symbolic landed, specialization completion queued

| ID | Work | Owner branch | Worktree | Base | Status |
| --- | --- | --- | --- | --- | --- |
| C3a | Symbolic-template reuse (`symbolic-template-v1`) | `codex/velocity-c3` | `velocity-c3` | `8def75e8` | **done** `8b212f7e`/`d7a1cf00`; registered `SEMANTIC-CACHE-11` |
| C3b | Canonical specialization keys (conservative miss) | `codex/velocity-c3` | `velocity-c3` | `8def75e8` | **done** `b0b156e8`/`27520639`; registered `SEMANTIC-CACHE-12` |
| C3S | Concrete specialization body reuse, remap and durable payload | `codex/velocity-c3s` | `velocity-c3s` | `121032ec` | in progress |
| C4 | Shared cached test preparation and lazy lowering/emission; two-provider reversed-order regression | `codex/velocity-c4` | `velocity-c4` | C3S integrated | blocked on C3S |

Also preserved: `wip/cache-prefix-2026-09-16` (`4fa44aa3`) holds concurrent uncommitted
semantic-cache retention/remap work found in the integration checkout (SEMANTIC-CACHE-9/10
numbering). It is not merged or evaluated here; C3 used 11/12 to avoid colliding with it.

### C3S / C4 status

| ID | Work | Owner branch | Base | Status |
| --- | --- | --- | --- | --- |
| C3S | Validated concrete-specialization reuse (`specialization-v1`), typed remap, effect-rerun discipline | `codex/velocity-c3s` | `121032ec` | **done** `f444ddc5`; merged; real replay via `checked_bodies.reused` plus new `specialization_bodies` report |
| C4 | Shared cached test preparation, receipt-first selection, provider-order e2e | `codex/velocity-c4` | `ee392fbf` | **done** `aea9b525`, merged `5538a5d9`; per-function lazy lowering remains |

C3S residual conservative misses: ordinary bodies that reference a specialization still
miss (`.generic_specialization`) because invertible specialization recipes are not
persisted; nested refs whose instance is not yet materialized miss
(`.missing_specialization`); interned-catalog and synthesized-lambda refs miss.

## Correction pass — C3/C4 review 2026-09-16

Source: [development-velocity-c3-c4-review-2026-09-16.md](../development-velocity-c3-c4-review-2026-09-16.md).

| ID | Finding | Owner | Status |
| --- | --- | --- | --- |
| G1 | Reduced graph not bound to its requested input key | integration (`native_test_graph.zig`) | **done** `0c420fbc` — v2 envelope stores/verifies key + structural validation; copied-entry regression |
| N1 | Directory tests ignored `--no-cache` | integration (`native_test_directory.zig`) | **done** `0c420fbc` — flag forwarded to every child; seeded and empty caches execute 2/0 with zero durable files, including `--jobs 1` |
| C3R1 | `check-session clear` retained generic tables | `codex/velocity-retain` | **done** `ddacfb57`, merged |
| C3R2 | Generic tables lack the shared retention budget | `codex/velocity-retain` | **done** `ddacfb57`, merged; SEMANTIC-CACHE-14 registered |
| WIP | Rebase/review preserved retention/remap work | `codex/velocity-retain` | **done** `ddacfb57`; rebased onto C3/C3S, SEMANTIC-CACHE-9/10 registered |

After this pass: S1 remeasurement on one corrected commit, C4 per-function lazy
lowering, D2, productivity trial and final acceptance remain open.

Warm-check correction (2026-09-16): [s1-profile-warm-2026-09-16.md](s1-profile-warm-2026-09-16.md)
replaced the hand-picked S1 sample view with complete `work-report-v1` and
`phase-timings-v1` records, showed concrete-specialization `specialization_bodies
64/64` (the remaining 64 misses are `specialization-missing-instance-identity`),
and measured dependency-key preparation as the largest warm-check phase after
near-total ordinary replay.

Correction-pass integration log (2026-09-16):
- `0c420fbc` G1 + N1: graph-key binding (v2 envelope, structural validation) and directory `--no-cache` forwarding; end-to-end directory run executes 2/0 with zero durable files, including `--jobs 1`.
- `ddacfb57`/`ddacfb57` retention package rebased and merged (G1/N1 preceded it): bounded-prefix ordinary retention (SEMANTIC-CACHE-9), reference-sized ordinary relocation (SEMANTIC-CACHE-10), clear releases all three kinds (SEMANTIC-CACHE-13), shared `reuse.max_bytes` budget across ordinary/symbolic/specialization entries with deterministic eviction and per-kind reporting (SEMANTIC-CACHE-14).
- `610656cf` retains cumulative eviction counts across `clear` and finalizes the SPEC/features registration; final Debug `zig build test` 1199/1199, ReleaseFast 1198/1199 with 1 Debug-only skip (both 39/39 steps).
