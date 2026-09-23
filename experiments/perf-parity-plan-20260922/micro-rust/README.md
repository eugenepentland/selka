# Rust ports of the matched micro-kernel suite

Rust arms for the eleven kernels in
`experiments/perf-parity-audit-20260921/micro/`. Each `<name>.rs` runs the same
algorithm as `<name>.zig`: same loop structure and bounds, the same data
structures in their ordinary Rust form, and loop bounds hidden behind
`std::hint::black_box` where Zig uses `common.opaqueN`. Each prints a line that is
byte-identical to what the Zig and mylang kernels print. `<name>.expected` holds
that line (the exact stdout bytes, trailing newline included). The two variants
print their kernel's line: `dict_count_entry.rs` matches `dict_count.expected`,
and `alloc_churn_reuse.rs` matches `alloc_churn.expected`.

## Build and check

```bash
rustc --edition 2021 -C opt-level=3 -C codegen-units=1 -C target-cpu=native \
      -C panic=abort -o OUT name.rs
./OUT | cmp - name.expected
```

`std` only, no `unsafe`, no crates. All 13 files compile without warnings.
They were checked three ways. Every timed run of every Rust, Zig and mylang
binary (111 runs) printed the same bytes as the Zig reference. The 54 runs of
the final Rust binaries and the attribution variants all matched `.expected`.
Every file was also built and run with `-C overflow-checks=on` and printed the
same line, so no kernel overflows and the harness's checked arm will qualify.

Toolchains: rustc 1.98.1 (LLVM 22.1.8); zig 0.17.0-dev.1683+5ceec001b (its
bundled clang/LLVM is also 22.1.8); mylang
`/home/epentland/ai/canopy/mylang/.tmp/perf-audit-20260922/install-a3/bin/mylang`
(sha256 `133ceb415a91147d…`). mylang's default `build` is `--mode ReleaseFast`,
which means `--backend llvm --llvm-opt 3 --lto` with checked arithmetic, the
suite's `mylang-o3-lto` arm.

## How the ports are written

- **Loops.** Zig's `while (i < n) : (i += 1)` over `i64` becomes
  `for i in 0..n` over `i64`: the same trip count and the same induction type.
  Zig's `for (items) |v|` becomes `for &v in &values`. `bytes_scan` keeps an
  index loop (`data[k]`) because indexing is what that kernel measures. LLVM
  removes the bounds check there, and in every other loop whose index it can
  prove in range.
- **`%`.** Every dividend in the suite is non-negative, so Rust's truncating
  `%` gives the same value as Zig's `@mod` and mylang's floor `%`. It does not
  always cost the same; see finding 3. `i64::rem_euclid` is the op-for-op floor
  mod if the harness wants it.
- **Output.** Every port prints through a tiny `#[inline(never)] fn emit1(value:
  i64)` (or `emit2`) that makes one `println!`. The helper takes its argument by
  value, like `common.zig`'s `emit1`. This matters: `println!("{}", count)`
  written in `main` borrows `count`. For `bytes_scan` that leaves a conditional
  stack store inside the hot loop, which blocks vectorisation. The loop then
  becomes scalar and branchy: 47.6 ms, measured in the same window as Zig's
  61.8 ms, against 31.7–38.6 ms for the by-value build in two later windows
  (rough). In the other twelve files the hot loop is identical either way.
- **Library defaults.** The global allocator is glibc `malloc`, the Rust
  default. `HashMap` uses its default hasher, randomly keyed SipHash-1-3.
  `Vec<T>` stands in for `ArrayList(T)`, and `HashMap<&str, i64>` for
  `StringHashMap(i64)`: the map borrows its keys, just as Zig's stores slices
  it does not own. Rust release builds wrap on overflow and keep bounds checks.
  Zig ReleaseFast has neither.

## Results

**Rough, E-core.** Every figure is the median of 3 runs, in ms. Each run was
`/usr/bin/time -f '%e s %M KB' taskset -c 12-19 BIN`, one process at a time, on
the Gracemont E-cores 12-19 of an i7-12700H. Wall-clock time was read around a
blocking wait (it includes about 1–2 ms of `time`/`taskset` exec). The `%e`
values agreed at their 10 ms resolution. Other agents were building and timing
on the same E-cores during the first window.

