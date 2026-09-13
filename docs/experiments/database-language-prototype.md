# Database language prototype proposal

Design proposal, 2026-09-09. The commands below are proposed interfaces, not implemented commands. This review produced this proposal and a read-only evidence snapshot; it did not change or run the compiler, Guardian, or evaluation participants.

Build a database-backed programming environment using Python syntax and execution first. Store functions, tests, documentation, and revisions in SQLite. Make a task-context query and an edit-with-verification command the normal development interface. Use this working prototype to decide which language semantics actually need to change.

The target is time and generated tokens to a correct change, with as few sequential agent/tool exchanges as possible. A useful small-change target is one context request, one edit request that returns completed tests, and the agent's final response. This is a design target, not a result already demonstrated.

**What the existing evaluations show**

The dashboard snapshot generated at 2026-09-09 01:01:07 UTC reports the following. The My/Python rows cover the same twelve tasks. Rust and Zig belong to a separate, incomplete cohort; their totals and medians should not be used as a four-way ranking.

| Language | Sealed attempts / planned | Recorded passes | Median delivery seconds | Completed model responses | Model output tokens |
| --- | ---: | ---: | ---: | ---: | ---: |
| Python | 12 / 12 | 12 | 79.1 | 75 | 19,681 |
| My | 12 / 12 | 12 | 179.8 | 154 | 50,276 |
| Rust | 8 / 12 | 8 | 178.9 | 64 | 31,508 |
| Zig | 7 / 12; 8 started | 5 | 231.8 | 64 | 30,078 |

The dashboard's response/token totals include whichever attempts have telemetry, including an active attempt for Zig. Its median includes sealed failures. Its Rust status says complete because all created attempts were sealed, although only eight of twelve planned tasks had been created. Use the counts above rather than that status label.

The completed My/Python cohort has a family-weighted delivery-cost ratio of 2.275. My used 2.05 times the recorded responses and 2.55 times the output tokens. These are application-window measurements; onboarding and post-seal responses are excluded. Output includes reasoning output. Completed responses are not a count of every API request or every tool operation.

Only 41.6 seconds of My's 2,318.4 seconds were inside recorded tool operations, approximately 1.8%. The remaining time combines drafting, reasoning, scheduling, and orchestration; the evidence does not separate those components. Runtime optimization has little measured headroom in this cohort. The result motivates a simpler language and interaction protocol, but does not isolate syntax from libraries, tooling, or model familiarity.

Sources: [completed cohort report](/home/epentland/ai/canopy/application-trials/development-velocity-20260908/reports/development-001-v1/report.md), [provider metadata](/home/epentland/ai/canopy/application-trials/development-velocity-20260908/reports/provider-development-001-v1/report.md), and [dashboard snapshot](/home/epentland/ai/canopy/benchmark-dashboard/public/progress.json). The companion [evidence snapshot](database-language-prototype-evidence.json) preserves the values and input hashes used here.

Later My improvements must be treated separately. The historical latest-available compilation reports 124 responses and 34,786 output tokens, but mixes builds and reasoning efforts across tasks. It is not a measurement of the present compiler: [mixed-run report](/home/epentland/ai/canopy/application-trials/development-velocity-20260908/reports/astra-latest-costs-001/report.md).

**The existing database prototype is a starting point**

[store.py](/home/epentland/ai/canopy/mylang/scripts/store.py) already implements SQLite declarations, revisions, imports, and rendering. [store_server.py](/home/epentland/ai/canopy/mylang/scripts/store_server.py) provides name-based context and transactional batches. Participants write no imports and see no source paths. Reuse those storage, revision, and verification ideas, with an adapter boundary around the My-specific parser and compiler.

The current interaction still requires `open`, individual `asset` requests, `context`, `batch`, and a separate public `check`. `batch` runs the compiler checker; it does not run the public tests. Its `passed: true` means the edit was accepted, even if `checked` is false. The replacement protocol also requires whole declarations and repeated hashes inside a JSON envelope.

In the Astra store study's five fully sealed pairs, the stored profiles contain 139 operations for the store versus 50 for files. Store operations include 52 asset reads and 25 context requests. Summed delivery times are 965.0 versus 621.9 seconds. These are descriptive observations from an incomplete twelve-task cohort with no completed source-review qualification; the failed, unmatched data-rollup attempt and all unfinished slots remain visible in the evidence snapshot. They are not a valid completed-cohort speed estimate.

The separate Opus study has eleven fully sealed pairs: 363 store operations versus 260 file operations, including 102 store asset reads. It is also incomplete and unreviewed. Do not pool these studies. Both expose an interface that makes the agent assemble its own context through many requests.

