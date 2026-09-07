# Matched preparation drafts

The [practice contract](../contracts/practice-v1.md) supplies the plan's three
unrelated exercises: call a local module, handle a fallible operation, and repair
an unresolved-name diagnostic. Each language has `starter/`, a separate coordinator
`solution/`, a guide, and independent construction tests outside the starter.
Builders did not read application baselines, pilot tasks or grading oracles.

All solutions pass the same 21 public checks from `practice_cases.py` in isolation
(63 checks total). See the recorded
[construction evidence](../evidence/practice-solution-validation.json).
For that conformance run, the Zig solution was compiled once in isolation and its
executable identity pinned for all inputs; this is not a compilation/development
speed comparison. Raw records are at the temporary path in the summary; reproduce
them into durable private storage before a scored cohort is frozen.

Builders also tested the three intended defects separately: wrong helper argument,
lost parse failure and unresolved name. `.my` and Zig reject the unresolved name
before executing any input; Python raises it when the diagnostic branch executes.
This difference is documented rather than hidden. No language compiler changes or
Guardian runs were needed for these practice projects.

`practice_pack.create(directory, language=...)` captures only the language's starter
and guide, plus the common public contract/checks. `practice_pack.load` verifies
those receipts. It never includes `solution/` or coordinator tests. Feed the pack's
contract into the practice prompt, `starter/` into the practice source, and
`cases.json` into the practice checker. Retain the initial guide during the task
as required by the plan. Cohort v2 captures all three practice packs and derives
practice inputs from them, rejecting overrides. The guide and contract remain
protected task files under `.trial-practice-guide/`.

Independent fairness review confirmed three-expression repair parity. It exposed
a contract mismatch between the application limit and host envelope, now corrected
to a common 2 MiB harness ceiling. All three solutions pass an additional isolated
check at that ceiling; see `evidence/practice-envelope-validation.json`. Python
extra helper-argument guidance was normalized, and the contract now acknowledges
that long invalid inputs cannot independently prove a size guard. Static/runtime
diagnostics and supplied I/O scaffolding remain visible language differences.
The packs remain `draft-unreviewed` launch artifacts: unscored agent calibration
and complete launch review are still required. Passing a completed reference does not demonstrate that an agent
can learn and repair the starter within the provisional 20-minute ceiling.