The **Rust** column is the final files, measured in a later, quieter window.
**Rust (same window)** is an earlier build that printed with `println!`. It was
run interleaved with the Zig and mylang binaries, and its hot loops are
instruction-identical to the final files except in `bytes_scan`. Between the two
windows, identical loops differed by 0.91–1.08x. Treat any Rust/Zig difference
under about 10% as noise, and take ratios from the same-window column.

| kernel | Rust port uses | algorithmic match to `<name>.zig` | Rust | Rust (same window) | Zig | mylang |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| intloop | `for i in 0..n` (`i64`), `(total + i * 7) % 1000003` | exact | 156 | 162 | 171 | 166 |
| calls | `#[inline(never)] fn step(a, b) -> i64 { (a + b) % 1000003 }` | exact; `%` skips the sign fix-up Zig's `@mod` keeps in the out-of-line callee | 140 | 152 | 175 | 187 |
| fib | plain recursive `fn fib(n: i64) -> i64` | exact (on both sides LLVM turns the second recursive call into a loop; Zig also sets up a frame pointer) | 49 | 51 | 56 | 149 |
| records | `#[derive(Clone, Copy)] struct Vec3 { x, y, z }` by value into an inlinable `norm1` | exact; named `Vec3` so it does not shadow the prelude `Vec`; `%` skips the fix-up Zig keeps here | 103 | 107 | 125 | 117 |
| list_append_sum | `Vec<i64>::new()` + `push`, fold with `for &v in &values` | exact loop; `Vec` doubles where `ArrayList` grows to 1.5x + 8; glibc vs `smp_allocator` (both grow big blocks with `mremap`); both folds vectorised | 71 | 66 | 67 | 84 |
| list_records | `Vec<Row>` (4 x `i64`, 32 B) + `push`, ten passes of `for row in &rows` | exact loop; same growth and allocator note; both folds vectorised | 65 | 60 | 60 | 85 |
| dict_count | `Vec<String>` keys from `format!`; `HashMap<&str, i64>`; `get` then `insert` | exact algorithm (two lookups per step); the hasher and table implementation differ unavoidably | 107 | 118 | 49 | 97 |
| dict_count_entry | as `dict_count`, with `*counts.entry(key).or_insert(0) += 1` | matches `dict_count_getorput.zig` (one lookup) | 62 | 65 | 32 (getOrPut) | — |
| str_build | `Vec<u8>` + `extend_from_slice(b"mylang!\n")`, then the sampled fold | exact loop; same growth-policy note | 64 | 61 | 59 | 69 |
| alloc_churn | a fresh `Vec::new()` per batch, 16 `push`es, fold, drop at scope end | same loop, different memory strategy (std has no arena); this is the matched arm, and its strategy matches `alloc_churn_gpa.zig` | 149 | 163 | 109 (arena) / 97 (gpa) | 331 |
| alloc_churn_reuse | one `Vec`, `clear()` at the top of each batch | the arena's `reset(.retain_capacity)`: no allocator call after batch 1 | 76 | 83 | 109 (arena) | — |
| float_loop | `x = x * 0.999 + (i as f64).sqrt()`, print `(x * 1000.0) as i64` | exact (rustc never contracts to FMA; the saturating cast is in range) | 71 | 74 | 76 | 76 |
| bytes_scan | `Vec<u8>` + `extend_from_slice` (64 B x 131072), `&[u8]` view, index loop | exact loop; Rust's loop vectorises and Zig's does not (finding 2) | 32 | 48\* | 62 | 97 |

\* The same-window `bytes_scan` figure is the `println!` build, whose loop is
scalar and branchy. It still beat Zig's scalar branchless loop, because the
64-byte payload repeats and the branch predicts perfectly. The final
vectorised build measured 38.6 ms in a busier window.

## Where the Rust arm differs from Zig

1. **`dict_count` is slower in Rust, mainly because of the hasher.** In the
   same window, `get` + `insert` ran at 118 ms against Zig's 49 ms (2.4x), and
   `entry` at 65 ms against `getOrPut`'s 32 ms (2.1x). Swapping SipHash-1-3 for
   an FxHash in a scratch build (both sides measured in the final window) took
   107 → 66 ms and 62 → 41 ms. So the default hasher is about 70% of the gap to Zig's Wyhash.
   The remaining ~1.3x is not isolated. Candidates: each key compare is a call
   to glibc `bcmp` through the GOT (Zig's static binary uses its own
   `StringContext.eql`), and hashbrown's probing and layout. Because SipHash is
   keyed randomly per process, Rust's dict timings also vary from run to run
   (100–119 ms). mylang's dict, at 97 ms, is now faster than Rust's default
   `HashMap` on this kernel. The suite's `results.md` still describes an O(n)
   association list costing 15.9 s, which predates this install.
