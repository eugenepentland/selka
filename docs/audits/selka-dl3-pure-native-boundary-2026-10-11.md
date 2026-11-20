# DL3 independent native tooling boundary

Base: `65776b95dffb653628a05cfdda55d487646eeba7`. This change builds
`src/tooling_root_test.zig` independently, with provider `tooling-units` and
verification cohort `tooling_unit`. It carries 27 existing named tests:
documentation text contracts (7), private temporary input probing (2), fix edit
selection (1), phase-record arithmetic (1), and synthetic invalidation reports (16).
The root adds one unnamed import/discovery test, so its runner reports 28 tests.

The implementation closure contains exactly 11 local Zig files, listed in
`build_test_inputs.zig`. It imports only these modules and `std`; it has no compiler
root alias, build identity module, guest compiler options, component packages,
embedded production runtime, repository fixture reads, subprocesses or live counter
collectors. Input probing creates and removes its own temporary files. Timing tests
accumulate supplied durations rather than reading the clock.

Documentation tests originally lived inline in `doc_coverage.zig`, which the unit
root also imports indirectly through reference and documentation command tests.
Their extraction into `doc_coverage_test.zig` avoids duplicated execution. All
exercised functions were already public, production function text is unchanged,
and original SPEC tags and assertion bodies are preserved. The other four test
files move by root import only. The larger unit root retains diagnostic, guest,
command, host and fixture coverage.

The cached tooling run deliberately bypasses `cached`, `bounded` and `focused`,
whose existing wiring also binds or installs compiler/component artifacts. It
consumes its own executable, source manifest and live environment manifest only.
The coordinator explicitly selects `artifacts = ["tooling-units"]`. Guardian and
the pinned Zig/standard-library implementation remain qualified build tools;
the compiled executable digest binds their actual output. Whole-compiler producer
identity has not been narrowed.

## Coverage and developer commands

The new root participates in `test`, `test-compile`, `test-runtime-audit`, prepared
artifact export, Guardian orphan/test reachability and static input coverage.
Unfiltered `test-units` and `test-units-sharded` include both roots. A filtered
invocation of these two targets selects the compiler root; tooling filters use
`test-tooling-units`. No-match remains a failure.

The focused wrapper supports `tooling NAME` and routes explicit moved namespaces
from `units`, translating old `doc_coverage.test.` names to
`doc_coverage_test.test.`. Broad filters remain scoped to their requested root;
the wrapper prints that scope for `units`. Affected selection discovers both roots
and plans a separate tooling action. Its selection remains a heuristic inner loop.
New focused-wrapper regression tests are required by the existing affected cohort.

Static tooling coverage also rejects a newly imported local source outside the
exact recipe. Adding methods to imported test files changes the binary/manifest;
new test files must be imported and declared. Renames/deletions change imports or
cause missing-file failures. Orphan/reachability checks continue to reject unattached
source tests. This is not an exemption from global discovery or gate accounting.

## Focused qualification

- Admitted `zig build test-tooling-units --summary all`: 28 passed, zero failures
  or skips; only the independent native test root compiled.
- Admitted `zig build verification-plan --summary all`: 45 cohorts, 94 required
  actions, all 94 registered, no unknown actions. `tooling_unit` is cacheable and
  selects only `tooling-units`.
- Focused `profile` selection passed its named test plus import block; an
  invented no-match filter failed with an aborted verdict as required.
- Admitted cached tooling cohort: first execution 28 passed; unchanged second
  invocation reused the Zig test verdict.
- Named-test source inventory comparison preserves every declaration: 1,560 in
  the baseline local import graph equals 1,533 remaining plus 27 tooling tests,
  with no intersection. These are static source declarations, not a claim about
  the larger compiled runner's runtime count. Complete runtime gate parity remains
  for the integration owner.
- Input coverage and its self-test pass, including an undeclared transitive-source
  negative case. Affected mapping: 14 passed; focused wrapper: 17 passed. Budget
  helper tests: 13 passed after bringing in the already integrated helper commit.
- Source matrix in [the structured evidence](selka-dl3-pure-native-evidence-2026-10-11.json):
  an unrelated lexer edit leaves the tooling manifest identical; editing its
  transitive `invalidation.zig` changes it; adding a test import changes its root.
  Probes used private copies and did not modify production compiler files.

The budget helper is added to the verification-cache, fuzz and Juice-cache recipes
because the latter import `verify_cache` transitively. The retained-session recipe
already covers all `scripts/`. Its regression script is wired into verification
self-tests. Bootstrap source/semantic work was not changed.

## Directional invalidation and limits

A frontend/Core implementation edit can preserve this tooling executable and input
manifest. A tooling test edit still invalidates the larger unit cohort through its
conservative `src/` fixture recipe, even after the unit executable no longer owns
that test. Source-reading lint/navigation/fixture tests make an automatic global
reduction unsafe; no symmetric independence is claimed.

Common build configuration, `build.zig`, execution implementation, environment and
tools remain conservative identities. Full preparation still builds all required
native artifacts, and a new executable adds some cold compilation/startup work.
The focused build's observed peak was 165 MiB; this is an operational observation,
not a comparative memory budget or isolated latency result. No cold/warm speedup,
p95 target, whole-gate improvement or semantic producer narrowing is claimed.
The integration owner runs the complete gate and reconciles this boundary with
localized inventory contracts and report-only budgets.
