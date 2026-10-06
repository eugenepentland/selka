# S4 benchmark rows: contract

Six new microbenchmark rows. Each gates the new core against Zig ReleaseSafe and Rust,
and against the old core, as the 35 S2 rows and 5 applications do. They exercise
mechanisms the existing rows do not:
- recursive values;
- large records crossing calls;
- 2D nested lists;
- index-chasing with writes;
- float text;
- `byte_buffer` output.

## Common rules (as `benchmarks/runtime/expanded/collections/CONTRACT.md`)

**Interface.**
- **mylang** (`row.my`, built by both mylang compilers) takes `SIZE ITERATIONS SEED`;
  the references take `CASE SIZE ITERATIONS SEED`.
- **Validation:** SIZE >= 2, ITERATIONS >= 1, 1 <= SEED <= 1000000. Anything else
  exits with status 2.
- **Output:** exactly `CHECKSUM ELAPSED_NS\n` on stdout, and nothing on stderr.
- **Timing:** ELAPSED_NS is monotonic nanoseconds around the whole batch loop. mylang
  uses `extern def runtime_bench_now(host: Host) -> i64 effects(host)`, linked from
  `benchmarks/runtime/ports/native_clock.c`, exactly like
  `test/core/row_list_append.my`. Rust uses `std::time::Instant`, Zig
  `clock_gettime(1)`, Go `time.Now`/`time.Since`.

**Checksum.** `MOD = 1000000007`. Batches are numbered `0..ITERATIONS-1`, and
`checksum = (checksum + part(batch)) % MOD`. Arithmetic stays in signed 64-bit: every
formula below is bounded, so no language needs wrapping operations. Final printing is
outside timing.

**What counts as fair:**
- Everything a batch builds, it builds *and releases* inside timing.
- Normal dynamic containers and the default general-purpose allocator: Zig
  `std.heap.c_allocator` as the existing Zig ports use; Rust `std` only; Go `std`
  only with `GOMAXPROCS=1`.
- Not allowed:
  - arenas, pools or object reuse across batches;
  - unsafe or unchecked indexing (Rust `get_unchecked`, Zig `@setRuntimeSafety(false)`);
  - `noinline`/`inline(always)` attributes, intrinsics or SIMD by hand;
  - global mutable state.
- Natural optimizer elimination is allowed.
- Write each port the way a competent programmer in that language would. The goal is
  idiomatic code in every language running the *same algorithm* in the same order, so
  checksums agree exactly.

**Sizes.** The measured sizes are 4096 and 64, with seed 7. The verify probes are
`(2,1,1) (3,42,7) (17,999983,31) (64,3,7) (4096,2,7)`.

**Unit.** `element`: cycles are divided by `SIZE × ITERATIONS`.

## tree_build_walk (recursive values)

A binary tree is `Leaf` or `Node(left, value, right)`.
- **mylang:** a recursive union, written as `tests/lang` writes recursive values.
- **Rust:** `enum` with `Box`.
- **Zig:** a struct of optional pointers allocated with `c_allocator`, freed by an
  explicit recursive `destroy`.
- **Go:** pointers, with `nil` for `Leaf`.

```
build(lo, hi, base):
    if lo >= hi: return Leaf
    mid = (lo + hi) // 2
    return Node(build(lo, mid, base), (base + 13*mid) % 1009, build(mid + 1, hi, base))

walk(t, depth):
    Leaf -> 0
    Node(l, v, r) -> (depth + 1) * v + walk(l, depth + 1) + walk(r, depth + 1)

part(batch) = walk(build(0, SIZE, SEED + batch), 0) % MOD    # the tree is released in the batch
```

## record_pass (large records across calls)

`State` has twelve `i64` fields `f0..f11`.

