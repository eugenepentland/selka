#include "native_rc_values.h"
#include <assert.h>
#include <stdio.h>
static const myl_native_type pointer={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER};
static const myl_native_type array={.size=64,.alignment=8,.kind=MYL_NATIVE_ARRAY,.element=&pointer,.count=8,.stride=8};
static const myl_rc_shape leaf={.size=8,.kind=MYL_RC_SHAPE_POINTER};
static const myl_rc_shape shape={.size=64,.kind=MYL_RC_SHAPE_ARRAY,.as.array={.element=&leaf,.count=8,.stride=8}};
static const myl_rc_descriptor descriptor={.type=&array,.shape=&shape};
int main(void) {
 myl_native_heap heap; myl_native_heap_init(&heap,1u<<20);
 assert(myl_rc_enabled(&heap) || myl_rc_storage_init(&heap)==MYL_RC_OK);
 assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
 void *payload=myl_rc_storage_bytes(&heap,8,0), *source[8],*target[8]={0};
 assert(payload);
 for(unsigned i=0;i<8;i++){source[i]=payload;assert(myl_rc_owner_acquire(&heap,payload)==MYL_RC_OK);}
 heap.limit=heap.bytes;
 unsigned long checksum=0;
 for(unsigned i=0;i<500000;i++){
  assert(myl_rc_native_copy(&heap,&array,target,source,0));
  myl_rc_native_drop(&heap,&array,target);
  checksum+=((myl_rc_object *)payload-1)->owners;
 }
 assert(checksum==4500000);
 myl_rc_native_drop(&heap,&array,source);myl_rc_owner_release(&heap,payload);
 assert(!heap.objects_live);myl_native_heap_destroy(&heap);assert(!heap.bytes);
 printf("%lu\n",checksum);
 return 0;
}
