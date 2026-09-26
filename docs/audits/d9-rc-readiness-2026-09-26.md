# D9 production RC readiness — 2026-09-26

This is a read-only implementation inventory and proposed work split. No WP-4
code is introduced. Start implementation only after WP-3f and WP-4pre have
their required acceptance and are on `main`, as the
[closeout plan](d9-closeout-plan-2026-09-26.md) requires. Stage 3's joined
performance acceptance is still a separate gate; this assessment does not
declare it complete.

The production compiler now provides substantially better ownership facts than
E2b, but E2b cannot be imported as a complete runtime. Its refused operations
include supported D9 programs, its count representation conflicts with current
headers, and it predates nested receiver scopes. Arenas and the one-release
legacy-sharing compatibility lane must remain supported.

## Inspection baseline

| Component | Inspected revision and evidence |
|---|---|
| E2b prototype | `exp/e2b-rc-runtime`, `21a2a4a1`; implementation `f04770e1`, corrections `edf5ca8c`, `experiments/value-semantics-20260924/e2b/summary.md` on that branch |
| Joined D9 compiler | `91d1311e`; indexed transfer proof plus scoped receivers, pure box reads, current COW and ownership passes |
| Combined validation | [60 guest probes per backend and 44 legacy IL comparisons](d9-indexed-scope-review-2026-09-26.md), frozen Debug compiler SHA-256 `d733b14aca8b25b0d4fb2d1becda50c98c2ab0f8cfac342e22a204bc58c9d82c` |
| Physical borrow prerequisite | `450d151a` on `d9/stage4pre`, including `363231da`; `docs/audits/d9-stage4pre-borrow-closeout-2026-09-26.md` on that branch |
| Default/compatibility contract | `codex-d9-stage3f-prep/src/main_value_semantics.zig` and its default-validation report; value default with one-release `--legacy-sharing` |

E2b measured 26 LLVM parity programs and three QBE schematic inputs. Its parity
instruction geomean was 0.989; schematic was 1.289. No measured program made a
COW copy, and 48 of 108 `tests/lang` programs were refused. Its mixed-backend
total is not production evidence for WP-4. Reuse the lessons, action vocabulary
and runtime algorithms after review, rather than the old coverage claim.

## Contracts to settle before parallel implementation

1. **Runtime selection.** Until RC acceptance, value-default programs use the
   accepted stage-3 GC runtime. After acceptance, value-default programs select
   RC; `--legacy-sharing` and other resolved legacy-mode entry points continue
   selecting tracing GC for the authorized compatibility release. Their
   `class`/`Cell` graphs can cycle. Do not run them on acyclic RC or introduce a
   cycle collector to make the modes appear interchangeable. Resolve the mode
   once per artifact/heap and propagate it to child compilers, providers and
   caches. Reject incompatible linked guest artifacts; do not permit implicit
   pointers between GC and RC heaps. Shared immutable literals need an explicit
   immortal representation accepted by each runtime.
2. **Object/header ABI.** Current `native_heap.h` uses a 16-byte header whose
   mark word contains element count, arena depth and GC/COW flags. E2b uses a
   32-byte header with a separate element count and an RC count in the old mark
   position. Reinterpreting the current mark word as a count is invalid. Choose
   and document the heap/arena/literal layouts, count limits and mode accessors
   before changing allocators or emitted header loads. A compact 16-byte RC
   header is an optimization to evaluate, not a substitute for this contract.
3. **Physical ownership and ABI.** Define an operation table for borrowed,
   owned, moved, immortal, arena-resident and freshly constructed results.
   Include inline aggregates, physical boxes, list storage, dictionary metadata,
   text views and shared byte backing blocks. Decide whether runtime producers
   return owned values or E2b's floating values; every producer, failure path
   and consumer must follow the same rule. Document direct, indirect, host and
   C-ABI call results and `mut` parameter replacement.
4. **Keepalive holds versus snapshots.** A pending receiver needs its original
   backing and ancestors kept alive across a callback. A lifetime hold does not
   itself create an independent value snapshot. E2b's `count > 1` uniqueness
   test cannot blindly include such holds: that could detach a pinned receiver
   and break its identity. Specify how holds, real sharing, nested pins and
   restoration interact, including partially prepared scopes and error exits.
