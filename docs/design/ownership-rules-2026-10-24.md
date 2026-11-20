# Ownership rules (draft of 24 October 2026)

The current language reference is [Ownership rules](../ownership-rules.md).

This is the repository copy of the Claude Doc "Selka ownership rules (draft)",
<https://claude.ai/artifact/Efx4k4nepPqwYWRcL8s2N6>. The doc is the authority; this
copy exists so that agents without access to it work from the same words. It
describes the compiler on `main` at `68ed3981d`, before the
[ownership rules plan](../audits/ownership-rules-plan-2026-10-24.md) changes it. The
decisions the user took on 24 October are at the end.

## Purpose

This draft writes Selka's ownership model as numbered rules, taken from the compiler
on main `68ed3981d`. It has two jobs: to be the object a soundness proof targets, and
to be what every ownership refusal cites.

No such list existed. The rules are enforced in three layers:

- **Front end**: `sema*.zig`, `origins.zig`, `own_parameters.zig`,
  `value_semantics_check.zig` and `generic_bodies.zig`.
- **Core ownership checker**: `src/core/single_owner.zig` (3,361 lines), run on
  complete typed trees before optimization.
- **Core lowering and verification**: `own.zig` places destruction, and
  `verify_ir.zig` checks the result under `--verify-facts`.

Each rule states what the checker enforces now, not what it should enforce. Where the
two differ, Gaps says so. A rule marked *limit* records an implementation limit, not a
meaning of the language.

## The model in brief

Every managed value has exactly one owner at a time, and the compiler destroys it after
the owner's last use on every path. The rules below use these terms.

| Term | What it is | Where the checker decides it |
| --- | --- | --- |
| Managed type | A type that owns heap storage: `str`, `bytes`, lists, dictionaries, sets, byte buffers, files, owning capabilities, and any record, union, option or fixed array holding one | `ownedTypes`, a fixed point over record definitions |
| Move-only type | A managed type that cannot be copied: a resource (file, socket, listener) or a provider-dependent value | `single_owner_resource.zig` `affine` |
| Owner | A local binding, or an `own` parameter | `State.borrowed == false` |
| Place | An owner, or a field, element, dictionary value or match payload reached from one | `placeRoots`, `origin` |
| Move | Hands a value to a new owner; the old binding becomes unavailable | access `.move` in `checkLocal` |
| Borrow | A read-only hold on a place: a plain argument, a `const` of a place, a borrowed call result, a `for` variable, a `match` on a named value | a `Loan` with `write = false` |
| Exclusive borrow | A writable hold: a `mut` argument, or a `match mut` arm | a `Loan` with `write = true` |
| View | A slice of text, bytes or a list: a pointer and length into its source, read-only, never stored | `ownership.view`, `isBorrowedView` |
| Copy | `copy(value)` or a conversion rule C names; the only way to get a second independent owner | `copy` operations, `E_CORE_HIDDEN_COPY` |
| Loan release | A `const` borrow ends after its last use in its block; an argument loan ends with its call; an arm hold ends after the arm's last use of a payload binding | `releaseBindings`, `armHold` |

A binding is either available or unavailable. A move makes it unavailable; assigning a
whole new value makes it available again. At a join (after `if`, after `match` arms) a
binding is available only if it is available on every incoming path. A loop must leave
every owner it found available as it found it.

## The rules

There are 54 rules in 12 groups. Each rule names the refusal that enforces it. *Limit*
means the checker refuses a program the model would accept.

### T. Types

- **T1 Managed types.** A type is managed when it owns heap storage (see the model).
  Every other type is scalar and is copied on each use.
- **T2 Move-only types.** A resource or provider-dependent value cannot be copied. A
  plain parameter of such a type is refused; it must be `own` or `mut`. Enforced by
  `E_OWN_PARAMETER`.
- **T3 No shared mutable identity.** `class` and `Cell` are refused; identity uses pool
  handles or ids. Enforced by `E_VALUE_CLASS`, `E_VALUE_CELL` and `E_CELL_ELEMENT`.
- **T4 Containment.** List elements cannot hold resources, capabilities or pending
  Results (`E_LIST_ELEMENT`, `E_LIST_CAPABILITY`, `E_LIST_TYPE`). Text and bytes are
  immutable (`E_TEXT_IMMUTABLE`). *Limit:* files live only in named local scopes, and
  owning providers only in plain records (`E_ZERO_RC_UNSUPPORTED`).

