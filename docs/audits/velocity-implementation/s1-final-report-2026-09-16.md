# S1 final performance report — integrated compiler `c18c0d18` (ReleaseFast)

Status: **measurement and documentation reconciliation only; no compiler source
changed.** The integrated compiler (warm-check telemetry/profiling + C4 selective
native-test preparation/lowering) was re-measured end to end. C4 makes the 100k
native-test path feasible — whole-project lowering is no longer on the `mylang
test` path and the first 100k native build falls from a >150 s time-box timeout to 11–16 s
while lowering only 322–524 of 33k bodies. The **100k check-feedback (<500 ms) and
100k affected-test (<1 s) objectives remain unmet**: ordinary-100k edits are
≈1.0 s p95 and forced/affected tests are ≈2.8–3.2 s p95. The largest remaining
cost is `dependency_key_preparation`, preserved from the warm-profiling
correction; retention truncation is a work multiplier, not the dominant wall cost.

Prepared 2026-09-16 on branch `codex/velocity-integration`, commit
`c18c0d187f4478e240c5a8373d7db866f3e5fe40`.

## 1. Identity and host caveat

| Item | Value |
| --- | --- |
| Commit | `c18c0d187f4478e240c5a8373d7db866f3e5fe40` (`c18c0d18`) |
| Branch | `codex/velocity-integration` |
| Measured compiler | `/tmp/bisect-c18c0d18/zig-out/bin/mylang` — clean detached worktree at `c18c0d18`, `zig build -Doptimize=ReleaseFast` |
| Compiler SHA-256 | `8e58100c03aaad22cb1c9edcb56d8aa91266228c9feec88b5c18867bb584cb48` |
| `--features` compiler identity | `431cdcd620b5e50517e981e0990a21f1f2f03732d1c79b59b5dd9382e37c6aa5` |
| `zig-out/bin/qbe` SHA-256 | `966c8ce714289a797ea93043f17dbfb15365e546afb2c7a64575b06f139325bb` (vendored QBE `.qbeversion` 1.3) |
| Zig | `0.17.0-dev.1683+5ceec001b` at `/home/epentland/.local/bin/zig` |
| Harness | `scripts/profile_large_project.py` at `c18c0d18`; `generator_sha256` `2c5b3bc70457bd20dcb7a8b55cdf9452b3b7b3f3f66d4d737f61923302292fb5` |
| Native probe | `docs/audits/velocity-implementation/s1-final-2026-09-16/native_probe.py` |
| Host | `linuxserver`: 12th Gen Intel Core i7-12700H, 20 threads, 30 GiB RAM, Ubuntu 26.04, Linux `7.0.0-31-generic`, x86_64 |

Full identity: `s1-final-2026-09-16/identity.txt`.

**Host-load caveat (honest).** The host is shared. The 10k and 100k matrix runs
completed in a quiet window (`/proc/loadavg` 1.4–4.1); the earlier
`/tmp`-handoff runs at load 12–15 were discarded. The native probe ran at load
3.1–4.0 for ordinary 10k/100k and managed 10k; managed-100k
used/unused/provider/no-cache were first hit by a load-11–15 spike from another
agent's self-host sweep and were re-measured at load 3.2–5.0
(`native-probe-managed-100k.json`, §6). The contaminated samples remain in the
raw JSON with their loads. The
harness JSON records host load before/after each document and the native probe
records load before/after each state. Phase shares and work counters are the
defensible evidence; absolute wall times are observed values on a shared host.

**Main-worktree concurrency incident (measurement integrity).** At 17:09:19 UTC
another agent overwrote the handoff `zig-out/bin/mylang` (ReleaseFast,
28,638,464 bytes, sha256 `6248187994…`) with an 82,735,871-byte **Debug** build
(sha256 `0a5ef78c…`), and modified four tracked files (`CLAUDE.md`, `build.zig`,
`build_qbe_assets.zig`, `src/qbe_build_test.zig`) without committing. The first
10k matrix and the first 100k attempt were therefore mode/load contaminated;
they are quarantined under `s1-final-2026-09-16/contaminated/` and are **not**
used for any headline number. All reported measurements use the clean detached
`c18c0d18` ReleaseFast build, which reproduces the same `--features` identity
(`431cdcd6…`) as the intended main-worktree build. No compiler source was
altered by this task, and none of the other agent's files were staged.

