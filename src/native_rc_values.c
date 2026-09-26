#include "native_collections.h"
#include "native_dictionary.h"
#include "native_rc_values.h"
#include "native_rc_internal.h"
#include <stdlib.h>
#include <string.h>
const myl_rc_shape *myl_rc_native_shape(myl_native_heap *heap, const myl_native_type *type) {
    const myl_rc_descriptor *known=myl_rc_descriptor_find(heap,type);
    if (known) return known->shape;
    myl_rc_shape source={.size=type->size,.kind=MYL_RC_SHAPE_NONE};
    if (type->kind==MYL_NATIVE_POINTER) source.kind=MYL_RC_SHAPE_POINTER;
    else if (type->kind!=MYL_NATIVE_PLAIN && type->kind!=MYL_NATIVE_FLOAT) abort();
    myl_rc_descriptor descriptor={.type=type,.shape=&source};
    myl_rc_status status=myl_rc_descriptor_import(heap,&descriptor);
    if (status!=MYL_RC_OK) { myl_rc_record_failure(heap,status); return NULL; }
    return myl_rc_descriptor_find(heap,type)->shape;
}
/* Indexed descriptors live in immutable private bindings. Registration alone
 * builds the optional flat plan; imported public metadata remains unchanged. */
static const myl_rc_binding *native_binding(myl_native_heap *heap, const myl_native_type *type) {
    const myl_rc_descriptor *descriptor=myl_rc_descriptor_find(heap,type);
    if (!descriptor) {
        if (!myl_rc_native_shape(heap,type)) return NULL;
        descriptor=myl_rc_descriptor_find(heap,type);
    }
    return (const myl_rc_binding *)descriptor;
}
/* No callback/allocation runs between preflight and publication. Repeated
 * payloads need one increment per physical edge, so include earlier aliases
 * when checking capacity. Refusal has acquired no tokens to roll back. */
