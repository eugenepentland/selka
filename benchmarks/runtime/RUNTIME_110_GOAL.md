# Runtime performance goal: LLVM within 1.10×, with QBE tracked

This is the execution plan and live status document for the next performance
campaign. The goal is active. The initial table came from saved measurements; new results
will be added with their own evidence IDs. Update this file in place and retain
the raw evidence for every reported result.

## Status

<!-- STATUS-START -->
- **Campaign:** active; B1 confirmed; equality candidate held after regression, loop screen next.
- **Last document update:** 2026-10-04 01:53:10 UTC.
- **Active batch:** B3/B4 loop subset candidate `5dc31c3a`, focused screen
  queued after correctness and independent review. B2 equality candidate
  `965d416c` remains unintegrated after a repeatable search regression; an
  isolated join optimization and B11 sorting optimization are in progress.
- **Current implementation:** `perf/runtime-parity-20261003`; production source
  `730a86e62b47c922dc1411d24b5868c3bd2132f3`.
- **Latest complete integrated measurement:** B0, the prior campaign's final run.
- **Acceptance scope:** LLVM required; QBE tracked separately.
- **New goal confirmations:** **6/80 required LLVM targets** at production `730a86e6`.
- **LLVM states:** 6 confirmed, 1 observed within 1.10 awaiting confirmation,
  73 above 1.10; 0 stale confirmations and 0 reopened confirmed targets.
- **Dashboard artifact:** [B1 accepted status](candidates/goal110-dashboard-20261004-b1.json).
- **Active operations:** B1 measurements and the quiet B2 repeat finished.
  The next timing lane belongs to `goal110_calls`. Join and sorting work will
  hold builds during measurements. No experimental production changes have
  been integrated into the accepted branch yet.
- **Next action:** measure the four selected loop cases and the excluded-path
  regression sentinel. Investigate equality with matched-host control artifacts
  while keeping the measured regression visible.

| Backend | Required targets | Latest observed ≤1.10 | Latest observed >1.10 | Goal confirmations |
|---|---:|---:|---:|---:|
| MyLang LLVM | 80 | 7 | 73 | 6 |
| MyLang QBE | 0 (80 tracked) | 2 | 78 | Not required |
<!-- STATUS-END -->

The counts above use the **fastest current configuration in each measured row**.
They differ from the earlier campaign's counts against its frozen historical
1.00 targets. An observed result below 1.10 is not yet a confirmed pass for this
new goal. Six LLVM targets are confirmed at the linked production revision;
74 remain unresolved. QBE being above 1.10 does not prevent completion.

