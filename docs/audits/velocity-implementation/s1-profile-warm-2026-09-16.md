# Warm-check phase and retention profile — 2026-09-16

Status: **instrumentation and measurement package; no language-semantic change and
no semantic-cache redesign.** This report corrects the S1 priority order with a
20-sample fresh-process budget sweep and phase-level attribution after
near-total ordinary-body replay.

## Identity

| Item | Value |
| --- | --- |
| Worktree | `/home/epentland/ai/canopy/mylang-worktrees/velocity-profile-warm` |
| Branch | `codex/velocity-profile-warm` |
| Base commit | `2afef03c` |
| Compiler | `zig build -Doptimize=ReleaseFast`; `zig-out/bin/mylang` |
| Compiler SHA-256 | `1d4603442559c8c826065e6841203c840ba1c8cece2983d215666f87a221c7df` |
| Features compiler SHA-256 | `ecef974275f819372ad59a1607fef5ad8f88393df49f0cb28b54fc3bda7e974d` |
| Zig | `0.17.0-dev.1683+5ceec001b` |
| Host | 20-thread x86_64 Linux; loads recorded per run, 3.96–14.10 |

Raw evidence and replicable summaries are in
[`s1-profile-warm-2026-09-16/`](s1-profile-warm-2026-09-16/): `summary.json`,
`summary-tables.md`, and gzipped per-budget `raw/*.json.gz`/`*.csv.gz` files
containing every complete `work-report-v1`, `phase-timings-v1` record and
`check-session-v1` probe reply.

## Commands

ReleaseFast build:

```sh
cd /home/epentland/ai/canopy/mylang-worktrees/velocity-profile-warm
zig build -Doptimize=ReleaseFast --summary all -j8
```

Each workload/budget was measured with the same process-level workload and
cache policy; only the semantic retention cap changed through the
measurement-only environment control `MYLANG_SEMANTIC_BUDGET`:

```sh
for family in ordinary managed; do
  for budget_mib in 0 16 32 64 128; do
    MYLANG_SEMANTIC_BUDGET=$((budget_mib*1024*1024)) \
      python3 scripts/profile_large_project.py \
      --compiler "$PWD/zig-out/bin/mylang" \
      --output "docs/audits/velocity-implementation/s1-profile-warm-2026-09-16/raw/${family}-100k-budget-${budget_mib}.json" \
      --workdir "/tmp/mylang-profile-sweep/${family}-100k-budget-${budget_mib}" \
      --sizes 100000 --families "$family" \
      --samples 20 --baseline-samples 20 --extra-samples 0 \
      --session-samples 20 --test-samples 0 \
      --states cold,unchanged,no_cache,implementation_edit,session_implementation_edit \
      --session-probe --session-probe-checks 2 --timeout 600
  done
done
```

The `--no-cache` state is the no-retention control. `cold` deletes the cache
before every sample. `unchanged` and edit states require a successful warm-up
check before any sample is measured; failed or timed-out warm-ups are marked
`blocked` and excluded from summaries. CSV/JSON summaries contain only successful
samples in p50/p95.

Summarize the raw evidence:

```sh
python3 scripts/summarize_profile_warm.py \
  --evidence-dir docs/audits/velocity-implementation/s1-profile-warm-2026-09-16/raw \
  --output docs/audits/velocity-implementation/s1-profile-warm-2026-09-16/summary.json \
  --markdown docs/audits/velocity-implementation/s1-profile-warm-2026-09-16/summary-tables.md
```

## Instrumentation convention

`--timings=json` still emits `phase-timings-v1`. For project commands the old
composite `frontend` record is replaced by disjoint `inclusive:false` records;
only `total` is `inclusive:true`. The new/existing project records are:

