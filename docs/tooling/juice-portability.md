# Juice portability design

The installed `selka juice` command contains the comparison, scenario validation
and calibration code in native Zig. Today capture supports Linux x86_64. This
page describes later work, once the compiler itself supports other targets; it
does not claim those capture adapters are implemented or validated.

## Keep measurement semantics separate from platform access

`src/core/juice/data.zig`, `report.zig`, `calibration.zig`, `manifest.zig`,
`toml.zig`, `normalize.zig` and `profiles.zig` hold contracts and data processing.
`platform.zig` handles processes, paths, timeouts, affinity and tool discovery;
`collectors.zig` implements Linux capture; `inventory.zig` currently inspects ELF
using binutils and identifies shared libraries with `ldd`. The engine composes
those services. A future port selects these host implementations at compile time
and keeps the JSON/report layer shared. Merely cross-compiling the command is
insufficient: each collector needs qualification on its actual host and CPU.

A future collector result should advertise:

- Counter semantics and ISA/CPU family, user/kernel scope, inherited-child scope,
  region support, missing events and whether values are counted or sampled.
- Tool/driver version, permissions and any multiplexing or dropped-trace evidence.
- Attribution availability and the relation between optimization, debug locations
  and emitted instruction counts.

An unavailable collector stays unavailable. A sampling estimate must have a
separate metric/schema and uncertainty model; it cannot silently replace an exact
instruction count. Doctor should probe these capabilities before recording.

## Candidate host adapters

| Host | Candidate collection path | Qualification needed |
|---|---|---|
| Linux x86_64 | Existing perf and Valgrind paths | Maintain full-running event checks and explicit hybrid PMU selection |
| Linux ARM64 | perf's ARM PMU support | Discover actual PMU/event mapping and validate complete counts, child scope and heterogenous cores |
| macOS / Apple silicon | Instruments CPU Counters and documented trace export | Establish automation, entitlements, counter scope and whether available exports support complete counts or only sampled evidence |
| Windows x64 / ARM64 | WPR/ETW hardware-counter recording | Enumerate supported counters, attribute switch-boundary data to the process tree, detect trace loss and validate count coverage |

Linux documents [ARM64 perf support](https://www.kernel.org/doc/html/latest/arch/arm64/perf.html).
Apple describes the [CPU Counters instrument](https://developer.apple.com/videos/play/wwdc2025/308/).
Microsoft documents [WPR/ETW PMU recording and enumeration](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/recording-pmu-events).
These establish possible integration points, not drop-in equivalents to today's
Linux full-workload counter contract. Prototype each adapter before promising
unprivileged, exact or fully unattended capture.

Host services also need Windows process-tree termination (for example, Job
Objects), macOS process control, platform-native affinity or an explicit absence
of pinning, executable suffixes, native cache paths and robust argument handling.
Replace ELF-only inventory with ELF/Mach-O/PE readers and record loaded-library
identities under the real execution environment. Source attribution needs DWARF
and PDB/CodeView adapters where applicable. Keep target architecture and host
architecture separate for cross-compilation; a cross-built guest must be captured
on the execution target, not scored from the build host.

## A portable fallback that remains honest

Add an optional LLVM instrumentation mode for optimized basic-block/edge counts,
plus existing selka semantic counters for allocations, copies and retain/release
work. Label the new measurements as their own work domain, not hardware retired
instructions. Instrumentation changes execution and may affect optimization; its
placement, thread-local aggregation and optimization correspondence need tests.
It should remain a separate executable checked against the ordinary build.

This would make short scenario feedback available without PMU access on supported
targets. It cannot predict contention, cache misses, I/O waits or scheduling just
from block counts. Preserve a vector of work metrics and cost warnings. Fit an
optional runtime model only to explicit, independent, held-out timing evidence.

## Compare changes within a target

Keep a separate baseline for each OS, architecture/ISA, CPU family, collector
contract and runtime/library context. Compare base and candidate on each target
and show a matrix of their relative changes. An ARM instruction and an x86
instruction represent different work; a single raw count must not rank platforms.
Likewise, never mix Valgrind, hardware and LLVM block-count ratios in one suite.
Semantic counters can be compared across targets only when their hook contracts
and application units agree; allocator-observed bytes remain platform dependent.

Runtime calibration remains local to the validated context and workload family.
The same change may improve one target and regress another. Report that instead
of averaging it away.

## Later implementation order

1. Add a collector capability schema and compile-time host interfaces, backed by
   the existing Linux qualification fixtures and report compatibility tests.
2. Add and qualify Linux ARM64. Preserve exact event identity and test heterogeneous
   core selection, missing permissions, child processes and short/large agreement.
3. Prototype macOS and Windows capture, including process-tree cleanup, library
   identity and attribution. Introduce sampled metrics only with explicit semantics.
4. Add the LLVM work-counter fallback and cross-target regression matrix. Run
   algorithm/copy/atomic/vectorization fixtures, same-machine load interference,
   correctness failures and unsupported-capability tests on every supported host.

None of these steps require a quiet machine for ordinary instruction/work
comparisons. Whole-job runtime claims still require validated representative
scenarios and an appropriate timing model.
