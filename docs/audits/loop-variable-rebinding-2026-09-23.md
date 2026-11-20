# Loop-variable rebinding (2026-09-23)

Branch `fix/loop-variable-rebinding`, built on `perf/parity-integration` at
`32ec8a0f`, which is 2117349f plus the coordinator's `qbe_range_keys` compile
fix. Spec tag: `PY-FOR-REBIND-1`.

## The defect

`for i, x in enumerate(xs):` bound the name `i` to the loop's own counter slot
and left it mutable. `i = 10` in the body therefore rewrote the counter: the
next bound test was `10 < len`, and the loop ended after one pass. Python
rebinds the loop variable from the iterator at the top of every iteration, so a
body write never changes which iteration comes next.

## Every loop form before the fix

| Form | What the body assigns | Before |
|---|---|---|
| `for i in range(n)` / `range(a, b)` | `i = 10`, `i += 3` | rejected with `E_IMMUTABLE` (FOR-RANGE-1 said "immutable") |
| `for i, x in enumerate(list)` | `i = 10` | **miscompiled**: the loop ran once |
| `for i, x in enumerate([N]T)` | `i = 10` | **miscompiled**: the loop ran once |
| `for i, x in enumerate(...)` | `i, x = pair()` | **miscompiled**: the loop ran once |
| `for i, x in enumerate(...)` | `x = ...` | correct |
| `for x in xs` over a list, str, bytes, dict, dict view or fixed array | `x = ...` | correct: the element slot is re-read every iteration |
| `for k, v in d.items()`, `for a, b in pairs` | either name | correct |
| `for x in reversed(xs)`, `for a, b in zip(xs, ys)` | any name | correct |
| comprehensions | nothing | an expression cannot assign its variable |
| nested `range` loops | inner or outer name | rejected with `E_IMMUTABLE` |
| generic function bodies | any loop name | rejected: the symbolic checker bound every loop name immutable, even an element name that the concrete checker accepts |
| `range` loop in a compile-time function | `i = ...` | rejected (immutable) |

Only the `enumerate` position was silently wrong. It was the one name that was
both the counter itself and mutable. The `range` variable was also the counter,
but it was immutable.

## The fix

`src/loop_rebinding.zig` reads the syntax before the body is checked and
answers whether a loop body can assign a name. It counts a plain or augmented
assignment, an annotated binding, a destructuring target, and a place write
rooted at the name, at any depth. A nested loop, `with` or `match` cannot rebind
an active name, so every hit is a write to the loop's own variable. The walk
over nested statements is now `ast.appendNested`, which `option_flow`'s
invalidation walk also uses.

- **A counting loop (`range`, or an `enumerate` position) whose body never
  assigns its variable** keeps its old lowering. The variable is the counter,
  and it is now immutable in both cases. The `enumerate` position used to be
  mutable.
- **A counting loop whose body does assign its variable** keeps its count in a
  hidden local (`<range-index>`, or the enumerate index). The visible name is a
  separate mutable local, set from the counter by the first statement of each
  iteration. `continue` jumps to the step, which advances the hidden counter,
  and the next iteration copies it again. `break` skips the step.
- **Loop variables can now be assigned in more places.** `range` variables can
  be assigned, as in Python (FOR-RANGE-1 is amended). So can every loop name in
  a generic body, and the `range` variable of a compile-time function. That
  function's evaluator already reset the variable from its own count on every
  iteration.
- **Element loops, `reversed`, `zip`, dictionary items and tuple pairs** already
  had separate slots and needed no change.

## The array lane's "withdraw" rule is gone

`PY-ARRAY-NEGATIVE-1` skips the negative-index adjustment when the checker
proves an index non-negative, and an `enumerate` position counted as one.
Because the position was mutable, the array lane recorded every access that
relied on it (`CounterAssumption`, `ArrayKey.counter`, `assume`,
`beginCounter`, `endCounter`, `settleCounter`). Once the body was checked, it
switched those accesses to count from the end if the body had assigned the name.
For the same reason it refused to treat `range(position, n)` as non-negative.

Now every loop counter is immutable, and a variable the body assigns is never
registered as a counter. The proof is a plain lookup: the `.local` case of
`nonNegative` is `self.counters.contains(slot)`. All of the machinery listed
above is deleted. A side gain is that `for inner in range(position, 8)` inside
an `enumerate` loop now proves non-negative; a new `array_places_test` case
checks this.

When an `enumerate` loop or a range comprehension ends, its counter is removed
from the set. A sort-key lambda's trial check truncates the locals table, so a
counter left in the set could later be attached to an unrelated local that
reuses its slot.

## No codegen change for loops that never assign their variable

- **Hot-loop probe, byte-identical.** The probe covers `for i in range(n)`,
  `range(a, b)`, a triangular nested `range(i, 4)` indexing a fixed array,
  `enumerate` over a list and over a fixed array, and a range comprehension.
  `mylang emit-qbe` output before (32ec8a0f) and after is byte-identical.
- **Corpus, 177 programs, 0 differ.** The corpus is every program that
  `emit-qbe` accepts in `tests/lang` (with the `module` header dropped),
  `tests/lang/migrated` and `examples`.

A loop that does assign its variable pays one local copy per iteration and
loses the non-negative proof for that variable.

## Tests

- **`tests/lang/loop_rebinding.my`** (`# spec: PY-FOR-REBIND-1`): 14 tests, run
  under `--gc-stress` with traced strings. They cover:
  - `range` and `range(a, b)` with plain and augmented writes
  - `enumerate` over a list and over a fixed array
  - destructuring into the position
  - `continue` and `break` after a write
  - list, str, fixed-array and bytes elements
  - `reversed`, `zip`, dictionary keys and items, and tuple pairs
  - nested loops, a generic body and a compile-time function
  - loops that never assign their variable and still count
- **`src/array_places_test.zig`:** array reads through a rebound variable carry
  the negative-index adjustment. Counters that are never assigned carry none,
  including a `range` that starts at an `enumerate` position.
- **`generic_bodies_test`:** removed the case that expected `E_IMMUTABLE` for
  `i = 1` inside a generic `range` loop, because that behaviour is now defined
  to be accepted.
- **`tests/lang/array_negative_index.my`:** the `enumerate` test no longer puts
  its position back after the write.
- **Docs:** `docs/range-iteration.md` gains a runnable example, and
  `docs/statements.md` states the rule.

## Gate

Each step was compared with `gate_diff.py` against the coordinator's
`arrneg2-*.log` for 32ec8a0f. `test`, `test-qbe`, `test-qbe-build`,
`test-schematic` and `test-byte-io` show 0 new failures, `fmt-check` is clean,
and `test-docs` has 0 failed. The first `zig build test` run failed the stale
generic-bodies case above. After that case was removed, the rerun was green.