### B. Bindings and moves

- **B1 Writability.** A `const` binding, a plain parameter and a loop variable cannot
  be written. Enforced by `E_IMMUTABLE`.
- **B2 Moves.** A managed value moves when it initializes or is assigned to a binding
  from a whole owner, is stored into a field, element or container, is returned, or is
  passed to an `own` position. The source becomes unavailable.
- **B3 Use after move.** Reading, writing or moving an unavailable binding is refused.
  Enforced by `E_SINGLE_OWNER_MOVED`, and in the front end by `E_OWNED_CONSUMED`
  (move-only values) and `E_RESULT_CONSUMED` (Results).
- **B4 Reinitialization.** Assigning a whole value to a `mut` binding makes it
  available again.
- **B5 Joins.** After `if` or `match`, a binding is available only if it is available
  on every path that falls through. A later use is refused by B3; the front end reports
  a move-only value or Result that differs by path as `E_OWNED_PATH`.
- **B6 Loops.** Each owner available when a loop starts must be available at every
  back edge, `break` and `continue`. Enforced by `E_SINGLE_OWNER_LOOP`, and in the
  front end by `E_OWNED_LOOP`.
- **B7 No moving out of a container.** Reading an element or dictionary value as an
  owned value is refused; use `copy`, `pop` or `exchange`. Enforced by
  `E_SINGLE_OWNER_BORROW`, which offers the `const` or write-back repair when it is
  proven.
- **B8 No moving out of a record.** *Limit:* a managed field cannot be moved out of a
  record. The exception is consuming the whole record in straight-line code at the top
  of a function. Enforced by `E_SINGLE_OWNER_BORROW`.
- **B9 `const` of a place borrows.** `const x = place` borrows read-only when the place
  is a parameter, or a field, element or dictionary value of a parameter or owned
  local. The borrow lasts until `x`'s last use in its block. `const x = local` and
  `const x = own_param` move instead.

### R. Read borrows

- **R1 Plain parameters borrow.** A plain parameter of a managed type borrows its
  argument read-only for the call. The callee cannot write, move or store it. Writes:
  `E_MUTATION_MARKER` (front end) and `E_SINGLE_OWNER_BORROW` (Core). Stores:
  `E_SINGLE_OWNER_BORROW` with a `copy` repair.
- **R2 Loans block changes.** While a read loan on an owner is live, nothing may move
  or change that owner or any place in it. Enforced by `E_SINGLE_OWNER_OVERLAP`. Loans
  come from call arguments, `const` borrows, a matched named value, an iterated
  collection, and the left operand of a binary operator.
- **R3 Borrowed call results.** A call whose callee's inferred borrow set names
  arguments returns a borrow of those owners. It may be read in place or bound with
  `const`; storing, moving or passing it `mut` or `own` needs `copy`. Enforced by
  `E_SINGLE_OWNER_BORROW`. *Limit:* more than two owners is refused.
- **R4 Borrowed returns.** A function may return a place of its plain or `mut`
  parameters as a borrow when the inferred borrow set names them. *Limit:* two owners
  at most across all returns (`E_SINGLE_OWNER_BORROW`).
- **R5 One kind of return.** A function cannot return a borrow on one path and a new
  value on another. Enforced by `E_BORROW_MIXED`, with a `copy` repair on each borrowed
  return.
- **R6 Borrowed selections.** A dictionary read with a default borrows either input. It
  is read-only and cannot be stored (`E_SINGLE_OWNER_BORROW`). A view of it is refused
  (`E_SLICE_ESCAPES`).
- **R7 Iteration.** A `for` loop borrows its collection, and the loop variable is
  read-only. Writing through the variable is `E_VALUE_BINDING_WRITE`; changing the
  collection inside the loop is `E_SINGLE_OWNER_OVERLAP`. The run-time trap
  `R_LIST_ITERATION_MUTATION` stays as a backstop.

### M. Exclusive borrows

- **M1 `mut` parameters.** A `mut` parameter is an exclusive borrow of caller storage.
  The callee may read and write it, including rebinding the whole value, but not store,
  move or return it except as R4 allows. A resource stored this way gets the `own`
  repair.
