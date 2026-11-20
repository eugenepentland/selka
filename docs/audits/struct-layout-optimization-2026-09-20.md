**Automatic record layout and representation optimization — implementation audit**

September 20, 2026. Decision recommendation, with source inspection, emitted-layout
measurements, optimized assembly inspection, and small native execution probes.
This audit adds documentation and evidence; it does not implement an optimization.

**Adopt the representation policy. Treat deterministic reordering as a bounded
compiler improvement, but prioritize eliminating unnecessary aggregate storage and
copies for current application performance. Defer automatic field pruning and
AoS/SoA selection.** The supplied proposal is sound in its separation of logical
types, materialized layouts, and temporary representations. Its implementation
sequence needs adjustment for the compiler that exists today.

The strongest new result is that descending-alignment reordering saves **zero
bytes** in the emitted tokenizer/AST and schematic populations inspected here.
It does save eight bytes in the proposal's mixed-width example. This establishes
a useful general capability, not a demonstrated performance fix for these apps.

| Proposal component | Recommendation for mylang | Reason |
| --- | --- | --- |
| Logical fields independent of byte order | Adopt explicitly | Compatible with existing field-index IR and value semantics |
| Deterministic aligned field reordering | Worth a small, tested follow-up | Existing shared layout machinery makes it practical; measured current-workload savings are zero |
| Layout inspection | Add with reordering | Expose existing facts and make the optimization auditable |
| Local scalar replacement and copy elimination | Higher performance priority | Fresh optimized assembly still stores unused local fields |
| Explicit C aggregate representation | Add with aggregate FFI | Current direct C imports accept scalars; internal aggregate ABI is not a C struct contract |
| Globally removing fields from stored records | Defer | Broad observers, tracing, boundaries, and cache dependencies need coordinated analysis |
| Explicit SoA collection | Profile a library/application prototype first | No collection benchmark in this audit supports adding a language feature |
| Automatic AoS/SoA/AoSoA or regional shapes | Defer | Disproportionate analysis and representation complexity for the evidence available |

**What already exists.** [README](../../README.md) documents QBE as the only runtime;
the interpreter was removed September 14. Bytecode remains an internal typed
operand-stack IR. The proposal's VM/native comparison stage should become a
comparison between reference and optimized native lowering, with the reference
path retaining all checks. A new VM or a wholesale SSA rewrite is not required
to implement record reordering.

[native_types.zig](../../src/native_types.zig) already contains a lazy `Catalog`
and `Layout` with size, alignment, field offsets, array count/stride, variant
payload offsets, copy/drop/tracing properties, and recursive content hashes.
Its current policy is source-order aligned layout (`build`, lines 184–194), with
checked addition/multiplication, zero-sized values, nested records, domains,
arrays, tagged variants, and managed-reference recursion. It explicitly targets
Linux AMD64; it does not inherit ordinary Zig struct layout. The working-tree
layout version is `mylang-native-amd64-layout-v2`.

The same catalog feeds:

- [QBE field access and storage](../../src/qbe.zig), including `field`, `layout`,
  width-specific loads/stores, and aggregate ABI types.
- [Record/array/variant lowering](../../src/qbe_aggregate.zig) and
  [managed collection lowering](../../src/qbe_managed.zig).
- [Complete and GC-only descriptors](../../src/native_descriptors.zig), consumed
  by [tracing and cleanup](../../src/native_heap.c) and
  [structural equality](../../src/native_equal.c).
- [Source-named rendering](../../src/native_render.zig),
  [copied-value boundary metadata](../../src/qbe_wire.zig), and the generated
  host/wire conversion adapters.
- Both [checked native-test facts](../../src/native_test_facts.zig) and
  [emitted native-test dependencies](../../src/native_test_dependencies.zig).
  These include layouts, managed bodies, and recursively referenced child types.

The typed instruction model already represents `get_field` by logical index and
`make_record` with an initializer-order mapping
([bytecode_model.zig](../../src/bytecode_model.zig), lines 36–38). Constructors,
field identity, and physical offsets do not need to be disentangled from scratch.

**Fresh size evidence.** The audit froze the installed compiler, emitted native
descriptors, and reconstructed their source-order sizes, offsets, array strides,
and variant payload offsets. All 158 descriptors across three manifests agreed
with the reconstruction. It then recursively modeled stable descending-alignment
field ordering, keeping scalar widths, pointer representations, and variant tag
rules unchanged. Of the 28 synthetic descriptors, only `Example` shrank; none of
the 49 tokenizer/AST or 81 schematic descriptors changed size. Descriptor counts
include builtins, managed references, and synthesized types, not just user records.

