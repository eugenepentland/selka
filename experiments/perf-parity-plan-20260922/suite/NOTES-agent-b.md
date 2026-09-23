# Agent B notes: fannkuch_redux, sort_*, sieve, matmul

Ports of SUITE.md sections 4, 7, 8 and 9 in mylang, Zig and Rust, plus mylang
variants. Every port and variant prints byte-identical stdout, checked with
`cmp` against `<bench>.expected`. Each `.expected` also matches an independent
CPython oracle (not part of the suite).

## Setup

- mylang: `.tmp/perf-audit-20260922/install-a3/bin/mylang` (tree 4d81f680),
  `build X.my -o BIN --cache-dir DIR`. That is the default ReleaseFast build:
  `--backend llvm --llvm-opt 3 --lto`. No other flags.
- Zig 0.17.0-dev.1683: `zig build-exe X.zig -O ReleaseFast`, run from `suite/`.
  The only helper I added is `common_b.zig`, which has one function, `print`:
  one `bufPrint` into a stack buffer, then one raw write, called once at the end.
- Rust 1.98.1: `rustc --edition 2021 -C opt-level=3 -C codegen-units=1
  -C target-cpu=native -C panic=abort`, std only.
- Timing: all timings are rough, E-core and unpinned-load. Each binary ran 3
  times under `taskset -c 12-19` (the i7-12700H E-cores), one process at a
  time, on a shared machine. `/usr/bin/time -f '%e %M'` gives wall time with
  10 ms resolution, and peak RSS. I had no `perf` access
  (`perf_event_paranoid=4`), so the codegen observations come from `objdump` of
  `--keep-symbols` builds and `mylang emit-qbe` IL. Those builds were made in
  my work directory; the suite binaries have no symbols.

## Files

| benchmark | files | expected |
| --- | --- | --- |
| fannkuch_redux | `fannkuch_redux.{my,zig,rs}`, `fannkuch_redux_tuned.my` | `73196` / `Pfannkuchen(10) = 38` |
| sort_builtin | `sort_builtin.{my,zig,rs}` | `321 1074397298 2147483273` / `318620633` |
| sort_quick | `sort_quick.{my,zig,rs}` | same two lines as sort_builtin |
| sort_records | `sort_records.{my,zig,rs}`, `sort_records_sorted.my` | `0 99999` / `551029697` |
| sieve | `sieve.{my,zig,rs}`, `sieve_tuned.my` | `1270607` |
| matmul | `matmul.{my,zig,rs}`, `matmul_flat.my`, `matmul_tuned.my` | `62489758` / `31249063032` |

Other files:
- `common_b.zig`: the Zig output helper.
- `repro/agent_b_bug_sorted_key_identity_internal_error.my`: compiler bug.
- `repro/agent_b_bug_sorted_key_callback_value_internal_error.my`: compiler bug.
- `repro/agent_b_diag_generic_callback_lambda.my`: diagnostic friction.

There is no `sieve_bytes.my`, for two reasons. `byte_buffer`, the only mutable
byte container, has no indexed store (`buf[i] = v` is `E_COLLECTION_METHOD`).
And `list[bool]` already stores one byte per element: `bool` has layout size 1,
and peak RSS is 21.9 MB for 20 M flags. A `list[u8]` sieve measured the same
0.54 s and the same RSS, so it is not a materially different container.

## Timing and peak RSS

