#ifndef MYLANG_NATIVE_HEAP_H
#define MYLANG_NATIVE_HEAP_H
#include <stddef.h>
#include <stdint.h>
/* Descriptor storage outlives the heap. Offsets describe native bytes, never VM
 * tagged values. Variant fields trace only when their u32 tag matches. */
typedef struct myl_native_type myl_native_type;
typedef struct {
    size_t offset;
    const myl_native_type *type;
    uint32_t tag;
} myl_native_field;
struct myl_native_type {
    size_t size;
    size_t alignment;
    const myl_native_field *fields;
    size_t field_count;
    size_t count;
    size_t stride;
    unsigned kind;
    unsigned collection_kind; /* 0 opaque, 1 list, 2 string, 3 dictionary, 4 bytes */
    const myl_native_type *element, *key;
    /* GC-only field view. Runtime-built descriptors may leave trace_mode zero,
     * which preserves the legacy walk through `fields`. Generated descriptors
     * use NONE for pointer-free values and FIELDS for a filtered table containing
     * only children that can reach managed storage. Other descriptor consumers
     * continue to use the complete field table above. */
    const myl_native_field *trace_fields;
    size_t trace_field_count;
    unsigned trace_mode;
};
enum { MYL_NATIVE_TRACE_LEGACY, MYL_NATIVE_TRACE_NONE, MYL_NATIVE_TRACE_FIELDS };
enum { MYL_NATIVE_PLAIN, MYL_NATIVE_POINTER, MYL_NATIVE_RECORD,
       MYL_NATIVE_ARRAY, MYL_NATIVE_VARIANT, MYL_NATIVE_OWNED_BUFFER, MYL_NATIVE_OWNED_POOL, MYL_NATIVE_FLOAT, MYL_NATIVE_RESOURCE };
typedef struct myl_native_root {
    struct myl_native_root *previous;
    void *address;
    const myl_native_type *type;
    /* Fourth word: storage for a traced scalar whose slot generated code kept in
     * a register. A root pushed that way points `address` at this word, so the
     * collector still reads the pointer through `address`; a root pushed from a
     * live slot leaves this word unused. */
    void *value;
} myl_native_root;
/* One tracing-heap allocation's two-word header, laid out immediately before its
 * payload so the collector reaches it as `(myl_native_object *)payload - 1`.
 * Word 0 is the mark word: bit 0 is the collector's mark, bit 1 marks storage
 * that lives outside the heap (a frozen `str`/`bytes` literal), which the
 * collector never queues, re-traces, frees or bulk-releases, and every higher
 * bit holds the element count. A reclaimed slot reuses the whole word as its
 * free-list link with `MYL_NATIVE_OBJECT_FREE` set above the link, because a
 * free slot carries no count. The count lives in the header rather than in the
 * segment because precise tracing needs it for any payload address, including
 * one first reached through a root. Word 1 is the element descriptor. Two words
 * keep the payload aligned to `max_align_t` because a segment slot is. An arena
 * payload carries the same two words, so every managed payload's region,
 * element and count are one header load away; its mark word is described with
 * MYL_NATIVE_OBJECT_ARENA below. */
struct myl_native_object {
    uintptr_t mark;
    const myl_native_type *element;
};
typedef struct myl_native_object myl_native_object;
enum { MYL_NATIVE_OBJECT_MARKED = 1, MYL_NATIVE_OBJECT_IMMORTAL = 2,
       MYL_NATIVE_OBJECT_COUNT_SHIFT = 2 };
/* The mark word's sign bit, above any canonical address and above the element
 * count. A free slot's word is `link | MYL_NATIVE_OBJECT_FREE`. */
#define MYL_NATIVE_OBJECT_FREE (((uintptr_t)1) << (sizeof(uintptr_t) * 8 - 1))
/* The mark word of an arena allocation: this flag, the owning arena depth in
 * the bits from MYL_NATIVE_ARENA_REGION_SHIFT up to the flag, and the element
 * count between the two flag bits and the depth. The collector never sets the
 * mark or immortal bit on one, and a tracing-heap count is kept below the flag,
 * so the flag alone tells an arena payload from every other managed payload. */
