# Declaration store experiment

Status: plan, 2026-09-08. Sections 3.2, 3.3, 3.4 and 3.5 are implemented: the
`list-declarations` command (see [declaration listing](list-declarations.md)),
the `scripts/store.py` importer, renderer and receipt chain with their
round-trip suite (see [declaration store format](declaration-store-format.md)),
the `scripts/store_server.py` session server with its verbs, budgets,
transactional batches and delta diagnostics (see
[declaration store session](declaration-store-session.md)), and the harness arm,
`StoreGateway`, practice pack, participant prompt and scripted dry run (see
[declaration store harness](declaration-store-harness.md)). The four-attempt
calibration pilot of 2026-09-08 ran; its friction is addressed here, its numbers
are used for nothing. The
rejection details now state the accepted fields of the failing operation and, for
a syntax error at a declaration header, the accepted declaration kinds and the
syntax reminder; the participant documents carry a copy-ready example of every
operation shape and verb argument; store onboarding drills `add` and `remove`
before the clock; and both arms gained the `await-handoff` bridge tool, so
practice and the timed task run in one participant context. The cohorts of
phases 4 onward remain planned. This is a workflow treatment for the
development-velocity study, not a language change. Historical evidence stays
immutable; the treatment is compared in fresh matched cohorts.

## 1. Question

Does keeping `.selka` source only in a declaration store, reachable only through a
session interface, reduce application delivery time for agents without
weakening correctness, memory safety or verification?

The treatment removes files, shells, paths and line numbers from the
participant's world. Source is a set of declarations addressed by qualified
name. The participant reads declarations under a byte budget, edits by
replacing whole declarations in transactional batches, searches through the
compiler index, and runs the same public check as today. The compiler and the
public verification adapter are unchanged; they run on private snapshots the
server renders and the participant never sees.

The treatment is a bundle: name addressing, compiler-pushed bounded context,
index search, transactional batches, derived imports and delta diagnostics.
Attributing the effect to one component is out of scope for the first cohorts.

## 2. Baseline evidence from `development-001`

The cohort is in progress. Sealed `.selka` attempts so far, from
`application-trials/development-velocity-20260908/development-001`:

| Task | `.selka` seconds | Python seconds | Bridge operations | Output retrievals |
| --- | ---: | ---: | ---: | ---: |
| little-endian-read | 110.5 | 56.0 | 8 commands, 1 check | 6 |
| atomic-transfers | 87.2 | 70.4 | 10 commands, 1 check | 0 |
| ascii-table | 189.3 | 66.6 | 14 commands, 1 check | 0 |
| data-rollup | 289.5 | 113.1 | 14 commands, 1 check | 5 |
| inventory-reservations | 239.9 | 103.0 | 13 commands, 1 check | 4 |
| mount-routing | 270.7 | 109.8 | 13 commands, 1 check | 5 |
| snapshot-diff | 302.2 | 87.8 | 17 commands, 1 check | 1 |
| record-frames | 170.2 | pending | 15 commands, 1 check | 0 |

Command argv classification puts six to thirteen operations per attempt on
reading sources and documents and one to three on edits. Every public check
passed on its first or second submission. Recorded friction: `rg` was absent in
the isolated namespace, and an 18,846-character successful check response
triggered repeated output retrievals. Both are tooling hypotheses recorded in
the journal, with no mid-cohort change. The files arm in the new cohort must
receive frozen `rg` and the current bounded feedback so the contrast isolates
the store rather than known friction.

The earlier velocity-v1 tasks show the same shape: most bytes went to reading
guides and sources, edits were single Python commands chaining exact-anchor
string replacements, and the compiler rejected nothing.

## 3. Design

### 3.1 Store

One SQLite file per attempt, `store.sqlite`, owned by the coordinator.

```text
declarations  hash TEXT PK, kind, module, name, exported INTEGER,
              canonical_source BLOB, signature, effects_json, doc
names         branch, module, name, position INTEGER, hash   (current tree)
module_meta   branch, module, header_json                     (aliases, order)
edges         branch, from_hash, to_id, kind                  (from the index)
assets        name PK, kind, bytes, sha256                    (task documents, cases)
receipts      id INTEGER PK, parent_id, branch, utc, batch_json,
              delta_json, snapshot_sha256, sha256
```

`canonical_source` is the declaration's byte range, with attached leading
comment lines, taken from the `fmt-module` output of its module. `hash` is
SHA-256 over those bytes framed by the module, kind, name and exported flag of
the row, because identical sources recur under different identities in one tree;
the implemented framing is in
[declaration store format](declaration-store-format.md). Identical declarations
share one row across branches
and receipts. A branch is the `names` rows for one label; the initial import
creates `base`, and the participant works on `work`. Receipts form a hash chain
in the same style as the study journal.