**Branch advanced after the instructed commit (identity note).** While this task
ran, the integration branch received three commits on top of the instructed
`c18c0d18`: `7472a0da` (build: keep focused tests off the install graph),
`1c40467f` and `9a177b53` (audit: managed-job lifetimes / timeout reads). HEAD
at report time is `9a177b53`. None of them touches a production compiler source:
`git diff c18c0d18..HEAD -- src/` lists only the test file
`src/qbe_build_test.zig`. They do change the build-time compiler identity
(`build_qbe_assets.zig` now excludes `*_test.zig`/fixture inputs from
`compiler_identity`), so a ReleaseFast build of HEAD reports a different
`--features` identity. A clean ReleaseFast build of `9a177b53` gives binary
sha256 `6951cf789894f88994c85ede60c83be11d11355c145aaac6b0b559a920f504df` and
`--features` compiler identity
`eefa70b382a501c83032ee2e88939d0f5d886261702afa5ea683de0d3e8e964d`, and a
5-sample ordinary-100k spot check is within noise of the pinned `c18c0d18`
numbers (cold 1,219.6 ms, unchanged 97.3 ms, implementation_edit 980.9 ms p50 vs
1,246.7 / 101.3 / 998.0 ms). The reported measurements are the instructed
`c18c0d18` commit; the performance conclusions transfer to `9a177b53` because
the production source tree is byte-identical. Evidence:
`s1-final-2026-09-16/head-verify-100k.json`.

## 2. Exact commands and evidence paths

Pinned build (clean detached worktree; 18/18 steps, binary sha `8e58100c…`):

```sh
git -C /home/epentland/ai/canopy/mylang worktree add -f --detach /tmp/bisect-c18c0d18 c18c0d18
cd /tmp/bisect-c18c0d18
zig build -Doptimize=ReleaseFast --summary all
```

Main matrices (20 samples for baseline/edit/session states, 5 forced-test samples,
900 s timeout, default 16 MiB semantic budget):

```sh
python3 scripts/profile_large_project.py \
  --compiler /tmp/bisect-c18c0d18/zig-out/bin/mylang \
  --output docs/audits/velocity-implementation/s1-final-2026-09-16/matrix-10k.json \
  --workdir /tmp/s1-rf-10k \
  --sizes 10000 --families ordinary,managed \
  --samples 20 --baseline-samples 20 --extra-samples 20 --session-samples 20 \
  --test-samples 5 --timeout 900
# same with --sizes 100000 --workdir /tmp/s1-rf-100k -> matrix-100k.json
```

Direct native states (first build, warm unchanged, forced, used-helper edit,
unused-helper edit, provider edit, `--no-cache` control), 5 repeats per mutating
state, 3 fresh-cache first builds:

```sh
python3 docs/audits/velocity-implementation/s1-final-2026-09-16/native_probe.py \
  --compiler /tmp/bisect-c18c0d18/zig-out/bin/mylang \
  --output docs/audits/velocity-implementation/s1-final-2026-09-16/native-probe.json \
  --workdir /tmp/s1-rf-native \
  --sizes 10000,100000 --families ordinary,managed --repeats 5 --first-builds 3 --timeout 900
```

Check-state budget/phase verification (ordinary-100k, `MYLANG_SEMANTIC_BUDGET`
0/16/64 MiB, 5 samples each for `cold`, `unchanged`, `implementation_edit`):

```sh
MYLANG_SEMANTIC_BUDGET=$((B*1024*1024)) python3 scripts/profile_large_project.py \
  --compiler /tmp/bisect-c18c0d18/zig-out/bin/mylang \
  --output docs/audits/velocity-implementation/s1-final-2026-09-16/budget-${B}mib.json \
  --workdir /tmp/s1-rf-budget-$B --sizes 100000 --families ordinary \
  --samples 5 --baseline-samples 5 --extra-samples 0 --session-samples 5 --test-samples 0 \
  --states cold,unchanged,implementation_edit --timeout 900
```

Evidence directory:
[`s1-final-2026-09-16/`](s1-final-2026-09-16/) — `identity.txt`,
`matrix-10k.json`/`.csv`, `matrix-100k.json`/`.csv`, `native-probe.json`,
`native-probe-managed-100k.json`, `budget-{0,16,64}mib.json`,
`runlog-*.txt`, `gate-native-tests.log`, `summary-tables.md` (tables generated by
`summarize_final.py`), `contaminated/` (quarantined main-worktree runs).

