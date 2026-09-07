# Validation of the ergonomics refactor — 2026-09-07

- Installed ReleaseFast compiler and raw-byte host: Guardian 88/88 passed,
  baseline disabled, no frozen findings or policy edits for this task.
- Application format check passed. Exact duplicate discovery at min-nodes=30
  reported zero candidate groups (21/39 functions indexed; advisory threshold).
- Public CLI and role regressions passed. The private replay receipt records
  seven passing groups: 142 boards plus four malformed raw requests.
- The unchanged 57,692,813-byte output stress case passed within existing host
  and VM limits. Exact one-MiB input, 50,000-key input and long duplicated keys
  passed their expected behavioral assertions.
- The final aggregate interpreter run reported 911/911 Zig tests passed.
- All nine navigation-client tests and all 44 verification tests passed
  independently against the final installed compiler.
- All ten repair-harness tests passed with disk-backed temporary storage.
- Source/binary hashes in verification.json were checked against final disk
  contents; whitespace validation passed.

## Aggregate-run limitation

The all-in-one command did not finish green in this environment. Initially the
repair harness exhausted its /tmp quota. Running with TMPDIR on the main disk
fixed that harness, but the unchanged scheduler test
test_ten_clients_coalesce failed its five-second subscription deadline, including
a serial (-j1) run. Its fixture uses a 150ms worker lease.

The 44-test verification suite passed twice independently using normal /tmp,
including the new standard-library cache checks; the final replay took 9.838s.
The ten repair-harness tests passed independently with disk-backed temporary
storage in 36.183s. No scheduler production code, test deadlines or tests were
changed to suppress the failures.

This records component passes and the remaining aggregate environmental/test
limitation separately; it does not claim a clean aggregate run.
