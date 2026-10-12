# S03 full-root cold preparation tradeoff

Two complete paired, order-balanced, S10-approved comparisons of frozen C0
`fbfcaa7a923186a8e773c3760f81c10aa345a432` and B0
`c1857310e0bf623545380c8de24515f1b9970021`. No production source changed.
The same unit inventory is prepared: C0 broad root (1541 tests) versus B0 broad
root (1532) plus independent scalar root (9). This is compile/link-only;
no broad test suite, full gate, guest compiler build or native guest ran.
The prior exact moved-name/wrapper audit and the admitted same-eight-name
15/9 selected-test executions establish the preserved boundary inventory.

Each variant started with its own absent Zig local/global cache directories.
Installed/frozen compiler and Zig/tool sources remained available; OS page
cache was not flushed. Thus cold means the named Zig cache tiers, not cold
compiler bootstrap, seed provisioning or filesystem page cache. Source/tool/
recipe authority was checked before and after; paired records have matching
harness `143941721c2c9556870d6aa5cd940defa618c0e0f55b2da164db2bfc8ab4b8c9`,
recipe/tool hashes and CPU affinity. Default Debug, native target, `-j4`, current
shared admission configuration; no CPU pinning/slot override.

After sourcing the shared dev environment, each separate window ran:

```
scripts/build-slot.sh timing timeout --signal=TERM --kill-after=10s 300s python3 experiments/development-loop-wave2-20261012/S03/measure_boundaries.py all-units --pair PAIR --label LABEL --timeout 240
```

PAIR/LABEL order was 0/C0, 0/B0, 1/B0, 1/C0. All four exited 0 and emitted
exactly one C0 binary or two B0 binaries. The 240-second command limit is an
explicit experiment exception replacing the underestimated 120-second bound;
production budgets were not changed. Queue was respectively 5, 0, 40 and
5 seconds and is separate from command time.

| Pair | C0 command | B0 command | C0 max process RSS | B0 max process RSS |
| --- | ---: | ---: | ---: | ---: |
| 0 | 65.794 s | 64.793 s | 1,078,656 KiB | 1,122,468 KiB |
| 1 (reverse order) | 64.838 s | 64.451 s | 1,040,404 KiB | 1,074,528 KiB |

Paired wall ratios B0/C0 are 0.98479 and 0.99403: near-equal observations in
this small cohort, not a stable speedup or p95. Maximum process RSS rises
4.06% and 3.28%; this is a visible regression, not aggregate concurrent RSS.
Build-runner cold configuration dominates that peak and the roughly minute
of command time. Actual broad compile step peaks are recorded in raw summaries;
the additional scalar compile took 381–392 ms with 156–163 MiB step peaks.
Those concurrently scheduled peaks cannot be added as measured aggregate memory.

Installed artifacts grow from 222,170,722 / 222,158,434 bytes to
247,904,346 / 247,900,250 bytes: approximately +25.74 MB / +11.58% of this
unit-artifact cohort. Private Zig local caches grow from 288,678,369 /
288,666,081 bytes to 314,477,459 / 314,473,363 bytes. Each private global
cache contains 59,964,022 bytes. Artifacts and caches are separate footprints;
debug/source paths can affect exact artifact bytes. The broader prepared gate
inventory is not measured by this minimal recipe.

The split therefore carries measured disk and process-memory costs. Combined
with `warm-report.md` (higher median command time, lower empirical tail and RSS),
these observations support an explicit tradeoff rather than an unconditional
no-regression or speed claim. They do not justify additional splits or removal
of tests. Independent producer/invalidation correctness is established by prior
closure qualification; broader live cache/edit acceptance belongs S06/coordinator.

Raw commands, CPU/usage, immutable identities, artifact SHA-256 and cache bytes:
`all-units-pair-{00,01}-{C0,B0}.json`, `C-window-*`, `raw/all-units-*`.
`measurement-summary.json` is reproduced by `summarize_measurements.py` and
pairs only fully completed, identity-compatible variants. The earlier incomplete
focused true-cold attempt remains unqualified and is never combined into a pair.
Golden runtime comparison remains separate and awaits matching repaired-compiler
operational qualification; its prepared artifacts and original blocker remain
recorded in the preceding commit.
