# S1 performance measurement — corrected compiler (budget-accounting fix `3f76446c`, ReleaseFast)

Status: **measurement only; no compiler/source behavior changed.** The corrected
compiler is substantially faster than the prior S1 baseline in every comparable
state, but the **100k check-feedback target (<500 ms) is still not met**, and the
**100k affected-test target is still unmeasured/blocked**. The 16 MiB shared
semantic retention budget is a demonstrated source of extra work: it retains
only ~8.8k of 33.5k ordinary bodies at 100k, so every edit rechecks ~24.6k
bodies. Later 20-sample profile evidence shows that retention truncation is a
modest session benefit, not the established dominant wall-time cost; after
near-total body replay the largest demonstrated warm-check cost is dependency-key
preparation. See the corrected profile:
[s1-profile-warm-2026-09-16.md](s1-profile-warm-2026-09-16.md).

Prepared 2026-09-16 on branch `codex/velocity-integration`, commit
`3f76446c9e4134d7fea0c67045dee4a28fb24507`.

## 1. Identity

| Item | Value |
| --- | --- |
| Commit | `3f76446c9e4134d7fea0c67045dee4a28fb24507` |
| Measured worktree | `/tmp/mylang-s1-corrected` (detached at `3f76446c`; clean) |
| Build | `zig build -Doptimize=ReleaseFast` (measured install; deterministically restored after the focused-test step — see the binary-identity note in §9) |
| `zig-out/bin/mylang` sha256 | `58a39d625369491cc696f9585d002aac4d6e9265afb2d5458b425d92cc61f57f` |
| Compiler identity (`mylang --features` `compiler_sha256`) | `2ab93be8437d1bf00580f136c0e0a155acfa2621c33ebc7f2ece7f03ee1635aa` |
| `zig-out/bin/qbe` sha256 | `9f1a32c1f2c4548595b61089a172dd0c6cfd5cbbb29677984db7442387204117` |
| QBE vendored version | `1.3` (`.qbeversion`) |
| Harness | `scripts/profile_large_project.py` sha256 `9cb579c34039a923110ee3aa2abbf2b3d4f4e01a9590e08b249c2683c23caec6` |
| Zig | `/home/epentland/.local/bin/zig`, `0.17.0-dev.1683+5ceec001b` |
| Machine | `linuxserver`: 12th Gen Intel Core i7-12700H, 20 threads, 30 GiB RAM |
| OS/arch | Ubuntu 26.04 LTS, Linux `7.0.0-31-generic`, `x86_64` |
| Concurrent-load caveat | see below |

Full identity capture: `s1-corrected-2026-09-16/identity.txt`.

### Concurrent-load caveat (honest)

The host is shared and was **not idle** for any run. Two distinct load regimes
were observed, and the report separates them:

- **First pass (13:18–13:35 UTC): load 7–14 on 20 threads.** Another agent's
  self-host corpus sweep (`python3 selfhost/tests/run_corpus_sweep.py --update`,
  started 13:23:28) spawned ~12 CPU-bound `mylang run` processes. The first-pass
  `10k.json` and `100k.json` are preserved as evidence, but their latencies are
  **load-contaminated and not used for the headline p50/p95**.
- **Primary low-load pass (13:35–13:53 UTC): 1-min load 0.46–3.08.** One
  competing `mylang run` process (self-host parser diff) was observed during part
  of this window. All headline numbers come from this pass.

The contamination is demonstrable, not hypothetical: in the first pass the
ordinary-100k `implementation_edit` produced **byte-identical work counters on
every sample** (`parsed 1/65, checked 24655/8820`) while wall time swung between
~1000 ms and ~3080 ms. The variance is therefore the shared host, not the
compiler. Even the low-load pass was not fully idle, so absolute latencies are
slightly pessimistic; relative/work-counter comparisons remain sound.

## 2. Exact commands, timestamps, and raw evidence

Setup (path dependency `../guardian-zig` is resolved with an out-of-tree symlink
so the main checkout is untouched):