| Phase | Meaning |
| --- | --- |
| `source_load_parse` | source/header loading and import discovery |
| `syntax_replay` / `syntax_parse` | parsed syntax copied from cache vs freshly lexed/parsed |
| `declarations_interfaces` | declaration/index/export and exported-signature work, excluding syntax acquisition |
| `source_merge` | module syntax relocation/merge into the project compilation |
| `dependency_key_preparation` | `semantic_key.prepare`: stable function identities, declaration regions and per-body dependency contexts |
| `symbolic_templates` | abstract/symbolic generic-template check or replay |
| `ordinary_body_replay` | ordinary `Session.lookup` path, including hit copies and miss detection |
| `specialization_body_replay` | concrete-specialization `lookupSpecialization` path |
| `fresh_body_check` | `Checker.checkFunction` for bodies not answered by the ordinary or specialization stores |
| `entry_adaptation` | synthesized entry adapter construction |
| `effect_origin_passes` | `effects.check`, including the mutation/origin pass |
| `domain_codec_validation` | domain codec validation |
| `warning_derivation` | binding/warning derivation |
| `retention_store_io` | `publishSpecializationSession` plus `Session.remember`: in-memory retention transfer/publication and durable-store publication |

The timing recorder disables clock reads by default, ignores record overflow
instead of panicking, and never participates in cache keys, acceptance,
diagnostics or work-report counts. `ordinary_body_replay` includes the miss
probe, and `retention_store_io` includes in-memory transfer/compaction as well as
store I/O; they are not narrower syscall-only timers.

## Budget sweep

All rows are 100k-line workloads with 20 successful samples per state. Peak RSS
is the maximum successful-sample `ru_maxrss`. p50/p95 are honest observations of
this shared host, but the host was not idle; use the phase shares for attribution
and the wall numbers only with the load caveat below.

### ordinary-100k

| semantic budget | retained ordinary bytes | edit checked/reused | edit p50 / p95 ms | session edit p50 / p95 ms | edit peak RSS KiB |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 MiB | 0 | 33,475 / 0 | 1406.3 / 2237.8 | 1462.3 / 1742.4 | 410,920 |
| 16 MiB | 16,775,562 | 24,655 / 8,820 | 1550.8 / 2278.2 | 1373.5 / 1512.2 | 446,680 |
| 32 MiB | 33,553,946 | 15,815 / 17,660 | 1338.4 / 2057.2 | 1254.2 / 1594.2 | 485,032 |
| 64 MiB | 63,644,070 | 2 / 33,473 | 1541.4 / 3849.7 | 1729.7 / 1955.9 | 555,256 |
| 128 MiB | 63,644,070 | 2 / 33,473 | 1807.9 / 3252.8 | 1806.0 / 1986.8 | 534,328 |

### managed-100k

| semantic budget | retained bytes (ordinary / symbolic / specialization) | edit checked/reused | specialization bodies checked/reused | symbolic templates checked/reused | edit p50 / p95 ms |
| ---: | --- | ---: | ---: | ---: | ---: |
| 0 MiB | 0 / 0 / 0 | 32,708 / 0 | 128 / 0 | 2 / 0 | 1290.9 / 1423.7 |
| 16 MiB | 16,377,934 / 2,116 / 393,848 | 24,137 / 8,571 | **64 / 64** | **0 / 2** | 1446.7 / 1501.8 |
| 32 MiB | 33,158,438 / 2,116 / 393,848 | 15,628 / 17,080 | **64 / 64** | **0 / 2** | 1743.7 / 2151.4 |
| 64 MiB | 59,408,970 / 2,116 / 393,848 | 130 / 32,578 | **64 / 64** | **0 / 2** | 1535.0 / 1640.3 |
| 128 MiB | 59,408,970 / 2,116 / 393,848 | 130 / 32,578 | **64 / 64** | **0 / 2** | 1650.7 / 1938.1 |

At 64/128 MiB the ordinary body set fits (60,639,212 owned bytes), so edit
samples check only the edited body and replayed dependent work; fresh ordinary
checking falls to 1–2 bodies. The budget increase is a real reuse win but, in
these runs, it does not produce a reliable wall-time win: the measured p50 is
dominated by other phases and by host variance. The 16 MiB run demonstrates the
S1R2 counter directly with `specialization_bodies 64/64`; the old
`instantiated_specializations 128/0` counter is checked-program shape, not
body-replay work.

## Largest demonstrated warm-check costs

Implementation-edit exclusive phase p50 values (ms):

