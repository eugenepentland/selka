#include "native_rc_collections.h"
#include "native_rc_internal.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

extern int query_from_other_tu(myl_native_heap *, const myl_native_list *);
static const myl_native_type scalar = {.size=8, .alignment=8, .kind=MYL_NATIVE_PLAIN};
static const myl_native_type wide = {.size=16, .alignment=8, .kind=MYL_NATIVE_PLAIN};
static const myl_native_type pointer = {.size=8, .alignment=8, .kind=MYL_NATIVE_POINTER};
static const myl_native_type other = {.size=4, .alignment=4, .kind=MYL_NATIVE_FLOAT};
static myl_rc_binding binding;
static const myl_native_type *registered;
static unsigned lookups;

/* Precise external slow-lookup boundary; production helper and cache are real. */
const myl_rc_binding *myl_rc_binding_find_slow(const myl_native_heap *heap, const myl_native_type *type) {
    assert(heap && heap->rc);
    ++lookups;
    return registered == type ? &binding : NULL;
}
extern void select_query(int);
int main(int argc, char **argv) {
    (void)argv;
    select_query(argc>1);
    myl_native_heap heap = {0};
    myl_rc_state state = {0};
    myl_native_list list = {.element=&scalar};
    unsigned cases=0;
    assert(!query_from_other_tu(NULL,&list)); ++cases;
    assert(!query_from_other_tu(&heap,&list)); ++cases;
    heap.rc=&state;
    assert(!query_from_other_tu(&heap,NULL)); ++cases;
    list.element=NULL;
    assert(!query_from_other_tu(&heap,&list)); ++cases;
    list.element=&scalar;
    state.plain_word=&scalar;
    assert(query_from_other_tu(&heap,&list) && !lookups); ++cases;
    state.dead.head=(myl_rc_object *)&binding;
    assert(!query_from_other_tu(&heap,&list) && !lookups); ++cases;
    state.dead.head=NULL;
    state.plain_word=NULL;
    list.element=&pointer;
    assert(!query_from_other_tu(&heap,&list) && !lookups); ++cases;
    list.element=&wide;
    assert(!query_from_other_tu(&heap,&list) && !lookups); ++cases;
    list.element=&scalar;
    myl_rc_state original=state;
    assert(!query_from_other_tu(&heap,&list) && lookups==1);
    assert(!memcmp(&original,&state,sizeof state) && !heap.bytes && !heap.allocations); ++cases;
    registered=&scalar;
    binding.flat.count=1;
    assert(!query_from_other_tu(&heap,&list) && lookups==2 && !state.plain_word && !state.plain); ++cases;
    binding.flat.count=0;binding.flat.native_unique=1;
    assert(!query_from_other_tu(&heap,&list) && lookups==3 && !state.plain_word && !state.plain); ++cases;
    binding.flat.native_unique=0;
    assert(query_from_other_tu(&heap,&list) && lookups==4 && state.plain_word==&scalar && state.plain==&scalar); ++cases;
    assert(query_from_other_tu(&heap,&list) && lookups==4); ++cases;
    state.plain_word=NULL;
    assert(query_from_other_tu(&heap,&list) && lookups==4 && state.plain_word==&scalar); ++cases;
    list.element=&other;registered=&other;
    assert(query_from_other_tu(&heap,&list) && lookups==5 && state.plain_word==&other && state.plain==&other); ++cases;
    assert(!heap.bytes && !heap.allocations);
    printf("independent callable plain query: %u cases passed\n",cases);
    return 0;
}
