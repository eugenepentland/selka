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
/* One managed allocation's header, laid out immediately before its payload so
 * the collector reaches it as `(myl_native_object *)payload - 1`. `marked` is a
 * collector write. `immortal` marks storage that lives outside the heap, such as
 * a frozen `str`/`bytes` literal: the collector never frees it and never
 * re-traces it. `region` is the arena depth that owns the payload; a literal
 * keeps 0 so arena ownership checks treat it as ordinary heap-owned storage that
 * any scope may reference. `payload_alignment` forces the header's size to a
 * multiple of `max_align_t` so the payload stays suitably aligned. */
struct myl_native_object {
    struct myl_native_object *next, *pending;
    const myl_native_type *element;
    size_t count, bytes;
    unsigned marked, immortal, region;
    max_align_t payload_alignment;
};
typedef struct myl_native_object myl_native_object;
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
/* Bulk arena counters, reported separately from tracing reclamation. */
typedef struct { uint64_t scopes, released, escaped; } myl_native_arena_statistics;
typedef struct {
    myl_native_object *objects;
    myl_native_object *pending;
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
 * is charged, linked and freed as one object whose payload holds no traced
 * pointer, so the collector never walks it; a reference the caller stores into
 * the data must point at another heap object. Returns NULL on overflow or
 * budget exhaustion. */
void *myl_native_heap_alloc_block(myl_native_heap *heap, size_t prefix, size_t extra);
void myl_native_heap_collect(myl_native_heap *heap);
/* Allocate at an explicit arena depth so collection backing joins its owner
 * rather than the innermost open arena. */
void *myl_native_heap_alloc_at(myl_native_heap *heap,
                               const myl_native_type *element, size_t count, unsigned region);
/* Arena depth owning one managed payload; 0 for the ordinary tracing heap. */
unsigned myl_native_object_region(const void *payload);
/* Open the next innermost arena; later managed allocation lands in it. */
void myl_native_region_begin(myl_native_heap *heap);
/* Free every object allocated at the innermost arena depth and leave it. */
void myl_native_region_end(myl_native_heap *heap);
/* Explicit owned storage release. Caller removes all roots/references first. */
void myl_native_heap_release(myl_native_heap *heap, void *payload);
/// Release every external resource reachable from a value in place.
void myl_native_owned_drop(myl_native_heap *heap, const myl_native_type *type, void *value);
#endif
