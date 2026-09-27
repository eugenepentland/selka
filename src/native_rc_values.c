#include "native_collections.h"
#include "native_dictionary.h"
#include "native_rc_values.h"
#include "native_rc_internal.h"
#include <stdlib.h>
#include <string.h>
const myl_rc_shape *myl_rc_native_shape(myl_native_heap *heap, const myl_native_type *type) {
    const myl_rc_binding *known=myl_rc_binding_find(heap,type);
    if (known) return known->descriptor.shape;
    myl_rc_shape source={.size=type->size,.kind=MYL_RC_SHAPE_NONE};
    if (type->kind==MYL_NATIVE_POINTER) source.kind=MYL_RC_SHAPE_POINTER;
    else if (type->kind!=MYL_NATIVE_PLAIN && type->kind!=MYL_NATIVE_FLOAT) abort();
    myl_rc_descriptor descriptor={.type=type,.shape=&source};
    myl_rc_status status=myl_rc_descriptor_import(heap,&descriptor);
    if (status!=MYL_RC_OK) { myl_rc_record_failure(heap,status); return NULL; }
    return myl_rc_binding_find(heap,type)->descriptor.shape;
}
/* Indexed descriptors live in immutable private bindings. Registration alone
 * builds the optional flat plan; imported public metadata remains unchanged. */
static const myl_rc_binding *native_binding(myl_native_heap *heap, const myl_native_type *type) {
    const myl_rc_binding *binding=myl_rc_binding_find(heap,type);
    if (binding) return binding;
    if (!myl_rc_native_shape(heap,type)) return NULL;
    return myl_rc_binding_find(heap,type);
}
/* No callback/allocation runs between preflight and publication. Repeated
 * payloads need one increment per physical edge, so include earlier aliases
 * when checking capacity. Refusal has acquired no tokens to roll back. */
static int flat_transfer(myl_native_heap *heap, const myl_rc_binding *binding,
                         void *destination, void *source, unsigned region, myl_rc_transfer mode) {
    const myl_rc_flat *flat=&binding->flat;
    if (flat->count>MYL_RC_FLAT_LEAVES) return -1;
    myl_rc_invariant(heap && heap->rc && destination && source && destination!=source);
    size_t bytes=binding->flat.size;
    uintptr_t dst=(uintptr_t)destination, src=(uintptr_t)source;
    if (dst>src?dst-src<bytes:src-dst<bytes) return -1;
    if (region>heap->region_depth) return MYL_RC_REGION_ERROR;
    void *payloads[MYL_RC_FLAT_LEAVES];
    unsigned live=myl_rc_flat_live(flat,source);
    for (unsigned i=0;i<flat->count;i++) {
        void *payload=NULL;
        if (live&(1u<<i)) memcpy(&payload,(const unsigned char *)source+flat->offsets[i],sizeof payload);
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
                myl_rc_drain_pending(heap);
                return MYL_RC_COUNT_LIMIT;
            }
        }
    }
    if (mode==MYL_RC_COPY) for (unsigned rest=live;rest;rest&=rest-1) {
        void *payload=payloads[__builtin_ctz(rest)];
        if (!payload) continue;
        myl_native_object *common=(myl_native_object *)payload-1;
        if (common->mark&MYL_NATIVE_OBJECT_IMMORTAL) continue;
        if (common->mark&MYL_NATIVE_OBJECT_ARENA) common->mark|=MYL_NATIVE_OBJECT_SHARED;
        else {
            ++((myl_rc_object *)payload-1)->owners;
            MYL_RC_STAT(heap,MYL_RC_STAT_OWNER_ACQUIRE);
        }
    }
    myl_rc_copy_bytes(destination,source,bytes);
    if (mode==MYL_RC_TAKE) myl_rc_zero_bytes(source,bytes);
    myl_rc_drain_pending(heap);
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
    /* A flat TAKE either refuses before writing or completes; with no queued
     * death it cannot drain, so it may publish straight into the output. */
    if (!heap->rc->dead.head && dst!=src) {
        int direct=flat_transfer(heap,binding,dst,src,region,MYL_RC_TAKE);
        if (direct>=0) return publication_status(heap,(myl_rc_status)direct);
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
    const myl_rc_binding *binding=myl_rc_binding_find(heap,type);
    if (!binding) abort();
    const myl_rc_descriptor *descriptor=&binding->descriptor;
    if (descriptor->shape->kind==MYL_RC_SHAPE_POINTER) {
        void *payload;
        memcpy(&payload,value,sizeof payload);
        memset(value,0,sizeof payload);
        myl_rc_owner_release(heap,payload);
        return;
    }
    if (binding->flat.count<=MYL_RC_FLAT_LEAVES) {
        myl_rc_flat_release_one(heap,&binding->flat,value);
        myl_rc_zero_bytes(value,binding->flat.size);
        myl_rc_drain_pending(heap);
        return;
    }
    myl_rc_slot slot={.shape=descriptor->shape,.address=value};
    myl_rc_value_drop(heap,&slot);
}
/* Clear every sibling before callbacks. The generic compound walker defers
 * H-release drains until its frames are empty; a flat loop must do the same.
 * Arm tags are read before the clear: admission keeps them out of every leaf. */
