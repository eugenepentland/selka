# Ownership certificates (design, package C0 of the 2026-10-26 plan)

This is the fixed reference for packages C1–C5 of
`docs/audits/ownership-certificates-plan-2026-10-26.md`. It defines:
- the ownership class of every Core IR operation;
- the states a certificate assigns to values;
- the checks J1–J8 the validator makes;
- the theorem the Lean model proves;
- the trusted assumptions;
- which of the 54 ownership rules the proof covers.

C1 may refine an operation's class where `own.zig`, the emitter or the runtime does
something this document did not anticipate. Every such change is recorded in §9, and
the Lean model follows it. The theorem in §6 is not weakened without Claude's approval
(plan §11).

## 1. Where the certificate applies

The certificate describes the **final IR**: the module after `own.zig` and every
later pass, as `emit_llvm` receives it. A pass that runs after `own.zig` and changes
an ownership-relevant instruction must keep the certificate current, or the
certificate is rebuilt from the final IR by `own.zig`'s analysis run read-only. C1
finds out which applies.

Each concrete function instance has its own certificate, generic instances included.

## 2. Values and states

`copy` instructions are resolved first (`Function.resolve`): a `copy` names the same
value as its operand and has no state of its own.

Each value has one state:
- **scalar**: integers, floats, booleans, function references, inline arrays of
  scalars, and every value of a type `Module.managed` says is unmanaged.
- **immortal**: `str_const` and `text_sentinel`; also `undef` of a managed type, the
  null owner (A3). Never freed; reading or consuming one has no effect on the heap.
- **owned**: a managed value whose storage this function must destroy or transfer
  exactly once.
- **stack**: an owned list that `promote.zig` placed on the stack, with its filling
  pushes and loop phi. It must never escape (J7). It has no destruction obligation:
  `own.zig` gives it class `none` and schedules no `drop` for it, so it is never entered
  into `L` (§9, entry 10).
- **borrowed(P)**: a managed value that lives inside, or is lent by, the values in
  `P`. Each element of `P` is a value of this function, or `caller(i)` for borrowed
  parameter `i`.
- **emptied**: an aggregate, a record or a call's record result, whose managed parts
  were all taken by owned reads (§3, slots). It owns nothing itself, is never
  consumed, and is not in `L`.

**Roots** are where a borrowed value's lifetime ends: `roots(v) = {v}` for an owned
or stack `v`, the union of `roots(p)` over `p ∈ P` for `borrowed(P)`, and
`{caller(i)}` for `caller(i)`.

Throughout a check, the **live set** `L` is the owned values that are defined and not
yet consumed. A `caller(i)` root is always live: the caller keeps
it alive for the whole call. A value `v` is **usable** at a point when:
- it is scalar or immortal;
- it is owned and in `L`, or stack;
- it is borrowed, it is defined on every path to the point (the set `D` of §5), and every
  owned root of it is in `L`.

`own.zig` already computes these states (`Class` = `none`, `owned`, `borrowed`,
`immortal`; parents in `children` and `extra_parents`). The certificate writes them
down instead of discarding them.

## 3. Operation classes

Each operation's class says what it does to its operands and what its result is:
- **read** operands must be usable;
- **consume** operands must be in `L` (or be scalar or immortal, where consuming is a
  no-op), and leave it;
- results are scalar, immortal, owned (*fresh*), or borrowed from given operands.

`ownership_ops.zig` encodes this table as an exhaustive `switch` over `ir.Op`. Its test
compares the consumed positions with `own.zig`'s `consuming` for every operation. Rows
marked **verified** were checked against `own.zig`, the emitter and `core_rt.c` in C1.

A result whose type is unmanaged and holds no borrow is `scalar`, whatever the row says.
The export lists every value operand, scalars included, split into `reads` and
`consumes` by the row.

| Class | Operations | Operands | Result |
| --- | --- | --- | --- |
| Parameter | `param` | n/a | owned if `passing.takes(i)`, else scalar or `borrowed({caller(i)})` |
| Constant | `iconst`, `fconst`, `func_ref` | none | scalar |
| | `str_const`, `text_sentinel` | none | immortal |
| | `undef` | none | scalar; for a managed type the null owner: immortal (A3, **verified**: `own_conditional_drop.zig`, `core_owned_child_inline`) |
| Forward | `copy` | n/a | the operand's state; resolved away, never on an `inst` line |
| Pure | `add` `sub` `mul` `div` `rem` `floor_div` `floor_rem` `neg` `bit_and` `bit_or` `bit_xor` `not` `cmp` `fadd` `fsub` `fmul` `fdiv` `fneg` `fcmp` `int_to_float` `float_to_int` `convert` `shift_left` `shift_right` `saturating_add` `float_unary` `float_convert` `bitcast` `float_fma` `vector_select` | read | scalar |
| Inspect | `list_len` `str_len` `dict_len` `dict_find` `dict_entries` `dict_entry_live` `str_width` `str_code` `union_tag` `str_parse_int` `byte_load` | read | scalar |
| Fresh | `list_new` `dict_new` `buffer_new` | read (scalars) | owned; stack for a list promoted to the frame, its filling pushes and loop phi. A stack list holds no managed elements: `promote.zig` skips every list whose element type is managed (`if (module.managed(element)) continue`), and the exporter refuses a function that says otherwise |
| Copy | `list_copy` `dict_copy` `buffer_copy` `str_slice` `str_from_view` `array_from_bytes` | read | owned (`array_from_bytes`: scalar) |
| Project | `list_get` `list_get_field` `record_get` `union_payload` `box_get` `dict_entry_key` `dict_entry_value` `array_get` | read | scalar for an unmanaged result. For a managed result: `borrowed({a})`; `borrowed(the call's from values)` when `a` is reached from a `call` result by `record_get`/`union_payload` steps that match the callee's `from` path (R3); or `owned`, a **take** of the slot (slots, below). A borrowed read of a slot that the same block takes later is a *forward take*: its parent is that take (the value the take defines), not `a` |
| View | `list_view_of` `list_slice_view` `str_view_of` `str_slice_view` `str_slice_bytes_view` | read | borrowed({a}) |
| Character | `str_char` | read | owned (**verified**, `myl_core_ir_str_char`): a fresh string, or one of the runtime's static one-byte blocks, whose destruction is a no-op (A4) |
| TextFrame | `text_frame` | read | borrowed({b}) (**verified**): `b` is the text view the frame holds (`borrow_result.zig` takes `inst.b`, and a function that returns the frame states `from` the view); `a`, the cache owner, only supplies the frame. The result is `a` or a header in this frame whose kind is not static, so it can never be consumed. `own.zig` classes it immortal and schedules no drop; the table is stricter |
| Borrow | `borrow` | read | borrowed({a}) |
| Update | `list_push` `list_set` `list_set_field` `list_pop` `record_set` `array_set` `dict_set_value` `dict_insert` `dict_remove` `dict_clear` `str_append` `str_append_char` `list_sort` `buffer_set` `buffer_push` `buffer_pop` `buffer_append` | consume operand 0 (`consumesOperand0`); consume the stored value: `b` for `list_push` and `record_set`, `extra[0]` for the `set` forms, `dict_insert`'s key and value; read the rest | owned, or stack for an update of a stack list, or scalar for an update of a scalar aggregate. Implicit releases and slot stores: see below |
| Construct | `record_make` `union_make` `box_make` | consume each managed operand; read each view operand | owned. Borrowed when every managed operand is borrowed (their roots) and nothing is consumed (R4: `borrowedOperand`, `borrowedItem`); a union of no payload over a type that holds a view is borrowed with no parents. An owned aggregate that holds a view has the view as a parent (a loan). `box_make` with `flags.lent_box` is a *lend* (§10): it reads the lender and the group it is lent to, consumes nothing, and the group holds the loan until it ends |
| Take | `union_take` `box_take` `record_take` | consume `a` | owned (scalar for a scalar payload); `record_take` destroys the other fields |
| Drop | `drop` | consume `a` | none |
| Call | `call`, `call_indirect` | for each argument, consume if `passing.takes(i)`, else read; views read | owned, scalar, none for no result, or borrowed(arguments named by the callee's `BorrowContract`), exported as `from`. A result may also be `emptied` (a record whose managed parts were all taken). The runtime's group calls (`myl_core_group_open`, `myl_core_owned_task_submit_indexed`, `myl_core_owned_group_take`, `myl_core_owned_group_end`) are ordinary calls with the contracts of §10. A reserved marker call (`myl_core_borrow_select_v1_*`, `myl_core_borrow_choice_v1_*`, `myl_core_borrowed_provider_v1_*`, `myl_core_borrowed_optional_provider_v1_*`) borrows from the operands `own.zig` names and writes them as its parents |
| Output | `print` | read | none |
| Trace | `err_trace` | none | none |
| Join | `phi` | per edge, below | the phi's stated state |
| Jump | `jump` | none | n/a |
| Branch | `branch` | read (scalar) | n/a |
| Return | `ret` | consume if the result is owned, read if borrowed | n/a |
| Trap | `unreachable` | none | n/a; ends the path |

**Phis.** Four kinds, by state:
- *owned*: on each incoming edge it consumes that edge's operand, which must be owned
  or immortal. This includes the cleanup phi `own.zig` builds when a `drop`'s owner
  does not dominate it: the owner on the paths that built it and `undef` (the null
  owner) on the others. The edge with `undef` is a live edge.
- *stack*: takes stack operands, so a stack list flows through a loop.
- *borrowed*: reads its operands, which are borrowed, immortal, or the owned value it
  selects between (R6); its parents contain every operand's roots (V5).
- *dead* (state `none`): no instruction reads it, `own.zig` ignores it, it consumes
  nothing and the checker skips it.

A phi never consumes a container with a pending transfer (J8). A scalar phi takes scalars.

**Slots (the take protocol).** A container's managed contents are its slots: a record's
managed fields (`f<k>`), the elements of a list or inline array (`e<index>`, with a field
path for the `_field` forms), a dictionary entry's key and value (`k<index>`, `v<index>`).
`<index>` is the value or constant that picks the element. A Project instruction whose
state is `owned` *takes* its slot: the container keeps the pointer but no longer owns what
it points to. A take is closed by:
- a store into the same slot: `record_set`, `array_set`, `list_set`, `list_set_field` or
  `dict_set_value`, which consumes the container and returns the updated one. The
  list and dictionary stores release the old content unless `transfers.slots` pairs them
  with a transferred read (the emitter calls the same function): exported `released old`
  or `released -`. `record_set` and `array_set` never release: when the program took
  nothing itself, `own.zig` adds an owned read of the old field before the set and a
  `drop` after it. `moveCopiedChild` stores `undef` into a taken list slot, so the
  container can then be dropped whole;
- `list_pop`, which removes the last element without releasing it. Its `slot` is the key
  of the owned `list_get` `markPops` found earlier in the block, or `tail` for the read
  and `drop` `markPops` adds after the pop;
- `dict_remove`, which releases the key and the value except the parts a take moved out
  (the `dict_take_key` and `dict_take_value` bits of its `data`);
- dissolution: a record whose managed fields were all taken, each by one owned
  `record_get`, is `emptied`, is never consumed, and lists those fields in `slots`.

Consuming a container as a whole (`drop`, a call, a constructor, a phi, `ret`, an update
that is not the closing store) while a take is open on it is a fault: the slot still holds
the pointer, so it would be released twice.

`flags.transferredRead` marks four of the takes: `list_get`, `list_get_field`,
`dict_entry_key` and `dict_entry_value`. The others carry no marker in the IR:
`record_get` and `array_get` (`takeFields`, `extractDroppedFields`, `empty`), and the
`list_get` of `markPops`. The state the pass kept is the only record of them.

**Implicit releases.** An instruction releases what it replaces or removes: `list_set`,
`list_set_field` and `dict_set_value` the old content (unless taken), `dict_remove` the
key and value (unless taken), `dict_clear` every entry, `record_take` the sibling fields,
`drop` the whole tree. `list_push`, `list_pop`, `record_set`, `array_set`, `dict_insert`
and the string and buffer updates release nothing.

## 4. The certificate

Per function instance:
- `state[v]` for every value;
- `parents[v]` for every borrowed value: values of this function or `caller(i)`; an owned
  aggregate that holds a view lists the view as a loan;
- `unchecked: ?Reason`. A function whose certificate is unchecked is skipped and
  counted, never counted as validated. Since C6 no reason is produced: a function with a
  task group is checked (§10). The reader still accepts the reason `task-group` in a file
  written before C6, and counts the function as unchecked.

The parameter and result states follow from `Signature.passing` and
`Signature.borrow`; the function line repeats them so the file is self-contained, and the
validator checks them against the signature.

The export (`ownership-certificate-v2`; v1 had no `views` extra) adds the operation-class table, and for each
function its blocks, predecessors and instructions reduced to (class, operands,
consumed positions, result), the slot of a container instruction and, for a call, the
values its result borrows from. The Lean checker sees exactly what the Zig validator
sees.

### 4.1 Format `ownership-certificate-v2`

The format is UTF-8 text, one item per line, fields separated by single spaces.
- `%N` names value `N`, `^I` names `caller(I)`, and `bN` names a block.
- `-` stands for an empty list; a list is comma-separated, with no spaces.
- Lines are in this order, and the bytes are deterministic.

```text
ownership-certificate-v2
class <op> <Class>                                   one per ir.Op, in enum order
function <name> result <scalar|owned|borrowed> from <I,…|-> unchecked <-|reason>
param <I> %N <state>                                 one per parameter
callee N <name|-> <kind> <modes|-> <result> <from|->   one per distinct callee of the function's calls
block bN preds <bM,…|->                              blocks in index order
abandon bP <%V,…>                                    zero or more, one per predecessor bP, after a trap-region block's line
phi %N <state> parents <%P,…|^I,…|-> edges <bM:%V,…>
inst %N <op> <Class> reads <%V,…|-> consumes <%V,…|-> state <state> parents <%P,…|^I,…|-> [slot KEY] [released PARTS] [taken PARTS] [slots KEYS] [from <%V,…|->] [callee N] [lent %G] [noloans] [views <%V,…>] [imm N]
inst - <op> <Class> reads <…> consumes <…> state none parents -
term jump bN | term branch %V bT bF | term ret <%V|-> | term unreachable
end
```

- **Classes.** The spellings are exactly: `Parameter Constant Pure Inspect Fresh Copy
  Project View Character TextFrame Borrow Update Construct Take Drop Call Output Trace`
  on `inst` lines. The `class` lines add `Join Jump Branch Return Trap` and `Forward`
  (the class of `copy`, which has no `inst` line). `TextFrame` is one token.
- **Names.** A function name is one token: a byte at or below `0x20`, `0x7f` or `\` is
  written `\xHH`.
- **Values are defined once.** Each `%N` is the destination of at most one `inst` or `phi` line of a function (a
  parameter's value is the destination of its `param` instruction in `b-`). A text that defines a value twice is
  malformed: the reader refuses the file (an error line, not a verdict), as both checkers do.
- **Instructions** appear in block order. `inst` lines list a block's instructions in
  order, and the `term` line closes the block.
- **Constants and parameters** are listed once, as `inst` lines in a pseudo-block `b-`
  before `b0`. They are defined outside every block (`Op.isConstant`). The `param` line
  names the value of each parameter.
- **Reads and consumes** are the value operands, scalars included, after `copy`
  resolution, split by §3, in operand order. A value read and consumed by the same
  instruction appears in both lists, and J6 rejects it. A phi's operands are on its
  `edges`; a `ret` reads or consumes its value by §3.
- **States** are `scalar`, `immortal`, `owned`, `stack`, `borrowed`, `emptied` and `none`.
  An instruction with no value (`inst -`) has state `none`; so does a dead phi.
- **Unit values.** A value of the unit type that some instruction names as an operand (the
  unit stored in a `dict[K, Unit]`, which is an `undef`) gets a name and the state `none`:
  `inst %N undef Constant reads - consumes - state none parents -`. It owns nothing:
  consuming it is a no-op, and reading it is J3. A unit value nothing names stays
  `inst -`. Only a `Constant` or a `Call` line may name a `none` value.
- **Extras**, in this order, when they apply:
  - `slot KEY`: the slot a container instruction reads, takes or stores (§3, slots). `KEY`
    is `f<k>` (a record field), `e<I>` or `e<I>p<s>.<s>…` (a list or array element, with
    the field path), `k<I>` or `v<I>` (a dictionary entry's key or value), or `tail` (the
    slot a pop leaves). `<I>` is `%N` or `#C`, the index value or constant;
  - `released PARTS`: what a store destroys of the old content: `old` or `-` for
    `list_set`, `list_set_field` and `dict_set_value`; `key,value`, `key`, `value` or `-`
    for `dict_remove`;
  - `taken PARTS`: for `dict_remove`, the parts the removal finds already moved out by a
    take (`key`, `value`, `key,value` or `-`); the parts it destroys are in `released`.
    `dict_remove` carries `slot v<I>` (the entry it removes, whose take is `v<I>` or `k<I>`);
  - `slots KEYS`: the managed fields of an `emptied` record, each taken exactly once;
  - `from VALUES`: for a `call`, the values the callee's `from` contract names, plus any
    other parent of the result;
  - `callee N`: for a `call` or `call_indirect`, the entry of the function's callee table that names the callee (§9, entry 57);
  - `lent %G`: for a `box_make` with `flags.lent_box`, the group the box is lent to (§10). `%G` is
    the second value it reads; the first is the lender;
  - `noloans`, a flag that stands alone: for a `Take` whose result type cannot hold a view, the part it takes out
    carries none of the loans of the aggregate it leaves (§5, J4; §9, entry 51). A reader accepts it anywhere among the
    extras; a take without it carries the loans;
  - `views %V,…` (format v2, entry 62): for a constructor whose result is owned or `emptied` and that is not a lend, the
    borrowed operands it reads into a slot whose type its destruction does not destroy (a span, a list view, a borrowed
    overlay, a record of those: the slot type is not `managed`). Written only when there is one. Only a listed view may
    be a loan an owned aggregate holds (J6 `construct-read`); J1 `views` refuses a view on another instruction or a view
    that is not an operand the constructor reads. A reader refuses a file of format v1, which had no such extra, by name;
  - `imm N`, last: for `iconst`, `cmp` and `fcmp`, the instruction's `data` in decimal (a
    `u64`: the constant, or the comparison predicate). The validator needs it to recognise
    two branches on the same test (§5, guards). No other instruction carries it.

