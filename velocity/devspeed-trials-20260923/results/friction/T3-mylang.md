# FRICTION.md — notes from implementing `route` in mylang

Overall this went smoothly: one working draft, four small compiler-driven fixes,
done. I had never used the language before this task. Total elapsed effort was
dominated by reading docs up front, not by fighting the compiler.

## Points where I was blocked, surprised, or slowed down

### 1. Empty list literal inside `.append(...)` is not inferred from context

**Tried:** `adjacency.append([])` to grow a `list[list[Edge]]` with a fresh empty
inner list, mirroring the record-field example in `python-syntax.md` (`Node(value=2,
children=[])`).

**Compiler said:**
```
route.my:48:30: error[E_LIST_INFERENCE]: empty list requires an expected List type
              adjacency.append([])
                               ^
```

**Fix:** bind the empty list to an explicitly annotated local first, then append the
local: `empty_edges: list[Edge] = []` then `adjacency.append(empty_edges)`. One attempt
to hit the error, one attempt to fix it.

**Docs verdict:** misleading by omission. `managed-memory.md` and `python-syntax.md`
both say `[]` "takes its type from an annotation, field, parameter, or return type,"
and the very next example in `python-syntax.md` shows exactly this pattern working
as a *record field* argument (`children=[]`). Neither page says that a call
argument to a built-in mutating method (`.append`, `.insert`, etc.) is a narrower
context that doesn't count. I'd read "parameter" as covering this case and it
doesn't. A one-line caveat next to that sentence ("a call argument to an intrinsic
list/dict method is not an inference context; bind an annotated local first") would
have saved the round trip.

### 2. `mylang test` rejects a headerless file that `check`/`build`/`run` accept

**Tried:** `mylang test route.my` on the same headerless single-file program that
`mylang check route.my` and `mylang build route.my -o prog` had just accepted.

**Compiler said:**
```
route.my:1:1: error[E_MODULE_HEADER]: file must begin with a module declaration
  record Edge:
  ^
```

**Fix:** add `module route` as the first line. Since I had no imports beyond the
language's own builtins, this cost nothing else. One attempt to hit the error, one
attempt to fix it.

**Docs verdict:** silent/misleading. `modules.md` describes the headerless-script
exemption in detail but never says it's narrower than `run`/`check`/`build` — I read
"a file with no module header is still checked and run as one standalone unit" as
covering every command. `tooling/guest-tests.md` separately explains that a
`*_test.my`-named file gets an *automatic* synthetic header, which implied to me
(wrongly) that headerless was the general case and the auto-header was only extra
convenience for the naming convention. It never states the actual rule: `mylang
test` requires an explicit `module` header on every entry unless the filename ends
in `_test.my`. Stating that rule plainly next to the `E_MODULE_HEADER` explanation,
or having `test` accept the same headerless form the other commands do, would have
avoided this.

### 3. Uncertainty about `mut` parameters and method-call receivers (self-resolved, no compiler round trip)

`managed-memory.md` states list/dict mutating methods "currently use a named local
or parameter as their receiver" — which reads as if `adjacency[from_index].append(x)`
(an indexed expression as receiver) might be rejected — while a different paragraph
in the same file says indexed reads/writes accept "arbitrary expressions." I could
not find a worked example either confirming or denying method calls on an indexed
receiver, so I played it safe and always bound the target to a named local first
(`from_list = adjacency[from_index]; from_list.append(...)`). This cost design time,
not compiler attempts, and the resulting code is arguably clearer anyway. I never
went back to test whether the direct indexed-receiver form would actually have
worked, so I can't say whether this caution was necessary or just belt-and-suspenders. Related: the `mut`
parameter/effects machinery (`functions.md`, `effects.md`) is thorough and
consistent once read, but it's spread across two long pages with many
worked examples of what's *rejected*; a single compact "mutation cheat sheet" (when
do I need `mut` on a parameter, when do I need `effects(mutation)`, when is neither
needed for a purely local list) would have let me skip a fair amount of
cross-referencing. I avoided the whole question by never mutating anything across a
function boundary — all mutation happens on locals inside the function that owns
them — which the docs do support cleanly (`managed-memory.md`'s "fresh local
mutation" section), but I only found that reassurance by reading further than I
expected to need to.

### Everything else was smooth

`fs.read_text`, `Result`/`Option` matching, `text.splitlines()`, `text.split()`
(whitespace form), `str.isdigit()`, f-strings, list comprehensions over `range()`,
negative list indexing, and `" -> ".join(...)` all worked exactly as documented on
the first try. `mylang build --report` gave a clear, immediately useful JSON
timing/reuse receipt. `mylang test` discovered the `test_*` functions with zero
configuration once the module header was in place, and its pass/fail output was
unambiguous. Performance was a non-issue: a 50,000-node/200,000-edge graph (built
with a hand-rolled binary heap over parallel `list[int]` arrays, since the standard
library has no heap/priority-queue primitive) ran in about 0.13 s wall time,
comfortably inside the 10-second budget, with no tuning needed.

## Ranked changes that would have saved the most time

1. **Make `mylang test`'s entry-file rules match `run`/`check`/`build`.** Requiring
   an explicit `module` header only for `test` (unless the file happens to be named
   `*_test.my`) is a surprising, undocumented asymmetry between otherwise-identical
   commands. Either accept the same headerless form everywhere, or state the
   divergence explicitly in one place both `modules.md` and `guest-tests.md` link to.
2. **Document the actual boundary of empty-list-literal inference.** "Takes its
   type from ... a parameter" needs a carve-out: it applies to a *declared*
   function/record-constructor parameter, not to a call argument of a built-in
   mutating collection method. This is a one-sentence fix with an outsized payoff,
   since appending an empty inner list to build any list-of-list/adjacency-style
   structure is an extremely common pattern.
3. **Add one compact reference page for the mutation/`mut`/`effects(mutation)`
   system**, cross-linking `functions.md` and `effects.md`'s existing (good, but
   scattered) examples. A single table of "receiver shape -> do you need `mut`? do
   you need `effects(mutation)`?" would let a newcomer skip the exploratory reading
   I did out of caution rather than necessity.