Larger information bundles alone have not reliably helped. The single-task API-capsule experiment changed eight completed responses to fifteen and 2,888 output tokens to 3,780; the API-batch experiment changed eight responses to twenty-three and 2,888 tokens to 8,432. These exploratory runs do not prove that bundling is harmful, but they rule out treating more context or a batching instruction as a demonstrated improvement. Sources: [capsule report](/home/epentland/ai/canopy/application-trials/development-velocity-20260908/reports/api-capsule-036/report.md), [batch report](/home/epentland/ai/canopy/application-trials/development-velocity-20260908/reports/api-batch-037/report.md).

**The first language implementation**

Use a documented subset of ordinary Python: functions, local variables, conditions, loops, comprehensions, assertions, numbers, strings, bytes, lists, dictionaries, and sets. Preserve Python behavior for these constructs. Use its automatic memory management and existing collection/JSON/text operations. Keep state explicit in function arguments and results. Initially, records can be dictionaries, errors can use Python exceptions, and functions can have optional annotations without a new static type system.

The application language has no imports, classes, decorators, metaprogramming, or module initialization with side effects. Registered standard-library namespaces are available directly, such as `json.loads`. Functions in the same namespace can call each other by name; other namespaces use qualified calls such as `inventory.reserve`. Namespace resolution is deterministic and rejects collisions. The CLI owns the pinned library environment; calling an unknown namespace never installs a package automatically.

