# S1 — Representative workloads and consistent resource budgets

Status: **measurement package; one-shot check/test baselines collected and the
existing generator repaired. No language feature was added and no loader limit
was changed.** The 100k check-feedback objective is **not met at this baseline**;
the measured causes are recorded below.

Prepared on branch `codex/velocity-s1`, base commit
`5988575bf25ba96f1e9f5f79c8c824c1852a661c`. Raw samples are checked in beside
this report under `docs/audits/velocity-implementation/s1/`.

## 1. Identity

| Item | Value |
| --- | --- |
| Branch | `codex/velocity-s1` |
| Base SHA | `5988575bf25ba96f1e9f5f79c8c824c1852a661c` |
| `zig` on PATH | `/home/epentland/.local/bin/zig`, `0.17.0-dev.1683+5ceec001b` |
| `zig-out/bin/mylang` sha256 | `df7e16a1b5b00a3ff188c57c5f89d3d4ae20494ae8a5733f30ab15ecd638bc40` |
| Compiler identity (`mylang --features`) | `34e66576d40e60c998c102c105de07cd49a43f8a0a99ebba046039cadb41908f` |
| `zig-out/bin/qbe` sha256 | `a612d0ebae23b878f7e8e1845d6624b3f9a011cec159f823af29a38e3709b67a` |
| QBE vendored version | `1.3` (`.qbeversion`) |
| Generator sha256 | recorded in each JSON artifact (`generator_sha256`); `85319c3f…` for the 10k/maintained runs, `bc05abf…` for the 100k checks, see each file |
| Machine | `linuxserver`: Intel i7-12700H (20 threads), Ubuntu 26.04 LTS, Linux 7.0.0-31, 30 GiB RAM |
| OS/arch | `Linux 7.0.0-31-generic`, `x86_64` |

**Reference-machine caveat.** The machine is shared with other implementation
agents. A `zig build test-units` process from another agent and a `netlisp`
process were active during part of the collection (load average ~4 on 20
threads). Every measured command ran sequentially inside one harness, no other
S1 workload ran concurrently, and the harness records each sample's own wall
time and RSS, but the machine was not fully idle. Paired states were collected
in the same session, so relative comparisons remain meaningful; absolute
latencies may be slightly pessimistic.

## 2. Harness repair and reproduction

`scripts/profile_large_project.py` is the repaired harness. The previous
revision emitted removed brace/`fn` syntax and never validated it, so its
numbers could not be used. The repaired script:

- generates current Python-indented `module`/`import`/`export`/`def`/`effects`
  source and validates every workload with `check-project --no-cache --report`
  before timing it; one small project per family is also run natively;
- implements three families: ordinary call graphs, managed data with
  generic/named-constraint providers, and the maintained `src/schematic/guest`
  and `selfhost/prototype` programs copied into the scratch tree;
- times fresh processes (process start through command exit), records child
  `ru_maxrss`, parses the compiler's own `work-report-v1` for real execution-site
  stage counts, and records `list-modules` module/import structure plus an
  `index-project` call-graph depth where navigation accepts the workload;
- supports cold, unchanged, no-cache, implementation-edit, constant-edit,
  signature-edit, union-edit, effect-edit, provider-edit and forced-test states,
  plus in-process `check-session` edit states;
- gives every edit sample a deterministic token unique to that sample, so a
  stored whole-project verdict for a previous sample cannot satisfy the next one;
- probes bounded failure at 257 modules, a >4 MiB file and a >16 MiB project;
- writes raw JSON plus a per-sample CSV after each workload.

Reproduce with (examples used for the checked-in artifacts):

```sh
zig build

python3 scripts/profile_large_project.py --compiler zig-out/bin/mylang \
  --output docs/audits/velocity-implementation/s1/10k.json --workdir /tmp/s1-10k \
  --sizes 10000 --families ordinary,managed --samples 20 --baseline-samples 20 \
  --extra-samples 5 --test-samples 3 --timeout 900 --probe-limits

python3 scripts/profile_large_project.py --compiler zig-out/bin/mylang \
  --output docs/audits/velocity-implementation/s1/100k.json --workdir /tmp/s1-100k \
  --sizes 100000 --families ordinary --samples 20 --baseline-samples 20 \
  --session-samples 20 --test-samples 0 --timeout 900 \
  --states cold,unchanged,no_cache,implementation_edit,constant_edit,signature_edit,union_edit,provider_edit,effect_edit,session_implementation_edit,session_constant_edit
```

