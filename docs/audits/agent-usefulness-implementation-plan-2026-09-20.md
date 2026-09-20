# Making mylang more useful to coding agents

Status: **proposed implementation plan; this document implements no features**.
Prepared 2026-09-20 from repository inspection and a small installed-compiler probe.

## 1. Outcome

Make it easier for an agent to understand an unfamiliar project, implement a
bounded change, and establish that the resulting behavior is correct. Also make
mylang a practical language for the small reusable tools an agent creates while
working on other projects.

Deliver four improvements:

1. Dependable, bounded context for a symbol, source location, or diagnostic.
2. Native invocation of an exported function using structured inputs and outputs.
3. Typed-hole reports that describe the implementation obligation precisely.
4. Measured improvements to the complete read/edit/check/test loop.

The guiding design principle is to expose facts the compiler already knows,
with their provenance and limitations. Keep ordinary source files, the current
language semantics, and existing verification infrastructure.

## 2. Starting point

These are starting observations, not a substitute for checking the selected
implementation baseline. The inspected working tree contains substantial ongoing
changes; a Git revision alone does not identify its contents.

| Area | Existing foundation | Work proposed here |
| --- | --- | --- |
| Navigation | `index-project`, `list-interfaces`, `tests-for`, `api-diff`, and `scripts/navigate.py` | Compose focused answers with consistent fact status, bounded output, and freshness checks. |
| Project feedback | `scripts/project.py` combines navigation and declared verification; the declaration-store experiment has bounded context queries | Reuse these mechanisms in the ordinary file workflow; no mandatory source database. |
| Documentation | `--features`, checked schemas, embedded standard modules, executable documentation | Provide one current, compiler-pinned entry point and remove misleading current-to-historical routing. |
| Function execution | Native guest tests validate typed inputs, select reachable code, and execute in bounded child processes | Generalize the invocation machinery to ordinary public exports, then add a practical copied managed-value boundary. |
| Unfinished code | `todo[T]()` blocks publication; declaration inspection remains possible | Retain and expose the local facts needed to fill a hole. |
| Incrementality | Persistent checked-body/native caches, selective tests, receipts, and phase/work reports | Measure complete maintenance tasks and optimize the dominant remaining work. |

The review probe used compiler identity
`7d3d52d755a44aa7f8dc73a2792d223b6f6ccb408aced4b2130061cd8c05c79a`.
A module containing `todo[int]()` produced `E_TYPED_HOLE`, while
`list-interfaces` succeeded and printed declarations. Its incomplete bodies also
caused interfaces to display the full effect vocabulary alongside `ceiling()`.
This motivates distinguishing an unknown inferred effect set from a declared
ceiling; it does not establish a soundness defect in effect checking.

The README's compiler-derived-reference link leads to a historical page whose
Python generator was removed. Current capability discovery should not require
reconciling that history. The [typed JSON guide](../typed-json.md) also explicitly
records that arbitrary exported-function invocation was removed with the
interpreter; the current execution route is through native tests.

Relevant foundations:

- [Navigation](../tooling/navigation.md), [project feedback](../experiments/project-workflow.md), and [store sessions](../experiments/declaration-store-session.md).
- [Typed JSON](../typed-json.md), [guest tests](../tooling/guest-tests.md), and [effects](../effects.md).
- [Typed holes](../typed-holes.md) and [diagnostic recovery](../diagnostic-recovery.md).
- [Caches](../tooling/caches.md) and [previous velocity implementation status](velocity-implementation/final-status.md).

## 3. Scope and implementation rules

- Extend the existing checker, semantic index, native build path, and native
  execution machinery. No second frontend, interpreter, or independently inferred
  semantic graph.
- Keep QBE as the required implementation route for these features. An optional
  backend experiment is not a prerequisite or a reason to change language rules.
- Context queries are read-only. They never execute tests, edit source, apply a
  suggested fix, or infer that reachable tests establish behavioral coverage.
- Preserve current checked-result, effect, mutation, nominal-identity, and
  capability rules. Reporting incomplete information must not weaken checking.
- Preserve unrelated working-tree changes. Establish a content-pinned baseline
  before implementation, and use an isolated checkout/build directory when needed.
- Proposed command spellings below are design defaults. Freeze their exact
  contracts in W0 before implementation and document any adjustment once.
- Do not add an MCP server, mandatory daemon, source-store migration, editor
  integration, or broad package ecosystem as a dependency of the first release.