Parse with Python's `ast`, validate the supported constructs, then compile and execute a revision using CPython. Pre-create namespace environments before binding functions so forward and recursive calls work. This is a fast route to a language experiment with useful libraries, not a claim that the final language must have Python's semantics. Pin the Python version; the inspected machine has Python 3.14.4. Python documents [AST parsing and compilation](https://docs.python.org/3/library/ast.html) and its built-in [SQLite interface](https://docs.python.org/3/library/sqlite3.html).

Store canonical source alongside derived syntax and dependency indexes. Source comments and documentation must survive edits; never use an AST pretty-printer as the sole preservation format. Give declarations stable internal IDs, names, and version hashes. Use ordinary revision snapshots first. Unison offers useful precedent for [database-backed code](https://www.unison-lang.org/) and [hash-addressed definitions](https://www.unison-lang.org/docs/the-big-idea/), but dependency-sensitive semantic hashing is unnecessary for this first experiment.

The minimum records are declarations, namespace bindings, dependency edges, documents/fixtures, immutable revisions, and verification results. A revision pins every declaration version, fixture, library/runtime version, and test policy. Application state is separate from code history. Export and diff can render text through the CLI when needed.

**One context request should prepare an edit**

Proposed command:

```sh
code context "Expire cache entries at the TTL boundary" --budget 6000
```

The response should contain, in this order:

1. The exact relevant task contract, project constraints, and existing verification state.
2. Complete definitions most likely to change, with an edit ticket tied to the revision.
3. Relevant tests and fixtures, including boundary cases and current failures.
4. Caller/callee signatures and the record shapes those definitions use.
5. Exact library signatures and one short, validated example where needed.
6. Explicit uncertainty and an inventory of omitted optional material.

The server does the document queries, name lookup, graph traversal, and deduplication internally. Start with exact identifiers, lexical ranking of task words against docs/tests/code, and bounded graph expansion. No extra model call or embedding service is needed for the first version. When a query is ambiguous, return a few candidates with enough source to choose among them, not just another list of names to look up.

Treat 6,000 tokens as an initial tuning value. Use the configured tokenizer when available and label estimates when it is not. Never silently cut a requested editable definition or mandatory contract halfway through to hit a budget. Include complete required material and report a budget overrun, or expose an explicit narrower target when the complete definition cannot fit the model's hard limit. Spend remaining space on optional context in relevance order. Do not include unrelated library implementations or all callers recursively.

A context ticket remembers which revision and definitions were delivered. Further requests can return only new or changed material. If the task is already known at agent launch, place this same context response in the initial task message and eliminate even the first discovery exchange. Count those frontloaded input tokens and the server's preparation time in the evaluation.

**One edit should return verification**

Proposed common interaction, using ordinary source on stdin:

```sh
code change --ticket w7 --namespace cache <<'PY'
def active(created, ttl, now):
    return now < created + ttl

def test_active_boundary():
    assert active(10, 5, 14)
    assert not active(10, 5, 15)
PY
```

The server parses all supplied definitions and atomically adds or replaces them in the selected namespace. The ticket supplies the concurrency precondition, avoiding repeated source hashes and the usual JSON-escaped source strings. A structured transport can carry several namespace/source chunks in the same transaction. Existing tests remain unless explicitly changed; same-name replacement is revision guarded.

An illustrative successful response is:

```text
r42 verified | changed 2 definitions | public 12/12 | local 1/1
```

A failed response should give the revision, failing test, exact input/expected/actual values, the relevant declaration and expression, and any newly needed API or caller context. Deduplicate repeated failures and retain the complete report under a result ID. A success should not echo all source, inventories, logs, or per-case output.

Inside the command, the server:

1. Validates the ticket and parses the entire edit.
2. Saves an immutable candidate revision and updates indexes.
3. Resolves names and compiles that revision.
4. Runs its local tests and the full declared public test workload.
5. Records a result pinned to that exact revision and returns it.

Tests run after the edited code is available, within the same tool request. The agent does not issue an edit followed by a separate run command. A malformed batch leaves the branch unchanged. A saved revision with a compile or test failure remains a repairable draft; it is never labeled verified. A conflict returns the current conflicting definitions and a refreshed ticket in the same response. Parse, edit acceptance, compilation, and test success have distinct statuses.

Do not hold a SQLite write transaction open while tests execute. Save the snapshot, execute outside the transaction, then record its result. Advance the verified branch pointer only if the revision is still current. Tests execute in fresh child environments with bounded time; clock, random, and external inputs need controlled fixtures. Hidden evaluation tests stay outside participant feedback.

Run the full public suite on every edit initially. This is simpler and reliable at prototype scale. Later, dependency-based test selection can reduce tool time, with conservative full-suite fallback for dynamic calls, changed schemas, external effects, or incomplete indexes. A prior runtime trace is not proof that an edited function cannot reach a new dependency. Cached results require the complete revision, test, fixture, runtime, and environment identity, not just the edited function's hash.

Whole-definition replacement is a good first operation, but it makes tiny repairs expensive in large functions. Add one exact, revision-guarded replacement within a named declaration next. Require the old fragment to occur exactly once and reject ambiguity; return the relevant current source on failure. This lets an agent emit a one-line fix without rewriting a 200-line function. Keep raw definitions as the main language interface rather than requiring agents to construct AST JSON.

Normal work needs `context`, `change`, and `run`; history, diff, undo, and result expansion are supporting CLI commands. The common successful edit needs no separate test or finish command. An evaluation harness can seal against the already verified revision internally.

**A bounded build and evaluation plan**

Estimated effort for an experienced implementer is two to four working days for a usable local experiment, excluding a custom type system and repeated model evaluations. This is a planning estimate, not a measured delivery time.

| Milestone | Scope | Acceptance |
| --- | --- | --- |
| First half to full day | SQLite revisions, Python adapter, raw declaration edits, namespace resolution | Create and call mutually dependent functions without source files or imports; reopen the same database and get identical behavior. |
| Next half to full day | Automatic public/local tests, compact feedback, conflict handling, history/undo | A seeded defect fails in the edit response; the repair passes there; stale edits cannot overwrite later work; old test results cannot verify a changed revision. |
| Next half to full day | Task-context retrieval and documents/tests/API indexing | One request delivers complete editable code, relevant contracts, tests, and exact helper APIs for representative tasks. |
| Remaining time | Existing harness adapter, metrics, trial preparation | Preserve the benchmark JSON contracts and test workloads, validate fixtures, and freeze the candidate before fresh trials. |

Start with three task shapes already represented in the corpus: a TTL boundary repair, inventory reservations, and snapshot-diff maintenance. Use fresh variants and include a larger namespace graph with irrelevant declarations: tiny single-function programs cannot establish a navigation advantage.

The first useful comparison has three arms: Python/files with a competent batched workflow, Python/database with the proposed CLI, and My/database with the same proposed CLI where supported. The My arm uses the existing compiler adapter. Python/files versus Python/database measures the overall workflow bundle; the two database arms help examine language/representation costs. A later file-storage backend behind the identical CLI can isolate whether SQLite itself adds value beyond semantic indexing and automatic tests.

Keep model settings, task contracts, available general-purpose library operations, public tests, and resource budgets matched. Randomize order and repeat fresh contexts. Include onboarding and preparation separately as well as application delivery. Do not inherit the historical language ranking by comparing a fresh candidate against mixed older efforts.

Record actual sequential tool-response rounds, tool operations within each round, completed provider responses, generated output tokens, returned tool text tokens, input/cache tokens, time to first edit, end-to-end delivery, and hidden correctness. Model output and tool output are different quantities: tool results become future input; model output contains code, command wrappers, prose, and possibly reasoning. Capture missing provider measurements as unknown rather than converting output bytes into model tokens.

Set the decision rule before running. A reasonable exploratory target is two tool rounds for simple repairs and at least 30% lower median model output and sequential rounds than fresh Python/files, with every required public/hidden check passing and no delivery-time regression. Count failed and unfinished tasks against their full budget and publish every attempt. A small screen selects what to test further; it does not establish broad language superiority.

The first deliverable should be a working CLI and comparable evidence. Syntax redesign, inferred static types, immutable collection semantics, semantic content addressing, selective test caches, and native execution can then be separate experiments justified by observed friction.
