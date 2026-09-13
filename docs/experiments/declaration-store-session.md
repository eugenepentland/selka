# Declaration store session protocol

`scripts/store_server.py` is the participant's only interface to source in the
[declaration store](declaration-store.md) experiment's `my-store` arm. It owns
one [declaration store](declaration-store-format.md) database, renders private
snapshots the participant never sees, and runs the frozen compiler and
application adapter on them. Protocol version `store-session-v1`, on every
response. Standard library only.

```sh
python3 scripts/store_server.py --db store.sqlite --branch work \
  --compiler zig-out/bin/mylang --session-dir attempt/store \
  --cases pack/public/cases.json \
  --adapter zig-out/bin/mylang-io --project '{work}' --timings=json
```

The command reads one JSON request per line on stdin and writes one JSON
response per line on stdout. A request is `{"verb": ..., "arguments": {...}}`.
An unknown verb or a bad argument answers with an error response and the
session continues; a line that is not a request object exits 2.

The module is importable, which is how the coordinator gateway uses it:

```python
from store_server import StoreSession
session = StoreSession(database, 'work', compiler, adapter, session_dir,
                       asset_root='.trial-public', budgets=None,
                       protected_modules=('main', 'io'), check=runner, cases=None,
                       limits={'wall_seconds': 90, 'cpu_seconds': 90})
response = session.dispatch('open', {})          # or session.open(), session.batch(...)
snapshot = session.snapshot()                     # coordinator only; carries the path
```

`adapter` is either a callable `(work_path, request_bytes) -> {outcome,
returncode, stdout, stderr, elapsed_seconds}` — the gateway passes one that runs
`experiments/application_comparison/isolation.run` under the trial `Limits` — or
an argv template in which `{work}` is replaced by the rendered snapshot.
`check` is a callable `(snapshot_record) -> dict`; the gateway passes the
public-verification runner. `cases` is the standalone alternative used by the
CLI and the tests. Exactly one of the two must be configured for `check`.

## Envelope

Every response carries `version`, `verb` and `record`. `record` is this
response's retention number, the value `output` pages. A rejected request
answers with `verb: "error"` and the fields `error`, `requested_verb` and
`verbs`; the session is not disturbed.

A response that did not fit its budget also carries `response_truncated: true`
and `hint`, the exact `output` request that pages the retained original.

## Verbs and budgets

| Verb | Request | Budget |
| --- | --- | ---: |
| `open` | `{}` | 8 KiB |
| `context` | `{"ids": [...], "budget": N}` | 8 KiB, `budget` up to 32 KiB |
| `search` | one of `{"text":…}`, `{"type":…}`, `{"calls":…}`, `{"effect":…}`, optional `limit` | 8 KiB |
| `asset` | `{"name":…, "offset": N, "limit": N}` | 8 KiB |
| `batch` | `{"ops": [...], "if_match": {id: hash}}` | 16 KiB |
| `probe` | `{"request": <json>}` | 16 KiB |
| `check` | `{}` | 16 KiB |
| `output` | `{"record": N, "offset": N, "limit": N}` | 8 KiB |
| `finish` | `{"reason": "completed"｜"abandoned"}` | 4 KiB |

Budgets are stated in **bytes of the serialized response**, envelope included,
and are enforced on exactly that number. Unexpected argument keys are refused
per verb. There is no `command` verb in this arm.

These nine are the whole session protocol. The participant bridge additionally
offers `await-handoff`, which belongs to both arms of the harness and never
reaches this server: it is the single-context bridge between onboarding practice
and the timed task, described in
[declaration store harness](declaration-store-harness.md).

## `open`

`branch`, `modules` (`module`, `declarations`, `protected`), `declarations`
(`id`, `kind`, `exported`, `signature` clipped to 160 bytes, `bytes`,
`protected`), `assets` (`name`, `kind`, `bytes`), `budgets`, `receipt`
(`id`, `parent_id`, `branch`, `utc`, `sha256`), `omitted` and `hints`.

Declaration ids are `module::name`. `open` does **not** return declaration
hashes; `context` is the source of the `if_match` hash, so an edit is always
preceded by a read.

## `context`

`{"ids": ["module::name", ...], "budget": N}`, 1..16 ids, `budget` 1024..32768.

