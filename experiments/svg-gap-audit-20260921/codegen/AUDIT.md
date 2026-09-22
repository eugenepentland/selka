# SVG code-generation gap audit

## Accounting isolation

`accounting_matrix.py` emits the same checked guest four times and changes only
the existing step/frame emission switches. The `none` and `both` outputs are
byte-identical to the retained qualified `gc-lto` and `gc-lto-bounded` controls.
All four variants passed the fixture, changed-net, and changed-value SVG cases,
both normally and with `--gc-stress`. `accounting-census.json` records the IR
and final disassembly counts; no timing is performed by these scripts.

## Checked aggregate list reads

The managed-list read lowering in `src/qbe_managed.zig:115` already obtains the
receiver length. At `src/qbe_managed.zig:122` it uses the checked inline path
only for scalar elements; aggregate elements call `myl_native_list_get`, then
translate its false result through the same detailed bounds failure.

The existing helper at `src/qbe_managed.zig:445` is already shaped for a safe
aggregate specialization. It performs an unsigned `index < length` test and
calls `requireIndexBounds` before reading storage. For an aggregate it computes
the address with the statically known element layout, blits exactly that layout
size into the instruction's `%agg<pc>` scratch, and publishes the scratch
pointer as the stack value (`src/qbe_managed.zig:449-455`). Extending the caller
to select this path for suitable known-layout aggregates would preserve:

- The bounds contract and the existing normalized-index diagnostic, including
  negative indices represented as large unsigned values.
- Value-snapshot semantics. The result remains a copy in `%agg<pc>`, rather
  than a borrowed pointer into list storage, so a later list mutation cannot
  change the value already read.
- Managed-reference semantics. The copy remains shallow at the same native
  layout boundary as `myl_native_list_get`; traced fields in the copied record
  are subsequently rooted from the operand scratch by the existing root pass.
- Backing-storage lifetime. The receiver is live while the address and copy are
  formed, and no allocation or collection occurs between the bounds check and
  the blit. The published result points to frame scratch, not movable backing.

This should be implemented with focused ownership/rooting tests before a
production change. The audit closure contains 179 static `list_get` calls and
277 aggregate blits; 59 blits are 112 bytes. `circuit::normalize` and
`layout_graph::build` each contain 37 list-get calls, making this a concrete
code-generation priority.

## Constant-copy probe

`build_copy112.py` reproduces the private runtime probe from the frozen
unaccounted manifest. It verifies the exact old source fragment, inserts only:

```diff
+    case 112: memcpy(destination,source,112); return;
```

and rebuilds through the same frozen compiler, LLVM adapter, LTO mode, provider,
guest manifest, and link options. The change preserves `myl_native_list_get`'s
bounds check, false error return, descriptor-selected size, and copy behavior.
It is a specialization experiment, not check elision.

`copy112-provenance.json` records all 115 guest object hashes for both arms,
every runtime archive member hash, both runtime source trees, compiler and
manifest identities, and the exact source delta. The 115 guest objects are
byte-identical. The copied runtime trees have 46 files and differ only in
`native_collections.c`. Other LTO archive member bytes can differ because the
hermetic compiler embeds cache-directory prefix maps into bitcode; the JSON
records those hashes explicitly rather than claiming archive-member identity.
The qualified probe passed all three frozen SVG cases normally and under GC
stress, as recorded in `copy112-qualification.json`.

## Checked manifest-rewrite probe

`build_aggregate_inline.py` models the aggregate branch of `inlineIndexRead`
without rebuilding the compiler. It rewrites 178 of 179 list-get sites. Native
stack scratches provide their `alloc8` capacity directly. Heap-frame scratches
derive capacity from the next distinct frame-slot offset; the single tail slot
whose capacity cannot be bounded remains unchanged.

Scratch capacity alone does not prove logical element size because alignment can
add padding. The retained probe therefore loads `list->element->size` and takes
the direct path only when it equals the inferred capacity. A mismatch falls back
to the original `myl_native_list_get`. A match performs the unsigned bounds test
and copies from `list->storage + index*size` into the same `%agg<pc>` scratch.
The original `requireIndexBounds` branch consumes the status from either path.
This preserves padded layouts, bounds errors, value snapshots, and root-visible
scratch ownership. No pointer into list backing escapes the instruction.

An earlier unguarded capacity inference completed but produced a wrong fixture
SVG and was rejected. The guarded unaccounted and fully accounted LTO probes
pass all three frozen cases normally and with GC stress. Exact sites, inferred
capacities, hashes, and commands are in `aggregate-inline-builds.json`; results
are in `aggregate-inline-qualification.json`.

The 54,672-byte frame in `circuit::normalize` illustrates a separate future
lever: projection scratches, root slots, and value snapshots accumulate in one
large frame. The checked inline-read change removes an ABI/runtime barrier but
does not solve that frame and projection bookkeeping cost.
