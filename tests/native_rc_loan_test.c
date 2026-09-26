#include "native_rc_dictionary.h"
#include "native_rc_internal.h"
#include "native_regions.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static const myl_native_type number = {.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type pointer = {.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER};
static const myl_native_field pair_fields[] = {{.type=&pointer}, {.offset=8,.type=&pointer}};
static const myl_native_type pair = {.size=16,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=pair_fields,.field_count=2};
static const myl_rc_shape owned = {.size=8,.kind=MYL_RC_SHAPE_POINTER};
static const myl_rc_shape held = {.size=8,.kind=MYL_RC_SHAPE_HOLD_POINTER};
static const myl_rc_field pair_edges[] = {{.shape=&owned}, {.offset=8,.shape=&held}};
static const myl_rc_shape pair_shape = {.size=16,.kind=MYL_RC_SHAPE_RECORD,.as.record={pair_edges,2}};
static const myl_native_field array_fields[] = {{.type=&pointer}};
static const myl_native_type array = {.size=16,.alignment=8,.kind=MYL_NATIVE_ARRAY,.fields=array_fields,.field_count=1,.count=2,.stride=8};
static const myl_rc_shape array_shape = {.size=16,.kind=MYL_RC_SHAPE_ARRAY,.as.array={&owned,2,8}};
static const myl_native_field variant_fields[] = {{.offset=8,.tag=0,.type=&pointer}, {.offset=8,.tag=1,.type=&number}};
static const myl_native_type variant = {.size=16,.alignment=8,.kind=MYL_NATIVE_VARIANT,.fields=variant_fields,.field_count=2};
static const myl_rc_field variant_edges[] = {{.offset=8,.tag=0,.shape=&owned}};
static const myl_rc_shape variant_shape = {.size=16,.kind=MYL_RC_SHAPE_VARIANT,.as.variant={variant_edges,1,0}};
static const myl_rc_descriptor descriptors[] = {{.type=&pointer,.shape=&owned}, {.type=&pair,.shape=&pair_shape},
    {.type=&array,.shape=&array_shape}, {.type=&variant,.shape=&variant_shape}};
static const myl_rc_module module = {.abi=MYL_RC_ABI_VERSION,.descriptors=descriptors,.descriptor_count=4};
static void start(myl_native_heap *heap) {
    myl_native_heap_init(heap,64u<<20);
    if (!myl_rc_enabled(heap)) assert(myl_rc_storage_init(heap)==MYL_RC_OK);
    assert(myl_rc_module_register(heap,&module)==MYL_RC_OK);
}
static void finish(myl_native_heap *heap) {
    assert(!heap->objects_live);
    myl_native_heap_destroy(heap);
    assert(!heap->bytes);
}
static myl_rc_object *header(void *p) { return (myl_rc_object *)p-1; }
// spec: RC-SEMANTIC-HISTORY-1
static void pinned_projection_does_not_publish(void) {
    myl_native_heap heap; start(&heap);
    myl_native_dictionary *mapping=myl_native_dictionary_new(&heap,&number,&number,0);
    uint64_t key=1,value=7,found=0;
    assert(mapping && myl_native_dictionary_write(&heap,mapping,&key,&value));
    myl_rc_pin pin={0}; assert(myl_rc_pin_acquire(&heap,mapping,&pin)==MYL_RC_OK);
    uintptr_t mark=header(mapping)->common.mark;
    void *loan=NULL; size_t objects=heap.objects_live;
    assert(myl_rc_native_loan(&heap,&pointer,&loan,&mapping));
    assert(loan==mapping && header(mapping)->owners==1 && header(mapping)->holds==2);
    assert(header(mapping)->common.mark==mark && heap.objects_live==objects);
    value=13; assert(myl_native_dictionary_write(&heap,mapping,&key,&value));
    assert(myl_native_dictionary_read(loan,&key,&found) && found==13);
    myl_rc_native_unloan(&heap,&pointer,&loan);
    assert(!loan && header(mapping)->holds==1 && header(mapping)->common.mark==mark);
    myl_rc_pin_release(&heap,&pin); myl_rc_owner_release(&heap,mapping); finish(&heap);
}
static void ownerless_loan_survives(void) {
    myl_native_heap heap; start(&heap);
    void *value=myl_rc_storage_bytes(&heap,8,0),*loan=NULL; assert(value);
    *(uint64_t *)value=73;
    assert(myl_rc_native_loan(&heap,&pointer,&loan,&value));
    myl_rc_owner_release(&heap,value);
    assert(header(loan)->owners==0 && header(loan)->holds==1 && *(uint64_t *)loan==73);
    heap.limit=heap.bytes; myl_rc_native_unloan(&heap,&pointer,&loan);
    assert(!loan); finish(&heap);
}
/* spec-case: RC-FLAT-SINGLE-DESTRUCTION-1. A whole-box loan protects its O
 * children until the last outer H dies; child history does not change death. */
