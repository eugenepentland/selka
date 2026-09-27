#include "native_rc_internal.h"
#include "native_rc_values.h"
#include <assert.h>
#include <string.h>
static void begin(myl_native_heap *heap){
    myl_native_heap_init(heap,1u<<20);
    assert(myl_rc_storage_init(heap)==MYL_RC_OK);
}
static void finish(myl_native_heap *heap){
    assert(!heap->objects_live);
    myl_native_heap_destroy(heap);assert(!heap->bytes);
}
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
static void physical_traffic(void){
    myl_native_heap heap;begin(&heap);
    void *value=myl_rc_storage_bytes(&heap,8,0);assert(value);
    assert(myl_rc_unique(&heap,value));
    assert(myl_rc_owner_acquire(&heap,value)==MYL_RC_OK);
    assert(!myl_rc_unique(&heap,value));
    myl_rc_hold hold={0};assert(myl_rc_hold_acquire(&heap,value,&hold)==MYL_RC_OK);
    myl_rc_owner_release(&heap,value);myl_rc_owner_release(&heap,value);
    assert(heap.objects_live==1);myl_rc_hold_release(&heap,&hold);
    myl_rc_counters counts;assert(myl_rc_stats_snapshot(&heap,&counts));
    assert(counts.events[MYL_RC_STAT_OWNER_ACQUIRE]==1 && counts.events[MYL_RC_STAT_OWNER_RELEASE]==2);
    assert(counts.events[MYL_RC_STAT_HOLD_ACQUIRE]==1 && counts.events[MYL_RC_STAT_HOLD_RELEASE]==1);
    assert(counts.events[MYL_RC_STAT_HEAP_ALLOCATE]==1 && counts.events[MYL_RC_STAT_RETIRE]==1);
    assert(counts.events[MYL_RC_STAT_UNIQUE_CHECK]==2 && !counts.saturated);
    myl_rc_stats_report(&heap);finish(&heap);
}
static void noops_and_refusals(void){
    myl_native_heap heap;begin(&heap);
    assert(myl_native_region_begin(&heap));
    void *arena=myl_rc_storage_bytes(&heap,8,1);assert(arena);
    struct {myl_native_object header;uint64_t value;} literal={.header={.mark=MYL_NATIVE_OBJECT_IMMORTAL}};
    myl_rc_counters before,after;assert(myl_rc_stats_snapshot(&heap,&before));
    assert(before.events[MYL_RC_STAT_ARENA_ALLOCATE]==1);
    assert(myl_rc_owner_acquire(&heap,NULL)==MYL_RC_OK);
    assert(myl_rc_owner_acquire(&heap,&literal.value)==MYL_RC_OK);
    assert(myl_rc_owner_acquire(&heap,arena)==MYL_RC_OK);
    myl_rc_owner_release(&heap,NULL);myl_rc_owner_release(&heap,&literal.value);myl_rc_owner_release(&heap,arena);
    myl_rc_hold hold={0};assert(myl_rc_hold_acquire(&heap,arena,&hold)==MYL_RC_OK);myl_rc_hold_release(&heap,&hold);
    assert(myl_rc_stats_snapshot(&heap,&after) && !memcmp(&before,&after,sizeof before));
    myl_native_region_end(&heap);
    void *value=myl_rc_storage_bytes(&heap,8,0);assert(value);
    myl_rc_object *object=(myl_rc_object *)value-1;object->owners=MYL_RC_COUNT_MAX;
    assert(myl_rc_owner_acquire(&heap,value)==MYL_RC_COUNT_LIMIT && object->owners==MYL_RC_COUNT_MAX);
    object->owners=1;object->holds=MYL_RC_COUNT_MAX;
    assert(myl_rc_hold_acquire(&heap,value,&hold)==MYL_RC_COUNT_LIMIT && !hold.payload);
    object->holds=0;
    assert(myl_rc_stats_snapshot(&heap,&after));
    assert(after.events[MYL_RC_STAT_OWNER_LIMIT]==1 && after.events[MYL_RC_STAT_HOLD_LIMIT]==1);
    assert(!after.events[MYL_RC_STAT_OWNER_ACQUIRE] && !after.events[MYL_RC_STAT_HOLD_ACQUIRE]);
    myl_rc_owner_release(&heap,value);finish(&heap);
}
static void pinned_snapshot(void){
    static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
    myl_native_heap heap;begin(&heap);
    void *value=myl_rc_storage_bytes(&heap,16,0);assert(value);memset(value,55,16);
    myl_rc_pin pin={0};assert(myl_rc_pin_acquire(&heap,value,&pin)==MYL_RC_OK);
    void *copy=NULL;assert(myl_rc_native_copy(&heap,&pointer,&copy,&value,0));
    assert(copy!=value && !memcmp(copy,value,16));
    myl_rc_owner_release(&heap,value);myl_rc_owner_release(&heap,copy);myl_rc_pin_release(&heap,&pin);
    myl_rc_counters counts;assert(myl_rc_stats_snapshot(&heap,&counts));
    assert(counts.events[MYL_RC_STAT_CLONE]==1 && counts.events[MYL_RC_STAT_HEAP_ALLOCATE]==2);
    assert(counts.events[MYL_RC_STAT_RETIRE]==2 && !counts.events[MYL_RC_STAT_OWNER_ACQUIRE]);
    finish(&heap);
}
static void isolation_and_saturation(void){
    myl_native_heap first,second;begin(&first);begin(&second);
    void *value=myl_rc_storage_bytes(&first,8,0);assert(value);
    first.rc->stats.events[MYL_RC_STAT_OWNER_ACQUIRE]=UINT64_MAX;
    assert(myl_rc_owner_acquire(&first,value)==MYL_RC_OK);
    assert(((myl_rc_object *)value-1)->owners==2);
    myl_rc_counters one,two,empty={0};
    assert(myl_rc_stats_snapshot(&first,&one) && myl_rc_stats_snapshot(&second,&two));
    assert(one.saturated && one.events[MYL_RC_STAT_OWNER_ACQUIRE]==UINT64_MAX);
    assert(!memcmp(&two,&empty,sizeof empty));
    myl_rc_owner_release(&first,value);myl_rc_owner_release(&first,value);finish(&first);finish(&second);
    assert(!myl_rc_stats_snapshot(&first,&one) && !memcmp(&one,&empty,sizeof empty));
}
int myl_rc_stats_verify(void){physical_traffic();noops_and_refusals();pinned_snapshot();isolation_and_saturation();return 4;}
#else
int myl_rc_stats_verify(void){
    myl_native_heap heap;begin(&heap);
    void *value=myl_rc_storage_bytes(&heap,8,0);assert(value);
    assert(myl_rc_owner_acquire(&heap,value)==MYL_RC_OK);
    myl_rc_owner_release(&heap,value);myl_rc_owner_release(&heap,value);
    myl_rc_counters counts,empty={0};memset(&counts,255,sizeof counts);
    assert(!myl_rc_stats_snapshot(&heap,&counts) && !memcmp(&counts,&empty,sizeof empty));
    myl_rc_stats_report(&heap);finish(&heap);return 1;
}
#endif
#ifndef MYL_RC_STATS_LIBRARY
int main(void){
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
    assert(myl_rc_stats_verify()==4);
#else
    assert(myl_rc_stats_verify()==1);
#endif
    return 0;
}
#endif