- **M2 Declared mutation.** A function may write only parameters declared `mut`
  (`E_MUTATION_MARKER` at the declaration). A write the analysis cannot place is
  `E_MUTATION_PERMISSION`.
- **M3 Call markers.** A `mut` argument is spelled `mut x` at the call; a missing or
  extra marker is `E_MUTATION_MARKER`.
- **M4 Writable targets.** A change needs a `mut` local owner or a `mut` parameter
  (`E_SINGLE_OWNER_BORROW`). Writing into a call's returned temporary is
  `E_VALUE_TEMPORARY_WRITE`.
- **M5 Disjoint arguments.** A `mut` argument cannot overlap another argument of the
  same call. Two known paths are disjoint at different fields of one record, or at
  different literal indices when both are mutable. Enforced by
  `E_SINGLE_OWNER_OVERLAP`, and in the front end by `E_MUTATION_OVERLAP`.
- **M6 No self-source.** A byte buffer cannot be written from its own octets, and
  `extend` cannot read an overlapping ancestor. Enforced by `E_SINGLE_OWNER_OVERLAP`.

### W. `own` parameters

- **W1 Taking.** An `own` parameter takes its argument; the caller's binding is
  unavailable after the line. The callee owns the value: it may store, return or move
  it, and it is destroyed at the callee's scope end otherwise.
- **W2 Markers.** `own` is written exactly where a named binding or place of a managed
  value is given away, and refused on a fresh value or a scalar. Enforced by
  `E_OWN_ARGUMENT`. The standard storing functions (`append`, `dicts.add`,
  `dicts.append_to`, `sets.add`) take their element `own`.
- **W3 Function types.** A plain move-only position in a function type is refused like
  a parameter (`E_OWN_PARAMETER`).
- **W4 No slice to `own`.** A list slice passed to an `own` parameter would copy
  silently, so it is refused with a `copy` repair (`E_SLICE_ESCAPES`).

### V. Views

- **V1 Slices are views.** `s[a:b]` on text, bytes or a list is a read-only view. It
  allocates nothing and borrows its source until its last use.
- **V2 Views are never stored.** A view cannot go into a record, list, dictionary,
  module constant or callback, even after binding it with `const`. Enforced by
  `E_SLICE_ESCAPES`. Re-binding a view to an owned local copies it.
- **V3 Sources stay put.** Changing or moving a source while a view of it is live is
  refused (`E_SLICE_ESCAPES`). The retired `TextView` and `ByteView` types also refuse
  a loop that invalidates a view made outside it (`E_ZERO_RC_VIEW_INVALIDATED`); a
  slice view is refused at its next use instead.
- **V4 Returned views.** A function returns a text slice as a view only when every path
  returns a view of its single borrowable parameter: its one managed parameter that is
  neither `mut` nor a capability. Whether it does is inferred from the body
  (`inferred.view_source`). Any other returned slice is refused with a `copy` repair
  (`E_SLICE_ESCAPES`). *Limit:* a bytes or list slice is never returned as a view. A
  view-returning function cannot be a function value (`E_VIEW_FUNCTION_VALUE`).
  `E_ZERO_RC_VIEW_SIGNATURE` covers only the retired typed views.
- **V5 Joins of views.** Two views of the same source merge as one view. Views of
  different sources make the binding unavailable, and the repair copies.
- **V6 Dictionary views.** `keys()`, `values()` and `items()` views cannot be stored or
  passed (`E_VIEW_STORED`). A recursive stored value cannot hold a live view cycle
  (`E_LIVE_VIEW_CYCLE`).
- **V7 View operations.** A view supports slicing, indexing, `len`, `copy` and printing
  text. The retired typed views also refuse other operators, conversions and byte
  printing (`E_ZERO_RC_VIEW_UNSUPPORTED`).

### X. Matches

- **X1 Matching a name borrows.** A match on a named value holds it while an arm that
  binds a payload runs, until that arm's last use of a binding. A match on a fresh
  value (a call or a constructor) consumes it, and the payload transfers. Conflicts are
  `E_SINGLE_OWNER_OVERLAP`.
- **X2 `match mut`.** The scrutinee must be a local, field or list element with a
  mutable owner (`E_MATCH_MUT`). Bindings write through to the place and cannot be
  moved or stored (`E_SINGLE_OWNER_BORROW`). *Limit:* a dictionary element is refused
  until exchange lands (`E_MATCH_MUT`).

