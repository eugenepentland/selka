# SVG algorithm gap probe

This directory records an isolated source experiment. It does not modify the
production guest. `build.py` builds an unchanged control and the probe with the
same frozen compiler, LLVM adapter, provider, optimization, LTO and memory
policy. `qualify.py` checks byte output and failure behavior; it does not time.

## Probe: indexed net facts

The production layout repeatedly resolves a normalized integer `display_id` by
linearly scanning `list[Net]` in `pinGroup` and `depth`. Those helpers sit below
`nearest`, `innerPin`, `bridge`, recursive `branch`, and `endpoint`, so the same
identity scan is repeated many times. The probe creates one dense
identity-to-net-index list in `layout.build` and threads it through those calls.
It deliberately leaves row ordering, row scans, append order, tie-breaking,
recursion, and mutations unchanged. The exact delta is in
`indexed-net-facts.patch`.

Qualification covers the three benchmark projects and seven edge variants,
including declaration/pin reorderings, raw/display identity collisions, an NC
only bridge collision, and the empty-net rejection path. LTO and bounded-LTO
control/probe binaries match byte-for-byte normally and under `--gc-stress`;
bounded binaries also retain step/frame budget rejection. See
`qualification.json` and `builds.json`.

## Remaining repeated source work

Measured priority should decide whether to pursue these after this probe:

1. `endpoint` invokes `innerPin`, `bridge`, `nearest`, `groundBranch`, and
   recursive `branch` per passive pin. Those helpers repeatedly scan all parts
   and rows. Per-part immutable layout facts and per-pin row ownership are the
   largest credible next algorithm intervention, but require more semantic
   care because source-order tie-breaking is observable.
2. Routing scans all pins for every non-NC pin to count a display net and find
   its nearest prior point. Rail bus construction then scans pins again, while
   blocked-lane search rescans pins for every attempted lane. Identity buckets
   can remove most unrelated-pin visits while preserving encounter order.
3. `layout_graph.build` linearly searches nets during edge construction and
   performs group merging by scanning every net. It then relaxes every edge for
   up to 128 passes. Dense identity lookup helps edge creation; a work queue can
   reduce relaxation, but exact owner tie behavior needs adversarial tests.
4. SVG rendering still scans all pins for each part and computes display
   reference ordinals from the prefix of the parts list. Existing `pin1`/`pin2`
   indexes cover passive geometry, while a kind counter can supply ordinals.
   This is lower priority because output formatting dominates this phase and
   the benchmark has few parts.

The Rust, Go and Zig ports retain nearly all of these same nested scans. Thus
they cannot by themselves attribute the language gap to algorithm choice.
Any residual gap after a source intervention should be separated from compiler
costs: mylang passes and returns multi-field records such as `Pin`, `Part`,
`Row`, `Point`, and `Span` by value throughout these hot helpers, while native
optimizers can scalarize or elide those projections. A source rewrite from
records to scalar/index arguments may improve mylang, but it measures compiler
record lowering as much as the schematic algorithm and should be reported as
such.

## Source comparison and recommendation readiness

The native ports are semantic translations rather than more efficient layout
algorithms. Production's linear identity lookups are at `layout.my:25-29` and
`:255-259`; Rust has the same scans at `ports/rust/main.rs:1287-1294` and
`:1568-1575`, Go at `ports/go/main.go:1136-1143` and `:1419-1426`, and Zig at
`ports/zig/main.zig:1018-1023` and `:1242-1247`. The repeated part/row traversal
under endpoint placement is production `layout.my:272-396`, Rust
`:1590-1762`, Go `:1441-1596`, and Zig `:1258-1388`. Routing's all-pin nearest
scan is production `layout_routes.my:61-101`, Rust `:1890-1970`, Go
`:1703-1777`, and Zig `:1498-1568`. All four implementations preserve source
encounter order and the same tie rules.

