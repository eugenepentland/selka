#include "native_owned.h"
#include "native_pool.h"
#include <string.h>
static const myl_native_type pointer_type = {.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static unsigned char *slot(myl_native_owned_buffer *buffer, size_t index) {
    return (unsigned char *)buffer->storage + index * buffer->element->size;
}
static void schedule(myl_native_drop_link **work,const myl_native_type *type,void *value) {
    myl_native_drop_link *link=NULL;
    void *owner=NULL;
    if (type->kind==MYL_NATIVE_OWNED_BUFFER || type->kind==MYL_NATIVE_OWNED_POOL || type->kind==MYL_NATIVE_RESOURCE) {
        memcpy(&owner,value,sizeof owner);
        memset(value,0,sizeof owner);
        if (!owner) return;
        if (type->kind==MYL_NATIVE_OWNED_BUFFER) link=&((myl_native_owned_buffer *)owner)->work;
        else if (type->kind==MYL_NATIVE_OWNED_POOL) link=&((myl_native_pool *)owner)->work;
        else link=&((myl_native_resource *)owner)->work;
        *link=(myl_native_drop_link){.next=*work,.owner=owner,.kind=type->kind};
        *work=link;
    } else if (type->kind==MYL_NATIVE_ARRAY) {
        for (size_t i=0;i<type->count;i++) schedule(work,type->fields[0].type,(unsigned char *)value+i*type->stride);
    } else if (type->kind==MYL_NATIVE_RECORD || type->kind==MYL_NATIVE_VARIANT) {
        uint32_t tag=0;
        if (type->kind==MYL_NATIVE_VARIANT) memcpy(&tag,value,sizeof tag);
        for (size_t i=0;i<type->field_count;i++) {
            const myl_native_field *field=&type->fields[i];
            if (type->kind==MYL_NATIVE_RECORD || field->tag==tag) schedule(work,field->type,(unsigned char *)value+field->offset);
        }
    }
}
void myl_native_owned_drop(myl_native_heap *heap,const myl_native_type *type,void *value) {
    myl_native_drop_link *work=NULL;
    schedule(&work,type,value);
    while (work) {
        void *owner=work->owner;
        unsigned kind=work->kind;
        work=work->next;
        if (kind==MYL_NATIVE_OWNED_BUFFER) {
            myl_native_owned_buffer *buffer=owner;
            for (size_t i=0;i<buffer->length;i++) schedule(&work,buffer->element,slot(buffer,i));
            heap->owned_capacity-=buffer->capacity;
            if (buffer->region) buffer->region->users--;
            myl_native_heap_release(heap,buffer->storage);
            myl_native_heap_release(heap,buffer);
        } else if (kind==MYL_NATIVE_OWNED_POOL) {
            myl_native_pool *pool=owner;
            for (size_t i=0;i<pool->issued;i++) if (pool->entries[i].live)
                schedule(&work,pool->element,(unsigned char *)pool->storage+i*pool->element->size);
            heap->pool_owners--;heap->pool_slots-=pool->capacity;
            if (pool->region) pool->region->users--;
            myl_native_heap_release(heap,pool->entries);
            myl_native_heap_release(heap,pool->storage);
            myl_native_heap_release(heap,pool);
        } else ((myl_native_resource *)owner)->drop(owner);
    }
}

int myl_native_owned_new(myl_native_heap *heap, const myl_native_type *element, int64_t capacity, size_t limit, myl_native_owned_buffer **output) {
    *output=NULL;
    if (capacity<0 || heap->owned_capacity>limit || (uint64_t)capacity>limit-heap->owned_capacity) return 1;
    myl_native_owned_buffer *buffer=myl_native_list_new(heap,element,(size_t)capacity);
    if (!buffer) return -1;
    heap->owned_capacity+=(size_t)capacity;
    *output=buffer;
    return 0;
}
int myl_native_owned_append(myl_native_heap *heap, myl_native_owned_buffer *buffer, void *value) {
    if (buffer->length==buffer->capacity) { myl_native_owned_drop(heap,buffer->element,value);return 2; }
    memcpy(slot(buffer,buffer->length++),value,buffer->element->size);
    memset(value,0,buffer->element->size);
    return 0;
}
int myl_native_owned_set(myl_native_heap *heap, myl_native_owned_buffer *buffer, int64_t index, void *value) {
    if (index<0 || (uint64_t)index>=buffer->length) { myl_native_owned_drop(heap,buffer->element,value);return 3; }
    myl_native_owned_drop(heap,buffer->element,slot(buffer,(size_t)index));
    memcpy(slot(buffer,(size_t)index),value,buffer->element->size);
    memset(value,0,buffer->element->size);
    return 0;
}
int myl_native_owned_take(myl_native_owned_buffer *buffer, int64_t index, void *output) {
    if (index<0 || (uint64_t)index>=buffer->length) return 3;
    memcpy(output,slot(buffer,(size_t)index),buffer->element->size);
    --buffer->length;
    if ((size_t)index!=buffer->length) memcpy(slot(buffer,(size_t)index),slot(buffer,buffer->length),buffer->element->size);
    memset(slot(buffer,buffer->length),0,buffer->element->size);
    return 0;
}
int myl_native_owned_truncate(myl_native_heap *heap, myl_native_owned_buffer *buffer, int64_t length) {
    if (length<0 || (uint64_t)length>buffer->length) return 3;
    while (buffer->length>(size_t)length) {
        void *value=slot(buffer,--buffer->length);
        myl_native_owned_drop(heap,buffer->element,value);
        memset(value,0,buffer->element->size);
    }
    return 0;
}
int myl_native_owned_resize(myl_native_heap *heap, myl_native_owned_buffer *buffer, int64_t length, void *fill) {
    if (length<0) { myl_native_owned_drop(heap,buffer->element,fill);return 3; }
    if ((uint64_t)length>buffer->capacity) { myl_native_owned_drop(heap,buffer->element,fill);return 2; }
    if ((size_t)length<buffer->length) (void)myl_native_owned_truncate(heap,buffer,length);
    /* Frontend permits resize only for copyable element values. */
    while (buffer->length<(size_t)length) memcpy(slot(buffer,buffer->length++),fill,buffer->element->size);
    myl_native_owned_drop(heap,buffer->element,fill);
    return 0;
}
int myl_native_owned_reserve(myl_native_heap *heap, myl_native_owned_buffer *buffer, int64_t capacity, size_t limit) {
    if (capacity<0 || (uint64_t)capacity>limit) return 1;
    if ((size_t)capacity<=buffer->capacity) return 0;
    size_t increase=(size_t)capacity-buffer->capacity;
    if (heap->owned_capacity>limit || increase>limit-heap->owned_capacity) return 1;
    myl_native_root root;
    myl_native_root_push(heap,&root,&buffer,&pointer_type);
    void *storage=myl_native_heap_alloc(heap,buffer->element,(size_t)capacity);
    myl_native_root_pop(heap,&root);
    if (!storage) return -1;
    if (buffer->length) memcpy(storage,buffer->storage,buffer->length*buffer->element->size);
    myl_native_heap_release(heap,buffer->storage);
    buffer->storage=storage;
    buffer->capacity=(size_t)capacity;
    heap->owned_capacity+=increase;
    return 0;
}