### P. Resources and providers

- **P1 Origin.** Every resource comes from a provider bound to a named local, and one
  carrier cannot combine providers. Enforced by `E_ZERO_RC_RESOURCE_ORIGIN`.
- **P2 Lifetime.** A resource cannot outlive its provider or its `with` scope, and a
  provider cannot move or change while a dependent resource is live. Enforced by
  `E_ZERO_RC_RESOURCE_ESCAPE`.
- **P3 Returned resources.** A returned resource must depend on the function's single
  provider or resource input (`E_ZERO_RC_RESOURCE_ESCAPE`, `E_ZERO_RC_RESOURCE_ORIGIN`).
- **P4 Scoped handles.** An open file binding cannot be stored, passed or returned
  (`E_WITH_RESOURCE`). *Limit:* dependent capabilities need a `with` scope opened
  directly from a named provider, and provider owners cannot be copied
  (`E_ZERO_RC_UNSUPPORTED`).
- **P5 Provider contexts.** A borrowed provider context and an optional provider are
  read-only and cannot be stored or returned (`E_SINGLE_OWNER_BORROW`).

### K. Tasks

- **K1 Lent arguments.** A task borrows its arguments read-only until its group's block
  ends. Writing a lent value is `E_TASK_LOAN`; a `mut` argument is `E_TASK_MUT`; a
  resource or `Host` argument is `E_TASK_RESOURCE` or `E_TASK_HOST`.
- **K2 Scoped groups and handles.** A group exists only as a `with` scope
  (`E_TASK_GROUP`). Groups and handles are never stored, passed or returned
  (`E_TASK_ESCAPE`). A handle initializes a `const` (`E_TASK_HANDLE`) and is read
  before the group ends (`E_TASK_RESULT_UNREAD`).
- **K3 `parallel.map`.** The input and trailing arguments are lent to every item. A
  slice or borrowed list parameter needs `copy` (`E_SLICE_ESCAPES`). `own` arguments,
  more than five, and fallible functions are `E_PARALLEL_MAP_ARGS`; `mut` is
  `E_TASK_MUT`.

### L. Result obligations

- **L1 Linear Results.** A Result must be handled, returned or transferred before its
  scope ends (`E_RESULT_UNHANDLED`). It cannot be overwritten (`E_RESULT_OVERWRITE`),
  used after transfer (`E_RESULT_CONSUMED`) or dropped by `try`
  (`E_RESULT_PROPAGATION`). Paths and loops must agree, as in B5 and B6.

### C. Copies and destruction

- **C1 Written copies.** Every run-time copy is a `copy(value)` or a conversion rule C
  names. A shape that would copy silently is refused with the `copy` repair. Under
  `--verify-facts`, a hidden copy in Core is `E_CORE_HIDDEN_COPY`.
- **C2 `old` captures.** `old(x)` in `@ensures` copies at entry; `old` of shared
  mutable storage is `E_CONTRACT_OLD_SHARED`.
- **C3 Destruction.** Core destroys each owner after its last use on every path,
  including early returns and `try`. `@noalloc` is checked on the destroyed and copied
  Core (`E_NOALLOC_ALLOCATES`).

### Z. Whole-function limits

- **Z1 Evaluation temporaries.** *Limit:* a call whose arguments need evaluation
  temporaries, or a callback call, must bind its arguments first
  (`E_SINGLE_OWNER_UNSUPPORTED`).
- **Z2 Analysis budget.** *Limit:* when the mutation analysis runs out of its
  fixed-point budget, the program is refused (`E_MUTATION_LIMIT`).
- **Z3 Build-time refusals.** *Limit:* `selka build` can refuse a program
  `selka check` accepted, when a Core builder or the ownership pass in `own.zig`
  cannot place an operation (`E_CORE_UNSUPPORTED`).

## Refusal codes mapped to rules

All 55 ownership refusal codes map to at least one rule. Eight are exercised by no test
or doc example. "Raised in" names the non-test source files that emit the code (Core
files under `src/core/`, all others under `src/`). "Tests" counts test and doc files
that name the code.