- Do not make automatic repair suggestions or an architecture score part of the
  initial treatment. Evaluate them separately if later evidence justifies them.

## 4. Release sequence

Size is relative implementation scope, not a calendar estimate.

| Package | Deliverable | Depends on | Size |
| --- | --- | --- | --- |
| W0 | Verified baseline, protocol decisions, and runnable task pack | — | Small |
| F1 | Honest interface facts and current agent reference | W0 | Medium |
| C1 | Focused context command over existing compiler facts | F1 | Medium |
| I1 | Native invocation for the existing copied-value subset | W0, F1 | Medium |
| I2 | Managed data needed by useful tools | I1 | Large |
| I3 | Explicit capability provisioning for invocation | I1 | Medium |
| H1 | Structured typed-hole obligations and context integration | F1, C1 | Medium |
| E1 | Maintenance and tool-authoring comparisons | W0; each measured package | Medium |
| P1 | Targeted latency improvements selected by measurements | E1 profiling | Variable |

Recommended execution order: W0 → F1 → C1 → I1 → I2 → H1 → I3. Capture
measurements throughout; start P1 when profiling identifies a concrete target.
Each package has its own correctness acceptance and can land independently of a
productivity claim. The useful-tool milestone requires I2; a scalar-only I1 is
infrastructure, not completion of that outcome.

### W0 — Establish the baseline and shared contracts

1. Capture selected source contents, existing modifications, compiler identity,
   toolchain/backend identities, mode, and relevant environment. Use the
   repository's pinned Zig toolchain; do not update it as part of this work.
2. Reproduce the incomplete-interface probe, typed-hole diagnostics, current
   navigation limits, and the actual native copied-value codec matrix. Mark
   already-fixed observations as such rather than reimplementing historical gaps.
3. Preflight two current applications and their independent acceptance checks.
   Prefer the S-expression port and a second application that works with this
   exact compiler. The M3 planner snapshot was blocked by obsolete syntax;
   select a compatible snapshot or another application before spending on trials.
4. Record baseline command timings and a few complete maintenance sessions.
   Preserve raw command events and output sizes, including unsuccessful attempts.
5. Freeze versions, required fields, exit statuses, size limits, and compatibility
   rules for the reference, context, invocation, and hole reports. Freeze the
   copied-value matrix separately from the host/native ABI.
6. Create an implementation ledger beside this plan with package status, source
   identity, evidence paths, and any deviations. Creating that ledger belongs to
   implementation; this planning task does not manufacture acceptance evidence.

**Acceptance:** both application baselines pass; the focused observations are
reproducible; protocol decisions and unsupported cases are explicit. No agent
productivity experiment begins against a nonworking baseline.

### F1 — Make compiler facts unambiguous and current

**Entry points:** `src/interfaces.zig`, `src/main.zig`, `src/navigation.zig`,
`src/schema_report.zig`, `src/features.json`, and `src/standard_library.zig`.

Separate three concepts everywhere they are reported:

- A declared ceiling: present or absent in source.
- An inferred effect or mutation summary: known only when the necessary checking
  completed successfully.
- Analysis status: checked, declaration-only, lexical-only, or unavailable, with
  the reason when unavailable.

Keep conservative internal masks if they are needed for checking. Render them as
unknown or conservative bounds when appropriate; never label an internal
fallback as an inferred fact. In particular, an empty declared ceiling remains
visible when a body contains a hole, while the inferred set is unavailable.
Apply the same distinction to return origins and test relationships.

Add a small compiler-derived reference entry point, provisionally
`mylang reference --query TERM --format=text|json`. It should expose current
syntax examples, builtins, embedded standard-library signatures, supported
boundaries, and relevant exclusions. Derive signatures and feature status from
the selected executable. Keep explanatory prose curated, versioned, and shipped
with that executable; execute its examples in the documentation gate. The command
must work outside the source checkout.

Route README/current-guide onboarding to this current surface. Mark historical
pages consistently and retain their evidence. This is a focused correction of
current entry points, not a rewrite of every experiment report.

**Acceptance:** incomplete and complete modules render distinguishable facts;
JSON uses explicit status/null fields rather than an empty set for unknowns;
existing checked contracts remain unchanged; reference examples match the
selected binary even when the surrounding checkout differs. Add feature pointers
and executable documentation with the implementation.

### C1 — Answer a focused change-context question

Proposed usage:

```sh
mylang context app/main.my --symbol 'model::validate' --context-bytes=8192
mylang context app/main.my --at 'model.my:42:12' --format=json
mylang context app/main.my --symbol 'model::validate' --against=api-baseline.json
```