## 3. Method

- Wall time = `time.monotonic()` around a forked/exec'd child: process start,
  dynamic linking, source load, check/test work and exit are inside the sample.
- Percentile: **nearest-rank**, ascending sort, index `ceil(0.95*n)-1`
  (`scripts/profile_large_project.py: percentile_nearest_rank`).
- Every one-shot sample runs with `--report`; the recorded `stage` object is that
  sample's own `work-report-v1`. Session samples record each
  `check-session-v1` reply's `work.request` deltas.
- Memory is the child's `ru_maxrss` from `wait4`, per sample; reported as the
  maximum over samples. Forced-test memory is a lower bound: QBE/Zig
  grandchildren are not in the direct child's `ru_maxrss`.
- Warm-up: one successful check populates the persistent cache before
  `unchanged` and all edit states; cold samples delete the cache directory
  before each sample. Forced tests run one complete build (recorded separately
  as `cold_build`) before the measured `--force` runs.
- A rejected size/limit is recorded as unsupported, never as a timing sample.

## 4. Limits and bounded failure

The harness records every subsystem budget it can find and verifies the literal
still appears in the owning source (`limits` in each JSON, all
`all_patterns_present=true` for this commit):

| Subsystem | Budget | Source |
| --- | --- | --- |
| check/build loader | 256 modules, 4096 imports, 4 MiB/file, 16 MiB total | `src/project.zig` |
| configuration | 1 MiB `mylang.json`/policy | `src/project_config.zig` |
| navigation index | 50000 symbols, 250000 references | `src/navigation.zig` |
| native test snapshot / providers | 16 MiB, 50000 entries | `src/native_test_snapshot.zig` |
| Python navigation inventory | 16 MiB, 50000 entries | `scripts/navigate.py` |
| package materialization | 16 MiB | `scripts/packages.py` |
| agent store materialization | 8 MiB/file, 64 MiB total | `scripts/store.py` |

Active bounded-failure evidence (10k artifact, all true):

| Probe | Observed |
| --- | --- |
| 257-module project | `E_MODULE_LIMIT` at `m255.my:2:8` |
| single source file over 4 MiB | `E_PROJECT_BYTES: cannot load main.my: TooLarge` |
| project source over 16 MiB | `E_PROJECT_BYTES: cannot load m4.my: TooLarge` |

Concrete inconsistencies found and **reported, not changed**:

1. **Module/import counts are bounded only by the loader.** A 257-module project
   can be snapshotted, inventoried or package-materialized and then fail ordinary
   checking. A consistent fix must add the shared module/import budget to
   `src/native_test_snapshot.zig`, `scripts/navigate.py` and `scripts/packages.py`;
   changing `src/project.zig` alone is insufficient.
2. **Store byte budgets exceed the compiler budgets.** `scripts/store.py` allows
   8 MiB/file and 64 MiB total against the loader's 4 MiB/16 MiB, so the store
   accepts projects the compiler rejects.
3. **Navigation has separate symbol/reference budgets.** Both 100k workloads
   check successfully but `index-project` exits 2 with
   `mylang: host failure: NavigationLimit` (50000 symbols/250000 references).
   The call-graph depth is therefore *unsupported* at 100k, not zero.
4. **The in-process checked-body cache reuses the 16 MiB source budget as a
   retained-tree budget** (`src/main.zig:1715` initializes the semantic cache at
   `16 * 1024 * 1024`). At 100k the ordinary workload retains 33475 bodies; the
   semantic cache reports `functions.bypassed=1` and `reused=0`, so every edit
   rechecks every body even in one session. At 10k the same path reuses bodies.
   This is the measured explanation for the missing 500 ms edit target, but
   raising the number without measuring the retained-tree size and the other
   budget consumers would repeat the current inconsistency; it is left open.

No loader/limit constant was changed: the 500k source fits the existing loader
budget (below), so no acceptance or resource measurement justified raising it.

## 5. Workloads

Generated source is deterministic; the harness reports the actual on-disk
line/byte counts and the compiler's own module/import/body/specialization counts.
`checked bodies` is `work-report-v1.checked_bodies.performed` from a fresh
`--no-cache` check; it equals the function count for the ordinary family and
counts template/provider bodies for the managed family. Call depth is from
compiler-resolved `index-project` references.

