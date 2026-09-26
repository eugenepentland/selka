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
/* One reference slot of a descriptor's flat scan plan (GC-SCAN-PLAN-2): the
 * byte offset of a pointer inside one element and, when that pointer is a
 * union case's payload, the offset of the union's 32-bit tag and the tag value
 * under which the slot holds a reference. `tag_offset` is
 * MYL_NATIVE_SCAN_ALWAYS for a slot that always holds one. */
typedef struct {
    uint32_t offset, tag_offset, tag;
} myl_native_scan_entry;
#define MYL_NATIVE_SCAN_ALWAYS UINT32_MAX
/* The most slots a generated plan holds. A shape with more, or with a union
 * inside a union, has no plan and keeps the collector's recursive walk. */
#define MYL_NATIVE_SCAN_ENTRIES 8
struct myl_native_type {
    size_t size;
    size_t alignment;
    const myl_native_field *fields;
    size_t field_count;
    size_t count;
    size_t stride;
    unsigned kind;
    /* 0 opaque, 1 list, 2 string, 3 dictionary, 4 bytes, 5 box: the pointer to
     * the immutable one-field record a recursive value's boxed field or case
     * lives in, whose body descriptor `element` names (RECURSIVE-VALUES-2). */
    unsigned collection_kind;
    const myl_native_type *element, *key;
    /* GC-only field view. Runtime-built descriptors may leave trace_mode zero,
     * which preserves the legacy walk through `fields`. Generated descriptors
     * use NONE for pointer-free values and FIELDS for a filtered table containing
     * only children that can reach managed storage. Other descriptor consumers
     * continue to use the complete field table above. */
    const myl_native_field *trace_fields;
    size_t trace_field_count;
    unsigned trace_mode;
    /* Nonzero only for a generated `class` body: every store into an allocated
     * object of this descriptor after its constructor filled it runs the
     * generational store barrier (`myl_native_heap_remember`), so an old body is
     * not rescanned by a minor collection unless a store reached it. Zero keeps
     * the conservative rule every runtime descriptor relies on: an old object's
     * references are rescanned by every minor collection. */
    unsigned cell;
    /* The flat scan plan (GC-SCAN-PLAN-2): the `scan_count` reference slots at
     * `scan` are exactly the pointers the recursive walk of `fields` (or
     * `trace_fields`) reaches in one element, in the order it reaches them, so
     * the collector traces an element with one loop and no lookup. The compiler
     * emits a plan with every generated aggregate descriptor that has one, the
     * runtime spells its own record descriptors' plans, and a dictionary builds
     * its entries' plan inside itself when it is created. A plan is never
     * written after its descriptor is built, so a descriptor in read-only
     * storage stays valid. NULL keeps the recursive walk; a pointer descriptor
     * needs no plan. */
    const myl_native_scan_entry *scan;
    size_t scan_count;
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
 * Word 0 is the mark word: bit 0 says the object is old — for a large object
 * (`MYL_NATIVE_OBJECT_LARGE`) it is the collector's mark itself, for any other
 * object the mark lives in its segment's bitmap and bit 0 is the flag the
 * generational store barrier tests — bit 1 marks storage that lives outside
 * the heap (a frozen `str`/`bytes` literal), which the collector never queues,
 * re-traces, frees or bulk-releases, and the bits above hold the element count
 * (below bits 60 and 61, the copy-on-write flags, bit 62, the arena flag, and
 * bit 63, the large flag). A free slot of a
 * segment without mark bits is never marked: the first slot of a hole holds a
 * `myl_native_hole` whose first word is an aligned address, and every other
 * free slot keeps its last occupant's unmarked word. A free slot of a bitmap
 * segment may keep a stale bit 0, which nothing reads: its mark bit is clear.
 * The count lives in the header rather than in the segment because precise
 * tracing needs it for any payload address, including
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
/* The mark word of an arena allocation: this flag, the owning arena depth in
 * the bits from MYL_NATIVE_ARENA_REGION_SHIFT up to the flag, and the element
 * count between the two flag bits and the depth. The collector never sets the
 * mark or immortal bit on one, and a tracing-heap count is kept below the flag,
 * so the flag alone tells an arena payload from every other managed payload. */
#define MYL_NATIVE_OBJECT_ARENA (((uintptr_t)1) << 62)
#define MYL_NATIVE_ARENA_REGION_SHIFT 40
/* The copy-on-write flags of a list, byte buffer, dictionary or set header
 * (COW-SHARED-1, COW-PIN-1), below the arena flag in both mark-word layouts.
 * SHARED says a value transfer left a second holder of this payload, so the
 * first write through any holder copies it first (`native_cow.h`); it is
 * sticky, because nothing counts the holders. PINNED says a caller lent this
 * payload to a `mut` parameter, whose slot the callee cannot redirect, so a
 * transfer copies it at once instead of setting SHARED. The collector never
 * reads, sets or clears either flag: it keeps both through every mark, sweep
 * and growth, and a fresh allocation starts with both clear. */
#define MYL_NATIVE_OBJECT_SHARED (((uintptr_t)1) << 61)
#define MYL_NATIVE_OBJECT_PINNED (((uintptr_t)1) << 60)
#define MYL_NATIVE_OBJECT_COW (MYL_NATIVE_OBJECT_SHARED | MYL_NATIVE_OBJECT_PINNED)
/* Largest element count a tracing-heap mark word holds below the
 * copy-on-write flags. */
#define MYL_NATIVE_OBJECT_COUNT_MAX ((size_t)((MYL_NATIVE_OBJECT_PINNED >> MYL_NATIVE_OBJECT_COUNT_SHIFT) - 1))
/* The count bits of a tracing-heap mark word, in place. */
#define MYL_NATIVE_OBJECT_COUNT_BITS ((uintptr_t)MYL_NATIVE_OBJECT_COUNT_MAX << MYL_NATIVE_OBJECT_COUNT_SHIFT)
/* Largest element count and arena depth an arena mark word holds. The depth
 * sits below the copy-on-write flags; its bound is far beyond any nesting a
 * native stack can reach. */
#define MYL_NATIVE_ARENA_COUNT_MAX ((((size_t)1) << (MYL_NATIVE_ARENA_REGION_SHIFT - MYL_NATIVE_OBJECT_COUNT_SHIFT)) - 1)
#define MYL_NATIVE_ARENA_REGION_MAX ((unsigned)((MYL_NATIVE_OBJECT_PINNED >> MYL_NATIVE_ARENA_REGION_SHIFT) - 1))
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
/* The size classes generated code allocates from inline: the first twelve,
 * strides 16 to 256. Their strides are a compile-time contract with
 * `inline_class_strides` in src/qbe_alloc.zig, which a Zig test checks against
 * the table in native_heap.c. */
#define MYL_NATIVE_INLINE_CLASSES 12
/* A size-classed segment is one block of this many bytes aligned to its own
 * size, so any object in it finds its segment — and its mark bit — by masking
 * its address. One mark bit covers each 16-byte granule of the block. */
#define MYL_NATIVE_SEGMENT_BYTES ((size_t)1 << 16)
#define MYL_NATIVE_SEGMENT_MARK_WORDS (MYL_NATIVE_SEGMENT_BYTES / 16 / 64)
/* Entries of the heap's pool-region lookup cache (a power of two). */
#define MYL_NATIVE_POOL_HITS 128
/* The mark word bit that tells an object with a one-slot segment of its own
 * (an oversized object) from a size-classed one: an oversized object keeps its
 * collector mark in its header's bit 0, a size-classed object in its segment's
 * mark bits. Bit 63 is above any element count a tracing-heap object holds. */
#define MYL_NATIVE_OBJECT_LARGE (((uintptr_t)1) << 63)
/* One size-classed slab of tracing-heap storage: `slots` fixed-stride object
 * slots at `data`, zero-filled by the host on first use. `used` counts the
 * slots the segment has handed out as fresh storage — its tail past `used` has
 * never held an object — and `class_index` names the stride's class
 * (`MYL_NATIVE_CLASS_COUNT` for a one-slot oversized segment). */
typedef struct myl_native_segment {
    struct myl_native_segment *next;
    size_t stride, slots, used, class_index;
    /* The first hole the last sweep found: a run of consecutive free slots
     * inside the used prefix, whose first slot holds a `myl_native_hole`
     * naming the run's end and the next hole. `live` counts the marked slots
     * that sweep kept. `available` links the segment into its class's list of
     * segments with holes nobody has started on. A segment is dirty from the
     * moment it hands out storage (or an object of it is released) until it is
     * swept again, so a minor collection sweeps exactly the segments that can
     * hold a young object. */
    unsigned char *holes;
    size_t live;
    struct myl_native_segment *available;
    unsigned char dirty, listed;
    /* Set when the segment's slots are not zero-filled: a spare segment taken
     * back into service by another class holds its previous objects' bytes,
     * so its never-used tail is not fresh storage and every slot handed out
     * from it is cleared the way a reused hole's slot is. */
    unsigned char stale;
    /* The collector's mark bits of a size-classed segment, one per 16-byte
     * granule of the segment's aligned block, set at an object's first
     * granule. An oversized segment keeps its one object's mark in the
     * object's header instead and leaves this unused. */
    uint64_t marks[MYL_NATIVE_SEGMENT_MARK_WORDS];
    /* Aging bits (`GC-AGING-1`), one per granule like `marks`. Outside a
     * collection a set bit names a young object that survived exactly one
     * minor collection without being promoted: its mark bit is clear again,
     * so the next minor collection traces it like any young object and
     * promotes it if it is still reachable. While a collection marks, a set
     * bit on a marked object means "kept young by this collection". Only a
     * dirty segment carries set bits; its next sweep recomputes them. */
    uint64_t ages[MYL_NATIVE_SEGMENT_MARK_WORDS];
    max_align_t payload_alignment;
    unsigned char data[];
} myl_native_segment;
/* The header a sweep writes into the first slot of a hole. `end` is the
 * address just past the run, 16-aligned, so the word reads as an unmarked mark
 * word to anything that inspects the slot; every other slot of the run keeps
 * whatever its last occupant left, which is never marked either. */
typedef struct {
    unsigned char *end, *next;
} myl_native_hole;
/* A run of free slots one allocator consumes by bumping `cursor` a stride at
 * a time until it reaches `limit`; both are NULL when the window is empty. */
typedef struct {
    unsigned char *cursor, *limit;
} myl_native_window;
/* One size class's allocation state. Storage comes from holes — first the
 * `source` segment's, then each `available` segment's, then the never-used
 * tail of the bump segment `current` or a fresh segment — and is consumed
 * through two windows: generated code's inline window (in
 * `myl_native_heap.inline_windows`, taken from `inline_segment`) and the
 * runtime path's own `runtime` window. `runtime_fresh` says the runtime
 * window is never-used, still zero-filled storage. */
typedef struct {
    myl_native_segment *current, *source, *available, *inline_segment;
    myl_native_window runtime;
    int runtime_fresh;
} myl_native_class;
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
/* One growable array of object headers the collector owns. */
typedef struct {
    myl_native_object **items;
    size_t length, capacity;
} myl_native_object_stack;
/* The sticky-mark generational state. After a collection every surviving
 * object keeps its mark bit and is old; an allocation is young (unmarked). A
 * minor collection marks only young objects: a reference to an old object is
 * not followed, because an old object's references are already old — except
 * for the two sets it rescans. `rescan` lists every old size-classed object
 * whose descriptor is traced and not a `cell`, appended as each is marked and
 * reset by a full collection: those may gain a young reference with no
 * barrier (runtime collections, list storage); old oversized ones are found
 * on the segment list instead.
 * `remembered` lists the old `cell` bodies a store has reached since the last
 * collection; the barrier clears such a body's mark bit, so a minor collection
 * marks it and traces it like a young object. A full collection clears every
 * mark first and reclaims old garbage too. */
enum { MYL_NATIVE_AGING_OFF, MYL_NATIVE_AGING_KEEP, MYL_NATIVE_AGING_PROMOTE };
typedef struct {
    myl_native_object_stack rescan, remembered;
    /* Old-generation bytes (`old_bytes`) at which the next collection is a
     * full one. */
    size_t full_threshold;
    /* Set when a set above could not grow or a collection was abandoned, so
     * the next collection must be full to stay sound. */
    int force_full;
    /* Collection-local state of a minor collection's aging (`GC-AGING-1`):
     * `aging` says how a young object this collection reaches is treated —
     * MYL_NATIVE_AGING_OFF in a full collection, where no age bit is set;
     * MYL_NATIVE_AGING_KEEP while a minor collection marks from roots and
     * young objects, where a first survivor is kept young; and
     * MYL_NATIVE_AGING_PROMOTE while it marks from old objects, where every
     * survivor is promoted at once and its age bit cleared. `young_edge`
     * records that the object being scanned references an object that stays
     * young, which obliges a promoted `cell` body to be remembered. */
    unsigned char aging, young_edge;
    size_t minor_collections, full_collections;
    /* Tracing-heap bytes the last collection kept: the old generation,
     * including garbage a minor collection cannot reclaim. */
    size_t old_bytes;
    /* Tracing-heap bytes the last collection kept young (aged, not promoted);
     * part of the live bytes, not of `old_bytes`. */
    size_t young_bytes;
} myl_native_generations;
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
    /* The chunks of every open arena, one list per depth (`ARENA-CHUNKS-1`):
     * `arena_chunks[d]` lists depth d's chunks newest first, so its head is
     * the chunk that depth allocates from and closing the scope frees exactly
     * that list. Entries at and above `arena_depths` are empty; the array
     * holds `arena_depth_capacity` entries and grows on demand. Appended
     * fields preserve generated code's fixed root-chain offset. */
    myl_native_arena_chunk **arena_chunks;
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
    /* Generated code's inline allocation windows, one per inline size class,
     * at the frozen offset `MYL_NATIVE_HEAP_INLINE_OFFSET`. Every slot left in
     * one is prepaid: already charged to `bytes`, `objects_live` and the
     * collection trigger when `myl_native_heap_alloc_small` opened the window,
     * so the inline path only bumps the cursor and writes the header. A
     * collection empties every window and recounts what is live, which
     * discharges the slots nobody took. The windows are empty whenever an arena
     * is open, under `--gc-stress` and while an escape copy suspends
     * collection, so every such allocation takes the runtime path. */
    myl_native_window inline_windows[MYL_NATIVE_INLINE_CLASSES];
    /* Generated code's arena window, at the frozen offset
     * `MYL_NATIVE_HEAP_ARENA_OFFSET`: the free tail of the innermost open
     * arena's current chunk, and the mark word of a one-element allocation at
     * that depth. A class body constructed inside an arena is bumped out of it
     * with no runtime call; the chunk is zero-filled, so its payload needs no
     * clearing. The window is open only between arena allocations the runtime
     * made at the innermost depth, and every runtime operation on arena chunks
     * first folds its progress back into the chunk and closes it
     * (`myl_native_arena_sync`). */
    myl_native_window arena_window;
    uintptr_t arena_mark;
    myl_native_class classes[MYL_NATIVE_CLASS_COUNT];
    myl_native_generations generations;
    /* Tracing-heap objects charged to `objects_live`, so a collection that
     * recounts them can correct that total without touching arena counts. */
    size_t gc_objects;
    /* The arena chunk `arena_window` belongs to, or NULL when it is closed. */
    myl_native_arena_chunk *arena_window_chunk;
    /* Size-classed segments are carved from aligned host mappings of
     * `MYL_NATIVE_SEGMENT_POOL` segments, each one 2 MiB-aligned private
     * anonymous mapping that reads as zeros until written: the unused rest of
     * the newest one runs from `pool_next` to `pool_end`, and every mapping is
     * listed in `pools` so destroying the heap unmaps it. */
    unsigned char *pool_next, *pool_end;
    void **pools;
    size_t pool_count, pool_capacity;
    /* Spare segments (`GC-SPARE-1`): size-classed blocks a sweep found with
     * no object in them, unlinked from their class and from `segments`, and
     * handed to the next class that needs a fresh segment, whatever its
     * stride. A spare keeps its pages, so it holds stale bytes. */
    myl_native_segment **spare;
    size_t spare_length, spare_capacity;
    /* See `arena_chunks`. */
    size_t arena_depths, arena_depth_capacity;
    /* The 2 MiB regions (address >> 21) of every pool mapping, in an
     * open-addressed table of `pool_set_capacity` slots (a power of two, zero
     * meaning empty), so the collector can tell a size-classed object from its
     * address alone (`GC-POOLSET-1`). */
    uintptr_t *pool_set;
    size_t pool_set_capacity;
    /* A direct-mapped cache of pool regions lookups found, indexed by the
     * region's low bits; zero is empty. A few regions hold most references. */
    uintptr_t pool_hits[MYL_NATIVE_POOL_HITS];
} myl_native_heap;
/* Frozen byte offsets of `inline_windows` and `arena_window`, read by generated
 * inline allocation; src/native_heap.c asserts them and src/qbe_alloc.zig
 * mirrors them. */
