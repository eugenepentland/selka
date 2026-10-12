# S05 profiles and bounded work contract

Base C0 is `fbfcaa7a923186a8e773c3760f81c10aa345a432`. The profile
schema is `verification-profile-v1`. Selection consumes the current validated
inventory and every action's current qualified receipt decision; it creates no
new inventory, cache, scheduler, or dependency authorization.

`schedule(plan, rows, profile="complete", quick_actions=3, costs=None)` selects
existing pending actions. `quick` uses dependency miss explanations, optional
report-only costs, then an explicitly heuristic member-count proxy. It lists all
pending, selected, deferred, and affected actions. A broader semantic edit cannot
shrink the visible obligation inventory. The three-action default is a bounded
feedback selection, not a qualified five-second latency promise. Zig dependencies
may also execute prerequisite work outside those selected targets.

`coverage(plan, rows, selected, profile, status, inputs_stable,
qualification_required=(), qualification_results=())` accounts for all current
IDs. The caller alone qualifies receipts and successful admitted execution under
its live input guards. A failed shared gate proves no selected action succeeded.
Unstable inputs revoke coverage; explicit failed/skipped work cannot become
complete. Missing, duplicate, foreign, or corrupt decision identities fail closed.
Filtered inventories cannot certify the full gate.

`quick` always reports partial and `complete_verification=false`, even with all
required receipts warm. `complete` selects all pending required work. The proposed
coordinator adapter returns 3 for partial, 0 for complete success, and the existing
failure/cancellation status otherwise. Action successes remain reusable across
profiles; selecting fewer actions does not publish a complete-verification receipt.

`long-qualification` retains the complete gate and names additional qualified work.
`complete_verification` and `complete_qualification` are separate. Missing long
qualification inventory is explicitly outstanding. The proposed coordinator patch
names fuzz and wall-clock performance as outstanding; final qualification
orchestration and authenticated result integration remain coordinator/S10 work.
Instruction counts never provide a wall-clock qualification result. Telemetry
completeness never provides verification completeness.

Both existing fuzz and Juice coordinators accept optional `--max-actions` and
`--action-timeout`. Defaults remain unlimited missing actions and no newly added
whole-action deadline. Existing fuzz steps/runs/per-case limits are unchanged.
The maximum counts admitted missing actions, after qualified reuse lookup; reuse
does not consume the cap. Exhaustion returns 3 with `complete=false`, preserves
completed evidence, and names outstanding actions/workloads. Fuzz also names
unvisited targets whose retained replay inventory has not yet been expanded.
An explicit positive finite action timeout uses S02's `ProcessLimits`, excludes
admission queue time, covers the admitted worker, and enters evidence identity.
The work cap is request selection and does not enter completed-action identity.
No deadline is inferred from advisory calibration.

Fresh Juice requests remain fresh, threshold reevaluation remains measurement-free,
and existing raw evidence validation still checks sample count, outputs, completed
units, metrics, and repeatability. Fuzz still requires complete explored work and
retained corpora; corrupt/missing receipts and inputs cannot supply success.
Fuzz/compiler and Juice/compiler inputs retain the broad compiler/provider closure:
S04 has no qualified independent checker identity for these consumers.

`workloads/prepare.py` generates real native Juice compiler-check and forced guest
test-driver manifests. The latter's oracle requires exactly both named tests to
pass freshly, with zero cached/skipped/failed/unsupported tests. Normalization
retains the completed-work summary while the oracle checks the full raw report.
Workloads stay fresh-only and explicitly incomplete for external provider closure.
Their software-count/performance qualification is unavailable on this machine:
`valgrind` is absent. Native smoke proves command behavior, not performance.

Shared-file changes are reviewable patch requests: `coordinator-profile.patch`
and `build-registration.patch`. Session JSONL already forwards the same CLI args;
the patch adds the profile module to guarded dispatch. Root owns common CLI,
integration tests, registration, and user-facing docs. Root must re-audit its final
configuration fingerprint after adapting the patches.