### 10k workloads

| workload | status | lines | bytes | modules | edges | mod depth | checked bodies | specializations | call depth |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ordinary-10k | measured | 9935 | 186437 | 66 | 192 | 66 | 3139 | 0 | 113 |
| managed-10k | measured | 10022 | 196210 | 68 | 130 | 3 | 2756 | 128 | 35 |

### 100k workloads

| workload | status | lines | bytes | modules | edges | mod depth | checked bodies | specializations | call depth |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ordinary-100k | measured | 100943 | 1969413 | 66 | 192 | 66 | 33475 | 0 | unsupported (NavigationLimit) |
| managed-100k | measured | 99878 | 1954866 | 68 | 130 | 3 | 32708 | 128 | unsupported (NavigationLimit) |

### Maintained workloads (natural size; below 10k, not scaled)

| workload | status | lines | bytes | modules | edges | mod depth | checked bodies | specializations | call depth |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| maintained-guest (`src/schematic/guest/main.my`) | measured | 2186 | 67782 | 14 | 42 | 9 | 114 | 0 | unsupported |
| maintained-prototype (`selfhost/prototype/bench.my`) | measured | 720 | 22812 | 2 | 1 | 2 | 22 | 0 | unsupported |

## 6. Results

`n` is the measured sample count; unsupported states have no samples.
Peak RSS is KiB for the samples of that state (not the largest tree value ever).

### 10k

| workload | state | n | median ms | p95 ms | peak RSS KiB |
| --- | --- | ---: | ---: | ---: | ---: |
| ordinary-10k | cold | 20 | 391.6 | 398.9 | 57344 |
| ordinary-10k | unchanged | 20 | 100.8 | 105.5 | 30948 |
| ordinary-10k | no_cache | 20 | 284.2 | 293.0 | 57216 |
| ordinary-10k | implementation_edit | 20 | 281.9 | 290.2 | 47584 |
| ordinary-10k | constant_edit | 20 | 282.4 | 288.6 | 47488 |
| ordinary-10k | signature_edit | 20 | 281.7 | 290.3 | 47584 |
| ordinary-10k | session_implementation_edit | 20 | 212.9 | 213.4 | - |
| ordinary-10k | session_constant_edit | 20 | 211.3 | 212.8 | - |
| ordinary-10k | forced_tests (cold build 106.4 s) | 3 | 6953.5 | 7834.8 | 123580 |
| managed-10k | cold | 20 | 588.8 | 630.0 | 60048 |
| managed-10k | unchanged | 20 | 145.8 | 165.3 | 30064 |
| managed-10k | no_cache | 20 | 439.7 | 451.0 | 59848 |
| managed-10k | implementation_edit | 20 | 456.5 | 559.0 | 50832 |
| managed-10k | constant_edit | 20 | 441.6 | 449.3 | 50608 |
| managed-10k | union_edit | 5 | 439.9 | 445.7 | 50412 |
| managed-10k | provider_edit | 5 | 446.8 | 451.2 | 50928 |
| managed-10k | effect_edit | 5 | 437.1 | 439.7 | 50832 |
| managed-10k | session_implementation_edit | 20 | 360.7 | 365.5 | - |
| managed-10k | session_constant_edit | 20 | 365.2 | 370.8 | - |
| managed-10k | forced_tests (cold build 89.8 s) | 3 | 7225.5 | 7250.0 | 118144 |

### 100k