Reference hashing in the Unison style, where a caller's identity survives a
callee rename, is deferred. Source-text hashing is sufficient for one attempt.

### 3.2 Compiler support: `list-declarations`

Add one read-only CLI command that parses a module and prints JSON:

```text
{"version":"declarations-v1","module":"planner",
 "imports":[{"name":"std_math","alias":null}],
 "declarations":[
   {"kind":"struct","name":"Job","exported":false,
    "bytes":{"start":120,"end":204},"comment_start":96},
   {"kind":"fn","name":"schedule","exported":true, ...}]}
```

Kinds are exactly the constructs the top-level parser accepts. The implemented
list is alias, const, struct, enum, union, result, domain, buffer, pool,
resource, fn and host_fn; there is no separate top-level proc, record or codec
form, and any later top-level form adds a kind. `export` statements become the
`exported` flag of the named declaration. Line comments immediately preceding a
declaration belong to it. The command uses the existing parser and needs no
checking. It is a parse-only command, so a module with type errors still lists.
The implemented document also reports the module header and export directive
byte ranges, so a consumer can verify that the listing accounts for every byte.
See [declaration listing](list-declarations.md) for the exact contract.

Fallback if the Zig change is blocked: a Python top-level scanner over the
module text. The compiler command is preferred because byte literals and
comments make a textual scanner fragile.

### 3.3 Importer and renderer (`scripts/store.py`)

- `import DIRECTORY --db store.sqlite --branch base`: for each `.selka` module,
  run `fmt-module`, then `list-declarations`, then insert rows. Files under
  `.trial-public` and public case files become assets. Record module order,
  import aliases and export placement in `module_meta`.
- `render --db store.sqlite --branch work --output DIRECTORY`: write each
  module as header, imports, then declarations in `position` order with
  `export name;` lines for exported declarations. Imports are the union of
  declared imports and the module names referenced by the branch's
  declarations, sorted, with unused imports dropped. Verify the output with
  `fmt-project --check`.
- `receipt --db store.sqlite`: print the chain head.

Acceptance for this component:

- Round trip on all twelve `my-baseline` directories, the practice starter, and
  every project under `examples/` and `experiments/`: import then render must
  equal `fmt-project` output of the original byte for byte, after the renderer's
  import normalization is applied to the original as well.
- Re-import of a rendered tree produces identical hashes.
- `check-project` on the rendered tree gives the same verdict and diagnostic
  set as on the original.
- No declaration, comment line or asset is lost; counts are compared.

### 3.4 Session server (`scripts/store_server.py`)

One process per attempt, started by the coordinator, speaking JSON lines on
stdin/stdout with version `store-session-v1`. It owns the store, renders private
snapshots under `attempt/store/snapshots/NNN`, and runs the frozen compiler and
adapter on them. Every request and response is retained by the observed gateway
exactly as commands are today.

| Verb | Request | Response | Budget |
| --- | --- | --- | --- |
| `open` | `{}` | modules, declarations with kind/signature/exported/size, assets with sizes, budgets | 8 KiB |
| `context` | `{"ids":[...],"budget":N}` | for each id: canonical source, hash, callees' and callers' signatures, types used with their declarations, tests reaching it; `omitted` counts when trimmed | default 8 KiB, max 32 KiB |
| `search` | `{"text":...}` or `{"type":...}` or `{"calls":...}` or `{"effect":...}` | up to 20 hits with declaration id and 200-byte snippet; asset hits with page offsets | 8 KiB |
| `asset` | `{"name":...,"offset":N,"limit":N}` | one page of a task document or case file | 8 KiB per page |
| `batch` | `{"ops":[...],"if_match":{id:hash}}` | delta diagnostics, signature changes, affected declarations, receipt id, or rejection | 16 KiB |
| `probe` | `{"request":<json>}` | adapter stdout/stderr/exit for one request against the current branch | 16 KiB |
| `check` | `{}` | the existing public check receipt under the existing bounded-feedback policy | 16 KiB |
| `output` | as today | page of a prior response | as today |
| `finish` | `{"reason":...}` | seals as today | |

There is no `command` verb in this arm.

Batch operations are `replace {id, source}`, `add {module, source, after?}`
and `remove {id}`. Processing order: verify every `if_match` against the branch
head; render a candidate branch; parse each touched module with
`list-declarations`; reject the entire batch on any if-match mismatch or parse
failure, leaving the branch untouched. Otherwise commit a receipt, then run
`check-project --diagnostics=json` on the rendered snapshot and return the
delta. Committing on parse rather than on check lets the participant iterate
on type and ownership errors without losing work.

