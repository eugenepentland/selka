# Full SVG comparison against EDA NetLisp — 2026-09-21

The actual EDA NetLisp implementation renders the frozen LMX2595 circuit in
**2.54 ms**, compared with **17.57 ms for standalone mylang LLVM O3** and
**42.86 ms with the schematic tool's step/frame accounting retained**.
Those are respectively **6.92× and 16.87× NetLisp's elapsed time**. Mylang has
not reached NetLisp performance on this complete source-to-SVG workload.

This measures the existing implementations, including their different models,
algorithms, validation, allocation and output. It does not isolate language or
LLVM code generation. Both produce the same circuit connectivity; they do not
produce identical SVGs or identical placement for every pin.

| Implementation | Original circuit, ms | Changed net, ms | Changed value, ms | Original / NetLisp Fast |
|---|---:|---:|---:|---:|
| EDA NetLisp, Zig LLVM ReleaseFast | 2.540 | 2.498 | 2.521 | 1.00× |
| EDA NetLisp, Zig LLVM ReleaseSafe | 2.641 | 2.650 | 2.629 | 1.04× |
| mylang LLVM O3, standalone release | 17.567 | 17.815 | 17.545 | 6.92× |
| mylang LLVM O3 + full LTO, standalone release | 34.593 | 34.632 | 34.492 | 13.62× |
| mylang LLVM O3, step/frame accounting retained | 42.864 | 42.978 | 42.808 | 16.87× |

Every value is the median of 31 fresh-process runs after three warmups.
The original-circuit ratio's paired bootstrap 95% interval is 6.83–7.00× for
standalone O3 and 16.66–17.08× for the bounded configuration. All 465 timed
executions passed status, diagnostics and exact output-hash checks.

LTO makes the standalone mylang workload **1.97× slower** here. Retaining
step/frame accounting makes O3 **2.44× slower** than standalone release.
These measured differences identify useful follow-up work; this benchmark
does not establish the internal cause of either overhead. Even standalone
O3 remains substantially slower than NetLisp's ReleaseSafe build.

The timed interval starts before launching the prebuilt executable and ends
after it exits. It includes file reads, parsing, evaluation or model validation,
layout, routing, SVG serialization, output to a private file and shutdown.
Each process starts fresh, with warm filesystem caches and no persistent
evaluated-model cache. Compilation, Python preparation/verification, HTTP,
HTML page chrome, ERC/review reports, rasterization, browser rendering and
the outer mylang compiler/transport driver are excluded. This is the complete
measured source-to-per-hub-SVG pipeline for this one-hub fixture. It is not an
end-to-end web-page or editor latency measurement, and does not execute EDA's
full `renderToHtml` or connected-sheet page pipeline.

NetLisp uses unmodified production code at EDA revision
`2a8d901174255ff8fa3e4840acd35a041e39c9a8`. A
[thin harness](../../experiments/full-svg-benchmark/netlisp_bench.zig) calls
`modules.instantiateStandalone`, `render_html.setupRenderCtx`, and
`renderHubSvgForView(.functional)`, including pin-group gathering and file
output. It uses the process arena, as the one-shot EDA CLI does. The native
evaluator loads the traced real component definitions; the binary also contains
the production embedded-standard-library fallback. It does not use a
precomputed model or a newly ported renderer. This fixture has one hub, so the
production per-hub renderer produces one valid standalone SVG root.

Mylang runs `src/schematic/guest/main.my` with the normal
`src/schematic/native_schematic.c` provider. All three configurations retain
ordinary runtime checks, collecting GC, capability checks and the bounded
host-call/work interface. Standalone ReleaseFast omits step/frame accounting;
the bounded arm explicitly enables it and runs with 100,000,000 maximum steps,
matching the existing schematic host's accounting policy. This bounded arm
is the relevant comparison when those tool limits are required. The checked
per-byte host interface remains part of mylang's measured cost.

