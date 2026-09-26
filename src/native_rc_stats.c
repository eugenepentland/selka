#include "native_rc_internal.h"
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
void myl_rc_stats_record(const myl_native_heap *heap, myl_rc_stat_event event) {
    if (!heap || !heap->rc) return;
    myl_rc_invariant((unsigned)event < MYL_RC_STAT_COUNT);
    myl_rc_counters *stats=&heap->rc->stats;
    if (stats->events[event]==UINT64_MAX) stats->saturated=1;
    else ++stats->events[event];
}
#endif
int myl_rc_stats_snapshot(const myl_native_heap *heap, myl_rc_counters *out) {
    myl_rc_invariant(out!=NULL);
    memset(out,0,sizeof *out);
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
    if (heap && heap->rc) { *out=heap->rc->stats; return 1; }
#else
    (void)heap;
#endif
    return 0;
}
void myl_rc_stats_report(const myl_native_heap *heap) {
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
    static const char *const names[]={
        "owner_acquire","owner_release","hold_acquire","hold_release",
        "owner_limit","hold_limit","heap_allocate","arena_allocate",
        "retire","clone_shell","unique_check"
    };
    _Static_assert(sizeof names/sizeof *names==MYL_RC_STAT_COUNT,"statistics event names");
    myl_rc_counters stats;
    if (!myl_rc_stats_snapshot(heap,&stats)) return;
    fprintf(stderr,"MYLANG_RC_COUNTS {\"version\":1,\"runtime\":\"rc-v3-counting\",\"saturated\":%s",stats.saturated?"true":"false");
    for (size_t i=0;i<MYL_RC_STAT_COUNT;++i) fprintf(stderr,",\"%s\":%" PRIu64,names[i],stats.events[i]);
    fputs("}\n",stderr);
#else
    (void)heap;
#endif
}
