# Independent integrated configuration/producer review

Read-only review of integration tree on 2026-10-12, following stable shared build
wiring. `final-review.json` binds 212 reviewed configuration file content hashes,
46 exported groups, exact inventory SHA, actual scalar executable/source metadata,
and a caller exercise against the adopted v4 action implementation. No integration
file or pin was written.

Observed projection candidate SHA256:
`686631858644a1ce4535ac1f981f3338421ff46e3f0f3ca10d7e5de43c14b655`.
Checked-in pin remains
`7cefed8043b05279aa8960b33ea742e728f91dfc294d08c6e48d7b4a0a8fd6fc`.
This is a candidate fingerprint, **not an accepted qualification**.

## Consumer and closure conclusions

Reviewed all references to build_test_inputs/test_inputs/input_lists in root build
files, Python drivers, coordinator and selfhost. Lists drive input hashing, group
registration, complete inventory export, fixture membership coverage and now exact
producer writer Run file inputs. No list-derived command/flag/runtime/tool policy
was found. The coordinator data-only parser agrees exactly with current exported
lists. Arbitrary build code, Guardian source/runner and Zig tools/library closure
stay broad; the list stays watched during projected action reuse.

Producer action v4 authenticates opted-in tooling-units/text-scalar-units against
full live source snapshots and exact artifact provider bytes. Missing metadata
retains full artifacts; reviewed legacy providers preserve their prior artifact
projections; unknown new narrowing retains full artifacts. Context keeps build,
tools, options, mode, environment and platform. Artifact writer has explicit file
inputs for producers, snapshot helper and each reviewed source/oracle. Full
artifact and source snapshots stay live through lookup/publication.

Authorization modules verify_cache/snapshot/process/producers/profiles/store have
loaded-code digests and watched source. Retained RuntimeGuard covers complete
scripts and imported providers, including dynamic imports. Fixed unittest module
names in build.zig bind telemetry's dynamic test loader. Report/budget/policy
helpers are advisory-only: they do not grant receipts or alter profile verdicts.
Their absent common loaded digests are not presently an authorization blocker;
coherent diagnostic-version identity should be considered separately before any
future enforcement. Imported source and reporting errors must remain advisory.

## Two blocking defects and fixes

1. Actual exported optimize mode is `debug`; pinned Zig enum `@tagName` uses
   `debug`, `release_safe`, `release_fast`, `release_small`. Initial S04 helper
   accepted only uppercase historical CLI spellings, so verification-prepare would
   throw and actual action metadata would not authenticate. Fixed in S04 by
   canonical lowercase tags, explicit aliases for prior CLI calls, and producer
   contract version/domain 2. New regression tests cover all actual tags. With
   the corrected helper loaded in memory, root's actual v4 action accepts metadata
   for the real native scalar executable and retains whole-artifact fallback for
   absent metadata. The isolated caller exercise uses a synthetic tool digest;
   it is not a production receipt or end-to-end toolchain qualification.
2. `verification_producers_test.py` dynamically copies ROOT/name from 11 tooling
   files and six existing scalar source/oracle files. Its verification_cache input
   list omitted those sources; static fixture coverage does not see ROOT/name.
   Root patch request: append `++ tooling_unit ++ text_scalar_unit` to the existing
   array (or declare its exact union). Confirm source edits invalidate that cohort.

Root `.tmp/scalar-plan.log` shows verification-plan succeeded and the actual scalar
native target passed 9/9 tests with Guardian runner; compile MaxRSS164M, run5M.
This is focused operational evidence, not the final complete gate.

## Conditions for explicit qualification

- Integrate producer version2/mode fix and declared fixture-source closure.
- Re-export inventory and verify exact list agreement, coverage and all members.
- Run producer and coordinator regressions, including lowercase actual modes,
  missing metadata fallback, arbitrary configuration mismatch, semantic/source
  changes and fixture-source action identity changes.
- Confirm writer actual --qualify invocations succeed and source/oracle edits
  regenerate metadata; retain tool/build/source/ABI/seed and mutation authority.
- Recompute candidate fingerprint from the exact frozen configuration; any changed
  configuration file requires renewed review. A list-only patch should preserve
  this excluded-list candidate, while still affecting responsible action recipes.
- Only then let root explicitly record the qualification pin and run S10's exact
  candidate complete gate/formatting and forced/cached edit/failure matrix.

DL4 cannot close from this caller exercise alone. Cross-worktree producer identity
parity remains distinct from action receipt root/environment policy. Bootstrap
seed/stage and median/p95 acceptance remain S09/S10 requirements.
