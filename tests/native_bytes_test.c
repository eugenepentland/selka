#include "native_bytes.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static myl_native_bytes *raw(myl_native_heap *heap,const char *text) {
    return myl_native_bytes_new(heap,(const unsigned char *)text,strlen(text));
}
static void equals(myl_native_bytes *value,const char *text) {
    assert(value && value->length==strlen(text));
    assert(!value->length || !memcmp(value->storage,text,value->length));
}
/* spec-case: BUFFER-GROWTH-1. Octet writes stay correct across every doubling
   of a buffer's backing, including the doublings the allocator serves by
   extending the block's own reservation rather than by copying it. A backing
   drawn from a size class is a slot shared with its class, so the allocator
   refuses to resize it; once a backing is big enough to own a segment whole,
   the growth keeps the octets already written, keeps the object's element count
   and traced size exact, and leaves the extended block alive across a
   collection. */
static void growth_keeps_octets(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,256u<<20);
    myl_native_bytes *buffer=myl_native_bytes_new(&heap,(const unsigned char *)"",0);
    assert(buffer);
    myl_native_root root;
    myl_native_root_push(&heap,&root,&buffer,&pointer);
    assert(myl_native_bytes_buffer_append_byte(&heap,buffer,'a')==MYL_BYTES_WROTE);
    assert(!myl_native_heap_extend(&heap,buffer->storage,buffer->capacity+1));
    const unsigned char *octets=(const unsigned char *)buffer->storage;
    size_t written=1;
    size_t grown=0;
    for (int step=0;step<40;++step) {
        size_t before=buffer->capacity;
        for (int i=0;i<8000;++i) {
            assert(myl_native_bytes_buffer_append_byte(&heap,buffer,(int64_t)(written%251))==MYL_BYTES_WROTE);
            written++;
        }
        if (buffer->capacity!=before) grown++;
        octets=(const unsigned char *)buffer->storage;
        assert(octets[0]=='a');
        assert(octets[1]==1);
        assert(buffer->length==written);
    }
    assert(grown>=4 && buffer->capacity>(256u<<10));
    assert(myl_native_object_element(&heap,buffer->storage)==buffer->element);
    for (size_t i=1;i<written;++i) assert(octets[i]==(i%251));
    myl_native_heap_collect(&heap);
    assert(buffer->length==written && octets[written-1]==((written-1)%251));
    myl_native_root_pop(&heap,&root);
    myl_native_heap_destroy(&heap);
}
int main(void) {
    growth_keeps_octets();
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20); heap.stress=1;
    myl_native_root roots[8];
    myl_native_bytes *input=raw(&heap,"a,b,"); assert(input);
    myl_native_root_push(&heap,&roots[0],&input,&pointer);
    myl_native_bytes *separator=raw(&heap,","); assert(separator);
    myl_native_root_push(&heap,&roots[1],&separator,&pointer);
    myl_native_list *parts=myl_native_bytes_split(&heap,input,separator);
    assert(parts && parts->length==3);
    myl_native_root_push(&heap,&roots[2],&parts,&pointer);
    myl_native_bytes *joined=myl_native_bytes_join(&heap,separator,parts);
    myl_native_root_push(&heap,&roots[3],&joined,&pointer);
    equals(joined,"a,b,");
    /* Clamped Python endpoints, including a reversed and an out-of-range range. */
    equals(myl_native_bytes_slice(&heap,input,-99,99),"a,b,");
    equals(myl_native_bytes_slice(&heap,input,2,1),"");
    equals(myl_native_bytes_slice(&heap,input,-2,INT64_MAX),"b,");
    assert(myl_native_bytes_find(input,separator)==1);
    assert(myl_native_bytes_find(input,raw(&heap,"zz"))==-1);
    assert(myl_native_bytes_find(input,raw(&heap,""))==0);
    assert(myl_native_bytes_starts_with(input,raw(&heap,"a,")));
    assert(myl_native_bytes_ends_with(input,separator));
    assert(!myl_native_bytes_ends_with(input,raw(&heap,"a,b,c")));
    assert(myl_native_bytes_has_byte(input,'a') && !myl_native_bytes_has_byte(input,300));
    assert(!myl_native_bytes_has_byte(input,-1));
    assert(!myl_native_bytes_split(&heap,input,raw(&heap,"")));
    myl_native_list *octets=myl_native_bytes_to_list(&heap,input);
    assert(octets && octets->length==4);
    myl_native_root_push(&heap,&roots[4],&octets,&pointer);
    int status=MYL_BYTES_OK;
    equals(myl_native_bytes_from_list(&heap,octets,&status),"a,b,");
    assert(status==MYL_BYTES_OK);
    int64_t *values=octets->storage;
    values[0]=256;
    assert(!myl_native_bytes_from_list(&heap,octets,&status) && status==MYL_BYTES_RANGE);
    values[0]=-1;
    assert(!myl_native_bytes_from_list(&heap,octets,&status) && status==MYL_BYTES_RANGE);
    values[0]='a';
    myl_native_text *hex=myl_native_bytes_hex(&heap,input);
    assert(hex && hex->length==8);
    myl_native_root_push(&heap,&roots[5],&hex,&pointer);
    myl_native_bytes *back=myl_native_bytes_from_hex(&heap,hex,&status);
    assert(status==MYL_BYTES_OK);
    equals(back,"a,b,");
    myl_native_text *odd=myl_native_text_from_utf8(&heap,(const unsigned char *)"0f0",3);
    assert(!myl_native_bytes_from_hex(&heap,odd,&status) && status==MYL_BYTES_INVALID);
    myl_native_text *bad=myl_native_text_from_utf8(&heap,(const unsigned char *)"0g",2);
    assert(!myl_native_bytes_from_hex(&heap,bad,&status) && status==MYL_BYTES_INVALID);
    myl_native_bytes *invalid=myl_native_bytes_new(&heap,(const unsigned char *)"\xff",1);
    assert(!myl_native_bytes_decode(&heap,invalid,&status) && status==MYL_BYTES_INVALID);
    myl_native_bytes *utf8=myl_native_bytes_new(&heap,(const unsigned char *)"h\xc3\xa9",3);
    myl_native_root_push(&heap,&roots[6],&utf8,&pointer);
    myl_native_text *decoded=myl_native_bytes_decode(&heap,utf8,&status);
    assert(status==MYL_BYTES_OK && decoded && decoded->length==2);
    myl_native_root_push(&heap,&roots[7],&decoded,&pointer);
    equals(myl_native_bytes_encode(&heap,decoded),"h\xc3\xa9");
    equals(myl_native_bytes_concat(&heap,input,separator),"a,b,,");
    equals(myl_native_bytes_new(&heap,(const unsigned char *)"",0),"");
    myl_native_heap_collect(&heap);
    equals(input,"a,b,");
    for (int i=7;i>=0;--i) assert(myl_native_root_pop(&heap,&roots[i]));
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==0);
    myl_native_heap_destroy(&heap);
    puts("native byte string tests passed");
    return 0;
}
