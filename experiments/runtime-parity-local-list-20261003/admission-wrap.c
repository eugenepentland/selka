#include "qbe_runtime.h"
#include <assert.h>
#include <stdio.h>
static unsigned hot,cold;
static size_t allocations,epoch;
static struct { const myl_native_type *element; size_t capacity; unsigned hot,cold; } groups[5];
static unsigned group_count;
extern int __real_myl_qbe_local_list(void *,const myl_native_type *,size_t);
int __wrap_myl_qbe_local_list(void *context,const myl_native_type *element,size_t capacity) {
    MylQbeContext *ctx=context;
    if (!hot && !cold) { allocations=ctx->heap.allocations; epoch=ctx->heap.collections; }
    assert(ctx->heap.objects_live==0);
    assert(ctx->heap.allocations==allocations+2*(hot+cold));
    assert(ctx->heap.collections==epoch+2*(hot+cold));
    int admitted=__real_myl_qbe_local_list(context,element,capacity);
    if(admitted) hot++; else cold++;
    unsigned group=0;
    while(group<group_count && (groups[group].element!=element || groups[group].capacity!=capacity)) group++;
    if(group==group_count) { assert(group_count<5); groups[group].element=element; groups[group].capacity=capacity; group_count++; }
    if(admitted) groups[group].hot++; else groups[group].cold++;
    return admitted;
}
__attribute__((destructor)) static void verify(void) {
    fprintf(stderr,"local list execution: hot=%u cold=%u\n",hot,cold);
    assert(group_count==5 && hot+cold==30);
    for(unsigned i=0;i<group_count;i++) {
        fprintf(stderr,"  size=%zu capacity=%zu hot=%u cold=%u\n",groups[i].element->size,groups[i].capacity,groups[i].hot,groups[i].cold);
        assert(groups[i].hot && groups[i].cold<=1);
    }
}
