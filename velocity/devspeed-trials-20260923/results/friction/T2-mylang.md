# Friction log — calc in mylang

Overall this went smoothly: the ~600-line `calc.my` type-checked clean on the
*first* `mylang check` attempt, and the native build worked on the first
`mylang build` attempt too. The documentation (`docs/python-syntax.md`,
`docs/statements.md`, `docs/records-and-unions.md`, `docs/results-and-options.md`,
`docs/tuples.md`, `docs/io.md`, `docs/text.md`, `docs/integer-operations.md`)
was thorough enough, with enough runnable `# doc: expect N` examples, that I
could get the syntax right by pattern-matching against worked examples
instead of guessing against the compiler. Two real stumbles below, plus one
thing that cost reading time rather than compiler attempts.

## 1. `mylang test` silently requires a project the other commands don't

**What I tried:** I wrote `calc.my` as a headerless single-file script (no
`module` line), exactly as `docs/python-syntax.md` and `docs/modules.md`
describe ("A file with no module header is still checked and run as one
standalone unit"). `mylang check calc.my` and `mylang build calc.my -o prog`
both worked perfectly against that headerless file.

**What the tool said:** `mylang test calc.my` rejected it with:

```
calc.my:7:1: error[E_MODULE_HEADER]: file must begin with a module declaration
```

This code name suggests the same "add a `module` line" fix documented for
`import`, but nothing in `docs/experiments/guest-tests.md` (the page named for
the test workflow) mentions that `test` — alone among `check`/`build`/`run`/
`test` — refuses a headerless entry. The one hint, in retrospect, is the
single word "project" in "The command checks *the project* and discovers
exported `test_` functions in its reachable schema," which reads as
incidental phrasing, not a documented divergence from `check`/`build`/`run`.

**How I resolved it:** Added `module calc` at the top of the file. That then
hit a second, related surprise: `E_MODULE_NAME: declared module name does not
match its requested path` — the module name has to equal the file's own
basename (`calc.my` → `module calc`), which I confirmed by trial in a scratch
copy since `docs/modules.md`'s worked examples always name the module and the
file consistently (`module units` / `units.my`) without ever stating that
match is required rather than a convention. Once both were satisfied, `mylang
test calc.my` discovered and ran all 20 `@test` functions cleanly.

**Cost:** ~3 extra compiler invocations and one scratch-directory experiment,
maybe 10 minutes: cheap in isolation, but this was the single biggest time
sink because the first three commands I tried (`check`, `build`, and reading
the whole language guide) all reinforced the same assumption — "headerless
scripts are a full first-class citizen" — that `test` then broke, with an
error code that reads like a syntax problem rather than a command-specific
policy.

## 2. `int` in mylang: `/` is not integer division

**What I expected:** given the task's own C semantics (`-7 / 2` is `-3`), I
expected `/` and `%` on two `int` values to already be the operators I
needed, or at worst floor division like Python's `//`/`%`.

**What the docs actually say, once found:** `docs/python-syntax.md`'s float
section states in passing that "`/` produces a float; `//` rounds the
quotient down and `%` follows that quotient" — i.e. plain `/` on two `int`s
is float division, not integer division at all, which is easy to miss since
it's introduced while discussing `float` literals rather than in an operator
reference for `int`. The actual C-truncating operators
(`divtrunc`/`remtrunc`) are documented on a completely different page,
`docs/integer-operations.md`, under "Truncating division," with the worked
example (`-85 // 2 != -43`, `remtrunc(-85, 2) != -1`) that let me confirm the
rounding direction without writing throwaway code.

**How I resolved it:** cross-referenced both pages before writing any
evaluator code, then used `divtrunc`/`remtrunc` directly for the `/`/`%` AST
cases; this cost reading time, not compiler attempts (the eventual test
`test_eval_negative_div_mod_c_semantics` passed first try).

**Cost:** no failed builds, but a good five minutes of hopping between two
pages to make sure `/` on two `int`s wasn't a trap waiting in `calc.my`
(it would have silently produced a `float`-typed expression tree if I'd
written a naive `left / right` and let inference paper over it — except that
can't actually happen here, because `int / int` typing as `float` would have
been caught at `mylang check` time as a type mismatch against my `int`
evaluator; the real risk was wasted implementation time, not a silent bug).

## 3. (minor, no cost) One rough edge in language design worth flagging anyway

The one editor-visible papercut, unrelated to being blocked: `mut` on a
collection parameter is enforced in *both* directions
(`E_MUTATION_MARKER` fires for a caller-visible mutation missing `mut`, but
also for a `mut` parameter a function body never actually writes). I had
first written `try_eval_line`'s `variables` parameter as `mut dict[str, int]`
by copy-pasting from a sibling function, and the checker caught that this
particular helper only reads the dictionary. This is a *good* diagnostic —
precise, one-line fix suggested inline — not a friction point; noting it only
because it's the only compiler rejection I hit in the whole task that wasn't
the module-header issue above.

## Ranked: three changes that would have saved the most time

1. **Make `mylang test` accept a headerless single-file entry exactly as
   `check`/`build`/`run` do** (or, if that's structurally impossible, say so
   loudly and early in `docs/experiments/guest-tests.md`'s first paragraph —
   "unlike `check`/`build`/`run`, `test` always requires a project entry with
   a `module NAME` header matching the file's basename" — right next to the
   `mylang test examples/testing/main.my` command block). This is the one
   place the four sibling commands disagree, and it's the most-used command
   for exactly the workflow this task asked for (write code, then write
   tests for it in the same file).
2. **State `int`'s `/` and `%` behavior in one place a systems-language
   reader would look first** — a plain operator table in
   `docs/current-language.md` or at the top of `docs/integer-operations.md`:
   "`/` and `%` between two `int`s are float division and its remainder,
   *not* C truncation; use `divtrunc`/`remtrunc` for C truncation or `//`/`%`
   for floor division." Both pieces of truth exist today, just on two pages
   that don't cross-link to each other from the angle a reader hits first
   (the float section of the Python-syntax guide).
3. **State the module-name-matches-filename rule as a rule, not an example
   convention**, in `docs/modules.md`'s "Disk modules" section — one
   sentence ("the declared name after `module` must equal the file's own
   basename") next to where it already says imports turn a dotted name into
   a path.