The command composes existing navigation, interface, test-reachability, and API
comparison logic. Share implementations with existing commands; do not spawn a
full frontend independently for every section. Prototype selection/rendering
against the existing client if useful, then expose the maintained command through
the installed toolchain without requiring the repository's Python scripts.

Return, in deterministic priority order:

1. The requested declaration or diagnostic, its source span and relevant body.
2. Its signature, declared bounds, checked effects, mutation footprint, and
   return-origin information, each with fact status.
3. Definitions of directly relevant nominal types and generic requirements.
4. Resolved direct dependencies and caller signatures.
5. Direct and transitive test callers, labeled as static reachability.
6. Interface changes when the caller supplies an existing API baseline.

Support locating a diagnostic through its source span in the same source
snapshot. Report ambiguity instead of silently choosing a similarly named symbol.
For incomplete projects, return available declarations/local facts and the reason
resolved relationships are unavailable. Never reuse old checked edges as though
they described the current broken source.

The `agent-context-v1` envelope includes compiler/source identities, selector,
analysis status, section records, emitted byte count, and omissions by section.
Define the budget over the complete serialized response, including JSON escaping
and metadata. Use an 8 KiB default and a documented minimum large enough for the
envelope; retain complete records and valid UTF-8. If the requested declaration
does not fit, return its signature/location and an explicit continuation query.
Do not silently truncate a contract into a misleading fragment.

Use source identities and existing invalidation mechanisms for caching. Detect a
source change while assembling the response and return a stale-snapshot result;
do not combine facts from different versions. Keep the first version one-shot;
consider persistent service reuse only after measuring its contribution.

**Acceptance:** useful answers on both real applications; exact budget adherence;
deterministic ordering; ambiguous and missing selectors handled; partial-source
facts labeled; private helper edits invalidate relevant answers; source changes
during collection reject. Existing navigation/test semantics remain unchanged.

### I1 — Invoke an ordinary export through the native runtime

Proposed usage:

```sh
mylang invoke app/main.my --function 'app::normalize' --describe --format=json
mylang invoke app/main.my --function 'app::normalize' --input=request.json
```

`--describe` returns the selected function's checked argument/result contract,
wire representation, effects, required capabilities, limits, and invocation
eligibility. A checked signature is not necessarily serializable: explain the
first unsupported type path rather than advertising an unusable callable tool.
An optional generated JSON Schema describes the supported wire subset, including
decimal-string integers; it must not be confused with the language-contract graph.

Extract reusable invocation components from `native_test_execute.zig`,
`native_test_wire.zig`, `native_test_session.zig`, and the existing QBE
build/codec modules. Preserve the native test runner's behavior and receipts.
Select an exported concrete function without a `test_` prefix or expected-value
fixture. An exported concrete wrapper is the initial route for generic functions.
Support a library entry without requiring the user to add a dummy `main`.

I1 starts with the existing verified copied-value subset. Describe exactly which
types work at W0, and reject all others before executing guest code. Use named
arguments checked against the selected signature; reject missing, extra, duplicate,
or malformed inputs. Reuse the exact-integer representation and nominal identity
validation from the existing boundary.

Execute in a fresh native child with bounded input/output, wall time, memory, and
the existing execution quotas. Initially accept only exports whose effects and
signature need no external authority. Managed allocation and permitted mutation
of copied inputs do not themselves require an external grant.

Write one `native-invocation-v1` JSON response on stdout. Keep compiler diagnostics
and captured guest output separate from that channel. Distinguish a returned
language `Result.Err` from a runtime trap, timeout, invalid request, and host/setup
failure. A returned `Err` is a completed invocation and remains a typed result;
define exit 0 for completed calls, 1 for source/runtime failure, and 2 for
request/setup failure. Include source/compiler/schema identities and effective
limits in the response/report.

Reuse compilation artifacts, but execute every requested invocation. Do not
reuse cached test successes as function results, automatically retry a call, or
claim that process isolation constrains arbitrary trusted foreign code. Publish
the result only after validating the complete child response. Result publication
does not imply rollback of external side effects in later capability-enabled calls.

**Acceptance:** invoke a non-test public function without modifying it; validate
integer boundaries and nested values; distinguish `Err`, traps, and timeout;
reject private/unknown/generic-uninstantiated targets and unsupported type paths;
retain source-mapped failures; keep stdout parseable; preserve existing tests;
repeated calls execute while unchanged native artifacts are reused.