## 3. Method

- Wall time is `time.monotonic()` around a forked/exec'd child: process start,
  dynamic linking, source load, command work and exit are inside the sample.
- Percentiles are nearest-rank, ascending, index `ceil(0.95*n)-1`; `p50` is the
  median. Failed/timed-out samples never enter p50/p95 but remain in raw JSON.
- Peak RSS is child `ru_maxrss` from `wait4`, max over successful samples. For
  `mylang test` it is a **lower bound**: QBE/Zig grandchild peaks are not counted.
- `check-project` never lowers/emits/links; native-test counters come from the
  folded `work-report-v1` `command:"test"` record and its per-child `native-test-graph`
  / `emit-project-qbe` records (`child_reports` in `native-probe.json`).
- The measured worktree, optimize mode, workloads, semantic budget (16 MiB) and
  private cache directories are fixed within each comparison. No
  `MYLANG_SEMANTIC_BUDGET` is set for the matrices.
- `--no-cache` control: the native probe writes a fresh cache directory, runs
  `mylang test --no-cache`, and asserts zero durable graph/receipt/object files.

## 4. Matrix results — p50/p95 wall time and peak RSS

### 10k (load 4.06 → 3.20)

| workload | state | n | p50 ms | p95 ms | peak RSS KiB |
| --- | --- | ---: | ---: | ---: | ---: |
| ordinary-10k (9,935 lines, 64 modules, 3,139 bodies) | cold | 20 | 117.3 | 125.1 | 62,284 |
| ordinary-10k | unchanged | 20 | 13.1 | 14.1 | 32,756 |
| ordinary-10k | no_cache | 20 | 62.6 | 67.9 | 52,172 |
| ordinary-10k | implementation_edit | 20 | 76.1 | 88.3 | 53,292 |
| ordinary-10k | constant_edit | 20 | 77.9 | 90.4 | 53,292 |
| ordinary-10k | signature_edit | 20 | 72.5 | 83.4 | 52,492 |
| ordinary-10k | session_implementation_edit | 20 | 37.1 | 37.6 | – |
| ordinary-10k | session_constant_edit | 20 | 37.5 | 37.9 | – |
| ordinary-10k | forced_tests (first native build 1,696 ms) | 5 | 330.1 | 356.3 | 80,452 |
| managed-10k (10,022 lines, 64 providers, 2,756 bodies, 128 specs) | cold | 20 | 135.0 | 147.4 | 64,524 |
| managed-10k | unchanged | 20 | 12.9 | 14.2 | 42,516 |
| managed-10k | no_cache | 20 | 84.6 | 90.5 | 53,804 |
| managed-10k | implementation_edit | 20 | 99.5 | 107.1 | 60,204 |
| managed-10k | constant_edit | 20 | 100.6 | 123.5 | 62,092 |
| managed-10k | union_edit | 20 | 97.5 | 114.3 | 61,132 |
| managed-10k | provider_edit | 20 | 98.9 | 109.9 | 62,252 |
| managed-10k | effect_edit | 20 | 99.6 | 119.9 | 62,604 |
| managed-10k | session_implementation_edit | 20 | 60.2 | 60.6 | – |
| managed-10k | session_constant_edit | 20 | 61.5 | 62.5 | – |
| managed-10k | forced_tests (first native build 8,270 ms) | 5 | 439.2 | 446.9 | 100,096 |

`ordinary` has no union/provider/effect recipe and `managed` has no signature
recipe; those cells are explicitly `unsupported`, not zero.

### 100k (load 1.99 → 1.43)

