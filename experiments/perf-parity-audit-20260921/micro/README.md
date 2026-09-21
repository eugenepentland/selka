# Matched micro-kernel suite — mylang versus Zig

Eleven small kernels, each written twice: once as `<name>.my` and once as
`<name>.zig`. Every kernel prints exactly one checksum line, and the harness
refuses to time a kernel whose arms do not print byte-identical output. The
point is attribution: an application benchmark says *mylang is N× Zig*, and
this suite says *which primitive* pays for it.

Nothing here is wired into `zig build`; it is a standalone measurement that
uses the already-installed `zig-out/bin/mylang` and the `zig` on `PATH`.

## The kernels

| file | what it isolates |
| --- | --- |
| `intloop` | checked integer `+`, `*`, `%` in a loop-carried dependency |
| `calls` | an ordinary call to a two-argument leaf function, 30,000,000 times |
| `fib` | the call/frame protocol at depth (naive `fib(36)`) |
| `records` | constructing a 3-field value record and passing it by value |
| `list_append_sum` | growing `list[int]` by `append`, then one fold |
| `list_records` | a list of 2,000,000 32-byte records, ten field-summing passes |
| `dict_count` | `dict[str, int]` read-modify-write over 1000 short string keys |
| `str_build` | 16,000,000 eight-byte appends into a growable byte buffer |
| `alloc_churn` | build/fold/drop a 16-element list once per batch, 1,000,000 batches |
| `float_loop` | a binary64 multiply-add-sqrt dependency chain |
| `bytes_scan` | indexing an 8 MiB `bytes` value sixteen times, counting one octet |

`calls_inline.zig`, `dict_count_getorput.zig` and `alloc_churn_gpa.zig` are
extra Zig variants; `alloc_churn_arena.my` is the extra mylang variant that
wraps each batch in `with arena():`. `common.zig` holds the Zig side's
one-line stdout writer and `opaqueN`, a volatile load that always yields 1 —
it keeps a compile-time loop bound opaque so LLVM cannot fold a whole kernel
away. The mylang side needs no such guard.

## Arms

| arm | build |
| --- | --- |
| `mylang-qbe` | `mylang build X.my -o OUT --mode ReleaseFast --cache-dir CACHE` |
| `mylang-o3` | the same plus `--backend llvm --llvm-opt 3` |
| `mylang-o3-lto` | the same plus `--backend llvm --llvm-opt 3 --lto` |
| `zig-fast` | `zig build-exe X.zig -O ReleaseFast -femit-bin=OUT` (the reference) |
| `zig-safe` | the same with `-O ReleaseSafe` |

`zig-fast` is the denominator of every ratio. `zig-safe` is the closer
semantic match, because mylang keeps its overflow and bounds checks in
ReleaseFast and Zig's ReleaseFast does not.

## Reproduce

Run from the repository root, with the machine otherwise idle. The compiler
must already be installed (`zig build`); the harness never builds it.

```bash
python3 experiments/perf-parity-audit-20260921/micro/run.py
```

That writes `results.json` (every raw sample, medians, ratios, checksums,
build commands, binary SHA-256s and peak RSS) and `results.md` (the tables)
next to `run.py`, and puts every binary and object cache under
`.tmp/perf-audit-20260921/micro/`, which is gitignored.

Useful options:

- `--only NAME` (repeatable) restricts the run to one kernel.
- `--rounds N` / `--warmups N` change the timing protocol (default 15 and 3).
- `--cpu N` picks the pinned core (default 6).
- `--skip-build` reuses binaries already in the work directory.
- `--work DIR`, `--json PATH`, `--markdown PATH` move the outputs.

A full run takes roughly 25 minutes, almost all of it in `dict_count`, where
the mylang arms are three to four orders of magnitude slower than Zig's.

## Protocol

1. **Build** every arm. A failed build is printed with the compiler's stderr
   and recorded in `results.json`; that kernel is excluded from timing.
2. **Qualify**: run each arm once and compare stdout byte for byte. A kernel
   whose arms disagree is reported and excluded from the ratios.
3. **Peak RSS**: `/usr/bin/time -f %M` once per arm, before any timing.
4. **Time**: 3 warmup rounds then 15 measured rounds. Inside each round the
   arm order is reshuffled from a fixed seed, so a drift in machine state
   spreads across arms instead of landing on one. Each sample is a fresh
   `taskset -c 6 BINARY` process with stdout to `/dev/null`, timed with
   `perf_counter_ns` around a blocking `waitpid`.

Do not pass `timeout=` to the timed `subprocess` call: CPython's timeout path
polls the child with a backoff capped at 50 ms, which quantises every sample
onto a 50 ms grid. `run.py` uses `Popen` + blocking `wait()` for that reason.

## Reading the results

`results.md` ends with a **Notes** section naming every kernel whose two
implementations are not strictly matched, and why. Read it before quoting a
ratio: `bytes_scan` and `list_append_sum` compare a vectorised Zig loop
against a scalar mylang one, `calls` is dominated by its callee's `%` rather
than by the call, and `alloc_churn` deliberately compares four different
memory strategies.
