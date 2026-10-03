#include "qbe_runtime.h"
#include <assert.h>
#include <stdio.h>
static unsigned hot,cold;
extern int __real_myl_qbe_local_list(void *,const myl_native_type *,size_t);
int __wrap_myl_qbe_local_list(void *context,const myl_native_type *element,size_t capacity) {
    assert(element->size==8 && capacity==3);
    int admitted=__real_myl_qbe_local_list(context,element,capacity);
    if(admitted) hot++; else cold++;
    return admitted;
}
__attribute__((destructor)) static void verify(void) {
    fprintf(stderr,"eligible list execution: hot=%u cold=%u\n",hot,cold);
    assert(hot>0 && cold<=1);
}
