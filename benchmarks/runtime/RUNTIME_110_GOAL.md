# Runtime performance goal: LLVM within 1.10×, with QBE tracked

This is the execution plan and live status document for the next performance
campaign. The goal is active. The initial table came from saved measurements; new results
will be added with their own evidence IDs. Update this file in place and retain
the raw evidence for every reported result.

## Status

<!-- STATUS-START -->
- **Campaign:** active. LLVM must reach ≤1.10×; QBE is tracked separately.
- **Last document update:** 2026-10-04 10:27:31 UTC.
- **Integrated source:** `eaf4cda8f5c758cadafaadfa5e328c0fba252ac6` on
  `perf/runtime-parity-20261003`. Checked-index/value reuse is integrated.
- **LLVM status:** **70 open, ten stale, zero current confirmations**.
  The ten previously confirmed G4 cells need reconfirmation after integration;
  their last measured ratio remains 1.0000×. No new target is closed.
- **Latest full-suite measurement:** B0, before this campaign's changes.
  The [live speed table](#live-speed-table) retains each row's evidence and date;
  the [dashboard artifact](candidates/goal110-dashboard-20261004-index.json)
  contains the current integrated state.
- **Latest integrated gain:** repeated LLVM unique-mutation improvements of
  5.2%/5.4% and shared-mutation improvements of 5.1%/1.1% (small/large).
  Unique mutation still measures 1.3576×/1.4381× the fastest runtime;
  shared mutation measures 10.7449×/3.3703×. Other allocated control code is
  unchanged from G4. These results do not close targets.
- **Bounded remainder:** candidate `5e97db47` repeats LLVM filtering gains of
  6.0%/7.4% and a small-sort gain of 5.2%. Its negative-input supplement also
  improves. QBE large nested mutation slows 12%, so this candidate remains
  unintegrated. An LLVM-only successor will retain the LLVM lowering and
  restore QBE's previous lowering, with exact code comparisons required.
- **Text range facts:** candidate `0311796e` repeats a 10% small-equality gain,
  but equality remains about 1.25× the fastest runtime and large search slows
  15.5%. It remains unintegrated. The search loop's instructions are unchanged
  but its placement shifts; the cause is still being investigated.
- **Dictionary lookup:** candidate `64fb7e62` reduces probe-cache writes.
  Four native sanitizer suites, independent source/outcome replay and all
  88 Guardian checks pass. Its pinned Debug compiler and all 24 optimized
  guests are built; 720 qualification and 516 holdout outcomes pass independent
  replay. Actual store removal is independently verified; the seven-case timing
  screen and matched comparison are ready and awaiting a quiet lane.
- **Current activity:** timing is finished and workers are released. Arithmetic archives
  are complete. The LLVM-only successor runs focused tests, text placement
  diagnostic commands are being prepared, and the dictionary screen is ready. Reserve the next ReleaseFast
  compiler rebuild for a promising integrated milestone.
- **Deferred experiments:** bounded equality `3dcbe723` leaves equality above
  target and costs large search; nonnegative remainder `27de73d3` slows signed
  inputs. Their evidence is retained. Neither is integrated.

| Backend | Required targets | Latest observed ≤1.10 | Latest observed >1.10 | Current goal confirmations |
|---|---:|---:|---:|---:|
| MyLang LLVM | 80 | 10 | 70 | 0; ten historical confirmations stale |
| MyLang QBE | 0 (80 tracked) | 3 | 77 | 0; three historical confirmations stale |
<!-- STATUS-END -->

The counts above use the **fastest current configuration in each measured row**.
They differ from the earlier campaign's frozen historical 1.00 targets. G4
reconfirms the eight historical G2 cells and adds large equality and large integer
sorting on the integrated source. Both independent15r/3w sessions cover12 rows;
small equality and small integer sorting remain open. The other68 rows retain
older observations. QBE being above1.10 does not prevent completion.

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
Guardian feedback when a gate is exercised. Prepare and review exact timing
commands before holding other workers; release the hold when guest measurements
finish, so bootstrap analysis and archiving do not delay implementation.

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
| B1 | `mutate_nested`, `bytes_scan`, `string_search` | Confirm existing LLVM wins and establish regression checks | G4 confirmed6/6; stale after index-reuse integrationeaf4cda8 |
| B2 | `string_equal`, `string_join` | Equality/ownership overhead and nearby large-input targets | G4 join/large-equality confirmations now stale; small remains1.3898×. Bounded equality3dc deferred; LLVM result-range0311796e deferred after repeated15.5% large-search cost despite10% small-equality gain |
| B3 | `record_reads`, `record_construct`, `record_update` | Record representation, scalar replacement and transfers | Strict/hybrid scalar-pointer lowering deferred: actual code unchanged; record targets remain open |
| B4 | `call_direct`, `call_indirect`, `option_handle`, `result_propagate` | Calls, inlining, dispatch and return paths | `d14e26f4` speeds direct calls but retains fallback/record regressions; unintegrated |
| B5 | `integer_math`, `float_math`, `branch_predictable`, `branch_mixed` | Scalar lowering and loop invariants | Queued |
| B6 | `list_scan`, `list_append`, `list_filter`, `mutate_unique` | Iteration, capacity and uniqueness | Append/unique gains integrated; remainder27de deferred for negative-input cost, bounded-bias successor repeats LLVM filter/sort gains but a12% QBE nested cost remains under investigation. Index/value reuse14ffa2c0 adopted aseaf4cda8 after repeated LLVM unique gains5.2%/5.4% and unchanged allocated-code controls |
| B7 | `tagged_stack`, `mutate_shared`, `alloc_short`, `alloc_retained` | Ownership, allocation elimination and retained data | Queued |
| B8 | `dict_lookup`, `dict_lookup_str` | Lookup/probe and key costs | [G4 static triage](../../experiments/runtime-goal110-map-audit-20261004/README.md) identifies dynamic layout/cache writes. Probe-cache publication64fb7e62 passes native sanitizer suites/88 Guardian checks; pinned Debug host builds. Typed lookup remains the next hypothesis |
| B9 | `dict_update`, `dict_update_str`, `set_dedup` | Publication, replacement and deduplication | Queued |
| B10 | `binary_search`, `packet_decode` | Bounds, branches and scalar reads | Queued |
| B11 | `sort_int`, `sort_records` | Comparator dispatch and scratch work | G4 large-integer-sort confirmation now stale; small remains1.3925×; record sorting remains open |
| B12 | `string_split`, `int_parse`, `int_format` | Text ownership, parsing and formatting | Parser outline/alignment integrated in textd9; parsing/formatting still above target |
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
| record_reads / small (64) | 3.8071 | **1.0000** | 1.2034 | 1.3815 | 1.2844 | 1.4038 | 2.9913 | O / O | T16-index-screen |
| record_reads / large (4096) | 3.8857 | **1.0000** | 1.2041 | 1.4121 | 1.2350 | 1.4356 | 4.0160 | O / O | T16-index-screen |
| tagged_stack / small (64) | 5.6965 | **1.0000** | 1.0531 | 1.8438 | 1.8624 | 2.9293 | 3.7731 | O / O | T13 |
| tagged_stack / large (4096) | 5.7073 | **1.0000** | 1.0523 | 1.8383 | 1.8592 | 2.9234 | 3.7499 | O / O | T13 |
| mutate_unique / small (64) | 2.9026 | **1.0000** | 1.1507 | 1.2895 | 1.2372 | 1.3576 | 6.7536 | O / O | T16-index-screen |
| mutate_unique / large (1024) | 2.9017 | **1.0000** | 1.1506 | 1.2876 | 1.2364 | 1.4381 | 6.7739 | O / O | T16-index-screen |
| mutate_shared / small (64) | 9.7464 | 1.0487 | 5.5117 | 1.5753 | **1.0000** | 10.7449 | 16.0660 | O / O | T16-index-screen |
| mutate_shared / large (1024) | 65.1761 | **1.0000** | 8.9154 | 2.2502 | 1.7374 | 3.3703 | 4.1422 | O / O | T16-index-screen |
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
| list_append / small (64) | 112.7540 | 1.3635 | 1.9205 | 2.1700 | **1.0000** | 2.3878 | 4.0291 | O / O | T12 |
| list_append / large (4096) | 5316.1692 | 1.0883 | 1.9989 | 2.1341 | **1.0000** | 1.8502 | 3.7854 | O / O | T12 |
| list_filter / small (64) | 139.3599 | 1.0775 | 1.9520 | 1.4605 | **1.0000** | 2.5734 | 4.5527 | O / O | T12 |
| list_filter / large (4096) | 5380.9056 | **1.0000** | 1.9535 | 1.8042 | 1.3147 | 2.3925 | 5.2128 | O / O | T12 |
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
| mutate_nested / small (64) | 743.1072 | 1.5630 | 1.5550 | 1.5835 | 1.4494 | **1.0000** | 1.1819 | S / O | G4 |
| mutate_nested / large (1024) | 7194.4692 | 2.7668 | 2.4057 | 2.7373 | 2.5132 | **1.0000** | 1.1046 | S / O | G4 |
| sort_int / small (64) | 165.2368 | 1.3727 | 6.4191 | 1.6209 | **1.0000** | 1.3925 | 2.5638 | O / O | G4 |
| sort_int / large (4096) | 44151.3168 | 1.4312 | 5.2569 | 1.4696 | 1.0165 | **1.0000** | 1.2146 | S / O | G4 |
| sort_records / small (64) | 534.9452 | 1.1915 | 12.9614 | 1.4126 | **1.0000** | 2.2464 | 2.9003 | O / O | T9 |
| sort_records / large (4096) | 51470.2384 | **1.0000** | 23.3619 | 2.1788 | 1.7380 | 1.2257 | 1.4972 | O / O | T9 |
| lox_eval / small (16) | 738.1632 | **1.0000** | 1.1383 | 2.6921 | 2.6291 | 3.6607 | 4.0643 | O / O | B0 |
| lox_eval / large (256) | 10981.4215 | **1.0000** | 1.1776 | 2.7947 | 2.7405 | 3.6183 | 3.9186 | O / O | B0 |
| bytes_scan / small (64) | 3.4649 | 5.0849 | 6.8839 | 7.9880 | 3.4720 | **1.0000** | 2.3692 | S / O | G4 |
| bytes_scan / large (4096) | 75.3386 | 14.1340 | 13.3834 | 18.8670 | 9.2750 | **1.0000** | 1.0494 | S / S | G4 |
| string_equal / small (64) | 2.9979 | **1.0000** | 1.4842 | 1.3563 | 1.2735 | 1.3898 | 7.2728 | O / O | G4 |
| string_equal / large (4096) | 12.7438 | 2.4308 | 2.9087 | 5.0839 | 3.9540 | **1.0000** | 18.7675 | S / O | G4 |
| string_search / small (64) | 19.5696 | 2.1785 | 1.2547 | 4.5712 | 3.7904 | **1.0000** | 1.2549 | S / O | G4 |
| string_search / large (4096) | 87.5278 | 14.7733 | 7.3155 | 33.9751 | 30.0027 | **1.0000** | 1.0550 | S / S | G4 |
| string_split / small (64) | 557.5921 | **1.0000** | 1.8763 | 1.8560 | 1.7269 | 6.2247 | 8.1218 | O / O | B0 |
| string_split / large (4096) | 28435.3492 | **1.0000** | 2.3570 | 2.1980 | 2.0666 | 7.6152 | 9.7548 | O / O | B0 |
| string_join / small (64) | 162.8626 | 1.3451 | 2.4317 | 1.8955 | 1.6336 | **1.0000** | 1.1664 | S / O | G4 |
| string_join / large (4096) | 5763.9243 | 2.3079 | 4.3569 | 3.0551 | 2.8575 | **1.0000** | 1.0115 | S / S | G4 |
| int_parse / small (64) | 4.4652 | **1.0000** | 5.4083 | 1.2816 | 1.2776 | 2.2302 | 4.0938 | O / O | T14 |
| int_parse / large (4096) | 5.0104 | **1.0000** | 5.3917 | 1.3551 | 1.2539 | 2.2453 | 3.8461 | O / O | T14 |
| int_format / small (64) | 14.7507 | **1.0000** | 1.1094 | 2.7537 | 2.1862 | 3.9779 | 5.8586 | O / O | T14 |
| int_format / large (4096) | 15.0874 | **1.0000** | 1.1681 | 2.8252 | 2.3938 | 3.9588 | 5.8056 | O / O | T14 |
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

| T1 | Unintegrated text source `965d416c`; 5-round screen and 15-round paired control | [Investigation and archives](../../experiments/runtime-goal110-text-20261004/README.md), [quiet paired report](../../experiments/runtime-goal110-text-20261004/equality-quiet15-before-after.json.gz) | Equality improves; large LLVM search and equal64 helper regressions prevent adoption. Matched-host controls retained. No goal confirmations. |
| T2 | Unintegrated loop source `5dc31c3a`; paired five-round selected and fallback screens | [Investigation and archives](../../experiments/runtime-goal110-calls-20261004/README.md), [independent correctness review](../../experiments/runtime-goal110-subset-independent-review-20261004/REVIEW.md) | Rejected for integration: record/fallback LLVM regressions despite QBE gains. No goal confirmations. |

| T3 | Join `5a60ef10`, integrated as `957f97c6`; Debug host, RF guests; 5 rounds/1 warmup | [Raw screen](../../experiments/runtime-goal110-join-20261004/join-screen.json.gz), [observed analysis](candidates/goal110-join-5a60ef10-20261004-observed.json), [paired controls](../../experiments/runtime-goal110-join-20261004/join-before-after.json.gz), [review](../../experiments/runtime-goal110-join-20261004/README.md) | Join small1.05204/large1.000; no material paired control regression. Exploratory observations, no confirmations. |

| T4 | Rejected sorting `2a49da29`; Debug host, six-arm and paired five-round screens | [Complete archive](../../experiments/runtime-goal110-sort-counting-20261004/README.md), [coordinator replay](candidates/goal110-rejected-screens-20261004-0240-review.json) | No material LLVM gain; QBE record-sort regressions. No integrated dashboard rows replaced. |
| T5 | Rejected loop `d14e26f4`; matched Debug-host paired screen | [Complete archive](../../experiments/runtime-goal110-copy-locals-20261004/README.md), [paired raw](../../experiments/runtime-goal110-copy-locals-20261004/regression-screen.json.gz) | Direct calls improve, but fallback and record regressions remain. No integrated dashboard rows replaced. |
| G2 | Integrated join957f97c6; sessions `0a7c22fa-7d2c-49b4-b64f-ffbb4803a5cf` and `653a9088-22ea-4938-b01e-8af53a1346fa`; 02:51:25–02:54:43 and 02:55:34–02:59:02 UTC; RF host,15r/3w each | [Accepted analysis](candidates/goal110-join-957f97c6-rf-20261004-accepted.json), [complete archive](../../experiments/runtime-goal110-integrated-rf-20261004/README.md), [review](candidates/goal110-join-957f97c6-rf-20261004-correctness-review.json), [checks](candidates/goal110-join-957f97c6-rf-20261004-checks.json) | Eight LLVM cells confirmed; latest displayed medians from B. Three QBE confirmations are informational. Full80 goal remains incomplete. |

| T6 | Rejected equality `99a4d071` and untimed precursor `1c367e95`; Debug hosts | [Equality99 archive](../../experiments/runtime-goal110-equality-always-20261004/README.md), [untimed static checks](../../experiments/runtime-goal110-equality-inline-20261004/static-validation.json), [coordinator replay](candidates/goal110-rejected-screens-20261004-0334-review.json) | Large equality improves but small equality does not, and LLVM large search regresses16.3%. No accepted rows change. |

| T7 | Sorting `8043c4d9`, integrated as `63df6b6c`; six-arm5r/1w and paired15r/3w repeat | [Archive](../../experiments/runtime-goal110-sort-rotation-20261004/README.md), [observed analysis](candidates/goal110-sort-8043c4d9-20261004-observed.json), [coordinator review](candidates/goal110-rejected-screens-20261004-0334-review.json) | LLVM small integer sort improves17.6%, still1.3607× fastest. QBE nested-large+11.0% is an explicit tradeoff. No goal confirmations. |

| T8 | Unintegrated parser `52e6d074`; six-arm5r/1w and matched Debug5a paired screen | [Archive](../../experiments/runtime-goal110-int-parse-20261004/README.md), [paired raw](../../experiments/runtime-goal110-int-parse-20261004/parser-before-after.json.gz), [coordinator review](candidates/goal110-parser-52e6d074-20261004-review.json) | Modest parsing gains accompany a16.8% large LLVM search regression. No accepted rows changed. |

| T9 | Readiness `63842d3c`, integrated as `7e7773e4`; six-arm5r/1w plus independent matched15r/3w repeat | [Archive](../../experiments/runtime-goal110-presize-ready-20261004/README.md), [observed analysis](candidates/goal110-readiness-63842d3c-20261004-observed.json), [coordinator review](candidates/goal110-screens-20261004-0438-review.json) | Repeated LLVM small integer sort0.97896 after/before; nested-small1.01061 is accepted and remains fastest. No normal goal confirmation. |
| T10 | Unintegrated scanner alignment `57034382`; six-arm5r/1w and three-artifact matched comparison | [Archive](../../experiments/runtime-goal110-search-align-20261004/README.md), [coordinator review](candidates/goal110-screens-20261004-0438-review.json) | Large search570/5a0.99935 versus52/5a1.16262. General placement restores search in this run; individual-address causality unproven. |

| T11 | Text `d9d6362f`, integrated as `f994742d`; six-arm5r/1w, matched15r/3w repeat,80 medium helper rows | [Archive](../../experiments/runtime-goal110-text-combined-20261004/README.md), [observed analysis](candidates/goal110-combined-d9d6362f-20261004-observed.json), [coordinator review](candidates/goal110-combined-d9d6362f-20261004-review.json) | Large equality0.35592 after/before; small join1.05524 is an explicit cost and reopens its target. Search stable. No normal confirmation. |

| T12 | Append `6910e083`, integrated as `db11bf30`; six-arm 5r/1w and independent matched 15r/3w repeat | [Archive](../../experiments/runtime-goal110-append-range-20261004/README.md), [observed analysis](candidates/goal110-append-6910e083-20261004-observed.json), [coordinator review](candidates/goal110-mutation-append-20261004-review.json) | Repeated LLVM append 0.88833/0.76986 after/before; small filter 1.03905 is an explicit cost. Both append targets remain open. No normal confirmation. |

| T13 | Mutation `d4c28bda`, production delta integrated as `38af69d3`; six-arm 5r/1w and independent matched 15r/3w repeat | [Archive](../../experiments/runtime-goal110-unique-capture-20261004/README.md), [observed analysis](candidates/goal110-mutation-d4c28bda-20261004-observed.json), [coordinator review](candidates/goal110-mutation-append-20261004-review.json) | Repeated LLVM unique mutation 0.95636/0.95397 after/before; QBE large-record-read repeat 1.02502 has a wide interval. No target closed or normal confirmation. |

| T14 | Short join `448ee20c`, integrated as `6cf7bdce`; six-arm 5r/1w and independent matched 15r/3w repeat | [Archive](../../experiments/runtime-goal110-join-short-20261004/README.md), [Observed analysis](candidates/goal110-shortjoin-448ee20c-20261004-observed.json), [coordinator review](candidates/goal110-shortjoin-448ee20c-20261004-review.json) | Repeated LLVM join 0.66360/0.46401 after/before; large search 0.99395. Both join rows are observed fastest; small join recovers provisionally. No normal confirmation. |


| G4 | Integrated`6cf7bdce`; A`620102fe-f182-439c-a8ff-2bbc42b25152`06:37:24–06:42:12 UTC, B`bcc5273b-e669-4cf3-9682-5580ed530ff0`06:42:44–06:47:37 UTC; RF host,15r/3w each | [Accepted analysis](candidates/goal110-g4-6cf7bdce-rf-20261004-accepted.json), [complete archive](../../experiments/runtime-goal110-g4-rf-20261004/README.md), [independent correctness review](candidates/goal110-g4-6cf7bdce-rf-20261004-correctness-review.json), [checks](candidates/goal110-g4-6cf7bdce-rf-20261004-checks.json) | Ten LLVM cells confirmed at1.00 with all paired upper95% comparisons≤1.10 in both sessions. Small equality1.389811 and small integer sort1.392460 remain open. Three QBE confirmations are informational. No full-suite or new full-repository acceptance. |

| T16 | Index reuse `14ffa2c0`, integrated as `eaf4cda8`; six-arm5r/1w and matched15r/3w repeat | [Complete archive](../../experiments/runtime-goal110-index-update-20261004/README.md), [observed speeds](candidates/goal110-index-14ffa2c0-20261004-observed.json), [official correctness/repeat review](candidates/goal110-index-14ffa2c0-20261004-releasefast-review.json), [unchanged control code](candidates/goal110-index-14ffa2c0-20261004-controls-review.json) | LLVM unique after/before0.94814/0.94565; shared0.94881/0.98872. No material measured regression; allocated code for compute/collections/text is identical. Six targets remain open; no normal confirmation. |

| T17 | Unintegrated range annotation `0311796e`; six-arm 5r/1w and independent two-row matched 15r/3w repeat | [Archive](../../experiments/runtime-goal110-floor-result-range-20261004/README.md), [observations](candidates/goal110-floor-result-0311796e-20261004-observed.json), [timing replay](candidates/goal110-arithmetic-candidates-20261004-timing-review.json), [archive review](candidates/goal110-floor-result-0311796e-20261004-archive-review.json) | Small LLVM equality improves 10% but remains 1.2506×; large search slows 15.5%. Caller/helpers retain normalized instructions with changed placement; no causal attribution or target confirmation. |
| T18 | Unintegrated bounded bias `5e97db47`; six-arm 5r/1w, matched four-row 15r/3w repeat and signed supplement | [Archive](../../experiments/runtime-goal110-bounded-rem-20261004/README.md), [observations](candidates/goal110-bounded-rem-5e97db47-20261004-observed.json), [timing replay](candidates/goal110-arithmetic-candidates-20261004-timing-review.json), [archive review](candidates/goal110-bounded-rem-5e97db47-20261004-archive-review.json) | Repeated LLVM filter gains 6.0%/7.4% and small-sort gain 5.2%; QBE nested cost repeats 12%. LLVM-only successor planned. No goal confirmation. |

| D3 | Deferred scalar-pointer sources `a29aa6a9` and `1fdae8e1`; no timing | [Strict proof and incident archive](../../experiments/runtime-goal110-scalar-slots-20261004/README.md), [hybrid archive](../../experiments/runtime-goal110-scalar-addresses-20261004/README.md), [coordinator review](candidates/goal110-screens-20261004-0438-review.json) | Actual optimized code unchanged. Root checked96 raw/archive bindings and identical live hybrid/control ELFs; neither source is integrated. |

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

| 2026-10-04 01:41:43 UTC | Isolated `965d416c` / T1 exploratory | Five-round six-arm equality screen: LLVM small1.2951 and large1.0000; large search1.1017. Paired before/after versus730a86e6 suggests equality0.904/0.350, but search samples contain simultaneous roughly2× spikes in both binaries. Native equal64 helpers also slowed about14–21%. Root verified screen structure/oracles and confirmed paired guest hashes match the six-arm report. | Not adopted; integrated dashboard stays at B0/G1. Repeat quiet15-round controls before attributing search regression to code. Raw [screen](../../experiments/runtime-goal110-text-20261004/equality-screen.json.gz) and [paired data](../../experiments/runtime-goal110-text-20261004/equality-before-after.json.gz) remain separate exploratory evidence. |
| 2026-10-04 01:41:43 UTC | Isolated `5dc31c3a` / independent review `5ccbed8e` | Actual specialization selects10/11 certified values within unchanged byte budgets. Selected/excluded/unknown native outcome checks pass;216 compute checksum cells and432 join executions passed across LLVM and QBE. Independent allocation-failure review passed2 scenarios. LLVM whole-guest text grows3.26% (entry27.56%). | Await focused runtime screen after text quiet interval. No parity claim or accepted production change yet. |

| 2026-10-04 01:53:10 UTC | Isolated `965d416c` / quiet T1 repeat, archive `5777c59a` | Fifteen paired rounds confirm LLVM equality after/before0.9105 (small) and0.3545 (large), but large search1.1589; QBE search0.9930. Checksums pass. No cgroup throttling was recorded; thermal counters still advanced. A search-helper alignment change is observed but not established as the cause. | Keep equality unintegrated. Preserve raw results and investigate against the existing Debug730 control; move timing lane to the loop screen. Join and numeric-sort permutation optimizations remain isolated. |

| 2026-10-04 01:59:08 UTC | Isolated `5dc31c3a` / selected screen + fallback sentinel | Five-round paired LLVM after/before: direct calls0.9099/0.9263, option0.9547/1.0385, result0.9995/1.0377, record update4.0479/4.2583 (small/large). Excluded branch sentinel1.3661/1.6405. QBE improves in all ten cells. Root independently replayed240 outcomes against the compute oracle and recomputed medians; all pass. | Reject this candidate for integration. Correctness and fewer dispatches do not establish LLVM profitability. Agent inspects actual record/fallback loops; builds open for separate join/sorting work. Raw [selected screen](../../experiments/runtime-goal110-calls-20261004/selected-screen.json.gz) and [sentinel](../../experiments/runtime-goal110-calls-20261004/fallback-sentinel.json.gz). |

| 2026-10-04 02:06:41 UTC | Isolated loop diagnosis; join `5a60ef10`; sort `2a49da29` | LLVM translator replay shows selected record addresses lose alias classes when loop copying changes one-definition temporary names to multiple definitions. Safe scoped renaming is in progress. Join has passed native sanitizers and built24 benchmark executables; sort passed32 native suites,46,234 permutations and6 host-failure probes. | No new timing or acceptance yet. Sort compiler build finishes before the next quiet join screen. The integrated branch retains production730a86e6; rejected experiment archives are committed in `b4dc3a15`. |

| 2026-10-04 02:17:02 UTC | Join `5a60ef10` / T3 exploratory, archive `b1021e2b` | Six-arm five-round screen: LLVM join small1.05204, large1.000. Paired Debug730→Debug5a LLVM after/before0.56298/0.55530; QBE0.94280/0.90415. Six equality/search/bytes controls have no material regression. Root replayed192 paired outcomes against the independent oracle and verified all4 live hashes; live expanded verification passed. | Promising, not confirmed. Reporting anchor comparison exposed unnormalized cache/output directory paths; build flags/ISA/reference bytes remain unchanged, and a focused helper fix is in progress. Screen sorting before the next costly RF build; retain all raw results in the [join investigation](../../experiments/runtime-goal110-join-20261004/README.md). |

| 2026-10-04 02:28:09 UTC | Integrated `957f97c6` / T3 | Adopted only the validated join optimization. Root independently passed18 reporting tests, live source/artifact/anchor verification,192 paired outcomes and4 live hashes. Fixed cache-path normalization regenerated B0/G1 analyses under a new checks identity without changing any raw samples or prior receipts. Dashboard now has9 latest observations within1.10 but0 current confirmations after the production change. | Sort screen next; then one RF build and normal independent confirmation. Historical6 G1 confirmations remain visible; no goal completion claimed. |

| 2026-10-04 02:37:20 UTC | Isolated sorting `2a49da29` | Five-round six-arm screen: LLVM record sorting 2.3546 small / 1.2514 large versus current fastest. Paired Debug730→Debug2a LLVM after/before: records 1.05734 / 1.01499, integer sort 1.01658 / 0.99938, nested mutation 0.99836 / 0.98883, append 1.06140 / 0.98900. Record-sort LLVM intervals cross 1; QBE records 1.08249 / 1.02335 with intervals above 1. Native correctness and 720 qualifications passed. | Reject for integration: no material LLVM gain, recorded QBE regressions and a small-append slowdown requiring caution. Preserve raw [six-arm screen](../../experiments/runtime-goal110-sort-counting-20261004/sort-screen.json.gz) and [paired controls](../../experiments/runtime-goal110-sort-counting-20261004/sort-before-after.json.gz); archive `bb0827af` is preserved with 24 independently checked raw/archive hash bindings. Integrated dashboard is unchanged. |

| 2026-10-04 02:40:00 UTC | Isolated loop `d14e26f4` | Five paired rounds: LLVM direct calls improve to 0.7264 / 0.6776 after/before (small/large). Renaming removes the earlier 4× record-copy regression, but record update remains 1.0135 / 1.0658 and predictable-branch fallback 1.1273 / 1.1216. All 144 outcomes pass. Root independently replayed these plus 192 sorting outcomes, checked eight live executable hashes and recomputed all medians/ratios in the [coordinator review](candidates/goal110-rejected-screens-20261004-0240-review.json). | Keep unintegrated; preserve the [paired run](../../experiments/runtime-goal110-copy-locals-20261004/regression-screen.json.gz). Investigate residual fallback/record costs before broader timing. Start the clean ReleaseFast join build at source957f97c6; no new confirmations yet. |

| 2026-10-04 02:51:00 UTC | Integrated join957f97c6 / ReleaseFast build | Official clean compiler build completed in 6m13s, Guardian passed, source/assets verified; compiler SHA871fcc92ebbfc5721c9c1102dce369d36a8828b6e4878dac6058740b8a09086a. All 24 guests built; 128 text checks and 516 fresh nearby-input checks passed. | Start normal eight-row confirmation A then independent B, both15r/3w/all6 arms, covering join plus B1 controls. No new timings or confirmations claimed at launch. All other heavy jobs held. |

| 2026-10-04 02:56:00 UTC | Integrated join957f97c6 / RF session A | Normal15r/3w six-arm run passed720 samples and720 qualifications. LLVM/current-fastest: join1.047461 small (227.532ns versus Rust217.223),1.000 large (12530.122ns); bytes/search/nested mutation1.000 at both sizes. [Raw A](../../experiments/runtime-goal110-integrated-rf-20261004/confirmation-a.json.gz). | Independent B is running on the same artifacts. Bootstrap, coordinator checks and dashboard merge wait until timing finishes; no new C states yet. |

| 2026-10-04 03:10:28 UTC | Integrated join957f97c6 / G2 | Both normal sessions pass720 samples and720 qualifications each. Latest LLVM join1.046350 small /1.000 large; all six B1 controls1.000. All80 per-peer LLVM interval checks across A/B pass, worst upper95=1.053874. Root replayed516 exact-artifact holdouts,120 text oracles,6 refusal records,2 live text artifacts and all24 manifest/source/assets; reviewed applicable native sanitizer checks and13 RF archive bindings. | Confirm8/80 LLVM cells. The one historical sort observation remains unconfirmed and71 cells remain above target. No fresh whole-repository gate or full-suite acceptance is claimed. New candidates remain isolated; next short timing lane waits for their checks. |

| 2026-10-04 03:22:14 UTC | Isolated equality `99a4d071` | Five-round six-arm screen passes240 samples/720 qualifications: LLVM equality1.391574 small/1.000 large; large search1.095649 versus current fastest. Matched Debug5a→99 after/before LLVM equality1.01903/0.35408, join1.03973/0.99703, search1.00382/1.16311, bytes1.02983/1.04399 (small/large). QBE equality0.98305/0.33696; controls0.9878–1.0280. Restored LLVM inlining did not remove the search regression. [Six-arm raw](../../experiments/runtime-goal110-equality-always-20261004/equality-screen.json.gz), [paired raw](../../experiments/runtime-goal110-equality-always-20261004/equality-before-after.json.gz). | Reject99; skip medium-distribution timing because there is no adoption case. Defer equality after several unsuccessful related hypotheses, retain the repeated search interaction as a prerequisite, and investigate independent parsing/formatting or split work. Sorting804 now owns the quiet lane; integrated G2 rows remain unchanged. |

| 2026-10-04 03:25:36 UTC | Isolated sorting `8043c4d9` | Six-arm five-round screen passes240 samples/720 qualifications: LLVM integer sort1.3607 small/1.000 large, records2.2466/1.2157. Matched Debug5a→804 LLVM integer sort0.82234/1.00152 after/before; records1.02547/1.01012; nested0.98910/0.99960; append1.01118/0.99518. QBE integer sort0.87480/0.99385, records1.01316/1.00031, but large nested mutation1.10596 (7843→8674ns; exploratory CI1.07961–1.11767). [Six-arm raw](../../experiments/runtime-goal110-sort-rotation-20261004/six-arm-screen.json.gz), [paired raw](../../experiments/runtime-goal110-sort-rotation-20261004/paired-screen.json.gz). | Keep unintegrated pending an independent15r/3w paired repeat of both sorts/nested mutation. Small integer sorting improves materially but still misses the1.10 goal. QBE's existing gaps are optional, but this new regression needs evidence and an explicit decision. |

| 2026-10-04 03:34:40 UTC | Isolated sorting `8043c4d9` / repeat `5aea9874-b35d-4099-b5b7-fa640e5ccb98` | Independent15r/3w paired repeat confirms LLVM small integer sort0.82396 after/before (268.66→221.36ns; CI0.81992–0.82759), but QBE large nested mutation1.10972 (7880.64→8745.31ns; CI1.09834–1.11763). LLVM large sort1.00468; records1.01978/1.01194; nested0.98644/1.00122. Root independently replayed192 equality outcomes and624 sorting outcomes, checked12 live executable bindings and recomputed medians/ratios in the [review](candidates/goal110-rejected-screens-20261004-0334-review.json). | Keep804 unintegrated and inspect the QBE regression before a tradeoff decision. Timing ended; scalar-slot final-source checks and integer-parser outlining are running. No accepted dashboard rows changed. |

| 2026-10-04 03:39:10 UTC | Isolated scalar slots `a29aa6a9`; integer parser `52e6d074` | Scalar-slot final-source checks pass34 LLVM tests,13 retired-corpus tests and630 native oracle comparisons/1260 calls. Actual LLVM/QBE compute entry machine code remains unchanged; timing skipped. The proof rejects address copies in real scratch uses; transitive uses are being inspected. Parser outline passes4 native-format plus3 shared-grammar tests and its Debug host build; guests are building. Both source commits passGuardian88. Equality99 and untimed1c archives are retained with12+6 independently checked archive bindings. | No performance acceptance. Investigate the scalar proof before another build, screen parsing after actual-frame inspection, and review804's documented QBE tradeoff. |

| 2026-10-04 03:47:10 UTC | Integrated `63df6b6c` / T7 | Adopted rotation804 after repeated LLVM small-sort gain0.82396 and QBE nested-large slowdown1.10972. Root replayed516 holdouts,49 archive bindings and the static comparison:402 named QBE functions, only six sorting bodies changed,2649 nested instructions and96 direct/tail-call routines equivalent after address normalization. Source bytes match804 exactly. | Explicit LLVM-first tradeoff; QBE regression retained and causality unresolved. Latest8-row screen merges into the dashboard; earlier confirmations are stale or superseded by observations. Next parser screen uses isolated52 versus5a; it is not integrated acceptance. |

| 2026-10-04 03:57:20 UTC | Isolated integer parser `52e6d074` | Five-round six-arm screen passes360 samples/720 qualifications: LLVM parsing2.2723/2.2453× current fastest. The matched5a→52 pair passes288 outcomes: parsing0.95216/0.97983 after/before, formatting1.02454/1.04157, CSV0.99477/1.01780, JSON1.00528/1.00116, search1.00481/1.16849 and join1.02304/0.97588 (small/large). QBE parsing0.97307/0.98996 and join0.87108/0.83008. Root independently replayed all288 outcomes/medians and four live hashes; the [review](candidates/goal110-parser-52e6d074-20261004-review.json) retains the result. | Keep52 unintegrated: the modest parsing gain accompanies another16.8% large LLVM search regression. The same blocker now follows an independent parser change, so inspect exact search code/layout before more text iteration. Scalar direct-address mapping and certified list-readiness inlining are in static investigation. Integrated dashboard unchanged. |

| 2026-10-04 04:04:40 UTC | Diagnostic artifact incident | Live hashes caught modified Debug5a compute controls, last written03:44:39. The static inspection used `objcopy --dump-section` without a separate output ELF, which rewrites the input. Only compute controls changed; root verified text, collections and legacy hashes still match. No measured compute run used the modified files. Parser52 review independently passes288 paired outcomes, four live text hashes,360 six-arm samples/720 qualifications and14 archive bindings. | Quarantine the changed compute artifacts; preserve the failure and compare loadable sections before recovering pristine controls into new paths. Existing text/sorting timings remain bound to unchanged bytes. Use read-only disassembly tools or a disposable output ELF. Source optimization work continues. |

| 2026-10-04 04:11:30 UTC | Readiness `63842d3c`; search and scalar diagnostics | Actual LLVM retains13 ordinary readiness calls, including a reachable certified sort-comprehension guard. The candidate chooses the existing hot alias under the identical proof;20 focused tests,53 native ASan/UBSan cases andGuardian88 pass. The empty-list append guard refuses its capacity check, so append is a control, not a claimed direct beneficiary. Parser52 search caller/helper bodies are identical after relocation normalization but move32 bytes modulo64; a scanner-only alignment probe is planned. Disposable objcopy replay confirms ELF-header/section-table rewriting without allocated-section changes. | No new timing or acceptance. Build readiness separately, test scanner alignment as a hypothesis, and recover source-bound compute controls into fresh paths before further scalar diagnosis. Prior mutated files and the incident remain preserved. |

| 2026-10-04 04:18:15 UTC | Static scalar rejection; readiness638 and alignment570 readying | Hybrid direct-address lowering passes37 LLVM tests,12 identical emitted SSA units and108 untimed checks but produces an ELF byte-identical to a fresh accepted-source compute control. No timing/full host rebuild is warranted. Root verified all24 recovered guest hashes,16 external reference hashes and both compute allocated-section/program-header identities in the [recovery review](candidates/goal110-control-recovery-20261004-review.json). Readiness638 passes720 qualifications/516 holdouts; alignment570 passes31,104 native boundary cases and is finishing guest checks. | Defer scalar-pointer optimization and preserve its incident/negative evidence. Screen readiness first, then alignment; scanner, caller and index-walker placements all change, so the alignment experiment cannot isolate one address change. No accepted rows changed. |

| 2026-10-04 04:29:00 UTC | Readiness638 timing; scalar archives | User scope remains LLVM required and QBE tracked separately. Readiness638 starts its prepared all-six-arm5r/1w screen and matched804 control; alignment570 is qualified and queued next. Scalar source candidates remain unintegrated; evidence commit `1d02c3dc` preserves identical-machine-code results and the control-artifact incident. | Quiet timing: all builds/tests/commits held. No new timing or acceptance claimed at launch. |

| 2026-10-04 04:32:10 UTC | Isolated readiness `63842d3c` | Six-arm5r/1w screen passes240 samples/720 qualifications: LLVM integer sort1.34017 small/1.01248 large; records2.24642/1.22575; nested1/1; append2.67919/2.40716. Matched804→638 paired LLVM small integer sort0.97997 after/before (220.57→216.15ns; CI0.97086–0.98565), large0.99381; records0.99306/0.95377, nested1.01162/0.99572, append0.99592/1.00111. QBE ratios range0.99597–1.00457. | Modest candidate, not adopted or confirmed. Repeat the targeted gain and nested controls after alignment570, which now owns the quiet lane. All raw results remain in the isolated readiness worktree pending archive. |

| 2026-10-04 04:37:00 UTC | Isolated alignment `57034382` | Six-arm screen passes360 samples/720 qualifications; the matched5a/52/570 comparison passes432 outcomes. LLVM570/5a search0.99985/0.99935, join1.00933/0.97845, bytes0.99456/0.97128, equality1.00173/0.99986, parse0.98141/0.98792, format0.96596/0.96944. Large search570/52 is0.85957 while52/5a is1.16262 in the same run. QBE570/5a ranges0.93467–1.03000. | General alignment change recovers search in this session; scanner-only causality remains unproven. Prepare combined equality/parser/alignment source after quiet readiness repeat. No production integration or target confirmations yet. |

| 2026-10-04 04:44:10 UTC | Integrated `7e7773e4` / T9 | Independent15r/3w repeat confirms LLVM small integer sort0.97896 after/before (219.87→215.24ns; CI0.97644–0.98317), nested-small1.01061 (714.87→722.45ns; CI1.00732–1.01435), nested-large0.98074. QBE intervals cross1 in all three cells. Root replayed840 paired outcomes,14 live executable bindings, both six-arm reports (600 samples/1440 qualifications),96 scalar archive bindings and33 alignment archive bindings. | Adopt readiness with the explicit1.1% nested-small cost, retaining its leading ratio. Source bytes match638. Dashboard updates eight observed rows; all80 targets still need current-source acceptance. Combined text now starts from7e and uses638 as its matched control. |

| 2026-10-04 04:49:12 UTC | Combined text `d9d6362f`; duplicate-check proof | Combined parser/equality/alignment source starts from accepted7e. Five native sanitizer suites,4 native-format tests,3 shared-grammar tests and the official Debug compiler build pass; compiler SHAc394761eedf98cb5ebbbe94c14ba0b118c479fec521158ff7905ba0b960a39f2. Its24 guest builds are in progress. Mutation proof now also refuses producer checks covered by an existing hoist, preserving the first check explicitly. | No new timing. Qualify fresh guests, inspect actual code and then coordinate the next quiet screen. Main evidence/dashboard commit1684aa4e and required Guardian feedbackd0155d3 are complete. |

| 2026-10-04 04:53:11 UTC | Combined text `d9d6362f` starts timing | All24 guests built and all candidate/accepted638 identities verified. Fresh400 text records include384 outcomes,12 refusal probes and4 artifact records. Its LLVM equality wrapper is inlined; scanner/index instructions are unchanged, while kernel code grows2151 bytes. Duplicate uniqueness prototype passes16 focused tests and removes two actual runtime-check sites in a diagnostic LLVM guest. | Combined text owns the quiet lane: six-arm screen, matched638 pairs and conditional medium-distribution helper check. All other builds/tests/commits held. No new timing claimed at launch. |

| 2026-10-04 04:58:39 UTC | Combined text `d9d6362f` exploratory screen | Six-arm5r/1w passes360 samples/720 qualifications. Matched638→d9 screen passes288 outcomes: LLVM large equality0.35675 after/before, small equality1.02280, large search0.99817, small join1.04868 and large join0.99038. Small join is1.118284× current fastest in the six-arm screen, so it is above target despite the equality gain. | Independent15r/3w paired repeat of small join, large equality and large search is running with unchanged artifacts. Native medium-distribution timing is deferred until the tradeoff is assessed. No adoption or normal confirmation yet. |

| 2026-10-04 05:05:47 UTC | Combined text `d9d6362f` repeat and medium diagnostics | Independent15r/3w repeat: LLVM large equality0.35592 after/before (CI0.35440–0.35735), large search1.00471 (CI0.99746–1.01279), small join1.05524 (226.78→239.30ns; CI1.04842–1.05945). QBE equality0.33786, search1.00068, small join1.04254. Native80 medium rows range0.92782–1.04779. Root replayed504 paired outcomes, six-arm360samples/720qualifications and the full80-row helper grid/medians/live binaries. | Preserve the small-join regression and above1.10 screen result. Inspect its actual code before explicit tradeoff adoption. Timing ended05:01:35; builds/tests resumed for mutation and arithmetic-only append versions. Native helper checksums were asserted during execution but are not retained per sample; these helper rows are exploratory, not goal acceptance. |

| 2026-10-04 05:11:39 UTC | Native test argument audit | Found that `qbe_loop_unswitch_test.sameInputOutcome` passes numeric argv without the runtime-options delimiter and can compare matching option failures. A separate test-only fix adds the delimiter and explicit successful results. Root independently verified the historical432-execution matrix uses direct subprocess argv, then replayed144 saved oracle cases (138 successes/6 division failures); its evidence and direct benchmark timings are unaffected. The prior independent review now has an appended correction. | Preserve original receipts and the [coverage review](candidates/goal110-argv-coverage-20261004-review.json). New mutation tests pass19 focused checks with explicit real guest outputs after correcting the same delimiter mistake; a test-layout Guardian finding is being corrected before its source pin. No new timing or target acceptance. |

| 2026-10-04 05:17:36 UTC | Integrated `f994742d` / T11 | Accepted the general bounded equality, separated floating-parser frame and aligned scanner combination. Repeat LLVM large equality0.35592 accompanies small join1.05524; search1.00471. Root verified source equivalence to d9,504 paired outcomes,360 samples/720 qualifications,80 medium-helper rows,43 raw/archive plus13 static bindings, and independently replayed identical native join/score bodies. The caller changes code/placement without frame or stack-reference count growth. | Explicit tradeoff: retain64.4% large-equality gain and reopen small join at1.118284× current fastest. Dashboard nowO70/P9/R1 for LLVM, with0 current confirmations. No goal completion, RF acceptance or causal placement explanation claimed. Root production Guardian88 passed; mutation/append work continues. |

| 2026-10-04 05:31:00 UTC | Mutation/append source pins and argv fix | Mutation `d4c28bda` combines the uniqueness proof with accepted readiness, passing24 focused and14 affected readiness tests. Append `6910e083` passes27 focused tests, including exact native growth/overflow/refusal outcomes and frozen-project emission. Both official source-bound Debug hosts are built; native differentials and fresh guests continue against unchanged638 controls. The separate guest-argv test correction `61e9bd6f` is integrated as `dfcb900b`; its23-test differential batch and explicit successful fold oracle pass. | No new timing or target confirmations. Production optimizations remain isolated pending actual-code and paired screens. Limited review of the two other argument-forwarding environment helpers confirms their callers intentionally pass runtime options, so they do not need the guest delimiter. |

| 2026-10-04 05:38:53 UTC | Append/mutation quiet timing begins | Root independently replays append720 qualification checks,11 exact native pairs,24 guest hashes/16 frozen references/15 assets and2617 source bindings; holdout verifier passes516. Mutation replay checks872 native pairs (644 successful,224 semantic errors,4 budget refusals),1744 recorded executions and14 live guests. Actual mutation legacy LLVM unique calls18→16 and entry16041→15796bytes; QBE18→16 and50516→50148bytes. Append LLVM removes repeated scalar overflow work and retains ordinary growth. | Append owns the quiet lane, mutation follows; both use four cases at both sizes, six arms5r/1w and matched638 pairs. No timing result at launch. Source-only short-join specialization hoists separator classification under the existing16-byte policy; its tests/build wait until timing ends. Required Guardian feedback is committed as `fc0c6e9`. |

| 2026-10-04 05:41:52 UTC | Append `6910e083` first exploratory result | Six-arm05:38:56–05:39:45 passes240 samples/720 qualifications. Matched638→6910 session `4d1c67cf-48ef-445f-ada7-66062f1a191b` passes192 outcomes: LLVM append0.88887/0.77683 after/before, filter1.03956/0.99653, sort1.00750/1.00810, nested0.98720/0.98971. QBE append0.92885/0.96880; other controls0.93867–1.03212. Six-arm LLVM append remains2.38780/1.85022× current fastest; sort large1.01076, nested1/1. | Not adopted or confirmed. Mutation now owns the quiet lane. Repeat both append sizes and small-filter control15r/3w after mutation. Raw evidence is in the isolated collections-hot worktree under `.mylang-cache/goal110-append-range-review/`; archive and independent timing replay wait until the quiet window ends. |

| 2026-10-04 05:46:26 UTC | Mutation `d4c28bda` exploratory result | Six-arm screen 05:41:45–05:42:47 passes 240 samples/720 qualifications. Matched 638→d4 comparison passes 192 outcomes: LLVM unique 0.95408/0.97523 after/before, shared 0.98794/0.99466, record reads 1.00176/0.99564 and tagged stack 1.00141/0.99896. QBE unique 0.99570/0.99504; large record reads 1.09353 with wide interval [0.98550,1.23690]. LLVM/current-fastest unique remains 1.444/1.455. | No adoption or confirmation. Append owns its three-row 15r/3w repeat; mutation then repeats unique small/large and large record reads. Source and artifacts remain unchanged. Raw screen/pair SHA d1fd0995…/b7a07dd5… are retained under `experiments/runtime-goal110-unique-capture-20261004/`; archive and independent timing replay follow the quiet window. |

| 2026-10-04 05:54:27 UTC | Integrated append `db11bf30` and mutation `38af69d3` | Independent 15r/3w append repeat: LLVM small 301.404→267.745ns (0.88833, CI0.88640–0.89233), large 12899.634→9930.942ns (0.76986, CI0.76429–0.77310); small filter 346.008→359.521ns (1.03905, CI1.02700–1.04217). Mutation repeat: LLVM unique 0.95636/0.95397 after/before; QBE large record reads 1.02502, CI0.95752–1.09906. Root verifies 816 timing outcomes, exact oracles/medians/ratios/plans/live binaries and independent repeat intervals; both six-arm analyses pass artifact validation. | Adopt both changes, explicitly retaining the 3.9% small-filter cost and QBE uncertainty. No new target is closed and no normal confirmation is claimed. All timing ended 05:48:18; archives and short-join checks are released. Short-join source `448ee20c` passes five optimized native sanitizer suites including 684 mixed-width joins; its Debug host is building. |

| 2026-10-04 06:01:55 UTC | Short-join `448ee20c` quiet screen starts | Source and Debug host gates pass 88 checks; five optimized sanitizer suites include 684 new mixed-width joins. All24 guests and400 text records pass. The new1605-byte short helper has zero calls on LLVM/QBE; LLVM has no stack-memory references. Public join grows1229→1352 bytes; mixed fallback retains its bulk copies. Scanner/index/kernel normalized code matches d9, with entry shifts of64 bytes. | Six text cases at both sizes, all six arms5r/1w, then matched d9 pairs. No timing result at launch. Other heavy work is held. Append/mutation evidence is committed as `a34c41c4`; mandatory Guardian feedback is committed as `f92827d`. |

| 2026-10-04 06:07:01 UTC | Short-join `448ee20c` exploratory result | Six-arm session `d4cdb9de-8914-401b-ba4c-6c4fc4f56f8d` passes360 samples/720 qualifications: LLVM join168.049/5827.498ns is current fastest at both sizes. Matched d9→448 pairs pass288 outcomes: LLVM join243.025→161.998ns small (0.666589),12360.904→5757.473ns large (0.465781); QBE0.646823/0.436828. All LLVM controls lie0.98973–1.00795 and QBE controls0.98426–1.00736. | Promising, not yet adopted or confirmed. Independent15r/3w repeat of both join sizes and large search is authorized with unchanged artifacts. Quiet lane continues. Native correctness includes bounded views and mixed/bulk fallback; no broader input-distribution timing is claimed. |

| 2026-10-04 06:12:03 UTC | Integrated short-join `6cf7bdce` | Independent15r/3w repeat passes216 outcomes: LLVM join237.874→157.853ns small (0.66360, root CI0.66048–0.66949),12240.259→5679.631ns large (0.46401, CI0.45692–0.46924); large search0.99395 (CI0.98646–1.00134). QBE join0.65052/0.46066, search0.99307. Root replays504 paired outcomes, exact oracles/medians/ratios/plans/live hashes; six-arm analysis passes artifact validation. | Adopt the general short-copy path; small join is now observed below1.10, but no integrated normal confirmation is claimed. Production gate88 passes. Fresh RF milestone from6cf covers12 rows in two normal sessions; new nonnegative-remainder implementation will use a separate worktree and cannot change this pin. |

| 2026-10-04 06:18:18 UTC | G4 integrated ReleaseFast build | Short-join archive `84092ce0` includes45 raw/archive bindings,6 helper bindings and2 native-check bindings, independently verified by root. Root also replays384 saved text checksum oracles,12 recorded refusals and4 live text/sidecar identities. Current dashboard is LLVM O70/P10, QBE O77/P3; there are0 current confirmations. | Fresh `goal110-g4-rf-20261004` builds exact production `6cf7bdce` with an official ReleaseFast host and private caches. Final-pin focused append/unique/readiness tests,24 guests and qualification precede two normal12-row sessions. New remainder work is isolated. No new normal timing result yet. |

| 2026-10-04 06:23:11 UTC | G4 ReleaseFast compiler complete | Official build from `6cf7bdce` ran06:15:02–06:21:06 UTC and exited0. Compiler SHA `6d284b91b0ca95b566f38ea5a2e6d914b56d9c0c75694310773065d3cc0f5e4f`; its receipt is in `goal110-g4-rf-20261004/.mylang-cache/goal110-g4-rf/compiler-receipt.json`. Short-join evidence/dashboard commit is `3ac28084`; Guardian feedback is `4709c1f`. | Build/qualify fresh guests and run focused integrated semantic tests before normal timing. Separate nonnegative-remainder work is implementing a guarded proof; mutation follow-up is still auditing exact index/value reuse. Neither can change the G4 source or artifacts. No new normal timing result. |

| 2026-10-04 06:39:00 UTC | G4 normal A/B starts | Exact `6cf7bdce` ReleaseFast compiler SHA `6d284b91b0ca95b566f38ea5a2e6d914b56d9c0c75694310773065d3cc0f5e4f`; manifest SHA `4757812159060d11f035115d40fbf94e894bc08030e961fa7c2fdd8d955f4479`. All24 guests,200 text records,516 holdouts and42 focused tests pass. A starts06:37:24.885692 UTC; B uses the same artifacts. | Join, bytes, search, equality, integer sort and nested mutation at both sizes; six arms15r/3w. All other builds/tests/commits and heavy analysis are held. No timing result or current confirmation is claimed yet. |

| 2026-10-04 06:43:30 UTC | G4 session A passes; B running | A session `620102fe-f182-439c-a8ff-2bbc42b25152`,06:37:24.921179–06:42:12.780228 UTC, passes1080 samples/720 qualifications. LLVM has the fastest median on10/12 rows; small equality1.389721 and small integer sort1.382696 remain open. Source/compiler/guest hashes are unchanged before/after. | B starts06:42:44.803823 UTC with the same artifacts. Results are provisional until independent B and paired uncertainty analysis. Quiet timing hold continues. No normal confirmation is claimed yet. |

| 2026-10-04 06:50:30 UTC | G4 A/B complete; acceptance review | B session `bcc5273b-e669-4cf3-9682-5580ed530ff0`,06:42:44.840921–06:47:37.984776 UTC, passes1080 samples/720 qualifications, matching A identities. LLVM is fastest on the same ten rows; small equality1.389811 and small integer sort1.392460 remain open. B QBE large nested mutation is1.104603 relative to current fastest, above its informational target. | All timing is complete; artifact archiving and root uncertainty/correctness review are released. Candidate agents resume focused tests, with no official host or new timing yet. No current confirmed count is asserted until review finishes. |

| 2026-10-04 07:02:14 UTC | G4 ten LLVM cells confirmed | Root independently replays1440 qualification outcomes,516 holdouts,192 text oracles,6 recorded refusal codes,2 text identities,11 exact native pairs and42 focused test results; validates2619 source,15 installed-asset,24 guest and16 frozen-reference bindings. Prior five optimized C sanitizer suites match114 source files; their684 mixed-width joins are reused source checks, not fresh RF executions. Normal A/B analysis passes all100 LLVM peer comparisons for the ten winning cells (self comparisons excluded). | Dashboard becomes LLVM C10/O70, QBE C3/O77. Archive35917617 is integrated as evidence only; source remains6cf. Remainder073e450b passes56 units/88 Guardian checks and root replays32 exact native outcomes; its RF build is authorized. Index-update tests remain incomplete; no candidate adoption or new timing yet. |

| 2026-10-04 07:12:40 UTC | Remainder LLVM policy gap caught before timing | Source073e450b RF host and all24 guests build;720 qualification and516 holdout outcomes pass. Actual QBE fast code consumes the sign proof, but LLVM still emits its signed multiply/shift/floor-correction path because the new recipe flag was wired only into QBE policy. No timing was run. | Retain073e artifacts as an untimed precursor. Add a narrowly certified positive-literal i64 unsigned-remainder lowering for LLVM, explicit policy tests, and a new pinned build before timing. Current integrated source remains6cf and G4 C10 is unaffected. G4 milestonebef79c46 and Guardian feedback815fc3e are committed. |

| 2026-10-04 07:21:31 UTC | Next candidates checked before official timing | Corrected remainder draft emits LLVM urem in the guarded copy and srem in fallback;59 focused tests plus13 translation-test results pass (12 are imported unnamed tests). Its nine new native pairs execute LLVM scalar-policy IL through QBE and are explicitly labeled; actual LLVM successor artifacts still need rebuilding. Index-update candidate passes23 units and exact same-policy counting/sites comparisons on LLVM/QBE, but the frozen mutation entry has no hits; its floor-rem opcode is a concrete unhandled candidate. | Text standalone bounded17..64 comparator passes optimized sanitizer coverage including90,048 Unicode outcomes and emits vector head/tail comparisons. Its80-row matched native screen is authorized after source gate/pin; other heavy work is held. No new optimization is integrated, and G4 C10 remains current. |

| 2026-10-04 07:36:09 UTC | Bounded equality `3dcbe723` native screen | Session b5337f29-9dbc-4dcd-bb44-a50c8db08718 completed80 rows,5 paired rounds/1 warmup in34.23s. Root independently verifies every pilot/warmup/timed checksum, status and stderr. Affected17..64 ratios range0.60920–0.87081; negative controls65..4096 range0.9850–1.05339, with128-byte owned ASCII middle mismatch the largest cost. | Authorize a fresh officialRF host and actual guest-code review. The >5% control needs an independent repeat. Final corrected-remainder and modulo-shaped index-update checks resume; no source integration or new goal confirmation. |

For future entries, include the affected cases/sizes/backends and before → after
ratios, or say explicitly that the step produced no timing result. Link long
diagnostic notes and raw evidence rather than pasting build logs here.


| 2026-10-04 07:41:28 UTC | Corrected remainder `27de73d3` pinned | Final59 focused results and whole-tree88 source/commit gates pass. Root independently replays41 complete accounted/unaccounted pairs (32success/9failure), including9 LLVM-scalar-policy pairs executed throughQBE. Real LLVM translation contains unsigned remainder in the admitted copy and signed remainder in fallback. [Independent replay](candidates/goal110-remainder-27de73d3-20261004-native-review.json). | Fresh successorRF host is authorized in a separate worktree;073 artifacts remain intact. Require actual LLVM boundary executions and signed-input performance checks before adoption. Index-update24 tests pass but no real benchmark hit yet; diagnostics remain isolated. |


| 2026-10-04 07:44:40 UTC | Mutation diagnostic attribution correction | The new focused build installed its compiler under `zig-out/focus/focus/mylang`, but the diagnostic read the old `zig-out/focus/mylang`. Withdraw the new floor-stage/no-hit conclusion and final-source counting attribution; compiled24/13 unit results remain valid. Earlier four same-policy pairs retain only their recorded earlier-source attribution. | Preserve wrong-host receipts. Require exact resolved executable/source bindings and an expected-marker control before redoing actual frozen-port diagnostics. No official mutation host or timing was run. EqualityRF host completes successfully; its24 guests are building. |


| 2026-10-04 07:48:35 UTC | Corrected mutation diagnostic and native equality replay | The correctly resolved diagnostic compiler emits two checked-index rewrite sites in frozen ports (shared/unique writes); the following unique read is refused because checksum already occupies a plain scalar stack slot. Root approves a separately proved following-read scalar prefix without weakening existing token-deletion admission. Root independently replays all1,282 equality helper processes and3 raw archive bindings,10 helper bindings and native source bindings. [Equality replay](candidates/goal110-bounded-3dcbe723-20261004-native-review.json). | Finish exact clean-host attribution, then test the narrow prefix change. Equality and corrected-remainder official guests/qualification remain pending. No new source integration, timing or goal confirmation. |


| 2026-10-04 07:54:46 UTC | Official candidate builds complete | Bounded equality RF host/24 guests pass, with fresh200 text checks and516 holdouts. ActualLLVM uses XMM/YMM bounded comparisons; shared text function grows1533bytes and frame16bytes. Corrected remainderRF host/24 guests also pass;720 qualification/516 holdouts are finishing, with actualLLVM boundary and supplementary builds deferred. | Text and mutation agents are idle; root awaits the remaining qualification idle boundary before serial native-repeat/six-arm/paired text timing. No new candidate adopted or target confirmed. |


| 2026-10-04 08:01:56 UTC | Bounded equality RF screen remains open | Native8-row15r/3w repeat816622cb passes;64 equal ratios0.74216/0.82313 and middle0.70946/0.74409 (ownedASCII/viewUTF), with128 middle costs1.04684/1.02434. Six-arm sessiona8ccda6c passes360samples/720qualifications: LLVM small equality4.02140ns,1.35326× fastest2.97164; large12.71250ns is fastest. | MatchedG4 comparison is running in the quiet lane. Native helper gains do not directly establish guest gains. No adoption or new confirmation; normal integrated dashboard remainsG4 C10/O70. Next audit will separate actual comparison from checksum/loop overhead. |


| 2026-10-04 08:11:46 UTC | Text tradeoff and remainder timing readiness | MatchedG4→3dc session0ac7f30e passes288outcomes: LLVM small equality0.963449 and large equality1.005119, but large search1.056424. Root replays all288statuses/checksums/livehashes and the six-arm artifact analysis passes. Remainder27de passes nine actualLLVM boundary pairs/18executions; root independently verifies5success/4failure, full outcomes and LLVM-O3/fullLTO guest identities. [LLVM boundary replay](candidates/goal110-remainder-27de73d3-20261004-actual-llvm-review.json). | Keep textcandidateunintegrated pending repeat. Remainder actualELF15→7instruction change and supplementaryguestbuilds are ready for timing. Mutation emits exacthook PCs759/841/859/866;30semanticresults pass, but resource-bound splitreruns/finalgate are pending. Current integrated source remains6cf andC10/O70. |


| 2026-10-04 08:24:02 UTC | Remainder negative-input blocker and text repeat | Remainder six-armcdad3663 passes240samples/720qualifications; matched214afcd5 passes192outcomes. LLVM ratios small/large: append0.9905/0.9948, filter0.9376/0.9194, sort0.8688/0.9760, nested0.9829/0.9935. Supplementfc3b2e26 passes96outcomes; negative LLVM1.0686/1.1201 and QBE1.1606/1.2680, while positive LLVM0.9617/0.8585. Text15r/3w repeat9583c652 passes144outcomes: small equalityLLVM0.96831/QBE0.71952, large searchLLVM1.03520/QBE1.00467. | Both candidates stay unintegrated pending review. Retain all initial costs and calibration caps. Plan to preserve the old optimized signed path rather than accept the negative slowdown. Text range-fact work is an isolated IR experiment; no new production behavior or goal confirmation. Source remains6cf and dashboardC10/O70. |

| 2026-10-04 08:35:00 UTC | Candidate archives reviewed; signed-range follow-up | Root checks 140 compressed/raw/live-file bindings and 22 metadata bindings, then independently replays 720 paired outcomes and medians across the initial text comparison, repeat, frozen remainder rows and signed supplement. The supplement uses an independent residue-sum oracle. [Archive review](candidates/goal110-candidate-archives-20261004-0835-review.json). Text archives32b/7e2d and remainder945f retain the measured costs and refusal history. Mutation split groups pass30 unique tests within unchanged bounds; Guardian88 passes. | Keep3dc/27de unintegrated. Fresh bounded-bias work preserves the old signed fast-loop admission; isolated LLVM range assumptions remove checksum correction in a synthetic experiment, with production interface review pending. No new measured result or goal confirmation; integrated source6cf/C10 remains current. |

| 2026-10-04 08:45:10 UTC | Mutation14ffa2c0 ready for official build; LLVM range experiment passes | Root independently checks106 successful and30 failing actual QBE/LLVM pairs, two detach allocation refusals and four identical accounting pairs, with full streams and source/artifact bindings. All30 unique focused tests pass within unchanged bounds. [Mutation review](candidates/goal110-index-update-20261004-native-review.json). Actual LLVM mutation entry shrinks16825→16365 bytes, removing repeated write-index checks and the following value reload while retaining first-read checks and COW. Root separately verifies127 raw/6metadata bindings and27452 saved IR outcomes, including1400 overflow statuses. [IR review](candidates/goal110-floor-range-ir-20261004-review.json). | A fresh14ffa2c0 ReleaseFast host is building; timing follows24guest builds and qualification. Fresh6cf-based bounded-bias and final-result annotation implementations are isolated. Source integration and G4 confirmations remain unchanged; no new benchmark timing result. |


| 2026-10-04 08:54:06 UTC | Index-reuse official compiler complete | Fresh14ffa2c0 ReleaseFast host completed08:45:34–08:51:48 UTC, exit0, source/assets unchanged and Guardian88 passed. Compiler SHA59c98b1c06dd1815809528c2e4e88e713deeeb4ad42418dc38f33d41585574cf; receipt29ad2a6fefbb1d2d579ad0dbdf60a1e446d91416a115b99e1e723d191c1863f4. | All24 guests,720 qualification cells,516 holdouts and final official-host behavior checks precede a six-row screen of unique/shared mutation and record reads at both sizes. No timing started. Arithmetic candidates remain isolated; integrated6cf/G4 C10 unchanged. |


| 2026-10-04 09:05:05 UTC | Index-reuse six-row exploratory timing starts | Exact14ffa2c0 RF manifest e02fd8476ee7b36d04e74a46287dcdbcc0fade79156f40b4e0de2d9e6674a171 passes24guest/source bindings,720qualifications and516holdouts. Root verified2621source/15installed-asset host bindings and reviewed timingcommands1ebd0784/8helper identities. Six-arm5r/1w run starts with driver83a60a10; a same-plan G4 comparison follows. | Both implementation agents are idle under HOLD. No builds/tests/Guardian/commits or heavy analysis during measurement. Bounded-bias52 focused results and range-annotation18 results pass but remain unpinned/untimed; no new goal confirmation. |


| 2026-10-04 09:15:00 UTC | Index-reuse initial screen complete; independent repeat starts | Six-arm5r/1w yields180 measured samples/720 qualifications. Matched sessionf6e54af4 passes144 outcomes: LLVM unique0.94934/0.94800, shared0.94952/0.98579, record reads0.98810/0.98611 after/before (small/large). Large-unique upper95 crosses1; QBE large-record interval is wide. All six required LLVM targets remain above1.10. | Start independent15r/3w on unchanged6plans/4before-after arms, command SHA368f460d. This is adoption evidence, not normal goal confirmation. Quiet HOLD remains until guest timing ends; integrated6cf andG4 C10/O70 are unchanged. |


| 2026-10-04 09:19:30 UTC | Index-reuse independent repeat complete | Repeat15r/3w retains the exact initial6plans/4arms and passes432 outcomes. LLVM large unique0.94565 (95% interval0.93582–0.95770), shared0.94881/0.98872, records0.98641/0.99172; QBE records1.00183/0.99678 and large-record upper95=1.02826. | Release build/test hold. Root independently replays official native/GC/accounting outcomes and both paired sessions; preserve the archive. Check prior-pass control code or measure a nested-mutation sentinel before adoption. Source remains6cf, no new goal confirmation. |


| 2026-10-04 09:27:00 UTC | Index reuse integrated aseaf4cda8 / T16 | Exact8-file production source14ffa2c0 is cherry-picked with no source delta. Root replay passes150 official process pairs,720 qualifications,516 holdouts and576 paired outcomes. Independent ELF parsing confirms allocated sections/program headers/executable LOADs unchanged for compute/collections/text on both backends; only mapped section-header-table offsets differ. [Control review](candidates/goal110-index-14ffa2c0-20261004-controls-review.json). | Adopt repeated LLVM unique gains5.2%/5.4%; no new target closes. New dashboard isLLVM O70/S10, QBE O77/S3. Prior G4 confirmations are stale until normal integrated recheck. Arithmetic candidates stay isolated; no additional timing or whole-repository acceptance. |


| 2026-10-04 09:31:30 UTC | Mutation archive1b8ab336 and bounded-bias5e97db47 reviewed | Root verifies all85 exact committed archive files,1894 raw/member bindings and1893 live origins. [Archive review](candidates/goal110-index-14ffa2c0-20261004-archive-review.json). Bounded-bias final source57 tests/88 Guardian checks pass; root checks11 source/8 log bindings and49 complete native pairs, including38 new bias pairs and11 append controls. [Source review](candidates/goal110-bounded-rem-5e97db47-20261004-source-review.json). Four LLVM-policy pairs execute throughQBE; actual LLVM ELF checks remain pending. | Preserve measured mutation gain and sourceeaf4. Bounded-bias Debug host builds; annotation0311796e actual LLVM checks run. Dictionary follow-up starts fromeaf4 in a new worktree. No new timing or goal confirmation. |


| 2026-10-04 09:35:30 UTC | Evidence checkpointd9810f25; arithmetic native proof | Mutation archive/dashboard commit passes whole-tree88 Guardian checks; mandatory feedback committed as355509f inGuardian. Bounded-bias5e97 Debug compiler SHA46e2d49b is validated and guests build. Annotation0311796e Debug compiler SHAe29567b2 emits19 LLVM range assumptions in the real text kernel; equality checksum loses seven instructions, while a recursive signed control retains correction and checked-subtraction failure. | Actual native policy/boundary checks precede timing; no performance gain claimed from instruction count alone. Fresh dictionary treegoal110-dict-read-20261004 starts one narrow cache-field publication change, independently of typed lookup. Sourceeaf4 andLLVM O70/S10 unchanged. |


| 2026-10-04 09:41:00 UTC | Annotation0311796e actual native replay passes | Root independently verifies2763 paired native outcomes/5526 executions across7 policies,14 ELF/sidecar identities and both compiler source bindings. Closed-form arithmetic oracles confirm2604 successes,70 overflow,70 division-by-zero,7 startup-memory,6 step-limit and6 frame-limit pairs. [Native replay](candidates/goal110-floor-result-0311796e-20261004-native-review.json). All200 diagnostic text records are ordinary oracle outcomes, not a192+6+2 mixed receipt. | Finish final guest/code bindings and prepare exploratory text timing. Bounded-bias real LLVM wide-unsigned-bias and exact-magnitude endpoint checks run separately from the12 standard pairs. Dictionary candidate changes only ordinary found-cache publication; tests pending. No new speed or confirmation. |


| 2026-10-04 09:43:00 UTC | Annotation assembly-count correction | Precise code proof counts equality arithmetic17→11 instructions, or20→14 including loop inc/cmp/je. The earlier seven-instruction estimate is superseded by six removed arithmetic instructions. Root separately replays all200 ordinary text records with independent registry oracles and exact helper/live-guest bindings. [Text replay](candidates/goal110-floor-result-0311796e-20261004-text-review.json). | Final24guest runner is building with16 frozen foreign references. Recheck final text artifact against the diagnostic proof before timing; no speed claim yet. |


| 2026-10-04 09:49:30 UTC | Annotation quiet screen START approved | Root verifies final24guest manifest409ddeac, pinnedDebug host, helperbindings and finaltextELF identical to reviewed diagnostic892b089c. Exactcommands4de03754 select equality/search/bytes/join/parse/format at both sizes, sixarms5r/1w then G4matched5r/1w onCPU2. Calls/reporting agents confirm actualidle. Bounded-bias commands3108dc55 and host/24guests/helpers are also validated; root replay passes18actualLLVM boundary pairs. [Bias LLVM review](candidates/goal110-bounded-rem-5e97db47-20261004-llvm-review.json). | MaintainquietHOLD through the two serial candidate screens. No optional repeat has started. No builds/tests/Guardian/commits/heavy analysis until RELEASE. Sourceeaf4 anddashboard O70/S10 remain unchanged; no new measured result yet. |


| 2026-10-04 09:54:00 UTC | Annotation initial tradeoff; bounded-bias START | Annotation031 six-arm screen finishes09:52:06,360samples/720qualifications; matchedG4 finishes09:52:49.836796 with288 complete paired outcomes. SmallLLVM equality3.65935ns versusRust2.92597ns is1.25064×; matchedLLVM equality0.90417small/0.97886large, but largeLLVMsearch1.15704 (QBE0.99552). Other LLVM control medians≤1.00546 and QBE≤1.00297. | Keepannotationunintegrated. START bounded-bias exactcommands3108dc55, eight frozenrows then matchedG4 and signed supplement. The prepared annotation two-row15r/3w repeat follows under the samequietHOLD. No new integratedsource or targetconfirmation. |


| 2026-10-04 10:03:00 UTC | Bounded-bias first screens complete; annotation repeat starts | Bounded5e97 six-arm session296b1b31 finishes09:55:59 with240 samples/720 qualifications; LLVM fastest ratios append2.3764/1.8540, filter2.3820/2.1649, sort1.3169/1.0000, nested1.0000/1.0000. MatchedG4 sessiondd217d10 has192 outcomes: LLVM append1.0141/.9977, filter.9409/.9236, sort.9479/.9789, nested.9962/1.0032. QBE large nested1.1252, preliminary95% interval[1.0751,1.1595]. Signed supplement2ecbdd7c ends09:57:41 with96 outcomes; negativeLLVM.95235/.85815, positive.96182/.86053; negative admission is preserved and its previous slowdown is absent. | Annotation independent two-row15r/3w starts10:02:36.509UTC using unchanged commands4de03754. KeepquietHOLD. Prepare a bounded-bias repeat of gains and QBE nested control; no adoption or goal closure from exploratory screens. Integratedsourceeaf4/dashboard O70/S10 unchanged. |


| 2026-10-04 10:04:32 UTC | Annotation repeat confirms search blocker | Exact two-row15r/3w repeat ends10:02:49.505UTC with144 outcomes. SmallLLVM equality.900423; largeLLVMsearch1.154867. QBE.999073/1.001366. Both initial gain and cost replicate. | Keep0311796e unintegrated. Bounded-bias targeted repeat prepared ascommands0c5bd410/helper2c97f5f4: filterbothsizes, smallsort and largenested; fourarms15r/3w,288 outcomes. Rootreviews helperdiff and authorizes START under continuingquietHOLD. No newsource or goalconfirmation. |


| 2026-10-04 10:07:58 UTC | Timing released; bounded repeat confirms gain and QBE cost | Bounded repeat6600ce5a ends10:05:11.463UTC,288 outcomes: LLVM filter.94013/.92558, smallsort.94817, largenested.99986; QBE largenested1.11993 repeats the cost. All timing jobs ended; root RELEASES allworkers10:05:30. | Root independently replays saved streams/checksums/oracles/medians/intervals and creates separate exploratory six-arm observations. Agents diagnose actualcode regressions and archive candidates; dictionary gate/Debugbuild resumes. No candidate source is adopted yet; integratedeaf4 remains O70/S10. |


| 2026-10-04 10:08:45 UTC | Independent arithmetic timing replay and dictionary source pin | [Root replay](candidates/goal110-arithmetic-candidates-20261004-timing-review.json) verifies1008 outcomes across five distinct sessions, liveguest/helper bindings, independent checksum oracles, medians and recomputed paired intervals. Annotation repeatLLVM equality.90042[.89422,.90772], search1.15487[1.15085,1.16223]; bias filter.94013[.93768,.94342]/.92558[.92344,.92766], smallsort.94817[.94564,.95149], QBE largenested1.11993[1.09366,1.13595]. [T17 annotation observations](candidates/goal110-floor-result-0311796e-20261004-observed.json) and [T18 bias observations](candidates/goal110-bounded-rem-5e97db47-20261004-observed.json) pass artifact verification; neither can confirm targets. | Dictionary source64fb7e62 onbaseeaf4 passes88 Guardian checks and four native sanitizer suites; comment-only spec-tag correction is bound to tested bytes. Its Debughost build starts. Keep integrated dashboard unchanged while candidates remain unadopted. |


| 2026-10-04 10:14:09 UTC | Backend-specific remainder successor authorized | QBE nested comparison has2648 instructions in both builds with unchanged arithmetic/control sequence, but batch stackframe grows0x1e68→0x1e78 and1060 nested stack-address operands remap. Only generated batch_result/main change across403 named functions;401 native/helper bodies retain normalized instructions. This explains code differences, not the microarchitectural cause of12%cost. Annotation search loop has102 normalized-identical instructions but shifts32bytes; placement causality remains unproven. | Preserve5e/031 unintegrated archives. In a fresh5e-based tree, return to oldQBE remainder lowering before allocating a bias temp; keep LLVM lowering exact. Require focused proof, pinnedhost and full code/placement equivalence comparisons before adoption. Dictionary [independent native replay](candidates/goal110-dict-probe-64fb7e62-20261004-native-review.json) passes4 suites/56sourcebindings. Root checkpoint720267d7 passes88 Guardian checks; feedback committed56ebe4c. |


| 2026-10-04 10:19:53 UTC | Dictionary guest qualification; text placement evidence | Dictionary Debughost completes10:08:56UTC, SHA28b7ba85/receipt48bd5a7b; all24 optimized guests build. [Root guest replay](candidates/goal110-dict-probe-64fb7e62-20261004-guest-review.json) verifies livehost/source/assets,24guests,720 qualification and516 holdout checks with independent oracles. Text search normalization verifies400-byte/102-instruction loop,221-instruction scanner,393-instruction indexwalk and19-instruction large-equality helper unchanged apart fromplacement, including exactRIPconstant bytes. | Prepare dictionary lookup/update/set screen and controls againstcurrent14ffa/eaf4 guests. Text agent proposes a diagnostic-only loop-placement counterfactual; no productionpadding or causalclaim yet. Root notescurrentcompute stillhasperiterationdispatch and rangeplanner200-instructioncap versus~483-bytecode-operationinnerloop; this is a nextaudit prerequisite, not a newoptimization result. Timinglane remainsfree; no newgoalconfirmation. |


| 2026-10-04 10:27:31 UTC | Arithmetic archives verified and dictionary screen ready | Root copies exact191 files from annotation archive641506e1 and105 files from bounded archivebdcfac1e; verifies179+89 compressed/raw/live bindings and11 annotation helper bindings. Bounded portable verifier passes from integration with11 archived source snapshots and all correctness/timing replays. Both archive gates pass88 checks. Dictionary [static replay](candidates/goal110-dict-probe-64fb7e62-20261004-static-review.json) verifies lookup publication windows, unchanged collections frontend and four exact allocated/executable legacy/compute controls. | Dictionary commands ec09a8d2/readiness87d12255 are prepared for seven cases at both sizes, six-arm then matched5r/1w; no timing has started. LLVM-only successor focused58-test run is active, longhost deferred until lane release. Text diagnostic32-byte pre-loop padding is approved only as a separately labeled placement experiment after passthrough reproduction; no productionpadding or goal acceptance. |