5. **Region and cleanup ownership.** Heap references stored inside an arena
   need counted ownership while that arena is open, and releases when their
   slots are replaced or the arena closes. Preserve the older/younger-region
   barrier and bulk allocation. Define exception/failure cleanup and resource
   destruction separately from shared-value count changes.

The runtime selection permits removal of GC machinery from RC artifacts after
validation. It does not permit deleting the compatibility collector while
`--legacy-sharing` remains supported. Native trace frames, runtime error checks
and resource cleanup are independent of GC roots and must remain.

### Proposed receiver and representation contract

Track ordinary owner references and non-sharing lifetime holds separately.
Destroy a heap payload only when both reach zero; uniqueness considers owners,
not holds. A pending receiver can therefore remain alive with zero ordinary
owners after a callback replaces its parent. Before lending it, detach the
selected path under the normal snapshot rules, acquire holds for the exact
backings/ancestors and set pins. A subsequent snapshot transfer copies the
finite pinned path, preserving the original receiver. Child boxes outside that
path stay opaque; do not recursively duplicate the entire reachable graph.
Each nested scope restores its previous pin state and releases only its own
holds. Restore pins before releasing the last hold, since that release may
destroy the object. A scope link must itself have explicit ownership rather
than relying on its former GC descriptor to keep the chain alive.

A concrete initial layout to evaluate is a 32-byte RC allocation header: two
words for owners/holds immediately before the existing 16-byte common header.
This leaves mark and descriptor at payload minus 16 and minus 8, and places the
new words at minus 32 and minus 24. Preserve the existing GC, arena and literal
headers initially; test immortal/arena flags before accessing an RC prefix.
Allocator size-class/large-block bookkeeping then needs separate metadata or
an explicit additional layout decision. All RC allocation/extension/free paths
must agree, with alignment/offset assertions. Runtime-specific COW fast paths
must use the agreed owner/hold rules rather than continuing to interpret sticky
GC SHARED flags as a reference count. Measure the header cost before attempting
compaction; do not silently change common ABI offsets or Guardian limits.

An arena hold does not extend a chunk's lifetime. Its safety comes from region
dominance: any scope targeting a region being closed must restore/release its
pins before that region's teardown. A callback may open and close younger
arenas while holding an older receiver. Older heap payloads retained by arena
edges still use normal RC ownership. Verify cleanup ordering on every unwind;
do not postpone bulk release indefinitely because an internal pin survived.

## Compiler integration

Use current `ownership*.zig`, `qbe_liveness.zig`, `cow_plan*.zig` and
`qbe_cow.zig` as the analysis foundation. In `qbe.zig::planOwnership`, implicit
parent/key uses extend liveness and ownership/COW planning repeats to stability
before moves and roots are planned. RC actions must consume that final solution
and preserve this ordering. E2b's duplicate `qbe_rc_classify`, `qbe_rc_flow` and
`qbe_rc_state` analyses predate these facts and should not become a competing
source of lifetime truth.

The useful E2b lowering model attaches actions before/after instructions and to
control-flow edges: retain borrowed values that become owned, move last uses,
release overwritten/dead owners, adopt runtime results, and clean up switch
arms and error edges. Rebuild that model against current source provenance and
storage decisions. Cover early return, `try_result`, trap unwinding, loop exits,
mut-parameter rebinding, large-result storage and heap-backed guest frames.
Aliases whose aggregate storage was forwarded or whose initialization was
elided must not acquire a second destructor merely because two local numbers
name the same address. Conversely, two physical owning slots require two
counts even if their source values are equal.

`value_semantics.needsCopy` answers whether mutable value sharing needs COW.
It does not answer whether a value owns RC-managed storage. Immutable `bytes`,
text and collection-free recursive boxes still need lifetime accounting.
Likewise `value_copy.elided`, pure-box unbox elision, field-return elision and
the indexed-return proof do not automatically authorize skipping a retain or
release. Each needs a physical borrow/move/ownership justification. Preserve
their negative tests, especially earlier match bindings whose owned role does
not fully describe the physical borrow provenance.