C1.3 implements exactly this grammar. C3.5 reads it. A change to the grammar
is a §9 entry.

The exporter is a direct serialization of the IR, the §3 table and the states the pass
kept, so it is trusted along with the table (A1).

## 5. The checks

The validator makes one forward pass over the reachable blocks in reverse post-order,
then rechecks every live edge, back edges included. The state it carries is `(L, D, P)`,
and `R` and `G`:
- `L`, the live set;
- `D`, the borrowed values defined on every path to the point (a borrowed name left over
  from an earlier loop iteration is not usable);
- `P`, the open takes: `(container, slot)` pairs of an owned container whose slot an owned
  read took and no store has refilled, and the slots an `emptied` aggregate still owes
  (J8). An entry may carry a guard (J8);
- `R`, the roots of each borrowed value of `D` on this path: the owned values it lives in
  and `caller(i)`;
- `G`, the branch decisions known to hold on the path (J8, guards).

**Roots follow ownership.** An owned value is its own root. A borrowed value defined here
gets the roots of its parents at that point (an owned parent is its own root, a borrowed
parent contributes the roots recorded for it, `caller(i)` stays). A borrowed phi gets the
roots its operand has on the incoming edge. When an owned phi or a constructor consumes an
owner, the roots that named the owner name the new holder: the storage does not move, so a
borrow of the owner stays valid while the phi's or the aggregate's value is live. A borrowed
value that reads slot `k` of an owned container `c` in place also has `(c, k)` as a slot root
(J4).

At a join, `L` must be equal on every incoming edge (after that edge's phi
consumptions), the target's `D` must be contained in each edge's `D`, the roots each edge
records for a name of the target's `D` must be among the target's, the target's `G` in
each edge's `G`, and the open takes must agree up to guards (J8). The entry state of a
block is the join of its edges: `D` intersected, `R` united, `G` common to all, `L` that of
the first edge (the others must agree). The forward pass is repeated until no entry state
changes (a loop needs a few rounds), and the recheck then runs every block again from its
entry state and compares every live edge with its target's entry state, back edges
included. A name enters `D` only when none of its roots is redefined at that point:
defining an owned or stack value removes the names that live in it from `D`; a loan that
was written ahead of the definition (a forward take) comes alive instead. The decisions
known on entering a loop are dropped at its head: they need not hold on the back edges.

The *trap region* is the set of blocks every path from which ends in `unreachable`: a block ends in `unreachable`, or has
successors and all of them are in the region (a cycle that never reaches a trap is not in it). The pass schedules no drop in it,
since the process ends at the trap (RC-TRAP-TEARDOWN-1), so the owners that are live on an edge into the region and that nothing
from the block on needs would differ from edge to edge. The certificate says what the path abandons: a block of the region lists,
in `abandon bP %V,…` lines, the owners the edge from its predecessor `bP` leaves undestroyed. The edge state loses them (they leave
`L`, and the open takes whose container is listed leave `P`; `D` and `R` stay, and a view of a listed owner, or an owner that
holds a loan on one, is unusable because an owned root of it is no longer live, as after a drop). From there the block is checked
like any other: equal `L` on every edge, open takes that agree up to guards. Nothing else about the region is special (§9, entry
55; it replaces the meet, the chain rules and `trap-holder` of entries 46, 49, 53 and 54).

A borrowed value whose root is consumed (and not handed to a phi or an aggregate) can never be used again, so it leaves `D` and
`R` at the consumption: the state holds only what can still be used. This changes no verdict, since a use of such a name is J4
whether the name is in `D` with a dead root or not in `D`, and it keeps the validator's memory proportional to the live
borrows rather than to every borrow the function ever made.

A join failure is reported as J2 (the live sets differ), J8 (the open takes differ) or
J4 (the target needs a borrowed name the edge does not define), at the predecessor's
terminator. The checks:

