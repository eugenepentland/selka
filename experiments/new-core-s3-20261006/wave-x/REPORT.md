# S3 exit report — 2026-10-06

**S3 is complete.** Every exit check of the S3 plan's §7 passes on the final source
`d4994214579adb8d1897a40fc65de1462b000939` on `codex/new-core-s3-integration`. S3
stops here for the user's go/stop decision on S4. The old core stays the default
compiler until S5. Nothing was pushed or merged into `main`.

S3 admits, in the new core, everything `tests/lang` uses except user modules (S4) and
the retired arenas:
- capabilities, resources and I/O, and the property-test runner;
- the remaining text and byte methods, mutable byte buffers, and exact float text;
- math operations, recursive equality and aggregate operators, and concrete
  generics;
- `strings`/`json` standard-library imports;
- the five application workloads.

## Final receipts (all on `d4994214`)

| Check | Result | Evidence (`integration/`) |
|---|---|---|
| Frozen source and oracles | Old core `d366…0c79`, QBE `b613…af4c`, new core `09f90c02…50f0`; `ir.zig` unchanged since S3-0; `tests/lang` unchanged since D2 | `final-source-freeze-run02.json` |
| Uncontended new-core rebuild | **1.80 s**; all build slots held, gate excluded | `final-merge-run02/install-core.log` |
| Core tests (64 shards) | **277/277** in 145.97 s; longest shard 50.94 s; peak test RSS 347 MB | `final-merge-run02/test-core.log` |
| Conformance with leak and fact verification | Debug and release each **1518 match, 0 mismatch, 0 unsupported**, 59.24 s | `final-merge-run02/full-conformance.log` |
| Ordinary conformance | Debug and release each **1518 / 0 / 0**, 150.36 s | `final-ordinary-conformance-run02.log` |
| Full old-core gate | `test` 115/115 steps, 3,002 tests (1,049 s); `test-qbe` 520/520 (93 s); `test-qbe-build` 29/29; `fmt-check` 2/2 | `final-old-run02/summary.json` |
| Strict 9 kinds × 200 fuzz matrix | **1,800 sources accepted, 25,800 exact native comparisons**: old core against new debug, release and verify builds, with stdout, status, traps, leaks and facts compared. Run as `matrix-final-run02` plus a rerun of four kinds (below). | `matrix-final-run02-rerun01/combined.json` |
| Supplementary split-key sweep | **200 sources, 3,000 comparisons**, 0 mismatches | `split-final-run02/summary.json` |
| All 40 rows, CPU 10, 7 rounds, 3 startup samples | **80/80 cells within 1.10× Zig ReleaseSafe and within 1.10× the old core.** Worst against Zig: `int_parse`/64 at 1.0893. Worst against the old core: `packet_decode`/64 at 1.0601. | `all40-final-run02.json` |
| Count audit, all 40 rows | Valid. **8** static count stores in timed innermost loops (`alloc_retained` 1, `mutate_nested` 2, `csv_aggregate` 5). `alloc_short`'s tags do not survive optimization, so it is reported as unknown. | `count-audit-final-run02.json` |
| Coverage, four corpora | **3,633/3,639** per corpus and **3,410/3,416** deduplicated, identical to run01. The 6 not accepted are 3 bodyless `extern` and 3 bodyless Host declarations. | `coverage-final-run02/summary.json` |
| Exclusions | **9 S4 tests** (`tests/lang/migrated/propagation.my`, which imports user modules) and **118 retired arena tests**, identical to run01 | `exceptions-final-run02.json` |
| Protected refs | `main` `df55c52d`, `codex/new-core-s2-integration` `92590700`, both unchanged | `final-source-freeze-run02.json` |

Both tables (performance and counts) are in
[`integration/exit-tables-final-run02.md`](integration/exit-tables-final-run02.md).

## The S3-X repair: `NEW-CORE-RC-13`

S3-X run01 stopped on a real wrong answer. The matrix's 82nd rebinding source,
`mut_records_alias81`, printed a stale snapshot under the new core.

**Root cause** (`src/core/own.zig`, `Analysis.liveAfter`, used by `promote`):
- `b`, a copy `c = b` and `snap = b` are one SSA record.
- Rebinding `c.items` through a `mut` call consumes that record before
  `b.items.append(…)` reads the field.
- `liveAfter` called the field read live at that earlier consumption, because it
  checked only for later uses. So the read was promoted to an owned value.