Response: `checked`, `signature_source`, `relation_source`, `budget`, `entries`,
`omitted`, `hints`. Each entry has

- `id`, `hash`, `kind`, `module`, `exported`, `protected`
- `signature` — the checked signature from `index-project` when the branch
  checks, otherwise the declaration header from `list-declarations`
- `source` — the canonical declaration source with its attached comments
- `source_bytes` — the untrimmed size
- `callees`, `callers` — `{id, signature, external}` rows; `external` marks a
  standard-library declaration that is not on the branch
- `types` — the same rows plus `source` for the types the declaration uses,
  clipped to 512 bytes; `null` source for an external type
- `tests` — exported `test_` declarations whose call graph reaches this one
- `omitted` — counts for `callees`, `callers`, `types`, `tests` and, when the
  budget trimmed it, `source_bytes`

`signature_source` is `index-project` or `declaration-header`, and
`relation_source` is `index-project` or `imported index edges`. When the branch
does not check, `checked` is false, signatures are declaration headers rather
than resolved types, and the hint says so; relationships then come from the
edges recorded at import, which can be stale.

Related rows are capped at eight each with explicit `omitted` counts. When the
response still does not fit, sources are clipped first, then types, callers and
callees are dropped, then whole entries; every stage records its `omitted`
count, and the full response stays in the retained record.

## `search`

Exactly one selector.

- `text` — case-insensitive substring over canonical declaration sources and
  over readable assets.
- `type` — declarations that use the named type, plus its own declaration.
- `calls` — declarations that call the named declaration.
- `effect` — declarations whose checked effects include the named effect;
  without an index, the effect names spelled in their signatures.

Response: `mode`, `query`, `checked`, `hits`, `omitted`, `hints`. At most 20
hits; snippets are at most 200 bytes. A declaration hit is `{kind:
"declaration", id, offset, protected, snippet}`. An asset hit is `{kind:
"asset", name, offset, snippet, total_bytes}`, where `offset` is the page offset
to pass straight back to `asset`.

## `asset`

`{"name": …, "offset": N, "limit": 1..8192}`. Unknown names, and names outside
the configured asset root (`.trial-public` by default), are refused. Response:
`name`, `offset`, `bytes`, `total_bytes`, `text`, `next_offset`, `complete`,
`omitted.bytes`. The served page is shortened when needed so the response fits
its budget; `next_offset` always reflects what was actually served, so paging
never loses a byte. Assets are read-only for every verb.

## `batch`

`{"ops": [...], "if_match": {id: hash}}`, 1..32 operations.

```text
{"op": "replace", "id": "model::Stock", "source": "..."}
{"op": "add", "module": "model", "source": "...", "after": "Stock", "exported": true}
{"op": "remove", "id": "model::Stock"}
```

`replace` and `remove` require an `if_match` entry for their id; `add` requires
none. Every `if_match` entry is verified against the branch head before anything
is touched. A replacement or addition must be exactly one top-level declaration;
`replace` keeps the declaration's name and exported flag, so renaming is an `add`
and a `remove`.

The accepted fields are exact: `replace` takes `op`, `id`, `source`; `add` takes
`op`, `module`, `source` and the optional `after` and `exported`; `remove` takes
`op`, `id`. Any unexpected or missing field is an `invalid-operation` rejection
whose `detail` states that op's accepted fields, the fields the operation
actually carried, and a copy-ready example — `store_server.OPERATION_SHAPES` is
that table. The pilot lost five batches to a guessed `add` shape.

`store_server.DECLARATION_KINDS` is the exact list of accepted top-level
declaration kinds, checked at import against `store.KINDS`:

```text
alias  const  resource  result  enum  union  domain  struct  fn  host_fn  extern_fn
```

Processing: validate shapes, protection and `if_match`; copy the branch to a
candidate; apply the operations there; render the candidate and re-list every
touched module with `list-declarations`; on any failure drop the candidate and
reject, leaving the branch, the receipt head and the rendered snapshot exactly
as they were. Otherwise the candidate replaces the working branch in one
transaction, the rendered candidate becomes the new private snapshot,
`check-project --diagnostics=json` runs on it, and a receipt is committed
carrying the batch and the delta. **The commit follows parse, not check**: a
batch that leaves type or ownership errors is still committed, so iteration
never loses work.

### Committed response