### I2 — Add useful copied managed values

Add support in this order: immutable `str`, `list[T]`, then combinations with
value records, `Option`, and `Result`. Support compositions according to the
verified language storage rules; do not silently relax must-handle restrictions
to accommodate a codec. Existing scalar and fixed-shape encodings remain stable.
Make `bytes` and `dict[str,T]` separate follow-ups when a concrete tool requires
them; specify their wire encodings before implementation.

This is a copied serialization boundary, not permission to pass arbitrary managed
objects through the C ABI. Decode into fresh guest-owned storage, retain every
temporary GC root, copy the result out before teardown, and release partial values
on failure. Input JSON describes value trees and introduces no shared aliases.
Repeated acyclic output references serialize as repeated values; cyclic output
fails with a located/type-path error. Bound expanded output size and traversal
work, not only the number of distinct heap objects.

Validate Unicode and embedded NUL handling, collection lengths, nesting depth,
total nodes/bytes, allocation failures, and integer ranges. Reject classes,
capabilities, resources, callbacks, and private-domain construction until an
explicit corresponding boundary contract exists. Version capability/schema
metadata and native codec cache keys when supported shapes change. Audit both
the parent codec and native runtime path; host-side validation alone is insufficient.

Deliver two small examples that use the invocation route without handwritten
JSON plumbing: a structured-record validator returning useful errors, and a
text/list transformation returning a typed report. Give them independent expected
results and document how an agent discovers their contracts and calls them.

**Acceptance:** nested Unicode/list/record/result round trips; empty and large
bounded values; no leaked references across repeated calls; `--gc-stress` and
allocation-failure coverage; malformed/cyclic/oversized cases reject cleanly;
both examples work through the public CLI. Record preparation and per-call cost.

### I3 — Supply capabilities explicitly

Reuse the existing grant resolution and capability runtime rather than adding a
new authority system. For `invoke`, make no external grants the default, and
document this difference from ordinary `run`. Missing required grants reject
before execution. Describe capability parameters separately from JSON data
parameters; JSON can never mint them.

The generated entry shim provisions declared capabilities, preserving the rule
that only an entry shim constructs them. Stage support by capability kind;
initial filesystem/stream grants are sufficient for a first useful slice. Keep
unsupported kinds explicit. Integrate existing restrictions for later network,
environment, clock, and entropy support rather than inventing parallel rules.
Host calls remain subject to their existing registration/trust contract.

**Acceptance:** a fixture reader can access its granted directory, denied access
fails, capabilities cannot arrive in JSON or escape in a result, guest printing
cannot corrupt the result channel, and effective grants are recorded without
serializing environment values or other secrets into receipts.

### H1 — Expose the obligation at a typed hole

**Entry points:** `src/sema.zig`, `src/generic_bodies.zig`, `src/diagnostic.zig`,
`src/diagnostic_output.zig`, and `src/typed_holes_test.zig`.

Retain a bounded context snapshot when ordinary or symbolic generic checking
reaches a valid `todo[T]()`. It contains the declared result type, enclosing
callable, available initialized bindings and types, generic requirements,
declared effect ceiling, and permitted mutation footprint. Include a contextual
expected type only when the checker actually knows it; expected-type inference
is not a new language feature in this package.

Copy the necessary facts into storage with a defined diagnostic lifetime before
failed-function recovery clears checker state. Preserve source locations and
nominal identities. Mark unavailable facts explicitly, especially transitive
effect summaries that require successful whole-program checking. Never expose
uninitialized, consumed, or out-of-scope bindings as usable inputs.

Keep the default error concise and the stable `E_TYPED_HOLE` code. Expose details
as a versioned structured obligation or through `context --at`; larger snapshots
may be collected on request to bound ordinary-check overhead. Associate an
obligation with function identity, source range, and snapshot identity. Old line
numbers alone must not identify a hole after edits.

An on-demand relevant-function list may use exact type relationships and checked
effect compatibility. Label declarations whose bodies are unverified. Defer
implementation synthesis and heuristic repair prose; source semantics and the
requirement to resolve holes before publication remain unchanged.

**Acceptance:** ordinary and uncalled generic holes expose correct local facts;
separate invalid functions retain independent diagnostics; incomplete global
facts stay unknown; formatting preserves holes; filling a hole removes its
obligation; stale queries reject. Do not promise recovery for multiple holes in
one function beyond the checker's existing safe recovery boundaries. Production
builds continue to reject all holes in their selected program.

## 5. E1 — Evaluate complete work