static int flat_transfer(myl_native_heap *heap, const myl_rc_binding *binding,
                         void *destination, void *source, unsigned region, myl_rc_transfer mode) {
    const myl_rc_flat *flat=&binding->flat;
    if (flat->count>MYL_RC_FLAT_LEAVES) return -1;
    myl_rc_invariant(heap && heap->rc && destination && source && destination!=source);
    size_t bytes=binding->descriptor.type->size;
    uintptr_t dst=(uintptr_t)destination, src=(uintptr_t)source;
    if (dst>src?dst-src<bytes:src-dst<bytes) return -1;
    if (region>heap->region_depth) return MYL_RC_REGION_ERROR;
    void *payloads[MYL_RC_FLAT_LEAVES];
    for (unsigned i=0;i<flat->count;i++) {
        void *payload;
        memcpy(&payload,(const unsigned char *)source+flat->offsets[i],sizeof payload);
        payloads[i]=payload;
        if (!payload) continue;
        uintptr_t mark=((myl_native_object *)payload-1)->mark;
        if (mark&MYL_NATIVE_OBJECT_IMMORTAL) continue;
        if (mark&MYL_NATIVE_OBJECT_PINNED) return -1;
        if (mark&MYL_NATIVE_OBJECT_ARENA) {
            if (myl_native_header_region(payload)>region) return -1;
            continue;
        }
        const myl_rc_object *object=(const myl_rc_object *)payload-1;
        myl_rc_invariant(!(mark&MYL_RC_OBJECT_DYING) && (object->owners || object->holds));
        if (mode==MYL_RC_COPY) {
            uintptr_t additions=1;
            for (unsigned j=0;j<i;j++) if (payloads[j]==payload) ++additions;
            if (object->owners>MYL_RC_COUNT_MAX-additions) {
                MYL_RC_STAT(heap,MYL_RC_STAT_OWNER_LIMIT);
                memset(destination,0,bytes);
                if (heap->rc->dead.head) myl_rc_drain(heap);
                return MYL_RC_COUNT_LIMIT;
            }
        }
    }
    if (mode==MYL_RC_COPY) for (unsigned i=0;i<flat->count;i++) {
        void *payload=payloads[i];
        if (!payload) continue;
        myl_native_object *common=(myl_native_object *)payload-1;
        if (common->mark&MYL_NATIVE_OBJECT_IMMORTAL) continue;
        if (common->mark&MYL_NATIVE_OBJECT_ARENA) common->mark|=MYL_NATIVE_OBJECT_SHARED;
        else {
            ++((myl_rc_object *)payload-1)->owners;
            MYL_RC_STAT(heap,MYL_RC_STAT_OWNER_ACQUIRE);
        }
    }
    memcpy(destination,source,bytes);
    if (mode==MYL_RC_TAKE) memset(source,0,bytes);
    if (heap->rc->dead.head) myl_rc_drain(heap);
    return MYL_RC_OK;
}
static int publication_status(myl_native_heap *heap, myl_rc_status status) {
    if (status==MYL_RC_OK) return 1;
    myl_rc_record_failure(heap,status);
    return 0;
}
int myl_rc_native_copy(myl_native_heap *heap, const myl_native_type *type, void *dst, const void *src, unsigned region) {
    if (type->kind==MYL_NATIVE_PLAIN || type->kind==MYL_NATIVE_FLOAT) {
        memmove(dst,src,type->size);
        return 1;
    }
    const myl_rc_binding *binding=native_binding(heap,type);
    if (!binding) return 0;
    const myl_rc_shape *shape=binding->descriptor.shape;
    if (shape->kind==MYL_RC_SHAPE_POINTER)
        return publication_status(heap,myl_rc_pointer_transfer(heap,shape,dst,(void *)src,region,MYL_RC_COPY));
    int flat=flat_transfer(heap,binding,dst,(void *)src,region,MYL_RC_COPY);
    if (flat>=0) return publication_status(heap,(myl_rc_status)flat);
    myl_rc_slot target={.shape=shape,.address=dst,.region=region};
    myl_rc_slot source={.shape=shape,.address=(void *)src,.region=region};
    return publication_status(heap,myl_rc_value_copy(heap,&target,&source));
}
int myl_rc_native_replace(myl_native_heap *heap, const myl_native_type *type, void *dst, const void *src, unsigned region) {
    if (type->kind==MYL_NATIVE_PLAIN || type->kind==MYL_NATIVE_FLOAT) {
        memmove(dst,src,type->size);
        return 1;
    }
    const myl_rc_shape *shape=myl_rc_native_shape(heap,type);
    if (!shape) return 0;
    myl_rc_slot target={.shape=shape,.address=dst,.region=region};
    myl_rc_slot source={.shape=shape,.address=(void *)src,.region=region};
    return publication_status(heap,myl_rc_value_replace(heap,&target,&source,MYL_RC_COPY));
}
int myl_rc_native_take(myl_native_heap *heap, const myl_native_type *type, void *dst, void *src, unsigned region) {
    if (type->kind==MYL_NATIVE_PLAIN || type->kind==MYL_NATIVE_FLOAT) {
        memmove(dst,src,type->size);
        if (dst!=src) memset(src,0,type->size);
        return 1;
    }
    const myl_rc_binding *binding=native_binding(heap,type);
    if (!binding) return 0;
    const myl_rc_shape *shape=binding->descriptor.shape;
    if (shape->kind==MYL_RC_SHAPE_POINTER) {
        void *staged=NULL;
        myl_rc_status status=myl_rc_pointer_transfer(heap,shape,&staged,src,region,MYL_RC_TAKE);
        if (status==MYL_RC_OK) memcpy(dst,&staged,sizeof staged);
        return publication_status(heap,status);
    }
    unsigned char local[128];
    void *staged=type->size<=sizeof local?local:myl_rc_storage_bytes(heap,type->size,0);
    if (!staged) return 0;
    myl_rc_slot target={.shape=shape,.address=staged,.region=region};
    myl_rc_slot source={.shape=shape,.address=src,.region=region};
    int flat=flat_transfer(heap,binding,staged,src,region,MYL_RC_TAKE);
    myl_rc_status status=flat>=0?(myl_rc_status)flat:myl_rc_value_take(heap,&target,&source);
    int ok=publication_status(heap,status);
    if (ok) memmove(dst,staged,type->size);
    if (staged!=local) myl_rc_owner_release(heap,staged);
    return ok;
}
void myl_rc_native_drop(myl_native_heap *heap, const myl_native_type *type, void *value) {
    const myl_rc_descriptor *descriptor=myl_rc_descriptor_find(heap,type);
    if (!descriptor) abort();
    if (descriptor->shape->kind==MYL_RC_SHAPE_POINTER) {
        void *payload;
        memcpy(&payload,value,sizeof payload);
        memset(value,0,sizeof payload);
        myl_rc_owner_release(heap,payload);
        return;
    }
    const myl_rc_binding *binding=(const myl_rc_binding *)descriptor;
    if (binding->flat.count<=MYL_RC_FLAT_LEAVES) {
        myl_rc_flat_edges_release(heap,binding,value,1);
        memset(value,0,type->size);
        if (heap->rc->dead.head) myl_rc_drain(heap);
        return;
    }
    myl_rc_slot slot={.shape=descriptor->shape,.address=value};
    myl_rc_value_drop(heap,&slot);
}
int myl_rc_native_loan(myl_native_heap *heap, const myl_native_type *type, void *dst, const void *src) {
    const myl_rc_shape *shape = myl_rc_native_shape(heap, type);
    if (!shape) { memset(dst, 0, type->size); return 0; }
    myl_rc_invariant(!myl_rc_native_has_unique(heap, type));
    return publication_status(heap, myl_rc_loan_copy(heap, shape, dst, src));
}
void myl_rc_native_unloan(myl_native_heap *heap, const myl_native_type *type, void *value) {
    const myl_rc_descriptor *descriptor = myl_rc_descriptor_find(heap, type);
    myl_rc_invariant(descriptor != NULL);
    myl_rc_loan_drop(heap, descriptor->shape, value);
}
int myl_rc_native_mutable(const void *payload) {
    return myl_native_list_header(payload) || myl_native_dictionary_header(payload);
}
int myl_rc_native_publish(myl_native_heap *heap, const myl_native_type *type, void *dst,
                          void *src, unsigned region, unsigned semantic_mode) {
    myl_rc_invariant(!(semantic_mode & ~(MYL_RC_HISTORY_TAKE | 3u)) && (semantic_mode & 3u) != 3u);
    const myl_rc_shape *shape = myl_rc_native_shape(heap, type);
    if (!shape) { memset(dst, 0, type->size); return 0; }
    myl_rc_invariant(!myl_rc_native_has_unique(heap, type));
    myl_rc_slot destination = {.shape=shape,.address=dst,.region=region};
    myl_rc_slot source = {.shape=shape,.address=src};
    myl_rc_transfer mode = semantic_mode & MYL_RC_HISTORY_TAKE ? MYL_RC_TAKE : MYL_RC_COPY;
    unsigned policy = 1;
    if ((semantic_mode & 3u) && type->kind == MYL_NATIVE_POINTER)
        policy = type->collection_kind == 1 || type->collection_kind == 3 || type->collection_kind == 4 ? 2 : 0;
    return publication_status(heap, myl_rc_semantic_transfer(heap, &destination, &source, mode, policy));
}
int myl_rc_native_retain(myl_native_heap *heap, const myl_native_type *type, void *dst,
                         const void *src, unsigned region) {
    const myl_rc_shape *shape = myl_rc_native_shape(heap, type);
    if (!shape) { memset(dst, 0, type->size); return 0; }
    myl_rc_invariant(!myl_rc_native_has_unique(heap, type));
    memset(dst, 0, type->size);
    myl_rc_slot target = {.shape=shape,.address=dst,.region=region};
    myl_rc_slot source = {.shape=shape,.address=(void *)src};
    return publication_status(heap, myl_rc_value_retain_many(heap, &target, &source, 1));
}
int myl_rc_native_retain_replace(myl_native_heap *heap, const myl_native_type *type, void *dst,
                                 const void *src, unsigned region) {
    if (dst == src) return 1;
    unsigned char local[128];
    void *staged = type->size <= sizeof local ? local : myl_rc_storage_bytes(heap, type->size, 0);
    if (!staged) return 0;
    int ok = myl_rc_native_retain(heap, type, staged, src, region);
    if (ok) {
        /* The old slot is inaccessible to callbacks until the new value is
         * installed. Cleanup walks only the separately staged former value. */
        unsigned char *left=dst, *right=staged;
        for (size_t i=0;i<type->size;i++) { unsigned char byte=left[i]; left[i]=right[i]; right[i]=byte; }
        myl_rc_native_drop(heap, type, staged);
    }
    if (staged != local) myl_rc_owner_release(heap, staged);
    return ok;
}
void *myl_rc_native_storage(myl_native_heap *heap, const myl_native_type *type, size_t count, unsigned region) {
    if (type->size && count>SIZE_MAX/type->size) return NULL;
    return myl_rc_storage_bytes(heap,type->size*count,region);
}
myl_rc_status myl_rc_native_result(myl_native_heap *heap, const void *result) {
    if (result) return MYL_RC_OK;
    myl_rc_status status=myl_rc_take_failure(heap);
    if (status==MYL_RC_OK) status=MYL_RC_ALLOCATION_REFUSED;
    myl_rc_record_failure(heap,status);
    return status;
}
void myl_rc_native_abort(myl_native_heap *heap, void *payload) {
    myl_rc_construction_abort(heap,payload);
}
