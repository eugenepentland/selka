# `sorted(key=...)` crashes after a clean check — 2026-09-22

**Headline.** Two programs from the benchmark ports passed `mylang check` and
then failed every build with `mylang: host failure: InternalError`. Both came
from one line: the checker gave the key slot of `sorted(xs, key=...)` a callback
type that no source spelling produces. The slot now has exactly the type
`def(T) -> int effects()` spells, and every probed spelling below builds and
answers correctly. This is item 6.12 of the
[performance parity plan](performance-parity-plan-2026-09-22.md) (§4.9, wave 0).

Branch `fix/sorted-key-crash` from `base/parity-20260922` (`bbabfc85`).

## Root cause

A callback type is interned by `callables.intern` in
[`src/callables.zig`](../../src/callables.zig). Its identity is the whole
contract, `callables.equal`: parameters, result, effect ceiling, `mutates`
positions **and a return-origin bound** (`fresh`, `params`, `unknown`). Its
record *name* leaves the origin out, `def(i64) -> i64 effects()`, because the
surface has no way to write an origin bound. Every written callback type gets
the bound `unknown` (`nominal_layouts`, `symbolic_shapes`, `generic_bodies`),
and so does every unannotated function value (`Checker.functionValue`).

`Checker.hintSortedArguments` in [`src/sema.zig`](../../src/sema.zig) was the
one place that interned a different bound. It hinted the key argument with
`def(T) -> int effects()` and origin **`fresh`**. That caused two failures.

1. **A second callback of the key's type anywhere in the program**
   (`agent_b_bug_sorted_key_callback_value_internal_error.my`). `f = twice`, a
   `def(int) -> int effects()` parameter, `sort.sort_by_key(xs, f)` or a lambda
   all intern the `unknown` record. The sorted hint then interned a `fresh`
   record with the same name. `native_types.Catalog.init` rejects duplicate
   record names with `DuplicateIdentity`, and `qbe.layoutError` reports that as
   `InternalError`. Bytecode lowering passes; QBE and LLVM emission both fail.
2. **An identity key** (`agent_b_bug_sorted_key_identity_internal_error.my`).
   `Checker.functionValue` adopts the destination's schema when only the origin
   bound differs, without checking the bound. It cannot check it: a function's
   return origin is only summarized after checking (`effects.zig`). So
   `key=by_value` took the `fresh` type. `by_value` returns its parameter, so
   its computed origin is `params [0]`. The bytecode validator
   (`validateFunctionValue` in [`src/bytecode.zig`](../../src/bytecode.zig))
   found `params [0]` outside `fresh` and returned `InternalError` before any
   backend ran. `lambda v: v` failed the same way.

The bound `fresh` bought nothing here. The key returns `int`, and no managed
value can flow out of it.

## The fix

The sorted hint interns `.return_origin = .unknown`
([`src/sema.zig`](../../src/sema.zig), `hintSortedArguments`). The key slot is
now the same record as every other `def(T) -> int effects()` in the program, so
both failures are gone. The change touches neither the lowering of `sorted`, the
prelude, nor `src/stdlib/sort.my`.

## Nearby spellings probed

The base compiler (`install-a3`) against this branch, with `mylang run
--print-result`. Each probe program also declares `apply_key(key: def(int) -> int
effects(), v: int)`. That annotation is enough to make every `list[int]` sorted
key fail on the base.

| spelling | base | fixed |
|---|---|---|
| named identity key `key=by_value` | InternalError | 1 ✓ |
| `key=lambda v: v` | InternalError | 1 ✓ |
| `key=lambda v: 0 - v` (a callback-typed parameter elsewhere) | InternalError | 3 ✓ |
| key passed through a local, `k = neg; sorted(xs, key=k)` | InternalError | 3 ✓ |
| one key function in two `sorted` calls | InternalError | 8 ✓ |
| `sort.sort_by_key(xs, neg)` and `sorted(xs, key=neg)` together | InternalError | 6 ✓ |
| `sort.sort_by_key(xs, by_value)` alone | 1 ✓ | 1 ✓ |
| key-typed callback passed to an ordinary parameter plus `sorted` | InternalError | 6 ✓ |
| stored callback `f = twice; f(...)` plus `sorted` | InternalError | 6 ✓ |
| record list, named key and `lambda e: e.rank` | 4 ✓ | 4 ✓ |
| record list, `sort.sort_by_key` and `sorted` with one key | InternalError | 22 ✓ |

None of these needs to become a diagnostic. Each is a well-typed program with a
defined answer.

## Tests

[`tests/lang/sorted_keys.my`](../../tests/lang/sorted_keys.my) has eight guest
tests (`# spec: PRELUDE-SORT-KEY-2` and seven `# spec-case:`). It puts every
spelling above into one program, because failure 1 needed a second callback of
the key's type anywhere in the program. With the base compiler the file does not
build (`host failure: InternalError`). With this branch all eight pass under
`--gc-stress`. The new bullet `[PRELUDE-SORT-KEY-2]` in `SPEC.md` states the
contract. The existing `sorted` Zig tests (`prelude_builtins_test`) and the
`callbacks` and `python_core` guest files still pass.

## What is left

- A callback record's name still omits its origin bound, and
  `functionValue` still adopts a destination's bound without checking it. With
  every interned callback type at `unknown`, neither can fire today. A future
  hint that interns a narrower bound would bring both failures back. The safe
  rule is that callback types carry `unknown`, and the function's own summary
  stays the thing the validator checks.
- Out of scope, found while probing: `sorted(xs, key=key)` inside a generic
  function body (`def f[T: copy + storable](xs: list[T], key: def(T) -> int
  effects())`) is rejected with `E_UNKNOWN_SYMBOL: declaration is not present in
  the resolved module`, on the base and on this branch alike. The prelude
  builtin does not resolve in a generic body, and the message does not say so.
