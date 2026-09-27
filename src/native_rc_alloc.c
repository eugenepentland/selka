#define _POSIX_C_SOURCE 200809L
#include "native_rc_alloc.h"
#include "native_rc_internal.h"
#include "native_rc_values.h"
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
    struct { size_t index, capacity; } class;
};
typedef struct rc_large rc_large;
struct rc_large {
    rc_large *previous, *next;
    size_t charge, extent;
};
typedef struct {
    rc_slab *all, *available;
} rc_class;
/* Size classes for extents up to the largest stride, one byte per 16-byte step. */
#define RC_CLASS_STEPS (8192 / 16 + 1)
typedef struct {
    rc_class classes[RC_SLAB_CLASSES];
    rc_large *large;
    size_t reserved;
    struct { const myl_native_type *type; size_t index; } single;
    unsigned char class_of[RC_CLASS_STEPS];
} rc_storage;
static const size_t strides[RC_SLAB_CLASSES] = {
    16,32,48,64,80,96,112,128,160,192,224,256,320,384,448,512,
    640,768,896,1024,1280,1536,1792,2048,2560,3072,3584,4096,
    5120,6144,7168,8192
};
#define RC_SLAB_OFFSET ((sizeof(rc_slab) + 15) & ~(size_t)15)
_Static_assert(RC_SLAB_OFFSET == 80, "cached capacity fits the existing aligned slab metadata extent");
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
    myl_rc_invariant(heap && heap->rc);
    return heap->rc->allocator.context;
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
    return slab->class.capacity;
}
static void slab_free(myl_native_heap *heap, rc_slab *slab) {
    rc_class *class=&storage_of(heap)->classes[slab->class.index];
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
static __attribute__((noinline)) rc_slab *slab_new(myl_native_heap *heap, size_t index) {
    if (!reserve(heap,RC_SLAB_BYTES)) return NULL;
    rc_slab *slab=aligned_alloc(RC_SLAB_BYTES,RC_SLAB_BYTES);
    if (!slab) { trim_empty(heap); slab=aligned_alloc(RC_SLAB_BYTES,RC_SLAB_BYTES); }
    if (!slab) return NULL;
    memset(slab,0,sizeof *slab);
    slab->stride=strides[index];
    slab->class.index=index;
    slab->class.capacity=(RC_SLAB_BYTES-RC_SLAB_OFFSET)/slab->stride;
    rc_class *class=&storage_of(heap)->classes[index];
    slab->all.next=class->all;
    if (class->all) class->all->all.previous=slab;
    class->all=slab;
    available_add(class,slab);
    charge(heap,RC_SLAB_BYTES);
    return slab;
}
static size_t class_search(size_t extent) {
    size_t low=0, high=RC_SLAB_CLASSES;
    while (low<high) {
        size_t middle=low+(high-low)/2;
        if (strides[middle]<extent) low=middle+1;
        else high=middle;
    }
    return low;
}
/* One table load for every slab-sized extent; larger extents are LARGE. */
static size_t class_for(const rc_storage *storage, size_t extent) {
    return extent<=strides[RC_SLAB_CLASSES-1]?storage->class_of[(extent+15)/16]:RC_SLAB_CLASSES;
}
static inline __attribute__((always_inline)) myl_rc_object *slab_take(myl_native_heap *heap, size_t index) {
    rc_class *class=&storage_of(heap)->classes[index];
    rc_slab *slab=class->available;
    if (!slab) slab=slab_new(heap,index);
    if (!slab) return NULL;
    void *slot=slab->free;
    if (slot) memcpy(&slab->free,slot,sizeof slab->free);
    else slot=(unsigned char *)slab+RC_SLAB_OFFSET+slab->stride*slab->used++;
    slab->live++;
    if (!slab->free && slab->used==slots(slab)) available_remove(class,slab);
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
/* A retired slab slot keeps this mark until reuse. DYING|IMMORTAL never
 * describes a counted object, so it separates free slots from allocated ones
 * (live, or queued for death) without a side table. */
#define RC_RETIRED_MARK (MYL_RC_OBJECT_DYING|(uintptr_t)MYL_NATIVE_OBJECT_IMMORTAL)
/* Zero a slab payload in whole 16-byte units: the slot is 16-byte aligned and
 * its stride covers the rounded payload, so the tail is slot padding. Small
 * payloads use straight-line vector stores instead of a memset call. */
typedef unsigned char rc_zero_unit __attribute__((vector_size(16), aligned(16), may_alias));
static inline void zero_payload(unsigned char *payload, size_t bytes) {
    rc_zero_unit *unit=(rc_zero_unit *)payload;
    const rc_zero_unit zero={0};
    switch ((bytes+15)/16) {
        case 8: unit[7]=zero; /* fall through */
        case 7: unit[6]=zero; /* fall through */
        case 6: unit[5]=zero; /* fall through */
        case 5: unit[4]=zero; /* fall through */
        case 4: unit[3]=zero; /* fall through */
        case 3: unit[2]=zero; /* fall through */
        case 2: unit[1]=zero; /* fall through */
        case 1: unit[0]=zero; /* fall through */
        case 0: return;
        default: memset(payload,0,bytes); return;
    }
}
/* Write the prefix of a fresh allocation. Only the payload needs zero bytes
 * (large extents arrive zeroed; slab callers zero first), and bytes past the
 * payload in a slab slot are never read. */
static void *initialize(myl_native_heap *heap, myl_rc_object *object,
                        const myl_native_type *element, size_t count, uintptr_t flags) {
    object->owners=1;
    object->holds=0;
    object->common=(myl_native_object){.mark=((uintptr_t)count<<MYL_NATIVE_OBJECT_COUNT_SHIFT)|flags,
        .element=element};
    heap->objects_live++;
    heap->allocations++;
    return object+1;
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
    size_t index=class_for(storage_of(heap),extent);
    myl_rc_object *object=index<RC_SLAB_CLASSES?slab_take(heap,index):large_take(heap,extent);
    if (!object) return MYL_RC_ALLOCATION_REFUSED;
    if (index<RC_SLAB_CLASSES) zero_payload((unsigned char *)(object+1),extent-MYL_RC_PREFIX_BYTES);
    *out=initialize(heap,object,request->element,request->count,
        index==RC_SLAB_CLASSES?MYL_NATIVE_OBJECT_LARGE:0);
    return MYL_RC_OK;
}
/* The descriptor/type contract is immutable for the heap's lifetime. This
 * single-type cache stores only a completed registration and size-class proof,
 * never a slab address; trim, retirement and reentrant metadata registration
 * therefore cannot invalidate it. All other requests retain the generic hook. */
void *myl_rc_storage_alloc(myl_native_heap *heap, const myl_native_type *element, size_t count, unsigned region) {
    myl_rc_invariant(heap && heap->rc && element);
    if (!region && count==1 && heap->rc->allocator.hooks.allocate==allocate) {
        rc_storage *storage=storage_of(heap);
        size_t index;
        if (storage->single.type==element) index=storage->single.index;
        else {
            /* The binding carries its type's class; the one-entry cache then
             * follows the most recent type. */
            myl_rc_binding *binding=(myl_rc_binding *)myl_rc_binding_find(heap,element);
            if (binding && binding->alloc_class) index=binding->alloc_class-1;
            else {
                if (!myl_rc_native_shape(heap,element)) return NULL;
                if (element->alignment>16 || element->size>strides[RC_SLAB_CLASSES-1]-MYL_RC_PREFIX_BYTES)
                    goto registered;
                index=class_for(storage,MYL_RC_PREFIX_BYTES+element->size);
                binding=(myl_rc_binding *)myl_rc_binding_find(heap,element);
                binding->alloc_class=(unsigned)index+1;
            }
            storage->single.type=element;
            storage->single.index=index;
        }
        myl_rc_object *object=slab_take(heap,index);
        if (!object) { myl_rc_record_failure(heap,MYL_RC_ALLOCATION_REFUSED); return NULL; }
        zero_payload((unsigned char *)(object+1),element->size);
        void *payload=initialize(heap,object,element,1,0);
        MYL_RC_STAT(heap,MYL_RC_STAT_HEAP_ALLOCATE);
        return payload;
    }
    if (!myl_rc_native_shape(heap,element)) return NULL;
registered:;
    myl_rc_alloc_request request={element,count,region};
    void *result=NULL;
    myl_rc_status status=myl_rc_new(heap,&request,&result);
    if (status!=MYL_RC_OK) myl_rc_record_failure(heap,status);
    return result;
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
    rc_class *class=&storage_of(heap)->classes[slab->class.index];
    int full=!slab->free && slab->used==slots(slab);
    object->common.mark=RC_RETIRED_MARK;
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
void myl_rc_storage_visit(myl_native_heap *heap, myl_rc_extent_visitor visit, void *context) {
    myl_rc_invariant(heap && heap->rc && heap->rc->allocator.hooks.allocate==allocate && visit);
    rc_storage *storage=storage_of(heap);
    for (size_t i=0;i<RC_SLAB_CLASSES;i++)
        for (rc_slab *slab=storage->classes[i].all;slab;slab=slab->all.next) {
            unsigned char *slot=(unsigned char *)slab+RC_SLAB_OFFSET;
            for (size_t used=slab->used;used;--used,slot+=slab->stride) {
                myl_rc_object *object=(myl_rc_object *)slot;
                if (object->common.mark!=RC_RETIRED_MARK) visit(heap,object+1,context);
            }
        }
    for (rc_large *large=storage->large;large;large=large->next)
        visit(heap,(myl_rc_object *)(large+1)+1,context);
}
void myl_rc_storage_release_all(myl_native_heap *heap) {
    myl_rc_invariant(heap && heap->rc && heap->rc->allocator.hooks.allocate==allocate);
    myl_rc_invariant(!heap->rc->dead.active && !heap->rc->walk.depth);
    rc_storage *storage=storage_of(heap);
    size_t released=0;
    while (storage->large) {
        rc_large *large=storage->large;
        storage->large=large->next;
        discharge(heap,large->charge);
        free(large);
        ++released;
    }
    for (size_t i=0;i<RC_SLAB_CLASSES;i++)
        while (storage->classes[i].all) {
            rc_slab *slab=storage->classes[i].all;
            released+=slab->live;
            slab->live=0;
            slab_free(heap,slab);
        }
    myl_rc_invariant(heap->objects_live>=released && storage->reserved==sizeof *storage);
    heap->objects_live-=released;
    heap->rc->dead.head=NULL;
    reuse_epoch(heap);
}
myl_rc_status myl_rc_storage_init(myl_native_heap *heap) {
    if (!budget(heap,sizeof(rc_storage))) return MYL_RC_ALLOCATION_REFUSED;
    rc_storage *storage=calloc(1,sizeof *storage);
    if (!storage) return MYL_RC_ALLOCATION_REFUSED;
    heap->bytes+=sizeof *storage;
    storage->reserved=sizeof *storage;
    for (size_t step=0;step<RC_CLASS_STEPS;step++) storage->class_of[step]=(unsigned char)class_search(step*16);
    myl_rc_status status=myl_rc_heap_init(heap,&allocator,storage);
    if (status!=MYL_RC_OK) { heap->bytes-=sizeof *storage; free(storage); return status; }
    status=myl_rc_module_register(heap,&raw_module);
    if (status!=MYL_RC_OK) myl_rc_heap_destroy(heap);
    return status;
}
/* Raw bytes are registered at initialization and own no edges, so a slab-sized
 * heap request needs none of myl_rc_new's metadata or region admission. A
 * block (zero == 0) leaves its payload unwritten: its caller writes every octet
 * it reads (GC-NOZERO-1). Everything else takes the generic hook. */
static void *raw_bytes(myl_native_heap *heap, size_t bytes, unsigned region, int zero) {
    myl_rc_invariant(heap && heap->rc);
    if (!region && heap->rc->allocator.hooks.allocate==allocate && bytes<=strides[RC_SLAB_CLASSES-1]-MYL_RC_PREFIX_BYTES) {
        myl_rc_object *object=slab_take(heap,class_for(storage_of(heap),MYL_RC_PREFIX_BYTES+bytes));
        if (!object) { myl_rc_record_failure(heap,MYL_RC_ALLOCATION_REFUSED); return NULL; }
        if (zero) zero_payload((unsigned char *)(object+1),bytes);
        void *payload=initialize(heap,object,&raw_type,bytes,0);
        MYL_RC_STAT(heap,MYL_RC_STAT_HEAP_ALLOCATE);
        return payload;
    }
    void *result=NULL;
    myl_rc_alloc_request request={&raw_type,bytes,region};
    myl_rc_status status=myl_rc_new(heap,&request,&result);
    if (status!=MYL_RC_OK) myl_rc_record_failure(heap,status);
    return result;
}
void *myl_rc_storage_bytes(myl_native_heap *heap, size_t bytes, unsigned region) {
    return raw_bytes(heap,bytes,region,1);
}
void *myl_rc_storage_block(myl_native_heap *heap, size_t bytes, unsigned region) {
    return raw_bytes(heap,bytes,region,0);
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
