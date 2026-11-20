# Per-function cost

Juice (`docs/tooling/juice.md`, in the compiler repository) combines this static report with short, verified workload
runs to compare application and backend changes without an elapsed-time gate.
Its collection and text workflow (`docs/tooling/cost-workflow.md`) shows how to combine a
source entry, static sites, runtime counters and equivalent completed work.

`selka cost ENTRY.selka [FUNCTION]` runs the same reachable Core construction and
release passes as `selka build ENTRY.selka --release --stats`, then compiles the
identical emitted LLVM units to capture optimization remarks. It does not link
or execute the program.
It writes one row per emitted function and a total. `FUNCTION` is an exact Core
name or its unqualified name; matching specializations remain separate rows. An
unknown or unreachable name exits 2. `--json` writes a `cost-v1` document with
`functions` and `totals`. Filtering also filters the total.

```bash
selka cost program.selka
selka cost program.selka work --json
selka cost program.selka --debug
selka cost program.selka --verify-facts
selka cost program.selka --sites
selka cost program.selka --clauses
```

The counts describe static sites, not executions, bytes, timings or instruction
counts; a counting build (`--counters`, run-time counters) records
executions and bytes, and `--counters FILE.json` adds that run's executions
after the static rows. They belong to the physical emitted body: costs introduced by inlining
are attributed to the caller. Internal callees have separate rows, so allocation
counts do not double-count a call and its callee. Blocks not reachable from the entry, and blocks the build's facts
prove unreachable, contribute no kept checks or allocation sites.

| Field | Meaning |
|---|---|
| `checks.kept` | Check-bearing Core instructions still checked at run time; verify builds include checks re-emitted to validate proofs |
| `checks.proved` | Proof events recorded by the fact passes, including proofs after loop versioning |
| `updates.in_place` | Updates performed directly on exclusively owned storage |
| `allocation.sites` | Sites that may allocate heap or runtime scratch memory; growth and conditional copies count even when an execution does not allocate |
| `allocation.unresolved_calls` | Subset of allocation sites with a foreign or unresolved function target |
| `ownership.drops` | Deterministic cleanup operations inserted for owned values |
| `inlined_calls` | Calls expanded by the Core inliner, excluding later LLVM inlining |
| `loops.vector_plans` | Loops given a Core vector emission plan; `--stats`'s legacy `vectorized` count has this meaning |
| `llvm_vectorized_loops` | Positive LLVM loop-vectorization remarks; `null` when no positive evidence is available |
| `loops.unknown` | Core loops whose LLVM outcome is unclassified; remains conservative when LLVM transforms loop structure |
| `loops.unswitched`, `loops.versioned`, `ownership.stack_lists` | Loop transformations and lists promoted to stack storage, also printed by `--stats` |

The retired RC and uniqueness-test fields are absent from static and dynamic
reports. Runtime cleanup is measured by `frees` and `free_bytes`, alongside
calls, copies, growth, allocations and checks.

`--debug`, `--no-facts` and `--verify-facts` select the same passes as those build
modes; the default is release with trusted facts. The verifier's extra fact
assertions are not optimization proof events. A `debug(...)` line costs what a release
binary pays for it, the evaluation of its arguments and no formatting or write; `--debug`
adds the output.

## Allocation and copy sites