- **J1 States follow operations.** Each `state[v]` is the result §3 gives for
  `v`'s operation, operand states and signature. Each parent of a borrowed value is
  an operand §3 names, or a `caller(i)` for a borrowed parameter. A borrowed result names
  as parents only operands the instruction reads, and they must be usable. Two exceptions:
  a projection of a call result is rooted in what the callee's `from` names, or in
  another projection of the same call; and a *forward take* has the later take of its
  container as its parent, which is not defined yet (every later use of the view then
  needs that take alive). An owned value lists as parents only operands the instruction
  reads (an owner it consumes is inherited with its loans, never a parent); any other value
  (scalar, immortal, stack, `emptied`, none) and any non-borrowed phi has none; only a
  parameter borrows from its caller. Both validators apply this to every class of instruction
  (entry 59). Every phi satisfies the phi rule of §3. A phi edge whose operand is an `undef` of a managed type
  contributes the null owner: consuming it is a no-op, and the edge is live (A3).
- **J2 Exactly once.**
  - Each consumed owned operand is in `L` and leaves it; a consumed scalar, immortal or
    `none` (unit) operand is a no-op (the export lists consumed positions, so `list_push(l, 5)` has
    `5` in `consumes`); each owned result enters `L`. A stack value is never in `L`.
  - At `ret`, when the result is owned, `L` is exactly the returned value, which the
    `ret` consumes, or `L` is empty when the returned value is immortal; otherwise `L` is
    empty. At `ret`, `P` is empty.
  - `unreachable` ends a path with any `L`.
  - Together these mean every owned value is consumed exactly once on every path that
    returns (B3–B6, C3, Z1).
- **J3 Used only while live.** Every read operand is usable where it is read.
- **J4 Loans end with their roots.** A borrowed value is usable only while it is in `D` and
  every root it lives in is alive: an owned root in `L`, a slot root while its container is in
  `L`. This is J3 for borrowed values, separated out because it carries R2, R3, V3 and X1.
  - A borrowed read of slot `k` of an owned container `c` in place (a Project with `slot k`
    whose parent is `c`) lives in the slot root `(c, k)`, and so does every borrow of that
    borrow. Consuming `c` ends the loan, and so does taking `k`: the view leaves `D`.
  - A view written ahead of the take of its slot in the same block, and read only after the
    take, is a view of the value the take defines: the table gives it the take as its parent
    (*forward take*, §3). Its loan on the take is dead until the take is defined and alive
    after, as for any owned root.
  - An owned value that lists parents (a call result that holds a view) *holds the loans* of
    its parents. While it is live no root of such a loan may end: consuming the owner, or
    taking the slot, is J4 (`loan-outlives-root`). A constructor that consumes an owner takes
    over the loans on it, which then name the aggregate (a slot root becomes the aggregate's
    wildcard slot `*`, ended by a take of any of its slots), and inherits the loans its
    operands held; the loans listed on its own result are the views of those owners and are
    dropped. A phi that consumes a holder carries its loans. Only a constructor with an owned
    result moves the loans with the storage: a constructor with an `emptied` result destroys
    what it consumes, so consuming a root of a live holder's loan that way is J4 too (§9, entry
    41).
  - A *lend* (§10) is a loan held by a group: the lender's roots join the loans of the group
    value, which holds them until the group is consumed (its join). Consuming or taking a root
    of such a loan while the group is live is J4 (`loan-outlives-root`), which is rule K1: a lent
    value is neither consumed nor changed before the join.
  - **Loans are carried through consumers.** An instruction with an owned result hands on to it the loans of the owned values it
    consumes: an update, a call and a take (a constructor renames the roots of the owners it takes to the aggregate). The result of
    a constructor also holds the loans on its listed parents, apart from the roots that name the aggregate itself. So
    `list_push` of a record that holds a view of `%0`, followed by `drop %0`, is J4 at the drop. A consumed holder is exempt from
    `loan-outlives-root` only if its loans end with it, that is when the instruction has no owned result or is a take marked
    `noloans`: a call that consumes a holder together with the owner it borrows from, and returns an owner, is J4 at the call.
    A take carries the loans unless it is marked `noloans` (the exporter marks a take whose result type cannot hold a view, such
    as the `None` arm of the lowering of `copy` of an option) (§9, entries 50 and 51).
- **J5 Borrowed values are never taken.** No consumed position, including an owned
  `ret`, receives a borrowed value. A borrowed `ret` requires the returned value's
  roots to be `caller(i)` for `i` in the result's `from` set (R4, V4, W4, P3).
- **J6 One instruction never takes what it also reads.**
  - A consumed operand is not a root of any other operand of the same instruction. The one
    exception is a constructor with an owned result that consumes an owner and reads a view
    of it: the aggregate records the view as a loan and takes over the owner's storage (the roots of the view name the aggregate). A record built that way and `emptied` at once (all its managed fields taken straight out) keeps no parents and counts the same.
  - No value fills two consumed positions of one instruction (M5, M6).
  - **`construct-read`** (entries 61 and 62): a constructor whose result is owned or `emptied`, and that is not a lend,
    reads a borrowed operand only when every root recorded for it is an owner the constructor consumes, or a slot of one
    (entries 19 and 28), or when the result is owned and lists the operand among its parents and its `views` (a view the
    aggregate holds as a loan, which its destruction leaves alone; A19). A
    borrowed operand rooted in the caller, in a later take, or nowhere satisfies neither. Builds count it and the gate
    refuses it (`validate_ownership.build_mode`).
- **J7 Stack values stay put.** A stack value is consumed only by an Update whose result
  is the same stack list (a filling push) or by a stack phi. It is never dropped (the pass
  schedules no `drop` for it), returned, stored, built into a constructor, or passed to an
  owned call position. A stack list holds no managed elements (§3, Fresh), so storing an
  owned, emptied or stack value in one is also J7. J7 is covered by the theorem since C3.6
  (entry 44).
- **J8 Takes are closed, per slot.** `P` holds `(container, slot)` pairs, plus the slots an
  `emptied` aggregate still owes.
  - A *take* is a Project instruction whose state is `owned` and that names a `slot`. It
    requires its container to be owned, live and without a pending take of that slot, and
    adds `(c, k)` to `P`. A take from a borrowed container is rejected, and so is a borrowed
    read of a slot that a take has opened. A take out of an `emptied` aggregate is a complete
    move: it needs an owed slot, removes it, and requires nothing of `L`.
  - A *closing update* closes a slot: `record_set`, `array_set`, `list_set`, `list_set_field`
    and `dict_set_value` close the slot they name; `list_pop` closes the slot it names (`tail`
    is closed by the take at the list's length); `dict_remove` closes the slots its `taken`
    parts name (`k<I>` for the key, `v<I>` for the value). `released -` on a store requires its
    slot pending, and `released old` requires it not pending. The update consumes the
    container as its first consumed operand and passes the container's other pending slots on
    to the container it returns.
  - While any slot of `c` is pending, `c` is not consumed as a whole (`drop`, a call, a
    constructor, a phi, `ret`, an update that is not the closing store). An `emptied`
    aggregate is never consumed, and is used only to take its owed slots and to read its
    scalars. At `ret`, `P` is empty.
  - **Guards.** A pending slot may carry a *guard*, the branch decision it was opened under,
    so that a take made under one branch and its close under a later branch on the same test
    are correlated (`i = dict_find(d, k)`; `if i != -1`: take `v<i>`; later `if i != -1`:
    `dict_remove`).
    - A branch decides a *test*: when its condition is a `cmp` or `fcmp` defined in the
      branch's own block, the test is the operation, the predicate (`imm`) and the two operands,
      an operand defined by an `iconst` being the constant (`imm`, by value) and any other the
      value; otherwise the test is the condition value. Two tests are the same when they are
      equal. A decision is a test with the arm taken (its polarity).
    - `G` holds the decisions known on the path. An edge out of a branch adds the decision of
      its arm to the source's, and settles every guarded entry of the same test: on the arm the
      guard names it becomes unguarded, on the other arm it is removed. An edge that decides a test
      the other way from a decision already known on the path is infeasible: no state flows along it.
    - At a join, an entry open on some incoming edges and not on others is kept as guarded by a
      decision that every edge with the entry knows with its polarity and every edge without it
      knows with the opposite polarity. The join's `G` is the decisions common to its edges.
      An entry for which no such decision exists is a mismatch (J8).
    - A guarded entry is open only where its decision holds, so every use that needs the slot
      open or closed (a take of it, a closing update, a whole-container use, a borrowed read,
      `ret`) rejects it; only a later branch on the same test removes the guard.
    - A guarded entry names a container that is live (in `L`) wherever the entry is joined; otherwise the join is
      refused (J8 `join-pending`). No certificate text reaches the clause, since the live sets of the edges of a join are
      compared first (J2) and no state the solver builds has a guarded take on a dead container; the clause is the Lean
      checker's (its invariant `Inv.Gin` needs it) and a unit test states it (§9, entry 52).
    - Defining a value, by an instruction or by a phi, drops the decisions that mention it. Defining
      a value that the test of a guarded take mentions is a J8 failure (`guard-redefined`): after
      it the model cannot say whether the take is open. This can only happen through a loop.

Each check reports the function, block, instruction, the check's name and the nearest
source rule (the rule column of §7).

## 6. The theorem

**Model.** The Lean model abstracts the IR to §3's classes:
- a heap of allocations, each with an owner tree: a value owns its managed children;
- a function body as blocks of class-level instructions;
- small-step execution.

A **fault** is any of:
- reading or consuming an allocation that is not live;
- destroying one twice;
- consuming or destroying an allocation reachable only from a `caller(i)` root.

**Contract of a function `g`:**
- **Before the call:**
  - the owned arguments are live and own disjoint allocation trees;
  - the borrowed arguments are live;
  - the owned arguments' trees are disjoint from the borrowed arguments' trees
    (`apart`); call sites establish it through J6 and M5;
  - the heap is well formed (`wf`): the root of every live cell's tree is a live cell
    whose label is itself.
- **After a normal return:**
  - every owned argument's tree has been destroyed or is reachable from the result;
  - the borrowed arguments' trees are unchanged and live;
  - an owned result is a fresh tree, disjoint from the borrowed arguments;
  - a borrowed result lies inside the trees of the arguments its `from` set names.

**Theorem (per function).** If `check f c = true`, and every function `f` calls
satisfies its contract, then every execution of `f` from a state that meets `f`'s
before-the-call condition never faults. Every normal return then meets `f`'s
after-return condition. In particular, every allocation created during the call or
passed to an owned parameter is destroyed exactly once or reachable from the result.

J7 (stack escape) is covered since C3.6: a stack list is a value kind of its own and escaping
it is a fault (§9, entry 44). From C6 the faults also include destroying a cell that was lent to
a group before the group is consumed (§10, rule K1).

**Corollary (whole program).** If every function of a module checks, and the external
functions satisfy their contracts (A5), then no execution of the program faults, and
at a normal exit of `main` nothing it allocated is left live. The proof is by
induction on the length of the execution, so recursion is covered.

Traps end the execution and are excluded: they run no destruction
(RC-TRAP-TEARDOWN-1).

## 7. The 54 rules

The proof covers the run-time property a rule protects. It does not prove that the
source checker enforces the rule's predicate.

- **S** (safety): a property J1–J8 checks in the final IR.
- **C** (clarity): a source discipline the proof does not need.
- **T** (type): a type-level rule the model takes as given.
- **S2**: stage 2.

| Rule | Class | Checks | Rule | Class | Checks |
| --- | --- | --- | --- | --- | --- |
| T1 Managed types | T | | V1 Slices are views | S | J1, J4 |
| T2 Move-only types | T | | V2 Views are never stored | S | J5 |
| T3 No shared mutable identity | T | model assumption | V3 View sources stay put | S | J4 |
| T4 Containment | T | | V4 Returned views | S | J5 |
| B1 Writability | C | | V5 Joins of views | S | J1 (phi) |
| B2 Moves (`own` markers) | C | the move itself: J2 | V6 Dictionary views | S | J4, J5 |
| B3 Use after move | S | J2, J3 | V7 View operations | T | |
| B4 Reinitialization | S | J2 | X1 Matching a name borrows | S | J1, J4 |
| B5 Joins | S | J2 | X2 Mutable matches | S | J4, J6 |
| B6 Loops | S | J2 | P1 Resource origin | C | |
| B7 No moving out of a container | S | J5, J8 | P2 Resource lifetime | S | J2, J4 |
| B8 No partial record moves | S | J2 (`record_take`) | P3 Returned resources | S | J5 |
| B9 Const place bindings borrow | S | J4 | P4 Scoped handles | S | J4 |
| R1 Plain parameters borrow | S | J1, J5 | P5 Provider contexts | S | J4, J5 |
| R2 Loans block changes | S | J4 | K1 Lent task arguments | S2 | |
| R3 Borrowed call results | S | J1, J4 | K2 Scoped groups and handles | S2 | |
| R4 Borrowed returns | S | J5 | K3 Parallel map | S2 | |
| R5 One kind of return | S | J1 | L1 Linear Results | C | leaks: J2 |
| R6 Borrowed selections | S | J1 (phi) | C1 Written copies | C | |
| R7 Iteration | S | J4 | C2 Old captures | C | |
| M1 Mut parameters | S | J1, J2 | C3 Destruction | S | J2 |
| M2 Declared mutation | C | | Z1 Evaluation temporaries | S | J2 |
| M3 Call markers | C | | Z2 Retired analysis budget | C | |
| M4 Writable targets | C | | Z3 Build-time ownership limits | C | |
| M5 Disjoint arguments | S | J6 | | | |
| M6 No self-source | S | J6 | | | |
| W1 Taking parameters | S | J2 | | | |
| W2 Own argument markers | C | the transfer: J2 | | | |
| W3 Function types | T | | | | |
| W4 No slice to own | S | J5 | | | |

**Totals:** 33 S, 12 C, 6 T and 3 S2.

Since C6 the proof covers the three S2 rules (§10, entries 42 and 43): K1 by J4 (`loan-outlives-root`), K2 by J2
(`group-join`) and J3, and K3 by no check of its own. The rules document gives the check, the Lean lemma and
the assumptions of every rule in `docs/ownership-rules.md`, "Proof coverage".

## 8. Trusted assumptions (`proofs/ownership/AXIOMS.md` mirrors this list)

- **A1** The operation-class table (§3) describes what the emitter and the runtime
  do.
- **A2** `drop` frees exactly its operand's allocation tree, and allocation returns
  storage disjoint from every live tree (`core_rt.c`).
- **A3** `undef` of a managed type is the null owner and is immortal: destroying it,
  or consuming it into a phi or a store, is a no-op (`core_owned_child_inline` returns on
  null). It is never dereferenced. It appears on live edges: `own.zig`'s cleanup phis
  carry it on the paths where the owner was not built, and `moveCopiedChild` stores it
  into a taken list slot.
- **A4** Immortal values are never freed, and consuming one changes nothing.
- **A5** External functions (`myl_core_*`, `extern func`) satisfy their signatures'
  contracts; so do the reserved marker calls (§3).
- **A6** LLVM emission keeps each function's instruction order for ownership
  effects: no destruction moves above a use.
- **A7** Task groups (C6, made concrete in §10): the runtime's group, submit, take and end
  contracts (A7.1–A7.8), including that the thread pool runs a task concurrently with its
  submitter, only between its submit and its group's end, and that `myl_core_owned_group_end`
  returns only after every task of the group has finished.
- **A8** (retired in C3.6) J7, the stack escape, is covered by the theorem; see §9, entry 44.
- **A19** (lane VAL, entry 62) The parts an owned or `emptied` constructor hands out are the trees it consumes or the
  views it lists: no constructor stores a borrowed managed value it only reads into a slot its destruction or a take
  treats as owned. Enforced by J6 `construct-read` and the exporter's `views`; not modelled (a take yields a fresh
  tree), and a proof needs per-field provenance, which is not planned.

