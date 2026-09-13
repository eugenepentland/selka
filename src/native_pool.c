#include "native_pool.h"
#include <string.h>
static const myl_native_type pointer_type={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER};
static const myl_native_type entry_type={.size=sizeof(myl_native_pool_entry),.alignment=_Alignof(myl_native_pool_entry),.kind=MYL_NATIVE_PLAIN};
static const myl_native_field fields[]={
    {.offset=offsetof(myl_native_pool,storage),.type=&pointer_type},
    {.offset=offsetof(myl_native_pool,entries),.type=&pointer_type}
};
static const myl_native_type pool_type={.size=sizeof(myl_native_pool),.alignment=_Alignof(myl_native_pool),.kind=MYL_NATIVE_RECORD,.fields=fields,.field_count=2};
static void *slot(myl_native_pool *pool,size_t i) { return (unsigned char *)pool->storage+i*pool->element->size; }
int myl_native_pool_new(myl_native_heap *heap,const myl_native_type *element,int64_t capacity,myl_native_pool **output) {
    *output=NULL;
    if (capacity<0 || capacity>4096 || heap->pool_owners>=64 || (uint64_t)capacity>16384-heap->pool_slots) return 1;
    if (heap->next_pool_identity==UINT64_MAX) return 2;
    myl_native_pool *pool=myl_native_heap_alloc(heap,&pool_type,1);
    if (!pool) return -1;
    myl_native_root root;
    myl_native_root_push(heap,&root,&pool,&pointer_type);
    pool->element=element;
    pool->storage=myl_native_heap_alloc(heap,element,(size_t)capacity);
    if (pool->storage) pool->entries=myl_native_heap_alloc(heap,&entry_type,(size_t)capacity);
    myl_native_root_pop(heap,&root);
    if (!pool->storage || !pool->entries) {
        myl_native_heap_release(heap,pool->storage);
        myl_native_heap_release(heap,pool);
        return -1;
    }
    pool->capacity=(size_t)capacity;
    pool->identity=heap->next_pool_identity++;
    pool->free_head=SIZE_MAX;
    heap->pool_owners++;
    heap->pool_slots+=(size_t)capacity;
    *output=pool;
    return 0;
}
static int index_for(myl_native_pool *pool,const myl_native_pool_handle *id,size_t *index) {
    if (id->pool!=pool->identity) return 2;
    if (id->index>=pool->issued) return 1;
    *index=(size_t)id->index;
    const myl_native_pool_entry *entry=&pool->entries[*index];
    return !entry->live || id->generation!=entry->generation ? 1:0;
}
int myl_native_pool_insert(myl_native_heap *heap,myl_native_pool *pool,void *value,myl_native_pool_handle *output) {
    if (pool->free_head==SIZE_MAX && pool->issued==pool->capacity) {
        myl_native_owned_drop(heap,pool->element,value);return 3;
    }
    size_t index;
    if (pool->free_head==SIZE_MAX) { index=pool->issued++;pool->entries[index].generation=1; }
    else { index=pool->free_head;pool->free_head=pool->entries[index].next; }
    myl_native_pool_entry *entry=&pool->entries[index];
    entry->live=1;entry->next=SIZE_MAX;
    memcpy(slot(pool,index),value,pool->element->size);
    memset(value,0,pool->element->size);
    pool->length++;
    *output=(myl_native_pool_handle){pool->identity,index,entry->generation};
    return 0;
}
int myl_native_pool_read(myl_native_pool *pool,const myl_native_pool_handle *id,void *output) {
    size_t index=0;int status=index_for(pool,id,&index);
    if (!status) memcpy(output,slot(pool,index),pool->element->size);
    return status;
}
int myl_native_pool_replace(myl_native_heap *heap,myl_native_pool *pool,const myl_native_pool_handle *id,void *value) {
    size_t index=0;int status=index_for(pool,id,&index);
    if (!status) {
        myl_native_owned_drop(heap,pool->element,slot(pool,index));
        memcpy(slot(pool,index),value,pool->element->size);
        memset(value,0,pool->element->size);
    } else myl_native_owned_drop(heap,pool->element,value);
    return status;
}
static void remove_index(myl_native_heap *heap,myl_native_pool *pool,size_t index) {
    myl_native_pool_entry *entry=&pool->entries[index];
    myl_native_owned_drop(heap,pool->element,slot(pool,index));
    memset(slot(pool,index),0,pool->element->size);
    entry->live=0;pool->length--;
    if (entry->generation!=UINT64_MAX) {
        entry->generation++;entry->next=pool->free_head;pool->free_head=index;
    }
}
int myl_native_pool_remove(myl_native_heap *heap,myl_native_pool *pool,const myl_native_pool_handle *id) {
    size_t index=0;int status=index_for(pool,id,&index);
    if (!status) remove_index(heap,pool,index);
    return status;
}
void myl_native_pool_clear(myl_native_heap *heap,myl_native_pool *pool) {
    for (size_t i=pool->issued;i;i--) if (pool->entries[i-1].live) remove_index(heap,pool,i-1);
}
void myl_native_pool_drop(myl_native_heap *heap,myl_native_pool *pool) {
    myl_native_pool_clear(heap,pool);
    heap->pool_owners--;heap->pool_slots-=pool->capacity;
    if (pool->region) pool->region->users--;
    myl_native_heap_release(heap,pool->entries);
    myl_native_heap_release(heap,pool->storage);
    myl_native_heap_release(heap,pool);
}
