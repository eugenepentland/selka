#ifndef MYLANG_QBE_ARENA_H
#define MYLANG_QBE_ARENA_H
#include "native_regions.h"
#include "qbe_runtime.h"
/* Located trap for a managed reference that would outlive its arena. */
void myl_qbe_fail_arena_escape(void *context);
void myl_qbe_region_begin(void *context);
void myl_qbe_region_end(void *context);
/* Arena depth on entry to one native frame. */
uint64_t myl_qbe_region_mark(void *context);
/* Close every arena opened above a frame's entry depth, on return or while a
   trap, `?` propagation or host allocation failure unwinds through it. */
void myl_qbe_region_restore(void *context, uint64_t mark);
int myl_qbe_region_retains(void *context, const myl_native_type *type, const void *value);
int myl_qbe_region_check(void *context, const void *container, const myl_native_type *type, const void *value);
/* Zero after an exhausted allocation budget has already set the trap. */
int myl_qbe_region_escape(void *context, const myl_native_type *type, const void *value, void *output);
#endif
