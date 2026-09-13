#include "qbe_runtime.h"
#include <assert.h>
#include <string.h>
static const myl_native_type integer={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type owned={.size=8,.alignment=8,.kind=MYL_NATIVE_OWNED_BUFFER};
int main(void) {
    MylQbeContext context={0};
    myl_native_heap_init(&context.heap,SIZE_MAX);
    uint64_t outer=myl_qbe_region_begin(&context,1);
    uint64_t inner=myl_qbe_region_begin(&context,outer);
    assert(outer>=2 && inner>outer);
    assert(myl_qbe_region_reset(&context,outer)==2);
    myl_native_owned_buffer *buffer=NULL;
    assert(myl_qbe_owned_new(&context,&integer,inner,2,100,&buffer)==0);
    assert(myl_qbe_region_reset(&context,inner)==1);
    assert(myl_qbe_owned_reserve(&context,buffer,inner,4,100)==0);
    assert(myl_qbe_owned_reserve(&context,buffer,outer,8,100)==-1);
    assert(!strcmp(context.trap,"R_CAPABILITY"));
    context.trap=NULL;
    myl_qbe_region_end(&context,inner);
    assert(!strcmp(context.trap,"R_REGION_IN_USE"));
    context.trap=NULL;
    myl_native_owned_drop(&context.heap,&owned,&buffer);
    assert(myl_qbe_region_reset(&context,inner)==0);
    myl_qbe_region_end(&context,inner);
    myl_qbe_region_end(&context,outer);
    assert(!context.trap);
    assert(myl_qbe_region_reset(&context,inner)==3);
    uint64_t next=myl_qbe_region_begin(&context,1);
    assert(next>inner);
    myl_qbe_region_end(&context,next);
    for (size_t i=0;i<256;i++) assert(myl_qbe_region_begin(&context,1));
    assert(myl_qbe_region_begin(&context,1)==0 && !strcmp(context.trap,"R_REGION_LIMIT"));
    myl_native_heap_destroy(&context.heap);
}
