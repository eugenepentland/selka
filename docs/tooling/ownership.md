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
usual and also writes the analysis of every lowered function, including
imported functions in a project, to `OUT.jsonl`, one JSON object per line
(`OWNERSHIP-EXPLAIN-1`):

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
{"function":"fill","return_origin":{"kind":"fresh","params":[]},"borrow_origin":{"kind":"fresh","params":[]},"locals":[{"index":1,"name":"<collection>","role":"owned"},{"index":2,"name":"out","role":"owned"}],"transfers":[{"pc":2,"kind":"assign","target":1,"source":{"origin":"fresh"},"class":"move"},{"pc":4,"kind":"assign","target":2,"source":{"origin":"local","local":1,"part":"whole"},"class":"move"},{"pc":22,"kind":"return","source":{"origin":"local","local":2,"part":"whole"},"class":"move"}],"cow":[{"pc":14,"local":2,"via":2,"elements":false,"needed":true,"hoisted":9}],"moves":[3,21]}
```

Each line carries:

| key | meaning |
|---|---|
| `function` | the lowered function's name |
| `return_origin` | the checker's logical return provenance: `fresh`, `params` with zero-based parameter positions, or `unknown` |
| `borrow_origin` | the physical provenance of retained backing, including immutable bytes in a copied record; it has the same shape as `return_origin` (`RETURN-BORROW-1`) |
| `locals` | every non-scalar local: `index`, `name`, `role` (`owned`, `param`, `mut_param`, `borrowed`, `path`) and, for `borrowed` and `path`, the `parent` local it names |
| `transfers` | every transfer of a non-scalar value: `pc`, `kind` (`assign`, `binding`, `argument`, `element`, `dict_value`, `field`, `construct`, `update`, `return`), `target` for an assignment or binding, `source` (`origin` `fresh`, `local` or `unknown`, with the `local` and the `part` read: `whole`, `element`, `field`) and `class` (`move`, `borrow`, `copy`) |
| `cow` | every copy-on-write check site: `pc`, the `local` whose payload must be unique, the local the instruction names (`via`), whether the elements must be unique too (`elements`), whether a check is `needed` at all (a `mut` parameter's caller guarantees it) and the loop header it is `hoisted` to, or `null` |
| `moves` | the pcs of the loads whose value moves out of their local |

The `pc`s are the ones `mylang dump-bytecode` prints, so the two outputs line up.
In the example the append's check moves to the loop header at pc 9: nothing in
the loop can make `out` shared, and `out` moves out of the function at its
return. `alias = items` in `main` is a `borrow`, because
neither list is written afterwards.

For example, an accessor returning `nodes[i]` where each `Node` record holds
`bytes` has logical `return_origin: fresh` under `--value-semantics`: the caller
receives an independent record value. Its physical `borrow_origin: params[0]`
records that the copied record still holds backing from `nodes`. A direct
caller can skip a retained-backing copy only while that source remains live and
unwritten. Mutating the source or returning the result outside its lifetime
keeps a real copy. The two facts are tracked through direct calls and generic
specializations; indirect calls remain conservative.

The report is an inspection surface for the compiler's own development — it
validates the analysis against the E2b prototype's decisions and against
hand-written cases — not a stable interface. Host and C-ABI functions have no
body and are skipped.

## Ownership sites

`--rc-runtime=sites` builds a counting RC program that also says *where* its
ownership operations come from (`RC-SITES-1`). Every physical event the
counting runtime records (owner and hold acquire and release, allocation,
retirement, clone, uniqueness check) and the receiver-scope and frame-journal
events a plain counting build does not count (scope begin, end, hold, pin and
prepare; frame enter and leave; slot drop; a uniqueness check that could not be
answered in place) is charged to the emitted call that caused it. A site is one
direct call into the runtime or into a type's generated glue: its function,
bytecode pc (or `entry` for the prologue and `exit` for the shared cleanup),
source position, operation (the runtime entry, or `rcg_OP` for a type's
`loan`, `unloan`, `retain`, `take`, `drop`, `publish`, `list_set`,
`list_append` or `slot_drop` glue) and the static type its descriptor names.
Nothing is sampled: a site's counts are exact, and the sites' counts add up to
the `MYLANG_RC_COUNTS` totals event by event.

```console
$ mylang build tree.my -o tree --rc-runtime=sites
$ MYLANG_RC_SITES=sites.json MYLANG_RC_SITES_TOP=6 ./tree
26
MYLANG_RC_COUNTS {"version":1,"runtime":"rc-v3-sites","saturated":false,"owner_acquire":92,"owner_release":138,"hold_acquire":122,"hold_release":122,"owner_limit":0,"hold_limit":0,"heap_allocate":46,"arena_allocate":0,"retire":46,"clone_shell":0,"unique_check":30}
MYLANG_RC_SITES {"version":1,"runtime":"rc-v3-sites","sites":37,"events":799,"calls":702,"shown":6,"report":"sites.json"}
      events        calls  operation                  type               function                 position pc counts
          92           31  myl_qbe_rc_frame_cleanup   -                  total                    tree.my:18:5 pc 36 hold_release=46 slot_drop=46
          92            1  rcg_slot_drop              Node               main                     tree.my:22:15 pc 3 owner_release=46 retire=46
          62           31  myl_qbe_rc_frame_cleanup   -                  build                    tree.my:11:5 pc 26 owner_release=31 slot_drop=31
          31           31  myl_native_list_new        Node               build                    tree.my:7:24 pc 1 heap_allocate=31
          31           31  rcg_retain                 List<Node>         build                    tree.my:7:5 pc 5 owner_acquire=31
          31           31  rcg_slot_drop              List<Node>         build                    tree.my:7:5 pc 5 owner_release=31
$ head -n 2 sites.json
{"version":1,"runtime":"rc-v3-sites","events":799,"calls":702,"sites":[
{"function":"total","path":"/work/tree.my","line":18,"column":5,"pc":36,"operation":"myl_qbe_rc_frame_cleanup","type":"","calls":31,"events":92,"counts":{"hold_release":46,"slot_drop":46}},
```

`tree.my` builds a binary tree of depth 4 whose nodes hold their children in a
`list[Node]`, then sums it with a `for` loop over each node's children.

At exit the program prints the `MYLANG_RC_COUNTS` line, a `MYLANG_RC_SITES`
summary (how many sites ran, their events and calls, and where the JSON went)
and a table of the top sites by events: `MYLANG_RC_SITES_TOP` sites, 20 by
default, `0` for none. When `MYLANG_RC_SITES` names a file, every site that ran
goes there as JSON, sorted the same way, with the full source path and every
nonzero count. `calls` is how often the call ran, so a site with calls but no
events (a scope lookup, an ownership helper that found nothing to do) still
shows how often it is paid for. Events the runtime records outside any guest
call, such as the final teardown, belong to the `runtime` pseudo-site.

A sites build is for finding which operations to remove, not for timing: its
glue always calls out (like `--rc-runtime=stats`), and every site bumps a
counter. It works with `mylang run`, `mylang test` and `--release`. Guest code
and the `--rc-runtime` and `--rc-runtime=stats` artifacts are unchanged.
