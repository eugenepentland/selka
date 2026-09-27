#ifndef MYLANG_NATIVE_RC_INTERNAL_H
#define MYLANG_NATIVE_RC_INTERNAL_H
#include "native_rc.h"
#include "native_rc_stats.h"
/* Private state: generated code sees only the frozen object/common prefixes. */
typedef struct {
    union { const myl_rc_shape *shape; const myl_native_type *type; };
    unsigned char *address;
    size_t cursor;
} myl_rc_frame;
typedef struct {
    const myl_rc_shape *source;
    myl_rc_shape shape;
    size_t depth;
    size_t inline_depth;
} myl_rc_shape_entry;
/* Checked mode keeps invariants that need a metadata lookup or a value walk
 * (stats/counting builds and the C contract tests). Production keeps only the
 * constant-time checks; a checked invariant must never have side effects. */
#ifndef MYL_RC_CHECKED
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
#define MYL_RC_CHECKED 1
#else
#define MYL_RC_CHECKED 0
#endif
#endif
#define MYL_RC_FLAT_LEAVES 16
#define MYL_RC_FLAT_ALWAYS UINT32_MAX
/* One owning leaf of a flat plan. A conditional leaf is live only while the
 * u32 at tag_offset equals tag, exactly as the generic walker visits one
 * variant arm; unconditional leaves use MYL_RC_FLAT_ALWAYS. */
typedef struct { uint32_t offset, tag_offset, tag; } myl_rc_leaf;
/* Private plan, never part of emitted metadata. count > the bound means the
 * authoritative shape/native-kind pair requires generic traversal. Leaves are
 * in the generic walker's order; simultaneously live leaves never overlap one
 * another or any tag word. */
#define MYL_RC_FLAT_ARMS 32
/* Hot fields first: an operation reads the header, one live set and offsets. */
typedef struct {
    unsigned count;
    unsigned char loanable, native_unique, conditional;
    uint32_t arm_offset;
    /* The native element size, copied so flat paths never load the type. */
    size_t size;
    /* Live-leaf bit sets, bit i for leaf i. `all` is every leaf. When every
     * conditional leaf tests the one tag word at arm_offset with a tag below
     * MYL_RC_FLAT_ARMS, arms[tag] is that arm's live set and `always` (the
     * unconditional leaves) serves every other tag; otherwise arm_offset is
     * MYL_RC_FLAT_ALWAYS and each conditional leaf is tested on its own. */
    uint16_t all, always, arms[MYL_RC_FLAT_ARMS];
    uint32_t offsets[MYL_RC_FLAT_LEAVES];
    myl_rc_leaf leaves[MYL_RC_FLAT_LEAVES];
} myl_rc_flat;
_Static_assert(MYL_RC_FLAT_LEAVES <= 16, "live-leaf sets are 16 bits");
/* alloc_class caches the production allocator's size class for a single
 * element (class + 1; 0 unknown or not slab-sized). */
typedef struct { myl_rc_descriptor descriptor; myl_rc_flat flat; unsigned alloc_class; } myl_rc_binding;
_Static_assert(offsetof(myl_rc_binding, descriptor) == 0, "indexed descriptor is its private binding prefix");
static inline int myl_rc_leaf_live(const myl_rc_leaf *leaf, const unsigned char *base) {
    if (leaf->tag_offset == MYL_RC_FLAT_ALWAYS) return 1;
    uint32_t tag;
    __builtin_memcpy(&tag, base + leaf->tag_offset, sizeof tag);
    return tag == leaf->tag;
}
/* The leaves live in the value at base, read before any edge is changed. */
static inline unsigned myl_rc_flat_live(const myl_rc_flat *flat, const unsigned char *base) {
    if (!flat->conditional) return flat->all;
    if (flat->arm_offset != MYL_RC_FLAT_ALWAYS) {
        uint32_t tag;
        __builtin_memcpy(&tag, base + flat->arm_offset, sizeof tag);
        return tag < MYL_RC_FLAT_ARMS ? flat->arms[tag] : flat->always;
    }
    unsigned live = 0;
    for (unsigned i = 0; i < flat->count; ++i)
        if (myl_rc_leaf_live(&flat->leaves[i], base)) live |= 1u << i;
    return live;
}
typedef struct myl_rc_batch {
    struct myl_rc_batch *next;
    const myl_rc_module *module;
    myl_rc_shape_entry *shapes;
    myl_rc_binding *bindings;
    struct { size_t shapes, descriptors; } count;
    size_t bytes;
} myl_rc_batch;
/* Open-addressed pointer map with a power-of-two capacity kept at most half
 * full. An empty map points at a shared one-slot sentinel, so a lookup is a
 * multiply, a mask and a probe with no emptiness branch. Keys are never NULL. */
