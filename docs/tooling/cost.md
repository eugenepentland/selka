# Per-function cost

`selka cost ENTRY.selka [FUNCTION]` reports what the compiler can see statically about each function: the run-time checks that remain, the sites that may allocate or copy, and what each contract clause became. It runs the passes of `selka build ENTRY.selka --release --stats` and does not link or run the program.

It writes one row per emitted function and a total. `FUNCTION` is an exact Core name or its unqualified name; matching specializations stay separate rows, an unknown or unreachable name exits 2, and a filter also filters the total. `--json` writes a `cost-v1` document with `functions` and `totals`.

```bash
selka cost program.selka
selka cost program.selka work --json
selka cost program.selka --debug
selka cost program.selka --verify-facts
selka cost program.selka --sites
selka cost program.selka --clauses
```

The counts are static sites, not executions, bytes or timings (`--counters FILE.json` adds a counting run's executions after the static rows). Inlined costs go to the caller, and blocks the facts prove unreachable add nothing.

| Field | Meaning |
|---|---|
| `checks.kept` | Check-bearing instructions still checked at run time |
| `checks.proved` | Checks the fact passes proved cannot fail |
| `updates.in_place` | Updates done directly on exclusively owned storage |
| `allocation.sites` | Sites that may allocate; growth and conditional copies count even when a run does not allocate |
| `allocation.unresolved_calls` | The subset whose call target is foreign or unresolved |
| `ownership.drops` | Deterministic cleanup operations for owned values |
| `inlined_calls` | Calls the Core inliner expanded (not LLVM's inlining) |
| `loops.vector_plans` | Loops given a vector plan |
| `llvm_vectorized_loops` | Loops LLVM reported vectorizing; `null` when there is no evidence |
| `loops.unknown` | Loops whose LLVM outcome is unclassified |
| `loops.unswitched`, `loops.versioned`, `ownership.stack_lists` | Loop transformations and lists moved to the stack, also printed by `--stats` |

`--debug`, `--no-facts` and `--verify-facts` select the passes of the matching build modes; the default is release with trusted facts. A `debug(...)` line costs what a release binary pays: its arguments are evaluated, nothing is formatted or written; `--debug` adds the output.

## Allocation and copy sites

`--sites` adds one row per site that may allocate or copy, after the function rows. The row count equals `allocation.sites` when no `FUNCTION` filter is given. `--sites` cannot be combined with `--counters`.

```bash
selka cost program.selka --sites
selka cost program.selka --sites --json
selka cost program.selka work --sites
```

| Field | Meaning |
|---|---|
| `path`, `line`, `column` | Source position of the site; inlining keeps the callee's position |
| `function` | The source function the operation came from |
| `kind` | `copy`, `construction`, `conversion`, `growth` or `unresolved call` |
| `loop_depth` | Loops enclosing the site after the passes; `0` outside every loop |
| `written` | On a `copy` row: `false` for a frame block and an unwritten copy, `true` for the rest |
| `hint` | The one-line repair for the `kind` |
| `label`, `implicit` | On a `copy` row: `written`, `named operation` or `implicit`, and the implicit kind (below) |

| Kind | Meaning | Hint |
|---|---|---|
| `copy` | An independent copy | Move the value, borrow a view, or copy once outside the loop |
| `construction` | A new list, dictionary, buffer or box | Construct it once outside the loop |
| `conversion` | A new storage form (text, encode, join) | Convert once outside the loop |
| `growth` | Push, insert, remove, sort, append | Reserve capacity up front |
| `unresolved call` | A foreign call or a call through a function value | Call a known helper |

Every `copy` row says how the copy reads on the page:

| Label | When | Example |
| --- | --- | --- |
| `written` | The source says `copy(...)` at the site | `prog.selka:3:13  kinds  copy  written  loop 0` |
| `named operation` | An operation whose name says it makes a new value: `sorted`, `list(...)`, `+` on text, `.split`, `.encode`, a trim | `prog.selka:4:15  kinds  copy  named operation  loop 0` |
| `implicit` | Nothing on the page says the copy happens | `prog.selka:7:9  index  copy  implicit (dictionary key)  loop 1` |

An implicit copy is one of four kinds:

- `frame block`: the callee copies a text, bytes or list parameter that a record or a list of borrows holds. Counted, not refused.
- `dictionary key`: `d[k] = v` or `dicts.setdefault(mut d, k, v)` with a borrowed key copies it when it is new. It is the language's one documented implicit copy ([functions](../functions.md)). `sets.include` makes the same copy inside the library, where it is written.
- `old capture`: the entry copy of `old(...)` whose argument is not a named place. `old(copy(x))` of a managed place reads `written` ([contracts](../contracts.md)).
- `unwritten`: any other copy with no written mark. The hidden-copy check refuses it (`E_CORE_HIDDEN_COPY`).

The text output ends with a `hidden copies: N` line naming the implicit kinds. The JSON has `hidden_copies` (the `"written":false` rows) and `implicit_copies`. A `copy(x)` the passes remove because `x` is dead leaves no row.

The hidden-copy check runs in every guest build under the policy of the other validators ([certificate validators](native-build.md#certificate-validators)): `--no-validate` turns it off, `--verify-written-copies` and `--verify-facts` ask for it in any case. It refuses only an `unwritten` copy, and `--stats` prints one line:

```console
selka-core: hidden-copy check: written 1, named operations 1, implicit 2 (frame blocks 1, dictionary keys 1, old captures 0); implicit copies are counted, not refused
```

`FUNCTION` filters the rows by their `function`, so a fully inlined callee still lists its sites when you name it. With `--json`, `--sites` writes one `cost-sites-v1` document: `functions`, `totals`, then a `sites` array.

## Contract clauses

`--clauses` replaces the site section with one row per contract clause (`@requires`, `@ensures`, `@invariant`) and says what the build's facts made of it:

| Status | Meaning |
|---|---|
| `proved` | No copy of the check can fail |
| `refuted` | It fails whenever this program reaches it |
| `kept` | A run-time check remains |

`--asserts` adds a row per `assert` (always counted in the totals). `--debug` and `--no-facts` compute no facts, so every copy is `kept`. [Contracts](../contracts.md#what-the-compiler-proved) explains how to read the rows.

```bash
selka cost program.selka --clauses
selka cost program.selka --clauses --asserts --json
selka cost program.selka clamp --clauses
```

A clause has one copy per place it is checked (each return of an `@ensures`, each construction of an `@invariant`, each generic instance). It is `refuted` when one copy is, `kept` when one is kept, and `proved` otherwise.

| Field | Meaning |
|---|---|
| `kind` | `requires`, `ensures`, `invariant`, or `assert` in `asserts` |
| `function` | The function or record the clause is written on (empty for an `assert`) |
| `clause` | The condition as written; an `assert` row shows its message |
| `ordinal` | Which clause of its kind on that function or record, from 1 |
| `path`, `line`, `column` | The condition's position |
| `status` | `proved`, `refuted` or `kept` |
| `own`, `inlined` | Copies by status (`proved`, `refuted`, `kept`, `unused`) in the function's own body and in callers the inliner cloned it into |
| `refuted_at` | On a refuted clause: the emitted function holding the first refuted copy |
| `call_sites` | On a `requires` row: its call sites by what the facts made of the copy each runs |

A `@requires` row also counts its call sites (`call sites P/R/K` in the text); a call through a function value is not counted. `FUNCTION` filters the rows by the function or record they are written on. With `--json`, `--clauses` writes one `cost-clauses-v1` document: `functions`, `totals`, `clause_totals`, `clauses` and `asserts` (empty unless `--asserts`).

`build --stats` prints the same totals on a `selka-core: clauses` line and a `selka-core: refuted:` line per refuted clause. `--clauses` cannot be combined with `--sites` or `--counters`. The compiler's own checks (overlapping `mut` arguments, a narrowed option, a zero `range` step) are not asserts.

## LLVM remarks

`cost` and `build --stats` also compile the emitted units to collect LLVM's remarks, because a Core vector plan does not show that LLVM vectorized a loop. Only a successful `loop-vectorize` remark counts toward `llvm_vectorized_loops`; otherwise it is `null`. `--llvm-remarks FILE.opt.yaml` reads saved remarks instead.

## Incremental queries

`selka cost` reuses the front-end, lowering and optimizer caches and caches static counts per function, so an edit recomputes only the affected rows.

```bash
selka cost program.selka --json --cache-dir .selka-cache/cost --cache-report
selka cost program.selka --json --cache-dir .selka-cache/cost --verify-cache
selka cost program.selka --json --no-cache
```

`--cache-report` writes `cost-query-work-v1` to stderr (computed, reused, verified and bypassed queries). `--verify-cache` checks saved rows against a fresh computation. `--no-cache` bypasses reuse.

## The allocation definition

Stack-promoted lists and borrow helpers do not allocate. Construction, copy, growth, dictionary deletion, sort scratch and other runtime helpers do, and foreign or unresolved calls may. The report describes the optimized build, which may have removed some sites.

## Costs alongside interfaces

`selka list-interfaces ENTRY.selka --cost` prints the public declaration listing, then the release `cost-v1` report of `selka cost ENTRY.selka`. It excludes `--contracts`, needs an executable entry, and prints nothing when a body or Core error occurs. The rows cover the reachable emitted functions, private ones included; an uncalled public declaration has no row. Use `selka cost` directly for JSON, function selection and other build modes.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/cost.md).
