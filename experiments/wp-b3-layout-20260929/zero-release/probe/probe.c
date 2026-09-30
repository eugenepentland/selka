#include "native_rc.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
extern uint64_t owner(void *, void **), hold(void *, void **);
typedef struct { unsigned calls; myl_rc_object *object; } Context;
static void final(Context *ctx, void **slot, int is_hold) {
    assert(*slot == ctx->object + 1);
    assert(ctx->object->owners == (is_hold ? 0 : 1));
    assert(ctx->object->holds == (is_hold ? 1 : 0));
    ++ctx->calls;
    if (is_hold) ctx->object->holds = 0;
    else ctx->object->owners = 0;
    *slot = NULL;
}
void boundary_drop(Context *ctx, void **slot) { final(ctx, slot, 0); }
void boundary_unloan(Context *ctx, void **slot) { final(ctx, slot, 1); }
int main(void) {
    const uint64_t values[] = {0,1,2,UINT32_MAX,UINT64_C(1)<<32,UINT64_C(1)<<48,UINT64_MAX-1,UINT64_MAX};
    const uint64_t others[] = {0,1,UINT64_C(1)<<32};
    unsigned cases = 0;
    for (int h=0;h<2;h++) for(unsigned i=0;i<8;i++) for(unsigned j=0;j<3;j++) {
        _Alignas(16) struct { myl_rc_object prefix; uint64_t payload; } storage;
        memset(&storage,0,sizeof(storage));
        myl_rc_object *o=&storage.prefix;
        o->common.mark=4;
        o->owners=h?others[j]:values[i]; o->holds=h?values[i]:others[j];
        Context ctx={0,o}; void *slot=o+1;
        assert((h?hold:owner)(&ctx,&slot)==0);
        const uint64_t expected=values[i]-1;
        const int last=values[i]==1 && others[j]==0;
        assert(ctx.calls==(unsigned)last);
        assert((h?o->holds:o->owners)==expected);
        assert((h?o->owners:o->holds)==others[j]);
        assert(slot==NULL); ++cases;
    }
    for (int h=0;h<2;h++) for (int kind=0;kind<3;kind++) {
        _Alignas(16) struct { myl_rc_object prefix; uint64_t payload; } storage;
        memset(&storage,0,sizeof(storage)); myl_rc_object *o=&storage.prefix;
        o->owners=5; o->holds=9;
        o->common.mark=kind==1?2:(UINT64_C(1)<<62);
        Context ctx={0,o}; void *slot=kind?o+1:NULL;
        assert((h?hold:owner)(&ctx,&slot)==0);
        assert(slot==NULL && ctx.calls==0 && o->owners==5 && o->holds==9); ++cases;
    }
    printf("release boundary probes: %u cases passed\n",cases);
    return 0;
}
