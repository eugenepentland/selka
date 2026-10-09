# Development-speed lane: collections fidelity (recommendation 7, collections half)

> **Ported to main on 2026-09-29** (branch `claude/devspeed-fidelity`). As the
> merge-devspeed-into-main decision recorded, main's sets (`SET-1`,
> `SET-OPERATORS-1`) were kept and this lane's set implementation, ascending
> set printing, `PY-SET-1` and `set` as a free local name were not ported.
> Dict and multi-clause comprehensions, generator arguments, `dict()`,
> `PRELUDE-KEYS-1`, iterable set-method operands and the integer bitwise
> operators landed on top of main's sets.

Branch `devspeed/collections-fidelity`, cut from `450216fe` (`devspeed/integration` with
`mylang fix`). `devspeed/expression-fidelity` (head `1b48be90`, its gate green) is merged
in at `7a0269c0`: its stepped `range` (`ast.RangeBounds`) and shared comparison level
are what the new comprehension clauses and the bitwise precedence build on, so the two
parser changes could not be written apart without a silent gap (a gather loop that
ignored a range step). The work itself is `13084aa9` and `2105aee4`.

This lane closes the last three open items of the 23 September audit, §7: `set`, dict
comprehensions and generator arguments.

## What changed

| Idiom | Spec tag | Behaviour |
|---|---|---|
| `set[T]`, `{a, b}`, `set()`, `set(iterable)`, methods | PY-SET-1 | A set of `int` or `str` elements (`E_SET_ELEMENT` otherwise). `add`, `remove` (traps `R_MISSING_KEY`, Python's `KeyError`), `discard`, `clear`, `copy`, `update`; `union`, `intersection`, `difference`, `symmetric_difference`, `issubset`, `issuperset`, `isdisjoint` take another set or any iterable. `in`, `len`, iteration, `==`, printing, `sorted`/`list`/`sum`/`min`/`max`/`any`/`all` of a set (and of a dictionary: its keys). `set()` needs its type from context (`E_SET_INFERENCE`); indexing is `E_SET_INDEX`. |
| `a \| b`, `a & b`, `a - b`, `a ^ b`, `<=` `<` `>=` `>` | PY-SET-OPS-1 | On two sets of one type. On integers `\|`, `^`, `&` are the bitwise operators with Python's precedence (`\|` < `^` < `&` < `+`). A prefix `&` is still the removed argument marker. |
| `{k: v for ...}`, `{x for ...}`, several clauses | PY-GATHER-1 | Dict and set comprehensions; every comprehension takes two names (`for k, v in d.items()`, `enumerate`, `zip`, tuples), several `for` clauses and several `if` filters. A filter narrows an `Option` it tests. |
| `f(x for x in xs)`, `(x for x in xs)` | PY-GENERATOR-1 | Consumed by `sum`, `any`, `all`, `min`, `max`, `sorted`, `list`, `set`, `dict` and `str.join`. Anywhere else is `E_GENERATOR`, whose note names the list comprehension. |
| `len(x for x in xs)`, `f(x for x in xs, y)` | PY-GENERATOR-2 | `E_GENERATOR` with `sum(1 for ...)` as the alternative; `E_SYNTAX` at the comma with the parenthesized spelling. |

**How it is built.**

- **A set is a dictionary** from its elements to `True`. `CollectionShape.set` marks it, and
  `nominal_catalog` gives the builtin `set[T]` template that shape. Hashing, open addressing,
  membership, `len`, order-insensitive equality, arena escape, GC tracing and iteration
  are the dictionary's own. The checker (`src/sema_sets.zig`) lowers every set operation
  onto dictionary operations the backends already compile: `write`, `contains`, `pop_key`,
  `pop_default`, `copy`, `update`, and `key_at` walks. No backend lowering changed. The one
  runtime addition is the renderer `myl_print_set` in `native_print.c`.
- **Comprehensions lower through ordinary loops** (`src/sema_gathers.zig`). The parser
  builds each `for` clause as the `for` statement it spells, each `if` as a branch, and
  one innermost `gather_step` statement. The checker checks that loop with the ordinary
  statement checker, and the step appends, adds, writes or folds. Every clause therefore
  accepts exactly what a `for` loop accepts, including `range` steps, `zip`, `reversed`,
  views and `.items()`. The unfiltered one-clause, one-name list comprehension keeps
  its existing form, which reserves the source length.
- **Generic function bodies** check set literals, set methods and operators, and dict and
  set comprehensions symbolically. A generator expression there is `E_GENERATOR`, because
  template bodies have no prelude folds at all.

**Decisions the prompt asked for.**

- **Element types.** Integers and `str`, exactly the dictionary key rule. There are no
  tuple, float, bool or record elements.
- **Order.** Iteration visits elements in the order they were first added, as a dictionary
  visits its keys. `a | b` keeps the left operand's order, then the right operand's new
  elements; `&`, `-` and `^` keep the left operand's order. **Printing** (and `str()` or
  an f-string) lists elements in ascending order, integers numerically and `str` by code
  point, and prints `set()` when empty. So two equal sets print alike whatever order built
  them. For small non-negative integers that is also what CPython prints; for other
  elements CPython follows hash order. Documented in `docs/python-syntax.md#sets`.
