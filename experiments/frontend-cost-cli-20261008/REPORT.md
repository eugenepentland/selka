# Coordinator cost CLI completion, 2026-10-08

Source commit: `8955c4ed98d8e3bc50bc7d1073eef3842fee699d`.
Locked branch/worktree: `codex/frontend-cost-cli`, created from FB1's clean
`889943fa81a7c0c69a6452b0ab6c076b42b728cc`. FB1 remains reserved for VP3.
This batch contains only the coordinator CLI completion and focused evidence.
It does not certify the common package exits or authorize a merge.

## Behavior

`mylang list-interfaces ENTRY.my --cost` keeps the ordinary declaration listing
as its exact prefix and appends the default release report from `mylang cost`.
The rows describe reachable emitted functions, including private functions and
specializations; an uncalled public declaration has no emitted row. One shared
cost-command pipeline produces both surfaces. Cost definitions and `ir.zig`
were unchanged. Main help lists `cost` and optional interface costs.

The option checks executable bodies before any stdout is written. Duplicate
`--cost`, the option on another command, and either ordering of `--cost` with
JSON `--contracts` are usage errors. Body failures print no partial listing.
The default declaration and contract outputs preserve their prior behavior.
The shared LLVM collector still prints its remark verdict and elapsed time on
stderr, as the standalone cost command does.

## Focused validation

| Check | Verdict | Admitted wall time |
| --- | --- | ---: |
| Green install, diff-scoped Guardian | 9/9 steps, 88/88 checks | 1.024305 s |
| CLI interface/help regression selection | 6/6 tests | 0.480954 s |
| Shared cost-command unit selection | 7/7 tests | 1.984508 s |
| Listing differential against clean FB1 executable | 12/12 comparisons | 1.681475 s |
| Source commit, whole-tree Guardian hook | 88/88 checks | 1.335493 s |
| Zig format check | PASS | 0.031449 s |
| Source whitespace check | PASS | 0.045460 s |

The CLI regression checks the exact appended costs, omission of an uncalled
public function, repeated default listing, flag refusals, and empty stdout on a
body error. `listing-comparison.json` records five single-file, imported,
library-only, bad-body and bad-signature fixtures. Plain and contract outputs
are identical in status, stdout and stderr across both compilers (10 cases).
Two executable entries additionally match `default stdout + cost stdout`
exactly. Collector diagnostics match after replacing only elapsed nanoseconds;
all raw timing, count and verdict bytes remain in their command logs.

FB1 executable SHA256: `5ddab7ce39d576615f55676886252e4dbfff863d0d253cc003886a769c7b1a55`.
Candidate installed Debug executable SHA256: `7c37507410b4e4d339c0039b7cec47d36b84566190e7d96bf3df79133e2d35a8`.

## Command history and timing

`logs/` retains one raw stdout, stderr and JSON receipt for every command run,
including the initial Guardian holds and the first comparator attempt. That
attempt incorrectly assumed the shared collector was quiet on stderr; the
corrected comparator preserves the raw diagnostics and excludes only their
varying elapsed nanoseconds when comparing them.

Guardian's change classifier did not accept a regression tagged as a case of
the existing cost spec. A new `FRONTEND-INTERFACE-COST-1` bullet and primary tag
resolved the hold without weakening the gate. The test runner printed its
known `failed command` trailer despite PASS and exit 0; raw receipts preserve it.
These observations were sent to the coordinator for the required consolidated
Guardian feedback entry and commit.

Every build/test used `scripts/build-slot.sh`; recorded build/test affinities
exclude CPUs 2, 3, 10 and 11. Cold compiler admission used the outer benchmark
compile lock. The longest admitted step was the initial cold install at
6.743378 s, following 150.573969 s of contended admission wait. No admitted step
exceeded five minutes, so no new slow-step investigation was required. No
full gate or fuzz matrix ran in this batch, and no benchmark worktree/cache was
modified. No branch was pushed or merged.

## Held exits

The coordinator still owns common section 5 qualification: full post-S5 gate,
frozen S5 differential/fuzz, external corpora, C1/C2_policy=0/C3 and performance
budgets. Benchmark fuzz was active while these focused checks ran, so the full
gate remained held. Only the focused CLI completion is ready to integrate after
those exits pass.

The source commit receipt is tracked here. Final evidence staging/commit and
clean-tree receipts are retained locally under
`.mylang-cache/frontend-cost-cli/closeout/logs/` to avoid recursive self-recording.