#define MYL_NATIVE_OBJECT_ARENA (((uintptr_t)1) << 62)
#define MYL_NATIVE_ARENA_REGION_SHIFT 40
/* Largest element count a tracing-heap mark word holds below the arena flag. */
#define MYL_NATIVE_OBJECT_COUNT_MAX ((size_t)((MYL_NATIVE_OBJECT_ARENA >> MYL_NATIVE_OBJECT_COUNT_SHIFT) - 1))
/* Largest element count and arena depth an arena mark word holds. The depth
 * bound is far beyond any nesting a native stack can reach. */
#define MYL_NATIVE_ARENA_COUNT_MAX ((((size_t)1) << (MYL_NATIVE_ARENA_REGION_SHIFT - MYL_NATIVE_OBJECT_COUNT_SHIFT)) - 1)
#define MYL_NATIVE_ARENA_REGION_MAX ((unsigned)((MYL_NATIVE_OBJECT_ARENA >> MYL_NATIVE_ARENA_REGION_SHIFT) - 1))
/* Arena depth owning one non-null managed payload, read from its header: the
 * recorded depth for an arena allocation, 0 for a tracing-heap object or a
 * frozen literal. One load, whatever the number of arena chunks. */
static inline unsigned myl_native_header_region(const void *payload) {
    uintptr_t mark = ((const myl_native_object *)payload - 1)->mark;
    if (!(mark & MYL_NATIVE_OBJECT_ARENA)) return 0;
    return (unsigned)((mark >> MYL_NATIVE_ARENA_REGION_SHIFT) & MYL_NATIVE_ARENA_REGION_MAX);
}
/* The mark word a generated frozen literal block in the image initializes. Such
 * a block is never queued, so its element count is unreachable and only the
 * immortal flag is spelled. */
#define MYL_NATIVE_OBJECT_LITERAL_MARK ((uintptr_t)MYL_NATIVE_OBJECT_IMMORTAL)
/* Number of size classes the tracing heap slabs objects into, and the largest
 * object they cover. A bigger object gets a one-slot segment of its own. The
 * strides themselves live with the allocator in native_heap.c, which asserts
 * this count matches its table. */
#define MYL_NATIVE_CLASS_COUNT 52
#define MYL_NATIVE_CLASS_LIMIT ((size_t)262144)
/* One size-classed slab of tracing-heap storage: `slots` fixed-stride object
 * slots at `data`, zero-filled by the host on first use. `used` counts the
 * slots handed out by the bump pointer, and `class_index` names the stride's
 * class (`MYL_NATIVE_CLASS_COUNT` for a one-slot oversized segment). */
typedef struct myl_native_segment {
    struct myl_native_segment *next;
    size_t stride, slots, used, class_index;
    max_align_t payload_alignment;
    unsigned char data[];
} myl_native_segment;
typedef struct myl_native_drop_link {
    struct myl_native_drop_link *next;
    void *owner;
    unsigned kind;
} myl_native_drop_link;
typedef struct myl_native_resource {
    void (*drop)(struct myl_native_resource *);
    myl_native_drop_link work;
} myl_native_resource;
typedef struct myl_native_region {
    uint64_t identity;
    struct myl_native_region *parent;
    size_t users, children;
} myl_native_region;
/* Bulk arena counters, reported separately from tracing reclamation. `chunks`
 * counts host reservations, so a chunk taken from the retention cache instead
 * of the host advances `reused` and not `chunks`. `chunks_live`,
 * `reserved_bytes` and `peak_reserved_bytes` count only chunks currently
 * serving allocations: a retained chunk has already been discharged from them
 * and from the memory budget, and is counted by `cached`/`cached_bytes`. */
