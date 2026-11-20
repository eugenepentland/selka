# Parity leftover bugs — 2026-09-23

The correctness bugs the performance-parity lanes found and worked around,
fixed on `fix/checker-bugs` from `base/parity-leftovers` (`160a2d08`). One
commit per bug; every behavioural change has a `// spec:` test and a SPEC.md
bullet.

| # | bug | status | spec | commit |
|---|---|---|---|---|
| 1 | `escape` cannot copy a `class` instance | fixed | ARENA-ESCAPE-CLASS-1 | `112d4112` |
| 2 | `?` on `Option[Node]` in a function returning `Option[int]` is `E_TYPE` | fixed | OPTION-TRY-3 | `09239127` |
| 3 | unannotated function rejected by a generic callback slot | fixed, and the slot rule made sound | CALLBACK-SLOT-1 | `793118f2`, `bef9d498` |
| 4 | `sorted(xs, key=...)` in a generic body | named keys already worked; lambdas now one clear diagnostic | GENERIC-LAMBDA-1 | `6852fe75` |
| 5 | lambda sort keys typed `int` unless the body is simple | fixed: the key type is the body's own type | LAMBDA-KEY-INFER-1 | `bef9d498` |
| 6 | `fmt-module` prints `Option[int]effects()` | fixed | FMT-CLAUSE-SPACE-1 | `10273098` |
| 7 | SPEC.md's first line truncated to `ython` | fixed | — | `112d4112` |
| 8 | functions past ~120k bytecode instructions do not build | LLVM: fixed (quadratic dominators); QBE: inherent, now a clean up-front refusal | QBE-SIZE-LIMIT-1 | `37e85b07` |
| 9 | overflow traps print `u64` operands signed (added by the coordinator) | fixed | TRAP-UNSIGNED-1 | `c58b5950` |

## 1. `escape` of a class instance

**Repro.** `kept = scratch.escape(Node(value=7, next=Some(leaf)))` with `Node`
a `class` trapped `OutOfMemory` (option-niche audit).

**Root cause.** `native_regions.c` `shallow()` cloned only collections
(`collection_kind` 1–4) and returned NULL for any other managed pointer; the
copier reports a NULL clone as allocation failure. A class body has no
collection header: its pointer descriptor is opaque (`collection_kind` 0) and
its shape lives in the payload header — the `X_body` descriptor and element
count.

**Fix.** For `collection_kind == 0`, allocate the clone with
`myl_native_heap_alloc(heap, header->element, count)` in the enclosing region
and, in `fill`, translate each element through the body descriptor, patching
references through the clone table. The clone is therefore exactly what a
constructor makes: the same two-word header and `cell` body descriptor (so later
field stores run the generational barrier), young on the tracing heap (or an
allocation of the enclosing arena), filled while collection is suspended, so no
barrier is owed for the fill.

**Test.** `tests/lang/arena_class_escape.my`, 7 cases under `--gc-stress`:
a class chain, a cycle through class fields (identity checked by mutation),
classes in lists and lists/strings in classes with sharing, sharing of an
older instance, a young object stored into an escaped (promoted) instance
through the barrier and churned, escape into an enclosing arena, and a class
with no fields.

## 2. `?` on `Option[T]` into `Option[U]`

**Root cause.** The concrete checker (`sema.zig` `.propagate`), the generic
body checker (`propagateValue`) and the bytecode validator
(`validateOpTryResult`) all required the operand's element to equal the
enclosing function's. OPTION-TRY-1 only asks for a "compatible Option", and the
QBE lowering already writes a fresh `None` tag of the *output* type, so the
check was the whole bug.

**Fix.** Drop the element equality in all three places; a non-Option return
is still `E_TRY_RETURN`. Documented in `docs/results-and-options.md` with a
runnable example.

**Test.** `tests/lang/option_propagation.my` (class payload into
`Option[int]`, class into another class option, `int` into `str`, and a
generic function), under `--gc-stress`.

## 3. Unannotated functions in generic callback slots

**Rule check.** CALLBACK-EFFECTS-1 says an unannotated free function fills any
callback slot, and `Checker.functionValue` implements it by giving the value
the slot's ceiling — but only when the slot is known when the argument is
checked. A generic callee's parameter (`def(T) -> int effects()`) is concrete
only after inference, so the value was typed `effects(<all>)` and the call
failed `E_TYPE`.

**Fix.** The call-argument check gives such a value the instantiated slot type
(`adoptSlotCeiling`).

**Soundness hole found on the way.** Adopting the slot was never checked
against the body, so `run(key, 1)` with `run` `noalloc`/`noio` and `key`
allocating or printing through an `effects()` slot compiled and ran. The
effect pass now holds every unannotated function value's inferred body to its
value type's ceiling (`effects.zig` `checkSlotCeilings`): `E_EFFECT_BOUND` at
the value, naming the function, the slot type, the effect and the witness path.
To keep allocating sort keys (LIST-SORT-KEY-3) the sort-key slot became
`def(T) -> K effects(managed_allocation)` (see 5), which is exact: its only
call site is the keyed sort, already charged allocation. So no effect is
exempt.