```sh
git -C /home/epentland/ai/canopy/mylang worktree add /tmp/mylang-s1-corrected 3f76446c
ln -sfn /home/epentland/ai/canopy/guardian-zig /tmp/guardian-zig
cd /tmp/mylang-s1-corrected && zig build -Doptimize=ReleaseFast
```

Runs (all sequential, one harness at a time; `$EVID` is the evidence directory):

| # | UTC window | load (start → end) | Command / output |
| --- | --- | --- | --- |
| 1 | 13:18:33 → 13:23:19 | 7.03 → 9.59 | 10k full: `--sizes 10000 --families ordinary,managed --samples 20 --baseline-samples 20 --extra-samples 5 --test-samples 3 --session-samples 20 --timeout 900 --probe-limits` → `10k.json` / `10k.csv` (preserved; load-contaminated) |
| 2 | 13:27:17 → 13:35:05 | 12.56 → 3.71 | 100k full: `--sizes 100000 --families ordinary,managed --samples 20 --baseline-samples 10 --extra-samples 5 --session-samples 20 --test-samples 0 --states cold,unchanged,no_cache,implementation_edit,constant_edit,signature_edit,union_edit,provider_edit,effect_edit,session_implementation_edit,session_constant_edit` → `100k.json` / `100k.csv` (preserved; ordinary under load) |
| 3 | 13:35:27 → 13:37:43 | 3.08 → 2.09 | **100k ordinary low-load** (same states as #2, ordinary only) → `100k-ordinary-lowload.json` / `.csv` |
| 4 | 13:39:21 → 13:45:03 | 0.74 → 1.03 | **100k managed low-load** (managed only) → `100k-managed-lowload.json` / `.csv`; then **10k low-load with forced tests** `--sizes 10000 --families ordinary,managed --samples 20 --baseline-samples 20 --extra-samples 5 --test-samples 3 --session-samples 20` → `10k-lowload.json` / `.csv` |
| 5 | 13:57:15 → 14:02:17 | 0.38 → 1.27 | 100k forced-test time-box on the restored measured binary (first attempt 13:48–13:53 used an accidental Debug install, see §9): `--families ordinary --samples 2 --test-samples 1 --timeout 150 --states forced_tests` → `100k-forced-attempt.json` / `.csv` |
| 6 | 13:47, re-run ~14:03 | ~0.5 each | retention counters: `python3 retention_probe.py <compiler> <entry> 3` → `retention-{ordinary,managed}-{10k,100k}.json` (re-run on the restored binary; identical values) |
| 7 | 13:48 | ~0.5 | focused retention tests: `zig build test-units -Dtest-filter="eviction forces fresh checks"` and `-Dtest-filter="many distinct symbolic templates"` → `retention-eviction-specializations.log`, `retention-eviction-symbolic.log` (`rc=0`, PASS) |

Every harness invocation writes `.json` **and** `.csv` after each workload.
Every generated workload was validated with `check-project --no-cache --report`
before timing (`validation.accepted = true`, `exit = 0` for all six primary
workloads), and each invocation also runs the harness `smoke_validation`
(ordinary + managed + maintained) first: all accepted.

The full 10k run additionally ran `--probe-limits`: all three bounded failures
were reproduced — 257 modules → `E_MODULE_LIMIT`, >4 MiB file → `E_PROJECT_BYTES`,
>16 MiB project → `E_PROJECT_BYTES`; every budget literal was still present in
its owning source (`limits[*].all_patterns_present = true`).

**Evidence directory (main checkout, new, untracked):**
`/home/epentland/ai/canopy/mylang/docs/audits/velocity-implementation/s1-corrected-2026-09-16/`

Index: `10k.json`/`.csv`, `10k-lowload.json`/`.csv`,
`100k.json`/`.csv`, `100k-ordinary-lowload.json`/`.csv`,
`100k-managed-lowload.json`/`.csv`, `100k-forced-attempt.json`/`.csv`,
`identity.txt`, `summary-tables.md` (all tables above), `retention-*.json`
(raw retention counters), `retention_probe.py` (the thin check-session probe that
read them), `retention-eviction-specializations.log`,
`retention-eviction-symbolic.log`, `retention-focused-tests.log`.

## 3. Method

- Wall time: `time.monotonic()` around a forked/exec'd child (process start,
  dynamic linking, source load, check/test work, exit are inside the sample).