| workload | state | n | median ms | p95 ms | peak RSS KiB |
| --- | --- | ---: | ---: | ---: | ---: |
| ordinary-100k | cold | 20 | 3730.8 | 4850.1 | 474324 |
| ordinary-100k | unchanged | 20 | 910.1 | 956.5 | 48460 |
| ordinary-100k | no_cache | 20 | 2892.8 | 3094.9 | 474240 |
| ordinary-100k | implementation_edit | 20 | 2854.0 | 3555.3 | 362116 |
| ordinary-100k | constant_edit | 20 | 2839.1 | 2890.5 | 361900 |
| ordinary-100k | signature_edit | 20 | 2886.2 | 3289.1 | 362096 |
| ordinary-100k | session_implementation_edit | 20 | 3098.6 | 4015.3 | - |
| ordinary-100k | session_constant_edit | 20 | 3242.2 | 4022.4 | - |
| managed-100k | cold | 5 | 4099.0 | 4156.1 | 480796 |
| managed-100k | unchanged | 5 | 903.3 | 905.8 | 47728 |
| managed-100k | no_cache | 5 | 3449.4 | 3951.0 | 480484 |
| managed-100k | implementation_edit | 20 | 3254.9 | 3314.3 | 370244 |
| managed-100k | constant_edit | 20 | 3741.4 | 4915.5 | 369980 |
| managed-100k | union_edit | 5 | 3669.5 | 3742.7 | 364732 |
| managed-100k | provider_edit | 5 | 3560.1 | 3810.7 | 370064 |
| managed-100k | effect_edit | 5 | 3498.9 | 3626.2 | 368320 |
| managed-100k | session_implementation_edit | 20 | 3373.4 | 3630.4 | - |
| managed-100k | session_constant_edit | 20 | 3429.6 | 3958.4 | - |

### Maintained

| workload | state | n | median ms | p95 ms | peak RSS KiB |
| --- | --- | ---: | ---: | ---: | ---: |
| maintained-guest | cold | 20 | 129.7 | 136.1 | 31536 |
| maintained-guest | unchanged | 20 | 42.4 | 50.6 | 16076 |
| maintained-guest | no_cache | 20 | 99.0 | 105.7 | 31368 |
| maintained-guest | implementation_edit | 20 | 109.8 | 115.8 | 28880 |
| maintained-guest | session_implementation_edit | 20 | 73.5 | 169.5 | - |
| maintained-prototype | cold | 20 | 37.8 | 47.0 | 17060 |
| maintained-prototype | unchanged | 20 | 20.0 | 23.8 | 17124 |
| maintained-prototype | no_cache | 20 | 21.2 | 26.5 | 17192 |
| maintained-prototype | implementation_edit | 20 | 16.8 | 23.8 | 17272 |
| maintained-prototype | session_implementation_edit | 20 | 2.4 | 2.6 | - |

### Real stage counts (representative samples)

| workload | state | parsed performed/reused | checked performed/reused | specializations performed | bypassed |
| --- | --- | ---: | ---: | ---: | --- |
| ordinary-10k | cold | 66 / 0 | 3139 / 0 | 0 | `semantic-reuse-unavailable` |
| ordinary-10k | unchanged | 0 / 0 | 0 / 0 | 0 | verdict replayed, `reused=true` |
| ordinary-10k | implementation_edit | 1 / 65 | 3139 / 0 | 0 | `semantic-reuse-unavailable` |
| ordinary-10k | constant_edit | 1 / 65 | 3139 / 0 | 0 | `semantic-reuse-unavailable` |
| managed-10k | implementation_edit | 1 / 67 | 2756 / 0 | 128 | `semantic-reuse-unavailable` |
| ordinary-100k | cold | 66 / 0 | 33475 / 0 | 0 | `semantic-reuse-unavailable` |
| ordinary-100k | implementation_edit | 1 / 65 | 33475 / 0 | 0 | `semantic-reuse-unavailable` |
| ordinary-100k | session_implementation_edit | 66 / 0 | 33475 / 0 | 0 | session `functions.bypassed=1`, retained 0 |
| managed-100k | implementation_edit | 1 / 67 | 32708 / 0 | 128 | `semantic-reuse-unavailable` |
| managed-100k | session_implementation_edit | 68 / 0 | 32708 / 0 | 128 | generic body disables ordinary reuse |

At 10k the in-process session path reuses 3138/3139 ordinary bodies per edit;
at 100k the same path is bypassed and rechecks 33475/33475. Generic workloads
recheck the fresh path at every size, matching the current C1/C3 limitations.

## 7. Objectives (assessed, not presumed)

Target: p95 < 500 ms check feedback and p95 < 1 s through affected tests on the
selected 100k workload. The selected 100k workload is `ordinary-100k`
(100943 lines); `managed-100k` is reported separately because API/effect edits
legitimately touch the generic specialization set.