static void flat_unloan(myl_native_heap *heap, const myl_rc_binding *binding, void *value) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth && value);
    const myl_rc_flat *flat = &binding->flat;
    for (unsigned live = myl_rc_flat_live(flat, value); live; live &= live - 1) {
        void *edge = (unsigned char *)value + flat->offsets[__builtin_ctz(live)], *payload;
        memcpy(&payload, edge, sizeof payload);
        memset(edge, 0, sizeof payload);
        myl_rc_hold_drop(heap, payload);
    }
    myl_rc_zero_bytes(value, binding->flat.size);
    myl_rc_drain_pending(heap);
}
/* A loaned payload's own descriptor must have no finalizer. That needs a probe
 * per payload, so it is a checked-mode invariant. */
static int loanable_payload(myl_native_heap *heap, const void *payload) {
    if (!payload) return 1;
    const myl_native_object *header = (const myl_native_object *)payload - 1;
    if (header->mark & MYL_NATIVE_OBJECT_IMMORTAL) return 1;
    const myl_rc_binding *binding = myl_rc_binding_find(heap, header->element);
    return binding && !binding->descriptor.finalize;
}
/* Native admission proves no inline unique field, including a NULL typed box.
 * Actual opaque payloads still need their own finalizer check. Acquisition in
 * shape order preserves duplicate-limit refusal and exact prefix rollback. */
