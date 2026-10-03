# Selected QBE native-variant backend policy

The corrected policy is selected on `codex/lox-parity-20261003` as core
`d22f7fa7cfedc0523f1d106f27cb6d9eb48bc82b`, from independently qualified
author commit `a07fee5e878a4ad4c5610c07928b0fe9f45f0269`. All 878 compiler
source files match the frozen qualification after integration. The selected
37-file Lox source is unchanged. This selection does not merge main.

Known current QBE producers use the bounded native variant path. LLVM,
legacy LLVM invocation syntax, foreign overrides and default selective APIs retain
the original policy. Policy participates in producer/cache identities before
lookup. The corrected default producer boundaries preserve their prior COW,
counting, step, frame and drop settings. Checked tag, region, bounds and overlap
behavior stays required.

Three paired rounds across 13 workloads per engine give these geometric mean
changes relative to the preceding selected AST/d14 compiler. Negative changes
mean less time/work. Counters use the calibrated tree tier; wall uses timed
inputs. They cover the same case names with separately recorded input sizes.

| Backend / engine | Wall time change | Instructions change | Cycles change |
| --- | ---: | ---: | ---: |
| LLVM VM | +0.0284% | approximately 0% | -0.1623% |
| LLVM tree | +0.1051% | approximately 0% | +0.0106% |
| QBE VM | +0.4868% | approximately 0% | +0.3779% |
| QBE tree | -7.7089% | -2.6607% | -8.5299% |

All 13 QBE tree wall medians improve, from 1.5255% to 27.1339%; each round's
tree geometric mean improves 7.64–7.82%. The equal-weight geometric mean
across all 26 QBE VM/tree cases improves 3.6982%. This robust tree gain and
overall case mean justify selection with the VM tradeoff explicit. Nine VM
cases have slower paired medians; `fib` rises 2.2802%, string equality 1.3447%
and `trees` 1.5321%. Paired spreads are observations, not confidence intervals.
The result is not a claim that every workload improves or that Rust/Go parity
has been reached.

The current direct wall ratios remain substantial: QBE tree is 6.833× Rust and
6.649× Go; QBE VM is 5.252× Rust and 5.308× Go. LLVM VM/tree are 2.694×/4.093×
Rust and 2.723×/3.989× Go. LLVM allocated code matches the preceding selection;
its small timing variations are retained without attributing them to changed
LLVM lowering.

`selection.json` binds the source, actual qualified compiler `81fe4784…`,
adjacent QBE `99ad919d…`, prepared identities and the integrated core commit.
The immutable qualification and independent reviews retain 336 fresh public
passes, 1,168 native plus 96 AST exact comparisons, eight checked refusals and
80 explicit unrun stress cells. Public QBE tests use Debug mode and LLVM tests
use release mode. The final QBE gate passes 515 tests, including a root with
231 golden checks,
with 373 explicit corpus skips. Focused 19/20 unit runs share twelve common
imports; five CLI checks are separate. Historical V1 broad unit results are
not credited to the corrected V2. Guardian passes 88 checks without waivers
or baseline edits. Native-run receipts bind the used artifacts and assert
prefix equality in memory; saved full prefix/imported-helper maps are a
separate retrospective postflight. The prospective full prefix snapshot below
applies to central preparation, without supplying an earlier native-run map.

Central preparation verifies 1,038 prospective inputs, including frozen
source and the complete owned compiler prefix, before/after fresh reproduction
builds. It compares every allocated ELF section and entry/header/layout, then
copies the actual qualified RC executables byte-for-byte for measurement.
The new prospective protocol reconstructs exactly 252 guards and six actual
baseline/candidate/rebuilt runtime roles. It covers installed and fresh-cache
archive paths and refuses missing or extra bindings. No legacy receipt or
guard was changed.

All 1,196 observations completed: 156 output/stat checks, 104 diagnostic
counter cells, 468 wall cells and 468 full counter cells. All 2,288 PMU-event
checks ran at 100%. Full output hashes, ordinary diagnostics, equal smoke
collector statistics, commands, source identities and paired arithmetic pass
strict closeout. Raw stdout was checked and is retained as a hash; measurement
stderr tails retain at most 1,500 characters. An early checker invocation
correctly refused the still-active wall command. That historical refusal and
the original 35-file protocol review's refusal after additive packaging remain
preserved and excluded from successful coverage.

The sealed archive is
`/home/epentland/ai/canopy/evidence/mylang-lox-compiler-screens-20261003/native-backend-policy`,
manifest `431b64aca839ef7514c0f388815cc8d0bf29b0b69dcc4f9b6710af155250b18b`.
It retains 375 original paths in 276 content-addressed objects. Both original
identity and portable object verification pass. `closeout.json`, `archive.json`
and the verification copies record those exact scopes. Independent source and
qualification reviews are in the adjacent `lox-native-policy-review-20261003`
and `lox-native-policy-final-review-20261003` directories. The separate
[measurement review](../lox-native-policy-measurement-review-20261003/README.md)
reconstructs completed coverage, source/tool/ELF bindings, paired arithmetic
and the sealed archive without running a compiler or guest.

Later host-only inspections are separate from the sealed measurement archive.
`vm-comparison.json` finds all 41 VM IL units/object bodies and 40 linked
functions unchanged except at existing relocation fields. Heap/value/table
bodies also match. The text section grows 19,984 bytes and shifts all linked
VM functions by that amount, changing alignment. Layout is a possible
contributor to the measured cost, not a proven cause. `runtime-lto-feasibility.json`
rules out simply enabling LLVM runtime LTO: both actual LLVM RC archives
already contain 36 bitcode C units and full-LTO links optimize them with guest
code. No new compiler, guest or performance run is attributed to these reads.
