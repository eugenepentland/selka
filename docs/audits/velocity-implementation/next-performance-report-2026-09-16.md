# Next performance work report — 2026-09-16

Status: **implementation + measurement.** Two packages from the
[implementation plan](next-performance-work-plan-2026-09-16.md) landed:

1. `semantic_key.prepare` now indexes each module's export directives once
   instead of rescanning the module for every declaration.
2. A native-test provider graph is fully checked **once**: the internal
   `native-test-compile` session retains the checked compilation that produced
   the test facts, and selective lowering plus the linking driver consume it
   instead of re-checking the project in a second frontend process.

Both objectives improved materially but neither target is fully met:
ordinary-100k edits are now **549 ms p50 / 556 ms p95** (goal <500 ms).
Forced runs are **1.32 s p95 ordinary / 1.54 s p95 managed**, but forced
execution is not every affected edit: the actual 100k used-helper edit is
**1.45 s p95 ordinary / 3.47 s p95 managed** (goal <1 s). Correctness is
unchanged and the full gate is green. A later correction measures the managed
edit path and attributes its gap to object compilation, not checking.

## 1. Identity and host caveat

| Item | Value |
| --- | --- |
| Branch | `codex/velocity-integration` |
| Worktree base | `df39a308` (audit commit; production source same as `e44046a3`) |
| Measured compiler | `/tmp/vel-rf/bin/mylang`, `zig build -Doptimize=ReleaseFast --prefix /tmp/vel-rf` |
| Compiler SHA-256 | `186ac5c6f181b6026c9b4302a924c74622949fcc8d3376d6d6e99d44c1af797d` |
| `--features` compiler identity | `8c5df7ebd80b08397605865fdf8c9eb0dc116c85042b865dbfb601d14e953c5f` |
| `qbe` SHA-256 | `e8556667871eff58a795be26f9937a6778aaeef7a0a8ff6c885ce28061101fc4` |
| Zig | `0.17.0-dev.1683+5ceec001b` |
| Matrix harness | `scripts/profile_large_project.py` |
| Native probe | `docs/audits/velocity-implementation/s1-final-2026-09-16/native_probe.py` |
| Host | `linuxserver`: 12th Gen Intel Core i7-12700H, 20 threads, 30 GiB RAM |

**Host-load caveat.** The matrices ran at load 3.4 → 2.2 and the native probe
at load 2.1 → 1.1, both with other tenants active. Absolute wall times are
observed values on a shared host; work counters and phase shares are the
load-independent evidence. `/proc/loadavg` before/after is recorded in each
JSON.

**Final-binary confirmation.** After the report's headline 20-sample run, an
additional test plus error-path-only hardening changed the embedded compiler
identity; the final source was
rebuilt (`/tmp/vel-rf-final/bin/mylang`, SHA-256
`d2dde81c6d4dfd8c6397489efa379d09e7c4b5ae1db996e9482654b88acaa866`, features
identity `77df1098401ddcedb8902b0b5002c612d0eab425873ad3e898b03727dc1ee56d`)
and a 5-sample 100k confirmation (`matrix-final-confirm.json`) reproduced the
same shape at a higher host load (4.0 → 4.8): ordinary cold 912/948 ms, edit
610/614 ms, forced 1,575/1,664 ms; managed cold 996/1,034 ms, edit 716/726 ms,
forced 1,505/1,554 ms. The confirmation is a final-binary sanity check, not a
replacement for the 20-sample headline. Neither change touches
any measured success path.

**Filesystem caveat for the raw evidence.** The first matrix attempt used a
workdir under `/home`; publishing ~3,200 small semantic-cache entries per cold
sample costs ~11 ms/file on that ext4 volume (34 s for one 10k cold check)
versus ~42 ms total on tmpfs. That run was discarded and both final matrices
and the native probe used `/tmp` workdirs, matching the S1 method. The measured
compiler and source were unchanged across the discarded run.

## 2. Method

