#include "native_dictionary.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static const myl_native_type number={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static myl_native_text *text(myl_native_heap *heap,const char *bytes) { return myl_native_text_from_utf8(heap,(const unsigned char *)bytes,strlen(bytes)); }
static void equals(myl_native_text *value,const char *bytes) {
    unsigned char buffer[128];
    size_t length=myl_native_text_utf8(value,buffer,sizeof(buffer));
    assert(length==strlen(bytes) && !memcmp(buffer,bytes,length));
}
int main(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20); heap.stress=1;
    myl_native_root roots[8];
    myl_native_text *input=text(&heap,"é🙂|x|"); assert(input && input->length==5);
    myl_native_root_push(&heap,&roots[0],&input,&pointer);
    myl_native_text *separator=text(&heap,"|"); assert(separator);
    myl_native_root_push(&heap,&roots[1],&separator,&pointer);
    myl_native_list *parts=myl_native_text_split(&heap,input,separator); assert(parts && parts->length==3);
    myl_native_root_push(&heap,&roots[2],&parts,&pointer);
    myl_native_text *joined=myl_native_text_join(&heap,separator,parts); assert(joined);
    myl_native_root_push(&heap,&roots[3],&joined,&pointer);
    assert(myl_native_text_equal(input,joined));
    equals(myl_native_text_at(&heap,input,-4),"🙂");
    equals(myl_native_text_slice(&heap,input,-99,2),"é🙂");
    assert(!myl_native_text_at(&heap,input,INT64_MIN));
    assert(!myl_native_text_from_utf8(&heap,(const unsigned char *)"\xc0\x80",2));
    assert(!myl_native_text_from_utf8(&heap,(const unsigned char *)"\xed\xa0\x80",3));
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&pointer,&number,1); assert(dict);
    myl_native_root_push(&heap,&roots[4],&dict,&pointer);
    int64_t one=1,two=2,three=3,out;
    assert(myl_native_dictionary_write(&heap,dict,&input,&one));
    assert(myl_native_dictionary_write(&heap,dict,&separator,&two));
    assert(myl_native_dictionary_write(&heap,dict,&joined,&three));
    assert(myl_native_dictionary_length(dict)==2);
    assert(myl_native_dictionary_read(dict,&input,&out) && out==3);
    myl_native_text *first;
    assert(myl_native_dictionary_key_at(dict,0,&first) && first==input);
    myl_native_list *snapshot=myl_native_dictionary_snapshot(&heap,dict,0); assert(snapshot);
    myl_native_root_push(&heap,&roots[5],&snapshot,&pointer);
    assert(myl_native_dictionary_write(&heap,dict,&input,&one));
    assert(myl_native_list_get(snapshot,0,&out) && out==3);
    myl_native_heap_collect(&heap);
    equals(first,"é🙂|x|");
    for (int i=5;i>=0;--i) assert(myl_native_root_pop(&heap,&roots[i]));
    myl_native_heap_collect(&heap); assert(heap.objects_live==0);
    myl_native_heap_destroy(&heap);
    /* Snapshot descriptors reference canonical key/value types, not the dead
       dictionary's embedded entry descriptor. */
    myl_native_heap_init(&heap,1<<20); heap.stress=1;
    dict=myl_native_dictionary_new(&heap,&number,&number,0); assert(dict);
    myl_native_root_push(&heap,&roots[0],&dict,&pointer);
    assert(myl_native_dictionary_write(&heap,dict,&one,&three));
    snapshot=myl_native_dictionary_snapshot(&heap,dict,0); assert(snapshot);
    myl_native_root_pop(&heap,&roots[0]);
    myl_native_root_push(&heap,&roots[0],&snapshot,&pointer);
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==2);
    assert(myl_native_list_get(snapshot,0,&out) && out==3);
    myl_native_heap_collect(&heap);
    assert(myl_native_list_get(snapshot,0,&out) && out==3);
    myl_native_heap_destroy(&heap);
    myl_native_heap_init(&heap,1<<20); heap.stress=1;
    dict=myl_native_dictionary_new(&heap,&pointer,&number,1); assert(dict);
    myl_native_root_push(&heap,&roots[0],&dict,&pointer);
    input=text(&heap,"retained key"); assert(input);
    assert(myl_native_dictionary_write(&heap,dict,&input,&three));
    snapshot=myl_native_dictionary_snapshot(&heap,dict,1); assert(snapshot);
    myl_native_root_pop(&heap,&roots[0]);
    myl_native_root_push(&heap,&roots[0],&snapshot,&pointer);
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==4);
    assert(myl_native_list_get(snapshot,0,&first)); equals(first,"retained key");
    myl_native_heap_collect(&heap);
    assert(myl_native_list_get(snapshot,0,&first)); equals(first,"retained key");
    myl_native_heap_destroy(&heap);
    puts("native text and dictionary tests passed");
}