typedef struct {
    uint64_t scopes, released, escaped, allocations, chunks, reused;
    size_t chunks_live, reserved_bytes, peak_reserved_bytes;
    size_t cached, cached_bytes;
} myl_native_arena_statistics;
typedef struct myl_native_arena_chunk myl_native_arena_chunk;
typedef struct {
    /* Every size-classed slab the heap ever reserved; the sweep walks this list
     * of segments, so no object carries a link to its neighbour. */
    myl_native_segment *segments;
    /* Collector worklist: objects marked but whose children are not yet
     * traced. Grown on demand and empty outside a collection. */
    myl_native_object **pending;
    myl_native_root *roots;
    size_t bytes;
    size_t owned_capacity, pool_owners, pool_slots;
    uint64_t next_pool_identity;
    size_t objects_live;
    size_t allocations;
    size_t collections;
    size_t limit, next_collection;
    int stress;
    /* Set once an allocation was refused by `limit` rather than by the host
     * allocator, so the trap names the budget instead of an out-of-memory host. */
    int exhausted;
    /* Innermost arena depth; 0 is the ordinary tracing heap. Collection is
     * suspended only while one escape copy builds its not-yet-rooted clones. */
    unsigned region_depth;
    int suspended;
    myl_native_arena_statistics arena;
    /* Immortal one-scalar texts for the ASCII range: `text[i]` on a scalar below
     * 128 returns the shared object here instead of allocating a fresh copy. The
     * table is filled lazily, and the collector marks every entry directly rather
     * than through the root stack, because the generated code restores that stack
     * to a per-frame mark and would otherwise drop a lazily pushed root. A slot
     * stays NULL if its allocation was refused, and the caller falls back to an
     * ordinary copy. */
    void *text_scalars[128];
    int text_scalars_ready;
    /* Region payloads and their compact side descriptors share bulk chunks.
     * Appended fields preserve generated code's fixed root-chain offset. */
    myl_native_arena_chunk *arena_chunks;
    /* Chunks a closed scope released, kept for the next scope's first
     * allocation so a loop of short scopes does not reserve and zero a fresh
     * chunk per iteration. Bounded in count and bytes, never reachable from
     * `arena_chunks`, and freed by `myl_native_heap_destroy`. */
    myl_native_arena_chunk *arena_cache;
    /* Appended fields preserve generated code's fixed root-chain offset. The
     * collector's worklist is heap-side, so no object pays for a link.
     * `scratch_failed` records a worklist reservation the host refused: the
     * collection is abandoned unmarked and the allocation that ran it is
     * refused, so a partial mark can never be swept. */
    size_t pending_len, pending_capacity;
    int scratch_failed;
    /* Bump segment and reclaimed-slot list per size class. A class's free list
     * is threaded through reclaimed headers; `current` is the segment the bump
     * pointer still has room in. */
    myl_native_segment *current[MYL_NATIVE_CLASS_COUNT];
    myl_native_object *free_lists[MYL_NATIVE_CLASS_COUNT];
} myl_native_heap;
/* Address space granted to a guest process on top of its managed byte budget:
 * program text, the C library's own arenas and the test harness that loads it.
 * A trivial native guest needs about 64 MiB of address space before it holds
 * any managed bytes at all, so the soft budget is always reached first. */
#define MYL_NATIVE_BUDGET_HEADROOM (((size_t)256) << 20)
/* Name of the environment variable every spawner sets to publish a guest's byte
 * ceiling. Bytes, with an optional K, M or G suffix; empty or absent grants none. */
#define MYL_NATIVE_BUDGET_VARIABLE "MYLANG_MEMORY_LIMIT"
/* Parse a byte budget written as digits with an optional K, M or G suffix.
 * Returns 1 and stores the value, or 0 for empty, trailing or overflowing text. */
int myl_native_budget_parse(const char *text, size_t *out);
/* The budget named by MYL_NATIVE_BUDGET_VARIABLE, or 0 when it names none.
 * Stores 0 through `valid` when the variable is present but malformed, so a
 * caller refuses to run rather than running unbounded. */