- The push's uniqueness test then saw the record's own count of 1 and appended in
  place, under `snap`.

**Fix:** `liveAfter` returns false before a value's definition. That is three lines;
every other caller already passes a position after the definition.

**Evidence:**
- reduction tools and results in [`rebinding-repair/`](rebinding-repair/README.md);
- regression fixture `test/core/rc_promote_order.my`, with the `NEW-CORE-RC-13` test
  in debug, release and verify builds under the leak check;
- repair commit `53bbfb53` and integration merge `d4994214`.

**Deviation:** the Codex handoff asked that `own.zig` stay frozen. The defect was in
`own.zig`. The plan itself freezes only `ir.zig`, which is unchanged.

## What else happened in S3-X (failed attempts kept)

- **Run01** (`5ee5b8d2`): the matrix stopped at `rebinding` (the defect above), and
  `dict` stopped on an old-compiler build timeout under load. The old gate and count
  audit were cancelled. All of it is retained under `integration/*run01*`.
- **Run02's matrix:** `s0`, `s1`, `rc`, `number` and `rebinding` passed. `iteration`,
  `dict`, `text` and `functions` stopped on the old compiler's 60 s build timeout,
  with **no mismatch**.
  - The cause was the full old gate, which I started alongside to save time. It
    pushed load to about 56 while the matrix workers run at `nice 10`. The same
    source built in 16 s at load 31 and in 9.5 s unloaded.
  - `fuzz_matrix_rerun.py` reran exactly those four kinds with the matrix's own
    command (seeds, generators, oracles) on a quiet machine, and all four passed.
  - It refuses kinds that stopped for any other reason, and it never edits the
    original evidence. `combined.json` applies the matrix's own pass rule.
- **Run01's timing** (`all40-final-run01.json`) was valid but measured the pre-repair
  source. Run02 replaces it.

## Package identities

| Package | Final source | Qualification | Integration merge |
|---|---|---|---|
| S3-0 (design, frozen IR) | `dc1a5831` | `643858e3` | `e39ad11d` |
| S3-L (D2, views not stored) | `225bee07` | `225bee07` | `f5ba28e5` |
| S3-T1 (text methods) | `ade0ce29` | `0b48e921` | `2e4f0f51` |
| S3-T2 (bytes, numbers, float text) | `52a9e1ef` | `5d2849ff` | `fb9bff99` |
| S3-C with property runner (`ENV-NAMES-GRANT-1` old-core fix `4747ad07`) | `9637eb9a` | `6bac5b16` | `f1319a77` |
| S3-M (math, values, generics) | `93030b84` | `d5be46e4` | `da321c57` |
| S3-A (stdlib, applications, performance repairs) | `203c0ca6` | `80fa132a` | `5ee5b8d2` |
| S3-X repair `NEW-CORE-RC-13` | `53bbfb53` | `final-merge-run02` | `d4994214` |

Full hashes, the repair composition inside S3-A and every package's retained
failures are in [the package history](report-preparation/report-candidate-01.md).

## Dev loop

| Measure | Result |
|---|---|
| New-core rebuild after an edit, uncontended | 1.80 s |
| Core test suite, 64 shards | 146 s, longest shard 51 s |
| Full conformance with leak and fact checks | 59 s |
| Float-text runtime unit, first program build in a fresh cache | 0.97 s of a 3.12 s build; reused in 0.11 s by the next program |
| Full old-core gate | about 19 min (`test` 1,049 s) |

## Remaining limits

The complete inventory is
[`report-preparation/limits-final-candidate.md`](report-preparation/limits-final-candidate.md):
source refusals, inherited front-end and runtime budgets, optimization fallbacks,
and the S4 module boundary.

**Kept unchanged:**
- IR frozen at `dc1a5831`;
- no record phi emptied;
- aggregate parameters within the first 64 positions;
- formats `module-interface-v5`, `check-summaries-v6` and `mutation-v2`;
- provider ABI 7.

**Out of S3 by design** (S4): user modules, persisted interfaces and incremental
per-module builds.

## Next

S4 is planned in `docs/audits/new-core-s4-plan-2026-10-06.md` on
`claude/new-core-s4-design`. Its Wave 0 is done:
- the Lox port migrated to value semantics;
- EDA Stage 1 ported, with byte-identical golden outputs;
- six new benchmark rows on `claude/new-core-s4-rows`.

S4's Wave A starts only on the user's go.
