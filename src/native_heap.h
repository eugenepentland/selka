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
    unsigned collection_kind; /* 0 opaque, 1 list, 2 string, 3 dictionary */
    const myl_native_type *element, *key;
};
enum { MYL_NATIVE_PLAIN, MYL_NATIVE_POINTER, MYL_NATIVE_RECORD,
       MYL_NATIVE_ARRAY, MYL_NATIVE_VARIANT, MYL_NATIVE_OWNED_BUFFER, MYL_NATIVE_OWNED_POOL, MYL_NATIVE_FLOAT, MYL_NATIVE_RESOURCE };
typedef struct myl_native_root {
    struct myl_native_root *previous;
    void *address;
    const myl_native_type *type;
} myl_native_root;
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
} myl_native_heap;
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
void myl_native_heap_collect(myl_native_heap *heap);
/* Explicit owned storage release. Caller removes all roots/references first. */
void myl_native_heap_release(myl_native_heap *heap, void *payload);
#endif