static int flat_loan(myl_native_heap *heap, const myl_rc_binding *binding,
                      void *destination, const void *source) {
    if (!binding->flat.loanable || !binding->flat.size) return -1;
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth && destination && source && destination != source);
    uintptr_t dst = (uintptr_t)destination, src = (uintptr_t)source;
    size_t bytes = binding->flat.size;
    if (dst > src ? dst - src < bytes : src - dst < bytes) return -1;
    /* One pass: the copied bytes already hold every leaf. A refusal clears the
     * leaves not yet acquired, so the unloan releases exactly the prefix. */
    myl_rc_copy_bytes(destination, source, bytes);
    const myl_rc_flat *flat = &binding->flat;
    for (unsigned rest = myl_rc_flat_live(flat, source); rest; rest &= rest - 1) {
        void *payload;
        memcpy(&payload, (const unsigned char *)source + flat->offsets[__builtin_ctz(rest)], sizeof payload);
        myl_rc_checked(loanable_payload(heap, payload));
        if (!myl_rc_counted(payload)) continue;
        myl_rc_object *object = myl_rc_live(payload);
        if (object->holds == MYL_RC_COUNT_MAX) {
            MYL_RC_STAT(heap, MYL_RC_STAT_HOLD_LIMIT);
            for (; rest; rest &= rest - 1)
                memset((unsigned char *)destination + flat->offsets[__builtin_ctz(rest)], 0, sizeof(void *));
            flat_unloan(heap, binding, destination);
            return MYL_RC_COUNT_LIMIT;
        }
        ++object->holds;
        MYL_RC_STAT(heap, MYL_RC_STAT_HOLD_ACQUIRE);
    }
    myl_rc_drain_pending(heap);
    return MYL_RC_OK;
}
int myl_rc_native_loan(myl_native_heap *heap, const myl_native_type *type, void *dst, const void *src) {
    const myl_rc_binding *binding = myl_rc_binding_find(heap, type);
    if (binding) {
        int flat = flat_loan(heap, binding, dst, src);
        if (flat >= 0) return publication_status(heap, (myl_rc_status)flat);
    }
    const myl_rc_shape *shape = binding ? binding->descriptor.shape : myl_rc_native_shape(heap, type);
    if (!shape) { memset(dst, 0, type->size); return 0; }
    myl_rc_invariant(!(binding ? myl_rc_binding_has_unique(heap, binding) : myl_rc_native_has_unique(heap, type)));
    return publication_status(heap, myl_rc_loan_copy(heap, shape, dst, src));
}
void myl_rc_native_unloan(myl_native_heap *heap, const myl_native_type *type, void *value) {
    const myl_rc_binding *binding = myl_rc_binding_find(heap, type);
    myl_rc_invariant(binding != NULL);
    if (binding->flat.loanable && type->size) { flat_unloan(heap, binding, value); return; }
    myl_rc_loan_drop(heap, binding->descriptor.shape, value);
}
int myl_rc_native_mutable(const void *payload) {
    return myl_native_list_header(payload) || myl_native_dictionary_header(payload);
}
/* Direct (policy 1) semantic publication of an admitted flat value: the
 * general transaction's per-leaf transfer_pointer and deferred marks, with a
 * preflight that proves every acquisition succeeds first. Pinned and
 * younger-region leaves (snapshots, escapes) keep the general path. */
