# Ownership analysis

The compiler runs one ownership analysis over every function it lowers
(`OWNERSHIP-ANALYSIS-1`). It answers, without assuming any particular runtime,
what value semantics costs the function: which transfers of a value can
hand it over (a *move*), which can share it because neither side is written
while both are read (a *borrow*), and which would need a real *copy*; and, for
every in-place write of a list, dictionary, set or byte buffer, where a
copy-on-write check goes and which loop entry can hoist it. It is
the shared analysis developed for stage 2 of
[D9](../adr/D9-value-semantics-then-rc.md): the current collector uses it to
skip aggregate copies (`QBE-MOVE-ELIDE-1`) and root records
(`QBE-BORROW-ROOT-1`), see [Performance](../performance.md#records-are-values-not-copies).

The analysis reads the same bytecode and the same liveness solution the native
emitter plans its garbage-collection roots on, so what it prints is what codegen
acts on. It never refuses a program: a fact it cannot prove is answered the
conservative way (`owned`, `copy`, not hoisted).

## Explain ownership

`mylang check FILE.my --explain-ownership=OUT.jsonl` checks the program as
usual and also writes the analysis of every lowered function to `OUT.jsonl`, one
JSON object per line (`OWNERSHIP-EXPLAIN-1`):

```console
$ cat fill.my
def fill(n: int) -> list[int]:
    out: list[int] = []
    for i in range(n):
        out.append(i)
    return out


def main() -> int:
    items = fill(3)
    alias = items
    return len(alias) + len(items)
$ mylang check fill.my --explain-ownership=fill.jsonl
$ head -n 1 fill.jsonl
{"function":"fill","locals":[{"index":1,"name":"<collection>","role":"owned"},{"index":2,"name":"out","role":"owned"}],"transfers":[{"pc":2,"kind":"assign","target":1,"source":{"origin":"fresh"},"class":"move"},{"pc":4,"kind":"assign","target":2,"source":{"origin":"local","local":1,"part":"whole"},"class":"move"},{"pc":22,"kind":"return","source":{"origin":"local","local":2,"part":"whole"},"class":"move"}],"cow":[{"pc":14,"local":2,"via":2,"elements":false,"needed":true,"hoisted":9}],"moves":[3,21]}
```

Each line carries:

| key | meaning |
|---|---|
| `function` | the lowered function's name |
| `locals` | every non-scalar local: `index`, `name`, `role` (`owned`, `param`, `mut_param`, `borrowed`, `path`) and, for `borrowed` and `path`, the `parent` local it names |
| `transfers` | every transfer of a non-scalar value: `pc`, `kind` (`assign`, `binding`, `argument`, `element`, `dict_value`, `field`, `construct`, `update`, `return`), `target` for an assignment or binding, `source` (`origin` `fresh`, `local` or `unknown`, with the `local` and the `part` read: `whole`, `element`, `field`) and `class` (`move`, `borrow`, `copy`) |
| `cow` | every copy-on-write check site: `pc`, the `local` whose payload must be unique, the local the instruction names (`via`), whether the elements must be unique too (`elements`), whether a check is `needed` at all (a `mut` parameter's caller guarantees it) and the loop header it is `hoisted` to, or `null` |
| `moves` | the pcs of the loads whose value moves out of their local |

The `pc`s are the ones `mylang dump-bytecode` prints, so the two outputs line up.
In the example the append's check moves to the loop header at pc 9: nothing in
the loop can make `out` shared, and `out` moves out of the function at its
return. `alias = items` in `main` is a `borrow`, because
neither list is written afterwards.

The report is an inspection surface for the compiler's own development — it
validates the analysis against the E2b prototype's decisions and against
hand-written cases — not a stable interface. Host and C-ABI functions have no
body and are skipped.
