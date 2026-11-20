# Surface simplification: the decisions and proposals of 13–14 October 2026

This is the source text for the language waves, copied from the design review
"Selka: how it works and why" (Claude Docs,
<https://claude.ai/artifact/Dm5CLnEbW7ssrDPbjfu9C7>, sections 3, 4, 5 and 7.1–7.2,
revision 51). The review is the authority; this copy exists so that agents
without access to it work from the same words. Proposal numbers are the
review's. The execution plan for the first wave is
[language wave 1](../audits/language-wave1-10-agent-plan-2026-10-14.md).

## Decisions taken on 13 October 2026

**User types keep no methods.** The question a reviewer asks of every line is
what it can change, and with free functions the answer is on the line:
`translate(mut points, 5)` changes `points`, and a line without `mut` changes
nothing. A receiver call moves that answer off the line into the callee's
declaration. Free functions also keep one name one function, found by text
search, because there is no overloading. The cost is qualification and no
chaining, `money.add(a, b)` rather than `a.add(b)`. (Already true of the
reviewed revision.)

**Scalar domains are removed.** A domain was a class-shaped third kind of type:
a wrapper over a scalar with a body of functions and construction confined by
`wrap` and `unwrap`. Its replacement is a one-field record guarded by an
invariant: nominal identity comes from the record, validity is enforced at
every construction and write, the cost is the integer's because the optimizer
flattens a one-field record, and the operations are ordinary module functions.
The `op(...)` structural requirement and named constraints, which existed only
because domains had type-owned operations, go with them; generic code takes an
operation as a function value, as the standard library's sort already does.
The migration is mechanical: `wrap[X](v)` becomes `X(value=v)`, `unwrap(x)`
becomes `x.value`, and `X.f(a)` becomes `f(a)`. The one detail to settle is
JSON: a domain serializes as its bare number, so a record whose only field
carries the value should probably do the same.

**The inferred effect system is deleted; the parameter list is the contract.**
To print, a function must hold a `Stream`; to read a file, a `Filesystem`; to
call C, a `Host`; and it can hold one only by being handed one. A capability
parameter the body never uses is an error. What follows:

- Mutation is already declared: a function's mutation footprint is exactly its
  `mut` parameter set, and a write through a parameter not marked `mut` is a
  local error.
- Allocation becomes a per-function build-time contract, `@noalloc`, checked on
  the ownership-expanded Core.
- A callback that needs authority takes it as a parameter,
  `func(Stream, int) -> int`, so a callback's ceiling is its parameter list.
- A contract condition is pure by a syntactic rule: it may not mention a
  capability parameter, a `mut` marker or a receiver update.
- An `extern func` needs only its `host: Host` parameter.
- A function with no capability and no `mut` parameters is pure apart from
  allocation, which is the definition constant evaluation and contracts use.

Deleted with the effect system: the nine inferred effect bits, `effects(...)`
and `noio`, `E_EFFECT_BOUND` with its call-path witness, and the derived-effects
diagnostics. A violation becomes a type error at the exact operation (no
`Filesystem` in scope here). Interface hashes stop depending on facts inferred
from bodies, and about two thousand lines of front end go.

## Proposals on the surface (section 7.1)

None is implemented. All serve one goal: a line should tell its reader what it
does, what it changes and what it costs. The last five apply that rule to cost
directly: wherever the short spelling was the slow one, the proposal swaps which
spelling is short.

1. **No methods on built-in types either.** `text.split()`, `xs.append(x)`,
   `counts.get(k, 0)` and `out.print(a)` become `strings.split(text)`,
   `append(mut xs, x)`, `dicts.get(counts, k, 0)`, `print(out, a)`; names live in
   modules (`strings`, `dicts`, `lists`). `b.decode()` becomes
   `strings.decode(b)`, declared `fails` for invalid UTF-8, and `s.encode()`
   becomes `strings.encode(s)`. The rejection diagnostic names the replacement, so
   `selka fix` migrates code mechanically.
2. **Sequencing without methods.** Named temporaries are the one way to
   sequence; a lint caps nesting at two calls in one expression and names the
   temporary to introduce; `strings`, `lists` and `dicts` get the words Go's
   packages have (`strings.words(text)` for trim-and-split). A pipe operator was
   considered and dropped.
3. **Field punning.** `WordCount(word, count)` when locals named `word` and
   `count` are in scope, short for `word=word, count=count`, and the same in
   patterns: `case rect(width, height)`. The names must match the fields.
4. **Empty literals keep their annotation (withdrawn).** `mut result:
   WordCount[] = []` stays as it is today.
5. **Comprehensions are removed**, together with the generator argument to
   `sum`, `any`, `all`, `min`, `max` and `sorted`. The statement form stays: a
   `mut` accumulator, a `for` loop and an `append` or `+=` per element.
6. **Unqualified case names when the type is known.** `case circle(radius)`
   instead of `case Shape.circle(radius=r)`, and `rect(width=2.0, height=3.0)`
   where a `Shape` is expected.
