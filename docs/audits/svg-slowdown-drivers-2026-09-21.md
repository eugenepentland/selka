# Full SVG slowdown drivers — 2026-09-21

**Repeated pin scans and record copying during placement are the largest
measured driver. Step/frame accounting magnifies that work. The LTO regression
is a separate target-feature propagation problem. Per-byte host marshaling
is measurable but smaller; garbage collection is not collecting on this input.**

The audit profiles the same full LMX2595 source-to-SVG workload used in the
[NetLisp comparison](full-svg-netlisp-benchmark-2026-09-21.md). Production
sources were left unchanged. All changes below are isolated diagnostic probes,
not implemented production fixes.

Fresh baseline medians are 17.492 ms for mylang O3, 34.470 ms for full LTO,
42.764 ms with step/frame accounting, and 2.510 ms for the actual NetLisp LLVM
ReleaseFast renderer. Each arm has 31 randomized rounds after three warmups,
pinned to CPU 6. All 403 timed runs checked exact expected SVG bytes, success,
and empty diagnostics. All mylang probe arms also passed the original circuit,
changed net, changed value, and fixture GC stress. The NetLisp and mylang
renderers still have the implementation and layout differences recorded in
the preceding comparison; these interventions isolate costs *within mylang*.

| Isolated change | Matched control | Probe | Elapsed reduction |
|---|---:|---:|---:|
| Use existing part-to-pin indexes, O3 | 17.492 ms | 8.997 ms | **48.6%** |
| Same index change, tool step/frame limits retained | 42.764 ms | 18.205 ms | **57.4%** |
| Restore vector target features only on LTO's hottest function | 34.470 ms | 17.367 ms | **49.6%** |
| Restore vector target features on all LTO guest functions | 34.470 ms | 16.010 ms | **53.6%** |
| Scalar host marshaling fast path, O3 | 17.510 ms | 15.910 ms | **9.1%** |

The interventions were measured separately. Their savings overlap and must
not be added together. The remaining 8.997 ms after the pin-index change is
still about 3.58× NetLisp; this audit does not establish parity.

