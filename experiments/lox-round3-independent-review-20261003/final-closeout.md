# Round3 independent measurement closeout

The complete round3 evidence passes the independent identity, coverage,
output, PMU and paired-arithmetic checks. This closes the measurement review;
it does not select a new canonical source or establish Rust/Go parity.
No guests, tests or performance commands were executed by this review.

`final-review.json` SHA256 is
`bd8e734c304940db87fb769eedcc409affd806c194a190e1e77086cb62ed0722`.
All 887 recorded inputs were rehashed after inspection. The immutable
manifest remains `d1b04d2b3084aad01b32898fced996a072f9181f746afef839ac7012ef596d3b`.
All four source maps still contain the exact 37 files, including 26 modules;
composition changes only interpreter.my, vm.my and the two driver fixture
files. Accepted baseline84, author AST/constant sources, production guest
identities, original baseline sidecars, compiler d14, QBE99ad, actual runtime
objects, reference sources and helper/build receipts all match the earlier
independent review. The prior sealed checkpoint archive remains untouched.

Completed original coverage is **1,976 unique rows**: smoke208 + screen208 +
wall780 + counters780. Both full phases contain exactly 26 cases × 10 arms ×
3 rounds. Fresh reproduction adds **260 behavior-only rows**, for 2,236
completed observations including reproduction. The preserved initial62 and
partial320 wall observations are prefixes of the final780, not additional
measurements. Both historical receipt hashes remain unchanged; their earlier
416/676 coverage is not added again.

The full wall receipt SHA256 is
`76aa55350abcc26fd7dc1f285641d1a352a0de30135b543990522b154a9c1964`.
The full counter receipt SHA256 is
`43a8d4f8d0626195d101aa837815536b71fb909b0cf29770bc44625db0694509`.
Command exits, final source checks, expected output hashes, empty diagnostics,
unique coverage, deterministic shuffled order, quiet waits and all summaries
pass. All four PMU events have integer nonnegative counts and 100% running
rates in all780 counter rows: **3,120 checks**, or **3,952** including the
screen. Counter summaries independently reproduce instructions, cycles,
branches, branch misses and IPC.

Wall uses the engine-specific `timed` sizes on CPU2. Full counters use the
original `tree` sizes on both engines on CPU10, as did the screen. These are
distinct workload-size protocols; their results are not silently pooled.
The screen has six comparisons and each full analysis has 18, including the
original frozen Rust/Go controls. All42 comparisons, their 13 cases per
engine, every paired ratio, median, spread and geometric mean reproduce from
the retained samples independently of the producer's paired analyzer.

Positive values below mean a reduction relative to baseline84; negative
values mean slower walls or more instructions. These are descriptive paired
estimates, not significance claims.

| Arm | Backend | VM wall % | Tree wall % | VM instructions % | Tree instructions % |
| --- | --- | ---: | ---: | ---: | ---: |
| AST | LLVM | 0.221583 | 3.054058 | essentially 0 | 1.787149 |
| AST | QBE | 1.397084 | 2.480703 | essentially 0 | 2.078419 |
| Constant | LLVM | 1.680175 | 0.587556 | 1.054670 | essentially 0 |
| Constant | QBE | -1.203140 | -0.695516 | 0.047292 | essentially 0 |
| Combined | LLVM | 2.018140 | 2.224258 | 1.054671 | 1.787149 |
| Combined | QBE | 0.515634 | 2.668104 | 0.047341 | 2.078419 |

AST tree walls improve in 11/13 LLVM cases and all13 QBE cases. The LLVM
exceptions are string_equality (-0.4895%) and strings (-0.8400%). The median
per-case paired-ratio spreads are 1.8163% and 3.1311%. LLVM per-round all13
geometric-mean reductions are 4.6243%, -0.4034% and 3.4098%; QBE gives 2.1077%,
3.4008% and 2.6732%. Leave-one-round-out case-median reductions remain
positive: LLVM 1.4098–3.9897%, QBE 2.3770–3.0246%. Leave-one-case-out ranges
are LLVM 2.6871–3.3717% and QBE 2.2643–2.6842%.

Combined tree improves in 12/13 cases on both backends; strings regresses
0.8686% LLVM and 1.3310% QBE. Its per-round tree aggregates and omission
checks remain positive. Combined VM improves in 10/13 LLVM and 7/13 QBE
cases, but median per-case paired spreads of **9.3463% / 5.1989%** exceed the
reported **2.0181% / 0.5156%** aggregate wall reductions. LLVM VM also has a
negative per-round aggregate. AST's instruction-flat VM shows 1.3971% QBE
wall movement, warning against attributing every wall delta to the intended
source mechanism. Constant QBE VM is slower in 12/13 cases and in every
per-round aggregate despite its small instruction reduction. The VM wall
benefit remains uncertain; the constant component does not establish a
consistent wall win across backends.

`wall-robustness.json` SHA256 is
`23b7b7ac4661cafc3c5439a1949aee48c56180d2b3d7f061776afb009a0b86ea`.
It retains each baseline comparison's per-round aggregate, case wins,
omission ranges, spreads and all slower-case exceptions. Omission checks are
descriptive sensitivity, not confidence intervals, p-values or independent
replication. A two-round median averages the two ratios, so its estimator
differs from the three-round median used for the reported result.

The combined wall-time ratios to the original frozen references remain far
above one. Against Rust/Go respectively, LLVM is **2.6849× / 2.6717× on VM**
and **4.1572× / 4.0516× on tree**; QBE is **5.2955× / 5.2983× on VM** and
**7.4201× / 7.2076× on tree**. These are geometric means of case-median
candidate/reference ratios, not speedups or newly reproduced-reference
timings. Rust/Go parity is not reached.

Fresh reproduction still matches all eight measured mylang ELFs and Rust
byte-for-byte. Fresh Go is a distinct identity, qualified only by the
260-row CPU0 smoke; it never replaces the measured Go arm. Both Go ELFs
report the same build metadata and no VCS entries. Embedded source paths
differ, without proving that this alone explains every byte difference.
The helper, effective build commands/environment, pinned sources, tool
shims and actual tool executables are checked. Post-build tool observations
and recorded environment do not constitute full hermetic toolchain archives.

The producer compared complete raw stdout before retaining only its hash.
Per-sample raw perf CSV is also not archived. Completed diagnostics are
ASCII shorter than the retained tail limit, so they are complete; exact
statistics are checked in the smoke phases. Separate source/native
qualification and complete-stream author receipts remain inherited evidence.
This audit makes no new semantic qualification or native-trace equivalence
claim. No source, root workspace or sealed archive was changed.

To reproduce this read-only review with a fresh output path:

```bash
taskset -c 16 python3 -B experiments/lox-round3-independent-review-20261003/review.py \
  --root /home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003 \
  --require-full --out .tmp-lox-round3-review-20261003/recheck-final.json
```

The host-only robustness script likewise reads frozen data and writes a new
receipt. Its wall/analysis hashes bind the sensitivity results to the
completed measured originals. Commit qualification is the automatic Guardian
gate; root consolidates Guardian feedback separately.
