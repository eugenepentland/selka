#ifndef MYLANG_NATIVE_RC_H
#define MYLANG_NATIVE_RC_H
#include "native_heap.h"
/* The versioned RC artifact/heap ABI is never inferred from an arbitrary
 * pointer. GC, arena and immortal objects keep their 16-byte common header. */
#define MYL_RC_ABI_VERSION 3u
#define MYL_RC_PREFIX_BYTES ((size_t)32)
#define MYL_RC_COUNT_MAX UINTPTR_MAX
#define MYL_RC_COUNT_LIMIT_CODE "R_REFERENCE_COUNT_LIMIT"
/* Bit zero has no tracing meaning in an RC artifact. Set it exactly once when
 * O=H=0, before repurposing either count word as intrusive worklist storage. */
#define MYL_RC_OBJECT_DYING ((uintptr_t)MYL_NATIVE_OBJECT_MARKED)
typedef struct {
    uintptr_t owners, holds;
    myl_native_object common;
} myl_rc_object;
typedef enum {
    MYL_RC_OK, MYL_RC_ALLOCATION_REFUSED, MYL_RC_COUNT_LIMIT, MYL_RC_REGION_ERROR
} myl_rc_status;
/* Only recoverable failures are statuses. Underflow, DYING resurrection,
 * malformed metadata and unregistered ownership shapes are internal defects.
 * The located adapter upgrades OutOfMemory to R_MEMORY_BUDGET when the heap
 * reports exhaustion; metadata/host allocation refusal need not be budgeted. */
const char *myl_rc_status_code(myl_rc_status status);
int myl_rc_enabled(const myl_native_heap *);
/* NULL/int legacy helpers preserve their first failure until the located
 * compiler adapter consumes it; ownership-aware helpers return status directly. */
void myl_rc_record_failure(myl_native_heap *, myl_rc_status);
myl_rc_status myl_rc_take_failure(myl_native_heap *);

/* Ownership shapes are independent of native_type's GC scan view. A pointer
 * is a terminal owning edge; HOLD_POINTER is a terminal nonsharing lifetime
 * token. Its copy acquires H without pinning or snapshotting, take transfers H,
 * and drop releases H. Neither pointee is part of inline depth. NONE
 * ignores every byte. Variant tags are u32 at tag_offset. All sizes/offsets
 * and array arithmetic are checked size_t values, with no source-depth cap. */
typedef struct myl_rc_shape myl_rc_shape;
typedef struct myl_rc_slot myl_rc_slot;
typedef struct {
    size_t offset;
    const myl_rc_shape *shape;
    uint32_t tag;
} myl_rc_field;
typedef enum {
    MYL_RC_SHAPE_NONE, MYL_RC_SHAPE_POINTER, MYL_RC_SHAPE_RECORD,
    MYL_RC_SHAPE_ARRAY, MYL_RC_SHAPE_VARIANT, MYL_RC_SHAPE_HOLD_POINTER
} myl_rc_shape_kind;
struct myl_rc_shape {
    size_t size;
    myl_rc_shape_kind kind;
    union {
        struct { const myl_rc_field *fields; size_t count; } record;
        struct { const myl_rc_shape *element; size_t count, stride; } array;
        struct { const myl_rc_field *fields; size_t count, tag_offset; } variant;
    } as;
};
/* Adapters enumerate live logical edges without allocating, hashing, invoking
 * guest code or recursively draining. Header metadata remains alive for the
 * whole call. Raw backing has NONE shape and stable extent metadata; a held
 * dictionary backing must never borrow a dictionary-embedded descriptor.
 * finalize is reserved for explicitly unique resource hooks: it runs with an
 * idle descriptor stack, BEFORE releasing managed child edges and before
 * retire, so its callback context stays alive. It may enqueue, allocate or
 * register; existing unique cleanup delegates this hook exactly once. */