2. **`bytes_scan` is faster in Rust because of vectorisation, not the
   language.** Both toolchains use LLVM 22.1.8. Rust's count loop vectorises
   (`vpcmpeqb`/`vpaddq`). Zig's does not: its optimised IR is a scalar
   `icmp`/`zext`/`add` chain interleaved 8 ways, which compiles to
   `cmp`/`sete`/`add`, and the Zig binary contains no `vpcmpeqb` at all. The
   suite README says "LLVM auto-vectorises the Zig index loop", which does not
   hold for this Zig build. Rust ran at 32 ms (38.6 ms even in a busier
   window) against Zig's 62 ms. See **Output** above for how a `println!`
   borrow undoes Rust's advantage.
3. **`calls` and `records` are faster in Rust because of `%` versus `@mod`.**
   Rust's `%` is a bare signed remainder by magic multiply. Zig's `@mod` keeps
   a three-instruction sign fix-up (`sar`/`and`/`add`) wherever LLVM cannot
   prove the dividend non-negative, and mylang's floor `%` does the same. That
   happens in `calls`' out-of-line `step` and in the `records` loop, where Zig
   has five fix-ups. `intloop` has none: there LLVM proves the dividend
   non-negative and drops the fix-up. Same-window ratios are 0.87x and 0.86x
   of Zig. A scratch A/B with `rem_euclid`, whose fix-up
   (`lea`/`test`/`cmovns`) costs the same, took 140 → 166 ms and
   103 → 121 ms. That is 0.95x and 0.96x of Zig across windows, which is
   parity once the drift is allowed for. The files keep `%` because every
   operand is non-negative; switch to `rem_euclid` if the harness wants
   op-for-op floor mod.
4. **`fib` and `calls` pay for Zig's frame pointer.** Zig ReleaseFast compiles
   with `"frame-pointer"="all"`, while rustc omits frame pointers in user
   code. Apart from that, `fib` is the same code shape on both sides (0.91x
   same-window, within noise).
5. **`alloc_churn` uses a different memory strategy, by necessity.** Rust's
   `Vec` grows 4 → 8 → 16: one `malloc`, two `realloc`s and one `free` per
   batch. Zig's `ArrayList` grows 9 → 23, inside an arena. Same-window, Rust
   ran at 163 ms against the arena's 109 ms (1.50x) and `gpa`'s 97 ms (1.68x).
   A scratch build using `Vec::with_capacity(16)` per batch ran at 76.5 ms,
   the same as `alloc_churn_reuse` (75.8 ms). Its disassembly shows it still
   calls `__rust_alloc` and `__rust_dealloc` in every batch. Out-of-order
   execution hides that tcache `malloc`/`free` pair behind the loop's serial
   `%` chain, but it cannot hide the growth path (`grow_one` and the two
   `realloc`s). That growth path is what `alloc_churn.rs` pays for.
   `alloc_churn_reuse` runs at 0.76x of Zig's arena same-window.
6. **Everything else is at parity**: `intloop`, `list_append_sum`,
   `list_records`, `str_build` and `float_loop` are all within the window drift.
   On the buffer kernels Rust's peak RSS is about 2 MB above Zig's (for
   example 127,304 KB against 125,280 KB for `list_append_sum`). That is most
   likely the dynamically linked glibc and ld.so image, since Zig's binaries
   are static. On the tiny kernels both read about 2 MB. That is `taskset`'s
   own image under `/usr/bin/time`: `taskset -c 12-19 /bin/true` reads
   2,024 KB.

The scratch variants behind findings 1, 3 and 5 are not part of the suite:
FxHash `dict_count`/`dict_count_entry`, `rem_euclid` `calls`/`records`, and
`with_capacity(16)` `alloc_churn`. They are in
`/home/epentland/ai/canopy/mylang/.tmp/perf-plan-20260922/work/agent-d/scratch/`.
Every run is recorded in `rough_runs.json` (the first window) and
`rough_runs_final.json` (the final window) in the directory above it.
