# Schematic performance parity with Zig using LLVM O3

21 September 2026. **There is measurable overhead to remove before redesigning
the language. On the actual schematic SVG guest, isolated host-bridge changes
plus runtime LTO reduce measured runtime by 25.4%, from 91.53 to 68.32 ms. This
does not establish Zig parity: the existing matched Zig benchmark measures
S-expression parsing/pretty-printing, not schematic layout and SVG generation.**

This audit inspects the current dirty working tree at `b8f6ec3f` and executes the
installed compiler identified in the [evidence](../../experiments/schematic-parity-audit-20260921/README.md).
Only this report and diagnostic scripts/results were added. Production compiler,
runtime, guest and EDA source were not edited. The installed compiler was not
rebuilt from the working tree; source inspection and executable evidence are
identified separately. No Guardian gate was exercised.

**Fresh evidence from the schematic.** The three retained LMX2595 inputs total
25,845 bytes and produce 49,617 bytes of SVG. Each batch has 21 randomized,
interleaved rounds after three warmups, pinned to CPU 6 on the i7-12700H. The
interval covers process launch, input-file reading, parsing, validation, layout,
SVG-file output and shutdown. It excludes the parent schematic host's compilation,
input validation and transport-copy work. These are warm-file-cache process
measurements, not persistent-server latency or isolated layout-kernel timings.

The guest retains collecting GC, ordinary checks, step accounting and frame
accounting. All 115 frozen-manifest object keys were checked against the original
per-function O3 build. An initial whole-module probe had different frame
accounting; it was corrected and all reported batches rerun.

| First batch: one change at a time | Median ms | Time reduction from regenerated control |
| --- | ---: | ---: |
| Per-function LLVM O3, regenerated metadata control | 89.34 | — |
| Stack scratch for small host calls | 87.10 | 2.5% |
| Cache validated host bindings | 79.53 | 11.0% |
| Both bridge changes | 78.27 | 12.4% |
| Whole-guest LLVM O3 only | 88.34 | 1.1% |
| Whole-guest O3 and both bridge changes | 78.28 | 12.4% |

The original and relinked controls measured 89.65 and 89.91 ms, with their
comparison intervals including equality to the regenerated control. Generated
metadata objects have different hashes; the bridge comparisons therefore use
the same regenerated-metadata recipe rather than assuming binary identity.

| Second batch: runtime visibility | Median ms |
| --- | ---: |
| Per-function LLVM O3 control | 91.53 |
| Whole-guest O3, runtime rebuilt without LTO | 91.10 |
| Same with runtime LTO | 89.71 |
| Whole-guest O3, bridge changes, runtime rebuilt without LTO | 79.09 |
| Same with runtime LTO | **68.32** |

The combined result is **25.4% less elapsed time**, or 1.34× throughput if this
workload is the limiting operation. Its time ratio to the control is 0.746
(paired-bootstrap 95% interval approximately 0.731–0.756). LTO adds a **13.6%**
reduction after the bridge changes. With the original bridge, LTO's ratio to its
matched non-LTO control is 0.985 [0.973, 1.017]: no resolved improvement. Benefits
interact; they should not be added together or extrapolated to every design.

Both batches check complete SVG bytes, exit status, stdout, stderr and issue
bytes on every run. Separate checks cover independent wire geometry, a changed
net, four malformed/model inputs, GC stress, instruction-budget exhaustion and
frame-budget exhaustion. These are useful prototype checks, not the full
compiler/host qualification suite. Hardware counters were unavailable because
`perf_event_paranoid=4`; no fresh cycle/profile claims are made.

**Recommended work, in priority order.**

1. **Make backend configuration and cache identity reliable.**
   [`App.initDisk`](../../src/schematic/app.zig) passes no backend choice, so
   [`host_native.Request`](../../src/host_native.zig) selects QBE. Building the
   Zig host in ReleaseFast does not select guest LLVM O3. The experimental adapter
   selects O3 through `MYLANG_QBE_LLVM_OPT`; the native C helpers still use O2.
   Give the schematic host and build driver an explicit backend/optimization
   configuration and record it in the build receipt.

   There is a reproduced cache bug: changing only the adapter environment from
   `-O3` to `-O2` compiled **zero functions and reused all 115 O3 objects**.
   [`environmentJson`](../../src/qbe_build.zig) includes tool stamps, mode and
   target, but omits this environment value. The adapter's imported Python
   modules are also outside the entry-file stamp. Hash the optimization level,
   adapter dependency/version identity, resolved LLVM toolchain, target features
   and LTO mode into the relevant cache keys. Until then, use separate fresh
   caches. See [the reproduction](../../experiments/schematic-parity-audit-20260921/cache-recheck.json).