typedef struct {
    const myl_native_type *type;
    const myl_rc_shape *shape;
    void (*edges)(myl_native_heap *, void *, size_t);
    void (*finalize)(myl_native_heap *, void *);
    /* Optional collection clone: copy logical edges pin-aware into the exact
     * destination region. Fresh owned success; complete rollback on failure.
     * Without it a descriptor with no custom edges uses the generic body copy. */
    myl_rc_status (*clone)(myl_native_heap *, const void *, unsigned, void **);
    /* Iterative clone protocol: shell owns private backing but initializes no
     * logical value edges. next yields one empty destination/source slot pair
     * without allocation or hashing, returning 1 for a pair and 0 at the end.
     * A terminal shell with no remaining logical edges leaves next NULL. */
    myl_rc_status (*shell)(myl_native_heap *, const void *, unsigned, void **);
    int (*next)(myl_native_heap *, const void *, void *, size_t *, myl_rc_slot *, myl_rc_slot *);
} myl_rc_descriptor;
typedef struct {
    unsigned abi;
    const myl_rc_shape *const *shapes;
    size_t shape_count;
    const myl_rc_descriptor *descriptors;
    size_t descriptor_count;
} myl_rc_module;
/* Module metadata and native_type identities are immutable and live through
 * heap teardown. Registration copies shapes/fields and descriptor bindings,
 * then atomically publishes them and budget-charged teardown frames. Shapes
 * retain the native inline nesting even for raw-resource NONE leaves, so
 * registration also reserves the independent unique-drop traversal depth.
 * Count-free shapes may collapse internally after this reservation. Every
 * inline local/argument/result/host/arena shape registers before construction,
 * even if no allocation ever uses that shape. Repeated module registration is
 * idempotent. Failure preserves all old registrations and release capacity. */
myl_rc_status myl_rc_module_register(myl_native_heap *, const myl_rc_module *);
/* Runtime/foreign metadata with shorter lifetime uses import, which copies the
 * complete inline graph and returns a stable heap-lifetime shape. Source
 * metadata may be discarded immediately; its addresses are never identities. */
myl_rc_status myl_rc_shape_import(myl_native_heap *, const myl_rc_shape *,
                                    const myl_rc_shape **out);
const myl_rc_shape *myl_rc_shape_resolve(const myl_native_heap *, const myl_rc_shape *);
/* Register a runtime binding whose struct may be temporary; its native_type
 * identity stays valid through teardown and shape must already be registered.
 * The binding is copied atomically and its adapter code remains loaded. */
myl_rc_status myl_rc_descriptor_register(myl_native_heap *, const myl_rc_descriptor *);
/* Atomically import a temporary shape graph and its binding together. Failure
 * publishes neither shape nor binding; only native_type/code have long lifetime. */
myl_rc_status myl_rc_descriptor_import(myl_native_heap *, const myl_rc_descriptor *);
const myl_rc_descriptor *myl_rc_descriptor_find(const myl_native_heap *, const myl_native_type *);
size_t myl_rc_reserved_depth(const myl_native_heap *);
size_t myl_rc_metadata_bytes(const myl_native_heap *);

/* The allocator owns extent lookup, immediate reuse and accounting. allocate
 * returns zero-filled storage with a fully initialized RC/arena prefix and
 * exactly one owner on RC success. Failure rolls back every partial allocation
 * and initialized child edge, leaves inputs unchanged and *out NULL. retire is
 * allocation-free, takes only DYING ordinary heap storage after direct edges
 * and finalization, and advances its reuse epoch before reuse. destroy runs
 * only after all values, arenas, scopes and queued objects have been released.
 * Every allocation/reservation, including metadata, shares heap->limit/bytes. */
typedef struct {
    const myl_native_type *element;
    size_t count;
    unsigned region;
} myl_rc_alloc_request;
/* teardown releases every remaining extent at once after a trap: it runs no
 * finalizer, edge release or drain, and in a counting build it retires each
 * remaining object and releases its outstanding owner and hold counts. */
typedef struct {
    myl_rc_status (*allocate)(myl_native_heap *, const myl_rc_alloc_request *, void **);
    void (*retire)(myl_native_heap *, void *);
    void (*destroy)(myl_native_heap *);
    void (*teardown)(myl_native_heap *);
} myl_rc_allocator;
myl_rc_status myl_rc_heap_init(myl_native_heap *, const myl_rc_allocator *, void *allocator_context);
void *myl_rc_allocator_context(const myl_native_heap *);
void myl_rc_heap_destroy(myl_native_heap *);
/* Trap teardown of the whole RC heap. Traps are fatal, so no guest code runs
 * again: open scopes are abandoned, queued and live objects are released
 * wholesale through the allocator's teardown hook, and the heap is left empty
 * and consistent for destroy. Unique resources are not closed here; the
 * execution's resource registry closes each one exactly once, as it does for
 * the tracing collector. Arena regions must be discarded first. */