| benchmark | port | 3 runs, wall s | peak RSS | median vs Zig |
| --- | --- | --- | --- | --- |
| fannkuch_redux | zig | 0.23 0.22 0.22 | 2.0 MB | 1.0 |
| | rs | 0.23 0.23 0.22 | 2.3 MB | 1.0 |
| | my | 4.13 4.12 4.13 | 2.4-2.7 MB | **18.8x** |
| | my `_tuned` ([10]int arrays) | 0.21 0.21 0.21 | 2.6-2.8 MB | 0.95x |
| sort_builtin | zig (`std.mem.sort` = block sort) | 0.28 0.29 0.29 | 16.1 MB | 1.0 |
| | rs (`slice::sort`) | 0.09 0.12 0.09 | 25.6 MB | 0.31x |
| | my (`values.sort()`) | 0.37 0.38 0.38 | 34.2 MB | 1.3x |
| sort_quick | zig | 0.25 0.24 0.24 | 16.0 MB | 1.0 |
| | rs | 0.22 0.21 0.21 | 17.8 MB | 0.88x |
| | my | 0.45 0.48 0.46 | 18.7 MB | 1.9x |
| sort_records | zig | 0.16 0.16 0.16 | 16.0 MB | 1.0 |
| | rs | 0.07 0.07 0.07 | 25.6 MB | 0.44x |
| | my (`sort.sort_by_key`) | 1.01 1.00 1.00 | **224.8 MB** | **6.3x** |
| | my `_sorted` (`sorted(key=lambda)`) | 0.26 0.26 0.26 | 50.0 MB | 1.6x |
| sieve | zig | 0.12 0.12 0.12 | 19.9 MB | 1.0 |
| | rs | 0.12 0.11 0.12 | 21.6 MB | 1.0 |
| | my | 0.54 0.56 0.54 | 21.9 MB | 4.5x |
| | my `_tuned` (loop in helper) | 0.29 0.31 0.31 | 21.9 MB | 2.6x |
| matmul | zig | 0.05 0.05 0.05 | 6.3 MB | 1.0 |
| | rs | 0.13 0.13 0.13 | 8.0 MB | 2.6x |
| | my (nested lists) | 2.62 2.61 2.63 | 12.2 MB | **52x** |
| | my `_flat` | 1.47 1.53 1.51 | 9.0 MB | 30x |
| | my `_tuned` (row comprehension) | 0.50 0.49 0.48 | 30.4 MB | 9.8x |

The sort_builtin, sort_quick and matmul_flat mylang rows come from the final
binaries. They were rebuilt after an unused loop variable was renamed to `_`;
earlier runs of the pre-rename code measured 0.42, 0.50 and 1.48 s.

For the harness owner:
- `matmul.zig` sits at the bottom of the 0.05-1.0 s target range on an E-core.
  On a P-core it is probably below the range. I did not change the size.
- The Rust matmul index loop keeps bounds checks in the inner loop, which
  blocks vectorization (0.13 s). The same loop written with row slices and
  `iter_mut().zip()` ran 0.03 s (1 run, explore only, not in the suite).
- Zig's `std.mem.sort` is an in-place block sort, while Rust's stable sort is
  driftsort. That accounts for the 3x Zig/Rust spread on the two stable-sort
  benchmarks.

## Per benchmark

### fannkuch_redux

This is the C algorithm verbatim. The mylang port uses three `list[int]`s and
`shift_right(k + 1, 1)` for `>> 1`, and returns `tuple[int, int]`. The Zig and
Rust ports use `usize` slices/Vecs; Rust uses `copy_from_slice` and
`perm.swap`, Zig uses `@memcpy` and `std.mem.swap`.

**Performance.** The mylang port is 18.8x slower than Zig. Each `perm[i] = ...`
lowers to an out-of-line call to `myl_native_list_set`. That call does a bounds
check, loads `list->element->size`, multiplies, and takes an indirect jump
through a size-switch table. Before every call, the function's GC root chain is
republished: 22 four-word root records, which is 88 stack stores, then the
chain head is stored to `heap+0x268` and restored after the call. The emitted
IL shows `fannkuch` has 22 root slots fed from about 24 distinct temporaries.
There is one slot per list-valued expression, not one per source list; only 3
lists are live. `list_set` never allocates, so none of this publication is
needed.

Two experiments confirm it:
- Moving the flip loop into a helper `count_flips(perm: mut list[int])`
  (explore, 1 run) cut the time from 4.13 s to 1.95 s. The helper publishes 7-8
  records per write instead of 22.
- `fannkuch_redux_tuned.my` stores the arrays as `[10]int` values and writes
  them with `perm = replace(perm, i, x)`. It runs 0.21 s, Zig/Rust parity:
  `replace` on a frame-resident array compiles to a plain store with no roots.
  One caveat: `n` is fixed by the array type there, so it is a compile-time
  constant, unlike the `opaqueN`/`black_box` n in the Zig and Rust ports.

**Friction.**
- `(k + 1) >> 1` fails with `E_EXPRESSION: expected an expression` at the
  second `>`, with no hint pointing to `shift_right`. The docs say `<<` gets a
  targeted hint; `>>` does not.
