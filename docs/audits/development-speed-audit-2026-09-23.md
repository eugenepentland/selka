# What slowed down development of mylang itself — 2026-09-23

The performance-parity work of 22–23 September ran 29 Opus agents on this one
machine and merged more than 25 branches through gated integration. This audit asks
where their time went, and what would let the next round of compiler and runtime
work iterate faster.

## Sources

- **Agent transcripts.** Every tool call and result in all 29 transcripts
  carries a timestamp. Pairing calls with results gives foreground time per
  command. Blocking waits (`until`/`while`/`sleep` loops over a log) are charged
  to what they polled. The gap before each assistant message is counted as model
  time.
- **The coordinator's gate logs** for 24 merge-and-gate runs.
- **Direct measurements** made for this audit: builds, guest tests, the commit
  hook, Debug-vs-release guest binaries.

Scripts and raw numbers are in
[`experiments/dev-speed-audit-20260923/`](../../experiments/dev-speed-audit-20260923/).

## Headline

**Totals.** 45 agent-hours of wall time; the median lane ran 1.4 hours.

| where the time went | hours | share |
|---|---:|---:|
| model thinking and generation | 15.7 | 35% |
| building ReleaseFast compilers, and waiting on them | 10.2 | 23% |
| benchmarks, running and waiting | 4.1 | 9% |
| guest test runs, mostly `--gc-stress`, running and waiting | 3.3 | 7% |
| full gates, running and waiting | 2.1 | 5% |
| reading, grepping, editing, git | 5.9 | 13% |
| guest builds, focused tests, C tests, idle and other | 3.8 | 8% |

**How the shares split by lane.** Model time was 15–25% in the lanes that
measured most (memory footprint, NaN, dictionary, string views). It was 70% or
more in the lanes that mostly reasoned (vectorizer blockers, the audit-phase
porting agents). The waiting column is where development speed was lost.

**The waiting was mostly avoidable.** Three causes:

- **Needless ReleaseFast builds.** Most of the ReleaseFast compiler builds were
  unnecessary (§1).
- **A shared, saturated machine.** It turned 4–5 minute gates and 26-second test
  suites into 10–20 minute waits (§2).
- **Integration friction.** Semantic conflicts between lanes, plus a red base and
  invisible test suites, cost hours of rework and serial gating (§3, §4).

Fixing the first two alone would cut roughly a third of every measuring lane's wall
time. That is an estimate from the shares above, not a measurement.

## 1. Building ReleaseFast compilers to measure — 10.2 h, 23%

**What happened.** Every lane brief told the agent to build a ReleaseFast compiler
before measuring.
- Agents ran 80 explicit ReleaseFast builds, with 201 release-build commands in
  all counting their wrapper scripts. One lane ran 16.
- Each took 2.4 minutes in the foreground on average, plus waits, with `-j2` and
  queued behind the other agents' builds.
- A default install optimizes the compiler four times over: `board-trial`,
  `schematic-svg` and `mylang-io` each link their own copy of it.

**It was not needed.** A Debug and a ReleaseFast compiler emit byte-identical
guest binaries (5 of 5 suite programs checked, `measurements.md`), and the Debug
compiler is only 0.1–1.5 s slower per guest build. An incremental Debug `zig build`
averaged 15 s across the night. So for timing guest programs, a Debug compiler
gives the same binaries at about a tenth of the build cost. That instruction was
the coordinator's, not the agents'.

**Already done:** `-Dcompiler-only=true` (on main): a clean ReleaseFast install is
166 s instead of 418 s, when an optimized compiler is really needed.

**To do:**
- **Say it in `CLAUDE.md`:** measure guest programs with the Debug `zig-out/bin/mylang`.
  ReleaseFast is only for timing the compiler itself, or for handing a compiler to
  other agents.
- **Make the harness defaults follow:** point `experiments/perf-parity-plan-20260922/bench.py`
  and `bench_parity.py` at `zig-out/bin/mylang`.

**Estimated saving:** 8–9 of the 10.2 hours.

