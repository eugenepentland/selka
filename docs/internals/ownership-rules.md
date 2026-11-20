# Ownership rules: internals

Maintainer detail moved out of the user guide [`docs/ownership-rules.md`](../ownership-rules.md). The headings match the
guide's, so its "How it works" links land here. The paragraphs are the guide's earlier text, unchanged; the guide keeps a
shorter statement of each rule. This folder is not part of the published site.

## Keeping pieces of a buffer

A name that repeats, in many headers or many files, is better kept once. [`symbols.intern`](../standard-library.md#symbols)
answers a `Symbol`, one integer, and copies the text only the first time it sees it: interning a name the table already holds
allocates nothing. The `Symbol` is stored, compared with `==` and used as a dictionary key; `symbols.name(table, symbol)` reads
the text back as a view of the table. What it costs is a hash of the name at each `intern` and a table that grows with the
distinct names and never shrinks; what it gives is that equal names are equal numbers. A million uses of one 34-octet name held
about 12 MB at its peak where a million copies held about 104 MB (a `--release` run, 17 November 2026).

## Proof coverage

Since 26 October 2026 a Debug compiler checks the final Core IR of every function with the
ownership validator (checks J1 to J8, `src/core/validate_ownership.zig`), and a Lean proof
(`proofs/ownership`, `Own.check_sound`) shows that a function that passes the same
checks never faults: no read or destruction of a dead allocation, no second
destruction, no consumption of a borrowed value, no stack value escaping, and no leak
at a normal return. `Own.runs_sound` and `Own.main_no_leak` extend that to a whole
program. The proof covers the run-time property a rule protects. It does not prove
that the source checker enforces the rule's predicate. The optimizer's fact checks
(F1 to F7, `docs/tooling/fact-certificates.md`) concern value ranges and the
overflow, division, shift and bounds checks a release build drops, so none of the 54 rules
is proved by them. The design is
ownership certificates (`docs/design/ownership-certificates.md`) (the classification is its
section 7); the guide is `docs/tooling/ownership-certificates.md`;
the totals, the assumptions and the costs are in the
report (`docs/audits/ownership-certificates-report-2026-10-26.md`).

The kind column says what the proof can say about a rule:

- **safety** (36 rules): a run-time property that J1 to J8 check in the final IR and the
  proof covers. The three task-group rules K1 to K3 were stage 2 in the design and are
  covered since C6.
- **clarity** (12 rules): a source discipline the proof does not need. Where a clarity
  rule is the spelling of a move or a transfer, the move itself is proved and the
  marker is not.
- **type** (6 rules): a type-level rule the model takes as given.

| Rule | Kind | Proved by | Lean lemmas (`Own.`) | Rests on |
| --- | --- | --- | --- | --- |
| T1 | type | none: the model takes the type split as given | - | A1 |
| T2 | type | none: owned and borrowed states are the model's | - | A1 |
| T3 | type | none: model assumption (the heap is a forest of owner trees, `wf` and `apart` in the contract) | - | A2 |
| T4 | type | none: the model takes containment as given | - | A1 |
| B1 | clarity | none | - | - |
| B2 | clarity | the move itself: J2 | consumeLive_ok, consumeOnce_ok | A3, A4, A10 |
| B3 | safety | J2, J3 | consumeLive_ok, consumeOnce_ok, readsAlive_ok | A3, A4, A10 |
| B4 | safety | J2 | consumeLive_ok, consumeOnce_ok, post_core | A3, A4, A10 |
| B5 | safety | J2 | edge_inv, post_core | A3, A4, A10 |
| B6 | safety | J2 | edge_inv, post_core | A3, A4, A10 |
| B7 | safety | J5, J8 | notBorrowed_ok, transferOk_ok, closeOk_ok, noStale_ok | A8 |
| B8 | safety | J2 (`record_take`) | consumeLive_ok, post_core | A3, A4, A10 |
| B9 | safety | J4 | readsAlive_ok, loansLive_ok | A12; gaps A13-A15 |
| R1 | safety | J1, J5 | inst_step, notBorrowed_ok | A3 |
| R2 | safety | J4 | readsAlive_ok, loansLive_ok | A12; gaps A13-A15 |
| R3 | safety | J1, J4 | inst_step, readsAlive_ok, loansLive_ok | A3, A12; gaps A13-A15 |
| R4 | safety | J5 | notBorrowed_ok, post_core | - |
| R5 | safety | J1 | inst_step, edge_inv | A3 |
| R6 | safety | J1 (phi) | edge_inv | A3 |
| R7 | safety | J4 | readsAlive_ok, loansLive_ok | A12; gaps A13-A15 |
| M1 | safety | J1, J2 | inst_step, consumeLive_ok, post_core | A3, A4, A10, A16 |
| M2 | clarity | none | - | - |
| M3 | clarity | none | - | - |
| M4 | clarity | none | - | - |
| M5 | safety | J6 | separate_ok | - |
| M6 | safety | J6 | separate_ok | - |
| W1 | safety | J2 | consumeLive_ok, consumeOnce_ok, post_core | A3, A4, A10 |
| W2 | clarity | the transfer: J2 | consumeLive_ok, consumeOnce_ok | A3, A4, A10 |
| W3 | type | none: the signature's states are the model's | - | A1 |
| W4 | safety | J5 | notBorrowed_ok | - |
| V1 | safety | J1, J4 | inst_step, readsAlive_ok | A3, A12; gaps A13-A15 |
| V2 | safety | J5 | notBorrowed_ok | - |
| V3 | safety | J4 | readsAlive_ok, loansLive_ok | A12; gaps A13-A15 |
| V4 | safety | J5 | notBorrowed_ok, post_core | - |
| V5 | safety | J1 (phi) | edge_inv | A3 |
| V6 | safety | J4, J5 | readsAlive_ok, notBorrowed_ok | A12; gaps A13-A15 |
| V7 | type | none: the class table gives each view operation's state | - | A1 |
| X1 | safety | J1, J4 | inst_step, readsAlive_ok | A3, A12; gaps A13-A15 |
| X2 | safety | J4, J6 | readsAlive_ok, separate_ok | A12; gaps A13-A15 |
| P1 | clarity | none | - | - |
| P2 | safety | J2, J4 | consumeLive_ok, post_core, readsAlive_ok | A3, A4, A10, A12 |
| P3 | safety | J5 | notBorrowed_ok, post_core | - |
| P4 | safety | J4 | readsAlive_ok, loansLive_ok | A12; gaps A13-A15 |
| P5 | safety | J4, J5 | readsAlive_ok, notBorrowed_ok | A12; gaps A13-A15 |
| K1 | safety | J4 (`loan-outlives-root`) | lentSafe_ok, root_consumed | A7.1, A7.2, A7.5, A7.7 |
| K2 | safety | J2 (`group-join`), J3 | consumeLive_ok, consumeOnce_ok, readsAlive_ok | A7.3-A7.6, A7.7 |
| K3 | safety | none of its own: `myl_core_owned_map*` is an ordinary call that joins | - | A7.8 |
| L1 | clarity | leaks: J2 | post_core | A3, A4, A10 |
| C1 | clarity | none (checked at run time by `--verify-written-copies`) | - | - |
| C2 | clarity | none | - | - |
| C3 | safety | J2 | consumeOnce_ok, post_core | A3, A4, A10 |
| Z1 | safety | J2 | consumeLive_ok, post_core | A3, A4, A10 |
| Z2 | clarity | none | - | - |
| Z3 | clarity | none | - | - |

The lemmas are in `proofs/ownership` and are all consequences of the one per-function
theorem `Own.check_sound`; each is the step that rules out one fault of the model
(`Fault` in `Semantics.lean`) from one check:

| Lemma | Check | What it says for a function that passes the checks |
| --- | --- | --- |
| `inst_step`, `edge_inv` | J1 | one instruction and one phi edge keep the invariant that relates the checker's state (live set, roots, loans, open takes) to the machine state |
| `consumeLive_ok`, `consumeOnce_ok` | J2 | every consumed tree is live and no tree is consumed twice by one instruction (`consumeDead`, `destroyTwice`) |
| `post_core`, `ret_some_facts` | J2, J5, J8 | at a `ret` nothing the call allocated or was given to own is left live, nothing is pending, and a borrowed result lies inside the trees its `from` set names |
| `abandon_inv` | J2 | an edge into a trap region that abandons owners keeps the invariant, so a leak is allowed on a path to a trap and on no other |
| `readsAlive_ok` | J3, J4 | every operand an instruction reads is live (`readDead`) |
| `loansLive_ok` | J4 | the cells an owned value points into are live where it is read (`dangling`) |
| `lentSafe_ok`, `root_consumed` | J4 | a cell lent to a live group is not destroyed before the group ends (`lentGone`) |
| `notBorrowed_ok` | J5 | no consumed operand is a borrowed value (`takeBorrowed`) |
| `separate_ok` | J6 | an instruction does not consume a tree another operand still reads into (`overlap`) |
| `noEscape_ok` | J7 | a stack value is consumed only by a filling push and is never returned (`escape`) |
| `transferOk_ok`, `closeOk_ok`, `noStale_ok` | J8 | a take reads a live owned slot that is not already taken, a closing update agrees with the open slots, and a container with an open take is consumed only by its closing update (`stranded`) |

J7 has no source rule: it checks the compiler's own stack promotion (the S1 pass).

Every safety row also rests on A1 (the operation-class table describes the emitter and the
runtime), A2 (`drop` frees exactly its operand's tree and allocation returns disjoint
storage), A5 (external functions meet their contracts), A6 (LLVM emission keeps the
instruction order for ownership effects) and A9 (the entry function's scalar parameters
receive immediates; inside the program J1 checks it at each call). Calls through function
values rest on A17 (a function value points to a function with the signature of its type).
The last column adds what the row's own checks need: A3 (`undef` of a managed type is the
null owner), A4 (immortals are never freed), A8 (a repeated pure comparison gives the same
answer; the guards of J8), A10 (a closing update through a null owner returns a null owner),
A11 (the `stack` state is exactly a stack list of this activation), A12 (the parents the
certificate lists cover everything an owned value points into), A16 (the storage of an
`emptied` call result is what the caller takes out at once) and A7.1 to A7.8 (the runtime
contracts of task groups). "Gaps A13-A15" marks the three loan assumptions the validator and
the Lean checker enforce but the theorem does not cover: A13 (a take marked `noloans`
carries no loans, and a view into itself does not survive an update), A14 (the slot-level
end of a loan) and A15 (a view written before the take that owns its storage). The list,
and what would close each assumption, is in
`proofs/ownership/AXIOMS.md`; the layer table above says
where the compiler decides a rule, and this table says what the proof covers in the final IR.

