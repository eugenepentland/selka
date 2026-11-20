# Agent handoff: development velocity fixes

Prepared 2026-09-15. This is an execution guide for the proposed
[implementation plan](development-velocity-implementation-plan-2026-09-15.md).
No implementation package has been completed by writing this guide.

## Start here

Give one integration agent **W0** first. It establishes a current baseline,
verifies which findings still exist, freezes shared contracts, and creates the
execution ledger. Then give separate implementation agents the IDs below, using
distinct worktrees and one owner per shared source file.

The plan recommends preserving managed collection sharing and adding checked
mutation contracts. This is a proposed default, not an assertion that the user
explicitly chose it. Incorporate any subsequent user choice before starting M1.
The entire contract in plan section 3 matters: merely adding an effect bit does
not implement read-only inputs or prevent writes through aliases.

## Initial assignments

After W0, the first independent assignments are:

| Agent | Package | Concrete result |
| --- | --- | --- |
| Formatter | F1 | Canonical formatting changes spacing/layout; `--check` detects differences; semantic/comment preservation tests pass. |
| Runtime diagnostics | D1 | Native bounds failures report original index and length in text and structured JSON, preserving trap behavior and stacks. |
| Compiler observability | C0 | Reports distinguish actual query reuse from fingerprint equality and identify work performed. |

Start E1 when a slot is free. Keep the integration agent responsible for merging,
shared-file ownership, current contracts and combined acceptance. The plan's wave
table is the dependency authority; this table does not override it.

## Package index

| ID | Assignment | Prerequisites |
| --- | --- | --- |
| W0 | Baseline, shared designs, ownership and ledger | None |
| E1 | Directional callable effect assignability and readable diagnostics | W0 |
| E2 | Required exported ceilings, migrations and stable public effect fingerprints | E1 |
| M1 | Complete mutation operation facts, metadata, source contract and validation representation | W0; serialize effect/type ownership with E1/E2 |
| M2 | Deep origin/alias enforcement, call permissions and callback mutation substitution | M1, E1 |
| M3 | Corpus migration, activation, user docs and measured ergonomics | M2, E2 |
| F1 | Canonical formatter | W0; new mutation grammar integration follows M1 |
| D1 | Structured native trap details | W0 |
| D2 | Current documentation and feature reconciliation | Each relevant feature; final pass after integration |
| C0 | Actual work/reuse counters | W0 |
| C1 | Per-function eligibility/dependencies and stable identity remapping | C0, E2, frozen M1 metadata |
| C2 | Persistent checked-body reuse in ordinary commands | C1, final M2 metadata |
| C3 | Symbolic generic and concrete specialization reuse | C2; named-constraint baseline fixes verified |
| P1 | Select a test provider before checking unselected production bodies | E2, M3 |
| C4 | Shared cached test preparation and lazy native lowering/emission | C3, P1 |
| A1 | Required configured import policy in ordinary project commands | W0; coordinate project/CLI edits |
| S1 | Repaired representative workloads, consistent limits, scale and maintenance evidence | C0 initially; integrated core for final evaluation |

## Reusable implementation-agent prompt

Replace the placeholders before assigning it:

```text
Implement package <ID> from:
  docs/audits/development-velocity-implementation-plan-2026-09-15.md

Read that plan's package, its shared-contract sections, and:
  docs/audits/development-velocity-agent-handoff-2026-09-15.md
  docs/audits/development-velocity-proposals-2026-09-15.md

Baseline commit: <SHA>
Assigned worktree/branch: <WORKTREE>, codex/velocity-<ID>
Dependency commits already integrated: <SHAS>
Exclusive shared-file ownership: <FILES>
Current execution ledger: <PATH>

Implement the package through its acceptance criteria, including source, meaningful
tests and current documentation. Inspect the actual baseline first: audits are
dated evidence, not permission to reintroduce removed code or duplicate a fix.

Preserve unrelated work. Use the pinned Zig toolchain and the QBE native path.
Do not widen this assignment into the plan's follow-on roadmap. Where a required
shared file has a different owner, coordinate its contract/patch through the
integrator rather than modifying a shared checkout. Build and test in your own
worktree with your own installed compiler; record its identity.

Keep exact type identity distinct from directional assignability. Keep real
cache reuse distinct from unchanged fingerprints. Keep inferred implementation
facts distinct from declared public guarantees. Do not claim an alias is fresh
when its origin is unknown, and do not weaken a guarantee to make tests pass.

Run focused checks and the relevant package acceptance; update SPEC/features/docs
with the implementation. Follow the user's Guardian feedback/commit instructions
whenever a gate is exercised. Coordinate writes to that shared feedback log.

Return the completion report described in the handoff. Mark acceptance criteria
individually as met or remaining. If the task is incomplete, name the concrete
remaining work rather than declaring the package complete.
```