## 2. One saturated machine — gates 3–5× slower, tests 5–8× slower, noisy numbers

**Constraints.** 30 GB of RAM, 20 threads, up to 9 agents plus other sessions at
once. The coordinator's slot wrapper allowed 3 concurrent builds and 1 gate.

- **Gates.** A clean-cache full gate is about 4–5 minutes of work
  (`zig build test` 202–237 s, `test-qbe` 47–56 s, the rest seconds, plus
  the build step). The same
  merge-and-gate run averaged 12 minutes over the night and reached 22.
- **Guest tests.** The whole `tests/lang` suite is 26 s cold (39 s with
  `--gc-stress`) and 1–4 s warm on a quiet machine. Agents waited 2.8 hours on it,
  about 3 minutes per wait: cold caches after every compiler change, run
  alongside everyone else's builds.
- **Out-of-memory kills.** 48 tool results mention the memory ceiling. Several
  ReleaseFast builds and one `root_test` compile were killed and rerun, and gates
  produced "new" failures that passed when rerun alone (9 in one gate).
- **Measurement noise.** Identical binaries swung up to 1.8× when the timing
  core's SMT sibling was busy. Every lane had to label its numbers "loaded
  machine" and take 9–11 rounds; the coordinator then re-measured everything on a
  quiet core (about 2 hours of the final stretch).
- **Outage.** The `/tmp` tmpfs has a per-user quota. When other sessions filled
  it, every shell command in every agent failed for about an hour (17 DiskQuota
  failures on record).

**To do:**
- **Cap parallelism to what the machine holds.** About 4 build-heavy agents here.
  More lanes than that queue anyway, and add kills and flakes. The slot wrapper
  (`.tmp/perf-plan-20260922/slot.sh`) worked; move it into `scripts/` and make it
  admit by free memory as well as by count.
- **Reserve timing cores.** Keep two P-core pairs (for example 2/3 and 10/11)
  free of builds, with `taskset` on the build wrapper or `isolcpus`/cgroups. Then
  timings no longer need a separate quiet re-measure.
- **Use instruction counts for A/B checks.** `perf_event_paranoid=1` is set now,
  and `bench-parity` records counts pinned to the timing core. Instruction counts
  do not move with load, so one run can decide most "did this get faster" questions
  that took 9–11 timed rounds tonight.
- **Move gates off the dev box.** A second machine or a CI runner for gates would
  keep integration off the critical path while agents build.

## 3. Integration friction — about 5 h of serial gating, and semantic conflicts

**Serial gating.** The coordinator merged lanes one or two at a time, each behind a
clean-cache gate: 24 runs, about 5 hours in total. While a gate ran, the next
finished lane waited.

**Textual conflicts.** Every lane appended SPEC bullets at the end of the same
sections, so nearly every merge conflicted in `SPEC.md`. It was resolved each time
by taking both sides, twice leaving a duplicated, amended bullet that Guardian
rejected. Two more needed real resolution: `emit`'s signature changed under the
niche branch (`src/native_descriptors.zig`), and two lanes rewrote the same
paragraph of `docs/tooling/native-build.md`.

**Four semantic conflicts, clean merges with a broken result:**
- `get_index` became an `Access`, so the merged tree did not compile.
- `Option[Node]` shrank from 16 to 8 bytes, so an inline-allocation test named the
  wrong size class.
- Unsigned trap operands started printing unsigned, so a boundary test pinned the
  old text.
- A NaN helper was deleted while another lane added attributes and a test for it.

**Silently wrong measurements.** Two trees sharing one Zig cache embedded a stale
runtime hash, so one lane's benchmark batch measured the old runtime (fixed on main,
`test-runtime-identity`).

**To do:**
- **Stop appending to one file.** Give SPEC bullets per-area files, or a small tool
  that inserts a bullet in tag order. Parallel lanes then touch different lines.
- **Rebase lanes often.** Have each lane merge the integration branch before its
  final gate (the later lanes did this). The integration gate then mostly
  re-confirms instead of discovering.
