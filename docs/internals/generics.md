# Generics: how it works

Implementation detail moved out of `docs/generics.md`. The guide keeps the user-visible rule.

## Generic functions

Ownership is judged at the declaration. `selka check` (a file, a module or a
project, with `check-module`, `check-project` and `selka fix` alike) checks the body
of every generic function of the program, those a program already instantiates
included, through one instance per kind of type argument the function's bounds
admit: a scalar (`int`), a text (`str`), a record with a managed field and a list
(`int[]`). Each type parameter is tried with each managed kind while
the others are `int`, and, when there are two or more, every parameter with the same
managed kind; mixed managed kinds (`str` beside `int[]`) are not tried, and a real
instance of them is still judged where a program makes it. A body that one of these
kinds refuses is an error at the declaration, reported once, naming the type
parameter and the kinds, with the place in the body as a note: `first[T](xs: T[]) -> T`
that returns `xs[0]` is refused when `T` is a text, a record or a list, and `selka
fix` writes the certain repair, ` from xs` on the result or `copy(...)` on a stored
value (a `copy` only when every type parameter admits one). A result an instance's
view sources cannot lend (`E_BORROW_SOURCE`) is still reported at the call, naming
the instance. A function whose parameter has a structural requirement is not tried
with stand-ins: its instances are judged where programs make them. A build
(`build`, `run`, `test`) makes no stand-in instance; it judges the instances its
program makes and reports a refusal inside one at the template's declaration in the
same words.

The standard library's generic functions are judged once per compiler, not in each
`check`: the library is embedded in the compiler, and a gate test runs
`selka template-stand-ins --standard-library`, which tries every library template
with every stand-in above (and more), and fails when one is refused. A judgment that
passed is kept with the ownership proofs of the template's module, under the
template's stable key, the digest of the declarations its body and signature name
(a callee's signature and `from` contract, a record's fields, the compiler's
identity) folded with the rule's own version, and the digest of the declaration's
tokens; while all three are what this check computes, the template is not judged
again, so a comment or a line shift keeps it and a changed token, bound, callee
contract or named record judges it again. `SELKA_ENGINE_VERIFY=N` judges one held
template in N anyway.