- **Generators.** `sum`, `any`, `all`, `min` and `max` fold each value as the loop produces
  it, with **no list**. `any` and `all` leave every loop of the generator (`loop_exit` to
  the outermost clause) at the first deciding value, so effects and traps after it do not
  happen, as in CPython. `min` and `max` of no values trap `R_ASSERT` with CPython's
  `min() arg is an empty sequence`. `set(...)` and `dict(...)` fill their collection
  directly. `sorted`, `list` and `str.join` go **through a temporary list**: `list(...)`
  is that list; `sorted` sorts a copy of it (one extra copy); `join` joins it.
- **`len(generator)`** is rejected, as CPython rejects it (`TypeError`). A bare generator
  in a variable or passed to a declared function is `E_GENERATOR`.
- **`set` stays a free name.** A function or a local named `set` still declares itself.
  The builtin template does not claim the name, so only `set[T]` spells the type. A
  program's own `set` function shadows that spelling, as it would in Python. This was
  caught by `unit_test.zig`'s `def set(x)`.
- **No program-wide counter.** The gather state is a stack and a span-keyed use map. The
  only counter touched is the existing per-function loop id.

**Also changed, because the features needed it:**

- `union` is accepted as a member name (`a.union(b)`).
- The four parser hints that named these forms as unsupported are gone from
  `declaration_hints`, `velocity/friction/classifier.json` (`hints`) and
  `tests/parser_hints.py`. PARSER-HINT-8 now says they parse.
- `dict()` and `dict(mapping)` work.
- Backlog C-10 and C-11 are `done`. C-8 is partly done: `<<`, `>>` and `~` remain.

Files:

- New: `src/sema_sets.zig`, `src/sema_gathers.zig`, `src/collections_fidelity_test.zig`,
  `tests/lang/{sets,dict_comprehensions,generator_arguments}.my`.
- Small edits:
  - front end: parser, lexer, formatter, ast;
  - checker: `sema{,_builtins,_collections,_expressions,_operators,_statements}.zig`,
    `generic_bodies.zig`, `symbolic_shapes.zig`;
  - types and runtime: `nominal_{catalog,templates}.zig`, `runtime_values.zig`,
    `native_render.zig`, `native_print.{c,h}`;
  - `prelude{,_builtins}.zig`, `reference.zig`, `diagnostic.zig`.
- Docs: `docs/python-syntax.md` (Operators, Sets, Dict and set comprehensions,
  Generator expressions), `docs/primer.md`, `docs/managed-memory.md`,
  `docs/current-language.md`.
- Four `src/features.json` entries: `sets`, `dict-and-set-comprehensions`,
  `generator-arguments`, `bitwise-operators`.