```
mix(a, b) = (a * 31 + b) % 1009

advance(s, x) -> State:            # a function returning a new State; s is not modified in place
    t = mix(s.f0 + s.f5, x)
    f3 = mix(s.f4, x) if x % 3 == 0 else s.f4
    return State(f0=s.f1, f1=s.f2, f2=s.f3, f3=f3, f4=s.f5, f5=s.f6, f6=s.f7,
                 f7=s.f8, f8=s.f9, f9=s.f10, f10=s.f11, f11=t)

batch:
    s = State(fk = (SEED + batch + 7*k) % 1009 for k in 0..11)
    for j in 0..SIZE-1: s = advance(s, (SEED + batch + 13*j) % 1009)
    part = sum((k + 1) * s.fk for k in 0..11)
```

`advance` and `mix` are separate functions in every port. `advance` takes and returns
the record by value; in Rust and Zig that is `fn advance(s: State, x: i64) -> State`.

## grid_dp (2D nested lists)

```
W = isqrt(SIZE)  (largest w with w*w <= SIZE);  H = SIZE // W
cost[i][j] = (SEED + batch + 13*(i*W + j)) % 1009          # built as H rows of W, nested lists
dp[0][0] = cost[0][0]
dp[0][j] = dp[0][j-1] + cost[0][j]                          # j >= 1
dp[i][0] = dp[i-1][0] + cost[i][0]                          # i >= 1
dp[i][j] = cost[i][j] + min(dp[i-1][j], dp[i][j-1])         # i, j >= 1
part = dp[H-1][W-1] + sum(dp[H-1][j] for j in 0..W-1)
```

Both grids are nested dynamic lists: `list[list[int]]`, `Vec<Vec<i64>>`, a slice of
`c_allocator` slices in Zig, `[][]int64` in Go. They are built row by row inside
timing and released inside timing. Fill `dp` in row-major order.

## union_find (index-chasing with writes)

```
N = SIZE; parent = [0, 1, ..., N-1]                   # fresh list per batch
find(x): while parent[x] != x: parent[x] = parent[parent[x]]; x = parent[x]
         return x                                     # path halving, mutating parent
for j in 0..SIZE-1:
    a = (SEED + batch + 13*j) % N
    b = (SEED + 7*batch + 17*j + 1) % N
    ra = find(a); rb = find(b)
    if ra != rb: parent[ra] = rb
components = count of j in 0..N-1 with find(j) == j   # in increasing j, find still halves paths
rootsum = sum(find(j) for j in 0..N-1)                # a second pass, again in increasing j
part = (components * 1000003 + rootsum) % MOD
```

In mylang, `find` takes `parent: mut list[int]`. The order of every `find` call is
fixed, because path halving changes `parent`.

## float_format (float to text)

```
for j in 0..SIZE-1:
    k = (SEED + batch + 13*j) % 100003
    x = k + 0.125 * (1 + j % 7)          # a non-integral binary fraction below 100004
    text = shortest round-trip decimal of x, e.g. "12345.375", "0.125"
    h = 0; for each byte c of text: h = (h * 131 + c) % MOD
    part = (part + h + len(text)) % MOD
```

Each value is converted to a **fresh** text or string:
- mylang `str(x)` (or `f"{x}"` if it is the same text);
- Rust `x.to_string()`;
- Zig `std.fmt.allocPrint(c_allocator, "{d}", .{x})` and then `free`;
- Go `strconv.FormatFloat(x, 'f', -1, 64)`.

Every one gives Python's `repr(x)` for these values. Each text is folded and
released inside the batch.

## buffer_write (byte_buffer output)

```
buffer = fresh empty growable byte buffer
for j in 0..SIZE-1:
    v = (SEED + batch + 13*j) % 100003
    append the decimal ASCII digits of v, then b','; if j % 16 == 15 also append b'\n'
h = 0; for each byte c of buffer: h = (h * 131 + c) % MOD
part = (len(buffer) + h) % MOD                        # the buffer is released in the batch
```

The buffer and the digit appending in each language:
- **mylang:** a `byte_buffer`, using its idiomatic append path for the digits (record
  in NOTES.md exactly which, and whether it allocates an intermediate text).
- **Rust:** `Vec<u8>` with `write!(buf, "{}", v)` (`std::io::Write`).
- **Zig:** `std.ArrayList(u8)` on `c_allocator`, with its writer's `print("{d}", .{v})`.
- **Go:** `strconv.AppendInt`.