Delta diagnostics are computed against the previous committed receipt.
Diagnostics are keyed by code, declaration id and message, with declaration
ids derived from `list-declarations` byte ranges on the snapshot. The response
lists `new`, `resolved` and `unchanged_count`, plus mechanical notes the
compiler already emits, such as the constructor sites reported by
`E_INCOMPLETE_CONSTRUCTION` after a record gains a field.

Protected declarations are those in modules that are protected files today
(`main.selka`, `io.selka` and every asset). A batch touching them is rejected with the
same scope-violation receipt the gateway records for protected file edits, so
reporting needs no new rule.

`probe` gives the store arm the one capability the files arm gets from
`command` that matters for development: running the application on an input
of the participant's choosing. It uses the frozen adapter and the same limits.

### 3.5 Harness integration

Existing modules and the change in each:

- `experiments/application_comparison/session.py`: accept arm
  `declaration-store` alongside `main` and `language-focused`.
- `experiments/development_velocity/runner.py`: `freeze` takes an explicit
  arm list; `configuration.arms` records `comparator` and `candidate` labels,
  for this study `my-files` and `my-store`, both with language `my`. Tools
  gain the store server and importer paths with hashes. Dispatch order is
  randomized over arms exactly as it is over languages today. `prepare` imports
  the baseline and practice starter into per-attempt stores for the store arm.
  `participant` selects the gateway by arm. `begin`, `grade` and sealing are
  unchanged because `finish` renders the final branch into
  `submissions/NNN/source` through the existing submit path.
- `experiments/development_velocity/telemetry.py`: `StoreGateway` subclasses
  `ObservedGateway`, forwards verbs to the server, and retains every request and
  response. The profile adds `bytes_returned`, counts per verb,
  `context_omitted_total`, `if_match_conflicts` and `batch_rejections`. These
  fields are `null` for the files arm.
- `report.py` and `analysis.py`: identities iterate over the registered arm
  labels instead of the literal `my`/`python` pair. When a registration has no
  `arms` field, the analyzer keeps the current behavior so existing evidence
  files still validate against their hashes. The speed statistic is
  candidate over comparator, unchanged in form.
- `corpus/`: unchanged. Tasks, packs, oracles, cases and budgets are identical
  across arms.
- Practice: `practice_pack.create` gains an interface option that rewrites the
  guide for verbs. The three practice repairs are done through `batch`.
- Participant prompt: a copy of the current onboarding text with the verb list
  in place of `command`, and no mention of paths.

The public check runs the frozen adapter with `/work` bound to the rendered
snapshot for the duration of the check, exactly like today. The participant has
no verb that reads `/work`.

Confinement in the first cohorts equals today's: namespaced commands and
instruction-confined whole-agent access. The store adds completeness of the
operation log, because the interface is the only channel that returns source,
but it does not by itself stop an instruction-violating agent from reading the
attempt directory on the host. Structural enforcement, with the server running
as a separate user and the attempt directory unreadable to the participant, is
a separate hardening step and is not required for the first decision.

## 4. Pre-registration

Freeze this before any timed attempt in the new cohort.

- Study: `application-trials/declaration-store-<date>`, a new raw directory and
  journal. Predecessor evidence: `development-001` hashes pinned in the
  iteration log.
- Arms: comparator `my-files` with frozen `rg` and the current bounded
  feedback; candidate `my-store`. Same compiler, standard library, adapter,
  tasks, packs, budgets, limits and clock policy. Fresh contexts, one context
  per attempt, randomized dispatch within each pair.
- Primary outcome: capped delivery seconds ratio, candidate over comparator,
  using the existing hierarchy, bootstrap and one-sided upper bound.
  Qualification rules are unchanged: sealed, within budget, behavior and
  verification pass, timing-blind review approve or approve with nits.
- Secondary outcomes: bytes returned to the participant per attempt, operations
  per attempt, output retrievals, failed operations, batch rejections,
  if-match conflicts, abandonments, review findings, scope violations. All
  reported per task and per family. None decides.
- Quality gate: unchanged completion difference and Hoeffding bound.
- Development phase, look 0: one full cohort of twelve tasks, one pair, both
  arms, twenty-four attempts. If the ratio point estimate is within 0.85 to
  1.15, run a second development cohort with two pairs before deciding.
- Decision rule to proceed to confirmation: upper bound of the ratio at or
  below 1.00, every store attempt qualified, no increase in review rejections.
  Confirmation is then `my-store` against `python` under the existing parity
  protocol and look allocation. Failure across two development cohorts records
  the treatment as not demonstrated; the interface is not tuned mid-cohort.