static int flat_semantic(myl_native_heap *heap, const myl_rc_binding *binding,
                         void *destination, void *source, unsigned region, myl_rc_transfer mode) {
    const myl_rc_flat *flat = &binding->flat;
    size_t bytes = flat->size;
    if (flat->count > MYL_RC_FLAT_LEAVES || !bytes) return -1;
    uintptr_t dst = (uintptr_t)destination, src = (uintptr_t)source;
    if (dst > src ? dst - src < bytes : src - dst < bytes) return -1;
    if (region > heap->region_depth) return MYL_RC_REGION_ERROR;
    void *payloads[MYL_RC_FLAT_LEAVES];
    unsigned live = myl_rc_flat_live(flat, source), counted = 0;
    for (unsigned rest = live; rest; rest &= rest - 1) {
        unsigned leaf = __builtin_ctz(rest);
        void *payload;
        memcpy(&payload, (const unsigned char *)source + flat->offsets[leaf], sizeof payload);
        payloads[leaf] = payload;
        if (!payload) continue;
        uintptr_t mark = ((myl_native_object *)payload - 1)->mark;
        if (mark & MYL_NATIVE_OBJECT_IMMORTAL) continue;
        if (mark & MYL_NATIVE_OBJECT_PINNED) return -1;
        if (mark & MYL_NATIVE_OBJECT_ARENA) {
            if (myl_native_header_region(payload) > region) return -1;
            continue;
        }
        const myl_rc_object *object = (const myl_rc_object *)payload - 1;
        myl_rc_invariant(!(mark & MYL_RC_OBJECT_DYING) && (object->owners || object->holds));
        counted |= 1u << leaf;
        if (mode != MYL_RC_COPY) continue;
        uintptr_t additions = 1;
        for (unsigned prior = live & ((1u << leaf) - 1); prior; prior &= prior - 1)
            if (payloads[__builtin_ctz(prior)] == payload) ++additions;
        if (object->owners > MYL_RC_COUNT_MAX - additions) {
            MYL_RC_STAT(heap, MYL_RC_STAT_OWNER_LIMIT);
            memset(destination, 0, bytes);
            myl_rc_drain_pending(heap);
            return MYL_RC_COUNT_LIMIT;
        }
    }
    for (unsigned rest = live; rest; rest &= rest - 1) {
        unsigned leaf = __builtin_ctz(rest);
        void *payload = payloads[leaf];
        if (!payload) continue;
        myl_native_object *common = (myl_native_object *)payload - 1;
        if (common->mark & MYL_NATIVE_OBJECT_IMMORTAL) continue;
        if (mode == MYL_RC_COPY && (counted & (1u << leaf))) {
            ++((myl_rc_object *)payload - 1)->owners;
            MYL_RC_STAT(heap, MYL_RC_STAT_OWNER_ACQUIRE);
        }
        if (!(common->mark & MYL_NATIVE_OBJECT_SHARED) && myl_rc_native_mutable(payload))
            common->mark |= MYL_NATIVE_OBJECT_SHARED;
    }
    myl_rc_copy_bytes(destination, source, bytes);
    if (mode == MYL_RC_TAKE) myl_rc_zero_bytes(source, bytes);
    myl_rc_drain_pending(heap);
    return MYL_RC_OK;
}
int myl_rc_native_publish(myl_native_heap *heap, const myl_native_type *type, void *dst,
                          void *src, unsigned region, unsigned semantic_mode) {
    myl_rc_invariant(!(semantic_mode & ~(MYL_RC_HISTORY_TAKE | 3u)) && (semantic_mode & 3u) != 3u);
    const myl_rc_shape *shape = myl_rc_native_shape(heap, type);
    if (!shape) { memset(dst, 0, type->size); return 0; }
    myl_rc_checked(!myl_rc_native_has_unique(heap, type));
    if (type->kind != MYL_NATIVE_POINTER) {
        int fast = flat_semantic(heap, myl_rc_binding_find(heap, type), dst, src, region,
                                 semantic_mode & MYL_RC_HISTORY_TAKE ? MYL_RC_TAKE : MYL_RC_COPY);
        if (fast >= 0) return publication_status(heap, (myl_rc_status)fast);
    }
    myl_rc_slot destination = {.shape=shape,.address=dst,.region=region};
    myl_rc_slot source = {.shape=shape,.address=src};
    myl_rc_transfer mode = semantic_mode & MYL_RC_HISTORY_TAKE ? MYL_RC_TAKE : MYL_RC_COPY;
    unsigned policy = 1;
    if ((semantic_mode & 3u) && type->kind == MYL_NATIVE_POINTER)
        policy = type->collection_kind == 1 || type->collection_kind == 3 || type->collection_kind == 4 ? 2 : 0;
    return publication_status(heap, myl_rc_semantic_transfer(heap, &destination, &source, mode, policy));
}
/* Physical acquisition preserves pins, identity and arena history. Unlike
 * semantic COPY, a later refusal must retain the exact acquired-prefix traffic.
 * Loan admission also proves the native unique predicate and local stack bound;
 * actual opaque pointee finalizers remain legal for ordinary owner retention. */