- Wall time is `time.monotonic()` around a forked/exec'd child: process start,
  dynamic linking, source load, work and exit.
- The matrix uses 20 samples for baseline/edit/session states and 5 for
  `forced_tests`; percentiles are nearest-rank (`ceil(0.95*n)-1`).
- The native probe runs `mylang test --json --report` directly with a fixed
  environment: first build, warm unchanged, forced run, used-helper edit,
  unused-helper edit, provider edit (managed) and a `--no-cache` control.
- Compared against the recorded S1-final evidence at `c18c0d18`
  (`s1-final-2026-09-16/matrix-{10k,100k}.json`, `native-probe*.json`). The
  production source between `c18c0d18` and this working tree differs only by
  these two packages, so the deltas attribute the work.

Raw evidence lives next to this report in
[`next-performance-2026-09-16/`](next-performance-2026-09-16/):
`matrix-next.json`/`.csv`, `native-probe.json`, `matrix-final-confirm.json`,
`verify_one_check.py`.

## 3. Package 1 — export indexing in `semantic_key.prepare`

`Builder` now builds one `ExportIndex` per module in `Builder.init`; each
`export NAME` directive line is stored once, keyed by its declared name and in
source order. `exportDigest` hashes only the matching lines. The hash inputs
are unchanged: the same `trimStart`-normalized line text, the same separator
set for the declared name, the same order, and the same `export-v1` domain.
Duplicate directives and same-named declarations keep their exact previous
digests.

Tests (`src/semantic_key.zig`, selected by `zig build test-units`):

- `a module export index reproduces the per-declaration scan byte for byte`
  compares the indexed digest against a preserved pre-change oracle over
  leading whitespace, trailing whitespace/`\r`, tabs, semicolons, empty and
  malformed directives, duplicate directives, dotted names and absent names.
- `export indexing visits each module byte once regardless of declaration
  count` asserts one scan per module byte instead of one module scan per
  declaration.
- `export indexing scans many small and fewer large modules once each` extends
  the parity and one-scan-per-byte assertions to a many-small/fewer-large module
  pair.

Phase cost at 100k `implementation_edit` (exclusive p50, ms):

| phase | ordinary S1 | ordinary now | managed S1 | managed now |
| --- | ---: | ---: | ---: | ---: |
| `dependency_key_preparation` | **518.6** | **65.5** | **495.8** | **76.2** |
| `retention_store_io` | 75.9 | 80.6 | 98.7 | 115.2 |
| `source_load_parse` | 94.7 | 94.1 | 92.6 | 102.5 |
| `fresh_body_check` | 113.6 | 113.6 | 170.4 | 199.1 |
| `syntax_replay` | 52.7 | 54.8 | 51.3 | 59.8 |
| total inclusive | 994.3 | **543.7** | 1083.8 | **750.6** |

Preparation falls by 453 ms ordinary / 420 ms managed. The residual 65–76 ms is
the rest of preparation (reference collection, declaration fingerprinting and
context hashing), not export scanning. Cold and fresh-process paths improve by
the same mechanism because the index is rebuilt from the current snapshot on
every check.

## 4. Package 2 — one checked compilation per provider graph

The native-test flow now starts one internal `native-test-compile` session per
selected provider graph. The session checks the project exactly as
`native-test-graph` did, writes the `native-test-graph-v3` facts the planner
consumes, and **retains** the checked compilation. When the planner has a
selection, the same child lowers/emits that closure and writes the checked
frontend manifest; the linking driver consumes it through an internal
`--manifest-file` input and spawns no frontend. The result is one full body
check per graph and no second `emit-project-qbe` pass.

`native-probe.json` child work counters (representative successful sample;
`checked` is `performed/reused`):