## 5. Phases and acceptance

| Phase | Work | Done when |
| --- | --- | --- |
| 0 | Pre-registration text, new study directory, arm labels chosen | Journal created; predecessor hashes pinned |
| 1 | `list-declarations` command with CLI tests; `store.py` import and render; round-trip suite | Round trip passes on every baseline, practice starter, example and experiment project; re-import hashes stable; Guardian gate passes |
| 2 | `store_server.py` verbs, budgets, delta diagnostics, if-match, rollback, protected rejection; `tests/store_server.py` | Each verb has a positive and negative test; rejection leaves the branch unchanged; a batch on the slack-style migration returns the constructor-site diagnostics; response sizes never exceed budgets |
| 3 | Harness arm support, `StoreGateway`, telemetry fields, report and analysis generalization, practice pack and prompt | A scripted non-model participant completes practice and one task in both arms; `report.py` produces a full projection; old evidence files still validate |
| 4 | Pilot: two tasks, one pair, both arms, fresh agents, recorded as calibration | Interface friction recorded; no change to task content; pilot excluded from decision |
| 5 | Development cohort 1 | All twenty-four attempts sealed, graded, reviewed; report published to a new path |
| 6 | Decision; optional second development cohort; confirmation against Python if warranted | Decision recorded in the journal with the rule from section 4 |

Rough effort, in agent working days: phase 1 two to three, phase 2 three to
four, phase 3 two to three, phases 4 and 5 two to three days of wall time
dominated by attempts and reviews. Preparation time is recorded in its own
ledger as the study protocol requires.

## 6. Risks

- **Agents fight the interface.** Models default to files and shells. The
  practice pack teaches the verbs before timing, and abandonments are reported
  rather than hidden. If practice completion falls below the files arm, stop
  and revise before the cohort.
- **Budgets hide something needed.** Every trimmed response reports `omitted`
  counts and how to fetch the rest; the retained response holds everything.
  Retrieval counts are a secondary outcome, so hidden cost stays visible.
- **Derived imports misbehave on host modules.** `io.selka` declares `host fn`
  entries and is protected; imports derive from index references, which cover
  host calls. The round-trip suite includes every baseline that uses it.
- **Comment attachment.** A comment separated from its declaration by a blank
  line is ambiguous. The importer attaches contiguous leading comment lines
  only; the round-trip suite catches drift.
- **Rendering order.** New declarations append at module end unless `after` is
  given. Order is not semantic for functions and types in this language, and
  the formatter is deterministic, so diffs stay local.
- **Equal on average, worse on one family.** Family results are published
  regardless; the aggregate never hides a regression.
- **Confinement claims.** The first cohorts do not claim structural isolation.
  The report says so in the same words as today.

## 7. Files this plan creates or touches

New: `src/declarations.zig` and CLI wiring, `scripts/store.py`,
`scripts/store_server.py`, `tests/store_roundtrip.py`, `tests/store_api.py`,
`tests/store_server.py`, `tests/development_velocity/test_store_gateway.py`,
`tests/development_velocity/test_handoff.py`,
`tests/development_velocity/test_store_practice.py`,
`experiments/development_velocity/PARTICIPANT-STORE.md`,
`experiments/development_velocity/PROMPT-STORE.md`,
`experiments/development_velocity/PROMPT-FILES.md`,
`experiments/development_velocity/dry_run.py`,
`experiments/application_comparison/practice/my/GUIDE-store.md`,
`docs/experiments/declaration-store.md` (this file),
`docs/experiments/declaration-store-format.md`,
`docs/experiments/declaration-store-session.md`,
`docs/experiments/declaration-store-harness.md`,
`docs/experiments/declaration-store-results-<date>.md` after the cohort.

Touched: `src/main.zig`, `experiments/application_comparison/session.py`,
`experiments/application_comparison/practice_pack.py`,
`experiments/development_velocity/runner.py`, `telemetry.py`, `report.py`,
`analysis.py`, `docs/current-language.md` for the new command.

Three refinements the harness work required, recorded here rather than silently:
frozen baselines are keyed by arm label instead of language, so each arm carries
its own `WORKFLOW.md` and a legacy cohort's directory names are unchanged; when a
store arm is registered, every `.selka` baseline is replaced by its own store
rendering, so both arms receive identical canonical source and a rendered
submission's protected files match the baseline byte for byte; and
`store_server.StoreSession` gained one additive method, `cached_snapshot`, so a
gateway that opens one session per request does not re-render an unchanged branch.
