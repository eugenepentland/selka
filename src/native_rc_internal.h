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
typedef struct myl_rc_batch {
    struct myl_rc_batch *next;
    const myl_rc_module *module;
    myl_rc_shape_entry *shapes;
    myl_rc_descriptor *descriptors;
    struct { size_t shapes, descriptors; } count;
    size_t bytes;
} myl_rc_batch;
typedef struct {
    const void *key, *value;
    size_t depth;
    size_t inline_depth;
    unsigned kind;
} myl_rc_index_entry;
struct myl_rc_state {
    struct { myl_rc_allocator hooks; void *context; } allocator;
    struct {
        myl_rc_batch *batches;
        size_t bytes;
        struct { myl_rc_index_entry *entries; size_t count, capacity; } index;
    } metadata;
    struct { myl_rc_frame *frames; size_t capacity, depth; } walk;
    struct { myl_rc_object *head; int active; } dead;
    myl_rc_scope *scopes;
    myl_rc_status failure;
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
    myl_rc_counters stats;
#endif
};
void myl_rc_invariant(int);
void *myl_rc_meta_alloc(myl_native_heap *, size_t);
void myl_rc_meta_free(myl_native_heap *, void *, size_t);
int myl_rc_size_add(size_t, size_t, size_t *);
int myl_rc_size_mul(size_t, size_t, size_t *);
int myl_rc_is_counted(const void *);
size_t myl_rc_shape_depth(const myl_native_heap *, const myl_rc_shape *);
void myl_rc_scopes_close_region(myl_native_heap *, unsigned);
myl_rc_status myl_rc_scope_extend(myl_rc_scope *, void *boundary, myl_rc_status (*)(myl_rc_scope *, void *));
void myl_rc_enqueue(myl_native_heap *, myl_rc_object *);
#endif
