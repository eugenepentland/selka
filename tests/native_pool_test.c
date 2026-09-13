#include "native_pool.h"
#include <assert.h>
#include <stdio.h>
static const myl_native_type integer={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type owned={.size=8,.alignment=8,.kind=MYL_NATIVE_OWNED_POOL};
int main(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,SIZE_MAX);heap.stress=1;
    myl_native_pool *pool=NULL,*other=NULL;
    assert(myl_native_pool_new(&heap,&integer,2,&pool)==0);
    myl_native_root root,other_root;
    myl_native_root_push(&heap,&root,&pool,&owned);
    assert(myl_native_pool_new(&heap,&integer,2,&other)==0);
    myl_native_root_push(&heap,&other_root,&other,&owned);
    myl_native_pool_handle a,b,c;
    int64_t value=42,result=0;
    assert(myl_native_pool_insert(&heap,pool,&value,&a)==0);
    assert(myl_native_pool_read(pool,&a,&result)==0 && result==42);
    assert(myl_native_pool_read(other,&a,&result)==2);
    assert(myl_native_pool_remove(&heap,pool,&a)==0);
    assert(myl_native_pool_read(pool,&a,&result)==1);
    value=21;
    assert(myl_native_pool_insert(&heap,pool,&value,&b)==0);
    assert(a.index==b.index && b.generation==a.generation+1);
    assert(myl_native_pool_insert(&heap,pool,&value,&c)==0);
    assert(myl_native_pool_insert(&heap,pool,&value,&c)==3);
    value=84;
    assert(myl_native_pool_replace(&heap,pool,&b,&value)==0);
    assert(myl_native_pool_read(pool,&b,&result)==0 && result==84);
    myl_native_heap_collect(&heap);
    assert(myl_native_pool_read(pool,&b,&result)==0 && result==84);
    myl_native_pool_clear(&heap,pool);
    assert(pool->length==0 && myl_native_pool_read(pool,&b,&result)==1);
    myl_native_pool *rejected=NULL;
    assert(myl_native_pool_new(&heap,&integer,4097,&rejected)==1);
    myl_native_owned_drop(&heap,&owned,&other);
    myl_native_root_pop(&heap,&other_root);
    myl_native_owned_drop(&heap,&owned,&pool);
    assert(heap.pool_owners==0 && heap.pool_slots==0 && heap.bytes==0);
    myl_native_root_pop(&heap,&root);
    myl_native_heap_destroy(&heap);
    puts("native pools: generations, foreign/stale IDs, replacement, clear, GC stress passed");
}