2. **Remove repeated host-bridge work, then introduce bulk byte operations.**
   [`qbe_host_invoke`](../../src/qbe_host_runtime.c) searches registrations and
   validates signatures on every call, even though initialization already
   validates them. It counts argument nodes, allocates a zeroed node buffer,
   copies arguments, invokes the callback, validates/copies the result and frees
   the buffer. [`io.byte` and `io.put`](../../src/schematic/guest/io.my) make this
   the interface for each byte. The provider's `fputc` is buffered stdio; this is
   not a claim of one syscall per byte.

   Cache the validated binding per declaration in execution-local state. Use
   bounded stack scratch for small scalar calls, with heap fallback for larger
   values. The 12.4% bridge result measures these changes without changing guest
   source or deleting checks. The prototype has seven binding slots because this
   guest has seven declarations; production needs storage sized for the registry.
   Preserve duplicate/missing registration checks, budgets, callback result
   validation and the no-retention/no-reentry contract.

   Next, provide a document byte buffer/view acquired once, and a bulk output
   operation for a byte range or buffer. Keep parsing, validation and drawing in
   mylang. Charge work by transferred bytes and retain document/output limits and
   publication only on success. This larger change is **not yet priced**.

3. **Normalize and index schematic data before layout.**
   Separate instrumentation counted **580,423 host calls**: 530,800 byte reads,
   49,617 writes and six input/length calls. The phase split is revealing:

   | Phase | Byte reads | Byte writes |
   | --- | ---: | ---: |
   | Parsing all three documents | 27,355 | 0 |
   | Model construction and validation | 11,750 | 0 |
   | `svg.render`, including layout and routing | **491,695** | **49,617** |

   About **92.6% of reads occur after model construction**. This is a call-count
   result, not a time profile. [`svg.render`](../../src/schematic/guest/svg.my)
   calls both placement and routing. [`layout_routes.build`](../../src/schematic/guest/layout_routes.my)
   scans pins inside the pin loop, repeatedly calls `displayNet`, and compares
   names through byte callbacks. [`displayNet`](../../src/schematic/guest/circuit.my)
   scans a net spelling and, for branch candidates, the pin list again.

   Compute display/electrical-net identity once per pin; intern names to compact
   IDs while retaining source spans for diagnostics and SVG metadata. Build
   net-to-pins and part-to-pins indexes, cache rail/ground/decoupling facts, and
   reject nonintersecting geometry before expensive net comparisons in `blocked`.
   Preserve branch-folding rules, nearest-pin tie order and wire geometry. LLVM
   cannot generally memoize these host-effectful calls or invent those indexes.
   This is the strongest application candidate from inspection; its speedup
   remains **unmeasured**. Larger valid designs should determine its priority
   relative to compiler changes.