| workload | objective | measured p95 | result |
| --- | --- | ---: | --- |
| ordinary-10k | cold check < 500 ms | 398.9 ms | **met** |
| ordinary-10k | implementation edit < 500 ms | 290.2 ms | **met** |
| ordinary-10k | API/constant edit < 500 ms | 288.6 ms | **met** |
| ordinary-10k | affected tests < 1 s | 7834.8 ms (n=3) | **not met** (cold native build 106.4 s) |
| managed-10k | cold check < 500 ms | 630.0 ms | **not met** |
| managed-10k | implementation edit < 500 ms | 559.0 ms | **not met** |
| managed-10k | constant edit < 500 ms | 449.3 ms | **met** |
| managed-10k | provider/union/effect edit < 500 ms | 439.7–451.2 ms | **met** |
| managed-10k | affected tests < 1 s | 7250.0 ms (n=3) | **not met** (cold native build 89.8 s) |
| ordinary-100k | cold check < 500 ms | 4850.1 ms | **not met** |
| ordinary-100k | implementation edit < 500 ms | 3555.3 ms | **not met** |
| ordinary-100k | API/constant edit < 500 ms | 2890.5 ms | **not met** |
| ordinary-100k | API/signature edit < 500 ms | 3289.1 ms | **not met** |
| ordinary-100k | in-process edit < 500 ms | 4015.3 ms | **not met** |
| ordinary-100k | affected tests < 1 s | not measured (blocked) | **not achieved / unmeasured** (§7.1) |
| managed-100k | cold check < 500 ms | 4156.1 ms | **not met** |
| managed-100k | implementation edit < 500 ms | 3314.3 ms | **not met** |
| managed-100k | constant edit < 500 ms | 4915.5 ms | **not met** |
| managed-100k | provider/union/effect edit < 500 ms | 3626.2–3810.7 ms | **not met** |
| managed-100k | affected tests < 1 s | not measured | **not achieved / unmeasured** (§9) |
| maintained-guest | cold check < 500 ms | 136.1 ms | **met** (natural 2186-line fixture, not 100k) |
| maintained-prototype | cold check < 500 ms | 47.0 ms | **met** (natural 720-line fixture, not 100k) |

**Achieved/not-achieved for 100k:** the explicit result is **not achieved** at
this baseline. The p95 check-feedback latencies are 2.9–4.9 s, roughly 6–10x the
target. The measured causes are: (a) one-shot edit checks recheck every body
because C2 persistent checked-body reuse is not implemented
(`semantic-reuse-unavailable`), and (b) even in-process reuse is bypassed at
100k because the retained checked-tree cache is bounded at the same 16 MiB as
the source budget, which cannot hold 33475 ordinary bodies. The parser cache
does reuse 65/66 modules, so the remaining cost is semantic body checking. API
constant edits affected all 33475 bodies rather than a small private set, which
is reported separately from private edits as required.

### 7.1 100k affected-test feedback: unmeasured / blocked

The `forced_tests` state for the selected 100k workload was attempted with the
standard harness and then time-boxed and killed. Exact command:

```sh
python3 scripts/profile_large_project.py --compiler zig-out/bin/mylang \
  --output docs/audits/velocity-implementation/s1/100k-forced.json \
  --workdir /tmp/s1-100k-tests --sizes 100000 --families ordinary \
  --samples 2 --test-samples 1 --timeout 900 --states forced_tests --no-call-depth
```

The underlying process observed was:

```text
mylang test /tmp/s1-100k-tests/sources/ordinary-100k/main.my --json \
  --cache-dir=/tmp/s1-100k-tests/caches/ordinary-100k
  -> mylang build .../main.my --project --library -o .../tests.so \
       --cache-dir .../objects/5d5f79fb... --mode Debug
```

At shutdown the native build had been running for more than 13 minutes and had
emitted 7636 object files; it was still making progress, not deadlocked, but it
had not returned a test result. The 10k cold native build took 106.4 s for 3139
bodies; the 100k project has 33475 bodies (10.7x). The 1 s affected-test target
is therefore **not achieved** and the exact 100k p95 is **unmeasured**: the
baseline lowers and links the whole checked project before running one test, and
C4 test selection/lazy lowering is not implemented. The partial cache under
`/tmp/s1-100k-tests` was deleted when the process was killed; no sample is
reported. The 10k forced-test numbers (§6) are real measured values and show the
baseline cost.

### 7.2 500k milestone

