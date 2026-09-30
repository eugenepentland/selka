#include "native_rc_internal.h"
#include <inttypes.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#if defined(MYL_NATIVE_RC_SITES) && MYL_NATIVE_RC_SITES
_Static_assert(offsetof(myl_rc_site, calls) == 0, "generated code bumps a site's first word");
myl_rc_site *myl_rc_site_current;
static myl_rc_site runtime_site = {.pc = MYL_RC_SITE_ENTRY, .operation = "runtime", .type = ""};
const char *const myl_rc_site_event_names[MYL_RC_SITE_EVENT_COUNT] = {
    "owner_acquire","owner_release","hold_acquire","hold_release",
    "owner_limit","hold_limit","heap_allocate","arena_allocate",
    "retire","clone_shell","unique_check",
    "scope_begin","scope_end","scope_hold","scope_pin","scope_prepare",
    "frame_enter","frame_leave","slot_drop","unique_slow"
};
myl_rc_site *myl_rc_site_runtime(void) { return &runtime_site; }
void myl_rc_site_record(unsigned event) {
    myl_rc_site_record_many(event, 1);
}
void myl_rc_site_record_many(unsigned event, uint64_t count) {
    myl_rc_invariant(event < MYL_RC_SITE_EVENT_COUNT);
    myl_rc_site *site = myl_rc_site_current ? myl_rc_site_current : &runtime_site;
    site->events[event] = count > UINT64_MAX - site->events[event] ? UINT64_MAX : site->events[event] + count;
}
#endif
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
void myl_rc_stats_record(const myl_native_heap *heap, myl_rc_stat_event event) {
    if (!heap || !heap->rc) return;
    myl_rc_invariant((unsigned)event < MYL_RC_STAT_COUNT);
    myl_rc_counters *stats=&heap->rc->stats;
    if (stats->events[event]==UINT64_MAX) stats->saturated=1;
    else ++stats->events[event];
    MYL_RC_SITE(event);
}
void myl_rc_stats_record_many(const myl_native_heap *heap, myl_rc_stat_event event, uint64_t count) {
    if (!heap || !heap->rc) return;
    myl_rc_invariant((unsigned)event < MYL_RC_STAT_COUNT);
    myl_rc_counters *stats=&heap->rc->stats;
    if (count>UINT64_MAX-stats->events[event]) { stats->events[event]=UINT64_MAX; stats->saturated=1; }
    else stats->events[event]+=count;
    MYL_RC_SITE_MANY(event,count);
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
#if defined(MYL_NATIVE_RC_SITES) && MYL_NATIVE_RC_SITES
#define MYL_RC_STATS_RUNTIME "rc-v5-sites"
#else
#define MYL_RC_STATS_RUNTIME "rc-v5-counting"
#endif
    fprintf(stderr,"MYLANG_RC_COUNTS {\"version\":1,\"runtime\":\"" MYL_RC_STATS_RUNTIME "\",\"saturated\":%s",stats.saturated?"true":"false");
    for (size_t i=0;i<MYL_RC_STAT_COUNT;++i) fprintf(stderr,",\"%s\":%" PRIu64,names[i],stats.events[i]);
    fputs("}\n",stderr);
#else
    (void)heap;
#endif
}
