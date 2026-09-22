# Remaining full SVG performance gap

The [audit report](../../docs/audits/svg-remaining-gap-2026-09-21.md) gives the
ranked implementation plan and distinguishes measured prototypes from
production-ready changes. The combined diagnostic saves 28.3% of ordinary
LTO elapsed time but remains 2.55 times the direct Zig port on the original
circuit; it does not establish parity.

This audit investigates the optimized mylang GC/arena implementations against
the Rust, Go and direct Zig ports. All work is isolated in this directory and
`.tmp/svg-gap-audit-20260921`; no production compiler, runtime, guest or EDA
source is changed. Diagnostic shortcuts are not production fixes.

The starting executables are the qualified binaries from
`experiments/svg-arenas-20260921/native-qualification.json`. The installed
compiler changed after that benchmark, so the audit freezes a private compiler
and rebuilds matched controls. The rebuilt unbounded and bounded LTO controls
are **byte-identical** to the retained executables. `arms.json` records and
deduplicates these equivalent controls.

## Evidence

| File or directory | Purpose |
|---|---|
| `provenance.json` | Frozen compiler, baseline binaries, source verification and perf restriction |
| `sampling.json`, `samples-*.txt.gz` | 4,800 profiled runs of four unchanged binaries, actual PC counts and raw samples |
| `phase-builds.json`, `phase-*-wrappers.c`, `phases.json` | Coarse CPU phases with unchanged non-LTO guest/runtime objects and relink calibration |
| `phase-counts.json` | Allocation, collection and logical-step counts; no timing inference |
| `arms.json`, `measurements.json` | 17 configurations, three cases, 31 interleaved measured rounds; every output checked |
| `headroom-arms.json`, `headroom-measurements.json` | 15 configurations, three cases, 31 rounds; aggregate read, typed host, combined and frame probes |
| `sampling-combined.json` | Another 1,200 profiled runs of the combined diagnostic; no wall-time claims |
| `frame_ceiling.py`, `frame-ceiling-builds.json` | Isolated oversized-frame experiment; no speedup and not safe for production stack accounting |
| `qualify_extended.py`, `extended-qualification.json` | Eight later probes across ten inputs, normal and GC stress, plus budget rejection |
| `measurement-environment.json` | Hardware, OS and observed background load |
| `artifact-validation.json` | Final binary-hash, median/ratio, sample-count, Python-syntax and report-link checks |
| `host/` | Per-declaration call counts, provider-only probes and a typed host ABI ceiling |
| `algorithm/` | Net-lookup index and normalization early-exit source probes, mutations and qualification |
| `codegen/` | Separate step/frame accounting, generated-code census and checked record-copy experiments |

## Method and limitations

`audit.py` times fresh processes pinned to CPU 6, including process launch,
input reads, parsing, model construction, placement, routing, SVG file writes,
and shutdown. Compilation, fixture preparation and verification are excluded.
The seed is 20260923 (an arbitrary seed, not a date). Each batch has three
warmup rounds and 31 measured rounds. Configurations and cases are shuffled
together. Every invocation checks return status, stdout, stderr, issue output
and the expected complete SVG hash. Mylang uses an explicit 256 MiB managed
memory budget. Go uses its default runtime policy; related environment
overrides are cleared. GC stress is qualification only.

The reference ports and mylang produce identical SVG bytes for these three
cases. This compares implementations, including their host I/O boundaries,
memory policies and checks. It is not an isolated comparison of LLVM code
generation or evidence for all schematic sizes. The three cases are one real
circuit and two mutations of it. Absolute timings from separate runs should
not be subtracted; intervention ratios use matched controls in the same batch.
Reported bootstrap intervals describe variation within this machine/batch.
The two main intervention batches contain 2,976 timed executions in total.
The separate Zig ReleaseSafe build is byte-qualified but not timed: its allocator
policy and exit diagnostics change as well as its checking policy. See
`algorithm/zig-safe-build.json`.

Hardware and software perf events are unavailable (`perf_event_paranoid=4`).
The userspace sampler from the earlier audit requests a 500 microsecond CPU
timer and records actual sample counts, including outside-executable and
unmapped samples in the denominator. It reports self-PC attribution, not
call stacks, cycles or wall-time fractions. `LD_PRELOAD` is applied after
`taskset` using `env`, so its timer starts only inside the target executable.
The initial attempt that preloaded `taskset` could inherit a pending SIGPROF
across exec and was discarded; the retained complete run uses the corrected
launch. Profiling may coexist with unrelated builds because no profiled
wall-time results are used. Performance batches begin after audit builds finish;
unrelated background activity is not controlled or stopped.

The phase experiment uses the system linker and therefore includes paired
relinked controls. Instrumented CPU times are diagnostic: they are not an exact
decomposition of LTO process wall time. Linker/code-layout differences are
visible in `median_wall_ms` and must not be silently attributed to phases.

## Reproduction

First retain or rebuild the exact binary/source snapshots recorded in the
provenance files. The probe subdirectories document their build and qualification
commands. Keep builds separate from timed runs; audit invocations share output
paths and must run sequentially.

```sh
python3 -B experiments/svg-gap-audit-20260921/audit.py sample --count 1200
python3 -B experiments/svg-gap-audit-20260921/phases.py build
python3 -B experiments/svg-gap-audit-20260921/phases.py measure
python3 -B experiments/svg-gap-audit-20260921/audit.py measure
python3 -B experiments/svg-gap-audit-20260921/audit.py measure --manifest experiments/svg-gap-audit-20260921/headroom-arms.json
python3 -B experiments/svg-gap-audit-20260921/audit.py sample --count 1200 --combined
python3 -B experiments/svg-gap-audit-20260921/qualify_extended.py
```

No Guardian gate was exercised by this audit. Unrelated Guardian processes in
the shared workspace were observed but were not launched, modified or stopped.