| workload | state | n | p50 ms | p95 ms | peak RSS KiB |
| --- | --- | ---: | ---: | ---: | ---: |
| ordinary-100k (100,943 lines, 64 modules, 33,475 bodies) | cold | 20 | 1,246.7 | 1,262.2 | 544,724 |
| ordinary-100k | unchanged | 20 | 101.3 | 103.3 | 40,108 |
| ordinary-100k | no_cache | 20 | 1,031.2 | 1,047.8 | 524,216 |
| ordinary-100k | implementation_edit | 20 | 998.0 | 1,016.5 | 442,308 |
| ordinary-100k | constant_edit | 20 | 1,004.0 | 1,014.2 | 447,788 |
| ordinary-100k | signature_edit | 20 | 1,001.5 | 1,020.5 | 442,836 |
| ordinary-100k | session_implementation_edit | 20 | 1,017.0 | 1,041.2 | – |
| ordinary-100k | session_constant_edit | 20 | 1,025.4 | 1,044.1 | – |
| ordinary-100k | forced_tests (first native build 15,617 ms) | 5 | 2,822.2 | 2,846.0 | 684,660 |
| managed-100k (99,878 lines, 64 providers, 32,708 bodies, 128 specs) | cold | 20 | 1,314.4 | 1,331.0 | 551,844 |
| managed-100k | unchanged | 20 | 103.1 | 108.5 | 39,628 |
| managed-100k | no_cache | 20 | 1,074.7 | 1,142.0 | 531,672 |
| managed-100k | implementation_edit | 20 | 1,088.5 | 1,102.3 | 517,840 |
| managed-100k | constant_edit | 20 | 1,089.0 | 1,093.8 | 522,072 |
| managed-100k | union_edit | 20 | 1,072.9 | 1,104.0 | 516,804 |
| managed-100k | provider_edit | 20 | 1,086.8 | 1,094.2 | 517,464 |
| managed-100k | effect_edit | 20 | 1,087.2 | 1,091.3 | 514,324 |
| managed-100k | session_implementation_edit | 20 | 1,075.4 | 1,079.9 | – |
| managed-100k | session_constant_edit | 20 | 1,079.7 | 1,083.5 | – |
| managed-100k | forced_tests (first native build 11,346 ms) | 5 | 3,035.3 | 3,173.7 | 692,176 |

## 5. Actual `work-report-v1` counters and phase highlights

Representative successful sample per state (performed/reused from the receipts;
`check-project` never lowers/emits/links):

| workload/state | parsed | checked bodies | spec. bodies | symbolic tmpl. | lowered | emitted | links | retained bytes | evicted |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | ---: |
| ordinary-10k cold | 66/0 | 3139/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 5,651,180 | 0 |
| ordinary-10k implementation_edit | 1/65 | 2/3137 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 5,906,598 | 0 |
| ordinary-100k cold | 66/0 | 33475/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 16,776,636 | 0 |
| ordinary-100k implementation_edit | 1/65 | 24655/8820 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 16,775,562 | 0 |
| ordinary-100k constant_edit | 2/64 | 24637/8838 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 16,776,022 | 32 |
| ordinary-100k signature_edit | 2/64 | 24636/8839 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 16,776,004 | 33 |
| managed-100k cold | 68/0 | 32708/0 | 128/0 | 2/0 | 0/0 | 0/0 | 0/0 | 16,775,706 | 0 |
| managed-100k implementation_edit | 1/67 | 24137/8571 | **64/64** | **0/2** | 0/0 | 0/0 | 0/0 | 16,777,034 | 130 |
| managed-100k provider_edit | 2/66 | 24139/8567 | **63/63** | **0/2** | 0/0 | 0/0 | 0/0 | 16,775,384 | 581 |
| managed-100k effect_edit | 2/66 | 24137/8571 | 65/63 | 0/2 | 0/0 | 0/0 | 0/0 | 16,776,410 | 130 |

`instantiated_specializations` (128/0) remains checked-program shape, not
body-replay work; the body-replay counter is `specialization_bodies` (64/64),
with the remaining 64 misses labelled `specialization-missing-instance-identity`.
The 16 MiB ordinary store retains 8,820/33,475 bodies, so every 100k edit
rechecks ~24.6k bodies; that is the retention work multiplier, not a wall-time
explanation by itself.

**Exclusive phase p50 for 100k `implementation_edit` (ms):**

| phase | ordinary-100k | managed-100k |
| --- | ---: | ---: |
| `dependency_key_preparation` | **518.6** | **495.8** |
| `fresh_body_check` | 113.6 | 170.4 |
| `retention_store_io` | 75.9 | 98.7 |
| `source_load_parse` | 94.7 | 92.6 |
| `syntax_replay` | 52.7 | 51.3 |
| `source_merge` | 34.9 | 33.3 |
| `effect_origin_passes` | 27.6 | 31.4 |
| `specialization_body_replay` | – (0) | 18.5 |
| `ordinary_body_replay` | 14.3 | 15.2 |
| `entry_adaptation` | 3.9 | 3.5 |
| `declarations_interfaces` | 3.2 | 3.3 |
| total inclusive | 994.3 | 1,083.8 |

