# Schematic LLVM O3 implementation

21 September 2026. Implements the measured build, host-boundary and application
improvements from the [audit](schematic-llvm-o3-parity-2026-09-21.md). Ordinary
runtime checks and collecting GC remain enabled. This work does not establish
end-to-end Zig parity: there is still no matched Zig implementation of the
complete layout and SVG workload.

## Use

After `zig build -Doptimize=ReleaseFast`, compile a guest with:

```sh
zig-out/bin/mylang build src/schematic/guest/main.my --project \
  --provider src/schematic/native_schematic.c \
  --backend llvm --llvm-opt 3 --step-accounting \
  --report -o /tmp/schematic-guest
```

The schematic host exposes the same selection:

```sh
zig-out/bin/schematic-svg --backend llvm --llvm-opt 3 \
  --project src/schematic/guest \
  experiments/schematic/fixtures/straps-synth-lmx2595.sexp \
  experiments/schematic/fixtures/lmx2595rhar.sexp \
  experiments/schematic/fixtures/spi.sexp > /tmp/schematic.svg
```

Use these flags before `--dev-session` to select the backend for prepared
generations. Embedded hosts use `App.initDiskWithOptions` and
`host_native.BuildOptions`; existing `initDisk` callers retain QBE defaults.
The adapter is installed under `lib/mylang-llvm`; `--llvm-adapter PATH` overrides
it. Python 3 and the pinned Zig toolchain are required for LLVM builds.
`ReleaseFast` selects LLVM O3 by default, and `Debug` selects O0.
Add `--lto` to enable full LTO. Keep it off for this fixture: after indexing,
the measured per-function O3 build is faster. LTO is an optimization choice,
not a guarantee of lower runtime.

## Changes

- Build receipts and cache identity include backend, optimization, LTO mode,
  adapter Python dependencies and the selected Zig toolchain. Known legacy
  `--qbe …/qbe_llvm.py` calls also include their environment optimization.
- Full LTO retains LLVM bitcode for guest functions, generated C metadata,
  entry code, the C provider and C runtime archive members until the final link.
  The Zig number-formatting runtime remains a native object when needed.
- Each execution caches validated host bindings. Small calls use eight stack
  nodes; larger values use checked heap storage. Registration, signature,
  authority, work/call budgets and returned-value validation remain enforced.
- The schematic resolves raw and displayed net identities once, caches rail
  and decoupling facts and indexes passive pins. Routing uses integer identities
  after geometry rejection. Source spans and iteration order preserve SVG
  metadata and placement ties.
- Byte ranges support `parse_int_range`, `parse_float_range` and
  `scalar_count_range`, avoiding temporary views in the S-expression port.
  Numeric parsing is allocation-free. Scalar-count errors can allocate their
  message, and its effect declaration reflects that.
- The LLVM adapter gives generated host boundaries their exact pointer ABI and
  marks only the proven heap-address getter as having no memory effects.

## Combined implementation evidence

The final batch ran after the task's builds stopped, with three warmups and
21 randomized, interleaved rounds pinned to CPU 6. All configurations retained
ordinary checks, collecting GC and step/frame accounting.

| Configuration | Median elapsed time | Reduction from baseline |
| --- | ---: | ---: |
| Retained original guest, per-function LLVM O3 | 85.89 ms | — |
| Implemented guest/runtime, per-function LLVM O3 | **45.51 ms** | **47.0%** |
| Implemented guest/runtime, full LLVM O3 LTO | 51.80 ms | 39.7% |

The O3 ratio is 0.530, with a paired-bootstrap 95% interval of 0.529–0.531.
These are warm-file-cache process timings, including launch, input read, SVG
generation to a private file and shutdown; compilation and the parent host's
validation/transport work are excluded. No matched full-schematic Zig benchmark
exists, so a 1.89× improvement over the old mylang build is not a Zig parity claim.
See [raw samples](../../experiments/schematic-parity-audit-20260921/combined-measurements.json)
and [qualification](../../experiments/schematic-parity-audit-20260921/combined-qualification.json).

Full LTO is genuinely active: every guest object and all 19 C runtime archive
members are LLVM bitcode, and the final link receives `-O3 -flto`. Its slower
result here appears to reflect optimization choices after the workload changed;
the exact cause has not been isolated. The original audit's whole-guest LTO
prototype measured a different application version and compilation arrangement.
Keep per-function O3 as the measured choice for this fixture.

## Application-only evidence

With the same retained compiler/runtime, per-function LLVM O3 and both step and
frame accounting, net normalization reduced the fixture's median from 84.77 ms
to 44.80 ms (47.2%). The runs used CPU 6, three warmups and 21 randomized,
interleaved rounds. This interval includes process launch, file input, rendering,
private-file output and shutdown, and excludes compilation.

The 49,617-byte SVG matches exactly. Differential cases also cover changed net
names, passive ordering, raw/display identity collisions, NC labels and empty-net
rejection. Independent geometry checks pass. See the retained
[measurements](../../experiments/schematic-parity-audit-20260921/implementation-measurements.json)
and [provenance limitations](../../experiments/schematic-parity-audit-20260921/implementation-README.md).

## Validation

- ReleaseFast build and all 88 whole-tree Guardian checks pass.
- Native build, host configuration, schematic and byte-I/O suites pass:
  62 + 2 + 13 + 11 tests, plus the C bridge harness. The bridge harness also
  passed AddressSanitizer and UndefinedBehaviorSanitizer.
- All 19 LLVM adapter tests pass. Cache tests cover O3/O2 switching, legacy
  environment flags, imported-module changes and a relocated compiler package.
- LLVM O3/LTO schematic acceptance covers all 34 fixture nets, 23 invalid-input
  mutations, independent geometry, rewiring and a rejected routing mutation.
  An LLVM O3 development session passes prepare, exact SVG, commit and quit.
- The combined binaries match SVG, status and diagnostics under ordinary and
  stressed GC, malformed input, changed nets, step exhaustion and frame exhaustion.
- Byte range tests pass on QBE and LLVM O3/LTO with GC stress; the ordinary
  S-expression suite passes all 114 tests. The separate stress limitation follows.

Commands and retained results are in
[integration qualification](../../experiments/schematic-parity-audit-20260921/integration-qualification.json),
[backend qualification](../../experiments/schematic-parity-audit-20260921/backend-qualification.md)
and [range qualification](../../experiments/schematic-parity-audit-20260921/implementation-range-qualification.md).

## Remaining work

Bulk byte transport, compact frozen collections, object-header redesign and
precise root liveness need separate implementation and measurements. This change
does not introduce unchecked layouts or assume that `noalloc` means no memory
reads or writes. Net normalization still uses bounded scans during setup; it
removes repeated text work in placement and routing rather than proving linear
scaling for arbitrary designs.

The broader S-expression port still has pre-existing printer/round-trip crashes
under GC stress: 20 failures with the range calls, versus 24 with the restored
transient-view calls on both the new and retained preimplementation compilers.
Ordinary execution passes all 114 tests. The complete schematic fixture passes
GC stress. The [controlled baseline](../../experiments/schematic-parity-audit-20260921/implementation-range-qualification.md)
records this separate unresolved defect; its root cause has not been isolated.