- There is no walrus, so `while (k = perm[0]) != 0` became a read before the
  loop and at the end of the body.
- Swapping two slots with `xs[i], xs[j] = xs[j], xs[i]` fails with
  `E_SYNTAX: unexpected token; expected a newline`. Tuple assignment only
  accepts names (`a, b = b, a` works), so the port uses a temp.
- A fixed array has no indexed store: `arr[i] = v` fails with
  `E_LIST_TYPE: operation requires a managed list`. It must be written
  `arr = replace(arr, i, v)`, which is clunky but fast.

### sort_builtin, sort_quick

The data is generated by a pure step function `xorshift(x: u64) -> u64`
(`bit_xor`/`shift_left`/`shift_right` on `u64`) in all three languages. Values
are `i64`.

**sort_builtin performance.** Generation plus checksum costs about 0.02 s in
every language. I measured this with the sort removed (explore, 2 runs each).
That leaves the sort itself at about 0.36 s in mylang, 0.27 s for Zig's block
sort and 0.07-0.10 s for Rust's driftsort.

`myl_native_list_sort` in `src/native_collections.c` is a generic bottom-up
merge. It starts at width 1, with no small-run insertion pass, so it makes 21
full passes over 2 M elements. Each comparison goes through
`compare_element(..., size, order)` and each move through `copy_element`
(switch on size). It also `malloc`s an n-element scratch buffer, which is why
peak RSS is 34 MB against 16 MB for Zig's in-place sort.

**sort_quick performance.** mylang is 1.9x slower than Zig. Each swap does two
`list_set` calls, each with 8 root records. Each read does a sign test for
negative-index normalization, then a bounds check against a reloaded header
length. Recursion also pays the frame protocol (a stack-limit check and a
frame-record link) on every call. Two variants each gained only about 5%:
putting the swap in a helper (0.48/0.46 s), and using
`wrapping_add`/`wrapping_sub` on the cursors (0.49/0.48 s). Neither is
materially different, so there is no `sort_quick_tuned.my`.

**Friction.**
- `list.sort()` has no `key=` or `reverse=`. `records.sort(key=lambda r: r.key)`
  fails with `E_CALL_ARGUMENT: keyword arguments require a declared function or
  record constructor`, and that error then cascades into `E_LAMBDA_CONTEXT`.
- Recursion with `mut`: the parameter is `xs: mut list[int]` and each call is
  `quicksort(mut xs, lo, j)`. `E_MUTATION_MARKER` states the exact fix at both
  places, so this is cheap friction.
- Reassigning parameters (`lo = i`) works.

### sort_records

`sort_records.my` uses `sort.sort_by_key(records, by_key)`, the spelling
SUITE.md names. Zig uses `std.mem.sort` with a `lessThan` on `key`; Rust uses
`sort_by_key(|r| r.key)`. The fields are `i64` everywhere, to match mylang's
16-byte `record Rec: key: int, id: int`. `sort_records_sorted.my` is the Python
spelling, `sorted(records, key=lambda r: r.key)`.

**Performance.** `sort.sort_by_key` is a recursive top-down merge in
`src/stdlib/sort.my`. Every level copies both halves with slices
(`values[0:middle]`) and builds a fresh output list by `append`
(`merge_by_key`), so about 20 levels each allocate the 16 MB data set 2-3
times. The result is 1.0 s and a **224.8 MB peak RSS**, against 16 MB for Zig.
Garbage made of a few very large lists piles up because collection is
triggered by an object-count threshold, not by bytes.

The prelude keyed `sorted` is a bottom-up merge into one reused scratch list:
0.26 s and 50 MB, 4x faster than the stdlib function. The key callback is
inlined in both mylang versions; the only indirect calls in either binary are
in runtime startup.

A decorate-to-int formulation, `key * 2^20 + id` sorted with `list.sort()`
then decoded, runs 0.17 s and 18.5 MB, Zig parity (explore, 1 run). It is not
in the suite because it is not a key sort. What it shows is that the gap is
the record/keyed path, not the merge itself.