| budget | dependency key prep | retention/store I/O | source/header | syntax replay | ordinary replay | fresh body check | total inclusive |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ordinary 0 MiB | 762.0 | 0.0 | 141.3 | 123.9 | 0.8 | 206.6 | 1403.6 |
| ordinary 16 MiB | 760.0 | 106.6 | 144.3 | 172.2 | 18.0 | 156.0 | 1546.3 |
| ordinary 64 MiB | 714.3 | 383.7 | 123.5 | 73.3 | 56.2 | **1.3** | 1531.4 |
| ordinary 128 MiB | 825.8 | 443.2 | 138.9 | 85.8 | 66.9 | **1.5** | 1798.1 |
| managed 16 MiB | 661.8 | 131.1 | 120.8 | 69.2 | 17.7 | 226.4 | 1442.0 |
| managed 64 MiB | 608.2 | 387.6 | 111.8 | 65.5 | 52.2 | 80.0 | 1526.0 |
| managed 128 MiB | 676.9 | 406.9 | 123.9 | 70.7 | 54.2 | 85.0 | 1642.2 |

The largest demonstrated warm-check cost after near-total ordinary replay is
**`dependency_key_preparation`**: 608–826 ms p50 across the full-reuse budgets,
roughly 40–50% of measured total and roughly six to ten times larger than fresh
body checking at 64/128 MiB. It calls `semantic_key.prepare`, which builds
stable function keys and dependency contexts for every AST function before any
body lookup. Fresh ordinary body checking is not the remaining cost at full
retention (`1.3–1.5 ms` p50); managed fresh body checking remains `80–85 ms`
because 64 concrete specializations and generic bodies still miss.

The second-largest phase is **`retention_store_io`** (`384–443 ms` p50 at
64/128 MiB). At full retention it includes O(N) in-memory transfer/publication of
33k retained entries plus durable-store publication, so it is not pure
filesystem I/O. Source/header, syntax replay, ordinary replay, source merge and
effect/origin work are individually smaller (`36–139 ms` p50).

The uninstrumented remainder (total minus recorded phases) is roughly `0.09–0.14
s`; it includes catalog collection, process startup, diagnostics/reporting,
CLI/cache policy, frontend-verdict handling and timer overhead. Allocation/copy
volume was not separately measurable with this harness; peak RSS and exact
retained bytes are recorded instead.

## Next optimization

The next package should target **`semantic_key.prepare` / dependency-key
preparation**, not a larger retention budget and not fresh body checking. A
bounded design would preserve stable keys/contexts for unchanged declaration
regions across an in-process session or across an edit, invalidating only
changed bodies and their dependency closures. Because that touches dependency
identity and cache admission, it must preserve exact per-body context digests
and negative lookups; this package leaves the implementation to a separately
tested cache-identity change rather than making a speculative edit here.

A secondary bounded optimization is reducing O(N) `Session.remember` publication
at full retention. Raising the default budget from 16 MiB to 64 MiB is only
justified if the memory increase is accepted; it removes ordinary rechecks but
does not remove the dominant key-preparation cost.

## Corrections carried into the S1 report

- Retention truncation is a demonstrated source of extra body checks and a
  modest session benefit. It is not the established dominant wall-time cost.
- Managed concrete-specialization body replay works partially: the 16/32/64/128
  MiB runs report `specialization_bodies 64/64`; the leftover 64 misses are
  `specialization-missing-instance-identity`. `instantiated_specializations
  128/0` is not body-replay evidence.
- Whole-project preparation/lowering and linking are separate from test
  selection; `check-project` never lowers/emits/links, and the C4 affected-test
  path should be measured separately from whole-project preparation.

## Limitations and blockers

- The shared host was loaded by other agents for every run (`/proc/loadavg`
  3.96–14.10). p50/p95 are observed values, not clean acceptance-quality
  absolute latencies; the phase shares are the defensible evidence.
- The phase attribution uses fresh-process `check-project --timings=json` after
  a successful warm-up. `check-session` rejects `--timings=json`, so the
  in-process session probes preserve counters/retention/miss reasons but do not
  carry phase timings.
- The sweep does not measure allocation/copy volume beyond RSS and owned
  retention bytes, and it does not vary native lowering/linking/test-selection
  costs.
- `MYLANG_SEMANTIC_BUDGET` is a measurement-only control. Its default remains the
  production 16 MiB budget; no acceptance or language behavior changes when it
  is unset.
