# Where the remaining time goes: self-PC profiles, 2026-09-21

Five profiles of two already-built binaries, taken with the repository's
userspace SIGPROF sampler because `perf_event_paranoid=4` denies every hardware
and software perf event on this host. Method, caveats and reproduction commands
are in `README.md`; read the two that change how these tables should be read:

1. **A sample inside a shared library is counted but not located.** It appears
   only in the "outside the executable" share. In the LLVM builds that is where
   `memcpy`, `memset` and `malloc` go. The QBE build statically links Zig's
   compiler-rt, which is why the same work is visible there as a `libc` class
   *inside* the binary, and why its outside share is half the LLVM build's.
2. **LTO folds callees into callers**, so a sample inside an inlined guest
   function is charged to the surviving outer symbol. 70 of the SVG build's 124
   manifest functions and 33 of the s-expression build's 101 kept their own
   symbol.

Sample counts are CPU-time samples at 1 ms granularity (`CONFIG_HZ=1000` caps
the sampler's 500 µs request), self PC only, no stacks, no cycles.

## What the profiles say

### SVG schematic renderer (`gc-lto`, GC, LLVM -O3 + LTO, no step accounting)

Guest code is 81.7% of all samples; the runtime C is 2.3%; the host provider
that actually writes the file is 0.07%; the collector is 0.04%. Whatever
separates this binary from Zig on this workload is in the emitted guest code,
not in the collector, the allocator or the host boundary.

- **`io::flush` alone is 42.5% of every sample taken**, and eleven of the fifteen
  hottest instructions in the whole program sit in one ~130-byte loop inside it.
  The disassembly is unambiguous: eight 32-byte `vmovups` loads from one stack
  slot (`0x160(%rsp)` upward) and eight stores into another (`0x60(%rsp)`
  upward), with a single `mov %dil,0x160(%rsp,%rax,1)` inserting one byte in the
  middle. That is a whole-256-byte stack-to-stack copy per byte written. It is
  `replace(payload, i, u8(out.buffer[position + i]))` in
  `src/schematic/guest/io.my`, applied to a `[256]u8` value array: value
  semantics copy the array for each of the 49 617 output bytes, so the program
  moves roughly 12.7 MB of stack to emit 49.6 KB of SVG. The bulk
  `io::write_block` boundary underneath it is free by comparison — the host
  provider never exceeds 0.07%.
- **`layout_routes::build` is 10.5%, and its single hottest instruction is the
  hottest address in the profile** (6.6% of all samples). It is the `lea`
  between two back-to-back 128-byte `vmovups` bursts that store the *same* four
  `ymm` registers to `(%rax)` and then to `0x1b0(%r14)` — one 128-byte record
  value being materialised into two stack slots, and the sampled instruction is
  the address computation for the second. The function is the O(pins²) loop that
  reads `pins[j]` and `parts[pin.part]` on every iteration, and `circuit::Pin`
  is two `text::Span` (32 bytes each) plus six integers and two flags, so a list
  index there moves a full ~128-byte record.
- **The byte-level formatting path is next**: `text::write` 3.8%,
  `text::escaped` 2.6%, `text::decimal` 2.5%, 8.9% together, plus
  `buffer_grow_rooted` at 1.7% — the only runtime function of any weight, and it
  is the managed byte buffer growing.
- **Input parsing is small**: `sexpr::at` 3.0% and `sexpr::form` 2.3%.
- **Nothing GC-shaped appears at all.** `trace`, `myl_native_heap_collect` and
  the root operations sum to 0.04%. The 15.8% outside the executable is
  shared-library code the sampler cannot place — libc `memcpy`/`memset`/`malloc`
  and `ld.so` — and the whole run is only about 2 ms of CPU.

### S-expression parser and printer (`sexpr-o3-lto`, GC, LLVM -O3 + LTO)

A different shape entirely: guest code is 36–43%, runtime C is 18–28%, and a
third of all samples are in libc.

- **The collector is the largest single identified block on the census
  workload**: `trace` 10.9% + `myl_native_heap_collect` 4.9% + the allocator and
  root operations = 16.5% of all samples, about 26% of the samples that could be
  located. The hot instructions in both are pointer-chasing compares and
  branches (`mov (%rdi),%rdi` / `cmpl $0x0,0x2c(%rdi)` / `jne`), i.e. mark-phase
  traversal of the object graph, not memory bandwidth. On render it falls to
  9.6% because there is more non-GC work to dilute it, not because it got
  cheaper: `trace` took 1914 raw samples on census and 1918 on render, the same
  absolute cost under a larger total.
- **`myl_native_bytes_find_any` is 8.9% (census) / 5.0% (render).** Its hot
  instruction is a 64-bit bitset membership test — `shr $0x6,%ecx`,
  `mov -0x30(%rbp,%rcx,8),%rcx`, `bt %rax,%rcx`, `jb` — followed by
  `inc %rdi`: a one-byte-at-a-time delimiter scan, one call per token.
- **Guest tokenizing and parsing**: `next_raw` 11.0%, `parse_node` 6.2%,
  `read_string` 4.4%, `advance` 3.6%, `read_atom` 2.1% on census.
  `sexpr.parser::advance`'s hot address is a 32-byte `vmovups` plus a 16-byte
  `vmovups` plus an 8-byte `mov` writing a token record into a heap object —
  a record store, not arithmetic.
- **Aggregate copies out of lists recur.** `main::tally`'s hot address
  (2.2% of all samples) is `vmovupd 0x0(%r13,%rax,1),%ymm0` /
  `vmovupd 0x20(...),%ymm1` into stack slots: a 64-byte element copied out of a
  list per iteration. On render, `sexpr.printer::is_short_list` shows the same
  pattern — two `ymm` loads from a list element, two stores into a
  caller-supplied buffer.
- **Render is dominated by the printer**: `push_node` 10.3%,
  `estimate_width` 4.6%, `scalar_len` 3.1%, `is_short_list` 2.4%, with
  `byte_builder::append` 2.7% and `buffer_grow_rooted` 1.5% behind them.

### The same workloads on the production QBE backend

Useful mainly because the QBE build links compiler-rt statically and so *shows*
what the LLVM build hides outside the executable.

| | outside | libc inside | guest | runtime C |
| --- | ---: | ---: | ---: | ---: |
| `sexpr-o3-lto-census` | 35.7% | — | 36.3% | 27.6% |
| `sexpr-qbe-census` | 17.8% | 10.9% | 45.6% | 25.4% |
| `sexpr-o3-lto-render` | 37.2% | — | 43.2% | 17.6% |
| `sexpr-qbe-render` | 13.9% | 17.6% | 44.9% | 22.2% |

The outside share falls by 18–23 points exactly as a `memcpy`/`memset` block of
11–18 points appears inside. `memcpy` is the hottest function of the QBE render
profile (12.6%) and third on census (8.3%), and its hottest address, `+0x141`,
is the middle of a `vmovaps`/`vmovups` 32-byte-per-step unrolled copy. So the
third of the LLVM build's samples that the sampler cannot place is very likely
block copy and zeroing rather than scheduler or loader time — the same
aggregate-copy traffic that is visible as inline `vmovups` bursts wherever LTO
inlined it into guest code. The two backends do not emit the same code, so this
indicates where the unplaceable samples go; it does not transfer one profile
onto the other.

`sexpr.tokenizer::raw` (6.1%) and `is_atom_continue` (5.5%) are large in the QBE
profiles and nearly absent from the LLVM ones; LTO inlined them into
`next_raw`. Read cross-backend function rows with that in mind — only the class
totals compare cleanly.

## Method check: what the sampler's start offset does

The SVG run is about 2 ms of CPU, and the repository sampler's first expiration
is 0.5–2.0 ms of CPU in, so with the unmodified sampler part of every run goes
unsampled and the phases that run last are over-weighted. Three passes over the
same binary:

| pass | runs | samples | per run | `io::flush` | outside |
| --- | ---: | ---: | ---: | ---: | ---: |
| repository sampler | 16000 | 13062 | 0.82 | 52.0% | 14.5% |
| repository sampler | 8000 | 9656 | 1.21 | 40.9% | 17.2% |
| `sample_dense.c` | 16000 | 19644 | 1.23 | 42.5% | 15.8% |

The pass that saw fewest samples per run — i.e. the one whose unsampled prefix
covered the largest fraction of the run — put the most weight on the last phase.
The retained `svg-o3-lto.json` is the dense-sampler pass, which has no unsampled
prefix; `svg-o3-lto-repo-sampler.json` is the second row, kept as the artifact
of the comparison. The first row's raw samples were overwritten by the later
pass and only the numbers above survive. The s-expression workloads are 30–80 ms
and are unaffected: an independent repository-sampler pass over all four agreed
with the dense pass within about one point on every leading function
(`next_raw` 11.11% vs 10.99%, `trace` 10.69% vs 10.92%,
`bytes_find_any` 9.15% vs 8.85%, outside 33.5% vs 35.7%).

A 3000-run control on a six-byte input produced **zero** samples from either
s-expression binary, so process startup and dynamic loading together cost less
than the sampler's first tick and contribute essentially nothing to any of these
profiles.

## Tables

### svg-o3-lto

`.tmp/svg-gap-fixes-20260921/gc-lto`  ·  16000 runs  ·  **19644 samples**  ·  outside the executable **15.8%**  ·  unmapped inside 0.17%

| class | samples | share of all samples |
| --- | ---: | ---: |
| guest | 16046 | 81.68% |
| runtime-c | 456 | 2.32% |
| host-provider | 14 | 0.07% |
| startup | 1 | 0.01% |
| (outside the executable: libc, ld.so) | 3094 | 15.75% |

| # | function | class | samples | share |
| ---: | --- | --- | ---: | ---: |
| 1 | `io::flush` | guest | 8354 | 42.53% |
| 2 | `layout_routes::build` | guest | 2067 | 10.52% |
| 3 | `text::write` | guest | 752 | 3.83% |
| 4 | `sexpr::at` | guest | 595 | 3.03% |
| 5 | `layout::partPin` | guest | 529 | 2.69% |
| 6 | `text::escaped` | guest | 502 | 2.56% |
| 7 | `text::decimal` | guest | 499 | 2.54% |
| 8 | `sexpr::form` | guest | 442 | 2.25% |
| 9 | `svg::passive` | guest | 372 | 1.89% |
| 10 | `buffer_grow_rooted [native_bytes.c]` | runtime-c | 339 | 1.73% |
| 11 | `layout::collectRows` | guest | 280 | 1.43% |
| 12 | `layout::nearest` | guest | 200 | 1.02% |
| 13 | `circuit::label` | guest | 189 | 0.96% |
| 14 | `layout::innerPin` | guest | 159 | 0.81% |
| 15 | `ports::equal` | guest | 95 | 0.48% |
| 16 | `draw::line` | guest | 86 | 0.44% |
| 17 | `layout::bridge` | guest | 75 | 0.38% |
| 18 | `layout::depth` | guest | 73 | 0.37% |
| 19 | `layout::branch` | guest | 66 | 0.34% |
| 20 | `layout::groundBranch` | guest | 61 | 0.31% |
| 21 | `svg::routes` | guest | 60 | 0.31% |
| 22 | `layout_graph::build` | guest | 59 | 0.30% |
| 23 | `svg::pinStart` | guest | 58 | 0.30% |
| 24 | `circuit::normalize` | guest | 56 | 0.29% |
| 25 | `layout_routes::blocked` | guest | 54 | 0.27% |
| 26 | `qbe_host_invoke [qbe_host_runtime.c]` | runtime-c | 49 | 0.25% |
| 27 | `svg::render` | guest | 47 | 0.24% |
| 28 | `svg::chip` | guest | 38 | 0.19% |
| 29 | `myl_native_list_append [native_collections.c]` | runtime-c | 36 | 0.18% |
| 30 | `svg::displayRef` | guest | 33 | 0.17% |

Hottest individual instruction addresses:

| # | address | function | +offset | samples | share |
| ---: | --- | --- | --- | ---: | ---: |
| 1 | `0x1077907` | `layout_routes::build` | `0x1177` | 1297 | 6.60% |
| 2 | `0x10839ea` | `io::flush` | `0x2aa` | 933 | 4.75% |
| 3 | `0x10839e1` | `io::flush` | `0x2a1` | 848 | 4.32% |
| 4 | `0x10839f3` | `io::flush` | `0x2b3` | 800 | 4.07% |
| 5 | `0x10839fc` | `io::flush` | `0x2bc` | 780 | 3.97% |
| 6 | `0x1083a26` | `io::flush` | `0x2e6` | 694 | 3.53% |
| 7 | `0x1083a38` | `io::flush` | `0x2f8` | 670 | 3.41% |
| 8 | `0x1083a5c` | `io::flush` | `0x31c` | 660 | 3.36% |
| 9 | `0x1083a4a` | `io::flush` | `0x30a` | 613 | 3.12% |
| 10 | `0x10bd01a` | `sexpr::at` | `0xea` | 405 | 2.06% |
| 11 | `0x108cd05` | `sexpr::form` | `0x85` | 162 | 0.82% |
| 12 | `0x1083a65` | `io::flush` | `0x325` | 157 | 0.80% |
| 13 | `0x1083a02` | `io::flush` | `0x2c2` | 132 | 0.67% |
| 14 | `0x10dd8b7` | `buffer_grow_rooted [native_bytes.c]` | `0x157` | 126 | 0.64% |
| 15 | `0x1083a2f` | `io::flush` | `0x2ef` | 123 | 0.63% |

`0x1077907` — `layout_routes::build` +`0x1177` (6.60% of all samples)

```
    0x10778f4  vmovups %ymm3,0x60(%rax)
    0x10778f9  vmovups %ymm2,0x40(%rax)
    0x10778fe  vmovups %ymm1,0x20(%rax)
    0x1077903  vmovups %ymm0,(%rax)
==> 0x1077907  lea    0x1b0(%r14),%rax
    0x107790e  vmovups %ymm3,0x60(%rax)
    0x1077913  vmovups %ymm2,0x40(%rax)
    0x1077918  vmovups %ymm1,0x20(%rax)
```

`0x10839ea` — `io::flush` +`0x2aa` (4.75% of all samples)

```
    0x10839c7  vmovups %ymm0,0x160(%rsp)
    0x10839d0  mov    %dil,0x160(%rsp,%rax,1)
    0x10839d8  vmovups 0x160(%rsp),%ymm0
    0x10839e1  vmovups 0x180(%rsp),%ymm1
==> 0x10839ea  vmovups 0x1a0(%rsp),%ymm2
    0x10839f3  vmovups 0x1c0(%rsp),%ymm3
    0x10839fc  vmovups %ymm0,0x60(%rsp)
```

`0x10839e1` — `io::flush` +`0x2a1` (4.32% of all samples)

```
    0x10839be  vmovups %ymm1,0x180(%rsp)
    0x10839c7  vmovups %ymm0,0x160(%rsp)
    0x10839d0  mov    %dil,0x160(%rsp,%rax,1)
    0x10839d8  vmovups 0x160(%rsp),%ymm0
==> 0x10839e1  vmovups 0x180(%rsp),%ymm1
    0x10839ea  vmovups 0x1a0(%rsp),%ymm2
    0x10839f3  vmovups 0x1c0(%rsp),%ymm3
```

`0x10839f3` — `io::flush` +`0x2b3` (4.07% of all samples)

```
    0x10839d0  mov    %dil,0x160(%rsp,%rax,1)
    0x10839d8  vmovups 0x160(%rsp),%ymm0
    0x10839e1  vmovups 0x180(%rsp),%ymm1
    0x10839ea  vmovups 0x1a0(%rsp),%ymm2
==> 0x10839f3  vmovups 0x1c0(%rsp),%ymm3
    0x10839fc  vmovups %ymm0,0x60(%rsp)
    0x1083a02  vmovups %ymm1,0x80(%rsp)
```

`0x10839fc` — `io::flush` +`0x2bc` (3.97% of all samples)

```
    0x10839d8  vmovups 0x160(%rsp),%ymm0
    0x10839e1  vmovups 0x180(%rsp),%ymm1
    0x10839ea  vmovups 0x1a0(%rsp),%ymm2
    0x10839f3  vmovups 0x1c0(%rsp),%ymm3
==> 0x10839fc  vmovups %ymm0,0x60(%rsp)
    0x1083a02  vmovups %ymm1,0x80(%rsp)
    0x1083a0b  vmovups %ymm2,0xa0(%rsp)
```

### sexpr-o3-lto-census

`.tmp/perf-audit-20260921/sexpr-o3-lto`  ·  600 runs  ·  **17526 samples**  ·  outside the executable **35.7%**  ·  unmapped inside 0.46%

| class | samples | share of all samples |
| --- | ---: | ---: |
| guest | 6362 | 36.30% |
| runtime-c | 4833 | 27.58% |
| (outside the executable: libc, ld.so) | 6251 | 35.67% |

| # | function | class | samples | share |
| ---: | --- | --- | ---: | ---: |
| 1 | `sexpr.tokenizer::next_raw` | guest | 1926 | 10.99% |
| 2 | `trace [native_heap.c]` | runtime-c | 1914 | 10.92% |
| 3 | `myl_native_bytes_find_any [native_bytes.c]` | runtime-c | 1551 | 8.85% |
| 4 | `sexpr.parser::parse_node` | guest | 1083 | 6.18% |
| 5 | `main::tally` | guest | 869 | 4.96% |
| 6 | `myl_native_heap_collect [native_heap.c]` | runtime-c | 863 | 4.92% |
| 7 | `sexpr.tokenizer::read_string` | guest | 775 | 4.42% |
| 8 | `sexpr.parser::advance` | guest | 638 | 3.64% |
| 9 | `sexpr.tokenizer::read_atom` | guest | 374 | 2.13% |
| 10 | `myl_native_list_append [native_collections.c]` | runtime-c | 329 | 1.88% |
| 11 | `sexpr.parser::parse_list` | guest | 315 | 1.80% |
| 12 | `sexpr.tokenizer::raw` | guest | 142 | 0.81% |
| 13 | `sexpr.tokenizer::read_number` | guest | 122 | 0.70% |
| 14 | `myl_native_heap_alloc_at [native_heap.c]` | runtime-c | 115 | 0.66% |
| 15 | `sexpr.parser::parse_leaf` | guest | 106 | 0.60% |
| 16 | `myl_native_bytes_number_parse` | runtime-c | 58 | 0.33% |
| 17 | `sexpr.tokenizer::is_atom_continue` | guest | 6 | 0.03% |
| 18 | `sexpr.parser::parse` | guest | 3 | 0.02% |
| 19 | `read_handle [native_scoped.c]` | runtime-c | 2 | 0.01% |
| 20 | `main::summarise` | guest | 2 | 0.01% |
| 21 | `myl_qbe_stream_begin [qbe_io.c]` | runtime-c | 1 | 0.01% |
| 22 | `main::main` | guest | 1 | 0.01% |

Hottest individual instruction addresses:

| # | address | function | +offset | samples | share |
| ---: | --- | --- | --- | ---: | ---: |
| 1 | `0x10502f4` | `myl_native_bytes_find_any [native_bytes.c]` | `0xf4` | 637 | 3.63% |
| 2 | `0x104db9f` | `myl_native_heap_collect [native_heap.c]` | `0x23f` | 608 | 3.47% |
| 3 | `0x104dcf4` | `trace [native_heap.c]` | `0x104` | 604 | 3.45% |
| 4 | `0x104dc68` | `trace [native_heap.c]` | `0x78` | 414 | 2.36% |
| 5 | `0x1033e97` | `main::tally` | `0x2e7` | 377 | 2.15% |
| 6 | `0x10363f8` | `sexpr.parser::advance` | `0x198` | 329 | 1.88% |
| 7 | `0x1035e2e` | `sexpr.tokenizer::next_raw` | `0xbee` | 244 | 1.39% |
| 8 | `0x1040535` | `sexpr.parser::parse_node` | `0x8a5` | 243 | 1.39% |
| 9 | `0x10502f2` | `myl_native_bytes_find_any [native_bytes.c]` | `0xf2` | 212 | 1.21% |
| 10 | `0x1033e9e` | `main::tally` | `0x2ee` | 184 | 1.05% |
| 11 | `0x10502ee` | `myl_native_bytes_find_any [native_bytes.c]` | `0xee` | 172 | 0.98% |
| 12 | `0x1035ee2` | `sexpr.tokenizer::next_raw` | `0xca2` | 150 | 0.86% |
| 13 | `0x10361b8` | `sexpr.tokenizer::next_raw` | `0xf78` | 143 | 0.82% |
| 14 | `0x1032fd1` | `sexpr.tokenizer::read_string` | `0x8d1` | 120 | 0.68% |
| 15 | `0x1033004` | `sexpr.tokenizer::read_string` | `0x904` | 113 | 0.64% |

`0x10502f4` — `myl_native_bytes_find_any [native_bytes.c]` +`0xf4` (3.63% of all samples)

```
    0x10502e6  shr    $0x6,%ecx
    0x10502e9  mov    -0x30(%rbp,%rcx,8),%rcx
    0x10502ee  bt     %rax,%rcx
    0x10502f2  jb     1050303 <myl_native_bytes_find_any+0x103>
==> 0x10502f4  inc    %rdi
    0x10502f7  cmp    %rdi,%r8
    0x10502fa  jne    10502e0 <myl_native_bytes_find_any+0xe0>
    0x10502fc  mov    $0xffffffffffffffff,%rdi
```

`0x104db9f` — `myl_native_heap_collect [native_heap.c]` +`0x23f` (3.47% of all samples)

```
    0x104db93  mov    (%rdi),%rdi
    0x104db96  test   %rdi,%rdi
    0x104db99  je     104dbb0 <myl_native_heap_collect+0x250>
    0x104db9b  cmpl   $0x0,0x2c(%rdi)
==> 0x104db9f  jne    104db90 <myl_native_heap_collect+0x230>
    0x104dba1  cmpl   $0x0,0x28(%rdi)
    0x104dba5  je     104db75 <myl_native_heap_collect+0x215>
    0x104dba7  movl   $0x0,0x28(%rdi)
```

`0x104dcf4` — `trace [native_heap.c]` +`0x104` (3.45% of all samples)

```
    0x104dce8  jae    104dcd0 <trace+0xe0>
    0x104dcea  cmpl   $0x0,0x20(%rcx)
    0x104dcee  jne    104dd61 <trace+0x171>
    0x104dcf0  cmpl   $0x0,-0x34(%rax)
==> 0x104dcf4  jne    104dd61 <trace+0x171>
    0x104dcf6  cmpl   $0x0,-0x38(%rax)
    0x104dcfa  jne    104dd61 <trace+0x171>
    0x104dcfc  lea    -0x60(%rax),%rcx
```

`0x104dc68` — `trace [native_heap.c]` +`0x78` (2.36% of all samples)

```
    0x104dc59  movl   $0x0,-0x2c(%rbp)
    0x104dc60  cmp    $0x4,%ecx
    0x104dc63  jne    104dc6b <trace+0x7b>
    0x104dc65  mov    (%r14),%eax
==> 0x104dc68  mov    %eax,-0x2c(%rbp)
    0x104dc6b  test   %r12,%r12
    0x104dc6e  je     104dd61 <trace+0x171>
    0x104dc74  mov    (%rdx),%r13
```

`0x1033e97` — `main::tally` +`0x2e7` (2.15% of all samples)

```
    0x1033e81  cmp    %r14,(%r12)
    0x1033e85  jne    1033f7a <myl_f_3edf79354916f8d010aaa7e22a06a2b2e0944427858dfba883ade1d0e2be0036+0x3ca>
    0x1033e8b  mov    0x20(%r12),%rax
    0x1033e90  vmovupd 0x0(%r13,%rax,1),%ymm0
==> 0x1033e97  vmovupd 0x20(%r13,%rax,1),%ymm1
    0x1033e9e  vmovupd %ymm1,0x60(%rsp)
    0x1033ea4  vmovupd %ymm0,0x40(%rsp)
    0x1033eaa  cmp    %r9,%rcx
```

### sexpr-o3-lto-render

`.tmp/perf-audit-20260921/sexpr-o3-lto`  ·  600 runs  ·  **31594 samples**  ·  outside the executable **37.2%**  ·  unmapped inside 1.96%

| class | samples | share of all samples |
| --- | ---: | ---: |
| guest | 13640 | 43.17% |
| runtime-c | 5574 | 17.64% |
| (outside the executable: libc, ld.so) | 11762 | 37.23% |

| # | function | class | samples | share |
| ---: | --- | --- | ---: | ---: |
| 1 | `sexpr.printer::push_node` | guest | 3259 | 10.32% |
| 2 | `sexpr.tokenizer::next_raw` | guest | 1982 | 6.27% |
| 3 | `trace [native_heap.c]` | runtime-c | 1918 | 6.07% |
| 4 | `myl_native_bytes_find_any [native_bytes.c]` | runtime-c | 1575 | 4.99% |
| 5 | `sexpr.printer::estimate_width` | guest | 1460 | 4.62% |
| 6 | `sexpr.parser::parse_node` | guest | 1023 | 3.24% |
| 7 | `sexpr.printer::scalar_len` | guest | 968 | 3.06% |
| 8 | `byte_builder::append` | guest | 853 | 2.70% |
| 9 | `myl_native_heap_collect [native_heap.c]` | runtime-c | 843 | 2.67% |
| 10 | `sexpr.printer::is_short_list` | guest | 752 | 2.38% |
| 11 | `sexpr.tokenizer::read_string` | guest | 701 | 2.22% |
| 12 | `sexpr.parser::advance` | guest | 663 | 2.10% |
| 13 | `buffer_grow_rooted [native_bytes.c]` | runtime-c | 481 | 1.52% |
| 14 | `sexpr.tokenizer::read_atom` | guest | 436 | 1.38% |
| 15 | `byte_builder::append_range` | guest | 355 | 1.12% |
| 16 | `myl_native_list_append [native_collections.c]` | runtime-c | 328 | 1.04% |
| 17 | `sexpr.parser::parse_list` | guest | 288 | 0.91% |
| 18 | `myl_native_heap_alloc_at [native_heap.c]` | runtime-c | 271 | 0.86% |
| 19 | `byte_builder::append_spaces` | guest | 210 | 0.66% |
| 20 | `sexpr.printer::append_view` | guest | 184 | 0.58% |
| 21 | `sexpr.tokenizer::raw` | guest | 132 | 0.42% |
| 22 | `sexpr.tokenizer::read_number` | guest | 125 | 0.40% |
| 23 | `sexpr.parser::parse_leaf` | guest | 108 | 0.34% |
| 24 | `sexpr.printer::append_float` | guest | 64 | 0.20% |
| 25 | `sexpr.printer::decimal_width` | guest | 57 | 0.18% |
| 26 | `myl_native_text_from_utf8_checked [native_text.c]` | runtime-c | 53 | 0.17% |
| 27 | `myl_native_bytes_number_parse` | runtime-c | 53 | 0.17% |
| 28 | `myl_native_text_scalar` | runtime-c | 16 | 0.05% |
| 29 | `myl_native_text_utf8 [native_text.c]` | runtime-c | 15 | 0.05% |
| 30 | `sexpr.tokenizer::is_atom_continue` | guest | 12 | 0.04% |

Hottest individual instruction addresses:

| # | address | function | +offset | samples | share |
| ---: | --- | --- | --- | ---: | ---: |
| 1 | `0x10502f4` | `myl_native_bytes_find_any [native_bytes.c]` | `0xf4` | 627 | 1.98% |
| 2 | `0x104db9f` | `myl_native_heap_collect [native_heap.c]` | `0x23f` | 604 | 1.91% |
| 3 | `0x104dcf4` | `trace [native_heap.c]` | `0x104` | 591 | 1.87% |
| 4 | `0x104dc68` | `trace [native_heap.c]` | `0x78` | 410 | 1.30% |
| 5 | `0x10363f8` | `sexpr.parser::advance` | `0x198` | 337 | 1.07% |
| 6 | `0x1034f3f` | `sexpr.printer::is_short_list` | `0xff` | 326 | 1.03% |
| 7 | `0x1040535` | `sexpr.parser::parse_node` | `0x8a5` | 253 | 0.80% |
| 8 | `0x1035e2e` | `sexpr.tokenizer::next_raw` | `0xbee` | 231 | 0.73% |
| 9 | `0x10502f2` | `myl_native_bytes_find_any [native_bytes.c]` | `0xf2` | 220 | 0.70% |
| 10 | `0x1050467` | `buffer_grow_rooted [native_bytes.c]` | `0x157` | 184 | 0.58% |
| 11 | `0x103b6a1` | `sexpr.printer::scalar_len` | `0x131` | 182 | 0.58% |
| 12 | `0x10502ee` | `myl_native_bytes_find_any [native_bytes.c]` | `0xee` | 182 | 0.58% |
| 13 | `0x1030ca0` | `sexpr.printer::estimate_width` | `0x160` | 170 | 0.54% |
| 14 | `0x10361b8` | `sexpr.tokenizer::next_raw` | `0xf78` | 150 | 0.47% |
| 15 | `0x1035ee2` | `sexpr.tokenizer::next_raw` | `0xca2` | 135 | 0.43% |

`0x10502f4` — `myl_native_bytes_find_any [native_bytes.c]` +`0xf4` (1.98% of all samples)

```
    0x10502e6  shr    $0x6,%ecx
    0x10502e9  mov    -0x30(%rbp,%rcx,8),%rcx
    0x10502ee  bt     %rax,%rcx
    0x10502f2  jb     1050303 <myl_native_bytes_find_any+0x103>
==> 0x10502f4  inc    %rdi
    0x10502f7  cmp    %rdi,%r8
    0x10502fa  jne    10502e0 <myl_native_bytes_find_any+0xe0>
    0x10502fc  mov    $0xffffffffffffffff,%rdi
```

`0x104db9f` — `myl_native_heap_collect [native_heap.c]` +`0x23f` (1.91% of all samples)

```
    0x104db93  mov    (%rdi),%rdi
    0x104db96  test   %rdi,%rdi
    0x104db99  je     104dbb0 <myl_native_heap_collect+0x250>
    0x104db9b  cmpl   $0x0,0x2c(%rdi)
==> 0x104db9f  jne    104db90 <myl_native_heap_collect+0x230>
    0x104dba1  cmpl   $0x0,0x28(%rdi)
    0x104dba5  je     104db75 <myl_native_heap_collect+0x215>
    0x104dba7  movl   $0x0,0x28(%rdi)
```

`0x104dcf4` — `trace [native_heap.c]` +`0x104` (1.87% of all samples)

```
    0x104dce8  jae    104dcd0 <trace+0xe0>
    0x104dcea  cmpl   $0x0,0x20(%rcx)
    0x104dcee  jne    104dd61 <trace+0x171>
    0x104dcf0  cmpl   $0x0,-0x34(%rax)
==> 0x104dcf4  jne    104dd61 <trace+0x171>
    0x104dcf6  cmpl   $0x0,-0x38(%rax)
    0x104dcfa  jne    104dd61 <trace+0x171>
    0x104dcfc  lea    -0x60(%rax),%rcx
```

`0x104dc68` — `trace [native_heap.c]` +`0x78` (1.30% of all samples)

```
    0x104dc59  movl   $0x0,-0x2c(%rbp)
    0x104dc60  cmp    $0x4,%ecx
    0x104dc63  jne    104dc6b <trace+0x7b>
    0x104dc65  mov    (%r14),%eax
==> 0x104dc68  mov    %eax,-0x2c(%rbp)
    0x104dc6b  test   %r12,%r12
    0x104dc6e  je     104dd61 <trace+0x171>
    0x104dc74  mov    (%rdx),%r13
```

`0x10363f8` — `sexpr.parser::advance` +`0x198` (1.07% of all samples)

```
    0x10363e9  je     1036469 <myl_f_59c4bbc7071b8e5740b45acc273a5dd464bfcfe4b67081aa51105d0e1634c116+0x209>
    0x10363eb  test   %eax,%eax
    0x10363ed  jne    10363cd <myl_f_59c4bbc7071b8e5740b45acc273a5dd464bfcfe4b67081aa51105d0e1634c116+0x16d>
    0x10363ef  vmovups 0xb8(%rsp),%ymm0
==> 0x10363f8  vmovups 0xd8(%rsp),%xmm1
    0x1036401  mov    0xe8(%rsp),%rax
    0x1036409  mov    %rax,0x40(%r12)
    0x103640e  vmovups %xmm1,0x30(%r12)
```

### sexpr-qbe-census

`.tmp/perf-audit-20260921/sexpr-qbe`  ·  600 runs  ·  **23600 samples**  ·  outside the executable **17.8%**  ·  unmapped inside 0.33%

| class | samples | share of all samples |
| --- | ---: | ---: |
| guest | 10770 | 45.64% |
| runtime-c | 5991 | 25.39% |
| libc | 2564 | 10.86% |
| (outside the executable: libc, ld.so) | 4198 | 17.79% |

| # | function | class | samples | share |
| ---: | --- | --- | ---: | ---: |
| 1 | `sexpr.tokenizer::next_raw` | guest | 2311 | 9.79% |
| 2 | `trace [native_heap.c]` | runtime-c | 1982 | 8.40% |
| 3 | `memcpy` | libc | 1965 | 8.33% |
| 4 | `myl_native_bytes_find_any [native_bytes.c]` | runtime-c | 1789 | 7.58% |
| 5 | `sexpr.tokenizer::raw` | guest | 1429 | 6.06% |
| 6 | `sexpr.tokenizer::is_atom_continue` | guest | 1308 | 5.54% |
| 7 | `main::tally` | guest | 1111 | 4.71% |
| 8 | `sexpr.parser::parse_node` | guest | 1042 | 4.42% |
| 9 | `sexpr.parser::advance` | guest | 889 | 3.77% |
| 10 | `myl_native_heap_collect [native_heap.c]` | runtime-c | 887 | 3.76% |
| 11 | `sexpr.parser::parse_list` | guest | 751 | 3.18% |
| 12 | `sexpr.tokenizer::read_string` | guest | 636 | 2.69% |
| 13 | `memset` | libc | 599 | 2.54% |
| 14 | `myl_native_list_append [native_collections.c]` | runtime-c | 527 | 2.23% |
| 15 | `sexpr.parser::parse_leaf` | guest | 503 | 2.13% |
| 16 | `sexpr.tokenizer::read_atom` | guest | 363 | 1.54% |
| 17 | `myl_native_heap_alloc_at [native_heap.c]` | runtime-c | 226 | 0.96% |
| 18 | `sexpr.tokenizer::read_number` | guest | 214 | 0.91% |
| 19 | `sexpr.parser::view_of` | guest | 158 | 0.67% |
| 20 | `myl_qbe_heap [qbe_runtime.c]` | runtime-c | 147 | 0.62% |
| 21 | `myl_qbe_root_mark [qbe_runtime.c]` | runtime-c | 142 | 0.60% |
| 22 | `myl_native_bytes_number_parse` | runtime-c | 83 | 0.35% |
| 23 | `myl_native_list_new [native_collections.c]` | runtime-c | 54 | 0.23% |
| 24 | `myl_native_root_pop [native_heap.c]` | runtime-c | 52 | 0.22% |
| 25 | `sexpr.tokenizer::si_suffix_len` | guest | 52 | 0.22% |
| 26 | `myl_native_root_push [native_heap.c]` | runtime-c | 41 | 0.17% |
| 27 | `myl_native_arena_region [native_arena.c]` | runtime-c | 30 | 0.13% |
| 28 | `myl_native_object_region [native_heap.c]` | runtime-c | 10 | 0.04% |
| 29 | `myl_native_heap_alloc [native_heap.c]` | runtime-c | 4 | 0.02% |
| 30 | `myl_native_bytes_range [native_bytes.c]` | runtime-c | 4 | 0.02% |

Hottest individual instruction addresses:

| # | address | function | +offset | samples | share |
| ---: | --- | --- | --- | ---: | ---: |
| 1 | `0x103cb51` | `memcpy` | `0x141` | 962 | 4.08% |
| 2 | `0x10389c4` | `myl_native_bytes_find_any [native_bytes.c]` | `0xf4` | 703 | 2.98% |
| 3 | `0x103557f` | `myl_native_heap_collect [native_heap.c]` | `0x14f` | 621 | 2.63% |
| 4 | `0x10356b2` | `trace [native_heap.c]` | `0xe2` | 603 | 2.56% |
| 5 | `0x103cb6d` | `memcpy` | `0x15d` | 510 | 2.16% |
| 6 | `0x1035648` | `trace [native_heap.c]` | `0x78` | 405 | 1.72% |
| 7 | `0x102ca31` | `sexpr.tokenizer::raw` | `0x131` | 368 | 1.56% |
| 8 | `0x102ca57` | `sexpr.tokenizer::raw` | `0x157` | 339 | 1.44% |
| 9 | `0x1011aba` | `main::tally` | `0x41a` | 299 | 1.27% |
| 10 | `0x10389c2` | `myl_native_bytes_find_any [native_bytes.c]` | `0xf2` | 259 | 1.10% |
| 11 | `0x1014279` | `sexpr.parser::advance` | `0x339` | 232 | 0.98% |
| 12 | `0x10389be` | `myl_native_bytes_find_any [native_bytes.c]` | `0xee` | 193 | 0.82% |
| 13 | `0x103cbc6` | `memcpy` | `0x1b6` | 176 | 0.75% |
| 14 | `0x103c8a0` | `memset` | `0x0` | 175 | 0.74% |
| 15 | `0x103c915` | `memset` | `0x75` | 146 | 0.62% |

`0x103cb51` — `memcpy` +`0x141` (4.08% of all samples)

```
    0x103cb32  vmovups %ymm0,-0xa0(%rax,%r10,1)
    0x103cb3c  vmovaps -0x80(%rsi,%r10,1),%ymm0
    0x103cb43  vmovups %ymm0,-0x80(%rax,%r10,1)
    0x103cb4a  vmovaps -0x60(%rsi,%r10,1),%ymm0
==> 0x103cb51  vmovups %ymm0,-0x60(%rax,%r10,1)
    0x103cb58  vmovaps -0x40(%rsi,%r10,1),%ymm0
    0x103cb5f  vmovups %ymm0,-0x40(%rax,%r10,1)
    0x103cb66  vmovaps -0x20(%rsi,%r10,1),%ymm0
```

`0x10389c4` — `myl_native_bytes_find_any [native_bytes.c]` +`0xf4` (2.98% of all samples)

```
    0x10389b6  shr    $0x6,%ecx
    0x10389b9  mov    -0x30(%rbp,%rcx,8),%rcx
    0x10389be  bt     %rax,%rcx
    0x10389c2  jb     10389d3 <myl_native_bytes_find_any+0x103>
==> 0x10389c4  inc    %rdi
    0x10389c7  cmp    %rdi,%r8
    0x10389ca  jne    10389b0 <myl_native_bytes_find_any+0xe0>
    0x10389cc  mov    $0xffffffffffffffff,%rdi
```

`0x103557f` — `myl_native_heap_collect [native_heap.c]` +`0x14f` (2.63% of all samples)

```
    0x1035573  mov    (%rdi),%rdi
    0x1035576  test   %rdi,%rdi
    0x1035579  je     1035590 <myl_native_heap_collect+0x160>
    0x103557b  cmpl   $0x0,0x2c(%rdi)
==> 0x103557f  jne    1035570 <myl_native_heap_collect+0x140>
    0x1035581  cmpl   $0x0,0x28(%rdi)
    0x1035585  je     1035555 <myl_native_heap_collect+0x125>
    0x1035587  movl   $0x0,0x28(%rdi)
```

`0x10356b2` — `trace [native_heap.c]` +`0xe2` (2.56% of all samples)

```
    0x10356a4  call   1035930 <myl_native_arena_region>
    0x10356a9  test   %eax,%eax
    0x10356ab  jne    1035721 <trace+0x151>
    0x10356ad  cmpl   $0x0,-0x34(%r14)
==> 0x10356b2  jne    1035721 <trace+0x151>
    0x10356b4  cmpl   $0x0,-0x38(%r14)
    0x10356b9  jne    1035721 <trace+0x151>
    0x10356bb  lea    -0x60(%r14),%rax
```

`0x103cb6d` — `memcpy` +`0x15d` (2.16% of all samples)

```
    0x103cb51  vmovups %ymm0,-0x60(%rax,%r10,1)
    0x103cb58  vmovaps -0x40(%rsi,%r10,1),%ymm0
    0x103cb5f  vmovups %ymm0,-0x40(%rax,%r10,1)
    0x103cb66  vmovaps -0x20(%rsi,%r10,1),%ymm0
==> 0x103cb6d  vmovups %ymm0,-0x20(%rax,%r10,1)
    0x103cb74  vmovaps (%rsi,%r10,1),%ymm0
    0x103cb7a  vmovups %ymm0,(%rax,%r10,1)
    0x103cb80  add    $0x8,%r9
```

### sexpr-qbe-render

`.tmp/perf-audit-20260921/sexpr-qbe`  ·  600 runs  ·  **43663 samples**  ·  outside the executable **13.9%**  ·  unmapped inside 1.46%

| class | samples | share of all samples |
| --- | ---: | ---: |
| guest | 19589 | 44.86% |
| runtime-c | 9697 | 22.21% |
| libc | 7690 | 17.61% |
| (outside the executable: libc, ld.so) | 6051 | 13.86% |

| # | function | class | samples | share |
| ---: | --- | --- | ---: | ---: |
| 1 | `memcpy` | libc | 5508 | 12.61% |
| 2 | `sexpr.printer::push_node` | guest | 4605 | 10.55% |
| 3 | `sexpr.tokenizer::next_raw` | guest | 2325 | 5.32% |
| 4 | `sexpr.printer::estimate_width` | guest | 2226 | 5.10% |
| 5 | `memset` | libc | 2166 | 4.96% |
| 6 | `trace [native_heap.c]` | runtime-c | 1977 | 4.53% |
| 7 | `myl_native_bytes_find_any [native_bytes.c]` | runtime-c | 1654 | 3.79% |
| 8 | `sexpr.tokenizer::raw` | guest | 1446 | 3.31% |
| 9 | `sexpr.tokenizer::is_atom_continue` | guest | 1377 | 3.15% |
| 10 | `sexpr.parser::parse_node` | guest | 1126 | 2.58% |
| 11 | `sexpr.parser::advance` | guest | 1005 | 2.30% |
| 12 | `myl_native_heap_collect [native_heap.c]` | runtime-c | 893 | 2.05% |
| 13 | `scalar_count [native_bytes.c]` | runtime-c | 826 | 1.89% |
| 14 | `sexpr.printer::is_short_list` | guest | 779 | 1.78% |
| 15 | `myl_native_bytes_buffer_append_range [native_bytes.c]` | runtime-c | 765 | 1.75% |
| 16 | `sexpr.parser::parse_list` | guest | 742 | 1.70% |
| 17 | `byte_builder::append` | guest | 731 | 1.67% |
| 18 | `myl_qbe_heap [qbe_runtime.c]` | runtime-c | 721 | 1.65% |
| 19 | `sexpr.tokenizer::read_string` | guest | 629 | 1.44% |
| 20 | `sexpr.parser::parse_leaf` | guest | 534 | 1.22% |
| 21 | `myl_native_list_append [native_collections.c]` | runtime-c | 505 | 1.16% |
| 22 | `myl_qbe_root_mark [qbe_runtime.c]` | runtime-c | 480 | 1.10% |
| 23 | `myl_native_object_immortal [native_heap.c]` | runtime-c | 377 | 0.86% |
| 24 | `sexpr.tokenizer::read_atom` | guest | 348 | 0.80% |
| 25 | `sexpr.printer::scalar_len` | guest | 341 | 0.78% |
| 26 | `myl_native_heap_alloc_at [native_heap.c]` | runtime-c | 335 | 0.77% |
| 27 | `byte_builder::append_range` | guest | 305 | 0.70% |
| 28 | `buffer_grow_rooted [native_bytes.c]` | runtime-c | 294 | 0.67% |
| 29 | `sexpr.printer::append_view` | guest | 239 | 0.55% |
| 30 | `byte_builder::append_spaces` | guest | 225 | 0.52% |

Hottest individual instruction addresses:

| # | address | function | +offset | samples | share |
| ---: | --- | --- | --- | ---: | ---: |
| 1 | `0x103cb51` | `memcpy` | `0x141` | 1010 | 2.31% |
| 2 | `0x103cb43` | `memcpy` | `0x133` | 989 | 2.27% |
| 3 | `0x103cb6d` | `memcpy` | `0x15d` | 712 | 1.63% |
| 4 | `0x103cb0a` | `memcpy` | `0xfa` | 668 | 1.53% |
| 5 | `0x10389c4` | `myl_native_bytes_find_any [native_bytes.c]` | `0xf4` | 649 | 1.49% |
| 6 | `0x103c8a0` | `memset` | `0x0` | 631 | 1.45% |
| 7 | `0x103557f` | `myl_native_heap_collect [native_heap.c]` | `0x14f` | 623 | 1.43% |
| 8 | `0x10356b2` | `trace [native_heap.c]` | `0xe2` | 604 | 1.38% |
| 9 | `0x103c915` | `memset` | `0x75` | 559 | 1.28% |
| 10 | `0x10339ac` | `myl_qbe_heap [qbe_runtime.c]` | `0xc` | 449 | 1.03% |
| 11 | `0x103c92c` | `memset` | `0x8c` | 423 | 0.97% |
| 12 | `0x1035648` | `trace [native_heap.c]` | `0x78` | 382 | 0.87% |
| 13 | `0x102ca31` | `sexpr.tokenizer::raw` | `0x131` | 381 | 0.87% |
| 14 | `0x103cb5f` | `memcpy` | `0x14f` | 380 | 0.87% |
| 15 | `0x102ca57` | `sexpr.tokenizer::raw` | `0x157` | 376 | 0.86% |

`0x103cb51` — `memcpy` +`0x141` (2.31% of all samples)

```
    0x103cb32  vmovups %ymm0,-0xa0(%rax,%r10,1)
    0x103cb3c  vmovaps -0x80(%rsi,%r10,1),%ymm0
    0x103cb43  vmovups %ymm0,-0x80(%rax,%r10,1)
    0x103cb4a  vmovaps -0x60(%rsi,%r10,1),%ymm0
==> 0x103cb51  vmovups %ymm0,-0x60(%rax,%r10,1)
    0x103cb58  vmovaps -0x40(%rsi,%r10,1),%ymm0
    0x103cb5f  vmovups %ymm0,-0x40(%rax,%r10,1)
    0x103cb66  vmovaps -0x20(%rsi,%r10,1),%ymm0
```

`0x103cb43` — `memcpy` +`0x133` (2.27% of all samples)

```
    0x103cb1e  vmovups %ymm0,-0xc0(%rax,%r10,1)
    0x103cb28  vmovaps -0xa0(%rsi,%r10,1),%ymm0
    0x103cb32  vmovups %ymm0,-0xa0(%rax,%r10,1)
    0x103cb3c  vmovaps -0x80(%rsi,%r10,1),%ymm0
==> 0x103cb43  vmovups %ymm0,-0x80(%rax,%r10,1)
    0x103cb4a  vmovaps -0x60(%rsi,%r10,1),%ymm0
    0x103cb51  vmovups %ymm0,-0x60(%rax,%r10,1)
    0x103cb58  vmovaps -0x40(%rsi,%r10,1),%ymm0
```

`0x103cb6d` — `memcpy` +`0x15d` (1.63% of all samples)

```
    0x103cb51  vmovups %ymm0,-0x60(%rax,%r10,1)
    0x103cb58  vmovaps -0x40(%rsi,%r10,1),%ymm0
    0x103cb5f  vmovups %ymm0,-0x40(%rax,%r10,1)
    0x103cb66  vmovaps -0x20(%rsi,%r10,1),%ymm0
==> 0x103cb6d  vmovups %ymm0,-0x20(%rax,%r10,1)
    0x103cb74  vmovaps (%rsi,%r10,1),%ymm0
    0x103cb7a  vmovups %ymm0,(%rax,%r10,1)
    0x103cb80  add    $0x8,%r9
```

`0x103cb0a` — `memcpy` +`0xfa` (1.53% of all samples)

```
    0x103caeb  sub    %rdi,%r10
    0x103caee  xor    %r9d,%r9d
    0x103caf1  data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
    0x103cb00  vmovaps -0xe0(%rsi,%r10,1),%ymm0
==> 0x103cb0a  vmovups %ymm0,-0xe0(%rax,%r10,1)
    0x103cb14  vmovaps -0xc0(%rsi,%r10,1),%ymm0
    0x103cb1e  vmovups %ymm0,-0xc0(%rax,%r10,1)
```

`0x10389c4` — `myl_native_bytes_find_any [native_bytes.c]` +`0xf4` (1.49% of all samples)

```
    0x10389b6  shr    $0x6,%ecx
    0x10389b9  mov    -0x30(%rbp,%rcx,8),%rcx
    0x10389be  bt     %rax,%rcx
    0x10389c2  jb     10389d3 <myl_native_bytes_find_any+0x103>
==> 0x10389c4  inc    %rdi
    0x10389c7  cmp    %rdi,%r8
    0x10389ca  jne    10389b0 <myl_native_bytes_find_any+0xe0>
    0x10389cc  mov    $0xffffffffffffffff,%rdi
```