**Tests.** `tests/lang/callback_slots.my` (`sort.sort_by_key` with an
unannotated key, user generic slots, an allocating function in an unbounded
slot); `src/python_core_test.zig` diagnostic cases for `output` (direct and
generic, with a witness path) and `managed_allocation` under `noalloc`.

## 4. `sorted` with a key in a generic body

Re-checked: `sorted(xs, key=key)`, `ys.sort(key=key, reverse=True)` and
`xs.copy()` in a generic body all work (GENERIC-BODY-4, keyed-sort lane),
including in another module and — with 3 — with an unannotated key. The
`E_UNKNOWN_SYMBOL` from the sorted-key-crash audit no longer reproduces.

What remained: **any lambda** in a generic body failed with two misleading
diagnostics, `E_UNKNOWN_NAME "name is not defined in this template scope"`
(the parser names a lambda by its `lambda` keyword and the template checker
looked it up as a local) and `E_LAMBDA_CONTEXT` (the never-typed lambda).
Supporting it is a real feature: a lambda is one synthesized function with one
callback type, so it cannot follow the template's type parameters into each
specialization. Both paths now report one `E_GENERIC_BODY_UNSUPPORTED` at the
lambda that says to pass a named function. Test:
`src/generic_bodies_test.zig` (GENERIC-LAMBDA-1, exactly one diagnostic, sort
key and plain callback); guest case `tests/lang/keyed_sorting.my`.

## 5. Lambda sort-key types

**Root cause.** `hintSortKeywords` read the key type off a few body shapes
(element, field path, arithmetic, `len`, tuples) and otherwise guessed `int`,
so `key=lambda p: p.name.lower()` failed `expected int, found str`, and a
`bool` body was rejected.

**Fix.** `inferLambdaKey` checks the body once with its parameter bound to the
element type and no expected result, then undoes every trace of the trial —
typed nodes, statements, locals, resolved entries, the parameter binding
(restoring a shadowed one), option facts, ownership state and diagnostics — so
the lambda is checked for real exactly once, against the slot this type fixes.
A body that does not type on its own is one `E_SORT_KEY` at the lambda quoting
the underlying diagnostic (the never-typed lambda is marked so it adds no
`E_LAMBDA_CONTEXT`). The fast shape reader stays first, so every key that
checked before gets the same type.

**Tests.** `tests/lang/lambda_sort_keys.my` (method call, declared function,
float conversion, conditional, slice with `.sort(reverse=True)`, text keys
under `--gc-stress`); `src/prelude_builtins_test.zig` for the diagnostic; the
old `key=lambda v: True` rejection became a run (bool keys are ordered).

## 6. `fmt-module` spacing

**Root cause.** `formatter.zig` keeps an identifier tight after `]` so an array
spelling `[2]u.Value` binds its element type; that also glued a clause to a
bracketed return type.

**Fix.** `followsApplication` finds the `[` the `]` closes and spaces the
identifier when that bracket is a type application or subscript
(`bracketRole == .subscript`). Test: `src/formatter_test.zig`, round-tripped
twice (idempotent), plus `src/stdlib/sort.my` checked for `]effects(`.

Noticed, not changed: `fmt-module` puts one blank line after `module` where
`src/stdlib/sort.my` has two, and prints a keyword-typed array element spaced
(`[2] u8`) — both pre-existing canonical choices.

## 7. SPEC.md first line

`b05b3034` replaced the title and the first two sentences with `ython`. Restored
from `b05b3034~1`.

## 8. Functions past ~120k bytecode instructions

Measured with a generated straight-line function of N checked statements
(`x = x + y * k`, 6 bytecode instructions each), Debug compiler:

| N | backend | before | after |
|---|---|---|---|
| 2 000 | llvm | 16 s, 2.3 GB | 9 s, 0.28 GB |
| 8 000 | llvm | adapter `MemoryError` at 8.6 GB | 43 s, 1.0 GB |
| 20 000 (120k instr.) | llvm | out of memory | 3 min 37 s, 2.6 GB |
| 2 000 | qbe | 9 s, 0.97 GB | same |
| 4 000 | qbe | 72 s, 3.7 GB | same |
| 8 000 | qbe | QBE `emalloc` OOM after 3–4 min | refused in 14 s with a message |