The 5-sample budget check (`budget-{0,16,64}mib.json`) is summarized in §9.
`unchanged` check-project replays the whole verdict and emits only
`source_load_parse` (~95 ms at 100k); edits pay the full phase set above.

## 6. Native-test selective lowering and direct-state results

C4 replaces whole-project lowering on the `mylang test` path. Direct probe
counters (representative successful samples; each has `--select-file` closure):

### ordinary (used/unused helper edits)

| size | state | wall p50/p95 ms | lowered | emitted | links | executed tests | native statuses | cache delta |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: |
| 10k | first build (cold cache) | 1,701 / 1,734 | 50/0 | 50/0 | 1/0 | 1/0 | passed | +3,355 |
| 10k | warm unchanged (cached selection) | 49.5 / 114.5 | **0/0** | **0/0** | **0/0** | **0/1** | cached | +1 |
| 10k | forced run | 327 / 346 | 50/0 | 50/0 | 1/0 | 1/0 | passed | 0 |
| 10k | used-helper private edit | 350 / 357 | 50/0 | 50/0 | 1/0 | 1/0 | passed | +5 |
| 10k | unused-helper private edit | 139 / 149 | **0/0** | **0/0** | **0/0** | **0/1** | cached | +2 |
| 10k | `--no-cache` control | 303 | 50/0 | 50/0 | 1/0 | 1/0 | passed | 0 files |
| 100k | first build (cold cache) | 15,907 / 15,907 | 524/0 | 524/0 | 1/0 | 1/0 | passed | +10,439 |
| 100k | warm unchanged (cached selection) | 424 / 1,316 | **0/0** | **0/0** | **0/0** | **0/1** | cached | +1 |
| 100k | forced run | 2,732 / 2,752 | 524/0 | 524/0 | 1/0 | 1/0 | passed | 0 |
| 100k | used-helper private edit | 2,786 / 2,848 | 524/0 | 524/0 | 1/0 | 1/0 | passed | +5 |
| 100k | unused-helper private edit | 1,533 / 1,576 | **0/0** | **0/0** | **0/0** | **0/1** | cached | +2 |
| 100k | `--no-cache` control | 2,782 | 524/0 | 524/0 | 1/0 | 1/0 | passed | 0 files |

Selectivity: 524 lowered/emitted of 33,475 checked bodies (1.6%) for the 100k
ordinary test closure; the other 32,951 bodies are checked but never lowered.
`native-test-graph` performs the full check with no QBE work; `emit-project-qbe
--select-file` records the closure-only lower/emit; the test child records one
link and one execution. Warm unchanged and unused-helper edit show
`lowered/emitted/links = 0/0, 0/0, 0/0`, no `--select-file` child, and
`executed_tests 0/1 reused` with `native-tests-v1` status `cached`.

### managed (provider edit)

| size | state | wall p50/p95 ms | lowered | emitted | links | executed tests | cache delta |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| 10k | first build (cold cache) | 8,457 / 8,519 | 322/0 | 322/0 | 1/0 | 1/0 | +3,519 |
| 10k | warm unchanged | 53.6 / 130 | **0/0** | **0/0** | **0/0** | **0/1** | +1 |
| 10k | forced run | 414 / 426 | 322/0 | 322/0 | 1/0 | 1/0 | 0 |
| 10k | used-helper edit (`pricing.apply`) | 2,126 / 2,271 | 322/0 | 322/0 | 1/0 | 1/0 | +135 |
| 10k | unused-helper edit (`size` chain) | 153 / 156 | **0/0** | **0/0** | **0/0** | **0/1** | +2 |
| 10k | provider edit | 605 / 733 | 317/0 | 317/0 | 1/0 | 1/0 | +9 |
| 10k | `--no-cache` control | 382 | 322/0 | 322/0 | 1/0 | 1/0 | 0 files |
| 100k | first build (cold cache) | 11,503 / 11,757 | 322/0 | 322/0 | 1/0 | 1/0 | +9,896 |
| 100k | warm unchanged | 480 / 1,603 | **0/0** | **0/0** | **0/0** | **0/1** | +1 |
| 100k | forced run | 3,137 / 3,396 | 322/0 | 322/0 | 1/0 | 1/0 | 0 |
| 100k | used-helper edit (`pricing.apply`) | 4,925 / 5,555 | 322/0 | 322/0 | 1/0 | 1/0 | +135 |
| 100k | unused-helper edit (`size` chain) | 2,037 / 2,254 | **0/0** | **0/0** | **0/0** | **0/1** | +2 |
| 100k | provider edit | 3,451 / 4,070 | 317/0 | 317/0 | 1/0 | 1/0 | +9 |
| 100k | `--no-cache` control | 3,245 | 322/0 | 322/0 | 1/0 | 1/0 | 0 files |