Use the existing velocity/project-invocation infrastructure and independent
application oracles. Preserve historical cohorts. The
[M1b readout](m1b-diagnostic-feedback-readout-2026-09-19.md) did not establish a
repair benefit from suggestions, and the
[elegance findings](../../experiments/elegance-metrics/findings-2026-09-19.md)
did not validate dependency-graph propagation cost as a proxy for agent effort.
Treat both as reasons to measure direct outcomes.

Prepare distinct development and held-out tasks in three families:

| Family | Example | Primary comparison |
| --- | --- | --- |
| Maintenance | Repair a parser edge case or change a validation rule across modules | Existing workflow vs focused context, with identical verification. |
| Incomplete implementation | Fill a helper under an effect/mutation contract | Existing hole diagnostics vs structured obligation context. |
| Small tool authoring | Validate records or transform text into a structured report | Existing mylang CLI plumbing vs native invocation; a matched Python baseline may be added as a separate comparison. |

Freeze task briefs, sources, compiler, prompts, model settings, tools, cache
policy, budgets, and grading before each cohort. Randomize matched assignments
and vary one feature at a time before testing the combined workflow. Both arms
receive accurate documentation and equivalent ordinary tools. Pilot on development
tasks to establish outcome headroom and variance, then preregister sample size and
decision thresholds before held-out runs. Do not treat repeated attempts at one
task as independent task diversity.

Retain failed attempts, retries, timeouts, and delivery failures. Record:

- Independent behavioral acceptance and unintended changes.
- Wall time to accepted completion, with unsuccessful attempts reported separately.
- Agent input/output tokens and tool-response bytes when directly available;
  otherwise mark missing values rather than inventing a token estimate.
- Failed compiler/test invocations and the underlying processes inside bundled
  commands, so a wrapper cannot manufacture an apparent reduction.
- Time reading context, waiting for tools, checking, compiling, linking, and
  executing tests; distinguish overlapping work from wall-clock totals.
- Cold, warm-unchanged, and warm-after-edit behavior, plus work/reuse counters.

Feature correctness and productivity are separate verdicts. Recommend a default
workflow change only when the held-out comparison meets its preregistered useful
improvement threshold without an unacceptable correctness loss. Report uncertainty
and inconclusive outcomes; do not claim noninferiority from a small sample with
zero observed failures. An unsuccessful treatment remains useful evidence.

## 6. P1 — Improve the measured bottleneck

Keep the existing sub-500 ms check-feedback and sub-1 s affected-test objectives
as reference targets, with project size, machine, mode, and cache state stated.
They are targets, not assertions about this checkout.

Use `--timings=json`, work reports, and complete command wall time to determine
whether the next improvement belongs in source discovery, dependency keys,
checking, context serialization, lowering, linking, process startup, or execution.
Improve one dominant component per change and retain semantic/cache equivalence
checks. A persistent process, lazy lowering, or batched execution requires its own
measurement; none is automatically the answer.

**Acceptance:** compare the same frozen workloads before/after with retained raw
samples and noise controls; unchanged, implementation-edit, signature-edit, and
import-edit results agree with fresh execution. Demonstrate a reduction in actual
work and end-to-end latency, or report that the change failed its objective.
Small projects must not absorb a large fixed cost to improve a scale benchmark.

## 7. Verification and completion

For implementation packages, add focused tests at the relevant semantic, CLI,
native execution, and cache boundaries. Test observable contracts rather than
mirroring internal helper implementations. Register new tests in the maintained
suites. Use the existing `test-units`/`test-cli` filters while iterating, then run
the required integrated gates for the completed scope with the pinned toolchain.
Native invocation and codec work require native build/test coverage and GC stress;
all public commands require feature/documentation updates and executable examples.

Shared regressions to preserve: selected-provider tests with unfinished unselected
production bodies, checked effects/mutation, source-mapped diagnostics, empty-test
selection failure, exact cache invalidation, and existing typed JSON compatibility.

After any task that exercises Guardian, append concrete feedback to
`~/ai/canopy/guardian-zig/FEEDBACK.md` and commit that feedback in the Guardian
repository, following the user's global instructions. A documentation-only task
that does not exercise Guardian does not need a feedback entry.

Complete each package with its implemented behavior, source/compiler identity,
commands and evidence, remaining limits, and measurement verdict recorded in the
ledger. The plan is complete when all four outcomes have implemented acceptance
evidence and an honest evaluation readout; a favorable productivity finding is
not something implementation can guarantee.