Zig is pinned to `0.17.0-dev.1683+5ceec001b`, explicitly using `-fllvm` with
`-OReleaseFast` or `-OReleaseSafe`. ReleaseSafe retains Zig safety checks;
ReleaseFast omits them. Mylang uses its LLVM backend with `--llvm-opt 3` and
ReleaseFast mode. No explicit CPU tuning flags were passed: Zig direct-build
host defaults and mylang's `amd64_sysv` target apply. This is not a claim of
identical LLVM flags or CPU feature selection. The machine is an Intel Core
i7-12700H, runs are pinned to logical CPU 6, and the existing `powersave`
governor was left unchanged. Cases and implementation order are randomized
with seed 20260921. Builds and correctness qualification finished before timing.

The original module, pinout and SPI interface are the same frozen files on
both sides, totaling 25,845 bytes. The two additional cases change every
`LMX_CE` to `LMX_CE_BENCH`, or change the single `390pF` value to `470pF`.
NetLisp also needs its real library definitions: an untimed system-call trace
confirmed eight distinct staged disk inputs totaling 50,759 bytes. The binary
also contains the embedded standard-library fallback; the filesystem trace
does not establish whether individual embedded entries were used. The pinout
was opened three times.
Staged part catalogs were not read by this rendering path. The
[read closure](../../experiments/full-svg-benchmark/read-closure.json) and
[fixture hashes](../../experiments/full-svg-benchmark/fixture-provenance.json)
record those differences explicitly.

Correctness qualification covers all five builds and all three cases:

- The independent source model, mylang SVG metadata and NetLisp's evaluated
  model agree on all 30 components, 95 connected pins and 34 nets. All nine
  port names and directions agree. NetLisp draws the expected 29 unique
  passive references and 37 connected IC pins; mylang additionally records
  four NC pins explicitly.
- SVG bytes match exactly across the three mylang configurations and across
  the two Zig configurations. Both engines reflect each source mutation.
  All three mylang GC-stress runs produce the same bytes as normal execution.
- Mylang's independent geometry oracle passes. Both SVGs are valid XML with
  one SVG root and `viewBox="0 0 884 1144"`. Across engines, 31 of 37 connected
  IC pin positions match; pins 7, 11, 15, 21, 26 and 37 sit 20 px lower in
  mylang. This difference is recorded, not treated as pixel equality.
- The original NetLisp SVG is 70,549 bytes, SHA-256
  `8a78de19c4c4121855904c2d5e4f0397d6ce24ab901e4f037a3735d671f7081f`;
  mylang is 49,617 bytes, SHA-256
  `68157ea785ee3766c039714d1d081ea1c7a55def6cf9124660495f8b797ed388`.

This is one supported 30-component circuit and two edits of it. It does not
measure scaling to larger circuits, other NetLisp language features, cold disk
I/O, malformed-input behavior parity or the whole web application.

| Implementation | Original-circuit median peak RSS, KiB |
|---|---:|
| NetLisp LLVM ReleaseFast | 3,888 |
| NetLisp LLVM ReleaseSafe | 3,616 |
| mylang O3 | 3,240 |
| mylang O3 + LTO | 3,236 |
| mylang O3 with step/frame accounting | 3,716 |

RSS is from five separate `/usr/bin/time -f %M` executions per case/build.
It includes process/runtime memory, is not a heap allocation count, and is
small enough here that startup and page granularity matter.

The [experiment directory](../../experiments/full-svg-benchmark/README.md)
contains reproduction commands, all individual timing samples, confidence
intervals, peak RSS samples, build reports, source and binary provenance,
qualification results, and representative SVG/model artifacts. View the
[NetLisp SVG](../../experiments/full-svg-benchmark/artifacts/fixture-netlisp-llvm-fast.svg)
and [mylang SVG](../../experiments/full-svg-benchmark/artifacts/fixture-mylang-o3.svg).

EDA's main checkout remains clean and its engine sources are unchanged.
The isolated worktree
`/home/epentland/ai/canopy/eda/.claude/worktrees/mylang-svg-benchmark-20260921`,
branch `codex/mylang-svg-benchmark-20260921`, remains unmerged and contains only
the untracked benchmark entry point. Direct harness compilation did not invoke
Guardian; no Guardian feedback entry was needed for this benchmark task.