## 9. Changes after C0

Each entry gives the date, what changed, why, and whether the Lean model followed.
"C1" is lane 1, "coordination" is the coordinator's message to lane 1 on the same day.

| # | Date | Change | Reason | Lean model |
| --- | --- | --- | --- | --- |
| 1 | 2026-10-26 (C1) | Mechanism of §1: the pass writes its table (`Capture`) when it has scheduled the drops, and the exporter describes the final IR from that table. Nothing is rebuilt from the final IR. | After `own.zig`, `index_checks` and `overflow_edges` change only `check` markers and `forward` replaces scalar field reads: none changes an ownership-relevant instruction. The instructions added after the analysis are drops, cleanup phis, their `undef`s and jumps, whose states follow from the op. Rebuilding from the final IR cannot recover `owned_get`, `taken`, `emptied` and `stack`, which the pass keeps in side tables. A certificate run bypasses the optimizer caches (their restored bodies carry no table). | none |
| 2 | 2026-10-26 (C1) | §3: `copy` gets the row `Forward`; `array_get` moves from Inspect to Project; the op count is 107. | `copy` is an operation; `array_get` of a managed element is a slot read, and `array_set` is its store. | add class `Forward` to the class line set; `array_get` is Project |
| 3 | 2026-10-26 (C1) | §3, §2, §8 A3: `undef` of a managed type is the null owner (immortal) on live edges, not an operand of an unreachable edge. | `own_conditional_drop.zig` builds `phi(owner, undef)` for a drop whose owner does not dominate it, and `moveCopiedChild` stores `undef` into a taken slot; `core_owned_child_inline` returns on null. Skipping an `undef` edge as dead (coordination item 3(d)) would skip the checks of a path the program takes. | `edgeTo` must not skip the edge; consuming `undef` is a no-op |
| 4 | 2026-10-26 (C1) | §3: `str_char` is owned, a fresh string or a static block (**verified**). `text_frame` is borrowed({a}) and never consumable (**verified**). | `myl_core_ir_str_char` returns `core_ascii_char` (static header) or `str_from`; `text_frame`'s result is `a` or a frame header whose kind is `STR` without the static bit, so a `drop` of it would free a stack slot or the caller's block. | none |
| 5 | 2026-10-26 (C1) | §3, Update/Construct/Take/Call: scalar results (update of a scalar aggregate, take of a scalar payload), a call with no result (`inst -`), construct rules for borrowed and view operands, owned aggregates that hold views, marker calls, call-result projections. | Each occurs in the corpus; the old table left them undefined. | `classOk` must allow them (see the report) |
| 6 | 2026-10-26 (C1) | §3 slots, §4.1 `slot`/`released`/`slots`, state `emptied`, §5 J8 note: the take protocol covers records, arrays, lists and dictionaries, and `flags.transferredRead` marks only four of the takes. | `record_get` takes (about 570 in 1272 sample functions), `array_get`, the `markPops` read and `emptied` aggregates (about 300) carry no marker in the IR. | `pairingOps` gains `record_set` and `array_set`; `transferOps` gains `record_get` and `array_get`; per-slot `P` and `emptied` are needed (**needs decision**) |
| 7 | 2026-10-26 (C1) | §3 Update: implicit releases (`list_set`, `list_set_field`, `dict_set_value`, `dict_remove`, `dict_clear`); `list_pop` releases nothing. | `emit_llvm.zig` `listSet`/`listSetField` and `emit_dict.zig` release the old content unless `transfers.slots` marks the store; `dict_remove` takes its parts from `data`. | stores carry `released` |
| 8 | 2026-10-26 (C1) | §3 Phis: a borrowed phi may take the owned value it selects between; a dead phi (state `none`) is skipped. | One borrowed-selection phi in `borrowed_defaults_64` has an owned fallback operand; six dead phis occur in the 1272-function sample. | `phiShape` allows both |
| 9 | 2026-10-26 (C1) | §4.1: the call line carries `from VALUES`; function names are escaped; `Forward` is a class line spelling. | A call's contract names argument positions, but the file lists no positions; names may contain spaces. | parser reads `from` |
| 10 | 2026-10-26 (C1) | §2, §5 J2/J7: a stack value carries no destruction obligation and is never in `L`. | `classify` gives stack values class `none`; no `drop` exists for them (about 340 stack values in the sample). If the model treats `stack` as `owned`, every stack list leaks at `ret`. | `St.owning` must exclude `stack` (or the model must say so) |
| 11 | 2026-10-26 (coordination) | §4.1: `param <I> %N <state>`; canonical class spellings (`TextFrame` is one token). | Lane 2's parser. | done by lane 2 |
| 12 | 2026-10-26 (coordination) | §5 clarifications: (a) the set `D`; (b) the root table by iteration and its closure; (c) `P` empty at `ret`; (e) consuming a scalar or immortal is a no-op. Item (d), skipping an `undef` edge, is **not** adopted: see entry 3. | Lane 2's checker. | done by lane 2 except (d) |
| 13 | 2026-10-26 (coordination) | §3 phis: stack phi; a phi never consumes a pending container. §5: the state `(L, D, P)`, join equality of `L` and `P`, `D` containment, redefinition removes dependent names, `ret` rules, parents are operands, join reports at the predecessor's terminator, one forward pass then a recheck. | Lane 2's checker (`NOTES.md` 18–26). | done by lane 2 |
| 14 | 2026-10-26 (coordination) | §6: the before-the-call condition adds `apart` and `wf`. | Without them the theorem is false (`NOTES.md` 13). | done by lane 2 |
| 15 | 2026-10-26 (coordination) | §6, §8 A8: J7 is checked, not covered by the theorem in stage 1; the model treats `stack` as `owned`. | `NOTES.md` 10. | done by lane 2; see entry 10 |
| 16 | 2026-10-26 (C2) | §5 J8 is per slot (the "[Needs decision]" paragraph became the rule): `P` holds `(container, slot)` pairs and the slots an `emptied` aggregate owes; a take of `(c, k)` needs `(c, k)` not pending; stores, `list_pop` and `dict_remove` close the slots they name; `released -` needs the slot pending and `released old` needs it not; whole-container uses, borrowed reads of a pending slot and a take from a borrowed container are faults. | The container-level form rejected most real functions (entry 6). | follows the revised `NOTES.md` 8 |
| 17 | 2026-10-26 (C2) | §5: a block ending in `unreachable` has the meet of its edges as its entry state (`L` and `D` intersected, `P` not compared). | Traps run no destruction (RC-TRAP-TEARDOWN-1), and the pass does not release owners on the way; requiring agreement would reject a trap reached from paths with different live owners. | `NOTES.md` 12 |
| 18 | 2026-10-26 (C2, coordination) | §5: the state carries `R`, the roots of each borrowed value on the path; defining a borrowed value takes the roots of its parents at that point, a borrowed phi those of its operand on the edge, and an owned phi or a constructor that consumes an owner renames the roots that named it. Joins unite `R`; the forward pass runs to a fixpoint. This replaces the static root table with *holders* of the first C2 validator, which accepted a borrow whose owner one edge destroyed while another edge's phi (a holder of the same owner by name) was live. | The static table was too coarse (a cleanup phi `phi(owner, undef)` consumes the owner, and the borrows of the owner outlive its name) and, with holders, too weak at joins. | `NOTES.md` 1, 2 (`R`) |
| 19 | 2026-10-26 (C2) | §5 J6: a constructor with an owned result may consume an owner and read a view of it; the aggregate records the view as a loan. | `through_mut_list` (a `mut` parameter written back) builds the record from the owner and a view of it. | `NOTES.md` 11, 15 |
| 20 | 2026-10-26 (C2) | §3 Project, §5 J1: a *forward take*: a borrowed read of a slot whose take follows has that take as its parent; a projection of a call result may be rooted in another projection of the same call. | The pass reads the leaf of a call result before it takes the final owner out of the same result. | `NOTES.md` 5 |
| 21 | 2026-10-26 (C2, coordination) | §3 TextFrame: the result is borrowed({b}), the view the frame holds, not `a`. Supersedes the parent in entry 4. | `borrow_result.zig:74` takes `inst.b`, and the affected functions' own `from` set names the view. Lane 2's corpus run rejected `path::basename`, `path::dirname` and `dictionary_range_keys::built` because of it. | the checker reads the exporter's parents |
| 22 | 2026-10-26 (C2, coordination) | §4.1: a unit value that an instruction names as an operand gets a name and the state `none` (`inst %N undef Constant … state none`); consuming it is a no-op, reading it is J3. | The operand of `dict_insert` for a `dict[K, Unit]` named a value no line defined. | `NOTES.md` 17 |
| 23 | 2026-10-26 (C2, coordination) | §4.1: `iconst`, `cmp` and `fcmp` lines end with ` imm <decimal u64>`, the instruction's `data`. §5 J8: guards. | Two corpus functions open a dictionary take under `if i != -1` and close it under a second `if i != -1`; the join after the first `if` has the slot open on one edge only. Path-insensitive joins cannot accept it; the guard states the correlation. | lane 2 implements the same |
| 24 | 2026-10-26 (C2, coordination) | §5 J4: a borrowed read of slot `k` of an owned container `c` is rooted in `(c, k)`; consuming `c` or taking `k` ends the loan. | Loans on a container's slot were recorded and not enforced. `a02_list_methods` (`lists.extend(mut rows[0], rows[0])`) reads a view of `rows[0]` in the call that receives the take of `rows[0]`: the exporter makes the take the view's parent (entry 29). Unguarding a forgotten entry would call a slot open that may not be. | the coordinator's J4 rule (`loan-outlives-root`) |
| 25 | 2026-10-26 (C2) | §3, §4.1: `dict_remove` exports `slot v<I>`, `released` and a new `taken` extra; `list_pop` of the `tail`. | The slot protocol needs the parts a removal finds already moved out. | `taken` is read by the parser |
| 26 | 2026-10-26 (C2) | §3 Fresh, §5 J7: a stack list holds no managed elements (`promote.zig` skips managed element types), and storing an owned, emptied or stack value in one is J7. | The coordinator asked for the answer; the exporter refuses a function that says otherwise. | none (A8) |
| 27 | 2026-10-26 (C2) | `own.zig` (compiler, no grammar change): a block from which only trap blocks are reachable schedules no drop. | The validator showed three corpus functions (`recursive::test_a_copied_recursive_box_shares_and_separates_nested_lists`, `recursive::test_repeated_write_through_a_boxed_child`, `recursive_values::test_writes_to_copies_leave_other_values_unchanged`) that drop a container with an open take on a path that ends in a trap: the take leaves the slot's pointer in place, so the drop releases it a second time before the trap. The fix removes the drops, as `own.zig`'s own comments say; J8 stays strict. | none: the three rejections disappear from the corpus |
| 28 | 2026-10-26 (C2) | §5 J6: a constructor whose result is `emptied` (a record built only to have its managed fields taken straight out) may consume an owner and read a view of it, like an owned aggregate that records the view as a loan. | `test/fixtures/fix-migration/borrowed_signatures` builds a record from an owner and a view of it and takes the field back at once; the emptied result carries no parents, so no loan is listed. | the constructor-loan exception covers `emptied` results |
| 29 | 2026-10-26 (C2) | §3 Project, §5 J4: a borrowed view of a slot that an owned read of the same slot takes later in the same block, with no read of the view in between, has that take as its parent (a *forward take*); its loan on the take is dead until the take is defined. This replaces the exemption for takes out of `emptied` aggregates in the rule for redefinition. | `lists.extend(mut rows[0], rows[0])` (`a02_list_methods`) reads a view of `rows[0]` in the call that receives the take of `rows[0]` and again on its failure edge; the view and the take are the same allocation. Rule 24 would end the loan at the take. | the checker's placeholder root `fwd(n)` |
| 30 | 2026-10-26 (C2, coordination) | §5 J8: defining a value that the test of a guarded take mentions is a J8 failure (`guard-redefined`), not an entry of unknown state. | Lane 2's checker; the coordinator's decision. It happens only through a loop. | `guard-redefined` |
| 31 | 2026-10-26 (C2, coordination) | §5 trap blocks: the instructions of a block that ends in `unreachable` are checked against the meet of the incoming edges, and a value is usable there only if it is usable on every incoming edge; nothing has to agree at the join. | The path ends in a trap and runs no destruction. | lane 2 switches its checker and proof to this rule |
| 32 | 2026-10-26 (C2, coordination) | §5 J4: owned values that list parents hold the loans of their parents, and consuming a root owner or taking a rooted slot while the holder lives is J4 (`loan-outlives-root`); a constructor that consumes an owner takes over the loans on it (slot roots become the wildcard slot of the aggregate) and inherits its operands' loans, and a phi that consumes a holder carries its loans. `R` also records the loans of owned holders. | `NOTES.md` 18. | `loan-outlives-root` |
| 33 | 2026-10-26 (C2) | §3 Project, §5 J1: a borrowed projection of an `emptied` aggregate (or of any container) may list, besides the container, takes of the same container that follow it. | `borrowed_signatures` builds a record from an owner and a view and takes its field back at once: `inst %45 record_get %84 … borrowed parents %84,%46` with `%46` the take. | forward parents (entry 20) |
| 34 | 2026-10-26 (C2) | `build_list_methods.zig` (compiler, no grammar change): `extend` of a list with an element of the same list read at the same index (`lists.extend(mut rows[0], rows[0])`) is one list: the append reads the receiver itself, and the runtime same-block test and the view of the source are gone. | The lowering kept a runtime branch on `myl_core_owned_same_block` and, on the other arm, read a view of `rows[0]` while pushing onto `rows[0]`: safe because the arms are exclusive at run time, but the certificate cannot see that, and a view of a list that outlives an update of it is what J4 refuses. Both reads name one slot of one list statically. | none |
| 35 | 2026-10-26 (C2, coordination) | §5 J8: an edge whose test is already decided the other way on the path is infeasible and is not taken. | `NOTES.md` 19 (facts). | the checker skips such an edge |
| 36 | 2026-10-26 (C2.7) | §5: a block from which only trap blocks can be reached takes the meet of its edges, like a block that ends in `unreachable`; borrows whose root was consumed leave `D` and `R` at the consumption. | EDA stage 2 (`eval_design_block_test::parse_form`) drops its list on the path that continues and leaves it on the path into a trap, and the paths join in a block that only jumps to the trap block: the pass's own rule (entry 27) leaves the owner live there, so the join cannot agree. The old state kept every dead borrow, so a function with thousands of views took 3.4 GB to validate. | the Lean checker's trap block must cover trap-only chains, as `own.zig`'s `dead_end` does |
| 37 | 2026-10-26 (C4.5, coordination) | §4.1: a value is defined once, and a text that defines one twice is malformed input (an error, not a verdict). §5 J8: consuming an `emptied` aggregate is J8 (the slot protocol: an emptied aggregate is never consumed), not J2; J8 comes before J2 at `ret`. | Fixture differential Zig/Lean (`tests/ownership-proof-known.json`): the checkers reported these three differently; the coordinator decided. A value is defined again only by executing its definition again, and a guarded take cannot reach a loop head that joins an edge without it (J8 at the join), so `guard-redefined` is a defence that no text reaches. | `dst-unique` in the reader; the consume check reports J8 |
| 38 | 2026-10-26 (C6.0) | §3, §4.1: a `box_make` with `flags.lent_box` is exported as `box_make Construct` with the extra `lent %G`. It reads the lender (first) and the group `%G` (second), consumes nothing, and has state `owned` (the box shell); its `parents` is `-`. | The lowering of `g.submit` (`build_task.zig`) boxes a lent argument this way; `own.zig` and `ownership_ops.zig` already treat it as reading the lender (rule B). The class table is per operation, so the lend is told apart by the extra, not by a new class or operation name. | Inst gets `lent`; `lend` shape check (J1) |
| 39 | 2026-10-26 (C6.0) | §4, §8 A7: the reason `task-group` is no longer produced; the exporter stops refusing lent boxes, `ty == task_group` and calls of `myl_core_owned_group_*`/`myl_core_group_*`. A7 is replaced by A7.1–A7.8 (§10.5). | The 41 functions of `tests/lang/parallel_groups`, `parallel_map` and `parallel_wrapper_inputs` that were `unchecked task-group` become checked. | the reader still accepts the reason |
| 40 | 2026-10-26 (C6.0) | §5 J4: a lend adds the roots of its lender to the loans of its group; the group holds them until it is consumed (`myl_core_owned_group_end`). While the group is live, consuming a lender root or taking its slot is `loan-outlives-root`. | Rule K1 (lent task arguments are neither consumed nor changed before the join). `own.zig` rule A keeps the lender's drop behind every join of the group; the check makes that a property of the final IR. Prototype: the 260 functions of the three corpus files accept, and moving the lender's `drop` above the group end in `fall_through` is J4. | `instNext` for a lend; `loansOk` unchanged |
| 41 | 2026-10-26 (C6.0) | §5 J4: `loan-outlives-root` also applies to a constructor with an `emptied` result (before, every constructor was exempt). Only a constructor with an owned result moves the loans with the storage. | The Lean semantics destroys the trees an `emptied` constructor consumes (the storage is taken out again by owned reads that the model gives fresh trees), so a lent cell must not be among them. No corpus function consumes a loan root that way. | `dyingOwners` |
| 42 | 2026-10-26 (C6.0) | §6, §10: the theorem's faults include a cell lent to a group that is destroyed before the group is consumed. The thread pool's concurrency is not modelled; a task is a call that may read the lent cells at any time between its submit and the group's end. | K1 is the memory-safety content of the lend; a task's reads race with its submitter, so the model forbids the submitter from destroying what a task may still read. | `DState.lent`, a new fault |
| 43 | 2026-10-26 (C6.0) | §10.4: K2 (scoped groups and handles) and K3 (parallel map) need no check of their own: the group is an owned value (J2: consumed once on every exit edge; J3: no submit, take or end after the join), handles are scalars, and `myl_core_owned_map*` are calls that join before they return. | Their runtime backstops (`R_TASK_ESCAPE`, `R_TASK_GROUP`) are the user-facing rules' last line, not part of the certificate. | none |
| 44 | 2026-10-26 (C3.6) | §5 J7, §6, §8 A8: J7 is covered by the theorem. A stack list is a value of its own kind (`Val.stk`), and consuming one other than as the first operand of a filling push, pushing a value that owns a tree into one, or returning one is a fault. | Lane 2, C3.6 item 1. The checker was already stricter in the Lean (a stored owned value is J7, as entry 26 says). | `Val.stk`, `Fault.escape`, A11 |
| 45 | 2026-10-26 (C6.1, coordinator) | §5 J2, §10.4: a group (an owned value that was the second operand of a lend on the path) is consumed only by a call whose result state is `none`, or by an owned phi that carries its "lent-to" bit; a constructor, an update, a take, a `drop`, a call that returns a value and a `ret` are J2 `group-join`. The state gains one bit per owned value (a lend sets it, an owned phi moves it, joins OR it, a definition or consumption clears it); the format does not change. | The Lean proof (C6.2) would otherwise have to assume that whatever consumes a group ends it, which the loans cannot show: an update or an owner-returning call could keep the group's storage alive after the loans on it are gone. | `group-join` in the checker; the same bit |
| 46 | 2026-10-26 (C6.1, coordinator) | **Superseded by entry 55.** §5 trap blocks, §10.4: (1) an edge into a trap block must keep every value of its `L` that carries the lent-to mark in the meet's `L`; otherwise J2 `trap-group` at the terminator of the edge's block. (2) A block that contains a lend is not part of the trap-only region and is checked like an ordinary block. | The meet intersects `L`; a group live on only some edges of a trap block would lose its loans there, and a lender dropped in the block would go unseen. The theorem needs the rule. | `trap-group` in `trapCompat`; `trapLocal` excludes a lend |
| 47 | 2026-10-26 (C6.1) | §10.7, §4.1: the reader only reads `lent %G` (once per line). A lend whose second read is not its group, or a `lent` extra on an operation that is not a `box_make`, is a J1 verdict of the validator, not a malformed file. | The Lean checker judges both as J1 (`lend`); the C6.0 text had the Zig reader refuse the file, a difference in kind that only a constructed function shows. | none (already J1) |
| 48 | 2026-10-26 (C6.1) | **Superseded by entry 57.** §3 Call, §8: the exporter checks the call-site agreement (`CallWf` of the Lean whole-program corollary, `proofs/ownership/AXIOMS.md` A9) at every call of a function of the program, and refuses a function with a call that disagrees (`E_CERTIFICATE`, so a validating compiler fails): one argument per parameter; a parameter of an unmanaged type receives a scalar, an immortal or a unit value; the state of the call's value follows what the callee returns (an owner, or an `emptied` record, for an owner; a borrow for a borrow; a scalar for a scalar) and is never a stack list. A call of a runtime function or a reserved marker call (A5) and an indirect call are not checked. The certificate text names no callee, so this is a check of the compiler's own export, not a verdict of the validator or of `certcheck`; `CallWf.noEmptied` is **not** enforced. | The corollary assumes `CallWf`; checking it makes the part that can be checked a fact. `noStack` already holds (J1: a call result is never a stack list). `noEmptied` cannot be: 1,041 calls of the corpus (v3 export, 10,775 functions) return an `emptied` record (a `mut` parameter written back whose other parts the caller takes at once), and rejecting them would reject real functions, so the corollary keeps `noEmptied` as a hypothesis until the semantics of `emptied` values (NOTES.md, "Open gaps") covers them. | none |
| 49 | 2026-10-26 (C3.8) | **Superseded by entry 55.** §5 trap blocks: the meet of a trap block unites the roots `R` and the open takes `P` of every incoming edge (before, those of the first edge only); where an entry is unguarded on one edge and guarded on another, the unguarded one wins. An edge's roots and takes are then contained in the meet's. | Unsound otherwise: a slot taken on a later edge was invisible at the meet, so a second take passed (`bad_trap_meet_take_first`, `reject J8 b3 0`), and a borrowed phi of views of two owners lost one root, so the drop of that owner and a read of the phi passed (`bad_trap_meet_roots_swapped`, `reject J4 b3 1`). | `meetState`, `trapCompat` |
| 50 | 2026-10-26 (C3.8) | §5 J4, §3 Construct/Update/Call/Take: an instruction with an owned result hands on to it the loans of the owned values it consumes (a constructor renames the roots of the owners it takes to the aggregate); the result of a constructor holds the loans on its listed parents, apart from roots naming the aggregate itself; `loan-outlives-root` exempts a consumed holder only when its loans end with it (no owned result, or a take marked `noloans`). | Before, a holder consumed by an update or a call lost its loans: `list_push` of a record that holds a view of `%0`, then `drop %0`, left the view dangling (`bad_loan_lost_through_update`, `bad_loan_lost_through_call`, `reject J4 b0 4`), and a holder consumed together with its own root passed (`bad_holder_with_its_root`, `reject J4 b0 3`). The loans a constructor was meant to inherit from the holders it consumed were forgotten when the aggregate was defined, too. | `instNext`, `loansOk` (`carries`) |
| 51 | 2026-10-26 (C3.8) | §4.1: the new extra `noloans`, a flag that stands alone, written on a `Take` whose result type cannot hold a view; a take carries the loans of the aggregate it leaves unless it is marked. | A take of a part that holds a view must carry the loans (`bad_take_holds_view`); the `None` arm of the lowering of `copy` of an option takes from the holder although its payload holds nothing, and would otherwise reject the corpus function `borrowed_signatures::test_read_only_wrapper_arguments_accept_borrowed_slices_and_owned_values` (`ok_take_none_arm`). The exporter knows the type; the lowering is unchanged. | `Inst.dropsLoans` is `cls == .take && noLoans` |
| 52 | 2026-10-26 (C3.8) | §5 J8, guards: a guarded take names a container that is live where the entry is joined (J8 `join-pending`). | Lean's invariant `Inv.Gin`, stated in `slotsFit`. No certificate reaches the clause (the live sets of a join are compared first and the solver builds no guard on a dead container), so the Zig side states it in `compatible` and tests it on hand-built states. | `slotsFit` |
| 53 | 2026-10-26 (C3.8) | **Superseded by entry 55.** §5: the trap-only region is made of chains of jumps: a block belongs to it when it holds no closing update and no lend and ends in `unreachable` or jumps to a block of the region without a live phi; a block that branches, one with a closing update or a lend, and a block whose jump leads to a phi are checked like any other (agreement between their edges). Before, a block belonged to it when all its successors did. | The meet has no decided tests, so a branch cannot be checked in the shadow of one edge; a closing update compares the open takes with the `released` mark exactly; a phi in the middle of a chain needs the edge step. Lean proves the chain case (`bad_trap_closing`, `reject J8 b3 0`; `bad_trap_branch_chain` and `bad_trap_chain_phi`, `reject J2 b1 1`). | `trapChain`, `trapLocal` |
| 54 | 2026-10-26 (C3.8) | **Superseded by entry 55.** §5, §10.4: `trap-holder` replaces `trap-group` (entry 46): every owned value of an edge's `L` that holds loans (a group that was lent to, or an owner with an entry in `R`) must be in the meet's `L`. | The loans of a holder that is live on some edges only would not be looked at in the block (`bad_trap_holder`, `reject J2 b1 0`; `bad_trap_group` keeps its verdict). | `trap-holder` |
| 55 | 2026-10-26 (C9.1) | §4.1, §5, §10.4: the trap region (every path from the block ends in `unreachable`) may carry `abandon bP %V,…` lines, one per predecessor edge, naming the owners the path abandons. The edge state loses them (`L`, and the open takes of a listed container); the block is then merged like any other. J1 `abandon-shape`, J2 `abandon-region`, `abandon-live`, `abandon-group`. **Supersedes** the trap meet, `uniteTakes`, `trap-group`/`trap-holder` and the chain rules of entries 46, 49, 53 and 54. | `own.zig` releases nothing on a path to `unreachable`, so the edges into a trap block disagreed about what is live; the meet that papered over it (intersect `L`, unite roots and takes, require holders live at the meet, restrict the region to jump chains) was the source of both real validator holes of C3.8, five Zig/Lean deviations and the C2.7 out-of-memory case. Certificate growth is under 0.25% (C9.0). `bad_trap_holder` is accepted when the holder is listed on its edge. | `Block.abandons`; `TrapShadow.lean` and the trap cases of `Checker.lean` go |
| 56 | 2026-10-26 (C9.4) | §6, §8: the whole-program corollary covers a call whose value is `emptied` (the write-back record of a function with `mut` parameters, which the caller takes apart at once). `CallWf.noEmptied` is replaced by `resEmptied` (the callee returns an owner, which entry 48 already checks); the step of such a call destroys the callee's result tree and binds the destination to an immediate, as the per-function semantics treats an `emptied` constructor. New assumption A16: the storage of the returned record is exactly the storage of the parts the caller takes at once (enforced by `Taking.empty` and J8 `emptiedOk`). Entry 48's last clause (`noEmptied` not enforced) is superseded; entries 28 and 41 stay. | The corollary excluded 26% of the gate programs, 73% of EDA stage 2 and 80% of selka (891, 2,036 and 279 calls); with it, every function of 632/632, 140/140 and 86/86 programs is accepted and none is excluded by an `emptied` call; programs with a call of a unit program function stay outside until C9.2 (`CallWf.dst`), see the correction in `docs/design/c9-write-back.md`. `docs/design/c9-write-back.md`. | `callNext`, `effect_of_post_emptied`; AXIOMS.md A16 |
| 57 | 2026-10-26 (C9.2) | §4.1, §5: a function carries a callee table, one `callee N NAME KIND PARAMS RESULT FROM` line per distinct callee, after its `param` lines, and each `call` and `call_indirect` line names its entry (`callee N`). The validator makes the call-site agreement (`CallWf`) a check: J1 `callee-table`, `call-entry`, `call-arity`, `call-scalar`, `call-result`, `call-from`. A program-level link (`selka link-certificates`, `certcheck --link`) checks each `program` entry against the callee's own `function` and `param` lines found by name among the functions of the program: `callee-missing`, `callee-arity`, `callee-param`, `callee-result`, `callee-from`. The exporter's private check (entry 48) is deleted; the entry and the callee's own lines are derived from one function, so they cannot differ. A runtime, `extern` or marker callee is named and checked for arity only (A5 stays an assumption). | The certificate named no callee, so the call-site agreement could only be the exporter's own check and the corollary's hypothesis. With the table the validator and Lean state the site half from the certificate alone, the entry half is a link that someone checks (a hypothesis nobody checks, like `CallWf.dst` in C9.4, is how a proof goes wrong), an indirect call is checked against its function type, and a later step can check runtime callees against the operation table. | `Function.callees`; `CallWf` split into a site half and a link |
| 58 | 2026-10-26 (C9.9) | §3 Project, §5 J4, entry 29: the lowering no longer produces the forward take of entry 29. The dead view the evaluation of a `mut` place argument leaves in front of the take of the same slot is dropped (`take_first.zig`, run with the other function-local normalizations and after ownership turns a copy of a list element into a take) when nothing observable (`fuse.inert`: no write, call, print, allocation or trap) lies between the view and the take, and the take reports the view's place in the source, so every failure and effect keeps its order and the release binaries are byte for byte the ones of before; and a call's value that is a view borrowed from a written-back part (`-> T from p`) is read after that part. The gate corpus has 8 forward takes where it had 73 (5 of the 73 were the borrowed-result case); the 8 have a call, an allocation or a checked read between the view and the take. The rule of entry 29, the placeholder root `fwd(n)` and A15 stay in both checkers; removing them is a joint step. | `lists.extend(mut rows[0], rows[0])` no longer makes one (entry 34); the 160 of 168 views C9.0 counted were dead lowering leftovers, not aliasing the user wrote. | unchanged |
| 59 | 2026-10-30 (F5) | §5 J1: the Zig validator is as strict as Lean's `parentsOk` and the checks beside it, for every class. The parents of an instruction's value follow the state alone: a borrowed value names only what `parentOperand` allows (a read operand, a parent of a borrowed or owned operand it reads, the owned slot take of its container that follows it, or for a projection a `from` value of its call) and never `caller`; an owned value names only operands it reads; a scalar, immortal, stack, `emptied` or unnamed value and a non-borrowed phi name none. A constant other than `undef` is a scalar or an immortal. A borrowed call's contract may not name a parameter the callee takes, and an argument at a `from` position that is not a scalar, an immortal or a unit value must be a parent. A line with no value has state `none` (the reader refuses the text). Before, `Construct` and `Call` were exempt from the owned and bare-state rules, a borrowed constructor's parents were not looked at, a later sibling read of the container counted as a forward take, any projection of the call counted as a sibling, a phi's parents were not looked at, and a constant could be `none`. | F3's gate found the Lean checker rejecting the callee `withmut` (J1) that the Zig validator accepted; a sweep of one-line mutants of the gate corpus (`experiments/incremental-engine-20261030/F5/j1_differential.py`) found 1,079 of 15,876 that the Zig validator accepted and Lean rejected, all in these classes, and 8 of 21,108 after (6 reader, 2 J8 in unreachable blocks). 19 rejected, 2 accepted and 1 malformed fixture in `validate_ownership_test.zig` carry the same verdict in both checkers. | `parentsFault`, `parentOperand`, `forwardTake`, `callFromOperand`, `callFault`, `edgeFailure`, `ownership_parse.zig` |
| 60 | 2026-10-30 (F7) | §4.1, §5 J8: the Zig reader refuses what `Parse.lean` refuses, and the Zig validator judges `emptied` aggregates over every block. A certificate file starts with the format line (`parseFile`; bare function text, which the validator's fixtures are, is still read by `parse`), `class OP CLASS` lines are three words with a known class and are not read inside a function, and an instruction names an operation of that table. In a function: `param` and `callee` lines come before the first block and the parameters are numbered 0, 1, …; the pseudo-block is `block b- preds -` and comes before `b0`; block ids ascend; a block has exactly one terminator and nothing follows it (the checker accepts lines after it, the Zig reader refuses them: it used to keep a slice of a list that later lines grew); a phi line is inside a block and before its instructions; `end` is one word and every edge targets a block the function defines; numbers are decimal digits; an extra is given once. J8 `emptiedOk` is a function-wide check in both: an `emptied` value is defined by an instruction, every use of it is the first read of a projection in its block, each slot it lists is taken once and no other, and it is placed at the first instruction that misuses it (`emptiedBadUse`). Before, Zig judged only the blocks it reached. | The reader sweep (`experiments/incremental-engine-20261030/F7/reader_differential.py`, mutated text of the gate corpus): 675 of 6,339 texts that Zig read and the checker refused, and 16 crashes, now 0 of 6,445 and 0; the F5 J1 sweep left 8 of 21,108, now 0 of 21,204. All 9,426 corpus functions are accepted by both. | `ownership_parse.zig` (`parseFile`), `validate_ownership.zig` (`emptiedFault`), `ownership_commands.zig` |
| 61 | 2026-11-12 (VAL) | §5 J6: the rule `construct-read` (above), in the Zig validator and in Lean's `check` (`constructReadOk`), with the same verdict (J6 at the constructor). Builds run it counting (`--stats` prints `selka: construct-reads: N ...`); `selka validate-certificates`, `dump-ir --certificate --validate` and `certcheck`, and so the gate's `ownership-proof`, refuse. The format does not change. | Lane FX6 (F-36): `dicts.items` over a dictionary of a borrowed type built each item as an `emptied` record that read the key as a borrow of the dictionary, took it out as an owner and dropped it every iteration; both checkers accepted the plan, because a constructor's owned or emptied result was not asked where a borrow it reads lives. The rule refuses that plan and the ten of `tests/lang/dict_lent_iteration.selka` made before FX6's fix, and nothing on main. The model cannot show the fault (a take out of an `emptied` aggregate yields a fresh tree, `NOTES.md` item 13), so the theorem does not use the check. | `constructReadOk`, `InstOk.cread`; the theorem is unchanged |
| 62 | 2026-11-13 (VAL, phase 2) | §4.1, §5 J1 and J6, §8: format `ownership-certificate-v2`, whose Construct lines carry `views %V,…`; condition 2 of `construct-read` asks that a listed loan be a view; J1 `views`; assumption A19 (what a constructor hands out is what it consumes or the views it lists). Both readers refuse a v1 file by name. Builds count, the gate refuses, as for entry 61. | Without the view part an owned aggregate that listed a borrowed `str` as a loan passed and would destroy the caller's text with itself; the certificate did not say which operands are views, and the exporter, which has the types, is the one place that can. A19 names the gap the model leaves (a take yields a fresh tree). | `viewsOk`, `Inst.views`, `formatVersion`; A19 is not a Lean statement |

### The C9.1 rules (entry 55)

**Format.** In a trap-region block, directly after the `block bN preds …` line and before its phis:

```text
abandon bP %V,%V,…        one line per predecessor bP whose edge abandons something; values strictly ascending
```

An edge that abandons nothing has no line. Nothing else in the format changes.

**Which owners are listed.** For each edge into a region block `T` from `P`, the owners that are live on the edge, that `T` and the
region after it do not need, and that no phi of `T` takes on the edge: exactly the deaths `own.zig` skipped there because a trap
follows (the death on the edge, and the death after the last use inside a region block, listed on each edge out of that block unless
the block consumes the owner). An owner built on one arm only is named by the nullable phi `own_conditional_drop` made for it. A
lent-to group is never listed.

**Checks** (on the edge `P → T`, at `P`'s terminator, before `T`'s phis take their operands):
- *J1 `abandon-shape`:* a line names a block that is not a predecessor of `T`, a predecessor twice, or its values are not
  strictly ascending.
- *J2 `abandon-region`:* `T` is not in the trap region.
- *J2 `abandon-live`:* a listed value is not an owned value live on the edge (a scalar, an immortal, an `emptied` aggregate or a
  borrowed value is not abandonable; an owed slot must agree at the join, like any open take).
- *J2 `abandon-group`:* a listed value is a group (it was the second operand of a lend on the path).
- *The edge state:* the listed values leave `L`; the open takes and guarded takes whose container is listed leave `P`; the lent-to
  mark goes with them. A phi operand that is also listed fails as a phi operand that is not live.
- *The join:* from here `T` is an ordinary block.

**Why it is sound.** An abandoned owner is never read or destroyed again, so no fault can involve it; a trap ends the run before
any normal exit, so `main_no_leak` keeps its meaning. The loans of a leaked holder end with it: nothing reads it. The loans of a
group do not, since its tasks read the lent cells, which is why a group is never abandoned.

**What went.** Zig: the trap meet in `merge`, `uniteTakes`, `strandedHolder` and `trap-holder`, the chain rules (`trapLocal`,
`chainContinues`, `hasLivePhi`), the `ends(target)` arm of the recheck; the exporter adds the lines from `own.zig`'s record of the
skipped deaths. Lean: the trap shadow (`TrapShadow.lean`) and the trap cases of `Checker.lean` and `Soundness.lean`.

### The C9.2 rules (entry 57)

**Format.** In a function, after the `param` lines and before `block b-`, one line per distinct callee, ids from 0 in the order the
calls first use them (block order). The table is the function's own, so a function stays self-contained for the gate's per-function
digests; the callee is found across units by its name.

```text
callee N NAME KIND PARAMS RESULT FROM
```

- `NAME` is the callee's name, escaped like a function name, as it appears on the callee's `function` line, or `-` for an indirect
  call (its entry is the function type's signature, one entry per distinct signature). `KIND` is `program` (a function of the
  program), `runtime` (a `myl_core_*` function), `extern` (an `extern func`), `marker` (a reserved marker call of §3) or `indirect`.
- `PARAMS` lists the parameters in order, or `-`. Each word gives how the callee takes the parameter and the state its own `param`
  line gives it: `take` (consumed; state owned), `take-scalar` (consumed; an unmanaged parameter passed to a taking parameter, state
  scalar), `read` (read only; a managed or view-holding parameter, state borrowed) or `read-scalar` (read only; unmanaged, state scalar).
- `RESULT` is the kind of the callee's `function` line (`scalar`, `owned` or `borrowed`; a function that returns nothing returns
  `scalar`). `FROM` is its `from` list, or `-`.