The managed-100k rows are from the load-3.2–5.0 re-run
(`native-probe-managed-100k.json`); the main `native-probe.json` retains the
first (partly load-contaminated) managed-100k edit samples as raw evidence. The
managed test closure is wide (all 64 providers' `Policy.price`/`tag` plus
`pricing` and adapters: 322 functions), so its selective build is larger than the
ordinary closure. A used-helper edit to `pricing.apply` invalidates the whole
provider-dependent closure and re-lowers 322; a provider edit re-lowers 317; an
unused-helper edit to the `size`/`h*` chain leaves the closure intact and
executes nothing.

`--no-cache` produced **zero durable files** in every one of the 12 control runs
(`graphs=0, results=0, objects=0`), confirming no graph/receipt/object
publication for the control.

Checked-fact counters per child (ordinary-100k first build): `list-interfaces`
parsed 0/66; `native-test-graph` parsed 66/0, checked 33,475/0, lowered 0/0;
`emit-project-qbe --select-file` parsed 0/66, checked 24,654/8,821, lowered
524/0, emitted 524/0; the folded `test` record links 1 and executes 1. The
`emit-project-qbe` check pass is the shared 16 MiB semantic store (8,821 replayed
bodies), not whole-project lowering.

## 7. Objective assessment at 100k

| objective | measured | met? |
| --- | --- | --- |
| ordinary-100k cold check p95 < 500 ms | **1,262.2 ms** | **no** (2.5×) |
| ordinary-100k private edit p95 < 500 ms | **1,016.5 ms** | **no** (2.0×) |
| ordinary-100k constant edit p95 < 500 ms | **1,014.2 ms** | **no** |
| ordinary-100k signature edit p95 < 500 ms | **1,020.5 ms** | **no** |
| ordinary-100k in-process session p95 < 500 ms | **1,041.2 / 1,044.1 ms** | **no** |
| managed-100k cold / edit p95 < 500 ms | **1,331.0 / 1,091.3–1,102.3 ms** | **no** |
| 100k affected tests p95 < 1 s | **2,846.0 ms** ordinary / **3,173.7 ms** managed | **no** (2.8–3.2×) |
| 10k forced tests p95 < 1 s (context) | **356.3 ms** ordinary / **446.9 ms** managed | yes at 10k |

The 100k affected-test objective is now **measured rather than blocked**: the
harness `forced_tests` state warmed and completed within the 900 s timeout, and
the direct used-helper edit reproduces it (`ordinary` 2,786 ms p95 2,848 ms).
The cost is dominated by the full `native-test-graph`/`check-project` pass plus
the selective closure build, not by whole-project lowering; lowering is 322–524
functions.

## 8. Comparison to the corrected S1 and prior baseline

Both the corrected S1 rerun (`3f76446c`, ReleaseFast) and this final rerun are
ReleaseFast and comparable; the prior `s1-report.md` baseline is plain Debug
(default `standardOptimizeOption`) and is **not** apples-to-apples.

| workload/state (100k) | prior baseline S1 (Debug) p50 | corrected S1 (`3f76446c`, ReleaseFast) p50 | final (`c18c0d18`, ReleaseFast) p50 | final/corrected |
| --- | ---: | ---: | ---: | ---: |
| ordinary cold | 3,730.8 | 1,249.0 | 1,246.7 | 1.00× |
| ordinary unchanged | 910.1 | 97.2 | 101.3 | 1.04× |
| ordinary no_cache | 2,892.8 | 1,026.8 | 1,031.2 | 1.00× |
| ordinary implementation_edit | 2,854.0 | 1,001.5 | 998.0 | 1.00× |
| ordinary session_impl | 3,098.6 | 1,001.4 | 1,017.0 | 1.02× |
| managed cold | 4,099.0 | 1,215.2 | 1,314.4 | 1.08× |
| managed implementation_edit | 3,254.9 | 1,045.7 | 1,088.5 | 1.04× |
| managed provider_edit | 3,560.1 | 1,068.1 | 1,086.8 | 1.02× |

