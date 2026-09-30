/* Independent boundary oracle for extracted production release/publication IL.
 * Synthetic prefixes isolate the changed emitted branches; no source-level
 * ownership validity is claimed for zero-count compatibility cases. */
#include "native_rc.h"
#include "symbols.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern int review_owner(void *, void *, void **);
extern int review_hold(void *, void *, void **);
extern int review_publish(void *, void *, void **, void **, unsigned, unsigned);
typedef struct {
    myl_rc_object *object;
    unsigned final_calls, slow_calls, failure;
    uint64_t old_owners, old_holds;
    uintptr_t old_mark;
    void *original;
} Context;

static void final(Context *c, void **slot, int hold) {
    assert(*slot == c->original);
    assert(c->object->owners == (hold ? 0 : 1));
    assert(c->object->holds == (hold ? 1 : 0));
    ++c->final_calls;
    if (hold) c->object->holds = 0;
    else c->object->owners = 0;
    *slot = NULL;
}
void final_owner(Context *, void **) __asm__(OWNER_SYMBOL);
void final_owner(Context *c, void **slot) { final(c, slot, 0); }
void final_hold(Context *, void **) __asm__(HOLD_SYMBOL);
void final_hold(Context *c, void **slot) { final(c, slot, 1); }
int slow_publish(Context *, void **, void **, unsigned, unsigned) __asm__(PUBLISH_SYMBOL);
int slow_publish(Context *c, void **dst, void **src, unsigned region, unsigned mode) {
    (void)region; (void)mode;
    assert(!*dst && *src == c->original);
    assert(c->object->owners == c->old_owners && c->object->holds == c->old_holds);
    assert(c->object->common.mark == c->old_mark);
    ++c->slow_calls;
    return 0;
}
myl_rc_status myl_rc_take_failure(myl_native_heap *heap) { (void)heap; return MYL_RC_COUNT_LIMIT; }
int myl_qbe_rc_status(Context *c, unsigned status) { c->failure = status; return 0; }

static unsigned release_cases(void) {
    const uint64_t counts[] = {0, 1, 2, UINT32_MAX, UINT64_C(1)<<32,
        UINT64_C(1)<<48, UINT64_C(1)<<63, (UINT64_C(1)<<32)+1,
        (UINT64_C(1)<<48)+1, (UINT64_C(1)<<63)+1, UINT64_MAX-1, UINT64_MAX};
    const uint64_t others[] = {0, 1, UINT64_C(1)<<32, UINT64_C(1)<<63, UINT64_MAX};
    unsigned cases = 0;
    for (unsigned hold=0; hold<2; ++hold) {
        for (unsigned i=0; i<sizeof counts/sizeof *counts; ++i) {
            for (unsigned j=0; j<sizeof others/sizeof *others; ++j) {
                struct { myl_rc_object prefix; uint64_t body; } block = {0};
                myl_rc_object *o = &block.prefix;
                o->owners = hold ? others[j] : counts[i];
                o->holds = hold ? counts[i] : others[j];
                void *slot = o+1;
                Context c = {.object=o, .original=slot};
                assert((hold ? review_hold : review_owner)(&c, &c, &slot));
                assert(!slot);
                assert((hold ? o->holds : o->owners) == counts[i]-1);
                assert((hold ? o->owners : o->holds) == others[j]);
                assert(c.final_calls == (unsigned)(counts[i]==1 && others[j]==0));
                assert(!o->common.mark);
                ++cases;
            }
        }
        for (unsigned special=0; special<3; ++special) {
            struct { myl_rc_object prefix; uint64_t body; } block = {0};
            myl_rc_object *o = &block.prefix;
            o->owners=7; o->holds=UINT64_C(1)<<32;
            o->common.mark = special==1 ? MYL_NATIVE_OBJECT_IMMORTAL : MYL_NATIVE_OBJECT_ARENA;
            void *slot = special ? o+1 : NULL;
            Context c = {.object=o, .original=slot};
            assert((hold ? review_hold : review_owner)(&c, &c, &slot));
            assert(!slot && !c.final_calls && o->owners==7 && o->holds==(UINT64_C(1)<<32));
            ++cases;
        }
    }
    return cases;
}

static unsigned publish_cases(void) {
    const unsigned modes[] = {0,1,2,3,4,5,6,7,0x80000000u,0x80000004u,0x100u,0x104u};
    const uint64_t counts[] = {1,UINT64_C(1)<<32,UINT64_MAX-1,UINT64_MAX};
    const uintptr_t marks[] = {0,MYL_NATIVE_OBJECT_SHARED,MYL_NATIVE_OBJECT_PINNED,
        MYL_NATIVE_OBJECT_ARENA,MYL_NATIVE_OBJECT_IMMORTAL,0};
    unsigned cases=0;
    for (unsigned state=0; state<6; ++state) {
        for (unsigned i=0; i<sizeof counts/sizeof *counts; ++i) {
            for (unsigned j=0; j<sizeof modes/sizeof *modes; ++j) {
                struct { myl_rc_object prefix; uint64_t body; } block = {0};
                myl_rc_object *o=&block.prefix;
                o->owners=counts[i]; o->holds=UINT64_C(1)<<48; o->common.mark=marks[state];
                void *src=state==5 ? NULL : o+1, *dst=NULL;
                Context c={.object=o,.old_owners=o->owners,.old_holds=o->holds,
                    .old_mark=o->common.mark,.original=src};
                const int take=(modes[j]&4)!=0;
                const int slow=(modes[j]&3)!=0 || (src &&
                    ((marks[state]&(MYL_NATIVE_OBJECT_PINNED|MYL_NATIVE_OBJECT_ARENA)) ||
                     (!take && !(marks[state]&MYL_NATIVE_OBJECT_IMMORTAL) && counts[i]==UINT64_MAX)));
                assert(review_publish(&c,&c,&dst,&src,0,modes[j]) == !slow);
                assert(c.slow_calls == (unsigned)slow);
                if (slow) {
                    assert(!dst && src==c.original && c.failure==MYL_RC_COUNT_LIMIT);
                    assert(o->owners==c.old_owners && o->holds==c.old_holds && o->common.mark==c.old_mark);
                } else {
                    assert(dst==c.original && src==(take ? NULL : c.original));
                    assert(o->owners==c.old_owners+(c.original && !take && !(marks[state]&MYL_NATIVE_OBJECT_IMMORTAL)));
                    assert(o->holds==c.old_holds && !c.failure);
                    assert(o->common.mark==(c.old_mark | (c.original && !(marks[state]&MYL_NATIVE_OBJECT_IMMORTAL) ? MYL_NATIVE_OBJECT_SHARED : 0)));
                }
                ++cases;
            }
        }
    }
    return cases;
}
int main(void) {
    const unsigned release=release_cases(), publish=publish_cases();
    printf("independent release/publication: %u release, %u publication cases passed\n",release,publish);
    return 0;
}
