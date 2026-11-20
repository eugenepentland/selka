# Value semantics: internals

Maintainer detail moved out of the user guide [`docs/value-semantics.md`](../value-semantics.md). The headings match the
guide's, so its "How it works" links land here. The paragraphs are the guide's earlier text, unchanged. This folder is not
part of the published site.

## The rules

a binding only if the source lives on. Where a `match name:` statement (or `const x = name else:`) copies a payload and `name` is an owned local that
nothing reads after it, `selka fix` writes `match own name:` and `own payload` itself. A `mut` local assigned more than once, each time from a place
(`mut net = port.name`, then `if ...: net = port.net`) borrows like a `const` of a
place, so a default chosen by a condition needs no copy unless the local is changed
or kept ([B9](ownership-rules.md#b9--const-place-bindings-borrow)). Writing into an unnamed returned temporary is
`E_VALUE_TEMPORARY_WRITE`: bind the result first, then change or store it. An element of a new list, one a call
returns or a literal, needs no copy where a value is taken: `const piece = strings.split(text, sep)[1]` moves the
element out and drops the rest of the list
([B7](ownership-rules.md#b7--no-moving-out-of-a-container)). A read that keeps nothing of a record constructor's field,
`len(Name(text=own t).text)`, checks as it does for a call's result: the record lives to the end of the statement and is
destroyed there with its other fields, and so does a text slice read in the same way, `len(Name(text=own t).text[0:2])`.
Binding the field (`const text = Name(text=own t).text`), or binding, storing or returning its slice, would keep the temporary
and stays refused, with the `copy(...)` that keeps both, or the record bound to a local first. In the same way `maybe().unwrap_or("")`, on the option a
call returns and with a default of its own, gives an owned value where a value is taken; `o.unwrap_or(d)` on a local
option borrows it, and `options.take_or(own o, d)` moves the value out
([R6](ownership-rules.md#r6--borrowed-selections)).

## Taking and exchanging a value

The place is borrowed `mut`, as `append` borrows its list: the marker is required, `own` there is
refused with the repair `mut`, and no other argument takes `mut`. The replacement of `exchange`
moves in under the ordinary rule for a move (B2): a fresh value (a literal, a call result,
`copy(value)`) takes no marker, and a named value takes `own`, as in `exchange(mut holder.items,
own fresh)` and `append(mut rows, own piece)`. A replacement built from the place itself
(`exchange(mut xs, own xs)`) is refused, because the replacement is built before the place is
read and moving the owner leaves nothing to write. An element place is written the way
`rows[i] = value` writes it: the index is checked (`R_LIST_BOUNDS`) before anything moves, and a
live borrow of the list, a loop over it or a running `match mut` arm on it holds the whole list,
so the take is refused while it lasts (`E_SINGLE_OWNER_OVERLAP`). An exchange inside a writer's
argument may write another field of the record that holds the writer's receiver, as
`append(mut builder.done, exchange(mut builder.block, Block()))` does; two elements of one list
stay refused there, even at different literal indices.

## Consuming a list in a loop

The elements come out in order. One the body does not move is dropped at the end of its
iteration, and a `break`, `return` or `fail` drops the ones the loop has not reached. The list's
name is moved from the loop on, so a use of it inside the body or after the loop is
`E_SINGLE_OWNER_MOVED`; a `mut` local can be assigned a new list afterwards. A `mut` or borrowed
parameter, a field (`own h.items`), a `const` binding of a place, a dictionary and two names
(`for i, x in own xs:`) are refused, most as `E_ITERATION` with the line to write instead:
`mut items = take(mut values)` for a `mut` parameter's list, `mut items = copy(values)` for a
borrowed one. A call whose result is lent by its argument (declared `from` it) is refused as
`E_SINGLE_OWNER_BORROW`, which says so and offers `for x in own copy(first(xss)):`. A list literal
cannot follow `own` here: `own [0]` already reads element 0 of a local named `own`.

## Setting a list aside for a loop

- **The place** is a field of a `mut` local, a `mut` parameter or a `match mut` binding, through list
  elements (`detach groups[at].items`); each index is a number or a name the loop cannot change. A
  dictionary value, a call, a plain value, two loop names, and a place that an enclosing `detach` loop has
  set aside (or one inside it) are `E_ITERATION`. The loop variable is read-only, as in any `for` loop.
- **What leaves.** The value of a `return` or `fail` is computed first, then the list is put back, then
  the value leaves; so a `return len(r.items)` inside the loop sees the empty list. A value that borrows
  the loop variable or the list (`return x`, `return x.name`) is `E_SINGLE_OWNER_OVERLAP`: return
  `copy(...)` of it, or a position, and read the element after the loop.
- **`try`** in the loop is a declaration's value or a statement of its own (`const value = try f()`,
  `try f()`); `x = try f()`, `return try f()` and a `try` in a call's argument are `E_TRY_POSITION`. In a
  function that returns an optional, write `const value = f() else: return None` instead of `try`.
  `on fail:` clauses run before the list is put back.
- **A place written while set aside.** If the body, or a function it calls, puts a new list in the place
  (`append(mut r.items, x)` through `r`), putting the loop's list back would lose one of the two, so the
  put-back traps `R_ASSERT` with a message that names the place and the loop's line. Collect new elements
  in a list of their own and add them after the loop.

## How it is implemented

Every dynamic allocation has one owner. Marked stores and owned returns transfer
that owner; read-only calls borrow it, and `mut` calls borrow exclusively. The
compiler places direct destruction on every path after an owner's last use,
including early returns and checked error propagation. It rejects a later use
of a moved value, an escaping borrow or overlapping mutation. There is no
copy-on-write fallback.

A release build can eliminate an explicit copy when the source dies and the
result can take over its storage. This preserves the program's values while
reducing allocation. `selka build --release --stats`, `selka dump-ir` and
`selka cost` expose static compiler decisions; runtime counters describe
executed allocations, copies and destruction (`docs/tooling/ownership.md`).