| Code | Rules | Raised in | Tests |
| --- | --- | --- | ---: |
| `E_BORROW_MIXED` | R5 | core/single_owner | 6 |
| `E_CELL_ELEMENT` | T3 | cell_types | 1 |
| `E_CONTRACT_OLD_SHARED` | C2 | sema_contracts | 0 |
| `E_CORE_HIDDEN_COPY` | C1 | core/verify_ir | 3 |
| `E_CORE_UNSUPPORTED` | Z3 | core/pipeline, from core/build* and core/own | 16 |
| `E_IMMUTABLE` | B1 | sema, sema_places, sema_calls, sema_statements, generic_bodies | 25 |
| `E_LIST_CAPABILITY` | T4 | record_layouts | 5 |
| `E_LIST_ELEMENT` | T4 | record_layouts | 0 |
| `E_LIST_TYPE` | T4 | sema_collections, collection_lower | 4 |
| `E_LIVE_VIEW_CYCLE` | V6 | view_cycles | 3 |
| `E_MATCH_MUT` | X2 | sema_statements, core/single_owner | 2 |
| `E_MUTATION_LIMIT` | Z2 | origins | 0 |
| `E_MUTATION_MARKER` | R1, M2, M3 | origins, sema_simd, scalar_text_helpers | 27 |
| `E_MUTATION_OVERLAP` | M5 | origins | 36 |
| `E_MUTATION_PERMISSION` | M2 | origins | 5 |
| `E_NOALLOC_ALLOCATES` | C3 | lint, core/allocation_contract | 14 |
| `E_OWNED_CONSUMED` | B3 | sema, sema_calls, generic_bodies | 6 |
| `E_OWNED_LOOP` | B6 | sema, generic_bodies | 2 |
| `E_OWNED_PATH` | B5 | sema, generic_bodies | 2 |
| `E_OWN_ARGUMENT` | W2 | own_parameters, scalar_text_helpers | 7 |
| `E_OWN_PARAMETER` | T2, W3 | own_parameters | 6 |
| `E_PARALLEL_MAP_ARGS` | K3 | sema | 2 |
| `E_RESOURCE_TYPE` | P1 | sema_collections, generic_bodies | 0 |
| `E_RESULT_CONSUMED` | B3, L1 | sema_calls, sema_expressions, sema_collections, generic_bodies | 4 |
| `E_RESULT_OVERWRITE` | L1 | sema_places, sema_statements, generic_bodies | 5 |
| `E_RESULT_PROPAGATION` | L1 | sema_expressions, generic_bodies | 0 |
| `E_RESULT_UNHANDLED` | L1 | sema, generic_bodies | 18 |
| `E_SINGLE_OWNER_BORROW` | B7, B8, R1, R3, R4, R6, M4, X2, P5 | core/single_owner, core/borrow_repair | 29 |
| `E_SINGLE_OWNER_LOOP` | B6 | core/single_owner | 5 |
| `E_SINGLE_OWNER_MOVED` | B3 | core/single_owner | 13 |
| `E_SINGLE_OWNER_OVERLAP` | R2, R7, M5, M6, X1, X2 | core/single_owner | 41 |
| `E_SINGLE_OWNER_UNSUPPORTED` | Z1 | core/single_owner | 0 |
| `E_SLICE_ESCAPES` | R6, V2, V3, V4, W4, K3 | core/single_owner | 19 |
| `E_TASK_ESCAPE` | K2 | sema_tasks | 4 |
| `E_TASK_GROUP` | K2 | sema_tasks | 4 |
| `E_TASK_HANDLE` | K2 | sema_tasks | 4 |
| `E_TASK_HOST` | K1 | sema_tasks | 4 |
| `E_TASK_LOAN` | K1 | sema_tasks | 3 |
| `E_TASK_MUT` | K1, K3 | sema_tasks, sema | 7 |
| `E_TASK_RESOURCE` | K1 | sema_tasks | 4 |
| `E_TASK_RESULT_UNREAD` | K2 | sema_tasks | 4 |
| `E_TEXT_IMMUTABLE` | T4 | sema_collections, generic_bodies | 1 |
| `E_VALUE_BINDING_WRITE` | R7 | value_semantics_check | 4 |
| `E_VALUE_CELL` | T3 | cell_types, nominal_templates, generic_bodies | 6 |
| `E_VALUE_CLASS` | T3 | nominal_templates | 6 |
| `E_VALUE_TEMPORARY_WRITE` | M4 | value_semantics_check | 6 |
| `E_VIEW_FUNCTION_VALUE` | V4 | view_function_value | 6 |
| `E_VIEW_STORED` | V6 | dictionary_views, nominal_templates | 11 |
| `E_WITH_RESOURCE` | P4 | sema_shared | 4 |
| `E_ZERO_RC_RESOURCE_ESCAPE` | P2, P3 | core/single_owner | 3 |
| `E_ZERO_RC_RESOURCE_ORIGIN` | P1, P3 | core/single_owner | 1 |
| `E_ZERO_RC_UNSUPPORTED` | T4, P4, plus internal consistency checks | core/single_owner | 8 |
| `E_ZERO_RC_VIEW_INVALIDATED` | V3 | core/single_owner | 2 |
| `E_ZERO_RC_VIEW_SIGNATURE` | V4 | core/single_owner | 0 |
| `E_ZERO_RC_VIEW_UNSUPPORTED` | V7 | core/single_owner | 0 |