static void flat_body_survives_ownerless_loan(void) {
    static const myl_native_type flat_pair={.size=16,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=pair_fields,.field_count=2};
    static const myl_rc_field edges[]={{.shape=&owned},{.offset=8,.shape=&owned}};
    static const myl_rc_shape shape={.size=16,.kind=MYL_RC_SHAPE_RECORD,.as.record={edges,2}};
    static const myl_rc_descriptor descriptor={.type=&flat_pair,.shape=&shape};
    myl_native_heap heap; start(&heap);
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    const myl_rc_binding *binding=(const myl_rc_binding *)myl_rc_descriptor_find(&heap,&flat_pair);
    assert(binding->flat.count==2);
    myl_native_dictionary *child=myl_native_dictionary_new(&heap,&number,&number,0);
    uint64_t key=1,value=7,found=0;
    assert(child && myl_native_dictionary_write(&heap,child,&key,&value));
    void *snapshot=NULL;
    assert(myl_rc_native_publish(&heap,&pointer,&snapshot,&child,0,MYL_RC_HISTORY_DIRECT));
    assert(snapshot==child && header(child)->owners==2 && (header(child)->common.mark&MYL_NATIVE_OBJECT_SHARED));
    myl_rc_alloc_request request={.element=&flat_pair,.count=1};
    void *box=NULL,*loan=NULL;
    assert(myl_rc_new(&heap,&request,&box)==MYL_RC_OK);
    ((void **)box)[0]=child; ((void **)box)[1]=snapshot;
    myl_rc_hold view={0}; assert(myl_rc_hold_acquire(&heap,child,&view)==MYL_RC_OK);
    assert(myl_rc_native_loan(&heap,&pointer,&loan,&box));
    myl_rc_owner_release(&heap,box);
    assert(header(loan)->owners==0 && header(loan)->holds==1 && header(child)->owners==2);
    heap.limit=heap.bytes;
    myl_rc_native_unloan(&heap,&pointer,&loan);
    assert(!loan && header(child)->owners==0 && header(child)->holds==1);
    assert(header(child)->common.mark&MYL_NATIVE_OBJECT_SHARED);
    assert(myl_native_dictionary_read(view.payload,&key,&found) && found==7);
    myl_rc_hold_release(&heap,&view); finish(&heap);
}
/* spec-case: RC-FLAT-SINGLE-DESTRUCTION-1. A mixed O/H body is never flattened
 * even when its outer object is retained only by a loan. */
