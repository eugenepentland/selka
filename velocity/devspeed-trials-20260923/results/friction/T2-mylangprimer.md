# FRICTION.md — building `calc` in mylang

Overall this went smoothly: the PRIMER covered almost everything I needed, `mylang
check` found one real error on the first pass, and all 16 unit tests plus every
manual error-path test I tried passed on the first build. Below is the honest
blow-by-blow.

## Points of friction

### 1. `E_PRIVATE_INTERFACE` from over-using `public` (1 attempt, ~1 minute)

I marked every helper function (`tokenize`, `parse_stmt`, `eval_expr`, ...) `public`
out of habit, thinking it was needed for `mylang test` to see them. `mylang check`
immediately rejected it:

```
calc.my:64:47: error[E_PRIVATE_INTERFACE]: exported interface exposes an unexported type
  public def tokenize(line: str) -> Result[list[Token], CalcError]:
```

Fix was mechanical — mark `Token`, `CalcError`, `Expr`, `Stmt`, etc. `public` too — and
the error message's "note: related module/import declaration" pointer made the fix
obvious, so this cost almost nothing. But on reflection the `public` markers on the
helper functions were unnecessary in the first place: PRIMER.md says tests in the
*same file* as the code see everything regardless of visibility ("in the same file as
the code or in `name_test.my` that does `import name` (then only `public`
declarations of `name` are visible)"). Only the `test_*` functions actually needed
`public`. The PRIMER's wording is correct, I just didn't fully internalize the
same-file exception before typing `public` on everything — but the PRIMER doesn't
warn that a `public` function/type pair has to agree (a public function can't expose
a private type in its signature), which is the rule that actually fired here. A
one-line note on that interaction would have prevented the reflex entirely.

### 2. `W_UNUSED_BINDING` warnings on discarded tuple positions (instant, cosmetic)

`expr, _pos = pair` triggered "binding is never read" three times. Renaming the
unused half of the tuple destructure to plain `_` (which PRIMER.md and
`docs/tuples.md` both mention as the no-op discard name) silenced it. Not really
friction, just a reminder that `_name` isn't itself special — only literal `_` is.

### 3. Needed the fuller docs for the recursive-AST idiom (~5 minutes of reading)

PRIMER.md's only example of a self-referential type is the simple linked-list case
(`class Node: value: int; next: Option[Node]`). My `Expr` type needed a sum type
(number / name / negation / binary-op) where two of the cases recurse into `Expr`
itself, and PRIMER.md doesn't show that combination. Rather than guess and iterate
against the compiler, I read `docs/records-and-unions.md`'s "Recursive payloads"
section, which turned out to give almost exactly the shape I needed:

```mylang
class Binary:
    left: Expr
    right: Expr

union Expr:
    number: int,
    binary: Binary
```

with the accompanying rule "Declare the class before the union so the union's
payload names an already-declared type; the class may name the union it is
eventually a case of." I mirrored this directly for `Neg`/`BinOpNode`/`Expr` and it
compiled without a single recursion-related error. The documentation here was
accurate and helpful, not misleading — it just wasn't reachable from the one-page
primer, so I had to go find it. This is the closest thing to a real time sink in the
whole exercise, and it was a documentation-lookup cost, not a compiler-error cost.

## Everything else that "just worked" from the PRIMER alone

`divtrunc`/`remtrunc` matching the task's required C-style truncation exactly,
`mut` on both the parameter and call site, `s[i]`/`.isdigit()`/`.isalpha()`/`ord()`
for hand-rolled tokenizing, tuple returns (`Result[tuple[Expr, int], CalcError]`)
and `x, y = f()?` for threading a parser position without closures or mutable
`int` out-parameters, `?` propagation through same-error-type call chains,
`text.splitlines()` for line numbering (it even folded `\r\n` into one line break,
which I hadn't planned for but needed no special-casing), `k in dict` for the
undefined-variable check, and `f"..."` for building the exact `error: line L col C:
MESSAGE` format. None of these needed a second guess.

## Ranked changes that would have saved the most time

1. **Document the public-function/public-type coupling rule** (`E_PRIVATE_INTERFACE`)
   next to the existing "only `public` declarations are visible across files" note in
   the PRIMER, or in `docs/modules.md`. It's a natural mistake for anyone reflexively
   marking helpers public, and the fix is invisible until the compiler names it.
2. **Add one AST/sum-type-recursion example to PRIMER.md itself** — the exact snippet
   from `docs/records-and-unions.md`'s "Recursive payloads" section would fit in the
   existing "Types and declarations" block and would have saved the trip to the full
   docs entirely; a one-page primer that promises "the differences that matter are all
   on this page" is one recursive-union example short of that promise for anyone
   writing a parser/interpreter, which is a very common first project in a new
   language.
3. **Nothing else rose to the level of a real change** — the third-ranked item is
   minor: have the formatter/linter suggest `_` by name in the `W_UNUSED_BINDING`
   message the way it does for other fixes (the message already names the pattern
   `_ =` for a different case; doing the same for tuple-destructure targets would save
   a lookup for someone who hasn't seen `docs/tuples.md` yet).

If nothing else needs saying: this was a genuinely fast build for a from-scratch
language — one real compiler error, three cosmetic warnings, one documentation
lookup, and no incorrect-semantics bugs found by my own tests or manual probing of
every error path in the spec (unexpected character, expected expression at EOF,
expected `')'`, unexpected token in all its forms, undefined variable, division and
modulo by zero, blank/comment-line handling, tabs between tokens, CRLF input,
argument-count and unreadable-file errors, and a 20,000-line performance run at
0.069s).
