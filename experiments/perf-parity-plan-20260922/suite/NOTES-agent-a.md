# Agent A notes: binary_trees, nbody, spectral_norm, mandelbrot (SUITE.md sections 1, 2, 3, 5)

## Setup and method

- mylang: `install-a3/bin/mylang build <file> -o … --cache-dir …`, default
  ReleaseFast (LLVM -O3 + LTO), no tuning flags. Zig 0.17.0-dev.1683
  `-O ReleaseFast`. rustc 1.98.1 `-C opt-level=3 -C codegen-units=1
  -C target-cpu=native -C panic=abort`. The exact build commands are in
  `.tmp/perf-plan-20260922/work/agent-a/build.sh`.
- **All timings are rough, E-core, unpinned-load**: `taskset -c 12-19`,
  `/usr/bin/time -f '%e %M'` (10 ms resolution), 3 runs per binary, run one at a
  time on a shared machine (`work/agent-a/timeit.sh`, which also compares every
  run's stdout with `<bench>.expected`). Peak RSS is `%M`.
- Every port and variant prints bytes identical to `<bench>.expected`, on every
  timed run. Each `.expected` file was also reproduced by an independent CPython
  transcription of SUITE.md (`work/agent-a/oracle/*.py`, all four MATCH), so the
  ports agree with each other and with the spec text.
- No binary contains an FMA instruction (`objdump -d | grep vf[n]m{add,sub}`
  is 0 for all 16), so byte identity follows from the specified operation order.
- `perf` is unavailable to this user (`perf_event_paranoid=4`), so the
  performance explanations below come from `mylang emit-qbe` IL and `objdump`
  of `--keep-symbols` builds. Probes referenced below live in
  `work/agent-a/probe/`. None of them is a suite arm.
- `common_a.zig` holds `Lines`: `print` formats into a fixed 4 KiB buffer and
  `flush` writes it to fd 1 with the raw write syscall (a loop that retries
  `EINTR` and short writes). The Zig ports with more than one output line use it.
  `spectral_norm.zig` uses `common.emit1`. Rust ports use `BufWriter` over a
  locked stdout.

## Timing table (rough, E-core, unpinned-load)

| benchmark | port | run 1 | run 2 | run 3 | peak RSS | vs Zig |
| --- | --- | --- | --- | --- | --- | --- |
| binary_trees | `binary_trees.my` | 0.73 s | 0.72 s | 0.73 s | 51.7 MB | 2.6× |
| binary_trees | `binary_trees_arena.my` | 0.46 s | 0.45 s | 0.48 s | 18.9 MB | 1.6× |
| binary_trees | `binary_trees.zig` (arena) | 0.28 s | 0.27 s | 0.28 s | 4.5 MB | 1.0× |
| binary_trees | `binary_trees_gpa.zig` | 0.29 s | 0.29 s | 0.29 s | 4.5 MB | 1.0× |
| binary_trees | `binary_trees.rs` | 0.54 s | 0.54 s | 0.55 s | 10.3 MB | 1.9× |
| nbody | `nbody.my` (record in list) | 15.42 s | 15.59 s | 15.28 s | 2.5 MB | 39× |
| nbody | `nbody_class.my` | 1.50 s | 1.50 s | 1.48 s | 2.4 MB | 3.8× |
| nbody | `nbody.zig` | 0.39 s | 0.39 s | 0.39 s | 0.5 MB | 1.0× |
| nbody | `nbody.rs` | 0.48 s | 0.47 s | 0.50 s | 2.2 MB | 1.2× |
| spectral_norm | `spectral_norm.my` | 0.92 s | 0.93 s | 0.96 s | 3.0 MB | 2.4× |
| spectral_norm | `spectral_norm_tuned.my` | 0.40 s | 0.40 s | 0.41 s | 3.0 MB | 1.0× |
| spectral_norm | `spectral_norm.zig` | 0.39 s | 0.39 s | 0.38 s | 0.5 MB | 1.0× |
| spectral_norm | `spectral_norm.rs` | 0.39 s | 0.39 s | 0.38 s | 2.4 MB | 1.0× |
| mandelbrot | `mandelbrot.my` | 0.22 s | 0.22 s | 0.23 s | 2.6 MB | 1.16× |
| mandelbrot | `mandelbrot.zig` | 0.19 s | 0.19 s | 0.19 s | 0.5 MB | 1.0× |
| mandelbrot | `mandelbrot.rs` | 0.19 s | 0.19 s | 0.20 s | 2.2 MB | 1.0× |

Every Zig port lands inside SUITE.md's 0.05–1.0 s window on an E-core, so no
size needs revisiting. For scale, the CPython oracles took (one run, E-core)
2.66 s for binary_trees, 24.35 s for nbody, 24.66 s for spectral_norm and
18.75 s for mandelbrot. **`nbody.my` is only 1.6× faster than CPython.**

---

## 1. binary_trees

Files: `binary_trees.my`, `binary_trees_arena.my`, `binary_trees.zig`,
`binary_trees_gpa.zig`, `binary_trees.rs`, `binary_trees.expected`.

Expected output (sha256 `3b9e63e2…782cd7ff`; tabs are real tabs):

```
stretch tree of depth 17	 check: 262143
65536	 trees of depth 4	 check: 2031616
16384	 trees of depth 6	 check: 2080768
4096	 trees of depth 8	 check: 2093056
1024	 trees of depth 10	 check: 2096128
256	 trees of depth 12	 check: 2096896
64	 trees of depth 14	 check: 2097088
16	 trees of depth 16	 check: 2097136
long lived tree of depth 16	 check: 131071
```

Port decisions:

- Node shape: mylang `class Node` with `left`/`right: Option[Node]`; Zig
  `?*Node`; Rust `Option<Box<Node>>`.
- All ports allocate both children before their parent. mylang and Rust do so
  inherently (constructor arguments are evaluated first). The Zig ports are
  written that way to match (the benchmarks-game Zig allocates the parent
  first). In an arena this makes the layout post-order in every language.
- `check`: mylang tests both children (`if left is None or right is None:
  return 1`), because narrowing works only on locals and there is no unwrap
  operator (see friction below). Zig tests the left child with `orelse return 1`
  and unwraps the right with `.?`, which is the spec's wording. Rust matches the
  pair `(Some(l), Some(r))`. The extra predictable branch in mylang is
  negligible next to the allocation.
- `binary_trees_arena.my`: the stretch tree and each short-lived tree are built
  and checked inside their own `with arena():` block, and only the scalar count
  leaves the block. The long-lived tree stays on the collecting heap. It needs
  no arena, and nothing allocates on the GC heap afterwards, so it is never
  traced.
- `binary_trees.zig`: one `ArenaAllocator(page_allocator)` per depth batch,
  `reset(.retain_capacity)` after each tree, and one arena each for the stretch
  and long-lived trees. `binary_trees_gpa.zig`: `smp_allocator` `create` per
  node, and a recursive `destroy` right after each check.

Friction:

- **Option narrowing does not apply to field paths.** `if node.left is None:
  return 1` followed by `check(node.left)` is `E_TYPE: expected Node, found
  Option[Node]`. Copying the fields into locals first narrows fine. Natural
  enough once known, but a Python programmer's first draft fails.
- Nothing else: the class/Option/f-string/`shift_left` program checked on the
  first try.

Performance:

- GC port is 2.6× Zig and peaks at 51.7 MB (Zig 4.5 MB, Rust 10.3 MB). Each node
  is one out-of-line `myl_native_heap_alloc` call. The payload is 32 bytes because
  `Option[Node]` is a 16-byte {tag word, pointer} value, where Rust
  (`Option<Box<_>>`, null niche) and Zig (`?*Node`) use 8 bytes, and the GC
  header comes on top. `make` also re-stores a root record around each
  recursive call.
- The arena port (0.46 s, 18.9 MB) beats Rust's glibc `malloc`/`free` (0.54 s)
  and is 1.6× Zig.
- **Zig baseline caveat:** in Zig 0.17-dev, `std.heap.ArenaAllocator` is the
  lock-free thread-safe arena, and every `alloc` performs
  `@atomicRmw(.Add)` on the node's end index (`ArenaAllocator.zig:358`), a
  `lock xadd`. That fits the arena port (0.28 s) being no faster than
  `smp_allocator` create/destroy (0.29 s). So treat the Zig arena number as
  "std arena", not as a bump-allocator floor: a non-atomic bump allocator should
  be cheaper (not measured here).

## 2. nbody

Files: `nbody.my`, `nbody_class.my`, `nbody.zig`, `nbody.rs`,
`nbody.expected`.

Expected output (sha256 `179a443b…07c98245`):

```
-169075163
-169083133
```

**SUITE.md erratum:** it says "First line: `-169075164`". That is the
benchmarks-game `%.9f` rounding of the energy −0.16907516382852447. SUITE.md's
own rule, `int(energy * 1e9)` truncating toward zero, gives `-169075163`. All
four ports and the CPython oracle print `-169075163`. Please fix the line in
SUITE.md rather than a port.

Port decisions:

- `nbody.my`: `record Body` in a `list[Body]`, updated in place through
  `bodies[i].field = …`, exactly as specified. `nbody_class.my`: `class Body`,
  `bi = bodies[i]`, then `bi.vx = …` through the reference.
- `for i in range(len(bodies))` in mylang (the list's length is dynamic). Zig
  and Rust keep a local `[5]Body` and pass slices, so after inlining their
  optimizers see the constant 5.
- The Zig constants are typed `f64` (`const pi: f64 = …`). An untyped
  `comptime_float` would compute `4.0 * pi * pi` in f128 and could round
  differently.

Friction:

- **`E_CONSTANT_TYPE`: "constant types currently require builtin integers or
  bool".** `const PI: float = 3.141592653589793` is rejected, so the three
  constants are zero-argument functions (`pi()`, `solar_mass()`,
  `days_per_year()`). LLVM inlines them, so they cost nothing, but it is the
  first thing a Python port hits.
- **`E_MUTATION_MARKER` in `nbody_class.my`:** writing a field of a class
  object read out of a list parameter needs the list parameter declared `mut`
  ("this function writes `bodies` (parameter 1) reachable from the caller;
  declare `bodies: mut list[Body]`") and `mut` at the call site. The message is
  precise and actionable. It is surprising only in that the list itself is never
  written.
- **A fixed array cannot replace the list.** `mut [5]Body` is
  `E_MUTATION_MARKER` ("`mut` on `[5]Body` has nothing to write; only a list,
  dict, class, Cell, array, byte buffer or a record holding one can be `mut`").
  The message lists "array" among the mutable kinds while rejecting one. Without `mut`,
  `bodies[i].vx = …` is `E_COLLECTION_METHOD: indexed field assignment requires
  a list or dictionary` and `for b in bodies` is `E_COLLECTION_METHOD: iteration
  requires a collection or dictionary view`. Repro:
  `repro/agent_a_diag_mut_fixed_array.my`.

Performance (the most important finding in my set):

- **`nbody.my` is 39× Zig. A record-field write through a list slot costs about
  37 ns here.** In `advance`, every `bodies[x]` expression gets its own GC root
  slot holding a copy of the `bodies` list pointer: 35 distinct `%root` slots
  (exactly the 34 `bodies` occurrences in the body, counting `len(bodies)`, plus
  the parameter), all with the one `list[Body]` pointer descriptor. Every
  `bodies[i].f = v` then compiles to:
  1. copy the 56-byte record out of the list;
  2. set the field;
  3. re-store the whole chain of those 35 root records (315 descriptor stores in
     the function's IL). The optimized machine code still has 35 descriptor
     stores, 3–4 stores per record, before each of the 9 writes, so LLVM
     removes none of them;
  4. call the out-of-line `myl_native_list_set`, which copies the 56 bytes back
     through a size jump table.
  `myl_native_list_set` never allocates, so it is unclear why it needs a
  published root chain at all.
- The cost scales with that chain, not with the number of writes alone.
  Rewriting `nbody.my`'s `advance` as copy / modify / whole-record write-back
  (`bi = bodies[i]; …; bodies[i] = bi`, 25 slot writes per step instead of 75)
  leaves 8 root slots (7 occurrences plus the parameter) with 8 root records per
  write, and runs in **2.67 s** (one run; `probe/nbody_writeback.my`, 5.8× faster
  than `nbody.my`).
- The same holds for scalar lists. Structure-of-arrays with one `list[float]` per
  component is even slower, 16.4 s (one run; `probe/nbody_soa.my`: 42 root
  records per slot write). Two minimal probes isolate it: 100M
  `xs[j] = xs[j] + 1.0` writes take 0.60 s with one list live and 1.5–1.6 s
  with five more lists live
  (`repro/agent_a_perf_slot_write_{one,six}_live.my`). For comparison, 100M
  class field writes through list elements take 0.11 s, and 100M record field
  writes through list slots take 0.58 s (`probe/field_{class,record}.my`). These
  probe numbers are single runs.
- `nbody_class.my` avoids list writes entirely: 1.5 s, 10× faster than the record
  port and 3.8× Zig. What remains shows in the hot loop:
  - after every float operation, a position store and a `vucomisd x,x; jp`
    branch to the NaN canonicalizer (`myl_qbe_float_canonical`), for the
    canonical-NaN rule;
  - a bounds check and a reload of the list's data pointer on each `bodies[j]`;
  - a pointer hop per body;
  - no unrolling, because `len(bodies)` is dynamic.
- No `nbody_tuned.my`. The class port is already the fastest formulation I
  found. Caching `bi`'s fields in locals gave 1.45 s (one run;
  `probe/nbody_class_hoist.my`, no gain). A `[5]Body` fixed array cannot be
  updated in place (above).

## 3. spectral_norm

Files: `spectral_norm.my`, `spectral_norm_tuned.my`, `spectral_norm.zig`,
`spectral_norm.rs`, `spectral_norm.expected`.

Expected output (sha256 `ce457b58…bdf238050`):

```
1274224152
```

Port decisions:

- mylang `a` uses `int` and `//`, which is exact here. Zig and Rust use `usize`
  indices, the idiomatic type, with `/ 2`. `a` is an ordinary function in every
  port, and the compilers may inline it.
- `u`, `v`, `tmp` are built with a comprehension `[1.0 for _ in range(n)]`
  (see friction). Zig allocates them from `smp_allocator` and `@memset`s them;
  Rust uses `vec![…; n]`.

Friction:

- **List repetition `[1.0] * n` is unsupported, and the rejection is
  misleading:** `E_TYPE: expected list[float], found int`, with the caret on
  the `*`. It neither names repetition nor offers the comprehension. Repro:
  `repro/agent_a_diag_list_repeat.my`.
- **`E_MUTATION_OVERLAP` in `mul_atav`, with a hint that cannot be followed.**
  `mul_av(v, mut tmp)` inside `mul_atav(v, out: mut, tmp: mut)` is rejected:
  "writable argument may alias an argument promised read-only; pass a fresh
  snapshot, make both inputs writable, or split the call". Following "make both
  inputs writable" yields `E_MUTATION_MARKER` ("`v` is declared `mut` but never
  written; remove `mut`"), which sends you straight back. Repros:
  `repro/agent_a_diag_overlap_hint.my` and `…_writable.my`. The port uses the
  "fresh snapshot" route (`mul_av(v.copy(), mut tmp)`), which keeps SUITE.md's
  function shape and costs 40 copies of 16 KB. "Split the call" (calling
  `mul_av`/`mul_atv` straight from `main`) also type-checks and times the same
  (0.96 s, one run, `probe/sn_c.my`).

Performance:

- 2.4× Zig. **With checked arithmetic, `a(i, j)` is not inlined** by the LLVM
  build. It stays an out-of-line call with a frame-record push/pop and overflow
  checks on its three `+` and one `*`. The caller stores a position and spills
  the running sum `s` to the stack around every call. Zig and Rust inline it
  into a `cvtsi2sd`/`vdivsd`/`vmulsd`/`vaddsd` loop.
- `spectral_norm_tuned.my` changes only `a`, to
  `wrapping_add`/`wrapping_mul`. The values stay below about 8e6, so the result
  is bit-identical. With nothing left in `a` that can trap, it is inlined and the
  port runs at **Zig parity (0.40 s)**. What remains in the loop is one bounds
  check on `v[j]`, a NaN check per float operation and position stores, all
  hidden behind the divider. The expensive part of checked arithmetic here is
  not the check but that a possible trap blocks inlining.

## 5. mandelbrot

Files: `mandelbrot.my`, `mandelbrot.zig`, `mandelbrot.rs`,
`mandelbrot.expected`.

Expected output (sha256 `81099b92…8091fd28b`):

```
P4 1600 1600
209816799
```

Port decisions:

- The trailing `byte = 0; bits = 0` inside the `if bits > 0` row tail are dead
  stores: both are reset at the top of every row, and rustc warns about them.
  They are dropped in all three ports. The branch never runs for size 1600
  anyway.
- `byte << (8 - bits)` is `shift_left(byte, 8 - bits)` in mylang. `mix` uses
  `%` (mylang, Rust) and `@mod` (Zig) on non-negative `i64`.

Friction: none. The loop, conditional expression and f-string all checked on
the first try.

Performance: 1.16× Zig. The escape loop is bound by the `zr → tr → zr`
dependency latency, so the per-operation NaN checks and position stores mostly
execute in the shadow of that chain. No `_tuned` variant: nothing in the
language would change this loop.

---

## Compiler bugs

None found. No program produced wrong output, crashed or trapped spuriously,
and all byte-identity checks passed on every run. The files under `repro/` are
diagnostic-quality and performance repros, not wrong-code repros:

| file | kind | what it shows |
| --- | --- | --- |
| `repro/agent_a_diag_list_repeat.my` | diagnostic | `[1.0] * 4` gives `E_TYPE` "expected list[float], found int", with no mention of repetition or of the comprehension spelling |
| `repro/agent_a_diag_overlap_hint.my` + `…_writable.my` | diagnostic | `E_MUTATION_OVERLAP`'s "make both inputs writable" hint leads to `E_MUTATION_MARKER` "declared `mut` but never written" |
| `repro/agent_a_diag_mut_fixed_array.my` | diagnostic | `mut [2]P` is rejected by a message that lists "array" as mutable; fixed arrays also lack indexed field assignment and `for` iteration |
| `repro/agent_a_perf_slot_write_one_live.my` + `…_six_live.my` | performance | a list slot write re-stores a GC root chain whose length grows with the live rooted values (0.60 s vs 1.5–1.6 s for 100M writes) |

## Other notes

- `mylang fmt`'s canonical layout attaches a file-header comment to the first
  declaration (it deletes the blank lines between them) and deletes blank lines
  inside function bodies. The suite's reference micros
  (`perf-parity-audit-20260921/micro/*.my`) are not canonical either. I kept
  their layout, so `fmt --check` reports differences for my `.my` files. Zig
  (`zig fmt --check`) and Rust (`rustfmt --check`) ports are canonical.
- `mylang emit-qbe` prints a JSON document with per-function IL under
  `functions[].il`. `work/agent-a/nbody_il_*.qbe` are the extracted IL files
  used above.
- `mylang check` (and `fmt`, `emit-qbe`) writes its frontend/semantic cache to
  `.mylang-cache/` in the current directory unless given `--cache-dir=DIR`.
  Running `check` from the suite directory, as the task instructions suggest,
  therefore created `suite/.mylang-cache/` (about 3 MB of cache data, no
  binaries), starting with my first `check` at 18:15. Other agents write to it
  too, so I left it in place. It is safe to delete once nobody is building.