| workload/state | S1 fresh checks | now fresh checks | now child that checked | now lowered |
| --- | ---: | ---: | --- | ---: |
| ordinary-100k first build | 33,475 + 24,654 | **33,475** | one `native-test-compile` | 524 |
| ordinary-100k used-helper edit | 24,655 + 24,654 | **24,655** | one `native-test-compile` | 524 |
| ordinary-100k forced run | 24,655 + 24,654 | **24,654** | one `native-test-compile` | 524 |
| managed-100k used-helper edit | 24,200 + 24,136 | **24,200** | one `native-test-compile` | 322 |
| managed-100k provider edit | 24,139 + 24,134 | **24,139** | one `native-test-compile` | 317 |

Every successful sample has `child_commands = list-interfaces,
native-test-compile, test` and no `emit-project-qbe`; the folded `test` record
equals the single child, so it is an aggregate, not a third check.
`verify_one_check.py` asserts this over the whole probe and passes on all 106
successful samples. A whole-project request with no selection still uses its
own frontend check and is named as a `native-test-whole-project-build` bypass
instead of being hidden.

Warm unchanged runs load the durable graph (`list-interfaces`, `check-project`,
`test`) and lower/emit/link/execute nothing. Invalid projects still reject
before any green receipt, and `--no-cache` writes zero durable graph, receipt
or object files (verified in all four probe workloads).

## 5. End-to-end matrix — S1 vs now (p50/p95 ms)

### ordinary-100k

| state | S1 p50 | S1 p95 | now p50 | now p95 |
| --- | ---: | ---: | ---: | ---: |
| cold | 1,246.7 | 1,262.2 | **773.4** | **797.5** |
| unchanged | 101.3 | 103.3 | 98.7 | 102.0 |
| no_cache | 1,031.2 | 1,047.8 | **559.3** | **564.5** |
| implementation_edit | 998.0 | 1,016.5 | **548.7** | **556.1** |
| constant_edit | 1,004.0 | 1,014.2 | **550.4** | **554.6** |
| signature_edit | 1,001.5 | 1,020.5 | **554.2** | **560.7** |
| session_implementation_edit | 1,017.0 | 1,041.2 | **556.9** | **563.5** |
| forced_tests (5) | 2,822.2 | 2,846.0 | **1,320.7** | **1,327.2** |

### managed-100k

| state | S1 p50 | S1 p95 | now p50 | now p95 |
| --- | ---: | ---: | ---: | ---: |
| cold | 1,314.4 | 1,331.0 | **840.5** | **861.3** |
| unchanged | 103.1 | 108.5 | 94.6 | 96.5 |
| no_cache | 1,074.7 | 1,142.0 | **624.7** | **646.6** |
| implementation_edit | 1,088.5 | 1,102.3 | **756.6** | **780.4** |
| constant_edit | 1,089.0 | 1,093.8 | **758.6** | **775.5** |
| union_edit | 1,072.9 | 1,104.0 | **789.8** | **795.1** |
| provider_edit | 1,086.8 | 1,094.2 | **742.1** | **774.7** |
| effect_edit | 1,087.2 | 1,091.3 | **700.1** | **729.4** |
| session_implementation_edit | 1,075.4 | 1,079.9 | **670.9** | **694.7** |
| forced_tests (5) | 3,035.3 | 3,173.7 | **1,535.2** | **1,544.9** |

### 10k

| workload/state | S1 p50 | S1 p95 | now p50 | now p95 |
| --- | ---: | ---: | ---: | ---: |
| ordinary cold | 117.3 | 125.1 | 114.7 | 127.3 |
| ordinary implementation_edit | 76.1 | 88.3 | 68.4 | 83.1 |
| ordinary forced_tests (5) | 330.1 | 356.3 | **271.7** | **283.4** |
| managed cold | 135.0 | 147.4 | 122.8 | 128.3 |
| managed implementation_edit | 99.5 | 107.1 | 90.2 | 113.4 |
| managed forced_tests (5) | 439.2 | 446.9 | **339.8** | **342.4** |

### Direct native states