- Percentile: nearest-rank, ascending, index `ceil(0.95*n)-1`; `p50` is the median.
- Memory: child `ru_maxrss` from `wait4`, reported as the max over that state's
  samples. Forced-test memory is a **lower bound** (QBE/Zig grandchildren are not
  counted).
- Warm-ups: one successful check populates the cache before `unchanged`/edit
  states; `cold` deletes the cache before every sample; edit samples each write a
  unique deterministic token so no verdict from a previous sample can replay.
- n: 20 measured samples for `implementation_edit`/`constant_edit`/
  `signature_edit` and sessions, 10 baseline samples for `cold`/`unchanged`/
  `no_cache`, 5 for `union`/`provider`/`effect`, 3 forced-test samples at 10k.

**Optimize-mode warning for all prior-S1 comparisons.** The prior S1 report
(`s1-report.md`) reproduces with plain `zig build`; `build.zig` uses
`standardOptimizeOption`, whose default is Debug. Its binary (`df7e16a1…`) is
99,387,576 bytes. This measurement is `ReleaseFast` and its binary is
28,394,904 bytes. **Absolute prior-vs-corrected deltas therefore conflate
optimize mode with the budget-accounting fix** and must not be read as a pure
fix speedup. Work counters are optimize-mode independent and are the honest
fix-level comparison.

## 4. Results — trustworthy low-load pass

`n`, floor/ceiling summary, and per-state peak RSS. Unsupported states are
marked, not zero.

### 10k (primary, load ≈1)

| workload | state | n | p50 ms | p95 ms | max RSS KiB |
| --- | --- | ---: | ---: | ---: | ---: |
| ordinary-10k (9935 lines, 66 modules, 3139 bodies) | cold | 20 | 109.6 | 121.8 | 59424 |
| ordinary-10k | unchanged | 20 | 12.5 | 13.9 | 32288 |
| ordinary-10k | no_cache | 20 | 58.1 | 60.9 | 52032 |
| ordinary-10k | implementation_edit | 20 | 66.6 | 68.3 | 51904 |
| ordinary-10k | constant_edit | 20 | 68.8 | 76.9 | 53824 |
| ordinary-10k | signature_edit | 20 | 67.1 | 73.8 | 51104 |
| ordinary-10k | session_implementation_edit | 20 | 35.4 | 36.0 | – |
| ordinary-10k | session_constant_edit | 20 | 35.7 | 36.1 | – |
| ordinary-10k | forced_tests (cold native build 94.0 s) | 3 | 721.9 | 727.5 | 123532 (lower bound) |
| managed-10k (10022 lines, 68 modules, 2756 bodies, 128 specs) | cold | 20 | 126.1 | 133.1 | 63584 |
| managed-10k | unchanged | 20 | 12.7 | 13.8 | 41368 |
| managed-10k | no_cache | 20 | 77.9 | 80.5 | 53824 |
| managed-10k | implementation_edit | 20 | 93.1 | 103.0 | 62144 |
| managed-10k | constant_edit | 20 | 94.9 | 106.9 | 61824 |
| managed-10k | union_edit | 5 | 92.0 | 97.4 | 60704 |
| managed-10k | provider_edit | 5 | 92.5 | 94.8 | 61024 |
| managed-10k | effect_edit | 5 | 94.4 | 98.6 | 61504 |
| managed-10k | session_implementation_edit | 20 | 58.0 | 58.3 | – |
| managed-10k | session_constant_edit | 20 | 57.9 | 58.3 | – |
| managed-10k | forced_tests (cold native build 83.9 s) | 3 | 760.0 | 765.5 | 115060 (lower bound) |

