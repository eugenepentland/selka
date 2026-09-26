#include "native_rc_values.h"
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
    const myl_rc_shape *shape=myl_rc_native_shape(heap,type);
    if (!shape) return 0;
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
    const myl_rc_shape *shape=myl_rc_native_shape(heap,type);
    if (!shape) return 0;
    myl_rc_slot target={.shape=shape,.address=dst,.region=region};
    myl_rc_slot source={.shape=shape,.address=src,.region=region};
    return publication_status(heap,myl_rc_value_take(heap,&target,&source));
}
void myl_rc_native_drop(myl_native_heap *heap, const myl_native_type *type, void *value) {
    const myl_rc_descriptor *descriptor=myl_rc_descriptor_find(heap,type);
    if (!descriptor) abort();
    myl_rc_slot slot={.shape=descriptor->shape,.address=value};
    myl_rc_value_drop(heap,&slot);
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