## Measurements

**C1**, measured with `python3 velocity/score.py --binary <install>/bin/mylang`. The
load average was 16 to 38 while scoring; C1 is a correctness count, not a timing.

| compiler | C1 on the original 67 probes | C1 with the 12 new probes | C2_policy | C3 |
|---|---|---|---|---|
| base `450216fe` | 21/67 | — | 0 | 44/73 |
| + expression-fidelity (`7a0269c0`) | 26/67 | — | 0 | 45/68 |
| this branch (`2105aee4`) | **32/67** | **44/79** | 0 | 42/62 |

- **Flipped by this lane:** `a21_set`, `a22_set_literal`, `a66_nested_comp`,
  `a67_dict_comp`, `a68_genexp` and `e02_bitops_each`. No probe was lost against either
  earlier compiler.
- **`a54_bitops` still rejects**, because it also uses `<<` and `~`.
- **The 12 new CPython-oracle probes** are `velocity/suites/idioms/f01…f12` (same text as
  `tests/fixtures/idioms/*`, `must_pass`). They cover set operators, set methods, set
  comprehensions, `sorted(set(...))`, dict comprehensions over `.items()` and `zip`,
  nested clauses, `sum`/`any`/`all`/`min`/`max` and the collecting consumers of
  generators, and integer bitwise operators. All 12 agree with CPython.
- C2 strict is still 1: the declared `d05_round_half`.

**Both backends.** The comparison program is `/home/epentland/.cache/mylang-tmp/cf-backends.my`.
It prints every set operation, method and printing case, dict comprehensions over a
range, `.items()` and `zip`, nested clauses, every generator consumer and the bitwise
operators.

- `mylang build` (QBE) and `mylang build --release` (LLVM `-O3` + LTO) print identical
  output.
- The only difference from CPython's output is the order CPython prints `{8, 3, 5}` and
  `{8, 5}` in; this language prints them ascending.
- The 12 probes agree with CPython under both backends.
- `mylang test --release` passes all three new guest files: 19 + 10 + 8 tests.

**Gate** at `2105aee4`, run through `slot.sh gate` / `slot.sh build`; all green:

| step | result |
|---|---|
| `zig build test --summary all --maxrss 8000000000` | exit 0, 92/92 steps, 1,999 tests passed (the rest are other shards' skips) |
| `zig build test-qbe --summary all` | exit 0, 47/47 steps, 415/415 tests |
| `zig build test-qbe-build --summary all` | exit 0, 29/29 steps |
| `zig build fmt-check` | exit 0 |
| `zig-out/bin/mylang test tests/lang` | 632 passed, 0 failed across 111 programs |
| `tests/idiom_probes.py` (in the gate) | the 12 new probes at target; `is_none` is "changed" on the merged base too |

## A pre-existing crash the gate's `--gc-stress` run found

The first gate run failed one new guest test under `mylang test tests/lang --gc-stress`,
with SIGABRT / SIGSEGV. The cause is **not** a set. This dictionary-only program crashes
the same way on the base `450216fe`:

```mylang
# doc: skip Historical pre-redesign syntax retained as audit evidence.
# doc: expect 1
def main() -> int:
    keys: dict[str, bool] = {"a": True}
    values: dict[int, bool] = {1: True}
    counted = {0: True, 1: True, 2: True}
    return 1 if counted == {0: True, 1: True, 2: True} else 0
```

```console
$ mylang run --gc-stress repro.my     # exit 139 on 450216fe; exit 1 (correct) without --gc-stress
```

- **Small edits hide it.** Dropping `keys` or `values`, or using one literal instead of
  three pairs, makes it pass. That points to a use-after-free that shows only when freed
  memory is reused (a Zig safety panic reported `pointer index expression with base 0x1`).
- **Likely location:** the root protocol around dictionary-literal construction or
  equality (`qbe_roots.zig` / `qbe_managed.zig`), or in `native_dictionary.c`. This
  machine has no debugger, so it was not pinned down.
- **Workaround here:** the set test was split so that no single function reaches the
  shape, and every new guest file passes under `--gc-stress`.
- **It is reachable from sets too.** The whole backend-comparison program crashes under
  `--gc-stress` when all its statements are in one function; dropping any of several
  unrelated statements makes it pass. Normal runs are unaffected, but a GC at the wrong
  allocation in a normal run would hit the same bug. **It needs an owner.**

## Known gaps

- **Elements.** Set elements, like dictionary keys, are only integers and `str`: there
  are no tuples (for example coordinates), `float`s or `bool`s. There is no `frozenset`
  and no `set.pop()`.
- **Augmented operators.** `s |= t`, `&=`, `-=` and `^=` are not provided; write
  `s = s | t` or `s.update(t)`.
- **`remove` and `discard` are linear** in the set's size, because dictionary `pop` shifts
  later entries (PY-DICT-5).
- **`dict(zip(keys, values))`** is rejected: `zip` is only an iteration source. The note
  names `{k: v for k, v in zip(keys, values)}`.
- **`sum` of `bool`s** is rejected (a `bool` is not an `int` here); the note names
  `sum(1 for ...)`.
- **`sorted(generator)`** makes one extra copy of the loop's list.
- **Generators in generic function bodies** are `E_GENERATOR`, as prelude folds are
  unavailable there too.
- **A module that defines a function named `set`** cannot also spell `set[T]`: the
  existing `f[T]` call-application rule claims the spelling.
- **Printing order** differs from CPython's hash order for `str` sets and some integer
  sets. It is documented, and no velocity probe prints a set; add a divergence entry if
  one ever does.

## Integrator notes

- **This branch contains `devspeed/expression-fidelity`** up to `1b48be90`. Merging it
  after that lane is a no-op for those commits.
- **Conflict-prone shared files:**
  - `src/parser.zig`:
    - `forStatement` is split into `loopHeader`/`loopStatement`;
    - `parseComprehension` and `parseDictionary` are rewritten;
    - `callArguments`, `parenthesizedExpression` and `parseBuiltin` handle generators;
    - `binaryPrecedence` has a bitwise level 4, with `bitwiseOperand` ranking inside it.
  - `src/lexer.zig` (`|`, `^`, binary `&`).
  - `src/sema_builtins.zig` (`queuePreludeCall`/`checkPreludeCall`, `set`/`dict`).
  - `src/generic_bodies.zig`.
  - `SPEC.md`: five new bullets after PY-RANGE-STEP-1, and the reworded PY-COMPREHENSION-2
    and PARSER-HINT-8.
  - `src/features.json`, `docs/python-syntax.md`, `docs/primer.md`.
  - `velocity/friction/classifier.json` (`hints` lost four idioms).
  - `tests/fixtures/idioms/manifest.json` (12 records appended).
- **New AST forms.** `ast.Node.data` gained `gather` and `set_literal`, and
  `ast.Statement.data` gained `gather_step`. A lane that adds an exhaustive switch over
  either needs the cases.
- **Reserved prelude names.** `set` and `dict` are now reserved prelude names. They stay
  shadowable: a local or declared function of that name wins.
- **The velocity manifest.** `velocity/suites/idioms/manifest.json` was not regenerated
  for the `f*` probes; `score.py` globs the suite, and the lead regenerates the manifest.

## Reproduce

```console
$ python3 velocity/score.py --binary zig-out/bin/mylang
$ zig-out/bin/mylang test tests/lang/sets.my tests/lang/dict_comprehensions.my tests/lang/generator_arguments.my
$ zig-out/bin/mylang test tests/lang/sets.my --release
$ zig-out/bin/mylang test tests/lang/sets.my --gc-stress
$ zig build test-units -Dtest-filter=generator -Dtest-filter="a set "
$ python3 tests/idiom_probes.py --compiler zig-out/bin/mylang
```