WP-4pre distinguishes logical `return_origin` from physical `borrow_origin`.
Its schematic ledger changes 72 call-site transfer decisions toward borrowing,
but COW sites remain 40, with three real copies. That is static prerequisite
evidence, not measured RC savings. Production must make the caller/callee
ownership ABI agree: classifying a caller result as borrowed while the callee
always returns an extra retained owner would leak it. A fresh inline record can
contain borrowed heap fields; the fact must describe those physical lifetimes.
Unknown indirect/foreign calls need an explicit conservative owned result
contract, with stabilization at escapes or mutation.

Keep COW hoisting and loop-versioning compatibility. E2b without hoisting was
1.268 on parity and 60.8 on `matmul`; an otherwise correct per-element count or
uniqueness check can prevent vectorization. Reuse current proofs and vetoes
rather than importing E2b's older loop analysis unchanged. Expose RC actions
and borrow origins through explanation output and optional counters so the
schematic prerequisite can be checked dynamically.

Mode, header ABI and physical return contracts must participate in all affected
semantic/native-function hashes, emitted fragments, embedded runtime/object
keys, executable/test caches and provider artifacts. WP-4pre already adds
borrow facts to several keys; E2b's older `rc_runtime.keyByte` wiring is not an
inventory of today's cache layers. Test cold and warm builds, mode changes,
callee-origin edits, generic specialization and incompatible artifact reuse.

## Runtime and boundary inventory

| Area | Current/prototype location | Required production work |
|---|---|---|
| Heap and allocator | `native_heap.[ch]`; E2b `native_rc.[ch]` | Put RC state in the owning heap/context rather than E2b's process-global `rc`/`myl_rc_active`; preserve heap budgets, alignment, allocation failure and lifecycle. Audit allocator reuse and dictionary probe-cache invalidation; E2b increments `heap->collections` on frees, which needs a deliberate reuse-epoch contract. |
| Retain/release traversal | E2b `visit_value`, `visit_children`, `destroy`, `adopt_payload` | Count direct owned edges, not all transitively reachable objects on every retain. Handle descriptor/tag layouts and live collection extents. Replace recursive destruction/adoption of deep graphs with bounded-stack iteration. Define overflow, underflow, double-release and partial-construction behavior. |
| Recursive boxes | `qbe_aggregate.zig`, `qbe_borrow.zig`, `native_cow.c`, physical type/descriptor lowering | Support acyclic physical boxes, including million-deep immutable chains and shared DAGs. Preserve lazy child sharing and private payload behavior. A shared box pointer and a copied box body have different child-count effects. Do not revive source `class` semantics in the RC lane. |
| Collections and text | `native_collections.c`, `native_dictionary.c`, `native_bytes.c`, `native_text.c`; their emitter lowerings | Audit every insert, overwrite, removal, resize, sort, bulk copy, view and backing-store growth. Retain borrowed incoming edges before releasing possibly identical old edges; transfer owned inputs exactly once. Separate physical backing blocks from logical elements and preserve dictionary descriptor lifetime. |
| Pending receivers | `cow_plan*.zig`, `qbe_cow.zig`, scope functions in `native_cow.c` | Replace traced scope roots/links with explicit lifetime holds under the agreed pin contract. Capture the evaluated receiver, key and ancestors through callbacks, growth and write-back. Restore nested pin state and release holds/links once on normal, early and failed-preparation exits. |
| Arena lifetime | `native_arena.[ch]`, `qbe_arena.zig`, arena allocation lowering | Retain arena-owned edges into the RC heap/older regions and release them at overwrite or region close. Current `arena_trace` keeps them alive through GC; current `arena_release` only frees/caches chunks. Avoid double accounting list backing blocks, dead slots and nested arenas. Keep generated inline bump allocation in sync with the chosen header. |
| Arena escape | `native_regions.c`, region checks/lowering | Preserve the copier's source→clone map and DAG sharing, retain already-outer objects, and establish ownership of cloned edges once. Replace GC suspension/reclamation of partial clones with explicit rollback. Preserve invalid escape diagnostics and region-depth checks. |
| Resources and host boundaries | `qbe_resources.zig`, `native_heap.c::myl_native_owned_drop`, host/C-ABI lowerings and provider runtime | Define value-count versus unique-resource ownership; never duplicate a close/drop hook. Cover borrowed/static host data, returned aggregates, provider failures, resources containing managed values and callback lifetimes. E2b needed a follow-up fix merely to adopt host results. |
| GC-only structures | `qbe_roots.zig`, `qbe_managed.zig`, `qbe_alloc.zig`, runtime build/fragments | Omit GC root publication and collection barriers only in the RC artifact once all lifetime paths are accounted for. Keep the compatibility GC implementation and all non-GC error/frame/resource protocols. |