The placement problem is concrete. In
[`layout.my:191`](../../src/schematic/guest/layout.my#L191), `partPin` linearly
searches up to 99 pins for a part/pin number, returning at the first match. Passive placement calls
it repeatedly through `innerPin`, `bridge`, `branch` and `endpoint`. Those
helpers repeatedly scan the 30 parts and reconstruct topology while placing
the 58 passive endpoints. Each tested pin is a **112-byte record**, accessed
through the checked list runtime and copied into guest temporaries.

The normalized model already stores `Part.pin1` and `Part.pin2`. The isolated
[index patch](../../experiments/svg-slowdown-20260921/algorithms/part-pin-index.diff)
uses those indices, validates the candidate's part/number and retains the
original search as fallback. It leaves placement order, routing, tie rules,
checks and GC intact. This small change nearly halves O3 runtime and saves
24.56 ms with the tool's accounting retained. The time ratio to baseline is
0.514 [paired-bootstrap 95% interval 0.511–0.517], or 0.426 [0.421–0.428]
for the bounded build.

A userspace PC sampler on the **unchanged original executables** corroborates
the intervention. `layout::partPin` accounts for 41.5% of O3 samples, 58.1%
of bounded-O3 samples and 73.3% of full-LTO samples. O3 additionally spends
19.9% of samples inside `memcpy`, 5.9% inside `myl_native_list_get`, and 9.1%
inside `layout::collectRows`. These are self-PC samples, not stack/caller
attribution: the memcpy percentage cannot all be assigned to `partPin`.

Step/frame accounting is the second major multiplier. The same workload
takes **2.445× as long** with it enabled: 42.764 versus 17.492 ms. The bounded
phase probe counts **58,242,305 logical steps**, of which **52,647,621 (90.4%)**
occur in placement. Those are compiler-accounted steps, not CPU instructions.
The experiment toggles step and frame accounting together, so it does not
separate their individual costs. The result supports reducing repeated work
first: the indexed probe retains those limits and still reaches 18.205 ms.
Removing the tool's limits is not required for that improvement.

The LTO regression has a distinct, reproducible code-generation cause. The
ordinary adapter emits native assembly per guest function; LTO emits bitcode
for later lowering. The bitcode path does not preserve the effective target
features used by the non-LTO native path. In `partPin`, fixed 112-byte copies
change from vector `vmovups` sequences to `rep movsq` with a count of 14. The
most frequent full-LTO sampled PC follows that short repeat-copy instruction.
This copying repeats inside the full-list scan.

| LTO isolation experiment | Median |
|---|---:|
| Original O3 | 17.492 ms |
| Original full LTO | 34.470 ms |
| LTO guest + ordinary native runtime | 35.206 ms |
| Ordinary native guest + LTO runtime | 16.182 ms |
| Full LTO, disable all guest inlining | 36.259 ms |
| Full LTO, AVX/AVX2 feature attributes on `partPin` only | 17.367 ms |
| Full LTO, AVX/AVX2 feature attributes on all guest functions | 16.010 ms |

Guest LTO reproduces the regression; runtime LTO does not. Disabling inlining
does not fix it. Restoring vector lowering in only the sampled hotspot recovers
almost the entire loss. This supports fixing target-feature propagation in
[`qbe_llvm.py`](../../experiments/llvm-backend/qbe_llvm.py), including target
selection in cache identity. The diagnostic AVX2 setting is valid on this
machine; a production fix must preserve the selected target's features rather
than force AVX2 for every machine. The actual executable code section grows
only about 1.7% under LTO; the larger `size` text total mainly reflects metadata
moving into read-only storage, not a doubling of executable code.

The scalar host boundary is the next measured compiler/runtime opportunity.
The current indexed workload makes **105,060 host calls**: 55,437 byte reads,
49,617 byte writes and six input/length calls. The earlier pre-index audit's
580,423 calls no longer describe this program. Each current scalar call still
passes through generic node sizing, argument serialization and result decoding.
The isolated scalar path retains binding initialization/validation, capability
checks, call/work budgets and charging, reentry protection, callback failure
handling and scalar result validation. It saves 1.60 ms, or 9.1%, relative to
its regenerated control. The control matches the original O3 baseline:
17.510 versus 17.492 ms, ratio 1.001 [0.997–1.005].

Bulk document access and bulk SVG writes could remove more calls, but that
larger API change was not measured. The current provider uses buffered stdio;
49,617 byte callbacks are **not** 49,617 write syscalls. The scalar probe has
output and GC qualification, not the complete adversarial host-boundary test
suite, so it is evidence for implementation work rather than a ready-to-merge
runtime change. In particular, the prototype assumes this provider's default
node budget; its fast path does not yet fall back for unusually restrictive
`max_values` settings. The measured saving applies to this fixed registry,
not a contract-complete general host implementation.

Low-frequency phase timers provide a second view of where work happens:

| Phase | O3 diagnostic CPU time | Bounded O3 diagnostic CPU time |
|---|---:|---:|
| Parse all three documents | 1.09 ms | 1.45 ms |
| Model construction and validation | 1.18 ms | 2.13 ms |
| Placement | **10.82 ms** | **32.14 ms** |
| Routing | 0.17 ms | 0.68 ms |
| SVG emission after placement/routing | 1.86 ms | 2.58 ms |
| Guest total | 15.13 ms | 39.01 ms |

These are diagnostic CPU times, not a decomposition of the original process
wall-time medians. Timers wrap only eight coarse calls and subtract nested
placement/routing from SVG rendering. They reuse unchanged guest/runtime
objects but require the system linker because the Zig link path rejected
`--wrap`. The relinked controls measure 16.09/41.18 ms versus original
17.45/42.59 ms in the phase batch; instrumentation measures 16.49/40.35 ms.
Thus linker/code-layout effects are visible, and phase percentages are
approximate. The unchanged-binary sampler and independent source intervention
establish the placement result without depending on those exact percentages.

Both O3 phase builds report **77 managed allocations, zero collections and
277,744 retained managed bytes** after rendering. Managed-list checks, record
copying and root bookkeeping still cost time; zero collections does not remove
those costs. However, rewriting the collector or allocation headers is not
supported as the first fix for this fixture. Routing is also a small measured
phase despite its nested loops, so it should not outrank placement based on
source appearance alone.

After the part-to-pin index probe, the remaining samples shift toward generic
host writes (22.2%) and `collectRows` (21.1%). `collectRows` walks pin numbers
1–128 and scans all pins, then repeats the number/pin scan for each newly
encountered group. Its base scan alone visits 128 × 99 = 12,672 candidates.
This gives a concrete next application target: construct ordered hub-pin/group
indexes once and precompute row heights and per-part branch facts. Preserve
number-major order, source order, and strict nearest-match tie rules. These
additional index changes were inspected, not priced by this audit.

Recommended implementation order:

1. Use the existing part-to-pin indexes throughout placement. This is the
   largest demonstrated improvement and retains the tool's limits.
2. Preserve the chosen target CPU/features through LLVM bitcode and LTO,
   with target-aware cache keys. Keep the existing non-LTO release default
   until that path is qualified.
3. Replace fixed-range row scans and repeated per-part topology calculations
   with stable ordered indexes and cached facts.
4. Specialize checked scalar host marshaling, then measure bulk input/output
   APIs. Consider projection/borrowing for large record reads after removing
   the unnecessary scans.

No combined speedup is claimed. Each production change needs exact SVG and
mutation qualification, GC stress, and the relevant boundary/budget checks;
the LTO change also needs target-selection and cache tests. Larger designs
remain necessary before generalizing beyond this supported circuit.

[Evidence and reproduction](../../experiments/svg-slowdown-20260921/README.md)
include all timings, paired intervals, phase traces, 1,000 sampled executions,
source patches, disassembly, hashes and build recipes. Hardware perf events
were unavailable (`perf_event_paranoid=4`); the sampler uses process CPU-time
signals and reports actual sample counts, not hardware cycles. It collected
2,986 O3, 6,393 LTO, 8,075 bounded, 1,258 indexed and 2,670 feature-restored
samples, retaining outside-executable and unmapped counts in the denominator.
No Guardian gate was exercised, and the audit made no production or EDA edits.
