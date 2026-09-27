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
#define MYL_RC_STAT(heap,event) myl_rc_stats_record((heap),(event))
#define MYL_RC_STAT_WHEN(heap,event,condition) do { if (condition) MYL_RC_STAT(heap,event); } while (0)
#else
/* Disabled artifacts have neither counter storage nor event calls/branches. */
#define MYL_RC_STAT(heap,event) ((void)0)
#define MYL_RC_STAT_WHEN(heap,event,condition) ((void)0)
#endif
/* RC-SITES-1: a sites build (a counting build compiled with
 * MYL_NATIVE_RC_SITES) also attributes every event to the emitted call site
 * that caused it. Before each direct runtime or glue call the generated code
 * bumps that site's `calls` word and stores the site in myl_rc_site_current;
 * every MYL_RC_STAT event and the sites-only journal events below then land
 * in that site's counters. Events outside any site (startup, teardown) land
 * in the runtime pseudo-site. The compiler's build driver defines each site
 * record and the myl_rc_site_table the exit report walks. */
#if defined(MYL_NATIVE_RC_SITES) && MYL_NATIVE_RC_SITES
typedef enum {
    MYL_RC_SITE_SCOPE_BEGIN = MYL_RC_STAT_COUNT, MYL_RC_SITE_SCOPE_END,
    MYL_RC_SITE_SCOPE_HOLD, MYL_RC_SITE_SCOPE_PIN, MYL_RC_SITE_SCOPE_PREPARE,
    MYL_RC_SITE_FRAME_ENTER, MYL_RC_SITE_FRAME_LEAVE, MYL_RC_SITE_SLOT_DROP,
    MYL_RC_SITE_UNIQUE_SLOW,
    MYL_RC_SITE_EVENT_COUNT
} myl_rc_site_event;
/* A pc naming the function's prologue or its shared exit instead of an instruction. */
#define MYL_RC_SITE_ENTRY (UINT64_MAX - 1)
#define MYL_RC_SITE_EXIT UINT64_MAX
typedef struct myl_rc_site {
    uint64_t calls; /* offset 0: the generated code increments it in place */
    const void *function; /* the emitting function's MylQbeFunction record */
    uint64_t pc;
    const char *operation, *type;
    uint64_t events[MYL_RC_SITE_EVENT_COUNT];
} myl_rc_site;
extern myl_rc_site *myl_rc_site_current;
void myl_rc_site_record(unsigned event);
/* The pseudo-site that owns events recorded while no site is current. */
myl_rc_site *myl_rc_site_runtime(void);
extern const char *const myl_rc_site_event_names[MYL_RC_SITE_EVENT_COUNT];
#define MYL_RC_SITE(event) myl_rc_site_record(event)
#else
#define MYL_RC_SITE(event) ((void)0)
#endif
/* Disabled or non-RC heaps return zero and an all-zero snapshot. */
int myl_rc_stats_snapshot(const myl_native_heap *, myl_rc_counters *);
/* Emit one versioned MYLANG_RC_COUNTS JSON record to stderr. The execution
 * adapter calls this after cleanup and before heap destruction, even on its
 * standalone fast-exit path. Disabled/non-RC heaps emit nothing. */
void myl_rc_stats_report(const myl_native_heap *);
#endif