`status: "committed"`, `passed: true`, `scope_violations: []`, `checked`,
`applied`, `delta`, `signature_changes`, `affected`, `affected_source`,
`receipt`, `omitted`, `hints`.

- `applied` — `{operation, op, id, hash}` per operation; `hash` is `null` for a
  removal, and an addition reports the id the parser gave it.
- `delta` — `{new, resolved, unchanged_count}`. Diagnostics are keyed by
  `(code, declaration id, message)` against the previous receipt's recorded set.
  Each row is `{code, severity, id, message, notes}`, and each note is
  `{role, id, message}` — the mechanical evidence the compiler already emits,
  such as the field a record gained under `E_INCOMPLETE_CONSTRUCTION`. `id` is
  the qualified declaration whose byte range contains the location, from
  `list-declarations` on the snapshot, and is `null` outside the branch. No
  file path or line number ever appears.
- `signature_changes` — `{id, before, after}` for touched declarations whose
  shape changed: the header for a function, the whole body with whitespace
  collapsed for a type, so that adding a field is visible.
- `affected` — `{id, kinds}` for declarations that reference a touched one, from
  the index of the **previous** snapshot; `affected_source` names that index or
  the imported edges it fell back to.
- `receipt` — `{id, parent_id, sha256, utc}`.

### Rejection response

The shape of the gateway's scope-violation receipt: `status: "rejected"`,
`passed: false`, `committed: false`, `scope_violations`, `reason`, `rejections`,
`branch_sha256`, `receipt` (the unchanged head), `omitted`, `hints`.

`scope_violations` lists the protected declaration ids the batch tried to touch,
exactly as the files arm lists protected file names, so reporting needs no new
rule. It is `[]` for every other rejection. Each `rejections` row is
`{operation, reason, detail}`, with `operation` the index in `ops` or `null` for
a whole-batch reason. `reason` values:

```text
protected-declaration  unknown-declaration  unknown-module  if-match-missing
if-match-mismatch      invalid-operation    invalid-source  duplicate-declaration
parse-failure
```

The top-level `reason` is the first row's. Rejections are all-or-nothing.

A `parse-failure` `detail` is the compiler's own diagnostic, clipped to 512
bytes. When that diagnostic is `E_SYNTAX` at or before the failing declaration's
own header line — the store parses one declaration inside a synthetic
`module NAME;` line, so a diagnostic on line N lands on line N-1 of the
participant's source — `store_server.SYNTAX_HELP` is appended: the accepted kinds
above, that there is no `record` keyword and a product type is
`struct Name { field: i64, other: i64 }`, that casts are `T(x)` and never
`T(x)` or `as`, and that qualified references derive imports so no import
statement is ever written. A syntax error deeper inside a body is not a question
about declaration kinds and gets the diagnostic alone. The pilot lost ten batches
to invented syntax at this exact point.

**Protected declarations** are every declaration of a protected module — `main`
and `io` by default, configurable — and every asset, which no verb can write.
Protected declarations are readable through `open`, `context` and `search`, as
protected files are in the files arm; they are only unwritable.

## `probe`

`{"request": <json>}`. The request is canonicalized to bytes and fed to the
frozen adapter on stdin, against the current private snapshot, under the same
limits the gateway uses. Response: `outcome`, `returncode`, `request_sha256`,
`request_bytes`, `elapsed_seconds`, `stdout`, `stderr`, `stdout_bytes`,
`stderr_bytes`. This is the store arm's equivalent of running the application on
an input of the participant's choosing.

## `check`

`{}`. The public check, unchanged: the coordinator's injected runner against the
private snapshot, or in standalone mode every case of the configured case file
through the adapter with a canonical comparison of the answer. Response fields
follow the files arm: `submission`, `passed`, `cases`, `scope_violations`,
`diagnostics`. The response is shaped by the same 16 KiB bounded-feedback policy
the files arm applies; `store_server.bounded` mirrors
`experiments/development_velocity/runner.bounded_feedback`, and
`tests/store_server.py` compares the two whenever the harness package is
importable.

## `output`

`{"record": N, "offset": N, "limit": 1..8192}`. Pages a prior response of this
session. Response: `source_record` (the record paged), `offset`, `text`,
`total_characters`, `next_offset`, `omitted.characters`. The envelope `record`
is this response's own number, not the one being paged.

