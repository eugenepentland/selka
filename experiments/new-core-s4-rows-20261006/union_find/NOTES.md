# union_find: notes

Contract: `../CONTRACT.md`, section union_find. Verified against `oracle.py` for all five arms at all five probes
(`rows.py verify union_find`: PASS). Calibrated iterations (`rows.py calibrate union_find`, CPU 12): 4096 -> 698,
64 -> 37157.

## Idioms per language

`parent` is one fresh list per batch (`0..N-1`), built and released inside the batch. `find` does path halving with
`parent[x] = parent[parent[x]]; x = parent[x]` and the union links the roots as `parent[ra] = rb`. Per batch the order is
fixed: the `SIZE` unions (`a` computed, then `b`, then `ra = find(a)`, then `rb = find(b)`, then the link), then the
components pass (increasing `j`, one `find(j)` each), then the rootsum pass (a second increasing `j` pass).

| arm | `parent` | `find` | release |
|---|---|---|---|
| mylang (`test/core/row_union_find.my`) | `list(range(size))` | `def find(parent: mut list[int], x: int) -> int`; call sites write `find(mut parent, a)`; `x` is reassigned in the body | reference count, at function exit |
| Rust | `(0..size).collect::<Vec<usize>>()` | `fn find(parent: &mut [usize], mut x: usize) -> usize`, called as `find(&mut parent, a)` | drop at function exit |
| Zig | `c_allocator.alloc(usize, size)` filled with the identity | `fn find(parent: []usize, start: usize) usize` | `defer a.free(parent)` |
| Go | `make([]int, size)` filled with the identity | `func find(parent []int, x int) int` | garbage collector (`runtime.GOMAXPROCS(1)` in `main`) |

- **Threading `parent` in mylang:** `batch_result` owns `parent` as a local and passes it as `find(mut parent, ...)` at
  every call (four call sites). Elements are `int` (64-bit), the same width as the `usize`/`int` elements of the references.
- **Index arithmetic:** `a = (seed + batch + 13*j) % N`, `b = (seed + 7*batch + 17*j + 1) % N`, all non-negative signed
  64-bit; mylang and Go use `%`, Rust `%` on `i64` then `as usize`, Zig `@mod` then `@intCast`. `components * 1000003 +
  rootsum` is at most about 4096 * 1000003 + 4096 * 4095, far below 2^63.
- **Validation:** same rules and same battery as grid_dp (wrong case, 1 1 7, 64 0 7, 64 1 0, 64 1 1000001, abc 1 7,
  -4 1 7, a missing argument): every arm exits 2 with empty stdout and stderr.

## Left open by the contract

Nothing material. `parent` is never grown: every port creates it with all `N` elements at once (`list(range(size))`,
`collect`, `alloc`, `make`).

## Findings

1. **No refusal, no wrong answer.** Both mylang compilers build `test/core/row_union_find.my`; the new core accepts `find`, `batch_result`,
   `parse_number` and `main` (`mylang-core coverage`; only the extern `runtime_bench_now` is "refused extern", as for the
   template). All five arms agree with the oracle. No `new-core-refusal.txt`.

2. **How the new core threads `mut parent`:** `my.row::find` is emitted as an out-of-line function returning
   `{ i64, ptr }` (the root and the list, handed back through the `mut` convention); the four `find` calls in
   `batch_result` are not inlined. Both element writes (`parent[x] = ...` in `find`, `parent[ra] = rb` in
   `batch_result`) test `refcount == 1` first and call `myl_core_list_copy` only on the shared path, so unlike
   grid_dp's nested write they do not copy per write.
   Indicative (user cycles per element incl. startup, CPU 12, noisy, not a measurement): 4096: old 100, new 103,
   Rust 59, Zig ReleaseSafe 52, Go 57; 64: old 96, new 91, Rust 50, Zig 45, Go 48. No cliff here; the new core
   matches the old core and is about 2x Zig/Rust.

3. **No language limitation hit.** `while parent[x] != x:` with the parameter `x` reassigned in the body, `list(range(n))`, and
   `find(mut parent, x)` as a call inside a condition (`if find(mut parent, j) == j:`) are all accepted by both
   compilers.