`ordinary-10k` has no union/provider/effect recipe and `managed-10k` has no
signature recipe; those states are explicitly unsupported (harness limitation,
not zero).

### 100k (primary, low-load, load 0.7–3.1)

| workload | state | n | p50 ms | p95 ms | max RSS KiB |
| --- | --- | ---: | ---: | ---: | ---: |
| ordinary-100k (100943 lines, 66 modules, 33475 bodies) | cold | 10 | 1249.0 | 1255.9 | 544200 |
| ordinary-100k | unchanged | 10 | 97.2 | 99.3 | 40128 |
| ordinary-100k | no_cache | 10 | 1026.8 | 1042.4 | 524016 |
| ordinary-100k | implementation_edit | 20 | 1001.5 | 1013.6 | 444432 |
| ordinary-100k | constant_edit | 20 | 1057.5 | 1113.7 | 447792 |
| ordinary-100k | signature_edit | 20 | 1021.8 | 1074.5 | 447480 |
| ordinary-100k | session_implementation_edit | 20 | 1001.4 | 1009.6 | – |
| ordinary-100k | session_constant_edit | 20 | 997.0 | 999.2 | – |
| managed-100k (99878 lines, 68 modules, 32708 bodies, 128 specs) | cold | 10 | 1215.2 | 1230.3 | 551352 |
| managed-100k | unchanged | 10 | 92.5 | 95.2 | 39648 |
| managed-100k | no_cache | 10 | 1017.4 | 1023.5 | 531500 |
| managed-100k | implementation_edit | 20 | 1045.7 | 1057.0 | 515832 |
| managed-100k | constant_edit | 20 | 1057.1 | 1069.9 | 519536 |
| managed-100k | union_edit | 5 | 1084.3 | 1118.6 | 510620 |
| managed-100k | provider_edit | 5 | 1068.1 | 1073.7 | 516656 |
| managed-100k | effect_edit | 5 | 1057.7 | 1064.9 | 514364 |
| managed-100k | session_implementation_edit | 20 | 1055.6 | 1057.6 | – |
| managed-100k | session_constant_edit | 20 | 1059.1 | 1067.0 | – |

At 100k the plan/navigation call graph is `unsupported` (`index-project` →
`mylang: host failure: NavigationLimit`, exit 2), recorded as unsupported, not
zero. Module depth/imports are recorded (`ordinary` 66 modules/192 imports/depth
66; `managed` 68/130/3).

### Actual `work-report-v1` stage counters (representative samples)

Performed/reused, from the samples' own receipts. These are optimize-mode
independent and are the clearest statement of what the fix changed.

| workload | state | parsed | checked bodies | specializations | lowered | emitted | bypass reasons |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ordinary-10k | cold | 66/0 | 3139/0 | 0/0 | 0/0 | 0/0 | – |
| ordinary-10k | unchanged | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | verdict replayed |
| ordinary-10k | implementation_edit | 1/65 | **2/3137** | 0/0 | 0/0 | 0/0 | declaration-region-length-changed×1, relocation-failed×1 |
| ordinary-10k | constant_edit | 2/64 | 67/3072 | 0/0 | 0/0 | 0/0 | no-retained-body×66 |
| managed-10k | implementation_edit | 1/67 | 130/2626 | **128/0** | 0/0 | 0/0 | not-ordinary-body×128, relocation-failed×64, generic-specialization×1 |
| ordinary-100k | cold | 66/0 | 33475/0 | 0/0 | 0/0 | 0/0 | – |
| ordinary-100k | implementation_edit | 1/65 | **24655/8820** | 0/0 | 0/0 | 0/0 | **no-retained-body×24653**, declaration-region-length-changed×1, relocation-failed×1 |
| ordinary-100k | constant_edit | 2/64 | 24637/8838 | 0/0 | 0/0 | 0/0 | **no-retained-body×24636** |
| ordinary-100k | signature_edit | 2/64 | 24636/8839 | 0/0 | 0/0 | 0/0 | **no-retained-body×24636** |
| managed-100k | cold | 68/0 | 32708/0 | 128/0 | 0/0 | 0/0 | generic-specialization×1, symbolic-no-retained-template×2 |
| managed-100k | implementation_edit | 1/67 | 24137/8571 | **128/0** | 0/0 | 0/0 | not-ordinary-body×128, **no-retained-body×24055**, relocation-failed×17, generic-specialization×1 |
| managed-100k | constant_edit | 2/66 | 24089/8619 | **128/0** | 0/0 | 0/0 | not-ordinary-body×128, **no-retained-body×24007**, relocation-failed×17 |

