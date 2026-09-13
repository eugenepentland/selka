#include "native_owned.h"
#include <assert.h>
#include <stdio.h>
static const myl_native_type integer={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type owned={.size=8,.alignment=8,.kind=MYL_NATIVE_OWNED_BUFFER};
int main(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,SIZE_MAX);
    heap.stress=1;
    myl_native_owned_buffer *outer=NULL,*child=NULL;
    assert(myl_native_owned_new(&heap,&owned,2,100,&outer)==0);
    myl_native_root root;
    myl_native_root_push(&heap,&root,&outer,&owned);
    for (int64_t i=1;i<=3;i++) {
        assert(myl_native_owned_new(&heap,&integer,1,100,&child)==0);
        int64_t value=i;
        assert(myl_native_owned_append(&heap,child,&value)==0);
        assert(myl_native_owned_append(&heap,outer,&child)==(i==3?2:0));
        assert(!child);
    }
    assert(heap.owned_capacity==4);
    assert(myl_native_owned_reserve(&heap,outer,4,100)==0);
    assert(heap.owned_capacity==6);
    assert(myl_native_owned_take(outer,0,&child)==0);
    int64_t value=0;
    assert(myl_native_list_get(child,0,&value) && value==1);
    myl_native_owned_drop(&heap,&owned,&child);
    assert(!child && heap.owned_capacity==5);
    assert(myl_native_owned_truncate(&heap,outer,2)==3);
    assert(myl_native_owned_truncate(&heap,outer,0)==0);
    assert(heap.owned_capacity==4);
    size_t before=heap.bytes;
    heap.limit=before;
    assert(myl_native_owned_reserve(&heap,outer,8,100)==-1);
    assert(outer->capacity==4 && heap.owned_capacity==4);
    heap.limit=SIZE_MAX;
    assert(myl_native_owned_new(&heap,&integer,-1,100,&child)==1);
    assert(myl_native_owned_new(&heap,&integer,101,100,&child)==1);
    assert(myl_native_owned_new(&heap,&integer,1,100,&child)==0);
    value=42;
    assert(myl_native_owned_append(&heap,child,&value)==0);
    assert(myl_native_owned_set(&heap,outer,0,&child)==3);
    assert(!child && heap.owned_capacity==4);
    myl_native_owned_drop(&heap,&owned,&outer);
    assert(!outer && heap.owned_capacity==0);
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==0 && heap.bytes==0);
    heap.stress=0;
    for (size_t i=0;i<20000;i++) {
        myl_native_owned_buffer *parent=NULL;
        assert(myl_native_owned_new(&heap,&owned,1,30000,&parent)==0);
        assert(myl_native_owned_append(&heap,parent,&outer)==0);
        outer=parent;
    }
    heap.limit=0; /* Destruction must not allocate and must not recurse per owner. */
    myl_native_owned_drop(&heap,&owned,&outer);
    assert(!outer && heap.owned_capacity==0 && heap.bytes==0);
    myl_native_root_pop(&heap,&root);
    myl_native_heap_destroy(&heap);
    puts("native owned buffers: consumption, nested drop, reserve failure, quotas, stress passed");
}
