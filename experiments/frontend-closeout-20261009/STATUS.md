# Frontend closeout status

Complete for the bounded October 9 frontend follow-through plan.
Branch: codex/frontend-followthrough-20261009.
Implementation commits: fb868aace and 48e741592.

- Parser recovery and configured developer views: complete.
- Resolved nominal specialization reuse: complete for the measured scope.
- Explicit noalloc Core checking and effect consumer audit: complete.
- First source-shaped lowering family (range) and shared validation: complete.
- Selected typed cost census, counters and Juice workflow: complete.

Qualified compiler: 21319448ba51241f917c040004d1a3c7123e5516d5f0a766d7cff557294793f2.
All 614 recorded source hashes remain unchanged; the installed compiler matches.

Full gate: 94/94 steps, 2,256 executed Zig test entries, 20,987 shard skips.
Formatting: 15/15 steps. Whole-tree Guardian: 88/88 checks.
External: all 450 mode commands, 974 Lox native cases and 34 EDA outputs match.
Range: 100 exact accepted raw/facts outputs, 72 preserved rejection statuses,
six accepted native probes exact. Cache relocation reuses the measured nominal
specialization instead of checking it again.

REPORT.md, qualification.json and package reports contain exact source identities,
remaining conservative limits, changed verdicts and retained failed attempts.
Three Lox source fingerprints remain explicitly unproved; contracts, providers,
case membership and verdicts match. The pre-existing custom range CFG refusal
remains documented. Historical timing work stays unfinished outside this plan.

Guardian feedback: guardian-zig commit 675dac5. No mylang main merge or push.

## Archived full evidence

Full captures and the original version of this report remain in commit `0bbfeb740`,
reachable from `main` and `codex/frontend-followthrough-20261009`.
Retrieve any archived path with `git show 0bbfeb740:PATH` (paths are repository-relative).