void myl_rc_heap_teardown(myl_native_heap *);
myl_rc_status myl_rc_new(myl_native_heap *, const myl_rc_alloc_request *, void **out);
void myl_rc_allocator_retire(myl_native_heap *, void *);

/* Owner acquisition establishes a physical token; it is not semantic value
 * publication (which must honor pins). NULL/immortal/arena are checked before
 * reading an RC prefix. Holds affect lifetime only. Both counts must be zero
 * to enqueue death. Internal edge_release only enqueues; public owner_release
 * drains at an idle safe boundary. Count failure makes no count change. */
myl_rc_status myl_rc_owner_acquire(myl_native_heap *, void *);
void myl_rc_edge_release(myl_native_heap *, void *);
void myl_rc_owner_release(myl_native_heap *, void *);
int myl_rc_unique(const myl_native_heap *, const void *);
typedef struct { void *payload; } myl_rc_hold;
myl_rc_status myl_rc_hold_acquire(myl_native_heap *, void *, myl_rc_hold *);
void myl_rc_hold_release(myl_native_heap *, myl_rc_hold *);
/* A pin owns its hold and restores the exact prior bit before releasing it.
 * Independent pin records nest LIFO; an arena pin cannot extend its region's
 * lifetime. Multi-pin scopes restore ALL pin bits before releasing ANY hold. */
typedef struct { myl_rc_hold hold; uintptr_t previous; } myl_rc_pin;
myl_rc_status myl_rc_pin_acquire(myl_native_heap *, void *, myl_rc_pin *);
void myl_rc_pin_release(myl_native_heap *, myl_rc_pin *);
/* Visit/drop only initialized live values. This borrows the heap's reserved
 * stack for a complete nonallocating direct-edge walk; it never recurses into
 * managed payloads. An adapter may call it repeatedly while no walk is active. */
void myl_rc_edges_release(myl_native_heap *, const myl_rc_shape *, void *, size_t count);
/* Read direct arena edges using the same reserved iterative shape stack. */
unsigned myl_rc_value_region(myl_native_heap *, const myl_rc_shape *, const void *);
/* Public ownership boundaries drain before returning to ordinary guest code.
 * Guest reentry from a finalizer instead inherits the active outer drain: its
 * queued siblings remain pending and nested drains do nothing. Direct-edge
 * adapters cannot enter guest code. A proven pure token relocation therefore
 * needs no drain; callers of internal enqueue-only helpers must drain before
 * entering guest code outside an active finalizer. */
void myl_rc_drain(myl_native_heap *);
/* Seed empty construction storage with scalar bytes/active tags, clearing all
 * direct owners and holds without releasing them. Source and destination are distinct. */
void myl_rc_value_seed(myl_native_heap *, const myl_rc_shape *, void *, const void *, size_t);
/* Abort one unpublished owned allocation. Arena payload edges are released
 * immediately and zeroed so later region teardown cannot release them twice. */
void myl_rc_construction_abort(myl_native_heap *, void *);
/* Descriptor finalizer for a noncopyable managed body containing raw unique
 * resource fields. Runs their existing drop adapter before counted children. */
void myl_rc_finalize_unique(myl_native_heap *, void *);
/* Close raw unique resources using the reserved inline stack, then call each
 * detached resource hook at idle walker depth. Managed pointers are terminal. */
void myl_rc_owned_drop(myl_native_heap *, const myl_native_type *, void *);

/* Owned slots identify a complete initialized value. Construction registers
 * first, then tracks initialized fields/tags or a collection's live prefix;
 * an uncommitted child token stays in an explicit temporary. Empty slots have
 * zeroed ownership-bearing bytes and a valid inactive variant tag. container
 * is a borrowed authority/lifetime anchor, never an extra owner. */
struct myl_rc_slot {
    const myl_rc_shape *shape;
    void *address, *container;
    unsigned region;
};
typedef enum { MYL_RC_COPY, MYL_RC_TAKE } myl_rc_transfer;
/* Copy/take initialize an empty destination. Ordinary POINTER edges preserve
 * snapshots across pins, including the last owner taken from a pending receiver.
 * HOLD_POINTER edges preserve live identity regardless of pins. Source/target
 * shapes must express the same token kinds; this is not an O/H conversion. Take
 * clears its source only on success. Replace prepares incoming ownership
 * before releasing old edges; failure preserves both slots. Relocate is only
 * proven movement of the SAME logical edge, never source-level publication. */