`--sites` adds one row per allocation or copy site of the same final module:
the instructions whose classification (`allocation.sites`) may allocate, after the
build's Core passes. The function rows, text output and `cost-v1` document are
unchanged; the sites follow them. The row count equals `allocation.sites` when no
`FUNCTION` filter is given. Unreachable blocks (from the entry, or by the build's facts) contribute
no rows, exactly as they contribute no allocation sites.

```bash
selka cost program.selka --sites
selka cost program.selka --sites --json
selka cost program.selka work --sites
```

| Field | Meaning |
|---|---|
| `path`, `line`, `column` | The source origin of the site's witness span, kept through inlining the way counting builds keep a counter site's position: a cloned operation keeps its callee's source position |
| `function` | The source function the operation came from; an inlined callee keeps its own name, not the caller's |
| `kind` | `copy`, `construction`, `conversion`, `growth` or `unresolved call` |
| `loop_depth` | The number of recorded loops enclosing the site after the passes; `0` outside every loop. A callee inlined into a caller's loop reports that physical depth, not the loop-free depth of its own body |
| `written` | On a `copy` row only: the mark the hidden-copy check reads, `true` for a written copy, a named operation, a dictionary-key copy and an `old` capture, `false` for a frame block and an unwritten copy. Other kinds carry no `written` member |
| `hint` | The one-line repair or check hint for `kind` |
| `label` | On a `copy` row only, after `hint`: `written`, `named operation` or `implicit` (below) |
| `implicit` | On an implicit `copy` row only: `frame block`, `dictionary key`, `old capture` or `unwritten` |

| Kind | Sites | Hint |
|---|---|---|
| `copy` | `list_copy`, `dict_copy`, `buffer_copy`, `str_slice`, `str_from_view`, a frame block (`block_frame`), and compiler runtime helpers that copy (`src/core/copy_sites.zig`) | An independent copy: move the value, borrow a view, or copy once outside the loop |
| `construction` | `list_new`, `dict_new`, `buffer_new`, `box_make`, and a resolved runtime helper with no more specific kind | A new value: construct it once outside the loop or reuse storage |
| `conversion` | `str_char` and runtime text, encode, join, show and render helpers | A new storage form: convert once outside the loop and keep the result |
| `growth` | `list_push`, `dict_insert`, `dict_remove`, `dict_find` on a compound key, `list_sort`, `buffer_push`, `buffer_append`, `str_append`, `str_append_char`, and sort, rotate or comparison-scratch helpers | Storage may grow: reserve capacity up front, or grow once outside the loop |
| `unresolved call` | A call whose target the classification cannot resolve: a foreign declaration or a function-value call that is not a direct function reference | An unresolved or foreign call may allocate: call a known helper or move it out of the loop |

Every `copy` row is one site of the one list of copy sites (`src/core/copy_sites.zig`) that the hidden-copy check
reads too, and says how the copy reads on the page:

| Label | When | Example |
| --- | --- | --- |
| `written` | The source says `copy(...)` at the site | `prog.selka:3:13  kinds  copy  written  loop 0` |
| `named operation` | An operation whose name says it makes a new value made the copy: `sorted`, `list(...)`, `+` on text, `.split`, `.encode`, a trim | `prog.selka:4:15  kinds  copy  named operation  loop 0` |
| `implicit` | Nothing on the page says the copy happens | `prog.selka:7:9  index  copy  implicit (dictionary key)  loop 1` |

An implicit copy is one of four kinds:

- `frame block`: the callee copies a plain text, bytes or list parameter that a record or a list of borrows holds,
  once per call when the caller passed a slice, and always for `bytes`. Counted, not refused (decision Q8 is open).
- `dictionary key`: `d[k] = v` or `dicts.setdefault(mut d, k, v)` with a borrowed key `k` copies it when it is new.
  This is the language's one documented implicit copy ([functions](../functions.md)), kept by the user's decision of
  12 November 2026. `sets.include(mut s, k)` makes the same copy inside the library, where `copy(value)` is written,
  so its row is at that line of `sets.selka` and reads `written`.
- `old capture`: the entry copy of `old(...)` whose argument is not a named place, such as a call's borrowed result.
  An `old(x)` of a managed place is written `old(copy(x))` ([contracts](../contracts.md)), so its row reads `written`.
- `unwritten`: any other copy with no written mark. The hidden-copy check refuses it (`E_CORE_HIDDEN_COPY`).

The text output prints each copy row's label, and a `hidden copies: N` line counts the implicit rows and names their
kinds (`hidden copies: 2 (1 frame block, 1 dictionary key)`; `hidden copies: 0` when there are none). The JSON
document keeps `hidden_copies` as the count of `"written":false` rows and adds `implicit_copies`, the count of
implicit rows. A written `copy(x)` that the passes remove because `x` is dead afterwards leaves no row.

The hidden-copy check runs in every guest build, debug and `--release`, under the policy of the other validators
([certificate validators](native-build.md#certificate-validators)): `--no-validate` turns it off, and
`--verify-written-copies` and `--verify-facts` ask for it in any case. It reads the same sites in the same blocks as
`--sites`: those reachable from the entry, less the ones the build's facts prove dead (a verify build traps on entering
such a block). It refuses only an `unwritten` copy, and with `--stats` prints one line:

```console
selka-core: hidden-copy check: written 1, named operations 1, implicit 2 (frame blocks 1, dictionary keys 1, old captures 0); implicit copies are counted, not refused
```

Rows are in emitted-function order, then block order, then instruction order of the
final body, so a caller's cloned sites appear before the standalone body of the
callee they came from. `FUNCTION` filters these rows as it filters the function
rows: by the row's `function`, with the same exact-or-unqualified match. A callee
that was fully inlined has no function row but still names its sites, so select it
by name to list only those. With `--json`, `--sites` writes one `cost-sites-v1`
document whose `functions` and `totals` members are the unchanged filtered
`cost-v1` members and whose `sites` array holds these rows in the same order:

```console
{"version":"cost-sites-v1","functions":[...],"totals":{...},"sites":[{"function":"make","path":"program.selka","line":2,"column":21,"kind":"construction","loop_depth":1,"hint":"a new value: construct it once outside the loop or reuse storage"}],"hidden_copies":0}
```

`--sites` cannot be combined with `--counters`; the counter section describes a
run, while site rows describe the build. The rows remain static sites, never
executions, bytes or elapsed time.

## Contract clauses

`--clauses` replaces the site section with one row per contract clause
(`@requires`, `@ensures`, `@invariant`) of the same final module, and says what
the build mode's facts made of it: `proved` (no copy of its check can fail; the
facts state every copy's trap unreachable), `refuted` (it fails whenever this program reaches it) or `kept`
(a run-time check remains). `--asserts` adds a row per `assert`; asserts are
always counted in the totals. The function rows, text output and `cost-v1`
members are unchanged. `docs/contracts.md#what-the-compiler-proved` explains how
to read the rows.

```bash
selka cost program.selka --clauses
selka cost program.selka --clauses --asserts --json
selka cost program.selka clamp --clauses
```

A clause has one copy per place it is checked (each return of an `@ensures`,
each construction or write of an `@invariant`, each instance of a generic
function); `own` counts copies in the function's own body and `inlined` copies
the Core inliner cloned into callers. A copy is proved when the facts state its
trap block unreachable (the fact certificate's dead block), refuted when its trap
is reachable and the block its check passes to is not, and kept otherwise; a
clause is refuted when one copy is, kept when one is kept, and proved otherwise.
`--debug` and `--no-facts` compute no facts, so every copy is kept.

| Field | Meaning |
|---|---|
| `kind` | `requires`, `ensures`, `invariant`, or `assert` in `asserts` |
| `function` | The function or record the clause is written on (empty for an `assert`) |
| `clause` | The condition as written, whitespace folded; an `assert` row shows its message |
| `ordinal` | Which clause of its kind on that function or record it is, from 1 in source order |
| `path`, `line`, `column` | The condition's position; an invariant is found in the source by its condition and record, else placed at its first copy |
| `status` | `proved`, `refuted` or `kept` |
| `own`, `inlined` | Copies by status: `proved`, `refuted`, `kept`, and `unused`: copies in a function nothing calls after the passes (a body the inliner cloned into every caller), which never run and decide no status |
| `refuted_at` | On a refuted clause: the emitted `function` holding the first refuted copy and, for an inlined copy, the `call` it was cloned at |
| `call_sites` | On a `requires` row: its call sites by what the facts made of the copy each runs (`proved`, `refuted`, `kept`); see below |

A `@requires` row also counts its call sites, `call sites P/R/K` in the text. An
inlined copy is one call site; every direct call of the function's own body that
the facts can reach runs that body's copy, so it counts with that copy's status.
The body's copy is analysed with the parameter intervals every caller's arguments
join to, so a proof there covers each of its sites, and a site whose own arguments
would satisfy a kept clause still counts as kept: the check runs there. A call
through a function value is not counted. The totals line ends with
`requires at call sites: P proved / R refuted / K kept` when the program has a
`@requires`, and `clause_totals` carries the same as `call_sites`.

`FUNCTION` filters the clause rows by the function or record they are written on
and recounts the clause totals. With `--json`, `--clauses` writes one
`cost-clauses-v1` document: the unchanged `functions` and `totals`, then
`clause_totals` (`clauses` by status, clause copies `own` and `inlined`,
`asserts` copies, and `call_sites` of every `@requires`), `clauses` and `asserts`
(empty unless `--asserts`):

```console
{"version":"cost-clauses-v1","functions":[...],"totals":{...},"clause_totals":{"clauses":{"proved":1,"refuted":1,"kept":0,"unused":0},"own":{"proved":4,"refuted":1,"kept":0,"unused":0},"inlined":{"proved":0,"refuted":0,"kept":0,"unused":0},"asserts":{"proved":0,"refuted":0,"kept":0,"unused":0},"call_sites":{"proved":0,"refuted":0,"kept":0}},"clauses":[{"kind":"ensures","function":"wrong","clause":"result >= 1","ordinal":1,"path":"probe.selka","line":9,"column":10,"status":"refuted","own":{"proved":1,"refuted":1,"kept":0,"unused":0},"inlined":{"proved":0,"refuted":0,"kept":0,"unused":0},"refuted_at":{"function":"wrong"}}],"asserts":[]}
```

`build --stats` prints the same totals on a `selka-core: clauses` line and one
`selka-core: refuted:` line per refuted clause, only when the program has a
clause or an `assert`. `--clauses` cannot be combined with `--sites` or
`--counters`. The checks the compiler makes for its own operations (overlapping
`mut` arguments, a narrowed option, a zero `range` step) are not asserts and are
not counted.

## LLVM remarks

Core vector plans do not establish that LLVM vectorized another loop. Cost and
`build --stats` request YAML with `-fsave-optimization-record` and an explicit
`-foptimization-record-file` from `zig cc`, using the build's exact target, CPU,
optimization flags and emitted units. The compiler records each remark compile's
wall time on stderr. The remark objects never replace build objects or enter the
link. Unsupported flags, failed collection and missing records leave the outcome
unknown. To read saved records for this exact module instead, use
`--llvm-remarks FILE.opt.yaml`.

Only successful `loop-vectorize` / `Vectorized` remarks whose `Function` matches
a reported Core name contribute to `llvm_vectorized_loops`. Missing, missed and
unrelated remarks leave the outcome unknown. `my.` is the emitter's symbol prefix
and is removed before matching. Remaining source loops stay unclassified because
LLVM can clone, inline or eliminate them. Debug's content-named synthetic helpers
may therefore remain unknown even when LLVM supplies a helper remark.

Successful remark collections are cached for the exact instrumented LLVM unit,
compiler/tool contract, CPU, target, layout, build mode and sanitizer settings.
Failed or missing collections remain unknown and are attempted again. Ordinary
builds without `--stats` do not request this additional compile.

## Incremental queries

Cost uses the existing frontend, lowering and optimizer caches, then caches static
counts per final Core function. Query identities include declaration/type layout,
allocation classification dependencies, optimization events, reachable blocks and
verification mode. An edit can reuse unaffected rows; a helper change invalidates
any changed optimized caller body. Counts remain static sites, never a machine
cost or elapsed-time prediction.

```bash
selka cost program.selka --json --cache-dir .selka-cache/cost --cache-report
selka cost program.selka --json --cache-dir .selka-cache/cost --verify-cache
selka cost program.selka --json --no-cache
```

`--cache-report` writes `cost-query-work-v1` to stderr. Its policy identifies
whether reuse and cache verification are enabled. Frontend, lowering and optimizer
groups expose existing cache instrumentation; zeroes when those caches are bypassed
do not mean those stages skipped fresh analysis. Cost rows distinguish actual
computed, reused, verified and bypassed queries; LLVM reports remark processes
and reuse.
The normal text and `cost-v1` JSON output are unchanged. Function selection and
formatting happen after querying, so changing either can reuse the underlying
rows. `--verify-cache` checks saved rows against independent fresh computation and
collects LLVM remarks freshly; `--no-cache` bypasses reuse. Missing or damaged
query storage computes fresh. Supplied `--llvm-remarks` and `--counters` files are
read on every invocation and never folded into saved static rows.

## The allocation definition

`src/core/cost.zig` exports the instruction-level allocation classification used
by this report and the build-time allocation promise. Stack-promoted lists and
allocation-free borrow/identity helpers do not allocate. Managed construction,
materialization, copy, growth, dictionary deletion bitmaps, stable sorting
scratch, compound-key lookup scratch, and other potentially allocating runtime helpers do. Runtime helpers
have an explicit audited allocation-free allowlist; an unknown helper is
conservative. Foreign and unresolved function-value calls may allocate.

A whole-program allocation check must visit every internal callee and every path,
including cold error paths. It runs before release optimization, after debug
ownership exposes explicit copies and other potentially allocating operations. This
prevents release-only stack promotion or unreachable-code proof from satisfying
an allocation promise that fails in debug builds. The report itself describes
the chosen optimized build, which may eliminate those sites.

## Costs alongside interfaces

`selka list-interfaces ENTRY.selka --cost` prints the ordinary public declaration
listing followed by the exact release `cost-v1` report from `selka cost ENTRY.selka`.
It is mutually exclusive with `--contracts`, which emits a JSON manifest. The
cost rows describe the entry's reachable emitted functions, including private functions and specializations; an uncalled
public declaration has no emitted cost row. Totals sum those emitted rows.

The option checks bodies and requires an executable entry. A body or Core error
fails the command before it prints a partial listing. Without `--cost`, the
existing declaration listing and its handling of bodies are unchanged. Use
`selka cost` directly for JSON, function selection and alternative build modes.