7. **Public signatures name their dictionaries.** A bare `dict[K, V]` or
   `tuple[...]` in a public parameter or result must be named through a
   transparent alias (`type WordCounts = dict[str, int]`) or a record whose field
   name documents the key; the compiler reports a bare type with a fix that
   introduces the alias.
8. **`match` on scalars and on more than one value.** Arms are literals or
   compile-time constants (`case ord("("):`), `|` joins alternatives, `case _` is
   required; `match a, b:` with pair patterns, exhaustive over the product and
   ending in `case _`.
9. **Two lints with fixes for loose parameter groups.** `W_PARAMETER_COUNT`
   (more than five parameters, not counting capabilities, must take a record) and
   `W_DATA_CLUMP` (three or more `mut` locals always passed together to one call).
10. **Lambdas are removed.** Sort keys and callbacks become named top-level
    functions, `sorted(words, key=length)` with `func length(w: str) -> int`.
    Decision record D5, non-capturing lambdas, is superseded.
11. **No control flow inside an expression.** The conditional expression
    (`a if p else b`, also `if p then a else b`) and the `match` expression with
    `yield` arms are removed; an `if` or `match` statement assigns a named result
    instead, so every branch has a line of its own in a diff.
12. **Negative indexes are removed.** `xs[-1]` and `xs[-2:]` count from the end
    today, so `xs[i - 1]` with `i == 0` silently reads the last element. A
    negative index or slice bound traps; the spellings are `xs[len(xs) - 1]` or
    `lists.last(xs)`.
13. **Tuples are removed.** A function that returns two things returns a
    record, `return Split(head, rest)` with punning; the two-variable `for` over
    `enumerate`, `zip` and `dicts.items` stays as a loop form that never
    materialises a tuple. The swap idiom goes with it.
14. **Sequence repetition is removed.** `"-" * 3`, `[0] * n` and `*=` on a list
    give `*` a second meaning; `strings.repeat("-", 3)` and `lists.filled(n, 0)`
    say what happens.
15. **`in` on a list is removed.** `x in xs` is a linear scan that reads like a
    keyed lookup; `lists.contains(xs, x)` shows the cost, and `in` keeps meaning a
    hashed lookup on a dictionary or set.
16. **`str` is bytes underneath.** `len(s)` is the byte length, `s[i]` a byte as
    `int`, `s[a:b]` slices by byte offset and traps inside a multi-byte scalar;
    iterating a `str` directly is an error whose fix names `strings.chars(s)` or
    `strings.bytes(s)`; f-string padding keeps counting scalars.
17. **A slice is a view.** `xs[a:b]` and `s[a:b]` become immutable reads of the
    source, never stored, returned only under the one-parameter rule;
    `copy(xs[a:b])` is the owned list; `E_SLICE_ESCAPES` with a `copy` fix; Core
    gains a pointer-and-length representation for borrowed ranges.
18. **One lookup per dictionary operation.** `dicts.find(d, k) -> V?`,
    `dicts.add(mut d, k, delta)`, `dicts.append_to(mut d, k, item)`, each one
    probe; the lint `W_DOUBLE_LOOKUP` carries the fixes.
19. **Counting loops become `range` loops.** The lint `W_COUNTING_WHILE` rewrites
    `mut i = 0` / `while i < n:` / `i += 1` to `for i in range(start, bound):` only
    when the rewrite is exact.
20. **Output is buffered.** `write` buffers like `print`; `out` flushes at exit,
    on `flush(out)` and before any write to `err`; `err` stays unbuffered; a trap
    flushes `out` before printing its stack.

A further lint: an enum with one payload case and one empty case is usually a
`T?` or a list that may be empty.

## Working in parallel (section 7.2), six tooling proposals

1. **A module can be a directory**: `import shop.billing` resolves to
   `shop/billing.selka` or every `.selka` file under `shop/billing/`, one namespace.
2. **Merging at declaration granularity**: a `selka merge` git driver treats a
   module as a set of declarations keyed by name.
3. **Renames and moves the fixer carries**: `@renamed_from("old_name")` and
   `@moved_from("old.module")`.
4. **Holes that run**: under `--allow-holes` a `todo[T]()` traps at run time; the
   gate refuses holes on the integration branch; `fix` inserts stub arms for a new
   enum case.
5. **Tests and examples beside the code**, one test file per module; a public
   function with a hole carries an `@ensures` or a docstring example.
6. **Diff-stable formatting**: one field or argument per line with a trailing
   comma in multi-line constructors, sorted imports.

## Waves

| Wave | Contents | When |
| --- | --- | --- |
| 1 | Decisions (domains, effect system); proposals 5, 10, 11, 12, 13, 14, 15 | now, beside the caching follow-up |
| 2 | Proposals 1, 2, 3, 6, 7, 8, 9, 18, 19, 20 | after wave 1 |
| 3 | Proposals 16 and 17, inside the ownership program (borrowed ranges in Core) | with ownership as the default |
| tooling | Section 7.2, items 2 and 6 first | before wave 2, which touches every file |
