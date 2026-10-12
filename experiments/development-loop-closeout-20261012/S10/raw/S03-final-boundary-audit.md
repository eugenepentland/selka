# S03 frozen boundary audit

Read-only audit of Git objects at C0
`fbfcaa7a923186a8e773c3760f81c10aa345a432` and C1
`a9a3208a4f3edbf17170cfc18d57f5f999af49c3`.
`python3 experiments/development-loop-closeout-20261012/S03/audit_frozen_boundary.py`
exited 0; assertions, exact names and source/evidence SHA-256 hashes are retained
in `final-boundary-audit.json`. No integration edits or builds/gates were run.

- **Named parity passes:** all eight names moved exactly once from broad units
  to `text_scalar_root_test.zig` (three number grammar, five format tests).
  Both test modules, both production modules and both embedded oracles are
  byte-identical C0→C1. The broad root diff is exactly the approved import removal.
- **Wrapper parity passes:** C0 broad root 7 unnamed wrappers; C1 broad root 6
  plus scalar root 1. Total remains 7.
- **Independent closure passes:** final import/embed closure is exactly the
  previously declared seven files, std only externally. Final `text_scalar_unit`
  group has exactly those inputs and only artifact `text-scalar-units`; it is
  registered as cacheable with complete declared inputs. No compiler, runtime,
  generated-option or seed imports were introduced.
- **Final inventory passes:** frozen `candidate-inventory.json` contains 46
  groups and 101 required/registered members; summing action metadata also gives
  101. Unknown member count is zero.
- **Recorded native execution passes:** frozen coordinator `scalar-plan.log`
  reports 9 selected/9 passed. `scalar-filter-controls.log` reports matching
  `float format` filter status 0 (one named plus one wrapper, 2 passed), and
  nonexistent `s03-guaranteed-absent-filter` status 1 as expected. Those are
  inspected existing executions, not new runs or whole-gate acceptance.

Paired cold compile/link/RSS and latency acceptance remain **not qualified**.
The coordinator's warm operational compile/RSS output and S03's direct binary
size do not establish a matched cold regression comparison. The complete frozen
candidate gate and broader edit/failure matrix remain S10/coordinator acceptance.