| Type | Current bytes | Projected bytes |
| --- | ---: | ---: |
| Synthetic `Example(u8, float, u8, u32)` | 24 | 16 |
| Separately declared reordered example | 16 | 16 |
| Parser `Span` | 24 | 24 |
| Parser `View` | 24 | 24 |
| Parser `RawToken` | 64 | 64 |
| Parser `Node` union | 72 | 72 |
| `Lexer` heap body, excluding object header | 32 | 32 |
| Schematic `Part` | 88 | 88 |
| Schematic `Pin` | 48 | 48 |
| Schematic `Segment` | 64 | 64 |

The parser uses many eight-byte integers/references and aggregates aligned to
eight. Its token enum's padding cannot disappear merely by moving it to the end:
array stride still needs tail alignment. The schematic's small Boolean fields
are already grouped at the end of relevant records. Reordering also does not
remove a union's tag or change its largest payload rule.

The separate reordered source declaration confirms that the existing compiler
can materialize the synthetic 16-byte shape. Automatic reordering itself was
**modeled, not implemented or runtime-tested**. These are storage measurements;
there is no wall-time, RSS, allocation-count, or end-to-end speedup claim. For
actual compactness work, narrower bounded position/index types and different tree
representations remain separate experiments. They should not be credited to
field reordering.

**The next useful optimizer work is smaller than whole-program specialization.**
Current [qbe.zig](../../src/qbe.zig) already has aggregate-by-address parameters,
private copies for written parameters, and immediate-consumer local-copy
avoidance. Existing syntax retains value semantics. Fresh probes agree:

- `first(value: Example) -> u8` emits zero `blit` instructions and its optimized
  assembly directly loads the byte from the parameter address.
- `p = Pair(used=value, unused=42); return p.used` emits one 16-byte `blit`.
  QBE removes the literal copy, but optimized assembly still reserves stack
  storage and executes stores for both `value` and unused `42`.
- An unused field initialized by `10 // value` retains its division checks;
  calling with zero produces `R_DIVISION_BY_ZERO`, with the helper and caller
  in the trace.

This is evidence for local scalar replacement/dead-storage work, not evidence
that every source-level `blit` survives or that copies dominate runtime. The
vendored [QBE promotion pass](../../vendor/qbe/mem.c) promotes suitable uniform
stack slots, and its other passes already eliminate some aggregate overhead.
Preserve logical fields longer or lower proven nonescaping plain records to
scalar locals so those passes have better input. Follow with destination
forwarding for constructors, returns, and result/match payloads where profiling
justifies it. The earlier
[application performance audit](language-performance-ergonomics-2026-09-20.md)
also identifies these targets; its wall times are not new measurements here.

Do not use `noalloc` or an empty authority-effect set as a deletion proof.
[effect_set.zig](../../src/effect_set.zig) describes authority, allocation, output,
and mutation, not a complete model of traps, divergence, or resource lifetime.
Mylang additionally exposes instruction/frame budgets and detailed trap traces.
Storage elimination must preserve the chosen accounting contract, or remain
disabled in modes where that contract cannot be preserved. Start with plain,
nonescaping records; avoid dropping managed references or owned resources until
their roots, cleanup, and lifetime behavior are covered.

**A safe first reordering change.** The critical implementation rule is to keep
`typed.Record.fields` **and `Layout.fields` indexed by logical declaration order**.
Sort a separate list of field indices to assign offsets, then write each offset
back into `Layout.fields[logical_index]`. Do not sort those field arrays in place.

This matters because `Emitter.field` indexes `Layout.fields[index]`, rendering
zips declared names with those indices, wire metadata is positional, and cleanup
walks descriptor field order. Constructors also evaluate supplied expressions in
source argument order; that order must not follow physical offsets. Nonmonotonic
offsets in a logically ordered descriptor are sufficient for the current design.
No persistent field-ID system is required just to make this change.

A bounded implementation should:

1. Record the source contract: ordinary `record` fields and `class` bodies have
   compiler-controlled target layout, with source order retained for positional
   constructors, initialization, schema, rendering, and existing cleanup rules.
   Stored layouts must depend on declarations and target policy, never whole-
   program field usage. Keep application code free of extra annotations.