The check path is statistically flat versus the corrected S1 (final/prior p50
0.99–1.08×); the small managed increase is within the shared-host noise recorded
above. The corrections to the earlier S1 interpretation are preserved:
retention truncation is a work multiplier and a modest session benefit, not the
dominant wall-time cost, and managed concrete-specialization bodies do replay
(`specialization_bodies 64/64`).

**C4 changed the test path, not the check path.** The corrected S1 could not
complete a 100k native build in a 150 s box, so the affected-test target was
recorded as blocked. The final rerun completes a first 100k native build in
15.6 s (ordinary) / 11.3 s (managed) by lowering only the tested closure; the
10k first build falls from 94.0 s / 83.9 s to 1.70 s / 8.46 s. Forced-run p95
falls from 727.5/765.5 ms at 10k to 356.3/446.9 ms in the same ReleaseFast build
mode. Work counters are optimize-mode independent and were unchanged for the
check path.

## 9. Check-state budget/profile verification

The 5-sample ordinary-100k budget check re-verifies the corrected warm-profile
finding on the integrated tree (default budget 16 MiB; 0 and 64 MiB are
measurement-only controls):

| budget MiB | implementation_edit checked/reused | `dependency_key_preparation` p50 ms | `retention_store_io` p50 ms | `fresh_body_check` p50 ms | total p50 ms |
| ---: | --- | ---: | ---: | ---: | ---: |
| 0 | 33,475 / 0 | 586.3 | 0.0 | 178.4 | 1,078.0 |
| 16 | 24,655 / 8,820 | 600.4 | 90.4 | 132.0 | 1,140.4 |
| 64 | 2 / 33,473 | 560.1 | 322.3 | 1.1 | 1,255.4 |

The direction is the corrected one: raising the budget removes fresh ordinary
body checks (24,655 → 2) and adds retention/publication work
(`retention_store_io` 0 → 90 → 322 ms), so the 64 MiB total is not better than
0/16 MiB on this host. `dependency_key_preparation` stays the largest single
phase at every budget (560–600 ms p50). This 5-sample budget probe ran at load
8.5–15.6, so its absolute walls are inflated relative to the clean 16 MiB matrix
row (`implementation_edit` 994.3 ms total, `dependency_key_preparation` 518.6 ms);
the shares and direction are the evidence. Raw files: `budget-0mib.json`,
`budget-16mib.json`, `budget-64mib.json`.

## 10. Corrected priority order after C4

1. **`dependency_key_preparation` / `semantic_key.prepare`.** 518.6 ms p50
   (ordinary) and 495.8 ms p50 (managed) of a ≈1.0–1.1 s 100k edit, ~46–52% of
   measured total. It builds stable function identities and dependency contexts
   for every AST function before any body lookup. This is also inside the
   `native-test-graph` pass that dominates 100k affected-test feedback. The next
   package should make preparation incremental/session-reusable for unchanged
   declaration regions while preserving exact per-body dependency digests.
2. **Fresh ordinary body checking** (113.6 ms ordinary, 170.4 ms managed at
   16 MiB) — the retention-truncation work multiplier. Raising the budget to
   64 MiB removes it but adds `retention_store_io` publication work, a memory/time
   trade rather than a solution.
3. **Retention/publication `Session.remember` + durable publication** (75.9 ms
   ordinary, 98.7 ms managed at 16 MiB; the warm profile measured 384–443 ms at
   64/128 MiB). Reducing the O(N) transfer/publication is a bounded follow-up.
4. **Source/syntax acquisition** (`source_load_parse` 94.7 ms; `syntax_replay`
   52.7 ms) and `source_merge` 34.9 ms.
5. **Whole-graph passes** `effect_origin_passes` 27.6 ms and `entry_adaptation`
   3.9 ms.
6. **Native-test selective build** is no longer a whole-project cost. Its
   remaining cost is the full check (item 1) plus linking/execution; only 1.6% of
   ordinary-100k bodies are lowered. Nested specialization identity
   (`specialization_bodies 64/64`, 64 `specialization-missing-instance-identity`
   misses) is a separate bounded follow-up.

## 11. Eviction/retention and specialization-body replay observations

- The 16 MiB store retains 8,820/33,475 ordinary-100k bodies. `implementation_edit`
  rechecks 24,655 and replays 8,820; `constant_edit`/`signature_edit` recheck
  ~24,637 and replay ~8,838. Eviction counts appear once a state re-publishes
  (`constant_edit` 32, `signature_edit` 33; managed `provider_edit` 581), so
  eviction/re-admission is active but the stable 128-specialization workload does
  not exercise high-churn re-admission. That remains a gap (§12).