static int flat_retain(myl_native_heap *heap, const myl_rc_binding *binding,
                       void *destination, const void *source, unsigned region) {
    size_t bytes = binding->flat.size;
    if (!binding->flat.loanable || !bytes) return -1;
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth && destination && source);
    uintptr_t dst = (uintptr_t)destination, src = (uintptr_t)source;
    if (dst > src ? dst - src < bytes : src - dst < bytes) return -1;
    if (region > heap->region_depth) {
        memset(destination, 0, bytes);
        myl_rc_drain_pending(heap);
        return MYL_RC_REGION_ERROR;
    }
    myl_rc_copy_bytes(destination, source, bytes);
    const myl_rc_flat *flat = &binding->flat;
    myl_rc_status status = MYL_RC_OK;
    for (unsigned rest = myl_rc_flat_live(flat, source); rest; rest &= rest - 1) {
        void *payload;
        memcpy(&payload, (const unsigned char *)source + flat->offsets[__builtin_ctz(rest)], sizeof payload);
        if (payload && myl_native_header_region(payload) > region) status = MYL_RC_REGION_ERROR;
        else status = myl_rc_owner_take(heap, payload);
        if (status == MYL_RC_OK) continue;
        /* Clear the leaves not yet acquired; release exactly the prefix. */
        for (; rest; rest &= rest - 1)
            memset((unsigned char *)destination + flat->offsets[__builtin_ctz(rest)], 0, sizeof(void *));
        myl_rc_flat_edges_release(heap, binding, destination, 1);
        memset(destination, 0, bytes);
        break;
    }
    myl_rc_drain_pending(heap);
    return status;
}
int myl_rc_native_retain(myl_native_heap *heap, const myl_native_type *type, void *dst,
                         const void *src, unsigned region) {
    const myl_rc_binding *binding = myl_rc_binding_find(heap, type);
    /* Flat admission excludes unique contents and hooks as well as O/H leaves.
     * Keep cold registration, zero-size/overlapping slots and queued callbacks
     * on the original path; retain's empty output differs from replacement. */
    if (binding && !binding->flat.count && !heap->rc->dead.head) {
        uintptr_t target = (uintptr_t)dst, source = (uintptr_t)src;
        size_t bytes = type->size;
        if (bytes && (target > source ? target - source >= bytes : source - target >= bytes)) {
            if (region > heap->region_depth) {
                memset(dst, 0, bytes);
                return publication_status(heap, MYL_RC_REGION_ERROR);
            }
            myl_rc_copy_bytes(dst, src, bytes);
            return 1;
        }
    }
    if (binding) {
        int flat = flat_retain(heap, binding, dst, src, region);
        if (flat >= 0) return publication_status(heap, (myl_rc_status)flat);
    }
    const myl_rc_shape *shape = binding ? binding->descriptor.shape : myl_rc_native_shape(heap, type);
    if (!shape) { memset(dst, 0, type->size); return 0; }
    myl_rc_invariant(!(binding ? myl_rc_binding_has_unique(heap, binding) : myl_rc_native_has_unique(heap, type)));
    memset(dst, 0, type->size);
    myl_rc_slot target = {.shape=shape,.address=dst,.region=region};
    myl_rc_slot source = {.shape=shape,.address=(void *)src};
    return publication_status(heap, myl_rc_value_retain_many(heap, &target, &source, 1));
}
int myl_rc_native_retain_replace(myl_native_heap *heap, const myl_native_type *type, void *dst,
                                 const void *src, unsigned region) {
    if (dst == src) return 1;
    const myl_rc_binding *binding = myl_rc_binding_find(heap, type);
    /* Native flat admission excludes raw unique contents and every hook, not
     * just counted edges. Pending deaths retain the staged-source callback
     * order below. Cold metadata keeps its existing allocation/failure order. */
    if (binding && !binding->flat.count && !heap->rc->dead.head) {
        if (region > heap->region_depth) return publication_status(heap, MYL_RC_REGION_ERROR);
        memmove(dst, src, type->size);
        return 1;
    }
    unsigned char local[128];
    void *staged = type->size <= sizeof local ? local : myl_rc_storage_bytes(heap, type->size, 0);
    if (!staged) return 0;
    int ok = myl_rc_native_retain(heap, type, staged, src, region);
    if (ok) {
        /* The old slot is inaccessible to callbacks until the new value is
         * installed. Cleanup walks only the separately staged former value. */
        if (staged == local) {
            unsigned char previous[sizeof local];
            myl_rc_copy_bytes(previous, dst, type->size);
            myl_rc_copy_bytes(dst, staged, type->size);
            myl_rc_copy_bytes(staged, previous, type->size);
        } else {
            unsigned char *left=dst, *right=staged;
            for (size_t i=0;i<type->size;i++) { unsigned char byte=left[i]; left[i]=right[i]; right[i]=byte; }
        }
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