#define MYL_NATIVE_HEAP_INLINE_OFFSET 1280
#define MYL_NATIVE_HEAP_ARENA_OFFSET 1472
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
/* Flatten `type` into the reference slots the collector's recursive walk
 * reaches in one element, in the order it reaches them, writing at most
 * `capacity` of them to `entries`. Returns 1 and stores the slot count, or 0
 * when the shape needs more slots or holds a union inside a union. It is the
 * plan a descriptor's `scan` must spell (GC-SCAN-PLAN-2). */
int myl_native_scan_flatten(const myl_native_type *type, myl_native_scan_entry *entries, size_t capacity, size_t *count);
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
/* Run one full collection: every unreachable tracing-heap object, young or
 * old, is reclaimed. */
void myl_native_heap_collect(myl_native_heap *heap);
/* Allocate one zeroed element of `element`, whose stride is in inline size
 * class `class_index`, and open that class's inline window on the storage
 * after it: prepaid slots for generated code to bump through. Collection and
 * the budget refusal happen exactly where `myl_native_heap_alloc` would put
 * them. Inside an arena, under `--gc-stress` and during an escape copy it is
 * `myl_native_heap_alloc` and opens no window. The descriptor's class is
 * checked against `class_index`, and a mismatch — a compiler defect — aborts
 * the process rather than handing out a slot of the wrong stride. */
void *myl_native_heap_alloc_small(myl_native_heap *heap, const myl_native_type *element, size_t class_index);
/* Close every inline window, discharging its prepaid slots and giving them
 * back to their segment as a hole, so `bytes` counts only allocations
 * generated code received. */
void myl_native_heap_settle(myl_native_heap *heap);
/* The generational store barrier's slow half: an old `cell` body is about to
 * receive a store, so clear its mark bit and remember it for the next minor
 * collection. A body that is already young or remembered is left alone. */
void myl_native_heap_remember(myl_native_heap *heap, void *payload);
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
