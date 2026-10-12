# S01 handoff

C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Implementation: `277089d1831895c99697e5abbfd5862f67ac7552`.
Branch: `codex/dl-closeout-20261012-S01`.
Owned changes: scripts/verification_report.py, new
scripts/verification_telemetry.py and scripts/verification_telemetry_test.py,
and this experiment directory. No shared build/registration/runner/Guardian
files changed; FEEDBACK.md untouched. Worktree checkout was checked clean before
edits (initial checkout in progress was allowed to finish).

The actual Python unittest producer captures every selected case, including fast
cases, failures, skips and parent subtests. It records start-before-setup through
stop-after-teardown monotonic elapsed, actual loaded selected count and terminal
completeness. Skipped/reused rows have null elapsed. Fail-fast leaves explicit
partial coverage. Malformed/truncated/duplicate/version-mismatched data never
becomes complete coverage. Process CPU is runner-self suite delta; Linux RSS is
runner-process lifetime high-water. Aggregate concurrent RSS remains null.
Nested explicit phase spans are retained without adding their durations.

The coverage helper represents every caller-supplied action inventory ID,
including outstanding work; it is advisory and never verifies success. Bounded
stability diagnostics detach provider observations without clearing dirty state
or inspecting inputs. Provider byte-restored ABA/watch overflow/membership
reason generation belongs to S08. Version and integration APIs are documented
in schema.md; six precise shared patch requests are in shared-patch-requests.md.
S02/S05/S06/S08/S10 received the contracts directly.

Commands run in this worktree (Python 3.14.4):

```bash
python3 -m unittest discover -s scripts -p 'verification_report_test.py'
python3 -m unittest discover -s scripts -p 'verification_telemetry_test.py'
python3 scripts/verification_telemetry.py --action-id report-python --member 0 --output experiments/development-loop-closeout-20261012/S01/report-telemetry.json verification_report_test
python3 scripts/verification_telemetry.py --action-id telemetry-python --member 0 --output experiments/development-loop-closeout-20261012/S01/telemetry-tests.json verification_telemetry_test
git diff --check
git commit -m 'Add supported unittest telemetry and bounded advisory coverage reports'
```

All commands exited 0. Initial discovery covered 12 existing report + 7 new
collector tests; final supported-producer runs covered 12 + 9 after CLI/process
adversarial tests were added. Raw logs and producer JSON are committed.
Final counts: selected 21, executed 21, timed 21, reused 0, skipped 0;
selected timing coverage complete for these two suites. Internal adversarial
fixtures intentionally fail/skip to prove the outer collector assertions;
subprocess missing-module fixture exits 1 as asserted. An unwritable advisory
output leaves the successful suite exit 0. Enabling the collector preserves
suite selection, stdout and verdict compared with ordinary TextTestRunner.
Commit hook ran Guardian whole-tree gate: 88 checks passed, with pre-existing
report-only findings. No independent full native gate was launched; S10 owns it.
No native build or timing admission was needed for these Python-only changes.
Zig pin remains `0.17.0-dev.1683+5ceec001b`.

Source SHA-256 values are in source-hashes.txt. Producer artifact hashes:

- report-telemetry.json: `844bb85f68996d159d551c503b11f53d635c705e90a6f16585d99ae8700f5a9a`
- telemetry-tests.json: `e62ff982e15cfd4f152c79c333de664835a1ebfaae86fb875cae1b7b82b1851f`

Durations/CPU/RSS in JSON are operational observations on this shared host,
not isolated comparisons. Cold/warm/edit paired timing, median/p95 and memory
regressions are unavailable/unqualified in this lane. No deterministic counter
reduction or developer-loop latency improvement is claimed.

Remaining acceptance:

1. Coordinator registers the new meaningful tests and dependency closure,
   reviews configuration fingerprint changes, and adds explicit unknown test
   telemetry on every existing action/member. Current action inventory export
   and final all-action report coverage belong to coordinator/S10.
2. Adopt the supported producer for compatible Python unittest members. Preserve
   script-specific setup/CLI in members requiring direct runner integration.
   The two archived real suites establish an executable producer, not automatic
   complete production coverage.
3. S08 integrates precise dirty-authority causes and coordinator wires them on
   failed snapshot checks without changing selection/output/reuse behavior.
4. External Guardian and jointly owned guest runner need supported per-test
   event hooks. Their individual-test durations remain unknown today. S01 does
   not claim DL1 complete while those current-action coverage gaps remain.
5. S10 compares final integrated selection/reuse and independent executions,
   captures qualified latency/counter evidence and runs complete gates.

Integrate implementation first, then coordinator registration/report wiring and
S08 diagnostics; budget consumers can use validated passed fresh rows only.
The conservative rejection of inference from Zig summary/slow-test messages is
intentional: summary counts and timings cannot prove every individual case ran.

Integration follow-up adds static build-compatible
`--output-directory-env MYLANG_TEST_TELEMETRY_DIR`. A new adversarial subprocess
test proves actual environment-enabled sidecar and environment-absent ordinary
verdict; final telemetry suite now has 10 selected/executed/timed tests, all pass.
Combined final supported coverage is 22 tests. The refreshed JSON/log/source
hashes supersede telemetry-tests.json hash and its 9-test count above. Exact build
argv and per-member attachment instructions are in shared-patch-requests.md.