typedef struct { const void *key, *value; } myl_rc_map_entry;
typedef struct { const myl_rc_map_entry *entries; size_t mask, count; } myl_rc_map;
extern const myl_rc_map_entry myl_rc_map_sentinel[1];
static inline size_t myl_rc_map_home(const void *key, size_t mask) {
    return (size_t)(((uintptr_t)key * UINT64_C(0x9e3779b97f4a7c15)) >> 32) & mask;
}
static inline const void *myl_rc_map_get(const myl_rc_map *map, const void *key) {
    size_t mask = map->mask, slot = myl_rc_map_home(key, mask);
    for (;;) {
        const myl_rc_map_entry *entry = &map->entries[slot];
        if (entry->key == key) return entry->value;
        if (!entry->key) return NULL;
        slot = (slot + 1) & mask;
    }
}
/* A released scope journal node waits here for the next capture. Spare nodes
 * are uncharged (at most MYL_RC_SPARE_ENTRIES of them); taking one repeats
 * the metadata budget admission and charge, so accounting matches a fresh
 * allocation exactly. Heap teardown frees them. */
typedef struct myl_rc_spare { struct myl_rc_spare *next; } myl_rc_spare;
#define MYL_RC_SPARE_ENTRIES 32
struct myl_rc_state {
    struct { myl_rc_allocator hooks; void *context; } allocator;
    struct {
        myl_rc_batch *batches;
        size_t bytes;
        /* Modules, shape identities (registered copies and persistent sources)
         * and native_type bindings. All three commit together. */
        myl_rc_map modules, shapes, bindings;
    } metadata;
    struct { myl_rc_frame *frames; size_t capacity, depth; } walk;
    struct { myl_rc_object *head; int active; } dead;
    myl_rc_scope *scopes;
    struct { myl_rc_spare *entries; size_t count; } spare;
    myl_rc_status failure;
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
    myl_rc_counters stats;
#endif
};
__attribute__((cold, noreturn)) void myl_rc_invariant_failed(void);
/* Keep every check in production, but only a violated invariant calls out. */
static inline void myl_rc_invariant(int valid) {
    if (!valid) myl_rc_invariant_failed();
}
/* An invariant whose evaluation needs a lookup or a walk; see MYL_RC_CHECKED. */
#define myl_rc_checked(valid) do { if (MYL_RC_CHECKED) myl_rc_invariant(valid); } while (0)
/* The registered binding of a native type, or NULL: one inline probe. */
static inline const myl_rc_binding *myl_rc_binding_find(const myl_native_heap *heap, const myl_native_type *type) {
    return (const myl_rc_binding *)myl_rc_map_get(&heap->rc->metadata.bindings, type);
}
/* Descriptor view of the same probe for RC-enabled runtime-internal callers. */
static inline const myl_rc_descriptor *myl_rc_descriptor_of(const myl_native_heap *heap, const myl_native_type *type) {
    const myl_rc_binding *binding = myl_rc_binding_find(heap, type);
    return binding ? &binding->descriptor : NULL;
}
/* The registered copy of a shape identity (itself or a persistent source). */
static inline const myl_rc_shape *myl_rc_shape_find(const myl_native_heap *heap, const myl_rc_shape *shape) {
    return (const myl_rc_shape *)myl_rc_map_get(&heap->rc->metadata.shapes, shape);
}
/* Pointer-owning depth of a shape already returned by a registry lookup. */
static inline size_t myl_rc_registered_depth(const myl_rc_shape *registered) {
    return ((const myl_rc_shape_entry *)((const unsigned char *)registered -
        offsetof(myl_rc_shape_entry, shape)))->depth;
}
/* Inline forms of the count primitives for runtime-internal hot paths. They
 * perform exactly the public functions' checks, counts and statistics. */
