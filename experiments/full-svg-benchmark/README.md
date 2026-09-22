# Actual NetLisp versus mylang full SVG benchmark

This benchmark uses the existing EDA NetLisp evaluator and Functional SVG
renderer. It compares the complete source-to-per-hub-SVG implementations on
the frozen one-hub LMX2595 circuit and two source edits. The algorithms and SVG bytes differ;
this is not an isolated compiler or matched-algorithm language benchmark.

Three further arms are **native ports of the mylang guest itself** — Rust at
`-C opt-level=3`, Zig at `-O ReleaseFast`, and Go at its default optimizing
compilation. They run the same parse, validation, model, placement, routing and
serialization steps as `src/schematic/guest/*.my` and are required to reproduce
its SVG bytes exactly, so mylang, Rust, Go and Zig can be compared on one
matched algorithm. NetLisp remains a different engine and is reported
separately.

See the [results and limitations](../../docs/audits/full-svg-netlisp-benchmark-2026-09-21.md)
and the [four-language port report](../../docs/audits/full-svg-native-ports-2026-09-21.md).

From the mylang repository root, using the recorded compiler and EDA revision:

```sh
python3 experiments/full-svg-benchmark/prepare_fixtures.py
python3 experiments/full-svg-benchmark/build_mylang.py
bash experiments/full-svg-benchmark/build_netlisp_llvm.sh
python3 experiments/full-svg-benchmark/build_native.py      # Rust, Go, Zig arms
python3 experiments/full-svg-benchmark/qualify.py
python3 experiments/full-svg-benchmark/differential.py      # malformed inputs
python3 experiments/full-svg-benchmark/measure.py
```

`build_native.py` needs `rustc` (default `~/.cargo/bin/rustc`), `go` and the
repository's pinned `./zigw`, and installs the arms at
`.tmp/full-svg-benchmark-20260921/{rust-o3,go-fast,zig-o3}` where `measure.py`
expects them. `ports/check_native.sh <binary>` checks one build against the
mylang SVG bytes on its own.

`build_netlisp_llvm.sh` expects the isolated worktree recorded in
`netlisp-llvm-provenance.json`; `EDA_WORKTREE` can select another isolated
worktree at revision `2a8d901174255ff8fa3e4840acd35a041e39c9a8`.
It copies only `netlisp_bench.zig` into that worktree's `src/`, generates the
normal embedded standard-library table, and directly compiles the harness.
It does not modify the EDA engine or install over the running NetLisp binary.
The fixture preparer reads the local EDA design library; consult the recorded
hashes before reproducing against a library that may have changed.

The mylang compiler must include the LLVM/build and host-bridge work identified
by `provenance.json`; the repository contained existing uncommitted changes.
All guest sources, the native provider, installed compiler and adapter files
are hashed. Build reports retain compiler backend, mode, optimization and LTO.
Both benchmark build scripts retain symbols and use private output paths.

`qualify.py` checks the actual model, SVG content, source mutations, layout
differences, equal output within optimization families, and mylang GC stress.
It also requires the three native arms to reproduce the mylang SVG bytes on all
three cases. `differential.py` goes further: it mutates each document, runs the
mylang guest and every native arm on the same bytes and requires the same
located issue code, the same process status and no published SVG. `measure.py`
requires that qualification, runs three warmups and 31 randomized
rounds on CPU 6, verifies every output, and then measures peak RSS separately.
Do not run qualification, builds or another benchmark concurrently with timing;
the scripts share per-arm scratch output paths. No server is needed.

## Native ports

`ports/{rust,go,zig}` are one algorithm in three more languages. Each is a
single source file with no third-party dependencies, and each replaces the
guest's per-byte host interface with one read of each document; everything else
— the flat node list, the validation order, the net graph and its 128-pass
relaxation, row collection and splitting, `branch`/`endpoint` geometry, the
routing ladder, and the SVG writers — is step-for-step the mylang guest's.
They are ports, not rewrites: where the guest does something odd (the
`at()`-out-of-range empty node, the value-copy snapshots inside the relaxation
loop, `j = len(parts)` as a loop break, `pre = empty` on a rename) the ports
keep it, because the byte-identity requirement makes each of those load-bearing.