**LLVM adapter — a clear bug.** `llvm_emit.py` `_dominators` kept a full
dominator *set* per block (quadratic space) and rebuilt `set(order)` for every
successor edge (quadratic time). It now computes immediate dominators
(Cooper–Harvey–Kennedy over reverse postorder) and answers `dominates(a, b)`
from dominator-tree entry/exit numbers; `_established` is its only consumer.
`test_adapter.py` checks it against the set definition on hand-made and 200
random graphs (loops, unreachable blocks) and a 60 000-block chain. The
remaining superlinearity at 20 000 statements (codegen 156 s) is in LLVM itself
and LTO, not the adapter. This touches the adapter, which is the
`perf/checked-arith-intrinsics` lane's area; the change is confined to
`_dominators`/`_established` plus a new `Dominators` class.

**QBE — inherent.** QBE's liveness and register allocation keep one temporary
bit set per block, so its memory is about 1.6 bytes per block × temporary pair
(0.97 GB at 8k × 76k, 3.7 GB at 16k × 152k): quadratic in function size by
design of the vendored backend, not a data structure of ours. The build now
estimates it before starting QBE (`qbe_build.zig` `qbeRefusal`) and, when the
estimate exceeds three quarters of the address-space ceiling QBE inherits
(`MYLANG_HOST_MEMORY_LIMIT`, 8 GiB by default), stops with:

```text
mylang: function `work` is too large for the QBE backend: 32006 blocks x 304016 temporaries need about 14.5 GiB in QBE, over the 8.3 GiB address-space ceiling it inherits (MYLANG_HOST_MEMORY_LIMIT); split the function, or build with `--backend llvm`
```

An unbounded ceiling refuses nothing. Documented in
`docs/tooling/native-build.md` ("Very large functions"). Test:
`src/qbe_build.zig` (QBE-SIZE-LIMIT-1), including the measured 4 000/8 000
shapes against the default ceiling.

Worth knowing for whoever shrinks it: the IL spends ~38 temporaries and 4 blocks
per checked statement in a ReleaseFast build (Debug `emit-qbe` IL: 62 and 10),
mostly per-operation overflow branches and position/step bookkeeping; halving
either halves QBE's memory.

## 9. Unsigned trap operands (coordinator addition)

**Root cause.** The trap detail stores operands as `int64_t` and every renderer
(`qbe_runtime.c` `detail_text`/`detail_json`, `native_trap_detail.zig`,
`--diagnostics=json`) printed them signed: a `u64` overflow read `left -2`.

**Fix.** A present bit, `MYL_QBE_TRAP_PRESENT_UNSIGNED`, marks unsigned
operands. Generated cold calls OR `MYL_QBE_UNSIGNED_OPERANDS` (0x100) into their
width (`myl_qbe_fail_overflow_op`, `myl_qbe_fail_cast`) or operation
(`myl_qbe_fail_division`) argument only at unsigned sites; the runtime helpers
(`myl_qbe_int_binary`, `_cast`, `_neg`) set the bit from `is_signed`. The
record adds `"unsigned":true` and prints unsigned decimals; the host parser
reads operands as `i128`. No runtime symbol or signature changed, so the LLVM
adapter's tables are untouched, and signed sites emit byte-identical IL and
text. Tests: `src/native_execute.zig` (add, mul, cast, division by zero, sub
unsigned; add, mul signed unchanged), `src/native_trap_detail.zig` (transport
round trip, malformed out-of-range operand).

## Found, not fixed

- `src/qbe.zig.orig`, `src/qbe_test.zig.orig`, `src/bytecode_inline.zig.orig`
  and `src/bytecode_inline_test.zig.orig` are tracked (from `ed6148cf`, a
  snapshot commit) and look like merge leftovers.
- `experiments/llvm-backend/test_adapter.py`
  `test_benchmark_runtime_registry_is_complete` fails on this base:
  `myl_native_text_points` has no entry in `runtime_signatures.py`. Not run by
  the gate.
- `typed.surfaceTypeName` renders capability parameters of callback types by
  their internal names (`def(stream_cap, int) -> int effects()`); existing tests
  pin that spelling.

## Gate

Debug compiler at `37e85b07`, each step through the gate slot and the memory
cap, compared with `gate_diff.py` against the coordinator's `w4-<step>.log`:

| step | result | vs. w4 |
|---|---|---|
| `zig build test` | 73/73 steps (sharded; `tests/lang` 511 passed across 101 programs under `--gc-stress`) | 0 new; clears `QBE-INLINE-ALLOC-1 a small class body…` (fixed by `160a2d08`) |
| `test-qbe` | 48/48 steps, 308/308 tests | 0 new |
| `test-qbe-build` | 30/30 steps | 0 new |
| `fmt-check` | 2/2 | 0 new |
| `test-docs` | 25/25 | — |
| `test-byte-io` | 26/26 | 0 new |
| `test-schematic` | 27/27 | 0 new |

`experiments/llvm-backend/test_adapter.py` (not in the gate) passes except the
pre-existing registry failure noted above.