static inline int myl_rc_counted(const void *payload) {
    return payload && !(((const myl_native_object *)payload - 1)->mark &
        (MYL_NATIVE_OBJECT_IMMORTAL | MYL_NATIVE_OBJECT_ARENA));
}
static inline myl_rc_object *myl_rc_live(void *payload) {
    myl_rc_object *object = (myl_rc_object *)payload - 1;
    myl_rc_invariant(!(object->common.mark & MYL_RC_OBJECT_DYING) && (object->owners || object->holds));
    return object;
}
/* myl_rc_allocator_retire for a DYING counted object known to runtime code. */
static inline void myl_rc_retire(myl_native_heap *heap, myl_rc_object *object) {
    myl_rc_invariant((object->common.mark & (MYL_RC_OBJECT_DYING | MYL_NATIVE_OBJECT_IMMORTAL |
        MYL_NATIVE_OBJECT_ARENA)) == MYL_RC_OBJECT_DYING);
    MYL_RC_STAT(heap, MYL_RC_STAT_RETIRE);
    heap->rc->allocator.hooks.retire(heap, object + 1);
}
void myl_rc_enqueue(myl_native_heap *, myl_rc_object *);
/* Out-of-line half of a death outside any drain: retire an edge-free object
 * at once, or queue it. The object is already DYING. */
void myl_rc_dead_outside(myl_native_heap *, myl_rc_object *);
/* O=H=0: mark DYING exactly once. Inside an active drain (or finalizer
 * reentry) the object is queued inline behind its siblings. */
static inline void myl_rc_dies(myl_native_heap *heap, myl_rc_object *object) {
    myl_rc_invariant(!(object->common.mark & MYL_RC_OBJECT_DYING));
    object->common.mark |= MYL_RC_OBJECT_DYING;
    if (!heap->rc->dead.active) { myl_rc_dead_outside(heap, object); return; }
    object->owners = (uintptr_t)heap->rc->dead.head;
    heap->rc->dead.head = object;
}
/* Release one counted O edge and enqueue its death; the caller drains. */
static inline void myl_rc_owner_drop(myl_native_heap *heap, void *payload) {
    if (!myl_rc_counted(payload)) return;
    myl_rc_object *object = (myl_rc_object *)payload - 1;
    myl_rc_invariant(object->owners != 0 && !(object->common.mark & MYL_RC_OBJECT_DYING));
    --object->owners;
    MYL_RC_STAT(heap, MYL_RC_STAT_OWNER_RELEASE);
    if (!object->owners && !object->holds) myl_rc_dies(heap, object);
}
/* Release one counted H token and enqueue its death; the caller drains. */
static inline void myl_rc_hold_drop(myl_native_heap *heap, void *payload) {
    if (!myl_rc_counted(payload)) return;
    myl_rc_object *object = (myl_rc_object *)payload - 1;
    myl_rc_invariant(object->holds != 0 && !(object->common.mark & MYL_RC_OBJECT_DYING));
    --object->holds;
    MYL_RC_STAT(heap, MYL_RC_STAT_HOLD_RELEASE);
    if (!object->owners && !object->holds) myl_rc_dies(heap, object);
}
/* myl_rc_unique's predicate without its statistics event: a caller that
 * returns on a positive answer records UNIQUE_CHECK itself, and a caller that
 * falls back to a counting slow path records nothing. */
