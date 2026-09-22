# Full-SVG LTO regression isolation

The retained benchmark measured standalone LLVM O3 at 17.567 ms and full LTO
at 34.593 ms with byte-identical SVG output. Static inspection and userspace
PC sampling isolate the regression to guest code generation, especially
`layout::partPin`.

The non-LTO compiler lowers each guest unit to native assembly before the
final link. Its `partPin` copies a 112-byte `Pin` record with YMM `vmovups`
loads and stores. Full LTO retains each guest unit as LLVM bitcode. The final
LTO path does not preserve the effective guest target features used by the
native-assembly path, and lowers the same
fixed-size copies to `rep movsq` with `ecx = 14`. The hottest sampled full-LTO
PC is the instruction immediately following that repeat-string operation.

The O3 and bounded-O3 phase probes report zero collections and 77 allocations;
the LTO feature probes retain the same GC configuration. The LTO regression
is not explained by cross-unit runtime
optimization: the native-guest/LTO-runtime hybrid preserves O3's `partPin`
assembly, while the LTO-guest/native-runtime hybrid reproduces LTO's assembly.
Adding `noinline` to every guest function does not alter the fixed-size copy
lowering. Adding `-march=native` only to the final link, or only to the command
that ingests pre-authored textual IR, also does not attach features to the IR
function definitions.

Two output-equivalent causal probes attach
`"target-features"="+avx,+avx2"` before producing guest bitcode:

- `lto-partpin-avx2` changes only `layout::partPin`.
- `lto-guest-avx2` changes every guest definition.

Both restore vector record copies. These are diagnosis probes tied to the
benchmark host. The implementation recommendation is to preserve the selected
target's CPU and feature attributes in generated LLVM IR and in cache identity,
rather than enabling AVX2 unconditionally.

The final randomized 31-round comparison in the parent experiment's
`measurements.json` confirms the mechanism:

| Build | Median, ms |
|---|---:|
| ordinary O3 | 17.492 |
| full LTO | 34.470 |
| LTO guest + native runtime | 35.206 |
| native guest + LTO runtime | 16.182 |
| full LTO, all guest functions `noinline` | 36.259 |
| full LTO, AVX2 on `partPin` only | 17.367 |
| full LTO, AVX2 on all guest functions | 16.010 |

Putting only the guest through current LTO reproduces the regression; putting
only the runtime through LTO does not. Preventing inlining makes it slightly
worse. Restoring vector lowering only in the sampled `partPin` hotspot recovers
nearly the entire loss, while restoring the guest target features recovers all
of it and slightly exceeds the non-LTO baseline on this host.

Run `analyze.py` to reproduce section sizes, VEX instruction counts, and the
`partPin` lowering from retained binaries. Candidate binaries, SVG checks,
reports, disassemblies, captured link arguments, and hybrid build inputs are
under `.tmp/svg-slowdown-20260921/lto/`.
