# Round3 independent evidence review

The later [final closeout](final-closeout.md) records both complete780-row
matrices and preserves the historical partial observations below.

`initial-review.json` is a preserved **partial phase observation**, not a
completed review of the full timing/counter matrices. Its 416 completed rows
are the 208-row smoke and 208-row instruction screen. At that observation,
full timing had 62 rows of a 780-row target and is excluded from pass coverage.
The receipt SHA256 is
`2e860149cb23ac7245bc9f47a3f38b3b6b8626efa6b8e751d20a2437b9f1f9f3`.
Later observations must use distinct paths and preserve this receipt.

`partial-review.json` extends that observation with the completed fresh
reproduction and remains explicitly partial for full measurements. Its
completed coverage is **676 rows**: smoke208 + instruction208 + fresh
behavior260. At its freeze, original full timing was 320/780 and excluded;
the full counter matrix had not started. There is no timing result, speed
acceptance or full-matrix pass claim. SHA256:
`1828e9df32b09c6c5c1b5c50b8c152565228af1faa61c6ce265c848213811481`.

The manifest SHA256 is
`d1b04d2b3084aad01b32898fced996a072f9181f746afef839ac7012ef596d3b`.
All four source maps contain the exact 37 files/26 modules. Baseline matches
accepted source84 and canonical replay; AST matches its author source, and
constant matches its author qualified85 source. In-memory patch replay
combines exactly four changed files: interpreter.my, vm.my, driver_tests.my
and driver_cases.json. The last two are the constant-read provider fixture;
its production84 and qualified85 runtime guest bytes match.

All eight mylang guests and two frozen Rust/Go guests match the manifest.
Baseline84 ELF bytes and both sidecars are inherited exactly from accepted
checkpoint `44cd4307`. AST individual RC guests match author `180575c3` /
`246f2178`; constant guests match `37b2707e` / `b7499343`. Six fresh build
entries plus the original baseline build provenance, compiler d14, QBE99ad,
eight native metadata files and actual runtime objects are verified. LLVM
uses O3/full LTO and QBE its recorded default RC mode; no checks are dropped
by these guest build commands. The author's separate diagnostic SSA command
is not used as a native production build receipt.

This workspace contains **53 benchmark files**. They match the benchmark
subset of the accepted checkpoint's 127-file reference tree; that entire
older reference tree is independently rehashed. Rust/Go ELFs are copied
byte-for-byte, with their source/tool provenance inherited from the accepted
checkpoint, not newly built or replaced in round3. Preparation records three
input source maps and helper hashes; the combined output has its separate
composition receipt. No standalone source-copy launcher is claimed for this
initial preparation receipt. The later reproduction helper is qualified
separately below.

The smoke phase covers all 13 scripts on both engines and eight mylang arms,
with one smoke-size round: 26 × 8 × 1 = 208 unique rows. Complete decoded
ASCII statistics, status and output hashes match exactly. The instruction
screen has the same coverage at the original tree-size setting on both
engines. All four PMU running rates equal 100 in every counter row, for 832
rate checks. Quiet waits, deterministic shuffled ordering, summaries and
paired arithmetic pass. The new strict factorial analyzer's six screen
comparisons reproduce independently. Full phases require 26 × 10 × 3 = 780
unique rows with Rust and Go, and 18 analysis comparisons; they will receive
a separate completed receipt when available.

The screen reproduces instruction reductions of 1.787148% LLVM / 2.078419%
QBE on tree for AST, and 1.054670% / 0.047293% on VM for constant. The
unaffected engines are essentially flat. The combined arm preserves both
effects. These are diagnostic instruction results, not timing conclusions.

The added standalone `prepare.py` SHA256 is
`7f4626e86764b0670419cfc36292354a7e33b0f3e3df0a7585dfad2e25253548`.
Its accepted baseline tar SHA256 is
`ecb25e84109b7f8ee451b44eb25275a9b7f82a37dd8f0a46fa7438d3c1391486`.
Independent in-memory archive inspection matches all 37 accepted source84
files. The helper uses a new private workspace, applies the two fixed patches
with zero fuzz, composes them, and checks all four exact source maps before
building. It rejects source drift and existing output workspaces. Compiler,
QBE, helper and source identities are checked before/after; argv commands
and private build caches/TMPDIR are recorded. Absolute RUSTC and effective
reference build environment are captured, with cargo/rustc shim and actual
sysroot executable identities separately recorded.

Fresh manifest `00ec5396` has all ten preparation commands successful, eight
native mylang builds with matching compiler/runtime receipts, and 106 pinned
benchmark/Rust/Go reference files. All eight mylang ELFs and Rust match the
original measured bytes. Fresh Go has its own identity and is used only in
the CPU0 behavior smoke: all ten arms × 26 cases × one smoke round = 260
unique rows, with exact status/output hashes/complete statistics. No fresh
binary replaces a measured binary or creates a new timing result.

The host-only `go version -m` inspection in `go-metadata.json` reports the
same build metadata and no VCS entries in either original or fresh Go ELF.
The helper passes `-buildvcs=false`. Embedded absolute source paths differ
between the binaries; this observation does not establish the sole cause of
all byte differences. Tool versions and hashes are post-build observations,
and neither full toolchain/standard-library archives nor exhaustive ambient
flags are claimed. This qualifies observed sources, commands, guest
identities and behavior; it does not establish a hermetic-build guarantee.

For metric m, each case/arm/round produces a paired ratio
`candidate_m / control_m`. The reported case ratio is the median of those
paired ratios; its spread is `(max - min) / median`. Engine results take the
geometric mean of the 13 case ratios, with reduction `100 × (1 - ratio)`.
The reviewer implements this independently instead of invoking the producer's
paired analyzer. One-round instruction screening is a diagnostic, not wall
acceptance or a parity result.

The producer compares full raw stdout with pinned expected bytes before
saving its hash. Raw stdout and per-sample perf CSV are not retained in these
measurement receipts. Every completed decoded stderr is ASCII shorter than
the 1,500-character tail limit, so it is complete; smoke contains exact stats
and instruction rows have empty diagnostics. Separate author native
qualification retains full streams. The read-only review executes no tests,
guests or performance commands and changes no source, root or evidence
archive files.

Use a fresh output to inspect completed later phases:

```bash
taskset -c 16 python3 -B experiments/lox-round3-independent-review-20261003/review.py \
  --root /home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003 \
  --out .tmp-lox-round3-review-20261003/new-review.json
```

The prior callee-table archive and its manifest94d85 remain untouched. This
phase has no canonical adoption or Rust/Go parity completion claim.