2. Add stable descending-alignment placement inside `Catalog.build` for ordinary
   record bodies. Retain current array and variant rules, natural alignment,
   checked size arithmetic, and logical field indices. Managed body layouts use
   the same policy; their reference values remain one pointer. C runtime structs
   and runtime-owned collection header layouts are separate contracts.
3. Extend existing reporting to show canonical identity, size/alignment, logical
   fields with offsets, physical order, total padding, source-order baseline,
   tracing fields, and layout fingerprint. `emit-qbe` already exposes much of the
   underlying data, but it is an unnecessarily large inspection interface.
4. Advance the layout policy/ABI version and verify both native-object and test-
   receipt invalidation. Existing recursive hashes and compiler identities are a
   strong foundation; they do not replace regression coverage. A managed body
   can change while its reference remains eight bytes, so test that case too.
5. Validate constructors, positional/named arguments, nested updates, fixed
   arrays, lists, generic instances, calls/returns/callbacks, generated printing,
   host/JSON adapters, equality, GC stress, and owned-field cleanup. Cover empty
   and overflowing layouts, repeated deterministic emissions, and cached tests
   after a nested or managed layout change. Measure compiler overhead as well:
   `heapLayout` currently constructs a body on demand for field accesses, so a
   new sort should not become repeated avoidable work.

The implementation is bounded because centralization already exists; its
acceptance scope is broader than changing one loop. If performance time is
limited, do the policy/reporting and local aggregate work first, then reordering.

**Interop and collections need mylang-specific treatment.**
[Direct C imports](../c-ffi.md) already exist, but
[c_abi.zig](../../src/c_abi.zig) rejects aggregate and pointer signatures. Thus
external aggregate representation is future aggregate-FFI work, not a prerequisite
to preserving internal layout freedom. Existing copied structured host adapters
must keep working with generated offsets.

When aggregate FFI is added, layout ordering alone is insufficient. Current
internal aggregate QBE declarations use aligned byte aggregates, and copyable
parameters commonly cross internal calls as addresses. C ABI classification of
integer and floating members needs dedicated lowering; an `extern` marker cannot
simply reuse those internal calling rules. The
[QBE IL documentation](https://c9x.me/compile/doc/il.html) distinguishes ABI
aggregate descriptions from data definitions whose padding is supplied by the
frontend.

Mylang already distinguishes `record` value copies from `class` shared identity.
[Managed list indexing](../managed-memory.md) returns snapshots, with shared
managed references inside them, and exposes no interior pointer. That removes
one obstacle to an eventual explicit SoA value container: it can retain snapshot
reads without promising a contiguous element address. It still needs correct
indexed writes, column growth/permutation, tracing, and failure behavior. Benchmark
sequential field scans, random complete-record access, and mixed writes before
adding it. A list of class references is a different workload from inline values.

Whole-value equality, printing, JSON/codecs, callbacks, and copied host boundaries
already observe fields indirectly. Whole-population pruning therefore needs more
than a search for `.field`. Keep one complete materialized representation for
ordinary development builds. Automatic conversion between regional shapes also
cannot reconstruct values previously discarded.

Do not build heap migration or representation-version dispatch for this change.
The old [development-host page](../experiments/development-host.md) is explicitly
historical and did not preserve guest heap state. Live-object hot reload is a
separate runtime feature, not an existing obligation that blocks reordering.

**Verification and limits.** The
[retained evidence](../../experiments/struct-layout-audit-20260920/README.md)
contains sizes, projection code, probe sources, emitted/optimized function
excerpts, tool/source hashes, and execution results. Normal and GC-stress native
runs passed the small value-copy, list, field-access, and named-initializer-order
probe. The negative dead-initializer probe produced the required division trap.

The workspace already contained substantial concurrent changes. Source inspection
describes that working tree; executable observations use a frozen installed
compiler and are not claimed to come from an exact rebuild of it. Full parser
emission failed on an unresolved `byte_buffer` in the changing standard library;
the successful parser layout census instead imports the captured tokenizer/AST
closure. The schematic emission used live source. No complete compiler suite,
Guardian gate, reordering implementation, or collection benchmark ran.

The proposal's external precedents check out at the relevant scope: the
[Rust layout reference](https://doc.rust-lang.org/reference/type-layout.html)
allows ordinary field reordering, and
[LLVM's pass reference](https://llvm.org/docs/Passes.html) distinguishes scalar
replacement from interprocedural argument optimizations. These support the design
distinctions; the recommendation and priority here come from mylang's inspected
implementation and the bounded evidence above.
