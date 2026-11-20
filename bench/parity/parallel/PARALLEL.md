# Parallel scaling programs (Selka, Zig and Rust)

Three programs, each written in Selka (`.selka`), Zig (`.zig`) and Rust (`.rs`), with **the same algorithm, the same
work split and the same output**, run at 1, 2, 4 and 8 threads. They measure how the thread pool scales, and how
Selka's pool compares with a plain Zig or Rust pool doing the same work. Threads are allowed here, unlike the
single-threaded program suite in `bench/parity/suite/SUITE.md`, and the programs are not pinned to CPUs.

## Shared work

`work(seed, rounds)` is the unit of work every program repeats. Everything is integer arithmetic; no program
overflows 64 bits.

```
work(seed, rounds):
    t = seed mod 1000003
    for i in 0 .. rounds-1:
        t = (t * 31 + i) mod 1000003
    return t
```

`MODULUS = 1000003`. Each program prints one line, and only that line.

## Program 1: `map_work` (parallel.map over independent items)

`items = 4096`, `rounds = 100000`. The item `x` has the value `work(x, rounds)`, and the program sums the values.

```
map_work 4096 100000 checksum 2048809542
```

Selka: `parallel.map(xs, work, rounds)` over `xs = [0 .. items-1]`, then the sum of the results.

## Program 2: `group_tasks` (a task group of independent tasks)

Eight tasks, each over 512 items. Task `j` (for `j = 0 .. 7`) sums `work(x, rounds)` over `x` in
`[512j, 512j + 511]`. The checksum is the sum of the eight task results, which equals program 1's checksum
because the same items are summed.

```
group_tasks 8 512 100000 checksum 2048809542
```

Selka: a `with parallel.group() as g:` block with eight `g.submit(span, first, 512, rounds)` handles, read with
`t.result()`. Zig and Rust: eight task slots pulled by the workers.

## Program 3: `shared_model` (parallel.map reading one shared list)

A shared list `model` of `1048576` integers, built once before the timed map:
`model[k] = (k * 2654435761 + 12345) mod 1000003`, for `k = 0 .. 1048575`.

The item `x` (for `x = 0 .. 4095`) has the value `s mod 1000003 + work(x, rounds)`, where
`s = sum over j = 0 .. 999 of model[(x * 7919 + j * 104729) mod 1048576]`, with `rounds = 100000`. Every thread reads
the same list, and nothing is copied: in Selka the list is lent to every item as a trailing argument
(`parallel.map(xs, lookup, model, rounds)`).

```
shared_model 4096 100000 checksum 4087409215
```

## Work split (the same in all three languages)

A map over `N` items on `T` threads is split into `C` contiguous chunks, with `C = 1` when `T = 1` and `C = 4T`
otherwise, never more than `N`. Chunk `c` starts at `c * q + min(c, r)` and holds `q + (c < r)` items, where
`q = N div C` and `r = N mod C`. This is the split `myl_core_map_chunks` makes in the Selka runtime. Zig and Rust
hand the chunks to their `T` workers in order, through one atomic counter, and sum the chunks' results.
`group_tasks` has eight fixed tasks, pulled by `T` workers in order.

## Threads

The thread count is the environment variable `SELKA_THREADS`, for every language. Selka's runtime reads it
(`--threads` on `selka run` sets the same variable for a run). Zig and Rust read it in `common.zig` and
`common.rs`. The count is `T` worker threads plus no other thread that does work.

## Build and run

- Selka: `selka build PROGRAM.selka -o BIN --release`, with the installed compiler (`zig-out/bin/selka`).
- Zig: `zig build-exe -OReleaseFast PROGRAM.zig -femit-bin=BIN` with the pinned toolchain (`.zigversion`), with
  `common.zig` beside it.
- Rust: `rustc -C opt-level=3 -C codegen-units=1 -C target-cpu=native -C panic=abort PROGRAM.rs -o BIN`, with
  `common.rs` beside it, using `~/.cargo/bin/rustc`. Standard library only, no crates.

## Timing

`time_parallel.py` builds every port, runs every binary at `T = 1, 2, 4, 8` with `SELKA_THREADS=T`, does one
untimed warm-up run and then five timed runs, and takes the median. A run's time is the wall time of the whole
process (start, the shared list's construction, the parallel part, and exit). Each run's stdout must equal the
program's `.expected` line, or the run fails. The script runs inside one `scripts/build-slot.sh timing …` window,
unpinned, so that no other admitted job runs while it measures. The parity harness (`bench/parity/bench_parity.py`) pins
each sample to one CPU, which is not wanted here, so this group has its own script.

The report gives, per program, the median wall time of each language at each thread count, the Selka/Zig and
Selka/Rust ratios at each count, and each language's own speedup at 8 threads (its 1-thread median over its
8-thread median). When Selka's 8-thread median is more than 1.25 times Zig's, the result is profiled and explained
in the write-up (scheduler, chunking, allocation contention, false sharing, or a missing lend).

## Deviations from the Zig and Rust pools

- Zig 0.17-dev (the pinned toolchain) has no `std.Thread.Pool` and no `std.Thread.WaitGroup`. The Zig ports use
  `std.Thread.spawn` workers that pull chunks through one `std.atomic.Value` counter, and `join` them. The work
  split, the thread count and the output are the same as a pool's.
- Rust uses `std::thread::scope` with the same atomic-counter pull, as the Zig port does.