Not in the table: `E_ARENA_REMOVED`, `E_COPY_METHOD_REMOVED` and
`E_BORROW_VIEWS_REMOVED` refuse retired spellings and need no rule. The lints
`L_COPY_FOR_STORE`, `L_COPY_IN_LOOP` and `L_NEEDLESS_COPY` advise but never refuse.

## Prototype refusals

27 refusals are implementation limits, not language rules. That counts the 12 checker
lines that say "prototype", 11 more `E_ZERO_RC_*` sites, and 4 other limits. Accepted
on 24 October: lift 8, make 8 into rules, delete 8 and turn 3 into internal errors.

Line numbers are in `src/core/single_owner.zig` at `68ed3981d` unless the row says
otherwise. Rows 1–5 check `TextView` and `ByteView` types, which source can no longer
spell: `func f(t: TextView)` is refused with `E_BORROW_VIEWS_REMOVED` before this
checker runs.

| # | Site | Code | What it says | Rule | Proposal | Why |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | 316 | `E_ZERO_RC_VIEW_SIGNATURE` | a function returning a view cannot also take mut parameters in this prototype | V4 | Delete | Typed views only |
| 2 | 1633 | `E_ZERO_RC_VIEW_UNSUPPORTED` | view bindings are immutable in this prototype | V7 | Delete | Typed views only |
| 3 | 2213 | `E_ZERO_RC_VIEW_UNSUPPORTED` | printing ByteView requires an explicit copy(value) in this prototype | V7 | Delete | Typed views only |
| 4 | 2278 | `E_ZERO_RC_VIEW_UNSUPPORTED` | view binary operations are outside this prototype | V7 | Delete | Typed views only |
| 5 | 2777 | `E_ZERO_RC_VIEW_INVALIDATED` | a loop cannot invalidate a view created outside it in this prototype | V3 | Delete | Typed views only; slice views are already refused at their next use |
| 6 | 1869 | `E_SINGLE_OWNER_BORROW` | this call borrows from more owners than this prototype tracks | R3 | Lift the limit | A fixed table of 8 owners |
| 7 | 1870 | `E_SINGLE_OWNER_BORROW` | this call keeps more than two owned values alive | R3 | Lift the limit | Core tracks two owners per borrow |
| 8 | 1989 | `E_SINGLE_OWNER_BORROW` | the returns would borrow from more than two parameters | R4 | Lift the limit | Same two-owner limit |
| 9 | 2040 | `E_SINGLE_OWNER_BORROW` | moving a field out of a record is outside this prototype | B8 | Make it a rule | "Fields never move out of a record that stays usable" avoids partial moves, which complicate the proof |
| 10 | 2197 | `E_SINGLE_OWNER_UNSUPPORTED` | calls requiring argument-evaluation temporaries are outside this prototype | Z1 | Lift the limit | Lowering can bind them; state left-to-right evaluation as a rule |
| 11 | 2204 | `E_SINGLE_OWNER_UNSUPPORTED` | bind callback arguments before calling in this prototype | Z1 | Lift the limit | As row 10 |
| 12 | 3194 | `E_ZERO_RC_UNSUPPORTED` | open a dependent scope directly from a named provider in this prototype | P4 | Make it a rule | Part of P1; raise as the resource-origin code |
| 13 | 921 | `E_ZERO_RC_UNSUPPORTED` | copied Host adapters are retired | none | Delete | `host func` is retired |
| 14 | 939 | `E_ZERO_RC_UNSUPPORTED` | store file owners in named local scopes | P4 | Make it a rule | Same rule as `E_WITH_RESOURCE` |
| 15 | 943 | `E_ZERO_RC_UNSUPPORTED` | owning providers can be stored only in ordinary records or tuples | T4 | Make it a rule | Tuples are removed; drop them from the text |
| 16 | 2011 | `E_ZERO_RC_UNSUPPORTED` | invalid complete tuple staging | none | Internal error | Compiler consistency check, tuples removed |
| 17 | 2115 | `E_ZERO_RC_UNSUPPORTED` | invalid borrowed selection type contract | none | Internal error | Compiler consistency check |
| 18 | 2338 | `E_ZERO_RC_UNSUPPORTED` | dependent capabilities require a with scope | P4 | Make it a rule | A real rule with a borrowed code |
| 19 | 2488 | `E_ZERO_RC_UNSUPPORTED` | retained views are unsupported | none | Delete | Refuse `.view()` in the front end as a retired spelling |
| 20 | 2494 | `E_ZERO_RC_UNSUPPORTED` | provider owners cannot be copied | T2 | Make it a rule | Move-only types, as `E_OWN_PARAMETER` |
| 21 | 3184 | `E_ZERO_RC_UNSUPPORTED` | zero-RC scopes require an explicit file owner | none | Internal error | A `with` with no resource; the front end should never produce it |
| 22 | 3195 | `E_ZERO_RC_UNSUPPORTED` | bind the provider or its enclosing record to a local before opening a scope | P1 | Make it a rule | Raise as the resource-origin code |
| 23 | 2399 | `E_ZERO_RC_RESOURCE_ORIGIN` | this resource origin is outside the local checked contract | P1 | Make it a rule | List the origins that exist and refuse the rest by name |
| 24 | 589 | `E_SLICE_ESCAPES` | a returned bytes slice would outlive its source | V4 | Lift the limit | Text slices can be returned as views; bytes slices never can |
| 25 | `origins.zig` 1209 | `E_MUTATION_LIMIT` | mutation origin analysis exhausted its fixed-point budget | Z2 | Lift the limit | Refuses the whole program; summaries from declared `mut` sets need no fixed point |
| 26 | `sema_statements.zig` | `E_MATCH_MUT` | a dictionary element is refused until its exchange lands | X2 | Lift the limit | Planned |
| 27 | 2061 | (falls to row 9) | a field moves only in straight-line code at the top of a function | B8 | Delete | Backend limit noted in `canMoveAffineField`; goes with row 9 |