## Rule 1: Escape

### B2 — Moves

In expressions, `own` is a marker only when separated from a following identifier
on the same logical line (an open group permits continuation).
Before any other token it is an ordinary name: `own - 1` subtracts from a binding
named `own`, and `own (value)` calls it. Write a grouped move as `(own value)`;
a fresh identifier-led call such as `own make()` is refused because it needs no
marker.

### B7 — No moving out of a container

An element of a new list is the exception: when the list is the result of a call that
lends nothing (its result is not declared `from` a parameter) or a list literal, nothing
else can name it, so `strings.split(text, sep)[1]` in a position that takes a value (a
binding, an assignment, a `return`, a store, an `own` argument, a constructor's field, a
list literal's element, `Some`) moves the element out and drops the rest of the list. The
index's bounds check and its trap are unchanged. A new dictionary's `TEMP[key]` moves its
value out the same way. A read in a borrowing position still borrows, and a list lent by
a call, a field of an element (`rows()[1].tags`) and a slice still need `copy(...)`.

### B9 — Const place bindings borrow

A `mut` local whose every assignment, its initializer included, reads a place without
`own` borrows the same way, whether it is assigned once or more: `mut net = port.name`
then `if ...: net = port.net` needs no copy, and neither does `mut net = port.name` read
alone. A write through such a local stored once (`append(mut net, ...)`, `net.f = v`,
`net[i] = v`, a `mut` argument) is refused at the write, which names the binding and both
repairs at it, `mut net = own place` to give a bare owner and `mut net = copy(place)` to
keep both; `selka fix` writes the copy. A local assigned more than once and written keeps
its refusal at the store that needs the copy. Its loans are the union of every assignment's places, held to its last use, so
changing any of those owners while it is live is refused, across loop iterations too;
the local itself cannot be changed, moved or stored, may be returned only under `from`,
and cannot borrow an owner that a loop makes again in each iteration while the local
lives past it. Such a refusal names the store that needs `copy(...)`, with its repair.
Beside those places, an assignment may also be a result that borrows (a call with a `from`
contract, `atom_of(x).unwrap_or(b"")`), and, when every place it reads is the caller's
storage (a plain parameter, a loop variable over one, or a `const` alias of either), a text
or bytes literal: `mut suffix = raw` then `suffix = b"R"`, or `mut mpn = b""` then
`mpn = p.value` in a loop over a parameter.

A slice of such a place reads it the same way, for text, bytes and lists: `mut head = p[0:2]`, then
`if ...: head = port.name`, copies nothing, and neither does a local rebound to its own tail. A list slice is
a view of the elements. Writing through it, storing it or changing its owner while it is live keeps the
slice's refusal (V2) at the store, with `copy(...)` around the slice.

After `if x is None: return` (or `fail`, `break`, `continue`), a read of `x` is its payload
read in place, as `x.unwrap_or(d)` of an option local is: `const id = x.unwrap_or(b"")`
borrows `x`, so `x` cannot change while `id` is live. A loop variable names an element of
the place it iterates, so `for pn in ledger.pins: remember(mut ledger.names, pn.net)` passes
a disjoint field, and the loop variable is read again after the write. A `match` arm whose
payload owns no storage (a number, a flag, a record of those) is copied when bound, fielded
or not, so the arm may change the place it matched, or the list or record that holds it
(`case Some(sec): attach[i] = None`, `case num(v=n): t.keys[at] = Key.other`), and `n` keeps the
value it had. A payload that holds text, bytes, a list, a dictionary or a resource is not copied,
and `match mut` writes its place: both hold the place until the arm's last use of a binding.

Where the function owns `x` (a `const` or `mut` local, or an `own` parameter), `own x` after
such a test (or in the `else:` of `if x is None:`) moves the payload out and consumes `x`, as
`const p = own x else:` does, with no copy; a bare `return x` or `fail x` gives it the same
way. A later read of `x` is then a use after the move, a `mut` `x` may be assigned again, and a
move in a loop `x` was declared outside of is refused as any such move is. A bare `x` stored
where a value is kept is refused (B7) with `own x` offered first and `copy(x)` second, and
`selka fix` writes the `own` where nothing reads `x` after it and no loop runs it again. A
plain or `mut` parameter, a loop variable and a `match` binding only lend: `own x` of one is
refused (B2) naming the lender, and `selka fix` writes `copy(x)` in its place.

A record constructor whose managed fields all borrow is a borrowed value too, as a `from`
result is: `RailSpot(net=b.power, x=1)` copies nothing. At least one managed field must
borrow, and every managed field must be one of these.

**Sources** (each read bare, with no `own`):
- a place: a field, an element or a dictionary value of a named binding;
- a bare owner, an `own` or `mut` parameter, a loop variable or a binding of a record;
- a plain parameter (not `own`, not `mut`) of a record, dictionary or set type, which is
  the caller's storage;
- a plain text, bytes or list parameter. It arrives as a view, so the record holds a
  *frame block*: the caller's own text or list when the argument was a whole value, else
  one copy this call makes the first time it builds such a record and frees when it
  returns. Bytes carry no owner, so a bytes argument is always copied this way, and so is
  a slice. `--stats` counts these sites;
- `Some(place)` of a place above (a field, an element, a dictionary value) whose payload
  is not boxed, and `Some(p)` of a read-only record parameter (see *Borrowed parents*);
- the record a `from` function returns (`first_of(shelf)` under `-> Item from shelf`), whose
  owners are the call's sources: it goes where the field it returns would go;
- a nested borrowed record, a text or bytes literal, or `None`.

**Positions:**
- a read-only argument of a call;
- a `const` local, and `Some(...)` of one bound to a `const` local (below);
- a `mut` local whose every assignment borrows;
- a value returned under a `from` contract, `Some(...)` of one too. A record holding a
  frame block never leaves its call, even under `from`.

Its loans are its fields' owners, held to its last use.

**What stays refused**, with the repair named on the field that needs `own` or
`copy(...)`, as before records could borrow:
- storing the record in a list, a dictionary or an owned field that owns its elements
  (a local collection of borrows, below, may hold it), or into a `mut` parameter;
- moving it, changing it, or returning it without `from`;
- submitting it to a task;
- changing one of its owners while it is live;
- a slice, or a `const` that borrows a text, bytes or list parameter, which are views;
- a record that mixes a borrow with a fresh value, which is an owner.

#### Borrowed parents

A borrowed record may also hold `None` beside its borrows (a payload-less case owns
nothing, as a literal does) and `Some(p)` of a read-only record parameter: a plain
parameter, not `own` and not `mut`, read bare without `own`. A recursive walk then passes
its context down with no copy: `walk(Scope(block=sb.block, parent=Some(scope)))`. The
parameter is the caller's storage, which cannot change during the call, so the record
holds it in place. When the option's payload is boxed (a recursive field such as
`parent: Scope?`), the box is a slot of this call's frame, made once when the call
starts. A callee reads it like any box, a `copy(...)` of the record copies it into an
owned box, and nothing destroys it.

