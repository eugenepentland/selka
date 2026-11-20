# Next runtime steps: review of the second pass — 2026-09-20

Prioritize rendering after fixing a reproducible compatibility bug in the
compact-arena writer. Census already meets the 2× wall-time goal in the reported
configuration. This review changed no production source and ran no Guardian gate.

## Correct the baseline interpretation

The medians in `.tmp/bench/final2-{census,render,census8,render8}.json` give:

| Workload | Current / Zig | Further reduction to reach 2× |
|---|---:|---:|
| Small census | 1.455× | None; target met |
| Large census | 1.609× | None; target met |
| Small render | 2.385× | 16.1%, or 1.15 ms |
| Large render | 2.933× | 31.8%, or 17.13 ms |

The second-pass report's 27%/20% census entries are not remaining reductions:
they describe being below the threshold relative to the target's time budget.

The report's instruction/cycle table implies mylang IPC of approximately
2.54–2.65 and Zig IPC of 3.18–3.73. Its 1.41–2.85 values are cycle ratios, not
mylang IPC. For large render, 2.19× as many instructions and a 1.30× IPC penalty
combine into the 2.85× cycle ratio. Excess instruction work remains material.
Low IPC does not distinguish memory stalls, dependency chains, branch recovery,
or front-end limitations. Memory-bound remains a hypothesis.

The report names `.tmp/bench/final-counters.json` as table evidence, but that
file currently contains different counts (e.g. 189.28 M/415.25 M for the new
large census/render, versus 178.67 M/405.39 M in the report). Preserve the exact
final counter runs, executable hashes, commands and unsorted per-round samples
before treating those table values as a reproducible matched data set. The
wall harness's saved samples are sorted, so their original round pairing is lost.

## First: fix the compact writer's header access

`src/native_bytes.c:224` implements `buffer_frozen` by reading
`((const myl_native_object *)buffer - 1)->immortal`. The compact arena explicitly
does not allocate that header. The final2 executable confirms a read from
`buffer - 52` in `myl_native_bytes_buffer_append_range`.

I reproduced a valid-input failure using the runtime sources captured inside
the final2 build:

1. Initialize the arena.
2. Allocate 64 ordinary bytes and fill them with `0xa5`.
3. Allocate a fresh empty byte buffer.
4. Append the valid byte `x`.

| Arena | Append result | Buffer length |
|---|---:|---:|
| Compact, without object headers | 2 (`MYL_BYTES_REFUSED`) | 0 |
| Original object headers retained | 1 (`MYL_BYTES_WROTE`) | 1 |

The guard reads preceding payload data as an immortal flag. This can silently
drop fragments because several builder wrappers discard the refusal boolean.
The same final2 safe and compact binaries **do** produce identical render bytes
for both benchmark inputs (700,425 and 5,603,400 bytes). Those examples therefore
do not expose the layout-dependent failure; this finding does not claim their
observed output was wrong.

Fix the storage-kind query so it is valid for every allocator configuration.
Keep immutable literal rejection in the checked runtime. A compact-mode policy
must be explicit about its valid receivers and must not read nonexistent object
headers. A distinct mutable buffer representation is the cleaner long-term
boundary than treating ordinary `bytes` as both immutable source and mutable
writer state.

Reproduction source, captured commands/output and source hashes are under
`.tmp/headroom-review-20260920/`: `header_probe.c`, `header-probe.json`, and
`source-hashes.json`. Both probes compile the final2 runtime source snapshot;
only `MYL_MAXPERF_ARENA_COMPACT` differs. Add this allocation-order case to the
arena/writer gate, then requalify and freeze the corrected executable.

## Next performance experiments

### 1. Make appends with spare capacity avoid the growth machinery

`buffer_grow_rooted` pushes roots before `buffer_grow` checks whether capacity
already suffices. Disassembly of the final compact executable confirms calls to
`myl_native_root_push` survive even though that mode's root functions are no-ops.
Root pops survive as well. Ordinary appends should test available capacity first,
and enter rooting/allocation only when growth is necessary. Preserve all range,
overflow, aliasing, and growth-GC behavior. This is a general runtime improvement,
not a guest-only change.

Then compare specialized byte/repeat appends and batching of punctuation with
the existing range path. Avoid replacing many tiny fragments with freshly
allocated fragment lists. Measure call counts and bytes copied in diagnostic
builds, wall time in uninstrumented builds.

### 2. Remove width-only text allocations

The source-backed AST has not removed all leaf decoding. In printer.my,
`estimate_width` calls `len(text_of(view))` for atoms and strings; `literal_width`
also decodes. `text_of` invokes `.decode()`, allocating a scalar string.
`view.matches` similarly decodes the viewed source, contrary to its comment,
and `view.equal` copies both ranges before comparison.

Provide nonallocating UTF-8 scalar counting over a byte range, with an ASCII
fast path and explicit invalid-input behavior. Use it for layout widths, and
cache bounded widths only where repeated traversal justifies the metadata.
Do not substitute byte length for Unicode scalar width. Range comparison is
another reusable primitive, though its hotness in this benchmark is unproven.
Numeric width/float emission still create temporary strings and should be
measured separately.

### 3. Isolate output copying before adopting a streaming redesign

The CLI needs synchronous output, while `byte_builder.finish` deliberately
copies to preserve immutable snapshots. A `write_to(Stream)` operation could
write the live buffer without creating that snapshot and without weakening
`finish` semantics. Measure this change separately. Compare pre-reservation
against growth copies using a general sizing policy, not a fixture-specific
constant.

If growth/retained storage remains significant, compare a bounded output buffer
with bulk flushes. Account for `Stream.write` flushing on every call; per-token
writes would introduce a different overhead. Removing one 5.6 MB copy alone is
not evidence that the required 17.13 ms reduction will follow.

### 4. Leave the scanner as a subsequent improvement

An offset-taking byte search and multi-delimiter scan can help the tokenizer,
but census is already within the goal. A native `find_any(values, start)` is a
language/library/runtime addition, not purely a guest change. Design it to
preserve escape parity, newlines and byte locations; a one-pass multi-byte
search should be compared with multiple memchr scans rather than assuming they
have identical cost.

## Measurement for the next pass

After fixing the allocator issue, freeze one corrected baseline and compare
each change separately. Use paired randomized wall rounds with fail-fast
exit/output verification, raw sample order, hashes and confidence intervals.
Retain census as a regression check and make large render the primary target.

Collect processor-supported top-down metrics to distinguish memory-bound from
core-bound/front-end/speculation limits, then inspect cache/TLB misses and
bandwidth as appropriate. Output size or bytes per retired instruction is not
itself a measurement of memory traffic. Intel's
[top-down analysis guidance](https://www.intel.com/content/www/us/en/docs/vtune-profiler/cookbook/2024-0/top-down-microarchitecture-analysis-method.html)
describes this distinction. Re-run checked GC/QBE configurations after the
compact experiment; success in that experiment alone is not a production-wide
2× result.
