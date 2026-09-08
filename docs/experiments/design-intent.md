# Design intent and traceability

The first implementation is project tooling over the existing compiler index.
It resolves requirement and decision links to real checked .my declarations;
it does not add runtime instructions or new annotation syntax.

Run the included example from the language checkout:

~~~sh
python3 scripts/trace.py report examples/intent/main.my \
  --compiler zig-out/bin/mylang --output /tmp/intent-before.json

python3 scripts/trace.py verify examples/intent/main.my \
  --compiler zig-out/bin/mylang --cache /tmp/intent-cache \
  --output /tmp/intent-evidence.json

python3 scripts/trace.py report examples/intent/main.my \
  --compiler zig-out/bin/mylang --evidence /tmp/intent-evidence.json \
  --requirement LIMIT-001
~~~

The example verification manifest names this machine's installed compiler.
Update its command path when installing elsewhere. Verification commands are
explicit project commands; the report action only performs compiler inspection.

## Records

An intent.json file has version design-intent-v1, requirements and decisions.
The files under examples/intent provide complete working records.

Requirements contain:

- A stable uppercase ID, positive revision, and proposed/accepted/retired status.
- The interpreted statement and its rationale.
- An origin with a project-relative request snapshot path, SHA-256, exact excerpt,
  kind (user-request, artifact or example), and optional external reference.
- Assumptions and non_goals, kept separate from the original request.
- implements links to module-qualified compiler symbols.
- tests links to test, parity or mutation steps in a version 2 verification manifest.

Decisions contain the same identity/revision/status/statement/rationale fields,
plus requirements, symbols, alternatives and revisit_when. Decision links are
resolved along with implementation links. There is no requirement to annotate
every helper or repeat documentation on every local variable.

Origin hashes and excerpts are checked against retained files. No network access
is needed to resolve an original request. External references are descriptive;
a retained local snapshot supplies the actual input bytes.

An accepted status is an author-declared project record, not authenticated user
approval. An agent interpretation must not be presented as the user's original
words. Both shipped examples use proposed status; the pin-role example points
to a retained task artifact, and the small limit example is explicitly fictional.

## Commands and diagnostics

Report resolves symbols and test IDs without running acceptance tests.
It reports broken links, unimplemented requirements and missing tests.
Unbuilt proposals are warnings; missing coverage for accepted requirements and
broken non-retired links are errors. Verification rejects those errors.

Use --requirement ID to see the original request, implementation, tests and
associated decisions. Use --symbol module::function to find potentially affected
requirements by following incoming checked relationships, including calls and
type uses. Filtered reports contain bounded compiler context and are marked
partial. Static reachability does not establish dynamic test coverage.

IDs survive line edits. Renaming a symbol or moving it into another module
requires updating its link; the old link fails visibly rather than silently
matching an unrelated function.

Use --previous /path/to/full-report.json to compare against a reviewed baseline.
Any changed record must increase its revision. Removed IDs must be retained
with retired status. Partial query reports cannot serve as history baselines.
Without --previous, only current-record consistency is checked; Git retains
the revision history. This tool does not authenticate reviewers or automatically
approve requirement changes.

CLI output is JSON. Exit 0 means no blocking trace diagnostics or a passing
verification manifest; exit 1 means broken links/coverage or failed tests.
Invalid input and changed-during-verification snapshots produce I_INVALID_TRACE
on stderr and exit 2.

## Evidence and caching

Verify captures the project, adds all captured files as declared verification
inputs, and runs the existing verification engine. Existing incomplete-input
jobs remain incomplete; tracing does not upgrade their trust declaration.

Evidence includes the exact intent and request hashes, compiler source snapshot,
project files, test manifest, declared tools/environment, Python executable and
trace/verification implementation identities. The original snapshot is checked
again before publication. Receipts have corruption checksums, not signatures.

Report distinguishes:

- declared: links are recorded without current passing evidence.
- linked-tests-passed: linked tests passed for current tracked inputs.
- observed-pass-untracked-inputs: tests passed, but their input declaration is incomplete.
- stale: evidence belongs to different inputs.
- failed: current recorded verification did not pass the linked tests.
- retired: the record is historical.

No state claims formal proof, measured runtime coverage, or complete satisfaction
of natural-language intent. Mutation tests can strengthen evidence but do not
turn a statement into a theorem.

Repeated verification reuses the existing successful-job cache. This first
version conservatively binds all project files to the trace verification jobs:
unrelated edits can invalidate evidence too. Impact queries are informative,
not permission to skip unlinked tests. Finer invalidation can be added after
measuring this conservative implementation.

Keep reports, evidence, caches and scheduler databases outside the source root.
The source snapshot is bounded by the existing verification tree limits.
Manifests/request records are limited to 1 MiB; retained reports/evidence to
64 MiB. Symlink and parent-directory escapes are rejected.

## Agents and combined revisions

The verify command accepts the existing scheduler options, including --scheduler,
resource budgets and priority. Identical tracked jobs share the normal cached
execution path across equivalent worktrees.

Run trace verification on the actual combined candidate checkout, using the
accepted base's full report with --previous. Source differences invalidate
branch-only evidence; passing component reports are not combined into a passing
candidate. Existing merge verification can invoke the trace command as a
required command with external output/cache paths. Keep its acceptance manifest
separate from the outer merge manifest to avoid recursive verification.

No merge, push or acceptance decision is performed by trace tooling.

## Application example and validation

The pin-role application under experiments/ergonomics/pin-roles now includes
intent.json, intent-source.md and intent-verify.json. NET-DRIVERS-001 links its
task artifact to main::net_role_finding/main::board and the role acceptance suite;
DEC-ROLE-PHASE records why reference validation precedes role findings.

~~~sh
python3 scripts/trace.py verify experiments/ergonomics/pin-roles/main.my \
  --compiler zig-out/bin/mylang --verification intent-verify.json \
  --cache /tmp/pin-role-intent-cache --output /tmp/pin-role-intent-evidence.json
~~~

Run zig build test-intent -Doptimize=ReleaseFast for the real compiler regressions.
Tests exercise successful execution and cache reuse, behavior/test/intent edits,
broken symbols and test IDs, request hashes, revision/retirement rules,
transitive impact, incomplete-input labeling, malformed receipts and scheduler
integration. The target is also included in the default interpreter test suite.
