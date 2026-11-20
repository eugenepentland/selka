# Per-function cost: how it works

Implementation detail and measurements moved out of the user guide, [docs/tooling/cost.md](../tooling/cost.md). Each section keeps the heading of the guide section it came from.

## Allocation and copy sites

| Kind | Sites | Hint |
|---|---|---|
| `copy` | `list_copy`, `dict_copy`, `buffer_copy`, `str_slice`, `str_from_view`, a frame block (`block_frame`), and compiler runtime helpers that copy (`src/core/copy_sites.zig`) | An independent copy: move the value, borrow a view, or copy once outside the loop |
| `construction` | `list_new`, `dict_new`, `buffer_new`, `box_make`, and a resolved runtime helper with no more specific kind | A new value: construct it once outside the loop or reuse storage |
| `conversion` | `str_char` and runtime text, encode, join, show and render helpers | A new storage form: convert once outside the loop and keep the result |
| `growth` | `list_push`, `dict_insert`, `dict_remove`, `dict_find` on a compound key, `list_sort`, `buffer_push`, `buffer_append`, `str_append`, `str_append_char`, and sort, rotate or comparison-scratch helpers | Storage may grow: reserve capacity up front, or grow once outside the loop |
| `unresolved call` | A call whose target the classification cannot resolve: a foreign declaration or a function-value call that is not a direct function reference | An unresolved or foreign call may allocate: call a known helper or move it out of the loop |

Every `copy` row is one site of the one list of copy sites (`src/core/copy_sites.zig`) that the hidden-copy check
reads too, and says how the copy reads on the page:

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

## Contract clauses

A clause has one copy per place it is checked (each return of an `@ensures`,
each construction or write of an `@invariant`, each instance of a generic
function); `own` counts copies in the function's own body and `inlined` copies
the Core inliner cloned into callers. A copy is proved when the facts state its
trap block unreachable (the fact certificate's dead block), refuted when its trap
is reachable and the block its check passes to is not, and kept otherwise; a
clause is refuted when one copy is, kept when one is kept, and proved otherwise.

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
