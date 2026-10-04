# Runtime performance goal: LLVM within 1.10×, with QBE tracked

This is the execution plan and live status document for the next performance
campaign. The goal is active. The initial table came from saved measurements; new results
will be added with their own evidence IDs. Update this file in place and retain
the raw evidence for every reported result.

## Status

<!-- STATUS-START -->
- **Campaign:** active; sorting improvement integrated with a documented QBE tradeoff.
- **Last document update:** 2026-10-04 04:18:15 UTC.
- **Active batch:** certified list-readiness inlining, search alignment, and
  scalar-address lowering diagnostics.
- **Current implementation:** `perf/runtime-parity-20261003`, production source
  `63df6b6c481b12fd711755ec40cdcb5d1c984ccc`, equivalent to sorting `8043c4d9`.
- **Latest complete integrated measurement:** B0, before join and sorting changes.
- **Acceptance scope:** LLVM required; QBE tracked separately.
- **Current confirmations:** **0/80** after the production change. The eight
  earlier G2 confirmations remain in history and require fresh integrated checks.
- **LLVM states:** 71 above target, three observations awaiting confirmation,
  six stale confirmations. Mixed revisions remain visible; this is not a full-suite pass.
- **Dashboard artifact:** [After sorting integration](candidates/goal110-dashboard-20261004-sort.json).
- **Active operations:** readiness `63842d3c` passed720 qualifications and516
  holdouts and is next for timing. Scanner alignment `57034382` is built and
  finishing nearby-input checks. The strict and hybrid scalar-pointer changes
  both leave actual optimized code unchanged and are being deferred.
- **Sorting tradeoff:** repeated small LLVM integer-sort improvement of 17.6%
  is accepted alongside an 11.0% large QBE nested-mutation regression. The QBE
  nested instruction stream is unchanged; code/data layout is a hypothesis,
  not an established cause. Small LLVM integer sorting still misses at 1.3607×.
- **Next action:** investigate the repeated search slowdown and two compiler
  mechanisms using existing artifacts before another host build. The parser
  timing lane has ended; builds and checks have resumed. No new confirmations.

| Backend | Required targets | Latest observed ≤1.10 | Latest observed >1.10 | Current goal confirmations |
|---|---:|---:|---:|---:|
| MyLang LLVM | 80 | 9 | 71 | 0; eight earlier G2 confirmations need rechecking |
| MyLang QBE | 0 (80 tracked) | 3 | 77 | 0; three earlier confirmations are stale |
<!-- STATUS-END -->

