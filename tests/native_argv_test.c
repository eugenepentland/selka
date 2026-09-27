/* Real argv construction: transfer fresh texts, roll back before longjmp. */
#include "qbe_runtime.h"
#include "native_collections.h"
#include "native_text.h"
#include "native_rc_alloc.h"
#include "native_rc_internal.h"
#include <assert.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static const myl_native_type text_pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=2};
typedef struct {
    myl_rc_status (*allocate)(myl_native_heap *,const myl_rc_alloc_request *,void **);
    unsigned calls,refuse,append_refuse;
    myl_native_list *list;
} AllocationProbe;
static AllocationProbe *probe;
static myl_rc_status allocate(myl_native_heap *heap,const myl_rc_alloc_request *request,void **out) {
    unsigned call=++probe->calls;
    if (call==probe->refuse) { *out=NULL; return MYL_RC_ALLOCATION_REFUSED; }
    myl_rc_status status=probe->allocate(heap,request,out);
    if (status==MYL_RC_OK && call==1) probe->list=*out;
    /* The argv constructor reserves its whole backing up front; append has
     * no ordinary allocation site. Inject its generation-limit refusal after
     * one stored text, exercising the same real helper's rollback branch. */
    if (status==MYL_RC_OK && call==probe->append_refuse) probe->list->generation=UINT64_MAX;
    return status;
}
static void balanced(MylQbeContext *ctx) {
    myl_rc_counters counts;
    assert(myl_rc_stats_snapshot(&ctx->heap,&counts));
    assert(!counts.saturated && ctx->heap.objects_live==0);
    assert(counts.events[MYL_RC_STAT_HEAP_ALLOCATE]==counts.events[MYL_RC_STAT_RETIRE]);
    assert(counts.events[MYL_RC_STAT_HEAP_ALLOCATE]+counts.events[MYL_RC_STAT_OWNER_ACQUIRE]==counts.events[MYL_RC_STAT_OWNER_RELEASE]);
    assert(counts.events[MYL_RC_STAT_HOLD_ACQUIRE]==counts.events[MYL_RC_STAT_HOLD_RELEASE]);
}
static void scenario(unsigned count,unsigned refused,int append_refused,int jumping) {
    MylQbeContext *ctx=calloc(1,sizeof *ctx);assert(ctx);
    AllocationProbe *state=calloc(1,sizeof *state);assert(state);
    myl_native_heap_init(&ctx->heap,8u<<20);
    if (!myl_rc_enabled(&ctx->heap)) assert(myl_rc_storage_init(&ctx->heap)==MYL_RC_OK);
    char *arguments[257];
    for (size_t i=0;i<257;++i) arguments[i]=(char *)(i%2?"héllo":"argument");
    ctx->guest_argc=(int)count;ctx->guest_argv=arguments;
    state->allocate=ctx->heap.rc->allocator.hooks.allocate;
    state->refuse=refused;state->append_refuse=append_refused?4:0;
    probe=state;ctx->heap.rc->allocator.hooks.allocate=allocate;
    void *owner=NULL;uint32_t initialized=1;
    MylQbeRcSlot slot={&text_pointer,&owner,&initialized,MYL_QBE_RC_CONSTRUCTION};
    jmp_buf unwind;
    if (jumping) ctx->unwind=&unwind;
    if (!setjmp(unwind)) {
        myl_native_list *list=myl_qbe_argv_list(ctx,&text_pointer);
        owner=list;
        assert(!jumping || !(refused || append_refused));
        if (refused || append_refused) assert(!list && ctx->trap);
        else {
            assert(list && !ctx->trap && list->length==count);
            for (size_t i=0;i<count;++i) {
                myl_native_text *text=((myl_native_text **)list->storage)[i];
                assert(text->bytes==strlen(arguments[i]));
                assert(!memcmp(text+1,arguments[i],text->bytes));
                assert(((myl_rc_object *)text-1)->owners==1);
            }
        }
        myl_qbe_rc_slot_drop(ctx,&slot);
    } else assert(jumping && (refused || append_refused) && ctx->trap);
    ctx->unwind=NULL;
    assert(!ctx->heap.roots);
    /* A trap is released by heap teardown, exactly as an execution does. */
    myl_qbe_rc_finish(ctx);
    if (refused) assert(state->calls==refused);
    if (append_refused) assert(state->calls==4);
    ctx->heap.rc->allocator.hooks.allocate=state->allocate;probe=NULL;
    balanced(ctx);
    myl_native_heap_destroy(&ctx->heap);assert(!ctx->heap.bytes);
    free(state);free(ctx);
}
int myl_native_argv_verify(void) {
    scenario(0,0,0,0);scenario(1,0,0,0);scenario(257,0,0,0);
    for (unsigned refused=1;refused<=5;++refused) {
        scenario(3,refused,0,0);scenario(3,refused,0,1);
    }
    scenario(3,0,1,0);scenario(3,0,1,1);
    return 15;
}
#ifndef MYL_NATIVE_ARGV_LIBRARY
int main(void) { assert(myl_native_argv_verify()==15); puts("native argv: 15 passed"); return 0; }
#endif