Descriptor recursion and runtime graph recursion need separate treatment. E2b
refuses types after depth 32; use a visited type graph for recursive physical
types instead. Releasing a million-node list-shaped box graph must not recurse
one native frame per node. Iterative release must remain correct under memory
pressure, when allocating another work queue may fail; choose its storage or
fallback strategy before relying on it for teardown. Audit runtime-only
back-pointers and metadata ownership too: acyclic source values alone do not
prove that every pointer in a native descriptor is a counted owning edge.
An iterative queue also needs destruction continuations or equivalent metadata
lifetimes: a dictionary's entry descriptor lives inside its header, so freeing
that header before queued entry destruction would leave a dangling descriptor.

Arena edge accounting needs a concrete design, not simply skipping counts on
arena payloads. The same heap child may be referenced by several arena slots
and an outer value; each owning edge must have a matching release. A raw scan
of every allocation can double-count a list and its storage unless ownership
categories distinguish them. Region escape failure must leave the source
usable and must not leak newly created clones or release an outer shared value.

## Prototype refusals to resolve

| E2b refusal | Production disposition |
|---|---|
| `class`, `Cell`, collection containing `Cell` | Remain invalid in the value/RC language lane; preserve their supported legacy behavior through GC. Do not blanket-reject recursive physical boxes as managed classes. |
| Resources with managed descendants | Implement the value-count/resource-drop composition for otherwise legal programs; retain existing language restrictions on copying unique resources. |
| Arena begin/end/escape | Remove the refusal with full region and rollback support. Arenas are a D9 requirement. |
| Managed/string elements in mutable fixed arrays and element replacement | Implement aggregate slot ownership and receiver lifetime preservation, including nested arrays and callbacks. |
| Indexed writes through record fields, dictionary values or unmodelled temporaries | Use current place/projection plans, stable indices/keys, detach and write-back semantics. Do not reintroduce unsupported-source-form refusals for legal D9 operations. |
| Mutation classified as borrowed | Stabilize/detach under the current ownership and mutation rules; distinguish a legal writable local from genuinely invalid source mutation. |
| `setdefault`, `update`, keyed/default `pop`, `remove`, `clear`, `take`, `truncate`, `resize` with managed elements | Define consume/borrow/return behavior for success, absence, self-alias and failure; release precisely removed elements and preserve ownership of returned ones. |
| Nontrivial `mut` argument producers and mut-parameter rebinding | Support every currently legal argument shape and control-flow producer. Preserve caller uniqueness/pinning, replacement ownership and nested scope cleanup. Illegal `mut` field/index syntax need not become legal. |
| Recursive descriptor depth over 32 | Replace the blanket recursion cutoff with recursive-type-aware classification and bounded runtime traversal. |

No production acceptance run may silently fall back to GC for a refused
value-mode function or omit its workload. Temporary diagnostic refusals during
implementation should have a tracked removal test; remaining language
diagnostics must match the accepted stage-3 contract.

## Proposed parallel work after prerequisites are accepted

First land a small serial contract change: runtime selection, object/arena ABI,
operation ownership table, scope-hold protocol and runtime entry-point
signatures. Add executable contract tests and cache identity checks there.
This is the dependency boundary that makes subsequent parallel work safe.

