#define _POSIX_C_SOURCE 200809L
#include "native_rc_alloc.h"
#include "native_arena.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>

/* Slab addresses recover their metadata with one mask. Large reservations put
 * their metadata before (not inside) the frozen 32-byte RC object prefix. */
#define RC_SLAB_BYTES ((size_t)65536)
#define RC_SLAB_CLASSES 32
typedef struct rc_slab rc_slab;
typedef struct { rc_slab *previous, *next; } rc_slab_links;
struct rc_slab {
    rc_slab_links all, available;
    size_t stride, used, live;
    void *free;
    size_t class_index;
};
typedef struct rc_large rc_large;
struct rc_large {
    rc_large *previous, *next;
    size_t charge, extent;
};
typedef struct {
    rc_slab *all, *available;
} rc_class;
typedef struct {
    rc_class classes[RC_SLAB_CLASSES];
    rc_large *large;
    size_t reserved;
} rc_storage;
static const size_t strides[RC_SLAB_CLASSES] = {
    16,32,48,64,80,96,112,128,160,192,224,256,320,384,448,512,
    640,768,896,1024,1280,1536,1792,2048,2560,3072,3584,4096,
    5120,6144,7168,8192
};
#define RC_SLAB_OFFSET ((sizeof(rc_slab) + 15) & ~(size_t)15)
_Static_assert(sizeof(rc_large) % 16 == 0, "large allocator metadata preserves alignment");
_Static_assert(sizeof(myl_rc_object) == MYL_RC_PREFIX_BYTES, "RC prefix ABI");
_Static_assert(offsetof(myl_rc_object, common) == 16, "common header ABI");
static const myl_native_type raw_type = {
    .size=1, .alignment=1, .kind=MYL_NATIVE_PLAIN, .trace_mode=MYL_NATIVE_TRACE_NONE
};
static const myl_rc_shape raw_shape = {.size=1,.kind=MYL_RC_SHAPE_NONE};
static const myl_rc_descriptor raw_descriptor = {.type=&raw_type,.shape=&raw_shape};
static const myl_rc_module raw_module = {
    .abi=MYL_RC_ABI_VERSION,.descriptors=&raw_descriptor,.descriptor_count=1
};
static rc_storage *storage_of(const myl_native_heap *heap) {
    return myl_rc_allocator_context(heap);
}
static int budget(myl_native_heap *heap, size_t bytes) {
    if (bytes>SIZE_MAX-heap->bytes || (heap->limit && (heap->bytes > heap->limit || bytes > heap->limit - heap->bytes))) {
        heap->exhausted=1;
        return 0;
    }
    return 1;
}
static void charge(myl_native_heap *heap, size_t bytes) {
    heap->bytes+=bytes;
    storage_of(heap)->reserved+=bytes;
}
static void discharge(myl_native_heap *heap, size_t bytes) {
    assert(heap->bytes>=bytes && storage_of(heap)->reserved>=bytes);
    heap->bytes-=bytes;
    storage_of(heap)->reserved-=bytes;
}
static void available_add(rc_class *class, rc_slab *slab) {
    slab->available=(rc_slab_links){.next=class->available};
    if (class->available) class->available->available.previous=slab;
    class->available=slab;
}
static void available_remove(rc_class *class, rc_slab *slab) {
    if (slab->available.previous) slab->available.previous->available.next=slab->available.next;
    else class->available=slab->available.next;
    if (slab->available.next) slab->available.next->available.previous=slab->available.previous;
    slab->available=(rc_slab_links){0};
}
static size_t slots(const rc_slab *slab) {
    return (RC_SLAB_BYTES-RC_SLAB_OFFSET)/slab->stride;
}
static void slab_free(myl_native_heap *heap, rc_slab *slab) {
    rc_class *class=&storage_of(heap)->classes[slab->class_index];
    assert(!slab->live);
    available_remove(class,slab);
    if (slab->all.previous) slab->all.previous->all.next=slab->all.next;
    else class->all=slab->all.next;
    if (slab->all.next) slab->all.next->all.previous=slab->all.previous;
    discharge(heap,RC_SLAB_BYTES);
    free(slab);
}
/* At most one empty slab is retained per class, at its available-list head.
 * Reclaiming those heads is bounded independently of the allocation count. */