- A `call` or `call_indirect` line ends its extras with `callee N` (after `from …`, before `lent`/`noloans`/`imm`). Its operands are the
  arguments in parameter order: walk `PARAMS`, a `take`/`take-scalar` one takes the next value of `consumes`, any other the next of
  `reads`; for an `indirect` entry the first `reads` value is the function value itself and is skipped. A unit argument is not passed.
  The format stays `ownership-certificate-v1`; a call line without `callee` is a J1 failure. The reader refuses an unknown kind, mode
  or result word.

**Checks** (J1, reported at the call instruction; a table error at the signature, `b- -`):
- *`callee-table`:* the ids are not 0, 1, 2, …; a name is `-` exactly when the kind is `indirect`; `FROM` names a position the entry does
  not have.
- *`call-entry`:* a call line has no `callee`, or names no entry, or the entry is `indirect` and the operation is not `call_indirect`
  (or the other way round); a line that is not a call names a `callee`.
- *`call-arity`:* `consumes` holds a different number of values than `PARAMS` has taking parameters, or `reads` (less the function
  value of an indirect call) a different number than the others. This is `len`, `mode`, `cons` and `rds` of `CallWf`.
- For `program` and `indirect` callees only (A5 judges the others): *`call-scalar`:* the argument of a `*-scalar` parameter is not
  scalar, immortal or a unit value; *`call-result`:* the call's value is `owned` or `emptied` and `RESULT` is not `owned`, it is
  `borrowed` and `RESULT` is not `borrowed`, or it is scalar, immortal, a unit value or absent and `RESULT` is not `scalar` (a stack
  value is never a call's value: J1); *`call-from`:* the value is `borrowed` and an argument at a position of `FROM` that is an owned or
  borrowed value is not among the value's parents (`resBor`).
- The checks run in that order on one call line.

**The link** (one per program, `selka link-certificates PATH` and `certcheck --link PATH`; a program is a directory that holds
certificate files directly, all the units of a build). For each `program` entry of each function, the callee is the function of the
program with that name; the first thing that differs is reported as `DIR CALLER link-reject ENTRY TAG`: `callee-missing` (no such
function), `callee-arity` (a different number of parameters), `callee-param` (a mode that does not match the state of the callee's
`param` line: `take` owned, `read` borrowed, `take-scalar` and `read-scalar` scalar), `callee-result`, `callee-from`. Runtime, `extern`
and marker entries are assumed (A5) and an indirect entry has no name to look up. It spans functions, so no per-function verdict holds
it; the gate action runs it on the whole certificate root and requires no line. In the compiler the entry and the callee's own
`function` and `param` lines are one derivation (`headerOf`), so the link can only fail on a certificate that was changed or built by
something else.

**What goes.** The exporter's `callDisagreement` and `checkCall` (entry 48). **Lean:** `CallWf` splits into the site half these checks
establish from the table and the entry half (the entry equals the callee's signature and certificate, `argScalar` among it), which is
the link. `CallWf.dst` is dropped: a void call has no destination and `RESULT` `scalar`.

## 10. Task groups (package C6)

Until C6 a function with a task group was `unchecked task-group` (A7, stage 2). This section makes the
runtime's task groups part of the certificate: 41 corpus functions (`tests/lang/parallel_groups`,
`parallel_map`, `parallel_wrapper_inputs`) become checked and covered by the theorem. It defines rules
K1 (lent task arguments), K2 (scoped groups and handles) and K3 (parallel map) of §7 as checks of the final
IR. Nothing here weakens a check of J1–J8.

### 10.1 How task groups lower

`build_task.zig` lowers the source forms; `own.zig` rule A and rule B schedule their drops. For
`with parallel.group() as g: … g.submit(fn, ARGS) … t.result()` the final IR has these shapes (a real
certificate, `parallel_groups::fall_through`):

```text
inst %1  call Call reads - consumes - state owned parents - from -        # myl_core_group_open
inst %12 box_make Construct reads %11,%1 consumes - state owned parents - lent %1   # lend %11 to %1
inst %14 record_make Construct reads - consumes %12,%13 state owned parents -       # the environment
inst %15 box_make Construct reads - consumes %14 state owned parents -
inst %18 call Call reads %1,%16,%17 consumes %15 state scalar parents - from -      # submit: the handle is an index
inst %19 call Call reads %1,%18 consumes - state owned parents - from -             # group take: the result box
inst %20 box_take Take reads - consumes %19 state scalar parents -
inst - call Call reads - consumes %1 state none parents - from -                    # group end: the join
inst - drop Drop reads - consumes %11 state none parents -                          # the lender, after the join
```

- A **group** is one runtime block, a managed owner of IR type `box(i64)`: `myl_core_group_open()` returns
  it (owned). A **handle** is an `i64`, the index of the task in the group's task list.
- A **submit** builds the task's environment, a box of a record with a field per argument: a scalar argument
  is stored as itself, every managed argument in a box of its own. A managed argument that is *lent* (a place
  passed to a parameter that is not `own`, or the owner of a view argument) goes in a **lent box**: a
  `box_make` with `flags.lent_box`. A lent box holds the lender's value without owning it and has no layout,
  so destroying the box (alone, or as part of its environment) releases only its shell. Any other managed
  argument is owned by the environment; the thunk takes it out of the box (`myl_core_task_take`, then
  `box_take`) when its parameter is `own`. `myl_core_owned_task_submit_indexed(g, run, env, item)` consumes
  the environment and returns the handle. The environment belongs to the runtime from then on.
- `t.result()` is `myl_core_owned_group_take(g, handle)`, which waits for the task and returns its result box
  (owned), and a `box_take` of it.
- The **join** is `myl_core_owned_group_end(g)`: it waits for every task of the group, then destroys the
  group, so it consumes `g`. The scope of the `with` ends it on every exit edge: falling through, `return`,
  `break`, `continue`, `fail` and `try`. `own.zig` rule A reads the lender at every join of the group its
  lent box names, so the lender's `drop` follows the join; rule B keeps a lent box from consuming its operand.
- `parallel.map` (K3) lowers to a single call, `myl_core_owned_map` / `myl_core_owned_map_with`, that opens
  its own group and joins before it returns; its source and extra arguments are borrowed for the call. The
  instances of `parallel::map_with*` in the standard library still contain a lend (their `args` box is lent to
  a group that is ended after the call), as a task group does.

### 10.2 Classes (§3) and the certificate (§4)

No new state and no new class.
- **Lend.** A `box_make` with `flags.lent_box` is a Construct whose operands are the *lender* `a` (any value
  whose storage the box refers to: owned, borrowed or immortal) and the *group* `b`. It reads both and consumes
  neither: the lender keeps its owner. Its result is `owned` (the box shell, consumed by the environment's
  `record_make`) and its `parents` is `-`. The line carries the extra `lent %G`, with `%G` equal to the second
  value it reads (§4.1).
- **Group calls.** `myl_core_group_open() → owned`; `myl_core_owned_task_submit_indexed(g: read, run: scalar,
  env: consumed, item: scalar) → scalar`; `myl_core_owned_group_take(g: read, index: scalar) → owned` (a box);
  `myl_core_owned_group_end(g: consumed) → none`. They are Call rows: which operands are consumed is their
  signature's `passing`, as for every call (the lines above are what the exporter already writes). The
  checker does not know their names; the contracts of §10.5 are the assumptions that make the table right.

### 10.3 The state and the loans

The group value `g` is an owned value in `L` from `myl_core_group_open` to `myl_core_owned_group_end`. It
*holds loans* in the sense of §5 J4: its entry in `R` lists the roots of every value lent to it on this path.
A lend `box_make(a, g)` adds the roots of `a` to the loans of `g` (an owned `a` is its own root, a borrowed `a`
contributes the roots recorded for it, a view of slot `k` of `c` contributes `(c, k)`, `caller(i)` stays), and
gives its own result the same loans (so that the environment's `record_make` and `box_make`, which inherit the
loans of what they consume, carry them until `submit` consumes the environment). Nothing removes a loan from
`g` but the consumption of `g`: the environment is gone after the submit, but the task may still be running.
A phi that consumes `g` carries its loans (§5, roots follow ownership), and the join of two paths unites them.

### 10.4 Checks

- **J1 (shape).** A lend reads exactly two values, `a` and `%G`; `%G` is the value of `lent`, is owned
  (a group), and is not `a`; it consumes nothing; its state is `owned`; its `parents` is `-`. `lent` appears on
  no other instruction.
- **J3.** Both operands of a lend are usable. A submit, a take and an end read or consume `g`: after the join
  `g` is not in `L`, so a submit, a take or a second end is J3 or J2 (K2: handles never outlive their group).
- **J4 (K1).** While `g` is in `L` no root of its loans may end (`loan-outlives-root`, §5): the lender is
  neither consumed (by a `drop`, a call, an update — a `list_push` of the lender consumes it —, a store) nor
  has the slot a lent view lives in taken. The lender's drop is therefore behind the join. A phi or a
  constructor with an owned result that takes the lender over moves the storage with it, and the loans of
  `g` then name the phi's value or the aggregate (the roots are renamed, §5); a constructor with an `emptied`
  result destroys what it consumes and is J4 (entry 41).
- **J2 (K2).** The group is consumed exactly once on every path that returns: an exit edge without the
  join leaves `g` in `L` at `ret` (J2). `unreachable` needs no join (RC-TRAP-TEARDOWN-1).
- **J2 (`group-join`).** A *group* is an owned value that was the second operand of a lend on some path to
  the point. The validator keeps one "lent-to" bit per owned value: a lend sets it, an owned phi that consumes
  a group moves it to the phi's value, a join takes the OR of the bits of its edges, and a definition or a
  consumption clears it. A group is consumed only by a call whose result state is `none` (the join,
  `myl_core_owned_group_end`) or by an owned phi, which carries the bit. Any other consumption (a constructor,
  an update, a take, a `drop`, a call that returns a value, or a `ret`) is J2, named `group-join`. Without
  this the theorem would have to assume that whatever consumes a group ends it; an update or a call that
  returns an owner could keep the group's storage, and the tasks it covers, alive after the loans on it are no
  longer visible (§9, entry 45).
- **J2 (`abandon-group`).** A group is never abandoned (§5, entry 55): its tasks read the lent cells until the process ends, so
  the loans on them stay in force. A group live on some edges into a trap block and joined on others is then an ordinary join
  mismatch (J2), reported at the predecessor's terminator.
- **K3.** The map calls need no check of their own.

### 10.5 Trusted assumptions (A7 made concrete)

- **A7.1** A lent box has no layout: destroying it, or an environment that holds it, releases the lender's
  storage never (`emit_llvm.zig`, the lent-box layout rule; `core_owned_child_inline` skips the null reference).
- **A7.2** A task reads the storage lent to it and only that, read-only (`mut` arguments are refused by the
  source checker), between its submit and the end of its group; everything else it touches is its own
  environment and its result box.
- **A7.3** `myl_core_owned_task_submit_indexed` consumes the environment, reads the group, and returns the
  task's index; the task may run on another thread at any time after it returns, or inline when the pool is
  not parallel.
- **A7.4** `myl_core_owned_group_take(g, i)` waits for task `i` and returns its result box (owned); the group
  must be open.
- **A7.5** `myl_core_owned_group_end(g)` returns only after every task of the group has finished, and consumes
  `g`. No task of the group runs after it returns.
- **A7.6** `myl_core_group_open()` returns a fresh group, disjoint from every live tree.
- **A7.7** A group is confined to the thread that opened it; a task never submits to, takes from or ends it
  (`R_TASK_ESCAPE` is the runtime backstop of `E_TASK_ESCAPE`).
- **A7.8** `myl_core_owned_map` and `myl_core_owned_map_with` join their tasks before they return and treat
  their source and extra arguments as borrowed for the call.

### 10.6 The Lean model (C6.2)

A group's tree carries the set of cells lent to it. A lend adds the cells its lender gives access to; the
group's end consumes the tree. Destroying (or moving out of the group's reach) a cell that is lent to a
live group is the fault `lentGone` (entry 42): the model does not run the tasks, it forbids the submitter from
destroying what a task may still read. The invariant that proves it records, for each owned value, the roots
that cover the cells lent to it, as it does for the loans of borrowed values; every instruction that could
destroy a covered cell ends a root of a live holder, and J4 refuses that.