## Reusable integration-agent prompt

```text
Execute W0 and coordinate the core release in:
  docs/audits/development-velocity-implementation-plan-2026-09-15.md

First inspect the current checkout and select a baseline that includes the intended
preceding fixes. Preserve all unrelated/uncommitted work. Record compiler/tool
identities and baseline acceptance. Recheck the dated audit's key behaviors.

Create the execution ledger and freeze shared source/protocol contracts. Incorporate
the user's latest decisions, especially mutation semantics. Assign one owner per
file per wave and use separate worktrees. Start F1, D1 and C0 independently after
W0; schedule the rest according to the plan's actual dependencies.

Maintain one shared semantic implementation. Reconcile changes to schema, generic
constraints, effects, mutation origins, cache identities and native ABI together.
Do not accept a task merely because its isolated tests pass; inspect its promised
behavior, tests, limitations and interaction with already merged tasks.

For the final combined commit, run the release checklist and required current
gates, including cold/warm correctness, native execution, documentation and scale
evidence. Serialize Guardian feedback-log writers. Report met and unmet milestones
accurately; missing latency targets remain open even if correctness gates pass.
```

## Using the audit evidence

Preserve the original
[probe JSON](development-velocity-proposals-2026-09-15-probes.json) as historical
evidence. Create new fixtures/results for implementation acceptance; do not rewrite
the old record to make it appear that the compiler already behaved differently.

| Probe or finding | Target interpretation |
| --- | --- |
| `empty_effects_mutate_argument`, `record_nested_alias` | Reject the old unpermitted writes after M2/M3; add declared-mutation positive counterparts. |
| `empty_effects_reject_output`, `unhandled_result`, nominal/option errors | Preserve rejection. Mutation work must not weaken existing guarantees. |
| `unannotated_output` | A private helper still checks; E2 adds a distinct exported-helper rejection fixture. |
| `callback_effect_subset` | Accept after E1; add the forbidden reverse direction and indirect-call checks. |
| `formatter_whitespace`, `formatter_check_whitespace` | Canonical bytes change; the noncanonical input's check becomes nonzero. |
| `trap_metadata` | Preserve bounds trap/status/location; add actual index/length and JSON assertions. |
| `session_generic` | Reuse unaffected ordinary bodies after C1; C2 adds fresh-process cases; C3 adds real generic reuse. |
| `selective_tests_*` | Preserve executed/cached selection and setup-error behavior; migrate exported test ceilings after E2. |
| `ordinary_check_ignores_policy` | An unconfigured adjacent JSON file still has no magic effect; add a configured required-policy case that ordinary commands enforce. |
| `noio_allows_host` | Preserve the documented narrow meaning unless the user separately changes it; do not rename it “pure.” |
| `aliases_are_transparent`, `domains_are_distinct` | Preserve the existing distinction. A type alias is not a new nominal type. |
| `wildcard_union_added` | Preserve valid catch-all semantics; do not force every wildcard into an explicit variant list. |
| `default_257_module_limit` | Preserve baseline evidence; new supported budgets require consistent loader/test/package acceptance and resource measurements. |

## Required completion report

Every implementation agent returns:

1. **Package and commit:** task ID, branch, base SHA, implementation commits.
2. **Behavior:** concrete before/after example and exact guarantee added.
3. **Files/contracts:** touched files; public syntax, schema, ABI and cache-version
   changes; any compatibility migration.
4. **Acceptance:** one line per required criterion, with evidence and outcome.
5. **Verification:** exact commands, nonempty executed counts, compiler identity,
   native mode, cold/warm/forced state where relevant; link stored reports.
6. **Limitations:** remaining work, conservative rejections, measurements that
   missed targets, and any integration dependency still outstanding.
7. **Guardian:** whether exercised and the required feedback commit, if applicable.

The integrator verifies these reports against the combined tree and updates the
ledger. Historical audits remain unchanged; a new final audit records the achieved
state and any deferred milestones.