`check-project` never lowers/emits/links, so `lowered_functions`,
`emitted_fragments` and `links` are `0/0` for every check state — the remaining
cost is entirely parse + body check + specialization instantiation.

In-process session deltas (`check-session-v1` `work.request`):

| workload | session state | parsed | checked bodies | specializations |
| --- | --- | --- | --- | --- |
| ordinary-100k | session_implementation_edit | 66/0 | 24202/9273 | 0/0 |
| ordinary-100k | session_constant_edit | 66/0 | 24220/9255 | 0/0 |
| managed-100k | session_implementation_edit | 68/0 | 23659/9049 | 128/0 |
| managed-100k | session_constant_edit | 68/0 | 23677/9031 | 128/0 |

At 100k the in-process session path no longer bypasses reuse (the prior report's
`bypassed=1, retained 0`), but it still rechecks ~24.2k bodies per edit because
they are not retained.

## 5. Objectives at 100k (plainly)

Selected 100k workload is `ordinary-100k` (100943 lines); `managed-100k` is
reported separately because contract/effect/provider edits legitimately touch the
specialization set.

| objective | measured | met? |
| --- | --- | --- |
| ordinary-100k cold check p95 < 500 ms | **1255.9 ms** | **no** (2.5× over) |
| ordinary-100k private edit p95 < 500 ms | **1013.6 ms** | **no** (2.0× over) |
| ordinary-100k constant edit p95 < 500 ms | **1113.7 ms** | **no** (2.2× over) |
| ordinary-100k signature edit p95 < 500 ms | **1074.5 ms** | **no** (2.1× over) |
| ordinary-100k in-process edit p95 < 500 ms | **1009.6 / 999.2 ms** | **no** (2.0× over) |
| managed-100k cold check p95 < 500 ms | **1230.3 ms** | **no** |
| managed-100k edit/union/provider/effect p95 < 500 ms | **1057.0–1118.6 ms** | **no** |
| 100k affected tests p95 < 1 s | **not measured / blocked** | **unmeasured** |
| 10k forced tests p95 < 1 s (context only, not 100k) | **727.5 / 765.5 ms** | yes at 10k |

**100k affected tests: explicitly not measured.** The time-boxed harness attempt
(`--timeout 150`, run 13:57–14:02 on the restored measured binary sha
`58a39d62…`) recorded the warm first build as `timed_out=true, exit=-9,
wall_ms=150041.7` and the single `--force` sample as `timed_out=true, exit=-9,
wall_ms=150041.3` — both SIGKILLed after 150 s. The 10k forced-test numbers above
are real and meet <1 s, but they are **not** a substitute for the 100k
measurement. The reason is structural: `mylang test` lowers/emits/links the whole
checked project before selecting tests, and 33,475 bodies at 100k make the cold
native build exceed 150 s (the 10k cold build is already 84–94 s). Lazy lowering
/ affected-test selection (C4) is still required.

## 6. Eviction / retention observations