- Managed `specialization_bodies` is **64/64 replayed** across edit states; the
  remaining 64 specializations miss with
  `specialization-missing-instance-identity`. `symbolic_templates` is **0/2**
  replayed (two abstract templates replayed, none freshly checked).
  `instantiated_specializations 128/0` is checked-program shape, not body-replay
  evidence — preserve the earlier correction.
- `provider_edit` reports `specialization_bodies 63/63` and
  `instantiated_specializations 126/0` because the rotated provider graph changes
  which concrete instances exist; this is consistent, not a regression.
- `--no-cache` wrote zero durable graph/receipt/object files in all 12 direct
  controls.

## 12. Gaps and blockers

- **100k check-feedback (<500 ms) and affected-test (<1 s) objectives are unmet**
  at 1.0–1.3 s and 2.8–3.2 s respectively. The dominant remaining phase is
  `dependency_key_preparation`.
- **Shared-host load.** The 100k managed used/unused/provider/no-cache direct
  states were first measured at load 11–15 (raw JSON retains them); they were
  re-run in a quiet window (`native-probe-managed-100k.json`). Even the quiet
  windows were not idle, so absolute latencies are slightly pessimistic.
- **Main-worktree concurrency.** The handoff ReleaseFast binary and four tracked
  files were overwritten/modified by another agent during the task; measurements
  were pinned to a clean `c18c0d18` worktree. The other agent's files are
  untouched by this task and must not be committed by it.
- **Eviction/re-admission churn gap.** A workload whose distinct
  specializations/templates exceed the chosen budget (or churns providers) is
  still needed; the stable 128-specialization family does not cover it.
- **Navigation/scale.** `index-project` still rejects both 100k workloads
  (`NavigationLimit`), recorded as unsupported rather than zero; the project
  loader bound remains 256 modules/16 MiB and 500k is unmeasured.
- **Forced memory is a lower bound** for `mylang test` (QBE/Zig grandchildren are
  excluded from `ru_maxrss`).
- **`signature_edit` for managed and union/provider/effect for ordinary** remain
  unsupported harness states, recorded as unsupported rather than zero.

## 13. Verification gates

| Gate | Command | Result |
| --- | --- | --- |
| Harness compile | `python3 -m py_compile scripts/profile_large_project.py scripts/summarize_profile_warm.py` | pass (main worktree, HEAD `9a177b53`) |
| Formatter | `zig build fmt-check --summary all` | 2/2 steps succeeded (clean `c18c0d18` and clean `9a177b53` trees) |
| Focused native tests | `zig build test-native-tests --summary all -j8` | 22/22 steps succeeded; 56/56 tests passed on clean `c18c0d18` (`gate-native-tests.log`) and clean `9a177b53` (`gate-native-tests-head.log`) |
| Performance transfer | 5-sample ordinary-100k spot check on `9a177b53` ReleaseFast | cold/unchanged/implementation_edit p50 1,219.6 / 97.3 / 980.9 ms, within noise of the pinned `c18c0d18` numbers (`head-verify-100k.json`) |

The full Debug `1210/1210` and ReleaseFast `1209/1210` (1 expected skip) gates
were already run by the parent on this merge and were not re-run; this task
changed no compiler source. The `test-native-tests` install step overwrote the
isolated worktree binary with a Debug build; it was deterministically rebuilt to
ReleaseFast (`zig build -Doptimize=ReleaseFast`, binary sha `8e58100c…`) before
the native probe re-run, matching the corrected-report binary-identity note.

## 14. What changed in the current docs

- This report is new.
- `docs/audits/velocity-implementation/final-status.md` now records
  `c18c0d18` as the integration HEAD, states that C4 lowers only the
  `--select-file` closure (no whole-project lowering on the `mylang test` path),
  replaces the "100k forced tests blocked" claim with the measured 2,846.0 /
  3,173.7 ms p95 numbers, and updates the scale/limitations text.
- `docs/audits/velocity-implementation/README.md` has a dated final-S1 note
  appended; historical rows are left unchanged.
- Dated historical audits (`s1-report.md`,
  `s1-corrected-report-2026-09-16.md`,
  `s1-profile-warm-2026-09-16.md`, the review documents) are unchanged.
