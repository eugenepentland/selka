#include "native_rc_dictionary.h"
#include "native_rc_internal.h"
#include "native_regions.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

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
/* spec-case: RC-FLAT-LOAN-1. Padding is copied, duplicate leaves acquire distinct
 * H tokens, and a late limit failure preserves the generic prefix counters. */
static const myl_native_field padded_fields[]={{.offset=8,.type=&pointer},{.offset=24,.type=&pointer}};
static const myl_native_type padded={.size=32,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=padded_fields,.field_count=2};
static const myl_rc_field padded_edges[]={{.offset=8,.shape=&owned},{.offset=24,.shape=&owned}};
static const myl_rc_shape padded_shape={.size=32,.kind=MYL_RC_SHAPE_RECORD,.as.record={padded_edges,2}};
static const myl_rc_descriptor padded_descriptor={.type=&padded,.shape=&padded_shape};
static void flat_padding_and_duplicate_limit(void) {
    myl_native_heap heap; start(&heap);
    assert(myl_rc_descriptor_import(&heap,&padded_descriptor)==MYL_RC_OK);
    void *value=myl_rc_storage_bytes(&heap,8,0); assert(value);
    uint64_t source[]={UINT64_C(0x123456789abcdef), (uintptr_t)value, UINT64_C(0xfedcba987654321), (uintptr_t)value};
    uint64_t loan[4]={0};
    header(value)->holds=MYL_RC_COUNT_MAX-1;
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
    myl_rc_counters before,after; assert(myl_rc_stats_snapshot(&heap,&before));
#endif
    assert(!myl_rc_native_loan(&heap,&padded,loan,source));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    assert(header(value)->holds==MYL_RC_COUNT_MAX-1 && header(value)->owners==1);
    assert(!loan[0] && !loan[1] && !loan[2] && !loan[3]);
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
    assert(myl_rc_stats_snapshot(&heap,&after));
    assert(after.events[MYL_RC_STAT_HOLD_ACQUIRE]==before.events[MYL_RC_STAT_HOLD_ACQUIRE]+1);
    assert(after.events[MYL_RC_STAT_HOLD_RELEASE]==before.events[MYL_RC_STAT_HOLD_RELEASE]+1);
    assert(after.events[MYL_RC_STAT_HOLD_LIMIT]==before.events[MYL_RC_STAT_HOLD_LIMIT]+1);
#endif
    header(value)->holds=0;
    header(value)->common.mark|=MYL_NATIVE_OBJECT_PINNED;
    uintptr_t mark=header(value)->common.mark;
    heap.limit=heap.bytes;
    assert(myl_rc_native_loan(&heap,&padded,loan,source));
    assert(!memcmp(source,loan,sizeof source) && header(value)->holds==2 && header(value)->common.mark==mark);
    myl_rc_owner_release(&heap,value);
    myl_rc_native_unloan(&heap,&padded,loan);
    assert(!loan[0] && !loan[1] && !loan[2] && !loan[3]);
    heap.limit=0; assert(myl_native_region_begin(&heap));
    void *arena=myl_rc_storage_bytes(&heap,8,1); assert(arena);
    struct { myl_native_object common; uint64_t value; } literal={.common={.mark=MYL_NATIVE_OBJECT_IMMORTAL},.value=17};
    source[1]=(uintptr_t)arena; source[3]=(uintptr_t)&literal.value;
    uintptr_t arena_mark=((myl_native_object *)arena-1)->mark;
    assert(myl_rc_native_loan(&heap,&padded,loan,source));
    assert(!memcmp(source,loan,sizeof source) && ((myl_native_object *)arena-1)->mark==arena_mark);
    myl_rc_native_unloan(&heap,&padded,loan); myl_native_region_end(&heap); finish(&heap);
}
static void reject_loan(myl_native_heap *heap, const myl_native_type *type, void *source) {
    pid_t child=fork(); assert(child>=0);
    if (!child) {
        struct rlimit no_core={0,0}; assert(!setrlimit(RLIMIT_CORE,&no_core));
        uint64_t output[4]={0}; (void)myl_rc_native_loan(heap,type,output,source); _exit(0);
    }
    int status=0; assert(waitpid(child,&status,0)==child && WIFSIGNALED(status) && WTERMSIG(status)==SIGABRT);
}
/* spec-case: RC-FLAT-LOAN-1. NULL typed boxes still carry unique obligations;
 * opaque pointers still validate the actual terminal payload descriptor. */
