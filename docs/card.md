# Selka on a card

Read before writing Selka; `selka docs primer` is the tutorial.

## Program and bindings

- After each file: `selka fix FILE; selka check FILE`. Fix writes the errors' repairs (imports, `own`, `copy`, `mut`, `from`, `try`, removed spellings), check shows the rest; `--warnings` or a folder adds warnings', `--check` lists edits.
- `func main(out: Stream) -> int:` returns the exit status. `print(out, a, b)`; `err: Stream` is stderr; `debug(x)`: stderr, but nothing in a `build --release` executable.
- Authority is a parameter of `main`: `args: str[]` first, then `out`, `fs: Filesystem`, `clock: Clock`, `env: Environment`, `net: Network` (`main(out: Stream, args: str[])` is `E_MAIN`). Pass it down. An unused capability parameter is refused (`E_UNUSED_CAPABILITY`): delete it.
- Read a file with `fs.read_text(path)`, a `Result` (below); a folder: `filesystem.list_entries(fs, dir)`.
- `const x = 1` is fixed, `mut x = 1` changes. A name binds once: no shadowing a local, parameter, function or imported module (`E_SHADOWING`). A module constant needs its type, `const LIMIT: int = 8`, and is a number, `bool`, `str` or `bytes`.
- An empty collection needs its type: `mut xs: int[] = []`, `mut d: dict[str, int] = {}`. Conditions are `bool`: `if len(xs) > 0:`; `True` and `False`.
- No tuples, classes, lambdas, comprehensions, `a if c else b`, `**` (`math.pow(2.0, 3)`) or `& | ^ << >>` (`bit_and(a, b)`, `bit_or`, `bit_xor`, `shift_left`, `shift_right`).
- Dropping a result is refused, in tests too: `_ = lists.pop(mut xs)`.

## Ownership

```selka
# doc: expect 2 ['a', 'b']
record Row:
    name: str
    tags: str[]

func add(mut rows: Row[], own row: Row):
    append(mut rows, own row)

func names(own rows: Row[]) -> str[]:
    mut out: str[] = []
    for row in own rows:
        append(mut out, own row.name)
    return out

func main(out: Stream) -> int:
    mut rows: Row[] = []
    const row = Row(name="a", tags=[])
    add(mut rows, own row)
    add(mut rows, Row(name="b", tags=[]))
    const n = len(rows)
    print(out, n, names(own rows))
    return 0
```

- A plain argument is lent for the call: `size(rows)`, not `size(copy(rows))`; a `mut` parameter takes `f(mut x)`. A fresh value (call, constructor, literal) or a scalar is stored bare: `add(mut rows, make())`.
- A name you are finished with moves with `own`: `append(mut rows, own row)`, `Row(tags=own tags)`, `Some(own items)`. It is dead afterwards (`E_SINGLE_OWNER_MOVED`). Return a local bare; a field is `return own row.tags`.
- A value you were only lent (a plain parameter, a loop variable, a match payload, a slice `t[a:b]`) cannot be stored or returned as it is (`E_SINGLE_OWNER_BORROW`, `E_SLICE_ESCAPES`, `E_BORROW_UNDECLARED`). Owner done? Move: an `own` parameter, `for x in own xs:`, `match own v:` (payloads are owned). Receiver only reads it? Lend: `const`, a plain parameter, `-> T from p`. Only if both live on: `copy(x)`.
- `for x in r.items:` borrows `r.items` to its end: `f(mut r)` in it is `E_SINGLE_OWNER_OVERLAP`. Pass the field `f` changes (`mut r.n`), or write `for x in detach r.items:`: `r.items` is empty inside and put back at every exit.
- Returning part of a parameter: `func name_of(row: Row) -> str from row:`, no copy. `take(mut r.items)` moves a field out.

## Results and options

```selka
# doc: expect 3
func parse(text: str) -> int fails str:
    const n = parse_int(text) else:
        fail "bad"
    return n

func total(a: str, b: str) -> int fails str:
    const x = try parse(a)
    const y = try parse(b)
    return x + y

func main(out: Stream) -> int:
    const sum = total("1", "2") else Err(message):
        print(out, message)
        return 1
    print(out, sum)
    return 0
```

- `-> T fails E`; raise with `fail`. `try f()` is a value anywhere (`g(try f())`, `if try ok(n):`), left to right; not in a constant or default. Or `match f(s):` with `case Ok(n):`, `case Err(e):`; a `Result` has no methods.
- `parse_int(s)` is `int?`: `x.unwrap_or(0)`, `if x is None:` over a block that returns narrows `x`, `if f() is Some(x):`, `const n = f() else:` over a block that leaves. `else Err(m):` makes a new name: not for an assignment (`E_SYNTAX`).
- An enum pattern uses the fields' own names, not positions: `case rect(w, h):` binds `rect`'s `w`, `h`; `rect(w=a, h=_)` renames `w`, discards `h`. Nested patterns need labels (`E_NAMED_PATTERN`). One case: `if e is rect(w, h):`.

## Text, bytes and collections

- `str` is bytes: `len(t)` counts octets, `t[i]` is an `int`: `t[i] == ord("a")`, not `== "a"`. `"b" in t` tests text (`strings.contains` does not exist). `t[a:b]` is a borrowed slice.
- Operations are functions, not methods (`t.split(",")` is `E_METHOD_REMOVED`): after `import strings`, `split(t, ",")`, `join(parts, ", ")`, `strip`, `lines`, `starts_with`, `replace`.
- `append(mut xs, x)`, `len`, `sorted(xs)`; the rest is in `lists`: `lists.pop(mut xs)`, `lists.contains(xs, x)` (`x in xs` is refused). `sort(mut xs, key=by_name)`: a top-level function returning an owned `int`, `float` or `str`.
- `d[k] = v`; `d[k]` of a missing key traps; `dicts.get(d, k, 0)`, `k in d`, `for k, v in dicts.items(d)`; `sets.include(mut s, v)`.

## Modules and tests

- A file is a module by its path: `import util`, then `util.f(x)`; `import shared.calc` gives `calc.f`. Imports start at the folder of the file you check, or of the nearest `selka.json` (`{"version": 1}`); else `E_MODULE_READ`. Only `public` declarations are visible; a `public func`'s types must be `public` too (`E_PRIVATE_INTERFACE`).
- `public func test_name() -> bool:` in the file, or in `name_test.selka` after `import name`; `selka test FILE`. One `assert a == b` per fact.

## Before you guess

- `selka reference --query NAME`: signature (`strings.split`), module (`strings`), code (`E_OWN_MARKER`).
- `selka docs` lists the guides, `selka docs TOPIC` prints one: `io` (files, processes, network), `concurrency` (tasks, `parallel.map`), `ownership`, `stdlib`.
