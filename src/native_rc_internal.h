#ifndef MYLANG_NATIVE_RC_INTERNAL_H
#define MYLANG_NATIVE_RC_INTERNAL_H
#include "native_rc.h"
/* Private state: generated code sees only the frozen object/common prefixes. */
typedef struct {
    const myl_rc_shape *shape;
    unsigned char *address;
    size_t cursor;
} myl_rc_frame;
typedef struct {
    const myl_rc_shape *source;
    myl_rc_shape shape;
    size_t depth;
} myl_rc_shape_entry;
typedef struct myl_rc_batch {
    struct myl_rc_batch *next;
    const myl_rc_module *module;
    myl_rc_shape_entry *shapes;
    myl_rc_descriptor *descriptors;
    struct { size_t shapes, descriptors; } count;
    struct { size_t *slots; size_t capacity; } lookup;
    size_t bytes;
} myl_rc_batch;
struct myl_rc_state {
    struct { myl_rc_allocator hooks; void *context; } allocator;
    struct { myl_rc_batch *batches; size_t bytes; } metadata;
    struct { myl_rc_frame *frames; size_t capacity, depth; } walk;
    struct { myl_rc_object *head; int active; } dead;
    myl_rc_scope *scopes;
    myl_rc_status failure;
};
void myl_rc_invariant(int);
void *myl_rc_meta_alloc(myl_native_heap *, size_t);
void myl_rc_meta_free(myl_native_heap *, void *, size_t);
int myl_rc_size_add(size_t, size_t, size_t *);
int myl_rc_size_mul(size_t, size_t, size_t *);
int myl_rc_is_counted(const void *);
void myl_rc_enqueue(myl_native_heap *, myl_rc_object *);
#endif