**The S1 workloads saturate the 16 MiB shared semantic retention budget but do
not increment `retention.evicted`.** The original S1 harness version dropped
`functions.retention` (its session reply carried it, but the harness kept only
`wall_ms`/`reused`/`request`; `work-report-v1` then had no retention field), so
this was captured with a thin probe over the same `check-session` protocol and
the same harness-generated sources (`retention-*.json`). The repaired harness
now preserves the complete work report and semantic retention/per-kind/eviction
counters directly.

| project | retained_bytes | budget | ordinary / symbolic / specialization bytes | `retention.evicted` |
| --- | ---: | ---: | --- | ---: |
| ordinary-10k | 5,651,180 | 16,777,216 | 5,651,180 / 0 / 0 | 0 |
| managed-10k | 5,493,510 | 16,777,216 | 5,097,546 / 2,116 / 393,848 | 0 |
| ordinary-100k | **16,776,636** | 16,777,216 | 16,776,636 / 0 / 0 | **0** |
| managed-100k | **16,775,706** | 16,777,216 | 16,379,742 / 2,116 / 393,848 | **0** |

Interpretation: the budget is enforced by retaining only the prefix that fits
and refusing the rest (`no-retained-body` bypass), not by oldest-first
eviction. At 100k this leaves only ~8.8k of 33.5k ordinary bodies retained; the
other ~24.6k are rechecked on **every** edit. The fix's durable reuse is real
(it reuses 8820 bodies where the prior baseline reused 0). The 20-sample
profile sweep in
[s1-profile-warm-2026-09-16.md](s1-profile-warm-2026-09-16.md) still shows a
modest benefit rather than a dominant wall-time effect: raising the budget to
64/128 MiB removes nearly all ordinary rechecks, but dependency-key preparation
and retention/publication remain, and host variance keeps the p50 comparison
from demonstrating a stable large win. Retention truncation is therefore a
demonstrated work multiplier and a moderate session benefit, not the established
dominant latency cost.

**Where eviction does happen (existing focused retention tests).** The
repository's focused retention contract tests force genuine old-to-new eviction
and were run with the corrected worktree (rc=0, PASS):

- `shared retention budget bounds distinct specializations and eviction forces
  fresh checks`: `retention: budget=5766 retained=2946 spec_bytes=2154
  evictions=39 oldest_fresh_checks=+1` — after eviction the oldest specialization
  is checked fresh instead of reused.
- `shared retention budget bounds many distinct symbolic templates`:
  `symbolic retention: budget=4354 retained=4276 symbolic_bytes=4276 templates=8
  evictions=8 warm_fresh=+4 warm_reused=+8`.