static inline int myl_rc_unique_payload(const void *payload) {
    if (!payload) return 1;
    uintptr_t mark = ((const myl_native_object *)payload - 1)->mark;
    if (mark & (MYL_NATIVE_OBJECT_IMMORTAL | MYL_NATIVE_OBJECT_SHARED)) return 0;
    if (mark & MYL_NATIVE_OBJECT_ARENA) return 1;
    myl_rc_invariant(!(mark & MYL_RC_OBJECT_DYING));
    const myl_rc_object *object = (const myl_rc_object *)payload - 1;
    myl_rc_invariant(object->owners || object->holds);
    return object->owners <= 1;
}
/* Drain only when a death is queued; myl_rc_drain repeats its own admission. */
static inline void myl_rc_drain_pending(myl_native_heap *heap) {
    if (heap->rc->dead.head) myl_rc_drain(heap);
}
/* Metadata budget: admit checks the limit (marking exhaustion on refusal),
 * charge/discharge move heap->bytes and the metadata total together. */
int myl_rc_meta_admit(myl_native_heap *, size_t);
void myl_rc_meta_charge(myl_native_heap *, size_t);
void myl_rc_meta_discharge(myl_native_heap *, size_t);
void *myl_rc_meta_alloc(myl_native_heap *, size_t);
void myl_rc_meta_free(myl_native_heap *, void *, size_t);
int myl_rc_size_add(size_t, size_t, size_t *);
int myl_rc_size_mul(size_t, size_t, size_t *);
int myl_rc_is_counted(const void *);
size_t myl_rc_shape_depth(const myl_native_heap *, const myl_rc_shape *);
/* Point every metadata map at the empty sentinel / free every map table. */
void myl_rc_metadata_init(myl_rc_state *);
void myl_rc_metadata_release(myl_native_heap *);
/* Private identity hint only; clients must repeat all operation admission. */
const myl_rc_descriptor *myl_rc_descriptor_repeat(const myl_native_heap *, const myl_native_type *);
void myl_rc_scopes_close_region(myl_native_heap *, unsigned);
myl_rc_status myl_rc_scope_extend(myl_rc_scope *, void *boundary, myl_rc_status (*)(myl_rc_scope *, void *));
/* Release one H token and enqueue death without callbacks; caller drains. */
void myl_rc_hold_edge_release(myl_native_heap *, void *);
/* Admitted ordinary leaves only, in the authoritative walker's order. Clears
 * and enqueues each edge without callbacks or allocation; caller drains. */
void myl_rc_flat_edges_release(myl_native_heap *, const myl_rc_binding *, void *, size_t count);
/* Internal native bridge: shape is an already registered ordinary pointer. */
myl_rc_status myl_rc_pointer_transfer(myl_native_heap *, const myl_rc_shape *, void *, void *, unsigned, myl_rc_transfer);
/* Physical loan primitives: ordinary and held leaves both contribute H.
 * The native wrapper excludes every raw unique obligation first. */
myl_rc_status myl_rc_loan_copy(myl_native_heap *, const myl_rc_shape *, void *, const void *);
void myl_rc_loan_drop(myl_native_heap *, const myl_rc_shape *, void *);
/* Nonmutating native inline-type walk; terminal managed payloads stay opaque. */
int myl_rc_native_has_unique(myl_native_heap *, const myl_native_type *);
/* Heap-local memo of the completed native predicate: 0 unknown, 1 no, 2 yes.
 * The binding/type and consulted body finalizers are immutable through teardown.
 * This never replaces the loan's separate actual-payload finalizer check. */
int myl_rc_binding_has_unique(myl_native_heap *, const myl_rc_binding *);
/* Native mutable collection classification used only by semantic transfers. */
int myl_rc_native_mutable(const void *);
/* Acquire ordinary edges without semantic history or pinned snapshots. */
myl_rc_status myl_rc_value_retain_many(myl_native_heap *, myl_rc_slot *, const myl_rc_slot *, size_t);
myl_rc_status myl_rc_semantic_transfer(myl_native_heap *, myl_rc_slot *, const myl_rc_slot *, myl_rc_transfer, unsigned);
#endif