- [Live speed table](#live-speed-table)
- [Work queue](#work-queue)
- [Progress log](#progress-log)
- [Evidence register](#evidence-register)

## Launch instruction

Use this instruction when ready to start:

> Start a goal to complete `benchmarks/runtime/RUNTIME_110_GOAL.md` in
> `/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-20261003`.
> Bring MyLang LLVM within 1.10× of the fastest runtime on every benchmark at
> both sizes. Track QBE separately and check for regressions; QBE parity is not
> required for completion. Use Sol 6.1 agents with xhigh reasoning for
> implementation. Work in small batches, confirm improvements, and maintain
> this Markdown file as the live status dashboard. Preserve benchmark
> contracts and language semantics. Finish with full-suite validation on the
> integrated revision; do not declare completion with unresolved targets.

The coordinator owns this document and integration branch. Agents should work
in separate worktrees, return changes and evidence, and avoid concurrent edits
to the dashboard. Code inspection and implementation can run in parallel;
performance measurements must be serialized.

## Objective and acceptance

There are **40 cases: 35 microbenchmarks and five application workloads**.
Each has two existing sizes, giving **40 × 2 = 80 required LLVM targets**.
Keep the other **80 QBE observations** visible for comparison and regression
tracking. Compare against all six existing configurations: Rust, Go, Zig
ReleaseSafe, Zig ReleaseFast, MyLang LLVM and MyLang QBE.

For a case and size, using medians from the same measurement session:

```text
fastest = min(Rust, Go, Zig Safe, Zig Fast, MyLang LLVM, MyLang QBE)
LLVM ratio = MyLang LLVM / fastest
QBE ratio  = MyLang QBE  / fastest
required target: LLVM ratio <= 1.10
QBE ratio: reported for information; no parity threshold required
```

Keep the reference compiler versions, reference executable bytes, benchmark
sources, inputs, optimization/ISA policies and semantic contracts fixed to the
recorded starting setup. Remeasure reference executables alongside the candidate;
old wall-clock timings alone are not acceptance evidence. The fastest arm can
change, including when one MyLang backend improves. Recompute the denominator
for every new complete row. If QBE wins a case, LLVM still needs to be within
1.10 of it. Improving LLVM can increase QBE's normalized ratio without making
QBE itself slower; that alone is not a QBE regression.

This is a new **current-fastest 1.10** objective. Keep the earlier frozen target
files, raw results and reports unchanged. Their `numerical_target_status` and
confidence intervals against the original winner do not implement this goal.
Do not reinterpret those historical fields as current-fastest acceptance.

A required LLVM target is confirmed only when:

1. Correctness qualification and checks appropriate to the changed mechanism
   pass, including relevant edge cases and nearby inputs outside the timed set.
2. A normal six-configuration run and an independent confirmation session on
   the same production revision both show an unrounded ratio at or below 1.10.
3. Uncertainty supports the threshold. Use same-round paired samples; check
   upper 95% interval bounds for LLVM against each other configuration
   are at or below 1.10. Self-comparisons are exactly one. If intervals cross
   the threshold, record **inconclusive** and gather independent evidence or
   improve the margin. Never pair archived rounds with newly collected rounds.
4. The evidence records source, compiler/guest identities, actual backend,
   build policy, input, rounds, calibration limitations and host conditions.

These are per-comparison intervals, not a simultaneous 95% guarantee over the
whole campaign. Repeated tuning and winner selection remain limitations; the
independent final sessions are necessary. Aim for about 1.05 when practical to
leave room for measurement variation. A 1.099 screen is only a promising result.

Final completion requires all 80 LLVM cells passing on one integrated production
revision, a second independent full-suite confirmation of that revision, and
the repository correctness gates. Do not average failures away. Results from
different revisions cannot collectively establish completion.

QBE must remain correct. Investigate material QBE performance regressions caused
by shared changes, then fix them or explicitly record the evidence and tradeoff.
There is no requirement to close QBE's existing gaps to 1.10. Prioritize work
that helps LLVM; take QBE improvements when they arise from shared mechanisms.

## How to work

### 1. Prepare the campaign

- Work in `perf/runtime-parity-20261003` at the path in the launch instruction.
  The starting implementation HEAD is `b1b0500e`; its production source pin is
  `730a86e62b47c922dc1411d24b5868c3bd2132f3`. Later documentation commits may
  advance HEAD. Check status and source identity before starting new work.
- The original `/home/epentland/ai/canopy/mylang` checkout has unrelated local
  changes. Keep this campaign in its existing isolated worktree.
- Lox integration `codex/lox-parity-20261003` / main `1fd1d566` is already in
  the implementation's ancestry. Do not repeat that integration.
- Read [candidate tooling](CANDIDATES.md), [prior implementation and remaining
  gaps](candidates/README.md), and the [earlier audit](audit/README.md). This
  document supplies the new threshold and workflow; earlier 1.00 completion
  rules belong to the earlier campaign.
- Use B0 below to triage without rerunning the full suite immediately. Verify
  current artifacts before reusing them. A missing reference artifact or changed
  policy must be repaired or explicitly reconciled, never silently substituted.
- First add a small report/update helper for this goal, if needed: consume
  verified reports, compute LLVM current-fastest 1.10 acceptance and QBE tracking
  states with paired comparisons. Update only measured rows, retain evidence
  IDs, and recalculate the summary.
  Keep old report schemas and frozen comparison behavior intact. Cover the
  meaningful failure modes: missing arms, size-specific winners, incomplete
  subsets, changed identities and accidental comparison of different sessions.

### 2. Work on a small batch

Choose two to four related cases from the queue. Prioritize a combination of
distance to target, likely effort, measurement cost and benefit to other cases.
The shortest kernel is not necessarily the cheapest benchmark: calibration
repeats fast kernels to gather enough data.

For each experiment:

1. Record the hypothesis, affected backends/cases and intended general benefit.
2. Inspect emitted code, ownership/allocation behavior or a focused profile.
   Identify the work responsible for the gap before changing code.
3. Make one coherent optimization and run the relevant correctness checks.
   Preserve error behavior, overflow/bounds checks, accounting, lifetimes and
   allocation-refusal semantics unless an existing proof makes work redundant.
4. Build the affected guests and run a short timing screen. Start with five
   rounds and one warmup, retaining the usual calibration and checksums. These
   are exploratory measurements, never completion evidence.
5. Measure a small regression set, record results and keep or reject the change.
6. When promising, run normal confirmation: 15 randomized rounds, three warmups,
   both original sizes, all six configurations, then an independent session.

The existing `expanded/run.py --only CASE ...` already selects timing cases,
keeps both sizes and all six configurations, and still performs full checksum
qualification. Use that initially. It does not currently offer a reduced-arm
timing switch. Add a separately labeled lean mode only if measured overhead
justifies it; a candidate-versus-leader screen cannot establish the current
six-arm winner or overwrite a complete dashboard row.

For exploratory builds, the existing compiler builder supports `--optimize
Debug`; guests still need the recorded ReleaseFast/backend settings. Validate
the actual guest code/identity. Use a ReleaseFast compiler host for milestones
and final acceptance, as in the existing campaign. Reuse verified reference
executables and unchanged artifacts; rebuild whenever their identity changes.

Keep benchmark timing serial on the reserved CPU. Existing invocations acquire
the timing lock themselves; do not wrap the runner in that same lock. Use
`scripts/build-slot.sh` for builds, private Zig caches, disk TMPDIR and `-j2`.
Respect the repository's build and Guardian requirements, including committing
Guardian feedback when a gate is exercised.

### 3. Guard previous progress

Each batch also selects two or three regression cases: one previously passing
LLVM case and cases that exercise the changed compiler/runtime subsystem. Rotate
other completed cases through subsequent screens so coverage stays broad.

Compare meaningful suspected regressions with the previous accepted binary in
the same session. A repeated slowdown above 5%, even while below 1.10, needs
investigation and an explicit tradeoff decision. Apply this slowdown check to
both backends using same-session before/after absolute times, not a change in
their ratio to a newly faster competitor. A previously confirmed LLVM cell
that reproducibly exceeds 1.10 reopens immediately. Never hide regressions by
reporting only a geometric mean or by choosing a more favorable old denominator.

Mark affected historical confirmations stale after production changes until
they are rechecked. Keep their previous speed and evidence visible. Run a full
suite after major shared compiler/runtime changes or a substantial group of
completed batches, and at final acceptance—not after every edit.

### 4. Handle hard cases and finish

After three distinct unsuccessful hypotheses on a case, record the evidence,
likely prerequisite and next useful experiment; move to independent work while
keeping the LLVM target open. This is a scheduling decision, not a pass or removal
from scope. Revisit deferred targets after their prerequisites improve.

Some targets may require broad compiler work. For example, the very large
`alloc_short` ratio includes work eliminated by the reference compiler; a faster
allocator alone may not close it. Diagnose that mechanism, preserve observable
semantics, and avoid benchmark-name/input-specific shortcuts. Application rows
also include library behavior; do not quietly replace their algorithms or edit
competitor ports to make the comparison easier.

Once every LLVM cell has focused confirmation, run the integrated full suite,
recompute every current winner, and fix any reopened targets in small batches.
Then run the independent full confirmation and final correctness gates on the
same production revision. Any subsequent production change invalidates that
final acceptance and requires a new integrated check. Report unresolved targets
honestly if completion has not been achieved.

## Work queue

This is a starting order, not an instruction to ignore newly discovered shared
prerequisites. Every case appears once. Both sizes remain required for LLVM;
measure QBE alongside it without treating its existing gaps as acceptance work.

| Batch | Cases | Initial purpose | State |
|---|---|---|---|
| B1 | `mutate_nested`, `bytes_scan`, `string_search` | Confirm existing LLVM wins and establish regression checks | Confirmed 6/6 at `730a86e6` (G1) |
| B2 | `string_equal`, `string_join` | Equality/ownership overhead and nearby large-input targets | Quiet repeat of `965d416c`; first screen has regressions/noise |
| B3 | `record_reads`, `record_construct`, `record_update` | Record representation, scalar replacement and transfers | Queued |
| B4 | `call_direct`, `call_indirect`, `option_handle`, `result_propagate` | Calls, inlining, dispatch and return paths | `5dc31c3a` checked/reviewed; focused timing queued |
| B5 | `integer_math`, `float_math`, `branch_predictable`, `branch_mixed` | Scalar lowering and loop invariants | Queued |
| B6 | `list_scan`, `list_append`, `list_filter`, `mutate_unique` | Iteration, capacity and uniqueness | Queued |
| B7 | `tagged_stack`, `mutate_shared`, `alloc_short`, `alloc_retained` | Ownership, allocation elimination and retained data | Queued |
| B8 | `dict_lookup`, `dict_lookup_str` | Lookup/probe and key costs | Queued |
| B9 | `dict_update`, `dict_update_str`, `set_dedup` | Publication, replacement and deduplication | Queued |
| B10 | `binary_search`, `packet_decode` | Bounds, branches and scalar reads | Queued |
| B11 | `sort_int`, `sort_records` | Comparator dispatch and scratch work | Queued |
| B12 | `string_split`, `int_parse`, `int_format` | Text ownership, parsing and formatting | Queued |
| B13 | `word_count`, `csv_aggregate`, `json_transform`, `lox_eval` | Combined application behavior and remaining library costs | Queued |

B1's LLVM observations are already at 1.00; this batch first qualifies the new
acceptance/reporting process and supplies regression checks. QBE is recorded,
but its small `bytes_scan` gap of 2.3430 is not work required by this goal.
Then move to the open LLVM targets. Reorder or defer with an explanation when
a mechanism proves larger than a quick improvement.

## Reporting protocol

Treat this file as the single place to check campaign status. Update it:

- At the start of a batch or a long build/run: current revision, work item,
  hypothesis, start time and expected next checkpoint.
- After every completed screen, confirmation, rejected experiment, integration
  or regression discovery. Update within five minutes of receiving results.
- At least every ten minutes during ongoing work, even when a long operation
  has not finished. State what is still running; do not invent partial results.
- Before yielding, stopping or handing off: exact next action, active processes,
  unresolved cases and evidence locations.

Continue concise chat updates during interactive work. The file must stand on
its own, so no essential status should exist only in chat or an agent message.

For each measured row, update **all six arm ratios, the fastest absolute median,
both MyLang states and its evidence ID together**. Unmeasured rows keep their
values and original evidence ID. A mixed-revision dashboard shows latest known
results, not a full-suite pass. Keep the most recent complete integrated result
explicitly identified in the status section.

The summary should distinguish observed below-threshold LLVM cells, confirmed
LLVM cells, open/inconclusive LLVM cells, stale confirmations and regressions.
Keep QBE observations and regressions in a separate count. Do not count an
unmeasured or stale LLVM cell as confirmed for the current revision. Retain failed
and rejected experiments in the progress log, with before/after ratios, sizes,
backend, source revision, correctness result, decision and next action. Record
reduced-arm screens there without replacing full-row dashboard evidence.

Evidence IDs resolve through the register to raw reports, compiler/source and
guest identities, UTC timing, rounds, checks and confirmation reports. Preserve
raw reports under unique names. Never overwrite an old measurement with a new
candidate under the same ID.

## Live speed table

Each number is a median-time ratio to the **fastest of the six configurations
in that row's evidence session**. Lower is better; the winner is **1.0000**.
`Best ns/iteration` is the absolute winning median. Multiply it by an arm's
ratio for an approximate absolute time; the linked raw data retain full
precision. An iteration may mean an operation, a data pass or a complete job;
compare arms within a row, not absolute numbers between unrelated cases.

States are listed **LLVM / QBE**. The QBE state is informational; only LLVM
states contribute to goal completion:

- **O**: observed above 1.10; open for LLVM, a recorded gap for QBE.
- **P**: observed at or below 1.10; LLVM confirmation pending, QBE informational.
- **C**: confirmed by this campaign's acceptance procedure at the linked revision
  (optional for QBE).
- **I**: below-threshold estimate with inconclusive confirmation.
- **S**: previous confirmation is stale after a relevant production change.
- **R**: previously confirmed target has regressed above 1.10.

States use unrounded data. Initially every row comes from B0; no new timings
were collected to populate this document. B0 has per-comparison uncertainty
against the original frozen winner, which is not always today's winner; it
does not supply the new goal's confirmation protocol.

<!-- DASHBOARD-START -->
| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| record_reads / small (64) | 4.0033 | **1.0000** | 1.2072 | 1.3713 | 1.2724 | 1.4598 | 3.3636 | O / O | B0 |
| record_reads / large (4096) | 4.5650 | **1.0000** | 1.1234 | 1.3275 | 1.2162 | 1.4129 | 3.6264 | O / O | B0 |
| tagged_stack / small (64) | 6.4408 | **1.0000** | 1.0269 | 1.8674 | 1.9016 | 3.0195 | 4.0123 | O / O | B0 |
| tagged_stack / large (4096) | 7.6010 | **1.0000** | 1.0901 | 1.8459 | 1.8480 | 3.0251 | 3.6091 | O / O | B0 |
| mutate_unique / small (64) | 3.2762 | **1.0000** | 1.1804 | 1.2290 | 1.2094 | 1.5747 | 7.6379 | O / O | B0 |
| mutate_unique / large (1024) | 3.4398 | **1.0000** | 1.1486 | 1.3022 | 1.2176 | 1.4749 | 6.9678 | O / O | B0 |
| mutate_shared / small (64) | 11.8443 | 1.0509 | 5.1436 | 1.6182 | **1.0000** | 11.9037 | 15.1546 | O / O | B0 |
| mutate_shared / large (1024) | 96.3787 | **1.0000** | 8.6954 | 2.2145 | 1.7497 | 3.2446 | 3.9678 | O / O | B0 |
| integer_math / small (64) | 105.7685 | **1.0000** | 1.3640 | 1.3398 | 1.1877 | 1.8197 | 5.0610 | O / O | B0 |
| integer_math / large (4096) | 6392.6711 | **1.0000** | 1.3269 | 1.3768 | 1.2743 | 1.8377 | 5.2206 | O / O | B0 |
| float_math / small (64) | 91.4178 | 1.5745 | 1.5169 | 1.5610 | **1.0000** | 2.5058 | 6.5162 | O / O | B0 |
| float_math / large (4096) | 5916.6681 | 1.5073 | 1.4176 | 1.3404 | **1.0000** | 2.5444 | 6.5156 | O / O | B0 |
| branch_predictable / small (64) | 60.8996 | 1.0064 | 1.9126 | 2.1806 | **1.0000** | 2.1627 | 6.7382 | O / O | B0 |
| branch_predictable / large (4096) | 3857.2533 | **1.0000** | 2.0636 | 2.3532 | 1.0083 | 2.1880 | 6.9528 | O / O | B0 |
| branch_mixed / small (64) | 80.8896 | 1.0122 | 1.4726 | 1.7674 | **1.0000** | 1.4963 | 5.7080 | O / O | B0 |
| branch_mixed / large (4096) | 5392.7967 | **1.0000** | 1.6810 | 1.8025 | 1.0213 | 1.4794 | 5.4820 | O / O | B0 |
| record_construct / small (64) | 117.0071 | **1.0000** | 1.3917 | 1.5113 | 1.3046 | 1.8202 | 9.9000 | O / O | B0 |
| record_construct / large (4096) | 8032.3910 | **1.0000** | 1.4712 | 1.5283 | 1.3087 | 1.8130 | 9.9099 | O / O | B0 |
| record_update / small (64) | 135.6380 | **1.0000** | 1.3243 | 1.6213 | 1.2125 | 1.8238 | 12.6456 | O / O | B0 |
| record_update / large (4096) | 7810.9254 | **1.0000** | 1.4069 | 1.6395 | 1.3422 | 2.0557 | 14.0277 | O / O | B0 |
| call_direct / small (64) | 53.5971 | **1.0000** | 1.4886 | 1.4581 | 1.1261 | 1.6899 | 18.3277 | O / O | B0 |
| call_direct / large (4096) | 2328.1370 | **1.0000** | 1.7183 | 1.5253 | 1.0437 | 2.1965 | 27.0024 | O / O | B0 |
| call_indirect / small (64) | 119.4754 | 1.0756 | 1.3121 | 1.4906 | **1.0000** | 1.3423 | 8.8352 | O / O | B0 |
| call_indirect / large (4096) | 6998.9496 | 1.1581 | 1.3453 | 1.5799 | **1.0000** | 1.3756 | 9.6028 | O / O | B0 |
| option_handle / small (64) | 50.9477 | **1.0000** | 2.2121 | 2.3130 | 1.7541 | 2.2282 | 21.0979 | O / O | B0 |
| option_handle / large (4096) | 2433.8520 | **1.0000** | 2.8414 | 2.6665 | 2.1914 | 2.6353 | 27.9332 | O / O | B0 |
| result_propagate / small (64) | 67.8821 | **1.0000** | 2.2136 | 1.8857 | 1.2119 | 2.4130 | 19.6002 | O / O | B0 |
| result_propagate / large (4096) | 3981.3316 | **1.0000** | 2.4216 | 2.0523 | 1.4753 | 2.4797 | 22.2252 | O / O | B0 |
| binary_search / small (16) | 58.4475 | **1.0000** | 1.9603 | 1.5091 | 1.4379 | 1.9800 | 7.2034 | O / O | B0 |
| binary_search / large (256) | 1580.0181 | **1.0000** | 1.6992 | 3.4432 | 1.3305 | 1.9192 | 10.6123 | O / O | B0 |
| packet_decode / small (16) | 44.4827 | 1.1836 | 2.6728 | 1.8419 | **1.0000** | 2.1621 | 10.4416 | O / O | B0 |
| packet_decode / large (256) | 660.8722 | 1.2066 | 3.0576 | 1.9560 | **1.0000** | 2.2540 | 11.4511 | O / O | B0 |
| list_scan / small (64) | 49.0371 | **1.0000** | 1.2722 | 1.8459 | 1.3498 | 2.0643 | 5.0333 | O / O | B0 |
| list_scan / large (4096) | 3380.0797 | **1.0000** | 1.2127 | 1.6581 | 1.3890 | 1.5361 | 3.6315 | O / O | B0 |
| list_append / small (64) | 148.6046 | 1.3928 | 2.0184 | 2.2165 | **1.0000** | 2.7172 | 4.4791 | O / O | B0 |
| list_append / large (4096) | 6910.9729 | 1.0796 | 1.9621 | 2.1933 | **1.0000** | 2.4487 | 3.8480 | O / O | B0 |
| list_filter / small (64) | 177.9840 | 1.0990 | 1.9368 | 1.5068 | **1.0000** | 2.6375 | 4.7879 | O / O | B0 |
| list_filter / large (4096) | 6892.5245 | **1.0000** | 1.9650 | 1.8369 | 1.2613 | 2.4967 | 5.3200 | O / O | B0 |
| dict_lookup / small (64) | 300.9516 | 2.4699 | 1.7785 | 2.0004 | **1.0000** | 1.9397 | 3.2588 | O / O | B0 |
| dict_lookup / large (4096) | 33803.0743 | 1.3746 | **1.0000** | 1.7895 | 1.3927 | 1.7863 | 2.6548 | O / O | B0 |
| dict_lookup_str / small (64) | 467.1945 | 2.2418 | 1.4048 | 1.2997 | **1.0000** | 1.4698 | 2.2298 | O / O | B0 |
| dict_lookup_str / large (4096) | 48823.4819 | 1.4964 | **1.0000** | 1.5235 | 1.2243 | 1.6699 | 2.3235 | O / O | B0 |
| dict_update / small (64) | 2901.9315 | 2.4568 | 3.3928 | 2.0251 | **1.0000** | 5.0071 | 6.7677 | O / O | B0 |
| dict_update / large (4096) | 517545.3553 | 1.0873 | 1.1729 | 1.3933 | **1.0000** | 2.2007 | 2.7962 | O / O | B0 |
| dict_update_str / small (64) | 5815.2123 | 2.7412 | 1.9978 | 1.3210 | **1.0000** | 2.9788 | 3.8135 | O / O | B0 |
| dict_update_str / large (4096) | 813334.5833 | 1.5250 | **1.0000** | 1.2508 | 1.0737 | 1.7264 | 2.0366 | O / O | B0 |
| set_dedup / small (64) | 315.2532 | 3.2981 | 3.9658 | 2.1143 | **1.0000** | 10.2592 | 13.5868 | O / O | B0 |
| set_dedup / large (4096) | 65854.8194 | 1.1052 | 1.2774 | 1.4120 | **1.0000** | 3.3251 | 4.2926 | O / O | B0 |
| alloc_short / small (64) | 3.9337 | 20.8925 | 38.2879 | 88.5583 | **1.0000** | 1256.0525 | 1706.3399 | O / O | B0 |
| alloc_short / large (1024) | 3.9012 | 327.5994 | 536.1037 | 1374.7989 | **1.0000** | 19711.5691 | 26589.1038 | O / O | B0 |
| alloc_retained / small (64) | 1292.6997 | 1.0697 | 1.4853 | 1.0303 | **1.0000** | 2.3540 | 3.5644 | O / O | B0 |
| alloc_retained / large (1024) | 20710.2684 | 1.0504 | 1.2628 | 1.0366 | **1.0000** | 2.2667 | 3.3646 | O / O | B0 |
| mutate_nested / small (64) | 909.7296 | 1.4770 | 1.5487 | 1.5239 | 1.3798 | **1.0000** | 1.1346 | C / O | G1 |
| mutate_nested / large (1024) | 8702.5518 | 2.5893 | 2.3812 | 2.5576 | 2.3413 | **1.0000** | 1.1070 | C / O | G1 |
| sort_int / small (64) | 171.4333 | 1.3346 | 6.3726 | 1.6065 | **1.0000** | 1.6126 | 2.8249 | O / O | B0 |
| sort_int / large (4096) | 44258.7276 | 1.4306 | 5.3712 | 1.4788 | 1.0267 | **1.0000** | 1.2139 | P / O | B0 |
| sort_records / small (64) | 571.1779 | 1.1716 | 12.9634 | 1.4071 | **1.0000** | 2.1426 | 2.8365 | O / O | B0 |
| sort_records / large (4096) | 52264.4234 | **1.0000** | 24.5636 | 2.2368 | 1.7803 | 1.1932 | 1.5272 | O / O | B0 |
| lox_eval / small (16) | 738.1632 | **1.0000** | 1.1383 | 2.6921 | 2.6291 | 3.6607 | 4.0643 | O / O | B0 |
| lox_eval / large (256) | 10981.4215 | **1.0000** | 1.1776 | 2.7947 | 2.7405 | 3.6183 | 3.9186 | O / O | B0 |
| bytes_scan / small (64) | 3.6132 | 4.9535 | 6.6721 | 7.6987 | 3.3981 | **1.0000** | 2.3594 | C / O | G1 |
| bytes_scan / large (4096) | 88.9207 | 13.5780 | 13.9344 | 18.5810 | 8.9383 | **1.0000** | 1.0693 | C / I | G1 |
| string_equal / small (64) | 3.0562 | **1.0000** | 1.5325 | 1.3735 | 1.2617 | 1.3640 | 7.2900 | O / O | B0 |
| string_equal / large (4096) | 30.9760 | **1.0000** | 1.2294 | 2.1009 | 1.6346 | 1.1642 | 23.0765 | O / O | B0 |
| string_search / small (64) | 22.2408 | 2.1525 | 1.2343 | 4.5417 | 3.7611 | **1.0000** | 1.2519 | C / O | G1 |
| string_search / large (4096) | 101.0547 | 14.4075 | 7.1893 | 33.8407 | 29.9761 | **1.0000** | 1.0212 | C / I | G1 |
| string_split / small (64) | 557.5921 | **1.0000** | 1.8763 | 1.8560 | 1.7269 | 6.2247 | 8.1218 | O / O | B0 |
| string_split / large (4096) | 28435.3492 | **1.0000** | 2.3570 | 2.1980 | 2.0666 | 7.6152 | 9.7548 | O / O | B0 |
| string_join / small (64) | 220.9090 | **1.0000** | 1.8606 | 1.4400 | 1.2367 | 1.8723 | 1.5513 | O / O | B0 |
| string_join / large (4096) | 13591.0305 | **1.0000** | 1.9143 | 1.3440 | 1.2312 | 1.6706 | 1.1320 | O / O | B0 |
| int_parse / small (64) | 4.4765 | **1.0000** | 5.4265 | 1.2862 | 1.2858 | 2.3003 | 4.1124 | O / O | B0 |
| int_parse / large (4096) | 5.1722 | **1.0000** | 5.3121 | 1.3142 | 1.2250 | 2.2325 | 3.8033 | O / O | B0 |
| int_format / small (64) | 14.6652 | **1.0000** | 1.1260 | 2.8091 | 2.2430 | 4.1006 | 5.8296 | O / O | B0 |
| int_format / large (4096) | 15.2605 | **1.0000** | 1.1656 | 2.8462 | 2.4104 | 3.9492 | 5.7315 | O / O | B0 |
| word_count / small (16) | 191.7825 | 1.8371 | 3.3564 | 1.2846 | **1.0000** | 12.1132 | 15.9617 | O / O | B0 |
| word_count / large (256) | 2487.5682 | 1.5222 | 4.0224 | 1.2683 | **1.0000** | 8.7401 | 11.3832 | O / O | B0 |
| csv_aggregate / small (16) | 2944.5439 | 1.3879 | 1.7711 | 1.2608 | **1.0000** | 6.0784 | 9.0282 | O / O | B0 |
| csv_aggregate / large (256) | 52479.7031 | 1.2783 | 1.5519 | 1.2404 | **1.0000** | 5.6377 | 8.3173 | O / O | B0 |
| json_transform / small (16) | 6899.6433 | **1.0000** | 4.3197 | 1.6697 | 1.1923 | 8.0906 | 13.1937 | O / O | B0 |
| json_transform / large (256) | 112741.4467 | **1.0000** | 4.3936 | 1.8951 | 1.4849 | 7.7247 | 12.8006 | O / O | B0 |
<!-- DASHBOARD-END -->

## Evidence register

| ID | Source and measurement | Reports | Interpretation |
|---|---|---|---|
| B0 | Production `730a86e62b47c922dc1411d24b5868c3bd2132f3`; session `d4378789-427a-4862-8718-52189af6bc96`; 2026-10-03 23:40:22 through 2026-10-04 00:04:48 UTC; 15 rounds, 3 warmups | [Raw run](candidates/final-730a86e6-releasefast-20261003.json.gz), [comparison JSON](candidates/final-730a86e6-releasefast-20261003-comparison.json.gz), [measurement receipt](candidates/final-730a86e6-releasefast-20261003-README.md), [all-arm absolute times](candidates/final-730a86e6-releasefast-20261003-six-arm.md) | Starting observations from the completed prior campaign; not new goal confirmations |
| G1A | Production `730a86e6`; session `f58b516a-fc86-49b6-b5fc-49bda2057537`; 2026-10-04 01:10:28–01:13:38 UTC; 15 rounds, 3 warmups | [Raw](candidates/goal110-b1-730a86e6-20261004-a.json.gz), [comparison](candidates/goal110-b1-730a86e6-20261004-a-comparison.json.gz), [command](candidates/goal110-b1-730a86e6-20261004-a-command.json) | Six B1 rows; LLVM fastest in all six; verification passed; independent confirmation pending |
| G1 | Production `730a86e6`; independent A/B sessions on 2026-10-04; 15 rounds/3 warmups each; latest medians from B | [Accepted analysis](candidates/goal110-b1-730a86e6-20261004-accepted.json), [receipt](candidates/goal110-b1-730a86e6-20261004-README.md), [B raw](candidates/goal110-b1-730a86e6-20261004-b.json.gz), [correctness review](candidates/goal110-b1-730a86e6-20261004-correctness-review.json), [checks attestation](candidates/goal110-b1-730a86e6-20261004-checks.json) | Six LLVM cells confirmed; 74 untouched rows retain B0; no new production optimization claimed |

B0 comparison JSON (uncompressed) SHA256:
`dbb1906bcac50cb015171cce52ff68a0297f728db81e9ec4927f4f158117d473`.
B0 raw report (uncompressed) SHA256:
`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`.
Prior [correctness receipts](candidates/validation/730a86e6-validation.json) and
[independent replay](candidates/validation/730a86e6-coordinator-replay.json)
describe the starting implementation. New changes require new validation.

## Progress log

Append entries; do not remove failed experiments or historical outcomes.

| UTC | Revision / evidence | Work and result | Decision / next action |
|---|---|---|---|
| 2026-10-04 | `730a86e6` / B0 | Created the goal plan and populated all 80 rows from the existing verified comparison. LLVM has 7/80 observations within 1.10; none has this goal's confirmation. QBE has 2/80 within 1.10 for tracking. No builds, profiling or evals were run. | Ready to launch. Begin with campaign preflight, report/update support and B1. |
| 2026-10-04 | Scope decision | User selected LLVM required, QBE tracked separately. The goal has 80 required targets. QBE remains in all-arm comparisons and regression checks. | Prioritize LLVM parity; QBE's existing gaps do not block completion. |

| 2026-10-04 01:07:09 UTC | `b1b0500e` / production `730a86e6` | Started the user-authorized goal. Verified worktree state and read the complete acceptance plan; no production edits or new timing yet. | Prepare isolated Sol 6.1/xhigh tasks for reporting and next-batch optimizations; coordinator owns B1 timing and the dashboard. |

| 2026-10-04 01:11:10 UTC | `a0892204` / production `730a86e6` | Replayed B0 with live source/artifact checks: 480 groups valid; production diff from pin is empty. Goal-plan commit passed Guardian 88/88. Started fresh B1 session A, 15 rounds/3 warmups, all six arms and both sizes, reusing verified binaries. | Await session A; reporting and independent text/call investigations run in isolated worktrees. No new performance claim yet. |

| 2026-10-04 01:15:56 UTC | `730a86e6` / G1A | Fresh B1 A: LLVM ratio 1.0000 in all six rows, 540 timing samples and 720 checksum qualifications; live artifact replay passed. CPU sibling average busy 0.36%, no frequency warning. Unchanged production. | Started independent B1 B (exec `63831`). No C states yet. Agents found a loop branch-attribution mismatch and prepared a general bounded string-equality candidate; neither has timing evidence yet. |

| 2026-10-04 01:17:23 UTC | B3/B4 diagnostic correction | Repeated per-element dispatch is confirmed, but missing branch labels in final IL do not establish the cause: specialization runs before label elision. Agent withdrew the mapping diagnosis before production edits and is capturing pre-rewrite refusal evidence. | Retain the dispatch hypothesis; do not add speculative marker changes. B2 equality candidate has bounded loads and sanitizer coverage in progress; timing still pending. |

| 2026-10-04 01:22:39 UTC | `730a86e6` / B1 A+B | Session B finished at 01:17:08 UTC, 540 samples/720 qualifications; live artifact verification passed. Independent pairwise interval replay puts the worst LLVM upper95 bound at 1.0551 across both sessions. Replayed 516 prior RF holdouts with exact A/B artifact identity and live manifest checks; reviewed unchanged-source gate receipts. | Finalize machine-readable acceptance receipt; no new full gate was claimed. Text agent owns the next timing window; loop agent is using gate-compliant diagnostics to establish the actual refusal. |

| 2026-10-04 01:32:38 UTC | `ffc2412f` / G1 | Integrated the reporting tool; independently reran 15 goal tests and 8 historical candidate tests. Both fresh sessions and the reviewed correctness receipt confirm all six B1 LLVM cells. The generated dashboard retains 74 B0 rows and correctly reports goal incomplete. | B1 complete at unchanged production `730a86e6`. B2 equality screens are active; a 64-byte equal-string helper slowdown is being investigated before adoption. Loop candidate selects fitting copies without raising code budgets. |

| 2026-10-04 01:41:43 UTC | Isolated `965d416c` / T1 exploratory | Five-round six-arm equality screen: LLVM small1.2951 and large1.0000; large search1.1017. Paired before/after versus730a86e6 suggests equality0.904/0.350, but search samples contain simultaneous roughly2× spikes in both binaries. Native equal64 helpers also slowed about14–21%. Root verified screen structure/oracles and confirmed paired guest hashes match the six-arm report. | Not adopted; integrated dashboard stays at B0/G1. Repeat quiet15-round controls before attributing search regression to code. Raw [screen](/home/epentland/ai/canopy/mylang-worktrees/goal110-text-20261004/.mylang-cache/goal110-text/equality-screen.json) and [paired data](/home/epentland/ai/canopy/mylang-worktrees/goal110-text-20261004/.mylang-cache/goal110-text/equality-before-after.json) remain separate exploratory evidence. |
| 2026-10-04 01:41:43 UTC | Isolated `5dc31c3a` / independent review `5ccbed8e` | Actual specialization selects10/11 certified values within unchanged byte budgets. Selected/excluded/unknown native outcome checks pass;216 compute checksum cells and432 join executions passed across LLVM and QBE. Independent allocation-failure review passed2 scenarios. LLVM whole-guest text grows3.26% (entry27.56%). | Await focused runtime screen after text quiet interval. No parity claim or accepted production change yet. |

| 2026-10-04 01:53:10 UTC | Isolated `965d416c` / quiet T1 repeat, archive `5777c59a` | Fifteen paired rounds confirm LLVM equality after/before0.9105 (small) and0.3545 (large), but large search1.1589; QBE search0.9930. Checksums pass. No cgroup throttling was recorded; thermal counters still advanced. A search-helper alignment change is observed but not established as the cause. | Keep equality unintegrated. Preserve raw results and investigate against the existing Debug730 control; move timing lane to the loop screen. Join and numeric-sort permutation optimizations remain isolated. |

For future entries, include the affected cases/sizes/backends and before → after
ratios, or say explicitly that the step produced no timing result. Link long
diagnostic notes and raw evidence rather than pasting build logs here.