static void flat_loan_unique_refusals(void) {
    static const myl_native_type resource={.size=8,.alignment=8,.kind=MYL_NATIVE_RESOURCE};
    static const myl_rc_shape none={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor body={.type=&resource,.shape=&none,.finalize=myl_rc_finalize_unique};
    static const myl_native_type box={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.collection_kind=5,.element=&resource};
    static const myl_rc_descriptor box_descriptor={.type=&box,.shape=&owned};
    myl_native_heap heap; start(&heap);
    assert(myl_rc_descriptor_import(&heap,&body)==MYL_RC_OK);
    assert(myl_rc_descriptor_import(&heap,&box_descriptor)==MYL_RC_OK);
    void *nil=NULL; reject_loan(&heap,&box,&nil); reject_loan(&heap,&resource,&nil);
    void *value=myl_native_heap_alloc(&heap,&resource,1); assert(value);
    reject_loan(&heap,&pointer,&value);
    myl_rc_owner_release(&heap,value); finish(&heap);
}
static uint64_t *flat_callback_loan;
static unsigned flat_callback_count,flat_callback_order[2];
static void flat_loan_finalizer(myl_native_heap *heap, void *payload) {
    for (size_t i=0;i<4;i++) assert(!flat_callback_loan[i]);
    assert(flat_callback_count<2); flat_callback_order[flat_callback_count++]=(unsigned)*(uint64_t *)payload;
    static const myl_native_type extra={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_shape none={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor descriptor={.type=&extra,.shape=&none};
    assert(myl_rc_descriptor_import(heap,&descriptor)==MYL_RC_OK);
    void *temporary=myl_native_heap_alloc(heap,&extra,1); assert(temporary);
    myl_rc_owner_release(heap,temporary);
}
/* spec-case: RC-FLAT-LOAN-1. Both dying siblings must be cleared/enqueued before
 * LIFO finalization, including callbacks that register and release new objects. */
static void flat_loan_sibling_callbacks(void) {
    static const myl_native_type finalized={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_shape none={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor descriptor={.type=&finalized,.shape=&none,.finalize=flat_loan_finalizer};
    myl_native_heap heap; start(&heap);
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    assert(myl_rc_descriptor_import(&heap,&padded_descriptor)==MYL_RC_OK);
    void *a=myl_native_heap_alloc(&heap,&pointer,1),*b=myl_native_heap_alloc(&heap,&pointer,1);
    assert(a && b);
    *(void **)a=myl_native_heap_alloc(&heap,&finalized,1); *(void **)b=myl_native_heap_alloc(&heap,&finalized,1);
    assert(*(void **)a && *(void **)b);
    **(uint64_t **)a=1; **(uint64_t **)b=2;
    uint64_t source[]={71,(uintptr_t)a,93,(uintptr_t)b},loan[4]={0};
    assert(myl_rc_native_loan(&heap,&padded,loan,source));
    myl_rc_owner_release(&heap,a); myl_rc_owner_release(&heap,b);
    flat_callback_loan=loan; flat_callback_count=0;
    myl_rc_native_unloan(&heap,&padded,loan);
    assert(flat_callback_count==2 && flat_callback_order[0]==2 && flat_callback_order[1]==1);
    flat_callback_loan=NULL; finish(&heap);
}
static void **flat_copy_source,**flat_copy_loan;
static void flat_copy_finalizer(myl_native_heap *heap, void *payload) {
    (void)heap; (void)payload;
    assert(flat_copy_loan[0]==flat_copy_source[0] && header(flat_copy_loan[0])->holds==1);
    flat_copy_source[0]=NULL;
}
/* spec-case: RC-FLAT-LOAN-1. Success retains dispose_walk's final drain after
 * loan acquisition, so a queued source-changing callback sees completed output. */
static void flat_loan_queued_copy(void) {
    static const myl_native_type finalized={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_shape none={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor descriptor={.type=&finalized,.shape=&none,.finalize=flat_copy_finalizer};
    myl_native_heap heap; start(&heap);
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    void *value=myl_rc_storage_bytes(&heap,8,0),*queued=myl_native_heap_alloc(&heap,&finalized,1);
    assert(value && queued); void *source=value,*loan=NULL;
    flat_copy_source=&source; flat_copy_loan=&loan;
    heap.rc->dead.active=1; myl_rc_owner_release(&heap,queued); heap.rc->dead.active=0;
    assert(myl_rc_native_loan(&heap,&pointer,&loan,&source));
    assert(!source && loan==value && !heap.rc->dead.head);
    myl_rc_owner_release(&heap,value); myl_rc_native_unloan(&heap,&pointer,&loan);
    flat_copy_source=flat_copy_loan=NULL; finish(&heap);
}
/* spec-case: RC-FLAT-LOAN-1. Deeper shapes retain transfer-frame allocation and
 * its refusal; cold metadata and empty values retain their exact output rules. */
static void flat_loan_depth_and_cold(void) {
    myl_native_heap heap; start(&heap);
    myl_native_type types[10]={0}; myl_native_field fields[9]={0};
    myl_rc_shape shapes[10]={0}; myl_rc_field edges[9]={0};
    types[9]=pointer; shapes[9]=owned;
    for (size_t i=9;i>0;i--) {
        fields[i-1]=(myl_native_field){.type=&types[i]};
        edges[i-1]=(myl_rc_field){.shape=&shapes[i]};
        types[i-1]=(myl_native_type){.size=8,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=&fields[i-1],.field_count=1};
        shapes[i-1]=(myl_rc_shape){.size=8,.kind=MYL_RC_SHAPE_RECORD,.as.record={&edges[i-1],1}};
    }
    const myl_rc_descriptor descriptor={.type=&types[0],.shape=&shapes[0]};
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    void *source=myl_rc_storage_bytes(&heap,8,0),*loan=(void *)(uintptr_t)123; assert(source);
    heap.limit=heap.bytes;
    assert(!myl_rc_native_loan(&heap,&types[0],&loan,&source));
    assert(!loan && myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED && !header(source)->holds);
    static const myl_native_type cold={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    loan=(void *)(uintptr_t)123;
    assert(!myl_rc_native_loan(&heap,&cold,&loan,&source));
    assert(!loan && myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED);
    heap.limit=0;
    assert(myl_rc_native_loan(&heap,&types[0],&loan,&source));
    myl_rc_native_unloan(&heap,&types[0],&loan); myl_rc_owner_release(&heap,source);
    static const myl_native_type empty={.alignment=1,.kind=MYL_NATIVE_PLAIN};
    uint64_t bits=71,other=93;
    assert(myl_rc_native_loan(&heap,&empty,&other,&bits) && bits==71 && other==93);
    myl_rc_native_unloan(&heap,&empty,&other); assert(other==93); finish(&heap);
}

static int binding_unique(myl_native_heap *heap, const myl_native_type *type) {
    const myl_rc_binding *binding=(const myl_rc_binding *)myl_rc_descriptor_find(heap,type);
    assert(binding);
    return myl_rc_binding_has_unique(heap,binding);
}
/* spec-case: RC-SEMANTIC-HISTORY-1. A type fact covers all variant arms and
 * native unique kinds, independently of which value happens to be active. */
static void type_facts_all_arms(void) {
    myl_native_heap heap; start(&heap);
    myl_native_type raw[]={
        {.size=8,.alignment=8,.kind=MYL_NATIVE_RESOURCE},
        {.size=8,.alignment=8,.kind=MYL_NATIVE_OWNED_BUFFER},
        {.size=8,.alignment=8,.kind=MYL_NATIVE_OWNED_POOL}};
    const myl_rc_shape none={.size=8,.kind=MYL_RC_SHAPE_NONE};
    for (size_t i=0;i<3;i++) {
        const myl_native_field fields[]={{.offset=8,.tag=0,.type=&number},{.offset=8,.tag=1,.type=&raw[i]}};
        const myl_native_type type={.size=16,.alignment=8,.kind=MYL_NATIVE_VARIANT,.fields=fields,.field_count=2};
        const myl_rc_field edges[]={{.offset=8,.tag=0,.shape=&none},{.offset=8,.tag=1,.shape=&none}};
        const myl_rc_shape shape={.size=16,.kind=MYL_RC_SHAPE_VARIANT,.as.variant={edges,2,0}};
        const myl_rc_descriptor descriptor={.type=&type,.shape=&shape};
        assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
        assert(myl_rc_native_has_unique(&heap,&type) && binding_unique(&heap,&type));
        uint64_t plain_arm[]={0,73}; reject_loan(&heap,&type,plain_arm);
        assert(binding_unique(&heap,&type));
        const myl_native_field element={.type=&raw[i]};
        const myl_native_type sequence={.size=16,.alignment=8,.kind=MYL_NATIVE_ARRAY,
            .fields=&element,.field_count=1,.element=&raw[i],.count=2,.stride=8};
        const myl_rc_shape sequence_shape={.size=16,.kind=MYL_RC_SHAPE_ARRAY,.as.array={&none,2,8}};
        const myl_rc_descriptor sequence_descriptor={.type=&sequence,.shape=&sequence_shape};
        assert(myl_rc_descriptor_import(&heap,&sequence_descriptor)==MYL_RC_OK);
        assert(binding_unique(&heap,&sequence) && binding_unique(&heap,&sequence));
        /* Each temporary native identity stays alive through its heap. */
        finish(&heap); if (i+1<3) start(&heap);
    }
}
static void type_facts_deep_generic_values(void) {
    myl_native_heap heap; start(&heap);
    myl_native_type types[12]={0}; myl_native_field fields[11]={0};
    myl_rc_shape shapes[12]={0}; myl_rc_field edges[11]={0};
    types[11]=pointer; shapes[11]=owned;
    for (size_t i=11;i>0;i--) {
        fields[i-1]=(myl_native_field){.type=&types[i]};
        edges[i-1]=(myl_rc_field){.shape=&shapes[i]};
        types[i-1]=(myl_native_type){.size=8,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=&fields[i-1],.field_count=1};
        shapes[i-1]=(myl_rc_shape){.size=8,.kind=MYL_RC_SHAPE_RECORD,.as.record={&edges[i-1],1}};
    }
    const myl_rc_descriptor descriptor={.type=&types[0],.shape=&shapes[0]};
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    size_t bytes=heap.bytes; heap.limit=bytes;
    for (unsigned i=0;i<2;i++) assert(!binding_unique(&heap,&types[0]) && heap.bytes==bytes);
    void *nil=NULL,*output=(void *)(uintptr_t)91;
    assert(!myl_rc_native_loan(&heap,&types[0],&output,&nil));
    assert(!output && myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED);
    heap.limit=0;
    assert(myl_rc_native_loan(&heap,&types[0],&output,&nil));
    myl_rc_native_unloan(&heap,&types[0],&output);
    assert(!binding_unique(&heap,&variant) && !binding_unique(&heap,&array));
    finish(&heap);
}
static void type_fact_finalizer(myl_native_heap *heap, void *payload) { (void)heap; (void)payload; }
/* The root can precede its typed-box body. Heap-local bindings of the same
 * native identities can have different finalizers, including after reinit. */
static void type_facts_late_body_and_heap_lifetime(void) {
    static const myl_native_type body={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_native_type box={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.collection_kind=5,.element=&body};
    static const myl_rc_shape none={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor box_descriptor={.type=&box,.shape=&owned};
    const myl_rc_descriptor plain={.type=&body,.shape=&none};
    const myl_rc_descriptor finalized={.type=&body,.shape=&none,.finalize=type_fact_finalizer};
    myl_native_heap a,b; start(&a); start(&b);
    assert(myl_rc_descriptor_import(&a,&box_descriptor)==MYL_RC_OK);
    void *nil=NULL; reject_loan(&a,&box,&nil);
    assert(myl_rc_descriptor_import(&a,&finalized)==MYL_RC_OK);
    assert(myl_rc_descriptor_import(&b,&box_descriptor)==MYL_RC_OK);
    assert(myl_rc_descriptor_import(&b,&plain)==MYL_RC_OK);
    for (unsigned i=0;i<2;i++) assert(binding_unique(&a,&box) && !binding_unique(&b,&box));
    reject_loan(&a,&box,&nil); finish(&a);
    start(&a); assert(myl_rc_descriptor_import(&a,&box_descriptor)==MYL_RC_OK);
    assert(myl_rc_descriptor_import(&a,&plain)==MYL_RC_OK);
    assert(!binding_unique(&a,&box)); finish(&a); finish(&b);
}
static void type_facts_keep_dynamic_payload_admission(void) {
    static const myl_native_type finalized={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_shape none={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor descriptor={.type=&finalized,.shape=&none,.finalize=type_fact_finalizer};
    myl_native_heap heap; start(&heap);
    assert(!binding_unique(&heap,&variant));
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    void *payload=myl_native_heap_alloc(&heap,&finalized,1); assert(payload);
    struct { uint64_t tag; void *value; } source={0,payload},copy={0};
    reject_loan(&heap,&variant,&source);
    assert(myl_rc_native_retain(&heap,&variant,&copy,&source,0));
    assert(copy.value==payload && header(payload)->owners==2);
    myl_rc_native_drop(&heap,&variant,&copy); myl_rc_owner_release(&heap,payload); finish(&heap);
}
static myl_native_type fact_extra_types[128];
static void type_fact_registering_finalizer(myl_native_heap *heap, void *payload) {
    (void)payload;
    const myl_rc_binding *binding=(const myl_rc_binding *)myl_rc_descriptor_find(heap,&variant);
    assert(!myl_rc_binding_has_unique(heap,binding));
    const myl_rc_shape none={.size=8,.kind=MYL_RC_SHAPE_NONE};
    const myl_rc_descriptor first={.type=&fact_extra_types[0],.shape=&none};
    size_t bytes=heap->bytes,limit=heap->limit; heap->limit=bytes;
    assert(myl_rc_descriptor_import(heap,&first)==MYL_RC_ALLOCATION_REFUSED);
    assert(heap->bytes==bytes && !myl_rc_binding_has_unique(heap,binding)); heap->limit=limit;
    for (size_t i=0;i<128;i++) {
        const myl_rc_descriptor descriptor={.type=&fact_extra_types[i],.shape=&none};
        assert(myl_rc_descriptor_import(heap,&descriptor)==MYL_RC_OK);
    }
    assert(binding==(const myl_rc_binding *)myl_rc_descriptor_find(heap,&variant));
    assert(!myl_rc_binding_has_unique(heap,binding) && !heap->rc->walk.depth);
}
static void type_facts_registration_and_idle_invariant(void) {
    static const myl_native_type final_type={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_shape none={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor descriptor={.type=&final_type,.shape=&none,.finalize=type_fact_registering_finalizer};
    for (size_t i=0;i<128;i++) fact_extra_types[i]=number;
    myl_native_heap heap; start(&heap); assert(!binding_unique(&heap,&variant));
    pid_t child=fork(); assert(child>=0);
    if (!child) {
        struct rlimit no_core={0,0}; assert(!setrlimit(RLIMIT_CORE,&no_core));
        heap.rc->walk.depth=1; (void)binding_unique(&heap,&variant); _exit(0);
    }
    int status=0; assert(waitpid(child,&status,0)==child && WIFSIGNALED(status) && WTERMSIG(status)==SIGABRT);
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    void *value=myl_native_heap_alloc(&heap,&final_type,1); assert(value);
    myl_rc_owner_release(&heap,value); assert(!binding_unique(&heap,&variant)); finish(&heap);
}

int myl_rc_loan_verify(void) {
    pinned_projection_does_not_publish(); ownerless_loan_survives(); repeated_mixed_leaves();
    late_hold_refusal_rolls_back(); array_and_variant(); arena_loan_closes_before_region(); raw_unique_type_detection();
    flat_body_survives_ownerless_loan(); held_body_loan_uses_generic_drop();
    flat_padding_and_duplicate_limit(); flat_loan_unique_refusals(); flat_loan_sibling_callbacks();
    flat_loan_queued_copy(); flat_loan_depth_and_cold();
    type_facts_all_arms(); type_facts_deep_generic_values(); type_facts_late_body_and_heap_lifetime();
    type_facts_keep_dynamic_payload_admission(); type_facts_registration_and_idle_invariant();
    return 19;
}
#ifndef MYL_RC_CONTRACT_LIBRARY
int main(void) { assert(myl_rc_loan_verify()==19); puts("native rc loans: 19 passed"); }
#endif