size_t myl_native_budget_environment(int *valid);
/* Cap this process's address space at `budget` plus MYL_NATIVE_BUDGET_HEADROOM,
 * the kernel backstop behind the heap's own budget. Never raises an existing
 * tighter ceiling, and applies none under a sanitizer, whose shadow mapping
 * reserves far more address space than any budget would allow. Returns 1 when a
 * ceiling was installed. */
int myl_native_budget_guard(size_t budget);
void myl_native_heap_init(myl_native_heap *heap, size_t limit);
void myl_native_heap_destroy(myl_native_heap *heap);
void myl_native_root_push(myl_native_heap *heap, myl_native_root *root,
                          void *address, const myl_native_type *type);
/* Returns zero on mismatched root pop, preserving the root chain. */
int myl_native_root_pop(myl_native_heap *heap, myl_native_root *root);
/* Allocate count contiguous typed elements. Returns NULL on overflow or budget
 * exhaustion. Caller roots inputs before allocation and output before the next
 * allocation safepoint. Zero-filled payload is safe for precise tracing. */
void *myl_native_heap_alloc(myl_native_heap *heap,
                            const myl_native_type *element, size_t count);
/* Allocate one block holding `prefix` bytes of caller-owned header followed
 * immediately by `extra` bytes of data the caller owns inline. The whole block
 * is charged, tracked and freed as one object whose payload holds no traced
 * pointer, so the collector never walks it; a reference the caller stores into
 * the data must point at another heap object. Returns NULL on overflow or
 * budget exhaustion. */
void *myl_native_heap_alloc_block(myl_native_heap *heap, size_t prefix, size_t extra);
/* Grow one oversized, one-slot managed block to `count` elements of its own
 * element type, in place when the host can extend the reservation and moved —
 * with its bytes — when it cannot. The payload address is unchanged when the
 * reservation could be extended, which is what lets a buffer grow without
 * copying and without faulting a second time for pages it already owns.
 *
 * This is the allocator's growth path, not a constructor: it answers NULL for a
 * payload that is not the whole of its own one-slot segment, for an arena or
 * immortal allocation, for a count that is not larger, for a request that would
 * overflow, and for one the memory budget refuses after the same collection the
 * ordinary allocation path would run. The bytes the block did not already hold
 * are zeroed unless its element descriptor is opaque — `MYL_NATIVE_PLAIN` with
 * `MYL_NATIVE_TRACE_NONE` — in which case the collector is promised never to
 * interpret them and only the caller's own writes are readable. A refused
 * request leaves the block exactly as it was; the caller then allocates a fresh
 * block and copies into it.
 *
 * The reservation may move, so the caller must treat every address it derived
 * from the block — the payload itself and any pointer into its bytes — as dead
 * the moment it asks. Only a block nothing else points into may grow. */
void *myl_native_heap_extend(myl_native_heap *heap, void *payload, size_t count);
void myl_native_heap_collect(myl_native_heap *heap);
/* Allocate at an explicit arena depth so collection backing joins its owner
 * rather than the innermost open arena. */
void *myl_native_heap_alloc_at(myl_native_heap *heap,
                               const myl_native_type *element, size_t count, unsigned region);
/* Arena depth owning one managed payload; 0 for the ordinary tracing heap. */
unsigned myl_native_object_region(const myl_native_heap *heap, const void *payload);
/* Allocation metadata for GC, arena and static payloads without assuming an
 * adjacent header. NULL payload has no element and is not immortal. */
const myl_native_type *myl_native_object_element(const myl_native_heap *heap, const void *payload);
int myl_native_object_immortal(const myl_native_heap *heap, const void *payload);
/* Open the next innermost arena; later managed allocation lands in it. */
int myl_native_region_begin(myl_native_heap *heap);
/* Free the innermost arena's chunks without walking individual allocations. */
void myl_native_region_end(myl_native_heap *heap);
/* Explicit owned storage release. Caller removes all roots/references first. */
void myl_native_heap_release(myl_native_heap *heap, void *payload);
/// Release every external resource reachable from a value in place.
void myl_native_owned_drop(myl_native_heap *heap, const myl_native_type *type, void *value);
#endif