4. **Optimize guest and runtime together for release builds.**
   The normal adapter emits one assembly unit per function. That ends LLVM's
   visibility before native linking; adding a linker flag after assembly cannot
   recover runtime IR. Add a bitcode build path for the LLVM guest, generated
   metadata, runtime C and provider, with ordinary native objects at stable FFI
   boundaries. The measured LTO result above justifies this after bridge cleanup.
   Whole-guest optimization by itself gave only about 1% here.

   Keep the incremental development path and measure release build/link cost
   separately. ThinLTO is a candidate for cross-module optimization with cached
   incremental work, but this audit measured **full LTO**, not ThinLTO. See the
   [LLVM LTO design](https://llvm.org/docs/LinkTimeOptimization.html) and
   [Clang ThinLTO documentation](https://clang.llvm.org/docs/ThinLTO.html).

5. **Reduce allocation volume for the larger parser/tree workload.**
   Current measured native sizes are a **96-byte allocation header**, **72-byte
   list/byte header**, and **32-byte GC root record**. A byte view avoids copying
   its payload but [`myl_native_bytes_view`](../../src/native_bytes.c) still
   allocates a view object. Lists allocate new backing and copy on growth;
   [`byte_builder.finish`](../../src/stdlib/byte_builder.my) deliberately copies
   into an immutable snapshot.

   Prioritize allocation-free range operations, a frozen sequence that stores
   `{owner/data, length}` with a correct lifetime contract, in-place arena growth
   where possible, and direct buffer writes/ownership transfer where permitted.
   Shrinking object headers is promising but requires a collector/layout design,
   not deleting header fields: allocation tracing, alignment, immortal literals,
   region ownership and resource cleanup all use that representation. Keep
   existing `finish` snapshot semantics and offer a separate transfer/write API.

   The SVG parser already uses one flat node list, so do not apply the historical
   recursive S-expression tree's per-form-list savings to it. Its emitted Node
   is 40 bytes and Span is 24 bytes. Narrowing validated document offsets/node
   indexes to `u32` is another candidate under the pilot's 1 MiB/16,384-node
   limits; no benefit from that change was measured here.

6. **Preserve pointer, effect and lifetime facts through LLVM lowering.**
   The QBE-facing representation uses `l` for both integers and addresses.
   [`llvm_emit.py`](../../experiments/llvm-backend/llvm_emit.py) recovers some
   pointer origins, but guest context/aggregate-address parameters and generated
   host declarations still arrive as integers in the inspected LLVM IR. Extend
   manifest signatures to retain pointer/scalar kinds, layout/alignment and
   proven effects. Use pointer operations and attributes only when their
   contracts hold; LLVM's [frontend guidance](https://llvm.org/docs/Frontend/PerformanceTips.html)
   specifically recommends preserving these facts and limiting pointer/integer
   conversion.

   The compiler **already** performs transitive no-collection analysis and
   safepoint root suppression in [`qbe.zig`](../../src/qbe.zig). Refine that work
   rather than proposing it anew: root only locals live across the call, and
   distinguish host effects/system allocation from the ability to trigger guest
   collection. Current root enumeration walks all traced locals; providers remain
   conservatively classified through unknown `_host` calls. A no-GC classification
   needs an explicit provider contract and stress tests, not a `noalloc` guess.

   Result-slot forwarding and typed list-element projection remain useful
   candidates. Some aggregate parameters, payload projections, constructor
   forwarding and list/buffer capacity fast paths already exist. Preserve value
   snapshot semantics when removing copies. These compiler recommendations are
   source findings; this audit does not assign them speculative percentages.

**What the existing Zig numbers establish.** The previous
[LLVM/Zig audit](llvm-zig-parity-2026-09-20.md) compares equivalent S-expression
census and pretty-printing workloads. Its header-retaining arena control measured
22.23/48.93 ms against Zig's 12.81/16.54 ms. Removing dead experimental root stores
and using complete width helpers reached 20.35/32.96 ms: **1.59×/1.99× Zig** in
that batch. These are retained historical measurements, not fresh SVG timings.

The [more aggressive composition](llvm-arena-parity-gap-2026-09-20.md) reports
1.25× census and 1.37× render in **total cycles**; its displayed task-clock values
are approximately 1.30× and 1.39×. It uses unchecked/noncollecting execution,
header removal, an ASCII-specific width substitute, a changed Result path and
fixture-sized output reservation. It also records a headerless-buffer header
access defect. Treat it as evidence locating overhead, not a qualified production
result or proof that only 25–37% remains. A headerless probe with output equality
does not establish memory safety.

**Acceptance for an actual parity claim.** Establish a matched Zig schematic
workload with the same supported input/model/geometry/output contract. Measure
parse, model build, placement, routing and output separately, plus end-to-end
execution; keep build/reload latency separate. Use small, medium and large valid
designs, equal target features and clearly stated safety/allocator policies.
Record medians, paired uncertainty, output equality, peak memory/allocation data
and warmed persistent-session results. A practical initial target could be
within 10% of Zig on representative designs, but that is a proposed acceptance
threshold, not an achieved result. The immediate sequence is cache/backend
correctness, the measured bridge changes, runtime LTO, then net indexing and
allocation-volume work with the same correctness oracles.