## Gaps found while mapping

Every code maps to a rule, but the mapping is not one-to-one. Several rules are checked
twice, and some acceptance depends on facts inferred from other functions' bodies.

1. **Rules checked twice under different codes.** Use after move is
   `E_OWNED_CONSUMED` in the front end and `E_SINGLE_OWNER_MOVED` in Core; loops are
   `E_OWNED_LOOP` and `E_SINGLE_OWNER_LOOP`. Overlap is `E_MUTATION_OVERLAP` (judged by
   origin and type) and `E_SINGLE_OWNER_OVERLAP` (judged by place path). `E_MATCH_MUT`
   is raised in both layers too: the place's shape in the front end, the owner's
   mutability in Core. The accepted language is the intersection of two checkers.
2. **A third copy for generics.** `generic_bodies.zig` (3,906 lines) re-checks generic
   instances with its own versions of B1, B3, B5, B6 and L1.
3. **Facts inferred from other bodies.** R3, R4 and V4 read the callee's
   `inferred.borrow_set` and `inferred.view_source`, computed from bodies by a
   whole-program fixed point (`borrow_set.zig`, `origins.zig`). M2's analysis is a
   fixed point too, with a budget that refuses the whole program when exhausted (Z2).
   None of these can be checked one function at a time from signatures.
4. **Moves depend on types, not syntax.** B2 moves silently at `mut b = a`, at stores
   and at returns. W2 requires `own` only at call positions. Whether a line moves
   depends on whether the type is managed.
5. **`const` has two meanings.** Under B9, `const x = xs[1]` borrows but
   `const x = xs` moves.
6. **One code covers many rules.** `E_SINGLE_OWNER_BORROW` covers 9 rules,
   `E_SINGLE_OWNER_OVERLAP` 6 and `E_SLICE_ESCAPES` 6. A refusal should name its rule,
   by its own code or by a rule id in the diagnostic.