The meaningful native-only differences are representation/compiler effects:
Rust reserves output capacity (`ports/rust/main.rs:1777`), native fixed-size
count arrays are stack values (Rust `:1314-1316`), and native compilers can
inline and scalarize the by-value `Pin`/`Row` helpers. Mylang constructs its
130-element count arrays by appending (`layout.my:45-64`) and passes whole
records through the hot helper graph. These differences should not be labeled
schematic algorithm superiority.

Implementation decision is ready after matched timing. Promote the indexed-net
facts change only if it wins consistently against the same-compiler control;
it is byte/behavior qualified and narrowly removes real repeated work. If the
gain is negligible, do not add the threaded lookup parameter surface. The next
algorithm probe should cache immutable per-part layout facts and row ownership,
with source-order adversarial fixtures. A scalar-argument rewrite should be a
separate compiler-lowering probe because it primarily tests record
copy/projection elimination.

Matched measurements subsequently found indexed net facts improved ordinary
LTO by 4.5% and bounded LTO by 10.5%. Normalize early exit was 0.4% slower and
its confidence interval included 1, so it is not supported for production.

## Static follow-up from profiles

`circuit.normalize` (`circuit.my:254-301`) has three avoidable tail walks. Once
`raw_id` is found, `:266-269` still advances through every prior pin; once
`display_id` is found, `:278-281` and `:283-286` do likewise. The equality call
is guarded, but the loop/index work remains. `displayNet` also continues its
all-pin scan after both `trunk` and `named_host` are true (`:230-238`). Tightening
the loop conditions is a low-risk algorithm probe because first-match identity
and mutation order remain unchanged. Rust/Go/Zig translate the same full walks
(Rust `main.rs:626-674`), so this is shared source overhead rather than an
explanation of native parity by itself.

The profile attributed to `partPin` is not evidence that its fallback scan is
running on valid drawings. Validation requires every passive to have exactly
two pins before normalization; normalization populates `Part.pin1/pin2` at
`circuit.my:260-263`; and all hot layout callers pass passive parts and pin
numbers 1 or 2. Therefore `layout.my:233-234` should always return from the
indexed fast path, leaving `:235-240` unreachable for qualified inputs. Its
cost is repeated calls, bounds/ownership checks, and returning a ten-field
`Pin` by value. A direct-index/per-part-facts rewrite is credible, but it mixes
invariant specialization with compiler record copy/projection costs. Keep it
separate from the normalize early-exit algorithm probe and retain malformed
model rejection tests to substantiate the invariant.

## Non-LTO aggregate-copy count

`counts.py` relinks the original non-LTO `gc-o3` guest objects unchanged and
uses linker `--wrap` around `myl_native_list_get`. Each of the three qualified
SVG inputs reaches 288,066 intercepted calls requesting 22,899,360 copied
bytes. The 112-byte `Pin` descriptor accounts for 111,020 calls and 12,434,240
requested bytes: 38.54% of calls and 54.30% of bytes. All calls succeeded. The
full size histogram and hashes are in `list-get-counts.json`.

These are calls reaching the external list-get boundary from the original
non-LTO executable. They do not include list gets that an LTO build might
inline, and they do not establish the executed count of an LTO binary. Current
runtime sources do not call `myl_native_list_get` internally, but this wrapper
would also intercept runtime-internal calls if any were added. “Requested
bytes” is the sum of `list->element->size`; it describes full-record copy
requests at the ABI boundary, not measured memory traffic or hardware bytes.

## Zig ReleaseSafe comparator

`zig-safe-build.json` records an unchanged-source `ReleaseSafe -fllvm` build of
the direct Zig port and exact qualification on all three frozen inputs. It is a
valid checked application comparator, but not a pure estimate of bounds or
arithmetic-check overhead. The port assigns `std.process.Init.gpa` to its global
allocator (`ports/zig/main.zig:2061`), while this pinned Zig's `std.start`
selects `SafeAllocator(page_allocator)` for `.safe` mode and selects allocator
policy by build mode (`std/start.zig:744-770`). The retained stderr leak reports
confirm that the checked allocator is active. Any later Safe/Fast timing must
therefore attribute the difference jointly to checks, optimizer mode, and
allocator policy.