The counts above use the **fastest current configuration in each measured row**.
They differ from the earlier campaign's frozen historical 1.00 targets. G2
confirmed eight LLVM cells on the join source. Sorting T7 updates eight observed
rows but provides no normal confirmation; every target still needs acceptance
on the current integrated source. QBE being above 1.10 does not prevent completion.

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
| B1 | `mutate_nested`, `bytes_scan`, `string_search` | Confirm existing LLVM wins and establish regression checks | Reconfirmed 6/6 at integrated join957f97c6 / G2 |
| B2 | `string_equal`, `string_join` | Equality/ownership overhead and nearby large-input targets | Join both sizes confirmed at G2; equality99 rejected and deferred pending shared cause |
| B3 | `record_reads`, `record_construct`, `record_update` | Record representation, scalar replacement and transfers | General direct scalar-slot lowering is in focused/native checks |
| B4 | `call_direct`, `call_indirect`, `option_handle`, `result_propagate` | Calls, inlining, dispatch and return paths | `d14e26f4` speeds direct calls but retains fallback/record regressions; unintegrated |
| B5 | `integer_math`, `float_math`, `branch_predictable`, `branch_mixed` | Scalar lowering and loop invariants | Queued |
| B6 | `list_scan`, `list_append`, `list_filter`, `mutate_unique` | Iteration, capacity and uniqueness | Queued |
| B7 | `tagged_stack`, `mutate_shared`, `alloc_short`, `alloc_retained` | Ownership, allocation elimination and retained data | Queued |
| B8 | `dict_lookup`, `dict_lookup_str` | Lookup/probe and key costs | Queued |
| B9 | `dict_update`, `dict_update_str`, `set_dedup` | Publication, replacement and deduplication | Queued |
| B10 | `binary_search`, `packet_decode` | Bounds, branches and scalar reads | Queued |
| B11 | `sort_int`, `sort_records` | Comparator dispatch and scratch work | `2a49da29` rejected; disjoint-run rotation8043c4d9 passed native checks, guests building |
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
| list_append / small (64) | 116.6963 | 1.3316 | 1.8960 | 2.1422 | **1.0000** | 2.6790 | 4.2871 | O / O | T7 |
| list_append / large (4096) | 5492.3848 | 1.0786 | 1.9315 | 2.1213 | **1.0000** | 2.3875 | 3.8839 | O / O | T7 |
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
| mutate_nested / small (64) | 719.2670 | 1.5723 | 1.5873 | 1.6002 | 1.4487 | **1.0000** | 1.1548 | P / O | T7 |
| mutate_nested / large (1024) | 7131.9083 | 2.6814 | 2.3925 | 2.6951 | 2.4699 | **1.0000** | 1.2309 | P / O | T7 |
| sort_int / small (64) | 162.9593 | 1.3593 | 6.3105 | 1.6248 | **1.0000** | 1.3607 | 2.5518 | O / O | T7 |
| sort_int / large (4096) | 44161.2680 | 1.4352 | 5.2027 | 1.4470 | 1.0013 | **1.0000** | 1.2097 | P / O | T7 |
| sort_records / small (64) | 542.3958 | 1.1991 | 12.8080 | 1.4046 | **1.0000** | 2.2466 | 2.8732 | O / O | T7 |
| sort_records / large (4096) | 49756.5747 | **1.0000** | 24.2944 | 2.2739 | 1.8195 | 1.2157 | 1.5656 | O / O | T7 |
| lox_eval / small (16) | 738.1632 | **1.0000** | 1.1383 | 2.6921 | 2.6291 | 3.6607 | 4.0643 | O / O | B0 |
| lox_eval / large (256) | 10981.4215 | **1.0000** | 1.1776 | 2.7947 | 2.7405 | 3.6183 | 3.9186 | O / O | B0 |
| bytes_scan / small (64) | 3.4936 | 5.0533 | 6.7494 | 7.8731 | 3.4318 | **1.0000** | 2.3316 | S / O | G2 |
| bytes_scan / large (4096) | 75.9983 | 13.9961 | 13.2417 | 18.9235 | 9.1867 | **1.0000** | 1.0389 | S / S | G2 |
| string_equal / small (64) | 2.9688 | **1.0000** | 1.5119 | 1.3398 | 1.2732 | 1.3576 | 7.3130 | O / O | T3 |
| string_equal / large (4096) | 30.0438 | **1.0000** | 1.2331 | 2.1291 | 1.6502 | 1.1718 | 22.8477 | O / O | T3 |
| string_search / small (64) | 19.5710 | 2.1818 | 1.2578 | 4.5687 | 3.7994 | **1.0000** | 1.2554 | S / O | G2 |
| string_search / large (4096) | 87.2513 | 14.8271 | 7.3482 | 34.0815 | 30.1024 | **1.0000** | 1.0635 | S / S | G2 |
| string_split / small (64) | 557.5921 | **1.0000** | 1.8763 | 1.8560 | 1.7269 | 6.2247 | 8.1218 | O / O | B0 |
| string_split / large (4096) | 28435.3492 | **1.0000** | 2.3570 | 2.1980 | 2.0666 | 7.6152 | 9.7548 | O / O | B0 |
| string_join / small (64) | 218.7103 | **1.0000** | 1.8238 | 1.4099 | 1.2128 | 1.0464 | 1.3873 | S / O | G2 |
| string_join / large (4096) | 12572.0989 | 1.0570 | 2.0184 | 1.3990 | 1.3022 | **1.0000** | 1.0738 | S / S | G2 |
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