**Friction.**
- `sort.sort_by_key(records, lambda r: r.key)` fails with
  `E_LAMBDA_CONTEXT: lambda requires an expected callback type; annotate the
  destination or pass it to a callback parameter`. A lambda cannot fill a
  generic callback parameter (`key: def(T) -> int effects()`), even though
  `docs/lambdas.md` says a lambda belongs directly in a callback argument. The
  hint is wrong: the lambda *is* in a callback parameter. A valid
  `sorted(..., key=lambda ...)` on a later line is then also reported
  (a cascade). The workaround is a named `def by_key(r: Rec) -> int effects()`.
  Repro: `repro/agent_b_diag_generic_callback_lambda.my`.
- One program cannot use both `sort.sort_by_key(records, f)` and
  `sorted(records, key=g)`: that crashes the compiler (see compiler bugs
  below). This is why the two spellings live in two files.

### sieve

The ports are all the SUITE loop. mylang builds the flags as
`[True for _ in range(n + 1)]`; Zig uses `alloc` + `@memset`; Rust uses
`vec![true; n + 1]`.

**Performance.** mylang is 4.5x slower. `flags[j] = False` is again a
`list_set` call, with a root chain of 7 records in `main`, plus a position
store, a sign test and an overflow check on `j + i`. The loop is partly memory
bound, which hides some of the cost.

`sieve_tuned.my` moves only the crossing-off loop into
`cross_off(flags: mut list[bool], start, step, n)`, which publishes 2 records
per write. It runs 0.29-0.31 s, 1.9x faster than the idiomatic port. Changing
`j + step` to `wrapping_add` was within noise; `wrapping_add` alone in `main`
gave 0.46 s.

**Friction.** `[True] * (n + 1)` fails with
`E_TYPE: expected list[bool], found int`. List repetition is unsupported, and
the message does not say so.

### matmul

`matmul.my` is the SUITE line written literally,
`c[i][j] = c[i][j] + aik * b[k][j]`, over `list[list[float]]`.
`random_matrix(n, seed) -> tuple[list[list[float]], int]` threads the LCG
state. `matmul_flat.my` uses one `list[float]` per matrix indexed `i * n + j`.
The Zig and Rust ports are flat index loops, and Zig and Rust use a small
`Lcg` struct.

**Performance.** The nested port is 52x slower than Zig and the flat port 30x.
LTO did inline `list_set` here, but every element store still:
- publishes the root chain: 19 records in `matmul.my`, 12 in `matmul_flat.my`;
- dispatches through the runtime element-size jump table;
- reloads the list headers, with a sign test and a bounds check per index.

On top of that, every float op carries NaN canonicalization, a
`vucomisd x,x; jp` after the multiply and again after the add. Together with
the position stores (`mov [frame], <line>` two or three times per element),
this rules out vectorization. Zig vectorizes this loop.

Formulations measured, all byte-identical output. `_tuned` numbers are from
the suite build; the rest are from explore builds, 1 run each.

| formulation | time |
| --- | --- |
| hoist `ci = c[i]`, `bk = b[k]` (the Python idiom) | 2.44 s |
| in-place j loop in a helper, nested | 0.78 s |
| in-place j loop in a helper, flat | 0.81 s |
| dot products over a transposed B (inner loop only reads) | 0.51 s |
| flat dot products, column reads | 0.49 s |
| **row rebuilt by a comprehension per k (`_tuned`)** | **0.48-0.50 s** |

In the `_tuned` form, a comprehension over `range(n)` reserves n up front and
its appends are inline stores with no root publication. Its inner loop still
reloads both list headers every element and does two bounds checks, three
position stores, two NaN checks, and a length plus generation-counter update.
It also allocates about 1 GB of short-lived 4 KB rows, hence the 30 MB peak.

**Friction.**
- `[x + y for x, y in zip(a, b)]` fails with `E_SYNTAX: expected in`. A
  two-name binding is not allowed in a comprehension, although
  `for x, y in zip(...)` works as a statement.
- `_` is a real binding in `for` loops and comprehensions. Nested
  `for _ in ...` or `[[0.0 for _ in r] for _ in r]` fails with `E_SHADOWING`,
  whereas in tuple destructuring `_` binds nothing. Python code nests `_`
  routinely.
- Tuples work well: tuple returns and destructuring into an existing binding
  (`b, seed = random_matrix(n, seed)`). The tree's `CLAUDE.md` still says
  "No tuples", which is stale.

## Cross-cutting performance observations (ranked)

