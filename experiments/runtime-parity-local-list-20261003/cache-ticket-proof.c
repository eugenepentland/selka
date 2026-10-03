#include "native_collections.h"
#include "native_rc_alloc.h"
#include "native_rc_internal.h"
#include "native_rc_values.h"
#include "qbe_runtime.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static const myl_native_type word={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type octet={.size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type narrow={.size=2,.alignment=2,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type boolean={.size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type unit={.size=0,.alignment=1,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type pointer={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER};
static const myl_native_type wide={.size=16,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type aligned={.size=16,.alignment=16,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type unknown={.size=4,.alignment=4,.kind=MYL_NATIVE_PLAIN};
static void no_edges(myl_native_heap *heap, void *payload, size_t count) {
    (void)heap; (void)payload; (void)count;
}
static void no_cleanup(void *context) { (void)context; }
static void no_finalize(myl_native_heap *heap, void *payload) { (void)heap; (void)payload; }
static void init(myl_native_heap *heap) {
    myl_native_heap_init(heap,64u<<20);
    if (!myl_rc_enabled(heap)) assert(myl_rc_storage_init(heap)==MYL_RC_OK);
}
static myl_native_list *list_type(myl_native_heap *heap, const myl_native_type *type, size_t capacity) {
    myl_native_list *value=myl_native_list_new(heap,type,capacity);
    if (!value) return NULL;
    for (size_t i=0;i<capacity;i++) assert(myl_native_list_append(heap,value,&i));
    assert(value->length==capacity && value->generation==capacity);
    return value;
}
static myl_native_list *list(myl_native_heap *heap, size_t capacity) {
    return list_type(heap,&word,capacity);
}
static void warm(myl_native_heap *heap, size_t capacity) {
    myl_native_list *value=list(heap,capacity);
    assert(value);
    myl_rc_owner_release(heap,value);
}
static void unchanged(const myl_native_heap *heap, const myl_native_heap *before) {
    assert(heap->bytes==before->bytes && heap->objects_live==before->objects_live);
    assert(heap->allocations==before->allocations && heap->collections==before->collections);
    assert(heap->exhausted==before->exhausted && heap->scratch_failed==before->scratch_failed);
    assert(!memcmp(&heap->rc_cache,&before->rc_cache,sizeof heap->rc_cache));
}
static void unit_refusal(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_list *value=list_type(&heap,&unit,2);
    assert(value);
    myl_rc_owner_release(&heap,value);
    heap.limit=heap.bytes;
    myl_native_heap before=heap;
    assert(!myl_rc_storage_local_list(&heap,&unit,2,1));
    unchanged(&heap,&before);
    myl_native_heap_destroy(&heap);
}
#if !defined(MYL_NATIVE_RC_COUNTING) || !MYL_NATIVE_RC_COUNTING
typedef struct { myl_rc_object *first[MYL_RC_CACHE_CLASSES], *second[MYL_RC_CACHE_CLASSES], *third[MYL_RC_CACHE_CLASSES]; } positions;
static positions capture(const myl_native_heap *heap) {
    positions found={0};
    for (size_t i=0;i<MYL_RC_CACHE_CLASSES;i++) {
        found.first[i]=heap->rc_cache.free[i];
        if (found.first[i]) found.second[i]=(myl_rc_object *)found.first[i]->retired_link;
        if (found.second[i]) found.third[i]=(myl_rc_object *)found.second[i]->retired_link;
    }
    return found;
}
static void returned(const myl_native_heap *heap, const positions *before, size_t backing_bytes) {
    for (size_t i=0;i<MYL_RC_CACHE_CLASSES;i++) {
        myl_rc_object *first=before->first[i];
        /* Header and ten-word backing share a class: ordinary header-first
         * retirement swaps exactly the first two tickets, keeping the tail. */
        if (backing_bytes>64 && backing_bytes<=80 && first && ((const myl_rc_slab_class *)((uintptr_t)first&~(uintptr_t)(MYL_RC_SLAB_BYTES-1)))->stride==112) {
            myl_rc_object *second=before->second[i];
            assert(heap->rc_cache.free[i]==second && (myl_rc_object *)second->retired_link==first);
            assert((myl_rc_object *)first->retired_link==before->third[i]);
        } else assert(heap->rc_cache.free[i]==first);
    }
}
#endif
/* spec-case: RC-LOCAL-LIST-1. Admission never reserves, charges or refills;
 * same-class tickets, tight budgets, trim accumulation and saturated epochs
 * match a complete real constructor followed by its ordinary release. */
static void tickets(const myl_native_type *type, size_t capacity, size_t epoch, size_t pushed) {
    myl_native_heap original, promoted;
    init(&original); init(&promoted);
    myl_native_list *warm_original=list_type(&original,type,capacity), *warm_promoted=list_type(&promoted,type,capacity);
    assert(warm_original && warm_promoted);
    myl_rc_owner_release(&original,warm_original); myl_rc_owner_release(&promoted,warm_promoted);
    original.limit=original.bytes; promoted.limit=promoted.bytes;
    original.collections=promoted.collections=epoch;
    original.rc_cache.pushed=promoted.rc_cache.pushed=pushed;
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
    myl_native_heap before=promoted;
    myl_rc_counters counts_before,counts_after;
    assert(myl_rc_stats_snapshot(&promoted,&counts_before));
    assert(!myl_rc_storage_local_list(&promoted,type,capacity,1));
    unchanged(&promoted,&before);
    assert(myl_rc_stats_snapshot(&promoted,&counts_after));
    assert(!memcmp(&counts_before,&counts_after,sizeof counts_before));
#else
    positions original_before=capture(&original), promoted_before=capture(&promoted);
    myl_native_list *value=list_type(&original,type,capacity);
    assert(value); myl_rc_owner_release(&original,value);
    int accepted=myl_rc_storage_local_list(&promoted,type,capacity,1);
    if (!accepted) fprintf(stderr,"ticket refused size=%zu capacity=%zu\n",type->size,capacity);
    assert(accepted);
    assert(original.bytes==promoted.bytes && original.objects_live==promoted.objects_live);
    assert(original.allocations==promoted.allocations && original.collections==promoted.collections);
    assert(original.rc_cache.pushed==promoted.rc_cache.pushed);
    returned(&original,&original_before,capacity*type->size);
    returned(&promoted,&promoted_before,capacity*type->size);
    /* A later refused reservation must trim/discharge exactly the same slabs. */
    void *a=myl_rc_storage_bytes(&original,20000,0), *b=myl_rc_storage_bytes(&promoted,20000,0);
    assert((a==NULL)==(b==NULL) && original.bytes==promoted.bytes);
    if (a) { myl_rc_owner_release(&original,a); myl_rc_owner_release(&promoted,b); }
#endif
    myl_native_heap_destroy(&original); myl_native_heap_destroy(&promoted);
}
/* spec-case: RC-LOCAL-LIST-1. Every failed preflight is read-only, including
 * missing registration/cache, physical peak, pending failure and custom hooks. */
static void refusals(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_heap before=heap;
    assert(!myl_rc_storage_local_list(&heap,&word,3,1)); unchanged(&heap,&before);
    warm(&heap,3); before=heap;
    assert(!myl_rc_storage_local_list(NULL,&word,3,1));
    assert(!myl_rc_storage_local_list(&heap,NULL,3,1));
    assert(!myl_rc_storage_local_list(&heap,&word,0,1));
    assert(!myl_rc_storage_local_list(&heap,&word,17,1));
    assert(!myl_rc_storage_local_list(&heap,&word,3,0));
    assert(!myl_rc_storage_local_list(&heap,&word,3,65));
    assert(!myl_rc_storage_local_list(&heap,&word,3,64));
    assert(!myl_rc_storage_local_list(&heap,&wide,3,1));
    assert(!myl_rc_storage_local_list(&heap,&aligned,3,1));
    assert(!myl_rc_storage_local_list(&heap,&unit,2,1));
    assert(!myl_rc_storage_local_list(&heap,&unknown,3,1));
    unchanged(&heap,&before);
    assert(myl_rc_native_shape(&heap,&pointer)); before=heap;
    assert(!myl_rc_storage_local_list(&heap,&pointer,3,1)); unchanged(&heap,&before);
    heap.region_depth=1; assert(!myl_rc_storage_local_list(&heap,&word,3,1)); heap.region_depth=0;
    heap.scratch_failed=1; assert(!myl_rc_storage_local_list(&heap,&word,3,1)); heap.scratch_failed=0;
    heap.exhausted=1; assert(!myl_rc_storage_local_list(&heap,&word,3,1)); heap.exhausted=0;
    heap.rc->walk.depth=1; assert(!myl_rc_storage_local_list(&heap,&word,3,1)); heap.rc->walk.depth=0;
    heap.rc->dead.active=1; assert(!myl_rc_storage_local_list(&heap,&word,3,1)); heap.rc->dead.active=0;
    myl_rc_object dead={0};
    heap.rc->dead.head=&dead; assert(!myl_rc_storage_local_list(&heap,&word,3,1)); heap.rc->dead.head=NULL;
    heap.rc->failure=MYL_RC_COUNT_LIMIT;
    assert(!myl_rc_storage_local_list(&heap,&word,3,1)); heap.rc->failure=MYL_RC_OK;
    heap.rc->lists=0; assert(!myl_rc_storage_local_list(&heap,&word,3,1)); heap.rc->lists=1;
    myl_rc_allocator hooks=heap.rc->allocator.hooks;
    heap.rc->allocator.hooks.allocate=NULL;
    assert(!myl_rc_storage_local_list(&heap,&word,3,1)); heap.rc->allocator.hooks=hooks;
    heap.rc->allocator.hooks.retire=NULL;
    assert(!myl_rc_storage_local_list(&heap,&word,3,1)); heap.rc->allocator.hooks=hooks;
    heap.rc->allocator.hooks.destroy=NULL;
    assert(!myl_rc_storage_local_list(&heap,&word,3,1)); heap.rc->allocator.hooks=hooks;
    heap.rc->allocator.hooks.teardown=NULL;
    assert(!myl_rc_storage_local_list(&heap,&word,3,1)); heap.rc->allocator.hooks=hooks;
    unchanged(&heap,&before);
    const myl_rc_shape plain={.size=4,.kind=MYL_RC_SHAPE_NONE};
    const myl_rc_descriptor edges={.type=&unknown,.shape=&plain,.edges=no_edges};
    assert(myl_rc_descriptor_import(&heap,&edges)==MYL_RC_OK);
    before=heap; assert(!myl_rc_storage_local_list(&heap,&unknown,3,1)); unchanged(&heap,&before);
    static const myl_native_type finalized={.size=4,.alignment=4,.kind=MYL_NATIVE_PLAIN};
    const myl_rc_descriptor finalize={.type=&finalized,.shape=&plain,.finalize=no_finalize};
    assert(myl_rc_descriptor_import(&heap,&finalize)==MYL_RC_OK);
    before=heap; assert(!myl_rc_storage_local_list(&heap,&finalized,3,1)); unchanged(&heap,&before);
    myl_native_heap_destroy(&heap);
}
/* spec-case: RC-LOCAL-LIST-1. A pending id plan and every context observer
 * refuse without mutating allocator or registration state. */
static void context_refusals(void) {
    MylQbeContext ctx={0};
    init(&ctx.heap); warm(&ctx.heap,3);
    myl_native_heap before=ctx.heap;
    assert(!myl_qbe_local_list(NULL,&word,3));
    ctx.trap="fixture"; assert(!myl_qbe_local_list(&ctx,&word,3)); ctx.trap=NULL;
    ctx.cleanup=no_cleanup; assert(!myl_qbe_local_list(&ctx,&word,3)); ctx.cleanup=NULL;
    ctx.adapter_cleanup=no_cleanup; assert(!myl_qbe_local_list(&ctx,&word,3)); ctx.adapter_cleanup=NULL;
    ctx.stand_in_cleanup=no_cleanup; assert(!myl_qbe_local_list(&ctx,&word,3)); ctx.stand_in_cleanup=NULL;
    ctx.resource_live[0]=1; assert(!myl_qbe_local_list(&ctx,&word,3)); ctx.resource_live[0]=0;
    ctx.resource_live[1]=1; assert(!myl_qbe_local_list(&ctx,&word,3)); ctx.resource_live[1]=0;
    ctx.heap.stress=1; assert(!myl_qbe_local_list(&ctx,&word,3)); ctx.heap.stress=0;
    myl_rc_scope scope={0};
    ctx.heap.rc->scopes=&scope; assert(!myl_qbe_local_list(&ctx,&word,3)); ctx.heap.rc->scopes=NULL;
    unchanged(&ctx.heap,&before);
    myl_native_list *live=list(&ctx.heap,3); assert(live); before=ctx.heap;
    assert(!myl_qbe_local_list(&ctx,&word,3)); unchanged(&ctx.heap,&before);
    myl_rc_owner_release(&ctx.heap,live);
    static const myl_native_type pending={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN,.rc_id=16};
    const myl_rc_shape plain={.size=8,.kind=MYL_RC_SHAPE_NONE};
    const myl_rc_descriptor descriptor={.type=&pending,.shape=&plain};
    assert(myl_rc_descriptor_import(&ctx.heap,&descriptor)==MYL_RC_OK);
    myl_rc_map_entry entry=ctx.heap.rc->metadata.ids.entries[16];
    assert(!entry.key && entry.value); before=ctx.heap;
    assert(!myl_rc_storage_local_list(&ctx.heap,&pending,3,1)); unchanged(&ctx.heap,&before);
    assert(!memcmp(&entry,&ctx.heap.rc->metadata.ids.entries[16],sizeof entry));
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
    assert(!myl_qbe_local_list(&ctx,&word,3));
#else
    /* A dormant provider table is never invoked without a resource/cleanup. */
    ctx.providers=(const struct MylangNativeProvidersTag *)&ctx;
    assert(myl_qbe_local_list(&ctx,&word,3)); ctx.providers=NULL;
#endif
    myl_native_heap_destroy(&ctx.heap);
}
/* spec-case: MEMORY-CEILING-1. A bare byte-peak or independently admitted
 * second literal is unsound: early first-list retirement lets reserve() trim
 * its slab. The production certificate rejects every second constructor. */
static void overlapping_refusal_witness(void) {
#if !defined(MYL_NATIVE_RC_COUNTING) || !MYL_NATIVE_RC_COUNTING
    myl_native_heap original, unsound;
    init(&original); init(&unsound);
    warm(&original,3); warm(&unsound,3);
    original.limit=original.bytes; unsound.limit=unsound.bytes;
    myl_native_list *first=list(&original,3);
    assert(first && myl_rc_storage_local_list(&unsound,&word,3,1));
    assert(!list(&original,16) && original.exhausted);
    myl_native_list *second=list(&unsound,16);
    assert(second); /* This is the counterexample, not an admitted program. */
    myl_rc_owner_release(&original,first); myl_rc_owner_release(&unsound,second);
    myl_native_heap_destroy(&original); myl_native_heap_destroy(&unsound);
#endif
}
int main(void) {
    tickets(&word,1,0,0); tickets(&word,3,0,0); tickets(&word,10,0,0);
    tickets(&word,3,SIZE_MAX-1,SIZE_MAX-100);
    tickets(&octet,2,0,0); tickets(&narrow,2,0,0); tickets(&boolean,2,0,0);
    refusals(); context_refusals(); unit_refusal(); overlapping_refusal_witness();
    puts("local list tickets: cold refusal, tight-budget admission, same-class order, accounting, trim and overlap witnesses passed");
}
