#ifndef MYLANG_NATIVE_POOL_H
#define MYLANG_NATIVE_POOL_H
#include "native_owned.h"
typedef struct { uint64_t pool,index,generation; } myl_native_pool_handle;
typedef struct { uint64_t generation; size_t next; int live; } myl_native_pool_entry;
typedef struct {
    size_t length,capacity;
    uint64_t identity;
    const myl_native_type *element;
    void *storage;
    myl_native_pool_entry *entries;
    size_t issued,free_head;
    myl_native_region *region;
    myl_native_drop_link work;
} myl_native_pool;
/* Acquisition: 1 Capacity, 2 IdentityExhausted, -1 OutOfMemory.
 * Operations: 1 Stale, 2 Foreign, 3 Full; insert/replace consume values. */
int myl_native_pool_new(myl_native_heap *,const myl_native_type *,int64_t,myl_native_pool **);
int myl_native_pool_insert(myl_native_heap *,myl_native_pool *,void *,myl_native_pool_handle *);
int myl_native_pool_read(myl_native_pool *,const myl_native_pool_handle *,void *);
int myl_native_pool_replace(myl_native_heap *,myl_native_pool *,const myl_native_pool_handle *,void *);
int myl_native_pool_remove(myl_native_heap *,myl_native_pool *,const myl_native_pool_handle *);
void myl_native_pool_clear(myl_native_heap *,myl_native_pool *);
void myl_native_pool_drop(myl_native_heap *,myl_native_pool *);
#endif