myl_rc_status myl_rc_value_copy(myl_native_heap *, myl_rc_slot *, const myl_rc_slot *);
/* One construction transaction across multiple empty slots (for example a
 * dictionary key/value pair), including immediate fresh-arena clone rollback. */
myl_rc_status myl_rc_value_copy_many(myl_native_heap *, myl_rc_slot *, const myl_rc_slot *, size_t);
myl_rc_status myl_rc_value_take(myl_native_heap *, myl_rc_slot *, myl_rc_slot *);
myl_rc_status myl_rc_value_replace(myl_native_heap *, myl_rc_slot *, myl_rc_slot *, myl_rc_transfer);
void myl_rc_value_drop(myl_native_heap *, myl_rc_slot *);
void myl_rc_value_relocate(myl_rc_slot *, myl_rc_slot *);
typedef struct { void *payload; unsigned owned; } myl_rc_edit;
typedef struct myl_rc_scope {
    myl_native_heap *heap;
    struct myl_rc_scope *previous;
    void *journal;
    unsigned active, region;
} myl_rc_scope;
typedef struct { const myl_rc_shape *shape; size_t offset; unsigned immutable_box; } myl_rc_projection;
typedef struct {
    myl_rc_slot receiver;
    const myl_rc_projection *path;
    size_t count;
} myl_rc_place;
void myl_rc_scope_begin(myl_native_heap *, myl_rc_scope *);
myl_rc_status myl_rc_scope_hold(myl_rc_scope *, void *);
myl_rc_status myl_rc_scope_pin(myl_rc_scope *, void *);
/* Receiver detachment never moves an existing leaf into a younger region.
 * The place's destination region remains the maximum allocation depth. */
myl_rc_status myl_rc_scope_prepare(myl_rc_scope *, const myl_rc_place *);
/* The inline receiver contains loan H tokens. A heap-body dereference resumes
 * ordinary child ownership; successful replacements preserve the loan role. */
myl_rc_status myl_rc_scope_prepare_loan(myl_rc_scope *, const myl_rc_place *);
/* Close even empty/partly prepared scopes: unlink, restore pins in reverse
 * order, release holds/journal exactly once, then drain. Escape first. */
void myl_rc_scope_end(myl_rc_scope *);
/* A checkpoint is a borrowed active scope. Unwind closes only newer scopes;
 * all captured pin states in that prefix are restored before any hold drops. */
myl_rc_scope *myl_rc_scope_current(myl_native_heap *);
void myl_rc_scope_unwind(myl_native_heap *, myl_rc_scope *checkpoint);
/* Uniqueness slots contain one managed payload pointer, never an inline
 * aggregate. The caller zero-initializes edit; failure leaves it empty. */
myl_rc_status myl_rc_unique_owned(myl_native_heap *, myl_rc_slot *);
/* Immutable body writes always detach, preserving older region and committing
 * semantic history on reused mutable children, even without ordinary aliases. */
myl_rc_status myl_rc_box_detach_owned(myl_native_heap *, myl_rc_slot *);
/* The same immutable-body transaction through an initialized H token. */
myl_rc_status myl_rc_box_detach_held(myl_native_heap *, myl_rc_slot *);
/* An initialized HOLD_POINTER slot remains H after uniqueness detaches it.
 * Refusal leaves the original token and slot intact. */
myl_rc_status myl_rc_unique_held(myl_native_heap *, myl_rc_slot *);
/* Reuse is a borrow; detach is an owned token. The parent edge is intact until
 * commit, which requires the closed edit's unchanged-place proof. Abort drops
 * only a detached token. A callback-replaced parent must never be resurrected. */
myl_rc_status myl_rc_unique_borrow(myl_native_heap *, const myl_rc_slot *, const myl_rc_scope *, myl_rc_edit *);
void myl_rc_edit_abort(myl_native_heap *, myl_rc_edit *);
void myl_rc_edit_commit(myl_native_heap *, myl_rc_slot *, myl_rc_edit *);
myl_rc_status myl_rc_region_escape(myl_native_heap *, myl_rc_slot *, const myl_rc_slot *);
void myl_rc_arena_close(myl_native_heap *, unsigned depth);
#endif
