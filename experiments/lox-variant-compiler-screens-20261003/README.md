# Qualified variant compiler trials

Both compiler trials remain unselected. The ownership trial improves QBE's
tree interpreter but regresses LLVM; the fresh bool-store trial has only a
narrow QBE equality timing result. Neither is merged into the selected core or
main. The selected core remains `3b33df52` and the complete selected 37-file
Lox source remains unchanged.

## Ownership trial

Candidate `9ab993c1` inlines take/drop/unloan for bounded, declared plain cases
of counted native variants. Its original generated helper remains the fallback
for counted or unknown cases and unsupported overlap/region conditions. The
existing completed private-buffer certificate supplies disjointness without
changing its admission. Independent proof and root full-stream/build reviews
are separate from performance acceptance.

| Reduction versus selected control | LLVM VM | LLVM tree | QBE VM | QBE tree |
| --- | ---: | ---: | ---: | ---: |
| Wall runtime | 0.1451% | -1.6608% | -0.1409% | 8.1563% |
| Instructions | approximately 0% | 0.9942% | approximately 0% | 2.6607% |
| Cycles | -0.9597% | -1.4684% | -0.4252% | 8.5894% |

Positive reduction means less work or lower runtime; negative means an
increase. Each full matrix contains 468 cells: two interpreters, 13 workloads,
six arms and three rounds. Ratios are paired within rounds, median per
workload, then geometric mean across 13 workloads per interpreter. Counters
use the calibrated tree-sized inputs for both interpreters; timing uses each
interpreter's timed sizes. The median paired wall spread is 2.859%/3.707% for
LLVM VM/tree and 6.057%/2.476% for QBE VM/tree. These are spread measures, not
confidence intervals. The VM aggregate changes are small relative to spread.
LLVM tree string equality regresses 8.88%, while QBE tree equality and string
equality improve 26.29% and 23.26%; the mixed result prevents selection.

The separate first screen contains 104 counter cells. All 156 smoke/stat
checks and both full matrices passed output/status/diagnostic checks. All four
PMU events ran at 100% in every counter cell, with 223 unchanged guards.

Qualification separately checked 336 fresh public tests, 1,264 actual native
program pairs and eight checked RC-native-stress refusal pairs. Eighty costly
native-GC-stress smoke cells remain explicitly omitted; provider-backed clock
execution is not claimed. All 2,487 compiler unit tests passed fresh bounded
shards without the unfiltered run's retained memory warning. The QBE gate
passed 515 named checks plus the native COW runner; its golden replay checked
231 cases, skipped 373 for corpus reasons and had no mismatches.

## Fresh bool-store trial

Candidate `9481fbaa` widens tag and bool writes only inside proven fresh,
fully zeroed native variant storage. Its 156 smoke/stat checks and 104 counter
cells passed, with 223 stable guards. Aggregate instruction counts are
effectively unchanged and its one-round aggregate cycle results are roughly
flat. A follow-up measures only VM equality and string equality, with four
arms and three rounds (24 cells); it is a partial diagnostic, not a full
performance matrix or selection result.

| Focused wall reduction | LLVM | QBE |
| --- | ---: | ---: |
| VM equality | -0.3873% | 4.7330% |
| VM string equality | -5.1267% | -1.5432% |

The respective paired spreads are 0.467%/2.298% for equality and
6.548%/6.976% for string equality. The latter has substantial variation. This
trial remains isolated pending a broader useful result. Qualification checked
336 fresh public Lox tests plus 28 constructor tests, 1,264 native pairs and
eight refusal pairs; the same 80 stress-smoke omissions and provider limit
remain explicit. The 2,490-test unfiltered unit run passed but retained a
memory-budget warning; clean bounded coverage is narrower and no completed
full bounded/compiler gate is claimed for this trial.

## Evidence and limits

`native-behavior-review.json`, `native-build-review.json` and
`wide-behavior-review.json` bind the author qualification streams, exact
sources, separate RC/GC guests, optimization flags and runtime archives.
Native runtime stress uses `MYLANG_OPTIONS=--gc-stress`; the Lox collector's
independent stress switch is the guest argument `--gc-stress`.

The compiler-only preparer measures exact original qualified RC ELF bytes and
sidecars. Fresh rebuilds match every allocated ELF section, entry and program
layout. Differences are confined to permitted nonallocated debug and symbol
metadata; this is reproduction evidence, not a general ELF equivalence proof.
The earlier byte-exact rebuild refusal and superseded preparation/smoke work
are retained separately and excluded from current performance coverage.

Archive receipts and closeout reports retain every measurement row and input
identity; the independent closeout helper rechecks outputs, complete matrices,
command provenance, source expansion, actual ELF reproduction and paired
analysis arithmetic. Portable archive verification checks objects without
requiring the original absolute paths. Checking original paths is explicit.
Guardian gates passed 88 checks without waivers or baseline changes. Root
consolidates feedback in the Guardian repository.

`native-archive.json` binds 633 original paths to 239 immutable objects under
`/home/epentland/ai/canopy/evidence/mylang-lox-compiler-screens-20261003/native-variant`;
its manifest SHA-256 is
`34986591f66b04a8009065a27bed537f72dcae02ea6b4fc0118131aabd9d0630`.
`wide-archive.json` binds 347 paths to 263 objects under the adjacent
`variant-wide` archive, with manifest
`70116edc606ff73d1c7c697e4d16b08b45c9e1dacb9db840832875b6c7a11926`.
All archived bytes and original identities were rechecked after copying.
The native archive also retains the first failed byte-exact rebuild and the
superseded 213-guard smoke work; those extras do not contribute current rows.
The separate closeout reports count 1,296 native and 284 bool-trial rows.