| Owner | Separate implementation branch | Exclusive initial files and join contract |
|---|---|---|
| Integrator | Contract, cache/build wiring, validation and final assembly | Own shared headers and build/cache mode wiring initially. Freeze interfaces before worker branches start; integrate real two-parent merges and serialize full gates. |
| Astra A | RC runtime and collection ownership | New production RC modules, `native_heap.c`, collection/dictionary/bytes/text runtime changes and native unit tests. Supply allocation, retain/release, unique, hold and collection-operation interfaces from the contract. |
| Astra B | Emitter action planning and borrow ABI | New RC plan/lowering modules, `ownership*`, `qbe.zig`, `qbe_cow.zig`, roots/managed/aggregate lowering and emitter/guest tests. Own scope code-generation changes; consume A's lifetime-hold API and final D9 liveness. |
| Astra C | Arenas, regions and external ownership boundaries | `native_arena*`, `native_regions.c`, arena/resource/host/C-ABI lowerings and corresponding tests. Review native resource drops with A; request shared-header changes through the integrator. Scope runtime changes in `native_cow.c` belong to A, coordinated with B. |

These are three worker slots plus the integrator. Do not have two workers edit
`qbe.zig`, `native_heap.h` or `native_cow.c` concurrently. Each branch first
delivers a tested vertical slice against the frozen interfaces. Unsupported
arena/scoped/boundary cases remain explicitly gated during development, not
enabled as an incomplete default. Join all required slices before assessing
production correctness or starting acceptance timings. Further optimizations
such as memory reuse, new uniqueness types or atomic counts are not prerequisites
for this implementation; concurrency remains WP-5.

## Required validation and acceptance record

- Run the complete current gate and value corpus on QBE and LLVM; preserve the
  legacy-sharing compatibility corpus, cyclic graphs, error traces and mode
  propagation. Retain Guardian limits without ratchet growth. Use Debug
  compilers, isolated caches and serialized full gates.
- Add native ownership invariants and targeted failure injection: allocation
  failure at construction/clone/scope/escape stages, exact releases of overwritten
  edges, self-assignment, duplicate DAG children, resource close counts, two
  independent heap contexts and clean teardown excluding documented immortals.
- Exercise million-deep immutable boxes, wide shared DAGs, nested fixed arrays,
  dictionary entry receivers, callback replacement/growth, earlier match
  snapshots, indexed/field transfers, nested pins, early return/error cleanup,
  arena→older-region edges, nested arena teardown and successful/failed escape.
  Run equivalent GC cases with GC stress and RC cases with count/lifetime
  assertions; the absence of a collector is not itself a stress test.
- Check generated ownership actions and dynamic counters on schematic accessor
  returns. Demonstrate the promised RC-relevant transfer reduction without
  dropping required counts on immutable bytes/boxes. Verify hoisting and retain
  separate diagnostic counting builds from timing builds.
- Freeze the accepted stage-3 GC compiler and final migrated sources as the
  WP-4 baseline. Measure both backends independently on the complete 43-key
  suite: historical 27 parity keys, three schematic inputs and 13 Lox VM keys.
  Keep exact stdout/SVG checks, pinned CPUs, median-three instruction samples,
  exact identities and raw per-key data. Do not substitute `60b668cf` for this
  new GC baseline, drop recursive binary trees, mix backends or change source
  arms silently. Include graph-heavy Lox and arena/recursive-tree diagnostics
  alongside the fixed suite; predeclare any expanded acceptance population.
- WP-4 requires instruction geomean **≤1.0**, every program **≤1.3**, and a
  lower median-program peak RSS than that GC baseline. Record median-three peak
  RSS per program and the resulting suite medians and paired ratios. The E2b
  allocator gains and schematic failure are hypotheses to remeasure, not
  credits toward acceptance. Keep legacy GC available for its compatibility
  release even after the value lane passes.

The immediate next step is acceptance of the existing stage-3/default and
physical-borrow work, followed by the serial ownership/ABI contract. The
prototype supplies useful machinery, but current receiver and region lifetime
semantics determine the production design.
