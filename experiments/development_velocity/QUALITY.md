# Source review rubric v1

Review the exact sealed submission against its public contract and protected
starter. Reviews happen after the application clock stops. Reviewers receive no
delivery times, language ranking, counterpart source, or improvement hypothesis.
They may inspect the public tests and run additional independent checks outside
application time. Keep any new findings separate from original timed work.

Approve only when the implementation is a general solution to the specified
domain, preserves complete input validation and error precedence, handles the
declared upper bounds, and uses the required process interface. Check state
conservation, rollback/expiry/ordering semantics where applicable. Verify required
module boundaries on maintenance tasks and inspect error handling for hidden
failures. Do not infer correctness solely from a passing private suite.

Reject correctness defects, hardcoded visible answers, edited protected inputs,
skipped required verification, dependencies outside the declared standard library,
or delegating `.my` behavior to another language/native host. Reimplementing a
missing general parser, map, sorter, codec or path library during timing violates
the preparation rule and must be recorded as a prerequisite discovery. Domain
validation, state transitions and task-specific traversal are application work.
Using a different sound algorithm or representation is allowed.

Use `approve_with_nits` only for nonblocking clarity/maintainability findings that
do not change behavior, robustness or the required verification. Do not reject
stylistic preferences, code size alone, or language-required ownership handling.
Compiler memory checks remain part of `.my` execution; do not remove checks or
change resource limits to qualify a result.

Record `development-source-review-v1`, the sealed source hash, decision and a
findings list. Each finding needs severity, file/location, concrete evidence and
practical impact. No source changes or feedback enter an active participant.
Untimed follow-up fixes retain the original failing attempt and its full budget
cost. A reviewed repaired artifact is a separate record, never a revised clock.