### 10.7 What C6.1 (the Zig side) does

- **Exporter** (`ownership_export.zig`): stop refusing lent boxes, `task_group`/`task_handle` types and the
  group calls; write the `lent %G` extra on a lent `box_make`; the `unchecked` field stays `-`.
- **Reader** (`ownership_parse.zig`): read the extra, once per line. The shape of a lend, including a second read that is
  not `%G`, is the validator's to judge (J1), as in the Lean checker (§9, entry 47).
- **Validator** (`validate_ownership.zig`): the J1 shape of a lend (two reads, the lender first and `%G` second, which is
  owned and is not the lender; nothing consumed; an owned box without parents; `lent` only on a `box_make`); the lend adds `roots(a)` to the loans of `%G`
  (the loan machinery of J4 already holds loans for owned values); `loan-outlives-root` applies to a constructor
  with an `emptied` result (the loop over the consumed operands of `outlivesRoot` skips only a constructor
  with an owned result).
- **Fixtures** (`validate_ownership_test.zig`), each with the expected verdict:
  accepted: the 41 corpus functions and a lend of a borrowed parameter; rejected: the lender dropped before the
  group end (J4), the lender consumed by `list_push` before the group end (J4), a lent slot view whose slot is
  taken before the group end (J4), a group never ended (J2), a submit after the group end (J3), a lend onto a
  value that is not owned (J1), a lend that reads three values (J1), a lender consumed by an `emptied`
  constructor while lent (J4).
- Prototype result in the Lean checker, for the validator's author: with the lend rule above the 260 functions
  of the three corpus files accept, and `fall_through` with its `drop %11` moved above the group end is
  `reject J4 b0 14 (loan-outlives-root)`.