7. **Codes named for a retired model.** Six `E_ZERO_RC_*` codes still name the
   reference-counting experiments. Rows 12–23 of the prototype table move most of their
   sites to rule codes.
8. **Probably unreachable paths.** The typed-view checks (prototype rows 1–5,
   `E_ZERO_RC_VIEW_SIGNATURE`, `E_ZERO_RC_VIEW_UNSUPPORTED`) can only fire on
   `TextView` or `ByteView`, which source cannot spell. No coverage run confirmed this.
9. **Eight codes with no test or doc example:** `E_CONTRACT_OLD_SHARED`,
   `E_LIST_ELEMENT`, `E_MUTATION_LIMIT`, `E_RESOURCE_TYPE`, `E_RESULT_PROPAGATION`,
   `E_SINGLE_OWNER_UNSUPPORTED`, `E_ZERO_RC_VIEW_SIGNATURE` and
   `E_ZERO_RC_VIEW_UNSUPPORTED`.
10. **A run-time backstop.** `R_LIST_ITERATION_MUTATION` still traps at run time, so R7
    is not trusted to be complete. Either show which shapes reach the trap, or prove R7
    and drop it.
11. **Destruction has no checked rule.** C3 is placed by `own.zig`, which fails closed
    with an internal error. In a proof, this is the part a per-function certificate and
    validator would cover.
12. **Text that disagrees with the checker.** `managed-memory.md` says a view-returning
    function cannot take `mut` parameters; the slice check allows them, and only typed
    views enforce it. The Core comment at `single_owner.zig:300` calls a plain
    move-only parameter "the hand-over spelling", which `E_OWN_PARAMETER` now refuses.
    The header of `value_semantics_check.zig` still calls loop variables copies and
    `class` values writable references.
13. **`check` and `build` accept different programs.** `E_CORE_UNSUPPORTED` refuses at
    build time programs that `check` accepted. It comes from 182 refusal call sites in
    the Core builders and 15 in `own.zig`. Not all are ownership limits, and none was
    sorted for this draft.

## Decisions of 24 October 2026

Codex implements these through the
[ownership rules plan](../audits/ownership-rules-plan-2026-10-24.md).

- **D1 One layer per rule.** Core owns the move and borrow rules; the front end keeps
  spelling rules (markers, `class`/`Cell`, task scoping, Result obligations).
  `E_OWNED_CONSUMED`, `E_OWNED_LOOP`, `E_OWNED_PATH` and `E_MUTATION_OVERLAP` retire
  after a corpus comparison.
- **D2 Borrow sets in signatures.** A borrowed result is declared `-> Json from doc`
  (several owners: `from d, fallback`). `selka fix` inserts the clause from today's
  inferred set.
- **D3 `own` on every move.** `own` marks every move of a named binding
  (`mut ys = own xs`, `r.items = own xs`); a binding without `own` borrows, so
  `const ys = xs` borrows. Returns stay unmarked. `selka fix` inserts the markers.
- **D4 Prototype dispositions.** Accepted as drafted in the table above.

## Method and sources

The checkers were read on main `68ed3981d` and probed with the installed compiler
(built 23 October). Nothing in the repository was changed by the draft.

- **Core checker:** `src/core/single_owner.zig`, read in full for its state, access,
  loan, store, call, loop, match, return, view and resource rules. Refusal sites were
  extracted by script from every `reject` call.
- **Front end:** `own_parameters.zig`, `origins.zig`, `sema_tasks.zig`,
  `value_semantics_check.zig` and the sites that raise each code, located with `grep`
  and read at the raising site, not in full.
- **Code meanings:** `src/diagnostic_codes.zig`, the index `selka reference` answers.
- **Test counts:** files under `src/`, `test/`, `tests/` and `docs/` whose test, `.selka`
  or `.md` text names the code. A count is a reference, not proof the refusal fires.
- **Probes:** `func f(t: TextView)` gives `E_BORROW_VIEWS_REMOVED`; `const ys = xs` and
  `mut ys = xs` both make `xs` unavailable (`E_SINGLE_OWNER_MOVED`).

Not verified: whether the typed-view paths are reachable (needs a coverage run), how
often the front end and Core disagree on overlap, and the rules inside `own.zig` and
`verify_ir.zig` beyond the two codes they raise.
