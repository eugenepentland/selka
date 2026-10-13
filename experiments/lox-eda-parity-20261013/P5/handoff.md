# P5 remaining EDA copies

Base: `2525a66f61838086f5327d74db7412926ce4a221`.

The candidate caches the target pin side and edge coordinate in `edge_spacing`
and reads candidate pins without copying their pad/name text. Empty units still
return `None`; duplicate edge positions and pins on other sides are still
ignored. A focused regression covers empty units, duplicate coordinates,
negative top-edge coordinates, and the separate bottom edge.

`route_parts` receives scoped borrowed obstacle arrays. Existing `route(Field)`
delegates to it, preserving the existing route candidate sequence, legality
checks, crossing/tee/overlap/body policy, and owned successful `Path` result.
`join_sites` uses this entry point without constructing an owned obstacle
snapshot and appends segments directly into their owner. The successful path
still enters retained storage through its existing explicit copy. `add_wire`
also appends segments directly.
`pad_of` reads integer shape/unit selectors without copying the parent Part;
the returned pad bytes remain an independent owner.

Dense text overlap remains unchanged, including strict ten-unit boundaries,
stable ties, first-pair selection, and report order. No compiler/runtime change,
arena, RC fallback, escaped borrowed view, historical evidence edit, peer merge,
push, or Guardian feedback entry is involved.

`identity.json` verifies the exact compiler and baseline executable against the
historical EDA build receipt. `source-manifest.json` pins candidate EDA module
bytes. `baseline-copy-calls.json` records direct static copy calls from the
pinned baseline LLVM, with its digest. It is not CPU attribution or timing.

Verified checked-release emit (8/8), wire (6/6), and corrected compose (2/2)
tests passed through shared build admission, with failed/skipped/unsupported
all zero. Exact commands use the pinned compiler,
`--release --verify-facts --experimental-zero-rc`, and private P5 caches.
Their raw output is in `emit-tests.log`, `compose-tests.log`, `wire-tests.log`.

The initial compose build rejected attempted `self.paths.append(path)` at
`kicad_sch_compose.my:578` with `E_SINGLE_OWNER_BORROW`: the narrowed optional
path is borrowed. The final source retains `path.copy()` and the failed raw log
is preserved as `compose-tests-path-borrow-rejected.log`. There is no compiler
workaround. The compose rerun enables `MYL_CORE_LEAKCHECK=1` and passed.
`test-commands.json` and `test-receipt.json` retain exact commands, statuses,
raw-log digests, source-manifest digest, and compiler identity.

The bounded CPU profile is diagnostic only. `profile.py` uses two existing full
inputs, twelve repetitions per cell, `cycles:u` at 499 Hz, and DWARF call stacks.
Each perf invocation is bounded at 23 seconds and each guest at three seconds.
The coordinator initially authorized an outer lease of at most 60 seconds after
P2 and pending builds. P2 cancelled its queued request before any profile ran;
the coordinator then consolidated baseline profiling. P5 never queued a timing
request and its runner has not run. Command JSON files pin input argv
and redirect output into this worker's private temporary tree.

All 34 goldens, full 60-case runtime qualification, 3x fresh Zig cutoffs, 120-second
absolute bounds, and counted integrated candidate receipts remain coordinator
work. No runtime/RSS or managed-memory improvement claim is made here.