static void trim_empty(myl_native_heap *heap) {
    for (size_t i=0;i<RC_SLAB_CLASSES;i++) {
        rc_slab *slab=storage_of(heap)->classes[i].available;
        if (slab && !slab->live) slab_free(heap,slab);
    }
}
static int reserve(myl_native_heap *heap, size_t bytes) {
    if (bytes<=SIZE_MAX-heap->bytes && (!heap->limit || (heap->bytes<=heap->limit && bytes<=heap->limit-heap->bytes))) return 1;
    trim_empty(heap);
    return budget(heap,bytes);
}
static rc_slab *slab_new(myl_native_heap *heap, size_t index) {
    if (!reserve(heap,RC_SLAB_BYTES)) return NULL;
    rc_slab *slab=aligned_alloc(RC_SLAB_BYTES,RC_SLAB_BYTES);
    if (!slab) { trim_empty(heap); slab=aligned_alloc(RC_SLAB_BYTES,RC_SLAB_BYTES); }
    if (!slab) return NULL;
    memset(slab,0,sizeof *slab);
    slab->stride=strides[index];
    slab->class_index=index;
    rc_class *class=&storage_of(heap)->classes[index];
    slab->all.next=class->all;
    if (class->all) class->all->all.previous=slab;
    class->all=slab;
    available_add(class,slab);
    charge(heap,RC_SLAB_BYTES);
    return slab;
}
static size_t class_for(size_t extent) {
    size_t low=0, high=RC_SLAB_CLASSES;
    while (low<high) {
        size_t middle=low+(high-low)/2;
        if (strides[middle]<extent) low=middle+1;
        else high=middle;
    }
    return low;
}
static myl_rc_object *slab_take(myl_native_heap *heap, size_t index) {
    rc_class *class=&storage_of(heap)->classes[index];
    rc_slab *slab=class->available;
    if (!slab) slab=slab_new(heap,index);
    if (!slab) return NULL;
    void *slot=slab->free;
    if (slot) memcpy(&slab->free,slot,sizeof slab->free);
    else slot=(unsigned char *)slab+RC_SLAB_OFFSET+slab->stride*slab->used++;
    slab->live++;
    if (!slab->free && slab->used==slots(slab)) available_remove(class,slab);
    memset(slot,0,slab->stride);
    return slot;
}
static myl_rc_object *large_take(myl_native_heap *heap, size_t extent) {
    if (extent>SIZE_MAX-sizeof(rc_large)) return NULL;
    size_t bytes=sizeof(rc_large)+extent;
    if (!reserve(heap,bytes)) return NULL;
    rc_large *large=calloc(1,bytes);
    if (!large) { trim_empty(heap); large=calloc(1,bytes); }
    if (!large) return NULL;
    rc_storage *storage=storage_of(heap);
    *large=(rc_large){.next=storage->large,.charge=bytes,.extent=extent};
    if (large->next) large->next->previous=large;
    storage->large=large;
    charge(heap,bytes);
    return (myl_rc_object *)(large+1);
}
static myl_rc_status allocate(myl_native_heap *heap, const myl_rc_alloc_request *request, void **out) {
    *out=NULL;
    if (request->region) {
        *out=myl_native_arena_alloc(heap,request->element,request->count,request->region);
        return *out?MYL_RC_OK:MYL_RC_ALLOCATION_REFUSED;
    }
    if (!request->element || request->element->alignment>16 ||
        request->count>MYL_NATIVE_OBJECT_COUNT_MAX ||
        (request->element->size && request->count>(SIZE_MAX-MYL_RC_PREFIX_BYTES)/request->element->size))
        return MYL_RC_ALLOCATION_REFUSED;
    size_t extent=MYL_RC_PREFIX_BYTES+request->count*request->element->size;
    size_t index=class_for(extent);
    myl_rc_object *object=index<RC_SLAB_CLASSES?slab_take(heap,index):large_take(heap,extent);
    if (!object) return MYL_RC_ALLOCATION_REFUSED;
    object->owners=1;
    object->holds=0;
    object->common=(myl_native_object){
        .mark=((uintptr_t)request->count<<MYL_NATIVE_OBJECT_COUNT_SHIFT) |
            (index==RC_SLAB_CLASSES?MYL_NATIVE_OBJECT_LARGE:0),
        .element=request->element
    };
    heap->objects_live++;
    heap->allocations++;
    *out=object+1;
    return MYL_RC_OK;
}
/* Saturation disables weak absence caching permanently; it never wraps back
 * to a cached epoch that could name a previous allocation at the same address. */
