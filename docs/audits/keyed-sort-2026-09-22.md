# Keyed sorting in the standard surface (wave 3) — 2026-09-22

Lane `lang/keyed-sort` of the performance-parity plan
([`performance-parity-plan-2026-09-22.md`](performance-parity-plan-2026-09-22.md),
§4.3, §5.5, wave 3 item 3). Base `base/parity-w3-sort` (`92ca76b7`).

## Result

Loaded machine (load average 9–13 during the batch; Zig's `sort_records` took
148 ms against 108 ms on a quieter run). 11 interleaved rounds pinned to CPU 9,
paired medians against Zig ReleaseFast with 95% bootstrap intervals
(`table.py --ms --ci`). Peak RSS is the median of three `/usr/bin/time` runs
per arm. *before* is the base compiler (`install-textsort`, the integration
branch this lane starts from); the keyed program has no *before* because the
surface did not exist.

| program | spelling | before | after | target | peak RSS (× Zig) |
|---|---|---:|---:|---|---:|
| `sort_records_keyed` (new) | `records.sort(key=lambda r: r.key)` | — | **0.56** [0.51, 0.62] | ≤ 1.0×, RSS ≤ 2× | 26.7 MB (**1.67**) |
| `sort_records_sorted` | `sorted(records, key=lambda r: r.key)` | 1.48 [1.44, 1.48] | **0.33** [0.32, 0.33] | ≤ 1.0× | 50.0 → 42.1 MB (2.62) |
| `sort_records` | `sort.sort_by_key(records, by_key)` | 0.69 [0.67, 0.70] | **0.31** [0.30, 0.32] | not gated | 42.4 → 42.1 MB (2.63) |
| `sort_builtin` | `values.sort()` | 0.50 [0.47, 0.53] | 0.52 [0.49, 0.53] | unchanged | 26.4 → 26.4 MB |

Zig ReleaseSafe ran at 1.16× and 1.17×, Rust at 0.41× and 0.31× in the same
batch. Raw rounds:
[`results/wave3/keyed-sort.json`](../../experiments/perf-parity-plan-20260922/results/wave3/keyed-sort.json).

All three acceptance items hold. The in-place keyed sort holds no second list
of records: its peak is the records, the key list and the counting table. The
two copying spellings still hold the input and the result (2× Zig by
construction, as the lib-sort lane noted), so their RSS is unchanged; they now
gather the result directly, so their time is below the in-place sort's.

`sort_records`' keys (0..99 999 over a million records) span fewer values than
there are elements, so all three keyed spellings take the counting-sort path
below. Keys spread wider than the list take the packed integer sort, which is
the lib-sort lane's `sort_by_key` engine: about the old `before` column plus
the permutation. Earlier in this lane, before the counting path and the
prefetching permutation existed, the in-place arm measured 0.80× on a quiet
machine and 1.22× under heavy load (a latency-bound cycle walk suffers most
from a shared, thrashed L3); the prefetch took that loaded figure to 1.02× and
the counting path to the numbers above.

## Surface

- `values.sort(key=f, reverse=b)` sorts in place; `sorted(values, key=f,
  reverse=b)` returns a sorted copy. Both keywords are optional and
  keyword-only, as in Python. The method form works on a named list and on any
  list expression (`holder.items.sort(key=...)`), which needed method calls on
  expression receivers to record keyword names (SYNTAX-METHOD-KEYWORDS-1).
- Keys: every integer width, `bool`, `float`, `str`, and flat tuples of those
  (2–8 fields, compared field by field). Tuples exist on this base
  (`SYNTAX-TUPLE-*`, `TUPLE-*`), so tuple keys are in, not left.
- `sort.sort_by_key(values, key)` is now `return sorted(values, key=key)`.
  That needed the generic-body checker to accept the prelude `sorted` (and,
  for the keyword method, `values.sort(key=..., reverse=...)` and
  `values.copy()`), GENERIC-BODY-4.
- A lambda key gets its key type from its body when the body is the element, a
  field path from it, arithmetic or negation of one, `len` of one, or a tuple
  of those; otherwise `int` (the old behaviour). A named function key is hinted
  with its declared result, so an unannotated key fills the slot with the empty
  ceiling exactly as before.