| workload/state | S1 p50/p95 | now p50/p95 |
| --- | ---: | ---: |
| ordinary-10k first build | 1,701/1,734 | 1,633/1,650 |
| ordinary-10k used-helper edit | 350/357 | 283/320 |
| ordinary-100k first build | 15,907/15,907 | 14,969/15,673 |
| ordinary-100k used-helper edit | 2,786/2,848 | **1,408/1,454** |
| ordinary-100k unused-helper edit | 1,533/1,576 | **1,123/1,131** |
| managed-100k first build | 11,503/11,757 | 10,315/10,354 |
| managed-100k used-helper edit | 4,925/5,555 | **3,328/3,467** |
| managed-100k provider edit | 3,451/4,070 | **1,617/1,822** |
| managed-100k unused-helper edit | 2,037/2,254 | **1,164/1,185** |

## 6. Objective assessment

| objective | measured | met? |
| --- | --- | --- |
| ordinary-100k cold check p95 < 500 ms | 797.5 ms | no (1.6×) |
| ordinary-100k private edit p95 < 500 ms | **556.1 ms** | no (1.11×) |
| ordinary-100k constant edit p95 < 500 ms | **554.6 ms** | no (1.11×) |
| ordinary-100k signature edit p95 < 500 ms | **560.7 ms** | no (1.12×) |
| managed-100k cold / edit p95 < 500 ms | 861.3 / 780.4 ms | no |
| 100k forced execution p95 < 1 s | **1,327 ms** ordinary / **1,545 ms** managed | no (1.3–1.5×) |
| 100k used-helper edit p95 < 1 s | **1,452 ms** ordinary / **3,587 ms** managed | no (1.5–3.6×) |
| 10k forced tests p95 < 1 s (context) | 283 ms ordinary / 342 ms managed | yes |

The forced-execution row is not the affected-test acceptance criterion; the
used-helper edit row is the real edit-to-result path. The follow-up
publication report profiles the managed edit and attributes its ~1.9 s gap over
a forced run to QBE object compilation of 64 re-emitted fragments, not to
provider materialization or additional checking.

The two packages are the dominant part of the remaining gap. Ordinary-100k
edits moved from 2.0× to 1.11× the check target and 100k affected tests from
2.8–3.2× to 1.3–1.5×. Cold checks and the managed used-helper edit remain the
largest residual costs (fresh body checks, source load/parse and provider
materialization), so the next cost choice should come from the new profile
rather than from further work on these two mechanisms.

## 7. Correctness and gate status

- Package 1 oracle: indexed vs pre-change export digest byte-for-byte over the
  edge-case matrix; scaling test asserts one scan per module byte.
- Package 2 acceptance: `verify_one_check.py` passes 106/106 samples; the C4
  integration tests assert one `native-test-compile` child per graph, no
  `emit-project-qbe` re-check, zero lower/emit/link work on a fully cached
  rerun, rejection before green receipts, distinct-provider isolation and the
  `--no-cache` contract.
- Per-child work reports expose the single check and any whole-project
  fallback; nothing re-checks silently.
- Full gate on the final source: `zig build fmt-check` clean;
  `zig build test --summary all` 41/41 steps and **1,216/1,216 tests**;
  `zig build test-qbe --summary all` 36/36 steps and **133/133 tests**
  (this step includes `test-native-tests`); `zig build test-qbe-build
  --summary all` 22/22 steps.

## 8. Follow-ups

1. Re-run the final-S1 matrix and direct native states on one pinned
   ReleaseFast compiler and freeze the artifacts, as the plan requires.
2. Profile the residual ordinary-100k edit: source load/parse (~94 ms),
   retention store I/O (~81 ms), syntax replay (~55 ms), `fresh_body_check`
   (~114 ms) and the remaining dependency preparation (~66 ms).
3. Session-level preparation retention is still available if the residual
   ~66 ms of preparation and the double `source_load_parse` justify it; it was
   not needed for this package.
4. The productivity trial remains a separate task requiring a reviewed, frozen
   baseline.