| T1 | Unintegrated text source `965d416c`; 5-round screen and 15-round paired control | [Investigation and archives](../../experiments/runtime-goal110-text-20261004/README.md), [quiet paired report](../../experiments/runtime-goal110-text-20261004/equality-quiet15-before-after.json.gz) | Equality improves; large LLVM search and equal64 helper regressions prevent adoption. Matched-host controls retained. No goal confirmations. |
| T2 | Unintegrated loop source `5dc31c3a`; paired five-round selected and fallback screens | [Investigation and archives](../../experiments/runtime-goal110-calls-20261004/README.md), [independent correctness review](../../experiments/runtime-goal110-subset-independent-review-20261004/REVIEW.md) | Rejected for integration: record/fallback LLVM regressions despite QBE gains. No goal confirmations. |

| T3 | Join `5a60ef10`, integrated as `957f97c6`; Debug host, RF guests; 5 rounds/1 warmup | [Raw screen](../../experiments/runtime-goal110-join-20261004/join-screen.json.gz), [observed analysis](candidates/goal110-join-5a60ef10-20261004-observed.json), [paired controls](../../experiments/runtime-goal110-join-20261004/join-before-after.json.gz), [review](../../experiments/runtime-goal110-join-20261004/README.md) | Join small1.05204/large1.000; no material paired control regression. Exploratory observations, no confirmations. |

| T4 | Rejected sorting `2a49da29`; Debug host, six-arm and paired five-round screens | [Complete archive](../../experiments/runtime-goal110-sort-counting-20261004/README.md), [coordinator replay](candidates/goal110-rejected-screens-20261004-0240-review.json) | No material LLVM gain; QBE record-sort regressions. No integrated dashboard rows replaced. |
| T5 | Rejected loop `d14e26f4`; matched Debug-host paired screen | [Complete archive](../../experiments/runtime-goal110-copy-locals-20261004/README.md), [paired raw](../../experiments/runtime-goal110-copy-locals-20261004/regression-screen.json.gz) | Direct calls improve, but fallback and record regressions remain. No integrated dashboard rows replaced. |
| G2 | Integrated join957f97c6; sessions `0a7c22fa-7d2c-49b4-b64f-ffbb4803a5cf` and `653a9088-22ea-4938-b01e-8af53a1346fa`; 02:51:25–02:54:43 and 02:55:34–02:59:02 UTC; RF host,15r/3w each | [Accepted analysis](candidates/goal110-join-957f97c6-rf-20261004-accepted.json), [complete archive](../../experiments/runtime-goal110-integrated-rf-20261004/README.md), [review](candidates/goal110-join-957f97c6-rf-20261004-correctness-review.json), [checks](candidates/goal110-join-957f97c6-rf-20261004-checks.json) | Eight LLVM cells confirmed; latest displayed medians from B. Three QBE confirmations are informational. Full80 goal remains incomplete. |

| T6 | Rejected equality `99a4d071` and untimed precursor `1c367e95`; Debug hosts | [Equality99 archive](../../experiments/runtime-goal110-equality-always-20261004/README.md), [untimed static checks](../../experiments/runtime-goal110-equality-inline-20261004/static-validation.json), [coordinator replay](candidates/goal110-rejected-screens-20261004-0334-review.json) | Large equality improves but small equality does not, and LLVM large search regresses16.3%. No accepted rows change. |

| T7 | Sorting `8043c4d9`, integrated as `63df6b6c`; six-arm5r/1w and paired15r/3w repeat | [Archive](../../experiments/runtime-goal110-sort-rotation-20261004/README.md), [observed analysis](candidates/goal110-sort-8043c4d9-20261004-observed.json), [coordinator review](candidates/goal110-rejected-screens-20261004-0334-review.json) | LLVM small integer sort improves17.6%, still1.3607× fastest. QBE nested-large+11.0% is an explicit tradeoff. No goal confirmations. |

| T8 | Unintegrated parser `52e6d074`; six-arm5r/1w and matched Debug5a paired screen | [Archive](../../experiments/runtime-goal110-int-parse-20261004/README.md), [paired raw](../../experiments/runtime-goal110-int-parse-20261004/parser-before-after.json.gz), [coordinator review](candidates/goal110-parser-52e6d074-20261004-review.json) | Modest parsing gains accompany a16.8% large LLVM search regression. No accepted rows changed. |

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

For future entries, include the affected cases/sizes/backends and before → after
ratios, or say explicitly that the step produced no timing result. Link long
diagnostic notes and raw evidence rather than pasting build logs here.