| arm | source | flags |
|---|---|---|
| `rust-o3` | `ports/rust/main.rs` | `rustc -C opt-level=3 -C codegen-units=1 -C debug-assertions=off` |
| `go-fast` | `ports/go/main.go` | `go build` (default optimization; Go has no -O level) |
| `zig-o3` | `ports/zig/main.zig` | `zig build-exe -O ReleaseFast -fllvm` |

`python3 experiments/full-svg-benchmark/build_native.py` builds all three,
records the toolchains, flags, source and binary hashes in
`native-provenance.json`, and re-checks the SVG bytes (`native-check.txt`).
`python3 experiments/full-svg-benchmark/differential.py` writes
`native-differential.json`.

## Results

Median process wall clock in milliseconds, 31 randomized interleaved rounds
after three warmups, every process pinned to CPU 6, every run checked against
the exact expected SVG hash. Full tables, intervals, memory and caveats:
[the report](../../docs/audits/full-svg-native-ports-2026-09-21.md).

| Implementation | fixture | changed-net | changed-value | ÷ zig-o3 |
|---|---:|---:|---:|---:|
| zig-o3 | **1.554** | **1.561** | **1.538** | 1.00× |
| rust-o3 | 1.720 | 1.723 | 1.704 | 1.11× |
| go-fast | 2.209 | 2.205 | 2.165 | 1.42× |
| netlisp-llvm-fast (different engine) | 2.695 | 2.678 | 2.705 | 1.73× |
| netlisp-llvm-safe (different engine) | 2.862 | 2.823 | 2.880 | 1.84× |
| mylang-o3 | 18.903 | 19.355 | 19.108 | 12.16× |
| mylang-o3-lto | 37.229 | 37.456 | 36.870 | 23.96× |
| mylang-o3-bounded | 46.452 | 46.791 | 46.715 | 29.89× |

The matched-algorithm comparison is the three ports against `mylang-o3`: one
algorithm, byte-identical output. NetLisp is a different engine producing
different bytes and is shown only for scale. The figure lives at
`docs/audits/figures/full-svg-native-ports-2026-09-21.png`.

| Evidence | Contents |
|---|---|
| `measurements.json` | 465 individual timings, medians, percentiles and paired bootstrap intervals |
| `memory.json` | Five peak-RSS samples for every case and build |
| `qualification.json` | Model/output/GC checks and exact cross-engine placement differences |
| `artifacts/` | Six SVGs and three evaluated NetLisp model dumps |
| `fixture-provenance.json` | Frozen input paths, variants, dependency hashes |
| `read-closure.json`, `netlisp-read-trace.txt` | Independent proof of NetLisp's successful file reads |
| `provenance.json` | Machine, mylang source/compiler hashes, flags and worktree status |
| `netlisp-llvm-provenance.json` | EDA revision, source/stdlib hashes, Zig flags and binary hashes |
| `native-provenance.json`, `native-check.txt` | Rust/Go/Zig toolchains, flags, source and binary hashes, SVG equality |
| `native-differential.json` | Per-mutant issue code and status for all three ports against the mylang guest |
| `mylang-*-build.json` | Compiler build reports |

The untimed read-closure trace was captured with:

```sh
strace -f -qq -e trace=%file -o experiments/full-svg-benchmark/netlisp-read-trace.txt \
  .tmp/full-svg-benchmark-20260921/netlisp-llvm-fast \
  .tmp/full-svg-benchmark-20260921/projects/fixture straps-synth-lmx2595 \
  .tmp/full-svg-benchmark-20260921/trace.svg
```

Successful input `openat` paths were checked against the staged project and
their contents hashed against `fixture-provenance.json`. The binary's embedded
standard-library fallback is captured by the NetLisp build provenance; the
filesystem trace cannot establish use of individual embedded entries.