1. **Indexed list writes are the dominant cost wherever they sit in a hot
   loop.** Each `xs[i] = v` does three things:
   - republishes a GC root chain with one 4-word record per list-valued
     temporary in the function. The counts were 22 (fannkuch), 19 (matmul),
     12 (matmul_flat), 8 (quicksort), 7 (sieve `main`), and 2 in a 2-parameter
     helper;
   - calls or inlines `myl_native_list_set`, which dispatches on the *runtime*
     `element->size` through a jump table;
   - restores the chain afterwards.

   Nothing in `list_set` can allocate or collect. The publication is explicit
   in the emitted IL (`storel %rootN` ... `storel %root_mark`), so LLVM cannot
   drop it. Moving the loop into a small helper alone gives 1.9-3.4x. Agent A's
   `repro/agent_a_perf_slot_write_*.my` measures the same effect.
2. **Fixed arrays avoid all of it.** `[N]int` plus `replace` compiled to plain
   stores and gave Zig parity on fannkuch. That is strong evidence the gap is
   the managed-list store protocol, not the arithmetic or bounds checks.
3. **Per-element overheads in read and append loops.** These are:
   - a sign test for negative-index normalization plus a bounds check on every
     index;
   - list header (length and storage) reloads every iteration, because the
     position stores and appends may alias them;
   - `mov [frame], <source position>` stores per statement;
   - NaN canonicalization after every float op;
   - a `generation` counter increment on every append.

   These block vectorization in matmul even in the best formulation, 9.8x Zig.
4. **The builtin `list.sort()` is 1.3x Zig's block sort and 4-5x Rust's.** It
   is a generic runtime merge: no insertion-sort runs, a per-compare
   size/order switch, and an n-element malloc'd buffer (2x the data's RSS).
5. **`sort.sort_by_key` allocates about 20 copies of the data** (recursive
   slices plus fresh output lists) and reached 225 MB peak for a 16 MB input.
   The prelude `sorted(key=...)` does the same job in a quarter of the time and
   memory. The stdlib function could simply delegate to it, once the compiler
   bug below is fixed.

## Compiler bugs (repros in `repro/`)

1. `agent_b_bug_sorted_key_identity_internal_error.my`: `sorted(xs, key=f)`
   over a `list[int]`, where `f` returns its argument unchanged (or
   `key=lambda v: v`), passes `check` but fails to lower:
   `mylang: host failure: InternalError`, exit 2. This happens for
   `run`/`build` (llvm and qbe backends) and for `dump-bytecode`, so it is
   before any backend. A non-identity key over the same list works.
2. `agent_b_bug_sorted_key_callback_value_internal_error.my`: `sorted(xs,
   key=...)` fails with the same InternalError when the program also
   materializes any callback value of the key's type `def(T) -> int effects()`.
   That covers a different function assigned to a local, a function passed to
   `sort.sort_by_key`, or a key lambda. Here `dump-bytecode` succeeds and
   `emit-qbe` fails, so this one breaks in the bytecode -> QBE IL step, which
   both backends go through (`build --backend llvm` and `qbe` both fail).
   Dropping `effects()` from the other function, so the callback type differs,
   makes it build (prints 9).

Both repros fail identically with `install-a3`, `.tmp/perf-audit-20260922/install`
and the main checkout's `zig-out/bin/mylang`. None of them prints a stack
trace, and there is no environment knob to get one.

There was no wrong output and no unexpected trap in any benchmark port.

## Minor notes

- `mylang check` writes `.mylang-cache/{frontend,semantic}` into the current
  directory, and `suite/.mylang-cache` now exists from the agents' check runs.
  `build` and `run` were always given `--cache-dir` in my work directory.
- `mut c[i]` (an expression, not a name) is accepted as a `mut` argument.
- The `.my` files are not `mylang fmt`-canonical in exactly one respect: the
  two blank lines after the file-header comment. The formatter has no
  file-level comment, so it would glue the header onto the first declaration.
  The existing `perf-parity-audit-20260921/micro/*.my` files fail
  `fmt --check` the same way.
- The headerless `import sort` form in `sort_records.my` is accepted by
  `check`, `build` and `run`. `fmt`, `dump-bytecode` and `emit-qbe` reject it
  with `E_SYNTAX: unexpected token; expected def`; `fmt-module` works.
- `max(a, b)` with two scalars, `list(range(n))`, conditional expressions and
  f-strings all worked first time.