Such a record follows every rule above, and one more: a value that holds a frame box its
own call made cannot be returned, even under `from`, because the slot ends with the
call. That covers the record itself, a `const` of it, a field read from it and a `from`
call result that borrows it (R4 has the example). A box an ancestor's call made is the caller's storage, so a
function may return it `from` the parameter that holds it: `bridged(self)` below returns
a scope read out of `self.parent`. `Some(...)` of a record built in place, or of a local,
keeps its copy: its value differs at each evaluation, so one slot cannot hold it.

#### Collections of borrows

A local list or dictionary whose every element store is a borrow is a *collection of
borrows*: it owns its buffer (and a dictionary its keys) and lends its elements, so
nothing is copied, and it holds what its elements borrow until its last use. It is:
- a `mut` local made empty (`[]`, `{}`), each `append`, `xs[i] = v` or `d[k] = v`
  storing a borrowed record, a place, `Some(place)`, `Some` of a borrowed record, a bare
  plain text, bytes or list parameter, `None` or a text literal, at least one of them a
  borrow;
- a list literal of such values: a `const`, or an argument built for one call;
- a field of a borrowed record that lends it (`Names(names=xs)`).

A dictionary key written as a place is copied when its entry is new, as before. Its
elements are read in place: an element, a `for` loop, `len`, `in`, and a read-only
argument (a library helper such as `dicts.find` reads it too).