static void held_body_loan_uses_generic_drop(void) {
    myl_native_heap heap; start(&heap);
    const myl_rc_binding *binding=(const myl_rc_binding *)myl_rc_descriptor_find(&heap,&pair);
    assert(binding->flat.count>MYL_RC_FLAT_LEAVES);
    void *child=myl_rc_storage_bytes(&heap,8,0),*box=NULL,*loan=NULL; assert(child);
    myl_rc_alloc_request request={.element=&pair,.count=1};
    assert(myl_rc_new(&heap,&request,&box)==MYL_RC_OK);
    myl_rc_hold child_hold={0}; assert(myl_rc_hold_acquire(&heap,child,&child_hold)==MYL_RC_OK);
    ((void **)box)[0]=child; ((void **)box)[1]=child_hold.payload;
    child_hold.payload=NULL;
    assert(myl_rc_native_loan(&heap,&pointer,&loan,&box));
    myl_rc_owner_release(&heap,box);
    assert(header(child)->owners==1 && header(child)->holds==1);
    heap.limit=heap.bytes;
    myl_rc_native_unloan(&heap,&pointer,&loan);
    assert(!loan); finish(&heap);
}
static void repeated_mixed_leaves(void) {
    myl_native_heap heap; start(&heap);
    void *value=myl_rc_storage_bytes(&heap,8,0),*source[]={value,value},*loan[2]={0}; assert(value);
    assert(myl_rc_native_loan(&heap,&pair,loan,source));
    assert(loan[0]==value && loan[1]==value && header(value)->owners==1 && header(value)->holds==2);
    myl_rc_owner_release(&heap,value); heap.limit=heap.bytes;
    myl_rc_native_unloan(&heap,&pair,loan); assert(!loan[0] && !loan[1]); finish(&heap);
}
static void late_hold_refusal_rolls_back(void) {
    myl_native_heap heap; start(&heap);
    void *a=myl_rc_storage_bytes(&heap,8,0),*b=myl_rc_storage_bytes(&heap,8,0);
    assert(a && b); void *source[]={a,b},*loan[2]={0};
    uintptr_t amark=header(a)->common.mark,bmark=header(b)->common.mark;
    header(b)->holds=MYL_RC_COUNT_MAX;
    assert(!myl_rc_native_loan(&heap,&pair,loan,source));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    assert(!loan[0] && !loan[1] && !header(a)->holds && header(b)->holds==MYL_RC_COUNT_MAX);
    assert(header(a)->owners==1 && header(b)->owners==1 && header(a)->common.mark==amark && header(b)->common.mark==bmark);
    header(b)->holds=0; assert(myl_rc_native_loan(&heap,&pair,loan,source));
    myl_rc_native_unloan(&heap,&pair,loan);
    myl_rc_owner_release(&heap,a); myl_rc_owner_release(&heap,b); finish(&heap);
}
static void array_and_variant(void) {
    myl_native_heap heap; start(&heap);
    void *value=myl_rc_storage_bytes(&heap,8,0),*source[]={value,value},*loan[2]={0}; assert(value);
    assert(myl_rc_native_loan(&heap,&array,loan,source)); assert(header(value)->holds==2);
    myl_rc_native_unloan(&heap,&array,loan); assert(!header(value)->holds);
    struct { uint64_t tag; void *value; } from={0,value},to={0};
    assert(myl_rc_native_loan(&heap,&variant,&to,&from)); assert(to.value==value && header(value)->holds==1);
    myl_rc_native_unloan(&heap,&variant,&to); assert(!to.value && !header(value)->holds);
    from.tag=1; from.value=(void *)(uintptr_t)73;
    assert(myl_rc_native_loan(&heap,&variant,&to,&from)); assert(to.tag==1 && to.value==from.value);
    myl_rc_native_unloan(&heap,&variant,&to); assert(!to.tag && !to.value);
    myl_rc_owner_release(&heap,value); finish(&heap);
}
static void arena_loan_closes_before_region(void) {
    myl_native_heap heap; start(&heap); assert(myl_native_region_begin(&heap));
    void *value=myl_rc_storage_bytes(&heap,8,1),*loan=NULL; assert(value);
    uintptr_t mark=((myl_native_object *)value-1)->mark;
    assert(myl_rc_native_loan(&heap,&pointer,&loan,&value)); assert(loan==value);
    assert(((myl_native_object *)value-1)->mark==mark);
    myl_rc_native_unloan(&heap,&pointer,&loan); assert(!loan);
    myl_native_region_end(&heap); finish(&heap);
}
static void raw_unique_type_detection(void) {
    myl_native_heap heap; start(&heap);
    const myl_native_type resource={.size=8,.alignment=8,.kind=MYL_NATIVE_RESOURCE};
    const myl_native_field field={.type=&resource};
    const myl_native_type wrapped={.size=8,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=&field,.field_count=1};
    const myl_native_type empty={.alignment=8,.kind=MYL_NATIVE_ARRAY,.fields=&field,.field_count=1,.stride=8};
    assert(myl_rc_native_has_unique(&heap,&resource)); assert(myl_rc_native_has_unique(&heap,&wrapped));
    assert(!myl_rc_native_has_unique(&heap,&empty));
    const myl_rc_shape none={.size=8,.kind=MYL_RC_SHAPE_NONE};
    const myl_rc_descriptor unique={.type=&resource,.shape=&none,.finalize=myl_rc_finalize_unique};
    assert(myl_rc_descriptor_import(&heap,&unique)==MYL_RC_OK);
    const myl_native_type box={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.collection_kind=5,.element=&resource};
    assert(myl_rc_native_has_unique(&heap,&box)); assert(!myl_rc_native_has_unique(&heap,&pair)); finish(&heap);
}
int myl_rc_loan_verify(void) {
    pinned_projection_does_not_publish(); ownerless_loan_survives(); repeated_mixed_leaves();
    late_hold_refusal_rolls_back(); array_and_variant(); arena_loan_closes_before_region(); raw_unique_type_detection();
    flat_body_survives_ownerless_loan(); held_body_loan_uses_generic_drop();
    return 9;
}
#ifndef MYL_RC_CONTRACT_LIBRARY
int main(void) { assert(myl_rc_loan_verify()==9); puts("native rc loans: 9 passed"); }
#endif