## `finish`

`{"reason": "completed"|"abandoned"}`. Renders the final branch and returns
`reason`, `branch`, `modules`, `assets`, `declarations`, `snapshot_sha256`,
`inventory_sha256` and the verified `receipt` head. Sealing is the gateway's
step; nothing is submitted here.

## Snapshots, retention and confinement

`StoreSession.snapshot()` renders the branch into a fresh private directory
under `<session-dir>/snapshots/NNN` and returns `{index, path, branch,
branch_sha256, inventory, inventory_sha256, modules, assets, entries}`. The
inventory is every rendered regular file as relative path to SHA-256, and
`inventory_sha256` digests it; the tree is a file-for-file drop-in, assets
included, which is what the gateway's public check runs on. A snapshot is
re-rendered only when the branch digest changes.

Every response is retained whole at `<session-dir>/records/NNNNNN.json` as
`{version, record, verb, arguments, utc, response, returned, private}`.
`response` is the full response before any budget trimming and is what `output`
pages; `returned` is what the participant received; `private` holds the snapshot
path and inventory digest for the coordinator. As a fail-closed backstop, any
occurrence of the session directory path in a participant response is replaced
with `<private-snapshot>` before it is returned. **`finish` therefore does not
return the snapshot path**: the gateway reads it from `snapshot()`,
`session.final_snapshot`, or the retained record's `private` section. This is
the one deliberate departure from the plan's wording for `finish`, and it
follows the plan's own rule that the participant's world has no paths.

The telemetry fields `StoreGateway` reports are all derivable from the retained
records without re-running anything: `bytes_returned` is the serialized size of
each `returned`, `verb_counts` groups by `verb`, `context_omitted_total` sums the
`omitted` counts of `context` entries, `if_match_conflicts` counts `batch`
rejection rows whose `reason` is `if-match-mismatch`, and `batch_rejections`
counts `batch` responses whose `status` is `rejected`.

`context` and `search` are backed by `index-project` through
`scripts/navigate.py`, cached per branch digest and rebuilt after every
committed batch.

## Limits

- Diagnostics are keyed by code, declaration id and message. Two diagnostics of
  one code with the same message on the same declaration collapse to one key,
  and a check that stops early does not reach later diagnostics, so a warning
  can appear as `resolved` when an error aborts the check ahead of it.
- Delta diagnostics compare against the previous receipt's recorded set. The
  first batch of a session has no recorded set, so the pre-batch snapshot is
  checked once to establish the baseline.
- `affected` comes from static index references, not runtime coverage, and is
  not proof of complete change impact. It is empty for a branch that has never
  checked and only had import-time edges.
- `tests` are exported declarations named `test_` reached over call edges. They
  are not selected tests and not evidence that they cover the declaration.
- A `.my` file that is not a lexical module of the tree is an asset, so it is
  invisible to `context` and unwritable by `batch`.
- The server is trusted local tooling. It bounds its inputs and never returns a
  path, but it does not by itself stop an instruction-violating agent from
  reading the attempt directory on the host; structural isolation is a separate
  hardening step.

## Acceptance

`tests/store_server.py --compiler zig-out/bin/mylang --runner zig-out/bin/mylang-io`
imports the development-velocity runtime with the `inventory-reservations`
starter — a real `main`/`io` pair over five modules — and runs 113 checks: a
positive and a negative case for every verb, rejection shapes for protected
declarations, if-match conflicts, unknown ids, parse failures and
multi-declaration sources with the branch, receipt head and declaration hash
unchanged after each, a record migration that adds a struct field and replaces
one constructor and not the other returning the `E_INCOMPLETE_CONSTRUCTION`
delta at the unreplaced declaration with its mechanical note, a follow-up batch
that resolves it, delta arithmetic across three receipts, `add` and `remove`,
a probe round trip, a passing and a failing standalone check, an injected check
hook, output paging that reconstructs a trimmed response, budget assertions on
every response, no private path in any returned response, and the CLI line
protocol including an unknown verb and two malformed lines. Observed maxima:
`open` 4,958, `context` 9,750 at the 32 KiB budget, `search` 2,845, `asset` 261,
`batch` 1,559, `probe` 416, `check` 381, `output` 4,747, `finish` 591 bytes.
Run it with `python3 -B`; it is not wired into `zig build`.