- **Gate a batch at once.** Batch compatible lanes into one gate, and bisect only on
  failure. Tonight's combined gates (text+sort, noreturn+roots+arrays) found
  nothing the single gates would have.
- **Split lanes by file ownership, not by feature.** Most semantic conflicts came
  from two lanes editing `src/qbe.zig`, `sema.zig` or the adapter.

## 4. A red base and invisible tests

**The red base.** For the first half of the run `zig build test` had 46–47
pre-existing failures from another session's migration. Every gate needed a
`gate_diff` against the base. Every "new" failure needed a rerun to tell a flake
from a regression, and real ones had to be spotted inside a red summary. The base
turned green only when that migration landed mid-run.

**Tests that never ran or failed quietly:**
- 12 of 37 `tests/lang` files had no `main` and had never run (fixed: discovery now
  runs every test-declaring file and fails on skipped ones).
- The C runtime suites and the adapter's unit tests were outside the gate, and two C
  suites had been broken by merges without anyone noticing (fixed:
  `test-native-memory`, `test-llvm-adapter` under `zig build test`).
- A timing-sensitive integration test ("guest benchmarks write a candidate…")
  flaked under load in three different gates.

**To do:**
- **Keep main green.** Don't start parallel lanes on a red base.
- **Make timing-dependent tests insensitive to load,** or quarantine them.
- **Scan for tests the gate never runs.** A new test that no step runs should fail
  the gate, the way test discovery now does for guest files.

## 5. Model time — 15.7 h, 35%

**This is the least attributable share.** It includes real reasoning, which is
most of the value, but also re-reading large files and long reports:

- `src/sema.zig` is 6,874 lines, `src/qbe.zig` 3,048, `llvm_emit.py` 2,101 and
  `SPEC.md` 1,112, and nearly every lane read parts of them.
- Lane briefs pointed at 3–6 prior audit reports each, several hundred lines apiece.

**Levers, not measured here:**
- split `sema.zig` and `qbe.zig` along the seams the lanes already used
  (`qbe_borrow`, `qbe_liveness`, `qbe_range_keys` and `qbe_frame_map` were split out
  this way);
- keep each audit's decisions in a short header the next brief can quote;
- give agents a symbol index (`mylang context --symbol` exists for guest code;
  nothing similar exists for the compiler's own Zig).

## 6. What was not a bottleneck

- **The commit hook** (`guardian-check all . --gate`): 1.3 s cold, 50 ms cached.
- **Guardian rework:** 24 change-classification, 15 line-length, 10 spec, and a
  handful each of complexity rules. Each costs one edit and a 15 s rebuild. It is
  friction, but small, and the change-classification rule caught untested
  behaviour several times.
- **Focused Zig tests** (`test-units`/`test-cli -Dtest-filter`): 18 s average.
  Debug builds: 15 s.
- **Git operations:** 0.14 h in total.

## Ranked changes

| # | change | estimated effect | cost |
|---|---|---|---|
| 1 | Measure guest programs with the Debug compiler; harness defaults to `zig-out/bin/mylang`; ReleaseFast only when timing the compiler | about 8–9 agent-hours of ~45 (≈ 20%) | small: `CLAUDE.md`, two script defaults |
| 2 | Cap concurrent build-heavy agents at ~4; memory-aware slot wrapper in `scripts/` | gates and test waits back toward 4–5 min / 30 s; fewer OOM kills and load flakes | small |
| 3 | Reserved timing cores plus instruction-count A/B via `bench-parity` counters | fewer rounds per measurement; no separate quiet re-measure | small |
| 4 | SPEC bullets without a shared append point; lanes merge integration before their final gate; batch gating | most `SPEC.md` conflicts gone; fewer post-merge breaks | small–medium |
| 5 | Quarantine or fix the load-sensitive timing test; fail on tests no step runs | no false "new failures" | small |
| 6 | Split `sema.zig`/`qbe.zig`; short decision headers in audits | less re-reading per lane | medium |
| 7 | A second machine or CI runner for gates | integration off the critical path | infrastructure |

Items 1–3 would have removed most of the waiting in this run without changing
the compiler.