**Gap:** the S1 workloads have only 128 stable specializations (~394 KiB), far
below the 16 MiB budget, and their ordinary bodies saturate it by non-admission,
so the harness as-is does **not** measure the cost of eviction/**re-admission
churn** under a realistic large workload. Measuring that would need a workload
with >16 MiB of distinct generic specializations/symbolic templates (or repeated
provider churn). This was **not** invented here; it is recorded as an open gap.
No compiler source was modified.

## 7. Comparison to the prior S1 report

Prior report: `docs/audits/velocity-implementation/s1-report.md`, base
`5988575b`, raw under `s1/`. **Two mandatory caveats:**

1. **Optimize mode differs.** Prior reproduction is plain `zig build` →
   `standardOptimizeOption` default Debug (binary 99.4 MB); this run is
   `ReleaseFast` (28.4 MB). Absolute latencies are not apples-to-apples.
2. **Sample counts differ at 100k.** Prior used 20 baseline samples for
   ordinary-100k and 5 for managed-100k cold/unchanged/no_cache; this run uses 10
   baseline samples for both. Edits are 20 vs 20/5.

The 100k workloads *are* comparable: prior `100k.json`/`100k-managed.json` carry
the **same generator sha256** `9cb579c34039…` as this run, and the generated line/
body counts match. The prior 10k used an earlier generator `85319c3f…` (identical
line counts but a different generator revision), so 10k comparison is only
approximate.

### Optimize-mode-independent comparison: work counters

| workload | state | prior S1 (Debug) checked/reused | corrected (ReleaseFast) checked/reused | what changed |
| --- | --- | --- | --- | --- |
| ordinary-10k | implementation_edit | 3139/0 (`semantic-reuse-unavailable`) | **2/3137** | C2 persistent body reuse now works |
| ordinary-10k | constant_edit | 3139/0 | **67/3072** | reuse now works for constant edits |
| ordinary-10k | session_impl | 3138/3139 reused (10k session reuse existed) | 3139 total, ~full reuse | maintained |
| ordinary-100k | implementation_edit | 33475/0 | **24655/8820** | partial reuse appears, capped by 16 MiB |
| ordinary-100k | session_impl | 33475/0, `bypassed=1, retained 0` | 24202/9273 | session no longer bypasses, still capped |
| managed-100k | implementation_edit | 32708/0, specs 128 | 24137/8571, specs 128/0; **specialization_bodies 64/64** | partial ordinary reuse; concrete specialization bodies replay 64/64, with 64 misses `specialization-missing-instance-identity` |

So the budget-accounting work already converts "reuse every body" from 0 to
8820/33475 at 100k and to near-full reuse at 10k. Raising the budget to 64/128
MiB reaches 33473/33475 reused ordinary bodies in the corrected profile, so the
ordinary retention cap is a real work multiplier. It is not, by itself, the
dominant latency explanation: after near-total replay the profile still measures
dependency-key preparation at 608-826 ms p50 and retention/publication at
384-443 ms p50. The old `instantiated_specializations 128/0` counter is checked
program shape; the actual specialization-body counter is `64/64`.

### Absolute comparison (conflates Debug vs ReleaseFast — read with the warning)

`p50` (prior Debug number → corrected ReleaseFast number):

| workload/state | prior p50 | corrected p50 | corrected/prior |
| --- | ---: | ---: | ---: |
| ordinary-10k cold | 391.6 | 109.6 | 0.28× |
| ordinary-10k no_cache | 284.2 | 58.1 | 0.20× |
| ordinary-10k implementation_edit | 281.9 | 66.6 | 0.24× |
| ordinary-10k session_impl | 212.9 | 35.4 | 0.17× |
| ordinary-10k forced_tests p95 | 7834.8 | 727.5 | 0.09× |
| managed-10k cold | 588.8 | 126.1 | 0.21× |
| managed-10k implementation_edit | 456.5 | 93.1 | 0.20× |
| managed-10k forced_tests p95 | 7250.0 | 765.5 | 0.11× |
| ordinary-100k cold | 3730.8 | 1249.0 | 0.33× |
| ordinary-100k unchanged | 910.1 | 97.2 | 0.11× |
| ordinary-100k no_cache | 2892.8 | 1026.8 | 0.35× |
| ordinary-100k implementation_edit | 2854.0 | 1001.5 | 0.35× |
| ordinary-100k session_impl | 3098.6 | 1001.4 | 0.32× |
| managed-100k cold | 4099.0 | 1215.2 | 0.30× |
| managed-100k implementation_edit | 3254.9 | 1045.7 | 0.32× |
| managed-100k provider_edit | 3560.1 | 1068.1 | 0.30× |

Some of this is the Debug→ReleaseFast change and some is the fix; the
work-counter table above separates the two. The 100k objective remains unmet in
both builds.

## 8. Top remaining compilation/lowering costs (next implementation step)

1. **Dependency-key preparation is the largest demonstrated warm-check cost
   after near-total replay.** The corrected profile measures
   `dependency_key_preparation` at 608–826 ms p50 across full-reuse budgets
   (roughly 40–50% of measured total), while fresh ordinary body checking falls
   to 1.3–1.5 ms p50 and ordinary replay is 52–67 ms p50. The cost is
   `semantic_key.prepare` building stable function identities and dependency
   contexts for every AST function before any body lookup. The next package
   should make that preparation incremental or session-reusable for unchanged
   declaration regions, with exact dependency-digest preservation; this package
   deliberately did not change cache identities.
2. **Retention/publication is the second-largest measured phase, and a larger
   budget alone is only a trade.** At 64/128 MiB all 33,473 ordinary bodies are
   retained and fresh ordinary checks fall to two, but `retention_store_io`
   (`Session.remember` plus durable publication) rises to 384–443 ms p50 because
   full retention transfers/publishes O(N) entries. Raising the default budget
   from 16 MiB would trade memory for fewer checks; it would not remove the
   dominant key-preparation cost and needs its own measured policy decision.
   Reducing the O(N) publication/transfer work is a bounded follow-up.
3. **Managed concrete-specialization body replay is partial.** The corrected
   profile reports `specialization_bodies 64/64` across 16/32/64/128 MiB; the
   remaining 64 misses are `specialization-missing-instance-identity`, and
   `instantiated_specializations 128/0` is not body-replay evidence. Nested
   specialization identity materialization/remapping is the bounded follow-up;
   sparse remapping alone does not make those 64 identities replayable.
4. **Affected-test feedback at 100k remains blocked by whole-project lowering.**
   The 150 s time-box cannot complete the warm native build; the 10k cold build
   is already 84–94 s. Lazy lowering plus affected-test selection is required
   before the <1 s affected-test objective can be measured at 100k. Keep this
   work separate from whole-project preparation/lowering and linking.
5. **Cold/first check ~1.5–2.2 s and RSS ~0.53–0.60 GiB at 100k under load.**
   `no_cache` (33,475 bodies) is ~1.3–1.5 s p50 and RSS ~0.51–0.53 GiB. The
   parser is not the problem (edits replay 65/66 modules). Per-body check
   throughput and check-time memory remain throughput levers after the
   dependency-key and publication work.
6. **Eviction-cost measurement gap.** Add a realistic workload whose distinct
   specializations/symbolic templates exceed the chosen budget or churn providers
   to measure eviction/re-admission cost; the current managed family fills the
   16/32 MiB budgets and evicts generic entries, but the stable 128-specialization
   workload does not cover churn.

## 9. Accuracy notes / limitations

- Headline numbers use the low-load pass only; the load-contaminated first pass
  is preserved in `10k.json`/`100k.json` and must not be quoted for p95.
- The host was shared even in the low-load pass (one competing `mylang run`), so
  numbers are slightly pessimistic.
- Forced-test memory is a lower bound (host build children excluded).
- `signature_edit` for managed and `union`/`provider`/`effect` for ordinary are
  unsupported by the harness generator, marked unsupported rather than zero.
- 100k navigation call depth is unsupported (`NavigationLimit`), marked as such.
- **Binary-identity incident (resolved).** Running `zig build test-units` for the
  focused retention tests at 13:47:44 also executed the build's install step
  (`guardian.addAllChecks(..., b.getInstallStep(), ...)`), which overwrote
  `zig-out/bin/mylang` with a default-optimize **Debug** binary (106,289,826
  bytes). The focused retention tests exercise `src/` compiled into the test
  binary, so their result is unaffected. Every harness measurement through 13:45
  recorded compiler sha `58a39d62…` in its JSON and used the ReleaseFast binary;
  the retention probes (13:47:26–28) also preceded the overwrite. The first 100k
  forced-test attempt (13:48–13:53) ran against the accidental Debug binary and
  was discarded; it was re-run at 13:57 after a deterministic
  `zig build -Doptimize=ReleaseFast` restore reproduced sha `58a39d62…` exactly,
  and the report and `100k-forced-attempt.json` cite the re-run. The retention
  probes were also re-run after the restore with identical values.
- No compiler/source behavior was changed. This task added only the new untracked
  evidence directory and this report to the main checkout. Separately, during the
  measurement window another agent concurrently modified 23 tracked `docs/`/
  `src/` files in the main checkout (mtimes 13:18–13:23 UTC); none of those files
  are used by the measured worktree, which is a clean checkout of `3f76446c`.
  This task did not touch them.