## Semantics decisions

- **Key evaluation: exactly once per element, in input order**, before any
  element moves (Python's order). `sort_by_key` used to ask for keys in the
  order its recursive merge first needed them; a key function that traps on
  several elements now reports the first in list order. The lib-sort lane's
  trap-order test was rewritten to the new order and SPEC STANDARD-SORT-KEY-1
  says so.
- **Stable in both directions.** `reverse=True` complements the key word, so
  keys order descending while ties keep input order — not sort-then-reverse.
  The same holds with no key: `values.sort(reverse=True)` keeps `0.0` before
  `-0.0` when that is their input order (tested).
- **Floats**: signed zeros equal, every NaN after every ordered value (the order
  `list.sort()` already uses); `reverse=True` puts NaNs first, being the exact
  reverse of that total order. Python leaves NaN order undefined.
- **Traps**: the key loop runs to completion before the native sort starts, so
  a trapping key stops the program with no element moved. Python only promises
  "some state"; ours is "unchanged", which is also the state an allocation
  failure in the native sort leaves (it refuses before moving anything).
- **Effects**: the key is invoked like any callback value, so its bounded
  ceiling is charged to the caller. In practice a one-parameter key has no
  effect to declare (effects derive from parameters), and a key that declares
  its element `mut` is `E_SORT_KEY`, so keys are pure. "Called once" is
  therefore observable only through traps and cost; the guest test measures it
  with the step budget (a 1500-step key over 100 elements passes once per
  element and would exceed the budget at two calls per comparison).

## Diagnostics (LIST-SORT-KEY-2)

`E_SORT_KEY` for a key that is not a one-element callback of the list's element
type, declares `mut`, or returns an unordered type (the message names the
types); `E_TYPE` for a non-`bool` `reverse`; `E_CALL_ARGUMENT` with the accepted
signature for a positional operand, an unknown or repeated keyword (`cmp=` also
names the key alternative), and for named arguments on any other collection
method; `E_COLLECTION_METHOD` for a keyless sort of an unordered element.
DIAGNOSTIC-SITES-6's `sorted(..., reverse=True)` example, now valid, became
`cmp=True`.

## Lowering (LIST-SORT-KEY-3)

The checker builds the whole sort from checked nodes
(`prelude_builtins.keyedSortCall`): a key list allocated at the list's length,
one loop that reads each element into a local and appends `key(element)`, then
one internal buffer operation `.sort_keyed(source, keys, reverse)` that calls
`myl_native_list_sort_keyed` (`src/native_collections.c`):

- A numeric key becomes one order-preserving 64-bit word (sign flip for signed,
  reflected bits for binary64 with `-0` merged and NaN greatest), complemented
  for `reverse`. When the words span fewer values than there are elements, a
  **stable counting sort** gives each element, in input order, the next slot of
  its key (one counting pass, a prefix sum, one assigning pass; no
  comparisons), writing the slots into the key list's own storage. Otherwise,
  when every word minus the smallest fits above the position bits,
  `(word - low) << bits | position` is sorted by the lib-sort lane's integer
  engine, again in the key list's storage; wider keys take two 32-bit passes.
  Text and tuple keys sort (key, position) entries with a stable merge.
- In place (`values.sort`): the elements move along the permutation's cycles
  through element-sized temporaries — no second list of elements. A cycle walk
  is a chain of dependent loads, so the position table is first narrowed to 32
  bits (half the cache footprint) and a second cursor runs eight steps ahead on
  the same cycle, prefetching the element each step will move.
- Copy (`sorted`, and so `sort_by_key`): the elements are gathered in order
  from the original list into a new list allocated at its length, so no copy is
  made only to be permuted.
- The QBE emitter encodes the key's field kinds, widths and offsets (from the
  native layout) as two constants.

### A collector bug this exposed (QBE-INVOKE-ROOTS-1)

