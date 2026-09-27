#ifndef MYLANG_NATIVE_RC_STATS_H
#define MYLANG_NATIVE_RC_STATS_H
#include "native_heap.h"
/* Events count successful physical operations, not null/immortal/arena owner
 * no-ops. Initial O=1 is an allocation, not an owner-acquire event. Refused
 * count increments have separate events. Counters saturate diagnostically. */
typedef enum {
    MYL_RC_STAT_OWNER_ACQUIRE, MYL_RC_STAT_OWNER_RELEASE,
    MYL_RC_STAT_HOLD_ACQUIRE, MYL_RC_STAT_HOLD_RELEASE,
    MYL_RC_STAT_OWNER_LIMIT, MYL_RC_STAT_HOLD_LIMIT,
    MYL_RC_STAT_HEAP_ALLOCATE, MYL_RC_STAT_ARENA_ALLOCATE,
    MYL_RC_STAT_RETIRE, MYL_RC_STAT_CLONE, MYL_RC_STAT_UNIQUE_CHECK,
    MYL_RC_STAT_COUNT
} myl_rc_stat_event;
typedef struct {
    uint64_t events[MYL_RC_STAT_COUNT];
    unsigned saturated;
} myl_rc_counters;
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
void myl_rc_stats_record(const myl_native_heap *, myl_rc_stat_event);
/* Record `count` events at once (trap teardown's bulk retire and release). */
void myl_rc_stats_record_many(const myl_native_heap *, myl_rc_stat_event, uint64_t count);
#define MYL_RC_STAT(heap,event) myl_rc_stats_record((heap),(event))
#define MYL_RC_STAT_MANY(heap,event,count) myl_rc_stats_record_many((heap),(event),(count))
#define MYL_RC_STAT_WHEN(heap,event,condition) do { if (condition) MYL_RC_STAT(heap,event); } while (0)
#else
/* Disabled artifacts have neither counter storage nor event calls/branches. */
#define MYL_RC_STAT(heap,event) ((void)0)
#define MYL_RC_STAT_MANY(heap,event,count) ((void)0)
#define MYL_RC_STAT_WHEN(heap,event,condition) ((void)0)
#endif
/* Disabled or non-RC heaps return zero and an all-zero snapshot. */
int myl_rc_stats_snapshot(const myl_native_heap *, myl_rc_counters *);
/* Emit one versioned MYLANG_RC_COUNTS JSON record to stderr. The execution
 * adapter calls this after cleanup and before heap destruction, even on its
 * standalone fast-exit path. Disabled/non-RC heaps emit nothing. */
void myl_rc_stats_report(const myl_native_heap *);
#endif