**What stays refused**, with the diagnostic, location and repair each refusal had
before, because the collection then owns its elements:
- changing a source while the collection lives, or a source a loop makes again in
  each iteration while the collection lives past it;
- moving the collection, storing it, or passing it `mut` (a library call that stores
  into it, `lists.insert`, `sets.add`); a `mut` out-parameter; a task;
- returning it, even under `from`: a list returned under `from` is a view of its
  sources, so a new collection of borrows keeps its copies;
- an element that mixes a borrow with a fresh value;
- a set, and an owned record that takes the collection with `own`.

**Which line made it own.** Each of these makes the whole collection an owner, so the
refusal lands on an earlier `append` of a borrow, not on the line that changed the
decision. That refusal keeps its code, position and repair, and carries a note at the
other line, for example "`hits` owns its elements because this line stores a new value
in it, so the earlier line needs `copy(...)` or `own`" on the later `append`. A record of
borrows (B9) gets the same note when a later line moves or stores it, and when a managed
field the constructor leaves out takes a default that is a new value, the note sits on
that field's declaration in the record. In `--diagnostics=json` the note has the role
`cause`. `selka dump-typed FILE.selka` shows what was decided for each local: `owns`,
`borrows from all`, `borrows elements from all` or `borrows fields from names`.

A bare plain text, bytes or list parameter is held as its *frame block*, as a borrowed
record holds one (B9's sources): the caller's own text or list when the argument was a
whole value, else one copy this call makes the first time it stores the parameter and
frees when it returns, however many times it stores it, in a loop too. Bytes carry no
owner, so a bytes argument is always copied this way, and so is a slice. `--stats` counts
these sites. The collection never leaves its call (above), so neither does the frame block.

### R4 — Borrowed returns

`-> T from a, b` declares a read-only result borrowed from the named plain or `mut`
managed parameters. There may be any number of sources. Every value return must refer to
those parameters, optionally through `Some` or a `fails` success; their slices are
covered by V4. `E_BORROW_UNDECLARED` points to the first return using an undeclared source.
An unknown or ineligible source is `E_BORROW_SOURCE`. Each source must appear once;
duplicates report the same code with a fix removing the duplicate. A nongeneric
function whose successful result contains no managed storage cannot declare `from`;
its fix removes the clause. A source lends only storage it holds: text or bytes for a text or
bytes result, a list of the result's element type for a list, and a record or one of its managed
fields for a record result. A plain (not `mut`) text or bytes parameter arrives as a view,
which lends only a text or bytes result of its own kind. A nongeneric clause in which no
source can lend its result is `E_BORROW_SOURCE` with the same fix; a source that cannot lend
beside one that can is dropped. A generic declaration is judged at each instance: an instance
whose sources cannot lend its result is `E_BORROW_SOURCE` at the call that made it, and the
clause's removal is its fix when no source's type names a type parameter (such a source cannot
reach a result a type parameter makes). Concrete scalar generic instances retain the declaration
and ignore borrowing. Formatting orders names by parameter position. Write `from`
before `fails`; function types cannot declare borrowed results.

### R6 — Borrowed selections

`unwrap_or` on an option nobody else holds is the exception (F-71): when the option is the result of a call that lends
nothing (its result is not declared `from` a parameter) and the default is a value of its own (a literal, a new value
such as a call, a joined text or a constructor, or a name given with `own`), `maybe().unwrap_or("")` in a position that
takes a value (a `const` binding, an assignment, a `return`, a `fail`, a store, an `own` argument, a constructor's
field, a list literal's element, `Some`) gives an owned value: the payload moves out on `Some`, the default on `None`,
and the other is dropped. A read in a borrowing position still borrows for its statement, and so does a `mut` binding
(which may later borrow a place beside it). An option that is a local, a parameter, a field or a lent call, and a default
that is a place (`maybe().unwrap_or(self.name)`), keep the borrow: there the refusal names `options.take_or(own o, d)`
when the option is a local the function owns, and `copy(...)` otherwise.

## Rule 2: Exclusion

### R2 — Loans block changes

F-string holes evaluate left to right like call arguments. An earlier managed
hole stays borrowed through later holes. When `print` renders a format directly,
those loans also cover later print arguments, separators and terminators.
Materialized text owns its storage independently of the values it rendered.

A `const` binding holds the place it names, not its whole owner. `const item = self.items[i]` holds `self.items`: a
write to another field of `self` (`self.links`, `self.count`, `self.inner.n`) may happen while `item` is live, and `item`
may be read after it. The same holds for nested records (`self.a.b` against `self.a.c`) and for a local record. The
fields next to the owner decide: a write to the borrowed field, to the whole record, to an element of the borrowed list
(`self.items[j]`) or to anything inside it overlaps, and so does passing the whole record `mut` to a call. A binding
holds the container its value lies in, not the element, so two elements of one list are never told apart. Only a
direct `const` binding of a place is read this way; a binding of a binding, a slice, an iteration binding and a borrowed call
result hold the whole owner, as before. The compiler reads such a binding's place again from the record after a write, so the
borrow never outlives the update of the record it was read from.

### R7 — Iteration

The loan is on the place that is iterated, not on its owner: `for root in tree.roots` borrows
`tree.roots`. A sibling path may change in the body, through `append(mut ...)` or a `mut`
argument (`tree.nodes[root].children`, another field of `tree`); the iterated field, a prefix
of it (`tree`) and anything inside it (an element, a field of an element) stay borrowed.
A place the checker cannot name (a call result, a dictionary value) borrows its whole owner.

### M5 — Disjoint arguments

An exclusive mutable argument must be disjoint from the other arguments whose borrows
remain live in that call. Different record fields are disjoint. Different literal list
indices are disjoint, whether the other argument is mutable or read-only, and after any
equal field prefix (`tree.nodes[0]` and `tree.nodes[1]`). A record field inside an element
(`rows[0].tags`), dynamic indices, equal indices and overlapping prefixes do not establish
disjointness. Scalar argument reads finish before the call mutates storage; argument
expressions still evaluate left to right.

Two payload bindings of one `match mut` arm name different fields of the payload inside the
matched place (X2), so passing both `mut` is disjoint (`put(mut keys, mut vals)` in
`case pairs(keys, vals)`, or `mut p.keys, mut p.vals` of a record payload `p`) when the
matched place is a local, a parameter, a path of record fields of one, or an enclosing
arm's binding (`match mut x:` in `case both(x, y):`, where `fill(mut u, mut v)` in
`case two(u, v):` and `fill(mut u, mut y)` both separate); inside a list element it is not
(`match mut ts[0]`). A binding passed beside the matched place (`mut u, mut x`), beside a
field path under itself, or read beside a `mut` sibling binding still overlaps.

A read argument that makes a value of its own finishes before the call the same way, so it may
read a record another argument passes `mut` (`emit(mut work, "x" + target(work))`,
`link(mut self, self.design + suffix)`): an operator's result, a format string, `copy(...)` or
a call whose result is not declared `from` that record. This holds when the `mut` argument is a
local or a path of fields of one (`mut work`, `mut work.inner`), with no list element in the
path, and no other argument takes the record `mut` or `own`. An argument that lends a part of the
record to the call (`work.targets[0]`, a call declared `from work`) stays refused, and the
message names it and the copy that frees it. The same holds for such a value given to an `own`
parameter (`keep(mut work, copy(work.targets[0]))`, `keep(mut work, "a" + target(work))`): the
read ends when the value is made, and the callee owns a value that shares nothing with the record.
A `match mut` payload binding passed `mut` is such a path too (`emit(mut held, copy(held.targets[0]) + "?")`,
`put(mut keys, mut vals, keys[0] + "!", vals[0])`): Core makes every argument's value before it takes the
payload out of its case for the `mut` one.
A move of a part of the record (`own work.lines`, `own work`) and an argument that lends a part of
it to the `own` parameter (`work.targets[0]`, a call declared `from work`) stay refused with the
message of an argument that reads the record; a resource keeps the earlier rule.

The diagnostic names both overlapping arguments and points to the earlier one. For two
list elements it says that they are separate storage only when both indices are distinct
literals, and names the remedies: bind a copy of the read element first, or pass the list
`mut` and index both elements inside the callee. When one argument passes a record `mut` and
another lends a part of it (`rebuild(mut state, state.stack)`), the message names both arguments,
says that the callee may change what the other reads, and gives the remedies: pass a value of its
own (`copy(state.stack)`), or pass the record `mut` and read it inside the callee.
If separate writable storage is intended, write `mut part = copy(a[0])`, pass
`mut part`, then write `a[0] = own part` after the call. Scalar write-back uses
plain `part`. Move-only values cannot use this copy rewrite. Choosing separate
storage requires a deliberate decision, so this message has no automatic fix.

### V3 — View sources stay put

The refusal names the line and column of the write, call or move that changed the source, and
what it wrote (a write to any field of a record changes the whole record, so a view of `r.buf`
does not survive `r.pos = n`). Its repairs come in the order that copies nothing first: read the
view before that line; after a write, keep the span (start and length) and slice again where it is
read; and the copy of the slice's binding last. A repair that does not apply is left out: no
reorder where the change does not lie between the binding and the read, no re-slicing after a move.

### X1 — Matching a name borrows

Matching an ordinary, non-affine named value or projected place borrows its payload.
The source stays held until the active arm’s final use of a payload binding; a
conflicting move or mutation is refused. Matching a fresh owned call, constructor or
explicit copy consumes that temporary and transfers its immediate payload, and so does
`match own name` for an owned local or an `own` parameter: the owner is moved, so a
payload binding owns its value and `own payload.field` takes a field under B8 (several
in one statement). A
borrowed or `mut` parameter, a borrowed local and a field or element place cannot be
consumed this way. A declared `from` call still borrows under R3. Nested non-affine
patterns continue to borrow their intermediate value. A resource-bearing move-only
scrutinee is consumed instead: matching a named owner requires `match own value` under B2.

## Rule 3: Gone

### B3 — Use after move

A moved binding is unavailable: it cannot be read, written through or moved again.
Reinitialize a writable whole binding under B4, or request an independent `copy` before
transferring its source. A read that comes after the move in the same call or constructor, in an
argument written after the one that gives the value, and only gives a number or a `bool`
(`len(x)` of a text, bytes, list, dictionary or set, a comparison or arithmetic over it), or is a literal, needs no copy: the arguments are evaluated from
left to right as they are written, so the call written with the read first
(`Source(total=len(plain), mem=own plain)`) reads the value and then moves it. The refusal names
that form before the copy, and `selka fix` writes it where the function checks with the call so
written (a later statement that reads the value, a read that keeps part of it, a positional
argument and a comment between the arguments keep the copy). Pending Results have their separate consumption obligations
under L1.

## Current limits

These refusals come from what the checker or the representation of values can do today, not
from the model. Removing one removes a refusal and changes no verb and none of the three
rules. R5, B8 and Z3 are rules below. The other limits belong to rules filed elsewhere, so
they are described here with what would remove them.

| Limit | Where it shows | What would remove it |
| --- | --- | --- |
| R5: a `from` function returns only borrows (and static empties) | R5, `E_BORROW_MIXED` | A returned value that is a borrow on one path and a fresh owner on another needs one run-time shape for both. Nothing is decided. Until then copy the borrowed returns and remove `from`. |
| B8: no partial record moves across statements | B8, `E_SINGLE_OWNER_BORROW`, `E_SINGLE_OWNER_MOVED` | The checker and the drop plans tracking which fields of a record are gone after a statement ends. Within one statement several fields already move out together (lane FR91); moves spread over statements are not planned. Until then move the fields in one statement (`total(own p.lo, own p.hi)`; `selka fix` joins two `const` moves the next call takes), or `copy(record.field)`. |
| A text, bytes or list view stored in a local record, list, dictionary or option (`Some(view)`): a slice (`p[0:2]`) or the result of a `from` call (`first_text(r)`). These are 24 of the ownership matrix's 312 function-local cells, 6 of them the option form, and the only ones where a bare name is refused | V2, `E_SLICE_ESCAPES` | A representation in which a view can sit where a field or an element expects a block. Frame blocks, which hold a whole parameter (B9, collections of borrows), would take these only by a copy the compiler inserts, which was decided against. One value shape that is either a view or an owner, for local aggregates only, would take them all without a copy (estimated 23 to 49 lane-hours); such an aggregate could not be passed whole to a function. For a local record alone, a view kept as a field of the record's value would do (3 to 6 hours). None is chosen. Until then write `copy(...)`; a record result of a `from` call goes where its field would (B9's sources), and the field read directly or a slice in a `mut` local (B9) is accepted. |
| X2: a mutable match on a dictionary element | X2, `E_MATCH_MUT` | `take` and `exchange` reaching dictionary elements. Until then match the element read-only and assign the complete updated value back. |
| Z3: a shape `check` accepts and `build` cannot place | Z3, `E_CORE_UNSUPPORTED` | `check` running the placement of ownership operations that `build` runs; what that costs is being measured. A shape that is valid is a gap in the scheduler and is fixed there. |

The test-loop plan (`docs/audits/test-loop-plan-2026-11-09.md`), Part B, prices and orders the work that would remove these limits.

### B8 — No partial record moves

`own record.field` transfers a managed field by consuming its whole owning record. The
record becomes unavailable and its other fields are destroyed at that point. A record
that remains usable supplies a field by a read borrow or an explicit copy; assigning its
fields new values remains possible. A field of a borrowed record cannot be taken this
way.

One statement may move several fields of one owned record, each field once:
`total(own p.lo, own p.hi)` or `Graph(ids=own t.ids, nodes=own t.nodes)`. The record is an
`own` parameter, a `const` or `mut` local, or a binding that owns what it names (a `match own`
payload, the payload of `own x else:`, the element of `for x in own xs:`). It is consumed
once, at the first move the statement makes, and the fields no move names are destroyed
there, as with one move. The moves count together only where the statement runs every one
of them in order: call arguments, constructor fields, `try`, arithmetic, `print` and f-string
holes. A move in the right operand of `and` or `or`, in a branch, in another statement or
inside another operation (`append(mut xs, f(own p.a, own p.b))`) is a move of its own, and
the record is gone by then; so is a read of the record after the first move, which is read
into a local before the statement instead. A field of a `match mut` or read-only `match`
binding or of a plain or `mut` parameter is lent, never moved. Each refusal names the way out
in the program's own words, and `selka fix` joins `const a = own p.x` and `const b = own p.y`
into the call or constructor of the next statement when that is their only use.

### Z3 — Build-time ownership limits

Some lowering and ownership scheduling shapes remain build-time limits. A build reports `E_CORE_UNSUPPORTED` with rule Z3 when it cannot place a required ownership operation, even if source checking succeeded. A shape that is valid is a gap in the scheduler, not a rule: it is fixed there, and one that is invalid is reported by `check` with its own code (the cases the stage-2 EDA port found are in `src/core/check_build_agree_test.zig`, and the G3 redo's in `test/check_build_agree_redo_cli_test.zig`). The gate builds every function of every language-suite file
the check accepts (`src/core/check_build_corpus_test.zig`), so a new disagreement there fails it. Other ABI, type or backend limits can use the same code without an ownership rule.

One limit is reported by `check` itself, with this code and rule: a function that `fails` with a managed error type (such as `str`) cannot return a borrow of its `mut` parameter (`func next(mut self: Cursor) -> Entry? from self fails str`). The ownership certificate cannot yet state a borrow of the parameter's final value inside a `Result` that owns its error. Without `fails`, or with an `int` error, the borrow builds. The repair is a copy without `from`, a scalar error, or a split of the update (`advance(mut self)`) from the read (`current(self) -> Entry? from self`).

For example, bind an explicit owned bytes copy before lending a slice of bytes to a task. A plain `bytes` parameter given to a task whole is lent as it is (FR58); a slice of bytes or text written at the submit itself is not yet (a slice of a list there is copied into a new list). The first program has that owner; the second requests the still-unsupported loan of the slice. Its refusal is checked at build time without running an artifact.

## Applications

### P3 — Returned resources

A function returning a resource has exactly one input in its signature that the result can come from, its origin. The returned resource must depend on that input, including when it is wrapped in a Result or carrier record. A local provider cannot supply an escaping resource, and two possible input origins are ambiguous.

The count is every parameter that is a resource (an open `File` or `TextFile`, a `resource` type, a record that holds one) or a provider of the result's kind: a `Filesystem` for a file or a `filesystem` resource, a `Network` for a `network` resource (a `Poller`, a `Connection`, a `Listener`). A `Clock`, an `Entropy`, an `Environment` and a `Process` acquire no resource, and a provider of the other kind cannot supply this one, so neither is counted; a `Stream`, an `Input` and a `Stop` are handles and are not counted. When exactly one parameter is an `own` resource of the result's type (or of its Result's payload), it is the origin and no provider beside it is counted; another resource still is. A function whose count is not one is refused with `E_RESOURCE_ORIGIN` at its name, and the message lists the inputs it counted, in source order, with their types: `` `two` returns a resource, so it takes exactly one input the result can come from (a `Network` or a resource), and it takes 2: `net: Network`, `other: Network` ``. Keep the one the result comes from; the work that needs the others beside it goes in a function that returns a `bool` or an `int`, which may take any number of inputs, a file as `mut` and any other resource as `own` (the operations on a `Poller` take it `own`). (A function that takes only inputs that are not counted keeps the origin it had before this narrowing, its one provider or resource input, so nothing accepted before is refused.)

So `func step(own live: network.Poller, root: Filesystem) -> network.Poller`, `func on_event(own live: network.Poller, clock: Clock) -> network.Poller`, `func dial_slot(own live: network.Poller, net: Network) -> network.Poller` and `func open_server(net: Network, fs: Filesystem) -> network.Polling` are accepted; their origins are `live`, `live`, `live` and `net`. A body that drops `live` and returns a poller made from `net` is refused at its `return` with `E_RESOURCE_ESCAPE`, because the caller ties the result to `live`.