Under `--gc-stress`, a key that allocated (`lambda e: e.name + "!"`) freed the
list's texts. The cause is older than this lane and not specific to sorting:
`Emitter.loweredAllocates` (`src/qbe.zig`) decides whether an instruction is a
safepoint by scanning its lowered text for `call $<callee>`; an indirect call
is `call %v…`, so every call through a callback value was treated as
non-allocating and the caller pushed no roots across it. Any callback that
allocates could let a collection free objects only the caller's locals held.
The base compiler crashes (`SIGSEGV`) on a four-line program that calls an
allocating function through a local (`k = label; k(e)`) under `--gc-stress`.
The fix treats `call %` as allocating; the regression test is in
`src/prelude_builtins_test.zig`. This is `src/qbe.zig`, which the
root-liveness lane also works near — flag for the merge.

## Tests

- `tests/lang/keyed_sorting.my` (17 guest tests; `module` and `main` declared):
  stability with and without reverse, reverse-first evaluation, keyless reverse
  and signed zeros, float/NaN, `str` (multibyte), tuples, `i32`/`u8`/`u64`/`bool`
  keys, the wide two-pass path, empty and one-element lists, key-called-once via
  the step budget, a 3000-element stability check, copies leave input
  unchanged, `sort_by_key`, a generic caller, an expression receiver. All pass,
  also under `--gc-stress`.
- `src/prelude_builtins_test.zig`: diagnostics (LIST-SORT-KEY-2), `str` keys
  that allocate under `--gc-stress`, input-order traps for `sort` and `sorted`
  (LIST-SORT-KEY-3), and the invoke-roots regression.
- `src/stdlib_sort_test.zig`: `sort_by_key` trap order is now input order.
- `tests/native_collections_test.c`: the native keyed sort against a stable
  insertion reference — every key shape, both directions, in place and gather,
  80-byte elements, a list that is its own key list, refused shapes — clean
  under UBSan and ASan.

## Gate

Each full-gate step ran on the committed tree and was diffed against the base's
logs (`textsort-*.log`) with `gate_diff.py`. `/tmp` on this machine is a tmpfs
whose per-user quota other sessions had exhausted, and the guest-test runner
hard-codes `/tmp` (`src/native_test_session.zig:88`), so every step ran inside
the coordinator's `faketmp.sh` (a private `/tmp` on the main disk).

| step | base failures | lane failures | new |
|---|---:|---:|---|
| `zig build test` | 55 | 46 | 0 |
| `zig build test-qbe` | 2 | 2 | 0 |
| `zig build test-qbe-build` | 0 | 0 | 0 |
| `zig build fmt-check` | 0 | 0 | 0 |
| `zig build test-schematic` | 0 | 0 | 0 |
| `zig build test-byte-io` | 0 | 0 | 0 |
| `zig build test-docs` | — | 0 | green |

Guardian was green on every build and on the whole-tree pre-commit run. The
`test-lang` step inside `zig build test` ran 76 programs with none dropped,
`keyed_sorting` included. The failures that remain are the base's
half-finished migration (for example `removed names and punctuation report
their canonical migration` and `M1 mutates clause normalizes duplicate names`,
both failing on the base).

## Left

- A lambda key's type is read off a few body shapes (element, field path,
  arithmetic, negation, `len`, tuples of those); any other lambda body is
  typed `int`, so a `str` key from, say, a method call needs a named function.
  Full inference would need the lambda body checked before its slot is typed.
- `key=None` is not accepted, nor nested tuples or tuples with non-scalar
  fields as keys.
- Found, not fixed: an unannotated function passed to a generic callback
  parameter (`sort.sort_by_key(xs, by_rank)` where `by_rank` has no
  `effects()`) is `E_TYPE` "expected … effects(), found … effects(<all>)" on
  the base and on this branch. The concrete keyword forms are unaffected.
- Keys spread wider than the list take the packed merge sort and then the
  cycle walk, which stays memory-latency-bound; the suite has no wide-key
  keyed program to measure it against Zig.
- The QBE-INVOKE-ROOTS-1 fix is in `src/qbe.zig` (`loweredAllocates`), next to
  the safepoint code the root-liveness lane changes; check it survives that
  merge.
- The guest-test runner's hard-coded `/tmp` (above) makes the gate depend on
  the tmpfs quota.