The full multi-state 500k measurement was not run inside this time box; it is
**not achieved and not measured**. A single provisional cold check of a
deterministically generated 500k ordinary project was taken separately and is
reported as a single observation, **not** a p95 and not a substitute for the
20-sample method:

| workload | lines | bytes (MiB) | modules | edges | mod depth | checked bodies | specializations | cold wall | peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ordinary-500k (n=1) | 500303 | 10028357 (9.56) | 66 | 192 | 66 | 166595 | 0 | 17.64 s | 2330656 KiB (2.22 GiB) |

The size is **accepted** by the loader (9.56 MiB total, 66 modules, largest file
well under 4 MiB) and is not a bounded-failure case. It misses the 500 ms check
target by ~35x in this one observation. A managed 500k project was generated
(64 providers, 502694 lines, 10,081,650 bytes) but was not checked. Full 500k
results, edit distributions and affected-test behaviour remain open.


## 8. Verification

- `zig build`: exit 0; Guardian diff-scoped run-all 88/88 passed.
- Commit hook: whole-tree Guardian `run-all: whole-tree run`, 88/88 passed.
- `zig build fmt-check` (no Zig source touched; must exit 0).
- `python3 scripts/profile_large_project.py --help` and smoke runs exercised the
  harness itself.
- One small generated project per family checks and runs natively during each
  harness invocation (`smoke_validation` in every JSON artifact).
- Every workload checks with `check-project --no-cache --report` before timing;
  the run stage was additionally exercised for ordinary/managed at <=10k.

Artifacts:

| Artifact | Contents |
| --- | --- |
| `docs/audits/velocity-implementation/s1/10k.json` | ordinary + managed 10k, all states, bounded-failure probes |
| `docs/audits/velocity-implementation/s1/10k.csv` | per-sample CSV for the 10k run |
| `docs/audits/velocity-implementation/s1/100k.json` | ordinary + managed 100k check states (managed merged from a second invocation) |
| `docs/audits/velocity-implementation/s1/100k.csv` | per-sample CSV for the 100k run |
| `docs/audits/velocity-implementation/s1/100k-managed.json` | raw managed-100k invocation (provenance for the merge) |
| `docs/audits/velocity-implementation/s1/maintained.json` | maintained schematic/self-host workloads |
| `docs/audits/velocity-implementation/s1/maintained.csv` | per-sample CSV for the maintained run |

## 9. Limitations and unmeasured items

- **100k affected tests: unmeasured/blocked** (see §7.1). The objective is
  reported not achieved.
- **500k: not fully measured** (see §7.2); one provisional cold check is given.
- **Mutation edits are not measured.** M2/M3 are not integrated at this base, so
  there is no checked mutation contract to edit; the plan's mutation-edit
  workload is explicitly remaining. Body, signature, constant, union, effect and
  provider edits are measured.
- **Managed signature edits are unsupported** by the generator (a generic
  signature change would require coordinated constraint/caller edits); this is
  marked unsupported in the JSON, not zero.
- **Plan-graph depth at 100k is unsupported** because `index-project` reports
  `NavigationLimit`; module-graph depth is recorded from `list-modules`.
- **Reference machine was not fully idle**; another agent's `zig build test-units`
  and `netlisp` ran during part of the collection.
- **Forced-test memory is a lower bound** for the direct child; QBE/Zig
  grandchildren are not counted.
- **Productivity trial is not run.** The five unfamiliar-code tasks (add a union
  variant, change an exported contract, repair aliasing, swap a provider,
  diagnose a runtime failure) need multiple fresh-context trials with accepted
  correct deliveries and a randomized order; that was not possible comparably in
  this time box. It is left explicitly remaining rather than claimed.
- **Integration dependencies outstanding:** C4 (test selection/lazy lowering)
  for affected-test feedback, C2/C3 for persistent checked-body and
  specialization reuse, M2/M3 for mutation edits, and the limits unification
  across loader/snapshot/package/store described in §4.

## 10. Guardian

Guardian ran during `zig build` (diff-scoped 88/88) and on the commit
(whole-tree 88/88). The concrete feedback entry is
`docs/audits/velocity-implementation/guardian-s1.md`; it records the validated
generator, edit independence, bounded-failure probes, the `--cache-dir`/session
friction, the navigation and 16 MiB semantic-cache budget findings, and the
shared-machine caveat. `~/ai/canopy/guardian-zig/FEEDBACK.md` was not edited.
