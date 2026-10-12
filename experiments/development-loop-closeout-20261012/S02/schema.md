# S02 scoped policy and lifecycle contract

Base C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.

`verification_policy.validate_policy`, `execution_identity`, and `evaluate`
implement v1 report-only policy data. The document has exactly `version: 1`,
`mode: "report_only"`, and `entries: []`. Each entry identifies `action_id`,
`scope`, optional `member_id` and `test_id`, and `targets`. An individual test
requires both member and test identities. An admitted action cannot identify a
member. Duplicate identities and unknown fields fail validation.

Targets are independent positive finite values or null: `expected_seconds`,
`regression_seconds`, `hard_deadline_seconds`, `memory_ceiling_bytes`, and
`work_ceiling`. Bytes/work require integers. A work ceiling requires `work_unit`
(a declared completed unit, such as `test_case`, `action`, or `instruction`);
observations with another unit remain unknown. Memory is aggregate concurrent
resident bytes; a process lifetime high-water observation cannot establish it.
All policy targets remain advisory, including a configured hard deadline.
`mode: "enforced"` is rejected because there is no qualified enforcement adapter
or current isolated headroom evidence. No sample count implies qualification.

Optional `exception: {name, reason, review_point}` documents a named reviewed
legacy exception without renaming a slow test. Optional `headroom_evidence` is a
bounded list of SHA256 references; references alone establish no qualification.

| Scope | Required explicit clock |
| --- | --- |
| `admitted_action` | `admission_handshake_to_lineage_closeout` |
| `setup_build` | `explicit_setup_build_start_to_end` |
| `individual_test` | `supported_runner_start_to_stop_including_teardown` |

Queue time and user cancellation are separate outcomes. Setup/build is a nested
span; its duration cannot be added to the enclosing admitted action. A shared
Zig gate's wall time cannot be assigned to every action or summed from member
steps. Evaluation requires exact scope/identities/clock and fresh, complete,
successful observations. Missing telemetry stays unknown; results are nonadditive.

`verification_budgets.evaluate_scoped_policy(path, report, inventory)` is the
coordinator integration API. It bounds and strictly parses policy data, checks
current action identities, and returns `evaluated`, `not_configured`, or
`unavailable`; every result declares `enforced: false`. Invalid data never masks
the gate verdict. It accepts explicit `report.scoped_budget_observations` and
adapts `actions[].test_telemetry` lists of S01 validated observed member documents.
Only fresh actions, complete/untruncated member documents, and passed tests with
integer `elapsed_ns` become individual-test duration samples. Reused/skipped,
failed, missing, duplicate, or incomplete observations establish no sample.

`execution_identity(policy)` is empty: advisory-only threshold changes preserve
compatible captures. The coordinator patch keeps the optional policy path and
module out of common execution inputs. The policy module must still be declared
as an input of tests that execute it. Existing explicit user-configured
`ProcessLimits` are independent controls, and timeout/grace changes continue to
alter their execution identity. Existing five-sample named-member advisory
calibration and threshold-only reevaluation remain unchanged.

`run_supervised` runs in a fresh admitted launcher. It forks one isolated
subreaper for the action lineage, preserving admission descriptors while leaving
preexisting admission helpers and their later children owned by the outer
launcher. SIGTERM/SIGINT are masked across fork until the inner handlers are
ready. Pending cancellation is observed before work starts. Cleanup freezes all
discovered descendants using pidfds and birth identities before killing and
reaping, including detached/thread-owned descendants. Unexpected inner errors
return incomplete status 125. The existing two-second natural cleanup window
counts against admitted execution limits. Parent watchdog grace must remain at
least 0.5 seconds, as required before this change. No new scheduler or shared
subscriber ownership mechanism is introduced.