static void reuse_epoch(myl_native_heap *heap) {
    if (heap->collections!=SIZE_MAX) heap->collections++;
}
static void retire(myl_native_heap *heap, void *payload) {
    myl_rc_object *object=(myl_rc_object *)payload-1;
    assert(object->common.mark&MYL_RC_OBJECT_DYING);
    reuse_epoch(heap);
    assert(heap->objects_live);
    heap->objects_live--;
    if (object->common.mark&MYL_NATIVE_OBJECT_LARGE) {
        rc_large *large=(rc_large *)object-1;
        if (large->previous) large->previous->next=large->next;
        else storage_of(heap)->large=large->next;
        if (large->next) large->next->previous=large->previous;
        discharge(heap,large->charge);
        free(large);
        return;
    }
    rc_slab *slab=(rc_slab *)((uintptr_t)object&~(uintptr_t)(RC_SLAB_BYTES-1));
    rc_class *class=&storage_of(heap)->classes[slab->class_index];
    int full=!slab->free && slab->used==slots(slab);
    memcpy(object,&slab->free,sizeof slab->free);
    slab->free=object;
    assert(slab->live);
    slab->live--;
    if (full) available_add(class,slab);
    if (!slab->live) {
        rc_slab *empty=class->available;
        if (empty!=slab && empty && !empty->live) slab_free(heap,empty);
        available_remove(class,slab);
        available_add(class,slab);
    }
}
static void destroy(myl_native_heap *heap) {
    rc_storage *storage=storage_of(heap);
    assert(!storage->large);
    for (size_t i=0;i<RC_SLAB_CLASSES;i++) {
        while (storage->classes[i].all) slab_free(heap,storage->classes[i].all);
    }
    assert(storage->reserved==sizeof *storage);
    discharge(heap,sizeof *storage);
    free(storage);
}
static const myl_rc_allocator allocator={allocate,retire,destroy};
myl_rc_status myl_rc_storage_init(myl_native_heap *heap) {
    if (!budget(heap,sizeof(rc_storage))) return MYL_RC_ALLOCATION_REFUSED;
    rc_storage *storage=calloc(1,sizeof *storage);
    if (!storage) return MYL_RC_ALLOCATION_REFUSED;
    heap->bytes+=sizeof *storage;
    storage->reserved=sizeof *storage;
    myl_rc_status status=myl_rc_heap_init(heap,&allocator,storage);
    if (status!=MYL_RC_OK) { heap->bytes-=sizeof *storage; free(storage); return status; }
    status=myl_rc_module_register(heap,&raw_module);
    if (status!=MYL_RC_OK) myl_rc_heap_destroy(heap);
    return status;
}
void *myl_rc_storage_bytes(myl_native_heap *heap, size_t bytes, unsigned region) {
    void *result=NULL;
    myl_rc_alloc_request request={&raw_type,bytes,region};
    myl_rc_status status=myl_rc_new(heap,&request,&result);
    if (status!=MYL_RC_OK) myl_rc_record_failure(heap,status);
    return result;
}
void *myl_rc_storage_extend(myl_native_heap *heap, void *payload, size_t count) {
    if (!payload) return NULL;
    myl_native_object *common=(myl_native_object *)payload-1;
    if (common->mark&(MYL_NATIVE_OBJECT_IMMORTAL|MYL_NATIVE_OBJECT_ARENA|MYL_RC_OBJECT_DYING)) return NULL;
    myl_rc_object *object=(myl_rc_object *)payload-1;
    if (!(common->mark&MYL_NATIVE_OBJECT_LARGE) || object->owners!=1 || object->holds ||
        (common->mark&MYL_NATIVE_OBJECT_PINNED) || count>MYL_NATIVE_OBJECT_COUNT_MAX ||
        !common->element->size || count>(SIZE_MAX-MYL_RC_PREFIX_BYTES-sizeof(rc_large))/common->element->size)
        return NULL;
    rc_large *large=(rc_large *)object-1;
    size_t extent=MYL_RC_PREFIX_BYTES+count*common->element->size;
    if (extent<=large->extent) return NULL;
    size_t bytes=sizeof *large+extent, growth=bytes-large->charge;
    if (!reserve(heap,growth)) return NULL;
    size_t previous=large->charge;
    rc_large *grown=realloc(large,bytes);
    if (!grown) return NULL;
    memset((unsigned char *)grown+previous,0,growth);
    if (grown->previous) grown->previous->next=grown;
    else storage_of(heap)->large=grown;
    if (grown->next) grown->next->previous=grown;
    grown->charge=bytes;
    grown->extent=extent;
    object=(myl_rc_object *)(grown+1);
    object->common.mark=(object->common.mark&~MYL_NATIVE_OBJECT_COUNT_BITS)|((uintptr_t)count<<MYL_NATIVE_OBJECT_COUNT_SHIFT);
    charge(heap,growth);
    reuse_epoch(heap);
    return object+1;
}
size_t myl_rc_storage_reserved(const myl_native_heap *heap) {
    return storage_of(heap)->reserved;
}
