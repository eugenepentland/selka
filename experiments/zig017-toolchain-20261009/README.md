# Zig 0.17.0 versus the pinned and custom toolchains

Local measurements on the Intel i7-12700H, 9–10 October 2026. Official release
metadata and the verified download checksum are in `metadata.json`.
The release index lists 0.17.0 on 1 October 2026:
[official index](https://ziglang.org/download/index.json).

## Compiler build time and runtime

The native x86 rows force `-fno-llvm` on every toolchain. The LLVM rows
force `-fllvm`, the official compiler’s normal optimized configuration.
The custom EDA package has no LLVM backend. Compiler build mode is
independent of the optimization mode of any Selka program it compiles.

| Toolchain | Mode/backend | Clean build | Build peak RSS | Type check | Core IR generation | IR peak RSS |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Custom EDA | Debug / native x86 | 5.43 s | 472.9 MiB | 228.5 ms | 187.1 ms | 46.8 MiB |
| Official 0.17.0 | Debug / native x86 | 5.58 s | 516.8 MiB | 245.3 ms | 214.5 ms | 48.4 MiB |
| Pinned dev.1683 | Debug / native x86 | 5.61 s | 506.3 MiB | 253.6 ms | 222.0 ms | 47.9 MiB |
| Custom EDA | ReleaseSafe / native x86 | 5.82 s | 462.3 MiB | 249.0 ms | 192.2 ms | 46.5 MiB |
| Official 0.17.0 | ReleaseSafe / native x86 | 5.41 s | 505.7 MiB | 244.3 ms | 235.7 ms | 47.2 MiB |
| Pinned dev.1683 | ReleaseSafe / native x86 | 5.49 s | 495.1 MiB | 253.1 ms | 233.7 ms | 46.9 MiB |
| Official 0.17.0 | ReleaseSafe / LLVM | 218.81 s | 3504.8 MiB | 37.3 ms | 41.8 ms | 38.4 MiB |
| Pinned dev.1683 | ReleaseSafe / LLVM | 196.88 s | 3472.4 MiB | 38.1 ms | 42.2 ms | 38.1 MiB |

### Method and limits

- Three clean-project-cache build samples for each native row; one for each LLVM row.
  Each successful build was followed by an unchanged build. Native unchanged builds
  took roughly 20–40 ms. The shared Zig global cache and OS file cache were warm.
  Initial compatibility attempts and build-runner provisioning are excluded.
- This measures compiler-only construction through a matching standalone module
  graph, excluding Guardian, component provisioning, and test execution. The
  embedded number-formatting helper uses native x86 code generation in every arm.
  No strip flag is used, matching the current Selka build; this does not measure
  the custom compiler’s best-case stripped EDA application configuration.
- Runtime uses seven alternating-order samples after a warmup, pinned to CPU 2.
  CPU 2 is locked for these timings; sibling CPU activity is recorded per sample.
  No project builds ran in the final window, but another prebuilt benchmark
  used the separate reserved CPU 10. This is a shared-machine comparison,
  not whole-machine isolation. No filesystem cache eviction or governor change.
- `frontend.my` is 256 functions plus `main`, 3,078 lines / 99,181 bytes.
  Type checking passes `--no-cache`. `dump-ir` performs a fresh frontend check
  and Core lowering/rendering in a new process, without external code generation.
  All arms have byte-identical outputs. These timings do not measure linked
  guest-program execution, an entire project gate, or incremental compiler edits.
- Peak RSS comes from GNU time: the largest process including child usage,
  not the sum of simultaneous processes. Runtime includes process startup.
- All arms use one frozen source snapshot from the self-hosting wave worktree.
  0.17 adds `ArrayList.pointer_stability`, so eight direct initializers in five
  files were expressed through `.empty` / `fromOwnedSlice` in **every** arm.
  `compatibility.patch` records the exact adjustment. No production source or
  toolchain pin was changed. This is a comparison, not upgrade qualification.

## SHA-256 transition regression

The SHA-256 source file is byte-identical across all three toolchains.
All probes stream through 64 KiB buffers and match an independent Python
SHA-256 digest. The following are three-run medians for the same 16 MiB file,
after warmup, using each toolchain’s default backend for that mode.

| Toolchain | Mode | Native CPU | Baseline CPU |
| --- | --- | ---: | ---: |
| Pinned dev.1683 | Debug | 1840.5 ms | 1027.5 ms |
| Pinned dev.1683 | ReleaseSafe | 16.1 ms | 60.1 ms |
| Pinned dev.1683 | ReleaseFast | 1335.1 ms | 61.6 ms |
| Custom EDA | Debug | 1831.2 ms | 544.6 ms |
| Custom EDA | ReleaseSafe | 1817.1 ms | 563.8 ms |
| Custom EDA | ReleaseFast | 1796.1 ms | 444.4 ms |
| Official 0.17.0 | Debug | 1785.6 ms | 865.6 ms |
| Official 0.17.0 | ReleaseSafe | 16.1 ms | 60.7 ms |
| Official 0.17.0 | ReleaseFast | 15.7 ms | 61.1 ms |

The actual ReleaseFast coordinator was also rebuilt with each toolchain.
Each row below is one CPU-pinned `--seed-only` verification of the same
existing qualified seed and the same pinned Zig files, including `perf`.
All returned the same seed executable; no seed compilation is included.

| Coordinator compiler/CPU | Verification | Peak RSS | SSE/AVX transition assists |
| --- | ---: | ---: | ---: |
| pinned-native | 34.83 s | 37.5 MiB | 591,707,471 |
| release-native | 0.41 s | 37.5 MiB | 0 |
| pinned-baseline | 1.49 s | 37.5 MiB | 0 |
| release-baseline | 1.43 s | 37.5 MiB | 0 |
| custom-native | 49.92 s | 37.5 MiB | 759,313,699 |
| custom-baseline | 12.80 s | 37.5 MiB | 0 |

A followup alternated three uninstrumented samples after warmup:

| Coordinator | Median verification | Median peak RSS |
| --- | ---: | ---: |
| pinned-baseline | 1.390 s | 38.3 MiB |
| pinned-safe-native | 0.405 s | 38.3 MiB |
| release-native | 0.386 s | 38.3 MiB |

`pinned-safe-native` uses LLVM ReleaseSafe instead of ReleaseFast. It is
the build-mode workaround now selected for the production coordinator with
the existing pin and explicit LLVM. The separate perf run reports
one transition assist over the entire seed verification, versus hundreds of
millions in the old native-CPU ReleaseFast build. Neither workaround changes
the pinned Zig compiler or constitutes a general fix to its native backend.

The released compiler eliminates the observed ReleaseFast/LLVM coordinator
regression: roughly 592 million transition assists become zero. This is
an empirical result for these reproductions, not a claim that all related
code-generation cases are fixed. Its Debug native backend still produces
about 29.36 million assists on the 16 MiB probe. Explicit ReleaseSafe
`-fno-llvm` reproduces the same issue on both official snapshots; the custom
compiler also reproduces it. Optimized LLVM and native x86 must therefore
be distinguished when describing the fix.

The old LLVM ReleaseFast probe holds 256-bit YMM state across legacy SHA
instructions. The release’s corresponding SHA round uses 128-bit state.
Both toolchains report clang 22.1.8, so this report does not attribute the
difference to a particular upstream LLVM release or commit.

## Validation and reproduction

- 56 representative source checks passed across all eight compiler artifacts.
- Frozen sources and the final retained binary for each build configuration
  were checked against their latest successful build receipts.
- All timed compiler outputs and hash outputs match across toolchains.
- No Guardian gate was exercised by this isolated experiment.

From the worktree root:

```sh
scripts/build-slot.sh build python3 experiments/zig017-toolchain-20261009/build_hashes.py
scripts/build-slot.sh build python3 experiments/zig017-toolchain-20261009/build_compilers.py
scripts/build-slot.sh build python3 experiments/zig017-toolchain-20261009/build_compilers.py --llvm
scripts/build-slot.sh build python3 experiments/zig017-toolchain-20261009/build_coordinators.py
python3 experiments/zig017-toolchain-20261009/qualify.py
python3 experiments/zig017-toolchain-20261009/quiet.py python3 experiments/zig017-toolchain-20261009/measure.py frontend
python3 experiments/zig017-toolchain-20261009/measure.py hash
python3 experiments/zig017-toolchain-20261009/measure_coordinators.py
python3 experiments/zig017-toolchain-20261009/measure_coordinator_followup.py
python3 experiments/zig017-toolchain-20261009/summarize.py
```

Toolchain paths are in `build_hashes.py`; binary hashes and host information
are in `metadata.json`. `source-manifest.json` covers the frozen compiler
snapshot. Commands, results and raw counters are retained in the adjacent
JSON, log and perf files. Build caches and binaries remain under the worktree’s
ignored `.mylang-cache/zig017-toolchain-20261009/` directory.
