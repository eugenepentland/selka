# C2 copy worklist scratch initialization

Production/regression commit: `2d69c183674fd2338498e815ec60b8a88b67f099` (normal Guardian88 passed; no feedback/push). Isolated checkout `/home/epentland/ai/canopy/mylang-lox-runtime-stack-20261013-p7`, baseline `fbeba4eed7b549a3feef14c8b8dd620e41494139`. Only production change: initialize stack.items/count/capacity instead of clearing all64 work items. Baseline core_owned_copy.c SHA256 `e0df96ef27050a5f74ba36ac9f761633b7fd0eaa3dcb81ee392f37cb21648b21`; runtime-variants.json pins all14 concatenated runtime sources. Scalar-only C2 baseline, no pointer/bulk overlays.

Push assigns all three pointers before publishing count; pop reads only the initialized live prefix; growth copies exactly count slots. Empty/static/scalar roots never read an unassigned item. Tag/resource/descriptor validation and allocation policies remain unchanged. Registered Core regression passed both ownership ABIs (registered.log, exact process0), including64→65 growth, recursive20k cleanup, active unions/independence, arrays/scalar/empty/static roots and fatal invalid descriptors. Standalone checks-002 passed63commands. GCC15 ASan+UBSan and pattern stack initialization pass; deliberate bad accesses verify instrumentation. These tools do not constitute MemorySanitizer/uninitialized-read detection; initialization safety additionally follows the prefix audit. First checks-001 control failure preserved: UBSan fired before expected ASan marker; corrected control explicitly allows UBSan to continue to ASan, while positive tests halt on either error.

Native proof uses identical pinned Zig/native flags: old helper clears1552bytes via memset; candidate LLVM/helper assembly no longer contains this clear. Baseline runtime object9b0081bfa90c91953a70bd19cd8424ecf311fb1b94980f2ca6d8641c238a58fa; candidate5c575bc09fdb112e236153205f4fe731786baa188374c70c9ce9b8876d6c5a9c. checks-002 contains exact commands/processcodes, source/tool/sanitizer hashes, extracted LLVM/assembly and raw counters.

Controlled guests retain C2 frozen application LLVM, common numeric provider, target/cpu/link flags. Within each old/new pair only the runtime object changes. Installed C2 compiler SHA2569bedb835438615d79ed8f2985352877a8c844eebeb74cd95a1d276332b6b0c6a; full6-file installation manifest pinned. guest-builds-001 and counted-guests-001 record exact build argv and before/end input pins. Counted LLVM was freshly generated with this compiler from exact immutable source-002 paths; canonical count_runtime.source instrumentation is unchanged. No frontend/application performance claim follows from relinking.

Qualification retains stdout/stderr/goldens and all raw counters. Realloc movement is allocator-placement dependent; all other semantic/allocation/growth/copy/peak/exit-live fields must match. Only list_push.extra can differ, and a changed projection must equal its per-function movement delta; global projected delta is zero or the global movement delta. Zero projection is allowed because core_count.c162 requires a non-null push_site. This is not full-counter equality. Earlier harness attempts are preserved:001 observed movement mismatch,002 reused private cwd,003 observed list_push projection,004 overly strict projection demanded every movement have a site. Final005 uses separate attempt directories and the precise reconciliation policy. Additional unchanged-control/candidate repeats preserve all raw placement ranges.

Reproduction (source dev-env first; each native action one outer lease; no nesting):
```
source /home/epentland/.config/mylang/dev-env.sh
scripts/build-slot.sh build -- python3 experiments/lox-eda-parity-20261013/P7-stack/check.py
scripts/build-slot.sh build -- bash .tmp/lox-eda-parity/P7-stack/verify-registered.sh
scripts/build-slot.sh build -- python3 experiments/lox-eda-parity-20261013/P7-stack/build-guests.py
scripts/build-slot.sh build -- python3 experiments/lox-eda-parity-20261013/P7-stack/build-counted-guests.py
scripts/build-slot.sh build -- python3 experiments/lox-eda-parity-20261013/P7-stack/qualify-guests.py
scripts/build-slot.sh build -- python3 experiments/lox-eda-parity-20261013/P7-stack/repeat-counters.py
python3 experiments/lox-eda-parity-20261013/P7-stack/prepare-timing.py
python3 experiments/lox-eda-parity-20261013/P7-stack/run-timing.py
python3 experiments/lox-eda-parity-20261013/P7-stack/report-timing.py
```
Attempt directories deliberately refuse overwrites; choose a new name before reproducing. Timing runner obtains one shared timing lease per chunk; fresh5sample Zig calibration,3× cutoff capped120s, CPU8,2warmups9alternating rounds and3separate RSS samples. Selected5cases: EDA rds3+flat/rds3-rf-selector, tree binary_trees/fib and VMfib. Raw censors/statuses retained; no ratios inferred from censors. Recommendation: adopt production/regression2d69c1836 into the combined final candidate; final compiler installation/fullqualification remains coordinator-owned. This is a bounded redundant-store removal with focused correctness proof and no material timing regression, not strong broad performance evidence.

## Completed timing

50/50 shared timing chunks completed process0. Every case has9valid wall samples and3RSS samples perarm, no censors. CPU8, fresh5sample Zig calibration,2warmups,9alternating paired rounds; raw receipts/statuses and exact admitted commands retained.

| Case | Baseline / candidate wall ms | Paired candidate/base | Wins | Baseline / candidate RSS KiB | Candidate/Zig |
|---|---:|---:|---:|---:|---:|
| eda-rds3+flat | 97.453 / 95.902 | 0.983105 | 7/9 | 60368 / 60436 | 1.615918 |
| eda-rds3-rf-selector | 13.420 / 13.389 | 0.990362 | 5/9 | 9872 / 9940 | 1.156802 |
| tree-binary_trees | 154.054 / 154.186 | 1.002753 | 3/9 | 6920 / 7048 | 1.285209 |
| tree-fib | 104.873 / 102.597 | 0.990727 | 6/9 | 5400 / 5528 | 1.086310 |
| vm-fib | 1232.009 / 1232.244 | 1.001573 | 4/9 | 2528 / 2656 | 2.060602 |

Candidate RSS is68KiB higher in EDA and128KiB higher in Lox; no RSS improvement claimed. Semantic allocation/traffic/peak-live counters match and all exits have live0; actual realloc-movement observations remain visible in counter-summary.json and full raw files. Additional installed-control/candidate repeats both vary416–417moves and3,167,106–4,215,646movedbytes, demonstrating allocator placement variation independently of the patch. No case here reaches Zigparity. No further prototypes/measurements queued.

Raw directories are preserved in raw-evidence.tar.gz with archive-index.json and evidence-manifest.json exact paths/hashes; extract before reading raw receipts or reproduction. This consolidation follows a preserved normal Guardian GitSpawnFailed with700artifactpaths; no hook bypass. First hook log is commit-evidence-first.log.gz.
