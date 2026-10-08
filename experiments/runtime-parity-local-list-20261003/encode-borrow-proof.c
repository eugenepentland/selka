#include "native_bytes.h"
#include "native_text.h"
#include "native_rc_values.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* spec-case: MEMORY-CEILING-1. Even an immediate scalar consumer observes
 * encode's allocation refusal; borrowing the same UTF-8 storage would succeed. */
static void encode_refusal(void) {
    const size_t length=140000;
    unsigned char *source=malloc(length);
    assert(source); memset(source,'x',length);
    myl_native_heap heap;
    myl_native_heap_init(&heap,64u<<20);
    myl_native_text *text=myl_native_text_from_utf8(&heap,source,length);
    assert(text);
    myl_native_root root;
    myl_native_root_push(&heap,&root,&text,&myl_rc_pointer_leaf);
    myl_native_bytes *warm=myl_native_bytes_encode(&heap,text);
    assert(warm);
    if (myl_rc_enabled(&heap)) myl_rc_owner_release(&heap,warm);
    else myl_native_heap_collect(&heap);
    heap.limit=heap.bytes;
    const size_t before=heap.bytes;
    assert(!myl_native_bytes_encode(&heap,text) && heap.exhausted);
    const unsigned char *borrowed=myl_native_text_storage(text);
    size_t score=0;
    for(size_t i=0;i<length;i++) score+=borrowed[i];
    assert(score==length*(size_t)'x');
    printf("encode borrow witness: ordinary encode refused at %zu charged bytes; borrowed scalar score=%zu\n",before,score);
    myl_native_root_pop(&heap,&root);
    if (myl_rc_enabled(&heap)) myl_rc_owner_release(&heap,text);
    myl_native_heap_destroy(&heap); free(source);
}
/* spec-case: UTF8-TEXT-1. A retained encode owns independent bytes after the
 * non-ASCII input dies; a borrow requires a separate owner/root. */
static void retained_encode(void) {
    const unsigned char source[]="left \xc3\xa9 \xf0\x9f\x99\x82 right";
    myl_native_heap heap;
    myl_native_heap_init(&heap,64u<<20);
    myl_native_text *text=myl_native_text_from_utf8(&heap,source,sizeof source-1);
    assert(text);
    myl_native_root text_root,bytes_root;
    myl_native_root_push(&heap,&text_root,&text,&myl_rc_pointer_leaf);
    myl_native_bytes *encoded=myl_native_bytes_encode(&heap,text);
    assert(encoded && encoded->storage!=myl_native_text_storage(text));
    myl_native_root_pop(&heap,&text_root);
    myl_native_root_push(&heap,&bytes_root,&encoded,&myl_rc_pointer_leaf);
    if(myl_rc_enabled(&heap)) myl_rc_owner_release(&heap,text);
    else myl_native_heap_collect(&heap);
    for(size_t i=0;i<100;i++) {
        myl_native_text *churn=myl_native_text_from_utf8(&heap,(const unsigned char *)"overwrite retired text",22);
        assert(churn);
        if(myl_rc_enabled(&heap)) myl_rc_owner_release(&heap,churn);
        else myl_native_heap_collect(&heap);
    }
    assert(encoded->length==sizeof source-1 && !memcmp(encoded->storage,source,sizeof source-1));
    myl_native_root_pop(&heap,&bytes_root);
    if(myl_rc_enabled(&heap)) myl_rc_owner_release(&heap,encoded);
    myl_native_heap_destroy(&heap);
}
int main(void) { encode_refusal(); retained_encode(); }
